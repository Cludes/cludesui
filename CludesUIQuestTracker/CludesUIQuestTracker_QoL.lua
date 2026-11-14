if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
-- CludesUIQuestTracker_QoL.lua
--
-- QoL layer: auto-accept, auto-turn-in, quest-item hotkey, SplashFrame
-- taint-free OnHide clone. Everything here is combat-gated.
--
-- Ported verbatim from the previous custom tracker:
--   * Auto-accept / auto-turn-in event machine (source L3421-3495)
--   * SplashFrame taint fix (source L3132-3150) -- intentional SetScript,
--     replaces Blizzard's OnHide with a clone that drops the
--     ObjectiveTrackerFrame:Update() call that taints Quest Button +
--     money frames downstream.
--   * Quest-item hotkey via SecureActionButton (source L3531-3708)
-------------------------------------------------------------------------------
local _, mod = ...
local EQT = mod.EQT
local function Cfg(k)
    return EQT.Cfg(k)
end

-------------------------------------------------------------------------------
-- SplashFrame taint fix. This is the one intentional SetScript in this
-- addon -- we are replacing Blizzard's OnHide body because calling
-- ObjectiveTrackerFrame:Update() from it taints downstream secure frames.
-------------------------------------------------------------------------------
local function InstallSplashFrameFix()
    local scrollFrame = _G.SplashFrame
    if not scrollFrame then
        return
    end
    scrollFrame:SetScript("OnHide", function(widget)
        local fromGameMenu = widget.screenInfo and widget.screenInfo.gameMenuRequest
        widget.screenInfo = nil
        if C_TalkingHead_SetConversationsDeferred then
            C_TalkingHead_SetConversationsDeferred(false)
        end
        if _G.AlertFrame and _G.AlertFrame.SetAlertsEnabled then
            _G.AlertFrame:SetAlertsEnabled(true, "splashFrame")
        end
        -- ObjectiveTrackerFrame:Update() intentionally omitted (causes taint)
        if fromGameMenu and not widget.showingQuestDialog and not InCombatLockdown() then
            if _G.GameMenuFrame then
                ShowUIPanel(_G.GameMenuFrame)
            end
        end
        widget.showingQuestDialog = nil
    end)
end

-------------------------------------------------------------------------------
-- Auto-accept / auto-turn-in
-------------------------------------------------------------------------------
-- Blizzard's trivial flag never fires for a quest that scales to the player,
-- so quests from an earlier expansion have a toggle of their own. Leveling
-- (below max level or in Chromie Time) runs through older content, so that
-- toggle waits for max level; WoW Forever has no older expansions.
local function IsIgnoredQuest(questID, isTrivial)
    if isTrivial and Cfg("autoAcceptIgnoreTrivial") then
        return true
    end
    if not Cfg("autoAcceptIgnoreOldExpansion") or not questID or questID == 0 then
        return false
    end
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

-- Hold Shift to Enable runs the feature only while Shift is down; Hold Shift
-- to Skip runs it only while Shift is up. prefix is "autoAccept" or "autoTurnIn".
local function ShiftAllows(prefixText)
    if Cfg(prefixText .. "ShiftEnable") then
        return IsShiftKeyDown()
    end
    if Cfg(prefixText .. "ShiftSkip") then
        return not IsShiftKeyDown()
    end
    return true
end

local function InstallAutoQuests()
    local autoFrame = CreateFrame("Frame")
    local autoPreventNPCGUID = nil
    -- Deliberately NOT enrolled in EQT._eventFrames, so the raid/arena/M+
    -- suspension leaves it alone. That suspension exists to stop skin and
    -- layout work while the tracker is hidden; this frame does neither, it
    -- answers quest NPC dialogs, so Auto Accept / Auto Turn In keep working
    -- while the tracker is hidden.
    autoFrame:SetScript("OnEvent", function(_, evt, ...)
        if Cfg("enabled") == false then
            return
        end

        if evt == "GOSSIP_SHOW" then
            if C_GossipInfo then
                if Cfg("autoTurnIn") and ShiftAllows("autoTurnIn") and C_GossipInfo.GetActiveQuests then
                    local isActive = C_GossipInfo.GetActiveQuests()
                    if isActive then
                        for _, quest in ipairs(isActive) do
                            if quest.questID and quest.isComplete then
                                C_GossipInfo.SelectActiveQuest(quest.questID)
                                return
                            end
                        end
                    end
                end
                if Cfg("autoAccept") and C_GossipInfo.GetAvailableQuests then
                    if not ShiftAllows("autoAccept") then
                        return
                    end
                    local available = C_GossipInfo.GetAvailableQuests()
                    if available then
                        for idx = #available, 1, -1 do
                            if IsIgnoredQuest(available[idx].questID, available[idx].isTrivial) then
                                table.remove(available, idx)
                            end
                        end
                    end
                    if available and #available > 0 then
                        local npcGUID = UnitGUID("npc")
                        if Cfg("autoAcceptPreventMulti") then
                            if #available > 1 then
                                autoPreventNPCGUID = npcGUID
                            end
                            if autoPreventNPCGUID == npcGUID then
                                -- do nothing; let user pick manually
                            elseif available[1].questID then
                                C_GossipInfo.SelectAvailableQuest(available[1].questID)
                                return
                            end
                        elseif available[1].questID then
                            C_GossipInfo.SelectAvailableQuest(available[1].questID)
                            return
                        end
                    end
                end
            end
            return
        end

        -- The quest greeting: an NPC with quests and no gossip lists them as
        -- Current Quests and Available Quests (common on WoW Forever). The same
        -- order as the gossip above, by the greeting's own indexes.
        if evt == "QUEST_GREETING" then
            if Cfg("autoTurnIn") and ShiftAllows("autoTurnIn") then
                for idx = 1, GetNumActiveQuests() do
                    local _, isComplete = GetActiveTitle(idx)
                    if isComplete then
                        SelectActiveQuest(idx)
                        return
                    end
                end
            end
            if Cfg("autoAccept") and ShiftAllows("autoAccept") then
                local first, total = nil, 0
                for idx = 1, GetNumAvailableQuests() do
                    local isTrivial, _, _, _, questID = GetAvailableQuestInfo(idx)
                    if not IsIgnoredQuest(questID, isTrivial) then
                        total = total + 1
                        first = first or idx
                    end
                end
                if first then
                    if Cfg("autoAcceptPreventMulti") then
                        local npcGUID = UnitGUID("npc")
                        if total > 1 then
                            autoPreventNPCGUID = npcGUID
                        end
                        if autoPreventNPCGUID ~= npcGUID then
                            SelectAvailableQuest(first)
                        end
                    else
                        SelectAvailableQuest(first)
                    end
                end
            end
            return
        end

        -- QUEST_AUTOCOMPLETE handling removed: calling ShowQuestComplete() from addon
        -- execution runs Blizzard's quest-complete panel flow (ShowUIPanel, UIPanel
        -- attribute writes on WorldMapFrame) under our taint, and that state is read by
        -- every later map open -- confirmed in tester taint logs as blocked map-pin
        -- calls in combat. Blizzard's native auto-quest popup in the tracker covers
        -- this securely: the player clicks it, and if the reward has no choice, the
        -- QUEST_COMPLETE auto-turn-in below still fires.

        if evt == "QUEST_DETAIL" then
            if not Cfg("autoAccept") then
                return
            end
            if not ShiftAllows("autoAccept") then
                return
            end
            local questID = GetQuestID()
            if IsIgnoredQuest(questID, C_QuestLog.IsQuestTrivial(questID)) then
                return
            end
            AcceptQuest()
        elseif evt == "QUEST_PROGRESS" then
            -- A turn-in that asks for items shows this page (Continue) before
            -- the reward page. One that costs gold stays with the player, as
            -- Blizzard asks before taking it.
            if not Cfg("autoTurnIn") then
                return
            end
            if not ShiftAllows("autoTurnIn") then
                return
            end
            if IsQuestCompletable() and (GetQuestMoneyToGet() or 0) == 0 then
                CompleteQuest()
            end
        elseif evt == "QUEST_COMPLETE" then
            if not Cfg("autoTurnIn") then
                return
            end
            if not ShiftAllows("autoTurnIn") then
                return
            end
            local numChoices = GetNumQuestChoices()
            if numChoices <= 1 then
                GetQuestReward(numChoices)
            end
        end
    end)

    -- The dialog events are registered only while Auto Accept or Auto Turn In
    -- is on; their toggles and profile swaps call this.
    local registered = false
    function EQT.SyncAutoQuests()
        local wanted = (Cfg("autoAccept") or Cfg("autoTurnIn")) and true or false
        if wanted == registered then
            return
        end
        registered = wanted
        if wanted then
            autoFrame:RegisterEvent("QUEST_DETAIL")
            autoFrame:RegisterEvent("QUEST_PROGRESS")
            autoFrame:RegisterEvent("QUEST_COMPLETE")
            autoFrame:RegisterEvent("GOSSIP_SHOW")
            autoFrame:RegisterEvent("QUEST_GREETING")
        else
            autoFrame:UnregisterEvent("QUEST_DETAIL")
            autoFrame:UnregisterEvent("QUEST_PROGRESS")
            autoFrame:UnregisterEvent("QUEST_COMPLETE")
            autoFrame:UnregisterEvent("GOSSIP_SHOW")
            autoFrame:UnregisterEvent("QUEST_GREETING")
        end
    end
    EQT.SyncAutoQuests()
end

-------------------------------------------------------------------------------
-- Quest-item hotkey. SecureActionButton (type="item") carrying the player's
-- current quest item, reached by an OVERRIDE binding on the chosen key.
--
-- The button has to stay secure. Using an item is a protected action, and the
-- dedicated quest API, UseQuestLogSpecialItem, is itself protected, so there
-- is no insecure route to this: a plain button calling it is simply blocked.
--
-- The key used to travel through the GLOBAL binding table instead:
-- SetBinding(key, "CUI_QUESTITEM") plus SaveBindings, with a restricted
-- snippet reading GetBindingKey back out to build the click binding.
-- CUI_QUESTITEM was never declared in a Bindings.xml, so no such binding
-- command exists for the client to execute, and the round trip also took the
-- key away from whatever the player had bound there and wrote that to their
-- saved bindings. Override bindings avoid both: they execute a click on our
-- button directly, and they never touch anything persistent.
-------------------------------------------------------------------------------
local function ScanForQuestItem()
    if not C_QuestLog then
        return nil
    end
    local num = C_QuestLog.GetNumQuestLogEntries() or 0
    local fallback = nil
    for idx = 1, num do
        local details = C_QuestLog.GetInfo(idx)
        if details and not details.isHeader and details.questID then
            local logIdx = C_QuestLog.GetLogIndexForQuestID
                    and C_QuestLog.GetLogIndexForQuestID(details.questID)
                or idx
            local itemLink = GetQuestLogSpecialItemInfo(logIdx)
            if itemLink then
                local name = itemLink:match("%[(.-)%]")
                if name then
                    local wt = C_QuestLog.GetQuestWatchType and C_QuestLog.GetQuestWatchType(details.questID)
                    if wt ~= nil then
                        return name
                    end
                    fallback = fallback or name
                end
            end
        end
    end
    return fallback
end

-- One-time repair for profiles that ran the SetBinding version below. That
-- binding can never do anything, but it was written to the player's SAVED
-- bindings, so it sits there holding a key hostage until something clears it.
local _legacyCleared = false
local function ClearLegacyQuestItemBinding()
    if _legacyCleared or InCombatLockdown() then
        return
    end
    if not (GetBindingKey and SetBinding) then
        return
    end
    _legacyCleared = true
    local k1, k2 = GetBindingKey("CUI_QUESTITEM")
    if not (k1 or k2) then
        return
    end
    if k1 then
        SetBinding(k1)
    end
    if k2 then
        SetBinding(k2)
    end
    local bindingSet = GetCurrentBindingSet and GetCurrentBindingSet()
    if SaveBindings and bindingSet and bindingSet >= 1 and bindingSet <= 2 then
        SaveBindings(bindingSet)
    end
end

local function InstallQuestItemHotkey()
    -- The button stays a SecureActionButton with type="item": quest items are
    -- ordinary bag items as far as using them goes, and the dedicated
    -- UseQuestLogSpecialItem API is PROTECTED, so a plain button calling it
    -- would be blocked. What was broken was never the use, it was the key.
    local qItemBtn = CreateFrame("Button", "CUI_QuestItemHotkeyBtn", UIParent, "SecureActionButtonTemplate")
    qItemBtn:SetSize(32, 32)
    qItemBtn:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    qItemBtn:SetAlpha(0)
    qItemBtn:EnableMouse(false)
    -- BOTH phases, and this is load-bearing rather than defensive.
    -- SecureActionButton_OnClick runs the action only when the click phase
    -- matches the player's "cast on key down" preference:
    --     useOnKeyDown = SecureActionButton_ShouldUseOnKeyDown(self)
    --                    -- attribute, else the ActionButtonUseKeyDown CVar
    --     clickAction  = (down and useOnKeyDown)
    --                    or (not down and not useOnKeyDown)
    -- Registered for up only, OnClick can never fire with down == true, so
    -- for anyone playing with cast-on-key-down the test is false every time
    -- and the action is silently discarded. The binding is created, the
    -- attributes are right, the click is delivered, and nothing happens --
    -- which is exactly how this presented. Register both and let the secure
    -- handler pick the phase; it fires the action for precisely one of them.
    qItemBtn:RegisterForClicks("AnyDown", "AnyUp")

    local function InitSecureAttributes()
        qItemBtn:SetAttribute("type", "item")
    end
    if InCombatLockdown() then
        mod.CombatQueue.Defer("QuestItemInit", function()
            InitSecureAttributes()
            if EQT.ApplyQuestItemHotkey then
                EQT.ApplyQuestItemHotkey()
            end
        end)
    else
        InitSecureAttributes()
    end

    EQT.qItemBtn = qItemBtn

    -- The key the override is currently laid down on, or nil for "none".
    -- _bindingDirty is tracked SEPARATELY and deliberately: nil has to mean
    -- "bound to nothing", not "state unknown". Folding the two together meant
    -- that after an external invalidation, losing the quest item compared
    -- nil == nil, skipped ClearOverrideBindings, and left a priority override
    -- sitting on a button with no item -- eating the key for good, which is
    -- the exact failure the want/_boundKey check exists to avoid.
    local _boundKey = nil
    local _bindingDirty = true
    -- Our own binding writes raise UPDATE_BINDINGS. Re-applying from inside
    -- that event is a self-feeding loop, and a plain "did anything change"
    -- test cannot break it because the invalidation arrives after the write.
    -- Ignore the event for a short window after we write instead; a genuine
    -- external clear inside that window is picked up by the next quest event
    -- or by PLAYER_REGEN_ENABLED.
    local _selfWriteUntil = 0

    local function ApplyBinding()
        -- Binding writes are combat-restricted; PLAYER_REGEN_ENABLED replays.
        if InCombatLockdown() then
            return
        end
        local key = Cfg("questItemHotkey")
        if key == "" then
            key = nil
        end
        -- Bind only while a quest item actually exists. An override outranks
        -- the player's own binding for that key, so holding it while there is
        -- nothing to use would silently eat the key.
        local wanted = (key and qItemBtn:GetAttribute("item")) and key or nil
        if not _bindingDirty and wanted == _boundKey then
            return
        end
        _bindingDirty = false
        _selfWriteUntil = GetTime() + 0.5
        if ClearOverrideBindings then
            ClearOverrideBindings(qItemBtn)
        end
        if wanted and SetOverrideBindingClick then
            SetOverrideBindingClick(qItemBtn, true, wanted, "CUI_QuestItemHotkeyBtn", "LeftButton")
        end
        _boundKey = wanted
    end

    local cachedName = nil
    local dirty = true

    local function UpdateQuestItemAttribute()
        if InCombatLockdown() then
            return
        end
        -- The gate belongs HERE, on the scan, not only on the quest-event
        -- branch that used to carry it. PLAYER_REGEN_ENABLED reaches this
        -- through the force entry point, so with the gate further out every
        -- combat drop paid a full quest-log walk -- the allocation peak the
        -- coalescer below exists to avoid -- for players who never set a
        -- hotkey. ApplyBinding still runs either way, so unbinding still
        -- clears.
        if not Cfg("questItemHotkey") then
            return
        end
        if not dirty then
            return
        end
        dirty = false
        local found = ScanForQuestItem()
        if found ~= cachedName then
            cachedName = found
            qItemBtn:SetAttribute("item", found)
            -- Gaining or losing the item flips whether the key should be bound
            -- at all, so the binding has to follow the scan.
            ApplyBinding()
        end
    end
    EQT.UpdateQuestItemAttribute = UpdateQuestItemAttribute

    -- Options entry point. It must force a rescan, not just re-apply: the
    -- event-driven scan is skipped entirely while no hotkey is configured, so
    -- the very first bind would otherwise apply against a stale item.
    local function ApplyQuestItemHotkey()
        if InCombatLockdown() then
            return
        end
        dirty = true
        -- Force the binding too, not just the scan. Without this the entry
        -- point cannot re-lay an override something else wiped: the state
        -- would compare equal and take the early-out.
        _bindingDirty = true
        UpdateQuestItemAttribute()
        ApplyBinding()
    end
    EQT.ApplyQuestItemHotkey = ApplyQuestItemHotkey

    -- Loot-storm coalescer (memory pass 2026-08-03): QUEST_LOG_UPDATE fires in bursts
    -- on loot/objective progress, and each fire paid a full quest log scan -- an info
    -- table per log entry, the suite's single-frame allocation peak (~106KB in one
    -- frame). One deferred scan per burst instead; the scan keeps its own dirty/combat
    -- gates, so a burst that ends in combat parks on dirty and the existing
    -- PLAYER_REGEN_ENABLED path picks it up. Prebuilt closure: no per-burst allocation.
    local scanPending = false
    local function FlushQuestItemScan()
        scanPending = false
        UpdateQuestItemAttribute()
    end

    local qItemFrame = CreateFrame("Frame")
    qItemFrame:RegisterEvent("QUEST_LOG_UPDATE")
    qItemFrame:RegisterEvent("QUEST_ACCEPTED")
    qItemFrame:RegisterEvent("QUEST_REMOVED")
    qItemFrame:RegisterEvent("QUEST_TURNED_IN")
    qItemFrame:RegisterEvent("UPDATE_BINDINGS")
    qItemFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    -- Deliberately NOT enrolled in EQT._eventFrames, so the raid/arena/M+
    -- suspension leaves it alone. That suspension exists to stop skin and
    -- layout work while the tracker is hidden; this frame does neither, it
    -- owns a keybind.
    --
    -- Enrolling it was actively harmful. The dominant suspension trigger is
    -- ENCOUNTER_START, which fires IN COMBAT, and binding writes are
    -- combat-restricted -- so the override could not be cleared on the way in,
    -- and unregistering PLAYER_REGEN_ENABLED removed the one event that could
    -- have cleared it on the way out. The result was a priority override
    -- parked on the player's key for the whole encounter, pointing at a
    -- button whose item attribute was frozen where the scan stopped.
    --
    -- The scan it drives is already gated on a hotkey being configured and
    -- coalesced to one pass per burst, so leaving it registered costs nothing
    -- for anyone who has not set a key.
    qItemFrame:SetScript("OnEvent", function(_, evt)
        if InCombatLockdown() then
            return
        end
        if evt == "PLAYER_REGEN_ENABLED" then
            -- Also the recovery path for a /reload taken in combat, where the
            -- init timer bailed before it could run.
            ClearLegacyQuestItemBinding()
            ApplyQuestItemHotkey()
            return
        end
        if evt == "UPDATE_BINDINGS" then
            -- Ours, echoing back: ignore, or we re-enter forever.
            if GetTime() < _selfWriteUntil then
                return
            end
            -- Someone else rewrote the binding table. LoadBindings, which the
            -- settings panel runs on cancel and on a binding-set switch,
            -- clears every override, so waiting for the tracked item to change
            -- before re-applying could leave the hotkey dead indefinitely.
            _bindingDirty = true
            ApplyBinding()
            return
        end
        if not Cfg("questItemHotkey") then
            return
        end
        dirty = true
        if not scanPending then
            scanPending = true
            C_Timer.After(0.3, FlushQuestItemScan)
        end
    end)

    C_Timer.After(1.5, function()
        if InCombatLockdown() then
            return
        end
        ClearLegacyQuestItemBinding()
        ApplyQuestItemHotkey()
    end)
end

-------------------------------------------------------------------------------
-- Entry point
-------------------------------------------------------------------------------
function EQT.InitQoL()
    InstallSplashFrameFix()
    InstallAutoQuests()
    InstallQuestItemHotkey()
    -- WoW Forever's quest tools (CludesUIQuestTracker_Forever.lua; nil on retail).
    if EQT.ApplyQuestWatches then
        EQT.ApplyQuestWatches()
    end
    if EQT.ApplyQuestProgress then
        EQT.ApplyQuestProgress()
    end
    if EQT.ApplyQuestLinks then
        EQT.ApplyQuestLinks()
    end
end
