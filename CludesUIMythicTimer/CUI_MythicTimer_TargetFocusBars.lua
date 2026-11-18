if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
--------------------------------------------------------------------------------
--  CUI_MythicTimer_TargetFocusBars.lua - Target and Focus cast bars.
--
--  Two standalone cast bars (Mythic+ Tools), placed anywhere in unlock mode,
--  with the nameplates' cast colours and effects: the kick-ready tint, the
--  uninterruptible wash and shield, the Important-cast colour, the kick tick
--  and kick-ready window during the cast, and the Interrupted flash.
--
--  Off, they cost nothing: no events, no frames until a bar is enabled. Hidden
--  ("secret") values are never branched on: type() for existence, duration
--  objects straight into SetTimerDuration, colour curves (C_CurveUtil) to mix
--  colours, SetAlphaFromBoolean to show or hide.
--------------------------------------------------------------------------------
local _, mod = ...

local saved -- the module's settings handle, given by mod.TFB_OnEnable

local function Settings()
    local profile = saved and saved.profile
    return profile and profile.tfb
end

local function BarSettings(which)
    local tf = Settings()
    return tf and tf[which]
end

-- Font family, outline and shadow are the module's ("mythicTimer"); only
-- sizes are settings. The target text names a player, so the texts take a
-- font family (Cyrillic, Korean and Chinese names draw).
local function Font(text, size)
    CludesUI.ApplyModuleFontFamily(text, nil, size, "mythicTimer")
end

local WHITE = "Interface\\Buttons\\WHITE8x8"
local KickSpell = CludesUI.GetActiveKickSpell
local KickTint = CludesUI.ComputeCastBarTint

--------------------------------------------------------------------------------
--  State: the two bars, made when first needed (barOf.target / barOf.focus)
--------------------------------------------------------------------------------
local barOf = {}
local listening = false
local castsUp = 0 -- casts showing on either bar (arms the kick watcher)
local tintTicker -- re-tints every 0.2s while any cast is up
local previewOn = { target = false, focus = false }

local DEFAULT_POS = {
    target = { x = 0, y = -240 },
    focus = { x = 0, y = -310 },
}

-- Unlock mode hands over a CENTER offset from UIParent's centre; scale is
-- never divided out anywhere but this SetPoint.
local function Place(barFrame)
    if not barFrame then
        return
    end
    local conf = BarSettings(barFrame.which)
    local position = conf and conf.pos
    barFrame.frame:ClearAllPoints()
    if position and position.centerX and position.centerY then
        barFrame.frame:SetPoint("CENTER", UIParent, "CENTER", position.centerX, position.centerY)
    else
        local skinData = DEFAULT_POS[barFrame.which]
        barFrame.frame:SetPoint("CENTER", UIParent, "CENTER", skinData.x, skinData.y)
    end
end

-- A status bar's fill off the pixel grid (so a summed edge stays exact).
local function Unsnap(statusBar)
    local fillTex = statusBar:GetStatusBarTexture()
    if fillTex and fillTex.SetSnapToPixelGrid then
        fillTex:SetSnapToPixelGrid(false)
        fillTex:SetTexelSnappingBias(0)
    end
end

--------------------------------------------------------------------------------
--  A bar, as the nameplate cast bar: fill, uninterruptible wash, shield,
--  spark, the kick parts (clip, positioner, marker, tick, ready window), three
--  texts and the icon. The visible parts (everything Style and the sample
--  paint touch) have their own builder, so the options header's sample needs
--  none of the kick parts, the timer or a place in barOf.
--------------------------------------------------------------------------------
local function NewBarVisuals(which, owner)
    local holder = CreateFrame("Frame", nil, owner)
    holder:Hide()
    local barFrame = { which = which, unit = which, frame = holder } -- "target" and "focus" are unit tokens

    barFrame.bg = holder:CreateTexture(nil, "BACKGROUND")
    barFrame.bg:SetAllPoints(holder)
    barFrame.bg:SetColorTexture(0, 0, 0, 0.45)

    barFrame.iconFrame = CreateFrame("Frame", nil, holder)
    barFrame.iconFrame:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
    barFrame.iconFrame:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 0, 0)
    barFrame.icon = barFrame.iconFrame:CreateTexture(nil, "ARTWORK")
    barFrame.icon:SetAllPoints(barFrame.iconFrame)
    barFrame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local sb = CreateFrame("StatusBar", nil, holder)
    barFrame.sb = sb
    -- A status bar has no fill texture until one is set, and the parts riding
    -- the fill's edge would index nil before Style ran.
    sb:SetStatusBarTexture(WHITE)
    sb:SetPoint("TOPLEFT", barFrame.iconFrame, "TOPRIGHT", 0, 0)
    sb:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", 0, 0)
    sb:SetMinMaxValues(0, 1)
    sb:SetValue(0)

    -- Uninterruptible wash on the fill, shown by the (maybe hidden) flag.
    barFrame.overlay = sb:CreateTexture(nil, "ARTWORK", nil, 2)
    barFrame.overlay:SetAllPoints(sb:GetStatusBarTexture())
    barFrame.overlay:SetTexture(WHITE)
    barFrame.overlay:SetAlpha(0)

    -- Interrupted flash: a wash over the whole bar, not a repaint of the fill
    -- (a running timer owns the drawn fill, which SetValue does not reclaim).
    barFrame.flash = sb:CreateTexture(nil, "ARTWORK", nil, 3)
    barFrame.flash:SetAllPoints(sb)
    barFrame.flash:SetTexture(WHITE)
    barFrame.flash:Hide()

    barFrame.spark = sb:CreateTexture(nil, "OVERLAY", nil, 1)
    barFrame.spark:SetTexture("Interface\\AddOns\\CludesUI\\media\\cast_spark.tga")
    barFrame.spark:SetBlendMode("ADD")
    barFrame.spark:SetPoint("CENTER", sb:GetStatusBarTexture(), "RIGHT", 0, 0)

    barFrame.shieldFrame = CreateFrame("Frame", nil, holder)
    barFrame.shieldFrame:SetPoint("CENTER", holder, "LEFT", 0, 0)
    barFrame.shieldFrame:SetFrameLevel(holder:GetFrameLevel() + 5)
    barFrame.shieldFrame:Hide()
    barFrame.shield = barFrame.shieldFrame:CreateTexture(nil, "OVERLAY")
    barFrame.shield:SetAllPoints()
    barFrame.shield:SetAtlas("nameplates-InterruptShield")

    barFrame.textFrame = CreateFrame("Frame", nil, sb)
    barFrame.textFrame:SetAllPoints(sb)
    barFrame.textFrame:SetFrameLevel(sb:GetFrameLevel() + 6)
    -- Fonts now as well as in Style: a bar can be made while disabled (unlock
    -- mode asks for its frame) and clearing a fontless text errors.
    local function Text(justify, size)
        local text = barFrame.textFrame:CreateFontString(nil, "OVERLAY")
        text:SetJustifyH(justify)
        text:SetWordWrap(false)
        text:SetMaxLines(1)
        Font(text, size)
        return text
    end
    barFrame.name = Text("LEFT", 11)
    barFrame.target = Text("RIGHT", 10)
    barFrame.timer = Text("RIGHT", 11)
    return barFrame
end

-- The cast's duration object for the timer: the kind ArmFill found first,
-- else whichever answers.
local function CastDuration(barFrame)
    local unit, kind = barFrame.unit, barFrame.durKind
    local skinData
    if kind == "cast" then
        skinData = UnitCastingDuration(unit)
    elseif kind == "empowered" then
        skinData = UnitEmpoweredChannelDuration and UnitEmpoweredChannelDuration(unit, true)
    elseif kind == "channel" then
        skinData = UnitChannelDuration and UnitChannelDuration(unit)
    end
    return skinData
        or UnitCastingDuration(unit)
        or (UnitEmpoweredChannelDuration and UnitEmpoweredChannelDuration(unit, true))
        or (UnitChannelDuration and UnitChannelDuration(unit))
end

local function NewBar(which)
    local barFrame = NewBarVisuals(which, UIParent)
    local sb = barFrame.sb

    -- The kick tick, clipped so it never draws past the bar when the kick's
    -- cooldown outlasts the cast.
    barFrame.kickClip = CreateFrame("Frame", nil, sb)
    barFrame.kickClip:SetAllPoints(sb)
    barFrame.kickClip:SetClipsChildren(true)
    local function Invisible()
        local s = CreateFrame("StatusBar", nil, barFrame.kickClip)
        s:SetStatusBarTexture(WHITE)
        s:GetStatusBarTexture():SetAlpha(0)
        return s
    end
    barFrame.kickPositioner = Invisible()
    barFrame.kickPositioner:SetPoint("CENTER", sb)
    barFrame.kickPositioner:SetFrameLevel(sb:GetFrameLevel() + 1)
    barFrame.kickPositioner:Hide()
    barFrame.kickMarker = Invisible()
    barFrame.kickMarker:SetPoint("LEFT", barFrame.kickPositioner:GetStatusBarTexture(), "RIGHT")
    barFrame.kickMarker:SetSize(1, 1)
    barFrame.kickMarker:SetFrameLevel(sb:GetFrameLevel() + 2)
    barFrame.kickMarker:Hide()
    Unsnap(barFrame.kickPositioner)
    Unsnap(barFrame.kickMarker)
    barFrame.kickTick = barFrame.kickMarker:CreateTexture(nil, "OVERLAY", nil, 3)
    barFrame.kickTick:SetColorTexture(1, 1, 1, 1)
    barFrame.kickTick:SetWidth(2)
    barFrame.kickTick:SetPoint("TOP", barFrame.kickMarker, "TOP", 0, 0)
    barFrame.kickTick:SetPoint("BOTTOM", barFrame.kickMarker, "BOTTOM", 0, 0)
    barFrame.kickTick:SetPoint("LEFT", barFrame.kickMarker:GetStatusBarTexture(), "RIGHT")
    -- The kick-ready window: hung from the marker, so the test "is the kick
    -- back in time" (two hidden numbers) is answered by where the marker's
    -- edge lands; the anchors cross and the fill shrinks to nothing.
    barFrame.kickReadyFill = sb:CreateTexture(nil, "ARTWORK", nil, 1)
    barFrame.kickReadyFill:SetColorTexture(1, 1, 1, 1)
    barFrame.kickReadyFill:SetAlpha(0)
    barFrame.kickReadyFill:Hide()

    -- The cast's seconds at 10 Hz (the engine sleeps it between ticks; it
    -- stops itself when the cast ends), from the duration object alone.
    barFrame._timerTick = function(force)
        if not barFrame.isCasting and not force then
            return
        end
        local conf = BarSettings(barFrame.which)
        if not conf or conf.showTimer == false then
            return true
        end
        if UnitCastingDuration then
            local skinData = CastDuration(barFrame)
            if skinData then
                barFrame.timer:SetFormattedText("%.1f", skinData:GetRemainingDuration())
            else
                barFrame.timer:SetText("")
            end
        end
        return true
    end
    if CludesUI.Tick and CludesUI.Tick.NewAnimTicker then
        barFrame._timerTicker = CludesUI.Tick.NewAnimTicker(barFrame.frame, barFrame._timerTick, 0.1)
    end

    barOf[which] = barFrame
    Place(barFrame)
    return barFrame
end

--------------------------------------------------------------------------------
--  Style
--------------------------------------------------------------------------------
local function Style(barFrame)
    local conf, tf = BarSettings(barFrame.which), Settings()
    if not (conf and tf) then
        return
    end
    local width, height = conf.width or 260, conf.height or 22
    barFrame.frame:SetSize(width, height)

    local withIcon = conf.showIcon ~= false
    barFrame.iconFrame:SetWidth(withIcon and height or 0.001)
    barFrame.iconFrame:SetShown(withIcon)

    local sb = barFrame.sb
    sb:SetStatusBarTexture(
        CludesUI.ResolveTexturePath(mod.barTextures, conf.texture or "none", WHITE) or WHITE
    )
    local PP = CludesUI.PP
    if PP and PP.DisablePixelSnap then
        PP.DisablePixelSnap(sb:GetStatusBarTexture())
    end
    -- A new fill texture: the parts riding its edge are pinned again.
    barFrame.overlay:ClearAllPoints()
    barFrame.overlay:SetAllPoints(sb:GetStatusBarTexture())
    barFrame.spark:ClearAllPoints()
    barFrame.spark:SetPoint("CENTER", sb:GetStatusBarTexture(), "RIGHT", 0, 0)
    barFrame.spark:SetSize(8, height)
    barFrame.spark:SetShown(tf.showSpark ~= false)

    local wash = tf.uninterruptible or { r = 0.45, g = 0.45, b = 0.45 }
    barFrame.overlay:SetVertexColor(wash.r, wash.g, wash.b)
    local flash = tf.interruptedColor or { r = 0.8, g = 0, b = 0 }
    barFrame.flash:SetVertexColor(flash.r, flash.g, flash.b, 0.85)

    local shieldH = height * 0.75
    barFrame.shieldFrame:SetSize(shieldH * (29 / 35), shieldH)

    if PP and PP.CreateBorder and not barFrame._border then
        barFrame._border = true
        PP.CreateBorder(barFrame.frame, 0, 0, 0, 1, 1, "OVERLAY", 7)
    end

    local timerSize = conf.timerSize or 11
    Font(barFrame.name, conf.nameSize or 11)
    Font(barFrame.target, conf.targetSize or 10)
    Font(barFrame.timer, timerSize)

    local withTimer = conf.showTimer ~= false
    local timerRoom = withTimer and timerSize * 2.2 or 0
    barFrame.name:ClearAllPoints()
    barFrame.name:SetPoint("LEFT", sb, "LEFT", 4, 0)
    barFrame.name:SetWidth((width - height) * 0.48)
    barFrame.timer:ClearAllPoints()
    barFrame.timer:SetPoint("RIGHT", sb, "RIGHT", -3, 0)
    barFrame.target:ClearAllPoints()
    barFrame.target:SetPoint("RIGHT", sb, "RIGHT", -3 - timerRoom, 0)
    barFrame.target:SetWidth((width - height) * 0.40)

    barFrame.name:SetShown(conf.showSpellName ~= false)
    barFrame.timer:SetShown(withTimer)
end

--------------------------------------------------------------------------------
--  Colour: the kick-ready tint over the base (or Important) colour, mixed by
--  colour curves; nothing branches on a hidden value.
--------------------------------------------------------------------------------
local mixed = {} -- reused: the Important / base mix
local function Paint(barFrame, uninterruptible)
    local tf = Settings()
    if not tf then
        return
    end
    local ready = tf.interruptReady or { r = 0.92, g = 0.35, b = 0.20 }
    local base = tf.castColor or { r = 0.70, g = 0.40, b = 0.90 }
    if tf.importantEnabled and C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean then
        local important = tf.importantColor or { r = 1, g = 0.2, b = 0.2 }
        local isImportant = barFrame._castImportant
        if type(isImportant) == "nil" then
            isImportant = false
        end
        local Mix = C_CurveUtil.EvaluateColorValueFromBoolean
        mixed.r = Mix(isImportant, important.r, base.r)
        mixed.g = Mix(isImportant, important.g, base.g)
        mixed.b = Mix(isImportant, important.b, base.b)
        base = mixed
    end
    barFrame.sb:GetStatusBarTexture():SetVertexColor(KickTint(ready, base))
    local withShield = tf.showShield ~= false
    if barFrame.overlay.SetAlphaFromBoolean then
        barFrame.overlay:SetAlphaFromBoolean(uninterruptible)
        if withShield then
            barFrame.shieldFrame:SetAlphaFromBoolean(uninterruptible)
        else
            barFrame.shieldFrame:SetAlpha(0)
        end
    else
        local alpha = uninterruptible and 1 or 0
        barFrame.overlay:SetAlpha(alpha)
        barFrame.shieldFrame:SetAlpha(withShield and alpha or 0)
    end
end

--------------------------------------------------------------------------------
--  The kick tick and kick-ready window (as on the nameplates). Their layout
--  belongs to the cast; RefreshKick pins the positioner and marker again on
--  cooldown events, always both together (one alone makes the tick drift).
--------------------------------------------------------------------------------
local function HideKick(barFrame)
    barFrame.kickPositioner:Hide()
    barFrame.kickMarker:Hide()
    barFrame.kickReadyFill:Hide()
    barFrame.kickTick:Hide()
    if barFrame._kickTicker then
        barFrame._kickTicker:Cancel()
        barFrame._kickTicker = nil
    end
end

-- The cast's duration for the kick parts: the channel's (or empowered
-- channel's), or the cast's.
local function KickCastDuration(barFrame, isChannel, isEmpowered)
    if not isChannel then
        return UnitCastingDuration(barFrame.unit)
    end
    local skinData = isEmpowered and UnitEmpoweredChannelDuration and UnitEmpoweredChannelDuration(barFrame.unit, true)
    return skinData or UnitChannelDuration(barFrame.unit)
end

-- Tick and window alpha: shown while the kick cools and the cast can be
-- kicked, both maybe hidden, so mixed by curves.
local function KickAlpha(barFrame, cooldown)
    if cooldown and cooldown.IsZero and C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean then
        local Mix = C_CurveUtil.EvaluateColorValueFromBoolean
        local kickable = Mix(barFrame._kickProtected, 0, 1)
        local alpha = Mix(cooldown:IsZero(), 0, kickable)
        barFrame.kickTick:SetAlpha(alpha)
        barFrame.kickReadyFill:SetAlpha(alpha)
        return true
    end
end

local function UpdateKick(barFrame, kickProtected, isChannel, isEmpowered)
    local tf = Settings()
    if not tf then
        HideKick(barFrame)
        return
    end
    local tickOn, windowOn = tf.kickTickEnabled ~= false, tf.midCastEnabled == true
    if not (tickOn or windowOn) or not KickSpell() then
        HideKick(barFrame)
        return
    end
    barFrame._kickProtected, barFrame._kickIsChannel, barFrame._kickIsEmpowered = kickProtected, isChannel, isEmpowered
    if
        not (C_Spell and C_Spell.GetSpellCooldownDuration and UnitCastingDuration and barFrame.sb.SetTimerDuration)
    then
        HideKick(barFrame)
        return
    end
    local cast = KickCastDuration(barFrame, isChannel, isEmpowered)
    if not cast then
        HideKick(barFrame)
        return
    end
    local total = cast:GetTotalDuration()
    local cooldown = C_Spell.GetSpellCooldownDuration(KickSpell())
    if not cooldown then
        HideKick(barFrame)
        return
    end

    local positioner, marker, tick, window, sb =
        barFrame.kickPositioner, barFrame.kickMarker, barFrame.kickTick, barFrame.kickReadyFill, barFrame.sb
    local height, width = barFrame.frame:GetHeight(), sb:GetWidth()
    positioner:SetSize(width, height)
    positioner:SetMinMaxValues(0, total)
    marker:SetMinMaxValues(0, total)
    marker:SetSize(width, height)
    -- Both read at one instant: elapsed, and the kick's cooldown left.
    positioner:SetValue(cast:GetElapsedDuration())
    marker:SetValue(cooldown:GetRemainingDuration())
    local tc = tf.kickTickColor or { r = 1, g = 1, b = 1 }
    tick:SetColorTexture(tc.r, tc.g, tc.b, 1)

    -- A channel drains right to left, so the parts run the other way.
    local reverse = isChannel and not isEmpowered
    local style = reverse and Enum.StatusBarFillStyle.Reverse or Enum.StatusBarFillStyle.Standard
    positioner:SetFillStyle(style)
    marker:SetFillStyle(style)
    -- SetFillStyle makes a new, snapped fill: off the grid again so the tick
    -- holds still.
    Unsnap(positioner)
    Unsnap(marker)
    marker:ClearAllPoints()
    tick:ClearAllPoints()
    window:ClearAllPoints()
    local near, far = reverse and "RIGHT" or "LEFT", reverse and "LEFT" or "RIGHT"
    marker:SetPoint(near, positioner:GetStatusBarTexture(), far)
    tick:SetPoint("TOP", marker, "TOP", 0, 0)
    tick:SetPoint("BOTTOM", marker, "BOTTOM", 0, 0)
    tick:SetPoint(near, marker:GetStatusBarTexture(), far)
    window:SetPoint("TOP", sb, "TOP", 0, 0)
    window:SetPoint("BOTTOM", sb, "BOTTOM", 0, 0)
    if reverse then
        window:SetPoint("LEFT", sb, "LEFT", 0, 0)
        window:SetPoint("RIGHT", marker:GetStatusBarTexture(), "LEFT")
    else
        window:SetPoint("LEFT", marker:GetStatusBarTexture(), "RIGHT")
        window:SetPoint("RIGHT", sb, "RIGHT", 0, 0)
    end
    positioner:Show()
    marker:Show()
    local wc = tf.midCastColor or { r = 0.318, g = 0.820, b = 0.357 }
    window:SetVertexColor(wc.r, wc.g, wc.b, 1)
    tick:SetShown(tickOn)
    window:SetShown(windowOn)
    if not KickAlpha(barFrame, cooldown) then
        tick:SetAlpha(0)
        window:SetAlpha(0)
    end
    if barFrame._kickTicker then
        barFrame._kickTicker:Cancel()
    end
    local mine
    mine = C_Timer.NewTicker(0.1, function()
        if barFrame._kickTicker ~= mine then
            mine:Cancel()
        elseif not barFrame.isCasting or not KickSpell() then
            HideKick(barFrame)
        else
            KickAlpha(barFrame, C_Spell.GetSpellCooldownDuration(KickSpell()))
        end
    end)
    barFrame._kickTicker = mine
end

-- After a cooldown event: just the two values, pinned together.
local function RefreshKick(barFrame)
    if not KickSpell() or not (C_Spell and C_Spell.GetSpellCooldownDuration) then
        HideKick(barFrame)
        return
    end
    local cooldown = C_Spell.GetSpellCooldownDuration(KickSpell())
    if not cooldown or not UnitCastingDuration then
        return -- a momentary miss: keep what is shown rather than blink
    end
    local cast = KickCastDuration(barFrame, barFrame._kickIsChannel, barFrame._kickIsEmpowered)
    if cast then
        barFrame.kickPositioner:SetValue(cast:GetElapsedDuration())
        barFrame.kickMarker:SetValue(cooldown:GetRemainingDuration())
    end
end

--------------------------------------------------------------------------------
--  The kick watcher: cooldown events and a 0.2s re-tint, only while a cast is
--  up on either bar (the kick coming back does not always send an event that
--  names the spell).
--------------------------------------------------------------------------------
local kickWatcher = CreateFrame("Frame")
kickWatcher:SetScript("OnEvent", function()
    for _, barFrame in pairs(barOf) do
        if barFrame.isCasting and type(barFrame._kickProtected) ~= "nil" then
            Paint(barFrame, barFrame._kickProtected)
            if barFrame.kickPositioner:IsShown() then
                RefreshKick(barFrame)
            else
                UpdateKick(barFrame, barFrame._kickProtected, barFrame._kickIsChannel, barFrame._kickIsEmpowered)
            end
        end
    end
end)

local function CastStarted(barFrame)
    if barFrame._timerTick then
        barFrame._timerTick(true)
    end
    if barFrame._timerTicker then
        barFrame._timerTicker.Start()
    end
    castsUp = castsUp + 1
    if castsUp == 1 then
        kickWatcher:RegisterEvent("SPELL_UPDATE_COOLDOWN")
        kickWatcher:RegisterEvent("SPELL_UPDATE_USABLE")
        if KickSpell() and not tintTicker then
            tintTicker = C_Timer.NewTicker(0.2, function()
                for _, b in pairs(barOf) do
                    if b.isCasting and type(b._kickProtected) ~= "nil" then
                        Paint(b, b._kickProtected)
                    end
                end
            end)
        end
    end
end

local function CastEnded()
    castsUp = castsUp - 1
    if castsUp <= 0 then
        castsUp = 0
        kickWatcher:UnregisterEvent("SPELL_UPDATE_COOLDOWN")
        kickWatcher:UnregisterEvent("SPELL_UPDATE_USABLE")
        if tintTicker then
            tintTicker:Cancel()
            tintTicker = nil
        end
    end
end

--------------------------------------------------------------------------------
--  The spell's target (shown only where the game says to show it)
--------------------------------------------------------------------------------
-- Style gives the name 48% of the room, assuming a target text beside it;
-- most casts have none (self-casts, or the text off), so the name then takes
-- that room back instead of cutting off early.
local function NameWidth(barFrame, withTarget)
    local conf = BarSettings(barFrame.which)
    if not conf then
        return
    end
    local width, height = conf.width or 260, conf.height or 22
    local timerRoom = (conf.showTimer ~= false) and ((conf.timerSize or 11) * 2.2) or 0
    local shared = (width - height) * 0.48
    barFrame.name:SetWidth(withTarget and shared or math.max(shared, (width - height) - 8 - timerRoom))
end

-- Per bar; a bar that never set it follows the older shared setting.
local function ShowsTarget(tf, which)
    local conf = BarSettings(which)
    local on = conf and conf.showTarget
    if on == nil then
        on = tf.showTarget
    end
    return on ~= false
end

local function PaintTarget(barFrame)
    local tf = Settings()
    local text = barFrame.target
    local who, class
    if
        tf
        and ShowsTarget(tf, barFrame.which)
        and UnitShouldDisplaySpellTargetName
        and UnitShouldDisplaySpellTargetName(barFrame.unit)
    then
        local name = UnitSpellTargetName and UnitSpellTargetName(barFrame.unit)
        if type(name) ~= "nil" then
            who = name
            class = UnitSpellTargetClass and UnitSpellTargetClass(barFrame.unit)
        end
    end
    if type(who) == "nil" then
        text:SetText("")
        text:Hide()
        NameWidth(barFrame, false)
        return
    end
    local color = tf.targetClassColor ~= false
        and type(class) ~= "nil"
        and C_ClassColor
        and C_ClassColor.GetClassColor(class)
    if color then
        text:SetTextColor(color:GetRGB())
    elseif tf.targetClassColor ~= false and type(class) ~= "nil" and C_ClassColor then
        text:SetTextColor(1, 1, 1, 1)
    else
        local tc = tf.targetColor
        if tc then
            text:SetTextColor(tc.r, tc.g, tc.b, 1)
        else
            text:SetTextColor(1, 1, 1, 1)
        end
    end
    text:SetText(who)
    text:Show()
    NameWidth(barFrame, true)
end

--------------------------------------------------------------------------------
--  A cast's life (as the nameplates': a full setup, or just the timing)
--------------------------------------------------------------------------------
-- Starts the fill's timer; returns whether there is a cast, and if it is empowered.
local function ArmFill(barFrame, isChannel)
    local sb = barFrame.sb
    if not (UnitCastingDuration and sb.SetTimerDuration) then
        return false
    end
    local skinData, empowered
    if isChannel then
        if UnitEmpoweredChannelDuration then
            skinData = UnitEmpoweredChannelDuration(barFrame.unit, true)
            empowered = skinData and true or nil
        end
        skinData = skinData or UnitChannelDuration(barFrame.unit)
        if skinData then
            sb:SetReverseFill(false)
            local direction = empowered and Enum.StatusBarTimerDirection.ElapsedTime
                or Enum.StatusBarTimerDirection.RemainingTime
            sb:SetTimerDuration(skinData, nil, direction)
            barFrame.durKind = empowered and "empowered" or "channel"
        end
    else
        skinData = UnitCastingDuration(barFrame.unit)
        if skinData then
            sb:SetReverseFill(false)
            sb:SetTimerDuration(skinData, nil, Enum.StatusBarTimerDirection.ElapsedTime)
            barFrame.durKind = "cast"
        end
    end
    return skinData ~= nil, empowered
end

local function EndCast(barFrame)
    if barFrame.isCasting then
        CastEnded()
    end
    barFrame.isCasting = false
    barFrame._castDirtyFull = nil
    HideKick(barFrame)
    barFrame.timer:SetText("")
    if not barFrame._interrupted then
        barFrame.frame:Hide()
        barFrame.flash:Hide()
    end
end

-- The cast's icon: its own texture (maybe hidden; SetTexture takes it), else
-- the spell's icon. Icon and name always describe the same cast.
local function PaintIcon(barFrame, texture, spellID)
    if type(texture) ~= "nil" then
        barFrame.icon:SetTexture(texture)
    elseif type(spellID) ~= "nil" then
        local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
        barFrame.icon:SetTexture(ok and type(info) == "table" and info.iconID or nil)
    else
        barFrame.icon:SetTexture(nil)
    end
end

local function UpdateCast(barFrame)
    if previewOn[barFrame.which] then
        return
    end
    local conf = BarSettings(barFrame.which)
    if not (conf and conf.enabled == true) then
        EndCast(barFrame)
        barFrame._interrupted = nil
        barFrame.frame:Hide()
        return
    end
    if not UnitExists(barFrame.unit) then
        EndCast(barFrame)
        return
    end
    local name, _, texture, _, _, _, _, kickProtected, spellID = UnitCastingInfo(barFrame.unit)
    local isChannel = false
    if type(name) == "nil" then
        name, _, texture, _, _, _, kickProtected, spellID = UnitChannelInfo(barFrame.unit)
        isChannel = true
    end
    if type(name) == "nil" then
        EndCast(barFrame)
        return
    end

    -- A new cast ends an Interrupted flash still showing.
    if barFrame._interrupted then
        barFrame._interrupted = nil
        barFrame.flash:Hide()
        if barFrame._interruptTimer then
            barFrame._interruptTimer:Cancel()
            barFrame._interruptTimer = nil
        end
    end

    local full = barFrame._castDirtyFull or not barFrame.isCasting
    barFrame._castDirtyFull = nil
    if full then
        Style(barFrame)
        barFrame.flash:Hide()
        barFrame.frame:Show()
        if conf.showIcon ~= false then
            PaintIcon(barFrame, texture, spellID)
        end
        -- The target first: it sizes the name for whether a target text
        -- shares the row, and a width set after the text does not always cut
        -- an already laid-out string again.
        PaintTarget(barFrame)
        if conf.showSpellName ~= false then
            barFrame.name:SetText(name)
        end
        barFrame.timer:SetText("")
        if type(kickProtected) == "nil" then
            kickProtected = false
        end
        barFrame._kickProtected = kickProtected
        -- The Important flag may be hidden: kept as is, only fed to the curves.
        barFrame._castImportant = false
        if C_Spell and C_Spell.IsSpellImportant then
            local ok, important = pcall(C_Spell.IsSpellImportant, spellID or 0)
            if ok then
                barFrame._castImportant = important
            end
        end
        Paint(barFrame, kickProtected)
    end

    local armed, empowered = ArmFill(barFrame, isChannel)
    if armed then
        if not barFrame.isCasting then
            CastStarted(barFrame)
        end
        barFrame.isCasting = true
    end

    if full then
        barFrame._kickGeoDirty = nil
        UpdateKick(barFrame, barFrame._kickProtected, isChannel, empowered or false)
    elseif barFrame._kickGeoDirty then
        barFrame._kickGeoDirty = nil
        UpdateKick(barFrame, barFrame._kickProtected, barFrame._kickIsChannel, barFrame._kickIsEmpowered)
    end
end

-- The cast became kickable or not: read its protection once, repaint.
local function ProtectionChanged(barFrame)
    -- The unit events cover both units while either bar is on, and an off bar
    -- can still exist (unlock mode makes it), so the check is here.
    local conf = BarSettings(barFrame.which)
    if not (conf and conf.enabled == true) then
        return
    end
    local name, _, _, _, _, _, _, protected = UnitCastingInfo(barFrame.unit)
    if type(name) == "nil" then
        name, _, _, _, _, _, protected = UnitChannelInfo(barFrame.unit)
        if type(name) == "nil" then
            return
        end
    end
    if type(protected) == "nil" then
        protected = false
    end
    barFrame._kickProtected = protected
    Paint(barFrame, protected)
    RefreshKick(barFrame)
end

-- The Interrupted flash: only for a cast that could be kicked (or whose
-- protection is hidden) and only with an interrupter named.
local function Interrupted(barFrame, interrupter)
    local tf = Settings()
    if not tf or tf.interruptedFlash == false then
        return
    end
    local conf = BarSettings(barFrame.which)
    if not (conf and conf.enabled == true) or type(interrupter) == "nil" then
        return
    end
    local protected = barFrame._kickProtected
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
--  Events: the unit events for "target" and "focus" only, and only while a
--  bar is on.
--------------------------------------------------------------------------------
local listener = CreateFrame("Frame")

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
local STARTS = {
    UNIT_SPELLCAST_START = true,
    UNIT_SPELLCAST_CHANNEL_START = true,
    UNIT_SPELLCAST_EMPOWER_START = true,
}
local RETIMED = {
    UNIT_SPELLCAST_DELAYED = true,
    UNIT_SPELLCAST_CHANNEL_UPDATE = true,
    UNIT_SPELLCAST_EMPOWER_UPDATE = true,
}
local CHANGED_UNIT = { PLAYER_TARGET_CHANGED = "target", PLAYER_FOCUS_CHANGED = "focus" }

listener:SetScript("OnEvent", function(_, event, unit, ...)
    local changed = CHANGED_UNIT[event]
    if changed then
        local barFrame = barOf[changed]
        if barFrame then
            barFrame._castDirtyFull = true
            barFrame._interrupted = nil
            barFrame.flash:Hide()
            UpdateCast(barFrame)
        end
        return
    end
    local barFrame = barOf[unit]
    if not barFrame or previewOn[unit] then
        return
    end
    if STARTS[event] then
        barFrame._castDirtyFull = true
        UpdateCast(barFrame)
    elseif RETIMED[event] then
        barFrame._kickGeoDirty = true
        UpdateCast(barFrame)
    elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_FAILED" then
        UpdateCast(barFrame)
    elseif event == "UNIT_SPELLCAST_EMPOWER_STOP" then
        -- An interrupted empower names the interrupter 4th after the unit
        -- (castGUID, spellID, complete, interrupter).
        local _, _, _, interrupter = ...
        if type(interrupter) ~= "nil" then
            EndCast(barFrame)
            if not barFrame._interrupted then
                Interrupted(barFrame, interrupter)
            end
        else
            UpdateCast(barFrame)
        end
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        -- Ended at once: in restricted combat UnitCastingInfo can answer with
        -- hidden values (not nil) for a finished channel. An interrupted
        -- channel names the interrupter 3rd after the unit (castGUID, spellID,
        -- interrupter); nil on a natural end.
        EndCast(barFrame)
        local _, _, interrupter = ...
        if type(interrupter) ~= "nil" and not barFrame._interrupted then
            Interrupted(barFrame, interrupter)
        end
    elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
        local _, _, interrupter = ...
        Interrupted(barFrame, interrupter)
        UpdateCast(barFrame)
    elseif event == "UNIT_SPELLCAST_INTERRUPTIBLE" or event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
        ProtectionChanged(barFrame)
        UpdateCast(barFrame)
    end
end)

local function AnyOn()
    local t, frame = BarSettings("target"), BarSettings("focus")
    return (t and t.enabled == true) or (frame and frame.enabled == true)
end

local function Listen()
    if listening then
        return
    end
    listening = true
    for _, event in ipairs(UNIT_EVENTS) do
        listener:RegisterUnitEvent(event, "target", "focus")
    end
    listener:RegisterEvent("PLAYER_TARGET_CHANGED")
    listener:RegisterEvent("PLAYER_FOCUS_CHANGED")
end

local function StopListening()
    if not listening then
        return
    end
    listening = false
    listener:UnregisterAllEvents()
    for _, barFrame in pairs(barOf) do
        EndCast(barFrame)
        barFrame._interrupted = nil
        barFrame.frame:Hide()
    end
end

--------------------------------------------------------------------------------
--  The sample cast (unlock mode's preview and the options header): a still,
--  a plain SetValue with no timer; no unit is read.
--------------------------------------------------------------------------------
local function PaintSample(barFrame, which, tf)
    barFrame.icon:SetTexture(134400)
    barFrame.name:SetText(which == "target" and "Crushing Blow" or "Dark Mending")
    local tc = tf and tf.targetColor
    if tf and tf.targetClassColor ~= false and C_ClassColor and UnitClassBase then
        -- The class token alone: UnitClassBase's second return (the class id)
        -- would land in GetClassColor's tint argument and be refused.
        local color = C_ClassColor.GetClassColor((UnitClassBase("player")))
        if color then
            barFrame.target:SetTextColor(color:GetRGB())
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
    local base = (tf and tf.castColor) or { r = 0.70, g = 0.40, b = 0.90 }
    barFrame.sb:GetStatusBarTexture():SetVertexColor(base.r, base.g, base.b)
    barFrame.overlay:SetAlpha(0)
    barFrame.flash:Hide()
    barFrame.sb:SetValue(0.62)
end

local function ShowPreview(which)
    local barFrame = barOf[which] or NewBar(which)
    Style(barFrame)
    PaintSample(barFrame, which, Settings())
    Place(barFrame)
    barFrame.frame:Show()
end

-- The options header's sample: one visuals-only bar per unit, made once on
-- the header's host and painted still each call (no kick parts, ticker or
-- events). Never in barOf, so casts and refreshes never see it.
local sampleOf = {}

-- Hangs the sample at the host's top left; returns its width and height, or
-- nil before the settings exist.
function mod.TFB_PaintSample(owner, which)
    local conf, tf = BarSettings(which), Settings()
    if not (conf and tf) then
        return nil
    end
    local barFrame = sampleOf[which]
    if not barFrame then
        barFrame = NewBarVisuals(which, owner)
        sampleOf[which] = barFrame
    end
    barFrame.frame:SetParent(owner)
    barFrame.frame:ClearAllPoints()
    barFrame.frame:SetPoint("TOPLEFT", owner, "TOPLEFT", 0, 0)
    Style(barFrame)
    PaintSample(barFrame, which, tf)
    barFrame.frame:Show()
    return conf.width or 260, conf.height or 22
end

function mod.TFB_SetPreview(which, on)
    previewOn[which] = on == true
    if previewOn[which] then
        ShowPreview(which)
        return
    end
    local barFrame = barOf[which]
    if barFrame then
        barFrame.frame:Hide()
        barFrame.sb:SetValue(0)
        if listening then
            UpdateCast(barFrame)
        end
    end
end

function mod.TFB_IsPreview(which)
    return previewOn[which] == true
end

--------------------------------------------------------------------------------
--  Refresh: on and off, and the restyle. The options call it on every write.
--------------------------------------------------------------------------------
function mod.TFB_Refresh()
    local wanted = AnyOn()
    if wanted and not listening then
        Listen()
    elseif not wanted and listening then
        StopListening()
        previewOn.target, previewOn.focus = false, false
    end
    for which in pairs(DEFAULT_POS) do
        local conf = BarSettings(which)
        local on = conf and conf.enabled == true
        local barFrame = barOf[which]
        if on and not barFrame then
            barFrame = NewBar(which)
        end
        if barFrame then
            if on then
                Style(barFrame)
                Place(barFrame)
                if previewOn[which] then
                    ShowPreview(which)
                elseif listening then
                    barFrame._castDirtyFull = true
                    UpdateCast(barFrame)
                end
            else
                previewOn[which] = false
                EndCast(barFrame)
                barFrame._interrupted = nil
                barFrame.frame:Hide()
            end
        end
    end
end

--------------------------------------------------------------------------------
--  Unlock mode: one element per bar; hidden while that bar is off.
--------------------------------------------------------------------------------
local function UnlockElement(which, label, order)
    return CludesUI.MakeUnlockElement({
        key = which == "target" and "EMT_TargetCastBar" or "EMT_FocusCastBar",
        label = label,
        group = "Mythic+",
        order = order,
        -- Sized by the sliders (no drag handle), but it can match another
        -- element's size and be matched to: a match is written through
        -- setWidth/setHeight into the same settings the sliders use, so it
        -- survives reloads like a slider value.
        noResize = true,
        allowMatchSource = true,
        isHidden = function()
            local conf = BarSettings(which)
            return not (conf and conf.enabled == true)
        end,
        getFrame = function()
            return (barOf[which] or NewBar(which)).frame
        end,
        getSize = function()
            local conf = BarSettings(which)
            return (conf and conf.width) or 260, (conf and conf.height) or 22
        end,
        setWidth = function(_, w)
            local conf = BarSettings(which)
            if conf then
                conf.width = math.floor(w + 0.5)
                mod.TFB_Refresh()
            end
        end,
        setHeight = function(_, h)
            local conf = BarSettings(which)
            if conf then
                conf.height = math.floor(h + 0.5)
                mod.TFB_Refresh()
            end
        end,
        savePos = function(_, _, _, x, y)
            -- Unlock mode hands over CENTER offsets; on Cancel the frame is
            -- still where it was dragged, so the live position is never read.
            local conf = BarSettings(which)
            if conf and x and y then
                conf.pos = { centerX = x, centerY = y }
                if not CludesUI._unlockActive then
                    Place(barOf[which])
                end
            end
        end,
        loadPos = function()
            local conf = BarSettings(which)
            local position = conf and conf.pos
            if position and position.centerX and position.centerY then
                return { point = "CENTER", relPoint = "CENTER", x = position.centerX, y = position.centerY }
            end
            return nil
        end,
        clearPos = function()
            local conf = BarSettings(which)
            if conf then
                conf.pos = nil
            end
        end,
        applyPos = function()
            Place(barOf[which])
        end,
    })
end

local function RegisterUnlock()
    if not (CludesUI.RegisterUnlockElements and CludesUI.MakeUnlockElement) then
        return
    end
    CludesUI:RegisterUnlockElements({
        UnlockElement("target", "Target Cast Bar", 522),
        UnlockElement("focus", "Focus Cast Bar", 523),
    }, "CludesUIMythicTimer")
    if not CludesUI.RegisterUnlockModeListener then
        return
    end
    local function Listener(which, key)
        return function(active)
            local conf = BarSettings(which)
            if not (conf and conf.enabled == true) then
                return
            end
            mod.TFB_SetPreview(which, active == true)
            if not (CludesUI.IsUnlockAnchored and CludesUI.IsUnlockAnchored(key)) then
                Place(barOf[which])
            end
        end
    end
    CludesUI:RegisterUnlockModeListener("EMT_TargetCastBar", Listener("target", "EMT_TargetCastBar"))
    CludesUI:RegisterUnlockModeListener("EMT_FocusCastBar", Listener("focus", "EMT_FocusCastBar"))
end

-- Called from the module's OnEnable (before the timer's own enable check).
function mod.TFB_OnEnable(database)
    saved = database
    if saved then
        RegisterUnlock()
        mod.TFB_Refresh()
    end
end
