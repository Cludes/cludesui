if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if not (CludesUI and CludesUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_QuestAutomation.lua  (WoW Forever only)
--  Quest Automation, each part with its own switch:
--    Auto Accept     takes the quests an NPC offers.
--    Auto Turn In    hands in finished quests, and takes the reward when
--                    there is one or none to choose. With a choice of
--                    rewards it always stops and lets you pick.
--    Skip Grey       leaves quests far below your level (grey) alone.
--    Party Progress  says your objective progress ("Kobold Vermin slain:
--                    4/10") in party chat. Party only, never raid.
--  Hold Shift while talking to an NPC to do it all yourself.
-------------------------------------------------------------------------------
local _, module = ...

local F = module.Feature("questAutomation",
    { enabled = false, accept = true, turnIn = true, skipGrey = true, progress = false })
local Get, Enabled = F.Get, F.Enabled

local function Paused() return IsShiftKeyDown() end
local function Secret(v) return issecretvalue and issecretvalue(v) end

local ev = CreateFrame("Frame")

local function OnGossip()
    if Get("turnIn") then
        for _, q in ipairs(C_GossipInfo.GetActiveQuests() or {}) do
            if q.isComplete and q.questID then return C_GossipInfo.SelectActiveQuest(q.questID) end
        end
    end
    if Get("accept") then
        for _, q in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
            if q.questID and not (Get("skipGrey") and q.isTrivial) then
                return C_GossipInfo.SelectAvailableQuest(q.questID)
            end
        end
    end
end

-- The older quest greeting window (an NPC with only quests to offer).
local function OnGreeting()
    if Get("turnIn") then
        for i = 1, GetNumActiveQuests() do
            local _, complete = GetActiveTitle(i)
            if complete then return SelectActiveQuest(i) end
        end
    end
    if Get("accept") then
        for i = 1, GetNumAvailableQuests() do
            local trivial = IsAvailableQuestTrivial and IsAvailableQuestTrivial(i)
            if not (Get("skipGrey") and trivial) then return SelectAvailableQuest(i) end
        end
    end
end

local lastSaid = {}
ev:SetScript("OnEvent", function(_, event, a1, a2)
    if event == "UI_INFO_MESSAGE" then
        if not (Get("progress") and IsInGroup(LE_PARTY_CATEGORY_HOME) and not IsInRaid()) then return end
        local msg = a2
        if type(msg) ~= "string" or Secret(msg) then return end
        local done, need = msg:match(": (%d+)/(%d+)$")
        if not done then return end
        if lastSaid[msg] and GetTime() - lastSaid[msg] < 2 then return end
        lastSaid[msg] = GetTime()
        SendChatMessage(msg, "PARTY")
        return
    end
    if Paused() then return end
    if event == "GOSSIP_SHOW" then
        OnGossip()
    elseif event == "QUEST_GREETING" then
        OnGreeting()
    elseif event == "QUEST_DETAIL" then
        if Get("accept") and not (Get("skipGrey") and QuestIsTrivial and QuestIsTrivial()) then
            AcceptQuest()
        end
    elseif event == "QUEST_ACCEPT_CONFIRM" then
        -- An escort quest started by a group member.
        if Get("accept") then ConfirmAcceptQuest() end
    elseif event == "QUEST_PROGRESS" then
        if Get("turnIn") and IsQuestCompletable() then CompleteQuest() end
    elseif event == "QUEST_COMPLETE" then
        if Get("turnIn") and GetNumQuestChoices() <= 1 then GetQuestReward(GetNumQuestChoices()) end
    end
end)

local EVENTS = { "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_ACCEPT_CONFIRM",
                 "QUEST_PROGRESS", "QUEST_COMPLETE", "UI_INFO_MESSAGE" }

local function Apply()
    if Enabled() then
        for _, e in ipairs(EVENTS) do ev:RegisterEvent(e) end
    else
        ev:UnregisterAllEvents()
    end
end

CludesUI._QuestAutomation = { Get = Get, Cfg = F.Cfg, Apply = Apply }

F.Start(Apply)
