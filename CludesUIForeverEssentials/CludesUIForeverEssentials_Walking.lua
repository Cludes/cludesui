if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
if not (CUI and CUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_Walking.lua  (WoW Forever only)
--  Walking costs and paths for Journeys, over the walking maps in the
--  load-on-demand CludesUIJourneysData addon (loaded the first time a
--  journey needs them, never in combat).
--
--  The maps, per continent, in world yards (x north, y west):
--    tiles["tx_ty"]  a 533 yard square of walkable polygons: v vertices
--                    (delta coded x, y, z), p polygons (vertex count then
--                    delta coded indices), a each polygon's ground (0 land,
--                    1 water, 2 sea), x { crossing, polygon } pairs where
--                    the tile meets the continent graph, l links across a
--                    tile side { polygon, side, dtx, dty, polygon there }
--    graph           c crossings (x, y, z), e edges (a, b, yards)
--    walks           k the travel places ("f2" flight, "s3.1" dock, "l1.2"
--                    link end), d yards between each pair (-1: no walk),
--                    r each place's reach { tx, ty, polygon, crossing,
--                    yards, crossing, yards, ... }
--  Each is CBOR, deflated, in Base64, decoded when first needed; at most
--  TILE_CACHE tiles stay decoded, and everything is let go after a minute
--  unused.
--
--  A walk from a spot: the cheapest way to every polygon of its tile
--  (Dijkstra over polygon neighbours, water and sea cost more), then on to
--  every crossing of the continent graph. Between two spots: the best
--  crossing of the far end's tile, or straight across a shared tile. The
--  path is the crossings passed, each tile's polygons between them pulled
--  tight (funnel), then corners cut wherever a straight line stays on land.
--  Searches pause when they use up their slice of a frame (Slice) inside a
--  coroutine; Journeys drives them across frames.
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
-- For each polygon side, the polygon across it (shared vertex pair).
local function LinkSides(polys)
    local firstOwner, across = {}, {}
    for p = 1, #polys do
        local poly, row = polys[p], {}
        across[p] = row
        for k = 1, #poly do
            local a, b = poly[k], poly[k % #poly + 1]
            local key = a < b and a * EDGE_KEY + b or b * EDGE_KEY + a
            local owner = firstOwner[key]
            if owner then
                local q = floor(owner / MAX_SIDES)
                row[k] = q
                across[q][owner % MAX_SIDES + 1] = p
            else
                firstOwner[key] = p * MAX_SIDES + k - 1
            end
        end
    end
    return across
end

local function BuildTile(tx, ty, raw)
    local baseX, baseY = GRID_ORIGIN - ty * TILE_YARDS, GRID_ORIGIN - tx * TILE_YARDS
    local vx, vy, vz = {}, {}, {}
    local ax, ay, az = 0, 0, 0
    local verts = raw.v
    for i = 1, #verts, 3 do
        ax, ay, az = ax + verts[i], ay + verts[i + 1], az + verts[i + 2]
        local n = #vx + 1
        vx[n], vy[n], vz[n] = baseX - ax, baseY - ay, az
    end
    local polys, packed, index, i = {}, raw.p, 0, 1
    while i <= #packed do
        local poly = {}
        for k = 1, packed[i] do
            index = index + packed[i + k]
            poly[k] = index
        end
        i = i + packed[i] + 1
        polys[#polys + 1] = poly
    end
    local mx, my, mz = {}, {}, {}
    for n = 1, #polys do
        local poly, sx, sy, sz = polys[n], 0, 0, 0
        for k = 1, #poly do
            sx, sy, sz = sx + vx[poly[k]], sy + vy[poly[k]], sz + vz[poly[k]]
        end
        mx[n], my[n], mz[n] = sx / #poly, sy / #poly, sz / #poly
    end
    local crossings = {}
    local x = raw.x or {}
    for k = 1, #x, 2 do
        crossings[#crossings + 1] = { x[k], x[k + 1] }
    end
    local bridges = {}
    local l = raw.l or {}
    for k = 1, #l, 5 do
        local key = l[k] * MAX_SIDES + l[k + 1] - 1
        local list = bridges[key] or {}
        bridges[key] = list
        list[#list + 1], list[#list + 2], list[#list + 3] = l[k + 2], l[k + 3], l[k + 4]
    end
    return {
        vx = vx, vy = vy, vz = vz, polys = polys, across = LinkSides(polys),
        mx = mx, my = my, mz = mz, ground = raw.a, crossings = crossings, bridges = bridges,
    }
end

local function DropOldestTile()
    local oldest, oldestKey = huge, nil
    for key, at in pairs(tileUsed) do
        if at < oldest then oldest, oldestKey = at, key end
    end
    if oldestKey then tileCache[oldestKey], tileUsed[oldestKey] = nil, nil end
end

local function Tile(c, tx, ty)
    if not Walking.Ready() then return nil end
    local key = c .. ":" .. tx .. ":" .. ty
    local tile = tileCache[key]
    if tile == nil then
        local all = data.tiles[c]
        local packed = all and all[tx .. "_" .. ty]
        local raw = packed and Unpack(packed)
        tile = raw and BuildTile(tx, ty, raw) or false
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

local function InPolygon(tile, poly, x, y)
    local vx, vy = tile.vx, tile.vy
    local inside = false
    local j = poly[#poly]
    for k = 1, #poly do
        local i = poly[k]
        if (vy[i] > y) ~= (vy[j] > y) and x < (vx[j] - vx[i]) * (y - vy[i]) / (vy[j] - vy[i]) + vx[i] then inside = not inside end
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
    for p = 1, #tile.polys do
        local dx, dy = tile.mx[p] - x, tile.my[p] - y
        local flat = sqrt(dx * dx + dy * dy)
        local on = InPolygon(tile, tile.polys[p], x, y)
        local rise = z and abs(tile.mz[p] - z) or 0
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
    local poly = tile and StandOn(tile, spot.x, spot.y, spot.z)
    return poly ~= nil and not (tile.ground and tile.ground[poly] == SEA)
end

-------------------------------------------------------------------------------
--  Searches
-------------------------------------------------------------------------------
local function HeapPush(heap, cost, node)
    local n = #heap + 1
    heap[n] = node
    while n > 1 do
        local up = floor(n / 2)
        if cost[heap[up]] <= cost[heap[n]] then break end
        heap[up], heap[n] = heap[n], heap[up]
        n = up
    end
end

local function HeapPop(heap, cost)
    local top, n = heap[1], #heap
    heap[1] = heap[n]
    heap[n] = nil
    n = n - 1
    local i = 1
    while true do
        local l, r, m = 2 * i, 2 * i + 1, i
        if l <= n and cost[heap[l]] < cost[heap[m]] then m = l end
        if r <= n and cost[heap[r]] < cost[heap[m]] then m = r end
        if m == i then break end
        heap[m], heap[i] = heap[i], heap[m]
        i = m
    end
    return top
end

local function SideMiddle(tile, p, k)
    local poly = tile.polys[p]
    local a, b = poly[k], poly[k % #poly + 1]
    return (tile.vx[a] + tile.vx[b]) / 2, (tile.vy[a] + tile.vy[b]) / 2, (tile.vz[a] + tile.vz[b]) / 2
end

local function ToMiddle(tile, p, x, y, z)
    local dx, dy, dz = tile.mx[p] - x, tile.my[p] - y, tile.mz[p] - z
    local rate = tile.ground and GROUND_COST[tile.ground[p]] or 1
    return sqrt(dx * dx + dy * dy + dz * dz) * rate
end

-- The cheapest way from polygon `from` (starting at `extra` yards) to every
-- polygon of the tile: cost[p], prev[p].
local function SpreadInTile(tile, from, extra)
    local cost, done, heap, prev = { [from] = extra }, {}, { from }, {}
    while #heap > 0 do
        local p = HeapPop(heap, cost)
        if not done[p] then
            done[p] = true
            local across = tile.across[p]
            for k = 1, #tile.polys[p] do
                local q = across[k]
                if q and not done[q] then
                    local sx, sy, sz = SideMiddle(tile, p, k)
                    local c = cost[p] + ToMiddle(tile, p, sx, sy, sz) + ToMiddle(tile, q, sx, sy, sz)
                    if c < (cost[q] or huge) then
                        cost[q], prev[q] = c, p
                        HeapPush(heap, cost, q)
                    end
                end
            end
            Slice()
        end
    end
    return cost, prev
end

local function Graph(c)
    Touch()
    local g = graphCache[c]
    if g == nil then
        local packed = data.graph[c]
        g = false
        local raw = packed and Unpack(packed)
        if raw then
            local cs, es, px, py, pz, adj = raw.c, raw.e, {}, {}, {}, {}
            for i = 1, #cs, 3 do
                local n = #px + 1
                px[n], py[n], pz[n], adj[n] = cs[i], cs[i + 1], cs[i + 2], {}
            end
            for i = 1, #es, 3 do
                local a, b, yards = es[i], es[i + 1], es[i + 2]
                local la, lb = adj[a], adj[b]
                la[#la + 1], la[#la + 2] = b, yards
                lb[#lb + 1], lb[#lb + 2] = a, yards
            end
            g = { px = px, py = py, pz = pz, adj = adj }
        end
        graphCache[c] = g
    end
    return g or nil
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
            places = { index = index, count = #raw.k, yards = raw.d, reach = raw.r }
        end
        placeCache[c] = places
    end
    return places or nil
end

-- Every crossing's cost from the seeds { [crossing] = yards }.
local function SearchGraph(g, seeds)
    local cost, done, heap, prev = {}, {}, {}, {}
    for crossing, yards in pairs(seeds) do
        cost[crossing] = yards
        HeapPush(heap, cost, crossing)
    end
    while #heap > 0 do
        local a = HeapPop(heap, cost)
        if not done[a] then
            done[a] = true
            local list = g.adj[a]
            for i = 1, #list, 2 do
                local b = list[i]
                local yards = cost[a] + list[i + 1]
                if not done[b] and yards < (cost[b] or huge) then
                    cost[b], prev[b] = yards, a
                    HeapPush(heap, cost, b)
                end
            end
            Slice()
        end
    end
    return cost, prev
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
                local root = at and places.reach[at]
                local tile = root and root[1] and Tile(c, root[1], root[2])
                if tile then
                    local rx, ry = tile.mx[root[3]], tile.my[root[3]]
                    local span = sqrt((dock[2] - rx) ^ 2 + (dock[3] - ry) ^ 2)
                    local toRoot = sqrt((spot.x - rx) ^ 2 + (spot.y - ry) ^ 2)
                    local toDock = sqrt((spot.x - dock[2]) ^ 2 + (spot.y - dock[3]) ^ 2)
                    if toDock + toRoot <= span + PIER_WIDTH then return tile, root[1], root[2], root[3], toRoot end
                end
            end
        end
    end
end

-- A spot's reach: its tile, polygon, costs to its tile's polygons (near)
-- and to every crossing (far). nil where there is no walking data, false
-- where the spot is off it (the sea, past a pier).
function Walking.Reach(spot)
    if not Walking.Ready() then return nil end
    local c = spot.c
    local g = Graph(c)
    if not g then return nil end
    local tx, ty = TileOf(spot.x, spot.y)
    local tile = Tile(c, tx, ty)
    local poly, off
    if tile then poly, off = StandOn(tile, spot.x, spot.y, spot.z, true) end
    if not poly then
        local cx, cy = tx, ty
        for dx = -1, 1 do
            for dy = -1, 1 do
                local t = Tile(c, cx + dx, cy + dy)
                if t then
                    local p, o = StandOn(t, spot.x, spot.y, spot.z, true)
                    if p and (not poly or o < off) then poly, off, tile, tx, ty = p, o, t, cx + dx, cy + dy end
                end
            end
        end
    end
    local pier
    if not poly or off > 0 then
        local t, x, y, p, o = PierRoot(c, spot)
        if t then tile, tx, ty, poly, off, pier = t, x, y, p, o, true end
    end
    if not poly then return false end
    local x, y, start = spot.x, spot.y, nil
    local sx, sy = TileOf(spot.x, spot.y)
    if pier or sx ~= tx or sy ~= ty then x, y, start = tile.mx[poly], tile.my[poly], { spot.x, spot.y } end
    local near, nearPrev = SpreadInTile(tile, poly, off)
    local seeds = {}
    for _, cross in ipairs(tile.crossings) do
        local yards = near[cross[2]]
        if yards then
            local dx, dy = g.px[cross[1]] - tile.mx[cross[2]], g.py[cross[1]] - tile.my[cross[2]]
            seeds[cross[1]] = yards + sqrt(dx * dx + dy * dy)
        end
    end
    local far, farPrev = SearchGraph(g, seeds)
    return { c = c, tx = tx, ty = ty, poly = poly, x = x, y = y, start = start, near = near, nearPrev = nearPrev, far = far, farPrev = farPrev }
end

local function ReachToPlace(reach, places, i)
    local r = places.reach[i]
    if not r or not r[1] then return nil end
    local best
    if r[1] == reach.tx and r[2] == reach.ty then best = reach.near[r[3]] end
    for k = 4, #r, 2 do
        local far = reach.far[r[k]]
        if far and (not best or far + r[k + 1] < best) then best = far + r[k + 1] end
    end
    return best
end

-- Yards between two reaches, and the crossing of b's tile it comes in by
-- (nil: straight across their shared tile).
local function ReachToReach(a, b)
    local best = a.tx == b.tx and a.ty == b.ty and a.near[b.poly] or nil
    local via
    local tile = Tile(b.c, b.tx, b.ty)
    local g = Graph(b.c)
    for _, cross in ipairs(tile.crossings) do
        local far, back = a.far[cross[1]], b.near[cross[2]]
        if far and back then
            local dx, dy = g.px[cross[1]] - tile.mx[cross[2]], g.py[cross[1]] - tile.my[cross[2]]
            local total = far + back + sqrt(dx * dx + dy * dy)
            if not best or total < best then best, via = total, cross[1] end
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
        if not i or not j or not places.reach[i][1] or not places.reach[j][1] then return nil end
        local yards = places.yards[(i - 1) * places.count + j]
        return yards >= 0 and yards or false
    end
    if type(a) == "string" then a, b = b, a end
    if type(b) == "string" then
        local i = places and places.index[b]
        if not i or not places.reach[i][1] then return nil end
        return ReachToPlace(a, places, i) or false
    end
    return ReachToReach(a, b) or false
end

-------------------------------------------------------------------------------
--  Paths
-------------------------------------------------------------------------------
local function Cross2(ax, ay, bx, by, cx, cy) return (cx - ax) * (by - ay) - (bx - ax) * (cy - ay) end

-- The side polygon p shares with q, as left and right ends seen going p to q.
local function Doorway(tile, p, q)
    local poly = tile.polys[p]
    for k = 1, #poly do
        if tile.across[p][k] == q then
            local a, b = poly[k], poly[k % #poly + 1]
            local ax, ay, bx, by = tile.vx[a], tile.vy[a], tile.vx[b], tile.vy[b]
            if Cross2(tile.mx[p], tile.my[p], tile.mx[q], tile.my[q], ax, ay) > 0 then ax, ay, bx, by = bx, by, ax, ay end
            return ax, ay, bx, by
        end
    end
end

-- Simple stupid funnel: the tightest line through the doorways.
local function PullTight(lx, ly, rx, ry, out)
    local n = #lx
    local apexX, apexY = lx[1], ly[1]
    local leftX, leftY, rightX, rightY = lx[1], ly[1], rx[1], ry[1]
    local leftAt, rightAt = 1, 1
    local i = 2
    while i <= n do
        local nlx, nly, nrx, nry = lx[i], ly[i], rx[i], ry[i]
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
    out[#out + 1], out[#out + 2] = lx[n], ly[n]
end

-- Corners from (fromX, fromY) on fromPoly to (toX, toY) on toPoly, one tile.
local function TileCorners(tile, fromPoly, fromX, fromY, toPoly, toX, toY, out)
    local _, prev = SpreadInTile(tile, fromPoly, 0)
    local chain, p = {}, toPoly
    while p and p ~= fromPoly do
        table.insert(chain, 1, p)
        p = prev[p]
    end
    if not p then return false end
    table.insert(chain, 1, fromPoly)
    local lx, ly, rx, ry = { fromX }, { fromY }, { fromX }, { fromY }
    for k = 1, #chain - 1 do
        local ax, ay, bx, by = Doorway(tile, chain[k], chain[k + 1])
        lx[#lx + 1], ly[#ly + 1], rx[#rx + 1], ry[#ry + 1] = ax, ay, bx, by
    end
    lx[#lx + 1], ly[#ly + 1], rx[#rx + 1], ry[#ry + 1] = toX, toY, toX, toY
    PullTight(lx, ly, rx, ry, out)
    return true
end

local function CrossingPolygon(tile, crossing)
    for _, cross in ipairs(tile.crossings) do
        if cross[1] == crossing then return cross[2] end
    end
end

-- How far (x, y) is inside side k of polygon p (negative: outside).
local function Inside(tile, p, k, x, y)
    local poly = tile.polys[p]
    local i, j = poly[k], poly[k % #poly + 1]
    local ax, ay, bx, by = tile.vx[i], tile.vy[i], tile.vx[j], tile.vy[j]
    local d = Cross2(ax, ay, bx, by, x, y) / sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
    if Cross2(ax, ay, bx, by, tile.mx[p], tile.my[p]) < 0 then d = -d end
    return d, ax, ay, bx, by
end

local function OnPolygon(tile, p, x, y)
    for k = 1, #tile.polys[p] do
        if Inside(tile, p, k, x, y) < -ON_EDGE then return false end
    end
    return true
end

-- Where a line from (sx, sy) to (ex, ey) leaves polygon p, past t = after.
local function LeavesBy(tile, p, sx, sy, ex, ey, after)
    local dx, dy = ex - sx, ey - sy
    local side, at, out
    for k = 1, #tile.polys[p] do
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
    for q = 1, #tile.polys do
        if q ~= p and OnPolygon(tile, q, x, y) then
            local rise = abs(tile.mz[q] - tile.mz[p])
            if not best or rise < bestRise then best, bestRise = q, rise end
        end
    end
    return best
end

-- Whether a straight line stays on the walking map (never changing level,
-- and off water unless wet). Returns the tile, tx, ty, polygon it ends on.
local function StaysOnMap(c, tile, tx, ty, p, sx, sy, ex, ey, wet)
    local length = sqrt((ex - sx) ^ 2 + (ey - sy) ^ 2)
    if length == 0 then return tile, tx, ty, p end
    local ux, uy = (ex - sx) / length, (ey - sy) / length
    local after, nudged = 0, false
    for _ = 1, RAY_STEPS do
        if not wet and tile.ground and tile.ground[p] ~= LAND then return nil end
        local out, k, t = LeavesBy(tile, p, sx, sy, ex, ey, after)
        if not out then return tile, tx, ty, p end
        if not k then return nil end
        local q = tile.across[p][k]
        local list = not q and tile.bridges[p * MAX_SIDES + k - 1]
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
                local nextTile = Tile(c, tx + list[i], ty + list[i + 1])
                if nextTile and OnPolygon(nextTile, list[i + 2], x - list[i + 1] * NUDGE, y - list[i] * NUDGE) then
                    tile, tx, ty, p, found = nextTile, tx + list[i], ty + list[i + 1], list[i + 2], true
                    break
                end
            end
            if not found then return nil end
        end
    end
end

-- Drops every corner a straight line can skip.
local function CutCorners(a, points, start)
    local out = {}
    for i = 1, start + 1 do
        out[i] = points[i]
    end
    local tile, tx, ty, p = Tile(a.c, a.tx, a.ty), a.tx, a.ty, a.poly
    local last = #points - 1
    local i = start
    while i < last do
        local reached, rTile, rtx, rty, rp
        for j = i + 2, last, 2 do
            local t2, tx2, ty2, p2 = StaysOnMap(a.c, tile, tx, ty, p, points[i], points[i + 1], points[j], points[j + 1], j == i + 2)
            Slice()
            if not t2 then break end
            reached, rTile, rtx, rty, rp = j, t2, tx2, ty2, p2
        end
        if not reached then
            for k = i + 2, #points do
                out[#out + 1] = points[k]
            end
            return out
        end
        out[#out + 1], out[#out + 2] = points[reached], points[reached + 1]
        tile, tx, ty, p, i = rTile, rtx, rty, rp, reached
    end
    return out
end

local function WithEnd(b, out)
    if b.start then out[#out + 1], out[#out + 2] = b.start[1], b.start[2] end
    return out
end

-- The corners { x1, y1, x2, y2, ... } of the walk from reach a to reach b,
-- both ends included, or nil.
function Walking.Corners(a, b)
    local _, via = ReachToReach(a, b)
    local out = a.start and { a.start[1], a.start[2], a.x, a.y } or { a.x, a.y }
    local first = #out - 1
    if not via then
        if a.tx ~= b.tx or a.ty ~= b.ty or not a.near[b.poly] then return nil end
        local tile = Tile(a.c, a.tx, a.ty)
        return TileCorners(tile, a.poly, a.x, a.y, b.poly, b.x, b.y, out) and WithEnd(b, CutCorners(a, out, first)) or nil
    end
    local g = Graph(a.c)
    local chain, crossing = {}, via
    while crossing do
        table.insert(chain, 1, crossing)
        crossing = a.farPrev[crossing]
    end
    local tx, ty = a.tx, a.ty
    local tile = Tile(a.c, tx, ty)
    local fromPoly, fromX, fromY = a.poly, a.x, a.y
    for k = 1, #chain do
        local id = chain[k]
        local toPoly = CrossingPolygon(tile, id)
        if not toPoly or not TileCorners(tile, fromPoly, fromX, fromY, toPoly, g.px[id], g.py[id], out) then return nil end
        fromPoly = nil
        for _, step in ipairs(NEIGHBOUR_TILES) do
            local nextTile = Tile(a.c, tx + step[1], ty + step[2])
            local poly = nextTile and CrossingPolygon(nextTile, id)
            if poly then
                tile, fromPoly, tx, ty = nextTile, poly, tx + step[1], ty + step[2]
                break
            end
        end
        if not fromPoly then return nil end
        fromX, fromY = g.px[id], g.py[id]
    end
    if not TileCorners(tile, fromPoly, fromX, fromY, b.poly, b.x, b.y, out) then return nil end
    return WithEnd(b, CutCorners(a, out, first))
end

-- For a scenario: forget whether the data loaded.
function Walking.Reset()
    loaded, data = nil, nil
    wipe(tileCache)
    wipe(tileUsed)
    wipe(graphCache)
    wipe(placeCache)
end
