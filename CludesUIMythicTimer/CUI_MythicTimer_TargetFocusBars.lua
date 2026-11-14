if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
--------------------------------------------------------------------------------
--  CUI_MythicTimer_TargetFocusBars.lua
--  Target/Focus Bars (Mythic+ Tools): standalone cast bars for the target and
--  focus units, placeable anywhere via unlock mode, carrying the nameplate
--  cast color/effects system -- interrupt-ready tint, uninterruptible overlay
--  + shield, important-cast color, kick-ready mid-cast hint (tick + window
--  fill), and the interrupted flash.
--
--  Zero cost while disabled: no events are registered and no frames are built
--  until a bar is enabled. Secret discipline throughout: type() existence
--  checks, duration objects into SetTimerDuration, boolean color curves via
--  C_CurveUtil, SetAlphaFromBoolean for secret-gated visibility -- never a
--  Lua branch on a secret value.
--------------------------------------------------------------------------------
local ADDON_NAME, mod = ...

local saved -- Lite DB handle, handed over by ns.TFB_OnEnable

local function TF()
    local p = saved and saved.profile
    return p and p.tfb
end

local function BarCfg(which)
    local tf = TF()
    return tf and tf[which]
end

--------------------------------------------------------------------------------
--  Fonts (module surface "mythicTimer": family/outline/shadow are global,
--  only sizes are per-bar settings). A bar's target text names a player, so
--  the bar texts take a font family (Cyrillic, Korean and Chinese names
--  draw); no plain SetFont may reach them after it.
--------------------------------------------------------------------------------
local function SetFSFont(fontStr, size)
    CludesUI.ApplyModuleFontFamily(fontStr, nil, size, "mythicTimer")
end

--------------------------------------------------------------------------------
--  State: two bar objects, built lazily. `bars.target` / `bars.focus`.
--------------------------------------------------------------------------------
local barList = {}
local isActive = false -- events registered
local activeCastCount = 0 -- casts live across both bars (watcher arm/disarm)
local castColorTicker -- 0.2s re-tint while any cast is up
local previewOn = { target = false, focus = false }

local DEFAULT_POS = {
    target = { x = 0, y = -240 },
    focus = { x = 0, y = -310 },
}

local GetActiveKickSpell = CludesUI.GetActiveKickSpell
local ComputeCastBarTint = CludesUI.ComputeCastBarTint

--------------------------------------------------------------------------------
--  Position (unlock interchange = raw UIParent-logical center delta; scale
--  division never leaves the module's own SetPoint -- the timer lesson).
--------------------------------------------------------------------------------
local function ApplyBarPosition(bar)
    if not bar then
        return
    end
    local conf = BarCfg(bar.which)
    local place = conf and conf.pos
    bar.frame:ClearAllPoints()
    if place and place.centerX and place.centerY then
        bar.frame:SetPoint("CENTER", UIParent, "CENTER", place.centerX, place.centerY)
    else
        local d = DEFAULT_POS[bar.which]
        bar.frame:SetPoint("CENTER", UIParent, "CENTER", d.x, d.y)
    end
end

--------------------------------------------------------------------------------
--  Bar construction (lazy, once per unit). Structure mirrors the nameplate
--  cast bar: fill + uninterruptible overlay + shield + spark + kick clip
--  (positioner/marker/tick/ready-fill) + three text zones + icon.
--
--  The chrome (everything StyleBar and the static sample paint touch) is its
--  own builder so the options header sample can be built on its column host
--  without the kick machinery, the timer ticker or a slot in `bars`.
--------------------------------------------------------------------------------
local function BuildBarChrome(which, hostFrame)
    local unitToken = which -- "target" / "focus" ARE the unit tokens
    local holderFrame = CreateFrame("Frame", nil, hostFrame)
    holderFrame:Hide()

    local bar = { which = which, unit = unitToken, frame = holderFrame }

    bar.bg = holderFrame:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints(holderFrame)
    bar.bg:SetColorTexture(0, 0, 0, 0.45)

    bar.iconFrame = CreateFrame("Frame", nil, holderFrame)
    bar.iconFrame:SetPoint("TOPLEFT", holderFrame, "TOPLEFT", 0, 0)
    bar.iconFrame:SetPoint("BOTTOMLEFT", holderFrame, "BOTTOMLEFT", 0, 0)
    bar.icon = bar.iconFrame:CreateTexture(nil, "ARTWORK")
    bar.icon:SetAllPoints(bar.iconFrame)
    bar.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    bar.sb = CreateFrame("StatusBar", nil, holderFrame)
    -- Placeholder fill: a StatusBar has NO texture object until one is set, and
    -- the fill-edge riders below plus every GetStatusBarTexture() call on the
    -- cast path would index nil on a bar that never reached StyleBar.
    bar.sb:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    bar.sb:SetPoint("TOPLEFT", bar.iconFrame, "TOPRIGHT", 0, 0)
    bar.sb:SetPoint("BOTTOMRIGHT", holderFrame, "BOTTOMRIGHT", 0, 0)
    bar.sb:SetMinMaxValues(0, 1)
    bar.sb:SetValue(0)

    -- Uninterruptible grey wash: rides the fill texture, alpha-gated by the
    -- (possibly secret) protection flag via SetAlphaFromBoolean.
    bar.overlay = bar.sb:CreateTexture(nil, "ARTWORK", nil, 2)
    bar.overlay:SetAllPoints(bar.sb:GetStatusBarTexture())
    bar.overlay:SetTexture("Interface\\Buttons\\WHITE8x8")
    bar.overlay:SetAlpha(0)

    -- Interrupted flash: a full-bar wash OVER the fill. Deliberately not a
    -- fill repaint -- an armed SetTimerDuration owns the drawn fill and a
    -- plain SetValue neither repaints nor reliably reclaims it.
    bar.flash = bar.sb:CreateTexture(nil, "ARTWORK", nil, 3)
    bar.flash:SetAllPoints(bar.sb)
    bar.flash:SetTexture("Interface\\Buttons\\WHITE8x8")
    bar.flash:Hide()

    bar.spark = bar.sb:CreateTexture(nil, "OVERLAY", nil, 1)
    bar.spark:SetTexture("Interface\\AddOns\\CludesUI\\media\\cast_spark.tga")
    bar.spark:SetBlendMode("ADD")
    bar.spark:SetPoint("CENTER", bar.sb:GetStatusBarTexture(), "RIGHT", 0, 0)

    bar.shieldFrame = CreateFrame("Frame", nil, holderFrame)
    bar.shieldFrame:SetPoint("CENTER", holderFrame, "LEFT", 0, 0)
    bar.shieldFrame:SetFrameLevel(holderFrame:GetFrameLevel() + 5)
    bar.shieldFrame:Hide()
    bar.shield = bar.shieldFrame:CreateTexture(nil, "OVERLAY")
    bar.shield:SetAllPoints()
    bar.shield:SetAtlas("nameplates-InterruptShield")

    bar.textFrame = CreateFrame("Frame", nil, bar.sb)
    bar.textFrame:SetAllPoints(bar.sb)
    bar.textFrame:SetFrameLevel(bar.sb:GetFrameLevel() + 6)
    -- Fonts applied at BUILD as well as in StyleBar: a bar can be built on a
    -- disabled path (unlock getFrame, enable round-trip) and its teardown
    -- SetText("") errors on a fontless FontString.
    bar.name = bar.textFrame:CreateFontString(nil, "OVERLAY")
    bar.name:SetJustifyH("LEFT")
    bar.name:SetWordWrap(false)
    bar.name:SetMaxLines(1)
    SetFSFont(bar.name, 11)
    bar.target = bar.textFrame:CreateFontString(nil, "OVERLAY")
    bar.target:SetJustifyH("RIGHT")
    bar.target:SetWordWrap(false)
    bar.target:SetMaxLines(1)
    SetFSFont(bar.target, 10)
    bar.timer = bar.textFrame:CreateFontString(nil, "OVERLAY")
    bar.timer:SetJustifyH("RIGHT")
    bar.timer:SetWordWrap(false)
    bar.timer:SetMaxLines(1)
    SetFSFont(bar.timer, 11)

    return bar
end

local function BuildBar(which)
    local bar = BuildBarChrome(which, UIParent)

    -- Kick tick machinery, clipped so the tick never renders outside the bar
    -- when the kick CD exceeds the remaining cast.
    bar.kickClip = CreateFrame("Frame", nil, bar.sb)
    bar.kickClip:SetAllPoints(bar.sb)
    bar.kickClip:SetClipsChildren(true)
    bar.kickPositioner = CreateFrame("StatusBar", nil, bar.kickClip)
    bar.kickPositioner:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    bar.kickPositioner:GetStatusBarTexture():SetAlpha(0)
    bar.kickPositioner:SetPoint("CENTER", bar.sb)
    bar.kickPositioner:SetFrameLevel(bar.sb:GetFrameLevel() + 1)
    bar.kickPositioner:Hide()
    bar.kickMarker = CreateFrame("StatusBar", nil, bar.kickClip)
    bar.kickMarker:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    bar.kickMarker:GetStatusBarTexture():SetAlpha(0)
    bar.kickMarker:SetPoint("LEFT", bar.kickPositioner:GetStatusBarTexture(), "RIGHT")
    bar.kickMarker:SetSize(1, 1)
    bar.kickMarker:SetFrameLevel(bar.sb:GetFrameLevel() + 2)
    bar.kickMarker:Hide()
    local function Unsnap(sbFrame)
        local tx = sbFrame:GetStatusBarTexture()
        if tx and tx.SetSnapToPixelGrid then
            tx:SetSnapToPixelGrid(false)
            tx:SetTexelSnappingBias(0)
        end
    end
    Unsnap(bar.kickPositioner)
    Unsnap(bar.kickMarker)
    bar.kickTick = bar.kickMarker:CreateTexture(nil, "OVERLAY", nil, 3)
    bar.kickTick:SetColorTexture(1, 1, 1, 1)
    bar.kickTick:SetWidth(2)
    bar.kickTick:SetPoint("TOP", bar.kickMarker, "TOP", 0, 0)
    bar.kickTick:SetPoint("BOTTOM", bar.kickMarker, "BOTTOM", 0, 0)
    bar.kickTick:SetPoint("LEFT", bar.kickMarker:GetStatusBarTexture(), "RIGHT")
    -- Mid-cast "kick available" window: rides the marker geometry so the
    -- two-secret in-time test resolves by where the marker edge lands (the
    -- anchors cross and the fill collapses to zero width -- no Lua branch).
    bar.kickReadyFill = bar.sb:CreateTexture(nil, "ARTWORK", nil, 1)
    bar.kickReadyFill:SetColorTexture(1, 1, 1, 1)
    bar.kickReadyFill:SetAlpha(0)
    bar.kickReadyFill:Hide()

    -- 10Hz cast timer text (engine-slept between fires; self-stops when the
    -- cast ends). Remaining time from the duration object only. bar.durKind
    -- (set by ArmFill, which already knows which getter applies) picks the
    -- one matching API instead of probing all three every tick; falls back to
    -- the full chain on a transient miss or before any kind is cached.
    bar._timerTick = function(force)
        if not bar.isCasting and not force then
            return
        end
        local conf = BarCfg(bar.which)
        if not conf or conf.showTimer == false then
            return true
        end
        if UnitCastingDuration then
            local durObj
            local kind = bar.durKind
            if kind == "cast" then
                durObj = UnitCastingDuration(bar.unit)
            elseif kind == "empowered" then
                durObj = UnitEmpoweredChannelDuration and UnitEmpoweredChannelDuration(bar.unit, true)
            elseif kind == "channel" then
                durObj = UnitChannelDuration and UnitChannelDuration(bar.unit)
            end
            if not durObj then
                durObj = UnitCastingDuration(bar.unit)
                    or (UnitEmpoweredChannelDuration and UnitEmpoweredChannelDuration(bar.unit, true))
                    or (UnitChannelDuration and UnitChannelDuration(bar.unit))
            end
            if durObj then
                bar.timer:SetFormattedText("%.1f", durObj:GetRemainingDuration())
            else
                bar.timer:SetText("")
            end
        end
        return true
    end
    if CludesUI.Tick and CludesUI.Tick.NewAnimTicker then
        bar._timerTicker = CludesUI.Tick.NewAnimTicker(bar.frame, bar._timerTick, 0.1)
    end

    barList[which] = bar
    ApplyBarPosition(bar)
    return bar
end

--------------------------------------------------------------------------------
--  Style pass
--------------------------------------------------------------------------------
local function StyleBar(bar)
    local conf = BarCfg(bar.which)
    local tf = TF()
    if not (conf and tf) then
        return
    end
    local wid = conf.width or 260
    local hgt = conf.height or 22
    bar.frame:SetSize(wid, hgt)

    local showIcon = conf.showIcon ~= false
    bar.iconFrame:SetWidth(showIcon and hgt or 0.001)
    bar.iconFrame:SetShown(showIcon)

    local texPath = CludesUI.ResolveTexturePath(
        mod.barTextures,
        conf.texture or "none",
        "Interface\\Buttons\\WHITE8x8"
    ) or "Interface\\Buttons\\WHITE8x8"
    bar.sb:SetStatusBarTexture(texPath)
    local pp = CludesUI.PP
    if pp and pp.DisablePixelSnap then
        pp.DisablePixelSnap(bar.sb:GetStatusBarTexture())
    end
    -- Fill texture re-mint: re-pin the fill-edge riders.
    bar.overlay:ClearAllPoints()
    bar.overlay:SetAllPoints(bar.sb:GetStatusBarTexture())
    bar.spark:ClearAllPoints()
    bar.spark:SetPoint("CENTER", bar.sb:GetStatusBarTexture(), "RIGHT", 0, 0)
    bar.spark:SetSize(8, hgt)
    bar.spark:SetShown(tf.showSpark ~= false)

    local un = tf.uninterruptible or { r = 0.45, g = 0.45, b = 0.45 }
    bar.overlay:SetVertexColor(un.r, un.g, un.b)

    local fl = tf.interruptedColor or { r = 0.8, g = 0, b = 0 }
    bar.flash:SetVertexColor(fl.r, fl.g, fl.b, 0.85)

    local shieldH = hgt * 0.75
    bar.shieldFrame:SetSize(shieldH * (29 / 35), shieldH)

    if pp and pp.CreateBorder then
        if not bar._border then
            bar._border = true
            pp.CreateBorder(bar.frame, 0, 0, 0, 1, 1, "OVERLAY", 7)
        end
    end

    SetFSFont(bar.name, conf.nameSize or 11)
    SetFSFont(bar.target, conf.targetSize or 10)
    SetFSFont(bar.timer, conf.timerSize or 11)

    local showTimer = conf.showTimer ~= false
    local reserve = showTimer and ((conf.timerSize or 11) * 2.2) or 0
    bar.name:ClearAllPoints()
    bar.name:SetPoint("LEFT", bar.sb, "LEFT", 4, 0)
    bar.name:SetWidth((wid - hgt) * 0.48)
    bar.timer:ClearAllPoints()
    bar.timer:SetPoint("RIGHT", bar.sb, "RIGHT", -3, 0)
    bar.target:ClearAllPoints()
    bar.target:SetPoint("RIGHT", bar.sb, "RIGHT", -3 - reserve, 0)
    bar.target:SetWidth((wid - hgt) * 0.40)

    bar.name:SetShown(conf.showSpellName ~= false)
    bar.timer:SetShown(showTimer)
end

--------------------------------------------------------------------------------
--  Cast color: kick-ready tint over the base (or Important) color. All secret
--  combines ride C_CurveUtil boolean curves; nothing branches on a secret.
--------------------------------------------------------------------------------
local impScratch = {}
local function ApplyCastColor(bar, uninterruptible)
    local tf = TF()
    if not tf then
        return
    end
    local kickReadyTint = tf.interruptReady or { r = 0.92, g = 0.35, b = 0.20 }
    local baseTint = tf.castColor or { r = 0.70, g = 0.40, b = 0.90 }
    if tf.importantEnabled and C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean then
        local imp = tf.importantColor or { r = 1, g = 0.2, b = 0.2 }
        local isImp = bar._castImportant
        if type(isImp) == "nil" then
            isImp = false
        end
        local ev = C_CurveUtil.EvaluateColorValueFromBoolean
        impScratch.r = ev(isImp, imp.r, baseTint.r)
        impScratch.g = ev(isImp, imp.g, baseTint.g)
        impScratch.b = ev(isImp, imp.b, baseTint.b)
        baseTint = impScratch
    end
    local cr, cg, cb = ComputeCastBarTint(kickReadyTint, baseTint)
    bar.sb:GetStatusBarTexture():SetVertexColor(cr, cg, cb)
    local showShield = TF().showShield ~= false
    if bar.overlay.SetAlphaFromBoolean then
        bar.overlay:SetAlphaFromBoolean(uninterruptible)
        if showShield then
            bar.shieldFrame:SetAlphaFromBoolean(uninterruptible)
        else
            bar.shieldFrame:SetAlpha(0)
        end
    else
        local a = uninterruptible and 1 or 0
        bar.overlay:SetAlpha(a)
        bar.shieldFrame:SetAlpha(showShield and a or 0)
    end
end

--------------------------------------------------------------------------------
--  Kick tick + mid-cast window (nameplate port). Geometry is cast-identity
--  work; RefreshKickTick re-pins the PAIRED positioner/marker snapshot on
--  cooldown events -- never one without the other (the tick drifts).
--------------------------------------------------------------------------------
local function HideKickTick(bar)
    bar.kickPositioner:Hide()
    bar.kickMarker:Hide()
    bar.kickReadyFill:Hide()
    bar.kickTick:Hide()
    if bar._kickTicker then
        bar._kickTicker:Cancel()
        bar._kickTicker = nil
    end
end

local function UpdateKickTick(bar, kickProtected, isChannel, isEmpowered)
    local tf = TF()
    if not tf then
        HideKickTick(bar)
        return
    end
    local tickOn = tf.kickTickEnabled ~= false
    local midOn = tf.midCastEnabled == true
    if (not (tickOn or midOn)) or not GetActiveKickSpell() then
        HideKickTick(bar)
        return
    end
    bar._kickProtected = kickProtected
    bar._kickIsChannel = isChannel
    bar._kickIsEmpowered = isEmpowered
    if
        not (C_Spell and C_Spell.GetSpellCooldownDuration and UnitCastingDuration and bar.sb.SetTimerDuration)
    then
        HideKickTick(bar)
        return
    end
    local castDuration
    if isChannel then
        if isEmpowered and UnitEmpoweredChannelDuration then
            castDuration = UnitEmpoweredChannelDuration(bar.unit, true)
        end
        if not castDuration then
            castDuration = UnitChannelDuration(bar.unit)
        end
    else
        castDuration = UnitCastingDuration(bar.unit)
    end
    if not castDuration then
        HideKickTick(bar)
        return
    end
    local totalDur = castDuration:GetTotalDuration()
    local interruptCD = C_Spell.GetSpellCooldownDuration(GetActiveKickSpell())
    if not interruptCD then
        HideKickTick(bar)
        return
    end

    local hgt = bar.frame:GetHeight()
    local barW = bar.sb:GetWidth()
    bar.kickPositioner:SetSize(barW, hgt)
    bar.kickPositioner:SetMinMaxValues(0, totalDur)
    bar.kickMarker:SetMinMaxValues(0, totalDur)
    bar.kickMarker:SetSize(barW, hgt)
    -- PAIRED snapshot: elapsed + kick CD remaining sampled at one instant.
    bar.kickPositioner:SetValue(castDuration:GetElapsedDuration())
    bar.kickMarker:SetValue(interruptCD:GetRemainingDuration())
    local kc = tf.kickTickColor or { r = 1, g = 1, b = 1 }
    bar.kickTick:SetColorTexture(kc.r, kc.g, kc.b, 1)

    local function Unsnap(sbFrame)
        local tx = sbFrame:GetStatusBarTexture()
        if tx and tx.SetSnapToPixelGrid then
            tx:SetSnapToPixelGrid(false)
            tx:SetTexelSnappingBias(0)
        end
    end
    if isChannel and not isEmpowered then
        bar.kickPositioner:SetFillStyle(Enum.StatusBarFillStyle.Reverse)
        bar.kickMarker:SetFillStyle(Enum.StatusBarFillStyle.Reverse)
        -- SetFillStyle re-mints the fill snap-ON; re-disable so the summed
        -- edge stays an exact float and the tick holds still.
        Unsnap(bar.kickPositioner)
        Unsnap(bar.kickMarker)
        bar.kickMarker:ClearAllPoints()
        bar.kickTick:ClearAllPoints()
        bar.kickMarker:SetPoint("RIGHT", bar.kickPositioner:GetStatusBarTexture(), "LEFT")
        bar.kickTick:SetPoint("TOP", bar.kickMarker, "TOP", 0, 0)
        bar.kickTick:SetPoint("BOTTOM", bar.kickMarker, "BOTTOM", 0, 0)
        bar.kickTick:SetPoint("RIGHT", bar.kickMarker:GetStatusBarTexture(), "LEFT")
        bar.kickReadyFill:ClearAllPoints()
        bar.kickReadyFill:SetPoint("TOP", bar.sb, "TOP", 0, 0)
        bar.kickReadyFill:SetPoint("BOTTOM", bar.sb, "BOTTOM", 0, 0)
        bar.kickReadyFill:SetPoint("LEFT", bar.sb, "LEFT", 0, 0)
        bar.kickReadyFill:SetPoint("RIGHT", bar.kickMarker:GetStatusBarTexture(), "LEFT")
    else
        bar.kickPositioner:SetFillStyle(Enum.StatusBarFillStyle.Standard)
        bar.kickMarker:SetFillStyle(Enum.StatusBarFillStyle.Standard)
        Unsnap(bar.kickPositioner)
        Unsnap(bar.kickMarker)
        bar.kickMarker:ClearAllPoints()
        bar.kickTick:ClearAllPoints()
        bar.kickMarker:SetPoint("LEFT", bar.kickPositioner:GetStatusBarTexture(), "RIGHT")
        bar.kickTick:SetPoint("TOP", bar.kickMarker, "TOP", 0, 0)
        bar.kickTick:SetPoint("BOTTOM", bar.kickMarker, "BOTTOM", 0, 0)
        bar.kickTick:SetPoint("LEFT", bar.kickMarker:GetStatusBarTexture(), "RIGHT")
        bar.kickReadyFill:ClearAllPoints()
        bar.kickReadyFill:SetPoint("TOP", bar.sb, "TOP", 0, 0)
        bar.kickReadyFill:SetPoint("BOTTOM", bar.sb, "BOTTOM", 0, 0)
        bar.kickReadyFill:SetPoint("LEFT", bar.kickMarker:GetStatusBarTexture(), "RIGHT")
        bar.kickReadyFill:SetPoint("RIGHT", bar.sb, "RIGHT", 0, 0)
    end
    bar.kickPositioner:Show()
    bar.kickMarker:Show()
    local mc = tf.midCastColor or { r = 0.318, g = 0.820, b = 0.357 }
    bar.kickReadyFill:SetVertexColor(mc.r, mc.g, mc.b, 1)
    bar.kickTick:SetShown(tickOn)
    bar.kickReadyFill:SetShown(midOn)
    -- Alpha = on-CD x interruptible, both possibly SECRET: chained curves.
    if interruptCD.IsZero and C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean then
        local interruptible = C_CurveUtil.EvaluateColorValueFromBoolean(bar._kickProtected, 0, 1)
        local kickReady = interruptCD:IsZero()
        local alpha = C_CurveUtil.EvaluateColorValueFromBoolean(kickReady, 0, interruptible)
        bar.kickTick:SetAlpha(alpha)
        bar.kickReadyFill:SetAlpha(alpha)
    else
        bar.kickTick:SetAlpha(0)
        bar.kickReadyFill:SetAlpha(0)
    end
    if bar._kickTicker then
        bar._kickTicker:Cancel()
    end
    local myTicker
    myTicker = C_Timer.NewTicker(0.1, function()
        if bar._kickTicker ~= myTicker then
            myTicker:Cancel()
            return
        end
        if not bar.isCasting then
            HideKickTick(bar)
            return
        end
        if not GetActiveKickSpell() then
            HideKickTick(bar)
            return
        end
        local icd = C_Spell.GetSpellCooldownDuration(GetActiveKickSpell())
        if icd and icd.IsZero and C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean then
            local interruptible = C_CurveUtil.EvaluateColorValueFromBoolean(bar._kickProtected, 0, 1)
            local kickReady = icd:IsZero()
            local alpha = C_CurveUtil.EvaluateColorValueFromBoolean(kickReady, 0, interruptible)
            bar.kickTick:SetAlpha(alpha)
            bar.kickReadyFill:SetAlpha(alpha)
        end
    end)
    bar._kickTicker = myTicker
end

-- Light cooldown-event refresh: bar values + alpha only, PAIRED re-pin.
local function RefreshKickTick(bar)
    if not GetActiveKickSpell() or not (C_Spell and C_Spell.GetSpellCooldownDuration) then
        HideKickTick(bar)
        return
    end
    local icd = C_Spell.GetSpellCooldownDuration(GetActiveKickSpell())
    if not icd then
        return
    end -- transient miss: keep current state, no blink
    if not UnitCastingDuration then
        return
    end
    local castDuration
    if bar._kickIsChannel then
        if bar._kickIsEmpowered and UnitEmpoweredChannelDuration then
            castDuration = UnitEmpoweredChannelDuration(bar.unit, true)
        end
        if not castDuration then
            castDuration = UnitChannelDuration(bar.unit)
        end
    else
        castDuration = UnitCastingDuration(bar.unit)
    end
    if not castDuration then
        return
    end
    bar.kickPositioner:SetValue(castDuration:GetElapsedDuration())
    bar.kickMarker:SetValue(icd:GetRemainingDuration())
end

--------------------------------------------------------------------------------
--  Kick watcher: SPELL_UPDATE_COOLDOWN/USABLE + a 0.2s safety ticker, armed
--  only while a cast is live on either bar (the kick coming OFF cooldown does
--  not reliably fire an event naming the spell).
--------------------------------------------------------------------------------
local kickWatcher = CreateFrame("Frame")
kickWatcher:SetScript("OnEvent", function()
    for _, bar in pairs(barList) do
        if bar.isCasting and type(bar._kickProtected) ~= "nil" then
            ApplyCastColor(bar, bar._kickProtected)
            if not bar.kickPositioner:IsShown() then
                UpdateKickTick(bar, bar._kickProtected, bar._kickIsChannel, bar._kickIsEmpowered)
            else
                RefreshKickTick(bar)
            end
        end
    end
end)

local function NotifyCastStarted(bar)
    if bar._timerTick then
        bar._timerTick(true)
    end
    if bar._timerTicker then
        bar._timerTicker.Start()
    end
    activeCastCount = activeCastCount + 1
    if activeCastCount == 1 then
        kickWatcher:RegisterEvent("SPELL_UPDATE_COOLDOWN")
        kickWatcher:RegisterEvent("SPELL_UPDATE_USABLE")
        if GetActiveKickSpell() and not castColorTicker then
            castColorTicker = C_Timer.NewTicker(0.2, function()
                for _, b in pairs(barList) do
                    if b.isCasting and type(b._kickProtected) ~= "nil" then
                        ApplyCastColor(b, b._kickProtected)
                    end
                end
            end)
        end
    end
end

local function NotifyCastEnded()
    activeCastCount = activeCastCount - 1
    if activeCastCount <= 0 then
        activeCastCount = 0
        kickWatcher:UnregisterEvent("SPELL_UPDATE_COOLDOWN")
        kickWatcher:UnregisterEvent("SPELL_UPDATE_USABLE")
        if castColorTicker then
            castColorTicker:Cancel()
            castColorTicker = nil
        end
    end
end

--------------------------------------------------------------------------------
--  Target text (nameplate port: UnitShouldDisplaySpellTargetName gate).
--------------------------------------------------------------------------------
-- StyleBar's 48% name width assumes the target zone is in use; most casts (any
-- self-cast, or a unit with target text off) never populate it, so name stays
-- needlessly capped and clips into "..." with room to spare. Hand that zone back
-- to the name whenever this cast has no target text to show.
local function SizeNameForTarget(bar, hasTarget)
    local conf = BarCfg(bar.which)
    if not conf then
        return
    end
    local wid = conf.width or 260
    local hgt = conf.height or 22
    local reserve = (conf.showTimer ~= false) and ((conf.timerSize or 11) * 2.2) or 0
    local shared = (wid - hgt) * 0.48
    bar.name:SetWidth(hasTarget and shared or math.max(shared, (wid - hgt) - 8 - reserve))
end

-- Per-bar toggle; a bar that never set it inherits the former shared one.
local function ShowsTarget(tf, which)
    local conf = BarCfg(which)
    local val = conf and conf.showTarget
    if val == nil then
        val = tf.showTarget
    end
    return val ~= false
end

local function PaintTarget(bar)
    local tf = TF()
    local fontStr = bar.target
    if not tf or not ShowsTarget(tf, bar.which) then
        fontStr:SetText("")
        fontStr:Hide()
        SizeNameForTarget(bar, false)
        return
    end
    local spellTarget, spellTargetClass
    if UnitShouldDisplaySpellTargetName and UnitShouldDisplaySpellTargetName(bar.unit) then
        local raw = UnitSpellTargetName and UnitSpellTargetName(bar.unit)
        if type(raw) ~= "nil" then
            spellTarget = raw
            spellTargetClass = UnitSpellTargetClass and UnitSpellTargetClass(bar.unit)
        end
    end
    if type(spellTarget) == "nil" then
        fontStr:SetText("")
        fontStr:Hide()
        SizeNameForTarget(bar, false)
        return
    end
    if tf.targetClassColor ~= false and type(spellTargetClass) ~= "nil" and C_ClassColor then
        local col = C_ClassColor.GetClassColor(spellTargetClass)
        if col then
            fontStr:SetTextColor(col:GetRGB())
        else
            fontStr:SetTextColor(1, 1, 1, 1)
        end
    else
        local tc = tf.targetColor
        if tc then
            fontStr:SetTextColor(tc.r, tc.g, tc.b, 1)
        else
            fontStr:SetTextColor(1, 1, 1, 1)
        end
    end
    fontStr:SetText(spellTarget)
    fontStr:Show()
    SizeNameForTarget(bar, true)
end

--------------------------------------------------------------------------------
--  Cast lifecycle (nameplate UpdateCast port, full/fast split)
--------------------------------------------------------------------------------
local function ArmFill(bar, isChannel)
    local scrollBar = bar.sb
    if not (UnitCastingDuration and scrollBar.SetTimerDuration) then
        return false
    end
    local dur, isEmp
    if isChannel then
        if UnitEmpoweredChannelDuration then
            dur = UnitEmpoweredChannelDuration(bar.unit, true)
            if dur then
                isEmp = true
            end
        end
        if not dur then
            dur = UnitChannelDuration(bar.unit)
        end
        if dur then
            scrollBar:SetReverseFill(false)
            local dirn = isEmp and Enum.StatusBarTimerDirection.ElapsedTime
                or Enum.StatusBarTimerDirection.RemainingTime
            scrollBar:SetTimerDuration(dur, nil, dirn)
            bar.durKind = isEmp and "empowered" or "channel"
        end
    else
        dur = UnitCastingDuration(bar.unit)
        if dur then
            scrollBar:SetReverseFill(false)
            scrollBar:SetTimerDuration(dur, nil, Enum.StatusBarTimerDirection.ElapsedTime)
            bar.durKind = "cast"
        end
    end
    return dur ~= nil, isEmp
end

local function TeardownCast(bar)
    if bar.isCasting then
        NotifyCastEnded()
    end
    bar.isCasting = false
    bar._castDirtyFull = nil
    HideKickTick(bar)
    bar.timer:SetText("")
    if not bar._interrupted then
        bar.frame:Hide()
        bar.flash:Hide()
    end
end

local function UpdateCast(bar)
    if previewOn[bar.which] then
        return
    end
    local conf = BarCfg(bar.which)
    if not (conf and conf.enabled == true) then
        TeardownCast(bar)
        bar._interrupted = nil
        bar.frame:Hide()
        return
    end
    if not UnitExists(bar.unit) then
        TeardownCast(bar)
        return
    end
    local name, _, texture, _, _, _, _, kickProtected, castSpellID = UnitCastingInfo(bar.unit)
    local isChannel = false
    local isEmpowered = false
    if type(name) == "nil" then
        name, _, texture, _, _, _, kickProtected, castSpellID = UnitChannelInfo(bar.unit)
        isChannel = true
    end
    if type(name) == "nil" then
        TeardownCast(bar)
        return
    end

    if bar._interrupted then
        bar._interrupted = nil
        bar.flash:Hide()
        if bar._interruptTimer then
            bar._interruptTimer:Cancel()
            bar._interruptTimer = nil
        end
    end

    local isFullSetup = bar._castDirtyFull or not bar.isCasting
    bar._castDirtyFull = nil

    if isFullSetup then
        StyleBar(bar)
        bar.flash:Hide()
        bar.frame:Show()
        -- Icon and name MUST describe the SAME cast; the live texture may be
        -- SECRET (SetTexture accepts it).
        if conf.showIcon ~= false then
            if type(texture) ~= "nil" then
                bar.icon:SetTexture(texture)
            elseif type(castSpellID) ~= "nil" then
                local okInfo, details = pcall(C_Spell.GetSpellInfo, castSpellID)
                if okInfo and type(details) == "table" then
                    bar.icon:SetTexture(details.iconID)
                else
                    bar.icon:SetTexture(nil)
                end
            else
                bar.icon:SetTexture(nil)
            end
        end
        -- PaintTarget first: it sizes bar.name for whether this cast has target
        -- text to share the row with, and SetWidth after SetText does not
        -- reliably re-truncate an already-laid-out FontString.
        PaintTarget(bar)
        if conf.showSpellName ~= false then
            bar.name:SetText(name)
        end
        bar.timer:SetText("")

        if type(kickProtected) == "nil" then
            kickProtected = false
        end
        bar._kickProtected = kickProtected
        -- Important flag may be SECRET: stored raw, fed only to color curves.
        bar._castImportant = false
        if C_Spell and C_Spell.IsSpellImportant then
            local impOK, imp = pcall(C_Spell.IsSpellImportant, castSpellID or 0)
            if impOK then
                bar._castImportant = imp
            end
        end
        ApplyCastColor(bar, kickProtected)
    end

    local armed, isEmp = ArmFill(bar, isChannel)
    isEmpowered = isEmp or false
    if armed and not bar.isCasting then
        NotifyCastStarted(bar)
    end
    if armed then
        bar.isCasting = true
    end

    if isFullSetup then
        bar._kickGeoDirty = nil
        UpdateKickTick(bar, bar._kickProtected, isChannel, isEmpowered)
    elseif bar._kickGeoDirty then
        bar._kickGeoDirty = nil
        UpdateKickTick(bar, bar._kickProtected, bar._kickIsChannel, bar._kickIsEmpowered)
    end
end

-- Mid-cast interruptibility flips: re-read protection once, store, refresh.
local function KickProtectionChanged(bar)
    -- The unit events cover both tokens whenever EITHER bar is enabled, and a
    -- disabled bar can still exist (unlock getFrame builds it), so gate here --
    -- UpdateCast's own gate runs too late for this one.
    local conf = BarCfg(bar.which)
    if not (conf and conf.enabled == true) then
        return
    end
    local kickProtected
    local sName, _, _, _, _, _, _, kp = UnitCastingInfo(bar.unit)
    if type(sName) ~= "nil" then
        kickProtected = kp
    else
        local chName
        chName, _, _, _, _, _, kp = UnitChannelInfo(bar.unit)
        if type(chName) == "nil" then
            return
        end
        kickProtected = kp
    end
    if type(kickProtected) == "nil" then
        kickProtected = false
    end
    bar._kickProtected = kickProtected
    ApplyCastColor(bar, kickProtected)
    RefreshKickTick(bar)
end

local function ShowInterruptedFlash(bar, interrupterGUID)
    local tf = TF()
    if not tf or tf.interruptedFlash == false then
        return
    end
    local conf = BarCfg(bar.which)
    if not (conf and conf.enabled == true) then
        return
    end
    local protected = bar._kickProtected
    if type(interrupterGUID) == "nil" then
        return
    end
    if not ((issecretvalue and issecretvalue(protected)) or not protected) then
        return
    end
    bar._interrupted = true
    bar.flash:Show()
    bar.name:SetText(CludesUI.L("Interrupted") or "Interrupted")
    bar.target:SetText("")
    bar.target:Hide()
    bar.timer:SetText("")
    bar.frame:Show()
    if bar._interruptTimer then
        bar._interruptTimer:Cancel()
    end
    bar._interruptTimer = C_Timer.NewTimer(1.0, function()
        bar._interruptTimer = nil
        bar._interrupted = nil
        bar.flash:Hide()
        if not bar.isCasting then
            bar.frame:Hide()
        end
    end)
end

--------------------------------------------------------------------------------
--  Events: RegisterUnitEvent("...", "target", "focus") -- fires ONLY for
--  those tokens, registered only while a bar is enabled.
--------------------------------------------------------------------------------
local evt = CreateFrame("Frame")

local UNIT_EVENTS = {
    "UNIT_SPELLCAST_START",
    "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_EMPOWER_START",
    "UNIT_SPELLCAST_DELAYED",
    "UNIT_SPELLCAST_CHANNEL_UPDATE",
    "UNIT_SPELLCAST_EMPOWER_UPDATE",
    "UNIT_SPELLCAST_STOP",
    "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_EMPOWER_STOP",
    "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_INTERRUPTIBLE",
    "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
}

evt:SetScript("OnEvent", function(_, event, unitToken, ...)
    if event == "PLAYER_TARGET_CHANGED" then
        local bar = barList.target
        if bar then
            bar._castDirtyFull = true
            bar._interrupted = nil
            bar.flash:Hide()
            UpdateCast(bar)
        end
        return
    end
    if event == "PLAYER_FOCUS_CHANGED" then
        local bar = barList.focus
        if bar then
            bar._castDirtyFull = true
            bar._interrupted = nil
            bar.flash:Hide()
            UpdateCast(bar)
        end
        return
    end
    local bar = barList[unitToken]
    if not bar then
        return
    end
    if previewOn[unitToken] then
        return
    end
    if
        event == "UNIT_SPELLCAST_START"
        or event == "UNIT_SPELLCAST_CHANNEL_START"
        or event == "UNIT_SPELLCAST_EMPOWER_START"
    then
        bar._castDirtyFull = true
        UpdateCast(bar)
    elseif
        event == "UNIT_SPELLCAST_DELAYED"
        or event == "UNIT_SPELLCAST_CHANNEL_UPDATE"
        or event == "UNIT_SPELLCAST_EMPOWER_UPDATE"
    then
        bar._kickGeoDirty = true
        UpdateCast(bar)
    elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_FAILED" then
        UpdateCast(bar)
    elseif event == "UNIT_SPELLCAST_EMPOWER_STOP" then
        -- An interrupted empower carries the interrupter GUID as the 4th arg
        -- after unit (castGUID, spellID, complete, interrupterGUID).
        local _, _, _, interrupterGUID = ...
        if type(interrupterGUID) ~= "nil" then
            TeardownCast(bar)
            if not bar._interrupted then
                ShowInterruptedFlash(bar, interrupterGUID)
            end
        else
            UpdateCast(bar)
        end
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        -- Direct teardown: in restricted execution UnitCastingInfo can return
        -- secret values (not nil) for a stale channel (nameplate lesson).
        -- An interrupted channel carries the interrupter GUID as the 3rd arg
        -- after unit (castGUID, spellID, interrupterGUID); nil on a natural end.
        TeardownCast(bar)
        local _, _, interrupterGUID = ...
        if type(interrupterGUID) ~= "nil" and not bar._interrupted then
            ShowInterruptedFlash(bar, interrupterGUID)
        end
    elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
        local _, _, interrupterGUID = ...
        ShowInterruptedFlash(bar, interrupterGUID)
        UpdateCast(bar)
    elseif event == "UNIT_SPELLCAST_INTERRUPTIBLE" or event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
        KickProtectionChanged(bar)
        UpdateCast(bar)
    end
end)

local function AnyEnabled()
    local t = BarCfg("target")
    local f = BarCfg("focus")
    return (t and t.enabled == true) or (f and f.enabled == true)
end

local function Activate()
    if isActive then
        return
    end
    isActive = true
    for idx = 1, #UNIT_EVENTS do
        evt:RegisterUnitEvent(UNIT_EVENTS[idx], "target", "focus")
    end
    evt:RegisterEvent("PLAYER_TARGET_CHANGED")
    evt:RegisterEvent("PLAYER_FOCUS_CHANGED")
end

local function Deactivate()
    if not isActive then
        return
    end
    isActive = false
    evt:UnregisterAllEvents()
    for _, bar in pairs(barList) do
        TeardownCast(bar)
        bar._interrupted = nil
        bar.frame:Hide()
    end
end

--------------------------------------------------------------------------------
--  Preview: static sample cast (unlock placement and the options header
--  sample). Plain SetValue on a bar with no armed timer -- nothing reads
--  units.
--------------------------------------------------------------------------------
-- The static content alone: icon, texts, colour, fill. Shared by the on-screen
-- preview (the live bar) and the options header sample (a chrome-only bar).
local function PaintSampleCast(bar, which, tf)
    bar.icon:SetTexture(134400)
    bar.name:SetText(which == "target" and "Crushing Blow" or "Dark Mending")
    local tc = tf and tf.targetColor
    if tf and tf.targetClassColor ~= false and C_ClassColor and UnitClassBase then
        -- Class token only: UnitClassBase also returns the class ID, which would
        -- land in GetClassColor's optional tint color argument and be rejected.
        local col = C_ClassColor.GetClassColor((UnitClassBase("player")))
        if col then
            bar.target:SetTextColor(col:GetRGB())
        end
    elseif tc then
        bar.target:SetTextColor(tc.r, tc.g, tc.b, 1)
    end
    if tf and ShowsTarget(tf, which) then
        bar.target:SetText(UnitName("player") or "Target")
        bar.target:Show()
    else
        bar.target:SetText("")
        bar.target:Hide()
    end
    bar.timer:SetText("1.4")
    local base = (tf and tf.castColor) or { r = 0.70, g = 0.40, b = 0.90 }
    bar.sb:GetStatusBarTexture():SetVertexColor(base.r, base.g, base.b)
    bar.overlay:SetAlpha(0)
    bar.flash:Hide()
    bar.sb:SetValue(0.62)
end

local function ShowPreview(which)
    local bar = barList[which] or BuildBar(which)
    StyleBar(bar)
    PaintSampleCast(bar, which, TF())
    ApplyBarPosition(bar)
    bar.frame:Show()
end

--------------------------------------------------------------------------------
--  Options header sample: one chrome-only bar per unit, built ONCE on the
--  header's column host and painted static on every call (no kick machinery,
--  no ticker, no events; a plain SetValue fill). Never a slot in `bars`, so
--  the cast lifecycle and the refresh pass never see it.
--------------------------------------------------------------------------------
local sampleBars = {}

-- Hangs the sample at the host's TOPLEFT and returns its size (width, height
-- in the host's units); nil before the settings exist.
function mod.TFB_PaintSample(host, which)
    local conf = BarCfg(which)
    local tf = TF()
    if not (conf and tf) then
        return nil
    end
    local bar = sampleBars[which]
    if not bar then
        bar = BuildBarChrome(which, host)
        sampleBars[which] = bar
    end
    bar.frame:SetParent(host)
    bar.frame:ClearAllPoints()
    bar.frame:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    StyleBar(bar)
    PaintSampleCast(bar, which, tf)
    bar.frame:Show()
    return conf.width or 260, conf.height or 22
end

function mod.TFB_SetPreview(which, on)
    previewOn[which] = on == true
    if previewOn[which] then
        ShowPreview(which)
    else
        local bar = barList[which]
        if bar then
            bar.frame:Hide()
            bar.sb:SetValue(0)
            if isActive then
                UpdateCast(bar)
            end
        end
    end
end

function mod.TFB_IsPreview(which)
    return previewOn[which] == true
end

--------------------------------------------------------------------------------
--  Refresh: enable/disable + live restyle. Options call this on every write.
--------------------------------------------------------------------------------
function mod.TFB_Refresh()
    local wanted = AnyEnabled()
    if wanted and not isActive then
        Activate()
    elseif not wanted and isActive then
        Deactivate()
        previewOn.target = false
        previewOn.focus = false
    end
    for which in pairs(DEFAULT_POS) do
        local conf = BarCfg(which)
        local enabled = conf and conf.enabled == true
        local bar = barList[which]
        if enabled and not bar then
            bar = BuildBar(which)
        end
        if bar then
            if enabled then
                StyleBar(bar)
                ApplyBarPosition(bar)
                if previewOn[which] then
                    ShowPreview(which)
                elseif isActive then
                    bar._castDirtyFull = true
                    UpdateCast(bar)
                end
            else
                previewOn[which] = false
                TeardownCast(bar)
                bar._interrupted = nil
                bar.frame:Hide()
            end
        end
    end
end

--------------------------------------------------------------------------------
--  Unlock mode: one element per bar; movers hidden while disabled.
--------------------------------------------------------------------------------
local function MakeBarUnlockElement(which, labelText, sequence)
    local MK = CludesUI.MakeUnlockElement
    return MK({
        key = which == "target" and "EMT_TargetCastBar" or "EMT_FocusCastBar",
        label = labelText,
        group = "Mythic+",
        order = sequence,
        -- Sized by the options sliders (no drag-resize handle), but the bar can
        -- size-MATCH another element and be matched TO: the match apply pushes
        -- through setWidth/setHeight into the same cfg keys the sliders write,
        -- so a match survives reloads exactly like a slider value.
        noResize = true,
        allowMatchSource = true,
        isHidden = function()
            local conf = BarCfg(which)
            return not (conf and conf.enabled == true)
        end,
        getFrame = function()
            local bar = barList[which] or BuildBar(which)
            return bar.frame
        end,
        getSize = function()
            local conf = BarCfg(which)
            return (conf and conf.width) or 260, (conf and conf.height) or 22
        end,
        setWidth = function(_, wid)
            local conf = BarCfg(which)
            if not conf then
                return
            end
            conf.width = math.floor(wid + 0.5)
            mod.TFB_Refresh()
        end,
        setHeight = function(_, hgt)
            local conf = BarCfg(which)
            if not conf then
                return
            end
            conf.height = math.floor(hgt + 0.5)
            mod.TFB_Refresh()
        end,
        savePos = function(_, _, _, posX, posY)
            -- Unlock mode hands over CENTER/CENTER coords; on Cancel the frame
            -- still sits at the dragged spot, so never read the live position.
            local conf = BarCfg(which)
            if not (conf and posX and posY) then
                return
            end
            conf.pos = { centerX = posX, centerY = posY }
            if not CludesUI._unlockActive then
                ApplyBarPosition(barList[which])
            end
        end,
        loadPos = function()
            local conf = BarCfg(which)
            local place = conf and conf.pos
            if not (place and place.centerX and place.centerY) then
                return nil
            end
            return { point = "CENTER", relPoint = "CENTER", x = place.centerX, y = place.centerY }
        end,
        clearPos = function()
            local conf = BarCfg(which)
            if conf then
                conf.pos = nil
            end
        end,
        applyPos = function()
            local bar = barList[which]
            if bar then
                ApplyBarPosition(bar)
            end
        end,
    })
end

local function RegisterUnlock()
    if not (CludesUI.RegisterUnlockElements and CludesUI.MakeUnlockElement) then
        return
    end
    CludesUI:RegisterUnlockElements({
        MakeBarUnlockElement("target", "Target Cast Bar", 522),
        MakeBarUnlockElement("focus", "Focus Cast Bar", 523),
    }, "CludesUIMythicTimer")

    if CludesUI.RegisterUnlockModeListener then
        local function Listener(which, key)
            return function(unlockActive)
                local conf = BarCfg(which)
                if not (conf and conf.enabled == true) then
                    return
                end
                mod.TFB_SetPreview(which, unlockActive == true)
                local anchored = CludesUI.IsUnlockAnchored and CludesUI.IsUnlockAnchored(key)
                if not anchored then
                    local bar = barList[which]
                    if bar then
                        ApplyBarPosition(bar)
                    end
                end
            end
        end
        CludesUI:RegisterUnlockModeListener("EMT_TargetCastBar", Listener("target", "EMT_TargetCastBar"))
        CludesUI:RegisterUnlockModeListener("EMT_FocusCastBar", Listener("focus", "EMT_FocusCastBar"))
    end
end

--------------------------------------------------------------------------------
--  Init: called from EMT:OnEnable (before the timer's own enable guard).
--------------------------------------------------------------------------------
function mod.TFB_OnEnable(database)
    saved = database
    if not saved then
        return
    end
    RegisterUnlock()
    mod.TFB_Refresh()
end
