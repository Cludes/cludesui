-- Waypoint Pin (CludesUIQoL_WaypointPin.lua): on, the game's icon, border
-- and distance text go to alpha 0 and our pin shows the tracked quest's
-- title, objectives and distance; at the screen edge only a smaller pin;
-- shapes; off puts the game's parts back.
local CUI = rawget(_G, "CludesUI")
local P = CUI._WaypointPin
OUT:write("== pin " .. tostring(P ~= nil) .. "\n")
if not P then return end

SuperTrackedFrame = CreateFrame("Frame", "SuperTrackedFrame", UIParent)
for _, k in ipairs({ "Icon", "IconBorder", "DistanceText", "Arrow" }) do
    SuperTrackedFrame[k] = SuperTrackedFrame:CreateTexture()
end
local clamped = false
C_Navigation = {
    HasValidScreenPosition = function() return true end,
    WasClampedToScreen = function() return clamped end,
    GetDistance = function() return 312.4 end,
}
Enum.SuperTrackingType = { Quest = 0, UserWaypoint = 1, Corpse = 2, Scenario = 3, Content = 4, PartyMember = 5 }
local kind = 0
C_SuperTrack.GetHighestPrioritySuperTrackingType = function() return kind end
C_SuperTrack.GetSuperTrackedQuestID = function() return 77 end
C_QuestLog.GetTitleForQuestID = function() return "Raptor Thieves" end
C_QuestLog.GetQuestObjectives = function()
    return { { text = "Raptor Head: 3/12", finished = false }, { text = "Done thing", finished = true } }
end

local function Parts()
    local t = {}
    for _, k in ipairs({ "Icon", "IconBorder", "DistanceText", "Arrow" }) do
        t[#t + 1] = k .. "=" .. tostring(SuperTrackedFrame[k]:GetAlpha())
    end
    return table.concat(t, " ")
end
local function State(tag)
    local pin = _G.CludesUIWaypointPin
    HARNESS_ADVANCE(0.2)
    OUT:write(("== %s: shown=%s title=%s dist=%s obj=%s scale=%s | %s\n"):format(tag, tostring(pin and pin:IsShown()),
        tostring(pin and pin.title:IsShown() and pin.title:GetText()), tostring(pin and pin.distance:IsShown() and pin.distance:GetText()),
        tostring(pin and pin.objectives:IsShown() and pin.objectives:GetText()), tostring(pin and pin:GetScale()), Parts()))
end

P.Cfg().enabled = true
P.Apply()
local pin = _G.CludesUIWaypointPin
pin:GetScript("OnUpdate")(pin, 0.2)
State("quest tracked")
clamped = true
pin:GetScript("OnUpdate")(pin, 0.2)
State("off screen")
clamped = false
kind = 1
HARNESS_FIRE_EVENT("SUPER_TRACKING_CHANGED")
pin:GetScript("OnUpdate")(pin, 0.2)
State("map pin")
P.Cfg().shape = "dot"
P.Apply()
OUT:write("== dot texture " .. tostring(pin.rim:GetTexture()) .. "\n")
P.Cfg().enabled = false
P.Apply()
State("off")
