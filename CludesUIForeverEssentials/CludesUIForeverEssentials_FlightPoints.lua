if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
if not (CUI and CUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_FlightPoints.lua  (WoW Forever only)
--  Flight Point Reminder: "Learn the Crossroads flight point" on a small card
--  when you reach a town (its subzone, or within 400 yards) whose flight
--  point you have not learned, and for 10 seconds as you enter a zone that
--  has one. Capitals only count their own flight master.
--
--  What you know: opening a flight master's map saves every point on that
--  continent as known or not (C_TaxiMap); talking to a flight master (its
--  taxi gossip line) marks theirs. Until a continent's map has been seen,
--  a point the game reports as undiscovered still reminds you, and the card
--  says to open a flight master's map. Saved per character in
--  CludesUIDB.flightPointsKnown["Name-Realm"]. Hidden in combat and on
--  flights.
-------------------------------------------------------------------------------
local _, module = ...

local F = module.Feature(
    "flightPoints",
    { enabled = false, textSize = 15 },
    { point = "TOP", relPoint = "TOP", x = 0, y = -190 }
)
local Get, Enabled = F.Get, F.Enabled

local TOWN_YARDS = 400
local MASTER_YARDS = 50
local NOTICE_SECONDS = 10
local PAD = 10
local ZONE_TYPE = Enum.UIMapType.Zone
local CONTINENT_TYPE = Enum.UIMapType.Continent
local TAXI_CONTINENTS = { [1415] = 1463, [1414] = 1464 }
local SIDE_N = Enum.FlightPathFaction and Enum.FlightPathFaction.Neutral
local SIDE_H = Enum.FlightPathFaction and Enum.FlightPathFaction.Horde
local SIDE_A = Enum.FlightPathFaction and Enum.FlightPathFaction.Alliance
local STATE_UNREACHABLE = Enum.FlightPathState and Enum.FlightPathState.Unreachable
local MAP_ALIAS = { [2665] = 2521 }
local CITY_ZONES = { [1453] = true, [1454] = true, [1455] = true, [1456] = true, [1457] = true, [1458] = true, [2482] = true, [2521] = true }
local RETIRED_NODES = { "zzOLD", "Quest Path", "[DNT]", "DEPRECATED" }
local UNSEEN_TEXT = { [59] = true, [60] = true, [62] = true, [63] = true, [84] = true, [85] = true, [86] = true, [87] = true }
local GOSSIP_TAXI_ICON = "Interface\\GossipFrame\\TaxiGossipIcon"
local LEARN_TEXT, ASK_RANGE = "learn", "ask"
local WATCHED = {
    "ZONE_CHANGED",
    "ZONE_CHANGED_INDOORS",
    "ZONE_CHANGED_NEW_AREA",
    "PLAYER_ENTERING_WORLD",
    "PLAYER_STOPPED_MOVING",
    "GOSSIP_SHOW",
    "TAXIMAP_OPENED",
    "TAXIMAP_CLOSED",
    "PLAYER_CONTROL_LOST",
    "PLAYER_CONTROL_GAINED",
    "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED",
}
local RECHECK = {
    ZONE_CHANGED = true,
    ZONE_CHANGED_INDOORS = true,
    ZONE_CHANGED_NEW_AREA = true,
    PLAYER_ENTERING_WORLD = true,
    TAXIMAP_OPENED = true,
    TAXIMAP_CLOSED = true,
}

local frame, fighting, gossipIcon
local nodesZone, nodesMap, nodesList
local noticeZone, noticeShown, noticeNode, noticePlace, noticeTimer
local events = CreateFrame("Frame")

local function Secret(v) return issecretvalue and issecretvalue(v) end
local function AliasMap(map) return MAP_ALIAS[map] or map end

-- This character's saved points (nil while it has none and create is false).
local function MyPoints(create)
    if not CludesUIDB then return nil end
    local key = (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
    local all = CludesUIDB.flightPointsKnown
    if not all then
        if not create then return nil end
        all = {}
        CludesUIDB.flightPointsKnown = all
    end
    if not all[key] and create then all[key] = {} end
    return all[key]
end

local function TownName(name)
    local commaAt = name:find(",", 1, true)
    return commaAt and name:sub(1, commaAt - 1) or name
end

local function WordEdge(text, at) return at < 1 or at > #text or not text:sub(at, at):match("%a") end
local function ContainsWord(haystack, word)
    if word == "" then return false end
    local from = 1
    while true do
        local at = haystack:find(word, from, true)
        if not at then return false end
        if WordEdge(haystack, at - 1) and WordEdge(haystack, at + #word) then return true end
        from = at + 1
    end
end
local function CityMaster(town, zoneTitle)
    if zoneTitle == "" then return false end
    return town == zoneTitle or ContainsWord(zoneTitle, town) or ContainsWord(town, zoneTitle)
end

local function IsRetired(name)
    for _, pin in ipairs(RETIRED_NODES) do
        if name:find(pin, 1, true) then return true end
    end
    return false
end

local function OurFaction(myFaction)
    if myFaction == SIDE_N then return true end
    local nodeSide = UnitFactionGroup("player")
    if nodeSide == "Horde" then return myFaction == SIDE_H end
    if nodeSide == "Alliance" then return myFaction == SIDE_A end
    return false
end

local function Kind(tn, myPoints, seenMaps)
    if not (tn and OurFaction(tn.faction) and tn.name) or IsRetired(tn.name) then return nil end
    if myPoints and tn.nodeID and myPoints[tn.nodeID] == true then return nil end
    if tn.isUndiscovered then return LEARN_TEXT end
    if seenMaps then return LEARN_TEXT end
    return ASK_RANGE
end

local function ParentOfType(id, mapType)
    local info = id and C_Map.GetMapInfo(id)
    while info and info.mapType > mapType and info.parentMapID and info.parentMapID > 0 do
        info = C_Map.GetMapInfo(info.parentMapID)
    end
    if info and info.mapType == mapType then return info.mapID end
end

local function SeenContinent(myPoints, zone)
    local maps = myPoints and myPoints.seenMaps
    local landmass = ParentOfType(zone, CONTINENT_TYPE) or zone
    return maps and landmass and (maps[landmass] or maps[TAXI_CONTINENTS[landmass]])
end

-- A flight master's map is open: every point on it, known or not.
local function ReadTaxiMap()
    local taxiMap = GetTaxiMapID and GetTaxiMapID()
    local myPoints = taxiMap and MyPoints(true)
    if not myPoints then return end
    local playerMap = C_Map.GetBestMapForUnit("player")
    local landmass = ParentOfType(playerMap, CONTINENT_TYPE) or ParentOfType(AliasMap(playerMap), ZONE_TYPE)
    local taxiLand = ParentOfType(taxiMap, CONTINENT_TYPE)
    myPoints.seenMaps = myPoints.seenMaps or {}
    myPoints.seenMaps[taxiMap] = true
    if taxiLand then myPoints.seenMaps[taxiLand] = true end
    if landmass then myPoints.seenMaps[landmass] = true end
    for _, tn in ipairs(C_TaxiMap.GetAllTaxiNodes(taxiMap) or {}) do
        if tn.nodeID then myPoints[tn.nodeID] = tn.state ~= STATE_UNREACHABLE end
    end
end

local function SubzoneText()
    local text = GetSubZoneText()
    if not text or Secret(text) then return "" end
    return text
end

local function WorldSpot(map, pos)
    if not map or not pos then return nil, false end
    if Secret(pos.x) or Secret(pos.y) then return nil, true end
    local landmass, worldPos = C_Map.GetWorldPosFromMapPos(map, pos)
    if not worldPos then return nil, false end
    if Secret(worldPos.x) or Secret(worldPos.y) then return nil, true end
    return worldPos, false, landmass
end

local function YardsBetween(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

local function DropNodeCache() nodesZone, nodesMap, nodesList = nil, nil, nil end

local function SameZone(zone, worldPos, landmass)
    if not worldPos or not landmass then return false end
    local top = ParentOfType(zone, CONTINENT_TYPE)
    local _, pos = C_Map.GetMapPosFromWorldPos(landmass, worldPos, top or zone)
    if not pos or Secret(pos.x) or Secret(pos.y) then return false end
    if top then
        local info = C_Map.GetMapInfoAtPosition(top, pos.x, pos.y)
        return info ~= nil and info.mapID == zone
    end
    return pos.x >= 0 and pos.x <= 1 and pos.y >= 0 and pos.y <= 1
end

-- The zone's flight points with their world positions; the zone's own map
-- first, else the nearest parent short of the continent that has some.
local function ZoneNodes(zone)
    if nodesZone == zone and nodesList then return nodesMap, nodesList end
    local taxiNodes = C_TaxiMap.GetTaxiNodesForMap(zone) or {}
    local map = zone
    if not taxiNodes[1] then
        local info = C_Map.GetMapInfo(zone)
        map, taxiNodes = nil, nil
        while info and info.parentMapID and info.parentMapID > 0 do
            local parent = info.parentMapID
            info = C_Map.GetMapInfo(parent)
            if info and info.mapType < CONTINENT_TYPE then break end
            local list = C_TaxiMap.GetTaxiNodesForMap(parent) or {}
            if list[1] then
                map, taxiNodes = parent, list
                break
            end
            if not info or info.mapType == CONTINENT_TYPE then break end
        end
    end
    if not taxiNodes then
        nodesZone, nodesMap, nodesList = zone, nil, {}
        return nil, nodesList
    end
    local ready = {}
    for _, tn in ipairs(taxiNodes) do
        if not UNSEEN_TEXT[tn.nodeID] then
            local worldPos, hidden, landmass = WorldSpot(map, tn.position)
            if hidden then return nil, nil, true end
            ready[#ready + 1] = { node = tn, world = worldPos, continent = landmass, inZone = SameZone(zone, worldPos, landmass) }
        end
    end
    nodesZone, nodesMap, nodesList = zone, map, ready
    return map, ready
end

local function Unlearned(rowRec, map, zone, zoneTitle, player, landmass, sub, myPoints, seenMaps, wholeZone)
    local tn = rowRec.node
    local kind = Kind(tn, myPoints, seenMaps)
    if not kind then return nil end
    if landmass and rowRec.continent and rowRec.continent ~= landmass then return nil end
    local yardsAway = player and rowRec.world and YardsBetween(player, rowRec.world)
    local town = TownName(tn.name)
    if CITY_ZONES[zone] and (map == zone or wholeZone) then
        if not CityMaster(town, zoneTitle) then return nil end
    elseif wholeZone then
        if not rowRec.inZone then return nil end
    else
        local byName = sub ~= "" and sub == town
        if not (byName or (yardsAway and yardsAway <= TOWN_YARDS)) then return nil end
    end
    return kind, town, yardsAway or math.huge
end

-- The nearest unlearned point here (zoneWide: anywhere in the zone): its
-- place, whether only an unsure one was found, its node and distance.
local function ClosestUnlearned(wholeZone)
    if fighting or UnitOnTaxi("player") then return nil end
    local playerMap = C_Map.GetBestMapForUnit("player")
    local zone = ParentOfType(AliasMap(playerMap), ZONE_TYPE)
    if not zone then return nil end
    local player, isSecret, landmass = WorldSpot(playerMap, playerMap and C_Map.GetPlayerMapPosition(playerMap, "player"))
    if isSecret then return nil end
    local info = C_Map.GetMapInfo(zone)
    local sub, myPoints = SubzoneText(), MyPoints()
    local seenMaps = SeenContinent(myPoints, zone)
    local map, rows, hidden = ZoneNodes(zone)
    if hidden or not map then return nil end
    local nearName, nearYards, nearNode, ask, askYards, askAt
    for _, rowRec in ipairs(rows) do
        local kind, town, order =
            Unlearned(rowRec, map, zone, info and info.name or "", player, landmass, sub, myPoints, seenMaps, wholeZone)
        if kind == LEARN_TEXT and (not nearName or order < nearYards) then
            nearName, nearYards, nearNode = town, order, rowRec.node
        elseif kind == ASK_RANGE and (not ask or order < askYards) then
            ask, askYards, askAt = true, order, rowRec.node
        end
    end
    if nearName then return nearName, nil, nearNode, nearYards end
    return nil, ask, askAt, askYards
end

-------------------------------------------------------------------------------
--  The card
-------------------------------------------------------------------------------

local function MakeCard()
    if frame then return frame end
    local Kit = CUI.Kit
    frame = CreateFrame("Frame", "CludesUIFlightPointReminder", UIParent)
    frame:SetSize(300, 30)
    Kit.Panel(frame, 0.75)
    frame.text = frame:CreateFontString(nil, "OVERLAY")
    frame.text:SetPoint("CENTER")
    frame:Hide()
    return frame
end

local function StyleCard()
    local Kit = CUI.Kit
    local size = Get("textSize")
    Kit.Font(frame.text, size, "essentials")
    frame.text:SetTextColor(Kit.Accent())
    frame:SetHeight(size + 2 * PAD)
end

local function ShowCard(town)
    if town then
        frame.text:SetText(CUI.Lf("Learn the %1$s flight point", (town:gsub("^The ", ""))))
    else
        frame.text:SetText(CUI.L("Open a flight master's map to save the points you know"))
    end
    frame:SetWidth(math.max(120, frame.text:GetStringWidth() + 2 * PAD + 8))
    frame:Show()
end

local function StopZoneNotice()
    if noticeTimer then noticeTimer:Cancel() end
    noticeTimer, noticeNode, noticePlace = nil, nil, nil
end

local Refresh
local function ZoneNoticeOver()
    noticeTimer, noticeNode, noticePlace = nil, nil, nil
    Refresh()
end

Refresh = function()
    if not frame then return end
    if CUI._unlockActive then
        ShowCard("Ratchet")
        return
    end
    local zone = ParentOfType(C_Map.GetBestMapForUnit("player"), ZONE_TYPE)
    if zone ~= noticeZone then
        StopZoneNotice()
        noticeZone, noticeShown = zone, false
    end
    if zone and not noticeShown then
        local town, ask, tn = ClosestUnlearned(true)
        if town or ask then
            noticeShown, noticeNode, noticePlace = true, tn, town
            noticeTimer = C_Timer.NewTimer(NOTICE_SECONDS, ZoneNoticeOver)
        end
    end
    local town, ask = ClosestUnlearned()
    if town or ask then
        ShowCard(town)
    elseif noticeTimer and not fighting and not UnitOnTaxi("player") and Kind(noticeNode, MyPoints(), false) then
        ShowCard(noticePlace)
    else
        frame:Hide()
    end
end

-- Talking to a flight master (its taxi line) marks the point beside you.
local function HasTaxiOption()
    if gossipIcon == nil then
        local nodeKey = GetFileIDFromPath and GetFileIDFromPath(GOSSIP_TAXI_ICON)
        gossipIcon = (nodeKey and nodeKey ~= 0) and nodeKey or false
    end
    if not gossipIcon then return false end
    for _, opt in ipairs(C_GossipInfo.GetOptions() or {}) do
        if opt.icon == gossipIcon then return true end
    end
    return false
end

local function OnTaxiGossip()
    if not HasTaxiOption() then return end
    local _, _, tn, yd = ClosestUnlearned()
    if not (tn and tn.nodeID) or (yd ~= math.huge and yd > MASTER_YARDS) then return end
    local myPoints = MyPoints(true)
    if myPoints then myPoints[tn.nodeID] = true end
end

events:SetScript("OnEvent", function(_, ev)
    if RECHECK[ev] then DropNodeCache() end
    if ev == "PLAYER_REGEN_DISABLED" then
        fighting = true
    elseif ev == "PLAYER_REGEN_ENABLED" then
        fighting = false
    elseif ev == "TAXIMAP_OPENED" then
        ReadTaxiMap()
    elseif ev == "GOSSIP_SHOW" then
        OnTaxiGossip()
    end
    Refresh()
end)

local function Apply()
    events:UnregisterAllEvents()
    DropNodeCache()
    if not Enabled() then
        StopZoneNotice()
        noticeZone, noticeShown = nil, nil
        if frame then frame:Hide() end
        return
    end
    MakeCard()
    StyleCard()
    if not CUI._unlockActive then F.Place(frame) end
    fighting = UnitAffectingCombat("player")
    for _, ev in ipairs(WATCHED) do
        events:RegisterEvent(ev)
    end
    Refresh()
end

if CUI.RegisterUnlockModeListener then
    CUI:RegisterUnlockModeListener("CUI_FlightPoints", function()
        if frame and Enabled() then Refresh() end
    end)
end

CUI._FlightPoints = { Get = Get, Cfg = F.Cfg, Apply = Apply }

F.Start(Apply, {
    key = "CUI_FlightPoints",
    label = "Flight Point Reminder",
    order = 761,
    frame = function(build)
        if build then
            MakeCard()
            StyleCard()
        end
        return frame
    end,
    size = function() return 300, Get("textSize") + 2 * PAD end,
    noAnchorTarget = true,
    noSizeMatchTarget = true,
})
