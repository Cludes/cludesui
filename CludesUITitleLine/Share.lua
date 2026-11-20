-- Guildmates' keys. The game gives another player's dungeons only while they
-- are in your group, so this asks their own TitleLine over an addon whisper,
-- and otherwise falls back on what was seen the last time you grouped.

local _, mod = ...
if mod.standalone then
    return
end
local DAY = mod.DAY

local Share = {}
mod.Share = Share

local PREFIX = "TitleLine"
local ASK_WAIT = 15 -- seconds before an unanswered ask counts as no TitleLine
local REPLY_GAP = 10 -- seconds between answers to the same player
local MAX_RUNS = 20

local asked, answered = {}, {}

-- "Name-Realm", the form addon whispers and the stores use.
function Share.Key(name)
    if not name or name == "" then
        return nil
    end
    return name:find("-", 1, true) and name or (name .. "-" .. GetNormalizedRealmName())
end

-- One message: score, class, scored runs this season, then each dungeon's
-- best as "map,level,score,timed,day" (day of the season it was set).
function Share.Encode(score, class, total, bests)
    local parts = {}
    for _, b in ipairs(bests) do
        parts[#parts + 1] = ("%d,%d,%d,%d,%s"):format(
            b.map,
            b.level,
            math.floor(b.score + 0.5),
            b.timed and 1 or 0,
            b.day and tostring(b.day) or ""
        )
    end
    return ("K1|%d|%s|%d|%s"):format(
        math.floor(score + 0.5),
        class or "",
        total or 0,
        table.concat(parts, ";")
    )
end

-- A reply from another player is untrusted: anything out of shape or out of
-- range is dropped rather than shown.
function Share.Decode(textValue)
    local score, class, total, entries = textValue:match("^K1|(%d+)|(%u*)|(%d+)|([%d,;]*)$")
    score, total = tonumber(score), tonumber(total)
    if not score or score > 9999 or not total then
        return nil
    end
    local runs = {}
    for record in entries:gmatch("[^;]+") do
        local map, level, s, timed, day = record:match("^(%d+),(%d+),(%d+),([01]),(%d*)$")
        map, level, s, day = tonumber(map), tonumber(level), tonumber(s), tonumber(day)
        if map and level and level >= 2 and level <= 99 and s and s <= 999 and (not day or day <= 400) then
            runs[#runs + 1] = { map = map, level = level, score = s, timed = timed == "1", day = day }
        end
        if #runs >= MAX_RUNS then
            break
        end
    end
    return { score = score, class = class ~= "" and class or nil, count = total, runs = runs }
end

-- Your current character's keys, for a guildmate who asked.
local function MyKeys()
    local context = mod.Context({ subject = "current" })
    if context.error then
        return nil
    end
    local startsAt = context.region.startsAt
    -- The day each dungeon's best was set: its last step in your history.
    local when = {}
    for _, p in ipairs(context.history.points) do
        if p.map then
            when[p.map] = math.max(0, math.floor((p.t - startsAt) / DAY))
        end
    end
    local bests = {}
    for _, r in ipairs(context.myRuns) do
        if (r.mapScore or 0) > 0 then
            bests[#bests + 1] = {
                map = r.challengeModeID,
                level = r.bestRunLevel,
                score = r.mapScore,
                timed = r.finishedSuccess,
                day = when[r.challengeModeID],
            }
        end
    end
    local _, class = UnitClass("player")
    return Share.Encode(context.history.actual, class, context.history.runs, bests)
end

-- Ask a player's TitleLine for their keys. Not during a chat lockdown, when
-- addon messages are restricted.
function Share.Ask(key)
    if C_ChatInfo.InChatMessagingLockdown() then
        return false
    end
    asked[key] = time()
    C_ChatInfo.SendAddonMessage(PREFIX, "Q1", "WHISPER", key)
    return true
end

-- "asking" while an ask is fresh, "silent" once it has gone unanswered.
function Share.AskState(key)
    local at = asked[key]
    if not at then
        return nil
    end
    return time() - at < ASK_WAIT and "asking" or "silent"
end

function Share.OnMessage(prefixText, textValue, channel, sender)
    if prefixText ~= PREFIX or channel ~= "WHISPER" then
        return
    end
    sender = Share.Key(sender)
    if not sender then
        return
    end
    if textValue == "Q1" then
        local nowTime = time()
        if (answered[sender] or 0) + REPLY_GAP > nowTime or C_ChatInfo.InChatMessagingLockdown() then
            return
        end
        answered[sender] = nowTime
        local reply = MyKeys()
        if reply then
            C_ChatInfo.SendAddonMessage(PREFIX, reply, "WHISPER", sender)
        end
    elseif asked[sender] then
        -- Only answers to an ask are taken; anything unsolicited is ignored.
        local payload = Share.Decode(textValue)
        if payload then
            asked[sender] = nil
            payload.at, payload.season = time(), mod.Data.season.slug
            CludesUITitleLineDB.shared[sender] = payload
            if mod.Views and mod.Views.OnShared then
                mod.Views.OnShared(sender)
            end
        end
    end
end

-- What there is on a player this season: their own TitleLine's answer, else
-- what was seen when you last grouped, else nothing.
function Share.Keys(key)
    local slug = mod.Data.season.slug
    local cfg = CludesUITitleLineDB.shared[key]
    if cfg and cfg.season == slug then
        return cfg, "shared"
    end
    local seen = CludesUITitleLineDB.seen[key]
    if seen and seen.season == slug and seen.runs and #seen.runs > 0 then
        local runs = {}
        for _, r in ipairs(seen.runs) do
            runs[#runs + 1] = { map = r[1], level = r[2], score = r[3], timed = r[4] }
        end
        local last = seen.pts[#seen.pts]
        return { score = last and last[2] or 0, class = seen.class, runs = runs, at = seen.runsAt }, "grouped"
    end
    return nil
end

local events = CreateFrame("Frame")
events:RegisterEvent("CHAT_MSG_ADDON")
events:SetScript("OnEvent", function(_, _, ...)
    Share.OnMessage(...)
end)
C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
