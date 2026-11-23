if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-------------------------------------------------------------------------------
--  CludesUIBlizzardSkin_SideTabs.lua
--  The game's side tabs (SidePanelTabButtonMixin: the character sheet's mode
--  tabs, the professions, inspect, collections, social, Legacy, bank and
--  group finder tabs, the quest map's) in the CludesUI look: the gold ring,
--  its mask and its glow go; the icon is a cropped square on a dark square
--  with a 1 px border, the accent border on the selected tab, a faint light
--  on hover. Only while the active profile is on the CludesUI window look
--  and window skins are on. Tabs built before this file loads are found by
--  name; every later one as the game builds it (the mixin's OnLoad).
-------------------------------------------------------------------------------
local SIZE = 36 -- the square
local ICON_INSET = 4

local function On()
    if CUI.BlizzWindowSkinsKilled and CUI.BlizzWindowSkinsKilled() then return false end
    local look = CUI.ProfileWindowSkinLook and CUI.ProfileWindowSkinLook(CUI.GetActiveProfileData(), CludesUIDB and CludesUIDB.fonts)
    return look == "cui"
end

local skinned = setmetatable({}, { __mode = "k" })

local function Paint(tab)
    local look = skinned[tab]
    if not look then return end
    local checked = tab.SelectedTexture and tab.SelectedTexture:IsShown()
    if tab.SelectedTexture then tab.SelectedTexture:SetAlpha(0) end
    local r, g, b = CUI.Kit.Accent()
    if checked then
        CUI.Kit.Border(look, r, g, b, 1)
        look.fill:SetColorTexture(r, g, b, 0.15)
    else
        CUI.Kit.Border(look, 0, 0, 0, 1)
        look.fill:SetColorTexture(0.062, 0.070, 0.082, 0.95)
    end
    -- The icon's own atlas (SetChecked can set it at its art size) fits the square.
    tab.Icon:ClearAllPoints()
    tab.Icon:SetPoint("TOPLEFT", look, "TOPLEFT", ICON_INSET, -ICON_INSET)
    tab.Icon:SetPoint("BOTTOMRIGHT", look, "BOTTOMRIGHT", -ICON_INSET, ICON_INSET)
    tab.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
end

local function Skin(tab)
    if skinned[tab] or not (tab and tab.Icon) or not On() then return end
    -- The look sits on a child frame: nothing is written onto the game's tab.
    local look = CreateFrame("Frame", nil, tab)
    look:SetSize(SIZE, SIZE)
    look:SetPoint("LEFT", tab, "LEFT", 2, 0)
    look:SetFrameLevel(math.max(0, tab:GetFrameLevel() - 1))
    look.fill = look:CreateTexture(nil, "BACKGROUND")
    look.fill:SetAllPoints()
    skinned[tab] = look
    for _, key in ipairs({ "Background", "TabGlow" }) do
        if tab[key] then tab[key]:SetAlpha(0) end
    end
    if tab.Mask and tab.Icon.RemoveMaskTexture then tab.Icon:RemoveMaskTexture(tab.Mask) end
    if tab.HighlightTexture then
        tab.HighlightTexture:SetColorTexture(1, 1, 1, 0.08)
        tab.HighlightTexture:ClearAllPoints()
        tab.HighlightTexture:SetAllPoints(look)
    end
    if tab.SetChecked then hooksecurefunc(tab, "SetChecked", Paint) end
    if tab.OnMouseUp then
        -- The pressed nudge re-anchors the icon: back to the square after.
        tab:HookScript("OnMouseUp", Paint)
    end
    Paint(tab)
end

-- Tabs the game builds from now on.
if SidePanelTabButtonMixin and SidePanelTabButtonMixin.OnLoad then
    hooksecurefunc(SidePanelTabButtonMixin, "OnLoad", function(tab) C_Timer.After(0, function() Skin(tab) end) end)
end

-- Tabs built before this file: by name, and the quest map's by key.
local function SkinKnown()
    for index = 1, 8 do
        local tab = _G["CharacterFrameModeTab" .. index]
        if tab then Skin(tab) end
    end
    local quest = _G.QuestMapFrame
    if quest then
        for _, key in ipairs({ "QuestsTab", "EventsTab", "MapLegendTab" }) do
            if quest[key] then Skin(quest[key]) end
        end
    end
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    SkinKnown()
end)

CUI._SkinSideTab = Skin
