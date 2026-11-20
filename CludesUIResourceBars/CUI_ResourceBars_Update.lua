if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_ResourceBars_Update.lua
--
--  The update functions of the health, power and class resource bars, the
--  spender tracking, the Ironfur and Ignore Pain bars, visibility and the
--  tickers.
--  Reads the earlier Resource Bars files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._internals
-- CludesUIResourceBars.lua or an earlier Resource Bars file failed to load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local ceil, min, max = math.ceil, math.min, math.max
local format = string.format
local UnitHealth, UnitHealthMax, UnitPower = UnitHealth, UnitHealthMax, UnitPower
local UnitPowerMax, UnitClass = UnitPowerMax, UnitClass

local CLASS_COLORS, EBON_MIGHT_DURATION = Inner.CLASS_COLORS, Inner.EBON_MIGHT_DURATION
local EBON_MIGHT_SPELL_ID, ERB, FRENZIED_REGEN = Inner.EBON_MIGHT_SPELL_ID, Inner.ERB, Inner.FRENZIED_REGEN
local GetIcicleCount, GetPrimaryPowerType = Inner.GetIcicleCount, Inner.GetPrimaryPowerType
local GetSpecialization, GUARDIAN_OF_ELUNE, IP = Inner.GetSpecialization, Inner.GUARDIAN_OF_ELUNE, Inner.IP
local IRONFUR_GOE_BONUS, IRONFUR_GOE_WINDOW = Inner.IRONFUR_GOE_BONUS, Inner.IRONFUR_GOE_WINDOW
local IRONFUR_SPELL, IronfurBaseDuration = Inner.IRONFUR_SPELL, Inner.IronfurBaseDuration
local ironfurTicks, MANGLE_SPELL, POWER_COLORS = Inner.ironfurTicks, Inner.MANGLE_SPELL, Inner.POWER_COLORS
local PT, FindCountBand, GetBarBandCurve = Inner.PT, Inner.FindCountBand, Inner.GetBarBandCurve
local GetBarThresholdCurve, ResolveBandConfig = Inner.GetBarThresholdCurve, Inner.ResolveBandConfig
local ResolveThresholdSpecEntry, ApplyBarFlat = Inner.ResolveThresholdSpecEntry, Inner.ApplyBarFlat
local ApplyBarGradient, CalcPipGeometry = Inner.ApplyBarGradient, Inner.CalcPipGeometry
local PipTextureHelpers = Inner.PipTextureHelpers
local IsPowerBarHidden, IsSpecDisabled, pips = Inner.IsPowerBarHidden, Inner.IsSpecDisabled, Inner.pips
local runeFrames, secondaryBarTicks = Inner.runeFrames, Inner.secondaryBarTicks
local ApplyResourceBarTicks = Inner.ApplyResourceBarTicks
local EnsureIronfurOverlay, ironfurTickTex = Inner.EnsureIronfurOverlay, Inner.ironfurTickTex
local SetCachedPrimary = Inner.SetCachedPrimary

local ironfurBaseDur = 7
Inner.ironfurBaseDurSetters[#Inner.ironfurBaseDurSetters + 1] = function(v)
    ironfurBaseDur = v
end
local ironfurGoEUntil = 0
Inner.ironfurGoEUntilSetters[#Inner.ironfurGoEUntilSetters + 1] = function(v)
    ironfurGoEUntil = v
end
local mainFrame
Inner.mainFrameSetters[#Inner.mainFrameSetters + 1] = function(v)
    mainFrame = v
end
local health
Inner.healthBarSetters[#Inner.healthBarSetters + 1] = function(v)
    health = v
end
local mainBar
Inner.primaryBarSetters[#Inner.primaryBarSetters + 1] = function(v)
    mainBar = v
end
local classFrame
Inner.secondaryFrameSetters[#Inner.secondaryFrameSetters + 1] = function(v)
    classFrame = v
end
local classBar
Inner.secondaryBarSetters[#Inner.secondaryBarSetters + 1] = function(v)
    classBar = v
end
local castBarFrame
Inner.castBarFrameSetters[#Inner.castBarFrameSetters + 1] = function(v)
    castBarFrame = v
end
local gcdBarFrame
Inner.gcdBarFrameSetters[#Inner.gcdBarFrameSetters + 1] = function(v)
    gcdBarFrame = v
end
local isInCombat = false
Inner.isInCombatSetters[#Inner.isInCombatSetters + 1] = function(v)
    isInCombat = v
end
local cachedClass
Inner.cachedClassSetters[#Inner.cachedClassSetters + 1] = function(v)
    cachedClass = v
end
local cachedPrimary
Inner.cachedPrimarySetters[#Inner.cachedPrimarySetters + 1] = function(v)
    cachedPrimary = v
end
local cachedSecondary
Inner.cachedSecondarySetters[#Inner.cachedSecondarySetters + 1] = function(v)
    cachedSecondary = v
end
local _ebonMightExpiry = 0
Inner.ebonMightExpirySetters[#Inner.ebonMightExpirySetters + 1] = function(v)
    _ebonMightExpiry = v
end
local UpdateCastBar
Inner.UpdateCastBarSetters[#Inner.UpdateCastBarSetters + 1] = function(v)
    UpdateCastBar = v
end
local UpdateGCDBar
Inner.UpdateGCDBarSetters[#Inner.UpdateGCDBarSetters + 1] = function(v)
    UpdateGCDBar = v
end

-- Update functions (event-driven)
-- WoW Forever: no health/power number under 10,000 abbreviates
-- (CludesUI_NumberFormat.lua). On ns, not a local:
-- the druid mana bar file reads it too.
mod.AbbreviateNumbers = (CludesUI.IS_FOREVER and CludesUI.ForeverAbbreviateNumbers) or AbbreviateNumbers
-- Health text: the global Number Format for valueType (power text keeps the
-- default above). On ns for the options preview.
mod.AbbreviateValue = CludesUI.AbbreviateValue
CludesUI.RegisterNumberFormatCallback(function()
    Inner.UpdateHealthBar()
end)
local function UpdateHealthBar()
    if not health or not health:IsShown() then
        return
    end
    local healthCfg = _G._CURB_ResolveHealthCfg()

    local current = UnitHealth("player")
    local mx = UnitHealthMax("player")
    if not current or not mx then
        return
    end
    if not (issecretvalue and issecretvalue(mx)) and mx <= 0 then
        return
    end

    health:SetMinMaxValues(0, mx)

    local curTainted = issecretvalue and issecretvalue(current)
    -- Percent for text display. UnitHealthPercent may return a secret, but
    -- string.format handles secrets natively (C function): store as-is and only
    -- pass to format/SetFormattedText, NEVER arithmetic.
    local pctRaw
    if UnitHealthPercent then
        pctRaw = UnitHealthPercent("player", true, CurveConstants and CurveConstants.ScaleTo100)
    elseif not curTainted and mx > 0 then
        pctRaw = current / mx * 100
    else
        pctRaw = 0
    end

    -- Color: threshold via ColorCurve (same as the power bar), from the
    -- per-spec threshold entry.
    local _hpTsEntry = ResolveThresholdSpecEntry(healthCfg)
    local _hpTsEnabled = _hpTsEntry and (_hpTsEntry.thresholdEnabled ~= false) or false
    local _hpBandOn, _hpBands, _hpBandMode, _hpBandRev = ResolveBandConfig(healthCfg, _hpTsEntry)
    if not _hpTsEnabled then
        _hpTsEntry = nil
    end
    local fillTex = health:GetStatusBarTexture()
    local _hpTextInstead = _hpTsEntry and _hpTsEntry.thresholdTextInstead and healthCfg.textFormat ~= "none"
    if (_hpTsEntry or _hpBandOn) and fillTex and UnitHealthPercent then
        local colorCurve
        local baseR, baseG, baseB
        if healthCfg.customColored then
            baseR, baseG, baseB = healthCfg.fillR, healthCfg.fillG, healthCfg.fillB
        else
            local classColor = CLASS_COLORS[cachedClass]
            if classColor then
                baseR, baseG, baseB = classColor[1], classColor[2], classColor[3]
            else
                baseR, baseG, baseB = 0.15, 0.75, 0.30
            end
        end
        local _bandOn, _bands, _bandMode, _bandRev = _hpBandOn, _hpBands, _hpBandMode, _hpBandRev
        -- Recolor text instead of bar
        if _hpTextInstead then
            local tbR, tbG, tbB
            if healthCfg.textCustomColored == false then
                local tcc = CLASS_COLORS[cachedClass]
                if tcc then
                    tbR, tbG, tbB = tcc[1], tcc[2], tcc[3]
                else
                    tbR, tbG, tbB = 1, 1, 1
                end
            else
                tbR, tbG, tbB = healthCfg.textFillR or 1, healthCfg.textFillG or 1, healthCfg.textFillB or 1
            end
            if _bandOn then
                colorCurve = GetBarBandCurve("health", _bands, _bandMode, mx, tbR, tbG, tbB, _bandRev)
            else
                local tR = _hpTsEntry.thresholdR or healthCfg.thresholdR or 1
                local tG = _hpTsEntry.thresholdG or healthCfg.thresholdG or 0.2
                local tB = _hpTsEntry.thresholdB or healthCfg.thresholdB or 0.2
                colorCurve = GetBarThresholdCurve(
                    tbR,
                    tbG,
                    tbB,
                    tR,
                    tG,
                    tB,
                    _hpTsEntry.thresholdPct or healthCfg.thresholdPct or 30
                )
            end
            if colorCurve and health._text then
                local success, colorResult = pcall(UnitHealthPercent, "player", false, colorCurve)
                if success and colorResult and colorResult.GetRGBA then
                    health._text:SetTextColor(colorResult:GetRGBA())
                end
            end
            -- Fill stays at base color.
            if healthCfg.gradientEnabled then
                ApplyBarGradient(
                    fillTex,
                    healthCfg.gradientDir or "HORIZONTAL",
                    baseR,
                    baseG,
                    baseB,
                    1,
                    healthCfg.gradientR,
                    healthCfg.gradientG,
                    healthCfg.gradientB,
                    healthCfg.gradientA
                )
            else
                ApplyBarFlat(fillTex, baseR, baseG, baseB, 1)
            end
        else
            if _bandOn then
                colorCurve = GetBarBandCurve("health", _bands, _bandMode, mx, baseR, baseG, baseB, _bandRev)
            else
                local tR = _hpTsEntry.thresholdR or healthCfg.thresholdR or 1
                local tG = _hpTsEntry.thresholdG or healthCfg.thresholdG or 0.2
                local tB = _hpTsEntry.thresholdB or healthCfg.thresholdB or 0.2
                colorCurve = GetBarThresholdCurve(
                    baseR,
                    baseG,
                    baseB,
                    tR,
                    tG,
                    tB,
                    _hpTsEntry.thresholdPct or healthCfg.thresholdPct or 30
                )
            end
            if colorCurve then
                local success, colorResult = pcall(UnitHealthPercent, "player", false, colorCurve)
                if success and colorResult and colorResult.GetRGBA then
                    fillTex:SetVertexColor(colorResult:GetRGBA())
                end
            end
        end
    elseif fillTex and not healthCfg.customColored then
        local red, green, blue
        local classColor = CLASS_COLORS[cachedClass]
        if classColor then
            red, green, blue = classColor[1], classColor[2], classColor[3]
        else
            red, green, blue = 0.15, 0.75, 0.30
        end
        if healthCfg.gradientEnabled then
            ApplyBarGradient(
                fillTex,
                healthCfg.gradientDir or "HORIZONTAL",
                red,
                green,
                blue,
                1,
                healthCfg.gradientR,
                healthCfg.gradientG,
                healthCfg.gradientB,
                healthCfg.gradientA
            )
        else
            ApplyBarFlat(fillTex, red, green, blue, 1)
        end
    end

    -- Fill: the bar's Smooth Bars item decides whether the engine eases toward
    -- the new value (CreateStatusBar's SetValue wrapper), at zero per-frame Lua.
    health:SetValue(current)

    if healthCfg.textFormat ~= "none" and not _G._CURB_TextHiddenByForm(healthCfg) then
        local formatStr = healthCfg.textFormat
        local pctStr = format("%d", pctRaw)
        local curStr = mod.AbbreviateValue(current, "health")
        local txt
        if formatStr == "both" then
            txt = curStr .. " | " .. pctStr .. "%"
        elseif formatStr == "curhpshort" then
            txt = curStr
        elseif formatStr == "curmaxhp" then
            txt = curStr .. " / " .. mod.AbbreviateValue(mx, "maxHealth")
        elseif formatStr == "perhp" then
            txt = pctStr .. "%"
        elseif formatStr == "perhpnosign" then
            txt = pctStr
        elseif formatStr == "perhpnum" then
            txt = pctStr .. "% | " .. curStr
        else
            txt = pctStr .. "%"
        end
        health._text:SetText(txt)
        health._text:Show()
    else
        health._text:Hide()
    end
end

local function UpdatePrimaryBar()
    if not mainBar or not mainBar:IsShown() then
        return
    end
    -- Config resolution cache: ResolvePowerCfg/ResolveThresholdSpecEntry/
    -- ResolveBandConfig walk profile tables and only change on a profile edit,
    -- spec swap or form change, but power events fire a dozen times/sec while
    -- casting -- and this pair sat above the "is threshold colouring even on"
    -- branch, so it ran in full for users with the feature off. Resolve once per
    -- config generation (bumped by ApplyAll).
    local powerColor = mod.PPC
    if not powerColor or powerColor.gen ~= mod.CfgGen then
        if not powerColor then
            powerColor = {}
            mod.PPC = powerColor
        end
        powerColor.gen = mod.CfgGen
        powerColor.pp = _G._CURB_ResolvePowerCfg()
        local e = ResolveThresholdSpecEntry(powerColor.pp)
        -- ResolveBandConfig must see the RAW entry, not the enabled-gated one.
        powerColor.bandOn, powerColor.bands, powerColor.bandMode, powerColor.bandRev = ResolveBandConfig(powerColor.pp, e)
        powerColor.tsEntry = (e and (e.thresholdEnabled ~= false)) and e or nil
        -- Primary power type is spec/form/profile state; every path that can
        -- change it funnels through BuildBars, which bumps CfgGen.
        powerColor.primary = GetPrimaryPowerType()
        -- WoW Forever mana regen spark: whether this bar shows mana moves
        -- only with the primary power type, so it is reported from here.
        if CludesUI.ManaRegenSpark and powerColor.pp.manaRegenSpark then
            CludesUI.ManaRegenSpark.SetMana("erb", powerColor.primary == PT.MANA)
        end
    end
    local primaryCfg = powerColor.pp

    if cachedPrimary ~= powerColor.primary then
        SetCachedPrimary(powerColor.primary)
    end
    if not cachedPrimary then
        return
    end
    -- Park the engine-slot overlay when the primary is no longer Ebon Might.
    if mod.EMB121_Gate then
        mod.EMB121_Gate(cachedPrimary == "EBON_MIGHT")
    end

    -- Ebon Might: aura-based countdown, not a standard power type. The OnUpdate
    -- ticker does the smooth frame-by-frame updates; this path runs on UNIT_AURA
    -- to pick up buff gain/loss/refresh.
    if cachedPrimary == "EBON_MIGHT" then
        if mod.EMB121_Owns then
            -- The engine slot (CUI_ResourceBars_EbonMight121.lua) renders fill and
            -- text -- secrecy makes the numeric path below impossible in combat.
            -- Legacy stays empty underneath; Sync attaches/builds the overlay with
            -- the live bar and settings.
            if mod.EMB121_Sync then
                mod.EMB121_Sync(mainBar, primaryCfg, POWER_COLORS["EBON_MIGHT"])
            end
            mainBar:SetMinMaxValues(0, EBON_MIGHT_DURATION)
            mainBar:SetValue(0)
            if mod.EMB121_TextOk and mod.EMB121_TextOk() then
                mainBar._text:Hide()
                return
            end
            -- Engine text isn't confirmed live yet (build still queued, or its
            -- one-shot FontString attempt failed and won't retry this session)
            -- -- fall through and render the legacy numeric text below instead
            -- of leaving the bar permanently blank.
        end
        local aura = C_UnitAuras.GetPlayerAuraBySpellID(EBON_MIGHT_SPELL_ID)
        -- Ebon Might is secret-flagged: under aura restriction the query returns
        -- nil or carries secret fields, and a secret expirationTime would error in
        -- the numeric chain below. Degrade to an empty bar.
        if aura and issecretvalue(aura.expirationTime) then
            aura = nil
        end
        _ebonMightExpiry = (aura and aura.expirationTime) or 0
        local remaining = (_ebonMightExpiry > 0) and max(0, _ebonMightExpiry - GetTime()) or 0
        if not mod.EMB121_Owns then
            mainBar:SetMinMaxValues(0, EBON_MIGHT_DURATION)
            mainBar:SetValue(remaining)
            -- Color: custom > power color (same priority as standard)
            local fillTex = mainBar:GetStatusBarTexture()
            if not primaryCfg.customColored then
                local powerColor = POWER_COLORS["EBON_MIGHT"]
                local red, green, blue = 1, 1, 1
                if powerColor then
                    red, green, blue = powerColor[1], powerColor[2], powerColor[3]
                end
                if primaryCfg.gradientEnabled then
                    ApplyBarGradient(
                        fillTex,
                        primaryCfg.gradientDir or "HORIZONTAL",
                        red,
                        green,
                        blue,
                        1,
                        primaryCfg.gradientR,
                        primaryCfg.gradientG,
                        primaryCfg.gradientB,
                        primaryCfg.gradientA
                    )
                else
                    ApplyBarFlat(fillTex, red, green, blue, 1)
                end
            end
        end
        if primaryCfg.textFormat and primaryCfg.textFormat ~= "none" then
            local formatStr = primaryCfg.textFormat
            local percentSuffix = (primaryCfg.showPercent == false) and "" or "%"
            local pct = format("%d", remaining / EBON_MIGHT_DURATION * 100)
            local timeText = remaining > 0 and format("%.1f", remaining) or "0"
            local txt
            if formatStr == "perpp" then
                txt = pct .. percentSuffix
            elseif formatStr == "both" then
                txt = timeText .. " | " .. pct .. percentSuffix
            else
                txt = timeText
            end
            mainBar._text:SetText(txt)
            mainBar._text:Show()
        else
            mainBar._text:Hide()
        end
        return
    end

    local current = UnitPower("player", cachedPrimary)
    local mx = UnitPowerMax("player", cachedPrimary)
    if not mx or mx <= 0 then
        return
    end
    -- Some custom power types (e.g. Devourer Fury) can transiently report a
    -- negative value from the server between spend and the next power sync.
    -- The StatusBar widget itself clamps the *fill* to [0, mx] automatically,
    -- but nothing was clamping the raw number handed to the text formatters
    -- below, so "smart"/"curpp"/"both" text could show a negative number
    -- while the bar visually read empty. Floor it once here, and use the
    -- clamped value everywhere after this point (fill + text) so both stay
    -- consistent. issecretvalue()'d numbers can't be compared, so skip the
    -- floor for those (SetValue's own clamp still protects the fill).
    if not (issecretvalue and issecretvalue(current)) and current < 0 then
        current = 0
    end

    mainBar:SetMinMaxValues(0, mx)

    local pctRaw = UnitPowerPercent
            and UnitPowerPercent("player", cachedPrimary, true, CurveConstants and CurveConstants.ScaleTo100)
        or 0
    local pctTainted = issecretvalue and issecretvalue(pctRaw)
    local pct01 = (not pctTainted) and (pctRaw / 100) or 1

    -- Both allocating stages below (the curve color read returns a color object,
    -- the formatters build strings) are stamped on the value pair, so a repaint
    -- that finds the same value re-derives nothing. A secret value cannot be
    -- compared, so it always rebuilds and drops the stamps (the next clean event
    -- rebuilds too).
    local vmClean = not (issecretvalue and (issecretvalue(current) or issecretvalue(mx)))
    if not vmClean then
        mainBar._colCur = nil
        mainBar._txtCur = nil
    end

    -- Color: threshold via ColorCurve (secret-safe) for non-mana specs. The
    -- per-spec entry was resolved once per config generation above; pc.tsEntry is
    -- already nil when thresholds are disabled.
    local _ppTsEntry = powerColor.tsEntry
    local _ppTsEnabled = _ppTsEntry ~= nil
    local _ppBandOn, _ppBands, _ppBandMode, _ppBandRev = powerColor.bandOn, powerColor.bands, powerColor.bandMode, powerColor.bandRev
    local fillTex = mainBar:GetStatusBarTexture()
    local _ppTextInstead = _ppTsEntry and _ppTsEntry.thresholdTextInstead and primaryCfg.textFormat ~= "none"
    -- A castable tracked spender outranks threshold and band coloring; Recolor
    -- Text Instead sends it to the text.
    local spOn = mod.PowTracks()
    local spR, spG, spB, spA, spW
    if spOn then
        spR, spG, spB, spA, spW = mod.PowSpenderColor()
    end
    local spText = spOn and mod.PTK.entry.thresholdTextInstead and primaryCfg.textFormat ~= "none"
    if not spR and mainBar._ovW then
        if mainBar._ovTI then
            if primaryCfg.textCustomColored == false then
                local tpc = POWER_COLORS[cachedPrimary]
                if tpc then
                    mainBar._text:SetTextColor(tpc[1], tpc[2], tpc[3], 1)
                else
                    mainBar._text:SetTextColor(1, 1, 1, 1)
                end
            else
                mainBar._text:SetTextColor(
                    primaryCfg.textFillR or 1,
                    primaryCfg.textFillG or 1,
                    primaryCfg.textFillB or 1,
                    primaryCfg.textFillA or 1
                )
            end
        end
        mainBar._ovW, mainBar._ovGen, mainBar._ovTI = nil, nil, nil
        mainBar._colCur, mainBar._colGen = nil, nil
    end
    if spR then
        if
            not (mainBar._ovW == spW and mainBar._ovGen == mod.CfgGen and mainBar._ovTI == spText)
        then
            mainBar._ovW, mainBar._ovGen, mainBar._ovTI = spW, mod.CfgGen, spText
            mainBar._colCur, mainBar._colGen = nil, nil
            if spText then
                mainBar._text:SetTextColor(spR, spG, spB, spA or 1)
            elseif fillTex then
                -- The curve paints raw, so the flat memo may be stale.
                fillTex._lfOn = nil
                ApplyBarFlat(fillTex, spR, spG, spB, spA or 1)
            end
        end
    elseif (_ppTsEntry or _ppBandOn) and fillTex and UnitPowerPercent then
        local colorCurve
        local baseR, baseG, baseB
        if primaryCfg.customColored then
            baseR, baseG, baseB = primaryCfg.fillR, primaryCfg.fillG, primaryCfg.fillB
        else
            local powerColor = POWER_COLORS[cachedPrimary]
            if powerColor then
                baseR, baseG, baseB = powerColor[1], powerColor[2], powerColor[3]
            else
                baseR, baseG, baseB = 1, 1, 1
            end
        end
        local _bandOn, _bands, _bandMode, _bandRev = _ppBandOn, _ppBands, _ppBandMode, _ppBandRev
        local rvR, rvG, rvB = baseR, baseG, baseB
        if _ppTextInstead then
            if primaryCfg.textCustomColored == false then
                local tpc = POWER_COLORS[cachedPrimary]
                if tpc then
                    rvR, rvG, rvB = tpc[1], tpc[2], tpc[3]
                else
                    rvR, rvG, rvB = 1, 1, 1
                end
            else
                rvR, rvG, rvB = primaryCfg.textFillR or 1, primaryCfg.textFillG or 1, primaryCfg.textFillB or 1
            end
        end
        if _bandOn then
            colorCurve = GetBarBandCurve("primary", _bands, _bandMode, mx, rvR, rvG, rvB, _bandRev)
        else
            local tR = _ppTsEntry.thresholdR or primaryCfg.thresholdR or 1
            local tG = _ppTsEntry.thresholdG or primaryCfg.thresholdG or 0.2
            local tB = _ppTsEntry.thresholdB or primaryCfg.thresholdB or 0.2
            local tPct = _ppTsEntry.thresholdPct or primaryCfg.thresholdPct or 30
            local _ppPartial = _ppTsEntry.thresholdPartialOnly
            if _ppPartial == nil then
                _ppPartial = primaryCfg.thresholdPartialOnly
            end
            if _ppPartial then
                colorCurve = GetBarThresholdCurve(rvR, rvG, rvB, tR, tG, tB, tPct)
            else
                colorCurve = GetBarThresholdCurve(tR, tG, tB, rvR, rvG, rvB, tPct)
            end
        end
        -- The curve object is the settings identity (rebuilt on any input change),
        -- so (value, max, curve, target) names every input of this color.
        if
            colorCurve
            and not (
                vmClean
                and mainBar._colCur == current
                and mainBar._colMx == mx
                and mainBar._colCurve == colorCurve
                and mainBar._colTI == _ppTextInstead
            )
        then
            if vmClean then
                mainBar._colCur, mainBar._colMx = current, mx
                mainBar._colCurve, mainBar._colTI = colorCurve, _ppTextInstead
            end
            local success, colorResult = pcall(UnitPowerPercent, "player", cachedPrimary, false, colorCurve)
            if success and colorResult and colorResult.GetRGBA then
                if _ppTextInstead then
                    if mainBar._text then
                        mainBar._text:SetTextColor(colorResult:GetRGBA())
                    end
                else
                    fillTex:SetVertexColor(colorResult:GetRGBA())
                end
            end
        end
        if _ppTextInstead then
            -- Fill stays at base color; static per config generation + power
            -- type, so reapplying it on every power tick was pure churn.
            if mainBar._colGen ~= mod.CfgGen or mainBar._colPow ~= cachedPrimary then
                mainBar._colGen, mainBar._colPow = mod.CfgGen, cachedPrimary
                if primaryCfg.gradientEnabled then
                    ApplyBarGradient(
                        fillTex,
                        primaryCfg.gradientDir or "HORIZONTAL",
                        baseR,
                        baseG,
                        baseB,
                        1,
                        primaryCfg.gradientR,
                        primaryCfg.gradientG,
                        primaryCfg.gradientB,
                        primaryCfg.gradientA
                    )
                else
                    ApplyBarFlat(fillTex, baseR, baseG, baseB, 1)
                end
            end
        end
    elseif spOn and not spText then
        -- Spender coloring keeps the base flat, as threshold coloring does.
        if mainBar._colGen ~= mod.CfgGen or mainBar._colPow ~= cachedPrimary then
            mainBar._colGen, mainBar._colPow = mod.CfgGen, cachedPrimary
            local red, green, blue
            if primaryCfg.customColored then
                red, green, blue = primaryCfg.fillR, primaryCfg.fillG, primaryCfg.fillB
            else
                local powerColor = POWER_COLORS[cachedPrimary]
                if powerColor then
                    red, green, blue = powerColor[1], powerColor[2], powerColor[3]
                else
                    red, green, blue = 1, 1, 1
                end
            end
            ApplyBarFlat(fillTex, red, green, blue, 1)
        end
    elseif not primaryCfg.customColored then
        -- Static per config generation + power type (same stamp as above).
        if mainBar._colGen ~= mod.CfgGen or mainBar._colPow ~= cachedPrimary then
            mainBar._colGen, mainBar._colPow = mod.CfgGen, cachedPrimary
            local red, green, blue
            local powerColor = POWER_COLORS[cachedPrimary]
            if powerColor then
                red, green, blue = powerColor[1], powerColor[2], powerColor[3]
            else
                red, green, blue = 1, 1, 1
            end
            if primaryCfg.gradientEnabled then
                ApplyBarGradient(
                    fillTex,
                    primaryCfg.gradientDir or "HORIZONTAL",
                    red,
                    green,
                    blue,
                    1,
                    primaryCfg.gradientR,
                    primaryCfg.gradientG,
                    primaryCfg.gradientB,
                    primaryCfg.gradientA
                )
            else
                ApplyBarFlat(fillTex, red, green, blue, 1)
            end
        end
    end

    -- Fill: eased only while the bar's Smooth Bars item is on (see the health
    -- handler note).
    mainBar:SetValue(current)

    if primaryCfg.textFormat ~= "none" and not _G._CURB_TextHiddenByForm(primaryCfg) then
        -- Stamped only when the text is actually written, so a form-hidden
        -- stretch can never leave a stale string behind for a repeated value.
        if
            not (
                vmClean
                and mainBar._txtCur == current
                and mainBar._txtMx == mx
                and mainBar._txtGen == mod.CfgGen
                and mainBar._txtPow == cachedPrimary
            )
        then
            if vmClean then
                mainBar._txtCur, mainBar._txtMx = current, mx
                mainBar._txtGen, mainBar._txtPow = mod.CfgGen, cachedPrimary
            end
            local formatStr = primaryCfg.textFormat
            local percentSuffix = (primaryCfg.showPercent == false) and "" or "%"
            local percentText = format("%d", pctRaw) .. percentSuffix
            local txt
            if formatStr == "smart" then
                local isPercent = CludesUI.IsSmartPowerPercent and CludesUI.IsSmartPowerPercent(cachedPrimary)
                txt = isPercent and percentText or mod.AbbreviateNumbers(current)
            elseif formatStr == "both" then
                txt = mod.AbbreviateNumbers(current) .. " | " .. percentText
            elseif formatStr == "curpp" then
                txt = mod.AbbreviateNumbers(current)
            elseif formatStr == "curmaxpp" then
                txt = mod.AbbreviateNumbers(current) .. " / " .. mod.AbbreviateNumbers(mx)
            elseif formatStr == "perpp" then
                txt = percentText
            else
                txt = mod.AbbreviateNumbers(current)
            end
            mainBar._text:SetText(txt)
        end
        mainBar._text:Show()
    else
        mainBar._text:Hide()
    end
end

-- Pre-allocated rune sorting buffers to avoid per-tick table creation.
-- Uses parallel arrays instead of tables-of-tables for zero GC pressure.
local _runeOrder = {} -- [slot] = rune index (1-6)
local _runeRemaining = {} -- [rune index] = remaining time
local _runeStart = {} -- [rune index] = cooldown start
local _runeDuration = {} -- [rune index] = cooldown duration
local _runeReady = {} -- [rune index] = true/false

-- Evoker Essence recharge state (timer-based, UnitPower partial doesn't work for Essence)
local _essenceNextTick = nil -- GetTime() when the next pip will be ready
Inner.essenceNextTickSetters[#Inner.essenceNextTickSetters + 1] = function(v)
    _essenceNextTick = v
end
local _essenceLastCount = nil -- last known whole-pip count
Inner.essenceLastCountSetters[#Inner.essenceLastCountSetters + 1] = function(v)
    _essenceLastCount = v
end
local _essenceTickDur = 0 -- seconds per pip recharge
Inner.essenceTickDurSetters[#Inner.essenceTickDurSetters + 1] = function(v)
    _essenceTickDur = v
end
-- Seconds per Essence pip from the regen rate; the last known duration (5 before
-- any) while the rate reads secret, as it does in combat. On ns.
function mod.EssenceTickDuration()
    if not GetPowerRegenForPowerType then
        return _essenceTickDur > 0 and _essenceTickDur or 5
    end
    local regen = GetPowerRegenForPowerType(PT.ESSENCE)
    if not regen or (issecretvalue and issecretvalue(regen)) then
        return _essenceTickDur > 0 and _essenceTickDur or 5
    end
    return regen > 0 and (1 / regen) or 5
end

-- Cast handler for the Prot Ignore Pain bar's moving hash line: each cast
-- refreshes the buff, so the line resets to the right edge and slides left.
IP.HandleCast = function(spellId)
    if not (cachedSecondary and cachedSecondary.power == "IGNOREPAIN_BAR") then
        return
    end
    if spellId == IP.SPELL then
        IP.hashEndTime = GetTime() + IP.DURATION
        return
    end
    -- Indirect refresh: Shield Slam consuming Violent Outburst. Layered probe --
    -- GetPlayerAuraBySpellID is plain table-or-nil for unflagged ids (returns
    -- NOTHING for restriction-flagged ids, today's law), so the viewer-active
    -- fallback (frames-as-truth, works under restriction when the user tracks
    -- the proc) backs it up. Called at SUCCEEDED: if the proc aura is already
    -- consumed by then BOTH probes can miss -- field question; the escalation
    -- is a SENT-time latch, not a wider guess. A miss leaves a stale tick and,
    -- since the bar fill rides this same window, an early-empty bar; IP.Active
    -- covers both from the tracked-buff icon when the user tracks IP.
    if spellId == IP.SHIELD_SLAM then
        local aura = C_UnitAuras
            and C_UnitAuras.GetPlayerAuraBySpellID
            and C_UnitAuras.GetPlayerAuraBySpellID(IP.VO_PROC)
        if aura or (IP.BuffActiveViaViewer and IP.BuffActiveViaViewer(IP.VO_PROC)) then
            IP.hashEndTime = GetTime() + IP.DURATION
        end
    end
end

-- Cast handler for the Guardian Ironfur bar. Only tracks while the Ironfur
-- bar is the active class resource so the tick list can't grow unbounded.
local function HandleIronfurCast(spellId)
    if not (cachedSecondary and cachedSecondary.power == "IRONFUR_BAR") then
        return
    end
    local nowTime = GetTime()
    if spellId == IRONFUR_SPELL then
        ironfurBaseDur = IronfurBaseDuration()
        local hasGoE = ironfurGoEUntil > 0
            and nowTime < ironfurGoEUntil
            and C_SpellBook
            and C_SpellBook.IsSpellKnown
            and C_SpellBook.IsSpellKnown(GUARDIAN_OF_ELUNE)
        local dur = ironfurBaseDur + (hasGoE and IRONFUR_GOE_BONUS or 0)
        ironfurTicks[#ironfurTicks + 1] = { endTime = nowTime + dur, duration = dur }
        if hasGoE then
            ironfurGoEUntil = 0
        end
    elseif spellId == MANGLE_SPELL then
        if C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(GUARDIAN_OF_ELUNE) then
            ironfurGoEUntil = nowTime + IRONFUR_GOE_WINDOW
        end
    elseif spellId == FRENZIED_REGEN then
        ironfurGoEUntil = 0
    end
end

-- Recolor text instead of bar
local function colorText(on, triggered, tr, tg, textBlock, baseR, baseG, baseB)
    if not on then
        return
    end
    local ct = classFrame and classFrame._countText
    if not ct then
        return
    end
    if triggered then
        ct:SetTextColor(tr, tg, textBlock, 0.9)
    else
        ct:SetTextColor(baseR, baseG, baseB, 0.9)
    end
end

-- Buff-color for the resource bar. Combat procs read Blizzard's Cooldown Viewer
-- active state, so only buffs the Cooldown Manager tracks are found; any ID may
-- still be entered and tried.
local _cuiBuffViewers = { "BuffBarCooldownViewer", "BuffIconCooldownViewer" }
-- Spell names never change within a session, so the buff check and its viewer
-- scan read them from here instead of asking the client on every update.
local _cuiSpellNames = {}
local function CachedSpellName(spellId)
    local nm = _cuiSpellNames[spellId]
    if nm == nil then
        nm = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellId) or false
        _cuiSpellNames[spellId] = nm
    end
    return nm or nil
end
-- Every item frame each viewer's pool has handed out, in plain arrays refreshed
-- only after the pool acquired one (a released item is hidden with its cooldown
-- data cleared, so a shown frame here is exactly a shown active item). The pools
-- are Blizzard's secure pools: walking one builds an iterator closure and makes a
-- secure call per step, too costly for a check that runs on every class-resource update.
-- One table.
local BVI = { items = { {}, {} }, seen = { {}, {} }, dirty = { true, true }, hooked = {} }
function BVI.Items(vi)
    local vf = _G[_cuiBuffViewers[vi]]
    local pool = vf and vf.itemFramePool
    if not (pool and pool.EnumerateActive) then
        return nil
    end
    local dirty = BVI.dirty
    if BVI.hooked[vi] ~= pool then
        BVI.hooked[vi] = pool
        dirty[vi] = true
        hooksecurefunc(pool, "Acquire", function()
            dirty[vi] = true
        end)
    end
    local entries = BVI.items[vi]
    if dirty[vi] then
        dirty[vi] = false
        local seen = BVI.seen[vi]
        for widget in pool:EnumerateActive() do
            if not seen[widget] then
                seen[widget] = true
                entries[#entries + 1] = widget
            end
        end
    end
    return entries
end
-- True when any ID the viewer scan compares is secret: Blizzard writes secret
-- values into an item's live cooldownInfo mid-fight (raid encounters), and
-- comparing one from addon code is a hard error.
function BVI.Secret(details)
    if not issecretvalue then
        return false
    end
    if issecretvalue(details.spellID) or issecretvalue(details.overrideSpellID) then
        return true
    end
    local linked = details.linkedSpellIDs
    if type(linked) == "table" then
        for i = 1, #linked do
            if issecretvalue(linked[i]) then
                return true
            end
        end
    end
    return false
end
local function BuffActiveViaCooldownViewer(spellId, wantName)
    local getCdInfo = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
    if not getCdInfo then
        return false
    end
    for vi = 1, #_cuiBuffViewers do
        local entries = BVI.Items(vi)
        if entries then
            for li = 1, #entries do
                local widget = entries[li]
                if widget:IsShown() then -- shown = the buff is currently up
                    -- The item's own cooldownInfo is the data provider's live
                    -- table (Blizzard updates its override and linked IDs in
                    -- place), so reading it allocates nothing; a
                    -- GetCooldownViewerCooldownInfo call builds a fresh copy per
                    -- item. An item without one, or whose live table holds a
                    -- secret ID, reads that copy instead: its fields are never
                    -- secret (no secret returns in the API docs), and a copy that
                    -- somehow is still secret is skipped rather than compared.
                    local details = widget.cooldownInfo
                    if not details or BVI.Secret(details) then
                        local cdID = widget.cooldownID
                        details = nil
                        if type(cdID) == "number" and not (issecretvalue and issecretvalue(cdID)) then
                            details = getCdInfo(cdID)
                            if details and BVI.Secret(details) then
                                details = nil
                            end
                        end
                    end
                    if details then
                        if details.spellID == spellId or details.overrideSpellID == spellId then
                            return true
                        end
                        if details.linkedSpellIDs then
                            for _, lid in ipairs(details.linkedSpellIDs) do
                                if lid == spellId then
                                    return true
                                end
                            end
                        end
                        local spellRef = wantName and details.spellID
                        if spellRef then
                            local nm = _cuiSpellNames[spellRef]
                            if nm == nil then
                                nm = CachedSpellName(spellRef)
                            end
                            if nm == wantName then
                                return true
                            end
                        end
                    end
                end
            end
        end
    end
    return false
end
-- Published for IP.HandleCast (defined ABOVE this helper -- a direct upvalue
-- reference there would compile as a nil global; the table field binds late).
IP.BuffActiveViaViewer = BuffActiveViaCooldownViewer

local function PlayerHasBuff(spellId)
    if not spellId or spellId == 0 or not C_UnitAuras then
        return false
    end
    local nm = CachedSpellName(spellId)
    -- 1) Exact aura spellId match.
    local byID = C_UnitAuras.GetPlayerAuraBySpellID
    if byID then
        local success, aura = pcall(byID, spellId)
        if success and aura ~= nil then
            return true
        end
    end
    -- 2) Name match. The APPLIED aura's spellId often differs from the entered
    -- (tooltip) ID (per-spec variants), so match by name. Presence only.
    local byName = C_UnitAuras.GetAuraDataBySpellName
    if byName and nm then
        local success, aura = pcall(byName, "player", nm, "HELPFUL")
        if success and aura ~= nil then
            return true
        end
    end
    -- 3) Secret rotational procs (Essence Burst etc.) are invisible to both aura
    -- reads; fall back to Blizzard's Cooldown Viewer active state.
    if BuffActiveViaCooldownViewer(spellId, nm) then
        return true
    end
    return false
end

-- Buff coloring for the class-resource bar. The 5th return is the winning row's
-- index, which the class-bar value early-out keys on.
local function ActiveBuffColor(record)
    if not record or not record.buffColorEnabled then
        return nil
    end
    local entries = record.buffColors
    if not entries then
        return nil
    end
    for i = 1, #entries do
        local e = entries[i]
        if e.spellID and PlayerHasBuff(e.spellID) then
            return e.r, e.g, e.b, e.a, i
        end
    end
    return nil
end

-- Config-derived coloring answers for the class-resource bar, rebuilt once per
-- ns.CfgGen (BuildBars and ApplyAll bump it on every option edit and on profile,
-- spec, talent and form changes). entry = the resolved threshold entry while the
-- bar is enabled; buff / spend = that entry colors by buffs / by spenders; ids =
-- the tracked spender spell IDs; w = the winning spender index (nil = not scanned
-- since the bump); oncd = per-spell verdicts ("on a real cooldown"), keyed by the
-- configured spell ID and latched from SPELL_UPDATE_COOLDOWN. The verdicts outlive
-- the bump (a rebuild in combat must not send every spell back to a live read):
-- a spell that leaves the list is pruned, and disarming wipes them all.
mod.STK = { ids = {}, oncd = {} }
-- The Power Bar's counterpart (entry, spend, ids, w, oncd).
mod.PTK = { ids = {}, oncd = {} }

-- True when the entry colors by spenders and at least one row names a spell (a
-- blank "+ Add Spender" row arms nothing). Refills ids (default ns.STK.ids) with
-- those spells.
function mod.SecondaryTracksSpender(e, ids)
    ids = ids or mod.STK.ids
    wipe(ids)
    local entries = e and e.spenderColorEnabled and e.spenderColors
    if not entries then
        return false
    end
    local any = false
    for i = 1, #entries do
        local ident = entries[i].spellID
        if ident then
            ids[ident] = true
            any = true
        end
    end
    return any
end

-- The one accessor for those answers. Returns buff, spend.
function mod.SecTracks()
    local tbl = mod.STK
    if tbl.gen ~= mod.CfgGen then
        tbl.gen = mod.CfgGen
        local secondaryCfg = _G._CURB_ResolveSecondaryCfg()
        local e = secondaryCfg and secondaryCfg.enabled ~= false and ResolveThresholdSpecEntry(secondaryCfg) or nil
        tbl.entry = e
        tbl.buff = (e and e.buffColorEnabled and e.buffColors and #e.buffColors > 0) and true or false
        tbl.spend = mod.SecondaryTracksSpender(e)
        tbl.w = nil
        -- Nothing latches a spell that left the list, so its verdict would go
        -- stale if it came back later: drop it.
        local oncd, ids = tbl.oncd, tbl.ids
        for ident in pairs(oncd) do
            if not ids[ident] then
                oncd[ident] = nil
            end
        end
    end
    return tbl.buff, tbl.spend
end

-- The Power Bar's counterpart of ns.SecTracks. Returns spend. A Power Bar that
-- cannot show (IsPowerBarHidden: off, hidden in this form or by Hide Power Bar if
-- Resource, no primary power) tracks nothing, so no spender events stay armed.
function mod.PowTracks()
    local tbl = mod.PTK
    if tbl.gen ~= mod.CfgGen then
        tbl.gen = mod.CfgGen
        local primaryCfg = _G._CURB_ResolvePowerCfg()
        local e = primaryCfg and not IsPowerBarHidden() and ResolveThresholdSpecEntry(primaryCfg) or nil
        tbl.entry = e
        tbl.spend = mod.SecondaryTracksSpender(e, tbl.ids)
        tbl.w = nil
        local oncd, ids = tbl.oncd, tbl.ids
        for ident in pairs(oncd) do
            if not ids[ident] then
                oncd[ident] = nil
            end
        end
    end
    return tbl.spend
end

-- Spender coloring: the FIRST castable spell in the entry's list wins. Each spell
-- is read through its current override (transforming spells). Castable means
-- IsSpellUsable (resource, range, known) and not on a real cooldown: IsSpellUsable
-- ignores cooldowns, so a spell that is free under some condition (Void Ray during
-- Void Metamorphosis) would otherwise read castable for its whole cooldown. A
-- charge spell is castable while it holds a charge. Its count is secret in
-- restricted combat: full charges still read from the recharge flag, and a
-- recharging spell falls back to the latched verdict like every other spell. The
-- latch stands in for a live read because isOnGCD is only trustworthy inside
-- SPELL_UPDATE_COOLDOWN; a live read covers a spell only until its first latch.
-- oncd: the bar's verdicts (default ns.STK.oncd). Returns the winning index, 0
-- for none.
function mod.SpenderScan(record, oncd)
    local entries = record and record.spenderColorEnabled and record.spenderColors
    if not entries then
        return 0
    end
    local S = C_Spell
    oncd = oncd or mod.STK.oncd
    for i = 1, #entries do
        local spellRef = entries[i].spellID
        if spellRef then
            local ident = S.GetOverrideSpell(spellRef) or spellRef
            if S.IsSpellUsable(ident) then
                local ready
                local ch = S.GetSpellCharges(ident)
                local mx = ch and ch.maxCharges
                if mx and mx > 1 then
                    local num = ch.currentCharges
                    if not (issecretvalue and issecretvalue(num)) then
                        ready = num > 0
                    elseif not ch.isActive then
                        ready = true
                    end
                end
                if ready == nil then
                    local oc = oncd[spellRef]
                    if oc == nil then
                        local cd = S.GetSpellCooldown(ident)
                        oc = cd and cd.isActive and not cd.isOnGCD
                    end
                    ready = not oc
                end
                if ready then
                    return i
                end
            end
        end
    end
    return 0
end

-- Cached winning spender index (0 = none): scanned once after each config bump,
-- then kept current by the spender pass (next to ns.PollTick). Call after
-- ns.SecTracks().
function mod.SpenderWinner()
    local tbl = mod.STK
    local wid = tbl.w
    if wid == nil then
        wid = tbl.spend and mod.SpenderScan(tbl.entry) or 0
        tbl.w = wid
    end
    return wid
end

-- Override color of the cached winning spender. The paints and their 30 Hz and
-- 10 Hz tickers read this; only the spender pass queries the spell APIs.
function mod.ActiveSpenderColor(record)
    local _, spend = mod.SecTracks()
    if not spend or record ~= mod.STK.entry then
        return nil
    end
    local wid = mod.SpenderWinner()
    local e = wid > 0 and record.spenderColors[wid]
    if e then
        return e.r, e.g, e.b, e.a
    end
    return nil
end

-- The Power Bar's counterpart of ns.SpenderWinner. Call after ns.PowTracks().
function mod.PowSpenderWinner()
    local tbl = mod.PTK
    local wid = tbl.w
    if wid == nil then
        wid = tbl.spend and mod.SpenderScan(tbl.entry, tbl.oncd) or 0
        tbl.w = wid
    end
    return wid
end

-- The Power Bar's override color and winning index. Separate from
-- ns.ActiveSpenderColor so class-resource paints pay nothing for it.
function mod.PowSpenderColor()
    if not mod.PowTracks() then
        return nil
    end
    local wid = mod.PowSpenderWinner()
    local e = wid > 0 and mod.PTK.entry.spenderColors[wid]
    if e then
        return e.r, e.g, e.b, e.a, wid
    end
    return nil
end

-- Per-frame render for the Guardian Ironfur bar: prune expired ticks, position
-- the moving hash lines (right -> left as each cast decays), and drive the fill
-- to the longest-remaining fraction.
local function UpdateIronfurBar()
    if not (classBar and classBar:IsShown()) then
        return
    end
    local secondaryCfg = _G._CURB_ResolveSecondaryCfg() or ERB.db.profile.secondary
    local nowTime = GetTime()

    -- Prune expired casts
    for i = #ironfurTicks, 1, -1 do
        if ironfurTicks[i].endTime <= nowTime then
            table.remove(ironfurTicks, i)
        end
    end

    local total = #ironfurTicks
    local barW = classBar:GetWidth() or 0
    local barH = classBar:GetHeight() or 0
    local overlayFrame = classBar._ifOverlay
    local showHash = secondaryCfg.guardianShowHashLines ~= false
    local Pix = CludesUI and CludesUI.PP
    local tickW = Pix and (2 * Pix.mult) or 2
    local maxFrac = 0
    local isShown = 0

    -- Follow bar orientation instead of assuming horizontal.
    local oriSb = classBar._sb
    local vert = (oriSb and oriSb.GetOrientation and oriSb:GetOrientation() == "VERTICAL") or false
    local revFill = (vert and oriSb.GetReverseFill and oriSb:GetReverseFill()) or false

    for i = 1, total do
        local tbl = ironfurTicks[i]
        local frac = (tbl.duration > 0) and ((tbl.endTime - nowTime) / tbl.duration) or 0
        if frac < 0 then
            frac = 0
        elseif frac > 1 then
            frac = 1
        end
        if frac > maxFrac then
            maxFrac = frac
        end
        if showHash and overlayFrame and barW > 0 and barH > 0 then
            isShown = isShown + 1
            local texture = ironfurTickTex[isShown]
            if not texture then
                texture = overlayFrame:CreateTexture(nil, "OVERLAY", nil, 7)
                texture:SetSnapToPixelGrid(false)
                texture:SetTexelSnappingBias(0)
                ironfurTickTex[isShown] = texture
            end
            texture:SetColorTexture(1, 1, 1, 0.9)
            texture:ClearAllPoints()
            if vert then
                local posY = frac * barH
                if posY > barH - tickW then
                    posY = barH - tickW
                end
                if posY < 0 then
                    posY = 0
                end
                texture:SetSize(barW, tickW)
                if revFill then
                    texture:SetPoint("TOPLEFT", classBar, "TOPLEFT", 0, -posY)
                else
                    texture:SetPoint("BOTTOMLEFT", classBar, "BOTTOMLEFT", 0, posY)
                end
            else
                local posX = frac * barW
                if posX > barW - tickW then
                    posX = barW - tickW
                end
                if posX < 0 then
                    posX = 0
                end
                texture:SetSize(tickW, barH)
                texture:SetPoint("TOPLEFT", classBar, "TOPLEFT", posX, 0)
            end
            texture:Show()
        end
    end

    -- Hide any leftover pooled tick textures
    for i = isShown + 1, #ironfurTickTex do
        ironfurTickTex[i]:Hide()
    end

    -- Fill color: class/custom/dark base, swapped to the per-spec threshold
    -- color while the active Ironfur stack count is at or above the threshold.
    local red, green, blue, a
    if secondaryCfg.darkTheme then
        local _dfr, _dfg, _dfb = CludesUI.GetDarkModeFill()
        red, green, blue, a = _dfr, _dfg, _dfb, 1
    elseif secondaryCfg.classColored ~= false then
        local classColor = CLASS_COLORS[cachedClass]
        if classColor then
            red, green, blue = classColor[1], classColor[2], classColor[3]
        else
            red, green, blue = 1, 1, 1
        end
        a = 1
    else
        red, green, blue, a = secondaryCfg.fillR, secondaryCfg.fillG, secondaryCfg.fillB, 1
    end
    local tsEntry = ResolveThresholdSpecEntry(secondaryCfg)
    -- Capture "recolor text instead" BEFORE the buff nils tsEntry below so the flag
    -- survives (buff + text-instead => buff colors the count text, fill stays base).
    local _tiWanted = (tsEntry and tsEntry.thresholdTextInstead and secondaryCfg.showText) and true or false
    -- Buff coloring wins: a tracked buff on this entry overrides the base color and
    -- suppresses the stack-count threshold/bands below.
    local _bfr, _bfg, _bfb, _bfa = ActiveBuffColor(tsEntry)
    -- No tracked buff active: a castable spender supplies the override color instead.
    if not _bfr then
        _bfr, _bfg, _bfb, _bfa = mod.ActiveSpenderColor(tsEntry)
    end
    local _buffActive = _bfr ~= nil
    if _buffActive and not _tiWanted then
        red, green, blue, a = _bfr or red, _bfg or green, _bfb or blue, _bfa or a
    end
    -- Ironfur colors by active stack count, NOT the bar's duration fraction, so
    -- both single-threshold and multi-band match against `count`; multi wins when
    -- enabled with bands, else the single stack-count threshold (FindCountBand).
    local bandOn, bands, _bandMode, bandRev = ResolveBandConfig(secondaryCfg, tsEntry)
    if _buffActive then
        tsEntry = nil
        bandOn = false
    end
    -- Active (threshold/band) color is computed separately from the base so it can
    -- route to the fill or the count text. `triggered` = the stack count satisfies
    -- the threshold/band.
    local arR, arG, arB, arA = red, green, blue, a
    local triggered = false
    if bandOn then
        local bandTex = FindCountBand(bands, total, bandRev)
        if bandTex then
            arR = bandTex.r or red
            arG = bandTex.g or green
            arB = bandTex.b or blue
            arA = bandTex.a or a
            triggered = true
        end
    elseif tsEntry and tsEntry.thresholdEnabled ~= false then
        local threshCount = tsEntry.thresholdCount or secondaryCfg.thresholdCount or 3
        if total >= threshCount then
            arR = tsEntry.thresholdR or secondaryCfg.thresholdR or red
            arG = tsEntry.thresholdG or secondaryCfg.thresholdG or green
            arB = tsEntry.thresholdB or secondaryCfg.thresholdB or blue
            arA = tsEntry.thresholdA or secondaryCfg.thresholdA or a
            triggered = true
        end
    end
    local _spTextInstead = _tiWanted
    local fillTex = classBar:GetStatusBarTexture()
    if fillTex then
        if _spTextInstead then
            fillTex:SetVertexColor(red, green, blue, a)
        else
            fillTex:SetVertexColor(arR, arG, arB, arA)
        end
    end

    -- Fill = longest remaining fraction (min/max is 0..1 here), so the bar depletes
    -- with the longest-lived Ironfur stack. Set directly: this runs from the motion
    -- ticker, which is its own smooth cadence.
    classBar:SetValue(maxFrac)

    if secondaryCfg.showText and classFrame and classFrame._countText then
        classFrame._countText:SetText(total > 0 and tostring(total) or "")
        -- Buff + text-instead: use the buff color as the text base (there's no
        -- stack-threshold trigger while a buff is up), so colorText paints it.
        local _tbR, _tbG, _tbB = secondaryCfg.textR or 1, secondaryCfg.textG or 1, secondaryCfg.textB or 1
        if _buffActive and _spTextInstead then
            _tbR, _tbG, _tbB = _bfr, _bfg, _bfb
        end
        colorText(_spTextInstead, triggered, arR, arG, arB, _tbR, _tbG, _tbB)
    end
end

-- Single moving hash line for the Prot Ignore Pain bar (Ironfur-style): resets to the
-- right edge on each cast, slides left as the buff decays. Reuses the Ironfur overlay
-- host with one pooled texture, driven from the main OnUpdate while the bar is shown.
IP.UpdateHash = function()
    local secondaryCfg = ERB.db.profile.secondary
    local remain = IP.hashEndTime - GetTime()
    if secondaryCfg.protIgnorePainHashLine == false or remain <= 0 then
        if IP.hashTex then
            IP.hashTex:Hide()
        end
        return
    end
    local barW = classBar:GetWidth() or 0
    local barH = classBar:GetHeight() or 0
    if barW <= 0 then
        return
    end
    local overlayFrame = EnsureIronfurOverlay(classBar)
    if not IP.hashTex then
        IP.hashTex = overlayFrame:CreateTexture(nil, "OVERLAY", nil, 7)
        IP.hashTex:SetSnapToPixelGrid(false)
        IP.hashTex:SetTexelSnappingBias(0)
        IP.hashTex:SetColorTexture(1, 1, 1, 0.9)
    end
    local Pix = CludesUI and CludesUI.PP
    local tickW = Pix and (2 * Pix.mult) or 2
    local frac = remain / IP.DURATION
    if frac > 1 then
        frac = 1
    end
    -- Follow bar orientation instead of assuming horizontal.
    local oriSb = classBar._sb
    local vert = (oriSb and oriSb.GetOrientation and oriSb:GetOrientation() == "VERTICAL") or false
    local revFill = (vert and oriSb.GetReverseFill and oriSb:GetReverseFill()) or false
    IP.hashTex:ClearAllPoints()
    if vert then
        local posY = frac * barH
        if posY > barH - tickW then
            posY = barH - tickW
        end
        if posY < 0 then
            posY = 0
        end
        IP.hashTex:SetSize(barW, tickW)
        if revFill then
            IP.hashTex:SetPoint("TOPLEFT", classBar, "TOPLEFT", 0, -posY)
        else
            IP.hashTex:SetPoint("BOTTOMLEFT", classBar, "BOTTOMLEFT", 0, posY)
        end
    else
        local posX = frac * barW
        if posX > barW - tickW then
            posX = barW - tickW
        end
        if posX < 0 then
            posX = 0
        end
        IP.hashTex:SetSize(tickW, barH)
        IP.hashTex:SetPoint("TOPLEFT", classBar, "TOPLEFT", posX, 0)
    end
    IP.hashTex:Show()
end

-- In-combat text source: the ONLY clean stack number in combat is the one
-- Blizzard's tracked-buff (cooldown viewer) Ignore Pain icon displays, observed
-- via hooksecurefunc on its stack FontString's SetText. Every direct read is
-- secret (absorbs, aura data, bar value, rendered fill rect); no dependency on
-- the CUI CDM module. Degrades gracefully: viewer hidden/IP untracked falls back
-- to the fill-width readback (clean values only) or stays blank.
IP.FrameSpellID = function(widget)
    if widget.GetSpellID then
        local success, spellRef = pcall(widget.GetSpellID, widget)
        if success and spellRef and not (issecretvalue and issecretvalue(spellRef)) then
            return spellRef
        end
    end
    local cdID = widget.cooldownID or (widget.cooldownInfo and widget.cooldownInfo.cooldownID)
    if cdID and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
        local success, details = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cdID)
        if success and details then
            local spellRef = details.spellID
            if spellRef and not (issecretvalue and issecretvalue(spellRef)) then
                return spellRef
            end
        end
    end
end

IP.HookViewerFS = function(widget, appFS)
    IP.viewerFrame = widget
    IP.viewerFS = appFS
    if not IP.hookedFS[appFS] then
        IP.hookedFS[appFS] = true
        hooksecurefunc(appFS, "SetText", function(_, val)
            if IP.viewerFS ~= appFS then
                return
            end
            -- Pool recycling: this frame may now show another buff
            if IP.FrameSpellID(widget) ~= IP.SPELL then
                IP.viewerFrame = nil
                IP.viewerFS = nil
                IP.value = nil
                -- Recapture next text tick: the pool rebuild that recycled this
                -- frame has already re-homed the IP icon.
                IP.nextScan = 0
                return
            end
            -- Secrets pass through raw (SetText renders them); clean strings
            -- normalize to numbers.
            if issecretvalue and issecretvalue(val) then
                IP.value = val
            elseif type(val) == "number" then
                IP.value = val
            elseif type(val) == "string" then
                IP.value = tonumber(val)
            else
                IP.value = nil
            end
        end)
    end
    -- Seed from whatever the icon currently shows
    local success, current = pcall(appFS.GetText, appFS)
    if success then
        if issecretvalue and issecretvalue(current) then
            IP.value = current
        elseif type(current) == "string" then
            IP.value = tonumber(current)
        end
    end
end

-- Scan BOTH Blizzard viewers for Ignore Pain. Tracked Buffs carry the stack
-- FontString at frame.Applications.Applications; Tracked Bars at
-- frame.Icon.Applications (same child the CUI CDM buff bars read). Whichever has
-- IP wins. force: rescan even with a capture held (used when the captured FS
-- went invisible, possibly stranded on a released pool frame); a forced scan
-- finding nothing leaves the current capture in place.
IP.ScanViewer = function(force)
    if IP.viewerFrame and not force then
        return
    end
    local function scanPool(viewer, resolve)
        if not viewer or not viewer.itemFramePool then
            return
        end
        for widget in viewer.itemFramePool:EnumerateActive() do
            if IP.FrameSpellID(widget) == IP.SPELL then
                local fontStr = resolve(widget)
                if fontStr then
                    IP.HookViewerFS(widget, fontStr)
                    return true
                end
                return
            end
        end
    end
    local hit = scanPool(_G.BuffIconCooldownViewer, function(frame)
        return frame.Applications and frame.Applications.Applications
    end)
    -- Icon viewer wins; the bar viewer is only consulted when the icon scan
    -- captured nothing this pass (a held stale capture must not block it).
    if not hit and (not IP.viewerFrame or force) then
        scanPool(_G.BuffBarCooldownViewer, function(frame)
            return frame.Icon and frame.Icon.Applications
        end)
    end
end

-- Lazy (re)scan for the Blizzard tracked-buff IP icon (2s throttle); also rescan
-- while the captured FS is invisible, since a viewer pool rebuild (tracked buffs
-- proccing/expiring, e.g. Thunder Blast) can strand the capture on a released
-- hidden frame that never fires SetText, while the icon lives on in another pool
-- frame -- otherwise text stays blank until the orphan happens to be reused. Driven
-- from MotionTick, not from UpdateText: the fill gate below reads the capture too,
-- so it has to stay current with the count text switched off.
IP.EnsureViewer = function()
    local staleFS = IP.viewerFS and not IP.viewerFS:IsVisible()
    if (not IP.viewerFrame or staleFS) and GetTime() >= IP.nextScan then
        IP.nextScan = GetTime() + 2
        IP.ScanViewer(staleFS)
    end
end

-- Is Ignore Pain up? Blizzard's tracked-buff icon is the authoritative answer -- it
-- survives a reload, a spec swap and a Violent Outburst refresh the cast handler
-- missed -- but it only exists while the user tracks IP in the CDM, so the
-- cast-driven window backs it up.
IP.Active = function()
    if IP.viewerFS and IP.viewerFS:IsVisible() then
        return true
    end
    return IP.hashEndTime > GetTime()
end

-- Per-frame stack text for the IP bar. Preferred source: the exact stack number
-- captured from Blizzard's tracked-buff icon above; fallback: rendered fill width
-- (fill/bar = percent of cap = stacks) when values read clean but the viewer is
-- unavailable. Change-detected; blank with no clean source, empty bar, or text off.
IP.UpdateText = function()
    if not (classFrame and classFrame._countText) then
        return
    end
    local secondaryCfg = ERB.db.profile.secondary
    if not secondaryCfg.showText then
        if IP.lastTextStacks then
            classFrame._countText:SetText("")
            IP.lastTextStacks = nil
        end
        return
    end
    -- The captured viewer value is usually a SECRET number (type() says "number"
    -- and truthiness works, but comparisons/format error). SetText renders secret
    -- numbers natively -- exactly what Blizzard's own icon does with this value --
    -- so pass it UNTOUCHED: no clamp, no change-detection, no tostring.
    if issecretvalue and issecretvalue(IP.value) then
        if IP.viewerFS and IP.viewerFS:IsVisible() then
            classFrame._countText:SetText(IP.value)
            IP.lastTextStacks = nil -- secrets cannot be change-detected
        elseif IP.lastTextStacks ~= 0 then
            IP.lastTextStacks = 0
            classFrame._countText:SetText("")
        end
        return
    end
    local stacks = 0
    if IP.value and IP.viewerFS and IP.viewerFS:IsVisible() then
        stacks = IP.value
        if stacks > 100 then
            stacks = 100
        end
        if stacks < 0 then
            stacks = 0
        end
    else
        local fillTex = classBar.GetStatusBarTexture and classBar:GetStatusBarTexture()
        if fillTex then
            local okW, fw = pcall(fillTex.GetWidth, fillTex)
            local okB, bw = pcall(classBar.GetWidth, classBar)
            if
                okW
                and okB
                and fw
                and bw
                and not (issecretvalue and (issecretvalue(fw) or issecretvalue(bw)))
                and bw > 0
            then
                stacks = math.floor(fw / bw * 100 + 0.5)
                if stacks > 100 then
                    stacks = 100
                end
            end
        end
    end
    if stacks == IP.lastTextStacks then
        return
    end
    IP.lastTextStacks = stacks
    classFrame._countText:SetText(stacks > 0 and tostring(stacks) or "")
end

local function UpdateSecondaryResource()
    -- Blizzard Class Resource Art stands in: the pips are unseen, paint nothing.
    if mod._erbArtOn then
        return
    end
    if not classFrame or not classFrame:IsShown() then
        return
    end
    if not cachedSecondary then
        return
    end

    local powerKind = cachedSecondary.power
    local pointCap = cachedSecondary.max or 5

    if powerKind == "IRONFUR_BAR" then
        UpdateIronfurBar()
        return
    end

    -- Value early-out for plain point resources (Holy Power, combo points, soul shards,
    -- chi, ...). Everything below is a pure function of value/max/config, and four
    -- triggers reach this per cast (UNIT_POWER_FREQUENT, UNIT_AURA,
    -- UNIT_SPELLCAST_SUCCEEDED, the 10fps safety poll), most firing with the resource
    -- unchanged (~300 hits/9 misses over 15s casting, profiled 12.2%->2.9%). The
    -- active tracked buff and the winning spender change while the value stands
    -- still, so both are part of the key (the buff is read here; the spender comes
    -- from the cache the spender pass keeps current). The charged-point set is not:
    -- UNIT_POWER_POINT_CHARGE drops the memo instead. Secret values bail out (not
    -- comparable); non-"points" resources never reach this branch. THE GUARD MUST
    -- COMPARE THE VALUE THE RENDER CONSUMES, not the whole-unit count: Destruction
    -- soul shards move in tenths and the partial-pip fill is driven by the fragment
    -- read, so guarding on the whole count would swallow every fragment change. The
    -- unmodified read is never less sensitive -- Affliction/Demonology step in whole
    -- shards. Essence is the other fractional resource and can't use this (UnitPower
    -- has no partial for it), hence its timer exemption below; any future fractional
    -- resource belongs HERE.
    -- The tracked buff this early-out reads is handed to the fill pass below (same
    -- entry, same call), so a redraw scans the buff viewers once, not twice.
    local _ebEntry, _ebR, _ebG, _ebB, _ebA
    if cachedSecondary.type == "points" then
        local _evCur
        if cachedSecondary.frac then
            _evCur = UnitPower("player", powerKind, true)
            if _evCur == nil then
                _evCur = UnitPower("player", powerKind)
            end
        elseif cachedSecondary.onTarget then
            -- WoW Forever: combo points belong to the target, and UnitPower still
            -- reports the previous target's count after a target swap.
            _evCur = GetComboPoints("player", "target") or 0
        else
            _evCur = UnitPower("player", powerKind)
        end
        if not (issecretvalue and issecretvalue(_evCur)) then
            local textBlock, ts = mod.SecTracks()
            local bw, sw = 0, 0
            if textBlock then
                local i
                _ebEntry = mod.STK.entry
                _ebR, _ebG, _ebB, _ebA, i = ActiveBuffColor(_ebEntry)
                bw = i or 0
            end
            if ts then
                sw = mod.SpenderWinner()
            end
            local st = mod.SecSt
            -- Essence recharge exemption: the partial pip refills over several
            -- seconds while UnitPower reads the SAME count, so an in-flight
            -- recharge (_essenceNextTick set) must keep redrawing or this
            -- unchanged-value early-out freezes it.
            if
                st
                and st.cur == _evCur
                and st.max == pointCap
                and st.gen == mod.CfgGen
                and st.bw == bw
                and st.sw == sw
                and not _essenceNextTick
            then
                return
            end
            if not st then
                st = {}
                mod.SecSt = st
            end
            st.cur, st.max, st.gen, st.bw, st.sw = _evCur, pointCap, mod.CfgGen, bw, sw
        end
    end

    local secondaryCfg = _G._CURB_ResolveSecondaryCfg()
    if not secondaryCfg then
        return
    end
    -- Per-spec threshold entry, resolved once per update
    local _tsEntry = ResolveThresholdSpecEntry(secondaryCfg)
    local _buffEntry = _tsEntry
    -- Per-entry thresholdEnabled (absent field = true, for migrated entries)
    local _tsEnabled = _tsEntry and (_tsEntry.thresholdEnabled ~= false) or false
    local _tsBandOn, _tsBands, _tsBandMode, _tsBandReverse = ResolveBandConfig(secondaryCfg, _tsEntry)
    if not _tsEnabled then
        _tsEntry = nil
    end
    local _tsThreshCount = _tsEntry and _tsEntry.thresholdCount or secondaryCfg.thresholdCount
    -- Enhance Five Bar needs a threshold of at least 7 (5 pips + overflow). Clamp
    -- the value used this update, and persist a stale entry saved below 7 so it
    -- actually updates (Enhancement entry only).
    if
        powerKind == "MAELSTROM_WEAPON"
        and secondaryCfg.enhanceFiveBar
        and _tsEntry
        and _tsThreshCount
        and _tsThreshCount < 7
    then
        _tsThreshCount = 7
        local _specIdx = GetSpecialization()
        local _specID = _specIdx
            and C_SpecializationInfo
            and C_SpecializationInfo.GetSpecializationInfo(_specIdx)
        if _specID and _tsEntry.specIDs then
            for _, spellRef in ipairs(_tsEntry.specIDs) do
                if spellRef == _specID then
                    _tsEntry.thresholdCount = 7
                    break
                end
            end
        end
    end
    local _tsPartialOnly = _tsEntry and _tsEntry.thresholdPartialOnly
    if _tsPartialOnly == nil then
        _tsPartialOnly = secondaryCfg.thresholdPartialOnly
    end
    -- Bar-type only: reverse so the threshold color shows below the value
    local _tsReverse = _tsEntry and _tsEntry.thresholdReverse
    if _tsReverse == nil then
        _tsReverse = secondaryCfg.thresholdReverse
    end
    -- "Only color at/above threshold" (partial pip recolor) is "From"-only --
    -- meaningless under "Up to" (low count = no pips past the threshold), so the
    -- option is greyed there and ignored here.
    if _tsReverse then
        _tsPartialOnly = false
    end
    -- Per-entry threshold color (falls back to global sp.thresholdR/G/B/A)
    local _tsR = _tsEntry and _tsEntry.thresholdR or secondaryCfg.thresholdR
    local _tsG = _tsEntry and _tsEntry.thresholdG or secondaryCfg.thresholdG
    local _tsB = _tsEntry and _tsEntry.thresholdB or secondaryCfg.thresholdB
    local _tsA = _tsEntry and _tsEntry.thresholdA or secondaryCfg.thresholdA
    -- "Recolor text instead of bar": route the threshold/band color to the count
    -- text, fill/pips stay at base. Only when text is shown, else fall back to
    -- fill coloring so the threshold stays visible. Works for every clean
    -- (Lua-comparable) resource -- bar-type, runes, all pips -- except the two
    -- secret-value resources, Ignore Pain and Vengeance soul fragments.
    local _spTextInstead = _buffEntry
        and _buffEntry.thresholdTextInstead
        and secondaryCfg.showText
        and powerKind ~= "IGNOREPAIN_BAR"
    local _spTextBaseR, _spTextBaseG, _spTextBaseB = secondaryCfg.textR or 1, secondaryCfg.textG or 1, secondaryCfg.textB or 1
    local red, green, blue, a = 1, 1, 1, 1

    -- Color: dark theme > class colored > custom fill color
    if secondaryCfg.darkTheme then
        red, green, blue = CludesUI.GetDarkModeFill()
    elseif secondaryCfg.resourceColored then
        -- Per-spec resource/power color; falls back to class color.
        local rr, rg, rb = ERB.ResolveSecondaryResourceColor(powerKind)
        if rr then
            red, green, blue = rr, rg, rb
        else
            local classColor = CLASS_COLORS[cachedClass]
            if classColor then
                red, green, blue = classColor[1], classColor[2], classColor[3]
            end
        end
        a = 1
    elseif secondaryCfg.classColored ~= false then
        -- Power types in secondary slot use power color; class resources use class color
        local powerColor = POWER_COLORS[powerKind]
        if powerColor then
            red, green, blue = powerColor[1], powerColor[2], powerColor[3]
        else
            local classColor = CLASS_COLORS[cachedClass]
            if classColor then
                red, green, blue = classColor[1], classColor[2], classColor[3]
            end
        end
        a = 1
    else
        -- classColored explicitly false -- custom fill
        red, green, blue, a = secondaryCfg.fillR, secondaryCfg.fillG, secondaryCfg.fillB, 1
    end

    -- A tracked buff overrides the fill (buff wins over threshold). With "recolor
    -- text instead" on, the buff colors the count TEXT (done at the end of this
    -- function) and fill/pips stay at their base color.
    local _bfr, _bfg, _bfb, _bfa
    if _ebEntry ~= nil and _ebEntry == _buffEntry then
        _bfr, _bfg, _bfb, _bfa = _ebR, _ebG, _ebB, _ebA
    else
        _bfr, _bfg, _bfb, _bfa = ActiveBuffColor(_buffEntry)
    end
    -- No tracked buff active: a castable spender supplies the override color instead.
    if not _bfr then
        _bfr, _bfg, _bfb, _bfa = mod.ActiveSpenderColor(_buffEntry)
    end
    local _buffActive = _bfr ~= nil
    if _buffActive then
        if not _spTextInstead then
            red, green, blue, a = _bfr or red, _bfg or green, _bfb or blue, _bfa or a
        end
        _tsEntry = nil
        _tsBandOn = false
    end

    -- Points: read once. A secret can't survive the comparison-based points
    -- path, so it routes to the secret overlay renderer (custom branch).
    local _ptsCur, _ptsSecret
    if cachedSecondary.type == "points" then
        if cachedSecondary.onTarget then
            _ptsCur = GetComboPoints("player", "target") or 0
        else
            _ptsCur = UnitPower("player", powerKind)
        end
        _ptsSecret = (issecretvalue and issecretvalue(_ptsCur)) and true or false
    end

    if cachedSecondary.type == "runes" then
        local nowTime = GetTime()
        local readyN, cdN = 0, 0
        for i = 1, 6 do
            local start, duration, ready = GetRuneCooldown(i)
            _runeStart[i] = start
            _runeDuration[i] = duration
            if ready then
                _runeReady[i] = true
                _runeRemaining[i] = 0
                readyN = readyN + 1
                _runeOrder[readyN] = i
            else
                _runeReady[i] = false
                _runeRemaining[i] = (start and duration and duration > 0)
                        and max(0, start + duration - nowTime)
                    or 999
                cdN = cdN + 1
            end
        end

        -- Threshold: color ready runes differently when enough are available
        local runeUseThresh = _tsEntry and readyN >= _tsThreshCount
        local tr, tg, textBlock = _tsR, _tsG, _tsB
        -- Multi-band threshold
        if _tsBandOn then
            local bandTex = FindCountBand(_tsBands, readyN, _tsBandReverse)
            if bandTex then
                runeUseThresh = true
                tr, tg, textBlock = bandTex.r, bandTex.g, bandTex.b
            else
                runeUseThresh = false
            end
        end
        local _runeTI = _spTextInstead and secondaryCfg.runesSimple
        local _runeTiTrig = runeUseThresh and true or false
        if _runeTI then
            runeUseThresh = false
        end

        if secondaryCfg.runesSimple then
            -- Simple mode: flat pips like Holy Power (active/inactive, no recharge animation)
            local numPips = 6
            local totalW = secondaryCfg.pipWidth or 214
            local pipSp = secondaryCfg.pipSpacing or 1
            local slots = CalcPipGeometry(totalW, numPips, pipSp, classFrame)

            for i = 1, 6 do
                local resourceFrame = runeFrames[i]
                if resourceFrame and resourceFrame:IsShown() then
                    local slot = slots[i]
                    local x0 = slot.x0
                    local wid = slot.x1 - slot.x0
                    local pipOri = secondaryCfg.pipOrientation or "HORIZONTAL"
                    resourceFrame:ClearAllPoints()
                    if pipOri == "VERTICAL_UP" then
                        resourceFrame:SetPoint("BOTTOM", classFrame, "BOTTOM", 0, x0)
                        resourceFrame:SetHeight(wid)
                    elseif pipOri == "VERTICAL_DOWN" or pipOri == "VERTICAL" then
                        resourceFrame:SetPoint("TOP", classFrame, "TOP", 0, -x0)
                        resourceFrame:SetHeight(wid)
                    else
                        resourceFrame:SetPoint("LEFT", classFrame, "LEFT", x0, 0)
                        resourceFrame:SetWidth(wid)
                    end

                    local active = (i <= readyN)
                    if secondaryCfg.useContinuousTexture then
                        PipTextureHelpers.SetRange(resourceFrame, x0, slot.x1, slots[numPips].x1, pipOri)
                    end
                    if active and runeUseThresh then
                        if not _tsBandOn and _tsPartialOnly and i < _tsThreshCount then
                            resourceFrame:SetActive(true, red, green, blue, a)
                        else
                            resourceFrame:SetActive(true, tr, tg, textBlock)
                        end
                    else
                        resourceFrame:SetActive(active, red, green, blue, a)
                    end
                    if resourceFrame._rechargeBar then
                        resourceFrame._rechargeBar:Hide()
                    end
                    if resourceFrame._cdText then
                        resourceFrame._cdText:SetText("")
                    end
                end
            end

            -- Central count text (like other pip resources)
            if secondaryCfg.showText and classFrame._countText then
                classFrame._countText:SetText(tostring(readyN))
                colorText(_runeTI, _runeTiTrig, tr, tg, textBlock, _spTextBaseR, _spTextBaseG, _spTextBaseB)
            end
        else
            -- Full rune mode: sort ready left, cooling right with recharge animation
            -- Clear central count text (used by simple mode)
            if classFrame._countText then
                classFrame._countText:SetText("")
            end
            -- Append cd runes after ready runes in _runeOrder
            local ci = readyN
            for i = 1, 6 do
                if not _runeReady[i] then
                    ci = ci + 1
                    _runeOrder[ci] = i
                end
            end
            -- Insertion-sort the cd portion (indices readyN+1..readyN+cdN) by
            -- remaining time. Max 6 elements so this is faster than table.sort
            -- and avoids creating a comparator closure each tick.
            for i = readyN + 2, readyN + cdN do
                local key = _runeOrder[i]
                local keyRem = _runeRemaining[key]
                local jdx = i - 1
                while jdx > readyN and _runeRemaining[_runeOrder[jdx]] > keyRem do
                    _runeOrder[jdx + 1] = _runeOrder[jdx]
                    jdx = jdx - 1
                end
                _runeOrder[jdx + 1] = key
            end
            local totalRunes = readyN + cdN

            -- Compute pixel-snapped pip geometry (spacing guaranteed >= 1 physical pixel)
            local numPips = 6
            local totalW = secondaryCfg.pipWidth or 214
            local pipSp = secondaryCfg.pipSpacing or 1
            local slots = CalcPipGeometry(totalW, numPips, pipSp, classFrame)

            for place = 1, totalRunes do
                local runeIdx = _runeOrder[place]
                local resourceFrame = runeFrames[runeIdx]
                if resourceFrame and resourceFrame:IsShown() then
                    local slot = slots[place]
                    local x0 = slot.x0
                    local wid = slot.x1 - slot.x0
                    local pipOri = secondaryCfg.pipOrientation or "HORIZONTAL"
                    resourceFrame:ClearAllPoints()
                    if pipOri == "VERTICAL_UP" then
                        resourceFrame:SetPoint("BOTTOM", classFrame, "BOTTOM", 0, x0)
                        resourceFrame:SetHeight(wid)
                    elseif pipOri == "VERTICAL_DOWN" or pipOri == "VERTICAL" then
                        resourceFrame:SetPoint("TOP", classFrame, "TOP", 0, -x0)
                        resourceFrame:SetHeight(wid)
                    else
                        resourceFrame:SetPoint("LEFT", classFrame, "LEFT", x0, 0)
                        resourceFrame:SetWidth(wid)
                    end

                    if secondaryCfg.useContinuousTexture then
                        PipTextureHelpers.SetRange(resourceFrame, x0, slot.x1, slots[numPips].x1, pipOri)
                    end
                    if _runeReady[runeIdx] then
                        -- Ready rune: full brightness + restore background, hide recharge overlay
                        resourceFrame._bg:SetAlpha(1)
                        if runeUseThresh then
                            if not _tsBandOn and _tsPartialOnly and place < _tsThreshCount then
                                resourceFrame:SetActive(true, red, green, blue, a)
                            else
                                resourceFrame:SetActive(true, tr, tg, textBlock)
                            end
                        else
                            resourceFrame:SetActive(true, red, green, blue, a)
                        end
                        if resourceFrame._rechargeBar then
                            resourceFrame._rechargeBar:Hide()
                        end
                        if resourceFrame._cdText then
                            resourceFrame._cdText:SetText("")
                        end
                    else
                        -- Cooling-down rune: hide normal fill, show recharge bar.
                        -- The pip background is zeroed ONLY at full Fill
                        -- Opacity, where the frame-wide backdrop shows through
                        -- and carries the look. Below 100 that backdrop is
                        -- hidden by design and the composited per-pip bg
                        -- (PipBgColor: bar background under the overlay tint)
                        -- is the ONLY background a recharging rune has --
                        -- zeroing it left the un-recharged portion fully
                        -- transparent. SetActive(false) has just restored the
                        -- bg for the Fill Opacity case. Background on individual
                        -- pips stamps _fillOp = 1 for the same reason.
                        resourceFrame:SetActive(false, red, green, blue, a)
                        if not resourceFrame._fillOp then
                            resourceFrame._bg:SetAlpha(0)
                        end

                        -- Lazily create a StatusBar overlay for recharge progress
                        if not resourceFrame._rechargeBar then
                            local scrollBar = CreateFrame("StatusBar", nil, resourceFrame)
                            scrollBar:SetAllPoints(resourceFrame)
                            scrollBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
                            scrollBar:SetFrameLevel(resourceFrame:GetFrameLevel())
                            scrollBar:SetMinMaxValues(0, 1)
                            -- Apply the same bar texture if one is set
                            if resourceFrame._texKey then
                                local filePath =
                                    CludesUI.ResolveTexturePath(_G._CURB_BarTextures, resourceFrame._texKey, nil)
                                if filePath then
                                    scrollBar:SetStatusBarTexture(filePath)
                                end
                            end
                            resourceFrame._rechargeBar = scrollBar
                            if resourceFrame._blizzMask then
                                mod.ERB_MaskPip(resourceFrame, resourceFrame._blizzMask)
                            end
                        end

                        -- Recharge fill follows the pip orientation: a lazily
                        -- created StatusBar defaults to HORIZONTAL and persists
                        -- across orientation swaps. Same direction convention
                        -- as ApplyBarOrientation (VERTICAL_DOWN = reverse =
                        -- fills from the top). Change-guarded on the full
                        -- orientation token (up/down differ only in reverse).
                        if resourceFrame._rechargeOri ~= pipOri then
                            local vertPip = pipOri ~= "HORIZONTAL"
                            resourceFrame._rechargeBar:SetOrientation(vertPip and "VERTICAL" or "HORIZONTAL")
                            resourceFrame._rechargeBar:SetRotatesTexture(vertPip)
                            resourceFrame._rechargeBar:SetReverseFill(pipOri == "VERTICAL_DOWN" or pipOri == "VERTICAL")
                            resourceFrame._rechargeOri = pipOri
                        end

                        -- Compute recharge fraction (0 = just started, 1 = almost ready)
                        local frac = 0
                        local rStart, rDur = _runeStart[runeIdx], _runeDuration[runeIdx]
                        if rStart and rDur and rDur > 0 then
                            local elapsed = nowTime - rStart
                            frac = max(0, min(1, elapsed / rDur))
                        end
                        resourceFrame._rechargeBar:SetValue(frac)
                        -- Recharge color: custom color when enabled, otherwise 75%
                        -- brightness (subtle dim), matching threshold color when active
                        if secondaryCfg.runesCustomRecharge then
                            resourceFrame._rechargeBar:SetStatusBarColor(
                                secondaryCfg.runesRechargeR or 0.5,
                                secondaryCfg.runesRechargeG or 0.5,
                                secondaryCfg.runesRechargeB or 0.5,
                                secondaryCfg.runesRechargeA or 1
                            )
                        elseif runeUseThresh then
                            resourceFrame._rechargeBar:SetStatusBarColor(tr * 0.75, tg * 0.75, textBlock * 0.75, a)
                        else
                            resourceFrame._rechargeBar:SetStatusBarColor(red * 0.75, green * 0.75, blue * 0.75, a)
                        end
                        resourceFrame._rechargeBar:Show()
                        if secondaryCfg.useContinuousTexture then
                            PipTextureHelpers.DrawFill(resourceFrame, resourceFrame._rechargeBar)
                        end

                        -- Show duration text if Resource Text is enabled (DK runes use it for cooldown)
                        if resourceFrame._cdText then
                            local rem = _runeRemaining[runeIdx]
                            if secondaryCfg.showText and rem > 0 and rem < 999 then
                                resourceFrame._cdText:SetText(format("%d", ceil(rem)))
                            else
                                resourceFrame._cdText:SetText("")
                            end
                        end
                    end
                end
            end
        end
    elseif cachedSecondary.type == "bar" then
        -- Bar-style secondary (e.g. Devourer soul fragments, Elemental maelstrom, Brewmaster stagger)
        if classBar then
            local current, maxCount = 0, pointCap
            if powerKind == "SOUL_FRAGMENTS_DEVOURER" and CludesUI and CludesUI.GetSoulFragments then
                current, maxCount = CludesUI.GetSoulFragments()
                if not maxCount or maxCount <= 0 then
                    maxCount = pointCap
                end
            elseif powerKind == "MAELSTROM_BAR" then
                current = UnitPower("player", PT.MAELSTROM) or 0
                maxCount = UnitPowerMax("player", PT.MAELSTROM) or pointCap
                if issecretvalue and issecretvalue(maxCount) then
                    maxCount = pointCap
                end
                if maxCount <= 0 then
                    maxCount = pointCap
                end
            elseif powerKind == "INSANITY_BAR" then
                current = UnitPower("player", PT.INSANITY) or 0
                maxCount = UnitPowerMax("player", PT.INSANITY) or pointCap
                if issecretvalue and issecretvalue(maxCount) then
                    maxCount = pointCap
                end
                if maxCount <= 0 then
                    maxCount = pointCap
                end
            elseif powerKind == "FOCUS_BAR" then
                current = UnitPower("player", PT.FOCUS) or 0
                maxCount = UnitPowerMax("player", PT.FOCUS) or pointCap
                if issecretvalue and issecretvalue(maxCount) then
                    maxCount = pointCap
                end
                if maxCount <= 0 then
                    maxCount = pointCap
                end
            elseif powerKind == "LUNAR_POWER_BAR" then
                current = UnitPower("player", PT.LUNAR_POWER) or 0
                maxCount = UnitPowerMax("player", PT.LUNAR_POWER) or pointCap
                if issecretvalue and issecretvalue(maxCount) then
                    maxCount = pointCap
                end
                if maxCount <= 0 then
                    maxCount = pointCap
                end
            elseif powerKind == "BREWMASTER_STAGGER" then
                current = UnitStagger("player") or 0
                maxCount = UnitHealthMax("player") or 1
                local curTainted = issecretvalue and issecretvalue(current)
                local maxTainted = issecretvalue and issecretvalue(maxCount)
                -- stagger thresholds
                local staggerPct
                if not curTainted and not maxTainted and maxCount > 0 then
                    staggerPct = current / maxCount * 100
                    classBar._staggerPctCache = staggerPct
                else
                    -- Stagger / max health go SECRET intermittently in instanced
                    -- combat: reuse the last clean % so the threshold color PERSISTS
                    -- instead of flickering back to base fill, and re-applies even
                    -- if a rebuild reset the fill in that window.
                    staggerPct = classBar._staggerPctCache
                end
                if _buffActive then
                    local _sft = classBar:GetStatusBarTexture()
                    if _sft then
                        classBar._lastStaggerR, classBar._lastStaggerG, classBar._lastStaggerB =
                            red, green, blue
                        _sft:SetVertexColor(red, green, blue, a)
                    end
                elseif not secondaryCfg.darkTheme and staggerPct then
                    local trig, tcr, tcg, tcb = false, red, green, blue
                    if _tsBandOn then
                        local bandTex = FindCountBand(_tsBands, staggerPct, _tsBandReverse)
                        if bandTex then
                            trig, tcr, tcg, tcb = true, bandTex.r or red, bandTex.g or green, bandTex.b or blue
                        end
                    elseif _tsEntry then
                        local threshVal = _tsThreshCount or 30
                        local over
                        if _tsReverse then
                            over = staggerPct <= threshVal
                        else
                            over = staggerPct >= threshVal
                        end
                        if over then
                            trig, tcr, tcg, tcb = true, _tsR or red, _tsG or green, _tsB or blue
                        end
                    else
                        trig = true
                        if staggerPct >= 60 then
                            tcr, tcg, tcb = 1.0, 0.2, 0.2
                        elseif staggerPct >= 30 then
                            tcr, tcg, tcb = 1.0, 0.85, 0.2
                        else
                            tcr, tcg, tcb = 0.2, 0.8, 0.2
                        end
                    end
                    if _spTextInstead then
                        local lastR, lastG, lastB =
                            classBar._lastStaggerR, classBar._lastStaggerG, classBar._lastStaggerB
                        if not classBar._atlasFill and (lastR ~= red or lastG ~= green or lastB ~= blue) then
                            classBar._lastStaggerR, classBar._lastStaggerG, classBar._lastStaggerB =
                                red, green, blue
                            classBar:GetStatusBarTexture():SetVertexColor(red, green, blue, a)
                        end
                        colorText(true, trig, tcr, tcg, tcb, _spTextBaseR, _spTextBaseG, _spTextBaseB)
                    else
                        -- Fill = effective color (threshold/band or base), guarded.
                        local fr, fg, fb = red, green, blue
                        if trig then
                            fr, fg, fb = tcr, tcg, tcb
                        end
                        local lastR, lastG, lastB =
                            classBar._lastStaggerR, classBar._lastStaggerG, classBar._lastStaggerB
                        if not classBar._atlasFill and (lastR ~= fr or lastG ~= fg or lastB ~= fb) then
                            classBar._lastStaggerR, classBar._lastStaggerG, classBar._lastStaggerB =
                                fr, fg, fb
                            classBar:GetStatusBarTexture():SetVertexColor(fr, fg, fb, 1)
                        end
                    end
                end
                if maxTainted then
                    maxCount = pointCap
                end
                if not maxTainted and maxCount <= 0 then
                    maxCount = 1
                end
            elseif powerKind == "IGNOREPAIN_BAR" then
                -- Prot Ignore Pain. Preferred: the tracked-buff icon's stack count --
                -- IP caps at 30% max health, so 0-100 stacks are percent-of-cap, i.e.
                -- IP's own share with no foreign shield mixed in. It exists only while
                -- the user tracks IP in the CDM, so UnitGetTotalAbsorbs stays as the
                -- fallback: EVERY shield on the player, and secret, so IP cannot be
                -- subtracted out -- gated on IP being up, still over-reads in uptime.
                -- 190456 is restriction-flagged and GetPlayerAuraBySpellID returns
                -- NOTHING for it (field-probed): aura points are not an exact source.
                maxCount = UnitHealthMax("player")
                if (issecretvalue and issecretvalue(maxCount)) or not maxCount or maxCount <= 0 then
                    maxCount = pointCap
                else
                    maxCount = maxCount * IP.CAP
                end
                if IP.value and IP.viewerFS and IP.viewerFS:IsVisible() then
                    -- Kept for the value-mode threshold rescale below.
                    IP.stackAxis = maxCount
                    current, maxCount = IP.value, 100
                else
                    IP.stackAxis = nil
                    current = IP.Active() and (UnitGetTotalAbsorbs("player") or 0) or 0
                end
            end
            -- Brewmaster stagger ceiling
            local barMax = maxCount
            if powerKind == "BREWMASTER_STAGGER" then
                local ceil = secondaryCfg.staggerCeilingPercent or 100
                if ceil < 1 then
                    ceil = 1
                end
                barMax = maxCount * ceil / 100
            end
            -- Only call SetMinMaxValues if max actually changed (prevents flicker)
            local maxChanged = classBar._lastMaxC ~= barMax
            if maxChanged then
                classBar._lastMaxC = barMax
                classBar:SetMinMaxValues(0, barMax)
            end
            -- Reapply hash positions on a max change or the first valid layout
            -- (bar width can be 0 at BuildBars time, before layout settles).
            local barW = classBar:GetWidth()
            if
                barW > 0
                and (maxChanged or not classBar._hashApplied)
                and powerKind ~= "IGNOREPAIN_BAR"
            then
                classBar._hashApplied = true
                local _rtTsEntry = ResolveThresholdSpecEntry(secondaryCfg)
                local _rtTickStr = (_rtTsEntry and _rtTsEntry.hashValues ~= "") and _rtTsEntry.hashValues
                    or secondaryCfg.tickValues
                local _rtHW = _rtTsEntry and _rtTsEntry.hashWidth or 1
                local _rtHR = _rtTsEntry and _rtTsEntry.hashColorR or 1
                local _rtHG = _rtTsEntry and _rtTsEntry.hashColorG or 1
                local _rtHB = _rtTsEntry and _rtTsEntry.hashColorB or 1
                local _rtHA = _rtTsEntry and _rtTsEntry.hashColorA or 0.7
                local _rtHPct = _rtTsEntry and _rtTsEntry.hashMode == "percent"
                -- Devourer in Void Meta: hide any hash above 39.
                local _rtHashCap = (
                    powerKind == "SOUL_FRAGMENTS_DEVOURER"
                    and C_UnitAuras
                    and C_UnitAuras.GetPlayerAuraBySpellID(1217607)
                )
                        and 39
                    or nil
                ApplyResourceBarTicks(
                    classBar,
                    barMax,
                    _rtTickStr,
                    secondaryBarTicks,
                    _rtHW,
                    _rtHR,
                    _rtHG,
                    _rtHB,
                    _rtHA,
                    _rtHPct,
                    _rtHashCap
                )
            end
            -- Fill color (dark theme / class colored / custom). Brewmaster stagger
            -- uses threshold colors unless darkTheme is on. Bar-type resources
            -- (Maelstrom, Insanity) trigger at/above thresholdCount as a percent.
            if powerKind ~= "BREWMASTER_STAGGER" or secondaryCfg.darkTheme then
                local fillTex = classBar:GetStatusBarTexture()
                -- An active atlas fill is NEVER tinted: route every fill
                -- SetVertexColor below into the no-op sink. Text recoloring still
                -- runs; Ignore Pain / Devourer / Stagger can never be atlased.
                if fillTex and classBar._atlasFill then
                    fillTex = mod._atlasNoTint
                end
                if fillTex then
                    -- Hide Ignore Pain band/threshold overlays by default; the IP
                    -- branch below re-shows exactly the layers it needs.
                    if classBar._ipBandBars then
                        for _i = 1, #classBar._ipBandBars do
                            classBar._ipBandBars[_i]:Hide()
                        end
                    end
                    local pType = (powerKind == "MAELSTROM_BAR") and PT.MAELSTROM
                        or (powerKind == "INSANITY_BAR") and PT.INSANITY
                        or (powerKind == "FOCUS_BAR") and PT.FOCUS
                        or (powerKind == "LUNAR_POWER_BAR") and PT.LUNAR_POWER
                        or nil
                    if (_tsEntry or _tsBandOn) and pType and UnitPowerPercent then
                        -- ColorCurve + UnitPowerPercent: WoW evaluates the secret
                        -- value against the curve C-side. Default = threshold color
                        -- above value, fill below (builders warn when high);
                        -- thresholdReverse flips it for spenders (e.g. Hunter Focus)
                        -- that warn when low.
                        local colorCurve
                        local _bandOn, _bands, _bandMode, _bandRev =
                            _tsBandOn, _tsBands, _tsBandMode, _tsBandReverse
                        local _tsThreshPct = _tsThreshCount or 30
                        if _tsEntry and _tsEntry.thresholdMode == "value" and maxCount and maxCount > 0 then
                            _tsThreshPct = math.min(100, (_tsThreshCount or 30) / maxCount * 100)
                        end
                        local rvR, rvG, rvB = red, green, blue
                        if _spTextInstead then
                            rvR, rvG, rvB = _spTextBaseR, _spTextBaseG, _spTextBaseB
                        end
                        if _bandOn then
                            colorCurve =
                                GetBarBandCurve("secondary", _bands, _bandMode, maxCount, rvR, rvG, rvB, _bandRev)
                        elseif _tsReverse then
                            colorCurve = GetBarThresholdCurve(
                                rvR,
                                rvG,
                                rvB, -- fill/text color (above)
                                _tsR or 1,
                                _tsG or 0.2,
                                _tsB or 0.2, -- threshold color (below)
                                _tsThreshPct
                            )
                        else
                            colorCurve = GetBarThresholdCurve(
                                _tsR or 1,
                                _tsG or 0.2,
                                _tsB or 0.2, -- threshold color (above)
                                rvR,
                                rvG,
                                rvB, -- fill/text color (below)
                                _tsThreshPct
                            )
                        end
                        if _spTextInstead then
                            -- Fill stays at base; the count text carries the curve's
                            -- color (already threshold-above / text-base-below).
                            fillTex:SetVertexColor(red, green, blue, a)
                            if colorCurve then
                                local success, colorResult =
                                    pcall(UnitPowerPercent, "player", pType, false, colorCurve)
                                if success and colorResult and colorResult.GetRGBA then
                                    local cr, cg, callback = colorResult:GetRGBA()
                                    colorText(true, true, cr, cg, callback)
                                end
                            end
                        elseif colorCurve then
                            local success, colorResult =
                                pcall(UnitPowerPercent, "player", pType, false, colorCurve)
                            if success and colorResult and colorResult.GetRGBA then
                                fillTex:SetVertexColor(colorResult:GetRGBA())
                            else
                                fillTex:SetVertexColor(red, green, blue, a)
                            end
                        else
                            fillTex:SetVertexColor(red, green, blue, a)
                        end
                    elseif _tsEntry and powerKind == "SOUL_FRAGMENTS_DEVOURER" then
                        local threshVal = _tsThreshCount or 30
                        if _tsEntry.thresholdMode ~= "value" and maxCount and maxCount > 0 then
                            threshVal = maxCount * threshVal / 100
                        end
                        if _spTextInstead then
                            -- Fill at base; tint the count text when at/over the threshold.
                            fillTex:SetVertexColor(red, green, blue, a)
                            colorText(
                                true,
                                current >= threshVal,
                                _tsR or 1,
                                _tsG or 0.2,
                                _tsB or 0.2,
                                _spTextBaseR,
                                _spTextBaseG,
                                _spTextBaseB
                            )
                        elseif current >= threshVal then
                            fillTex:SetVertexColor(_tsR or 1, _tsG or 0.2, _tsB or 0.2, _tsA or 1)
                        else
                            fillTex:SetVertexColor(red, green, blue, a)
                        end
                    elseif
                        powerKind == "IGNOREPAIN_BAR"
                        and (_tsEntry or _tsBandOn)
                        and maxCount
                        and maxCount > 0
                    then
                        -- Ignore Pain is a bar but not a real power type and its
                        -- absorb value is secret in combat, so use the secret-safe
                        -- StatusBar-overlay technique (as Vengeance pips): the fill
                        -- texture is the "cell", each overlay repaints the visible fill.
                        local function _ipBound(to)
                            if _tsBandMode ~= "value" then
                                return maxCount * (to or 0) / 100
                            end
                            -- A value-mode bound is an absorb amount. On the stack axis
                            -- maxC is 0-100, so rescale it against the absorb-scale cap
                            -- (both clean: user config and max health).
                            if IP.stackAxis and IP.stackAxis > 0 then
                                return (to or 0) / IP.stackAxis * 100
                            end
                            return to or 0
                        end
                        IP.layerN = 0
                        if _tsBandOn and _tsBands and #_tsBands > 0 then
                            if _tsBandReverse then
                                -- "From"
                                IP.push(0, red, green, blue, a)
                                for k = 1, #_tsBands do
                                    local edge = _tsBands[k]
                                    IP.push(
                                        _ipBound(edge.to),
                                        edge.r or 1,
                                        edge.g or 1,
                                        edge.b or 1,
                                        edge.a or a
                                    )
                                end
                            else
                                -- "Up to"
                                local b1 = _tsBands[1]
                                IP.push(0, b1.r or 1, b1.g or 1, b1.b or 1, b1.a or a)
                                for k = 1, #_tsBands - 1 do
                                    local nb = _tsBands[k + 1]
                                    IP.push(
                                        _ipBound(_tsBands[k].to),
                                        nb.r or 1,
                                        nb.g or 1,
                                        nb.b or 1,
                                        nb.a or a
                                    )
                                end
                                IP.push(_ipBound(_tsBands[#_tsBands].to), red, green, blue, a)
                            end
                        elseif _tsEntry and _tsEntry.thresholdEnabled ~= false and _tsThreshCount then
                            local tv = (_tsEntry.thresholdMode == "value") and _tsThreshCount
                                or (maxCount * _tsThreshCount / 100)
                            if _tsReverse then
                                -- threshold color below the value, base fill at/above.
                                IP.push(0, _tsR or 1, _tsG or 0.2, _tsB or 0.2, _tsA or 1)
                                IP.push(tv, red, green, blue, a)
                            else
                                -- base fill below, threshold color at/above.
                                IP.push(0, red, green, blue, a)
                                IP.push(tv, _tsR or 1, _tsG or 0.2, _tsB or 0.2, _tsA or 1)
                            end
                        else
                            IP.push(0, red, green, blue, a)
                        end
                        -- Base layer paints the bar's own fill.
                        local _base = IP.layers[1]
                        fillTex:SetVertexColor(_base.r, _base.g, _base.b, _base.a)
                        local barList = classBar._ipBandBars
                        if not barList then
                            barList = {}
                            classBar._ipBandBars = barList
                        end
                        local owner = classBar._sb or classBar
                        local texKey = ERB.db
                                and ERB.db.profile
                                and ERB.db.profile.general
                                and ERB.db.profile.general.barTexture
                            or "none"
                        local texPath = CludesUI.ResolveTexturePath(
                            _G._CURB_BarTextures,
                            texKey,
                            "Interface\\Buttons\\WHITE8x8"
                        )
                        local isShown = 0
                        for li = 2, IP.layerN do
                            local L = IP.layers[li]
                            if L.step and L.step > 0 then
                                isShown = isShown + 1
                                local ob = barList[isShown]
                                if not ob then
                                    ob = CreateFrame("StatusBar", nil, owner)
                                    -- Anchors are constant to the fill texture; set once.
                                    ob:SetPoint("TOPLEFT", fillTex, "TOPLEFT", 0, 0)
                                    ob:SetPoint("BOTTOMRIGHT", fillTex, "BOTTOMRIGHT", 1, 0)
                                    barList[isShown] = ob
                                end
                                -- Texture/level change on config/rebuild, not per tick.
                                if ob._texPath ~= texPath then
                                    ob:SetStatusBarTexture(texPath)
                                    local _obt = ob:GetStatusBarTexture()
                                    if _obt then
                                        _obt:SetSnapToPixelGrid(false)
                                        _obt:SetTexelSnappingBias(0)
                                    end
                                    ob._texPath = texPath
                                    -- Blizzard Style: the layer rides the row's bar-shape mask
                                    -- (the bevel overlay sits above it by level).
                                    local rm = classFrame and classFrame._blizzBarMask
                                    if rm and _obt then
                                        mod.ERB_MaskTex(_obt, rm)
                                    end
                                end
                                local _lvl = owner:GetFrameLevel() + isShown
                                if ob._lvl ~= _lvl then
                                    ob:SetFrameLevel(_lvl)
                                    ob._lvl = _lvl
                                end
                                ob:SetMinMaxValues(L.step * 0.999, L.step)
                                ob:SetValue(current)
                                ob:SetStatusBarColor(L.r, L.g, L.b, L.a)
                                ob:Show()
                            end
                        end
                    else
                        fillTex:SetVertexColor(red, green, blue, a)
                    end
                end
            end
            -- Fill: eased only while the bar's Smooth Bars item is on (see the
            -- health handler note); a secret goes straight to the StatusBar too.
            classBar:SetValue(current)
            local tainted = issecretvalue and issecretvalue(current)
            if secondaryCfg.showText and classFrame._countText then
                local ct = classFrame._countText
                local percentSuffix = (secondaryCfg.showPercent == false) and "" or "%"
                -- Power-based bar resources treat "Show %" as a value<->percent
                -- switch: OFF (default) = bare current value, ON = percent
                -- (secret-safe via the ScaleTo100 declassifier, capped 0-100 by
                -- nature). Mode is identical in/out of instanced combat -- display
                -- must never flip with taint state. All modes use SetFormattedText,
                -- which renders a secret value's digits engine-side, so no Lua
                -- compare/concat ever touches the secret.
                local pType = (powerKind == "MAELSTROM_BAR") and PT.MAELSTROM
                    or (powerKind == "INSANITY_BAR") and PT.INSANITY
                    or (powerKind == "FOCUS_BAR") and PT.FOCUS
                    or (powerKind == "LUNAR_POWER_BAR") and PT.LUNAR_POWER
                    or nil
                if powerKind == "BREWMASTER_STAGGER" then
                    -- Stagger always shows a percentage of max health; "Show %"
                    -- only toggles the "%" sign here.
                    if not tainted then
                        local pct = maxCount > 0 and (current / maxCount * 100) or 0
                        ct:SetText(format("%d", pct) .. percentSuffix)
                    else
                        local cp = classBar._staggerPctCache
                        if cp then
                            ct:SetText(format("%d", cp) .. percentSuffix)
                        else
                            ct:SetText("")
                        end
                    end
                elseif powerKind == "IGNOREPAIN_BAR" then
                    -- Text is driven per-frame by IP.UpdateText. No-op here.
                elseif pType and secondaryCfg.showPercent and UnitPowerPercent then
                    -- Percent
                    local pct = UnitPowerPercent(
                        "player",
                        pType,
                        true,
                        CurveConstants and CurveConstants.ScaleTo100
                    ) or 0
                    ct:SetFormattedText("%d%%", pct)
                elseif pType then
                    -- Value: bare current for the power bars (no "/ max").
                    ct:SetFormattedText("%s", current)
                elseif secondaryCfg.showMaxStacks == false then
                    -- Current count only (Devourer "Show Max Stacks" off).
                    ct:SetFormattedText("%s", current)
                else
                    -- Current / max (Devourer default). SetFormattedText renders the
                    -- possibly-secret current alongside the clean max -- never a Lua
                    -- concat of a secret value.
                    ct:SetFormattedText("%s / %s", current, maxCount)
                end
            end
        end
    elseif cachedSecondary.type == "custom" or _ptsSecret then
        local current, maxCount = 0, pointCap
        local isSecret = false
        local _wcEngine = false
        if _ptsSecret then
            current = _ptsCur
            maxCount = pointCap
            isSecret = true
        elseif powerKind == "SOUL_FRAGMENTS_VENGEANCE" then
            -- Vengeance DH: GetSpellCastCount returns a SECRET value, uncomparable
            -- in Lua. Pass the raw value to StatusBar widgets embedded in each pip
            -- (SetMinMaxValues(i-1, i) + SetValue(secret)) which fill C-side.
            local rawCur = C_Spell and C_Spell.GetSpellCastCount and C_Spell.GetSpellCastCount(228477) or 0
            current = rawCur
            isSecret = true
            maxCount = 6
        elseif powerKind == "SOUL_FRAGMENTS" and CludesUI and CludesUI.GetSoulFragments then
            current, maxCount = CludesUI.GetSoulFragments()
            if not maxCount or maxCount <= 0 then
                maxCount = pointCap
            end
        elseif powerKind == "MAELSTROM_WEAPON" and CludesUI and CludesUI.GetMaelstromWeapon then
            current, maxCount = CludesUI.GetMaelstromWeapon()
            -- Enhance 5-bar mode: clamp visual to 5 pips
            if secondaryCfg.enhanceFiveBar and maxCount > 5 then
                maxCount = 5
            end
        elseif powerKind == "TIP_OF_THE_SPEAR" and CludesUI and CludesUI.GetTipOfTheSpear then
            current, maxCount = CludesUI.GetTipOfTheSpear()
        elseif powerKind == "WHIRLWIND_STACKS" or powerKind == "SWEEPING_STRIKES" then
            -- Engine slot owns the display (CludesUI_WarriorCharges): the
            -- true count fills the overlay bar C-side. Fall through the shared
            -- color chain below so the fill inherits the exact resolved color;
            -- the handoff before the render paths does the rest. Until the
            -- deferred build lands the row simply shows empty (the cast-count
            -- simulator is retired).
            -- BuildBars still lays the legacy gap-fill strips from the OLD pip
            -- grid (cumulative cell+gap pixels); the engine bar's separator
            -- ticks follow the fill's uniform fractions, so live strips
            -- double-line against them, drifting apart along the bar (worst
            -- with a wide Bar Spacing). These two powers never render pips,
            -- so the strips are never wanted; hide once when present.
            local gf = classFrame._gapFills
            if gf and gf[1] and gf[1]:IsShown() then
                for gi = 1, #gf do
                    gf[gi]:Hide()
                end
            end
            if mod.WC_EngineOn and mod.WC_EngineOn(powerKind) then
                _wcEngine = true
            else
                for i = 1, #pips do
                    if pips[i] then
                        pips[i]:Hide()
                    end
                end
                return
            end
        elseif powerKind == "ICICLES" then
            current = GetIcicleCount()
            maxCount = 5
        end
        -- For pips using class/resource color, prefer the per-spec resource color.
        -- skip only when the buff colors the fill
        if not (_buffActive and not _spTextInstead) then
            if secondaryCfg.resourceColored and not secondaryCfg.darkTheme then
                local rr, rg, rb = ERB.ResolveSecondaryResourceColor(powerKind)
                if rr then
                    red, green, blue = rr, rg, rb
                end
            elseif secondaryCfg.classColored ~= false and not secondaryCfg.darkTheme then
                local pc2 = POWER_COLORS[powerKind]
                if pc2 then
                    red, green, blue = pc2[1], pc2[2], pc2[3]
                elseif CludesUI and CludesUI.GetResourceColor then
                    local _, class = UnitClass("player")
                    local rc = CludesUI.GetResourceColor(class)
                    if rc then
                        red, green, blue = rc.r, rc.g, rc.b
                    end
                end
            end
        end

        -- Warrior charge powers: hand the module the fully resolved color on
        -- EVERY pass, engine-owned or not. Pre-build passes stash it, so the
        -- creation-window bake paints the painter's exact color -- under
        -- restriction that window is the ONLY legal color write into the slot
        -- subtree. Engine-owned passes then park the legacy pips and legacy
        -- count text (the engine slot carries its own) and stop before any
        -- value read.
        if mod.WC_Recolor and (powerKind == "WHIRLWIND_STACKS" or powerKind == "SWEEPING_STRIKES") then
            mod.WC_Recolor(powerKind, red, green, blue, a)
            -- Threshold/band settings ride along raw (already resolved above
            -- at this pass's existing cost); the engine module change-gates
            -- and renders them as fill-masked range strips -- no Lua count
            -- exists for these two powers, so this is the only threshold
            -- renderer they have.
            if mod.WC_Thresholds then
                mod.WC_Thresholds(
                    powerKind,
                    (_tsEntry and _tsEntry.thresholdMode) or secondaryCfg.thresholdMode,
                    _tsEntry and _tsThreshCount or nil,
                    _tsR,
                    _tsG,
                    _tsB,
                    _tsA,
                    _tsBandOn,
                    _tsBands,
                    _tsBandReverse,
                    _tsReverse
                )
            end
        end
        if _wcEngine then
            for i = 1, #pips do
                if pips[i] then
                    pips[i]:Hide()
                end
            end
            if classFrame._countText then
                classFrame._countText:SetText("")
            end
            return
        end
        if isSecret then
            -- Secret-value path: each pip is driven by a StatusBar overlay, which
            -- accepts the secret number natively -- a value inside [i-1, i] fills
            -- proportionally, giving a binary active/inactive look for integer
            -- counts. Threshold coloring adds a second overlay per pip.
            local _useThresh = _tsEntry and _tsThreshCount and _tsThreshCount > 0
            -- Multi-band: precompute each band's start count. A band overlay fills
            -- pip i when cur >= max(i, start_k); higher bands sit on higher frame
            -- levels so the topmost filled band wins.
            local _bandStarts
            if _tsBandOn and _tsBands then
                _bandStarts = {}
                if _tsBandReverse then
                    for k = 1, #_tsBands do
                        _bandStarts[k] = (_tsBands[k].to or 0)
                    end
                else
                    local previous = 0
                    for k = 1, #_tsBands do
                        _bandStarts[k] = previous + 1
                        previous = _tsBands[k].to or previous
                    end
                end
            end
            for i = 1, maxCount do
                local pipTex = pips[i]
                if pipTex and pipTex:IsShown() then
                    -- Lazily create a StatusBar overlay inside the pip
                    local texKey = ERB.db
                            and ERB.db.profile
                            and ERB.db.profile.general
                            and ERB.db.profile.general.barTexture
                        or "none"
                    local texPath = CludesUI.ResolveTexturePath(
                        _G._CURB_BarTextures,
                        texKey,
                        "Interface\\Buttons\\WHITE8x8"
                    )
                    if not pipTex._secretBar then
                        local scrollBar = CreateFrame("StatusBar", nil, pipTex)
                        scrollBar:SetAllPoints(pipTex._fill)
                        scrollBar:SetStatusBarTexture(texPath)
                        scrollBar._texPath = texPath
                        scrollBar:SetStatusBarColor(red, green, blue, a)
                        scrollBar:SetFrameLevel(pipTex:GetFrameLevel())
                        pipTex._secretBar = scrollBar
                        if pipTex._blizzMask then
                            mod.ERB_MaskPip(pipTex, pipTex._blizzMask)
                        end
                    elseif pipTex._secretBar._texPath ~= texPath then
                        -- A path swap mints a brand-new inner texture and runs the
                        -- parent's pixel-snap hook: NEVER re-set the current path.
                        pipTex._secretBar:SetStatusBarTexture(texPath)
                        pipTex._secretBar._texPath = texPath
                        if pipTex._blizzMask then
                            mod.ERB_MaskPip(pipTex, pipTex._blizzMask)
                        end
                    end
                    pipTex._secretBar:SetMinMaxValues(i - 1, i)
                    pipTex._secretBar:SetValue(current)
                    pipTex._secretBar:SetStatusBarColor(red, green, blue, a)
                    pipTex._secretBar:Show()

                    if _tsBandOn and _bandStarts then
                        -- Multi-band overlays: one StatusBar per band, higher bands
                        -- on top -> the topmost reached band colors the whole bar.
                        if not pipTex._bandBars then
                            pipTex._bandBars = {}
                        end
                        for k = 1, #_tsBands do
                            local bb = pipTex._bandBars[k]
                            if not bb then
                                bb = CreateFrame("StatusBar", nil, pipTex)
                                bb:SetAllPoints(pipTex._fill)
                                pipTex._bandBars[k] = bb
                            end
                            -- Texture/level change on config or rebuild, not per
                            -- tick: re-apply only on a real difference, or the hot
                            -- loop fires pips x bands redundant calls.
                            if bb._texPath ~= texPath then
                                bb:SetStatusBarTexture(texPath)
                                bb._texPath = texPath
                                if pipTex._blizzMask then
                                    mod.ERB_MaskPip(pipTex, pipTex._blizzMask)
                                end
                            end
                            local _lvl = pipTex:GetFrameLevel() + k
                            if bb._lvl ~= _lvl then
                                bb:SetFrameLevel(_lvl)
                                bb._lvl = _lvl
                            end
                            local lo = (i > _bandStarts[k]) and i or _bandStarts[k]
                            bb:SetMinMaxValues(lo - 1, lo)
                            bb:SetValue(current)
                            local bandTex = _tsBands[k]
                            bb:SetStatusBarColor(bandTex.r or 1, bandTex.g or 1, bandTex.b or 1, a)
                            bb:Show()
                        end
                        for k = #_tsBands + 1, #pipTex._bandBars do
                            pipTex._bandBars[k]:Hide()
                        end
                        if not _tsBandReverse then
                            -- "Up to" semantics: above the top band, revert to the base
                            -- fill color. A topmost overlay fills when cur > top band's `to`.
                            local _topTo = _tsBands[#_tsBands] and _tsBands[#_tsBands].to or 0
                            if not pipTex._bandResetBar then
                                local rb = CreateFrame("StatusBar", nil, pipTex)
                                rb:SetAllPoints(pipTex._fill)
                                pipTex._bandResetBar = rb
                            end
                            if pipTex._bandResetBar._texPath ~= texPath then
                                pipTex._bandResetBar:SetStatusBarTexture(texPath)
                                pipTex._bandResetBar._texPath = texPath
                                if pipTex._blizzMask then
                                    mod.ERB_MaskPip(pipTex, pipTex._blizzMask)
                                end
                            end
                            pipTex._bandResetBar:SetFrameLevel(pipTex:GetFrameLevel() + #_tsBands + 1)
                            local _rlo = (i > (_topTo + 1)) and i or (_topTo + 1)
                            pipTex._bandResetBar:SetMinMaxValues(_rlo - 1, _rlo)
                            pipTex._bandResetBar:SetValue(current)
                            pipTex._bandResetBar:SetStatusBarColor(red, green, blue, a)
                            pipTex._bandResetBar:Show()
                        elseif pipTex._bandResetBar then
                            -- "From" semantics: base fill below the first boundary is
                            -- handled by the base _secretBar; no reset overlay needed.
                            pipTex._bandResetBar:Hide()
                        end
                        if pipTex._secretThreshBar then
                            pipTex._secretThreshBar:Hide()
                        end
                    else
                        if pipTex._bandResetBar then
                            pipTex._bandResetBar:Hide()
                        end
                        if pipTex._bandBars then
                            for k = 1, #pipTex._bandBars do
                                pipTex._bandBars[k]:Hide()
                            end
                        end
                        -- Threshold overlay (drawn on top of the base fill)
                        -- Partial-only: pips below the threshold index never recolor.
                        local showThresh = _useThresh and not (_tsPartialOnly and i < _tsThreshCount)
                        if showThresh then
                            if not pipTex._secretThreshBar then
                                local textBlock = CreateFrame("StatusBar", nil, pipTex)
                                textBlock:SetAllPoints(pipTex._fill)
                                textBlock:SetStatusBarTexture(texPath)
                                textBlock._texPath = texPath
                                textBlock:SetFrameLevel(pipTex:GetFrameLevel() + 1)
                                pipTex._secretThreshBar = textBlock
                                if pipTex._blizzMask then
                                    mod.ERB_MaskPip(pipTex, pipTex._blizzMask)
                                end
                            elseif pipTex._secretThreshBar._texPath ~= texPath then
                                pipTex._secretThreshBar:SetStatusBarTexture(texPath)
                                pipTex._secretThreshBar._texPath = texPath
                                if pipTex._blizzMask then
                                    mod.ERB_MaskPip(pipTex, pipTex._blizzMask)
                                end
                            end
                            -- Fills only when cur >= max(i, threshCount): the pip is
                            -- active AND the threshold has been reached.
                            local tlo = (i > _tsThreshCount) and i or _tsThreshCount
                            pipTex._secretThreshBar:SetMinMaxValues(tlo - 1, tlo)
                            pipTex._secretThreshBar:SetValue(current)
                            pipTex._secretThreshBar:SetStatusBarColor(_tsR or 1, _tsG or 0.2, _tsB or 0.2, a)
                            pipTex._secretThreshBar:Show()
                        elseif pipTex._secretThreshBar then
                            pipTex._secretThreshBar:Hide()
                        end
                    end

                    -- Hide the normal fill; the StatusBar replaces it
                    pipTex._fill:Hide()

                    -- Fill Opacity in secret contexts, same look as the clean path:
                    -- region alpha on the overlay fills + bg anchored to the base
                    -- fill's moving edge so it covers only the empty remainder,
                    -- never reading the secret value. _fillOp is nil at 100.
                    -- Factor 1 (Background on individual pips) keeps the
                    -- colour alpha each SetStatusBarColor above wrote.
                    if pipTex._fillOp then
                        local _fo = pipTex._fillOp < 1 and pipTex._fillOp
                        local _sft = pipTex._secretBar:GetStatusBarTexture()
                        if _sft then
                            if _fo then
                                _sft:SetAlpha(_fo)
                            end
                            if not pipTex._sbgAnchored then
                                pipTex._sbgAnchored = true
                                pipTex._bg:ClearAllPoints()
                                pipTex._bg:SetPoint("TOPLEFT", _sft, "TOPRIGHT", 0, 0)
                                pipTex._bg:SetPoint("BOTTOMRIGHT", pipTex, "BOTTOMRIGHT", 0, 0)
                                pipTex._bg:SetAlpha(1)
                            end
                        end
                        local _stb = pipTex._secretThreshBar
                        if _fo and _stb and _stb:IsShown() then
                            local t = _stb:GetStatusBarTexture()
                            if t then
                                t:SetAlpha(_fo)
                            end
                        end
                        local _srb = pipTex._bandResetBar
                        if _fo and _srb and _srb:IsShown() then
                            local t = _srb:GetStatusBarTexture()
                            if t then
                                t:SetAlpha(_fo)
                            end
                        end
                        if _fo and pipTex._bandBars then
                            for k = 1, #pipTex._bandBars do
                                local bb = pipTex._bandBars[k]
                                if bb:IsShown() then
                                    local t = bb:GetStatusBarTexture()
                                    if t then
                                        t:SetAlpha(_fo)
                                    end
                                end
                            end
                        end
                    end
                    -- Keep the native secret-value and opacity paths intact.
                    if secondaryCfg.useContinuousTexture then
                        PipTextureHelpers.DrawFill(pipTex, pipTex._secretBar)
                        PipTextureHelpers.DrawFill(pipTex, pipTex._secretThreshBar)
                        PipTextureHelpers.DrawFill(pipTex, pipTex._bandResetBar)
                        if pipTex._bandBars then
                            for k = 1, #pipTex._bandBars do
                                PipTextureHelpers.DrawFill(pipTex, pipTex._bandBars[k])
                            end
                        end
                    end
                end
            end
            -- Count text: derive from UnitPowerPercent when it reads clean
            -- (raw secrets don't reliably render); else pass the raw value.
            if secondaryCfg.showText and classFrame._countText then
                local isShown = current
                if type(powerKind) == "number" and UnitPowerPercent and maxCount and maxCount > 0 then
                    local pct = UnitPowerPercent(
                        "player",
                        powerKind,
                        true,
                        CurveConstants and CurveConstants.ScaleTo100
                    )
                    if pct and not (issecretvalue and issecretvalue(pct)) then
                        isShown = math.floor(pct * maxCount / 100 + 0.5)
                    end
                end
                classFrame._countText:SetText(isShown)
            end
        else
            -- Clean-value path: normal boolean comparisons
            -- Hide any leftover secret StatusBar overlays
            for i = 1, maxCount do
                local p = pips[i]
                if p then
                    if p._secretBar then
                        p._secretBar:Hide()
                    end
                    if p._secretThreshBar then
                        p._secretThreshBar:Hide()
                    end
                    if p._bandResetBar then
                        p._bandResetBar:Hide()
                    end
                    if p._bandBars then
                        for k = 1, #p._bandBars do
                            p._bandBars[k]:Hide()
                        end
                    end
                    -- Leaving a secret Fill Opacity pass: restore the full-pip
                    -- bg anchor (SetActive owns bg visibility from here).
                    if p._sbgAnchored then
                        p._sbgAnchored = nil
                        p._bg:ClearAllPoints()
                        p._bg:SetAllPoints(p)
                    end
                end
            end
            -- Enhance 5-bar overflow: stacks 6-10 recolor pips 1-5
            local _enhFive = secondaryCfg.enhanceFiveBar and powerKind == "MAELSTROM_WEAPON"
            local _enhOverflow = _enhFive and current > 5
            local _enhOverCount = _enhOverflow and (current - 5) or 0
            local _enhRealCur = current -- preserve for count text
            local _enhOR, _enhOG, _enhOB =
                secondaryCfg.enhanceOverflowR or 1, secondaryCfg.enhanceOverflowG or 0.6, secondaryCfg.enhanceOverflowB or 0.2
            if _enhOverflow then
                current = 5
            end -- all 5 pips active when overflowing

            -- Direction: "From" (>=, default) or "Up to" (<=, thresholdReverse).
            local useThresh = _tsEntry
                and (
                    (_tsReverse and current <= _tsThreshCount)
                    or ((not _tsReverse) and (current >= _tsThreshCount or _enhRealCur >= _tsThreshCount))
                )
            local tr, tg, textBlock = _tsR, _tsG, _tsB
            -- Multi-band: whole bar takes the color of the band containing `cur`.
            if _tsBandOn and not _enhFive then
                local bandTex = FindCountBand(_tsBands, current, _tsBandReverse)
                if bandTex then
                    useThresh = true
                    tr, tg, textBlock = bandTex.r, bandTex.g, bandTex.b
                else
                    useThresh = false
                end
            end
            -- "Recolor text instead of bar": keep pips at base, route to the text.
            local _tiTrig = useThresh and true or false
            if _spTextInstead then
                useThresh = false
            end
            for i = 1, maxCount do
                if pips[i] and pips[i]:IsShown() then
                    local active = i <= current
                    -- if no threshold just use enhfive color
                    if active and _enhOverflow and i <= _enhOverCount and not useThresh then
                        pips[i]:SetActive(true, _enhOR, _enhOG, _enhOB)
                    elseif active and _enhOverflow and i <= _enhOverCount and useThresh then
                        -- if partial, make count 5 based
                        if _tsPartialOnly and i < (_tsThreshCount - current) then
                            pips[i]:SetActive(true, _enhOR, _enhOG, _enhOB)
                        else
                            pips[i]:SetActive(true, tr, tg, textBlock)
                        end
                    elseif active and useThresh then
                        if not _tsBandOn and _tsPartialOnly and i < _tsThreshCount then
                            pips[i]:SetActive(true, red, green, blue, a)
                        else
                            pips[i]:SetActive(true, tr, tg, textBlock)
                        end
                    else
                        pips[i]:SetActive(active, red, green, blue, a)
                    end
                end
            end
            -- Count text (use real count, not clamped)
            if secondaryCfg.showText and classFrame._countText then
                classFrame._countText:SetText(tostring(_enhRealCur or current))
                colorText(_spTextInstead, _tiTrig, tr, tg, textBlock, _spTextBaseR, _spTextBaseG, _spTextBaseB)
            end
        end
    else
        local current = _ptsCur or UnitPower("player", powerKind)
        -- Hide any secret StatusBar overlays left from a combat update that
        -- routed through the secret pip renderer above.
        for i = 1, pointCap do
            local p = pips[i]
            if p then
                if p._secretBar then
                    p._secretBar:Hide()
                end
                if p._secretThreshBar then
                    p._secretThreshBar:Hide()
                end
                if p._bandResetBar then
                    p._bandResetBar:Hide()
                end
                if p._bandBars then
                    for k = 1, #p._bandBars do
                        p._bandBars[k]:Hide()
                    end
                end
                -- Leaving a secret Fill Opacity pass: restore the full-pip
                -- bg anchor (SetActive owns bg visibility from here).
                if p._sbgAnchored then
                    p._sbgAnchored = nil
                    p._bg:ClearAllPoints()
                    p._bg:SetAllPoints(p)
                end
            end
        end
        -- Direction: "From" (>=, default) or "Up to" (<=, thresholdReverse).
        local useThresh = _tsEntry
            and (
                (_tsReverse and current <= _tsThreshCount)
                or ((not _tsReverse) and current >= _tsThreshCount)
            )
        local tr, tg, textBlock = _tsR, _tsG, _tsB
        -- Multi-band
        if _tsBandOn then
            local bandTex = FindCountBand(_tsBands, current, _tsBandReverse)
            if bandTex then
                useThresh = true
                tr, tg, textBlock = bandTex.r, bandTex.g, bandTex.b
            else
                useThresh = false
            end
        end
        local _tiTrig = useThresh and true or false
        if _spTextInstead then
            useThresh = false
        end

        -- Fractional resource detection
        local frac = 0
        local preciseCur = current
        if powerKind == PT.SOUL_SHARDS then
            -- Destruction warlock: UnitPower partial values work
            local specIdx = GetSpecialization()
            local specID = specIdx
                and C_SpecializationInfo
                and C_SpecializationInfo.GetSpecializationInfo(specIdx)
            if specID == 267 then
                local raw = UnitPower("player", powerKind, true)
                if raw and (not issecretvalue or not issecretvalue(raw)) then
                    preciseCur = raw / 10
                    frac = preciseCur - current
                end
            end
        elseif powerKind == PT.ESSENCE then
            -- Evoker Essence: timer-based recharge (UnitPower partial doesn't work)
            local nowTime = GetTime()
            local maxE = UnitPowerMax("player", PT.ESSENCE) or pointCap
            if issecretvalue and issecretvalue(maxE) then
                maxE = pointCap
            end

            -- Detect pip gain/loss and reset the timer
            if _essenceLastCount == nil then
                _essenceLastCount = current
            end
            if current ~= _essenceLastCount then
                if current < maxE then
                    _essenceTickDur = mod.EssenceTickDuration()
                    _essenceNextTick = nowTime + _essenceTickDur
                else
                    _essenceNextTick = nil
                end
                _essenceLastCount = current
            end

            -- If below max and no timer running, start one
            if current < maxE and not _essenceNextTick then
                _essenceTickDur = mod.EssenceTickDuration()
                _essenceNextTick = nowTime + _essenceTickDur
            end

            -- At max: clear timer
            if current >= maxE then
                _essenceNextTick = nil
            end

            -- Compute fill fraction for the recharging pip
            if _essenceNextTick and _essenceTickDur > 0 then
                local remaining = max(0, _essenceNextTick - nowTime)
                frac = 1 - (remaining / _essenceTickDur)
                frac = max(0, min(1, frac))
                preciseCur = current + frac
            end
        end

        -- Charged combo points (e.g. Supercharger talent)
        local chargedSet
        if powerKind == PT.COMBO then
            local func = GetUnitChargedPowerPoints
            if func then
                local pts = func("player")
                if pts and #pts > 0 then
                    chargedSet = {}
                    for _, position in ipairs(pts) do
                        chargedSet[position] = true
                    end
                end
            end
        end
        local cr, cg, callback, ca = secondaryCfg.chargedR or 0.44, secondaryCfg.chargedG or 0.77, secondaryCfg.chargedB or 1.00, secondaryCfg.chargedA or 1

        for i = 1, pointCap do
            if pips[i] and pips[i]:IsShown() then
                local active = i <= current
                if chargedSet and chargedSet[i] then
                    if active then
                        pips[i]:SetActive(true, cr, cg, callback, ca)
                    else
                        pips[i]:SetActive(true, cr * 0.5, cg * 0.5, callback * 0.5, ca)
                    end
                elseif active and useThresh then
                    if not _tsBandOn and _tsPartialOnly and i < _tsThreshCount then
                        pips[i]:SetActive(true, red, green, blue, a)
                    else
                        pips[i]:SetActive(true, tr, tg, textBlock)
                    end
                else
                    pips[i]:SetActive(active, red, green, blue, a)
                end
                -- Hide any leftover partial-fill overlay on non-fractional pips
                if pips[i]._rechargeBar then
                    pips[i]._rechargeBar:Hide()
                end
            end
        end

        -- Partial pip fill for fractional resources (reuses DK rune recharge pattern)
        if frac > 0 and current < pointCap and pips[current + 1] and pips[current + 1]:IsShown() then
            local nextPip = pips[current + 1]
            if not nextPip._rechargeBar then
                local scrollBar = CreateFrame("StatusBar", nil, nextPip)
                scrollBar:SetAllPoints(nextPip)
                scrollBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
                scrollBar:SetFrameLevel(nextPip:GetFrameLevel())
                scrollBar:SetMinMaxValues(0, 1)
                if nextPip._texKey then
                    local filePath = CludesUI.ResolveTexturePath(_G._CURB_BarTextures, nextPip._texKey, nil)
                    if filePath then
                        scrollBar:SetStatusBarTexture(filePath)
                    end
                end
                nextPip._rechargeBar = scrollBar
                if nextPip._blizzMask then
                    mod.ERB_MaskPip(nextPip, nextPip._blizzMask)
                end
            end
            -- Reused overlays follow orientation changes, as rune recharge fills do.
            local pipOri = secondaryCfg.pipOrientation or "HORIZONTAL"
            if nextPip._rechargeOri ~= pipOri then
                Inner.ApplyBarOrientation(
                    nextPip._rechargeBar,
                    pipOri == "VERTICAL" and "VERTICAL_DOWN" or pipOri
                )
                nextPip._rechargeOri = pipOri
            end
            nextPip._rechargeBar:SetValue(frac)
            -- Partial generator (Evoker/Lock): color the filling pip like the full
            -- ones -- the threshold/band color when it applies to this slot (index
            -- cur+1), else the base color. Optionally dimmed so it still reads
            -- as "recharging" rather than a completed pip.
            local fr, fg, fb = red, green, blue
            local fi = current + 1
            if useThresh and not (not _tsBandOn and _tsPartialOnly and fi < _tsThreshCount) then
                fr, fg, fb = tr, tg, textBlock
            end
            local shade = secondaryCfg.darkenPartialPips == false and 1 or 0.75
            nextPip._rechargeBar:SetStatusBarColor(fr * shade, fg * shade, fb * shade, a)
            nextPip._rechargeBar:Show()
            if secondaryCfg.useContinuousTexture then
                PipTextureHelpers.DrawFill(nextPip, nextPip._rechargeBar)
            end
        end

        if secondaryCfg.showText and classFrame._countText then
            if frac > 0 and powerKind ~= PT.ESSENCE then
                classFrame._countText:SetText(format("%.1f", preciseCur))
            else
                classFrame._countText:SetText(tostring(current))
            end
            colorText(_spTextInstead, _tiTrig, tr, tg, textBlock, _spTextBaseR, _spTextBaseG, _spTextBaseB)
        end
    end
    -- Buff + recolor text instead
    if _buffActive and _spTextInstead and classFrame and classFrame._countText then
        classFrame._countText:SetTextColor(_bfr, _bfg, _bfb, 0.9)
    end
end

-- Visibility & combat fade
local function ShouldShowSecondary()
    local secondaryCfg = _G._CURB_ResolveSecondaryCfg()
    -- Check visibility options first
    if CludesUI.CheckVisibilityOptions(secondaryCfg) then
        return false
    end
    -- Multi-select / dragonriding path (nil = legacy single mode below)
    if CludesUI and CludesUI.EvalVisibilityExtended then
        local st = ERB._visState
        if not st then
            st = {}
            ERB._visState = st
        end
        local inRaid = IsInRaid and IsInRaid() or false
        st.inCombat = isInCombat
        st.inRaid = inRaid
        st.inParty = not inRaid and (IsInGroup and IsInGroup() or false)
        local ext = CludesUI.EvalVisibilityExtended(secondaryCfg, "visibility", st, CludesUI.VIS_CAPS_DEFAULT)
        if ext ~= nil then
            return ext
        end
    end
    local visible = secondaryCfg.visibility
    if visible == "always" then
        return true
    end
    if visible == "never" then
        return false
    end
    if visible == "mouseover" then
        return "mouseover"
    end
    if visible == "combat" or visible == "in_combat" then
        return isInCombat
    end
    if visible == "out_of_combat" then
        return not isInCombat
    end
    if visible == "target" then
        return UnitExists("target") and UnitCanAttack("player", "target")
    end
    if visible == "in_raid" then
        return IsInRaid and IsInRaid() or false
    end
    if visible == "in_party" then
        local inRaid = IsInRaid and IsInRaid() or false
        return not inRaid and (IsInGroup and IsInGroup() or false)
    end
    if visible == "solo" then
        return not (IsInRaid and IsInRaid()) and not (IsInGroup and IsInGroup())
    end
    return true
end

local function ShouldShowBar(barProfile)
    -- Check visibility options first
    if CludesUI.CheckVisibilityOptions(barProfile) then
        return false
    end
    -- Multi-select / dragonriding path (nil = legacy single mode below)
    if CludesUI and CludesUI.EvalVisibilityExtended then
        local st = ERB._visState
        if not st then
            st = {}
            ERB._visState = st
        end
        local inRaid = IsInRaid and IsInRaid() or false
        st.inCombat = isInCombat
        st.inRaid = inRaid
        st.inParty = not inRaid and (IsInGroup and IsInGroup() or false)
        local ext = CludesUI.EvalVisibilityExtended(barProfile, "visibility", st, CludesUI.VIS_CAPS_DEFAULT)
        if ext ~= nil then
            return ext
        end
    end
    local visible = barProfile.visibility or "always"
    if visible == "always" then
        return true
    end
    if visible == "never" then
        return false
    end
    if visible == "mouseover" then
        return "mouseover"
    end
    if visible == "combat" or visible == "in_combat" then
        return isInCombat
    end
    if visible == "out_of_combat" then
        return not isInCombat
    end
    if visible == "target" then
        return UnitExists("target") and UnitCanAttack("player", "target")
    end
    if visible == "in_raid" then
        return IsInRaid and IsInRaid() or false
    end
    if visible == "in_party" then
        local inRaid = IsInRaid and IsInRaid() or false
        return not inRaid and (IsInGroup and IsInGroup() or false)
    end
    if visible == "solo" then
        return not (IsInRaid and IsInRaid()) and not (IsInGroup and IsInGroup())
    end
    return true
end

-- Shared with CUI_ResourceBars_SwingTimer.lua: the swing timer runs the same
-- Visibility checklist as the class/power/health bars.
mod.ShouldShowBar = ShouldShowBar

-- Show When Missing: a step curve on the engine-side percent reveals a rule-hidden
-- bar below full. The curve result can be secret (for health it always is), so it
-- drives a wrapper the bar is parented to. A bar shown outright and faded out of
-- combat takes the same wrapper: its curve rests at the faded opacity over the
-- normal one (ns.ERB_MissingLiftFloor), lifting the fade below full. Either way a
-- revealed bar shows at its normal opacity (ns.ERB_MissingBarAlpha), the wrapper
-- hiding or fading it at full. A secret wrapper alpha makes the bar's own
-- GetAlpha read secret too: never compare the Health or Power bar's alpha
-- without issecretvalue (CludesUI.SetElementVisibility checks it). Built on
-- first use. Only resources that rest at full count; rage and the like rest at
-- empty.
local MISSING_POWERS = { [PT.MANA] = true, [PT.ENERGY] = true, [PT.FOCUS] = true }

function mod.ERB_MissingWanted(conf, powerKind)
    if not conf then
        return false
    end
    if powerKind then
        if not MISSING_POWERS[powerKind] then
            return false
        end
        if powerKind == PT.MANA then
            local mx = UnitPowerMax("player", PT.MANA)
            if not mx or issecretvalue(mx) or mx <= 0 then
                return false
            end
        end
    end
    return (CludesUI.VisOverrideValue(conf) or conf.visibility) ~= "never"
end

-- Step curves: 1 below full, then the bar's rest value at full. A rule-hidden
-- reveal rests at 0 on one shared curve; a fade lift rests at its floor on a
-- curve of the bar's own, re-pointed only when that floor changes.
local missingHideCurve
local function MissingCurve(barFrame)
    local floor = barFrame._missFloor
    if not floor then
        if not missingHideCurve then
            missingHideCurve = C_CurveUtil.CreateCurve()
            missingHideCurve:SetType(Enum.LuaCurveType.Step)
            missingHideCurve:AddPoint(0, 1)
            missingHideCurve:AddPoint(1, 0)
        end
        return missingHideCurve
    end
    local c = barFrame._missLiftCurve
    if not c then
        c = C_CurveUtil.CreateCurve()
        c:SetType(Enum.LuaCurveType.Step)
        barFrame._missLiftCurve = c
    end
    if barFrame._missLiftAt ~= floor then
        barFrame._missLiftAt = floor
        c:ClearPoints()
        c:AddPoint(0, 1)
        c:AddPoint(1, floor)
    end
    return c
end

-- Fade Out of Combat on a bar shown outright: the value its wrapper rests at
-- while the resource is full (the faded opacity over the normal one); nil in
-- combat, with the fade off, or for a fade that does not dim below normal.
function mod.ERB_MissingLiftFloor(conf)
    if isInCombat or not (conf and conf.oocFadeEnabled) then
        return nil
    end
    local normal, faded = conf.barAlpha or 1, conf.oocAlpha or 0.5
    if normal <= 0 or faded >= normal then
        return nil
    end
    return faded / normal
end

-- The Health or Power bar's own alpha: its normal opacity while Show When
-- Missing reveals it (the wrapper hides or fades it at full), else the
-- ns.ResolveBarAlpha answer.
function mod.ERB_MissingBarAlpha(barFrame, conf)
    if barFrame and barFrame._missLive then
        return (conf and conf.barAlpha) or 1
    end
    return mod.ResolveBarAlpha(conf)
end

function mod.ERB_MissingPaint(barFrame)
    local colorCurve = MissingCurve(barFrame)
    local pt = barFrame._missPower
    local a
    if pt then
        a = UnitPowerPercent("player", pt, false, colorCurve)
    else
        a = UnitHealthPercent("player", false, colorCurve)
    end
    barFrame._missWrap:SetAlpha(a)
end

-- SetParent resets the frame level; the strata follows the new parent (the
-- wrapper takes the bar's own on entry, so an inherited strata is never pinned).
local function MissingRehome(barFrame, hostFrame)
    local level = barFrame:GetFrameLevel()
    barFrame:SetParent(hostFrame)
    barFrame:SetFrameLevel(level)
end

-- live: reveal active for this bar; powerType nil means the health bar. home:
-- the parent to return to when the reveal ends (nil keeps the wrapper). park:
-- held in the wrapper at alpha 0 instead (the druid strip while the Power Bar
-- is revealed on energy with Show When Mana Missing off).
function mod.ERB_MissingApply(barFrame, live, powerKind, home, park, floor)
    local wid = barFrame._missWrap
    if not live and not park then
        barFrame._missLive, barFrame._missParked, barFrame._missFloor = nil, nil, nil
        if wid then
            wid:SetAlpha(1)
        end
        local hgt = barFrame._missHome
        if hgt and barFrame:GetParent() ~= hgt then
            MissingRehome(barFrame, hgt)
        end
        return
    end
    if not wid then
        wid = CreateFrame("Frame", nil, mainFrame)
        wid:SetAllPoints(mainFrame)
        barFrame._missWrap = wid
    end
    barFrame._missHome = home
    if barFrame:GetParent() ~= wid then
        wid:SetFrameStrata(barFrame:GetFrameStrata())
        MissingRehome(barFrame, wid)
    end
    if park then
        barFrame._missLive, barFrame._missParked = nil, true
        wid:SetAlpha(0)
        return
    end
    barFrame._missParked = nil
    barFrame._missLive = true
    barFrame._missFloor = floor
    barFrame._missPower = powerKind
    mod.ERB_MissingPaint(barFrame)
end

-- The druid mana strip (a child of the Power Bar) on its own Show When Mana
-- Missing curve. mode "mana": while the visibility rules hide the Power Bar, or,
-- with a lift floor, while a Power Bar shown outright is faded out of combat;
-- "park": held out of sight while an energy reveal shows the Power Bar (its
-- anchor edge handed back); nil: back under the Power Bar. Out of its wrapper it
-- no longer inherits the Power Bar's alpha, so its own is applied directly.
function mod.ERB_MissingHost(pb, primaryCfg, mode, floor)
    local hgt = mode and mod.FDM_Host() or pb._missHost
    if not hgt then
        return
    end
    pb._missHost = hgt
    if mode == "mana" then
        mod.ERB_MissingApply(hgt, true, PT.MANA, pb, nil, floor)
        hgt:SetAlpha(mod.ERB_MissingBarAlpha(hgt, primaryCfg))
    elseif mode == "park" then
        mod.ERB_MissingApply(hgt, false, nil, pb, true)
    elseif hgt._missLive or hgt._missParked then
        mod.ERB_MissingApply(hgt, false)
        hgt:SetAlpha(1)
    end
    mod.FDM_Parked(mode == "park")
end

-- WoW Forever Spell Cost Prediction host (CludesUI_SpellCostPrediction.lua,
-- nil off Forever): the power type the Power Bar shows, the segment's color at
-- the bar's Fill Opacity, and the Blizzard Style bar-shape mask for the
-- segment's fill. The segment sits one level above the inner bar, where the
-- druid mana strip's Inside mode draws: a frame at the inner bar's own level
-- is covered by its fill (see the hash tick overlay). Read on a cast start and
-- by a repeat attach during one, never per power event.
if CludesUI.SpellCostPrediction then
    mod.ERB_COST_HOST = {
        PowerType = function()
            return cachedPrimary
        end,
        Color = function()
            local primaryCfg = _G._CURB_ResolvePowerCfg()
            local red, green, b = CludesUI.SpellCostPrediction.Color(primaryCfg)
            return red, green, b, ((primaryCfg and primaryCfg.fillOpacity) or 100) / 100
        end,
        Mask = function()
            return mainBar and mainBar._blizzBarMask
        end,
    }
end

local function UpdateVisibility()
    -- Swing timer (Forever only) rides every visibility edge this module sees;
    -- a no-op until the feature is on.
    if mod.ST_UpdateVisibility then
        mod.ST_UpdateVisibility()
    end
    if not mainFrame then
        return
    end

    -- Main frame always shown
    mainFrame:Show()
    mainFrame:SetAlpha(1)

    local inVehicle = ERB._inVehicle

    -- Hover-eligibility flags for the shared mouseover poll: a bar evaluating to
    -- "mouseover" stays hidden here and is revealed by the poll proxies
    -- (registered at setup) while the cursor is over it.
    ERB._moEligible = ERB._moEligible or {}

    -- Classic "Border Around All" membership: a bar shown outright and not
    -- riding the cursor (a mouseover bar is revealed on its own, so it keeps
    -- its own frame). Recorded only while the setting is on or the group
    -- still stands.
    local grp = mod._erbGroupOn or mod._erbGroupActive
    if grp then
        mod._erbGrpH, mod._erbGrpP, mod._erbGrpS = false, false, false
    end

    -- Health bar visibility
    if health then
        local healthCfg = _G._CURB_ResolveHealthCfg()
        local avail = healthCfg
            and healthCfg.enabled
            and not IsSpecDisabled(healthCfg)
            and not _G._CURB_BarHiddenByForm(healthCfg)
            and not inVehicle
        local visible = avail and ShouldShowBar(healthCfg)
        ERB._moEligible.health = (visible == "mouseover")
        -- Show When Health Missing: reveals a rule-hidden bar below full, and
        -- lifts the out-of-combat fade of one shown outright (rest at the fade).
        local wanted = avail and healthCfg.showWhenMissing and mod.ERB_MissingWanted(healthCfg)
        local missing = wanted and visible == false
        local lift = wanted and visible == true and mod.ERB_MissingLiftFloor(healthCfg) or nil
        -- A lifted bar's opacity follows its health: no shared-opacity group member.
        if grp then
            mod._erbGrpH = (visible == true) and not health._erbMouseTrack and not lift
        end
        if missing or lift or health._missLive then
            mod.ERB_MissingApply(health, (missing or lift) and true or false, nil, nil, nil, lift)
        end
        if missing then
            visible = true
        end
        if visible == true then
            health:Show()
            CludesUI.SetElementVisibility(health, true)
            health:SetAlpha(mod.ERB_MissingBarAlpha(health, healthCfg))
        else
            CludesUI.SetElementVisibility(health, false)
        end
    end

    -- Power bar visibility
    if mainBar then
        local primaryCfg = _G._CURB_ResolvePowerCfg()
        local secondaryCfg = ERB.db.profile.secondary
        -- cachedPrimary is also checked: specs with no primary power (BM/MM Hunter)
        -- hide the power bar even when it is enabled in settings. "Hide Power Bar if
        -- Resource" applies only while the Class Resource is on: its toggle is greyed
        -- out otherwise, and a WoW Forever druid has combo points in Cat Form alone.
        local hidePower = secondaryCfg and secondaryCfg.hidePowerIfResource and secondaryCfg.enabled ~= false and cachedSecondary
        local avail = not hidePower
            and primaryCfg
            and primaryCfg.enabled ~= false
            and not IsSpecDisabled(primaryCfg)
            and not _G._CURB_BarHiddenByForm(primaryCfg)
            and cachedPrimary
            and not inVehicle
        local visible = avail and ShouldShowBar(primaryCfg)
        ERB._moEligible.primary = (visible == "mouseover")
        local pt = avail and cachedPrimary
        local ruleHidden = avail and visible == false
        -- One toggle per resource the bar can show; Mana also covers the druid
        -- strip below. Each reveals a rule-hidden bar below full, and lifts the
        -- out-of-combat fade of one shown outright, as on the Health bar.
        local barFlag
        if pt == PT.MANA then
            barFlag = primaryCfg.showManaWhenMissing
        else
            barFlag = primaryCfg and primaryCfg.showWhenMissing
        end
        local wanted = avail and barFlag and type(pt) == "number" and mod.ERB_MissingWanted(primaryCfg, pt)
        local missing = wanted and ruleHidden
        local lift = wanted and visible == true and mod.ERB_MissingLiftFloor(primaryCfg) or nil
        if grp then
            mod._erbGrpP = (visible == true) and not mainBar._erbMouseTrack and not lift
        end
        if missing or lift or mainBar._missLive then
            mod.ERB_MissingApply(mainBar, (missing or lift) and true or false, pt, nil, nil, lift)
        end
        if missing then
            visible = true
        end
        local strip = mod.FDM_Host and mod.FDM_Host()
        local manaWanted = strip and avail and primaryCfg.showManaWhenMissing and mod.ERB_MissingWanted(primaryCfg, PT.MANA)
        local hostMode, hostLift
        if strip and ruleHidden then
            if manaWanted then
                hostMode = "mana"
            elseif missing then
                hostMode = "park"
            end
        elseif manaWanted and visible == true then
            hostLift = mod.ERB_MissingLiftFloor(primaryCfg)
            if hostLift then
                hostMode = "mana"
            end
        end
        if hostMode or mainBar._missHost then
            mod.ERB_MissingHost(mainBar, primaryCfg, hostMode, hostLift)
        end
        if visible == true then
            mainBar:Show()
            CludesUI.SetElementVisibility(mainBar, true)
            mainBar:SetAlpha(mod.ERB_MissingBarAlpha(mainBar, primaryCfg))
        else
            CludesUI.SetElementVisibility(mainBar, false)
        end
        -- WoW Forever mana regen spark (CludesUI_ManaRegenSpark.lua): attached
        -- while this bar can show, mouseover included so a hover reveal finds it
        -- running. Every BuildBars is followed by this pass, so attaching here
        -- also lays the spark out from the orientation BuildBars applied.
        if CludesUI.ManaRegenSpark then
            if (visible == true or visible == "mouseover") and primaryCfg.manaRegenSpark then
                CludesUI.ManaRegenSpark.Attach("erb", mainBar._sb, primaryCfg.manaRegenSparkMode == "ticks")
            else
                CludesUI.ManaRegenSpark.Detach("erb")
            end
        end
        -- WoW Forever Spell Cost Prediction: attached on the same verdict while
        -- the bar shows mana, so a druid in Bear or Cat Form (or a class with
        -- no mana on a shared profile) hears no cast events. Every form change
        -- refreshes cachedPrimary before this pass.
        if CludesUI.SpellCostPrediction then
            if
                (visible == true or visible == "mouseover")
                and primaryCfg.powerCostPrediction
                and cachedPrimary == PT.MANA
            then
                CludesUI.SpellCostPrediction.Attach("erb", mainBar._sb, mod.ERB_COST_HOST)
            else
                CludesUI.SpellCostPrediction.Detach("erb")
            end
        end
        -- WoW Forever druid mana bar: its mana events follow this verdict.
        if mod.FDM_Visibility then
            local fdmVis = visible
            if hostMode == "mana" then
                fdmVis = true
            elseif hostMode == "park" then
                fdmVis = false
            end
            mod.FDM_Visibility(fdmVis)
        end
    end

    -- Secondary resource visibility + ooc alpha
    if classFrame then
        local secondaryCfg = _G._CURB_ResolveSecondaryCfg()
        local visible = secondaryCfg
            and secondaryCfg.enabled ~= false
            and not IsSpecDisabled(secondaryCfg)
            and not _G._CURB_BarHiddenByForm(secondaryCfg)
            and cachedSecondary
            and not inVehicle
            and ShouldShowSecondary()
        ERB._moEligible.secondary = (visible == "mouseover")
        -- Blizzard Class Resource Art: the host holding Blizzard's frame takes
        -- this visibility; while that frame stands in for the pips the slot
        -- stays at zero alpha and out of the Border Around All group.
        local artOn, artHost = mod._erbArtOn, mod._erbArtHost
        if grp then
            mod._erbGrpS = (visible == true) and not artOn and not classFrame._erbMouseTrack
        end
        if artHost then
            if visible == true then
                CludesUI.SetElementVisibility(artHost, true)
                artHost:SetAlpha(mod.ResolveBarAlpha(secondaryCfg))
            else
                CludesUI.SetElementVisibility(artHost, false)
            end
        end
        if visible == true and not artOn then
            classFrame:Show()
            CludesUI.SetElementVisibility(classFrame, true)
            classFrame:SetAlpha(mod.ResolveBarAlpha(secondaryCfg))
        else
            CludesUI.SetElementVisibility(classFrame, false)
        end
    end

    if grp then
        mod.ERB_GroupEval()
    end
end

-- Subsystem tickers. There is NO frame-rate OnUpdate multiplexer:
--  * Value fills (health/primary/secondary) are EVENT-DRIVEN -- handlers call
--    SetValue(v) and, while the bar's Smooth Bars item is on, the engine
--    animates the ease (ERB:ApplySmoothing), zero per-frame Lua.
--    Threshold/band coloring rides the same events; never add a color poll.
--  * Genuinely time-based jobs each ride their own fixed-rate anim ticker
--    (CludesUI.Tick.NewAnimTicker): the C engine fires OnLoop at the
--    configured rate and sleeps between fires, so no per-frame dispatch exists;
--    each ticker self-stops the moment its job settles.
--  * ns.ArmTick() (after every event and from ApplyAll) starts whichever
--    tickers the current state needs. Arming is deliberately indiscriminate: a
--    redundant Start is one IsPlaying check, a missed arm is a frozen bar.
-- Frames passed to NewAnimTicker are created HERE at file scope so the engine
-- bills the work to ResourceBars (frame-birth attribution rule).

-- Ebon Might drain (Aug Evoker; the engine slot owns the countdown when present).
-- 20 Hz drain + text; with the Power Bar's Smooth Bars item on, the engine eases
-- the fill between fires.
-- Re-armed by UNIT_AURA via ns.ArmTick.
mod.EMTick = CludesUI.Tick.NewAnimTicker(CreateFrame("Frame"), function()
    if mod.EMB121_Owns then
        return
    end
    if cachedPrimary ~= "EBON_MIGHT" then
        return
    end
    if not (mainBar and mainBar:IsShown() and mainBar:GetAlpha() > 0) then
        return
    end
    local remaining = (_ebonMightExpiry > 0) and max(0, _ebonMightExpiry - GetTime()) or 0
    mainBar:SetValue(remaining)
    local primaryCfg = _G._CURB_ResolvePowerCfg()
    if primaryCfg and primaryCfg.textFormat and primaryCfg.textFormat ~= "none" then
        local formatStr = primaryCfg.textFormat
        local percentSuffix = (primaryCfg.showPercent == false) and "" or "%"
        local pct = format("%d", remaining / EBON_MIGHT_DURATION * 100)
        local timeText = remaining > 0 and format("%.1f", remaining) or "0"
        local txt
        if formatStr == "perpp" then
            txt = pct .. percentSuffix
        elseif formatStr == "both" then
            txt = timeText .. " | " .. pct .. percentSuffix
        else
            txt = timeText
        end
        mainBar._text:SetText(txt)
    end
    return remaining > 0
end, 0.05)

-- Guardian Ironfur / Prot Ignore Pain moving-hash motion: the only continuously
-- moving visuals outside the cast bar. 30 Hz keeps it fluid at a seventh of
-- frame-rate cost; both update paths are change-gated internally.
mod.MotionTick = CludesUI.Tick.NewAnimTicker(CreateFrame("Frame"), function()
    local cs = cachedSecondary
    if not (cs and classBar and classBar:IsShown() and classBar:GetAlpha() > 0) then
        return
    end
    if cs.power == "IRONFUR_BAR" then
        UpdateIronfurBar()
        return true
    elseif cs.power == "IGNOREPAIN_BAR" then
        IP.EnsureViewer()
        IP.UpdateHash()
        IP.UpdateText()
        return true
    end
end, 1 / 30)

-- Secondary-resource poll: DK rune fills and the custom/bar/buff safety poll at
-- 10Hz, Evoker Essence recharge at 20Hz. ONE ticker at a 20Hz base; 10Hz jobs
-- skip every other fire. All paths funnel into UpdateSecondaryResource, whose
-- value early-out makes an unchanged poll nearly free.
mod.PollTick = CludesUI.Tick.NewAnimTicker(CreateFrame("Frame"), function()
    local cs = cachedSecondary
    -- Blizzard Class Resource Art stands in: nothing to poll (the ticker stops).
    if not cs or mod._erbArtOn then
        return
    end
    local pwr, typ = cs.power, cs.type
    if _essenceNextTick and pwr == PT.ESSENCE then
        UpdateSecondaryResource()
        return true
    end
    mod._pollFlip = not mod._pollFlip
    if mod._pollFlip then
        return true
    end
    if typ == "runes" or typ == "custom" or typ == "bar" or cs.frac then
        -- cs.frac (Destruction shard fragments): sub-unit movement, including
        -- out-of-combat decay, has no reliable event. The fragment-aware value
        -- guard costs one UnitPower per fire when nothing moved.
        UpdateSecondaryResource()
        return true
    end
    -- Tracked buffs on an enabled bar: the safety poll behind UNIT_AURA.
    if mod.SecTracks() then
        UpdateSecondaryResource()
        return true
    end
end, 0.05)

-- Spender pass (Class Resource Bar and Power Bar spender coloring). SPELL_UPDATE_USABLE,
-- SPELL_UPDATE_COOLDOWN, SPELL_UPDATE_ICON and each tracked spell's cooldown-end
-- edge only request it: one hidden frame runs it on the next frame (its OnUpdate
-- hides the frame first), scans once and repaints a bar only when its winning spender
-- changed. A cooldown that ends on its own fires no event, so each tracked row
-- gets a hidden Cooldown widget fed the spell's cooldown duration object (GCD
-- ignored; the object is secret-safe) and its OnCooldownDone is the ready edge.
-- SPELL_UPDATE_COOLDOWN and an override swap (SPELL_UPDATE_ICON) re-feed the
-- widgets. They are built on the first pass and cleared on disarm; nothing here
-- runs while spenders are not armed (ns.ArmTick).
do
    local pass = CreateFrame("Frame")
    pass:Hide()
    local owner
    local cds = {}
    local feed = false -- re-feed the widgets on the next pass

    -- Latch each tracked spell's "on a real cooldown" verdict under its configured
    -- ID (read through the current override). isOnGCD is only trustworthy while
    -- answering SPELL_UPDATE_COOLDOWN, so it is read here.
    local function Latch(entries, oncd)
        local S = C_Spell
        for i = 1, #entries do
            local spellRef = entries[i].spellID
            if spellRef then
                local cd = S.GetSpellCooldown(S.GetOverrideSpell(spellRef) or spellRef)
                oncd[spellRef] = (cd and cd.isActive and not cd.isOnGCD) and true or false
            end
        end
    end

    local function OnDone(cd)
        if not mod._spenderEvents then
            return
        end
        if cd._sid and cd._oncd then
            cd._oncd[cd._sid] = false
        end
        pass:Show()
    end

    -- Feeds list's rows into the widgets after position n, tagged with the bar's
    -- verdicts; returns the last position used.
    local function Feed(entries, num, oncd)
        if not entries then
            return num
        end
        if not owner then
            owner = CreateFrame("Frame")
            owner:SetSize(1, 1)
            owner:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
            owner:SetAlpha(0)
        end
        owner:Show()
        local S = C_Spell
        for i = 1, #entries do
            local k = num + i
            local cd = cds[k]
            if not cd then
                cd = CreateFrame("Cooldown", nil, owner, "CooldownFrameTemplate")
                cd:SetAllPoints()
                cd:SetHideCountdownNumbers(true)
                cd:SetDrawBling(false)
                cd:EnableMouse(false)
                cd:SetScript("OnCooldownDone", OnDone)
                cds[k] = cd
            end
            local ident = entries[i].spellID
            cd._sid = ident
            cd._oncd = oncd
            local dur = ident and S.GetSpellCooldownDuration(S.GetOverrideSpell(ident) or ident, true)
            if dur then
                cd:SetCooldownFromDurationObject(dur)
            else
                cd:Clear()
            end
        end
        return num + #entries
    end

    pass:SetScript("OnUpdate", function(self)
        self:Hide()
        local _, spend = mod.SecTracks()
        local pspend = mod.PowTracks()
        spend, pspend = spend and mod._spenderSec, pspend and mod._spenderPow
        if not (spend or pspend) then
            return
        end
        local t, pt = mod.STK, mod.PTK
        if feed then
            feed = false
            local num = Feed(spend and t.entry.spenderColors, 0, t.oncd)
            num = Feed(pspend and pt.entry.spenderColors, num, pt.oncd)
            for i = num + 1, #cds do
                cds[i]._sid = nil
                cds[i]._oncd = nil
                cds[i]:Clear()
            end
        end
        if spend then
            local wid = mod.SpenderScan(t.entry)
            if wid ~= t.w then
                t.w = wid
                UpdateSecondaryResource()
            end
        end
        if pspend then
            local wid = mod.SpenderScan(pt.entry, pt.oncd)
            if wid ~= pt.w then
                pt.w = wid
                UpdatePrimaryBar()
            end
        end
    end)

    function mod.SpenderRequest(refeed)
        if refeed then
            feed = true
        end
        pass:Show()
    end

    function mod.SpenderEvent(_, evt, spellId, baseSpellID, category, recoveryCat)
        if evt == "SPELL_UPDATE_COOLDOWN" then
            local _, spend = mod.SecTracks()
            local pspend = mod.PowTracks()
            spend, pspend = spend and mod._spenderSec, pspend and mod._spenderPow
            if not (spend or pspend) then
                return
            end
            local t, pt = mod.STK, mod.PTK
            -- A named update for an untracked spell changes nothing here unless it
            -- started the GCD; a nil or unreadable spellID updates every cooldown.
            if
                not (issecretvalue and issecretvalue(spellId))
                and spellId
                and not t.ids[spellId]
                and not pt.ids[spellId]
                and not (baseSpellID and (t.ids[baseSpellID] or pt.ids[baseSpellID]))
                and recoveryCat ~= Constants.SpellCooldownConsts.GLOBAL_RECOVERY_CATEGORY
            then
                return
            end
            if spend then
                Latch(t.entry.spenderColors, t.oncd)
            end
            if pspend then
                Latch(pt.entry.spenderColors, pt.oncd)
            end
            feed = true
        elseif evt == "SPELL_UPDATE_ICON" then
            -- An override appeared or went away: re-feed the widgets from the
            -- current forms.
            feed = true
        end
        pass:Show()
    end

    function mod.SpenderDisarm()
        feed = false
        pass:Hide()
        mod.STK.fedGen = nil
        wipe(mod.STK.oncd)
        wipe(mod.PTK.oncd)
        for i = 1, #cds do
            cds[i]:Clear()
        end
        if owner then
            owner:Hide()
        end
    end
end

-- Tick arming. Called after every event (OnEvent tail) and from ApplyAll; starts
-- whichever subsystem tickers the current state needs. Each ticker self-stops
-- when its job settles, so a redundant arm costs one IsPlaying check and a
-- missed arm only freezes until the next event. Cheap field reads only; the
-- config-derived answers (buff and spender tracking) come from ns.SecTracks,
-- cached on ns.CfgGen. Anything time-based added later MUST ride one of the
-- tickers above (with an arm condition here) or be event-driven -- NEVER a
-- per-frame OnUpdate (the spender pass is a one-shot on a hidden frame).
function mod.ArmTick()
    local cs = cachedSecondary
    local tracksBuff, tracksSpender = mod.SecTracks()
    -- Blizzard Class Resource Art stands in for the pips: arm nothing for them.
    if cs and not mod._erbArtOn then
        local pwr, typ = cs.power, cs.type
        if pwr == "IRONFUR_BAR" or pwr == "IGNOREPAIN_BAR" then
            mod.MotionTick.Start()
        end
        if
            typ == "runes"
            or typ == "custom"
            or typ == "bar"
            or cs.frac
            or (_essenceNextTick and pwr == PT.ESSENCE)
            or tracksBuff
        then
            mod.PollTick.Start()
        end
    end
    if cachedPrimary == "EBON_MIGHT" and not mod.EMB121_Owns and _ebonMightExpiry > GetTime() then
        mod.EMTick.Start()
    end
    -- Spender coloring: its three events are registered on the addon's own event
    -- frame only while an enabled bar's entry tracks spenders (the class-resource
    -- bar only while its pips are ours to paint). Arming and every config bump
    -- re-feed the spender pass.
    local swant = (tracksSpender and cs and not mod._erbArtOn) and true or false
    local pwant = (mod.PowTracks() and cachedPrimary and cachedPrimary ~= "EBON_MIGHT") and true or false
    local want = swant or pwant
    mod._spenderSec, mod._spenderPow = swant, pwant
    if want ~= (mod._spenderEvents or false) then
        mod._spenderEvents = want
        if want then
            ERB:RegisterEvent("SPELL_UPDATE_USABLE", mod.SpenderEvent)
            ERB:RegisterEvent("SPELL_UPDATE_COOLDOWN", mod.SpenderEvent)
            ERB:RegisterEvent("SPELL_UPDATE_ICON", mod.SpenderEvent)
        else
            ERB:UnregisterEvent("SPELL_UPDATE_USABLE")
            ERB:UnregisterEvent("SPELL_UPDATE_COOLDOWN")
            ERB:UnregisterEvent("SPELL_UPDATE_ICON")
            mod.SpenderDisarm()
        end
    end
    if want and mod.STK.fedGen ~= mod.CfgGen then
        mod.STK.fedGen = mod.CfgGen
        mod.SpenderRequest(true)
    end
end

-- Cast bar redraw without per-frame dispatch: a looping Animation fires OnLoop at the
-- redraw rate and the C engine sleeps between fires, so an active cast runs ZERO Lua at
-- frame rate (a per-frame accumulator gating the redraw would cost more than the redraw
-- itself: 0.14% floor vs 0.06% body). Host frame and group born HERE at file scope so
-- the work bills ResourceBars (frame-birth attribution). Self-stopping: the loop halts
-- the moment no cast state remains, covering every stop path without Stop calls in each
-- handler, at the cost of at most one no-op fire.
do
    local owner = CreateFrame("Frame")
    local ag = owner:CreateAnimationGroup()
    ag:SetLooping("REPEAT")
    local tick = ag:CreateAnimation("Animation")
    -- 20 Hz redraw: the eased SetValue has the engine rendering intermediate fill
    -- positions between redraws, so this rate governs only text/stage/safety
    -- granularity, not fill smoothness.
    tick:SetDuration(1 / 20)
    ag:SetScript("OnLoop", function()
        if
            castBarFrame
            and (castBarFrame._casting or castBarFrame._channeling or castBarFrame._empowering)
        then
            UpdateCastBar()
        else
            ag:Stop()
        end
    end)
    -- Idempotent; safe to call from every cast event.
    mod.StartCastTick = function()
        if not ag:IsPlaying() then
            ag:Play()
        end
    end
end

-- Raw-fill writer for Smooth Bar Animation OFF. A plain SetValue lands only
-- at the 20 Hz tick and the engine has no linear interpolation to carry the
-- fill between redraws (Enum.StatusBarInterpolation: Immediate or ease-out
-- only), so raw mode visibly stepped. This frame does the minimal per-frame
-- write -- one time read, one SetValue -- and exists ONLY while a Lua-drawn
-- cast is active with smoothing off: shown by the per-cast constants memo,
-- hidden by ns.ShowIdleCastBar and by its own gate the moment cast state or
-- fill ownership changes. Hidden frame = zero idle cost. Text, stages,
-- spark and safety stay on the 20 Hz tick.
do
    local min, max = math.min, math.max
    local driver = CreateFrame("Frame")
    driver:Hide()
    mod._rawFillDriver = driver
    driver:SetScript("OnUpdate", function(self)
        local frame = castBarFrame
        if not frame or frame._nativeFill or not frame._rawFill or not (frame._casting or frame._channeling or frame._empowering) then
            self:Hide()
            return
        end
        local dur = frame._endTime - frame._startTime
        local v
        if frame._channeling then
            v = (dur > 0) and ((frame._endTime - GetTime()) / dur) or 0
        else
            v = (dur > 0) and ((GetTime() - frame._startTime) / dur) or 0
        end
        v = min(max(v, 0), 1)
        local barFrame = frame._bar
        local scrollBar = barFrame._sb or barFrame
        scrollBar:SetValue(v)
        if frame._gradientFullBar and frame._gradClip then
            frame._gradClip:SetWidth(max(0.01, barFrame:GetWidth() * v))
        end
    end)
end

-- GCD bar ticker: 20 Hz; the eased SetValue inside UpdateGCDBar carries the
-- fill between fires. Runs only while a GCD is live, and the final fire
-- renders the idle state before the loop stops itself.
mod.GCDTick = CludesUI.Tick.NewAnimTicker(CreateFrame("Frame"), function()
    UpdateGCDBar()
    return gcdBarFrame and gcdBarFrame._gcdStart ~= nil
end, 0.05)

Inner.HandleIronfurCast, Inner.ShouldShowBar = HandleIronfurCast, ShouldShowBar
Inner.ShouldShowSecondary, Inner.UpdateHealthBar = ShouldShowSecondary, UpdateHealthBar
Inner.UpdatePrimaryBar, Inner.UpdateSecondaryResource = UpdatePrimaryBar, UpdateSecondaryResource
Inner.UpdateVisibility = UpdateVisibility
Inner.broken = false
