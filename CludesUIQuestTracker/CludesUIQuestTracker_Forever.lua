if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
if not CUI.IS_FOREVER then return end
-------------------------------------------------------------------------------
--  CludesUIQuestTracker_Forever.lua - WoW Forever's quest tools.
--
--  Sorting, filters and zone auto-track (behind the Experimental Quest Tools
--  switch on Blizzard's tracker; always available on ours), objective
--  progress colours, completion sounds and party progress messages. None of
--  it exists on retail: the file stops above, and the loader, skin and
--  options reach it only through EQT fields that are nil there.
-------------------------------------------------------------------------------
local _, mod = ...
local TrackerNS = mod.EQT
local Cfg = TrackerNS.Cfg

-- The progress colour stops: the defaults, the paint's fallbacks and the
-- options' swatches all read this.
local OBJ_STOPS = {
    Start = { 1.0, 0.4, 0.4 },
    Mid = { 1.0, 1.0, 0.4 },
    End = { 0.4, 1.0, 0.4 },
}
TrackerNS.OBJ_STOPS = OBJ_STOPS

-- Defaults, added to the module's table before its database is made at login.
do
    local trackerCfg = mod.QT_DEFAULTS.profile.questTracker
    trackerCfg.questWatchExperimental = false -- unlocks sorting, filters and auto-track
    -- Sorting: Quest Log Order unless another mode is picked; "mixed" leaves
    -- completed quests where the mode puts them.
    trackerCfg.questSortMode = "log"
    trackerCfg.questSortCompleted = "mixed"
    trackerCfg.questSortThenBy = "none"
    -- Filters untrack matching quests and track them again when they pass;
    -- Filter Quests switches the choices below on and off together.
    trackerCfg.filterEnabled = false
    trackerCfg.filterZone = true
    trackerCfg.filterCompleted = false
    trackerCfg.filterTrivial = false
    trackerCfg.filterRepeatable = false
    trackerCfg.filterHeaderToggle = false
    trackerCfg.autoTrackZone = false -- tracks quests listed under the current zone or dungeon
    -- Progress: alert sound keys ("none" = off), party messages.
    trackerCfg.soundObjective = "none"
    trackerCfg.soundQuest = "none"
    trackerCfg.announceProgress = false
    -- Objective line colours (CludesUI style only).
    trackerCfg.objProgressColor = false
    trackerCfg.objDimCompleted = false
    trackerCfg.objDimAlpha = 45
    for name, c in pairs(OBJ_STOPS) do
        trackerCfg["obj" .. name .. "R"], trackerCfg["obj" .. name .. "G"], trackerCfg["obj" .. name .. "B"] =
            c[1], c[2], c[3]
    end
end

-------------------------------------------------------------------------------
--  Sorting, filters and auto-track. Blizzard's tracker lists watched quests in
--  watch order, so editing the watch list sorts and filters it without
--  touching the tracker. Blizzard's distance sort on zone changes is off
--  while the tools are on, and turning them off puts the watch list back in
--  quest log order once. The frame is made on first use and sleeps while
--  everything is off.
-------------------------------------------------------------------------------
local watchList
local passQueued = false
local sortRefused = false -- the last re-order did not take (see ApplySort)
local restoreOrder = false -- the tools were turned off: the next pass restores log order
local sortWasOn = false
local awaitingLog = false -- a QUEST_WATCH_UPDATE waits for its QUEST_LOG_UPDATE
local dungeonPass = false -- one pass on entering a dungeon (see CanEditWatches)
local ourEdit = false -- inside our own watch edit: its events are ours
local sortIDs, sortGroup, sortKey, sortKey2, sortRank = {}, {}, {}, {}, {}
local isWatched = {}
local changedQuests, wasComplete = {}, {} -- the QUEST_WATCH_UPDATE probe

-- The pass's quest log snapshot: one GetInfo per entry per pass.
local logList = {} -- every entry, in log order
local logInfo, logHeader, logZone, logIndex = {}, {}, {}, {} -- by questID
local passZone, instancePass, passInstance

-- Our tracker (Custom.lua) sorts, filters and auto-tracks its own list with
-- no watch edits, so it needs no experimental switch.
local function ToolsOn() return mod.UseCustomTracker() or Cfg("questWatchExperimental") == true end
-- Quest Log Order is the base mode (a saved "default", the retired Blizzard
-- order mode, reads as it).
local function SortMode()
    local mode = Cfg("questSortMode")
    return (mode == nil or mode == "default") and "log" or mode
end
local function SortCompleted() return Cfg("questSortCompleted") or "mixed" end
-- The second key; none when the first is already unique per quest.
local function SortThenBy()
    if SortMode() == "log" then return "none" end
    return Cfg("questSortThenBy") or "none"
end
-- The tools keep the watch list sorted while they are on.
local SortOn = ToolsOn
local function SortUses(key) return SortMode() == key or SortThenBy() == key end

-- A filter counts only while Filter Quests is on.
local function Filter(key) return ToolsOn() and Cfg("filterEnabled") and Cfg(key) end
local function FilterOn()
    return Filter("filterZone")
        or Filter("filterCompleted")
        or Filter("filterTrivial")
        or Filter("filterRepeatable")
end
local function AutoOn() return ToolsOn() and Cfg("autoTrackZone") end

-- Per character (watch lists are per character; profiles may be shared), in
-- the account database: hidden = untracked by a filter, exempt = tracked
-- again by the player, auto = tracked by auto-track, declined = auto-tracked
-- then untracked by the player (left alone until they leave the area).
local CHAR_SETS = { "hidden", "exempt", "auto", "declined" }
local charSets
local function CharSets()
    if charSets then return charSets end
    CludesUIDB = CludesUIDB or {}
    local all = CludesUIDB.questWatchChars
    if type(all) ~= "table" then
        all = {}
        CludesUIDB.questWatchChars = all
    end
    local guid = UnitGUID("player")
    local mine = all[guid]
    if type(mine) ~= "table" then
        mine = {}
        all[guid] = mine
    end
    for _, k in ipairs(CHAR_SETS) do
        if type(mine[k]) ~= "table" then mine[k] = {} end
    end
    charSets = mine
    return mine
end

-- Whether a feature turned off left quests to give back. Reads only.
local function HasLeftovers()
    local all = CludesUIDB and CludesUIDB.questWatchChars
    local mine = type(all) == "table" and all[UnitGUID("player")]
    if type(mine) ~= "table" then return false end
    for _, k in ipairs(CHAR_SETS) do
        if type(mine[k]) == "table" and next(mine[k]) ~= nil then return true end
    end
    return false
end

local function WatchesActive() return SortOn() or FilterOn() or AutoOn() or HasLeftovers() end

local function ReadWatched()
    wipe(isWatched)
    for i = 1, C_QuestLog.GetNumQuestWatches() do
        local questId = C_QuestLog.GetQuestIDForQuestWatchIndex(i)
        if questId then isWatched[questId] = true end
    end
end

local function Snapshot()
    wipe(logList)
    wipe(logInfo)
    wipe(logHeader)
    wipe(logZone)
    wipe(logIndex)
    passZone = GetRealZoneText()
    instancePass = IsInInstance()
    passInstance = instancePass and GetInstanceInfo() or nil
    local headerFrame, headerIndex = nil, 0
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local questInfo = C_QuestLog.GetInfo(i)
        if questInfo then
            logList[#logList + 1] = questInfo
            if questInfo.isHeader then
                headerFrame, headerIndex = questInfo.title, i
            elseif questInfo.questID then
                local id = questInfo.questID
                logInfo[id], logHeader[id], logZone[id], logIndex[id] = questInfo, headerFrame, headerIndex, i
            end
        end
    end
end

-- "The current area": the quest log header names the zone the player is in,
-- or the instance (exact names: a city is its own zone, so Orgrimmar is not
-- Durotar). Quests under a class or profession header name no zone, so in
-- the open world a quest with objectives on the current map counts too;
-- inside an instance that flag also takes in the parent zone's quests, so
-- only the header decides there.
local function InArea(questInfo, headerFrame)
    if headerFrame and (headerFrame == passZone or (instancePass and headerFrame == passInstance)) then
        return true
    end
    return not instancePass and questInfo.isOnMap == true
end

-- Whether a filter takes the quest off (never the super-tracked one).
local function Filtered(questId, superID)
    if questId == superID then return false end
    local questInfo = logInfo[questId]
    if not questInfo then return false end
    if Filter("filterCompleted") and C_QuestLog.IsComplete(questId) then return true end
    if Filter("filterTrivial") and C_QuestLog.IsQuestTrivial(questId) then return true end
    if
        Filter("filterRepeatable")
        and questInfo.frequency
        and questInfo.frequency ~= Enum.QuestFrequency.Default
    then
        return true
    end
    return Filter("filterZone") and not InArea(questInfo, logHeader[questId]) or false
end

-- Our own watch edits (QUEST_WATCH_LIST_CHANGED fires inside the call).
local function Watch(questId)
    ourEdit = true
    C_QuestLog.AddQuestWatch(questId)
    ourEdit = false
end
local function Unwatch(questId)
    ourEdit = true
    C_QuestLog.RemoveQuestWatch(questId)
    ourEdit = false
end

local function ApplyFilter()
    local sets = CharSets()
    local isHidden, exempt = sets.hidden, sets.exempt
    local isOn = FilterOn()
    local superID = C_SuperTrack.GetSuperTrackedQuestID()
    ReadWatched()
    -- An exemption ends when the player untracks the quest.
    for questId in pairs(exempt) do
        if not isOn or not isWatched[questId] then exempt[questId] = nil end
    end
    for questId in pairs(isHidden) do
        -- IsOnQuest, not a log index: collapsed headers and loading screens hide indexes.
        if not C_QuestLog.IsOnQuest(questId) then
            isHidden[questId] = nil
        elseif isWatched[questId] then
            -- The player tracked it again: it stays tracked.
            isHidden[questId] = nil
            if isOn and Filtered(questId, superID) then exempt[questId] = true end
        elseif not isOn or not Filtered(questId, superID) then
            isHidden[questId] = nil
            Watch(questId)
        end
    end
    if not isOn then return end
    for questId in pairs(isWatched) do
        if not exempt[questId] and Filtered(questId, superID) then
            isHidden[questId] = true
            sets.auto[questId] = nil
            Unwatch(questId)
        end
    end
end

-- Tracks quests in the current area (see InArea), and untracks them again on leaving.
local function ApplyAutoTrack()
    local sets = CharSets()
    local isHidden, autoMode, declined = sets.hidden, sets.auto, sets.declined
    local isOn = AutoOn()
    if not isOn and next(autoMode) == nil and next(declined) == nil then return end
    local superID = C_SuperTrack.GetSuperTrackedQuestID()
    ReadWatched()
    -- One we tracked that the player untracked: declined.
    for questId in pairs(autoMode) do
        if not isWatched[questId] then
            autoMode[questId] = nil
            declined[questId] = true
        end
    end
    local room = Constants.QuestWatchConsts.MAX_QUEST_WATCHES - C_QuestLog.GetNumQuestWatches()
    local headerFrame
    for _, questInfo in ipairs(logList) do
        if questInfo.isHeader then
            headerFrame = questInfo.title
        elseif not questInfo.isHidden and not questInfo.isTask and not questInfo.isBounty then
            local questId = questInfo.questID
            if isOn and InArea(questInfo, headerFrame) then
                if
                    room > 0
                    and not isWatched[questId]
                    and not declined[questId]
                    and not isHidden[questId]
                    and not Filtered(questId, superID)
                then
                    autoMode[questId] = true
                    room = room - 1
                    Watch(questId)
                end
            else
                declined[questId] = nil
                if autoMode[questId] then
                    autoMode[questId] = nil
                    Unwatch(questId)
                end
            end
        end
    end
    -- Quests that left the log.
    for questId in pairs(autoMode) do
        if not C_QuestLog.IsOnQuest(questId) then autoMode[questId] = nil end
    end
    for questId in pairs(declined) do
        if not isOn or not C_QuestLog.IsOnQuest(questId) then declined[questId] = nil end
    end
end

local function Before(a, b)
    if sortGroup[a] ~= sortGroup[b] then
        return sortGroup[a] < sortGroup[b]
    elseif sortKey[a] ~= sortKey[b] then
        return sortKey[a] < sortKey[b]
    elseif sortKey2[a] ~= sortKey2[b] then
        return sortKey2[a] < sortKey2[b]
    end
    return sortRank[a] < sortRank[b]
end

-- Lower sorts first. Recurring = dailies and weeklies.
local QC = Enum.QuestClassification
local TYPE_RANK = {
    [QC.Campaign] = 1,
    [QC.Legendary] = 2,
    [QC.Important] = 3,
    [QC.Meta] = 4,
    [QC.Questline] = 5,
    [QC.Normal] = 6,
    [QC.Recurring] = 7,
}

-- Most complete first: minus the share of all objective counts done.
local function ProgressKey(questId)
    if C_QuestLog.IsComplete(questId) then return -1 end
    local have, need = 0, 0
    for _, o in ipairs(C_QuestLog.GetQuestObjectives(questId) or {}) do
        local required = o.numRequired
        if type(required) == "number" and required > 0 then
            have, need = have + math.min(o.numFulfilled or 0, required), need + required
        end
    end
    return need > 0 and -(have / need) or 0
end

local SORT_KEYS = {
    zone = function(id) return logZone[id] or 0 end,
    progress = ProgressKey,
    type = function(id)
        local questInfo = logInfo[id]
        if not questInfo then return 6 end
        local rank = TYPE_RANK[questInfo.questClassification] or 6
        if rank == 6 and questInfo.frequency and questInfo.frequency ~= Enum.QuestFrequency.Default then
            rank = 7
        end
        return rank
    end,
    log = function(id) return logIndex[id] or 0 end,
    level = function(id)
        local questInfo = logInfo[id]
        return questInfo and (questInfo.difficultyLevel or questInfo.level) or 0
    end,
    name = function(id)
        local questInfo = logInfo[id]
        return questInfo and questInfo.title and questInfo.title:lower() or ""
    end,
    none = function() return 0 end,
}

-- An unknown mode keeps the list's own order.
local function KeyFor(mode, questId, rank)
    local fn = SORT_KEYS[mode]
    if fn then return fn(questId) end
    return rank
end

-- Sorts a quest ID list in place (its order is the tie-break). Reads the pass's snapshot.
local function SortList(ids, mode, isCompleted, thenBy)
    wipe(sortGroup)
    wipe(sortKey)
    wipe(sortKey2)
    wipe(sortRank)
    for i, questId in ipairs(ids) do
        sortRank[questId] = i
        local group = 1
        if isCompleted ~= "mixed" then
            local done = C_QuestLog.IsComplete(questId) == true
            group = ((isCompleted == "top") == done) and 1 or 2
        end
        sortGroup[questId] = group
        sortKey[questId] = KeyFor(mode, questId, i)
        sortKey2[questId] = KeyFor(thenBy, questId, i)
    end
    table.sort(ids, Before)
end

-- Re-orders the watch list: the settings' choices, or the restore pass's
-- plain quest log order.
local function ApplySort(mode, isCompleted, thenBy)
    local total = 0
    for i = 1, C_QuestLog.GetNumQuestWatches() do
        local questId = C_QuestLog.GetQuestIDForQuestWatchIndex(i)
        if questId then
            total = total + 1
            sortIDs[total] = questId
        end
    end
    for i = #sortIDs, total + 1, -1 do
        sortIDs[i] = nil
    end
    SortList(sortIDs, mode, isCompleted, thenBy)

    -- AddQuestWatch inserts at the top, so the head that is out of place is
    -- added again from the bottom up; the tail already in place stays.
    local last
    for i = total, 1, -1 do
        if sortRank[sortIDs[i]] ~= i then
            last = i
            break
        end
    end
    if not last then
        sortRefused = false
        return
    end
    -- The last re-order did not produce its order: skip one pass, so an
    -- order the game will not take cannot loop.
    if sortRefused then
        sortRefused = false
        return
    end
    -- The super-track is not restored here: setting it from addon code taints the map.
    for i = last, 1, -1 do
        Unwatch(sortIDs[i])
        Watch(sortIDs[i])
    end
    -- Read the order back; the guard arms only if it did not take.
    local count = 0
    for i = 1, C_QuestLog.GetNumQuestWatches() do
        local questId = C_QuestLog.GetQuestIDForQuestWatchIndex(i)
        if questId then
            count = count + 1
            if questId ~= sortIDs[count] then
                sortRefused = true
                return
            end
        end
    end
end

-- For our tracker, which reads only: one snapshot per pass, then area,
-- filters and sorting against it. No watch edits.
function TrackerNS.QuestLogSnapshot()
    Snapshot()
    return logList, logHeader
end
TrackerNS.QuestInArea = InArea
function TrackerNS.IsQuestFiltered(questId)
    return FilterOn() and Filtered(questId, C_SuperTrack.GetSuperTrackedQuestID())
end
function TrackerNS.AutoTrackOn() return AutoOn() end
function TrackerNS.SortQuestList(ids) SortList(ids, SortMode(), SortCompleted(), SortThenBy()) end

-- A watch edit fires QUEST_WATCH_LIST_CHANGED at once, so Blizzard's tracker,
-- quest log and super-track handlers run under our taint (and the tracker
-- update they schedule). Under aura restrictions that update can error in
-- the scenario tracker, so edits happen out of combat and encounters, never
-- with the map open (its quest pins would rebuild tainted too), and in the
-- open world. The one instance edit is the pass on entering a 5-player
-- dungeon (out of combat, from its loading screen), which brings its quests
-- back for Current Zone Only and auto-track; leaving an instance (a loading
-- screen and zone events) runs a pass again.
local function MapOpen() return WorldMapFrame ~= nil and WorldMapFrame:IsShown() end

local function CanEditWatches()
    if IsInInstance() and not dungeonPass then return false end
    if MapOpen() or InCombatLockdown() then return false end
    return not (C_InstanceEncounter and C_InstanceEncounter.IsEncounterInProgress())
end

local QueueWatches -- below; the map callback needs it
local waitingForMap = false

-- Again when the map closes. EventRegistry calls through
-- securecallfunction, so this stays out of the map's chain; it unhooks
-- itself once it has run.
local function MapClosed()
    EventRegistry:UnregisterCallback("WorldMapOnHide", TrackerNS)
    if waitingForMap then
        waitingForMap = false
        QueueWatches()
    end
end

local function WatchPass()
    passQueued = false
    ourEdit = false
    if not CanEditWatches() then
        dungeonPass = false
        if MapOpen() and not waitingForMap then
            waitingForMap = true
            EventRegistry:RegisterCallback("WorldMapOnHide", MapClosed, TrackerNS)
        end
        -- Combat or an open-world encounter: again when it ends. Instances
        -- wait for the zone events on the way out.
        if not IsInInstance() then
            if InCombatLockdown() then mod.CombatQueue.Defer("QuestWatches", QueueWatches) end
            watchList:RegisterEvent("ENCOUNTER_END")
        end
        return
    end
    dungeonPass = false
    watchList:UnregisterEvent("ENCOUNTER_END")
    -- The log is not loaded yet (a loading screen): nothing to go on.
    if C_QuestLog.GetNumQuestLogEntries() == 0 then return end
    Snapshot()
    ApplyFilter()
    ApplyAutoTrack()
    -- The tools were turned off: back to quest log order once, after the
    -- filter and auto-track have given their quests back.
    if restoreOrder then
        restoreOrder = false
        ApplySort("log", "mixed", "none")
    end
    if SortOn() then ApplySort(SortMode(), SortCompleted(), SortThenBy()) end
    -- The last pass after everything was turned off: the frame sleeps.
    if not WatchesActive() then watchList:UnregisterAllEvents() end
end

function QueueWatches()
    if not passQueued then
        passQueued = true
        C_Timer.After(0, WatchPass)
    end
end

-- QUEST_WATCH_UPDATE fires before the log has the new counts, so the probe
-- waits for the QUEST_LOG_UPDATE after it, and a pass runs only when a quest
-- turned complete or back (or Progress sorts the list).
local function OnWatchEvent(_, eventName, arg)
    if eventName == "QUEST_WATCH_LIST_CHANGED" then
        if not ourEdit then QueueWatches() end
    elseif eventName == "QUEST_WATCH_UPDATE" then
        if arg then changedQuests[arg] = true end
        awaitingLog = true
    elseif eventName == "QUEST_LOG_UPDATE" then
        if not awaitingLog then return end
        awaitingLog = false
        local need = SortUses("progress")
        for questId in pairs(changedQuests) do
            changedQuests[questId] = nil
            local done = C_QuestLog.IsComplete(questId) == true
            local was = wasComplete[questId]
            wasComplete[questId] = done
            if was ~= done and (was ~= nil or done) then need = true end
        end
        if need then QueueWatches() end
    elseif eventName == "PLAYER_ENTERING_WORLD" then
        local inInstance, kind = IsInInstance()
        dungeonPass = inInstance and kind == "party"
        QueueWatches()
    else
        QueueWatches()
    end
end

-- These two events only drive Blizzard's distance sort on the tracker
-- (ObjectiveTrackerFrameMixin:OnEvent), so while the tools keep the watch
-- list sorted they are off rather than fighting it.
local blizzardSortOff = false
local BLIZZARD_SORT_EVENTS = { "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA" }
local function ApplyBlizzardSort()
    local otf = _G.ObjectiveTrackerFrame
    if not otf then return end
    local off = SortOn()
    if off == blizzardSortOff then return end
    blizzardSortOff = off
    for _, eventName in ipairs(BLIZZARD_SORT_EVENTS) do
        if off then
            otf:UnregisterEvent(eventName)
        else
            otf:RegisterEvent(eventName)
        end
    end
end

-- The Filter Quests button on the Quests header, left of its minimize
-- button. Made on first use; the skin tints it and switches its mouse off
-- with the tracker's (EQT.FilterToggle).
local function FilterTip() return Cfg("filterEnabled") and "Quest Filters On" or "Quest Filters Off" end

local function MakeFilterButton()
    local trackerCfg = _G.QuestObjectiveTracker
    local headerFrame = trackerCfg and trackerCfg.Header
    local minimize = headerFrame and headerFrame.MinimizeButton
    if not minimize then return nil end
    local button = CreateFrame("Button", nil, headerFrame)
    button:SetSize(minimize:GetSize())
    button:SetPoint("RIGHT", minimize, "LEFT", -2, 0)
    -- Above the minimize button's header-wide click area (SkinHeader).
    button:SetFrameLevel(minimize:GetFrameLevel() + 1)
    button:SetNormalAtlas("ui-questtrackerbutton-filter")
    button:SetPushedAtlas("ui-questtrackerbutton-filter-pressed")
    button:SetHighlightAtlas("ui-questtrackerbutton-red-highlight", "ADD")
    button:SetScript("OnEnter", function(self) CUI.ShowWidgetTooltip(self, FilterTip()) end)
    button:SetScript("OnLeave", function() CUI.HideWidgetTooltip() end)
    button:SetScript("OnClick", function(self)
        TrackerNS.Set("filterEnabled", not Cfg("filterEnabled"))
        TrackerNS.ApplyQuestWatches()
        CUI:RefreshPage()
        CUI.ShowWidgetTooltip(self, FilterTip())
    end)
    TrackerNS.FilterToggle = button
    TrackerNS.SkinHeader(headerFrame)
    if TrackerNS._trackerMouseOff then TrackerNS.MouseOff(button) end
    return button
end

local function ApplyFilterButton()
    local wanted = ToolsOn() and Cfg("filterHeaderToggle") == true
    local button = TrackerNS.FilterToggle
    if not button then
        if not wanted then return end
        button = MakeFilterButton()
        if not button then return end
    end
    button:SetShown(wanted)
    button:SetAlpha(Cfg("filterEnabled") and 1 or 0.4)
end

-- The options' and profile switch's entry point.
function TrackerNS.ApplyQuestWatches()
    -- Our tracker keeps its own list; the watch list is left alone.
    if mod.UseCustomTracker() then
        if TrackerNS.RefreshCustom then TrackerNS.RefreshCustom() end
        return
    end
    ApplyBlizzardSort()
    ApplyFilterButton()
    -- The tools turned off (or a profile without them): the next pass
    -- restores quest log order.
    local sortOn = SortOn()
    if sortWasOn and not sortOn then restoreOrder = true end
    sortWasOn = sortOn
    if sortOn then restoreOrder = false end
    local active = WatchesActive()
    if not watchList then
        if not (active or restoreOrder) then return end
        watchList = CreateFrame("Frame")
        watchList:SetScript("OnEvent", OnWatchEvent)
    end
    watchList:UnregisterAllEvents()
    sortRefused, awaitingLog, dungeonPass = false, false, false
    wipe(changedQuests)
    if not active then
        -- The restore pass puts the frame to sleep once it has run.
        if restoreOrder then QueueWatches() end
        return
    end
    local zoneBased = Filter("filterZone") or AutoOn()
    watchList:RegisterEvent("QUEST_WATCH_LIST_CHANGED")
    -- The current area changes on these, and entering or leaving an instance
    -- ends on a loading screen.
    if zoneBased then
        watchList:RegisterEvent("ZONE_CHANGED")
        watchList:RegisterEvent("ZONE_CHANGED_NEW_AREA")
        watchList:RegisterEvent("PLAYER_ENTERING_WORLD")
    end
    -- Objective progress can make a quest complete.
    if (sortOn and (SortCompleted() ~= "mixed" or SortUses("progress"))) or Filter("filterCompleted") then
        watchList:RegisterEvent("QUEST_WATCH_UPDATE")
        watchList:RegisterEvent("QUEST_LOG_UPDATE")
    end
    -- Quests turn trivial as the player levels.
    if Filter("filterTrivial") then watchList:RegisterEvent("PLAYER_LEVEL_UP") end
    -- Blizzard does not always watch a new quest.
    if AutoOn() then watchList:RegisterEvent("QUEST_ACCEPTED") end
    QueueWatches()
end

-------------------------------------------------------------------------------
--  Progress: completion sounds and party messages. Objective counts are kept
--  per quest; QUEST_WATCH_UPDATE marks a quest and the QUEST_LOG_UPDATE after
--  it (when the new counts can be read) compares. The frame is made on first
--  use and sleeps while both are off.
-------------------------------------------------------------------------------
local progressFrame
local counts = {} -- questID -> { [objective] = numFulfilled, done = bool }
local marked = {}
local seedWaiting = false

-- The Warcraft III peon lines in the game files (sound/creature/peon). These
-- are FileDataIDs, not SoundKit IDs, so PlaySoundKey plays them as files.
local PEON_SOUNDS = {
    { "peoncomplete", "Peon: Work Complete", 558132 },
    { "peonready", "Peon: Ready to Work", 558137 },
    { "peonyes1", "Peon: Yes 1", 558136 },
    { "peonyes2", "Peon: Yes 2", 558139 },
    { "peonyes3", "Peon: Yes 3", 558147 },
    { "peonyes4", "Peon: Yes 4", 558140 },
    { "peonwhat1", "Peon: What 1", 558141 },
    { "peonwhat2", "Peon: What 2", 558134 },
    { "peonwhat3", "Peon: What 3", 558143 },
    { "peonwhat4", "Peon: What 4", 558135 },
    { "peonpissed1", "Peon: Annoyed 1", 558133 },
    { "peonpissed2", "Peon: Annoyed 2", 558144 },
    { "peonpissed3", "Peon: Annoyed 3", 558142 },
    { "peonpissed4", "Peon: Annoyed 4", 558146 },
}
local isFile = {}

local soundFiles
function TrackerNS.Sounds()
    if not soundFiles then
        local names, order
        soundFiles, names, order = CUI.BuildAlertSoundTables()
        -- After the bundled sounds, before the media library's "---" block.
        for i, peon in ipairs(PEON_SOUNDS) do
            local key, name, file = peon[1], peon[2], peon[3]
            soundFiles[key], names[key], isFile[key] = file, name, file
            table.insert(order, #CUI.ALERT_SOUND_ORDER + i, key)
        end
        CUI.AppendSharedMediaSounds(soundFiles, names, order)
        TrackerNS.SoundNames, TrackerNS.SoundOrder = names, order
    end
    return soundFiles, TrackerNS.SoundNames, TrackerNS.SoundOrder
end

-- Also the options dropdown's preview.
local function PlaySoundKey(key)
    if key and key ~= "none" then CUI.PlaySoundPath(TrackerNS.Sounds()[key], isFile[key] ~= nil) end
end
TrackerNS.PlaySoundKey = PlaySoundKey

local function ProgressOn()
    return (Cfg("soundObjective") or "none") ~= "none"
        or (Cfg("soundQuest") or "none") ~= "none"
        or Cfg("announceProgress")
end

-- A finished objective, with the quest's link. In a party or instance group
-- only; never a raid, never during chat lockdown.
local function Announce(questId, text)
    if not Cfg("announceProgress") or not text or text == "" or IsInRaid() then return end
    local channel
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        channel = "INSTANCE_CHAT"
    elseif IsInGroup(LE_PARTY_CATEGORY_HOME) then
        channel = "PARTY"
    else
        return
    end
    if C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then return end
    local quest = GetQuestLink(questId) or C_QuestLog.GetTitleForQuestID(questId) or ""
    C_ChatInfo.SendChatMessage("[CUI] " .. quest .. ": " .. text, channel)
end

-- Keeps the quest's current counts; false when it has no data yet.
local function Remember(questId)
    local objectives = C_QuestLog.GetQuestObjectives(questId)
    if not objectives then return false end
    local kept = counts[questId] or {}
    for i, o in ipairs(objectives) do
        kept[i] = o.numFulfilled or 0
    end
    kept.done = C_QuestLog.IsComplete(questId) == true
    counts[questId] = kept
    return true
end

local function Compare(questId)
    local kept = counts[questId]
    if not kept then
        Remember(questId)
        return
    end
    local objectives = C_QuestLog.GetQuestObjectives(questId)
    if not objectives then return end
    local finishedOne = false
    for i, o in ipairs(objectives) do
        local now = o.numFulfilled or 0
        if kept[i] and now > kept[i] and o.finished then
            Announce(questId, o.text)
            finishedOne = true
        end
        kept[i] = now
    end
    local done = C_QuestLog.IsComplete(questId) == true
    if done and not kept.done then
        PlaySoundKey(Cfg("soundQuest"))
    elseif finishedOne then
        PlaySoundKey(Cfg("soundObjective"))
    end
    kept.done = done
end

local function RememberAll()
    wipe(counts)
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local questInfo = C_QuestLog.GetInfo(i)
        if questInfo and not questInfo.isHeader and questInfo.questID then Remember(questInfo.questID) end
    end
end

local function OnProgressEvent(_, eventName, questId)
    if eventName == "QUEST_WATCH_UPDATE" then
        if questId then marked[questId] = true end
    elseif eventName == "QUEST_LOG_UPDATE" then
        -- The counts are first taken here, once the log has entries (not at login).
        if seedWaiting then
            if C_QuestLog.GetNumQuestLogEntries() == 0 then return end
            seedWaiting = false
            RememberAll()
        end
        for id in pairs(marked) do
            marked[id] = nil
            Compare(id)
        end
    elseif eventName == "QUEST_ACCEPTED" then
        if questId then Remember(questId) end
    elseif eventName == "QUEST_REMOVED" then
        if questId then counts[questId] = nil end
    end
end

-- The options' and profile switch's entry point.
function TrackerNS.ApplyQuestProgress()
    local isOn = ProgressOn()
    if not progressFrame then
        if not isOn then return end
        progressFrame = CreateFrame("Frame")
        progressFrame:SetScript("OnEvent", OnProgressEvent)
    end
    progressFrame:UnregisterAllEvents()
    wipe(marked)
    wipe(counts)
    seedWaiting = isOn
    if not isOn then return end
    for _, eventName in ipairs({ "QUEST_WATCH_UPDATE", "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED" }) do
        progressFrame:RegisterEvent(eventName)
    end
end

-------------------------------------------------------------------------------
--  Objective line colours (CludesUI style; the skin paints): a progress
--  gradient over the three stops and/or dimmed finished lines. Blizzard
--  recolours a line only when its colour style changes, so ours holds
--  between passes. Each line is stamped with what it was painted from (its
--  text, Blizzard's colour style, the settings), and only a line whose stamp
--  moved is painted again: an unchanged block costs no objective lookup.
-------------------------------------------------------------------------------
local painted = setmetatable({}, { __mode = "k" })
local stampText = setmetatable({}, { __mode = "k" })
local stampStyle = setmetatable({}, { __mode = "k" })
local stampGen = setmetatable({}, { __mode = "k" })

local STOPS = {
    { "objStartR", "objStartG", "objStartB", def = OBJ_STOPS.Start },
    { "objMidR", "objMidG", "objMidB", def = OBJ_STOPS.Mid },
    { "objEndR", "objEndG", "objEndB", def = OBJ_STOPS.End },
}
-- Every setting the paint reads; a change moves the generation each stamp carries.
local COLOUR_KEYS = { "objProgressColor", "objDimCompleted", "objDimAlpha" }
for _, stop in ipairs(STOPS) do
    for i = 1, 3 do
        COLOUR_KEYS[#COLOUR_KEYS + 1] = stop[i]
    end
end
local seen, generation = {}, 0
local function Generation()
    local db = TrackerNS.DB()
    local moved = false
    for _, key in ipairs(COLOUR_KEYS) do
        if seen[key] ~= db[key] then
            seen[key] = db[key]
            moved = true
        end
    end
    if moved then generation = generation + 1 end
    return generation
end

local function StopColour(stop)
    local db = TrackerNS.DB()
    return db[stop[1]] or stop.def[1], db[stop[2]] or stop.def[2], db[stop[3]] or stop.def[3]
end

-- The gradient at f (0 to 1) over Start, Mid and End.
local function ProgressRGB(frame)
    local from, to
    if frame < 0.5 then
        from, to, frame = STOPS[1], STOPS[2], frame * 2
    else
        from, to, frame = STOPS[2], STOPS[3], frame * 2 - 1
    end
    local r1, g1, b1 = StopColour(from)
    local r2, g2, b2 = StopColour(to)
    return r1 + (r2 - r1) * frame, g1 + (g2 - g1) * frame, b1 + (b2 - b1) * frame
end
TrackerNS.ProgressRGB = ProgressRGB

-- Back to Blizzard's colour.
local function Restore(text)
    local style = text.colorStyle
    if style then text:SetTextColor(style.r, style.g, style.b, 1) end
    painted[text], stampText[text], stampStyle[text], stampGen[text] = nil, nil, nil, nil
end

local function Stamp(text, gen)
    stampText[text], stampStyle[text], stampGen[text] = text:GetText(), text.colorStyle, gen
end

local function Stale(text, gen)
    return stampGen[text] ~= gen or stampText[text] ~= text:GetText() or stampStyle[text] ~= text.colorStyle
end

-- Whether the skin should hand blocks over: a mode is on, or lines still
-- carry our colour.
function TrackerNS.ObjColorsWanted()
    return Cfg("objProgressColor") or Cfg("objDimCompleted") or next(painted) ~= nil
end

function TrackerNS.ColorObjectiveLines(questBlock)
    local lines = questBlock and questBlock.usedLines
    if not lines then return end
    local gradient, dim = Cfg("objProgressColor"), Cfg("objDimCompleted")
    local questId = type(questBlock.id) == "number" and questBlock.id
    if not ((gradient or dim) and questId) then
        if next(painted) ~= nil then
            for _, line in pairs(lines) do
                if line.Text and painted[line.Text] then Restore(line.Text) end
            end
        end
        return
    end
    local gen = Generation()
    -- Anything to do? An objective line whose stamp moved, or a non-objective
    -- line still carrying our colour.
    local stale = false
    for key, line in pairs(lines) do
        local text = line.Text
        if
            text
            and ((type(key) == "number" and Stale(text, gen)) or (type(key) ~= "number" and painted[text]))
        then
            stale = true
            break
        end
    end
    if not stale then return end
    local objectives = C_QuestLog.GetQuestObjectives(questId)
    local alpha = (Cfg("objDimAlpha") or 45) / 100
    for key, line in pairs(lines) do
        local text = line.Text
        local o = objectives and type(key) == "number" and objectives[key]
        if text and o then
            if Stale(text, gen) then
                local style = text.colorStyle
                local red, green, blue = 1, 1, 1
                if style then
                    red, green, blue = style.r, style.g, style.b
                end
                if gradient then
                    -- Finished lines take the End colour, not Blizzard's grey.
                    if o.finished then
                        red, green, blue = ProgressRGB(1)
                    elseif type(o.numRequired) == "number" and o.numRequired > 0 then
                        red, green, blue = ProgressRGB((o.numFulfilled or 0) / o.numRequired)
                    end
                end
                text:SetTextColor(red, green, blue, (dim and o.finished) and alpha or 1)
                painted[text] = true
                Stamp(text, gen)
            end
        elseif text then
            -- A line that is not an objective (a recycled frame).
            if painted[text] then Restore(text) end
            -- An index with no objective is stamped too, so it cannot keep the block stale.
            if objectives and type(key) == "number" then Stamp(text, gen) end
        end
    end
end
