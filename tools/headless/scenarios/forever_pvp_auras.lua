-- PvP Auras (CludesUIForeverEssentials_PvPAuras.lua): the target panel's
-- container (rows, caps, filters, unit), its buttons dressed at creation, a
-- size change waiting out restricted auras, the focus panel, an empty debuff
-- list switching its row off, the absorb text, and the Battleground
-- Countdown hanging the timer tracker from its holder and back.
local CUI = rawget(_G, "CludesUI")
local A = CUI._PvPAuras
OUT:write("== pvp auras " .. tostring(A ~= nil) .. "\n")
if not A then return end

-- A stand-in container: records what the module asks of it, and builds two
-- buttons per group through initializeFrame, as the engine does.
local containers = {}
local realCreate = CreateFrame
CreateFrame = function(kind, name, parent, template)
    if kind ~= "AuraContainer" then return realCreate(kind, name, parent, template) end
    local c = realCreate("Frame", name, parent)
    local rec = { groups = {}, order = {}, caps = {}, on = {}, filters = {}, buttons = {} }
    containers[#containers + 1] = { frame = c, rec = rec }
    function c:AddAuraGroup(key, filter, opts)
        rec.groups[key] = { filter = filter, opts = opts }
        rec.order[#rec.order + 1] = key
        rec.caps[key], rec.filters[key] = opts.maxFrameCount, opts.candidateFilters
        for _ = 1, 2 do
            local b = realCreate("Button", nil, c)
            local log = {}
            b.SetIcon = function(_, t) log.icon = t ~= nil end
            b.SetDurationCooldown = function(_, cd) log.cooldown = cd ~= nil end
            b.SetApplicationCount = function(_, fs) log.count = fs ~= nil end
            b.SetDurationText = function(_, fs, o) log.timer = (log.timer or 0) + 1; log.curve = o and o.textColor ~= nil end
            opts.initializeFrame(b)
            rec.buttons[#rec.buttons + 1] = { b = b, log = log }
        end
    end
    function c:SetAuraGroupMaxFrameCount(key, n) rec.caps[key] = n end
    function c:SetAuraGroupEnabled(key, on) rec.on[key] = on end
    function c:SetAuraGroupCandidateFilters(key, f) rec.filters[key] = f end
    function c:SetUnit(u) rec.unit = u end
    function c:SetEnabled(on) rec.enabled = on end
    function c:UpdateAllAuras() rec.updates = (rec.updates or 0) + 1 end
    return c
end
local secret = false
C_Secrets = { ShouldAurasBeSecret = function() return secret end }
C_UnitAuras.GetAuraDataByIndex = function() return nil end
UnitExists = function() return true end
UnitGetTotalAbsorbs = function() return 500 end
UnitIsUnit = function() return false end
UnitName = function(u) return u == "focus" and "Rogue Guy" or "Target Guy" end
_G.TimerTracker = realCreate("Frame", "TimerTracker", UIParent)
TimerTracker:SetAllPoints(UIParent)

local function Count(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end
local function Panel(i, tag)
    local e = containers[i]
    if not e then
        OUT:write("== " .. tag .. ": no container " .. i .. "\n")
        return
    end
    local r = e.rec
    local parts = {}
    for _, key in ipairs(r.order) do
        local f = r.filters[key] or {}
        parts[#parts + 1] = ("%s[%s cap=%s on=%s ids=%d max=%s magic=%s]"):format(key, r.groups[key].filter,
            tostring(r.caps[key]), tostring(r.on[key]), Count(f.includeSpellIDs), tostring(f.maxDuration),
            tostring(f.includeDispelTypes ~= nil))
    end
    local holder = e.frame:GetParent()
    OUT:write(("== %s: unit=%s enabled=%s shown=%s size=%sx%s | %s\n"):format(tag, tostring(r.unit), tostring(r.enabled),
        tostring(holder:IsShown()), tostring(holder:GetWidth()), tostring(holder:GetHeight()), table.concat(parts, " ")))
end
local function Button(i, tag)
    local r = containers[i].rec.buttons[1]
    local b, log = r.b, r.log
    OUT:write(("== %s: button %sx%s icon=%s cd=%s count=%s timer=%s curve=%s\n"):format(tag, tostring(b:GetWidth()),
        tostring(b:GetHeight()), tostring(log.icon), tostring(log.cooldown), tostring(log.count), tostring(log.timer),
        tostring(log.curve)))
end

local c = A.Cfg()
c.enabled = true
A.Apply()
OUT:write("== containers " .. #containers .. "\n")
Panel(1, "target panel")
Button(1, "target button")

-- Size change while auras are secret: the buttons wait, then restyle.
secret = true
c.size = 48
A.Apply()
Button(1, "size 48 while secret")
secret = false
HARNESS_FIRE_EVENT("PLAYER_REGEN_ENABLED")
-- The retry after a same-frame restricted answer (a second advance: one
-- advance can spend its whole timer budget on a chain of zero-delay timers).
HARNESS_ADVANCE(0.3)
HARNESS_ADVANCE(0.01)
Button(1, "after the restriction lifts")
Panel(1, "target panel at 48")

-- Debuffs on with nothing picked: the row stays off; a typed ID turns it on.
c.debuffs = true
A.Apply()
Panel(1, "debuffs on, none picked")
c.debuffExtra = "12294, 21551"
A.Apply()
Panel(1, "two typed IDs")
c.buffMagicOnly, c.buffLength = true, 60
c.cc = false
A.Apply()
Panel(1, "magic only, 60s, no cc")
c.cc, c.debuffs, c.debuffExtra, c.buffMagicOnly, c.buffLength = nil, nil, nil, nil, nil

-- The focus panel.
c.focus = true
A.Apply()
OUT:write("== containers " .. #containers .. "\n")
Panel(2, "focus panel")
HARNESS_FIRE_EVENT("PLAYER_FOCUS_CHANGED")
OUT:write("== focus updates " .. tostring(containers[2].rec.updates) .. "\n")
c.focus = nil
A.Apply()
Panel(2, "focus off")

-- Absorb text.
HARNESS_FIRE_EVENT("UNIT_ABSORB_AMOUNT_CHANGED", "target")
local holder = containers[1].frame:GetParent()
local absorbText
for _, ch in ipairs({ holder:GetChildren() }) do
    if ch.text then absorbText = ch.text:GetText() end
end
OUT:write("== absorb " .. tostring(absorbText) .. "\n")

-- Off.
c.enabled = nil
A.Apply()
Panel(1, "off")

-- Battleground Countdown.
local function Tracker(tag)
    local p, rel, rp, x, y = TimerTracker:GetPoint(1)
    OUT:write(("== %s: %s %s %s %s %s n=%d\n"):format(tag, tostring(p), tostring(rel and rel:GetName()), tostring(rp),
        tostring(x), tostring(y), TimerTracker:GetNumPoints()))
end
Tracker("countdown default")
A.CountdownCfg().enabled = true
A.Apply()
Tracker("movable countdown")
A.CountdownCfg().enabled = nil
A.Apply()
Tracker("back off")

-- The options page: Forever Tools > PvP gains the PvP Auras sections.
CUI:SelectModule("CludesUIForeverEssentials")
CUI:SelectPage("PvP")
local want = { ["PvP Auras"] = 0, ["Crowd Control"] = 0, ["Charge Stun"] = 0, ["Mortal Strike"] = 0,
    ["Movable Countdown"] = 0, ["Your Own Spell IDs"] = 0, ["Focus Panel"] = 0, ["PVP AURAS"] = 0 }
local function Walk(f, d)
    if d > 14 then return end
    for _, r in ipairs({ f:GetRegions() }) do
        local t = r.GetText and r:GetText()
        if t and want[t] then want[t] = want[t] + 1 end
    end
    for _, ch in ipairs({ f:GetChildren() }) do Walk(ch, d + 1) end
end
Walk(CUI._scrollFrame, 0)
local seen = {}
for k, v in pairs(want) do seen[#seen + 1] = k .. "=" .. v end
table.sort(seen)
OUT:write("== page: " .. table.concat(seen, " ") .. "\n")
