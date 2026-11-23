if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
--------------------------------------------------------------------------------
--  Spellbook on WoW Forever
--
--  Forever builds the spellbook from its Camelot variant: parchment pages
--  (spellbook-Page-*-C60), gold-framed icon tabs for the schools
--  (spellbook-Tab-Frame-*-C60) and round-masked spell icons inside ornate
--  frames. The shared pack (WindowPacks.lua, key "playerspells") does the shell,
--  text and controls; this adds the content in the house look, under the same
--  card: the pages go, the school tabs are flat squares (accent border on the
--  open one), spell icons are cropped squares with a 1 px border, and the
--  settings arrow is a flat square button. Forever only.
--------------------------------------------------------------------------------
local _, mod = ...
local CUI = _G.CludesUI
if not (CUI and CUI.IS_FOREVER) then return end
local Skin = mod.WSkin
if not (Skin and Skin.RegisterWindow and Skin.GetFFD) then return end

local PSF = {}
mod._PlayerSpellsForever = PSF

local PAGES = { "BookBGLeft", "BookBGRight", "BookBGHalved" }
local SQUARE_ART = { "SquareBackground", "SquareBackgroundActive", "SquareBackgroundActiveGlow" }

local function Pix() return CUI.PanelPP or CUI.PP end

local function BorderColor(frame, r, g, b)
    if not Skin.GetFFD(frame).border then
        Skin.AddBorder(frame, r, g, b, 1)
    else
        local P = Pix()
        if P and P.SetBorderColor then P.SetBorderColor(frame, r, g, b, 1) end
    end
end

-- Keep a texture at alpha 0 whatever sets it later (the pack dims the pages to
-- 0.1 on every show; Blizzard raises the tab frames on selection).
local function KeepHidden(tex)
    if not tex or not tex.SetAlpha then return end
    tex:SetAlpha(0)
    local data = Skin.GetFFD(tex)
    if data.keptHidden then return end
    data.keptHidden = true
    hooksecurefunc(tex, "SetAlpha", function(self, a)
        if a and a > 0 then self:SetAlpha(0) end
    end)
end

-- A dark square behind an icon with a 1 px border, as a child frame so nothing
-- is drawn onto the game's own button.
local function Plate(owner, icon, inset)
    local data = Skin.GetFFD(owner)
    if data.cuiPlate then return data.cuiPlate end
    local plate = CreateFrame("Frame", nil, owner)
    plate:SetPoint("TOPLEFT", icon, "TOPLEFT", -inset, inset)
    plate:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", inset, -inset)
    plate:SetFrameLevel(math.max(0, owner:GetFrameLevel()))
    plate.fill = plate:CreateTexture(nil, "BACKGROUND", nil, -6)
    plate.fill:SetAllPoints()
    data.cuiPlate = plate
    return plate
end

local function Unmask(icon, mask)
    if icon and mask and icon.RemoveMaskTexture then pcall(icon.RemoveMaskTexture, icon, mask) end
    if icon and icon.SetTexCoord then pcall(icon.SetTexCoord, icon, 0.08, 0.92, 0.08, 0.92) end
end

-- School tabs: the gold frames go; a flat square, the accent border and a
-- faint accent fill on the open school.
local function PaintIconTab(tab)
    local plate = Skin.GetFFD(tab).cuiPlate
    if not plate then return end
    local r, g, b = Skin.AccentBarColor()
    if tab.isSelected then
        BorderColor(plate, r, g, b)
        plate.fill:SetColorTexture(r, g, b, 0.15)
    else
        BorderColor(plate, 0, 0, 0)
        plate.fill:SetColorTexture(0.08, 0.08, 0.08, 0.95)
    end
end
PSF.PaintIconTab = PaintIconTab

function PSF.IconTab(tab)
    if not tab or not tab.tabIcon or not tab.Icon then return end
    for _, k in ipairs(SQUARE_ART) do
        KeepHidden(tab[k])
    end
    local data = Skin.GetFFD(tab)
    if not data.cuiPlate then
        Unmask(tab.Icon, tab.IconMask)
        Plate(tab, tab.Icon, 2)
        if tab.SetTabSelected then hooksecurefunc(tab, "SetTabSelected", PaintIconTab) end
    end
    PaintIconTab(tab)
end

function PSF.TabsIn(tabSystem)
    if not tabSystem or not tabSystem.GetChildren then return end
    local kids = { tabSystem:GetChildren() }
    for i = 1, #kids do
        PSF.IconTab(kids[i])
    end
    local data = Skin.GetFFD(tabSystem)
    if not data.cuiTabHook and tabSystem.AddTab then
        -- New school tabs come with each spell change (pooled; AddTab inits one).
        data.cuiTabHook = true
        hooksecurefunc(tabSystem, "AddTab", function(self) PSF.TabsIn(self) end)
    end
end

-- A spell: the ornate frame and its shadow go, the round mask comes off, the
-- icon is cropped square on a plate with a 1 px border.
function PSF.Spell(entry)
    local button = entry and entry.Button
    if not (button and button.Icon) or button:IsForbidden() then return end
    if button.Border then button.Border:Hide() end
    if button.BorderShadow then button.BorderShadow:Hide() end
    local data = Skin.GetFFD(button)
    if not data.cuiPlate then
        Unmask(button.Icon, button.IconMask)
        local plate = Plate(button, button.Icon, 1)
        BorderColor(plate, 0, 0, 0)
        plate.fill:SetColorTexture(0, 0, 0, 0.6)
    else
        pcall(button.Icon.SetTexCoord, button.Icon, 0.08, 0.92, 0.08, 0.92)
    end
end

-- The settings arrow beside the search box: a flat square with the house arrow.
function PSF.SettingsArrow(dropdown)
    if not dropdown or dropdown:IsForbidden() then return end
    local data = Skin.GetFFD(dropdown)
    if data.cuiArrow then return end
    data.cuiArrow = true
    Skin.FadeRegions(dropdown)
    for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
        local t = dropdown[getter] and dropdown[getter](dropdown)
        if t then t:SetAlpha(0) end
    end
    local fill = dropdown:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints()
    fill:SetColorTexture(0.08, 0.08, 0.08, 0.95)
    Skin.AddBorder(dropdown, 0.25, 0.25, 0.25, 1)
    local hover = dropdown:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, 0.08)
    local arrow = dropdown:CreateTexture(nil, "OVERLAY")
    arrow:SetAtlas("Azerite-PointingArrow")
    arrow:SetSize(14, 10)
    arrow:SetPoint("CENTER")
    data.arrowTex = arrow
end

local function SpellsIn(widget, depth)
    if not widget or depth > 10 or widget:IsForbidden() then return end
    if widget.Backplate and widget.Button then PSF.Spell(widget) end
    local kids = { widget:GetChildren() }
    for i = 1, #kids do
        SpellsIn(kids[i], depth + 1)
    end
end

local hooked
local Skin_SpellBook = Skin.WindowCallback("playerspells", function()
    local book = _G.PlayerSpellsFrame and _G.PlayerSpellsFrame.SpellBookFrame
    if not book then return end
    for _, k in ipairs(PAGES) do
        KeepHidden(book[k])
    end
    PSF.TabsIn(book.CategoryTabSystem)
    PSF.SettingsArrow(book.SettingsDropdown)
    SpellsIn(book, 0)
    if not hooked and SpellBookItemMixin and SpellBookItemMixin.UpdateVisuals then
        hooked = true
        hooksecurefunc(SpellBookItemMixin, "UpdateVisuals", function(entry)
            if Skin.GetStyle("playerspells") ~= "off" then PSF.Spell(entry) end
        end)
    end
end)
PSF.Apply = Skin_SpellBook

Skin.RegisterWindow({
    key = "playerspells",
    addons = { Blizzard_PlayerSpells = true },
    apply = function()
        Skin_SpellBook()
        local book = _G.PlayerSpellsFrame and _G.PlayerSpellsFrame.SpellBookFrame
        if book then Skin.HookShow(book, Skin.Debounce(Skin_SpellBook)) end
    end,
})
