if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
--------------------------------------------------------------------------------
--  Bag Bar on WoW Forever
--
--  The bag bar's slot buttons (backpack, four bag slots, reagent bag, keyring)
--  in the micro menu pack's cell look: bevel and icon-frame art faded, icon
--  cropped square, a theme background and border, a white hover wash, and a
--  quality-coloured border for a coloured bag. The BagsBar strip art is faded.
--  Alpha and our own child frames only: nothing is hidden, reparented or hooked
--  on show inside the BagsBar tree (Blizzard shows and hides it on the way to
--  protected calls). Forever only (IS_FOREVER is false everywhere else).
--------------------------------------------------------------------------------
local ADDON_NAME, mod = ...
local CUI = _G.CludesUI
if not (CUI and CUI.IS_FOREVER) then return end
local Skin = mod.WSkin
if not (Skin and Skin.RegisterWindow) then return end

local Theme = Skin.Theme
local FFD, GetFFD = CUI.NewFrameData()
local OURS = setmetatable({}, { __mode = "k" }) -- the frames this pack created

local ICON_CROP = 0.08
local CELL_BG_A = 0.45
-- BagsBar container backdrop atlases (the dark strip behind the slots).
local FRAME_ATLASES = { "actionbar-frame", "iconframe-background" }
local BAG_BUTTONS = {
    "MainMenuBarBackpackButton",
    "CharacterBag0Slot",
    "CharacterBag1Slot",
    "CharacterBag2Slot",
    "CharacterBag3Slot",
    "CharacterReagentBag0Slot",
    "KeyRingButton",
}

local function BorderPP() return CUI.PanelPP or CUI.PP end

-- One-time cell chrome: a box frame of ours with the theme border, the cell
-- background behind the icon, and the highlight turned into a white wash.
local function EnsureChrome(button)
    local skinData = GetFFD(button)
    if skinData.box then return skinData end
    local box = CreateFrame("Frame", nil, button)
    box:SetAllPoints(button)
    box:EnableMouse(false)
    Skin.AddBorder(box)
    OURS[box] = true
    skinData.box = box
    local backdrop = button:CreateTexture(nil, "BACKGROUND", nil, -8)
    backdrop:SetColorTexture(Theme.bgR, Theme.bgG, Theme.bgB, CELL_BG_A)
    backdrop:SetAllPoints(button)
    skinData.bg = backdrop
    local highlight = button.GetHighlightTexture and button:GetHighlightTexture()
    if highlight and highlight.SetColorTexture then
        highlight:SetColorTexture(1, 1, 1, 0.1)
        if highlight.SetTexCoord then highlight:SetTexCoord(0, 1, 0, 1) end
    end
    return skinData
end

-- The keyring's frame art sits in its child frames (a NineSlice border built
-- after the first pass): fade their textures, walking Blizzard's own frames only.
local function FadeKeyRingArt(frame, depth)
    if not frame or depth > 4 or (frame.IsForbidden and frame:IsForbidden()) then return end
    local children = { frame:GetChildren() }
    for idx = 1, #children do
        local child = children[idx]
        if child and not OURS[child] and not Skin.IsForeignFrame(child, frame) then
            local regionList = { child:GetRegions() }
            for jdx = 1, #regionList do
                local region = regionList[jdx]
                if region and region.GetObjectType and region:GetObjectType() == "Texture" then
                    region:SetAlpha(0)
                end
            end
            FadeKeyRingArt(child, depth + 1)
        end
    end
end

-- Per pass: icon crop, bevel art, masks and the border colour (bag quality).
local function PaintBag(button)
    local skinData = FFD[button]
    if not (skinData and skinData.box) then return end
    local isKeyRing = (button == _G.KeyRingButton)
    local iconTex = button.icon or (button.GetName and _G[button:GetName() .. "IconTexture"])
    local nt = (button.GetNormalTexture and button:GetNormalTexture()) or button.NormalTexture
    if isKeyRing then
        -- Its glyph can live on the NormalTexture, under its own SquareMask.
        local sm = button.SquareMask
        if sm then
            for _, t in ipairs({ _G.KeyRingButtonIconTexture, nt }) do
                if t and t.RemoveMaskTexture then pcall(t.RemoveMaskTexture, t, sm) end
            end
        end
        FadeKeyRingArt(button, 1)
        if not (iconTex and iconTex.GetTexture and iconTex:GetTexture()) then iconTex = nt end
    end
    if iconTex and iconTex.SetTexCoord then
        iconTex:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
    end
    -- The bevel NormalTexture fades, except while it is the keyring glyph.
    if nt and nt ~= iconTex then nt:SetAlpha(0) end
    if button.IconBorder then button.IconBorder:SetAlpha(0) end
    local regionList = { button:GetRegions() }
    for idx = 1, #regionList do
        local region = regionList[idx]
        local kind = region and region.GetObjectType and region:GetObjectType()
        if kind == "MaskTexture" then
            -- pcall: a texture the mask is not on may reject the removal.
            if iconTex and iconTex.RemoveMaskTexture then
                pcall(iconTex.RemoveMaskTexture, iconTex, region)
            end
            if nt and nt ~= iconTex and nt.RemoveMaskTexture then pcall(nt.RemoveMaskTexture, nt, region) end
        elseif kind == "Texture" then
            local atlas = region.GetAtlas and region:GetAtlas()
            if atlas and atlas:lower():find("iconframe", 1, true) then region:SetAlpha(0) end
        end
    end
    -- A coloured bag (uncommon and up) colours its border; the rest keep the theme border.
    local ident = button.GetID and button:GetID()
    local itemId = ident and ident > 0 and GetInventoryItemID("player", ident)
    local q = itemId and C_Item.GetItemQualityByID(itemId)
    local red, green, blue
    if q and q >= 2 then
        red, green, blue = C_Item.GetItemQualityColor(q)
    end
    local Pix = BorderPP()
    if red then
        Pix.SetBorderColor(skinData.box, red, green, blue, 1)
    else
        Pix.SetBorderColor(skinData.box, Theme.brdR, Theme.brdG, Theme.brdB, Theme.brdA)
    end
end

local function FadeFrameArt(widget)
    if not widget then return end
    local regionList = { widget:GetRegions() }
    for idx = 1, #regionList do
        local region = regionList[idx]
        local atlas = region and region.GetAtlas and region:GetAtlas()
        if atlas then
            local la = atlas:lower()
            for _, wanted in ipairs(FRAME_ATLASES) do
                if la:find(wanted, 1, true) then
                    region:SetAlpha(0)
                    break
                end
            end
        end
    end
end

local function PaintAll()
    for _, name in ipairs(BAG_BUTTONS) do
        local button = _G[name]
        if button then PaintBag(button) end
    end
end

local hooked = false
local function Skin_BagBar()
    FadeFrameArt(_G.BagsBar)
    for _, name in ipairs(BAG_BUTTONS) do
        local button = _G[name]
        if button and not button:IsForbidden() then EnsureChrome(button) end
    end
    PaintAll()
    if hooked then return end
    hooked = true
    -- Bag changes: quality borders and icon crops follow the equipped bags.
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("BAG_UPDATE_DELAYED")
    frame:SetScript("OnEvent", Skin.Debounce(PaintAll))
    -- The keyring rebuilds its art in its own texture update (bag updates and
    -- zone-ins): repaint it right after.
    local kr = _G.KeyRingButton
    if kr and kr.UpdateTextures then hooksecurefunc(kr, "UpdateTextures", function() PaintBag(kr) end) end
end

Skin.RegisterWindow({
    key = "bagbar",
    apply = Skin_BagBar,
})
