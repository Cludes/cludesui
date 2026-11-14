-- Dialogs: confirm (two buttons, one button, disclaimer), the info dialog
-- (short and long), the input dialog; each button resting, hovered, and back.
local CUI = rawget(_G, "CludesUI")

local function Buttons(label, f)
    for _, name in ipairs({ "_cancelBtn", "_confirmBtn" }) do
        local b = f and f[name]
        if b then
            b:GetScript("OnEnter")(b)
            SETTLE(b, 20, 0.02)
            SNAP(label .. name .. " hovered", b)
            b:GetScript("OnLeave")(b)
            SETTLE(b, 20, 0.02)
            SNAP(label .. name .. " rested", b)
        end
    end
end

CUI:ShowConfirmPopup({ title = "Reset Settings", message = "Reset every setting to its default?", onConfirm = function() end })
SNAP("confirm", rawget(_G, "CUIConfirmPopup"))
Buttons("confirm", rawget(_G, "CUIConfirmPopup"))

CUI:ShowConfirmPopup({ title = "Done", message = "One button only.", hideCancel = true, onConfirm = function() end })
SNAP("confirm one button", rawget(_G, "CUIConfirmPopup"))

CUI:ShowConfirmPopup({ title = "Uninstall", message = "Remove CludesUI's settings?", disclaimer = "This cannot be undone.", onConfirm = function() end })
SNAP("confirm disclaimer", rawget(_G, "CUIConfirmPopup"))

CUI:ShowInfoPopup({ title = "Export Failed", content = "Could not build the export string." })
SNAP("info short", rawget(_G, "CUIInfoPopup"))
CUI:ShowInfoPopup({ title = "Long", content = string.rep("A long line of text. ", 60) })
SNAP("info long", rawget(_G, "CUIInfoPopup"))

CUI:ShowInputPopup({ title = "New Profile", message = "Name the new profile.", onConfirm = function() end })
local input
for _, f in ipairs({ UIParent:GetChildren() }) do
    if f.__name and f.__name:find("Input") then input = f end
end
SNAP("input", input)
