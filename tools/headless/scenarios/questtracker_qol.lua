-- Quest Tracker > conveniences: auto accept / turn in through gossip, the
-- quest greeting and the quest pages (with Shift rules, trivial and
-- several-quest NPCs), event registration following the toggles, the quest
-- item hotkey (bound only while an item exists, cleared again, a binding
-- reset from elsewhere), and the splash frame's OnHide. Prints every call.
local CUI = rawget(_G, "CludesUI")
local mod = CUI._ModuleNS.CludesUIQuestTracker
local EQT = mod.EQT
local function Put(...)
    local t = { ... }
    for i = 1, select("#", ...) do t[i] = tostring(t[i]) end
    OUT:write("== ", table.concat(t, " "), "\n")
end
local shift, npc = false, "Creature-1"
IsShiftKeyDown = function() return shift end
UnitGUID = function(u) return u == "npc" and npc or "Player-1" end
local active, available = {}, {}
C_GossipInfo.GetActiveQuests = function() return active end
C_GossipInfo.GetAvailableQuests = function() local c = {} for i, q in ipairs(available) do c[i] = q end return c end
C_GossipInfo.SelectActiveQuest = function(id) Put("gossip turn in", id) end
C_GossipInfo.SelectAvailableQuest = function(id) Put("gossip accept", id) end
local greetActive, greetAvail = {}, {}
GetNumActiveQuests = function() return #greetActive end
GetActiveTitle = function(i) return "Q" .. i, greetActive[i] end
SelectActiveQuest = function(i) Put("greeting turn in", i) end
GetNumAvailableQuests = function() return #greetAvail end
GetAvailableQuestInfo = function(i) return greetAvail[i].trivial, nil, nil, nil, greetAvail[i].id end
SelectAvailableQuest = function(i) Put("greeting accept", i) end
GetQuestID = function() return 500 end
C_QuestLog.IsQuestTrivial = function() return false end
AcceptQuest = function() Put("accept page") end
IsQuestCompletable = function() return true end
local cost = 0
GetQuestMoneyToGet = function() return cost end
CompleteQuest = function() Put("complete page") end
local choices = 0
GetNumQuestChoices = function() return choices end
GetQuestReward = function(n) Put("take reward", n) end
C_PlayerInfo.IsPlayerInChromieTime = function() return false end
UnitLevel = function() return 80 end
GetMaxLevelForPlayerExpansion = function() return 80 end
GetQuestExpansion = function(id) return id == 77 and 3 or 10 end
GetServerExpansionLevel = function() return 10 end
local function Fire(e) HARNESS_FIRE_EVENT(e) end

Fire("GOSSIP_SHOW")
Put("off: nothing above")
EQT.Set("autoAccept", true)
EQT.Set("autoTurnIn", true)
EQT.SyncAutoQuests()
active = { { questID = 11, isComplete = false }, { questID = 12, isComplete = true } }
available = { { questID = 21 } }
Fire("GOSSIP_SHOW")
active = {}
Fire("GOSSIP_SHOW")
available = { { questID = 31 }, { questID = 32 } }
Fire("GOSSIP_SHOW")
available = { { questID = 33 } }
Fire("GOSSIP_SHOW")
Put("same npc after several: held")
npc = "Creature-2"
Fire("GOSSIP_SHOW")
EQT.Set("autoAcceptPreventMulti", false)
available = { { questID = 41, isTrivial = true }, { questID = 42 } }
EQT.Set("autoAcceptIgnoreTrivial", true)
Fire("GOSSIP_SHOW")
EQT.Set("autoAcceptIgnoreOldExpansion", true)
available = { { questID = 77 }, { questID = 78 } }
Fire("GOSSIP_SHOW")
shift = true
available = { { questID = 90 } }
Fire("GOSSIP_SHOW")
Put("shift skip: nothing")
EQT.Set("autoAcceptShiftEnable", true)
Fire("GOSSIP_SHOW")
shift = false
EQT.Set("autoAcceptShiftEnable", false)
greetActive = { false, true }
greetAvail = { { id = 5, trivial = false } }
Fire("QUEST_GREETING")
greetActive = {}
Fire("QUEST_GREETING")
Fire("QUEST_DETAIL")
Fire("QUEST_PROGRESS")
cost = 100
Fire("QUEST_PROGRESS")
Put("costs gold: not completed")
Fire("QUEST_COMPLETE")
choices = 3
Fire("QUEST_COMPLETE")
Put("three choices: not taken")
EQT.Set("enabled", false)
Fire("QUEST_DETAIL")
Put("tracker off: nothing")
EQT.Set("enabled", true)
EQT.Set("autoAccept", false)
EQT.Set("autoTurnIn", false)
EQT.SyncAutoQuests()
Fire("QUEST_DETAIL")
Put("toggles off: nothing")

-- The hotkey.
local logItem
C_QuestLog.GetNumQuestLogEntries = function() return 2 end
C_QuestLog.GetInfo = function(i) return i == 1 and { isHeader = true } or { questID = 600 } end
C_QuestLog.GetLogIndexForQuestID = function() return 2 end
C_QuestLog.GetQuestWatchType = function() return 0 end
GetQuestLogSpecialItemInfo = function() return logItem end
ClearOverrideBindings = function() Put("clear override") end
SetOverrideBindingClick = function(_, _, key, name, button) Put("override", key, name, button) end
EQT.Set("questItemHotkey", "F")
EQT.ApplyQuestItemHotkey()
Put("no item: item attr", EQT.qItemBtn:GetAttribute("item"))
logItem = "|cff|Hitem:1|h[Glowing Orb]|h|r"
Fire("QUEST_LOG_UPDATE")
Fire("QUEST_LOG_UPDATE")
HARNESS_ADVANCE(0.5)
Put("item attr", EQT.qItemBtn:GetAttribute("item"), EQT.qItemBtn:GetAttribute("type"))
Fire("QUEST_LOG_UPDATE")
HARNESS_ADVANCE(0.5)
Put("same item: no new override above")
HARNESS_ADVANCE(1)
Fire("UPDATE_BINDINGS")
logItem = nil
Fire("QUEST_REMOVED")
HARNESS_ADVANCE(0.5)
Put("item gone attr", EQT.qItemBtn:GetAttribute("item"))
EQT.Set("questItemHotkey", nil)
EQT.ApplyQuestItemHotkey()

-- The splash frame's replacement OnHide.
local splash = _G.SplashFrame
C_TalkingHead_SetConversationsDeferred = function(v) Put("talking head deferred", v) end
if splash and splash["\0scripts"] and splash["\0scripts"].OnHide then
    splash.screenInfo = { gameMenuRequest = true }
    splash["\0scripts"].OnHide(splash)
    Put("splash", splash.screenInfo, splash.showingQuestDialog)
else
    Put("no splash frame")
end
