if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
if not CUI.IS_FOREVER then return end
-------------------------------------------------------------------------------
-- CludesUIQuestTracker_Custom.lua  (WoW Forever only)
--
-- Our own quest tracker frame, used instead of ObjectiveTrackerFrame when the
-- Custom Quest Tracker option is on. Blizzard's tracker is muted (alpha 0,
-- click-through, see EQT.MuteBlizzardTracker) and never skinned or fed watch
-- list edits. This file only reads the quest log, the watch list and the
-- tracked recipes: untracking, zone auto-track, filters and sorting all live
-- in our own list (the Forever file's quest tools, read-only).
-------------------------------------------------------------------------------
local _, mod = ...
local TrackerNS = mod.EQT
local IsSecret = CUI.IsSecret
local function TrackerCfg(key) return TrackerNS.Cfg(key) end

-- The tracker's width, and the height it grows to before it scrolls: the
-- values a new profile starts on, and the range a user can set.
local DEF_WIDTH, DEF_HEIGHT = 260, 450
local WIDTH_MIN, WIDTH_MAX = 150, 600
local HEIGHT_MIN, HEIGHT_MAX = 100, 1200
-- Its Unlock Mode element: the key Blizzard's tracker has when this one is off.
local UNLOCK_KEY = "EQT_Tracker"

-- Defaults, merged into the module's table before its DB is made at login.
-- Whether this tracker is used at all has no default here: the loader's
-- ns.CustomTrackerWanted decides it from the profile's style and pick.
-- Its spot is customPos (none until one is taken or saved).
do
    local qt = mod.QT_DEFAULTS.profile.questTracker
    qt.customGroupByZone = true
    qt.customWidth = DEF_WIDTH
    qt.customMaxHeight = DEF_HEIGHT
    qt.customGrowUp = false -- grows up from its bottom edge
    qt.customCollapseCompleted = false
    qt.customZoneFontSize = 13
    qt.customQuestSpacing = 4
    qt.customObjSpacing = 1
    qt.customFocusClick = true -- focus buttons + menu entry
    qt.customWrapTitles = true -- off: one line, cut with "..."
    qt.customWrapObjectives = true
    qt.customScrollbar = "always" -- always / hover / hidden
    qt.customBgHover = false -- background + top line only while hovered
    qt.customBgFade = true -- fade it in and out
    qt.customItemButtons = false -- quest item buttons beside titles
    qt.customFlashUpdates = false -- flash objectives that just changed
    qt.customClickAction = "collapse" -- collapse / map / details
end

local PAD = 8
local HEADER_H = 24
local BAR_W = 3 -- scrollbar track width
local BAR_GAP = 6 -- space kept for the track right of the text
local OBJ_IND = 10 -- objective indent
local FOCUS_GAP = 6 -- focus button to title
local WHEEL = 40

-- Inert until InitCustom registers events (zero cost while off).
local eventTag = CreateFrame("Frame")

local widget, headerFrame, scroller, childFrame, rail, knob
local lines, used = {}, 0
local sequence, zoneOf, seen = {}, {}, {}
local pending = false
local stale = false -- skipped a render while hidden
local fontGen = 1
local inEncounter = false
local prevObj = {} -- questID -> objective texts last shown (update flashes)
local rowHooks, hookW = {}, 0 -- public row hooks; hookW: width they reserve
local TITLE_MIN_W = 40 -- the narrowest a quest title gets, whatever the hooks reserve

-------------------------------------------------------------------------------
-- Per-character state: untracked = removed from our list by the player,
-- collapsed = questID / "z:<zone>" / "all", doneOpen = completed quests
-- expanded while Collapse Completed Quests is on, pinned = kept listed and
-- sorted first. Kept per character in the
-- account DB, as the Forever file keeps its watch sets.
-------------------------------------------------------------------------------
local charDB
local function CharStore()
    if charDB then return charDB end
    local all = CludesUIDB.questTrackerChars
    if type(all) ~= "table" then
        all = {}
        CludesUIDB.questTrackerChars = all
    end
    local unitGuid = UnitGUID("player")
    local savedVars = all[unitGuid]
    if type(savedVars) ~= "table" then
        savedVars = {}
        all[unitGuid] = savedVars
    end
    if type(savedVars.ctUntracked) ~= "table" then savedVars.ctUntracked = {} end
    if type(savedVars.ctCollapsed) ~= "table" then savedVars.ctCollapsed = {} end
    if type(savedVars.ctDoneOpen) ~= "table" then savedVars.ctDoneOpen = {} end
    if type(savedVars.ctPinned) ~= "table" then savedVars.ctPinned = {} end
    charDB = savedVars
    return savedVars
end

-------------------------------------------------------------------------------
-- Quest list: watched quests in watch order (Blizzard's order), then quests
-- under the current zone header when zone auto-track is on, then pinned ones.
-------------------------------------------------------------------------------
local listPos, listRank, zoneRank = {}, {}, {}

local function ByRank(a, b)
    local ra, rb = listRank[a], listRank[b]
    if ra ~= rb then return ra < rb end
    return listPos[a] < listPos[b]
end

-- Stable sort of order by listRank, lowest first.
local function SortByListRank()
    wipe(listPos)
    for index, questId in ipairs(sequence) do
        listPos[questId] = index
    end
    table.sort(sequence, ByRank)
end

local function BuildList()
    wipe(sequence)
    wipe(seen)
    wipe(listRank)
    local saved = CharStore()
    local untracked, pinned = saved.ctUntracked, saved.ctPinned
    local watched = seen
    for index = 1, C_QuestLog.GetNumQuestWatches() do
        local questId = C_QuestLog.GetQuestIDForQuestWatchIndex(index)
        if questId then
            watched[questId] = true
            if not untracked[questId] then sequence[#sequence + 1] = questId end
        end
    end
    -- One log snapshot per pass; filters and sort keys read it too.
    local log
    log, zoneOf = TrackerNS.QuestLogSnapshot()
    local auto = TrackerNS.AutoTrackOn()
    for _, details in ipairs(log) do
        local questId = details.questID
        if questId and not details.isHeader then
            if pinned[questId] or (auto and TrackerNS.QuestInArea(details, zoneOf[questId])) then
                if
                    not watched[questId]
                    and not untracked[questId]
                    and not details.isHidden
                    and not details.isTask
                    and not details.isBounty
                then
                    sequence[#sequence + 1] = questId
                end
            elseif untracked[questId] and not watched[questId] then
                -- An auto-tracked quest untracked here: free again once out of the zone.
                untracked[questId] = nil
            end
        end
    end
    for index = #sequence, 1, -1 do
        if TrackerNS.IsQuestFiltered(sequence[index]) then table.remove(sequence, index) end
    end
    TrackerNS.SortQuestList(sequence)
    if next(pinned) then
        for _, questId in ipairs(sequence) do
            listRank[questId] = pinned[questId] and 0 or 1
        end
        SortByListRank()
    end
    if not TrackerCfg("customGroupByZone") then return end
    -- Zones in order of their first quest.
    wipe(zoneRank)
    local num = 0
    for _, questId in ipairs(sequence) do
        local z = zoneOf[questId] or ""
        if not zoneRank[z] then
            num = num + 1
            zoneRank[z] = num
        end
        listRank[questId] = zoneRank[z]
    end
    SortByListRank()
end

-------------------------------------------------------------------------------
-- Lines: one pooled Button per row (zone header, quest title, objective).
-------------------------------------------------------------------------------
local OnLineClick, OnLineEnter, OnLineLeave, ToggleFocus, SyncItems, HideOverlay, Queue -- defined below

-- Outline and shadow follow the Fonts page's Module Outline.
local function StyleText(fontStr, px)
    CUI.PrimeFontShadow(fontStr, CUI.GetFontUseShadow("questTracker") and true or false)
    local flag = CUI.GetFontOutlineFlag("questTracker")
    if not pcall(fontStr.SetFont, fontStr, TrackerNS.GetFont(), px, flag) then
        fontStr:SetFont("Fonts/FRIZQT__.TTF", px, flag)
    end
end

local SIZE_KEY = {
    zone = "customZoneFontSize",
    quest = "titleFontSize",
    recipe = "titleFontSize",
    obj = "objectiveFontSize",
}
local SIZE_DEF = { zone = 13, quest = 12, recipe = 12, obj = 10 }

-- key: objective identity, so a flash survives re-renders of the same row.
local function AcquireLine(kind, ident, textValue, posX, posY, width, key)
    used = used + 1
    local l = lines[used]
    if not l then
        l = CreateFrame("Button", nil, childFrame)
        l:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        l.text = l:CreateFontString(nil, "OVERLAY")
        l.text:SetPoint("TOPLEFT")
        l.text:SetJustifyH("LEFT")
        l:SetScript("OnClick", OnLineClick)
        l:SetScript("OnEnter", OnLineEnter)
        l:SetScript("OnLeave", OnLineLeave)
        lines[used] = l
    end
    if l.kind ~= kind or l.gen ~= fontGen then
        l.kind, l.gen = kind, fontGen
        StyleText(l.text, TrackerCfg(SIZE_KEY[kind]) or SIZE_DEF[kind])
        l:EnableMouse(kind ~= "obj")
        l.lastText = nil
        l.dashW = nil -- a timer bar's indent, measured in this font
    end
    l.id = ident
    if l.flash and l.key ~= key then l.flash:Stop() end
    l.key = key
    if l.focus and kind ~= "quest" then l.focus:Hide() end
    if l.slots and kind ~= "quest" then
        for _, slot in ipairs(l.slots) do
            slot:Hide()
        end
    end
    if l.bar then l.bar:Hide() end
    -- Only a changed row is measured or moved.
    local wrap = TrackerCfg(kind == "obj" and "customWrapObjectives" or "customWrapTitles") ~= false
    if l.lastText ~= textValue or l.lastWidth ~= width or l.lastWrap ~= wrap then
        l.lastText, l.lastWidth, l.lastWrap = textValue, width, wrap
        l.text:SetWordWrap(wrap)
        l.text:SetWidth(width)
        l.text:SetText(textValue)
        l.lastH = math.ceil(l.text:GetStringHeight())
        -- Font not ready: measure again next pass.
        if l.lastH <= 0 then l.lastText = nil end
        l:SetSize(width, l.lastH)
    end
    if l.lastX ~= posX or l.lastY ~= posY then
        l.lastX, l.lastY = posX, posY
        l:ClearAllPoints()
        l:SetPoint("TOPLEFT", childFrame, "TOPLEFT", posX, -posY)
    end
    l:Show()
    return l, l.lastH
end

-- Update flash: a white band that fades in and out behind the row.
local function Flash(l)
    local frame = l.flash
    if not frame then
        local texture = l:CreateTexture(nil, "BACKGROUND")
        texture:SetPoint("TOPLEFT", -2, 1)
        texture:SetPoint("BOTTOMRIGHT", 2, -1)
        texture:SetColorTexture(1, 1, 1)
        texture:SetBlendMode("ADD")
        texture:SetAlpha(0)
        frame = l:CreateAnimationGroup()
        local fade = frame:CreateAnimation("Alpha")
        fade:SetTarget(texture)
        fade:SetFromAlpha(0)
        fade:SetToAlpha(0.3)
        fade:SetDuration(0.15)
        fade:SetOrder(1)
        fade = frame:CreateAnimation("Alpha")
        fade:SetTarget(texture)
        fade:SetFromAlpha(0.3)
        fade:SetToAlpha(0)
        fade:SetDuration(0.85)
        fade:SetOrder(2)
        l.flash = frame
    end
    frame:Stop()
    frame:Play()
end

-------------------------------------------------------------------------------
-- Colors
-------------------------------------------------------------------------------
local OBJ_RGB = OBJECTIVE_TRACKER_COLOR and OBJECTIVE_TRACKER_COLOR.Normal or { r = 0.8, g = 0.8, b = 0.8 }
local DONE_RGB = OBJECTIVE_TRACKER_COLOR and OBJECTIVE_TRACKER_COLOR.Complete or { r = 0.6, g = 0.6, b = 0.6 }

local function TitleRGB(questId, isComplete)
    if questId == C_SuperTrack.GetSuperTrackedQuestID() then return TrackerNS.GetFocusRGB() end
    if isComplete then return TrackerNS.GetCompletedRGB() end
    -- Title Difficulty Colors: the game's own option (EQT.TitleDifficultyOn)
    if TrackerNS.TitleDifficultyOn() then
        local red, green, blue = TrackerNS.QuestDifficultyRGB(questId)
        if red then return red, green, blue end
    end
    return TrackerNS.GetTitleRGB()
end

-- Zone headers: the colour picked on Group Quests by Zone (the accent or a
-- custom colour); with no pick, the Header Color. The fourth return is true
-- while that colour is the accent.
local function ZoneRGB()
    local cfg = TrackerNS.DB()
    local accent = cfg.customZoneUseAccent
    if accent == nil then
        local red, green, blue = TrackerNS.GetHeaderRGB()
        return red, green, blue, not (cfg.headerShowClassColor or cfg.headerUseAccent == false)
    end
    if accent then
        local a = CUI.CLUDES_GREEN
        return a.r, a.g, a.b, true
    end
    return cfg.customZoneR or 1, cfg.customZoneG or 1, cfg.customZoneB or 1, false
end
TrackerNS.CustomZoneRGB = ZoneRGB

local function ObjectiveRGBA(object)
    local red, green, blue = OBJ_RGB.r, OBJ_RGB.g, OBJ_RGB.b
    if object.finished then
        red, green, blue = DONE_RGB.r, DONE_RGB.g, DONE_RGB.b
    end
    if TrackerCfg("objProgressColor") then
        local req = object.numRequired
        if object.finished then
            red, green, blue = TrackerNS.ProgressRGB(1)
        elseif type(req) == "number" and req > 0 then
            red, green, blue = TrackerNS.ProgressRGB(math.min((object.numFulfilled or 0) / req, 1))
        end
    end
    local a = (object.finished and TrackerCfg("objDimCompleted")) and (TrackerCfg("objDimAlpha") or 45) / 100
        or 1
    return red, green, blue, a
end

-- "[12+] Title (Elite)", as Blizzard's Forever tracker writes it.
local titleInfo = {}

local function QuestTitle(questId)
    local title = C_QuestLog.GetTitleForQuestID(questId) or ""
    titleInfo.questID, titleInfo.difficultyLevel = questId, C_QuestLog.GetQuestDifficultyLevel(questId)
    local prefixText = QuestUtilsOverrides.GetQuestTitlePrefix(titleInfo)
    local tag = QuestUtilsOverrides.GetQuestTagText(questId)
    return (prefixText or "") .. title .. (tag and (" " .. tag) or "")
end

-------------------------------------------------------------------------------
-- Scrollbar: shown only while the list is taller than the frame.
-------------------------------------------------------------------------------
local contentH, viewH = 0, 0

local function MaxScroll() return math.max(0, contentH - viewH) end

-- Scrollbar mode; the wheel scrolls in every mode. A drag in progress
-- keeps a hover-mode bar up.
local function BarMode() return TrackerCfg("customScrollbar") or "always" end

local function Hovered() return widget:IsMouseOver() or knob:GetScript("OnUpdate") ~= nil end
local function HoverWanted() return BarMode() == "hover" or TrackerCfg("customBgHover") end

local function BarVisible()
    local mode = BarMode()
    if mode == "hidden" then return false end
    if mode == "hover" then return Hovered() end
    return true
end

-- Background (+ top line) shown: always, or only while hovered, faded by an
-- alpha animation on their holder (no OnUpdate). A reversal mid-fade starts
-- from the alpha reached so far.
local FADE_TIME = 0.2

local function ShowBackground(instant)
    local hgt = widget.bgHolder
    widget.topLine:SetShown(TrackerCfg("showTopLine") ~= false)
    local target = (not TrackerCfg("customBgHover") or Hovered()) and 1 or 0
    if instant or not TrackerCfg("customBgFade") then
        hgt.fade:Stop()
        hgt.target = target
        hgt:SetAlpha(target)
        return
    end
    if hgt.target == target then return end
    hgt.target = target
    local current = hgt:GetAlpha()
    if hgt.fade:IsPlaying() then
        current = hgt.from + (hgt.to - hgt.from) * hgt.anim:GetSmoothProgress()
        hgt.fade:Stop()
    end
    hgt.from, hgt.to = current, target
    hgt.anim:SetFromAlpha(current)
    hgt.anim:SetToAlpha(target)
    hgt.anim:SetDuration(math.max(FADE_TIME * math.abs(target - current), 0.01))
    hgt.fade:Play()
end

local function SyncHover()
    if not HoverWanted() then return end
    if BarMode() == "hover" and MaxScroll() > 0 then rail:SetShown(BarVisible()) end
    if TrackerCfg("customBgHover") then ShowBackground() end
end

local function UpdateThumb()
    local range = MaxScroll()
    if range <= 0 then
        rail:Hide()
        scroller:SetVerticalScroll(0)
        return
    end
    rail:SetShown(BarVisible())
    local current = math.min(scroller:GetVerticalScroll(), range)
    scroller:SetVerticalScroll(current)
    local thumbH = math.max(20, viewH * viewH / contentH)
    knob:SetHeight(thumbH)
    knob:ClearAllPoints()
    knob:SetPoint("TOP", rail, "TOP", 0, -(viewH - thumbH) * current / range)
end

local function ScrollTo(val)
    scroller:SetVerticalScroll(math.max(0, math.min(val, MaxScroll())))
    HideOverlay()
    UpdateThumb()
    SyncItems()
end

-------------------------------------------------------------------------------
-- Render
-------------------------------------------------------------------------------
-- Focus button: Blizzard's quest POI art, beside the title.
local function FocusOnEnter(self)
    CUI.ShowWidgetTooltip(
        self,
        self.id == C_SuperTrack.GetSuperTrackedQuestID() and STOP_SUPER_TRACK_QUEST or SUPER_TRACK_QUEST
    )
end

local function FocusButton(line)
    local widget = line.focus
    if widget then return widget end
    widget = CreateFrame("Button", nil, line)
    widget.glow = widget:CreateTexture(nil, "BACKGROUND")
    widget.glow:SetPoint("CENTER")
    widget.glow:SetAtlas("UI-QuestPoi-OuterGlow")
    -- Blizzard draws 32px art on a 20px button: the atlases carry padding.
    widget.ring = widget:CreateTexture(nil, "ARTWORK")
    widget.ring:SetPoint("CENTER")
    widget.icon = widget:CreateTexture(nil, "OVERLAY")
    widget.icon:SetPoint("CENTER")
    local highlight = widget:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetPoint("CENTER")
    highlight:SetAtlas("UI-QuestPoi-InnerGlow")
    widget.hl = highlight
    highlight:SetBlendMode("ADD")
    widget:SetScript("OnClick", function(self) ToggleFocus(self.id) end)
    widget:SetScript("OnEnter", function(self)
        SyncHover()
        FocusOnEnter(self)
    end)
    widget:SetScript("OnLeave", function()
        SyncHover()
        CUI.HideWidgetTooltip()
    end)
    line.focus = widget
    return widget
end

local function ShowFocusButton(line, questId, isComplete, px)
    local widget = FocusButton(line)
    local focused = questId == C_SuperTrack.GetSuperTrackedQuestID()
    widget.id = questId
    widget:Show()
    if widget.lastSize == px and widget.lastFocused == focused and widget.lastComplete == isComplete then
        return
    end
    widget.lastSize, widget.lastFocused, widget.lastComplete = px, focused, isComplete
    widget:SetSize(px, px)
    local art = px * 1.6
    widget.ring:SetSize(art, art)
    widget.hl:SetSize(art, art)
    widget:ClearAllPoints()
    widget:SetPoint("TOPRIGHT", line, "TOPLEFT", -FOCUS_GAP, (px - (TrackerCfg("titleFontSize") or 12)) / 2)
    if isComplete then
        widget.ring:SetAtlas("UI-QuestIcon-TurnIn-Normal")
        widget.icon:Hide()
    else
        widget.ring:SetAtlas(focused and "UI-QuestPoi-QuestNumber-SuperTracked" or "UI-QuestPoi-QuestNumber")
        widget.icon:SetAtlas(focused and "Quest-In-Progress-Icon-Brown" or "Quest-In-Progress-Icon-yellow")
        widget.icon:SetSize(px * 0.75, px * 0.75)
        widget.icon:Show()
    end
    widget.glow:SetSize(art * 1.25, art * 1.25)
    widget.glow:SetShown(focused)
end

local function AddObjectives(questId, posY, width, posX)
    local gap = TrackerCfg("customObjSpacing") or 1
    local wid = width - posX
    local l, hgt
    if C_QuestLog.IsFailed(questId) then
        l, hgt = AcquireLine("obj", questId, "- " .. FAILED, posX, posY, wid)
        l.text:SetTextColor(DIM_RED_FONT_COLOR.r, DIM_RED_FONT_COLOR.g, DIM_RED_FONT_COLOR.b, 1)
        return posY + hgt + gap
    end
    if C_QuestLog.IsComplete(questId) then
        local logIndex = C_QuestLog.GetLogIndexForQuestID(questId)
        local textValue = logIndex and GetQuestLogCompletionText(logIndex)
            or C_QuestLog.GetNextWaypointText(questId)
            or QUEST_WATCH_QUEST_READY
        l, hgt = AcquireLine("obj", questId, "- " .. textValue, posX, posY, wid)
        local red, green, blue = TrackerNS.GetCompletedRGB()
        l.text:SetTextColor(red, green, blue, 1)
        return posY + hgt + gap
    end
    local objectives = C_QuestLog.GetQuestObjectives(questId)
    if not objectives then return posY end
    -- First sight of a quest records its texts without flashing.
    local previous = TrackerCfg("customFlashUpdates") and prevObj[questId]
    if TrackerCfg("customFlashUpdates") and not previous then
        previous = {}
        prevObj[questId] = previous
    end
    for index, object in ipairs(objectives) do
        local textValue = object.text
        if textValue and textValue ~= "" then
            if object.type == "progressbar" then
                textValue = textValue .. " (" .. math.floor(GetQuestProgressBarPercent(questId) or 0) .. "%)"
            end
            l, hgt = AcquireLine("obj", questId, "- " .. textValue, posX, posY, wid, questId * 100 + index)
            l.text:SetTextColor(ObjectiveRGBA(object))
            if previous then
                if previous[index] and previous[index] ~= textValue then Flash(l) end
                previous[index] = textValue
            end
            posY = posY + hgt + gap
        end
    end
    return posY
end

-------------------------------------------------------------------------------
-- Quest timers. Blizzard shows them in QuestTimerFrame, a child of its muted
-- tracker, so they went with it. Render puts a timer line under each listed
-- quest with a running timer, collapsed or complete included, and a bar under
-- the text when the quest's total time is known; while one shows, a tick
-- repaints only those lines, just after each displayed second changes.
-------------------------------------------------------------------------------
local timerEnd = {} -- questID -> GetTime() its timer runs out at
local timerLines, timerN = {}, 0 -- the timer lines the last render placed
local tickArmed = false
local TimerTick -- defined below
local BAR_H = 5
-- Fill: gold, red under a third of the time left (the skin's timer colours).
local TIMER_FILL, TIMER_LOW = { 1, 0.82, 0.2 }, { 1, 0.3, 0.3 }

-- Blizzard's timer ramp: white, yellow under two thirds left, red under one.
local function TimerRGB(pct)
    if pct > 0.66 then return 1, 1, 1 end
    if pct > 0.33 then return 1, 1, (pct - 0.33) / 0.33 end
    return 1, pct / 0.33, 0
end

local function TimerText(leftX) return "- " .. TIME_REMAINING .. " " .. SecondsToClock(leftX) end

-- The bar under a timer line: a track in the shared pixel border, made once
-- per line (AcquireLine hides it).
local function TimerBar(l)
    local barFrame = l.bar
    if barFrame then return barFrame end
    barFrame = CreateFrame("StatusBar", nil, l)
    barFrame:SetHeight(BAR_H)
    barFrame:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    barFrame:SetMinMaxValues(0, 1)
    local backdrop = barFrame:CreateTexture(nil, "BACKGROUND")
    backdrop:SetAllPoints()
    backdrop:SetColorTexture(0.15, 0.15, 0.15, 0.8)
    CUI.PP.CreateBorder(barFrame, 0, 0, 0, 0.9, 1, "OVERLAY", 1)
    l.bar = barFrame
    return barFrame
end

-- Repaints one timer line. False when its new text no longer fits the row it
-- was laid out in: a full render places it again.
local function PaintTimer(l, nowTime)
    local leftX = timerEnd[l.timerQuest] - nowTime
    if leftX < 0 then leftX = 0 end
    local textValue = TimerText(leftX)
    if l.lastText ~= textValue then
        l.text:SetText(textValue)
        l.lastText = textValue
        if math.ceil(l.text:GetStringHeight()) ~= l.lastH then return false end
    end
    local sum = l.timerTotal
    local pct = sum and math.min(leftX / sum, 1) or 1
    l.text:SetTextColor(TimerRGB(pct))
    local barFrame = sum and l.bar
    if barFrame then
        barFrame:SetWidth(math.max(l.text:GetStringWidth() - l.dashW, 1))
        barFrame:SetValue(pct)
        local c = pct > 0.33 and TIMER_FILL or TIMER_LOW
        barFrame:SetStatusBarColor(c[1], c[2], c[3])
    end
    return true
end

-- The next tick lands just after the soonest displayed second changes
-- (SecondsToClock floors).
local function ArmTick(nowTime)
    if tickArmed or timerN == 0 then return end
    local wait = 1
    for index = 1, timerN do
        local leftX = timerEnd[timerLines[index].timerQuest] - nowTime
        if leftX > 0 then
            local frac = leftX - math.floor(leftX)
            if frac < wait then wait = frac end
        end
    end
    tickArmed = true
    C_Timer.After(wait + 0.02, TimerTick)
end

TimerTick = function()
    tickArmed = false
    if timerN == 0 or not widget then return end
    -- Hidden: stop; the show renders again and the tick comes back with it.
    if not widget:IsShown() then
        stale = true
        return
    end
    local nowTime = GetTime()
    for index = 1, timerN do
        if not PaintTimer(timerLines[index], nowTime) then
            Queue()
            return
        end
    end
    ArmTick(nowTime)
end

local function AddTimer(questId, posY, width, posX)
    local ends = timerEnd[questId]
    if not ends then return posY end
    local nowTime = GetTime()
    local l, hgt =
        AcquireLine("obj", questId, TimerText(math.max(ends - nowTime, 0)), posX, posY, width - posX)
    posY = posY + hgt + (TrackerCfg("customObjSpacing") or 1)
    local sum = C_QuestLog.GetTimeAllowed(questId)
    l.timerQuest = questId
    l.timerTotal = (sum and sum > 0) and sum or nil
    timerN = timerN + 1
    timerLines[timerN] = l
    if l.timerTotal then
        local barFrame = TimerBar(l)
        if not l.dashW then
            -- The "- " prefix's width in the line's font: the bar starts under the text.
            l.text:SetText("- ")
            l.dashW = l.text:GetStringWidth()
            l.text:SetText(l.lastText)
        end
        barFrame:ClearAllPoints()
        barFrame:SetPoint("TOPLEFT", l, "BOTTOMLEFT", l.dashW, -1)
        barFrame:Show()
        posY = posY + BAR_H + 2
    end
    PaintTimer(l, nowTime)
    return posY
end

-------------------------------------------------------------------------------
-- Tracked recipes. Blizzard lists them in its tracker's Professions module,
-- muted with the rest of that tracker, so they follow the quests here under a
-- Professions header: each recipe with its required reagents, written as
-- Blizzard writes them. A click on a recipe goes to its block in Blizzard's
-- tracker through the header overlay below (out of combat), so Blizzard's own
-- code opens the recipe, untracks it or opens its menu.
-------------------------------------------------------------------------------
local RECIPE_KEY = "@recipes" -- the header's id, never a zone name
local RECIPE_COLLAPSED = "z:" .. RECIPE_KEY -- its key in the collapsed set
local reagentState = {} -- a reagent line's progress, for ObjectiveRGBA
local recipeEvents = false -- bag and currency events: while a recipe is listed
local nameAsked = {} -- itemID -> true once its name was asked for, false if it never loads
local nameWait, nameListen = false, false -- a reagent name is loading; ITEM_DATA_LOAD_RESULT registered
local schematics = {} -- recipe id (negative: recraft) -> its schematic, until the tracked recipes change

-- One required reagent slot: "- 2/4 Linen Cloth". A reagent whose item name
-- has not loaded is left out, asked for once; its load renders the list again.
local function AddReagent(ident, slotFrame, posY, width, posX)
    local region = slotFrame.reagents and slotFrame.reagents[1]
    if not region then return posY end
    local name
    if ProfessionsUtil.IsReagentSlotBasicRequired(slotFrame) then
        if region.itemID then
            name = C_Item.GetItemNameByID(region.itemID)
            if not name and nameAsked[region.itemID] ~= false then
                nameWait = true
                if not nameAsked[region.itemID] then
                    nameAsked[region.itemID] = true
                    C_Item.RequestLoadItemDataByID(region.itemID)
                end
            end
        elseif region.currencyID then
            local details = C_CurrencyInfo.GetCurrencyInfo(region.currencyID)
            name = details and details.name
        end
    elseif ProfessionsUtil.IsReagentSlotModifyingRequired(slotFrame) and slotFrame.slotInfo then
        name = slotFrame.slotInfo.slotText
    end
    if not name then return posY end
    local textValue
    if slotFrame:IsVariableQuantityReagent(region) then
        textValue =
            PROFESSIONS_TRACKER_REAGENT_RANGE_FORMAT:format(slotFrame:GetVariableQuantityRange(region))
        reagentState.finished, reagentState.numRequired = false, 0
    else
        local need = slotFrame:GetQuantityRequired(region)
        local have = ProfessionsUtil.AccumulateReagentsInPossession(slotFrame.reagents)
        textValue = PROFESSIONS_TRACKER_REAGENT_COUNT_FORMAT:format(have, need)
        reagentState.finished, reagentState.numFulfilled, reagentState.numRequired = have >= need, have, need
    end
    local l, hgt = AcquireLine(
        "obj",
        ident,
        "- " .. PROFESSIONS_TRACKER_REAGENT_FORMAT:format(textValue, name),
        posX,
        posY,
        width - posX
    )
    l.text:SetTextColor(ObjectiveRGBA(reagentState))
    return posY + hgt + (TrackerCfg("customObjSpacing") or 1)
end

-- id: the recipe, negative for a recraft, as Blizzard keys its blocks.
local function AddRecipeList(entries, isRecraft, posY, width, titleX, objX)
    for _, recipeID in ipairs(entries) do
        local ident = isRecraft and -recipeID or recipeID
        -- A recipe's schematic is game data: read once and kept until the
        -- tracked recipes change (names and counts are read on every pass).
        local schematic = schematics[ident]
        if not schematic then
            schematic = ProfessionsUtil.GetRecipeSchematic(recipeID, isRecraft)
            schematics[ident] = schematic
        end
        local name = schematic.name or ""
        if isRecraft then name = PROFESSIONS_CRAFTING_FORM_RECRAFTING_HEADER:format(name) end
        local l, hgt = AcquireLine("recipe", ident, name, titleX, posY, math.max(TITLE_MIN_W, width - titleX))
        l.text:SetTextColor(TrackerNS.GetTitleRGB())
        posY = posY + hgt + 2
        -- Modifying reagent slots first, as Blizzard lists them.
        local slots = schematic.reagentSlotSchematics
        for _, slotFrame in ipairs(slots) do
            if ProfessionsUtil.IsReagentSlotModifyingRequired(slotFrame) then
                posY = AddReagent(ident, slotFrame, posY, width, objX)
            end
        end
        for _, slotFrame in ipairs(slots) do
            if
                ProfessionsUtil.IsReagentSlotRequired(slotFrame)
                and not ProfessionsUtil.IsReagentSlotModifyingRequired(slotFrame)
            then
                posY = AddReagent(ident, slotFrame, posY, width, objX)
            end
        end
        posY = posY + (TrackerCfg("customQuestSpacing") or 4)
    end
    return posY
end

-- The Professions section, after the quests. Its bag and currency events
-- (reagent counts) are registered only while a recipe is tracked.
local function AddRecipes(posY, width, titleX, objX, isCollapsed, zr, zg, zb)
    local entries, recrafts = C_TradeSkillUI.GetRecipesTracked(false), C_TradeSkillUI.GetRecipesTracked(true)
    local any = (entries[1] or recrafts[1]) ~= nil
    if any ~= recipeEvents then
        recipeEvents = any
        if any then
            eventTag:RegisterEvent("BAG_UPDATE_DELAYED")
            eventTag:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
        else
            eventTag:UnregisterEvent("BAG_UPDATE_DELAYED")
            eventTag:UnregisterEvent("CURRENCY_DISPLAY_UPDATE")
        end
    end
    nameWait = false
    if any then
        if posY > 0 then posY = posY + 6 end
        local shut = isCollapsed[RECIPE_COLLAPSED]
        local l, hgt = AcquireLine(
            "zone",
            RECIPE_KEY,
            (shut and "+ " or "") .. PROFESSIONS_TRACKER_HEADER_PROFESSION,
            0,
            posY,
            width
        )
        l.text:SetTextColor(zr, zg, zb, 1)
        posY = posY + hgt + 3
        if not shut then
            posY = AddRecipeList(entries, false, posY, width, titleX, objX)
            posY = AddRecipeList(recrafts, true, posY, width, titleX, objX)
        end
    end
    if nameWait ~= nameListen then
        nameListen = nameWait
        if nameWait then
            eventTag:RegisterEvent("ITEM_DATA_LOAD_RESULT")
        else
            eventTag:UnregisterEvent("ITEM_DATA_LOAD_RESULT")
        end
    end
    return posY
end

-------------------------------------------------------------------------------
-- Quest item buttons (customItemButtons). Secure, so they live on their own
-- layer under UIParent and are placed by screen position, never anchored to
-- our frame (which must stay free to move and hide in combat). In combat a
-- layout change waits for combat to end; buttons keep their spot and item.
-------------------------------------------------------------------------------
local itemLayer
local itemList, itemWant, itemN = {}, {}, 0 -- itemWant: pooled, first itemN in use
local cdRegistered = false

-- Tooltip side facing the screen centre, away from the edge.
local function TooltipAnchorSide()
    local cx = widget:GetCenter()
    local onLeft = cx
        and cx * widget:GetEffectiveScale() < UIParent:GetWidth() * UIParent:GetEffectiveScale() / 2
    return onLeft and "ANCHOR_RIGHT" or "ANCHOR_LEFT"
end

-- Log index looked up per use: it shifts as quests come and go.
local function UpdateItemCooldown(b)
    local logIndex = C_QuestLog.GetLogIndexForQuestID(b.questID)
    if not logIndex then return end
    local start, duration, enable = GetQuestLogSpecialItemCooldown(logIndex)
    if start then CooldownFrame_Set(b.cd, start, duration, enable) end
end

local function ItemButton(index)
    local widget = itemList[index]
    if widget then return widget end
    widget = CreateFrame("Button", nil, itemLayer, "SecureActionButtonTemplate")
    widget:RegisterForClicks("AnyUp")
    widget:SetAttribute("type", "item")
    widget:SetAttribute("useOnKeyDown", false)
    local backdrop = widget:CreateTexture(nil, "BACKGROUND")
    backdrop:SetAllPoints()
    backdrop:SetColorTexture(0, 0, 0, 1)
    widget.icon = widget:CreateTexture(nil, "ARTWORK")
    widget.icon:SetPoint("TOPLEFT", 1, -1)
    widget.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    widget.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    widget.cd = CreateFrame("Cooldown", nil, widget, "CooldownFrameTemplate")
    widget.cd:SetAllPoints(widget.icon)
    widget.count = widget:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    widget.count:SetPoint("BOTTOMRIGHT", -1, 1)
    widget:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    widget:SetScript("OnEnter", function(self)
        SyncHover()
        GameTooltip:SetOwner(self, TooltipAnchorSide())
        local logIndex = C_QuestLog.GetLogIndexForQuestID(self.questID)
        if logIndex then GameTooltip:SetQuestLogSpecialItem(logIndex) end
        GameTooltip:Show()
    end)
    widget:SetScript("OnLeave", function()
        SyncHover()
        GameTooltip:Hide()
    end)
    itemList[index] = widget
    return widget
end

-- Shows a button for each wanted item whose title row is fully in view.
function SyncItems()
    if not itemLayer or (#itemList == 0 and itemN == 0) then return end
    if InCombatLockdown() then
        mod.CombatQueue.Defer("EQT_CustomItems", SyncItems)
        return
    end
    local num = 0
    local topY, bottom = scroller:GetTop(), scroller:GetBottom()
    if widget:IsVisible() and topY then
        for index = 1, itemN do
            local wid = itemWant[index]
            local l = wid.line
            local lt, lr = l:GetTop(), l:GetRight()
            if lt and lt <= topY + 0.5 and lt - wid.size >= bottom - 0.5 then
                num = num + 1
                local widget = ItemButton(num)
                local s = l:GetEffectiveScale() / widget:GetEffectiveScale()
                local posX, posY, px = (lr + hookW + 4) * s, lt * s, wid.size * s
                if widget.lastX ~= posX or widget.lastY ~= posY or widget.lastSize ~= px then
                    widget.lastX, widget.lastY, widget.lastSize = posX, posY, px
                    widget:SetSize(px, px)
                    widget:ClearAllPoints()
                    widget:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", posX, posY)
                end
                if widget.itemID ~= wid.itemID then
                    widget.itemID = wid.itemID
                    widget:SetAttribute("item", "item:" .. wid.itemID)
                end
                widget.questID = wid.questID
                widget.icon:SetTexture(wid.tex)
                widget.count:SetText((wid.charges and wid.charges > 1) and wid.charges or "")
                UpdateItemCooldown(widget)
                widget:Show()
            end
        end
    end
    for index = num + 1, #itemList do
        itemList[index]:Hide()
    end
end

-------------------------------------------------------------------------------
-- Row hooks (public, CludesUI.RegisterQuestTrackerRow): other addons add
-- their own icons or buttons to quest title rows. Each hook gets its own slot
-- frame per row, right of the title, its reserved width wide. Developer
-- guide: PLUGINS_API.md.
-------------------------------------------------------------------------------
local function RunRowHooks(l, questId)
    local slots = l.slots
    if not slots then
        slots = {}
        l.slots = slots
    end
    for index, hgt in ipairs(rowHooks) do
        local s = slots[index]
        if not s then
            s = CreateFrame("Frame", nil, l)
            s:SetPoint("TOPLEFT", l, "TOPRIGHT", hgt.x, 0)
            s:SetPoint("BOTTOMLEFT", l, "BOTTOMRIGHT", hgt.x, 0)
            s:SetWidth(hgt.width)
            slots[index] = s
        end
        s:Show()
        local success, err = pcall(hgt.fn, s, questId, l.text)
        if not success then geterrorhandler()(err) end
    end
end

local function Draw()
    pending = false
    if not widget then return end
    if not widget:IsShown() then
        stale = true
        return
    end
    stale = false
    HideOverlay()
    widget:SetMouseMotionEnabled(HoverWanted() and true or false)
    if not TrackerCfg("customFlashUpdates") then wipe(prevObj) end
    itemN = 0
    wipe(timerEnd)
    timerN = 0
    local timers = C_QuestLog.GetQuestTimers()
    if timers then
        local nowTime = GetTime()
        for _, t in ipairs(timers) do
            if t.questID and t.questTimer then timerEnd[t.questID] = nowTime + t.questTimer end
        end
    end
    BuildList()
    local isCollapsed = CharStore().ctCollapsed
    local width = (TrackerCfg("customWidth") or DEF_WIDTH) - PAD * 2 - BAR_GAP
    childFrame:SetWidth(width)
    used = 0
    local posY = 0
    local itemSize = TrackerCfg("customItemButtons") and (TrackerCfg("titleFontSize") or 12) + 12
    if not isCollapsed.all then
        local set = TrackerCfg("customGroupByZone")
        -- Focus buttons take a column left of the titles.
        local titleSize = TrackerCfg("titleFontSize") or 12
        local focusPx = TrackerCfg("customFocusClick") and titleSize + 6 or 0
        -- The art overhangs the button by 0.3x each side; keep it off the clip edge, less 2
        -- (the ring's outer edge is the atlas padding).
        local titleX = focusPx > 0 and focusPx * 1.3 - 2 + FOCUS_GAP or 0
        -- It also rises above its title: the button sits (size - font) / 2 higher and the
        -- focused glow reaches 0.5x past it. A quest on the first row starts that far down.
        local focusRise = focusPx > 0 and math.ceil((focusPx - titleSize) / 2 + focusPx * 0.5) or 0
        local objX = math.max(OBJ_IND, titleX)
        local collapseDone = TrackerCfg("customCollapseCompleted")
        local doneOpen = CharStore().ctDoneOpen
        local lastZone
        local zr, zg, zb = ZoneRGB()
        for _, questId in ipairs(sequence) do
            local zone = zoneOf[questId] or OTHER or "Other"
            if set and zone ~= lastZone then
                lastZone = zone
                if posY > 0 then posY = posY + 6 end
                local mark = isCollapsed["z:" .. zone] and "+ " or ""
                local l, hgt = AcquireLine("zone", zone, mark .. zone, 0, posY, width)
                l.text:SetTextColor(zr, zg, zb, 1)
                posY = posY + hgt + 3
            end
            if not (set and isCollapsed["z:" .. zone]) then
                local isComplete = C_QuestLog.IsComplete(questId) == true
                local entry
                if itemSize then
                    local logIndex = C_QuestLog.GetLogIndexForQuestID(questId)
                    local itemLink, texture, charges, showDone
                    if logIndex then
                        itemLink, texture, charges, showDone = GetQuestLogSpecialItemInfo(logIndex)
                    end
                    local itemId = itemLink and tonumber(itemLink:match("item:(%d+)"))
                    if itemId and (not isComplete or showDone) then
                        itemN = itemN + 1
                        entry = itemWant[itemN]
                        if not entry then
                            entry = {}
                            itemWant[itemN] = entry
                        end
                        entry.itemID, entry.tex, entry.charges = itemId, texture, charges
                        entry.questID, entry.size = questId, itemSize
                    end
                end
                local itemW = entry and itemSize + 8 or 0
                if posY == 0 then posY = focusRise end
                local topY = posY
                local l, hgt = AcquireLine(
                    "quest",
                    questId,
                    QuestTitle(questId),
                    titleX,
                    posY,
                    math.max(TITLE_MIN_W, width - titleX - itemW - hookW)
                )
                l.text:SetTextColor(TitleRGB(questId, isComplete))
                if rowHooks[1] then RunRowHooks(l, questId) end
                if focusPx > 0 then
                    ShowFocusButton(l, questId, isComplete, focusPx)
                elseif l.focus then
                    l.focus:Hide()
                end
                if entry then entry.line = l end
                posY = posY + hgt + 2
                local shut
                if isComplete and collapseDone then
                    shut = not doneOpen[questId]
                else
                    shut = isCollapsed[questId]
                end
                if not shut then posY = AddObjectives(questId, posY, width, objX) end
                posY = AddTimer(questId, posY, width, objX)
                if entry then posY = math.max(posY, topY + itemSize + 2) end
                posY = posY + (TrackerCfg("customQuestSpacing") or 4)
            end
        end
        posY = AddRecipes(posY, width, titleX, objX, isCollapsed, zr, zg, zb)
    end
    for index = used + 1, #lines do
        lines[index]:Hide()
    end

    local _, numQuests = C_QuestLog.GetNumQuestLogEntries()
    headerFrame.count:SetText((numQuests or 0) .. "/" .. C_QuestLog.GetMaxNumQuestsCanAccept())
    headerFrame.toggle:SetText(isCollapsed.all and "+" or "-")

    contentH = posY
    childFrame:SetHeight(math.max(posY, 1))
    local maxH = TrackerCfg("customMaxHeight") or DEF_HEIGHT
    local body = posY > 0 and (posY + PAD) or 0
    -- Unlock Mode shows the whole area the tracker may grow into, so its
    -- mover and Height row match what is being set.
    local hgt = CUI._unlockActive and maxH or math.min(HEADER_H + body, maxH)
    viewH = math.max(hgt - HEADER_H - PAD, 0)
    widget:SetHeight(hgt)
    -- An Unlock Mode link places the tracker by its centre, from its height:
    -- back onto it in the render that changed the height, as Unlock Mode's own
    -- resize notice is throttled and can skip the last change of a burst (a
    -- quest in a new zone arrives over several renders).
    if hgt ~= widget.renderH then
        widget.renderH = hgt
        if not CUI._unlockActive then CUI.ReapplyOwnAnchor(UNLOCK_KEY) end
    end
    UpdateThumb()
    if (itemSize and true or false) ~= cdRegistered then
        cdRegistered = not cdRegistered
        if cdRegistered then
            eventTag:RegisterEvent("BAG_UPDATE_COOLDOWN")
        else
            eventTag:UnregisterEvent("BAG_UPDATE_COOLDOWN")
        end
    end
    SyncItems()
    ArmTick(GetTime())
end

function Queue()
    if pending then return end
    pending = true
    C_Timer.After(0, Draw)
end
TrackerNS.RefreshCustom = Queue

-- Public: fn(slot, questID, titleFontString) runs for each quest title row on
-- every render. width (0-64, default 0) is kept free right of the title.
local HOOK_MAX_W = 64
function CUI.RegisterQuestTrackerRow(ident, func, width)
    if type(ident) ~= "string" or ident == "" or type(func) ~= "function" then return false end
    for _, hgt in ipairs(rowHooks) do
        if hgt.id == ident then return false end
    end
    width = Clamp(math.floor(tonumber(width) or 0), 0, HOOK_MAX_W)
    rowHooks[#rowHooks + 1] = { id = ident, fn = func, width = width, x = hookW }
    hookW = hookW + width
    Queue()
    return true
end

-- Public: re-render the tracker, for a hook whose own state changed.
CUI.RefreshQuestTrackerRows = Queue

-------------------------------------------------------------------------------
-- Interaction. Nothing here touches Blizzard's tracker, the watch list, the
-- super-track or the world map (opening it from addon code taints its pins:
-- SetPassThroughButtons blocked in combat, tested 2026-10-17). Untrack is our
-- list's own; a modified click that untracks reaches Blizzard's own quest header
-- through the secure overlay below, whose code edits the watch list.
-------------------------------------------------------------------------------
local function Untrack(questId)
    local saved = CharStore()
    saved.ctUntracked[questId] = true
    saved.ctPinned[questId] = nil
    Queue()
end

local function TogglePin(questId)
    local pinned = CharStore().ctPinned
    pinned[questId] = not pinned[questId] or nil
    Queue()
end

local function Abandon(questId)
    CUI:ShowConfirmPopup({
        title = ABANDON_QUEST,
        message = ABANDON_QUEST_CONFIRM:format(C_QuestLog.GetTitleForQuestID(questId) or ""),
        confirmText = ACCEPT,
        cancelText = CANCEL,
        onConfirm = function()
            C_QuestLog.SetSelectedQuest(questId)
            C_QuestLog.SetAbandonQuest()
            C_QuestLog.AbandonQuest()
        end,
    })
end

-- Focus (customFocusClick): sets the super-track straight from our click.
-- Skin.lua dropped this on retail for tainting the world map's pins; on WoW
-- Forever taint logs stayed clean, focusing in combat and using map pins.
function ToggleFocus(questId)
    local current = C_SuperTrack.GetSuperTrackedQuestID()
    C_SuperTrack.SetSuperTrackedQuestID(current == questId and 0 or questId)
end

-- For the details window (Details.lua).
TrackerNS.CustomQuestActions = { Focus = ToggleFocus, Untrack = Untrack, Abandon = Abandon }

local function Disabled() return true end
local MENU_OPTS = { fontKey = "questTracker" }

-- The quest's title heads the menu as a disabled row.
local function ShowMenu(ownerFrame, questId)
    local itemList =
        { { text = C_QuestLog.GetTitleForQuestID(questId) or "", noLoc = true, isDisabled = Disabled } }
    if TrackerCfg("customFocusClick") then
        local focused = C_SuperTrack.GetSuperTrackedQuestID() == questId
        itemList[#itemList + 1] = {
            text = focused and STOP_SUPER_TRACK_QUEST or SUPER_TRACK_QUEST,
            noLoc = true,
            onClick = function() ToggleFocus(questId) end,
        }
    end
    itemList[#itemList + 1] = {
        noLoc = true,
        text = CharStore().ctPinned[questId] and CUI.L("Unpin") or CUI.L("Pin to Top"),
        onClick = function() TogglePin(questId) end,
    }
    itemList[#itemList + 1] = {
        text = OBJECTIVES_STOP_TRACKING,
        noLoc = true,
        onClick = function() Untrack(questId) end,
    }
    if IsInGroup() and C_QuestLog.IsPushableQuest(questId) then
        itemList[#itemList + 1] = {
            text = SHARE_QUEST,
            noLoc = true,
            onClick = function() QuestLogPushQuest(C_QuestLog.GetLogIndexForQuestID(questId)) end,
        }
    end
    itemList[#itemList + 1] = {
        text = ABANDON_QUEST_ABBREV,
        noLoc = true,
        onClick = function() Abandon(questId) end,
    }
    -- Wowhead Quest Links: the entry Blizzard's tracker menu gets, after a divider
    -- as there (QuestLinks.lua).
    if TrackerNS.WowheadQuestOK(questId) then
        itemList[#itemList + 1] = "---"
        itemList[#itemList + 1] = {
            text = CUI.L("Wowhead Link"),
            noLoc = true,
            onClick = function() TrackerNS.ShowWowheadLink(questId) end,
        }
    end
    CUI.ShowContextMenu(ownerFrame, itemList, MENU_OPTS)
end

local function ToggleCollapsed(key)
    local isCollapsed = CharStore().ctCollapsed
    isCollapsed[key] = not isCollapsed[key] or nil
    Queue()
end

function OnLineClick(self, btnFrame)
    local ident = self.id
    if self.kind == "zone" then
        ToggleCollapsed("z:" .. ident)
    elseif self.kind == "quest" then
        if btnFrame == "RightButton" then
            ShowMenu(self, ident)
            return
        end
        if IsModifiedClick("CHATLINK") and ChatFrameUtil.TryInsertQuestLinkForQuestID(ident) then return end
        if IsModifiedClick("QUESTWATCHTOGGLE") then
            Untrack(ident)
            return
        end
        local action = TrackerCfg("customClickAction") or "collapse"
        if action ~= "collapse" and not IsModifierKeyDown() then
            if action == "details" then TrackerNS.ShowQuestDetails(ident) end
            -- map: the overlay's job; reached only in combat, where it is off.
            return
        end
        if TrackerCfg("customCollapseCompleted") and C_QuestLog.IsComplete(ident) then
            local open = CharStore().ctDoneOpen
            open[ident] = not open[ident] or nil
            Queue()
        else
            ToggleCollapsed(ident)
        end
    end
end

-------------------------------------------------------------------------------
-- Blizzard header overlay. One secure button over the hovered quest line clicks
-- the quest's block in Blizzard's muted tracker, so Blizzard's own header click
-- does what addon code cannot do cleanly: with Open Quest Log (customClickAction
-- "map") a plain left click opens the map (from addon code it taints the map's
-- pins, SetPassThroughButtons blocked in combat, and a macro /run carries
-- ForceTaint_Strong into them), and on every setting the untrack modifier
-- (QUESTWATCHTOGGLE, Shift by default) untracks the quest in the game's own watch
-- list, so the quest log follows (or, with the chat box open, puts its link in
-- chat). Over a tracked recipe it takes every left and right click to the
-- recipe's block, whose own code opens the recipe, untracks it, links it or
-- opens its menu. Only for a quest or recipe Blizzard's tracker lists; placed by
-- screen position like the item buttons; out of combat only: it hides when
-- combat starts, and a click then takes our own path (none for a recipe). Open
-- Quest Details uses our own window (Details.lua).
-------------------------------------------------------------------------------
local QUEST_MODULES = { "QuestObjectiveTracker", "CampaignQuestObjectiveTracker" }
-- The untrack modifier as a secure attribute prefix (a single-modifier binding)
local UNTRACK_PREFIX = { SHIFT = "shift-", CTRL = "ctrl-", ALT = "alt-" }
local overlayFrame

-- The header button of Blizzard's block for the quest, if it has one.
local function BlizzardHeader(questId)
    for _, name in ipairs(QUEST_MODULES) do
        local module = _G[name]
        local block = module and module.GetExistingBlock and module:GetExistingBlock(questId)
        if block and block.HeaderButton then return block.HeaderButton end
    end
end

-- The header button of Blizzard's block for a tracked recipe (id: negative
-- for a recraft, as Blizzard keys its blocks), if it has one.
local function RecipeHeader(ident)
    local module = _G.ProfessionsRecipeTracker
    local block = module and module.GetExistingBlock and module:GetExistingBlock(ident)
    return block and block.HeaderButton
end

local function Overlay()
    if overlayFrame then return overlayFrame end
    overlayFrame = CreateFrame("Button", nil, itemLayer, "SecureActionButtonTemplate")
    overlayFrame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    -- The clicks set per line (ShowOverlay) go to Blizzard's header; the rest
    -- go to PostClick, our own line click.
    overlayFrame:SetAttribute("useOnKeyDown", false)
    overlayFrame:SetScript("PostClick", function(self, btnFrame)
        -- A recipe: Blizzard's recipe block took the click.
        if self.line.kind == "recipe" then return end
        if btnFrame == "LeftButton" then
            local prefixText = SecureButton_GetModifierPrefix(self)
            if self:GetAttribute(prefixText .. "type1") == "click" then
                -- Blizzard's header took it. A quest it untracked also leaves our
                -- list for good, or zone auto-track would list it again.
                if prefixText ~= "" and not C_QuestLog.GetQuestWatchType(self.line.id) then
                    Untrack(self.line.id)
                end
                return
            end
        end
        OnLineClick(self.line, btnFrame)
    end)
    overlayFrame:SetScript("OnEnter", function(self) OnLineEnter(self.line) end)
    overlayFrame:SetScript("OnLeave", function()
        OnLineLeave()
        HideOverlay()
    end)
    return overlayFrame
end

function HideOverlay()
    if overlayFrame and not InCombatLockdown() then overlayFrame:Hide() end
end

-- Covers the part of the line inside the scroll view.
local function ShowOverlay(l)
    if InCombatLockdown() then return end
    local recipe = l.kind == "recipe"
    local headerFrame
    if recipe then
        headerFrame = RecipeHeader(l.id)
    else
        headerFrame = BlizzardHeader(l.id)
    end
    if not headerFrame then return end
    local topY, bottom =
        math.min(l:GetTop(), scroller:GetTop()), math.max(l:GetBottom(), scroller:GetBottom())
    if topY <= bottom then return end
    local o = Overlay()
    local s = l:GetEffectiveScale() / o:GetEffectiveScale()
    o:ClearAllPoints()
    o:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l:GetLeft() * s, topY * s)
    o:SetSize(l:GetWidth() * s, (topY - bottom) * s)
    -- Plain left click: Open Quest Log only. The untrack modifier: always.
    -- A recipe: every left and right click.
    local map = recipe or TrackerCfg("customClickAction") == "map"
    o:SetAttribute("type1", map and "click" or nil)
    o:SetAttribute("clickbutton1", map and headerFrame or nil)
    local untrack = UNTRACK_PREFIX[GetModifiedClick("QUESTWATCHTOGGLE") or ""]
    for _, prefixText in pairs(UNTRACK_PREFIX) do
        local enabled = recipe or prefixText == untrack
        o:SetAttribute(prefixText .. "type1", enabled and "click" or nil)
        o:SetAttribute(prefixText .. "clickbutton1", enabled and headerFrame or nil)
    end
    o:SetAttribute("type2", recipe and "click" or nil)
    o:SetAttribute("clickbutton2", recipe and headerFrame or nil)
    o.line = l
    o:Show()
end

-- One icon line per reward; Blizzard's tooltip helper shows one item, no choices.
-- Uncached items redraw the tooltip once loaded, if owner still holds it.
local function AddRewardLine(e, ownerFrame)
    if not e.name then
        TrackerNS.OnRewardLoad(e, function()
            if GameTooltip:IsOwned(ownerFrame) then OnLineEnter(ownerFrame) end
        end)
        return
    end
    local textValue = e.count
            and e.count > 1
            and BONUS_OBJECTIVE_REWARD_WITH_COUNT_FORMAT:format(
                e.texture,
                HIGHLIGHT_FONT_COLOR:WrapTextInColorCode(e.count),
                e.name
            )
        or BONUS_OBJECTIVE_REWARD_FORMAT:format(e.texture, e.name)
    local color = e.quality and ColorManager.GetColorDataForItemQuality(e.quality)
    if color then
        GameTooltip:AddLine(textValue, color.r, color.g, color.b)
    else
        GameTooltip:AddLine(textValue, 1, 1, 1)
    end
end

local function AddRewards(questId, ownerFrame)
    local region = TrackerNS.QuestRewards(questId)
    if not region then return end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(QUEST_REWARDS, NORMAL_FONT_COLOR:GetRGB())
    if region.xp > 0 then
        GameTooltip:AddLine(BONUS_OBJECTIVE_EXPERIENCE_FORMAT:format(region.xp), 1, 1, 1)
    end
    if region.money > 0 then GameTooltip:AddLine(GetMoneyString(region.money), 1, 1, 1) end
    for _, entry in ipairs(region.rewards) do
        AddRewardLine(entry, ownerFrame)
    end
    if #region.choices > 0 then
        GameTooltip:AddLine(
            REWARD_CHOICES,
            NORMAL_FONT_COLOR.r,
            NORMAL_FONT_COLOR.g,
            NORMAL_FONT_COLOR.b,
            true
        )
        for _, entry in ipairs(region.choices) do
            AddRewardLine(entry, ownerFrame)
        end
    end
end

function OnLineEnter(self)
    SyncHover()
    -- A recipe: only the overlay that takes its clicks to Blizzard's block.
    if self.kind == "recipe" then
        ShowOverlay(self)
        return
    end
    if self.kind ~= "quest" then return end
    ShowOverlay(self)
    GameTooltip:SetOwner(self, TooltipAnchorSide())
    if IsInGroup() then
        GameTooltip:SetQuestPartyProgress(self.id)
    else
        local itemLink = GetQuestLink(self.id)
        if itemLink then
            GameTooltip:SetHyperlink(itemLink)
        else
            GameTooltip:SetText(C_QuestLog.GetTitleForQuestID(self.id) or "")
        end
    end
    AddRewards(self.id, self)
    GameTooltip:Show()
end

function OnLineLeave()
    SyncHover()
    GameTooltip:Hide()
end

-------------------------------------------------------------------------------
-- Frame
-------------------------------------------------------------------------------
local function ApplyBackground()
    if not widget then return end
    local cfg = TrackerNS.DB()
    widget.bg:SetColorTexture(cfg.bgR or 0, cfg.bgG or 0, cfg.bgB or 0, cfg.bgAlpha or 0.5)
    widget.topLine:SetColorTexture(TrackerNS.GetLineRGB())
    ShowBackground(true)
    local hr, hg, hb = TrackerNS.GetHeaderRGB()
    headerFrame.text:SetTextColor(hr, hg, hb)
    headerFrame.toggle:SetTextColor(hr, hg, hb)
end

local function RefreshFonts()
    if not widget then return end
    fontGen = fontGen + 1
    local px = TrackerCfg("headerFontSize") or 13
    StyleText(headerFrame.text, px)
    StyleText(headerFrame.toggle, px)
    StyleText(headerFrame.count, TrackerCfg("objectiveFontSize") or 10)
    headerFrame.text:SetText(TRACKER_HEADER_QUESTS)
    Queue()
end

local function SavedPos()
    local p = TrackerCfg("customPos")
    return p and p.point and p or { point = "TOPRIGHT", relPoint = "TOPRIGHT", x = -80, y = -280 }
end

-- Anchor fractions per point, for re-anchoring a saved position by the edge
-- the tracker keeps in place.
local HX = {
    LEFT = 0,
    CENTER = 0.5,
    RIGHT = 1,
    TOP = 0.5,
    BOTTOM = 0.5,
    TOPLEFT = 0,
    TOPRIGHT = 1,
    BOTTOMLEFT = 0,
    BOTTOMRIGHT = 1,
}
local VY = {
    TOP = 1,
    CENTER = 0.5,
    BOTTOM = 0,
    LEFT = 0.5,
    RIGHT = 0.5,
    TOPLEFT = 1,
    TOPRIGHT = 1,
    BOTTOMLEFT = 0,
    BOTTOMRIGHT = 0,
}
-- The same horizontal point on the other vertical edge.
local OTHER_EDGE = {
    TOPLEFT = "BOTTOMLEFT",
    TOP = "BOTTOM",
    TOPRIGHT = "BOTTOMRIGHT",
    BOTTOMLEFT = "TOPLEFT",
    BOTTOM = "TOP",
    BOTTOMRIGHT = "TOPRIGHT",
}

-- Grow Direction: the tracker keeps its top edge and grows down, or keeps its
-- bottom edge and grows up.
local function GrowsUp() return TrackerCfg("customGrowUp") == true end

-- Same spot, anchored by the edge the tracker keeps, so a height change grows
-- away from it. A spot on the other edge is that edge of the same area (the
-- width by the max height): both directions fill one box, from opposite
-- ends. Unlock Mode hands back CENTER points; the current size places the edge.
local function Anchored(profile)
    local anchorPoint, rel = profile.point, profile.relPoint or profile.point
    local up = GrowsUp()
    local vy = VY[anchorPoint]
    if vy == (up and 0 or 1) or not (HX[anchorPoint] and HX[rel]) then return profile end
    if OTHER_EDGE[anchorPoint] then
        local maxH = TrackerCfg("customMaxHeight") or DEF_HEIGHT
        return {
            point = OTHER_EDGE[anchorPoint],
            relPoint = rel,
            x = profile.x or 0,
            y = (profile.y or 0) + (up and -maxH or maxH),
        }
    end
    if not widget then return profile end
    local px = UIParent:GetWidth() * HX[rel] + (profile.x or 0)
    local py = UIParent:GetHeight() * VY[rel] + (profile.y or 0)
    local leftX = px - widget:GetWidth() * HX[anchorPoint]
    if up then
        return { point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT", x = leftX, y = py - widget:GetHeight() * vy }
    end
    return { point = "TOPLEFT", relPoint = "BOTTOMLEFT", x = leftX, y = py + widget:GetHeight() * (1 - vy) }
end

-- The saved spot by the edge the tracker keeps: what Unlock Mode reads and
-- places it by at login.
local function GrowSpot() return Anchored(SavedPos()) end

local function PlaceTracker()
    local p = GrowSpot()
    widget:ClearAllPoints()
    widget:SetPoint(p.point, UIParent, p.relPoint or p.point, p.x or 0, p.y or 0)
    -- Linked to another element in Unlock Mode: back onto that link.
    CUI.ReapplyOwnAnchor(UNLOCK_KEY)
    SyncItems()
end

-------------------------------------------------------------------------------
-- Starting place. With no spot saved, the tracker takes the place and size of
-- Blizzard's tracker, which it replaces (muted, but still placed by Edit
-- Mode), so turning it on does not move the quest list. Under the CludesUI
-- look that tracker's background ran from 6 left of it (19 with Blizzard's
-- quest icons shown) to 11 right of it, and began under the master header
-- while that header was hidden; a stock style showed the tracker's own box.
-------------------------------------------------------------------------------
local SKIN_LEFT, SKIN_LEFT_ICONS, SKIN_RIGHT = 6, 19, 11
local SEED_TRIES = 10 -- then the fallback spot stands until the next login
local seedWait = false -- a spot is still to be taken from Blizzard's tracker
local seedTries, seedQueued = 0, false
local worldReady = false -- the first PLAYER_ENTERING_WORLD has come

-- Blizzard's tracker stands where it will stay: the world has loaded (at
-- login the right-side frames are still settling before that) and Edit Mode
-- has placed its systems.
local function BlizzardPlaced()
    local objectiveTracker = _G.ObjectiveTrackerFrame
    return worldReady
        and objectiveTracker ~= nil
        and (not objectiveTracker.IsInitialized or objectiveTracker:IsInitialized())
end

-- Left, top, width and height of that panel in UIParent units; nothing until
-- Edit Mode has placed Blizzard's tracker, or while its rect cannot be read.
local function BlizzardPanel()
    if not BlizzardPlaced() then return end
    local objectiveTracker = _G.ObjectiveTrackerFrame
    local leftX, topY, wid, hgt =
        objectiveTracker:GetLeft(),
        objectiveTracker:GetTop(),
        objectiveTracker:GetWidth(),
        objectiveTracker:GetHeight()
    local scale, ui = objectiveTracker:GetEffectiveScale(), UIParent:GetEffectiveScale()
    if not (leftX and topY and wid and hgt and scale and ui) then return end
    if IsSecret(leftX) or IsSecret(topY) or IsSecret(wid) or IsSecret(hgt) or IsSecret(scale) then return end
    if wid < 1 or hgt < 1 or ui <= 0 then return end
    local s = scale / ui
    if TrackerNS.Blizz() then return leftX * s, topY * s, wid * s, hgt * s end
    local padLeft = TrackerCfg("showQuestIcons") and SKIN_LEFT_ICONS or SKIN_LEFT
    local panelTop = topY
    local headerFrame = objectiveTracker.HeaderMenu or objectiveTracker.Header
    if headerFrame and TrackerNS.ShouldHideMasterHeader() then
        local bottom = headerFrame:GetBottom()
        if bottom and not IsSecret(bottom) and bottom < topY then panelTop = bottom end
    end
    return (leftX - padLeft) * s,
        panelTop * s,
        (wid + padLeft + SKIN_RIGHT) * s,
        (hgt - (topY - panelTop)) * s
end

-- Takes the spot from Blizzard's tracker, and its width and height while ours
-- are still the ones a new profile starts on. False while it has no place.
local function TakeBlizzardSpot()
    local leftX, topY, wid, hgt = BlizzardPanel()
    if not leftX then return false end
    local cfg = TrackerNS.DB()
    if (cfg.customWidth or DEF_WIDTH) == DEF_WIDTH then
        cfg.customWidth = Clamp(math.floor(wid + 0.5), WIDTH_MIN, WIDTH_MAX)
    end
    if (cfg.customMaxHeight or DEF_HEIGHT) == DEF_HEIGHT then
        cfg.customMaxHeight = Clamp(math.floor(hgt + 0.5), HEIGHT_MIN, HEIGHT_MAX)
    end
    -- The panel's top edge; growing up, the bottom edge of the same area.
    cfg.customPos = Anchored({
        point = "TOPLEFT",
        relPoint = "BOTTOMLEFT",
        x = math.floor(leftX + 0.5),
        y = math.floor(topY + 0.5),
    })
    return true
end

-- The profile's spot and width, the spot taken from Blizzard's tracker first
-- when the profile has none. Until that tracker is placed (it is not yet at
-- login) the frame sits at the fallback spot; Edit Mode's layout event, heard
-- only while a spot is still to be taken, moves it once (SeedSoon).
local function PlaceAtSpot()
    local wait = TrackerCfg("customPos") == nil and not TakeBlizzardSpot()
    if wait ~= seedWait then
        seedWait = wait
        if wait then
            seedTries = 0
            eventTag:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
        else
            eventTag:UnregisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
        end
    end
    widget:SetWidth(TrackerCfg("customWidth") or DEF_WIDTH)
    if CUI._unlockActive then
        widget:SetHeight(TrackerCfg("customMaxHeight") or DEF_HEIGHT)
    else
        PlaceTracker()
    end
    Queue()
end

-- Edit Mode has placed its systems, or the world or the quest log has loaded:
-- one more try a frame later, once every handler of that event has run. A
-- placed tracker whose rect still cannot be read stops the tries after a
-- few; the fallback spot then stands until the next login.
local function SeedSoon()
    if not seedWait or seedQueued then return end
    seedQueued = true
    C_Timer.After(0, function()
        seedQueued = false
        if not seedWait then return end
        PlaceAtSpot()
        if seedWait and BlizzardPlaced() then
            seedTries = seedTries + 1
            if seedTries >= SEED_TRIES then
                seedWait = false
                eventTag:UnregisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
            end
        end
    end)
end

local function BuildFrame()
    widget = CreateFrame("Frame", "CUI_CustomQuestTracker", UIParent)
    widget:SetFrameStrata("LOW")
    widget:SetWidth(TrackerCfg("customWidth") or DEF_WIDTH)
    widget:SetHeight(HEADER_H)
    widget:SetClampedToScreen(TrackerCfg("forceOnScreen") == true)
    widget:SetScript("OnShow", function()
        itemLayer:SetAlpha(widget:GetAlpha())
        if stale then
            Draw()
        else
            SyncItems()
        end
    end)
    -- Alpha first: in combat the hide itself waits for combat to end.
    widget:SetScript("OnHide", function()
        itemLayer:SetAlpha(0)
        SyncItems()
        HideOverlay()
    end)
    -- Item buttons sit outside our frame: they follow its alpha (mouseover fade).
    itemLayer = CreateFrame("Frame", nil, UIParent)
    itemLayer:SetFrameStrata("LOW")
    itemLayer:SetFrameLevel(widget:GetFrameLevel() + 20)
    hooksecurefunc(widget, "SetAlpha", function(_, a) itemLayer:SetAlpha(a) end)
    -- Hover modes only: motion (no clicks) so hover sees the cursor over gaps.
    widget:SetMouseClickEnabled(false)
    widget:SetScript("OnEnter", SyncHover)
    widget:SetScript("OnLeave", SyncHover)
    local holderFrame = CreateFrame("Frame", nil, widget)
    holderFrame:SetAllPoints()
    holderFrame:SetFrameLevel(widget:GetFrameLevel())
    holderFrame.fade = holderFrame:CreateAnimationGroup()
    holderFrame.fade:SetToFinalAlpha(true)
    holderFrame.anim = holderFrame.fade:CreateAnimation("Alpha")
    widget.bgHolder = holderFrame
    widget.bg = holderFrame:CreateTexture(nil, "BACKGROUND")
    widget.bg:SetAllPoints()
    widget.topLine = holderFrame:CreateTexture(nil, "BORDER")
    widget.topLine:SetPoint("TOPLEFT")
    widget.topLine:SetPoint("TOPRIGHT")
    widget.topLine:SetHeight(1)

    headerFrame = CreateFrame("Button", nil, widget)
    headerFrame:SetPoint("TOPLEFT")
    headerFrame:SetPoint("TOPRIGHT")
    headerFrame:SetHeight(HEADER_H)
    headerFrame.text = headerFrame:CreateFontString(nil, "OVERLAY")
    headerFrame.text:SetPoint("LEFT", PAD, 0)
    headerFrame.toggle = headerFrame:CreateFontString(nil, "OVERLAY")
    headerFrame.toggle:SetPoint("RIGHT", -PAD, 0)
    headerFrame.count = headerFrame:CreateFontString(nil, "OVERLAY")
    headerFrame.count:SetPoint("RIGHT", headerFrame.toggle, "LEFT", -8, 0)
    headerFrame.count:SetTextColor(1, 1, 1, 0.5)
    headerFrame:SetScript("OnClick", function() ToggleCollapsed("all") end)
    headerFrame:SetScript("OnEnter", SyncHover)
    headerFrame:SetScript("OnLeave", SyncHover)

    scroller = CreateFrame("ScrollFrame", nil, widget)
    scroller:SetPoint("TOPLEFT", PAD, -HEADER_H)
    scroller:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    scroller:SetClipsChildren(true)
    scroller:EnableMouseWheel(true)
    scroller:SetScript(
        "OnMouseWheel",
        function(self, delta) ScrollTo(self:GetVerticalScroll() - delta * WHEEL) end
    )
    childFrame = CreateFrame("Frame", nil, scroller)
    childFrame:SetSize(1, 1)
    scroller:SetScrollChild(childFrame)

    rail = CreateFrame("Frame", nil, widget)
    rail:SetWidth(BAR_W)
    rail:SetPoint("TOPRIGHT", scroller, "TOPRIGHT", 0, 0)
    rail:SetPoint("BOTTOMRIGHT", scroller, "BOTTOMRIGHT", 0, 0)
    rail.bg = rail:CreateTexture(nil, "BACKGROUND")
    rail.bg:SetAllPoints()
    rail.bg:SetColorTexture(1, 1, 1, 0.05)
    rail:Hide()

    -- Draggable thumb; OnUpdate only while dragging.
    knob = CreateFrame("Frame", nil, rail)
    knob:SetWidth(BAR_W)
    knob:EnableMouse(true)
    knob.tex = knob:CreateTexture(nil, "ARTWORK")
    knob.tex:SetAllPoints()
    knob.tex:SetColorTexture(1, 1, 1, 0.3)
    local function OnDrag(self)
        local _, curY = GetCursorPosition()
        local dy = (self.startY - curY) / self:GetEffectiveScale()
        local free = viewH - self:GetHeight()
        if free > 0 then ScrollTo(self.startScroll + dy * MaxScroll() / free) end
    end
    knob:SetScript("OnMouseDown", function(self)
        local _, curY = GetCursorPosition()
        self.startY, self.startScroll = curY, scroller:GetVerticalScroll()
        self:SetScript("OnUpdate", OnDrag)
    end)
    knob:SetScript("OnMouseUp", function(self)
        self:SetScript("OnUpdate", nil)
        SyncHover()
    end)

    PlaceAtSpot()
    ApplyBackground()
    RefreshFonts()
end

-------------------------------------------------------------------------------
-- Visibility: the module's visibility rules, raid / arena auto-hide and
-- cross-module suppression, on our own frame.
-------------------------------------------------------------------------------
local function AutoHidden()
    local _, instanceType = IsInInstance()
    if instanceType == "arena" then return true end
    if instanceType == "raid" then
        local mode = TrackerCfg("hideInRaidMode")
        return mode == "always" or (mode ~= "never" and inEncounter)
    end
    return false
end

-- Visibility options that cannot change during a fight.
local FIGHT_STATIC = {
    visOnlyInstances = true,
    visHideInstances = true,
    visOnlyDungeons = true,
    visHideDungeons = true,
    visOnlyHousing = true,
    visHideHousing = true,
    visOnlyResting = true,
    visHideResting = true,
}

-- The tracker can hide mid-fight: Hide When In Raid (unless Never), a combat or
-- group rule, or any other visibility option (target, mounted, vehicle, Party Mode).
local function CanHideInCombat()
    local _, instanceType = IsInInstance()
    if instanceType == "raid" and TrackerCfg("hideInRaidMode") ~= "never" then return true end
    local saved = TrackerNS.DB()
    if CUI.VisDependsOnCombat(saved, "visibility") then return true end
    local sel = CUI.GetVisibilitySelection(saved, "visibility")
    if sel.in_raid or sel.in_party or sel.solo then return true end
    for _, k in ipairs(CUI.VIS_OPT_KEYS) do
        if saved[k] and not FIGHT_STATIC[k] then return true end
    end
    return false
end

local function Blocked() return TrackerCfg("enabled") == false or TrackerNS.IsSuppressed() or AutoHidden() end

local function SyncShown()
    if not widget then return end
    local vis = not Blocked() and CUI.EvalVisibility(TrackerNS.DB())
    if not vis then
        widget:Hide()
        return
    end
    widget:Show()
    widget:SetAlpha(vis == "mouseover" and 0 or 1)
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------
local EVENTS = {
    "QUEST_LOG_UPDATE",
    "QUEST_WATCH_LIST_CHANGED",
    "QUEST_ACCEPTED",
    "QUEST_REMOVED",
    "SUPER_TRACKING_CHANGED",
    "ZONE_CHANGED",
    "ZONE_CHANGED_NEW_AREA",
    "PLAYER_ENTERING_WORLD",
    "PLAYER_LEVEL_UP",
    "ENCOUNTER_START",
    "ENCOUNTER_END",
    "PLAYER_REGEN_DISABLED",
    "TRACKED_RECIPE_UPDATE",
}

eventTag:SetScript("OnEvent", function(_, eventName, questId, added)
    if eventName == "PLAYER_REGEN_DISABLED" then
        -- InCombatLockdown() is already true here, but protected writes stay
        -- legal until this handler returns: last chance to hide secure buttons,
        -- which would otherwise stay clickable on a hidden tracker.
        if overlayFrame then overlayFrame:Hide() end
        if CanHideInCombat() then
            for _, b in ipairs(itemList) do
                b:Hide()
            end
            mod.CombatQueue.Defer("EQT_CustomItems", SyncItems)
        end
        return
    elseif eventName == "BAG_UPDATE_COOLDOWN" then
        for _, b in ipairs(itemList) do
            if b:IsShown() then UpdateItemCooldown(b) end
        end
        return
    elseif eventName == "EDIT_MODE_LAYOUTS_UPDATED" then
        SeedSoon()
        return
    elseif eventName == "ITEM_DATA_LOAD_RESULT" then
        -- A reagent name the recipe list asked for (questID is the item here,
        -- added whether it loaded); any other item load is not ours.
        if not nameAsked[questId] then return end
        if not added then nameAsked[questId] = false end
    elseif eventName == "TRACKED_RECIPE_UPDATE" then
        wipe(schematics)
    elseif eventName == "QUEST_WATCH_LIST_CHANGED" then
        -- Tracking it again in the quest log brings it back.
        if questId and added then CharStore().ctUntracked[questId] = nil end
    elseif eventName == "QUEST_REMOVED" and questId then
        local saved = CharStore()
        saved.ctUntracked[questId] = nil
        saved.ctCollapsed[questId] = nil
        saved.ctDoneOpen[questId] = nil
        saved.ctPinned[questId] = nil
        prevObj[questId] = nil
    elseif
        eventName == "ENCOUNTER_START"
        or eventName == "ENCOUNTER_END"
        or eventName == "PLAYER_ENTERING_WORLD"
    then
        if eventName == "PLAYER_ENTERING_WORLD" then worldReady = true end
        inEncounter = eventName == "ENCOUNTER_START"
        SyncShown()
    end
    if seedWait then SeedSoon() end
    Queue()
end)

-------------------------------------------------------------------------------
-- Entry point (loader, custom mode only). Takes over the EQT entry points the
-- options page and profile refresh call, so none of them reach Blizzard's
-- tracker.
-------------------------------------------------------------------------------
local function Noop() end

function TrackerNS.InitCustom()
    TrackerNS.MuteBlizzardTracker()
    BuildFrame()

    TrackerNS.UpdateVisibility = SyncShown
    TrackerNS.RefreshStateDriver = SyncShown
    TrackerNS.ApplyBackground = ApplyBackground
    TrackerNS.RefreshFonts = RefreshFonts
    TrackerNS.RestyleAll = function()
        ApplyBackground()
        RefreshFonts()
    end
    TrackerNS.ApplyForceOnScreen = function() widget:SetClampedToScreen(TrackerCfg("forceOnScreen") == true) end
    TrackerNS.ApplyMasterHeaderVisibility = Noop
    TrackerNS.QueueResize = Noop
    TrackerNS.ResizeBGToContent = Noop
    -- Profile swap, and the options page's Width and Max Height: the
    -- profile's width, height and spot.
    TrackerNS.SyncPosition = PlaceAtSpot

    for _, event in ipairs(EVENTS) do
        eventTag:RegisterEvent(event)
    end
    CUI.RegisterVisibilityUpdater(SyncShown)
    CUI.RegisterMouseoverTarget(
        widget,
        function() return not Blocked() and CUI.VisWantsMouseover(TrackerNS.DB(), "visibility") end
    )
    CUI.RegAccent({ type = "callback", fn = TrackerNS.RestyleAll })

    -- Unlock Mode keeps the edge the tracker grows away from: its own answer
    -- in place of the one Blizzard's tracker has under this key.
    CUI.GetQuestTrackerGrowDir = function() return GrowsUp() and "UP" or "DOWN" end

    CUI:RegisterUnlockElements({
        CUI.MakeUnlockElement({
            key = UNLOCK_KEY,
            label = "Quest Tracker",
            group = "Quest Tracker",
            order = 560,
            getFrame = function() return widget end,
            isHidden = function() return not TrackerCfg("enabled") end,
            -- One spot for every spec, like Blizzard's tracker under this key.
            noSpecLayout = true,
            -- Width, and the height the tracker may grow to: in Unlock Mode the
            -- frame fills that whole area (Render), so the mover outlines it.
            getSize = function()
                return TrackerCfg("customWidth") or DEF_WIDTH, TrackerCfg("customMaxHeight") or DEF_HEIGHT
            end,
            -- Unlock Mode also calls these with no size, to lay the element out again.
            setWidth = function(_, wid)
                if wid then
                    TrackerNS.Set("customWidth", Clamp(math.floor(wid + 0.5), WIDTH_MIN, WIDTH_MAX))
                end
                widget:SetWidth(TrackerCfg("customWidth") or DEF_WIDTH)
                Queue()
            end,
            setHeight = function(_, hgt)
                if hgt then
                    TrackerNS.Set("customMaxHeight", Clamp(math.floor(hgt + 0.5), HEIGHT_MIN, HEIGHT_MAX))
                end
                if CUI._unlockActive then
                    widget:SetHeight(TrackerCfg("customMaxHeight") or DEF_HEIGHT)
                end
                Queue()
            end,
            savePos = function(_, anchorPoint, relPoint, posX, posY)
                if not anchorPoint then return end
                TrackerNS.Set(
                    "customPos",
                    Anchored({ point = anchorPoint, relPoint = relPoint, x = posX, y = posY })
                )
                if not CUI._unlockActive then PlaceTracker() end
            end,
            loadPos = GrowSpot,
            -- Back to its starting place: where Blizzard's tracker sits.
            clearPos = function()
                TrackerNS.Set("customPos", nil)
                PlaceAtSpot()
                PlaceTracker()
            end,
            applyPos = PlaceTracker,
        }),
    }, "CludesUIQuestTracker")

    -- Unlock Mode outlines the whole area the tracker may fill; a closed
    -- session takes it back to the height of its quests. A drag leaves the
    -- frame on Unlock Mode's own anchor, so it first goes back onto the edge
    -- it keeps.
    CUI:RegisterUnlockModeListener("CludesUIQuestTracker", function(isActive)
        if isActive then
            widget:SetHeight(TrackerCfg("customMaxHeight") or DEF_HEIGHT)
        else
            PlaceTracker()
        end
        Draw()
    end)

    SyncShown()
    Queue()
end

-- The options page's sliders: the width and height a user can set.
function TrackerNS.CustomSizeRange() return WIDTH_MIN, WIDTH_MAX, HEIGHT_MIN, HEIGHT_MAX end

-- The options page's Grow Direction. The saved spot moves to the other edge
-- of the same area, so the tracker fills the box it had from its other end,
-- and a later Max Height change leaves the edge it keeps where it is.
function TrackerNS.SetCustomGrowUp(up)
    up = up and true or false
    if GrowsUp() == up then return end
    TrackerNS.Set("customGrowUp", up)
    local p = TrackerCfg("customPos")
    if p and p.point then TrackerNS.Set("customPos", Anchored(p)) end
    if widget then PlaceAtSpot() end
end
