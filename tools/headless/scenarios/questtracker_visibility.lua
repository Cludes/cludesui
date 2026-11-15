-- Quest Tracker > visibility (retail, Blizzard's tracker): arenas and raids
-- (always / boss / never, an encounter starting and ending), suppression,
-- the visibility modes (shown, hidden, mouseover), the background (colour,
-- top line, empty and with content, M+), force on screen, combat, and the
-- mouseover proxy. Prints the tracker's and background's state at each step.
local CUI = rawget(_G, "CludesUI")
local mod = CUI._ModuleNS.CludesUIQuestTracker
local EQT = mod.EQT
local function Put(...)
    local t = { ... }
    for i = 1, select("#", ...) do t[i] = tostring(t[i]) end
    OUT:write("== ", table.concat(t, " "), "\n")
end
if mod.UseCustomTracker() then
    Put("custom tracker in use")
    return
end
local otf = _G.ObjectiveTrackerFrame
if not otf then
    Put("no tracker frame")
    return
end
local instance, combat, vis, mplus = "none", false, true, false
GetInstanceInfo = function() return "Somewhere", instance end
InCombatLockdown = function() return combat end
CUI.EvalVisibility = function() return vis end
C_ChallengeMode.IsChallengeModeActive = function() return mplus end
local mouse = {}
EQT.ApplyTrackerMouse = function(on) mouse[#mouse + 1] = tostring(on) end
local module = CreateFrame("Frame", nil, otf)
module.bottomSpacing = 10
module:Show()
otf.modules = { module }
local proxy, proxyGate
local reg = CUI.RegisterMouseoverTarget
CUI.RegisterMouseoverTarget = function(p, gate) proxy, proxyGate = p, gate end
local function State(label)
    local bg = rawget(_G, "CludesUIQTBackground")
    Put(label, "tracker", otf:IsShown(), otf:GetAlpha(), "bg", bg and bg:IsShown(), bg and bg:GetAlpha(),
        "mouse", table.concat(mouse, ","), "visible", EQT.TrackerIsVisible(otf))
    mouse = {}
end
local function Zone(kind)
    instance = kind
    HARNESS_FIRE_EVENT("ZONE_CHANGED_NEW_AREA")
end

EQT.InitVisibility()
HARNESS_ADVANCE(1)
State("start")
SNAP("visibility background", rawget(_G, "CludesUIQTBackground"))
Zone("arena")
State("arena")
Zone("raid")
State("raid boss mode, no encounter")
HARNESS_FIRE_EVENT("ENCOUNTER_START")
State("encounter")
combat = true
otf:Show()
State("encounter, Blizzard shows it in combat")
combat = false
HARNESS_FIRE_EVENT("ENCOUNTER_END")
State("encounter over")
EQT.Set("hideInRaidMode", "always")
EQT.UpdateVisibility()
State("raid always")
EQT.Set("hideInRaidMode", "never")
HARNESS_FIRE_EVENT("ENCOUNTER_START")
State("raid never, encounter")
HARNESS_FIRE_EVENT("PLAYER_ENTERING_WORLD")
EQT.Set("hideInRaidMode", "boss")
Zone("none")
State("open world")
_CUQT_SetSuppressed("probe", true)
State("suppressed")
_CUQT_SetSuppressed("probe", false)
State("released")
vis = false
EQT.UpdateVisibility()
State("hidden by mode")
vis = "mouseover"
EQT.UpdateVisibility()
State("mouseover idle")
if proxy then
    proxy:SetAlpha(1)
    proxy:Show()
    State("proxy reveal")
    proxy:Hide()
    State("proxy hide")
    Put("proxy gate", proxyGate and proxyGate(), "shown", proxy.IsShown())
end
vis = true
EQT.UpdateVisibility()
mplus = true
EQT.ResizeBGToContent()
State("mythic plus")
mplus = false
EQT.ResizeBGToContent()
module:Hide()
EQT.ResizeBGToContent()
State("content gone, held")
HARNESS_ADVANCE(0.5)
State("content gone, checked")
module:Show()
EQT.QueueResize()
EQT.QueueResize()
HARNESS_ADVANCE(0.2)
State("content back")
EQT.Set("bgR", 0.2)
EQT.Set("bgAlpha", 0.4)
EQT.Set("showTopLine", false)
EQT.ApplyBackground()
SNAP("visibility background restyled", rawget(_G, "CludesUIQTBackground"))
EQT.Set("forceOnScreen", false)
EQT.ApplyForceOnScreen()
Put("clamped", otf:IsClampedToScreen())
EQT.Set("forceOnScreen", true)
EQT.ApplyForceOnScreen()
Put("clamped", otf:IsClampedToScreen())
EQT.RefreshStateDriver()
State("state driver refresh")
