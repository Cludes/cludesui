local addonName, mod = ...
if mod.standalone then return end
-------------------------------------------------------------------------------
--  Tank Kit has no settings window of its own. Its settings are the Tank Kit
--  pages of the CludesUI panel (CludesUIOptions/CUI_Tank_Options.lua). This
--  file is the small bridge the rest of the module calls.
-------------------------------------------------------------------------------
mod.Options = {}

function mod.Options:Initialize() end

--- Opens the Tank Kit pages of the CludesUI panel.
function mod.Options:Open()
    if InCombatLockdown() then
        mod.Print("Settings cannot be opened in combat.")
        return
    end
    -- One tick later: the first open loads the settings addon and builds the
    -- whole panel, which is too much work for a click or slash handler.
    C_Timer.After(0, function()
        if InCombatLockdown() then return end
        if CludesUI.EnsureOptionsLoaded and not CludesUI.EnsureOptionsLoaded() then return end
        CludesUI:ShowModule(addonName)
    end)
end

--- Called when test mode or the frame lock changes outside the panel (a slash
--- command): repaints the Tank Kit page if it is the one on screen.
function mod.Options:SyncTestButton()
    local main = CludesUI._mainFrame
    if not (main and main:IsShown()) then return end
    if CludesUI.GetActiveModule and CludesUI:GetActiveModule() == addonName and CludesUI.RefreshPage then
        CludesUI:RefreshPage(true)
    end
end
