if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
--------------------------------------------------------------------------------
--  CUI_MythicTimer_Where.lua - Where to Show, for every Mythic+ Tools feature.
--
--  What kind of content the player is in (a "bucket": open world, Mythic
--  dungeon, heroic raid, delve...), whether they are in combat, and one shared
--  watcher that tells each subscribed feature when either may have changed
--  (mod.MTWhere).
--
--  Costs nothing while unused: the watcher frame is made by the first
--  subscriber and registers nothing before it, and unregisters everything when
--  the last one leaves. Each feature offers its own set of buckets, and a
--  bucket its filter does not offer never hides it.
--------------------------------------------------------------------------------
local _, mod = ...

local MTWhere = {}
mod.MTWhere = MTWhere

-- The nameplate unit tokens, as a list and as a set, for every feature that
-- walks or recognises plates (this file loads first).
local NAMEPLATE_TOKENS, NAMEPLATE_UNITS = {}, {}
for i = 1, 40 do
    local unit = "nameplate" .. i
    NAMEPLATE_TOKENS[i] = unit
    NAMEPLATE_UNITS[unit] = true
end
mod.NAMEPLATE_TOKENS, mod.NAMEPLATE_UNITS = NAMEPLATE_TOKENS, NAMEPLATE_UNITS

-- Every bucket Bucket() can answer; a feature's filter offers all or some.
MTWhere.LOCATION_KEYS = {
    "open_world",
    "raid_mythic",
    "raid_heroic",
    "raid_normal_lfr",
    "dungeon_mythic",
    "dungeon_nonmythic",
    "timewalking",
    "delve",
    "lair",
    "scenario",
    "arena",
    "battleground",
}

-- A feature's buckets: the list its filter walks, and a set to look one up.
-- Made once per feature when its file loads.
function MTWhere.NewKeySet(keys)
    local set = {}
    for _, key in ipairs(keys) do
        set[key] = true
    end
    return { list = keys, set = set }
end

--------------------------------------------------------------------------------
--  The content bucket
--------------------------------------------------------------------------------
-- Difficulty id -> bucket, by instance type (ids the tables do not name fall
-- through to the open-world test at the end).
local BY_DIFFICULTY = {
    party = {
        [23] = "dungeon_mythic", -- Mythic
        [8] = "dungeon_mythic", -- Mythic Keystone
        [1] = "dungeon_nonmythic", -- Normal
        [2] = "dungeon_nonmythic", -- Heroic
        [205] = "dungeon_nonmythic", -- Follower
        [24] = "timewalking",
    },
    raid = {
        [16] = "raid_mythic",
        [233] = "raid_mythic",
        [15] = "raid_heroic",
        [6] = "raid_heroic", -- legacy 25 heroic
        [14] = "raid_normal_lfr",
        [17] = "raid_normal_lfr", -- LFR
        [3] = "raid_normal_lfr", -- legacy 10 / 25 / 10 heroic / LFR
        [4] = "raid_normal_lfr",
        [5] = "raid_normal_lfr",
        [7] = "raid_normal_lfr",
        [33] = "timewalking",
    },
}
-- Instance types that are one bucket whatever the difficulty.
local BY_TYPE = { arena = "arena", pvp = "battleground" }

local function Bucket()
    if
        C_ChallengeMode
        and C_ChallengeMode.IsChallengeModeActive
        and C_ChallengeMode.IsChallengeModeActive()
    then
        return "dungeon_mythic"
    end
    -- Housing plots report as a scenario; they belong to the open world.
    if C_Housing and C_Housing.IsInsideHouseOrPlot and C_Housing.IsInsideHouseOrPlot() then
        return "open_world"
    end
    local _, kind, difficulty, _, _, _, _, _, _, _, worldTier = GetInstanceInfo()
    difficulty = tonumber(difficulty) or 0
    -- Lairs carry the World Tier flag instead of a known difficulty; only
    -- inside an instance, so the flag never reclassifies the open world.
    if worldTier == true and kind ~= "none" then
        return "lair"
    end
    local byDifficulty = BY_DIFFICULTY[kind]
    if byDifficulty then
        local bucket = byDifficulty[difficulty]
        if bucket then
            return bucket
        end
    elseif kind == "scenario" then
        return difficulty == 208 and "delve" or "scenario"
    elseif BY_TYPE[kind] then
        return BY_TYPE[kind]
    end
    if IsInInstance and not IsInInstance() then
        return "open_world"
    end
    return nil -- content not mapped: it always shows, as in AuraBuffReminders
end
MTWhere.Bucket = Bucket

--------------------------------------------------------------------------------
--  Combat: followed from PLAYER_REGEN_DISABLED / _ENABLED rather than read at
--  each check. A live lockdown read is the one input that can answer
--  differently (or as a secret) inside restricted instanced combat, and a
--  wrong answer there switches a feature off for the whole fight. The edges
--  are exact, so a read is only needed at login, zoning and arming.
--------------------------------------------------------------------------------
local inCombat = false

local function ReadCombat()
    if not InCombatLockdown then
        return false
    end
    local ok, value = pcall(InCombatLockdown)
    if not ok then
        return false
    end
    if issecretvalue then
        local checked, secret = pcall(issecretvalue, value)
        if checked and secret then
            return false
        end
    end
    return value and true or false
end

function MTWhere.InCombat()
    return inCombat
end

--------------------------------------------------------------------------------
--  The filter: nothing ticked shows everywhere. Ticked buckets limit WHERE,
--  the two combat ticks limit WHEN, and both must pass. Content not mapped,
--  and a bucket the feature does not offer, never hide.
--------------------------------------------------------------------------------
function MTWhere.Shows(filter, keySet)
    if not filter or not next(filter) then
        return true
    end
    local inTicked, outTicked = filter.in_combat == true, filter.out_of_combat == true
    -- Exactly one ticked: it must match (both or neither = either state).
    if inTicked ~= outTicked and inCombat ~= inTicked then
        return false
    end
    local anyPlace = false
    for _, key in ipairs(keySet.list) do
        if filter[key] == true then
            anyPlace = true
            break
        end
    end
    if not anyPlace then
        return true
    end
    local bucket = Bucket()
    if not bucket or not keySet.set[bucket] then
        return true
    end
    return filter[bucket] == true
end

--------------------------------------------------------------------------------
--  The shared watcher: one frame for every subscriber, registered only while
--  there is one. Each zone or combat change updates the combat flag first,
--  then calls every subscriber with the event's name.
--------------------------------------------------------------------------------
local EVENTS = {
    "PLAYER_ENTERING_WORLD",
    "CHALLENGE_MODE_START",
    "CHALLENGE_MODE_COMPLETED",
    "CHALLENGE_MODE_RESET",
    "PLAYER_DIFFICULTY_CHANGED",
    "ZONE_CHANGED_NEW_AREA",
    "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED",
}

local callbacks, keys, slotOf = {}, {}, {} -- [i] = fn; [i] = its key; key -> i

-- Walked backwards: a subscriber that leaves from inside its own call moves
-- the last one (already called) into its place. Each call is protected, so
-- one feature's error is reported and the rest still hear the event.
local securecallfunction = securecallfunction
local function Tell(event)
    for i = #callbacks, 1, -1 do
        local fn = callbacks[i]
        if fn then
            securecallfunction(fn, event)
        end
    end
end

-- On the first frame after a loading screen GetInstanceInfo() can still
-- describe the PREVIOUS zone, which would leave a feature off in a zone its
-- filter allows (AuraBuffReminders waits 0.5s for the same reason). So
-- everyone is told once more ("RECHECK") when the client has settled; a
-- feature changes only if its answer did.
local recheckQueued = false
local function Recheck()
    recheckQueued = false
    Tell("RECHECK")
end

local watcher -- made by the first subscriber

local function OnEvent(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
    elseif event == "PLAYER_ENTERING_WORLD" then
        inCombat = ReadCombat()
    end
    Tell(event)
    if event == "PLAYER_ENTERING_WORLD" and not recheckQueued then
        recheckQueued = true
        C_Timer.After(0.5, Recheck)
    end
end

-- Subscribing again under the same key replaces the function. The first
-- subscriber arms the watcher and reads the combat state; the combat events
-- keep it right from there.
function MTWhere.Subscribe(key, fn)
    if not fn then
        MTWhere.Unsubscribe(key)
        return
    end
    local slot = slotOf[key]
    if slot then
        callbacks[slot] = fn
        return
    end
    slot = #callbacks + 1
    callbacks[slot], keys[slot], slotOf[key] = fn, key, slot
    if slot == 1 then
        if not watcher then
            watcher = CreateFrame("Frame")
            watcher:SetScript("OnEvent", OnEvent)
        end
        inCombat = ReadCombat()
        for _, event in ipairs(EVENTS) do
            watcher:RegisterEvent(event)
        end
    end
end

-- The last subscriber leaving disarms the watcher.
function MTWhere.Unsubscribe(key)
    local slot = slotOf[key]
    if not slot then
        return
    end
    local last = #callbacks
    callbacks[slot], keys[slot] = callbacks[last], keys[last]
    slotOf[keys[slot]] = slot
    callbacks[last], keys[last] = nil, nil
    slotOf[key] = nil
    if last == 1 then
        watcher:UnregisterAllEvents()
    end
end
