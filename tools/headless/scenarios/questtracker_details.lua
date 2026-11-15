-- Quest Tracker > Quest details window (WoW Forever): a quest with
-- objectives (one done), a description, XP, money, item and currency
-- rewards and choices (one uncached); quest log updates that change nothing,
-- an objective finishing, the buttons (focus, share, abandon), toggling,
-- and the quest leaving the log. Counts window rebuilds.
local CUI = rawget(_G, "CludesUI")
local mod = CUI._ModuleNS.CludesUIQuestTracker
local EQT = mod.EQT
local function Put(...)
    local t = { ... }
    for i = 1, select("#", ...) do t[i] = tostring(t[i]) end
    OUT:write("== ", table.concat(t, " "), "\n")
end
if not EQT.ShowQuestDetails then
    Put("no details window on this client")
    return
end
local objectives = {
    { text = "Wolves slain: 3/8", finished = false },
    { text = "Find the cave", finished = true },
}
local inLog, focused, grouped = true, nil, false
C_QuestLog.GetLogIndexForQuestID = function(id) return inLog and id == 101 and 5 or nil end
C_QuestLog.GetTitleForQuestID = function() return "Wolves at the Door" end
C_QuestLog.GetQuestDifficultyLevel = function() return 12 end
C_QuestLog.GetQuestTagInfo = function() return { tagName = "Elite" } end
C_QuestLog.IsComplete = function() return false end
C_QuestLog.GetQuestObjectives = function() return objectives end
C_QuestLog.ShouldShowQuestRewards = function() return true end
C_QuestLog.GetQuestRewardCurrencies = function() return { { name = "Honor", texture = 1, totalRewardAmount = 50, quality = 1 } } end
C_QuestLog.IsPushableQuest = function() return true end
C_QuestLog.CanAbandonQuest = function() return true end
GetQuestLogQuestText = function() return "The wolves grow bold.", "Kill 8 wolves." end
GetQuestLogRewardXP = function() return 450 end
GetQuestLogRewardMoney = function() return 1234 end
GetNumQuestLogRewards = function() return 1 end
GetQuestLogRewardInfo = function() return "Wolf Pelt Cloak", 2, 1, 2, nil, 9001 end
GetNumQuestLogChoices = function() return 2 end
GetQuestLogChoiceInfo = function(i) if i == 1 then return "Axe", 3, 1, 3, nil, 9002 end return nil, 4, 1, nil, nil, 9003 end
GetQuestDifficultyColor = function() return { r = 1, g = 1, b = 0 } end
CreateColor = function(r, g, b) return { WrapTextInColorCode = function(_, t) return "|cff" .. t .. "|r" end } end
GetMoneyString = function(m) return m .. "c" end
ColorManager = { GetColorDataForItemQuality = function(q) return q and { r = 0.1 * q, g = 0.5, b = 1 } end }
Item = { CreateFromItemID = function(_, id) return {
    IsItemEmpty = function() return false end,
    IsItemDataCached = function() return id ~= 9003 end,
    ContinueOnItemLoad = function(_, fn) PENDING = fn end,
} end }
C_SuperTrack.GetSuperTrackedQuestID = function() return focused end
IsInGroup = function() return grouped end
BUILDS = 0
local getFont = EQT.GetFont
EQT.GetFont = function(...) BUILDS = BUILDS + 1 return getFont(...) end
local function Window() return rawget(_G, "CUI_QuestDetails") end

EQT.ShowQuestDetails(101)
SNAP("details", Window())
local before = BUILDS
HARNESS_FIRE_EVENT("QUEST_LOG_UPDATE")
HARNESS_FIRE_EVENT("QUEST_LOG_UPDATE")
HARNESS_FIRE_EVENT("QUEST_LOG_UPDATE")
Put("text styles for 3 updates with no change", BUILDS - before)
objectives[1] = { text = "Wolves slain: 8/8", finished = true }
HARNESS_FIRE_EVENT("QUEST_LOG_UPDATE")
SNAP("details objective done", Window())
if PENDING then PENDING() end
SNAP("details item loaded", Window())
focused, grouped = 101, true
HARNESS_FIRE_EVENT("SUPER_TRACKING_CHANGED")
HARNESS_FIRE_EVENT("GROUP_ROSTER_UPDATE")
SNAP("details focused in group", Window())
EQT.ShowQuestDetails(101)
Put("second click hides", Window():IsShown())
EQT.ShowQuestDetails(101)
inLog = false
HARNESS_FIRE_EVENT("QUEST_LOG_UPDATE")
Put("left the log", Window():IsShown())
inLog = true
EQT.ShowQuestDetails(101)
HARNESS_FIRE_EVENT("QUEST_REMOVED", 101)
Put("removed", Window():IsShown())
