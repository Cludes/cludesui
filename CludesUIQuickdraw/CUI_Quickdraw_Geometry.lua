if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_Quickdraw_Geometry.lua
--
--  Claim boxes (nest bounding box, corridor, carve, holes, AddRegion),
--  ChildGeom, the arc geometry and the fan layout.
--  Reads the earlier Quickdraw files through ns and ns._qdInternals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._qdInternals
-- CludesUIQuickdraw.lua or an earlier Quickdraw file failed to load.
if not Inner or Inner.broken then return end
Inner.broken = true

local floor, min, max, abs = math.floor, math.min, math.max, math.abs
local sin, cos, tan, pi = math.sin, math.cos, math.tan, math.pi
local log = math.log

local ChildIndex, ChildSlots, MAX_CHILD_ROWS = Inner.ChildIndex, Inner.ChildSlots, Inner.MAX_CHILD_ROWS
local MAX_CHILDREN, MAX_SLOTS = Inner.MAX_CHILDREN, Inner.MAX_SLOTS
local NEST_BAND_DEFAULT, PA, TWO_PI = Inner.NEST_BAND_DEFAULT, Inner.PA, Inner.TWO_PI
local PaletteView, SelectedZoom = Inner.PaletteView, Inner.SelectedZoom

-------------------------------------------------------------------------------
--  A claim's true ground, as a small set of rects rather than one bounding
--  box -- see the "Arming gates" section in CUI_Quickdraw_Gates.lua for what
--  these feed.
--  Shared by both the ARC claims (ChildGeom) and the block-layout ones
--  (CellChildGeom): a nest that breaks out of its parent on one side leaves a
--  bounding box across the two swallowing whatever plain ground of the block
--  sits between them, which is exactly the "dim never backs out" complaint.
--  The true shape is instead the parent's own cell, the nest's own tight box,
--  and a narrow corridor connecting the two -- standing on the block's own
--  ground either side of that corridor is standing outside the nest.
-------------------------------------------------------------------------------

-- Tight bounding box around a set of child boxes, with no parent box folded
-- in -- unlike the old single-rect scheme, this is meant to be paired with a
-- SEPARATE parent box and corridor rather than merged with them.
local function NestBBox(cells)
    local first = cells[1]
    local x0, x1 = first.x - first.hw, first.x + first.hw
    local y0, y1 = first.y - first.hh, first.y + first.hh
    for jdx = 2, #cells do
        local b = cells[jdx]
        x0, x1 = min(x0, b.x - b.hw), max(x1, b.x + b.hw)
        y0, y1 = min(y0, b.y - b.hh), max(y1, b.y + b.hh)
    end
    return {
        x = (x0 + x1) * 0.5,
        y = (y0 + y1) * 0.5,
        hw = (x1 - x0) * 0.5,
        hh = (y1 - y0) * 0.5,
    }
end

-- The rect connecting a claim's parent box to its nest box, that lets
-- crossing the gap between them count as staying on the claim's own ground.
-- axis is the axis the nest's own cells spread ALONG -- every style that
-- hangs its nest off one side of the parent already tags its claim with
-- this, the same convention HaloNest opts out of by setting neither axis nor
-- sign. The corridor runs along the OTHER axis, in the direction sign says
-- the nest lies.
--
-- As WIDE as the wider of the parent cell or the nest box, not one child
-- cell: a natural diagonal reach from the parent toward the nest's own
-- centre drifts outside a one-cell-wide band long before it arrives, and
-- once LeaveSnippet's true-shape test actually runs (see EnsureGates) that
-- reads as having left the claim -- the nest vanishing mid-reach. minWidth
-- is only a floor, for the degenerate case of a single-cell nest whose box
-- is no wider than the corridor itself would otherwise be.
local function CorridorBox(parentBox, nest, axis, sign, minWidth)
    local along, away = "x", "y"
    local hAlong, hAway = "hw", "hh"
    if axis ~= "X" then
        along, away, hAlong, hAway = "y", "x", "hh", "hw"
    end

    local pEdge = parentBox[away] + sign * parentBox[hAway]
    local nEdge = nest[away] - sign * nest[hAway]
    local lo, hi = min(pEdge, nEdge), max(pEdge, nEdge)

    local box = {}
    box[along] = parentBox[along]
    box[hAlong] = max(minWidth * 0.5, parentBox[hAlong], nest[hAlong])
    box[away], box[hAway] = (lo + hi) * 0.5, max(0, (hi - lo) * 0.5)
    return box
end

-- One rect covering a nest run AND the ground between it and the parent's own
-- cell: the corridor folded into the run rather than standing beside it. That is
-- what lets a run with cells on more than one side of the block have EVERY side
-- of it reachable -- a reach for a child round the far side of a corner leaves
-- the parent cell diagonally, and a claim with one corridor pointing at one side
-- loses the cursor the moment it aims at another -- without spending a region
-- gate per side on the corridors alone.
--
-- The PARENT'S OWN CELL folded in, rather than a corridor drawn between the two:
-- a rect is convex, so a rect holding both ends of a line holds every point of
-- it, and a reach IS a line -- a hand goes straight at the icon it wants. Any
-- corridor narrower than that leaves some straight reach crossing ground the
-- claim does not hold, however carefully it is aimed: a corridor laid across the
-- gap the two boxes leave in ONE direction is exited by a reach that leaves the
-- parent cell through a different edge.
--
-- What it costs is honest: the sweep from the parent's cell out to a run stands
-- over whatever plain entries lie in it -- for a parent in the middle of a block
-- the ones between it and its lane, which the corridor this replaces covered too
-- (that was as wide as the whole nest), and for a parent on the block's own edge
-- the rest of its own row or column, which the corridor did not. Those entries
-- stay exactly as selectable and as firable as they were; what they no longer do
-- is back the nest out. A run reached by a straight line that breaks halfway is
-- worse than a nest that stays up one entry too long: the break does not cancel
-- anything, it fires whatever the cursor came to rest over instead.
--
-- One kind of entry in that sweep IS allowed to back the nest out: another
-- claim's own entry, which the sweep would otherwise make unreachable while this
-- claim is armed -- its parent gate being dark the whole time. Those cells are
-- taken back out afterwards, one at a time; see ParentHoles.
local function RunReach(parentBox, run) return NestBBox({ run, parentBox }) end

-- The overshoot grace, applied to one nest run's own rect. Reaching quickly for
-- a small child icon overruns the run's edge by a few units, and a cursor path
-- sampled once per frame can put a single sample outside it on the way in;
-- either one would otherwise read as having left the claim and vanish the
-- nest mid-reach. A cell's own box is untouched, so this only decides how long the
-- nest STAYS open -- what a release fires still needs the cursor inside a child
-- cell.
--
-- axis and sign are the run's, as ever: the axis its cells spread along and the
-- side of the block it lies on. ALONG the run the grace applies both ways --
-- either end of a run is more run, or empty screen. ACROSS it, only OUTWARD:
-- inward is the block itself, and for a lane hugging it that is a plain entry's
-- own centre less than half an icon away, which a region reaching over would
-- leave unselectable while the nest was up. A nest set a whole band out has the
-- room to spare either way, and nothing wants the inward half of it.
local function GraceBox(box, grace, axis, sign)
    local away, hAway, hAlong = "y", "hh", "hw"
    if axis ~= "X" then
        away, hAway, hAlong = "x", "hw", "hh"
    end
    box[hAlong] = box[hAlong] + grace
    box[away] = box[away] + sign * grace * 0.5
    box[hAway] = box[hAway] + grace * 0.5
    return box
end

-- The carve below works in edges; everything else here works in centre and
-- half-extent.
local function EdgesOf(b) return b.x - b.hw, b.x + b.hw, b.y - b.hh, b.y + b.hh end

local function EdgeBox(x0, x1, y0, y1)
    return {
        x = (x0 + x1) * 0.5,
        y = (y0 + y1) * 0.5,
        hw = (x1 - x0) * 0.5,
        hh = (y1 - y0) * 0.5,
    }
end

local function BoxesMeet(a, b) return abs(a.x - b.x) < a.hw + b.hw and abs(a.y - b.y) < a.hh + b.hh end

local function AnyBoxMeets(b, boxes)
    for jdx = 1, (boxes and #boxes or 0) do
        if BoxesMeet(b, boxes[jdx]) then return true end
    end
    return false
end

-- A piece thinner than this holds nothing a cursor could be inside, and would
-- spend one of the REGION_MAX gate slots a piece that matters needs.
local CARVE_MIN = 1

-- One region rect with ONE other claim's parent cell taken out of it, as up to
-- four pieces appended to `out`.
--
-- Why a hole at all: a claim's region sweeps its parent's own row or column (see
-- RunReach), so while claim A is armed its region stands over claim B's parent
-- cell. B's own parent gate is dark for as long as A is armed, and gliding from
-- A's entry straight onto B's leaves no region of A's -- so no OnLeave runs,
-- nothing disarms, and B cannot be reached at all without leaving the row first.
-- Taking B's cell out of A's coverage puts a real boundary there: the glide
-- leaves an rgate at the hole's edge, LeaveSnippet's geometric re-test answers
-- "outside", and its re-arm hands the claim over.
--
-- splitY says which axis the FULL-WIDTH slabs are cut on, and the caller sets it
-- from the run's own axis so the slab that survives whole is the one holding the
-- run: a hole is always a cell INSIDE the block, and the run lies beyond the
-- block along the region's away axis, so cutting that axis first leaves every
-- child in one piece rather than sliced into per-column strips.
local function CarveBox(result, b, hole, splitY)
    local bx0, bx1, by0, by1 = EdgesOf(b)
    local hx0, hx1, hy0, hy1 = EdgesOf(hole)
    if hx1 <= bx0 or hx0 >= bx1 or hy1 <= by0 or hy0 >= by1 then
        result[#result + 1] = b
        return
    end
    hx0, hx1 = max(hx0, bx0), min(hx1, bx1)
    hy0, hy1 = max(hy0, by0), min(hy1, by1)
    if splitY then
        if hy0 - by0 >= CARVE_MIN then result[#result + 1] = EdgeBox(bx0, bx1, by0, hy0) end
        if by1 - hy1 >= CARVE_MIN then result[#result + 1] = EdgeBox(bx0, bx1, hy1, by1) end
        if hx0 - bx0 >= CARVE_MIN then result[#result + 1] = EdgeBox(bx0, hx0, hy0, hy1) end
        if bx1 - hx1 >= CARVE_MIN then result[#result + 1] = EdgeBox(hx1, bx1, hy0, hy1) end
    else
        if hx0 - bx0 >= CARVE_MIN then result[#result + 1] = EdgeBox(bx0, hx0, by0, by1) end
        if bx1 - hx1 >= CARVE_MIN then result[#result + 1] = EdgeBox(hx1, bx1, by0, by1) end
        if hy0 - by0 >= CARVE_MIN then result[#result + 1] = EdgeBox(hx0, hx1, by0, hy0) end
        if by1 - hy1 >= CARVE_MIN then result[#result + 1] = EdgeBox(hx0, hx1, hy1, by1) end
    end
end

-- A hole pulled back off this claim's OWN children, or nil when there is no
-- hole left worth punching. A child cell that stands over a neighbouring
-- claim's cell has to WIN there -- it is drawn there, and a hole under it would
-- make it unselectable -- but a child that merely grazes the cell must not cost
-- the whole hole: a lane hugs the block so closely that its cells reach back
-- over the outer row's own boxes by half a gap, so every hole a lane wants would
-- otherwise be refused on a sliver.
--
-- Each pass gives away the one side a child has got LEAST far in through, which
-- is the smallest concession that answers that child. What must survive it is
-- the neighbour's own CENTRE: that is where a cursor aimed at the neighbour's
-- icon lands, and the hole exists so that landing there is outside this claim.
local function ClipHole(hole, cells)
    local x0, x1, y0, y1 = EdgesOf(hole)
    -- One side given away per pass, so four passes per child is the most that
    -- can be asked of it -- plus the pass that finds nothing left to answer.
    for _ = 1, 4 * (cells and #cells or 0) + 1 do
        local best, bx0, bx1, by0, by1
        for jdx = 1, (cells and #cells or 0) do
            local qx0, qx1, qy0, qy1 = EdgesOf(cells[jdx])
            if qx1 > x0 and qx0 < x1 and qy1 > y0 and qy0 < y1 then
                local skinData = min(qx1 - x0, x1 - qx0, qy1 - y0, y1 - qy0)
                if not best or skinData < best then
                    best, bx0, bx1, by0, by1 = skinData, qx1, qx0, qy1, qy0
                end
            end
        end
        if not best then
            local hgt = EdgeBox(x0, x1, y0, y1)
            -- The centre, with room around it: a hole clipped down to a line
            -- through the neighbour's icon is not somewhere a hand can land.
            if abs(hgt.x - hole.x) + CARVE_MIN <= hgt.hw and abs(hgt.y - hole.y) + CARVE_MIN <= hgt.hh then
                return hgt
            end
            return nil
        end
        if best == bx0 - x0 then
            x0 = bx0
        elseif best == x1 - bx1 then
            x1 = bx1
        elseif best == by0 - y0 then
            y0 = by0
        else
            y1 = by1
        end
        if x1 - x0 < CARVE_MIN or y1 - y0 < CARVE_MIN then return nil end
    end
    return nil
end

-- Does this hole stand STRAIGHT OUT from the parent, in the direction its own
-- children lie? Then it is the one piece of ground the nest cannot be reached
-- across, and the nest keeps it: a claim whose entry has another claim's entry
-- between it and its own run -- the middle column of a block, all three of them
-- nesting -- would otherwise have every child of its middle nest cut off, the
-- reach handing the claim over before it arrived. The swap in that one direction
-- is what gives way instead, and it is still there the way round the block. A
-- hole to the SIDE of the parent blocks nothing and is carved as normal, which is
-- the case the carve exists for.
--
-- The claim's OWN side only -- groups[1], the nearest one, which PerimeterNest
-- has already sorted to the front -- not every side a long run wrapped onto. The
-- tail of a wrapped run reaches back past the parent's neighbours, and protecting
-- those directions too would leave a block whose neighbouring entries both nest
-- with no hole anywhere and no swap at all. Reaching a wrapped cell out past
-- another claim's entry hands the claim over instead, which is the trade the carve
-- is for; what must not happen is a nest with no way in.
local function BlocksReach(cfg, hole)
    local pb = cfg.parentBox
    local side = (cfg.groups and cfg.groups[1]) or cfg
    local axis, sign = side.axis, side.sign
    if not axis then return false end
    local away, halong = "y", "hw"
    if axis ~= "X" then
        away, halong = "x", "hh"
    end
    local along = (away == "y") and "x" or "y"
    return abs(hole[along] - pb[along]) < hole[halong] + pb[halong] and sign * (hole[away] - pb[away]) > 0
end

-- Every OTHER claim's parent cell, clipped off this claim's own children.
local function ParentHoles(claims, index)
    local claim, holes = claims[index], nil
    for jdx = 1, #claims do
        local hgt = (jdx ~= index) and claims[jdx].parentBox or nil
        if hgt and BlocksReach(claim, hgt) then hgt = nil end
        if hgt then
            if AnyBoxMeets(hgt, claim.cells) then hgt = ClipHole(hgt, claim.cells) end
            if hgt then
                holes = holes or {}
                holes[#holes + 1] = hgt
            end
        end
    end
    return holes
end

-- Is this piece ground the claim already holds? Every side of a run folds the
-- parent's own cell in (see RunReach), so the sides overlap heavily around it and
-- carving each of them splits the same ground into pieces again and again -- and
-- a piece straddling two rects the claim already has is nobody's subset. Answered
-- by subtracting what is already there and asking whether anything survives, so
-- that costs no more code than the carve itself. A gate spent on ground the claim
-- holds anyway is a gate a piece that matters may not get.
local function Covered(b, regions)
    local pieces = { b }
    for region = 1, #regions do
        local kept = {}
        for index = 1, #pieces do
            CarveBox(kept, pieces[index], regions[region], true)
        end
        pieces = kept
        if #pieces == 0 then return true end
    end
    return false
end

-- Append one region rect to a claim, carved. The pieces holding one of this
-- claim's own children come first: PushPalette writes only REGION_MAX of them,
-- so an overflow drops the tail, and a dropped piece with a child under it would
-- take that child off the claim's ground entirely.
local AddRegion
do
    -- Do these two boxes share a stretch of EDGE, overlapping or merely abutting?
    -- BoxesMeet answers the other question -- is one box standing over the other --
    -- and a corridor never is: CorridorBox starts it at the parent cell's own outer
    -- edge, so the two touch along that whole edge and overlap by nothing at all.
    -- Read through BoxesMeet, a corridor therefore looked disconnected from the very
    -- cell it leads out of.
    --
    -- A shared edge and not a shared CORNER: contact at one point is not ground a
    -- cursor can cross, and a piece reachable only past a corner is exactly what the
    -- filter below is there to drop. So one axis must genuinely overlap while the
    -- other is allowed to touch.
    --
    -- The tolerance is for the touch itself. Two edges that meet by construction
    -- still arrive here through different arithmetic -- a centre and a half-extent
    -- recovered from a pair of edges -- and a boundary this rests on cannot be left
    -- to land on the exact same float twice.
    --
    -- Inside the block with its only caller, which is what kept it off the main
    -- chunk: as one file the module sat within a couple of Lua's ceiling of 200
    -- locals.
    local function BoxesTouch(a, b)
        local dx, dy = abs(a.x - b.x), abs(a.y - b.y)
        local sx, sy = a.hw + b.hw, a.hh + b.hh
        return (dx < sx and dy <= sy + 1e-4) or (dy < sy and dx <= sx + 1e-4)
    end

    function AddRegion(c, box, axis, holes)
        if not holes then
            c.regions[#c.regions + 1] = box
            return
        end
        local pieces = { box }
        for hi = 1, #holes do
            local kept = {}
            for pi = 1, #pieces do
                CarveBox(kept, pieces[pi], holes[hi], axis ~= "Y")
            end
            pieces = kept
        end
        for pass = 1, 2 do
            for pi = 1, #pieces do
                local b = pieces[pi]
                local holds = AnyBoxMeets(b, c.cells)
                -- A piece that holds no child of this claim and does not touch its
                -- parent cell either is on the FAR side of a hole, and the only way
                -- onto it is across that hole -- which hands the claim over before
                -- the cursor arrives. Keeping it would spend a gate on ground this
                -- claim can never be armed on.
                --
                -- Touching is the whole test, so it is asked with BoxesTouch. The
                -- corridor is the piece that turns on this: it abuts the parent cell
                -- along a full edge and overlaps it by nothing, so a strict test
                -- dropped the one rect covering the ground between an entry and its
                -- own nest -- and only ever where a second claim put a hole in play,
                -- which is why one nesting entry behaved and two did not.
                if
                    holds == (pass == 1)
                    and (holds or BoxesTouch(b, c.parentBox))
                    and not Covered(b, c.regions)
                then
                    c.regions[#c.regions + 1] = b
                end
            end
        end
    end
end

-- Nested geometry for one palette. Returns an array of CLAIMS -- one per slot
-- that opens a palette -- or nil when nothing in it nests:
--
--   parent   the slot index the children hang off
--   palette  the palette index they come from
--   slots    the child slots themselves, already capped at what this view's
--            layout can seat (see NestChildCap)
--   n        how many
--   angle    the parent entry's own angle                     } arc only
--   half     the half-angle of the room the rings may spread into } arc only
--   ground   the claim's own ground for the DISARM test, as a beam out of the
--            parent entry and a wedge past the entry ring     } arc only
--   rows     concentric rings of children, hugging the arc's own ring;
--            { radius, step, n, base, start, lo, hi } each -- start is the
--            CENTRE angle of that ring's first child, lo/hi the radial band
--            it answers to, hi nil on the outermost ring    } arc only
--   radius   the outermost ring's radius, for sizing the frame } arc only
--   band     the distance at which the children take over from the parent
--   cells    one box per child, { x, y, hw, hh }   } block layouts only
--   axis     the axis its run travels on, X or Y
--   sign     which side of the block it came out on, +1 up/right
--   dim      whether the block behind it is pushed back while it is open
--
-- ONE allocator, read by the drawing, by the hit test and by the push onto the
-- secure button. A second copy of any of this inside the snippet would drift
-- from what the palette draws the first time an option moved -- the same reason
-- the grid's cell centres are pushed rather than re-derived.
--
-- How much of the arc a claim's children may spread along: up to
-- arcChildMaxSpan, whatever its parent's own sector is worth. Child sectors
-- do NOT have to partition the plane against their neighbours: a claim
-- answers a release only while it is armed, and only the cursor's passing
-- through that parent entry arms it, so ground two claims' children both
-- cover is never ambiguous -- at most one of them is live. arcChildOverflow
-- decides whether the widening is allowed onto a neighbouring CLAIM's ground
-- at all:
--
--   NONE      stop at the midpoint to the nearest other claim, so no two
--             nests are ever drawn over one another
--   MIDPOINT  spend the whole span, overlapping other nests if it comes to it
--
-- Both may cross the PLAIN entries in between: those keep answering their own
-- angles whenever nothing is armed, and give them up only for as long as a
-- nest reaching over them is open.
--
-- More children than the span can hold is answered by RINGING them: a claim's
-- children hug the arc's own ring, spaced roughly a child pitch apart, and a
-- ring with no room left spills the rest into a second ring one child pitch
-- further out rather than growing its own radius until the angle buys enough
-- room, which is unbounded.
function PaletteView:ChildGeom(isShown, slots)
    local profile = self:P()
    if not profile or not slots or isShown < 1 then return nil end
    -- An editor draws no nests. What a nested entry holds is that palette's own
    -- business -- switch to it and it is the whole preview -- and drawing every
    -- nest at once buries the palette actually being arranged. It would also
    -- make the preview budget space for a reach it is not showing, shrinking the
    -- palette under the cursor to leave room for entries that are not there.
    if self.opts.interactive then return nil end

    -- Claimants in entry order first: how much room each one may take depends
    -- on where the next one sits, so none of them can be sized on its own.
    --
    -- NestChildCap's rule, asked of the view's own predicates rather than of
    -- the stored profile so a preview that pinned its layout seats what the
    -- layout it is showing can seat. Keep the two in step: this is the copy the
    -- LIVE menu uses, and it went on capping the arc at eight for a whole
    -- release after the other one stopped.
    local cap = (self:IsGrid() and profile.gridNestStyle == "HALO") and MAX_CHILDREN or MAX_SLOTS
    local claims
    for index = 1, isShown do
        local kids = ChildSlots(ChildIndex(slots[index]), cap)
        if kids and #kids > 0 then
            claims = claims or {}
            claims[#claims + 1] =
                { parent = index, n = #kids, slots = kids, palette = ChildIndex(slots[index]) }
        end
    end
    if not claims then return nil end

    -- Placement is per layout; the claims themselves are not. An arc carves
    -- sectors out of its parent's own, so its children are found by angle; a
    -- block layout gives every child a box and finds them by containment. The
    -- two answer the same question -- which region of the plane is this? -- in
    -- the terms their own layout is already steered in.
    if self:IsPointerLayout() then return self:CellChildGeom(claims, isShown) end
    if self:IsFan() then return self:StripNest(claims, isShown) end
    if self:LayoutMode() ~= "ARC" then return nil end

    local step, arcStart, full = self:ArcGeom(isShown)
    local radius, iconSize = self:Geom(isShown)
    -- Scaled by whatever this view scaled its geometry by, recovered from the
    -- icon size Geom handed back -- the same recovery the hub logo makes. The
    -- radius already carries that factor; a band read at its literal profile
    -- size would not, and the options preview would then draw its nests at
    -- full distance around a palette fitted to two-thirds.
    local base = profile.iconSize or 40
    local scale = (base > 0) and (iconSize / base) or 1
    local band = max(0, profile.nestBand or NEST_BAND_DEFAULT) * scale
    local gap = ((profile and profile.fanGap) or 10) * scale
    -- Nested entries are drawn smaller than the palette's own, so a nest reads
    -- as subordinate to the entry it hangs off rather than as a second ring of
    -- equals. It costs nothing in the hit test: the sectors are angular, and an
    -- icon's size has no part in deciding which one the cursor is in.
    local childIcon = iconSize * min(1, max(0.4, profile.nestScale or 0.8))
    local childPitch = childIcon + gap
    local capHalf = min(180, max(10, profile.arcChildMaxSpan or 90)) * pi / 180 * 0.5
    -- Anything that is not the one opt-in value keeps clear of other claims,
    -- so a saved profile that never set this reads as the cautious side.
    local keepClear = profile.arcChildOverflow ~= "MIDPOINT"
    local total = #claims

    -- Angles for all of them before any of them is sized: a claim keeping clear
    -- of its neighbours measures against the claim either side of it, and half
    -- of those sit later in the array.
    for index = 1, total do
        claims[index].angle = arcStart + (claims[index].parent - 1) * step
    end

    -- Both icons' halves plus the gap, so the band the user sets is the space
    -- actually seen between the palette's own ring and the first ring of
    -- children -- the ring every claim's children start hugging from.
    local inner = radius + iconSize * 0.5 + childIcon * 0.5 + band

    for index = 1, total do
        local claim = claims[index]
        -- The whole cap by default. NONE stops at the midpoint with the nearest
        -- CLAIMANT either side, so two nests never share ground; a lone
        -- claimant on a full circle has no neighbour to meet, and on an open
        -- arc the ends are free space.
        local half = capHalf
        if keepClear and total > 1 then
            local nxt = claims[index + 1] and claims[index + 1].angle or (full and (claims[1].angle + TWO_PI))
            local previous = claims[index - 1] and claims[index - 1].angle
                or (full and (claims[total].angle - TWO_PI))
            if nxt then half = min(half, (nxt - claim.angle) * 0.5) end
            if previous then half = min(half, (claim.angle - previous) * 0.5) end
        end
        -- Never NARROWER than the parent's own sector: a claim always has at
        -- least the room the entry it hangs off already owns.
        half = max(half, step * 0.5)

        claim.icon = childIcon
        claim.half = half
        -- Halfway across the gap: clear of the parent's own icon, short of the
        -- first ring of children. The parent entry keeps everything inside
        -- this.
        claim.band = radius + iconSize * 0.5 + band * 0.5

        -- Ring the children rather than pushing them out: each ring sits one
        -- child pitch further out than the last, its children spaced roughly a
        -- pitch apart along it, and a ring with no room left for the rest
        -- spills them into the next ring instead of growing its own radius.
        -- The room is the whole of c.half, so a claim whose children fit
        -- inside the span cap stays ONE ring however wide that has to be.
        -- MAX_CHILD_ROWS caps how many rings a claim may spill into -- past it
        -- the last ring simply takes everyone still waiting, however crowded
        -- that makes it, which is the same trade the old radius clamp made
        -- except it no longer drifts the children away from the arc to make
        -- it.
        local rowList, placed, ri = {}, 0, 0
        while placed < claim.n and ri < MAX_CHILD_ROWS do
            local rr = inner + ri * childPitch
            -- The arc length one child pitch buys at this ring's radius, in
            -- radians -- further out, the same angle spans more distance, so
            -- fewer degrees are needed to keep neighbours a pitch apart.
            local angStep = childPitch / rr
            local capacity = (ri == MAX_CHILD_ROWS - 1) and (claim.n - placed)
                or max(1, floor((half * 2) / angStep + 1e-6) + 1)
            local m = min(claim.n - placed, capacity)
            rowList[#rowList + 1] = {
                radius = rr,
                step = angStep,
                n = m,
                base = placed,
                start = claim.angle - (m - 1) * 0.5 * angStep,
            }
            placed = placed + m
            ri = ri + 1
        end
        -- The boundary between two rings is their midpoint radius: past it,
        -- the further ring's children are the nearer ones underfoot. The
        -- first ring's inner edge is c.band, the parent/child hand-off
        -- already computed above; the last ring has no outer edge at all.
        rowList[1].lo = claim.band
        for region = 2, #rowList do
            local mid = (rowList[region - 1].radius + rowList[region].radius) * 0.5
            rowList[region - 1].hi, rowList[region].lo = mid, mid
        end
        claim.rows = rowList
        -- The outermost ring's radius, so Layout can size the frame to hold
        -- every ring rather than just the first.
        claim.radius = rowList[#rowList].radius

        -- The ground the DISARM test keeps this claim armed on, in two pieces
        -- (LeaveSnippet, ANGULAR branch). Neither is the release's own per-ring
        -- resolution, and both are supersets of it, which is the only property
        -- that has to hold: a claim must never disarm anywhere its own release
        -- would still fire one of its children.
        --
        -- WEDGE, from the entry ring's outer edge outward. Its half-angle is
        -- the widest RING's: a ring answers the angles its children's own
        -- sectors cover, n * step wide, so the widest one covers every angle
        -- the release could resolve to a child here -- and one wedge for the
        -- lot leaves no gap between two rings of unequal width for the cursor
        -- to disarm in on its way out to the further one. Floored at the
        -- parent's own sector, which is the wider of the two on a claim of one
        -- or two children, and at the parent icon's own angular width, so a
        -- palette of one entry on an open arc (step 0) still has a wedge.
        -- Plus a grace of half a child sector, so overshooting the edge child
        -- by a hair leaves the nest open to correct back into rather than
        -- closing it for good; the grace deliberately does NOT widen the
        -- release, which still resolves the rings exactly, so the graced
        -- sliver fires the plain entry behind it while the nest stays live.
        --
        -- BEAM, out of the parent entry itself, for everything nearer than
        -- that. The wedge alone is not enough and the parent's icon box is not
        -- enough either: the reach for a child is a straight line from the
        -- parent, so it passes BESIDE the icon before it gets out past the
        -- entry ring -- a nest spread 44 degrees either side of a 30-degree
        -- entry is crossed at 11 to 25 degrees while still inside the ring's
        -- own radius -- and that ground answers to no ring and no icon box.
        -- The beam is a half-icon wide at the palette's centre and opens at
        -- the parent's own sector angle, which is what keeps it clear of the
        -- NEIGHBOURING entries' icons: the room between the beam's edge and a
        -- neighbour's centre works out to radius * tan(step / 2) - icon / 2,
        -- i.e. the beam misses the neighbour exactly when the two entries'
        -- icons do not overlap in the first place. That clearance is what lets
        -- a neighbouring claim take over -- gliding onto its entry leaves this
        -- ground, which disarms, which puts its parent gate back up.
        local wide, coarsest = 0, 0
        for region = 1, #rowList do
            wide = max(wide, rowList[region].n * rowList[region].step * 0.5)
            coarsest = max(coarsest, rowList[region].step)
        end
        claim.ground = {
            -- Radial projection onto the parent's own axis, not plain
            -- distance: the beam is measured along and across that axis.
            ax = sin(claim.angle),
            ay = cos(claim.angle),
            -- Inward of the icon's inner face is a retreat toward the centre,
            -- and disarming there is what hands the other claims their gates
            -- back.
            lo = radius - iconSize * 0.5,
            -- Where the wedge takes over from the beam. Past the entry ring
            -- rather than past the icons ON it, and that is the whole margin
            -- there is to work with: a nest spread wider than its parent's
            -- sector is reached by a line that crosses its NEIGHBOURS' icons,
            -- so some of that ground has to answer to the armed claim or the
            -- reach breaks -- while a neighbouring entry's own CENTRE sits at
            -- the ring itself and so is always outside the wedge, whatever the
            -- step. That is what a handoff needs: gliding onto another claim's
            -- entry leaves this ground, which disarms, which puts that claim's
            -- parent gate back up.
            edge = radius + iconSize * 0.25,
            beam = iconSize * 0.5,
            -- Clamped short of a quarter turn: tan runs away at one, and a
            -- palette of two entries on a full circle has a half-sector of
            -- exactly that. Past 60 degrees the wedge covers those angles
            -- anyway everywhere it applies.
            slope = tan(min(step * 0.5, pi / 3)),
            half = max(wide + coarsest * 0.5, step * 0.5, (iconSize * 0.5) / max(1, radius)),
        }

        -- The parent's own icon box, for the arming gate (see EnsureGates)
        -- and the disarm test alike -- standing on it always counts as this
        -- claim's ground. ChildRingPos wants c.rows, which is why this waits
        -- until here rather than running alongside the loop above.
        local px, py = radius * sin(claim.angle), radius * cos(claim.angle)
        claim.parentBox = { x = px, y = py, hw = iconSize * 0.5, hh = iconSize * 0.5 }

        -- What the disarm test actually decides an arc claim's ground by is
        -- polar -- c.ground above. The rects
        -- built here are only EVENT surfaces for the real gate frames, which
        -- can only ever be rects: generous rather than tight is fine for
        -- them, because the geometric test that decides whether leaving one
        -- actually disarms never trusts their bounds, only the wedge.
        local ringBoxes = {}
        for jdx = 1, claim.n do
            local region, a = self:ChildRingPos(claim, jdx)
            local cx, cy = region * sin(a), region * cos(a)
            ringBoxes[jdx] = { x = cx, y = cy, hw = claim.icon * 0.5, hh = claim.icon * 0.5 }
        end
        local nest = NestBBox(ringBoxes)

        -- The corridor's break-out direction is whichever screen axis the
        -- parent's own radial position leans further along -- an
        -- approximation of "straight out from the centre", which is all a
        -- rect can ever be for a wedge.
        local axis, sign
        if abs(px) >= abs(py) then
            axis, sign = "Y", (px >= 0) and 1 or -1
        else
            axis, sign = "X", (py >= 0) and 1 or -1
        end
        local corridor = CorridorBox(claim.parentBox, nest, axis, sign, childPitch)

        claim.regions = { claim.parentBox, nest, corridor }
    end

    return claims
end

-- An arc claim's j-th child (1-based across the whole claim, not just one
-- ring) -> the radius and angle it is drawn at. Read by the drawing and by
-- the needle's direction; HitTest walks the rings the other way, from a
-- radius to a ring, but lands on this same row.start/row.step to turn the
-- local index it finds back into the child it belongs to.
function PaletteView:ChildRingPos(cfg, jdx)
    local rowList = cfg.rows
    for region = 1, #rowList do
        local row = rowList[region]
        if jdx <= row.n then return row.radius, row.start + (jdx - 1) * row.step end
        jdx = jdx - row.n
    end
end

-- Angular step and starting angle for the arc layout, both clockwise from
-- straight up. Returns the step, the angle of slot 1, and whether this is a
-- full circle.
--
-- A full circle divides by the entry count and wraps: the last entry's far side
-- is the first entry's near side, so there is no seam. An arc divides by count
-- MINUS ONE instead, which puts the first and last entries ON its ends rather
-- than leaving a step-wide gap at the seam that belongs to no entry at all.
function PaletteView:ArcGeom(isShown)
    local profile = self:P()
    local deg = min(360, max(30, (profile and profile.arcSpan) or 360))
    local rot = ((profile and profile.arcRotation) or 0) * pi / 180

    if deg >= 359.5 then return (isShown > 0) and (TWO_PI / isShown) or 0, rot, true end

    local span = deg * pi / 180
    local step = (isShown > 1) and (span / (isShown - 1)) or 0
    return step, rot - span * 0.5, false
end

-- The pointer-steered fan is RETIRED from the UI: a fan is always
-- wheel-steered, with Select Action with Mouse on top (the Steering setting
-- was removed). The grid-one-deep machinery it routed to stays for the grid
-- itself; a fanInput key left in stored profiles is never read.
function PaletteView:IsHoverFan() return false end

-- Everything steered by pointing at a fixed arrangement, as opposed to the
-- scroll fan's moving one. These all share the grid's geometry and its update.
function PaletteView:IsPointerLayout() return self:IsGrid() or self:IsHoverFan() end

-------------------------------------------------------------------------------
--  Fan layout
--
--  A coverflow strip: the selected entry sits at the centre at full size, and
--  its neighbours shrink and fade by a fixed per-step ratio. Selection is
--  whatever is centred, so there is no hit test at all -- the mouse wheel
--  scrubs the strip and the centre is the answer.
--
--  Distance from the centre is the INTEGRAL of the scale curve plus a constant
--  gap rather than a sum of discrete steps. Two reasons: the spacing then
--  derives from the sizes it separates, so the strip tapers instead of leaving
--  shrunken icons floating in dead space; and it stays defined for fractional
--  offsets, which is what lets the strip slide smoothly between slots.
-------------------------------------------------------------------------------

-- Editor floors. The options preview draws the whole palette at once and every
-- entry in it is a drag target, so the live floors -- which are tuned to let
-- distant entries fade away -- would leave the ends of a long strip both
-- unreadable and hard to hit.
local FAN_EDIT_MIN_SCALE = 0.45
local FAN_EDIT_MIN_ALPHA = 0.45

-- Signed distance is applied by the caller; k is always >= 0 here.
--
-- minScale is not optional cosmetics: scale stops shrinking at the floor, so
-- spacing has to stop shrinking there too. Integrating the raw curve past that
-- point keeps closing the gaps under icons that have stopped getting smaller,
-- and they overlap. Past the knee the strip is therefore evenly spaced at the
-- floored size.
-- The size and alpha falloffs in force: both HARDCODED to 1 -- flat size,
-- full alpha, no proximity effects (the settings were removed pending the
-- user's own animation pass). 1 is a no-op everywhere it lands: decay ^ k
-- stays 1 at every k, the min-scale/alpha floors never engage, and
-- FanOffset's even-spacing branch takes the strip out to full pitch. This
-- pair is the single place to bring the falloffs back.
local function FalloffRatios() return 1, 1 end
mod.FalloffRatios = function(paletteIndex) return FalloffRatios(PA(paletteIndex)) end

-- Steps, flattened over the entry's own ground. Raw nearness is measured to an
-- entry's CENTRE, so the entry under the cursor grew and shrank as the cursor
-- crossed it -- it was at its largest only dead in the middle, and the one thing
-- on screen that should hold still while you settle on it was the one thing
-- moving. Everything inside an entry's own ground now reads as zero steps away.
--
-- Ground is half a step each side, which is exactly what the hit tests hand an
-- entry: half a step of arc, half a cell of grid. So the entry drawn at full
-- size and full alpha is precisely the entry a release would fire.
--
-- The identity past one full step is what keeps the settled drawing untouched:
-- an entry a whole step out is still decay ^ 1, two steps decay ^ 2, a grid
-- diagonal decay ^ sqrt 2. Only the half-step band between an entry's edge and
-- its neighbour's centre is redrawn, at twice the rate, and the strip -- whose
-- entries come to rest at whole steps -- never leaves the identity at all.
--
-- Fed ONE AXIS AT A TIME on the grid, then combined: flattening the 2D distance
-- instead would leave the corners of a cell outside the flat disc, still
-- breathing, and would pull the diagonal neighbour in off sqrt 2.
local function FalloffK(key)
    if key <= 0.5 then return 0 end
    if key >= 1 then return key end
    return (key - 0.5) * 2
end

local function FanOffset(scale, size, gap, decay, minScale)
    -- decay ~= 1 makes the integral degenerate (and 1 means "no falloff", so
    -- even spacing is the right answer anyway).
    if decay >= 0.999 then return (size + gap) * scale end
    local lnd = -log(decay)

    minScale = minScale or 0
    if minScale <= 0 then return size * (1 - decay ^ scale) / lnd + gap * scale end

    -- decay ^ knee == minScale, which is what makes the two branches meet.
    local knee = log(minScale) / log(decay)
    if scale <= knee then return size * (1 - decay ^ scale) / lnd + gap * scale end
    return size * (1 - minScale) / lnd + gap * knee + (size * minScale + gap) * (scale - knee)
end

-- Half-length of the editor's strip: centre to the outer edge of the last
-- entry, at the editor's own floors. Exported so the options preview can fit a
-- strip to the panel without duplicating any of the constants above.
--
-- HALF the count, from the full count the caller counted: the strip is cyclic,
-- and ApplyFanGeometry folds every offset into [-shown/2, shown/2], so the
-- entry drawn farthest from the centre is half the palette out and not the
-- whole of it. Measured over the whole count the strip was fitted to about
-- twice its own drawn length -- the preview shrank its icons to half what the
-- panel had room for.
function mod.FanReach(total, iconSize, gap, decay)
    return FanOffset(total * 0.5, iconSize, gap, decay, FAN_EDIT_MIN_SCALE)
        + iconSize
        + iconSize * (SelectedZoom() - 1) * 0.5
end

-- Position every widget from self.fanVisual, the CONTINUOUS centre. Called
-- from Layout and from every animation step; it never repaints icons, so it is
-- cheap enough to run each frame while the strip settles.
function PaletteView:ApplyFanGeometry()
    local profile = self:P()
    if not profile or not self:IsFan() then return end

    local isShown = self.shownCount
    if isShown < 1 then return end

    local _, iconSize = self:Geom()
    local gap = profile.fanGap or 10
    local decay, aDecay = FalloffRatios(profile)
    local minS = profile.fanMinScale or 0.30
    local minA = profile.fanMinAlpha or 0.12
    if self.opts.interactive then
        minS = max(minS, FAN_EDIT_MIN_SCALE)
        minA = max(minA, FAN_EDIT_MIN_ALPHA)
    end
    local horiz = self:FanHoriz()
    -- The editor windows exactly like play now: it draws the centre plus
    -- fanVisible each side and the wheel scrolls the rest into view, so what
    -- the preview shows is what a hold shows.
    local window = profile.fanVisible or 2

    local widget = self.frame
    local center = self.fanVisual or 1
    local half = isShown / 2
    -- The editor drops a horizontal strip a little to make room for its add
    -- button above the line -- see fanSide in Layout. Zero everywhere else.
    local crossOff = self._fanCrossOff or 0

    -- Half the width the selected entry gains, added to every offset past the
    -- centre so magnifying it cannot close the gaps under its neighbours. A
    -- CONSTANT, applied whichever entry is selected: making it follow the
    -- selection would reflow the whole strip on every step.
    --
    -- Ramped in over the first step rather than switched on the moment k leaves
    -- 0 -- see the offset below. The strip settles onto its entry CONTINUOUSLY,
    -- so a term that appeared the instant k was nonzero held the centre entry a
    -- few pixels out for the whole slide and then dropped it back as k reached
    -- exactly 0: the whole strip came to rest and the middle icon twitched a
    -- moment later, against the direction of travel. At every integer k the
    -- ramp is already at full extra, so nothing about the settled strip moves.
    local zoom = SelectedZoom()
    local extra = iconSize * (zoom - 1) * 0.5
    local sel = self.selection

    for index = 1, isShown do
        local wid = self.widgets[index]
        -- Shortest cyclic path, so wrapping past the end slides forward
        -- instead of rewinding the whole strip.
        local skinData = (index - center) % isShown
        if skinData > half then skinData = skinData - isShown end

        local key = abs(skinData)
        -- The strip FLOWS at its ends instead of popping: an entry keeps
        -- drawing for one slot past the last settled one, its alpha fading
        -- to exactly zero at the first slot a settled strip hides -- alpha
        -- as the mask. A slide therefore carries the incoming icon in from
        -- nothing and the outgoing one out to nothing, while a SETTLED
        -- strip shows precisely the set it always did at full strength, so
        -- the hover and release tests -- untouched -- keep firing exactly
        -- what is drawn solid. floor()ed off the cull's own old bound so a
        -- legacy fractional stored window keeps its drawn set too.
        local edge = floor(window + 0.5) + 1 - key
        if edge <= 0 then
            wid:Hide()
        else
            local s = max(minS, decay ^ key)
            local off = FanOffset(key, iconSize, gap, decay, minS)
            off = off + extra * min(1, key)
            if skinData < 0 then off = -off end

            wid:SetAlpha(min(1, edge) * max(minA, aDecay ^ key))
            -- Depth is size, not scale: SetPoint offsets are read in the
            -- widget's own scaled space, so scaling here would silently
            -- multiply the spacing computed above. The selected entry is
            -- magnified in the same breath, because these sizes are rewritten
            -- on every animation step and would erase a zoom applied elsewhere.
            local z = (index == sel) and zoom or 1
            wid.baseSize = iconSize * s
            wid:SetSize(iconSize * s * z, iconSize * s * z)
            wid:ClearAllPoints()
            if horiz then
                wid:SetPoint("CENTER", widget, "CENTER", off, crossOff)
            else
                wid:SetPoint("CENTER", widget, "CENTER", crossOff, -off)
            end
            wid:Show()
        end
    end
end

Inner.AddRegion, Inner.CorridorBox, Inner.EdgeBox, Inner.FalloffK = AddRegion, CorridorBox, EdgeBox, FalloffK
Inner.FalloffRatios, Inner.FAN_EDIT_MIN_ALPHA = FalloffRatios, FAN_EDIT_MIN_ALPHA
Inner.FAN_EDIT_MIN_SCALE, Inner.FanOffset, Inner.GraceBox = FAN_EDIT_MIN_SCALE, FanOffset, GraceBox
Inner.NestBBox, Inner.ParentHoles, Inner.RunReach = NestBBox, ParentHoles, RunReach
Inner.broken = false
