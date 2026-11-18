if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
--------------------------------------------------------------------------------
--  CUI_MythicTimer_KickBars.lua - Kick Tracker bars (Mythic+ Tools).
--
--  One movable group with a row for each group member who has an interrupt
--  (you too), in roster order: the interrupt's icon, the member's name on a
--  bar in their class colour over a darker class colour (or a chosen colour)
--  and, while the interrupt cools down, the seconds left on the right with
--  the bar draining to the left (full again once it is back). Cooldowns come
--  from the kick engine (ns.KickEngine), which knows each member's class, spec
--  and talents, yours included.
--
--  The bar is the engine's own timer (a duration object: no Lua each frame);
--  only the seconds are painted, by a 10 Hz ticker that runs while any row is
--  cooling and stops itself after. Off, it costs nothing: no frames exist and
--  nothing listens, and the engine runs only while something subscribes.
--
--  Kicks the engine cannot attribute: every meter update also brings a "gate"
--  packet, each member who could have kicked with their interrupt count
--  before and after it (hidden numbers in combat). Each gets a layer over
--  their row: a copy of the row on that update's cooldown, inside a clip
--  whose left edge hangs from the fill of an invisible status bar given the
--  count before as its value and the count after as its maximum. The fill is
--  whole, and the clip empty, unless the count rose; then the clip opens over
--  the whole row. So only the member who kicked shows it, and Lua never learns
--  who. Layers are pooled, the newest on top, each with an opaque backing so
--  nothing below shows through, and freed when their cooldown ends, when a
--  known kick of that member replaces them, when the member's row goes, and
--  on every mode change. A member whose party token changes (the tokens close
--  up when someone leaves) keeps their layers on their new row.
--
--  The options page header shows a still sample of the same rows
--  (ns.KTB_PaintSample): built once, kept apart from the live rows, styled by
--  the same pass, with a plain fill and text instead of the timer and ticker.
--------------------------------------------------------------------------------
local _, ns = ...

local MTWhere, KE, KD = ns.MTWhere, ns.KickEngine, CludesUI.KickData
if not (MTWhere and KE and KD) then
    return
end

local db -- the module's settings handle, given by ns.KTB_OnEnable

local function Cfg()
    local profile = db and db.profile
    return profile and profile.kickTracker
end

local floor, ceil = math.floor, math.ceil
local GetTime = GetTime
local GetRaidTargetIndex, SetRaidTargetIconTexture = GetRaidTargetIndex, SetRaidTargetIconTexture
local PP = CludesUI.PP

-- Font family, outline and shadow are the module's ("mythicTimer"); only
-- sizes are settings. Rows show player names, so they take a font family
-- (Cyrillic, Korean and Chinese names draw), never a plain SetFont.
local function Font(text, size)
    CludesUI.ApplyModuleFontFamily(text, nil, size, "mythicTimer")
end

local IMMEDIATE = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate or 0
local ELAPSED = Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.ElapsedTime or 0
local REMAINING = Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime or 1
local WHITE = "Interface\\Buttons\\WHITE8x8"

local WHERE_KEY = "kickbars"
local WHERE_KEYS = MTWhere.NewKeySet(KE.WHERE_LIST)

local DEFAULT_X, DEFAULT_Y = -340, -120
local TICK = 0.1 -- how often the seconds are painted while a row cools
local TENTHS_BELOW = 10 -- under this many seconds left, show tenths
local DARK_SHARE = 0.3 -- the class colour's share in the dark background
local DARK_ALPHA = 0.9
local MARKER_GAP = 3 -- the kicked mob's raid marker sits this far outside the row
local MARKER_MAX = 24
local OFF, LIVE, PREVIEW_MODE = 0, 1, 2
-- A layer's gate is GATE_SPAN content widths long (each GATE_PAD wider), so
-- a count up by one opens the clip over the whole row for up to GATE_SPAN
-- interrupts in a fight; its right end sits GATE_EDGE past the content's.
local GATE_SPAN, GATE_PAD, GATE_EDGE = 100, 4, 2
local GATE_TALL = 24 -- the gate (and the clip) is this much taller than the row
local LEVELS_PER_LAYER = 3 -- a layer's frame levels: holder; bar and icon; text
local MAX_DEPTH = 29 -- the deepest stack of layers a row keeps in order

-- Sample rows: class, interrupt, fallback name, seconds left on a sample
-- cooldown (0 = ready), the raid marker of the mob kicked.
local SAMPLES = {
    { "WARRIOR", 6552, "Warrior", 0 },
    { "MAGE", 2139, "Mage", 9.1, 8 },
    { "DEATHKNIGHT", 47528, "Death Knight", 0 },
    { "SHAMAN", 57994, "Shaman", 4.4, 7 },
}
local SAMPLE_COUNT = 3 -- rows the options header shows by default

-- A sample row's name: its class, in the client's language.
local function SampleName(sample)
    local names = LOCALIZED_CLASS_NAMES_MALE
    return (names and names[sample[1]]) or sample[3]
end

--------------------------------------------------------------------------------
--  State
--------------------------------------------------------------------------------
local container -- the frame unlock mode drags; made when first needed
local rows = {} -- live rows, by slot
local inUse = 0 -- live rows shown
local sampleRows = {} -- the options header's rows: kept apart from `rows`
local rowOf = {} -- unit -> its row while shown
local markerOf = {} -- unit -> raid marker of the mob it last kicked (nil = none)
local markerGuid = {} -- unit -> its GUID at that kick (a new occupant shows no old marker)
local mode = OFF
local previewOn = false
local styleGen = 0 -- bumped by each settings write; a row restyles when its stamp differs
local ticker -- the seconds ticker; nil while idle
local unlockRegistered = false
local layersOf = {} -- unit -> its live layers, oldest first (each list kept)
local freeLayers = {} -- freed layers, for reuse
local moving = {} -- RelayLayers' scratch: layers following their member to a new token

--------------------------------------------------------------------------------
--  Container and position (unlock mode hands over a CENTER offset from
--  UIParent's centre, as for the cast bars)
--------------------------------------------------------------------------------
local function PlaceContainer()
    if not container then
        return
    end
    local settings = Cfg()
    local position = settings and settings.barPos
    container:ClearAllPoints()
    if position and position.centerX and position.centerY then
        container:SetPoint("CENTER", UIParent, "CENTER", position.centerX, position.centerY)
    else
        container:SetPoint("CENTER", UIParent, "CENTER", DEFAULT_X, DEFAULT_Y)
    end
end

local function Container()
    if not container then
        container = CreateFrame("Frame", nil, UIParent)
        container:SetSize(200, 22)
        container:Hide()
        PlaceContainer()
    end
    return container
end

--------------------------------------------------------------------------------
--  A row: holder > background + icon + status bar + texts. Made once per
--  slot and restyled by Style. Live rows hang from the container, sample
--  rows from the host the options page gives.
--------------------------------------------------------------------------------
local function NewRow(parent)
    local row = CreateFrame("Frame", nil, parent or Container())
    row:Hide()

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints(row)

    row.iconFrame = CreateFrame("Frame", nil, row)
    row.icon = row.iconFrame:CreateTexture(nil, "ARTWORK")
    row.icon:SetAllPoints(row.iconFrame)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.sb = CreateFrame("StatusBar", nil, row)
    -- A status bar has no texture object until one is set.
    row.sb:SetStatusBarTexture(WHITE)
    row.sb:SetMinMaxValues(0, 1)
    row.sb:SetValue(1)

    -- The texts ride a child frame so they draw above the fill and border.
    row.textFrame = CreateFrame("Frame", nil, row.sb)
    row.textFrame:SetAllPoints(row.sb)

    -- A font now as well as in Style: SetText on a fontless FontString errors.
    local function Text(justify)
        local text = row.textFrame:CreateFontString(nil, "OVERLAY")
        text:SetJustifyH(justify)
        text:SetWordWrap(false)
        text:SetMaxLines(1)
        Font(text, 11)
        return text
    end
    row.name = Text("LEFT")
    row.timer = Text("RIGHT")

    -- The kicked mob's raid marker, outside the row.
    row.marker = row:CreateTexture(nil, "ARTWORK")
    row.marker:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    row.marker:Hide()

    -- The bar's timer: the engine animates the fill from it.
    row.dur = C_DurationUtil.CreateDuration()
    return row
end

local function LiveRow(slot)
    local row = rows[slot]
    if not row then
        row = NewRow()
        rows[slot] = row
    end
    return row
end

--------------------------------------------------------------------------------
--  Style: size, texture, border, fonts, text layout. Once per settings change
--  per row.
--------------------------------------------------------------------------------
local function Style(row, settings)
    local width, height = settings.barWidth or 200, settings.barHeight or 22
    row:SetSize(width, height)

    local withIcon = settings.barShowIcon ~= false
    local iconRight = withIcon and settings.barIconOnRight == true
    local iconTex = row.iconFrame
    iconTex:ClearAllPoints()
    if iconRight then
        iconTex:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
        iconTex:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    else
        iconTex:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        iconTex:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    end
    iconTex:SetWidth(withIcon and height or 0.001)
    iconTex:SetShown(withIcon)

    local barFrame = row.sb
    barFrame:ClearAllPoints()
    if iconRight then
        barFrame:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        barFrame:SetPoint("BOTTOMRIGHT", iconTex, "BOTTOMLEFT", 0, 0)
    else
        barFrame:SetPoint("TOPLEFT", iconTex, "TOPRIGHT", 0, 0)
        barFrame:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    end
    barFrame:SetStatusBarTexture(
        CludesUI.ResolveTexturePath(ns.barTextures, settings.texture or "none", WHITE) or WHITE
    )
    PP.DisablePixelSnap(barFrame:GetStatusBarTexture())

    -- A black border on the row; size 0 removes it. The slider stores UI
    -- units, the border takes physical pixels.
    local border = PP.ToPixels(settings.barBorderSize or 0)
    if border > 0 then
        if not row.border then
            -- Kept: a layer sets its frame level with the rest of its row.
            row.border = PP.CreateBorder(row, 0, 0, 0, 1, border, "OVERLAY", 7) or true
        else
            PP.UpdateBorder(row, border)
        end
        PP.ShowBorder(row)
    elseif row.border then
        PP.HideBorder(row)
    end

    local timerSize = settings.barTimerSize or 11
    Font(row.name, settings.barNameSize or 11)
    Font(row.timer, timerSize)
    local withTimer = settings.barShowTimer ~= false
    local timerRoom = withTimer and timerSize * 2.4 or 0
    row.name:ClearAllPoints()
    row.name:SetPoint("LEFT", barFrame, "LEFT", 4, 0)
    row.name:SetWidth(math.max(1, (withIcon and (width - height) or width) - 8 - timerRoom))
    row.timer:ClearAllPoints()
    row.timer:SetPoint("RIGHT", barFrame, "RIGHT", -3, 0)
    row.name:SetShown(settings.barShowName ~= false)
    row.timer:SetShown(withTimer)

    -- The raid marker beside the row, at the end away from the icon.
    local size = math.min(math.max(height - 4, 8), MARKER_MAX)
    row.marker:SetSize(size, size)
    row.marker:ClearAllPoints()
    if iconRight then
        row.marker:SetPoint("RIGHT", row, "LEFT", -MARKER_GAP, 0)
    else
        row.marker:SetPoint("LEFT", row, "RIGHT", MARKER_GAP, 0)
    end
    row.showMarker = settings.barShowMarker ~= false
    -- How far the row reaches past its right edge (a layer's gate ends there).
    row.rightReach = iconRight and 0 or (MARKER_GAP + size)

    row.styleGen = styleGen
end

-- The row's place in the group, under `anchor` (the container by default).
local function Place(row, slot, settings, anchor)
    anchor = anchor or container
    row:ClearAllPoints()
    local offset = (slot - 1) * ((settings.barHeight or 22) + (settings.barSpacing or 2))
    if settings.barGrowUp then
        row:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 0, offset)
    else
        row:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, -offset)
    end
end

--------------------------------------------------------------------------------
--  Painting
--------------------------------------------------------------------------------
-- The member: their interrupt's icon, name and class colour; the background
-- a darker class colour or the chosen one. A layer's row also paints its
-- backing: the background's colour, opaque.
local function PaintMember(row, settings, class, kick, name)
    row.icon:SetTexture(kick and C_Spell.GetSpellTexture(kick) or WHITE)
    row.name:SetText(name or "")
    local color = class and C_ClassColor.GetClassColor(class)
    local region, g, b = 0.6, 0.6, 0.6
    if color then
        region, g, b = color:GetRGB()
    end
    row.sb:SetStatusBarColor(region, g, b)
    local br, bgTex, bb, ba
    if settings.barBgMode == "custom" then
        local c = settings.barBgColor
        if c then
            br, bgTex, bb, ba = c.r, c.g, c.b, c.a or 0.45
        else
            br, bgTex, bb, ba = 0, 0, 0, 0.45
        end
    else
        br, bgTex, bb, ba = region * DARK_SHARE, g * DARK_SHARE, b * DARK_SHARE, DARK_ALPHA
    end
    row.bg:SetColorTexture(br, bgTex, bb, ba)
    if row.cover then
        row.cover:SetColorTexture(br, bgTex, bb, 1)
    end
end

local StartTicker

-- The kicked mob's marker: beside the row while that kick's cooldown runs.
-- In a dungeon the index is hidden; it is drawn anyway, since
-- SetRaidTargetIconTexture takes a hidden cell. type() is the one test a
-- hidden value allows.
local function PaintMarker(row)
    local index = row.showMarker and row.readyAt and row.markerIdx
    if type(index) == "number" then
        SetRaidTargetIconTexture(row.marker, index)
        row.marker:Show()
    else
        row.marker:Hide()
    end
end

-- The row's cooldown: the bar drains from full at the kick to empty at
-- start + dur, the ticker paints the seconds. None (or ended): full (an ended
-- span read as elapsed time is 100%), no text, and the kick's marker goes.
local function PaintCooldown(row, start, dur)
    local now = GetTime()
    if start and dur and start + dur > now then
        row.dur:SetTimeFromStart(start, dur)
        row.sb:SetTimerDuration(row.dur, IMMEDIATE, REMAINING)
        row.readyAt = start + dur
        StartTicker()
    else
        row.dur:SetTimeFromStart(now - 1, 0.5)
        row.sb:SetTimerDuration(row.dur, IMMEDIATE, ELAPSED)
        row.readyAt = nil
        row.timer:SetText("")
        row.timeShown = nil
        row.markerIdx = nil
        if row.unit then
            markerOf[row.unit] = nil
        end
    end
    PaintMarker(row)
end

-- Seconds left: tenths under TENTHS_BELOW, whole seconds (rounded up) above.
-- Set only when the reading changes (timeShown: the tenths, or minus the
-- seconds); anything else that clears the text drops it.
local function PaintSeconds(row, left)
    if left < TENTHS_BELOW then
        local tenths = floor(left * 10 + 0.5)
        if row.timeShown ~= tenths then
            row.timeShown = tenths
            row.timer:SetFormattedText("%.1f", tenths / 10)
        end
    else
        local secs = ceil(left)
        if row.timeShown ~= -secs then
            row.timeShown = -secs
            row.timer:SetFormattedText("%d", secs)
        end
    end
end

--------------------------------------------------------------------------------
--  Layers (see the top): root > gate (an invisible status bar) + clip > a
--  full row, made once and pooled. The row sits exactly over its member's
--  row; only the clip's left edge moves, with the gate's fill. Nothing is
--  ever read back from a gate, a clip or anything anchored to them.
--------------------------------------------------------------------------------
local function NewLayer()
    local layer = CreateFrame("Frame", nil, Container())
    layer:Hide()
    layer:EnableMouse(false)
    -- The gate draws nothing; the clip and row are not its children, so they
    -- keep their alpha. Its fill does not snap to the pixel grid.
    local gate = CreateFrame("StatusBar", nil, layer)
    gate:EnableMouse(false)
    gate:SetStatusBarTexture(WHITE)
    gate:SetAlpha(0)
    local fillTex = gate:GetStatusBarTexture()
    fillTex:SetVertexColor(0, 0, 0, 0)
    if fillTex.SetSnapToPixelGrid then
        fillTex:SetSnapToPixelGrid(false)
        fillTex:SetTexelSnappingBias(0)
    end
    local clip = CreateFrame("Frame", nil, layer)
    clip:SetClipsChildren(true)
    clip:EnableMouse(false)
    local row = NewRow(clip)
    -- Opaque backing under the background: neither the member's own row nor
    -- an older layer shows through.
    row.cover = row:CreateTexture(nil, "BACKGROUND", nil, -8)
    row.cover:SetAllPoints(row)
    row:Show()
    layer.gate, layer.fill, layer.clip, layer.row = gate, fillTex, clip, row
    return layer
end

-- The counts into the gate (before as its value, after as its maximum), then
-- the clip hung from the fill again, so the clip never waits for a layout
-- the engine does not run for a moved fill: left edge on the fill's right
-- edge, right edge the gate's.
local function Feed(layer)
    local gate, fillTex, clip = layer.gate, layer.fill, layer.clip
    gate:SetMinMaxValues(0, layer.after)
    gate:SetValue(layer.before)
    clip:ClearAllPoints()
    clip:SetPoint("TOPLEFT", fillTex, "TOPRIGHT", 0, 0)
    clip:SetPoint("BOTTOMLEFT", fillTex, "BOTTOMRIGHT", 0, 0)
    clip:SetPoint("TOPRIGHT", gate, "TOPRIGHT", 0, 0)
    clip:SetPoint("BOTTOMRIGHT", gate, "BOTTOMRIGHT", 0, 0)
    layer.feed = nil
end

-- Frame levels from `base`: above the member's row, each layer above the
-- ones before it.
local function SetLevels(layer, base)
    layer:SetFrameLevel(base)
    layer.gate:SetFrameLevel(base)
    layer.clip:SetFrameLevel(base)
    local row = layer.row
    row:SetFrameLevel(base)
    row.iconFrame:SetFrameLevel(base + 1)
    row.sb:SetFrameLevel(base + 1)
    if type(row.border) == "table" then
        row.border:SetFrameLevel(base + 1)
    end
    row.textFrame:SetFrameLevel(base + 2)
end

local function LevelFor(memberRow, depth)
    return memberRow:GetFrameLevel() + LEVELS_PER_LAYER * (1 + math.min(depth, MAX_DEPTH))
end

-- The layer `depth` up its member's stack, over row `under`: styled and laid
-- exactly over it; the gate GATE_SPAN content widths long and GATE_TALL
-- taller, its right end GATE_EDGE past the content's (the marker's far edge
-- when the marker is on the right). A count that rose shortens the fill by
-- at least one content width, opening the clip over the row; one that did
-- not leaves the fill whole and the clip empty.
local function Lay(layer, under, settings, depth)
    local row = layer.row
    if row.styleGen ~= styleGen then
        Style(row, settings)
    end
    layer:ClearAllPoints()
    layer:SetAllPoints(under)
    row:ClearAllPoints()
    row:SetAllPoints(under)
    local gate = layer.gate
    local width, height = settings.barWidth or 200, settings.barHeight or 22
    gate:SetSize(GATE_SPAN * (width + MARKER_GAP + MARKER_MAX + GATE_PAD), height + GATE_TALL)
    gate:ClearAllPoints()
    gate:SetPoint("RIGHT", under, "RIGHT", (row.rightReach or 0) + GATE_EDGE, 0)
    SetLevels(layer, LevelFor(under, depth))
end

-- Back to the pool: hidden, its timer ended and its text and marker cleared
-- (its row has no unit, so no member's marker is touched), the gate whole.
local function Free(layer)
    layer:Hide()
    PaintCooldown(layer.row, nil, nil)
    layer.gate:SetMinMaxValues(0, 1)
    layer.gate:SetValue(1)
    layer.t, layer.unit, layer.guid, layer.before, layer.after, layer.feed = nil, nil, nil, nil, nil, nil
    freeLayers[#freeLayers + 1] = layer
end

-- A member's layers levelled again by their place (after some left).
local function Relevel(unit)
    local list, under = layersOf[unit], rowOf[unit]
    if list and under then
        for i, layer in ipairs(list) do
            SetLevels(layer, LevelFor(under, i - 1))
        end
    end
end

-- Frees a member's layers started at or before `upto` (all with nil).
local function FreeUnit(unit, upto)
    local list = layersOf[unit]
    if not list or #list == 0 then
        return
    end
    local freed = false
    for i = #list, 1, -1 do
        if upto == nil or list[i].t <= upto then
            Free(table.remove(list, i))
            freed = true
        end
    end
    if freed then
        Relevel(unit)
    end
end

local function FreeAll()
    for _, list in pairs(layersOf) do
        for i = #list, 1, -1 do
            Free(list[i])
            list[i] = nil
        end
    end
end

-- The ticker's pass over the layers: an ended one is freed, a running one
-- paints its seconds, one fed since the last pass is fed once more. Returns
-- whether any is left.
local function TickLayers(now)
    local any = false
    for unit, list in pairs(layersOf) do
        local freed = false
        for i = #list, 1, -1 do
            local layer = list[i]
            local readyAt = layer.row.readyAt
            if not readyAt or readyAt <= now then
                Free(layer)
                table.remove(list, i)
                freed = true
            else
                any = true
                if layer.feed then
                    Feed(layer)
                end
                PaintSeconds(layer.row, readyAt - now)
            end
        end
        if freed then
            Relevel(unit)
        end
    end
    return any
end

local function Tick()
    local now = GetTime()
    local any = false
    for i = 1, inUse do
        local row = rows[i]
        local readyAt = row.readyAt
        if readyAt then
            if readyAt - now <= 0 then
                PaintCooldown(row, nil, nil)
            else
                any = true
                PaintSeconds(row, readyAt - now)
            end
        end
    end
    if TickLayers(now) then
        any = true
    end
    if not any and ticker then
        ticker:Cancel()
        ticker = nil
    end
end

StartTicker = function()
    if not ticker then
        ticker = C_Timer.NewTicker(TICK, Tick)
        Tick()
    end
end

local function StopTicker()
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
end

--------------------------------------------------------------------------------
--  Layout: a row per member with an interrupt (or the samples), in roster
--  order; spare rows hide; the container takes the group's size.
--------------------------------------------------------------------------------
local function ShowRow(slot, settings, class, kick, name, start, dur, unit, marker)
    local row = LiveRow(slot)
    if row.styleGen ~= styleGen then
        Style(row, settings)
    end
    Place(row, slot, settings)
    row.unit, row.markerIdx = unit, marker
    PaintMember(row, settings, class, kick, name)
    PaintCooldown(row, start, dur)
    row:Show()
    return row
end

-- The group unit holding `guid` now that has a row, or nil.
local function UnitOf(guid)
    for _, unit in ipairs(KE.GROUP_UNITS) do
        local member = rowOf[unit] and KE.Member(unit)
        if member and member.guid == guid then
            return unit
        end
    end
    return nil
end

-- Every live layer over its member's row again (the rows were just laid
-- out): restyled after a settings change, its member painted, fed again (its
-- gate may have changed size or row) and once more on the next tick. A layer
-- whose slot now holds someone else follows its member to their new token,
-- placed by its kick's time; one whose member has no row goes. The moves are
-- collected first, so no list is made while the lists are walked.
local function Relay(settings)
    for unit, list in pairs(layersOf) do
        if #list > 0 then
            local member = rowOf[unit] and KE.Member(unit)
            local guid = member and member.guid
            for i = #list, 1, -1 do
                local layer = list[i]
                if not guid or layer.guid ~= guid then
                    table.remove(list, i)
                    local to = layer.guid and UnitOf(layer.guid)
                    if to then
                        layer.unit = to
                        moving[#moving + 1] = layer
                    else
                        Free(layer)
                    end
                end
            end
        end
    end
    for i, layer in ipairs(moving) do
        moving[i] = nil
        local list = layersOf[layer.unit]
        if not list then
            list = {}
            layersOf[layer.unit] = list
        end
        local at = #list + 1
        while at > 1 and list[at - 1].t > layer.t do
            at = at - 1
        end
        table.insert(list, at, layer)
    end
    for unit, list in pairs(layersOf) do
        if #list > 0 then
            local under, member = rowOf[unit], KE.Member(unit)
            local name = UnitName(unit)
            for i, layer in ipairs(list) do
                Lay(layer, under, settings, i - 1)
                PaintMember(layer.row, settings, member.class, member.kick, name)
                PaintMarker(layer.row)
                Feed(layer)
                layer.feed = true
            end
        end
    end
end

-- The group's frame: the size of the sample rows, which the player places.
-- Rows grow from its top or bottom edge and may run past it, so that edge
-- stays put whatever the live count.
local function GroupSize(settings)
    local height, spacing = settings and settings.barHeight or 22, settings and settings.barSpacing or 2
    local n = #SAMPLES
    return (settings and settings.barWidth) or 200, n * height + (n - 1) * spacing
end

local function Layout()
    local settings = Cfg()
    if not settings then
        return
    end
    Container()
    wipe(rowOf)
    local n = 0
    if mode == PREVIEW_MODE then
        local now = GetTime()
        for _, sample in ipairs(SAMPLES) do
            local left = sample[4]
            local _, cd = KD.Cooldown(sample[2])
            local start = left > 0 and (now - (cd - left)) or nil
            n = n + 1
            ShowRow(
                n,
                settings,
                sample[1],
                sample[2],
                SampleName(sample),
                start,
                left > 0 and cd or nil,
                nil,
                sample[5]
            )
        end
    elseif mode == LIVE then
        local withSelf = settings.barIncludeSelf ~= false
        for _, unit in ipairs(KE.GROUP_UNITS) do
            local member = KE.Member(unit)
            if member and member.guid and member.kick and (withSelf or unit ~= "player") then
                local start, dur = KE.Cooldown(unit)
                -- The marker belongs to the member who kicked, not the slot.
                local marker = markerOf[unit]
                if type(marker) == "number" and markerGuid[unit] ~= member.guid then
                    marker = nil
                    markerOf[unit] = nil
                end
                n = n + 1
                rowOf[unit] =
                    ShowRow(n, settings, member.class, member.kick, UnitName(unit), start, dur, unit, marker)
            end
        end
    end
    for i = n + 1, #rows do
        local row = rows[i]
        row:Hide()
        row.readyAt, row.unit, row.markerIdx = nil, nil, nil
        row.marker:Hide()
    end
    inUse = n
    Relay(settings)
    container:SetSize(GroupSize(settings))
    container:SetShown(n > 0 or mode == PREVIEW_MODE)
end

--------------------------------------------------------------------------------
--  The engine's calls
--------------------------------------------------------------------------------
-- A cooldown with a start is a known kick: it replaces the member's layers up
-- to it. A cleared one ends them all.
local function OnCooldown(unit, start, dur)
    if mode ~= LIVE then
        return
    end
    FreeUnit(unit, start and (start + 0.01) or nil)
    local row = rowOf[unit]
    if row then
        PaintCooldown(row, start, dur)
    end
end

local function OnRoster()
    if mode == LIVE then
        Layout()
    end
end

-- A known kick on a plate: the mob's raid marker rides the kicker's row while
-- that kick's cooldown runs (the cooldown call comes before or after this).
-- Read now, as the plate may be gone a moment later. In a dungeon the index
-- is hidden (type() still says number): kept as is, only handed back to the
-- game, never compared.
local function OnKick(plate, kicker)
    if mode ~= LIVE or not kicker then
        return
    end
    local index = plate and GetRaidTargetIndex(plate)
    if type(index) ~= "number" then
        index = nil
    end
    local member = KE.Member(kicker)
    markerOf[kicker] = index
    markerGuid[kicker] = member and member.guid or nil
    local row = rowOf[kicker]
    if row then
        row.markerIdx = index
        PaintMarker(row)
    end
end

-- The gate packet for the meter update at t: a layer over the row of each
-- member in `units`, on their cooldown from t, fed their count before and
-- after (hidden numbers, only handed to the gate), so it shows only where the
-- count rose. The marker is the first plate's kicked in that update;
-- `platesOnly` adds it to the layers already made for t. The engine's tables
-- are read here and never kept.
local function OnGate(t, units, before, after, plates, platesOnly)
    if mode ~= LIVE then
        return
    end
    local plate = plates and plates[1]
    local index = plate and GetRaidTargetIndex(plate)
    if type(index) ~= "number" then
        index = nil
    end
    if platesOnly then
        if type(index) == "number" then
            for _, list in pairs(layersOf) do
                for _, layer in ipairs(list) do
                    if layer.t == t then
                        layer.row.markerIdx = index
                        PaintMarker(layer.row)
                    end
                end
            end
        end
        return
    end
    local settings = Cfg()
    if not settings then
        return
    end
    local now = GetTime()
    for _, unit in ipairs(units) do
        local under = rowOf[unit]
        local dur = under and KE.KickDuration(unit)
        local member = dur and KE.Member(unit)
        local b, a = before[unit], after[unit]
        if member and member.guid and t + dur > now and b ~= nil and a ~= nil then
            local list = layersOf[unit]
            if not list then
                list = {}
                layersOf[unit] = list
            end
            local layer = table.remove(freeLayers) or NewLayer()
            list[#list + 1] = layer
            layer.t, layer.unit, layer.guid, layer.before, layer.after = t, unit, member.guid, b, a
            Lay(layer, under, settings, #list - 1)
            PaintMember(layer.row, settings, member.class, member.kick, UnitName(unit))
            layer.row.unit, layer.row.markerIdx = nil, index
            Feed(layer)
            PaintCooldown(layer.row, t, dur)
            layer:Show()
            layer.feed = true -- fed once more on the next tick
        end
    end
end

local ENGINE_CALLS = { kick = OnKick, cooldown = OnCooldown, roster = OnRoster, gate = OnGate }

--------------------------------------------------------------------------------
--  Modes
--------------------------------------------------------------------------------
local function SetMode(to)
    if to == mode then
        return
    end
    if mode == LIVE then
        KE.Unsubscribe(WHERE_KEY)
    end
    mode = to
    FreeAll()
    wipe(rowOf)
    wipe(markerOf)
    wipe(markerGuid)
    if to == OFF then
        StopTicker()
        for _, row in ipairs(rows) do
            row:Hide()
            row.readyAt = nil
        end
        inUse = 0
        if container then
            container:Hide()
        end
        return
    end
    if to == LIVE then
        KE.Subscribe(WHERE_KEY, ENGINE_CALLS)
    end
    Layout()
end

local function Enabled(settings)
    return settings and settings.enabled == true and settings.showBars ~= false
end

-- The preview owns the display while on: no Where to Show filter, no
-- engine. Leaving it applies the filter again.
local function Sync()
    local settings = Cfg()
    if not Enabled(settings) then
        previewOn = false
        SetMode(OFF)
    elseif previewOn then
        SetMode(PREVIEW_MODE)
    elseif KE.Allowed() and MTWhere.Shows(settings.whereToShow, WHERE_KEYS) then
        SetMode(LIVE)
    else
        SetMode(OFF)
    end
end

-- A loading screen ends the layers, as the engine ends its cooldowns there
-- (its cooldown calls repaint the rows). A mode change freed them already.
local function OnWhere(event)
    local was = mode
    Sync()
    if event == "PLAYER_ENTERING_WORLD" and mode ~= OFF and mode == was then
        FreeAll()
    end
end

--------------------------------------------------------------------------------
--  Unlock mode: one element for the group, registered once; hidden while the
--  bars are off.
--------------------------------------------------------------------------------
local function RegisterUnlock()
    if unlockRegistered then
        return
    end
    unlockRegistered = true
    CludesUI:RegisterUnlockElements({
        CludesUI.MakeUnlockElement({
            key = "EMT_KickBars",
            label = "Kick Tracker Bars",
            group = "Mythic+",
            order = 522,
            -- Sized by the options sliders (no drag handle); can match another
            -- element's size and be matched to.
            noResize = true,
            allowMatchSource = true,
            isHidden = function()
                return not Enabled(Cfg())
            end,
            getFrame = Container,
            getSize = function()
                return GroupSize(Cfg())
            end,
            setWidth = function(_, w)
                local settings = Cfg()
                if settings then
                    settings.barWidth = floor(w + 0.5)
                    ns.KTB_Refresh()
                end
            end,
            setHeight = function(_, h)
                local settings = Cfg()
                if not settings then
                    return
                end
                -- A row's share of the group's height.
                local n = #SAMPLES
                settings.barHeight = math.max(6, floor((h - (n - 1) * (settings.barSpacing or 2)) / n + 0.5))
                ns.KTB_Refresh()
            end,
            savePos = function(_, _, _, x, y)
                -- Unlock mode hands over CENTER offsets; on Cancel the frame is
                -- still where it was dragged, so the live position is never read.
                local settings = Cfg()
                if settings and x and y then
                    settings.barPos = { centerX = x, centerY = y }
                    if not CludesUI._unlockActive then
                        PlaceContainer()
                    end
                end
            end,
            loadPos = function()
                local settings = Cfg()
                local position = settings and settings.barPos
                if position and position.centerX and position.centerY then
                    return { point = "CENTER", relPoint = "CENTER", x = position.centerX, y = position.centerY }
                end
                return nil
            end,
            clearPos = function()
                local settings = Cfg()
                if settings then
                    settings.barPos = nil
                end
            end,
            applyPos = PlaceContainer,
        }),
    }, "CludesUIMythicTimer")

    CludesUI:RegisterUnlockModeListener("EMT_KickBars", function(active)
        if not Enabled(Cfg()) then
            return
        end
        -- Sample rows while placing; live rows again on leaving.
        ns.KTB_SetPreview(active == true)
        if not CludesUI.IsUnlockAnchored("EMT_KickBars") then
            PlaceContainer()
        end
    end)
end

--------------------------------------------------------------------------------
--  For the other files and the options page
--------------------------------------------------------------------------------
-- Called by the nameplate file's ns.KT_Refresh after every Kick Tracker
-- settings write and on the module's profile apply.
function ns.KTB_Refresh()
    if not Enabled(Cfg()) then
        MTWhere.Unsubscribe(WHERE_KEY)
        previewOn = false
        SetMode(OFF)
        return
    end
    styleGen = styleGen + 1
    MTWhere.Subscribe(WHERE_KEY, OnWhere)
    PlaceContainer()
    Sync()
    if mode ~= OFF then
        Layout()
    end
end

-- Unlock mode's sample rows (only while the bars are enabled).
function ns.KTB_SetPreview(on)
    previewOn = on == true
    ns.KTB_Refresh()
end

function ns.KTB_IsPreview()
    return previewOn
end

-- The options header's sample: the first `n` sample rows (SAMPLE_COUNT by
-- default) under `host`'s top left, styled at the current settings whatever
-- the enabled state, each cooldown a plain fill and a fixed seconds text
-- (never the timer or ticker, so they cost nothing while hidden). Returns
-- the group's width and height, or nil with no settings. These rows are kept
-- out of `rows`, so the layout, ticker and modes never see them.
function ns.KTB_PaintSample(owner, n)
    local settings = Cfg()
    if not settings then
        return nil
    end
    n = math.min(n or SAMPLE_COUNT, #SAMPLES)
    local now = GetTime()
    for i = 1, n do
        local row = sampleRows[i]
        if not row then
            row = NewRow(owner)
            sampleRows[i] = row
        end
        row:SetParent(owner)
        row.styleGen = nil
        Style(row, settings)
        Place(row, i, settings, owner)
        local sample = SAMPLES[i]
        PaintMember(row, settings, sample[1], sample[2], SampleName(sample))
        -- The cooldown as a still; readyAt stands for "cooling" (PaintMarker).
        local left = sample[4]
        local _, cd = KD.Cooldown(sample[2])
        row.sb:SetMinMaxValues(0, 1)
        if left > 0 and cd and cd > 0 then
            row.sb:SetValue(left / cd)
            PaintSeconds(row, left)
            row.readyAt = now + left
        else
            row.sb:SetValue(1)
            row.timer:SetText("")
            row.timeShown = nil
            row.readyAt = nil
        end
        row.markerIdx = sample[5]
        PaintMarker(row)
        row.unit = nil
        row:Show()
    end
    for i = n + 1, #sampleRows do
        sampleRows[i]:Hide()
    end
    local height, spacing = settings.barHeight or 22, settings.barSpacing or 2
    return settings.barWidth or 200, n * height + (n - 1) * spacing
end

-- Called from ns.KT_OnEnable with the module's settings handle.
function ns.KTB_OnEnable(database)
    db = database
    if db then
        RegisterUnlock()
        ns.KTB_Refresh()
    end
end
