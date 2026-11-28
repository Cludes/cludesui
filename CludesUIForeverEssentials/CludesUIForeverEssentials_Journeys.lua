if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
if not (CUI and CUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_Journeys.lua  (WoW Forever only)
--  Journeys: the fastest way to the map pin you place, over walking, the
--  flights you know, your faction's boats and zeppelins, the Deeprun Tram,
--  the Darnassus portal, your Hearthstone and class teleports. A small card
--  lists the steps with their times and an arrow points the way to the next
--  one, with how far it is. The plan is made again from where you stand
--  every few seconds, on landing and after a loading screen; a new route
--  only replaces the one you follow when it is clearly quicker, so near
--  ties do not flip back and forth. Removing the pin ends the journey.
--
--  CludesUI never places the game's waypoint itself (see CludesUIQoL_
--  Waypoint.lua: taint), so the pin is yours to place: on the world map,
--  or with a /way link. Walks are measured on the walking maps
--  (CludesUIForeverEssentials_Walking.lua, the CludesUIJourneysData addon):
--  round hills and water, along piers; the arrow follows the walk's corners.
--  Where the maps cannot say, a walk is the straight line times a detour
--  factor, and the two islands the network reaches by boat (Teldrassil,
--  Feathermoon) are never walked to or from. Plans are made in slices of a
--  frame, so a search over a continent never stalls the game.
--  Flight points are learned at a flight master's map; Hearthstone and
--  teleport landings the first time you use them.
--  Per character: CludesUIDB.journeys.chars["Name-Realm"] = { flights, landings }.
--  Network: CludesUIForeverEssentials_JourneysData.lua.
-------------------------------------------------------------------------------
local _, module = ...

local F = module.Feature("journeys", { enabled = false, hearth = true, teleports = true, minimapRoute = true },
    { point = "TOPRIGHT", relPoint = "TOPRIGHT", x = -260, y = -220 })
local Get, Enabled, Cfg = F.Get, F.Enabled, F.Cfg
local Kit = CUI.Kit
local Pal = Kit.Palette

local C = {
    RUN_SPEED = 7,
    WALK_DETOUR = 1.3,
    FLIGHT_SPEED = 30.4,
    TAXI_OVERHEAD = 10,
    SHIP_SPEED = { Boat = 17, Zeppelin = 20 },
    BOARD = 5,
    LOADING = 15,
    HEARTH_CAST = 10,
    TELEPORT_CAST = 10,
    TRANSFER = 15,
    MIN_WALK = 1,
    SWITCH_GAIN = 30,
    SWITCH_SHARE = 0.1,
    ARRIVED = 15,
    STEP_REACHED = 20,
    REPLAN_MOVED = 5,
    DOT_EVERY = 12,
    MAX_DOTS = 80,
    CORNER_REACH = 8,
    REPLAN_EVERY = 3,
    HEARTHSTONE = 6948,
    HEARTH_SPELL = 8690,
}

local function Secret(v) return v ~= nil and issecretvalue and issecretvalue(v) end

-------------------------------------------------------------------------------
--  Planner: Dijkstra over the start, the goal and the network's places
-------------------------------------------------------------------------------
local Planner = {}
do
    local sqrt, huge = math.sqrt, math.huge
    local FROM, TO = 1, 2
    local CHAIN_STEP = { Tram = "tram", Lift = "lift" }

    local function Serves(side, faction) return side:find(faction, 1, true) ~= nil end

    local function Distance(a, b)
        local dx, dy = a.x - b.x, a.y - b.y
        return sqrt(dx * dx + dy * dy)
    end
    Planner.Distance = Distance

    local function PutPlace(places, place)
        places[#places + 1] = place
        place.index = #places
        return place
    end

    local built = { key = nil }
    local function MakeNetwork(ctx, net)
        local key = ctx.faction .. ":" .. ctx.knownVersion
        if built.key == key then return built end
        local places, masters, piers = { false, false }, {}, {}
        for id, f in pairs(net.flights) do
            if Serves(f[6], ctx.faction) and ctx.known[id] then
                masters[id] = PutPlace(places, { kind = "flight", net = true, id = id, name = f[1], c = f[2], x = f[3], y = f[4], key = "f" .. id })
            end
        end
        for s, ship in ipairs(net.ships) do
            if Serves(ship[2], ctx.faction) then
                piers[s] = {}
                for i = 3, #ship do
                    local d = ship[i]
                    piers[s][i - 2] = PutPlace(places, { kind = "dock", net = true, ship = s, dock = i - 2, name = d[5], shipKind = ship[1],
                        c = d[1], x = d[2], y = d[3], key = "s" .. s .. "." .. (i - 2) })
                end
            end
        end
        for l, chain in ipairs(net.links) do
            if Serves(chain[2], ctx.faction) then
                local a, b = chain[4], chain[5]
                local here = PutPlace(places, { kind = "link", net = true, link = l, name = a[4], linkKind = chain[1], c = a[1], x = a[2], y = a[3], key = "l" .. l .. ".1" })
                local there = PutPlace(places, { kind = "link", net = true, link = l, name = b[4], linkKind = chain[1], c = b[1], x = b[2], y = b[3], key = "l" .. l .. ".2" })
                here.other, there.other = there.index, here.index
            end
        end
        built = { key = key, places = places, masters = masters, piers = piers }
        return built
    end

    local function PlanPlaces(ctx, net)
        local places = {}
        PutPlace(places, { kind = "start", key = "start", c = ctx.from.c, x = ctx.from.x, y = ctx.from.y, reach = ctx.from.reach })
        PutPlace(places, { kind = "goal", key = "goal", c = ctx.to.c, x = ctx.to.x, y = ctx.to.y, name = ctx.to.name, reach = ctx.to.reach })
        local shared = MakeNetwork(ctx, net)
        for i = TO + 1, #shared.places do
            places[i] = shared.places[i]
        end
        for _, jump in ipairs(ctx.jumps or {}) do
            PutPlace(places, { kind = "jump", key = "j" .. (jump.spell or jump.item), mode = jump.mode, name = jump.name, cast = jump.cast,
                spell = jump.spell, item = jump.item, c = jump.c, x = jump.x, y = jump.y, reach = jump.reach })
        end
        return places, shared.masters, shared.piers
    end

    local function FlightWeb(net, masters)
        local web = {}
        for _, hop in ipairs(net.hops) do
            local a, b = hop[1], hop[2]
            if masters[a] and masters[b] then
                web[a] = web[a] or {}
                web[a][#web[a] + 1] = { b, hop[3] / C.FLIGHT_SPEED }
            end
        end
        return web
    end

    local function FlightSearch(web, from)
        local secs, cameFrom, settled = { [from] = 0 }, {}, {}
        while true do
            local winner, winnerSecs = nil, huge
            for id, t in pairs(secs) do
                if not settled[id] and t < winnerSecs then winner, winnerSecs = id, t end
            end
            if not winner then return secs, cameFrom end
            settled[winner] = true
            for _, edge in ipairs(web[winner] or {}) do
                local t = winnerSecs + edge[2]
                if t < (secs[edge[1]] or huge) then secs[edge[1]], cameFrom[edge[1]] = t, winner end
            end
        end
    end

    local flightMemo = { key = nil, from = {}, cameFrom = {} }
    local function FlightTable(ctx, net, masters, from)
        local key = ctx.faction .. ":" .. ctx.knownVersion
        if flightMemo.key ~= key then
            flightMemo.key, flightMemo.from, flightMemo.prev, flightMemo.graph = key, {}, {}, FlightWeb(net, masters)
        end
        local secs = flightMemo.from[from]
        if not secs then
            secs, flightMemo.prev[from] = FlightSearch(flightMemo.graph, from)
            flightMemo.from[from] = secs
        end
        return secs, flightMemo.prev[from]
    end

    local function LoopSeconds(ship)
        local total = 0
        local speed = C.SHIP_SPEED[ship[1]]
        for i = 3, #ship do
            total = total + ship[i][6] + ship[i][7] / speed
        end
        return total
    end

    local function Voyage(ship, from, to)
        local speed = C.SHIP_SPEED[ship[1]]
        local tally = #ship - 2
        local t, i = 0, from
        while i ~= to do
            t = t + ship[i + 2][7] / speed
            i = i % tally + 1
            if i ~= to then t = t + ship[i + 2][6] end
        end
        return t
    end

    local function Improve(search, from, to, cost)
        local t = search.secs[from] + cost
        if t >= search.secs[to] then return false end
        search.secs[to] = t
        search.cameFrom[to] = from
        return true
    end

    -- Islands a boat reaches, boxed round the built's own places there:
    -- Teldrassil (Rut'theran, Darnassus) north of 8000 on Kalimdor, and
    -- Feathermoon within 500 yards of its piers.
    local function Island(spot)
        if spot.c ~= 1 then return nil end
        if spot.x >= 8000 and spot.y >= 0 then return "teldrassil" end
        local dx, dy = spot.x + 4300, spot.y - 3320
        if dx * dx + dy * dy <= 500 * 500 then return "feathermoon" end
    end
    Planner.Island = Island

    local function WalkEdges(ctx, search, places, u)
        local a = places[u]
        local island = Island(a)
        for v = TO, #places do
            local b = places[v]
            if v ~= u and b.c == a.c and b.kind ~= "jump" and not search.settled[v] then
                local yards = ctx.walk and ctx.walk(a, b)
                if yards == nil and Island(b) == island then yards = Distance(a, b) * C.WALK_DETOUR end
                if yards then
                    local seconds = yards / ctx.speed
                    if Improve(search, u, v, seconds) then search.stepTo[v] = { mode = "walk", seconds = seconds } end
                end
            end
        end
    end

    local function FlightEdges(ctx, search, places, u, net)
        local secs = FlightTable(ctx, net, search.masters, places[u].id)
        for id, airSecs in pairs(secs) do
            local v = search.masters[id].index
            if v ~= u and not search.settled[v] then
                local seconds = airSecs + C.TAXI_OVERHEAD + C.TRANSFER
                if Improve(search, u, v, seconds) then search.stepTo[v] = { mode = "fly", seconds = seconds } end
            end
        end
    end

    local function ShipEdges(search, places, u, net)
        local a = places[u]
        local ship = net.ships[a.ship]
        local waitSecs = LoopSeconds(ship) / 2
        for j, b in ipairs(search.piers[a.ship]) do
            if j ~= a.dock and not search.settled[b.index] then
                local onBoard = Voyage(ship, a.dock, j) + C.BOARD + C.TRANSFER
                if b.c ~= a.c then onBoard = onBoard + C.LOADING end
                if Improve(search, u, b.index, waitSecs + onBoard) then
                    search.stepTo[b.index] = { mode = "ship", seconds = waitSecs + onBoard, wait = waitSecs }
                end
            end
        end
    end

    local function ChainEdges(search, places, u, net)
        local a = places[u]
        if search.settled[a.other] then return end
        local seconds = net.links[a.link][3] + C.TRANSFER
        if Improve(search, u, a.other, seconds) then search.stepTo[a.other] = { mode = CHAIN_STEP[a.linkKind] or "portal", seconds = seconds } end
    end

    local function JumpEdges(search, places)
        for v = TO + 1, #places do
            local b = places[v]
            if b.kind == "jump" then
                local seconds = b.cast + C.LOADING
                if Improve(search, FROM, v, seconds) then
                    search.stepTo[v] = { mode = b.mode, seconds = seconds, spell = b.spell, item = b.item }
                end
            end
        end
    end

    local function Unwind(search, places, v)
        local stages = {}
        while search.cameFrom[v] do
            local step = search.stepTo[v]
            local place = places[v]
            step.name, step.kind, step.key, step.c, step.x, step.y = place.name, place.kind, place.key, place.c, place.x, place.y
            step.shipKind = place.shipKind
            if step.mode ~= "walk" or step.seconds >= C.MIN_WALK then table.insert(stages, 1, step) end
            v = search.cameFrom[v]
        end
        return stages
    end

    local function SameRoute(a, b)
        if #a.legs ~= #b.legs then return false end
        for i, step in ipairs(a.legs) do
            if step.key ~= b.legs[i].key or step.mode ~= b.legs[i].mode then return false end
        end
        return true
    end

    -- The route you follow, timed from where you stand: the quickest way to
    -- its next place, then the rest as it was.
    local function Continued(followed, search, places)
        local first = followed.legs[1]
        if not first then return nil end
        for v = TO, #places do
            if places[v].key == first.key and search.secs[v] < huge then
                local stages, seconds = Unwind(search, places, v), search.secs[v]
                for i = 2, #followed.legs do
                    stages[#stages + 1] = followed.legs[i]
                    seconds = seconds + followed.legs[i].seconds
                end
                return { seconds = seconds, legs = stages }
            end
        end
    end

    local function WorthSwitching(winner, carried)
        if SameRoute(winner, carried) then return true end
        return winner.seconds <= carried.seconds - C.SWITCH_GAIN and winner.seconds <= carried.seconds * (1 - C.SWITCH_SHARE)
    end

    function Planner.Plan(ctx)
        local net = module.JOURNEY_NETWORK
        local places, masters, piers = PlanPlaces(ctx, net)
        local search = { secs = {}, cameFrom = {}, stepTo = {}, settled = {}, piers = piers, masters = masters }
        for i = 1, #places do
            search.secs[i] = huge
        end
        search.secs[FROM] = 0
        while true do
            local u, winner = nil, huge
            for i = 1, #places do
                if not search.settled[i] and search.secs[i] < winner then u, winner = i, search.secs[i] end
            end
            if not u or u == TO then break end
            search.settled[u] = true
            local kind = places[u].kind
            WalkEdges(ctx, search, places, u)
            if kind == "start" then JumpEdges(search, places) end
            if kind == "flight" then FlightEdges(ctx, search, places, u, net) end
            if kind == "dock" then ShipEdges(search, places, u, net) end
            if kind == "link" then ChainEdges(search, places, u, net) end
        end
        local winner
        if search.secs[TO] < huge then
            local stages, seconds = Unwind(search, places, TO), 0
            for _, step in ipairs(stages) do
                seconds = seconds + step.seconds
            end
            winner = { seconds = seconds, legs = stages }
        end
        local carried = ctx.keep and Continued(ctx.keep, search, places)
        if carried and not (winner and WorthSwitching(winner, carried)) then return carried end
        return winner
    end
end

-------------------------------------------------------------------------------
--  World: where you are, the pin, flights you know, jumps you can take
-------------------------------------------------------------------------------
local learnedVersion = 0
local teleportBySpell = {}
for _, tp in ipairs(module.JOURNEY_TELEPORTS or {}) do
    teleportBySpell[tp.spell] = tp
end

local function CharKeep()
    local root = Cfg()
    root.chars = root.chars or {}
    local key = (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
    local mine = root.chars[key]
    if not mine then
        mine = { flights = {}, landings = {} }
        root.chars[key] = mine
        learnedVersion = learnedVersion + 1
        -- Seed from the Flight Point Reminder's record of this character.
        local spotted = CludesUIDB and CludesUIDB.flightPointsKnown and CludesUIDB.flightPointsKnown[key]
        for id, known in pairs(spotted or {}) do
            if type(id) == "number" and known == true then mine.flights[id] = true end
        end
    end
    return mine
end

local function Person()
    local x, y, _, c = UnitPosition("player")
    if not x or Secret(x) or Secret(y) or Secret(c) then return nil end
    return { c = c, x = x, y = y }
end

-- The map pin, as a world spot, or nil.
local function Goal()
    if not (C_Map.HasUserWaypoint and C_Map.HasUserWaypoint()) then return nil end
    local point = C_Map.GetUserWaypoint()
    if not (point and point.uiMapID and point.position) then return nil end
    local c, pos = C_Map.GetWorldPosFromMapPos(point.uiMapID, point.position)
    if not (c and pos) or Secret(pos.x) then return nil end
    local info = C_Map.GetMapInfo(point.uiMapID)
    return { c = c, x = pos.x, y = pos.y, name = info and info.name or "your pin", map = point.uiMapID,
        mx = point.position.x, my = point.position.y }
end

local function Ready(start, duration)
    return (duration or 0) <= 1.5 or (start or 0) + duration <= GetTime()
end

local function Jumps(faction)
    local roster = {}
    local landings = CharKeep().landings
    if Get("hearth") and landings.hearth and C_Item.GetItemCount(C.HEARTHSTONE) > 0 then
        local start, duration = C_Item.GetItemCooldown(C.HEARTHSTONE)
        if Ready(start, duration) then
            local home = landings.hearth
            roster[#roster + 1] = { mode = "hearth", name = home.name or "home", cast = C.HEARTH_CAST, item = C.HEARTHSTONE, c = home.c, x = home.x, y = home.y }
        end
    end
    if Get("teleports") then
        for _, tp in ipairs(module.JOURNEY_TELEPORTS or {}) do
            local known = tp.side:find(faction, 1, true) and C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(tp.spell)
            local cd = known and C_Spell.GetSpellCooldown(tp.spell)
            if cd and Ready(cd.startTime, cd.duration) and (not tp.reagent or C_Item.GetItemCount(tp.reagent) > 0) then
                local spot = landings[tp.spell] or tp
                roster[#roster + 1] = { mode = "teleport", name = tp.name, cast = C.TELEPORT_CAST, spell = tp.spell, c = spot.c, x = spot.x, y = spot.y }
            end
        end
    end
    return roster
end

local atFlightMaster = false
local function GatherFlights()
    local taxi = GetTaxiMapID and GetTaxiMapID()
    if not taxi then return false end
    local known = CharKeep().flights
    local altered = false
    for _, node in ipairs(C_TaxiMap.GetAllTaxiNodes(taxi) or {}) do
        local now = node.state ~= Enum.FlightPathState.Unreachable or nil
        if node.nodeID and known[node.nodeID] ~= now then known[node.nodeID], altered = now, true end
    end
    if altered then learnedVersion = learnedVersion + 1 end
    return altered
end

local landing, castFrom
local function GatherLanding()
    local spell, spot = landing, Person()
    if not spell or not spot then return end
    if castFrom and spot.c == castFrom.c and Planner.Distance(spot, castFrom) < 100 then return end
    landing, castFrom = nil, nil
    local landings = CharKeep().landings
    if spell == C.HEARTH_SPELL then
        landings.hearth = { name = GetBindLocation and GetBindLocation() or "home", c = spot.c, x = spot.x, y = spot.y }
    else
        landings[spell] = spot
    end
end

-------------------------------------------------------------------------------
--  Guide: the journey you follow
-------------------------------------------------------------------------------
local Walking = module.Walking
local plan, goal, arrived
local corners, cornerAt -- the first walk's corners { x1, y1, ... }; the one aimed at
local working, driver -- the plan being made, across frames
local StepWork, TravelSpeed
local sinceReplan = 0

local function StepLabel(leg)
    local mode, title = leg.mode, leg.name or "?"
    if mode == "walk" then
        if leg.kind == "flight" then return "Flight master: " .. title end
        if leg.kind == "dock" then return title .. " dock" end
        return title
    end
    if mode == "fly" then return "Fly to " .. title end
    if mode == "ship" then return (leg.shipKind or "Boat") .. " to " .. title end
    if mode == "tram" then return "Deeprun Tram to " .. title end
    if mode == "portal" then return "Portal to " .. title end
    if mode == "lift" then return "Lift to " .. title end
    if mode == "hearth" then return "Hearthstone to " .. title end
    return "Teleport to " .. title
end

local function Duration(seconds)
    seconds = math.floor(seconds + 0.5)
    if seconds < 60 then return seconds .. "s" end
    if seconds < 3600 then return ("%dm %02ds"):format(seconds / 60, seconds % 60) end
    return ("%dh %02dm"):format(seconds / 3600, (seconds % 3600) / 60)
end

-- Reaches of spots that do not move (the pin, jump landings, step ends),
-- kept until the pin moves: each is a search over a continent.
local fixedReaches, fixedTally = {}, 0
local function FixedReach(spot)
    local key = ("%d:%.1f,%.1f"):format(spot.c, spot.x, spot.y)
    local reach = fixedReaches[key]
    if reach == nil then
        reach = Walking.Reach(spot)
        if reach ~= nil then
            if fixedTally >= 16 then
                wipe(fixedReaches)
                fixedTally = 0
            end
            fixedReaches[key], fixedTally = reach, fixedTally + 1
        end
    end
    return reach
end

-- Yards walked between two planner places: a travel place by its key,
-- anything else by its reach. false: no walk; nil: the maps cannot say.
local function WalkYards(a, b)
    local ea = a.net and a.key or a.reach
    local eb = b.net and b.key or b.reach
    if ea == false or eb == false then return false end
    if not ea or not eb then return nil end
    return Walking.Yards(a.c, ea, eb)
end

-- Yards a second for walks: your mount's, once it is known.
function TravelSpeed()
    local mounted = CharKeep().mountSpeed
    return mounted and mounted > C.RUN_SPEED and mounted or C.RUN_SPEED
end

local function Work(from, to, faction, jumps, keep)
    local mapped = Walking.Ready()
    if mapped then
        from.reach = Walking.Reach(from)
        to.reach = FixedReach(to)
        for _, jump in ipairs(jumps) do
            jump.reach = FixedReach(jump)
        end
    end
    local result = Planner.Plan({
        from = from,
        to = to,
        faction = faction,
        known = CharKeep().flights,
        knownVersion = learnedVersion,
        speed = TravelSpeed(),
        jumps = jumps,
        keep = keep,
        walk = mapped and WalkYards or nil,
    })
    local first = result and result.legs[1]
    if mapped and first and first.mode == "walk" and from.reach then
        local there = first.kind == "goal" and to.reach or FixedReach({ c = first.c, x = first.x, y = first.y })
        result.corners = there and Walking.Corners(from.reach, there) or nil
    end
    return result
end

local Render
local function Planned(ok, result)
    working = nil
    if driver then driver:SetScript("OnUpdate", nil) end
    if not ok then
        geterrorhandler()(result)
        return
    end
    plan = result
    corners, cornerAt = plan and plan.corners, 3
    if Render then Render() end
end

function StepWork()
    if not working then
        driver:SetScript("OnUpdate", nil)
        return
    end
    Walking.StartSlice()
    local ok, result = coroutine.resume(working)
    if coroutine.status(working) == "dead" then Planned(ok, result) end
end

local function Replan()
    sinceReplan = 0
    local was = goal
    goal = Goal()
    -- A pin moved somewhere else is a new journey: the old route is not kept.
    if goal and was and (goal.c ~= was.c or Planner.Distance(goal, was) > 1) then
        plan, corners = nil, nil
        wipe(fixedReaches)
        fixedTally = 0
    end
    if not goal then
        plan, arrived = nil, false
        return
    end
    if UnitOnTaxi and UnitOnTaxi("player") then return end
    local from = Person()
    if not from then return end
    if from.c == goal.c and Planner.Distance(from, goal) <= C.ARRIVED then
        plan, arrived = nil, true
        return
    end
    arrived = false
    if working then return end
    local faction = UnitFactionGroup("player") == "Horde" and "H" or "A"
    local to = { c = goal.c, x = goal.x, y = goal.y, name = goal.name }
    working = coroutine.create(Work)
    driver = driver or CreateFrame("Frame")
    Walking.StartSlice()
    local ok, result = coroutine.resume(working, from, to, faction, Jumps(faction), plan)
    if coroutine.status(working) == "dead" then
        Planned(ok, result)
    else
        driver:SetScript("OnUpdate", StepWork)
    end
end

-------------------------------------------------------------------------------
--  The Journey card
-------------------------------------------------------------------------------
local TILE_W, ROW_H, ARROW_LINE = 290, 17, 52
local TOP_LINES = 7
local tile, arrow, nextLabel, distLabel, lines, totalLabel
local ARROW = "Interface\\AddOns\\CludesUI\\media\\icons\\cui-arrow-down3.png"

local function TileHeight(n) return Kit.HEADER_H + ARROW_LINE + n * ROW_H + 30 end

local function MakeTile()
    if tile then return tile end
    tile = Kit.Window("CludesUIJourney", TILE_W, TileHeight(3), CUI.L("Journey"), { key = "essentials", special = false, strata = "MEDIUM" })
    tile:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint(1)
        Cfg().pos = { point = point, relPoint = relPoint, x = x, y = y }
    end)
    F.Place(tile)
    arrow = tile:CreateTexture(nil, "ARTWORK")
    arrow:SetTexture(ARROW)
    arrow:SetSize(36, 36)
    arrow:SetPoint("TOPLEFT", 12, -(Kit.HEADER_H + 8))
    local r, g, b = Kit.Accent()
    arrow:SetVertexColor(r, g, b)
    nextLabel = tile:CreateFontString(nil, "OVERLAY")
    Kit.Font(nextLabel, Kit.TEXT_SIZE, "essentials")
    nextLabel:SetPoint("TOPLEFT", 58, -(Kit.HEADER_H + 10))
    nextLabel:SetPoint("RIGHT", tile, "RIGHT", -10, 0)
    nextLabel:SetJustifyH("LEFT")
    nextLabel:SetWordWrap(false)
    distLabel = tile:CreateFontString(nil, "OVERLAY")
    Kit.Font(distLabel, Kit.SMALL_SIZE, "essentials")
    distLabel:SetPoint("TOPLEFT", nextLabel, "BOTTOMLEFT", 0, -4)
    distLabel:SetTextColor(Pal.muted[1], Pal.muted[2], Pal.muted[3])
    lines = {}
    for i = 1, TOP_LINES do
        local left = tile:CreateFontString(nil, "OVERLAY")
        Kit.Font(left, Kit.SMALL_SIZE, "essentials")
        left:SetPoint("TOPLEFT", 12, -(Kit.HEADER_H + ARROW_LINE + (i - 1) * ROW_H))
        left:SetPoint("RIGHT", tile, "RIGHT", -70, 0)
        left:SetJustifyH("LEFT")
        left:SetWordWrap(false)
        local right = tile:CreateFontString(nil, "OVERLAY")
        Kit.Font(right, Kit.SMALL_SIZE, "essentials")
        right:SetPoint("TOPRIGHT", tile, "TOPRIGHT", -10, -(Kit.HEADER_H + ARROW_LINE + (i - 1) * ROW_H))
        right:SetJustifyH("RIGHT")
        right:SetTextColor(Pal.muted[1], Pal.muted[2], Pal.muted[3])
        lines[i] = { left = left, right = right }
    end
    totalLabel = tile:CreateFontString(nil, "OVERLAY")
    Kit.Font(totalLabel, Kit.SMALL_SIZE, "essentials")
    totalLabel:SetPoint("BOTTOMLEFT", 12, 10)
    totalLabel:SetPoint("RIGHT", tile, "RIGHT", -10, 0)
    totalLabel:SetJustifyH("LEFT")
    totalLabel:SetTextColor(Pal.muted[1], Pal.muted[2], Pal.muted[3])
    tile:Hide()
    return tile
end

-- The arrow turns toward the next step's place (x north, y west; the game's
-- facing is radians from north, counter-clockwise). The art points down.
-------------------------------------------------------------------------------
--  The walk on the minimap: dots along its corners, every DOT_EVERY yards
--  from where you stand, left out past the minimap's edge, turned with the
--  minimap when it rotates.
-------------------------------------------------------------------------------
local routeLayer, dots = nil, {}

local function ConcealDots(from)
    for i = from, #dots do
        dots[i]:Hide()
    end
end

local function RenderRoute(here)
    if not (Get("minimapRoute") and corners and here and Minimap and Minimap:IsVisible() and C_Minimap and C_Minimap.GetViewRadius) then
        ConcealDots(1)
        return
    end
    if not routeLayer then
        routeLayer = CreateFrame("Frame", nil, Minimap)
        routeLayer:SetAllPoints(Minimap)
        routeLayer:SetFrameLevel(Minimap:GetFrameLevel() + 5)
    end
    local yards = C_Minimap.GetViewRadius()
    local radius = Minimap:GetWidth() / 2
    if not (yards and yards > 0 and radius > 0) then return ConcealDots(1) end
    local scale = radius / yards
    local hand = 0
    if GetCVar("rotateMinimap") == "1" then
        local facing = GetPlayerFacing and GetPlayerFacing()
        if facing and not Secret(facing) then hand = facing end
    end
    local cosT, sinT = math.cos(hand), math.sin(hand)
    local r, g, b = Kit.Accent()
    local shown = 0
    -- Walk the corners from where you stand, dropping a dot every DOT_EVERY yards.
    local fromX, fromY = here.x, here.y
    local carry = C.DOT_EVERY
    for i = cornerAt or 3, #corners - 1, 2 do
        local toX, toY = corners[i], corners[i + 1]
        local legX, legY = toX - fromX, toY - fromY
        local length = math.sqrt(legX * legX + legY * legY)
        local along = carry
        while along <= length and shown < C.MAX_DOTS do
            local px, py = fromX + legX * along / length, fromY + legY * along / length
            -- North is up, west is left; a rotating minimap turns with you.
            local up, right = (px - here.x) * scale, -(py - here.y) * scale
            up, right = up * cosT - right * sinT, up * sinT + right * cosT
            if up * up + right * right <= (radius - 3) * (radius - 3) then
                shown = shown + 1
                local dot = dots[shown]
                if not dot then
                    dot = routeLayer:CreateTexture(nil, "OVERLAY")
                    dot:SetTexture("Interface\\AddOns\\CludesUI\\media\\white-square.png")
                    dot:SetSize(4, 4)
                    dots[shown] = dot
                end
                dot:SetVertexColor(r, g, b, 0.9)
                dot:ClearAllPoints()
                dot:SetPoint("CENTER", routeLayer, "CENTER", right, up)
                dot:Show()
            end
            along = along + C.DOT_EVERY
        end
        carry = along - length
        fromX, fromY = toX, toY
        if shown >= C.MAX_DOTS then break end
    end
    ConcealDots(shown + 1)
end

local function PointArrow()
    if not (tile and tile:IsShown()) then
        ConcealDots(1)
        return
    end
    RenderRoute(not arrived and Person() or nil)
    local leg = plan and plan.legs[1]
    local here = Person()
    local aim = leg and (leg.mode == "walk" and leg or nil)
    if arrived or not (aim and here and here.c == aim.c) then
        arrow:SetShown(false)
        distLabel:SetText(arrived and "" or (UnitOnTaxi and UnitOnTaxi("player") and "In flight" or ""))
        return
    end
    local facing = GetPlayerFacing and GetPlayerFacing()
    local aimX, aimY, later = aim.x, aim.y, 0
    if corners then
        -- Aim at the next corner not yet reached; the yards are what is left of the walk.
        local n = #corners
        while cornerAt < n - 1 do
            local cx, cy = corners[cornerAt] - here.x, corners[cornerAt + 1] - here.y
            if cx * cx + cy * cy > C.CORNER_REACH * C.CORNER_REACH then break end
            cornerAt = cornerAt + 2
        end
        if cornerAt <= n - 1 then
            aimX, aimY = corners[cornerAt], corners[cornerAt + 1]
            for i = cornerAt, n - 3, 2 do
                later = later + math.sqrt((corners[i + 2] - corners[i]) ^ 2 + (corners[i + 3] - corners[i + 1]) ^ 2)
            end
        end
    end
    local dx, dy = aimX - here.x, aimY - here.y
    local yards = math.sqrt(dx * dx + dy * dy) + later
    if facing and not Secret(facing) then
        arrow:SetRotation(math.atan2(dy, dx) - facing + math.pi)
        arrow:SetShown(true)
    else
        arrow:SetShown(false)
    end
    distLabel:SetText(("%d yd"):format(yards))
    if math.sqrt((aim.x - here.x) ^ 2 + (aim.y - here.y) ^ 2) <= C.STEP_REACHED then sinceReplan = C.REPLAN_EVERY end
end

function Render()
    local shown = Enabled() and goal ~= nil and not IsInInstance()
    if not shown then
        if tile then tile:Hide() end
        return
    end
    MakeTile()
    local n = 0
    if arrived then
        nextLabel:SetText("You have arrived")
    elseif not plan then
        nextLabel:SetText("No way found to " .. goal.name)
    else
        local first = plan.legs[1]
        nextLabel:SetText(first and StepLabel(first) or goal.name)
        for i, leg in ipairs(plan.legs) do
            if i > TOP_LINES then break end
            n = i
            lines[i].left:SetText(("%d. %s"):format(i, StepLabel(leg)))
            lines[i].left:SetTextColor(i == 1 and 1 or Pal.text[1], i == 1 and 1 or Pal.text[2], i == 1 and 1 or Pal.text[3])
            lines[i].right:SetText(Duration(leg.seconds))
        end
    end
    for i = 1, TOP_LINES do
        lines[i].left:SetShown(i <= n)
        lines[i].right:SetShown(i <= n)
    end
    local known = 0
    for _ in pairs(CharKeep().flights) do
        known = known + 1
    end
    if plan then
        totalLabel:SetText(("About %s in all%s"):format(Duration(plan.seconds), known == 0 and ". Open a flight master's map to plan with your flights." or ""))
    else
        totalLabel:SetText(known == 0 and "Open a flight master's map to plan with your flights." or "")
    end
    tile:SetHeight(TileHeight(math.max(n, 1)))
    tile:Show()
    PointArrow()
end

-------------------------------------------------------------------------------
--  Events and Apply
-------------------------------------------------------------------------------
local events = CreateFrame("Frame")
local ticker

-- Where the last plan was made from, and the pin it went to: standing
-- still with the same pin, the plan stands (each one searches a continent).
local plannedFrom, plannedMarkerX, plannedMarkerY
local function Moved()
    local here, marker = Person(), Goal()
    if not (here and marker and plannedFrom) then return true end
    if marker.x ~= plannedMarkerX or marker.y ~= plannedMarkerY or here.c ~= plannedFrom.c then return true end
    return Planner.Distance(here, plannedFrom) > C.REPLAN_MOVED
end

-- Your mount's running speed, learned while you ride (walks are timed at it
-- once known: a mounted character rides between steps).
local function GatherMountSpeed()
    if not (IsMounted and IsMounted()) or (UnitOnTaxi and UnitOnTaxi("player")) or IsSwimming() or IsFlying() then return end
    local _, run = GetUnitSpeed("player")
    if not run or Secret(run) or run <= C.RUN_SPEED then return end
    local mine = CharKeep()
    if not mine.mountSpeed or run > mine.mountSpeed + 0.1 then mine.mountSpeed = run end
end

local function Tick()
    GatherMountSpeed()
    sinceReplan = sinceReplan + 0.1
    if sinceReplan >= C.REPLAN_EVERY and not InCombatLockdown() and (Moved() or not plan) then
        local here, marker = Person(), Goal()
        plannedFrom, plannedMarkerX, plannedMarkerY = here, marker and marker.x, marker and marker.y
        Replan()
        Render()
    else
        if sinceReplan >= C.REPLAN_EVERY then sinceReplan = 0 end
        PointArrow()
    end
end

events:SetScript("OnEvent", function(_, event, unit, _, spellID)
    if event == "TAXIMAP_OPENED" then
        atFlightMaster = true
        GatherFlights()
    elseif event == "TAXIMAP_CLOSED" then
        atFlightMaster = false
    elseif event == "TAXI_NODE_STATUS_CHANGED" then
        if atFlightMaster then GatherFlights() end
    elseif event == "HEARTHSTONE_BOUND" then
        landing, castFrom = C.HEARTH_SPELL, nil
        GatherLanding()
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if unit == "player" and not Secret(spellID) and (spellID == C.HEARTH_SPELL or teleportBySpell[spellID]) then
            landing, castFrom = spellID, Person()
            C_Timer.After(10, GatherLanding)
        end
        return
    elseif event == "PLAYER_ENTERING_WORLD" then
        GatherLanding()
    end
    Replan()
    Render()
end)

local EVENTS = { "USER_WAYPOINT_UPDATED", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "PLAYER_CONTROL_GAINED",
    "TAXIMAP_OPENED", "TAXIMAP_CLOSED", "TAXI_NODE_STATUS_CHANGED", "HEARTHSTONE_BOUND", "PLAYER_REGEN_ENABLED" }

local function Apply()
    events:UnregisterAllEvents()
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
    if not Enabled() then
        plan, goal, corners, working = nil, nil, nil, nil
        if driver then driver:SetScript("OnUpdate", nil) end
        if tile then tile:Hide() end
        return
    end
    for _, event in ipairs(EVENTS) do
        events:RegisterEvent(event)
    end
    events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    ticker = C_Timer.NewTicker(0.1, Tick)
    Replan()
    Render()
end

CUI._Journeys = {
    Get = Get,
    Cfg = Cfg,
    Apply = Apply,
    Plan = function() return plan, goal, arrived, corners, working ~= nil end,
    Replan = function()
        Replan()
        Render()
    end,
    StepText = StepLabel,
    Planner = Planner,
}

F.Start(Apply, {
    key = "CUIFE_Journey",
    label = "Journey",
    order = 61,
    frame = function(make)
        if make then MakeTile() end
        return tile
    end,
    size = function() return TILE_W, tile and tile:GetHeight() or TileHeight(3) end,
})
