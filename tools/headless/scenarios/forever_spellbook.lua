-- Forever spellbook content (CludesUIBlizzardSkin_PlayerSpellsForever.lua): a
-- stand-in PlayerSpellsFrame.SpellBookFrame with the Camelot parts. The pages
-- stay hidden after the pack's 0.1 dim, school tabs get a flat square (accent
-- border on the open one, repainted on SetTabSelected), a tab added later is
-- skinned too, spell icons lose the round mask and ornate frame, the settings
-- arrow becomes a flat square.
local ns = CludesUI._ModuleNS and CludesUI._ModuleNS["CludesUIBlizzardSkin"]
local PSF = ns and ns._PlayerSpellsForever
OUT:write("== psf " .. tostring(PSF ~= nil) .. "\n")
if not PSF then return end

local win = CreateFrame("Frame", "PlayerSpellsFrame", UIParent)
local book = CreateFrame("Frame", nil, win)
win.SpellBookFrame = book
for _, k in ipairs({ "BookBGLeft", "BookBGRight", "BookBGHalved" }) do
    book[k] = book:CreateTexture(nil, "BACKGROUND")
end

local tabs = CreateFrame("Frame", nil, book)
book.CategoryTabSystem = tabs
local function NewTab(selected)
    local t = CreateFrame("Button", nil, tabs)
    t:SetSize(44, 44)
    t.tabIcon = 136243
    t.Icon = t:CreateTexture(nil, "ARTWORK")
    t.Icon:SetSize(36, 36)
    t.Icon:SetPoint("CENTER")
    t.IconMask = t:CreateMaskTexture()
    t.Icon:AddMaskTexture(t.IconMask)
    for _, k in ipairs({ "SquareBackground", "SquareBackgroundActive", "SquareBackgroundActiveGlow" }) do
        t[k] = t:CreateTexture(nil, "ARTWORK", nil, 1)
    end
    function t:SetTabSelected(on)
        self.isSelected = on
        self.SquareBackground:SetShown(not on)
        self.SquareBackgroundActive:SetShown(on)
        self.SquareBackgroundActive:SetAlpha(1)
    end
    t:SetTabSelected(selected)
    return t
end
local tab1, tab2 = NewTab(true), NewTab(false)
function tabs:AddTab() return NewTab(false) end

book.SettingsDropdown = CreateFrame("Button", nil, book)
book.SettingsDropdown:SetSize(20, 20)
book.SettingsDropdown.arrowArt = book.SettingsDropdown:CreateTexture(nil, "ARTWORK")

local entry = CreateFrame("Frame", nil, book)
entry.Backplate = entry:CreateTexture(nil, "BACKGROUND")
entry.Button = CreateFrame("Button", nil, entry)
entry.Button:SetSize(40, 40)
entry.Button.Icon = entry.Button:CreateTexture(nil, "ARTWORK")
entry.Button.Icon:SetSize(36, 36)
entry.Button.Icon:SetPoint("CENTER")
entry.Button.IconMask = entry.Button:CreateMaskTexture()
entry.Button.Icon:AddMaskTexture(entry.Button.IconMask)
entry.Button.Border = entry.Button:CreateTexture(nil, "OVERLAY")
entry.Button.BorderShadow = entry.Button:CreateTexture(nil, "ARTWORK")

PSF.Apply()

local function A(t) return string.format("%.2f", t:GetAlpha()) end
local Skin = ns.WSkin
OUT:write(("== pages %s %s %s\n"):format(A(book.BookBGLeft), A(book.BookBGRight), A(book.BookBGHalved)))
book.BookBGLeft:SetAlpha(0.1)
OUT:write("== page after the pack's dim " .. A(book.BookBGLeft) .. "\n")
local p1 = Skin.GetFFD(tab1).cuiPlate
OUT:write(("== tab1 plate=%s activeArt=%s masks=%d\n"):format(tostring(p1 ~= nil), A(tab1.SquareBackgroundActive),
    tab1.Icon:GetNumMaskTextures()))
SNAP("tab selected plate", p1)
SNAP("tab idle plate", Skin.GetFFD(tab2).cuiPlate)
tab1:SetTabSelected(false)
tab2:SetTabSelected(true)
SNAP("tab1 after switch", p1)
OUT:write("== tab2 active art after switch " .. A(tab2.SquareBackgroundActive) .. "\n")
local tab3 = tabs:AddTab()
OUT:write("== added tab plate " .. tostring(Skin.GetFFD(tab3).cuiPlate ~= nil) .. "\n")
local b = entry.Button
OUT:write(("== spell border=%s shadow=%s masks=%d plate=%s\n"):format(tostring(b.Border:IsShown()),
    tostring(b.BorderShadow:IsShown()), b.Icon:GetNumMaskTextures(), tostring(Skin.GetFFD(b).cuiPlate ~= nil)))
OUT:write("== settings arrow " .. tostring(Skin.GetFFD(book.SettingsDropdown).arrowTex ~= nil) .. "\n")
