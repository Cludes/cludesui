-- TitleLine: your Mythic+ rating against the season's title lines.
--
-- The lines come from Raider.IO and ship in Data.lua, because addons cannot
-- reach the network. Your own rating history is rebuilt from the game's run
-- history, so the graph covers the whole season, not just since install.

local ADDON, mod = ...
if mod.standalone then
    return
end

local DAY = 86400
mod.DAY = DAY

local LINE_SLOPE_DAYS = 7 -- early in a season, before the curve fit has enough points
local FIT_FROM_DAY, FIT_MIN_POINTS = 7, 5 -- the curve ignores the opening week's scramble
local PACE_DAYS = 14 -- how far back your own pace is measured
local STALE_DAYS = 7

-- GetCurrentRegion() ids, per warcraft.wiki.gg/wiki/API_GetCurrentRegion.
mod.REGIONS = { [1] = "us", [2] = "kr", [3] = "eu", [4] = "tw", [5] = "cn" }

-- The tiers are ordered, so they share one hue stepped by lightness, brightest
-- for the most elite; your rating is the only accent. Checked against the dark
-- surface: the ramp passes the ordinal checks and every tier sits at least
-- dE 24 from the accent under colour-blind simulation.
mod.TIERS = {
    { key = "p999", label = "Top 0.1%", short = "0.1%", color = { 0.525, 0.714, 0.937 } }, -- #86b6ef
    { key = "p990", label = "Top 1%", short = "1%", color = { 0.224, 0.529, 0.898 } }, -- #3987e5
}
mod.YOU_COLOR = { 0.788, 0.522, 0 } -- #c98500

-- Surfaces and ink. Text never takes a series colour; a key beside it does.
mod.COLORS = {
    surface = { 0.102, 0.102, 0.098 }, -- #1a1a19
    raised = { 0.141, 0.141, 0.133 }, -- #242422
    ink = { 0.941, 0.937, 0.925 }, -- #f0efec
    ink2 = { 0.765, 0.761, 0.718 }, -- #c3c2b7
    muted = { 0.537, 0.529, 0.506 }, -- #898781
    grid = { 0.173, 0.173, 0.165 }, -- #2c2c2a
    axis = { 0.220, 0.220, 0.208 }, -- #383835
    warn = { 0.980, 0.698, 0.098 }, -- #fab219
}

local DEFAULTS = {
    chat = true,
    alerts = true,
    view = "recent",
    hidden = {},
    seen = {},
    chars = {},
    shared = {},
    alertState = {},
}
local SEEN_CAP = 500 -- groupmates remembered per season

local PREFIX = "|cffffd100TitleLine|r: "
function mod.Print(msg)
    print(PREFIX .. msg)
end

-- Formatting -------------------------------------------------------------------

function mod.Fmt(num)
    local s = tostring(math.floor(num + 0.5))
    local sign = ""
    if s:sub(1, 1) == "-" then
        sign, s = "-", s:sub(2)
    end
    s = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return sign .. (s:gsub("^,", ""))
end

function mod.DateText(t, long)
    local s = date(long and "%a %d %b" or "%d %b", t)
    return (s:gsub(" 0", " "):gsub("^0", ""))
end

function mod.Hex(c)
    return ("|cff%02x%02x%02x"):format(c[1] * 255, c[2] * 255, c[3] * 255)
end

-- A short coloured line, inline in text, to key a series.
function mod.Key(c)
    return ("|TInterface\\Buttons\\WHITE8X8:2:10:0:0:8:8:0:8:0:8:%d:%d:%d|t"):format(
        c[1] * 255,
        c[2] * 255,
        c[3] * 255
    )
end

-- Your rating history ----------------------------------------------------------

-- Run dates are realm time. time() reads a date table as local time, so measure
-- how far the realm clock sits from the local one and correct by that.
local function RealmOffset()
    local nowTime = C_DateAndTime.GetCurrentCalendarTime()
    local asLocal = time({
        year = nowTime.year,
        month = nowTime.month,
        day = nowTime.monthDay,
        hour = nowTime.hour,
        min = nowTime.minute,
    })
    return math.floor((time() - asLocal) / 900 + 0.5) * 900
end

function mod.CalendarToEpoch(d, off)
    return time({ year = d.year, month = d.month, day = d.monthDay, hour = d.hour, min = d.minute })
        + (off or 0)
end

-- The rating is the sum of each dungeon's best run score, so replaying the
-- season's runs in order rebuilds it over time. `exact` says whether the replay
-- lands on the rating the game reports; when it does not, the graph says so.
function mod.Replay(runs, actual, nowTime)
    table.sort(runs, function(lhs, rhs)
        return lhs.t < rhs.t
    end)
    local best, total, points = {}, 0, {}
    for _, run in ipairs(runs) do
        local prev = best[run.map] or 0
        if run.score > prev then
            best[run.map] = run.score
            total = total - prev + run.score
            points[#points + 1] = {
                t = math.min(run.t, nowTime),
                score = total,
                gain = run.score - prev,
                map = run.map,
                level = run.level,
            }
        end
    end
    local exact = math.abs(total - actual) <= 1
    -- Always end on the live rating, so the line reaches today.
    points[#points + 1] = { t = nowTime, score = actual }
    return { points = points, rebuilt = total, actual = actual, exact = exact, runs = #runs }
end

function mod.BuildHistory(nowTime)
    local off = RealmOffset()
    local runs = {}
    for _, r in ipairs(C_MythicPlus.GetRunHistory(true, true, true) or {}) do
        if r.runScore and r.runScore > 0 and r.completionDate then
            runs[#runs + 1] = {
                t = mod.CalendarToEpoch(r.completionDate, off),
                map = r.mapChallengeModeID,
                level = r.level,
                score = r.runScore,
            }
        end
    end
    return mod.Replay(runs, C_ChallengeMode.GetOverallDungeonScore() or 0, nowTime)
end

-- Your rating is a step function: it only moves when a key raises a best.
function mod.ScoreAt(points, t)
    local val = 0
    for _, p in ipairs(points) do
        if p.t > t then
            break
        end
        val = p.score
    end
    return val
end

-- The lines ------------------------------------------------------------------

-- Line points are { time, score }. Returns nil past the last point.
function mod.LineAt(pts, t)
    local num = #pts
    if num == 0 then
        return nil
    end
    if t <= pts[1][1] then
        return pts[1][2]
    end
    for idx = 2, num do
        local a, b = pts[idx - 1], pts[idx]
        if t <= b[1] then
            return a[2] + (b[2] - a[2]) * (t - a[1]) / (b[1] - a[1])
        end
    end
    return nil
end

-- Least-squares rise per day over the last `days` of the series.
function mod.Slope(pts, days)
    local num = #pts
    if num < 2 then
        return 0
    end
    local from = pts[num][1] - days * DAY
    local c, sx, sy, sxx, sxy = 0, 0, 0, 0, 0
    for idx = 1, num do
        local p = pts[idx]
        if p[1] >= from then
            local posX = (p[1] - from) / DAY
            c, sx, sy, sxx, sxy = c + 1, sx + posX, sy + p[2], sxx + posX * posX, sxy + posX * p[2]
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
function mod.Fit(pts, start)
    local c, sx, sy, sxx, sxy = 0, 0, 0, 0, 0
    for _, p in ipairs(pts) do
        local day = (p[1] - start) / DAY
        if day >= FIT_FROM_DAY then
            local posX = math.log(day)
            c, sx, sy, sxx, sxy = c + 1, sx + posX, sy + p[2], sxx + posX * posX, sxy + posX * p[2]
        end
    end
    local d = c * sxx - sx * sx
    if c < FIT_MIN_POINTS or d == 0 then
        return { slope = mod.Slope(pts, LINE_SLOPE_DAYS) }
    end
    return { start = start, b = (c * sxy - sx * sy) / d }
end

-- The line at time t: the data where it exists, its fitted course beyond it.
function mod.LineValue(pts, fit, t)
    local last = pts[#pts]
    if t <= last[1] then
        return mod.LineAt(pts, t)
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
local BAND = {
    { 0, 0 },
    { 7, 16 },
    { 14, 26 },
    { 21, 33 },
    { 28, 43 },
    { 42, 57 },
    { 56, 64 },
    { 84, 94 },
    { 112, 155 },
}

function mod.Band(days)
    if days <= 0 then
        return 0
    end
    for idx = 2, #BAND do
        local a, b = BAND[idx - 1], BAND[idx]
        if days <= b[1] then
            return a[2] + (b[2] - a[2]) * (days - a[1]) / (b[1] - a[1])
        end
    end
    local a, b = BAND[#BAND - 1], BAND[#BAND]
    return b[2] + (b[2] - a[2]) * (days - b[1]) / (b[1] - a[1])
end

-- The line at t with its likely range: low, central, high.
function mod.LineRange(pts, fit, t)
    local val = mod.LineValue(pts, fit, t)
    local band = mod.Band((t - pts[#pts][1]) / DAY)
    return val - band, val, val + band
end

-- Days from now until a straight-line pace meets the line, or nil within a
-- year. The line is a curve, so step a day at a time, then bisect the step.
-- `edge` -1 or +1 aims at the low or high side of the line's range instead.
function mod.Crossing(pts, fit, nowTime, you, pace, edge)
    if pace <= 0 then
        return nil
    end
    local last = pts[#pts][1]
    local function ahead(d)
        local t = nowTime + d * DAY
        local line = mod.LineValue(pts, fit, t)
        if edge then
            line = line + edge * mod.Band((t - last) / DAY)
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
function mod.Summary(regionFrame, history, nowTime, you)
    you = you or history.actual
    local from = math.max(regionFrame.startsAt, nowTime - PACE_DAYS * DAY)
    local window = (nowTime - from) / DAY
    -- A season's rating never falls; floor at zero so the rebuilt history's
    -- decimals against the game's whole-number rating cannot read as a loss.
    local pace = 0
    if window >= 1 then
        pace = math.max(0, (history.actual - mod.ScoreAt(history.points, from)) / window)
    end

    -- The season end: Blizzard's date once announced, until then the last
    -- season's length (Data.lua says which).
    local endsAt = regionFrame.endsAt
    local daysLeft = endsAt and endsAt > nowTime and (endsAt - nowTime) / DAY or nil

    local tiers = {}
    for _, tier in ipairs(mod.TIERS) do
        local pts = regionFrame.lines[tier.key]
        if pts and #pts > 0 then
            local fit = mod.Fit(pts, regionFrame.startsAt)
            local lineNow = mod.LineValue(pts, fit, nowTime)
            local s = { tier = tier, pts = pts, fit = fit, lineNow = lineNow, gap = lineNow - you }
            if s.gap > 0 then
                s.days = mod.Crossing(pts, fit, nowTime, you, pace)
                s.eta = s.days and (nowTime + s.days * DAY)
                s.afterEnd = s.eta and endsAt and s.eta > endsAt
                -- The same crossing against the low and high side of the line's range.
                local early, late =
                    mod.Crossing(pts, fit, nowTime, you, pace, -1),
                    mod.Crossing(pts, fit, nowTime, you, pace, 1)
                s.etaEarly = early and (nowTime + early * DAY)
                s.etaLate = late and (nowTime + late * DAY)
            end
            -- Where the line should finish, and the daily gain that reaches it.
            if daysLeft then
                s.lineEndLow, s.lineEnd, s.lineEndHigh = mod.LineRange(pts, fit, endsAt)
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
        endsEstimated = regionFrame.endsEstimated,
        daysLeft = daysLeft,
    }
end

-- A date span, sharing the month when both ends do: "20-28 Nov".
function mod.SpanText(a, b)
    if date("%m", a) == date("%m", b) then
        return mod.DateText(a):match("^(%d+)") .. "-" .. mod.DateText(b)
    end
    return mod.DateText(a) .. "-" .. mod.DateText(b)
end

-- When you reach the line at your current pace, in a few words: a span from
-- the low to the high side of the line's range where both fall in time.
function mod.EtaText(s, pace, endsAt)
    if s.gap <= 0 then
        return "reached"
    end
    local early = s.etaEarly or s.eta
    if early and endsAt and early > endsAt then
        return "after the season"
    end
    if early and s.etaLate and not (endsAt and s.etaLate > endsAt) then
        if mod.DateText(early) == mod.DateText(s.etaLate) then
            return "ETA " .. mod.DateText(early)
        end
        return "ETA " .. mod.SpanText(early, s.etaLate)
    end
    if early then
        return "ETA from " .. mod.DateText(early)
    end
    return pace and pace > 0 and "over a year" or "not closing"
end

-- Days until a line you are above would catch your straight-line pace, or
-- nil if it does not within `limit` days.
function mod.Overtake(pts, fit, nowTime, you, pace, limit)
    for d = 1, math.floor(limit) do
        if mod.LineValue(pts, fit, nowTime + d * DAY) >= you + pace * d then
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
mod.SCORING_NOTE =
    "Key levels use Raider.IO's scoring: the rating for timing every dungeon at that level, with 15 a level per dungeon and 30 at the levels that add an affix."

function mod.LevelFor(rating)
    local t = mod.Data.levels
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
function mod.Targets(maps, runs, tiers)
    local byMap = {}
    for _, r in ipairs(runs or {}) do
        byMap[r.challengeModeID] = r
    end
    local goals = {}
    for _, tier in ipairs(tiers) do
        local rating = tier.lineEnd or tier.lineNow
        goals[#goals + 1] = {
            tier = tier.tier,
            atEnd = tier.lineEnd ~= nil,
            level = mod.LevelFor(rating),
        }
    end
    local rowList = {}
    for _, map in ipairs(maps) do
        local r = byMap[map]
        local row = { map = map, best = r and r.bestRunLevel or 0, score = r and r.mapScore or 0 }
        row.played = row.score > 0
        row.timed = row.played and r.finishedSuccess
        rowList[#rowList + 1] = row
    end
    table.sort(rowList, function(posX, posY)
        if posX.best ~= posY.best then
            return posX.best < posY.best
        end
        return posX.score < posY.score
    end)
    return goals, rowList
end

-- Guild ---------------------------------------------------------------------------

-- The roster's rating has no season: a member keeps the last one they had,
-- so anyone not online since this season began is showing an old season's.
-- Last online comes as time since (Blizzard's member list prints it as "3
-- days ago"); a member in game now has none.
local IN_GAME = { [1] = true, [4] = true, [5] = true } -- Enum.ClubMemberPresence Online, Away, Busy

function mod.SeenThisSeason(details, seasonDays)
    if details.isSelf then
        return true
    end
    local posY, m, d, hgt =
        details.lastOnlineYear, details.lastOnlineMonth, details.lastOnlineDay, details.lastOnlineHour
    if posY or m or d or hgt then
        return (posY or 0) * 365 + (m or 0) * 30 + (d or 0) + (hgt or 0) / 24 <= seasonDays
    end
    return IN_GAME[details.presence] == true
end

-- Your guild's rated members this season, best first, read from the guild
-- roster the way Blizzard's own member list reads it. During a chat lockdown
-- (combat in instances) those values are secret, so it waits instead.
function mod.Guild(startsAt, nowTime)
    if not IsInGuild() then
        return { state = "none" }
    end
    if C_ChatInfo.InChatMessagingLockdown() then
        return { state = "hidden" }
    end
    local success, members = pcall(function()
        local club = C_Club.GetGuildClubId()
        local ids = club and C_Club.GetClubMembers(club)
        if not ids or #ids == 0 then
            return nil
        end
        local result, stale = {}, 0
        local seasonDays = (nowTime - startsAt) / DAY
        for _, ident in ipairs(ids) do
            local details = C_Club.GetMemberInfo(club, ident)
            local score = details and details.overallDungeonScore
            if score and score > 0 then
                if mod.SeenThisSeason(details, seasonDays) then
                    local class = details.classID and C_CreatureInfo.GetClassInfo(details.classID)
                    result[#result + 1] = {
                        name = details.name,
                        key = mod.Share.Key(details.name),
                        class = class and class.classFile,
                        score = score,
                        isSelf = details.isSelf,
                        online = IN_GAME[details.presence] == true,
                    }
                else
                    stale = stale + 1
                end
            end
        end
        table.sort(result, function(lhs, rhs)
            return lhs.score > rhs.score
        end)
        return { members = result, stale = stale }
    end)
    if not success or not members then
        return { state = "loading" }
    end
    return { state = "ok", members = members.members, stale = members.stale }
end

-- Groupmates -------------------------------------------------------------------

-- The game gives a groupmate's rating only as it is now, with no history. So
-- each one is remembered whenever you are grouped, and over time that builds
-- their own line. A season's rating only rises, so a lower reading is stale.
function mod.Remember(m, nowTime)
    local slug = mod.Data and mod.Data.season.slug
    local e = CludesUITitleLineDB.seen[m.key]
    if not e or e.season ~= slug then
        e = { season = slug, pts = {} }
        CludesUITitleLineDB.seen[m.key] = e
    end
    e.name, e.class, e.last = m.name, m.class, nowTime
    local last = e.pts[#e.pts]
    if not last or m.score > last[2] then
        e.pts[#e.pts + 1] = { nowTime, m.score }
    end
    return e
end

-- Your party as it stands, each with their rating, per-dungeon bests and what
-- has been remembered of them. Raids are skipped: M+ is a five-player party.
function mod.Party(nowTime)
    local result = {}
    if not IsInGroup() or IsInRaid() then
        return result
    end
    for idx = 1, 4 do
        local unitToken = "party" .. idx
        if
            UnitExists(unitToken)
            and UnitIsPlayer(unitToken)
            and not C_Secrets.ShouldUnitIdentityBeSecret(unitToken)
        then
            local name, realm = UnitFullName(unitToken)
            local _, class = UnitClass(unitToken)
            local summary = C_PlayerInfo.GetPlayerMythicPlusRatingSummary(unitToken)
            local m = {
                unit = unitToken,
                name = name,
                key = name and (name .. "-" .. (realm and realm ~= "" and realm or GetNormalizedRealmName())),
                class = class,
                score = summary and summary.currentSeasonScore or 0,
                runs = summary and summary.runs or {},
            }
            if m.key then
                if m.score > 0 then
                    m.seen = mod.Remember(m, nowTime)
                    -- Their dungeons too, for the Guild view to show later.
                    if #m.runs > 0 then
                        local runs = {}
                        for _, r in ipairs(m.runs) do
                            if (r.mapScore or 0) > 0 then
                                runs[#runs + 1] =
                                    { r.challengeModeID, r.bestRunLevel, r.mapScore, r.finishedSuccess }
                            end
                        end
                        m.seen.runs, m.seen.runsAt = runs, nowTime
                    end
                end
                result[#result + 1] = m
            end
        end
    end
    return result
end

function mod.ClassColor(class)
    local color = class and C_ClassColor.GetClassColor(class)
    return color and { color.r, color.g, color.b } or mod.COLORS.ink2
end

-- Your characters -------------------------------------------------------------------

-- Titles are account-wide (last season every character on a winning account
-- got the reward), so the character that counts is your best. Each one's
-- rating, history and dungeon bests are kept whenever you play it, so every
-- character can show the others.
function mod.CharKey()
    local name, realm = UnitFullName("player")
    return name and (name .. "-" .. (realm and realm ~= "" and realm or GetNormalizedRealmName())), name
end

local function SaveChar(context, key, name, history, runs)
    local slug = mod.Data.season.slug
    local old = CludesUITitleLineDB.chars[key]
    if
        history.actual <= 0
        or (old and old.season == slug and old.score == history.actual and #old.points == #history.points)
    then
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
        region = context.regionKey,
        season = slug,
        score = history.actual,
        updated = context.now,
        points = points,
        runs = bests,
    }
end

-- This season's characters in this region, best first.
function mod.Chars(regionKey)
    local slug, result = mod.Data.season.slug, {}
    for key, c in pairs(CludesUITitleLineDB.chars) do
        if c.season == slug and c.region == regionKey and c.score > 0 then
            result[#result + 1] =
                { key = key, name = c.name, class = c.class, score = c.score, updated = c.updated }
        end
    end
    table.sort(result, function(lhs, rhs)
        return lhs.score > rhs.score
    end)
    return result
end

-- A stored character's history and bests, in the shapes the live ones have.
local function StoredChar(key, nowTime)
    local c = CludesUITitleLineDB.chars[key]
    local points = {}
    for _, p in ipairs(c.points) do
        points[#points + 1] = { t = p[1], score = p[2], gain = p[3], map = p[4], level = p[5] }
    end
    -- Flat from when you last played it to today.
    if #points == 0 or points[#points].t < nowTime then
        points[#points + 1] = { t = nowTime, score = c.score }
    end
    local runs = {}
    for _, r in ipairs(c.runs) do
        runs[#runs + 1] =
            { challengeModeID = r[1], bestRunLevel = r[2], mapScore = r[3], finishedSuccess = r[4] }
    end
    return { points = points, actual = c.score, rebuilt = c.score, exact = true }, runs
end

-- Everything the UI needs, or an error to show instead. The subject is your
-- best character unless `opts.subject` is "current", or you chose to view
-- the one you are playing.
function mod.Context(options)
    local nowTime = time()
    local context = { now = nowTime, warnings = {} }
    if not mod.Data then
        context.error = "Cutoff data is missing. Reinstall TitleLine."
        return context
    end
    context.regionKey = mod.REGIONS[GetCurrentRegion()]
    context.region = context.regionKey and mod.Data.regions[context.regionKey]
    if not context.region then
        context.error = "TitleLine has no cutoff data for this region."
        return context
    end

    -- The character you are on, live, and kept for the others to show.
    local live = mod.BuildHistory(nowTime)
    local mine = C_PlayerInfo.GetPlayerMythicPlusRatingSummary("player")
    local liveRuns = mine and mine.runs or {}
    local key, name = mod.CharKey()
    if key then
        SaveChar(context, key, name, live, liveRuns)
    end
    context.chars = mod.Chars(context.regionKey)

    local best = context.chars[1]
    local wanted = (options and options.subject) or CludesUITitleLineDB.showChar or "best"
    local _, class = UnitClass("player")
    if wanted == "best" and best and best.key ~= key and best.score > live.actual then
        context.history, context.myRuns = StoredChar(best.key, nowTime)
        context.subject = { name = best.name, class = best.class, isCurrent = false, isBest = true }
    else
        context.history, context.myRuns = live, liveRuns
        context.subject = {
            name = name,
            class = class,
            isCurrent = true,
            isBest = not best or best.key == key or live.actual >= best.score,
        }
    end
    context.summary = mod.Summary(context.region, context.history, nowTime)
    context.party = mod.Party(nowTime)

    -- Each title line as a key level timed in every dungeon.
    context.maps = C_ChallengeMode.GetMapTable() or {}
    for _, tier in ipairs(context.summary.tiers) do
        tier.levelNow = mod.LevelFor(tier.lineNow)
        tier.levelEnd = tier.lineEnd and mod.LevelFor(tier.lineEnd)
    end

    local age = (nowTime - context.region.updatedAt) / DAY
    if age > STALE_DAYS then
        context.warnings[#context.warnings + 1] = ("The cutoff data is %d days old. Update TitleLine for newer lines."):format(
            math.floor(age)
        )
    end
    if not context.history.exact then
        context.warnings[#context.warnings + 1] = ("Run history adds up to %s, not your %s, so the earlier part of your line is approximate."):format(
            mod.Fmt(context.history.rebuilt),
            mod.Fmt(context.history.actual)
        )
    end
    local gameSeason = C_MythicPlus.GetCurrentSeason()
    local dataSeason = mod.Data.season.blizzardId
    if gameSeason and gameSeason > 0 and dataSeason and gameSeason ~= dataSeason then
        context.warnings[#context.warnings + 1] = ("This data is for %s (season %d) but the game is on season %d. Update TitleLine."):format(
            mod.Data.season.name,
            dataSeason,
            gameSeason
        )
    end
    return context
end

-- Tooltip lines, shared by the Mythic+ tab and the addon compartment.
function mod.AddTooltipLines(tt, spaced)
    local context = mod.Context()
    if spaced then
        tt:AddLine(" ")
    end
    local C = mod.COLORS
    tt:AddLine(
        "TitleLine" .. (context.regionKey and ("  " .. context.regionKey:upper()) or ""),
        C.ink[1],
        C.ink[2],
        C.ink[3]
    )
    if context.error then
        tt:AddLine(context.error, C.ink2[1], C.ink2[2], C.ink2[3], true)
        return
    end
    if not context.subject.isCurrent and context.subject.name then
        tt:AddLine(
            ("For %s, your best character (titles are account-wide)"):format(context.subject.name),
            C.muted[1],
            C.muted[2],
            C.muted[3],
            true
        )
    end
    for _, tier in ipairs(context.summary.tiers) do
        local right = tier.gap > 0 and (mod.Fmt(tier.gap) .. " to go") or "reached"
        tt:AddDoubleLine(
            mod.Key(tier.tier.color) .. " " .. tier.tier.label .. "  |cff898781" .. mod.Fmt(tier.lineNow) .. "|r",
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
local function Alert(textValue, loud, good)
    mod.Print(textValue)
    if loud then
        if RaidWarningUtil then
            RaidWarningUtil.AddMessage("TitleLine: " .. textValue, ChatTypeInfo["RAID_WARNING"])
        end
        PlaySound(good and SOUNDKIT.UI_PERSONAL_LOOT_BANNER or SOUNDKIT.RAID_WARNING)
    end
end

-- Watches your best character against each line: a crossing either way is
-- announced, and once a day a line you are above but on course to pass you
-- before the season ends is a warning.
function mod.CheckAlerts()
    if not CludesUITitleLineDB.alerts then
        return
    end
    local context = mod.Context({ subject = "best" })
    if context.error or context.history.actual <= 0 then
        return
    end
    local sum, who = context.summary, context.subject.name or "you"
    local slot = context.regionKey .. ":" .. mod.Data.season.slug
    local status = CludesUITitleLineDB.alertState[slot] or {}
    CludesUITitleLineDB.alertState[slot] = status
    local today = date("%Y-%m-%d", context.now)
    for _, tier in ipairs(sum.tiers) do
        local key = tier.tier.key
        local above = tier.gap <= 0
        local was = status[key]
        if was == "below" and above then
            Alert(("%s passed the %s line (%s)."):format(who, tier.tier.label, mod.Fmt(tier.lineNow)), true, true)
        elseif was == "above" and not above then
            Alert(
                ("The %s line (%s) passed %s: %s to go."):format(
                    tier.tier.label,
                    mod.Fmt(tier.lineNow),
                    who,
                    mod.Fmt(tier.gap)
                ),
                true,
                false
            )
        end
        status[key] = above and "above" or "below"

        if above and sum.daysLeft and status[key .. ":warned"] ~= today then
            local d = mod.Overtake(tier.pts, tier.fit, context.now, sum.you, sum.pace, sum.daysLeft)
            if d then
                status[key .. ":warned"] = today
                Alert(
                    ("At its pace the %s line passes %s around %s, before the season ends. Staying above takes +%.1f a day."):format(
                        tier.tier.label,
                        who,
                        mod.DateText(context.now + d * DAY),
                        tier.need or 0
                    )
                )
            end
        end
    end
end

local function OnKeyCompleted()
    if not CludesUITitleLineDB.chat then
        return
    end
    local details = C_ChallengeMode.GetChallengeCompletionInfo()
    if not details or details.practiceRun or not details.isEligibleForScore then
        return
    end
    -- Blizzard already prints the rating gained; add only where that leaves
    -- the character that ran the key.
    local context = mod.Context({ subject = "current" })
    if context.error then
        return
    end
    local you = details.newOverallDungeonScore or C_ChallengeMode.GetOverallDungeonScore() or 0
    local parts = {}
    for _, tier in ipairs(mod.Summary(context.region, context.history, context.now, you).tiers) do
        if not CludesUITitleLineDB.hidden[tier.tier.key] then
            local gap = tier.lineNow - you
            parts[#parts + 1] = gap > 0 and (mod.Fmt(gap) .. " to " .. tier.tier.label)
                or (tier.tier.label .. " reached")
        end
    end
    if #parts > 0 then
        mod.Print(table.concat(parts, ", "))
    end
end

-- Drop remembered groupmates from earlier seasons, and the longest-unseen
-- past a cap, so the saved file stays small.
local function PruneSeen()
    local slug = mod.Data and mod.Data.season.slug
    for _, storage in ipairs({ CludesUITitleLineDB.chars, CludesUITitleLineDB.shared }) do
        for key, c in pairs(storage) do
            if c.season ~= slug then
                storage[key] = nil
            end
        end
    end
    local keyList = {}
    for key, entry in pairs(CludesUITitleLineDB.seen) do
        if entry.season ~= slug then
            CludesUITitleLineDB.seen[key] = nil
        else
            keyList[#keyList + 1] = key
        end
    end
    if #keyList > SEEN_CAP then
        table.sort(keyList, function(lhs, rhs)
            return CludesUITitleLineDB.seen[lhs].last > CludesUITitleLineDB.seen[rhs].last
        end)
        for idx = SEEN_CAP + 1, #keyList do
            CludesUITitleLineDB.seen[keyList[idx]] = nil
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
        mod.Party(time())
        if mod.Graph then
            mod.Graph:Refresh()
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
events:SetScript("OnEvent", function(_, evt, arg1)
    if evt == "ADDON_LOADED" and arg1 == ADDON then
        CludesUITitleLineDB = CludesUITitleLineDB or {}
        for k, val in pairs(DEFAULTS) do
            if CludesUITitleLineDB[k] == nil then
                CludesUITitleLineDB[k] = type(val) == "table" and {} or val
            end
        end
        PruneSeen()
    elseif evt == "PLAYER_LOGIN" then
        -- Run history and the rating load from the server on request.
        C_MythicPlus.RequestMapInfo()
        RefreshGroupSoon(5)
        C_Timer.After(12, mod.CheckAlerts)
    elseif evt == "CHALLENGE_MODE_COMPLETED" then
        OnKeyCompleted()
        C_MythicPlus.RequestMapInfo()
        RefreshGroupSoon(15)
        C_Timer.After(20, mod.CheckAlerts)
    elseif evt == "CHALLENGE_MODE_MAPS_UPDATE" then
        if mod.Graph then
            mod.Graph:Refresh()
        end
    elseif evt == "GROUP_ROSTER_UPDATE" then
        RefreshGroupSoon(2)
    elseif evt == "GUILD_ROSTER_UPDATE" or evt == "CLUB_MEMBERS_UPDATED" then
        if CludesUITitleLineDB and CludesUITitleLineDB.view == "guild" then
            RefreshGroupSoon(1)
        end
    end
end)

-- Slash commands and the addon compartment ---------------------------------------

local function PrintDebug()
    local context = mod.Context()
    mod.Print(
        ("region %s, data %s, %s"):format(
            tostring(context.regionKey),
            mod.Data and mod.Data.season.slug or "missing",
            context.region and ("updated " .. mod.DateText(context.region.updatedAt)) or "no region data"
        )
    )
    if context.error then
        mod.Print(context.error)
        return
    end
    local hgt = context.history
    mod.Print(
        ("%d scored runs, rebuilt %s vs actual %s (%s)"):format(
            hgt.runs,
            mod.Fmt(hgt.rebuilt),
            mod.Fmt(hgt.actual),
            hgt.exact and "exact" or "MISMATCH"
        )
    )
    local first, last = hgt.points[1], hgt.points[#hgt.points - 1]
    if first and last and first.gain then
        mod.Print(
            ("first scored run %s, latest %s"):format(mod.DateText(first.t, true), mod.DateText(last.t, true))
        )
    end
    mod.Print(
        ("game season %s, data season %s"):format(
            tostring(C_MythicPlus.GetCurrentSeason()),
            tostring(mod.Data.season.blizzardId)
        )
    )
end

SLASH_TITLELINE1 = "/titleline"
SLASH_TITLELINE2 = "/tline"
SlashCmdList.TITLELINE = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "chat" then
        CludesUITitleLineDB.chat = not CludesUITitleLineDB.chat
        mod.Print("line distances after each key " .. (CludesUITitleLineDB.chat and "on" or "off"))
    elseif msg:match("^scale") then
        local num = tonumber(msg:match("^scale%s+([%d%.]+)$"))
        if num and num >= 0.7 and num <= 2 then
            CludesUITitleLineDB.scale = num
            mod.Graph:ApplyScale()
            mod.Print(("window scale %.2f"):format(num))
        else
            mod.Print("/titleline scale <0.7 to 2>, e.g. /titleline scale 1.2 (default 1.15)")
        end
    elseif msg == "alerts" then
        CludesUITitleLineDB.alerts = not CludesUITitleLineDB.alerts
        mod.Print("line alerts " .. (CludesUITitleLineDB.alerts and "on" or "off"))
    elseif msg == "debug" then
        PrintDebug()
    elseif msg == "" then
        mod.Graph:Toggle()
    else
        mod.Print(
            "/titleline - graph, chat - the after-key line, alerts - line alerts, scale <n> - window size, debug"
        )
    end
end

function TitleLine_OnAddonCompartmentClick()
    mod.Graph:Toggle()
end

function TitleLine_OnAddonCompartmentEnter(_, btnFrame)
    GameTooltip:SetOwner(btnFrame, "ANCHOR_LEFT")
    mod.AddTooltipLines(GameTooltip, false)
    GameTooltip:Show()
end

function TitleLine_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end
