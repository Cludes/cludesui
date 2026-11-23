-- Forever: Trade Enchants (CludesUIForeverEssentials_TradeEnchants.lua).
-- An enchanter knows three enchants: Minor Health to bracers (7418), Minor
-- Health and Lesser Mana to chest (7420, 7426). The trade partner whispered a
-- link to 7426, then puts a cloth chest in the "Will not be traded" slot:
-- the panel lists the two chest enchants, 7426 first and marked asked for,
-- each Enchant button set to click the trade slot. Each step's state is
-- written as == lines.
local CUI = rawget(_G, "CludesUI")
local TEm = CUI and CUI._TradeEnchants
OUT:write("== trade enchants " .. tostring(TEm ~= nil) .. "\n")
if not TEm then return end
local TE = TEm.TE

CludesUIDB.professions = { enabled = true, tradeEnchants = true, craftWindow = true }
CUI._Professions.Apply()

local recipes = {
    [7418] = { recipeID = 7418, name = "Enchant Bracer - Minor Health", icon = 1, learned = true, maxTrivialLevel = 50 },
    [7420] = { recipeID = 7420, name = "Enchant Chest - Minor Health", icon = 1, learned = true, maxTrivialLevel = 50 },
    [7426] = { recipeID = 7426, name = "Enchant Chest - Minor Absorption", icon = 1, learned = true, maxTrivialLevel = 70 },
}
local T = C_TradeSkillUI
rawset(T, "GetAllRecipeIDs", function() return { 7418, 7420, 7426 } end)
rawset(T, "GetRecipeInfo", function(id) return recipes[id] end)
rawset(T, "IsTradeSkillLinked", function() return false end)
rawset(T, "IsTradeSkillGuild", function() return false end)
rawset(T, "IsNPCCrafting", function() return false end)
rawset(T, "GetChildProfessionInfo", function() return nil end)
rawset(T, "GetBaseProfessionInfo", function() return { professionID = 333, professionName = "Enchanting", skillLevel = 80, maxSkillLevel = 150 } end)
rawset(T, "GetRecipeSchematic", function() return { reagentSlotSchematics = {} } end)
local crafted = {}
rawset(T, "CraftRecipe", function(id) crafted[#crafted + 1] = id end)
rawset(C_SpellBook, "IsSpellKnown", function(id) return id == 13262 end)
-- A cloth chest: armour (4), cloth (1), chest (5).
rawset(C_Item, "GetItemInfoInstant", function() return 1, "", "", "INVTYPE_CHEST", 1, 4, 1 end)
rawset(C_Item, "GetItemInventoryTypeByID", function() return 5 end)
rawset(_G, "GetTradeTargetItemLink", function(slot) return slot == 7 and "item:1" or nil end)
rawset(_G, "UnitGUID", function(unit) return unit == "NPC" and "Player-1-0001" or "Player-1-0000" end)
rawset(_G, "SpellIsTargeting", function() return false end)
rawset(_G, "TRADE_ENCHANT_SLOT", 7) -- the game's value; the fake client names unknown constants

local frame = ProfessionsFrame
if frame then frame:Show() end

-- The whisper with a link, then the trade.
HARNESS_FIRE_EVENT(
    "CHAT_MSG_WHISPER",
    "can you do |cffffffff|Henchant:7426|h[Enchant Chest - Minor Absorption]|h|r?",
    "Thrall", "", "", "", "", 0, 0, "", 0, 1, "Player-1-0001"
)
OUT:write("== asked: " .. tostring(TE.Asked("Player-1-0001", 7426)) .. " " .. tostring(TE.Asked("Player-1-0001", 7420)) .. "\n")
HARNESS_FIRE_EVENT("TRADE_SHOW")
HARNESS_FIRE_EVENT("TRADE_TARGET_ITEM_CHANGED", 7)
for _ = 1, 6 do HARNESS_ADVANCE(0.05) end
local panel = rawget(_G, "CludesUITradeEnchants")
local rows = {}
for _, row in ipairs(panel and panel.rows or {}) do
    if row:IsShown() then
        rows[#rows + 1] = row.name:GetText() .. " [" .. tostring(row.note:GetText()) .. "] -> " .. tostring(row.button.recipeID)
    end
end
OUT:write(("== panel: shown=%s note=%s\n   %s\n"):format(
    tostring(panel and panel:IsShown()),
    tostring(panel and panel.note:GetText()),
    table.concat(rows, "\n   ")
))
if panel then SNAP("trade enchants", panel) end
-- Enchant: casts the first.
local first = panel and panel.rows[1]
if first then
    first.button:GetScript("PreClick")(first.button, "LeftButton")
    OUT:write("== enchant: crafted " .. table.concat(crafted, ",") .. " type=" .. tostring(first.button:GetAttribute("type")) .. "\n")
end
HARNESS_FIRE_EVENT("TRADE_CLOSED")
OUT:write("== closed: " .. tostring(panel and panel:IsShown()) .. "\n")
