if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUIMythicTimer.lua  --  M+ Timer overlay for CludesUI
-------------------------------------------------------------------------------
local ADDON_NAME, mod = ...
if
    not (
        CludesUI
        and CludesUI._ModuleNS
        and CludesUI.NewCombatQueue
        and CludesUI.RegisterNumberFormatCallback
        and CludesUI.ApplyModuleFontFamily
        and CludesUI.SetFontFamily
    )
then
    CUI_CLIENT_BLOCKED = true
    return
end -- stale-parent guard: a partially updated install (old parent, new child) goes dormant via the line-1 failsafe instead of erroring (the run summary redraws through the parent's RegisterNumberFormatCallback, and the texts naming players take font families through its ApplyModuleFontFamily / SetFontFamily)
CludesUI._ModuleNS[ADDON_NAME] = mod -- LOD options files read this module ns via the registry
mod.CombatQueue = CludesUI.NewCombatQueue(CreateFrame("Frame"))
local EMT = CludesUI.Lite.NewAddon(ADDON_NAME)

-- Upvalues
local floor, min, max, abs = math.floor, math.min, math.max, math.abs
local format = string.format
local GetWorldElapsedTime = GetWorldElapsedTime
local wipe = wipe

-- Constants
local PLUS_TWO_RATIO = 0.8
local PLUS_THREE_RATIO = 0.6
-- SEASON UPDATE: the affix that adds time to the key timer (Challenger's Peril,
-- +90 s; the only such affix in the 12.1.5 affix table, build 70575).
local CHALLENGERS_PERIL_AFFIX_ID = 152

local COMPARE_NONE = "NONE"
local COMPARE_DUNGEON = "DUNGEON"
local COMPARE_LEVEL = "LEVEL"
local COMPARE_LEVEL_AFFIX = "LEVEL_AFFIX"

local barTextures, barTextureNames, barTextureOrder = CludesUI.BuildBarTextureTables()
mod.barTextures = barTextures
mod.barTextureOrder = barTextureOrder
mod.barTextureNames = barTextureNames

local function AppendSharedMediaBarTextures()
    CludesUI.AppendSharedMediaTextures(barTextureNames, barTextureOrder, nil, barTextures)
end
mod.AppendSharedMediaBarTextures = AppendSharedMediaBarTextures

local function ApplyBarTexture(texture, texKey, r, g, b, a)
    if not texture then
        return
    end
    local filePath = CludesUI.ResolveTexturePath(barTextures, texKey or "none", nil)
    if filePath then
        texture:SetTexture(filePath)
        texture:SetVertexColor(r, g, b, a)
    else
        texture:SetVertexColor(1, 1, 1, 1)
        texture:SetColorTexture(r, g, b, a)
    end
end

-- One full physical pixel. ResourceBars can get away with a sub-pixel inset because a
-- StatusBar clips its own fill texture tightly; our plain SetTexture fills (Melli
-- etc.) bilinear-filter a full pixel past their rect. Half-px left a visible fringe
-- past the border on the long continuous TICKS bar (SEGMENTS hid it better between
-- per-segment borders). Solid ColorTexture bars don't need this; same inset is
-- harmless and keeps timer/forces paths identical.
local function GetBarBleedInset(p, forForces)
    if not p or p.customBorderStyle ~= true then
        return 0
    end
    if (p.borderSize or 0) <= 0 then
        return 0
    end
    if forForces and p.borderApplyToForces == false then
        return 0
    end
    local Pix = CludesUI and CludesUI.PP
    return (Pix and Pix.mult or 1) * 1
end

-- Outer host = border/geometry anchor. Inner clip = bg+fill parent, inset so the
-- texture cannot sample past the border. Host clips its children so any residual
-- filter fringe from the clip's textures is still cut off at the host edge
-- (SetClipsChildren only affects child frames, not a frame's own textures -- so the
-- fill must live on `clip`, not on `host`).
local function EnsureBarShell(hostFrame, hostKey)
    local owner = hostFrame[hostKey]
    if owner then
        -- Re-assert: shells created before the TICKS bleed fix may lack this.
        owner:SetClipsChildren(true)
        return owner, owner._clip
    end
    owner = CreateFrame("Frame", nil, hostFrame)
    owner:EnableMouse(false)
    -- Clip child rendering (the inset `clip` frame + its textures' filter fringe)
    -- to the host rect so nothing paints past the border's outer edge.
    owner:SetClipsChildren(true)
    local clip = CreateFrame("Frame", nil, owner)
    clip:EnableMouse(false)
    owner._clip = clip
    hostFrame[hostKey] = owner
    return owner, clip
end

local function LayoutBarClip(owner, clip, inset)
    clip:ClearAllPoints()
    if inset > 0 then
        clip:SetPoint("TOPLEFT", owner, "TOPLEFT", inset, -inset)
        clip:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", -inset, inset)
    else
        clip:SetAllPoints(owner)
    end
end

-- Build (or reuse) bg+fill textures as children of clip so host clipping applies.
local function EnsureShellTextures(clip, ownerFrame, bgKey, fillKey)
    if not ownerFrame[bgKey] then
        ownerFrame[bgKey] = clip:CreateTexture(nil, "BACKGROUND", nil, 1)
        ownerFrame[bgKey]:SetAllPoints(clip)
    end
    if not ownerFrame[fillKey] then
        ownerFrame[fillKey] = clip:CreateTexture(nil, "ARTWORK")
    end
    return ownerFrame[bgKey], ownerFrame[fillKey]
end

local CopyTable = CludesUI.Lite.DeepCopy

local function CalculateBonusTimers(maxTime, affixes)
    local plusTwoT = (maxTime or 0) * PLUS_TWO_RATIO
    local plusThreeT = (maxTime or 0) * PLUS_THREE_RATIO

    if not maxTime or maxTime <= 0 then
        return plusTwoT, plusThreeT
    end

    if affixes then
        for _, affixID in ipairs(affixes) do
            if affixID == CHALLENGERS_PERIL_AFFIX_ID then
                local oldTimer = maxTime - 90
                if oldTimer > 0 then
                    plusTwoT = oldTimer * PLUS_TWO_RATIO + 90
                    plusThreeT = oldTimer * PLUS_THREE_RATIO + 90
                end
                break
            end
        end
    end

    return plusTwoT, plusThreeT
end

-- Database defaults
local DB_DEFAULTS = {
    profile = {
        enabled = true,
        borderTexture = "solid",
        borderSize = 0,
        borderR = 0,
        borderG = 0,
        borderB = 0,
        borderA = 1,
        showTitle = true,
        showDungeonName = true,
        -- Show the key level (e.g. "+21") with a divider to the left of the timer
        -- clock. Only usable while the dungeon name is hidden (the title is then
        -- just the lone key level, which moves down onto the timer line instead).
        showKeyLevelOnTimer = false,
        keyLevelTimerSpacing = 8,
        showAffixes = true,
        showPlusTwoTimer = true,
        showPlusThreeTimer = true,
        showThreshRemaining = false,
        showDeaths = true,
        showObjectives = true,
        showObjectiveTimes = true,
        objectiveTimePosition = "RIGHT",
        objectiveTextOffsetX = 0,
        objectiveTextOffsetY = 0,
        showEnemyBar = true,
        showEnemyText = true,
        scale = 1.0,
        standaloneAlpha = 0,
        showAccent = false,
        showPreview = false,
        enemyForcesPos = "BOTTOM",
        enemyForcesPctPos = "LABEL",
        -- enemyForcesTextSize: intentionally unset so it falls back to objectivesSize
        -- (see RenderEnemyForces). Writing a default here would override a user's
        -- customized objectivesSize. Written only when the slider is changed.
        enemyForcesTextOffsetX = 0,
        enemyForcesTextOffsetY = 0,
        deathsInTitle = false,
        deathTimeInTitle = false,
        timerInBar = false,
        showTimerBar = true,
        showTimerBreakdown = false,
        titleAffixPosition = "ABOVE_TIMER",
        -- titleAffixDeathGap: intentionally unset so it falls back to ROW_GAP + 5
        -- (which tracks the user's rowGap). A hardcoded default would break the
        -- title/affix spacing for anyone who customized rowGap.
        titleAffixSandwichGap = 6,
        titleAffixTimerGap = 6,
        titleAffixBarGap = 6,
        alignAllText = "RIGHT",
        titleUseAccent = true,
        titleColor = { r = 1, g = 1, b = 1 },
        titleSize = 16,
        affixSize = 12,
        thresholdSize = 12,
        -- thresholdPlus*Size: intentionally unset so each falls back to thresholdSize
        -- (see RenderThresholdText). Hardcoding 12 here would override a user's
        -- customized thresholdSize. Written per-row only when its slider is changed.
        tickAlpha = 1,
        timerBarStyle = "TICKS",
        timerBarSegmentGap = 2,
        thresholdTextOffsetX = 0,
        thresholdTextOffsetY = 0,
        thresholdPlusThreeTextOffsetX = 0,
        thresholdPlusThreeTextOffsetY = 0,
        thresholdPlusTwoTextOffsetX = 0,
        thresholdPlusTwoTextOffsetY = 0,
        thresholdPlusOneTextOffsetX = 0,
        thresholdPlusOneTextOffsetY = 0,
        objectivesSize = 12,
        timerExpiredColor = { r = 0.9, g = 0.2, b = 0.2 },
        enemyForcesTextFormat = "PERCENT",
        showCompletedMilliseconds = true,
        objectiveCompareMode = "NONE",
        objectiveCompareDeltaOnly = false,
        objectiveCompareStrict = false,
        showUpcomingSplitTargets = false,
        showFastestRunSplits = false,
        frameWidth = 260,
        barWidth = 210,
        barHeight = 8,
        -- enemyBarHeight: intentionally unset so the forces bar falls back to
        -- barHeight. A default here would change the forces bar of every user
        -- who customized barHeight. Written once either bar height slider is
        -- changed (the timer slider pins it to the old height first).
        barHeightExpanded = 22,
        barTexture = "none",
        barBgTexture = "none",
        enemyBarTexture = "none",
        enemyBarBgTexture = "none",
        customBorderStyle = false,
        borderApplyToForces = true,
        rowGap = 6,
        objectiveGap = 4,
        timerPlusTwoColor = { r = 0.3, g = 0.8, b = 1 },
        timerPlusThreeColor = { r = 0.4, g = 1, b = 0.4 },
        timerBarUseCustomColor = false,
        timerBarColor = { r = 0.4, g = 1, b = 0.4 },
        timerSegment1Color = { r = 0.4, g = 1, b = 0.4 },
        timerSegment2Color = { r = 0.3, g = 0.8, b = 1 },
        timerSegment3Color = { r = 0xB0 / 255, g = 0x59 / 255, b = 0xCC / 255 },
        timerSegment1TextColor = { r = 0.4, g = 1, b = 0.4 },
        timerSegment2TextColor = { r = 0.3, g = 0.8, b = 1 },
        timerSegment3TextColor = { r = 1, g = 1, b = 1 },
        thresholdPlusThreeTextWhite = false,
        thresholdPlusTwoTextWhite = false,
        thresholdPlusOneTextWhite = false,
        affixTextColor = { r = 1, g = 1, b = 1 },
        objectiveTextColor = { r = 0.9, g = 0.9, b = 0.9 },
        objectiveCompletedColor = { r = 0.3, g = 0.8, b = 0.3 },
        splitFasterColor = { r = 0.4, g = 1, b = 0.4 },
        splitSlowerColor = { r = 1, g = 0.45, b = 0.45 },
        deathTextColor = { r = 0.93, g = 0.33, b = 0.33 },
        enemyBarUseAccent = true,
        enemyBarColor = { r = 0.35, g = 0.55, b = 0.8 },
        -- Current pull: the bar previews the forces of every enemy in combat
        -- behind the forces fill (by default in the fill color at reduced alpha).
        showPullBar = false,
        pullBarUseBarColor = true,
        pullBarColor = { r = 1, g = 0.55, b = 0.1 },
        pullBarAlpha = 0.35,
        -- Targeted Spell Bars (Mythic+ Tools tab): replica nameplate cast bars
        -- collected into one movable group. Disabled by default; the feature
        -- registers its events only while enabled (zero cost off). Runtime in
        -- CUI_MythicTimer_TargetedSpellBars.lua.
        tsb = {
            enabled = false,
            growUp = false, -- false = new bars stack downward
            width = 240,
            height = 20,
            spacing = 4,
            maxBars = 5,
            texture = "none",
            barColor = { r = 0.70, g = 0.40, b = 0.90 },
            bgColor = { r = 0, g = 0, b = 0, a = 0.45 },
            borderSize = 1,
            showIcon = true,
            iconOnRight = false, -- attach the spell icon to the right of the bar instead of the left
            showIconDivider = false, -- draw a 1px divider at the icon/bar seam
            showSpellName = true,
            nameSize = 10,
            nameX = 0,
            nameY = 0,
            showTarget = true,
            targetSize = 10,
            targetX = 0,
            targetY = 0,
            targetClassColor = true,
            targetColor = { r = 1, g = 1, b = 1 },
            showTimer = true,
            timerSize = 10,
            timerX = 0,
            timerY = 0,
            -- Interrupt awareness and visibility. Cast Colors (kick-ready
            -- tint + uninterruptible wash) always applies, no off switch;
            -- the rest is opt-in and off by default: important-cast
            -- tint/glow, out-of-interrupt-range fade, raid target marker.
            interruptReady = { r = 0.92, g = 0.35, b = 0.20 },
            uninterruptible = { r = 0.45, g = 0.45, b = 0.45 },
            importantEnabled = false,
            importantColor = { r = 1, g = 0.2, b = 0.2 },
            importantGlow = false,
            importantGlowStyle = 1,
            importantGlowColor = { r = 1, g = 0.2, b = 0.2 },
            importantGlowLines = 8,
            importantGlowThickness = 2,
            importantGlowSpeed = 4,
            oorEnabled = false,
            oorAlpha = 0.45,
            showRaidMarker = false,
            raidMarkerSize = 14,
            -- Where to Show: positive filter -- a key is present (true) only
            -- when selected; nothing selected = the bars show everywhere.
            whereToShow = {},
        },
        -- Target/Focus standalone cast bars (Mythic+ Tools tab): unlock-mode
        -- placeable cast bars carrying the nameplate interrupt color/effects
        -- system. Both disabled by default. Runtime in
        -- CUI_MythicTimer_TargetFocusBars.lua.
        tfb = {
            castColor = { r = 0.70, g = 0.40, b = 0.90 },
            interruptReady = { r = 0.92, g = 0.35, b = 0.20 },
            uninterruptible = { r = 0.45, g = 0.45, b = 0.45 },
            importantColor = { r = 1, g = 0.2, b = 0.2 },
            importantEnabled = false,
            midCastColor = { r = 0.318, g = 0.820, b = 0.357 },
            kickTickColor = { r = 1, g = 1, b = 1 },
            kickTickEnabled = true,
            midCastEnabled = false,
            showShield = true,
            showSpark = true,
            interruptedFlash = true,
            interruptedColor = { r = 0.8, g = 0, b = 0 },
            showTarget = true,
            targetClassColor = true,
            targetColor = { r = 1, g = 1, b = 1 },
            target = {
                enabled = false,
                width = 260,
                height = 22,
                texture = "none",
                showIcon = true,
                showSpellName = true,
                nameSize = 11,
                showTimer = true,
                timerSize = 11,
                targetSize = 10,
            },
            focus = {
                enabled = false,
                width = 260,
                height = 22,
                texture = "none",
                showIcon = true,
                showSpellName = true,
                nameSize = 11,
                showTimer = true,
                timerSize = 11,
                targetSize = 10,
            },
        },
        -- Run Summary (Mythic+ Tools tab): end-of-key overview panel with one
        -- row per party member, plus a per-character history of finished runs.
        -- Disabled by default; the collector registers its events only while
        -- enabled (zero cost off). Runtime in CUI_MythicTimer_RunSummary.lua.
        -- The run records themselves live in the per-character SavedVariable
        -- CludesUIMythicRunsDB, not here -- profile data is settings only.
        runSummary = {
            enabled = false,
            showAfterLoot = true,
            historySize = 20,
            scale = 1,
            textSize = 14, -- member rows only; header/title sizes are fixed
            sortKey = "dps", -- dps | damageTaken | interrupts | deaths (header click)
            sortAsc = false,
            showSpecIcons = true,
            colItemLevel = true,
            colScore = true,
            colLoot = true,
            colDps = true,
            colDamageTaken = true,
            colInterrupts = true,
            colDeaths = true,
        },
        -- Kick Tracker (Mythic+ Tools tab): who in the group kicked each enemy
        -- and when their interrupt comes back (the kick engine), shown as an
        -- icon with a cooldown on the kicked enemy's nameplate and as a bar
        -- per member. Disabled by default; nothing registers until it is
        -- enabled (zero cost off). Runtime in CUI_MythicTimer_KickEngine.lua /
        -- _KickPlates.lua / _KickBars.lua over the parent's interrupt data
        -- (CludesUI_KickData.lua).
        kickTracker = {
            enabled = false, -- off by default
            -- Where to Show: checked = true. An unchecked default entry is
            -- stored as false, never nil (a nil reads back as true at login).
            whereToShow = { dungeon_mythic = true, arena = true },
            focusMarker = 0, -- Focus Announce: the raid marker (1-8) told to the party in a Mythic dungeon; 0 = none
            -- announceText: the player's own Focus Announce line (Edit Announce Text), {marker} = the raid marker; unset = the default line
            showPlates = true, -- the nameplate icon
            aboveOverlap = true, -- Show Above Overlapping Nameplates: the icons draw over every other nameplate (the plates' lift), never behind one
            iconStyle = "kick", -- "kick" | "spec" | "class": the kicker's interrupt icon, spec icon or classicon
            size = 28, -- icon size in px (16-48)
            anchor = "LEFT", -- "LEFT" | "RIGHT" | "TOP" | "BOTTOM": side of the nameplate
            offsetX = -4, -- CludesUI Nameplates: from the health bar (cast bar for BOTTOM) edge
            offsetY = 0, -- CludesUI Nameplates: vertical offset
            otherOffsetX = 0, -- other nameplates: from the base nameplate edge
            otherOffsetY = 0, -- other nameplates: vertical offset
            classBorder = true, -- border in the kicker's class color (black when off or hidden)
            swipe = true, -- the cooldown swipe over the icon
            desaturate = false, -- grey the icon while the kicker's interrupt is on cooldown
            showTimer = true, -- the seconds left on the kicker's interrupt
            timerSize = 11, -- timer text size (6-24)
            timerPos = "center", -- "center" | "topleft" | "topright" | "bottomleft" | "bottomright"
            timerX = 0, -- timer text offsets
            timerY = 0,
            -- The bars: a row per group member with an interrupt.
            showBars = true,
            barWidth = 200,
            barHeight = 22,
            barSpacing = 2,
            barGrowUp = false, -- false = rows stack downward
            texture = "none", -- the rows' bar texture (the Textures page's row writes this key)
            barBgMode = "class", -- "class" = a darkened class colour behind each row | "custom" = barBgColor
            barBgColor = { r = 0, g = 0, b = 0, a = 0.45 },
            barBorderSize = 0,
            barShowIcon = true, -- the interrupt's icon at the row's end
            barIconOnRight = false,
            barShowName = true,
            barNameSize = 11,
            barShowTimer = true, -- seconds left while on cooldown
            barTimerSize = 11,
            barIncludeSelf = true, -- your own row
            barShowMarker = true, -- the raid marker of the mob the member interrupted, beside their row
        },
    },
}

-- Per-addon border texture defaults (same as resourcebars/cdm)
CludesUI.RegisterBorderDefaults("MythicPlus", CludesUI.BORDER_DEFAULTS_BARS)

-- State
local db
local updateTicker
local currentRun = {
    active = false,
    mapID = nil,
    mapName = "",
    level = 0,
    affixes = {},
    maxTime = 0,
    elapsed = 0,
    completed = false,
    deaths = 0,
    deathTimeLost = 0,
    objectives = {},
}

-- Per-player death tracking (reset each key).
-- Midnight removed CLEU, so we detect deaths by comparing the API death
-- count each tick and scanning the party for who is newly dead.
local playerDeaths = {}
local _prevDeathCount = 0
local _partyAlive = {} -- [name] = true while alive, removed on death detection

local function ScanPartyAlive()
    wipe(_partyAlive)
    local prefixText = IsInRaid() and "raid" or "party"
    local count = GetNumGroupMembers()
    for i = 1, count do
        local unitToken = (prefixText == "party" and i == count) and "player" or (prefixText .. i)
        local name = UnitName(unitToken)
        if name and not UnitIsDeadOrGhost(unitToken) then
            _partyAlive[name] = true
        end
    end
    if prefixText == "party" then
        local name = UnitName("player")
        if name and not UnitIsDeadOrGhost("player") then
            _partyAlive[name] = true
        end
    end
end

local function CheckForNewDeaths(newDeathCount)
    if newDeathCount <= _prevDeathCount then
        _prevDeathCount = newDeathCount
        return
    end
    -- Death count went up -- find who is now dead that was alive last tick
    local prefixText = IsInRaid() and "raid" or "party"
    local count = GetNumGroupMembers()
    for i = 1, count do
        local unitToken = (prefixText == "party" and i == count) and "player" or (prefixText .. i)
        local name = UnitName(unitToken)
        if name and _partyAlive[name] and UnitIsDeadOrGhost(unitToken) then
            playerDeaths[name] = (playerDeaths[name] or 0) + 1
            _partyAlive[name] = nil
        end
    end
    if prefixText == "party" then
        local name = UnitName("player")
        if name and _partyAlive[name] and UnitIsDeadOrGhost("player") then
            playerDeaths[name] = (playerDeaths[name] or 0) + 1
            _partyAlive[name] = nil
        end
    end
    _prevDeathCount = newDeathCount
end

-- Helpers
local function FormatTime(seconds, withMilliseconds)
    if not seconds or seconds < 0 then
        seconds = 0
    end
    local whole = floor(seconds)
    local m = floor(whole / 60)
    local s = floor(whole % 60)
    if withMilliseconds then
        local ms = floor(((seconds - whole) * 1000) + 0.5)
        if ms >= 1000 then
            whole = whole + 1
            m = floor(whole / 60)
            s = floor(whole % 60)
            ms = 0
        end
        return format("%02d:%02d.%03d", m, s, ms)
    end
    return format("%02d:%02d", m, s)
end

-- Like FormatTime, but once the run is over time the remaining clock keeps
-- counting into the negative (e.g. "-01:04") instead of sitting frozen at
-- "00:00", so it's obvious by how much you're over.
local function FormatRemaining(remaining)
    if remaining and remaining < 0 then
        return "-" .. FormatTime(-remaining)
    end
    return FormatTime(remaining)
end

local function RoundToInt(value)
    if not value then
        return 0
    end
    return floor(value + 0.5)
end

local function GetColor(list, fallbackR, fallbackG, fallbackB)
    if list then
        return list.r or fallbackR, list.g or fallbackG, list.b or fallbackB
    end
    return fallbackR, fallbackG, fallbackB
end

local function GetTimerBarFillColor(profile, elapsed, plusThreeTime, plusTwoTime, maxTime)
    if profile and profile.timerBarUseCustomColor == true then
        return GetColor(profile.timerBarColor, 0.4, 1, 0.4)
    end
    if maxTime and maxTime > 0 and elapsed > plusTwoTime then
        -- +2 lost: solid #B059CC.
        return 0xB0 / 255, 0x59 / 255, 0xCC / 255
    elseif maxTime and maxTime > 0 and elapsed > plusThreeTime then
        -- +3 lost, +2 still on: match the +2 threshold color.
        return GetColor(profile and profile.timerPlusTwoColor, 0.3, 0.8, 1)
    end
    -- On for +3: match the +3 threshold color.
    return GetColor(profile and profile.timerPlusThreeColor, 0.4, 1, 0.4)
end

local function GetTimerSegmentFillColor(profile, elapsed, plusThreeTime, plusTwoTime)
    if elapsed > plusTwoTime then
        return GetColor(profile and profile.timerSegment3Color, 0xB0 / 255, 0x59 / 255, 0xCC / 255)
    elseif elapsed > plusThreeTime then
        return GetColor(profile and profile.timerSegment2Color, 0.3, 0.8, 1)
    end
    return GetColor(profile and profile.timerSegment1Color, 0.4, 1, 0.4)
end

local function GetTimerSegmentTextColor(profile, index)
    if index == 3 then
        if profile and profile.thresholdPlusOneTextWhite == true then
            return 1, 1, 1
        end
        return GetColor(profile and profile.timerSegment3Color, 0xB0 / 255, 0x59 / 255, 0xCC / 255)
    elseif index == 2 then
        if profile and profile.thresholdPlusTwoTextWhite == true then
            return 1, 1, 1
        end
        return GetColor(profile and profile.timerSegment2Color, 0.3, 0.8, 1)
    end
    if profile and profile.thresholdPlusThreeTextWhite == true then
        return 1, 1, 1
    end
    return GetColor(profile and profile.timerSegment1Color, 0.4, 1, 0.4)
end

local function NormalizeAffixKey(affixes)
    local ids = {}
    for _, affixID in ipairs(affixes or {}) do
        ids[#ids + 1] = affixID
    end
    table.sort(ids)
    return table.concat(ids, "-")
end

local function GetScopeKey(run, mode)
    if not run or not run.mapID then
        return nil
    end

    if mode == COMPARE_DUNGEON then
        return tostring(run.mapID)
    elseif mode == COMPARE_LEVEL then
        return format("%s:%d", run.mapID, run.level or 0)
    elseif mode == COMPARE_LEVEL_AFFIX then
        return format("%s:%d:%s", run.mapID, run.level or 0, NormalizeAffixKey(run.affixes))
    end

    return nil
end

local function EnsureProfileStore(key)
    if not db or not db.profile then
        return nil
    end
    if not db.profile[key] then
        db.profile[key] = {}
    end
    return db.profile[key]
end

local function GetReferenceObjectiveTime(run, objectiveIndex, mode)
    if mode == COMPARE_NONE then
        return nil
    end

    local storage = (db.profile.showFastestRunSplits and EnsureProfileStore("fastestRunSplits"))
        or EnsureProfileStore("bestObjectiveSplits")
    if not storage then
        return nil
    end

    -- Try exact scope first, then fall back to broader scopes
    -- (LEVEL_AFFIX -> LEVEL -> DUNGEON); strict mode = exact scope only, so a
    -- new key level shows no comparison instead of the dungeon-wide best.
    local tryOrder
    if db.profile.objectiveCompareStrict == true then
        tryOrder = { mode }
    elseif mode == COMPARE_LEVEL_AFFIX then
        tryOrder = { COMPARE_LEVEL_AFFIX, COMPARE_LEVEL, COMPARE_DUNGEON }
    elseif mode == COMPARE_LEVEL then
        tryOrder = { COMPARE_LEVEL, COMPARE_DUNGEON }
    else
        tryOrder = { mode }
    end

    for _, tryMode in ipairs(tryOrder) do
        local scopeKey = GetScopeKey(run, tryMode)
        local scope = scopeKey and storage[scopeKey]
        if scope and scope[objectiveIndex] then
            return scope[objectiveIndex]
        end
    end
    return nil
end

local function UpdateBestObjectiveSplits(run, objectiveIndex, elapsed)
    local storage = EnsureProfileStore("bestObjectiveSplits")
    if not storage then
        return
    end

    for _, mode in ipairs({ COMPARE_DUNGEON, COMPARE_LEVEL, COMPARE_LEVEL_AFFIX }) do
        local scopeKey = GetScopeKey(run, mode)
        if scopeKey then
            if not storage[scopeKey] then
                storage[scopeKey] = {}
            end
            local previous = storage[scopeKey][objectiveIndex]
            if not previous or elapsed < previous then
                storage[scopeKey][objectiveIndex] = elapsed
            end
        end
    end
end

local function UpdateObjectiveCompletion(object, objectiveIndex)
    if not db or not db.profile or not object or not object.elapsed or object.elapsed <= 0 then
        return
    end

    local compareMode = db.profile.objectiveCompareMode or COMPARE_NONE
    local reference = GetReferenceObjectiveTime(currentRun, objectiveIndex, compareMode)
    object.referenceElapsed = reference
    object.compareDelta = reference and (object.elapsed - reference) or nil
    object.isNewBest = reference == nil or object.elapsed < reference

    UpdateBestObjectiveSplits(currentRun, objectiveIndex, object.elapsed)
end

-- The splits of the fastest COMPLETED run per scope, beside the per-objective
-- bests: same shape (store[scopeKey][objectiveIndex] = elapsed) plus the
-- run's own time under "overallRunTime", which decides whether a run
-- replaces the stored one. Called once per completion from CompleteRun.
local FASTEST_RUN_SCOPES = { COMPARE_DUNGEON, COMPARE_LEVEL, COMPARE_LEVEL_AFFIX }
local function SaveFastestRunSplits()
    local storage = EnsureProfileStore("fastestRunSplits")
    if not storage then
        return
    end
    local run = currentRun
    local elapsed = run.elapsed
    -- The completion time can come from GetWorldElapsedTime after a
    -- depletion, which may hand back a secret: no compare on that. A run
    -- with no known time (0) never replaces the stored one.
    if type(elapsed) ~= "number" or (issecretvalue and issecretvalue(elapsed)) or elapsed <= 0 then
        return
    end
    for _, mode in ipairs(FASTEST_RUN_SCOPES) do
        local scopeKey = GetScopeKey(run, mode)
        if scopeKey then
            if not storage[scopeKey] then
                storage[scopeKey] = {}
            end
            local previousRunTime = storage[scopeKey].overallRunTime
            if not previousRunTime or elapsed < previousRunTime then
                storage[scopeKey].overallRunTime = elapsed
                for objectiveIndex, objective in ipairs(run.objectives) do
                    local t = objective.elapsed
                    storage[scopeKey][objectiveIndex] = (t and t > 0) and t or nil
                end
            end
        end
    end
end

local function BuildSplitCompareText(referenceTime, currentTime, deltaOnly, fasterColor, slowerColor)
    if not referenceTime then
        return ""
    end

    -- No time to compare yet (boss still alive): the reference on its own, in the
    -- same gray parentheses a completed objective uses, just without the +/-.
    if not currentTime then
        return format("  |cff888888(%s)|r", FormatTime(referenceTime))
    end

    local diff = currentTime - referenceTime
    local color = diff <= 0 and fasterColor or slowerColor
    local cR, cG, cB = GetColor(color, 0.4, 1, 0.4)
    local diffPrefix = diff < 0 and "-" or "+"
    local diffText = diff == 0 and "0:00" or FormatTime(abs(diff))
    local colorHex = CludesUI.HexColor(cR, cG, cB)

    if deltaOnly then
        return format("  %s(%s%s)|r", colorHex, diffPrefix, diffText)
    end

    return format("  |cff888888(%s, %s%s%s)|r", FormatTime(referenceTime), colorHex, diffPrefix, diffText)
end

local function FormatEnemyForcesText(enemyObj, formatId, compact)
    local rawCurrent = enemyObj.rawQuantity or enemyObj.quantity or 0
    local rawTotal = enemyObj.rawTotalQuantity or enemyObj.totalQuantity or 100
    local percent = enemyObj.percent or enemyObj.quantity or 0
    local remaining = max(0, rawTotal - rawCurrent)
    local suffix = compact and "" or CludesUI.L(" Enemy Forces")

    if formatId == "COUNT" then
        return format("%d/%d%s", RoundToInt(rawCurrent), RoundToInt(rawTotal), suffix)
    elseif formatId == "COUNT_PERCENT" then
        return format("%d/%d - %.2f%%%s", RoundToInt(rawCurrent), RoundToInt(rawTotal), percent, suffix)
    elseif formatId == "COUNT_REMAINING" then
        return format(
            "%d/%d (%d left)%s",
            RoundToInt(rawCurrent),
            RoundToInt(rawTotal),
            RoundToInt(remaining),
            suffix
        )
    elseif formatId == "REMAINING" then
        if compact then
            return format("%d left", RoundToInt(remaining))
        end
        return format("%d remaining%s", RoundToInt(remaining), suffix)
    end

    return format("%.2f%%%s", percent, suffix)
end

-- Objective tracking
local function UpdateObjectives()
    local numCriteria = select(3, C_Scenario.GetStepInfo()) or 0
    local elapsed = currentRun.elapsed

    for i = 1, numCriteria do
        local details = C_ScenarioInfo.GetCriteriaInfo(i)
        if details then
            local object = currentRun.objectives[i]
            if not object then
                object = {
                    name = "",
                    completed = false,
                    elapsed = 0,
                    quantity = 0,
                    totalQuantity = 0,
                    rawQuantity = 0,
                    rawTotalQuantity = 0,
                    percent = 0,
                    isWeighted = false,
                }
                currentRun.objectives[i] = object
            end

            -- Strip Blizzard's leading checkmark so completed objectives
            -- render as clean text. UTF-8 for U+2713 is 0xE2 0x9C 0x93.
            local rawName = details.description or ("Objective " .. i)
            rawName = rawName:gsub("^\226\156\147%s*", "")
            rawName = rawName:gsub("^%-%s*", "")
            object.name = rawName
            local wasCompleted = object.completed
            object.completed = details.completed

            if object.completed and (not wasCompleted or object._stampLater) then
                -- On reload, already-completed objectives would get current elapsed.
                -- Use persisted split time if available (saved on first completion),
                -- only from the table this run's check passed. Until the timer reads a
                -- real time nothing is stamped: the objective waits for the first tick
                -- that does.
                local splits = db and db.profile._activeRunSplits
                local saved = splits and splits == currentRun._checkedSplits and splits[i]
                if saved and saved > 0 then
                    object._stampLater = nil
                    object.elapsed = saved
                    -- The comparison it had when first stamped: its own banked best must
                    -- not become its reference. Looked up again when compare is off or the
                    -- fastest run is the reference (written only at completion).
                    local refs = (db.profile.objectiveCompareMode or COMPARE_NONE) ~= COMPARE_NONE
                        and not db.profile.showFastestRunSplits
                        and splits.refs
                    if refs and refs[i] ~= nil then
                        local ref = refs[i] or nil
                        object.referenceElapsed = ref
                        object.compareDelta = ref and (saved - ref) or nil
                        object.isNewBest = ref == nil or saved < ref
                    else
                        UpdateObjectiveCompletion(object, i)
                    end
                elseif elapsed > 0 then
                    object._stampLater = nil
                    object.elapsed = elapsed
                    UpdateObjectiveCompletion(object, i)
                    -- Persist for reload survival, with the run's server start time and
                    -- the comparison the split got
                    if db and db.profile then
                        if not splits or splits ~= currentRun._checkedSplits then
                            splits = {
                                mapID = currentRun.mapID,
                                level = currentRun.level,
                                start = GetServerTime() - elapsed,
                            }
                            db.profile._activeRunSplits = splits
                            currentRun._checkedSplits = splits
                        end
                        splits[i] = elapsed
                        splits.refs = splits.refs or {}
                        splits.refs[i] = object.referenceElapsed or false
                    end
                else
                    object._stampLater = true
                end
            end

            object.quantity = details.quantity or 0
            object.totalQuantity = details.totalQuantity or 0
            object.rawQuantity = details.quantity or 0
            object.rawTotalQuantity = details.totalQuantity or 0
            if details.isWeightedProgress then
                object.isWeighted = true
                currentRun._weightedObj = object -- cached for RenderEnemyForces
                -- Normalize weighted progress to a 0-100 percent value.
                -- Cache the parsed result keyed on the raw string -- skips
                -- the gsub/tonumber chain on every tick where quantityString
                -- hasn't actually changed (the common case).
                local rawQuantity = details.quantity or 0
                local quantityString = details.quantityString
                if quantityString and quantityString ~= "" then
                    if object._lastQS == quantityString then
                        rawQuantity = object._lastQSParsed or rawQuantity
                    else
                        local normalized = quantityString:gsub("%%", "")
                        if normalized:find(",") and not normalized:find("%.") then
                            normalized = normalized:gsub(",", ".")
                        end
                        local parsed = tonumber(normalized)
                        if parsed then
                            rawQuantity = parsed
                        end
                        object._lastQS, object._lastQSParsed = quantityString, parsed
                    end
                end

                object.rawQuantity = rawQuantity
                if object.totalQuantity and object.totalQuantity > 0 then
                    local percent = (rawQuantity / object.totalQuantity) * 100
                    object.quantity = floor(percent * 100 + 0.5) / 100
                else
                    object.quantity = rawQuantity
                end
                object.percent = object.quantity

                if object.completed then
                    object.quantity = 100
                    object.percent = 100
                    if object.rawTotalQuantity and object.rawTotalQuantity > 0 then
                        object.rawQuantity = object.rawTotalQuantity
                    end
                end
            else
                object.isWeighted = false
                object.percent = 0
                if object.totalQuantity == 0 then
                    object.quantity = object.completed and 1 or 0
                    object.totalQuantity = 1
                end
            end
        end
    end

    if currentRun.completed then
        SaveFastestRunSplits()
    end

    for i = numCriteria + 1, #currentRun.objectives do
        currentRun.objectives[i] = nil
    end
end

-- Coalesced refresh (C_Timer.After returns nothing, so a flag marks the pending one)
local _refreshPending = false
local function FlushRefresh()
    _refreshPending = false
    if _G._CUMT_StandaloneRefresh then
        _G._CUMT_StandaloneRefresh()
    end
end
local function NotifyRefresh()
    if _refreshPending then
        return
    end
    _refreshPending = true
    C_Timer.After(0.05, FlushRefresh)
end

-- Elapsed time: read from GetWorldElapsedTime(1) each tick. The Blizzard
-- hook on ChallengeModeBlock.UpdateTime is the tick driver (every frame
-- while a key's timer runs, zero cost outside M+); OnTimerTick keeps one
-- pass per whole second.
local _lastTickedSec = -1

-- StartRun keeps saved splits of the same dungeon and level; the first real
-- time decides whether they are this run's (a reload or re-entry) or an
-- earlier key's. The saved start is the run's server start time: a later
-- key starts at least the earlier run's first split later, while a reload
-- reads the same run (death penalties only move the estimate earlier), so
-- 30 s absorbs clock jitter. Tables saved before the stamp fall back to
-- "no split later than now". The table that passes is the only one saved
-- splits are read from; a different one (a profile switched in mid-key) is
-- checked again, map and level included.
local function CheckSavedSplits(elapsed)
    currentRun._checkSplits = nil
    currentRun._checkedSplits = nil
    local splits = db and db.profile._activeRunSplits
    if not splits then
        return
    end
    local stale = splits.mapID ~= currentRun.mapID or splits.level ~= currentRun.level
    if not stale and splits.start then
        stale = GetServerTime() - elapsed > splits.start + 30
    elseif not stale then
        for k, t in pairs(splits) do
            if type(k) == "number" and t > elapsed then
                stale = true
                break
            end
        end
    end
    if stale then
        db.profile._activeRunSplits = nil
    else
        currentRun._checkedSplits = splits
    end
end

-- A saved table this run has not checked arms the check again
local function NoteSavedSplits()
    local splits = db and db.profile._activeRunSplits
    if splits and splits ~= currentRun._checkedSplits then
        currentRun._checkSplits = true
    end
end

local function OnTimerTick()
    if not currentRun.active then
        return
    end

    local elapsed = select(2, GetWorldElapsedTime(1))
    if not (elapsed and elapsed >= 0) then
        return
    end

    -- Deduplicate: only refresh the display once per whole second.
    local sec = floor(elapsed)
    if sec == _lastTickedSec then
        return
    end
    _lastTickedSec = sec

    currentRun.elapsed = elapsed

    NoteSavedSplits()
    if currentRun._checkSplits and elapsed > 0 then
        CheckSavedSplits(elapsed)
    end

    local deathCount, timeLost = C_ChallengeMode.GetDeathCount()
    currentRun.deaths = deathCount or 0
    currentRun.deathTimeLost = timeLost or 0

    -- Detect per-player deaths, then refresh alive snapshot for next tick
    CheckForNewDeaths(deathCount or 0)
    ScanPartyAlive()

    UpdateObjectives()
    NotifyRefresh()
end

-- Primary driver: hook Blizzard's ChallengeModeBlock.UpdateTime. Blizzard's
-- ScenarioTimerFrame calls it every frame while a key's timer runs; that frame
-- has no parent and handles its own events, so hiding or reparenting
-- ObjectiveTrackerFrame does not stop it.
local _tickHooked = false
do
    local block = (ScenarioObjectiveTracker and ScenarioObjectiveTracker.ChallengeModeBlock)
        or (ScenarioBlocksFrame and ScenarioBlocksFrame.ChallengeModeBlock)
    if block and block.UpdateTime then
        hooksecurefunc(block, "UpdateTime", function()
            OnTimerTick()
        end)
        _tickHooked = true
    end
end

-- Fallback driver, only when the hook could not be installed: OnUpdate on
-- the standalone frame, throttled to 1/sec, running only while the frame is
-- shown (an active M+ key).
local _onUpdateAccum = 0
local function OnUpdateFallback(_, dt)
    _onUpdateAccum = _onUpdateAccum + dt
    if _onUpdateAccum < 1 then
        return
    end
    _onUpdateAccum = 0
    OnTimerTick()
end

local standaloneFrame
local standaloneCreated = false
local _timerLoopWanted = false
local function StartTimerLoop()
    if _tickHooked then
        return
    end
    _timerLoopWanted = true
    if standaloneFrame then
        _onUpdateAccum = 0
        standaloneFrame:SetScript("OnUpdate", OnUpdateFallback)
    end
end
local function StopTimerLoop()
    _timerLoopWanted = false
    if standaloneFrame then
        standaloneFrame:SetScript("OnUpdate", nil)
    end
end

-- Hide Blizzard's ObjectiveTrackerFrame whenever our M+ timer is enabled
-- and we're in an active challenge mode. Permanent hooksecurefunc on Show:
-- every time Blizzard tries to show it during M+, we re-hide it. No
-- SetParent (avoids tainting the secure scenario tree), no recursion into
-- children (avoids the invisible-click-catcher pattern).
local function TrackerShouldBeHidden()
    if not (db and db.profile and db.profile.enabled) then
        return false
    end
    -- Hide during active challenge AND after it completes but before the
    -- player has left the dungeon instance. Blizzard's end-of-run fanfare
    -- flips IsChallengeModeActive() back to false while the user is still
    -- inside -- without the completed + party gate the tracker pops back
    -- up for the last seconds before zone-out.
    if
        C_ChallengeMode
        and C_ChallengeMode.IsChallengeModeActive
        and C_ChallengeMode.IsChallengeModeActive()
    then
        return true
    end
    if currentRun and currentRun.completed then
        local _, iType = GetInstanceInfo()
        return iType == "party"
    end
    return false
end

-- ObjectiveTrackerFrame is EditMode-managed: its Hide() routes through the system
-- template to HideBase(), which is protected, so calling it from our execution during
-- combat is blocked (ADDON_ACTION_BLOCKED). In combat, suppress with alpha only
-- (top-level frame, never children, never mouse state) and finish the real Hide once
-- combat drops. Each new in-combat request re-queues the one-shot finish.
local function FinishTrackerHide()
    local frame = _G.ObjectiveTrackerFrame
    if not frame then
        return
    end
    frame:SetAlpha(1)
    if TrackerShouldBeHidden() then
        frame:Hide()
    end
end
local function HideTracker(otf)
    if InCombatLockdown() then
        otf:SetAlpha(0)
        mod.CombatQueue.Defer("TrackerHide", FinishTrackerHide)
    else
        otf:SetAlpha(1) -- clear any combat alpha-suppression before hiding
        otf:Hide()
    end
end

local _trackerHookInstalled = false
local function InstallTrackerHook()
    if _trackerHookInstalled then
        return
    end
    local otf = _G.ObjectiveTrackerFrame
    if not otf then
        return
    end
    _trackerHookInstalled = true
    hooksecurefunc(otf, "Show", function()
        if TrackerShouldBeHidden() then
            HideTracker(otf)
        end
    end)
end

-- Force a re-evaluation now (used at run start / option change). If we're
-- in M+ and the addon is enabled, tracker hides; otherwise nothing happens.
local function ApplyTrackerVisibility()
    InstallTrackerHook()
    local otf = _G.ObjectiveTrackerFrame
    if not otf then
        return
    end
    if TrackerShouldBeHidden() then
        HideTracker(otf)
    end
end

local function SuppressBlizzardMPlus()
    ApplyTrackerVisibility()
    if _G._CUQT_SetSuppressed then
        _G._CUQT_SetSuppressed("MythicPlus", true)
    end
end
local function UnsuppressBlizzardMPlus()
    if _G._CUQT_SetSuppressed then
        _G._CUQT_SetSuppressed("MythicPlus", false)
    end
end

-- Run lifecycle
local function StartRun()
    local mapID = C_ChallengeMode.GetActiveChallengeMapID()
    if not mapID then
        return
    end
    _lastTickedSec = -1 -- reset dedup so the first tick always fires

    local mapName, _, timeLimit = C_ChallengeMode.GetMapUIInfo(mapID)
    local level, affixes = C_ChallengeMode.GetActiveKeystoneInfo()

    currentRun.active = true
    currentRun.completed = false
    currentRun.mapID = mapID
    currentRun.mapName = mapName or "Unknown"
    currentRun.level = level or 0
    local splits = db and db.profile and db.profile._activeRunSplits
    if splits and (splits.mapID ~= currentRun.mapID or splits.level ~= currentRun.level) then
        db.profile._activeRunSplits = nil
        splits = nil
    end
    -- A reload mid-key resumes past every saved split; a fresh key starts near 0.
    -- The timer reads 0 both before a fresh key starts and until it is populated
    -- after a reload, so the first tick that reads a real time decides.
    currentRun._checkedSplits = nil
    currentRun._checkSplits = splits and true or nil
    currentRun.maxTime = timeLimit or 0
    currentRun.elapsed = 0
    currentRun.deaths = 0
    currentRun.deathTimeLost = 0
    wipe(playerDeaths)
    _prevDeathCount = 0
    ScanPartyAlive()
    currentRun.affixes = affixes or {}
    -- Cache affix names ONCE at run start. They never change mid-run, but
    -- RenderStandalone was previously calling C_ChallengeMode.GetAffixInfo
    -- for every affix on every render tick.
    currentRun.affixNames = {}
    if affixes then
        for i, affixID in ipairs(affixes) do
            local name = C_ChallengeMode.GetAffixInfo(affixID)
            currentRun.affixNames[i] = name or ""
        end
    end
    currentRun._lastDungeonComplete = false
    currentRun._weightedObj = nil -- populated by UpdateObjectives
    wipe(currentRun.objectives)

    StartTimerLoop()
    OnTimerTick() -- prime the display immediately

    SuppressBlizzardMPlus()
    NotifyRefresh()
end

local function CompleteRun()
    currentRun.completed = true
    currentRun.active = false

    StopTimerLoop()

    -- Use C_ChallengeMode.GetChallengeCompletionInfo() as the authoritative
    -- completion time (milliseconds). GetWorldElapsedTime can return secret
    -- or stale values after depletion, producing "99:99" display.
    local completionInfo = C_ChallengeMode
        and C_ChallengeMode.GetChallengeCompletionInfo
        and C_ChallengeMode.GetChallengeCompletionInfo()
    if completionInfo and completionInfo.time and completionInfo.time > 0 then
        currentRun.elapsed = completionInfo.time / 1000
    else
        local elapsedTime = select(2, GetWorldElapsedTime(1))
        currentRun.elapsed = elapsedTime or currentRun.elapsed
    end
    -- The check can still be waiting for a real time (a reload just before the last kill)
    local e = currentRun.elapsed
    NoteSavedSplits()
    if
        currentRun._checkSplits
        and type(e) == "number"
        and not (issecretvalue and issecretvalue(e))
        and e > 0
    then
        CheckSavedSplits(e)
    end
    UpdateObjectives()
    if db and db.profile then
        db.profile._activeRunSplits = nil
    end
    NotifyRefresh()
end

local function ResetRun()
    _lastTickedSec = -1
    currentRun.active = false
    currentRun.completed = false
    currentRun.mapID = nil
    currentRun.mapName = ""
    currentRun.level = 0
    currentRun.maxTime = 0
    currentRun.elapsed = 0
    currentRun.deaths = 0
    currentRun.deathTimeLost = 0
    wipe(playerDeaths)
    _prevDeathCount = 0
    wipe(_partyAlive)
    currentRun._lastDungeonComplete = false
    wipe(currentRun.affixes)
    wipe(currentRun.objectives)
    -- The saved splits stay: re-entering this run uses them again, and the
    -- next key drops them (StartRun, CheckSavedSplits).

    StopTimerLoop()

    UnsuppressBlizzardMPlus()
    NotifyRefresh()
end

-- Preview data. SEASON UPDATE (cosmetic): a current-season dungeon and affixes,
-- so LocalizePreview finds their names; shared with the Run Summary preview.
local PREVIEW_RUN = {
    active = true,
    completed = false,
    mapID = 585,
    mapName = "Voidscar Arena",
    level = 12,
    maxTime = 1800,
    elapsed = 1380,
    deaths = 2,
    deathTimeLost = 10,
    affixes = {},
    _previewAffixNames = { "Tyrannical", "Fortified" },
    _previewAffixIDs = { 9, 10 },
    -- Current pull sample: two pulled mobs worth 18 and 14 forces (~13%).
    _previewPullValues = { 18, 14 },
    objectives = {
        {
            name = "Taz'Rah",
            completed = true,
            elapsed = 510,
            quantity = 1,
            totalQuantity = 1,
            rawQuantity = 1,
            rawTotalQuantity = 1,
            percent = 0,
            isWeighted = false,
            previewSplit = 528,
        },
        {
            name = "Atroxus",
            completed = true,
            elapsed = 1005,
            quantity = 1,
            totalQuantity = 1,
            rawQuantity = 1,
            rawTotalQuantity = 1,
            percent = 0,
            isWeighted = false,
            previewSplit = 972,
        },
        {
            name = "Lua Error Monstrosity",
            completed = false,
            elapsed = 0,
            quantity = 0,
            totalQuantity = 1,
            rawQuantity = 0,
            rawTotalQuantity = 1,
            percent = 0,
            isWeighted = false,
            previewSplit = 1500,
        },
        {
            name = "|cffff3333Cludes|r",
            completed = false,
            elapsed = 0,
            quantity = 0,
            totalQuantity = 1,
            rawQuantity = 0,
            rawTotalQuantity = 1,
            percent = 0,
            isWeighted = false,
            previewSplit = 1770,
        },
        {
            name = "Enemy Forces",
            completed = false,
            elapsed = 0,
            quantity = 78.42,
            totalQuantity = 100,
            rawQuantity = 188,
            rawTotalQuantity = 240,
            percent = 78.42,
            isWeighted = true,
        },
    },
}

-- The preview is a hardcoded dummy run, so its dungeon and affix names would stay
-- English on every client. Both carry an ID and the live-run path already resolves
-- names from those same IDs, so do the same here. When an ID is not in the current
-- season the API returns nil, so the hardcoded English falls back through L() instead.
local function LocalizePreview()
    local run = PREVIEW_RUN
    if C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
        run.mapName = C_ChallengeMode.GetMapUIInfo(run.mapID) or CludesUI.L(run.mapName)
    end
    if run._previewAffixIDs and C_ChallengeMode and C_ChallengeMode.GetAffixInfo then
        for i, ident in ipairs(run._previewAffixIDs) do
            local name = C_ChallengeMode.GetAffixInfo(ident)
            run._previewAffixNames[i] = name or CludesUI.L(run._previewAffixNames[i])
        end
    end
end

-- The timer's own repaint: the timer's options rows (the Mythic+ Timer page,
-- its rows on the Fonts and Textures pages) call this on every write.
_G._CUMT_ApplyTimer = function()
    -- Render before CENTER re-apply so height is known (placeholder is 200px).
    if _G._CUMT_StandaloneRefresh then
        _G._CUMT_StandaloneRefresh()
    end
    if _G._CUMT_ApplyStandalonePosition then
        _G._CUMT_ApplyStandalonePosition()
    end
end

-- The whole module: a profile switch or a Spec Override flip lands here, and
-- every Mythic+ Tools feature re-reads its settings from the current profile.
_G._CUMT_Apply = function()
    _G._CUMT_ApplyTimer()
    if mod.TSB_Refresh then
        mod.TSB_Refresh()
    end
    if mod.TFB_Refresh then
        mod.TFB_Refresh()
    end
    if mod.RS_Apply then
        mod.RS_Apply()
    end
    if mod.RS_Refresh then
        mod.RS_Refresh()
    end
    if mod.KT_Refresh then
        mod.KT_Refresh()
    end
end

-- Whether the Mythic+ timer window itself is on. The parent's incompatible
-- addon check asks this before naming another Mythic+ timer addon: those only
-- clash with the timer window, not with the rest of Mythic+ Tools.
_G._CUMT_IsTimerEnabled = function()
    return (db and db.profile and db.profile.enabled) and true or false
end

-- Preset system removed. Users tweak settings directly.

-- Reset the current profile back to defaults.
-- Used by the module's "Reset" button in the CludesUI options panel.
_G._CUMT_ResetProfile = function()
    if not db or not db.profile then
        return false
    end

    -- Clear every key in the current profile
    for key in pairs(db.profile) do
        db.profile[key] = nil
    end

    -- Repopulate with DB defaults
    for key, value in pairs(DB_DEFAULTS.profile) do
        db.profile[key] = type(value) == "table" and CopyTable(value) or value
    end

    if _G._CUMT_StandaloneRefresh then
        _G._CUMT_StandaloneRefresh()
    end
    return true
end

-- Standalone frame (standaloneFrame / standaloneCreated are declared above
-- StartTimerLoop, which reads them)
local unlockLayoutActive = false -- force preview layout while Unlock Mode is open

-- NOTE: this function must come after the "local standaloneFrame" and
-- "local db" declarations. Placed earlier in the file (before those
-- locals) Lua would bind it to the same-named GLOBALS (which are never set)
-- instead of the locals, so it would always hit its early return immediately.
--
-- Uses the shared border system from CludesUI.lua (CludesUI.ApplyBorderStyle)
-- rather than a bespoke solution:
--   - "solid"           -> PP 4-strip system (as everywhere else in the addon)
--   - any other key     -> textured BackdropTemplate border (Glow, Blizzard,
--                          Lightspark, SharedMedia, ...)
-- ApplyBorderStyle needs a frame WE own ("borderFrame"). Bar shells ("_barHost",
-- "_enemyBarHost", "_timerSegHosts") are the outer geometry anchors; each holds
-- an inset clip child for the bg/fill textures so textured fills cannot bleed
-- past the border (see GetBarBleedInset / EnsureBarShell).
--
-- Border carrier is parented to the STANDALONE frame (not the host): the host
-- uses SetClipsChildren to cut fill fringe, which would also clip an outward
-- textured border if the border lived inside the host. Frame level is raised
-- above the host's tick layer every apply so the continuous TICKS fill cannot
-- paint over the border strips.
local function ApplyBorderTo(hostFrame, anchor, key, p, size, texKey, r, g, b, a, px)
    if not hostFrame or not anchor then
        return
    end

    local bf = hostFrame[key]
    -- Zero cost unless enabled: when the border is off (size 0 or the anchor is
    -- hidden) and no carrier frame was ever built, do nothing. No frame is
    -- created and no restyle runs for users who never turn a border on.
    if not bf and (size <= 0 or not anchor:IsShown()) then
        return
    end
    if not bf then
        bf = CreateFrame("Frame", nil, hostFrame)
        bf:EnableMouse(false)
        -- Clip every border (including textured styles with an outward
        -- offsetX/offsetY, e.g. Glow/Blizzard) strictly to the area of "bf"
        -- (== the bar/segment). Without this, textured border styles spill past
        -- the segment edges and overlap in the gaps between segments.
        bf:SetClipsChildren(true)
        hostFrame[key] = bf
        hostFrame._emtBordersBuilt = true
    end

    bf:ClearAllPoints()
    bf:SetAllPoints(anchor)
    -- Always re-assert above the bar host tree (clip + tick layer). A one-time
    -- level at create time can lose to a later tick-layer bump on the continuous
    -- TICKS bar, letting the melli fill paint over the border.
    local anchorLevel = anchor.GetFrameLevel and anchor:GetFrameLevel() or 0
    local parentLevel = hostFrame.GetFrameLevel and hostFrame:GetFrameLevel() or 0
    bf:SetFrameLevel(max(parentLevel + 10, anchorLevel + 20))

    if size <= 0 or not anchor:IsShown() then
        bf:Hide()
        CludesUI.ApplyBorderStyle(bf, 0, r, g, b, a, texKey)
        return
    end

    bf:Show()
    CludesUI.ApplyBorderStyle(
        bf,
        size,
        r,
        g,
        b,
        a,
        texKey,
        p.borderTextureOffset,
        p.borderTextureOffsetY,
        p.borderTextureShiftX,
        p.borderTextureShiftY,
        "MythicPlus",
        size,
        nil,
        px
    )
    -- PP strip container keeps an absolute level from create time; bump it with
    -- the carrier or the strips can sit under the TICKS tick layer while the
    -- empty carrier frame alone is "above".
    local Pix = CludesUI and CludesUI.PP
    local edges = Pix and Pix.GetBorders and Pix.GetBorders(bf)
    if edges then
        edges:SetFrameLevel(bf:GetFrameLevel() + 1)
    end
end

mod.ApplyBorder = function()
    if not standaloneFrame or not db or not db.profile then
        return
    end

    local frame = standaloneFrame
    local p = db.profile
    local size = p.borderSize or 0
    -- "Custom Border Style" is the master gate: when off, no border renders
    -- regardless of the saved borderSize.
    if not p.customBorderStyle then
        size = 0
    end
    -- Zero cost unless enabled: if the border is off and none were ever built,
    -- skip the whole pass (no per-segment loop, no restyle calls).
    if size <= 0 and not frame._emtBordersBuilt then
        return
    end
    local texKey = p.borderTexture or "solid"
    local r, g, b, a = p.borderR or 0, p.borderG or 0, p.borderB or 0, p.borderA or 1
    -- Exact pixel size (nil = the legacy path), resolved once against the bar's
    -- own step: every carrier below draws either this size or a forced 0.
    local px = CludesUI.BorderPx(p.borderSizePx, size, texKey)

    -- Main timer bar. In SEGMENTS mode "_barHost" is only a layout spacer that
    -- spans the ENTIRE bar width (including the gaps between segments). Bordering
    -- it here would draw a border line in the gaps too (left/right is hidden by
    -- the adjacent segment border, top/bottom is not), so in SEGMENTS mode the
    -- main border is disabled here; the individual segment borders below draw
    -- the complete outline.
    local isSegmented = (p.timerBarStyle == "SEGMENTS")
    local barAnchor = frame._barHost or frame._barBg
    if isSegmented then
        ApplyBorderTo(frame, barAnchor, "_emtBarBorderFrame", p, 0, texKey, r, g, b, a, nil)
    else
        ApplyBorderTo(frame, barAnchor, "_emtBarBorderFrame", p, size, texKey, r, g, b, a, px)
    end

    -- Forces bar (skipped when "Apply to Forces Bar" is off in the border cog).
    local forcesSize, forcesPx = size, px
    if p.borderApplyToForces == false then
        forcesSize, forcesPx = 0, nil
    end
    ApplyBorderTo(
        frame,
        frame._enemyBarHost or frame._enemyBarBg,
        "_emtEnemyBorderFrame",
        p,
        forcesSize,
        texKey,
        r,
        g,
        b,
        a,
        forcesPx
    )

    -- Segment bars (timer bar SEGMENTS mode) -- border each segment host.
    local segSize, segPx = 0, nil
    if isSegmented then
        segSize, segPx = size, px
    end
    if frame._timerSegHosts then
        for i, owner in ipairs(frame._timerSegHosts) do
            ApplyBorderTo(frame, owner, "_emtSegBorderFrame" .. i, p, segSize, texKey, r, g, b, a, segPx)
        end
    elseif frame._timerSegBgs then
        -- Legacy texture-only segments (pre-shell); keep border working if hosts
        -- were never built this session.
        for i, seg in ipairs(frame._timerSegBgs) do
            ApplyBorderTo(frame, seg, "_emtSegBorderFrame" .. i, p, segSize, texKey, r, g, b, a, segPx)
        end
    end
end

-- Font helpers
local FALLBACK_FONT = "Fonts/FRIZQT__.TTF"
local FONT_OPTIONS = {
    { key = nil, label = "CludesUI Default" },
    { key = "Fonts/FRIZQT__.TTF", label = "Fritz Quadrata" },
    { key = "Fonts/ARIALN.TTF", label = "Arial Narrow" },
    { key = "Fonts/MORPHEUS.TTF", label = "Morpheus" },
    { key = "Fonts/SKURRI.TTF", label = "Skurri" },
    { key = "Fonts/FRIZQT___CYR.TTF", label = "Fritz Quadrata (Cyrillic)" },
    { key = "Fonts/ARHei.TTF", label = "AR Hei (CJK)" },
}
local function SFont()
    if CludesUI and CludesUI.GetFontPath then
        local p = CludesUI.GetFontPath("mythicTimer")
        if p and p ~= "" then
            return p
        end
    end
    return FALLBACK_FONT
end
-- _CUMT_GetFontOptions removed: font dropdown deleted from options page.
local function SOutline()
    if CludesUI.GetFontOutlineFlag then
        return CludesUI.GetFontOutlineFlag("mythicTimer")
    end
    return ""
end
local function SetFS(fontStr, size, flags)
    if not fontStr then
        return
    end
    local p = SFont()
    flags = flags or SOutline()
    fontStr:SetFont(p, size, flags)
    if not fontStr:GetFont() then
        fontStr:SetFont(FALLBACK_FONT, size, flags)
    end
end
-- Per-user font override for the TIMER clock text only (profile.timerFont, a
-- dropdown key: "__global"/nil = follow the module font). SharedMedia keys
-- resolve via CludesUI.ResolveFontName, matching the Quest Tracker font
-- picker; anything else falls back to the module font (SFont).
local function TimerFont()
    local key = db and db.profile and db.profile.timerFont
    if key and key ~= "__global" and CludesUI and CludesUI.ResolveFontName then
        local filePath = CludesUI.ResolveFontName(key)
        if filePath and filePath ~= "" then
            return filePath
        end
    end
    return SFont()
end
local function SetTimerFS(fontStr, size, flags)
    if not fontStr then
        return
    end
    local p = TimerFont()
    flags = flags or SOutline()
    fontStr:SetFont(p, size, flags)
    if not fontStr:GetFont() then
        fontStr:SetFont(FALLBACK_FONT, size, flags)
    end
end
local function ApplyShadow(fontStr)
    if not fontStr then
        return
    end
    local useShadow = CludesUI.GetFontUseShadow("mythicTimer")
    -- Font is set elsewhere (SetFS) and ApplyShadow runs after it, so capture
    -- and restore the current font around PrimeFontShadow's SetFontObject.
    local _pf, _ps, _pfl = fontStr:GetFont()
    CludesUI.PrimeFontShadow(fontStr, useShadow)
    if _pf then
        fontStr:SetFont(_pf, _ps, _pfl)
    end
end

-- SetText with skip-if-unchanged. Avoids the per-tick SetText call (and
-- the implicit re-measure / re-layout) when the string hasn't changed.
local function SetTextDiff(fontStr, textValue)
    if not fontStr then
        return
    end
    textValue = textValue or ""
    if fontStr._lastText == textValue then
        return
    end
    fontStr:SetText(textValue)
    fontStr._lastText = textValue
end

local function SetFittedText(fontStr, textValue, maxWidth, preferredSize, minSize)
    if not fontStr then
        return
    end
    textValue = textValue or ""
    preferredSize = preferredSize or 10
    minSize = minSize or 8
    local outline = SOutline()
    SetFS(fontStr, preferredSize, outline)
    ApplyShadow(fontStr)
    fontStr:SetText(textValue)

    for size = preferredSize, minSize, -1 do
        SetFS(fontStr, size, outline)
        ApplyShadow(fontStr)
        fontStr:SetText(textValue)
        if not maxWidth or fontStr:GetStringWidth() <= maxWidth then
            return
        end
    end
end

-- Widest single-digit glyph in fs's CURRENT font. Clock-width templates replace
-- every digit with this instead of a hardcoded "9": proportional / oldstyle
-- numeral fonts can render another digit (e.g. "0" or "3") wider than "9", so a
-- "9" template under-measures and the pinned width then ellipsizes the live clock
-- (e.g. "33:00"). fs must already have its final font applied. Clears the width so
-- the per-glyph measurements are unbounded. Called only when a width cache key
-- changes (font / size / scale / length), never per tick.
local function WidestDigitChar(fontStr)
    fontStr:SetWidth(0)
    local widest, widestW = "9", 0
    for skinData = 0, 9 do
        local ch = tostring(skinData)
        fontStr:SetText(ch)
        local wid = fontStr:GetStringWidth() or 0
        if wid > widestW then
            widestW = wid
            widest = ch
        end
    end
    return widest
end

-- Set a threshold FontString's text and pin it to a stable, jitter-free width
-- based on the widest digit in the current font, so the small +2 / +3 / remaining
-- countdowns do not "breathe" horizontally as the seconds tick in a proportional
-- font (the same width-pin idea the main clock uses, applied to the threshold
-- row). Color escapes are zero-width, so they are stripped before templatizing.
-- The caller (placeAt) sets JustifyH to match the anchor edge so one edge stays
-- fixed. Returns the pinned width for the remaining-mode overlap packing.
local function SetThreshText(fontStr, textValue)
    local visible = (textValue:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
    fontStr:SetText((visible:gsub("%d", WidestDigitChar(fontStr))))
    -- +1px only (vs the clock's +3): the widest-digit template already covers the
    -- worst-case text for this length, so 1px is enough to absorb subpixel rounding
    -- at fractional UI scales -- keeps packed labels tight when GAP is 0.
    local wid = (fontStr:GetStringWidth() or 0) + 1
    fontStr:SetWidth(wid)
    fontStr:SetText(textValue)
    return wid
end

local function GetAccentColor()
    if CludesUI.ResolveActiveAccent then
        return CludesUI.ResolveActiveAccent()
    end
    return 0.05, 0.83, 0.62
end

-- Current pull bar: one StatusBar per enemy in combat, chained off the end of
-- the forces fill. In M+ the per-unit forces values are secret (tainted code
-- can neither add nor compare them) and unit identity is restricted, so the
-- pull total is never computed in Lua: each value goes straight into SetValue
-- and the segments add up on screen by anchoring each one to the previous
-- segment's fill edge. The host clips anything past 100%.
-- The full render stores the layout and style on the frame (f._pull*); plate
-- and regen events then only re-place the segments via UpdatePullSegments.
local RenderPullSegments, HidePullSegments, SyncPullEvents
do
    local PLATE_UNITS = {}
    for i = 1, 40 do
        PLATE_UNITS[i] = "nameplate" .. i
    end
    local GROUP_UNITS = { "player", "party1", "party2", "party3", "party4" }

    -- A secret never counts as true.
    local function IsPlainTrue(val)
        if val == nil or (issecretvalue and issecretvalue(val)) then
            return false
        end
        return val == true
    end

    -- Enemies only count while someone in the group fights, so the plate scan
    -- is skipped between pulls. Party members keep it alive after a death.
    local function GroupInCombat()
        for i = 1, #GROUP_UNITS do
            if IsPlainTrue(UnitAffectingCombat(GROUP_UNITS[i])) then
                return true
            end
        end
        return false
    end

    -- Without `from` this is a full hide: it also stops event-driven updates
    -- from re-showing segments until the next full render turns them back on.
    HidePullSegments = function(frame, from)
        if not from then
            frame._pullOn = false
        end
        local segs = frame._pullSegs
        if not segs then
            return
        end
        for i = from or 1, #segs do
            segs[i]:Hide()
        end
    end

    -- Returns the placed segment's fill texture, the anchor for the next one.
    -- Texture, color, range and size are re-applied only when the render's
    -- style version changed; per update a segment just re-anchors and SetValues.
    local function PlaceSegment(frame, num, anchor, value)
        local seg = frame._pullSegs[num]
        if not seg then
            seg = CreateFrame("StatusBar", nil, frame._pullClip)
            seg:EnableMouse(false)
            frame._pullSegs[num] = seg
        end
        if seg._styleVer ~= frame._pullStyleVer then
            seg._styleVer = frame._pullStyleVer
            seg:SetStatusBarTexture(frame._pullTex)
            seg:SetStatusBarColor(frame._pullR, frame._pullG, frame._pullB, frame._pullA)
            seg:SetMinMaxValues(0, frame._pullTotal)
            seg:SetSize(frame._pullW, frame._pullH)
        end
        seg:ClearAllPoints()
        seg:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 0, 0)
        seg:SetValue(value)
        seg:Show()
        return seg:GetStatusBarTexture()
    end

    local function UpdatePullSegments(frame)
        if not (frame and frame._pullOn) then
            return
        end
        local anchor, num = frame._enemyBarFill, 0
        local previewValues = frame._pullPreview
        if previewValues then
            for i = 1, #previewValues do
                num = num + 1
                anchor = PlaceSegment(frame, num, anchor, previewValues[i])
            end
        elseif C_ScenarioInfo and C_ScenarioInfo.GetUnitCriteriaProgressValues and GroupInCombat() then
            for i = 1, #PLATE_UNITS do
                local unitToken = PLATE_UNITS[i]
                if
                    IsPlainTrue(UnitExists(unitToken))
                    and IsPlainTrue(UnitCanAttack("player", unitToken))
                    and IsPlainTrue(UnitAffectingCombat(unitToken))
                    and not IsPlainTrue(UnitIsDead(unitToken))
                then
                    -- nil for enemies that give no forces. The value itself is
                    -- only ever handed to SetValue, never read: the nil test
                    -- reads its type tag, never the (secret) value.
                    local value = C_ScenarioInfo.GetUnitCriteriaProgressValues(unitToken)
                    if type(value) ~= "nil" then
                        num = num + 1
                        anchor = PlaceSegment(frame, num, anchor, value)
                    end
                end
            end
        end
        HidePullSegments(frame, num + 1)
    end

    RenderPullSegments = function(frame, clip, run, enemyObj, p, wid, hgt, barR, barG, barB)
        SyncPullEvents()
        local sum = enemyObj.rawTotalQuantity
        if p.showPullBar ~= true or enemyObj.completed or not sum or sum <= 0 then
            HidePullSegments(frame)
            return
        end
        if not frame._pullSegs then
            frame._pullSegs = {}
        end

        local r, g, b = barR, barG, barB
        if p.pullBarUseBarColor == false then
            r, g, b = GetColor(p.pullBarColor, 1, 0.55, 0.1)
        end
        local a = p.pullBarAlpha or 0.35
        local texPath = CludesUI.ResolveTexturePath(barTextures, p.enemyBarTexture or "none", nil)
            or "Interface\\Buttons\\WHITE8X8"

        if
            frame._pullTex ~= texPath
            or frame._pullR ~= r
            or frame._pullG ~= g
            or frame._pullB ~= b
            or frame._pullA ~= a
            or frame._pullTotal ~= sum
            or frame._pullW ~= wid
            or frame._pullH ~= hgt
            or frame._pullClip ~= clip
        then
            frame._pullTex, frame._pullR, frame._pullG, frame._pullB, frame._pullA = texPath, r, g, b, a
            frame._pullTotal, frame._pullW, frame._pullH, frame._pullClip = sum, wid, hgt, clip
            frame._pullStyleVer = (frame._pullStyleVer or 0) + 1
        end
        frame._pullOn = true
        frame._pullPreview = run._previewPullValues
        UpdatePullSegments(frame)
    end

    -- Event side. Regen events (twice per pull) are registered while a run is
    -- active with the bar enabled; nameplate events additionally only while
    -- the player is in combat, so segments follow enemies joining the fight
    -- between the 1/sec ticks. SyncPullEvents runs from the run-event toggle,
    -- the regen events and every full render, so enabling the option mid-run,
    -- mid-combat or after a mid-key /reload converges within a second.
    local pullFrame = CreateFrame("Frame")
    local PLATE_EVENTS = { "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED" }
    local regenOn, platesOn = false, false
    local updatePending = false

    local function RunPendingUpdate()
        updatePending = false
        UpdatePullSegments(standaloneFrame)
    end

    SyncPullEvents = function(inCombat)
        local p = db and db.profile
        local on = (currentRun.active and p and p.showPullBar == true and p.showEnemyBar ~= false) and true
            or false
        if inCombat == nil then
            inCombat = InCombatLockdown()
        end
        local plates = on and inCombat and true or false
        if on ~= regenOn then
            regenOn = on
            if on then
                pullFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
                pullFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
            else
                pullFrame:UnregisterEvent("PLAYER_REGEN_DISABLED")
                pullFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
            end
        end
        if plates ~= platesOn then
            platesOn = plates
            for i = 1, #PLATE_EVENTS do
                if plates then
                    pullFrame:RegisterEvent(PLATE_EVENTS[i])
                else
                    pullFrame:UnregisterEvent(PLATE_EVENTS[i])
                end
            end
        end
    end

    pullFrame:SetScript("OnEvent", function(_, evt)
        if evt == "PLAYER_REGEN_DISABLED" then
            SyncPullEvents(true)
        elseif evt == "PLAYER_REGEN_ENABLED" then
            SyncPullEvents(false)
        end
        -- Coalesce plate bursts (a pack scrolling into view) into one update.
        if not updatePending then
            updatePending = true
            C_Timer.After(0.05, RunPendingUpdate)
        end
    end)
end

local function StripDefeated(name)
    if not name then
        return name
    end
    name = name:gsub("[Dd]efeated", "")
    return name:match("^%s*(.-)%s*$") or name
end

local objRows = {}
local function GetObjRow(hostFrame, position)
    if objRows[position] then
        return objRows[position]
    end
    local nameFS = hostFrame:CreateFontString(nil, "OVERLAY")
    nameFS:SetWordWrap(false)
    nameFS:SetNonSpaceWrap(false)
    local timeFS = hostFrame:CreateFontString(nil, "OVERLAY")
    timeFS:SetWordWrap(false)
    timeFS:SetNonSpaceWrap(false)
    local record = { name = nameFS, time = timeFS }
    objRows[position] = record
    return record
end

local function CreateStandaloneFrame()
    if standaloneCreated then
        return standaloneFrame
    end
    standaloneCreated = true

    local frame = CreateFrame("Frame", "CludesUIMythicTimerStandalone", UIParent, "BackdropTemplate")
    frame:SetSize(260, 200)
    -- Default position: top of quest tracker, or right-side fallback
    local otf = _G.ObjectiveTrackerFrame
    if otf and otf:GetTop() then
        frame:SetPoint("TOPRIGHT", otf, "TOPRIGHT", 0, 0)
    else
        frame:SetPoint("RIGHT", UIParent, "RIGHT", -100, 0)
    end
    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(10)
    frame:SetClampedToScreen(true)

    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(0.05, 0.04, 0.08, 0.85)
    frame:SetBackdropBorderColor(0.15, 0.15, 0.15, 0.6)

    -- Dedicated layer for text that sits ABOVE the bars (timer / forces /
    -- threshold text). ns.ApplyBorder() gives each bar/segment a border wrapper
    -- frame that always sits above "f" (ApplyBorderStyle's border container
    -- frame is always FrameLevel = passed frame + 1). Without this layer the
    -- border would therefore ALWAYS sit above the text, whatever draw layer the
    -- text uses (frame level beats draw layer across different frames). Must be
    -- created BEFORE the fontstrings below so they can be reparented onto it.
    frame._emtTextLayer = CreateFrame("Frame", nil, frame)
    frame._emtTextLayer:SetFrameLevel(frame:GetFrameLevel() + 30)
    frame._emtTextLayer:EnableMouse(false)

    frame._accent = frame:CreateTexture(nil, "BORDER")
    frame._accent:SetWidth(2)
    frame._accent:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
    frame._accent:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)

    frame._titleFS = frame:CreateFontString(nil, "OVERLAY")
    frame._titleFS:SetWordWrap(false)
    frame._titleFS:SetJustifyV("MIDDLE")

    frame._affixFS = frame:CreateFontString(nil, "OVERLAY")
    frame._affixFS:SetWordWrap(true)

    frame._timerFS = frame:CreateFontString(nil, "OVERLAY")
    frame._timerFS:SetJustifyH("CENTER")
    frame._timerFS:SetWordWrap(false)
    frame._timerFS:SetNonSpaceWrap(false)
    -- Optional "+key  |" prefix rendered to the left of the timer clock
    -- (Show Key Level on Timer). Single-anchored, no explicit width, so it
    -- auto-sizes and never truncates.
    frame._keyLevelFS = frame:CreateFontString(nil, "OVERLAY")
    frame._keyLevelFS:SetWordWrap(false)
    frame._keyLevelFS:SetNonSpaceWrap(false)
    frame._timerDetailFS = frame:CreateFontString(nil, "OVERLAY")
    frame._timerDetailFS:SetWordWrap(false)
    frame._timerDetailFS:SetNonSpaceWrap(false)
    -- Timer bar shell: outer host is the border/geometry anchor; inset clip holds
    -- bg+fill so textured fills (Melli etc.) cannot bleed past the border.
    -- Tick markers sit on a sibling layer ABOVE the clip frame (child frames draw
    -- after parent textures, so ticks cannot live on the host itself).
    local barHost, barClip = EnsureBarShell(frame, "_barHost")
    frame._barBg, frame._barFill = EnsureShellTextures(barClip, frame, "_barBg", "_barFill")
    frame._barTickLayer = CreateFrame("Frame", nil, barHost)
    frame._barTickLayer:SetAllPoints(barHost)
    frame._barTickLayer:EnableMouse(false)
    frame._barTickLayer:SetFrameLevel(barClip:GetFrameLevel() + 2)
    frame._seg3 = frame._barTickLayer:CreateTexture(nil, "OVERLAY")
    frame._seg2 = frame._barTickLayer:CreateTexture(nil, "OVERLAY")
    frame._threshFS = frame:CreateFontString(nil, "OVERLAY")
    frame._threshFS:SetParent(frame._emtTextLayer)
    frame._threshFS:SetWordWrap(false)
    frame._threshFS2 = frame:CreateFontString(nil, "OVERLAY")
    frame._threshFS2:SetParent(frame._emtTextLayer)
    frame._threshFS2:SetWordWrap(false)
    frame._threshRemFS = frame:CreateFontString(nil, "OVERLAY")
    frame._threshRemFS:SetParent(frame._emtTextLayer)
    frame._threshRemFS:SetWordWrap(false)
    frame._deathFS = frame:CreateFontString(nil, "OVERLAY")
    frame._deathFS:SetWordWrap(false)
    frame._deathHit = CreateFrame("Frame", nil, frame)
    frame._deathHit:SetFrameLevel(frame:GetFrameLevel() + 5)
    frame._deathHit:EnableMouse(true)

    -- Custom two-column death tooltip
    local deathTT = CreateFrame("Frame", nil, UIParent)
    deathTT:SetFrameStrata("TOOLTIP")
    deathTT:SetFrameLevel(200)
    deathTT:Hide()
    local ttBg = deathTT:CreateTexture(nil, "BACKGROUND")
    ttBg:SetAllPoints()
    ttBg:SetColorTexture(0.067, 0.067, 0.067, 0.90)
    CludesUI.MakeBorder(deathTT, 1, 1, 1, 0.15, CludesUI.PanelPP)
    deathTT._rows = {}

    local TT_PAD = 8
    local TT_ROW_H = 14
    local TT_GAP = 3
    local TT_FONT = CludesUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF"

    local function EnsureRows(num)
        for i = #deathTT._rows + 1, num do
            local nameFS = deathTT:CreateFontString(nil, "OVERLAY")
            -- A group member's name: a font family (Cyrillic, Korean and Chinese
            -- names draw), no shadow, its only font write.
            CludesUI.SetFontFamily(nameFS, TT_FONT, 10, "", false)
            nameFS:SetJustifyH("LEFT")
            local countFS = deathTT:CreateFontString(nil, "OVERLAY")
            countFS:SetFont(TT_FONT, 10, "")
            countFS:SetJustifyH("RIGHT")
            deathTT._rows[i] = { name = nameFS, count = countFS }
        end
    end

    frame._deathHit:SetScript("OnEnter", function(self)
        local deaths = playerDeaths
        if not next(deaths) and currentRun.deaths and currentRun.deaths > 0 then
            deaths = { [UnitName("player") or "You"] = currentRun.deaths }
        end
        if not next(deaths) then
            return
        end

        local list = {}
        for name, count in pairs(deaths) do
            list[#list + 1] = { name = name, count = count }
        end
        table.sort(list, function(a, b)
            if a.count ~= b.count then
                return a.count > b.count
            end
            return a.name < b.name
        end)

        EnsureRows(#list)

        -- Hide all rows first
        for i = 1, #deathTT._rows do
            deathTT._rows[i].name:Hide()
            deathTT._rows[i].count:Hide()
        end

        -- Measure max name width for tooltip sizing
        local maxNameW = 0
        local maxCountW = 0
        for i, record in ipairs(list) do
            local row = deathTT._rows[i]
            local class = select(2, UnitClass(record.name))
            local color = class and (RAID_CLASS_COLORS[class] or RAID_CLASS_COLORS["PRIEST"])
            local short = Ambiguate and Ambiguate(record.name, "short") or record.name
            local colored = color and color:WrapTextInColorCode(short) or short
            row.name:SetText(colored)
            row.name:SetTextColor(1, 1, 1, 0.80)
            row.count:SetText(record.count)
            row.count:SetTextColor(1, 1, 1, 0.80)
            local nw = row.name:GetStringWidth() or 0
            local cw = row.count:GetStringWidth() or 0
            if nw > maxNameW then
                maxNameW = nw
            end
            if cw > maxCountW then
                maxCountW = cw
            end
        end

        local ttW = TT_PAD + maxNameW + 12 + maxCountW + TT_PAD
        local ttH = TT_PAD + #list * TT_ROW_H + (#list - 1) * TT_GAP + TT_PAD

        deathTT:SetSize(ttW, ttH)

        -- Position rows
        for i, record in ipairs(list) do
            local row = deathTT._rows[i]
            local yOff = -TT_PAD - (i - 1) * (TT_ROW_H + TT_GAP)
            row.name:ClearAllPoints()
            row.name:SetPoint("TOPLEFT", deathTT, "TOPLEFT", TT_PAD, yOff)
            row.count:ClearAllPoints()
            row.count:SetPoint("TOPRIGHT", deathTT, "TOPRIGHT", -TT_PAD, yOff)
            row.name:Show()
            row.count:Show()
        end

        -- Anchor tooltip above the death text
        local right = (self._align or "LEFT") == "RIGHT"
        deathTT:ClearAllPoints()
        if right then
            deathTT:SetPoint("BOTTOMRIGHT", self, "TOPRIGHT", 0, 4)
        else
            deathTT:SetPoint("BOTTOMLEFT", self, "TOPLEFT", 0, 4)
        end
        deathTT:Show()
    end)
    frame._deathHit:SetScript("OnLeave", function()
        deathTT:Hide()
    end)
    frame._enemyFS = frame:CreateFontString(nil, "OVERLAY")
    frame._enemyFS:SetParent(frame._emtTextLayer)
    frame._enemyFS:SetWordWrap(false)
    local enemyHost, enemyClip = EnsureBarShell(frame, "_enemyBarHost")
    frame._enemyBarBg, frame._enemyBarFill = EnsureShellTextures(enemyClip, frame, "_enemyBarBg", "_enemyBarFill")
    frame._previewFS = frame:CreateFontString(nil, "OVERLAY")
    frame._previewFS:SetWordWrap(false)

    -- Hidden until RenderStandalone() shows it
    frame:Hide()

    -- Apply saved scale and position immediately so the frame never flashes at default
    if db and db.profile then
        local scale = db.profile.scale or 1.0
        if scale == 0 then
            scale = 1.0
        end
        frame:SetScale(scale)
        if db.profile.standalonePos then
            local place = db.profile.standalonePos
            local cx, cy = place.centerX, place.centerY
            if not cx then
                -- Legacy TOPLEFT-stored position; will be migrated to center
                -- on the first ApplyStandalonePosition / drag-save call.
                frame:ClearAllPoints()
                frame:SetPoint(
                    place.point or "TOPLEFT",
                    UIParent,
                    place.relPoint or "BOTTOMLEFT",
                    place.x or 0,
                    place.y or 0
                )
            else
                frame:ClearAllPoints()
                frame:SetPoint("CENTER", UIParent, "CENTER", cx / scale, cy / scale)
            end
        end
    end

    standaloneFrame = frame
    -- If a run is already active (e.g. /reload mid-key), wire up the
    -- OnUpdate fallback now that the frame exists.
    if _timerLoopWanted then
        _onUpdateAccum = 0
        frame:SetScript("OnUpdate", OnUpdateFallback)
    end
    return frame
end

local function RenderStandalone()
    if not db or not db.profile.enabled then
        if standaloneFrame then
            standaloneFrame:Hide()
        end
        return
    end

    local p = db.profile
    local isPreview = false
    local run = currentRun
    if not run.active and not run.completed then
        if p.showPreview or unlockLayoutActive then
            run = PREVIEW_RUN
            LocalizePreview()
            isPreview = true
        else
            if standaloneFrame then
                standaloneFrame:Hide()
            end
            return
        end
    end

    local frame = CreateStandaloneFrame()
    local PAD = 12
    local ALIGN_PAD = 0
    local TBAR_PAD = 0
    local configuredTimerBarH = p.barHeight or 8
    local expandedH = p.barHeightExpanded or 22
    -- The in-bar timer only exists while the bar is shown; otherwise fall back
    -- to the standalone clock instead of hiding the timer entirely.
    local timerInBar = p.timerInBar and p.showTimerBar ~= false
    local TBAR_H = timerInBar and max(configuredTimerBarH, expandedH) or configuredTimerBarH
    local ENEMY_BAR_H = p.enemyBarHeight or p.barHeight or 8
    local ROW_GAP = p.rowGap or 6
    local OBJ_GAP = p.objectiveGap or 4

    frame:SetWidth(p.frameWidth or 260)

    -- Scale ownership lives in ApplyStandalonePosition (called from
    -- _CUMT_ApplyTimer on slider changes). Don't SetScale here -- doing so on
    -- every render can race the anchor and visually shift the frame.
    local alpha = p.standaloneAlpha or 0.85
    frame:SetBackdropColor(0.05, 0.04, 0.08, alpha)
    frame:SetBackdropBorderColor(0.15, 0.15, 0.15, min(alpha, 0.6))

    local aR, aG, aB = GetAccentColor()
    if p.showAccent then
        frame._accent:SetColorTexture(aR, aG, aB, 0.9)
        frame._accent:Show()
    else
        frame._accent:Hide()
    end

    local frameW = frame:GetWidth()
    local innerW = frameW - PAD * 2
    local posY = -PAD

    -- "Show Key Level on Timer": render "+key  |" to the left of the timer clock.
    -- Gated on the dungeon name being hidden (the title is then just the lone key
    -- level, which relocates onto the timer line). Used by RenderTitleAffixes (to
    -- suppress the now-redundant title) and by the timer block below.
    local keyLevelOnTimer = (p.showKeyLevelOnTimer == true) and (p.showDungeonName == false)

    local function ContentPad(align)
        if align == "LEFT" or align == "RIGHT" then
            return PAD + ALIGN_PAD
        end
        return PAD
    end

    local _gAlign = (p.alignAllText == "LEFT") and "LEFT" or "RIGHT"
    local function _ra()
        return _gAlign
    end

    local function RenderTitleAffixes()
        local titleAlign = _ra(p.titleAlign or "CENTER")
        local tR, tG, tB
        if p.titleUseAccent ~= false then
            tR, tG, tB = aR, aG, aB
        elseif p.titleColor then
            tR, tG, tB = p.titleColor.r or 1, p.titleColor.g or 1, p.titleColor.b or 1
        else
            tR, tG, tB = 1, 1, 1
        end
        -- When "Show Key Level on Timer" is on (only possible with the dungeon
        -- name hidden), the title would be just the lone "+key" -- that moves down
        -- onto the timer line instead, so suppress the title row entirely here.
        -- keyLevelOnTimer is a function-scope upvalue computed once near the top.
        if p.showTitle ~= false and not keyLevelOnTimer then
            local title
            if p.showDungeonName == false then
                -- Show only the key level number, not the dungeon name.
                title = format("%s+%d|r", CludesUI.HexColor(tR, tG, tB), run.level)
            else
                title =
                    format("%s+%d  %s|r", CludesUI.HexColor(tR, tG, tB), run.level, run.mapName or "Mythic+")
            end
            frame._titleFS:SetJustifyH(titleAlign)
            frame._titleFS:SetTextColor(1, 1, 1)
            local titleMax = p.titleSize or 13
            local titleMin = max(8, titleMax - 3)
            SetFittedText(frame._titleFS, title, innerW, titleMax, titleMin)
            frame._titleFS:ClearAllPoints()
            frame._titleFS:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, posY)
            frame._titleFS:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, posY)
            frame._titleFS:Show()
            local titleH = frame._titleFS:GetStringHeight() or titleMax
            posY = posY - titleH - 2 - ROW_GAP
        else
            frame._titleFS:Hide()
        end

        if p.showAffixes then
            local nameList = {}
            if run._previewAffixNames then
                for _, name in ipairs(run._previewAffixNames) do
                    nameList[#nameList + 1] = name
                end
            else
                -- Use the cached affix names snapshotted at StartRun. Falls back
                -- to GetAffixInfo only if cache is missing (run started before
                -- this code path was added, or preview mode).
                for i, ident in ipairs(run.affixes) do
                    local name = (run.affixNames and run.affixNames[i]) or C_ChallengeMode.GetAffixInfo(ident)
                    if name then
                        nameList[#nameList + 1] = name
                    end
                end
            end
            if #nameList > 0 then
                frame._affixFS:SetTextColor(GetColor(p.affixTextColor, 1, 1, 1))
                frame._affixFS:SetJustifyH(titleAlign)
                local affixMax = p.affixSize or 10
                local affixMin = max(6, affixMax - 2)
                SetFittedText(frame._affixFS, table.concat(nameList, "  \194\183  "), innerW, affixMax, affixMin)
                frame._affixFS:ClearAllPoints()
                frame._affixFS:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, posY + 5)
                frame._affixFS:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, posY + 5)
                frame._affixFS:Show()
                posY = posY - (frame._affixFS:GetStringHeight() or 12) - ROW_GAP + 5
            else
                frame._affixFS:Hide()
            end
        else
            frame._affixFS:Hide()
        end
    end

    local titleAffixBelowTimer = (p.titleAffixPosition == "BELOW_TIMER")
    local defaultTitleDeathGap = ROW_GAP + 5
    local defaultSandwichGap = ROW_GAP
    if not titleAffixBelowTimer then
        RenderTitleAffixes()
        posY = posY - ((p.titleAffixDeathGap or defaultTitleDeathGap) - defaultTitleDeathGap)
    end

    -- Deaths (toggle removed; always on when there are deaths)
    if run.deaths > 0 and not p.deathsInTitle then
        local deathAlign = _ra(p.deathAlign or "LEFT")
        local dPad = ContentPad(deathAlign)
        SetFS(frame._deathFS, 12)
        ApplyShadow(frame._deathFS)
        local dR, dG, dB = GetColor(p.deathTextColor, 0.93, 0.33, 0.33)
        frame._deathFS:SetTextColor(dR, dG, dB)
        frame._deathFS:SetText(
            run.deaths == 1 and CludesUI.Lf("%1$d Death  -%2$s", run.deaths, FormatTime(run.deathTimeLost))
                or CludesUI.Lf("%1$d Deaths  -%2$s", run.deaths, FormatTime(run.deathTimeLost))
        )
        frame._deathFS:ClearAllPoints()
        frame._deathFS:SetPoint("TOPLEFT", frame, "TOPLEFT", dPad, posY - 5)
        frame._deathFS:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -dPad, posY - 5)
        frame._deathFS:SetJustifyH(deathAlign)
        frame._deathFS:Show()
        -- Position hit frame over the actual text, not the full row
        local textW = frame._deathFS:GetStringWidth() or 0
        local textH = frame._deathFS:GetStringHeight() or 12
        frame._deathHit:ClearAllPoints()
        frame._deathHit:SetSize(textW, textH)
        if deathAlign == "RIGHT" then
            frame._deathHit:SetPoint("TOPRIGHT", frame._deathFS, "TOPRIGHT", 0, 0)
        else
            frame._deathHit:SetPoint("TOPLEFT", frame._deathFS, "TOPLEFT", 0, 0)
        end
        frame._deathHit._align = deathAlign
        frame._deathHit:Show()
        posY = posY - (frame._deathFS:GetStringHeight() or 12) - ROW_GAP - 5
    else
        frame._deathFS:Hide()
        frame._deathHit:Hide()
        if titleAffixBelowTimer and not p.deathsInTitle then
            posY = posY - 12 - ROW_GAP - 5
        end
    end

    -- Timer colours
    local elapsed = run.elapsed or 0
    local maxTime = run.maxTime or 0
    local timeLeft = max(0, maxTime - elapsed)
    local plusTwoT, plusThreeT = CalculateBonusTimers(maxTime, run.affixes)
    -- A completed run's elapsed is its completion time (CompleteRun)
    local timerBarR, timerBarG, timerBarB
    if p.timerBarStyle == "SEGMENTS" then
        timerBarR, timerBarG, timerBarB = GetTimerSegmentFillColor(p, elapsed, plusThreeT, plusTwoT)
    else
        timerBarR, timerBarG, timerBarB = GetTimerBarFillColor(p, elapsed, plusThreeT, plusTwoT, maxTime)
    end

    -- Build timer text per user-selected display mode.
    --   REMAINING        -> "11:37"   (or "+OT" when overtime)
    --   REMAINING_TOTAL  -> "11:37 / 33:00"
    --   ELAPSED          -> "21:23"
    --   ELAPSED_DETAIL   -> "21:23 (11:37 / 33:00)"
    local timerText
    local timerDetailText
    if run.completed then
        -- Completed run: freeze the clock at the final elapsed seconds but preserve the
        -- user's chosen display mode so "/33:00" doesn't vanish on completion.
        local mode = p.timerDisplayMode or "REMAINING_TOTAL"
        local elaStr = FormatTime(elapsed)
        local maxStr = FormatTime(maxTime)
        if mode == "REMAINING_TOTAL" then
            timerText = elaStr .. " / " .. maxStr
        elseif mode == "ELAPSED_DETAIL" then
            timerText = elaStr
            timerDetailText = " (" .. elaStr .. " / " .. maxStr .. ")"
        else
            timerText = elaStr
        end
    else
        local mode = p.timerDisplayMode or "REMAINING_TOTAL"
        local elaStr = FormatTime(elapsed)
        local maxStr = FormatTime(maxTime)
        local remStr = FormatRemaining(maxTime - elapsed)
        if mode == "REMAINING_TOTAL" then
            timerText = elaStr .. " / " .. maxStr
        elseif mode == "ELAPSED" then
            timerText = remStr
        elseif mode == "ELAPSED_DETAIL" then
            timerText = remStr
            timerDetailText = " (" .. elaStr .. " / " .. maxStr .. ")"
        else
            timerText = elaStr
        end
    end

    local tR, tG, tB = 1, 1, 1
    local depleted = (run.completed and elapsed > maxTime)
        or ((not run.completed) and timeLeft <= 0 and maxTime > 0)
    if depleted then
        tR, tG, tB = GetColor(p.timerExpiredColor, 0.9, 0.2, 0.2)
    end

    local underBarMode = (p.enemyForcesPos == "UNDER_BAR")

    -- Threshold text
    local _barW_for_thresh = math.min(p.barWidth or 210, innerW - TBAR_PAD * 2)
    if _barW_for_thresh < 60 then
        _barW_for_thresh = 60
    end

    local function RenderThresholdText()
        if p.showTimerBar == false and p.showEnemyBar == false then
            frame._threshFS:Hide()
            frame._threshFS2:Hide()
            frame._threshRemFS:Hide()
            return
        end

        local showRem = p.showThreshRemaining == true
        if (p.showPlusTwoTimer or p.showPlusThreeTimer or showRem) and maxTime > 0 then
            local plusThreeSize = p.thresholdPlusThreeSize or p.thresholdSize or 12
            local plusTwoSize = p.thresholdPlusTwoSize or p.thresholdSize or 12
            local plusOneSize = p.thresholdPlusOneSize or p.thresholdSize or 12
            local thresholdRowSize = max(
                p.showPlusThreeTimer and plusThreeSize or 0,
                p.showPlusTwoTimer and plusTwoSize or 0,
                showRem and plusOneSize or 0,
                12
            )

            local function buildLabel(threshTime, color)
                local diff = threshTime - elapsed
                if diff >= 0 then
                    local cR, cG, cB = GetColor(color, 0.3, 0.8, 1)
                    return format("%s%s|r", CludesUI.HexColor(cR, cG, cB), FormatTime(diff))
                end
                return format("|cff999999%s|r", FormatTime(threshTime))
            end

            local segmentedThresholds = (p.timerBarStyle == "SEGMENTS")
            local segmentGap = segmentedThresholds and max(0, p.timerBarSegmentGap or 2) or 0
            local plusThreeLabelX =
                max(0, min(_barW_for_thresh, _barW_for_thresh * (plusThreeT / maxTime) - segmentGap / 2))
            local plusTwoLabelX =
                max(0, min(_barW_for_thresh, _barW_for_thresh * (plusTwoT / maxTime) - segmentGap / 2))
            local thresholdAnchorBar = frame._barHost or frame._barBg
            if underBarMode and p.showTimerBar == false and p.showEnemyBar ~= false then
                thresholdAnchorBar = frame._enemyBarHost or frame._enemyBarBg
            end

            -- Anchor a FontString at bar-local x = cx in the threshold row.
            -- In segmented mode, +2/+3 labels right-align to segment ends.
            local function placeAt(fontStr, cx, rightJustified, offsetX, offsetY)
                local offX = offsetX
                local offY = offsetY
                if offX == nil then
                    offX = p.thresholdTextOffsetX or 0
                end
                if offY == nil then
                    offY = p.thresholdTextOffsetY or 0
                end
                local aboveBar = underBarMode or segmentedThresholds
                local anchorPoint
                if rightJustified then
                    anchorPoint = aboveBar and "BOTTOMRIGHT" or "TOPRIGHT"
                else
                    anchorPoint = aboveBar and "BOTTOM" or "TOP"
                end
                -- Justify to the anchored edge so the pinned width leaves the
                -- fixed edge steady: right-anchored labels keep their right edge on
                -- the segment/bar end; center-anchored labels align left inside a
                -- box centered on the tick (near-centered, but the digits no longer
                -- shift as the seconds tick, since the widest-digit pin keeps the
                -- box a couple px wider than the live text).
                fontStr:SetJustifyH(rightJustified and "RIGHT" or "LEFT")
                fontStr:ClearAllPoints()
                if aboveBar then
                    -- threshold rendered before the bar -> sit above the bar
                    fontStr:SetPoint(anchorPoint, thresholdAnchorBar, "TOPLEFT", cx + offX, 2 + offY)
                else
                    -- threshold rendered after the bar -> sit below the bar
                    fontStr:SetPoint(anchorPoint, thresholdAnchorBar, "BOTTOMLEFT", cx + offX, -2 + offY)
                end
            end

            -- Prepare each visible FontString (text + style) up front. Each is
            -- pinned to a jitter-free width via SetThreshText; the returned widths
            -- feed the remaining-mode overlap packing below (in place of a live,
            -- per-second GetStringWidth that would make the packing shift too).
            local threshW3, threshW2, threshWr = 0, 0, 0
            if p.showPlusThreeTimer then
                SetFS(frame._threshFS, plusThreeSize)
                ApplyShadow(frame._threshFS)
                frame._threshFS:SetTextColor(1, 1, 1)
                local c1r, c1g, c1b = GetTimerSegmentTextColor(p, 1)
                threshW3 = SetThreshText(frame._threshFS, buildLabel(plusThreeT, { r = c1r, g = c1g, b = c1b }))
            end
            if p.showPlusTwoTimer then
                SetFS(frame._threshFS2, plusTwoSize)
                ApplyShadow(frame._threshFS2)
                frame._threshFS2:SetTextColor(1, 1, 1)
                local c2r, c2g, c2b = GetTimerSegmentTextColor(p, 2)
                threshW2 = SetThreshText(frame._threshFS2, buildLabel(plusTwoT, { r = c2r, g = c2g, b = c2b }))
            end
            if showRem then
                SetFS(frame._threshRemFS, plusOneSize)
                ApplyShadow(frame._threshRemFS)
                -- Same single MM:SS as the timer's text, showing time left in
                -- the key. In the default TICKS style it inherits the main timer
                -- color so it reddens on depletion just like the big clock (legacy
                -- behavior); the new SEGMENTS style colors it to match segment 3,
                -- and the per-row "white" toggle still forces white.
                if p.timerBarStyle == "SEGMENTS" then
                    frame._threshRemFS:SetTextColor(GetTimerSegmentTextColor(p, 3))
                elseif p.thresholdPlusOneTextWhite == true then
                    frame._threshRemFS:SetTextColor(1, 1, 1)
                else
                    frame._threshRemFS:SetTextColor(tR, tG, tB)
                end
                threshWr = SetThreshText(frame._threshRemFS, FormatRemaining(maxTime - elapsed))
            end

            if not showRem then
                -- Each threshold text sits on its tick/segment boundary.
                if p.showPlusThreeTimer then
                    placeAt(
                        frame._threshFS,
                        segmentedThresholds and plusThreeLabelX or (_barW_for_thresh * (plusThreeT / maxTime)),
                        segmentedThresholds,
                        p.thresholdPlusThreeTextOffsetX,
                        p.thresholdPlusThreeTextOffsetY
                    )
                    frame._threshFS:Show()
                else
                    frame._threshFS:Hide()
                end
                if p.showPlusTwoTimer then
                    placeAt(
                        frame._threshFS2,
                        segmentedThresholds and plusTwoLabelX or (_barW_for_thresh * (plusTwoT / maxTime)),
                        segmentedThresholds,
                        p.thresholdPlusTwoTextOffsetX,
                        p.thresholdPlusTwoTextOffsetY
                    )
                    frame._threshFS2:Show()
                else
                    frame._threshFS2:Hide()
                end
                frame._threshRemFS:Hide()
            else
                if segmentedThresholds then
                    if p.showPlusThreeTimer then
                        placeAt(
                            frame._threshFS,
                            plusThreeLabelX,
                            true,
                            p.thresholdPlusThreeTextOffsetX,
                            p.thresholdPlusThreeTextOffsetY
                        )
                        frame._threshFS:Show()
                    else
                        frame._threshFS:Hide()
                    end
                    if p.showPlusTwoTimer then
                        placeAt(
                            frame._threshFS2,
                            plusTwoLabelX,
                            true,
                            p.thresholdPlusTwoTextOffsetX,
                            p.thresholdPlusTwoTextOffsetY
                        )
                        frame._threshFS2:Show()
                    else
                        frame._threshFS2:Hide()
                    end
                    placeAt(
                        frame._threshRemFS,
                        _barW_for_thresh,
                        true,
                        p.thresholdPlusOneTextOffsetX,
                        p.thresholdPlusOneTextOffsetY
                    )
                    frame._threshRemFS:Show()
                    posY = posY - thresholdRowSize - ROW_GAP
                    return
                end

                -- Remaining text pinned flush to the bar's right edge; the
                -- +2/+3 texts prefer their tick centers but are nudged left as
                -- needed so none of the three ever overlap. Packed right to
                -- left with a small gap, clamped to the bar's left edge.
                local GAP = 0
                local barW = _barW_for_thresh
                -- Visible set, left to right (plusThree < plusTwo < bar end).
                local entries = {}
                if p.showPlusThreeTimer then
                    entries[#entries + 1] = {
                        fs = frame._threshFS,
                        w = threshW3,
                        center = barW * (plusThreeT / maxTime),
                    }
                else
                    frame._threshFS:Hide()
                end
                if p.showPlusTwoTimer then
                    entries[#entries + 1] = {
                        fs = frame._threshFS2,
                        w = threshW2,
                        center = barW * (plusTwoT / maxTime),
                    }
                else
                    frame._threshFS2:Hide()
                end
                -- Use the pinned width (not a live GetStringWidth) so the right-edge
                -- pin and the overlap packing stay put as the seconds tick.
                local remW = threshWr
                entries[#entries + 1] = {
                    fs = frame._threshRemFS,
                    w = remW,
                    center = barW - remW / 2,
                    pinRight = true,
                }

                -- Right-to-left: each text's right edge must clear the next
                -- text's left edge (minus GAP). Only shift left, never right,
                -- so tick-aligned texts stay put when there is room.
                local limit -- max allowed right edge for the current text
                for i = #entries, 1, -1 do
                    local e = entries[i]
                    local half = e.w / 2
                    if (not e.pinRight) and limit then
                        local right = e.center + half
                        if right > limit then
                            e.center = limit - half
                        end
                    end
                    if e.center - half < 0 then
                        e.center = half
                    end -- clamp to left edge
                    limit = (e.center - half) - GAP
                end

                for _, e in ipairs(entries) do
                    local rightJustified = segmentedThresholds or e.pinRight
                    local anchorX = rightJustified and (e.center + e.w / 2) or e.center
                    local offX, offY
                    if e.fs == frame._threshFS then
                        offX, offY = p.thresholdPlusThreeTextOffsetX, p.thresholdPlusThreeTextOffsetY
                    elseif e.fs == frame._threshFS2 then
                        offX, offY = p.thresholdPlusTwoTextOffsetX, p.thresholdPlusTwoTextOffsetY
                    elseif e.fs == frame._threshRemFS then
                        offX, offY = p.thresholdPlusOneTextOffsetX, p.thresholdPlusOneTextOffsetY
                    end
                    placeAt(e.fs, anchorX, rightJustified, offX, offY)
                    e.fs:Show()
                end
            end

            -- Reserve vertical space for the threshold row (height + gap).
            posY = posY - thresholdRowSize - ROW_GAP
        else
            frame._threshFS:Hide()
            frame._threshFS2:Hide()
            frame._threshRemFS:Hide()
        end
    end

    -- Enemy forces
    local function RenderEnemyForces()
        if p.showEnemyBar == false then
            frame._enemyFS:Hide()
            if frame._enemyBarHost then
                frame._enemyBarHost:Hide()
            end
            frame._enemyBarBg:Hide()
            frame._enemyBarFill:Hide()
            if frame._enemyBarText then
                frame._enemyBarText:Hide()
            end
            HidePullSegments(frame)
            return
        end

        -- Use cached ref (set by UpdateObjectives) instead of re-finding
        -- the weighted objective on every render.
        local enemyObj = run._weightedObj
        if not enemyObj then
            for _, object in ipairs(run.objectives) do
                if object.isWeighted then
                    enemyObj = object
                    break
                end
            end
        end
        if not enemyObj then
            frame._enemyFS:Hide()
            if frame._enemyBarHost then
                frame._enemyBarHost:Hide()
            end
            frame._enemyBarBg:Hide()
            frame._enemyBarFill:Hide()
            if frame._enemyBarText then
                frame._enemyBarText:Hide()
            end
            HidePullSegments(frame)
            return
        end

        local objAlign = _ra(p.objectiveAlign or "LEFT")
        local ePad = ContentPad(objAlign)
        local pctRaw = min(100, max(0, enemyObj.quantity))
        local pctPos = p.enemyForcesPctPos or "LABEL"
        local showEnemyText = p.showEnemyText ~= false

        local enemyTextFormat = p.enemyForcesTextFormat or "PERCENT"
        local hideLabel = p.hideEnemyForcesLabel == true
        local labelText
        if pctPos == "LABEL" then
            -- compact=true skips the " Enemy Forces" suffix baked into
            -- FormatEnemyForcesText, so percent/count text shows alone.
            labelText = FormatEnemyForcesText(enemyObj, enemyTextFormat, hideLabel)
        elseif hideLabel then
            labelText = ""
        else
            labelText = CludesUI.L("Enemy Forces")
        end

        local enemyTextSize = p.enemyForcesTextSize or p.objectivesSize or 12
        SetFS(frame._enemyFS, enemyTextSize)
        ApplyShadow(frame._enemyFS)
        if enemyObj.completed then
            frame._enemyFS:SetTextColor(GetColor(p.objectiveCompletedColor, 0.3, 0.8, 0.3))
        else
            frame._enemyFS:SetTextColor(GetColor(p.objectiveTextColor, 0.9, 0.9, 0.9))
        end
        frame._enemyFS:SetText(labelText)
        if hideLabel and pctPos ~= "LABEL" then
            frame._enemyFS:Hide()
        else
            frame._enemyFS:Show()
        end

        local function RenderEnemyBar()
            local besideRoom = (not enemyObj.completed and pctPos == "BESIDE") and 62 or 0
            local barW = math.min(p.barWidth or 210, innerW - TBAR_PAD * 2) - besideRoom
            if barW < 60 then
                barW = 60
            end
            local enemyHost, enemyClip = EnsureBarShell(frame, "_enemyBarHost")
            EnsureShellTextures(enemyClip, frame, "_enemyBarBg", "_enemyBarFill")
            local eInset = GetBarBleedInset(p, true)
            enemyHost:ClearAllPoints()
            if objAlign == "RIGHT" then
                enemyHost:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -(PAD + TBAR_PAD), posY)
            elseif objAlign == "CENTER" then
                enemyHost:SetPoint("TOP", frame, "TOP", 0, posY)
            else
                enemyHost:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + TBAR_PAD, posY)
            end
            enemyHost:SetSize(barW, ENEMY_BAR_H)
            LayoutBarClip(enemyHost, enemyClip, eInset)
            enemyHost:Show()
            ApplyBarTexture(frame._enemyBarBg, p.enemyBarBgTexture, 0.12, 0.12, 0.12, 0.9)
            frame._enemyBarBg:SetAllPoints(enemyClip)
            frame._enemyBarBg:Show()

            local eR, eG, eB
            if enemyObj.completed then
                eR, eG, eB = GetColor(p.objectiveCompletedColor, 0.3, 0.8, 0.3)
            elseif p.enemyBarUseAccent ~= false then
                eR, eG, eB = GetAccentColor()
            else
                eR, eG, eB = GetColor(p.enemyBarColor, 0.35, 0.55, 0.8)
            end

            local epct = enemyObj.completed and 1 or min(1, max(0, pctRaw / 100))
            local clipW = max(1, barW - eInset * 2)
            local clipH = max(1, ENEMY_BAR_H - eInset * 2)
            local eFillW = max(1, clipW * epct)
            frame._enemyBarFill:ClearAllPoints()
            frame._enemyBarFill:SetPoint("TOPLEFT", enemyClip, "TOPLEFT", 0, 0)
            frame._enemyBarFill:SetSize(eFillW, clipH)
            ApplyBarTexture(frame._enemyBarFill, p.enemyBarTexture, eR, eG, eB, 0.8)
            frame._enemyBarFill:Show()
            RenderPullSegments(frame, enemyClip, run, enemyObj, p, clipW, clipH, eR, eG, eB)

            if not frame._enemyBarText then
                frame._enemyBarText = frame:CreateFontString(nil, "OVERLAY")
                frame._enemyBarText:SetParent(frame._emtTextLayer)
                frame._enemyBarText:SetWordWrap(false)
            end
            if pctPos == "BAR" then
                SetFS(frame._enemyBarText, enemyTextSize)
                ApplyShadow(frame._enemyBarText)
                -- In-bar percent is always white for readability over the
                -- accent-filled bar regardless of completion / user colors.
                frame._enemyBarText:SetTextColor(1, 1, 1)
                frame._enemyBarText:SetText(FormatEnemyForcesText(enemyObj, enemyTextFormat, true))
                frame._enemyBarText:ClearAllPoints()
                frame._enemyBarText:SetPoint("CENTER", enemyHost, "CENTER", 0, 0)
                frame._enemyBarText:Show()
            elseif pctPos == "BESIDE" then
                SetFS(frame._enemyBarText, enemyTextSize)
                ApplyShadow(frame._enemyBarText)
                if enemyObj.completed then
                    frame._enemyBarText:SetTextColor(GetColor(p.objectiveCompletedColor, 0.3, 0.8, 0.3))
                else
                    frame._enemyBarText:SetTextColor(GetColor(p.objectiveTextColor, 0.9, 0.9, 0.9))
                end
                frame._enemyBarText:SetText(FormatEnemyForcesText(enemyObj, enemyTextFormat, true))
                frame._enemyBarText:ClearAllPoints()
                if objAlign == "RIGHT" then
                    frame._enemyBarText:SetPoint("RIGHT", enemyHost, "LEFT", -4, 0)
                else
                    frame._enemyBarText:SetPoint("LEFT", enemyHost, "RIGHT", 4, 0)
                end
                frame._enemyBarText:Show()
            else
                frame._enemyBarText:Hide()
            end

            posY = posY - ENEMY_BAR_H - ROW_GAP
        end

        local function RenderEnemyLabel()
            if not showEnemyText then
                frame._enemyFS:Hide()
                return
            end
            -- In under-bar mode, lift the enemy text up 2px to sit closer to the bar.
            local labelX = p.enemyForcesTextOffsetX or 0
            local labelY = (underBarMode and (posY + 2) or posY) + (p.enemyForcesTextOffsetY or 0)
            frame._enemyFS:ClearAllPoints()
            frame._enemyFS:SetPoint("TOPLEFT", frame, "TOPLEFT", ePad + labelX, labelY)
            frame._enemyFS:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -ePad + labelX, labelY)
            frame._enemyFS:SetJustifyH(objAlign)
            frame._enemyFS:Show()
            local trailingGap = underBarMode and (4 - 2 + 5) or 4
            posY = posY - (frame._enemyFS:GetStringHeight() or 12) - trailingGap
        end

        if underBarMode then
            RenderEnemyBar()
            RenderEnemyLabel()
        else
            RenderEnemyLabel()
            RenderEnemyBar()
        end
    end

    -- Timer text (with optional inline detail rendered as one combined block)
    if not timerInBar then
        local timerAlign = _ra(p.timerAlign or "CENTER")
        SetTimerFS(frame._timerFS, p.timerTextSize or 20)
        ApplyShadow(frame._timerFS)
        frame._timerFS:SetTextColor(tR, tG, tB)
        SetTextDiff(frame._timerFS, timerText)
        if timerAlign == "RIGHT" then
            frame._timerFS:SetJustifyH("RIGHT")
        else
            frame._timerFS:SetJustifyH("LEFT")
        end
        frame._timerFS:ClearAllPoints()
        -- Pin a constant width so the timer doesn't wobble as digits change (a
        -- proportional font makes "1" narrower than "8"). We measure a worst-case
        -- template ("99:99 / 99:99") once per format and reuse it. The font path
        -- and outline flags are part of the key: without them a late font swap
        -- (LibSharedMedia load, "Apply to All Game Text", a heavier font) leaves
        -- the width pinned to the old, narrower measurement and the engine
        -- ellipsizes the overflow (e.g. "33:00" -> "33:...").
        local _timerSz = p.timerTextSize or 20
        local _fScale = frame:GetEffectiveScale() or 1
        local _fPath, _, _fFlags = frame._timerFS:GetFont()
        local _mainKey = #(timerText or "")
            .. "|"
            .. _timerSz
            .. "|"
            .. string.format("%.3f", _fScale)
            .. "|"
            .. (_fPath or "")
            .. "|"
            .. (_fFlags or "")
        if frame._timerFS._lastLen ~= _mainKey then
            frame._timerFS._lastLen = _mainKey
            -- Worst-case template using the WIDEST digit in the CURRENT font, not a
            -- hardcoded "9": decorative / oldstyle numeral fonts can make another
            -- digit (e.g. "0" or "3") wider than "9", so a "9" template under-measures
            -- and the live clock (e.g. "33:00") gets ellipsized. Once per key change.
            local templ = (timerText or ""):gsub("%d", WidestDigitChar(frame._timerFS))
            frame._timerFS:SetText(templ)
            -- Keep the SetTextDiff cache in sync with what we just wrote directly.
            -- Otherwise the cache still reflects the previous timerText, so the restore
            -- call below short-circuits and the "99:99" template stays visible (bug
            -- seen during the 10-second pre-start window where elapsed stays at 0).
            frame._timerFS._lastText = templ
            -- Clear any previously pinned width BEFORE measuring. With wrap off,
            -- GetStringWidth() returns a value CLAMPED to the current width whenever
            -- the text is being truncated -- so if the box needs to GROW (bigger
            -- timer font, a heavier font finishing load, or the clock gaining a
            -- character in overtime, e.g. "-00:01"), measuring against the old,
            -- narrower pinned width yields a too-small result that then stays
            -- truncated for the rest of the run. Matches the objective-row pattern
            -- (SetWidth(0) before GetStringWidth) used later in this file.
            frame._timerFS:SetWidth(0)
            -- +3px safety margin: subpixel rounding at fractional UI scales can
            -- otherwise clip the rightmost glyph and force a wrap.
            frame._timerFS:SetWidth((frame._timerFS:GetStringWidth() or 0) + 3)
            SetTextDiff(frame._timerFS, timerText)
        end

        -- Optional "+key  |" prefix to the left of the timer clock. keyExtra is the
        -- horizontal room it needs on the left; the timer group is shifted right by
        -- keyExtra (LEFT align) or keyExtra/2 (CENTER) so the whole "+21 | timer"
        -- block stays aligned, and is left untouched (flush right, growing left) for
        -- RIGHT align. Single-anchored with no explicit width, so it never truncates.
        local keyExtra, keySpacing = 0, 0
        if keyLevelOnTimer then
            SetTimerFS(frame._keyLevelFS, _timerSz)
            ApplyShadow(frame._keyLevelFS)
            -- Title identity color (accent / custom / white) so it does not turn red
            -- alongside the timer on depletion.
            local klR, klG, klB
            if p.titleUseAccent ~= false then
                klR, klG, klB = aR, aG, aB
            elseif p.titleColor then
                klR, klG, klB = p.titleColor.r or 1, p.titleColor.g or 1, p.titleColor.b or 1
            else
                klR, klG, klB = 1, 1, 1
            end
            frame._keyLevelFS:SetTextColor(klR, klG, klB)
            frame._keyLevelFS:SetJustifyH("LEFT")
            frame._keyLevelFS:SetWidth(0)
            -- "||" renders as a single literal pipe ("|" is WoW's escape introducer).
            SetTextDiff(frame._keyLevelFS, format("+%d  ||", run.level))
            keySpacing = p.keyLevelTimerSpacing or 8
            keyExtra = (frame._keyLevelFS:GetStringWidth() or 0) + keySpacing
        end

        if timerDetailText then
            local _mode = (not run.completed) and (p.timerDisplayMode or "REMAINING_TOTAL") or nil
            local detailSize = (_mode == "REMAINING_TOTAL") and 20 or 12
            SetTimerFS(frame._timerDetailFS, detailSize)
            ApplyShadow(frame._timerDetailFS)
            frame._timerDetailFS:SetTextColor(1, 1, 1)
            frame._timerDetailFS:SetText(timerDetailText)
            if timerAlign == "RIGHT" then
                frame._timerDetailFS:SetJustifyH("RIGHT")
            else
                frame._timerDetailFS:SetJustifyH("LEFT")
            end
            frame._timerDetailFS:ClearAllPoints()
            -- Cache key includes font size, scale, and font (path + flags):
            -- switching modes (12pt detail <-> 20pt detail) or a late font swap
            -- must re-measure the templatized width, else the larger/wider
            -- glyphs get clipped and the detail vanishes.
            local _detScale = frame:GetEffectiveScale() or 1
            local _detPath, _, _detFlags = frame._timerDetailFS:GetFont()
            local _detKey = #timerDetailText
                .. "|"
                .. detailSize
                .. "|"
                .. string.format("%.3f", _detScale)
                .. "|"
                .. (_detPath or "")
                .. "|"
                .. (_detFlags or "")
            if frame._timerDetailFS._lastKey ~= _detKey then
                frame._timerDetailFS._lastKey = _detKey
                local templ = timerDetailText:gsub("%d", WidestDigitChar(frame._timerDetailFS))
                frame._timerDetailFS:SetText(templ)
                -- Clear the pinned width first so GetStringWidth returns the true
                -- unbounded width, not one clamped to a previous, narrower pin (see
                -- the main-timer measurement above for the full explanation).
                frame._timerDetailFS:SetWidth(0)
                frame._timerDetailFS:SetWidth((frame._timerDetailFS:GetStringWidth() or 0) + 3)
                frame._timerDetailFS:SetText(timerDetailText)
            end

            local gap = 4
            local detailW = frame._timerDetailFS:GetStringWidth() or 0
            if timerAlign == "RIGHT" then
                -- Main timer flush right; detail sits to the LEFT of main.
                frame._timerFS:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -(PAD + ALIGN_PAD), posY)
                frame._timerDetailFS:SetPoint("BOTTOMRIGHT", frame._timerFS, "BOTTOMLEFT", -gap, 4)
            elseif timerAlign == "LEFT" then
                frame._timerFS:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + ALIGN_PAD + keyExtra, posY)
                frame._timerDetailFS:SetPoint("BOTTOMLEFT", frame._timerFS, "BOTTOMRIGHT", gap, 4)
            else
                frame._timerFS:SetPoint("TOP", frame, "TOP", -(detailW + gap) / 2 + keyExtra / 2, posY)
                frame._timerDetailFS:SetPoint("BOTTOMLEFT", frame._timerFS, "BOTTOMRIGHT", gap, 4)
            end
            frame._timerDetailFS:Show()
            -- Key prefix sits left of the leftmost timer element (the detail, when
            -- it is on the left for RIGHT align; otherwise the main clock).
            if keyLevelOnTimer then
                local leftmost = (timerAlign == "RIGHT") and frame._timerDetailFS or frame._timerFS
                frame._keyLevelFS:ClearAllPoints()
                frame._keyLevelFS:SetPoint("BOTTOMRIGHT", leftmost, "BOTTOMLEFT", -keySpacing, 0)
                frame._keyLevelFS:Show()
            else
                frame._keyLevelFS:Hide()
            end
        else
            if timerAlign == "RIGHT" then
                frame._timerFS:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -(PAD + ALIGN_PAD), posY)
            elseif timerAlign == "LEFT" then
                frame._timerFS:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + ALIGN_PAD + keyExtra, posY)
            else
                frame._timerFS:SetPoint("TOP", frame, "TOP", keyExtra / 2, posY)
            end
            frame._timerDetailFS:Hide()
            -- Key prefix immediately left of the clock, separated by the spacing.
            if keyLevelOnTimer then
                frame._keyLevelFS:ClearAllPoints()
                frame._keyLevelFS:SetPoint("BOTTOMRIGHT", frame._timerFS, "BOTTOMLEFT", -keySpacing, 0)
                frame._keyLevelFS:Show()
            else
                frame._keyLevelFS:Hide()
            end
        end

        frame._timerFS:Show()
        local timerH = frame._timerFS:GetStringHeight() or 20
        if timerH < 20 then
            timerH = 20
        end
        posY = posY - timerH - ROW_GAP
    else
        frame._timerFS:Hide()
        frame._timerDetailFS:Hide()
        -- In-bar mode: the key level is folded into the bar text (below), so the
        -- standalone prefix string is not used.
        frame._keyLevelFS:Hide()
    end

    if titleAffixBelowTimer then
        local timerGap = p.titleAffixTimerGap or p.titleAffixSandwichGap or defaultSandwichGap
        local barGap = p.titleAffixBarGap or p.titleAffixSandwichGap or defaultSandwichGap
        if timerInBar then
            posY = posY - timerGap
        else
            posY = posY - (timerGap - defaultSandwichGap)
        end
        RenderTitleAffixes()
        posY = posY - (barGap - defaultSandwichGap)
    end

    -- Gaps style renders threshold labels above the bar too; reserve space early like under-bar mode.
    if underBarMode or p.timerBarStyle == "SEGMENTS" then
        RenderThresholdText()
    end

    -- Timer bar
    if maxTime > 0 and p.showTimerBar ~= false then
        local barW = math.min(p.barWidth or 210, innerW - TBAR_PAD * 2)
        if barW < 60 then
            barW = 60
        end

        local barHost, barClip = EnsureBarShell(frame, "_barHost")
        EnsureShellTextures(barClip, frame, "_barBg", "_barFill")
        local barInset = GetBarBleedInset(p, false)
        barHost:ClearAllPoints()
        local _barAlign = _ra(p.timerAlign or "CENTER")
        if _barAlign == "RIGHT" then
            barHost:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -(PAD + TBAR_PAD), posY)
        elseif _barAlign == "LEFT" then
            barHost:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + TBAR_PAD, posY)
        else
            barHost:SetPoint("TOP", frame, "TOP", 0, posY)
        end
        barHost:SetSize(barW, TBAR_H)
        LayoutBarClip(barHost, barClip, barInset)
        barHost:Show()

        local clipW = max(1, barW - barInset * 2)
        local clipH = max(1, TBAR_H - barInset * 2)
        ApplyBarTexture(frame._barBg, p.barBgTexture, 0.12, 0.12, 0.12, 0.9)
        frame._barBg:SetAllPoints(barClip)
        frame._barBg:SetAlpha(1)
        frame._barBg:Show()

        local fillPct = min(1, elapsed / maxTime)
        local fillW = max(1, clipW * fillPct)
        frame._barFill:ClearAllPoints()
        frame._barFill:SetPoint("TOPLEFT", barClip, "TOPLEFT", 0, 0)
        frame._barFill:SetSize(fillW, clipH)
        local _fillA = timerInBar and (p.barFillAlphaExpanded or 0.85) or 0.85
        ApplyBarTexture(frame._barFill, p.barTexture, timerBarR, timerBarG, timerBarB, _fillA)
        frame._barFill:Show()

        -- Pixel-perfect 2-physical-pixel tick markers and segment boundaries.
        local _PP = CludesUI and CludesUI.PP
        local _es = frame:GetEffectiveScale()
        local _tickW = _PP and _PP.SnapForES(2, _es) or 2
        local function _snap(val)
            return _PP and _PP.SnapForES(val, _es) or val
        end

        local function HideTimerSegments()
            if frame._timerSegHosts then
                for _, owner in ipairs(frame._timerSegHosts) do
                    owner:Hide()
                end
            end
            if frame._timerSegBgs then
                for _, texture in ipairs(frame._timerSegBgs) do
                    texture:Hide()
                end
            end
            if frame._timerSegFills then
                for _, texture in ipairs(frame._timerSegFills) do
                    texture:Hide()
                end
            end
        end

        local function EnsureTimerSegments()
            frame._timerSegHosts = frame._timerSegHosts or {}
            frame._timerSegBgs = frame._timerSegBgs or {}
            frame._timerSegFills = frame._timerSegFills or {}
            for i = 1, 3 do
                if not frame._timerSegHosts[i] then
                    -- Per-segment shell so each segment border can clip its own
                    -- melli fill without a shared outer border spanning the gaps.
                    local owner = CreateFrame("Frame", nil, frame)
                    owner:EnableMouse(false)
                    owner:SetClipsChildren(true)
                    local clip = CreateFrame("Frame", nil, owner)
                    clip:EnableMouse(false)
                    owner._clip = clip
                    frame._timerSegHosts[i] = owner
                    frame._timerSegBgs[i] = clip:CreateTexture(nil, "BACKGROUND", nil, 1)
                    frame._timerSegBgs[i]:SetAllPoints(clip)
                    frame._timerSegFills[i] = clip:CreateTexture(nil, "ARTWORK")
                else
                    frame._timerSegHosts[i]:SetClipsChildren(true)
                end
            end
        end

        local barStyle = p.timerBarStyle or "TICKS"
        if barStyle == "SEGMENTS" then
            EnsureTimerSegments()
            -- Host stays shown as the layout spacer for ticks/thresholds; hide
            -- the continuous fill path so only the three segment shells draw.
            frame._barBg:SetAlpha(0)
            frame._barFill:Hide()
            frame._seg3:Hide()
            frame._seg2:Hide()

            -- Physical-pixel-perfect gaps, the same way ticks are: snap the gap
            -- WIDTH to a whole number of physical pixels, snap each boundary
            -- center, then derive the far gap edge as nearEdge + gapW so every
            -- gap is exactly gapW physical pixels wide (no independent-snap drift).
            local gapW = _snap(max(0, p.timerBarSegmentGap or 2))
            local b3 = _snap(barW * (plusThreeT / maxTime))
            local b2 = _snap(barW * (plusTwoT / maxTime))
            local g3L = _snap(b3 - gapW / 2)
            local g3R = g3L + gapW
            local g2L = _snap(b2 - gapW / 2)
            local g2R = g2L + gapW
            local segs = {
                { x1 = 0, x2 = g3L, t1 = 0, t2 = plusThreeT },
                { x1 = g3R, x2 = g2L, t1 = plusThreeT, t2 = plusTwoT },
                { x1 = g2R, x2 = barW, t1 = plusTwoT, t2 = maxTime },
            }
            for i, seg in ipairs(segs) do
                local x1 = max(0, min(barW, seg.x1))
                local x2v = max(0, min(barW, seg.x2))
                local wid = x2v - x1
                if wid < 1 then
                    wid = 1
                end

                local owner = frame._timerSegHosts[i]
                local clip = owner._clip
                owner:ClearAllPoints()
                owner:SetPoint("TOPLEFT", barHost, "TOPLEFT", x1, 0)
                owner:SetSize(wid, TBAR_H)
                LayoutBarClip(owner, clip, barInset)
                owner:Show()

                local backdrop = frame._timerSegBgs[i]
                backdrop:SetAllPoints(clip)
                ApplyBarTexture(backdrop, p.barBgTexture, 0.12, 0.12, 0.12, 0.9)
                backdrop:Show()

                local segDur = max(1, seg.t2 - seg.t1)
                local segPct = min(1, max(0, (elapsed - seg.t1) / segDur))
                local segClipW = max(1, wid - barInset * 2)
                local segClipH = max(1, TBAR_H - barInset * 2)
                local fillTex = frame._timerSegFills[i]
                fillTex:ClearAllPoints()
                fillTex:SetPoint("TOPLEFT", clip, "TOPLEFT", 0, 0)
                fillTex:SetSize(max(1, segClipW * segPct), segClipH)
                ApplyBarTexture(fillTex, p.barTexture, timerBarR, timerBarG, timerBarB, _fillA)
                if segPct > 0 then
                    fillTex:Show()
                else
                    fillTex:Hide()
                end
            end
        else
            HideTimerSegments()
        end

        local tickA = p.tickAlpha or 1
        local whiteTicks = p.tickWhite == true
        local tickR, tickG, tickB = GetColor(p.timerTickColor, 1, 1, 1)

        if barStyle == "SEGMENTS" then
            frame._seg3:Hide()
            frame._seg2:Hide()
        else
            -- Ticks sit in the inset clip band so they cannot stick past the
            -- border the way a full-height mark on the outer host edge would.
            if frame._barTickLayer then
                frame._barTickLayer:SetFrameLevel(barClip:GetFrameLevel() + 2)
            end
            frame._seg3:ClearAllPoints()
            frame._seg3:SetSize(_tickW, clipH)
            frame._seg3:SetPoint(
                "TOPLEFT",
                barHost,
                "TOPLEFT",
                _snap(barW * (plusThreeT / maxTime)) - _tickW / 2,
                -barInset
            )
            if p.timerTickColor or whiteTicks or elapsed > plusThreeT then
                frame._seg3:SetColorTexture(tickR, tickG, tickB, tickA)
            else
                frame._seg3:SetColorTexture(0.4, 1, 0.4, tickA)
            end
            frame._seg3:Show()

            frame._seg2:ClearAllPoints()
            frame._seg2:SetSize(_tickW, clipH)
            frame._seg2:SetPoint(
                "TOPLEFT",
                barHost,
                "TOPLEFT",
                _snap(barW * (plusTwoT / maxTime)) - _tickW / 2,
                -barInset
            )
            if p.timerTickColor or whiteTicks or elapsed > plusTwoT then
                frame._seg2:SetColorTexture(tickR, tickG, tickB, tickA)
            else
                frame._seg2:SetColorTexture(0.3, 0.8, 1, tickA)
            end
            frame._seg2:Show()
        end

        if timerInBar then
            if not frame._barTimerFS then
                frame._barTimerFS = frame:CreateFontString(nil, "OVERLAY")
                frame._barTimerFS:SetParent(frame._emtTextLayer)
                frame._barTimerFS:SetWordWrap(false)
            end
            SetTimerFS(frame._barTimerFS, 12)
            ApplyShadow(frame._barTimerFS)
            local btc = p.timerBarTextColor
            if btc then
                frame._barTimerFS:SetTextColor(btc.r or 1, btc.g or 1, btc.b or 1)
            else
                frame._barTimerFS:SetTextColor(tR, tG, tB)
            end
            local barTimerText = timerText
            if timerDetailText then
                barTimerText = timerText .. timerDetailText
            end
            -- In-bar mode folds the "+key  |" prefix inline (the pixel Spacing
            -- slider only applies to the standalone, non-in-bar clock).
            if keyLevelOnTimer then
                barTimerText = format("+%d  ||  ", run.level) .. barTimerText
            end
            SetTextDiff(frame._barTimerFS, barTimerText)
            frame._barTimerFS:ClearAllPoints()
            if p.timerInBarLeftText then
                frame._barTimerFS:SetPoint("LEFT", barHost, "LEFT", 5, 0)
            else
                frame._barTimerFS:SetPoint("CENTER", barHost, "CENTER", 0, 0)
            end
            frame._barTimerFS:Show()
        elseif frame._barTimerFS then
            frame._barTimerFS:Hide()
        end

        posY = posY - TBAR_H - ROW_GAP - 2
    else
        if frame._barHost then
            frame._barHost:Hide()
        end
        frame._barBg:Hide()
        frame._barFill:Hide()
        frame._seg3:Hide()
        frame._seg2:Hide()
        if frame._timerSegHosts then
            for _, owner in ipairs(frame._timerSegHosts) do
                owner:Hide()
            end
        end
        if frame._timerSegBgs then
            for _, texture in ipairs(frame._timerSegBgs) do
                texture:Hide()
            end
        end
        if frame._timerSegFills then
            for _, texture in ipairs(frame._timerSegFills) do
                texture:Hide()
            end
        end
        if frame._barTimerFS then
            frame._barTimerFS:Hide()
        end
    end

    if underBarMode then
        RenderEnemyForces()
    end

    if not (underBarMode or p.timerBarStyle == "SEGMENTS") then
        RenderThresholdText()
    end

    -- Objectives
    local objIdx = 0
    if p.showObjectives then
        local objAlign = _ra(p.objectiveAlign or "LEFT")
        local oPad = ContentPad(objAlign)
        for i, object in ipairs(run.objectives) do
            if not object.isWeighted then
                objIdx = objIdx + 1
                local record = GetObjRow(frame, objIdx)
                local nameFS, timeFS = record.name, record.time
                local objSize = p.objectivesSize or 12
                SetFS(nameFS, objSize)
                ApplyShadow(nameFS)
                SetFS(timeFS, objSize)
                ApplyShadow(timeFS)

                local displayName = StripDefeated(object.name) or ("Objective " .. i)
                -- Preview only: a real run gets its objective names from the game.
                if isPreview then
                    displayName = CludesUI.L(displayName)
                end
                if object.totalQuantity and object.totalQuantity > 1 then
                    displayName = format("%d/%d %s", object.quantity or 0, object.totalQuantity, displayName)
                end
                if object.completed then
                    nameFS:SetTextColor(GetColor(p.objectiveCompletedColor, 0.3, 0.8, 0.3))
                else
                    nameFS:SetTextColor(GetColor(p.objectiveTextColor, 0.9, 0.9, 0.9))
                end
                local timeStr = ""
                if
                    p.showObjectiveTimes ~= false
                    and object.completed
                    and object.elapsed
                    and object.elapsed > 0
                then
                    local cR, cG, cB = GetColor(p.objectiveCompletedColor, 0.3, 0.8, 0.3)
                    timeStr = format("%s%s|r", CludesUI.HexColor(cR, cG, cB), FormatTime(object.elapsed))
                end
                local compareMode = p.objectiveCompareMode or COMPARE_NONE
                local compareSuffix = ""
                if object.completed then
                    local reference = object.referenceElapsed
                    if isPreview then
                        reference = (compareMode ~= COMPARE_NONE) and object.previewSplit or nil
                    end
                    if reference then
                        compareSuffix = BuildSplitCompareText(
                            reference,
                            object.elapsed,
                            p.objectiveCompareDeltaOnly,
                            p.splitFasterColor,
                            p.splitSlowerColor
                        )
                    end
                elseif p.showUpcomingSplitTargets and compareMode ~= COMPARE_NONE then
                    local target
                    if isPreview then
                        target = object.previewSplit
                    else
                        target = GetReferenceObjectiveTime(run, i, compareMode)
                    end
                    compareSuffix = BuildSplitCompareText(target)
                end
                -- Timer/split text uses its own FontString (never truncated).
                -- Boss name uses the remaining width (truncated with "..." by
                -- WoW's engine if it exceeds the remaining width). No string
                -- reads required -- SetWidth + SetWordWrap(false) handles
                -- truncation at the C++ level, safe for secret values.
                local splitText = timeStr
                if splitText ~= "" and compareSuffix ~= "" then
                    splitText = splitText .. compareSuffix
                elseif compareSuffix ~= "" then
                    splitText = compareSuffix:gsub("^%s+", "")
                end
                local oInnerW = frameW - oPad * 2
                local timeOnLeft = (p.objectiveTimePosition == "LEFT")
                local splitGap = 4
                local objTextX = p.objectiveTextOffsetX or 0
                local objTextY = p.objectiveTextOffsetY or 0
                local objY = posY + objTextY
                nameFS:ClearAllPoints()
                timeFS:ClearAllPoints()
                nameFS:SetText(displayName)
                if splitText ~= "" then
                    timeFS:SetText(splitText)
                    timeFS:SetTextColor(1, 1, 1, 1)
                    timeFS:SetWidth(0)
                    local timeW = timeFS:GetStringWidth() or 0
                    local nameMaxW = oInnerW - timeW - splitGap
                    if nameMaxW < 20 then
                        nameMaxW = 20
                    end
                    nameFS:SetWidth(0)
                    local nameW = nameFS:GetStringWidth() or 0
                    if nameW > nameMaxW then
                        nameW = nameMaxW
                    end
                    if nameW < 20 then
                        nameW = 20
                    end
                    nameFS:SetWidth(nameW)
                    if timeOnLeft then
                        if objAlign == "RIGHT" then
                            nameFS:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -oPad + objTextX, objY)
                            timeFS:SetPoint("TOPRIGHT", nameFS, "TOPLEFT", -splitGap, 0)
                        elseif objAlign == "CENTER" then
                            local groupW = timeW + splitGap + nameW
                            timeFS:SetPoint("TOP", frame, "TOP", objTextX - (groupW - timeW) / 2, objY)
                            nameFS:SetPoint("TOPLEFT", timeFS, "TOPRIGHT", splitGap, 0)
                        else
                            timeFS:SetPoint("TOPLEFT", frame, "TOPLEFT", oPad + objTextX, objY)
                            nameFS:SetPoint("TOPLEFT", timeFS, "TOPRIGHT", splitGap, 0)
                        end
                    else
                        if objAlign == "RIGHT" then
                            timeFS:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -oPad + objTextX, objY)
                            nameFS:SetPoint("TOPRIGHT", timeFS, "TOPLEFT", -splitGap, 0)
                        elseif objAlign == "CENTER" then
                            local groupW = nameW + splitGap + timeW
                            nameFS:SetPoint("TOP", frame, "TOP", objTextX - (groupW - nameW) / 2, objY)
                            timeFS:SetPoint("TOPLEFT", nameFS, "TOPRIGHT", splitGap, 0)
                        else
                            nameFS:SetPoint("TOPLEFT", frame, "TOPLEFT", oPad + objTextX, objY)
                            timeFS:SetPoint("TOPLEFT", nameFS, "TOPRIGHT", splitGap, 0)
                        end
                    end
                    timeFS:Show()
                else
                    timeFS:Hide()
                    if objAlign == "RIGHT" then
                        nameFS:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -oPad + objTextX, objY)
                    elseif objAlign == "CENTER" then
                        nameFS:SetPoint("TOP", frame, "TOP", objTextX, objY)
                    else
                        nameFS:SetPoint("TOPLEFT", frame, "TOPLEFT", oPad + objTextX, objY)
                    end
                    nameFS:SetWidth(oInnerW)
                end
                nameFS:SetJustifyH(objAlign)
                nameFS:Show()
                posY = posY - (nameFS:GetStringHeight() or 12) - OBJ_GAP
            end
        end
    end

    for i = objIdx + 1, #objRows do
        local e = objRows[i]
        if e then
            e.name:Hide()
            e.time:Hide()
        end
    end

    if not underBarMode then
        if objIdx > 0 then
            posY = posY - 5
        end
        RenderEnemyForces()
    end

    local totalH = abs(posY) + PAD
    frame:SetHeight(totalH)

    if isPreview and p.showPreview then
        SetFS(frame._previewFS, 8)
        frame._previewFS:SetTextColor(0.5, 0.5, 0.5, 0.6)
        frame._previewFS:SetText(CludesUI.L("PREVIEW"))
        frame._previewFS:ClearAllPoints()
        frame._previewFS:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, 4)
        frame._previewFS:Show()
    elseif frame._previewFS then
        frame._previewFS:Hide()
    end

    mod.ApplyBorder()
    frame:Show()
end

_G._CUMT_StandaloneRefresh = RenderStandalone
_G._CUMT_GetStandaloneFrame = function()
    return CreateStandaloneFrame()
end

-- Forces a full rebuild by discarding the cached frame + its FontStrings
-- so the next RenderStandalone() re-creates them from scratch. Use when a
-- setting (e.g. text alignment) won't take effect via re-render alone.
_G._CUMT_RebuildStandalone = function()
    if standaloneFrame then
        standaloneFrame:SetScript("OnUpdate", nil) -- the timer fallback moves to the new frame
        standaloneFrame:Hide()
    end
    standaloneFrame = nil
    standaloneCreated = false
    wipe(objRows)
    RenderStandalone()
end

-- One-time migration of legacy TOPLEFT-stored position into stable centerX/Y offsets
-- relative to UIParent center. Must run BEFORE SetScale so the derived center reflects
-- the unscaled frame; otherwise repeated calls after SetScale would compute a different
-- center each time and the frame would drift.
local function _ensureCenterPos()
    local place = db and db.profile and db.profile.standalonePos
    if not place then
        return
    end
    if place.centerX and place.centerY then
        return
    end
    local frame = standaloneFrame
    if not (frame and frame:GetCenter()) then
        return
    end
    -- Force scale 1.0 momentarily so GetCenter returns un-scaled coords.
    local prevScale = frame:GetScale()
    frame:SetScale(1.0)
    local cx, cy = frame:GetCenter()
    local upX, upY = UIParent:GetCenter()
    place.centerX = cx - upX
    place.centerY = cy - upY
    -- Strip legacy keys so the migration only runs once.
    place.point, place.relPoint, place.x, place.y = nil, nil, nil, nil
    frame:SetScale(prevScale)
end

local function _centerPosFromSaved(place)
    if not place or place.centerX == nil or place.centerY == nil then
        return
    end
    local scale = (db and db.profile and db.profile.scale) or 1.0
    if scale == 0 then
        scale = 1.0
    end
    return place.centerX / scale, place.centerY / scale
end

local function ApplyStandalonePosition()
    if not db then
        return
    end
    if not standaloneFrame then
        return
    end
    _ensureCenterPos()
    local place = db.profile.standalonePos
    local scale = db.profile.scale or 1.0
    if scale == 0 then
        scale = 1.0
    end

    -- SetPoint offsets are in the frame's OWN scaled coord space, so the
    -- effective on-screen offset = stored * scale. To keep the visual
    -- center pinned regardless of scale, divide the stored offset by scale.
    standaloneFrame:SetScale(scale)
    local sx, sy = _centerPosFromSaved(place)
    if sx ~= nil then
        standaloneFrame:ClearAllPoints()
        standaloneFrame:SetPoint("CENTER", UIParent, "CENTER", sx, sy)
    end
end
_G._CUMT_ApplyStandalonePosition = ApplyStandalonePosition

-- True only when every scenario objective is complete: Avoids false times being saved/missed runs due to completion on same tick
local function IsDungeonComplete()
    local numCriteria = select(3, C_Scenario.GetStepInfo()) or 0
    if numCriteria == 0 then
        return false
    end

    local seenAny = false
    for i = 1, numCriteria do
        local details = C_ScenarioInfo.GetCriteriaInfo(i)
        if details then
            seenAny = true
            if not details.completed then
                return false
            end
        end
    end

    return seenAny
end

-- Event-driven runtime. Zero polling. Lifecycle events handle start /
-- complete / reset; SCENARIO_CRITERIA_UPDATE handles the "all objectives
-- done" detection (no need for a per-tick poller). Multi-event detection
-- with GetInstanceInfo difficulty fallback (IsChallengeModeActive returns
-- false post-completion, so map-id alone isn't reliable).
local runtimeFrame = CreateFrame("Frame")

local function _isInChallengeMode()
    if
        C_ChallengeMode
        and C_ChallengeMode.IsChallengeModeActive
        and C_ChallengeMode.IsChallengeModeActive()
    then
        return true
    end
    -- Fallback: difficulty 8 = Mythic Keystone. Reliable across the brief
    -- window where IsChallengeModeActive flips false but we're still in
    -- the dungeon (e.g. immediately after completion).
    local _, instanceType, difficulty = GetInstanceInfo()
    return instanceType == "party" and difficulty == 8
end

local function HandleRuntimeEvent(evt)
    if not db or not db.profile.enabled then
        if currentRun.active or currentRun.completed then
            ResetRun()
        end
        return
    end

    local activeMapID = C_ChallengeMode.GetActiveChallengeMapID()
    if activeMapID then
        if not currentRun.active and not currentRun.completed then
            StartRun()
        end
        -- Pure event-driven completion check: criteria updates fire when
        -- bosses die and when the weighted enemy-forces tally crosses 100.
        if currentRun.active and evt == "SCENARIO_CRITERIA_UPDATE" then
            if IsDungeonComplete() then
                CompleteRun()
            end
        end
    elseif (currentRun.active or currentRun.completed) and not _isInChallengeMode() then
        -- M+ cleared and we're no longer in a M+ instance. Salvage as
        -- completion if the last criteria update saw it complete.
        if currentRun.active and IsDungeonComplete() then
            CompleteRun()
        else
            ResetRun()
        end
    end
end

-- Always-on (low-frequency) events: enough to detect a key starting.
local _ALWAYS_EVENTS = {
    "PLAYER_ENTERING_WORLD",
    "CHALLENGE_MODE_START",
    "CHALLENGE_MODE_COMPLETED",
    "CHALLENGE_MODE_RESET",
    "WORLD_STATE_TIMER_START",
    "WORLD_STATE_TIMER_STOP",
}
-- High-frequency events: only needed during an active run. SCENARIO_CRITERIA_UPDATE
-- fires constantly in any scenario (pet battles, world quest scenarios, garrisons,
-- etc.); ZONE_CHANGED_NEW_AREA fires on every subzone crossing while questing.
-- Registering them only during a key keeps idle CPU at zero.
local _RUN_EVENTS = { "SCENARIO_CRITERIA_UPDATE", "ZONE_CHANGED_NEW_AREA" }

local function _registerRunEvents()
    for _, ev in ipairs(_RUN_EVENTS) do
        runtimeFrame:RegisterEvent(ev)
    end
    SyncPullEvents()
end
local function _unregisterRunEvents()
    for _, ev in ipairs(_RUN_EVENTS) do
        runtimeFrame:UnregisterEvent(ev)
    end
    SyncPullEvents()
end

-- Toggle high-frequency event subscriptions based on whether we're actually in a
-- key. Outside M+ we don't want to wake on every quest update or subzone change.
local function SyncRunEvents()
    if currentRun.active then
        _registerRunEvents()
    else
        _unregisterRunEvents()
    end
end

for _, ev in ipairs(_ALWAYS_EVENTS) do
    runtimeFrame:RegisterEvent(ev)
end
runtimeFrame:SetScript("OnEvent", function(_, evt)
    if evt == "PLAYER_ENTERING_WORLD" then
        ApplyStandalonePosition()
        -- API data isn't fully populated at PEW; retry once after 10s
        -- to catch a /reload mid-key.
        C_Timer.After(10, function()
            HandleRuntimeEvent("PLAYER_ENTERING_WORLD_DELAYED")
            SyncRunEvents()
        end)
    end
    HandleRuntimeEvent(evt)
    SyncRunEvents()
end)

function EMT:OnInitialize()
    db = CludesUI.Lite.NewDB("CludesUIMythicTimerDB", DB_DEFAULTS)
    _G._CUMT_AceDB = db
    AppendSharedMediaBarTextures()

    if db and db.profile then
        local pp = db.profile
        for key, value in pairs(DB_DEFAULTS.profile) do
            if pp[key] == nil then
                pp[key] = type(value) == "table" and CopyTable(value) or value
            end
        end
        -- showPreview is a transient options-panel state. /reload doesn't fire
        -- the CUI window's OnHide auto-off, so the saved value can persist
        -- as true across reloads. Force it off at every login.
        pp.showPreview = false
    end

    -- Season-based data purge: clear split records from previous seasons.
    C_Timer.After(2, function()
        if not db or not db.profile then
            return
        end
        local currentMaps = C_ChallengeMode.GetMapTable()
        if not currentMaps or #currentMaps == 0 then
            return
        end

        local validMapIDs = {}
        for _, mapID in ipairs(currentMaps) do
            validMapIDs[mapID] = true
        end

        if db.profile.bestObjectiveSplits then
            for scopeKey in pairs(db.profile.bestObjectiveSplits) do
                -- Keys are normally scoped strings ("<mapID>-..."), but legacy
                -- data can store a bare numeric mapID. tostring() guards against
                -- calling :match on a number (crashes in Lua 5.1).
                local mapIDStr = tostring(scopeKey):match("^(%d+)")
                local mapID = tonumber(mapIDStr)
                if mapID and not validMapIDs[mapID] then
                    db.profile.bestObjectiveSplits[scopeKey] = nil
                end
            end
        end
        if db.profile.fastestRunSplits then
            for scopeKey in pairs(db.profile.fastestRunSplits) do
                local mapIDStr = tostring(scopeKey):match("^(%d+)")
                local mapID = tonumber(mapIDStr)
                if mapID and not validMapIDs[mapID] then
                    db.profile.fastestRunSplits[scopeKey] = nil
                end
            end
        end
    end)

    -- runtimeFrame is now event-driven (registered above); no OnUpdate needed.
end

function EMT:OnEnable()
    -- Mythic+ Tools features initialize BEFORE the timer's own enable guard:
    -- they carry their own per-feature enable flags and must work with the
    -- timer feature turned off. Both are no-ops while their flags are off.
    if mod.TSB_OnEnable then
        mod.TSB_OnEnable(db)
    end
    if mod.TFB_OnEnable then
        mod.TFB_OnEnable(db)
    end
    if mod.RS_OnEnable then
        mod.RS_OnEnable(db)
    end
    if mod.KT_OnEnable then
        mod.KT_OnEnable(db)
    end
    if not db or not db.profile.enabled then
        return
    end

    if CludesUI and CludesUI.RegisterUnlockModeListener then
        CludesUI:RegisterUnlockModeListener("EMT_MythicTimer", function(isActive)
            unlockLayoutActive = isActive == true
            -- When the element is anchor-linked to another unlock element,
            -- the anchor system owns the frame's position; re-applying our
            -- stored absolute standalonePos would snap it away from the
            -- anchor-derived spot on every unlock open/close.
            local anchored = CludesUI.IsUnlockAnchored and CludesUI.IsUnlockAnchored("EMT_MythicTimer")
            if unlockLayoutActive then
                RenderStandalone()
                if not anchored then
                    ApplyStandalonePosition()
                end
            else
                if not db.profile.showPreview and not currentRun.active and not currentRun.completed then
                    if standaloneFrame then
                        standaloneFrame:Hide()
                    end
                else
                    RenderStandalone()
                end
                if not anchored then
                    ApplyStandalonePosition()
                end
            end
        end)
    end

    if CludesUI and CludesUI.RegisterUnlockElements and CludesUI.MakeUnlockElement then
        local MK = CludesUI.MakeUnlockElement
        CludesUI:RegisterUnlockElements({
            MK({
                key = "EMT_MythicTimer",
                label = "Mythic+ Timer",
                group = "Mythic+",
                order = 520,
                noResize = true,
                getFrame = function()
                    return _G._CUMT_GetStandaloneFrame and _G._CUMT_GetStandaloneFrame()
                end,
                getSize = function()
                    local frame = standaloneFrame
                    if frame then
                        return frame:GetWidth(), frame:GetHeight()
                    end
                    return 260, 200
                end,
                isHidden = function()
                    return false
                end,
                savePos = function(_, anchorPoint, relPoint, posX, posY)
                    -- Stored as delta in UIParent-logical units (matches the
                    -- migration in _ensureCenterPos). ApplyStandalonePosition
                    -- divides by profile.scale on apply; screen delta works
                    -- out to stored_UIlogical * UIParent:GetEffectiveScale().
                    --
                    -- f:GetCenter() returns coords in the frame's OWN scaled
                    -- units. At frame scale != 1 we must re-scale those to
                    -- UIParent-logical units before subtracting upX. Multiply
                    -- cx by (frame_effective / UIParent_effective) to land in
                    -- the same space as upX. Without this the stored offset
                    -- shrinks at larger scales and the frame snaps toward the
                    -- middle every time settings re-apply (e.g. Show Preview).
                    --
                    -- Unlock Cancel hands back the pre-session snapshot, i.e. the
                    -- value already stored, while the frame still sits at the
                    -- dragged spot: keep the stored value, never the live read.
                    local frame = standaloneFrame
                    local current = db.profile.standalonePos
                    local isRestore = current
                        and posX ~= nil
                        and current.centerX == posX
                        and current.centerY == posY
                    if not isRestore and frame and frame:GetCenter() then
                        local cx, cy = frame:GetCenter()
                        local upX, upY = UIParent:GetCenter()
                        local fes = frame:GetEffectiveScale() or 1
                        local ues = UIParent:GetEffectiveScale() or 1
                        local ratio = fes / ues
                        db.profile.standalonePos = {
                            centerX = cx * ratio - upX,
                            centerY = cy * ratio - upY,
                        }
                    end
                    if frame and not CludesUI._unlockActive then
                        local sx, sy = _centerPosFromSaved(db.profile.standalonePos)
                        if sx ~= nil then
                            frame:ClearAllPoints()
                            frame:SetPoint("CENTER", UIParent, "CENTER", sx, sy)
                        end
                    end
                end,
                loadPos = function()
                    -- RAW UIParent-logical units, NOT _centerPosFromSaved.
                    -- savePos stores UIParent-logical centerX/centerY, and the
                    -- consumers of loadPos (Unlock Mode's centralized
                    -- ApplySavedPositions pass in particular) divide by the
                    -- frame's scale themselves at SetPoint time. Returning the
                    -- scale-divided value here made that pass divide TWICE:
                    -- its SetPoint landed at stored/scale on screen, shrinking
                    -- a scaled floating timer toward screen center on every
                    -- pass -- the "wrong place at every key start, unlock
                    -- mode fixes it" field report (/emtdbg capture: our apply
                    -- wrote 696.3 at scale 1.26 = 877 on screen, then the
                    -- centralized pass stomped it with 552.6 = 696 on
                    -- screen). At scale 1.0 both forms are identical, which is why only
                    -- scaled timers ever drifted. The /scale division belongs ONLY at
                    -- the module's own SetPoint (ApplyStandalonePosition /
                    -- _centerPosFromSaved), never in the interchange format.
                    local place = db.profile.standalonePos
                    if not (place and place.centerX and place.centerY) then
                        return nil
                    end
                    return {
                        point = "CENTER",
                        relPoint = "CENTER",
                        x = place.centerX,
                        y = place.centerY,
                    }
                end,
                clearPos = function()
                    db.profile.standalonePos = nil
                end,
                applyPos = function()
                    if standaloneFrame then
                        ApplyStandalonePosition()
                    end
                end,
            }),
        })
    end
end
