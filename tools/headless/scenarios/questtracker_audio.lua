-- Quest Tracker > voice-over bridge (WoW Forever, our tracker): with a stub
-- of the voice-over addon, rows for voiced and silent quests, a row reused
-- for another quest (bound again) and the same quest (not), a settings
-- change (asks again), and a failing call turning the bridge off.
local CUI = rawget(_G, "CludesUI")
local mod = CUI._ModuleNS.CludesUIQuestTracker
local function Put(...)
    local t = { ... }
    for i = 1, select("#", ...) do t[i] = tostring(t[i]) end
    OUT:write("== ", table.concat(t, " "), "\n")
end
if not CUI.IS_FOREVER then
    Put("retail: no bridge")
    return
end
mod.UseCustomTracker = function() return true end
local voicedSet, binds, asks, fail = { [1] = true, [3] = true }, {}, 0, false
local callbacks = {}
local ui = {
    ShowsTrackerButton = function(_, id) asks = asks + 1 if fail then error("boom") end return voicedSet[id] end,
    BindPlayButton = function(_, b, id, title, origin) binds[#binds + 1] = id .. ":" .. title .. ":" .. origin b.questID = id end,
    SetPlayButtonState = function() end,
    FollowQueue = function() end,
    UpdateTrackerButtons = function() end,
}
VoiceOver = { QuestOverlayUI = ui }
Spoken = {
    DressBoxButton = function(_, b) b.SetBox = function(self, box, w, h) self.box = box .. w .. "x" .. h end end,
    RegisterCallback = function(_, name, fn) callbacks[name] = fn end,
}
C_QuestLog.GetTitleForQuestID = function(id) return "Quest " .. id end
local rowFn, width
CUI.RegisterQuestTrackerRow = function(name, fn, w) rowFn, width = fn, w Put("registered", name, w) return true end
CUI.RefreshQuestTrackerRows = function() Put("rows refreshed") end
-- The bridge installs at login, long past: load the file again (this tree's
-- version) and fire login for it.
local chunk = assert(loadfile("CludesUIQuestTracker/CludesUIQuestTracker_QuestAudio.lua"))
chunk("CludesUIQuestTracker", mod)
HARNESS_FIRE_EVENT("PLAYER_LOGIN")
if not rowFn then
    Put("not installed")
    return
end
local slotA, slotB = CreateFrame("Frame", nil, UIParent), CreateFrame("Frame", nil, UIParent)
rowFn(slotA, 1)
rowFn(slotB, 2)
rowFn(slotA, 1)
rowFn(slotA, 3)
Put("binds", table.concat(binds, ","), "asks", asks)
SNAP("audio slot A", slotA)
SNAP("audio slot B", slotB)
callbacks.VOICE_PACKS_LOADED()
rowFn(slotA, 3)
Put("asks after packs loaded", asks)
callbacks.PART_SWITCHED("npcs")
callbacks.PART_SWITCHED("quests")
fail = true
rowFn(slotB, 4)
SNAP("audio after failure A", slotA)
rowFn(slotA, 1)
Put("asks after failure", asks)
