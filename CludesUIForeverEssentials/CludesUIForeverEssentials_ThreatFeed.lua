if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if not (CludesUI and CludesUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_ThreatFeed.lua  (WoW Forever only)
--  The threat list for the Damage Meters "Threat" meter type: the threat
--  meter's data and settings (tracked unit, pets, pull aggro line, displayed
--  value, highlight colours) handed over as rows a Damage Meters window paints
--  in its own style. Damage Meters starts it while one of its windows shows
--  the list and stops it when none does, whatever the threat meter window's
--  own state. The two read through separate collectors, so neither rewrites
--  the rows the other has on screen.
-------------------------------------------------------------------------------
local _, module = ...
local mod = module.ThreatMeter
local CUI = CludesUI
local Get = mod.Get

local UPDATE_DELAY = 0.2
local FOLLOW_INTERVAL = 0.5
local PET_ICON = CUI.ClientIcon(132161)

local collector = mod.NewCollector()
local entries = collector.list
local pool = {} -- pooled rows, by position
local sources = {} -- the rows on screen
local session = { combatSources = sources } -- what a window paints
local events, isActive, notify
local pending, threatOn, flagsUnit, mobUnit, followTicker, titleName
local units = false -- Force English Units, the Damage Meters setting the value text follows
local fmtGen = 0 -- bumped on a Number Format change, so the value texts rebuild
local conf -- the list's settings, resolved once per settings change
local RequestUpdate

-- "1.", "2.", ... built once each. The pull line takes no rank.
local RANKS = setmetatable({}, {
    __index = function(tbl, index)
        local s = index .. "."
        tbl[index] = s
        return s
    end,
})

-- The icon a Damage Meters row carries for a class: WoW Forever's one spec
-- per class. Kept once found; a failed read tries again next time.
local specIcons = {}
local function SpecIcon(unitToken, class)
    local iconTex = specIcons[class]
    if iconTex then return iconTex end
    local _, _, classID = UnitClass(unitToken)
    if issecretvalue(classID) or type(classID) ~= "number" then return nil end
    local _, _, _, fileID = GetSpecializationInfoForClassID(classID, 1)
    if issecretvalue(fileID) or type(fileID) ~= "number" then return nil end
    specIcons[class] = fileID
    return fileID
end

-- The threat settings the rows use, read once after each settings change
-- (ns.FeedChanged drops it; the meter's settings writes all pass there).
local function Settings()
    if conf then return conf end
    conf = {
        pets = Get("pets"),
        pullBar = Get("pullBar"),
        showValue = Get("showValue"),
        showPercent = Get("showPercent"),
        pullPercent = Get("percentMode") == "pull",
        pullColor = Get("pullColor"),
        playerColor = Get("playerColorOn") and Get("playerColor") or nil,
        tankColor = Get("tankColorOn") and Get("tankColor") or nil,
    }
    return conf
end

-- One row: the fields a Damage Meters row reads, plus the threat ones
-- (rankText, threatText, threatColor, threatPet). The value text is rebuilt only
-- when its numbers or the unit style change.
local function FillRow(region, e, rank, cfg)
    local unitToken = e.unit
    if e.pull then
        region.name, region.classFilename, region.specIconID = CludesUI.L("Pull Aggro"), nil, nil
        region.rankText, region.threatColor = "", cfg.pullColor
    else
        local class = mod.ClassOf(unitToken)
        local name = CUI.WithSurname(UnitName(unitToken))
        if not issecretvalue(name) and name == nil then name = unitToken end
        region.name, region.classFilename = name, class
        if e.isPet then
            region.specIconID = PET_ICON
        else
            region.specIconID = class and SpecIcon(unitToken, class) or nil
        end
        region.rankText = RANKS[rank]
        region.threatColor = (e.own and cfg.playerColor) or (e.tanking and cfg.tankColor) or nil
    end
    region.threatPet = e.isPet == true
    region.isLocalPlayer = e.own == true
    region.totalAmount = e.raw
    region.threatScaled = e.scaled
    local raw = cfg.showValue and e.raw or nil
    local pct
    if cfg.showPercent and not (e.pull and raw) then
        if cfg.pullPercent then
            pct = e.scaled
        else
            pct = e.rawPct
        end
    end
    if
        region.threatText == nil
        or region._raw ~= raw
        or region._pct ~= pct
        or region._units ~= units
        or region._fmt ~= fmtGen
    then
        region._raw, region._pct, region._units, region._fmt = raw, pct, units, fmtGen
        if raw and pct then
            region.threatText = format("%s  %.0f%%", CUI.AbbreviateNumber(raw, units), pct)
        elseif raw then
            region.threatText = CUI.AbbreviateNumber(raw, units)
        elseif pct then
            region.threatText = format("%.0f%%", pct)
        else
            region.threatText = ""
        end
    end
end

-- Reads the mob's threat into the rows and titles the list with the mob.
-- Returns true when there is anything to repaint: rows now or before, or a new title.
local function Build()
    local c = Settings()
    local mob = mobUnit
    local total = 0
    if mob then
        local me, tankRaw = collector.Collect(mob, c.pets)
        if #entries > 0 then
            if c.pullBar then collector.AddPullEntry(me, tankRaw) end
            collector.Sort()
        end
        total = #entries
    end
    local had = #sources
    local rank = 0
    for index = 1, total do
        local entry = entries[index]
        if not entry.pull then rank = rank + 1 end
        local region = pool[index]
        if not region then
            region = {}
            pool[index] = region
        end
        FillRow(region, entry, rank, c)
        sources[index] = region
    end
    for index = had, total + 1, -1 do
        sources[index] = nil
    end
    -- (The secret test first: a secret name cannot be tested or joined.)
    local title = session.threatTitle
    local name = mob and CUI.WithSurname(UnitName(mob))
    if issecretvalue(name) or not name then
        titleName = nil
        session.threatTitle = CludesUI.L("Threat")
    elseif name ~= titleName then
        titleName = name
        session.threatTitle = format(CludesUI.L("Threat - %s"), name)
    end
    return total > 0 or had > 0 or session.threatTitle ~= title
end

-- The two threat events fire for every unit in every fight nearby, so they are
-- registered only while a mob resolves (as the meter window does).
local function SetThreatEvents(enabled)
    if enabled == threatOn then return end
    threatOn = enabled
    if enabled then
        events:RegisterEvent("UNIT_THREAT_LIST_UPDATE")
        events:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
    else
        events:UnregisterEvent("UNIT_THREAT_LIST_UPDATE")
        events:UnregisterEvent("UNIT_THREAT_SITUATION_UPDATE")
    end
end

-- No threat event names a derived token (targettarget): while the list follows
-- what a friendly unit is fighting, re-read on a short interval, in combat only.
local function SetFollow(enabled)
    if enabled then
        if not followTicker then followTicker = C_Timer.NewTicker(FOLLOW_INTERVAL, RequestUpdate) end
    elseif followTicker then
        followTicker:Cancel()
        followTicker = nil
    end
end

local function Update()
    pending = false
    if not isActive then return end
    local tracked = mod.GetTrackedUnit()
    if tracked ~= flagsUnit then
        events:RegisterUnitEvent("UNIT_FLAGS", "pet", tracked)
        flagsUnit = tracked
    end
    local mob = mod.ResolveSource(tracked)
    mobUnit = mob
    SetThreatEvents(mob ~= nil)
    SetFollow(mob ~= nil and mob ~= tracked and InCombatLockdown())
    return Build()
end

-- A list that stayed empty under the same title has nothing to repaint.
local function Tick()
    local changed = Update()
    if changed and isActive and notify then notify() end
end

-- A raid pull is a burst of per-unit updates: one rebuild per short window.
RequestUpdate = function()
    if pending then return end
    pending = true
    C_Timer.After(UPDATE_DELAY, Tick)
end

-- The feed's event filter, on the threat meter's rules: a threat-list change
-- counts only for the mob shown (a secret comparison counts as a match), a
-- threat-situation or pet change only for a unit the list can hold, a target or
-- flags change only for the tracked unit (or the pet). Combat edges start and
-- stop the follow reads.
local function OnEvent(_, evt, unitToken)
    if evt == "GROUP_ROSTER_UPDATE" then
        mod.RosterChanged()
    elseif evt == "PLAYER_TARGET_CHANGED" or evt == "PLAYER_FOCUS_CHANGED" then
        if (evt == "PLAYER_FOCUS_CHANGED") ~= (mod.GetTrackedUnit() == "focus") then return end
    end
    if pending then return end
    if evt == "UNIT_THREAT_LIST_UPDATE" then
        local mob = mobUnit
        if not mob then return end
        if unitToken ~= mob then
            local same = UnitIsUnit(unitToken, mob)
            if not issecretvalue(same) and not same then return end
        end
    elseif evt == "UNIT_THREAT_SITUATION_UPDATE" then
        if not (mod.MEMBER_UNITS[unitToken] or (mod.PET_UNITS[unitToken] and Settings().pets)) then return end
    elseif evt == "UNIT_PET" then
        if not (mod.MEMBER_UNITS[unitToken] and Settings().pets) then return end
    elseif evt == "UNIT_TARGET" or evt == "UNIT_FLAGS" then
        if unitToken == "pet" then
            if not Settings().pets then return end
        elseif unitToken ~= mod.GetTrackedUnit() then
            return
        end
    end
    RequestUpdate()
end

-- onUpdate runs after every rebuild an event starts; the rows are ready on
-- return (the caller paints them).
local function Start(onUpdate)
    notify = onUpdate
    if isActive then return end
    isActive = true
    if not events then
        events = CreateFrame("Frame")
        events:SetScript("OnEvent", OnEvent)
    end
    events:RegisterEvent("PLAYER_TARGET_CHANGED")
    events:RegisterEvent("PLAYER_FOCUS_CHANGED")
    events:RegisterEvent("GROUP_ROSTER_UPDATE")
    events:RegisterEvent("UNIT_PET")
    events:RegisterEvent("PLAYER_REGEN_DISABLED")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:RegisterUnitEvent("UNIT_TARGET", "target", "focus")
    flagsUnit = nil
    -- The roster memos missed every change made while nothing listened (the
    -- threat meter window keeps them current while it is on).
    if not Get("enabled") then mod.RosterChanged() end
    Update()
end

local function Stop()
    if not isActive then return end
    isActive = false
    events:UnregisterAllEvents()
    threatOn, flagsUnit, mobUnit, titleName = false, nil, nil, nil
    SetFollow(false)
    conf = nil
    for index = #sources, 1, -1 do
        sources[index] = nil
    end
end

-- A threat setting changed (the meter's options, its header menu, /cuitm).
function mod.FeedChanged()
    conf = nil
    if isActive then RequestUpdate() end
end

CUI.RegisterNumberFormatCallback(function()
    fmtGen = fmtGen + 1
    if isActive then RequestUpdate() end
end)

CUI._ThreatFeed = {
    Start = Start,
    Stop = Stop,
    IsActive = function() return isActive == true end,
    -- eng: the window's Force English Units; a change rebuilds the value texts.
    Session = function(eng)
        eng = eng == true
        if isActive and eng ~= units then
            units = eng
            Build()
        end
        return session
    end,
    -- Tracked unit, displayed value and pets, for the window's settings menu.
    MenuItems = function(itemList) return mod.DataMenuItems(itemList) end,
}
