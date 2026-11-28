-- Switching a section's main toggle on or off: the rows that depend on it
-- (greyed while it is off) follow at once, without leaving the page.
-- Forever Tools > Questing: Quest Automation and its Auto Accept row.
local CUI = rawget(_G, "CludesUI")
if not CUI._QuestAutomation then
    OUT:write("== no Quest Automation on this client\n")
    return
end
CludesUIDB.questAutomation = CludesUIDB.questAutomation or {}
CUI._QuestAutomation.Cfg().enabled = false
CUI:SelectModule("CludesUIForeverEssentials")
CUI:SelectPage("Questing")

local function FindLabel(f, text, d)
    if d > 14 then return end
    for _, r in ipairs({ f:GetRegions() }) do
        if r.GetText and r:GetText() == text then return r end
    end
    for _, ch in ipairs({ f:GetChildren() }) do
        local hit = FindLabel(ch, text, d + 1)
        if hit then return hit end
    end
end
local function ToggleNear(label)
    for _, ch in ipairs({ label:GetParent():GetChildren() }) do
        if ch.GetScript and ch:GetScript("OnClick") then return ch end
    end
end
local master = FindLabel(CUI._scrollFrame, "Quest Automation", 0)
local accept = FindLabel(CUI._scrollFrame, "Auto Accept", 0)
local masterToggle = master and ToggleNear(master)
local acceptToggle = accept and ToggleNear(accept)
local function State(label)
    OUT:write(("== %s: Auto Accept label alpha %.1f, toggle alpha %.1f, clickable %s\n"):format(label,
        accept:GetAlpha(), acceptToggle:GetAlpha(), tostring(acceptToggle:IsMouseEnabled())))
end
State("Quest Automation off")
masterToggle:GetScript("OnClick")(masterToggle)
State("clicked on")
masterToggle:GetScript("OnClick")(masterToggle)
State("clicked off")
