if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUIQuestTracker_QoL.lua - the quest conveniences.
--
--  Auto accept and auto turn-in, the quest item hotkey, and a replacement for
--  the splash frame's OnHide. Everything here waits out combat. These frames
--  are deliberately not suspended with the tracker in raids, arenas and M+
--  (EQT._eventFrames): that suspension stops skin and layout work while the
--  tracker is hidden, and these neither draw nor lay out.
-------------------------------------------------------------------------------
local _, mod = ...
local EQT = mod.EQT
local Cfg = EQT.Cfg

-------------------------------------------------------------------------------
--  The splash frame (what's-new screen). Blizzard's OnHide calls
--  ObjectiveTrackerFrame:Update(), which taints the quest item buttons and
--  money frames after it. This is the one deliberate SetScript on a
--  Blizzard frame in this addon: the same OnHide without that call.
-------------------------------------------------------------------------------
local function ReplaceSplashOnHide()
    local splash = _G.SplashFrame
    if not splash then return end
    splash:SetScript("OnHide", function(self)
        local fromGameMenu = self.screenInfo and self.screenInfo.gameMenuRequest
        self.screenInfo = nil
        if C_TalkingHead_SetConversationsDeferred then C_TalkingHead_SetConversationsDeferred(false) end
        if _G.AlertFrame and _G.AlertFrame.SetAlertsEnabled then
            _G.AlertFrame:SetAlertsEnabled(true, "splashFrame")
        end
        -- (ObjectiveTrackerFrame:Update() left out on purpose: it taints.)
        if fromGameMenu and not self.showingQuestDialog and not InCombatLockdown() and _G.GameMenuFrame then
            ShowUIPanel(_G.GameMenuFrame)
        end
        self.showingQuestDialog = nil
    end)
end

-------------------------------------------------------------------------------
--  Auto accept / auto turn-in
-------------------------------------------------------------------------------
-- Quests to leave alone: trivial ones (if set), and (if set) ones from an
-- earlier expansion. Blizzard never marks a quest that scales to the player
-- as trivial, hence the second toggle. Levelling (below max level, or in
-- Chromie Time) goes through old content, so that toggle waits for max
-- level; WoW Forever has no older expansions.
local function Skipped(questID, trivial)
    if trivial and Cfg("autoAcceptIgnoreTrivial") then return true end
    if not Cfg("autoAcceptIgnoreOldExpansion") or not questID or questID == 0 then return false end
    if
        CludesUI.IS_FOREVER
        or C_PlayerInfo.IsPlayerInChromieTime()
        or UnitLevel("player") < GetMaxLevelForPlayerExpansion()
    then
        return false
    end
    local expansion = GetQuestExpansion(questID)
    return expansion ~= nil and expansion >= 0 and expansion < GetServerExpansionLevel()
end

-- "Hold Shift to Enable" works only while Shift is down; "Hold Shift to
-- Skip" only while it is up. feature: "autoAccept" or "autoTurnIn".
local function ShiftAllows(feature)
    if Cfg(feature .. "ShiftEnable") then return IsShiftKeyDown() end
    if Cfg(feature .. "ShiftSkip") then return not IsShiftKeyDown() end
    return true
end

local function TurningIn() return Cfg("autoTurnIn") and ShiftAllows("autoTurnIn") end
local function Accepting() return Cfg("autoAccept") and ShiftAllows("autoAccept") end

local DIALOG_EVENTS = { "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "GOSSIP_SHOW", "QUEST_GREETING" }

local function InstallAutoQuests()
    local listener = CreateFrame("Frame")
    -- "Only one quest at a time": an NPC that offered several is left to the
    -- player from then on.
    local heldNPC

    -- With several quests on offer (or an NPC already held), the player picks.
    local function HoldsBack(count)
        if not Cfg("autoAcceptPreventMulti") then return false end
        local npc = UnitGUID("npc")
        if count > 1 then heldNPC = npc end
        return heldNPC == npc
    end

    local function OnGossip()
        if not C_GossipInfo then return end
        -- A finished quest first.
        if Cfg("autoTurnIn") and ShiftAllows("autoTurnIn") and C_GossipInfo.GetActiveQuests then
            for _, quest in ipairs(C_GossipInfo.GetActiveQuests() or {}) do
                if quest.questID and quest.isComplete then
                    C_GossipInfo.SelectActiveQuest(quest.questID)
                    return
                end
            end
        end
        if not (Cfg("autoAccept") and C_GossipInfo.GetAvailableQuests) or not ShiftAllows("autoAccept") then
            return
        end
        local offered = C_GossipInfo.GetAvailableQuests()
        if offered then
            for i = #offered, 1, -1 do
                if Skipped(offered[i].questID, offered[i].isTrivial) then table.remove(offered, i) end
            end
        end
        if offered and #offered > 0 and not HoldsBack(#offered) and offered[1].questID then
            C_GossipInfo.SelectAvailableQuest(offered[1].questID)
        end
    end

    -- The quest greeting: an NPC with quests but no gossip (common on WoW
    -- Forever), with Current and Available Quests by the greeting's own
    -- indexes. The same order as gossip.
    local function OnGreeting()
        if TurningIn() then
            for i = 1, GetNumActiveQuests() do
                local _, complete = GetActiveTitle(i)
                if complete then
                    SelectActiveQuest(i)
                    return
                end
            end
        end
        if not Accepting() then return end
        local first, count = nil, 0
        for i = 1, GetNumAvailableQuests() do
            local trivial, _, _, _, questID = GetAvailableQuestInfo(i)
            if not Skipped(questID, trivial) then
                count = count + 1
                first = first or i
            end
        end
        if first and not HoldsBack(count) then SelectAvailableQuest(first) end
    end

    -- QUEST_AUTOCOMPLETE is not handled: ShowQuestComplete() from addon code
    -- runs Blizzard's quest-complete panel (ShowUIPanel, attribute writes on
    -- WorldMapFrame) under our taint, and every later map open reads that
    -- state (testers' taint logs showed blocked map-pin calls in combat).
    -- Blizzard's own auto-quest popup does it securely: the player clicks it,
    -- and a reward with no choice is still taken on QUEST_COMPLETE below.
    local HANDLERS = {
        GOSSIP_SHOW = OnGossip,
        QUEST_GREETING = OnGreeting,
        QUEST_DETAIL = function()
            if Accepting() then
                local questID = GetQuestID()
                if not Skipped(questID, C_QuestLog.IsQuestTrivial(questID)) then AcceptQuest() end
            end
        end,
        -- A turn-in asking for items shows this page (Continue) before the
        -- rewards. One that costs gold is left to the player, as Blizzard asks.
        QUEST_PROGRESS = function()
            if TurningIn() and IsQuestCompletable() and (GetQuestMoneyToGet() or 0) == 0 then
                CompleteQuest()
            end
        end,
        -- Only with no reward to choose between.
        QUEST_COMPLETE = function()
            if TurningIn() then
                local choices = GetNumQuestChoices()
                if choices <= 1 then GetQuestReward(choices) end
            end
        end,
    }
    listener:SetScript("OnEvent", function(_, event)
        if Cfg("enabled") ~= false then HANDLERS[event]() end
    end)

    -- The dialog events are listened to only while either feature is on;
    -- their toggles and profile switches call this.
    local listening = false
    function EQT.SyncAutoQuests()
        local want = (Cfg("autoAccept") or Cfg("autoTurnIn")) and true or false
        if want == listening then return end
        listening = want
        for _, event in ipairs(DIALOG_EVENTS) do
            if want then
                listener:RegisterEvent(event)
            else
                listener:UnregisterEvent(event)
            end
        end
    end
    EQT.SyncAutoQuests()
end

-------------------------------------------------------------------------------
--  The quest item hotkey: a secure item button holding the current quest
--  item, clicked by an override binding on the chosen key.
--
--  It must be secure: using an item is protected, and so is the quest API
--  for it (UseQuestLogSpecialItem), so a plain button would just be blocked.
--  The key used to go through the global binding table (SetBinding(key,
--  "CUI_QUESTITEM") and SaveBindings), but CUI_QUESTITEM was never declared
--  in a Bindings.xml, so it could never do anything, and it took the key from
--  whatever the player had bound there and saved that. An override binding
--  clicks our button directly and saves nothing.
-------------------------------------------------------------------------------
-- The name of a quest item in the log, preferring a tracked quest's.
local function FindQuestItem()
    if not C_QuestLog then return nil end
    local untracked
    for i = 1, C_QuestLog.GetNumQuestLogEntries() or 0 do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and info.questID then
            local logIndex = C_QuestLog.GetLogIndexForQuestID
                    and C_QuestLog.GetLogIndexForQuestID(info.questID)
                or i
            local link = GetQuestLogSpecialItemInfo(logIndex)
            local name = link and link:match("%[(.-)%]")
            if name then
                local tracked = C_QuestLog.GetQuestWatchType and C_QuestLog.GetQuestWatchType(info.questID)
                if tracked ~= nil then return name end
                untracked = untracked or name
            end
        end
    end
    return untracked
end

-- Once: profiles that ran the SetBinding version have that dead binding in
-- their SAVED bindings, holding a key until something clears it.
local legacyChecked = false
local function ClearLegacyBinding()
    if legacyChecked or InCombatLockdown() or not (GetBindingKey and SetBinding) then return end
    legacyChecked = true
    local first, second = GetBindingKey("CUI_QUESTITEM")
    if not (first or second) then return end
    if first then SetBinding(first) end
    if second then SetBinding(second) end
    local set = GetCurrentBindingSet and GetCurrentBindingSet()
    if SaveBindings and set and set >= 1 and set <= 2 then SaveBindings(set) end
end

local function InstallQuestItemHotkey()
    local button = CreateFrame("Button", "CUI_QuestItemHotkeyBtn", UIParent, "SecureActionButtonTemplate")
    button:SetSize(32, 32)
    button:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    button:SetAlpha(0)
    button:EnableMouse(false)
    -- Both phases, and this matters: the secure click runs the action only
    -- when the phase matches the player's cast-on-key-down choice (the
    -- button's useOnKeyDown attribute, else the ActionButtonUseKeyDown CVar).
    -- Registered for up only, a key-down player's press would arrive, match
    -- nothing, and do nothing at all. With both, the handler fires for
    -- exactly one.
    button:RegisterForClicks("AnyDown", "AnyUp")

    local function SetType() button:SetAttribute("type", "item") end
    if InCombatLockdown() then
        mod.CombatQueue.Defer("QuestItemInit", function()
            SetType()
            if EQT.ApplyQuestItemHotkey then EQT.ApplyQuestItemHotkey() end
        end)
    else
        SetType()
    end
    EQT.qItemBtn = button

    -- The key the override is on (nil = none). Whether that is still true is
    -- kept apart (bindingStale), so nil keeps meaning "bound to nothing":
    -- folded together, losing the item after an outside reset compared nil
    -- with nil, skipped the clear, and left an override eating the key.
    local boundKey
    local bindingStale = true
    -- Our own binding writes raise UPDATE_BINDINGS; acting on that would loop
    -- (the event arrives after the write, so "did it change" cannot tell).
    -- It is ignored for a moment after we write; an outside reset in that
    -- moment is caught by the next quest event or the end of combat.
    local quietUntil = 0

    local function Bind()
        -- Binding writes are not allowed in combat; its end replays this.
        if InCombatLockdown() then return end
        local key = Cfg("questItemHotkey")
        if key == "" then key = nil end
        -- Bound only while there is a quest item: the override outranks the
        -- player's own binding of that key, so with nothing to use it would
        -- just eat the key.
        local want = (key and button:GetAttribute("item")) and key or nil
        if not bindingStale and want == boundKey then return end
        bindingStale = false
        quietUntil = GetTime() + 0.5
        if ClearOverrideBindings then ClearOverrideBindings(button) end
        if want and SetOverrideBindingClick then
            SetOverrideBindingClick(button, true, want, "CUI_QuestItemHotkeyBtn", "LeftButton")
        end
        boundKey = want
    end

    local itemName
    local scanNeeded = true

    local function Rescan()
        if InCombatLockdown() then return end
        -- Gated here, on the scan itself: the end of combat comes through
        -- here too, and with the gate further out every combat end walked
        -- the whole quest log for players who never set a key.
        if not Cfg("questItemHotkey") or not scanNeeded then return end
        scanNeeded = false
        local found = FindQuestItem()
        if found ~= itemName then
            itemName = found
            button:SetAttribute("item", found)
            -- Gaining or losing the item decides whether the key is bound.
            Bind()
        end
    end
    EQT.UpdateQuestItemAttribute = Rescan

    -- The options' entry point: a fresh scan (none runs while no key is set,
    -- so the first bind would see a stale item) and a fresh binding (so it
    -- can lay an override back that something else removed).
    local function Apply()
        if InCombatLockdown() then return end
        scanNeeded = true
        bindingStale = true
        Rescan()
        Bind()
    end
    EQT.ApplyQuestItemHotkey = Apply

    -- QUEST_LOG_UPDATE comes in bursts on loot and objective progress, and
    -- each scan builds a table per log entry (the suite's biggest one-frame
    -- allocation, about 106KB): one scan per burst instead. A burst ending in
    -- combat leaves scanNeeded set for the end of combat.
    local scanQueued = false
    local function QueuedScan()
        scanQueued = false
        Rescan()
    end

    local listener = CreateFrame("Frame")
    for _, event in ipairs({
        "QUEST_LOG_UPDATE",
        "QUEST_ACCEPTED",
        "QUEST_REMOVED",
        "QUEST_TURNED_IN",
        "UPDATE_BINDINGS",
        "PLAYER_REGEN_ENABLED",
    }) do
        listener:RegisterEvent(event)
    end
    -- Not suspended with the tracker either, and that one was harmful: the
    -- main suspension trigger, ENCOUNTER_START, fires in combat, when the
    -- override cannot be cleared, and suspending removed the end of combat,
    -- the one event that could clear it. The override then sat on the
    -- player's key all encounter. The scan is gated on a key being set and
    -- runs once per burst, so staying registered costs nothing without one.
    listener:SetScript("OnEvent", function(_, event)
        if InCombatLockdown() then return end
        if event == "PLAYER_REGEN_ENABLED" then
            -- Also how a /reload taken in combat (its start-up timer gave up) recovers.
            ClearLegacyBinding()
            Apply()
        elseif event == "UPDATE_BINDINGS" then
            -- Our own write echoing back: ignore it, or it loops.
            if GetTime() < quietUntil then return end
            -- Something else rewrote the bindings. LoadBindings (the settings
            -- panel's cancel, a binding-set switch) clears every override, so
            -- waiting for the item to change could leave the key dead.
            bindingStale = true
            Bind()
        elseif Cfg("questItemHotkey") then
            scanNeeded = true
            if not scanQueued then
                scanQueued = true
                C_Timer.After(0.3, QueuedScan)
            end
        end
    end)

    C_Timer.After(1.5, function()
        if not InCombatLockdown() then
            ClearLegacyBinding()
            Apply()
        end
    end)
end

-------------------------------------------------------------------------------
--  Start-up
-------------------------------------------------------------------------------
function EQT.InitQoL()
    ReplaceSplashOnHide()
    InstallAutoQuests()
    InstallQuestItemHotkey()
    -- WoW Forever's quest tools (CludesUIQuestTracker_Forever.lua; nil on retail).
    if EQT.ApplyQuestWatches then EQT.ApplyQuestWatches() end
    if EQT.ApplyQuestProgress then EQT.ApplyQuestProgress() end
    if EQT.ApplyQuestLinks then EQT.ApplyQuestLinks() end
end
