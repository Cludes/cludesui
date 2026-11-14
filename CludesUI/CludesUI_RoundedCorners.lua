if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUI_RoundedCorners.lua
--
--  Shared rounded corners for bar frames (unit frames, power bars, raid and
--  party cells, swing timer, nameplates). CludesUI.RoundCorners(owner,
--  radius, opts):
--    owner         the frame that keeps the state and hosts the body mask;
--                  an ancestor of every body texture
--    radius        0..16, 0 removes everything this owner added; never more
--                  than (the shape's short side - 1) / 2
--    opts.style    the border style key; only Solid, Glow and Shadow round
--                  (CludesUI.RoundedStyleOK), any other style removes it
--    opts.roots    up to 6 frames whose Texture regions (recursively) form
--                  the body; nil slots are fine
--    opts.textures up to 9 single textures of the body; nil slots are fine
--    opts.border   the frame CludesUI.ApplyBorderStyle draws on (optional)
--    opts.clip     a SetClipsChildren frame to switch off while rounded
--    opts.rect     the region whose rect is the rounded shape (default owner)
--    opts.corners  the corners that round, as bits (1 top left, 2 top right,
--                  4 bottom left, 8 bottom right); nil = all, 0 = none
--                  (CludesUI.RoundedJoinCorners splits them between two
--                  bars that join one above the other)
--  The opts tables are only read during the call, so callers may reuse them;
--  at radius 0 no opts are needed.
--  CludesUI.RoundedBorderColor(border, r, g, b, a) recolours the ring of a
--  border painted without CludesUI.SetBorderStyleColor (which recolours it
--  on its own).
--  CludesUI.RoundedSetCorners(owner, corners) moves only the round corners
--  of an owner whose other inputs (radius, style, rect, border, clip, roots,
--  textures) are those of its last RoundCorners pass, the caller's to check:
--  the pass re-fits and repaints without walking the body. It returns false,
--  and the caller runs RoundCorners, while the owner is not rounded, while a
--  body texture is left without the mask (the walk tries it again) or when no
--  corner rounds.
--
--  Masks: rounded-<r>.tga / rounded-inv-<r>.tga, (2r + 1) texels square
--  (.tools/rounded-glow/make_rounded_masks.py), sliced at r texels; no larger,
--  since the client shrinks the corners of a sliced texture bigger than its
--  region. rounded-<r>-<c>.tga / rounded-inv-<r>-<c>.tga: the same with only
--  the corners in c round, the rest square.
--  Body: a texture takes at most 3 masks, so each body texture gets ONE
--  nine-sliced rounded-rect mask, hosted on the owner (an ancestor of every
--  body texture, so it reaches into SetClipsChildren frames too). The bar
--  clip in opts.clip is switched off while rounded (the inset mask does its
--  job).
--  Solid: the body mask sits inside the border strips; the border is a
--  rounded fill in the border color with the body's exact inverse (same
--  nine-slice, same anchors) cut out, so body and border meet without a gap
--  and the fill never sits behind the body. The square strips are masked out.
--  One set of these parts per border container, so a border that moves
--  between frames (nameplate Basic <-> Custom) reuses its parts.
--  Glow / Shadow: the stock nine-slice glow is faded out and redrawn round:
--  its own edge art along the sides plus round corners generated from that
--  edge art (.tools/rounded-glow/make_glow_corners.py), its peak on the
--  rounded outline. Below half the glow width a corner piece spans the whole
--  band and the sides start past it, so they never overlap.
--  Pieces drawn outside the body stay square: the Raid Frames aggro and
--  dispel borders and party portrait, the Unit Frames threat border.
--
--  Cost: nothing until a radius above 0 is set (no masks, no hook). On: a
--  settings pass seats the body's new textures and redraws the border only
--  when one of its inputs moved; the recolor hook is a lookup. The pixel grid
--  watcher (CludesUI.RegisterPxReapply) re-fits the strip width and glow
--  edge of every rounded owner after a UI scale change.
--
--  The settings controls' rounded shapes, drawn texel to pixel (see
--  "Settings controls" at the end of this file): CludesUI.MakePixelLayer,
--  CludesUI.SetPillArt / SetCircleArt (the toggle's track and knob, the
--  slider's track, fill and thumb) and CludesUI.MakeRoundedBorder
--  (MakeBorder's API: dropdowns and their lists, value boxes, cog boxes).
-------------------------------------------------------------------------------
if not CludesUI then
    return
end

local MEDIA = "Interface\\AddOns\\CludesUI\\media\\rounded\\"
local GLOW_EDGE = "Interface\\AddOns\\CludesUI\\media\\borders\\glow-border"
local MAX_RADIUS = 16 -- rounded-1.tga .. rounded-16.tga
local ALL_CORNERS = 15
-- Glow corner art (the generator's constants match these): glow-corner-1..NA
-- for a radius of at least half the glow width E, by f = band width / radius
-- in even log steps from FMIN to 2; glow-tight-1..NB below that, by
-- k = S / E in even steps between 0.5 and 1 (S: the glow's outer corner to
-- the arc center).
local GLOW_FMIN, GLOW_NA, GLOW_NB = 0.03, 32, 12
local GLOW_LOGSTEP = math.log(2 / GLOW_FMIN) / (GLOW_NA - 1)
local STRETCHED = Enum.UITextureSliceMode.Stretched
local floor, min, upper, log, exp = math.floor, math.min, math.max, math.log, math.exp
local pairs, select, pcall = pairs, select, pcall

-- Media paths by number, built on first use.
local function Paths(fmt)
    return setmetatable({}, {
        __index = function(t, num)
            local val = MEDIA .. fmt:format(num)
            t[num] = val
            return val
        end,
    })
end
-- Masks by radius * 16 + round corners, built on first use.
local function MaskPaths(prefixText)
    return setmetatable({}, {
        __index = function(t, key)
            local num, c = floor(key / 16), key % 16
            local val = c == ALL_CORNERS and ("%s%s-%d.tga"):format(MEDIA, prefixText, num)
                or ("%s%s-%d-%d.tga"):format(MEDIA, prefixText, num, c)
            t[key] = val
            return val
        end,
    })
end
local ROUNDED = MaskPaths("rounded")
local ROUNDED_INV = MaskPaths("rounded-inv")
local GLOW_CORNER = Paths("glow-corner-%d.tga")
local GLOW_TIGHT = Paths("glow-tight-%d.tga")

-- dx, dy: the inward direction from each corner.
local CORNERS = {
    { p = "TOPLEFT", tc = { 0, 1, 0, 1 }, dx = 1, dy = -1, bit = 1 },
    { p = "TOPRIGHT", tc = { 1, 0, 0, 1 }, dx = -1, dy = -1, bit = 2 },
    { p = "BOTTOMLEFT", tc = { 0, 1, 1, 0 }, dx = 1, dy = 1, bit = 4 },
    { p = "BOTTOMRIGHT", tc = { 1, 0, 1, 0 }, dx = -1, dy = 1, bit = 8 },
}
local STRIPS = { "_top", "_bottom", "_left", "_right" }
local STYLE_OK = { solid = true, glow = true, shadow = true }
local EMPTY = {}
-- The options page pool's table (CludesUI_PixelPerfect.lua makes it; the
-- options addon fills it in place): read through this file local, never the
-- public slot.
local POOL = CludesUI._Pool

local status = setmetatable({}, { __mode = "k" }) -- owner -> rounding state
-- border container -> its Solid parts: a container outlives an owner's state
-- (an options page pool owner dressed again starts a new state, while its PP
-- border container stays on the same frame), so its parts are found again,
-- never made twice.
local solidsByCont = setmetatable({}, { __mode = "k" })
local byBorder = setmetatable({}, { __mode = "k" }) -- border frame -> state
local ownTex = setmetatable({}, { __mode = "k" }) -- our pieces, never masked
local hooked = false

CludesUI.ROUNDED_MAX_RADIUS = MAX_RADIUS
function CludesUI.RoundedStyleOK(look)
    return STYLE_OK[look or "solid"] == true
end

-- Options: appends the four corner toggles of a Corner Radius cog to rows.
-- get / set read and write the round corners bits (nil reads as all).
local CORNER_LABELS = { "Top Left", "Top Right", "Bottom Left", "Bottom Right" }
function CludesUI.RoundedCornerRows(rowList, get, group)
    for idx = 1, 4 do
        local b = CORNERS[idx].bit
        rowList[#rowList + 1] = {
            type = "toggle",
            label = CORNER_LABELS[idx],
            get = function()
                return bit.band(get() or ALL_CORNERS, b) ~= 0
            end,
            set = function(val)
                local m = get() or ALL_CORNERS
                group(val and bit.bor(m, b) or bit.band(m, ALL_CORNERS - b))
            end,
        }
    end
    return rowList
end

-- Options: the Join toggle for a bar that can sit right above or below its
-- partner (a detached power bar, a nameplate cast bar). applies() returns
-- true while the toggle applies; nil = always.
function CludesUI.RoundedJoinRow(rowList, labelText, tooltip, get, group, applies, need)
    rowList[#rowList + 1] = {
        type = "toggle",
        label = labelText,
        tooltip = tooltip,
        get = function()
            return get() == true
        end,
        set = group,
        disabled = applies and function()
            return not applies()
        end or nil,
        disabledTooltip = need,
    }
    return rowList
end

-- Two bars joined one above the other share one outline: the upper bar takes
-- the top corners, the lower one the bottom corners. Returns upper, lower.
function CludesUI.RoundedJoinCorners(corners)
    local m = corners or ALL_CORNERS
    return bit.band(m, 3), bit.band(m, 12)
end

-- Guarded: a texture takes at most 3 masks; a full one stays square.
local function AddMask(texture, m)
    return (pcall(texture.AddMaskTexture, texture, m))
end
-- Guarded the same way: the texture may no longer carry the mask.
local function RemoveMask(texture, m)
    pcall(texture.RemoveMaskTexture, texture, m)
end

local function SetRounded(object, radius, corners, wrap)
    object:SetTexture(ROUNDED[radius * 16 + corners], wrap, wrap)
    object:SetTextureSliceMargins(radius, radius, radius, radius)
    object:SetTextureSliceMode(STRETCHED)
end

-- Half a region's short side, or nil while it is unsized or secret.
local function HalfSide(regionFrame)
    local wid, hgt = regionFrame:GetSize()
    if issecretvalue(wid) or issecretvalue(hgt) then
        return nil
    end
    local half = min(wid, hgt) / 2
    if half > 0 then
        return half
    end
end

-------------------------------------------------------------------------------
--  Body
-------------------------------------------------------------------------------
-- The pass being walked (MaskBody sets these; walks never nest). A seated
-- texture carries the number of the last pass that found it, so the ones
-- left with an older number have left the body. wMissed: a body texture took
-- no mask (it holds three already); every walk tries it again.
local wMasked, wMask, wGen, wSkip, wMissed

local function Seat(texture)
    if wMasked[texture] or AddMask(texture, wMask) then
        wMasked[texture] = wGen
    else
        wMissed = true
    end
end

local function SeatRegions(...)
    for idx = 1, select("#", ...) do
        local r = select(idx, ...)
        if r:GetObjectType() == "Texture" and not ownTex[r] then
            Seat(r)
        end
    end
end

local Walk
local function WalkChildren(...)
    for idx = 1, select("#", ...) do
        Walk((select(idx, ...)))
    end
end
-- wSkip: the border frame (handled apart).
Walk = function(root)
    if root == wSkip then
        return
    end
    SeatRegions(root:GetRegions())
    WalkChildren(root:GetChildren())
end

-- Shape and place the body mask: inside the border strips' inner corners (they
-- follow every re-snap and a scale-decoupled border), else the shape rect.
-- Only while detached: a mask must carry its texture before it is added.
local function ShapeMask(st, m, radius, cont)
    SetRounded(m, radius, st.corners, "CLAMPTOBLACKADDITIVE")
    m:ClearAllPoints()
    if cont then
        m:SetPoint("TOPLEFT", cont._left, "TOPRIGHT", 0, 0)
        m:SetPoint("BOTTOMRIGHT", cont._right, "BOTTOMLEFT", 0, 0)
    else
        m:SetAllPoints(st.rect)
    end
end

-- A shape change detaches the mask from every body texture, reshapes it and
-- seats it again; one that no longer takes it waits for the next walk
-- (st.missed).
local function ReseatMask(st, radius, cont)
    local c = cont or false
    if st.kRadius == radius and st.kCont == c and st.kCorners == st.corners then
        return
    end
    st.kRadius, st.kCont, st.kCorners = radius, c, st.corners
    local m, masked = st.mask, st.masked
    for texture in pairs(masked) do
        RemoveMask(texture, m)
    end
    ShapeMask(st, m, radius, cont)
    for texture in pairs(masked) do
        if not AddMask(texture, m) then
            masked[texture] = nil
            st.missed = true
        end
    end
end

local function MaskBody(st, roots, singles, radius, cont, skip)
    local m = st.mask
    if not m then
        m = st.owner:CreateMaskTexture()
        st.mask = m
        st.kRadius = nil
    end
    ReseatMask(st, radius, cont)
    local gen = st.gen + 1
    st.gen = gen
    local masked = st.masked
    wMasked, wMask, wGen, wSkip, wMissed = masked, m, gen, skip, false
    for idx = 1, 6 do -- fixed slots: roots may hold nils
        local root = roots[idx]
        if root then
            Walk(root)
        end
    end
    for idx = 1, 9 do
        local texture = singles[idx]
        if texture then
            Seat(texture)
        end
    end
    st.missed = wMissed
    wMasked, wMask, wSkip = nil, nil, nil
    -- Release textures that left the body (a bar moved out, e.g. detached).
    for texture, g in pairs(masked) do
        if g ~= gen then
            RemoveMask(texture, m)
            masked[texture] = nil
        end
    end
end

-------------------------------------------------------------------------------
--  Solid: a rounded fill with the body's exact inverse cut out of it
-------------------------------------------------------------------------------
local function SolidOff(st)
    local sd = st.solid
    if not sd or not sd.on then
        return
    end
    for idx = 1, 4 do
        RemoveMask(sd.cont[STRIPS[idx]], sd.hide)
    end
    sd.fill:Hide()
    sd.on = nil
end

local function SolidParts(st, cont)
    local sd = solidsByCont[cont]
    if sd then
        return sd
    end
    sd = { cont = cont }
    -- The fill and its hole draw their slice corners in their frame's units,
    -- as the body mask does in the owner's. A scale-decoupled container
    -- (nameplates: its strips keep whole pixels whatever the plate's scale)
    -- runs other units, so there they take a layer of their own on the border
    -- frame, at the body's scale.
    local hostRegion = cont
    if cont.IsIgnoringParentScale and cont:IsIgnoringParentScale() then
        local hostFrame = cont:GetParent()
        hostRegion = CreateFrame("Frame", nil, hostFrame)
        hostRegion:SetAllPoints(cont)
        hostRegion:EnableMouse(false)
        -- Kept with its container: on a frame of the options page pool it
        -- rides that frame as the container does (CludesUI_PixelPerfect.lua),
        -- hidden at its reset and never handed out; SolidOn shows it again.
        local attach = POOL.Attach
        if attach then
            attach(hostFrame, hostRegion)
        end
        sd.layer = hostRegion
    end
    local fillTex = hostRegion:CreateTexture(nil, "OVERLAY", nil, 7)
    ownTex[fillTex] = true
    sd.fill = fillTex
    local hole = hostRegion:CreateMaskTexture()
    hole:SetPoint("TOPLEFT", cont._left, "TOPRIGHT", 0, 0)
    hole:SetPoint("BOTTOMRIGHT", cont._right, "BOTTOMLEFT", 0, 0)
    sd.hole = hole
    local hide = cont:CreateMaskTexture()
    hide:SetTexture(MEDIA .. "hide.tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    sd.hide = hide
    solidsByCont[cont] = sd
    return sd
end

-- radius: outer radius; inner: the body mask's radius (the hole is the same
-- nine-slice shape at the same anchors, so body and border always meet
-- without a gap, whatever size the client draws slice corners at).
local function SolidOn(st, cont, radius, inner)
    local sd = SolidParts(st, cont)
    if st.solid ~= sd then
        -- The border moved to another container: its old strips get their
        -- own look back and its fill goes.
        SolidOff(st)
        st.solid = sd
    end
    local rect = st.rect
    if sd.rect ~= rect then
        sd.fill:ClearAllPoints()
        sd.fill:SetAllPoints(rect)
        sd.hide:ClearAllPoints()
        sd.hide:SetAllPoints(rect)
        sd.rect = rect
    end
    -- The hole is reshaped only while detached (it must carry its texture
    -- before it is added).
    local corners = st.corners
    local innerKey = inner * 16 + corners
    if sd.inner ~= innerKey then
        if sd.inner then
            RemoveMask(sd.fill, sd.hole)
        end
        sd.hole:SetTexture(ROUNDED_INV[innerKey], "CLAMPTOWHITE", "CLAMPTOWHITE")
        sd.hole:SetTextureSliceMargins(inner, inner, inner, inner)
        sd.hole:SetTextureSliceMode(STRETCHED)
        AddMask(sd.fill, sd.hole)
        sd.inner = innerKey
    end
    if not sd.on then
        for idx = 1, 4 do
            AddMask(cont[STRIPS[idx]], sd.hide)
        end
        sd.on = true
    end
    if sd.radius ~= radius or sd.corners ~= corners then
        SetRounded(sd.fill, radius, corners)
        sd.radius, sd.corners = radius, corners
    end
    -- The layer draws where the container does.
    local layer = sd.layer
    if layer then
        if not layer:IsShown() then
            layer:Show()
        end
        local lvl = cont:GetFrameLevel()
        if layer:GetFrameLevel() ~= lvl then
            layer:SetFrameLevel(lvl)
        end
    end
    sd.fill:SetVertexColor(cont._top:GetVertexColor())
    sd.fill:Show()
end

-------------------------------------------------------------------------------
--  Glow / Shadow: the stock glow redrawn round
-------------------------------------------------------------------------------
local function GlowOff(st)
    local gl = st.glow
    if not gl or not gl.on then
        return
    end
    gl.bd:SetAlpha(1)
    gl.frame:Hide()
    gl.on = nil
end

local function GlowParts(st, border)
    local gl = st.glow
    if gl then
        return gl
    end
    -- On a frame of the options page pool the glow frame is pooled with it:
    -- the state that holds it is dropped once that frame is dressed again.
    local f = POOL.CreateFrame("Frame", nil, border)
    f:EnableMouse(false)
    gl = { frame = f, corner = {}, edge = {} }
    -- Corner pieces: art, size, place and crop are set per shape by GlowOn.
    for idx = 1, 4 do
        local t = f:CreateTexture(nil, "BORDER")
        ownTex[t] = true
        gl.corner[idx] = t
    end
    -- The edge file's left cell (outer side at u = 0) on every side: rotated
    -- for top and bottom, and turned round for the right and bottom edges so
    -- their outer side faces out too.
    for idx = 1, 4 do
        local t = f:CreateTexture(nil, "BORDER")
        t:SetTexture(GLOW_EDGE)
        ownTex[t] = true
        gl.edge[idx] = t
    end
    local e = gl.edge
    e[1]:SetTexCoord(0, 0, 0.125, 0, 0, 1, 0.125, 1) -- top
    e[2]:SetTexCoord(0.125, 0, 0, 0, 0.125, 1, 0, 1) -- bottom
    e[3]:SetTexCoord(0, 0.125, 0, 1) -- left
    e[4]:SetTexCoord(0.125, 0, 0, 1) -- right
    st.glow = gl
    return gl
end

-- One corner piece for S (the glow's outer corner to the arc center):
-- size: the piece's side; inset: its outer corner in from the glow's; crop:
-- the share of the art shown; run: where the sides start; band: the width
-- every piece draws the glow at, centered on the outline.
local function GlowPiece(Stl, E, half)
    if Stl >= E then
        -- The band fits between the outer corner and the arc center: the
        -- nearest step's piece, sized so its outline lands on this radius
        -- round this arc center. Its band is within a few percent of the
        -- border's, and the sides take the same width, so they meet it.
        local r = Stl - E / 2
        local num = Clamp(floor(log(E / r / GLOW_FMIN) / GLOW_LOGSTEP + 0.5) + 1, 1, GLOW_NA)
        local func = GLOW_FMIN * exp((num - 1) * GLOW_LOGSTEP)
        local dim = r * (1 + func / 2)
        return GLOW_CORNER[num], dim, Stl - dim, 1, Stl, func * r
    end
    -- A radius under half the band: the piece spans the whole band (at most
    -- half the short side, the art cut to match), its straight parts on the
    -- sides' own line, and the sides start past it.
    local dim = (half and half < E) and half or E
    return GLOW_TIGHT[Clamp(floor((Stl / E - 0.5) * 2 * GLOW_NB) + 1, 1, GLOW_NB)], dim, 0, dim / E, dim, E
end

local function GlowOn(st, border, bd, radius)
    -- The edge size from the backdrop's own info (GetBackdrop copies it).
    local E = bd.backdropInfo and bd:GetEdgeSize()
    if not E or E <= 0 then
        GlowOff(st)
        return
    end
    local gl = GlowParts(st, border)
    local f = gl.frame
    -- A new border or backdrop: the old one gets its alpha back.
    if gl.bd ~= bd then
        if gl.bd then
            gl.bd:SetAlpha(1)
        end
        gl.bd = bd
        gl.S = nil
    end
    if f:GetParent() ~= border then
        f:SetParent(border)
        gl.S = nil
    end
    -- S: from the glow's outer corner to the arc center, at most half the
    -- glow's short side. A square corner takes radius 0.
    local half = HalfSide(bd)
    local Stl = E / 2 + radius
    if half and Stl > half then
        Stl = half
    end
    local corners = st.corners
    local lvl = bd:GetFrameLevel()
    if gl.S ~= Stl or gl.E ~= E or gl.half ~= half or gl.lvl ~= lvl or gl.corners ~= corners then
        gl.S, gl.E, gl.half, gl.lvl, gl.corners = Stl, E, half, lvl, corners
        f:ClearAllPoints()
        f:SetAllPoints(bd)
        f:SetFrameLevel(lvl)
        local filePath, dim, inset, crop, run, band = GlowPiece(Stl, E, half)
        local sPath, sSize, sInset, sCrop, sRun
        if corners ~= ALL_CORNERS then
            local sS = E / 2
            if half and sS > half then
                sS = half
            end
            sPath, sSize, sInset, sCrop, sRun = GlowPiece(sS, E, half)
        end
        local runs = gl.runs
        if not runs then
            runs = {}
            gl.runs = runs
        end
        for idx = 1, 4 do
            local c, t = CORNERS[idx], gl.corner[idx]
            local p, sz, ins, cr = filePath, dim, inset, crop
            runs[idx] = run
            if bit.band(corners, c.bit) == 0 then
                p, sz, ins, cr = sPath, sSize, sInset, sCrop
                runs[idx] = sRun
            end
            local tc = c.tc
            t:SetTexture(p)
            t:SetTexCoord(tc[1] * cr, tc[2] * cr, tc[3] * cr, tc[4] * cr)
            t:SetSize(sz, sz)
            t:ClearAllPoints()
            t:SetPoint(c.p, f, c.p, c.dx * ins, c.dy * ins)
        end
        -- The sides: band wide, centered on the outline (E / 2 in from the
        -- glow's edge), from one corner's run to the other's.
        local e, o = gl.edge, (E - band) / 2
        local topY, bottom, leftX, right = e[1], e[2], e[3], e[4]
        topY:ClearAllPoints()
        topY:SetPoint("TOPLEFT", f, "TOPLEFT", runs[1], -o)
        topY:SetPoint("TOPRIGHT", f, "TOPRIGHT", -runs[2], -o)
        topY:SetHeight(band)
        bottom:ClearAllPoints()
        bottom:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", runs[3], o)
        bottom:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -runs[4], o)
        bottom:SetHeight(band)
        leftX:ClearAllPoints()
        leftX:SetPoint("TOPLEFT", f, "TOPLEFT", o, -runs[1])
        leftX:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", o, runs[3])
        leftX:SetWidth(band)
        right:ClearAllPoints()
        right:SetPoint("TOPRIGHT", f, "TOPRIGHT", -o, -runs[2])
        right:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -o, runs[4])
        right:SetWidth(band)
    end
    local r, g, b, a = bd:GetBackdropBorderColor()
    for idx = 1, 4 do
        gl.corner[idx]:SetVertexColor(r, g, b, a)
        gl.edge[idx]:SetVertexColor(r, g, b, a)
    end
    bd:SetAlpha(0)
    f:Show()
    gl.on = true
end

-------------------------------------------------------------------------------
--  Passes
-------------------------------------------------------------------------------
local Refit

-- Everything this owner added comes off; the state stays for the next time.
local function Clear(st)
    local m, masked = st.mask, st.masked
    for texture in pairs(masked) do
        RemoveMask(texture, m)
    end
    wipe(masked)
    st.kRadius = nil
    SolidOff(st)
    GlowOff(st)
    if st.border then
        byBorder[st.border] = nil
    end
    if st.clip then
        st.clip:SetClipsChildren(true)
        st.clip = nil
    end
    st.on = nil
    CludesUI.RegisterPxReapply(st.owner, nil)
end

local function OnBorderColor(borderFrame, r, g, b, a)
    local st = byBorder[borderFrame]
    if not st then
        return
    end
    a = a or 1
    local sd = st.solid
    if sd and sd.on then
        sd.fill:SetVertexColor(r, g, b, a)
    end
    local gl = st.glow
    if gl and gl.on then
        for idx = 1, 4 do
            gl.corner[idx]:SetVertexColor(r, g, b, a)
            gl.edge[idx]:SetVertexColor(r, g, b, a)
        end
    end
end
CludesUI.RoundedBorderColor = OnBorderColor

-- The scale-dependent half of a pass: the radius the shape allows, what the
-- border draws now (Solid strips, a glow backdrop, or nothing) and the body
-- mask's radius inside the strips.
local function Fit(st)
    local border, rect = st.border, st.rect
    local radius = st.radius
    -- A radius-r mask is 2r + 1 texels square, and the client shrinks a sliced
    -- texture's corners on a region smaller than the texture: the radius stays
    -- at most (short side - 1) / 2, so the region always holds its mask.
    local half = HalfSide(rect)
    if half and half >= 1 then
        local cap = upper(1, floor(half - 0.5))
        if radius > cap then
            radius = cap
        end
    end
    -- A border frame that is the owner itself hides along with the body, so
    -- its own shown flag says nothing (a nameplate cast bar between casts).
    local cont = border and (border == st.owner or border:IsShown()) and CludesUI.PP.GetBorders(border)
    local edge = cont and cont._top and cont:IsShown() and cont._top:IsShown() and cont._snapEdge or 0
    local inner = radius
    if edge > 0 then
        -- Strip width in shape units (the container may run its own scale).
        local cs, rs = cont:GetEffectiveScale(), rect:GetEffectiveScale()
        if rs > 0 then
            edge = edge * cs / rs
        end
        inner = upper(1, floor(radius - edge + 0.5))
        -- The inner rect holds the hole's and the body's masks the same way:
        -- past it their corners shrink or overlap and square their ends off,
        -- so a thin bar's body would poke out past the ring.
        if half then
            local cap = floor(half - edge - 0.5)
            if cap >= 1 and inner > cap then
                inner = cap
            end
        end
        return radius, inner, cont, nil
    end
    local bd = border and CludesUI._bdBorderData[border]
    local glow = st.glowStyle and bd and bd:IsShown() and bd or nil
    return radius, inner, nil, glow
end

local function Paint(st, radius, inner, cont, glow)
    if cont then
        SolidOn(st, cont, radius, inner)
    else
        SolidOff(st)
    end
    if glow then
        GlowOn(st, st.border, glow, radius)
    else
        GlowOff(st)
    end
end

-- The owner's options page pool dress (CludesUI_FramePool.lua; nil for a
-- frame the pool did not make).
local function PoolDress(ownerFrame)
    local gen = POOL.Gen
    return gen and gen(ownerFrame)
end
-- A state made for an earlier pool dress of its owner is over. The pool reset
-- the regions it holds (body mask, masked textures, glow pieces) and the new
-- dress may already use them in other roles, so none of them is touched: only
-- what lives outside the pool is undone (the Solid parts on the PP-kept border
-- container, a glow backdrop or bar clip the pool does not manage, the recolor
-- entry and the pixel-grid registration), then the state goes.
local function DropStale(ownerFrame, st)
    if not st or st.poolGen == PoolDress(ownerFrame) then
        return st
    end
    if st.on then
        SolidOff(st)
        local managed = POOL.Managed
        local gl = st.glow
        if gl and gl.on and gl.bd and not (managed and managed(gl.bd)) then
            gl.bd:SetAlpha(1)
        end
        local clip = st.clip
        if clip and not (managed and managed(clip)) then
            clip:SetClipsChildren(true)
        end
        CludesUI.RegisterPxReapply(ownerFrame, nil)
    end
    if st.border and byBorder[st.border] == st then
        byBorder[st.border] = nil
    end
    status[ownerFrame] = nil
    return nil
end

-- The pixel grid moved: the strips and the glow edge took new sizes, the
-- body textures stay the same.
Refit = function(ownerFrame)
    local st = DropStale(ownerFrame, status[ownerFrame])
    if not (st and st.on) then
        return
    end
    local radius, inner, cont, glow = Fit(st)
    ReseatMask(st, inner, cont)
    Paint(st, radius, inner, cont, glow)
end

function CludesUI.RoundCorners(ownerFrame, radius, options)
    if not ownerFrame then
        return
    end
    local st = DropStale(ownerFrame, status[ownerFrame])
    radius = min(floor(tonumber(radius) or 0), MAX_RADIUS)
    options = options or EMPTY
    local look = options.style or "solid"
    if radius > 0 and not STYLE_OK[look] then
        radius = 0
    end
    local corners = options.corners and floor(tonumber(options.corners) or ALL_CORNERS) % 16 or ALL_CORNERS
    if corners == 0 then
        radius = 0
    end
    if radius <= 0 then
        if st and st.on then
            Clear(st)
        end
        return
    end
    if not st then
        st = { owner = ownerFrame, masked = {}, gen = 0, poolGen = PoolDress(ownerFrame) }
        status[ownerFrame] = st
    end
    if not hooked then
        hooked = true
        hooksecurefunc(CludesUI, "SetBorderStyleColor", OnBorderColor)
    end
    st.radius, st.corners = radius, corners
    st.glowStyle = look == "glow" or look == "shadow"
    local rect = options.rect or ownerFrame
    if st.rect ~= rect then
        st.rect = rect
        st.kRadius = nil
    end
    local border = options.border
    if st.border ~= border then
        if st.border then
            byBorder[st.border] = nil
        end
        st.border = border
        st.kRadius = nil
    end
    if border then
        byBorder[border] = st
    end
    local clip = options.clip
    if st.clip ~= clip then
        if st.clip then
            st.clip:SetClipsChildren(true)
        end
        if clip then
            clip:SetClipsChildren(false)
        end
        st.clip = clip
    end
    local roots = options.roots
    if not roots then
        roots = st.ownRoots
        if not roots then
            roots = { ownerFrame }
            st.ownRoots = roots
        end
    end
    local r, inner, cont, glow = Fit(st)
    MaskBody(st, roots, options.textures or EMPTY, inner, cont, border)
    Paint(st, r, inner, cont, glow)
    if not st.on then
        st.on = true
        CludesUI.RegisterPxReapply(ownerFrame, Refit)
    end
end

-- A RoundCorners pass with only opts.corners changed: the body keeps its
-- textures, so the mask is reshaped in place (Refit) instead of walked again.
-- A body texture left without the mask needs the walk's retry: full pass.
function CludesUI.RoundedSetCorners(ownerFrame, corners)
    local st = ownerFrame and DropStale(ownerFrame, status[ownerFrame])
    if not (st and st.on) or st.missed then
        return false
    end
    corners = corners and floor(tonumber(corners) or ALL_CORNERS) % 16 or ALL_CORNERS
    if corners == 0 then
        return false
    end
    st.corners = corners
    if st.border then
        byBorder[st.border] = st
    end
    Refit(ownerFrame)
    return true
end

-------------------------------------------------------------------------------
--  Settings controls: art drawn in physical pixels
-------------------------------------------------------------------------------
-- CludesUI.MakePixelLayer(parent, fit) returns a layer object L whose
-- _frame is a frame over the parent (its level + 1, no mouse) that ignores
-- the parent's scale and runs at one unit per physical pixel, so art on it
-- lands texel to pixel at every Window Scale. fit(L, k), k = physical pixels
-- per parent unit, sizes that art: at L:Fit() (the caller's, once its art
-- exists), as the layer is shown, and after a Window Scale change while it
-- shows; it sets a piece again only when that piece moved. L.onShow(L), when
-- set, runs after the fit on every show. Frames and regions come from the
-- options page pool where the parent is pooled; a layer the pool dresses
-- again for another use drops out.
-- Art (media/rounded/pill-<h>.tga and circle-<d>.tga, 2..48 texels,
-- .tools/rounded-glow/make_pill_art.py): CludesUI.SetPillArt(tex, h), a
-- stadium h px tall with round ends of radius h / 2, sliced, so drawn on a
-- pixel layer at any width; CludesUI.SetCircleArt(tex, d), a circle d px
-- across, unsliced, so on any frame where the region is d px square. White:
-- the colour is the texture's vertex colour.
local WEAK_K = { __mode = "k" }
local layers = setmetatable({}, WEAK_K) -- layer frame -> layer object
local PILL = Paths("pill-%d.tga")
local CIRCLE = Paths("circle-%d.tga")
local ART_MIN, ART_MAX = 2, 48

function CludesUI.SetPillArt(texture, hgt)
    if hgt < ART_MIN then
        hgt = ART_MIN
    elseif hgt > ART_MAX then
        hgt = ART_MAX
    end
    local m = floor(hgt / 2)
    texture:SetTexture(PILL[hgt])
    texture:SetTextureSliceMargins(m, 0, m, 0)
    texture:SetTextureSliceMode(STRETCHED)
end

function CludesUI.SetCircleArt(texture, d)
    if d < ART_MIN then
        d = ART_MIN
    elseif d > ART_MAX then
        d = ART_MAX
    end
    texture:SetTexture(CIRCLE[d])
end

-- The layer's edges on whole pixels: a parent centred on its row or header
-- can sit half a pixel off the grid, which spread a 1 px outline over two.
-- Each edge moves to its nearest pixel (offsets in layer units = pixels).
local function SeatLayer(L, layer, key)
    local p = L.parent
    local l, t, r, b = p:GetLeft(), p:GetTop(), p:GetRight(), p:GetBottom()
    if
        not (l and t and r and b)
        or issecretvalue(l)
        or issecretvalue(t)
        or issecretvalue(r)
        or issecretvalue(b)
    then
        return
    end
    l, t, r, b = l * key, t * key, r * key, b * key
    l, t, r, b = floor(l + 0.5) - l, floor(t + 0.5) - t, floor(r + 0.5) - r, floor(b + 0.5) - b
    if L.sl == l and L.st == t and L.sr == r and L.sb == b then
        return
    end
    L.sl, L.st, L.sr, L.sb = l, t, r, b
    layer:ClearAllPoints()
    layer:SetPoint("TOPLEFT", p, "TOPLEFT", l, t)
    layer:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", r, b)
end

local function FitLayer(L)
    local layer = L._frame
    if L.gen ~= PoolDress(layer) then
        layers[layer] = nil
        return
    end
    local px = CludesUI.PP.perfect
    if L.px ~= px then
        L.px = px
        layer:SetScale(px)
    end
    local key = L.parent:GetEffectiveScale() / px
    if key > 0 then
        SeatLayer(L, layer, key)
        L.fit(L, key)
    end
end

local function LayerOnShow(self)
    local L = layers[self]
    if not L then
        return
    end
    FitLayer(L)
    if L.onShow and layers[self] then
        L.onShow(L)
    end
end

-- A layer made under a shown parent gets no OnShow, and its caller anchors
-- the parent only after the first fit, so the seat was taken from the wrong
-- spot until the next show. New layers re-fit once, together, a frame later.
local newLayers, newQueued = {}, false
local function FitNewLayers()
    newQueued = false
    for idx = 1, #newLayers do
        local L = newLayers[idx]
        newLayers[idx] = nil
        if layers[L._frame] == L and L._frame:IsVisible() then
            FitLayer(L)
        end
    end
end

function CludesUI.MakePixelLayer(hostFrame, fit)
    local layer = POOL.CreateFrame("Frame", nil, hostFrame)
    layer:SetIgnoreParentScale(true)
    layer:SetAllPoints(hostFrame)
    layer:SetFrameLevel(hostFrame:GetFrameLevel() + 1)
    layer:EnableMouse(false)
    local L = { _frame = layer, parent = hostFrame, fit = fit, gen = PoolDress(layer), Fit = FitLayer }
    layers[layer] = L
    layer:SetScript("OnShow", LayerOnShow)
    newLayers[#newLayers + 1] = L
    if not newQueued then
        newQueued = true
        C_Timer.After(0, FitNewLayers)
    end
    return L
end

-- A Window Scale change: the shown layers re-fit once the panel settles.
local function RefitLayers()
    for layer, L in pairs(layers) do
        if layer:IsVisible() then
            FitLayer(L)
        end
    end
end
if not CludesUI._onScaleChanged then
    CludesUI._onScaleChanged = {}
end
CludesUI._onScaleChanged[#CludesUI._onScaleChanged + 1] = RefitLayers

-- CludesUI.MakeRoundedBorder(parent, r, g, b, a, body, radius, clip, width) is the
-- rounded form of CludesUI.MakeBorder for the settings controls, with the
-- same API (_frame, :SetColor). The outline is a rounded fill with its inverse
-- cut out 1 px in, on a pixel layer, so its edge stays exactly 1 px and its
-- corners stay crisp at every Window Scale. radius (default 4) is in the
-- parent's units and is drawn in whole pixels. body (optional): the parent's
-- background texture, masked to the same shape in the parent's units (it
-- keeps the mask through SetColorTexture). clip (dropdown lists): on every
-- show, the textures in the scroll content of the parent's scroll frames take
-- a mask of the shape 1 unit in, so a row scrolled to an edge keeps the
-- corners round (once the mask's art and the texture's own have loaded:
-- ClipWhenLoaded). Only scroll content, which sits inside the list by
-- construction: a list's other children may lie outside it (a side submenu),
-- where the mask would hide them.
-- width (default 1): the edge in whole pixels, for a heavier ring (a pulse);
-- the radius keeps room for it.
-- The house corners when a caller names no radius: 2px on a control (a
-- button, a dropdown, an input, a tick box), 4px on a panel (a popup, a menu,
-- a list). A shape whose short side is PANEL_SIDE or more counts as a panel.
local OUTLINE_RADIUS, CONTROL_RADIUS, PANEL_SIDE = 4, 2, 80
local function HouseRadius(half)
    return (half and half * 2 >= PANEL_SIDE) and OUTLINE_RADIUS or CONTROL_RADIUS
end

local function OutlineSetColor(self, r, g, b, a)
    self._fill:SetVertexColor(r, g, b, a or 1)
end

-- o:SetCover(r, g, b): an opaque fill in the colour the control sits on,
-- under the outline, over its band and the corners outside it. A control of
-- stacked layers drawn square below it then reads rounded with its edge
-- blended once, where masks on each layer let the lower ones show through.
local function OutlineSetCover(self, r, g, b)
    local cover = self.cover
    if not cover then
        cover = self._frame:CreateTexture(nil, "BORDER", nil, 6)
        cover:SetAllPoints(self._frame)
        self.cover = cover
        if self.r then
            AddMask(cover, self.hole)
        end
    end
    cover:SetColorTexture(r, g, b, 1)
end

-- The radius in whole pixels from the parent's scale (at most what the height
-- holds) and the body's radius in the parent's units.
local function FitOutline(o, key)
    local hostFrame = o.parent
    local half = HalfSide(hostFrame)
    -- No radius named: the house corner for this size, read at each fit (the
    -- parent may not have been laid out when the outline was made).
    if o.autoRadius then
        o.radius = HouseRadius(half)
    end
    local r = floor(o.radius * key + 0.5)
    if half then
        local cap = floor(half * key - 0.5)
        if r > cap then
            r = cap
        end
    end
    local wid = o.width
    if r > MAX_RADIUS then
        r = MAX_RADIUS
    elseif r < wid + 1 then
        r = wid + 1
    end
    if o.r ~= r then
        -- The hole is reshaped detached (a mask carries its texture before
        -- it is added).
        local fillTex, hole, cover = o._fill, o.hole, o.cover
        if o.r then
            RemoveMask(fillTex, hole)
            if cover then
                RemoveMask(cover, hole)
            end
        end
        o.r = r
        SetRounded(fillTex, r, ALL_CORNERS)
        local inner = r - wid
        hole:SetTexture(ROUNDED_INV[inner * 16 + ALL_CORNERS], "CLAMPTOWHITE", "CLAMPTOWHITE")
        hole:SetTextureSliceMargins(inner, inner, inner, inner)
        hole:SetTextureSliceMode(STRETCHED)
        AddMask(fillTex, hole)
        if cover then
            AddMask(cover, hole)
        end
    end
    local bm = o.bodyMask
    if bm then
        local br = o.radius
        if half then
            local cap = floor(half - 0.5)
            if br > cap then
                br = cap
            end
        end
        if br < 1 then
            br = 1
        end
        if o.br ~= br then
            if o.br then
                RemoveMask(o.body, bm)
            end
            o.br = br
            SetRounded(bm, br, ALL_CORNERS, "CLAMPTOBLACKADDITIVE")
            AddMask(o.body, bm)
        end
    end
end

-- The clip walk (walks never nest): every texture in the scroll content of
-- the parent's own scroll frames takes the inner mask once per pool dress
-- (the pool's reset takes it off a texture it hands out again). Edit boxes
-- are skipped (the engine makes some of their regions). A texture whose own
-- art is still loading (a spell icon the session has not shown yet) goes
-- without the mask, losing one an earlier show gave it, and waits in
-- artWaiting (texture -> its list) for the art: see the wait below.
local cMask, cSet, cOwner
local artWaiting
local ClipFrame
local function ClipRegions(...)
    for idx = 1, select("#", ...) do
        local reg = select(idx, ...)
        if reg:GetObjectType() == "Texture" then
            local g = PoolDress(reg) or 0
            if reg.IsObjectLoaded and not reg:IsObjectLoaded() then
                if cSet[reg] == g then
                    RemoveMask(reg, cMask)
                    cSet[reg] = nil
                end
                if not artWaiting then
                    artWaiting = setmetatable({}, WEAK_K)
                end
                artWaiting[reg] = cOwner
            elseif cSet[reg] ~= g and AddMask(reg, cMask) then
                cSet[reg] = g
            end
        end
    end
end
local function ClipChildren(...)
    for idx = 1, select("#", ...) do
        ClipFrame((select(idx, ...)))
    end
end
ClipFrame = function(f)
    if f:GetObjectType() == "EditBox" then
        return
    end
    ClipRegions(f:GetRegions())
    ClipChildren(f:GetChildren())
end
local function ClipScrolls(...)
    for idx = 1, select("#", ...) do
        local f = select(idx, ...)
        if f:GetObjectType() == "ScrollFrame" then
            local contentFrame = f:GetScrollChild()
            if contentFrame then
                ClipFrame(contentFrame)
            end
        end
    end
end
local StartWait
local function ClipContent(o)
    cMask, cSet, cOwner = o.innerMask, o.clipped, o
    ClipScrolls(o.parent:GetChildren())
    cMask, cSet, cOwner = nil, nil, nil
    if artWaiting and next(artWaiting) then
        StartWait()
    end
end

-- The client loads texture files in the background, and a rounded mask's art
-- is first read when a session's first control of that shape shows. A texture
-- that takes a mask before the mask's art has loaded draws nothing, and nothing
-- redraws it when the art arrives: a list's checkboxes and icons stayed blank on
-- that first open until the pointer crossed them. So a list's clip walk, and a
-- card's clip and accent, wait for the art, as Blizzard's map waits for its
-- tiles: a frame of ours, shown only while something waits, finishes each once
-- its mask has loaded. Until then a texture draws unmasked (square corners).
-- The same holds for a masked texture's OWN art: a list of spell icons the
-- session had not shown yet drew most of them blank, or as a small stale
-- image, until the pointer crossed their rows. So the walk leaves a texture
-- whose art is still loading without the mask (it then draws as any texture
-- does once its art arrives), and the same frame gives it the mask once the
-- art is in, while its list is still open; a list closed meanwhile drops
-- its waits, and its next show walks it again.
local clipWait, clipWaiting, maskWaiting
local function ClipWaitTick(self)
    for o in pairs(clipWaiting) do
        if o.innerMask:IsObjectLoaded() then
            clipWaiting[o] = nil
            -- Still this layer's outline and on screen: a list closed
            -- meanwhile is walked by its next show.
            local layer = o._frame
            if layers[layer] == o and layer:IsVisible() then
                ClipContent(o)
            end
        end
    end
    for texture, wid in pairs(maskWaiting) do
        if wid.m:IsObjectLoaded() then
            maskWaiting[texture] = nil
            -- Not a texture the options page pool handed to another build since.
            if PoolDress(texture) == wid.gen then
                AddMask(texture, wid.m)
            end
        end
    end
    for texture, o in pairs(artWaiting) do
        local layer = o._frame
        if layers[layer] ~= o or not layer:IsVisible() then
            artWaiting[texture] = nil
        elseif texture:IsObjectLoaded() then
            artWaiting[texture] = nil
            local g = PoolDress(texture) or 0
            if o.clipped[texture] ~= g and AddMask(texture, o.innerMask) then
                o.clipped[texture] = g
            end
        end
    end
    if not next(clipWaiting) and not next(maskWaiting) and not next(artWaiting) then
        self:Hide()
    end
end
function StartWait()
    if not clipWait then
        clipWaiting, maskWaiting = setmetatable({}, WEAK_K), setmetatable({}, WEAK_K)
        if not artWaiting then
            artWaiting = setmetatable({}, WEAK_K)
        end
        clipWait = CreateFrame("Frame")
        clipWait:Hide()
        clipWait:SetScript("OnUpdate", ClipWaitTick)
    end
    clipWait:Show()
end
local function ClipWhenLoaded(o)
    local m = o.innerMask
    if not m.IsObjectLoaded or m:IsObjectLoaded() then
        return ClipContent(o)
    end
    StartWait()
    clipWaiting[o] = true
end
-- tex takes m now if its art has loaded, else once it has.
local function MaskWhenLoaded(texture, m)
    if not m.IsObjectLoaded or m:IsObjectLoaded() then
        return AddMask(texture, m)
    end
    StartWait()
    local wid = maskWaiting[texture]
    if wid then
        wid.m, wid.gen = m, PoolDress(texture)
    else
        maskWaiting[texture] = { m = m, gen = PoolDress(texture) }
    end
end

-- The outline's inner shape in the parent's units, made once: 1 unit in
-- with a radius 1 unit smaller, the same arc centres, so what it masks
-- follows the outline's corners as its sides do.
local function InnerMask(o)
    local im = o.innerMask
    if not im then
        local p = o.parent
        im = p:CreateMaskTexture()
        im:SetPoint("TOPLEFT", p, "TOPLEFT", 1, -1)
        im:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -1, 1)
        SetRounded(im, upper(1, o.radius - 1), ALL_CORNERS, "CLAMPTOBLACKADDITIVE")
        o.innerMask = im
    end
    return im
end

function CludesUI.MakeRoundedBorder(hostFrame, r, g, b, a, body, radius, clip, width)
    local o = CludesUI.MakePixelLayer(hostFrame, FitOutline)
    local layer = o._frame
    local fillTex = layer:CreateTexture(nil, "BORDER", nil, 7)
    fillTex:SetAllPoints(layer)
    fillTex:SetVertexColor(r or 0, g or 0, b or 0, a or 1)
    -- One unit is one pixel on the layer: width px in from every edge.
    local wid = width or 1
    o.width = wid
    local hole = layer:CreateMaskTexture()
    hole:SetPoint("TOPLEFT", layer, "TOPLEFT", wid, -wid)
    hole:SetPoint("BOTTOMRIGHT", layer, "BOTTOMRIGHT", -wid, wid)
    o._fill, o.hole, o.SetColor, o.SetCover = fillTex, hole, OutlineSetColor, OutlineSetCover
    -- A clipped outline is a list or a menu: a panel.
    o.radius = radius or (clip and OUTLINE_RADIUS or CONTROL_RADIUS)
    o.autoRadius = (radius == nil and not clip) or nil
    if body then
        local bm = hostFrame:CreateMaskTexture()
        bm:SetAllPoints(hostFrame)
        o.body, o.bodyMask = body, bm
    end
    if clip then
        InnerMask(o)
        o.clipped, o.onShow = setmetatable({}, WEAK_K), ClipWhenLoaded
    end
    o:Fit()
    return o
end

-- CludesUI.RoundBody(parent, body, radius): a background with no outline
-- (a search field, an input with no border) rounded: body takes a mask of a
-- rounded rect over its own rect, radius (default 4) in the parent's units,
-- at most what the body's short side holds (a body not laid out yet reads
-- 1 x 1 and takes the radius as given). The mask is the parent's, so body
-- is the parent's texture or a descendant's; it keeps the mask through
-- SetColorTexture. Returns the mask.
function CludesUI.RoundBody(hostFrame, body, radius)
    local half = HalfSide(body)
    radius = radius or HouseRadius(half)
    if half and half > 1 then
        local cap = floor(half - 0.5)
        if radius > cap then
            radius = cap
        end
    end
    if radius < 1 then
        return
    end
    local m = hostFrame:CreateMaskTexture()
    m:SetAllPoints(body)
    SetRounded(m, radius, ALL_CORNERS, "CLAMPTOBLACKADDITIVE")
    AddMask(body, m)
    return m
end

-- CludesUI.MakeRoundedCard(parent, brdA, bgA, accentH, r, g, b): the
-- settings card. A fill (default 0.062, 0.070, 0.082 at bgA 0.5) under a
-- rounded 1 px white outline at brdA (0.12). accentH: an accent bar down the
-- card's left edge, accentH thick, on the outline's pixel layer under its
-- inner shape (sharp, ends follow the corners); the caller colours it. Returns the outline with o.bg, o.accent
-- and o:Clip(tex), masking a texture of parent or a descendant to the
-- inside of the outline (a side strip, a hover fill).
local CARD_R, CARD_G, CARD_B = 0.062, 0.070, 0.082

local function FitCard(o, key)
    FitOutline(o, key)
    local accent, am = o.accent, o.accentMask
    if o.r and o.ar ~= o.r then
        if o.ar then
            RemoveMask(accent, am)
        end
        o.ar = o.r
        SetRounded(am, o.r - 1, ALL_CORNERS, "CLAMPTOBLACKADDITIVE")
        MaskWhenLoaded(accent, am)
    end
    local hgt = floor(o.accentH * key + 0.5)
    accent:SetWidth(hgt < 1 and 1 or hgt)
end

local function CardClip(o, texture)
    MaskWhenLoaded(texture, InnerMask(o))
end

function CludesUI.MakeRoundedCard(hostFrame, brdA, bgA, accentH, r, g, b)
    local backdrop = hostFrame:CreateTexture(nil, "BACKGROUND")
    backdrop:SetAllPoints()
    backdrop:SetColorTexture(r or CARD_R, g or CARD_G, b or CARD_B, bgA or 0.5)
    local o = CludesUI.MakeRoundedBorder(hostFrame, 1, 1, 1, brdA or 0.12, backdrop)
    o.bg, o.Clip = backdrop, CardClip
    if accentH then
        -- One unit is one pixel on the layer, as the outline's hole.
        local layer = o._frame
        local accent = layer:CreateTexture(nil, "BORDER", nil, 6)
        accent:SetPoint("TOPLEFT", layer, "TOPLEFT", 1, -1)
        accent:SetPoint("BOTTOMLEFT", layer, "BOTTOMLEFT", 1, 1)
        local am = layer:CreateMaskTexture()
        am:SetPoint("TOPLEFT", layer, "TOPLEFT", 1, -1)
        am:SetPoint("BOTTOMRIGHT", layer, "BOTTOMRIGHT", -1, 1)
        o.accent, o.accentMask, o.accentH, o.fit = accent, am, accentH, FitCard
        o:Fit()
    end
    return o
end

-------------------------------------------------------------------------------
--  House button and sidebar styles (the options panel's card look), for the
--  manager pages and popups that draw their own.
--
--  OutlineButton(btn, bg, primary): a square button, dark with an outline and
--  text in the accent colour (primary) or grey; hover adds a faint wash and
--  brightens the outline. Takes over the button's OnEnter/OnLeave, so call it
--  only on a button whose hover did nothing but recolour it. The label is the
--  button's first FontString.
--
--  CardSidebar(outer, bg): a manager sidebar as a card: faint body, an
--  accent cap along the top and 1px edges, over the sidebar's own background
--  texture bg (which it repaints).
-------------------------------------------------------------------------------
function CludesUI.OutlineButton(button, backdrop, primary)
    local function Colour()
        if primary then
            local c = CludesUI.CLUDES_GREEN
            return c.r, c.g, c.b
        end
        return 1, 1, 1
    end
    local rest, lit = primary and 0.7 or 0.22, primary and 1 or 0.45
    local r, g, b = Colour()
    backdrop:SetColorTexture(r, g, b, 0.06)
    local brd = CludesUI.MakeRoundedBorder(button, r, g, b, rest, backdrop, 2)
    local function Label()
        for _, regionFrame in ipairs({ button:GetRegions() }) do
            if regionFrame:GetObjectType() == "FontString" then
                return regionFrame
            end
        end
    end
    local function Paint(hover)
        local cr, cg, cb = Colour()
        backdrop:SetColorTexture(cr, cg, cb, hover and 0.14 or 0.06)
        brd:SetColor(cr, cg, cb, hover and lit or rest)
        local labelFS = Label()
        if labelFS then
            labelFS:SetTextColor(cr, cg, cb, primary and 1 or 0.8)
        end
    end
    button:SetScript("OnEnter", function()
        Paint(true)
    end)
    button:SetScript("OnLeave", function()
        Paint(false)
    end)
    Paint(false)
    return brd
end

-- AccentCap(frame): the house accent line along a menu's or popup's top
-- edge (2px), repainted with the current accent each time the frame shows.
function CludesUI.AccentCap(widget)
    local cap = widget:CreateTexture(nil, "OVERLAY", nil, 7)
    cap:SetPoint("TOPLEFT")
    cap:SetPoint("TOPRIGHT")
    cap:SetHeight(2)
    local function Paint()
        local c = CludesUI.CLUDES_GREEN
        cap:SetColorTexture(c.r, c.g, c.b, 0.9)
    end
    Paint()
    widget:HookScript("OnShow", Paint)
    return cap
end

function CludesUI.CardSidebar(outer, backdrop)
    backdrop:SetColorTexture(1, 1, 1, 0.025)
    local function Line(a)
        local t = outer:CreateTexture(nil, "ARTWORK")
        t:SetColorTexture(1, 1, 1, a)
        return t
    end
    local cap = outer:CreateTexture(nil, "ARTWORK")
    local c = CludesUI.CLUDES_GREEN
    cap:SetColorTexture(c.r, c.g, c.b, 0.9)
    cap:SetPoint("TOPLEFT")
    cap:SetPoint("TOPRIGHT")
    cap:SetHeight(2)
    for _, sideName in ipairs({ "LEFT", "RIGHT" }) do
        local e = Line(0.10)
        e:SetPoint("TOP" .. sideName)
        e:SetPoint("BOTTOM" .. sideName)
        e:SetWidth(1)
    end
    local bottom = Line(0.10)
    bottom:SetPoint("BOTTOMLEFT")
    bottom:SetPoint("BOTTOMRIGHT")
    bottom:SetHeight(1)
end
