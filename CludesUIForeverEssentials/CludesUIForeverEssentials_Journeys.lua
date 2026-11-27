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
--  or with a /way link. Walks are straight lines times a detour factor;
--  with no walking maps to say where the sea is, the two islands the
--  network reaches by boat (Teldrassil, Feathermoon) are never walked to or
--  from, so a journey there takes the boat.
--  Flight points are learned at a flight master's map; Hearthstone and
--  teleport landings the first time you use them.
--  Per character: CludesUIDB.journeys.chars["Name-Realm"] = { flights, landings }.
--  Network: CludesUIForeverEssentials_JourneysData.lua.
-------------------------------------------------------------------------------
local _, module = ...

local F = module.Feature("journeys", { enabled = false, hearth = true, teleports = true },
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
    local START, GOAL = 1, 2
    local LINK_MODE = { Tram = "tram", Lift = "lift" }

    local function Has(side, faction) return side:find(faction, 1, true) ~= nil end

    local function Distance(a, b)
        local dx, dy = a.x - b.x, a.y - b.y
        return sqrt(dx * dx + dy * dy)
    end
    Planner.Distance = Distance

    local function AddNode(nodes, node)
        nodes[#nodes + 1] = node
        node.index = #nodes
        return node
    end

    local network = { key = nil }
    local function Network(ctx, net)
        local key = ctx.faction .. ":" .. ctx.knownVersion
        if network.key == key then return network end
        local nodes, flights, docks = { false, false }, {}, {}
        for id, f in pairs(net.flights) do
            if Has(f[6], ctx.faction) and ctx.known[id] then
                flights[id] = AddNode(nodes, { kind = "flight", id = id, name = f[1], c = f[2], x = f[3], y = f[4], key = "f" .. id })
            end
        end
        for s, ship in ipairs(net.ships) do
            if Has(ship[2], ctx.faction) then
                docks[s] = {}
                for i = 3, #ship do
                    local d = ship[i]
                    docks[s][i - 2] = AddNode(nodes, { kind = "dock", ship = s, dock = i - 2, name = d[5], shipKind = ship[1],
                        c = d[1], x = d[2], y = d[3], key = "s" .. s .. "." .. (i - 2) })
                end
            end
        end
        for l, link in ipairs(net.links) do
            if Has(link[2], ctx.faction) then
                local a, b = link[4], link[5]
                local here = AddNode(nodes, { kind = "link", link = l, name = a[4], linkKind = link[1], c = a[1], x = a[2], y = a[3], key = "l" .. l .. ".1" })
                local there = AddNode(nodes, { kind = "link", link = l, name = b[4], linkKind = link[1], c = b[1], x = b[2], y = b[3], key = "l" .. l .. ".2" })
                here.other, there.other = there.index, here.index
            end
        end
        network = { key = key, nodes = nodes, flights = flights, docks = docks }
        return network
    end

    local function Nodes(ctx, net)
        local nodes = {}
        AddNode(nodes, { kind = "start", key = "start", c = ctx.from.c, x = ctx.from.x, y = ctx.from.y })
        AddNode(nodes, { kind = "goal", key = "goal", c = ctx.to.c, x = ctx.to.x, y = ctx.to.y, name = ctx.to.name })
        local fixed = Network(ctx, net)
        for i = GOAL + 1, #fixed.nodes do
            nodes[i] = fixed.nodes[i]
        end
        for _, jump in ipairs(ctx.jumps or {}) do
            AddNode(nodes, { kind = "jump", key = "j" .. (jump.spell or jump.item), mode = jump.mode, name = jump.name, cast = jump.cast,
                spell = jump.spell, item = jump.item, c = jump.c, x = jump.x, y = jump.y })
        end
        return nodes, fixed.flights, fixed.docks
    end

    local function TaxiGraph(net, flights)
        local graph = {}
        for _, hop in ipairs(net.hops) do
            local a, b = hop[1], hop[2]
            if flights[a] and flights[b] then
                graph[a] = graph[a] or {}
                graph[a][#graph[a] + 1] = { b, hop[3] / C.FLIGHT_SPEED }
            end
        end
        return graph
    end

    local function FlightsFrom(graph, from)
        local times, prev, done = { [from] = 0 }, {}, {}
        while true do
            local best, bestTime = nil, huge
            for id, t in pairs(times) do
                if not done[id] and t < bestTime then best, bestTime = id, t end
            end
            if not best then return times, prev end
            done[best] = true
            for _, edge in ipairs(graph[best] or {}) do
                local t = bestTime + edge[2]
                if t < (times[edge[1]] or huge) then times[edge[1]], prev[edge[1]] = t, best end
            end
        end
    end

    local cache = { key = nil, from = {}, prev = {} }
    local function FlightTimes(ctx, net, flights, from)
        local key = ctx.faction .. ":" .. ctx.knownVersion
        if cache.key ~= key then
            cache.key, cache.from, cache.prev, cache.graph = key, {}, {}, TaxiGraph(net, flights)
        end
        local times = cache.from[from]
        if not times then
            times, cache.prev[from] = FlightsFrom(cache.graph, from)
            cache.from[from] = times
        end
        return times, cache.prev[from]
    end

    local function Period(ship)
        local total = 0
        local speed = C.SHIP_SPEED[ship[1]]
        for i = 3, #ship do
            total = total + ship[i][6] + ship[i][7] / speed
        end
        return total
    end

    local function Sail(ship, from, to)
        local speed = C.SHIP_SPEED[ship[1]]
        local count = #ship - 2
        local t, i = 0, from
        while i ~= to do
            t = t + ship[i + 2][7] / speed
            i = i % count + 1
            if i ~= to then t = t + ship[i + 2][6] end
        end
        return t
    end

    local function Relax(state, from, to, cost)
        local t = state.time[from] + cost
        if t >= state.time[to] then return false end
        state.time[to] = t
        state.prev[to] = from
        return true
    end

    -- Islands a boat reaches, boxed round the network's own places there:
    -- Teldrassil (Rut'theran, Darnassus) north of 8000 on Kalimdor, and
    -- Feathermoon within 500 yards of its docks.
    local function Island(spot)
        if spot.c ~= 1 then return nil end
        if spot.x >= 8000 and spot.y >= 0 then return "teldrassil" end
        local dx, dy = spot.x + 4300, spot.y - 3320
        if dx * dx + dy * dy <= 500 * 500 then return "feathermoon" end
    end
    Planner.Island = Island

    local function RelaxWalks(ctx, state, nodes, u)
        local a = nodes[u]
        local island = Island(a)
        for v = GOAL, #nodes do
            local b = nodes[v]
            if v ~= u and b.c == a.c and b.kind ~= "jump" and not state.done[v] and Island(b) == island then
                local seconds = Distance(a, b) * C.WALK_DETOUR / ctx.speed
                if Relax(state, u, v, seconds) then state.leg[v] = { mode = "walk", seconds = seconds } end
            end
        end
    end

    local function RelaxFlights(ctx, state, nodes, u, net)
        local times = FlightTimes(ctx, net, state.flights, nodes[u].id)
        for id, flown in pairs(times) do
            local v = state.flights[id].index
            if v ~= u and not state.done[v] then
                local seconds = flown + C.TAXI_OVERHEAD + C.TRANSFER
                if Relax(state, u, v, seconds) then state.leg[v] = { mode = "fly", seconds = seconds } end
            end
        end
    end

    local function RelaxShip(state, nodes, u, net)
        local a = nodes[u]
        local ship = net.ships[a.ship]
        local wait = Period(ship) / 2
        for j, b in ipairs(state.docks[a.ship]) do
            if j ~= a.dock and not state.done[b.index] then
                local ride = Sail(ship, a.dock, j) + C.BOARD + C.TRANSFER
                if b.c ~= a.c then ride = ride + C.LOADING end
                if Relax(state, u, b.index, wait + ride) then
                    state.leg[b.index] = { mode = "ship", seconds = wait + ride, wait = wait }
                end
            end
        end
    end

    local function RelaxLink(state, nodes, u, net)
        local a = nodes[u]
        if state.done[a.other] then return end
        local seconds = net.links[a.link][3] + C.TRANSFER
        if Relax(state, u, a.other, seconds) then state.leg[a.other] = { mode = LINK_MODE[a.linkKind] or "portal", seconds = seconds } end
    end

    local function RelaxJumps(state, nodes)
        for v = GOAL + 1, #nodes do
            local b = nodes[v]
            if b.kind == "jump" then
                local seconds = b.cast + C.LOADING
                if Relax(state, START, v, seconds) then
                    state.leg[v] = { mode = b.mode, seconds = seconds, spell = b.spell, item = b.item }
                end
            end
        end
    end

    local function Legs(state, nodes, v)
        local legs = {}
        while state.prev[v] do
            local leg = state.leg[v]
            local node = nodes[v]
            leg.name, leg.kind, leg.key, leg.c, leg.x, leg.y = node.name, node.kind, node.key, node.c, node.x, node.y
            leg.shipKind = node.shipKind
            if leg.mode ~= "walk" or leg.seconds >= C.MIN_WALK then table.insert(legs, 1, leg) end
            v = state.prev[v]
        end
        return legs
    end

    local function Same(a, b)
        if #a.legs ~= #b.legs then return false end
        for i, leg in ipairs(a.legs) do
            if leg.key ~= b.legs[i].key or leg.mode ~= b.legs[i].mode then return false end
        end
        return true
    end

    -- The route you follow, timed from where you stand: the quickest way to
    -- its next place, then the rest as it was.
    local function Kept(old, state, nodes)
        local first = old.legs[1]
        if not first then return nil end
        for v = GOAL, #nodes do
            if nodes[v].key == first.key and state.time[v] < huge then
                local legs, seconds = Legs(state, nodes, v), state.time[v]
                for i = 2, #old.legs do
                    legs[#legs + 1] = old.legs[i]
                    seconds = seconds + old.legs[i].seconds
                end
                return { seconds = seconds, legs = legs }
            end
        end
    end

    local function Better(best, kept)
        if Same(best, kept) then return true end
        return best.seconds <= kept.seconds - C.SWITCH_GAIN and best.seconds <= kept.seconds * (1 - C.SWITCH_SHARE)
    end

    function Planner.Plan(ctx)
        local net = module.JOURNEY_NETWORK
        local nodes, flights, docks = Nodes(ctx, net)
        local state = { time = {}, prev = {}, leg = {}, done = {}, docks = docks, flights = flights }
        for i = 1, #nodes do
            state.time[i] = huge
        end
        state.time[START] = 0
        while true do
            local u, best = nil, huge
            for i = 1, #nodes do
                if not state.done[i] and state.time[i] < best then u, best = i, state.time[i] end
            end
            if not u or u == GOAL then break end
            state.done[u] = true
            local kind = nodes[u].kind
            RelaxWalks(ctx, state, nodes, u)
            if kind == "start" then RelaxJumps(state, nodes) end
            if kind == "flight" then RelaxFlights(ctx, state, nodes, u, net) end
            if kind == "dock" then RelaxShip(state, nodes, u, net) end
            if kind == "link" then RelaxLink(state, nodes, u, net) end
        end
        local best
        if state.time[GOAL] < huge then
            local legs, seconds = Legs(state, nodes, GOAL), 0
            for _, leg in ipairs(legs) do
                seconds = seconds + leg.seconds
            end
            best = { seconds = seconds, legs = legs }
        end
        local kept = ctx.keep and Kept(ctx.keep, state, nodes)
        if kept and not (best and Better(best, kept)) then return kept end
        return best
    end
end

-------------------------------------------------------------------------------
--  World: where you are, the pin, flights you know, jumps you can take
-------------------------------------------------------------------------------
local knownVersion = 0
local teleportBySpell = {}
for _, tp in ipairs(module.JOURNEY_TELEPORTS or {}) do
    teleportBySpell[tp.spell] = tp
end

local function CharStore()
    local root = Cfg()
    root.chars = root.chars or {}
    local key = (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
    local mine = root.chars[key]
    if not mine then
        mine = { flights = {}, landings = {} }
        root.chars[key] = mine
        knownVersion = knownVersion + 1
        -- Seed from the Flight Point Reminder's record of this character.
        local seen = CludesUIDB and CludesUIDB.flightPointsKnown and CludesUIDB.flightPointsKnown[key]
        for id, known in pairs(seen or {}) do
            if type(id) == "number" and known == true then mine.flights[id] = true end
        end
    end
    return mine
end

local function Player()
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
    local list = {}
    local landings = CharStore().landings
    if Get("hearth") and landings.hearth and C_Item.GetItemCount(C.HEARTHSTONE) > 0 then
        local start, duration = C_Item.GetItemCooldown(C.HEARTHSTONE)
        if Ready(start, duration) then
            local home = landings.hearth
            list[#list + 1] = { mode = "hearth", name = home.name or "home", cast = C.HEARTH_CAST, item = C.HEARTHSTONE, c = home.c, x = home.x, y = home.y }
        end
    end
    if Get("teleports") then
        for _, tp in ipairs(module.JOURNEY_TELEPORTS or {}) do
            local known = tp.side:find(faction, 1, true) and C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(tp.spell)
            local cd = known and C_Spell.GetSpellCooldown(tp.spell)
            if cd and Ready(cd.startTime, cd.duration) and (not tp.reagent or C_Item.GetItemCount(tp.reagent) > 0) then
                local spot = landings[tp.spell] or tp
                list[#list + 1] = { mode = "teleport", name = tp.name, cast = C.TELEPORT_CAST, spell = tp.spell, c = spot.c, x = spot.x, y = spot.y }
            end
        end
    end
    return list
end

local atFlightMaster = false
local function LearnFlights()
    local taxi = GetTaxiMapID and GetTaxiMapID()
    if not taxi then return false end
    local known = CharStore().flights
    local changed = false
    for _, node in ipairs(C_TaxiMap.GetAllTaxiNodes(taxi) or {}) do
        local now = node.state ~= Enum.FlightPathState.Unreachable or nil
        if node.nodeID and known[node.nodeID] ~= now then known[node.nodeID], changed = now, true end
    end
    if changed then knownVersion = knownVersion + 1 end
    return changed
end

local landing, castFrom
local function LearnLanding()
    local spell, spot = landing, Player()
    if not spell or not spot then return end
    if castFrom and spot.c == castFrom.c and Planner.Distance(spot, castFrom) < 100 then return end
    landing, castFrom = nil, nil
    local landings = CharStore().landings
    if spell == C.HEARTH_SPELL then
        landings.hearth = { name = GetBindLocation and GetBindLocation() or "home", c = spot.c, x = spot.x, y = spot.y }
    else
        landings[spell] = spot
    end
end

-------------------------------------------------------------------------------
--  Guide: the journey you follow
-------------------------------------------------------------------------------
local plan, goal, arrived
local sinceReplan = 0

local function StepText(leg)
    local mode, name = leg.mode, leg.name or "?"
    if mode == "walk" then
        if leg.kind == "flight" then return "Flight master: " .. name end
        if leg.kind == "dock" then return name .. " dock" end
        return name
    end
    if mode == "fly" then return "Fly to " .. name end
    if mode == "ship" then return (leg.shipKind or "Boat") .. " to " .. name end
    if mode == "tram" then return "Deeprun Tram to " .. name end
    if mode == "portal" then return "Portal to " .. name end
    if mode == "lift" then return "Lift to " .. name end
    if mode == "hearth" then return "Hearthstone to " .. name end
    return "Teleport to " .. name
end

local function Duration(seconds)
    seconds = math.floor(seconds + 0.5)
    if seconds < 60 then return seconds .. "s" end
    if seconds < 3600 then return ("%dm %02ds"):format(seconds / 60, seconds % 60) end
    return ("%dh %02dm"):format(seconds / 3600, (seconds % 3600) / 60)
end

local function Replan()
    sinceReplan = 0
    local was = goal
    goal = Goal()
    -- A pin moved somewhere else is a new journey: the old route is not kept.
    if goal and was and (goal.c ~= was.c or Planner.Distance(goal, was) > 1) then plan = nil end
    if not goal then
        plan, arrived = nil, false
        return
    end
    if UnitOnTaxi and UnitOnTaxi("player") then return end
    local from = Player()
    if not from then return end
    if from.c == goal.c and Planner.Distance(from, goal) <= C.ARRIVED then
        plan, arrived = nil, true
        return
    end
    arrived = false
    local faction = UnitFactionGroup("player") == "Horde" and "H" or "A"
    local known = CharStore().flights
    plan = Planner.Plan({
        from = from,
        to = goal,
        faction = faction,
        known = known,
        knownVersion = knownVersion,
        speed = C.RUN_SPEED,
        jumps = Jumps(faction),
        keep = plan,
    })
end

-------------------------------------------------------------------------------
--  The Journey card
-------------------------------------------------------------------------------
local CARD_W, LINE_H, ARROW_ROW = 290, 17, 52
local MAX_LINES = 7
local card, arrow, nextText, distText, lines, totalText
local ARROW = "Interface\\AddOns\\CludesUI\\media\\icons\\cui-arrow-down3.png"

local function CardHeight(n) return Kit.HEADER_H + ARROW_ROW + n * LINE_H + 30 end

local function BuildCard()
    if card then return card end
    card = Kit.Window("CludesUIJourney", CARD_W, CardHeight(3), CUI.L("Journey"), { key = "essentials", special = false, strata = "MEDIUM" })
    card:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint(1)
        Cfg().pos = { point = point, relPoint = relPoint, x = x, y = y }
    end)
    F.Place(card)
    arrow = card:CreateTexture(nil, "ARTWORK")
    arrow:SetTexture(ARROW)
    arrow:SetSize(36, 36)
    arrow:SetPoint("TOPLEFT", 12, -(Kit.HEADER_H + 8))
    local r, g, b = Kit.Accent()
    arrow:SetVertexColor(r, g, b)
    nextText = card:CreateFontString(nil, "OVERLAY")
    Kit.Font(nextText, Kit.TEXT_SIZE, "essentials")
    nextText:SetPoint("TOPLEFT", 58, -(Kit.HEADER_H + 10))
    nextText:SetPoint("RIGHT", card, "RIGHT", -10, 0)
    nextText:SetJustifyH("LEFT")
    nextText:SetWordWrap(false)
    distText = card:CreateFontString(nil, "OVERLAY")
    Kit.Font(distText, Kit.SMALL_SIZE, "essentials")
    distText:SetPoint("TOPLEFT", nextText, "BOTTOMLEFT", 0, -4)
    distText:SetTextColor(Pal.muted[1], Pal.muted[2], Pal.muted[3])
    lines = {}
    for i = 1, MAX_LINES do
        local left = card:CreateFontString(nil, "OVERLAY")
        Kit.Font(left, Kit.SMALL_SIZE, "essentials")
        left:SetPoint("TOPLEFT", 12, -(Kit.HEADER_H + ARROW_ROW + (i - 1) * LINE_H))
        left:SetPoint("RIGHT", card, "RIGHT", -70, 0)
        left:SetJustifyH("LEFT")
        left:SetWordWrap(false)
        local right = card:CreateFontString(nil, "OVERLAY")
        Kit.Font(right, Kit.SMALL_SIZE, "essentials")
        right:SetPoint("TOPRIGHT", card, "TOPRIGHT", -10, -(Kit.HEADER_H + ARROW_ROW + (i - 1) * LINE_H))
        right:SetJustifyH("RIGHT")
        right:SetTextColor(Pal.muted[1], Pal.muted[2], Pal.muted[3])
        lines[i] = { left = left, right = right }
    end
    totalText = card:CreateFontString(nil, "OVERLAY")
    Kit.Font(totalText, Kit.SMALL_SIZE, "essentials")
    totalText:SetPoint("BOTTOMLEFT", 12, 10)
    totalText:SetPoint("RIGHT", card, "RIGHT", -10, 0)
    totalText:SetJustifyH("LEFT")
    totalText:SetTextColor(Pal.muted[1], Pal.muted[2], Pal.muted[3])
    card:Hide()
    return card
end

-- The arrow turns toward the next step's place (x north, y west; the game's
-- facing is radians from north, counter-clockwise). The art points down.
local function PointArrow()
    if not (card and card:IsShown()) then return end
    local leg = plan and plan.legs[1]
    local here = Player()
    local target = leg and (leg.mode == "walk" and leg or nil)
    if arrived or not (target and here and here.c == target.c) then
        arrow:SetShown(false)
        distText:SetText(arrived and "" or (UnitOnTaxi and UnitOnTaxi("player") and "In flight" or ""))
        return
    end
    local facing = GetPlayerFacing and GetPlayerFacing()
    local dx, dy = target.x - here.x, target.y - here.y
    local yards = math.sqrt(dx * dx + dy * dy)
    if facing and not Secret(facing) then
        arrow:SetRotation(math.atan2(dy, dx) - facing + math.pi)
        arrow:SetShown(true)
    else
        arrow:SetShown(false)
    end
    distText:SetText(("%d yd"):format(yards))
    if yards <= C.STEP_REACHED then sinceReplan = C.REPLAN_EVERY end
end

local function Draw()
    local shown = Enabled() and goal ~= nil and not IsInInstance()
    if not shown then
        if card then card:Hide() end
        return
    end
    BuildCard()
    local n = 0
    if arrived then
        nextText:SetText("You have arrived")
    elseif not plan then
        nextText:SetText("No way found to " .. goal.name)
    else
        local first = plan.legs[1]
        nextText:SetText(first and StepText(first) or goal.name)
        for i, leg in ipairs(plan.legs) do
            if i > MAX_LINES then break end
            n = i
            lines[i].left:SetText(("%d. %s"):format(i, StepText(leg)))
            lines[i].left:SetTextColor(i == 1 and 1 or Pal.text[1], i == 1 and 1 or Pal.text[2], i == 1 and 1 or Pal.text[3])
            lines[i].right:SetText(Duration(leg.seconds))
        end
    end
    for i = 1, MAX_LINES do
        lines[i].left:SetShown(i <= n)
        lines[i].right:SetShown(i <= n)
    end
    local known = 0
    for _ in pairs(CharStore().flights) do
        known = known + 1
    end
    if plan then
        totalText:SetText(("About %s in all%s"):format(Duration(plan.seconds), known == 0 and ". Open a flight master's map to plan with your flights." or ""))
    else
        totalText:SetText(known == 0 and "Open a flight master's map to plan with your flights." or "")
    end
    card:SetHeight(CardHeight(math.max(n, 1)))
    card:Show()
    PointArrow()
end

-------------------------------------------------------------------------------
--  Events and Apply
-------------------------------------------------------------------------------
local events = CreateFrame("Frame")
local ticker

local function Tick()
    sinceReplan = sinceReplan + 0.1
    if sinceReplan >= C.REPLAN_EVERY and not InCombatLockdown() then
        Replan()
        Draw()
    else
        PointArrow()
    end
end

events:SetScript("OnEvent", function(_, event, unit, _, spellID)
    if event == "TAXIMAP_OPENED" then
        atFlightMaster = true
        LearnFlights()
    elseif event == "TAXIMAP_CLOSED" then
        atFlightMaster = false
    elseif event == "TAXI_NODE_STATUS_CHANGED" then
        if atFlightMaster then LearnFlights() end
    elseif event == "HEARTHSTONE_BOUND" then
        landing, castFrom = C.HEARTH_SPELL, nil
        LearnLanding()
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if unit == "player" and not Secret(spellID) and (spellID == C.HEARTH_SPELL or teleportBySpell[spellID]) then
            landing, castFrom = spellID, Player()
            C_Timer.After(10, LearnLanding)
        end
        return
    elseif event == "PLAYER_ENTERING_WORLD" then
        LearnLanding()
    end
    Replan()
    Draw()
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
        plan, goal = nil, nil
        if card then card:Hide() end
        return
    end
    for _, event in ipairs(EVENTS) do
        events:RegisterEvent(event)
    end
    events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    ticker = C_Timer.NewTicker(0.1, Tick)
    Replan()
    Draw()
end

CUI._Journeys = {
    Get = Get,
    Cfg = Cfg,
    Apply = Apply,
    Plan = function() return plan, goal, arrived end,
    Replan = function()
        Replan()
        Draw()
    end,
    StepText = StepText,
    Planner = Planner,
}

F.Start(Apply, {
    key = "CUIFE_Journey",
    label = "Journey",
    order = 61,
    frame = function(build)
        if build then BuildCard() end
        return card
    end,
    size = function() return CARD_W, card and card:GetHeight() or CardHeight(3) end,
})
