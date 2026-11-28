if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
if not (CUI and CUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_Walking.lua  (WoW Forever only)
--  Walking costs and paths for Journeys, over the walking maps in the
--  load-on-demand CludesUIJourneysData addon (loaded the firstCorner time a
--  journey needs them, never in combat).
--
--  The maps, per continent, in world yards (x north, y west):
--    tiles["tx_ty"]  a 533 yard square of walkable polygons: v vertices
--                    (delta coded x, y, z), p polygons (vertex count then
--                    delta coded indices), a each polygon's ground (0 land,
--                    1 water, 2 sea), x { gateId, polygon } pairs where
--                    the tile meets the continent graph, l links beside a
--                    tile side { polygon, side, dtx, dty, polygon there }
--    graph           c gates (x, y, z), e edges (a, b, yards)
--    walks           k the travel places ("f2" flight, "s3.1" dock, "l1.2"
--                    link end), d yards between each pair (-1: no walk),
--                    r each place's reach { col, row, polygon, gateId,
--                    yards, gateId, yards, ... }
--  Each is CBOR, deflated, in Base64, decoded when firstCorner needed; at most
--  TILE_CACHE tiles stay decoded, and everything is let go after a minute
--  unused.
--
--  A walk from a spot: the cheapest way to every polygon of its tile
--  (Dijkstra over polygon neighbours, water and sea dist more), then on to
--  every gateId of the continent graph. Between two spots: the best
--  gateId of the outward end's tile, or straight beside a shared tile. The
--  path is the gates passed, each tile's polygons between them pulled
--  tight (funnel), then corners cut wherever a straight line stays on land.
--  Searches pause when they use up their slice of a frame (Slice) inside a
--  coroutine; Journeys drives them beside frames.
-------------------------------------------------------------------------------
local _, module = ...

local sqrt, floor, abs, huge = math.sqrt, math.floor, math.abs, math.huge
local yield, running = coroutine.yield, coroutine.running

local DATA_ADDON = "CludesUIJourneysData"
local TILE_YARDS = 1600 / 3
local GRID_ORIGIN = 32 * TILE_YARDS
local EDGE_KEY = 65536
local MAX_SIDES = 8
local LAND, WATER, SEA = 0, 1, 2
local GROUND_COST = { [LAND] = 1, [WATER] = 1.6, [SEA] = 2.5 }
local TILE_CACHE = 48
local RELEASE_AFTER = 60
local SLICE_MS = 3
local STAND_REACH = 200
local HEIGHT_WEIGHT = 0.25
local PIER_WIDTH = 30
local NUDGE = 0.5
local RAY_STEPS = 4000
local RAY_SLACK = 1e-6
local ON_EDGE = 0.05
local NEIGHBOUR_TILES = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

local Walking = {}
module.Walking = Walking

local loaded -- nil: not tried; true/false after
local data -- CUI.WalkingData once the addon is in
local tileCache, tileUsed = {}, {}
local graphCache, placeCache = {}, {}
local sliceEnd = 0
local lastUse, releaseQueued = 0, false

-- A decoded table, or nil when the packed text will not decode.
local function Unpack(packed)
    local u = C_EncodingUtil
    local ok, raw = pcall(function()
        return u.DeserializeCBOR(u.DecompressString(u.DecodeBase64(packed), Enum.CompressionMethod.Deflate))
    end)
    if ok and type(raw) == "table" then return raw end
end

-- Yields once this frame's slice is spent, when run inside a coroutine.
local function Slice()
    if running() and debugprofilestop() > sliceEnd then
        yield()
        sliceEnd = debugprofilestop() + SLICE_MS
    end
end
function Walking.StartSlice() sliceEnd = debugprofilestop() + SLICE_MS end

local function Release()
    local idle = GetTime() - lastUse
    if idle < RELEASE_AFTER then
        C_Timer.After(RELEASE_AFTER - idle, Release)
        return
    end
    releaseQueued = false
    wipe(tileCache)
    wipe(tileUsed)
    wipe(graphCache)
    wipe(placeCache)
end

local function Touch()
    lastUse = GetTime()
    if releaseQueued then return end
    releaseQueued = true
    C_Timer.After(RELEASE_AFTER, Release)
end

-- Loads the walking maps (once, out of combat). False when they are missing.
function Walking.Ready()
    if loaded ~= nil then return loaded end
    if InCombatLockdown() then return false end
    local u = C_EncodingUtil
    if not (u and u.DecodeBase64 and u.DecompressString and u.DeserializeCBOR) then
        loaded = false
        return false
    end
    CUI.WalkingData = CUI.WalkingData or { tiles = { [0] = {}, [1] = {}, [2991] = {} }, graph = {}, walks = {} }
    local isLoaded = C_AddOns.IsAddOnLoaded(DATA_ADDON)
    if not isLoaded then isLoaded = C_AddOns.LoadAddOn(DATA_ADDON) end
    data = CUI.WalkingData
    -- Loaded and decodable: one continent's graph is tried before trusting any.
    local c, packed = next(data.graph)
    loaded = isLoaded and c ~= nil and Unpack(packed) ~= nil or false
    return loaded
end

-------------------------------------------------------------------------------
--  Tiles
-------------------------------------------------------------------------------
-- For each polygon side, the polygon beside it (shared vertex pair).
local function LinkSides(rings)
    local firstOwner, beside = {}, {}
    for p = 1, #rings do
        local ring, row = rings[p], {}
        beside[p] = row
        for k = 1, #ring do
            local a, b = ring[k], ring[k % #ring + 1]
            local key = a < b and a * EDGE_KEY + b or b * EDGE_KEY + a
            local owner = firstOwner[key]
            if owner then
                local q = floor(owner / MAX_SIDES)
                row[k] = q
                beside[q][owner % MAX_SIDES + 1] = p
            else
                firstOwner[key] = p * MAX_SIDES + k - 1
            end
        end
    end
    return beside
end

local function BuildTile(col, row, raw)
    local baseX, baseY = GRID_ORIGIN - row * TILE_YARDS, GRID_ORIGIN - col * TILE_YARDS
    local xs, ys, zs = {}, {}, {}
    local ax, ay, az = 0, 0, 0
    local verts = raw.v
    for i = 1, #verts, 3 do
        ax, ay, az = ax + verts[i], ay + verts[i + 1], az + verts[i + 2]
        local n = #xs + 1
        xs[n], ys[n], zs[n] = baseX - ax, baseY - ay, az
    end
    local rings, packed, index, i = {}, raw.p, 0, 1
    while i <= #packed do
        local ring = {}
        for k = 1, packed[i] do
            index = index + packed[i + k]
            ring[k] = index
        end
        i = i + packed[i] + 1
        rings[#rings + 1] = ring
    end
    local midX, midY, midZ = {}, {}, {}
    for n = 1, #rings do
        local ring, sx, sy, sz = rings[n], 0, 0, 0
        for k = 1, #ring do
            sx, sy, sz = sx + xs[ring[k]], sy + ys[ring[k]], sz + zs[ring[k]]
        end
        midX[n], midY[n], midZ[n] = sx / #ring, sy / #ring, sz / #ring
    end
    local gates = {}
    local x = raw.x or {}
    for k = 1, #x, 2 do
        gates[#gates + 1] = { x[k], x[k + 1] }
    end
    local seams = {}
    local l = raw.l or {}
    for k = 1, #l, 5 do
        local key = l[k] * MAX_SIDES + l[k + 1] - 1
        local list = seams[key] or {}
        seams[key] = list
        list[#list + 1], list[#list + 2], list[#list + 3] = l[k + 2], l[k + 3], l[k + 4]
    end
    return {
        xs = xs, ys = ys, zs = zs, rings = rings, beside = LinkSides(rings),
        midX = midX, midY = midY, midZ = midZ, ground = raw.a, gates = gates, seams = seams,
    }
end

local function DropOldestTile()
    local oldest, oldestKey = huge, nil
    for key, at in pairs(tileUsed) do
        if at < oldest then oldest, oldestKey = at, key end
    end
    if oldestKey then tileCache[oldestKey], tileUsed[oldestKey] = nil, nil end
end

local function Tile(c, col, row)
    if not Walking.Ready() then return nil end
    local key = c .. ":" .. col .. ":" .. row
    local tile = tileCache[key]
    if tile == nil then
        local all = data.tiles[c]
        local packed = all and all[col .. "_" .. row]
        local raw = packed and Unpack(packed)
        tile = raw and BuildTile(col, row, raw) or false
        local count = 0
        for _ in pairs(tileCache) do
            count = count + 1
        end
        if count >= TILE_CACHE then DropOldestTile() end
        tileCache[key] = tile
    end
    tileUsed[key] = GetTime()
    Touch()
    return tile or nil
end
Walking.Tile = Tile

local function TileOf(x, y) return floor((GRID_ORIGIN - y) / TILE_YARDS), floor((GRID_ORIGIN - x) / TILE_YARDS) end
Walking.TileOf = TileOf

local function InPolygon(tile, ring, x, y)
    local xs, ys = tile.xs, tile.ys
    local inside = false
    local j = ring[#ring]
    for k = 1, #ring do
        local i = ring[k]
        if (ys[i] > y) ~= (ys[j] > y) and x < (xs[j] - xs[i]) * (y - ys[i]) / (ys[j] - ys[i]) + xs[i] then inside = not inside end
        j = i
    end
    return inside
end

-- The polygon a spot stands on: the one under it (nearest in height), else
-- the nearest within STAND_REACH. dry: never the sea. Returns polygon,
-- yards to it (0 when on it).
local function StandOn(tile, x, y, z, dry)
    local best, bestScore, off = nil, huge, 0
    local ground = dry and tile.ground
    for p = 1, #tile.rings do
        local dx, dy = tile.midX[p] - x, tile.midY[p] - y
        local flat = sqrt(dx * dx + dy * dy)
        local on = InPolygon(tile, tile.rings[p], x, y)
        local rise = z and abs(tile.midZ[p] - z) or 0
        local score = on and rise or flat + rise * HEIGHT_WEIGHT
        if (on or flat < STAND_REACH) and score < bestScore and not (ground and ground[p] == SEA) then
            best, bestScore, off = p, score, on and 0 or flat + rise
        end
    end
    return best, off
end

-- Whether a spot is on land (not the sea). True when nothing can say.
function Walking.Ashore(spot)
    if not Walking.Ready() then return true end
    local tile = Tile(spot.c, TileOf(spot.x, spot.y))
    local ring = tile and StandOn(tile, spot.x, spot.y, spot.z)
    return ring ~= nil and not (tile.ground and tile.ground[ring] == SEA)
end

-------------------------------------------------------------------------------
--  Searches
-------------------------------------------------------------------------------
local function HeapPush(queue, dist, node)
    local n = #queue + 1
    queue[n] = node
    while n > 1 do
        local up = floor(n / 2)
        if dist[queue[up]] <= dist[queue[n]] then break end
        queue[up], queue[n] = queue[n], queue[up]
        n = up
    end
end

local function HeapPop(queue, dist)
    local top, n = queue[1], #queue
    queue[1] = queue[n]
    queue[n] = nil
    n = n - 1
    local i = 1
    while true do
        local l, r, m = 2 * i, 2 * i + 1, i
        if l <= n and dist[queue[l]] < dist[queue[m]] then m = l end
        if r <= n and dist[queue[r]] < dist[queue[m]] then m = r end
        if m == i then break end
        queue[m], queue[i] = queue[i], queue[m]
        i = m
    end
    return top
end

local function SideMiddle(tile, p, k)
    local ring = tile.rings[p]
    local a, b = ring[k], ring[k % #ring + 1]
    return (tile.xs[a] + tile.xs[b]) / 2, (tile.ys[a] + tile.ys[b]) / 2, (tile.zs[a] + tile.zs[b]) / 2
end

local function ToMiddle(tile, p, x, y, z)
    local dx, dy, dz = tile.midX[p] - x, tile.midY[p] - y, tile.midZ[p] - z
    local rate = tile.ground and GROUND_COST[tile.ground[p]] or 1
    return sqrt(dx * dx + dy * dy + dz * dz) * rate
end

-- The cheapest way from polygon `from` (starting at `extra` yards) to every
-- polygon of the tile: dist[p], cameFrom[p].
local function SpreadInTile(tile, from, extra)
    local dist, settled, queue, cameFrom = { [from] = extra }, {}, { from }, {}
    while #queue > 0 do
        local p = HeapPop(queue, dist)
        if not settled[p] then
            settled[p] = true
            local beside = tile.beside[p]
            for k = 1, #tile.rings[p] do
                local q = beside[k]
                if q and not settled[q] then
                    local sx, sy, sz = SideMiddle(tile, p, k)
                    local c = dist[p] + ToMiddle(tile, p, sx, sy, sz) + ToMiddle(tile, q, sx, sy, sz)
                    if c < (dist[q] or huge) then
                        dist[q], cameFrom[q] = c, p
                        HeapPush(queue, dist, q)
                    end
                end
            end
            Slice()
        end
    end
    return dist, cameFrom
end

local function Graph(c)
    Touch()
    local web = graphCache[c]
    if web == nil then
        local packed = data.graph[c]
        web = false
        local raw = packed and Unpack(packed)
        if raw then
            local cs, es, px, py, pz, edgesOf = raw.c, raw.e, {}, {}, {}, {}
            for i = 1, #cs, 3 do
                local n = #px + 1
                px[n], py[n], pz[n], edgesOf[n] = cs[i], cs[i + 1], cs[i + 2], {}
            end
            for i = 1, #es, 3 do
                local a, b, yards = es[i], es[i + 1], es[i + 2]
                local la, lb = edgesOf[a], edgesOf[b]
                la[#la + 1], la[#la + 2] = b, yards
                lb[#lb + 1], lb[#lb + 2] = a, yards
            end
            web = { nodeX = px, nodeY = py, nodeZ = pz, edgesOf = edgesOf }
        end
        graphCache[c] = web
    end
    return web or nil
end

local function Places(c)
    Touch()
    local places = placeCache[c]
    if places == nil then
        local packed = data.walks[c]
        places = false
        local raw = packed and Unpack(packed)
        if raw then
            local index = {}
            for i, key in ipairs(raw.k) do
                index[key] = i
            end
            places = { index = index, count = #raw.k, between = raw.d, reachOf = raw.r }
        end
        placeCache[c] = places
    end
    return places or nil
end

-- Every gateId's dist from the seeds { [gateId] = yards }.
local function SearchGraph(web, seeds)
    local dist, settled, queue, cameFrom = {}, {}, {}, {}
    for gateId, yards in pairs(seeds) do
        dist[gateId] = yards
        HeapPush(queue, dist, gateId)
    end
    while #queue > 0 do
        local a = HeapPop(queue, dist)
        if not settled[a] then
            settled[a] = true
            local list = web.edgesOf[a]
            for i = 1, #list, 2 do
                local b = list[i]
                local yards = dist[a] + list[i + 1]
                if not settled[b] and yards < (dist[b] or huge) then
                    dist[b], cameFrom[b] = yards, a
                    HeapPush(queue, dist, b)
                end
            end
            Slice()
        end
    end
    return dist, cameFrom
end

-- A boat dock's spot is the ship's, in the water: a spot between a dock
-- and where its pier meets land walks from that root.
local function PierRoot(c, spot)
    local places = Places(c)
    local net = module.JOURNEY_NETWORK
    if not (places and net) then return nil end
    for s, ship in ipairs(net.ships) do
        if ship[1] == "Boat" then
            for i = 3, #ship do
                local dock = ship[i]
                local at = dock[1] == c and places.index["s" .. s .. "." .. (i - 2)]
                local root = at and places.reachOf[at]
                local tile = root and root[1] and Tile(c, root[1], root[2])
                if tile then
                    local rootX, rootY = tile.midX[root[3]], tile.midY[root[3]]
                    local pierLength = sqrt((dock[2] - rootX) ^ 2 + (dock[3] - rootY) ^ 2)
                    local fromRoot = sqrt((spot.x - rootX) ^ 2 + (spot.y - rootY) ^ 2)
                    local fromDock = sqrt((spot.x - dock[2]) ^ 2 + (spot.y - dock[3]) ^ 2)
                    if fromDock + fromRoot <= pierLength + PIER_WIDTH then return tile, root[1], root[2], root[3], fromRoot end
                end
            end
        end
    end
end

-- A spot's reach: its tile, polygon, costs to its tile's polygons (inTile)
-- and to every gateId (outward). nil where there is no walking data, false
-- where the spot is off it (the sea, past a pier).
function Walking.Reach(spot)
    if not Walking.Ready() then return nil end
    local c = spot.c
    local web = Graph(c)
    if not web then return nil end
    local col, row = TileOf(spot.x, spot.y)
    local tile = Tile(c, col, row)
    local ring, off
    if tile then ring, off = StandOn(tile, spot.x, spot.y, spot.z, true) end
    if not ring then
        local baseCol, baseRow = col, row
        for dx = -1, 1 do
            for dy = -1, 1 do
                local t = Tile(c, baseCol + dx, baseRow + dy)
                if t then
                    local p, o = StandOn(t, spot.x, spot.y, spot.z, true)
                    if p and (not ring or o < off) then ring, off, tile, col, row = p, o, t, baseCol + dx, baseRow + dy end
                end
            end
        end
    end
    local pier
    if not ring or off > 0 then
        local t, x, y, p, o = PierRoot(c, spot)
        if t then tile, col, row, ring, off, pier = t, x, y, p, o, true end
    end
    if not ring then return false end
    local x, y, origin = spot.x, spot.y, nil
    local sx, sy = TileOf(spot.x, spot.y)
    if pier or sx ~= col or sy ~= row then x, y, origin = tile.midX[ring], tile.midY[ring], { spot.x, spot.y } end
    local inTile, inTileFrom = SpreadInTile(tile, ring, off)
    local seeds = {}
    for _, gate in ipairs(tile.gates) do
        local yards = inTile[gate[2]]
        if yards then
            local dx, dy = web.nodeX[gate[1]] - tile.midX[gate[2]], web.nodeY[gate[1]] - tile.midY[gate[2]]
            seeds[gate[1]] = yards + sqrt(dx * dx + dy * dy)
        end
    end
    local outward, outwardFrom = SearchGraph(web, seeds)
    return { c = c, col = col, row = row, ring = ring, x = x, y = y, origin = origin, inTile = inTile, inTileFrom = inTileFrom, outward = outward, outwardFrom = outwardFrom }
end

local function ReachToPlace(reach, places, i)
    local r = places.reachOf[i]
    if not r or not r[1] then return nil end
    local best
    if r[1] == reach.col and r[2] == reach.row then best = reach.inTile[r[3]] end
    for k = 4, #r, 2 do
        local outward = reach.outward[r[k]]
        if outward and (not best or outward + r[k + 1] < best) then best = outward + r[k + 1] end
    end
    return best
end

-- Yards between two reaches, and the gateId of b's tile it comes in by
-- (nil: straight beside their shared tile).
local function ReachToReach(a, b)
    local best = a.col == b.col and a.row == b.row and a.inTile[b.ring] or nil
    local via
    local tile = Tile(b.c, b.col, b.row)
    local web = Graph(b.c)
    for _, gate in ipairs(tile.gates) do
        local outward, back = a.outward[gate[1]], b.inTile[gate[2]]
        if outward and back then
            local dx, dy = web.nodeX[gate[1]] - tile.midX[gate[2]], web.nodeY[gate[1]] - tile.midY[gate[2]]
            local total = outward + back + sqrt(dx * dx + dy * dy)
            if not best or total < best then best, via = total, gate[1] end
        end
    end
    return best, via
end

-- Yards walked between a and b on continent c; each is a travel place key
-- or a reach. false: no walk; nil: the maps cannot say.
function Walking.Yards(c, a, b)
    if not Walking.Ready() then return nil end
    local places = Places(c)
    if type(a) == "string" and type(b) == "string" then
        local i, j = places and places.index[a], places and places.index[b]
        if not i or not j or not places.reachOf[i][1] or not places.reachOf[j][1] then return nil end
        local yards = places.between[(i - 1) * places.count + j]
        return yards >= 0 and yards or false
    end
    if type(a) == "string" then a, b = b, a end
    if type(b) == "string" then
        local i = places and places.index[b]
        if not i or not places.reachOf[i][1] then return nil end
        return ReachToPlace(a, places, i) or false
    end
    return ReachToReach(a, b) or false
end

-------------------------------------------------------------------------------
--  Paths
-------------------------------------------------------------------------------
local function Cross2(ax, ay, bx, by, baseCol, baseRow) return (baseCol - ax) * (by - ay) - (bx - ax) * (baseRow - ay) end

-- The side polygon p shares with q, as left and right ends seen going p to q.
local function Doorway(tile, p, q)
    local ring = tile.rings[p]
    for k = 1, #ring do
        if tile.beside[p][k] == q then
            local a, b = ring[k], ring[k % #ring + 1]
            local ax, ay, bx, by = tile.xs[a], tile.ys[a], tile.xs[b], tile.ys[b]
            if Cross2(tile.midX[p], tile.midY[p], tile.midX[q], tile.midY[q], ax, ay) > 0 then ax, ay, bx, by = bx, by, ax, ay end
            return ax, ay, bx, by
        end
    end
end

-- Simple stupid funnel: the tightest line through the doorways.
local function PullTight(leftXs, leftYs, rightXs, rightYs, out)
    local n = #leftXs
    local apexX, apexY = leftXs[1], leftYs[1]
    local leftX, leftY, rightX, rightY = leftXs[1], leftYs[1], rightXs[1], rightYs[1]
    local leftAt, rightAt = 1, 1
    local i = 2
    while i <= n do
        local nlx, nly, nrx, nry = leftXs[i], leftYs[i], rightXs[i], rightYs[i]
        local restarted = false
        if Cross2(apexX, apexY, rightX, rightY, nrx, nry) <= 0 then
            if (apexX == rightX and apexY == rightY) or Cross2(apexX, apexY, leftX, leftY, nrx, nry) > 0 then
                rightX, rightY, rightAt = nrx, nry, i
            else
                out[#out + 1], out[#out + 2] = leftX, leftY
                apexX, apexY = leftX, leftY
                rightX, rightY, rightAt = apexX, apexY, leftAt
                i, restarted = leftAt + 1, true
            end
        end
        if not restarted and Cross2(apexX, apexY, leftX, leftY, nlx, nly) >= 0 then
            if (apexX == leftX and apexY == leftY) or Cross2(apexX, apexY, rightX, rightY, nlx, nly) < 0 then
                leftX, leftY, leftAt = nlx, nly, i
            else
                out[#out + 1], out[#out + 2] = rightX, rightY
                apexX, apexY = rightX, rightY
                leftX, leftY, leftAt = apexX, apexY, rightAt
                i, restarted = rightAt + 1, true
            end
        end
        if not restarted then i = i + 1 end
    end
    out[#out + 1], out[#out + 2] = leftXs[n], leftYs[n]
end

-- Corners from (fromX, fromY) on fromPoly to (toX, toY) on toPoly, one tile.
local function TileCorners(tile, fromPoly, fromX, fromY, toPoly, toX, toY, out)
    local _, cameFrom = SpreadInTile(tile, fromPoly, 0)
    local route, p = {}, toPoly
    while p and p ~= fromPoly do
        table.insert(route, 1, p)
        p = cameFrom[p]
    end
    if not p then return false end
    table.insert(route, 1, fromPoly)
    local leftXs, leftYs, rightXs, rightYs = { fromX }, { fromY }, { fromX }, { fromY }
    for k = 1, #route - 1 do
        local ax, ay, bx, by = Doorway(tile, route[k], route[k + 1])
        leftXs[#leftXs + 1], leftYs[#leftYs + 1], rightXs[#rightXs + 1], rightYs[#rightYs + 1] = ax, ay, bx, by
    end
    leftXs[#leftXs + 1], leftYs[#leftYs + 1], rightXs[#rightXs + 1], rightYs[#rightYs + 1] = toX, toY, toX, toY
    PullTight(leftXs, leftYs, rightXs, rightYs, out)
    return true
end

local function CrossingPolygon(tile, gateId)
    for _, gate in ipairs(tile.gates) do
        if gate[1] == gateId then return gate[2] end
    end
end

-- How outward (x, y) is inside side k of polygon p (negative: outside).
local function Inside(tile, p, k, x, y)
    local ring = tile.rings[p]
    local i, j = ring[k], ring[k % #ring + 1]
    local ax, ay, bx, by = tile.xs[i], tile.ys[i], tile.xs[j], tile.ys[j]
    local d = Cross2(ax, ay, bx, by, x, y) / sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
    if Cross2(ax, ay, bx, by, tile.midX[p], tile.midY[p]) < 0 then d = -d end
    return d, ax, ay, bx, by
end

local function OnPolygon(tile, p, x, y)
    for k = 1, #tile.rings[p] do
        if Inside(tile, p, k, x, y) < -ON_EDGE then return false end
    end
    return true
end

-- Where a line from (sx, sy) to (ex, ey) leaves polygon p, past t = after.
local function LeavesBy(tile, p, sx, sy, ex, ey, after)
    local dx, dy = ex - sx, ey - sy
    local side, at, out
    for k = 1, #tile.rings[p] do
        local d, ax, ay, bx, by = Inside(tile, p, k, ex, ey)
        if d < -ON_EDGE then
            out = true
            local denom = dx * (by - ay) - dy * (bx - ax)
            if denom ~= 0 then
                local t = ((ax - sx) * (by - ay) - (ay - sy) * (bx - ax)) / denom
                if t >= after - RAY_SLACK and (not at or t < at) then side, at = k, t end
            end
        end
    end
    return out, side, at
end

local function PolygonAround(tile, p, x, y)
    local best, bestRise
    for q = 1, #tile.rings do
        if q ~= p and OnPolygon(tile, q, x, y) then
            local rise = abs(tile.midZ[q] - tile.midZ[p])
            if not best or rise < bestRise then best, bestRise = q, rise end
        end
    end
    return best
end

-- Whether a straight line stays on the walking map (never changing level,
-- and off water unless wet). Returns the tile, col, row, polygon it ends on.
local function StaysOnMap(c, tile, col, row, p, sx, sy, ex, ey, wet)
    local length = sqrt((ex - sx) ^ 2 + (ey - sy) ^ 2)
    if length == 0 then return tile, col, row, p end
    local ux, uy = (ex - sx) / length, (ey - sy) / length
    local after, nudged = 0, false
    for _ = 1, RAY_STEPS do
        if not wet and tile.ground and tile.ground[p] ~= LAND then return nil end
        local out, k, t = LeavesBy(tile, p, sx, sy, ex, ey, after)
        if not out then return tile, col, row, p end
        if not k then return nil end
        local q = tile.beside[p][k]
        local list = not q and tile.seams[p * MAX_SIDES + k - 1]
        if not q and not list and not nudged and t * length < NUDGE then
            q = PolygonAround(tile, p, sx + ux * NUDGE, sy + uy * NUDGE)
            nudged = true
            t = after
        end
        after = t
        if q then
            p = q
        else
            if not list then return nil end
            local x, y = sx + (ex - sx) * t, sy + (ey - sy) * t
            local found
            for i = 1, #list, 3 do
                local nextTile = Tile(c, col + list[i], row + list[i + 1])
                if nextTile and OnPolygon(nextTile, list[i + 2], x - list[i + 1] * NUDGE, y - list[i] * NUDGE) then
                    tile, col, row, p, found = nextTile, col + list[i], row + list[i + 1], list[i + 2], true
                    break
                end
            end
            if not found then return nil end
        end
    end
end

-- Drops every corner a straight line can skip.
local function CutCorners(a, points, from)
    local out = {}
    for i = 1, from + 1 do
        out[i] = points[i]
    end
    local tile, col, row, p = Tile(a.c, a.col, a.row), a.col, a.row, a.ring
    local last = #points - 1
    local i = from
    while i < last do
        local farthest, farTile, farCol, farRow, farRing
        for j = i + 2, last, 2 do
            local tile2, col2, row2, ring2 = StaysOnMap(a.c, tile, col, row, p, points[i], points[i + 1], points[j], points[j + 1], j == i + 2)
            Slice()
            if not tile2 then break end
            farthest, farTile, farCol, farRow, farRing = j, tile2, col2, row2, ring2
        end
        if not farthest then
            for k = i + 2, #points do
                out[#out + 1] = points[k]
            end
            return out
        end
        out[#out + 1], out[#out + 2] = points[farthest], points[farthest + 1]
        tile, col, row, p, i = farTile, farCol, farRow, farRing, farthest
    end
    return out
end

local function WithEnd(b, out)
    if b.origin then out[#out + 1], out[#out + 2] = b.origin[1], b.origin[2] end
    return out
end

-- The corners { x1, y1, x2, y2, ... } of the walk from reach a to reach b,
-- both ends included, or nil.
function Walking.Corners(a, b)
    local _, via = ReachToReach(a, b)
    local out = a.origin and { a.origin[1], a.origin[2], a.x, a.y } or { a.x, a.y }
    local firstCorner = #out - 1
    if not via then
        if a.col ~= b.col or a.row ~= b.row or not a.inTile[b.ring] then return nil end
        local tile = Tile(a.c, a.col, a.row)
        return TileCorners(tile, a.ring, a.x, a.y, b.ring, b.x, b.y, out) and WithEnd(b, CutCorners(a, out, firstCorner)) or nil
    end
    local web = Graph(a.c)
    local route, gateId = {}, via
    while gateId do
        table.insert(route, 1, gateId)
        gateId = a.outwardFrom[gateId]
    end
    local col, row = a.col, a.row
    local tile = Tile(a.c, col, row)
    local fromPoly, fromX, fromY = a.ring, a.x, a.y
    for k = 1, #route do
        local id = route[k]
        local toPoly = CrossingPolygon(tile, id)
        if not toPoly or not TileCorners(tile, fromPoly, fromX, fromY, toPoly, web.nodeX[id], web.nodeY[id], out) then return nil end
        fromPoly = nil
        for _, step in ipairs(NEIGHBOUR_TILES) do
            local nextTile = Tile(a.c, col + step[1], row + step[2])
            local ring = nextTile and CrossingPolygon(nextTile, id)
            if ring then
                tile, fromPoly, col, row = nextTile, ring, col + step[1], row + step[2]
                break
            end
        end
        if not fromPoly then return nil end
        fromX, fromY = web.nodeX[id], web.nodeY[id]
    end
    if not TileCorners(tile, fromPoly, fromX, fromY, b.ring, b.x, b.y, out) then return nil end
    return WithEnd(b, CutCorners(a, out, firstCorner))
end

-- For a scenario: forget whether the data loaded.
function Walking.Reset()
    loaded, data = nil, nil
    wipe(tileCache)
    wipe(tileUsed)
    wipe(graphCache)
    wipe(placeCache)
end
