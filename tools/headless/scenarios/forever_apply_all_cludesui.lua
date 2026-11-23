-- Forever: the Style page's Apply to All with CludesUI also puts every
-- window skin on (CludesUI.CludesUIWindowsAllOn). A profile on the WoW
-- Forever look with the character sheet at Blizz Default, the guild window
-- off and the kill switch on: before, the CludesUI card has a change to make
-- (pending); Apply to All("cui") leaves every window on the CludesUI skin;
-- after it nothing is pending. Nothing switches by itself at login.
local CUI = rawget(_G, "CludesUI")
OUT:write("== all-on " .. tostring(CUI and CUI.CludesUIWindowsAllOn ~= nil) .. "\n")
if not (CUI and CUI.CludesUIWindowsAllOn) then return end
C_AddOns.LoadAddOn("CludesUIOptions")
local BS = CUI.BlizzStyle
OUT:write("== style page " .. tostring(BS ~= nil and BS.ApplyAll ~= nil) .. "\n")
if not BS then return end

local profile = CUI.GetActiveProfileData()
profile.windowSkinLook = "forever"
profile.disableWindowSkins = true
CludesUIDB.reskinGuild = false
CludesUIDB.blizzWindowSkinStyles = { charsheet = "blizzard", quest = "modern" }

local function State(label)
    OUT:write(("== %s: look=%s kill=%s guild=%s charsheet=%s quest=%s pending=%s\n"):format(
        label,
        tostring(profile.windowSkinLook),
        tostring(CUI.BlizzWindowSkinsKilled()),
        CUI.GetBlizzWindowStyle("guild"),
        CUI.GetBlizzWindowStyle("charsheet"),
        CUI.GetBlizzWindowStyle("quest"),
        tostring(CUI.CludesUIWindowsAllOn(true))
    ))
end
State("before")
BS.ApplyAll("cui")
State("after Apply to All (CludesUI)")
