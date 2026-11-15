-- Info Bar > Profession blocks (primary and secondary): names vs values, the
-- skill bar (hidden at max), custom vs game icons, no icon, hover and tooltip,
-- a left click, events that change nothing, a skill-up, and a vertical bar.
-- Counts drawing passes, which should not grow when nothing changed.
local CUI = rawget(_G, "CludesUI")
local mod = CUI._ModuleNS.CludesUIDataBars

local profs = {
    [1] = { "Mining", 136248, 80, 100, 0, 0, 186 },
    [2] = { "Blacksmithing", 136241, 100, 100, 0, 0, 164 },
    [4] = { "Fishing", 136245, 12, 300, 0, 0, 356 },
    [5] = { "Cooking", 133971, 300, 300, 0, 0, 185 },
}
GetProfessions = function() return 1, 2, nil, 4, 5 end
GetProfessionInfo = function(i)
    local p = profs[i]
    if p then return unpack(p) end
end
OPENED = {}
C_TradeSkillUI = {
    GetBaseProfessionInfo = function() return nil end,
    OpenTradeSkill = function(id) OPENED[#OPENED + 1] = id end,
    CloseTradeSkill = function() end,
}

DRAWS = 0
local setFont = mod.SetFont
mod.SetFont = function(...)
    DRAWS = DRAWS + 1
    return setFont(...)
end

local bar = mod.BarsInOrder()[1] or mod.CreateBar("empty")
local b = mod.AddBlock(bar.id, "profession")
b.settings = b.settings or {}
local function Bar() return rawget(_G, "CludesUIDataBarsBar" .. bar.id) end
local function Show(label)
    mod.ApplyBar(bar.id)
    SNAP(label, Bar())
end
local function Buttons()
    local found = {}
    local stack = { Bar() }
    while #stack > 0 do
        local f = table.remove(stack)
        if type(f) == "table" and rawget(f, "\0children") then
            if f["\0kind"] == "Button" and f["\0scripts"].OnEnter and f["\0shown"] then found[#found + 1] = f end
            for _, c in ipairs(f["\0children"]) do stack[#stack + 1] = c end
        end
    end
    table.sort(found, function(x, y) return (x["\0name"] or "") < (y["\0name"] or "") end)
    return found
end

Show("prof names")
b.settings.textDisplay = "values"
Show("prof values")
b.settings.textDisplay = nil
b.settings.iconStyle = "wow"
Show("prof wow icons")
b.settings.iconStyle = nil
b.settings.showIcon = false
Show("prof no icon")
b.settings.showIcon = nil
Show("prof icon back")

local h = Buttons()[1]
h["\0scripts"].OnEnter(h)
SNAP("prof hovered", Bar())
SNAP("prof tooltip", rawget(_G, "CludesUIDataBarsTip"))
h["\0scripts"].OnLeave(h)
SNAP("prof left", Bar())
if h["\0scripts"].OnClick then h["\0scripts"].OnClick(h, "LeftButton") end
OUT:write("== opened: ", table.concat(OPENED, ","), "\n")

-- Events that change nothing, then a skill-up.
local before = DRAWS
HARNESS_FIRE_EVENT("SPELLS_CHANGED")
HARNESS_FIRE_EVENT("TRADE_SKILL_DETAILS_UPDATE")
HARNESS_FIRE_EVENT("SKILL_LINES_CHANGED")
OUT:write("== draws for 3 events with no change: ", DRAWS - before, "\n")
profs[1][3] = 81
HARNESS_FIRE_EVENT("SKILL_LINES_CHANGED")
SNAP("prof skill up", Bar())

-- The secondary block.
mod.AddBlock(bar.id, "profession2")
Show("prof with secondary")
local hs = Buttons()
local last = hs[#hs]
last["\0scripts"].OnEnter(last)
SNAP("prof secondary tooltip", rawget(_G, "CludesUIDataBarsTip"))
last["\0scripts"].OnLeave(last)

-- A profession dropped.
profs[2] = nil
HARNESS_FIRE_EVENT("SKILL_LINES_CHANGED")
SNAP("prof one dropped", Bar())

bar.orientation = "V"
Show("prof vertical")
bar.orientation = "H"
mod.ApplyBar(bar.id)
