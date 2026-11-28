if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
if not (CUI and CUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_PullWatch.lua  (WoW Forever only)
--  Who Pulled: in a dungeon or raid group, the first hit of each fight says
--  who started it: "Pull: Sneaky (Sinister Strike) on Defias Thug", or
--  "Pull: Defias Thug hit Holy" when a mob came to the group. Printed for
--  you; with Say in Group on, also in group chat. A fight is over once the
--  group is out of combat for a few seconds.
--  Reads the combat log's first damage or aura between a group member (or
--  their pet) and a hostile creature.
-------------------------------------------------------------------------------
local _, module = ...

local F = module.Feature("pullWatch", { enabled = false, say = false })
local Get, Enabled, Cfg = F.Get, F.Enabled, F.Cfg

-- The game's combat log flags (its constants, else their known values).
local function Flag(value, known) return type(value) == "number" and value or known end
local MINE = bit.bor(Flag(COMBATLOG_OBJECT_AFFILIATION_MINE, 1), Flag(COMBATLOG_OBJECT_AFFILIATION_PARTY, 2), Flag(COMBATLOG_OBJECT_AFFILIATION_RAID, 4))
local HOSTILE = Flag(COMBATLOG_OBJECT_REACTION_HOSTILE, 0x40)
local NPC = Flag(COMBATLOG_OBJECT_TYPE_NPC, 0x800)
local STARTS = { SWING_DAMAGE = true, RANGE_DAMAGE = true, SPELL_DAMAGE = true, SPELL_AURA_APPLIED = true, SPELL_MISSED = true,
    SWING_MISSED = true, RANGE_MISSED = true, SPELL_PERIODIC_DAMAGE = true }
local QUIET = 4 -- seconds out of combat before the next hit is a new pull

local fightOn = false
local lastInCombat = 0
local events = CreateFrame("Frame")

local function Secret(v) return v ~= nil and issecretvalue and issecretvalue(v) end

local function Wanted()
    if not (Enabled() and IsInGroup()) then return false end
    local inside, kind = IsInInstance()
    return inside and (kind == "party" or kind == "raid")
end

local function GroupInCombat()
    if UnitAffectingCombat("player") then return true end
    local prefix, n = IsInRaid() and "raid" or "party", IsInRaid() and GetNumGroupMembers() or GetNumSubgroupMembers()
    for i = 1, n do
        local fighting = UnitAffectingCombat(prefix .. i)
        if fighting and not Secret(fighting) then return true end
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

local function ShortName(name) return name and Ambiguate(name, "short") or "?" end

-- One combat log event: the first between the group and a hostile creature is the pull.
local function OnLog(_, sub, _, _, srcName, srcFlags, _, _, dstName, dstFlags, _, _, spellName)
    if fightOn or not STARTS[sub] then return end
    if Secret(srcFlags) or Secret(dstFlags) or type(srcFlags) ~= "number" or type(dstFlags) ~= "number" then return end
    local srcOurs, dstOurs = bit.band(srcFlags, MINE) ~= 0, bit.band(dstFlags, MINE) ~= 0
    local srcFoe = bit.band(srcFlags, HOSTILE) ~= 0 and bit.band(srcFlags, NPC) ~= 0
    local dstFoe = bit.band(dstFlags, HOSTILE) ~= 0 and bit.band(dstFlags, NPC) ~= 0
    if srcOurs and dstFoe then
        fightOn = true
        local how = (sub ~= "SWING_DAMAGE" and sub ~= "SWING_MISSED" and spellName and not Secret(spellName)) and (" (" .. spellName .. ")") or ""
        Announce(("%s%s on %s"):format(ShortName(srcName), how, ShortName(dstName)))
    elseif srcFoe and dstOurs then
        fightOn = true
        Announce(("%s hit %s"):format(ShortName(srcName), ShortName(dstName)))
    end
end

local wanted = false
local watcher -- once a second while a fight is on: has the group been out of combat long enough?

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

events:SetScript("OnEvent", function(_, event)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        if fightOn or not wanted then return end
        OnLog(CombatLogGetCurrentEventInfo())
        if fightOn then
            lastInCombat = GetTime()
            if not watcher then watcher = C_Timer.NewTicker(1, EndFightCheck) end
        end
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
    if not Enabled() or not CombatLogGetCurrentEventInfo then return end
    for _, ev in ipairs({ "COMBAT_LOG_EVENT_UNFILTERED", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "GROUP_ROSTER_UPDATE" }) do
        events:RegisterEvent(ev)
    end
    wanted = Wanted()
end

CUI._PullWatch = { Get = Get, Cfg = Cfg, Apply = Apply, OnLog = OnLog, Reset = function() fightOn = false end }

F.Start(Apply)
