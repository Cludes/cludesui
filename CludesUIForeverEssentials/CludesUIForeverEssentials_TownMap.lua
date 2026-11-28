if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
if not (CUI and CUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_TownMap.lua  (WoW Forever only)
--  Town Map: service NPCs on the world map for your faction (your class's
--  trainers, profession trainers, innkeepers, bank and auction house, repairs,
--  reagents, ammo and food, stable masters for hunters, other vendors), plus
--  every mailbox and spirit healer, in towns and out in the world. Mailboxes
--  and spirit healers near you also go on the minimap. Vendors and trainers
--  can be kept to the capital cities; flight masters, innkeepers and stable
--  masters show everywhere.
--  Places: CludesUIForeverEssentials_TownMapData.lua.
-------------------------------------------------------------------------------
local _, module = ...

local F = module.Feature("townMap", {
    enabled = false,
    capitalsOnly = true,
    size = 16,
    spirit = true,
    class = true,
    profession = true,
    flight = true,
    inn = true,
    bank = true,
    stable = false,
    repair = true,
    supplies = true,
    vendors = false,
    mail = true,
    minimapMail = true,
    minimapSpirit = true,
})
local Get, Enabled = F.Get, F.Enabled

local CLASS_ICON = "Interface\\Icons\\ClassIcon_"
local TRACKING = "Interface\\Minimap\\Tracking\\"
local GOSSIP = "Interface\\GossipFrame\\"
local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local CROP_LOW, CROP_HIGH = 0.08, 0.92
local MINI_MAX = 40
local EMPTY = {}

-- category = { setting, fallback icon, label }
local CATEGORIES = {
    spirit = { "spirit", "Interface\\Icons\\Spell_Holy_GuardianSpirit", "Spirit Healer" },
    class = { "class", nil, "Class Trainer" },
    profession = { "profession", "Interface\\Icons\\INV_Misc_Book_09", "Trainer" },
    flight = { "flight", "Interface\\Icons\\Ability_Mount_Gryphon_01", "Flight Master" },
    inn = { "inn", "Interface\\Icons\\INV_Misc_Rune_01", "Innkeeper" },
    bank = { "bank", "Interface\\Icons\\INV_Misc_Bag_10", "Banker" },
    auction = { "bank", "Interface\\Icons\\INV_Misc_Coin_01", "Auctioneer" },
    stable = { "stable", "Interface\\Icons\\Ability_Hunter_BeastTaming", "Stable Master" },
    repair = { "repair", "Interface\\Icons\\Trade_BlackSmithing", "Repairs" },
    reagents = { "supplies", "Interface\\Icons\\INV_Misc_Dust_01", "Reagents" },
    ammo = { "supplies", "Interface\\Icons\\INV_Ammo_Arrow_01", "Ammunition" },
    food = { "supplies", "Interface\\Icons\\INV_Misc_Food_14", "Food & Drink" },
    trade = { "vendors", "Interface\\Icons\\INV_Fabric_Linen_01", "Trade Goods" },
    vendor = { "vendors", "Interface\\Icons\\INV_Misc_Bag_07", "Vendor" },
    mail = { "mail", "Interface\\Icons\\INV_Letter_15", "Mailbox" },
}
local EVERYWHERE = { flight = true, inn = true, stable = true }

-- Map art per category, first that exists wins (atlas names, or file paths).
local MAP_ART = {
    spirit = { "poi-soulspiritghost" },
    class = { "Class", TRACKING .. "Class", GOSSIP .. "TrainerGossipIcon" },
    profession = { "Profession", TRACKING .. "Profession", GOSSIP .. "TrainerGossipIcon" },
    flight = { "Taxi_Frame_Green", "TaxiNode_Neutral", "FlightMaster", TRACKING .. "FlightMaster" },
    inn = { "Innkeeper", TRACKING .. "Innkeeper" },
    bank = { "Banker", TRACKING .. "Banker" },
    auction = { "Auctioneer", TRACKING .. "Auctioneer" },
    stable = { "StableMaster", TRACKING .. "StableMaster" },
    repair = { "Repair", TRACKING .. "Repair" },
    reagents = { "Reagents", TRACKING .. "Reagents" },
    ammo = { "Ammunition", TRACKING .. "Ammunition" },
    food = { "Food", TRACKING .. "Food" },
    trade = { "Banker", GOSSIP .. "VendorGossipIcon" },
    vendor = { "Banker", GOSSIP .. "VendorGossipIcon" },
    mail = { "Mailbox", TRACKING .. "Mailbox" },
}
local ROUND_ART = { spirit = true }

local payload
local function TownData()
    if not payload then
        payload = module.TownMapData()
        module.TownMapData = nil
    end
    return payload
end

--- The service NPCs by map, for other features (Professions' gathering trainers).
function module.TownNPCList() return TownData().npcs end

local function MainMap(map) return map and (TownData().same[map] or map) end
local function PlayerFaction() return UnitFactionGroup("player") == "Horde" and "H" or "A" end

-------------------------------------------------------------------------------
--  Pin art
-------------------------------------------------------------------------------
local function ArtExists(art) return art:find("\\", 1, true) ~= nil end

local function SetPinArt(iconTex, art)
    if ArtExists(art) then return iconTex:SetTexture(art) end
    if not C_Texture.GetAtlasInfo(art) then return false end
    iconTex:SetAtlas(art)
    return true
end

local function MakeRound(pin, round)
    if round and not pin.roundMask then
        pin.roundMask = pin:CreateMaskTexture()
        pin.roundMask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        pin.roundMask:SetAllPoints(pin.icon)
    end
    if not pin.roundMask or (pin.isRound or false) == round then return end
    if round then
        pin.icon:AddMaskTexture(pin.roundMask)
    else
        pin.icon:RemoveMaskTexture(pin.roundMask)
    end
    pin.isRound = round
end

local function ClassIconArt(token) return CLASS_ICON .. token:lower():gsub("^%l", string.upper) end

local function FillPin(pin, npc)
    local iconTex, kind = pin.icon, npc[3]
    MakeRound(pin, false)
    for _, art in ipairs(MAP_ART[kind] or EMPTY) do
        if SetPinArt(iconTex, art) then
            iconTex:SetTexCoord(0, 1, 0, 1)
            pin.border:Hide()
            return
        end
    end
    if ROUND_ART[kind] then
        MakeRound(pin, true)
        iconTex:SetTexture(CATEGORIES[kind][2])
        iconTex:SetTexCoord(0, 1, 0, 1)
        pin.border:Hide()
        return
    end
    iconTex:SetTexture(
        CATEGORIES[kind][2] or (npc[6] and ClassIconArt(npc[6])) or "Interface\\Icons\\INV_Misc_QuestionMark"
    )
    iconTex:SetTexCoord(CROP_LOW, CROP_HIGH, CROP_LOW, CROP_HIGH)
    pin.border:Show()
end

local function ShowPinTip(pin)
    local npc = pin.npc
    if not npc then return end
    GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
    GameTooltip:SetText(npc[4], 1, 1, 1)
    local title = (npc[5] and npc[5] ~= "") and npc[5] or CATEGORIES[npc[3]][3]
    if title ~= npc[4] then GameTooltip:AddLine(title, CUI.Kit.Accent()) end
    GameTooltip:Show()
end

local function CreatePin(hostFrame)
    local pin = CreateFrame("Frame", nil, hostFrame)
    pin:SetMouseMotionEnabled(true)
    pin:SetMouseClickEnabled(false)
    pin.border = pin:CreateTexture(nil, "BACKGROUND")
    pin.border:SetPoint("TOPLEFT", -1, 1)
    pin.border:SetPoint("BOTTOMRIGHT", 1, -1)
    pin.border:SetColorTexture(0, 0, 0, 1)
    pin.icon = pin:CreateTexture(nil, "ARTWORK")
    pin.icon:SetAllPoints()
    pin:SetScript("OnEnter", ShowPinTip)
    pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return pin
end

-------------------------------------------------------------------------------
--  World map
-------------------------------------------------------------------------------
local provider, layer, waiter
local added = false
local pins, used = {}, 0

-- Flight masters are left to Map Markers when it shows flight points.
local function FlightsShownElsewhere()
    local mt = CUI._MapTravel
    return mt and mt.On and mt.On("flights")
end

local function ShowNpc(npc, faction, class, shops)
    local kind = npc[3]
    local category = CATEGORIES[kind]
    if not category or not Get(category[1]) then return false end
    if not (npc[7] or ""):find(faction, 1, true) then return false end
    if kind == "mail" or kind == "spirit" then return true end
    if not (shops or EVERYWHERE[kind]) then return false end
    if kind == "class" and npc[6] ~= class then return false end
    if kind == "stable" and class ~= "HUNTER" then return false end
    if kind == "flight" and FlightsShownElsewhere() then return false end
    return true
end

local function AnchorPin(p)
    local canvas = layer:GetParent()
    local wid, hgt = canvas:GetSize()
    local cs = canvas:GetScale()
    p:SetScale(1 / cs)
    p:ClearAllPoints()
    p:SetPoint("CENTER", canvas, "TOPLEFT", p.x * wid * cs, -p.y * hgt * cs)
end

local function ClearPins()
    for index = 1, used do
        pins[index]:Hide()
        pins[index].npc = nil
    end
    used = 0
end

local function RescalePins()
    for index = 1, used do
        AnchorPin(pins[index])
    end
end

local function AddPin(npc)
    used = used + 1
    local p = pins[used]
    if not p then
        p = CreatePin(layer)
        pins[used] = p
    end
    p.npc, p.x, p.y = npc, npc[1] / 100, npc[2] / 100
    local size = Get("size")
    p:SetSize(size, size)
    FillPin(p, npc)
    AnchorPin(p)
    p:Show()
end

local function DrawPins()
    ClearPins()
    if not Enabled() then return end
    local mapID = MainMap(WorldMapFrame:GetMapID())
    if not mapID then return end
    local skinData = TownData()
    local faction = PlayerFaction()
    local _, class = UnitClass("player")
    local shops = not Get("capitalsOnly") or skinData.capitals[mapID]
    for _, entries in ipairs({ skinData.npcs[mapID], skinData.mail[mapID], skinData.spirit[mapID] }) do
        for _, npc in ipairs(entries or EMPTY) do
            if ShowNpc(npc, faction, class, shops) then AddPin(npc) end
        end
    end
end

local function BuildLayer()
    layer = CreateFrame("Frame", nil, WorldMapFrame.ScrollContainer.Child)
    layer:SetAllPoints()
    layer:SetFrameLevel(
        WorldMapFrame:GetPinFrameLevelsManager():GetValidFrameLevel("PIN_FRAME_LEVEL_AREA_POI")
    )
    provider = CreateFromMixins(MapCanvasDataProviderMixin)
    provider.OnMapChanged = DrawPins
    provider.RefreshAllData = DrawPins
    provider.RemoveAllData = ClearPins
    provider.OnCanvasScaleChanged = RescalePins
    provider.OnGlobalAlphaChanged = function(self) layer:SetAlpha(self:GetMap():GetGlobalAlpha()) end
end

local function ApplyWorldMap()
    if not Enabled() then
        if added then
            WorldMapFrame:RemoveDataProvider(provider)
            added = false
        end
        if layer then ClearPins() end
        return
    end
    if not provider then
        if not C_AddOns.IsAddOnLoaded("Blizzard_WorldMap") then
            if not waiter then
                waiter = CreateFrame("Frame")
                waiter:SetScript("OnEvent", function(self, _, name)
                    if name ~= "Blizzard_WorldMap" then return end
                    self:UnregisterEvent("ADDON_LOADED")
                    ApplyWorldMap()
                end)
            end
            waiter:RegisterEvent("ADDON_LOADED")
            return
        end
        BuildLayer()
    end
    if not added then
        WorldMapFrame:AddDataProvider(provider)
        added = true
    end
    if WorldMapFrame:IsShown() then DrawPins() end
end

-------------------------------------------------------------------------------
--  Minimap: mailboxes and spirit healers near you
-------------------------------------------------------------------------------
local mini
local spots = {}

local function CreateMinimapPin()
    local pin = CreatePin(Minimap)
    local size = Get("size") * 0.9
    pin:SetSize(size, size)
    return pin
end

local function FillMinimapPin(pin, entries, index)
    pin.npc = entries[index]
    local size = Get("size") * 0.9
    pin:SetSize(size, size)
    FillPin(pin, entries[index])
end

local function RefreshMinimap()
    wipe(spots)
    local map = Enabled()
        and (Get("minimapMail") or Get("minimapSpirit"))
        and C_Map.GetBestMapForUnit("player")
    if map then
        local skinData, faction = TownData(), PlayerFaction()
        local same = MainMap(map)
        if Get("minimapMail") and Get("mail") then
            for _, s in ipairs(skinData.mail[same] or EMPTY) do
                if (s[7] or ""):find(faction, 1, true) then spots[#spots + 1] = s end
            end
        end
        if Get("minimapSpirit") and Get("spirit") then
            for _, s in ipairs(skinData.spirit[same] or EMPTY) do
                if (s[7] or ""):find(faction, 1, true) then spots[#spots + 1] = s end
            end
        end
    end
    if not mini and #spots == 0 then return end
    mini = mini
        or module.MinimapLayer({
            max = MINI_MAX,
            new = CreateMinimapPin,
            paint = FillMinimapPin,
            xy = function(entries, index) return entries[index][1] / 100, entries[index][2] / 100 end,
        })
    mini:Set(map, spots, #spots)
end

local miniEv = CreateFrame("Frame")
miniEv:SetScript("OnEvent", RefreshMinimap)

local function ApplyMinimap()
    miniEv:UnregisterAllEvents()
    if Enabled() and (Get("minimapMail") or Get("minimapSpirit")) then
        for _, event in ipairs({
            "PLAYER_ENTERING_WORLD",
            "ZONE_CHANGED_NEW_AREA",
            "ZONE_CHANGED",
            "ZONE_CHANGED_INDOORS",
        }) do
            miniEv:RegisterEvent(event)
        end
    end
    if IsLoggedIn() then RefreshMinimap() end
end

local function Apply()
    ApplyWorldMap()
    ApplyMinimap()
end

CUI._TownMap = { Get = Get, Cfg = F.Cfg, Apply = Apply }

F.Start(Apply)
