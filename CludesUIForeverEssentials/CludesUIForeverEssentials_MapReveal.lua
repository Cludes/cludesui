if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if not (CludesUI and CludesUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_MapReveal.lua  (WoW Forever only)
--  Reveal Unexplored Areas: draws the world map overlays the player has not
--  explored yet, tinted with the chosen color.
--
--  The overlays are module.MapRevealData, the generated file listed before
--  this one (.tools/map-reveal-data.sh). A data provider reports map changes;
--  the textures live on a frame of our own under the canvas, so nothing of
--  Blizzard's map is hooked. They are not passed to AddMaskableTexture: that
--  table is walked with pairs() in secure code. Nothing is built while off.
-------------------------------------------------------------------------------
local _, module = ...

-- Settings live in CludesUIDB.worldMapReveal; unset keys read these.
local F = module.Feature("worldMapReveal", {
    enabled = false,
    color = { r = 0.55, g = 0.55, b = 0.55, a = 1 },
})

local provider, layer, waiter
local added = false
local textures, used = {}, 0
local explored = {}

local function Clear()
    for index = 1, used do
        textures[index]:Hide()
    end
    used = 0
end

-- Size of the texture file holding a partial tile: a power of two, at least 16
local function FileSize(px)
    local s = 16
    while s < px do
        s = s * 2
    end
    return s
end

local function Refresh()
    Clear()
    local payload = module.MapRevealData
    local mapID = WorldMapFrame:GetMapID()
    local overlays = payload and mapID and payload[C_Map.GetMapArtID(mapID)]
    if not overlays then return end
    local layers = C_Map.GetMapArtLayers(mapID)
    local art = layers and layers[1]
    if not art then return end
    local tw, th = art.tileWidth, art.tileHeight

    wipe(explored)
    local known = C_MapExplorationInfo.GetExploredMapTextures(mapID)
    if known then
        for index = 1, #known do
            local ident = known[index].fileDataIDs[1]
            if ident then explored[ident] = true end
        end
    end

    local colour = F.Get("color")
    local cr, cg, callback, ca = colour.r, colour.g, colour.b, colour.a or 1
    for index = 1, #overlays do
        local o = overlays[index]
        if not explored[o[5]] then
            local wid, hgt, posX, posY = o[1], o[2], o[3], o[4]
            local cols, rowList = math.ceil(wid / tw), math.ceil(hgt / th)
            for region = 1, rowList do
                local ph = region < rowList and th or hgt - th * (rowList - 1)
                local fh = region < rowList and th or FileSize(ph)
                for c = 1, cols do
                    local pw = c < cols and tw or wid - tw * (cols - 1)
                    local fw = c < cols and tw or FileSize(pw)
                    used = used + 1
                    local t = textures[used]
                    if not t then
                        t = layer:CreateTexture(nil, "ARTWORK")
                        textures[used] = t
                    end
                    t:SetSize(pw, ph)
                    t:SetTexCoord(0, pw / fw, 0, ph / fh)
                    t:ClearAllPoints()
                    t:SetPoint("TOPLEFT", posX + tw * (c - 1), -(posY + th * (region - 1)))
                    t:SetTexture(o[4 + (region - 1) * cols + c], nil, nil, "TRILINEAR")
                    t:SetVertexColor(cr, cg, callback, ca)
                    t:Show()
                end
            end
        end
    end
end

local function Build()
    layer = CreateFrame("Frame", nil, WorldMapFrame.ScrollContainer.Child)
    layer:SetAllPoints()
    layer:SetFrameLevel(
        WorldMapFrame:GetPinFrameLevelsManager():GetValidFrameLevel("PIN_FRAME_LEVEL_MAP_EXPLORATION")
    )
    layer:SetScript("OnEvent", Refresh) -- MAP_EXPLORATION_UPDATED

    provider = CreateFromMixins(MapCanvasDataProviderMixin)
    provider.OnMapChanged = Refresh
    provider.RefreshAllData = Refresh
    provider.RemoveAllData = Clear
    provider.OnShow = function() layer:RegisterEvent("MAP_EXPLORATION_UPDATED") end
    provider.OnHide = function() layer:UnregisterEvent("MAP_EXPLORATION_UPDATED") end
    provider.OnGlobalAlphaChanged = function(self) layer:SetAlpha(self:GetMap():GetGlobalAlpha()) end
end

-- The world map loads on demand, so building may wait for it.
local function Apply()
    if not F.Enabled() then
        if added then
            WorldMapFrame:RemoveDataProvider(provider)
            layer:UnregisterEvent("MAP_EXPLORATION_UPDATED")
            added = false
        end
        if waiter then waiter:UnregisterEvent("ADDON_LOADED") end
        return
    end
    if not provider then
        if not C_AddOns.IsAddOnLoaded("Blizzard_WorldMap") then
            if not waiter then
                waiter = CreateFrame("Frame")
                waiter:SetScript("OnEvent", function(self, _, name)
                    if name ~= "Blizzard_WorldMap" then return end
                    self:UnregisterEvent("ADDON_LOADED")
                    Apply()
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
        provider:OnGlobalAlphaChanged()
        if WorldMapFrame:IsShown() then provider:OnShow() end
    end
    if WorldMapFrame:IsShown() then Refresh() end
end

-- Options-page entry points.
CludesUI._MapReveal = {
    Get = F.Get,
    Cfg = F.Cfg,
    Apply = Apply,
}

F.Start(Apply)
