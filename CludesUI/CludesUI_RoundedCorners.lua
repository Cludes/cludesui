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
local floor, min, max, log, exp = math.floor, math.min, math.max, math.log, math.exp
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
function CludesUI.RoundedStyleOK(style)
    return STYLE_OK[style or "solid"] == true
end

-- Options: appends the four corner toggles of a Corner Radius cog to rows.
-- get / set read and write the round corners bits (nil reads as all).
local CORNER_LABELS = { "Top Left", "Top Right", "Bottom Left", "Bottom Right" }
function CludesUI.RoundedCornerRows(rowList, get, set)
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
                set(val and bit.bor(m, b) or bit.band(m, ALL_CORNERS - b))
            end,
        }
    end
    return rowList
end

-- Options: the Join toggle for a bar that can sit right above or below its
-- partner (a detached power bar, a nameplate cast bar). applies() returns
-- true while the toggle applies; nil = always.
function CludesUI.RoundedJoinRow(rowList, labelText, tooltip, get, set, applies, need)
    rowList[#rowList + 1] = {
        type = "toggle",
        label = labelText,
        tooltip = tooltip,
        get = function()
            return get() == true
        end,
        set = set,
        disabled = applies and function()
            return not applies()
        end or nil,
        disabledTooltip = need,
    }
    return rowList
end

-- Two bars joined one above the other share one outline: the upper bar takes
-- the top corners, the lower one the bottom corners. Returns upper, lower.
function CludesUI.RoundedJoinCorners(cornerList)
    local m = cornerList or ALL_CORNERS
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

local function SetRounded(object, cornerRadius, cornerList, wrap)
    object:SetTexture(ROUNDED[cornerRadius * 16 + cornerList], wrap, wrap)
    object:SetTextureSliceMargins(cornerRadius, cornerRadius, cornerRadius, cornerRadius)
    object:SetTextureSliceMode(STRETCHED)
end

-- Half a region's short side, or nil while it is unsized or secret.
local function HalfSide(regionFrame)
    local wid, hgt = regionFrame:GetSize()
    if issecretvalue(wid) or issecretvalue(hgt) then
        return nil
    end
    local halfSize = min(wid, hgt) / 2
    if halfSize > 0 then
        return halfSize
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
local function ShapeMask(state, m, cornerRadius, container)
    SetRounded(m, cornerRadius, state.corners, "CLAMPTOBLACKADDITIVE")
    m:ClearAllPoints()
    if container then
        m:SetPoint("TOPLEFT", container._left, "TOPRIGHT", 0, 0)
        m:SetPoint("BOTTOMRIGHT", container._right, "BOTTOMLEFT", 0, 0)
    else
        m:SetAllPoints(state.rect)
    end
end

-- A shape change detaches the mask from every body texture, reshapes it and
-- seats it again; one that no longer takes it waits for the next walk
-- (st.missed).
local function ReseatMask(state, cornerRadius, container)
    local c = container or false
    if state.kRadius == cornerRadius and state.kCont == c and state.kCorners == state.corners then
        return
    end
    state.kRadius, state.kCont, state.kCorners = cornerRadius, c, state.corners
    local m, masked = state.mask, state.masked
    for texture in pairs(masked) do
        RemoveMask(texture, m)
    end
    ShapeMask(state, m, cornerRadius, container)
    for texture in pairs(masked) do
        if not AddMask(texture, m) then
            masked[texture] = nil
            state.missed = true
        end
    end
end

local function MaskBody(state, roots, singles, cornerRadius, container, skip)
    local m = state.mask
    if not m then
        m = state.owner:CreateMaskTexture()
        state.mask = m
        state.kRadius = nil
    end
    ReseatMask(state, cornerRadius, container)
    local gen = state.gen + 1
    state.gen = gen
    local masked = state.masked
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
    state.missed = wMissed
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
local function SolidOff(state)
    local shadow = state.solid
    if not shadow or not shadow.on then
        return
    end
    for idx = 1, 4 do
        RemoveMask(shadow.cont[STRIPS[idx]], shadow.hide)
    end
    shadow.fill:Hide()
    shadow.on = nil
end

local function SolidParts(state, container)
    local shadow = solidsByCont[container]
    if shadow then
        return shadow
    end
    shadow = { cont = container }
    -- The fill and its hole draw their slice corners in their frame's units,
    -- as the body mask does in the owner's. A scale-decoupled container
    -- (nameplates: its strips keep whole pixels whatever the plate's scale)
    -- runs other units, so there they take a layer of their own on the border
    -- frame, at the body's scale.
    local host = container
    if container.IsIgnoringParentScale and container:IsIgnoringParentScale() then
        local hostFrame = container:GetParent()
        host = CreateFrame("Frame", nil, hostFrame)
        host:SetAllPoints(container)
        host:EnableMouse(false)
        -- Kept with its container: on a frame of the options page pool it
        -- rides that frame as the container does (CludesUI_PixelPerfect.lua),
        -- hidden at its reset and never handed out; SolidOn shows it again.
        local attach = POOL.Attach
        if attach then
            attach(hostFrame, host)
        end
        shadow.layer = host
    end
    local fillTex = host:CreateTexture(nil, "OVERLAY", nil, 7)
    ownTex[fillTex] = true
    shadow.fill = fillTex
    local cutout = host:CreateMaskTexture()
    cutout:SetPoint("TOPLEFT", container._left, "TOPRIGHT", 0, 0)
    cutout:SetPoint("BOTTOMRIGHT", container._right, "BOTTOMLEFT", 0, 0)
    shadow.hole = cutout
    local hide = container:CreateMaskTexture()
    hide:SetTexture(MEDIA .. "hide.tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    shadow.hide = hide
    solidsByCont[container] = shadow
    return shadow
end

-- radius: outer radius; inner: the body mask's radius (the hole is the same
-- nine-slice shape at the same anchors, so body and border always meet
-- without a gap, whatever size the client draws slice corners at).
local function SolidOn(state, container, cornerRadius, innerTex)
    local shadow = SolidParts(state, container)
    if state.solid ~= shadow then
        -- The border moved to another container: its old strips get their
        -- own look back and its fill goes.
        SolidOff(state)
        state.solid = shadow
    end
    local rectTex = state.rect
    if shadow.rect ~= rectTex then
        shadow.fill:ClearAllPoints()
        shadow.fill:SetAllPoints(rectTex)
        shadow.hide:ClearAllPoints()
        shadow.hide:SetAllPoints(rectTex)
        shadow.rect = rectTex
    end
    -- The hole is reshaped only while detached (it must carry its texture
    -- before it is added).
    local cornerList = state.corners
    local innerKey = innerTex * 16 + cornerList
    if shadow.inner ~= innerKey then
        if shadow.inner then
            RemoveMask(shadow.fill, shadow.hole)
        end
        shadow.hole:SetTexture(ROUNDED_INV[innerKey], "CLAMPTOWHITE", "CLAMPTOWHITE")
        shadow.hole:SetTextureSliceMargins(innerTex, innerTex, innerTex, innerTex)
        shadow.hole:SetTextureSliceMode(STRETCHED)
        AddMask(shadow.fill, shadow.hole)
        shadow.inner = innerKey
    end
    if not shadow.on then
        for idx = 1, 4 do
            AddMask(container[STRIPS[idx]], shadow.hide)
        end
        shadow.on = true
    end
    if shadow.radius ~= cornerRadius or shadow.corners ~= cornerList then
        SetRounded(shadow.fill, cornerRadius, cornerList)
        shadow.radius, shadow.corners = cornerRadius, cornerList
    end
    -- The layer draws where the container does.
    local drawLayer = shadow.layer
    if drawLayer then
        if not drawLayer:IsShown() then
            drawLayer:Show()
        end
        local lvl = container:GetFrameLevel()
        if drawLayer:GetFrameLevel() ~= lvl then
            drawLayer:SetFrameLevel(lvl)
        end
    end
    shadow.fill:SetVertexColor(container._top:GetVertexColor())
    shadow.fill:Show()
end

-------------------------------------------------------------------------------
--  Glow / Shadow: the stock glow redrawn round
-------------------------------------------------------------------------------
local function GlowOff(state)
    local glowTex = state.glow
    if not glowTex or not glowTex.on then
        return
    end
    glowTex.bd:SetAlpha(1)
    glowTex.frame:Hide()
    glowTex.on = nil
end

local function GlowParts(state, edgeTex)
    local glowTex = state.glow
    if glowTex then
        return glowTex
    end
    -- On a frame of the options page pool the glow frame is pooled with it:
    -- the state that holds it is dropped once that frame is dressed again.
    local f = POOL.CreateFrame("Frame", nil, edgeTex)
    f:EnableMouse(false)
    glowTex = { frame = f, corner = {}, edge = {} }
    -- Corner pieces: art, size, place and crop are set per shape by GlowOn.
    for idx = 1, 4 do
        local t = f:CreateTexture(nil, "BORDER")
        ownTex[t] = true
        glowTex.corner[idx] = t
    end
    -- The edge file's left cell (outer side at u = 0) on every side: rotated
    -- for top and bottom, and turned round for the right and bottom edges so
    -- their outer side faces out too.
    for idx = 1, 4 do
        local t = f:CreateTexture(nil, "BORDER")
        t:SetTexture(GLOW_EDGE)
        ownTex[t] = true
        glowTex.edge[idx] = t
    end
    local e = glowTex.edge
    e[1]:SetTexCoord(0, 0, 0.125, 0, 0, 1, 0.125, 1) -- top
    e[2]:SetTexCoord(0.125, 0, 0, 0, 0.125, 1, 0, 1) -- bottom
    e[3]:SetTexCoord(0, 0.125, 0, 1) -- left
    e[4]:SetTexCoord(0.125, 0, 0, 1) -- right
    state.glow = glowTex
    return glowTex
end

-- One corner piece for S (the glow's outer corner to the arc center):
-- size: the piece's side; inset: its outer corner in from the glow's; crop:
-- the share of the art shown; run: where the sides start; band: the width
-- every piece draws the glow at, centered on the outline.
local function GlowPiece(S, E, halfSize)
    if S >= E then
        -- The band fits between the outer corner and the arc center: the
        -- nearest step's piece, sized so its outline lands on this radius
        -- round this arc center. Its band is within a few percent of the
        -- border's, and the sides take the same width, so they meet it.
        local r = S - E / 2
        local num = Clamp(floor(log(E / r / GLOW_FMIN) / GLOW_LOGSTEP + 0.5) + 1, 1, GLOW_NA)
        local func = GLOW_FMIN * exp((num - 1) * GLOW_LOGSTEP)
        local size = r * (1 + func / 2)
        return GLOW_CORNER[num], size, S - size, 1, S, func * r
    end
    -- A radius under half the band: the piece spans the whole band (at most
    -- half the short side, the art cut to match), its straight parts on the
    -- sides' own line, and the sides start past it.
    local size = (halfSize and halfSize < E) and halfSize or E
    return GLOW_TIGHT[Clamp(floor((S / E - 0.5) * 2 * GLOW_NB) + 1, 1, GLOW_NB)], size, 0, size / E, size, E
end

local function GlowOn(state, edgeTex, backdrop, cornerRadius)
    -- The edge size from the backdrop's own info (GetBackdrop copies it).
    local E = backdrop.backdropInfo and backdrop:GetEdgeSize()
    if not E or E <= 0 then
        GlowOff(state)
        return
    end
    local glowTex = GlowParts(state, edgeTex)
    local f = glowTex.frame
    -- A new border or backdrop: the old one gets its alpha back.
    if glowTex.bd ~= backdrop then
        if glowTex.bd then
            glowTex.bd:SetAlpha(1)
        end
        glowTex.bd = backdrop
        glowTex.S = nil
    end
    if f:GetParent() ~= edgeTex then
        f:SetParent(edgeTex)
        glowTex.S = nil
    end
    -- S: from the glow's outer corner to the arc center, at most half the
    -- glow's short side. A square corner takes radius 0.
    local halfSize = HalfSide(backdrop)
    local S = E / 2 + cornerRadius
    if halfSize and S > halfSize then
        S = halfSize
    end
    local cornerList = state.corners
    local lvl = backdrop:GetFrameLevel()
    if glowTex.S ~= S or glowTex.E ~= E or glowTex.half ~= halfSize or glowTex.lvl ~= lvl or glowTex.corners ~= cornerList then
        glowTex.S, glowTex.E, glowTex.half, glowTex.lvl, glowTex.corners = S, E, halfSize, lvl, cornerList
        f:ClearAllPoints()
        f:SetAllPoints(backdrop)
        f:SetFrameLevel(lvl)
        local filePath, size, inset, crop, run, band = GlowPiece(S, E, halfSize)
        local sPath, sSize, sInset, sCrop, sRun
        if cornerList ~= ALL_CORNERS then
            local sS = E / 2
            if halfSize and sS > halfSize then
                sS = halfSize
            end
            sPath, sSize, sInset, sCrop, sRun = GlowPiece(sS, E, halfSize)
        end
        local runs = glowTex.runs
        if not runs then
            runs = {}
            glowTex.runs = runs
        end
        for idx = 1, 4 do
            local c, t = CORNERS[idx], glowTex.corner[idx]
            local p, sz, ins, cr = filePath, size, inset, crop
            runs[idx] = run
            if bit.band(cornerList, c.bit) == 0 then
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
        local e, o = glowTex.edge, (E - band) / 2
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
    local r, g, b, a = backdrop:GetBackdropBorderColor()
    for idx = 1, 4 do
        glowTex.corner[idx]:SetVertexColor(r, g, b, a)
        glowTex.edge[idx]:SetVertexColor(r, g, b, a)
    end
    backdrop:SetAlpha(0)
    f:Show()
    glowTex.on = true
end

-------------------------------------------------------------------------------
--  Passes
-------------------------------------------------------------------------------
local Refit

-- Everything this owner added comes off; the state stays for the next time.
local function Clear(state)
    local m, masked = state.mask, state.masked
    for texture in pairs(masked) do
        RemoveMask(texture, m)
    end
    wipe(masked)
    state.kRadius = nil
    SolidOff(state)
    GlowOff(state)
    if state.border then
        byBorder[state.border] = nil
    end
    if state.clip then
        state.clip:SetClipsChildren(true)
        state.clip = nil
    end
    state.on = nil
    CludesUI.RegisterPxReapply(state.owner, nil)
end

local function OnBorderColor(borderFrame, r, g, b, a)
    local state = byBorder[borderFrame]
    if not state then
        return
    end
    a = a or 1
    local shadow = state.solid
    if shadow and shadow.on then
        shadow.fill:SetVertexColor(r, g, b, a)
    end
    local glowTex = state.glow
    if glowTex and glowTex.on then
        for idx = 1, 4 do
            glowTex.corner[idx]:SetVertexColor(r, g, b, a)
            glowTex.edge[idx]:SetVertexColor(r, g, b, a)
        end
    end
end
CludesUI.RoundedBorderColor = OnBorderColor

-- The scale-dependent half of a pass: the radius the shape allows, what the
-- border draws now (Solid strips, a glow backdrop, or nothing) and the body
-- mask's radius inside the strips.
local function Fit(state)
    local edgeTex, rectTex = state.border, state.rect
    local cornerRadius = state.radius
    -- A radius-r mask is 2r + 1 texels square, and the client shrinks a sliced
    -- texture's corners on a region smaller than the texture: the radius stays
    -- at most (short side - 1) / 2, so the region always holds its mask.
    local halfSize = HalfSide(rectTex)
    if halfSize and halfSize >= 1 then
        local cap = max(1, floor(halfSize - 0.5))
        if cornerRadius > cap then
            cornerRadius = cap
        end
    end
    -- A border frame that is the owner itself hides along with the body, so
    -- its own shown flag says nothing (a nameplate cast bar between casts).
    local container = edgeTex and (edgeTex == state.owner or edgeTex:IsShown()) and CludesUI.PP.GetBorders(edgeTex)
    local edge = container and container._top and container:IsShown() and container._top:IsShown() and container._snapEdge or 0
    local innerTex = cornerRadius
    if edge > 0 then
        -- Strip width in shape units (the container may run its own scale).
        local cs, rs = container:GetEffectiveScale(), rectTex:GetEffectiveScale()
        if rs > 0 then
            edge = edge * cs / rs
        end
        innerTex = max(1, floor(cornerRadius - edge + 0.5))
        -- The inner rect holds the hole's and the body's masks the same way:
        -- past it their corners shrink or overlap and square their ends off,
        -- so a thin bar's body would poke out past the ring.
        if halfSize then
            local cap = floor(halfSize - edge - 0.5)
            if cap >= 1 and innerTex > cap then
                innerTex = cap
            end
        end
        return cornerRadius, innerTex, container, nil
    end
    local backdrop = edgeTex and CludesUI._bdBorderData[edgeTex]
    local glowFrame = state.glowStyle and backdrop and backdrop:IsShown() and backdrop or nil
    return cornerRadius, innerTex, nil, glowFrame
end

local function Paint(state, cornerRadius, innerTex, container, glowFrame)
    if container then
        SolidOn(state, container, cornerRadius, innerTex)
    else
        SolidOff(state)
    end
    if glowFrame then
        GlowOn(state, state.border, glowFrame, cornerRadius)
    else
        GlowOff(state)
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
local function DropStale(ownerFrame, state)
    if not state or state.poolGen == PoolDress(ownerFrame) then
        return state
    end
    if state.on then
        SolidOff(state)
        local managed = POOL.Managed
        local glowTex = state.glow
        if glowTex and glowTex.on and glowTex.bd and not (managed and managed(glowTex.bd)) then
            glowTex.bd:SetAlpha(1)
        end
        local clip = state.clip
        if clip and not (managed and managed(clip)) then
            clip:SetClipsChildren(true)
        end
        CludesUI.RegisterPxReapply(ownerFrame, nil)
    end
    if state.border and byBorder[state.border] == state then
        byBorder[state.border] = nil
    end
    status[ownerFrame] = nil
    return nil
end

-- The pixel grid moved: the strips and the glow edge took new sizes, the
-- body textures stay the same.
Refit = function(ownerFrame)
    local state = DropStale(ownerFrame, status[ownerFrame])
    if not (state and state.on) then
        return
    end
    local cornerRadius, innerTex, container, glowFrame = Fit(state)
    ReseatMask(state, innerTex, container)
    Paint(state, cornerRadius, innerTex, container, glowFrame)
end

function CludesUI.RoundCorners(ownerFrame, cornerRadius, options)
    if not ownerFrame then
        return
    end
    local state = DropStale(ownerFrame, status[ownerFrame])
    cornerRadius = min(floor(tonumber(cornerRadius) or 0), MAX_RADIUS)
    options = options or EMPTY
    local style = options.style or "solid"
    if cornerRadius > 0 and not STYLE_OK[style] then
        cornerRadius = 0
    end
    local cornerList = options.corners and floor(tonumber(options.corners) or ALL_CORNERS) % 16 or ALL_CORNERS
    if cornerList == 0 then
        cornerRadius = 0
    end
    if cornerRadius <= 0 then
        if state and state.on then
            Clear(state)
        end
        return
    end
    if not state then
        state = { owner = ownerFrame, masked = {}, gen = 0, poolGen = PoolDress(ownerFrame) }
        status[ownerFrame] = state
    end
    if not hooked then
        hooked = true
        hooksecurefunc(CludesUI, "SetBorderStyleColor", OnBorderColor)
    end
    state.radius, state.corners = cornerRadius, cornerList
    state.glowStyle = style == "glow" or style == "shadow"
    local rectTex = options.rect or ownerFrame
    if state.rect ~= rectTex then
        state.rect = rectTex
        state.kRadius = nil
    end
    local edgeTex = options.border
    if state.border ~= edgeTex then
        if state.border then
            byBorder[state.border] = nil
        end
        state.border = edgeTex
        state.kRadius = nil
    end
    if edgeTex then
        byBorder[edgeTex] = state
    end
    local clip = options.clip
    if state.clip ~= clip then
        if state.clip then
            state.clip:SetClipsChildren(true)
        end
        if clip then
            clip:SetClipsChildren(false)
        end
        state.clip = clip
    end
    local roots = options.roots
    if not roots then
        roots = state.ownRoots
        if not roots then
            roots = { ownerFrame }
            state.ownRoots = roots
        end
    end
    local r, innerTex, container, glowFrame = Fit(state)
    MaskBody(state, roots, options.textures or EMPTY, innerTex, container, edgeTex)
    Paint(state, r, innerTex, container, glowFrame)
    if not state.on then
        state.on = true
        CludesUI.RegisterPxReapply(ownerFrame, Refit)
    end
end

-- A RoundCorners pass with only opts.corners changed: the body keeps its
-- textures, so the mask is reshaped in place (Refit) instead of walked again.
-- A body texture left without the mask needs the walk's retry: full pass.
function CludesUI.RoundedSetCorners(ownerFrame, cornerList)
    local state = ownerFrame and DropStale(ownerFrame, status[ownerFrame])
    if not (state and state.on) or state.missed then
        return false
    end
    cornerList = cornerList and floor(tonumber(cornerList) or ALL_CORNERS) % 16 or ALL_CORNERS
    if cornerList == 0 then
        return false
    end
    state.corners = cornerList
    if state.border then
        byBorder[state.border] = state
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
local function SeatLayer(L, drawLayer, key)
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
    drawLayer:ClearAllPoints()
    drawLayer:SetPoint("TOPLEFT", p, "TOPLEFT", l, t)
    drawLayer:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", r, b)
end

local function FitLayer(L)
    local drawLayer = L._frame
    if L.gen ~= PoolDress(drawLayer) then
        layers[drawLayer] = nil
        return
    end
    local px = CludesUI.PP.perfect
    if L.px ~= px then
        L.px = px
        drawLayer:SetScale(px)
    end
    local key = L.parent:GetEffectiveScale() / px
    if key > 0 then
        SeatLayer(L, drawLayer, key)
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
    local drawLayer = POOL.CreateFrame("Frame", nil, hostFrame)
    drawLayer:SetIgnoreParentScale(true)
    drawLayer:SetAllPoints(hostFrame)
    drawLayer:SetFrameLevel(hostFrame:GetFrameLevel() + 1)
    drawLayer:EnableMouse(false)
    local L = { _frame = drawLayer, parent = hostFrame, fit = fit, gen = PoolDress(drawLayer), Fit = FitLayer }
    layers[drawLayer] = L
    drawLayer:SetScript("OnShow", LayerOnShow)
    newLayers[#newLayers + 1] = L
    if not newQueued then
        newQueued = true
        C_Timer.After(0, FitNewLayers)
    end
    return L
end

-- A Window Scale change: the shown layers re-fit once the panel settles.
local function RefitLayers()
    for drawLayer, L in pairs(layers) do
        if drawLayer:IsVisible() then
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
local function HouseRadius(halfSize)
    return (halfSize and halfSize * 2 >= PANEL_SIDE) and OUTLINE_RADIUS or CONTROL_RADIUS
end

local function OutlineSetColor(self, r, g, b, a)
    self._fill:SetVertexColor(r, g, b, a or 1)
end

-- o:SetCover(r, g, b): an opaque fill in the colour the control sits on,
-- under the outline, over its band and the corners outside it. A control of
-- stacked layers drawn square below it then reads rounded with its edge
-- blended once, where masks on each layer let the lower ones show through.
local function OutlineSetCover(self, r, g, b)
    local coverTex = self.cover
    if not coverTex then
        coverTex = self._frame:CreateTexture(nil, "BORDER", nil, 6)
        coverTex:SetAllPoints(self._frame)
        self.cover = coverTex
        if self.r then
            AddMask(coverTex, self.hole)
        end
    end
    coverTex:SetColorTexture(r, g, b, 1)
end

-- The radius in whole pixels from the parent's scale (at most what the height
-- holds) and the body's radius in the parent's units.
local function FitOutline(o, key)
    local hostFrame = o.parent
    local halfSize = HalfSide(hostFrame)
    -- No radius named: the house corner for this size, read at each fit (the
    -- parent may not have been laid out when the outline was made).
    if o.autoRadius then
        o.radius = HouseRadius(halfSize)
    end
    local r = floor(o.radius * key + 0.5)
    if halfSize then
        local cap = floor(halfSize * key - 0.5)
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
        local fillTex, cutout, coverTex = o._fill, o.hole, o.cover
        if o.r then
            RemoveMask(fillTex, cutout)
            if coverTex then
                RemoveMask(coverTex, cutout)
            end
        end
        o.r = r
        SetRounded(fillTex, r, ALL_CORNERS)
        local innerTex = r - wid
        cutout:SetTexture(ROUNDED_INV[innerTex * 16 + ALL_CORNERS], "CLAMPTOWHITE", "CLAMPTOWHITE")
        cutout:SetTextureSliceMargins(innerTex, innerTex, innerTex, innerTex)
        cutout:SetTextureSliceMode(STRETCHED)
        AddMask(fillTex, cutout)
        if coverTex then
            AddMask(coverTex, cutout)
        end
    end
    local bm = o.bodyMask
    if bm then
        local br = o.radius
        if halfSize then
            local cap = floor(halfSize - 0.5)
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
local cMask, cornerSet, cOwner
local artWaiting
local ClipFrame
local function ClipRegions(...)
    for idx = 1, select("#", ...) do
        local region = select(idx, ...)
        if region:GetObjectType() == "Texture" then
            local g = PoolDress(region) or 0
            if region.IsObjectLoaded and not region:IsObjectLoaded() then
                if cornerSet[region] == g then
                    RemoveMask(region, cMask)
                    cornerSet[region] = nil
                end
                if not artWaiting then
                    artWaiting = setmetatable({}, WEAK_K)
                end
                artWaiting[region] = cOwner
            elseif cornerSet[region] ~= g and AddMask(region, cMask) then
                cornerSet[region] = g
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
    cMask, cornerSet, cOwner = o.innerMask, o.clipped, o
    ClipScrolls(o.parent:GetChildren())
    cMask, cornerSet, cOwner = nil, nil, nil
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
            local drawLayer = o._frame
            if layers[drawLayer] == o and drawLayer:IsVisible() then
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
        local drawLayer = o._frame
        if layers[drawLayer] ~= o or not drawLayer:IsVisible() then
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
    local innerMask = o.innerMask
    if not innerMask then
        local p = o.parent
        innerMask = p:CreateMaskTexture()
        innerMask:SetPoint("TOPLEFT", p, "TOPLEFT", 1, -1)
        innerMask:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -1, 1)
        SetRounded(innerMask, max(1, o.radius - 1), ALL_CORNERS, "CLAMPTOBLACKADDITIVE")
        o.innerMask = innerMask
    end
    return innerMask
end

function CludesUI.MakeRoundedBorder(hostFrame, r, g, b, a, body, cornerRadius, clip, width)
    local o = CludesUI.MakePixelLayer(hostFrame, FitOutline)
    local drawLayer = o._frame
    local fillTex = drawLayer:CreateTexture(nil, "BORDER", nil, 7)
    fillTex:SetAllPoints(drawLayer)
    fillTex:SetVertexColor(r or 0, g or 0, b or 0, a or 1)
    -- One unit is one pixel on the layer: width px in from every edge.
    local wid = width or 1
    o.width = wid
    local cutout = drawLayer:CreateMaskTexture()
    cutout:SetPoint("TOPLEFT", drawLayer, "TOPLEFT", wid, -wid)
    cutout:SetPoint("BOTTOMRIGHT", drawLayer, "BOTTOMRIGHT", -wid, wid)
    o._fill, o.hole, o.SetColor, o.SetCover = fillTex, cutout, OutlineSetColor, OutlineSetCover
    -- A clipped outline is a list or a menu: a panel.
    o.radius = cornerRadius or (clip and OUTLINE_RADIUS or CONTROL_RADIUS)
    o.autoRadius = (cornerRadius == nil and not clip) or nil
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
function CludesUI.RoundBody(hostFrame, body, cornerRadius)
    local halfSize = HalfSide(body)
    cornerRadius = cornerRadius or HouseRadius(halfSize)
    if halfSize and halfSize > 1 then
        local cap = floor(halfSize - 0.5)
        if cornerRadius > cap then
            cornerRadius = cap
        end
    end
    if cornerRadius < 1 then
        return
    end
    local m = hostFrame:CreateMaskTexture()
    m:SetAllPoints(body)
    SetRounded(m, cornerRadius, ALL_CORNERS, "CLAMPTOBLACKADDITIVE")
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
    local accent, alphaMask = o.accent, o.accentMask
    if o.r and o.ar ~= o.r then
        if o.ar then
            RemoveMask(accent, alphaMask)
        end
        o.ar = o.r
        SetRounded(alphaMask, o.r - 1, ALL_CORNERS, "CLAMPTOBLACKADDITIVE")
        MaskWhenLoaded(accent, alphaMask)
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
        local drawLayer = o._frame
        local accent = drawLayer:CreateTexture(nil, "BORDER", nil, 6)
        accent:SetPoint("TOPLEFT", drawLayer, "TOPLEFT", 1, -1)
        accent:SetPoint("BOTTOMLEFT", drawLayer, "BOTTOMLEFT", 1, 1)
        local alphaMask = drawLayer:CreateMaskTexture()
        alphaMask:SetPoint("TOPLEFT", drawLayer, "TOPLEFT", 1, -1)
        alphaMask:SetPoint("BOTTOMRIGHT", drawLayer, "BOTTOMRIGHT", -1, 1)
        o.accent, o.accentMask, o.accentH, o.fit = accent, alphaMask, accentH, FitCard
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
    for _, side in ipairs({ "LEFT", "RIGHT" }) do
        local e = Line(0.10)
        e:SetPoint("TOP" .. side)
        e:SetPoint("BOTTOM" .. side)
        e:SetWidth(1)
    end
    local bottom = Line(0.10)
    bottom:SetPoint("BOTTOMLEFT")
    bottom:SetPoint("BOTTOMRIGHT")
    bottom:SetHeight(1)
end
