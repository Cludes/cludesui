-- The window engine's side tab (Skin.SideTab, CludesUIBlizzardSkin_WindowEngine.lua)
-- as a flat square: a stand-in tab with the template's parts; the ring and
-- glow go, the selected art is hidden, the square's fill and border follow
-- SetChecked (accent when selected).
local ns = CludesUI._ModuleNS and CludesUI._ModuleNS["CludesUIBlizzardSkin"]
local Skin = ns and ns.WSkin
OUT:write("== side tab " .. tostring(Skin and Skin.SideTab ~= nil) .. "\n")
if not (Skin and Skin.SideTab) then return end

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

Skin.SideTab(tab)
local square = Skin.GetFFD(tab).sideSquare
local function Fill() return table.concat({ square.fill:GetVertexColor() and "" or "", tostring(square.fill["\0color"] or "") }, "") end
OUT:write(("== idle: ring=%s glow=%s selected=%s square=%s\n"):format(
    tab.Background:GetAlpha(), tab.TabGlow:GetAlpha(), tab.SelectedTexture:GetAlpha(), tostring(square ~= nil)))
SNAP("tab idle", tab)
tab:SetChecked(true)
SNAP("tab selected", tab)
