if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUIQoL_Waypoint.lua - /way [#mapID | zone] x y [description] [; ...]
--
--  Prints one link per destination; clicking a link places the game's own
--  map pin. Arriving at a listed destination is announced (with the next
--  one), and with the options cog's setting so is arriving at a pin placed
--  by hand. /cuiway is always there; /way only if no other addon has it.
--
--  Taint: nothing here calls a C_Map waypoint setter or a C_SuperTrack
--  setter. USER_WAYPOINT_UPDATED runs Blizzard's pin code inside whoever set
--  the pin, and tracking set from addon code would leave the game's tracking
--  written by an addon. The pin is placed by the game's world map link, on
--  the player's own click.
-------------------------------------------------------------------------------
-- Off by default, and only read at load: while off, nothing below runs.
if not (CludesUIDB and CludesUIDB.waypointCmd and CludesUIDB.waypointCmd.enabled == true) then
    return
end

local mod = select(2, ...)
local CUI = CludesUI
local C = CUI.COLOR_CODES
local L, Lf = CludesUI.L, CludesUI.Lf
local floor, abs, min = math.floor, math.abs, math.min

local function Say(text)
    CUI.Print(C.BRAND .. "CludesUI:|r " .. text)
end
local function Note(text)
    Say(C.DIM .. text .. "|r")
end

-- The hand-placed pin setting, read each time (the options cog writes it).
local function HandPins()
    local s = CludesUIDB.waypointCmd
    return s ~= nil and s.manualArrival == true
end

local function MapName(mapID)
    local info = C_Map.GetMapInfo(mapID)
    return info and info.name or ("#" .. mapID)
end

local function Position(x, y)
    return C.DIM .. ("%.1f, %.1f"):format(x, y) .. "|r"
end

-------------------------------------------------------------------------------
--  Zones by name: every zone-like map under the top of the map tree, read
--  in one call on the first /way by name and kept. Names compare folded
--  (case and accents).
-------------------------------------------------------------------------------
local ZONE_KINDS = {
    [Enum.UIMapType.Continent] = true,
    [Enum.UIMapType.Zone] = true,
    [Enum.UIMapType.Dungeon] = true,
    [Enum.UIMapType.Micro] = true,
}
local zoneIds, zoneNames -- side by side: map ID, folded name

local function Fold(text)
    return CaseAccentInsensitiveParse(text):lower()
end

local function ReadZones()
    local top = C_Map.GetFallbackWorldMapID()
    local info = C_Map.GetMapInfo(top)
    while info do
        top = info.mapID
        info = C_Map.GetMapInfo(info.parentMapID)
    end
    zoneIds, zoneNames = {}, {}
    for _, map in ipairs(C_Map.GetMapChildrenInfo(top, nil, true) or {}) do
        if ZONE_KINDS[map.mapType] then
            zoneIds[#zoneIds + 1] = map.mapID
            zoneNames[#zoneIds] = Fold(map.name)
        end
    end
end

-- The maps a typed name means: those of exactly that name, else every one
-- whose name contains it. Keeps maps that take a pin, one per name and
-- parent (a city's floors share one), and none named like its parent (a
-- phase of it). Returns their IDs (nil: no map of that name), their
-- distinct names, and the first match's name.
local function ZonesNamed(query)
    if not zoneIds then
        ReadZones()
    end
    local wanted = Fold(query)
    local exact, partial = {}, {}
    for i, name in ipairs(zoneNames) do
        if name == wanted then
            exact[#exact + 1] = i
        elseif name:find(wanted, 1, true) then
            partial[#partial + 1] = i
        end
    end
    local found = #exact > 0 and exact or partial
    if #found == 0 then
        return nil
    end
    table.sort(found, function(a, b)
        return zoneIds[a] < zoneIds[b]
    end)
    local ids, names, seenSlot, seenName = {}, {}, {}, {}
    for _, i in ipairs(found) do
        local id, name = zoneIds[i], zoneNames[i]
        local info = C_Map.GetMapInfo(id)
        local parent = C_Map.GetMapInfo(info.parentMapID)
        local slot = name .. ":" .. info.parentMapID
        local phaseOfParent = parent and Fold(parent.name) == name
        if not seenSlot[slot] and C_Map.CanSetUserWaypointOnMap(id) and not phaseOfParent then
            seenSlot[slot] = true
            ids[#ids + 1] = id
            if not seenName[name] then
                seenName[name] = true
                names[#names + 1] = info.name
            end
        end
    end
    return ids, names, MapName(zoneIds[found[1]])
end

-------------------------------------------------------------------------------
--  Where a destination is
-------------------------------------------------------------------------------
local HIGHEST_MAP_ID = 999999 -- a typed ID stays inside the map API's integer range

local function IfPinnable(mapID)
    if C_Map.CanSetUserWaypointOnMap(mapID) then
        return { mapID }
    end
    CUI.PrintError(Lf("Map pins cannot be placed on %1$s.", MapName(mapID)))
end

-- A destination's map IDs (several when same-named maps all fit), or nil
-- after saying why not.
local function MapsFor(spec)
    if not spec.zone then
        local mapID = C_Map.GetBestMapForUnit("player")
        if mapID then
            return IfPinnable(mapID)
        end
        -- WoW Forever gives no player map inside instances.
        if IsInInstance() then
            CUI.PrintError(L("Map pins cannot be placed inside instances."))
        else
            CUI.PrintError(L("Cannot determine your current zone."))
        end
        return
    end
    local typedId = spec.zone:match("^#?(%d+)$")
    if typedId then
        local mapID = tonumber(typedId)
        if mapID <= HIGHEST_MAP_ID and C_Map.GetMapInfo(mapID) then
            return IfPinnable(mapID)
        end
        CUI.PrintError(Lf("Unknown map ID: %1$s", typedId))
        return
    end
    local ids, names, first = ZonesNamed(spec.zone)
    if not ids then
        CUI.PrintError(Lf("Unknown zone: %1$s", spec.zone))
    elseif #ids == 0 then
        CUI.PrintError(Lf("Map pins cannot be placed on %1$s.", first))
    elseif #names > 1 then
        table.sort(names, function(a, b)
            return strcmputf8i(a, b) < 0
        end)
        local shown = table.concat(names, ", ", 1, min(#names, 8)) .. (#names > 8 and ", ..." or "")
        Say(Lf("Several zones match %1$s:", spec.zone) .. " " .. shown)
    else
        return ids
    end
end

-------------------------------------------------------------------------------
--  Links
-------------------------------------------------------------------------------
-- As C_Map.GetUserWaypointHyperlink builds it: x and y (0-100) travel as
-- 0-10000, in the yellow every world map link has.
local function PinLink(mapID, x, y)
    return ("|cffffff00|Hworldmap:%d:%d:%d|h[%s]|h|r"):format(
        mapID,
        floor(x * 100 + 0.5),
        floor(y * 100 + 0.5),
        MAP_PIN_HYPERLINK
    )
end

-- number: the destination's place in the list, when there are several.
local function DestinationLine(dest, number)
    local line = PinLink(dest.mapID, dest.x, dest.y)
        .. " "
        .. C.WHITE
        .. dest.label
        .. "|r "
        .. Position(dest.x, dest.y)
    if dest.desc then
        line = line .. "  " .. dest.desc
    end
    if number then
        return C.BRAND .. number .. ".|r " .. line
    end
    return line
end

-------------------------------------------------------------------------------
--  Arriving. NAVIGATION_DESTINATION_REACHED (listened to only while a list
--  waits or hand-placed pins are on) fires for whatever is tracked (a quest,
--  a rare, a portal), so only the player's own distance to the pin counts.
--  A pin the game is not navigating to never fires it, so stopping near the
--  pin counts too (PLAYER_STOPPED_MOVING). A line due in combat waits for
--  the end of combat: an addon line printed in combat taints chat history.
-------------------------------------------------------------------------------
local NEAR = 30 -- yards
local listener = CreateFrame("Frame") -- made at load so its handler is billed to this addon
local waiting -- the last /way's destinations, until all are reached
local lastPin -- the pin last announced (each is announced once)
local held = {} -- lines waiting for the end of combat
local toldClick, toldRemove

local function Listen()
    if waiting or HandPins() then
        listener:RegisterEvent("NAVIGATION_DESTINATION_REACHED")
        listener:RegisterEvent("PLAYER_STOPPED_MOVING")
    else
        listener:UnregisterEvent("NAVIGATION_DESTINATION_REACHED")
        listener:UnregisterEvent("PLAYER_STOPPED_MOVING")
    end
end
mod.WaypointArrivalSync = Listen -- the options cog calls it after a change

local function SayHeld()
    for _, line in ipairs(held) do
        Say(line)
    end
    wipe(held)
end

local function Announce(line)
    held[#held + 1] = line
    if InCombatLockdown() then
        mod.CombatQueue.Defer("waypointArrival", SayHeld)
    else
        SayHeld()
    end
end

-- The listed destination at this pin (a link rounds to 1/10000), or nil.
local function ListedAt(mapID, x, y)
    for i, dest in ipairs(waiting or {}) do
        if dest.mapID == mapID and abs(dest.x / 100 - x) < 2e-4 and abs(dest.y / 100 - y) < 2e-4 then
            return i
        end
    end
end

local function OnNear()
    if not C_Map.HasUserWaypoint() then
        return
    end
    local pin = C_Map.GetUserWaypoint()
    local mapID, x, y = pin.uiMapID, pin.position.x, pin.position.y
    -- Nil while the player is off the pin's map or in an instance.
    local me = C_Map.GetPlayerMapPosition(mapID, "player")
    if not me then
        return
    end
    local width, height = C_Map.GetMapWorldSize(mapID)
    local dx, dy = (me.x - x) * width, (me.y - y) * height
    if dx * dx + dy * dy > NEAR * NEAR then
        return
    end
    local key = mapID .. ":" .. x .. ":" .. y
    if key == lastPin then
        return
    end
    local i = ListedAt(mapID, x, y)
    -- A hand-placed pin counts only with the setting on.
    if not i and not HandPins() then
        return
    end
    lastPin = key

    if not i then
        Announce(
            L("You have arrived:") .. " " .. C.WHITE .. MapName(mapID) .. "|r " .. Position(x * 100, y * 100)
        )
    else
        local dest = waiting[i]
        local number = #waiting > 1 and (i .. ". ") or ""
        Announce(L("You have arrived:") .. " " .. C.WHITE .. number .. (dest.desc or dest.label) .. "|r")
        -- The same-named maps offered for this destination are reached too.
        for _, other in ipairs(waiting) do
            if other.part == dest.part then
                other.reached = true
            end
        end
        -- The next one still to reach, after this one in list order.
        for step = 1, #waiting - 1 do
            local j = (i + step - 1) % #waiting + 1
            if not waiting[j].reached then
                Announce(L("Next:") .. " " .. DestinationLine(waiting[j], j))
                return
            end
        end
        waiting = nil
        Listen()
    end
    -- No game link removes a pin: say how, once.
    if not toldRemove then
        toldRemove = true
        Announce(C.DIM .. L("To remove the pin, ctrl-click it on the world map.") .. "|r")
    end
end
listener:SetScript("OnEvent", OnNear)

local function List(dests)
    waiting, lastPin = dests, nil
    for i, dest in ipairs(dests) do
        Say(DestinationLine(dest, #dests > 1 and i))
    end
    if not toldClick then
        toldClick = true
        Note(L("Click a link to place the pin, then click the pin on the map to track it."))
    end
    Listen()
end

-------------------------------------------------------------------------------
--  Reading the command: [#mapID | mapID | zone] x y [description], x and y
--  0-100. A pair can be "45.3 67.8", "45,3 67,8", "45.3, 67.8" or
--  "45.3,67.8"; the first pair splits the zone from the description.
-------------------------------------------------------------------------------
local ONE = "^(%d+[%.,]?%d*),?$" -- one coordinate (a trailing comma separates)
local JOINED = "^(%d+%.?%d*),(%d+%.?%d*)$" -- both in one word

local function Coordinate(text)
    local n = text and tonumber((text:gsub(",", ".")))
    if n and n >= 0 and n <= 100 then
        return n
    end
end

-- One destination as { x, y, zone (nil = here), desc }, or nil.
local function Read(part)
    local words = {}
    for word in part:gmatch("%S+") do
        words[#words + 1] = word
    end
    for i = 1, #words do
        local x = Coordinate(words[i]:match(ONE))
        local y = Coordinate(words[i + 1] and words[i + 1]:match(ONE))
        local width = 2
        if not (x and y) then
            local a, b = words[i]:match(JOINED)
            x, y, width = Coordinate(a), Coordinate(b), 1
        end
        if x and y then
            return {
                x = x,
                y = y,
                zone = i > 1 and table.concat(words, " ", 1, i - 1) or nil,
                desc = i + width <= #words and table.concat(words, " ", i + width) or nil,
            }
        end
    end
end

local command = "/cuiway" -- "/way" once that is ours

-- Several destinations in one line: split by ";", or pasted one after
-- another ("/way A /way B").
local function OnWay(text)
    text = strtrim(text or "")
    local word = text:lower()
    if word == "clear" or word == "reset" or word == "remove" then
        -- Stops waiting for the list; the pin itself is the player's to remove.
        waiting = nil
        Listen()
        Note(L("To remove the pin, ctrl-click it on the world map."))
        return
    end
    text = text:gsub("/[Ee][Uu][Ii][Ww][Aa][Yy]%f[%s%z]", ";"):gsub("/[Ww][Aa][Yy]%f[%s%z]", ";")
    local specs = {}
    for part in text:gmatch("[^;]+") do
        specs[#specs + 1] = Read(part)
    end
    -- How to use it only when nothing could be read: a destination that was
    -- read and then failed has said why.
    if #specs == 0 then
        Say(L("Usage:") .. " " .. command .. " [#mapID | zone] x y [description] [; ...]")
        return
    end
    local dests = {}
    for number, spec in ipairs(specs) do
        local ids = MapsFor(spec)
        for _, id in ipairs(ids or {}) do
            local label = MapName(id)
            if #ids > 1 then
                -- Same-named maps are told apart by their parent.
                local parent = C_Map.GetMapInfo(C_Map.GetMapInfo(id).parentMapID)
                if parent then
                    label = label .. " (" .. parent.name .. ")"
                end
            end
            dests[#dests + 1] =
                { mapID = id, x = spec.x, y = spec.y, desc = spec.desc, label = label, part = number }
        end
    end
    if #dests > 0 then
        List(dests)
    end
end

-------------------------------------------------------------------------------
--  The commands, a frame after the loading screen, so a /way another addon
--  registers at load or login is seen (already taken in hash_SlashCmdList,
--  or still waiting in SlashCmdList).
-------------------------------------------------------------------------------
local function Taken(name)
    if hash_SlashCmdList[name:upper()] then
        return true
    end
    for key in pairs(SlashCmdList) do
        local i = 1
        local alias = _G["SLASH_" .. key .. i]
        while type(alias) == "string" do
            if alias:lower() == name then
                return true
            end
            i = i + 1
            alias = _G["SLASH_" .. key .. i]
        end
    end
    return false
end

C_Timer.After(0, function()
    SLASH_CUIWAY1 = "/cuiway"
    if not Taken("/way") then
        SLASH_CUIWAY2 = "/way"
        command = "/way"
    end
    SlashCmdList.CUIWAY = OnWay
end)

Listen()
