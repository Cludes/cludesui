if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_UnitFrames_Reload.lua
--
--  ReloadFrames, the settings pass over every spawned unit frame, published
--  as I.ReloadFrames (CUI_UnitFrames_Init.lua, CUI_UnitFrames_OptionsSetup.lua),
--  and the frame border pad that mirrors its unified border apply. Reads the
--  main file through ns and ns._internals; db is set through I.dbSetters.
-------------------------------------------------------------------------------
local _, mod = ...

local issecretvalue = issecretvalue
local Pix = CludesUI.PP
local GetMiniDonorSettings = mod.GetMiniDonorSettings

local Inner = mod._internals
local frameList, GetSettingsForUnit, UnitToSettingsKey =
    Inner.frames, Inner.GetSettingsForUnit, Inner.UnitToSettingsKey
local UnsnapTex, SetFSFont, ResolveFontPath = Inner.UnsnapTex, Inner.SetFSFont, Inner.ResolveFontPath
local ApplyDarkTheme, ApplyEnemyColors, ApplyBarGradient =
    Inner.ApplyDarkTheme, Inner.ApplyEnemyColors, Inner.ApplyBarGradient
local ApplyHealthBarTexture, ApplyHealthBarAlpha, ApplyPowerBarAlpha =
    Inner.ApplyHealthBarTexture, Inner.ApplyHealthBarAlpha, Inner.ApplyPowerBarAlpha
local ApplyFramePosition, CreateBottomTextBar, ReparentBarsToClip, UpdateBordersForScale =
    Inner.ApplyFramePosition, Inner.CreateBottomTextBar, Inner.ReparentBarsToClip, Inner.UpdateBordersForScale
local ApplyAbsorbStyle, UpdateAbsorbBarReverseFill, ApplyDetachedPortraitShape =
    Inner.ApplyAbsorbStyle, Inner.UpdateAbsorbBarReverseFill, Inner.ApplyDetachedPortraitShape
local SwapPortraitMode, SpecHasClassPower = Inner.SwapPortraitMode, Inner.SpecHasClassPower
local CastIconInWidth, CastIconOffsets, CastIconOnRight, CastIconShown, LayoutCastbarIcon =
    Inner.CastIconInWidth,
    Inner.CastIconOffsets,
    Inner.CastIconOnRight,
    Inner.CastIconShown,
    Inner.LayoutCastbarIcon
local GetCastbarColor, ApplyUnitFrameCastColor, IsKickCastbarUnit, UpdateUnitFrameKickTick =
    Inner.GetCastbarColor,
    Inner.ApplyUnitFrameCastColor,
    Inner.IsKickCastbarUnit,
    Inner.UpdateUnitFrameKickTick
local saved
Inner.dbSetters[#Inner.dbSetters + 1] = function(val)
    saved = val
end

-- Detached portrait click overlays on the settled geometry; true while any
-- frame wants one.
local function SyncPortraitClicks()
    local any = false
    for _, widget in pairs(frameList) do
        if type(widget) == "table" and widget.Portrait and mod.UF_SyncPortraitClick(widget) then
            any = true
        end
    end
    return any
end

-- Blizzard Style: the per-unit geometry re-applies inside a reload each run
-- the stock pass from UpdateBordersForScale's tail, only for the re-anchors
-- that follow to undo it; the sweep at the end of the reload is the pass that
-- counts, so the tail steps aside for the reload's duration (login is a hot
-- path). The flag is cleared on every exit, error included.
local ReloadFramesBody
local function ReloadFrames()
    mod._ufReloadSweep = true
    local success, err = pcall(ReloadFramesBody)
    mod._ufReloadSweep = nil
    if not success then
        geterrorhandler()(err)
    end
end
ReloadFramesBody = function()
    ResolveFontPath()
    -- Refresh the tag-readable decimal globals before the combat early-return so
    -- tags pick up the saved state at login and on any settings change.
    mod.ApplyTextDecimalGlobals()
    if InCombatLockdown() then
        return
    end

    -- Normalize opacity values: old profiles stored 0-1 floats, new format is 0-100 integers
    do
        local prof = saved.profile
        local UNITS = { "player", "target", "focus", "boss", "pet", "targettarget", "focustarget" }
        if prof.healthBarOpacity and prof.healthBarOpacity <= 1.0 then
            prof.healthBarOpacity = math.floor(prof.healthBarOpacity * 100 + 0.5)
        end
        if prof.powerBarOpacity and prof.powerBarOpacity <= 1.0 then
            prof.powerBarOpacity = math.floor(prof.powerBarOpacity * 100 + 0.5)
        end
        for _, uKey in ipairs(UNITS) do
            local s = prof[uKey]
            if s then
                if s.healthBarOpacity and s.healthBarOpacity <= 1.0 then
                    s.healthBarOpacity = math.floor(s.healthBarOpacity * 100 + 0.5)
                end
                if s.powerBarOpacity and s.powerBarOpacity <= 1.0 then
                    s.powerBarOpacity = math.floor(s.powerBarOpacity * 100 + 0.5)
                end
            end
        end
    end

    local profile = saved.profile
    local castbarColor = GetCastbarColor()
    local castbarOpacity = profile.castbarOpacity
    local enabled = profile.enabledFrames

    -- A frame's castbar pass (focus, and the pet when it has one): size, icon,
    -- border, colors and text from the unit's settings.
    local function ApplyUnitCastbar(widget, unitToken, prefs)
        if widget.Castbar then
            local castbarBg = widget.Castbar:GetParent()
            if castbarBg then
                if prefs.showCastbar ~= false then
                    if not widget:IsElementEnabled("Castbar") then
                        widget:EnableElement("Castbar")
                    end
                    local cbW3 = prefs.castbarWidth or 181
                    local cbH3 = prefs.castbarHeight or 14
                    Pix.Size(castbarBg, cbW3, cbH3)
                    if castbarBg._bgTex then
                        local cbg = prefs.castBgColor
                        castbarBg._bgTex:SetColorTexture(
                            cbg and cbg.r or 0,
                            cbg and cbg.g or 0,
                            cbg and cbg.b or 0,
                            prefs.castBgAlpha or 0.5
                        )
                    end
                    local fIconOffX, fIconOffY = CastIconOffsets(unitToken, prefs)
                    LayoutCastbarIcon(
                        widget.Castbar,
                        CastIconInWidth(unitToken, prefs),
                        prefs.castbarHeight or 14,
                        CastIconOnRight(unitToken, prefs),
                        fIconOffX,
                        fIconOffY,
                        CastIconShown(unitToken, prefs),
                        prefs.castbarStockBorderScale,
                        mod.UF_CastIconPortrait(widget.Castbar, widget, prefs, unitToken)
                    )
                    mod.UF_ApplyCastBorder(widget.Castbar, prefs, nil, unitToken)
                    if widget.Castbar._iconFrame then
                        Pix.Size(widget.Castbar._iconFrame, cbH3, cbH3)
                        if not widget.Castbar:IsShown() then
                            widget.Castbar._iconFrame:Hide()
                        elseif prefs.showCastIcon == false then
                            widget.Castbar._iconFrame:Hide()
                        else
                            widget.Castbar._iconFrame:Show()
                        end
                    end
                    -- Position owned by centralized unlock system
                    -- Respect hide-while-not-casting: only show bg if inactive hiding is off or cast is active
                    if prefs.castbarHideWhenInactive and not widget.Castbar:IsShown() then
                        castbarBg:Hide()
                    else
                        castbarBg:Show()
                    end
                else
                    if widget:IsElementEnabled("Castbar") then
                        widget:DisableElement("Castbar")
                    end
                    widget.Castbar:Hide()
                    castbarBg:Hide()
                end
            end
            -- Store per-unit settings for PostCastStart
            widget.Castbar._eufSettings = prefs
            -- A glow already showing takes new Important Cast Glow settings now.
            if widget.Castbar._impGlowActive then
                mod.UpdateUnitFrameImportantGlow(widget.Castbar)
            end
            -- Resolve per-unit fill color
            local fCbColor = castbarColor
            if prefs.castbarFillColor then
                fCbColor = prefs.castbarFillColor
            end
            -- Fill Opacity below 100: tint layer carries the visible
            -- fill; zero the base so it cannot bleed through.
            widget.Castbar:SetStatusBarColor(
                fCbColor.r,
                fCbColor.g,
                fCbColor.b,
                ((prefs.castFillOpacity or 100) < 100) and 0 or castbarOpacity
            )
            mod.ApplyCastFillOpacity(widget.Castbar, prefs)
            if widget.Castbar:IsShown() then
                ApplyUnitFrameCastColor(widget.Castbar)
                UpdateUnitFrameKickTick(widget.Castbar)
            end
            -- Apply cast bar text settings
            if widget.Castbar.Text then
                local snSz = prefs.castSpellNameSize or 11
                SetFSFont(widget.Castbar.Text, snSz)
                local snC = prefs.castSpellNameColor or { r = 1, g = 1, b = 1 }
                widget.Castbar.Text:SetTextColor(snC.r, snC.g, snC.b)
            end
            if widget.Castbar.Time then
                local dtSz = prefs.castDurationSize or 10
                SetFSFont(widget.Castbar.Time, dtSz)
                local dtC = prefs.castDurationColor or { r = 1, g = 1, b = 1 }
                widget.Castbar.Time:SetTextColor(dtC.r, dtC.g, dtC.b)
                widget.Castbar._showDuration = prefs.showCastDuration ~= false
                widget.Castbar._durationSize = dtSz
                if widget.Castbar._showDuration and widget.Castbar:IsShown() then
                    widget.Castbar.Time:Show()
                elseif not widget.Castbar._showDuration then
                    widget.Castbar.Time:Hide()
                end
            end
            if widget.Castbar.Target then
                local tsSz = prefs.castSpellTargetSize or 11
                SetFSFont(widget.Castbar.Target, tsSz)
                local tsC = prefs.castSpellTargetColor or { r = 1, g = 1, b = 1 }
                widget.Castbar.Target:SetTextColor(tsC.r, tsC.g, tsC.b)
                widget.Castbar._showTarget = prefs.showCastTarget ~= false
                widget.Castbar._nameSide = prefs.castSpellNameSide or "left"
                widget.Castbar._tgtSide = prefs.castSpellTargetSide or "right"
                widget.Castbar._durSide = prefs.castDurationSide or "right"
                if not widget.Castbar._showTarget then
                    widget.Castbar.Target:Hide()
                end
                if widget.Castbar._layoutTextZones then
                    widget.Castbar:_layoutTextZones()
                end
            end
        end
    end

    -- Apply frame strata to all spawned unit frames
    local ufStrata = profile.frameStrata or "MEDIUM"
    for unitKey, widget in pairs(frameList) do
        if type(widget) == "table" and widget.SetFrameStrata then
            -- Any unit with its own settings table can override the global
            -- strata; nil (the default) means "follow the global value".
            -- GetSettingsForUnit maps boss1..boss5 onto the shared boss table
            -- and falls back to the player's settings, which is what the
            -- non-unit entries in `frames` (the class power bar above all)
            -- should ride with anyway.
            local strata = ufStrata
            local us = GetSettingsForUnit(unitKey)
            if us and us.frameStrata then
                strata = us.frameStrata
            end
            widget:SetFrameStrata(strata)
            -- Re-apply or reset custom strata for detached bars
            if widget.BottomTextBar and widget.BottomTextBar._isDetached then
                if profile.enableCustomBarStratas then
                    widget.BottomTextBar:SetFrameStrata(profile.detachedTextBarStrata or "DIALOG")
                else
                    widget.BottomTextBar:SetFrameStrata(strata)
                end
            end
            -- Same re-lift for a detached power bar: frame:SetFrameStrata above just
            -- reset it to the frame's strata (same reason the cast bar needs re-lifting
            -- below), so without this it silently falls back to the frame's strata and
            -- can end up behind the frame's own border, however "Detached Power Bar" strata is configured.
            if widget.Power then
                local us2 = GetSettingsForUnit(unitKey)
                local ppPos = mod.UF_PowerPos(us2)
                if ppPos == "detached_top" or ppPos == "detached_bottom" then
                    if profile.enableCustomBarStratas then
                        widget.Power:SetFrameStrata(profile.detachedPowerStrata or "HIGH")
                    else
                        widget.Power:SetFrameStrata("MEDIUM")
                    end
                end
            end
            -- The cast bar is a child of the frame, so SetFrameStrata above reset it to
            -- the frame's strata. Lift to HIGH so it never hides behind other MEDIUM-
            -- strata frames, unless "Raise Cast Bar Strata (All)" is off, in which case
            -- it's explicitly left at the frame's strata.
            if widget.Castbar and (unitKey == "player" or IsKickCastbarUnit(unitKey)) then
                local cbg = widget.Castbar:GetParent()
                if cbg then
                    if profile.raiseCastbarStrata ~= false then
                        cbg:SetFrameStrata("HIGH")
                    else
                        cbg:SetFrameStrata(strata)
                    end
                end
            end
            -- SetFrameStrata re-stacks children; lift the raid marker holder back
            -- above the text overlay so the marker is never hidden behind name/health text.
            if widget._raidMarkerHolder and widget._textOverlay then
                widget._raidMarkerHolder:SetFrameLevel(widget._textOverlay:GetFrameLevel() + 5)
            end
        end
    end

    -- Uses global font
    local donorFontPath = CludesUI.GetFontPath("unitFrames")
        or "Interface\\AddOns\\CludesUI\\media\\fonts\\Expressway.TTF"

    -- Live enable/disable frames without reload
    local function ToggleFrame(unitToken, widget)
        if not widget then
            return
        end
        if widget._cuiVisDriver then
            -- A secure condition driver owns this frame's Show/Hide (group gating
            -- included); manual toggling here would de-sync it until the next driver
            -- re-evaluation. The visibility pass converts the driver when disabled.
            return
        end
        local unitKey = unitToken:match("^boss%d$") and "boss" or unitToken
        local isEnabled = enabled[unitKey] ~= false
        -- Check group visibility for player/target/focus
        if isEnabled and (unitKey == "player" or unitKey == "target" or unitKey == "focus") then
            local s = profile[unitKey]
            if s then
                local inRaid = IsInRaid()
                local inParty = not inRaid and IsInGroup()
                local solo = not inRaid and not inParty
                local vis = (inRaid and (s.showInRaid ~= false))
                    or (inParty and (s.showInParty ~= false))
                    or (solo and (s.showSolo ~= false))
                if not vis then
                    isEnabled = false
                end
            end
        end
        if isEnabled then
            if not widget:IsShown() and UnitExists(unitToken) then
                widget:SetAttribute("unit", unitToken)
                widget:Show()
                -- The engine repaints in full on show (OnShow hook) and drops
                -- events for hidden frames at dispatch, so nothing needs
                -- re-enabling; one explicit pass covers the pre-show window.
                mod.Engine.RepaintAll(widget, "ToggleFrame")
            end
        else
            if widget:IsShown() then
                -- Hidden frames already cost nothing: the engine drops their
                -- events at dispatch and the poller skips them.
                widget:SetAttribute("unit", nil)
                widget:Hide()
            end
        end
    end

    for unitToken, widget in pairs(frameList) do
        if type(unitToken) == "string" and unitToken:sub(1, 1) ~= "_" and not unitToken:match("^boss%d$") then
            ToggleFrame(unitToken, widget)
        end
    end
    -- Boss frames: the unit watch registered at spawn is their show/hide authority.
    -- ToggleFrame's Hide() left that watch armed, so a profile switch that disables
    -- them had the next boss re-show all five. The watch owner unregisters (or
    -- re-registers) the watch and parks a regen one-shot when this runs in combat.
    if mod.UF_SetBossFramesActive and frameList.boss1 then
        mod.UF_SetBossFramesActive(enabled.boss ~= false)
    end

    for unitToken, widget in pairs(frameList) do
        if type(unitToken) == "string" and unitToken:sub(1, 1) ~= "_" and widget then
            local unitKey = unitToken:match("^boss%d$") and "boss" or unitToken
            if enabled[unitKey] == false then
                -- skip disabled frames
            else
                -- Restore position and scale from profile
                if unitKey == "boss" then
                    local bossPos = saved.profile.positions.boss
                    local bossSpacing = mod.UF_BossSpacing()
                    local bossIdx = tonumber(unitToken:match("(%d+)$"))
                    local bossAnchored = CludesUI
                        and CludesUI.IsUnlockAnchored
                        and CludesUI.IsUnlockAnchored("boss")
                    local canRepoBoss1 = bossPos
                        and not (CludesUI and CludesUI._unlockActive)
                        and (not bossAnchored or not widget:GetLeft())
                    if bossIdx == 1 and canRepoBoss1 then
                        widget:ClearAllPoints()
                        widget:SetPoint(
                            bossPos.point,
                            UIParent,
                            bossPos.relPoint or bossPos.point,
                            bossPos.x,
                            bossPos.y
                        )
                    elseif bossIdx and bossIdx > 1 and not (CludesUI and CludesUI._unlockActive) then
                        -- boss2..5 always re-chain off the previous boss with the
                        -- current Vertical Spacing value, regardless of saved pos.
                        local prev = frameList["boss" .. (bossIdx - 1)]
                        if prev then
                            widget:ClearAllPoints()
                            local bossStackDir = saved.profile.boss and saved.profile.boss.bossStackDirection
                                or "down"
                            if bossStackDir == "up" then
                                widget:SetPoint("TOPLEFT", prev, "TOPLEFT", 0, bossSpacing)
                            else
                                widget:SetPoint("TOPLEFT", prev, "TOPLEFT", 0, -bossSpacing)
                            end
                        end
                    end
                else
                    if not (CludesUI and CludesUI._unlockActive) then
                        -- Skip for unlock-anchored elements (anchor system is authority)
                        local anchored = CludesUI
                            and CludesUI.IsUnlockAnchored
                            and CludesUI.IsUnlockAnchored(unitToken)
                        if not anchored or not widget:GetLeft() then
                            ApplyFramePosition(widget, unitToken)
                        end
                    end
                end
                local prefs = GetSettingsForUnit(unitToken)
                local pStyle = prefs.portraitStyle or saved.profile.portraitStyle or "attached"
                -- Mini frames never use detached portraits
                local unitIsMini = unitToken == "pet"
                    or unitToken == "targettarget"
                    or unitToken == "focustarget"
                    or unitToken:match("^boss%d$")
                if unitIsMini and pStyle == "detached" then
                    pStyle = "attached"
                end
                local showPortrait = pStyle ~= "none" and prefs.showPortrait ~= false

                -- Keep the cached portrait side in sync with user-edited settings. Downstream
                -- re-snap code (SnapLayout, health anchor math) reads this lookup, so without
                -- it the side toggle wouldn't flip until a full UI reload.
                if prefs.portraitSide then
                    CludesUI._ufPortraitSide[widget] = prefs.portraitSide
                end

                -- Re-anchor portrait backdrop based on style + side.
                if widget.Portrait and widget.Portrait.backdrop and prefs.portraitSide then
                    local edge = widget.Portrait.backdrop
                    local pSide = prefs.portraitSide
                    local isInsideNow = pSide == "insideleft"
                        or pSide == "insideright"
                        or pSide == "insidecenter"
                    edge._isInside = isInsideNow
                    if isInsideNow then
                        if edge._bg then
                            edge._bg:Hide()
                        end
                        local healthAnchor = widget.Health or widget
                        local pXO = prefs.portraitX or 0
                        local pYO = prefs.portraitY or 0
                        local pSizeAdj = prefs.portraitSize or 0
                        local frameH = widget:GetHeight()
                        if frameH < 1 then
                            frameH = 46
                        end
                        local pDim = frameH + pSizeAdj
                        if pDim < 8 then
                            pDim = 8
                        end
                        edge:SetClipsChildren(true)
                        edge:SetFrameLevel(widget:GetFrameLevel() + 3)
                        -- Raise border above 3D model (PlayerModel ignores frame level):
                        -- a 3D portrait, or Class art whose non-player fallback is 3D.
                        local pMode = prefs.portraitMode or "2d"
                        local is3d = pMode == "3d"
                            or (pMode == "class" and mod.UF_ClassFallback(prefs) == "3d")
                        if is3d and widget.unifiedBorder and not prefs.borderBehind then
                            widget.unifiedBorder:SetFrameLevel(widget:GetFrameLevel() + 20)
                        end
                        edge:ClearAllPoints()
                        edge:SetWidth(pDim)
                        if pSide == "insideleft" then
                            edge:SetPoint("TOPLEFT", healthAnchor, "TOPLEFT", pXO, pYO)
                            edge:SetPoint("BOTTOMLEFT", widget, "BOTTOMLEFT", pXO, 0)
                        elseif pSide == "insideright" then
                            edge:SetPoint("TOPRIGHT", healthAnchor, "TOPRIGHT", pXO, pYO)
                            edge:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", pXO, 0)
                        else
                            edge:SetPoint("TOP", healthAnchor, "TOP", pXO, pYO)
                            edge:SetPoint("BOTTOM", widget, "BOTTOM", pXO, 0)
                        end
                    elseif pStyle == "attached" then
                        if edge._bg then
                            edge._bg:Show()
                        end
                        edge:SetClipsChildren(false)
                        edge:ClearAllPoints()
                        if pSide == "left" then
                            Pix.Point(edge, "TOPLEFT", widget, "TOPLEFT", 0, 0)
                        else
                            Pix.Point(edge, "TOPRIGHT", widget, "TOPRIGHT", 0, 0)
                        end
                    end
                    -- Restore border level when not inside+3D
                    if not isInsideNow and widget.unifiedBorder then
                        local bBehind = prefs.borderBehind
                        widget.unifiedBorder:SetFrameLevel(
                            bBehind and math.max(0, widget:GetFrameLevel() - 1)
                                or (widget:GetFrameLevel() + 10)
                        )
                    end
                end

                -- Swap 2D/3D portrait mode if changed (no reload needed)
                if widget.Portrait then
                    SwapPortraitMode(widget)
                    -- Always ForceUpdate so zoom/camDistanceScale applies even without mode change
                    if widget:IsElementEnabled("Portrait") and widget.Portrait.ForceUpdate then
                        widget.Portrait:ForceUpdate()
                    end
                end

                -- Show/hide portrait live (no reload needed)
                if widget.Portrait and widget.Portrait.backdrop then
                    local uKey = UnitToSettingsKey(unitToken) or unitToken
                    local uSettings = uKey and saved.profile[uKey]
                    local isClassMode = ((uSettings and uSettings.portraitMode) or "2d") == "class"
                    if showPortrait then
                        widget.Portrait.backdrop:Show()
                        if not widget:IsElementEnabled("Portrait") then
                            widget:EnableElement("Portrait")
                            widget.Portrait:ForceUpdate()
                        end
                    else
                        widget.Portrait.backdrop:Hide()
                        if widget:IsElementEnabled("Portrait") then
                            widget:DisableElement("Portrait")
                        end
                    end
                    -- Live-update detached portrait shape/mask/border
                    ApplyDetachedPortraitShape(widget.Portrait.backdrop, uSettings, unitToken)
                    -- Raise detached portrait above border/text/power
                    local isDetachedNow = pStyle == "detached"
                    if isDetachedNow then
                        widget.Portrait.backdrop:SetFrameLevel(widget:GetFrameLevel() + 15)
                    else
                        widget.Portrait.backdrop:SetFrameLevel(widget:GetFrameLevel() + 1)
                    end
                end

                if unitToken == "player" or unitToken == "target" then
                    local ppPos = mod.UF_PowerPos(prefs)
                    local ppIsAtt = (ppPos == "below" or ppPos == "above")
                    local ppExtra = ppIsAtt and prefs.powerHeight or 0
                    local playerTargetHeight = prefs.healthHeight + ppExtra
                    -- Class power "above" adds height above health bar (player only, "top" floats outside)
                    local cpAboveH = 0
                    if unitToken == "player" and SpecHasClassPower() then
                        local cpSt = prefs.classPowerStyle or "none"
                        if mod.UF_ForeverCPStyle then
                            cpSt = mod.UF_ForeverCPStyle(cpSt)
                        end
                        local cpPo = (cpSt == "modern") and (prefs.classPowerPosition or "top") or "none"
                        if cpSt == "modern" and cpPo == "above" then
                            local cpSizeAdj = prefs.classPowerSize or 8
                            local cpPipH = math.max(3, math.floor(cpSizeAdj * 0.375))
                            cpAboveH = cpPipH
                        end
                    end
                    local playerTargetHeightWithCp = playerTargetHeight + cpAboveH
                    local btbPos = prefs.btbPosition or "bottom"
                    local btbIsAttached = (btbPos == "top" or btbPos == "bottom")
                    local btbExtra = (prefs.bottomTextBar and btbIsAttached)
                            and (prefs.bottomTextBarHeight or 16)
                        or 0
                    local targetFrameHeight = playerTargetHeight + btbExtra
                    local portraitHeight = 0
                    local totalWidth = 0
                    local isAttached = pStyle == "attached"
                    local pSizeAdj = prefs.portraitSize or 0
                    local pXOff = prefs.portraitX or 0
                    local pYOff = prefs.portraitY or 0
                    if not isAttached then
                        pSizeAdj = pSizeAdj + 10
                        pYOff = pYOff + 5
                    end

                    if unitToken == "player" then
                        local pSide = prefs.portraitSide or "left"
                        local effectiveSide = pSide
                        if isAttached and pSide == "top" then
                            effectiveSide = "left"
                        end
                        local adjPortraitH = playerTargetHeightWithCp + pSizeAdj
                        if adjPortraitH < 8 then
                            adjPortraitH = 8
                        end
                        if not showPortrait then
                            totalWidth = prefs.frameWidth
                            portraitHeight = 0
                        elseif isAttached then
                            totalWidth = adjPortraitH + prefs.frameWidth
                            portraitHeight = adjPortraitH
                        else
                            totalWidth = prefs.frameWidth
                            portraitHeight = 0
                        end
                        -- Health bar xOffset: only offset when portrait is attached on the left
                        local healthXOffset = 0
                        local healthRightInset = 0
                        if showPortrait and isAttached and effectiveSide == "left" then
                            healthXOffset = portraitHeight
                        elseif showPortrait and isAttached and effectiveSide == "right" then
                            healthRightInset = portraitHeight
                        end

                        Pix.Size(widget, totalWidth, playerTargetHeightWithCp + btbExtra)

                        if
                            widget.Portrait
                            and widget.Portrait.backdrop
                            and not widget.Portrait.backdrop._isInside
                        then
                            Pix.Size(widget.Portrait.backdrop, adjPortraitH, adjPortraitH)
                            -- Reposition portrait for attached/detached
                            widget.Portrait.backdrop:ClearAllPoints()
                            local pBtbTopOff = (btbPos == "top" and prefs.bottomTextBar)
                                    and (prefs.bottomTextBarHeight or 16)
                                or 0
                            if isAttached then
                                if effectiveSide == "left" then
                                    Pix.Point(
                                        widget.Portrait.backdrop,
                                        "TOPLEFT",
                                        widget,
                                        "TOPLEFT",
                                        0,
                                        -pBtbTopOff
                                    )
                                else
                                    Pix.Point(
                                        widget.Portrait.backdrop,
                                        "TOPRIGHT",
                                        widget,
                                        "TOPRIGHT",
                                        0,
                                        -pBtbTopOff
                                    )
                                end
                            else
                                if effectiveSide == "top" then
                                    widget.Portrait.backdrop:SetPoint(
                                        "BOTTOM",
                                        widget.Health or widget,
                                        "TOP",
                                        pXOff,
                                        15 + pYOff
                                    )
                                elseif effectiveSide == "left" then
                                    widget.Portrait.backdrop:SetPoint(
                                        "TOPRIGHT",
                                        widget.Health or widget,
                                        "TOPLEFT",
                                        -15 + pXOff,
                                        pYOff
                                    )
                                else
                                    widget.Portrait.backdrop:SetPoint(
                                        "TOPLEFT",
                                        widget.Health or widget,
                                        "TOPRIGHT",
                                        15 + pXOff,
                                        pYOff
                                    )
                                end
                            end
                            if widget.Portrait.backdrop._2d then
                                UnsnapTex(widget.Portrait.backdrop._2d)
                            end
                            if widget:IsElementEnabled("Portrait") and widget.Portrait.ForceUpdate then
                                widget.Portrait:ForceUpdate()
                            end
                        end
                        if widget.Health then
                            widget.Health:ClearAllPoints()
                            -- Use portrait's actual snapped width for flush alignment
                            if
                                showPortrait
                                and isAttached
                                and widget.Portrait
                                and widget.Portrait.backdrop
                            then
                                local snappedPortW = widget.Portrait.backdrop:GetWidth()
                                healthXOffset = (effectiveSide == "left") and snappedPortW or 0
                                healthRightInset = (effectiveSide == "right") and snappedPortW or 0
                            end
                            widget.Health._xOffset = healthXOffset
                            widget.Health._rightInset = healthRightInset
                            local powerAboveOff = (ppPos == "above") and prefs.powerHeight or 0
                            local hTopOff = cpAboveH
                                + powerAboveOff
                                + (
                                    btbPos == "top"
                                        and prefs.bottomTextBar
                                        and (prefs.bottomTextBarHeight or 16)
                                    or 0
                                )
                            widget.Health._topOffset = hTopOff
                            widget.Health:SetPoint(
                                "TOPLEFT",
                                widget,
                                "TOPLEFT",
                                healthXOffset,
                                Pix.Scale(-hTopOff)
                            )
                            widget.Health:SetPoint("RIGHT", widget, "RIGHT", -healthRightInset, 0)
                            Pix.Height(widget.Health, prefs.healthHeight)
                        end
                        if widget.Power then
                            local pw = prefs.frameWidth
                            local ppIsDetached = (ppPos == "detached_top" or ppPos == "detached_bottom")
                            if ppIsDetached and (prefs.powerWidth or 0) > 0 then
                                pw = prefs.powerWidth
                            end
                            Pix.Size(widget.Power, pw, prefs.powerHeight)
                            -- Apply custom strata for detached power bar
                            if ppIsDetached and saved.profile.enableCustomBarStratas then
                                widget.Power:SetFrameStrata(saved.profile.detachedPowerStrata or "HIGH")
                            elseif ppIsDetached then
                                widget.Power:SetFrameStrata("MEDIUM")
                            end
                            widget.Power:ClearAllPoints()
                            if ppPos == "none" then
                                widget.Power:Hide()
                            elseif ppPos == "above" then
                                Pix.Point(widget.Power, "BOTTOMLEFT", widget.Health, "TOPLEFT", 0, 0)
                                Pix.Point(widget.Power, "BOTTOMRIGHT", widget.Health, "TOPRIGHT", 0, 0)
                                widget.Power:Show()
                            elseif ppPos == "detached_top" then
                                widget.Power:SetPoint(
                                    "BOTTOM",
                                    widget.Health,
                                    "TOP",
                                    prefs.powerX or 0,
                                    15 + (prefs.powerY or 0)
                                )
                                widget.Power:Show()
                            elseif ppPos == "detached_bottom" then
                                widget.Power:SetPoint(
                                    "TOP",
                                    widget.Health,
                                    "BOTTOM",
                                    prefs.powerX or 0,
                                    -15 + (prefs.powerY or 0)
                                )
                                widget.Power:Show()
                            else
                                Pix.Point(widget.Power, "TOPLEFT", widget.Health, "BOTTOMLEFT", 0, 0)
                                Pix.Point(widget.Power, "TOPRIGHT", widget.Health, "BOTTOMRIGHT", 0, 0)
                                widget.Power:Show()
                            end
                            if widget.Power._applyPowerPercentText then
                                widget.Power._applyPowerPercentText(prefs)
                            end

                            -- Update power bar border (detached only; lazily created)
                            mod.UpdatePowerBorder(widget.Power, prefs)

                            -- Gray out power bar background for generic melee NPCs
                            if ppPos ~= "none" and (ppPos == "below" or ppPos == "above") then
                                local shouldGray = false
                                if
                                    unitToken ~= "player"
                                    and UnitExists(unitToken)
                                    and UnitCanAttack("player", unitToken)
                                    and not UnitIsPlayer(unitToken)
                                then
                                    local cls = UnitClassification(unitToken)
                                    local isBoss = (cls == "worldboss")
                                    local isElite = (cls == "elite" or cls == "rareelite")
                                    local lvl = UnitLevel(unitToken)
                                    local pLvl = UnitLevel("player")
                                    local lvlOk = lvl and not (issecretvalue and issecretvalue(lvl))
                                    local pLvlOk = pLvl and not (issecretvalue and issecretvalue(pLvl))
                                    local isMB = isElite
                                        and lvlOk
                                        and (lvl == -1 or (pLvlOk and lvl >= pLvl + 1))
                                    local isCst = UnitClassBase and UnitClassBase(unitToken)
                                    if issecretvalue(isCst) then
                                        isCst = nil
                                    end
                                    isCst = (isCst == "PALADIN")
                                    if not isBoss and not isMB and not isCst then
                                        shouldGray = true
                                    end
                                end
                                if shouldGray then
                                    widget.Power._grayedOut = true
                                    if widget.Power.bg then
                                        widget.Power.bg:SetColorTexture(0.25, 0.25, 0.25, 1)
                                        widget.Power.bg:SetAlpha(1)
                                    end
                                else
                                    widget.Power._grayedOut = false
                                end
                            end
                        end
                        if widget.Castbar then
                            local castbarBg = widget.Castbar:GetParent()
                            if prefs.showPlayerCastbar then
                                -- Hide While Using Gamepad keeps the element off and the
                                -- holder hidden (ns.UF_ApplyGamepadCastbar); the style
                                -- below still lands, so the bar comes back current.
                                mod.SetCastbarElement(widget, not mod._ufCastPadHidden)
                                if castbarBg then
                                    local cbW = saved.profile.player.playerCastbarWidth or 181
                                    local cbH = saved.profile.player.playerCastbarHeight or 14
                                    Pix.Size(castbarBg, cbW, cbH)
                                    if castbarBg._bgTex then
                                        local cbg = prefs.castBgColor
                                        castbarBg._bgTex:SetColorTexture(
                                            cbg and cbg.r or 0,
                                            cbg and cbg.g or 0,
                                            cbg and cbg.b or 0,
                                            prefs.castBgAlpha or 0.5
                                        )
                                    end
                                    local pIconOffX, pIconOffY = CastIconOffsets("player", prefs)
                                    LayoutCastbarIcon(
                                        widget.Castbar,
                                        CastIconInWidth("player", prefs),
                                        prefs.playerCastbarHeight or 14,
                                        CastIconOnRight("player", prefs),
                                        pIconOffX,
                                        pIconOffY,
                                        CastIconShown("player", prefs),
                                        prefs.playerCastbarStockBorderScale,
                                        mod.UF_CastIconPortrait(widget.Castbar, widget, prefs, "player")
                                    )
                                    mod.UF_ApplyCastBorder(widget.Castbar, prefs, nil, "player")
                                    -- Resize cast icon to match castbar height
                                    if widget.Castbar._iconFrame then
                                        Pix.Size(widget.Castbar._iconFrame, cbH, cbH)
                                        if
                                            not widget.Castbar:IsShown()
                                            or prefs.showPlayerCastIcon == false
                                        then
                                            widget.Castbar._iconFrame:Hide()
                                        end
                                    end
                                    -- Position owned by centralized unlock system (no manual anchor)
                                    -- Respect hide-while-not-casting (and Hide While Using Gamepad)
                                    if
                                        mod._ufCastPadHidden
                                        or (prefs.castbarHideWhenInactive and not widget.Castbar:IsShown())
                                    then
                                        castbarBg:Hide()
                                    else
                                        castbarBg:Show()
                                    end
                                end
                                -- Store per-unit settings for PostCastStart
                                widget.Castbar._eufSettings = prefs
                                -- Resolve per-unit fill color
                                local pCbColor = castbarColor
                                if prefs.castbarClassColored then
                                    local _, classToken = UnitClass("player")
                                    if classToken and CludesUI.GetClassColor then
                                        pCbColor = CludesUI.GetClassColor(classToken) or castbarColor
                                    end
                                elseif prefs.castbarFillColor then
                                    pCbColor = prefs.castbarFillColor
                                end
                                -- Fill Opacity below 100: the tint layer is the visible
                                -- fill at that opacity; zero the base fill so it cannot
                                -- bleed through the translucent tint.
                                widget.Castbar:SetStatusBarColor(
                                    pCbColor.r,
                                    pCbColor.g,
                                    pCbColor.b,
                                    ((prefs.castFillOpacity or 100) < 100) and 0 or castbarOpacity
                                )
                                mod.ApplyCastFillOpacity(widget.Castbar, prefs)
                                -- Apply cast bar text settings
                                if widget.Castbar.Text then
                                    local snSz = prefs.castSpellNameSize or 11
                                    SetFSFont(widget.Castbar.Text, snSz)
                                    local snC = prefs.castSpellNameColor or { r = 1, g = 1, b = 1 }
                                    widget.Castbar.Text:SetTextColor(snC.r, snC.g, snC.b)
                                end
                                if widget.Castbar.Time then
                                    local dtSz = prefs.castDurationSize or 10
                                    SetFSFont(widget.Castbar.Time, dtSz)
                                    local dtC = prefs.castDurationColor or { r = 1, g = 1, b = 1 }
                                    widget.Castbar.Time:SetTextColor(dtC.r, dtC.g, dtC.b)
                                    widget.Castbar._showDuration = prefs.showCastDuration ~= false
                                    widget.Castbar._durationSize = dtSz
                                    -- Show/hide immediately (covers both toggle directions)
                                    if widget.Castbar._showDuration and widget.Castbar:IsShown() then
                                        widget.Castbar.Time:Show()
                                    elseif not widget.Castbar._showDuration then
                                        widget.Castbar.Time:Hide()
                                    end
                                end
                                if widget.Castbar.Target then
                                    local tsSz = prefs.castSpellTargetSize or 11
                                    SetFSFont(widget.Castbar.Target, tsSz)
                                    local tsC = prefs.castSpellTargetColor or { r = 1, g = 1, b = 1 }
                                    widget.Castbar.Target:SetTextColor(tsC.r, tsC.g, tsC.b)
                                    widget.Castbar._showTarget = prefs.showCastTarget ~= false
                                    if not widget.Castbar._showTarget then
                                        widget.Castbar.Target:Hide()
                                    end
                                    if widget.Castbar._syncOffsetsAndLayout then
                                        widget.Castbar:_syncOffsetsAndLayout(prefs)
                                    end
                                end
                            else
                                mod.SetCastbarElement(widget, false)
                                widget.Castbar:Hide()
                                if castbarBg then
                                    castbarBg:Hide()
                                end
                            end
                        end

                        -- Live toggle + style player absorbs. Never Enable/Disable the oUF
                        -- HealthPrediction element here: tearing it down unregisters events
                        -- and resets the calculator, which goes stale on the player frame
                        -- specifically (target/focus don't do this toggle and stay accurate).
                        -- Just Show/Hide the bar -- the element keeps running in the
                        -- background and the value stays live either way.
                        if widget.HealthPrediction and widget.HealthPrediction.damageAbsorb then
                            -- Boss frames style from the TARGET donor block,
                            -- behind the "Show on Boss Frames" toggle (nil = on).
                            local absSettings = prefs
                            local absStyle = prefs.showPlayerAbsorb
                            if unitToken and unitToken:match("^boss") then
                                if saved.profile.boss and saved.profile.boss.showAbsorbs == false then
                                    absStyle = nil
                                else
                                    absSettings = saved.profile.target or prefs
                                    absStyle = absSettings.showPlayerAbsorb
                                end
                            end
                            if absStyle and absStyle ~= "none" then
                                ApplyAbsorbStyle(widget.HealthPrediction.damageAbsorb, absStyle, absSettings)
                                widget.HealthPrediction.damageAbsorb:Show()
                                -- Force an immediate value update so the bar doesn't
                                -- show stale/uninitialized fill covering the full frame.
                                if widget.HealthPrediction.Override then
                                    widget.HealthPrediction.Override(
                                        widget,
                                        "UNIT_ABSORB_AMOUNT_CHANGED",
                                        unitToken
                                    )
                                end
                            else
                                widget.HealthPrediction.damageAbsorb:Hide()
                                -- Decoupled heal absorb: hiding the shield bar above
                                -- cascades (via the backfill OnHide hook) into hiding
                                -- the heal-absorb bar too. Re-run the prediction so the
                                -- heal absorb re-shows immediately after a reload even
                                -- with the shield absorb off, instead of staying hidden
                                -- until the next UNIT_ABSORB_AMOUNT_CHANGED event.
                                if widget.HealthPrediction.Override then
                                    widget.HealthPrediction.Override(
                                        widget,
                                        "UNIT_ABSORB_AMOUNT_CHANGED",
                                        unitToken
                                    )
                                end
                            end
                        end

                        -- Reposition name and health text (player)
                        if widget._applyTextTags then
                            widget._applyTextTags(
                                prefs.leftTextContent or "name",
                                prefs.rightTextContent or "both",
                                prefs.centerTextContent or "none"
                            )
                        end
                        if widget._applyTextPositions then
                            widget._applyTextPositions(prefs)
                        end

                        -- Bottom Text Bar update (player)
                        if prefs.bottomTextBar then
                            local btbPos2 = prefs.btbPosition or "bottom"
                            local btbIsAtt = (btbPos2 == "top" or btbPos2 == "bottom")
                            local btbIsDetached = not btbIsAtt
                            local btbW2 = btbIsDetached and (prefs.btbWidth or 0) or 0
                            local btbTW = (btbW2 > 0 and btbIsDetached) and btbW2 or totalWidth
                            -- Compute BTB xOffset for left-side portrait (attached only)
                            local btbXOff = 0
                            if btbIsAtt and showPortrait and isAttached and effectiveSide == "left" then
                                btbXOff = -adjPortraitH
                            end
                            local ppBtbAnchor = (ppIsAtt and widget.Power) or widget.Health
                            if not widget.BottomTextBar then
                                widget.BottomTextBar = CreateBottomTextBar(
                                    widget,
                                    unitToken,
                                    prefs,
                                    ppBtbAnchor,
                                    btbXOff,
                                    totalWidth
                                )
                                widget._btb = widget.BottomTextBar
                            else
                                local btb = widget.BottomTextBar
                                Pix.Size(btb, btbTW, prefs.bottomTextBarHeight or 16)
                                btb:ClearAllPoints()
                                if btbPos2 == "top" then
                                    Pix.Point(
                                        btb,
                                        "BOTTOMLEFT",
                                        widget.Health or widget,
                                        "TOPLEFT",
                                        btbXOff,
                                        0
                                    )
                                elseif btbPos2 == "detached_top" then
                                    btb:SetPoint(
                                        "BOTTOM",
                                        widget,
                                        "TOP",
                                        prefs.btbX or 0,
                                        15 + (prefs.btbY or 0)
                                    )
                                elseif btbPos2 == "detached_bottom" then
                                    btb:SetPoint(
                                        "TOP",
                                        widget,
                                        "BOTTOM",
                                        prefs.btbX or 0,
                                        -15 + (prefs.btbY or 0)
                                    )
                                else
                                    Pix.Point(btb, "TOPLEFT", ppBtbAnchor, "BOTTOMLEFT", btbXOff, 0)
                                end
                                -- Update BTB bg color
                                if btb.bg then
                                    local bgc = prefs.btbBgColor or { r = 0.2, g = 0.2, b = 0.2 }
                                    local bga = prefs.btbBgOpacity or 1.0
                                    btb.bg:SetColorTexture(bgc.r, bgc.g, bgc.b, bga)
                                end
                                if btb._applyBTBTextTags then
                                    btb._applyBTBTextTags(
                                        prefs.btbLeftContent or "none",
                                        prefs.btbRightContent or "none",
                                        prefs.btbCenterContent or "none"
                                    )
                                end
                                if btb._applyBTBTextPositions then
                                    btb._applyBTBTextPositions(prefs)
                                    if btb._applyBTBClassIcon then
                                        btb._applyBTBClassIcon(prefs)
                                    end
                                end
                                btb:Show()
                            end
                        elseif widget.BottomTextBar then
                            widget.BottomTextBar:Hide()
                        end

                        UpdateBordersForScale(widget, unitToken)
                        ReparentBarsToClip(widget, mod.UF_PowerPos(prefs), prefs)
                    elseif unitToken == "target" then
                        local pSide = prefs.portraitSide or "right"
                        local effectiveSide = pSide
                        if isAttached and pSide == "top" then
                            effectiveSide = "right"
                        end
                        local adjPortraitH = playerTargetHeight + pSizeAdj
                        if adjPortraitH < 8 then
                            adjPortraitH = 8
                        end
                        if not showPortrait then
                            totalWidth = prefs.frameWidth
                            portraitHeight = 0
                        elseif isAttached then
                            totalWidth = adjPortraitH + prefs.frameWidth
                            portraitHeight = adjPortraitH
                        else
                            totalWidth = prefs.frameWidth
                            portraitHeight = 0
                        end
                        -- Health bar xOffset: only offset when portrait is attached on the left
                        local healthXOffset = 0
                        local healthRightInset = 0
                        if showPortrait and isAttached and effectiveSide == "left" then
                            healthXOffset = portraitHeight
                        elseif showPortrait and isAttached and effectiveSide == "right" then
                            healthRightInset = portraitHeight
                        end

                        Pix.Size(widget, totalWidth, targetFrameHeight)

                        if
                            widget.Portrait
                            and widget.Portrait.backdrop
                            and not widget.Portrait.backdrop._isInside
                        then
                            Pix.Size(widget.Portrait.backdrop, adjPortraitH, adjPortraitH)
                            widget.Portrait.backdrop:ClearAllPoints()
                            local btbTopOff = (btbPos == "top" and prefs.bottomTextBar)
                                    and (prefs.bottomTextBarHeight or 16)
                                or 0
                            if isAttached then
                                if effectiveSide == "left" then
                                    Pix.Point(
                                        widget.Portrait.backdrop,
                                        "TOPLEFT",
                                        widget,
                                        "TOPLEFT",
                                        0,
                                        -btbTopOff
                                    )
                                else
                                    Pix.Point(
                                        widget.Portrait.backdrop,
                                        "TOPRIGHT",
                                        widget,
                                        "TOPRIGHT",
                                        0,
                                        -btbTopOff
                                    )
                                end
                            else
                                if effectiveSide == "top" then
                                    widget.Portrait.backdrop:SetPoint(
                                        "BOTTOM",
                                        widget.Health or widget,
                                        "TOP",
                                        pXOff,
                                        15 + pYOff
                                    )
                                elseif effectiveSide == "left" then
                                    widget.Portrait.backdrop:SetPoint(
                                        "TOPRIGHT",
                                        widget.Health or widget,
                                        "TOPLEFT",
                                        -15 + pXOff,
                                        pYOff
                                    )
                                else
                                    widget.Portrait.backdrop:SetPoint(
                                        "TOPLEFT",
                                        widget.Health or widget,
                                        "TOPRIGHT",
                                        15 + pXOff,
                                        pYOff
                                    )
                                end
                            end
                            if widget.Portrait.backdrop._2d then
                                UnsnapTex(widget.Portrait.backdrop._2d)
                            end
                            if widget:IsElementEnabled("Portrait") and widget.Portrait.ForceUpdate then
                                widget.Portrait:ForceUpdate()
                            end
                        end
                        if widget.Health then
                            widget.Health:ClearAllPoints()
                            -- Use portrait's actual snapped width for flush alignment
                            if
                                showPortrait
                                and isAttached
                                and widget.Portrait
                                and widget.Portrait.backdrop
                            then
                                local snappedPortW = widget.Portrait.backdrop:GetWidth()
                                healthXOffset = (effectiveSide == "left") and snappedPortW or 0
                                healthRightInset = (effectiveSide == "right") and snappedPortW or 0
                            end
                            local tBtbTopOff = (
                                btbPos == "top"
                                    and prefs.bottomTextBar
                                    and (prefs.bottomTextBarHeight or 16)
                                or 0
                            )
                            local tPowerAboveOff = (ppPos == "above") and prefs.powerHeight or 0
                            local tTopOff = tBtbTopOff + tPowerAboveOff
                            widget.Health._xOffset = healthXOffset
                            widget.Health._rightInset = healthRightInset
                            widget.Health._topOffset = tTopOff
                            widget.Health:SetPoint(
                                "TOPLEFT",
                                widget,
                                "TOPLEFT",
                                healthXOffset,
                                Pix.Scale(-tTopOff)
                            )
                            widget.Health:SetPoint("RIGHT", widget, "RIGHT", -healthRightInset, 0)
                            Pix.Height(widget.Health, prefs.healthHeight)
                        end
                        if widget.Power then
                            local pw2 = prefs.frameWidth
                            local ppIsDetached2 = (ppPos == "detached_top" or ppPos == "detached_bottom")
                            if ppIsDetached2 and (prefs.powerWidth or 0) > 0 then
                                pw2 = prefs.powerWidth
                            end
                            Pix.Size(widget.Power, pw2, prefs.powerHeight)
                            widget.Power:ClearAllPoints()
                            if ppPos == "none" then
                                widget.Power:Hide()
                            elseif ppPos == "above" then
                                Pix.Point(widget.Power, "BOTTOMLEFT", widget.Health, "TOPLEFT", 0, 0)
                                Pix.Point(widget.Power, "BOTTOMRIGHT", widget.Health, "TOPRIGHT", 0, 0)
                                widget.Power:Show()
                            elseif ppPos == "detached_top" then
                                widget.Power:SetPoint(
                                    "BOTTOM",
                                    widget.Health,
                                    "TOP",
                                    prefs.powerX or 0,
                                    15 + (prefs.powerY or 0)
                                )
                                widget.Power:Show()
                            elseif ppPos == "detached_bottom" then
                                widget.Power:SetPoint(
                                    "TOP",
                                    widget.Health,
                                    "BOTTOM",
                                    prefs.powerX or 0,
                                    -15 + (prefs.powerY or 0)
                                )
                                widget.Power:Show()
                            else
                                Pix.Point(widget.Power, "TOPLEFT", widget.Health, "BOTTOMLEFT", 0, 0)
                                Pix.Point(widget.Power, "TOPRIGHT", widget.Health, "BOTTOMRIGHT", 0, 0)
                                widget.Power:Show()
                            end
                            if widget.Power._applyPowerPercentText then
                                widget.Power._applyPowerPercentText(prefs)
                            end

                            -- Update power bar border (detached only; lazily created)
                            mod.UpdatePowerBorder(widget.Power, prefs)

                            -- Gray out power bar background for generic melee NPCs
                            if ppPos ~= "none" and (ppPos == "below" or ppPos == "above") then
                                local shouldGray = false
                                if
                                    unitToken ~= "player"
                                    and UnitExists(unitToken)
                                    and UnitCanAttack("player", unitToken)
                                    and not UnitIsPlayer(unitToken)
                                then
                                    local cls = UnitClassification(unitToken)
                                    local isBoss = (cls == "worldboss")
                                    local isElite = (cls == "elite" or cls == "rareelite")
                                    local lvl = UnitLevel(unitToken)
                                    local pLvl = UnitLevel("player")
                                    local lvlOk = lvl and not (issecretvalue and issecretvalue(lvl))
                                    local pLvlOk = pLvl and not (issecretvalue and issecretvalue(pLvl))
                                    local isMB = isElite
                                        and lvlOk
                                        and (lvl == -1 or (pLvlOk and lvl >= pLvl + 1))
                                    local isCst = UnitClassBase and UnitClassBase(unitToken)
                                    if issecretvalue(isCst) then
                                        isCst = nil
                                    end
                                    isCst = (isCst == "PALADIN")
                                    if not isBoss and not isMB and not isCst then
                                        shouldGray = true
                                    end
                                end
                                if shouldGray then
                                    widget.Power._grayedOut = true
                                    if widget.Power.bg then
                                        widget.Power.bg:SetColorTexture(0.25, 0.25, 0.25, 1)
                                        widget.Power.bg:SetAlpha(1)
                                    end
                                else
                                    widget.Power._grayedOut = false
                                end
                            end
                        end

                        -- Reposition name and health text
                        if widget._applyTextTags then
                            widget._applyTextTags(
                                prefs.leftTextContent or "name",
                                prefs.rightTextContent or "both",
                                prefs.centerTextContent or "none"
                            )
                        end
                        if widget._applyTextPositions then
                            widget._applyTextPositions(prefs)
                        end

                        -- Bottom Text Bar update (target) -- must come before castbar so castbar can anchor to it
                        local tPpBtbAnchor = (
                            ppIsAtt
                            and (prefs.powerHeight or 0) > 0
                            and widget.Power
                            and widget.Power:IsShown()
                        )
                                and widget.Power
                            or widget.Health
                        if prefs.bottomTextBar then
                            local btbPos2 = prefs.btbPosition or "bottom"
                            local btbIsAtt = (btbPos2 == "top" or btbPos2 == "bottom")
                            local btbIsDetached = not btbIsAtt
                            local btbW2 = btbIsDetached and (prefs.btbWidth or 0) or 0
                            local btbTW = (btbW2 > 0 and btbIsDetached) and btbW2 or totalWidth
                            local btbXOff = 0
                            if btbIsAtt and showPortrait and isAttached and effectiveSide == "left" then
                                btbXOff = -adjPortraitH
                            end
                            if not widget.BottomTextBar then
                                widget.BottomTextBar = CreateBottomTextBar(
                                    widget,
                                    unitToken,
                                    prefs,
                                    tPpBtbAnchor,
                                    btbXOff,
                                    totalWidth
                                )
                                widget._btb = widget.BottomTextBar
                            else
                                local btb = widget.BottomTextBar
                                Pix.Size(btb, btbTW, prefs.bottomTextBarHeight or 16)
                                btb:ClearAllPoints()
                                if btbPos2 == "top" then
                                    Pix.Point(
                                        btb,
                                        "BOTTOMLEFT",
                                        widget.Health or widget,
                                        "TOPLEFT",
                                        btbXOff,
                                        0
                                    )
                                elseif btbPos2 == "detached_top" then
                                    btb:SetPoint(
                                        "BOTTOM",
                                        widget,
                                        "TOP",
                                        prefs.btbX or 0,
                                        15 + (prefs.btbY or 0)
                                    )
                                elseif btbPos2 == "detached_bottom" then
                                    btb:SetPoint(
                                        "TOP",
                                        widget,
                                        "BOTTOM",
                                        prefs.btbX or 0,
                                        -15 + (prefs.btbY or 0)
                                    )
                                else
                                    Pix.Point(btb, "TOPLEFT", tPpBtbAnchor, "BOTTOMLEFT", btbXOff, 0)
                                end
                                if btb.bg then
                                    local bgc = prefs.btbBgColor or { r = 0.2, g = 0.2, b = 0.2 }
                                    local bga = prefs.btbBgOpacity or 1.0
                                    btb.bg:SetColorTexture(bgc.r, bgc.g, bgc.b, bga)
                                end
                                if btb._applyBTBTextTags then
                                    btb._applyBTBTextTags(
                                        prefs.btbLeftContent or "none",
                                        prefs.btbRightContent or "none",
                                        prefs.btbCenterContent or "none"
                                    )
                                end
                                if btb._applyBTBTextPositions then
                                    btb._applyBTBTextPositions(prefs)
                                    if btb._applyBTBClassIcon then
                                        btb._applyBTBClassIcon(prefs)
                                    end
                                end
                                btb:Show()
                            end
                        elseif widget.BottomTextBar then
                            widget.BottomTextBar:Hide()
                        end

                        -- Castbar (target)
                        if widget.Castbar then
                            local castbarBg = widget.Castbar:GetParent()
                            if castbarBg then
                                if prefs.showCastbar ~= false then
                                    if not widget:IsElementEnabled("Castbar") then
                                        widget:EnableElement("Castbar")
                                    end
                                    local cbW2 = prefs.castbarWidth or 181
                                    local cbH2 = prefs.castbarHeight or 14
                                    Pix.Size(castbarBg, cbW2, cbH2)
                                    if castbarBg._bgTex then
                                        local cbg = prefs.castBgColor
                                        castbarBg._bgTex:SetColorTexture(
                                            cbg and cbg.r or 0,
                                            cbg and cbg.g or 0,
                                            cbg and cbg.b or 0,
                                            prefs.castBgAlpha or 0.5
                                        )
                                    end
                                    local tIconOffX, tIconOffY = CastIconOffsets("target", prefs)
                                    LayoutCastbarIcon(
                                        widget.Castbar,
                                        CastIconInWidth("target", prefs),
                                        prefs.castbarHeight or 14,
                                        CastIconOnRight("target", prefs),
                                        tIconOffX,
                                        tIconOffY,
                                        CastIconShown("target", prefs),
                                        prefs.castbarStockBorderScale,
                                        mod.UF_CastIconPortrait(widget.Castbar, widget, prefs, "target")
                                    )
                                    mod.UF_ApplyCastBorder(widget.Castbar, prefs, nil, "target")
                                    if widget.Castbar._iconFrame then
                                        Pix.Size(widget.Castbar._iconFrame, cbH2, cbH2)
                                        if not widget.Castbar:IsShown() then
                                            widget.Castbar._iconFrame:Hide()
                                        elseif prefs.showCastIcon == false then
                                            widget.Castbar._iconFrame:Hide()
                                        else
                                            widget.Castbar._iconFrame:Show()
                                        end
                                    end
                                    -- Position owned by centralized unlock system
                                    -- Respect hide-while-not-casting: only show bg if inactive hiding is off or cast is active
                                    if prefs.castbarHideWhenInactive and not widget.Castbar:IsShown() then
                                        castbarBg:Hide()
                                    else
                                        castbarBg:Show()
                                    end
                                else
                                    if widget:IsElementEnabled("Castbar") then
                                        widget:DisableElement("Castbar")
                                    end
                                    widget.Castbar:Hide()
                                    castbarBg:Hide()
                                end
                            end
                            -- Store per-unit settings for PostCastStart
                            widget.Castbar._eufSettings = prefs
                            -- A glow already showing takes new Important Cast Glow settings now.
                            if widget.Castbar._impGlowActive then
                                mod.UpdateUnitFrameImportantGlow(widget.Castbar)
                            end
                            -- Resolve per-unit fill color
                            local tCbColor = castbarColor
                            if prefs.castbarFillColor then
                                tCbColor = prefs.castbarFillColor
                            end
                            -- Fill Opacity below 100: tint layer carries the visible
                            -- fill; zero the base so it cannot bleed through.
                            widget.Castbar:SetStatusBarColor(
                                tCbColor.r,
                                tCbColor.g,
                                tCbColor.b,
                                ((prefs.castFillOpacity or 100) < 100) and 0 or castbarOpacity
                            )
                            mod.ApplyCastFillOpacity(widget.Castbar, prefs)
                            if widget.Castbar:IsShown() then
                                ApplyUnitFrameCastColor(widget.Castbar)
                                UpdateUnitFrameKickTick(widget.Castbar)
                            end
                            -- Apply cast bar text settings
                            if widget.Castbar.Text then
                                local snSz = prefs.castSpellNameSize or 11
                                SetFSFont(widget.Castbar.Text, snSz)
                                local snC = prefs.castSpellNameColor or { r = 1, g = 1, b = 1 }
                                widget.Castbar.Text:SetTextColor(snC.r, snC.g, snC.b)
                            end
                            if widget.Castbar.Time then
                                local dtSz = prefs.castDurationSize or 10
                                SetFSFont(widget.Castbar.Time, dtSz)
                                local dtC = prefs.castDurationColor or { r = 1, g = 1, b = 1 }
                                widget.Castbar.Time:SetTextColor(dtC.r, dtC.g, dtC.b)
                                widget.Castbar._showDuration = prefs.showCastDuration ~= false
                                widget.Castbar._durationSize = dtSz
                                if widget.Castbar._showDuration and widget.Castbar:IsShown() then
                                    widget.Castbar.Time:Show()
                                elseif not widget.Castbar._showDuration then
                                    widget.Castbar.Time:Hide()
                                end
                            end
                            if widget.Castbar.Target then
                                local tsSz = prefs.castSpellTargetSize or 11
                                SetFSFont(widget.Castbar.Target, tsSz)
                                local tsC = prefs.castSpellTargetColor or { r = 1, g = 1, b = 1 }
                                widget.Castbar.Target:SetTextColor(tsC.r, tsC.g, tsC.b)
                                widget.Castbar._showTarget = prefs.showCastTarget ~= false
                                if not widget.Castbar._showTarget then
                                    widget.Castbar.Target:Hide()
                                end
                                if widget.Castbar._syncOffsetsAndLayout then
                                    widget.Castbar:_syncOffsetsAndLayout(prefs)
                                end
                            end
                        end

                        UpdateBordersForScale(widget, unitToken)
                        ReparentBarsToClip(widget, mod.UF_PowerPos(prefs), prefs)
                    end

                -- (health tag re-tagging now handled by _applyTextTags above)
                elseif unitToken == "focus" then
                    local fPpPos = mod.UF_PowerPos(prefs)
                    local fPpIsAtt = (fPpPos == "below" or fPpPos == "above")
                    local powerHeight = fPpIsAtt and (prefs.powerHeight or 6) or 0
                    local focusBarHeight = prefs.healthHeight + powerHeight
                    local fBtbPos = prefs.btbPosition or "bottom"
                    local fBtbIsAtt = (fBtbPos == "top" or fBtbPos == "bottom")
                    local fBtbExtra = (prefs.bottomTextBar and fBtbIsAtt)
                            and (prefs.bottomTextBarHeight or 16)
                        or 0
                    local totalWidth = 0
                    local focusPStyle = prefs.portraitStyle or saved.profile.portraitStyle or "attached"
                    local isAttached = focusPStyle == "attached"
                    local pSide = prefs.portraitSide or "right"
                    local effectiveSide = pSide
                    if isAttached and pSide == "top" then
                        effectiveSide = "right"
                    end
                    local pSizeAdj = prefs.portraitSize or 0
                    if not isAttached then
                        pSizeAdj = pSizeAdj + 10
                    end
                    local pXOff = prefs.portraitX or 0
                    local pYOff = prefs.portraitY or 0
                    if not isAttached then
                        pYOff = pYOff + 5
                    end
                    local adjPortraitH = focusBarHeight + pSizeAdj
                    if adjPortraitH < 8 then
                        adjPortraitH = 8
                    end

                    if not showPortrait then
                        totalWidth = prefs.frameWidth
                    elseif isAttached then
                        totalWidth = adjPortraitH + prefs.frameWidth
                    else
                        totalWidth = prefs.frameWidth
                    end

                    Pix.Size(widget, totalWidth, focusBarHeight + fBtbExtra)

                    if
                        widget.Portrait
                        and widget.Portrait.backdrop
                        and not widget.Portrait.backdrop._isInside
                    then
                        Pix.Size(widget.Portrait.backdrop, adjPortraitH, adjPortraitH)
                        -- Trim portrait to stay within frame bounds
                        if showPortrait and isAttached then
                            local frameW = widget:GetWidth()
                            local frameH = widget:GetHeight()
                            local portW = widget.Portrait.backdrop:GetWidth()
                            local portH = widget.Portrait.backdrop:GetHeight()
                            if portW + prefs.frameWidth > frameW + 0.01 then
                                Pix.Width(widget.Portrait.backdrop, frameW - prefs.frameWidth)
                            end
                            if portH > frameH + 0.01 then
                                Pix.Height(widget.Portrait.backdrop, frameH)
                            end
                        end
                        -- Reposition portrait for attached/detached
                        widget.Portrait.backdrop:ClearAllPoints()
                        local fBtbTopOff = (fBtbPos == "top" and prefs.bottomTextBar)
                                and (prefs.bottomTextBarHeight or 16)
                            or 0
                        if isAttached then
                            if effectiveSide == "left" then
                                Pix.Point(
                                    widget.Portrait.backdrop,
                                    "TOPLEFT",
                                    widget,
                                    "TOPLEFT",
                                    0,
                                    -fBtbTopOff
                                )
                            else
                                Pix.Point(
                                    widget.Portrait.backdrop,
                                    "TOPRIGHT",
                                    widget,
                                    "TOPRIGHT",
                                    0,
                                    -fBtbTopOff
                                )
                            end
                        else
                            if effectiveSide == "top" then
                                widget.Portrait.backdrop:SetPoint(
                                    "BOTTOM",
                                    widget.Health or widget,
                                    "TOP",
                                    pXOff,
                                    15 + pYOff
                                )
                            elseif effectiveSide == "left" then
                                widget.Portrait.backdrop:SetPoint(
                                    "TOPRIGHT",
                                    widget.Health or widget,
                                    "TOPLEFT",
                                    -15 + pXOff,
                                    pYOff
                                )
                            else
                                widget.Portrait.backdrop:SetPoint(
                                    "TOPLEFT",
                                    widget.Health or widget,
                                    "TOPRIGHT",
                                    15 + pXOff,
                                    pYOff
                                )
                            end
                        end
                        -- Re-apply pixel snap disable after resize
                        if widget.Portrait.backdrop._2d then
                            UnsnapTex(widget.Portrait.backdrop._2d)
                        end
                        if widget:IsElementEnabled("Portrait") and widget.Portrait.ForceUpdate then
                            widget.Portrait:ForceUpdate()
                        end
                    end
                    if widget.Health then
                        widget.Health:ClearAllPoints()
                        local focusHealthXOff = (showPortrait and isAttached and effectiveSide == "left")
                                and adjPortraitH
                            or 0
                        local focusHealthRightInset = (
                            showPortrait
                            and isAttached
                            and effectiveSide == "right"
                        )
                                and adjPortraitH
                            or 0
                        -- Use portrait's actual snapped width for flush alignment
                        if showPortrait and isAttached and widget.Portrait and widget.Portrait.backdrop then
                            local snappedPortW = widget.Portrait.backdrop:GetWidth()
                            focusHealthXOff = (effectiveSide == "left") and snappedPortW or 0
                            focusHealthRightInset = (effectiveSide == "right") and snappedPortW or 0
                        end
                        local fHTopOff = (
                            fBtbPos == "top" and prefs.bottomTextBar and (prefs.bottomTextBarHeight or 16)
                            or 0
                        )
                        local fPowerAboveOff = (fPpPos == "above") and (prefs.powerHeight or 6) or 0
                        fHTopOff = fHTopOff + fPowerAboveOff
                        widget.Health._xOffset = focusHealthXOff
                        widget.Health._rightInset = focusHealthRightInset
                        widget.Health._topOffset = fHTopOff
                        Pix.Point(widget.Health, "TOPLEFT", widget, "TOPLEFT", focusHealthXOff, -fHTopOff)
                        Pix.Point(widget.Health, "RIGHT", widget, "RIGHT", -focusHealthRightInset, 0)
                        Pix.Height(widget.Health, prefs.healthHeight)
                    end
                    if widget.Power then
                        local fpw = prefs.frameWidth
                        local fPpIsDet = (fPpPos == "detached_top" or fPpPos == "detached_bottom")
                        if fPpIsDet and (prefs.powerWidth or 0) > 0 then
                            fpw = prefs.powerWidth
                        end
                        Pix.Size(widget.Power, fpw, prefs.powerHeight or 6)
                        widget.Power:ClearAllPoints()
                        if fPpPos == "none" then
                            widget.Power:Hide()
                        elseif fPpPos == "above" then
                            Pix.Point(widget.Power, "BOTTOMLEFT", widget.Health, "TOPLEFT", 0, 0)
                            Pix.Point(widget.Power, "BOTTOMRIGHT", widget.Health, "TOPRIGHT", 0, 0)
                            widget.Power:Show()
                        elseif fPpPos == "detached_top" then
                            widget.Power:SetPoint(
                                "BOTTOM",
                                widget.Health,
                                "TOP",
                                prefs.powerX or 0,
                                15 + (prefs.powerY or 0)
                            )
                            widget.Power:Show()
                        elseif fPpPos == "detached_bottom" then
                            widget.Power:SetPoint(
                                "TOP",
                                widget.Health,
                                "BOTTOM",
                                prefs.powerX or 0,
                                -15 + (prefs.powerY or 0)
                            )
                            widget.Power:Show()
                        else
                            Pix.Point(widget.Power, "TOPLEFT", widget.Health, "BOTTOMLEFT", 0, 0)
                            Pix.Point(widget.Power, "TOPRIGHT", widget.Health, "BOTTOMRIGHT", 0, 0)
                            widget.Power:Show()
                        end
                        if widget.Power._applyPowerPercentText then
                            widget.Power._applyPowerPercentText(prefs)
                        end
                        -- Update power bar border (detached only; lazily created)
                        mod.UpdatePowerBorder(widget.Power, prefs)
                    end
                    if widget._applyTextTags then
                        widget._applyTextTags(
                            prefs.leftTextContent or "name",
                            prefs.rightTextContent or "perhp",
                            prefs.centerTextContent or "none"
                        )
                    end
                    if widget._applyTextPositions then
                        widget._applyTextPositions(prefs)
                    end

                    -- Bottom Text Bar update (focus) -- must come before castbar so castbar can anchor to it
                    local fPpBtbAnchor = (fPpIsAtt and widget.Power) or widget.Health
                    if prefs.bottomTextBar then
                        local btbPos2 = prefs.btbPosition or "bottom"
                        local btbIsAtt2 = (btbPos2 == "top" or btbPos2 == "bottom")
                        local btbIsDet2 = not btbIsAtt2
                        local btbW2 = btbIsDet2 and (prefs.btbWidth or 0) or 0
                        local btbTW = (btbW2 > 0 and btbIsDet2) and btbW2 or totalWidth
                        local btbXOff = 0
                        if btbIsAtt2 and showPortrait and isAttached and effectiveSide == "left" then
                            btbXOff = -adjPortraitH
                        end
                        if not widget.BottomTextBar then
                            widget.BottomTextBar = CreateBottomTextBar(
                                widget,
                                unitToken,
                                prefs,
                                fPpBtbAnchor,
                                btbXOff,
                                totalWidth
                            )
                            widget._btb = widget.BottomTextBar
                        else
                            local btb = widget.BottomTextBar
                            Pix.Size(btb, btbTW, prefs.bottomTextBarHeight or 16)
                            btb:ClearAllPoints()
                            if btbPos2 == "top" then
                                Pix.Point(btb, "BOTTOMLEFT", widget.Health or widget, "TOPLEFT", btbXOff, 0)
                            elseif btbPos2 == "detached_top" then
                                btb:SetPoint("BOTTOM", widget, "TOP", prefs.btbX or 0, 15 + (prefs.btbY or 0))
                            elseif btbPos2 == "detached_bottom" then
                                btb:SetPoint(
                                    "TOP",
                                    widget,
                                    "BOTTOM",
                                    prefs.btbX or 0,
                                    -15 + (prefs.btbY or 0)
                                )
                            else
                                Pix.Point(btb, "TOPLEFT", fPpBtbAnchor, "BOTTOMLEFT", btbXOff, 0)
                            end
                            if btb.bg then
                                local bgc = prefs.btbBgColor or { r = 0.2, g = 0.2, b = 0.2 }
                                local bga = prefs.btbBgOpacity or 1.0
                                btb.bg:SetColorTexture(bgc.r, bgc.g, bgc.b, bga)
                            end
                            if btb._applyBTBTextTags then
                                btb._applyBTBTextTags(
                                    prefs.btbLeftContent or "none",
                                    prefs.btbRightContent or "none",
                                    prefs.btbCenterContent or "none"
                                )
                            end
                            if btb._applyBTBTextPositions then
                                btb._applyBTBTextPositions(prefs)
                                if btb._applyBTBClassIcon then
                                    btb._applyBTBClassIcon(prefs)
                                end
                            end
                            btb:Show()
                        end
                    elseif widget.BottomTextBar then
                        widget.BottomTextBar:Hide()
                    end

                    -- Castbar (focus)
                    ApplyUnitCastbar(widget, "focus", prefs)

                    UpdateBordersForScale(widget, unitToken)
                    ReparentBarsToClip(widget, mod.UF_PowerPos(prefs), prefs)
                elseif unitToken == "pet" or unitToken == "targettarget" or unitToken == "focustarget" then
                    -- Pet, ToT and FoT all share the same simple-frame layout:
                    -- optional portrait on either side, health bar filling the rest.
                    -- A WoW Forever pet adds its own power bar (built at spawn): an
                    -- attached bar grows the stack and the portrait squares off it.
                    local miniPower = (unitToken == "pet" and mod.UF_PetHasPower and not mod.UF_Blizz())
                            and widget.Power
                        or nil
                    local miniPpPos = miniPower and (prefs.powerPosition or "below") or "none"
                    local miniPowerH = (miniPpPos == "below" or miniPpPos == "above")
                            and (prefs.powerHeight or 6)
                        or 0
                    local miniAboveOff = (miniPpPos == "above") and miniPowerH or 0
                    local miniBarH = prefs.healthHeight + miniPowerH
                    local miniPStyle = prefs.portraitStyle or saved.profile.portraitStyle or "attached"
                    local showMiniPortrait = miniPStyle ~= "none" and prefs.showPortrait ~= false
                    local miniSide = prefs.portraitSide or "left"
                    local miniW = prefs.frameWidth
                    local miniLeftOff = 0
                    local miniRightInset = 0
                    if showMiniPortrait then
                        miniW = miniBarH + prefs.frameWidth
                        if miniSide == "right" then
                            miniRightInset = miniBarH
                        else
                            miniLeftOff = miniBarH
                        end
                    end
                    Pix.Size(widget, miniW, miniBarH)
                    if widget.Portrait and widget.Portrait.backdrop then
                        Pix.Size(widget.Portrait.backdrop, miniBarH, miniBarH)
                    end
                    if widget.Health then
                        widget.Health:ClearAllPoints()
                        Pix.Point(widget.Health, "TOPLEFT", widget, "TOPLEFT", miniLeftOff, -miniAboveOff)
                        Pix.Point(widget.Health, "RIGHT", widget, "RIGHT", -miniRightInset, 0)
                        Pix.Height(widget.Health, prefs.healthHeight)
                        widget.Health._xOffset = miniLeftOff
                        widget.Health._rightInset = miniRightInset
                        widget.Health._topOffset = miniAboveOff
                    end
                    if miniPower then
                        local mpw = prefs.frameWidth
                        if
                            (miniPpPos == "detached_top" or miniPpPos == "detached_bottom")
                            and (prefs.powerWidth or 0) > 0
                        then
                            mpw = prefs.powerWidth
                        end
                        Pix.Size(miniPower, mpw, prefs.powerHeight or 6)
                        miniPower:ClearAllPoints()
                        if miniPpPos == "none" then
                            miniPower:Hide()
                        elseif miniPpPos == "above" then
                            Pix.Point(miniPower, "BOTTOMLEFT", widget.Health, "TOPLEFT", 0, 0)
                            Pix.Point(miniPower, "BOTTOMRIGHT", widget.Health, "TOPRIGHT", 0, 0)
                            miniPower:Show()
                        elseif miniPpPos == "detached_top" then
                            miniPower:SetPoint(
                                "BOTTOM",
                                widget.Health,
                                "TOP",
                                prefs.powerX or 0,
                                15 + (prefs.powerY or 0)
                            )
                            miniPower:Show()
                        elseif miniPpPos == "detached_bottom" then
                            miniPower:SetPoint(
                                "TOP",
                                widget.Health,
                                "BOTTOM",
                                prefs.powerX or 0,
                                -15 + (prefs.powerY or 0)
                            )
                            miniPower:Show()
                        else
                            Pix.Point(miniPower, "TOPLEFT", widget.Health, "BOTTOMLEFT", 0, 0)
                            Pix.Point(miniPower, "TOPRIGHT", widget.Health, "BOTTOMRIGHT", 0, 0)
                            miniPower:Show()
                        end
                        if miniPower._applyPowerPercentText then
                            miniPower._applyPowerPercentText(prefs)
                        end
                        -- "none" parks the power painter (zero cost while hidden);
                        -- turning the bar back on repaints it at once.
                        local wantPower = miniPpPos ~= "none"
                        if widget:IsElementEnabled("Power") ~= wantPower then
                            if wantPower then
                                widget:EnableElement("Power")
                            else
                                widget:DisableElement("Power")
                            end
                        end
                    end

                    if unitToken == "pet" and widget.Castbar then
                        ApplyUnitCastbar(widget, unitToken, prefs)
                    end
                    UpdateBordersForScale(widget, unitToken)
                    ReparentBarsToClip(widget, mod.UF_PowerPos(prefs), prefs)
                elseif unitToken:match("^boss%d$") then
                    local bPpPos = prefs.powerPosition or "below"
                    local bPpIsAtt = (bPpPos == "below" or bPpPos == "above")
                    local powerHeight = bPpIsAtt and (prefs.powerHeight or 6) or 0
                    local bossBarHeight = prefs.healthHeight + powerHeight
                    local totalWidth = 0

                    if not showPortrait then
                        totalWidth = prefs.frameWidth
                    else
                        totalWidth = bossBarHeight + prefs.frameWidth
                    end

                    Pix.Size(widget, totalWidth, bossBarHeight)

                    if widget.Portrait and widget.Portrait.backdrop then
                        Pix.Size(widget.Portrait.backdrop, bossBarHeight, bossBarHeight)
                        local bossPSide = prefs.portraitSide or "right"
                        widget.Portrait.backdrop:ClearAllPoints()
                        if bossPSide == "left" then
                            Pix.Point(widget.Portrait.backdrop, "TOPLEFT", widget, "TOPLEFT", 0, 0)
                        else
                            Pix.Point(widget.Portrait.backdrop, "TOPRIGHT", widget, "TOPRIGHT", 0, 0)
                        end
                        CludesUI._ufPortraitSide[widget] = bossPSide
                    end
                    if widget.Health then
                        widget.Health:ClearAllPoints()
                        -- Use portrait's actual snapped width for flush alignment
                        local bossPortW = 0
                        if showPortrait then
                            if widget.Portrait and widget.Portrait.backdrop then
                                bossPortW = widget.Portrait.backdrop:GetWidth()
                            else
                                bossPortW = bossBarHeight
                            end
                        end
                        local bossPSide = prefs.portraitSide or "right"
                        local bossLeftOff = (showPortrait and bossPSide == "left") and bossPortW or 0
                        local bossRightInset = (showPortrait and bossPSide == "right") and bossPortW or 0
                        local bPowerAboveOff = (bPpPos == "above") and (prefs.powerHeight or 6) or 0
                        Pix.Point(widget.Health, "TOPLEFT", widget, "TOPLEFT", bossLeftOff, -bPowerAboveOff)
                        Pix.Point(widget.Health, "RIGHT", widget, "RIGHT", -bossRightInset, 0)
                        Pix.Height(widget.Health, prefs.healthHeight)
                        widget.Health._xOffset = bossLeftOff
                        widget.Health._rightInset = bossRightInset
                        widget.Health._topOffset = bPowerAboveOff
                    end
                    if widget.Power then
                        local bpw = prefs.frameWidth
                        local bPpIsDet = (bPpPos == "detached_top" or bPpPos == "detached_bottom")
                        if bPpIsDet and (prefs.powerWidth or 0) > 0 then
                            bpw = prefs.powerWidth
                        end
                        widget.Power:SetSize(bpw, prefs.powerHeight or 6)
                        widget.Power:ClearAllPoints()
                        if bPpPos == "none" then
                            widget.Power:Hide()
                        elseif bPpPos == "above" then
                            Pix.Point(widget.Power, "BOTTOMLEFT", widget.Health, "TOPLEFT", 0, 0)
                            Pix.Point(widget.Power, "BOTTOMRIGHT", widget.Health, "TOPRIGHT", 0, 0)
                            widget.Power:Show()
                        elseif bPpPos == "detached_top" then
                            widget.Power:SetPoint(
                                "BOTTOM",
                                widget.Health,
                                "TOP",
                                prefs.powerX or 0,
                                15 + (prefs.powerY or 0)
                            )
                            widget.Power:Show()
                        elseif bPpPos == "detached_bottom" then
                            widget.Power:SetPoint(
                                "TOP",
                                widget.Health,
                                "BOTTOM",
                                prefs.powerX or 0,
                                -15 + (prefs.powerY or 0)
                            )
                            widget.Power:Show()
                        else
                            Pix.Point(widget.Power, "TOPLEFT", widget.Health, "BOTTOMLEFT", 0, 0)
                            Pix.Point(widget.Power, "TOPRIGHT", widget.Health, "BOTTOMRIGHT", 0, 0)
                            widget.Power:Show()
                        end
                        if widget.Power._applyPowerPercentText then
                            widget.Power._applyPowerPercentText(prefs)
                        end

                        -- Gray out power bar background for generic melee NPCs
                        if bPpPos ~= "none" and (bPpPos == "below" or bPpPos == "above") then
                            local shouldGray = false
                            if
                                UnitExists(unitToken)
                                and UnitCanAttack("player", unitToken)
                                and not UnitIsPlayer(unitToken)
                            then
                                local cls = UnitClassification(unitToken)
                                local isBoss = (cls == "worldboss")
                                local isElite = (cls == "elite" or cls == "rareelite")
                                local lvl = UnitLevel(unitToken)
                                local pLvl = UnitLevel("player")
                                local isMB = isElite and (lvl == -1 or (pLvl and lvl >= pLvl + 1))
                                local isCst = UnitClassBase and UnitClassBase(unitToken)
                                if issecretvalue(isCst) then
                                    isCst = nil
                                end
                                isCst = (isCst == "PALADIN")
                                if not isBoss and not isMB and not isCst then
                                    shouldGray = true
                                end
                            end
                            if shouldGray then
                                widget.Power._grayedOut = true
                                if widget.Power.bg then
                                    widget.Power.bg:SetColorTexture(0.25, 0.25, 0.25, 1)
                                    widget.Power.bg:SetAlpha(1)
                                end
                            else
                                widget.Power._grayedOut = false
                            end
                        end
                    end

                    -- Castbar (boss)
                    if widget.Castbar then
                        local castbarBg = widget.Castbar:GetParent()
                        if castbarBg then
                            if castbarBg._bgTex then
                                local cbg = prefs.castBgColor
                                castbarBg._bgTex:SetColorTexture(
                                    cbg and cbg.r or 0,
                                    cbg and cbg.g or 0,
                                    cbg and cbg.b or 0,
                                    prefs.castBgAlpha or 0.5
                                )
                            end
                            if prefs.showCastbar ~= false then
                                if not widget:IsElementEnabled("Castbar") then
                                    widget:EnableElement("Castbar")
                                end
                                -- castbarWidth > 0 = user-set custom width; 0 = match frame width.
                                -- Custom widths floor at 30: below the cast icon size the
                                -- icon-in-width inset inverts the bar's anchor rect.
                                local bCbW = prefs.castbarWidth or 0
                                if bCbW > 0 and bCbW < 30 then
                                    bCbW = 30
                                end
                                Pix.Size(
                                    castbarBg,
                                    bCbW > 0 and bCbW or totalWidth,
                                    prefs.castbarHeight or 14
                                )
                                local bIconOffX, bIconOffY = CastIconOffsets("boss1", prefs)
                                LayoutCastbarIcon(
                                    widget.Castbar,
                                    CastIconInWidth("boss1", prefs),
                                    prefs.castbarHeight or 14,
                                    CastIconOnRight("boss1", prefs),
                                    bIconOffX,
                                    bIconOffY,
                                    CastIconShown("boss1", prefs),
                                    prefs.castbarStockBorderScale
                                )
                                mod.UF_ApplyCastBorder(widget.Castbar, prefs, nil, "boss1")
                                if widget.Castbar._iconFrame then
                                    local cbH = prefs.castbarHeight or 14
                                    Pix.Size(widget.Castbar._iconFrame, cbH, cbH)
                                    if not widget.Castbar:IsShown() then
                                        widget.Castbar._iconFrame:Hide()
                                    elseif prefs.showCastIcon == false then
                                        widget.Castbar._iconFrame:Hide()
                                    else
                                        widget.Castbar._iconFrame:Show()
                                    end
                                end
                                castbarBg:ClearAllPoints()
                                -- Anchor to the frame's own (pixel-snapped) bottom edge, not the
                                -- bar's bottom: health/power bars live in the sub-pixel-inset bar
                                -- clip, which left a ~1px gap below the frame. Cast bar is full
                                -- frame width, so frame bottom-center keeps it centered + flush.
                                -- castbarOffsetX/Y nudge the whole cast bar (positive = right/up).
                                -- Blizzard Style: hug the visible art's bottom, not the stock box.
                                local _, _, _, bossVisB = mod.UF_BlizzVis(widget)
                                castbarBg:SetPoint(
                                    "TOP",
                                    widget,
                                    "BOTTOM",
                                    prefs.castbarOffsetX or 0,
                                    (prefs.castbarOffsetY or 0) + (bossVisB or 0)
                                )
                                if prefs.castbarHideWhenInactive and not widget.Castbar:IsShown() then
                                    castbarBg:Hide()
                                else
                                    castbarBg:Show()
                                end
                            else
                                if widget:IsElementEnabled("Castbar") then
                                    widget:DisableElement("Castbar")
                                end
                                widget.Castbar:Hide()
                                castbarBg:Hide()
                            end
                        end
                        widget.Castbar._eufSettings = prefs
                        local bCbColor = castbarColor
                        if prefs.castbarFillColor then
                            bCbColor = prefs.castbarFillColor
                        end
                        widget.Castbar:SetStatusBarColor(
                            bCbColor.r,
                            bCbColor.g,
                            bCbColor.b,
                            ((prefs.castFillOpacity or 100) < 100) and 0 or castbarOpacity
                        )
                        mod.ApplyCastFillOpacity(widget.Castbar, prefs)
                        if widget.Castbar:IsShown() then
                            ApplyUnitFrameCastColor(widget.Castbar)
                            UpdateUnitFrameKickTick(widget.Castbar)
                        end
                        if widget.Castbar.Text then
                            local snSz = prefs.castSpellNameSize or 11
                            SetFSFont(widget.Castbar.Text, snSz)
                            local snC = prefs.castSpellNameColor or { r = 1, g = 1, b = 1 }
                            widget.Castbar.Text:SetTextColor(snC.r, snC.g, snC.b)
                        end
                        if widget.Castbar.Time then
                            local dtSz = prefs.castDurationSize or 10
                            SetFSFont(widget.Castbar.Time, dtSz)
                            local dtC = prefs.castDurationColor or { r = 1, g = 1, b = 1 }
                            widget.Castbar.Time:SetTextColor(dtC.r, dtC.g, dtC.b)
                            widget.Castbar._showDuration = prefs.showCastDuration ~= false
                            widget.Castbar._durationSize = dtSz
                            if widget.Castbar._showDuration and widget.Castbar:IsShown() then
                                widget.Castbar.Time:Show()
                            elseif not widget.Castbar._showDuration then
                                widget.Castbar.Time:Hide()
                            end
                        end
                        if widget.Castbar.Target then
                            local tsSz = prefs.castSpellTargetSize or 11
                            SetFSFont(widget.Castbar.Target, tsSz)
                            local tsC = prefs.castSpellTargetColor or { r = 1, g = 1, b = 1 }
                            widget.Castbar.Target:SetTextColor(tsC.r, tsC.g, tsC.b)
                            widget.Castbar._showTarget = prefs.showCastTarget ~= false
                            widget.Castbar._nameSide = prefs.castSpellNameSide or "left"
                            widget.Castbar._tgtSide = prefs.castSpellTargetSide or "right"
                            widget.Castbar._durSide = prefs.castDurationSide or "right"
                            if not widget.Castbar._showTarget then
                                widget.Castbar.Target:Hide()
                            end
                            if widget.Castbar._layoutTextZones then
                                widget.Castbar:_layoutTextZones()
                            end
                        end
                    end

                    UpdateBordersForScale(widget, unitToken)
                    ReparentBarsToClip(widget, mod.UF_PowerPos(prefs), prefs)
                end

                -- Determine if this is a mini frame that inherits border/texture/font
                local isMiniFrame = (
                    unitToken == "pet"
                    or unitToken == "targettarget"
                    or unitToken == "focustarget"
                    or unitToken:match("^boss%d$")
                )
                local donorSettings = isMiniFrame and GetMiniDonorSettings(UnitToSettingsKey(unitToken))
                    or prefs

                -- Apply health bar texture overlay (mini frames inherit the donor
                -- texture unless they set their own override).
                if isMiniFrame then
                    local uKey = UnitToSettingsKey(unitToken)
                    ApplyHealthBarTexture(
                        widget.Health,
                        uKey,
                        mod.ResolveHealthBarTextureKey(prefs, donorSettings)
                    )
                    ApplyHealthBarAlpha(widget.Health, uKey)
                else
                    ApplyHealthBarTexture(widget.Health, UnitToSettingsKey(unitToken))
                    ApplyHealthBarAlpha(widget.Health, UnitToSettingsKey(unitToken))
                end
                -- Cast bar reuses the same bar texture as the health bar.
                if widget.Castbar then
                    local cbTexKey
                    if isMiniFrame then
                        cbTexKey = mod.ResolveHealthBarTextureKey(prefs, donorSettings)
                    else
                        cbTexKey = prefs.healthBarTexture or saved.profile.healthBarTexture or "none"
                    end
                    mod.ApplyCastBarTexture(widget.Castbar, cbTexKey)
                end
                widget.Health:SetReverseFill(prefs.healthReverseFill and true or false)
                mod.ApplyHealthOrientation(widget.Health, prefs)
                ApplyDarkTheme(widget.Health, unitToken) -- re-anchors health.bg for the new axis
                UpdateAbsorbBarReverseFill(widget, prefs.healthReverseFill and true or false, prefs)
                mod.UF_HealPredApply(widget, unitToken, prefs)
                mod.UF_MaxHpApply(widget, unitToken)
                mod.UF_AbsorbGlowApply(widget, unitToken)
                -- Smooth bar interpolation (live toggle without /reload)
                if prefs.smoothBars then
                    widget.Health.smoothing = Enum
                        and Enum.StatusBarInterpolation
                        and Enum.StatusBarInterpolation.ExponentialEaseOut
                else
                    widget.Health.smoothing = Enum
                        and Enum.StatusBarInterpolation
                        and Enum.StatusBarInterpolation.Immediate
                end
                if widget.Health.ForceUpdate then
                    widget.Health:ForceUpdate()
                end

                -- Apply power bar opacity
                if widget.Power then
                    ApplyPowerBarAlpha(widget.Power, UnitToSettingsKey(unitToken))

                    -- Re-apply power bar fill color based on powerPercentPowerColor toggle.
                    -- Gradient (additive) layers on top of the resolved custom/power-type color.
                    local usePowerColor = prefs.powerPercentPowerColor ~= false
                    widget.Power.colorPower = usePowerColor
                    if not usePowerColor then
                        local customFill = prefs.customPowerFillColor
                        if customFill then
                            widget.Power:SetStatusBarColor(customFill.r, customFill.g, customFill.b)
                        else
                            widget.Power:SetStatusBarColor(0, 0, 1)
                        end
                    end
                    widget.Power.PostUpdateColor = function(self)
                        local s2 = GetSettingsForUnit(unitToken)
                        if not s2 then
                            return
                        end
                        local useP = s2.powerPercentPowerColor ~= false
                        local bR, bG, bB
                        -- PLAIN stand-ins for bR
                        local haveBase, baseSecret = false, false
                        if not useP then
                            local castFrame = s2.customPowerFillColor
                            if castFrame then
                                bR, bG, bB = castFrame.r, castFrame.g, castFrame.b
                            else
                                bR, bG, bB = 0, 0, 1
                            end
                            haveBase = true
                        else
                            if s2.powerClassColored then
                                haveBase, bR, bG, bB = mod.UF_PowerClassColor(unitToken)
                                baseSecret = haveBase and issecretvalue(bR)
                            end
                            if not haveBase then
                                -- Secret-safe per-unit power color (player via token,
                                -- non-player via the clean integer type), so custom power
                                -- colors apply on EVERY unit independent of oUF's sync.
                                bR, bG, bB = CludesUI.ResolveUnitPowerColor(unitToken)
                                haveBase = bR ~= nil
                            end
                        end
                        if s2.powerGradientEnabled and haveBase and not baseSecret then
                            local gc = s2.powerGradientColor
                            local ga = s2.powerBarOpacity or 100
                            if ga > 1.0 then
                                ga = ga / 100
                            end
                            ApplyBarGradient(
                                self:GetStatusBarTexture(),
                                s2.powerGradientDir or "HORIZONTAL",
                                bR,
                                bG,
                                bB,
                                ga,
                                gc and gc.r or 0.20,
                                gc and gc.g or 0.20,
                                gc and gc.b or 0.80,
                                ga
                            )
                        elseif not useP then
                            local castFrame = s2.customPowerFillColor
                            if castFrame then
                                self:SetStatusBarColor(castFrame.r, castFrame.g, castFrame.b)
                            else
                                self:SetStatusBarColor(0, 0, 1)
                            end
                        elseif haveBase then
                            -- Power/class-color mode (no gradient): explicitly paint the bar so it
                            -- doesn't depend on oUF's colors.power being synced.
                            self:SetStatusBarColor(bR, bG, bB)
                        end
                        -- Bar Background: power-colored bg tracks this unit's power
                        -- color each update (mirrors the fill); see CreatePowerBar.
                        if s2.powerBgPowerColored and self.bg then
                            local pr, pg, pb = CludesUI.ResolveUnitPowerColor(unitToken)
                            if pr then
                                local f = CludesUI.GetPowerBgDarkenFactor()
                                self.bg:SetColorTexture(pr * f, pg * f, pb * f, 1)
                            end
                        end
                        -- Keep the power-percent text color in sync with this unit
                        -- (per-unit power color; set up in CreatePowerBar). Gated on
                        -- the feature being active (power-colored AND text shown) ->
                        -- short-circuits to no cost for every other frame.
                        if
                            s2.powerPercentTextPowerColor
                            and (s2.powerPercentText or "none") ~= "none"
                            and self._applyPowerTextColor
                        then
                            self._applyPowerTextColor(s2)
                        end
                        -- Same continuous re-application for the Bottom Text Bar's
                        -- power-colored text (per-slot early-out keeps it ~free).
                        local btb = widget.BottomTextBar
                        if btb and btb._applyBTBPowerColors then
                            btb._applyBTBPowerColors(s2)
                        end
                    end
                    local customBg = prefs.customPowerBgColor
                    if customBg and widget.Power.bg then
                        widget.Power.bg:SetColorTexture(customBg.r, customBg.g, customBg.b, 1)
                    elseif widget.Power.bg then
                        widget.Power.bg:SetColorTexture(17 / 255, 17 / 255, 17 / 255, 1)
                    end
                    widget.Power:SetReverseFill(prefs.powerReverseFill and true or false)
                    -- Reverse-fill direction is only final here; re-derive Fill Opacity state
                    -- (ApplyPowerBarAlpha above ran before this SetReverseFill, so a direction
                    -- change would otherwise leave the bg anchored to the wrong side).
                    ApplyPowerBarAlpha(widget.Power, UnitToSettingsKey(unitToken))
                    if widget.Power.ForceUpdate then
                        widget.Power:ForceUpdate()
                    end
                    if unitToken == "player" then
                        mod.UF_SetupPowerCost(widget.Power, prefs)
                        mod.UF_PowerValSync(widget)
                    end
                    if unitToken == "player" and mod.UF_ForeverFormBar then
                        mod.UF_ForeverFormBar(widget, widget.Power, prefs)
                    end
                    -- WoW Forever mana regen spark (CludesUI_ManaRegenSpark.lua):
                    -- attached while the bar draws. Below SetReverseFill, which the
                    -- attach lays the spark out from. Power paints report mana only
                    -- while attached, so the bar's power type (PaintPower's) is
                    -- reported first and the attach never arms from a stale one.
                    if unitToken == "player" and CludesUI.ManaRegenSpark then
                        if prefs.manaRegenSpark and mod.UF_PowerBarDraws(prefs) then
                            local pt = CludesUI.GetPlayerPowerOverride() or UnitPowerType("player")
                            CludesUI.ManaRegenSpark.SetMana(
                                "uf",
                                not issecretvalue(pt) and pt == Enum.PowerType.Mana
                            )
                            CludesUI.ManaRegenSpark.Attach(
                                "uf",
                                widget.Power,
                                prefs.manaRegenSparkMode == "ticks"
                            )
                            widget.Power._manaRegenSpark = true
                        else
                            CludesUI.ManaRegenSpark.Detach("uf")
                            widget.Power._manaRegenSpark = nil
                        end
                    end
                end

                -- Apply castbar reverse fill
                if widget.Castbar then
                    widget.Castbar:SetReverseFill(prefs.castReverseFill and true or false)
                end

                if widget.unifiedBorder then
                    widget.unifiedBorder:ClearAllPoints()
                    -- Mini frames (ToT/Focus Target/Pet) may override ONLY the border
                    -- size per frame (settings.borderSizeOverride); color and texture
                    -- still inherit from the donor. nil = inherit the donor size.
                    -- Boss frames paint from ns.UF_BossBorderSettings: the donor's
                    -- border until the boss Border Style leaves Inherit.
                    -- ns.UF_FrameBorderPad mirrors this apply for size matching: change the two together.
                    local bsrc = donorSettings
                    if unitToken:match("^boss%d$") then
                        bsrc = mod.UF_BossBorderSettings()
                    end
                    local bs = prefs.borderSizeOverride or bsrc.borderSize or 1
                    local bc = bsrc.borderColor or { r = 0, g = 0, b = 0 }
                    local btex = bsrc.borderTexture or "solid"
                    -- The donor's exact size rides along only while the size IS the
                    -- donor's own; a per-frame override is a substitute step (legacy path).
                    local bpx = nil
                    if not prefs.borderSizeOverride then
                        bpx = CludesUI.BorderPx(bsrc.borderSizePx, bs, btex)
                    end
                    Pix.Point(widget.unifiedBorder, "TOPLEFT", widget, "TOPLEFT", 0, 0)
                    Pix.Point(widget.unifiedBorder, "BOTTOMRIGHT", widget, "BOTTOMRIGHT", 0, 0)
                    CludesUI.ApplyBorderStyle(
                        widget.unifiedBorder,
                        bs,
                        bc.r,
                        bc.g,
                        bc.b,
                        bsrc.borderAlpha or 1,
                        btex,
                        bsrc.borderTextureOffset,
                        bsrc.borderTextureOffsetY,
                        bsrc.borderTextureShiftX,
                        bsrc.borderTextureShiftY,
                        "unitframes",
                        bs,
                        nil,
                        bpx
                    )
                end
                -- Boss Hover/Target border: the border was just restyled to its normal
                -- color above, so re-apply the hover/target recolor (both default off,
                -- so this repaints the same normal color unless the user enabled one).
                if unitToken:match("^boss%d$") then
                    local isT = UnitIsUnit(unitToken, "target")
                    widget._isTarget = (not issecretvalue(isT) and isT) and true or false
                    mod.ApplyBossBorderState(widget)
                end

                -- Helper: set font on a FontString, using donor font for mini frames.
                -- A font family, as SetFSFont gives.
                local function SetMiniFont(fontStr, sz)
                    if not fontStr or not fontStr.SetFont then
                        return
                    end
                    if isMiniFrame then
                        CludesUI.ApplyModuleFontFamily(fontStr, donorFontPath, sz or 12, "unitFrames")
                    else
                        SetFSFont(fontStr, sz)
                    end
                end

                if widget.NameText then
                    local s = isMiniFrame and donorSettings or GetSettingsForUnit(unitToken)
                    local rts = s.leftTextSize or s.textSize or 12
                    SetMiniFont(widget.NameText, rts)
                    widget.NameText:SetWordWrap(false)
                end
                if widget.HealthValue then
                    local s = isMiniFrame and donorSettings or GetSettingsForUnit(unitToken)
                    local rts = s.rightTextSize or s.textSize or 12
                    SetMiniFont(widget.HealthValue, rts)
                    widget.HealthValue:SetWordWrap(false)
                end
                if widget.CenterText then
                    local s = isMiniFrame and donorSettings or GetSettingsForUnit(unitToken)
                    local cts = s.centerTextSize or s.textSize or 12
                    SetMiniFont(widget.CenterText, cts)
                    widget.CenterText:SetWordWrap(false)
                end

                -- Apply text tags and positions for mini frames
                if isMiniFrame and widget._applyTextTags then
                    widget._applyTextTags(
                        prefs.leftTextContent or "name",
                        prefs.rightTextContent or "none",
                        prefs.centerTextContent or "none"
                    )
                end
                if isMiniFrame and widget._applyTextPositions then
                    widget._applyTextPositions(prefs)
                end

                if widget.Castbar then
                    local s = isMiniFrame and donorSettings or prefs
                    if widget.Castbar.Text then
                        local snSz = s.castSpellNameSize or 11
                        SetMiniFont(widget.Castbar.Text, snSz)
                    end
                    if widget.Castbar.Time then
                        local dtSz = s.castDurationSize or 10
                        SetMiniFont(widget.Castbar.Time, dtSz)
                    end
                    -- Boss frames get their full cast text refresh in the boss branch above
                    -- (colors/show/sides/bg). Two gaps remain: the donor-font line just above
                    -- set boss cast text to the DONOR size, and that branch re-runs layout from
                    -- CACHED offsets. Re-apply the size from boss settings (keeping the donor
                    -- typeface) and sync X/Y offsets + side layout so live boss frames update
                    -- on every cast-text option change.
                    if unitToken:match("^boss") then
                        local cb = widget.Castbar
                        if cb.Text then
                            SetMiniFont(cb.Text, prefs.castSpellNameSize or 11)
                        end
                        if cb.Time then
                            SetMiniFont(cb.Time, prefs.castDurationSize or 10)
                        end
                        if cb.Target then
                            SetMiniFont(cb.Target, prefs.castSpellTargetSize or 11)
                        end
                        if cb._syncOffsetsAndLayout then
                            cb:_syncOffsetsAndLayout(prefs)
                        end
                    end
                end
            end -- else (enabled frame processing)
        end
    end

    -- Refresh combat indicator on player + target frames after settings change
    for _, ciu in ipairs({ "player", "target" }) do
        local cif = frameList[ciu]
        if cif and cif._applyCombatTexture then
            cif._applyCombatTexture()
            local ciDefStyle = (ciu == "player") and "standard" or "none"
            if
                (saved.profile[ciu].combatIndicatorStyle or ciDefStyle) ~= "none"
                and UnitAffectingCombat(ciu)
            then
                cif._combatIndicator:Show()
            else
                cif._combatIndicator:Hide()
            end
        end
    end

    -- Refresh leader indicator on player frame after settings change
    if frameList.player and frameList.player._applyLeaderIndicator then
        frameList.player._applyLeaderIndicator()
    end
    if frameList.target and frameList.target._applyLeaderIndicator then
        frameList.target._applyLeaderIndicator()
    end

    -- Refresh elite/rare indicator on the target frame after settings change
    if frameList.target and frameList.target._applyEliteIndicator then
        frameList.target._applyEliteIndicator()
    end
    -- Portrait Dragon on the player, target and focus frames, after every
    -- portrait above has its final size, shape and clip.
    mod.UF_ApplyPortraitDragons()

    -- Refresh faction indicator on the player and target frames after settings change
    if frameList.player and frameList.player._applyFactionIndicator then
        frameList.player._applyFactionIndicator()
    end
    if frameList.target and frameList.target._applyFactionIndicator then
        frameList.target._applyFactionIndicator()
    end
    -- Pet happiness icon (WoW Forever): enable, size, side and offsets.
    mod.UF_ApplyPetHappiness()

    ---------------------------------------------------------------------------
    --  Live-update raid target marker icon (size / alignment / X / Y / enabled)
    --  for player, target, focus, and boss frames.  Uses oUF's EnableElement /
    --  DisableElement so the RAID_TARGET_UPDATE event is properly toggled.
    ---------------------------------------------------------------------------
    local RAID_MARKER_UNITS = { "player", "target", "focus", "boss1", "boss2", "boss3", "boss4", "boss5" }
    for _, rmUnit in ipairs(RAID_MARKER_UNITS) do
        local rmFrame = frameList[rmUnit]
        local icon = rmFrame and rmFrame._raidMarkerIcon
        if rmFrame and icon then
            local rmS = GetSettingsForUnit(rmUnit)
            local rmSize = (rmS and rmS.raidMarkerSize) or 28
            local rmAlign = (rmS and rmS.raidMarkerAlign) or "right"
            local rmX = (rmS and rmS.raidMarkerX) or 0
            local rmY = (rmS and rmS.raidMarkerY) or 0
            local rmEnabled = rmS and rmS.raidMarkerEnabled
            local isBoss = rmUnit:match("^boss%d$")
            icon:SetSize(rmSize, rmSize)
            icon:ClearAllPoints()
            if isBoss then
                if rmAlign == "left" then
                    icon:SetPoint("RIGHT", rmFrame, "LEFT", rmX, rmY)
                elseif rmAlign == "center" then
                    icon:SetPoint("CENTER", rmFrame, "CENTER", rmX, rmY)
                else
                    icon:SetPoint("LEFT", rmFrame, "RIGHT", rmX, rmY)
                end
            else
                local rmAnchor = (rmAlign == "left") and "TOPLEFT"
                    or (rmAlign == "center") and "TOP"
                    or "TOPRIGHT"
                icon:SetPoint("CENTER", rmFrame, rmAnchor, rmX, rmY)
            end
            if rmEnabled then
                rmFrame.RaidTargetIndicator = icon
                rmFrame:EnableElement("RaidTargetIndicator")
                if icon.ForceUpdate then
                    icon:ForceUpdate()
                end
            else
                rmFrame:DisableElement("RaidTargetIndicator")
                rmFrame.RaidTargetIndicator = nil
                icon:Hide()
            end
        end
    end

    -- Portrait settings (3D zoom, class style) used to live-apply through the ungated
    -- ambient repaints; the gated Override skips same-unit repaints, so settings
    -- changes now force one explicit portrait update per frame instead.
    for _, widget in pairs(frameList) do
        if type(widget) == "table" and widget.Portrait and widget.Portrait.ForceUpdate then
            widget.Portrait:ForceUpdate()
        end
    end

    -- Blizzard Style: one final geometry/art pass over every frame, after all
    -- the per-unit re-anchors above (idempotent; nothing while the style is off).
    if mod.UF_Blizz() then
        for _, widget in pairs(frameList) do
            if type(widget) == "table" and widget.Health and widget._cuiBaseUnit then
                mod.UF_ApplyBlizzardLayout(widget, widget._cuiBaseUnit)
            end
        end
    end
    -- WoW Forever: the combo point arc round its host frame's portrait, placed
    -- on the geometry the sweep just settled (returns at once everywhere else).
    mod.UF_ApplyForeverComboArc()

    -- Detached portrait click overlays, and once more next frame (anchors still
    -- resolving) only while a frame uses one.
    if SyncPortraitClicks() then
        C_Timer.After(0, SyncPortraitClicks)
    end

    -- Rounded corners (CludesUI_RoundedCorners.lua), on the settled
    -- geometry. The radius rides with the border source, like the border; a
    -- detached power bar rounds on its own with the same radius. An attached
    -- portrait joins with its own art only: the dragons on it reach past the
    -- frame and stay whole.
    for unitToken, widget in pairs(frameList) do
        if type(unitToken) == "string" and type(widget) == "table" and widget.unifiedBorder then
            local isMini = (unitToken == "pet" or unitToken == "targettarget" or unitToken == "focustarget")
            local isBoss = unitToken:match("^boss%d$") and true or false
            local source = isBoss and mod.UF_BossBorderSettings()
                or (isMini and GetMiniDonorSettings(unitToken))
                or GetSettingsForUnit(unitToken)
            local us = GetSettingsForUnit(unitToken)
            local radius = (not widget._blizzArtFrame and source and source.cornerRadius) or 0
            local corners = source and source.cornerMask
            local power = widget.Power
            local pp = mod.UF_PowerPos(us)
            local det = pp == "detached_top" or pp == "detached_bottom"
            -- Join Power Bar: a detached bar right above or below the frame
            -- shares its outline (the frame keeps the far corners).
            local pCorners = corners
            if det and us.cornerJoinPower then
                local max, lower = CludesUI.RoundedJoinCorners(corners)
                if pp == "detached_bottom" then
                    corners, pCorners = max, lower
                else
                    corners, pCorners = lower, max
                end
            end
            if radius > 0 then
                local ps = us and us.portraitStyle or profile.portraitStyle or "attached"
                local attached = ps == "attached" or ((isMini or isBoss) and ps == "detached")
                local edge = widget.Portrait and widget.Portrait.backdrop
                if not (attached and edge and edge:IsShown()) then
                    edge = nil
                end
                local btb = widget.BottomTextBar
                CludesUI.RoundCorners(widget, radius, {
                    roots = { widget._barClip, btb and not btb._isDetached and btb or nil },
                    textures = { edge and edge._bg, edge and edge._2d, edge and edge._class },
                    border = widget.unifiedBorder,
                    clip = widget._barClip,
                    style = source.borderTexture or "solid",
                    corners = corners,
                })
            else
                CludesUI.RoundCorners(widget, 0)
            end
            if power then
                if det and radius > 0 then
                    CludesUI.RoundCorners(power, radius, {
                        border = power._pbBorder,
                        style = us.powerBorderStyle or "solid",
                        corners = pCorners,
                    })
                else
                    CludesUI.RoundCorners(power, 0)
                end
            end
        end
    end

    -- Player Aura Bars resolve font path and outline flag at style-build time; every
    -- settings path landing here (fonts, profiles, options) forces one explicit
    -- re-skin of the default and custom bars, both change-guarded no-ops when nothing changed.
    if mod.PAB_Restyle then
        mod.PAB_Restyle()
    end
    -- Profile-grade resync: enable/useBlizzard modes, native frames, default
    -- movers, and a late build when a swap lands on an enabled profile from
    -- a disabled-at-login session. Cheap no-op when nothing changed.
    if mod.PAB_ProfileResync then
        mod.PAB_ProfileResync()
    end
    -- Reload-all also SWEEPS stale bar ids (a previous profile's bars must
    -- park on swap -- field report).
    if mod.PAB_ReloadAllCustomBars then
        mod.PAB_ReloadAllCustomBars()
    end
    mod.UF_PlayerPortraitChanged()
    -- Size matching: the unified borders were just applied, so report each
    -- frame's border pad; only a pad that really changed re-pushes its matches.
    if CludesUI.MatchPadChanged then
        local padKeys = mod.UF_PAD_KEYS
        for idx = 1, #padKeys do
            CludesUI.MatchPadChanged(padKeys[idx])
        end
    end
    -- Last: its ForceAll repaint must follow the per-frame ApplyDarkTheme, or turning
    -- Dark Mode off left the class-colored fill dark until the next health event.
    ApplyEnemyColors()
end

-- The unit frames whose unified border can reach outside the frame (the
-- class resource bar has none, the boss stack is never size matched), and
-- the three cast bars (a Custom Border Style border, the Classic frame; the
-- cast bar pass runs inside the same reload sweep).
mod.UF_PAD_KEYS = {
    "player",
    "target",
    "focus",
    "pet",
    "targettarget",
    "focustarget",
    "playerCastbar",
    "targetCastbar",
    "focusCastbar",
    "petCastbar",
}

-- Size matching: the width and height the unit frame's textured border draws
-- OUTSIDE the frame, from exactly what the reload sweep's unified border apply
-- passes (the paint that lands last: the minis take the donor's border, and a
-- per-frame Border Size override drops the donor's exact size). The border
-- wraps the frame getSize measures. nil for a solid border, under the stock
-- looks (no CludesUI border), for the class resource bar and the boss
-- stack. Reads settings only. Change together with the sweep.
function mod.UF_FrameBorderPad(key)
    if key == "classPower" or key == "boss" or mod.UF_Blizz() then
        return nil
    end
    local prefs = GetSettingsForUnit(key)
    if not prefs then
        return nil
    end
    local isMini = (key == "pet" or key == "targettarget" or key == "focustarget")
    local d = isMini and GetMiniDonorSettings(key) or prefs
    local btex = d.borderTexture or "solid"
    if btex == "solid" then
        return nil
    end
    local bs = prefs.borderSizeOverride or d.borderSize or 1
    local bpx = nil
    if not prefs.borderSizeOverride then
        bpx = CludesUI.BorderPx(d.borderSizePx, bs, btex)
    end
    return CludesUI.BorderMatchPad(
        bs,
        btex,
        d.borderTextureOffset,
        d.borderTextureOffsetY,
        d.borderTextureShiftX,
        d.borderTextureShiftY,
        "unitframes",
        bs,
        bpx,
        nil,
        d.borderAlpha or 1
    )
end

Inner.ReloadFrames = ReloadFrames
