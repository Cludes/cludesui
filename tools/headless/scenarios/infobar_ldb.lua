-- Info Bar > Broker (LDB) block: no plugin picked, a plugin with text and
-- icon, label on, colours kept and stripped, value + suffix, no icon, Max
-- Width, hover for each tooltip route (own fallback, OnTooltipShow, the
-- plugin's OnEnter), updates the block draws and ones it ignores, a source
-- that registers later, combat's end, and a vertical bar. Counts drawing passes.
local CUI = rawget(_G, "CludesUI")
local mod = CUI._ModuleNS.CludesUIDataBars
local LDB = mod.GetLDB()

local obj = LDB:NewDataObject("TestBroker", {
    type = "data source",
    text = "|cff00ff0060|r fps",
    label = "Perf",
    icon = "Interface\\Icons\\INV_Misc_QuestionMark",
})

DRAWS = 0
local setFont = mod.SetFont
mod.SetFont = function(...)
    DRAWS = DRAWS + 1
    return setFont(...)
end

local bar = mod.BarsInOrder()[1] or mod.CreateBar("empty")
local b = mod.AddBlock(bar.id, "ldb")
b.settings = b.settings or {}
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
local function Hover(label, tip)
    local h = Hoverable()
    h["\0scripts"].OnEnter(h)
    SNAP(label, Bar())
    SNAP(label .. " tooltip", rawget(_G, tip or "CludesUIDataBarsTip"))
    h["\0scripts"].OnLeave(h)
end

Show("ldb no plugin")
Hover("ldb no plugin hover")
b.settings.source = "TestBroker"
Show("ldb plugin")
b.settings.showLabel = true
Show("ldb label")
b.settings.stripColors = false
Show("ldb colours kept")
b.settings.stripColors = nil
b.settings.showLabel = nil
b.settings.showIcon = false
Show("ldb no icon")
b.settings.showIcon = nil
Show("ldb icon back")
Hover("ldb fallback hover")

-- Updates: text (drawn), a key the block does not show (ignored), the same
-- text again, then value + suffix.
local before = DRAWS
obj.text = "59 fps"
SNAP("ldb text update", Bar())
obj.somethingElse = 3
obj.text = "59 fps"
OUT:write("== draws: one change then two that show nothing new: ", DRAWS - before, "\n")
obj.text = nil
obj.value = 42
obj.suffix = "ms"
SNAP("ldb value suffix", Bar())

-- Max Width: the block holds the width whatever the plugin says.
b.settings.maxWidth = 80
Show("ldb max width")
before = DRAWS
for i = 1, 5 do
    obj.text = "fps " .. (50 + i)
end
SNAP("ldb max width updates", Bar())
OUT:write("== draws for 5 updates at a max width: ", DRAWS - before, "\n")
b.settings.maxWidth = nil
mod.ApplyBar(bar.id)

-- The other tooltip routes.
obj.OnTooltipShow = function(tt) tt:AddLine("From the plugin") end
Hover("ldb gametip hover", "GameTooltip")
obj.OnTooltipShow = nil
ENTERED = 0
obj.OnEnter = function() ENTERED = ENTERED + 1 end
obj.OnLeave = function() end
Hover("ldb own hover")
OUT:write("== plugin OnEnter calls: ", ENTERED, "\n")
obj.OnEnter, obj.OnLeave = nil, nil

-- Combat's end with nothing owed.
before = DRAWS
HARNESS_FIRE_EVENT("PLAYER_REGEN_ENABLED")
OUT:write("== draws at combat end with nothing owed: ", DRAWS - before, "\n")

-- A source that is not there yet, then registers.
b.settings.source = "LateBroker"
Show("ldb late source missing")
LDB:NewDataObject("LateBroker", { type = "data source", text = "late" })
SNAP("ldb late source arrived", Bar())

b.settings.source = "TestBroker"
bar.orientation = "V"
Show("ldb vertical")
bar.orientation = "H"
mod.ApplyBar(bar.id)
