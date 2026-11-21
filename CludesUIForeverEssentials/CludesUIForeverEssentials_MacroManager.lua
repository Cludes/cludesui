if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
if not (CUI and CUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_MacroManager.lua  (WoW Forever only)
--  The Macro Manager's switch and /cuimacros. The editor is the "Macros" page
--  of the Forever Essentials options (CUI_ForeverEssentials_Macros_Options.lua,
--  its model CUI_ForeverEssentials_MacroModel_Options.lua), built with the
--  panel. CludesUIDB.macroManager holds only the switch: the game's macro
--  text is the macro.
-------------------------------------------------------------------------------
local _, module = ...

local F = module.Feature("macroManager", { enabled = false })

-- /cuimacros opens the page; registered at the first enable.
local slashDone
local function Apply()
    if slashDone or not F.Enabled() then return end
    slashDone = true
    SLASH_CUIMACROS1 = "/cuimacros"
    SlashCmdList.CUIMACROS = function()
        if F.Enabled() and not InCombatLockdown() then
            CUI:NavigateToElementSettings("CludesUIForeverEssentials", "Macros")
        end
    end
end

-- Options-page entry points.
CUI._MacroManager = { Enabled = F.Enabled, Cfg = F.Cfg, Apply = Apply }

F.Start(Apply)
