-- Runs the Raid Lead note parser outside the game:  luajit tools/test-notes.lua
local ns = {}
assert(loadfile("CludesUIRaidLead/NoteParser.lua"))("CludesUIRaidLead", ns)
local P = ns.NoteParser

local function spellName(id)
    return ({ [48707] = "Anti-Magic Shell", [31821] = "Aura Mastery" })[id]
end

local checks = 0
local function eq(a, b, what)
    checks = checks + 1
    if a ~= b then error(("%s: expected %s, got %s"):format(what, tostring(b), tostring(a)), 2) end
end

eq(P.Seconds("1:30"), 90, "minutes")
eq(P.Seconds("95"), 95, "seconds")
eq(P.Seconds("0:07"), 7, "leading zero")
eq(P.Seconds("abc"), nil, "not a time")

local note = table.concat({
    "{time:1:30} Bloodlust",
    "{time:95} |cffc41e3aJimmy|r {spell:48707}",
    "{time:0:20} {tank} Taunt",
    "{time:2:10,p2} soak",
    "{time:40}{healer} |cfff58cbaSally|r {spell:31821} {time:41} {everyone} spread",
    "no time here",
    "{time:3:00} {skull} kill adds",
}, "\n")

local list, skipped = P.Parse(note, spellName)
eq(skipped, 1, "phase lines skipped")
eq(#list, 6, "reminders found")
eq(list[1].at, 20, "sorted first")
eq(list[1].text, "Taunt", "tag removed from text")
eq(list[1].roles.TANK, true, "tank tag")
eq(list[2].at, 40, "two timers on one line, first")
eq(list[2].text, "Sally Aura Mastery", "colour removed, spell named")
eq(list[3].at, 41, "two timers on one line, second")
eq(list[3].everyone, true, "everyone tag")
eq(list[4].text, "Bloodlust", "plain line")
eq(list[5].text, "Jimmy Anti-Magic Shell", "named line")
eq(list[6].text, "{rt8} kill adds", "marker kept")

local roster = { jimmy = true, sally = true, bob = true }
eq(P.IsFor(list[4], "Bob", "DAMAGER", roster), true, "a line naming nobody is for everyone")
eq(P.IsFor(list[5], "Jimmy", "TANK", roster), true, "named player sees it")
eq(P.IsFor(list[5], "Bob", "DAMAGER", roster), false, "others do not")
eq(P.IsFor(list[1], "Bob", "TANK", roster), true, "role tag reaches the role")
eq(P.IsFor(list[1], "Bob", "DAMAGER", roster), false, "role tag skips others")
eq(P.IsFor(list[2], "Sally", "DAMAGER", roster), true, "named in a role line")
eq(P.IsFor(list[3], "Bob", "DAMAGER", roster), true, "everyone tag")

-- Line breaks lost on paste: the time tags still split it.
local flat = note:gsub("\n", " ")
local list2, skipped2 = P.Parse(flat, spellName)
eq(#list2, 6, "same reminders without line breaks")
eq(skipped2, 1, "same phase lines without line breaks")

eq(#P.Parse("", spellName), 0, "empty note")
eq(#P.Parse(nil, spellName), 0, "no note")

print(("note parser: %d checks passed"):format(checks))
