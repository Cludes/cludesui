-- The graph window: your rating against the lines over the season, both
-- extended at their recent pace, with the rating each key added underneath.
--
-- Layout, top to bottom: header, stat tiles (which double as the legend and
-- toggle the lines), the plot, the per-key strip, notes.

local _, ns = ...
if ns.standalone then return end
local DAY = ns.DAY
local C = ns.COLORS

local Graph = {}
ns.Graph = Graph

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

local frame, plot, strip, hover, cross, tip, segmented, message, group, panel
local tiles = {}
local pools = {}
local fonts
local view -- the last render's scales and context, read by the hover

-- Building blocks ------------------------------------------------------------------

local function Color(region, c, a)
	region:SetColorTexture(c[1], c[2], c[3], a or c[4] or 1)
end

-- The game's own face, so every locale renders, at sizes of our choosing.
local function MakeFonts()
	fonts = {}
	local path, _, flags = GameFontHighlight:GetFont()
	for name, size in pairs({ title = 15, value = 20, body = 12, small = 11, tiny = 10 }) do
		local f = CreateFont("TitleLineFont_" .. name)
		f:SetFont(path, size, flags or "")
		fonts[name] = f
	end
end

local function Paint(fs, font, c)
	fs:SetFontObject(fonts[font])
	fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
end

local function FS(parent, font, c, layer)
	local fs = parent:CreateFontString(nil, layer or "OVERLAY")
	Paint(fs, font, c)
	fs:SetWordWrap(false)
	return fs
end

local function Hairlines(f, alpha)
	local edges = {}
	for _, e in ipairs({
		{ "TOPLEFT", "TOPRIGHT", nil, 1 },
		{ "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 },
		{ "TOPLEFT", "BOTTOMLEFT", 1, nil },
		{ "TOPRIGHT", "BOTTOMRIGHT", 1, nil },
	}) do
		local t = f:CreateTexture(nil, "BORDER")
		t:SetColorTexture(1, 1, 1, alpha)
		t:SetPoint(e[1])
		t:SetPoint(e[2])
		if e[3] then
			t:SetWidth(e[3])
		else
			t:SetHeight(e[4])
		end
		edges[#edges + 1] = t
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
		for i = 1, #self.items do
			self.items[i]:Hide()
		end
		self.used = 0
	end
	return p
end

-- The client draws lines and solid fills with hard, aliased edges, so anything
-- that is not axis-aligned uses a white texture with a soft alpha edge, tinted
-- per use. Snapping is off so a fractional position stays smooth.
local function Smooth(region, file)
	region:SetTexture(MEDIA .. file, "CLAMP", "CLAMP", "LINEAR")
	region:SetSnapToPixelGrid(false)
	region:SetTexelSnappingBias(0)
	return region
end

-- `th` is the stroke as it should look. A smooth line is drawn twice as thick,
-- because half of its texture is the fade that does the anti-aliasing.
local function Line(pool, rel, x1, y1, x2, y2, c, a, th)
	local l = pool:Get()
	if pool.smooth then
		l:SetThickness((th or 2) * 2)
		l:SetVertexColor(c[1], c[2], c[3], a or 1)
	else
		l:SetThickness(th or 1)
		Color(l, c, a)
	end
	l:SetStartPoint("BOTTOMLEFT", rel, x1, y1)
	l:SetEndPoint("BOTTOMLEFT", rel, x2, y2)
	return l
end

-- A dot or diamond `size` across, on a ring in the surface colour so it reads
-- over any line. The shape fills SHAPE_FILL of its texture.
local function Marker(rings, marks, rel, x, y, c, size)
	for _, m in ipairs({ { rings, size + 4, C.surface }, { marks, size, c } }) do
		local t = m[1]:Get()
		local s = m[2] / SHAPE_FILL
		t:SetSize(s, s)
		t:ClearAllPoints()
		t:SetPoint("CENTER", rel, "BOTTOMLEFT", x, y)
		t:SetVertexColor(m[3][1], m[3][2], m[3][3], 1)
	end
end

local function Text(pool, font, c, point, rel, relPoint, x, y, s)
	local fs = pool:Get()
	Paint(fs, font, c)
	fs:ClearAllPoints()
	fs:SetPoint(point, rel, relPoint, x, y)
	fs:SetText(s)
	return fs
end

-- Scales ------------------------------------------------------------------------------

local function X(t)
	return (t - view.x0) / (view.x1 - view.x0) * PW
end

local function Y(v)
	return (v - view.y0) / (view.y1 - view.y0) * PH
end

-- Dashes along a path of plot points, the pattern running on across joins so
-- a curve dashes as evenly as a straight line.
local DASH_ON, DASH_OFF = 5, 4
local function DashedPath(pool, path, c)
	local phase = 0
	for i = 2, #path do
		local x1, y1, x2, y2 = path[i - 1][1], path[i - 1][2], path[i][1], path[i][2]
		local dx, dy = x2 - x1, y2 - y1
		local len = math.sqrt(dx * dx + dy * dy)
		local pos = 0
		while pos < len do
			local cycle = phase % (DASH_ON + DASH_OFF)
			local on = cycle < DASH_ON
			local e = math.min(len, pos + (on and (DASH_ON - cycle) or (DASH_ON + DASH_OFF - cycle)))
			if on then
				Line(pool, plot, x1 + dx * pos / len, y1 + dy * pos / len, x1 + dx * e / len, y1 + dy * e / len, c)
			end
			phase = phase + (e - pos)
			pos = e
		end
	end
end

-- A segment in data space, clipped to the visible time window.
local function Segment(pool, ta, va, tb, vb, c, dashed, a, th)
	if tb < view.x0 or ta > view.x1 or tb <= ta then
		return
	end
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
	for x = xa, PW - 1, 3 do
		local t = view.x0 + (x + 1.5) / PW * (view.x1 - view.x0)
		local lo, _, hi = ns.LineRange(s.pts, s.fit, t)
		local y0, y1 = math.max(0, Y(lo)), math.min(PH, Y(hi))
		if y1 > y0 then
			local r = pools.band:Get()
			r:ClearAllPoints()
			r:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", x, y0)
			r:SetSize(math.min(3, PW - x), y1 - y0)
			Color(r, c, 0.10)
		end
	end
end

local function Projection(pool, s, c)
	local last = s.pts[#s.pts]
	local ta = math.max(last[1], view.x0)
	if ta >= view.x1 then
		return
	end
	local n = math.max(2, math.ceil((X(view.x1) - X(ta)) / 6))
	local path = {}
	for i = 0, n do
		local t = ta + (view.x1 - ta) * i / n
		path[#path + 1] = { X(t), Y(ns.LineValue(s.pts, s.fit, t)) }
	end
	DashedPath(pool, path, c)
end

function ns.NiceStep(range, target)
	local raw = range / target
	local mag = 10 ^ math.floor(math.log(raw) / math.log(10))
	local norm = raw / mag
	local step = norm < 1.5 and 1 or norm < 3 and 2 or norm < 7 and 5 or 10
	return step * mag
end

-- The time window and value range for this render.
function ns.Window(ctx, mode, hidden)
	local now, region, sum = ctx.now, ctx.region, ctx.summary
	local x0 = region.startsAt
	if mode ~= "season" then
		x0 = math.max(x0, now - RECENT_DAYS * DAY)
	end

	-- Reach far enough ahead to show the crossings, within reason.
	local ahead = MIN_AHEAD
	for _, s in ipairs(sum.tiers) do
		if s.days and not hidden[s.tier.key] then
			ahead = math.max(ahead, math.min(s.days * 1.15 + 1, MAX_AHEAD))
		end
	end
	local x1 = now + ahead * DAY
	-- The season view runs to the season's end.
	if mode == "season" and sum.endsAt and sum.endsAt > x1 then
		x1 = sum.endsAt
	end

	local lo, hi = math.huge, -math.huge
	local function take(v)
		if v then
			lo, hi = math.min(lo, v), math.max(hi, v)
		end
	end
	take(ns.ScoreAt(ctx.history.points, x0))
	for _, p in ipairs(ctx.history.points) do
		if p.t >= x0 then
			take(p.score)
		end
	end
	take(sum.you + sum.pace * (x1 - now) / DAY)
	for _, s in ipairs(sum.tiers) do
		if not hidden[s.tier.key] then
			take(ns.LineValue(s.pts, s.fit, x0))
			for _, p in ipairs(s.pts) do
				if p[1] >= x0 then
					take(p[2])
				end
			end
			local low, _, high = ns.LineRange(s.pts, s.fit, x1)
			take(low)
			take(high)
		end
	end
	-- Groupmates may widen the range only a little: one far below would squash
	-- your line and the title lines into a sliver. Past that they sit on the
	-- edge, labelled with their rating (see DrawParty).
	local reach = math.max(hi - lo, 100) * PARTY_REACH
	local floor, ceil = lo - reach, hi + reach
	local function near(v)
		if v >= floor and v <= ceil then
			take(v)
		end
	end
	for _, m in ipairs(ctx.party or {}) do
		if m.score > 0 then
			near(m.score)
			for _, p in ipairs(m.seen and m.seen.pts or {}) do
				if p[1] >= x0 then
					near(p[2])
				end
			end
		end
	end
	if hi - lo < 50 then
		lo, hi = lo - 25, hi + 25
	end
	local step = ns.NiceStep(hi - lo, 5)
	return { x0 = x0, x1 = x1, y0 = math.floor(lo / step) * step, y1 = math.ceil(hi / step) * step, step = step }
end

-- The window ----------------------------------------------------------------------------

local function MakeSegmented(parent, options)
	local box = CreateFrame("Frame", nil, parent)
	local bw = 72
	box:SetSize(#options * bw + 2, 24)
	Hairlines(box, 0.10)
	box.buttons = {}
	function box:Refresh()
		for _, b in ipairs(self.buttons) do
			local on = CludesUITitleLineDB.view == b.value
			Color(b.bg, C.raised, on and 1 or 0)
			local c = on and C.ink or (b:IsMouseOver() and C.ink2 or C.muted)
			b.text:SetTextColor(c[1], c[2], c[3])
		end
	end
	for i, o in ipairs(options) do
		local b = CreateFrame("Button", nil, box)
		b:SetSize(bw, 22)
		b:SetPoint("LEFT", 1 + (i - 1) * bw, 0)
		b.bg = b:CreateTexture(nil, "BACKGROUND")
		b.bg:SetAllPoints()
		b.text = FS(b, "small", C.muted)
		b.text:SetPoint("CENTER")
		b.text:SetText(o[2])
		b.value = o[1]
		b:SetScript("OnClick", function()
			CludesUITitleLineDB.view = o[1]
			if o[1] == "guild" and IsInGuild() then
				C_GuildInfo.GuildRoster()
			end
			Graph:Render()
		end)
		b:SetScript("OnEnter", function()
			box:Refresh()
		end)
		b:SetScript("OnLeave", function()
			box:Refresh()
		end)
		box.buttons[i] = b
	end
	return box
end

local function MakeClose(parent)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(24, 24)
	b.lines = {}
	for i, d in ipairs({ { -5, -5, 5, 5 }, { -5, 5, 5, -5 } }) do
		local l = Smooth(b:CreateLine(nil, "OVERLAY"), "Line")
		l:SetThickness(3)
		l:SetStartPoint("CENTER", b, d[1], d[2])
		l:SetEndPoint("CENTER", b, d[3], d[4])
		b.lines[i] = l
	end
	local function tint(c)
		for _, l in ipairs(b.lines) do
			l:SetVertexColor(c[1], c[2], c[3], 1)
		end
	end
	tint(C.muted)
	b:SetScript("OnEnter", function()
		tint(C.ink)
	end)
	b:SetScript("OnLeave", function()
		tint(C.muted)
	end)
	b:SetScript("OnClick", function()
		parent:Hide()
	end)
	return b
end

local function MakeTile(i, key)
	local count = #ns.TIERS + 1
	local w = (W - 2 * PAD - (count - 1) * TILE_GAP) / count
	local t = CreateFrame("Button", nil, frame)
	t:SetSize(w, TILE_H)
	t:SetPoint("TOPLEFT", PAD + (i - 1) * (w + TILE_GAP), -TILE_T)
	local bg = t:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	Color(bg, C.raised)
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
				CludesUITitleLineDB.showChar = (CludesUITitleLineDB.showChar == "current") and "best" or "current"
				Graph:Render()
			end
		end)
		t:SetScript("OnEnter", function()
			SetEdges(t.edges, 0.18)
			Graph.ShowChars(t)
		end)
		t:SetScript("OnLeave", function()
			SetEdges(t.edges, 0.06)
			tip:Hide()
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
			tip:Hide()
		end)
	end
	return t
end

local function MakeTip()
	tip = CreateFrame("Frame", nil, frame)
	tip:SetFrameLevel(frame:GetFrameLevel() + 30)
	tip:SetWidth(210)
	local bg = tip:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	Color(bg, C.raised)
	Hairlines(tip, 0.12)
	tip.title = FS(tip, "small", C.ink)
	tip.title:SetPoint("TOPLEFT", 10, -9)
	tip.tag = FS(tip, "tiny", C.muted)
	tip.tag:SetPoint("TOPRIGHT", -10, -10)
	tip.rows = Pool(function()
		local r = CreateFrame("Frame", nil, tip)
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
	tip.note = FS(tip, "tiny", C.muted)
	tip.note:SetWordWrap(true)
	tip.note:SetJustifyH("LEFT")
	tip:Hide()
end

local function Create()
	MakeFonts()
	frame = CreateFrame("Frame", "TitleLineFrame", UIParent)
	frame:SetSize(W, H)
	frame:SetFrameStrata("DIALOG")
	frame:SetScale(CludesUITitleLineDB.scale or DEFAULT_SCALE)
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function(f)
		f:StopMovingOrSizing()
		local p, _, rp, x, y = f:GetPoint()
		CludesUITitleLineDB.point = { p, rp, x, y }
	end)
	local pt = CludesUITitleLineDB.point
	if pt then
		frame:SetPoint(pt[1], UIParent, pt[2], pt[3], pt[4])
	else
		frame:SetPoint("CENTER")
	end
	frame:Hide()
	tinsert(UISpecialFrames, "TitleLineFrame")
	frame:SetScript("OnShow", function()
		C_MythicPlus.RequestMapInfo()
		Graph:Render()
	end)

	local bg = frame:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	Color(bg, C.surface, 0.98)
	Hairlines(frame, 0.10)

	-- Header.
	local icon = frame:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(MEDIA .. "Icon", "CLAMP", "CLAMP", "LINEAR")
	icon:SetSize(24, 24)
	icon:SetPoint("TOPLEFT", PAD, -11)
	frame.title = FS(frame, "title", C.ink)
	frame.title:SetPoint("LEFT", icon, "RIGHT", 8, 0)
	frame.title:SetText("TitleLine")
	frame.region = FS(frame, "small", C.ink2)
	frame.region:SetPoint("LEFT", frame.title, "RIGHT", 12, -1)
	frame.season = FS(frame, "small", C.muted)
	frame.season:SetPoint("LEFT", frame.region, "RIGHT", 8, 0)

	local close = MakeClose(frame)
	close:SetPoint("TOPRIGHT", -10, -11)
	segmented = MakeSegmented(frame, { { "recent", "4 weeks" }, { "season", "Season" }, { "keys", "Keys" }, { "guild", "Guild" } })
	segmented:SetPoint("RIGHT", close, "LEFT", -10, 0)

	local rule = frame:CreateTexture(nil, "BORDER")
	rule:SetColorTexture(1, 1, 1, 0.08)
	rule:SetHeight(1)
	rule:SetPoint("TOPLEFT", 0, -HEADER_H)
	rule:SetPoint("TOPRIGHT", 0, -HEADER_H)

	tiles[1] = MakeTile(1, "you")
	for i, tier in ipairs(ns.TIERS) do
		tiles[i + 1] = MakeTile(i + 1, tier.key)
	end

	-- The group row: one cell per party member, shown while you are grouped.
	group = CreateFrame("Frame", nil, frame)
	group:SetPoint("TOPLEFT", PAD, -GROUP_T)
	group:SetSize(W - 2 * PAD, GROUP_H)
	local label = FS(group, "tiny", C.muted)
	label:SetPoint("LEFT", 0, 0)
	label:SetText("Group")
	group.cells = {}
	local cw = (W - 2 * PAD - GROUP_LABEL_W + TILE_GAP) / 4
	for i = 1, 4 do
		local cell = CreateFrame("Button", nil, group)
		cell:SetSize(cw - TILE_GAP, GROUP_H)
		cell:SetPoint("LEFT", GROUP_LABEL_W + (i - 1) * cw, 0)
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
			tip:Hide()
		end)
		group.cells[i] = cell
	end

	plot = CreateFrame("Frame", nil, frame)
	plot:SetPoint("TOPLEFT", PL, -PT)
	plot:SetSize(PW, PH)

	strip = CreateFrame("Frame", nil, frame)
	strip:SetPoint("TOPLEFT", PL, -STRIP_T)
	strip:SetSize(PW, STRIP_H)
	local base = strip:CreateTexture(nil, "BORDER")
	Color(base, C.axis)
	base:SetHeight(1)
	base:SetPoint("BOTTOMLEFT")
	base:SetPoint("BOTTOMRIGHT")

	-- Where the Keys and Guild views draw (Views.lua).
	panel = CreateFrame("Frame", nil, frame)
	panel:SetSize(W - 2 * PAD, STRIP_T + STRIP_H - PT)
	panel:Hide()

	message = FS(plot, "body", C.ink2)
	message:SetPoint("CENTER")

	-- One hover layer over the plot and the strip, so the crosshair spans both.
	hover = CreateFrame("Frame", nil, frame)
	hover:SetPoint("TOPLEFT", plot, "TOPLEFT")
	hover:SetPoint("BOTTOMRIGHT", strip, "BOTTOMRIGHT")
	hover:SetFrameLevel(plot:GetFrameLevel() + 5)
	hover:EnableMouse(true)
	cross = hover:CreateTexture(nil, "OVERLAY")
	Color(cross, C.ink, 0.35)
	cross:SetWidth(1)
	cross:Hide()

	local function lines(parent, layer, sub, smooth)
		local p = Pool(function()
			local l = parent:CreateLine(nil, layer, nil, sub)
			return smooth and Smooth(l, "Line") or l
		end)
		p.smooth = smooth
		return p
	end
	local function textures(parent, layer, sub, file)
		return Pool(function()
			local t = parent:CreateTexture(nil, layer, nil, sub)
			return file and Smooth(t, file) or t
		end)
	end
	local function texts(parent)
		return Pool(function()
			local fs = parent:CreateFontString(nil, "OVERLAY")
			fs:SetWordWrap(false)
			return fs
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
	pools.axis = texts(frame)
	pools.bars = textures(strip, "ARTWORK", 0)
	pools.notes = texts(frame)
	pools.hoverRings = textures(hover, "OVERLAY", 3, "Dot")
	pools.hoverMarks = textures(hover, "OVERLAY", 4, "Dot")

	MakeTip()
	hover:SetScript("OnEnter", function()
		hover:SetScript("OnUpdate", Graph.OnHover)
	end)
	hover:SetScript("OnLeave", function()
		hover:SetScript("OnUpdate", nil)
		Graph:ClearHover()
	end)
end

-- Drawing -------------------------------------------------------------------------------

-- A fractional key level, as the level you would time.
local function LevelText(level)
	return ("+%d"):format(math.floor(level + 0.5))
end

local function DrawTiles(ctx, hidden)
	local sum = ctx.summary
	local you = tiles[1]
	-- The character shown: your best unless you chose the one you are playing.
	local subject, chars = ctx.subject, ctx.chars
	you.ctx = ctx
	you.swatch:SetColorTexture(ns.YOU_COLOR[1], ns.YOU_COLOR[2], ns.YOU_COLOR[3])
	you.label:SetText(subject.name or "Your rating")
	local cc = ns.ClassColor(subject.class)
	you.label:SetTextColor(cc[1], cc[2], cc[3])
	you.value:SetText(ns.Fmt(sum.you))
	you.unit:SetText("")
	you.eta:SetText("")
	you.canSwitch = #chars > 1 and not (subject.isCurrent and subject.isBest)
	if #chars > 1 then
		you.levels:SetText(subject.isBest and "best of your characters" or "not your best character")
	else
		you.levels:SetText("")
	end
	if sum.daysLeft then
		you.need:SetText(("%d days of the season left%s"):format(math.ceil(sum.daysLeft), sum.endsEstimated and " (est.)" or ""))
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

	for i, s in ipairs(sum.tiers) do
		local t = tiles[i + 1]
		local c = s.tier.color
		t.summary, t.ctx = s, ctx
		t.swatch:SetColorTexture(c[1], c[2], c[3])
		t.label:SetText(s.tier.label)
		-- The same level the Keys view draws: at the season end where known.
		local level = s.levelEnd or s.levelNow
		t.levels:SetText(level and level >= 2 and (LevelText(level) .. (s.levelEnd and " by the end" or " now")) or "")
		if s.gap > 0 then
			t.value:SetText(ns.Fmt(s.gap))
			t.unit:SetText("to go")
		else
			t.value:SetText("+" .. ns.Fmt(-s.gap))
			t.unit:SetText("above")
		end
		if hidden[s.tier.key] then
			t.sub:SetText("Hidden. Click to show.")
			t.need:SetText("")
			t.eta:SetText("")
			t:SetAlpha(0.45)
		else
			if s.lineEnd then
				t.sub:SetText(("Line %s now, ~%s at the end"):format(ns.Fmt(s.lineNow), ns.Fmt(s.lineEnd)))
			else
				t.sub:SetText("Line " .. ns.Fmt(s.lineNow))
			end
			if s.need then
				t.need:SetText(s.need > 0 and ("Need +%.1f a day"):format(s.need) or "On course")
			else
				t.need:SetText("")
			end
			t.eta:SetText(s.gap > 0 and ns.EtaText(s, sum.pace, sum.endsAt) or "")
			t:SetAlpha(1)
		end
	end
end

local function DrawAxes(ctx, hidden)
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
		local sum, ys = ctx.summary, {}
		for _, dx in ipairs({ 8, 68 }) do
			local t = view.now + dx / PW * (view.x1 - view.x0)
			ys[#ys + 1] = Y(sum.you + sum.pace * (t - view.now) / DAY)
			for _, s in ipairs(sum.tiers) do
				if not hidden[s.tier.key] then
					ys[#ys + 1] = Y(ns.LineValue(s.pts, s.fit, t))
				end
			end
		end
		for _, band in ipairs({ { PH - 20, PH - 2 }, { 2, 20 } }) do
			local free = true
			for _, y in ipairs(ys) do
				if y > band[1] - 8 and y < band[2] + 8 then
					free = false
				end
			end
			if free then
				tag = { today + 4, band[1], 64, band[2] - band[1] }
				Text(pools.labels, "tiny", C.muted, "BOTTOMLEFT", plot, "BOTTOMLEFT", today + 8, band[1] + 4, "Projected")
				break
			end
		end
	end

	for v = view.y0, view.y1 + 0.001, view.step do
		local y = Y(v)
		Line(pools.grid, plot, 0, y, PW, y, v == view.y0 and C.axis or C.grid, 1, 1)
		Text(pools.axis, "tiny", C.muted, "RIGHT", plot, "BOTTOMLEFT", -8, y, ns.Fmt(v))
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
		local x = X(t)
		Line(pools.grid, plot, x, 0, x, -4, C.axis, 1, 1)
		if math.abs(x - today) > 34 then
			Text(pools.axis, "tiny", C.muted, "TOP", plot, "BOTTOMLEFT", x, -7, ns.DateText(t))
		end
		t = t + stepDays * DAY
	end

	Line(pools.grid, plot, today, 0, today, PH, C.muted, 0.6, 1)
	Text(pools.axis, "tiny", C.ink2, "TOP", plot, "BOTTOMLEFT", today, -7, "Today")

	-- The season's end, when it falls in view.
	local taken = { tag }
	local endsAt = ctx.summary.endsAt
	if endsAt and endsAt > view.x0 and endsAt <= view.x1 then
		local xe = X(endsAt)
		Line(pools.grid, plot, xe, 0, xe, PH, C.muted, 0.6, 1)
		local fs = Text(pools.labels, "tiny", C.muted, "TOPRIGHT", plot, "TOPLEFT", xe - 5, -6,
			ctx.summary.endsEstimated and "Season end (est.)" or "Season end")
		local w = fs:GetStringWidth() + 8
		taken[#taken + 1] = { xe - 5 - w, PH - 20, w + 6, 18 }
	end
	return taken
end

local function DrawSeries(ctx, hidden)
	local sum = ctx.summary
	for _, s in ipairs(sum.tiers) do
		if not hidden[s.tier.key] then
			local pts, c = s.pts, s.tier.color
			for i = 2, #pts do
				Segment(pools.series, pts[i - 1][1], pts[i - 1][2], pts[i][1], pts[i][2], c)
			end
			Band(s, c)
			Projection(pools.series, s, c)
		end
	end

	-- Your rating moves in steps: flat until a key raises a best.
	local pts, c = ctx.history.points, ns.YOU_COLOR
	local pt, pv = view.x0, ns.ScoreAt(pts, view.x0)
	for _, p in ipairs(pts) do
		if p.t > view.x0 then
			Segment(pools.you, pt, pv, p.t, pv, c)
			if p.score ~= pv then
				local x = X(p.t)
				Line(pools.you, plot, x, Y(pv), x, Y(p.score), c)
			end
			pt, pv = p.t, p.score
		end
	end
	Segment(pools.you, ctx.now, sum.you, view.x1, sum.you + sum.pace * (view.x1 - ctx.now) / DAY, c, true)
end

local function Overlaps(a, b)
	return a[1] < b[1] + b[3] and b[1] < a[1] + a[3] and a[2] < b[2] + b[4] and b[2] < a[2] + a[4]
end

local function DrawMarkers(ctx, hidden, taken)
	local sum, today = ctx.summary, X(ctx.now)
	-- Boxes (left, bottom, width, height) that a label must not cover.
	-- `taken` arrives holding the axis tags ("Projected", "Season end").

	local function mark(x, y, c, size, diamond)
		if diamond then
			Marker(pools.diamondRings, pools.diamonds, plot, x, y, c, size)
		else
			Marker(pools.dotRings, pools.dots, plot, x, y, c, size)
		end
		taken[#taken + 1] = { x - 7, y - 7, 14, 14 }
	end

	-- Where every series stands today.
	for _, s in ipairs(sum.tiers) do
		if not hidden[s.tier.key] then
			mark(today, Y(s.lineNow), s.tier.color, 8)
		end
	end
	mark(today, Y(sum.you), ns.YOU_COLOR, 9)

	-- Where your pace meets each line, labelled with the date. Each label tries
	-- above, below, right, then left of its marker, and takes the first spot
	-- clear of the markers and earlier labels.
	local crossings = {}
	for _, s in ipairs(sum.tiers) do
		if s.eta and s.eta <= view.x1 and not hidden[s.tier.key] then
			local x, y = X(s.eta), Y(sum.you + sum.pace * s.days)
			mark(x, y, ns.YOU_COLOR, 12, true)
			crossings[#crossings + 1] = { s = s, x = x, y = y }
		end
	end
	for _, cr in ipairs(crossings) do
		local fs = Text(pools.labels, "tiny", C.ink, "BOTTOMLEFT", plot, "BOTTOMLEFT", 0, 0, cr.s.tier.short .. " by " .. ns.DateText(cr.s.eta))
		local w, h, x, y = fs:GetStringWidth() + 8, 15, cr.x, cr.y
		local box
		for _, b in ipairs({
			{ x - w / 2, y + 9, w, h },
			{ x - w / 2, y - 9 - h, w, h },
			{ x + 10, y - h / 2, w, h },
			{ x - 10 - w, y - h / 2, w, h },
		}) do
			local inside = b[1] >= 0 and b[1] + w <= PW and b[2] >= 0 and b[2] + h <= PH
			local clear = inside
			for _, t in ipairs(taken) do
				if clear and Overlaps(b, t) then
					clear = false
				end
			end
			if clear then
				box = b
				break
			end
		end
		box = box or { x - w / 2, y + 9, w, h }
		taken[#taken + 1] = box
		fs:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", box[1] + 4, box[2] + 2)
		local bg = pools.labelBg:Get()
		bg:ClearAllPoints()
		bg:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", box[1], box[2])
		bg:SetSize(w, h)
		Color(bg, C.surface, 0.92)
	end
end

-- Series names at the right edge, where each line ends. When two would touch,
-- the later one is dropped rather than nudged off its line; the tiles carry it.
local function DrawEndLabels(ctx, hidden)
	local sum = ctx.summary
	local entries = { { "You", sum.you + sum.pace * (view.x1 - ctx.now) / DAY, C.ink } }
	for _, s in ipairs(sum.tiers) do
		if not hidden[s.tier.key] then
			entries[#entries + 1] = { s.tier.short, ns.LineValue(s.pts, s.fit, view.x1), C.ink2 }
		end
	end
	local placed = {}
	for _, e in ipairs(entries) do
		local y = Y(e[2])
		local clear = true
		for _, py in ipairs(placed) do
			if math.abs(py - y) < 13 then
				clear = false
			end
		end
		if clear then
			placed[#placed + 1] = y
			Text(pools.labels, "tiny", e[3], "LEFT", plot, "BOTTOMLEFT", PW + 8, y, e[1])
		end
	end
end

local function DrawStrip(ctx)
	local maxGain = 0
	for _, p in ipairs(ctx.history.points) do
		if p.gain and p.t >= view.x0 then
			maxGain = math.max(maxGain, p.gain)
		end
	end
	Text(pools.axis, "tiny", C.muted, "BOTTOMRIGHT", strip, "BOTTOMLEFT", -8, 0, "Per key")
	if maxGain <= 0 then
		return
	end
	Text(pools.axis, "tiny", C.muted, "TOPRIGHT", strip, "TOPLEFT", -8, 0, "+" .. ns.Fmt(maxGain))
	local c = ns.YOU_COLOR
	for _, p in ipairs(ctx.history.points) do
		if p.gain and p.t >= view.x0 then
			local b = pools.bars:Get()
			Color(b, c, 0.9)
			b:SetSize(3, math.max(2, p.gain / maxGain * (STRIP_H - 2)))
			b:ClearAllPoints()
			b:SetPoint("BOTTOMLEFT", strip, "BOTTOMLEFT", X(p.t) - 1.5, 1)
		end
	end
end

local function DrawNotes(ctx)
	local y = -(FOOT_T + view.shift)
	local function note(s, c)
		local fs = Text(pools.notes, "tiny", c, "TOPLEFT", frame, "TOPLEFT", PAD, y, s)
		fs:SetWordWrap(true)
		fs:SetWidth(W - 2 * PAD)
		fs:SetJustifyH("LEFT")
		y = y - fs:GetStringHeight() - 5
	end

	local key, last = ctx.regionKey, ns.Data.lastSeason
	local source = "Lines from Raider.IO, updated " .. ns.DateText(ctx.region.updatedAt) .. "."
	if last and last.p999 and last.p999.awarded[key] then
		source = source
			.. (" They are estimates: last season Blizzard awarded the 0.1%% title at %s, %s below Raider.IO's final line."):format(
				ns.Fmt(last.p999.awarded[key]),
				ns.Fmt(last.p999.raiderio[key] - last.p999.awarded[key])
			)
	end
	note(source, C.muted)
	for _, w in ipairs(ctx.warnings) do
		note(ns.Hex(C.warn) .. "!|r  " .. w, C.ink2)
	end
	frame:SetHeight(math.max(H + view.shift, -y + PAD - 4))
end

-- How far a groupmate is from the next line up, in a few words.
local function NextLine(ctx, score)
	local sum = ctx.summary
	for i = #sum.tiers, 1, -1 do
		local s = sum.tiers[i]
		if score < s.lineNow then
			return ns.Fmt(s.lineNow - score) .. " to " .. s.tier.short
		end
	end
	return "above " .. sum.tiers[1].tier.short
end

local function DrawGroup(ctx)
	for i, cell in ipairs(group.cells) do
		local m = ctx.party[i]
		cell.member = m
		cell:SetShown(m ~= nil)
		if m then
			local c = ns.ClassColor(m.class)
			cell.name:SetText(m.name)
			cell.name:SetTextColor(c[1], c[2], c[3])
			if m.score > 0 then
				cell.value:SetText(ns.Fmt(m.score))
				cell.sub:SetText(NextLine(ctx, m.score))
			else
				cell.value:SetText("-")
				cell.sub:SetText("no rating yet")
			end
		end
	end
end

-- Groupmates on the graph: a marker on today's line at their rating, named in
-- their class colour, and the line remembered from earlier groups behind it.
local function DrawParty(ctx)
	local today, placed = X(ctx.now), { Y(ctx.summary.you) }
	-- Off-scale ratings ride the plot's edge rather than leave it.
	local function edge(v)
		return math.max(view.y0, math.min(view.y1, v))
	end
	for _, m in ipairs(ctx.party) do
		if m.score > 0 then
			local pts = m.seen and m.seen.pts or {}
			local pt, pv
			for _, p in ipairs(pts) do
				if pt then
					Segment(pools.party, pt, edge(pv), p[1], edge(pv), C.ink2, false, 0.5, 1.5)
					local x = X(p[1])
					if p[1] > view.x0 and edge(p[2]) ~= edge(pv) then
						Line(pools.party, plot, x, Y(edge(pv)), x, Y(edge(p[2])), C.ink2, 0.5, 1.5)
					end
				end
				pt, pv = p[1], p[2]
			end
			if pt and pt < ctx.now then
				Segment(pools.party, pt, edge(pv), ctx.now, edge(pv), C.ink2, false, 0.5, 1.5)
			end

			local offScale = edge(m.score) ~= m.score
			local y = Y(edge(m.score))
			Marker(pools.dotRings, pools.dots, plot, today, y, C.ink2, 7)
			local clear = true
			for _, py in ipairs(placed) do
				if math.abs(py - y) < 12 then
					clear = false
				end
			end
			if clear then
				placed[#placed + 1] = y
				local name = offScale and (m.name .. "  " .. ns.Fmt(m.score)) or m.name
				local fs = Text(pools.labels, "tiny", ns.ClassColor(m.class), "RIGHT", plot, "BOTTOMLEFT", today - 10, y, name)
				local w = fs:GetStringWidth() + 8
				local bg = pools.labelBg:Get()
				bg:ClearAllPoints()
				bg:SetPoint("RIGHT", plot, "BOTTOMLEFT", today - 6, y)
				bg:SetSize(w, 14)
				Color(bg, C.surface, 0.92)
			end
		end
	end
end

function Graph:Render()
	if not frame or not frame:IsShown() then
		return
	end
	for _, p in pairs(pools) do
		p:Reset()
	end
	self:ClearHover()
	segmented:Refresh()

	local ctx = ns.Context()
	frame.region:SetText(ctx.regionKey and ctx.regionKey:upper() or "")
	frame.season:SetText(ns.Data and ns.Data.season.name or "")

	if ctx.error then
		view = nil
		for _, t in ipairs(tiles) do
			t:Hide()
		end
		message:SetText(ctx.error)
		message:Show()
		group:Hide()
		panel:Hide()
		plot:Show()
		frame:SetHeight(H)
		return
	end
	message:Hide()
	for _, t in ipairs(tiles) do
		t:Show()
	end

	-- In a party, the group row opens under the tiles and the rest moves down.
	local grouped = #ctx.party > 0
	local shift = grouped and GROUP_SHIFT or 0
	group:SetShown(grouped)
	plot:ClearAllPoints()
	plot:SetPoint("TOPLEFT", PL, -(PT + shift))
	strip:ClearAllPoints()
	strip:SetPoint("TOPLEFT", PL, -(STRIP_T + shift))
	panel:ClearAllPoints()
	panel:SetPoint("TOPLEFT", PAD, -(PT + shift))

	local hidden = CludesUITitleLineDB.hidden
	DrawTiles(ctx, hidden)
	if grouped then
		DrawGroup(ctx)
	end

	-- The Keys and Guild views are tables in the plot's place.
	local list = ns.Views and ns.Views[CludesUITitleLineDB.view]
	plot:SetShown(not list)
	strip:SetShown(not list)
	hover:SetShown(not list)
	panel:SetShown(list ~= nil)
	if list then
		view = { now = ctx.now, ctx = ctx, shift = shift }
		list(panel, ctx)
		DrawNotes(ctx)
		return
	end

	view = ns.Window(ctx, CludesUITitleLineDB.view, hidden)
	view.now, view.ctx, view.shift = ctx.now, ctx, shift

	local taken = DrawAxes(ctx, hidden)
	DrawSeries(ctx, hidden)
	DrawParty(ctx)
	DrawMarkers(ctx, hidden, taken)
	DrawEndLabels(ctx, hidden)
	DrawStrip(ctx)
	DrawNotes(ctx)
end

-- Hover readout --------------------------------------------------------------------------

function Graph:ClearHover()
	if not hover then
		return
	end
	if view then
		view.hoverX = nil
	end
	cross:Hide()
	tip:Hide()
	pools.hoverRings:Reset()
	pools.hoverMarks:Reset()
end

-- The readout is as wide as its use needs: a date's values, or a groupmate's dungeons.
local function SizeTip(w)
	tip.w = w
	tip:SetWidth(w)
end

local function TipRow(swatch, label, value, y, muted, labelColor)
	local r = tip.rows:Get()
	r:SetWidth(tip.w - 20)
	r:ClearAllPoints()
	r:SetPoint("TOPLEFT", tip, "TOPLEFT", 10, y)
	if swatch then
		r.swatch:SetColorTexture(swatch[1], swatch[2], swatch[3])
		r.swatch:Show()
		r.label:SetPoint("LEFT", 16, 0)
	else
		r.swatch:Hide()
		r.label:SetPoint("LEFT", 0, 0)
	end
	r.label:SetText(label)
	local lc = labelColor or C.ink2
	r.label:SetTextColor(lc[1], lc[2], lc[3])
	r.value:SetText(value)
	local c = muted and C.muted or C.ink
	r.value:SetTextColor(c[1], c[2], c[3])
	return y - 17
end

function Graph.OnHover()
	if not view then
		return
	end
	local cx = GetCursorPosition() / plot:GetEffectiveScale() - plot:GetLeft()
	cx = math.max(0, math.min(PW, cx))
	-- Snap to whole days from the window's start: readers aim at a date.
	local t = view.x0 + math.floor((cx / PW * (view.x1 - view.x0)) / DAY + 0.5) * DAY
	t = math.min(t, view.x1)
	local x = X(t)
	if view.hoverX == x then
		return
	end
	view.hoverX = x

	local ctx, sum = view.ctx, view.ctx.summary
	local future = t > ctx.now
	cross:ClearAllPoints()
	cross:SetPoint("TOP", plot, "TOPLEFT", x, 0)
	cross:SetPoint("BOTTOM", strip, "BOTTOMLEFT", x, 0)
	cross:Show()

	pools.hoverRings:Reset()
	pools.hoverMarks:Reset()
	tip.rows:Reset()
	SizeTip(210)
	tip.note:Hide()
	tip.title:SetText(ns.DateText(t, true))
	tip.title:SetTextColor(C.ink[1], C.ink[2], C.ink[3])
	tip.tag:SetText(future and "Projected" or "")

	local y = -30
	local you = future and (sum.you + sum.pace * (t - ctx.now) / DAY) or ns.ScoreAt(ctx.history.points, t)
	Marker(pools.hoverRings, pools.hoverMarks, plot, x, Y(you), ns.YOU_COLOR, 8)
	y = TipRow(ns.YOU_COLOR, "You", ns.Fmt(you), y)
	for _, s in ipairs(sum.tiers) do
		if not CludesUITitleLineDB.hidden[s.tier.key] then
			local lo, v, hi = ns.LineRange(s.pts, s.fit, t)
			Marker(pools.hoverRings, pools.hoverMarks, plot, x, Y(v), s.tier.color, 8)
			local text = ns.Fmt(v)
			if hi - lo >= 2 then
				text = ns.Fmt(lo) .. "-" .. ns.Fmt(hi)
			end
			y = TipRow(s.tier.color, s.tier.label, text, y)
		end
	end

	-- Groupmates, where TitleLine has seen them by that day.
	local gap = true
	for _, m in ipairs(ctx.party) do
		local v
		if m.score > 0 and math.abs(t - ctx.now) < DAY / 2 then
			v = m.score
		elseif not future and m.seen then
			for _, p in ipairs(m.seen.pts) do
				if p[1] <= t then
					v = p[2]
				end
			end
		end
		if v then
			if gap then
				y = y - 4
				gap = false
			end
			y = TipRow(C.ink2, m.name, ns.Fmt(v), y, false, ns.ClassColor(m.class))
		end
	end

	-- The keys that raised your rating that day.
	local first = true
	for _, p in ipairs(ctx.history.points) do
		if p.gain and math.abs(p.t - t) < DAY / 2 then
			if first then
				y = y - 4
				first = false
			end
			local name = C_ChallengeMode.GetMapUIInfo(p.map) or "?"
			y = TipRow(nil, ("%s +%d"):format(name, p.level), "+" .. ns.Fmt(p.gain), y, true)
		end
	end

	tip:SetHeight(-y + 6)
	tip:ClearAllPoints()
	if x > PW / 2 then
		tip:SetPoint("TOPRIGHT", plot, "TOPLEFT", x - 14, -6)
	else
		tip:SetPoint("TOPLEFT", plot, "TOPLEFT", x + 14, -6)
	end
	tip:Show()
end

-- A groupmate's best key and score in every dungeon, under their cell.
function Graph.ShowMember(cell)
	local m = cell.member
	if not m then
		return
	end
	tip.rows:Reset()
	local c = ns.ClassColor(m.class)
	SizeTip(260)
	tip.note:Hide()
	tip.title:SetText(m.name)
	tip.title:SetTextColor(c[1], c[2], c[3])
	tip.tag:SetText(m.seen and #m.seen.pts > 1 and ("seen since " .. ns.DateText(m.seen.pts[1][1])) or "")

	local runs = {}
	for _, r in ipairs(m.runs) do
		if r.mapScore and r.mapScore > 0 then
			runs[#runs + 1] = r
		end
	end
	table.sort(runs, function(a, b)
		return a.mapScore > b.mapScore
	end)
	local y = -30
	for _, r in ipairs(runs) do
		local name = C_ChallengeMode.GetMapUIInfo(r.challengeModeID) or "?"
		local label = ("%s +%d"):format(name, r.bestRunLevel) .. (r.finishedSuccess and "" or "  (over time)")
		y = TipRow(nil, label, ns.Fmt(r.mapScore), y, not r.finishedSuccess)
	end
	if #runs == 0 then
		y = TipRow(nil, "No rated runs shared yet", "", y, true)
	end

	tip:SetHeight(-y + 6)
	tip:ClearAllPoints()
	tip:SetPoint("TOPLEFT", cell, "BOTTOMLEFT", 0, -6)
	tip:Show()
end

-- A title tile's detail: the line now and at the season end, what that is in
-- key levels, and the daily gain it takes against yours.
-- Your characters this season, best first, with how far each is from the
-- next line; says what a click on the tile does.
function Graph.ShowChars(t)
	local ctx = t.ctx
	if not ctx or #ctx.chars == 0 then
		return
	end
	tip.rows:Reset()
	SizeTip(250)
	tip.title:SetText("Your characters")
	tip.title:SetTextColor(C.ink[1], C.ink[2], C.ink[3])
	tip.tag:SetText("titles are account-wide")
	local y = -30
	for _, c in ipairs(ctx.chars) do
		y = TipRow(nil, c.name, ns.Fmt(c.score), y, false, ns.ClassColor(c.class))
	end
	tip.note:SetWidth(tip.w - 20)
	tip.note:ClearAllPoints()
	tip.note:SetPoint("TOPLEFT", tip, "TOPLEFT", 10, y - 4)
	local note = "A character appears here once you have logged in on it this season."
	if t.canSwitch then
		note = (ctx.subject.isCurrent and "Click to show your best character." or "Click to show the character you are playing.")
			.. " " .. note
	end
	tip.note:SetText(note)
	tip.note:Show()
	y = y - 4 - tip.note:GetStringHeight()
	tip:SetHeight(-y + 10)
	tip:ClearAllPoints()
	tip:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -6)
	tip:Show()
end

function Graph.ShowTile(t)
	local s, ctx = t.summary, t.ctx
	if not s or CludesUITitleLineDB.hidden[s.tier.key] then
		return
	end
	local sum = ctx.summary
	tip.rows:Reset()
	SizeTip(250)
	tip.title:SetText(s.tier.label)
	tip.title:SetTextColor(C.ink[1], C.ink[2], C.ink[3])
	tip.tag:SetText("")

	local y = -30
	y = TipRow(nil, "Line today", ns.Fmt(s.lineNow), y)
	if s.lineEnd then
		y = TipRow(nil, sum.endsEstimated and "At the season end (est.)" or "At the season end", "~" .. ns.Fmt(s.lineEnd), y)
		y = TipRow(nil, "Likely range at the end", ns.Fmt(s.lineEndLow) .. "-" .. ns.Fmt(s.lineEndHigh), y)
	end
	if s.levelNow then
		y = TipRow(nil, "Timed in every dungeon, today", LevelText(s.levelNow), y)
	end
	if s.levelEnd then
		y = TipRow(nil, "Timed in every dungeon, at the end", LevelText(s.levelEnd), y)
	end
	if s.need then
		y = TipRow(nil, "Daily gain it takes", ("+%.1f"):format(s.need), y)
		y = TipRow(nil, "Your daily gain", ("+%.1f"):format(sum.pace), y)
	end

	tip.note:SetWidth(tip.w - 20)
	tip.note:ClearAllPoints()
	tip.note:SetPoint("TOPLEFT", tip, "TOPLEFT", 10, y - 4)
	tip.note:SetText(ns.SCORING_NOTE)
	tip.note:Show()
	y = y - 4 - tip.note:GetStringHeight()

	tip:SetHeight(-y + 10)
	tip:ClearAllPoints()
	tip:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -6)
	tip:Show()
end

-- The drawing kit Views.lua shares, so its tables match the graph.
ns.UI = {
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
	if not frame then
		Create()
	end
	frame:SetShown(not frame:IsShown())
end

function Graph:ApplyScale()
	if frame then
		frame:SetScale(CludesUITitleLineDB.scale or DEFAULT_SCALE)
	end
end

function Graph:Refresh()
	if frame and frame:IsShown() then
		self:Render()
	end
end
