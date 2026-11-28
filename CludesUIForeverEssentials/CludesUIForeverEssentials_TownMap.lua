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

local CALLING_GLYPH = "Interface\\Icons\\ClassIcon_"
local TRACKING = "Interface\\Minimap\\Tracking\\"
local GOSSIP = "Interface\\GossipFrame\\"
local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local TRIM_LOWER, TRIM_UPPER = 0.08, 0.92
local MINI_TOP = 40
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
local CHART_IMAGE = {
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
local ROUND_IMAGE = { spirit = true }

local payload
local function Info()
    if not payload then
        payload = module.TownMapData()
        module.TownMapData = nil
    end
    return payload
end

--- The service NPCs by map, for other features (Professions' gathering trainers).
function module.TownNPCList() return Info().npcs end

local function SameChart(chart) return chart and (Info().same[chart] or chart) end
local function Faction() return UnitFactionGroup("player") == "Horde" and "H" or "A" end

-------------------------------------------------------------------------------
--  Pin art
-------------------------------------------------------------------------------
local function IsFile(image) return image:find("\\", 1, true) ~= nil end

local function TryImage(glyphTex, image)
    if IsFile(image) then return glyphTex:SetTexture(image) end
    if not C_Texture.GetAtlasInfo(image) then return false end
    glyphTex:SetAtlas(image)
    return true
end

local function AssignRound(marker, round)
    if round and not marker.roundMask then
        marker.roundMask = marker:CreateMaskTexture()
        marker.roundMask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        marker.roundMask:SetAllPoints(marker.icon)
    end
    if not marker.roundMask or (marker.isRound or false) == round then return end
    if round then
        marker.icon:AddMaskTexture(marker.roundMask)
    else
        marker.icon:RemoveMaskTexture(marker.roundMask)
    end
    marker.isRound = round
end

local function CallingGlyph(token) return CALLING_GLYPH .. token:lower():gsub("^%l", string.upper) end

local function Paint(marker, npc)
    local glyphTex, kind = marker.icon, npc[3]
    AssignRound(marker, false)
    for _, image in ipairs(CHART_IMAGE[kind] or EMPTY) do
        if TryImage(glyphTex, image) then
            glyphTex:SetTexCoord(0, 1, 0, 1)
            marker.border:Hide()
            return
        end
    end
    if ROUND_IMAGE[kind] then
        AssignRound(marker, true)
        glyphTex:SetTexture(CATEGORIES[kind][2])
        glyphTex:SetTexCoord(0, 1, 0, 1)
        marker.border:Hide()
        return
    end
    glyphTex:SetTexture(
        CATEGORIES[kind][2] or (npc[6] and CallingGlyph(npc[6])) or "Interface\\Icons\\INV_Misc_QuestionMark"
    )
    glyphTex:SetTexCoord(TRIM_LOWER, TRIM_UPPER, TRIM_LOWER, TRIM_UPPER)
    marker.border:Show()
end

local function RevealHint(marker)
    local npc = marker.npc
    if not npc then return end
    GameTooltip:SetOwner(marker, "ANCHOR_RIGHT")
    GameTooltip:SetText(npc[4], 1, 1, 1)
    local heading = (npc[5] and npc[5] ~= "") and npc[5] or CATEGORIES[npc[3]][3]
    if heading ~= npc[4] then GameTooltip:AddLine(heading, CUI.Kit.Accent()) end
    GameTooltip:Show()
end

local function FreshMarker(hostFrame)
    local marker = CreateFrame("Frame", nil, hostFrame)
    marker:SetMouseMotionEnabled(true)
    marker:SetMouseClickEnabled(false)
    marker.border = marker:CreateTexture(nil, "BACKGROUND")
    marker.border:SetPoint("TOPLEFT", -1, 1)
    marker.border:SetPoint("BOTTOMRIGHT", 1, -1)
    marker.border:SetColorTexture(0, 0, 0, 1)
    marker.icon = marker:CreateTexture(nil, "ARTWORK")
    marker.icon:SetAllPoints()
    marker:SetScript("OnEnter", RevealHint)
    marker:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return marker
end

-------------------------------------------------------------------------------
--  World map
-------------------------------------------------------------------------------
local provider, layer, waiter
local added = false
local markers, used = {}, 0

-- Flight masters are left to Map Markers when it shows flight points.
local function FlightsElsewhere()
    local mt = CUI._MapTravel
    return mt and mt.On and mt.On("flights")
end

local function Desired(npc, faction, calling, shops)
    local kind = npc[3]
    local category = CATEGORIES[kind]
    if not category or not Get(category[1]) then return false end
    if not (npc[7] or ""):find(faction, 1, true) then return false end
    if kind == "mail" or kind == "spirit" then return true end
    if not (shops or EVERYWHERE[kind]) then return false end
    if kind == "class" and npc[6] ~= calling then return false end
    if kind == "stable" and calling ~= "HUNTER" then return false end
    if kind == "flight" and FlightsElsewhere() then return false end
    return true
end

local function Anchor(p)
    local canvas = layer:GetParent()
    local wid, hgt = canvas:GetSize()
    local cs = canvas:GetScale()
    p:SetScale(1 / cs)
    p:ClearAllPoints()
    p:SetPoint("CENTER", canvas, "TOPLEFT", p.x * wid * cs, -p.y * hgt * cs)
end

local function Wipe()
    for catalog = 1, used do
        markers[catalog]:Hide()
        markers[catalog].npc = nil
    end
    used = 0
end

local function Resize()
    for catalog = 1, used do
        Anchor(markers[catalog])
    end
end

local function Place(npc)
    used = used + 1
    local p = markers[used]
    if not p then
        p = FreshMarker(layer)
        markers[used] = p
    end
    p.npc, p.x, p.y = npc, npc[1] / 100, npc[2] / 100
    local dims = Get("size")
    p:SetSize(dims, dims)
    Paint(p, npc)
    Anchor(p)
    p:Show()
end

local function Render()
    Wipe()
    if not Enabled() then return end
    local chartID = SameChart(WorldMapFrame:GetMapID())
    if not chartID then return end
    local skinInfo = Info()
    local faction = Faction()
    local _, calling = UnitClass("player")
    local shops = not Get("capitalsOnly") or skinInfo.capitals[chartID]
    for _, items in ipairs({ skinInfo.npcs[chartID], skinInfo.mail[chartID], skinInfo.spirit[chartID] }) do
        for _, npc in ipairs(items or EMPTY) do
            if Desired(npc, faction, calling, shops) then Place(npc) end
        end
    end
end

local function Build()
    layer = CreateFrame("Frame", nil, WorldMapFrame.ScrollContainer.Child)
    layer:SetAllPoints()
    layer:SetFrameLevel(
        WorldMapFrame:GetPinFrameLevelsManager():GetValidFrameLevel("PIN_FRAME_LEVEL_AREA_POI")
    )
    provider = CreateFromMixins(MapCanvasDataProviderMixin)
    provider.OnMapChanged = Render
    provider.RefreshAllData = Render
    provider.RemoveAllData = Wipe
    provider.OnCanvasScaleChanged = Resize
    provider.OnGlobalAlphaChanged = function(self) layer:SetAlpha(self:GetMap():GetGlobalAlpha()) end
end

local function ChartUse()
    if not Enabled() then
        if added then
            WorldMapFrame:RemoveDataProvider(provider)
            added = false
        end
        if layer then Wipe() end
        return
    end
    if not provider then
        if not C_AddOns.IsAddOnLoaded("Blizzard_WorldMap") then
            if not waiter then
                waiter = CreateFrame("Frame")
                waiter:SetScript("OnEvent", function(self, _, title)
                    if title ~= "Blizzard_WorldMap" then return end
                    self:UnregisterEvent("ADDON_LOADED")
                    ChartUse()
                end)
            end
            waiter:RegisterEvent("ADDON_LOADED")
            return
        end
        Build()
    end
    if not added then
        WorldMapFrame:AddDataProvider(provider)
        added = true
    end
    if WorldMapFrame:IsShown() then Render() end
end

-------------------------------------------------------------------------------
--  Minimap: mailboxes and spirit healers near you
-------------------------------------------------------------------------------
local mini
local places = {}

local function MiniFresh()
    local marker = FreshMarker(Minimap)
    local dims = Get("size") * 0.9
    marker:SetSize(dims, dims)
    return marker
end

local function MiniRender(marker, items, catalog)
    marker.npc = items[catalog]
    local dims = Get("size") * 0.9
    marker:SetSize(dims, dims)
    Paint(marker, items[catalog])
end

local function MiniRenew()
    wipe(places)
    local chart = Enabled()
        and (Get("minimapMail") or Get("minimapSpirit"))
        and C_Map.GetBestMapForUnit("player")
    if chart then
        local skinInfo, faction = Info(), Faction()
        local same = SameChart(chart)
        if Get("minimapMail") and Get("mail") then
            for _, s in ipairs(skinInfo.mail[same] or EMPTY) do
                if (s[7] or ""):find(faction, 1, true) then places[#places + 1] = s end
            end
        end
        if Get("minimapSpirit") and Get("spirit") then
            for _, s in ipairs(skinInfo.spirit[same] or EMPTY) do
                if (s[7] or ""):find(faction, 1, true) then places[#places + 1] = s end
            end
        end
    end
    if not mini and #places == 0 then return end
    mini = mini
        or module.MinimapLayer({
            max = MINI_TOP,
            new = MiniFresh,
            paint = MiniRender,
            xy = function(items, catalog) return items[catalog][1] / 100, items[catalog][2] / 100 end,
        })
    mini:Set(chart, places, #places)
end

local miniEv = CreateFrame("Frame")
miniEv:SetScript("OnEvent", MiniRenew)

local function MiniUse()
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
    if IsLoggedIn() then MiniRenew() end
end

local function Apply()
    ChartUse()
    MiniUse()
end

CUI._TownMap = { Get = Get, Cfg = F.Cfg, Apply = Apply }

F.Start(Apply)
