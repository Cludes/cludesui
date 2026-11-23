-- Forever: the one-time move to the CludesUI look everywhere
-- (CludesUIBlizzardSkin.lua, CludesUILookEverywhere). A profile on the WoW
-- Forever look with the character sheet at Blizz Default, the guild window
-- off and the kill switch on: the move runs the Style page's Apply to All
-- (recorded), turns every window skin on in the CludesUI style, clears the
-- kill switch and asks to reload; a second run does nothing.
local CUI = rawget(_G, "CludesUI")
local Move = CUI and CUI._CludesUILookEverywhere
OUT:write("== move " .. tostring(Move ~= nil) .. "\n")
if not Move then return end

local profile = CUI.GetActiveProfileData()
profile.windowSkinLook = "forever"
profile.disableWindowSkins = true
CludesUIDB.cuiLookEverywhereV1 = nil
CludesUIDB.reskinGuild = false
CludesUIDB.blizzWindowSkinStyles = { charsheet = "blizzard", quest = "modern" }

local applied, asked = {}, {}
rawset(C_AddOns, "LoadAddOn", function(name) return name == "CludesUIOptions" end)
CUI.BlizzStyle = CUI.BlizzStyle or {}
local realApply = CUI.BlizzStyle.ApplyAll
CUI.BlizzStyle.ApplyAll = function(key) applied[#applied + 1] = key end
local realPopup = CUI.ShowConfirmPopup
CUI.ShowConfirmPopup = function(_, o) asked[#asked + 1] = o.title .. " / " .. o.confirmText end

local function State(label)
    OUT:write(("== %s: look=%s kill=%s guild=%s styles=%s charsheet=%s quest=%s marker=%s\n"):format(
        label,
        tostring(profile.windowSkinLook),
        tostring(CUI.BlizzWindowSkinsKilled()),
        tostring(CludesUIDB.reskinGuild),
        tostring(CludesUIDB.blizzWindowSkinStyles),
        CUI.GetBlizzWindowStyle("charsheet"),
        CUI.GetBlizzWindowStyle("quest"),
        tostring(CludesUIDB.cuiLookEverywhereV1)
    ))
end
State("before")
Move(CludesUIDB)
State("after")
OUT:write("== apply to all: " .. table.concat(applied, ",") .. " | asked: " .. table.concat(asked, ",") .. "\n")
Move(CludesUIDB)
OUT:write("== second run: apply " .. #applied .. " asked " .. #asked .. "\n")
CUI.BlizzStyle.ApplyAll = realApply
CUI.ShowConfirmPopup = realPopup
