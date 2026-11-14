if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if CludesUI and CludesUI.IS_FOREVER then
    return
end -- no skyriding on WoW Forever: no DB, no events, no HUD; its options tab is not registered there
-------------------------------------------------------------------------------
--  CludesUIBlizzardSkin_DragonRiding.lua - Skyriding HUD
-------------------------------------------------------------------------------
local _, mod = ...

-- Upvalues
local floor, min, upper, abs = math.floor, math.min, math.max, math.abs
local format = string.format
local IsMounted = IsMounted
local C_PlayerInfo = C_PlayerInfo
local C_Spell = C_Spell
local C_Timer = C_Timer
local CreateFrame = CreateFrame
local UnitAffectingCombat = UnitAffectingCombat
local GetTime = GetTime

-- Bar texture table (shared with options via ns); paths only -- the
-- options file builds its own names/order pair from the same catalogue.
mod.EDR_BAR_TEXTURES = (CludesUI.BuildBarTextureTables())

-- Constants
local SPELL = {
    SKYWARD_ASCENT = 372610,
    SECOND_WIND = 425782,
    WHIRLING_SURGE = 361584,
}
local SKYRIDING_PIPS = 6
local SECONDWIND_PIPS = 3
local BASE_RUN_SPEED = 7.0

-- Classic vigor gems: Blizzard's pre-12.0 FillUpFrames widget, rebuilt from the
-- art the client still ships (interface/widgets/dragonridingvigorwidgets.blp).
-- Cell size, edge padding and decor offset are the dragonriding_vigor values from
-- Blizzard_UIWidgetTemplateFillUpFrames.lua; art sizes are the atlas pixel sizes
-- halved (the sheet is 2x).
local CLASSIC = {
    kit = "dragonriding_vigor",
    cellW = 42,
    cellH = 45,
    edgePad = -20,
    decorTop = 8,
    decorW = 46.5,
    decorH = 58.5,
    frameW = 60,
    frameH = 65,
    bgW = 30.5,
    bgH = 35.5,
    fillW = 36,
    fillH = 36,
    sparkW = 46.5,
    sparkH = 10,
    maskW = 64,
    maskH = 64,
}
local CLASSIC_W = CLASSIC.decorW * 2 + CLASSIC.edgePad * 2 + CLASSIC.cellW * SKYRIDING_PIPS
local CLASSIC_H = upper(CLASSIC.cellH, CLASSIC.decorTop + CLASSIC.decorH)
local FULL_CHARGE_SOUND = SOUNDKIT and SOUNDKIT.UI_DRAGONRIDING_FULL_NODE

-- Database defaults
local DB_DEFAULTS = {
    profile = {
        enabled = false,
        hideInCombat = false,

        -- Bar art (Global Settings > Style, "Skyriding HUD"): the Classic flag
        -- = Classic WoW UI, else the Blizzard flag = Blizzard Style, else the
        -- CludesUI look. Read through the session latch ns.EDR_Style().
        useBlizzardStyle = false,
        useClassicStyle = false,
        classicFrameSize = nil, -- Classic WoW UI frame %, nil = shared default
        -- Charges: "bars" = a pip row in the bar column, "gems" = Blizzard's
        -- original vigor gems above the column. Independent of the bar art.
        vigorStyle = "bars",
        classicScale = 1.0,
        chargeSound = false,
        showSpeed = true,
        showSecondWind = true,
        showWhirlingSurge = true,
        iconSize = nil, -- nil = as tall as the full bar column

        width = 240,
        speedHeight = 14,
        skyridingHeight = 10,
        secondWindHeight = 6,
        gap = 2,
        stackSpacing = 2,

        borderThickness = 0,
        borderColor = { r = 0.0, g = 0.0, b = 0.0, a = 1.0 },

        maxSpeed = 1300,
        thrillThreshold = 789,
        thrillColorToggle = true,
        normalColor = { r = 0.055, g = 0.667, b = 0.761, a = 1.0 },
        thrillColor = { r = 0.902, g = 0.494, b = 0.133, a = 1.0 },
        speedBarBg = { r = 0.10, g = 0.10, b = 0.10, a = 0.80 },
        tickColor = { r = 1.00, g = 1.00, b = 1.00, a = 0.50 },

        speedText = {
            enabled = true,
            justify = "CENTER",
            size = 12,
            offsetX = 0,
            offsetY = 0,
        },

        skyridingFilled = { r = 0.298, g = 0.788, b = 0.941, a = 1.0 },
        skyridingBg = { r = 0.10, g = 0.10, b = 0.10, a = 0.80 },

        secondWindFilled = { r = 0.902, g = 0.706, b = 0.133, a = 1.0 },
        secondWindBg = { r = 0.10, g = 0.10, b = 0.10, a = 0.80 },

        whirlingSurgeText = {
            enabled = true,
            justify = "CENTER",
            size = 12,
            offsetX = 0,
            offsetY = 0,
        },

        unlockPos = nil,
    },
}

-- State
local saved
local rootFrame, speedBar, stackFrame, swFrame, wsIcon, classicFrame
local skyridingDirty = true
local secondWindDirty = true
local whirlingDirty = true
local lastSpeedApplied = -1
local lastCdStart, lastCdDur = -1, -1
local lastSkyCur, lastSkyProgress = -1, -1
local lastSwCur, lastSwProgress = -1, -1
local lastClassicCur, lastClassicProgress = -1, -1
-- Charge count the full-charge sound last saw; -1 after every Redraw so a
-- repaint (login, settings change, style switch) never plays it.
local lastSoundCur = -1
local UPDATE_THROTTLE = 1 / 60
local elapsed = 0
local smoothedSpeed = 0
local SPEED_EMA_ALPHA = 0.25
local evtFrame -- event frame (created on first enable)
local _spellEventsRegistered = false
local _cdEventRegistered = false
-- True only while actually airborne skyriding: PLAYER_IS_GLIDING_CHANGED edges
-- plus a fresh read at every visibility evaluation. Gates the speed poll -- the
-- OnUpdate is armed only while gliding, while the landing decay is still
-- draining, or while a pip/cooldown section is mid-animation.
local _gliding = false

-- The bar art this session: "cui" | "blizzard" | "classic". Read from the
-- profile's two Style page flags once (the first call with a profile, which
-- is the DB creation at PLAYER_LOGIN) and latched for the session: the Style
-- page and a profile switch that changes it both reload. The Classic flag
-- wins when both are set (the Style page never writes both).
function mod.EDR_Style()
    local val = mod._edrStyle
    if val == nil then
        local p = saved and saved.profile
        if not p then
            return "cui"
        end
        val = (p.useClassicStyle and "classic") or (p.useBlizzardStyle and "blizzard") or "cui"
        mod._edrStyle = val
    end
    return val
end

-- Returns true when the module should be hard-disabled (M+ or raid instance).
-- No frames shown, no events processed, no OnUpdate.
local function IsInLockedContent()
    if
        C_ChallengeMode
        and C_ChallengeMode.IsChallengeModeActive
        and C_ChallengeMode.IsChallengeModeActive()
    then
        return true
    end
    local _, instanceType = IsInInstance()
    if instanceType == "raid" or instanceType == "party" then
        return true
    end
    return false
end

local function GetSkyridingSpeed()
    local isGliding, _, forwardSpeed = C_PlayerInfo.GetGlidingInfo()
    if not isGliding then
        smoothedSpeed = smoothedSpeed * (1 - SPEED_EMA_ALPHA)
        -- Floor the landing decay to exactly 0 so the final empty-bar state
        -- paints once and the tick can then disarm (TickWanted reads > 0).
        if smoothedSpeed < 0.01 then
            smoothedSpeed = 0
        end
        return false, smoothedSpeed
    end
    smoothedSpeed = smoothedSpeed + SPEED_EMA_ALPHA * ((forwardSpeed or 0) - smoothedSpeed)
    return true, smoothedSpeed
end

-- Forward declarations
local function Build() end
local function Rebuild() end
local function Redraw() end
local function UpdateVisibility() end
local function OnUpdate() end
local function ApplyPos() end
local function RegisterUnlockElements() end

-- Arm the per-frame body only while it has live work: airborne (speed poll),
-- landing decay still draining, or a pip/cooldown fill mid-animation. Grounded
-- with full charges and a settled bar = no OnUpdate and no API reads at all.
-- Unlock Mode force-arms so the HUD stays editable off-mount.
local function TickWanted()
    return skyridingDirty
        or secondWindDirty
        or whirlingDirty
        or ((_gliding or smoothedSpeed > 0) and saved.profile.showSpeed ~= false)
end
local function SyncTick()
    if not rootFrame then
        return
    end
    if rootFrame:IsShown() and (TickWanted() or (CludesUI and CludesUI._unlockActive)) then
        rootFrame:SetScript("OnUpdate", OnUpdate)
    else
        rootFrame:SetScript("OnUpdate", nil)
    end
end

-- Register/unregister high-frequency spell events based on HUD visibility.
-- These fire for ALL spells globally, so we only listen when actively showing.
-- SPELL_UPDATE_COOLDOWN feeds only the Whirling Surge icon, so it is also off
-- while the icon is hidden; every Rebuild ends in UpdateVisibility, which
-- re-syncs it when Show Whirling Surge flips.
local function RegisterSpellEvents()
    if not evtFrame then
        return
    end
    if not _spellEventsRegistered then
        evtFrame:RegisterEvent("SPELL_UPDATE_CHARGES")
        _spellEventsRegistered = true
    end
    local wantCd = saved.profile.showWhirlingSurge ~= false
    if wantCd ~= _cdEventRegistered then
        if wantCd then
            evtFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
        else
            evtFrame:UnregisterEvent("SPELL_UPDATE_COOLDOWN")
        end
        _cdEventRegistered = wantCd
    end
end
local function UnregisterSpellEvents()
    if not evtFrame then
        return
    end
    if _spellEventsRegistered then
        evtFrame:UnregisterEvent("SPELL_UPDATE_CHARGES")
        _spellEventsRegistered = false
    end
    if _cdEventRegistered then
        evtFrame:UnregisterEvent("SPELL_UPDATE_COOLDOWN")
        _cdEventRegistered = false
    end
end

-------------------------------------------------------------------------------
--  Visibility
-------------------------------------------------------------------------------
local function IsOnSkyridingMount()
    if not CludesUI.IsPlayerMountedLike() then
        return false
    end
    local _, canGlide = C_PlayerInfo.GetGlidingInfo()
    return canGlide == true
end

-- Hidden -> shown (the normal path and Unlock Mode's force-show alike). The
-- spell events are off while the HUD is hidden, so every section repaints
-- once; charges that refilled meanwhile are not a live gain, so they repaint
-- without the full-charge chime or the gem flash.
local function MarkReshown()
    skyridingDirty, secondWindDirty, whirlingDirty = true, true, true
    lastSoundCur, lastClassicCur = -1, -1
end

function UpdateVisibility()
    if not rootFrame then
        return
    end
    local p = saved and saved.profile
    if not p or not p.enabled or IsInLockedContent() then
        rootFrame:Hide()
        rootFrame:SetScript("OnUpdate", nil)
        UnregisterSpellEvents()
        return
    end
    local wasShown = rootFrame:IsShown()
    if CludesUI and CludesUI._unlockActive then
        if not wasShown then
            MarkReshown()
        end
        rootFrame:Show()
        rootFrame:SetScript("OnUpdate", OnUpdate)
        RegisterSpellEvents()
        return
    end
    local onSky = IsOnSkyridingMount()
    local hideCombat = p.hideInCombat and UnitAffectingCombat("player")
    local visible = onSky and not hideCombat
    rootFrame:SetShown(visible)
    if visible then
        if not wasShown then
            MarkReshown()
        end
        -- Seed the airborne flag from a fresh read (covers /reload mid-flight
        -- and any edge missed while hidden), then arm only if there is work.
        local isGliding = C_PlayerInfo.GetGlidingInfo()
        _gliding = isGliding == true
        SyncTick()
        RegisterSpellEvents()
    else
        rootFrame:SetScript("OnUpdate", nil)
        UnregisterSpellEvents()
    end
end

-- Re-check real visibility when Unlock Mode exits. UpdateVisibility()
-- force-shows the HUD while CludesUI._unlockActive is true (so it can be
-- edited even off-mount), but nothing previously re-ran it on exit, so
-- dismounting during Unlock Mode left it stuck visible until an unrelated
-- mount/dismount happened to call UpdateVisibility() again. Called from
-- CUI_UnlockMode.lua's exit path, matching the Quest Tracker's same pattern.
_G._CUDR_UpdateVisibility = function()
    UpdateVisibility()
end

-------------------------------------------------------------------------------
--  OnUpdate
-------------------------------------------------------------------------------
local function ApplyPipRow(pips, pipCount, current, maxC, progress, lastCur, lastProgress, filled, bgAlpha)
    if current ~= lastCur then
        for idx = 1, pipCount do
            local pipTex = pips[idx]
            if idx <= current then
                pipTex:SetValue(1)
                pipTex:SetStatusBarColor(filled.r, filled.g, filled.b, 1)
            elseif idx == current + 1 and current < maxC then
                pipTex:SetValue(progress)
                pipTex:SetStatusBarColor(filled.r, filled.g, filled.b, bgAlpha)
            else
                pipTex:SetValue(0)
                pipTex:SetStatusBarColor(filled.r, filled.g, filled.b, 1)
            end
        end
        return current, progress
    elseif current < maxC and abs(progress - lastProgress) > 0.005 then
        local pipTex = pips[current + 1]
        if pipTex then
            pipTex:SetValue(progress)
        end
        return current, progress
    end
    return lastCur, lastProgress
end

-- Per-cell state for the classic gems, mirroring UIWidgetFillUpFrameTemplateMixin:
-- a full gem flashes once when it completes, the filling gem pulses and plays the
-- swirl flipbook, the spark rides the fill line.
local function SetClassicFilling(cellFrame, progress)
    cellFrame.bar:SetValue(progress)
    cellFrame.spark:SetShown(progress > 0 and progress < 1)
    if cellFrame.flipAnim then
        if progress > 0 then
            if not cellFrame.flipAnim:IsPlaying() then
                cellFrame.flip:Show()
                cellFrame.flipAnim:Play()
            end
        else
            cellFrame.flip:Hide()
            cellFrame.flipAnim:Stop()
        end
    end
end

local function SetClassicFull(cellFrame, full)
    if cellFrame.isFull == full then
        return
    end
    cellFrame.isFull = full
    local atlas = full and cellFrame.fillFullAtlas or cellFrame.fillAtlas
    if atlas then
        cellFrame.bar:SetStatusBarTexture(atlas)
    end
    cellFrame.spark:ClearAllPoints()
    cellFrame.spark:SetPoint("CENTER", cellFrame.bar:GetStatusBarTexture(), "TOP", 0, 0)
    if cellFrame.flipMask then
        cellFrame.flipMask:ClearAllPoints()
        cellFrame.flipMask:SetPoint("TOP", cellFrame.bar:GetStatusBarTexture(), "TOP", 0, 0)
    end
end

local function ApplyClassicRow(current, maxC, progress)
    local cells = classicFrame.cells
    if current ~= lastClassicCur then
        -- lastClassicCur is -1 after every Redraw, so the first paint never flashes.
        local gained = lastClassicCur >= 0 and current > lastClassicCur
        for idx = 1, SKYRIDING_PIPS do
            local cellFrame = cells[idx]
            local isFull = idx <= current
            local isFilling = idx == current + 1 and current < maxC
            SetClassicFull(cellFrame, isFull)
            if isFull then
                cellFrame.bar:SetValue(1)
                cellFrame.spark:Hide()
                cellFrame.pulseAnim:Stop()
                if cellFrame.flipAnim then
                    cellFrame.flipAnim:Stop()
                    cellFrame.flip:Hide()
                end
                if gained and idx > lastClassicCur then
                    cellFrame.flashAnim:Restart()
                end
            elseif isFilling then
                cellFrame.flashAnim:Stop()
                cellFrame.flash:SetAlpha(0)
                cellFrame.pulseAnim:Play()
                SetClassicFilling(cellFrame, progress)
            else
                cellFrame.flashAnim:Stop()
                cellFrame.pulseAnim:Stop()
                cellFrame.flash:SetAlpha(0)
                SetClassicFilling(cellFrame, 0)
            end
        end
        return current, progress
    elseif current < maxC and abs(progress - lastClassicProgress) > 0.005 then
        local cellFrame = cells[current + 1]
        if cellFrame then
            SetClassicFilling(cellFrame, progress)
        end
        return current, progress
    end
    return lastClassicCur, lastClassicProgress
end

local function FormatSpeedText(speedPct)
    return format("%d%%", floor(speedPct + 0.5))
end

local function FormatCooldownText(remaining)
    if remaining >= 10 then
        return format("%d", floor(remaining + 0.5))
    elseif remaining >= 1 then
        return format("%d", floor(remaining))
    else
        return format("%.1f", remaining)
    end
end

function OnUpdate(self, dt)
    elapsed = elapsed + dt
    if elapsed < UPDATE_THROTTLE then
        return
    end
    elapsed = 0

    local p = saved.profile

    -- Speed poll only while airborne or while the landing decay drains; the
    -- decay floors to exactly 0 so the final empty-bar state paints once.
    -- Nothing to poll while the speed bar is hidden.
    if (_gliding or smoothedSpeed > 0) and p.showSpeed ~= false then
        local _, curSpeed = GetSkyridingSpeed()
        local speedPct = curSpeed / BASE_RUN_SPEED * 100
        local frac = (p.maxSpeed > 0) and (speedPct / p.maxSpeed) or 0
        frac = upper(0, min(1, frac))
        if frac ~= lastSpeedApplied then
            speedBar:SetValue(frac)
            if p.speedText.enabled ~= false then
                speedBar.text:SetText(FormatSpeedText(speedPct))
            end
            local aboveThrill = (speedPct >= (p.thrillThreshold or 0))
            local c = (p.thrillColorToggle and aboveThrill) and p.thrillColor or p.normalColor
            speedBar:SetStatusBarColor(c.r, c.g, c.b, c.a)
            lastSpeedApplied = frac
        end
    end -- speed-poll gate

    if skyridingDirty then
        local details = C_Spell.GetSpellCharges(SPELL.SKYWARD_ASCENT)
        local current = details and details.currentCharges or 0
        local maxC = details and details.maxCharges or SKYRIDING_PIPS
        local progress = 0
        if details and details.cooldownDuration and details.cooldownDuration > 0 then
            local e = GetTime() - (details.cooldownStartTime or 0)
            progress = upper(0, min(1, e / details.cooldownDuration))
        end
        if p.chargeSound and lastSoundCur >= 0 and current > lastSoundCur and FULL_CHARGE_SOUND then
            PlaySound(FULL_CHARGE_SOUND)
        end
        lastSoundCur = current
        if p.vigorStyle == "gems" and classicFrame then
            lastClassicCur, lastClassicProgress = ApplyClassicRow(current, maxC, progress)
        else
            lastSkyCur, lastSkyProgress = ApplyPipRow(
                stackFrame.pips,
                SKYRIDING_PIPS,
                current,
                maxC,
                progress,
                lastSkyCur,
                lastSkyProgress,
                p.skyridingFilled,
                0.4
            )
        end
        skyridingDirty = (current < maxC)
    end

    if secondWindDirty and p.showSecondWind == false then
        secondWindDirty = false -- hidden; showing it again redraws it
    elseif secondWindDirty then
        local details = C_Spell.GetSpellCharges(SPELL.SECOND_WIND)
        local current = details and details.currentCharges or 0
        local maxC = details and details.maxCharges or SECONDWIND_PIPS
        local progress = 0
        if details and details.cooldownDuration and details.cooldownDuration > 0 then
            local e = GetTime() - (details.cooldownStartTime or 0)
            progress = upper(0, min(1, e / details.cooldownDuration))
        end
        lastSwCur, lastSwProgress = ApplyPipRow(
            swFrame.pips,
            SECONDWIND_PIPS,
            current,
            maxC,
            progress,
            lastSwCur,
            lastSwProgress,
            p.secondWindFilled,
            0.4
        )
        secondWindDirty = (current < maxC)
    end

    if whirlingDirty and p.showWhirlingSurge == false then
        whirlingDirty = false -- hidden; showing it again redraws it
    elseif whirlingDirty then
        local details = C_Spell.GetSpellCooldown(SPELL.WHIRLING_SURGE)
        local start = details and details.startTime or 0
        local dur = details and details.duration or 0
        if dur > 1.5 then
            if start ~= lastCdStart or dur ~= lastCdDur then
                wsIcon.cd:SetCooldown(start, dur)
                lastCdStart, lastCdDur = start, dur
            end
            local remaining = start + dur - GetTime()
            if remaining > 0 then
                if p.whirlingSurgeText.enabled ~= false then
                    wsIcon.text:SetText(FormatCooldownText(remaining))
                end
                whirlingDirty = true
            else
                wsIcon.text:SetText("")
                whirlingDirty = false
            end
        else
            if lastCdDur ~= 0 then
                wsIcon.cd:Clear()
                wsIcon.text:SetText("")
                lastCdStart, lastCdDur = 0, 0
            end
            whirlingDirty = false
        end
    end

    -- Self-disarm once every section settled and we are grounded; every dirty
    -- writer and the gliding edge re-arm through SyncTick.
    if not TickWanted() then
        SyncTick()
    end
end

-------------------------------------------------------------------------------
--  Layout
-------------------------------------------------------------------------------
local ROW_FIELD = { speed = "speedHeight", sky = "skyridingHeight", sw = "secondWindHeight" }
-- Options-page slider range of each row height (the unlock height drag clamps to it).
local ROW_RANGE = { speedHeight = { 4, 40 }, skyridingHeight = { 2, 24 }, secondWindHeight = { 2, 24 } }
-- Every bar row of each vigor style, bottom to top (the automatic icon height).
local STYLE_ROWS_BARS = { "speed", "sky", "sw" }
local STYLE_ROWS_GEMS = { "speed", "sw" }

-- Stock style art (ns.EDR_Style). Both stock looks match the Resource Bars'
-- ones so the HUD and the class resource bar read as one UI; the bars keep
-- the user's texture and colours in every style, and the column is framed as
-- one box with dividers (see ApplyColumnChrome).
--
-- Blizzard: the Cooldown Manager bar panel (the personal resource display's
-- art) round the column, and an inner bevel over each row so the user's
-- texture reads recessed. The panel's opaque rim is 1 left and right, 2
-- above, 1 below.
local BLIZZ_CHROME = {
    bg = "UI-HUD-CoolDownManager-Bar-BG",
    fill = "UI-HUD-CoolDownManager-Bar",
    rimX = 1,
    rimT = 2,
    rimB = 1,
}
local SHADE_CLEAR = CreateColor(0, 0, 0, 0)
local SHADE_TOP = CreateColor(0, 0, 0, 0.55)
local SHADE_BOTTOM = CreateColor(0, 0, 0, 0.30)
local SHADE_END = CreateColor(0, 0, 0, 0.35)
-- Whirling Surge icon, Blizzard: action button frame (46x45 around a 45 icon,
-- anchored TOPLEFT) and mask, with the rounded swipe AuraKit and the Cooldown
-- Manager use (Cooldown frames cannot take a MaskTexture). Classic WoW UI: the
-- vanilla slot ring the classic action buttons wear (66/36 of the icon,
-- 1/36 low).
local BLIZZ_ICON = {
    frame = "ui-hud-actionbar-iconframe",
    frameW = 46,
    frameH = 45,
    iconSize = 45,
    mask = "ui-hud-actionbar-iconframe-mask",
    swipe = "Interface\\HUD\\UI-HUD-CoolDownManager-Icon-Swipe",
    ring = "Interface\\Buttons\\UI-Quickslot2",
}

local function PPSnap(val)
    local PPdr = CludesUI and CludesUI.PP
    if PPdr and PPdr.Snap then
        return PPdr.Snap(val)
    end
    return floor(val + 0.5)
end
-- Round a frame dimension UP to a whole number of physical pixel PAIRS. The HUD
-- is centre-anchored, so an odd pixel count (or a fraction, which the classic
-- gems' half-unit art sizes produced) puts every edge inside it half a pixel
-- off the grid.
local function SnapEven(val)
    local PPdr = CludesUI and CludesUI.PP
    local m = PPdr and PPdr.mult or 1
    if m <= 0 then
        m = 1
    end
    return math.ceil(val / (2 * m) - 1e-6) * 2 * m
end

-- Room the bar column reserves round itself for its frame's VISIBLE rim:
-- vertical (each side) and horizontal (each end). The Blizzard and Classic WoW
-- UI styles frame the column as one box (the Resource Bars' Border Around All
-- look), so the rim sits outside the column only. Above and below differ
-- slightly; each side takes half of their sum. 0,0 with no frame (modern).
local function ArtOverhang(chrome, k)
    if chrome == "blizzard" then
        local C = BLIZZ_CHROME
        return PPSnap((C.rimT + C.rimB) / 2), PPSnap(C.rimX)
    elseif chrome == "classic" then
        local CF = CludesUI.ClassicFrame
        if not CF then
            return 0, 0
        end
        local padW, padH = CF.Pad(k)
        return PPSnap(padH / 2), PPSnap(padW / 2)
    end
    return 0, 0
end

-- Height a list of rows occupies stacked with gaps, including the frame rim
-- (ov, from ArtOverhang).
local function StackHeight(p, rowList, ov)
    if #rowList == 0 then
        return 0
    end
    local total = 2 * ov
    for idx, key in ipairs(rowList) do
        total = total + p[ROW_FIELD[key]] + (idx > 1 and p.gap or 0)
    end
    return total
end

-- Classic WoW UI frame scale: the Border Size percentage (nil = the shared
-- default), as the Resource Bars' Classic WoW UI bars take it.
local function ClassicFrameK(p)
    local CF = CludesUI.ClassicFrame
    return CF and CF.ScaleK(p.classicFrameSize) or 1
end

-- Where everything goes for the current settings. The bar column stacks bottom
-- to top (speed, charges, Second Wind) and the Whirling Surge icon sits on its
-- right, the shorter of the two centred on the taller; the classic gem row sits
-- above both. The icon is as tall as the full column (every bar of the style)
-- unless given its own size. Classic gems replace the charge row rather than
-- sitting in the column, and the Blizzard and Classic WoW UI bar styles frame
-- each row, which needs room around it.
local function ComputeLayout(p)
    local classic = p.vigorStyle == "gems"
    local look = mod.EDR_Style()
    local chrome = look ~= "cui" and look or nil
    local k = chrome == "classic" and ClassicFrameK(p) or 1

    local rowList = {}
    if p.showSpeed ~= false then
        rowList[#rowList + 1] = "speed"
    end
    if not classic then
        rowList[#rowList + 1] = "sky"
    end
    if p.showSecondWind ~= false then
        rowList[#rowList + 1] = "sw"
    end

    local ov, padX = ArtOverhang(chrome, k)
    local colH = StackHeight(p, rowList, ov)
    local colW = #rowList > 0 and (p.width + 2 * padX) or 0

    local glyph = p.showWhirlingSurge ~= false
    local iconSize = 0
    if glyph then
        iconSize = p.iconSize
        if not iconSize then
            -- Every bar of the style, shown or not.
            iconSize = StackHeight(p, classic and STYLE_ROWS_GEMS or STYLE_ROWS_BARS, ov)
        end
    end
    local clusterW = colW + (glyph and ((colW > 0 and p.gap or 0) + iconSize) or 0)
    local clusterH = upper(colH, iconSize)

    local scale = p.classicScale or 1
    local classicW = classic and PPSnap(CLASSIC_W * scale) or 0
    local classicH = classic and PPSnap(CLASSIC_H * scale) or 0
    local rawW = upper(clusterW, classicW)
    local rawH = clusterH + classicH + ((classic and clusterH > 0) and p.gap or 0)
    -- The even-pixel rounding is for the stock frames and the classic gems
    -- only: the CludesUI bars keep their exact size, so their root frame
    -- and the unlock size stay what they always were.
    local even = chrome or classic

    return {
        rows = rowList,
        classic = classic,
        chrome = chrome,
        frameK = k,
        ov = ov,
        scale = scale,
        colH = colH,
        colW = colW,
        padX = padX,
        colY = PPSnap((clusterH - colH) / 2),
        icon = glyph,
        iconSize = iconSize,
        iconY = PPSnap((clusterH - iconSize) / 2),
        clusterW = clusterW,
        clusterH = clusterH,
        classicW = classicW,
        classicH = classicH,
        -- raw* before the even-pixel rounding (equal to total* without it).
        rawW = rawW,
        rawH = rawH,
        totalW = even and SnapEven(rawW) or rawW,
        totalH = even and SnapEven(rawH) or rawH,
    }
end

-------------------------------------------------------------------------------
--  Helpers
-------------------------------------------------------------------------------
local function ApplyFont(fontStr, dim)
    if not fontStr then
        return
    end
    local font = CludesUI.GetFontPath("blizzardSkin") or "Fonts/FRIZQT__.TTF"
    local flag = CludesUI.GetFontOutlineFlag("blizzardSkin") or ""
    CludesUI.PrimeFontShadow(fontStr, flag == "")
    fontStr:SetFont(font, dim or 12, flag)
end

local function CreateSolidTexture(hostFrame, layer, sublevel, r, g, b, a)
    local texture = hostFrame:CreateTexture(nil, layer or "BACKGROUND", nil, sublevel or 0)
    texture:SetColorTexture(r or 0, g or 0, b or 0, a or 1)
    texture:SetSnapToPixelGrid(false)
    texture:SetTexelSnappingBias(0)
    return texture
end

local borderedFrames = {}

-- A frame set is one HUD's frames: { root, speed, stack, sw, icon, classic,
-- bordered }. The live HUD is one set, the options header's sample another;
-- the layout and paint passes below take the set they draw.
local function EnsureBorder(Stl, widget)
    if not widget or widget._edrBorderAdded then
        return
    end
    if not (CludesUI and CludesUI.PP and CludesUI.PP.CreateBorder) then
        return
    end
    CludesUI.PP.CreateBorder(widget, 0, 0, 0, 1, 1, "OVERLAY", 7)
    widget._edrBorderAdded = true
    Stl.bordered[#Stl.bordered + 1] = widget
end

local function ApplyBorderEdges(widget, hideL, hideR, hideT, hideB)
    local Pix = CludesUI and CludesUI.PP
    local edges = Pix and Pix.GetBorders and Pix.GetBorders(widget)
    if not edges then
        return
    end
    edges._hideLeft = hideL or nil
    edges._hideRight = hideR or nil
    edges._hideTop = hideT or nil
    edges._hideBottom = hideB or nil
end

local function ApplyBordersAll(Stl, L)
    local Pix = CludesUI and CludesUI.PP
    if not Pix then
        return
    end
    local p = saved.profile
    local c = p.borderColor
    -- The Blizzard and Classic WoW UI bar styles draw their own frames instead.
    local thick = L.chrome and 0 or (p.borderThickness or 0)
    for _, f in ipairs(Stl.bordered) do
        if thick > 0 then
            Pix.UpdateBorder(f, thick, c.r, c.g, c.b, c.a)
            Pix.ShowBorder(f)
        else
            Pix.HideBorder(f)
        end
    end

    if thick > 0 then
        -- At Element Spacing / Stack Spacing = 0 the touching frames each
        -- draw their own full border, so the shared seam gets two
        -- independently pixel-snapped lines instead of one. Suppress the
        -- edge on one side of every seam so only a single line remains:
        -- the speed bar drops its top edge under the row above it, any other
        -- row drops its bottom edge over the row under it (the ownership the
        -- HUD has always drawn), and a row lying wholly beside the icon drops
        -- its right edge (the icon can be shorter than the column, so rows
        -- above or below it keep theirs).
        local gapTouch = p.gap == 0
        local stackTouch = p.stackSpacing == 0
        local iconLo, iconHi = L.iconY - 0.01, L.iconY + L.iconSize + 0.01
        local rowList = L.rows
        local posY = L.colY + L.ov
        for idx, key in ipairs(rowList) do
            local hgt = p[ROW_FIELD[key]]
            local iconTouch = gapTouch and L.icon and posY >= iconLo and posY + hgt <= iconHi
            posY = posY + hgt + p.gap
            local hideB = gapTouch and idx > 1 and rowList[idx - 1] ~= "speed"
            if key == "speed" then
                ApplyBorderEdges(Stl.speed, false, iconTouch, gapTouch and idx < #rowList, hideB)
            else
                local pips, num = Stl.stack.pips, SKYRIDING_PIPS
                if key == "sw" then
                    pips, num = Stl.sw.pips, SECONDWIND_PIPS
                end
                for jdx = 1, num do
                    local hideR = (stackTouch and jdx < num) or (iconTouch and jdx == num)
                    ApplyBorderEdges(pips[jdx], false, hideR, false, hideB)
                end
            end
        end
        -- Re-snap so the updated hide flags take effect immediately.
        for _, f in ipairs(Stl.bordered) do
            Pix.SetBorderSize(f, thick)
        end
    end
end

local function CreateSpeedBar(hostFrame)
    local f = CreateFrame("StatusBar", nil, hostFrame)
    f:SetMinMaxValues(0, 1)
    f:SetValue(0)
    f:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    f.bg = CreateSolidTexture(f, "BACKGROUND", 0)
    f.bg:SetAllPoints(f)
    f.tick = CreateSolidTexture(f, "OVERLAY", 5)
    -- The pip stacks/icon nest their bar textures one parent level deeper
    -- than the speed bar itself (stackFrame -> pip, wsIcon -> tex/cd), and
    -- frame level always outranks draw layer across frames. A plain OVERLAY
    -- fontstring parented directly to f would render behind that nested
    -- content, so give the text its own frame raised well above every level
    -- used anywhere in this HUD (same pattern as CreateWhirlingSurgeIcon's
    -- textFrame).
    f.textFrame = CreateFrame("Frame", nil, f)
    f.textFrame:SetAllPoints(f)
    f.textFrame:SetFrameLevel(f:GetFrameLevel() + 10)
    f.text = f.textFrame:CreateFontString(nil, "OVERLAY")
    return f
end

local function CreateStackFrame(hostFrame, pipCount)
    local f = CreateFrame("Frame", nil, hostFrame)
    f.pips = {}
    for idx = 1, pipCount do
        local pipTex = CreateFrame("StatusBar", nil, f)
        pipTex:SetMinMaxValues(0, 1)
        pipTex:SetValue(0)
        pipTex:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
        pipTex.bg = CreateSolidTexture(pipTex, "BACKGROUND", 0)
        pipTex.bg:SetAllPoints(pipTex)
        f.pips[idx] = pipTex
    end
    return f
end

local function CreateWhirlingSurgeIcon(hostFrame)
    local f = CreateFrame("Frame", nil, hostFrame)
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetAllPoints(f)
    local details = C_Spell.GetSpellInfo(SPELL.WHIRLING_SURGE)
    local iconFile = details and details.iconID or 135860
    f.tex:SetTexture(iconFile)
    f.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.cd:SetAllPoints(f)
    f.cd:SetDrawEdge(false)
    f.cd:SetHideCountdownNumbers(true)
    f.textFrame = CreateFrame("Frame", nil, f)
    f.textFrame:SetAllPoints(f)
    f.textFrame:SetFrameLevel(f.cd:GetFrameLevel() + 1)
    f.text = f.textFrame:CreateFontString(nil, "OVERLAY")
    return f
end

-- Inner bevel over a Blizzard-style row: gradient strips darkening the long
-- edges and both ends (the Resource Bars' bevel), so the user's texture reads
-- recessed in the panel.
local function LayoutBevel(shade, wid, hgt)
    local sh = shade.strips
    if not sh then
        sh = {}
        for idx = 1, 4 do
            local t = shade:CreateTexture(nil, "OVERLAY", nil, -3)
            t:SetTexture("Interface\\Buttons\\WHITE8X8")
            t:SetSnapToPixelGrid(false)
            t:SetTexelSnappingBias(0)
            sh[idx] = t
        end
        shade.strips = sh
    end
    local a = upper(2, floor(hgt * 0.2))
    local b = upper(1, floor(hgt * 0.1))
    local e = upper(2, floor(wid * 0.15))
    for idx = 1, 4 do
        sh[idx]:ClearAllPoints()
    end
    sh[1]:SetGradient("VERTICAL", SHADE_CLEAR, SHADE_TOP)
    sh[1]:SetPoint("TOPLEFT")
    sh[1]:SetPoint("TOPRIGHT")
    sh[1]:SetHeight(a)
    sh[2]:SetGradient("VERTICAL", SHADE_BOTTOM, SHADE_CLEAR)
    sh[2]:SetPoint("BOTTOMLEFT")
    sh[2]:SetPoint("BOTTOMRIGHT")
    sh[2]:SetHeight(b)
    sh[3]:SetGradient("HORIZONTAL", SHADE_END, SHADE_CLEAR)
    sh[3]:SetPoint("TOPLEFT")
    sh[3]:SetPoint("BOTTOMLEFT")
    sh[3]:SetWidth(e)
    sh[4]:SetGradient("HORIZONTAL", SHADE_CLEAR, SHADE_END)
    sh[4]:SetPoint("TOPRIGHT")
    sh[4]:SetPoint("BOTTOMRIGHT")
    sh[4]:SetWidth(e)
end

-- Add or move a mask on a texture, once per texture object (AddMaskTexture is
-- additive, and a status bar texture swap can mint a new fill object).
-- mask nil takes it off.
local function MaskTex(texture, maskTex)
    if not texture or texture._edrMask == maskTex then
        return
    end
    if texture._edrMask then
        texture:RemoveMaskTexture(texture._edrMask)
    end
    if maskTex then
        texture:AddMaskTexture(maskTex)
    end
    texture._edrMask = maskTex
end

-- Per-row part of the Blizzard style, as the Resource Bars keep it on every
-- bar, grouped or not: the row's fill, backing and bevel clipped to the stock
-- fill's rounded footprint (one clip across a pip row, so only its end pips
-- round off), which keeps the row inside the panel rim's rounded corners, and
-- the bevel over the row (above the pips and their borders, under the speed
-- text at +10). Built on first use; hidden and un-clipped in the other styles.
local function ApplyRowChrome(hostRegion, chrome, wid, hgt)
    local on = chrome == "blizzard"
    local shade = hostRegion._edrShade
    if on and not shade then
        shade = CreateFrame("Frame", nil, hostRegion)
        shade:SetAllPoints(hostRegion)
        shade:SetFrameLevel(hostRegion:GetFrameLevel() + 9)
        hostRegion._edrShade = shade
        if C_Texture.GetAtlasInfo(BLIZZ_CHROME.fill) then
            hostRegion._edrMask = hostRegion:CreateMaskTexture()
            hostRegion._edrMask:SetAtlas(BLIZZ_CHROME.fill)
            hostRegion._edrMask:SetAllPoints(hostRegion)
        end
    end
    if not shade then
        return
    end
    shade:SetShown(on)
    if on then
        LayoutBevel(shade, wid, hgt)
    end
    local maskTex = on and hostRegion._edrMask or nil
    if hostRegion.pips then
        for idx = 1, #hostRegion.pips do
            local pipTex = hostRegion.pips[idx]
            MaskTex(pipTex:GetStatusBarTexture(), maskTex)
            MaskTex(pipTex.bg, maskTex)
        end
    else
        MaskTex(hostRegion:GetStatusBarTexture(), maskTex)
        MaskTex(hostRegion.bg, maskTex)
    end
    if shade.strips then
        for idx = 1, #shade.strips do
            MaskTex(shade.strips[idx], maskTex)
        end
    end
end

-- Blizzard panel as a nine-slice round the whole column (the Resource Bars'
-- Border Around All panel). The atlas is 132x19 with the fill area at columns
-- 2..126 and rows 3..12; only the middle stretches, so the rims keep their
-- size however tall the column is. The centre is the rows' backdrop and sits
-- under them; the border pieces sit ABOVE the rows, or bars that rounded a
-- pixel outward covered the one- and two-pixel rims. The pieces are cut on
-- the fill area's edges, as the Resource Bars cut it; the rim's rounded
-- corners are kept clear by each row's clip to the stock bar shape
-- (ApplyRowChrome), not by the slicing.
-- Each piece: atlas u0, u1, v0, v1 (pixels), under-the-rows flag, and its
-- TOPLEFT / BOTTOMRIGHT as { column point, x, y }.
local PANEL_R = 0
local PANEL_PIECES = {
    -- corners
    { 0, 2 + PANEL_R, 0, 3 + PANEL_R, false, { "TOPLEFT", -2, 3 }, { "TOPLEFT", PANEL_R, -PANEL_R } },
    { 126 - PANEL_R, 132, 0, 3 + PANEL_R, false, { "TOPRIGHT", -PANEL_R, 3 }, { "TOPRIGHT", 6, -PANEL_R } },
    { 0, 2 + PANEL_R, 12 - PANEL_R, 19, false, { "BOTTOMLEFT", -2, PANEL_R }, { "BOTTOMLEFT", PANEL_R, -7 } },
    {
        126 - PANEL_R,
        132,
        12 - PANEL_R,
        19,
        false,
        { "BOTTOMRIGHT", -PANEL_R, PANEL_R },
        { "BOTTOMRIGHT", 6, -7 },
    },
    -- edges
    { 2 + PANEL_R, 126 - PANEL_R, 0, 3, false, { "TOPLEFT", PANEL_R, 3 }, { "TOPRIGHT", -PANEL_R, 0 } },
    {
        2 + PANEL_R,
        126 - PANEL_R,
        12,
        19,
        false,
        { "BOTTOMLEFT", PANEL_R, 0 },
        { "BOTTOMRIGHT", -PANEL_R, -7 },
    },
    { 0, 2, 3 + PANEL_R, 12 - PANEL_R, false, { "TOPLEFT", -2, -PANEL_R }, { "BOTTOMLEFT", 0, PANEL_R } },
    {
        126,
        132,
        3 + PANEL_R,
        12 - PANEL_R,
        false,
        { "TOPRIGHT", 0, -PANEL_R },
        { "BOTTOMRIGHT", 6, PANEL_R },
    },
    -- centre (backdrop)
    { 2, 126, 3, 12, true, { "TOPLEFT", 0, 0 }, { "BOTTOMRIGHT", 0, 0 } },
}

-- The Blizzard and Classic WoW UI styles frame the bar column as ONE box: the
-- panel (Blizzard) or the vanilla frame (Classic) round every shown row, plus
-- a one-pixel black divider centred in each gap, between the rows and between
-- the pips of a pip row (the Resource Bars' group separators). geo = the shown
-- rows bottom to top, { key, x, y, h } from the root's bottom-left; w = row
-- width; gap = Element Spacing; spacing = Stack Spacing. Nothing is built for
-- the modern style.
local function ApplyColumnChrome(Stl, L, geo, wid, gap, spacing)
    local root = Stl.root
    local column = root._edrCol
    local chrome = L.chrome
    if not chrome or #geo == 0 then
        if column then
            column:Hide()
        end
        return
    end
    if not column then
        column = CreateFrame("Frame", nil, root)
        column:EnableMouse(false)
        -- Art over every row's fill, pips and borders; under the speed text.
        column.art = CreateFrame("Frame", nil, column)
        column.art:EnableMouse(false)
        column.art:SetAllPoints(column)
        column.seps = {}
        root._edrCol = column
    end
    -- Under the rows (the panel is their backdrop); the art level above them.
    local rowLevel = Stl.speed:GetFrameLevel()
    column:SetFrameLevel(upper(0, rowLevel - 1))
    column.art:SetFrameLevel(rowLevel + 9)

    local first, last = geo[1], geo[#geo]
    column:ClearAllPoints()
    column:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", first.x, first.y)
    column:SetSize(wid, last.y + last.h - first.y)
    column:Show()

    -- Blizzard panel.
    local details = chrome == "blizzard" and not column.panel and C_Texture.GetAtlasInfo(BLIZZ_CHROME.bg)
    if details then
        column.panel = {}
        local file = details.file or details.filename
        local l, r, t, b =
            details.leftTexCoord, details.rightTexCoord, details.topTexCoord, details.bottomTexCoord
        for _, pc in ipairs(PANEL_PIECES) do
            local texture = pc[5] and column:CreateTexture(nil, "BACKGROUND", nil, -2)
                or column.art:CreateTexture(nil, "OVERLAY", nil, 0)
            texture:SetSnapToPixelGrid(false)
            texture:SetTexelSnappingBias(0)
            texture:SetTexture(file)
            texture:SetTexCoord(
                l + (r - l) * pc[1] / 132,
                l + (r - l) * pc[2] / 132,
                t + (b - t) * pc[3] / 19,
                t + (b - t) * pc[4] / 19
            )
            local p1, p2 = pc[6], pc[7]
            texture:SetPoint("TOPLEFT", column, p1[1], p1[2], p1[3])
            texture:SetPoint("BOTTOMRIGHT", column, p2[1], p2[2], p2[3])
            column.panel[#column.panel + 1] = texture
        end
    end
    if column.panel then
        for idx = 1, #column.panel do
            column.panel[idx]:SetShown(chrome == "blizzard")
        end
    end

    -- Classic WoW UI frame.
    local CF = CludesUI.ClassicFrame
    if chrome == "classic" and CF and not column.classic then
        column.classic = CF.Create(column.art, "OVERLAY", 2)
    end
    if column.classic then
        CF.SetShown(column.classic, chrome == "classic")
        if chrome == "classic" then
            CF.Seat(column.classic, column, L.frameK, false)
        end
    end

    -- Dividers, one physical pixel thick, snapped to whole pixels.
    local PPdr = CludesUI.PP
    local px = ((PPdr and PPdr.perfect) or 1) / column:GetEffectiveScale()
    local function Centre(span)
        return floor(((span - px) / 2) / px + 0.5) * px
    end
    local num = 0
    local function Sep(posX, posY, sw, sh)
        num = num + 1
        local t = column.seps[num]
        if not t then
            t = column.art:CreateTexture(nil, "OVERLAY", nil, 3)
            t:SetColorTexture(0, 0, 0, 1)
            t:SetSnapToPixelGrid(false)
            t:SetTexelSnappingBias(0)
            column.seps[num] = t
        end
        t:ClearAllPoints()
        t:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", posX, posY)
        t:SetSize(sw, sh)
        t:Show()
    end
    for idx, g in ipairs(geo) do
        if idx > 1 then
            local below = geo[idx - 1]
            Sep(g.x, below.y + below.h + Centre(gap), wid, px)
        end
        local rowFrame = g.key == "sky" and Stl.stack or g.key == "sw" and Stl.sw
        if rowFrame then
            for jdx = 1, #rowFrame.pips - 1 do
                local pipTex = rowFrame.pips[jdx]
                Sep(g.x + pipTex._edrX + pipTex._edrW + Centre(spacing), g.y, px, g.h)
            end
        end
    end
    for idx = num + 1, #column.seps do
        column.seps[idx]:Hide()
    end
end

-- Whirling Surge icon per bar style: Blizzard = action button frame, rounded
-- mask and rounded swipe; Classic WoW UI = the vanilla slot ring; modern = the
-- plain cropped square. The cooldown text is lifted above any frame.
local function ApplyIconArt(Stl, chrome)
    local f = Stl.icon
    if chrome and not f.artFrame then
        f.artFrame = CreateFrame("Frame", nil, f)
        f.artFrame:SetAllPoints(f)
        f.artFrame:SetFrameLevel(f.cd:GetFrameLevel() + 1)
        f.textFrame:SetFrameLevel(f.cd:GetFrameLevel() + 2)
    end
    if chrome == "blizzard" and not f.blizzFrame then
        f.blizzFrame = f.artFrame:CreateTexture(nil, "OVERLAY")
        f.blizzFrame:SetAtlas(BLIZZ_ICON.frame)
        f.blizzFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
        f.blizzMask = f:CreateMaskTexture()
        f.blizzMask:SetAtlas(BLIZZ_ICON.mask, false, nil, nil, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        f.blizzMask:SetPoint("CENTER", f.tex, "CENTER")
        -- The mask art has transparent padding around its rounded square, so it
        -- is sized from its own atlas (scaled like the icon), not to the icon.
        local details = C_Texture.GetAtlasInfo(BLIZZ_ICON.mask)
        f.blizzMaskW = details and details.width or BLIZZ_ICON.iconSize
        f.blizzMaskH = details and details.height or BLIZZ_ICON.iconSize
    end
    if chrome == "classic" and not f.classicRing then
        f.classicRing = f.artFrame:CreateTexture(nil, "OVERLAY")
        f.classicRing:SetTexture(BLIZZ_ICON.ring)
        f.classicRing:SetSnapToPixelGrid(false)
        f.classicRing:SetTexelSnappingBias(0)
    end

    local dim = f:GetHeight()
    if f.blizzFrame then
        local on = chrome == "blizzard"
        f.blizzFrame:SetShown(on)
        if on then
            local s = dim / BLIZZ_ICON.iconSize
            f.blizzFrame:SetSize(BLIZZ_ICON.frameW * s, BLIZZ_ICON.frameH * s)
            f.blizzMask:SetSize(f.blizzMaskW * s, f.blizzMaskH * s)
        end
        if on ~= (f.blizzMasked or false) then
            if on then
                f.tex:AddMaskTexture(f.blizzMask)
                f.cd:SetSwipeTexture(BLIZZ_ICON.swipe)
            else
                f.tex:RemoveMaskTexture(f.blizzMask)
                f.cd:SetSwipeTexture("")
            end
            f.blizzMasked = on
        end
    end
    if f.classicRing then
        local on = chrome == "classic"
        f.classicRing:SetShown(on)
        if on then
            f.classicRing:ClearAllPoints()
            f.classicRing:SetPoint("CENTER", f, "CENTER", 0, -dim / 36)
            f.classicRing:SetSize(dim * 66 / 36, dim * 66 / 36)
        end
    end
    if chrome == "blizzard" then
        f.tex:SetTexCoord(0, 1, 0, 1)
    else
        f.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
end

-- Resolve a classic atlas by its texture-kit name, falling back to the "-2x"
-- member name in case a client only registers that one. nil = art missing.
local classicAtlasCache = {}
local function ClassicAtlas(suffix)
    local hit = classicAtlasCache[suffix]
    if hit ~= nil then
        return hit or nil
    end
    local name = CLASSIC.kit .. "_" .. suffix
    if not C_Texture.GetAtlasInfo(name) then
        name = name .. "-2x"
        if not C_Texture.GetAtlasInfo(name) then
            name = false
        end
    end
    classicAtlasCache[suffix] = name
    return name or nil
end

local function SetClassicArt(texture, suffix, wid, hgt)
    local atlas = ClassicAtlas(suffix)
    if atlas then
        texture:SetAtlas(atlas)
    end
    texture:SetSize(wid, hgt)
    return atlas
end

local function AddAlphaStep(group, from, to, duration, sequence, endDelay)
    local a = group:CreateAnimation("Alpha")
    a:SetFromAlpha(from)
    a:SetToAlpha(to)
    a:SetDuration(duration)
    a:SetOrder(sequence)
    if endDelay then
        a:SetEndDelay(endDelay)
    end
end

-- One gem. Frame levels stand in for the template's draw layers: background on
-- the cell, fill bar one level up, frame/spark/flash one above that.
local function CreateClassicCell(hostFrame)
    local C = CLASSIC
    local cellFrame = CreateFrame("Frame", nil, hostFrame)
    cellFrame:SetSize(C.cellW, C.cellH)

    cellFrame.bg = cellFrame:CreateTexture(nil, "BACKGROUND")
    cellFrame.bg:SetPoint("CENTER")
    SetClassicArt(cellFrame.bg, "background", C.bgW, C.bgH)

    local barFrame = CreateFrame("StatusBar", nil, cellFrame)
    barFrame:SetOrientation("VERTICAL")
    barFrame:SetMinMaxValues(0, 1)
    barFrame:SetValue(0)
    barFrame:SetPoint("CENTER")
    barFrame:SetSize(C.fillW, C.fillH)
    barFrame:SetFrameLevel(cellFrame:GetFrameLevel() + 1)
    cellFrame.bar = barFrame
    cellFrame.fillAtlas = ClassicAtlas("fill")
    cellFrame.fillFullAtlas = ClassicAtlas("fillfull")
    if cellFrame.fillAtlas then
        barFrame:SetStatusBarTexture(cellFrame.fillAtlas)
    end
    cellFrame.isFull = false

    local flipAtlas = ClassicAtlas("fill_flipbook")
    if flipAtlas then
        cellFrame.flip = barFrame:CreateTexture(nil, "OVERLAY")
        cellFrame.flip:SetAllPoints(barFrame)
        cellFrame.flip:SetAtlas(flipAtlas)
        cellFrame.flip:Hide()
        cellFrame.flipMask = barFrame:CreateMaskTexture()
        cellFrame.flipMask:SetAtlas(
            "AlphaMask2",
            true,
            nil,
            nil,
            "CLAMPTOBLACKADDITIVE",
            "CLAMPTOBLACKADDITIVE"
        )
        cellFrame.flipMask:SetPoint("TOP", barFrame:GetStatusBarTexture(), "TOP", 0, 0)
        cellFrame.flip:AddMaskTexture(cellFrame.flipMask)
        cellFrame.flipAnim = cellFrame.flip:CreateAnimationGroup()
        cellFrame.flipAnim:SetLooping("REPEAT")
        local fb = cellFrame.flipAnim:CreateAnimation("FlipBook")
        fb:SetDuration(1.2)
        fb:SetFlipBookRows(5)
        fb:SetFlipBookColumns(4)
        fb:SetFlipBookFrames(20)
    end

    local ov = CreateFrame("Frame", nil, cellFrame)
    ov:SetAllPoints(cellFrame)
    ov:SetFrameLevel(cellFrame:GetFrameLevel() + 2)
    cellFrame.overlay = ov

    cellFrame.spark = ov:CreateTexture(nil, "OVERLAY")
    cellFrame.spark:SetBlendMode("ADD")
    SetClassicArt(cellFrame.spark, "spark", C.sparkW, C.sparkH)
    cellFrame.spark:SetPoint("CENTER", barFrame:GetStatusBarTexture(), "TOP", 0, 0)
    cellFrame.spark:Hide()
    local maskAtlas = ClassicAtlas("mask")
    if maskAtlas then
        local maskTex = ov:CreateMaskTexture()
        maskTex:SetAtlas(maskAtlas, false, nil, nil, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        maskTex:SetSize(C.maskW, C.maskH)
        maskTex:SetPoint("CENTER", cellFrame, "CENTER")
        cellFrame.spark:AddMaskTexture(maskTex)
    end

    cellFrame.frame = ov:CreateTexture(nil, "OVERLAY", nil, 1)
    cellFrame.frame:SetPoint("CENTER", cellFrame, "CENTER")
    SetClassicArt(cellFrame.frame, "frame", C.frameW, C.frameH)

    cellFrame.flash = ov:CreateTexture(nil, "OVERLAY", nil, 1)
    cellFrame.flash:SetBlendMode("ADD")
    cellFrame.flash:SetPoint("CENTER", cellFrame, "CENTER")
    SetClassicArt(cellFrame.flash, "flash", C.frameW, C.frameH)
    cellFrame.flash:SetAlpha(0)

    cellFrame.flashAnim = cellFrame.flash:CreateAnimationGroup()
    cellFrame.flashAnim:SetToFinalAlpha(true)
    AddAlphaStep(cellFrame.flashAnim, 0, 1, 0.5, 1)
    AddAlphaStep(cellFrame.flashAnim, 1, 0, 0.5, 2)

    cellFrame.pulseAnim = cellFrame.flash:CreateAnimationGroup()
    cellFrame.pulseAnim:SetToFinalAlpha(true)
    cellFrame.pulseAnim:SetLooping("REPEAT")
    AddAlphaStep(cellFrame.pulseAnim, 0, 1, 1.5, 1)
    AddAlphaStep(cellFrame.pulseAnim, 1, 0, 1.5, 2, 0.8)

    return cellFrame
end

-- The gem row at 1x: mirrored decor, six cells, decor. Built on first use only,
-- so the modern style never pays for it.
local function EnsureClassicFrame(Stl)
    if Stl.classic then
        return Stl.classic
    end
    local C = CLASSIC
    local f = CreateFrame("Frame", nil, Stl.root)
    f:SetSize(CLASSIC_W, CLASSIC_H)

    f.decorL = f:CreateTexture(nil, "ARTWORK")
    SetClassicArt(f.decorL, "decor", C.decorW, C.decorH)
    f.decorL:SetTexCoord(1, 0, 0, 1)
    f.decorL:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -C.decorTop)
    f.decorR = f:CreateTexture(nil, "ARTWORK")
    SetClassicArt(f.decorR, "decor", C.decorW, C.decorH)
    f.decorR:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -C.decorTop)

    f.cells = {}
    local posX = C.decorW + C.edgePad
    for idx = 1, SKYRIDING_PIPS do
        local cellFrame = CreateClassicCell(f)
        cellFrame:SetPoint("TOPLEFT", f, "TOPLEFT", posX, 0)
        -- Level above the decor so the end gems overlap the wings, as they did.
        cellFrame:SetFrameLevel(f:GetFrameLevel() + 1)
        cellFrame.bar:SetFrameLevel(cellFrame:GetFrameLevel() + 1)
        cellFrame.overlay:SetFrameLevel(cellFrame:GetFrameLevel() + 2)
        f.cells[idx] = cellFrame
        posX = posX + C.cellW
    end
    Stl.classic = f
    return f
end

-------------------------------------------------------------------------------
--  Build / Rebuild / Redraw
-------------------------------------------------------------------------------
local function LayoutPips(widget, pipCount, width, height, spacing)
    -- Distribute in whole PHYSICAL-pixel units (PP.mult), not whole UI-coordinate
    -- units. 1 UI-unit only equals 1 physical pixel at the "pixel perfect" scale -- at
    -- any other UI Scale, flooring to whole UI-units left a fractional remainder
    -- unassigned, so the last pip fell short of the frame's actual right edge (the
    -- "extra spacing between charges and Whirling Surge" report, reproducible at UI
    -- scales where that leftover doesn't round away to ~0).
    local PPdr = CludesUI and CludesUI.PP
    local px = (PPdr and PPdr.mult and PPdr.mult > 0) and PPdr.mult or 1
    local widthAvail = upper(0, width - (pipCount - 1) * spacing)
    -- If the whole row doesn't span even one physical pixel (a very small bar at a low
    -- UI Scale, where px itself is large), snapping to whole physical-pixel units would
    -- floor every pip to 0 width -- pips vanishing entirely is worse than the sub-pixel
    -- gap this fix targets. Fall back to plain UI-unit distribution (pre-fix behavior)
    -- in that degenerate case so pips stay visible, just not perfectly pixel-snapped.
    if widthAvail < px then
        px = 1
    end
    local totalUnits = floor(widthAvail / px + 1e-6)
    -- Cumulative boundary = floor(totalUnits * i / pipCount), not a fixed
    -- remainder lumped onto the first N pips. The two pip rows (6 and 3
    -- charges) share the same widthAvail and pipCount is an exact multiple
    -- between them, so this formula lands every 2nd Skyward Ascent divider
    -- on the exact same physical pixel as a Second Wind divider -- a
    -- per-row remainder would drift the two rows' dividers by up to 1px
    -- relative to each other even though they should align.
    local posX = 0
    local prevBoundary = 0
    for idx = 1, pipCount do
        local boundary = floor(totalUnits * idx / pipCount + 1e-6)
        local thisW = (boundary - prevBoundary) * px
        prevBoundary = boundary
        local pipTex = widget.pips[idx]
        pipTex:ClearAllPoints()
        pipTex:SetPoint("TOPLEFT", widget, "TOPLEFT", posX, 0)
        pipTex:SetSize(thisW, height)
        pipTex._edrX, pipTex._edrW = posX, thisW
        posX = posX + thisW + spacing
    end
end

-- The frames of one set under its root (CreateFrame order is the live HUD's).
local function NewSet(root, bordered)
    local Stl = { root = root, bordered = bordered }
    Stl.speed = CreateSpeedBar(root)
    EnsureBorder(Stl, Stl.speed)

    Stl.stack = CreateStackFrame(root, SKYRIDING_PIPS)
    for idx = 1, SKYRIDING_PIPS do
        EnsureBorder(Stl, Stl.stack.pips[idx])
    end

    Stl.sw = CreateStackFrame(root, SECONDWIND_PIPS)
    for idx = 1, SECONDWIND_PIPS do
        EnsureBorder(Stl, Stl.sw.pips[idx])
    end

    Stl.icon = CreateWhirlingSurgeIcon(root)
    EnsureBorder(Stl, Stl.icon)
    return Stl
end

local liveSet

function Build()
    if rootFrame then
        return
    end
    rootFrame = CreateFrame("Frame", "CludesUIDragonRidingAnchor", UIParent)
    rootFrame:SetFrameStrata("MEDIUM")
    rootFrame:Hide()
    rootFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

    liveSet = NewSet(rootFrame, borderedFrames)
    speedBar, stackFrame, swFrame, wsIcon = liveSet.speed, liveSet.stack, liveSet.sw, liveSet.icon

    Rebuild()
end

-- Sizes and anchors one set for the layout L.
local function LayoutSet(Stl, p, L)
    Stl.root:SetSize(L.totalW, L.totalH)

    -- Column rows, bottom to top, the column centred on the icon. Rows not in
    -- the layout are hidden; rows that stay are never hidden and re-shown.
    -- Every frame here is SHOWN BEFORE it is anchored, sized and has its pips
    -- laid out: a row or icon re-anchored while hidden and shown afterwards
    -- (Vigor Style Bars <-> Classic Gems, a row or the icon toggled back on)
    -- drew its pips piled up or not at all until a later pass.
    local rowFrames = { speed = Stl.speed, sky = Stl.stack, sw = Stl.sw }
    local inLayout = {}
    for _, key in ipairs(L.rows) do
        inLayout[key] = true
    end
    for key, f in pairs(rowFrames) do
        if not inLayout[key] then
            f:Hide()
        end
    end
    local spacing = p.stackSpacing
    local clusterX = PPSnap((L.totalW - L.clusterW) / 2)
    local posY = L.colY + L.ov
    local geo = {}
    for idx, key in ipairs(L.rows) do
        local f = rowFrames[key]
        local hgt = p[ROW_FIELD[key]]
        local rx, ry = clusterX + L.padX, posY
        geo[idx] = { key = key, x = rx, y = ry, h = hgt }
        f:Show()
        f:ClearAllPoints()
        f:SetPoint("BOTTOMLEFT", Stl.root, "BOTTOMLEFT", rx, ry)
        f:SetSize(p.width, hgt)
        if key == "sky" then
            LayoutPips(Stl.stack, SKYRIDING_PIPS, p.width, hgt, spacing)
        elseif key == "sw" then
            LayoutPips(Stl.sw, SECONDWIND_PIPS, p.width, hgt, spacing)
        end
        posY = posY + hgt + p.gap
    end
    ApplyColumnChrome(Stl, L, geo, p.width, p.gap, spacing)

    local glyph = Stl.icon
    if L.icon then
        glyph:Show()
        glyph:ClearAllPoints()
        glyph:SetPoint(
            "BOTTOMLEFT",
            Stl.root,
            "BOTTOMLEFT",
            clusterX + L.colW + (L.colW > 0 and p.gap or 0),
            L.iconY
        )
        glyph:SetSize(L.iconSize, L.iconSize)
    else
        glyph:Hide()
    end
    ApplyIconArt(Stl, L.chrome)

    if L.classic then
        local f = EnsureClassicFrame(Stl)
        f:Show()
        f:SetScale(L.scale)
        f:ClearAllPoints()
        -- Offsets on a scaled frame are in its own units.
        f:SetPoint("TOPLEFT", Stl.root, "TOPLEFT", PPSnap((L.totalW - L.classicW) / 2) / L.scale, 0)
    elseif Stl.classic then
        Stl.classic:Hide()
    end
end

-- Textures, colours, texts, borders and bevels of one set.
local function PaintSet(Stl, p, L)
    -- Apply bar texture to all StatusBars
    local texPath = CludesUI.ResolveTexturePath(
        mod.EDR_BAR_TEXTURES,
        p.barTexture or "none",
        "Interface\\Buttons\\WHITE8x8"
    )
    local speed, stack, sw, glyph = Stl.speed, Stl.stack, Stl.sw, Stl.icon
    speed:SetStatusBarTexture(texPath)
    for idx = 1, SKYRIDING_PIPS do
        stack.pips[idx]:SetStatusBarTexture(texPath)
    end
    for idx = 1, SECONDWIND_PIPS do
        sw.pips[idx]:SetStatusBarTexture(texPath)
    end

    local c = p.normalColor
    speed:SetStatusBarColor(c.r, c.g, c.b, c.a)
    speed.bg:SetColorTexture(p.speedBarBg.r, p.speedBarBg.g, p.speedBarBg.b, p.speedBarBg.a)

    local tickFrac = (p.thrillThreshold or 0) / (p.maxSpeed > 0 and p.maxSpeed or 1)
    tickFrac = upper(0, min(1, tickFrac))
    speed.tick:ClearAllPoints()
    speed.tick:SetPoint("TOP", speed, "TOPLEFT", p.width * tickFrac, 0)
    speed.tick:SetPoint("BOTTOM", speed, "BOTTOMLEFT", p.width * tickFrac, 0)
    speed.tick:SetWidth(2)
    speed.tick:SetColorTexture(p.tickColor.r, p.tickColor.g, p.tickColor.b, p.tickColor.a)

    ApplyFont(speed.text, p.speedText.size)
    speed.text:ClearAllPoints()
    speed.text:SetPoint(
        p.speedText.justify or "CENTER",
        speed,
        p.speedText.justify or "CENTER",
        p.speedText.offsetX or 0,
        p.speedText.offsetY or 0
    )
    speed.text:SetJustifyH(p.speedText.justify or "CENTER")
    speed.text:SetShown(p.speedText.enabled ~= false)

    for idx = 1, SKYRIDING_PIPS do
        local pipTex = stack.pips[idx]
        pipTex:SetStatusBarColor(p.skyridingFilled.r, p.skyridingFilled.g, p.skyridingFilled.b, 1)
        pipTex.bg:SetColorTexture(p.skyridingBg.r, p.skyridingBg.g, p.skyridingBg.b, p.skyridingBg.a)
    end

    for idx = 1, SECONDWIND_PIPS do
        local pipTex = sw.pips[idx]
        pipTex:SetStatusBarColor(p.secondWindFilled.r, p.secondWindFilled.g, p.secondWindFilled.b, 1)
        pipTex.bg:SetColorTexture(p.secondWindBg.r, p.secondWindBg.g, p.secondWindBg.b, p.secondWindBg.a)
    end

    ApplyFont(glyph.text, p.whirlingSurgeText.size)
    glyph.text:ClearAllPoints()
    glyph.text:SetPoint(
        p.whirlingSurgeText.justify or "CENTER",
        glyph,
        p.whirlingSurgeText.justify or "CENTER",
        p.whirlingSurgeText.offsetX or 0,
        p.whirlingSurgeText.offsetY or 0
    )
    glyph.text:SetJustifyH(p.whirlingSurgeText.justify or "CENTER")
    glyph.text:SetShown(p.whirlingSurgeText.enabled ~= false)

    ApplyBordersAll(Stl, L)

    -- Bar style bevel (the column frame is laid out by Rebuild).
    ApplyRowChrome(speed, L.chrome, p.width, p.speedHeight)
    ApplyRowChrome(stack, L.chrome, p.width, p.skyridingHeight)
    ApplyRowChrome(sw, L.chrome, p.width, p.secondWindHeight)
end

local RepaintSample

function Rebuild()
    if not rootFrame then
        return
    end
    local p = saved.profile
    local L = ComputeLayout(p)
    LayoutSet(liveSet, p, L)
    classicFrame = liveSet.classic
    Redraw(L)
    ApplyPos()
    UpdateVisibility()
end

-- L = the layout Rebuild already computed, or nil to compute it here.
function Redraw(L)
    if not rootFrame then
        return
    end
    local p = saved.profile
    L = L or ComputeLayout(p)
    PaintSet(liveSet, p, L)

    skyridingDirty = true
    secondWindDirty = true
    whirlingDirty = true
    lastSkyCur, lastSkyProgress = -1, -1
    lastSwCur, lastSwProgress = -1, -1
    lastClassicCur, lastClassicProgress = -1, -1
    lastSoundCur = -1
    lastCdStart, lastCdDur = -1, -1
    -- Settings applied: the repaint above rides the tick, so arm it if shown.
    SyncTick()
    -- Every settings path ends here (options, Unlock Mode mover, profile
    -- switch), so the options header's sample follows them all.
    RepaintSample()
end

-------------------------------------------------------------------------------
--  Options header sample
--  A second frame set, built the first time the Skyriding page asks, laid out
--  and painted by the same passes as the live HUD, then filled with fixed
--  values: 650% speed, 4 of 6 charges and a half-filled fifth, 2 of 3 Second
--  Wind, a held 12 s Whirling Surge cooldown. It reads no game state, has no
--  OnUpdate and no events, and is never an unlock element.
-------------------------------------------------------------------------------
local sampleSet, samplePlace
local SAMPLE_SPEED_PCT = 650

local function PaintSample()
    local p = saved and saved.profile
    if not (sampleSet and p) then
        return
    end
    local Stl = sampleSet
    local L = ComputeLayout(p)
    -- The options page scales and anchors the root first: the pixel snaps
    -- below read the scale the sample shows at.
    if samplePlace then
        samplePlace(Stl.root, L.totalW, L.totalH)
    end
    LayoutSet(Stl, p, L)
    PaintSet(Stl, p, L)

    local frac = (p.maxSpeed > 0) and (SAMPLE_SPEED_PCT / p.maxSpeed) or 0
    Stl.speed:SetValue(upper(0, min(1, frac)))
    Stl.speed.text:SetText(FormatSpeedText(SAMPLE_SPEED_PCT))
    local c = (p.thrillColorToggle and SAMPLE_SPEED_PCT >= (p.thrillThreshold or 0)) and p.thrillColor
        or p.normalColor
    Stl.speed:SetStatusBarColor(c.r, c.g, c.b, c.a)

    if L.classic then
        -- Still gems: no pulse, flash or swirl in the header.
        for idx, cellFrame in ipairs(Stl.classic.cells) do
            cellFrame.flashAnim:Stop()
            cellFrame.pulseAnim:Stop()
            cellFrame.flash:SetAlpha(0)
            if cellFrame.flipAnim then
                cellFrame.flipAnim:Stop()
                cellFrame.flip:Hide()
            end
            SetClassicFull(cellFrame, idx <= 4)
            local val = (idx <= 4 and 1) or (idx == 5 and 0.5) or 0
            cellFrame.bar:SetValue(val)
            cellFrame.spark:SetShown(val > 0 and val < 1)
        end
    else
        ApplyPipRow(Stl.stack.pips, SKYRIDING_PIPS, 4, SKYRIDING_PIPS, 0.5, -1, -1, p.skyridingFilled, 0.4)
    end
    ApplyPipRow(Stl.sw.pips, SECONDWIND_PIPS, 2, SECONDWIND_PIPS, 0.6, -1, -1, p.secondWindFilled, 0.4)

    local nowTime = GetTime()
    Stl.icon.cd:SetCooldown(nowTime - 8, 20)
    Stl.icon.cd:Pause()
    Stl.icon.text:SetText(FormatCooldownText(12))
end

function RepaintSample()
    if sampleSet and sampleSet.root:IsVisible() then
        PaintSample()
    end
end

-- Shows the sample under parent and paints it. place(root, w, h) runs before
-- every paint with the HUD's size in its own units, to scale and anchor the
-- root. Returns the root, or nil before the profile exists.
function mod.EDR_ShowSample(hostFrame, place)
    if not (saved and saved.profile) then
        return nil
    end
    if not sampleSet then
        sampleSet = NewSet(CreateFrame("Frame", nil, hostFrame), {})
    end
    local root = sampleSet.root
    root:SetParent(hostFrame)
    root:SetFrameStrata(hostFrame:GetFrameStrata())
    root:SetFrameLevel(hostFrame:GetFrameLevel() + 5)
    root:Show()
    samplePlace = place
    PaintSample()
    return root
end
mod.EDR_RepaintSample = RepaintSample

-------------------------------------------------------------------------------
--  Unlock mode
-------------------------------------------------------------------------------
local function SavePos(_, anchorPoint, relPoint, posX, posY)
    if not anchorPoint then
        return
    end
    local p = saved and saved.profile
    if not p then
        return
    end
    p.unlockPos = { point = anchorPoint, relPoint = relPoint or anchorPoint, x = posX, y = posY }
    if not CludesUI._unlockActive and rootFrame then
        rootFrame:ClearAllPoints()
        rootFrame:SetPoint(anchorPoint, UIParent, relPoint or anchorPoint, posX, posY)
    end
end
local function LoadPos()
    local p = saved and saved.profile
    local pos = p and p.unlockPos
    if not pos then
        return nil
    end
    return { point = pos.point, relPoint = pos.relPoint or pos.point, x = pos.x, y = pos.y }
end
local function ClearPos()
    local p = saved and saved.profile
    if not p then
        return
    end
    p.unlockPos = nil
end
function ApplyPos()
    local p = saved and saved.profile
    local pos = p and p.unlockPos
    if not pos or not rootFrame then
        return
    end
    rootFrame:ClearAllPoints()
    rootFrame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x, pos.y)
end

-- Profile-swap refresh: re-read DB and rebuild the HUD.
_G._CUDR_Rebuild = function()
    if not rootFrame then
        return
    end
    Rebuild()
    ApplyPos()
end

function RegisterUnlockElements()
    if not CludesUI or not CludesUI.RegisterUnlockElements then
        return
    end
    local MK = CludesUI.MakeUnlockElement
    CludesUI:RegisterUnlockElements({
        MK({
            key = "EDR_Cluster",
            label = "Dragon Riding",
            group = "Dragon Riding",
            order = 700,
            getFrame = function()
                return rootFrame
            end,
            getSize = function()
                local L = ComputeLayout(saved.profile)
                return L.totalW, L.totalH
            end,
            setWidth = function(_, wid)
                local p = saved.profile
                local L = ComputeLayout(p)
                if L.colW == 0 then
                    -- No bars in the column: the handle scales the gems, if any.
                    if L.classic then
                        p.classicScale = upper(0.5, min(2, floor(wid / CLASSIC_W * 100 + 0.5) / 100))
                        Rebuild()
                    end
                    return
                end
                -- Where getSize reports an even-pixel total, a restore of that
                -- exact size is a no-op; any other width (a drag, a width
                -- match) sizes the cluster as given, so a match converges.
                if L.totalW ~= L.rawW and abs(wid - L.totalW) < 0.01 then
                    return
                end
                local clusterW = wid
                -- A gem row wider than the bars sets the width by itself; the
                -- column only follows the handle once it is dragged past it.
                if L.classicW > L.clusterW and clusterW <= L.classicW then
                    return
                end
                local iconPart = L.icon and (p.gap + L.iconSize) or 0
                p.width = upper(60, PPSnap(clusterW - iconPart - 2 * L.padX))
                Rebuild()
            end,
            -- Height is built from independently-sized bars (Second Wind, modern
            -- charges, Speed) plus fixed gaps, the icon beside them, and the classic
            -- gem row when that style is on -- there's no single "height" field to
            -- write. Scale the icon and the shown bars by the same factor toward
            -- the requested total, matching how the Options page's size sliders
            -- combine, then clamp each to its own Options-page slider range
            -- (bars 2-24 / 2-24 / 4-40, icon 16-80) so a drag can't push one to
            -- zero or past its usable size.
            setHeight = function(_, hgt)
                local p = saved.profile
                local L = ComputeLayout(p)
                if L.clusterH == 0 then
                    if L.classic then
                        p.classicScale = upper(0.5, min(2, floor(hgt / CLASSIC_H * 100 + 0.5) / 100))
                        Rebuild()
                    end
                    return
                end
                -- A restore of getSize's even-pixel total is a no-op (see setWidth).
                if L.totalH ~= L.rawH and abs(hgt - L.totalH) < 0.01 then
                    return
                end
                local newTotalH = PPSnap(hgt)
                local classicPart = L.classic and (L.classicH + p.gap) or 0
                local k = upper(8, newTotalH - classicPart) / L.clusterH
                if L.icon and p.iconSize then
                    p.iconSize = upper(16, min(80, floor(L.iconSize * k + 0.5)))
                end
                local rowList = L.rows
                if #rowList == 0 then
                    Rebuild()
                    return
                end
                -- Bars top to bottom (Second Wind, charges, speed): the order
                -- the leftover pass below hands a remainder out in.
                local barList, loSum = {}, 0
                for idx = #rowList, 1, -1 do
                    local field = ROW_FIELD[rowList[idx]]
                    local lo = ROW_RANGE[field][1]
                    barList[#barList + 1] = { field = field, lo = lo, hi = ROW_RANGE[field][2] }
                    loSum = loSum + lo
                end
                -- The column takes the whole new height when it is the
                -- cluster's tallest part, else its scaled share, in whole
                -- units. Each row's frame rim is a fixed size, not scaled with
                -- the bar. The CludesUI bars filling the whole cluster take
                -- the exact pixel-snapped height, as they always have.
                local whole = L.colH == L.clusterH
                local colTarget = whole and (newTotalH - classicPart) or L.colH * k
                local targetSum = colTarget - (#rowList - 1) * p.gap - 2 * L.ov
                if L.chrome or L.classic or not whole then
                    targetSum = floor(targetSum + 0.5)
                end
                targetSum = upper(loSum, targetSum)

                local oldSum = 0
                for _, b in ipairs(barList) do
                    b.old = p[b.field]
                    oldSum = oldSum + b.old
                end
                if oldSum <= 0 then
                    -- Corrupted/legacy profile (e.g. hand-edited SavedVariables)
                    -- with every shown height at/under zero: reset to defaults so
                    -- the control self-heals instead of silently no-op'ing forever.
                    for _, b in ipairs(barList) do
                        p[b.field] = DB_DEFAULTS.profile[b.field]
                    end
                    Rebuild()
                    return
                end

                local scale = targetSum / oldSum
                for _, b in ipairs(barList) do
                    b.new = upper(b.lo, min(b.hi, floor(b.old * scale + 0.5)))
                end

                -- A bar already at its min/max absorbs none of a further shrink/grow,
                -- so plain proportional scaling can leave the resize handle feeling
                -- stuck once one or two bars saturate. Hand any leftover delta to
                -- whichever bar(s) still have headroom instead of discarding it
                -- (bounded to one pass per bar so this always terminates).
                for _ = 1, #barList do
                    local sum = 0
                    for _, b in ipairs(barList) do
                        sum = sum + b.new
                    end
                    local leftover = targetSum - sum
                    if leftover == 0 then
                        break
                    end
                    local openBars = {}
                    for _, b in ipairs(barList) do
                        if (leftover > 0 and b.new < b.hi) or (leftover < 0 and b.new > b.lo) then
                            openBars[#openBars + 1] = b
                        end
                    end
                    if #openBars == 0 then
                        break
                    end
                    local shareF = leftover / #openBars
                    local share = shareF >= 0 and floor(shareF + 0.5) or -floor(-shareF + 0.5)
                    if share == 0 then
                        -- Leftover doesn't divide evenly across every open bar
                        -- this pass (e.g. 1px across 3 bars): give the whole
                        -- remainder to just the first bar with headroom rather
                        -- than rounding a fractional share up and applying it
                        -- to all of them, which would overshoot the target.
                        local b = openBars[1]
                        b.new = upper(b.lo, min(b.hi, b.new + leftover))
                    else
                        for _, b in ipairs(openBars) do
                            b.new = upper(b.lo, min(b.hi, b.new + share))
                        end
                    end
                end

                for _, b in ipairs(barList) do
                    p[b.field] = b.new
                end
                Rebuild()
            end,
            savePos = SavePos,
            loadPos = LoadPos,
            clearPos = ClearPos,
            applyPos = ApplyPos,
        }),
    })
end

-------------------------------------------------------------------------------
--  Init
-------------------------------------------------------------------------------
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if not CludesUI or not CludesUI.Lite then
        return
    end

    saved = CludesUI.Lite.NewDB("CludesUIDragonRidingDB", DB_DEFAULTS)
    mod.edrDB = saved
    -- Latch the bar art from the login profile (even while the HUD is off,
    -- so a profile switch before its first build still compares against it).
    mod.EDR_Style()

    -- If disabled, skip all frame creation and event registration.
    -- Rebuild (called from options toggle) will lazy-init if needed.
    if not saved.profile.enabled then
        return
    end

    Build()

    evtFrame = CreateFrame("Frame")
    evtFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    evtFrame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
    evtFrame:RegisterEvent("PLAYER_CAN_GLIDE_CHANGED")
    evtFrame:RegisterEvent("PLAYER_IS_GLIDING_CHANGED")
    evtFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    evtFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    evtFrame:SetScript("OnEvent", function(_, evt)
        if evt == "SPELL_UPDATE_CHARGES" then
            skyridingDirty = true
            secondWindDirty = true
            SyncTick()
            return
        elseif evt == "SPELL_UPDATE_COOLDOWN" then
            whirlingDirty = true
            SyncTick()
            return
        elseif evt == "PLAYER_IS_GLIDING_CHANGED" then
            local isGliding = C_PlayerInfo.GetGlidingInfo()
            _gliding = isGliding == true
            SyncTick()
            return
        elseif evt == "PLAYER_ENTERING_WORLD" then
            skyridingDirty = true
            secondWindDirty = true
            whirlingDirty = true
        end
        UpdateVisibility()
    end)

    C_Timer.After(0.5, function()
        RegisterUnlockElements()
        ApplyPos()
    end)
end)

-- Exports for options page. Rebuild handles lazy-init if module was disabled at login.
mod.edrRebuild = function()
    if not saved then
        return
    end
    if not rootFrame then
        -- First enable after being disabled at login: full init
        Build()
        if not evtFrame then
            evtFrame = CreateFrame("Frame")
            evtFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
            evtFrame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
            evtFrame:RegisterEvent("PLAYER_CAN_GLIDE_CHANGED")
            evtFrame:RegisterEvent("PLAYER_IS_GLIDING_CHANGED")
            evtFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
            evtFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
            evtFrame:SetScript("OnEvent", function(_, evt)
                if evt == "SPELL_UPDATE_CHARGES" then
                    skyridingDirty = true
                    secondWindDirty = true
                    SyncTick()
                    return
                elseif evt == "SPELL_UPDATE_COOLDOWN" then
                    whirlingDirty = true
                    SyncTick()
                    return
                elseif evt == "PLAYER_IS_GLIDING_CHANGED" then
                    local isGliding = C_PlayerInfo.GetGlidingInfo()
                    _gliding = isGliding == true
                    SyncTick()
                    return
                elseif evt == "PLAYER_ENTERING_WORLD" then
                    skyridingDirty = true
                    secondWindDirty = true
                    whirlingDirty = true
                end
                UpdateVisibility()
            end)
        end
        RegisterUnlockElements()
    end
    Rebuild()
end
mod.edrRedraw = function()
    Redraw()
end
-- The icon's automatic size (as tall as every bar of the vigor style, frame
-- rim included), whatever Icon Size holds: the options show it while Auto Size
-- is on and hand it over when Auto Size is turned off.
mod.edrIconSize = function()
    local p = saved and saved.profile
    if not p then
        return 34
    end
    local L = ComputeLayout(p)
    return StackHeight(p, L.classic and STYLE_ROWS_GEMS or STYLE_ROWS_BARS, L.ov)
end
