if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_SpecOverrides_Hooks.lua
--
--  The page hooks and the events.
--  Reads the earlier Spec Overrides files through CUI_NS._soInternals.
-------------------------------------------------------------------------------
local _, CUI_NS = ...
CUI_NS = CUI_NS.__cuiCoreNS or CUI_NS  -- standalone builds: the core's own table (CludesUI.lua)
local I = CUI_NS._soInternals
-- CludesUI_SpecOverrides.lua or an earlier Spec Overrides file failed to
-- load.
if not I or I.broken then return end
I.broken = true

local DeepCopy, GetStore, RunRefreshers = I.DeepCopy, I.GetStore, I.RunRefreshers
local PruneRedundantValues, RequestGoldWalk = I.PruneRedundantValues, I.RequestGoldWalk
local OnPageRebuilt, PruneOrphanEntries = I.OnPageRebuilt, I.PruneOrphanEntries
local SetCombatFolders, SetWatchResync = I.SetCombatFolders, I.SetWatchResync

-- This file's copies of shared names; Set<Name> keeps every copy current
-- (the lists are built at the end of CludesUI_SpecOverrides.lua).
local _combatFolders = nil
I.combatFoldersSetters[#I.combatFoldersSetters + 1] = function(v) _combatFolders = v end

-------------------------------------------------------------------------------
--  Hooks + events
-------------------------------------------------------------------------------
-- Golden borders + watcher seed-absorption on page changes. RefreshPage only
-- rebuilds rows when forced; the fast path neither seeds nor re-rows.
if CludesUI.SelectModule then
    hooksecurefunc(CludesUI, "SelectModule", OnPageRebuilt)
end
if CludesUI.SelectPage then
    hooksecurefunc(CludesUI, "SelectPage", OnPageRebuilt)
end
if CludesUI.RefreshPage then
    hooksecurefunc(CludesUI, "RefreshPage", function(_, force)
        if force then
            SetWatchResync(true)
        end
        RequestGoldWalk()
    end)
end


local evFrame = CreateFrame("Frame")
evFrame:RegisterEvent("PLAYER_LOGIN")
evFrame:RegisterEvent("PLAYER_REGEN_ENABLED") -- guardrails-allow: combat-deferral by Cludes: moved unchanged by the file split; multi-event frame (login, combat end)
evFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        -- De-alias repair for stores that banked live TABLE references, which aliased
        -- the store to the live profile (any later live edit silently mutated the
        -- stored "override"). DeepCopy every table-typed value once so stores own their
        -- data. Harvests skip table values, so it cannot recur.
        local function DeAlias(store)
            for _, e in ipairs(store or {}) do
                if e.values then
                    for _, m in pairs(e.values) do
                        if type(m) == "table" then
                            for fkey, v in pairs(m) do
                                if type(v) == "table" then m[fkey] = DeepCopy(v) end
                            end
                        end
                    end
                end
            end
        end
        DeAlias(GetStore())
        if CludesUI._CondOv then DeAlias(CludesUI._CondOv.GetStore()) end
        -- One-time tidy: drop orphaned entries plus fkeys no group holds a value for.
        PruneOrphanEntries()
        PruneRedundantValues()
        if CludesUI._CondOv then
            CludesUI._CondOv.PruneEntries()
            CludesUI._CondOv.PruneRedundant()
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if _combatFolders then
            local fl = _combatFolders
            SetCombatFolders(nil)
            RunRefreshers(fl)
        end
    end
end)

-- Logout: keep the current spec's stored values in sync with live edits so a
-- shared profile opened on another character applies fresh data. Also banks +
-- restores an active Editing-as session. Pre-logout, so the restored values
-- land before Lite strips db.profile into the saved copy and before sync pushes.
CludesUI.Lite.RegisterPreLogout(function()
    CludesUI.SpecOverrides_HarvestCurrent()
end)

I.broken = false
