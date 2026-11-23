-- Powershifting on the Forever druid mana bar (CUI_ResourceBars_ForeverDruidMana.lua):
-- the shift cost mark at the end of the mana, the shifts-left count, the
-- missing mana below one shift, a form change re-reading the cost, and the
-- toggles. Run as a druid: COMPARE_CLASS=DRUID.
local CUI = rawget(_G, "CludesUI")
local mod = CUI._ModuleNS.CludesUIResourceBars
OUT:write("== fdm " .. tostring(mod and mod.FDM_Apply ~= nil) .. "\n")
if not (mod and mod.FDM_Apply) then return end

local MANA = Enum.PowerType.Mana
local form, costs = 1, { [768] = 300, [5487] = 450 }
GetShapeshiftForm = function() return form end
GetShapeshiftFormInfo = function(i) return 0, true, true, i == 1 and 768 or 5487 end
C_Spell.GetSpellPowerCost = function(id)
    return costs[id] and { { type = MANA, cost = costs[id] } } or {}
end
_G._CURB_GetPrimaryPowerType = function() return MANA + 100 end
HARNESS_POWER = { 1000, 2000 }

local profile = mod.ERB.db.profile
local c = profile.primary.foreverDruidMana
profile.primary.enabled = true
c.enabled = true
mod.FDM_Apply()
local host = mod.FDM_Host()
OUT:write("== host " .. tostring(host ~= nil) .. "\n")
if not host then return end
host._sb:SetSize(200, 6)
-- The Power Bar's visibility pass shows it (the harness never runs one).
mod.FDM_Visibility(true)

local function F(n) return n and ("%.1f"):format(n) or "-" end
local function Mark(tex)
    if not (tex and tex:IsShown()) then return "off" end
    return ("x=%s w=%s"):format(F(select(4, tex:GetPoint(1))), F(tex:GetWidth()))
end
-- The marks are the bar's 2nd and 3rd textures (after its background; cost
-- first), the count is the FontString anchored to the host's RIGHT.
local marks = { select(2, host._sb:GetRegions()) }
local shifts
for _, f in ipairs({ host:GetChildren() }) do
    for _, r in ipairs({ f:GetRegions() }) do
        if r.GetText and r:GetPoint(1) == "RIGHT" then shifts = r end
    end
end
local function State(tag)
    OUT:write(("== %s: cost %s | missing %s | shifts %s\n"):format(tag, Mark(marks[1]), Mark(marks[2]),
        shifts and shifts:IsShown() and tostring(shifts:GetText()) or "off"))
end
local function Mana(cur)
    HARNESS_POWER[1] = cur
    HARNESS_FIRE_EVENT("UNIT_POWER_FREQUENT", "player", "MANA")
end

Mana(1000)
State("cat, 1000/2000, cost 300")
Mana(350)
State("350: one shift")
Mana(120)
State("120: below a shift")
Mana(0)
State("empty")
form = 2
HARNESS_FIRE_EVENT("UNIT_DISPLAYPOWER", "player")
State("bear (cost 450), empty")
Mana(1000)
State("bear, 1000")
c.shiftMark = false
mod.FDM_Apply()
State("Shift Cost off")
c.shiftMark = nil
c.shiftsLeft = false
mod.FDM_Apply()
State("Shifts Left off")
c.shiftsLeft = nil
Mana(200)
c.warnLow = false
mod.FDM_Apply()
State("Missing Mana off, 200")
c.warnLow = nil
c.powershift = false
mod.FDM_Apply()
State("Powershifting off")
c.powershift = nil
mod.FDM_Apply()
State("back on")

-- The options page (Power Bar on): the Powershifting row sits after Mana Bar
-- while Shapeshifted, sharing Spell Cost Prediction's row.
CUI:SelectModule("CludesUIResourceBars")
CUI:SelectPage("Class, Power and Health Bars")
local labels = {}
local function Walk(f, d)
    if d > 14 then return end
    for _, r in ipairs({ f:GetRegions() }) do
        local t = r.GetText and r:GetText()
        if t == "Mana Bar while Shapeshifted" or t == "Powershifting" or t == "Spell Cost Prediction" then
            labels[#labels + 1] = t
        end
    end
    for _, ch in ipairs({ f:GetChildren() }) do Walk(ch, d + 1) end
end
Walk(CUI._scrollFrame, 0)
OUT:write("== page rows: " .. table.concat(labels, " | ") .. "\n")
