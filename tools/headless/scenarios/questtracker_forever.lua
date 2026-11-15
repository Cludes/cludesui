-- Quest Tracker > WoW Forever quest tools: sorting (every mode, completed
-- placement, then-by), filters (zone, completed, trivial, repeatable, the
-- super-tracked exception), the watch list edits on Blizzard's tracker
-- (filter, auto-track, sort, restore on turning off), progress sounds and
-- party announcements, objective colours, and the sound list.
local CUI = rawget(_G, "CludesUI")
local mod = CUI._ModuleNS.CludesUIQuestTracker
local EQT = mod.EQT
local function Put(...)
    local t = { ... }
    for i = 1, select("#", ...) do t[i] = tostring(t[i]) end
    OUT:write("== ", table.concat(t, " "), "\n")
end
if not EQT.SortQuestList then
    Put("retail: no quest tools")
    return
end
local QC = Enum.QuestClassification
QC.Campaign, QC.Legendary, QC.Important, QC.Meta, QC.Questline, QC.Normal, QC.Recurring = 1, 2, 3, 4, 5, 6, 7
Enum.QuestFrequency.Default = 0
Constants = Constants or {}
Constants.QuestWatchConsts = { MAX_QUEST_WATCHES = 25 }
local log = {
    { isHeader = true, title = "Elwynn Forest" },
    { questID = 1, title = "Bravo", level = 10, questClassification = 6, frequency = 0 },
    { questID = 2, title = "alpha", level = 12, questClassification = 1, frequency = 0 },
    { isHeader = true, title = "Westfall" },
    { questID = 3, title = "Charlie", level = 8, questClassification = 6, frequency = 1 },
    { questID = 4, title = "Delta", level = 15, questClassification = 6, frequency = 0, isOnMap = true },
}
local complete = { [3] = true }
local objectives = {
    [1] = { { numFulfilled = 2, numRequired = 8, text = "Wolves 2/8" } },
    [2] = { { numFulfilled = 5, numRequired = 5, finished = true, text = "Done 5/5" } },
    [3] = {},
    [4] = { { numFulfilled = 1, numRequired = 2, text = "Thing 1/2" }, { numFulfilled = 0, numRequired = 1, text = "Other 0/1" } },
}
local zone, trivial, super = "Elwynn Forest", { [4] = true }, nil
C_QuestLog.GetNumQuestLogEntries = function() return #log end
C_QuestLog.GetInfo = function(i) return log[i] end
C_QuestLog.IsComplete = function(id) return complete[id] == true end
C_QuestLog.IsQuestTrivial = function(id) return trivial[id] == true end
C_QuestLog.GetQuestObjectives = function(id) return objectives[id] end
C_QuestLog.IsOnQuest = function(id) return id >= 1 and id <= 4 end
C_QuestLog.GetTitleForQuestID = function(id) return "Quest " .. id end
C_SuperTrack.GetSuperTrackedQuestID = function() return super end
GetRealZoneText = function() return zone end
IsInInstance = function() return false end
InCombatLockdown = function() return false end
C_InstanceEncounter = { IsEncounterInProgress = function() return false end }
WorldMapFrame = { IsShown = function() return false end }
local function Ids() return { 1, 2, 3, 4 } end
local function Sorted()
    local ids = Ids()
    EQT.QuestLogSnapshot()
    EQT.SortQuestList(ids)
    return table.concat(ids, ",")
end
for _, mode in ipairs({ "log", "zone", "progress", "type", "level", "name", "default" }) do
    EQT.Set("questSortMode", mode)
    Put("sort", mode, Sorted())
end
EQT.Set("questSortMode", "zone")
for _, then_ in ipairs({ "name", "level", "progress" }) do
    EQT.Set("questSortThenBy", then_)
    Put("sort zone then", then_, Sorted())
end
for _, place in ipairs({ "top", "bottom" }) do
    EQT.Set("questSortCompleted", place)
    Put("completed", place, Sorted())
end
EQT.Set("questSortCompleted", "mixed")

-- Filters.
EQT.Set("filterEnabled", true)
local function Filtered()
    EQT.QuestLogSnapshot()
    local out = {}
    for _, id in ipairs(Ids()) do out[#out + 1] = EQT.IsQuestFiltered(id) and id or "-" end
    return table.concat(out, ",")
end
Put("filter zone", Filtered())
super = 3
Put("filter zone, 3 super-tracked", Filtered())
super = nil
EQT.Set("filterZone", false)
for _, k in ipairs({ "filterCompleted", "filterTrivial", "filterRepeatable" }) do
    EQT.Set(k, true)
    Put("filter", k, Filtered())
    EQT.Set(k, false)
end
EQT.Set("filterEnabled", false)
Put("filters off", Filtered())
EQT.QuestLogSnapshot()
Put("in area", EQT.QuestInArea(log[5], "Westfall"), EQT.QuestInArea(log[6], "Westfall"), EQT.QuestInArea(log[2], "Elwynn Forest"))

-- Watch list edits on Blizzard's tracker.
local watches = { 3, 1 }
local edits = {}
C_QuestLog.GetNumQuestWatches = function() return #watches end
C_QuestLog.GetQuestIDForQuestWatchIndex = function(i) return watches[i] end
C_QuestLog.AddQuestWatch = function(id) table.insert(watches, 1, id) edits[#edits + 1] = "+" .. id end
C_QuestLog.RemoveQuestWatch = function(id)
    for i, w in ipairs(watches) do if w == id then table.remove(watches, i) break end end
    edits[#edits + 1] = "-" .. id
end
mod.UseCustomTracker = function() return false end
local function Pass(label)
    edits = {}
    EQT.ApplyQuestWatches()
    HARNESS_ADVANCE(0.1)
    Put(label, "watches", table.concat(watches, ","), "edits", table.concat(edits, " "))
end
EQT.Set("questWatchExperimental", true)
EQT.Set("questSortMode", "name")
EQT.Set("questSortThenBy", "none")
Pass("sorted by name")
EQT.Set("filterEnabled", true)
EQT.Set("filterZone", true)
Pass("zone filter")
EQT.Set("autoTrackZone", true)
Pass("auto-track")
zone = "Westfall"
HARNESS_FIRE_EVENT("ZONE_CHANGED_NEW_AREA")
HARNESS_ADVANCE(0.1)
Put("moved to Westfall", "watches", table.concat(watches, ","))
EQT.Set("filterEnabled", false)
EQT.Set("autoTrackZone", false)
EQT.Set("questWatchExperimental", false)
Pass("tools off (restored)")

-- Progress: sounds and announcements.
local played, said = {}, {}
CUI.PlaySoundPath = function(path, isFile) played[#played + 1] = tostring(path) .. (isFile and "f" or "") end
IsInRaid = function() return false end
IsInGroup = function(cat) return cat == LE_PARTY_CATEGORY_HOME end
GetQuestLink = function(id) return "[Q" .. id .. "]" end
C_ChatInfo.InChatMessagingLockdown = function() return false end
C_ChatInfo.SendChatMessage = function(msg, chan) said[#said + 1] = chan .. ":" .. msg end
EQT.Set("soundObjective", "peonyes1")
EQT.Set("soundQuest", "peoncomplete")
EQT.Set("announceProgress", true)
EQT.ApplyQuestProgress()
HARNESS_FIRE_EVENT("QUEST_LOG_UPDATE")
objectives[4] = { { numFulfilled = 2, numRequired = 2, finished = true, text = "Thing 2/2" }, { numFulfilled = 0, numRequired = 1, text = "Other 0/1" } }
HARNESS_FIRE_EVENT("QUEST_WATCH_UPDATE", 4)
HARNESS_FIRE_EVENT("QUEST_LOG_UPDATE")
objectives[4][2] = { numFulfilled = 1, numRequired = 1, finished = true, text = "Other 1/1" }
complete[4] = true
HARNESS_FIRE_EVENT("QUEST_WATCH_UPDATE", 4)
HARNESS_FIRE_EVENT("QUEST_LOG_UPDATE")
HARNESS_FIRE_EVENT("QUEST_REMOVED", 4)
Put("played", table.concat(played, ","))
Put("said", table.concat(said, " | "))
local _, names, order = EQT.Sounds()
Put("sound names", names.peonyes1, names.peoncomplete, #order > 0)

-- Objective colours.
local function Line(text, style)
    local fs = UIParent:CreateFontString(nil, "OVERLAY")
    fs:SetFont("Fonts/FRIZQT__.TTF", 12, "")
    fs:SetText(text)
    fs.colorStyle = style
    return { Text = fs }
end
local grey = { r = 0.6, g = 0.6, b = 0.6 }
local block = { id = 1, usedLines = { Line("Wolves 2/8", grey), header = Line("Title", grey) } }
objectives[1] = { { numFulfilled = 2, numRequired = 8, text = "Wolves 2/8" } }
Put("colors wanted (off)", EQT.ObjColorsWanted())
EQT.ColorObjectiveLines(block)
EQT.Set("objProgressColor", true)
EQT.ColorObjectiveLines(block)
local r, g, b = block.usedLines[1].Text:GetTextColor()
Put("progress colour", string.format("%.3f %.3f %.3f", r, g, b))
EQT.Set("objDimCompleted", true)
objectives[1] = { { numFulfilled = 8, numRequired = 8, finished = true, text = "Wolves 8/8" } }
block.usedLines[1].Text:SetText("Wolves 8/8")
EQT.ColorObjectiveLines(block)
local r2, g2, b2, a2 = block.usedLines[1].Text:GetTextColor()
Put("finished, dimmed", string.format("%.3f %.3f %.3f %.2f", r2, g2, b2, a2 or 1))
EQT.Set("objProgressColor", false)
EQT.Set("objDimCompleted", false)
EQT.ColorObjectiveLines(block)
local r3, g3, b3 = block.usedLines[1].Text:GetTextColor()
Put("restored", r3, g3, b3, "wanted", EQT.ObjColorsWanted())
Put("rgb", string.format("%.2f %.2f %.2f", EQT.ProgressRGB(0.25)), string.format("%.2f %.2f %.2f", EQT.ProgressRGB(0.75)))
