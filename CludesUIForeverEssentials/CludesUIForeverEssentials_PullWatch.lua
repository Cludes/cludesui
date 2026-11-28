if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
if not (CUI and CUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_PullWatch.lua  (WoW Forever only)
--  Who Pulled: in a dungeon or raid group, says who was first into each
--  fight: "Pull: Sneaky on Defias Thug" when they had a hostile target, or
--  "Pull: Holy was attacked first" when a mob came to them. Printed for you;
--  with Say in Group on, also in group chat. A fight is over once the group
--  is out of combat for a few seconds.
--  The game keeps the combat log from addons on this client, so this reads
--  who enters combat first (UNIT_FLAGS), pets counting for their owner.
-------------------------------------------------------------------------------
local _, module = ...

local F = module.Feature("pullWatch", { enabled = false, say = false })
local Get, Enabled, Cfg = F.Get, F.Enabled, F.Cfg

local QUIET = 4 -- seconds out of combat before the next fight is a new pull

local fightOn = false
local lastInCombat = 0
local wanted = false
local watcher -- once a second while a fight is on: has the group been out of combat long enough?
local events = CreateFrame("Frame")

local function Secret(v) return v ~= nil and issecretvalue and issecretvalue(v) end

local function Wanted()
    if not (Enabled() and IsInGroup()) then return false end
    local inside, kind = IsInInstance()
    return inside and (kind == "party" or kind == "raid")
end

-- Each group unit and pet -> the member it belongs to.
local OWNER = { player = "player", pet = "player" }
for i = 1, 4 do
    OWNER["party" .. i], OWNER["partypet" .. i] = "party" .. i, "party" .. i
end
for i = 1, 40 do
    OWNER["raid" .. i], OWNER["raidpet" .. i] = "raid" .. i, "raid" .. i
end

local function Fighting(unit)
    local on = UnitAffectingCombat(unit)
    return on and not Secret(on)
end

local function GroupInCombat()
    if Fighting("player") then return true end
    local prefix, n = IsInRaid() and "raid" or "party", IsInRaid() and GetNumGroupMembers() or GetNumSubgroupMembers()
    for i = 1, n do
        if Fighting(prefix .. i) then return true end
    end
    return false
end

local function Announce(text)
    CUI.Print("|cff4cc9f0Pull:|r " .. text)
    if not Get("say") then return end
    if C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then return end
    local channel = IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and "INSTANCE_CHAT" or IsInRaid() and "RAID" or "PARTY"
    C_ChatInfo.SendChatMessage("Pull: " .. text, channel)
end

local function Plain(v) return v and not Secret(v) and v or nil end

local function EndFightCheck()
    if GroupInCombat() then
        lastInCombat = GetTime()
    elseif GetTime() - lastInCombat >= QUIET then
        fightOn = false
        if watcher then
            watcher:Cancel()
            watcher = nil
        end
    end
end

-- A group unit (or pet) went into combat: the first one of a fight is the pull.
local function Entered(unit)
    if fightOn or not wanted then return end
    local owner = OWNER[unit]
    if not owner or not UnitExists(unit) or not Fighting(unit) then return end
    fightOn = true
    lastInCombat = GetTime()
    if not watcher then watcher = C_Timer.NewTicker(1, EndFightCheck) end
    local who = Plain(UnitName(owner))
    who = who and Ambiguate(who, "short") or "?"
    if unit ~= owner then who = who .. "'s pet" end
    local target = unit .. "target"
    local foe = UnitExists(target) and UnitCanAttack(unit, target) and Plain(UnitName(target))
    if foe then
        Announce(("%s on %s"):format(who, foe))
    else
        Announce(("%s was attacked first"):format(who))
    end
end

events:SetScript("OnEvent", function(_, event, unit)
    if event == "UNIT_FLAGS" then
        if not Secret(unit) then Entered(unit) end
        return
    end
    if event == "PLAYER_REGEN_DISABLED" then
        Entered("player")
        return
    end
    -- Zone or group changed: is this a dungeon or raid group?
    wanted = Wanted()
end)

local function Apply()
    events:UnregisterAllEvents()
    fightOn = false
    if watcher then
        watcher:Cancel()
        watcher = nil
    end
    if not Enabled() then return end
    for _, ev in ipairs({ "UNIT_FLAGS", "PLAYER_REGEN_DISABLED", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "GROUP_ROSTER_UPDATE" }) do
        events:RegisterEvent(ev)
    end
    wanted = Wanted()
end

CUI._PullWatch = { Get = Get, Cfg = Cfg, Apply = Apply, Entered = Entered, Reset = function() fightOn = false end }

F.Start(Apply)
