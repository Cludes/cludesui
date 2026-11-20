if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if not (CludesUI and CludesUI.IS_FOREVER) then
    return
end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_MapTravel.lua  (WoW Forever only)
--  Map Markers: travel pins by zoom level. The world map shows transports,
--  a continent adds instance entrances, a zone adds flight points and its
--  exits; each set has its cog toggle. Hovering a pin names it; a left click
--  prints its map pin link in chat, as /way does, pointing at the zone it
--  stands in; a right click goes on to the map (back out a level).
--
--  As Reveal Unexplored Areas: nothing of Blizzard's map is hooked; a data
--  provider reports map changes and zoom, and the pins are frames of our own
--  on a frame of ours under the canvas.
--  Places: CludesUIForeverEssentials_MapTravelData.lua.
-------------------------------------------------------------------------------
local _, module = ...

-- Settings live in CludesUIDB.mapTravel; unset keys read these.
local F = module.Feature(
    "mapTravel",
    { enabled = false, transports = true, exits = true, instances = true, flights = true }
)

-- A set of pins shows while Map Markers is on and its cog toggle too.
local function On(key)
    return F.Get("enabled") and F.Get(key)
end

local PIN_SIZE = 22
local ARROW_SIZE = 20
local INSTANCE_SIZE = 32 -- the portal art leaves a wide margin in its atlas

local KIND_ATLAS = {
    boat = "flightmasterferry",
    zeppelin = "vehicle-air-horde",
    tram = "vehicle-alliancecart",
    skycutter = "vehicle-air-alliance",
    portal = "mageportalalliance",
}

local payload, provider, layer, waiter, taxiWatch
local added = false
local pins, used = {}, 0
local shownKey -- what the pins show (map and toggles); nil when cleared
local shownMap -- the map the pins are on

local function AnyOn()
    return On("transports") or On("exits") or On("instances") or On("flights")
end

-- A pin's tooltip, led by its icon (a transport's lines carry their own).
local function PinTip(p)
    if p.tip:find("^|A") or p.atlas:find("\\", 1, true) then
        return p.tip
    end
    return ("|A:%s:16:16|a "):format(p.atlas) .. p.tip
end

-- Pins that touch on screen (it depends on the zoom) share one tooltip: the
-- hovered pin's first, then each one touching it. Offsets and sizes are both
-- in the pins' own (scaled) units, as Anchor sets them.
local function PinOnEnter(self)
    local canvas = layer:GetParent()
    local wid, hgt = canvas:GetSize()
    local cs = canvas:GetScale()
    local tipText = PinTip(self)
    for index = 1, used do
        local p = pins[index]
        if p ~= self then
            local reach = (p.size + self.size) / 2
            if math.abs(p.x - self.x) * wid * cs < reach and math.abs(p.y - self.y) * hgt * cs < reach then
                tipText = tipText .. "\n\n" .. PinTip(p)
            end
        end
    end
    if C_Map.CanSetUserWaypointOnMap(self.linkMap) then
        tipText = tipText
            .. "\n\n"
            .. CludesUI.COLOR_CODES.DIM
            .. CludesUI.L("Click to link it in chat.")
            .. "|r"
    end
    CludesUI.ShowWidgetTooltip(self, tipText)
end

local function PinOnLeave()
    CludesUI.HideWidgetTooltip()
end

-- A pin's name for its link: the first line of its tooltip, without icons
-- or colors ("Boat to Menethil Harbor").
local function PinLabel(tipText)
    local line = tipText:match("^[^\n]*")
    line = line:gsub("|A.-|a", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    return strtrim(line)
end

-- The link C_Map.GetUserWaypointHyperlink builds, as /way prints it: x, y
-- (0..1 here) travel as 0..10000. Clicked in chat, Blizzard places the pin.
local hintedClick = false
local function PrintLink(mapID, posX, posY, labelText, atlas)
    local CC = CludesUI.COLOR_CODES
    local iconTex = atlas and not atlas:find("\\", 1, true) and ("|A:%s:16:16|a "):format(atlas) or ""
    local itemLink = ("|cffffff00|Hworldmap:%d:%d:%d|h[%s]|h|r"):format(
        mapID,
        math.floor(posX * 10000 + 0.5),
        math.floor(posY * 10000 + 0.5),
        MAP_PIN_HYPERLINK
    )
    CludesUI.Print(
        CC.BRAND
            .. "CludesUI:|r "
            .. itemLink
            .. " "
            .. iconTex
            .. CC.WHITE
            .. labelText
            .. "|r "
            .. CC.DIM
            .. ("%.1f, %.1f"):format(posX * 100, posY * 100)
            .. "|r"
    )
    if not hintedClick then
        hintedClick = true
        CludesUI.Print(
            CC.BRAND
                .. "CludesUI:|r "
                .. CC.DIM
                .. CludesUI.L("Click a link to place the pin, then click the pin on the map to track it.")
                .. "|r"
        )
    end
end

-- A left click on a pin: its link in chat, led by its icon, kind and name, on
-- the zone it stands in (world and continent maps take no pin). A line
-- printed in combat taints chat history, so it waits for the end of combat.
local function PinOnMouseUp(self, btnFrame)
    if btnFrame ~= "LeftButton" or not C_Map.CanSetUserWaypointOnMap(self.linkMap) then
        return
    end
    local mapID, posX, posY, atlas = self.linkMap, self.linkX, self.linkY, self.atlas
    local labelText = self.link or PinLabel(self.tip)
    local function Print()
        PrintLink(mapID, posX, posY, labelText, atlas)
    end
    if InCombatLockdown() then
        CludesUI.CombatQueue.Defer("MapTravelLink", Print)
    else
        Print()
    end
end

local function Clear()
    for index = 1, used do
        pins[index]:Hide()
    end
    used = 0
    shownKey = nil
end

-- Right clicks pass through every pin to the map. SetPassThroughButtons is
-- protected in combat: set once per pin, a pin made in combat waits for its end.
local function PassRightClicks()
    for index = 1, #pins do
        local p = pins[index]
        if not p.passes then
            p:SetPassThroughButtons("RightButton")
            p.passes = true
        end
    end
end

-- The next pin from our pool: hover names it, a left click links it.
local function NextPin()
    used = used + 1
    local p = pins[used]
    if not p then
        p = CreateFrame("Frame", nil, layer)
        p:SetMouseMotionEnabled(true)
        p:SetMouseClickEnabled(true)
        p:SetScript("OnMouseUp", PinOnMouseUp)
        p.tex = p:CreateTexture(nil, "ARTWORK")
        p.tex:SetAllPoints()
        p.count = p:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        p.count:SetPoint("BOTTOMRIGHT", 4, -2)
        p:SetScript("OnEnter", PinOnEnter)
        p:SetScript("OnLeave", PinOnLeave)
        pins[used] = p
        if InCombatLockdown() then
            CludesUI.CombatQueue.Defer("MapTravelPass", PassRightClicks)
        else
            PassRightClicks()
        end
    end
    return p
end

-- Pins are scaled against the canvas, so they keep one size on screen at any
-- zoom; their offsets are in their own (scaled) units.
local function Anchor(p)
    local canvas = layer:GetParent()
    local wid, hgt = canvas:GetSize()
    local cs = canvas:GetScale()
    p:SetScale(1 / cs)
    p:ClearAllPoints()
    p:SetPoint("CENTER", canvas, "TOPLEFT", p.x * wid * cs, -p.y * hgt * cs)
end

-- A pin at (x, y) of the canvas (0..1); count > 1 shows as a badge. link: its
-- kind and name for the chat line ("Dungeon: The Deadmines"). Its chat link
-- points at the shown map; a pin drawn from a zone onto a wider map points
-- back at the zone (the caller sets linkMap, linkX, linkY).
local function Place(posX, posY, atlas, size, tipText, rotation, total, itemLink)
    local p = NextPin()
    p.x, p.y, p.size = posX, posY, size
    p:SetSize(size, size)
    Anchor(p)
    if atlas:find("\\", 1, true) then
        p.tex:SetTexture(atlas)
    else
        p.tex:SetAtlas(atlas)
    end
    p.tex:SetRotation(rotation or 0)
    p.count:SetText(total and total > 1 and total or "")
    p.tip, p.link, p.atlas = tipText, itemLink, atlas
    p.linkMap, p.linkX, p.linkY = shownMap, posX, posY
    p:Show()
    return p
end

-- A zoom: the same pins, rescaled (rebuilding them would drop the tooltip).
local function Rescale()
    for index = 1, used do
        Anchor(pins[index])
    end
end

local function ZoneName(uiMapID)
    local details = C_Map.GetMapInfo(uiMapID)
    return details and details.name or ""
end

local function TransportTip(tbl)
    -- The place alone ("Orgrimmar"), its zone when the area has no name.
    local area = C_Map.GetAreaInfo(tbl[5])
    local where = area and area ~= "" and area or ZoneName(tbl[4])
    if tbl[3] == "boat" then
        return CludesUI.Lf("Boat to %s", where)
    end
    if tbl[3] == "zeppelin" then
        return CludesUI.Lf("Zeppelin to %s", where)
    end
    if tbl[3] == "skycutter" then
        return CludesUI.Lf("Skycutter to %s", where)
    end
    if tbl[3] == "portal" then
        return CludesUI.Lf("Portal to %s", where)
    end
    return CludesUI.Lf("Tram to %s", where)
end

-- The instance's name, the entrance or wings it opens on, then its kind.
local function InstanceTip(index)
    local tipText = GetRealZoneText(index[3])
    if index[5] then
        tipText = tipText .. "\n|cffffffff" .. CludesUI.L(index[5]) .. "|r"
    end
    return tipText .. "\n" .. (index[4] and CludesUI.L("Raid") or CludesUI.L("Dungeon"))
end

-- Its chat line: "Dungeon: The Deadmines (Main Entrance)".
local function InstanceLink(index)
    local name = GetRealZoneText(index[3])
    if index[5] then
        name = name .. " (" .. CludesUI.L(index[5]) .. ")"
    end
    return index[4] and CludesUI.Lf("Raid: %s", name) or CludesUI.Lf("Dungeon: %s", name)
end

-- The arrow's angle toward the destination zone's middle, read on the continent.
local function ExitRotation(zone, posX, posY, dest)
    local details = C_Map.GetMapInfo(zone)
    local continent = details and details.parentMapID
    if not continent or continent == 0 then
        return 0
    end
    local zl, zr, zt, zb = C_Map.GetMapRectOnMap(zone, continent)
    local left, right, top, bottom = C_Map.GetMapRectOnMap(dest, continent)
    if not (zl and left) then
        return 0
    end
    local px, py = zl + posX * (zr - zl), zt + posY * (zb - zt)
    local dx, dy = (left + right) / 2 - px, (top + bottom) / 2 - py
    return math.atan2(-dx, -dy) -- the atlas points up; screen y grows down
end

-- A zone's transports, those of one place (a dock's boats, a tower's
-- zeppelins) sharing one pin whose tooltip lists them all. Built once per zone.
local GROUP_DIST = 7 -- percent of the zone map
local transportGroups = {}
local function TransportGroups(zone)
    local groups = transportGroups[zone]
    if groups then
        return groups
    end
    groups = {}
    local entries = payload.transports[zone] or {}
    for index = 1, #entries do
        local tbl = entries[index]
        local g
        for jdx = 1, #groups do
            local hgt = groups[jdx]
            if math.abs(hgt.x - tbl[1]) < GROUP_DIST and math.abs(hgt.y - tbl[2]) < GROUP_DIST then
                g = hgt
                break
            end
        end
        -- Each destination on its own line, led by its transport's icon.
        local line = ("|A:%s:16:16|a %s"):format(KIND_ATLAS[tbl[3]], TransportTip(tbl))
        if g then
            g.tip = g.tip .. "\n" .. line
            g.link = g.link .. ", " .. TransportTip(tbl)
            g.count = g.count + 1
        else
            groups[#groups + 1] = {
                x = tbl[1],
                y = tbl[2],
                atlas = KIND_ATLAS[tbl[3]],
                tip = line,
                link = TransportTip(tbl),
                count = 1,
            }
        end
    end
    transportGroups[zone] = groups
    return groups
end

-- A zone map's pins.
local function DrawZone(zone)
    if On("transports") then
        local groups = TransportGroups(zone)
        for index = 1, #groups do
            local g = groups[index]
            Place(g.x / 100, g.y / 100, g.atlas, PIN_SIZE, g.tip, nil, g.count, g.link)
        end
    end
    if On("instances") then
        local entries = payload.instances[zone]
        if entries then
            for index = 1, #entries do
                local entry = entries[index]
                Place(
                    entry[1] / 100,
                    entry[2] / 100,
                    entry[4] and "raid" or "dungeon",
                    INSTANCE_SIZE,
                    InstanceTip(entry),
                    nil,
                    nil,
                    InstanceLink(entry)
                )
            end
        end
    end
    if On("exits") then
        local entries = payload.exits[zone]
        if entries then
            for index = 1, #entries do
                local entry = entries[index]
                local posX, posY = entry[1] / 100, entry[2] / 100
                Place(
                    posX,
                    posY,
                    "poi-traveldirections-arrow",
                    ARROW_SIZE,
                    ZoneName(entry[3]),
                    ExitRotation(zone, posX, posY, entry[3]),
                    nil,
                    CludesUI.Lf("Path from %s to %s", ZoneName(zone), ZoneName(entry[3]))
                )
            end
        end
    end
end

-- A zone's point (0..1) on a wider map that holds it, or nil.
local function OnWiderMap(zone, map, posX, posY)
    local left, right, top, bottom = C_Map.GetMapRectOnMap(zone, map)
    if not left or right <= left or bottom <= top then
        return nil
    end
    posX, posY = left + posX * (right - left), top + posY * (bottom - top)
    if posX < 0 or posX > 1 or posY < 0 or posY > 1 then
        return nil
    end
    return posX, posY
end

-- A world or continent map's pins: the transports, and on a continent the
-- instance entrances too, each linking back to its zone.
local function DrawWider(map, instances)
    if On("transports") then
        for zone in pairs(payload.transports) do
            local groups = TransportGroups(zone)
            for index = 1, #groups do
                local g = groups[index]
                local posX, posY = OnWiderMap(zone, map, g.x / 100, g.y / 100)
                if posX then
                    local p = Place(posX, posY, g.atlas, PIN_SIZE, g.tip, nil, g.count, g.link)
                    p.linkMap, p.linkX, p.linkY = zone, g.x / 100, g.y / 100
                end
            end
        end
    end
    if instances and On("instances") then
        for zone, entries in pairs(payload.instances) do
            for index = 1, #entries do
                local entry = entries[index]
                local posX, posY = OnWiderMap(zone, map, entry[1] / 100, entry[2] / 100)
                if posX then
                    local p = Place(
                        posX,
                        posY,
                        entry[4] and "raid" or "dungeon",
                        INSTANCE_SIZE,
                        InstanceTip(entry),
                        nil,
                        nil,
                        InstanceLink(entry)
                    )
                    p.linkMap, p.linkX, p.linkY = zone, entry[1] / 100, entry[2] / 100
                end
            end
        end
    end
end

-- The flight masters standing on a map (the game also lists those of the rest
-- of the continent, off its edges), the other faction's and the retired ones
-- ("zz" names) left out; none where the map draws its own.
local function FlightNodes(mapID)
    if C_TaxiMap.ShouldMapShowTaxiNodes(mapID) then
        return nil
    end
    local nodes = C_TaxiMap.GetTaxiNodesForMap(mapID)
    if not nodes then
        return nil
    end
    local Faction = Enum.FlightPathFaction
    local mine = UnitFactionGroup("player") == "Horde" and Faction.Horde or Faction.Alliance
    local entries = {}
    for index = 1, #nodes do
        local num = nodes[index]
        local posX, posY = num.position.x, num.position.y
        if
            (num.faction == Faction.Neutral or num.faction == mine)
            and not num.name:find("^zz")
            and posX >= 0
            and posX <= 1
            and posY >= 0
            and posY <= 1
        then
            if num.isUndiscovered then
                num.note = num.faction == Faction.Neutral and UNDISCOVERED_NEUTRAL_FLIGHTPOINT
                    or UNDISCOVERED_FACTION_FLIGHTPOINT:format(
                        mine == Faction.Horde and FACTION_HORDE or FACTION_ALLIANCE
                    )
            end
            if num.atlasName == "" then
                num.atlasName = "flightmaster"
            end
            entries[#entries + 1] = num
        end
    end
    return entries
end

local function DrawFlights(mapID)
    local entries = FlightNodes(mapID)
    if not entries then
        return
    end
    for index = 1, #entries do
        local num = entries[index]
        local tipText = num.note and (num.name .. "\n|cff808080" .. num.note .. "|r") or num.name
        Place(
            num.position.x,
            num.position.y,
            num.atlasName,
            PIN_SIZE,
            tipText,
            nil,
            nil,
            CludesUI.Lf("Flight Point: %s", num.name)
        )
    end
end

-- The map redraws its providers often (shows, quest and area updates): the
-- pins are rebuilt only when the map or the toggles changed, so a hovered
-- pin keeps its tooltip.
local function Refresh(force)
    local mapID = WorldMapFrame:GetMapID()
    -- One number for the map and the four toggles: no string per refresh.
    local key = mapID
        and (
            mapID * 16
            + (On("transports") and 1 or 0)
            + (On("instances") and 2 or 0)
            + (On("exits") and 4 or 0)
            + (On("flights") and 8 or 0)
        )
    if key and key == shownKey and force ~= true then
        Rescale()
        return
    end
    Clear()
    shownKey = key
    shownMap = mapID
    local details = mapID and C_Map.GetMapInfo(mapID)
    if not details then
        return
    end
    -- The world shows the transports; a continent adds the instance entrances;
    -- a zone adds the flight points and its exits.
    if details.mapType == Enum.UIMapType.World then
        DrawWider(mapID, false)
    elseif details.mapType == Enum.UIMapType.Continent then
        DrawWider(mapID, true)
    elseif details.mapType ~= Enum.UIMapType.Cosmic then
        if On("flights") then
            DrawFlights(mapID)
        end
        DrawZone(mapID)
    end
end

local function Build()
    payload = module.MapTravelData()
    module.MapTravelData = nil

    layer = CreateFrame("Frame", nil, WorldMapFrame.ScrollContainer.Child)
    layer:SetAllPoints()
    -- Above the map's own points of interest (a city's pin must not take the
    -- mouse from a dock or a tower beside it).
    layer:SetFrameLevel(
        WorldMapFrame:GetPinFrameLevelsManager():GetValidFrameLevel("PIN_FRAME_LEVEL_MAP_LINK")
    )

    provider = CreateFromMixins(MapCanvasDataProviderMixin)
    provider.OnMapChanged = function()
        Refresh()
    end
    provider.RefreshAllData = function()
        Refresh()
    end
    provider.RemoveAllData = Clear
    provider.OnCanvasScaleChanged = Rescale
    provider.OnGlobalAlphaChanged = function(self)
        layer:SetAlpha(self:GetMap():GetGlobalAlpha())
    end
end

-- Nothing exists until Map Markers is first on; off, the provider is removed.
-- The world map loads on demand, so building may wait for it.
local function Apply()
    if not AnyOn() then
        if added then
            WorldMapFrame:RemoveDataProvider(provider)
            added = false
        end
        if waiter then
            waiter:UnregisterEvent("ADDON_LOADED")
        end
        if taxiWatch then
            taxiWatch:UnregisterEvent("TAXI_NODE_STATUS_CHANGED")
        end
        return
    end
    if not provider then
        if not C_AddOns.IsAddOnLoaded("Blizzard_WorldMap") then
            if not waiter then
                waiter = CreateFrame("Frame")
                waiter:SetScript("OnEvent", function(self, _, name)
                    if name ~= "Blizzard_WorldMap" then
                        return
                    end
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
    end
    -- A flight point found: the next draw rebuilds the pins.
    if On("flights") then
        if not taxiWatch then
            taxiWatch = CreateFrame("Frame")
            taxiWatch:SetScript("OnEvent", function()
                shownKey = nil
            end)
        end
        taxiWatch:RegisterEvent("TAXI_NODE_STATUS_CHANGED")
    elseif taxiWatch then
        taxiWatch:UnregisterEvent("TAXI_NODE_STATUS_CHANGED")
    end
    if WorldMapFrame:IsShown() then
        Refresh(true)
    end
end

-- Options-page entry points.
CludesUI._MapTravel = {
    Get = F.Get,
    On = On,
    Cfg = F.Cfg,
    Apply = Apply,
}

F.Start(Apply)
