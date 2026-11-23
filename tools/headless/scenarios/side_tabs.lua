-- The game's side tabs in the CludesUI look (CludesUIBlizzardSkin_SideTabs.lua).
-- A stand-in tab with the template's parts (Background, Icon, Mask,
-- SelectedTexture, TabGlow, HighlightTexture, SetChecked) on the CludesUI
-- look: the ring and glow go, the icon fills the square, the selected tab
-- takes the accent fill; on the WoW Forever look nothing is touched.
local CUI = rawget(_G, "CludesUI")
local Skin = CUI and CUI._SkinSideTab
OUT:write("== side tabs " .. tostring(Skin ~= nil) .. "\n")
if not Skin then return end

local function NewTab()
    local tab = CreateFrame("Frame", nil, UIParent)
    tab:SetSize(46, 40)
    tab.Background = tab:CreateTexture(nil, "BACKGROUND")
    tab.Icon = tab:CreateTexture(nil, "ARTWORK")
    tab.Mask = tab:CreateMaskTexture()
    tab.SelectedTexture = tab:CreateTexture(nil, "OVERLAY")
    tab.TabGlow = tab:CreateTexture(nil, "OVERLAY")
    tab.HighlightTexture = tab:CreateTexture(nil, "HIGHLIGHT")
    function tab:SetChecked(on) self.SelectedTexture:SetShown(on) end
    tab:SetChecked(false)
    return tab
end
local function State(label, tab)
    OUT:write(("== %s: ring=%s glow=%s selected-art=%s icon=%s\n"):format(
        label,
        tostring(tab.Background:GetAlpha()),
        tostring(tab.TabGlow:GetAlpha()),
        tostring(tab.SelectedTexture:GetAlpha()),
        tostring(select(1, tab.Icon:GetTexCoord()))
    ))
end

local profile = CUI.GetActiveProfileData()
profile.windowSkinLook = "forever"
local off = NewTab()
Skin(off)
State("forever look", off)

profile.windowSkinLook = "cui"
profile.disableWindowSkins = nil
local tab = NewTab()
Skin(tab)
State("cludesui look", tab)
tab:SetChecked(true)
SNAP("side tab selected", tab)
