-- TitleLine: your Mythic+ rating against the season's title lines.
--
-- The lines come from Raider.IO and ship in Data.lua, because addons cannot
-- reach the network. Your own rating history is rebuilt from the game's run
-- history, so the graph covers the whole season, not just since install.

local ADDON, ns = ...
if ns.standalone then return end

local DAY = 86400
ns.DAY = DAY

local LINE_SLOPE_DAYS = 7 -- early in a season, before the curve fit has enough points
local FIT_FROM_DAY, FIT_MIN_POINTS = 7, 5 -- the curve ignores the opening week's scramble
local PACE_DAYS = 14 -- how far back your own pace is measured
local STALE_DAYS = 7

-- GetCurrentRegion() ids, per warcraft.wiki.gg/wiki/API_GetCurrentRegion.
ns.REGIONS = { [1] = "us", [2] = "kr", [3] = "eu", [4] = "tw", [5] = "cn" }

-- The tiers are ordered, so they share one hue stepped by lightness, brightest
-- for the most elite; your rating is the only accent. Checked against the dark
-- surface: the ramp passes the ordinal checks and every tier sits at least
-- dE 24 from the accent under colour-blind simulation.
ns.TIERS = {
	{ key = "p999", label = "Top 0.1%", short = "0.1%", color = { 0.525, 0.714, 0.937 } }, -- #86b6ef
	{ key = "p990", label = "Top 1%", short = "1%", color = { 0.224, 0.529, 0.898 } }, -- #3987e5
}
ns.YOU_COLOR = { 0.788, 0.522, 0 } -- #c98500

-- Surfaces and ink. Text never takes a series colour; a key beside it does.
ns.COLORS = {
	surface = { 0.102, 0.102, 0.098 }, -- #1a1a19
	raised = { 0.141, 0.141, 0.133 }, -- #242422
	ink = { 0.941, 0.937, 0.925 }, -- #f0efec
	ink2 = { 0.765, 0.761, 0.718 }, -- #c3c2b7
	muted = { 0.537, 0.529, 0.506 }, -- #898781
	grid = { 0.173, 0.173, 0.165 }, -- #2c2c2a
	axis = { 0.220, 0.220, 0.208 }, -- #383835
	warn = { 0.980, 0.698, 0.098 }, -- #fab219
}

local DEFAULTS = { chat = true, alerts = true, view = "recent", hidden = {}, seen = {}, chars = {}, shared = {}, alertState = {} }
local SEEN_CAP = 500 -- groupmates remembered per season

local PREFIX = "|cffffd100TitleLine|r: "
function ns.Print(msg)
	print(PREFIX .. msg)
end

-- Formatting -------------------------------------------------------------------

function ns.Fmt(n)
	local s = tostring(math.floor(n + 0.5))
	local sign = ""
	if s:sub(1, 1) == "-" then
		sign, s = "-", s:sub(2)
	end
	s = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return sign .. (s:gsub("^,", ""))
end

function ns.DateText(t, long)
	local s = date(long and "%a %d %b" or "%d %b", t)
	return (s:gsub(" 0", " "):gsub("^0", ""))
end

function ns.Hex(c)
	return ("|cff%02x%02x%02x"):format(c[1] * 255, c[2] * 255, c[3] * 255)
end

-- A short coloured line, inline in text, to key a series.
function ns.Key(c)
	return ("|TInterface\\Buttons\\WHITE8X8:2:10:0:0:8:8:0:8:0:8:%d:%d:%d|t"):format(c[1] * 255, c[2] * 255, c[3] * 255)
end

-- Your rating history ----------------------------------------------------------

-- Run dates are realm time. time() reads a date table as local time, so measure
-- how far the realm clock sits from the local one and correct by that.
local function RealmOffset()
	local now = C_DateAndTime.GetCurrentCalendarTime()
	local asLocal = time({ year = now.year, month = now.month, day = now.monthDay, hour = now.hour, min = now.minute })
	return math.floor((time() - asLocal) / 900 + 0.5) * 900
end

function ns.CalendarToEpoch(d, offset)
	return time({ year = d.year, month = d.month, day = d.monthDay, hour = d.hour, min = d.minute }) + (offset or 0)
end

-- The rating is the sum of each dungeon's best run score, so replaying the
-- season's runs in order rebuilds it over time. `exact` says whether the replay
-- lands on the rating the game reports; when it does not, the graph says so.
function ns.Replay(runs, actual, now)
	table.sort(runs, function(a, b)
		return a.t < b.t
	end)
	local best, total, points = {}, 0, {}
	for _, run in ipairs(runs) do
		local prev = best[run.map] or 0
		if run.score > prev then
			best[run.map] = run.score
			total = total - prev + run.score
			points[#points + 1] = {
				t = math.min(run.t, now),
				score = total,
				gain = run.score - prev,
				map = run.map,
				level = run.level,
			}
		end
	end
	local exact = math.abs(total - actual) <= 1
	-- Always end on the live rating, so the line reaches today.
	points[#points + 1] = { t = now, score = actual }
	return { points = points, rebuilt = total, actual = actual, exact = exact, runs = #runs }
end

function ns.BuildHistory(now)
	local offset = RealmOffset()
	local runs = {}
	for _, r in ipairs(C_MythicPlus.GetRunHistory(true, true, true) or {}) do
		if r.runScore and r.runScore > 0 and r.completionDate then
			runs[#runs + 1] = {
				t = ns.CalendarToEpoch(r.completionDate, offset),
				map = r.mapChallengeModeID,
				level = r.level,
				score = r.runScore,
			}
		end
	end
	return ns.Replay(runs, C_ChallengeMode.GetOverallDungeonScore() or 0, now)
end

-- Your rating is a step function: it only moves when a key raises a best.
function ns.ScoreAt(points, t)
	local v = 0
	for _, p in ipairs(points) do
		if p.t > t then
			break
		end
		v = p.score
	end
	return v
end

-- The lines ------------------------------------------------------------------

-- Line points are { time, score }. Returns nil past the last point.
function ns.LineAt(pts, t)
	local n = #pts
	if n == 0 then
		return nil
	end
	if t <= pts[1][1] then
		return pts[1][2]
	end
	for i = 2, n do
		local a, b = pts[i - 1], pts[i]
		if t <= b[1] then
			return a[2] + (b[2] - a[2]) * (t - a[1]) / (b[1] - a[1])
		end
	end
	return nil
end

-- Least-squares rise per day over the last `days` of the series.
function ns.Slope(pts, days)
	local n = #pts
	if n < 2 then
		return 0
	end
	local from = pts[n][1] - days * DAY
	local c, sx, sy, sxx, sxy = 0, 0, 0, 0, 0
	for i = 1, n do
		local p = pts[i]
		if p[1] >= from then
			local x = (p[1] - from) / DAY
			c, sx, sy, sxx, sxy = c + 1, sx + x, sy + p[2], sxx + x * x, sxy + x * p[2]
		end
	end
	local d = c * sxx - sx * sx
	if c < 2 or d == 0 then
		return 0
	end
	return (c * sxy - sx * sy) / d
end

-- How the line will move past its data. The lines rise fast early and slow all
-- season, so they follow v = a + b*ln(day). Backtested on Raider.IO's history
-- (season 1, all regions, then season 2 untouched), this is ~34 off four
-- weeks ahead and ~52 off eight weeks ahead, against 77 and 252 for carrying
-- on the last week's straight-line rise, which always overshot. Too little
-- data early in a season falls back to that straight line.
function ns.Fit(pts, start)
	local c, sx, sy, sxx, sxy = 0, 0, 0, 0, 0
	for _, p in ipairs(pts) do
		local day = (p[1] - start) / DAY
		if day >= FIT_FROM_DAY then
			local x = math.log(day)
			c, sx, sy, sxx, sxy = c + 1, sx + x, sy + p[2], sxx + x * x, sxy + x * p[2]
		end
	end
	local d = c * sxx - sx * sx
	if c < FIT_MIN_POINTS or d == 0 then
		return { slope = ns.Slope(pts, LINE_SLOPE_DAYS) }
	end
	return { start = start, b = (c * sxy - sx * sy) / d }
end

-- The line at time t: the data where it exists, its fitted course beyond it.
function ns.LineValue(pts, fit, t)
	local last = pts[#pts]
	if t <= last[1] then
		return ns.LineAt(pts, t)
	end
	if fit.b then
		return last[2] + fit.b * (math.log((t - fit.start) / DAY) - math.log((last[1] - fit.start) / DAY))
	end
	return last[2] + fit.slope * (t - last[1]) / DAY
end

-- How far off a projection has been, by days past the line's last data
-- point: 80% of Season 1's forecasts (every region, both title lines, made
-- from day 21 on) landed within this many points. Season 1 ran low at the
-- longest reaches, but Season 2 has shown no such lean so far, so the band is
-- symmetric rather than shifting the line.
local BAND = { { 0, 0 }, { 7, 16 }, { 14, 26 }, { 21, 33 }, { 28, 43 }, { 42, 57 }, { 56, 64 }, { 84, 94 }, { 112, 155 } }

function ns.Band(days)
	if days <= 0 then
		return 0
	end
	for i = 2, #BAND do
		local a, b = BAND[i - 1], BAND[i]
		if days <= b[1] then
			return a[2] + (b[2] - a[2]) * (days - a[1]) / (b[1] - a[1])
		end
	end
	local a, b = BAND[#BAND - 1], BAND[#BAND]
	return b[2] + (b[2] - a[2]) * (days - b[1]) / (b[1] - a[1])
end

-- The line at t with its likely range: low, central, high.
function ns.LineRange(pts, fit, t)
	local v = ns.LineValue(pts, fit, t)
	local band = ns.Band((t - pts[#pts][1]) / DAY)
	return v - band, v, v + band
end

-- Days from now until a straight-line pace meets the line, or nil within a
-- year. The line is a curve, so step a day at a time, then bisect the step.
-- `edge` -1 or +1 aims at the low or high side of the line's range instead.
function ns.Crossing(pts, fit, now, you, pace, edge)
	if pace <= 0 then
		return nil
	end
	local last = pts[#pts][1]
	local function ahead(d)
		local t = now + d * DAY
		local line = ns.LineValue(pts, fit, t)
		if edge then
			line = line + edge * ns.Band((t - last) / DAY)
		end
		return you + pace * d >= line
	end
	for d = 1, 365 do
		if ahead(d) then
			local lo, hi = d - 1, d
			for _ = 1, 24 do
				local mid = (lo + hi) / 2
				if ahead(mid) then
					hi = mid
				else
					lo = mid
				end
			end
			return hi
		end
	end
	return nil
end

-- Where you stand against each line, and when you would cross it if you kept
-- your recent pace and the line kept its course.
function ns.Summary(region, history, now, you)
	you = you or history.actual
	local from = math.max(region.startsAt, now - PACE_DAYS * DAY)
	local window = (now - from) / DAY
	-- A season's rating never falls; floor at zero so the rebuilt history's
	-- decimals against the game's whole-number rating cannot read as a loss.
	local pace = 0
	if window >= 1 then
		pace = math.max(0, (history.actual - ns.ScoreAt(history.points, from)) / window)
	end

	-- The season end: Blizzard's date once announced, until then the last
	-- season's length (Data.lua says which).
	local endsAt = region.endsAt
	local daysLeft = endsAt and endsAt > now and (endsAt - now) / DAY or nil

	local tiers = {}
	for _, tier in ipairs(ns.TIERS) do
		local pts = region.lines[tier.key]
		if pts and #pts > 0 then
			local fit = ns.Fit(pts, region.startsAt)
			local lineNow = ns.LineValue(pts, fit, now)
			local s = { tier = tier, pts = pts, fit = fit, lineNow = lineNow, gap = lineNow - you }
			if s.gap > 0 then
				s.days = ns.Crossing(pts, fit, now, you, pace)
				s.eta = s.days and (now + s.days * DAY)
				s.afterEnd = s.eta and endsAt and s.eta > endsAt
				-- The same crossing against the low and high side of the line's range.
				local early, late = ns.Crossing(pts, fit, now, you, pace, -1), ns.Crossing(pts, fit, now, you, pace, 1)
				s.etaEarly = early and (now + early * DAY)
				s.etaLate = late and (now + late * DAY)
			end
			-- Where the line should finish, and the daily gain that reaches it.
			if daysLeft then
				s.lineEndLow, s.lineEnd, s.lineEndHigh = ns.LineRange(pts, fit, endsAt)
				s.need = math.max(0, (s.lineEnd - you) / math.max(daysLeft, 1))
			end
			tiers[#tiers + 1] = s
		end
	end
	return {
		you = you,
		pace = pace,
		paceDays = window,
		tiers = tiers,
		endsAt = endsAt,
		endsEstimated = region.endsEstimated,
		daysLeft = daysLeft,
	}
end

-- A date span, sharing the month when both ends do: "20-28 Nov".
function ns.SpanText(a, b)
	if date("%m", a) == date("%m", b) then
		return ns.DateText(a):match("^(%d+)") .. "-" .. ns.DateText(b)
	end
	return ns.DateText(a) .. "-" .. ns.DateText(b)
end

-- When you reach the line at your current pace, in a few words: a span from
-- the low to the high side of the line's range where both fall in time.
function ns.EtaText(s, pace, endsAt)
	if s.gap <= 0 then
		return "reached"
	end
	local early = s.etaEarly or s.eta
	if early and endsAt and early > endsAt then
		return "after the season"
	end
	if early and s.etaLate and not (endsAt and s.etaLate > endsAt) then
		if ns.DateText(early) == ns.DateText(s.etaLate) then
			return "ETA " .. ns.DateText(early)
		end
		return "ETA " .. ns.SpanText(early, s.etaLate)
	end
	if early then
		return "ETA from " .. ns.DateText(early)
	end
	return pace and pace > 0 and "over a year" or "not closing"
end

-- Days until a line you are above would catch your straight-line pace, or
-- nil if it does not within `limit` days.
function ns.Overtake(pts, fit, now, you, pace, limit)
	for d = 1, math.floor(limit) do
		if ns.LineValue(pts, fit, now + d * DAY) >= you + pace * d then
			return d
		end
	end
	return nil
end

-- Key levels ---------------------------------------------------------------------

-- The lowest key level that, timed in every dungeon, reaches `rating`, from
-- Raider.IO's scoring table in Data.lua (15 rating a level per dungeon, 30 at
-- the levels that add an affix). Past the table's top it carries on at the
-- table's last step.
ns.SCORING_NOTE = "Key levels use Raider.IO's scoring: the rating for timing every dungeon at that level, with 15 a level per dungeon and 30 at the levels that add an affix."

function ns.LevelFor(rating)
	local t = ns.Data.levels
	for _, row in ipairs(t) do
		if row[2] >= rating - 0.5 then
			return row[1]
		end
	end
	local a, b = t[#t - 1], t[#t]
	return b[1] + math.ceil((rating - b[2]) / (b[2] - a[2]))
end

-- Each title as one key level timed in every dungeon, at the line's
-- season-end value where that is known (titles are awarded at the end), and
-- each dungeon's best, lowest first.
function ns.Targets(maps, runs, tiers)
	local byMap = {}
	for _, r in ipairs(runs or {}) do
		byMap[r.challengeModeID] = r
	end
	local goals = {}
	for _, s in ipairs(tiers) do
		local rating = s.lineEnd or s.lineNow
		goals[#goals + 1] = {
			tier = s.tier,
			atEnd = s.lineEnd ~= nil,
			level = ns.LevelFor(rating),
		}
	end
	local rows = {}
	for _, map in ipairs(maps) do
		local r = byMap[map]
		local row = { map = map, best = r and r.bestRunLevel or 0, score = r and r.mapScore or 0 }
		row.played = row.score > 0
		row.timed = row.played and r.finishedSuccess
		rows[#rows + 1] = row
	end
	table.sort(rows, function(x, y)
		if x.best ~= y.best then
			return x.best < y.best
		end
		return x.score < y.score
	end)
	return goals, rows
end

-- Guild ---------------------------------------------------------------------------

-- The roster's rating has no season: a member keeps the last one they had,
-- so anyone not online since this season began is showing an old season's.
-- Last online comes as time since (Blizzard's member list prints it as "3
-- days ago"); a member in game now has none.
local IN_GAME = { [1] = true, [4] = true, [5] = true } -- Enum.ClubMemberPresence Online, Away, Busy

function ns.SeenThisSeason(info, seasonDays)
	if info.isSelf then
		return true
	end
	local y, m, d, h = info.lastOnlineYear, info.lastOnlineMonth, info.lastOnlineDay, info.lastOnlineHour
	if y or m or d or h then
		return (y or 0) * 365 + (m or 0) * 30 + (d or 0) + (h or 0) / 24 <= seasonDays
	end
	return IN_GAME[info.presence] == true
end

-- Your guild's rated members this season, best first, read from the guild
-- roster the way Blizzard's own member list reads it. During a chat lockdown
-- (combat in instances) those values are secret, so it waits instead.
function ns.Guild(startsAt, now)
	if not IsInGuild() then
		return { state = "none" }
	end
	if C_ChatInfo.InChatMessagingLockdown() then
		return { state = "hidden" }
	end
	local ok, members = pcall(function()
		local club = C_Club.GetGuildClubId()
		local ids = club and C_Club.GetClubMembers(club)
		if not ids or #ids == 0 then
			return nil
		end
		local out, stale = {}, 0
		local seasonDays = (now - startsAt) / DAY
		for _, id in ipairs(ids) do
			local info = C_Club.GetMemberInfo(club, id)
			local score = info and info.overallDungeonScore
			if score and score > 0 then
				if ns.SeenThisSeason(info, seasonDays) then
					local class = info.classID and C_CreatureInfo.GetClassInfo(info.classID)
					out[#out + 1] = {
						name = info.name,
						key = ns.Share.Key(info.name),
						class = class and class.classFile,
						score = score,
						isSelf = info.isSelf,
						online = IN_GAME[info.presence] == true,
					}
				else
					stale = stale + 1
				end
			end
		end
		table.sort(out, function(a, b)
			return a.score > b.score
		end)
		return { members = out, stale = stale }
	end)
	if not ok or not members then
		return { state = "loading" }
	end
	return { state = "ok", members = members.members, stale = members.stale }
end

-- Groupmates -------------------------------------------------------------------

-- The game gives a groupmate's rating only as it is now, with no history. So
-- each one is remembered whenever you are grouped, and over time that builds
-- their own line. A season's rating only rises, so a lower reading is stale.
function ns.Remember(m, now)
	local slug = ns.Data and ns.Data.season.slug
	local e = CludesUITitleLineDB.seen[m.key]
	if not e or e.season ~= slug then
		e = { season = slug, pts = {} }
		CludesUITitleLineDB.seen[m.key] = e
	end
	e.name, e.class, e.last = m.name, m.class, now
	local last = e.pts[#e.pts]
	if not last or m.score > last[2] then
		e.pts[#e.pts + 1] = { now, m.score }
	end
	return e
end

-- Your party as it stands, each with their rating, per-dungeon bests and what
-- has been remembered of them. Raids are skipped: M+ is a five-player party.
function ns.Party(now)
	local out = {}
	if not IsInGroup() or IsInRaid() then
		return out
	end
	for i = 1, 4 do
		local unit = "party" .. i
		if UnitExists(unit) and UnitIsPlayer(unit) and not C_Secrets.ShouldUnitIdentityBeSecret(unit) then
			local name, realm = UnitFullName(unit)
			local _, class = UnitClass(unit)
			local summary = C_PlayerInfo.GetPlayerMythicPlusRatingSummary(unit)
			local m = {
				unit = unit,
				name = name,
				key = name and (name .. "-" .. (realm and realm ~= "" and realm or GetNormalizedRealmName())),
				class = class,
				score = summary and summary.currentSeasonScore or 0,
				runs = summary and summary.runs or {},
			}
			if m.key then
				if m.score > 0 then
					m.seen = ns.Remember(m, now)
					-- Their dungeons too, for the Guild view to show later.
					if #m.runs > 0 then
						local runs = {}
						for _, r in ipairs(m.runs) do
							if (r.mapScore or 0) > 0 then
								runs[#runs + 1] = { r.challengeModeID, r.bestRunLevel, r.mapScore, r.finishedSuccess }
							end
						end
						m.seen.runs, m.seen.runsAt = runs, now
					end
				end
				out[#out + 1] = m
			end
		end
	end
	return out
end

function ns.ClassColor(class)
	local c = class and C_ClassColor.GetClassColor(class)
	return c and { c.r, c.g, c.b } or ns.COLORS.ink2
end

-- Your characters -------------------------------------------------------------------

-- Titles are account-wide (last season every character on a winning account
-- got the reward), so the character that counts is your best. Each one's
-- rating, history and dungeon bests are kept whenever you play it, so every
-- character can show the others.
function ns.CharKey()
	local name, realm = UnitFullName("player")
	return name and (name .. "-" .. (realm and realm ~= "" and realm or GetNormalizedRealmName())), name
end

local function SaveChar(ctx, key, name, history, runs)
	local slug = ns.Data.season.slug
	local old = CludesUITitleLineDB.chars[key]
	if history.actual <= 0 or (old and old.season == slug and old.score == history.actual and #old.points == #history.points) then
		return
	end
	local points = {}
	for _, p in ipairs(history.points) do
		points[#points + 1] = { p.t, p.score, p.gain, p.map, p.level }
	end
	local bests = {}
	for _, r in ipairs(runs) do
		bests[#bests + 1] = { r.challengeModeID, r.bestRunLevel, r.mapScore, r.finishedSuccess }
	end
	local _, class = UnitClass("player")
	CludesUITitleLineDB.chars[key] = {
		name = name,
		class = class,
		region = ctx.regionKey,
		season = slug,
		score = history.actual,
		updated = ctx.now,
		points = points,
		runs = bests,
	}
end

-- This season's characters in this region, best first.
function ns.Chars(regionKey)
	local slug, out = ns.Data.season.slug, {}
	for key, c in pairs(CludesUITitleLineDB.chars) do
		if c.season == slug and c.region == regionKey and c.score > 0 then
			out[#out + 1] = { key = key, name = c.name, class = c.class, score = c.score, updated = c.updated }
		end
	end
	table.sort(out, function(a, b)
		return a.score > b.score
	end)
	return out
end

-- A stored character's history and bests, in the shapes the live ones have.
local function StoredChar(key, now)
	local c = CludesUITitleLineDB.chars[key]
	local points = {}
	for _, p in ipairs(c.points) do
		points[#points + 1] = { t = p[1], score = p[2], gain = p[3], map = p[4], level = p[5] }
	end
	-- Flat from when you last played it to today.
	if #points == 0 or points[#points].t < now then
		points[#points + 1] = { t = now, score = c.score }
	end
	local runs = {}
	for _, r in ipairs(c.runs) do
		runs[#runs + 1] = { challengeModeID = r[1], bestRunLevel = r[2], mapScore = r[3], finishedSuccess = r[4] }
	end
	return { points = points, actual = c.score, rebuilt = c.score, exact = true }, runs
end

-- Everything the UI needs, or an error to show instead. The subject is your
-- best character unless `opts.subject` is "current", or you chose to view
-- the one you are playing.
function ns.Context(opts)
	local now = time()
	local ctx = { now = now, warnings = {} }
	if not ns.Data then
		ctx.error = "Cutoff data is missing. Reinstall TitleLine."
		return ctx
	end
	ctx.regionKey = ns.REGIONS[GetCurrentRegion()]
	ctx.region = ctx.regionKey and ns.Data.regions[ctx.regionKey]
	if not ctx.region then
		ctx.error = "TitleLine has no cutoff data for this region."
		return ctx
	end

	-- The character you are on, live, and kept for the others to show.
	local live = ns.BuildHistory(now)
	local mine = C_PlayerInfo.GetPlayerMythicPlusRatingSummary("player")
	local liveRuns = mine and mine.runs or {}
	local key, name = ns.CharKey()
	if key then
		SaveChar(ctx, key, name, live, liveRuns)
	end
	ctx.chars = ns.Chars(ctx.regionKey)

	local best = ctx.chars[1]
	local wanted = (opts and opts.subject) or CludesUITitleLineDB.showChar or "best"
	local _, class = UnitClass("player")
	if wanted == "best" and best and best.key ~= key and best.score > live.actual then
		ctx.history, ctx.myRuns = StoredChar(best.key, now)
		ctx.subject = { name = best.name, class = best.class, isCurrent = false, isBest = true }
	else
		ctx.history, ctx.myRuns = live, liveRuns
		ctx.subject = { name = name, class = class, isCurrent = true, isBest = not best or best.key == key or live.actual >= best.score }
	end
	ctx.summary = ns.Summary(ctx.region, ctx.history, now)
	ctx.party = ns.Party(now)

	-- Each title line as a key level timed in every dungeon.
	ctx.maps = C_ChallengeMode.GetMapTable() or {}
	for _, s in ipairs(ctx.summary.tiers) do
		s.levelNow = ns.LevelFor(s.lineNow)
		s.levelEnd = s.lineEnd and ns.LevelFor(s.lineEnd)
	end

	local age = (now - ctx.region.updatedAt) / DAY
	if age > STALE_DAYS then
		ctx.warnings[#ctx.warnings + 1] =
			("The cutoff data is %d days old. Update TitleLine for newer lines."):format(math.floor(age))
	end
	if not ctx.history.exact then
		ctx.warnings[#ctx.warnings + 1] = ("Run history adds up to %s, not your %s, so the earlier part of your line is approximate."):format(
			ns.Fmt(ctx.history.rebuilt),
			ns.Fmt(ctx.history.actual)
		)
	end
	local gameSeason = C_MythicPlus.GetCurrentSeason()
	local dataSeason = ns.Data.season.blizzardId
	if gameSeason and gameSeason > 0 and dataSeason and gameSeason ~= dataSeason then
		ctx.warnings[#ctx.warnings + 1] = ("This data is for %s (season %d) but the game is on season %d. Update TitleLine."):format(
			ns.Data.season.name,
			dataSeason,
			gameSeason
		)
	end
	return ctx
end

-- Tooltip lines, shared by the Mythic+ tab and the addon compartment.
function ns.AddTooltipLines(tt, spaced)
	local ctx = ns.Context()
	if spaced then
		tt:AddLine(" ")
	end
	local C = ns.COLORS
	tt:AddLine("TitleLine" .. (ctx.regionKey and ("  " .. ctx.regionKey:upper()) or ""), C.ink[1], C.ink[2], C.ink[3])
	if ctx.error then
		tt:AddLine(ctx.error, C.ink2[1], C.ink2[2], C.ink2[3], true)
		return
	end
	if not ctx.subject.isCurrent and ctx.subject.name then
		tt:AddLine(("For %s, your best character (titles are account-wide)"):format(ctx.subject.name), C.muted[1], C.muted[2], C.muted[3], true)
	end
	for _, s in ipairs(ctx.summary.tiers) do
		local right = s.gap > 0 and (ns.Fmt(s.gap) .. " to go") or "reached"
		tt:AddDoubleLine(
			ns.Key(s.tier.color) .. " " .. s.tier.label .. "  |cff898781" .. ns.Fmt(s.lineNow) .. "|r",
			right,
			C.ink2[1],
			C.ink2[2],
			C.ink2[3],
			C.ink[1],
			C.ink[2],
			C.ink[3]
		)
	end
	tt:AddLine("Click for the graph", C.muted[1], C.muted[2], C.muted[3])
end

-- Events ------------------------------------------------------------------------

-- Line alerts ---------------------------------------------------------------------

-- Said in chat, and for a crossing also at the centre of the screen with a
-- sound, the way Blizzard's own alarm clock does it.
local function Alert(text, loud, good)
	ns.Print(text)
	if loud then
		if RaidWarningUtil then
			RaidWarningUtil.AddMessage("TitleLine: " .. text, ChatTypeInfo["RAID_WARNING"])
		end
		PlaySound(good and SOUNDKIT.UI_PERSONAL_LOOT_BANNER or SOUNDKIT.RAID_WARNING)
	end
end

-- Watches your best character against each line: a crossing either way is
-- announced, and once a day a line you are above but on course to pass you
-- before the season ends is a warning.
function ns.CheckAlerts()
	if not CludesUITitleLineDB.alerts then
		return
	end
	local ctx = ns.Context({ subject = "best" })
	if ctx.error or ctx.history.actual <= 0 then
		return
	end
	local sum, who = ctx.summary, ctx.subject.name or "you"
	local slot = ctx.regionKey .. ":" .. ns.Data.season.slug
	local state = CludesUITitleLineDB.alertState[slot] or {}
	CludesUITitleLineDB.alertState[slot] = state
	local today = date("%Y-%m-%d", ctx.now)
	for _, s in ipairs(sum.tiers) do
		local key = s.tier.key
		local above = s.gap <= 0
		local was = state[key]
		if was == "below" and above then
			Alert(("%s passed the %s line (%s)."):format(who, s.tier.label, ns.Fmt(s.lineNow)), true, true)
		elseif was == "above" and not above then
			Alert(("The %s line (%s) passed %s: %s to go."):format(s.tier.label, ns.Fmt(s.lineNow), who, ns.Fmt(s.gap)), true, false)
		end
		state[key] = above and "above" or "below"

		if above and sum.daysLeft and state[key .. ":warned"] ~= today then
			local d = ns.Overtake(s.pts, s.fit, ctx.now, sum.you, sum.pace, sum.daysLeft)
			if d then
				state[key .. ":warned"] = today
				Alert(("At its pace the %s line passes %s around %s, before the season ends. Staying above takes +%.1f a day."):format(
					s.tier.label, who, ns.DateText(ctx.now + d * DAY), s.need or 0))
			end
		end
	end
end

local function OnKeyCompleted()
	if not CludesUITitleLineDB.chat then
		return
	end
	local info = C_ChallengeMode.GetChallengeCompletionInfo()
	if not info or info.practiceRun or not info.isEligibleForScore then
		return
	end
	-- Blizzard already prints the rating gained; add only where that leaves
	-- the character that ran the key.
	local ctx = ns.Context({ subject = "current" })
	if ctx.error then
		return
	end
	local you = info.newOverallDungeonScore or C_ChallengeMode.GetOverallDungeonScore() or 0
	local parts = {}
	for _, s in ipairs(ns.Summary(ctx.region, ctx.history, ctx.now, you).tiers) do
		if not CludesUITitleLineDB.hidden[s.tier.key] then
			local gap = s.lineNow - you
			parts[#parts + 1] = gap > 0 and (ns.Fmt(gap) .. " to " .. s.tier.label) or (s.tier.label .. " reached")
		end
	end
	if #parts > 0 then
		ns.Print(table.concat(parts, ", "))
	end
end

-- Drop remembered groupmates from earlier seasons, and the longest-unseen
-- past a cap, so the saved file stays small.
local function PruneSeen()
	local slug = ns.Data and ns.Data.season.slug
	for _, store in ipairs({ CludesUITitleLineDB.chars, CludesUITitleLineDB.shared }) do
		for key, c in pairs(store) do
			if c.season ~= slug then
				store[key] = nil
			end
		end
	end
	local keys = {}
	for key, e in pairs(CludesUITitleLineDB.seen) do
		if e.season ~= slug then
			CludesUITitleLineDB.seen[key] = nil
		else
			keys[#keys + 1] = key
		end
	end
	if #keys > SEEN_CAP then
		table.sort(keys, function(a, b)
			return CludesUITitleLineDB.seen[a].last > CludesUITitleLineDB.seen[b].last
		end)
		for i = SEEN_CAP + 1, #keys do
			CludesUITitleLineDB.seen[keys[i]] = nil
		end
	end
end

-- Group changes and finished keys both move groupmates' ratings; the server
-- takes a moment to send them, so look a little later, once per burst.
local pending = false
local function RefreshGroupSoon(delay)
	if pending then
		return
	end
	pending = true
	C_Timer.After(delay, function()
		pending = false
		ns.Party(time())
		if ns.Graph then
			ns.Graph:Refresh()
		end
	end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("CHALLENGE_MODE_COMPLETED")
events:RegisterEvent("CHALLENGE_MODE_MAPS_UPDATE")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:RegisterEvent("GUILD_ROSTER_UPDATE")
events:RegisterEvent("CLUB_MEMBERS_UPDATED")
events:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" and arg1 == ADDON then
		CludesUITitleLineDB = CludesUITitleLineDB or {}
		for k, v in pairs(DEFAULTS) do
			if CludesUITitleLineDB[k] == nil then
				CludesUITitleLineDB[k] = type(v) == "table" and {} or v
			end
		end
		PruneSeen()
	elseif event == "PLAYER_LOGIN" then
		-- Run history and the rating load from the server on request.
		C_MythicPlus.RequestMapInfo()
		RefreshGroupSoon(5)
		C_Timer.After(12, ns.CheckAlerts)
	elseif event == "CHALLENGE_MODE_COMPLETED" then
		OnKeyCompleted()
		C_MythicPlus.RequestMapInfo()
		RefreshGroupSoon(15)
		C_Timer.After(20, ns.CheckAlerts)
	elseif event == "CHALLENGE_MODE_MAPS_UPDATE" then
		if ns.Graph then
			ns.Graph:Refresh()
		end
	elseif event == "GROUP_ROSTER_UPDATE" then
		RefreshGroupSoon(2)
	elseif event == "GUILD_ROSTER_UPDATE" or event == "CLUB_MEMBERS_UPDATED" then
		if CludesUITitleLineDB and CludesUITitleLineDB.view == "guild" then
			RefreshGroupSoon(1)
		end
	end
end)

-- Slash commands and the addon compartment ---------------------------------------

local function PrintDebug()
	local ctx = ns.Context()
	ns.Print(("region %s, data %s, %s"):format(
		tostring(ctx.regionKey),
		ns.Data and ns.Data.season.slug or "missing",
		ctx.region and ("updated " .. ns.DateText(ctx.region.updatedAt)) or "no region data"
	))
	if ctx.error then
		ns.Print(ctx.error)
		return
	end
	local h = ctx.history
	ns.Print(("%d scored runs, rebuilt %s vs actual %s (%s)"):format(
		h.runs,
		ns.Fmt(h.rebuilt),
		ns.Fmt(h.actual),
		h.exact and "exact" or "MISMATCH"
	))
	local first, last = h.points[1], h.points[#h.points - 1]
	if first and last and first.gain then
		ns.Print(("first scored run %s, latest %s"):format(ns.DateText(first.t, true), ns.DateText(last.t, true)))
	end
	ns.Print(("game season %s, data season %s"):format(
		tostring(C_MythicPlus.GetCurrentSeason()),
		tostring(ns.Data.season.blizzardId)
	))
end

SLASH_TITLELINE1 = "/titleline"
SLASH_TITLELINE2 = "/tline"
SlashCmdList.TITLELINE = function(msg)
	msg = (msg or ""):lower():match("^%s*(.-)%s*$")
	if msg == "chat" then
		CludesUITitleLineDB.chat = not CludesUITitleLineDB.chat
		ns.Print("line distances after each key " .. (CludesUITitleLineDB.chat and "on" or "off"))
	elseif msg:match("^scale") then
		local n = tonumber(msg:match("^scale%s+([%d%.]+)$"))
		if n and n >= 0.7 and n <= 2 then
			CludesUITitleLineDB.scale = n
			ns.Graph:ApplyScale()
			ns.Print(("window scale %.2f"):format(n))
		else
			ns.Print("/titleline scale <0.7 to 2>, e.g. /titleline scale 1.2 (default 1.15)")
		end
	elseif msg == "alerts" then
		CludesUITitleLineDB.alerts = not CludesUITitleLineDB.alerts
		ns.Print("line alerts " .. (CludesUITitleLineDB.alerts and "on" or "off"))
	elseif msg == "debug" then
		PrintDebug()
	elseif msg == "" then
		ns.Graph:Toggle()
	else
		ns.Print("/titleline - graph, chat - the after-key line, alerts - line alerts, scale <n> - window size, debug")
	end
end

function TitleLine_OnAddonCompartmentClick()
	ns.Graph:Toggle()
end

function TitleLine_OnAddonCompartmentEnter(_, button)
	GameTooltip:SetOwner(button, "ANCHOR_LEFT")
	ns.AddTooltipLines(GameTooltip, false)
	GameTooltip:Show()
end

function TitleLine_OnAddonCompartmentLeave()
	GameTooltip:Hide()
end
