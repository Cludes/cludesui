if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
if CUI and CUI.IS_FOREVER then return end -- no skyriding on WoW Forever: no DB, no events, no HUD; its options tab is not registered there
-------------------------------------------------------------------------------
--  CludesUIBlizzardSkin_DragonRiding.lua - Skyriding HUD
-------------------------------------------------------------------------------
local _, mod = ...

-- Upvalues
local floor, min, max, abs = math.floor, math.min, math.max, math.abs
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
mod.EDR_BAR_TEXTURES = (CUI.BuildBarTextureTables())

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
local CLASSIC_H = max(CLASSIC.cellH, CLASSIC.decorTop + CLASSIC.decorH)
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
local rootHost, speedBar, stackFrame, swFrame, whirlIcon, classicFrame
local skyridingStale = true
local secondWindStale = true
local whirlStale = true
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
local eventFrame -- event frame (created on first enable)
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
        local profile = saved and saved.profile
        if not profile then return "cui" end
        val = (profile.useClassicStyle and "classic") or (profile.useBlizzardStyle and "blizzard") or "cui"
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
    if instanceType == "raid" or instanceType == "party" then return true end
    return false
end

local function GetSkyridingSpeed()
    local gliding, _, forwardSpeed = C_PlayerInfo.GetGlidingInfo()
    if not gliding then
        smoothedSpeed = smoothedSpeed * (1 - SPEED_EMA_ALPHA)
        -- Floor the landing decay to exactly 0 so the final empty-bar state
        -- paints once and the tick can then disarm (TickWanted reads > 0).
        if smoothedSpeed < 0.01 then smoothedSpeed = 0 end
        return false, smoothedSpeed
    end
    smoothedSpeed = smoothedSpeed + SPEED_EMA_ALPHA * ((forwardSpeed or 0) - smoothedSpeed)
    return true, smoothedSpeed
end

-- Forward declarations
local function Build() end
local function RebuildBar() end
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
    return skyridingStale
        or secondWindStale
        or whirlStale
        or ((_gliding or smoothedSpeed > 0) and saved.profile.showSpeed ~= false)
end
local function SyncTicker()
    if not rootHost then return end
    if rootHost:IsShown() and (TickWanted() or (CUI and CUI._unlockActive)) then
        rootHost:SetScript("OnUpdate", OnUpdate)
    else
        rootHost:SetScript("OnUpdate", nil)
    end
end

-- Register/unregister high-frequency spell events based on HUD visibility.
-- These fire for ALL spells globally, so we only listen when actively showing.
-- SPELL_UPDATE_COOLDOWN feeds only the Whirling Surge icon, so it is also off
-- while the icon is hidden; every Rebuild ends in UpdateVisibility, which
-- re-syncs it when Show Whirling Surge flips.
local function RegisterSpellEvents()
    if not eventFrame then return end
    if not _spellEventsRegistered then
        eventFrame:RegisterEvent("SPELL_UPDATE_CHARGES")
        _spellEventsRegistered = true
    end
    local wantCd = saved.profile.showWhirlingSurge ~= false
    if wantCd ~= _cdEventRegistered then
        if wantCd then
            eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
        else
            eventFrame:UnregisterEvent("SPELL_UPDATE_COOLDOWN")
        end
        _cdEventRegistered = wantCd
    end
end
local function UnregisterSpellEvents()
    if not eventFrame then return end
    if _spellEventsRegistered then
        eventFrame:UnregisterEvent("SPELL_UPDATE_CHARGES")
        _spellEventsRegistered = false
    end
    if _cdEventRegistered then
        eventFrame:UnregisterEvent("SPELL_UPDATE_COOLDOWN")
        _cdEventRegistered = false
    end
end

-------------------------------------------------------------------------------
--  Visibility
-------------------------------------------------------------------------------
local function IsOnSkyridingMount()
    if not CUI.IsPlayerMountedLike() then return false end
    local _, canGlide = C_PlayerInfo.GetGlidingInfo()
    return canGlide == true
end

-- Hidden -> shown (the normal path and Unlock Mode's force-show alike). The
-- spell events are off while the HUD is hidden, so every section repaints
-- once; charges that refilled meanwhile are not a live gain, so they repaint
-- without the full-charge chime or the gem flash.
local function MarkReshown()
    skyridingStale, secondWindStale, whirlStale = true, true, true
    lastSoundCur, lastClassicCur = -1, -1
end

function UpdateVisibility()
    if not rootHost then return end
    local profile = saved and saved.profile
    if not profile or not profile.enabled or IsInLockedContent() then
        rootHost:Hide()
        rootHost:SetScript("OnUpdate", nil)
        UnregisterSpellEvents()
        return
    end
    local wasShown = rootHost:IsShown()
    if CUI and CUI._unlockActive then
        if not wasShown then MarkReshown() end
        rootHost:Show()
        rootHost:SetScript("OnUpdate", OnUpdate)
        RegisterSpellEvents()
        return
    end
    local onSky = IsOnSkyridingMount()
    local hideCombat = profile.hideInCombat and UnitAffectingCombat("player")
    local visible = onSky and not hideCombat
    rootHost:SetShown(visible)
    if visible then
        if not wasShown then MarkReshown() end
        -- Seed the airborne flag from a fresh read (covers /reload mid-flight
        -- and any edge missed while hidden), then arm only if there is work.
        local gliding = C_PlayerInfo.GetGlidingInfo()
        _gliding = gliding == true
        SyncTicker()
        RegisterSpellEvents()
    else
        rootHost:SetScript("OnUpdate", nil)
        UnregisterSpellEvents()
    end
end

-- Re-check real visibility when Unlock Mode exits. UpdateVisibility()
-- force-shows the HUD while CludesUI._unlockActive is true (so it can be
-- edited even off-mount), but nothing previously re-ran it on exit, so
-- dismounting during Unlock Mode left it stuck visible until an unrelated
-- mount/dismount happened to call UpdateVisibility() again. Called from
-- CUI_UnlockMode.lua's exit path, matching the Quest Tracker's same pattern.
_G._CUDR_UpdateVisibility = function() UpdateVisibility() end

-------------------------------------------------------------------------------
--  OnUpdate
-------------------------------------------------------------------------------
local function ApplyPipRow(
    pips,
    pipCount,
    current,
    maxC,
    fillProgress,
    lastCur,
    lastProgress,
    isFilled,
    bgAlpha
)
    if current ~= lastCur then
        for idx = 1, pipCount do
            local pipTex = pips[idx]
            if idx <= current then
                pipTex:SetValue(1)
                pipTex:SetStatusBarColor(isFilled.r, isFilled.g, isFilled.b, 1)
            elseif idx == current + 1 and current < maxC then
                pipTex:SetValue(fillProgress)
                pipTex:SetStatusBarColor(isFilled.r, isFilled.g, isFilled.b, bgAlpha)
            else
                pipTex:SetValue(0)
                pipTex:SetStatusBarColor(isFilled.r, isFilled.g, isFilled.b, 1)
            end
        end
        return current, fillProgress
    elseif current < maxC and abs(fillProgress - lastProgress) > 0.005 then
        local pipTex = pips[current + 1]
        if pipTex then pipTex:SetValue(fillProgress) end
        return current, fillProgress
    end
    return lastCur, lastProgress
end

-- Per-cell state for the classic gems, mirroring UIWidgetFillUpFrameTemplateMixin:
-- a full gem flashes once when it completes, the filling gem pulses and plays the
-- swirl flipbook, the spark rides the fill line.
local function SetClassicFilling(pipCell, fillProgress)
    pipCell.bar:SetValue(fillProgress)
    pipCell.spark:SetShown(fillProgress > 0 and fillProgress < 1)
    if pipCell.flipAnim then
        if fillProgress > 0 then
            if not pipCell.flipAnim:IsPlaying() then
                pipCell.flip:Show()
                pipCell.flipAnim:Play()
            end
        else
            pipCell.flip:Hide()
            pipCell.flipAnim:Stop()
        end
    end
end

local function SetClassicFull(pipCell, full)
    if pipCell.isFull == full then return end
    pipCell.isFull = full
    local atlas = full and pipCell.fillFullAtlas or pipCell.fillAtlas
    if atlas then pipCell.bar:SetStatusBarTexture(atlas) end
    pipCell.spark:ClearAllPoints()
    pipCell.spark:SetPoint("CENTER", pipCell.bar:GetStatusBarTexture(), "TOP", 0, 0)
    if pipCell.flipMask then
        pipCell.flipMask:ClearAllPoints()
        pipCell.flipMask:SetPoint("TOP", pipCell.bar:GetStatusBarTexture(), "TOP", 0, 0)
    end
end

local function ApplyClassicRow(current, maxC, fillProgress)
    local cells = classicFrame.cells
    if current ~= lastClassicCur then
        -- lastClassicCur is -1 after every Redraw, so the first paint never flashes.
        local gained = lastClassicCur >= 0 and current > lastClassicCur
        for idx = 1, SKYRIDING_PIPS do
            local pipCell = cells[idx]
            local isFull = idx <= current
            local isFilling = idx == current + 1 and current < maxC
            SetClassicFull(pipCell, isFull)
            if isFull then
                pipCell.bar:SetValue(1)
                pipCell.spark:Hide()
                pipCell.pulseAnim:Stop()
                if pipCell.flipAnim then
                    pipCell.flipAnim:Stop()
                    pipCell.flip:Hide()
                end
                if gained and idx > lastClassicCur then pipCell.flashAnim:Restart() end
            elseif isFilling then
                pipCell.flashAnim:Stop()
                pipCell.flash:SetAlpha(0)
                pipCell.pulseAnim:Play()
                SetClassicFilling(pipCell, fillProgress)
            else
                pipCell.flashAnim:Stop()
                pipCell.pulseAnim:Stop()
                pipCell.flash:SetAlpha(0)
                SetClassicFilling(pipCell, 0)
            end
        end
        return current, fillProgress
    elseif current < maxC and abs(fillProgress - lastClassicProgress) > 0.005 then
        local pipCell = cells[current + 1]
        if pipCell then SetClassicFilling(pipCell, fillProgress) end
        return current, fillProgress
    end
    return lastClassicCur, lastClassicProgress
end

local function FormatSpeedText(speedPct) return format("%d%%", floor(speedPct + 0.5)) end

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
    if elapsed < UPDATE_THROTTLE then return end
    elapsed = 0

    local profile = saved.profile

    -- Speed poll only while airborne or while the landing decay drains; the
    -- decay floors to exactly 0 so the final empty-bar state paints once.
    -- Nothing to poll while the speed bar is hidden.
    if (_gliding or smoothedSpeed > 0) and profile.showSpeed ~= false then
        local _, curSpeed = GetSkyridingSpeed()
        local speedPct = curSpeed / BASE_RUN_SPEED * 100
        local fraction = (profile.maxSpeed > 0) and (speedPct / profile.maxSpeed) or 0
        fraction = max(0, min(1, fraction))
        if fraction ~= lastSpeedApplied then
            speedBar:SetValue(fraction)
            if profile.speedText.enabled ~= false then speedBar.text:SetText(FormatSpeedText(speedPct)) end
            local aboveThrill = (speedPct >= (profile.thrillThreshold or 0))
            local color = (profile.thrillColorToggle and aboveThrill) and profile.thrillColor
                or profile.normalColor
            speedBar:SetStatusBarColor(color.r, color.g, color.b, color.a)
            lastSpeedApplied = fraction
        end
    end -- speed-poll gate

    if skyridingStale then
        local details = C_Spell.GetSpellCharges(SPELL.SKYWARD_ASCENT)
        local current = details and details.currentCharges or 0
        local maxC = details and details.maxCharges or SKYRIDING_PIPS
        local fillProgress = 0
        if details and details.cooldownDuration and details.cooldownDuration > 0 then
            local e = GetTime() - (details.cooldownStartTime or 0)
            fillProgress = max(0, min(1, e / details.cooldownDuration))
        end
        if profile.chargeSound and lastSoundCur >= 0 and current > lastSoundCur and FULL_CHARGE_SOUND then
            PlaySound(FULL_CHARGE_SOUND)
        end
        lastSoundCur = current
        if profile.vigorStyle == "gems" and classicFrame then
            lastClassicCur, lastClassicProgress = ApplyClassicRow(current, maxC, fillProgress)
        else
            lastSkyCur, lastSkyProgress = ApplyPipRow(
                stackFrame.pips,
                SKYRIDING_PIPS,
                current,
                maxC,
                fillProgress,
                lastSkyCur,
                lastSkyProgress,
                profile.skyridingFilled,
                0.4
            )
        end
        skyridingStale = (current < maxC)
    end

    if secondWindStale and profile.showSecondWind == false then
        secondWindStale = false -- hidden; showing it again redraws it
    elseif secondWindStale then
        local details = C_Spell.GetSpellCharges(SPELL.SECOND_WIND)
        local current = details and details.currentCharges or 0
        local maxC = details and details.maxCharges or SECONDWIND_PIPS
        local fillProgress = 0
        if details and details.cooldownDuration and details.cooldownDuration > 0 then
            local e = GetTime() - (details.cooldownStartTime or 0)
            fillProgress = max(0, min(1, e / details.cooldownDuration))
        end
        lastSwCur, lastSwProgress = ApplyPipRow(
            swFrame.pips,
            SECONDWIND_PIPS,
            current,
            maxC,
            fillProgress,
            lastSwCur,
            lastSwProgress,
            profile.secondWindFilled,
            0.4
        )
        secondWindStale = (current < maxC)
    end

    if whirlStale and profile.showWhirlingSurge == false then
        whirlStale = false -- hidden; showing it again redraws it
    elseif whirlStale then
        local details = C_Spell.GetSpellCooldown(SPELL.WHIRLING_SURGE)
        local start = details and details.startTime or 0
        local dur = details and details.duration or 0
        if dur > 1.5 then
            if start ~= lastCdStart or dur ~= lastCdDur then
                whirlIcon.cd:SetCooldown(start, dur)
                lastCdStart, lastCdDur = start, dur
            end
            local remaining = start + dur - GetTime()
            if remaining > 0 then
                if profile.whirlingSurgeText.enabled ~= false then
                    whirlIcon.text:SetText(FormatCooldownText(remaining))
                end
                whirlStale = true
            else
                whirlIcon.text:SetText("")
                whirlStale = false
            end
        else
            if lastCdDur ~= 0 then
                whirlIcon.cd:Clear()
                whirlIcon.text:SetText("")
                lastCdStart, lastCdDur = 0, 0
            end
            whirlStale = false
        end
    end

    -- Self-disarm once every section settled and we are grounded; every dirty
    -- writer and the gliding edge re-arm through SyncTick.
    if not TickWanted() then SyncTicker() end
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

local function SnapPx(val)
    local PPdr = CUI and CUI.PP
    if PPdr and PPdr.Snap then return PPdr.Snap(val) end
    return floor(val + 0.5)
end
-- Round a frame dimension UP to a whole number of physical pixel PAIRS. The HUD
-- is centre-anchored, so an odd pixel count (or a fraction, which the classic
-- gems' half-unit art sizes produced) puts every edge inside it half a pixel
-- off the grid.
local function SnapEven(val)
    local PPdr = CUI and CUI.PP
    local m = PPdr and PPdr.mult or 1
    if m <= 0 then m = 1 end
    return math.ceil(val / (2 * m) - 1e-6) * 2 * m
end

-- Room the bar column reserves round itself for its frame's VISIBLE rim:
-- vertical (each side) and horizontal (each end). The Blizzard and Classic WoW
-- UI styles frame the column as one box (the Resource Bars' Border Around All
-- look), so the rim sits outside the column only. Above and below differ
-- slightly; each side takes half of their sum. 0,0 with no frame (modern).
local function ArtOverhang(chromeFrame, keyName)
    if chromeFrame == "blizzard" then
        local C = BLIZZ_CHROME
        return SnapPx((C.rimT + C.rimB) / 2), SnapPx(C.rimX)
    elseif chromeFrame == "classic" then
        local CF = CUI.ClassicFrame
        if not CF then return 0, 0 end
        local padW, padH = CF.Pad(keyName)
        return SnapPx(padH / 2), SnapPx(padW / 2)
    end
    return 0, 0
end

-- Height a list of rows occupies stacked with gaps, including the frame rim
-- (ov, from ArtOverhang).
local function StackHeight(profile, rowList, overlay)
    if #rowList == 0 then return 0 end
    local total = 2 * overlay
    for idx, key in ipairs(rowList) do
        total = total + profile[ROW_FIELD[key]] + (idx > 1 and profile.gap or 0)
    end
    return total
end

-- Classic WoW UI frame scale: the Border Size percentage (nil = the shared
-- default), as the Resource Bars' Classic WoW UI bars take it.
local function ClassicFrameK(profile)
    local CF = CUI.ClassicFrame
    return CF and CF.ScaleK(profile.classicFrameSize) or 1
end

-- Where everything goes for the current settings. The bar column stacks bottom
-- to top (speed, charges, Second Wind) and the Whirling Surge icon sits on its
-- right, the shorter of the two centred on the taller; the classic gem row sits
-- above both. The icon is as tall as the full column (every bar of the style)
-- unless given its own size. Classic gems replace the charge row rather than
-- sitting in the column, and the Blizzard and Classic WoW UI bar styles frame
-- each row, which needs room around it.
local function ComputeLayout(profile)
    local classic = profile.vigorStyle == "gems"
    local style = mod.EDR_Style()
    local chromeFrame = style ~= "cui" and style or nil
    local keyName = chromeFrame == "classic" and ClassicFrameK(profile) or 1

    local rowList = {}
    if profile.showSpeed ~= false then rowList[#rowList + 1] = "speed" end
    if not classic then rowList[#rowList + 1] = "sky" end
    if profile.showSecondWind ~= false then rowList[#rowList + 1] = "sw" end

    local overlay, padX = ArtOverhang(chromeFrame, keyName)
    local colH = StackHeight(profile, rowList, overlay)
    local colW = #rowList > 0 and (profile.width + 2 * padX) or 0

    local iconTex = profile.showWhirlingSurge ~= false
    local iconSize = 0
    if iconTex then
        iconSize = profile.iconSize
        if not iconSize then
            -- Every bar of the style, shown or not.
            iconSize = StackHeight(profile, classic and STYLE_ROWS_GEMS or STYLE_ROWS_BARS, overlay)
        end
    end
    local clusterW = colW + (iconTex and ((colW > 0 and profile.gap or 0) + iconSize) or 0)
    local clusterH = max(colH, iconSize)

    local scale = profile.classicScale or 1
    local classicW = classic and SnapPx(CLASSIC_W * scale) or 0
    local classicH = classic and SnapPx(CLASSIC_H * scale) or 0
    local rawW = max(clusterW, classicW)
    local rawH = clusterH + classicH + ((classic and clusterH > 0) and profile.gap or 0)
    -- The even-pixel rounding is for the stock frames and the classic gems
    -- only: the CludesUI bars keep their exact size, so their root frame
    -- and the unlock size stay what they always were.
    local even = chromeFrame or classic

    return {
        rows = rowList,
        classic = classic,
        chrome = chromeFrame,
        frameK = keyName,
        ov = overlay,
        scale = scale,
        colH = colH,
        colW = colW,
        padX = padX,
        colY = SnapPx((clusterH - colH) / 2),
        icon = iconTex,
        iconSize = iconSize,
        iconY = SnapPx((clusterH - iconSize) / 2),
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
local function ApplyFont(fontStr, size)
    if not fontStr then return end
    local font = CUI.GetFontPath("blizzardSkin") or "Fonts/FRIZQT__.TTF"
    local flag = CUI.GetFontOutlineFlag("blizzardSkin") or ""
    CUI.PrimeFontShadow(fontStr, flag == "")
    fontStr:SetFont(font, size or 12, flag)
end

local function CreateSolidTexture(hostFrame, layer, sublevel, red, green, blue, a)
    local texture = hostFrame:CreateTexture(nil, layer or "BACKGROUND", nil, sublevel or 0)
    texture:SetColorTexture(red or 0, green or 0, blue or 0, a or 1)
    texture:SetSnapToPixelGrid(false)
    texture:SetTexelSnappingBias(0)
    return texture
end

local borderedFrames = {}

-- A frame set is one HUD's frames: { root, speed, stack, sw, icon, classic,
-- bordered }. The live HUD is one set, the options header's sample another;
-- the layout and paint passes below take the set they draw.
local function EnsureBorder(Set, widget)
    if not widget or widget._edrBorderAdded then return end
    if not (CUI and CUI.PP and CUI.PP.CreateBorder) then return end
    CUI.PP.CreateBorder(widget, 0, 0, 0, 1, 1, "OVERLAY", 7)
    widget._edrBorderAdded = true
    Set.bordered[#Set.bordered + 1] = widget
end

local function ApplyBorderEdges(widget, hideL, hideR, hideT, hideB)
    local Pix = CUI and CUI.PP
    local edges = Pix and Pix.GetBorders and Pix.GetBorders(widget)
    if not edges then return end
    edges._hideLeft = hideL or nil
    edges._hideRight = hideR or nil
    edges._hideTop = hideT or nil
    edges._hideBottom = hideB or nil
end

local function ApplyBordersAll(Set, Lay)
    local Pix = CUI and CUI.PP
    if not Pix then return end
    local profile = saved.profile
    local color = profile.borderColor
    -- The Blizzard and Classic WoW UI bar styles draw their own frames instead.
    local thick = Lay.chrome and 0 or (profile.borderThickness or 0)
    for _, frame in ipairs(Set.bordered) do
        if thick > 0 then
            Pix.UpdateBorder(frame, thick, color.r, color.g, color.b, color.a)
            Pix.ShowBorder(frame)
        else
            Pix.HideBorder(frame)
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
        local gapTouch = profile.gap == 0
        local stackTouch = profile.stackSpacing == 0
        local iconLo, iconHi = Lay.iconY - 0.01, Lay.iconY + Lay.iconSize + 0.01
        local rowList = Lay.rows
        local posY = Lay.colY + Lay.ov
        for idx, key in ipairs(rowList) do
            local hgt = profile[ROW_FIELD[key]]
            local iconTouch = gapTouch and Lay.icon and posY >= iconLo and posY + hgt <= iconHi
            posY = posY + hgt + profile.gap
            local hideB = gapTouch and idx > 1 and rowList[idx - 1] ~= "speed"
            if key == "speed" then
                ApplyBorderEdges(Set.speed, false, iconTouch, gapTouch and idx < #rowList, hideB)
            else
                local pips, num = Set.stack.pips, SKYRIDING_PIPS
                if key == "sw" then
                    pips, num = Set.sw.pips, SECONDWIND_PIPS
                end
                for jdx = 1, num do
                    local hideR = (stackTouch and jdx < num) or (iconTouch and jdx == num)
                    ApplyBorderEdges(pips[jdx], false, hideR, false, hideB)
                end
            end
        end
        -- Re-snap so the updated hide flags take effect immediately.
        for _, frame in ipairs(Set.bordered) do
            Pix.SetBorderSize(frame, thick)
        end
    end
end

local function CreateSpeedBar(hostFrame)
    local frame = CreateFrame("StatusBar", nil, hostFrame)
    frame:SetMinMaxValues(0, 1)
    frame:SetValue(0)
    frame:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    frame.bg = CreateSolidTexture(frame, "BACKGROUND", 0)
    frame.bg:SetAllPoints(frame)
    frame.tick = CreateSolidTexture(frame, "OVERLAY", 5)
    -- The pip stacks/icon nest their bar textures one parent level deeper
    -- than the speed bar itself (stackFrame -> pip, wsIcon -> tex/cd), and
    -- frame level always outranks draw layer across frames. A plain OVERLAY
    -- fontstring parented directly to f would render behind that nested
    -- content, so give the text its own frame raised well above every level
    -- used anywhere in this HUD (same pattern as CreateWhirlingSurgeIcon's
    -- textFrame).
    frame.textFrame = CreateFrame("Frame", nil, frame)
    frame.textFrame:SetAllPoints(frame)
    frame.textFrame:SetFrameLevel(frame:GetFrameLevel() + 10)
    frame.text = frame.textFrame:CreateFontString(nil, "OVERLAY")
    return frame
end

local function CreateStackFrame(hostFrame, pipCount)
    local frame = CreateFrame("Frame", nil, hostFrame)
    frame.pips = {}
    for idx = 1, pipCount do
        local pipTex = CreateFrame("StatusBar", nil, frame)
        pipTex:SetMinMaxValues(0, 1)
        pipTex:SetValue(0)
        pipTex:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
        pipTex.bg = CreateSolidTexture(pipTex, "BACKGROUND", 0)
        pipTex.bg:SetAllPoints(pipTex)
        frame.pips[idx] = pipTex
    end
    return frame
end

local function CreateWhirlingSurgeIcon(hostFrame)
    local frame = CreateFrame("Frame", nil, hostFrame)
    frame.tex = frame:CreateTexture(nil, "ARTWORK")
    frame.tex:SetAllPoints(frame)
    local details = C_Spell.GetSpellInfo(SPELL.WHIRLING_SURGE)
    local iconFile = details and details.iconID or 135860
    frame.tex:SetTexture(iconFile)
    frame.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    frame.cd = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    frame.cd:SetAllPoints(frame)
    frame.cd:SetDrawEdge(false)
    frame.cd:SetHideCountdownNumbers(true)
    frame.textFrame = CreateFrame("Frame", nil, frame)
    frame.textFrame:SetAllPoints(frame)
    frame.textFrame:SetFrameLevel(frame.cd:GetFrameLevel() + 1)
    frame.text = frame.textFrame:CreateFontString(nil, "OVERLAY")
    return frame
end

-- Inner bevel over a Blizzard-style row: gradient strips darkening the long
-- edges and both ends (the Resource Bars' bevel), so the user's texture reads
-- recessed in the panel.
local function LayoutBevel(shade, wid, hgt)
    local shine = shade.strips
    if not shine then
        shine = {}
        for idx = 1, 4 do
            local tex = shade:CreateTexture(nil, "OVERLAY", nil, -3)
            tex:SetTexture("Interface\\Buttons\\WHITE8X8")
            tex:SetSnapToPixelGrid(false)
            tex:SetTexelSnappingBias(0)
            shine[idx] = tex
        end
        shade.strips = shine
    end
    local a = max(2, floor(hgt * 0.2))
    local button = max(1, floor(hgt * 0.1))
    local e = max(2, floor(wid * 0.15))
    for idx = 1, 4 do
        shine[idx]:ClearAllPoints()
    end
    shine[1]:SetGradient("VERTICAL", SHADE_CLEAR, SHADE_TOP)
    shine[1]:SetPoint("TOPLEFT")
    shine[1]:SetPoint("TOPRIGHT")
    shine[1]:SetHeight(a)
    shine[2]:SetGradient("VERTICAL", SHADE_BOTTOM, SHADE_CLEAR)
    shine[2]:SetPoint("BOTTOMLEFT")
    shine[2]:SetPoint("BOTTOMRIGHT")
    shine[2]:SetHeight(button)
    shine[3]:SetGradient("HORIZONTAL", SHADE_END, SHADE_CLEAR)
    shine[3]:SetPoint("TOPLEFT")
    shine[3]:SetPoint("BOTTOMLEFT")
    shine[3]:SetWidth(e)
    shine[4]:SetGradient("HORIZONTAL", SHADE_CLEAR, SHADE_END)
    shine[4]:SetPoint("TOPRIGHT")
    shine[4]:SetPoint("BOTTOMRIGHT")
    shine[4]:SetWidth(e)
end

-- Add or move a mask on a texture, once per texture object (AddMaskTexture is
-- additive, and a status bar texture swap can mint a new fill object).
-- mask nil takes it off.
local function MaskTex(texture, mask)
    if not texture or texture._edrMask == mask then return end
    if texture._edrMask then texture:RemoveMaskTexture(texture._edrMask) end
    if mask then texture:AddMaskTexture(mask) end
    texture._edrMask = mask
end

-- Per-row part of the Blizzard style, as the Resource Bars keep it on every
-- bar, grouped or not: the row's fill, backing and bevel clipped to the stock
-- fill's rounded footprint (one clip across a pip row, so only its end pips
-- round off), which keeps the row inside the panel rim's rounded corners, and
-- the bevel over the row (above the pips and their borders, under the speed
-- text at +10). Built on first use; hidden and un-clipped in the other styles.
local function ApplyRowChrome(owner, chromeFrame, wid, hgt)
    local on = chromeFrame == "blizzard"
    local shade = owner._edrShade
    if on and not shade then
        shade = CreateFrame("Frame", nil, owner)
        shade:SetAllPoints(owner)
        shade:SetFrameLevel(owner:GetFrameLevel() + 9)
        owner._edrShade = shade
        if C_Texture.GetAtlasInfo(BLIZZ_CHROME.fill) then
            owner._edrMask = owner:CreateMaskTexture()
            owner._edrMask:SetAtlas(BLIZZ_CHROME.fill)
            owner._edrMask:SetAllPoints(owner)
        end
    end
    if not shade then return end
    shade:SetShown(on)
    if on then LayoutBevel(shade, wid, hgt) end
    local mask = on and owner._edrMask or nil
    if owner.pips then
        for idx = 1, #owner.pips do
            local pipTex = owner.pips[idx]
            MaskTex(pipTex:GetStatusBarTexture(), mask)
            MaskTex(pipTex.bg, mask)
        end
    else
        MaskTex(owner:GetStatusBarTexture(), mask)
        MaskTex(owner.bg, mask)
    end
    if shade.strips then
        for idx = 1, #shade.strips do
            MaskTex(shade.strips[idx], mask)
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
local PANEL_RADIUS = 0
local PANEL_PIECES = {
    -- corners
    {
        0,
        2 + PANEL_RADIUS,
        0,
        3 + PANEL_RADIUS,
        false,
        { "TOPLEFT", -2, 3 },
        { "TOPLEFT", PANEL_RADIUS, -PANEL_RADIUS },
    },
    {
        126 - PANEL_RADIUS,
        132,
        0,
        3 + PANEL_RADIUS,
        false,
        { "TOPRIGHT", -PANEL_RADIUS, 3 },
        { "TOPRIGHT", 6, -PANEL_RADIUS },
    },
    {
        0,
        2 + PANEL_RADIUS,
        12 - PANEL_RADIUS,
        19,
        false,
        { "BOTTOMLEFT", -2, PANEL_RADIUS },
        { "BOTTOMLEFT", PANEL_RADIUS, -7 },
    },
    {
        126 - PANEL_RADIUS,
        132,
        12 - PANEL_RADIUS,
        19,
        false,
        { "BOTTOMRIGHT", -PANEL_RADIUS, PANEL_RADIUS },
        { "BOTTOMRIGHT", 6, -7 },
    },
    -- edges
    {
        2 + PANEL_RADIUS,
        126 - PANEL_RADIUS,
        0,
        3,
        false,
        { "TOPLEFT", PANEL_RADIUS, 3 },
        { "TOPRIGHT", -PANEL_RADIUS, 0 },
    },
    {
        2 + PANEL_RADIUS,
        126 - PANEL_RADIUS,
        12,
        19,
        false,
        { "BOTTOMLEFT", PANEL_RADIUS, 0 },
        { "BOTTOMRIGHT", -PANEL_RADIUS, -7 },
    },
    {
        0,
        2,
        3 + PANEL_RADIUS,
        12 - PANEL_RADIUS,
        false,
        { "TOPLEFT", -2, -PANEL_RADIUS },
        { "BOTTOMLEFT", 0, PANEL_RADIUS },
    },
    {
        126,
        132,
        3 + PANEL_RADIUS,
        12 - PANEL_RADIUS,
        false,
        { "TOPRIGHT", 0, -PANEL_RADIUS },
        { "BOTTOMRIGHT", 6, PANEL_RADIUS },
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
local function ApplyColumnChrome(Set, Lay, geo, wid, gap, spacing)
    local rootTbl = Set.root
    local colour = rootTbl._edrCol
    local chromeFrame = Lay.chrome
    if not chromeFrame or #geo == 0 then
        if colour then colour:Hide() end
        return
    end
    if not colour then
        colour = CreateFrame("Frame", nil, rootTbl)
        colour:EnableMouse(false)
        -- Art over every row's fill, pips and borders; under the speed text.
        colour.art = CreateFrame("Frame", nil, colour)
        colour.art:EnableMouse(false)
        colour.art:SetAllPoints(colour)
        colour.seps = {}
        rootTbl._edrCol = colour
    end
    -- Under the rows (the panel is their backdrop); the art level above them.
    local rowLevel = Set.speed:GetFrameLevel()
    colour:SetFrameLevel(max(0, rowLevel - 1))
    colour.art:SetFrameLevel(rowLevel + 9)

    local first, last = geo[1], geo[#geo]
    colour:ClearAllPoints()
    colour:SetPoint("BOTTOMLEFT", rootTbl, "BOTTOMLEFT", first.x, first.y)
    colour:SetSize(wid, last.y + last.h - first.y)
    colour:Show()

    -- Blizzard panel.
    local details = chromeFrame == "blizzard" and not colour.panel and C_Texture.GetAtlasInfo(BLIZZ_CHROME.bg)
    if details then
        colour.panel = {}
        local file = details.file or details.filename
        local left, right, top, bottom =
            details.leftTexCoord, details.rightTexCoord, details.topTexCoord, details.bottomTexCoord
        for _, pc in ipairs(PANEL_PIECES) do
            local texture = pc[5] and colour:CreateTexture(nil, "BACKGROUND", nil, -2)
                or colour.art:CreateTexture(nil, "OVERLAY", nil, 0)
            texture:SetSnapToPixelGrid(false)
            texture:SetTexelSnappingBias(0)
            texture:SetTexture(file)
            texture:SetTexCoord(
                left + (right - left) * pc[1] / 132,
                left + (right - left) * pc[2] / 132,
                top + (bottom - top) * pc[3] / 19,
                top + (bottom - top) * pc[4] / 19
            )
            local p1, p2 = pc[6], pc[7]
            texture:SetPoint("TOPLEFT", colour, p1[1], p1[2], p1[3])
            texture:SetPoint("BOTTOMRIGHT", colour, p2[1], p2[2], p2[3])
            colour.panel[#colour.panel + 1] = texture
        end
    end
    if colour.panel then
        for idx = 1, #colour.panel do
            colour.panel[idx]:SetShown(chromeFrame == "blizzard")
        end
    end

    -- Classic WoW UI frame.
    local CF = CUI.ClassicFrame
    if chromeFrame == "classic" and CF and not colour.classic then
        colour.classic = CF.Create(colour.art, "OVERLAY", 2)
    end
    if colour.classic then
        CF.SetShown(colour.classic, chromeFrame == "classic")
        if chromeFrame == "classic" then CF.Seat(colour.classic, colour, Lay.frameK, false) end
    end

    -- Dividers, one physical pixel thick, snapped to whole pixels.
    local PPdr = CUI.PP
    local pixel = ((PPdr and PPdr.perfect) or 1) / colour:GetEffectiveScale()
    local function Centre(span) return floor(((span - pixel) / 2) / pixel + 0.5) * pixel end
    local num = 0
    local function Sep(posX, posY, sw, shine)
        num = num + 1
        local t = colour.seps[num]
        if not t then
            t = colour.art:CreateTexture(nil, "OVERLAY", nil, 3)
            t:SetColorTexture(0, 0, 0, 1)
            t:SetSnapToPixelGrid(false)
            t:SetTexelSnappingBias(0)
            colour.seps[num] = t
        end
        t:ClearAllPoints()
        t:SetPoint("BOTTOMLEFT", rootTbl, "BOTTOMLEFT", posX, posY)
        t:SetSize(sw, shine)
        t:Show()
    end
    for idx, g in ipairs(geo) do
        if idx > 1 then
            local below = geo[idx - 1]
            Sep(g.x, below.y + below.h + Centre(gap), wid, pixel)
        end
        local row = g.key == "sky" and Set.stack or g.key == "sw" and Set.sw
        if row then
            for jdx = 1, #row.pips - 1 do
                local pipTex = row.pips[jdx]
                Sep(g.x + pipTex._edrX + pipTex._edrW + Centre(spacing), g.y, pixel, g.h)
            end
        end
    end
    for idx = num + 1, #colour.seps do
        colour.seps[idx]:Hide()
    end
end

-- Whirling Surge icon per bar style: Blizzard = action button frame, rounded
-- mask and rounded swipe; Classic WoW UI = the vanilla slot ring; modern = the
-- plain cropped square. The cooldown text is lifted above any frame.
local function ApplyIconArt(Set, chromeFrame)
    local frame = Set.icon
    if chromeFrame and not frame.artFrame then
        frame.artFrame = CreateFrame("Frame", nil, frame)
        frame.artFrame:SetAllPoints(frame)
        frame.artFrame:SetFrameLevel(frame.cd:GetFrameLevel() + 1)
        frame.textFrame:SetFrameLevel(frame.cd:GetFrameLevel() + 2)
    end
    if chromeFrame == "blizzard" and not frame.blizzFrame then
        frame.blizzFrame = frame.artFrame:CreateTexture(nil, "OVERLAY")
        frame.blizzFrame:SetAtlas(BLIZZ_ICON.frame)
        frame.blizzFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        frame.blizzMask = frame:CreateMaskTexture()
        frame.blizzMask:SetAtlas(
            BLIZZ_ICON.mask,
            false,
            nil,
            nil,
            "CLAMPTOBLACKADDITIVE",
            "CLAMPTOBLACKADDITIVE"
        )
        frame.blizzMask:SetPoint("CENTER", frame.tex, "CENTER")
        -- The mask art has transparent padding around its rounded square, so it
        -- is sized from its own atlas (scaled like the icon), not to the icon.
        local details = C_Texture.GetAtlasInfo(BLIZZ_ICON.mask)
        frame.blizzMaskW = details and details.width or BLIZZ_ICON.iconSize
        frame.blizzMaskH = details and details.height or BLIZZ_ICON.iconSize
    end
    if chromeFrame == "classic" and not frame.classicRing then
        frame.classicRing = frame.artFrame:CreateTexture(nil, "OVERLAY")
        frame.classicRing:SetTexture(BLIZZ_ICON.ring)
        frame.classicRing:SetSnapToPixelGrid(false)
        frame.classicRing:SetTexelSnappingBias(0)
    end

    local size = frame:GetHeight()
    if frame.blizzFrame then
        local on = chromeFrame == "blizzard"
        frame.blizzFrame:SetShown(on)
        if on then
            local s = size / BLIZZ_ICON.iconSize
            frame.blizzFrame:SetSize(BLIZZ_ICON.frameW * s, BLIZZ_ICON.frameH * s)
            frame.blizzMask:SetSize(frame.blizzMaskW * s, frame.blizzMaskH * s)
        end
        if on ~= (frame.blizzMasked or false) then
            if on then
                frame.tex:AddMaskTexture(frame.blizzMask)
                frame.cd:SetSwipeTexture(BLIZZ_ICON.swipe)
            else
                frame.tex:RemoveMaskTexture(frame.blizzMask)
                frame.cd:SetSwipeTexture("")
            end
            frame.blizzMasked = on
        end
    end
    if frame.classicRing then
        local on = chromeFrame == "classic"
        frame.classicRing:SetShown(on)
        if on then
            frame.classicRing:ClearAllPoints()
            frame.classicRing:SetPoint("CENTER", frame, "CENTER", 0, -size / 36)
            frame.classicRing:SetSize(size * 66 / 36, size * 66 / 36)
        end
    end
    if chromeFrame == "blizzard" then
        frame.tex:SetTexCoord(0, 1, 0, 1)
    else
        frame.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
end

-- Resolve a classic atlas by its texture-kit name, falling back to the "-2x"
-- member name in case a client only registers that one. nil = art missing.
local classicAtlasCache = {}
local function ClassicAtlas(suffix)
    local hit = classicAtlasCache[suffix]
    if hit ~= nil then return hit or nil end
    local name = CLASSIC.kit .. "_" .. suffix
    if not C_Texture.GetAtlasInfo(name) then
        name = name .. "-2x"
        if not C_Texture.GetAtlasInfo(name) then name = false end
    end
    classicAtlasCache[suffix] = name
    return name or nil
end

local function SetClassicArt(texture, suffix, wid, hgt)
    local atlas = ClassicAtlas(suffix)
    if atlas then texture:SetAtlas(atlas) end
    texture:SetSize(wid, hgt)
    return atlas
end

local function AddAlphaStep(set, from, to, duration, sequence, endDelay)
    local fade = set:CreateAnimation("Alpha")
    fade:SetFromAlpha(from)
    fade:SetToAlpha(to)
    fade:SetDuration(duration)
    fade:SetOrder(sequence)
    if endDelay then fade:SetEndDelay(endDelay) end
end

-- One gem. Frame levels stand in for the template's draw layers: background on
-- the cell, fill bar one level up, frame/spark/flash one above that.
local function CreateClassicCell(hostFrame)
    local C = CLASSIC
    local pipCell = CreateFrame("Frame", nil, hostFrame)
    pipCell:SetSize(C.cellW, C.cellH)

    pipCell.bg = pipCell:CreateTexture(nil, "BACKGROUND")
    pipCell.bg:SetPoint("CENTER")
    SetClassicArt(pipCell.bg, "background", C.bgW, C.bgH)

    local barFrame = CreateFrame("StatusBar", nil, pipCell)
    barFrame:SetOrientation("VERTICAL")
    barFrame:SetMinMaxValues(0, 1)
    barFrame:SetValue(0)
    barFrame:SetPoint("CENTER")
    barFrame:SetSize(C.fillW, C.fillH)
    barFrame:SetFrameLevel(pipCell:GetFrameLevel() + 1)
    pipCell.bar = barFrame
    pipCell.fillAtlas = ClassicAtlas("fill")
    pipCell.fillFullAtlas = ClassicAtlas("fillfull")
    if pipCell.fillAtlas then barFrame:SetStatusBarTexture(pipCell.fillAtlas) end
    pipCell.isFull = false

    local flipAtlas = ClassicAtlas("fill_flipbook")
    if flipAtlas then
        pipCell.flip = barFrame:CreateTexture(nil, "OVERLAY")
        pipCell.flip:SetAllPoints(barFrame)
        pipCell.flip:SetAtlas(flipAtlas)
        pipCell.flip:Hide()
        pipCell.flipMask = barFrame:CreateMaskTexture()
        pipCell.flipMask:SetAtlas(
            "AlphaMask2",
            true,
            nil,
            nil,
            "CLAMPTOBLACKADDITIVE",
            "CLAMPTOBLACKADDITIVE"
        )
        pipCell.flipMask:SetPoint("TOP", barFrame:GetStatusBarTexture(), "TOP", 0, 0)
        pipCell.flip:AddMaskTexture(pipCell.flipMask)
        pipCell.flipAnim = pipCell.flip:CreateAnimationGroup()
        pipCell.flipAnim:SetLooping("REPEAT")
        local fb = pipCell.flipAnim:CreateAnimation("FlipBook")
        fb:SetDuration(1.2)
        fb:SetFlipBookRows(5)
        fb:SetFlipBookColumns(4)
        fb:SetFlipBookFrames(20)
    end

    local overlay = CreateFrame("Frame", nil, pipCell)
    overlay:SetAllPoints(pipCell)
    overlay:SetFrameLevel(pipCell:GetFrameLevel() + 2)
    pipCell.overlay = overlay

    pipCell.spark = overlay:CreateTexture(nil, "OVERLAY")
    pipCell.spark:SetBlendMode("ADD")
    SetClassicArt(pipCell.spark, "spark", C.sparkW, C.sparkH)
    pipCell.spark:SetPoint("CENTER", barFrame:GetStatusBarTexture(), "TOP", 0, 0)
    pipCell.spark:Hide()
    local maskAtlas = ClassicAtlas("mask")
    if maskAtlas then
        local mask = overlay:CreateMaskTexture()
        mask:SetAtlas(maskAtlas, false, nil, nil, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetSize(C.maskW, C.maskH)
        mask:SetPoint("CENTER", pipCell, "CENTER")
        pipCell.spark:AddMaskTexture(mask)
    end

    pipCell.frame = overlay:CreateTexture(nil, "OVERLAY", nil, 1)
    pipCell.frame:SetPoint("CENTER", pipCell, "CENTER")
    SetClassicArt(pipCell.frame, "frame", C.frameW, C.frameH)

    pipCell.flash = overlay:CreateTexture(nil, "OVERLAY", nil, 1)
    pipCell.flash:SetBlendMode("ADD")
    pipCell.flash:SetPoint("CENTER", pipCell, "CENTER")
    SetClassicArt(pipCell.flash, "flash", C.frameW, C.frameH)
    pipCell.flash:SetAlpha(0)

    pipCell.flashAnim = pipCell.flash:CreateAnimationGroup()
    pipCell.flashAnim:SetToFinalAlpha(true)
    AddAlphaStep(pipCell.flashAnim, 0, 1, 0.5, 1)
    AddAlphaStep(pipCell.flashAnim, 1, 0, 0.5, 2)

    pipCell.pulseAnim = pipCell.flash:CreateAnimationGroup()
    pipCell.pulseAnim:SetToFinalAlpha(true)
    pipCell.pulseAnim:SetLooping("REPEAT")
    AddAlphaStep(pipCell.pulseAnim, 0, 1, 1.5, 1)
    AddAlphaStep(pipCell.pulseAnim, 1, 0, 1.5, 2, 0.8)

    return pipCell
end

-- The gem row at 1x: mirrored decor, six cells, decor. Built on first use only,
-- so the modern style never pays for it.
local function EnsureClassicFrame(Set)
    if Set.classic then return Set.classic end
    local C = CLASSIC
    local frame = CreateFrame("Frame", nil, Set.root)
    frame:SetSize(CLASSIC_W, CLASSIC_H)

    frame.decorL = frame:CreateTexture(nil, "ARTWORK")
    SetClassicArt(frame.decorL, "decor", C.decorW, C.decorH)
    frame.decorL:SetTexCoord(1, 0, 0, 1)
    frame.decorL:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -C.decorTop)
    frame.decorR = frame:CreateTexture(nil, "ARTWORK")
    SetClassicArt(frame.decorR, "decor", C.decorW, C.decorH)
    frame.decorR:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -C.decorTop)

    frame.cells = {}
    local posX = C.decorW + C.edgePad
    for idx = 1, SKYRIDING_PIPS do
        local pipCell = CreateClassicCell(frame)
        pipCell:SetPoint("TOPLEFT", frame, "TOPLEFT", posX, 0)
        -- Level above the decor so the end gems overlap the wings, as they did.
        pipCell:SetFrameLevel(frame:GetFrameLevel() + 1)
        pipCell.bar:SetFrameLevel(pipCell:GetFrameLevel() + 1)
        pipCell.overlay:SetFrameLevel(pipCell:GetFrameLevel() + 2)
        frame.cells[idx] = pipCell
        posX = posX + C.cellW
    end
    Set.classic = frame
    return frame
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
    local PPdr = CUI and CUI.PP
    local pixel = (PPdr and PPdr.mult and PPdr.mult > 0) and PPdr.mult or 1
    local widthAvail = max(0, width - (pipCount - 1) * spacing)
    -- If the whole row doesn't span even one physical pixel (a very small bar at a low
    -- UI Scale, where px itself is large), snapping to whole physical-pixel units would
    -- floor every pip to 0 width -- pips vanishing entirely is worse than the sub-pixel
    -- gap this fix targets. Fall back to plain UI-unit distribution (pre-fix behavior)
    -- in that degenerate case so pips stay visible, just not perfectly pixel-snapped.
    if widthAvail < pixel then pixel = 1 end
    local totalUnits = floor(widthAvail / pixel + 1e-6)
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
        local thisW = (boundary - prevBoundary) * pixel
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
local function NewSet(rootTbl, bordered)
    local Set = { root = rootTbl, bordered = bordered }
    Set.speed = CreateSpeedBar(rootTbl)
    EnsureBorder(Set, Set.speed)

    Set.stack = CreateStackFrame(rootTbl, SKYRIDING_PIPS)
    for idx = 1, SKYRIDING_PIPS do
        EnsureBorder(Set, Set.stack.pips[idx])
    end

    Set.sw = CreateStackFrame(rootTbl, SECONDWIND_PIPS)
    for idx = 1, SECONDWIND_PIPS do
        EnsureBorder(Set, Set.sw.pips[idx])
    end

    Set.icon = CreateWhirlingSurgeIcon(rootTbl)
    EnsureBorder(Set, Set.icon)
    return Set
end

local liveCells

function Build()
    if rootHost then return end
    rootHost = CreateFrame("Frame", "CludesUIDragonRidingAnchor", UIParent)
    rootHost:SetFrameStrata("MEDIUM")
    rootHost:Hide()
    rootHost:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

    liveCells = NewSet(rootHost, borderedFrames)
    speedBar, stackFrame, swFrame, whirlIcon = liveCells.speed, liveCells.stack, liveCells.sw, liveCells.icon

    RebuildBar()
end

-- Sizes and anchors one set for the layout L.
local function LayoutSet(Set, profile, Lay)
    Set.root:SetSize(Lay.totalW, Lay.totalH)

    -- Column rows, bottom to top, the column centred on the icon. Rows not in
    -- the layout are hidden; rows that stay are never hidden and re-shown.
    -- Every frame here is SHOWN BEFORE it is anchored, sized and has its pips
    -- laid out: a row or icon re-anchored while hidden and shown afterwards
    -- (Vigor Style Bars <-> Classic Gems, a row or the icon toggled back on)
    -- drew its pips piled up or not at all until a later pass.
    local rowFrames = { speed = Set.speed, sky = Set.stack, sw = Set.sw }
    local inLayout = {}
    for _, key in ipairs(Lay.rows) do
        inLayout[key] = true
    end
    for key, frame in pairs(rowFrames) do
        if not inLayout[key] then frame:Hide() end
    end
    local spacing = profile.stackSpacing
    local clusterX = SnapPx((Lay.totalW - Lay.clusterW) / 2)
    local posY = Lay.colY + Lay.ov
    local geo = {}
    for idx, key in ipairs(Lay.rows) do
        local frame = rowFrames[key]
        local hgt = profile[ROW_FIELD[key]]
        local rx, ry = clusterX + Lay.padX, posY
        geo[idx] = { key = key, x = rx, y = ry, h = hgt }
        frame:Show()
        frame:ClearAllPoints()
        frame:SetPoint("BOTTOMLEFT", Set.root, "BOTTOMLEFT", rx, ry)
        frame:SetSize(profile.width, hgt)
        if key == "sky" then
            LayoutPips(Set.stack, SKYRIDING_PIPS, profile.width, hgt, spacing)
        elseif key == "sw" then
            LayoutPips(Set.sw, SECONDWIND_PIPS, profile.width, hgt, spacing)
        end
        posY = posY + hgt + profile.gap
    end
    ApplyColumnChrome(Set, Lay, geo, profile.width, profile.gap, spacing)

    local iconTex = Set.icon
    if Lay.icon then
        iconTex:Show()
        iconTex:ClearAllPoints()
        iconTex:SetPoint(
            "BOTTOMLEFT",
            Set.root,
            "BOTTOMLEFT",
            clusterX + Lay.colW + (Lay.colW > 0 and profile.gap or 0),
            Lay.iconY
        )
        iconTex:SetSize(Lay.iconSize, Lay.iconSize)
    else
        iconTex:Hide()
    end
    ApplyIconArt(Set, Lay.chrome)

    if Lay.classic then
        local frame = EnsureClassicFrame(Set)
        frame:Show()
        frame:SetScale(Lay.scale)
        frame:ClearAllPoints()
        -- Offsets on a scaled frame are in its own units.
        frame:SetPoint("TOPLEFT", Set.root, "TOPLEFT", SnapPx((Lay.totalW - Lay.classicW) / 2) / Lay.scale, 0)
    elseif Set.classic then
        Set.classic:Hide()
    end
end

-- Textures, colours, texts, borders and bevels of one set.
local function PaintSet(Set, profile, Lay)
    -- Apply bar texture to all StatusBars
    local texPath = CUI.ResolveTexturePath(
        mod.EDR_BAR_TEXTURES,
        profile.barTexture or "none",
        "Interface\\Buttons\\WHITE8x8"
    )
    local speedValue, stack, sw, iconTex = Set.speed, Set.stack, Set.sw, Set.icon
    speedValue:SetStatusBarTexture(texPath)
    for idx = 1, SKYRIDING_PIPS do
        stack.pips[idx]:SetStatusBarTexture(texPath)
    end
    for idx = 1, SECONDWIND_PIPS do
        sw.pips[idx]:SetStatusBarTexture(texPath)
    end

    local color = profile.normalColor
    speedValue:SetStatusBarColor(color.r, color.g, color.b, color.a)
    speedValue.bg:SetColorTexture(
        profile.speedBarBg.r,
        profile.speedBarBg.g,
        profile.speedBarBg.b,
        profile.speedBarBg.a
    )

    local tickFrac = (profile.thrillThreshold or 0) / (profile.maxSpeed > 0 and profile.maxSpeed or 1)
    tickFrac = max(0, min(1, tickFrac))
    speedValue.tick:ClearAllPoints()
    speedValue.tick:SetPoint("TOP", speedValue, "TOPLEFT", profile.width * tickFrac, 0)
    speedValue.tick:SetPoint("BOTTOM", speedValue, "BOTTOMLEFT", profile.width * tickFrac, 0)
    speedValue.tick:SetWidth(2)
    speedValue.tick:SetColorTexture(
        profile.tickColor.r,
        profile.tickColor.g,
        profile.tickColor.b,
        profile.tickColor.a
    )

    ApplyFont(speedValue.text, profile.speedText.size)
    speedValue.text:ClearAllPoints()
    speedValue.text:SetPoint(
        profile.speedText.justify or "CENTER",
        speedValue,
        profile.speedText.justify or "CENTER",
        profile.speedText.offsetX or 0,
        profile.speedText.offsetY or 0
    )
    speedValue.text:SetJustifyH(profile.speedText.justify or "CENTER")
    speedValue.text:SetShown(profile.speedText.enabled ~= false)

    for idx = 1, SKYRIDING_PIPS do
        local pipTex = stack.pips[idx]
        pipTex:SetStatusBarColor(
            profile.skyridingFilled.r,
            profile.skyridingFilled.g,
            profile.skyridingFilled.b,
            1
        )
        pipTex.bg:SetColorTexture(
            profile.skyridingBg.r,
            profile.skyridingBg.g,
            profile.skyridingBg.b,
            profile.skyridingBg.a
        )
    end

    for idx = 1, SECONDWIND_PIPS do
        local pipTex = sw.pips[idx]
        pipTex:SetStatusBarColor(
            profile.secondWindFilled.r,
            profile.secondWindFilled.g,
            profile.secondWindFilled.b,
            1
        )
        pipTex.bg:SetColorTexture(
            profile.secondWindBg.r,
            profile.secondWindBg.g,
            profile.secondWindBg.b,
            profile.secondWindBg.a
        )
    end

    ApplyFont(iconTex.text, profile.whirlingSurgeText.size)
    iconTex.text:ClearAllPoints()
    iconTex.text:SetPoint(
        profile.whirlingSurgeText.justify or "CENTER",
        iconTex,
        profile.whirlingSurgeText.justify or "CENTER",
        profile.whirlingSurgeText.offsetX or 0,
        profile.whirlingSurgeText.offsetY or 0
    )
    iconTex.text:SetJustifyH(profile.whirlingSurgeText.justify or "CENTER")
    iconTex.text:SetShown(profile.whirlingSurgeText.enabled ~= false)

    ApplyBordersAll(Set, Lay)

    -- Bar style bevel (the column frame is laid out by Rebuild).
    ApplyRowChrome(speedValue, Lay.chrome, profile.width, profile.speedHeight)
    ApplyRowChrome(stack, Lay.chrome, profile.width, profile.skyridingHeight)
    ApplyRowChrome(sw, Lay.chrome, profile.width, profile.secondWindHeight)
end

local RepaintSample

function RebuildBar()
    if not rootHost then return end
    local profile = saved.profile
    local Lay = ComputeLayout(profile)
    LayoutSet(liveCells, profile, Lay)
    classicFrame = liveCells.classic
    Redraw(Lay)
    ApplyPos()
    UpdateVisibility()
end

-- L = the layout Rebuild already computed, or nil to compute it here.
function Redraw(Lay)
    if not rootHost then return end
    local profile = saved.profile
    Lay = Lay or ComputeLayout(profile)
    PaintSet(liveCells, profile, Lay)

    skyridingStale = true
    secondWindStale = true
    whirlStale = true
    lastSkyCur, lastSkyProgress = -1, -1
    lastSwCur, lastSwProgress = -1, -1
    lastClassicCur, lastClassicProgress = -1, -1
    lastSoundCur = -1
    lastCdStart, lastCdDur = -1, -1
    -- Settings applied: the repaint above rides the tick, so arm it if shown.
    SyncTicker()
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
    local profile = saved and saved.profile
    if not (sampleSet and profile) then return end
    local Set = sampleSet
    local Lay = ComputeLayout(profile)
    -- The options page scales and anchors the root first: the pixel snaps
    -- below read the scale the sample shows at.
    if samplePlace then samplePlace(Set.root, Lay.totalW, Lay.totalH) end
    LayoutSet(Set, profile, Lay)
    PaintSet(Set, profile, Lay)

    local fraction = (profile.maxSpeed > 0) and (SAMPLE_SPEED_PCT / profile.maxSpeed) or 0
    Set.speed:SetValue(max(0, min(1, fraction)))
    Set.speed.text:SetText(FormatSpeedText(SAMPLE_SPEED_PCT))
    local color = (profile.thrillColorToggle and SAMPLE_SPEED_PCT >= (profile.thrillThreshold or 0))
            and profile.thrillColor
        or profile.normalColor
    Set.speed:SetStatusBarColor(color.r, color.g, color.b, color.a)

    if Lay.classic then
        -- Still gems: no pulse, flash or swirl in the header.
        for idx, pipCell in ipairs(Set.classic.cells) do
            pipCell.flashAnim:Stop()
            pipCell.pulseAnim:Stop()
            pipCell.flash:SetAlpha(0)
            if pipCell.flipAnim then
                pipCell.flipAnim:Stop()
                pipCell.flip:Hide()
            end
            SetClassicFull(pipCell, idx <= 4)
            local val = (idx <= 4 and 1) or (idx == 5 and 0.5) or 0
            pipCell.bar:SetValue(val)
            pipCell.spark:SetShown(val > 0 and val < 1)
        end
    else
        ApplyPipRow(
            Set.stack.pips,
            SKYRIDING_PIPS,
            4,
            SKYRIDING_PIPS,
            0.5,
            -1,
            -1,
            profile.skyridingFilled,
            0.4
        )
    end
    ApplyPipRow(Set.sw.pips, SECONDWIND_PIPS, 2, SECONDWIND_PIPS, 0.6, -1, -1, profile.secondWindFilled, 0.4)

    local nowTime = GetTime()
    Set.icon.cd:SetCooldown(nowTime - 8, 20)
    Set.icon.cd:Pause()
    Set.icon.text:SetText(FormatCooldownText(12))
end

function RepaintSample()
    if sampleSet and sampleSet.root:IsVisible() then PaintSample() end
end

-- Shows the sample under parent and paints it. place(root, w, h) runs before
-- every paint with the HUD's size in its own units, to scale and anchor the
-- root. Returns the root, or nil before the profile exists.
function mod.EDR_ShowSample(hostFrame, place)
    if not (saved and saved.profile) then return nil end
    if not sampleSet then sampleSet = NewSet(CreateFrame("Frame", nil, hostFrame), {}) end
    local rootTbl = sampleSet.root
    rootTbl:SetParent(hostFrame)
    rootTbl:SetFrameStrata(hostFrame:GetFrameStrata())
    rootTbl:SetFrameLevel(hostFrame:GetFrameLevel() + 5)
    rootTbl:Show()
    samplePlace = place
    PaintSample()
    return rootTbl
end
mod.EDR_RepaintSample = RepaintSample

-------------------------------------------------------------------------------
--  Unlock mode
-------------------------------------------------------------------------------
local function SavePos(_, anchorPoint, relPoint, posX, posY)
    if not anchorPoint then return end
    local profile = saved and saved.profile
    if not profile then return end
    profile.unlockPos = { point = anchorPoint, relPoint = relPoint or anchorPoint, x = posX, y = posY }
    if not CUI._unlockActive and rootHost then
        rootHost:ClearAllPoints()
        rootHost:SetPoint(anchorPoint, UIParent, relPoint or anchorPoint, posX, posY)
    end
end
local function LoadPos()
    local profile = saved and saved.profile
    local position = profile and profile.unlockPos
    if not position then return nil end
    return {
        point = position.point,
        relPoint = position.relPoint or position.point,
        x = position.x,
        y = position.y,
    }
end
local function ClearPos()
    local profile = saved and saved.profile
    if not profile then return end
    profile.unlockPos = nil
end
function ApplyPos()
    local profile = saved and saved.profile
    local position = profile and profile.unlockPos
    if not position or not rootHost then return end
    rootHost:ClearAllPoints()
    rootHost:SetPoint(position.point, UIParent, position.relPoint or position.point, position.x, position.y)
end

-- Profile-swap refresh: re-read DB and rebuild the HUD.
_G._CUDR_Rebuild = function()
    if not rootHost then return end
    RebuildBar()
    ApplyPos()
end

function RegisterUnlockElements()
    if not CUI or not CUI.RegisterUnlockElements then return end
    local MK = CUI.MakeUnlockElement
    CUI:RegisterUnlockElements({
        MK({
            key = "EDR_Cluster",
            label = "Dragon Riding",
            group = "Dragon Riding",
            order = 700,
            getFrame = function() return rootHost end,
            getSize = function()
                local Lay = ComputeLayout(saved.profile)
                return Lay.totalW, Lay.totalH
            end,
            setWidth = function(_, wid)
                local profile = saved.profile
                local Lay = ComputeLayout(profile)
                if Lay.colW == 0 then
                    -- No bars in the column: the handle scales the gems, if any.
                    if Lay.classic then
                        profile.classicScale = max(0.5, min(2, floor(wid / CLASSIC_W * 100 + 0.5) / 100))
                        RebuildBar()
                    end
                    return
                end
                -- Where getSize reports an even-pixel total, a restore of that
                -- exact size is a no-op; any other width (a drag, a width
                -- match) sizes the cluster as given, so a match converges.
                if Lay.totalW ~= Lay.rawW and abs(wid - Lay.totalW) < 0.01 then return end
                local clusterW = wid
                -- A gem row wider than the bars sets the width by itself; the
                -- column only follows the handle once it is dragged past it.
                if Lay.classicW > Lay.clusterW and clusterW <= Lay.classicW then return end
                local iconPart = Lay.icon and (profile.gap + Lay.iconSize) or 0
                profile.width = max(60, SnapPx(clusterW - iconPart - 2 * Lay.padX))
                RebuildBar()
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
                local profile = saved.profile
                local Lay = ComputeLayout(profile)
                if Lay.clusterH == 0 then
                    if Lay.classic then
                        profile.classicScale = max(0.5, min(2, floor(hgt / CLASSIC_H * 100 + 0.5) / 100))
                        RebuildBar()
                    end
                    return
                end
                -- A restore of getSize's even-pixel total is a no-op (see setWidth).
                if Lay.totalH ~= Lay.rawH and abs(hgt - Lay.totalH) < 0.01 then return end
                local newTotalH = SnapPx(hgt)
                local classicPart = Lay.classic and (Lay.classicH + profile.gap) or 0
                local scale = max(8, newTotalH - classicPart) / Lay.clusterH
                if Lay.icon and profile.iconSize then
                    profile.iconSize = max(16, min(80, floor(Lay.iconSize * scale + 0.5)))
                end
                local rowList = Lay.rows
                if #rowList == 0 then
                    RebuildBar()
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
                local whole = Lay.colH == Lay.clusterH
                local colTarget = whole and (newTotalH - classicPart) or Lay.colH * scale
                local targetSum = colTarget - (#rowList - 1) * profile.gap - 2 * Lay.ov
                if Lay.chrome or Lay.classic or not whole then targetSum = floor(targetSum + 0.5) end
                targetSum = max(loSum, targetSum)

                local oldSum = 0
                for _, button in ipairs(barList) do
                    button.old = profile[button.field]
                    oldSum = oldSum + button.old
                end
                if oldSum <= 0 then
                    -- Corrupted/legacy profile (e.g. hand-edited SavedVariables)
                    -- with every shown height at/under zero: reset to defaults so
                    -- the control self-heals instead of silently no-op'ing forever.
                    for _, button in ipairs(barList) do
                        profile[button.field] = DB_DEFAULTS.profile[button.field]
                    end
                    RebuildBar()
                    return
                end

                local scale = targetSum / oldSum
                for _, button in ipairs(barList) do
                    button.new = max(button.lo, min(button.hi, floor(button.old * scale + 0.5)))
                end

                -- A bar already at its min/max absorbs none of a further shrink/grow,
                -- so plain proportional scaling can leave the resize handle feeling
                -- stuck once one or two bars saturate. Hand any leftover delta to
                -- whichever bar(s) still have headroom instead of discarding it
                -- (bounded to one pass per bar so this always terminates).
                for _ = 1, #barList do
                    local sum = 0
                    for _, button in ipairs(barList) do
                        sum = sum + button.new
                    end
                    local leftover = targetSum - sum
                    if leftover == 0 then break end
                    local openBars = {}
                    for _, button in ipairs(barList) do
                        if
                            (leftover > 0 and button.new < button.hi)
                            or (leftover < 0 and button.new > button.lo)
                        then
                            openBars[#openBars + 1] = button
                        end
                    end
                    if #openBars == 0 then break end
                    local shareF = leftover / #openBars
                    local share = shareF >= 0 and floor(shareF + 0.5) or -floor(-shareF + 0.5)
                    if share == 0 then
                        -- Leftover doesn't divide evenly across every open bar
                        -- this pass (e.g. 1px across 3 bars): give the whole
                        -- remainder to just the first bar with headroom rather
                        -- than rounding a fractional share up and applying it
                        -- to all of them, which would overshoot the target.
                        local button = openBars[1]
                        button.new = max(button.lo, min(button.hi, button.new + leftover))
                    else
                        for _, button in ipairs(openBars) do
                            button.new = max(button.lo, min(button.hi, button.new + share))
                        end
                    end
                end

                for _, button in ipairs(barList) do
                    profile[button.field] = button.new
                end
                RebuildBar()
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
    if not CUI or not CUI.Lite then return end

    saved = CUI.Lite.NewDB("CludesUIDragonRidingDB", DB_DEFAULTS)
    mod.edrDB = saved
    -- Latch the bar art from the login profile (even while the HUD is off,
    -- so a profile switch before its first build still compares against it).
    mod.EDR_Style()

    -- If disabled, skip all frame creation and event registration.
    -- Rebuild (called from options toggle) will lazy-init if needed.
    if not saved.profile.enabled then return end

    Build()

    eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
    eventFrame:RegisterEvent("PLAYER_CAN_GLIDE_CHANGED")
    eventFrame:RegisterEvent("PLAYER_IS_GLIDING_CHANGED")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:SetScript("OnEvent", function(_, evt)
        if evt == "SPELL_UPDATE_CHARGES" then
            skyridingStale = true
            secondWindStale = true
            SyncTicker()
            return
        elseif evt == "SPELL_UPDATE_COOLDOWN" then
            whirlStale = true
            SyncTicker()
            return
        elseif evt == "PLAYER_IS_GLIDING_CHANGED" then
            local gliding = C_PlayerInfo.GetGlidingInfo()
            _gliding = gliding == true
            SyncTicker()
            return
        elseif evt == "PLAYER_ENTERING_WORLD" then
            skyridingStale = true
            secondWindStale = true
            whirlStale = true
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
    if not saved then return end
    if not rootHost then
        -- First enable after being disabled at login: full init
        Build()
        if not eventFrame then
            eventFrame = CreateFrame("Frame")
            eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
            eventFrame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
            eventFrame:RegisterEvent("PLAYER_CAN_GLIDE_CHANGED")
            eventFrame:RegisterEvent("PLAYER_IS_GLIDING_CHANGED")
            eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
            eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
            eventFrame:SetScript("OnEvent", function(_, evt)
                if evt == "SPELL_UPDATE_CHARGES" then
                    skyridingStale = true
                    secondWindStale = true
                    SyncTicker()
                    return
                elseif evt == "SPELL_UPDATE_COOLDOWN" then
                    whirlStale = true
                    SyncTicker()
                    return
                elseif evt == "PLAYER_IS_GLIDING_CHANGED" then
                    local gliding = C_PlayerInfo.GetGlidingInfo()
                    _gliding = gliding == true
                    SyncTicker()
                    return
                elseif evt == "PLAYER_ENTERING_WORLD" then
                    skyridingStale = true
                    secondWindStale = true
                    whirlStale = true
                end
                UpdateVisibility()
            end)
        end
        RegisterUnlockElements()
    end
    RebuildBar()
end
mod.edrRedraw = function() Redraw() end
-- The icon's automatic size (as tall as every bar of the vigor style, frame
-- rim included), whatever Icon Size holds: the options show it while Auto Size
-- is on and hand it over when Auto Size is turned off.
mod.edrIconSize = function()
    local profile = saved and saved.profile
    if not profile then return 34 end
    local Lay = ComputeLayout(profile)
    return StackHeight(profile, Lay.classic and STYLE_ROWS_GEMS or STYLE_ROWS_BARS, Lay.ov)
end
