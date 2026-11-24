-- Changed here (CludesUI_ChangedHere.lua): open Global Settings, flip a
-- toggle and move a slider through their row accessors: the footer button
-- reads "Changed here (2)", the list shows old -> new for each; Undo on one
-- puts it back, Undo All the rest; a page switch starts that page's own list.
local CUI = rawget(_G, "CludesUI")
local CH = CUI._ChangedHere
OUT:write("== loaded " .. tostring(CH ~= nil) .. "\n")
if not CH then return end
CUI:Show()
CUI:SelectModule("_CUIGlobal")
HARNESS_TICK(0.6)
local slots = CH.Slots()
OUT:write("== slots on page: " .. #slots .. " of " .. tostring(#CH.Slots()) .. " (" .. tostring(CUI:GetActiveModule()) .. ")\n")
local toggle, slider
for _, s in ipairs(slots) do
    if not toggle and s.cfg.type == "toggle" and type(s.values[1]) == "boolean" then toggle = s end
    if not slider and s.cfg.type == "slider" and type(s.values[1]) == "number" then slider = s end
end
OUT:write(("== picked toggle %s, slider %s\n"):format(toggle and toggle.label or "-", slider and slider.label or "-"))
local function Chip()
    local chip
    for _, kid in ipairs({ CUI._footerBar:GetChildren() }) do
        local ok, text = pcall(function() return kid:GetText() end)
        if ok and text and tostring(text):find("Changed here") then chip = kid end
    end
    return chip
end
if toggle then toggle.cfg.setValue(not toggle.values[1]) end
if slider then slider.cfg.setValue((slider.cfg.min or 0) + (slider.cfg.step or 1)) end
HARNESS_TICK(0.6)
local chip = Chip()
OUT:write("== chip: " .. tostring(chip and chip:IsShown() and chip:GetText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) .. "\n")
if not chip then return end
chip:GetScript("OnClick")(chip)
local changed = CH.Changed()
for _, s in ipairs(changed) do OUT:write("   " .. s.label .. "\n") end
SNAP("changed here list", chip)
CH.Undo(changed[1])
HARNESS_TICK(0.6)
OUT:write("== after one undo: " .. #CH.Changed() .. " | chip " .. tostring(chip:IsShown()) .. "\n")
CH.UndoAll(CH.Changed())
HARNESS_TICK(0.6)
OUT:write("== after undo all: " .. #CH.Changed() .. " | chip shown " .. tostring(chip:IsShown()) .. "\n")
CUI:SelectModule("CludesUIActionBars")
HARNESS_TICK(0.6)
OUT:write("== action bars page: " .. #CH.Slots() .. " settings read, " .. #CH.Changed() .. " changed\n")
