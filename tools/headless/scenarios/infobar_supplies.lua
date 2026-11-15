-- Info Bar > Class Resources block (WoW Forever only), as a rogue: flash and
-- blinding powder, poisons by rank (one too high a level), a thrown weapon by
-- durability, labels, no icons, a hidden item, hover and tooltip, bag updates
-- that change nothing, a count change, a shot that leaves the stack alone,
-- item data arriving, and a vertical bar. Counts drawing passes.
local CUI = rawget(_G, "CludesUI")
local mod = CUI._ModuleNS.CludesUIDataBars

UnitClass = function() return "Rogue", "ROGUE", 4 end
UnitLevel = function() return 40 end
NUM_TOTAL_EQUIPPED_BAG_SLOTS = 4
BreakUpLargeNumbers = tostring
Enum.ItemClass.Projectile, Enum.ItemClass.Weapon = 6, 2
Enum.ItemWeaponSubclass.Thrown, Enum.ItemWeaponSubclass.Bows = 16, 2
Enum.ItemWeaponSubclass.Guns, Enum.ItemWeaponSubclass.Crossbow = 3, 18

local SLOTS = { AmmoSlot = 0, RangedSlot = 18 }
GetInventorySlotInfo = function(name) return SLOTS[name] end
local equipped = { [18] = 3137 } -- a thrown weapon
local durability = { 80, 100 }
GetInventoryItemID = function(_, slot) return equipped[slot] end
GetInventoryItemCount = function(_, slot) return equipped[slot] and 1 or 0 end
GetInventoryItemTexture = function() return nil end
GetInventoryItemDurability = function() return durability[1], durability[2] end

local INFO = { -- class, subclass, required level
    [3137] = { 2, 16, 1 }, [5140] = { 0, 0, 1 }, [5530] = { 0, 0, 1 },
    [6947] = { 0, 0, 20 }, [6949] = { 0, 0, 28 }, [6950] = { 0, 0, 44 },
    [2892] = { 0, 0, 30 }, [5060] = { 0, 0, 1 },
}
local NAMES = { [3137] = "Deadly Throwing Axe", [5140] = "Flash Powder", [5530] = "Blinding Powder",
    [6947] = "Instant Poison", [6949] = "Instant Poison II", [6950] = "Instant Poison III",
    [2892] = "Deadly Poison", [5060] = "Thieves' Tools" }
C_Item.GetItemInfoInstant = function(id)
    local i = INFO[id]
    if i then return id, nil, nil, nil, nil, i[1], i[2] end
end
C_Item.GetItemInfo = function(id)
    local i = INFO[id]
    if i then return NAMES[id], nil, nil, nil, i[3] end
end
C_Item.GetItemNameByID = function(id) return NAMES[id] end
C_Item.GetItemIconByID = function(id) return "Interface\\Icons\\Item" .. id end
C_Item.RequestLoadItemDataByID = function() end
C_Item.GetItemCount = function() return 1 end

local bags = { [0] = { { 5140, 12 }, { 6947, 5 }, { 6950, 3 }, { 5060, 1 } }, [1] = { { 5140, 8 }, { 2892, 10 } } }
C_Container.GetContainerNumSlots = function(bag) return bags[bag] and #bags[bag] or 0 end
C_Container.GetContainerItemID = function(bag, slot) return bags[bag] and bags[bag][slot] and bags[bag][slot][1] end
C_Container.GetContainerItemInfo = function(bag, slot)
    local s = bags[bag] and bags[bag][slot]
    if s then return { stackCount = s[2] } end
end
local known = { [1856] = true, [1804] = true, [8681] = true, [8687] = true, [2835] = true }
C_SpellBook.IsSpellKnown = function(id) return known[id] or false end

DRAWS = 0
local setFont = mod.SetFont
mod.SetFont = function(...)
    DRAWS = DRAWS + 1
    return setFont(...)
end

local bar = mod.BarsInOrder()[1] or mod.CreateBar("empty")
local b = mod.AddBlock(bar.id, "supplies")
b.settings = b.settings or {}
local function Bar() return rawget(_G, "CludesUIDataBarsBar" .. bar.id) end
local function Show(label)
    mod.ApplyBar(bar.id)
    SNAP(label, Bar())
end
local function Hit()
    local found
    local stack = { Bar() }
    while #stack > 0 do
        local f = table.remove(stack)
        if type(f) == "table" and rawget(f, "__children") then
            if f.__kind == "Button" and f.__scripts.OnEnter then found = f end
            for _, c in ipairs(f.__children) do stack[#stack + 1] = c end
        end
    end
    return found
end

Show("supplies rogue")
b.settings.showLabel = true
Show("supplies labels")
b.settings.showLabel = nil
b.settings.showIcon = false
Show("supplies no icons")
b.settings.showIcon = nil
b.settings.hiddenItems = { [5530] = true }
Show("supplies blinding hidden")
b.settings.hiddenItems = nil
Show("supplies all again")

local h = Hit()
h.__scripts.OnEnter(h)
SNAP("supplies hovered", Bar())
SNAP("supplies tooltip", rawget(_G, "CludesUIDataBarsTip"))
h.__scripts.OnLeave(h)
SNAP("supplies left", Bar())

-- Bag updates that change nothing (looting a grey, moving an unrelated item).
local before = DRAWS
HARNESS_FIRE_EVENT("BAG_UPDATE_DELAYED")
HARNESS_FIRE_EVENT("BAG_UPDATE_DELAYED")
HARNESS_FIRE_EVENT("GET_ITEM_INFO_RECEIVED", 99999, true)
OUT:write("== draws for bag updates with no change: ", DRAWS - before, "\n")
-- A vanish: one flash powder used.
bags[0][1][2] = 11
HARNESS_FIRE_EVENT("BAG_UPDATE_DELAYED")
SNAP("supplies flash used", Bar())
-- A throw: durability down; an unrelated inventory change ignored.
durability[1] = 79
HARNESS_FIRE_EVENT("UPDATE_INVENTORY_DURABILITY")
SNAP("supplies thrown used", Bar())
before = DRAWS
HARNESS_FIRE_EVENT("UNIT_INVENTORY_CHANGED", "player")
OUT:write("== draws for an inventory change that is not the stack: ", DRAWS - before, "\n")

bar.orientation = "V"
Show("supplies vertical")
bar.orientation = "H"
mod.ApplyBar(bar.id)
