if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if not CludesUI.IS_FOREVER then
    return
end
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
local EQT = mod.EQT
local Cfg = EQT.Cfg

-- The progress colour stops: the defaults, the paint's fallbacks and the
-- options' swatches all read this.
local OBJ_STOPS = {
    Start = { 1.0, 0.4, 0.4 },
    Mid = { 1.0, 1.0, 0.4 },
    End = { 0.4, 1.0, 0.4 },
}
EQT.OBJ_STOPS = OBJ_STOPS

-- Defaults, added to the module's table before its database is made at login.
do
    local qt = mod.QT_DEFAULTS.profile.questTracker
    qt.questWatchExperimental = false -- unlocks sorting, filters and auto-track
    -- Sorting: Quest Log Order unless another mode is picked; "mixed" leaves
    -- completed quests where the mode puts them.
    qt.questSortMode = "log"
    qt.questSortCompleted = "mixed"
    qt.questSortThenBy = "none"
    -- Filters untrack matching quests and track them again when they pass;
    -- Filter Quests switches the choices below on and off together.
    qt.filterEnabled = false
    qt.filterZone = true
    qt.filterCompleted = false
    qt.filterTrivial = false
    qt.filterRepeatable = false
    qt.filterHeaderToggle = false
    qt.autoTrackZone = false -- tracks quests listed under the current zone or dungeon
    -- Progress: alert sound keys ("none" = off), party messages.
    qt.soundObjective = "none"
    qt.soundQuest = "none"
    qt.announceProgress = false
    -- Objective line colours (CludesUI style only).
    qt.objProgressColor = false
    qt.objDimCompleted = false
    qt.objDimAlpha = 45
    for name, c in pairs(OBJ_STOPS) do
        qt["obj" .. name .. "R"], qt["obj" .. name .. "G"], qt["obj" .. name .. "B"] = c[1], c[2], c[3]
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
local watchFrame
local passQueued = false
local sortRefused = false -- the last re-order did not take (see ApplySort)
local restoreOrder = false -- the tools were turned off: the next pass restores log order
local sortWasOn = false
local awaitingLog = false -- a QUEST_WATCH_UPDATE waits for its QUEST_LOG_UPDATE
local dungeonPass = false -- one pass on entering a dungeon (see CanEditWatches)
local ourEdit = false -- inside our own watch edit: its events are ours
local sortIDs, sortGroup, sortKey, sortKey2, sortRank = {}, {}, {}, {}, {}
local watched = {}
local changedQuests, wasComplete = {}, {} -- the QUEST_WATCH_UPDATE probe

-- The pass's quest log snapshot: one GetInfo per entry per pass.
local logList = {} -- every entry, in log order
local logInfo, logHeader, logZone, logIndex = {}, {}, {}, {} -- by questID
local passZone, passInInstance, passInstance

-- Our tracker (Custom.lua) sorts, filters and auto-tracks its own list with
-- no watch edits, so it needs no experimental switch.
local function ToolsOn()
    return mod.UseCustomTracker() or Cfg("questWatchExperimental") == true
end
-- Quest Log Order is the base mode (a saved "default", the retired Blizzard
-- order mode, reads as it).
local function SortMode()
    local mode = Cfg("questSortMode")
    return (mode == nil or mode == "default") and "log" or mode
end
local function SortCompleted()
    return Cfg("questSortCompleted") or "mixed"
end
-- The second key; none when the first is already unique per quest.
local function SortThenBy()
    if SortMode() == "log" then
        return "none"
    end
    return Cfg("questSortThenBy") or "none"
end
-- The tools keep the watch list sorted while they are on.
local SortOn = ToolsOn
local function SortUses(key)
    return SortMode() == key or SortThenBy() == key
end

-- A filter counts only while Filter Quests is on.
local function Filter(key)
    return ToolsOn() and Cfg("filterEnabled") and Cfg(key)
end
local function FilterOn()
    return Filter("filterZone")
        or Filter("filterCompleted")
        or Filter("filterTrivial")
        or Filter("filterRepeatable")
end
local function AutoOn()
    return ToolsOn() and Cfg("autoTrackZone")
end

-- Per character (watch lists are per character; profiles may be shared), in
-- the account database: hidden = untracked by a filter, exempt = tracked
-- again by the player, auto = tracked by auto-track, declined = auto-tracked
-- then untracked by the player (left alone until they leave the area).
local CHAR_SETS = { "hidden", "exempt", "auto", "declined" }
local charSets
local function CharSets()
    if charSets then
        return charSets
    end
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
        if type(mine[k]) ~= "table" then
            mine[k] = {}
        end
    end
    charSets = mine
    return mine
end

-- Whether a feature turned off left quests to give back. Reads only.
local function HasLeftovers()
    local all = CludesUIDB and CludesUIDB.questWatchChars
    local mine = type(all) == "table" and all[UnitGUID("player")]
    if type(mine) ~= "table" then
        return false
    end
    for _, k in ipairs(CHAR_SETS) do
        if type(mine[k]) == "table" and next(mine[k]) ~= nil then
            return true
        end
    end
    return false
end

local function WatchesActive()
    return SortOn() or FilterOn() or AutoOn() or HasLeftovers()
end

local function ReadWatched()
    wipe(watched)
    for i = 1, C_QuestLog.GetNumQuestWatches() do
        local questID = C_QuestLog.GetQuestIDForQuestWatchIndex(i)
        if questID then
            watched[questID] = true
        end
    end
end

local function Snapshot()
    wipe(logList)
    wipe(logInfo)
    wipe(logHeader)
    wipe(logZone)
    wipe(logIndex)
    passZone = GetRealZoneText()
    passInInstance = IsInInstance()
    passInstance = passInInstance and GetInstanceInfo() or nil
    local header, headerIndex = nil, 0
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        if info then
            logList[#logList + 1] = info
            if info.isHeader then
                header, headerIndex = info.title, i
            elseif info.questID then
                local id = info.questID
                logInfo[id], logHeader[id], logZone[id], logIndex[id] = info, header, headerIndex, i
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
local function InArea(info, header)
    if header and (header == passZone or (passInInstance and header == passInstance)) then
        return true
    end
    return not passInInstance and info.isOnMap == true
end

-- Whether a filter takes the quest off (never the super-tracked one).
local function Filtered(questID, superID)
    if questID == superID then
        return false
    end
    local info = logInfo[questID]
    if not info then
        return false
    end
    if Filter("filterCompleted") and C_QuestLog.IsComplete(questID) then
        return true
    end
    if Filter("filterTrivial") and C_QuestLog.IsQuestTrivial(questID) then
        return true
    end
    if Filter("filterRepeatable") and info.frequency and info.frequency ~= Enum.QuestFrequency.Default then
        return true
    end
    return Filter("filterZone") and not InArea(info, logHeader[questID]) or false
end

-- Our own watch edits (QUEST_WATCH_LIST_CHANGED fires inside the call).
local function Watch(questID)
    ourEdit = true
    C_QuestLog.AddQuestWatch(questID)
    ourEdit = false
end
local function Unwatch(questID)
    ourEdit = true
    C_QuestLog.RemoveQuestWatch(questID)
    ourEdit = false
end

local function ApplyFilter()
    local sets = CharSets()
    local hidden, exempt = sets.hidden, sets.exempt
    local on = FilterOn()
    local superID = C_SuperTrack.GetSuperTrackedQuestID()
    ReadWatched()
    -- An exemption ends when the player untracks the quest.
    for questID in pairs(exempt) do
        if not on or not watched[questID] then
            exempt[questID] = nil
        end
    end
    for questID in pairs(hidden) do
        -- IsOnQuest, not a log index: collapsed headers and loading screens hide indexes.
        if not C_QuestLog.IsOnQuest(questID) then
            hidden[questID] = nil
        elseif watched[questID] then
            -- The player tracked it again: it stays tracked.
            hidden[questID] = nil
            if on and Filtered(questID, superID) then
                exempt[questID] = true
            end
        elseif not on or not Filtered(questID, superID) then
            hidden[questID] = nil
            Watch(questID)
        end
    end
    if not on then
        return
    end
    for questID in pairs(watched) do
        if not exempt[questID] and Filtered(questID, superID) then
            hidden[questID] = true
            sets.auto[questID] = nil
            Unwatch(questID)
        end
    end
end

-- Tracks quests in the current area (see InArea), and untracks them again on leaving.
local function ApplyAutoTrack()
    local sets = CharSets()
    local hidden, auto, declined = sets.hidden, sets.auto, sets.declined
    local on = AutoOn()
    if not on and next(auto) == nil and next(declined) == nil then
        return
    end
    local superID = C_SuperTrack.GetSuperTrackedQuestID()
    ReadWatched()
    -- One we tracked that the player untracked: declined.
    for questID in pairs(auto) do
        if not watched[questID] then
            auto[questID] = nil
            declined[questID] = true
        end
    end
    local room = Constants.QuestWatchConsts.MAX_QUEST_WATCHES - C_QuestLog.GetNumQuestWatches()
    local header
    for _, info in ipairs(logList) do
        if info.isHeader then
            header = info.title
        elseif not info.isHidden and not info.isTask and not info.isBounty then
            local questID = info.questID
            if on and InArea(info, header) then
                if
                    room > 0
                    and not watched[questID]
                    and not declined[questID]
                    and not hidden[questID]
                    and not Filtered(questID, superID)
                then
                    auto[questID] = true
                    room = room - 1
                    Watch(questID)
                end
            else
                declined[questID] = nil
                if auto[questID] then
                    auto[questID] = nil
                    Unwatch(questID)
                end
            end
        end
    end
    -- Quests that left the log.
    for questID in pairs(auto) do
        if not C_QuestLog.IsOnQuest(questID) then
            auto[questID] = nil
        end
    end
    for questID in pairs(declined) do
        if not on or not C_QuestLog.IsOnQuest(questID) then
            declined[questID] = nil
        end
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
local function ProgressKey(questID)
    if C_QuestLog.IsComplete(questID) then
        return -1
    end
    local have, need = 0, 0
    for _, o in ipairs(C_QuestLog.GetQuestObjectives(questID) or {}) do
        local required = o.numRequired
        if type(required) == "number" and required > 0 then
            have, need = have + math.min(o.numFulfilled or 0, required), need + required
        end
    end
    return need > 0 and -(have / need) or 0
end

local SORT_KEYS = {
    zone = function(id)
        return logZone[id] or 0
    end,
    progress = ProgressKey,
    type = function(id)
        local info = logInfo[id]
        if not info then
            return 6
        end
        local rank = TYPE_RANK[info.questClassification] or 6
        if rank == 6 and info.frequency and info.frequency ~= Enum.QuestFrequency.Default then
            rank = 7
        end
        return rank
    end,
    log = function(id)
        return logIndex[id] or 0
    end,
    level = function(id)
        local info = logInfo[id]
        return info and (info.difficultyLevel or info.level) or 0
    end,
    name = function(id)
        local info = logInfo[id]
        return info and info.title and info.title:lower() or ""
    end,
    none = function()
        return 0
    end,
}

-- An unknown mode keeps the list's own order.
local function KeyFor(mode, questID, rank)
    local fn = SORT_KEYS[mode]
    if fn then
        return fn(questID)
    end
    return rank
end

-- Sorts a quest ID list in place (its order is the tie-break). Reads the pass's snapshot.
local function SortList(ids, mode, completed, thenBy)
    wipe(sortGroup)
    wipe(sortKey)
    wipe(sortKey2)
    wipe(sortRank)
    for i, questID in ipairs(ids) do
        sortRank[questID] = i
        local group = 1
        if completed ~= "mixed" then
            local done = C_QuestLog.IsComplete(questID) == true
            group = ((completed == "top") == done) and 1 or 2
        end
        sortGroup[questID] = group
        sortKey[questID] = KeyFor(mode, questID, i)
        sortKey2[questID] = KeyFor(thenBy, questID, i)
    end
    table.sort(ids, Before)
end

-- Re-orders the watch list: the settings' choices, or the restore pass's
-- plain quest log order.
local function ApplySort(mode, completed, thenBy)
    local count = 0
    for i = 1, C_QuestLog.GetNumQuestWatches() do
        local questID = C_QuestLog.GetQuestIDForQuestWatchIndex(i)
        if questID then
            count = count + 1
            sortIDs[count] = questID
        end
    end
    for i = #sortIDs, count + 1, -1 do
        sortIDs[i] = nil
    end
    SortList(sortIDs, mode, completed, thenBy)

    -- AddQuestWatch inserts at the top, so the head that is out of place is
    -- added again from the bottom up; the tail already in place stays.
    local last
    for i = count, 1, -1 do
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
    local n = 0
    for i = 1, C_QuestLog.GetNumQuestWatches() do
        local questID = C_QuestLog.GetQuestIDForQuestWatchIndex(i)
        if questID then
            n = n + 1
            if questID ~= sortIDs[n] then
                sortRefused = true
                return
            end
        end
    end
end

-- For our tracker, which reads only: one snapshot per pass, then area,
-- filters and sorting against it. No watch edits.
function EQT.QuestLogSnapshot()
    Snapshot()
    return logList, logHeader
end
EQT.QuestInArea = InArea
function EQT.IsQuestFiltered(questID)
    return FilterOn() and Filtered(questID, C_SuperTrack.GetSuperTrackedQuestID())
end
function EQT.AutoTrackOn()
    return AutoOn()
end
function EQT.SortQuestList(ids)
    SortList(ids, SortMode(), SortCompleted(), SortThenBy())
end

-- A watch edit fires QUEST_WATCH_LIST_CHANGED at once, so Blizzard's tracker,
-- quest log and super-track handlers run under our taint (and the tracker
-- update they schedule). Under aura restrictions that update can error in
-- the scenario tracker, so edits happen out of combat and encounters, never
-- with the map open (its quest pins would rebuild tainted too), and in the
-- open world. The one instance edit is the pass on entering a 5-player
-- dungeon (out of combat, from its loading screen), which brings its quests
-- back for Current Zone Only and auto-track; leaving an instance (a loading
-- screen and zone events) runs a pass again.
local function MapOpen()
    return WorldMapFrame ~= nil and WorldMapFrame:IsShown()
end

local function CanEditWatches()
    if IsInInstance() and not dungeonPass then
        return false
    end
    if MapOpen() or InCombatLockdown() then
        return false
    end
    return not (C_InstanceEncounter and C_InstanceEncounter.IsEncounterInProgress())
end

local QueueWatches -- below; the map callback needs it
local waitingForMap = false

-- Again when the map closes. EventRegistry calls through
-- securecallfunction, so this stays out of the map's chain; it unhooks
-- itself once it has run.
local function MapClosed()
    EventRegistry:UnregisterCallback("WorldMapOnHide", EQT)
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
            EventRegistry:RegisterCallback("WorldMapOnHide", MapClosed, EQT)
        end
        -- Combat or an open-world encounter: again when it ends. Instances
        -- wait for the zone events on the way out.
        if not IsInInstance() then
            if InCombatLockdown() then
                mod.CombatQueue.Defer("QuestWatches", QueueWatches)
            end
            watchFrame:RegisterEvent("ENCOUNTER_END")
        end
        return
    end
    dungeonPass = false
    watchFrame:UnregisterEvent("ENCOUNTER_END")
    -- The log is not loaded yet (a loading screen): nothing to go on.
    if C_QuestLog.GetNumQuestLogEntries() == 0 then
        return
    end
    Snapshot()
    ApplyFilter()
    ApplyAutoTrack()
    -- The tools were turned off: back to quest log order once, after the
    -- filter and auto-track have given their quests back.
    if restoreOrder then
        restoreOrder = false
        ApplySort("log", "mixed", "none")
    end
    if SortOn() then
        ApplySort(SortMode(), SortCompleted(), SortThenBy())
    end
    -- The last pass after everything was turned off: the frame sleeps.
    if not WatchesActive() then
        watchFrame:UnregisterAllEvents()
    end
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
local function OnWatchEvent(_, event, arg)
    if event == "QUEST_WATCH_LIST_CHANGED" then
        if not ourEdit then
            QueueWatches()
        end
    elseif event == "QUEST_WATCH_UPDATE" then
        if arg then
            changedQuests[arg] = true
        end
        awaitingLog = true
    elseif event == "QUEST_LOG_UPDATE" then
        if not awaitingLog then
            return
        end
        awaitingLog = false
        local need = SortUses("progress")
        for questID in pairs(changedQuests) do
            changedQuests[questID] = nil
            local done = C_QuestLog.IsComplete(questID) == true
            local was = wasComplete[questID]
            wasComplete[questID] = done
            if was ~= done and (was ~= nil or done) then
                need = true
            end
        end
        if need then
            QueueWatches()
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
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
    if not otf then
        return
    end
    local off = SortOn()
    if off == blizzardSortOff then
        return
    end
    blizzardSortOff = off
    for _, event in ipairs(BLIZZARD_SORT_EVENTS) do
        if off then
            otf:UnregisterEvent(event)
        else
            otf:RegisterEvent(event)
        end
    end
end

-- The Filter Quests button on the Quests header, left of its minimize
-- button. Made on first use; the skin tints it and switches its mouse off
-- with the tracker's (EQT.FilterToggle).
local function FilterTip()
    return Cfg("filterEnabled") and "Quest Filters On" or "Quest Filters Off"
end

local function MakeFilterButton()
    local qt = _G.QuestObjectiveTracker
    local header = qt and qt.Header
    local minimize = header and header.MinimizeButton
    if not minimize then
        return nil
    end
    local button = CreateFrame("Button", nil, header)
    button:SetSize(minimize:GetSize())
    button:SetPoint("RIGHT", minimize, "LEFT", -2, 0)
    -- Above the minimize button's header-wide click area (SkinHeader).
    button:SetFrameLevel(minimize:GetFrameLevel() + 1)
    button:SetNormalAtlas("ui-questtrackerbutton-filter")
    button:SetPushedAtlas("ui-questtrackerbutton-filter-pressed")
    button:SetHighlightAtlas("ui-questtrackerbutton-red-highlight", "ADD")
    button:SetScript("OnEnter", function(self)
        CludesUI.ShowWidgetTooltip(self, FilterTip())
    end)
    button:SetScript("OnLeave", function()
        CludesUI.HideWidgetTooltip()
    end)
    button:SetScript("OnClick", function(self)
        EQT.Set("filterEnabled", not Cfg("filterEnabled"))
        EQT.ApplyQuestWatches()
        CludesUI:RefreshPage()
        CludesUI.ShowWidgetTooltip(self, FilterTip())
    end)
    EQT.FilterToggle = button
    EQT.SkinHeader(header)
    if EQT._trackerMouseOff then
        EQT.MouseOff(button)
    end
    return button
end

local function ApplyFilterButton()
    local wanted = ToolsOn() and Cfg("filterHeaderToggle") == true
    local button = EQT.FilterToggle
    if not button then
        if not wanted then
            return
        end
        button = MakeFilterButton()
        if not button then
            return
        end
    end
    button:SetShown(wanted)
    button:SetAlpha(Cfg("filterEnabled") and 1 or 0.4)
end

-- The options' and profile switch's entry point.
function EQT.ApplyQuestWatches()
    -- Our tracker keeps its own list; the watch list is left alone.
    if mod.UseCustomTracker() then
        if EQT.RefreshCustom then
            EQT.RefreshCustom()
        end
        return
    end
    ApplyBlizzardSort()
    ApplyFilterButton()
    -- The tools turned off (or a profile without them): the next pass
    -- restores quest log order.
    local sortOn = SortOn()
    if sortWasOn and not sortOn then
        restoreOrder = true
    end
    sortWasOn = sortOn
    if sortOn then
        restoreOrder = false
    end
    local active = WatchesActive()
    if not watchFrame then
        if not (active or restoreOrder) then
            return
        end
        watchFrame = CreateFrame("Frame")
        watchFrame:SetScript("OnEvent", OnWatchEvent)
    end
    watchFrame:UnregisterAllEvents()
    sortRefused, awaitingLog, dungeonPass = false, false, false
    wipe(changedQuests)
    if not active then
        -- The restore pass puts the frame to sleep once it has run.
        if restoreOrder then
            QueueWatches()
        end
        return
    end
    local zoneBased = Filter("filterZone") or AutoOn()
    watchFrame:RegisterEvent("QUEST_WATCH_LIST_CHANGED")
    -- The current area changes on these, and entering or leaving an instance
    -- ends on a loading screen.
    if zoneBased then
        watchFrame:RegisterEvent("ZONE_CHANGED")
        watchFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
        watchFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    end
    -- Objective progress can make a quest complete.
    if (sortOn and (SortCompleted() ~= "mixed" or SortUses("progress"))) or Filter("filterCompleted") then
        watchFrame:RegisterEvent("QUEST_WATCH_UPDATE")
        watchFrame:RegisterEvent("QUEST_LOG_UPDATE")
    end
    -- Quests turn trivial as the player levels.
    if Filter("filterTrivial") then
        watchFrame:RegisterEvent("PLAYER_LEVEL_UP")
    end
    -- Blizzard does not always watch a new quest.
    if AutoOn() then
        watchFrame:RegisterEvent("QUEST_ACCEPTED")
    end
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

local soundPaths
function EQT.Sounds()
    if not soundPaths then
        local names, order
        soundPaths, names, order = CludesUI.BuildAlertSoundTables()
        -- After the bundled sounds, before the media library's "---" block.
        for i, peon in ipairs(PEON_SOUNDS) do
            local key, name, file = peon[1], peon[2], peon[3]
            soundPaths[key], names[key], isFile[key] = file, name, file
            table.insert(order, #CludesUI.ALERT_SOUND_ORDER + i, key)
        end
        CludesUI.AppendSharedMediaSounds(soundPaths, names, order)
        EQT.SoundNames, EQT.SoundOrder = names, order
    end
    return soundPaths, EQT.SoundNames, EQT.SoundOrder
end

-- Also the options dropdown's preview.
local function PlaySoundKey(key)
    if key and key ~= "none" then
        CludesUI.PlaySoundPath(EQT.Sounds()[key], isFile[key] ~= nil)
    end
end
EQT.PlaySoundKey = PlaySoundKey

local function ProgressOn()
    return (Cfg("soundObjective") or "none") ~= "none"
        or (Cfg("soundQuest") or "none") ~= "none"
        or Cfg("announceProgress")
end

-- A finished objective, with the quest's link. In a party or instance group
-- only; never a raid, never during chat lockdown.
local function Announce(questID, text)
    if not Cfg("announceProgress") or not text or text == "" or IsInRaid() then
        return
    end
    local channel
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        channel = "INSTANCE_CHAT"
    elseif IsInGroup(LE_PARTY_CATEGORY_HOME) then
        channel = "PARTY"
    else
        return
    end
    if C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then
        return
    end
    local quest = GetQuestLink(questID) or C_QuestLog.GetTitleForQuestID(questID) or ""
    C_ChatInfo.SendChatMessage("[CUI] " .. quest .. ": " .. text, channel)
end

-- Keeps the quest's current counts; false when it has no data yet.
local function Remember(questID)
    local objectives = C_QuestLog.GetQuestObjectives(questID)
    if not objectives then
        return false
    end
    local kept = counts[questID] or {}
    for i, o in ipairs(objectives) do
        kept[i] = o.numFulfilled or 0
    end
    kept.done = C_QuestLog.IsComplete(questID) == true
    counts[questID] = kept
    return true
end

local function Compare(questID)
    local kept = counts[questID]
    if not kept then
        Remember(questID)
        return
    end
    local objectives = C_QuestLog.GetQuestObjectives(questID)
    if not objectives then
        return
    end
    local finishedOne = false
    for i, o in ipairs(objectives) do
        local now = o.numFulfilled or 0
        if kept[i] and now > kept[i] and o.finished then
            Announce(questID, o.text)
            finishedOne = true
        end
        kept[i] = now
    end
    local done = C_QuestLog.IsComplete(questID) == true
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
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and info.questID then
            Remember(info.questID)
        end
    end
end

local function OnProgressEvent(_, event, questID)
    if event == "QUEST_WATCH_UPDATE" then
        if questID then
            marked[questID] = true
        end
    elseif event == "QUEST_LOG_UPDATE" then
        -- The counts are first taken here, once the log has entries (not at login).
        if seedWaiting then
            if C_QuestLog.GetNumQuestLogEntries() == 0 then
                return
            end
            seedWaiting = false
            RememberAll()
        end
        for id in pairs(marked) do
            marked[id] = nil
            Compare(id)
        end
    elseif event == "QUEST_ACCEPTED" then
        if questID then
            Remember(questID)
        end
    elseif event == "QUEST_REMOVED" then
        if questID then
            counts[questID] = nil
        end
    end
end

-- The options' and profile switch's entry point.
function EQT.ApplyQuestProgress()
    local on = ProgressOn()
    if not progressFrame then
        if not on then
            return
        end
        progressFrame = CreateFrame("Frame")
        progressFrame:SetScript("OnEvent", OnProgressEvent)
    end
    progressFrame:UnregisterAllEvents()
    wipe(marked)
    wipe(counts)
    seedWaiting = on
    if not on then
        return
    end
    for _, event in ipairs({ "QUEST_WATCH_UPDATE", "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED" }) do
        progressFrame:RegisterEvent(event)
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
    local db = EQT.DB()
    local moved = false
    for _, key in ipairs(COLOUR_KEYS) do
        if seen[key] ~= db[key] then
            seen[key] = db[key]
            moved = true
        end
    end
    if moved then
        generation = generation + 1
    end
    return generation
end

local function StopColour(stop)
    local db = EQT.DB()
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
EQT.ProgressRGB = ProgressRGB

-- Back to Blizzard's colour.
local function Restore(text)
    local style = text.colorStyle
    if style then
        text:SetTextColor(style.r, style.g, style.b, 1)
    end
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
function EQT.ObjColorsWanted()
    return Cfg("objProgressColor") or Cfg("objDimCompleted") or next(painted) ~= nil
end

function EQT.ColorObjectiveLines(block)
    local lines = block and block.usedLines
    if not lines then
        return
    end
    local gradient, dim = Cfg("objProgressColor"), Cfg("objDimCompleted")
    local questID = type(block.id) == "number" and block.id
    if not ((gradient or dim) and questID) then
        if next(painted) ~= nil then
            for _, line in pairs(lines) do
                if line.Text and painted[line.Text] then
                    Restore(line.Text)
                end
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
    if not stale then
        return
    end
    local objectives = C_QuestLog.GetQuestObjectives(questID)
    local alpha = (Cfg("objDimAlpha") or 45) / 100
    for key, line in pairs(lines) do
        local text = line.Text
        local o = objectives and type(key) == "number" and objectives[key]
        if text and o then
            if Stale(text, gen) then
                local style = text.colorStyle
                local region, g, b = 1, 1, 1
                if style then
                    region, g, b = style.r, style.g, style.b
                end
                if gradient then
                    -- Finished lines take the End colour, not Blizzard's grey.
                    if o.finished then
                        region, g, b = ProgressRGB(1)
                    elseif type(o.numRequired) == "number" and o.numRequired > 0 then
                        region, g, b = ProgressRGB((o.numFulfilled or 0) / o.numRequired)
                    end
                end
                text:SetTextColor(region, g, b, (dim and o.finished) and alpha or 1)
                painted[text] = true
                Stamp(text, gen)
            end
        elseif text then
            -- A line that is not an objective (a recycled frame).
            if painted[text] then
                Restore(text)
            end
            -- An index with no objective is stamped too, so it cannot keep the block stale.
            if objectives and type(key) == "number" then
                Stamp(text, gen)
            end
        end
    end
end
