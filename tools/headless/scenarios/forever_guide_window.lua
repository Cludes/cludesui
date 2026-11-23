-- Guide Window (CludesUIForeverEssentials_GuideWindow.lua) against a stand-in
-- RestedXP: heading with its range, progress, the active step's objectives
-- (count colours, a done one faded), the next steps, shift-click skipping
-- and going to a step, RestedXP's frames faded while on and back when off.
local CUI = rawget(_G, "CludesUI")
local G = CUI._GuideWindow
OUT:write("== guide " .. tostring(G ~= nil) .. "\n")
if not G then return end

local steps = {}
for i = 1, 20 do steps[i] = {} end
local wentTo
local rxpFrame = CreateFrame("Frame", nil, UIParent)
rxpFrame:SetAlpha(1)
rxpFrame:EnableMouse(true)
RXPV2GuideWindow = { frame = rxpFrame }
RXP = {
    currentGuide = { title = "12-14 The Barrens", steps = steps },
    GetGuideProgress = function() return 5 end,
    RXPFrame = {
        activeSteps = {
            { active = true, index = 5, elements = {
                { text = "Kill Raptors 3/8", tag = "kill" },
                { text = "Collect Plainstrider Beaks 8/8", tag = "collect" },
                { text = "Talk to Duokna", tag = "talk", completed = true },
            } },
        },
        DropDownMenu = function() end,
    },
    SetStep = function(i) wentTo = i end,
    v2 = {
        IsGuideWindowEnabled = function() return true end,
        BuildGuideStepsSnapshot = function()
            return { rows = { { index = 6, text = "Fly to the Crossroads" }, { index = 7, text = "Turn in Raptor Thieves" } } }
        end,
        UpdateGuideWindow = function() end,
    },
    icons = {},
    player = { name = "Bob" },
}
local shift = false
IsShiftKeyDown = function() return shift end

G.Cfg().enabled = true
G.Apply()
HARNESS_ADVANCE(0.1)
local win = _G.CludesUIGuideWindow
local function Dump(tag)
    local out = {}
    local function Walk(f)
        for _, r in ipairs({ f:GetRegions() }) do
            if r.GetText and r:IsShown() and r:GetText() and r:GetText() ~= "" then
                local cr, cg = r:GetTextColor()
                out[#out + 1] = r:GetText() .. (cg and cg > 0.75 and cr < 0.5 and " [green]" or "")
            end
        end
        for _, ch in ipairs({ f:GetChildren() }) do
            if ch:IsShown() then Walk(ch) end
        end
    end
    if win and win:IsShown() then Walk(win) end
    OUT:write(("== %s: shown=%s rxpAlpha=%s rxpMouse=%s | %s\n"):format(tag, tostring(win and win:IsShown()),
        tostring(rxpFrame:GetAlpha()), tostring(rxpFrame:IsMouseEnabled()), table.concat(out, " / ")))
end
Dump("on")

-- Shift-click the active step: the guide moves on (SetStep 6).
local box
for _, ch in ipairs({ win:GetChildren() }) do
    if ch.step then box = ch end
end
box:GetScript("OnClick")(box, "LeftButton")
OUT:write("== click without shift: wentTo=" .. tostring(wentTo) .. "\n")
shift = true
box:GetScript("OnClick")(box, "LeftButton")
OUT:write("== shift-click active: wentTo=" .. tostring(wentTo) .. "\n")
local nextRow
for _, ch in ipairs({ win:GetChildren() }) do
    if ch.index == 7 then nextRow = ch end
end
nextRow:GetScript("OnClick")(nextRow, "LeftButton")
OUT:write("== shift-click step 7: wentTo=" .. tostring(wentTo) .. "\n")

G.Cfg().folded = true
G.Apply()
HARNESS_ADVANCE(0.1)
Dump("folded")
G.Cfg().folded = nil
G.Cfg().enabled = false
G.Apply()
Dump("off")
