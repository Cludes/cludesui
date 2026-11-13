if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  BossTimeline.lua -- Raid Lead: boss timelines and encounter alerts.
--
--  Every Midnight raid boss's abilities by difficulty, when each comes in the
--  fight and what kind of mechanic it is (raid damage, soak, tankbuster ...),
--  from CludesUIRaidLead_BossData.lua.
--    /cbt              a window to read a boss's timeline before the pull
--    Upcoming bars     during the fight, the next abilities as countdown
--                      bars, coloured by kind; all of them or only the ones
--                      for your role (healers: raid damage and soaks; tanks:
--                      tankbusters and frontals)
--    Encounter alerts  timed calls on the reminder display ("Soak", "Spread",
--                      "Defensives") a few seconds before each mechanic, for
--                      your role, spoken if you like
--  Timings run from the pull. Phases after the first start at their usual
--  time, so later bars are estimates and alerts run for the first phase only.
-------------------------------------------------------------------------------
local _, ns = ...

local DIFFICULTY = { [14] = "Heroic", [15] = "Heroic", [16] = "Mythic", [17] = "Heroic" }
local ALERT_DIFF = { [14] = 15, [15] = 15, [16] = 16, [17] = 15 }
local COLORS = {
    ["raid damage"] = { 0.71, 0.33, 0.32 }, ["raid aoe"] = { 0.71, 0.33, 0.32 },
    ["raid soak"] = { 0.75, 0.34, 0 }, ["group soak"] = { 0.88, 0.47, 0.19 }, ["soak"] = { 0.50, 0, 0.50 },
    ["raid debuff"] = { 0.61, 0.35, 0.71 }, ["healing absorb"] = { 0.91, 0.30, 0.24 },
    ["debuffs"] = { 0.50, 0, 0.50 }, ["debuff"] = { 0.50, 0, 0.50 },
    ["tankbuster"] = { 0.43, 0.60, 0.74 }, ["tank debuff"] = { 0.43, 0.47, 0.74 }, ["singletarget"] = { 1, 0.45, 0.45 },
    ["frontal"] = { 0.46, 0.74, 0.37 }, ["dispel"] = { 0, 0.48, 1 }, ["cc"] = { 1, 1, 1 }, ["interrupt"] = { 0, 0.75, 1 },
    ["damage buff"] = { 1, 0.84, 0 }, ["damage amp"] = { 0.95, 0.77, 0.06 }, ["spread"] = { 0.10, 0.74, 0.61 },
    ["knock"] = { 0, 0.40, 0 }, ["add spawn"] = { 1, 1, 1 }, ["phase change"] = { 1, 1, 1 }, ["event"] = { 1, 1, 1 },
    ["boss immune"] = { 0.58, 0.65, 0.65 }, ["intermission"] = { 0.50, 0.55, 0.55 },
}
local HEALER = { ["raid damage"] = true, ["raid aoe"] = true, ["raid soak"] = true, ["group soak"] = true,
    ["raid debuff"] = true, ["healing absorb"] = true, ["intermission"] = true }
local TANK = { ["tankbuster"] = true, ["tank debuff"] = true, ["frontal"] = true }

local function Settings()
    local p = ns.RaidLeadDB()
    p.timeline = p.timeline or {}
    local s = p.timeline
    if s.bars == nil then s.bars = true end
    if s.alerts == nil then s.alerts = true end
    if s.mine == nil then s.mine = false end
    if s.count == nil then s.count = 6 end
    if s.ahead == nil then s.ahead = 30 end
    if s.tts == nil then s.tts = true end
    return s
end
ns.TimelineSettings = Settings

local data
local function Data()
    if not data then data = ns.BossData(); ns.BossData = nil end
    return data
end

local function Font() return (CludesUI.GetFontPath and CludesUI.GetFontPath()) or STANDARD_TEXT_FONT end
local function Secret(v) return issecretvalue and issecretvalue(v) end
local function Say(text) CludesUI.Print("|cff4cc9f0Raid Lead:|r " .. text) end

local function Keywords(category)
    local list = {}
    for word in (category or ""):gmatch("([^,]+)") do list[#list + 1] = strtrim(word):lower() end
    return list
end

local function Colour(category)
    for _, word in ipairs(Keywords(category)) do
        if COLORS[word] then return COLORS[word] end
    end
    return { 0.7, 0.7, 0.7 }
end

local function MyRole()
    local spec = GetSpecialization and GetSpecialization()
    return spec and GetSpecializationRole(spec) or "DAMAGER", spec and GetSpecializationInfo(spec)
end

local function ForRole(ability, role)
    if ability.important ~= nil then return ability.important end
    local list = role == "HEALER" and HEALER or role == "TANK" and TANK or nil
    if not list then return true end
    for _, word in ipairs(Keywords(ability.category)) do
        if list[word] then return true end
    end
    return false
end

-- Every cast as { at, ability } from the pull, later phases at their usual start.
local function Casts(timeline)
    local starts, maxPhase = {}, 0
    for n, phase in pairs(timeline.phases or {}) do
        starts[n] = phase.start or 0
        if n > maxPhase then maxPhase = n end
    end
    local out = {}
    for _, ability in ipairs(timeline.abilities or {}) do
        local start = starts[ability.phase] or 0
        local nextStart = ability.phase < maxPhase and starts[ability.phase + 1] or nil
        for _, t in ipairs(ability.times) do
            local at = start + t
            if not nextStart or at < nextStart then out[#out + 1] = { at = at, ability = ability } end
        end
    end
    table.sort(out, function(a, b) return a.at < b.at end)
    return out
end

local function Timeline(encID, difficulty)
    local boss = Data().timelines[encID]
    if not boss then return end
    local name = difficulty and DIFFICULTY[difficulty]
    return boss[name or "Mythic"] or boss.Mythic or boss.Heroic, boss[name or "Mythic"] and name or (boss.Mythic and "Mythic" or "Heroic")
end

-------------------------------------------------------------------------------
--  Upcoming bars
-------------------------------------------------------------------------------
local holder, bars = nil, {}
local fight

local function BuildBars()
    if holder then return end
    holder = CreateFrame("Frame", "CludesUIRaidLeadTimeline", UIParent)
    holder:SetSize(260, 20)
    holder:SetFrameStrata("MEDIUM")
    local p = Settings().pos
    if p then holder:SetPoint(p.point or "CENTER", UIParent, p.relPoint or "CENTER", p.x or 0, p.y or 0)
    else holder:SetPoint("LEFT", UIParent, "LEFT", 40, 80) end
end

local function Bar(i)
    local b = bars[i]
    if b then return b end
    b = CreateFrame("StatusBar", nil, holder)
    b:SetSize(230, 18)
    b:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, -(i - 1) * 21)
    b:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetColorTexture(0, 0, 0, 0.6)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(18, 18)
    b.icon:SetPoint("RIGHT", b, "LEFT", -2, 0)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.name = b:CreateFontString(nil, "OVERLAY")
    b.name:SetFont(Font(), 11, "OUTLINE")
    b.name:SetPoint("LEFT", 4, 0)
    b.name:SetPoint("RIGHT", -40, 0)
    b.name:SetJustifyH("LEFT")
    b.name:SetWordWrap(false)
    b.time = b:CreateFontString(nil, "OVERLAY")
    b.time:SetFont(Font(), 11, "OUTLINE")
    b.time:SetPoint("RIGHT", -4, 0)
    bars[i] = b
    return b
end

local function HideBars()
    for _, b in ipairs(bars) do b:Hide() end
end

local function Tick()
    if not fight then return HideBars() end
    local s = Settings()
    local now = GetTime() - fight.pulled
    local n = 0
    for _, cast in ipairs(fight.casts) do
        local left = cast.at - now
        if left > -1 and left <= s.ahead and (not s.mine or ForRole(cast.ability, fight.role)) then
            n = n + 1
            if n > s.count then break end
            local b = Bar(n)
            local c = Colour(cast.ability.category)
            b:SetStatusBarColor(c[1], c[2], c[3], 0.9)
            b:SetMinMaxValues(0, s.ahead)
            b:SetValue(math.max(0, s.ahead - left))
            local icon = C_Spell.GetSpellTexture(cast.ability.spellID)
            b.icon:SetTexture((not Secret(icon) and icon) or 134400)
            b.name:SetText(cast.ability.name .. (cast.ability.phase > 1 and " |cffaaaaaa(P" .. cast.ability.phase .. ")|r" or ""))
            b.time:SetText(left > 0 and ("%.0f"):format(left) or "NOW")
            b:Show()
        end
    end
    for i = n + 1, #bars do bars[i]:Hide() end
    if n == 0 and fight.casts[#fight.casts] and now > fight.casts[#fight.casts].at + 2 then fight.done = true end
end

-------------------------------------------------------------------------------
--  Encounter alerts
-------------------------------------------------------------------------------
local run = 0

local function Loads(alert, role, specID)
    local lc = alert.loadConditions
    if not lc then return true end
    local function Any(t) return t and next(t) ~= nil end
    if Any(lc.Roles) and not lc.Roles[role] then
        local melee, ranged = lc.Roles.MELEE, lc.Roles.RANGED
        if not (melee or ranged) then return false end
    end
    local _, class = UnitClass("player")
    if Any(lc.Classes) and not lc.Classes[class] then return false end
    if Any(lc.SpecIDs) and not (specID and lc.SpecIDs[specID]) then return false end
    if Any(lc.Names) and not lc.Names[(UnitName("player") or ""):lower()] then return false end
    return true
end

local function Condition(alert)
    local cond = alert.isConditional
    if type(cond) ~= "table" or type(cond.func) ~= "string" then return true end
    local fn = loadstring(cond.func)
    local ok, inner = pcall(fn or function() end)
    if not (ok and type(inner) == "function") then return true end
    local ok2, result = pcall(inner)
    return not ok2 or result == true
end

local function StartAlerts(encID, difficulty)
    run = run + 1
    local mine = run
    local s = Settings()
    if not (s.alerts and ns.ShowReminder) then return 0 end
    local diff = ALERT_DIFF[difficulty]
    if not diff then return 0 end
    local role, specID = MyRole()
    local n = 0
    for _, alert in ipairs(Data().alerts) do
        local timers = alert.encID == encID and alert.timers[diff]
        if type(timers) == "table" and (alert.phase or 1) == 1 and Loads(alert, role, specID) then
            local lead = alert.TTSTimer or alert.dur or 5
            for _, t in ipairs(timers) do
                if type(t) == "number" then
                    n = n + 1
                    C_Timer.After(math.max(0, t - lead), function()
                        if run ~= mine or not Condition(alert) then return end
                        local speak = s.tts and (alert.TTS ~= false) and (type(alert.TTS) == "string" and alert.TTS or true) or false
                        ns.ShowReminder(alert.text or alert.name or "?", t - (GetTime() - fight.pulled), speak, false)
                    end)
                end
            end
        end
    end
    return n
end

-------------------------------------------------------------------------------
--  Fight start and end
-------------------------------------------------------------------------------
local ticker
local function Stop()
    fight = nil
    run = run + 1
    if ticker then ticker:Cancel(); ticker = nil end
    HideBars()
end

function ns.StartTimeline(encID, difficulty)
    Stop()
    local timeline = Timeline(encID, difficulty)
    if not timeline then return false end
    fight = { encID = encID, pulled = GetTime(), casts = Casts(timeline), role = (MyRole()) }
    if Settings().bars then
        BuildBars()
        ticker = C_Timer.NewTicker(0.1, Tick)
    end
    StartAlerts(encID, difficulty)
    return true
end
ns.StopTimeline = Stop

local events = CreateFrame("Frame")
events:RegisterEvent("ENCOUNTER_START")
events:RegisterEvent("ENCOUNTER_END")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", function(_, event, encID, _, difficulty)
    if event ~= "ENCOUNTER_START" then return Stop() end
    if Secret(encID) or Secret(difficulty) then return end
    local s = Settings()
    if s.bars or s.alerts then ns.StartTimeline(encID, difficulty) end
end)

-------------------------------------------------------------------------------
--  The timeline window (/cbt)
-------------------------------------------------------------------------------
local win, content, rows = nil, nil, {}
local shownBoss, shownDiff

local function Time(sec) return ("%d:%02d"):format(math.floor(sec / 60), math.floor(sec % 60)) end

local function Row(i)
    local r = rows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, content)
    r:SetSize(560, 20)
    r.swatch = r:CreateTexture(nil, "ARTWORK")
    r.swatch:SetSize(4, 18)
    r.swatch:SetPoint("LEFT", 0, 0)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(18, 18)
    r.icon:SetPoint("LEFT", 8, 0)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.text = r:CreateFontString(nil, "OVERLAY")
    r.text:SetFont(Font(), 12, "")
    r.text:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 6, 0)
    r.text:SetWidth(530)
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(true)
    rows[i] = r
    return r
end

local function Draw()
    if not (win and win:IsShown()) then return end
    for _, r in ipairs(rows) do r:Hide() end
    local timeline, diffName = Timeline(shownBoss, shownDiff == "Heroic" and 15 or 16)
    win.boss:SetText((Data().names[shownBoss] or ("Encounter " .. shownBoss)) .. "  |cff9aa6b2" .. (diffName or "") .. "|r")
    if not timeline then content:SetHeight(10) return end
    local y, n = 0, 0
    local mine = Settings().mine
    local role = MyRole()
    local list = {}
    for _, a in ipairs(timeline.abilities) do
        if not mine or ForRole(a, role) then list[#list + 1] = a end
    end
    table.sort(list, function(a, b)
        if a.phase ~= b.phase then return a.phase < b.phase end
        return (a.times[1] or 0) < (b.times[1] or 0)
    end)
    local lastPhase
    for _, a in ipairs(list) do
        if a.phase ~= lastPhase then
            lastPhase = a.phase
            n = n + 1
            local r = Row(n)
            r.swatch:Hide(); r.icon:Hide()
            local phase = timeline.phases[a.phase]
            r.text:SetText(("|cffffd100Phase %s|r  |cff9aa6b2from %s%s|r"):format(a.phase, Time(phase and phase.start or 0),
                phase and phase.name and ("  " .. phase.name) or ""))
            r:SetHeight(20)
            r:ClearAllPoints(); r:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
            r:Show()
            y = y + 22
        end
        n = n + 1
        local r = Row(n)
        local c = Colour(a.category)
        r.swatch:SetColorTexture(c[1], c[2], c[3], 1); r.swatch:Show()
        local icon = C_Spell.GetSpellTexture(a.spellID)
        r.icon:SetTexture((not Secret(icon) and icon) or 134400); r.icon:Show()
        local times = {}
        local start = timeline.phases[a.phase] and timeline.phases[a.phase].start or 0
        for i, t in ipairs(a.times) do
            if i > 24 then times[#times + 1] = "..." break end
            times[#times + 1] = Time(start + t)
        end
        r.text:SetText(("%s  |cff9aa6b2%s%s|r\n|cffcccccc%s|r"):format(a.name, a.category or "",
            (a.duration or 0) > 0 and (", " .. a.duration .. "s") or "", table.concat(times, "  ")))
        local h = r.text:GetStringHeight() + 6
        r:SetHeight(math.max(22, h))
        r:ClearAllPoints(); r:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        r:Show()
        y = y + math.max(22, h) + 2
    end
    content:SetHeight(y + 10)
end

local function BuildWindow()
    win = CreateFrame("Frame", "CludesUIBossTimeline", UIParent, "BackdropTemplate")
    win:SetSize(620, 520)
    win:SetPoint("CENTER", 0, 30)
    win:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    win:SetBackdropColor(0.06, 0.07, 0.09, 0.96)
    win:SetBackdropBorderColor(0.30, 0.79, 0.94, 0.8)
    win:SetMovable(true); win:EnableMouse(true); win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    win:SetFrameStrata("HIGH")
    win:SetClampedToScreen(true)
    local title = win:CreateFontString(nil, "OVERLAY")
    title:SetFont(Font(), 15, "OUTLINE")
    title:SetPoint("TOPLEFT", 10, -8)
    title:SetText("|cff4cc9f0Boss Timeline|r")
    local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    local pick = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    pick:SetSize(220, 22)
    pick:SetPoint("TOPLEFT", 10, -32)
    pick:SetText("Pick a boss")
    pick:SetScript("OnClick", function(self)
        MenuUtil.CreateContextMenu(self, function(_, root)
            local seen = {}
            local ids = {}
            for _, id in ipairs(Data().order or {}) do ids[#ids + 1] = id; seen[id] = true end
            local rest = {}
            for id in pairs(Data().timelines) do if not seen[id] then rest[#rest + 1] = id end end
            table.sort(rest)
            root:CreateTitle("Current raid")
            for _, id in ipairs(ids) do
                if Data().timelines[id] then root:CreateButton(Data().names[id] or tostring(id), function() shownBoss = id; Draw() end) end
            end
            root:CreateTitle("Earlier")
            for _, id in ipairs(rest) do root:CreateButton(Data().names[id] or tostring(id), function() shownBoss = id; Draw() end) end
        end)
    end)
    local diff = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    diff:SetSize(90, 22)
    diff:SetPoint("LEFT", pick, "RIGHT", 6, 0)
    diff:SetText("Mythic")
    diff:SetScript("OnClick", function(self)
        shownDiff = shownDiff == "Heroic" and "Mythic" or "Heroic"
        self:SetText(shownDiff)
        Draw()
    end)
    local test = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    test:SetSize(90, 22)
    test:SetPoint("LEFT", diff, "RIGHT", 6, 0)
    test:SetText("Test")
    test:SetScript("OnClick", function()
        if ns.StartTimeline(shownBoss, shownDiff == "Heroic" and 15 or 16) then Say("running this timeline as if pulled now. /cbt stop ends it.") end
    end)
    win.boss = win:CreateFontString(nil, "OVERLAY")
    win.boss:SetFont(Font(), 13, "OUTLINE")
    win.boss:SetPoint("TOPLEFT", 10, -62)
    local scroll = CreateFrame("ScrollFrame", nil, win, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 10, -84)
    scroll:SetPoint("BOTTOMRIGHT", -30, 10)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(570, 10)
    scroll:SetScrollChild(content)
    win:Hide()
    tinsert(UISpecialFrames, "CludesUIBossTimeline")
end

function ns.OpenTimeline()
    if not win then BuildWindow() end
    shownBoss = shownBoss or (Data().order and Data().order[1]) or next(Data().timelines)
    shownDiff = shownDiff or "Mythic"
    win:Show()
    Draw()
end

SLASH_CUIBOSSTIMELINE1 = "/cbt"
SlashCmdList.CUIBOSSTIMELINE = function(msg)
    if (msg or ""):lower():find("stop") then Stop(); if ns.StopReminders then ns.StopReminders() end return end
    if win and win:IsShown() then win:Hide() else ns.OpenTimeline() end
end

-------------------------------------------------------------------------------
--  Layout Mode
-------------------------------------------------------------------------------
local registered = false
local reg = CreateFrame("Frame")
reg:RegisterEvent("PLAYER_ENTERING_WORLD")
reg:SetScript("OnEvent", function()
    if registered or not (CludesUI.RegisterUnlockElements and CludesUI.MakeUnlockElement) then return end
    registered = true
    BuildBars()
    CludesUI:RegisterUnlockElements({
        CludesUI.MakeUnlockElement({
            key = "RLEAD_Timeline", label = "Boss Timeline Bars", group = "Raid Lead", order = 661,
            noAnchorTarget = true, noResize = true,
            isHidden = function() return not Settings().bars end,
            getFrame = function() BuildBars(); return holder end,
            getSize = function() return 260, 21 * Settings().count end,
            savePos = function(_, point, relPoint, x, y) Settings().pos = { point = point, relPoint = relPoint, x = x, y = y } end,
            loadPos = function() return Settings().pos end,
            clearPos = function() Settings().pos = nil end,
            applyPos = function()
                if not holder or InCombatLockdown() then return end
                holder:ClearAllPoints()
                local p = Settings().pos
                if p then holder:SetPoint(p.point or "CENTER", UIParent, p.relPoint or "CENTER", p.x or 0, p.y or 0)
                else holder:SetPoint("LEFT", UIParent, "LEFT", 40, 80) end
            end,
        }),
    }, "CludesUIRaidLead")
end)
