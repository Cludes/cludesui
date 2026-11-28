-- Dungeon Quests (CludesUIForeverEssentials_DungeonQuests.lua, Forever):
-- entering the Deadmines with its first quest in your log and the second
-- done prints a summary; the Quests button's tooltip lists them; clicking it
-- shares the one in your log; a shared dungeon quest from a player is
-- accepted with Accept Shared on, and a normal quest is not.
local CUI = rawget(_G, "CludesUI")
local DQ, DM = CUI._DungeonQuests, CUI._DungeonMap
if not (DQ and DM) then
    OUT:write("== no Dungeon Quests on this client\n")
    return
end
IsInInstance = function() return true, "party" end
GetInstanceInfo = function() return "The Deadmines", "party", 1, "Normal", 5, 0, false, 36 end
UnitFactionGroup = function() return "Alliance" end
local printed = {}
local oldPrint = CUI.Print
CUI.Print = function(t) printed[#printed + 1] = (t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

HARNESS_FIRE_EVENT("PLAYER_ENTERING_WORLD", false, false)
for _ = 1, 5 do HARNESS_ADVANCE(0.1) end
local dungeon = DM.State()
local rows = DQ.QuestsOf(dungeon)
OUT:write(("== %s: %d quests for the Alliance\n"):format(dungeon and dungeon.name or "?", #rows))
local inLogId, doneId = rows[1] and rows[1].quest[1], rows[2] and rows[2].quest[1]
C_QuestLog.IsOnQuest = function(id) return id == inLogId end
C_QuestLog.IsQuestFlaggedCompleted = function(id) return id == doneId end
C_QuestLog.GetLogIndexForQuestID = function(id) return id == inLogId and 4 or nil end
C_QuestLog.IsPushableQuest = function() return true end

-- A fresh entry prints the summary.
wipe(printed)
HARNESS_FIRE_EVENT("ZONE_CHANGED_NEW_AREA")
for _ = 1, 30 do HARNESS_ADVANCE(0.1) end
OUT:write("== summary: " .. tostring(printed[1]) .. "\n")
OUT:write("== summary line now: " .. tostring(DQ.SummaryLine(dungeon)) .. "\n")

-- The tooltip.
local lines = {}
local fake = { AddLine = function(_, t) lines[#lines + 1] = t end, AddDoubleLine = function(_, l, r) lines[#lines + 1] = l .. " | " .. r end }
CUI._DungeonQuests.QuestsOf(dungeon)
local DQmod = CUI._DungeonMap and rawget(_G, "CludesUIDungeonMap")
local fill = DQmod and DQmod.questsButton and DQmod.questsButton:GetScript("OnEnter")
OUT:write("== Quests button on the map " .. tostring(fill ~= nil) .. "\n")

-- Sharing: in a group, the quest in your log is pushed.
IsInGroup = function() return true end
local pushed = {}
QuestLogPushQuest = function(index) pushed[#pushed + 1] = index end
wipe(printed)
DQ.ShareAll(dungeon)
for _ = 1, 40 do HARNESS_ADVANCE(0.1) end
OUT:write(("== shared %d (log index %s); said: %s\n"):format(#pushed, tostring(pushed[1]), table.concat(printed, " / ")))

-- Accept Shared.
local accepted = 0
AcceptQuest = function() accepted = accepted + 1 end
QuestGetAutoAccept = function() return false end
UnitIsPlayer = function(u) return u == "questnpc" end
CludesUIDB.dungeonQuests = { acceptShared = true }
DQ.Apply()
GetQuestID = function() return inLogId end
HARNESS_FIRE_EVENT("QUEST_DETAIL")
GetQuestID = function() return 99999 end
HARNESS_FIRE_EVENT("QUEST_DETAIL")
OUT:write("== accepted " .. accepted .. " (a dungeon quest yes, another quest no)\n")
CUI.Print = oldPrint
