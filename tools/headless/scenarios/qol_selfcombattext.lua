-- QoL > Self Combat Text: switched on, damage (hit and crit), heals, an
-- avoid, entering and leaving combat, each category off, abbreviated,
-- staggered and not, the fountain and static animations, down, a burst past
-- the pool, the vehicle unit, unlock-mode position save and clear, reset,
-- and switched off (Blizzard's text shown again).
local CUI = rawget(_G, "CludesUI")
local mod = CUI._ModuleNS.CludesUIQoL
local frames = {}
local make = CreateFrame
-- The fake client's animations are bare; these record what is set and played.
local function Anim(log)
    local a = { log = log }
    local function Set(field) return function(self, ...) self[field] = { ... } end end
    a.SetOffset, a.SetDuration, a.SetStartDelay = Set("offset"), Set("duration"), Set("delay")
    a.SetFromAlpha, a.SetToAlpha, a.SetCurveType = Set("from"), Set("to"), Set("curve")
    a.CreateControlPoint = function(self) local p = Anim(log); self.points = self.points or {}; self.points[#self.points + 1] = p; return p end
    return a
end
local function Group(fs)
    local g = { fs = fs, anims = {} }
    g.CreateAnimation = function(self, kind) local a = Anim(); a.kind = kind; self.anims[#self.anims + 1] = a; return a end
    g.SetScript = function(self, _, fn) self.onFinished = fn end
    g.Play = function(self) self.playing = true end
    g.Stop = function(self) self.playing = false end
    return g
end
CreateFrame = function(kind, name, parent, ...)
    local f = make(kind, name, parent, ...)
    if parent == UIParent then
        frames[#frames + 1] = f
        local cfs = f.CreateFontString
        f.CreateFontString = function(self, ...)
            local fs = cfs(self, ...)
            fs.CreateAnimationGroup = function(me) me.__group = Group(me); return me.__group end
            return fs
        end
    end
    return f
end
local info = { 1234, 5678 }
C_CombatText.GetCurrentEventInfo = function() return info[1], info[2] end
UNIT = {}
C_CombatText.SetActiveUnit = function(u) UNIT[#UNIT + 1] = u end
UnitHasVehicleUI = function() return false end
COMBAT_TEXT_DODGE, COMBAT_TEXT_PARRY, COMBAT_TEXT_ABSORB = "Dodge", "Parry", "Absorb"
ENTERING_COMBAT, LEAVING_COMBAT = "+Combat", "-Combat"
AbbreviateNumbers = function(n) return (n / 1000) .. "K" end
BreakUpLargeNumbers = tostring
CombatText = make("Frame", "CombatText", UIParent)
CombatText:Show()

mod.SCT_Set("enabled", true)
CreateFrame = make
local anchor
for _, f in ipairs(frames) do
    if f.__strata == "HIGH" or (f.GetFrameStrata and f:GetFrameStrata() == "HIGH") then anchor = f end
end
anchor = anchor or frames[#frames]
OUT:write("== Blizzard text shown: ", tostring(CombatText:IsShown()), " unit ", table.concat(UNIT, ","), "\n")
local function Fire(...)
    HARNESS_FIRE_EVENT("COMBAT_TEXT_UPDATE", ...)
end
local function Snap(label)
    SNAP(label, anchor)
    for _, c in ipairs(anchor["\0regions"] or {}) do
        local g = rawget(c, "__group")
        if g and g.playing then
            local parts = {}
            for _, a in ipairs(g.anims) do
                local o = a.offset and table.concat(a.offset, ",") or "-"
                local pts = {}
                for _, p in ipairs(a.points or {}) do pts[#pts + 1] = p.offset and table.concat(p.offset, ",") or "-" end
                parts[#parts + 1] = a.kind .. "(" .. o .. " d" .. tostring(a.duration and a.duration[1]) .. " s" .. tostring(a.delay and a.delay[1]) .. " [" .. table.concat(pts, " ") .. "])"
            end
            OUT:write("   anim ", table.concat(parts, " "), "\n")
        end
    end
end
Fire("DAMAGE")
Fire("SPELL_DAMAGE_CRIT")
Fire("HEAL")
Fire("PERIODIC_HEAL_CRIT")
Fire("SPELL_DODGE")
Fire("ABSORB")
Fire("UNKNOWN_TYPE")
HARNESS_FIRE_EVENT("PLAYER_REGEN_DISABLED")
Snap("sct mixed")
HARNESS_ADVANCE(1)
HARNESS_FIRE_EVENT("PLAYER_REGEN_ENABLED")
Snap("sct later")
mod.SCT_Set("abbreviate", true)
info = { 25000, 9000 }
Fire("DAMAGE")
Fire("HEAL")
Snap("sct abbreviated")
mod.SCT_Set("damage", false)
mod.SCT_Set("stagger", false)
Fire("DAMAGE")
Fire("PARRY")
Snap("sct no damage, no stagger")
mod.SCT_Set("anim", "fountain")
mod.SCT_Set("stagger", true)
for _ = 1, 4 do Fire("HEAL") end
Snap("sct fountain")
mod.SCT_Set("anim", "static")
mod.SCT_Set("direction", "down")
for _ = 1, 3 do Fire("HEAL_CRIT") end
Snap("sct static down")
for _ = 1, 15 do Fire("HEAL") end
Snap("sct burst")
mod.SCT_Set("heal", false)
mod.SCT_Set("avoid", false)
Fire("HEAL")
Fire("DODGE")
mod.SCT_Set("combat", false)
HARNESS_FIRE_EVENT("PLAYER_REGEN_DISABLED")
Snap("sct all off but on")
HARNESS_FIRE_EVENT("UNIT_ENTERED_VEHICLE", "player", true)
HARNESS_FIRE_EVENT("UNIT_EXITING_VEHICLE", "player")
OUT:write("== units ", table.concat(UNIT, ","), "\n")
-- Unlock mode: save a position, clear it.
local el
el = CUI._unlockRegisteredElements and CUI._unlockRegisteredElements.CUI_SelfCombatText
if el then
    local save, load, clear = el.savePos or el.savePosition, el.loadPos or el.loadPosition, el.clearPos or el.clearPosition
    save(nil, "CENTER", "CENTER", 10, 20)
    Snap("sct saved position")
    local pos = load()
    OUT:write("== loadPos ", tostring(pos and pos.x), "\n")
    clear()
    Snap("sct cleared position")
end
mod.SCT_Reset()
OUT:write("== after reset: enabled ", tostring(mod.SCT_Get("enabled")), " Blizzard shown ", tostring(CombatText:IsShown()), "\n")
mod.SCT_Set("enabled", true)
Fire("DAMAGE")
Snap("sct back on")
mod.SCT_Set("enabled", false)
OUT:write("== off: Blizzard shown ", tostring(CombatText:IsShown()), " anchor shown ", tostring(anchor:IsShown()), "\n")
