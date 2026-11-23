-- Forever: the Disenchant tools (CludesUIForeverEssentials_Disenchant.lua).
-- Bags: a green level-24 sword, two copies of a blue level-40 chest and a
-- white shirt (not disenchantable). /cde opens the window: three slots, the
-- secure button pointed at the next one; right-click keeps one chest,
-- shift-right-click keeps every sword; a click on Disenchant All waits for
-- the bags; a refusal skips the item. The sword's tooltip line at scanned
-- prices (dust 10s, essence 30s, shard 60s): about 44s 88c after the cut,
-- needs 25. Each step's state is written as == lines.
local CUI = rawget(_G, "CludesUI")
local DE = CUI and CUI._Disenchant
OUT:write("== disenchant " .. tostring(DE ~= nil) .. "\n")
if not DE then return end
rawset(_G, "GetCoinTextureString", function(c) return c .. "c" end)
if C_CurrencyInfo then rawset(C_CurrencyInfo, "GetCoinTextureString", function(c) return c .. "c" end) end

CludesUIDB.professions = { enabled = true, disenchant = true, disenchantTooltip = true }
CludesUIDB.market = {
    enabled = true,
    houses = {
        [GetRealmName() .. "-" .. UnitFactionGroup("player")] = {
            time = GetServerTime(),
            prices = { [10940] = 1000, [10998] = 3000, [10978] = 6000 },
            listed = {},
        },
    },
}
CUI._Professions.Apply()

-- itemID = { classID, quality, level, equip }
local ITEMS = {
    [15210] = { 2, 2, 24, "INVTYPE_WEAPON", "Raider Shortsword" },
    [15295] = { 4, 3, 40, "INVTYPE_CHEST", "Quillward Harness" },
    [45] = { 4, 1, 5, "INVTYPE_BODY", "Squire's Shirt" },
}
local bag = { [1] = 15210, [2] = 15295, [3] = 15295, [4] = 45 }
rawset(C_Container, "GetContainerNumSlots", function(b) return b == 0 and 4 or 0 end)
rawset(C_Container, "GetContainerItemInfo", function(b, s)
    local id = b == 0 and bag[s]
    if not id then return nil end
    return { itemID = id, quality = ITEMS[id][2], hyperlink = "[" .. ITEMS[id][5] .. "]", iconFileID = 1, stackCount = 1 }
end)
rawset(C_Item, "GetItemInfoInstant", function(id)
    local i = ITEMS[id]
    if i then return id, "", "", i[4], 1, i[1] end
end)
rawset(C_Item, "GetItemQualityByID", function(id) return ITEMS[id] and ITEMS[id][2] end)
rawset(C_Item, "GetItemInfo", function(id)
    local i = ITEMS[id]
    if i then return i[5], "[" .. i[5] .. "]", i[2], i[3], 1, "", "", 1, i[4], 1, 100, i[1] end
end)
rawset(C_Item, "GetItemGUID", function(loc) return "Item-" .. loc.bag .. "-" .. loc.slot end)
rawset(_G, "ItemLocation", {
    CreateFromBagAndSlot = function(_, b, s)
        return { bag = b, slot = s, IsValid = function() return true end }
    end,
})
rawset(C_SpellBook, "IsSpellKnown", function(id) return id == 13262 end)
rawset(C_Spell, "GetSpellName", function(id) return id == 13262 and "Disenchant" or "?" end)
rawset(_G, "GetProfessions", function() return 1 end)
rawset(_G, "GetProfessionInfo", function() return "Enchanting", 1, 20, 75, 0, 0, 333, 0 end)
local targeting = false
rawset(_G, "SpellIsTargeting", function() return targeting end)

SlashCmdList.CUIDISENCHANT()
HARNESS_ADVANCE(0.1)
local win = rawget(_G, "CludesUIDisenchantWindow")
local all = rawget(_G, "CludesUIDisenchantAll")
local function Report(label)
    local shown = {}
    for _, child in ipairs(win.grid["\0children"] or {}) do
        if child:IsShown() and child.record then
            shown[#shown + 1] = child.record.link .. (child.mark:IsShown() and " (keep)" or "") .. (child.next:IsShown() and " (next)" or "")
        end
    end
    OUT:write(
        ("== %s: shown=%s | %s | %s | target %s/%s %s\n   %s\n"):format(
            label,
            tostring(win and win:IsShown()),
            tostring(win.summary:GetText()),
            tostring(all.label:GetText()),
            tostring(all:GetAttribute("target-bag")),
            tostring(all:GetAttribute("target-slot")),
            tostring(all:GetAttribute("macrotext")):gsub("\n", " / "),
            table.concat(shown, "; ")
        )
    )
end
Report("opened")
SNAP("disenchant window", win)

local function Slot(index)
    local n = 0
    for _, child in ipairs(win.grid["\0children"] or {}) do
        if child.record then
            n = n + 1
            if n == index then return child end
        end
    end
end
-- Right-click keeps the first chest; shift-right-click every sword.
Slot(2):GetScript("OnClick")(Slot(2), "RightButton")
local realShift = IsShiftKeyDown
rawset(_G, "IsShiftKeyDown", function() return true end)
Slot(1):GetScript("OnClick")(Slot(1), "RightButton")
rawset(_G, "IsShiftKeyDown", realShift)
Report("kept")

-- Disenchant All: waits for the bags, then the next.
all:GetScript("PreClick")(all, "LeftButton")
all:GetScript("PostClick")(all, "LeftButton")
Report("clicked")
bag[3] = nil
HARNESS_FIRE_EVENT("BAG_UPDATE_DELAYED")
Report("disenchanted")

-- Keep off again for the chest, then a refusal: skipped.
Slot(2):GetScript("OnClick")(Slot(2), "RightButton")
all:GetScript("PreClick")(all, "LeftButton")
targeting = true
local said = {}
local realPrint = CUI.Print
CUI.Print = function(text) said[#said + 1] = text end
all:GetScript("PostClick")(all, "LeftButton")
targeting = false
CUI.Print = realPrint
Report("refused")
OUT:write("== said: " .. table.concat(said, " / ") .. "\n")

-- Tooltip lines.
for _, id in ipairs({ 15210, 15295, 45 }) do
    local left, right = DE.Values.TooltipLine(id)
    OUT:write(("== tooltip %d: %s | %s\n"):format(id, tostring(left), tostring(right):gsub("|", "!")))
end
