-- Ctrl+F in the options window (CludesUI_Panel.lua) focuses the settings search.
local CUI = rawget(_G, "CludesUI")
CUI:Show()
HARNESS_ADVANCE(0.2)
local focused = false
local box = CUI._sidebarSearchBox
local setFocus = box.SetFocus
box.SetFocus = function(self) focused = true end
IsControlKeyDown = function() return true end
CUI._mainFrame:GetScript("OnKeyDown")(CUI._mainFrame, "F")
OUT:write("== ctrl+F focuses the search: " .. tostring(focused) .. "\n")
box.SetFocus = setFocus
