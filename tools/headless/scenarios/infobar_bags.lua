-- Info Bar > Bags block: every display mode, the icon, the low-space colour,
-- the reagent bag, a vertical bar, hover (tooltip) and the event gate.
local CUI = rawget(_G, "CludesUI")
local mod = CUI._ModuleNS.CludesUIDataBars

-- Known bags: backpack 16 slots / 3 free, bags 1-4 12 slots / 2 free, bag 3 a
-- profession bag (family 8, never counted), reagent bag 20 / 9 free.
local REAGENT = Enum.BagIndex.ReagentBag
local free = { [0] = 3, 2, 2, 2, 2, [REAGENT] = 9 }
local slots = { [0] = 16, 12, 12, 12, 12, [REAGENT] = 20 }
C_Container.GetContainerNumFreeSlots = function(bag) return free[bag] or 0, bag == 3 and 8 or 0 end
C_Container.GetContainerNumSlots = function(bag) return slots[bag] or 0 end
C_Container.GetBagName = function(bag) return "Bag " .. bag end

local bar = mod.BarsInOrder()[1] or mod.CreateBar("empty")
local frame = rawget(_G, "CludesUIDataBarsBar" .. bar.id)
local b = mod.AddBlock(bar.id, "bags")
local function Show(label)
    mod.ApplyBar(bar.id)
    SNAP(label, rawget(_G, "CludesUIDataBarsBar" .. bar.id))
end
local function Content()
    -- The newest block's button: the bag button is the only Button with OnClick in its content.
    local found
    local stack = { rawget(_G, "CludesUIDataBarsBar" .. bar.id) }
    while #stack > 0 do
        local f = table.remove(stack)
        if type(f) == "table" and rawget(f, "__children") then
            if f.__kind == "Button" and f.__scripts.OnClick and f.__scripts.OnEnter and f.__shown then found = f end
            for _, c in ipairs(f.__children) do stack[#stack + 1] = c end
        end
    end
    return found
end

Show("bags default")
for _, mode in ipairs({ "used", "usedTotal", "freeTotal", "free" }) do
    b.settings.value = mode
    Show("bags " .. mode)
end
b.settings.showIcon = false
Show("bags no icon")
b.settings.showIcon = true
b.settings.lowThreshold = 20
Show("bags low space")
b.settings.lowColor = { r = 0, g = 1, b = 0 }
Show("bags low custom colour")
b.settings.lowThreshold = 0
b.settings.reagent = true
Show("bags with reagent bag")

local btn = Content()
if btn then
    btn.__scripts.OnEnter(btn)
    SNAP("bags hovered", rawget(_G, "CludesUIDataBarsBar" .. bar.id))
    SNAP("bags tooltip", rawget(_G, "CludesUIDataBarsTip"))
    btn.__scripts.OnLeave(btn)
    SNAP("bags left", rawget(_G, "CludesUIDataBarsBar" .. bar.id))
end

-- Vertical bar.
bar.orientation = "V"
Show("bags vertical")

-- Bag events: a change redraws the number, an unchanged batch does not.
bar.orientation = "H"
mod.ApplyBar(bar.id)
local function FireBags()
    HARNESS_FIRE_EVENT("BAG_UPDATE_DELAYED")
end
free[0] = 0
FireBags()
SNAP("bags after looting", rawget(_G, "CludesUIDataBarsBar" .. bar.id))
FireBags()
SNAP("bags unchanged batch", rawget(_G, "CludesUIDataBarsBar" .. bar.id))
