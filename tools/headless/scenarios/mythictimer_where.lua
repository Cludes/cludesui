-- Mythic+ Tools > Where to Show (MTWhere): the content bucket for every
-- instance type and difficulty, Shows() for each filter shape, and the shared
-- watcher (subscribe, replace, dispatch order, recheck, unsubscribe from
-- inside a callback, last one out). Prints results; no frames to snapshot.
local CUI = rawget(_G, "CludesUI")
local mod = CUI._ModuleNS.CludesUIMythicTimer
local W = mod.MTWhere
local function P(...) OUT:write(table.concat({ ... }, " "), "\n") end
if not W then P("== no MTWhere") return end

local info = { "", "none", 0, false }
local challenge, house, instanced = false, false, false
C_ChallengeMode.IsChallengeModeActive = function() return challenge end
C_Housing = C_Housing or {}
C_Housing.IsInsideHouseOrPlot = function() return house end
GetInstanceInfo = function() return info[1], info[2], info[3], nil, nil, nil, nil, nil, nil, nil, info[4] end
IsInInstance = function() return instanced end

local cases = {
    { "none", 0 }, { "party", 23 }, { "party", 8 }, { "party", 2 }, { "party", 1 }, { "party", 205 },
    { "party", 24 }, { "party", 99 }, { "raid", 16 }, { "raid", 233 }, { "raid", 15 }, { "raid", 6 },
    { "raid", 14 }, { "raid", 3 }, { "raid", 4 }, { "raid", 5 }, { "raid", 17 }, { "raid", 7 },
    { "raid", 33 }, { "raid", 98 }, { "scenario", 208 }, { "scenario", 12 }, { "arena", 0 }, { "pvp", 0 },
    { "party", "23" }, { "party", nil },
}
for _, c in ipairs(cases) do
    info = { "", c[1], c[2], false }
    instanced = c[1] ~= "none"
    P("== bucket", c[1], tostring(c[2]), tostring(W.Bucket()))
end
info = { "", "party", 0, true }
P("== lair", tostring(W.Bucket()))
info = { "", "none", 0, true }
instanced = false
P("== world tier in the open world", tostring(W.Bucket()))
house = true
info = { "", "scenario", 0, false }
P("== housing", tostring(W.Bucket()))
house = false
challenge = true
P("== challenge", tostring(W.Bucket()))
challenge = false

-- Shows: no filter, location only, combat only, both.
local keys = W.NewKeySet({ "open_world", "dungeon_mythic", "raid_mythic" })
info, instanced = { "", "party", 23, false }, true
local filters = {
    {}, { dungeon_mythic = true }, { open_world = true }, { delve = true },
    { in_combat = true }, { out_of_combat = true }, { in_combat = true, out_of_combat = true },
    { in_combat = true, dungeon_mythic = true }, { out_of_combat = true, open_world = true },
}
local fired = {}
W.Subscribe("scenario", function(evt) fired[#fired + 1] = evt end)
for _, combat in ipairs({ false, true }) do
    HARNESS_FIRE_EVENT(combat and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED")
    for i, f in ipairs(filters) do
        P("== shows combat=" .. tostring(combat) .. " filter " .. i, tostring(W.Shows(f, keys)), tostring(W.InCombat()))
    end
end
P("== shows nil", tostring(W.Shows(nil, keys)))
info = { "", "raid", 99, false }
P("== shows unmapped", tostring(W.Shows({ open_world = true }, keys)))

-- The watcher: three subscribers, one replaced, one leaving from its callback.
local order = {}
W.Subscribe("a", function(evt) order[#order + 1] = "a:" .. evt end)
W.Subscribe("b", function(evt)
    order[#order + 1] = "b:" .. evt
    W.Unsubscribe("b")
end)
W.Subscribe("c", function(evt) order[#order + 1] = "c:" .. evt end)
W.Subscribe("a", function(evt) order[#order + 1] = "a2:" .. evt end)
HARNESS_FIRE_EVENT("ZONE_CHANGED_NEW_AREA")
HARNESS_FIRE_EVENT("PLAYER_ENTERING_WORLD")
HARNESS_ADVANCE(1)
HARNESS_FIRE_EVENT("CHALLENGE_MODE_START")
P("== order", table.concat(order, ","))
W.Subscribe("c", nil)
W.Unsubscribe("a")
W.Unsubscribe("scenario")
W.Unsubscribe("nobody")
order = {}
HARNESS_FIRE_EVENT("ZONE_CHANGED_NEW_AREA")
P("== after all left", #order)
P("== scenario saw", table.concat(fired, ","))
P("== tokens", #mod.NAMEPLATE_TOKENS, tostring(mod.NAMEPLATE_UNITS.nameplate40), tostring(mod.NAMEPLATE_UNITS.nameplate41))
