-- Builds CludesUIRaidLead/CludesUIRaidLead_BossData.lua from a Northern Sky Raid
-- Tools folder: the boss names, every boss's ability timeline by difficulty,
-- and the timed encounter alerts. The timeline files and each boss's alert
-- set-up run here against a stand-in that records what they add; nothing of
-- theirs runs in game.
-- Usage: luajit tools/build-boss-data.lua <NorthernSkyRaidTools dir> <out>
local src, out = arg[1], arg[2]
assert(src and out, "usage: luajit tools/build-boss-data.lua <NorthernSkyRaidTools dir> <out>")

-- A stand-in that takes any read, write or call.
local function Proxy()
    local p = {}
    return setmetatable(p, {
        __index = function(t, k) local v = Proxy(); rawset(t, k, v); return v end,
        __call = function() return Proxy() end,
    })
end

local alerts = {}
local NSI = Proxy()
NSI.BossTimelines = {}
NSI.InitializeAlerts = {}
function NSI:DefaultLoadConditions() return { Roles = {}, Classes = {}, SpecIDs = {}, Names = {} } end
function NSI:EncounterAlertLoc(key) return key end
function NSI:Loc(key) return key end
function NSI:AddEncounterAlert(data) alerts[#alerts + 1] = data end
function NSI:GetSortedPhaseKeys(t)
    local keys = {}
    for k in pairs(t or {}) do keys[#keys + 1] = k end
    table.sort(keys)
    return keys
end
_G.NSRT = Proxy()
_G.NSAPI = Proxy()
_G.CopyTable = function(t) return t end
_G.strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
_G.C_Spell = Proxy()

local function Run(path)
    local chunk = assert(loadfile(path))
    chunk("NorthernSkyRaidTools", NSI)
end

local base = src .. "/NorthernSkyRaidTools/"
Run(base .. "BossData.lua")
Run(base .. "BossTimelines/BossTimelines.lua")
local xml = assert(io.open(base .. "BossTimelines/BossTimelines.xml")):read("*a")
for file in xml:gmatch('<Script file="(Midnight[^"]+)"') do Run(base .. "BossTimelines/" .. file) end
local alertFiles = {}
for _, season in ipairs({ "MidnightS1", "MidnightS2" }) do
    for file in io.popen('ls "' .. base .. "EncounterAlerts/" .. season .. '"'):lines() do
        if file:match("%.lua$") then alertFiles[#alertFiles + 1] = base .. "EncounterAlerts/" .. season .. "/" .. file end
    end
end
table.sort(alertFiles)
for _, path in ipairs(alertFiles) do Run(path) end
for encID, init in pairs(NSI.InitializeAlerts) do
    if type(init) == "function" then
        local ok, err = pcall(init, NSI)
        if not ok then io.stderr:write("alerts " .. tostring(encID) .. ": " .. tostring(err) .. "\n") end
    end
end

-- Keep only plain timed alerts: text and timers per difficulty, nothing that
-- needs NSRT's own displays.
local KEEP = { "internalID", "name", "group", "text", "DisplayType", "encID", "phase", "TTS", "TTSTimer", "dur",
    "spellID", "countdown", "sound", "textColors", "barColors", "Ticks", "loadConditions", "isConditional" }
local kept = {}
local skipped = 0
for _, a in ipairs(alerts) do
    if type(a.timers) == "table" and next(a.timers) and type(a.encID) == "number" then
        local k = {}
        for _, key in ipairs(KEEP) do
            local v = a[key]
            if type(v) ~= "table" or getmetatable(v) == nil then k[key] = v end
        end
        k.timers = a.timers
        if type(k.name) == "table" or type(k.group) == "table" then k.name, k.group = k.internalID, nil end
        if type(k.phase) == "table" then k.phase = k.phase[1] end
        kept[#kept + 1] = k
    else
        skipped = skipped + 1
    end
end
table.sort(kept, function(a, b)
    if a.encID ~= b.encID then return a.encID < b.encID end
    return tostring(a.internalID) < tostring(b.internalID)
end)

local function Key(k)
    if type(k) == "string" and k:match("^[%a_][%w_]*$") then return k end
    if type(k) == "string" then return ("[%q]"):format(k) end
    return "[" .. tostring(k) .. "]"
end

local function Value(v, indent)
    local t = type(v)
    if t == "string" then return ("%q"):format(v):gsub("\\\n", "\\n") end
    if t == "number" then
        if v == math.floor(v) then return tostring(v) end
        return ("%.4g"):format(v)
    end
    if t == "boolean" then return tostring(v) end
    if t ~= "table" then return "nil" end
    local n = #v
    local parts = {}
    for i = 1, n do parts[#parts + 1] = Value(v[i], indent .. "    ") end
    local keys = {}
    for k in pairs(v) do
        if not (type(k) == "number" and k >= 1 and k <= n and k == math.floor(k)) then keys[#keys + 1] = k end
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do
        local s = Value(v[k], indent .. "    ")
        if s ~= "nil" then parts[#parts + 1] = Key(k) .. " = " .. s end
    end
    return "{ " .. table.concat(parts, ", ") .. " }"
end

local lines = {
    "if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)",
    "if CludesUI and CludesUI.IS_FOREVER then return end -- retail only",
    "-------------------------------------------------------------------------------",
    "--  CludesUIRaidLead_BossData.lua -- GENERATED by tools/build-boss-data.lua",
    "--  Midnight raid bosses: names, ability timelines by difficulty (duration,",
    "--  phases with their default start, abilities with category and cast times",
    "--  from their phase's start), and timed encounter alerts per difficulty ID",
    "--  (15 Heroic, 16 Mythic).",
    "-------------------------------------------------------------------------------",
    "local _, ns = ...",
    "",
    "function ns.BossData()",
    "local D = {}",
    "D.names = " .. Value(NSI.BossNames, ""),
    "D.order = " .. Value(NSI.CurrentEncounterIDList, ""),
    "D.timelines = {",
}
local ids = {}
for id in pairs(NSI.BossTimelines) do ids[#ids + 1] = id end
table.sort(ids)
for _, id in ipairs(ids) do lines[#lines + 1] = ("    [%d] = %s,"):format(id, Value(NSI.BossTimelines[id], "    ")) end
lines[#lines + 1] = "}"
lines[#lines + 1] = "D.alerts = {"
for _, a in ipairs(kept) do lines[#lines + 1] = "    " .. Value(a, "    ") .. "," end
lines[#lines + 1] = "}"
lines[#lines + 1] = "return D"
lines[#lines + 1] = "end"
lines[#lines + 1] = ""
local text = table.concat(lines, "\r\n")
assert(not text:find("NSRT") and not text:find("Northern"), "an NSRT name was left")
local f = assert(io.open(out, "wb"))
f:write(text)
f:close()
print(("wrote %d bytes: %d timelines, %d alerts kept, %d without plain timers"):format(#text, #ids, #kept, skipped))
