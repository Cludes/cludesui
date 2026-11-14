if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUIQoL_Waypoint.lua
--  /way [#mapID | zone] x y [description] [; ...] prints one link per
--  destination; a click on a link places Blizzard's native map pin. Arrival
--  at a listed destination is announced, and with the cog option arrival at
--  a hand-placed pin too. /cuiway is always registered, /way only while no
--  other addon owns it.
--
--  Taint: nothing here calls a C_Map user waypoint setter or a C_SuperTrack
--  setter. USER_WAYPOINT_UPDATED is a synchronous event, so a setter call
--  would run Blizzard's map pin code inside this addon's call, and a
--  super-track set from addon code would leave Blizzard's tracking state
--  written by an addon. The pin is placed by Blizzard's worldmap link
--  handler, on the player's own click.
-------------------------------------------------------------------------------
-- Off by default and reload-gated: while off, nothing below runs.
if not (CludesUIDB and CludesUIDB.waypointCmd and CludesUIDB.waypointCmd.enabled == true) then
    return
end

local mod = select(2, ...)
local CUI = CludesUI
local CC = CUI.COLOR_CODES

local PREFIX = CC.BRAND .. "CludesUI:|r "
local function Say(msg)
    CUI.Print(PREFIX .. msg)
end
local function Hint(msg)
    Say(CC.DIM .. msg .. "|r")
end

-- The hand-placed pin option, read live (the options cog writes it).
local function ManualArrival()
    local conf = CludesUIDB.waypointCmd
    return conf ~= nil and conf.manualArrival == true
end

local function MapLabel(mapID)
    local details = C_Map.GetMapInfo(mapID)
    return details and details.name or ("#" .. mapID)
end

-------------------------------------------------------------------------------
--  Zone names: every map under the top of the map tree, read in one call on
--  the first /way by name and kept for the session. Names compare folded
--  (case and accents).
-------------------------------------------------------------------------------
local ZONE_TYPES = {
    [Enum.UIMapType.Continent] = true,
    [Enum.UIMapType.Zone] = true,
    [Enum.UIMapType.Dungeon] = true,
    [Enum.UIMapType.Micro] = true,
}
local zoneIDs, zoneKeys -- parallel: uiMapID, folded name

local function Fold(s)
    return CaseAccentInsensitiveParse(s):lower()
end

local function BuildZones()
    local root = C_Map.GetFallbackWorldMapID()
    local details = C_Map.GetMapInfo(root)
    while details do
        root = details.mapID
        details = C_Map.GetMapInfo(details.parentMapID)
    end
    zoneIDs, zoneKeys = {}, {}
    for _, m in ipairs(C_Map.GetMapChildrenInfo(root, nil, true) or {}) do
        if ZONE_TYPES[m.mapType] then
            zoneIDs[#zoneIDs + 1] = m.mapID
            zoneKeys[#zoneIDs] = Fold(m.name)
        end
    end
end

-- The maps a typed name means: the maps of that exact name, else every map
-- whose name holds it. Keeps those that take a pin, one per name and parent
-- (a city's floors share one) and none named like its parent (a phase of
-- it). Returns the uiMapIDs (nil: no map has such a name), their distinct
-- names, and the first name matched.
local function FindZones(query)
    if not zoneIDs then
        BuildZones()
    end
    local q = Fold(query)
    local exact, part = {}, {}
    for idx, key in ipairs(zoneKeys) do
        if key == q then
            exact[#exact + 1] = idx
        elseif key:find(q, 1, true) then
            part[#part + 1] = idx
        end
    end
    local hits = #exact > 0 and exact or part
    if #hits == 0 then
        return nil
    end
    table.sort(hits, function(a, b)
        return zoneIDs[a] < zoneIDs[b]
    end)
    local ids, nameList, slots, named = {}, {}, {}, {}
    for _, idx in ipairs(hits) do
        local ident, key = zoneIDs[idx], zoneKeys[idx]
        local details = C_Map.GetMapInfo(ident)
        local hostFrame = C_Map.GetMapInfo(details.parentMapID)
        local slot = key .. ":" .. details.parentMapID
        if
            not slots[slot]
            and C_Map.CanSetUserWaypointOnMap(ident)
            and not (hostFrame and Fold(hostFrame.name) == key)
        then
            slots[slot] = true
            ids[#ids + 1] = ident
            if not named[key] then
                named[key] = true
                nameList[#nameList + 1] = details.name
            end
        end
    end
    return ids, nameList, MapLabel(zoneIDs[hits[1]])
end

-------------------------------------------------------------------------------
--  Resolving a destination
-------------------------------------------------------------------------------
local MAX_MAP_ID = 999999 -- a typed ID stays inside the map API's integer range

local function Pinnable(mapID)
    if C_Map.CanSetUserWaypointOnMap(mapID) then
        return { mapID }
    end
    CUI.PrintError(CludesUI.Lf("Map pins cannot be placed on %1$s.", MapLabel(mapID)))
end

-- spec -> its uiMapIDs (several when same-named maps all qualify), or nil
-- after printing why.
local function Candidates(specInfo)
    if not specInfo.zone then
        local mapID = C_Map.GetBestMapForUnit("player")
        if mapID then
            return Pinnable(mapID)
        end
        -- Inside instances the player has no map on WoW Forever.
        CUI.PrintError(
            IsInInstance() and CludesUI.L("Map pins cannot be placed inside instances.")
                or CludesUI.L("Cannot determine your current zone.")
        )
        return
    end
    local ident = specInfo.zone:match("^#?(%d+)$")
    if ident then
        local mapID = tonumber(ident)
        if mapID <= MAX_MAP_ID and C_Map.GetMapInfo(mapID) then
            return Pinnable(mapID)
        end
        CUI.PrintError(CludesUI.Lf("Unknown map ID: %1$s", ident))
        return
    end
    local ids, nameList, first = FindZones(specInfo.zone)
    if not ids then
        CUI.PrintError(CludesUI.Lf("Unknown zone: %1$s", specInfo.zone))
    elseif #ids == 0 then
        CUI.PrintError(CludesUI.Lf("Map pins cannot be placed on %1$s.", first))
    elseif #nameList > 1 then
        table.sort(nameList, function(a, b)
            return strcmputf8i(a, b) < 0
        end)
        Say(
            CludesUI.Lf("Several zones match %1$s:", specInfo.zone)
                .. " "
                .. table.concat(nameList, ", ", 1, math.min(#nameList, 8))
                .. (#nameList > 8 and ", ..." or "")
        )
    else
        return ids
    end
end

-------------------------------------------------------------------------------
--  Links
-------------------------------------------------------------------------------
-- The link C_Map.GetUserWaypointHyperlink builds: x, y in 0..100 travel as
-- 0..10000, in the colour every worldmap link takes.
local function PinLink(mapID, posX, posY)
    return ("|cffffff00|Hworldmap:%d:%d:%d|h[%s]|h|r"):format(
        mapID,
        math.floor(posX * 100 + 0.5),
        math.floor(posY * 100 + 0.5),
        MAP_PIN_HYPERLINK
    )
end

local function Coords(posX, posY)
    return CC.DIM .. ("%.1f, %.1f"):format(posX, posY) .. "|r"
end

-- n: the destination's number, when the list holds several.
local function LinkLine(dest, num)
    local line = PinLink(dest.mapID, dest.x, dest.y)
        .. " "
        .. CC.WHITE
        .. dest.label
        .. "|r "
        .. Coords(dest.x, dest.y)
    if dest.desc then
        line = line .. "  " .. dest.desc
    end
    return num and (CC.BRAND .. num .. ".|r " .. line) or line
end

-------------------------------------------------------------------------------
--  Arrival: NAVIGATION_DESTINATION_REACHED, registered only while a /way list
--  waits or the hand-placed pin option is on. It fires for whatever is
--  super-tracked (a quest, a rare, a party member, a route's portal), so only
--  the player's own distance to the pin counts. A pin the client is not
--  navigating to (not tracked, or in-game navigation turned off) never fires
--  it, so the player stopping near the pin counts too (PLAYER_STOPPED_MOVING,
--  same window). A message that lands in combat waits for the end of combat:
--  an addon line printed in combat taints chat history.
-------------------------------------------------------------------------------
local ARRIVE_YARDS = 30
local ev = CreateFrame("Frame") -- made in the main chunk so its handler bills to this addon
local listed -- destinations of the last /way, until all are reached
local announced -- the pin last announced, so each one is announced once
local held = {} -- arrival lines waiting for the end of combat
local hintedClick, hintedRemove

local function SyncArrival()
    if listed or ManualArrival() then
        ev:RegisterEvent("NAVIGATION_DESTINATION_REACHED")
        ev:RegisterEvent("PLAYER_STOPPED_MOVING")
    else
        ev:UnregisterEvent("NAVIGATION_DESTINATION_REACHED")
        ev:UnregisterEvent("PLAYER_STOPPED_MOVING")
    end
end
mod.WaypointArrivalSync = SyncArrival -- the options cog calls it after a change

local function FlushHeld()
    for idx = 1, #held do
        Say(held[idx])
    end
    wipe(held)
end

local function Announce(msg)
    held[#held + 1] = msg
    if InCombatLockdown() then
        mod.CombatQueue.Defer("waypointArrival", FlushHeld)
    else
        FlushHeld()
    end
end

local function OnArrival()
    if not C_Map.HasUserWaypoint() then
        return
    end
    local pin = C_Map.GetUserWaypoint()
    local mapID, px, py = pin.uiMapID, pin.position.x, pin.position.y
    -- Nil while the player is off the pin's map or inside an instance.
    local place = C_Map.GetPlayerMapPosition(mapID, "player")
    if not place then
        return
    end
    local wid, hgt = C_Map.GetMapWorldSize(mapID)
    local dx, dy = (place.x - px) * wid, (place.y - py) * hgt
    if dx * dx + dy * dy > ARRIVE_YARDS * ARRIVE_YARDS then
        return
    end
    local key = mapID .. ":" .. px .. ":" .. py
    if key == announced then
        return
    end

    -- A listed destination: its link rounded the coordinates to 1/10000.
    local idx
    if listed then
        for num, dest in ipairs(listed) do
            if
                dest.mapID == mapID
                and math.abs(dest.x / 100 - px) < 2e-4
                and math.abs(dest.y / 100 - py) < 2e-4
            then
                idx = num
                break
            end
        end
    end
    -- A pin the player placed by hand: only with the cog option.
    if not idx and not ManualArrival() then
        return
    end
    announced = key

    if not idx then
        Announce(
            CludesUI.L("You have arrived:")
                .. " "
                .. CC.WHITE
                .. MapLabel(mapID)
                .. "|r "
                .. Coords(px * 100, py * 100)
        )
    else
        local dest = listed[idx]
        Announce(
            CludesUI.L("You have arrived:")
                .. " "
                .. CC.WHITE
                .. (#listed > 1 and (idx .. ". ") or "")
                .. (dest.desc or dest.label)
                .. "|r"
        )
        -- Same-named maps offered for the same destination count as reached too.
        for _, d in ipairs(listed) do
            if d.part == dest.part then
                d.reached = true
            end
        end
        -- The next destination still to reach, after this one in list order.
        for k = 1, #listed - 1 do
            local jdx = (idx + k - 1) % #listed + 1
            if not listed[jdx].reached then
                Announce(CludesUI.L("Next:") .. " " .. LinkLine(listed[jdx], jdx))
                return
            end
        end
        listed = nil
        SyncArrival()
    end
    -- No Blizzard link clears the pin; point at the native gesture, once.
    if not hintedRemove then
        hintedRemove = true
        Announce(CC.DIM .. CludesUI.L("To remove the pin, ctrl-click it on the world map.") .. "|r")
    end
end
ev:SetScript("OnEvent", OnArrival)

local function ShowDestinations(dests)
    listed, announced = dests, nil
    for idx, dest in ipairs(dests) do
        Say(LinkLine(dest, #dests > 1 and idx))
    end
    if not hintedClick then
        hintedClick = true
        Hint(CludesUI.L("Click a link to place the pin, then click the pin on the map to track it."))
    end
    SyncArrival()
end

-------------------------------------------------------------------------------
--  Parsing: [#mapID | mapID | zone] x y [description], x and y in 0..100. A
--  pair reads "45.3 67.8", "45,3 67,8", "45.3, 67.8" or "45.3,67.8"; the
--  first pair splits the zone from the description.
-------------------------------------------------------------------------------
local COORD = "^(%d+[%.,]?%d*),?$" -- one coordinate (a trailing comma separates)
local PAIR = "^(%d+%.?%d*),(%d+%.?%d*)$" -- both in one token, comma-joined

local function Coord(s)
    local num = s and tonumber((s:gsub(",", ".")))
    if num and num >= 0 and num <= 100 then
        return num
    end
end

-- One destination -> { x, y, zone = text or nil (current zone), desc }, or nil.
local function ParseOne(part)
    local t = {}
    for wid in part:gmatch("%S+") do
        t[#t + 1] = wid
    end
    for idx = 1, #t do
        local posX, posY, used = Coord(t[idx]:match(COORD)), Coord(t[idx + 1] and t[idx + 1]:match(COORD)), 2
        if not (posX and posY) then
            local a, b = t[idx]:match(PAIR)
            posX, posY, used = Coord(a), Coord(b), 1
        end
        if posX and posY then
            return {
                x = posX,
                y = posY,
                zone = idx > 1 and table.concat(t, " ", 1, idx - 1) or nil,
                desc = idx + used <= #t and table.concat(t, " ", idx + used) or nil,
            }
        end
    end
end

local slashName = "/cuiway" -- "/way" once registered under it

-- Several destinations in one line: separated by ";" or pasted back to back
-- ("/way A /way B").
local function HandleWay(msg)
    msg = strtrim(msg or "")
    local word = msg:lower()
    if word == "clear" or word == "reset" or word == "remove" then
        -- Stops waiting for the list; the pin itself stays the player's to remove.
        listed = nil
        SyncArrival()
        Hint(CludesUI.L("To remove the pin, ctrl-click it on the world map."))
        return
    end
    msg = msg:gsub("/[Ee][Uu][Ii][Ww][Aa][Yy]%f[%s%z]", ";"):gsub("/[Ww][Aa][Yy]%f[%s%z]", ";")
    local specs = {}
    for part in msg:gmatch("[^;]+") do
        specs[#specs + 1] = ParseOne(part)
    end
    -- The usage line only when nothing parsed: a destination that parsed and
    -- then failed has printed its own reason.
    if #specs == 0 then
        Say(CludesUI.L("Usage:") .. " " .. slashName .. " [#mapID | zone] x y [description] [; ...]")
        return
    end
    local dests = {}
    for num, specInfo in ipairs(specs) do
        local ids = Candidates(specInfo)
        if ids then
            for _, ident in ipairs(ids) do
                local labelText = MapLabel(ident)
                if #ids > 1 then
                    -- Same-named maps: told apart by their parent map.
                    local hostFrame = C_Map.GetMapInfo(C_Map.GetMapInfo(ident).parentMapID)
                    if hostFrame then
                        labelText = labelText .. " (" .. hostFrame.name .. ")"
                    end
                end
                dests[#dests + 1] = {
                    mapID = ident,
                    x = specInfo.x,
                    y = specInfo.y,
                    desc = specInfo.desc,
                    label = labelText,
                    part = num,
                }
            end
        end
    end
    if #dests > 0 then
        ShowDestinations(dests)
    end
end

-------------------------------------------------------------------------------
--  Slash commands, one frame after the loading screen, so a /way another
--  addon registers at load or on its login events is seen: one already
--  imported by the chat code sits in hash_SlashCmdList, one still pending in
--  SlashCmdList.
-------------------------------------------------------------------------------
local function SlashTaken(cmd)
    if hash_SlashCmdList[cmd:upper()] then
        return true
    end
    for key in pairs(SlashCmdList) do
        local idx, s = 1, _G["SLASH_" .. key .. "1"]
        while type(s) == "string" do
            if s:lower() == cmd then
                return true
            end
            idx = idx + 1
            s = _G["SLASH_" .. key .. idx]
        end
    end
    return false
end

C_Timer.After(0, function()
    SLASH_CUIWAY1 = "/cuiway"
    if not SlashTaken("/way") then
        SLASH_CUIWAY2 = "/way"
        slashName = "/way"
    end
    SlashCmdList.CUIWAY = HandleWay
end)

SyncArrival()
