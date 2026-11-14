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
local function SetFSFont(fontStr, dim)
    CludesUI.ApplyModuleFontFamily(fontStr, nil, dim, "mythicTimer")
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
local function ApplyBarPosition(barFrame)
    if not barFrame then
        return
    end
    local conf = BarCfg(barFrame.which)
    local place = conf and conf.pos
    barFrame.frame:ClearAllPoints()
    if place and place.centerX and place.centerY then
        barFrame.frame:SetPoint("CENTER", UIParent, "CENTER", place.centerX, place.centerY)
    else
        local d = DEFAULT_POS[barFrame.which]
        barFrame.frame:SetPoint("CENTER", UIParent, "CENTER", d.x, d.y)
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

    local barFrame = { which = which, unit = unitToken, frame = holderFrame }

    barFrame.bg = holderFrame:CreateTexture(nil, "BACKGROUND")
    barFrame.bg:SetAllPoints(holderFrame)
    barFrame.bg:SetColorTexture(0, 0, 0, 0.45)

    barFrame.iconFrame = CreateFrame("Frame", nil, holderFrame)
    barFrame.iconFrame:SetPoint("TOPLEFT", holderFrame, "TOPLEFT", 0, 0)
    barFrame.iconFrame:SetPoint("BOTTOMLEFT", holderFrame, "BOTTOMLEFT", 0, 0)
    barFrame.icon = barFrame.iconFrame:CreateTexture(nil, "ARTWORK")
    barFrame.icon:SetAllPoints(barFrame.iconFrame)
    barFrame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    barFrame.sb = CreateFrame("StatusBar", nil, holderFrame)
    -- Placeholder fill: a StatusBar has NO texture object until one is set, and
    -- the fill-edge riders below plus every GetStatusBarTexture() call on the
    -- cast path would index nil on a bar that never reached StyleBar.
    barFrame.sb:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    barFrame.sb:SetPoint("TOPLEFT", barFrame.iconFrame, "TOPRIGHT", 0, 0)
    barFrame.sb:SetPoint("BOTTOMRIGHT", holderFrame, "BOTTOMRIGHT", 0, 0)
    barFrame.sb:SetMinMaxValues(0, 1)
    barFrame.sb:SetValue(0)

    -- Uninterruptible grey wash: rides the fill texture, alpha-gated by the
    -- (possibly secret) protection flag via SetAlphaFromBoolean.
    barFrame.overlay = barFrame.sb:CreateTexture(nil, "ARTWORK", nil, 2)
    barFrame.overlay:SetAllPoints(barFrame.sb:GetStatusBarTexture())
    barFrame.overlay:SetTexture("Interface\\Buttons\\WHITE8x8")
    barFrame.overlay:SetAlpha(0)

    -- Interrupted flash: a full-bar wash OVER the fill. Deliberately not a
    -- fill repaint -- an armed SetTimerDuration owns the drawn fill and a
    -- plain SetValue neither repaints nor reliably reclaims it.
    barFrame.flash = barFrame.sb:CreateTexture(nil, "ARTWORK", nil, 3)
    barFrame.flash:SetAllPoints(barFrame.sb)
    barFrame.flash:SetTexture("Interface\\Buttons\\WHITE8x8")
    barFrame.flash:Hide()

    barFrame.spark = barFrame.sb:CreateTexture(nil, "OVERLAY", nil, 1)
    barFrame.spark:SetTexture("Interface\\AddOns\\CludesUI\\media\\cast_spark.tga")
    barFrame.spark:SetBlendMode("ADD")
    barFrame.spark:SetPoint("CENTER", barFrame.sb:GetStatusBarTexture(), "RIGHT", 0, 0)

    barFrame.shieldFrame = CreateFrame("Frame", nil, holderFrame)
    barFrame.shieldFrame:SetPoint("CENTER", holderFrame, "LEFT", 0, 0)
    barFrame.shieldFrame:SetFrameLevel(holderFrame:GetFrameLevel() + 5)
    barFrame.shieldFrame:Hide()
    barFrame.shield = barFrame.shieldFrame:CreateTexture(nil, "OVERLAY")
    barFrame.shield:SetAllPoints()
    barFrame.shield:SetAtlas("nameplates-InterruptShield")

    barFrame.textFrame = CreateFrame("Frame", nil, barFrame.sb)
    barFrame.textFrame:SetAllPoints(barFrame.sb)
    barFrame.textFrame:SetFrameLevel(barFrame.sb:GetFrameLevel() + 6)
    -- Fonts applied at BUILD as well as in StyleBar: a bar can be built on a
    -- disabled path (unlock getFrame, enable round-trip) and its teardown
    -- SetText("") errors on a fontless FontString.
    barFrame.name = barFrame.textFrame:CreateFontString(nil, "OVERLAY")
    barFrame.name:SetJustifyH("LEFT")
    barFrame.name:SetWordWrap(false)
    barFrame.name:SetMaxLines(1)
    SetFSFont(barFrame.name, 11)
    barFrame.target = barFrame.textFrame:CreateFontString(nil, "OVERLAY")
    barFrame.target:SetJustifyH("RIGHT")
    barFrame.target:SetWordWrap(false)
    barFrame.target:SetMaxLines(1)
    SetFSFont(barFrame.target, 10)
    barFrame.timer = barFrame.textFrame:CreateFontString(nil, "OVERLAY")
    barFrame.timer:SetJustifyH("RIGHT")
    barFrame.timer:SetWordWrap(false)
    barFrame.timer:SetMaxLines(1)
    SetFSFont(barFrame.timer, 11)

    return barFrame
end

local function BuildBar(which)
    local barFrame = BuildBarChrome(which, UIParent)

    -- Kick tick machinery, clipped so the tick never renders outside the bar
    -- when the kick CD exceeds the remaining cast.
    barFrame.kickClip = CreateFrame("Frame", nil, barFrame.sb)
    barFrame.kickClip:SetAllPoints(barFrame.sb)
    barFrame.kickClip:SetClipsChildren(true)
    barFrame.kickPositioner = CreateFrame("StatusBar", nil, barFrame.kickClip)
    barFrame.kickPositioner:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    barFrame.kickPositioner:GetStatusBarTexture():SetAlpha(0)
    barFrame.kickPositioner:SetPoint("CENTER", barFrame.sb)
    barFrame.kickPositioner:SetFrameLevel(barFrame.sb:GetFrameLevel() + 1)
    barFrame.kickPositioner:Hide()
    barFrame.kickMarker = CreateFrame("StatusBar", nil, barFrame.kickClip)
    barFrame.kickMarker:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    barFrame.kickMarker:GetStatusBarTexture():SetAlpha(0)
    barFrame.kickMarker:SetPoint("LEFT", barFrame.kickPositioner:GetStatusBarTexture(), "RIGHT")
    barFrame.kickMarker:SetSize(1, 1)
    barFrame.kickMarker:SetFrameLevel(barFrame.sb:GetFrameLevel() + 2)
    barFrame.kickMarker:Hide()
    local function Unsnap(sbFrame)
        local tx = sbFrame:GetStatusBarTexture()
        if tx and tx.SetSnapToPixelGrid then
            tx:SetSnapToPixelGrid(false)
            tx:SetTexelSnappingBias(0)
        end
    end
    Unsnap(barFrame.kickPositioner)
    Unsnap(barFrame.kickMarker)
    barFrame.kickTick = barFrame.kickMarker:CreateTexture(nil, "OVERLAY", nil, 3)
    barFrame.kickTick:SetColorTexture(1, 1, 1, 1)
    barFrame.kickTick:SetWidth(2)
    barFrame.kickTick:SetPoint("TOP", barFrame.kickMarker, "TOP", 0, 0)
    barFrame.kickTick:SetPoint("BOTTOM", barFrame.kickMarker, "BOTTOM", 0, 0)
    barFrame.kickTick:SetPoint("LEFT", barFrame.kickMarker:GetStatusBarTexture(), "RIGHT")
    -- Mid-cast "kick available" window: rides the marker geometry so the
    -- two-secret in-time test resolves by where the marker edge lands (the
    -- anchors cross and the fill collapses to zero width -- no Lua branch).
    barFrame.kickReadyFill = barFrame.sb:CreateTexture(nil, "ARTWORK", nil, 1)
    barFrame.kickReadyFill:SetColorTexture(1, 1, 1, 1)
    barFrame.kickReadyFill:SetAlpha(0)
    barFrame.kickReadyFill:Hide()

    -- 10Hz cast timer text (engine-slept between fires; self-stops when the
    -- cast ends). Remaining time from the duration object only. bar.durKind
    -- (set by ArmFill, which already knows which getter applies) picks the
    -- one matching API instead of probing all three every tick; falls back to
    -- the full chain on a transient miss or before any kind is cached.
    barFrame._timerTick = function(force)
        if not barFrame.isCasting and not force then
            return
        end
        local conf = BarCfg(barFrame.which)
        if not conf or conf.showTimer == false then
            return true
        end
        if UnitCastingDuration then
            local durObj
            local kindOf = barFrame.durKind
            if kindOf == "cast" then
                durObj = UnitCastingDuration(barFrame.unit)
            elseif kindOf == "empowered" then
                durObj = UnitEmpoweredChannelDuration and UnitEmpoweredChannelDuration(barFrame.unit, true)
            elseif kindOf == "channel" then
                durObj = UnitChannelDuration and UnitChannelDuration(barFrame.unit)
            end
            if not durObj then
                durObj = UnitCastingDuration(barFrame.unit)
                    or (UnitEmpoweredChannelDuration and UnitEmpoweredChannelDuration(barFrame.unit, true))
                    or (UnitChannelDuration and UnitChannelDuration(barFrame.unit))
            end
            if durObj then
                barFrame.timer:SetFormattedText("%.1f", durObj:GetRemainingDuration())
            else
                barFrame.timer:SetText("")
            end
        end
        return true
    end
    if CludesUI.Tick and CludesUI.Tick.NewAnimTicker then
        barFrame._timerTicker = CludesUI.Tick.NewAnimTicker(barFrame.frame, barFrame._timerTick, 0.1)
    end

    barList[which] = barFrame
    ApplyBarPosition(barFrame)
    return barFrame
end

--------------------------------------------------------------------------------
--  Style pass
--------------------------------------------------------------------------------
local function StyleBar(barFrame)
    local conf = BarCfg(barFrame.which)
    local tf = TF()
    if not (conf and tf) then
        return
    end
    local wid = conf.width or 260
    local hgt = conf.height or 22
    barFrame.frame:SetSize(wid, hgt)

    local showIcon = conf.showIcon ~= false
    barFrame.iconFrame:SetWidth(showIcon and hgt or 0.001)
    barFrame.iconFrame:SetShown(showIcon)

    local texPath = CludesUI.ResolveTexturePath(
        mod.barTextures,
        conf.texture or "none",
        "Interface\\Buttons\\WHITE8x8"
    ) or "Interface\\Buttons\\WHITE8x8"
    barFrame.sb:SetStatusBarTexture(texPath)
    local pp = CludesUI.PP
    if pp and pp.DisablePixelSnap then
        pp.DisablePixelSnap(barFrame.sb:GetStatusBarTexture())
    end
    -- Fill texture re-mint: re-pin the fill-edge riders.
    barFrame.overlay:ClearAllPoints()
    barFrame.overlay:SetAllPoints(barFrame.sb:GetStatusBarTexture())
    barFrame.spark:ClearAllPoints()
    barFrame.spark:SetPoint("CENTER", barFrame.sb:GetStatusBarTexture(), "RIGHT", 0, 0)
    barFrame.spark:SetSize(8, hgt)
    barFrame.spark:SetShown(tf.showSpark ~= false)

    local un = tf.uninterruptible or { r = 0.45, g = 0.45, b = 0.45 }
    barFrame.overlay:SetVertexColor(un.r, un.g, un.b)

    local fl = tf.interruptedColor or { r = 0.8, g = 0, b = 0 }
    barFrame.flash:SetVertexColor(fl.r, fl.g, fl.b, 0.85)

    local shieldH = hgt * 0.75
    barFrame.shieldFrame:SetSize(shieldH * (29 / 35), shieldH)

    if pp and pp.CreateBorder then
        if not barFrame._border then
            barFrame._border = true
            pp.CreateBorder(barFrame.frame, 0, 0, 0, 1, 1, "OVERLAY", 7)
        end
    end

    SetFSFont(barFrame.name, conf.nameSize or 11)
    SetFSFont(barFrame.target, conf.targetSize or 10)
    SetFSFont(barFrame.timer, conf.timerSize or 11)

    local showTimer = conf.showTimer ~= false
    local reserve = showTimer and ((conf.timerSize or 11) * 2.2) or 0
    barFrame.name:ClearAllPoints()
    barFrame.name:SetPoint("LEFT", barFrame.sb, "LEFT", 4, 0)
    barFrame.name:SetWidth((wid - hgt) * 0.48)
    barFrame.timer:ClearAllPoints()
    barFrame.timer:SetPoint("RIGHT", barFrame.sb, "RIGHT", -3, 0)
    barFrame.target:ClearAllPoints()
    barFrame.target:SetPoint("RIGHT", barFrame.sb, "RIGHT", -3 - reserve, 0)
    barFrame.target:SetWidth((wid - hgt) * 0.40)

    barFrame.name:SetShown(conf.showSpellName ~= false)
    barFrame.timer:SetShown(showTimer)
end

--------------------------------------------------------------------------------
--  Cast color: kick-ready tint over the base (or Important) color. All secret
--  combines ride C_CurveUtil boolean curves; nothing branches on a secret.
--------------------------------------------------------------------------------
local impScratch = {}
local function ApplyCastColor(barFrame, uninterruptible)
    local tf = TF()
    if not tf then
        return
    end
    local kickReadyTint = tf.interruptReady or { r = 0.92, g = 0.35, b = 0.20 }
    local baseTint = tf.castColor or { r = 0.70, g = 0.40, b = 0.90 }
    if tf.importantEnabled and C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean then
        local imp = tf.importantColor or { r = 1, g = 0.2, b = 0.2 }
        local isImp = barFrame._castImportant
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
    barFrame.sb:GetStatusBarTexture():SetVertexColor(cr, cg, cb)
    local showShield = TF().showShield ~= false
    if barFrame.overlay.SetAlphaFromBoolean then
        barFrame.overlay:SetAlphaFromBoolean(uninterruptible)
        if showShield then
            barFrame.shieldFrame:SetAlphaFromBoolean(uninterruptible)
        else
            barFrame.shieldFrame:SetAlpha(0)
        end
    else
        local a = uninterruptible and 1 or 0
        barFrame.overlay:SetAlpha(a)
        barFrame.shieldFrame:SetAlpha(showShield and a or 0)
    end
end

--------------------------------------------------------------------------------
--  Kick tick + mid-cast window (nameplate port). Geometry is cast-identity
--  work; RefreshKickTick re-pins the PAIRED positioner/marker snapshot on
--  cooldown events -- never one without the other (the tick drifts).
--------------------------------------------------------------------------------
local function HideKickTick(barFrame)
    barFrame.kickPositioner:Hide()
    barFrame.kickMarker:Hide()
    barFrame.kickReadyFill:Hide()
    barFrame.kickTick:Hide()
    if barFrame._kickTicker then
        barFrame._kickTicker:Cancel()
        barFrame._kickTicker = nil
    end
end

local function UpdateKickTick(barFrame, kickProtected, isChannel, isEmpowered)
    local tf = TF()
    if not tf then
        HideKickTick(barFrame)
        return
    end
    local tickOn = tf.kickTickEnabled ~= false
    local midOn = tf.midCastEnabled == true
    if (not (tickOn or midOn)) or not GetActiveKickSpell() then
        HideKickTick(barFrame)
        return
    end
    barFrame._kickProtected = kickProtected
    barFrame._kickIsChannel = isChannel
    barFrame._kickIsEmpowered = isEmpowered
    if
        not (
            C_Spell
            and C_Spell.GetSpellCooldownDuration
            and UnitCastingDuration
            and barFrame.sb.SetTimerDuration
        )
    then
        HideKickTick(barFrame)
        return
    end
    local castDuration
    if isChannel then
        if isEmpowered and UnitEmpoweredChannelDuration then
            castDuration = UnitEmpoweredChannelDuration(barFrame.unit, true)
        end
        if not castDuration then
            castDuration = UnitChannelDuration(barFrame.unit)
        end
    else
        castDuration = UnitCastingDuration(barFrame.unit)
    end
    if not castDuration then
        HideKickTick(barFrame)
        return
    end
    local totalDur = castDuration:GetTotalDuration()
    local interruptCD = C_Spell.GetSpellCooldownDuration(GetActiveKickSpell())
    if not interruptCD then
        HideKickTick(barFrame)
        return
    end

    local hgt = barFrame.frame:GetHeight()
    local barW = barFrame.sb:GetWidth()
    barFrame.kickPositioner:SetSize(barW, hgt)
    barFrame.kickPositioner:SetMinMaxValues(0, totalDur)
    barFrame.kickMarker:SetMinMaxValues(0, totalDur)
    barFrame.kickMarker:SetSize(barW, hgt)
    -- PAIRED snapshot: elapsed + kick CD remaining sampled at one instant.
    barFrame.kickPositioner:SetValue(castDuration:GetElapsedDuration())
    barFrame.kickMarker:SetValue(interruptCD:GetRemainingDuration())
    local kc = tf.kickTickColor or { r = 1, g = 1, b = 1 }
    barFrame.kickTick:SetColorTexture(kc.r, kc.g, kc.b, 1)

    local function Unsnap(sbFrame)
        local tx = sbFrame:GetStatusBarTexture()
        if tx and tx.SetSnapToPixelGrid then
            tx:SetSnapToPixelGrid(false)
            tx:SetTexelSnappingBias(0)
        end
    end
    if isChannel and not isEmpowered then
        barFrame.kickPositioner:SetFillStyle(Enum.StatusBarFillStyle.Reverse)
        barFrame.kickMarker:SetFillStyle(Enum.StatusBarFillStyle.Reverse)
        -- SetFillStyle re-mints the fill snap-ON; re-disable so the summed
        -- edge stays an exact float and the tick holds still.
        Unsnap(barFrame.kickPositioner)
        Unsnap(barFrame.kickMarker)
        barFrame.kickMarker:ClearAllPoints()
        barFrame.kickTick:ClearAllPoints()
        barFrame.kickMarker:SetPoint("RIGHT", barFrame.kickPositioner:GetStatusBarTexture(), "LEFT")
        barFrame.kickTick:SetPoint("TOP", barFrame.kickMarker, "TOP", 0, 0)
        barFrame.kickTick:SetPoint("BOTTOM", barFrame.kickMarker, "BOTTOM", 0, 0)
        barFrame.kickTick:SetPoint("RIGHT", barFrame.kickMarker:GetStatusBarTexture(), "LEFT")
        barFrame.kickReadyFill:ClearAllPoints()
        barFrame.kickReadyFill:SetPoint("TOP", barFrame.sb, "TOP", 0, 0)
        barFrame.kickReadyFill:SetPoint("BOTTOM", barFrame.sb, "BOTTOM", 0, 0)
        barFrame.kickReadyFill:SetPoint("LEFT", barFrame.sb, "LEFT", 0, 0)
        barFrame.kickReadyFill:SetPoint("RIGHT", barFrame.kickMarker:GetStatusBarTexture(), "LEFT")
    else
        barFrame.kickPositioner:SetFillStyle(Enum.StatusBarFillStyle.Standard)
        barFrame.kickMarker:SetFillStyle(Enum.StatusBarFillStyle.Standard)
        Unsnap(barFrame.kickPositioner)
        Unsnap(barFrame.kickMarker)
        barFrame.kickMarker:ClearAllPoints()
        barFrame.kickTick:ClearAllPoints()
        barFrame.kickMarker:SetPoint("LEFT", barFrame.kickPositioner:GetStatusBarTexture(), "RIGHT")
        barFrame.kickTick:SetPoint("TOP", barFrame.kickMarker, "TOP", 0, 0)
        barFrame.kickTick:SetPoint("BOTTOM", barFrame.kickMarker, "BOTTOM", 0, 0)
        barFrame.kickTick:SetPoint("LEFT", barFrame.kickMarker:GetStatusBarTexture(), "RIGHT")
        barFrame.kickReadyFill:ClearAllPoints()
        barFrame.kickReadyFill:SetPoint("TOP", barFrame.sb, "TOP", 0, 0)
        barFrame.kickReadyFill:SetPoint("BOTTOM", barFrame.sb, "BOTTOM", 0, 0)
        barFrame.kickReadyFill:SetPoint("LEFT", barFrame.kickMarker:GetStatusBarTexture(), "RIGHT")
        barFrame.kickReadyFill:SetPoint("RIGHT", barFrame.sb, "RIGHT", 0, 0)
    end
    barFrame.kickPositioner:Show()
    barFrame.kickMarker:Show()
    local mc = tf.midCastColor or { r = 0.318, g = 0.820, b = 0.357 }
    barFrame.kickReadyFill:SetVertexColor(mc.r, mc.g, mc.b, 1)
    barFrame.kickTick:SetShown(tickOn)
    barFrame.kickReadyFill:SetShown(midOn)
    -- Alpha = on-CD x interruptible, both possibly SECRET: chained curves.
    if interruptCD.IsZero and C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean then
        local interruptible = C_CurveUtil.EvaluateColorValueFromBoolean(barFrame._kickProtected, 0, 1)
        local kickReady = interruptCD:IsZero()
        local alpha = C_CurveUtil.EvaluateColorValueFromBoolean(kickReady, 0, interruptible)
        barFrame.kickTick:SetAlpha(alpha)
        barFrame.kickReadyFill:SetAlpha(alpha)
    else
        barFrame.kickTick:SetAlpha(0)
        barFrame.kickReadyFill:SetAlpha(0)
    end
    if barFrame._kickTicker then
        barFrame._kickTicker:Cancel()
    end
    local myTicker
    myTicker = C_Timer.NewTicker(0.1, function()
        if barFrame._kickTicker ~= myTicker then
            myTicker:Cancel()
            return
        end
        if not barFrame.isCasting then
            HideKickTick(barFrame)
            return
        end
        if not GetActiveKickSpell() then
            HideKickTick(barFrame)
            return
        end
        local icd = C_Spell.GetSpellCooldownDuration(GetActiveKickSpell())
        if icd and icd.IsZero and C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean then
            local interruptible = C_CurveUtil.EvaluateColorValueFromBoolean(barFrame._kickProtected, 0, 1)
            local kickReady = icd:IsZero()
            local alpha = C_CurveUtil.EvaluateColorValueFromBoolean(kickReady, 0, interruptible)
            barFrame.kickTick:SetAlpha(alpha)
            barFrame.kickReadyFill:SetAlpha(alpha)
        end
    end)
    barFrame._kickTicker = myTicker
end

-- Light cooldown-event refresh: bar values + alpha only, PAIRED re-pin.
local function RefreshKickTick(barFrame)
    if not GetActiveKickSpell() or not (C_Spell and C_Spell.GetSpellCooldownDuration) then
        HideKickTick(barFrame)
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
    if barFrame._kickIsChannel then
        if barFrame._kickIsEmpowered and UnitEmpoweredChannelDuration then
            castDuration = UnitEmpoweredChannelDuration(barFrame.unit, true)
        end
        if not castDuration then
            castDuration = UnitChannelDuration(barFrame.unit)
        end
    else
        castDuration = UnitCastingDuration(barFrame.unit)
    end
    if not castDuration then
        return
    end
    barFrame.kickPositioner:SetValue(castDuration:GetElapsedDuration())
    barFrame.kickMarker:SetValue(icd:GetRemainingDuration())
end

--------------------------------------------------------------------------------
--  Kick watcher: SPELL_UPDATE_COOLDOWN/USABLE + a 0.2s safety ticker, armed
--  only while a cast is live on either bar (the kick coming OFF cooldown does
--  not reliably fire an event naming the spell).
--------------------------------------------------------------------------------
local kickWatcher = CreateFrame("Frame")
kickWatcher:SetScript("OnEvent", function()
    for _, barFrame in pairs(barList) do
        if barFrame.isCasting and type(barFrame._kickProtected) ~= "nil" then
            ApplyCastColor(barFrame, barFrame._kickProtected)
            if not barFrame.kickPositioner:IsShown() then
                UpdateKickTick(
                    barFrame,
                    barFrame._kickProtected,
                    barFrame._kickIsChannel,
                    barFrame._kickIsEmpowered
                )
            else
                RefreshKickTick(barFrame)
            end
        end
    end
end)

local function NotifyCastStarted(barFrame)
    if barFrame._timerTick then
        barFrame._timerTick(true)
    end
    if barFrame._timerTicker then
        barFrame._timerTicker.Start()
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
local function SizeNameForTarget(barFrame, hasTarget)
    local conf = BarCfg(barFrame.which)
    if not conf then
        return
    end
    local wid = conf.width or 260
    local hgt = conf.height or 22
    local reserve = (conf.showTimer ~= false) and ((conf.timerSize or 11) * 2.2) or 0
    local shared = (wid - hgt) * 0.48
    barFrame.name:SetWidth(hasTarget and shared or math.max(shared, (wid - hgt) - 8 - reserve))
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

local function PaintTarget(barFrame)
    local tf = TF()
    local fontStr = barFrame.target
    if not tf or not ShowsTarget(tf, barFrame.which) then
        fontStr:SetText("")
        fontStr:Hide()
        SizeNameForTarget(barFrame, false)
        return
    end
    local spellTarget, spellTargetClass
    if UnitShouldDisplaySpellTargetName and UnitShouldDisplaySpellTargetName(barFrame.unit) then
        local raw = UnitSpellTargetName and UnitSpellTargetName(barFrame.unit)
        if type(raw) ~= "nil" then
            spellTarget = raw
            spellTargetClass = UnitSpellTargetClass and UnitSpellTargetClass(barFrame.unit)
        end
    end
    if type(spellTarget) == "nil" then
        fontStr:SetText("")
        fontStr:Hide()
        SizeNameForTarget(barFrame, false)
        return
    end
    if tf.targetClassColor ~= false and type(spellTargetClass) ~= "nil" and C_ClassColor then
        local column = C_ClassColor.GetClassColor(spellTargetClass)
        if column then
            fontStr:SetTextColor(column:GetRGB())
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
    SizeNameForTarget(barFrame, true)
end

--------------------------------------------------------------------------------
--  Cast lifecycle (nameplate UpdateCast port, full/fast split)
--------------------------------------------------------------------------------
local function ArmFill(barFrame, isChannel)
    local scrollBar = barFrame.sb
    if not (UnitCastingDuration and scrollBar.SetTimerDuration) then
        return false
    end
    local dur, isEmp
    if isChannel then
        if UnitEmpoweredChannelDuration then
            dur = UnitEmpoweredChannelDuration(barFrame.unit, true)
            if dur then
                isEmp = true
            end
        end
        if not dur then
            dur = UnitChannelDuration(barFrame.unit)
        end
        if dur then
            scrollBar:SetReverseFill(false)
            local dirn = isEmp and Enum.StatusBarTimerDirection.ElapsedTime
                or Enum.StatusBarTimerDirection.RemainingTime
            scrollBar:SetTimerDuration(dur, nil, dirn)
            barFrame.durKind = isEmp and "empowered" or "channel"
        end
    else
        dur = UnitCastingDuration(barFrame.unit)
        if dur then
            scrollBar:SetReverseFill(false)
            scrollBar:SetTimerDuration(dur, nil, Enum.StatusBarTimerDirection.ElapsedTime)
            barFrame.durKind = "cast"
        end
    end
    return dur ~= nil, isEmp
end

local function TeardownCast(barFrame)
    if barFrame.isCasting then
        NotifyCastEnded()
    end
    barFrame.isCasting = false
    barFrame._castDirtyFull = nil
    HideKickTick(barFrame)
    barFrame.timer:SetText("")
    if not barFrame._interrupted then
        barFrame.frame:Hide()
        barFrame.flash:Hide()
    end
end

local function UpdateCast(barFrame)
    if previewOn[barFrame.which] then
        return
    end
    local conf = BarCfg(barFrame.which)
    if not (conf and conf.enabled == true) then
        TeardownCast(barFrame)
        barFrame._interrupted = nil
        barFrame.frame:Hide()
        return
    end
    if not UnitExists(barFrame.unit) then
        TeardownCast(barFrame)
        return
    end
    local name, _, texture, _, _, _, _, kickProtected, castSpellID = UnitCastingInfo(barFrame.unit)
    local isChannel = false
    local isEmpowered = false
    if type(name) == "nil" then
        name, _, texture, _, _, _, kickProtected, castSpellID = UnitChannelInfo(barFrame.unit)
        isChannel = true
    end
    if type(name) == "nil" then
        TeardownCast(barFrame)
        return
    end

    if barFrame._interrupted then
        barFrame._interrupted = nil
        barFrame.flash:Hide()
        if barFrame._interruptTimer then
            barFrame._interruptTimer:Cancel()
            barFrame._interruptTimer = nil
        end
    end

    local isFullSetup = barFrame._castDirtyFull or not barFrame.isCasting
    barFrame._castDirtyFull = nil

    if isFullSetup then
        StyleBar(barFrame)
        barFrame.flash:Hide()
        barFrame.frame:Show()
        -- Icon and name MUST describe the SAME cast; the live texture may be
        -- SECRET (SetTexture accepts it).
        if conf.showIcon ~= false then
            if type(texture) ~= "nil" then
                barFrame.icon:SetTexture(texture)
            elseif type(castSpellID) ~= "nil" then
                local okInfo, details = pcall(C_Spell.GetSpellInfo, castSpellID)
                if okInfo and type(details) == "table" then
                    barFrame.icon:SetTexture(details.iconID)
                else
                    barFrame.icon:SetTexture(nil)
                end
            else
                barFrame.icon:SetTexture(nil)
            end
        end
        -- PaintTarget first: it sizes bar.name for whether this cast has target
        -- text to share the row with, and SetWidth after SetText does not
        -- reliably re-truncate an already-laid-out FontString.
        PaintTarget(barFrame)
        if conf.showSpellName ~= false then
            barFrame.name:SetText(name)
        end
        barFrame.timer:SetText("")

        if type(kickProtected) == "nil" then
            kickProtected = false
        end
        barFrame._kickProtected = kickProtected
        -- Important flag may be SECRET: stored raw, fed only to color curves.
        barFrame._castImportant = false
        if C_Spell and C_Spell.IsSpellImportant then
            local impOK, imp = pcall(C_Spell.IsSpellImportant, castSpellID or 0)
            if impOK then
                barFrame._castImportant = imp
            end
        end
        ApplyCastColor(barFrame, kickProtected)
    end

    local armed, isEmp = ArmFill(barFrame, isChannel)
    isEmpowered = isEmp or false
    if armed and not barFrame.isCasting then
        NotifyCastStarted(barFrame)
    end
    if armed then
        barFrame.isCasting = true
    end

    if isFullSetup then
        barFrame._kickGeoDirty = nil
        UpdateKickTick(barFrame, barFrame._kickProtected, isChannel, isEmpowered)
    elseif barFrame._kickGeoDirty then
        barFrame._kickGeoDirty = nil
        UpdateKickTick(barFrame, barFrame._kickProtected, barFrame._kickIsChannel, barFrame._kickIsEmpowered)
    end
end

-- Mid-cast interruptibility flips: re-read protection once, store, refresh.
local function KickProtectionChanged(barFrame)
    -- The unit events cover both tokens whenever EITHER bar is enabled, and a
    -- disabled bar can still exist (unlock getFrame builds it), so gate here --
    -- UpdateCast's own gate runs too late for this one.
    local conf = BarCfg(barFrame.which)
    if not (conf and conf.enabled == true) then
        return
    end
    local kickProtected
    local sName, _, _, _, _, _, _, kp = UnitCastingInfo(barFrame.unit)
    if type(sName) ~= "nil" then
        kickProtected = kp
    else
        local chName
        chName, _, _, _, _, _, kp = UnitChannelInfo(barFrame.unit)
        if type(chName) == "nil" then
            return
        end
        kickProtected = kp
    end
    if type(kickProtected) == "nil" then
        kickProtected = false
    end
    barFrame._kickProtected = kickProtected
    ApplyCastColor(barFrame, kickProtected)
    RefreshKickTick(barFrame)
end

local function ShowInterruptedFlash(barFrame, interrupterGUID)
    local tf = TF()
    if not tf or tf.interruptedFlash == false then
        return
    end
    local conf = BarCfg(barFrame.which)
    if not (conf and conf.enabled == true) then
        return
    end
    local protected = barFrame._kickProtected
    if type(interrupterGUID) == "nil" then
        return
    end
    if not ((issecretvalue and issecretvalue(protected)) or not protected) then
        return
    end
    barFrame._interrupted = true
    barFrame.flash:Show()
    barFrame.name:SetText(CludesUI.L("Interrupted") or "Interrupted")
    barFrame.target:SetText("")
    barFrame.target:Hide()
    barFrame.timer:SetText("")
    barFrame.frame:Show()
    if barFrame._interruptTimer then
        barFrame._interruptTimer:Cancel()
    end
    barFrame._interruptTimer = C_Timer.NewTimer(1.0, function()
        barFrame._interruptTimer = nil
        barFrame._interrupted = nil
        barFrame.flash:Hide()
        if not barFrame.isCasting then
            barFrame.frame:Hide()
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
        local barFrame = barList.target
        if barFrame then
            barFrame._castDirtyFull = true
            barFrame._interrupted = nil
            barFrame.flash:Hide()
            UpdateCast(barFrame)
        end
        return
    end
    if event == "PLAYER_FOCUS_CHANGED" then
        local barFrame = barList.focus
        if barFrame then
            barFrame._castDirtyFull = true
            barFrame._interrupted = nil
            barFrame.flash:Hide()
            UpdateCast(barFrame)
        end
        return
    end
    local barFrame = barList[unitToken]
    if not barFrame then
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
        barFrame._castDirtyFull = true
        UpdateCast(barFrame)
    elseif
        event == "UNIT_SPELLCAST_DELAYED"
        or event == "UNIT_SPELLCAST_CHANNEL_UPDATE"
        or event == "UNIT_SPELLCAST_EMPOWER_UPDATE"
    then
        barFrame._kickGeoDirty = true
        UpdateCast(barFrame)
    elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_FAILED" then
        UpdateCast(barFrame)
    elseif event == "UNIT_SPELLCAST_EMPOWER_STOP" then
        -- An interrupted empower carries the interrupter GUID as the 4th arg
        -- after unit (castGUID, spellID, complete, interrupterGUID).
        local _, _, _, interrupterGUID = ...
        if type(interrupterGUID) ~= "nil" then
            TeardownCast(barFrame)
            if not barFrame._interrupted then
                ShowInterruptedFlash(barFrame, interrupterGUID)
            end
        else
            UpdateCast(barFrame)
        end
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        -- Direct teardown: in restricted execution UnitCastingInfo can return
        -- secret values (not nil) for a stale channel (nameplate lesson).
        -- An interrupted channel carries the interrupter GUID as the 3rd arg
        -- after unit (castGUID, spellID, interrupterGUID); nil on a natural end.
        TeardownCast(barFrame)
        local _, _, interrupterGUID = ...
        if type(interrupterGUID) ~= "nil" and not barFrame._interrupted then
            ShowInterruptedFlash(barFrame, interrupterGUID)
        end
    elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
        local _, _, interrupterGUID = ...
        ShowInterruptedFlash(barFrame, interrupterGUID)
        UpdateCast(barFrame)
    elseif event == "UNIT_SPELLCAST_INTERRUPTIBLE" or event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
        KickProtectionChanged(barFrame)
        UpdateCast(barFrame)
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
    for _, barFrame in pairs(barList) do
        TeardownCast(barFrame)
        barFrame._interrupted = nil
        barFrame.frame:Hide()
    end
end

--------------------------------------------------------------------------------
--  Preview: static sample cast (unlock placement and the options header
--  sample). Plain SetValue on a bar with no armed timer -- nothing reads
--  units.
--------------------------------------------------------------------------------
-- The static content alone: icon, texts, colour, fill. Shared by the on-screen
-- preview (the live bar) and the options header sample (a chrome-only bar).
local function PaintSampleCast(barFrame, which, tf)
    barFrame.icon:SetTexture(134400)
    barFrame.name:SetText(which == "target" and "Crushing Blow" or "Dark Mending")
    local tc = tf and tf.targetColor
    if tf and tf.targetClassColor ~= false and C_ClassColor and UnitClassBase then
        -- Class token only: UnitClassBase also returns the class ID, which would
        -- land in GetClassColor's optional tint color argument and be rejected.
        local column = C_ClassColor.GetClassColor((UnitClassBase("player")))
        if column then
            barFrame.target:SetTextColor(column:GetRGB())
        end
    elseif tc then
        barFrame.target:SetTextColor(tc.r, tc.g, tc.b, 1)
    end
    if tf and ShowsTarget(tf, which) then
        barFrame.target:SetText(UnitName("player") or "Target")
        barFrame.target:Show()
    else
        barFrame.target:SetText("")
        barFrame.target:Hide()
    end
    barFrame.timer:SetText("1.4")
    local baseValue = (tf and tf.castColor) or { r = 0.70, g = 0.40, b = 0.90 }
    barFrame.sb:GetStatusBarTexture():SetVertexColor(baseValue.r, baseValue.g, baseValue.b)
    barFrame.overlay:SetAlpha(0)
    barFrame.flash:Hide()
    barFrame.sb:SetValue(0.62)
end

local function ShowPreview(which)
    local barFrame = barList[which] or BuildBar(which)
    StyleBar(barFrame)
    PaintSampleCast(barFrame, which, TF())
    ApplyBarPosition(barFrame)
    barFrame.frame:Show()
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
function mod.TFB_PaintSample(hostRegion, which)
    local conf = BarCfg(which)
    local tf = TF()
    if not (conf and tf) then
        return nil
    end
    local barFrame = sampleBars[which]
    if not barFrame then
        barFrame = BuildBarChrome(which, hostRegion)
        sampleBars[which] = barFrame
    end
    barFrame.frame:SetParent(hostRegion)
    barFrame.frame:ClearAllPoints()
    barFrame.frame:SetPoint("TOPLEFT", hostRegion, "TOPLEFT", 0, 0)
    StyleBar(barFrame)
    PaintSampleCast(barFrame, which, tf)
    barFrame.frame:Show()
    return conf.width or 260, conf.height or 22
end

function mod.TFB_SetPreview(which, on)
    previewOn[which] = on == true
    if previewOn[which] then
        ShowPreview(which)
    else
        local barFrame = barList[which]
        if barFrame then
            barFrame.frame:Hide()
            barFrame.sb:SetValue(0)
            if isActive then
                UpdateCast(barFrame)
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
        local barFrame = barList[which]
        if enabled and not barFrame then
            barFrame = BuildBar(which)
        end
        if barFrame then
            if enabled then
                StyleBar(barFrame)
                ApplyBarPosition(barFrame)
                if previewOn[which] then
                    ShowPreview(which)
                elseif isActive then
                    barFrame._castDirtyFull = true
                    UpdateCast(barFrame)
                end
            else
                previewOn[which] = false
                TeardownCast(barFrame)
                barFrame._interrupted = nil
                barFrame.frame:Hide()
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
            local barFrame = barList[which] or BuildBar(which)
            return barFrame.frame
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
            local barFrame = barList[which]
            if barFrame then
                ApplyBarPosition(barFrame)
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
                    local barFrame = barList[which]
                    if barFrame then
                        ApplyBarPosition(barFrame)
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
