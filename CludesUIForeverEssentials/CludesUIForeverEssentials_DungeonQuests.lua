if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
if not (CUI and CUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_DungeonQuests.lua  (WoW Forever only)
--  Dungeon Quests: the quests for the dungeon you are in, from the Dungeon
--  Journal's quest list.
--    On entering    one chat line: how many are in your log, done, or still
--                   to pick up (and where the first of those is given), and
--                   the dungeon's level range when you are outside it.
--    Quests button  on the Dungeon Map's title bar. Hover it for the list;
--                   click it to share the ones in your log with your group,
--                   one at a time (each waits a moment so the group can
--                   answer, and sharing waits out combat).
--    Accept Shared  a dungeon quest a group member shares with you is
--                   accepted as it opens (off by default).
--  Quest rows: { id, name, level, side ("A", "H", "B"), shareable, where }.
-------------------------------------------------------------------------------
local _, module = ...

local F = module.Feature("dungeonQuests", { enabled = true, summary = true, acceptShared = false })
local Get, Enabled, Cfg = F.Get, F.Enabled, F.Cfg
local J = module.Journal

local QUEST_ID, QUEST_NAME, QUEST_LEVEL, QUEST_SIDE, QUEST_SHARE, QUEST_WHERE = 1, 2, 3, 4, 5, 6
local SIDE = { Alliance = "A", Horde = "H" }
local SHARE_GAP = 3 -- seconds between shares, for the group's answers
local TAG = "|cff4cc9f0Dungeon Quests:|r "

local function Say(text) CUI.Print(TAG .. text) end

local function ForMyFaction(quest)
    local side = quest[QUEST_SIDE]
    return side == "B" or side == SIDE[UnitFactionGroup("player") or ""]
end

-- Where a quest stands for you: "done", "log" or "todo".
local function Standing(id)
    if C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(id) then return "done" end
    if C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(id) then return "log" end
    return "todo"
end

-- The dungeon's quests for your faction, each with its standing.
local function QuestsOf(dungeon)
    if not dungeon then return {} end
    if J.Prepare then J.Prepare() end
    local list = dungeon.questInfo and dungeon.questInfo.quests or {}
    local out = {}
    for _, quest in ipairs(list) do
        if ForMyFaction(quest) then out[#out + 1] = { quest = quest, standing = Standing(quest[QUEST_ID]) } end
    end
    return out
end

local function Tally(rows)
    local inLog, done, todo, firstTodo = 0, 0, 0, nil
    for _, row in ipairs(rows) do
        if row.standing == "log" then
            inLog = inLog + 1
        elseif row.standing == "done" then
            done = done + 1
        else
            todo = todo + 1
            firstTodo = firstTodo or row.quest
        end
    end
    return inLog, done, todo, firstTodo
end

-------------------------------------------------------------------------------
--  Sharing, one quest at a time
-------------------------------------------------------------------------------
local queue, sharing = {}, false
local shareFrame = CreateFrame("Frame")

local ShareNext
function ShareNext()
    if InCombatLockdown() then
        shareFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    local quest = table.remove(queue, 1)
    if not quest then
        sharing = false
        Say("done sharing.")
        return
    end
    if not IsInGroup() then
        wipe(queue)
        sharing = false
        Say("stopped: you are not in a group.")
        return
    end
    local index = C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(quest[QUEST_ID])
    if index and QuestLogPushQuest then QuestLogPushQuest(index) end
    C_Timer.After(SHARE_GAP, ShareNext)
end

shareFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    if sharing then ShareNext() end
end)

local function ShareAll(dungeon)
    if not IsInGroup() then
        Say("join a group to share quests.")
        return
    end
    if sharing then
        Say("already sharing.")
        return
    end
    wipe(queue)
    local names = {}
    for _, row in ipairs(QuestsOf(dungeon)) do
        local quest = row.quest
        local pushable = not C_QuestLog.IsPushableQuest or C_QuestLog.IsPushableQuest(quest[QUEST_ID])
        if row.standing == "log" and quest[QUEST_SHARE] and pushable then
            queue[#queue + 1] = quest
            names[#names + 1] = quest[QUEST_NAME]
        end
    end
    if #queue == 0 then
        Say("none of your quests for this dungeon can be shared.")
        return
    end
    sharing = true
    Say("sharing " .. table.concat(names, ", ") .. ".")
    ShareNext()
end

-------------------------------------------------------------------------------
--  The tooltip for the Dungeon Map's Quests button
-------------------------------------------------------------------------------
local STANDING_TEXT = { done = "|cff60d080done|r", log = "|cffffd060in your log|r", todo = "|cffa3adb5not picked up|r" }

local function FillTooltip(tooltip, dungeon)
    tooltip:AddLine("Dungeon Quests", 1, 1, 1)
    local rows = QuestsOf(dungeon)
    if #rows == 0 then
        tooltip:AddLine("The Journal has no quests for this dungeon.", 0.64, 0.68, 0.71, true)
        return
    end
    for _, row in ipairs(rows) do
        local quest = row.quest
        tooltip:AddDoubleLine(("%d  %s"):format(quest[QUEST_LEVEL] or 0, quest[QUEST_NAME]), STANDING_TEXT[row.standing], 1, 1, 1)
        if row.standing == "todo" and quest[QUEST_WHERE] then tooltip:AddLine("   " .. quest[QUEST_WHERE], 0.55, 0.6, 0.65, true) end
    end
    local inLog = Tally(rows)
    tooltip:AddLine(" ")
    tooltip:AddLine(inLog > 0 and "Click to share the ones in your log with your group." or "None in your log to share.", 0.4, 0.9, 0.5, true)
end

-------------------------------------------------------------------------------
--  Entering, and accepting shared dungeon quests
-------------------------------------------------------------------------------
local dungeonQuestIds
local function IsDungeonQuest(id)
    if not dungeonQuestIds then
        dungeonQuestIds = {}
        for _, entry in ipairs(J.QuestData or {}) do
            for _, quest in ipairs(entry.quests or {}) do
                dungeonQuestIds[quest[QUEST_ID]] = true
            end
        end
    end
    return dungeonQuestIds[id] == true
end

local lastSummary
-- "(levels 17-26, you are 14)" when you are outside the dungeon's range.
local function LevelNote(dungeon)
    local levels = dungeon.levels
    local low, high = levels and levels[1], levels and levels[#levels]
    local mine = UnitLevel("player")
    if not (low and high and mine) or (mine >= low and mine <= high) then return "" end
    return (" (levels %d-%d, you are %d)"):format(low, high, mine)
end

local function SummaryLine(dungeon)
    local rows = QuestsOf(dungeon)
    local levelNote = LevelNote(dungeon)
    if #rows == 0 then return levelNote ~= "" and (dungeon.name .. levelNote .. ".") or nil end
    local inLog, done, todo, firstTodo = Tally(rows)
    local parts = {}
    if inLog > 0 then parts[#parts + 1] = (inLog == 1 and "1 quest" or inLog .. " quests") .. " in your log" end
    if todo > 0 then parts[#parts + 1] = todo .. " you have not picked up" end
    if done > 0 and inLog == 0 and todo == 0 then parts[#parts + 1] = "all done" end
    local line = dungeon.name .. levelNote .. ": " .. table.concat(parts, ", ") .. "."
    if inLog == 0 and firstTodo and firstTodo[QUEST_WHERE] then line = line .. " " .. firstTodo[QUEST_NAME] .. " is given at " .. firstTodo[QUEST_WHERE] .. "." end
    return line
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
    if event == "QUEST_DETAIL" then
        if not Get("acceptShared") then return end
        if not (UnitIsPlayer("questnpc") and IsDungeonQuest(GetQuestID())) then return end
        if QuestGetAutoAccept and QuestGetAutoAccept() then CloseQuest() else AcceptQuest() end
        return
    end
    -- Entering a dungeon: one summary line per dungeon visit, read a moment
    -- later so the Dungeon Map has worked out where you are.
    C_Timer.After(2, function()
        local DM = CUI._DungeonMap
        local dungeon = DM and DM.State and DM.State()
        local inside = IsInInstance()
        if not inside then
            lastSummary = nil
            return
        end
        if not (dungeon and Get("summary")) or lastSummary == dungeon then return end
        lastSummary = dungeon
        local line = SummaryLine(dungeon)
        if line then Say(line) end
    end)
end)

local function Apply()
    events:UnregisterAllEvents()
    if not Enabled() then return end
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    events:RegisterEvent("QUEST_DETAIL")
end

module.DungeonQuests = { FillTooltip = FillTooltip, ShareAll = ShareAll, QuestsOf = QuestsOf }
CUI._DungeonQuests = {
    Get = Get,
    Cfg = Cfg,
    Apply = Apply,
    SummaryLine = SummaryLine,
    QuestsOf = QuestsOf,
    ShareAll = ShareAll,
    IsDungeonQuest = IsDungeonQuest,
}

F.Start(Apply)
