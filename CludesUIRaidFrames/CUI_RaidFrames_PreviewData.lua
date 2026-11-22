if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_RaidFrames_PreviewData.lua
--
--  The sample values and ApplyPreviewData, which paints one preview frame.
--  Reads the earlier preview files through ns and ns._previewInternals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._previewInternals
-- CUI_RaidFrames_Preview.lua or an earlier preview file failed to load.
if not Inner or Inner.broken then return end
Inner.broken = true

local UnitName = UnitName

local RF = mod._internals -- the table of the Raid Frames chain
local ApplyFont, ApplyRoleIcon, defaultSet = RF.ApplyFont, RF.ApplyRoleIcon, RF.defaults
local DISPEL_ICON_ATLAS, GetDispelColor = RF.DISPEL_ICON_ATLAS, RF.GetDispelColor
local IsPowerBarEnabled, LayoutTopNameBar = RF.IsPowerBarEnabled, RF.LayoutTopNameBar
local PixelSnap, ResolveHealthTexture = RF.PixelSnap, RF.ResolveHealthTexture

local previewClassTokens, previewRoles = Inner.previewClassTokens, Inner.previewRoles

-- Shared state: one copy per file. A write goes through the Set<Name>
-- function of the table that holds its list, which hands the value to
-- every copy: db, PP and containerFrame are the Raid Frames chain's.
local saved
RF.dbSetters[#RF.dbSetters + 1] = function(val) saved = val end
local Pix
RF.PPSetters[#RF.PPSetters + 1] = function(val) Pix = val end

mod.previewAbsorbValues = mod.previewAbsorbValues or {}
local previewHealthValues = {}
local previewPowerValues = {}
mod.previewHealAbsorbValues = {}

-- roles, classTokens: the party preview hands in its own tables for this call.
local function ApplyPreviewData(frame, index, roles, classTokens)
    local previewRoles = roles or previewRoles
    local previewClassTokens = classTokens or previewClassTokens
    -- The main raid preview is a base "20 Man" mockup: RefreshPreview lays out from the
    -- base frameWidth and CreatePreviewFrame sizes from it too, so per-button sizing here
    -- must also read the base profile. ns._scaledProfile would return the active raid-size
    -- tier override for frameWidth, freezing buttons at override size while layout used
    -- base width (the 20 Man Width slider would re-space without resizing whenever a
    -- custom raid size was active). Party preview passes its own override via
    -- _previewSettingsOverride. The real-preview effective overlay (when active) resolves
    -- captured keys to panel-closed values and is NOT tier-scaled, so this holds.
    local cfg = mod._previewSettingsOverride or mod._pvOverlayProxy or saved.profile
    local compact = mod.RF_ButtonCompact(frame, cfg)
    local classToken = previewClassTokens[index]
        or mod._PV_CLASS_TOKENS[((index - 1) % #mod._PV_CLASS_TOKENS) + 1]
    local playerSlot = previewRoles._playerSlot or 1
    local name
    if index == playerSlot then
        name = UnitName("player") or "Player"
        if Ambiguate then name = Ambiguate(name, "short") end
    else
        -- Legends roster names are RAID-preview-only (user directive): the
        -- party preview (which sandwiches this fn with _previewSettingsOverride
        -- set and its own class tokens) keeps the generic name pool.
        local legend = not mod._partyPvActive
            and not mod._previewSettingsOverride
            and mod._pvNames
            and mod._pvNames[index]
        name = legend or mod._PV_NAMES[((index - 1) % #mod._PV_NAMES) + 1]
    end
    local healthPct = previewHealthValues[index] or (40 + math.random(60))

    local wid = PixelSnap(cfg.frameWidth or 72)
    local hgt = PixelSnap(cfg.frameHeight or 46)
    local powerH = IsPowerBarEnabled(cfg) and PixelSnap(cfg.powerHeight or 4) or 0
    local healthH = PixelSnap(hgt - mod.RF_HealthPowerInset(cfg, powerH))
    local topBarH = (cfg.topNameBarEnabled and PixelSnap(cfg.topNameBarHeight or 20)) or 0

    local pvInvert = mod.RF_IsInvertedFill(cfg)

    frame:SetSize(wid, hgt)

    -- Health bar height/anchor + Top Name Bar (helper re-anchors health top to
    -- -topBarH; the per-unit power block below re-sets only the height)
    LayoutTopNameBar(
        cfg,
        hgt,
        powerH,
        frame._health,
        frame._topNameBar,
        frame._topNameBarBg,
        frame._topNameBarText,
        frame._power,
        true
    )

    -- Health bar
    if frame._health then
        frame._health:SetStatusBarTexture(ResolveHealthTexture())
        frame._health:GetStatusBarTexture():SetHorizTile(false)
        mod.RF_ApplyHealthOrientation(frame._health, cfg)
        frame._health:SetMinMaxValues(0, 100)
        -- Preview: honor invert setting by flipping the displayed fill percentage
        local healthBarPct = healthPct
        if pvInvert then healthBarPct = 100 - healthBarPct end
        frame._health:SetValue(healthBarPct)
        frame._healthPct = healthPct
        frame._classToken = classToken

        local mode = cfg.healthColorMode or "class"
        local fillTex = frame._health:GetStatusBarTexture()
        if mode == "dark" then
            local dfr, dfg, dfb, dfa = CludesUI.GetDarkModeFill()
            frame._health:SetStatusBarColor(dfr, dfg, dfb, 1)
            if fillTex then fillTex:SetAlpha(dfa) end
        elseif mode == "classic" then
            if fillTex then fillTex:SetAlpha(1) end
            local pct = healthPct / 100
            local region = pct < 0.5 and 1 or (1 - (pct - 0.5) * 2)
            local g = pct > 0.5 and 1 or (pct * 2)
            frame._health:SetStatusBarColor(region, g, 0, (cfg.healthBarOpacity or 100) / 100)
        elseif mode == "customDynamic" then
            if fillTex then fillTex:SetAlpha(1) end
            local red, green, blue = mod.ResolveDynamicColor(cfg, healthPct / 100)
            frame._health:SetStatusBarColor(red, green, blue, (cfg.healthBarOpacity or 100) / 100)
        elseif mode == "classReactive" then
            if fillTex then fillTex:SetAlpha(1) end
            local red, green, blue = mod.ResolveClassReactiveColor(cfg, classToken, healthPct / 100)
            frame._health:SetStatusBarColor(red, green, blue, (cfg.healthBarOpacity or 100) / 100)
        elseif mode == "custom" then
            if fillTex then fillTex:SetAlpha(1) end
            local color = cfg.customFillColor
            frame._health:SetStatusBarColor(color.r, color.g, color.b, (cfg.healthBarOpacity or 100) / 100)
        else
            if fillTex then fillTex:SetAlpha(1) end
            local classColor = CludesUI.GetClassColor(classToken)
            if classColor then
                frame._health:SetStatusBarColor(
                    classColor.r,
                    classColor.g,
                    classColor.b,
                    (cfg.healthBarOpacity or 100) / 100
                )
            end
        end
    end

    -- Top Name Bar text (preview unit name + class/custom color)
    if frame._topNameBarText and cfg.topNameBarEnabled then
        local attach = mod.RF_TextNameAttach(cfg)
        if attach then
            frame._topNameBarText:SetFormattedText(attach[1], mod._RFPreviewLevel(), name)
        else
            frame._topNameBarText:SetText(name)
        end
        if (cfg.topNameBarTextColorMode or "class") == "custom" then
            local color = cfg.topNameBarTextColor or { r = 1, g = 1, b = 1 }
            frame._topNameBarText:SetTextColor(color.r, color.g, color.b)
        else
            local classColor = CludesUI.GetClassColor(classToken)
            if classColor then
                frame._topNameBarText:SetTextColor(classColor.r, classColor.g, classColor.b)
            else
                frame._topNameBarText:SetTextColor(1, 1, 1)
            end
        end
    end

    -- Background
    if frame._bg then
        -- BG covers the missing-health portion only (never behind the fill), so
        -- it hangs off the far side of the fill -- its right edge normally, its
        -- top edge on a vertical bar. Mirrors the live UpdateHealthBg.
        local pvVert = mod.RF_IsVerticalFill(cfg)
        local function PlacePreviewBg()
            frame._bg:ClearAllPoints()
            if pvVert then
                if pvInvert then
                    frame._bg:SetPoint("TOPLEFT", frame._health:GetStatusBarTexture(), "BOTTOMLEFT", 0, 0)
                    frame._bg:SetPoint("BOTTOMRIGHT", frame._health, "BOTTOMRIGHT", 0, 0)
                else
                    frame._bg:SetPoint("TOPLEFT", frame._health, "TOPLEFT", 0, 0)
                    frame._bg:SetPoint("BOTTOMRIGHT", frame._health:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
                end
            else
                if pvInvert then
                    frame._bg:SetPoint("TOPLEFT", frame._health, "TOPLEFT", 0, 0)
                    frame._bg:SetPoint("BOTTOMRIGHT", frame._health:GetStatusBarTexture(), "BOTTOMLEFT", 0, 0)
                else
                    frame._bg:SetPoint("TOPLEFT", frame._health:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
                    frame._bg:SetPoint("BOTTOMRIGHT", frame._health, "BOTTOMRIGHT", 0, 0)
                end
            end
        end
        -- Textured Background, as on the live frames.
        mod.RF_TexBgLayer(
            frame._health,
            frame._bg,
            not frame.kit and mod.RF_TexBgOpaque(cfg, cfg.healthColorMode == "dark") and mod.RF_TexBgPath(cfg)
                or nil
        )
        if cfg.healthColorMode == "dark" then
            PlacePreviewBg()
            frame._bg:SetColorTexture(CludesUI.GetDarkModeBg())
        else
            -- Matches the real-frame themed branch + Dark mode. Keeps the preview
            -- a 1:1 replica for reduced-fill-opacity setups.
            PlacePreviewBg()
            local bgA = (cfg.bgDarkness or 50) / 100
            local cc = cfg.bgClassColored and classToken and CludesUI.GetClassColor(classToken)
            if cc then
                frame._bg:SetColorTexture(cc.r, cc.g, cc.b, bgA)
            else
                local bgc = cfg.customBgColor or defaultSet.customBgColor
                frame._bg:SetColorTexture(bgc.r, bgc.g, bgc.b, bgA)
            end
        end
    end

    -- Absorb shield preview (dual clip-frame: backfill + forward)
    if frame._absorbBar then
        local absStyle = cfg.absorbStyle or "none"
        if mod._indicatorsVisible then
            absStyle = "none"
        elseif mod._testMode then
            if mod._testAbsorbs == false then
                absStyle = "none"
            elseif mod._testAbsorbs and absStyle == "none" then
                absStyle = "striped"
            end
        elseif not mod._absorbsPreviewVisible then
            absStyle = "none"
        end
        local absorbAmt = mod.previewAbsorbValues[index] or 0
        local fw = frame._absorbBar._forward
        -- Absorb Bar (solid bar above the frame): same preview gating as the
        -- shield styles (indicators / test mode / absorbs eyeball).
        local topBar = frame._absorbBar._topBar
        if topBar then
            local barPos = mod.GetAbsorbBarPosition(cfg)
            local barOn = barPos ~= "none"
            if mod._indicatorsVisible then
                barOn = false
            elseif mod._testMode then
                if mod._testAbsorbs == false then barOn = false end
            elseif not mod._absorbsPreviewVisible then
                barOn = false
            end
            if barOn and absorbAmt > 0 then
                local bc = cfg.absorbBarColor or { r = 1, g = 1, b = 1 }
                -- (Party Frames kit: laid out on the kit bar and host, as live.)
                mod.ApplyStripBarLayout(
                    topBar,
                    frame._absorbBar,
                    ((frame.kit or frame._health._cuiBarArea) and frame._health) or frame,
                    barPos,
                    cfg.absorbBarHeight or 4,
                    nil,
                    nil,
                    cfg.absorbBarGrowDir or "up"
                )
                topBar:SetStatusBarColor(bc.r, bc.g, bc.b, bc.a or 1)
                topBar:SetValue(absorbAmt)
                topBar:Show()
            else
                topBar:Hide()
            end
        end
        -- Heal Absorb Bar preview (mirrors the Absorb Bar; gated on the heal
        -- absorb preview toggles).
        do
            local healTopBarPv = frame._absorbBar._healTopBar
            if healTopBarPv then
                local healBarPos = mod.GetHealAbsorbBarPosition(cfg)
                local healBarOn = healBarPos ~= "none"
                if mod._indicatorsVisible then
                    healBarOn = false
                elseif mod._testMode then
                    if mod._testHealAbsorbs == false then healBarOn = false end
                elseif not mod._absorbsPreviewVisible then
                    healBarOn = false
                end
                local haAmtPv = mod.previewHealAbsorbValues[index] or 0
                if healBarOn and haAmtPv > 0 then
                    local hbc = cfg.healAbsorbBarColor or { r = 200 / 255, g = 29 / 255, b = 29 / 255 }
                    mod.ApplyStripBarLayout(
                        healTopBarPv,
                        frame._absorbBar,
                        ((frame.kit or frame._health._cuiBarArea) and frame._health) or frame,
                        healBarPos,
                        cfg.healAbsorbBarHeight or 4,
                        mod.GetAbsorbBarPosition(cfg),
                        cfg.absorbBarHeight or 4,
                        cfg.healAbsorbBarGrowDir or "up"
                    )
                    healTopBarPv:SetStatusBarColor(hbc.r, hbc.g, hbc.b, hbc.a or 1)
                    healTopBarPv:SetValue(haAmtPv)
                    healTopBarPv:Show()
                else
                    healTopBarPv:Hide()
                end
            end
        end
        if absStyle ~= "none" and absorbAmt > 0 then
            local modern = (absStyle == "blizzardModern")
            local texture = mod.ResolveAbsorbStyleTex(absStyle, "Interface\\Buttons\\WHITE8X8")
            local alpha = (cfg.absorbOpacity or 90) / 100
            local tiled = (
                absStyle == "striped"
                or absStyle == "stripedReversed"
                or absStyle == "stripedThick"
                or absStyle == "stripedThickR"
                or absStyle == "largeStripes"
                or absStyle == "largeStripesR"
                or absStyle == "largeOutlinedStripes"
                or absStyle == "largeOutlinedStripesR"
                or absStyle == "pixelsShieldFill"
            )
            -- (the Party Frames kit's health bar is its own rect)
            local hpW = frame.kitG and frame.kitG.health.w or wid
            local hpH = frame.kitG and frame.kitG.health.h or healthH
            local mask = frame._absorbBar._mask
            local ac = cfg.absorbColor or { r = 1, g = 1, b = 1 }

            frame._absorbBar:SetWidth(hpW)
            frame._absorbBar:SetHeight(hpH)
            if fw then
                fw:SetWidth(hpW)
                fw:SetHeight(hpH)
            end

            if modern then
                -- Forward = modern texture; backfill = flat 10% white overshield (mirrors live).
                if fw then mod.ApplyModernAbsorbBar(fw, mask) end
                mod.HideModernAbsorbBase(frame._absorbBar)
                frame._absorbBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
                frame._absorbBar:SetStatusBarColor(1, 1, 1, 0.10)
                local bfFill = frame._absorbBar:GetStatusBarTexture()
                if bfFill then
                    bfFill:SetDrawLayer("ARTWORK", 1)
                    bfFill:SetHorizTile(false)
                    bfFill:SetVertTile(false)
                    if mask then mod.RF_AddMaskOnce(bfFill, mask) end
                end
            else
                mod.HideModernAbsorbBase(frame._absorbBar)
                if fw then mod.HideModernAbsorbBase(fw) end

                -- Apply style to backfill bar
                frame._absorbBar:SetStatusBarTexture(texture)
                frame._absorbBar:SetStatusBarColor(ac.r or 1, ac.g or 1, ac.b or 1, alpha)
                local bfFill = frame._absorbBar:GetStatusBarTexture()
                if bfFill then
                    bfFill:SetDrawLayer("ARTWORK", 1)
                    bfFill:SetHorizTile(tiled)
                    bfFill:SetVertTile(tiled)
                    if mask then mod.RF_AddMaskOnce(bfFill, mask) end
                end

                -- Apply style to forward bar
                if fw then
                    fw:SetStatusBarTexture(texture)
                    fw:SetStatusBarColor(ac.r or 1, ac.g or 1, ac.b or 1, alpha)
                    local fwFill = fw:GetStatusBarTexture()
                    if fwFill then
                        fwFill:SetDrawLayer("ARTWORK", 1)
                        fwFill:SetHorizTile(tiled)
                        fwFill:SetVertTile(tiled)
                        if mask then mod.RF_AddMaskOnce(fwFill, mask) end
                    end
                end
            end

            -- Feed both bars with the same absorb value; clip frames do the visual math.
            -- Mirror the live Show Overshield gate: when off (overlay-like modes) feed
            -- the backfill 0 so the overshield does not render in the preview.
            local pvOsm = cfg.overshieldMode
            if pvOsm == nil then pvOsm = (cfg.showOvershield == false) and "never" or "always" end
            local pvOvershieldOn = pvOsm ~= "never"
            local pvOverlayLike = modern or (cfg.absorbEdgeMode or "overlay") == "overlay"
            local pvAbValue = (not pvOvershieldOn and pvOverlayLike) and 0 or absorbAmt
            frame._absorbBar:SetMinMaxValues(0, 100)
            frame._absorbBar:SetValue(pvAbValue)
            frame._absorbBar:Show()
            if fw then
                fw:SetMinMaxValues(0, 100)
                fw:SetValue(absorbAmt)
                fw:Show()
            end

            -- Blizzard Glow Line (mirrors live, placements included; preview values are plain
            -- numbers, so overshield is a normal compare instead of isClamped). Unset follows
            -- the style: on for Default Blizz Frames only. Vertical fill hides it (see live).
            local pvGlowVert = mod.RF_IsVerticalFill(cfg)
            if modern and fw and not pvGlowVert then
                local fmb = fw._modernBase
                if fmb then fmb:SetAllPoints(fw:GetStatusBarTexture()) end
            end
            local pvGlowSet = cfg.absorbGlowLine
            local pvEm = cfg.absorbEdgeMode or "overlay"
            if
                (pvGlowSet == true or (pvGlowSet == nil and modern))
                and fw
                and not pvGlowVert
                and (modern or pvEm ~= "left")
            then
                local ge
                if modern then
                    ge = 1
                elseif pvEm == "overlay" then
                    ge = (pvOsm == "fromleft") and 2 or 1
                elseif pvEm == "right" then
                    ge = 5
                else
                    ge = 3
                end
                local bft = frame._absorbBar:GetStatusBarTexture()
                local previewOver = absorbAmt > (100 - (healthPct or 100))
                local g, sp = fw._edgeGate, fw._edgeSpark
                if g and sp then
                    g:SetHeight(hpH)
                    g:ClearAllPoints()
                    if ge >= 3 then
                        g:SetPoint("CENTER", bft, "LEFT", -1, 0)
                    else
                        g:SetPoint("CENTER", fw, "LEFT", -1, 0)
                    end
                    g:SetValue(absorbAmt)
                    sp:SetAllPoints(g:GetStatusBarTexture())
                    local spOn = true
                    if ge <= 2 then
                        spOn = not previewOver
                    elseif ge == 5 then
                        spOn = previewOver
                    end
                    sp:SetAlpha(spOn and 1 or 0)
                    sp:Show()
                end
                local bsp = fw._bfSpark
                if bsp then
                    if ge <= 2 then
                        bsp:SetSize(16, hpH)
                        bsp:ClearAllPoints()
                        if not pvOvershieldOn then
                            bsp:SetPoint("CENTER", frame._absorbBar, "RIGHT", -1, 0)
                        elseif ge == 2 then
                            bsp:SetPoint("CENTER", bft, "RIGHT", 1, 0)
                        else
                            bsp:SetPoint("CENTER", bft, "LEFT", -1, 0)
                        end
                        bsp:SetAlpha(previewOver and 1 or 0)
                        bsp:Show()
                    else
                        bsp:Hide()
                    end
                end
            elseif fw and fw._edgeSpark then
                fw._edgeSpark:Hide()
                if fw._bfSpark then fw._bfSpark:Hide() end
            end
        else
            frame._absorbBar:Hide()
            if fw then fw:Hide() end
            mod.HideModernAbsorbBase(frame._absorbBar)
            if fw then mod.HideModernAbsorbBase(fw) end
            if fw and fw._edgeSpark then fw._edgeSpark:Hide() end
            if fw and fw._bfSpark then fw._bfSpark:Hide() end
        end
        -- Position clip frames + backfill based on shield absorb placement
        -- (mirrors the live ReanchorAbsorbToFill).
        local cc = frame._absorbBar._curClip
        local mc = frame._absorbBar._missClip
        if cc and mc and frame._health then
            local absorbMode = cfg.absorbEdgeMode or "overlay"
            -- Overlay Reverse (Full): Overlay Reverse plus the origin-edge forward bar for the
            -- excess (mirrors live; Default Blizz Frames keeps plain Overlay Reverse).
            local pvOrFull = absorbMode == "overlayReverseFull" and cfg.absorbStyle ~= "blizzardModern"
            -- Vertical fill: same layout with the axis swapped (the fill's right
            -- edge becomes its top edge). Mirrors the live vertical branch.
            local pvAbVert = mod.RF_IsVerticalFill(cfg)
            local hpA, hpB = mod.RF_HpEdge(pvAbVert, pvInvert)
            local pvAxisBars = { frame._absorbBar, fw }
            for index = 1, 2 do
                local widget = pvAxisBars[index]
                if widget then
                    widget:SetOrientation(pvAbVert and "VERTICAL" or "HORIZONTAL")
                    mod.RF_ApplyFillRotation(widget)
                end
            end
            if pvAbVert then
                local vfill = frame._health:GetStatusBarTexture()
                if absorbMode == "right" or absorbMode == "left" then
                    cc:ClearAllPoints()
                    cc:SetPoint("TOPLEFT", frame._health, "TOPLEFT", 0, 0)
                    cc:SetPoint("BOTTOMRIGHT", frame._health, "BOTTOMRIGHT", 0, 0)
                    frame._absorbBar:ClearAllPoints()
                    if absorbMode == "left" then
                        frame._absorbBar:SetReverseFill(false)
                        frame._absorbBar:SetPoint("BOTTOMLEFT", frame._health, "BOTTOMLEFT", 0, 0)
                        frame._absorbBar:SetPoint("BOTTOMRIGHT", frame._health, "BOTTOMRIGHT", 0, 0)
                    else
                        frame._absorbBar:SetReverseFill(true)
                        frame._absorbBar:SetPoint("TOPLEFT", frame._health, "TOPLEFT", 0, 0)
                        frame._absorbBar:SetPoint("TOPRIGHT", frame._health, "TOPRIGHT", 0, 0)
                    end
                    if fw then fw:Hide() end
                elseif absorbMode == "overlayReverse" or absorbMode == "overlayReverseFull" then
                    -- Whole absorb fills DOWN into the fill from its top edge;
                    -- the filled-region clip masks excess (mirrors live). Full
                    -- draws that excess through the forward bar instead.
                    cc:ClearAllPoints()
                    cc:SetPoint("BOTTOMLEFT", frame._health, "BOTTOMLEFT", 0, 0)
                    cc:SetPoint("TOPRIGHT", vfill, hpB, 0, 0)
                    frame._absorbBar:SetReverseFill(true)
                    frame._absorbBar:ClearAllPoints()
                    frame._absorbBar:SetPoint("TOPLEFT", vfill, hpA, 0, 0)
                    frame._absorbBar:SetPoint("TOPRIGHT", vfill, hpB, 0, 0)
                    if pvOrFull then
                        mc:ClearAllPoints()
                        mc:SetPoint("BOTTOMLEFT", vfill, hpA, 0, 0)
                        mc:SetPoint("TOPRIGHT", frame._health, "TOPRIGHT", 0, 0)
                    elseif fw then
                        fw:Hide()
                    end
                else
                    cc:ClearAllPoints()
                    cc:SetPoint("BOTTOMLEFT", frame._health, "BOTTOMLEFT", 0, 0)
                    cc:SetPoint("TOPRIGHT", vfill, hpB, 0, 0)
                    mc:ClearAllPoints()
                    mc:SetPoint("BOTTOMLEFT", vfill, hpA, 0, -1)
                    mc:SetPoint("TOPRIGHT", frame._health, "TOPRIGHT", 0, 0)
                    frame._absorbBar:ClearAllPoints()
                    local pvOsm2 = cfg.overshieldMode
                    if pvOsm2 == nil then pvOsm2 = (cfg.showOvershield == false) and "never" or "always" end
                    if pvOsm2 == "fromleft" and cfg.absorbStyle ~= "blizzardModern" then
                        frame._absorbBar:SetReverseFill(false)
                        frame._absorbBar:SetPoint("TOPLEFT", vfill, hpA, 0, 0)
                        frame._absorbBar:SetPoint("TOPRIGHT", vfill, hpB, 0, 0)
                    else
                        frame._absorbBar:SetReverseFill(true)
                        frame._absorbBar:SetPoint("TOPLEFT", frame._health, "TOPLEFT", 0, 0)
                        frame._absorbBar:SetPoint("TOPRIGHT", frame._health, "TOPRIGHT", 0, 0)
                    end
                end
                if fw then
                    fw:ClearAllPoints()
                    if pvOrFull then
                        fw:SetPoint("BOTTOMLEFT", frame._health, "BOTTOMLEFT", 0, 0)
                        fw:SetPoint("BOTTOMRIGHT", frame._health, "BOTTOMRIGHT", 0, 0)
                    else
                        fw:SetPoint("BOTTOMLEFT", vfill, hpA, 0, 0)
                        fw:SetPoint("BOTTOMRIGHT", vfill, hpB, 0, 0)
                    end
                end
            elseif absorbMode == "right" or absorbMode == "left" then
                cc:ClearAllPoints()
                cc:SetPoint("TOPLEFT", frame._health, "TOPLEFT", 0, 0)
                cc:SetPoint("BOTTOMRIGHT", frame._health, "BOTTOMRIGHT", 0, 0)
                frame._absorbBar:ClearAllPoints()
                if absorbMode == "left" then
                    frame._absorbBar:SetReverseFill(false)
                    frame._absorbBar:SetPoint("TOPLEFT", frame._health, "TOPLEFT", 0, 0)
                    frame._absorbBar:SetPoint("BOTTOMLEFT", frame._health, "BOTTOMLEFT", 0, 0)
                else
                    frame._absorbBar:SetReverseFill(true)
                    frame._absorbBar:SetPoint("TOPRIGHT", frame._health, "TOPRIGHT", 0, 0)
                    frame._absorbBar:SetPoint("BOTTOMRIGHT", frame._health, "BOTTOMRIGHT", 0, 0)
                end
                if fw then fw:Hide() end
            elseif absorbMode == "overlayReverse" or absorbMode == "overlayReverseFull" then
                -- Whole absorb backfills from the fill's leading edge INTO the
                -- fill; the filled-region clip masks excess (mirrors live). Full
                -- draws that excess through the forward bar instead.
                local fillTex = frame._health:GetStatusBarTexture()
                cc:ClearAllPoints()
                cc:SetPoint("TOPLEFT", frame._health, "TOPLEFT", 0, 0)
                cc:SetPoint("BOTTOMRIGHT", fillTex, hpB, 0, 0)
                frame._absorbBar:SetReverseFill(true)
                frame._absorbBar:ClearAllPoints()
                frame._absorbBar:SetPoint("TOPRIGHT", fillTex, hpA, 0, 0)
                frame._absorbBar:SetPoint("BOTTOMRIGHT", fillTex, hpB, 0, 0)
                if pvOrFull then
                    mc:ClearAllPoints()
                    mc:SetPoint("TOPLEFT", fillTex, hpA, 0, 0)
                    mc:SetPoint("BOTTOMRIGHT", frame._health, "BOTTOMRIGHT", 0, 0)
                elseif fw then
                    fw:Hide()
                end
            else
                local fillTex = frame._health:GetStatusBarTexture()
                cc:ClearAllPoints()
                cc:SetPoint("TOPLEFT", frame._health, "TOPLEFT", 0, 0)
                cc:SetPoint("BOTTOMRIGHT", fillTex, hpB, 0, 0)
                mc:ClearAllPoints()
                mc:SetPoint("TOPLEFT", fillTex, hpA, -1, 0)
                mc:SetPoint("BOTTOMRIGHT", frame._health, "BOTTOMRIGHT", 0, 0)
                -- Overlay backfill: overshield "From Left" mirrors the live
                -- anchors (fill-edge + forward fill); else the classic
                -- right-anchored reverse fill.
                frame._absorbBar:ClearAllPoints()
                local pvOsm2 = cfg.overshieldMode
                if pvOsm2 == nil then pvOsm2 = (cfg.showOvershield == false) and "never" or "always" end
                if pvOsm2 == "fromleft" and cfg.absorbStyle ~= "blizzardModern" then
                    frame._absorbBar:SetReverseFill(false)
                    frame._absorbBar:SetPoint("TOPRIGHT", fillTex, hpA, 0, 0)
                    frame._absorbBar:SetPoint("BOTTOMRIGHT", fillTex, hpB, 0, 0)
                else
                    frame._absorbBar:SetReverseFill(true)
                    frame._absorbBar:SetPoint("TOPRIGHT", frame._health, "TOPRIGHT", 0, 0)
                    frame._absorbBar:SetPoint("BOTTOMRIGHT", frame._health, "BOTTOMRIGHT", 0, 0)
                end
            end
            -- Restore the forward bar's horizontal anchors (the vertical branch
            -- above re-points it, and these are otherwise only set at creation).
            if not pvAbVert and fw then
                local hfill = frame._health:GetStatusBarTexture()
                fw:ClearAllPoints()
                if pvOrFull then
                    fw:SetPoint("TOPLEFT", frame._health, "TOPLEFT", 0, 0)
                    fw:SetPoint("BOTTOMLEFT", frame._health, "BOTTOMLEFT", 0, 0)
                else
                    fw:SetPoint("TOPLEFT", hfill, hpA, 0, 0)
                    fw:SetPoint("BOTTOMLEFT", hfill, hpB, 0, 0)
                end
            end
        end
    end

    -- Heal absorb preview
    if frame._healAbsorbBar then
        local haStyle = cfg.healAbsorbStyle or "clean"
        if mod._indicatorsVisible then
            haStyle = "none"
        elseif mod._testMode then
            if mod._testHealAbsorbs == false then
                haStyle = "none"
            elseif mod._testHealAbsorbs and haStyle == "none" then
                haStyle = "clean"
            end
        elseif not mod._absorbsPreviewVisible then
            haStyle = "none"
        end
        local haAmt = mod.previewHealAbsorbValues[index] or 0
        if haStyle ~= "none" and haAmt > 0 then
            local haTex = mod.ResolveAbsorbStyleTex(haStyle, "Interface\\Buttons\\WHITE8X8")
            local haAlpha = (cfg.healAbsorbOpacity or 75) / 100
            local hc = cfg.healAbsorbColor or { r = 0.8, g = 0.15, b = 0.15 }
            if
                haStyle == "healBlizzModern"
                or haStyle == "largeOutlinedStripes"
                or haStyle == "largeOutlinedStripesR"
            then
                hc = { r = 1, g = 1, b = 1 }
            end
            local tiled = (
                haStyle == "striped"
                or haStyle == "stripedReversed"
                or haStyle == "stripedThick"
                or haStyle == "stripedThickR"
                or haStyle == "largeStripes"
                or haStyle == "largeStripesR"
                or haStyle == "largeOutlinedStripes"
                or haStyle == "largeOutlinedStripesR"
                or haStyle == "pixelsShieldFill"
            )
            local hpW = frame.kitG and frame.kitG.health.w or wid
            local hpH = frame.kitG and frame.kitG.health.h or healthH
            local mask = frame._healAbsorbBar._mask
            frame._healAbsorbBar:SetStatusBarTexture(haTex)
            frame._healAbsorbBar:SetStatusBarColor(hc.r or 0.8, hc.g or 0.15, hc.b or 0.15, haAlpha)
            frame._healAbsorbBar:SetWidth(hpW)
            frame._healAbsorbBar:SetHeight(hpH)
            local haFillPv = frame._healAbsorbBar:GetStatusBarTexture()
            if haFillPv then
                haFillPv:SetDrawLayer("ARTWORK", 2)
                haFillPv:SetHorizTile(tiled)
                haFillPv:SetVertTile(tiled)
                if mask then mod.RF_AddMaskOnce(haFillPv, mask) end
            end
            frame._healAbsorbBar:SetMinMaxValues(0, 100)
            frame._healAbsorbBar:SetValue(haAmt)
            frame._healAbsorbBar:Show()
            local hbg = frame._healAbsorbBar._bg
            if hbg then
                hbg:SetColorTexture(0, 0, 0, (cfg.healAbsorbBgOpacity or 25) / 100)
                hbg:SetAllPoints(frame._healAbsorbBar:GetStatusBarTexture())
                hbg:Show()
            end
        else
            frame._healAbsorbBar:Hide()
        end
        -- Heal absorb placement (independent of shield absorb; mirrors live).
        if frame._health then
            local healMode = cfg.healAbsorbEdgeMode or "overlay"
            -- Vertical fill: same layout, axis swapped (mirrors the live branch).
            local pvHaVert = mod.RF_IsVerticalFill(cfg)
            local hpA, hpB = mod.RF_HpEdge(pvHaVert, pvInvert)
            frame._healAbsorbBar:SetOrientation(pvHaVert and "VERTICAL" or "HORIZONTAL")
            mod.RF_ApplyFillRotation(frame._healAbsorbBar)
            if pvHaVert then
                local vfill = frame._health:GetStatusBarTexture()
                if frame._healClip then
                    frame._healClip:ClearAllPoints()
                    if healMode == "right" or healMode == "left" then
                        frame._healClip:SetPoint("TOPLEFT", frame._health, "TOPLEFT", 0, 0)
                        frame._healClip:SetPoint("BOTTOMRIGHT", frame._health, "BOTTOMRIGHT", 0, 0)
                    else
                        frame._healClip:SetPoint("BOTTOMLEFT", frame._health, "BOTTOMLEFT", 0, 0)
                        frame._healClip:SetPoint("TOPRIGHT", vfill, hpB, 0, 0)
                    end
                end
                frame._healAbsorbBar:ClearAllPoints()
                if healMode == "right" then
                    frame._healAbsorbBar:SetReverseFill(true)
                    frame._healAbsorbBar:SetPoint("TOPLEFT", frame._health, "TOPLEFT", 0, 0)
                    frame._healAbsorbBar:SetPoint("TOPRIGHT", frame._health, "TOPRIGHT", 0, 0)
                elseif healMode == "left" then
                    frame._healAbsorbBar:SetReverseFill(false)
                    frame._healAbsorbBar:SetPoint("BOTTOMLEFT", frame._health, "BOTTOMLEFT", 0, 0)
                    frame._healAbsorbBar:SetPoint("BOTTOMRIGHT", frame._health, "BOTTOMRIGHT", 0, 0)
                else
                    frame._healAbsorbBar:SetReverseFill(true)
                    frame._healAbsorbBar:SetPoint("TOPLEFT", vfill, hpA, 0, 0)
                    frame._healAbsorbBar:SetPoint("TOPRIGHT", vfill, hpB, 0, 0)
                end
            else
                if frame._healClip then
                    frame._healClip:ClearAllPoints()
                    if healMode == "right" or healMode == "left" then
                        frame._healClip:SetPoint("TOPLEFT", frame._health, "TOPLEFT", 0, 0)
                        frame._healClip:SetPoint("BOTTOMRIGHT", frame._health, "BOTTOMRIGHT", 0, 0)
                    else
                        frame._healClip:SetPoint("TOPLEFT", frame._health, "TOPLEFT", 0, 0)
                        frame._healClip:SetPoint(
                            "BOTTOMRIGHT",
                            frame._health:GetStatusBarTexture(),
                            hpB,
                            0,
                            0
                        )
                    end
                end
                frame._healAbsorbBar:ClearAllPoints()
                if healMode == "right" then
                    frame._healAbsorbBar:SetReverseFill(true)
                    frame._healAbsorbBar:SetPoint("TOPRIGHT", frame._health, "TOPRIGHT", 0, 0)
                    frame._healAbsorbBar:SetPoint("BOTTOMRIGHT", frame._health, "BOTTOMRIGHT", 0, 0)
                elseif healMode == "left" then
                    frame._healAbsorbBar:SetReverseFill(false)
                    frame._healAbsorbBar:SetPoint("TOPLEFT", frame._health, "TOPLEFT", 0, 0)
                    frame._healAbsorbBar:SetPoint("BOTTOMLEFT", frame._health, "BOTTOMLEFT", 0, 0)
                else
                    local fillTex = frame._health:GetStatusBarTexture()
                    frame._healAbsorbBar:SetReverseFill(true)
                    frame._healAbsorbBar:SetPoint("TOPRIGHT", fillTex, hpA, 0, 0)
                    frame._healAbsorbBar:SetPoint("BOTTOMRIGHT", fillTex, hpB, 0, 0)
                end
            end
        end
    end

    -- Heal prediction preview
    if frame._healPredBar then
        local predAmt = mod.previewHealPredValues and mod.previewHealPredValues[index] or 0
        local wantPred = cfg.healPrediction
        if mod._indicatorsVisible then
            wantPred = false
        elseif mod._testMode and mod._testHealPrediction ~= nil then
            wantPred = mod._testHealPrediction
        end
        if wantPred and predAmt > 0 then
            local pc = cfg.healPredColor or { r = 102 / 255, g = 243 / 255, b = 102 / 255 }
            local pAlpha = (cfg.healPredOpacity or 75) / 100
            frame._healPredBar:SetStatusBarColor(pc.r, pc.g, pc.b, pAlpha)
            frame._healPredBar:SetWidth(frame.kitG and frame.kitG.health.w or wid)
            frame._healPredBar:SetHeight(frame.kitG and frame.kitG.health.h or healthH)
            -- Grows from the HP edge into the missing health: the fill's right
            -- edge normally, its top edge on a vertical bar. Only set at creation
            -- otherwise, so both axes are re-applied here.
            do
                local pvPredVert = mod.RF_IsVerticalFill(cfg)
                local pFill = frame._health and frame._health:GetStatusBarTexture()
                frame._healPredBar:SetOrientation(pvPredVert and "VERTICAL" or "HORIZONTAL")
                mod.RF_ApplyFillRotation(frame._healPredBar)
                if pFill then
                    local hpA, hpB = mod.RF_HpEdge(pvPredVert, pvInvert)
                    frame._healPredBar:ClearAllPoints()
                    if pvPredVert then
                        frame._healPredBar:SetPoint("BOTTOMLEFT", pFill, hpA, 0, 0)
                        frame._healPredBar:SetPoint("BOTTOMRIGHT", pFill, hpB, 0, 0)
                    else
                        frame._healPredBar:SetPoint("TOPLEFT", pFill, hpA, 0, 0)
                        frame._healPredBar:SetPoint("BOTTOMLEFT", pFill, hpB, 0, 0)
                    end
                end
            end
            frame._healPredBar:SetMinMaxValues(0, 100)
            frame._healPredBar:SetValue(predAmt)
            frame._healPredBar:Show()
        else
            frame._healPredBar:Hide()
        end
    end

    -- Reduced max health preview
    if frame._reducedMaxHealthBar then
        local rmhAmt = mod.previewReducedMaxHealth and mod.previewReducedMaxHealth[index] or 0
        local rmhStyle = cfg.maxHealthStyle or "maxHealthStripes"
        -- Show in the Full Preview (Reduced Max Health test toggle) AND in the
        -- Absorbs-section preview (the shield-effects eye), mirroring Heal Absorb.
        local rmhShow = mod._testReducedMaxHealth
            or (not mod._testMode and not mod._indicatorsVisible and mod._absorbsPreviewVisible)
        if rmhShow and rmhAmt > 0 and rmhStyle ~= "none" then
            mod.ApplyMaxHealthStyle(frame._reducedMaxHealthBar, rmhStyle, cfg)
            do -- eats the far end of the bar: the right edge, or the top when vertical
                local pvRmhVert = mod.RF_IsVerticalFill(cfg)
                frame._reducedMaxHealthBar:SetOrientation(pvRmhVert and "VERTICAL" or "HORIZONTAL")
                mod.RF_ApplyFillRotation(frame._reducedMaxHealthBar)
            end
            frame._reducedMaxHealthBar:SetValue(rmhAmt)
            local rmhBg = frame._reducedMaxHealthBg
            if rmhBg then
                rmhBg:SetColorTexture(0, 0, 0, (cfg.maxHealthBgOpacity or 100) / 100)
                rmhBg:SetAllPoints(frame._reducedMaxHealthBar:GetStatusBarTexture())
            end
            frame._reducedMaxHealthBar:Show()
        else
            frame._reducedMaxHealthBar:Hide()
        end
    end

    -- Power (filtered by role, hidden if class has no power)
    local role = previewRoles[index] or "DAMAGER"
    local showForRole = (role == "HEALER" and cfg.powerShowForHealer)
        or (role == "TANK" and cfg.powerShowForTank)
        or (role == "DAMAGER" and cfg.powerShowForDPS)
    local hidePower = powerH <= 0 or not showForRole
    -- Party Frames kit: the stock mana bar always shows (the kit pass sizes it).
    if frame.kitG then hidePower = false end

    if frame._power then
        if not hidePower then
            frame._power:SetHeight(powerH)
            frame._power:SetStatusBarTexture(ResolveHealthTexture())
            frame._power:GetStatusBarTexture():SetHorizTile(false)
            local pwPct = previewPowerValues[index] or (60 + math.random(40))
            frame._power:SetMinMaxValues(0, 100)
            frame._power:SetValue(pwPct)
            frame._powerPct = pwPct
            local pwToken = CludesUI.CLASS_POWER_MAP[classToken] or "MANA"
            local pc = CludesUI.GetPowerColor(pwToken)
            if pc then
                frame._power:SetStatusBarColor(pc.r, pc.g, pc.b, 1)
            else
                frame._power:SetStatusBarColor(0, 0.5, 1, 1)
            end
            frame._power:Show()
        else
            frame._power:Hide()
        end
    end

    -- Expand health to full frame when power is hidden (still reserving the Top
    -- Name Bar's height from the top; its anchor was set by LayoutTopNameBar)
    if frame._health then
        if hidePower then
            frame._health:SetHeight(hgt - topBarH)
        else
            frame._health:SetHeight(healthH - topBarH)
        end
    end

    if frame._powerBg then
        if hidePower then
            frame._powerBg:Hide()
        else
            local bgc = CludesUI.GetPowerColor
                and cfg.powerBgPowerColored
                and CludesUI.GetPowerColor(CludesUI.CLASS_POWER_MAP[classToken] or "MANA")
            local popFrame = bgc and CludesUI.GetPowerBgDarkenFactor() or 1
            bgc = bgc or cfg.powerBgColor
            mod.RF_TexBgTint(frame._powerBg, mod.RF_TexBgPath(cfg))
            frame._powerBg:SetColorTexture(
                ((bgc or {}).r or 0) * popFrame,
                ((bgc or {}).g or 0) * popFrame,
                ((bgc or {}).b or 0) * popFrame,
                (cfg.powerBgDarkness or 70) / 100
            )
            frame._powerBg:Show()
        end
    end

    -- Power border (Classic WoW UI: the stock divider stands in, drawn with
    -- the frame border below)
    if frame._powerBorder and Pix then
        if hidePower or frame.stockDiv or frame.kitG then
            if frame._powerBorder._powerArtKey then mod.RF_ClearPowerBorderArt(frame._powerBorder) end
            frame._powerBorder:Hide()
        elseif
            not (
                (cfg.powerBorderMatchFrame == true or frame._powerBorder._powerArtKey)
                and mod.RF_ApplyPowerBorderArt(frame._powerBorder, cfg, true, true)
            )
        then
            local pbStyle = cfg.powerBorderStyle or "cui"
            if pbStyle == "cui" then
                Pix.UpdateBorder(frame._powerBorder, 1, 1, 1, 1, 0.2)
                frame._powerBorder:Show()
                local ppC = Pix.GetBorders(frame._powerBorder)
                if ppC then
                    if ppC._bottom then ppC._bottom:SetAlpha(0) end
                    if ppC._left then ppC._left:SetAlpha(0) end
                    if ppC._right then ppC._right:SetAlpha(0) end
                    if ppC._top then ppC._top:SetAlpha(0.2) end
                end
            else
                local pbSize = cfg.powerBorderSize or 1
                if pbSize <= 0 then
                    frame._powerBorder:Hide()
                else
                    local pbc = cfg.powerBorderColor
                    local pba = cfg.powerBorderAlpha or 1
                    Pix.UpdateBorder(frame._powerBorder, pbSize, pbc.r, pbc.g, pbc.b, pba)
                    frame._powerBorder:Show()
                    local ppC = Pix.GetBorders(frame._powerBorder)
                    if ppC then
                        if pbStyle == "divider" then
                            if ppC._bottom then ppC._bottom:SetAlpha(0) end
                            if ppC._left then ppC._left:SetAlpha(0) end
                            if ppC._right then ppC._right:SetAlpha(0) end
                            if ppC._top then ppC._top:SetAlpha(pba) end
                        else
                            if ppC._top then ppC._top:SetAlpha(pba) end
                            if ppC._bottom then ppC._bottom:SetAlpha(pba) end
                            if ppC._left then ppC._left:SetAlpha(pba) end
                            if ppC._right then ppC._right:SetAlpha(pba) end
                        end
                    end
                end
            end
        end
    end

    -- Border (style/size/texture/offsets via ApplyBorderStyle, then state recolor)
    if frame._border and Pix and frame.kit then
        -- Party Frames kit: the art stands in for the border.
        frame._border:SetFrameLevel(frame:GetFrameLevel() + 8)
        CludesUI.ApplyBorderStyle(frame._border, 0, 0, 0, 0, 0, "solid")
        frame._border._hlBorderSize = nil
        if frame._ApplyBorderColor then frame._ApplyBorderColor() end
    elseif frame._border and Pix and frame.stockEdge then
        frame._border:SetFrameLevel(frame:GetFrameLevel() + 8)
        CludesUI.ApplyBorderStyle(frame._border, 0, 0, 0, 0, 0, "solid")
        frame._border._hlBorderSize = nil
        mod.RF_StockSeat(frame)
        if frame.stockDiv and frame._power and frame._power:IsShown() then mod.RF_StockDivider(frame) end
        if frame._ApplyBorderColor then frame._ApplyBorderColor() end
    elseif frame._border and Pix and compact then
        CludesUI.ApplyBorderStyle(frame._border, 0, 0, 0, 0, 0, "solid")
        if frame._ApplyBorderColor then frame._ApplyBorderColor() end
    elseif frame._border and Pix then
        local bs = cfg.borderSize or 1
        local bc = cfg.borderColor or { r = 0, g = 0, b = 0 }
        local pl = frame:GetFrameLevel()
        frame._border:SetFrameLevel(cfg.borderBehind and math.max(0, pl - 1) or (pl + 8))
        CludesUI.ApplyBorderStyle(
            frame._border,
            bs,
            bc.r,
            bc.g,
            bc.b,
            cfg.borderAlpha or 1,
            cfg.borderTexture or "solid",
            cfg.borderTextureOffset,
            cfg.borderTextureOffsetY,
            cfg.borderTextureShiftX,
            cfg.borderTextureShiftY,
            "unitframes",
            bs,
            nil,
            CludesUI.BorderPx(cfg.borderSizePx, bs, cfg.borderTexture or "solid")
        )
        if frame._ApplyBorderColor then frame._ApplyBorderColor() end
    end
    -- Rounded corners, as on the live cells (stock styles stay square).
    if frame._border then
        local radius = (frame.kit or frame.stockEdge or compact) and 0 or (cfg.cornerRadius or 0)
        if radius > 0 then
            CludesUI.RoundCorners(frame, radius, {
                roots = { frame._health, frame._power, frame._topNameBar, frame._powerBorder },
                textures = { frame._bg },
                border = frame._border,
                style = cfg.borderTexture or "solid",
                corners = cfg.cornerMask,
            })
        else
            CludesUI.RoundCorners(frame, 0)
        end
    end

    -- Indicators visibility (eyeball toggle)
    local indVis = mod._indicatorsVisible ~= false

    -- Threat border (always visible in test mode, otherwise requires animation).
    -- Color Custom Borders recolors the frame border instead of drawing this one
    -- (PvApplyBorderColor), so the slider size does not gate it.
    if frame._threatFrame and Pix then
        local bs = cfg.threatBorderSize or 0
        local rc = not compact and cfg.threatCustomBorder == true and mod.RF_CustomBorderOn(cfg)
        local wantThreat = bs > 0 or rc
        if mod._testMode and mod._testThreat ~= nil then wantThreat = mod._testThreat end
        local showThreat = wantThreat
            and (mod._testMode or mod._healthAnimActive)
            and previewRoles._threatIndex == index
        local agg
        if frame.stockHl then
            frame._threatFrame:Hide()
            mod.RF_StockAggro(frame, showThreat and 3 or nil)
        elseif showThreat and not rc then
            Pix.UpdateBorder(frame._threatFrame, bs > 0 and bs or 1, 1, 0, 0, 1)
            frame._threatFrame:Show()
        else
            frame._threatFrame:Hide()
            agg = (showThreat and rc) and true or nil
        end
        if frame._pvAggroBdr ~= agg then
            frame._pvAggroBdr = agg
            if frame._ApplyBorderColor then frame._ApplyBorderColor() end
        end
    end

    -- Dispel visuals (border, overlay, icon)
    local dispVis = mod._dispelsVisible ~= false
    local dispelMap = previewRoles._dispelMap
    local dispelType = dispelMap and dispelMap[index]
    local dispelDC = dispelType and GetDispelColor(dispelType, cfg)
    -- Color Custom Borders: the border takes the type color (PvApplyBorderColor,
    -- below hover/target and aggro), only over a custom border like the real
    -- frames; a change repaints it, the border pass above ran first.
    do
        local bdrC = dispVis
                and dispelDC
                and cfg.dispelCustomBorder == true
                and not compact
                and (dispelDC.a or 1) > 0
                and mod.RF_CustomBorderOn(cfg)
                and dispelDC
            or nil
        if frame._pvDispelBdrC ~= bdrC then
            frame._pvDispelBdrC = bdrC
            if frame._ApplyBorderColor then frame._ApplyBorderColor() end
        end
    end
    if dispVis and dispelDC then
        -- Per-type alpha (plain saved value in the preview path)
        local dcA = dispelDC.a or 1
        -- Dispel border (PP.UpdateBorder handles physical pixel sizing internally)
        local dbs = cfg.dispelBorderSize or 2
        if frame._dispelBdrFrame and Pix and dbs > 0 then
            Pix.UpdateBorder(frame._dispelBdrFrame, dbs, dispelDC.r, dispelDC.g, dispelDC.b, dcA)
            frame._dispelBdrFrame:Show()
        elseif frame._dispelBdrFrame then
            frame._dispelBdrFrame:Hide()
        end
        -- Dispel overlay
        local olMode = cfg.dispelOverlay or "fill"
        if olMode ~= "none" and frame._dispelOLTex and frame._health then
            local olAlpha = (cfg.dispelOverlayOpacity or 100) / 100 * dcA
            local olTex = frame._dispelOLTex
            olTex:ClearAllPoints()
            -- Reset any prior vertex tint so fill/full render their explicit color cleanly.
            olTex:SetVertexColor(1, 1, 1, 1)
            olTex:SetTexCoord(0, 1, 0, 1)
            if olMode == "fill" then
                -- Current health, as on the live frames (the fill, or the rest of
                -- the bar under Inverted Fill), off the bar oriented above.
                mod.RF_AnchorCurHealth(olTex, frame._health, frame._health:GetStatusBarTexture())
                olTex:SetColorTexture(dispelDC.r, dispelDC.g, dispelDC.b, olAlpha)
            elseif olMode == "full" then
                olTex:SetAllPoints(frame._health)
                olTex:SetColorTexture(dispelDC.r, dispelDC.g, dispelDC.b, olAlpha)
            elseif olMode == "gradient" or olMode == "gradient_sharp" or olMode == "gradient_reverse" then
                -- Same pre-baked gradient textures as the live frames so the preview matches.
                olTex:SetAllPoints(frame._health)
                olTex:SetTexture(
                    olMode == "gradient" and "Interface\\AddOns\\CludesUI\\media\\textures\\gradient-tb.tga"
                        or "Interface\\AddOns\\CludesUI\\media\\textures\\gradient-sharp.tga"
                )
                if olMode == "gradient_reverse" then olTex:SetTexCoord(0, 1, 1, 0) end
                olTex:SetVertexColor(dispelDC.r, dispelDC.g, dispelDC.b, olAlpha)
            end
            olTex:Show()
        elseif frame._dispelOLTex then
            frame._dispelOLTex:Hide()
        end
        -- Dispel type icon (positioned per setting)
        if cfg.showDispelIcons and frame._dispelIcon and frame._dispelIconTex then
            local atlas = DISPEL_ICON_ATLAS[dispelType]
            if atlas then frame._dispelIconTex:SetAtlas(atlas) end
            frame._dispelIcon:ClearAllPoints()
            local diSz = cfg.dispelIconSize or 16
            frame._dispelIcon:SetSize(diSz, diSz)
            local diPos = cfg.dispelIconPosition or "center"
            local diOX = cfg.dispelIconOffsetX or 0
            local diOY = cfg.dispelIconOffsetY or 0
            -- Dispel icon anchors flush to the health bar edge (no 1px inset),
            -- matching the debuff/role icon displays.
            local diHost = mod.RF_AnchorHost(frame._health, cfg)
            if diPos == "topleft" then
                frame._dispelIcon:SetPoint("TOPLEFT", diHost, "TOPLEFT", diOX, diOY)
            elseif diPos == "top" then
                frame._dispelIcon:SetPoint("TOP", diHost, "TOP", diOX, diOY)
            elseif diPos == "topright" then
                frame._dispelIcon:SetPoint("TOPRIGHT", diHost, "TOPRIGHT", diOX, diOY)
            elseif diPos == "left" then
                frame._dispelIcon:SetPoint("LEFT", diHost, "LEFT", diOX, diOY)
            elseif diPos == "right" then
                frame._dispelIcon:SetPoint("RIGHT", diHost, "RIGHT", diOX, diOY)
            elseif diPos == "bottomleft" then
                frame._dispelIcon:SetPoint("BOTTOMLEFT", diHost, "BOTTOMLEFT", diOX, diOY)
            elseif diPos == "bottom" then
                frame._dispelIcon:SetPoint("BOTTOM", diHost, "BOTTOM", diOX, diOY)
            elseif diPos == "bottomright" then
                frame._dispelIcon:SetPoint("BOTTOMRIGHT", diHost, "BOTTOMRIGHT", diOX, diOY)
            else -- center
                frame._dispelIcon:SetPoint("CENTER", diHost, "CENTER", diOX, diOY)
            end
            frame._dispelIcon:Show()
        elseif frame._dispelIcon then
            frame._dispelIcon:Hide()
        end
    else
        if frame._dispelBdrFrame then frame._dispelBdrFrame:Hide() end
        if frame._dispelOLTex then frame._dispelOLTex:Hide() end
        if frame._dispelIcon then frame._dispelIcon:Hide() end
    end

    -- Static dispel debuff icon (shows a fake debuff matching user's debuff settings)
    if frame._pvDispelDebuff then
        if dispVis and dispelType and mod._PV_DISPEL_DB_ICONS[dispelType] then
            local ddi = frame._pvDispelDebuff
            -- When dispellable debuffs are routed to their own anchor, the
            -- preview icon follows that location, its offsets and its size.
            local dispSplit = (cfg.dispellableDebuffLocation or "same") ~= "same"
            local dbSz
            if dispSplit then
                dbSz = mod.RFC_SnapSize(mod.DispellableDebuffSize(cfg))
            else
                dbSz = mod.RFC_DebuffSize(cfg)
            end
            ddi:SetSize(dbSz, dbSz)
            ddi._tex:SetTexture(mod._PV_DISPEL_DB_ICONS[dispelType])
            local _z = cfg.debuffIconZoom or 0.08
            ddi._tex:SetTexCoord(_z, 1 - _z, _z, 1 - _z)

            -- Position using debuff settings
            ddi:ClearAllPoints()
            local dbPos, dbOX, dbOY
            if dispSplit then
                dbPos = cfg.dispellableDebuffLocation
                dbOX = cfg.dispellableDebuffOffsetX or 0
                dbOY = cfg.dispellableDebuffOffsetY or 0
            else
                dbPos = cfg.debuffPosition or "bottomright"
                dbOX = cfg.debuffOffsetX or 0
                dbOY = cfg.debuffOffsetY or 0
            end
            local ddHost = mod.RF_AnchorHost(frame._health, cfg)
            if dbPos == "topleft" then
                ddi:SetPoint("TOPLEFT", ddHost, "TOPLEFT", dbOX, dbOY)
            elseif dbPos == "top" then
                ddi:SetPoint("TOP", ddHost, "TOP", dbOX, dbOY)
            elseif dbPos == "topright" then
                ddi:SetPoint("TOPRIGHT", ddHost, "TOPRIGHT", dbOX, dbOY)
            elseif dbPos == "left" then
                ddi:SetPoint("LEFT", ddHost, "LEFT", dbOX, dbOY)
            elseif dbPos == "center" then
                ddi:SetPoint("CENTER", ddHost, "CENTER", dbOX, dbOY)
            elseif dbPos == "right" then
                ddi:SetPoint("RIGHT", ddHost, "RIGHT", dbOX, dbOY)
            elseif dbPos == "bottomleft" then
                ddi:SetPoint("BOTTOMLEFT", ddHost, "BOTTOMLEFT", dbOX, dbOY)
            elseif dbPos == "bottom" then
                ddi:SetPoint("BOTTOM", ddHost, "BOTTOM", dbOX, dbOY)
            else -- bottomright
                ddi:SetPoint("BOTTOMRIGHT", ddHost, "BOTTOMRIGHT", dbOX, dbOY)
            end

            -- Border (dispel-type colored)
            local border = mod.RFC_AuraBorder(cfg, "debuffBorder")
            local dc = GetDispelColor(dispelType, cfg)
            if border and dc then
                border[1], border[2], border[3] = dc.r, dc.g, dc.b
            end
            mod.RFC_ApplyAuraBorder(
                ddi._borderFrame,
                ddi._borderFrame,
                border,
                (ddi._cooldown or ddi):GetFrameLevel()
            )

            if ddi._cooldown then ddi._cooldown:Hide() end
            if ddi._count then ddi._count:SetText("") end
            if ddi._durText then ddi._durText:Hide() end
            ddi:Show()
        else
            frame._pvDispelDebuff:Hide()
        end
    end

    -- Hover/target are recolored onto the single border (f._ApplyBorderColor),
    -- applied above with the border style; no separate hover/target frames.

    -- Raid marker (1 random in group 1, 1 random in group 4)
    if frame._raidMarker then
        local isMarked = indVis
            and cfg.showRaidMarker
            and (index == previewRoles._markerSlot1 or index == previewRoles._markerSlot2)
        if isMarked then
            local rmSz = PixelSnap(cfg.raidMarkerSize or 16)
            frame._raidMarker:SetSize(rmSz, rmSz)
            -- Use custom marker PNGs
            if index == previewRoles._markerSlot1 then
                frame._raidMarker:SetTexture("Interface\\AddOns\\CludesUI\\media\\marker.png")
                frame._raidMarker:SetTexCoord(0, 1, 0, 1)
            else
                frame._raidMarker:SetTexture("Interface\\AddOns\\CludesUI\\media\\marker2.png")
                frame._raidMarker:SetTexCoord(0, 1, 0, 1)
            end
            -- Anchor based on marker position setting
            frame._raidMarker:ClearAllPoints()
            local place = cfg.raidMarkerPosition or "center"
            local ox = cfg.raidMarkerOffsetX or 0
            local oy = cfg.raidMarkerOffsetY or 0
            local rmHost = mod.RF_AnchorHost(frame._health, cfg)
            if place == "topleft" then
                frame._raidMarker:SetPoint("TOPLEFT", rmHost, "TOPLEFT", 2 + ox, -2 + oy)
            elseif place == "top" then
                frame._raidMarker:SetPoint("TOP", rmHost, "TOP", ox, -2 + oy)
            elseif place == "topright" then
                frame._raidMarker:SetPoint("TOPRIGHT", rmHost, "TOPRIGHT", -2 + ox, -2 + oy)
            elseif place == "left" then
                frame._raidMarker:SetPoint("LEFT", rmHost, "LEFT", 2 + ox, oy)
            elseif place == "right" then
                frame._raidMarker:SetPoint("RIGHT", rmHost, "RIGHT", -2 + ox, oy)
            elseif place == "bottomleft" then
                frame._raidMarker:SetPoint("BOTTOMLEFT", rmHost, "BOTTOMLEFT", 2 + ox, 2 + oy)
            elseif place == "bottom" then
                frame._raidMarker:SetPoint("BOTTOM", rmHost, "BOTTOM", ox, 2 + oy)
            elseif place == "bottomright" then
                frame._raidMarker:SetPoint("BOTTOMRIGHT", rmHost, "BOTTOMRIGHT", -2 + ox, 2 + oy)
            else -- center
                frame._raidMarker:SetPoint("CENTER", rmHost, "CENTER", ox, oy)
            end
            frame._raidMarker:Show()
        else
            frame._raidMarker:Hide()
        end
    end

    -- WoW Forever: Missing Buffs (CUI_RaidFrames_ForeverMissingBuffs.lua).
    if mod.RF_FvMissingPreview then mod.RF_FvMissingPreview(frame, index, cfg, indVis) end

    -- Ready check icon
    if frame._readyCheck then
        local rcStatuses = previewRoles._readyCheck
        local rcStatus = rcStatuses and rcStatuses[index]
        local isSummon = rcStatus and rcStatus:sub(1, 6) == "summon"
        local isRez = rcStatus == "rez"
        local showRC = indVis
            and rcStatus
            and (
                (isRez and cfg.showIncomingRez)
                or (isSummon and cfg.showSummonPending)
                or (not isSummon and not isRez and cfg.showReadyCheck)
            )
        if showRC then
            local rcSz = PixelSnap(cfg.readyCheckSize or 20)
            frame._readyCheck:SetSize(rcSz, rcSz)
            -- Anchor based on ready-check position setting
            frame._readyCheck:ClearAllPoints()
            local place = cfg.readyCheckPosition or "center"
            local ox = cfg.readyCheckOffsetX or 0
            local oy = cfg.readyCheckOffsetY or 0
            local rcHost = mod.RF_AnchorHost(frame._health, cfg)
            if place == "topleft" then
                frame._readyCheck:SetPoint("TOPLEFT", rcHost, "TOPLEFT", 2 + ox, -2 + oy)
            elseif place == "top" then
                frame._readyCheck:SetPoint("TOP", rcHost, "TOP", ox, -2 + oy)
            elseif place == "topright" then
                frame._readyCheck:SetPoint("TOPRIGHT", rcHost, "TOPRIGHT", -2 + ox, -2 + oy)
            elseif place == "left" then
                frame._readyCheck:SetPoint("LEFT", rcHost, "LEFT", 2 + ox, oy)
            elseif place == "right" then
                frame._readyCheck:SetPoint("RIGHT", rcHost, "RIGHT", -2 + ox, oy)
            elseif place == "bottomleft" then
                frame._readyCheck:SetPoint("BOTTOMLEFT", rcHost, "BOTTOMLEFT", 2 + ox, 2 + oy)
            elseif place == "bottom" then
                frame._readyCheck:SetPoint("BOTTOM", rcHost, "BOTTOM", ox, 2 + oy)
            elseif place == "bottomright" then
                frame._readyCheck:SetPoint("BOTTOMRIGHT", rcHost, "BOTTOMRIGHT", -2 + ox, 2 + oy)
            else -- center
                frame._readyCheck:SetPoint("CENTER", rcHost, "CENTER", ox, oy)
            end
            if rcStatus == "ready" then
                frame._readyCheck:SetAtlas("UI-LFG-ReadyMark-Raid")
            elseif rcStatus == "notready" then
                frame._readyCheck:SetAtlas("UI-LFG-DeclineMark-Raid")
            elseif rcStatus == "pending" then
                frame._readyCheck:SetAtlas("UI-LFG-PendingMark-Raid")
            elseif rcStatus == "summon_pending" then
                frame._readyCheck:SetAtlas("RaidFrame-Icon-SummonPending")
            elseif rcStatus == "summon_accepted" then
                frame._readyCheck:SetAtlas("RaidFrame-Icon-SummonAccepted")
            elseif rcStatus == "summon_declined" then
                frame._readyCheck:SetAtlas("RaidFrame-Icon-SummonDeclined")
            elseif rcStatus == "rez" then
                frame._readyCheck:SetAtlas("RaidFrame-Icon-Rez")
            end
            frame._readyCheck:Show()
        else
            frame._readyCheck:Hide()
        end
    end

    -- Text band level: mirrors AnchorTexts on the live buttons ("Show Above Icons"
    -- lifts the carrier over the aura band). The texts are painted below.
    if frame.textCarrier then
        frame.textCarrier:SetFrameLevel(
            frame:GetFrameLevel() + (cfg.nameTextAboveIcons and (mod.LVL_AURA + 6) or mod.LVL_TEXT)
        )
    end

    -- Dead/offline/AFK states (only when indicators eyeball is on). The rez slot is
    -- a second corpse (dimmed, no "DEAD" text) that shows an incoming-rez icon in
    -- place of the status text -- mirrors the live "hide DEAD while rezzing" behavior.
    local isRezCorpse = indVis and index == previewRoles._rezSlot
    local isDead = indVis and (index == previewRoles._deadSlot or isRezCorpse)
    local isOffline = indVis and index == previewRoles._offlineSlot
    -- Mark dead/offline preview frames so the animated-preview ticker skips them
    -- (their health bar is emptied and health text hidden -- never animated).
    frame._pvHideHealthText = (isDead or isOffline) or nil
    local isAfk = indVis and index == previewRoles._afkSlot

    -- The texts from this member's made-up values, kept on the frame (f._pv) for the
    -- animated previews: health and power as its bars show them, a heal absorb of 3000 per
    -- health percent, its name as the name text shows it, its state, class and power type.
    if frame.textCarrier then
        local pv = frame._pv or {}
        frame._pv = pv
        local pTok = CludesUI.CLASS_POWER_MAP[classToken] or "MANA"
        pv.hpPct, pv.hpPer = healthPct, 12000
        pv.ppPct, pv.ppPer = frame._powerPct or 100, (pTok == "MANA") and 2500 or 1
        pv.ha = math.floor(healthPct * 3000)
        -- rawName: for a custom text tag's own Name Format ([name:abbr]).
        pv.rawName, pv.name = name, mod.CapName(mod.RF_FormatName(name, cfg), cfg)
        pv.dead, pv.offline = isDead or nil, isOffline or nil
        pv.power = not hidePower or nil
        pv.class, pv.pToken = classToken, pTok
        mod.RF_TextPreview(frame, cfg, pv)
    end

    -- Status text (DEAD / OFFLINE / AFK)
    if frame._statusText then
        local pvStc = cfg.statusTextColor or { r = 1, g = 1, b = 1 }
        ApplyFont(frame._statusText, cfg.statusTextSize or 14)
        frame._statusText:SetTextColor(pvStc.r, pvStc.g, pvStc.b)
        frame._statusText:ClearAllPoints()
        local stPos = cfg.statusTextPosition or "center"
        local stOX = cfg.statusTextOffsetX or 0
        local stOY = cfg.statusTextOffsetY or 0
        local stHost = mod.RF_BarHost(frame._health, cfg)
        if stPos == "topleft" then
            frame._statusText:SetPoint("TOPLEFT", stHost, "TOPLEFT", 2 + stOX, -2 + stOY)
        elseif stPos == "top" then
            frame._statusText:SetPoint("TOP", stHost, "TOP", stOX, -2 + stOY)
        elseif stPos == "topright" then
            frame._statusText:SetPoint("TOPRIGHT", stHost, "TOPRIGHT", -2 + stOX, -2 + stOY)
        elseif stPos == "left" then
            frame._statusText:SetPoint("LEFT", stHost, "LEFT", 2 + stOX, stOY)
        elseif stPos == "right" then
            frame._statusText:SetPoint("RIGHT", stHost, "RIGHT", -2 + stOX, stOY)
        elseif stPos == "bottomleft" then
            frame._statusText:SetPoint("BOTTOMLEFT", stHost, "BOTTOMLEFT", 2 + stOX, 2 + stOY)
        elseif stPos == "bottom" then
            frame._statusText:SetPoint("BOTTOM", stHost, "BOTTOM", stOX, 2 + stOY)
        elseif stPos == "bottomright" then
            frame._statusText:SetPoint("BOTTOMRIGHT", stHost, "BOTTOMRIGHT", -2 + stOX, 2 + stOY)
        else
            frame._statusText:SetPoint("CENTER", stHost, "CENTER", stOX, stOY)
        end
        if stPos == "none" then
            -- Status text display is turned off
            frame._statusText:Hide()
        elseif isRezCorpse then
            -- Being resurrected: the rez icon takes this spot, so no DEAD text.
            frame._statusText:Hide()
        elseif isDead then
            frame._statusText:SetText(CludesUI.L("DEAD"))
            frame._statusText:Show()
        elseif isOffline then
            frame._statusText:SetText(CludesUI.L("OFFLINE"))
            frame._statusText:Show()
        elseif isAfk then
            frame._statusText:SetText(CludesUI.L("AFK"))
            frame._statusText:Show()
        else
            -- No status to show
            frame._statusText:Hide()
        end
    end

    -- Dead/DC overlay (mirror the live-frame status tint: full-cover bg)
    if isDead then
        if frame._health then
            -- Emptied under Inverted Fill too (a full missing-health bar), so the
            -- current-health area the dispel wash covers stays empty, as live.
            frame._health:SetValue(pvInvert and 100 or 0)
            local ft = frame._health:GetStatusBarTexture()
            if ft then ft:SetAlpha(0) end
        end
        if frame._bg then
            local color = cfg.statusColorDead or { r = 0x24 / 255, g = 0x17 / 255, b = 0x17 / 255 }
            frame._bg:ClearAllPoints()
            frame._bg:SetAllPoints(frame._health)
            frame._bg:SetColorTexture(color.r, color.g, color.b, 1)
        end
        -- Hide shield on dead players
        if frame._absorbBar then
            frame._absorbBar:Hide()
            if frame._absorbBar._forward then frame._absorbBar._forward:Hide() end
            if frame._absorbBar._topBar then frame._absorbBar._topBar:Hide() end
        end
    elseif isOffline then
        if frame._health then
            frame._health:SetValue(pvInvert and 100 or 0) -- see the dead branch
            local ft = frame._health:GetStatusBarTexture()
            if ft then ft:SetAlpha(0) end
        end
        if frame._bg then
            local color = cfg.statusColorOffline or { r = 0x66 / 255, g = 0x66 / 255, b = 0x66 / 255 }
            frame._bg:ClearAllPoints()
            frame._bg:SetAllPoints(frame._health)
            frame._bg:SetColorTexture(color.r, color.g, color.b, 1)
        end
    end

    -- Role icon (not affected by indicators toggle)
    if frame._roleIcon then
        if frame._roleIcon._roleText then frame._roleIcon._roleText:Hide() end
        local style = cfg.roleIconStyle or "modern"
        if cfg.roleText or style ~= "none" then
            local role = previewRoles[index] or "DAMAGER"
            local showForRole = (role == "TANK" and cfg.showRoleForTank)
                or (role == "HEALER" and cfg.showRoleForHealer)
                or (role == "DAMAGER" and cfg.showRoleForDPS)
            if showForRole ~= false and (cfg.roleText or ApplyRoleIcon(frame._roleIcon, role, style)) then
                local riSz = PixelSnap(cfg.roleIconSize or 14)
                frame._roleIcon:SetSize(riSz, riSz)
                -- Mirror the live carrier's "Show Behind Border" level (see AnchorRoleIcon).
                local rc = frame._roleIcon:GetParent()
                if rc then
                    rc:SetFrameLevel(
                        frame:GetFrameLevel()
                            + (cfg.roleIconBehindBorder and mod.LVL_ROLE_BEHIND or (mod.LVL_AURA - 1))
                    )
                end
                frame._roleIcon:ClearAllPoints()
                if cfg.roleIconOnNameBar and cfg.topNameBarEnabled and frame._topNameBar then
                    local place = (cfg.roleNameBarPosition or "left"):upper()
                    frame._roleIcon:SetPoint(
                        place,
                        frame._topNameBar,
                        place,
                        cfg.roleNameBarOffsetX or 0,
                        cfg.roleNameBarOffsetY or 0
                    )
                else
                    local place = (cfg.roleIconPosition or "bottomleft"):upper()
                    frame._roleIcon:SetPoint(
                        place,
                        mod.RF_AnchorHost(frame._health, cfg),
                        place,
                        cfg.roleIconOffsetX or 0,
                        cfg.roleIconOffsetY or 0
                    )
                end
                frame._roleIcon:Show()
                if cfg.roleText then mod.ApplyRoleText(frame._roleIcon, role, cfg) end
            else
                frame._roleIcon:Hide()
            end
        else
            frame._roleIcon:Hide()
        end
        -- Attach Role Icons: the name makes room only where the icon shows (as live)
        local tnb = frame._topNameBar
        if cfg.roleIconOnNameBar and tnb and frame._topNameBarText then
            local has = frame._roleIcon:IsShown() and true or false
            if tnb._cuiRoleIcon ~= has then
                tnb._cuiRoleIcon = has
                mod.RF_PlaceTopNameText(frame._topNameBarText, tnb, cfg)
            end
        end
    end

    -- Leader icon: show on slot 1 (player = leader in preview)
    if frame._leaderIcon then
        if cfg.showLeaderIcon and index == 1 then
            local liSz = PixelSnap(cfg.leaderIconSize or 14)
            frame._leaderIcon:SetSize(liSz, liSz)
            frame._leaderIcon:ClearAllPoints()
            local liPos = (cfg.leaderIconPosition or "top"):upper()
            frame._leaderIcon:SetPoint(
                liPos,
                mod.RF_AnchorHost(frame._health, cfg),
                liPos,
                cfg.leaderIconOffsetX or 0,
                cfg.leaderIconOffsetY or 0
            )
            frame._leaderIcon:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
            frame._leaderIcon:Show()
        else
            frame._leaderIcon:Hide()
        end
    end

    -- Combat icon: on live alive members when the indicators eyeball is on.
    if frame._combatIcon then
        if indVis and cfg.showCombatIndicator and not isDead and not isOffline then
            local cciSz = PixelSnap(cfg.combatIndicatorSize or 16)
            frame._combatIcon:SetSize(cciSz, cciSz)
            frame._combatIcon:ClearAllPoints()
            local ciPos = (cfg.combatIndicatorPosition or "right"):upper()
            frame._combatIcon:SetPoint(
                ciPos,
                mod.RF_AnchorHost(frame._health, cfg),
                ciPos,
                cfg.combatIndicatorOffsetX or 0,
                cfg.combatIndicatorOffsetY or 0
            )
            local style = cfg.combatIndicatorStyle or "standard"
            local MEDIA = mod._COMBAT_MEDIA
            if style:find("^combat%d") then
                frame._combatIcon:SetTexture(MEDIA .. style .. ".tga")
                frame._combatIcon:SetTexCoord(0, 1, 0, 1)
                if frame._combatIcon.SetDesaturated then frame._combatIcon:SetDesaturated(false) end
                frame._combatIcon:SetVertexColor(1, 1, 1, 1)
            else
                if style == "class" then
                    frame._combatIcon:SetTexture(MEDIA .. "combat-indicator-class-custom.png")
                    local coords = classToken and mod._COMBAT_CLASS_COORDS[classToken]
                    if coords then
                        frame._combatIcon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
                    else
                        frame._combatIcon:SetTexCoord(0, 1, 0, 1)
                    end
                else
                    frame._combatIcon:SetTexture(MEDIA .. "combat-indicator-custom.png")
                    frame._combatIcon:SetTexCoord(0, 1, 0, 1)
                end
                local colorMode = cfg.combatIndicatorColor or "custom"
                if colorMode == "classcolor" then
                    local classColor = (classToken and CludesUI.GetClassColor(classToken)) or { r = 1, g = 1, b = 1 }
                    frame._combatIcon:SetVertexColor(classColor.r, classColor.g, classColor.b, 1)
                else
                    local cc = cfg.combatIndicatorCustomColor or { r = 1, g = 1, b = 1 }
                    frame._combatIcon:SetVertexColor(cc.r, cc.g, cc.b, 1)
                end
            end
            frame._combatIcon:Show()
        else
            frame._combatIcon:Hide()
        end
    end

    -- Buff manager indicators only shown on the BM page preview, not here

    -- Debuff/defensive preview icons managed by PvAuraTicker (cycling system)

    frame:Show()
end

mod._previewInitialized = false

local function InitPreviewHealthValues()
    if mod._previewInitialized then return end
    mod._previewInitialized = true
    for index = 1, 20 do
        previewHealthValues[index] = 40 + math.random(60)
        previewPowerValues[index] = 50 + math.random(50)
        mod.previewAbsorbValues[index] = 0
        mod.previewHealAbsorbValues[index] = 0
    end
    -- Assign shields: at least 1 per group of 5, plus a few random extras
    for g = 0, 3 do
        -- Guaranteed 1 per group
        local slot = g * 5 + math.random(5)
        mod.previewAbsorbValues[slot] = 5 + math.random(25)
        -- 50% chance of a second in the group
        if math.random() > 0.5 then
            local slot2 = g * 5 + math.random(5)
            if mod.previewAbsorbValues[slot2] == 0 then
                mod.previewAbsorbValues[slot2] = 3 + math.random(15)
            end
        end
    end
    -- Assign heal absorbs: 2 random slots
    local haPool = {}
    for index = 2, 20 do
        haPool[#haPool + 1] = index
    end
    for index = #haPool, 2, -1 do
        local jdx = math.random(index)
        haPool[index], haPool[jdx] = haPool[jdx], haPool[index]
    end
    mod.previewHealAbsorbValues[haPool[1]] = 20 + math.random(20)
    mod.previewHealAbsorbValues[haPool[2]] = 20 + math.random(20)

    -- Assign heal prediction: 2 random slots (non-full-health frames)
    mod.previewHealPredValues = {}
    for index = 1, 20 do
        mod.previewHealPredValues[index] = 0
    end
    local hpPool = {}
    for index = 1, 20 do
        if previewHealthValues[index] < 95 then hpPool[#hpPool + 1] = index end
    end
    for index = #hpPool, 2, -1 do
        local jdx = math.random(index)
        hpPool[index], hpPool[jdx] = hpPool[jdx], hpPool[index]
    end
    if hpPool[1] then mod.previewHealPredValues[hpPool[1]] = 10 + math.random(20) end
    if hpPool[2] then mod.previewHealPredValues[hpPool[2]] = 10 + math.random(20) end

    -- Reduced max health: 2 random slots with 10-25% health loss
    mod.previewReducedMaxHealth = {}
    for index = 1, 20 do
        mod.previewReducedMaxHealth[index] = 0
    end
    local rmhPool = {}
    for index = 2, 20 do
        rmhPool[#rmhPool + 1] = index
    end
    for index = #rmhPool, 2, -1 do
        local jdx = math.random(index)
        rmhPool[index], rmhPool[jdx] = rmhPool[jdx], rmhPool[index]
    end
    mod.previewReducedMaxHealth[rmhPool[1]] = 0.10 + math.random() * 0.15
    mod.previewReducedMaxHealth[rmhPool[2]] = 0.10 + math.random() * 0.15
end

Inner.ApplyPreviewData, Inner.InitPreviewHealthValues = ApplyPreviewData, InitPreviewHealthValues
Inner.previewHealthValues, Inner.previewPowerValues = previewHealthValues, previewPowerValues
Inner.broken = false
