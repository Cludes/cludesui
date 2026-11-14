-------------------------------------------------------------------------------
--  NoteParser.lua -- Raid Lead: reads reminder notes.
--
--  Pure Lua with no game calls, so tools/test-raidlead.lua can run it.
--
--  A note is the timer text that raid planning sites export (wowutils,
--  wowaudit) and that Method Raid Tools notes use: one reminder per line, each
--  starting with a time from the pull.
--
--    {time:1:30} Bloodlust
--    {time:95} |cffc41e3aDeathknight|r {spell:48707}
--    {time:2:10,p2} soak            <- a phase timer: not usable, see below
--
--  What a line can carry:
--    {time:M:SS} or {time:S}   when, counted from the pull
--    names                      players the line is for; with no names it is
--                               for everyone
--    {tank} {healer} {dps}      everyone in that role
--    {everyone}                 everyone, even when names are present
--    {spell:ID}                 shown as the spell's name
--    {rt1}..{rt8}, {star} ...   raid markers
--    colour codes |cAARRGGBB..|r and textures |T..|t, removed from the text
--
--  Phase timers (",p2", ",SCS:..") count from an event inside the fight. 12.1
--  gives addons no phase or boss cast events, so those lines are skipped and
--  counted, never guessed at.
-------------------------------------------------------------------------------
if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local _, mod = ...
mod = mod or {}

local Parser = {}
mod.NoteParser = Parser

local MARKERS = {
    star = 1,
    circle = 2,
    diamond = 3,
    triangle = 4,
    moon = 5,
    square = 6,
    cross = 7,
    x = 7,
    skull = 8,
}

--- Seconds from "{time:...}" contents, or nil. "1:30" -> 90, "95" -> 95.
function Parser.Seconds(specInfo)
    local m, s = specInfo:match("^%s*(%d+):(%d+%.?%d*)%s*$")
    if m then
        return tonumber(m) * 60 + tonumber(s)
    end
    local only = specInfo:match("^%s*(%d+%.?%d*)%s*$")
    return only and tonumber(only) or nil
end

-- Splits a note into reminder chunks: each starts at a {time:...} tag and runs
-- to the next one or the end of the line. Works whether or not the pasted
-- text kept its line breaks.
local function Chunks(textValue)
    local result = {}
    textValue = textValue:gsub("\r", "\n")
    for lineTex in (textValue .. "\n"):gmatch("([^\n]*)\n") do
        local starts = {}
        local place = 1
        while true do
            local a = lineTex:find("{time:", place, true)
            if not a then
                break
            end
            starts[#starts + 1] = a
            place = a + 6
        end
        for idx, a in ipairs(starts) do
            local b = (starts[idx + 1] or (#lineTex + 1)) - 1
            result[#result + 1] = lineTex:sub(a, b)
        end
    end
    return result
end

--- The words of a line that could be player names: letters only (accented
--- letters included), 2 to 12 characters, an optional -Realm dropped.
function Parser.Words(textValue)
    local words = {}
    for wid in textValue:gmatch("[^%s%p%d]+[%-]?[^%s%p%d]*") do
        local name = wid:match("^([^%-]+)") or wid
        if #name >= 2 then
            words[#words + 1] = name
        end
    end
    return words
end

--- Parses a note. `spellName(id)` (optional) turns {spell:ID} into a name.
--- Returns a list of { at = seconds, text = shown text, raw = line, names =
--- {lowercase names} or nil, roles = { TANK = true, ... } or nil,
--- everyone = bool }, sorted by time, and the number of phase lines skipped.
function Parser.Parse(textValue, spellName)
    local entries, skipped = {}, 0
    for _, chunk in ipairs(Chunks(textValue or "")) do
        local specInfo, rest = chunk:match("^{time:([^}]*)}(.*)$")
        if specInfo then
            local timePart, extra = specInfo:match("^([^,]*),(.*)$")
            if extra then
                skipped = skipped + 1
            else
                local at = Parser.Seconds(specInfo)
                if at then
                    local record = { at = at, raw = chunk }
                    local body = rest
                    -- Tags that pick who the line is for.
                    body = body:gsub("{(%a+)}", function(tag)
                        local t = tag:lower()
                        if t == "everyone" then
                            record.everyone = true
                            return ""
                        end
                        if t == "tank" or t == "tanks" then
                            record.roles = record.roles or {}
                            record.roles.TANK = true
                            return ""
                        end
                        if t == "healer" or t == "healers" or t == "heal" then
                            record.roles = record.roles or {}
                            record.roles.HEALER = true
                            return ""
                        end
                        if t == "dps" or t == "damager" then
                            record.roles = record.roles or {}
                            record.roles.DAMAGER = true
                            return ""
                        end
                        local mark = MARKERS[t]
                        if mark then
                            return "{rt" .. mark .. "}"
                        end
                        return "{" .. tag .. "}"
                    end)
                    -- Spells become their names.
                    body = body:gsub("{spell:(%d+)}", function(ident)
                        local num = spellName and spellName(tonumber(ident))
                        return num or ""
                    end)
                    -- Names are read from the coloured text before colours go.
                    body = body:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
                    local nameList
                    for _, wid in ipairs(Parser.Words((body:gsub("{rt%d}", " ")))) do
                        nameList = nameList or {}
                        nameList[#nameList + 1] = wid:lower()
                    end
                    record.names = nameList
                    record.text = body:gsub("^[%s%-:]+", ""):gsub("%s+$", ""):gsub("%s%s+", " ")
                    if record.text ~= "" then
                        entries[#entries + 1] = record
                    end
                end
            end
        end
    end
    table.sort(entries, function(a, b)
        return a.at < b.at
    end)
    return entries, skipped
end

--- Whether a parsed reminder is for this player. `me` is the player's name
--- (any case), `role` "TANK"/"HEALER"/"DAMAGER", `roster` a set of every
--- group member's lowercase name.
---
--- A line naming nobody in the group is for everyone; a line naming group
--- members is for them only (other words on the line, like "soak", are not
--- group members and so do not count).
function Parser.IsFor(record, me, role, roster)
    if record.everyone then
        return true
    end
    if record.roles and role and record.roles[role] then
        return true
    end
    local mine = me and me:lower()
    local namedSomeone = false
    for _, num in ipairs(record.names or {}) do
        if roster and roster[num] then
            namedSomeone = true
            if num == mine then
                return true
            end
        end
    end
    if record.roles then
        return false
    end
    return not namedSomeone
end

return Parser
