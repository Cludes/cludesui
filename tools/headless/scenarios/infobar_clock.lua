-- Info Bar > Clock block: 12 and 24 hour, the resting and mail icons (each
-- on and off), hover and tooltip (saved instances, resets, mail), the minute
-- ticking over, mail events that change nothing, a change in combat and the
-- pass after it, a vertical bar, and a removed block (which should stop).
-- Counts drawing passes.
local CUI = rawget(_G, "CludesUI")
local mod = CUI._ModuleNS.CludesUIDataBars

local clock = { 14, 5 }
GetGameTime = function() return clock[1], clock[2] end
local cvars = { timeMgrUseLocalTime = "0", timeMgrUseMilitaryTime = "0" }
GetCVar = function(k) return cvars[k] or "1" end
local resting, mail, combat = true, false, false
IsResting = function() return resting end
HasNewMail = function() return mail end
InCombatLockdown = function() return combat end
GetNumSavedInstances = function() return 2 end
GetSavedInstanceInfo = function(i)
    if i == 1 then return "Liberation of Undermine", 1, 300000, 16, true, false end
    return "Old Raid", 2, 0, 14, false, false
end
GetQuestResetTime = function() return 7200 end
FULLDATE = "%1$s, %2$s %3$d, %4$d"
CALENDAR_WEEKDAY_NAMES = { "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" }
CALENDAR_FULLDATE_MONTH_NAMES = { "January", "February", "March", "April", "May", "June", "July",
    "August", "September", "October", "November", "December" }
C_DateAndTime.GetCurrentCalendarTime = function()
    return { year = 2026, month = 11, monthDay = 15, weekday = 1, hour = 14, minute = 5 }
end

DRAWS = 0
local setFont = mod.SetFont
mod.SetFont = function(...)
    DRAWS = DRAWS + 1
    return setFont(...)
end

local bar = mod.BarsInOrder()[1] or mod.CreateBar("empty")
local b = mod.AddBlock(bar.id, "clock")
b.settings = b.settings or {}
b.settings.localTime = false -- server time: the local clock is the real one
local function Bar() return rawget(_G, "CludesUIDataBarsBar" .. bar.id) end
local function Show(label)
    mod.ApplyBar(bar.id)
    SNAP(label, Bar())
end
local function Hoverable()
    local found
    local stack = { Bar() }
    while #stack > 0 do
        local f = table.remove(stack)
        if type(f) == "table" and rawget(f, "\0children") then
            if f["\0kind"] == "Button" and f["\0scripts"].OnEnter and f["\0shown"] then found = f end
            for _, c in ipairs(f["\0children"]) do stack[#stack + 1] = c end
        end
    end
    return found
end
local function Tick(n)
    for _ = 1, n do
        HARNESS_ADVANCE(1)
    end
end

Show("clock 12h resting")
b.settings.twentyFour = true
Show("clock 24h")
b.settings.twentyFour = nil
cvars.timeMgrUseMilitaryTime = "1"
Show("clock 24h from the game setting")
cvars.timeMgrUseMilitaryTime = "0"
mail = true
Show("clock mail")
b.settings.showMail = false
Show("clock mail hidden")
b.settings.showMail = nil
b.settings.showResting = false
Show("clock not resting shown")
b.settings.showResting = nil
clock = { 0, 7 }
Show("clock midnight")
clock = { 14, 5 }
Show("clock back")

local h = Hoverable()
h["\0scripts"].OnEnter(h)
SNAP("clock hovered", Bar())
SNAP("clock tooltip", rawget(_G, "CludesUIDataBarsTip"))
h["\0scripts"].OnLeave(h)
SNAP("clock left", Bar())

-- The heartbeat: seconds within a minute draw nothing, the minute draws.
local before = DRAWS
Tick(5)
OUT:write("== draws for 5 seconds, same minute: ", DRAWS - before, "\n")
clock = { 14, 6 }
Tick(1)
SNAP("clock 14:06", Bar())

-- Mailbox chatter that changes nothing, then the mail being read.
before = DRAWS
HARNESS_FIRE_EVENT("MAIL_INBOX_UPDATE")
HARNESS_FIRE_EVENT("MAIL_INBOX_UPDATE")
HARNESS_FIRE_EVENT("UPDATE_PENDING_MAIL")
OUT:write("== draws for 3 mail events with no change: ", DRAWS - before, "\n")
mail = false
HARNESS_FIRE_EVENT("UPDATE_PENDING_MAIL")
SNAP("clock mail read", Bar())

-- Combat: the minute and leaving rest; the layout follows on regen.
combat = true
clock = { 14, 7 }
resting = false
HARNESS_FIRE_EVENT("PLAYER_UPDATE_RESTING")
Tick(1)
SNAP("clock in combat", Bar())
combat = false
HARNESS_FIRE_EVENT("PLAYER_REGEN_ENABLED")
SNAP("clock after combat", Bar())
resting = true
HARNESS_FIRE_EVENT("PLAYER_UPDATE_RESTING")
SNAP("clock resting again", Bar())

bar.orientation = "V"
Show("clock vertical")
bar.orientation = "H"
mod.ApplyBar(bar.id)

-- Removed: it should stop ticking and listening.
mod.RemoveBlock(bar.id, b.id)
mod.ApplyBar(bar.id)
before = DRAWS
clock = { 14, 8 }
Tick(2)
HARNESS_FIRE_EVENT("UPDATE_PENDING_MAIL")
OUT:write("== draws after the block was removed: ", DRAWS - before, "\n")
