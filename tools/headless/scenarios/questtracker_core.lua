-- Quest Tracker core: defaults, the style and custom-tracker answers for
-- each saved combination, the custom-tracker pick, suppression, the slash
-- command, and the profile refresh. Prints what each returns.
local mod = rawget(_G, "CludesUI")._ModuleNS.CludesUIQuestTracker
local EQT = mod.EQT
local function Put(...)
    local t = { ... }
    for i = 1, select("#", ...) do t[i] = tostring(t[i]) end
    OUT:write("== ", table.concat(t, " "), "\n")
end
for _, k in ipairs({ "enabled", "visibility", "hideInRaidMode", "titleFontSize", "bgAlpha", "autoAccept", "autoTurnInShiftSkip" }) do
    Put("cfg", k, EQT.Cfg(k))
end
Put("style", mod.QT_Style(), "blizz", EQT.Blizz(), "classic", EQT.Classic(), "custom", mod.UseCustomTracker())
local cases = {
    {}, { useBlizzardStyle = true }, { useClassicStyle = true }, { customTracker = false },
    { customTracker = true, useBlizzardStyle = true }, { customTrackerPick = true, useClassicStyle = true },
    { customTrackerPick = false },
}
for i, qt in ipairs(cases) do
    Put("wanted", i, mod.CustomTrackerWanted(qt))
    local copy = {}
    for k, v in pairs(qt) do copy[k] = v end
    mod.SetCustomTrackerWanted(copy, true)
    Put("pick on", i, tostring(copy.customTrackerPick), tostring(copy.customTracker))
    mod.SetCustomTrackerWanted(copy, false)
    Put("pick off", i, tostring(copy.customTrackerPick), tostring(copy.customTracker))
end
Put("suppressed", EQT.IsSuppressed())
_CUQT_SetSuppressed("a", true)
_CUQT_SetSuppressed("b", true)
_CUQT_SetSuppressed("a", false)
Put("suppressed after a off", EQT.IsSuppressed())
_CUQT_SetSuppressed("b", false)
_CUQT_SetSuppressed(nil, true)
Put("suppressed after all off", EQT.IsSuppressed())
for _, msg in ipairs({ " HIDE ", "show", "toggle", "toggle" }) do
    SlashCmdList.EQT(msg)
    Put("slash", msg, EQT.Cfg("enabled"))
end
EQT.Set("titleFontSize", 14)
Put("set", EQT.Cfg("titleFontSize"))
EQT.Set("titleFontSize", 12)
_CUQT_RefreshAll()
Put("refreshed", "ok", _G.CludesUIQuestTracker == EQT, type(_G._CUQT_DB))
