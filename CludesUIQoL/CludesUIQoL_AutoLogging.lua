if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUIQoL_AutoLogging.lua - combat logging that follows the content.
--
--  On entering an instance the log is switched on if its kind is ticked
--  (raid difficulties, LFR, Mythic and Mythic+ dungeons, arenas, group
--  scenarios, rated and Blitz battlegrounds), with Advanced Combat Logging
--  forced on. Leaving stops a log this started, after 30s by default (so a
--  quick zone-out and back keeps one log). A log the player started by hand
--  is left alone. WoW Forever has its own two kinds: raids and dungeons.
--
--  Settings: CludesUIDB.autoLogging (enabled, notify, the log* triggers,
--  delaystop).
-------------------------------------------------------------------------------

-- Retail instance map IDs below these are older content (and not logged),
-- except the ones listed below.
local NEW_RAID_FROM = 2657
local NEW_DUNGEON_FROM = 959

-- SEASON UPDATE: older dungeons back in the Mythic+ rotation.
local OLD_DUNGEONS_IN_SEASON = {
    [1594] = true, -- The MOTHERLODE!!
    [1208] = true, -- Grimrail Depot
    [1195] = true, -- Iron Docks
    [1651] = true, -- Return to Karazhan
    [657] = true, -- The Vortex Pinnacle
    [643] = true, -- Throne of the Tides
    [670] = true, -- Grim Batol
    [658] = true, -- Pit of Saron
}

-- SEASON UPDATE: current raids with a low map ID (IDs are not in release
-- order; Sporefall's 1592 is below older raids').
local NEW_RAIDS_WITH_OLD_IDS = {
    [1592] = true, -- Sporefall
}

local LFR = { [7] = true, [17] = true } -- regular and Timewalking
-- Raid difficulty -> its trigger. 233 is flexible Mythic, beside the old 20-player 16.
local RAID_TRIGGER = { [16] = "logMythic", [233] = "logMythic", [15] = "logHeroic", [14] = "logNormal" }
local KEYSTONE, MYTHIC_DUNGEON = 23, 8

-- Everything on except scenarios and the rated battlegrounds.
local DEFAULTS = {
    logMythic = true,
    logHeroic = true,
    logNormal = true,
    logLFR = true,
    log5pp = true,
    logArena = true,
    logScenario = false,
    logRBG = false,
    logBlitz = false,
    delaystop = true,
}

local STOP_AFTER = 30 -- seconds

local function Settings()
    if not CludesUIDB then
        return {}
    end
    CludesUIDB.autoLogging = CludesUIDB.autoLogging or {}
    return CludesUIDB.autoLogging
end

local function On(cfg, key)
    local value = cfg[key]
    if value == nil then
        return DEFAULTS[key]
    end
    return value
end

-- Whether the current place should be logged.
local function WantLog()
    local s = Settings()
    if not s.enabled then
        return false
    end
    local _, kind, rawDifficulty, _, maxPlayers, _, _, rawMap = GetInstanceInfo()

    -- WoW Forever: raids on the Raids trigger (the Normal raid key), dungeons
    -- on its own Dungeons trigger (off until ticked); nothing else applies.
    if CludesUI.IS_FOREVER then
        if kind == "raid" then
            return On(s, "logNormal")
        end
        return kind == "party" and s.logDungeon == true
    end

    -- Battlegrounds: Blitz first (it is also rated); unrated ones never log.
    if kind == "pvp" and C_PvP then
        if C_PvP.IsRatedSoloRBG and C_PvP.IsRatedSoloRBG() then
            return On(s, "logBlitz")
        end
        if C_PvP.IsRatedBattleground and C_PvP.IsRatedBattleground() then
            return On(s, "logRBG")
        end
        return false
    end

    local difficulty, map = tonumber(rawDifficulty), tonumber(rawMap)
    if not difficulty or not map then
        return false
    end
    if LFR[difficulty] then
        return On(s, "logLFR")
    end
    if kind == "raid" and (map >= NEW_RAID_FROM or NEW_RAIDS_WITH_OLD_IDS[map]) then
        local trigger = RAID_TRIGGER[difficulty]
        if trigger then
            return On(s, trigger)
        end
        return true -- Timewalking and other difficulties
    end
    if On(s, "log5pp") then
        local mythic = difficulty == KEYSTONE or difficulty == MYTHIC_DUNGEON
        if mythic and (map >= NEW_DUNGEON_FROM or OLD_DUNGEONS_IN_SEASON[map]) then
            return true
        end
    end
    if
        On(s, "logScenario")
        and kind == "scenario"
        and (tonumber(maxPlayers) or 0) > 1
        and map >= NEW_DUNGEON_FROM
    then
        return true
    end
    if On(s, "logArena") and (kind == "arena" or kind == "ratedarena") then
        return true
    end
    return false
end

-- A chat line when logging starts or stops (off by default).
local function Say(started)
    if Settings().notify ~= true then
        return
    end
    local text = CludesUI.L(started and "AutoLog Started" or "AutoLog Stopped")
    CludesUI.Print(CludesUI.COLOR_CODES.BRAND .. "CludesUI:|r " .. text)
end

local function Stop()
    if LoggingCombat() then
        LoggingCombat(false)
        Say(false)
    end
end

local ours = false -- the place we were in wanted a log (so the log is ours to stop)
local stopTimer

local function CancelStop()
    if stopTimer then
        stopTimer:Cancel()
        stopTimer = nil
    end
end

local function Apply()
    local want = WantLog()
    if want then
        CancelStop()
        if GetCVar and GetCVar("advancedCombatLogging") ~= "1" then
            CludesUI.SetCVar("advancedCombatLogging", 1, "CludesUIQoL")
        end
        local already = LoggingCombat()
        LoggingCombat(true)
        if not already then
            Say(true)
        end
    elseif ours and LoggingCombat() then
        if not On(Settings(), "delaystop") then
            Stop()
        elseif not stopTimer then
            stopTimer = C_Timer.NewTimer(STOP_AFTER, function()
                stopTimer = nil
                Stop()
            end)
        end
    end
    ours = want
end

-- The zone has settled a moment after these; a battleground going live can
-- set its rated flags after the zone-in check.
local EVENTS = {
    ZONE_CHANGED_NEW_AREA = function()
        C_Timer.After(2, Apply)
    end,
    CHALLENGE_MODE_START = function()
        C_Timer.After(1, Apply)
    end,
}
if not CludesUI.IS_FOREVER then
    EVENTS.PVP_MATCH_ACTIVE = Apply
end

-- The zone events are registered only while the feature is on.
local listener = CreateFrame("Frame")
local listening = false
local function Listen()
    local want = Settings().enabled and true or false
    if want == listening then
        return
    end
    listening = want
    for event in pairs(EVENTS) do
        if want then
            listener:RegisterEvent(event)
        else
            listener:UnregisterEvent(event)
        end
    end
end

-- The options call this on a change: it also applies at once, so switching
-- off inside an instance still stops the log.
_G._CUI_AutoLogging_Check = function()
    Listen()
    Apply()
end

listener:RegisterEvent("PLAYER_LOGIN")
listener:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        Listen()
        C_Timer.After(2, Apply)
    elseif EVENTS[event] then
        EVENTS[event]()
    end
end)
