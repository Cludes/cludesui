if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
--------------------------------------------------------------------------------
--  CUI_MythicTimer_KickPlates.lua
--  Kick Tracker (Mythic+ Tools), the nameplate icon: when an enemy's cast is
--  kicked, an icon on that enemy's nameplate shows who kicked it, with a
--  cooldown swipe and a countdown for their interrupt (from the kick engine's
--  model: from each member's class, spec and talents, your own included).
--  Each kicker has one icon: it stays on the enemy they kicked last until
--  that enemy's plate goes, and moves when they kick another; your own moves
--  the moment you cast. Once the cooldown ends the icon stays, plain.
--  The icon is the kicker's spec icon, their interrupt's icon or their class
--  icon (Icon setting).
--
--  A kick the engine cannot place on a member (inside a key the game hides
--  who kicked, and the engine never guesses) still shows, as a ghost: an
--  icon-like frame on the kicked plate that takes a slot like an icon on
--  cooldown, holding one cell per member who could have kicked. Each cell
--  sits behind its own gate: a hidden status bar fed that member's interrupt
--  count before and after the meter's update (hidden in combat), whose fill
--  is whole unless the count rose, and a clip hung from the fill's edge that
--  opens over the cell only while the fill is short. So the cell that shows
--  is the member whose count rose, and Lua never learns which. A ghost lasts
--  while the longest of its members' cooldowns from the kick could still
--  run, then goes; a live icon stays until its mob's plate goes. A later
--  sure kick of a member takes that member's cell out of the older ghosts.
--  When its plate goes, a ghost waits for its mob as a live icon does
--  (below), its span still running.
--
--  A kick the engine could not place leaves the kicker's earlier icon where
--  it was, since Lua never learns whose cell opened: their live icon from a
--  sure kick, their cell in an older ghost, or their marker lane would show
--  beside the ghost that holds their kick (a kicker twice on one plate, one
--  plain, one with the cooldown). So every such element also sits behind a
--  count gate of its own (the Count gates section): a hidden status bar fed
--  the member's count when the element was placed as its value and their
--  count as read at every meter update as its maximum, with a clip open over
--  the element only while that fill is whole. The element hides, by the
--  engine alone, once their count has risen past the one it was placed at:
--  they interrupted again. A live icon's and a ghost cell's gate keep their
--  baseline (the icon is superseded for good); a lane, a default rather
--  than a kick, takes its baseline from the oldest ghost still holding the
--  member's cell and comes back once every such ghost is gone. A gate is
--  fed only while the element's own cooldown cannot still be running (the
--  engine's own measure), so a grip while down never cuts a running
--  cooldown's display: it can only drop a plain residue.
--
--  The icon is a cell of the aura kit (the look of the aura icons: a 1 px
--  border, the swipe, the countdown text in the module font), registered as
--  style "mt:kick" so a settings change restyles every live icon. Several
--  kickers on one enemy sit in a row growing away from the plate, the ones
--  whose kick is ready nearest it, marker defaults and ghosts included
--  (LayoutPlate; a ghost always sits with the ones on cooldown).
--
--  Secret discipline: a kicker the engine names is a plain group unit, so
--  its spec, kick, class, colour and cooldown are plain; a class token the
--  engine could not read goes only into SetFormattedText (the inline class
--  icon), never compared, concatenated or keyed, and the border stays black.
--  Icons live in the nameplate tree, where nothing can be measured: layout is
--  SetPoint only, from plain profile numbers, and the icon renders at
--  UIParent's scale so its sizes land on whole pixels. On an CludesUI plate
--  whose aura row (debuffs, buffs or crowd control) sits on the icon's side,
--  the icon sits past that row's outer edge, which only the engine knows (the
--  shown counts are hidden): an edge frame of ours in the plate's own units
--  hangs from the row's bottom outer corner, level with the bar's centre, as
--  the nameplate module's target arrows hug a row, and the icon hangs from
--  it. An aura container may be anchored to only by an object born with the
--  arrows' aspect, so the park every icon and edge is born under carries it.
--
--  A plate goes away when its mob leaves the view or the nameplate range (and
--  with Alt-Z), and comes back as a new token. Two things can say the new
--  plate is the same mob: its GUID, where that is plain (an NPC's is hidden
--  on restricted maps), and the player's target: UnitIsUnit may compare
--  "target" with a plate token on any map, so an icon whose mob was the
--  player's target when its plate left waits, and comes back with the next
--  plate that is the target, unless the target changes meanwhile. A hidden
--  token cannot be handed to GetNamePlateForUnit, so nothing else can find a
--  mob again; the other icons wait for their kicker's next kick.
--
--  Zero cost while off: nothing is registered and no icon is built until the
--  feature is enabled; the engine runs only while this display (or the bars)
--  subscribes, and the plate events only while the Where to Show filter lets
--  it. One hidden driver follows plates, shown only while an icon is up.
--
--  The options page's header preview is two of these cells on a mock plate
--  (ns.KT_PaintSampleIcon): built once, kept outside the icon pool, dressed by
--  the same style and paint passes, with only the engine-run swipe and
--  countdown moving.
--------------------------------------------------------------------------------
local ADDON_NAME, mod = ...

local MTWhere, KE, KD = mod.MTWhere, mod.KickEngine, CludesUI.KickData
if not (MTWhere and KE and KD) then
    return
end

local saved -- Lite DB handle, handed over by ns.KT_OnEnable

local function Cfg()
    local p = saved and saved.profile
    return p and p.kickTracker
end

local pairs, next, type, pcall, tonumber = pairs, next, type, pcall, tonumber
local floor, ceil, max, min, format = math.floor, math.ceil, math.max, math.min, string.format
local GetTime = GetTime
local Pix = CludesUI.PP

local Secret, PlainString = CludesUI.IsSecret, CludesUI.PlainString

--------------------------------------------------------------------------------
--  Constants
--------------------------------------------------------------------------------
local STYLE = "mt:kick"
local FONT_KEY = "mythicTimer"
local BORDER_PX = 1 -- the aura icons' plain border
local TICK = 0.2 -- driver pass interval
local DEDUPE = 0.1 -- a second report for the same kicker on the same plate inside this is the same kick
local ICON_GAP = 2 -- pixels between icons sharing a plate
local ICON_ZOOM = 0.08 -- the aura icons' crop, each side
local PREVIEW_CD = 15 -- sample cooldown length
local PREVIEW_REST = 4 -- seconds a sample sits ready before it kicks again

local NEUTRAL = 0.55 -- grey border for a kicker without a class

local PAW_ATLAS = "paw-icon"

-- Blizzard's square class icons, one file per class token, drawn as an inline
-- texture whose path the engine formats from the (possibly secret) class
-- token. The icon string sits on a holder at scale 1, so its inline size is in
-- scale-1 units on any plate, and covers the area inside the border. An inline
-- texture's drawn size also follows the string's font size (about size x
-- font size / 12 units), so the icon string keeps one font size and its
-- inline size comes from what a string of that font size lays out
-- (InlineFactor). Inline sizes and texcoords are whole numbers, so the icon
-- overfills the area a little and its texcoords widen to match: the area
-- shows the art's middle ART_CROP of 64 texels (the icons have a 4-texel
-- baked frame), less the aura icons' zoom. The icon font is plain, with no
-- shadow (a shadow would draw a dark copy).
local ICON_FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local ICON_SIZE = 6 -- the icon string's font size; small, so the icon always sets the line height
local ICON_FMT = "|TInterface\\Icons\\ClassIcon_%%s:%d:%d:0:0:64:64:%d:%d:%d:%d|t"
local ICON_OVER = 1 -- physical pixels the icon overfills its area by at least; the clip trims it
local ART_CROP = 56 -- texels of 64 inside the icons' baked frame
local MEASURE_FMT = "|TInterface\\Icons\\ClassIcon_WARRIOR:%d:%d|t"
local MEASURE_H = 64 -- inline size the draw factor is measured at

local MODE_OFF, MODE_LIVE, MODE_PREVIEW = 0, 1, 2

-- The icons' frame level on an CludesUI plate: the top of its flattened
-- render layer (its text sits at 900, its raid marker at 901), and the same
-- height over the game's base nameplate. With Show Above Overlapping
-- Nameplates off, the icons take their host's own strata, so they never
-- leave their plate's layer and never draw over another plate; on (the
-- default), they hang from the lift instead (Lift, EnsurePool, Place).
local PLATE_TOP = 1000

local WHERE_KEY = "kickplates"
local WHERE_KEYS = MTWhere.NewKeySet(KE.WHERE_LIST)

-- Nameplate tokens only. The ordered list walks the plates already on screen.
local NAMEPLATE_UNITS, NAMEPLATE_TOKENS = mod.NAMEPLATE_UNITS, mod.NAMEPLATE_TOKENS

local ANCHORS = { LEFT = true, RIGHT = true, TOP = true, BOTTOM = true }
local ICON_STYLES = { spec = true, kick = true, class = true }

-- Timer text position: a baked edge nudge per corner (the aura icons' own),
-- the user's X/Y on top.
local TEXT_POS = {
    center = { point = "CENTER", nx = 0, ny = 0, justify = "CENTER" },
    topright = { point = "TOPRIGHT", nx = 3, ny = 4, justify = "RIGHT" },
    bottomleft = { point = "BOTTOMLEFT", nx = -3, ny = -4, justify = "LEFT" },
    bottomright = { point = "BOTTOMRIGHT", nx = 3, ny = -4, justify = "RIGHT" },
    topleft = { point = "TOPLEFT", nx = -3, ny = 4, justify = "LEFT" },
}

-- Preview samples: every class token, then a paw (false = no class).
local PREVIEW_CLASSES = {
    "WARRIOR",
    "PALADIN",
    "HUNTER",
    "ROGUE",
    "PRIEST",
    "DEATHKNIGHT",
    "SHAMAN",
    "MAGE",
    "WARLOCK",
    "MONK",
    "DRUID",
    "DEMONHUNTER",
    "EVOKER",
    false,
}
local NUM_PREVIEW = #PREVIEW_CLASSES
local CLASS_IDS = {
    WARRIOR = 1,
    PALADIN = 2,
    HUNTER = 3,
    ROGUE = 4,
    PRIEST = 5,
    DEATHKNIGHT = 6,
    SHAMAN = 7,
    MAGE = 8,
    WARLOCK = 9,
    MONK = 10,
    DRUID = 11,
    DEMONHUNTER = 12,
    EVOKER = 13,
}

local LIVE_EVENTS =
    { "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_TARGET_CHANGED", "RAID_TARGET_UPDATE" }
local PREVIEW_EVENTS = { "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED" }

--------------------------------------------------------------------------------
--  State
--------------------------------------------------------------------------------
local icons = {} -- key -> icon: a kicker's unit, "~" .. plate for a sample
local onPlate = {} -- plate unit -> ordered list of the icons shown on it
local isDetached = {} -- key -> icon whose plate went away (kept for its kicker)
local free = {} -- parked icons, reused forever
local parked -- hidden holder parked icons hang from; built lazily
local watchPark -- hidden holder parked cast watchers hang from (no aspect; EnsurePool)
local rowsOK = false -- the park bears the aspect an object needs to anchor to an aura row (EnsurePool)
local driverFrame -- hidden driver; built lazily
local evt -- event frame; built lazily
local driverAcc = 0
local currentMode = MODE_OFF
local previewing = false -- sample icons forced on the live plates (KT_SetPreview: the harness; no options caller)
local previewStep = 0 -- preview sample counter (class cycle, stagger)
local styleStamp = 0 -- bumped by a settings write and a UI scale change; an icon restyles when its stamp differs
local measureText -- off-screen font string that measures the inline draw factor; built lazily
local liveCount = 0 -- icons on a plate (live or sample)
local plateSeq = 0 -- arrival counter: an icon's `seq` on its plate orders it within its readiness group
local Rails = {} -- marker defaults: a rail per marked plate (the Marker defaults section)
-- Ghosts (the Ghosts section): live = the ghosts on plates and the ones
-- waiting for their mob's plate (nWaiting of them), free = parked ones,
-- reused forever. Nothing is built before the first gate packet.
local Ghosts = { live = {}, free = {}, nWaiting = 0 }
-- Show Above Overlapping Nameplates: `on` is the setting (ReadSettings),
-- `frame` the shown holder under UIParent at STRATA that every placed icon,
-- ghost and rail hangs from while it is on (EnsurePool, Place). A nameplate
-- composites as one unit, so nothing inside one can draw over a neighbouring
-- plate (the module's Raise Strata toggles and Casts In Front of Nameplates
-- leave the plate's render tree for the same reason); an element under the
-- lift still follows its plate through its anchors, with no per-frame work.
local Lift = { STRATA = "HIGH" }

-- The options header's sample: two cells on a mock plate, built once and never
-- in icons, free, onPlate or detached, nor counted in liveCount.
local sampleList = {}
local samplePlate
local SAMPLE_CLASSES = { "WARRIOR", "MAGE" }
local SAMPLE_CD_LEFT = 9 -- seconds left on the second sample's cooldown at each paint
local SAMPLE_PLATE_W, SAMPLE_PLATE_H = 150, 17 -- the mock plate while the nameplate module is off: a typical width, the default bar height

-- Scale snapshot (SyncScale): UIParent's scale, which the icon renders at,
-- and one physical pixel in scale-1 units (PP.perfect) it was taken with; one
-- physical pixel in icon units; the icon format for the current size.
local uiZoom, perfect, onePx, iconFmt

-- Settings snapshot, read by KT_Refresh before any icon can paint.
local iconPx, stackAnchor, sOffX, sOffY, sOthX, sOthY, iconStyle
local sClassBorder, sShowTimer, sTimerSize, sTimerPos, sTimerX, sTimerY, sSwipe, sDesat
local sPawInset

local function ReadSettings(conf)
    iconPx = floor(Clamp(tonumber(conf.size) or 28, 16, 48) + 0.5)
    stackAnchor = ANCHORS[conf.anchor] and conf.anchor or "LEFT"
    sOffX = tonumber(conf.offsetX) or -4
    sOffY = tonumber(conf.offsetY) or 0
    sOthX = tonumber(conf.otherOffsetX) or 0
    sOthY = tonumber(conf.otherOffsetY) or 0
    iconStyle = ICON_STYLES[conf.iconStyle] and conf.iconStyle or "kick"
    sClassBorder = conf.classBorder ~= false
    sShowTimer = conf.showTimer ~= false
    sTimerSize = floor(Clamp(tonumber(conf.timerSize) or 11, 6, 24) + 0.5)
    sTimerPos = TEXT_POS[conf.timerPos] and conf.timerPos or "center"
    sTimerX = tonumber(conf.timerX) or 0
    sTimerY = tonumber(conf.timerY) or 0
    sSwipe = conf.swipe ~= false
    sDesat = conf.desaturate == true
    Lift.on = conf.aboveOverlap ~= false
    sPawInset = floor(iconPx * 0.18 + 0.5)
end

-- Scale-1 units one unit of inline size takes in the icon string (ICON_FONT
-- at ICON_SIZE, as on the icon), read from a string laid out on a scale-1
-- holder under UIParent, where text can be measured. When the read fails, the
-- share seen in game: a twelfth of the font size per unit.
local function InlineFactor()
    if not measureText then
        local holderFrame = CreateFrame("Frame", nil, UIParent)
        holderFrame:SetIgnoreParentScale(true)
        holderFrame:SetScale(1)
        holderFrame:SetSize(1, 1)
        holderFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMRIGHT", 100, -100)
        holderFrame:SetAlpha(0)
        measureText = holderFrame:CreateFontString(nil, "ARTWORK")
        measureText:SetWordWrap(false)
        measureText:SetFont(ICON_FONT, ICON_SIZE, "")
        measureText:SetFormattedText(MEASURE_FMT, MEASURE_H, MEASURE_H)
    end
    local wid = measureText:GetStringWidth()
    if type(wid) ~= "number" or wid <= 0 then
        return ICON_SIZE / 12
    end
    return wid / MEASURE_H
end

-- UIParent's scale, one physical pixel and the icon size; a change (a UI
-- scale or resolution change, or new settings) restyles every icon. Returns
-- whether anything changed.
local function SyncScale(force)
    local ui, px = UIParent:GetEffectiveScale(), Pix.perfect or 1
    if not force and ui == uiZoom and px == perfect then
        return false
    end
    uiZoom, perfect = ui, px
    onePx = px / ui
    -- The area inside the border in physical pixels (the icon as PP.Size
    -- snaps it); the icon's inline size in scale-1 units: what it draws covers
    -- that area plus ICON_OVER pixels, rounded up, and the clip trims the
    -- rest. Texcoords widened by the overfill, centred, inside the aura
    -- icons' zoom: the clip trims the widening back off.
    local innerPx = Pix.Scale(iconPx) / onePx - 2 * BORDER_PX
    if innerPx < 1 then
        innerPx = 1
    end
    local k = InlineFactor()
    local iconH = ceil((innerPx + ICON_OVER) * px / k)
    local isShown = ART_CROP * (1 - 2 * ICON_ZOOM)
    local l = floor(32 - isShown * iconH * k / (px * innerPx) / 2 + 0.5)
    if l < 0 then
        l = 0
    end
    iconFmt = format(ICON_FMT, iconH, iconH, l, 64 - l, l, 64 - l)
    styleStamp = styleStamp + 1
    return true
end

--------------------------------------------------------------------------------
--  Count gates: a hidden status bar (alpha 0, its fill drawing nothing and
--  unsnapped) and a clip frame hung from it. The ghosts' gate opens its clip
--  where the fill falls SHORT (Ghosts.Hang: the clip from the fill's right
--  edge to the gate's right end); the gate every other element carries opens
--  its clip while the fill is WHOLE (Gate.HangWhole: the clip from the gate's left
--  edge to the fill's right edge), the element sitting in the gate's last
--  span, so a fill short by one span at least leaves it outside the clip. A
--  gate is Gate.SPAN spans wide, each span the cell, a margin on either side
--  (the countdown may sit past the cell: Gate.Margin) and 4 units, so a count
--  up to Gate.SPAN moves the fill a whole span at least. Fed (Gate.FeedWhole) the
--  count at the element's placing as its value and the latest as its
--  maximum, from the engine's counts event, hidden in combat and never read;
--  a count from an older fight is no baseline (Gate.Base: 0, so any
--  interrupt of the member in this fight hides the element).
--------------------------------------------------------------------------------
local Gate = {}
Gate.SPAN = 100 -- gate width in spans: counts up to this many move the fill by a span at least

-- How far a gate reaches past its cell on every side, in the cell's units:
-- the countdown may sit past the cell by a corner's baked nudge (up to 4
-- units) and the Timer X/Y offsets, and a timer font larger than the icon
-- spills round it; twice the font size covers its widest digits.
function Gate.Margin()
    return 2 * (sTimerSize or 11) + math.abs(sTimerX or 0) + math.abs(sTimerY or 0) + 4
end

-- The gate's size and place about `about` (the frame the cell fills) for the
-- cell width `cw`: the cell and its margin on every side, Gate.SPAN of those
-- wide, its right edge 2 units past the margin's. The clip is hung again
-- after this, since the fill's edge moved with the gate.
function Gate.Size(gateRec, about, cellW)
    local m = Gate.Margin()
    gateRec:SetSize(Gate.SPAN * (cellW + 2 * m + 4), cellW + 2 * m)
    gateRec:ClearAllPoints()
    gateRec:SetPoint("RIGHT", about, "RIGHT", m + 2, 0)
end

function Gate.New(hostFrame)
    local gateRec = CreateFrame("StatusBar", nil, hostFrame)
    gateRec:EnableMouse(false)
    gateRec:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    local fillTex = gateRec:GetStatusBarTexture()
    fillTex:SetVertexColor(0, 0, 0, 0)
    if fillTex.SetSnapToPixelGrid then
        fillTex:SetSnapToPixelGrid(false)
        fillTex:SetTexelSnappingBias(0)
    end
    gateRec:SetAlpha(0)
    gateRec:SetMinMaxValues(0, 1)
    gateRec:SetValue(1)
    return gateRec, fillTex
end

function Gate.NewClip(hostFrame)
    local clipFrame = CreateFrame("Frame", nil, hostFrame)
    clipFrame:SetClipsChildren(true)
    clipFrame:EnableMouse(false)
    return clipFrame
end

-- The clip open while the fill is whole: from the gate's left edge to the
-- fill's right edge, hung again after every feed so it never keeps the edge
-- of a fill that moved.
function Gate.HangWhole(clipFrame, fillTex, gateRec)
    clipFrame:ClearAllPoints()
    clipFrame:SetPoint("TOPLEFT", gateRec, "TOPLEFT", 0, 0)
    clipFrame:SetPoint("BOTTOMLEFT", gateRec, "BOTTOMLEFT", 0, 0)
    clipFrame:SetPoint("TOPRIGHT", fillTex, "TOPRIGHT", 0, 0)
    clipFrame:SetPoint("BOTTOMRIGHT", fillTex, "BOTTOMRIGHT", 0, 0)
end

-- The count at the element's placing as the value, the latest as the
-- maximum: whole while the count did not move, short once it rose.
function Gate.FeedWhole(gateRec, fillTex, clipFrame, base, current)
    gateRec:SetMinMaxValues(0, current)
    gateRec:SetValue(base)
    Gate.HangWhole(clipFrame, fillTex, gateRec)
end

-- Whole from plain values: the element shows.
function Gate.ResetWhole(gateRec, fillTex, clipFrame)
    gateRec:SetMinMaxValues(0, 1)
    gateRec:SetValue(1)
    Gate.HangWhole(clipFrame, fillTex, gateRec)
end

-- A hidden element must not keep its slot either (the owner's blank spot,
-- 2026-10-22), and only the engine knows it is hidden, so the row is not
-- laid out by slot numbers: every element hangs from the END of the one
-- before it, and a pooled icon's end (and a ghost's) sits one pitch on only
-- while it shows. A step pair: two bars one slot pitch wide chained edge to
-- edge from a point of the row (AnchorStep), the first at that point, the
-- second at the first's fill edge, the pair's end the second's fill edge:
-- one pitch on, plus the first's fill, less the second's. Fed one range and
-- two values (FeedStep), the pair advances a pitch times 1 + f(v1) - f(v2),
-- f a bar's fill share of its range, clamped. With an element's count when
-- it was placed as the floor, the latest as the ceiling and the values
-- (floor, ceiling): a pitch while the count did not move (both bars draw
-- whatever the engine draws for an empty range, and cancel) and nothing
-- once it rose (the first draws nothing, the second a whole fill), so the
-- slot collapses exactly with the count gate's clip. Other value orders
-- give 1 + [rose] or 1 - [rose], for a chain summing conditions whose
-- fixed length a plain offset undoes (Ghosts.Chain). A bar of a chain:
-- a standard or a reverse fill (set before the texture, which a fill style
-- change re-mints), drawing nothing, the fill unsnapped like the gates'.
function Gate.NewBar(hostFrame, reverse)
    local barFrame = CreateFrame("StatusBar", nil, hostFrame)
    barFrame:EnableMouse(false)
    if reverse then
        barFrame:SetFillStyle(Enum.StatusBarFillStyle.Reverse)
    end
    barFrame:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    local fillTex = barFrame:GetStatusBarTexture()
    fillTex:SetVertexColor(0, 0, 0, 0)
    if fillTex.SetSnapToPixelGrid then
        fillTex:SetSnapToPixelGrid(false)
        fillTex:SetTexelSnappingBias(0)
    end
    barFrame:SetMinMaxValues(0, 1)
    barFrame:SetValue(0)
    return barFrame, fillTex
end

function Gate.NewStep(hostFrame)
    local std, stdFill = Gate.NewBar(hostFrame, false)
    local rev, revFill = Gate.NewBar(hostFrame, true)
    return { std = std, stdFill = stdFill, rev = rev, revFill = revFill }
end

function Gate.SizeStep(plateRow, pitch, cellW)
    plateRow.std:SetSize(pitch, cellW)
    plateRow.rev:SetSize(pitch, cellW)
end

function Gate.ShowStep(plateRow, isShown)
    plateRow.std:SetShown(isShown)
    plateRow.rev:SetShown(isShown)
end

-- Anchors the pair from (from, fromPoint, offset) in the row's direction
-- and returns its end: a fill and the point of it the next thing hangs
-- from. The reverse bar leads leftward and trails rightward, so the first
-- bar's fill edge faces the second whichever way the row grows.
function Gate.AnchorStep(plateRow, from, fromPoint, off, goesLeft)
    local firstPlate, firstFill, secondary, secondFill
    if goesLeft then
        firstPlate, firstFill, secondary, secondFill = plateRow.rev, plateRow.revFill, plateRow.std, plateRow.stdFill
    else
        firstPlate, firstFill, secondary, secondFill = plateRow.std, plateRow.stdFill, plateRow.rev, plateRow.revFill
    end
    firstPlate:ClearAllPoints()
    secondary:ClearAllPoints()
    if goesLeft then
        firstPlate:SetPoint("RIGHT", from, fromPoint, off, 0)
        secondary:SetPoint("RIGHT", firstFill, "LEFT", 0, 0)
        return secondFill, "RIGHT"
    end
    firstPlate:SetPoint("LEFT", from, fromPoint, off, 0)
    secondary:SetPoint("LEFT", firstFill, "RIGHT", 0, 0)
    return secondFill, "LEFT"
end

-- The pair's first bar v1 and its second v2 over the range (lo, hi).
function Gate.FeedStep(plateRow, lo, hi, v1, v2, goesLeft)
    local firstPlate, secondary
    if goesLeft then
        firstPlate, secondary = plateRow.rev, plateRow.std
    else
        firstPlate, secondary = plateRow.std, plateRow.rev
    end
    firstPlate:SetMinMaxValues(lo, hi)
    firstPlate:SetValue(v1)
    secondary:SetMinMaxValues(lo, hi)
    secondary:SetValue(v2)
end

-- One pitch from plain values.
function Gate.ResetStep(plateRow, goesLeft)
    Gate.FeedStep(plateRow, 0, 1, 0, 0, goesLeft)
end

-- Where the next element of a row hangs from after `e`: a fill, the point
-- of it and a plain offset along the row (a ghost's chain undoes its fixed
-- length with it).
function Gate.ElementEnd(e)
    return e.endFill, e.endPoint, e.endOffset or 0
end

-- A pooled icon's count gate and its step pair, fed together: the clip
-- closes and the slot collapses on the same rise.
function Gate.FeedIconGate(b, base, current)
    Gate.FeedWhole(b.gate, b.fill, b.clip, base, current)
    Gate.FeedStep(b.step, base, current, base, current, stackAnchor == "LEFT")
end

function Gate.ResetIconGate(b)
    Gate.ResetWhole(b.gate, b.fill, b.clip)
    Gate.ResetStep(b.step, stackAnchor == "LEFT")
end

-- A baseline count taken in the fight `gen`: as it is in this fight, 0 from
-- an older one (the counts restarted since).
function Gate.Base(base, gen)
    if gen == KE.FightGen() then
        return base
    end
    return 0
end

-- A pooled icon's gate fed again as it was (the icon moved, and the fill's
-- edge with it), or whole while it was never fed.
function Gate.RefeedIcon(b)
    if b.cCur ~= nil then
        Gate.FeedIconGate(b, Gate.Base(b.cBase, b.cGen), b.cCur)
    else
        Gate.ResetIconGate(b)
    end
end

-- Whether a kick at `startAt` could still hold member u's interrupt down at
-- T, by the engine's own measure (KE.DownFor less its slack; the element's
-- own cooldown length where the engine knows none): a gate is fed only past
-- it, so nothing the count does while a member cannot kick (a grip of a
-- caster) ever cuts a running cooldown's display.
function Gate.StillDownAt(unit, startAt, duration, T)
    if not startAt then
        return false
    end
    local cd = KE.DownFor(unit) or duration
    return cd ~= nil and T - startAt < cd - KE.ELIM_SLACK
end

-- Member u's live icon fed their count as read at T: placed by a counted
-- kick with their count read at it (a sample never is; a kick whose count
-- could not be read keeps no gate, unless the fight moved since), and only
-- once that kick's cooldown is over.
function Gate.FeedIcon(b, unit, current, T)
    if b.cGen == nil or (b.cBase == nil and b.cGen == KE.FightGen()) then
        return
    end
    if Gate.StillDownAt(unit, b.cdStart, b.cdDur, T) then
        return
    end
    b.cCur = current
    Gate.FeedIconGate(b, Gate.Base(b.cBase, b.cGen), current)
end

--------------------------------------------------------------------------------
--  Unit tests: hostility and where the icon hangs.
--------------------------------------------------------------------------------
-- Only CLEANLY-friendly plates are skipped. The attackable flag can be SECRET
-- in instanced combat; a secret answer counts as hostile, never branched on.
local function IsHostile(unitToken)
    local success, att = pcall(UnitCanAttack, "player", unitToken)
    if success and not Secret(att) and att == false then
        return false
    end
    return true
end

-- The nameplate module's plate registry (unit token -> its plate frame), or
-- nil while that module is off. Mythic+ Tools loads first, so this is read at
-- use, never at load.
local function NPPlates()
    local reg = CludesUI._ModuleNS
    local m = reg and reg.CludesUINameplates
    return m and m.plates
end

-- The side ("LEFT" / "RIGHT") the nameplate module's Full Sized cast icon
-- takes beside the bars during a cast, or nil while it is not in use.
local function FullIconSide()
    local reg = CludesUI._ModuleNS
    local m = reg and reg.CludesUINameplates
    if not (m and m.GetShowCastIcon() and m.GetCastIconFullSize()) or m.NP_Classic() then
        return nil
    end
    return m.GetCastIconOnRight() and "RIGHT" or "LEFT"
end

-- The nameplate module's target arrows hug the outermost icon on their side
-- (SideGuest, through its ns.NP_AddSideGuest): once the icons on an
-- CludesUI plate changed, the arrows are placed again. A no-op unless that
-- plate shows them (the player's target).
local function ArrowsFollow(backing)
    if not (backing and backing.leftArrow) then
        return
    end
    local reg = CludesUI._ModuleNS
    local m = reg and reg.CludesUINameplates
    if m and m.PositionArrowsOutsideAuras then
        m.PositionArrowsOutsideAuras(backing)
    end
end

-- Plate units per icon unit: the icons render at UIParent's scale and the
-- plate at its own (the nameplate scale CVar times the plate's own, which
-- that module eases), so an icon size or offset converts by this ratio.
local function PlateRatio(backing)
    local global = tonumber(C_CVar.GetCVar("nameplateGlobalScale")) or 1
    if global <= 0 then
        global = 1
    end
    return (uiZoom or 1) / (global * (backing._curScale or 1))
end

-- The side guest provider: for an CludesUI plate and a side ("left" /
-- "right"), the outermost icon there, with its centre's height over the bar's
-- centre in plate units, while the icons sit on that side and their span
-- meets a0..a1 (the arrows', above the bar's bottom).
local function SideGuest(backing, side, a0, a1)
    if stackAnchor ~= ((side == "left") and "LEFT" or "RIGHT") then
        return nil
    end
    local entries
    for _, l in pairs(onPlate) do
        local b = l[1]
        if b and b.cuiPlate == backing then
            entries = l
            break
        end
    end
    -- The outermost element's row end: one pitch past it while it shows,
    -- its own inner edge once its count gate hid it, so the arrows never
    -- hug an empty slot.
    local outer = entries and entries[#entries]
    if outer then
        outer = outer.rowEnd or outer
    end
    -- A marker defaults rail: its hug edge, the end of the row as the mob
    -- draws it, its own marker's lanes included (LayoutRail), never the
    -- rail's whole span.
    local track = Rails.OnPlate(backing)
    if track then
        outer = track.hug
    end
    if not outer then
        return nil
    end
    local scaleRatio = PlateRatio(backing)
    local gy = sOffY * scaleRatio
    local half = (iconPx * scaleRatio + (a1 - a0)) / 2
    if gy >= half or -gy >= half then
        return nil
    end
    return outer, gy
end

local guestRegistered = false
local function RegisterGuest()
    if guestRegistered then
        return
    end
    local reg = CludesUI._ModuleNS
    local m = reg and reg.CludesUINameplates
    if m and m.NP_AddSideGuest then
        m.NP_AddSideGuest(SideGuest)
        guestRegistered = true
    end
end

-- Whether a plate is the player's target: the one unit comparison permitted
-- on a restricted map. A hidden answer never counts.
local function IsTargetPlate(unitToken)
    local success, same = pcall(UnitIsUnit, "target", unitToken)
    return success and not Secret(same) and same == true
end

-- Icon host: the CludesUI plate when there is one, else the game's base
-- nameplate (Blizzard's or another addon's plate hangs from it). A forbidden
-- plate has no base frame to hand out: nothing shows.
local function ResolveHost(unitToken)
    local plateList = NPPlates()
    local backing = plateList and plateList[unitToken]
    if backing and backing.health then
        return backing, true
    end
    local base = C_NamePlate.GetNamePlateForUnit(unitToken)
    if base then
        return base, false
    end
    return nil, false
end

--------------------------------------------------------------------------------
--  Style: the aura kit cell style for the current settings. Rebuilt on every
--  settings write; AK.Restyle re-dresses every live icon.
--------------------------------------------------------------------------------
local AK

-- The text pass (noDefaultFonts): the countdown in the module font at the
-- chosen corner; stacks never show.
local function ApplyText(btnFrame, skinData, style)
    local fontStr = skinData.duration
    if fontStr then
        local filePath = CludesUI.GetFontPath(FONT_KEY) or ICON_FONT
        local fontKey = filePath .. "|" .. style.timerSize
        if skinData.ktFont ~= fontKey then
            skinData.ktFont = fontKey
            CludesUI.ApplyIconTextFont(fontStr, filePath, style.timerSize, FONT_KEY)
        end
        fontStr:SetTextColor(1, 1, 1)
        local m = TEXT_POS[style.timerPos] or TEXT_POS.topleft
        local aKey = m.point .. "|" .. (m.nx + style.timerX) .. "|" .. (m.ny + style.timerY)
        if skinData.ktAnchor ~= aKey then
            fontStr:ClearAllPoints()
            fontStr:SetPoint(m.point, btnFrame, m.point, m.nx + style.timerX, m.ny + style.timerY)
            skinData.ktAnchor = aKey
        end
        fontStr:SetJustifyH(m.justify)
        fontStr:SetShown(not style.hideDurationText)
    end
    if skinData.stack then
        skinData.stack:Hide()
    end
end

local function BuildStyle()
    local px = Pix.Scale(iconPx)
    return {
        width = px,
        height = px,
        texCoord = { ICON_ZOOM, 1 - ICON_ZOOM, ICON_ZOOM, 1 - ICON_ZOOM },
        border = { 0, 0, 0, 1, size = BORDER_PX },
        cooldownReverse = false,
        cooldownDrawEdge = false,
        hideSwipe = not sSwipe,
        noDefaultFonts = true,
        noTooltips = true,
        hideDurationText = not sShowTimer,
        timerSize = sTimerSize,
        timerPos = sTimerPos,
        timerX = sTimerX,
        timerY = sTimerY,
        applyExtra = ApplyText,
    }
end

local function RegisterStyle()
    AK = AK or CludesUI.AuraKit
    if not AK then
        return false
    end
    AK.styles[STYLE] = BuildStyle()
    return true
end

--------------------------------------------------------------------------------
--  Placement: the icon joins the plate's tree so it takes the plate's alpha,
--  scale and visibility. SetPoint only; nothing in a nameplate subtree can be
--  measured. Icons sharing a plate step away from it by their slot.
--------------------------------------------------------------------------------
-- The CludesUI plate's aura row (debuffs, buffs or crowd control) on the
-- icon's side, with its slot's Y offset and its height in plate units, or
-- nil: no row there, a Top or Bottom icon, or a client without the aspect.
local function SideRow(backing)
    if not rowsOK or (stackAnchor ~= "LEFT" and stackAnchor ~= "RIGHT") then
        return nil
    end
    local reg = CludesUI._ModuleNS
    local m = reg and reg.CludesUINameplates
    if not (m and m.NPC_SideRow) then
        return nil
    end
    return m.NPC_SideRow(backing, (stackAnchor == "LEFT") and "left" or "right")
end

-- The icon's edge frame, in the plate's own units, at its row's outer edge
-- and level with the bar's centre: the row's bottom outer corner is the one
-- point with both axes truthful (the target arrows hug it the same way), so
-- the edge hangs from it, the bar's half height less the row's Y offset up.
-- While the plate shows a cast whose full-size icon meets the kick icon but
-- not the row (the row did not step past it), the edge sits one cast icon
-- further out, as the arrows do.
local function PlaceEdge(b)
    local backing, row = b.cuiPlate, b.row
    local m = CludesUI._ModuleNS.CludesUINameplates
    local side = (stackAnchor == "LEFT") and "left" or "right"
    local barH = m.GetHealthBarHeight()
    local push = 0
    if b.casting and m.NP_FullIconPush then
        local scaleRatio = PlateRatio(backing)
        local mid = barH / 2 + b.oy * scaleRatio
        local half = iconPx * scaleRatio / 2
        local iconTex = m.NP_FullIconPush(backing, side, mid - half, mid + half)
        if iconTex > 0 and m.NP_FullIconPush(backing, side, b.rowY, b.rowY + b.rowH) == 0 then
            push = iconTex
        end
    end
    -- The icon hangs from the edge's inner side (its LEFT on the plate's
    -- left, as from the bar's LEFT; AnchorIcon), so that side sits on the
    -- corner.
    local edge = b.edge
    edge:SetParent(backing)
    edge:ClearAllPoints()
    if side == "left" then
        Pix.Point(edge, "LEFT", row, "BOTTOMLEFT", -push, barH / 2 - b.rowY)
    else
        Pix.Point(edge, "RIGHT", row, "BOTTOMRIGHT", push, barH / 2 - b.rowY)
    end
end

-- Whether the icon's cooldown is still running. The modeled cooldowns are
-- plain numbers. A ghost counts as on cooldown until the driver lets it go
-- (Ghosts.Tick), so it never sorts among the ready icons meanwhile.
local function CdRunning(b)
    return b.cdStart ~= nil and b.cdDur ~= nil and (b.isGhost or b.cdStart + b.cdDur > GetTime())
end

-- The order of a plate's live icons: ready kicks first, each group in the
-- order they came (seq).
local function ReadyFirst(a, b)
    if a.rdy ~= b.rdy then
        return a.rdy
    end
    return a.seq < b.seq
end

-- The rail's lanes and shift chain for its plate (the Marker defaults
-- section); forward-declared for LayoutPlate.
local LayoutRail

-- The icon's point. The first element of a row sits at the spot Place
-- chose: its row's edge frame where a row sits on its side, else beside the
-- cast icon while it steps aside for one (WatchCast) and the plate shows a
-- cast, else the bar. A rail sits at the first slot (its lanes take their
-- own places inside it, LayoutRail). Every later element hangs from the END
-- of the element before it in the row (LayoutPlate: `prevEl`), one pitch
-- past that element while it shows and at its own inner edge once its count
-- gate hid it (its step pair, Gate.AnchorStep), so a hidden icon's slot
-- collapses. The first element past the ready ones on a plate with a rail
-- hangs from that rail's shift edge instead (`hang`): the engine puts the
-- edge one slot further out for each ready lane the mob shows (LayoutRail),
-- and hangConst undoes the chain's own length, so the element steps out
-- exactly when a ready lane sits before it. A pooled icon is placed by its
-- wrap (the cell fills it); a ghost or a rail by itself.
local function AnchorIcon(b)
    local rel = (b.iconFrame and b.casting) and b.iconFrame or b.rel
    if b.row then
        PlaceEdge(b)
        rel = b.edge
    end
    local offX, offY = b.ox, b.oy
    local frame = b.wrap or b
    frame:ClearAllPoints()
    if b.isRail then
        if stackAnchor == "LEFT" then
            Pix.Point(frame, "RIGHT", rel, "LEFT", offX, offY)
        elseif stackAnchor == "RIGHT" then
            Pix.Point(frame, "LEFT", rel, "RIGHT", offX, offY)
        elseif stackAnchor == "TOP" then
            Pix.Point(frame, "BOTTOMLEFT", rel, "TOP", offX - iconPx / 2, offY)
        else
            Pix.Point(frame, "TOPLEFT", b.relBottom, "BOTTOM", offX - iconPx / 2, offY)
        end
        return
    end
    local half = Pix.Scale(iconPx) / 2
    local hang, previous = b.hang, b.prevEl
    if hang then
        local const = b.hangConst or 0
        if stackAnchor == "LEFT" then
            Pix.Point(frame, "RIGHT", hang, "CENTER", const, 0)
        elseif stackAnchor == "RIGHT" then
            Pix.Point(frame, "LEFT", hang, "CENTER", -const, 0)
        elseif stackAnchor == "TOP" then
            Pix.Point(frame, "BOTTOMLEFT", hang, "CENTER", -const, -half)
        else
            Pix.Point(frame, "TOPLEFT", hang, "CENTER", -const, half)
        end
    elseif previous then
        local ef, ep, eo = Gate.ElementEnd(previous)
        if stackAnchor == "LEFT" then
            Pix.Point(frame, "RIGHT", ef, ep, eo, 0)
        elseif stackAnchor == "RIGHT" then
            Pix.Point(frame, "LEFT", ef, ep, eo, 0)
        elseif stackAnchor == "TOP" then
            Pix.Point(frame, "BOTTOMLEFT", ef, ep, eo, -half)
        else
            Pix.Point(frame, "TOPLEFT", ef, ep, eo, half)
        end
    else
        if stackAnchor == "LEFT" then
            Pix.Point(frame, "RIGHT", rel, "LEFT", offX, offY)
        elseif stackAnchor == "RIGHT" then
            Pix.Point(frame, "LEFT", rel, "RIGHT", offX, offY)
        elseif stackAnchor == "TOP" then
            Pix.Point(frame, "BOTTOM", rel, "TOP", offX, offY)
        else
            Pix.Point(frame, "TOP", b.relBottom, "BOTTOM", offX, offY)
        end
    end
    -- The count gate's clip hung again about the moved wrap; a fed gate is
    -- fed once more on the driver's next pass (its fill's edge moved).
    if b.gate then
        Gate.HangWhole(b.clip, b.fill, b.gate)
        if b.cCur ~= nil then
            b.feed = true
        end
    end
end

local function OnCastShown(self)
    local b = self.kickIcon
    b.casting = true
    if b.unit and b.iconFrame then
        AnchorIcon(b)
    end
end

local function OnCastHidden(self)
    local b = self.kickIcon
    b.casting = false
    if b.unit and b.iconFrame then
        AnchorIcon(b)
    end
end

-- While the CludesUI plate's Full Sized cast icon takes the icon's side,
-- the icon sits past it during a cast: a watcher of ours on the plate's cast
-- bar re-places the icon as the bar shows and hides, with no events. nil
-- castBar: stop watching. The watcher is born under a cast bar, so it never
-- carries the park's aspect, and a frame without it may not be moved under
-- one that has it (the icons and rails): it parks under its own holder.
local function WatchCast(b, castBar, iconFrame)
    b.iconFrame = nil
    local wid = b.castWatch
    if not castBar then
        if wid then
            wid:Hide()
            wid:SetParent(watchPark)
        end
        b.casting = false
        return
    end
    if wid then
        wid:SetParent(castBar)
    else
        wid = CreateFrame("Frame", nil, castBar)
        wid.kickIcon = b
        wid:SetScript("OnShow", OnCastShown)
        wid:SetScript("OnHide", OnCastHidden)
        b.castWatch = wid
    end
    wid:Show()
    b.casting = castBar:IsShown() and true or false
    b.iconFrame = iconFrame
end

-- The cell's strata and levels under its host: the kit's regions stacked
-- from `lvl` in their build order; a pooled icon's wrap, gate and clip at
-- `lvl` with it.
local function SetIconLevels(b, layerStrata, frameLvl)
    if b.wrap then
        b.wrap:SetFrameStrata(layerStrata)
        b.wrap:SetFrameLevel(frameLvl)
        b.gate:SetFrameStrata(layerStrata)
        b.gate:SetFrameLevel(frameLvl)
        b.clip:SetFrameStrata(layerStrata)
        b.clip:SetFrameLevel(frameLvl)
    end
    b:SetFrameStrata(layerStrata)
    b:SetFrameLevel(frameLvl)
    local skinData = b.d
    b.iconClip:SetFrameStrata(layerStrata)
    b.iconClip:SetFrameLevel(frameLvl)
    b.iconHolder:SetFrameStrata(layerStrata)
    b.iconHolder:SetFrameLevel(frameLvl)
    skinData.cooldown:SetFrameStrata(layerStrata)
    skinData.cooldown:SetFrameLevel(frameLvl + 1)
    skinData.borderHost:SetFrameStrata(layerStrata)
    skinData.borderHost:SetFrameLevel(frameLvl + 2)
    skinData.dispelHolder:SetFrameStrata(layerStrata)
    skinData.dispelHolder:SetFrameLevel(frameLvl + 3)
    skinData.stackCarrier:SetFrameStrata(layerStrata)
    skinData.stackCarrier:SetFrameLevel(frameLvl + 4)
end

local function Place(b, owner, isCUI)
    local rel, relBottom, offX, offY, layerStrata, frameLvl
    if isCUI then
        rel = owner.health
        -- Bottom side sits under the cast bar (its rect resolves while hidden).
        relBottom = owner.cast or rel
        offX, offY = sOffX, sOffY
        -- The plate's own strata keeps the icon inside its flattened render
        -- layer, at the level above every tier of ours (PLATE_TOP).
        layerStrata = owner:GetFrameStrata()
        frameLvl = PLATE_TOP
        b.cuiPlate = owner
        -- An aura row on the icon's side: the icon sits past it (AnchorIcon).
        b.row, b.rowY, b.rowH = SideRow(owner)
    else
        rel, relBottom = owner, owner
        offX, offY = sOthX, sOthY
        layerStrata = owner:GetFrameStrata()
        frameLvl = owner:GetFrameLevel() + PLATE_TOP
        b.cuiPlate = nil
        b.row = nil
    end
    -- Show Above Overlapping Nameplates: the element hangs from the lift at
    -- the lift's strata instead of the plate (its anchors still follow it).
    local above = Lift.on and Lift.frame or nil
    if above then
        layerStrata = Lift.STRATA
    end
    -- Placement stamp: a new kick on the same plate under the same style
    -- skips this pass.
    b.placedHost, b.placedGen = owner, styleStamp
    local placed = b.wrap or b
    placed:SetParent(above or owner)
    if b.isRail then
        Rails.SetLevels(b, layerStrata, frameLvl)
    elseif b.isGhost then
        Ghosts.SetLevels(b, layerStrata, frameLvl)
    else
        SetIconLevels(b, layerStrata, frameLvl)
    end
    b.rel, b.relBottom, b.ox, b.oy = rel, relBottom, offX, offY
    -- A Full Sized cast icon on the icon's side covers it during a cast.
    local iconFrame = isCUI and FullIconSide() == stackAnchor and owner.castIconFrame or nil
    WatchCast(b, iconFrame and owner.cast or nil, iconFrame)
    AnchorIcon(b)
    if isCUI then
        ArrowsFollow(owner)
    end
end

-- The icons on a plate take their places in order: ready kicks nearest the
-- plate, the ones on cooldown past them, each group in arrival order, sorted
-- only when a neighbouring pair is out of order (ReadyFirst); the plate's
-- rail lays its lanes and chains out for that order (LayoutRail); each
-- element hangs from the end of the one before it (AnchorIcon), the first
-- past the ready ones from the rail's shift edge where there is a rail, and
-- is re-anchored only when the element it hangs from, or that element's
-- end, moved; the target arrows follow the outermost. Run on every change of
-- the plate's icons and on the two edges where readiness moves, a cooldown
-- painted and a cell's own cooldown running out (PaintCooldown,
-- OnCooldownDone).
local function LayoutPlate(unitToken)
    local entries = onPlate[unitToken]
    local num = entries and #entries or 0
    local ready = 0
    for i = 1, num do
        local b = entries[i]
        b.rdy = not CdRunning(b)
        if b.rdy then
            ready = ready + 1
        end
    end
    for i = 2, num do
        if ReadyFirst(entries[i], entries[i - 1]) then
            table.sort(entries, ReadyFirst)
            break
        end
    end
    local track = Rails.railOf[unitToken]
    if track and not track.placedHost then
        track = nil
    end
    local shift = track and track.shift or false
    -- Each element's link, and every element whose link moved unhooked
    -- BEFORE the rail's chains are laid out: those anchor to the row's ends,
    -- and an element still hung from the rail's shift edge by the last
    -- layout (the first past the ready ones then, ready now) is the very end
    -- the shift chain starts at, which the engine refuses as a cycle (field
    -- 2026-10-22). Hooked again after, in row order.
    for i = 1, num do
        local b = entries[i]
        local hang, previous = false, false
        if shift and i == ready + 1 then
            hang = shift
        elseif i > 1 then
            previous = entries[i - 1]
        end
        local prevGen = previous and previous.endGen or 0
        b.slot = i
        if b.placedHost and (b.slotAt ~= i or b.hang ~= hang or b.prevEl ~= previous or b.prevGen ~= prevGen) then
            b.slotAt, b.hang, b.prevEl, b.prevGen = i, hang, previous, prevGen
            b.relink = true
            local frame = b.wrap or b
            frame:ClearAllPoints()
        end
    end
    if track then
        LayoutRail(track, ready, num, entries)
    end
    -- The chain's length to undo is the rail's after its layout, so an
    -- element on the shift edge is hooked again when that moved too.
    local backing
    for i = 1, num do
        local b = entries[i]
        local const = b.hang and track.shiftConst or 0
        if b.placedHost and (b.relink or b.hangConst ~= const) then
            b.relink, b.hangConst = nil, const
            AnchorIcon(b)
        end
        backing = backing or b.cuiPlate
    end
    ArrowsFollow(backing or (track and track.cuiPlate))
end

local function TakeOffPlate(b)
    local unitToken = b.unit
    if not unitToken then
        return
    end
    local entries = onPlate[unitToken]
    if entries then
        for i = 1, #entries do
            if entries[i] == b then
                table.remove(entries, i)
                break
            end
        end
        if #entries == 0 then
            onPlate[unitToken] = nil
        end
        LayoutPlate(unitToken)
    end
    b.unit, b.slot, b.slotAt = nil, nil, nil
    liveCount = liveCount - 1
    ArrowsFollow(b.cuiPlate)
end

-- Puts an icon on a plate (off its old one first). The plate's GUID is kept
-- where it is plain, and whether it is the player's target, to find the mob
-- again should its plate come back.
local function PutOnPlate(b, unitToken, owner, isCUI)
    if b.unit ~= unitToken then
        TakeOffPlate(b)
        local entries = onPlate[unitToken]
        if not entries then
            entries = {}
            onPlate[unitToken] = entries
        end
        entries[#entries + 1] = b
        plateSeq = plateSeq + 1
        b.unit, b.slot, b.seq = unitToken, #entries, plateSeq
        -- Hung from the bar until LayoutPlate links it into the row.
        b.slotAt, b.hang, b.hangConst, b.prevEl, b.prevGen = nil, false, 0, false, 0
        b.guid = PlainString(UnitGUID(unitToken))
        b.onTarget = IsTargetPlate(unitToken)
        b.waitTarget = false
        liveCount = liveCount + 1
        -- The kicker's marker default stands down while their live icon sits
        -- on a plate.
        if b.kicker then
            Rails.SetLiveHidden(b.kicker, true)
        end
    end
    if b.placedHost ~= owner or b.placedGen ~= styleStamp then
        Place(b, owner, isCUI)
    else
        AnchorIcon(b)
        if isCUI then
            ArrowsFollow(owner)
        end
    end
    b.slotAt = b.slot
    LayoutPlate(unitToken)
end

--------------------------------------------------------------------------------
--  Paint
--------------------------------------------------------------------------------
local function Inset(widget, b, region)
    widget:ClearAllPoints()
    widget:SetPoint("TOPLEFT", b, "TOPLEFT", region, -region)
    widget:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -region, region)
end

-- Sizes, insets and the style pass. Runs once per settings generation per
-- icon (StyleIcon stamps styleGen).
local function StyleIcon(b)
    -- A pooled icon renders at UIParent's scale, not the plate's (its wrap
    -- ignores its parent's), so its sizes land on whole physical pixels; the
    -- wrap takes the cell's size, which the cell fills, and the count gate
    -- is sized about it. A lane cell or a ghost cell takes its scale from
    -- its rail or ghost instead (BuildIcon).
    local wrap = b.wrap
    if wrap then
        if b.uiScale ~= uiZoom then
            wrap:SetScale(uiZoom)
            b.uiScale = uiZoom
        end
        local cellW = Pix.Scale(iconPx)
        wrap:SetSize(cellW, cellW)
        Gate.Size(b.gate, wrap, cellW)
        Gate.HangWhole(b.clip, b.fill, b.gate)
        -- The step pair from the wrap's inner edge, one pitch wide (the
        -- rail chains' own measure), and the row end frame at its end.
        local goesLeft = stackAnchor == "LEFT"
        Gate.SizeStep(b.step, iconPx + ICON_GAP, cellW)
        local ef, ep = Gate.AnchorStep(b.step, wrap, goesLeft and "RIGHT" or "LEFT", 0, goesLeft)
        b.endFill, b.endPoint = ef, ep
        b.rowEnd:SetSize(1, cellW)
        b.rowEnd:ClearAllPoints()
        b.rowEnd:SetPoint(goesLeft and "LEFT" or "RIGHT", ef, ep, 0, 0)
    end
    Inset(b.iconClip, b, BORDER_PX * onePx)
    Inset(b.paw, b, sPawInset)
    b.styleGen = styleStamp
end

-- The border in the kicker's colour while Class Color Border is on and the
-- class is plain; black otherwise (grey for a kicker without a class).
local function PaintBorder(b, classFile)
    local owner = b.d.borderHost
    if type(classFile) == "nil" then
        Pix.SetBorderColor(owner, NEUTRAL, NEUTRAL, NEUTRAL, 1)
        return
    end
    if sClassBorder and not Secret(classFile) then
        local color = C_ClassColor.GetClassColor(classFile)
        if color then
            local region, g, bl = color:GetRGB()
            Pix.SetBorderColor(owner, region, g, bl, 1)
            return
        end
    end
    Pix.SetBorderColor(owner, 0, 0, 0, 1)
end

-- What stands for the kicker: `tex` (a spec icon or an interrupt's icon,
-- plain file IDs) on the kit's icon texture, else the class icon string from
-- `cls` (a plain class token, a SECRET one), else the paw (a pet or an NPC).
-- Both are kept on the icon as values only, so a restyle can repaint them.
local function PaintKicker(b, classFile, texture)
    b.kClass, b.kTex = classFile, texture
    local skinData = b.d
    if texture then
        skinData.icon:SetTexture(texture)
        skinData.icon:Show()
        b.classFS:Hide()
        b.paw:Hide()
    elseif type(classFile) == "nil" then
        skinData.icon:Hide()
        b.classFS:Hide()
        b.paw:Show()
    else
        skinData.icon:Hide()
        b.paw:Hide()
        b.classFS:SetFormattedText(iconFmt, classFile)
        b.classFS:Show()
    end
    PaintBorder(b, classFile)
end

-- Desaturate on Cooldown: the icon texture and the paw grey while a cooldown
-- runs (the inline class icon string cannot be greyed). Painted with the
-- cooldown, taken off when the widget runs it out (OnCooldownDone).
local function PaintDesat(b, running)
    local on = (running and sDesat) and true or false
    b.d.icon:SetDesaturated(on)
    b.paw:SetDesaturated(on)
end

-- A cooldown edge on a live icon or a lane cell: the icon's plate, or the
-- plate of the rail the cell belongs to, lays its icons out again.
local function ReadinessMoved(b)
    if b.unit then
        LayoutPlate(b.unit)
    elseif b.rail and b.rail.placedHost then
        LayoutPlate(b.rail.unit)
    end
end

-- The swipe and the countdown from a cooldown (start, dur), or neither. The
-- widget and the text binding run the cooldown out by themselves; the icon
-- stays, plain, once it ends, and its plate's icons take their places by
-- readiness.
local function PaintCooldown(b, start, duration)
    local skinData = b.d
    b.cdStart, b.cdDur = start, duration
    if start and duration and duration > 0 then
        skinData.cooldown:SetCooldown(start, duration)
        if b.binding then
            b.dur:SetTimeFromStart(start, duration)
            b.binding:SetEnabled(true)
        end
    else
        skinData.cooldown:Clear()
        if b.binding then
            b.binding:SetEnabled(false)
            skinData.duration:SetText("")
        end
    end
    PaintDesat(b, CdRunning(b))
    ReadinessMoved(b)
end

-- The kicker's icon by the Icon setting, for a named group unit: the spec's
-- icon file, the interrupt's, or nil (the class icon string then).
local function KickerTexture(m)
    if not m then
        return nil
    end
    if iconStyle == "spec" then
        return m.specIcon
    elseif iconStyle == "kick" then
        return m.kick and C_Spell.GetSpellTexture(m.kick) or nil
    end
    return nil
end

--------------------------------------------------------------------------------
--  Pool: icons are built once and parked, never orphaned. A parked icon is
--  hidden under our own holder, out of every nameplate tree.
--------------------------------------------------------------------------------
local function Detach(b)
    if b.unit then
        WatchCast(b, nil)
        b:Hide()
        local frame = b.wrap or b
        frame:ClearAllPoints()
        frame:SetParent(parked)
        b.edge:ClearAllPoints()
        b.edge:SetParent(parked)
        TakeOffPlate(b)
        b.cuiPlate, b.placedHost, b.placedGen, b.rel, b.relBottom, b.row = nil, nil, nil, nil, nil, nil
        if b.kicker then
            Rails.SetLiveHidden(b.kicker, false)
        end
    end
    if driverFrame and liveCount == 0 and Rails.count == 0 then
        driverFrame:Hide()
    end
end

local function Release(b)
    Detach(b)
    if b.binding then
        b.binding:SetEnabled(false)
    end
    local key = b.key
    if key then
        icons[key] = nil
        isDetached[key] = nil
    end
    b.key, b.kicker, b.guid, b.kClass, b.kTex, b.preview, b.at = nil, nil, nil, nil, nil, nil, nil
    b.cdStart, b.cdDur, b.onTarget, b.waitTarget, b.seq, b.rdy = nil, nil, nil, nil, nil, nil
    b.hang, b.hangConst, b.slotAt, b.prevEl, b.prevGen = nil, nil, nil, nil, nil
    -- The count gate whole again from plain values, its baseline dropped.
    b.cBase, b.cGen, b.cCur, b.feed = nil, nil, nil, nil
    if b.gate then
        Gate.ResetIconGate(b)
    end
    free[#free + 1] = b
end

local function ReleaseAll()
    Ghosts.ReleaseAll()
    for _, b in pairs(icons) do
        Release(b)
    end
    wipe(isDetached)
    wipe(onPlate)
    liveCount = 0
    Rails.ReleaseAll()
    wipe(Rails.liveHidden)
    if driverFrame then
        driverFrame:Hide()
    end
end

-- A plate went away: its icons leave it. An icon that can find its mob again
-- (a plain GUID, or the mob was the player's target) waits; any other goes.
-- A ghost follows the same rule (Ghosts.Detach), its span still running.
local function PlateGone(unitToken)
    local entries = onPlate[unitToken]
    if not entries then
        return
    end
    for i = #entries, 1, -1 do
        local b = entries[i]
        if b.preview then
            Release(b)
        else
            b.waitTarget = b.onTarget == true
            if b.isGhost then
                if b.guid or b.waitTarget then
                    Ghosts.Detach(b)
                else
                    Ghosts.Release(b)
                end
            elseif b.guid or b.waitTarget then
                Detach(b)
                isDetached[b.key] = b
            else
                Release(b)
            end
        end
    end
end

-- The player's target changed: a waiting icon or ghost that counted on the
-- target loses that link (it keeps waiting only where the GUID can still
-- find the mob), and the icons on plates learn whether they sit on the
-- target now.
local function OnTargetChanged()
    for key, b in pairs(isDetached) do
        if b.waitTarget then
            b.waitTarget = false
            if not b.guid then
                Release(b)
            end
        end
    end
    if Ghosts.nWaiting > 0 then
        Ghosts.TargetChanged()
    end
    for unitToken, entries in pairs(onPlate) do
        local isTarget = IsTargetPlate(unitToken)
        for i = 1, #entries do
            entries[i].onTarget = isTarget
        end
    end
end

--------------------------------------------------------------------------------
--  Preview samples
--------------------------------------------------------------------------------
local function PreviewClass(num)
    local token = PREVIEW_CLASSES[(num - 1) % NUM_PREVIEW + 1]
    if token then
        return token
    end
    return nil
end

-- A sample's icon by the Icon setting: the class's first spec, its main
-- interrupt, or the class icon.
local function PreviewTexture(classFile)
    if not classFile then
        return nil
    end
    if iconStyle == "spec" then
        local ident = CLASS_IDS[classFile]
        local _, _, _, iconTex = GetSpecializationInfoForClassID(ident, 1)
        return iconTex
    elseif iconStyle == "kick" then
        local spell = KD.ClassMainKick(classFile)
        return spell and C_Spell.GetSpellTexture(spell) or nil
    end
    return nil
end

local function RestartPreview(b)
    previewStep = previewStep + 1
    local classFile = PreviewClass(previewStep)
    PaintKicker(b, classFile, PreviewTexture(classFile))
    PaintCooldown(b, GetTime(), PREVIEW_CD)
    b.restartAt = GetTime() + PREVIEW_CD + PREVIEW_REST
end

--------------------------------------------------------------------------------
--  Driver: one hidden frame, shown only while an icon is up. Every TICK it
--  follows a plate the nameplate module handed to another unit, kicks a
--  sample again once its cooldown has rested, feeds a new ghost's gates once
--  more and lets a ghost go once its cooldowns can no longer run.
--------------------------------------------------------------------------------
local function DriverOnUpdate(self, elapsed)
    driverAcc = driverAcc + elapsed
    if driverAcc < TICK then
        return
    end
    driverAcc = 0
    local nowTime = GetTime()
    local plateList = NPPlates()
    for unitToken, entries in pairs(onPlate) do
        -- The nameplate module's plates are pooled and can change hands
        -- without a plate removal for this unit (a hostile unit turning
        -- friendly), and a plate added in the same frame as the icon may not
        -- have been handed out yet: follow the unit's current plate.
        -- A ghost placed again has its gates fed once more by Ghosts.Tick
        -- below (its fills' edges moved with it).
        local p = plateList and plateList[unitToken]
        for i = #entries, 1, -1 do
            local b = entries[i]
            if p ~= b.cuiPlate then
                if p and p.health then
                    Place(b, p, true)
                    if b.isGhost then
                        b.feed = true
                    end
                elseif b.cuiPlate then
                    PlateGone(unitToken)
                    break
                end
            elseif p and b.row ~= SideRow(p) then
                -- The aura row on the icon's side came or went (a slot moved
                -- in that module's settings, the buff row hidden for a unit
                -- you cannot attack): the icon takes its new spot.
                Place(b, p, true)
                if b.isGhost then
                    b.feed = true
                end
            end
            if b.preview and b.unit and nowTime >= b.restartAt then
                RestartPreview(b)
            end
            -- The one deferred feed of a pooled icon's count gate after the
            -- icon moved (AnchorIcon).
            if b.feed and b.gate then
                b.feed = nil
                Gate.RefeedIcon(b)
            end
        end
    end
    Rails.Follow(plateList)
    if Ghosts.live[1] then
        Ghosts.Tick(nowTime)
    end
    if liveCount == 0 and Rails.count == 0 then
        self:Hide()
    end
end

--------------------------------------------------------------------------------
--  Icon construction: an aura kit cell (icon texture for spec and interrupt
--  icons, swipe, border, countdown) plus a clip frame holding the inline
--  class icon string or the paw. Never takes the mouse. The icon ignores its
--  parent's scale and renders at UIParent's (StyleIcon); the icon string's
--  holder renders at scale 1.
--------------------------------------------------------------------------------
local function CellExtra(btnFrame, skinData, style)
    ApplyText(btnFrame, skinData, style)
end

-- `parent`: a lane's or a ghost cell's count clip, for a cell that hangs
-- there for good (it gets no edge frame and keeps its parent's scale: the
-- rail or ghost renders at UIParent's scale already, and a lane cell in its
-- gate's own scale root is what follows the gate's fill as that moves); nil
-- for a pooled icon: its wrap, born under the park, is what joins a plate's
-- tree and is placed (AnchorIcon), ignoring the plate's scale to render at
-- UIParent's (StyleIcon); under it the count gate (drawing nothing) and the
-- clip the cell lives in, open over the cell while the gate's fill is whole
-- (Gate.FeedWhole); the cell fills the wrap.
local function BuildIcon(hostFrame)
    local wrap, gateRec, fillTex, clipFrame
    if not hostFrame then
        wrap = CreateFrame("Frame", nil, parked)
        wrap:EnableMouse(false)
        wrap:SetIgnoreParentScale(true)
        gateRec, fillTex = Gate.New(wrap)
        clipFrame = Gate.NewClip(wrap)
    end
    local b, skinData = AK.CreateStyledCell(hostFrame or clipFrame, STYLE, CellExtra)
    b.d = skinData
    if hostFrame then
        b.laneCell = true
    else
        b.wrap, b.gate, b.fill, b.clip = wrap, gateRec, fillTex, clipFrame
        b:SetAllPoints(wrap)
        Gate.HangWhole(clipFrame, fillTex, gateRec)
        -- The step pair the next element of the row hangs from (one pitch
        -- past the wrap while the icon shows), and the row end frame at its
        -- end for the target arrows (SideGuest); anchored by StyleIcon.
        b.step = Gate.NewStep(wrap)
        b.rowEnd = CreateFrame("Frame", nil, wrap)
        b.rowEnd:SetSize(1, 1)
        -- The edge frame the icon hangs from past an aura row (PlaceEdge):
        -- born under the park for its aspect, lent to the plate while placed.
        b.edge = CreateFrame("Frame", nil, parked)
        b.edge:SetSize(1, 1)
    end
    b:Hide()
    b:EnableMouse(false)
    skinData.cooldown:EnableMouse(false)
    skinData.cooldown:SetHideCountdownNumbers(true)
    skinData.icon:Hide()

    -- The class icon overfills the area inside the border by a hair and this
    -- frame, set to that area (StyleIcon), clips it there.
    b.iconClip = CreateFrame("Frame", nil, b)
    b.iconClip:SetClipsChildren(true)
    b.iconClip:EnableMouse(false)

    b.inner = b.iconClip:CreateTexture(nil, "BACKGROUND")
    b.inner:SetAllPoints(b.iconClip)
    b.inner:SetColorTexture(0.06, 0.06, 0.06, 1)

    -- Class icon: an inline texture whose path the engine formats from the
    -- (possibly secret) class token, on a holder at scale 1 (see ICON_FMT).
    -- Its one font size is set here: text on a fontless font string errors.
    b.iconHolder = CreateFrame("Frame", nil, b.iconClip)
    b.iconHolder:SetIgnoreParentScale(true)
    b.iconHolder:SetScale(1)
    b.iconHolder:SetAllPoints(b.iconClip)
    b.iconHolder:EnableMouse(false)
    b.classFS = b.iconHolder:CreateFontString(nil, "ARTWORK")
    b.classFS:SetPoint("CENTER", b.iconHolder, "CENTER", 0, 0)
    b.classFS:SetWordWrap(false)
    b.classFS:SetFont(ICON_FONT, ICON_SIZE, "")
    b.classFS:SetShadowOffset(0, 0)
    b.classFS:SetShadowColor(0, 0, 0, 0)

    b.paw = b.iconClip:CreateTexture(nil, "ARTWORK")
    b.paw:SetAtlas(PAW_ATLAS)
    b.paw:Hide()

    -- The cooldown ran out: the greyed icon comes back (a cell of ours), and
    -- its plate's icons take their places again (a ready kick moves up).
    skinData.cooldown:SetScript("OnCooldownDone", function()
        PaintDesat(b, false)
        ReadinessMoved(b)
    end)

    -- The countdown: a duration object the text binding formats into the
    -- cell's duration string, like the aura icons' own.
    if C_DurationUtil and C_DurationUtil.CreateDurationTextBinding then
        b.dur = C_DurationUtil.CreateDuration()
        b.binding = C_DurationUtil.CreateDurationTextBinding()
        b.binding:SetFontString(skinData.duration)
        b.binding:SetDuration(b.dur)
        local fmt = AK.GetDurationFormatter(false)
        if fmt then
            b.binding:SetFormatter(fmt)
        end
        b.binding:SetEnabled(false)
    end
    return b
end

local function EnsurePool()
    if parked then
        return
    end
    -- The park is born with the aspect that lets an object anchor to an aura
    -- container (a side row carries UntrustedLayoutScriptExecution once it
    -- holds a group, and the aspect is only ever inherited at creation,
    -- never conferred by SetParent), so every icon and edge frame built under
    -- it carries it too. A client without the template keeps the icons at
    -- the bar's edge.
    local success, holderFrame =
        pcall(CreateFrame, "Frame", nil, UIParent, "DisableUntrustedLayoutScriptsTemplate")
    if success and holderFrame then
        parked, rowsOK = holderFrame, true
    else
        parked, rowsOK = CreateFrame("Frame", nil, UIParent), false
    end
    parked:Hide()
    -- The lift (Show Above Overlapping Nameplates): a shown holder under
    -- UIParent at its own strata, born as the park is, so what the park
    -- bears moves under it. An element placed under it leaves its plate's
    -- render tree and draws over every plate; its anchors to the plate's
    -- bar, its edge frame or the rail's shift edge still carry it along.
    local okLift, liftPx = pcall(CreateFrame, "Frame", nil, UIParent, "DisableUntrustedLayoutScriptsTemplate")
    if not (okLift and liftPx) then
        liftPx = CreateFrame("Frame", nil, UIParent)
    end
    liftPx:SetFrameStrata(Lift.STRATA)
    liftPx:SetSize(1, 1)
    liftPx:EnableMouse(false)
    if liftPx.EnableMouseMotion then
        liftPx:EnableMouseMotion(false)
    end
    liftPx:Show()
    Lift.frame = liftPx
    -- The cast watchers' holder: a plain frame, since a watcher is born
    -- under a plate's cast bar without the aspect and cannot be moved under
    -- the park (WatchCast).
    watchPark = CreateFrame("Frame", nil, UIParent)
    watchPark:Hide()
    driverFrame = CreateFrame("Frame")
    driverFrame:Hide()
    driverFrame:SetScript("OnUpdate", DriverOnUpdate)
end

local function Acquire(key, kicker)
    local num = #free
    local b
    if num > 0 then
        b = free[num]
        free[num] = nil
    else
        b = BuildIcon()
    end
    b.key, b.kicker = key, kicker
    icons[key] = b
    return b
end

-- Shows an icon for `key` on a plate, painting the kicker and the cooldown.
-- The pool, and a style current for UIParent's scale: a UI scale change since
-- the last icon re-sizes the style and restyles from here on.
local function Ready()
    EnsurePool()
    if SyncScale() then
        RegisterStyle()
        AK.Restyle(STYLE)
    end
end

local function ShowIcon(key, kicker, unitToken, owner, isCUI, classFile, texture, start, duration, preview)
    Ready()
    local b = icons[key] or Acquire(key, kicker)
    isDetached[key] = nil
    b.preview = preview
    if b.styleGen ~= styleStamp then
        StyleIcon(b)
    end
    PutOnPlate(b, unitToken, owner, isCUI)
    PaintKicker(b, classFile, texture)
    PaintCooldown(b, start, duration)
    b:Show()
    if not driverFrame:IsShown() then
        driverAcc = 0
        driverFrame:Show()
    end
    return b
end

--------------------------------------------------------------------------------
--  Ghosts: a kick the engine could not place on a member, shown exactly from
--  its gate packet (the engine's gate handler). One ghost per kick and plate:
--  an icon-like frame that takes a slot through the icons' own placement
--  (PutOnPlate, Place, AnchorIcon, LayoutPlate, TakeOffPlate), so aura rows,
--  the cast icon watcher, the target arrows and a rail's shift edge treat it
--  as an icon on cooldown. Inside it, one sub-cell per member who could have
--  kicked: a kit cell fixed on the ghost's slot, inside a clip whose left edge
--  hangs from the fill edge of a gate. The gate reaches a margin past the
--  cell on every side (Ghosts.Margin: the countdown text may sit past the
--  cell), and is SPAN of those spans (and 4 units each) wide, its right edge
--  2 units past the margin's. The gate takes the member's count after the
--  update as its maximum and before it as its value (hidden in combat: only
--  handed on, never read). While the count did not move the fill is whole,
--  the clip has no width and the cell shows nothing; once it rose (by one,
--  with up to SPAN interrupts in the fight) the fill falls short by at least
--  a span and 4 units, and the whole cell shows, its countdown included. The
--  cell never moves, only the clip's left edge does. The gate draws nothing
--  (alpha 0, its fill unsnapped), and nothing is read back from a gate, a
--  clip or a ghost. A sure kick of a member takes that member's cells out of
--  the ghosts from that kick or before (Ghosts.Supersede), as the bars
--  release their layers. Each cell sits behind a count gate of its own too
--  (the Count gates section): fed the member's count after the update as
--  its baseline and their count as read at every later update, once the
--  cell's cooldown is over, so a cell that opened closes again, for good,
--  when its member interrupts again (their newer kick shows instead).
--------------------------------------------------------------------------------
Ghosts.SPAN = Gate.SPAN -- gate width in spans: counts up to this many open the whole cell
Ghosts.LEVELS = 5 -- frame levels a kit cell takes: icon, swipe, border, dispel, countdown (SetIconLevels)

-- A ghost: born under the park for its aspect (it may hang from an aura
-- row's edge frame like an icon), with an edge frame of its own, rendering
-- at UIParent's scale (Style). Sub-cells are built on demand (BuildSub).
function Ghosts.Build()
    local g = CreateFrame("Frame", nil, parked)
    g.isGhost = true
    g:Hide()
    g:EnableMouse(false)
    g:SetIgnoreParentScale(true)
    g.edge = CreateFrame("Frame", nil, parked)
    g.edge:SetSize(1, 1)
    -- The row end frame at its chain's end (Ghosts.Chain), for the arrows.
    g.rowEnd = CreateFrame("Frame", nil, g)
    g.rowEnd:SetSize(1, 1)
    g.endGen = 0
    g.subs = {}
    g.used = 0
    return g
end

-- The ghost's chain: per used cell two step pairs from the ghost's inner
-- edge, chained edge to edge, the first fed the member's count before the
-- update as floor and their latest as ceiling with the values (ceiling,
-- floor): a pitch, and one more once the count rose past the floor; the
-- second fed their count after the update as floor and the latest as
-- ceiling with the values (floor, ceiling): a pitch, less one once the
-- count rose past that (the cell closed again). A plain offset undoes the
-- two pitches per cell, so the next element of the row sits one pitch out
-- for each cell that shows (open and not closed since), and at the ghost's
-- own inner edge with none: an empty ghost takes no slot. The chain's end
-- (endFill, endPoint, endOffset) is what the next element hangs from
-- (Gate.ElementEnd); endGen moves when the chain is laid out again, so the
-- element after the ghost is anchored again (LayoutPlate).
function Ghosts.Chain(g)
    local goesLeft = stackAnchor == "LEFT"
    local from, fp = g, goesLeft and "RIGHT" or "LEFT"
    local subRows = g.subs
    for k = 1, #subRows do
        local subRow = subRows[k]
        local on = k <= g.used
        if on then
            from, fp = Gate.AnchorStep(subRow.stepA, from, fp, 0, goesLeft)
            from, fp = Gate.AnchorStep(subRow.stepB, from, fp, 0, goesLeft)
        end
        Gate.ShowStep(subRow.stepA, on)
        Gate.ShowStep(subRow.stepB, on)
    end
    local undo = 2 * (iconPx + ICON_GAP) * g.used
    g.endFill, g.endPoint, g.endOffset = from, fp, goesLeft and undo or -undo
    g.rowEnd:ClearAllPoints()
    g.rowEnd:SetPoint(goesLeft and "LEFT" or "RIGHT", from, fp, g.endOffset, 0)
    g.endGen = g.endGen + 1
end

-- A cell's step pairs fed as its gates are (Feed, FeedB): the first on the
-- count before the update, the second on the count after it, both against
-- the latest read (the count after the update until one comes).
function Ghosts.FeedSteps(subRow)
    local goesLeft = stackAnchor == "LEFT"
    local current = (subRow.cCur ~= nil) and subRow.cCur or subRow.after
    local floorA = Gate.Base(subRow.before, subRow.gen)
    Gate.FeedStep(subRow.stepA, floorA, current, current, floorA, goesLeft)
    if subRow.cCur ~= nil then
        local floorB = Gate.Base(subRow.after, subRow.gen)
        Gate.FeedStep(subRow.stepB, floorB, current, floorB, current, goesLeft)
    else
        Gate.ResetStep(subRow.stepB, goesLeft)
    end
end

-- How far a gate (and so an open clip) reaches past the cell on every side,
-- in the ghost's units (Gate.Margin).
function Ghosts.Margin()
    return Gate.Margin()
end

-- Both gates' size and place on ghost g for the cell width `cw`, in the
-- ghost's units (Gate.Size). The clips are hung again after this (Feed,
-- Hang), since the fills' edges moved with the gates.
function Ghosts.Size(g, subRow, cellW)
    Gate.Size(subRow.gate, g, cellW)
    Gate.Size(subRow.gateB, g, cellW)
    Gate.SizeStep(subRow.stepA, iconPx + ICON_GAP, cellW)
    Gate.SizeStep(subRow.stepB, iconPx + ICON_GAP, cellW)
end

-- The clip from the gate's fill edge to the gate's right edge, anchored again
-- after every feed so it never keeps the edge of a fill that moved.
function Ghosts.Hang(subRow)
    local clipFrame, fillTex, gateRec = subRow.clip, subRow.fill, subRow.gate
    clipFrame:ClearAllPoints()
    clipFrame:SetPoint("TOPLEFT", fillTex, "TOPRIGHT", 0, 0)
    clipFrame:SetPoint("BOTTOMLEFT", fillTex, "BOTTOMRIGHT", 0, 0)
    clipFrame:SetPoint("TOPRIGHT", gateRec, "TOPRIGHT", 0, 0)
    clipFrame:SetPoint("BOTTOMRIGHT", gateRec, "BOTTOMRIGHT", 0, 0)
end

-- The cell's count gate fed again as it was (its member's count after the
-- update as the baseline, their latest count as the maximum, by the fight
-- the baseline was read in), or whole while it was never fed.
function Ghosts.FeedB(subRow)
    if subRow.cCur ~= nil then
        Gate.FeedWhole(subRow.gateB, subRow.fillB, subRow.clipB, Gate.Base(subRow.after, subRow.gen), subRow.cCur)
    else
        Gate.ResetWhole(subRow.gateB, subRow.fillB, subRow.clipB)
    end
    Ghosts.FeedSteps(subRow)
end

-- The member's count after the update as the gate's maximum and before it as
-- its value, then the clip hung again; the count gate and the step pairs
-- likewise.
function Ghosts.Feed(subRow)
    local gateRec = subRow.gate
    gateRec:SetMinMaxValues(0, subRow.after)
    gateRec:SetValue(subRow.before)
    Ghosts.Hang(subRow)
    Ghosts.FeedB(subRow)
end

-- Sub-cell k: the gate (closed until fed: a whole fill from plain values), the
-- clip, and inside it the cell's count gate (whole until fed) with its clip
-- holding a lane-style kit cell, anchored on the ghost for good. All of them
-- are born under the ghost, so they carry the park's aspect.
function Ghosts.BuildSub(g, key)
    local gateRec, fillTex = Gate.New(g)
    gateRec:Hide()
    local clipFrame = Gate.NewClip(g)
    clipFrame:Hide()
    local gateBottom, fillB = Gate.New(g)
    gateBottom:Hide()
    local clipB = Gate.NewClip(clipFrame)
    local cellFrame = BuildIcon(clipB)
    cellFrame:ClearAllPoints()
    cellFrame:SetAllPoints(g)
    local subRow = {
        gate = gateRec,
        fill = fillTex,
        clip = clipFrame,
        gateB = gateBottom,
        fillB = fillB,
        clipB = clipB,
        cell = cellFrame,
        stepA = Gate.NewStep(g),
        stepB = Gate.NewStep(g),
    }
    g.subs[key] = subRow
    Ghosts.Size(g, subRow, Pix.Scale(iconPx))
    Ghosts.Hang(subRow)
    Gate.HangWhole(clipB, fillB, gateBottom)
    return subRow
end

-- A sub-cell out of use: cooldown and countdown off, both gates closed or
-- whole again with plain values, the hidden counts and its member dropped,
-- gates and clip hidden.
function Ghosts.Park(subRow)
    PaintCooldown(subRow.cell, nil, nil)
    local gateRec = subRow.gate
    gateRec:SetMinMaxValues(0, 1)
    gateRec:SetValue(1)
    Ghosts.Hang(subRow)
    subRow.cCur, subRow.gen = nil, nil
    Gate.ResetWhole(subRow.gateB, subRow.fillB, subRow.clipB)
    local goesLeft = stackAnchor == "LEFT"
    Gate.ResetStep(subRow.stepA, goesLeft)
    Gate.ResetStep(subRow.stepB, goesLeft)
    subRow.clip:Hide()
    gateRec:Hide()
    subRow.gateB:Hide()
    subRow.unit, subRow.guid, subRow.before, subRow.after = nil, nil, nil, nil
end

-- Scale and size for the current style: the ghost renders at UIParent's
-- scale like an icon and is one cell wide; its gates follow the cell width.
function Ghosts.Style(g)
    if g.uiScale ~= uiZoom then
        g:SetScale(uiZoom)
        g.uiScale = uiZoom
    end
    local cellW = Pix.Scale(iconPx)
    g:SetSize(cellW, cellW)
    g.rowEnd:SetSize(1, cellW)
    local subRows = g.subs
    for k = 1, #subRows do
        Ghosts.Size(g, subRows[k], cellW)
    end
    Ghosts.Chain(g)
    g.styleGen = styleStamp
end

-- Place's strata and levels: the ghost and its gates at `lvl`, each sub-cell
-- and its clip above them, a whole cell's levels (LEVELS) per index, so a
-- later cell draws wholly over an earlier one (two can open together when
-- two members' counts rose in one update).
function Ghosts.SetLevels(g, layerStrata, frameLvl)
    g:SetFrameStrata(layerStrata)
    g:SetFrameLevel(frameLvl)
    local subRows = g.subs
    for k = 1, #subRows do
        local subRow = subRows[k]
        local base = frameLvl + 1 + Ghosts.LEVELS * (k - 1)
        subRow.gate:SetFrameStrata(layerStrata)
        subRow.gate:SetFrameLevel(frameLvl)
        subRow.gateB:SetFrameStrata(layerStrata)
        subRow.gateB:SetFrameLevel(frameLvl)
        subRow.clip:SetFrameStrata(layerStrata)
        subRow.clip:SetFrameLevel(base)
        subRow.clipB:SetFrameStrata(layerStrata)
        subRow.clipB:SetFrameLevel(base)
        SetIconLevels(subRow.cell, layerStrata, base)
    end
end

-- A member's cooldown after a landed kick, while they can stand in a ghost:
-- both counts handed over and their interrupt known. nil otherwise.
function Ghosts.Dur(unit, before, after)
    if not (before[unit] ~= nil and after[unit] ~= nil) then
        return nil
    end
    local duration = KE.KickDuration(unit)
    if duration and duration > 0 then
        return duration
    end
    return nil
end

-- Whether the kick at t already has its ghost on plate `unit`.
function Ghosts.Has(t, unitToken)
    local liveSet = Ghosts.live
    for i = 1, #liveSet do
        local g = liveSet[i]
        if g.t == t and g.unit == unitToken then
            return true
        end
    end
    return false
end

-- Off its plate, never orphaned: the cast watcher parks under its own holder
-- (WatchCast), the ghost and its edge under the park.
function Ghosts.Unplace(g)
    WatchCast(g, nil)
    g:Hide()
    g:ClearAllPoints()
    g:SetParent(parked)
    g.edge:ClearAllPoints()
    g.edge:SetParent(parked)
    TakeOffPlate(g)
    g.cuiPlate, g.placedHost, g.placedGen, g.rel, g.relBottom, g.row = nil, nil, nil, nil, nil, nil
    g.hang, g.hangConst, g.slotAt, g.feed = nil, nil, nil, nil
end

-- Whether a ghost waits for its mob's plate, kept with the count of them.
function Ghosts.SetWaiting(g, on)
    on = on and true or nil
    if g.waiting == on then
        return
    end
    g.waiting = on
    Ghosts.nWaiting = Ghosts.nWaiting + (on and 1 or -1)
end

-- Off its plate (or out of waiting) and back to the free list, every
-- sub-cell parked; its members' lanes take their baselines from the ghosts
-- left (Ghosts.LanesAfter).
function Ghosts.Release(g)
    local liveSet = Ghosts.live
    for i = #liveSet, 1, -1 do
        if liveSet[i] == g then
            table.remove(liveSet, i)
            break
        end
    end
    Ghosts.Unplace(g)
    Ghosts.SetWaiting(g, false)
    Ghosts.LanesAfter(g)
    local subRows = g.subs
    for k = 1, g.used do
        Ghosts.Park(subRows[k])
    end
    g.used = 0
    g.t, g.cdStart, g.cdDur, g.expireAt = nil, nil, nil, nil
    g.guid, g.onTarget, g.waitTarget, g.seq, g.rdy = nil, nil, nil, nil, nil
    local free = Ghosts.free
    free[#free + 1] = g
    if driverFrame and liveCount == 0 and Rails.count == 0 then
        driverFrame:Hide()
    end
end

function Ghosts.ReleaseAll()
    local liveSet = Ghosts.live
    for i = #liveSet, 1, -1 do
        Ghosts.Release(liveSet[i])
    end
end

-- Its plate went (PlateGone) while the mob can be found again (a plain GUID,
-- or the mob was the player's target: waitTarget): off the plate with its
-- cells, counts and cooldowns kept, waiting until a plate that is its mob
-- comes (Ghosts.Return), the target it counts on changes
-- (Ghosts.TargetChanged) or its span ends (Ghosts.Tick, Ghosts.Return).
function Ghosts.Detach(g)
    Ghosts.Unplace(g)
    Ghosts.SetWaiting(g, true)
    if driverFrame and liveCount == 0 and Rails.count == 0 then
        driverFrame:Hide()
    end
end

-- The player's target changed: a waiting ghost that counted on it keeps
-- waiting only where the GUID can still find its mob.
function Ghosts.TargetChanged()
    local liveSet = Ghosts.live
    for i = #liveSet, 1, -1 do
        local g = liveSet[i]
        if g.waiting and g.waitTarget then
            g.waitTarget = false
            if not g.guid then
                Ghosts.Release(g)
            end
        end
    end
end

-- Every used sub-cell's gate fed now, and once more on the driver's next
-- pass (the gates were sized or the ghost placed again, which moves the
-- fills' edges).
function Ghosts.FeedAll(g)
    local subRows = g.subs
    for k = 1, g.used do
        Ghosts.Feed(subRows[k])
    end
    g.feed = true
end

-- A plate came (OnPlateAdded): every waiting ghost whose mob this is (by
-- plain GUID, or the player's target while the ghost counts on it) comes
-- back onto it, dressed for the current style and fed again; one whose span
-- ended meanwhile goes.
function Ghosts.Return(unitToken, unitGuid, isTarget)
    local liveSet, nowTime = Ghosts.live, GetTime()
    local owner, isCUI
    for i = #liveSet, 1, -1 do
        local g = liveSet[i]
        if g.waiting then
            if nowTime >= g.expireAt then
                Ghosts.Release(g)
            elseif (unitGuid and g.guid == unitGuid) or (isTarget and g.waitTarget) then
                if not owner then
                    owner, isCUI = ResolveHost(unitToken)
                end
                if owner then
                    Ghosts.SetWaiting(g, false)
                    if g.styleGen ~= styleStamp then
                        Ghosts.Dress(g)
                    end
                    PutOnPlate(g, unitToken, owner, isCUI)
                    Ghosts.FeedAll(g)
                    g:Show()
                    if not driverFrame:IsShown() then
                        driverAcc = 0
                        driverFrame:Show()
                    end
                end
            end
        end
    end
end

-- The driver's pass: a ghost whose cooldowns can no longer run goes; a new
-- one's gates are fed once more, a pass after it went up.
function Ghosts.Tick(nowTime)
    local liveSet = Ghosts.live
    for i = #liveSet, 1, -1 do
        local g = liveSet[i]
        if nowTime >= g.expireAt then
            Ghosts.Release(g)
        elseif g.feed then
            g.feed = nil
            local subRows = g.subs
            for k = 1, g.used do
                Ghosts.Feed(subRows[k])
            end
        end
    end
end

-- A ghost for the kick at t on plate `unit`: one sub-cell per member who
-- could have kicked and has a known cooldown, fed their counts and timed from
-- t with their own cooldown. The ghost holds that span while the longest of
-- them could still run (CdRunning: it sorts with the icons on cooldown).
function Ghosts.Show(t, unitToken, owner, isCUI, units, before, after)
    local num, longestText = 0, 0
    for i = 1, #units do
        local duration = Ghosts.Dur(units[i], before, after)
        if duration then
            num = num + 1
            if duration > longestText then
                longestText = duration
            end
        end
    end
    if num == 0 then
        return
    end
    Ready()
    local free = Ghosts.free
    local g = free[#free]
    if g then
        free[#free] = nil
    else
        g = Ghosts.Build()
    end
    if g.styleGen ~= styleStamp then
        Ghosts.Style(g)
    end
    local subRows, k = g.subs, 0
    local gen = KE.FightGen()
    for i = 1, #units do
        local u = units[i]
        local duration = Ghosts.Dur(u, before, after)
        if duration then
            k = k + 1
            local subRow = subRows[k] or Ghosts.BuildSub(g, k)
            local m = KE.Member(u)
            -- The member's GUID too: the cell stays theirs should their
            -- party token pass to someone else (Ghosts.MemberOf). The count
            -- gate starts whole: its baseline is the count after this
            -- update, in this fight, fed against the later reads.
            subRow.unit, subRow.guid, subRow.before, subRow.after = u, m and m.guid, before[u], after[u]
            subRow.gen, subRow.cCur = gen, nil
            subRow.gate:Show()
            subRow.gateB:Show()
            Ghosts.Feed(subRow)
            local cellFrame = subRow.cell
            if cellFrame.styleGen ~= styleStamp then
                StyleIcon(cellFrame)
            end
            PaintKicker(cellFrame, (m and m.class) or UnitClassBase(u), KickerTexture(m))
            PaintCooldown(cellFrame, t, duration)
            cellFrame:Show()
            subRow.clip:Show()
        end
    end
    g.used = k
    g.t, g.cdStart, g.cdDur, g.expireAt = t, t, longestText, t + longestText
    Ghosts.Chain(g)
    local liveSet = Ghosts.live
    liveSet[#liveSet + 1] = g
    PutOnPlate(g, unitToken, owner, isCUI)
    -- Placed: fed again now that the gates sit where they show, and once
    -- more on the driver's next pass.
    Ghosts.FeedAll(g)
    g:Show()
    if not driverFrame:IsShown() then
        driverAcc = 0
        driverFrame:Show()
    end
    -- Each candidate's lanes take this ghost into their baseline (the
    -- counts event of this update came before the ghost existed).
    for i = 1, k do
        local subRow = subRows[i]
        if after[subRow.unit] ~= nil then
            Rails.Counts(subRow.unit, after[subRow.unit], t)
        end
    end
end

-- A lane's baseline for the member holding `guid`: their count before the
-- oldest ghost still holding their cell (its fight's, 0 from an older one),
-- or nil with none, so the lane hides while such a ghost may show them and
-- comes back once every one of them is gone.
function Ghosts.LaneBase(unitGuid)
    if not unitGuid then
        return nil
    end
    local liveSet = Ghosts.live
    for i = 1, #liveSet do
        local g = liveSet[i]
        local subRows = g.subs
        for k = 1, g.used do
            local subRow = subRows[k]
            if subRow.guid == unitGuid then
                return Gate.Base(subRow.before, subRow.gen)
            end
        end
    end
    return nil
end

-- The engine's counts event for member u: each of their cells in the ghosts
-- is fed their count as read now against its own baseline, once the cell's
-- cooldown is over (a cell that opened closes for good when they interrupt
-- again). By their GUID: a cell follows its member, not their token.
function Ghosts.Counts(unit, current, T)
    local m = KE.Member(unit)
    local unitGuid = m and m.guid
    if not unitGuid then
        return
    end
    local liveSet = Ghosts.live
    for i = 1, #liveSet do
        local g = liveSet[i]
        local subRows = g.subs
        for k = 1, g.used do
            local subRow = subRows[k]
            if subRow.guid == unitGuid and not Gate.StillDownAt(unit, subRow.cell.cdStart, subRow.cell.cdDur, T) then
                subRow.cCur = current
                Ghosts.FeedB(subRow)
            end
        end
    end
end

-- A ghost leaving (Release: it is out of the live list by now): its members'
-- lanes take their baselines from the ghosts left, with the counts as the
-- engine last read them.
function Ghosts.LanesAfter(g)
    if Rails.count == 0 then
        return
    end
    local subRows, nowTime = g.subs, GetTime()
    for k = 1, g.used do
        local m = Ghosts.MemberOf(subRows[k])
        local current = m and KE.Count(m.unit)
        if current ~= nil then
            Rails.Counts(m.unit, current, nowTime)
        end
    end
end

-- The member a sub-cell stands for: the record its unit holds while that is
-- still the same player, else the record of the unit holding their GUID now
-- (the party tokens close up when someone leaves; the cell's unit follows),
-- else nil (they left the group: the cell keeps its picture).
function Ghosts.MemberOf(subRow)
    local unitGuid = subRow.guid
    if not unitGuid then
        return nil
    end
    local m = KE.Member(subRow.unit)
    if m and m.guid == unitGuid then
        return m
    end
    local units = KE.GROUP_UNITS
    for i = 1, #units do
        m = KE.Member(units[i])
        if m and m.guid == unitGuid then
            subRow.unit = units[i]
            return m
        end
    end
    return nil
end

-- The ghost and its cells for the current style: sized, each cell restyled,
-- its picture painted again by the Icon setting (from its member while they
-- are in the group, else as it was) and its greying again. The gates moved:
-- the caller feeds them after placing the ghost.
function Ghosts.Dress(g)
    Ghosts.Style(g)
    local subRows = g.subs
    for k = 1, g.used do
        local subRow = subRows[k]
        local cellFrame = subRow.cell
        if cellFrame.styleGen ~= styleStamp then
            StyleIcon(cellFrame)
        end
        local m = Ghosts.MemberOf(subRow)
        local texture = cellFrame.kTex
        if m then
            texture = KickerTexture(m)
        elseif iconStyle == "class" then
            texture = nil
        end
        PaintKicker(cellFrame, cellFrame.kClass, texture)
        PaintDesat(cellFrame, CdRunning(cellFrame))
    end
end

-- A settings write: every ghost on a plate still on its old stamp is
-- dressed, placed and fed again (a waiting one is dressed when it comes
-- back, Ghosts.Return).
function Ghosts.Restyle()
    local liveSet = Ghosts.live
    for i = #liveSet, 1, -1 do
        local g = liveSet[i]
        if g.styleGen ~= styleStamp and g.unit then
            local owner, isCUI = ResolveHost(g.unit)
            if owner then
                Ghosts.Dress(g)
                Place(g, owner, isCUI)
                Ghosts.FeedAll(g)
            else
                Ghosts.Release(g)
            end
        end
    end
end

-- A member's spec or interrupt became known: their sub-cells' pictures
-- follow. A cell whose member left the group keeps its picture.
function Ghosts.Repaint()
    local liveSet = Ghosts.live
    for i = 1, #liveSet do
        local g = liveSet[i]
        local subRows = g.subs
        for k = 1, g.used do
            local subRow = subRows[k]
            local m = Ghosts.MemberOf(subRow)
            if m then
                local texture = KickerTexture(m)
                if texture ~= subRow.cell.kTex then
                    PaintKicker(subRow.cell, m.class or subRow.cell.kClass, texture)
                end
            end
        end
    end
end

-- A member's cooldown with a start is a sure kick of theirs (the engine
-- times nothing else), and a cleared one ends what they had: their cells in
-- the ghosts from that kick or before (all of them with nil) leave, as the
-- bars release their layers, so the member never shows twice or on a
-- superseded cooldown. A cell leaves by trading places with the last used
-- one; a ghost left with no cell goes, one left with cells holds the span of
-- the longest of them.
function Ghosts.Supersede(kicker, start)
    local m = KE.Member(kicker)
    local unitGuid = m and m.guid
    if not unitGuid then
        return
    end
    local liveSet = Ghosts.live
    for i = #liveSet, 1, -1 do
        local g = liveSet[i]
        if start == nil or g.t <= start + 0.01 then
            local subRows, num = g.subs, g.used
            local hit = false
            for k = num, 1, -1 do
                local subRow = subRows[k]
                if subRow.guid == unitGuid then
                    Ghosts.Park(subRow)
                    subRows[k], subRows[num] = subRows[num], subRow
                    num = num - 1
                    hit = true
                end
            end
            if hit then
                g.used = num
                if num == 0 then
                    Ghosts.Release(g)
                else
                    local longestText = 0
                    for k = 1, num do
                        local skinData = subRows[k].cell.cdDur
                        if skinData and skinData > longestText then
                            longestText = skinData
                        end
                    end
                    g.cdDur, g.expireAt = longestText, g.t + longestText
                    -- Fewer cells: the chain, and the row after the ghost.
                    Ghosts.Chain(g)
                    if g.unit then
                        LayoutPlate(g.unit)
                    end
                end
            end
        end
    end
end

-- The engine's gate packet for the meter update at t: a ghost on each plate
-- kicked then that nobody was placed on. A plate joining the packet later
-- (platesOnly) is simply new; one that has its ghost for t already is not.
-- Every table is the engine's scratch, read here and never kept.
function Ghosts.OnGate(t, units, before, after, plateList, platesOnly)
    if currentMode ~= MODE_LIVE then
        return
    end
    for i = 1, #plateList do
        local unitToken = plateList[i]
        if NAMEPLATE_UNITS[unitToken] and not Ghosts.Has(t, unitToken) and IsHostile(unitToken) then
            local owner, isCUI = ResolveHost(unitToken)
            if owner then
                Ghosts.Show(t, unitToken, owner, isCUI, units, before, after)
            end
        end
    end
end

--------------------------------------------------------------------------------
--  Engine handlers
--------------------------------------------------------------------------------
-- A kick on a plate unit. who: the kicker's unit when the engine is sure of
-- them (their icon comes to this plate); by: the interrupter (a secret GUID
-- in restricted content). A kick the engine placed on a member: that
-- member's icon moves to the plate with their cooldown. Any other kick
-- arrives through the gate packet instead and shows as a ghost (Ghosts).
local function OnKick(unitToken, who, _, _, _, _)
    if currentMode ~= MODE_LIVE or not who or not NAMEPLATE_UNITS[unitToken] then
        return
    end
    local nowTime = GetTime()
    local b = icons[who]
    -- Your cast and its landing a moment later, or two tokens of one mob.
    if b and b.unit == unitToken and b.at and nowTime - b.at < DEDUPE then
        return
    end
    if not IsHostile(unitToken) then
        return
    end
    local owner, isCUI = ResolveHost(unitToken)
    if not owner then
        return
    end
    local m = KE.Member(who)
    local classFile = (m and m.class) or UnitClassBase(who)
    local start, duration = KE.Cooldown(who)
    b = ShowIcon(who, who, unitToken, owner, isCUI, classFile, KickerTexture(m), start, duration, false)
    b.at = nowTime
    -- The count gate's baseline: the kicker's count as the engine read it at
    -- this kick, in this fight (none for your own cast: you are never a
    -- candidate), the gate whole until a later read says they kicked again.
    b.cBase, b.cGen, b.cCur = KE.Count(who), KE.FightGen(), nil
    Gate.ResetIconGate(b)
end

-- A member's modeled cooldown moved: their icon follows, wherever it sits,
-- and their cells in older ghosts leave (Ghosts.Supersede).
local function OnCooldown(kicker, start, duration)
    if currentMode ~= MODE_LIVE then
        return
    end
    local b = icons[kicker]
    if b then
        PaintCooldown(b, start, duration)
    end
    Rails.Cooldown(kicker, start, duration)
    if Ghosts.live[1] then
        Ghosts.Supersede(kicker, start)
    end
end

-- A member's spec or interrupt became known: their icon's picture may change.
local function OnRoster()
    if currentMode ~= MODE_LIVE then
        return
    end
    for key, b in pairs(icons) do
        if b.kicker then
            local m = KE.Member(b.kicker)
            local texture = KickerTexture(m)
            if texture ~= b.kTex then
                PaintKicker(b, (m and m.class) or b.kClass, texture)
            end
        end
    end
    Ghosts.Repaint()
    Rails.SyncKickers()
    Rails.SyncAll()
end

local HANDLERS = { kick = OnKick, cooldown = OnCooldown, roster = OnRoster, gate = Ghosts.OnGate }

-- The engine's counts event: each member's count as read at this update,
-- for the count gates of their live icon, their cells in the ghosts and
-- their lanes (each fed only once its own cooldown is over).
function HANDLERS.counts(T, units, after)
    if currentMode ~= MODE_LIVE then
        return
    end
    for i = 1, #units do
        local u = units[i]
        local current = after[u]
        if current ~= nil then
            local b = icons[u]
            if b and b.gate then
                Gate.FeedIcon(b, u, current, T)
            end
            if Ghosts.live[1] then
                Ghosts.Counts(u, current, T)
            end
            if Rails.count > 0 then
                Rails.Counts(u, current, T)
            end
        end
    end
end

--------------------------------------------------------------------------------
--  Marker defaults: a kicker's icon sits on the mob carrying the raid marker
--  they announced (Focus Announce) before any kick, and comes back there once
--  their live icon is gone. A mob's marker index is hidden in every dungeon,
--  so Lua never reads it: per marked plate and kicker, a hidden status bar
--  (the gate) takes the index as its value, its fill edge travels one icon
--  width per index, and the kicker's cell hangs from that edge inside a clip
--  one icon wide (the lane) placed where their own marker's index lands, so
--  the engine shows the cell only on the mob that carries it. A rail holds a
--  marked plate's lanes, placed like an icon at the first slot; each lane
--  takes its own slot by its kicker's readiness among the plate's live icons
--  (LayoutRail: a ready lane right after the ready live icons, and the
--  on-cooldown live icons step out for it through the rail's shift chain;
--  two kickers on one marker take lanes side by side). Markers are learned
--  from addon messages on the group's channel (open before a key starts;
--  inside one the lockdown drops them): "F" carries a member's marker, "R"
--  carries it and asks everyone inside for theirs. Focus Announce sends an
--  "F" beside its chat line at the ready check; without one, a zone-in with
--  the group full and the group filling up to five inside send an "R", each
--  client inside answers, and a marker set or cleared inside is told at once.
--  Markers are cached by member GUID, saved so a reload keeps them inside the
--  same instance, and forgotten at every zone-in. Rails exist only on marked
--  hostile plates while a kicker is cached; markers are sent and heard only
--  inside a Mythic dungeon or key, where the tracker itself runs.
--------------------------------------------------------------------------------
Rails.PREFIX = "E" .. "UIKT" -- the prefix every client of this tracker shares
Rails.count = 0 -- rails on plates (the driver follows them like icons)
Rails.gen = 0 -- bumped when the kicker list changes: lanes are laid out again
Rails.markerOf = {} -- member GUID -> the marker they announced (1-8)
Rails.kickers = {} -- in roster order: { unit, marker, lane }
Rails.laneOf = {} -- kicker unit -> index in kickers
Rails.railOf = {} -- plate unit -> its rail
Rails.free = {} -- parked rails
Rails.liveHidden = {} -- kicker unit -> true while their live icon sits on a plate
Rails.inst = nil -- the dungeon the cache belongs to (GetInstanceInfo's instanceID)
Rails.pendingRestore = false
Rails.on = false -- the marker frame is live (SyncEvents: the plates are on)
Rails.marker = 0 -- your Focus Announce marker while the tracker is on (SyncAnnounce), else 0
Rails.askedT = -1 -- GetTime() of the last request sent
Rails.replyArmed = false -- an answer to a request is on its way
local RAIL_SPAN = 8 -- indexes of fill travel on either side of a kicker's marker
local ASK_GAP = 2 -- seconds between requests: a zone-in's roster storm asks once
local REPLY_DELAY = 1 -- seconds an answer waits, so a burst of requests gets one

-- The ID of the dungeon markers are shared in: a Mythic dungeon or key, the
-- tracker's own content (the Where bucket, read live), so nothing is sent or
-- heard in a dungeon where the tracker never shows; nil anywhere else.
local function MarkerInstance()
    if MTWhere.Bucket() ~= "dungeon_mythic" then
        return nil
    end
    local _, iType, _, _, _, _, _, instance = GetInstanceInfo()
    if iType ~= "party" then
        return nil
    end
    return instance
end

-- This character's saved record (CludesUIDB.kickMarkers[playerGUID]), or nil.
local function SavedRecord()
    if type(CludesUIDB) ~= "table" then
        return nil
    end
    local myGuid = PlainString(UnitGUID("player"))
    if not myGuid then
        return nil
    end
    local allPlates = CludesUIDB.kickMarkers
    if type(allPlates) ~= "table" then
        allPlates = {}
        CludesUIDB.kickMarkers = allPlates
    end
    local plateRec = allPlates[myGuid]
    if type(plateRec) ~= "table" then
        plateRec = {}
        allPlates[myGuid] = plateRec
    end
    return plateRec
end

-- Written only by Learn and Forget: a restore reads it and leaves it.
local function SaveCache()
    local plateRec = SavedRecord()
    if not plateRec then
        return
    end
    plateRec.inst = Rails.inst
    local m = {}
    for g, markerKey in pairs(Rails.markerOf) do
        m[g] = markerKey
    end
    plateRec.m = m
end

-- The cached kickers against the roster: members with a cached marker and an
-- interrupt. Lanes: the first of a marker sits nearest the plate, another
-- kicker on the same marker one lane out.
function Rails.SyncKickers()
    local entries, laneOf = Rails.kickers, Rails.laneOf
    wipe(entries)
    wipe(laneOf)
    Rails.gen = Rails.gen + 1
    if next(Rails.markerOf) == nil then
        return
    end
    local usedSet
    local units = KE.GROUP_UNITS
    for i = 1, #units do
        local unitToken = units[i]
        local m = KE.Member(unitToken)
        local markerKey = m and m.guid and m.kick and Rails.markerOf[m.guid]
        if markerKey then
            usedSet = usedSet or {}
            local laneRec = usedSet[markerKey] or 0
            usedSet[markerKey] = laneRec + 1
            entries[#entries + 1] = { unit = unitToken, marker = markerKey, lane = laneRec }
            laneOf[unitToken] = #entries
        end
    end
end

-- A member's marker (0: they have none now).
function Rails.Learn(unitGuid, markerTex)
    Rails.markerOf[unitGuid] = (markerTex >= 1 and markerTex <= 8) and markerTex or nil
    Rails.inst = MarkerInstance()
    SaveCache()
    Rails.SyncKickers()
    Rails.SyncAll()
end

-- A zone-in: the markers of the last visit are gone, everywhere.
local function ForgetMarkers()
    wipe(Rails.markerOf)
    Rails.inst = nil
    SaveCache()
    Rails.SyncKickers()
    Rails.SyncAll()
end

-- A login or reload: the saved markers come back only inside the instance
-- they were learned in. Read-only on the record.
local function RestoreMarkers()
    wipe(Rails.markerOf)
    local instance = MarkerInstance()
    Rails.inst = instance
    local plateRec = SavedRecord()
    if plateRec and instance and plateRec.inst == instance and type(plateRec.m) == "table" then
        for g, markerKey in pairs(plateRec.m) do
            if type(g) == "string" and type(markerKey) == "number" and markerKey >= 1 and markerKey <= 8 and markerKey == floor(markerKey) then
                Rails.markerOf[g] = markerKey
            end
        end
    end
    Rails.SyncKickers()
    Rails.SyncAll()
end

-- The chat type that reaches the whole group, as Blizzard's edit box picks it:
-- a Dungeon Finder group (which a party that queued together is in as well)
-- speaks on INSTANCE_CHAT, a party of your own on PARTY (sent from a Dungeon
-- Finder group alone, PARTY only brings back "You aren't in a party."); nil
-- solo and in a raid.
function Rails.Channel()
    if IsInRaid() then
        return nil
    end
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        return "INSTANCE_CHAT"
    end
    if IsInGroup(LE_PARTY_CATEGORY_HOME) then
        return "PARTY"
    end
    return nil
end

-- Whether the group is a full party inside a Mythic dungeon or key: the request edges fire
-- only then (owner 2026-10-21), the ready check whatever the count.
local function FullPartyInDungeon()
    if not MarkerInstance() then
        return false
    end
    if not Rails.Channel() then
        return false
    end
    return GetNumGroupMembers() == 5
end

-- Your marker to every client inside, on the addon channel alone (never the
-- chat line) of the group's chat type (Rails.Channel; solo or in a raid
-- nothing is sent): "F" tells it, "R" tells it and asks for theirs; a 0
-- clears a marker you no longer have. Before a key starts it goes through;
-- inside one the lockdown drops it, and the result is not read.
local function SendMarker(kind)
    local myGuid = PlainString(UnitGUID("player"))
    local channelling = Rails.Channel()
    if not (myGuid and channelling) then
        return
    end
    Rails.Learn(myGuid, Rails.marker)
    C_ChatInfo.SendAddonMessage(Rails.PREFIX, kind .. "\t" .. Rails.marker .. "\t" .. myGuid, channelling)
end

-- A request on the edges where a client may have missed earlier sends: your
-- zone-in with the group full, the group filling up to five inside, the
-- plates turned on inside. Every client inside answers (Reply), so a member
-- who arrived after the others still learns every marker, and they all hear
-- yours with the request. One request per ASK_GAP: a zone-in's roster storm
-- asks once, and a skipped event strands nothing, since the request out
-- covers the group as it stands and a member who arrives later asks on
-- their own arrival.
local function Request()
    if not Rails.on or not FullPartyInDungeon() then
        return
    end
    local T = GetTime()
    if Rails.askedT >= 0 and T - Rails.askedT < ASK_GAP then
        return
    end
    Rails.askedT = T
    SendMarker("R")
end

-- Someone asked: your marker goes out REPLY_DELAY later, one answer for every
-- request of a burst (a group zoning in together asks five times).
local function Reply()
    if Rails.replyArmed then
        return
    end
    Rails.replyArmed = true
    C_Timer.After(REPLY_DELAY, function()
        Rails.replyArmed = false
        if Rails.on and MarkerInstance() then
            SendMarker("F")
        end
    end)
end

local function BuildRail()
    local track = CreateFrame("Frame", nil, parked)
    track.isRail = true
    track:Hide()
    track:EnableMouse(false)
    track:SetIgnoreParentScale(true)
    track.edge = CreateFrame("Frame", nil, parked)
    track.edge:SetSize(1, 1)
    track.lanes = {}
    -- The shift chain (LayoutRail): its bar pairs, the edge at its end that
    -- the plate's on-cooldown live icons hang from, and per-marker scratch.
    track.chain = {}
    track.chainUsed = 0
    track.shift = CreateFrame("Frame", nil, track)
    track.shift:SetSize(1, 1)
    track.shiftConst = 0
    -- The hug chain (LayoutRail): its bar pairs, one per marker, and the
    -- frame at the last slot the mob draws, which the target arrows hug.
    track.hugChain = {}
    track.hugUsed = 0
    track.hug = CreateFrame("Frame", nil, track)
    track.hug:SetSize(1, 1)
    track.shownCount = 0
    track.readyBy, track.cdBy = {}, {}
    return track
end

-- A lane: its clip (one icon wide), the gate under the clip and the kicker's
-- cell under the gate, hung from the gate's fill edge for good: the shape of
-- the nameplate cast bar's kick tick, where a child of the bar it rides, in
-- that bar's own scale root, follows a fill fed hidden values. The fill does
-- not snap to the pixel grid, so the edge sits exactly one icon width per
-- index. The cell's count gate sits under the marker gate beside it, about
-- the cell (so it rides the fill with it), its clip holding the cell: the
-- marker gate draws at full alpha, since the cell is its descendant.
local function BuildLane(track, i)
    local clipFrame = Gate.NewClip(track)
    local gateRec = CreateFrame("StatusBar", nil, clipFrame)
    gateRec:EnableMouse(false)
    gateRec:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    local fillTex = gateRec:GetStatusBarTexture()
    fillTex:SetVertexColor(0, 0, 0, 0)
    if fillTex.SetSnapToPixelGrid then
        fillTex:SetSnapToPixelGrid(false)
        fillTex:SetTexelSnappingBias(0)
    end
    local gateBottom, fillB = Gate.New(gateRec)
    local clipB = Gate.NewClip(gateRec)
    local cellFrame = BuildIcon(clipB)
    cellFrame:ClearAllPoints()
    cellFrame:SetPoint("LEFT", fillTex, "RIGHT", 0, 0)
    cellFrame.rail = track
    Gate.HangWhole(clipB, fillB, gateBottom)
    local laneRec = {
        clip = clipFrame,
        gate = gateRec,
        fill = fillTex,
        gateB = gateBottom,
        fillB = fillB,
        clipB = clipB,
        cell = cellFrame,
    }
    track.lanes[i] = laneRec
    return laneRec
end

-- A lane's count gate fed member u's count as read at T against the
-- baseline the ghosts give (Ghosts.LaneBase: their count before the oldest
-- ghost still holding their cell, else the count itself, whole), once the
-- cooldown the lane shows (the kicker's own, from a sure kick) is over. With
-- no count read: whole from plain values.
function Rails.LaneFeed(laneRec, unit, current, T)
    if current == nil then
        laneRec.cBase, laneRec.cCur = nil, nil
        Gate.ResetWhole(laneRec.gateB, laneRec.fillB, laneRec.clipB)
        return
    end
    if Gate.StillDownAt(unit, laneRec.cell.cdStart, laneRec.cell.cdDur, T) then
        return
    end
    local m = KE.Member(unit)
    local base = Ghosts.LaneBase(m and m.guid)
    if base == nil then
        base = current
    end
    laneRec.cBase, laneRec.cCur = base, current
    Gate.FeedWhole(laneRec.gateB, laneRec.fillB, laneRec.clipB, base, current)
end

-- Fed again as it was (the cell moved with the marker fill: the count gate
-- and its fill's edge with it), or whole while it was never fed.
function Rails.LaneRefeed(laneRec)
    if laneRec.cCur ~= nil then
        Gate.FeedWhole(laneRec.gateB, laneRec.fillB, laneRec.clipB, laneRec.cBase, laneRec.cCur)
    else
        Gate.ResetWhole(laneRec.gateB, laneRec.fillB, laneRec.clipB)
    end
end

-- A bar of the shift chain: one slot pitch wide, a standard or a reverse
-- fill (Gate.NewBar).
local function ChainBar(track, reverse)
    local barFrame, fillTex = Gate.NewBar(track, reverse)
    barFrame:SetSize(iconPx + ICON_GAP, Pix.Scale(iconPx))
    barFrame:SetFrameStrata(track:GetFrameStrata())
    barFrame:SetFrameLevel(track:GetFrameLevel())
    return barFrame, fillTex
end

-- A pair of the shift chain (rail.chain) or, with `chain`, of the hug chain.
local function BuildPair(track, num, chain)
    local std, stdFill = ChainBar(track, false)
    local rev, revFill = ChainBar(track, true)
    local plateRow = { std = std, stdFill = stdFill, rev = rev, revFill = revFill }
    chain = chain or track.chain
    chain[num] = plateRow
    return plateRow
end

-- Both chains' bars take the plate's marker index like the gates.
local function FeedChain(track, position)
    local chain = track.chain
    for p = 1, track.chainUsed do
        local plateRow = chain[p]
        plateRow.std:SetValue(position)
        plateRow.rev:SetValue(position)
    end
    chain = track.hugChain
    for p = 1, track.hugUsed do
        local plateRow = chain[p]
        plateRow.std:SetValue(position)
        plateRow.rev:SetValue(position)
    end
end

-- The pairs of a chain anchored edge to edge from a point of the row (from,
-- fromPoint, offset), the first `used` of them shown with their marker's
-- range: a pair reaches its bars' width, and that width once more exactly on
-- its marker. Returns the chain's end, the last fill's outer edge, and the
-- offset left to apply there (the start's own, with no pair shown).
local function AnchorChain(track, chain, usedSet, goesLeft, from, fromPoint, off)
    for p = 1, #chain do
        local plateRow = chain[p]
        if p <= usedSet then
            local firstPlate, firstFill, secondary, secondFill
            if goesLeft then
                firstPlate, firstFill, secondary, secondFill = plateRow.rev, plateRow.revFill, plateRow.std, plateRow.stdFill
            else
                firstPlate, firstFill, secondary, secondFill = plateRow.std, plateRow.stdFill, plateRow.rev, plateRow.revFill
            end
            firstPlate:SetMinMaxValues(plateRow.marker - 1, plateRow.marker)
            secondary:SetMinMaxValues(plateRow.marker, plateRow.marker + 1)
            firstPlate:ClearAllPoints()
            secondary:ClearAllPoints()
            if goesLeft then
                firstPlate:SetPoint("RIGHT", from, fromPoint, off, 0)
                secondary:SetPoint("RIGHT", firstFill, "LEFT", 0, 0)
                from, fromPoint, off = secondFill, "RIGHT", 0
            else
                firstPlate:SetPoint("LEFT", from, fromPoint, off, 0)
                secondary:SetPoint("LEFT", firstFill, "RIGHT", 0, 0)
                from, fromPoint, off = secondFill, "LEFT", 0
            end
            firstPlate:Show()
            secondary:Show()
        else
            plateRow.std:Hide()
            plateRow.rev:Hide()
        end
    end
    return from, fromPoint, off
end

function Rails.SetLevels(track, layerStrata, frameLvl)
    track:SetFrameStrata(layerStrata)
    track:SetFrameLevel(frameLvl)
    for i = 1, #track.lanes do
        local laneRec = track.lanes[i]
        laneRec.clip:SetFrameStrata(layerStrata)
        laneRec.clip:SetFrameLevel(frameLvl)
        laneRec.gate:SetFrameStrata(layerStrata)
        laneRec.gate:SetFrameLevel(frameLvl)
        laneRec.gateB:SetFrameStrata(layerStrata)
        laneRec.gateB:SetFrameLevel(frameLvl)
        laneRec.clipB:SetFrameStrata(layerStrata)
        laneRec.clipB:SetFrameLevel(frameLvl)
        SetIconLevels(laneRec.cell, layerStrata, frameLvl + 1)
    end
    for p = 1, #track.chain do
        local plateRow = track.chain[p]
        plateRow.std:SetFrameStrata(layerStrata)
        plateRow.std:SetFrameLevel(frameLvl)
        plateRow.rev:SetFrameStrata(layerStrata)
        plateRow.rev:SetFrameLevel(frameLvl)
    end
    for p = 1, #track.hugChain do
        local plateRow = track.hugChain[p]
        plateRow.std:SetFrameStrata(layerStrata)
        plateRow.std:SetFrameLevel(frameLvl)
        plateRow.rev:SetFrameStrata(layerStrata)
        plateRow.rev:SetFrameLevel(frameLvl)
    end
end

-- Sizes for the style and the kicker list: the rail renders at UIParent's
-- scale like the icons; one lane per kicker, each gate wide enough for every
-- index to land inside it, each chain bar one slot pitch wide. The lanes'
-- slots and the rail's own size are LayoutRail's.
local function StyleRail(track)
    if track.uiScale ~= uiZoom then
        track:SetScale(uiZoom)
        track.uiScale = uiZoom
    end
    local cellW = Pix.Scale(iconPx)
    local entries = Rails.kickers
    local built = false
    for i = 1, #entries do
        local laneRec = track.lanes[i]
        if not laneRec then
            laneRec = BuildLane(track, i)
            built = true
        end
        laneRec.clip:SetSize(cellW, cellW)
        laneRec.gate:SetSize(2 * RAIL_SPAN * cellW, cellW)
        laneRec.gate:ClearAllPoints()
        laneRec.gate:SetPoint("LEFT", laneRec.clip, "LEFT", -RAIL_SPAN * cellW, 0)
        if laneRec.cell.styleGen ~= styleStamp then
            StyleIcon(laneRec.cell)
        end
        Gate.Size(laneRec.gateB, laneRec.cell, cellW)
        Gate.HangWhole(laneRec.clipB, laneRec.fillB, laneRec.gateB)
    end
    for p = 1, #track.chain do
        local plateRow = track.chain[p]
        plateRow.std:SetSize(iconPx + ICON_GAP, cellW)
        plateRow.rev:SetSize(iconPx + ICON_GAP, cellW)
    end
    -- The hug chain's widths are LayoutRail's (one per marker); its frame is
    -- a line at the row's end, the icons' height, so the arrows meet it at
    -- their height.
    for p = 1, #track.hugChain do
        local plateRow = track.hugChain[p]
        plateRow.std:SetHeight(cellW)
        plateRow.rev:SetHeight(cellW)
    end
    track.hug:SetSize(1, cellW)
    if built and track.placedHost then
        Rails.SetLevels(track, track:GetFrameStrata(), track:GetFrameLevel())
    end
    track.styleGen, track.kickGen = styleStamp, Rails.gen
end

-- Each lane for the kicker it stands for: picture, cooldown, the gate's range
-- about their marker, its count gate fed the count the engine last read, and
-- whether their live icon stands in for it. Spare lanes hide.
local function DressRail(track)
    local entries = Rails.kickers
    local nowTime = GetTime()
    for i = 1, #entries do
        local k = entries[i]
        local laneRec = track.lanes[i]
        local m = KE.Member(k.unit)
        PaintKicker(laneRec.cell, (m and m.class) or UnitClassBase(k.unit), KickerTexture(m))
        PaintCooldown(laneRec.cell, KE.Cooldown(k.unit))
        laneRec.floor = k.marker - RAIL_SPAN
        laneRec.gate:SetMinMaxValues(laneRec.floor, k.marker + RAIL_SPAN)
        laneRec.kicker = k.unit
        Rails.LaneFeed(laneRec, k.unit, KE.Count(k.unit), nowTime)
        laneRec.cell:Show()
        laneRec.gate:Show()
    end
    for i = #entries + 1, #track.lanes do
        local laneRec = track.lanes[i]
        laneRec.kicker = nil
        laneRec.clip:Hide()
        laneRec.gate:Hide()
    end
end

-- Every lane's gate takes the plate's marker index (hidden in every dungeon:
-- never read, only handed on), and its cell is anchored to the fill again,
-- so the cell never waits for a layout the engine does not run for a fill
-- that moved; the cell's count gate, which rides the cell, is fed again
-- with it. Fed before the rail shows, and once more on the driver's next
-- pass while the rail is visible (SyncPlate sets `feed`), so a rail back from
-- the park never keeps the fill its last plate gave it.
local function FeedRail(track, position)
    local lanes = track.lanes
    for i = 1, #Rails.kickers do
        local laneRec = lanes[i]
        laneRec.gate:SetValue(position)
        laneRec.cell:ClearAllPoints()
        laneRec.cell:SetPoint("LEFT", laneRec.fill, "RIGHT", 0, 0)
        Rails.LaneRefeed(laneRec)
    end
    FeedChain(track, position)
end

-- The rail's lanes and chains for its plate, with R ready live icons of L
-- (`list`, the plate's elements in row order). A shown lane (its kicker's
-- live icon down) takes a place by readiness: a ready one right after the
-- ready live icons, one on cooldown after every live icon and the ready
-- lanes of its marker, same-marker lanes side by side; a hidden lane parks
-- at the first slot. The row's own ends place them: the start, after the
-- ready live icons (the last of them's end, which collapses with a hidden
-- one; the rail's own inner edge with none), and the row end, after the
-- last live icon. The live icons past the ready ones must step out one slot
-- for each ready lane the mob shows, which only the engine knows, so the
-- shift chain is a pair of bars per ready lane, a standard and a reverse
-- fill one pitch wide chained edge to edge from the start and fed the mob's
-- index: each pair reaches one pitch, and one more exactly on its own
-- marker, so the shift edge at the chain's end sits the chain's length plus
-- one pitch per ready lane the mob shows out from the start (AnchorIcon
-- undoes the chain's length for the first element past the ready ones, and
-- the rest hang from each other). The row end is the last live icon's end,
-- or the shift edge with the chain's length undone while no live icon is on
-- cooldown: the cooldown lanes hang from it. The rail
-- spans every slot a lane or a shifted icon can take. The target arrows hug
-- the hug frame instead: the end of the row as the mob draws it, the row
-- end plus its own marker's cooldown lanes, which the hug chain places:
-- one pair per marker with cooldown lanes, its bars those lanes' pitches
-- wide, chained from the row end like the shift chain, so its end sits the
-- chain's own length plus the width of the mob's marker's lanes out, and
-- the hug frame hangs that length back from it (owner 2026-10-21: the
-- arrows left room for lanes the mob did not show; 2026-10-22: a line at
-- the row's end, so a hidden icon's empty slot is never hugged either).
LayoutRail = function(track, R, L, entries)
    local kickers, lanes = Rails.kickers, track.lanes
    local pitch = iconPx + ICON_GAP
    local cellW = Pix.Scale(iconPx)
    local goesLeft = stackAnchor == "LEFT"
    local result = goesLeft and -1 or 1 -- along the row, away from the plate
    local inner = goesLeft and "RIGHT" or "LEFT"
    local readyBy, cdBy = track.readyBy, track.cdBy
    wipe(readyBy)
    wipe(cdBy)
    local usedSet, isShown = 0, 0
    for i = 1, #kickers do
        local k, laneRec = kickers[i], lanes[i]
        laneRec.shown = laneRec.kicker ~= nil and not Rails.liveHidden[k.unit]
        if laneRec.shown and not CdRunning(laneRec.cell) then
            local num = readyBy[k.marker] or 0
            laneRec.slotNo = R + 1 + num
            readyBy[k.marker] = num + 1
            usedSet = usedSet + 1
            local plateRow = track.chain[usedSet] or BuildPair(track, usedSet)
            plateRow.marker = k.marker
        end
    end
    local most = 0
    for _, num in pairs(readyBy) do
        if num > most then
            most = num
        end
    end
    local maxSlot = L + most
    for i = 1, #kickers do
        local k, laneRec = kickers[i], lanes[i]
        if laneRec.shown then
            if CdRunning(laneRec.cell) then
                local num = cdBy[k.marker] or 0
                laneRec.slotNo = L + 1 + (readyBy[k.marker] or 0) + num
                cdBy[k.marker] = num + 1
            end
            isShown = isShown + 1
            if laneRec.slotNo > maxSlot then
                maxSlot = laneRec.slotNo
            end
        else
            laneRec.slotNo = 1
        end
    end
    if maxSlot < 1 then
        maxSlot = 1
    end
    track.shownCount = isShown
    track:SetSize(cellW + (maxSlot - 1) * pitch, cellW)
    -- The start: after the ready live icons.
    local scrollFrame, sp, so = track, inner, 0
    if R > 0 and entries then
        scrollFrame, sp, so = Gate.ElementEnd(entries[R])
    end
    -- The shift chain from it, and the edge at its end.
    local from, fromPoint, off = AnchorChain(track, track.chain, usedSet, goesLeft, scrollFrame, sp, so)
    track.chainUsed = usedSet
    track.shiftConst = usedSet * pitch
    track.shift:ClearAllPoints()
    track.shift:SetPoint("CENTER", from, fromPoint, off, 0)
    -- The row end: after the last live icon, or the shift edge with the
    -- chain's own length undone while none is on cooldown.
    local ef, ep, eo
    if L > R and entries then
        ef, ep, eo = Gate.ElementEnd(entries[L])
    else
        ef, ep, eo = track.shift, "CENTER", -result * track.shiftConst
    end
    -- Each lane's place: a ready one its number of a pitch past the start,
    -- one on cooldown past the row end; a hidden one parked at the rail.
    for i = 1, #kickers do
        local k, laneRec = kickers[i], lanes[i]
        laneRec.clip:ClearAllPoints()
        if not laneRec.shown then
            laneRec.clip:SetPoint(inner, track, inner, 0, 0)
        elseif CdRunning(laneRec.cell) then
            local num = laneRec.slotNo - L - 1 - (readyBy[k.marker] or 0)
            laneRec.clip:SetPoint(inner, ef, ep, eo + result * num * pitch, 0)
        else
            local num = laneRec.slotNo - R - 1
            laneRec.clip:SetPoint(inner, scrollFrame, sp, so + result * num * pitch, 0)
        end
        laneRec.clip:SetShown(laneRec.shown)
    end
    -- The hug chain from the row end, one pair per marker with cooldown
    -- lanes, and the hug frame its length back from the chain's end.
    local hugChain = track.hugChain
    local usedHug, wsum = 0, 0
    for markerTex = 1, 8 do
        local num = cdBy[markerTex] or 0
        if num > 0 then
            local wid = num * pitch
            usedHug = usedHug + 1
            local plateRow = hugChain[usedHug] or BuildPair(track, usedHug, hugChain)
            plateRow.marker = markerTex
            plateRow.std:SetWidth(wid)
            plateRow.rev:SetWidth(wid)
            wsum = wsum + wid
        end
    end
    from, fromPoint, off = AnchorChain(track, hugChain, usedHug, goesLeft, ef, ep, eo)
    track.hugUsed = usedHug
    track.hug:ClearAllPoints()
    track.hug:SetPoint(goesLeft and "LEFT" or "RIGHT", from, fromPoint, off - result * wsum, 0)
    if (usedSet > 0 or usedHug > 0) and track.unit then
        local position = GetRaidTargetIndex(track.unit)
        if type(position) == "number" then
            FeedChain(track, position)
        end
    end
end

local function AcquireRail(unitToken)
    local num = #Rails.free
    local track
    if num > 0 then
        track = Rails.free[num]
        Rails.free[num] = nil
    else
        track = BuildRail()
    end
    Rails.railOf[unitToken] = track
    Rails.count = Rails.count + 1
    return track
end

function Rails.Release(unitToken)
    local track = Rails.railOf[unitToken]
    if not track then
        return
    end
    Rails.railOf[unitToken] = nil
    Rails.count = Rails.count - 1
    local backing = track.cuiPlate
    WatchCast(track, nil)
    -- Each dressed lane's gate goes to its floor (a plain value): the rail
    -- draws no lane until its next plate's index is fed. Its count gate is
    -- whole again from plain values (DressRail feeds it on the next plate).
    for i = 1, #track.lanes do
        local laneRec = track.lanes[i]
        if laneRec.floor then
            laneRec.gate:SetValue(laneRec.floor)
        end
        if laneRec.cCur ~= nil then
            Rails.LaneFeed(laneRec, nil, nil, 0)
        end
    end
    track.feed = nil
    track:Hide()
    track:ClearAllPoints()
    track:SetParent(parked)
    track.edge:ClearAllPoints()
    track.edge:SetParent(parked)
    track.unit, track.cuiPlate, track.placedHost, track.placedGen = nil, nil, nil, nil
    track.rel, track.relBottom, track.row = nil, nil, nil
    Rails.free[#Rails.free + 1] = track
    -- Live icons still on the plate hung from the rail's shift edge: they
    -- take the bar again.
    if onPlate[unitToken] then
        LayoutPlate(unitToken)
    end
    ArrowsFollow(backing)
    if driverFrame and liveCount == 0 and Rails.count == 0 then
        driverFrame:Hide()
    end
end

function Rails.ReleaseAll()
    for unitToken in pairs(Rails.railOf) do
        Rails.Release(unitToken)
    end
end

-- A plate's rail: up while the plate is a marked hostile and a kicker is
-- cached, its lanes dressed, every gate fed the plate's marker index.
function Rails.SyncPlate(unitToken)
    if currentMode ~= MODE_LIVE or #Rails.kickers == 0 or not NAMEPLATE_UNITS[unitToken] then
        Rails.Release(unitToken)
        return
    end
    local position = GetRaidTargetIndex(unitToken)
    if type(position) ~= "number" or not IsHostile(unitToken) then
        Rails.Release(unitToken)
        return
    end
    local owner, isCUI = ResolveHost(unitToken)
    if not owner then
        Rails.Release(unitToken)
        return
    end
    Ready()
    local track = Rails.railOf[unitToken] or AcquireRail(unitToken)
    if track.styleGen ~= styleStamp or track.kickGen ~= Rails.gen then
        StyleRail(track)
    end
    DressRail(track)
    track.unit = unitToken
    if track.placedHost ~= owner or track.placedGen ~= styleStamp then
        Place(track, owner, isCUI)
    end
    LayoutPlate(unitToken)
    FeedRail(track, position)
    track.feed = true
    track:Show()
    if not driverFrame:IsShown() then
        driverAcc = 0
        driverFrame:Show()
    end
end

-- Every plate on screen (a marker moved, the cache or the roster changed).
function Rails.SyncAll()
    if currentMode ~= MODE_LIVE or #Rails.kickers == 0 then
        Rails.ReleaseAll()
        return
    end
    for i = 1, #NAMEPLATE_TOKENS do
        local u = NAMEPLATE_TOKENS[i]
        if UnitExists(u) then
            Rails.SyncPlate(u)
        else
            Rails.Release(u)
        end
    end
end

-- A kicker's live icon came onto a plate (hidden = true) or left every plate:
-- their lane on every rail follows, and each rail's plate lays its icons out
-- again (the lane's slot and the chain changed).
function Rails.SetLiveHidden(kicker, isHidden)
    isHidden = isHidden == true
    if (Rails.liveHidden[kicker] == true) == isHidden then
        return
    end
    Rails.liveHidden[kicker] = isHidden or nil
    if not Rails.laneOf[kicker] then
        return
    end
    for unitToken, track in pairs(Rails.railOf) do
        if track.placedHost then
            LayoutPlate(unitToken)
        end
    end
    -- The lane back (the live icon's plate went): its count gate against the
    -- ghosts that may hold the kicker's kick meanwhile.
    if not isHidden then
        local current = KE.Count(kicker)
        if current ~= nil then
            Rails.Counts(kicker, current, GetTime())
        end
    end
end

function Rails.Cooldown(kicker, start, duration)
    local i = Rails.laneOf[kicker]
    if not i then
        return
    end
    for _, track in pairs(Rails.railOf) do
        local laneRec = track.lanes[i]
        if laneRec and laneRec.kicker == kicker then
            PaintCooldown(laneRec.cell, start, duration)
        end
    end
end

-- The engine's counts event for member u (and a ghost coming or going):
-- their lane on every rail fed their count as read now (Rails.LaneFeed).
function Rails.Counts(unit, current, T)
    local i = Rails.laneOf[unit]
    if not i then
        return
    end
    for _, track in pairs(Rails.railOf) do
        local laneRec = track.lanes[i]
        if laneRec and laneRec.kicker == unit then
            Rails.LaneFeed(laneRec, unit, current, T)
        end
    end
end

-- The driver's pass: a rail follows its unit's plate as the icons do.
function Rails.Follow(plateList)
    if Rails.count == 0 then
        return
    end
    for unitToken, track in pairs(Rails.railOf) do
        local p = plateList and plateList[unitToken]
        if p ~= track.cuiPlate then
            if p and p.health then
                Place(track, p, true)
            elseif track.cuiPlate then
                Rails.Release(unitToken)
            end
        elseif p and track.row ~= SideRow(p) then
            Place(track, p, true)
        end
        -- The one deferred feed of a freshly placed rail, once it is visible.
        if track.feed and Rails.railOf[unitToken] == track and track:IsVisible() then
            track.feed = nil
            local position = GetRaidTargetIndex(unitToken)
            if type(position) == "number" then
                FeedRail(track, position)
            end
        end
    end
end

-- A settings write: every rail is sized, placed and painted again.
function Rails.Restyle()
    for unitToken in pairs(Rails.railOf) do
        Rails.SyncPlate(unitToken)
    end
end

-- The rail on an CludesUI plate, for the target arrows: only while it
-- shows a lane (every lane hidden, nothing of it is on screen).
function Rails.OnPlate(backing)
    for _, track in pairs(Rails.railOf) do
        if track.cuiPlate == backing then
            if track.shownCount > 0 then
                return track
            end
            return nil
        end
    end
    return nil
end

-- The marker frame: a zone-in forgets the cache; a login or reload restores
-- it once the zone has settled (Settled); the addon channel feeds it (your
-- own sends come back too and are skipped), a request on it is answered, and
-- the roster filling up inside asks.
local function OnMarkerEvent(_, event, a1, a2, a3)
    if event == "PLAYER_ENTERING_WORLD" then
        if a1 or a2 then
            Rails.pendingRestore = true
        else
            Rails.pendingRestore = false
            ForgetMarkers()
        end
    elseif event == "CHAT_MSG_ADDON" then
        if a1 ~= Rails.PREFIX or (a3 ~= "PARTY" and a3 ~= "INSTANCE_CHAT") then
            return
        end
        local textValue = PlainString(a2)
        if not textValue then
            return
        end
        local kind, markerKey, unitGuid = textValue:match("^([FR])\t([0-8])\t(Player%-%d+%-%x+)$")
        if not kind or unitGuid == PlainString(UnitGUID("player")) then
            return
        end
        Rails.Learn(unitGuid, tonumber(markerKey))
        if kind == "R" then
            Reply()
        end
    elseif event == "GROUP_ROSTER_UPDATE" then
        Request()
    end
end

-- The zone settled after a loading screen (the Where watcher's RECHECK): the
-- addon channel and the roster are heard only inside a Mythic dungeon or key
-- (MarkerInstance), a
-- pending login or reload restore runs here, where the instance reads true,
-- and a zone-in or a fresh enable asks the group (ask).
function Rails.Settled(ask)
    local frame = Rails.frame
    if not frame then
        return
    end
    if MarkerInstance() then
        frame:RegisterEvent("CHAT_MSG_ADDON")
        frame:RegisterEvent("GROUP_ROSTER_UPDATE")
    else
        frame:UnregisterEvent("CHAT_MSG_ADDON")
        frame:UnregisterEvent("GROUP_ROSTER_UPDATE")
    end
    if Rails.pendingRestore then
        Rails.pendingRestore = false
        RestoreMarkers()
    end
    if ask then
        Request()
    end
end

-- From KT_Refresh: the marker frame and the addon prefix while the plates are
-- enabled; a fresh enable restores the saved markers of this instance and
-- asks the group.
function Rails.SyncEvents(on)
    if not on then
        Rails.on = false
        if Rails.frame then
            Rails.frame:UnregisterAllEvents()
        end
        return
    end
    local fresh = not Rails.on
    Rails.on = true
    if not Rails.frame then
        Rails.frame = CreateFrame("Frame")
        Rails.frame:SetScript("OnEvent", OnMarkerEvent)
    end
    if not Rails.prefixRegistered and C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        Rails.prefixRegistered = true
        C_ChatInfo.RegisterAddonMessagePrefix(Rails.PREFIX)
    end
    Rails.frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    Rails.pendingRestore = false
    RestoreMarkers()
    Rails.Settled(fresh)
end

--------------------------------------------------------------------------------
--  Preview: looping sample icons on every visible hostile plate, painted from
--  plain class tokens through the same paths a kick takes. Staggered so the
--  countdown shows at different stages side by side.
--------------------------------------------------------------------------------
local function PreviewUnit(unitToken)
    if not NAMEPLATE_UNITS[unitToken] or not IsHostile(unitToken) then
        return
    end
    local owner, isCUI = ResolveHost(unitToken)
    if not owner then
        return
    end
    previewStep = previewStep + 1
    local off = ((previewStep - 1) % 3) * PREVIEW_CD / 3
    local classFile = PreviewClass(previewStep)
    local b = ShowIcon(
        "~" .. unitToken,
        nil,
        unitToken,
        owner,
        isCUI,
        classFile,
        PreviewTexture(classFile),
        GetTime() - off,
        PREVIEW_CD,
        true
    )
    b.restartAt = GetTime() - off + PREVIEW_CD + PREVIEW_REST
end

-- The plates already on screen, by unit token: a plate's namePlateUnitToken
-- can be nil when polled outside its NAME_PLATE_UNIT_ADDED.
local function SeedPreview()
    for i = 1, #NAMEPLATE_TOKENS do
        local u = NAMEPLATE_TOKENS[i]
        if UnitExists(u) then
            PreviewUnit(u)
        end
    end
end

--------------------------------------------------------------------------------
--  Events: one frame, registered by mode. Live: plate add (a kicker's icon
--  comes back with its plate where the GUID is plain) and removal; kicks come
--  from the engine. Preview: plate add and removal. Off: nothing.
--------------------------------------------------------------------------------
-- A plate came: every waiting icon and ghost whose mob this is (by plain
-- GUID, or the player's target while it counts on it) comes back onto it.
local function OnPlateAdded(unitToken)
    if currentMode == MODE_PREVIEW then
        PreviewUnit(unitToken)
        return
    end
    if next(isDetached) == nil and Ghosts.nWaiting == 0 then
        return
    end
    local g = PlainString(UnitGUID(unitToken))
    local isTarget = IsTargetPlate(unitToken)
    local owner, isCUI
    for key, b in pairs(isDetached) do
        if (g and b.guid == g) or (isTarget and b.waitTarget) then
            if not owner then
                owner, isCUI = ResolveHost(unitToken)
            end
            if owner then
                isDetached[key] = nil
                if b.styleGen ~= styleStamp then
                    StyleIcon(b)
                end
                PutOnPlate(b, unitToken, owner, isCUI)
                PaintKicker(b, b.kClass, b.kTex)
                PaintCooldown(b, b.cdStart, b.cdDur)
                b:Show()
                if not driverFrame:IsShown() then
                    driverAcc = 0
                    driverFrame:Show()
                end
            end
        end
    end
    if Ghosts.nWaiting > 0 then
        Ghosts.Return(unitToken, g, isTarget)
    end
end

local function OnEvent(_, event, unitToken)
    if event == "NAME_PLATE_UNIT_REMOVED" then
        PlateGone(unitToken)
        Rails.Release(unitToken)
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        if unitToken then
            OnPlateAdded(unitToken)
            Rails.SyncPlate(unitToken)
        end
    elseif event == "PLAYER_TARGET_CHANGED" then
        OnTargetChanged()
    elseif event == "RAID_TARGET_UPDATE" then
        Rails.SyncAll()
    end
end

-- Every mode change drops what is showing: leaving live clears its icons,
-- entering preview replaces them with samples, leaving preview clears those.
local function SetMode(mode)
    if mode == currentMode then
        return
    end
    if currentMode == MODE_LIVE then
        KE.Unsubscribe(WHERE_KEY)
    end
    currentMode = mode
    if evt then
        evt:UnregisterAllEvents()
    end
    ReleaseAll()
    if mode == MODE_OFF then
        return
    end
    if not evt then
        evt = CreateFrame("Frame")
        evt:SetScript("OnEvent", OnEvent)
    end
    local entries = (mode == MODE_LIVE) and LIVE_EVENTS or PREVIEW_EVENTS
    for i = 1, #entries do
        evt:RegisterEvent(entries[i])
    end
    if mode == MODE_LIVE then
        KE.Subscribe(WHERE_KEY, HANDLERS)
        Rails.SyncKickers()
        Rails.SyncAll()
    else
        SeedPreview()
    end
end

local function Enabled(conf)
    return conf and conf.enabled == true and conf.showPlates ~= false
end

-- The preview owns the display while it runs: it ignores the Where to Show
-- filter and real kicks. Leaving it re-applies the filter.
local function SyncState()
    local conf = Cfg()
    if not Enabled(conf) then
        previewing = false
        SetMode(MODE_OFF)
        return
    end
    if previewing then
        SetMode(MODE_PREVIEW)
        return
    end
    if KE.Allowed() and MTWhere.Shows(conf.whereToShow, WHERE_KEYS) then
        SetMode(MODE_LIVE)
    else
        SetMode(MODE_OFF)
    end
end

-- Shared Where to Show watcher: zone and combat edges switch the display on
-- or off; a loading screen clears every icon.
local function OnWhere(event)
    if event == "PLAYER_ENTERING_WORLD" then
        ReleaseAll()
    end
    SyncState()
    if event == "RECHECK" then
        Rails.Settled(true)
    end
    if event == "PLAYER_ENTERING_WORLD" and currentMode == MODE_PREVIEW and liveCount == 0 then
        SeedPreview()
    end
end

-- Settings write: the style is rebuilt and every icon still on its old stamp
-- re-places itself and repaints its kicker (the Icon setting may have moved)
-- and the greying of its running cooldown; ghosts and rails likewise.
local function RestyleLive()
    if AK then
        AK.Restyle(STYLE)
    end
    for key, b in pairs(icons) do
        if b.styleGen ~= styleStamp and b.unit then
            local owner, isCUI = ResolveHost(b.unit)
            if owner then
                StyleIcon(b)
                Place(b, owner, isCUI)
                local texture = b.kTex
                if b.kicker then
                    texture = KickerTexture(KE.Member(b.kicker))
                elseif b.preview then
                    texture = PreviewTexture(b.kClass)
                end
                PaintKicker(b, b.kClass, texture)
                PaintDesat(b, CdRunning(b))
            else
                PlateGone(b.unit)
            end
        end
    end
    Ghosts.Restyle()
    Rails.Restyle()
end

--------------------------------------------------------------------------------
--  Options header sample: a mock plate (a hostile health bar with a name)
--  the options kit hangs in its header, and two sample cells on it in slots
--  1 and 2, as two kickers on one enemy sit. A frame of ours, never the
--  options page pool's: the cells are foreign children and must stay.
--------------------------------------------------------------------------------
local function EnsureSamplePlate()
    if samplePlate then
        return samplePlate
    end
    local backing = CreateFrame("Frame", nil, UIParent)
    backing:SetSize(SAMPLE_PLATE_W, SAMPLE_PLATE_H)
    backing:Hide()
    local backdrop = backing:CreateTexture(nil, "BACKGROUND")
    backdrop:SetAllPoints(backing)
    backdrop:SetColorTexture(0.08, 0.08, 0.08, 0.9)
    local health = backing:CreateTexture(nil, "ARTWORK")
    health:SetPoint("TOPLEFT", backing, "TOPLEFT", 1, -1)
    health:SetPoint("BOTTOMRIGHT", backing, "BOTTOMRIGHT", -1, 1)
    health:SetColorTexture(0.78, 0.17, 0.17, 1)
    Pix.CreateBorder(backing, 0, 0, 0, 1, 1, "OVERLAY", 7)
    local name = backing:CreateFontString(nil, "OVERLAY")
    name:SetPoint("CENTER", backing, "CENTER", 0, 0)
    name:SetWordWrap(false)
    CludesUI.ApplyModuleFont(name, nil, 10, FONT_KEY)
    name:SetText(CludesUI.L("Enemy"))
    samplePlate = backing
    return backing
end

--------------------------------------------------------------------------------
--  Focus Announce: "My Focus Kick is {rtN}" in party chat at every ready
--  check inside a Mythic dungeon (difficulty 23 with no key running: never a
--  Mythic+ run, never any other content), or the player's own line from the
--  setting announceText (Edit Announce Text), where {marker} stands for the
--  raid marker and a line without it gets the marker at its end. READY_CHECK
--  is registered on a frame of ours only while a marker is set and the
--  tracker is on, so nothing runs elsewhere, and the content is checked at
--  the ready check itself.
--------------------------------------------------------------------------------
local announceMarker = 0 -- the marker the last sync saw (0 = off)
local announceFrame -- built on the first enable
local MARKER_TOKEN = "{marker}" -- where the raid marker goes in a custom line

-- True inside a Mythic dungeon with no key running.
local function MythicDungeon()
    if
        C_ChallengeMode
        and C_ChallengeMode.IsChallengeModeActive
        and C_ChallengeMode.IsChallengeModeActive()
    then
        return false
    end
    local _, iType, diffID = GetInstanceInfo()
    return iType == "party" and tonumber(diffID) == 23
end

-- The default line with {marker} where the raid marker goes: what Edit
-- Announce Text shows while no line of the player's own is saved.
function mod.KT_AnnounceDefault()
    return (CludesUI.L("My Focus Kick is %s"):gsub("%%s", MARKER_TOKEN))
end

-- The line sent for a marker: the player's own with {marker} swapped for the
-- raid marker (a function replacement, so a % in their text stays a %), the
-- marker added at the end when their line has none, else the default.
local function AnnounceLine(markerTex)
    local token = "{rt" .. markerTex .. "}"
    local conf = Cfg()
    local custom = conf and conf.announceText
    if type(custom) == "string" and custom ~= "" then
        local line, num = custom:gsub(MARKER_TOKEN, function()
            return token
        end)
        if num == 0 then
            line = line .. " " .. token
        end
        return line
    end
    return CludesUI.Lf("My Focus Kick is %s", token)
end

local function Announce(markerTex)
    if not MythicDungeon() then
        return
    end
    local channelling = Rails.Channel()
    if not channelling then
        return
    end
    C_ChatInfo.SendChatMessage(AnnounceLine(markerTex), channelling)
    -- The same marker on the addon channel for the marker defaults (Rails):
    -- before the key starts, as here, it still goes through.
    SendMarker("F")
end

-- From KT_Refresh: keeps the READY_CHECK registration with the setting, and
-- a marker set or cleared inside a Mythic dungeon or key tells every client inside at once
-- (the marker defaults need no ready check for it).
local function SyncAnnounce(conf)
    local markerTex = (conf and conf.enabled == true) and tonumber(conf.focusMarker) or 0
    if not (markerTex and markerTex >= 1 and markerTex <= 8) then
        markerTex = 0
    end
    announceMarker = markerTex
    if markerTex ~= Rails.marker then
        Rails.marker = markerTex
        if Rails.on and MarkerInstance() then
            SendMarker("F")
        end
    end
    if markerTex == 0 then
        if announceFrame then
            announceFrame:UnregisterEvent("READY_CHECK")
        end
        return
    end
    if not announceFrame then
        announceFrame = CreateFrame("Frame")
        announceFrame:SetScript("OnEvent", function()
            if announceMarker >= 1 then
                Announce(announceMarker)
            end
        end)
    end
    announceFrame:RegisterEvent("READY_CHECK")
end

--------------------------------------------------------------------------------
--  Public surface
--------------------------------------------------------------------------------
-- Options call this after every Kick Tracker settings write, and the module's
-- profile apply (_CUMT_Apply) after a profile switch or a Spec Override flip.
function mod.KT_Refresh()
    -- The bars (CUI_MythicTimer_KickBars.lua) read the same settings table.
    if mod.KTB_Refresh then
        mod.KTB_Refresh()
    end
    local conf = Cfg()
    SyncAnnounce(conf)
    Rails.SyncEvents(Enabled(conf))
    if not Enabled(conf) then
        MTWhere.Unsubscribe(WHERE_KEY)
        previewing = false
        SetMode(MODE_OFF)
        return
    end
    ReadSettings(conf)
    if not RegisterStyle() then
        return
    end
    RegisterGuest()
    -- New settings: the icon size and every icon's style are rebuilt.
    SyncScale(true)
    MTWhere.Subscribe(WHERE_KEY, OnWhere)
    SyncState()
    RestyleLive()
end

-- Sample icons on the live plates (the harness; the options page shows its
-- own header sample instead). Works only while the feature is enabled: the
-- refresh turns it back off otherwise, and reads the settings the samples
-- paint with.
function mod.KT_SetPreview(on)
    previewing = on == true
    mod.KT_Refresh()
end

function mod.KT_IsPreview()
    return previewing
end

-- Where a kicker's icon sits: its plate unit, "waiting" while its plate is
-- away, or nil. For /dump and the harness.
function mod.KT_IconPlate(kicker)
    local b = icons[kicker]
    if not b then
        return nil
    end
    return b.unit or (isDetached[kicker] and "waiting") or nil
end

-- The marker defaults, for /dump and the harness: the lanes on a plate's
-- rail (nil: no rail), whether a kicker's lane stands down for their live
-- icon, and the marker cached for a member GUID.
function mod.KT_Defaults(unitToken)
    local track = Rails.railOf[unitToken]
    return track and #Rails.kickers or nil
end

function mod.KT_DefaultHidden(kicker)
    return Rails.liveHidden[kicker] == true
end

function mod.KT_MarkerOf(unitGuid)
    return Rails.markerOf[unitGuid]
end

-- The ghosts on a plate unit (with nil, every ghost, those waiting for their
-- mob's plate included), for /dump and the harness.
function mod.KT_Ghosts(unitToken)
    local liveSet, num = Ghosts.live, 0
    for i = 1, #liveSet do
        if unitToken == nil or liveSet[i].unit == unitToken then
            num = num + 1
        end
    end
    return num
end

-- /cuikt: the plates' state in chat for a field report. No hidden value is
-- read: the cached markers, the kickers and their lanes, each live icon's
-- plate, each ghost's plate, slot and candidates, and each rail's plate,
-- host and lanes.
function mod.KT_Dump()
    -- The engine first: which units' casts it hears and what it knows of
    -- each member (the warlock question of 2026-10-21).
    print("Kick Tracker engine: " .. KE.Listening())
    local mode = (currentMode == MODE_LIVE) and "live" or (currentMode == MODE_PREVIEW) and "preview" or "off"
    local cached = 0
    for _ in pairs(Rails.markerOf) do
        cached = cached + 1
    end
    local parts = {}
    for i = 1, #Rails.kickers do
        local k = Rails.kickers[i]
        parts[#parts + 1] = format(
            "%s marker %d lane %d%s",
            k.unit,
            k.marker,
            k.lane + 1,
            Rails.liveHidden[k.unit] and " (live icon up)" or ""
        )
    end
    print(
        format(
            "Kick Tracker plates: mode %s%s, %d marker(s) cached, instance %s, kickers: %s",
            mode,
            Lift.on and " (above overlapping plates)" or "",
            cached,
            tostring(Rails.inst),
            (#parts > 0) and table.concat(parts, "; ") or "none"
        )
    )
    for key, b in pairs(icons) do
        print(
            format(
                "  icon %s: %s%s%s",
                tostring(key),
                b.unit or (isDetached[key] and "waiting") or "parked",
                b.onTarget and " (the target)" or "",
                (b.cCur ~= nil) and " (count gate fed)" or ""
            )
        )
    end
    local nowTime = GetTime()
    for i = 1, #Ghosts.live do
        local g = Ghosts.live[i]
        local cands = {}
        for k = 1, g.used do
            cands[k] = g.subs[k].unit
        end
        print(
            format(
                "  ghost on %s: slot %d, t %.1f, candidates %s, %.1f s left",
                g.unit or (g.waiting and "waiting") or "?",
                g.slot or 0,
                g.t or 0,
                (#cands > 0) and table.concat(cands, ",") or "none",
                (g.expireAt or nowTime) - nowTime
            )
        )
    end
    for unitToken, track in pairs(Rails.railOf) do
        local lanes = {}
        for i = 1, #Rails.kickers do
            local laneRec = track.lanes[i]
            lanes[#lanes + 1] = format(
                "%d %s slot %d%s",
                i,
                laneRec.kicker or "-",
                laneRec.slotNo or 0,
                laneRec.shown and "" or " (hidden)"
            )
        end
        print(
            format(
                "  rail on %s: %s, %s, chain %d, feed %s, lanes: %s",
                unitToken,
                track.cuiPlate and "CludesUI plate" or "base plate",
                track:IsVisible() and "visible" or (track:IsShown() and "shown but not visible" or "hidden"),
                track.chainUsed or 0,
                track.feed and "pending" or "done",
                table.concat(lanes, " | ")
            )
        )
    end
    -- Every plate on screen: what its marker index reads as (its type and
    -- whether it is hidden; the value itself is never read).
    for i = 1, #NAMEPLATE_TOKENS do
        local u = NAMEPLATE_TOKENS[i]
        if UnitExists(u) then
            local position = GetRaidTargetIndex(u)
            print(
                format(
                    "  plate %s: marker index %s%s%s",
                    u,
                    type(position),
                    Secret(position) and " (hidden)" or "",
                    Rails.railOf[u] and ", rail" or ""
                )
            )
        end
    end
end
SLASH_CUIKICKTRACKER1 = "/cuikt"
SlashCmdList.CUIKICKTRACKER = function()
    mod.KT_Dump()
end

-- The options header's sample: the mock plate on `host` with two cells
-- beside it at the current settings (a Warrior, ready; a Mage with
-- SAMPLE_CD_LEFT seconds of swipe and countdown left, restarted on every
-- paint and plain once run out), whatever the enable state; the plate takes
-- the CludesUI plate's health bar size while that module is on, and sits
-- off the host's centre so the plate and the cells together are centred.
-- Returns the scene's width and height in the host's units, or nil with
-- nothing to paint from. The cells render at UIParent's scale like the live
-- icons, so the host must sit at that scale (the kit's fit stays 1 for this
-- column).
function mod.KT_PaintSampleIcon(owner)
    local conf = Cfg()
    if not conf then
        return nil
    end
    if not Enabled(conf) then
        -- Off: KT_Refresh left the snapshot and the style stale.
        ReadSettings(conf)
        if not RegisterStyle() then
            return nil
        end
        EnsurePool()
        SyncScale(true)
        AK.Restyle(STYLE)
    else
        -- On: KT_Refresh registered the style on the last write.
        AK = AK or CludesUI.AuraKit
        if not AK then
            return nil
        end
        EnsurePool()
        if SyncScale() then
            RegisterStyle()
            AK.Restyle(STYLE)
        end
    end
    -- The plate: the CludesUI plate's health bar size and offsets while
    -- that module is on (its plates are what the icons sit on), else the
    -- fallback plate and the other plates' offsets.
    local np = NPPlates() and CludesUI._ModuleNS.CludesUINameplates
    local pw, ph, offX, offY = SAMPLE_PLATE_W, SAMPLE_PLATE_H, sOthX, sOthY
    if np then
        pw, ph, offX, offY = np.GetHealthBarWidth(), np.GetHealthBarHeight(), sOffX, sOffY
    end
    local backing = EnsureSamplePlate()
    backing:SetParent(owner)
    backing:SetSize(pw, ph)
    backing:Show()
    for i = 1, 2 do
        local b = sampleList[i]
        if not b then
            b = BuildIcon()
            sampleList[i] = b
        end
        b.wrap:SetParent(backing)
        SetIconLevels(b, backing:GetFrameStrata(), backing:GetFrameLevel() + 2)
        b.rel, b.relBottom = backing, backing
        b.ox, b.oy = offX, offY
        b.slot = i
        -- The second cell hangs from the first's end, as in a row.
        b.hang, b.hangConst, b.prevEl = false, 0, (i == 2) and sampleList[1] or false
        b.iconFrame, b.casting, b.row = nil, false, nil
        b.preview, b.unit, b.key = nil, nil, nil
        if b.styleGen ~= styleStamp then
            StyleIcon(b)
        end
        AnchorIcon(b)
        local classFile = SAMPLE_CLASSES[i]
        PaintKicker(b, classFile, PreviewTexture(classFile))
        if i == 2 then
            PaintCooldown(b, GetTime() - (PREVIEW_CD - SAMPLE_CD_LEFT), PREVIEW_CD)
        else
            PaintCooldown(b, nil, nil)
        end
        b:Show()
    end
    -- The scene: the plate and the two cells (the snapped size, BuildStyle,
    -- not the setting) in plate-centred units, where AnchorIcon puts them.
    -- The plate then sits off the host's centre by the scene's lean, so the
    -- whole scene is centred whichever side the icons take.
    local cellFrame = Pix.Scale(iconPx)
    local along = 2 * cellFrame + ICON_GAP
    local bl, br, bt, bb = -pw / 2, pw / 2, ph / 2, -ph / 2
    local il, ir, it, ib
    if stackAnchor == "LEFT" then
        il, ir, it, ib = bl + offX - along, bl + offX, offY + cellFrame / 2, offY - cellFrame / 2
    elseif stackAnchor == "RIGHT" then
        il, ir, it, ib = br + offX, br + offX + along, offY + cellFrame / 2, offY - cellFrame / 2
    elseif stackAnchor == "TOP" then
        il, ir, it, ib = offX - cellFrame / 2, offX + along - cellFrame / 2, bt + offY + cellFrame, bt + offY
    else
        il, ir, it, ib = offX - cellFrame / 2, offX + along - cellFrame / 2, bb + offY, bb + offY - cellFrame
    end
    bl, br, bt, bb = min(bl, il), max(br, ir), max(bt, it), min(bb, ib)
    backing:ClearAllPoints()
    backing:SetPoint("CENTER", owner, "CENTER", -(bl + br) / 2, -(bt + bb) / 2)
    return ceil(br - bl), ceil(bt - bb)
end

-- Called from EMT:OnEnable with the Lite DB; the bars take it from here.
function mod.KT_OnEnable(database)
    saved = database
    if not saved then
        return
    end
    if mod.KTB_OnEnable then
        mod.KTB_OnEnable(database)
    end
    mod.KT_Refresh()
end
