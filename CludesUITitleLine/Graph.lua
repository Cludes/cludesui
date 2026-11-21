-- The graph window: your rating against the lines over the season, both
-- extended at their recent pace, with the rating each key added underneath.
--
-- Layout, top to bottom: header, stat tiles (which double as the legend and
-- toggle the lines), the plot, the per-key strip, notes.

local _, mod = ...
if mod.standalone then return end
local DAY = mod.DAY
local C = mod.COLORS

local Graph = {}
mod.Graph = Graph

local W, PAD = 700, 16
local HEADER_H = 46
local TILE_T, TILE_H, TILE_GAP = HEADER_H + 14, 94, 8
local PL, PR = 62, 58 -- plot margins: value axis on the left, end labels on the right
local PT, PH = TILE_T + TILE_H + 28, 220
local PW = W - PL - PR
local STRIP_T, STRIP_H = PT + PH + 34, 30
local FOOT_T = STRIP_T + STRIP_H + 16
local H = FOOT_T + 34
-- The group row sits under the tiles while you are in a party, and pushes
-- everything below it down by GROUP_SHIFT.
local GROUP_T, GROUP_H, GROUP_LABEL_W = TILE_T + TILE_H + 10, 44, 52
local GROUP_SHIFT = GROUP_H + 10
local PARTY_REACH = 0.25 -- how far past you and the lines a groupmate may stretch the axis

local DEFAULT_SCALE = 1.15 -- the window, text and all, a little larger than UI size
local RECENT_DAYS = 28
local MIN_AHEAD, MAX_AHEAD = 14, 90 -- days drawn past today
local MEDIA = "Interface\\AddOns\\CludesUITitleLine\\Media\\"
local SHAPE_FILL = 0.85 -- the dot and diamond leave a clear margin in their 16px textures

local widget, plot, strip, hover, cross, tipText, segmented, message, set, panelFrame
local tiles = {}
local pools = {}
local fonts
local view -- the last render's scales and context, read by the hover

-- Building blocks ------------------------------------------------------------------

local function Color(regionFrame, cfg, a)
    regionFrame:SetColorTexture(cfg[1], cfg[2], cfg[3], a or cfg[4] or 1)
end

-- The game's own face, so every locale renders, at sizes of our choosing.
local function MakeFonts()
    fonts = {}
    local filePath, _, flags = GameFontHighlight:GetFont()
    for name, size in pairs({ title = 15, value = 20, body = 12, small = 11, tiny = 10 }) do
        local frame = CreateFont("TitleLineFont_" .. name)
        frame:SetFont(filePath, size, flags or "")
        fonts[name] = frame
    end
end

local function Paint(fontStr, font, cfg)
    fontStr:SetFontObject(fonts[font])
    fontStr:SetTextColor(cfg[1], cfg[2], cfg[3], cfg[4] or 1)
end

local function FS(hostFrame, font, c, layer)
    local fontStr = hostFrame:CreateFontString(nil, layer or "OVERLAY")
    Paint(fontStr, font, c)
    fontStr:SetWordWrap(false)
    return fontStr
end

local function Hairlines(frame, alpha)
    local edges = {}
    for _, e in ipairs({
        { "TOPLEFT", "TOPRIGHT", nil, 1 },
        { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 },
        { "TOPLEFT", "BOTTOMLEFT", 1, nil },
        { "TOPRIGHT", "BOTTOMRIGHT", 1, nil },
    }) do
        local tex = frame:CreateTexture(nil, "BORDER")
        tex:SetColorTexture(1, 1, 1, alpha)
        tex:SetPoint(e[1])
        tex:SetPoint(e[2])
        if e[3] then
            tex:SetWidth(e[3])
        else
            tex:SetHeight(e[4])
        end
        edges[#edges + 1] = tex
    end
    return edges
end

local function SetEdges(edges, alpha)
    for _, t in ipairs(edges) do
        t:SetColorTexture(1, 1, 1, alpha)
    end
end

local function Pool(make)
    local p = { items = {}, used = 0 }
    function p:Get()
        self.used = self.used + 1
        local o = self.items[self.used]
        if not o then
            o = make()
            self.items[self.used] = o
        end
        o:Show()
        return o
    end
    function p:Reset()
        for idx = 1, #self.items do
            self.items[idx]:Hide()
        end
        self.used = 0
    end
    return p
end

-- The client draws lines and solid fills with hard, aliased edges, so anything
-- that is not axis-aligned uses a white texture with a soft alpha edge, tinted
-- per use. Snapping is off so a fractional position stays smooth.
local function Smooth(regionFrame, file)
    regionFrame:SetTexture(MEDIA .. file, "CLAMP", "CLAMP", "LINEAR")
    regionFrame:SetSnapToPixelGrid(false)
    regionFrame:SetTexelSnappingBias(0)
    return regionFrame
end

-- `th` is the stroke as it should look. A smooth line is drawn twice as thick,
-- because half of its texture is the fade that does the anti-aliasing.
local function Line(pool, rel, x1, y1, x2, y2, cfg, a, th)
    local l = pool:Get()
    if pool.smooth then
        l:SetThickness((th or 2) * 2)
        l:SetVertexColor(cfg[1], cfg[2], cfg[3], a or 1)
    else
        l:SetThickness(th or 1)
        Color(l, cfg, a)
    end
    l:SetStartPoint("BOTTOMLEFT", rel, x1, y1)
    l:SetEndPoint("BOTTOMLEFT", rel, x2, y2)
    return l
end

-- A dot or diamond `size` across, on a ring in the surface colour so it reads
-- over any line. The shape fills SHAPE_FILL of its texture.
local function Marker(rings, marks, rel, posX, posY, c, size)
    for _, m in ipairs({ { rings, size + 4, C.surface }, { marks, size, c } }) do
        local t = m[1]:Get()
        local s = m[2] / SHAPE_FILL
        t:SetSize(s, s)
        t:ClearAllPoints()
        t:SetPoint("CENTER", rel, "BOTTOMLEFT", posX, posY)
        t:SetVertexColor(m[3][1], m[3][2], m[3][3], 1)
    end
end

local function Text(pool, font, c, anchorPoint, rel, relPoint, posX, posY, s)
    local fontStr = pool:Get()
    Paint(fontStr, font, c)
    fontStr:ClearAllPoints()
    fontStr:SetPoint(anchorPoint, rel, relPoint, posX, posY)
    fontStr:SetText(s)
    return fontStr
end

-- Scales ------------------------------------------------------------------------------

local function X(t) return (t - view.x0) / (view.x1 - view.x0) * PW end

local function Y(val) return (val - view.y0) / (view.y1 - view.y0) * PH end

-- Dashes along a path of plot points, the pattern running on across joins so
-- a curve dashes as evenly as a straight line.
local DASH_ON, DASH_OFF = 5, 4
local function DashedPath(pool, filePath, c)
    local phase = 0
    for idx = 2, #filePath do
        local x1, y1, x2, y2 = filePath[idx - 1][1], filePath[idx - 1][2], filePath[idx][1], filePath[idx][2]
        local dx, dy = x2 - x1, y2 - y1
        local len = math.sqrt(dx * dx + dy * dy)
        local place = 0
        while place < len do
            local cycle = phase % (DASH_ON + DASH_OFF)
            local enabled = cycle < DASH_ON
            local e = math.min(len, place + (enabled and (DASH_ON - cycle) or (DASH_ON + DASH_OFF - cycle)))
            if enabled then
                Line(
                    pool,
                    plot,
                    x1 + dx * place / len,
                    y1 + dy * place / len,
                    x1 + dx * e / len,
                    y1 + dy * e / len,
                    c
                )
            end
            phase = phase + (e - place)
            place = e
        end
    end
end

-- A segment in data space, clipped to the visible time window.
local function Segment(pool, ta, va, tb, vb, c, dashed, a, th)
    if tb < view.x0 or ta > view.x1 or tb <= ta then return end
    if ta < view.x0 then
        va = va + (vb - va) * (view.x0 - ta) / (tb - ta)
        ta = view.x0
    end
    if tb > view.x1 then
        vb = va + (vb - va) * (view.x1 - ta) / (tb - ta)
        tb = view.x1
    end
    local x1, y1, x2, y2 = X(ta), Y(va), X(tb), Y(vb)
    if dashed then
        DashedPath(pool, { { x1, y1 }, { x2, y2 } }, c)
    else
        Line(pool, plot, x1, y1, x2, y2, c, a, th)
    end
end

-- A line's fitted course from its last data point to the window's edge, as a
-- dashed curve.
-- The range 80% of past forecasts landed in, as thin strips behind the
-- projected line, widening the further ahead it reaches.
local function Band(s, c)
    local last = s.pts[#s.pts]
    local ta = math.max(last[1], view.x0)
    local xa = X(ta)
    for posX = xa, PW - 1, 3 do
        local t = view.x0 + (posX + 1.5) / PW * (view.x1 - view.x0)
        local lo, _, hi = mod.LineRange(s.pts, s.fit, t)
        local y0, y1 = math.max(0, Y(lo)), math.min(PH, Y(hi))
        if y1 > y0 then
            local r = pools.band:Get()
            r:ClearAllPoints()
            r:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", posX, y0)
            r:SetSize(math.min(3, PW - posX), y1 - y0)
            Color(r, c, 0.10)
        end
    end
end

local function Projection(pool, s, c)
    local last = s.pts[#s.pts]
    local ta = math.max(last[1], view.x0)
    if ta >= view.x1 then return end
    local num = math.max(2, math.ceil((X(view.x1) - X(ta)) / 6))
    local filePath = {}
    for idx = 0, num do
        local t = ta + (view.x1 - ta) * idx / num
        filePath[#filePath + 1] = { X(t), Y(mod.LineValue(s.pts, s.fit, t)) }
    end
    DashedPath(pool, filePath, c)
end

function mod.NiceStep(range, target)
    local raw = range / target
    local mag = 10 ^ math.floor(math.log(raw) / math.log(10))
    local norm = raw / mag
    local step = norm < 1.5 and 1 or norm < 3 and 2 or norm < 7 and 5 or 10
    return step * mag
end

-- The time window and value range for this render.
function mod.Window(context, mode, hidden)
    local nowTime, regionFrame, sum = context.now, context.region, context.summary
    local x0 = regionFrame.startsAt
    if mode ~= "season" then x0 = math.max(x0, nowTime - RECENT_DAYS * DAY) end

    -- Reach far enough ahead to show the crossings, within reason.
    local ahead = MIN_AHEAD
    for _, tier in ipairs(sum.tiers) do
        if tier.days and not hidden[tier.tier.key] then
            ahead = math.max(ahead, math.min(tier.days * 1.15 + 1, MAX_AHEAD))
        end
    end
    local x1 = nowTime + ahead * DAY
    -- The season view runs to the season's end.
    if mode == "season" and sum.endsAt and sum.endsAt > x1 then x1 = sum.endsAt end

    local lo, hi = math.huge, -math.huge
    local function take(val)
        if val then
            lo, hi = math.min(lo, val), math.max(hi, val)
        end
    end
    take(mod.ScoreAt(context.history.points, x0))
    for _, p in ipairs(context.history.points) do
        if p.t >= x0 then take(p.score) end
    end
    take(sum.you + sum.pace * (x1 - nowTime) / DAY)
    for _, tier in ipairs(sum.tiers) do
        if not hidden[tier.tier.key] then
            take(mod.LineValue(tier.pts, tier.fit, x0))
            for _, p in ipairs(tier.pts) do
                if p[1] >= x0 then take(p[2]) end
            end
            local low, _, high = mod.LineRange(tier.pts, tier.fit, x1)
            take(low)
            take(high)
        end
    end
    -- Groupmates may widen the range only a little: one far below would squash
    -- your line and the title lines into a sliver. Past that they sit on the
    -- edge, labelled with their rating (see DrawParty).
    local reach = math.max(hi - lo, 100) * PARTY_REACH
    local floor, ceil = lo - reach, hi + reach
    local function near(val)
        if val >= floor and val <= ceil then take(val) end
    end
    for _, m in ipairs(context.party or {}) do
        if m.score > 0 then
            near(m.score)
            for _, p in ipairs(m.seen and m.seen.pts or {}) do
                if p[1] >= x0 then near(p[2]) end
            end
        end
    end
    if hi - lo < 50 then
        lo, hi = lo - 25, hi + 25
    end
    local step = mod.NiceStep(hi - lo, 5)
    return {
        x0 = x0,
        x1 = x1,
        y0 = math.floor(lo / step) * step,
        y1 = math.ceil(hi / step) * step,
        step = step,
    }
end

-- The window ----------------------------------------------------------------------------

local function MakeSegmented(hostFrame, options)
    local box = CreateFrame("Frame", nil, hostFrame)
    local bw = 72
    box:SetSize(#options * bw + 2, 24)
    Hairlines(box, 0.10)
    box.buttons = {}
    function box:Refresh()
        for _, btn in ipairs(self.buttons) do
            local enabled = CludesUITitleLineDB.view == btn.value
            Color(btn.bg, C.raised, enabled and 1 or 0)
            local c = enabled and C.ink or (btn:IsMouseOver() and C.ink2 or C.muted)
            btn.text:SetTextColor(c[1], c[2], c[3])
        end
    end
    for idx, o in ipairs(options) do
        local widget = CreateFrame("Button", nil, box)
        widget:SetSize(bw, 22)
        widget:SetPoint("LEFT", 1 + (idx - 1) * bw, 0)
        widget.bg = widget:CreateTexture(nil, "BACKGROUND")
        widget.bg:SetAllPoints()
        widget.text = FS(widget, "small", C.muted)
        widget.text:SetPoint("CENTER")
        widget.text:SetText(o[2])
        widget.value = o[1]
        widget:SetScript("OnClick", function()
            CludesUITitleLineDB.view = o[1]
            if o[1] == "guild" and IsInGuild() then C_GuildInfo.GuildRoster() end
            Graph:Render()
        end)
        widget:SetScript("OnEnter", function() box:Refresh() end)
        widget:SetScript("OnLeave", function() box:Refresh() end)
        box.buttons[idx] = widget
    end
    return box
end

local function MakeClose(hostFrame)
    local widget = CreateFrame("Button", nil, hostFrame)
    widget:SetSize(24, 24)
    widget.lines = {}
    for idx, d in ipairs({ { -5, -5, 5, 5 }, { -5, 5, 5, -5 } }) do
        local l = Smooth(widget:CreateLine(nil, "OVERLAY"), "Line")
        l:SetThickness(3)
        l:SetStartPoint("CENTER", widget, d[1], d[2])
        l:SetEndPoint("CENTER", widget, d[3], d[4])
        widget.lines[idx] = l
    end
    local function tint(cfg)
        for _, l in ipairs(widget.lines) do
            l:SetVertexColor(cfg[1], cfg[2], cfg[3], 1)
        end
    end
    tint(C.muted)
    widget:SetScript("OnEnter", function() tint(C.ink) end)
    widget:SetScript("OnLeave", function() tint(C.muted) end)
    widget:SetScript("OnClick", function() hostFrame:Hide() end)
    return widget
end

local function MakeTile(idx, key)
    local total = #mod.TIERS + 1
    local wid = (W - 2 * PAD - (total - 1) * TILE_GAP) / total
    local t = CreateFrame("Button", nil, widget)
    t:SetSize(wid, TILE_H)
    t:SetPoint("TOPLEFT", PAD + (idx - 1) * (wid + TILE_GAP), -TILE_T)
    local backdrop = t:CreateTexture(nil, "BACKGROUND")
    backdrop:SetAllPoints()
    Color(backdrop, C.raised)
    t.edges = Hairlines(t, 0.06)
    t.swatch = t:CreateTexture(nil, "ARTWORK")
    t.swatch:SetSize(12, 2)
    t.swatch:SetPoint("TOPLEFT", 12, -15)
    t.label = FS(t, "small", C.ink2)
    t.label:SetPoint("LEFT", t.swatch, "RIGHT", 6, 0)
    t.value = FS(t, "value", C.ink)
    t.value:SetPoint("TOPLEFT", 12, -28)
    t.unit = FS(t, "small", C.muted)
    t.unit:SetPoint("BOTTOMLEFT", t.value, "BOTTOMRIGHT", 5, 2)
    t.levels = FS(t, "tiny", C.muted)
    t.levels:SetPoint("TOPRIGHT", -12, -10)
    t.sub = FS(t, "tiny", C.muted)
    t.sub:SetPoint("BOTTOMLEFT", 12, 26)
    t.need = FS(t, "tiny", C.ink2)
    t.need:SetPoint("BOTTOMLEFT", 12, 10)
    t.eta = FS(t, "tiny", C.ink2)
    t.eta:SetPoint("BOTTOMRIGHT", -12, 10)
    t.key = key
    if key == "you" then
        t:SetScript("OnClick", function()
            if t.canSwitch then
                CludesUITitleLineDB.showChar = (CludesUITitleLineDB.showChar == "current") and "best"
                    or "current"
                Graph:Render()
            end
        end)
        t:SetScript("OnEnter", function()
            SetEdges(t.edges, 0.18)
            Graph.ShowChars(t)
        end)
        t:SetScript("OnLeave", function()
            SetEdges(t.edges, 0.06)
            tipText:Hide()
        end)
    else
        t:SetScript("OnClick", function()
            CludesUITitleLineDB.hidden[key] = not CludesUITitleLineDB.hidden[key] or nil
            Graph:Render()
        end)
        t:SetScript("OnEnter", function()
            SetEdges(t.edges, 0.18)
            Graph.ShowTile(t)
        end)
        t:SetScript("OnLeave", function()
            SetEdges(t.edges, 0.06)
            tipText:Hide()
        end)
    end
    return t
end

local function MakeTip()
    tipText = CreateFrame("Frame", nil, widget)
    tipText:SetFrameLevel(widget:GetFrameLevel() + 30)
    tipText:SetWidth(210)
    local backdrop = tipText:CreateTexture(nil, "BACKGROUND")
    backdrop:SetAllPoints()
    Color(backdrop, C.raised)
    Hairlines(tipText, 0.12)
    tipText.title = FS(tipText, "small", C.ink)
    tipText.title:SetPoint("TOPLEFT", 10, -9)
    tipText.tag = FS(tipText, "tiny", C.muted)
    tipText.tag:SetPoint("TOPRIGHT", -10, -10)
    tipText.rows = Pool(function()
        local r = CreateFrame("Frame", nil, tipText)
        r:SetSize(190, 16)
        r.swatch = r:CreateTexture(nil, "ARTWORK")
        r.swatch:SetSize(10, 2)
        r.swatch:SetPoint("LEFT", 0, 0)
        r.label = FS(r, "small", C.ink2)
        r.label:SetPoint("LEFT", 16, 0)
        r.value = FS(r, "small", C.ink)
        r.value:SetPoint("RIGHT", 0, 0)
        return r
    end)
    tipText.note = FS(tipText, "tiny", C.muted)
    tipText.note:SetWordWrap(true)
    tipText.note:SetJustifyH("LEFT")
    tipText:Hide()
end

local function Create()
    MakeFonts()
    widget = CreateFrame("Frame", "TitleLineFrame", UIParent)
    widget:SetSize(W, H)
    widget:SetFrameStrata("DIALOG")
    widget:SetScale(CludesUITitleLineDB.scale or DEFAULT_SCALE)
    widget:SetToplevel(true)
    widget:SetClampedToScreen(true)
    widget:SetMovable(true)
    widget:EnableMouse(true)
    widget:RegisterForDrag("LeftButton")
    widget:SetScript("OnDragStart", widget.StartMoving)
    widget:SetScript("OnDragStop", function(frame)
        frame:StopMovingOrSizing()
        local point, _, relPoint, posX, posY = frame:GetPoint()
        CludesUITitleLineDB.point = { point, relPoint, posX, posY }
    end)
    local pt = CludesUITitleLineDB.point
    if pt then
        widget:SetPoint(pt[1], UIParent, pt[2], pt[3], pt[4])
    else
        widget:SetPoint("CENTER")
    end
    widget:Hide()
    tinsert(UISpecialFrames, "TitleLineFrame")
    widget:SetScript("OnShow", function()
        C_MythicPlus.RequestMapInfo()
        Graph:Render()
    end)

    local backdrop = widget:CreateTexture(nil, "BACKGROUND")
    backdrop:SetAllPoints()
    Color(backdrop, C.surface, 0.98)
    Hairlines(widget, 0.10)

    -- Header.
    local icon = widget:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(MEDIA .. "Icon", "CLAMP", "CLAMP", "LINEAR")
    icon:SetSize(24, 24)
    icon:SetPoint("TOPLEFT", PAD, -11)
    widget.title = FS(widget, "title", C.ink)
    widget.title:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    widget.title:SetText("TitleLine")
    widget.region = FS(widget, "small", C.ink2)
    widget.region:SetPoint("LEFT", widget.title, "RIGHT", 12, -1)
    widget.season = FS(widget, "small", C.muted)
    widget.season:SetPoint("LEFT", widget.region, "RIGHT", 8, 0)

    local close = MakeClose(widget)
    close:SetPoint("TOPRIGHT", -10, -11)
    segmented = MakeSegmented(
        widget,
        { { "recent", "4 weeks" }, { "season", "Season" }, { "keys", "Keys" }, { "guild", "Guild" } }
    )
    segmented:SetPoint("RIGHT", close, "LEFT", -10, 0)

    local rule = widget:CreateTexture(nil, "BORDER")
    rule:SetColorTexture(1, 1, 1, 0.08)
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", 0, -HEADER_H)
    rule:SetPoint("TOPRIGHT", 0, -HEADER_H)

    tiles[1] = MakeTile(1, "you")
    for idx, tier in ipairs(mod.TIERS) do
        tiles[idx + 1] = MakeTile(idx + 1, tier.key)
    end

    -- The group row: one cell per party member, shown while you are grouped.
    set = CreateFrame("Frame", nil, widget)
    set:SetPoint("TOPLEFT", PAD, -GROUP_T)
    set:SetSize(W - 2 * PAD, GROUP_H)
    local labelText = FS(set, "tiny", C.muted)
    labelText:SetPoint("LEFT", 0, 0)
    labelText:SetText("Group")
    set.cells = {}
    local cw = (W - 2 * PAD - GROUP_LABEL_W + TILE_GAP) / 4
    for idx = 1, 4 do
        local cell = CreateFrame("Button", nil, set)
        cell:SetSize(cw - TILE_GAP, GROUP_H)
        cell:SetPoint("LEFT", GROUP_LABEL_W + (idx - 1) * cw, 0)
        local cbg = cell:CreateTexture(nil, "BACKGROUND")
        cbg:SetAllPoints()
        Color(cbg, C.raised)
        cell.edges = Hairlines(cell, 0.06)
        cell.name = FS(cell, "small", C.ink)
        cell.name:SetPoint("TOPLEFT", 10, -8)
        cell.value = FS(cell, "body", C.ink)
        cell.value:SetPoint("BOTTOMLEFT", 10, 7)
        cell.sub = FS(cell, "tiny", C.muted)
        cell.sub:SetPoint("BOTTOMRIGHT", -10, 8)
        cell:SetScript("OnEnter", function(self)
            SetEdges(self.edges, 0.18)
            Graph.ShowMember(self)
        end)
        cell:SetScript("OnLeave", function(self)
            SetEdges(self.edges, 0.06)
            tipText:Hide()
        end)
        set.cells[idx] = cell
    end

    plot = CreateFrame("Frame", nil, widget)
    plot:SetPoint("TOPLEFT", PL, -PT)
    plot:SetSize(PW, PH)

    strip = CreateFrame("Frame", nil, widget)
    strip:SetPoint("TOPLEFT", PL, -STRIP_T)
    strip:SetSize(PW, STRIP_H)
    local base = strip:CreateTexture(nil, "BORDER")
    Color(base, C.axis)
    base:SetHeight(1)
    base:SetPoint("BOTTOMLEFT")
    base:SetPoint("BOTTOMRIGHT")

    -- Where the Keys and Guild views draw (Views.lua).
    panelFrame = CreateFrame("Frame", nil, widget)
    panelFrame:SetSize(W - 2 * PAD, STRIP_T + STRIP_H - PT)
    panelFrame:Hide()

    message = FS(plot, "body", C.ink2)
    message:SetPoint("CENTER")

    -- One hover layer over the plot and the strip, so the crosshair spans both.
    hover = CreateFrame("Frame", nil, widget)
    hover:SetPoint("TOPLEFT", plot, "TOPLEFT")
    hover:SetPoint("BOTTOMRIGHT", strip, "BOTTOMRIGHT")
    hover:SetFrameLevel(plot:GetFrameLevel() + 5)
    hover:EnableMouse(true)
    cross = hover:CreateTexture(nil, "OVERLAY")
    Color(cross, C.ink, 0.35)
    cross:SetWidth(1)
    cross:Hide()

    local function lines(hostFrame, layer, sub, smooth)
        local p = Pool(function()
            local l = hostFrame:CreateLine(nil, layer, nil, sub)
            return smooth and Smooth(l, "Line") or l
        end)
        p.smooth = smooth
        return p
    end
    local function textures(hostFrame, layer, sub, file)
        return Pool(function()
            local tex = hostFrame:CreateTexture(nil, layer, nil, sub)
            return file and Smooth(tex, file) or tex
        end)
    end
    local function texts(hostFrame)
        return Pool(function()
            local fontStr = hostFrame:CreateFontString(nil, "OVERLAY")
            fontStr:SetWordWrap(false)
            return fontStr
        end)
    end
    pools.shade = textures(plot, "BACKGROUND", 0)
    pools.band = textures(plot, "BACKGROUND", 1)
    pools.grid = lines(plot, "BACKGROUND", 2)
    pools.party = lines(plot, "ARTWORK", 0, true)
    pools.series = lines(plot, "ARTWORK", 1, true)
    pools.you = lines(plot, "ARTWORK", 3, true)
    pools.labelBg = textures(plot, "ARTWORK", 7)
    pools.dotRings = textures(plot, "OVERLAY", 1, "Dot")
    pools.dots = textures(plot, "OVERLAY", 2, "Dot")
    pools.diamondRings = textures(plot, "OVERLAY", 3, "Diamond")
    pools.diamonds = textures(plot, "OVERLAY", 4, "Diamond")
    pools.labels = texts(plot)
    pools.axis = texts(widget)
    pools.bars = textures(strip, "ARTWORK", 0)
    pools.notes = texts(widget)
    pools.hoverRings = textures(hover, "OVERLAY", 3, "Dot")
    pools.hoverMarks = textures(hover, "OVERLAY", 4, "Dot")

    MakeTip()
    hover:SetScript("OnEnter", function() hover:SetScript("OnUpdate", Graph.OnHover) end)
    hover:SetScript("OnLeave", function()
        hover:SetScript("OnUpdate", nil)
        Graph:ClearHover()
    end)
end

-- Drawing -------------------------------------------------------------------------------

-- A fractional key level, as the level you would time.
local function LevelText(level) return ("+%d"):format(math.floor(level + 0.5)) end

local function DrawTiles(context, hidden)
    local sum = context.summary
    local you = tiles[1]
    -- The character shown: your best unless you chose the one you are playing.
    local subject, chars = context.subject, context.chars
    you.ctx = context
    you.swatch:SetColorTexture(mod.YOU_COLOR[1], mod.YOU_COLOR[2], mod.YOU_COLOR[3])
    you.label:SetText(subject.name or "Your rating")
    local cc = mod.ClassColor(subject.class)
    you.label:SetTextColor(cc[1], cc[2], cc[3])
    you.value:SetText(mod.Fmt(sum.you))
    you.unit:SetText("")
    you.eta:SetText("")
    you.canSwitch = #chars > 1 and not (subject.isCurrent and subject.isBest)
    if #chars > 1 then
        you.levels:SetText(subject.isBest and "best of your characters" or "not your best character")
    else
        you.levels:SetText("")
    end
    if sum.daysLeft then
        you.need:SetText(
            ("%d days of the season left%s"):format(
                math.ceil(sum.daysLeft),
                sum.endsEstimated and " (est.)" or ""
            )
        )
    else
        you.need:SetText("")
    end
    local days = math.floor(sum.paceDays + 0.5)
    if sum.paceDays >= 1 and sum.pace < 0.05 then
        you.sub:SetText(("No gain in the last %d days"):format(days))
    elseif sum.paceDays >= 1 then
        you.sub:SetText(("+%.1f a day, last %d days"):format(sum.pace, days))
    else
        you.sub:SetText("The season has just started")
    end

    for idx, tier in ipairs(sum.tiers) do
        local t = tiles[idx + 1]
        local color = tier.tier.color
        t.summary, t.ctx = tier, context
        t.swatch:SetColorTexture(color[1], color[2], color[3])
        t.label:SetText(tier.tier.label)
        -- The same level the Keys view draws: at the season end where known.
        local level = tier.levelEnd or tier.levelNow
        t.levels:SetText(
            level and level >= 2 and (LevelText(level) .. (tier.levelEnd and " by the end" or " now")) or ""
        )
        if tier.gap > 0 then
            t.value:SetText(mod.Fmt(tier.gap))
            t.unit:SetText("to go")
        else
            t.value:SetText("+" .. mod.Fmt(-tier.gap))
            t.unit:SetText("above")
        end
        if hidden[tier.tier.key] then
            t.sub:SetText("Hidden. Click to show.")
            t.need:SetText("")
            t.eta:SetText("")
            t:SetAlpha(0.45)
        else
            if tier.lineEnd then
                t.sub:SetText(
                    ("Line %s now, ~%s at the end"):format(mod.Fmt(tier.lineNow), mod.Fmt(tier.lineEnd))
                )
            else
                t.sub:SetText("Line " .. mod.Fmt(tier.lineNow))
            end
            if tier.need then
                t.need:SetText(tier.need > 0 and ("Need +%.1f a day"):format(tier.need) or "On course")
            else
                t.need:SetText("")
            end
            t.eta:SetText(tier.gap > 0 and mod.EtaText(tier, sum.pace, sum.endsAt) or "")
            t:SetAlpha(1)
        end
    end
end

local function DrawAxes(context, hidden)
    -- The projected stretch gets a faint wash, so actual and forecast never blur.
    local today = X(view.now)
    local shade = pools.shade:Get()
    shade:ClearAllPoints()
    shade:SetPoint("TOPLEFT", plot, "TOPLEFT", today, 0)
    shade:SetPoint("BOTTOMRIGHT", plot, "BOTTOMRIGHT", 0, 0)
    shade:SetColorTexture(1, 1, 1, 0.025)

    -- The "Projected" tag takes whichever end of that stretch no line crosses,
    -- top first. With both busy it is left out; the wash and dashes still say it.
    local tag
    if PW - today > 70 then
        local sum, ys = context.summary, {}
        for _, dx in ipairs({ 8, 68 }) do
            local t = view.now + dx / PW * (view.x1 - view.x0)
            ys[#ys + 1] = Y(sum.you + sum.pace * (t - view.now) / DAY)
            for _, tier in ipairs(sum.tiers) do
                if not hidden[tier.tier.key] then ys[#ys + 1] = Y(mod.LineValue(tier.pts, tier.fit, t)) end
            end
        end
        for _, band in ipairs({ { PH - 20, PH - 2 }, { 2, 20 } }) do
            local free = true
            for _, posY in ipairs(ys) do
                if posY > band[1] - 8 and posY < band[2] + 8 then free = false end
            end
            if free then
                tag = { today + 4, band[1], 64, band[2] - band[1] }
                Text(
                    pools.labels,
                    "tiny",
                    C.muted,
                    "BOTTOMLEFT",
                    plot,
                    "BOTTOMLEFT",
                    today + 8,
                    band[1] + 4,
                    "Projected"
                )
                break
            end
        end
    end

    for val = view.y0, view.y1 + 0.001, view.step do
        local posY = Y(val)
        Line(pools.grid, plot, 0, posY, PW, posY, val == view.y0 and C.axis or C.grid, 1, 1)
        Text(pools.axis, "tiny", C.muted, "RIGHT", plot, "BOTTOMLEFT", -8, posY, mod.Fmt(val))
    end

    local span = (view.x1 - view.x0) / DAY
    local stepDays = 28
    for _, d in ipairs({ 1, 2, 3, 7, 14 }) do
        if span / d <= 7 then
            stepDays = d
            break
        end
    end
    local d = date("*t", view.x0)
    local t = time({ year = d.year, month = d.month, day = d.day + 1, hour = 0 })
    while t < view.x1 do
        local posX = X(t)
        Line(pools.grid, plot, posX, 0, posX, -4, C.axis, 1, 1)
        if math.abs(posX - today) > 34 then
            Text(pools.axis, "tiny", C.muted, "TOP", plot, "BOTTOMLEFT", posX, -7, mod.DateText(t))
        end
        t = t + stepDays * DAY
    end

    Line(pools.grid, plot, today, 0, today, PH, C.muted, 0.6, 1)
    Text(pools.axis, "tiny", C.ink2, "TOP", plot, "BOTTOMLEFT", today, -7, "Today")

    -- The season's end, when it falls in view.
    local taken = { tag }
    local endsAt = context.summary.endsAt
    if endsAt and endsAt > view.x0 and endsAt <= view.x1 then
        local xe = X(endsAt)
        Line(pools.grid, plot, xe, 0, xe, PH, C.muted, 0.6, 1)
        local fontStr = Text(
            pools.labels,
            "tiny",
            C.muted,
            "TOPRIGHT",
            plot,
            "TOPLEFT",
            xe - 5,
            -6,
            context.summary.endsEstimated and "Season end (est.)" or "Season end"
        )
        local wid = fontStr:GetStringWidth() + 8
        taken[#taken + 1] = { xe - 5 - wid, PH - 20, wid + 6, 18 }
    end
    return taken
end

local function DrawSeries(context, hidden)
    local sum = context.summary
    for _, tier in ipairs(sum.tiers) do
        if not hidden[tier.tier.key] then
            local pts, color = tier.pts, tier.tier.color
            for idx = 2, #pts do
                Segment(pools.series, pts[idx - 1][1], pts[idx - 1][2], pts[idx][1], pts[idx][2], color)
            end
            Band(tier, color)
            Projection(pools.series, tier, color)
        end
    end

    -- Your rating moves in steps: flat until a key raises a best.
    local pts, c = context.history.points, mod.YOU_COLOR
    local pt, pv = view.x0, mod.ScoreAt(pts, view.x0)
    for _, p in ipairs(pts) do
        if p.t > view.x0 then
            Segment(pools.you, pt, pv, p.t, pv, c)
            if p.score ~= pv then
                local posX = X(p.t)
                Line(pools.you, plot, posX, Y(pv), posX, Y(p.score), c)
            end
            pt, pv = p.t, p.score
        end
    end
    Segment(
        pools.you,
        context.now,
        sum.you,
        view.x1,
        sum.you + sum.pace * (view.x1 - context.now) / DAY,
        c,
        true
    )
end

local function Overlaps(a, b)
    return a[1] < b[1] + b[3] and b[1] < a[1] + a[3] and a[2] < b[2] + b[4] and b[2] < a[2] + a[4]
end

local function DrawMarkers(context, hidden, taken)
    local sum, today = context.summary, X(context.now)
    -- Boxes (left, bottom, width, height) that a label must not cover.
    -- `taken` arrives holding the axis tags ("Projected", "Season end").

    local function mark(posX, posY, c, size, diamond)
        if diamond then
            Marker(pools.diamondRings, pools.diamonds, plot, posX, posY, c, size)
        else
            Marker(pools.dotRings, pools.dots, plot, posX, posY, c, size)
        end
        taken[#taken + 1] = { posX - 7, posY - 7, 14, 14 }
    end

    -- Where every series stands today.
    for _, tier in ipairs(sum.tiers) do
        if not hidden[tier.tier.key] then mark(today, Y(tier.lineNow), tier.tier.color, 8) end
    end
    mark(today, Y(sum.you), mod.YOU_COLOR, 9)

    -- Where your pace meets each line, labelled with the date. Each label tries
    -- above, below, right, then left of its marker, and takes the first spot
    -- clear of the markers and earlier labels.
    local crossings = {}
    for _, tier in ipairs(sum.tiers) do
        if tier.eta and tier.eta <= view.x1 and not hidden[tier.tier.key] then
            local posX, posY = X(tier.eta), Y(sum.you + sum.pace * tier.days)
            mark(posX, posY, mod.YOU_COLOR, 12, true)
            crossings[#crossings + 1] = { s = tier, x = posX, y = posY }
        end
    end
    for _, cr in ipairs(crossings) do
        local fontStr = Text(
            pools.labels,
            "tiny",
            C.ink,
            "BOTTOMLEFT",
            plot,
            "BOTTOMLEFT",
            0,
            0,
            cr.s.tier.short .. " by " .. mod.DateText(cr.s.eta)
        )
        local wid, hgt, posX, posY = fontStr:GetStringWidth() + 8, 15, cr.x, cr.y
        local box
        for _, b in ipairs({
            { posX - wid / 2, posY + 9, wid, hgt },
            { posX - wid / 2, posY - 9 - hgt, wid, hgt },
            { posX + 10, posY - hgt / 2, wid, hgt },
            { posX - 10 - wid, posY - hgt / 2, wid, hgt },
        }) do
            local inside = b[1] >= 0 and b[1] + wid <= PW and b[2] >= 0 and b[2] + hgt <= PH
            local clear = inside
            for _, t in ipairs(taken) do
                if clear and Overlaps(b, t) then clear = false end
            end
            if clear then
                box = b
                break
            end
        end
        box = box or { posX - wid / 2, posY + 9, wid, hgt }
        taken[#taken + 1] = box
        fontStr:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", box[1] + 4, box[2] + 2)
        local backdrop = pools.labelBg:Get()
        backdrop:ClearAllPoints()
        backdrop:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", box[1], box[2])
        backdrop:SetSize(wid, hgt)
        Color(backdrop, C.surface, 0.92)
    end
end

-- Series names at the right edge, where each line ends. When two would touch,
-- the later one is dropped rather than nudged off its line; the tiles carry it.
local function DrawEndLabels(context, hidden)
    local sum = context.summary
    local entries = { { "You", sum.you + sum.pace * (view.x1 - context.now) / DAY, C.ink } }
    for _, tier in ipairs(sum.tiers) do
        if not hidden[tier.tier.key] then
            entries[#entries + 1] = { tier.tier.short, mod.LineValue(tier.pts, tier.fit, view.x1), C.ink2 }
        end
    end
    local placed = {}
    for _, entry in ipairs(entries) do
        local posY = Y(entry[2])
        local clear = true
        for _, py in ipairs(placed) do
            if math.abs(py - posY) < 13 then clear = false end
        end
        if clear then
            placed[#placed + 1] = posY
            Text(pools.labels, "tiny", entry[3], "LEFT", plot, "BOTTOMLEFT", PW + 8, posY, entry[1])
        end
    end
end

local function DrawStrip(context)
    local maxGain = 0
    for _, p in ipairs(context.history.points) do
        if p.gain and p.t >= view.x0 then maxGain = math.max(maxGain, p.gain) end
    end
    Text(pools.axis, "tiny", C.muted, "BOTTOMRIGHT", strip, "BOTTOMLEFT", -8, 0, "Per key")
    if maxGain <= 0 then return end
    Text(pools.axis, "tiny", C.muted, "TOPRIGHT", strip, "TOPLEFT", -8, 0, "+" .. mod.Fmt(maxGain))
    local c = mod.YOU_COLOR
    for _, p in ipairs(context.history.points) do
        if p.gain and p.t >= view.x0 then
            local widget = pools.bars:Get()
            Color(widget, c, 0.9)
            widget:SetSize(3, math.max(2, p.gain / maxGain * (STRIP_H - 2)))
            widget:ClearAllPoints()
            widget:SetPoint("BOTTOMLEFT", strip, "BOTTOMLEFT", X(p.t) - 1.5, 1)
        end
    end
end

local function DrawNotes(context)
    local posY = -(FOOT_T + view.shift)
    local function note(s, c)
        local fontStr = Text(pools.notes, "tiny", c, "TOPLEFT", widget, "TOPLEFT", PAD, posY, s)
        fontStr:SetWordWrap(true)
        fontStr:SetWidth(W - 2 * PAD)
        fontStr:SetJustifyH("LEFT")
        posY = posY - fontStr:GetStringHeight() - 5
    end

    local key, last = context.regionKey, mod.Data.lastSeason
    local source = "Lines from Raider.IO, updated " .. mod.DateText(context.region.updatedAt) .. "."
    if last and last.p999 and last.p999.awarded[key] then
        source = source
            .. (" They are estimates: last season Blizzard awarded the 0.1%% title at %s, %s below Raider.IO's final line."):format(
                mod.Fmt(last.p999.awarded[key]),
                mod.Fmt(last.p999.raiderio[key] - last.p999.awarded[key])
            )
    end
    note(source, C.muted)
    for _, wid in ipairs(context.warnings) do
        note(mod.Hex(C.warn) .. "!|r  " .. wid, C.ink2)
    end
    widget:SetHeight(math.max(H + view.shift, -posY + PAD - 4))
end

-- How far a groupmate is from the next line up, in a few words.
local function NextLine(context, score)
    local sum = context.summary
    for idx = #sum.tiers, 1, -1 do
        local s = sum.tiers[idx]
        if score < s.lineNow then return mod.Fmt(s.lineNow - score) .. " to " .. s.tier.short end
    end
    return "above " .. sum.tiers[1].tier.short
end

local function DrawGroup(context)
    for idx, cell in ipairs(set.cells) do
        local m = context.party[idx]
        cell.member = m
        cell:SetShown(m ~= nil)
        if m then
            local color = mod.ClassColor(m.class)
            cell.name:SetText(m.name)
            cell.name:SetTextColor(color[1], color[2], color[3])
            if m.score > 0 then
                cell.value:SetText(mod.Fmt(m.score))
                cell.sub:SetText(NextLine(context, m.score))
            else
                cell.value:SetText("-")
                cell.sub:SetText("no rating yet")
            end
        end
    end
end

-- Groupmates on the graph: a marker on today's line at their rating, named in
-- their class colour, and the line remembered from earlier groups behind it.
local function DrawParty(context)
    local today, placed = X(context.now), { Y(context.summary.you) }
    -- Off-scale ratings ride the plot's edge rather than leave it.
    local function edge(val) return math.max(view.y0, math.min(view.y1, val)) end
    for _, m in ipairs(context.party) do
        if m.score > 0 then
            local pts = m.seen and m.seen.pts or {}
            local pt, pv
            for _, p in ipairs(pts) do
                if pt then
                    Segment(pools.party, pt, edge(pv), p[1], edge(pv), C.ink2, false, 0.5, 1.5)
                    local posX = X(p[1])
                    if p[1] > view.x0 and edge(p[2]) ~= edge(pv) then
                        Line(pools.party, plot, posX, Y(edge(pv)), posX, Y(edge(p[2])), C.ink2, 0.5, 1.5)
                    end
                end
                pt, pv = p[1], p[2]
            end
            if pt and pt < context.now then
                Segment(pools.party, pt, edge(pv), context.now, edge(pv), C.ink2, false, 0.5, 1.5)
            end

            local offScale = edge(m.score) ~= m.score
            local posY = Y(edge(m.score))
            Marker(pools.dotRings, pools.dots, plot, today, posY, C.ink2, 7)
            local clear = true
            for _, py in ipairs(placed) do
                if math.abs(py - posY) < 12 then clear = false end
            end
            if clear then
                placed[#placed + 1] = posY
                local name = offScale and (m.name .. "  " .. mod.Fmt(m.score)) or m.name
                local fontStr = Text(
                    pools.labels,
                    "tiny",
                    mod.ClassColor(m.class),
                    "RIGHT",
                    plot,
                    "BOTTOMLEFT",
                    today - 10,
                    posY,
                    name
                )
                local wid = fontStr:GetStringWidth() + 8
                local backdrop = pools.labelBg:Get()
                backdrop:ClearAllPoints()
                backdrop:SetPoint("RIGHT", plot, "BOTTOMLEFT", today - 6, posY)
                backdrop:SetSize(wid, 14)
                Color(backdrop, C.surface, 0.92)
            end
        end
    end
end

function Graph:Render()
    if not widget or not widget:IsShown() then return end
    for _, p in pairs(pools) do
        p:Reset()
    end
    self:ClearHover()
    segmented:Refresh()

    local context = mod.Context()
    widget.region:SetText(context.regionKey and context.regionKey:upper() or "")
    widget.season:SetText(mod.Data and mod.Data.season.name or "")

    if context.error then
        view = nil
        for _, tile in ipairs(tiles) do
            tile:Hide()
        end
        message:SetText(context.error)
        message:Show()
        set:Hide()
        panelFrame:Hide()
        plot:Show()
        widget:SetHeight(H)
        return
    end
    message:Hide()
    for _, tile in ipairs(tiles) do
        tile:Show()
    end

    -- In a party, the group row opens under the tiles and the rest moves down.
    local grouped = #context.party > 0
    local shift = grouped and GROUP_SHIFT or 0
    set:SetShown(grouped)
    plot:ClearAllPoints()
    plot:SetPoint("TOPLEFT", PL, -(PT + shift))
    strip:ClearAllPoints()
    strip:SetPoint("TOPLEFT", PL, -(STRIP_T + shift))
    panelFrame:ClearAllPoints()
    panelFrame:SetPoint("TOPLEFT", PAD, -(PT + shift))

    local hidden = CludesUITitleLineDB.hidden
    DrawTiles(context, hidden)
    if grouped then DrawGroup(context) end

    -- The Keys and Guild views are tables in the plot's place.
    local list = mod.Views and mod.Views[CludesUITitleLineDB.view]
    plot:SetShown(not list)
    strip:SetShown(not list)
    hover:SetShown(not list)
    panelFrame:SetShown(list ~= nil)
    if list then
        view = { now = context.now, ctx = context, shift = shift }
        list(panelFrame, context)
        DrawNotes(context)
        return
    end

    view = mod.Window(context, CludesUITitleLineDB.view, hidden)
    view.now, view.ctx, view.shift = context.now, context, shift

    local taken = DrawAxes(context, hidden)
    DrawSeries(context, hidden)
    DrawParty(context)
    DrawMarkers(context, hidden, taken)
    DrawEndLabels(context, hidden)
    DrawStrip(context)
    DrawNotes(context)
end

-- Hover readout --------------------------------------------------------------------------

function Graph:ClearHover()
    if not hover then return end
    if view then view.hoverX = nil end
    cross:Hide()
    tipText:Hide()
    pools.hoverRings:Reset()
    pools.hoverMarks:Reset()
end

-- The readout is as wide as its use needs: a date's values, or a groupmate's dungeons.
local function SizeTip(wid)
    tipText.w = wid
    tipText:SetWidth(wid)
end

local function TipRow(colorSwatch, labelText, value, posY, muted, labelColor)
    local r = tipText.rows:Get()
    r:SetWidth(tipText.w - 20)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", tipText, "TOPLEFT", 10, posY)
    if colorSwatch then
        r.swatch:SetColorTexture(colorSwatch[1], colorSwatch[2], colorSwatch[3])
        r.swatch:Show()
        r.label:SetPoint("LEFT", 16, 0)
    else
        r.swatch:Hide()
        r.label:SetPoint("LEFT", 0, 0)
    end
    r.label:SetText(labelText)
    local lc = labelColor or C.ink2
    r.label:SetTextColor(lc[1], lc[2], lc[3])
    r.value:SetText(value)
    local c = muted and C.muted or C.ink
    r.value:SetTextColor(c[1], c[2], c[3])
    return posY - 17
end

function Graph.OnHover()
    if not view then return end
    local curX = GetCursorPosition() / plot:GetEffectiveScale() - plot:GetLeft()
    curX = math.max(0, math.min(PW, curX))
    -- Snap to whole days from the window's start: readers aim at a date.
    local t = view.x0 + math.floor((curX / PW * (view.x1 - view.x0)) / DAY + 0.5) * DAY
    t = math.min(t, view.x1)
    local posX = X(t)
    if view.hoverX == posX then return end
    view.hoverX = posX

    local context, sum = view.ctx, view.ctx.summary
    local future = t > context.now
    cross:ClearAllPoints()
    cross:SetPoint("TOP", plot, "TOPLEFT", posX, 0)
    cross:SetPoint("BOTTOM", strip, "BOTTOMLEFT", posX, 0)
    cross:Show()

    pools.hoverRings:Reset()
    pools.hoverMarks:Reset()
    tipText.rows:Reset()
    SizeTip(210)
    tipText.note:Hide()
    tipText.title:SetText(mod.DateText(t, true))
    tipText.title:SetTextColor(C.ink[1], C.ink[2], C.ink[3])
    tipText.tag:SetText(future and "Projected" or "")

    local posY = -30
    local you = future and (sum.you + sum.pace * (t - context.now) / DAY)
        or mod.ScoreAt(context.history.points, t)
    Marker(pools.hoverRings, pools.hoverMarks, plot, posX, Y(you), mod.YOU_COLOR, 8)
    posY = TipRow(mod.YOU_COLOR, "You", mod.Fmt(you), posY)
    for _, tier in ipairs(sum.tiers) do
        if not CludesUITitleLineDB.hidden[tier.tier.key] then
            local lo, val, hi = mod.LineRange(tier.pts, tier.fit, t)
            Marker(pools.hoverRings, pools.hoverMarks, plot, posX, Y(val), tier.tier.color, 8)
            local textValue = mod.Fmt(val)
            if hi - lo >= 2 then textValue = mod.Fmt(lo) .. "-" .. mod.Fmt(hi) end
            posY = TipRow(tier.tier.color, tier.tier.label, textValue, posY)
        end
    end

    -- Groupmates, where TitleLine has seen them by that day.
    local gap = true
    for _, m in ipairs(context.party) do
        local val
        if m.score > 0 and math.abs(t - context.now) < DAY / 2 then
            val = m.score
        elseif not future and m.seen then
            for _, p in ipairs(m.seen.pts) do
                if p[1] <= t then val = p[2] end
            end
        end
        if val then
            if gap then
                posY = posY - 4
                gap = false
            end
            posY = TipRow(C.ink2, m.name, mod.Fmt(val), posY, false, mod.ClassColor(m.class))
        end
    end

    -- The keys that raised your rating that day.
    local first = true
    for _, p in ipairs(context.history.points) do
        if p.gain and math.abs(p.t - t) < DAY / 2 then
            if first then
                posY = posY - 4
                first = false
            end
            local name = C_ChallengeMode.GetMapUIInfo(p.map) or "?"
            posY = TipRow(nil, ("%s +%d"):format(name, p.level), "+" .. mod.Fmt(p.gain), posY, true)
        end
    end

    tipText:SetHeight(-posY + 6)
    tipText:ClearAllPoints()
    if posX > PW / 2 then
        tipText:SetPoint("TOPRIGHT", plot, "TOPLEFT", posX - 14, -6)
    else
        tipText:SetPoint("TOPLEFT", plot, "TOPLEFT", posX + 14, -6)
    end
    tipText:Show()
end

-- A groupmate's best key and score in every dungeon, under their cell.
function Graph.ShowMember(cell)
    local m = cell.member
    if not m then return end
    tipText.rows:Reset()
    local color = mod.ClassColor(m.class)
    SizeTip(260)
    tipText.note:Hide()
    tipText.title:SetText(m.name)
    tipText.title:SetTextColor(color[1], color[2], color[3])
    tipText.tag:SetText(
        m.seen and #m.seen.pts > 1 and ("seen since " .. mod.DateText(m.seen.pts[1][1])) or ""
    )

    local runs = {}
    for _, r in ipairs(m.runs) do
        if r.mapScore and r.mapScore > 0 then runs[#runs + 1] = r end
    end
    table.sort(runs, function(lhs, rhs) return lhs.mapScore > rhs.mapScore end)
    local posY = -30
    for _, r in ipairs(runs) do
        local name = C_ChallengeMode.GetMapUIInfo(r.challengeModeID) or "?"
        local labelText = ("%s +%d"):format(name, r.bestRunLevel)
            .. (r.finishedSuccess and "" or "  (over time)")
        posY = TipRow(nil, labelText, mod.Fmt(r.mapScore), posY, not r.finishedSuccess)
    end
    if #runs == 0 then posY = TipRow(nil, "No rated runs shared yet", "", posY, true) end

    tipText:SetHeight(-posY + 6)
    tipText:ClearAllPoints()
    tipText:SetPoint("TOPLEFT", cell, "BOTTOMLEFT", 0, -6)
    tipText:Show()
end

-- A title tile's detail: the line now and at the season end, what that is in
-- key levels, and the daily gain it takes against yours.
-- Your characters this season, best first, with how far each is from the
-- next line; says what a click on the tile does.
function Graph.ShowChars(tbl)
    local context = tbl.ctx
    if not context or #context.chars == 0 then return end
    tipText.rows:Reset()
    SizeTip(250)
    tipText.title:SetText("Your characters")
    tipText.title:SetTextColor(C.ink[1], C.ink[2], C.ink[3])
    tipText.tag:SetText("titles are account-wide")
    local posY = -30
    for _, c in ipairs(context.chars) do
        posY = TipRow(nil, c.name, mod.Fmt(c.score), posY, false, mod.ClassColor(c.class))
    end
    tipText.note:SetWidth(tipText.w - 20)
    tipText.note:ClearAllPoints()
    tipText.note:SetPoint("TOPLEFT", tipText, "TOPLEFT", 10, posY - 4)
    local note = "A character appears here once you have logged in on it this season."
    if tbl.canSwitch then
        note = (
            context.subject.isCurrent and "Click to show your best character."
            or "Click to show the character you are playing."
        )
            .. " "
            .. note
    end
    tipText.note:SetText(note)
    tipText.note:Show()
    posY = posY - 4 - tipText.note:GetStringHeight()
    tipText:SetHeight(-posY + 10)
    tipText:ClearAllPoints()
    tipText:SetPoint("TOPLEFT", tbl, "BOTTOMLEFT", 0, -6)
    tipText:Show()
end

function Graph.ShowTile(tbl)
    local s, context = tbl.summary, tbl.ctx
    if not s or CludesUITitleLineDB.hidden[s.tier.key] then return end
    local sum = context.summary
    tipText.rows:Reset()
    SizeTip(250)
    tipText.title:SetText(s.tier.label)
    tipText.title:SetTextColor(C.ink[1], C.ink[2], C.ink[3])
    tipText.tag:SetText("")

    local posY = -30
    posY = TipRow(nil, "Line today", mod.Fmt(s.lineNow), posY)
    if s.lineEnd then
        posY = TipRow(
            nil,
            sum.endsEstimated and "At the season end (est.)" or "At the season end",
            "~" .. mod.Fmt(s.lineEnd),
            posY
        )
        posY = TipRow(
            nil,
            "Likely range at the end",
            mod.Fmt(s.lineEndLow) .. "-" .. mod.Fmt(s.lineEndHigh),
            posY
        )
    end
    if s.levelNow then posY = TipRow(nil, "Timed in every dungeon, today", LevelText(s.levelNow), posY) end
    if s.levelEnd then
        posY = TipRow(nil, "Timed in every dungeon, at the end", LevelText(s.levelEnd), posY)
    end
    if s.need then
        posY = TipRow(nil, "Daily gain it takes", ("+%.1f"):format(s.need), posY)
        posY = TipRow(nil, "Your daily gain", ("+%.1f"):format(sum.pace), posY)
    end

    tipText.note:SetWidth(tipText.w - 20)
    tipText.note:ClearAllPoints()
    tipText.note:SetPoint("TOPLEFT", tipText, "TOPLEFT", 10, posY - 4)
    tipText.note:SetText(mod.SCORING_NOTE)
    tipText.note:Show()
    posY = posY - 4 - tipText.note:GetStringHeight()

    tipText:SetHeight(-posY + 10)
    tipText:ClearAllPoints()
    tipText:SetPoint("TOPLEFT", tbl, "BOTTOMLEFT", 0, -6)
    tipText:Show()
end

-- The drawing kit Views.lua shares, so its tables match the graph.
mod.UI = {
    Pool = Pool,
    Text = Text,
    Color = Color,
    Hairlines = Hairlines,
    LevelText = LevelText,
    MakeClose = MakeClose,
    PANEL_W = W - 2 * PAD,
    PANEL_H = STRIP_T + STRIP_H - PT,
}

-- Public ------------------------------------------------------------------------------------

function Graph:Toggle()
    if not widget then Create() end
    widget:SetShown(not widget:IsShown())
end

function Graph:ApplyScale()
    if widget then widget:SetScale(CludesUITitleLineDB.scale or DEFAULT_SCALE) end
end

function Graph:Refresh()
    if widget and widget:IsShown() then self:Render() end
end
