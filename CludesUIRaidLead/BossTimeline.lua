if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
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
--  Phase changes are read from the boss's timeline (BossPhases.lua): each
--  phase's bars and alerts run from when it really began. Bosses with no
--  phase rule, and phases not reached yet, run at their usual time.
-------------------------------------------------------------------------------
local _, mod = ...

local DIFFICULTY = { [14] = "Heroic", [15] = "Heroic", [16] = "Mythic", [17] = "Heroic" }
local ALERT_DIFF = { [14] = 15, [15] = 15, [16] = 16, [17] = 15 }
local COLORS = {
    ["raid damage"] = { 0.71, 0.33, 0.32 },
    ["raid aoe"] = { 0.71, 0.33, 0.32 },
    ["raid soak"] = { 0.75, 0.34, 0 },
    ["group soak"] = { 0.88, 0.47, 0.19 },
    ["soak"] = { 0.50, 0, 0.50 },
    ["raid debuff"] = { 0.61, 0.35, 0.71 },
    ["healing absorb"] = { 0.91, 0.30, 0.24 },
    ["debuffs"] = { 0.50, 0, 0.50 },
    ["debuff"] = { 0.50, 0, 0.50 },
    ["tankbuster"] = { 0.43, 0.60, 0.74 },
    ["tank debuff"] = { 0.43, 0.47, 0.74 },
    ["singletarget"] = { 1, 0.45, 0.45 },
    ["frontal"] = { 0.46, 0.74, 0.37 },
    ["dispel"] = { 0, 0.48, 1 },
    ["cc"] = { 1, 1, 1 },
    ["interrupt"] = { 0, 0.75, 1 },
    ["damage buff"] = { 1, 0.84, 0 },
    ["damage amp"] = { 0.95, 0.77, 0.06 },
    ["spread"] = { 0.10, 0.74, 0.61 },
    ["knock"] = { 0, 0.40, 0 },
    ["add spawn"] = { 1, 1, 1 },
    ["phase change"] = { 1, 1, 1 },
    ["event"] = { 1, 1, 1 },
    ["boss immune"] = { 0.58, 0.65, 0.65 },
    ["intermission"] = { 0.50, 0.55, 0.55 },
}
local HEALER = {
    ["raid damage"] = true,
    ["raid aoe"] = true,
    ["raid soak"] = true,
    ["group soak"] = true,
    ["raid debuff"] = true,
    ["healing absorb"] = true,
    ["intermission"] = true,
}
local TANK = { ["tankbuster"] = true, ["tank debuff"] = true, ["frontal"] = true }

local function Settings()
    local p = mod.RaidLeadDB()
    p.timeline = p.timeline or {}
    local cfg = p.timeline
    if cfg.bars == nil then
        cfg.bars = true
    end
    if cfg.alerts == nil then
        cfg.alerts = true
    end
    if cfg.mine == nil then
        cfg.mine = false
    end
    if cfg.count == nil then
        cfg.count = 6
    end
    if cfg.ahead == nil then
        cfg.ahead = 30
    end
    if cfg.tts == nil then
        cfg.tts = true
    end
    if cfg.phaseChat == nil then
        cfg.phaseChat = false
    end
    return cfg
end
mod.TimelineSettings = Settings

local payload
local function Data()
    if not payload then
        payload = mod.BossData()
        mod.BossData = nil
    end
    return payload
end

local function Font()
    return CludesUI.GetFontPath(nil)
end
local function Secret(val)
    return issecretvalue and issecretvalue(val)
end
local function Say(textValue)
    CludesUI.Print("|cff4cc9f0Raid Lead:|r " .. textValue)
end

local function Keywords(category)
    local entries = {}
    for word in (category or ""):gmatch("([^,]+)") do
        entries[#entries + 1] = strtrim(word):lower()
    end
    return entries
end

local function Colour(category)
    for _, word in ipairs(Keywords(category)) do
        if COLORS[word] then
            return COLORS[word]
        end
    end
    return { 0.7, 0.7, 0.7 }
end

local function MyRole()
    local specInfo = GetSpecialization and GetSpecialization()
    return specInfo and GetSpecializationRole(specInfo) or "DAMAGER",
        specInfo and GetSpecializationInfo(specInfo)
end

local function ForRole(ability, role)
    if ability.important ~= nil then
        return ability.important
    end
    local entries = role == "HEALER" and HEALER or role == "TANK" and TANK or nil
    if not entries then
        return true
    end
    for _, word in ipairs(Keywords(ability.category)) do
        if entries[word] then
            return true
        end
    end
    return false
end

local function Timeline(encID, difficulty)
    local boss = Data().timelines[encID]
    if not boss then
        return
    end
    local name = difficulty and DIFFICULTY[difficulty]
    return boss[name or "Mythic"] or boss.Mythic or boss.Heroic,
        boss[name or "Mythic"] and name or (boss.Mythic and "Mythic" or "Heroic")
end

-- Every cast still to come, as { due (GetTime), ability }: the phase you are in
-- from when it really began, later phases at their usual distance from it.
local function Casts(f)
    local timeline = f.timeline
    local defaultSet, keyList = {}, {}
    for num, phase in pairs(timeline.phases or {}) do
        defaultSet[num] = phase.start or 0
        keyList[#keyList + 1] = num
    end
    table.sort(keyList)
    local current = f.Phase
    local curStart = f.phaseAt[current] or f.pulled
    local curDefault = defaultSet[current]
    if not curDefault then
        -- A phase the timeline has no row for (1.5, 2.5): its abilities follow the
        -- last listed phase before it.
        for _, num in ipairs(keyList) do
            if num <= current then
                curDefault = defaultSet[num]
            end
        end
        curDefault = curDefault or 0
    end
    local out = {}
    for _, ability in ipairs(timeline.abilities or {}) do
        local p = ability.phase
        if p >= current or (defaultSet[current] == nil and p == math.floor(current)) then
            local start
            if f.phaseAt[p] then
                start = f.phaseAt[p]
            elseif defaultSet[p] then
                start = curStart + (defaultSet[p] - curDefault)
            end
            if start then
                local nextStart
                for _, num in ipairs(keyList) do
                    if num > p then
                        nextStart = defaultSet[num] - defaultSet[p] + start
                        break
                    end
                end
                for _, t in ipairs(ability.times) do
                    local due = start + t
                    if not nextStart or due < nextStart then
                        out[#out + 1] = { due = due, ability = ability, guess = p > current }
                    end
                end
            end
        end
    end
    table.sort(out, function(lhs, rhs)
        return lhs.due < rhs.due
    end)
    return out
end

-------------------------------------------------------------------------------
--  Upcoming bars
-------------------------------------------------------------------------------
local holderFrame, barList = nil, {}
local fight

local function BuildBars()
    if holderFrame then
        return
    end
    holderFrame = CreateFrame("Frame", "CludesUIRaidLeadTimeline", UIParent)
    holderFrame:SetSize(260, 20)
    holderFrame:SetFrameStrata("MEDIUM")
    local p = Settings().pos
    if p then
        holderFrame:SetPoint(p.point or "CENTER", UIParent, p.relPoint or "CENTER", p.x or 0, p.y or 0)
    else
        holderFrame:SetPoint("LEFT", UIParent, "LEFT", 40, 80)
    end
end

local function Bar(idx)
    local widget = barList[idx]
    if widget then
        return widget
    end
    widget = CreateFrame("StatusBar", nil, holderFrame)
    widget:SetSize(230, 18)
    widget:SetPoint("TOPRIGHT", holderFrame, "TOPRIGHT", 0, -(idx - 1) * 21)
    widget:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    widget.bg = widget:CreateTexture(nil, "BACKGROUND")
    widget.bg:SetAllPoints()
    widget.bg:SetColorTexture(0, 0, 0, 0.6)
    widget.icon = widget:CreateTexture(nil, "ARTWORK")
    widget.icon:SetSize(18, 18)
    widget.icon:SetPoint("RIGHT", widget, "LEFT", -2, 0)
    widget.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    widget.name = widget:CreateFontString(nil, "OVERLAY")
    CludesUI.Kit.Font(widget.name, 11, nil)
    widget.name:SetPoint("LEFT", 4, 0)
    widget.name:SetPoint("RIGHT", -40, 0)
    widget.name:SetJustifyH("LEFT")
    widget.name:SetWordWrap(false)
    widget.time = widget:CreateFontString(nil, "OVERLAY")
    CludesUI.Kit.Font(widget.time, 11, nil)
    widget.time:SetPoint("RIGHT", -4, 0)
    barList[idx] = widget
    return widget
end

local function HideBars()
    for _, bar in ipairs(barList) do
        bar:Hide()
    end
end

local function Tick()
    if not fight then
        return HideBars()
    end
    local cfg = Settings()
    local nowTime = GetTime()
    local num = 0
    for _, cast in ipairs(fight.casts) do
        local leftX = cast.due - nowTime
        if leftX > -1 and leftX <= cfg.ahead and (not cfg.mine or ForRole(cast.ability, fight.role)) then
            num = num + 1
            if num > cfg.count then
                break
            end
            local widget = Bar(num)
            local c = Colour(cast.ability.category)
            widget:SetStatusBarColor(c[1], c[2], c[3], cast.guess and 0.5 or 0.9)
            widget:SetMinMaxValues(0, cfg.ahead)
            widget:SetValue(math.max(0, cfg.ahead - leftX))
            local icon = C_Spell.GetSpellTexture(cast.ability.spellID)
            widget.icon:SetTexture((not Secret(icon) and icon) or 134400)
            widget.name:SetText(
                cast.ability.name
                    .. (cast.guess and (" |cffaaaaaa(P" .. cast.ability.phase .. ", est.)|r") or "")
            )
            widget.time:SetText(leftX > 0 and ("%.0f"):format(leftX) or "NOW")
            widget:Show()
        end
    end
    for idx = num + 1, #barList do
        barList[idx]:Hide()
    end
end

-------------------------------------------------------------------------------
--  Encounter alerts
-------------------------------------------------------------------------------
local run = 0

local function Loads(alert, role, specID)
    local lc = alert.loadConditions
    if not lc then
        return true
    end
    local function Any(t)
        return t and next(t) ~= nil
    end
    if Any(lc.Roles) and not lc.Roles[role] then
        local melee, ranged = lc.Roles.MELEE, lc.Roles.RANGED
        if not (melee or ranged) then
            return false
        end
    end
    local _, class = UnitClass("player")
    if Any(lc.Classes) and not lc.Classes[class] then
        return false
    end
    if Any(lc.SpecIDs) and not (specID and lc.SpecIDs[specID]) then
        return false
    end
    if Any(lc.Names) and not lc.Names[(UnitName("player") or ""):lower()] then
        return false
    end
    return true
end

local function Condition(alert)
    local cond = alert.isConditional
    if type(cond) ~= "table" or type(cond.func) ~= "string" then
        return true
    end
    local fn = loadstring(cond.func)
    local success, inner = pcall(fn or function() end)
    if not (success and type(inner) == "function") then
        return true
    end
    local ok2, result = pcall(inner)
    return not ok2 or result == true
end

-- The phase's alerts, timed from when the phase began (start, a GetTime).
local function StartAlerts(f, phase, start)
    run = run + 1
    local mine = run
    local cfg = Settings()
    if not (cfg.alerts and mod.ShowReminder) then
        return 0
    end
    local diff = ALERT_DIFF[f.difficulty]
    if not diff then
        return 0
    end
    local role, specID = MyRole()
    local num = 0
    local nowTime = GetTime()
    for _, alert in ipairs(Data().alerts) do
        local byPhase = alert.encID == f.encID and alert.phases[diff]
        local times = byPhase and byPhase[phase]
        if type(times) == "table" and Loads(alert, role, specID) then
            local lead = alert.TTSTimer or alert.dur or 5
            for _, t in ipairs(times) do
                local due = start + t
                if type(t) == "number" and due > nowTime then
                    num = num + 1
                    C_Timer.After(math.max(0, due - lead - nowTime), function()
                        if run ~= mine or fight ~= f or not Condition(alert) then
                            return
                        end
                        local speak = cfg.tts
                                and (alert.TTS ~= false)
                                and (type(alert.TTS) == "string" and alert.TTS or true)
                            or false
                        mod.ShowReminder(alert.text or alert.name or "?", due - GetTime(), speak, false)
                    end)
                end
            end
        end
    end
    return num
end

-------------------------------------------------------------------------------
--  The fight: what the phase rules (BossPhases.lua) read and call
-------------------------------------------------------------------------------
local Fight = {}
Fight.__index = Fight

function Fight:DifficultyCheck(entries)
    local diff = self.testDifficulty or select(3, GetInstanceInfo()) or 0
    if diff == 233 then
        diff = 16
    end
    return tContains(entries, diff) and diff or nil
end

function Fight:StartReminders(phase)
    self.phaseAt[phase] = GetTime()
    self.casts = Casts(self)
    StartAlerts(self, phase, self.phaseAt[phase])
    if Settings().phaseChat then
        Say(("phase %s."):format(phase))
    end
end

-- The phase began late by `delay` seconds: everything still to come moves.
function Fight:DelayAllReminders(delay)
    local phase = self.Phase
    self.phaseAt[phase] = (self.phaseAt[phase] or GetTime()) + delay
    self.casts = Casts(self)
    StartAlerts(self, phase, self.phaseAt[phase])
end

function Fight:EncounterRegister(name, evt, enable, units)
    self.frames[name] = self.frames[name] or CreateFrame("Frame")
    local widget = self.frames[name]
    if type(evt) == "table" then
        for _, event in ipairs(evt) do
            self:EncounterRegister(name, event, enable, units)
        end
        return
    end
    if enable then
        if type(units) == "table" then
            widget:RegisterUnitEvent(evt, units[1], units[2], units[3], units[4])
        elseif units then
            widget:RegisterUnitEvent(evt, units)
        else
            widget:RegisterEvent(evt)
        end
    elseif evt then
        widget:UnregisterEvent(evt)
    end
end

function Fight:EncounterFunction(name, fn)
    self.frames[name] = self.frames[name] or CreateFrame("Frame")
    self.frames[name]:SetScript("OnEvent", function(...)
        if fight == self then
            fn(...)
        end
    end)
end

function Fight:GetActiveEncounterTimelineEventCount()
    if not (C_EncounterTimeline and C_EncounterTimeline.GetEventList) then
        return 0
    end
    local total = 0
    for _, eventID in ipairs(C_EncounterTimeline.GetEventList()) do
        local details = C_EncounterTimeline.GetEventInfo(eventID)
        if
            details
            and details.source == Enum.EncounterTimelineEventSource.Encounter
            and C_EncounterTimeline.GetEventState(eventID) == Enum.EncounterTimelineEventState.Active
        then
            total = total + 1
        end
    end
    return total
end

-------------------------------------------------------------------------------
--  Fight start and end
-------------------------------------------------------------------------------
local ticker
local timelineEvents = CreateFrame("Frame")
local custom = {}

local function Stop()
    if fight then
        for _, widget in pairs(fight.frames) do
            widget:UnregisterAllEvents()
        end
        if fight.VaelgorPhaseTimer then
            fight.VaelgorPhaseTimer:Cancel()
        end
    end
    fight = nil
    run = run + 1
    wipe(custom)
    timelineEvents:UnregisterAllEvents()
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
    HideBars()
end

-- testDifficulty: run it as that difficulty, whatever instance you are in (/cbt Test).
function mod.StartTimeline(encID, difficulty, testDifficulty)
    Stop()
    local timeline = Timeline(encID, difficulty)
    if not timeline then
        return false
    end
    local nowTime = GetTime()
    local f = setmetatable({
        encID = encID,
        EncounterID = encID,
        difficulty = difficulty,
        testDifficulty = testDifficulty,
        timeline = timeline,
        pulled = nowTime,
        Phase = 1,
        PhaseSwapTime = nowTime,
        phaseAt = { [1] = nowTime },
        Timelines = {},
        RemovedTimelines = {},
        frames = {},
        role = (MyRole()),
    }, Fight)
    fight = f
    f.casts = Casts(f)
    if Settings().bars then
        BuildBars()
        ticker = C_Timer.NewTicker(0.1, Tick)
    end
    StartAlerts(f, 1, nowTime)
    local rules = mod.BossPhases and mod.BossPhases[encID]
    if rules and not testDifficulty then
        if rules.start then
            rules.start(f)
        end
        if rules.detect then
            for _, event in ipairs({
                "ENCOUNTER_TIMELINE_EVENT_ADDED",
                "ENCOUNTER_TIMELINE_EVENT_REMOVED",
                "ENCOUNTER_TIMELINE_EVENT_STATE_CHANGED",
            }) do
                pcall(timelineEvents.RegisterEvent, timelineEvents, event)
            end
            if rules.engage then
                timelineEvents:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
            end
        end
    end
    return true
end
mod.StopTimeline = Stop

--- For testing a phase rule: change phase now, as if the rule had seen it.
function mod.TimelinePhase(phase)
    if not fight then
        return false
    end
    fight.Phase = phase
    fight:StartReminders(phase)
    fight.PhaseSwapTime = GetTime()
    return true
end

timelineEvents:SetScript("OnEvent", function(_, evt, arg)
    local f = fight
    local rules = f and mod.BossPhases and mod.BossPhases[f.encID]
    if not (rules and rules.detect) then
        return
    end
    if evt == "ENCOUNTER_TIMELINE_EVENT_ADDED" then
        local details = arg
        if type(details) ~= "table" then
            return
        end
        if details.source ~= Enum.EncounterTimelineEventSource.Encounter then
            custom[details.id] = true
            return
        end
        rules.detect(f, evt, details)
    elseif evt == "ENCOUNTER_TIMELINE_EVENT_REMOVED" then
        if custom[arg] then
            return
        end
        rules.detect(f, evt, nil)
    elseif evt == "ENCOUNTER_TIMELINE_EVENT_STATE_CHANGED" then
        if custom[arg] then
            return
        end
        if C_EncounterTimeline.GetEventState(arg) == Enum.EncounterTimelineEventState.Canceled then
            rules.detect(f, "ENCOUNTER_TIMELINE_EVENT_REMOVED", nil)
        end
    elseif evt == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" then
        rules.detect(f, evt)
    end
end)

local events = CreateFrame("Frame")
events:RegisterEvent("ENCOUNTER_START")
events:RegisterEvent("ENCOUNTER_END")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", function(_, evt, encID, _, difficulty)
    if evt == "ENCOUNTER_END" or evt == "PLAYER_ENTERING_WORLD" then
        return Stop()
    end
    if evt ~= "ENCOUNTER_START" then
        return
    end
    if Secret(encID) or Secret(difficulty) then
        return
    end
    local cfg = Settings()
    if cfg.bars or cfg.alerts then
        mod.StartTimeline(encID, difficulty)
    end
end)

-------------------------------------------------------------------------------
--  The timeline window (/cbt)
-------------------------------------------------------------------------------
local window, contentFrame, rowList = nil, nil, {}
local shownBoss, shownDiff

local function Time(sec)
    return ("%d:%02d"):format(math.floor(sec / 60), math.floor(sec % 60))
end

local function Row(idx)
    local r = rowList[idx]
    if r then
        return r
    end
    r = CreateFrame("Frame", nil, contentFrame)
    r:SetSize(560, 20)
    r.swatch = r:CreateTexture(nil, "ARTWORK")
    r.swatch:SetSize(4, 18)
    r.swatch:SetPoint("LEFT", 0, 0)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(18, 18)
    r.icon:SetPoint("LEFT", 8, 0)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.text = r:CreateFontString(nil, "OVERLAY")
    CludesUI.Kit.Font(r.text, 12, nil)
    r.text:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 6, 0)
    r.text:SetWidth(530)
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(true)
    rowList[idx] = r
    return r
end

local function Draw()
    if not (window and window:IsShown()) then
        return
    end
    for _, r in ipairs(rowList) do
        r:Hide()
    end
    local timeline, diffName = Timeline(shownBoss, shownDiff == "Heroic" and 15 or 16)
    window.boss:SetText(
        (Data().names[shownBoss] or ("Encounter " .. shownBoss)) .. "  |cff9aa6b2" .. (diffName or "") .. "|r"
    )
    if not timeline then
        contentFrame:SetHeight(10)
        return
    end
    local posY, num = 0, 0
    local mine = Settings().mine
    local role = MyRole()
    local entries = {}
    for _, a in ipairs(timeline.abilities) do
        if not mine or ForRole(a, role) then
            entries[#entries + 1] = a
        end
    end
    table.sort(entries, function(lhs, rhs)
        if lhs.phase ~= rhs.phase then
            return lhs.phase < rhs.phase
        end
        return (lhs.times[1] or 0) < (rhs.times[1] or 0)
    end)
    local lastPhase
    for _, a in ipairs(entries) do
        if a.phase ~= lastPhase then
            lastPhase = a.phase
            num = num + 1
            local r = Row(num)
            r.swatch:Hide()
            r.icon:Hide()
            local phase = timeline.phases[a.phase]
            r.text:SetText(
                ("|cffffd100Phase %s|r  |cff9aa6b2from %s%s|r"):format(
                    a.phase,
                    Time(phase and phase.start or 0),
                    phase and phase.name and ("  " .. phase.name) or ""
                )
            )
            r:SetHeight(20)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, -posY)
            r:Show()
            posY = posY + 22
        end
        num = num + 1
        local r = Row(num)
        local c = Colour(a.category)
        r.swatch:SetColorTexture(c[1], c[2], c[3], 1)
        r.swatch:Show()
        local icon = C_Spell.GetSpellTexture(a.spellID)
        r.icon:SetTexture((not Secret(icon) and icon) or 134400)
        r.icon:Show()
        local times = {}
        local start = timeline.phases[a.phase] and timeline.phases[a.phase].start or 0
        for idx, t in ipairs(a.times) do
            if idx > 24 then
                times[#times + 1] = "..."
                break
            end
            times[#times + 1] = Time(start + t)
        end
        r.text:SetText(
            ("%s  |cff9aa6b2%s%s|r\n|cffcccccc%s|r"):format(
                a.name,
                a.category or "",
                (a.duration or 0) > 0 and (", " .. a.duration .. "s") or "",
                table.concat(times, "  ")
            )
        )
        local hgt = r.text:GetStringHeight() + 6
        r:SetHeight(math.max(22, hgt))
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, -posY)
        r:Show()
        posY = posY + math.max(22, hgt) + 2
    end
    contentFrame:SetHeight(posY + 10)
end

local function BuildWindow()
    window = CreateFrame("Frame", "CludesUIBossTimeline", UIParent)
    window:SetSize(620, 520)
    window:SetPoint("CENTER", 0, 30)
    CludesUI.Kit.Panel(window, 0.96)
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    window:SetFrameStrata("HIGH")
    window:SetClampedToScreen(true)
    local title = window:CreateFontString(nil, "OVERLAY")
    CludesUI.Kit.Font(title, 15, nil)
    title:SetPoint("TOPLEFT", 10, -8)
    title:SetText("Boss Timeline")
    CludesUI.Kit.AccentText(title)
    local close = CludesUI.Kit.Glyph(window, "x", function()
        window:Hide()
    end, nil, nil)
    close:SetPoint("TOPRIGHT", -5, -5)
    local pick = CludesUI.Kit.Button(window, "", 90, 22, nil, { key = nil })
    pick:SetSize(220, 22)
    pick:SetPoint("TOPLEFT", 10, -32)
    pick:SetText("Pick a boss")
    pick:SetScript("OnClick", function(self)
        CludesUI.Kit.ContextMenu(self, function(_, root)
            local seen = {}
            local ids = {}
            for _, ident in ipairs(Data().order or {}) do
                ids[#ids + 1] = ident
                seen[ident] = true
            end
            local rest = {}
            for ident in pairs(Data().timelines) do
                if not seen[ident] then
                    rest[#rest + 1] = ident
                end
            end
            table.sort(rest)
            root:CreateTitle("Current raid")
            for _, ident in ipairs(ids) do
                if Data().timelines[ident] then
                    root:CreateButton(Data().names[ident] or tostring(ident), function()
                        shownBoss = ident
                        Draw()
                    end)
                end
            end
            root:CreateTitle("Earlier")
            for _, ident in ipairs(rest) do
                root:CreateButton(Data().names[ident] or tostring(ident), function()
                    shownBoss = ident
                    Draw()
                end)
            end
        end)
    end)
    local diff = CludesUI.Kit.Button(window, "", 90, 22, nil, { key = nil })
    diff:SetSize(90, 22)
    diff:SetPoint("LEFT", pick, "RIGHT", 6, 0)
    diff:SetText("Mythic")
    diff:SetScript("OnClick", function(self)
        shownDiff = shownDiff == "Heroic" and "Mythic" or "Heroic"
        self:SetText(shownDiff)
        Draw()
    end)
    local test = CludesUI.Kit.Button(window, "", 90, 22, nil, { key = nil })
    test:SetSize(90, 22)
    test:SetPoint("LEFT", diff, "RIGHT", 6, 0)
    test:SetText("Test")
    test:SetScript("OnClick", function()
        local d = shownDiff == "Heroic" and 15 or 16
        if mod.StartTimeline(shownBoss, d, d) then
            Say("running this timeline as if pulled now. /cbt stop ends it.")
        end
    end)
    window.boss = window:CreateFontString(nil, "OVERLAY")
    CludesUI.Kit.Font(window.boss, 13, nil)
    window.boss:SetPoint("TOPLEFT", 10, -62)
    local scroll = (CludesUI.Kit.Scroll(window))
    scroll:SetPoint("TOPLEFT", 10, -84)
    scroll:SetPoint("BOTTOMRIGHT", -30, 10)
    contentFrame = CreateFrame("Frame", nil, scroll)
    contentFrame:SetSize(570, 10)
    scroll:SetScrollChild(contentFrame)
    window:Hide()
    tinsert(UISpecialFrames, "CludesUIBossTimeline")
end

function mod.OpenTimeline()
    if not window then
        BuildWindow()
    end
    shownBoss = shownBoss or (Data().order and Data().order[1]) or next(Data().timelines)
    shownDiff = shownDiff or "Mythic"
    window:Show()
    Draw()
end

SLASH_CUIBOSSTIMELINE1 = "/cbt"
SlashCmdList.CUIBOSSTIMELINE = function(msg)
    if (msg or ""):lower():find("stop") then
        Stop()
        if mod.StopReminders then
            mod.StopReminders()
        end
        return
    end
    local phase = tonumber((msg or ""):match("^%s*phase%s+([%d.]+)"))
    if phase then
        if not mod.TimelinePhase(phase) then
            Say("no boss timeline is running.")
        end
        return
    end
    if window and window:IsShown() then
        window:Hide()
    else
        mod.OpenTimeline()
    end
end

-------------------------------------------------------------------------------
--  Layout Mode
-------------------------------------------------------------------------------
local registered = false
local reg = CreateFrame("Frame")
reg:RegisterEvent("PLAYER_ENTERING_WORLD")
reg:SetScript("OnEvent", function()
    if registered or not (CludesUI.RegisterUnlockElements and CludesUI.MakeUnlockElement) then
        return
    end
    registered = true
    BuildBars()
    CludesUI:RegisterUnlockElements({
        CludesUI.MakeUnlockElement({
            key = "RLEAD_Timeline",
            label = "Boss Timeline Bars",
            group = "Raid Lead",
            order = 661,
            noAnchorTarget = true,
            noResize = true,
            isHidden = function()
                return not Settings().bars
            end,
            getFrame = function()
                BuildBars()
                return holderFrame
            end,
            getSize = function()
                return 260, 21 * Settings().count
            end,
            savePos = function(_, anchorPoint, relPoint, posX, posY)
                Settings().pos = { point = anchorPoint, relPoint = relPoint, x = posX, y = posY }
            end,
            loadPos = function()
                return Settings().pos
            end,
            clearPos = function()
                Settings().pos = nil
            end,
            applyPos = function()
                if not holderFrame or InCombatLockdown() then
                    return
                end
                holderFrame:ClearAllPoints()
                local p = Settings().pos
                if p then
                    holderFrame:SetPoint(
                        p.point or "CENTER",
                        UIParent,
                        p.relPoint or "CENTER",
                        p.x or 0,
                        p.y or 0
                    )
                else
                    holderFrame:SetPoint("LEFT", UIParent, "LEFT", 40, 80)
                end
            end,
        }),
    }, "CludesUIRaidLead")
end)
