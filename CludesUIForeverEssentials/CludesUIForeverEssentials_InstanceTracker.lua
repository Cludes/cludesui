if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if not (CludesUI and CludesUI.IS_FOREVER) then
    return
end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_InstanceTracker.lua  (WoW Forever only)
--  Instance Tracker: how many new dungeons and raids the account has entered
--  in the last hour against the game's cap (10 an hour on Forever, a
--  setting in case that changes), when the next one frees up, and a timer
--  for the run you are in. Leaving an instance prints a summary: time,
--  deaths, experience and items looted. The last runs are kept per character.
--
--  Re-entering the same copy (after a wipe, say) is not a new instance. The
--  copy is read from a creature's GUID inside (its zone UID field), so the
--  count is taken back as soon as you target or mouse over anything that
--  shows the copy is one you were already in this hour. A reload or login
--  inside an instance never counts.
-------------------------------------------------------------------------------
local _, module = ...

local DEFAULTS = { enabled = false, cap = 10, hud = true, summary = true }
local F = module.Feature(
    "instanceTracker",
    DEFAULTS,
    { point = "TOPRIGHT", relPoint = "TOPRIGHT", x = -220, y = -220 }
)
local Get, Enabled = F.Get, F.Enabled

local HOUR = 3600
local KEEP_RUNS = 20

local function Say(textValue)
    CludesUI.Print("|cff4cc9f0Instances:|r " .. textValue)
end
local function Font()
    return CludesUI.GetFontPath("essentials")
end
local function Secret(val)
    return issecretvalue and issecretvalue(val)
end

-- Account store: entries = { {t, map, copy}, ... } for the last hour;
-- runs[guid] = { {name, start, seconds, deaths, xp, items}, ... } newest first.
local function Store()
    local c = F.Cfg()
    c.entries = c.entries or {}
    c.runs = c.runs or {}
    return c
end

local function Prune()
    local nowTime, keep = time(), {}
    for _, e in ipairs(Store().entries) do
        if nowTime - e.t < HOUR then
            keep[#keep + 1] = e
        end
    end
    Store().entries = keep
    return keep
end

--- Count this hour and seconds until the oldest one frees (nil when none).
function module.InstanceCount()
    local list = Prune()
    local oldest
    for _, e in ipairs(list) do
        if not oldest or e.t < oldest then
            oldest = e.t
        end
    end
    return #list, oldest and (oldest + HOUR - time()) or nil
end

local visit -- { map, name, start, entry, deaths, xp, items, copy }
local lastXP, lastMax

local function InGroupInstance()
    local inside, kind = IsInInstance()
    return inside and (kind == "party" or kind == "raid")
end

-- The copy (zone UID) a creature GUID names: Creature-0-server-instance-zoneUID-id-spawn.
local function CopyFrom(unitToken)
    local unitGuid = UnitGUID(unitToken)
    if not unitGuid or Secret(unitGuid) then
        return nil
    end
    local kind, _, _, _, zoneUID = strsplit("-", unitGuid)
    if kind == "Creature" or kind == "Vehicle" or kind == "GameObject" then
        return zoneUID ~= "0" and zoneUID or nil
    end
end

local copyEvents = CreateFrame("Frame")
local function ReadCopy(unitToken)
    if not visit or visit.copy then
        return
    end
    local copy = CopyFrom(unitToken)
    if not copy then
        return
    end
    visit.copy = copy
    copyEvents:UnregisterAllEvents()
    local record = visit.entry
    if record then
        record.copy = copy
    end
    -- The same copy earlier this hour: this visit is not a new instance.
    for index, e in ipairs(Store().entries) do
        if e ~= record and e.map == visit.map and e.copy == copy then
            for jdx, posX in ipairs(Store().entries) do
                if posX == record then
                    table.remove(Store().entries, jdx)
                    break
                end
            end
            visit.entry = nil
            return
        end
    end
end
copyEvents:SetScript("OnEvent", function(_, evt, unitToken)
    if evt == "UPDATE_MOUSEOVER_UNIT" then
        ReadCopy("mouseover")
    elseif evt == "PLAYER_TARGET_CHANGED" then
        ReadCopy("target")
    elseif evt == "NAME_PLATE_UNIT_ADDED" then
        ReadCopy(unitToken)
    end
end)

local function StartVisit(reload)
    local name, _, _, _, _, _, _, mapID = GetInstanceInfo()
    if visit and visit.map == mapID then
        return
    end -- still the same visit
    visit = { map = mapID, name = name, start = time(), deaths = 0, xp = 0, items = 0 }
    lastXP, lastMax = UnitXP("player"), UnitXPMax("player")
    if not reload then
        local record = { t = time(), map = mapID }
        table.insert(Store().entries, record)
        visit.entry = record
        local num = module.InstanceCount()
        local cap = Get("cap")
        if num >= cap then
            Say(
                ("|cffff6040%d of %d instances this hour.|r You may be locked out of new ones."):format(
                    num,
                    cap
                )
            )
        elseif num >= cap - 2 then
            Say(("%d of %d instances this hour."):format(num, cap))
        end
    end
    for _, e in ipairs({ "UPDATE_MOUSEOVER_UNIT", "PLAYER_TARGET_CHANGED", "NAME_PLATE_UNIT_ADDED" }) do
        copyEvents:RegisterEvent(e)
    end
end

local function EndVisit()
    if not visit then
        return
    end
    local val = visit
    visit = nil
    copyEvents:UnregisterAllEvents()
    local seconds = time() - val.start
    local unitGuid = UnitGUID("player")
    local runs = Store().runs
    runs[unitGuid] = runs[unitGuid] or {}
    table.insert(runs[unitGuid], 1, {
        name = val.name,
        start = val.start,
        seconds = seconds,
        deaths = val.deaths,
        xp = val.xp,
        items = val.items,
    })
    while #runs[unitGuid] > KEEP_RUNS do
        table.remove(runs[unitGuid])
    end
    if Get("summary") then
        local num, frees = module.InstanceCount()
        Say(
            ("%s: %s, %d death%s, %s XP, %d item%s. %d of %d this hour%s."):format(
                val.name or "?",
                SecondsToClock and SecondsToClock(seconds) or (math.floor(seconds / 60) .. "m"),
                val.deaths,
                val.deaths == 1 and "" or "s",
                BreakUpLargeNumbers and BreakUpLargeNumbers(val.xp) or val.xp,
                val.items,
                val.items == 1 and "" or "s",
                num,
                Get("cap"),
                frees and (", next frees in " .. math.ceil(frees / 60) .. " min") or ""
            )
        )
    end
end

--- This character's recent runs, newest first.
function module.InstanceRuns()
    return Store().runs[UnitGUID("player")] or {}
end

-------------------------------------------------------------------------------
--  HUD
-------------------------------------------------------------------------------
local hud, hudText

local function Build()
    if hud then
        return hud
    end
    hud = CreateFrame("Frame", "CludesUIInstanceTracker", UIParent)
    hud:SetSize(170, 30)
    hudText = hud:CreateFontString(nil, "OVERLAY")
    CludesUI.Kit.Font(hudText, 12, "essentials")
    hudText:SetPoint("TOPLEFT")
    hudText:SetJustifyH("LEFT")
    return hud
end

local function PaintHud()
    if not hud then
        return
    end
    local show = Enabled() and Get("hud")
    local num, frees = module.InstanceCount()
    if show and not visit and num == 0 and not CludesUI._unlockActive then
        show = false
    end
    hud:SetShown(show and true or false)
    if not show then
        return
    end
    local cap = Get("cap")
    local colour = num >= cap and "|cffff6040"
        or (num >= cap - 2 and "|cffffb040" or CludesUI.Kit.AccentHex())
    local line = ("%sInstances %d/%d|r"):format(colour, num, cap)
    if frees and num > 0 then
        line = line .. ("  |cff9aa6b2next in %dm|r"):format(math.ceil(frees / 60))
    end
    if visit then
        local s = time() - visit.start
        line = line .. ("\n%s  |cff9aa6b2%d:%02d|r"):format(visit.name or "", math.floor(s / 60), s % 60)
    end
    hudText:SetText(line)
end

-- Coming back to life outside ends a run left open while a ghost.
local function CheckAlive()
    if visit and not InGroupInstance() and not UnitIsDeadOrGhost("player") then
        EndVisit()
    end
end

-------------------------------------------------------------------------------
--  Events
-------------------------------------------------------------------------------
local LOOT_SELF = LOOT_ITEM_SELF and LOOT_ITEM_SELF:match("^(.-)%%s")
local LOOT_SELF_MULTI = LOOT_ITEM_SELF_MULTIPLE and LOOT_ITEM_SELF_MULTIPLE:match("^(.-)%%s")

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, evt, a1, a2)
    if evt == "PLAYER_ENTERING_WORLD" then
        local reload = a1 or a2 -- isInitialLogin, isReloadingUi
        -- A ghost running back from the graveyard is still on the run.
        if InGroupInstance() then
            StartVisit(reload)
        elseif not UnitIsDeadOrGhost("player") then
            EndVisit()
        end
    elseif evt == "PLAYER_ALIVE" or evt == "PLAYER_UNGHOST" then
        CheckAlive()
    elseif not visit then
        return
    elseif evt == "PLAYER_DEAD" then
        visit.deaths = visit.deaths + 1
    elseif evt == "PLAYER_XP_UPDATE" then
        local xp, max = UnitXP("player"), UnitXPMax("player")
        if lastXP then
            local skinData = xp - lastXP
            if skinData < 0 then
                skinData = (lastMax - lastXP) + xp
            end -- a level-up in between
            if skinData > 0 then
                visit.xp = visit.xp + skinData
            end
        end
        lastXP, lastMax = xp, max
    elseif evt == "CHAT_MSG_LOOT" and type(a1) == "string" and not Secret(a1) then
        local mine = (LOOT_SELF and a1:sub(1, #LOOT_SELF) == LOOT_SELF)
            or (LOOT_SELF_MULTI and a1:sub(1, #LOOT_SELF_MULTI) == LOOT_SELF_MULTI)
        if mine then
            visit.items = visit.items + 1
        end
    end
    PaintHud()
end)

local ticker
local function Apply()
    if Enabled() then
        Build()
        for _, e in ipairs({
            "PLAYER_ENTERING_WORLD",
            "PLAYER_DEAD",
            "PLAYER_ALIVE",
            "PLAYER_UNGHOST",
            "PLAYER_XP_UPDATE",
            "CHAT_MSG_LOOT",
        }) do
            ev:RegisterEvent(e)
        end
        if not ticker then
            ticker = C_Timer.NewTicker(1, PaintHud)
        end
        if not CludesUI._unlockActive then
            F.Place(hud)
        end
        if InGroupInstance() and not visit then
            StartVisit(true)
        end
    else
        ev:UnregisterAllEvents()
        copyEvents:UnregisterAllEvents()
        if ticker then
            ticker:Cancel()
            ticker = nil
        end
        visit = nil
    end
    PaintHud()
end

CludesUI._InstanceTracker = {
    Get = Get,
    Read = F.Read,
    Cfg = F.Cfg,
    Apply = Apply,
    Count = module.InstanceCount,
    Runs = module.InstanceRuns,
}

F.Start(Apply, {
    key = "CUI_InstanceTracker",
    label = "Instance Tracker",
    order = 741,
    frame = function(build)
        if build then
            Build()
            PaintHud()
        end
        return hud
    end,
    size = function()
        return 170, 30
    end,
    noAnchorTarget = true,
    noSizeMatchTarget = true,
})
