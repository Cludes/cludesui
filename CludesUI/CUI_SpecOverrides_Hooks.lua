if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_SpecOverrides_Hooks.lua
--
--  The page hooks and the events.
--  Reads the earlier Spec Overrides files through CUI_NS._soInternals.
-------------------------------------------------------------------------------
local _, CUI_NS = ...
CUI_NS = CUI_NS.__cuiCoreNS or CUI_NS -- standalone builds: the core's own table (CludesUI.lua)
local Inner = CUI_NS._soInternals
-- CludesUI_SpecOverrides.lua or an earlier Spec Overrides file failed to
-- load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local DeepCopy, GetStore, RunRefreshers = Inner.DeepCopy, Inner.GetStore, Inner.RunRefreshers
local PruneRedundantValues, RequestGoldWalk = Inner.PruneRedundantValues, Inner.RequestGoldWalk
local OnPageRebuilt, PruneOrphanEntries = Inner.OnPageRebuilt, Inner.PruneOrphanEntries
local SetCombatFolders, SetWatchResync = Inner.SetCombatFolders, Inner.SetWatchResync

-- This file's copies of shared names; Set<Name> keeps every copy current
-- (the lists are built at the end of CludesUI_SpecOverrides.lua).
local _combatFolders = nil
Inner.combatFoldersSetters[#Inner.combatFoldersSetters + 1] = function(val)
    _combatFolders = val
end

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
evFrame:SetScript("OnEvent", function(_, evt)
    if evt == "PLAYER_LOGIN" then
        -- De-alias repair for stores that banked live TABLE references, which aliased
        -- the store to the live profile (any later live edit silently mutated the
        -- stored "override"). DeepCopy every table-typed value once so stores own their
        -- data. Harvests skip table values, so it cannot recur.
        local function DeAlias(storage)
            for _, entry in ipairs(storage or {}) do
                if entry.values then
                    for _, m in pairs(entry.values) do
                        if type(m) == "table" then
                            for fkey, val in pairs(m) do
                                if type(val) == "table" then
                                    m[fkey] = DeepCopy(val)
                                end
                            end
                        end
                    end
                end
            end
        end
        DeAlias(GetStore())
        if CludesUI._CondOv then
            DeAlias(CludesUI._CondOv.GetStore())
        end
        -- One-time tidy: drop orphaned entries plus fkeys no group holds a value for.
        PruneOrphanEntries()
        PruneRedundantValues()
        if CludesUI._CondOv then
            CludesUI._CondOv.PruneEntries()
            CludesUI._CondOv.PruneRedundant()
        end
    elseif evt == "PLAYER_REGEN_ENABLED" then
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

Inner.broken = false
