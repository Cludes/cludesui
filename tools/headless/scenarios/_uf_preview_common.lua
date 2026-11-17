-- Shared body of the options_uf_preview* scenarios (dofile'd after the
-- prelude; it returns a function taking the prelude's OUT and the units to
-- run). Split in two because one run over every unit outgrew LuaJIT's memory.
-- Unit Frames: the page-header preview (mod.UFO_BuildUnitPreview) on its own,
-- for every unit, under a run of setting variants: each variant written into
-- the unit's settings, a fresh preview built on a plain host (snapshotted as
-- built), then its Update run (snapshotted again), then the settings put
-- back. The last rounds repeat a few variants with Blizzard Style forced on
-- and with the unit frame handed to another source (the disabled overlay).
return function(OUT, units, stockOnly, eyesOnly)
    local CUI = rawget(_G, "CludesUI")
    CUI:SelectModule("CludesUIUnitFrames")
    CUI:SelectPage("Main Frames")
    local mod = CUI._ModuleNS and CUI._ModuleNS["CludesUIUnitFrames"]
    local env = mod and mod._UFO_OptEnv
    if not (mod and env and mod.UFO_BuildUnitPreview) then
        OUT:write("== no preview builder\n")
        return
    end
    local prof = env.db.profile
    local RED, BLUE = { r = 0.9, g = 0.1, b = 0.2 }, { r = 0.1, g = 0.3, b = 0.9 }
    local CONTENT = {
        "name", "nametotarget", "targetname", "level", "levelname", "namelevel", "both", "bothdash",
        "curhpshort", "healthshort", "curmaxhp", "perhp", "perhpnosign", "perhpnum", "perhpnumdash",
        "perpp", "curpp", "curmaxpp", "curhp_curpp", "perhp_perpp", "absorb", "absorbshort",
        "healabsorb", "healabsorbshort", "group", "custom", "none",
    }
    local FMT = "[name] [level] [hp] [hp:abr] [hp:max] [hp:max:abr] [hp:pct] [pp] [pp:abr] [pp:max] [pp:max:abr] [pp:pct] [absorb] [absorb:abr] [healabsorb] [healabsorb:abr] [target] [group]"
    local variants = {}
    local function V(name, t)
        variants[#variants + 1] = { name = name, set = t }
    end
    V("default", {})
    -- Every text content key in each of the five slots (rotated).
    for i = 1, #CONTENT, 3 do
        local function at(k)
            return CONTENT[((i + k - 1) % #CONTENT) + 1]
        end
        V("text " .. i, {
            leftTextContent = at(0), rightTextContent = at(5), centerTextContent = at(10),
            extraTextContent = at(15), extraTextAlign = ({ "left", "right", "center" })[(i % 3) + 1],
            leftTextCustomFormat = FMT, rightTextCustomFormat = FMT, centerTextCustomFormat = FMT,
            extraTextCustomFormat = FMT, leftTextClassColor = (i % 2 == 0), rightTextClassColor = (i % 2 == 1),
            centerTextClassColor = true, extraTextClassColor = (i % 2 == 0), levelDifficultyColor = (i % 2 == 1),
            leftTextX = 3, leftTextY = -2, rightTextX = -4, rightTextY = 1, centerTextX = 2, centerTextY = 2,
            extraTextX = 1, extraTextY = -3, leftTextSize = 10, rightTextSize = 14, centerTextSize = 11,
            extraTextSize = 9, rightTextColorR = 0.5, rightTextColorG = 0.6, rightTextColorB = 0.7,
            leftTextTargetSep = "-", leftTextTargetSepClassColor = (i % 2 == 0), rightTextTargetPrefix = "",
            bottomTextBar = (i % 2 == 0), btbLeftContent = at(1), btbRightContent = at(2), btbCenterContent = at(3),
            btbLeftCustomFormat = FMT, btbRightPowerColor = true, btbCenterClassColor = true,
        })
    end
    V("health a", {
        healthReverseFill = true, healthBarOpacity = 60, gradientEnabled = true, gradientDir = "VERTICAL",
        gradientColor = BLUE, healthClassColored = true, bgClassColored = true, customBgAlpha = 50,
        frameWidth = 220, healthHeight = 30, healthBarTexture = "flat", maxHealthStyle = "maxHealthStripes",
        borderSize = 2, borderSizeOverride = 3,
    })
    V("health b", {
        healthVerticalFill = true, customFillColor = RED, customBgColor = BLUE, healthBarOpacity = 100,
        frameWidth = 150, healthHeight = 60, borderTexture = "none", borderSize = 0,
    })
    V("health c", { healthVerticalFill = true, healthReverseFill = true, gradientEnabled = true })
    for _, pos in ipairs({ "below", "above", "detached_top", "detached_bottom", "none" }) do
        V("power " .. pos, {
            powerPosition = pos, powerHeight = 10, powerWidth = 120, powerX = 4, powerY = -3,
            powerReverseFill = (pos == "above" or pos == "detached_top"), powerBarOpacity = 50,
            powerGradientEnabled = (pos ~= "below"), powerGradientColor = RED, powerGradientDir = "VERTICAL",
            powerClassColored = (pos == "above"), powerBgPowerColored = (pos == "detached_bottom"),
            powerPercentPowerColor = (pos == "none"), customPowerFillColor = BLUE, customPowerBgColor = RED,
            customPowerBgAlpha = 70, powerPercentText = ({ below = "left", above = "right", detached_top = "center", detached_bottom = "left", none = "right" })[pos],
            powerTextFormat = ({ below = "both", above = "curmaxpp", detached_top = "curpp", detached_bottom = "smart", none = "custom" })[pos],
            powerPercentX = 2, powerPercentY = 1, powerPercentSize = 11, powerShowPercent = true,
            powerCostPrediction = true, powerBorderStyle = "thin", cornerJoinPower = true,
        })
    end
    for _, st in ipairs({ "attached", "detached", "none" }) do
        for _, mode in ipairs({ "2d", "3d", "class" }) do
            V("portrait " .. st .. " " .. mode, {
                showPortrait = true, portraitStyle = st, portraitMode = mode, portraitSide = (mode == "3d") and "right" or "left",
                portraitSize = 50, portraitX = 3, portraitY = -2, portraitSeparator = (mode == "class"),
                portraitMirror = (mode == "2d"), portraitNonPlayerOn = true, classThemeStyle = "modern",
            })
        end
    end
    V("portrait off", { showPortrait = false })
    for i, side in ipairs({ "left", "center", "right", "none" }) do
        V("cast " .. side, {
            showPlayerCastbar = true, showCastbar = true, playerCastbarHeight = 18 + i, castbarHeight = 16 + i,
            castbarWidth = 160, castSpellNameSide = side, castDurationSide = ({ "right", "left", "none", "center" })[i],
            castSpellTargetSide = ({ "center", "none", "left", "right" })[i], showCastTarget = (i ~= 2),
            showCastIcon = (i ~= 3), showPlayerCastIcon = (i ~= 3), showCastDuration = (i ~= 4),
            castbarIconRight = (i == 2), playerCastbarIconRight = (i == 2), castReverseFill = (i == 4),
            castbarClassColored = (i == 1), castbarFillColor = RED, castBgColor = BLUE, castBgAlpha = 60,
            castSpellNameX = 2, castSpellNameY = 1, castSpellNameSize = 10, castDurationX = -2, castDurationY = 1,
            castDurationSize = 9, castSpellTargetX = 1, castSpellTargetY = -1, castSpellTargetSize = 8,
            castIconOffsetX = 1, castIconOffsetY = 1, playerCastIconOffsetX = 2, playerCastIconOffsetY = -1,
        })
    end
    V("cast off", { showPlayerCastbar = false, showCastbar = false })
    for i, pos in ipairs({ "bottom", "top", "detached_top", "detached_bottom" }) do
        V("textbar " .. pos, {
            bottomTextBar = true, btbPosition = pos, bottomTextBarHeight = 14 + i, btbWidth = 150, btbX = 3, btbY = -2,
            btbBgColor = RED, btbBgOpacity = 70, btbLeftContent = "name", btbRightContent = "perpp",
            btbCenterContent = (i % 2 == 0) and "level" or "none", btbLeftClassColor = true, btbRightPowerColor = true,
            btbLeftX = 1, btbLeftY = 1, btbRightX = -1, btbRightY = 0, btbCenterX = 0, btbCenterY = 1,
            btbLeftSize = 10, btbRightSize = 11, btbCenterSize = 12,
            btbClassIcon = ({ "class", "none", "modern", "class" })[i], btbClassIconLocation = ({ "left", "center", "right", "left" })[i],
            btbClassIconSize = 12, btbClassIconX = 1, btbClassIconY = -1,
        })
    end
    for i, pos in ipairs({ "top", "bottom", "above" }) do
        V("classpower " .. pos, {
            classPowerStyle = (i == 3) and "modern" or "pips", classPowerPosition = pos, classPowerSize = 8 + i,
            classPowerSpacing = i, classPowerBarX = 2, classPowerBarY = -1, classPowerClassColor = (i == 2),
            classPowerCustomColor = RED, classPowerEmptyColor = BLUE, classPowerBgColor = BLUE,
        })
    end
    local ABS = { "striped", "stripedReversed", "clean", "blizzard", "largeStripes", "pixelsShield", "pixelsShieldEdge", "none" }
    local EDGE = { "overlay", "overlayReverse", "overlayReverseFull", "left", "right", "overlay", "right", "left" }
    local HAS = { "clean", "largeOutlinedStripes", "largeOutlinedStripesR", "striped", "none", "blizzard", "clean", "stripedThick" }
    local PLACE = { "none", "top", "bottom", "none", "top", "bottom", "none", "top" }
    for i = 1, #ABS do
        V("absorb " .. i, {
            showPlayerAbsorb = ABS[i], absorbEdgeMode = EDGE[i], absorbOpacity = 70, absorbColor = BLUE,
            absorbBarPosition = PLACE[i], absorbBarHeight = 4, absorbBarColor = RED, absorbCleanAlpha = 40,
            absorbGlowLine = (i % 2 == 1), absorbGlowLineTexture = (i % 3 == 0) and "flat" or nil,
            healAbsorbStyle = HAS[i], healAbsorbEdgeMode = EDGE[#EDGE - i + 1], healAbsorbOpacity = 60,
            healAbsorbColor = RED, healAbsorbBgOpacity = 30, healAbsorbBarPosition = PLACE[#PLACE - i + 1],
            healAbsorbBarHeight = 3, healAbsorbBarColor = BLUE, healthReverseFill = (i % 2 == 0),
            healthVerticalFill = (i == 5), healPrediction = (i % 2 == 1), healPredOverheal = (i % 3 == 0),
            healPredOpacity = 50, healPredColor = RED, healPredOtherColor = BLUE, healPredTexture = (i % 2 == 0) and "flat" or "health",
        })
    end
    local ANCH = { "topleft", "topright", "bottomleft", "bottomright", "left", "right", "none" }
    local GROW = { "auto", "up", "down", "left", "right", "auto", "up" }
    for i = 1, #ANCH do
        V("auras " .. i, {
            showBuffs = true, buffAnchor = ANCH[i], buffGrowth = GROW[i], buffSize = 18 + i, buffOffsetX = i,
            buffOffsetY = (i % 2 == 0) and 70 or -12, buffSpacingX = 2, buffSpacingY = 1, maxBuffs = 3 + i,
            debuffAnchor = ANCH[#ANCH - i + 1], debuffGrowth = GROW[#GROW - i + 1], debuffSize = 16 + i,
            debuffOffsetX = -i, debuffOffsetY = (i % 2 == 1) and -70 or 8, debuffSpacingX = 1, debuffSpacingY = 2,
            maxDebuffs = 2 + i, debuffAnchorBuffs = (i % 2 == 0), debuffStackTextSize = 9,
            debuffStackTextPosition = (i % 2 == 0) and "TOPLEFT" or "BOTTOMRIGHT", debuffStackTextOffsetX = 1,
            debuffStackTextOffsetY = 1, debuffStackTextColor = RED, debuffShowCooldownText = (i % 2 == 0),
            debuffCooldownTextSize = 10, debuffCooldownTextOffsetX = 1, debuffCooldownTextOffsetY = -1,
            debuffCooldownTextColor = BLUE, simpleDebuffShowCooldownText = (i % 2 == 1),
            simpleDebuffCooldownTextSize = 11, simpleDebuffCooldownTextOffsetX = 2, simpleDebuffCooldownTextOffsetY = 2,
            auraBorderSize = (i % 3), auraBorderBehind = (i == 2), auraBorderBehindUnitFrame = (i == 3),
        })
    end
    local CIPOS = { "healthbar", "portrait", "textbar", "topright", "bottomleft", "bottomright", "center" }
    local FPOS = { "topright", "topleft", "bottomleft", "bottomright", "portrait", "topright", "topleft" }
    for i = 1, #CIPOS do
        V("indicators " .. i, {
            combatIndicatorStyle = (i == 7) and "none" or ((i % 2 == 0) and "class" or "default"),
            combatIndicatorPosition = CIPOS[i], combatIndicatorSize = 14 + i, combatIndicatorX = i, combatIndicatorY = -i,
            combatIndicatorColor = (i % 2 == 0) and "classcolor" or "custom", combatIndicatorCustomColor = RED,
            bottomTextBar = (i == 3),
            factionIndicatorMode = (i % 2 == 0) and "always" or "pvp", factionIndicatorPosition = FPOS[i],
            factionIndicatorStyle = (i % 2 == 0) and "pvp" or "pixels", factionIndicatorSize = 16, factionIndicatorX = 1,
            factionIndicatorY = 1, raidMarkerEnabled = true, raidMarkerAlign = ({ "left", "center", "right" })[(i % 3) + 1],
            raidMarkerSize = 14 + i, raidMarkerX = 1, raidMarkerY = 2, leaderIndicatorEnabled = true,
            leaderIndicatorStyle = (i % 2 == 0) and "pixels" or "blizzard", leaderIndicatorPosition = FPOS[i],
            leaderIndicatorSize = 12, leaderIndicatorX = 1, leaderIndicatorY = -1, eliteIndicatorEnabled = true,
            eliteIndicatorStyle = (i % 2 == 0) and "pixelsDragon" or "badge", eliteIndicatorPosition = FPOS[#FPOS - i + 1],
            eliteIndicatorSize = 20, eliteIndicatorX = -1, eliteIndicatorY = 1, showPortrait = (i ~= 5),
            happinessEnabled = true, happinessAlign = ({ "right", "top", "left" })[(i % 3) + 1], happinessSize = 18,
            happinessX = 2, happinessY = 1,
        })
    end
    -- Power Bar Height 0 with its text: the text meets the health bar instead.
    for i, pos in ipairs({ "above", "below", "detached_top" }) do
        V("power zero " .. pos, {
            powerPosition = pos, powerHeight = 0, powerPercentText = ({ "center", "left", "right" })[i],
            powerTextFormat = ({ "perpp", "both", "curmaxpp" })[i], powerShowPercent = (i ~= 2),
            powerPercentTextPowerColor = (i == 1), powerTextColor = BLUE, powerPercentX = 1, powerPercentY = -1,
        })
    end
    -- Modern class pips floating above and below the frame (with and
    -- without an offset, the cast bar on), and custom-coloured.
    for i, pos in ipairs({ "top", "bottom", "bottom" }) do
        V("classpower modern " .. pos .. " " .. i, {
            classPowerStyle = "modern", classPowerPosition = pos, classPowerSize = 9 + i, classPowerSpacing = i,
            classPowerBarX = (i == 3) and 0 or 2, classPowerBarY = (i == 3) and 0 or -2,
            classPowerClassColor = (i == 2), classPowerCustomColor = RED, classPowerEmptyColor = BLUE,
            showPlayerCastbar = (i ~= 1), playerCastbarHeight = 16,
        })
    end

    local NIL = {}
    local function Apply(s, set)
        local old = {}
        for k, v in pairs(set) do
            local cur = s[k]
            if cur == nil then cur = NIL end
            old[k] = cur
            s[k] = v
        end
        return old
    end
    local function Restore(s, old)
        for k, v in pairs(old) do
            if v == NIL then s[k] = nil else s[k] = v end
        end
    end
    local function Run(tag, unit, side)
        local host = CreateFrame("Frame", nil, UIParent)
        host:SetSize(1000, 220)
        host:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
        host:Show()
        local ok, pf = pcall(mod.UFO_BuildUnitPreview, host, unit, side)
        if not ok then
            OUT:write("== " .. tag .. " build ERR " .. tostring(pf) .. "\n")
        else
            SNAP(tag .. " built", pf)
            local ok2, err = pcall(pf.Update, pf)
            if not ok2 then OUT:write("== " .. tag .. " update ERR " .. tostring(err) .. "\n") end
            SNAP(tag .. " updated", pf)
            local ov = rawget(pf, "_disabledOverlay")
            if ov and ov:IsShown() then SNAP(tag .. " overlay", ov) end
            OUT:write("   " .. tag .. " fields b=" .. tostring(pf._buffExtra) .. " t=" .. tostring(pf._buffTopPad)
                .. " sc=" .. tostring(pf._previewScale) .. "\n")
            pf:Hide()
        end
        host:Hide()
    end
    -- eyesOnly: every preview eye toggle on (heal absorb, max health, heal
    -- prediction, power cost, combat icon, dispel overlay with its border
    -- and icons, faction, raid marker, leader, elite), over the variants that
    -- feed them, with the dispel overlay modes and custom combat icons cycled.
    if eyesOnly then
        local opt = env.optState
        local eyeFlags = {
            showHealAbsorbPreview = true, showCombatIndicatorPreview = true,
            showDispelOverlayPreview = true, showMaxHealthPreview = true,
        }
        local modFlags = {
            _ufShowHealPredPreview = true, _ufShowPowerCostPreview = true,
            _ufPvEyes = { faction = true, raid = true, leader = true, elite = true, raidIndex = 3 },
        }
        local oldOpt, oldMod = Apply(opt, eyeFlags), Apply(mod, modFlags)
        local DISPEL = { "full", "gradient", "gradient_reverse", "gradient_sharp", "left", "none", "full" }
        local GROWTH = { "right", "left", "up", "down", "none", "right", "left" }
        local picks = {}
        for _, v in ipairs(variants) do
            if v.name:find("^absorb") or v.name:find("^indicators") or v.name:find("^power ")
                or v.name:find("^portrait") or v.name == "default" or v.name:find("^classpower") then
                picks[#picks + 1] = v
            end
        end
        for _, unit in ipairs(units) do
            local s = prof[unit]
            if s then
                for pi, v in ipairs(picks) do
                    local k = (pi % #DISPEL) + 1
                    local old = Apply(s, v.set)
                    local old2 = Apply(s, {
                        combatIndicatorStyle = (pi % 3 == 0) and ("combat" .. (pi % 6)) or s.combatIndicatorStyle,
                        maxHealthStyle = (pi % 2 == 0) and "maxHealthStripes" or s.maxHealthStyle,
                        healPrediction = true, powerCostPrediction = true, factionIndicatorMode = "pvp",
                        raidMarkerEnabled = true, eliteIndicatorEnabled = true,
                    })
                    local old3 = Apply(prof, {
                        dispelOverlay = DISPEL[k], dispelOverlayOpacity = 70, dispelCustomBorder = (pi % 2 == 1),
                        showDispelIcons = true, dispelIconGrowth = GROWTH[k], dispelIconSize = 14 + k,
                        dispelIconPosition = ({ "left", "right", "center" })[(pi % 3) + 1],
                        dispelIconOffsetX = 1, dispelIconOffsetY = -1,
                    })
                    Run("eyes " .. unit .. " " .. v.name, unit, (pi % 2 == 0) and "right" or "left")
                    Restore(prof, old3)
                    Restore(s, old2)
                    Restore(s, old)
                end
            end
        end
        Restore(mod, oldMod)
        Restore(opt, oldOpt)
        return
    end
    -- stockOnly: the stock look rounds alone (Blizzard Style through the
    -- module's own style latch, the Classic WoW UI kit and, on WoW Forever,
    -- the Forever kit), over a picked set of variants.
    if stockOnly then
        local PICKS = {
            "default", "text 1", "health a", "health b", "power above", "power detached_top", "power none",
            "portrait attached 2d", "portrait detached 3d", "portrait none class", "cast left", "cast right",
            "cast none", "cast off", "textbar top", "textbar detached_bottom", "classpower above", "absorb 2",
            "absorb 5", "auras 1", "indicators 2", "power zero above",
        }
        local byName = {}
        for _, v in ipairs(variants) do
            byName[v.name] = v
        end
        local BS = CUI.BlizzStyle
        local saved = {
            get = BS.Get, active = BS.Active, forever = BS.Forever,
            style = mod._ufStyle, fstyle = mod._ufForever, kit = mod.UF_BLIZZ,
        }
        local kits = { { "blizzard", "blizzard", false, saved.kit } }
        if mod.UF_KITS and mod.UF_KITS.classic then
            kits[#kits + 1] = { "classic", "classic", false, mod.UF_KITS.classic }
        end
        if CUI.IS_FOREVER == true and mod.UF_ForeverKit then
            kits[#kits + 1] = { "forever", "blizzard", true, mod.UF_ForeverKit() }
        end
        for _, kit in ipairs(kits) do
            local label, active, isForever, kitTable = kit[1], kit[2], kit[3], kit[4]
            BS.Get = function(key) return key == "unitframes" or saved.get(key) end
            BS.Active = function(key) if key == "unitframes" then return active end return saved.active(key) end
            BS.Forever = function(key) if key == "unitframes" then return isForever end return saved.forever(key) end
            mod._ufStyle, mod._ufForever, mod.UF_BLIZZ = active, isForever, kitTable
            for _, unit in ipairs(units) do
                local s = prof[unit]
                if s then
                    for pi, name in ipairs(PICKS) do
                        local v = byName[name]
                        if v then
                            local side = (pi % 2 == 0) and "right" or "left"
                            local old = Apply(s, v.set)
                            local old2 = Apply(s, { portraitSide = side, blizzScale = (pi % 3 == 0) and 1.3 or 1 })
                            Run(label .. " " .. unit .. " " .. name .. " " .. side, unit, side)
                            Restore(s, old2)
                            Restore(s, old)
                        end
                    end
                end
            end
        end
        BS.Get, BS.Active, BS.Forever = saved.get, saved.active, saved.forever
        mod._ufStyle, mod._ufForever, mod.UF_BLIZZ = saved.style, saved.fstyle, saved.kit
        return
    end
    for _, unit in ipairs(units) do
        local s = prof[unit]
        if s then
            for vi, v in ipairs(variants) do
                local old = Apply(s, v.set)
                Run(unit .. " " .. vi .. " " .. v.name, unit, (vi % 2 == 0) and "right" or "left")
                Restore(s, old)
            end
        end
    end
    -- Blizzard Style forced on (the stock geometry pass over the mock).
    local BS = CUI.BlizzStyle
    local origGet, origActive = BS.Get, BS.Active
    BS.Get = function(key) return key == "unitframes" or origGet(key) end
    BS.Active = function(key) if key == "unitframes" then return "blizzard" end return origActive(key) end
    for _, unit in ipairs(units) do
        local s = prof[unit]
        if s then
            for _, vi in ipairs({ 1, 2, 12, 13, 16, 21, 24, 30, 38, 42 }) do
                local v = variants[vi]
                if v then
                    local old = Apply(s, v.set)
                    for _, side in ipairs({ "left", "right" }) do
                        local old2 = Apply(s, { portraitSide = side, blizzScale = (side == "right") and 1.3 or 0.8 })
                        Run("blizz " .. unit .. " " .. vi .. " " .. side, unit, side)
                        Restore(s, old2)
                    end
                    Restore(s, old)
                end
            end
        end
    end
    BS.Get, BS.Active = origGet, origActive
    -- Another source drives the frame: the preview dims under its overlay.
    local origSrc = mod.GetUnitFrameSource
    mod.GetUnitFrameSource = function() return "blizzard" end
    for _, unit in ipairs(units) do
        Run("disabled " .. unit, unit, "left")
    end
    mod.GetUnitFrameSource = origSrc
end
