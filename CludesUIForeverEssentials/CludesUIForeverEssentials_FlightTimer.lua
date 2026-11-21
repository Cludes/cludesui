if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
if not (CUI and CUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_FlightTimer.lua  (WoW Forever only)
--  Route display with an ETA for flight-master flights: a thin track between
--  the two ends, stops scrolling past a "you" marker. Route lengths come from
--  the game's TaxiPath data (CludesUIForeverEssentials_FlightTimerData.lua);
--  the client exposes no flight duration, so time is length / speed, with the
--  speed corrected by every flight that lands normally. The options page shows
--  the same display flying a sample route on a loop.
--
--  Known issue: a reload, relog or crash mid-flight drops the bar for the rest
--  of that flight. The client gives no destination or progress for a flight
--  already under way, and saving it would go stale across a logout or crash,
--  so the bar returns with the next takeoff instead.
-------------------------------------------------------------------------------
local _, module = ...
-- The options page pool's table (made by the core, filled in place when the
-- options addon loads): the settings preview reads a dress generation from
-- it at call time.
local POOL = CUI._Pool

local DEFAULT_SPEED = 30.4 -- yards per second; fitted to measured Classic flight times
local PREVIEW_SECONDS = 20
local PREVIEW_HOLD = 2 -- seconds a finished preview flight stays before the next
local TRACK_HEIGHT = 3
local PIN_SIZE = 14
-- Seconds before arrival a stop scrolls in at the track's right end.
local LOOKAHEAD = 60
local WHITE = "Interface\\Buttons\\WHITE8x8"
local STOP_ICON = "Interface\\Minimap\\Tracking\\FlightMaster"
-- Slow Fall's feather: "come down gently" reads as land here.
local EXIT_ICON = "Interface\\Icons\\Spell_Magic_FeatherFall"
local EXIT_SIZE = 28

-- Preview: a real two-stop route per faction as node id / name pairs, played
-- fast-forward in PREVIEW_SECONDS (the path the game flies between the ends).
local PREVIEW_ROUTES = {
    Horde = { 80, "Ratchet", 25, "Crossroads", 30, "Freewind Post", 40, "Gadgetzan" },
    Alliance = { 6, "Ironforge", 74, "Thorium Point", 71, "Morgan's Vigil", 5, "Lakeshire" },
}

-- Settings live in CludesUIDB.flightTimer; unset keys read these.
local DEFAULTS = {
    enabled = true,
    -- trackHeight: its own key; the retired bar style's `height` stays unread.
    width = 300,
    trackHeight = TRACK_HEIGHT,
    showEndCaps = true,
    texture = "none",
    bgTexture = "none",
    fillOpacity = 100,
    classColored = false,
    showSpark = false,
    sparkR = 1,
    sparkG = 1,
    sparkB = 1,
    bgR = 0.1,
    bgG = 0.1,
    bgB = 0.1,
    bgA = 0.8,
    borderSize = 1,
    borderR = 0,
    borderG = 0,
    borderB = 0,
    borderTexture = "solid",
    borderBehind = false,
    exitBorderCustom = false,
    -- Visibility controls retain the plain button border and white route marker.
    exitBorder = true,
    showSeparator = true,
    separatorHeight = PIN_SIZE + 4,
    customSeparator = false,
    -- destText / timeText: "none" hides; any other value (older saves hold a
    -- side from the retired bar style) shows.
    destText = "show",
    destSize = 12,
    destX = 0,
    destY = 0,
    timeText = "show",
    timeSize = 12,
    timeX = 0,
    timeY = 0,
    showTotal = false,
    earlyExit = true,
    fade = false,
}

local BAR_TEXTURES, BAR_TEXTURE_NAMES, BAR_TEXTURE_ORDER = CUI.BuildBarTextureTables()

local routes = CUI._FlightTimerRoutes
local barFrame, events, ticker, hooked
local pending -- destination picked on the flight map, waiting for takeoff
local flight -- the flight in progress

local F = module.Feature("flightTimer", DEFAULTS, { point = "CENTER", relPoint = "CENTER", x = 0, y = 250 })
local Get, Cfg, Read, Enabled = F.Get, F.Cfg, F.Read, F.Enabled

-- The display's full height, centred on the track: end names above it, stop
-- icons and names below (the same room the stop strip clips to).
local function BoxHeight()
    local separator = Get("showSeparator") and Get("separatorHeight") or 0
    return math.max(PIN_SIZE, Get("trackHeight"), separator - 4) + 2 * (Get("destSize") + 8)
end

-- How much further a label must sit from a mark of this height, centred on
-- the track, to clear a track taller than the mark.
local function Rise(size) return math.max(0, (Get("trackHeight") - size) / 2) end

local function Speed() return Read().speed or DEFAULT_SPEED end

-- Frequent Flier, node 110300 of the Adventure Legacy tree (1188), makes
-- flight path mounts 20% faster. Legacy perks are bought per character. Both
-- lookups may return nothing (a character with no config for the tree), so a
-- missing answer reads as no perk rather than erroring at takeoff.
local function SpeedMultiplier()
    local configID = C_Traits.GetConfigIDByTreeID(1188)
    local node = configID and C_Traits.GetNodeInfo(configID, 110300)
    return (node and node.activeRank or 0) > 0 and 1.2 or 1
end

local function FormatTime(sec)
    sec = math.max(0, math.floor(sec + 0.5))
    return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

-- The time text of flight fl at elapsed seconds: the time left, plus the
-- full time with Show Total Time.
local function TimeLeft(fl, elapsed)
    local leftX = FormatTime(fl.eta - elapsed)
    return Get("showTotal") and (leftX .. " / " .. FormatTime(fl.eta)) or leftX
end

local function FillColor()
    if Get("classColored") then
        local _, class = UnitClass("player")
        local cc = class and CUI.GetClassColor(class)
        if cc then return cc.r, cc.g, cc.b end
    end
    local c = Read()
    if c.fillR then return c.fillR, c.fillG, c.fillB end
    local ACC = CUI.CLUDES_GREEN
    return ACC.r, ACC.g, ACC.b
end

-- Sums the stored length of every hop on the way to slot; nil when any hop
-- is missing from the data, which leaves the bar showing elapsed time only.
-- Also returns every node on the way, start first, each with the yards flown
-- to reach it (nil once a hop is missing).
local function RouteInfo(slot)
    local hops = GetNumRoutes(slot)
    if hops < 1 then return nil end
    -- The taxi UI can open without a map id; no id means no route lookup.
    local mapID = GetTaxiMapID and GetTaxiMapID()
    local nodes = mapID and C_TaxiMap and C_TaxiMap.GetAllTaxiNodes(mapID)
    local idBySlot = {}
    for _, node in ipairs(nodes or idBySlot) do
        idBySlot[node.slotIndex] = node.nodeID
    end
    local yards = 0
    local points = { { name = TaxiNodeName(TaxiGetNodeSlot(slot, 1, true)), yards = 0 } }
    for hop = 1, hops do
        local toSlot = TaxiGetNodeSlot(slot, hop, false)
        local from = idBySlot[TaxiGetNodeSlot(slot, hop, true)]
        local to = idBySlot[toSlot]
        local hopYards = from and to and routes[from * 10000 + to]
        yards = yards and hopYards and yards + hopYards
        points[#points + 1] = { name = TaxiNodeName(toSlot), yards = yards }
    end
    return yards and yards > 0 and yards or nil, points
end

-- Text in Forever Essentials' font and outline (Fonts page, else the global font).
local function StyleFont(fontStr, size) CUI.ApplyModuleFont(fontStr, nil, size, "essentials") end

-- A mark on the route (an end, a stop, "you"): an icon with a label.
local function NewMark(hostFrame, texture, wid, hgt)
    local m =
        { icon = hostFrame:CreateTexture(nil, "OVERLAY"), label = hostFrame:CreateFontString(nil, "OVERLAY") }
    m.icon:SetTexture(texture)
    m.icon:SetSize(wid, hgt or wid)
    m.label:SetWordWrap(false)
    return m
end

-- text: a string shows icon and label, nil the icon alone, false neither.
local function ShowMark(m, textValue)
    m.icon:SetShown(textValue ~= false)
    m.icon:SetAlpha(1)
    m.label:SetShown(textValue and true or false)
    m.label:SetAlpha(1)
    if textValue then
        StyleFont(m.label, Get("destSize"))
        m.label:SetText(textValue)
    end
end

-- ShowMark's text for a mark shown only when show; with names off, icon only.
local function MarkText(show, name, nameList)
    if not show then return false end
    return nameList and (name or "") or nil
end

-- Every function below draws into a display b (the bar on screen, or the
-- options preview) showing flight fl.

-- Puts the stop strip where elapsed has it, dims the stops already passed,
-- then slides it on. One long translation over the whole flight ran far too
-- fast in the client, so each slide is short and the 1 s ticker restarts the
-- next from the exact spot: no drift, and a slide slightly longer than a tick
-- never snaps back.
local SLIDE = 1.25
local function ScrollStrip(b, fl, elapsed)
    local clip = b.clip
    if not clip:IsShown() then return end
    local g = clip.glide
    g:Stop()
    clip.strip:ClearAllPoints()
    clip.strip:SetPoint("CENTER", b, "CENTER", -elapsed * clip.pps, 0)
    if elapsed < fl.eta then
        g.move:SetOffset(-SLIDE * clip.pps, 0)
        g:Play()
    end
    local flown = elapsed / fl.eta * fl.yards
    for k = 1, #fl.points - 2 do
        local posY = fl.points[k + 1].yards
        if posY and posY <= flown then
            b.stops[k].icon:SetAlpha(0.4)
            b.stops[k].label:SetAlpha(0.4)
        end
    end
end

-- A side-scroller: the two ends hold still at the track's ends and "you" at
-- its centre. Stops scroll in from the right as they near, cross "you" the
-- moment they are reached, and run out to the left.
local function LayoutRoute(b, fl)
    local points = fl and fl.points
    local num = points and #points or 0
    local nameList = Get("destText") ~= "none"
    local dx, dy = Get("destX"), Get("destY")
    local level = b.track:GetFrameLevel() + 3
    b.over:SetFrameLevel(level)
    b.clip:SetFrameLevel(level)

    -- The ends: a dot in the fill colour (Show End Caps) with the node's name
    -- above it; a hidden dot still places its name.
    local caps = Get("showEndCaps")
    for index = 1, 2 do
        local m, side = b.ends[index], index == 1 and "LEFT" or "RIGHT"
        ShowMark(m, MarkText(num > 0, num > 0 and points[index == 1 and 1 or num].name, nameList))
        if not caps then m.icon:Hide() end
        m.icon:SetVertexColor(FillColor())
        m.label:ClearAllPoints()
        m.label:SetPoint("BOTTOM" .. side, m.icon, "TOP" .. side, dx, 4 + dy + Rise(PIN_SIZE / 2))
        -- Each end name gets at most 47% of the bar's width; a longer one is cut off.
        m.label:SetWidth(Get("width") * 0.47)
        m.label:SetJustifyH(side)
    end

    -- Where each stop sits comes from its arrival time, known only with route
    -- lengths and an ETA. After an early landing request the route ends at the
    -- next stop; stops already passed would keep sliding out, so the strip
    -- and "you" go entirely.
    local moving = points and fl.eta and fl.yards and not fl.early
    local scroll = moving and num > 2
    local clip = b.clip
    clip:SetShown(scroll)
    if scroll then
        -- Inside the two end dots, tall enough for a stop's icon and the name
        -- under it.
        clip:ClearAllPoints()
        clip:SetPoint(
            "BOTTOMLEFT",
            b,
            "LEFT",
            PIN_SIZE / 2,
            -PIN_SIZE / 2 - Get("destSize") - 8 - Rise(PIN_SIZE)
        )
        clip:SetPoint("TOPRIGHT", b, "RIGHT", -PIN_SIZE / 2, PIN_SIZE / 2 + 2)
        -- px per second of flight: a stop comes in LOOKAHEAD seconds out
        -- (scaled down with the clock for a fast-forward preview).
        clip.pps = Get("width") / 2 / (fl.lookahead or LOOKAHEAD)
    end
    -- b.stops[k] is the stop at points[k + 1]; leftovers from a longer
    -- route are hidden.
    for k = 1, math.max(num - 2, #b.stops) do
        local posY = scroll and k <= num - 2 and points[k + 1].yards
        local m = b.stops[k]
        if posY and not m then
            m = NewMark(clip.strip, STOP_ICON, PIN_SIZE)
            b.stops[k] = m
        end
        if m then
            ShowMark(m, MarkText(posY, posY and points[k + 1].name, nameList))
            m.label:ClearAllPoints()
            m.label:SetPoint("TOP", m.icon, "BOTTOM", 0, -4 - Rise(PIN_SIZE))
            if posY then
                m.icon:ClearAllPoints()
                m.icon:SetPoint("CENTER", clip.strip, "CENTER", posY / fl.yards * fl.eta * clip.pps, 0)
            end
        end
    end
    if scroll then ScrollStrip(b, fl, math.max(0, math.min(GetTime() - fl.start, fl.eta))) end

    -- "You are here": a white post at the centre, where each stop is reached;
    -- a direct flight has no stops to reach, so none.
    ShowMark(b.you, MarkText(scroll, CUI.L("You"), nameList))
    local iconTex = b.you.icon
    local height = Get("separatorHeight")
    local texture, size = Get("borderTexture"), Get("borderSize")
    if
        scroll
        and Get("showSeparator")
        and Get("customSeparator")
        and size > 0
        and CUI.GetBorderCompanion(texture, "sepV")
    then
        if not b.separatorAnchor then b.separatorAnchor = CreateFrame("Frame", nil, b.over) end
        local anchor = b.separatorAnchor
        anchor:ClearAllPoints()
        anchor:SetPoint("TOPLEFT", b, "CENTER", 0, height / 2)
        anchor:SetSize(1, height)
        CUI.PlaceBorderDividerV(
            iconTex,
            anchor,
            false,
            false,
            texture,
            size,
            CUI.BorderPx(Get("borderSizePx"), size, texture),
            b.over:GetEffectiveScale()
        )
        iconTex:SetVertexColor(Get("borderR"), Get("borderG"), Get("borderB"), 1)
    else
        iconTex:SetTexture(WHITE)
        iconTex:SetTexCoord(0, 1, 0, 1)
        iconTex:SetVertexColor(1, 1, 1, 1)
        iconTex:ClearAllPoints()
        iconTex:SetPoint("CENTER", b, "CENTER")
        iconTex:SetSize(2, height)
        iconTex:SetShown(scroll and Get("showSeparator"))
    end
    b.you.label:ClearAllPoints()
    b.you.label:SetPoint("BOTTOM", b, "CENTER", 0, math.max(height, Get("trackHeight")) / 2 + 2)
end

local RequestLanding -- the early exit button's click; defined with the flight code

-- Separate hosts let size 0 hide the border without hiding the track or button.
local function StyleBorder(ownerFrame, isExit)
    local Pix = CUI.PP
    local owner = ownerFrame.travelBorder
    if isExit and not Get("exitBorder") then
        Pix.HideBorder(ownerFrame)
        if owner then
            CUI.HideBorderStyle(owner)
            owner:Hide()
        end
        return
    end
    -- A saved style (including Solid) opts into exact sizing; old sizes stay capped.
    local custom
    if isExit then
        custom = Get("exitBorderCustom")
    else
        custom = Read().borderTexture ~= nil or Get("borderSizePx")
    end
    if not custom then
        if owner then
            CUI.HideBorderStyle(owner)
            owner:Hide()
        end
        local size, red, green, blue = 1, 0, 0, 0
        if not isExit then
            local cap = math.floor((Get("trackHeight") / (Pix.mult or 1) - 1) / 2)
            size = math.max(0, math.min(Get("borderSize"), cap))
            red, green, blue = Get("borderR"), Get("borderG"), Get("borderB")
        end
        if Pix.GetBorders(ownerFrame) then
            Pix.UpdateBorder(ownerFrame, size, red, green, blue, 1)
        else
            Pix.CreateBorder(ownerFrame, red, green, blue, 1, size, "OVERLAY", 2)
        end
        if size > 0 then
            Pix.ShowBorder(ownerFrame)
        else
            Pix.HideBorder(ownerFrame)
        end
        return
    end
    Pix.HideBorder(ownerFrame)
    if not owner then
        owner = CreateFrame("Frame", nil, ownerFrame)
        owner:SetAllPoints(ownerFrame)
        ownerFrame.travelBorder = owner
    end
    owner:SetFrameLevel(
        Get("borderBehind") and math.max(0, ownerFrame:GetFrameLevel() - 1) or ownerFrame:GetFrameLevel() + 1
    )
    local size, texture = Get("borderSize"), Get("borderTexture")
    local prefixText = isExit and "exitBorder" or "borderTexture"
    CUI.ApplyBorderStyle(
        owner,
        size,
        Get("borderR"),
        Get("borderG"),
        Get("borderB"),
        1,
        texture,
        Get(prefixText .. "Offset"),
        Get(prefixText .. "OffsetY"),
        Get("borderTextureShiftX"),
        Get("borderTextureShiftY"),
        nil,
        nil,
        nil,
        CUI.BorderPx(Get("borderSizePx"), size, texture)
    )
end

-- Early exit button right of the bar, built on first enable. Greyed out once a
-- landing is requested, as Blizzard's leave button does.
local function StyleExit(b, fl)
    local button = b.exit
    if not Get("earlyExit") then
        if button then button:Hide() end
        return
    end
    if not button then
        button = CreateFrame("Button", nil, b)
        button:SetSize(EXIT_SIZE, EXIT_SIZE)
        button:SetPoint("LEFT", b, "RIGHT", PIN_SIZE / 2 + 6, 0)
        button:SetNormalTexture(EXIT_ICON)
        button:GetNormalTexture():SetTexCoord(0.08, 0.92, 0.08, 0.92) -- trim the icon frame
        button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        button:SetScript("OnClick", function() RequestLanding(b) end)
        button:SetScript(
            "OnEnter",
            function(self) CUI.ShowWidgetTooltip(self, CUI.L("Land at the next flight point")) end
        )
        button:SetScript("OnLeave", function() CUI.HideWidgetTooltip() end)
        b.exit = button
    end
    StyleBorder(button, true)
    local done = fl and fl.early
    button:SetEnabled(not done)
    button:SetAlpha(done and 0.4 or 1)
    button:Show()
end

local function StyleBar(widget, fl)
    local track = widget.track
    widget:SetSize(Get("width"), BoxHeight())
    track:SetHeight(Get("trackHeight"))
    track:SetStatusBarTexture(CUI.ResolveTexturePath(BAR_TEXTURES, Get("texture"), WHITE))
    -- The fill's one alpha owner: a texture's SetAlpha and its colour alpha
    -- are the same channel. A plain SetValue does not reliably take the fill
    -- back from an armed SetTimerDuration, so an elapsed-only flight hides it.
    local cr, cg, callback = FillColor()
    track:SetStatusBarColor(cr, cg, callback, (fl and not fl.eta) and 0 or Get("fillOpacity") / 100)
    track.bg:SetTexture(CUI.ResolveTexturePath(BAR_TEXTURES, Get("bgTexture"), WHITE))
    track.bg:SetVertexColor(Get("bgR"), Get("bgG"), Get("bgB"), Get("bgA"))
    StyleBorder(track)
    -- The time sits left of the track, mirroring the early exit button on the
    -- right; under the track is the stop names' lane.
    widget.time:SetShown(Get("timeText") ~= "none")
    StyleFont(widget.time, Get("timeSize"))
    widget.time:ClearAllPoints()
    widget.time:SetPoint("RIGHT", widget, "LEFT", -PIN_SIZE / 2 - 6 + Get("timeX"), Get("timeY"))
    LayoutRoute(widget, fl)
    local spark = widget.spark
    if Get("showSpark") and fl and fl.eta and Get("fillOpacity") > 0 then
        if not spark then
            spark = track:CreateTexture(nil, "OVERLAY")
            spark:SetTexture("Interface\\AddOns\\CludesUI\\media\\textures\\shields\\pixels-glowline.tga")
            spark:SetBlendMode("ADD")
            widget.spark = spark
        end
        -- The fill texture's edge moves with the native timer, without polling.
        spark:ClearAllPoints()
        spark:SetPoint("CENTER", track:GetStatusBarTexture(), "RIGHT", 0, 0)
        spark:SetSize(5, Get("trackHeight"))
        spark:SetVertexColor(Get("sparkR"), Get("sparkG"), Get("sparkB"), Get("fillOpacity") / 100)
        spark:Show()
    elseif spark then
        spark:Hide()
    end
    StyleExit(widget, fl)
end

-- An invisible box around the whole display, sized by StyleBar: the unlock
-- mover takes the frame's own size, so this gives it a grabbable area. The
-- track is the thin line through its middle.
local function BuildBar(hostFrame)
    local widget = CreateFrame("Frame", nil, hostFrame)
    local track = CreateFrame("StatusBar", nil, widget)
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT")
    track:SetMinMaxValues(0, 1)
    track:SetValue(0)
    track.bg = track:CreateTexture(nil, "BACKGROUND")
    track.bg:SetAllPoints()
    widget.track = track
    widget.time = widget:CreateFontString(nil, "OVERLAY")
    widget.time:SetJustifyH("RIGHT")
    -- Border hosts and their PP children sit above the track; marks stay on top.
    widget.over = CreateFrame("Frame", nil, widget)
    widget.over:SetAllPoints()
    widget.ends = { NewMark(widget.over, WHITE, PIN_SIZE / 2), NewMark(widget.over, WHITE, PIN_SIZE / 2) }
    widget.ends[1].icon:SetPoint("CENTER", widget, "LEFT")
    widget.ends[2].icon:SetPoint("CENTER", widget, "RIGHT")
    widget.you = NewMark(widget.over, WHITE, 2, PIN_SIZE + 4)
    widget.you.icon:SetPoint("CENTER", widget, "CENTER")
    -- The stops ride a strip inside a clipping frame (see ScrollStrip).
    widget.clip = CreateFrame("Frame", nil, widget)
    widget.clip:SetClipsChildren(true)
    widget.clip.strip = CreateFrame("Frame", nil, widget.clip)
    widget.clip.strip:SetSize(1, 1)
    widget.clip.glide = widget.clip.strip:CreateAnimationGroup()
    widget.clip.glide.move = widget.clip.glide:CreateAnimation("Translation")
    widget.clip.glide.move:SetSmoothing("NONE")
    widget.clip.glide.move:SetDuration(SLIDE)
    widget.stops = {}
    return widget
end

local function CreateBar()
    if barFrame then return end
    barFrame = BuildBar(UIParent)
    barFrame:Hide()
    StyleBar(barFrame, flight)
    F.Place(barFrame)
end

local RefreshPreview -- the options preview's restyle; defined with it below

local function ApplyStyle()
    if barFrame then StyleBar(barFrame, flight) end
    RefreshPreview()
end

-- Shows or hides the bar, faded in and out when the setting is on. Same fade
-- as CludesUI's widget tooltips: 0.25 s, easing out on show, in on hide.
local FADE_TIME = 0.25
local function ShowBar(show)
    local g = barFrame.fade
    if g then g:Stop() end
    if not Get("fade") then
        barFrame:SetAlpha(1)
        barFrame:SetShown(show)
        return
    end
    if not show and not barFrame:IsShown() then return end
    if not g then
        g = barFrame:CreateAnimationGroup()
        g.alpha = g:CreateAnimation("Alpha")
        g.alpha:SetDuration(FADE_TIME)
        g:SetScript("OnFinished", function(self)
            barFrame:SetAlpha(self.to)
            if self.to == 0 then barFrame:Hide() end
        end)
        barFrame.fade = g
    end
    if show and not barFrame:IsShown() then
        barFrame:SetAlpha(0)
        barFrame:Show()
    end
    g.to = show and 1 or 0
    g.alpha:SetFromAlpha(barFrame:GetAlpha())
    g.alpha:SetToAlpha(g.to)
    g.alpha:SetSmoothing(show and "OUT" or "IN")
    g:Play()
end

local function EndFlight()
    flight = nil
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
    if barFrame then ShowBar(false) end
end

local Land

local function UpdateText()
    local elapsed = GetTime() - flight.start
    if elapsed > 2 and not UnitOnTaxi("player") then
        -- Landing edge missed (PLAYER_CONTROL_GAINED is the precise one): end the
        -- flight here instead of running on, but learn nothing from a late read.
        flight.early = true
        Land()
    elseif flight.eta then
        barFrame.time:SetText(TimeLeft(flight, elapsed))
        ScrollStrip(barFrame, flight, elapsed)
    else
        barFrame.time:SetText(FormatTime(elapsed))
    end
end

local function ArmTimer(b, fl)
    if not fl.eta then return end
    local dur = C_DurationUtil.CreateDuration()
    dur:SetTimeFromStart(fl.start, fl.eta)
    b.track:SetTimerDuration(
        dur,
        Enum.StatusBarInterpolation.Immediate,
        Enum.StatusBarTimerDirection.ElapsedTime
    )
end

-- points: every node on the way, start first (see RouteInfo).
local function StartFlight(yards, points)
    flight = { yards = yards, start = GetTime(), points = points }
    if yards then
        flight.mult = SpeedMultiplier()
        flight.eta = yards / (Speed() * flight.mult)
    end
    CreateBar()
    ArmTimer(barFrame, flight)
    ShowBar(true)
    StyleBar(barFrame, flight)
    UpdateText()
    if not ticker then ticker = C_Timer.NewTicker(1, UpdateText) end
end

-- An early landing stops at the next node on the way: the timer and the
-- route end there instead. Nothing is learned from it.
-- Assumes the server lands at the very next node: a request made right on top
-- of one may land at the node after, and the bar then ends early.
local function Retarget(b, fl)
    fl.early = true
    local points = fl.points
    if points and fl.yards and fl.eta then
        local flown = (GetTime() - fl.start) / fl.eta * fl.yards
        for index, p in ipairs(points) do
            if p.yards and p.yards > flown then
                for jdx = #points, index + 1, -1 do
                    points[jdx] = nil
                end
                fl.eta = fl.eta * p.yards / fl.yards
                fl.yards = p.yards
                ArmTimer(b, fl)
                break
            end
        end
    end
    StyleBar(b, fl)
end

-- Moves the stored speed a quarter of the way toward what this flight measured.
-- A flight more than a third off the estimate is treated as bad data, not a speed.
-- The stored speed excludes Frequent Flier so every character can share it.
Land = function()
    if flight.yards and not flight.early then
        local measured = flight.yards / (GetTime() - flight.start) / flight.mult
        local speed = Speed()
        if measured > speed * 0.75 and measured < speed * 1.33 then
            Cfg().speed = speed + (measured - speed) * 0.25
        end
    end
    EndFlight()
end

local function OnEvent(_, evt)
    if evt == "PLAYER_CONTROL_LOST" then
        -- UnitOnTaxi is still false when this fires at takeoff, so a fresh
        -- flight-map click is the signal. A click the server refused leaves
        -- pending behind; a takeoff minutes later must not start a flight from
        -- it. A stun right after a refused click is ended by UpdateText's
        -- not-on-taxi check two seconds in.
        if pending and GetTime() - pending.clicked < 5 then StartFlight(pending.yards, pending.points) end
        pending = nil
    elseif evt == "PLAYER_CONTROL_GAINED" then
        if flight and not UnitOnTaxi("player") then Land() end
    end
end

local function OnTakeTaxiNode(slot)
    if not Enabled() then return end
    local yards, points = RouteInfo(slot)
    pending = { yards = yards, points = points, clicked = GetTime() }
end

local function Apply()
    if Enabled() then
        if not hooked then
            hooksecurefunc("TakeTaxiNode", OnTakeTaxiNode)
            hooksecurefunc("TaxiRequestEarlyLanding", function()
                if flight then
                    Retarget(barFrame, flight)
                    UpdateText()
                end
            end)
            hooked = true
        end
        if not events then
            events = CreateFrame("Frame")
            events:SetScript("OnEvent", OnEvent)
        end
        events:RegisterEvent("PLAYER_CONTROL_LOST")
        events:RegisterEvent("PLAYER_CONTROL_GAINED")
    else
        if events then events:UnregisterAllEvents() end
        pending = nil
        if flight then EndFlight() end
    end
end

-------------------------------------------------------------------------------
--  Options preview: the same display in the Travel page's content header,
--  flying a real route of the player's faction (PREVIEW_ROUTES) on a loop,
--  sped up. Built when the page first opens; its ticker runs only while it is
--  visible, so a closed panel or another page costs nothing.
-------------------------------------------------------------------------------
local preview -- view, bar, the sample route and the flight drawn from it
local StartPreviewFlight

local function PreviewTick()
    local val, fl = preview, preview.flight
    local elapsed = GetTime() - fl.start
    -- The finished flight holds a moment, then the next one starts.
    if elapsed >= fl.eta + PREVIEW_HOLD then return StartPreviewFlight() end
    elapsed = math.min(elapsed, fl.eta)
    val.bar.time:SetText(TimeLeft(fl, elapsed))
    ScrollStrip(val.bar, fl, elapsed)
end

StartPreviewFlight = function()
    local val = preview
    local fl, points = val.flight, val.points
    -- An early landing cuts the route short: refill it from the full one.
    for index, p in ipairs(val.route) do
        points[index] = p
    end
    for index = #val.route + 1, #points do
        points[index] = nil
    end
    fl.points, fl.yards, fl.start, fl.early = points, val.yards, GetTime(), nil
    fl.eta = PREVIEW_SECONDS
    fl.lookahead = LOOKAHEAD * PREVIEW_SECONDS / (val.yards / Speed())
    ArmTimer(val.bar, fl)
    StyleBar(val.bar, fl)
    PreviewTick()
end

local RefreshPreviewNow -- RefreshPreview's body, defined below

local function PreviewShow()
    if preview.ticker then return end
    StartPreviewFlight()
    -- Settings may have changed while the page was away.
    RefreshPreviewNow()
    preview.ticker = C_Timer.NewTicker(1, PreviewTick)
end

local function PreviewHide()
    if preview.ticker then
        preview.ticker:Cancel()
        preview.ticker = nil
    end
    preview.bar.clip.glide:Stop()
end

-- The preview's early exit button lands the sample flight at its next stop.
local function PreviewLanding()
    local fl = preview.flight
    if fl.early then return end
    Retarget(preview.bar, fl)
    PreviewTick()
end

RequestLanding = function(b)
    if b == barFrame then
        -- The hook on TaxiRequestEarlyLanding retargets the bar.
        if flight and not flight.early then TaxiRequestEarlyLanding() end
    else
        PreviewLanding()
    end
end

-- force: draw while the header is still being built (not shown yet).
RefreshPreview = function(force)
    local val = preview
    if not (val and (force or val.view:IsVisible())) then return end
    RefreshPreviewNow()
end

RefreshPreviewNow = function()
    local val = preview
    -- Scaled down when the bar, the time on its left and the early exit
    -- button on its right are wider than the header.
    local wid = Get("width") + 2 * (PIN_SIZE / 2 + 6 + EXIT_SIZE)
    local pw = val.view:GetParent():GetWidth()
    local available = (pw > 0 and pw) or val.availableWidth or wid + 40
    local scale = math.min(1, math.max(100, available - 40) / wid)
    val.bar:SetScale(scale)
    StyleBar(val.bar, val.flight)
    val.previewHeight = BoxHeight() * scale + 30
    val.view:SetHeight(val.previewHeight)
    if val.onHeightChanged then val.onHeightChanged(val.previewHeight) end
end

-- parent -> the dress its size hook was made for: the options page pool
-- (CludesUI_FramePool.lua) resets a kept header root before each build,
-- which drops the hook, so a new dress (Pool.Gen) hooks again; a plain frame
-- (no Gen) is hooked once.
local hookedParents = {}
local function CreateSettingsPreview(hostFrame, availableWidth, onHeightChanged)
    local val = preview
    if not val then
        local route = PREVIEW_ROUTES[UnitFactionGroup("player")] or PREVIEW_ROUTES.Alliance
        val = { route = {}, points = {}, flight = {}, yards = 0 }
        for index = 1, #route, 2 do
            if index > 1 then val.yards = val.yards + routes[route[index - 2] * 10000 + route[index]] end
            val.route[#val.route + 1] = { name = route[index + 1], yards = val.yards }
        end
        val.view = CreateFrame("Frame", nil, hostFrame)
        val.bar = BuildBar(val.view)
        val.bar:SetPoint("CENTER")
        val.view:SetScript("OnShow", PreviewShow)
        val.view:SetScript("OnHide", PreviewHide)
        preview = val
        StartPreviewFlight()
    end
    -- Frames outlive a page rebuild, so the view is reused.
    val.availableWidth, val.onHeightChanged = availableWidth, onHeightChanged
    val.view:SetParent(hostFrame)
    val.view:ClearAllPoints()
    val.view:SetPoint("TOPLEFT")
    val.view:SetPoint("TOPRIGHT")
    local dress = POOL.Gen and POOL.Gen(hostFrame) or true
    if hookedParents[hostFrame] ~= dress then
        hookedParents[hostFrame] = dress
        local lastWidth
        hostFrame:HookScript("OnSizeChanged", function(_, width)
            if width == lastWidth then return end
            lastWidth = width
            if val.view:GetParent() == hostFrame then RefreshPreview() end
        end)
    end
    val.view:Show()
    RefreshPreview(true)
    -- A new frame starts shown, so no OnShow fires for the first open.
    if val.view:IsVisible() then PreviewShow() end
    return val
end

-- Options-page entry points.
CUI._FlightTimer = {
    Get = Get,
    Cfg = Cfg,
    Apply = Apply,
    ApplyStyle = ApplyStyle,
    ApplyPosition = function() F.Place(barFrame) end,
    textures = { lookup = BAR_TEXTURES, names = BAR_TEXTURE_NAMES, order = BAR_TEXTURE_ORDER },
    CreateSettingsPreview = CreateSettingsPreview,
}

F.Start(Apply, {
    key = "CUI_FlightTimer",
    label = "Flight Timer",
    order = 730,
    minWidth = 50,
    frame = function(build)
        if build then CreateBar() end
        return barFrame
    end,
    -- Follows the text around the track.
    height = BoxHeight,
    applyStyle = ApplyStyle,
})
