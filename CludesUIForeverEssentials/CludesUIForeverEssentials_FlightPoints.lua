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

local TOWN_RANGE = 400
local MASTER_REACH = 50
local ZONE_HOLD = 10
local PAD = 10
local ZONE = Enum.UIMapType.Zone
local CONTINENT = Enum.UIMapType.Continent
local TAXI_MAPS = { [1415] = 1463, [1414] = 1464 }
local NEUTRAL = Enum.FlightPathFaction and Enum.FlightPathFaction.Neutral
local HORDE = Enum.FlightPathFaction and Enum.FlightPathFaction.Horde
local ALLIANCE = Enum.FlightPathFaction and Enum.FlightPathFaction.Alliance
local UNREACHABLE = Enum.FlightPathState and Enum.FlightPathState.Unreachable
local SAME_MAP = { [2665] = 2521 }
local CAPITALS = { [1453] = true, [1454] = true, [1455] = true, [1456] = true, [1457] = true, [1458] = true, [2482] = true, [2521] = true }
local RETIRED = { "zzOLD", "Quest Path", "[DNT]", "DEPRECATED" }
local NO_DISCOVERY = { [59] = true, [60] = true, [62] = true, [63] = true, [84] = true, [85] = true, [86] = true, [87] = true }
local TAXI_ICON = "Interface\\GossipFrame\\TaxiGossipIcon"
local LEARN, ASK = "learn", "ask"
local EVENTS = {
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
local REFRESH = {
    ZONE_CHANGED = true,
    ZONE_CHANGED_INDOORS = true,
    ZONE_CHANGED_NEW_AREA = true,
    PLAYER_ENTERING_WORLD = true,
    TAXIMAP_OPENED = true,
    TAXIMAP_CLOSED = true,
}

local frame, inCombat, taxiIcon
local cachedZone, cachedMap, cachedNodes
local entryZone, entryNotified, entryNode, entryPlace, entryTimer
local events = CreateFrame("Frame")

local function Secret(v) return issecretvalue and issecretvalue(v) end
local function SameMap(map) return SAME_MAP[map] or map end

-- This character's saved points (nil while it has none and create is false).
local function Mine(create)
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

local function PlaceName(name)
    local comma = name:find(",", 1, true)
    return comma and name:sub(1, comma - 1) or name
end

local function Edge(text, at) return at < 1 or at > #text or not text:sub(at, at):match("%a") end
local function HasWord(hay, needle)
    if needle == "" then return false end
    local from = 1
    while true do
        local at = hay:find(needle, from, true)
        if not at then return false end
        if Edge(hay, at - 1) and Edge(hay, at + #needle) then return true end
        from = at + 1
    end
end
local function OwnCity(place, zoneName)
    if zoneName == "" then return false end
    return place == zoneName or HasWord(zoneName, place) or HasWord(place, zoneName)
end

local function Retired(name)
    for _, mark in ipairs(RETIRED) do
        if name:find(mark, 1, true) then return true end
    end
    return false
end

local function Ours(faction)
    if faction == NEUTRAL then return true end
    local side = UnitFactionGroup("player")
    if side == "Horde" then return faction == HORDE end
    if side == "Alliance" then return faction == ALLIANCE end
    return false
end

local function Kind(node, mine, seen)
    if not (node and Ours(node.faction) and node.name) or Retired(node.name) then return nil end
    if mine and node.nodeID and mine[node.nodeID] == true then return nil end
    if node.isUndiscovered then return LEARN end
    if seen then return LEARN end
    return ASK
end

local function Up(id, mapType)
    local info = id and C_Map.GetMapInfo(id)
    while info and info.mapType > mapType and info.parentMapID and info.parentMapID > 0 do
        info = C_Map.GetMapInfo(info.parentMapID)
    end
    if info and info.mapType == mapType then return info.mapID end
end

local function Seen(mine, zone)
    local maps = mine and mine.seenMaps
    local continent = Up(zone, CONTINENT) or zone
    return maps and continent and (maps[continent] or maps[TAXI_MAPS[continent]])
end

-- A flight master's map is open: every point on it, known or not.
local function Learn()
    local taxi = GetTaxiMapID and GetTaxiMapID()
    local mine = taxi and Mine(true)
    if not mine then return end
    local here = C_Map.GetBestMapForUnit("player")
    local continent = Up(here, CONTINENT) or Up(SameMap(here), ZONE)
    local taxiContinent = Up(taxi, CONTINENT)
    mine.seenMaps = mine.seenMaps or {}
    mine.seenMaps[taxi] = true
    if taxiContinent then mine.seenMaps[taxiContinent] = true end
    if continent then mine.seenMaps[continent] = true end
    for _, node in ipairs(C_TaxiMap.GetAllTaxiNodes(taxi) or {}) do
        if node.nodeID then mine[node.nodeID] = node.state ~= UNREACHABLE end
    end
end

local function Subzone()
    local text = GetSubZoneText()
    if not text or Secret(text) then return "" end
    return text
end

local function WorldOf(map, pos)
    if not map or not pos then return nil, false end
    if Secret(pos.x) or Secret(pos.y) then return nil, true end
    local continent, world = C_Map.GetWorldPosFromMapPos(map, pos)
    if not world then return nil, false end
    if Secret(world.x) or Secret(world.y) then return nil, true end
    return world, false, continent
end

local function Yards(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

local function ForgetNodes() cachedZone, cachedMap, cachedNodes = nil, nil, nil end

local function InZone(zone, world, continent)
    if not world or not continent then return false end
    local top = Up(zone, CONTINENT)
    local _, pos = C_Map.GetMapPosFromWorldPos(continent, world, top or zone)
    if not pos or Secret(pos.x) or Secret(pos.y) then return false end
    if top then
        local info = C_Map.GetMapInfoAtPosition(top, pos.x, pos.y)
        return info ~= nil and info.mapID == zone
    end
    return pos.x >= 0 and pos.x <= 1 and pos.y >= 0 and pos.y <= 1
end

-- The zone's flight points with their world positions; the zone's own map
-- first, else the nearest parent short of the continent that has some.
local function NodesFor(zone)
    if cachedZone == zone and cachedNodes then return cachedMap, cachedNodes end
    local nodes = C_TaxiMap.GetTaxiNodesForMap(zone) or {}
    local map = zone
    if not nodes[1] then
        local info = C_Map.GetMapInfo(zone)
        map, nodes = nil, nil
        while info and info.parentMapID and info.parentMapID > 0 do
            local parent = info.parentMapID
            info = C_Map.GetMapInfo(parent)
            if info and info.mapType < CONTINENT then break end
            local list = C_TaxiMap.GetTaxiNodesForMap(parent) or {}
            if list[1] then
                map, nodes = parent, list
                break
            end
            if not info or info.mapType == CONTINENT then break end
        end
    end
    if not nodes then
        cachedZone, cachedMap, cachedNodes = zone, nil, {}
        return nil, cachedNodes
    end
    local ready = {}
    for _, node in ipairs(nodes) do
        if not NO_DISCOVERY[node.nodeID] then
            local world, blocked, continent = WorldOf(map, node.position)
            if blocked then return nil, nil, true end
            ready[#ready + 1] = { node = node, world = world, continent = continent, inZone = InZone(zone, world, continent) }
        end
    end
    cachedZone, cachedMap, cachedNodes = zone, map, ready
    return map, ready
end

local function Candidate(entry, map, zone, zoneName, player, continent, subzone, mine, seen, zoneWide)
    local node = entry.node
    local kind = Kind(node, mine, seen)
    if not kind then return nil end
    if continent and entry.continent and entry.continent ~= continent then return nil end
    local dist = player and entry.world and Yards(player, entry.world)
    local place = PlaceName(node.name)
    if CAPITALS[zone] and (map == zone or zoneWide) then
        if not OwnCity(place, zoneName) then return nil end
    elseif zoneWide then
        if not entry.inZone then return nil end
    else
        local named = subzone ~= "" and subzone == place
        if not (named or (dist and dist <= TOWN_RANGE)) then return nil end
    end
    return kind, place, dist or math.huge
end

-- The nearest unlearned point here (zoneWide: anywhere in the zone): its
-- place, whether only an unsure one was found, its node and distance.
local function Nearest(zoneWide)
    if inCombat or UnitOnTaxi("player") then return nil end
    local here = C_Map.GetBestMapForUnit("player")
    local zone = Up(SameMap(here), ZONE)
    if not zone then return nil end
    local player, secret, continent = WorldOf(here, here and C_Map.GetPlayerMapPosition(here, "player"))
    if secret then return nil end
    local info = C_Map.GetMapInfo(zone)
    local subzone, mine = Subzone(), Mine()
    local seen = Seen(mine, zone)
    local map, entries, blocked = NodesFor(zone)
    if blocked or not map then return nil end
    local bestName, bestDist, bestNode, ask, askDist, askNode
    for _, entry in ipairs(entries) do
        local kind, place, rank =
            Candidate(entry, map, zone, info and info.name or "", player, continent, subzone, mine, seen, zoneWide)
        if kind == LEARN and (not bestName or rank < bestDist) then
            bestName, bestDist, bestNode = place, rank, entry.node
        elseif kind == ASK and (not ask or rank < askDist) then
            ask, askDist, askNode = true, rank, entry.node
        end
    end
    if bestName then return bestName, nil, bestNode, bestDist end
    return nil, ask, askNode, askDist
end

-------------------------------------------------------------------------------
--  The card
-------------------------------------------------------------------------------

local function Build()
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

local function Restyle()
    local Kit = CUI.Kit
    local size = Get("textSize")
    Kit.Font(frame.text, size, "essentials")
    frame.text:SetTextColor(Kit.Accent())
    frame:SetHeight(size + 2 * PAD)
end

local function Show(place)
    if place then
        frame.text:SetText(CUI.Lf("Learn the %1$s flight point", (place:gsub("^The ", ""))))
    else
        frame.text:SetText(CUI.L("Open a flight master's map to save the points you know"))
    end
    frame:SetWidth(math.max(120, frame.text:GetStringWidth() + 2 * PAD + 8))
    frame:Show()
end

local function CancelEntry()
    if entryTimer then entryTimer:Cancel() end
    entryTimer, entryNode, entryPlace = nil, nil, nil
end

local Update
local function EntryExpired()
    entryTimer, entryNode, entryPlace = nil, nil, nil
    Update()
end

Update = function()
    if not frame then return end
    if CUI._unlockActive then
        Show("Ratchet")
        return
    end
    local zone = Up(C_Map.GetBestMapForUnit("player"), ZONE)
    if zone ~= entryZone then
        CancelEntry()
        entryZone, entryNotified = zone, false
    end
    if zone and not entryNotified then
        local place, ask, node = Nearest(true)
        if place or ask then
            entryNotified, entryNode, entryPlace = true, node, place
            entryTimer = C_Timer.NewTimer(ZONE_HOLD, EntryExpired)
        end
    end
    local place, ask = Nearest()
    if place or ask then
        Show(place)
    elseif entryTimer and not inCombat and not UnitOnTaxi("player") and Kind(entryNode, Mine(), false) then
        Show(entryPlace)
    else
        frame:Hide()
    end
end

-- Talking to a flight master (its taxi line) marks the point beside you.
local function TaxiGossip()
    if taxiIcon == nil then
        local ident = GetFileIDFromPath and GetFileIDFromPath(TAXI_ICON)
        taxiIcon = (ident and ident ~= 0) and ident or false
    end
    if not taxiIcon then return false end
    for _, option in ipairs(C_GossipInfo.GetOptions() or {}) do
        if option.icon == taxiIcon then return true end
    end
    return false
end

local function Spoke()
    if not TaxiGossip() then return end
    local _, _, node, yards = Nearest()
    if not (node and node.nodeID) or (yards ~= math.huge and yards > MASTER_REACH) then return end
    local mine = Mine(true)
    if mine then mine[node.nodeID] = true end
end

events:SetScript("OnEvent", function(_, evt)
    if REFRESH[evt] then ForgetNodes() end
    if evt == "PLAYER_REGEN_DISABLED" then
        inCombat = true
    elseif evt == "PLAYER_REGEN_ENABLED" then
        inCombat = false
    elseif evt == "TAXIMAP_OPENED" then
        Learn()
    elseif evt == "GOSSIP_SHOW" then
        Spoke()
    end
    Update()
end)

local function Apply()
    events:UnregisterAllEvents()
    ForgetNodes()
    if not Enabled() then
        CancelEntry()
        entryZone, entryNotified = nil, nil
        if frame then frame:Hide() end
        return
    end
    Build()
    Restyle()
    if not CUI._unlockActive then F.Place(frame) end
    inCombat = UnitAffectingCombat("player")
    for _, evt in ipairs(EVENTS) do
        events:RegisterEvent(evt)
    end
    Update()
end

if CUI.RegisterUnlockModeListener then
    CUI:RegisterUnlockModeListener("CUI_FlightPoints", function()
        if frame and Enabled() then Update() end
    end)
end

CUI._FlightPoints = { Get = Get, Cfg = F.Cfg, Apply = Apply }

F.Start(Apply, {
    key = "CUI_FlightPoints",
    label = "Flight Point Reminder",
    order = 761,
    frame = function(build)
        if build then
            Build()
            Restyle()
        end
        return frame
    end,
    size = function() return 300, Get("textSize") + 2 * PAD end,
    noAnchorTarget = true,
    noSizeMatchTarget = true,
})
