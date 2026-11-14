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

-- Every confirm option.
CUI:ShowConfirmPopup({ title = "Remember", message = "Use this for every character?", checkbox = "Don't ask again", onConfirm = function() end })
SNAP("confirm checkbox", rawget(_G, "CUIConfirmPopup"))
CUI:ShowConfirmPopup({ title = "Import", message = "Import this layout?", scaleWarning = "Made at a different UI scale.", disclaimer = "Your current layout is replaced.", onConfirm = function() end })
SNAP("confirm warning", rawget(_G, "CUIConfirmPopup"))
CUI:ShowConfirmPopup({ title = "Delete", message = "Delete every profile?", typeToConfirm = "delete", onConfirm = function() end })
SNAP("confirm type gate", rawget(_G, "CUIConfirmPopup"))
CUI:ShowConfirmPopup({ title = "Wait", message = "Not yet.", confirmDisabled = true, modal = true, onConfirm = function() end })
SNAP("confirm disabled modal", rawget(_G, "CUIConfirmPopup"))
-- Clicking confirm runs the callback and closes; a handle closes only its own request.
local ran = 0
CUI:ShowConfirmPopup({ title = "Run", message = "Run it?", onConfirm = function() ran = ran + 1 end })
local f = rawget(_G, "CUIConfirmPopup")
f._confirmBtn:GetScript("OnClick")(f._confirmBtn)
local h1 = CUI:ShowConfirmPopup({ title = "First", message = "1", onConfirm = function() end })
local h2 = CUI:ShowConfirmPopup({ title = "Second", message = "2", onConfirm = function() end })
CUI:CloseConfirmPopup(h1)
local still = rawget(_G, "CUIConfirmDimmer"):IsShown()
CUI:CloseConfirmPopup(h2)
OUT:write("== behaviour ran=", ran, " stale-handle-left-open=", tostring(still), " closed=", tostring(not rawget(_G, "CUIConfirmDimmer"):IsShown()), "\n")

-- Input dialog options.
local function Input()
    for _, f in ipairs({ UIParent:GetChildren() }) do
        if f.__name and f.__name:find("Input") and f:IsShown() then return f end
    end
end
CUI:ShowInputPopup({ title = "Zone", message = "Name a zone.", extraButton = { text = "Add Current Zone" }, warning = "Names are case sensitive.", onConfirm = function() end })
SNAP("input extra+warning", Input())
CUI:ShowInputPopup({ title = "Import", message = "Paste the string.", redWarning = "Made at a different UI scale.", checkbox = "Keep my layout", validate = function() end, onConfirm = function() end })
SNAP("input red+checkbox+validate", Input())
CUI:ShowInputPopup({ title = "Copy", message = "Copy this link.", initialText = "https://example.invalid", selectText = true, hideCancel = true, onConfirm = function() end })
SNAP("input copy", Input())
