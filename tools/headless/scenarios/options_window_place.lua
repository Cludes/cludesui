-- The options window keeps where it was dragged (CUI_NS.SavePanelPoint /
-- ApplyPanelPoint): saved as the centre's offset in screen units.
local CUI = rawget(_G, "CludesUI")
CUI:Show()
HARNESS_ADVANCE(0.2)
local main = CUI._mainFrame
local rel = main:GetEffectiveScale() / UIParent:GetEffectiveScale()
main:ClearAllPoints()
main:SetPoint("CENTER", UIParent, "CENTER", 200 / rel, 100 / rel)
-- The window's own drag handle: its drag stop saves the place.
local function DragStop(frame)
    for _, kid in ipairs({ frame:GetChildren() }) do
        local stop = kid:GetScript("OnDragStop")
        if stop then return stop(kid) end
        if DragStop(kid) ~= nil then return true end
    end
end
DragStop(main)
-- The fake client lays nothing out (GetCenter ignores anchors), so only the
-- save and a clean reopen show here; the real spot needs the game.
OUT:write("== saved a place: " .. tostring(CludesUIDB.panelPoint ~= nil) .. "\n")
CUI:Hide()
main:ClearAllPoints()
main:SetPoint("CENTER")
CUI:Show()
HARNESS_ADVANCE(0.2)
OUT:write("== reopened: " .. tostring(main:IsShown()) .. "\n")
