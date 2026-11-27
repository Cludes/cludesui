-- Opening the options in combat (CUI.AfterCombat, CludesUI.lua): a note in
-- chat, then the window opens when combat ends.
local CUI = rawget(_G, "CludesUI")
local printed = {}
local print0 = CUI.Print
CUI.Print = function(msg) printed[#printed + 1] = tostring(msg) end
local combat = true
InCombatLockdown = function() return combat end
SlashCmdList.CUIOPTIONS("fonts")
HARNESS_ADVANCE(0.2)
local box = CUI._sidebarSearchBox
OUT:write(("== in combat: open %s, note %s\n"):format(tostring(box and box:IsVisible() or false), tostring(printed[1])))
combat = false
HARNESS_FIRE_EVENT("PLAYER_REGEN_ENABLED")
HARNESS_ADVANCE(0.2)
box = CUI._sidebarSearchBox
OUT:write(("== combat over: open %s, search %q\n"):format(tostring(box and box:IsVisible() or false), tostring(box and box:GetText())))
CUI.Print = print0
