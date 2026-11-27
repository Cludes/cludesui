-- A switched-off module's row (CludesUI_Panel.lua): a click offers to turn it
-- on (the power button's Enable & Reload ask) instead of doing nothing.
local CUI = rawget(_G, "CludesUI")
CUI:Show()
HARNESS_ADVANCE(0.2)
local row
for _, kid in ipairs({ CUI._addonScrollChild:GetChildren() }) do
    if kid._folder == "CludesUIMinimap" then row = kid end
end
row._notEnabled = true
row:GetScript("OnClick")(row)
HARNESS_ADVANCE(0.1)
local popup = rawget(_G, "CUIConfirmPopup")
OUT:write(("== click on a switched-off row: popup %s, title %s\n"):format(
    tostring(popup and popup:IsShown()), tostring(popup and popup._title and popup._title:GetText())))
