if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
if not (CUI and CUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_BossKills.lua  (WoW Forever only)
--  Boss Kill History: each Dungeon Journal boss this character has killed,
--  how many times, when, how long each fight took and who was with you. The
--  Journal and the Dungeon Map show it under each boss; a fight faster than
--  your best says so in chat. Kept per character, the last ten kills of each
--  boss (the count and best time cover every kill).
--    CludesUIDB.bossKills.chars[name-realm][encounterID] =
--      { n, first, best, bestAt, at = {}, took = {}, team = {} }
-------------------------------------------------------------------------------
local _, module = ...

local F = module.Feature("bossKills", { enabled = true })
local Get, Enabled, Cfg = F.Get, F.Enabled, F.Cfg
local J = module.Journal

local KEEP = 10
local DAY = 86400
local events = CreateFrame("Frame")
local pulled = {} -- encounterID -> GetTime() at the pull
local byEncounter

local function Secret(value)
    return issecretvalue and issecretvalue(value)
end

local function CharKey() return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?") end

local function Mine(create)
    local root = create and Cfg() or F.Read()
    local chars = root.chars
    if not chars then
        if not create then return nil end
        chars = {}
        root.chars = chars
    end
    local key = CharKey()
    if not chars[key] and create then chars[key] = {} end
    return chars[key]
end

local function Index()
    byEncounter = {}
    for _, dungeon in ipairs(J and J.dungeons or {}) do
        for _, wing in ipairs(dungeon.wings or {}) do
            for _, boss in ipairs(wing.bosses or {}) do
                for _, id in ipairs(boss.encounters or {}) do
                    byEncounter[id] = byEncounter[id] or boss
                end
            end
        end
    end
end

local function BossFor(encounterID)
    if not byEncounter then Index() end
    return byEncounter[encounterID]
end

local function Log(boss)
    local id = boss and boss.encounters and boss.encounters[1]
    local mine = id and Mine(false)
    local log = mine and mine[id]
    if type(log) == "table" and type(log.n) == "number" then return log end
end

local function Length(seconds)
    return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

local function Ago(at)
    local days = math.floor((time() - at) / DAY)
    if days <= 0 then return "today" end
    if days == 1 then return "yesterday" end
    return ("%d days ago"):format(days)
end

local function Team()
    local names = {}
    for i = 1, 4 do
        local name = UnitName("party" .. i)
        if name and not Secret(name) then names[#names + 1] = name end
    end
    return #names > 0 and table.concat(names, ", ") or false
end

local function Append(boss, took)
    local mine = Mine(true)
    if not mine then return end
    local key = boss.encounters[1]
    local now = time()
    local log = mine[key]
    if type(log) ~= "table" then
        log = { n = 0, first = now, at = {}, took = {}, team = {} }
        mine[key] = log
    end
    local length = took and math.floor(took + 0.5) or nil
    if length and (not log.best or length < log.best) then
        if log.best then
            CUI.Print(("|cff4cc9f0Boss Kills:|r new best on %s: %s, was %s."):format(boss.name, Length(length), Length(log.best)))
        end
        log.best, log.bestAt = length, now
    end
    if #log.at >= KEEP then
        table.remove(log.at, 1)
        table.remove(log.took, 1)
        table.remove(log.team, 1)
    end
    log.n = log.n + 1
    log.at[#log.at + 1] = now
    log.took[#log.took + 1] = length or false
    log.team[#log.team + 1] = Team()
end

-- One line for a boss: "Killed 3 times, last today, best 1:42", or nil.
local function Summary(boss)
    if not Enabled() then return nil end
    local log = Log(boss)
    if not log or log.n == 0 then return nil end
    local parts = { log.n == 1 and "Killed once" or ("Killed %d times"):format(log.n) }
    local last = log.at[#log.at]
    if last then parts[#parts + 1] = "last " .. Ago(last) end
    if log.best then parts[#parts + 1] = "best " .. Length(log.best) end
    return table.concat(parts, ", ")
end

-- Up to three latest kills, newest first: { "2 days ago, 1:42, with A, B", ... }.
local function Recent(boss, most)
    local log = Enabled() and Log(boss)
    if not log then return {} end
    local out = {}
    for i = #log.at, math.max(1, #log.at - (most or 3) + 1), -1 do
        local line = Ago(log.at[i])
        if log.took[i] then line = line .. ", " .. Length(log.took[i]) end
        if log.team[i] then line = line .. ", with " .. log.team[i] end
        out[#out + 1] = line
    end
    return out
end

-- Adds the summary and the latest kills to an open GameTooltip.
local function AppendToTooltip(tooltip, boss)
    local line = Summary(boss)
    if not line then return end
    tooltip:AddLine(line, 0.4, 0.9, 0.5)
    for _, kill in ipairs(Recent(boss, 3)) do
        tooltip:AddLine(kill, 0.6, 0.6, 0.6, true)
    end
end

events:SetScript("OnEvent", function(_, event, encounterID, _, _, _, success)
    if Secret(encounterID) or Secret(success) then return end
    if event == "ENCOUNTER_START" then
        pulled[encounterID] = GetTime()
        return
    end
    local started = pulled[encounterID]
    pulled[encounterID] = nil
    local boss = success == 1 and BossFor(encounterID)
    if boss then Append(boss, started and GetTime() - started) end
end)

local function Apply()
    if Enabled() then
        events:RegisterEvent("ENCOUNTER_START")
        events:RegisterEvent("ENCOUNTER_END")
    else
        events:UnregisterAllEvents()
        wipe(pulled)
    end
end

local function Forget()
    local mine = Mine(false)
    if mine then wipe(mine) end
end

-- How many times this character has killed the boss.
local function Total(boss)
    local log = Log(boss)
    return log and log.n or 0
end

module.BossKills = { Summary = Summary, Recent = Recent, AddToTooltip = AppendToTooltip, Count = Total }
CUI._BossKills = {
    Get = Get,
    Cfg = Cfg,
    Apply = Apply,
    Forget = Forget,
    Summary = Summary,
    Recent = Recent,
}

F.Start(Apply)
