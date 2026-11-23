-- Forever: Gear Score (CludesUIForeverEssentials_GearScore.lua). A level 30
-- character wearing a full set of level 30 epics but a level 25 blue
-- two-hander (main hand, nothing in the off hand): the score, its share of
-- the level's goal (epics of level 35), a full epic set scoring its own
-- level, an empty set scoring 0; the inspect sheet's line for another
-- player; the character sheet's line. Each step's state is written as ==
-- lines.
local CUI = rawget(_G, "CludesUI")
local GS = CUI and CUI._GearScore
OUT:write("== gear score " .. tostring(GS ~= nil) .. "\n")
if not GS then return end
local S = GS.Score
CludesUIDB.gearScore = { enabled = true }
GS.Apply()

-- link = "L<level>Q<quality>[T]" (T: two-hander)
rawset(C_Item, "GetDetailedItemLevelInfo", function(link) return tonumber(link:match("L(%d+)")) end)
rawset(C_Item, "GetItemInfo", function(link) return "x", link, tonumber(link:match("Q(%d)")) end)
rawset(C_Item, "GetItemInfoInstant", function(link)
    return 1, "", "", link:find("T$") and "INVTYPE_2HWEAPON" or "INVTYPE_HEAD"
end)
local gear = {}
for _, slot in ipairs({ 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 18 }) do
    gear[slot] = "L30Q4"
end
gear[16] = "L25Q3T"
rawset(_G, "GetInventoryItemLink", function(unit, slot)
    if unit == "player" then return gear[slot] end
    return slot ~= 16 and slot ~= 17 and "L20Q2" or nil
end)
rawset(_G, "UnitLevel", function() return 30 end)

local function Plain(text) return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local score = S.Unit("player")
local text, share = S.Text(score, 30)
OUT:write(("== player: %.2f -> %s %s (goal %.1f)\n"):format(score, Plain(text), Plain(share), S.Goal(30)))
local full = {}
for _, slot in ipairs({ 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }) do
    full[slot] = "L30Q4"
end
OUT:write(("== full epic 30 set: %.2f | empty: %.2f\n"):format(S.Links(full), S.Links({})))
local r, g, b = S.Colour(1)
OUT:write(("== colour at the goal: %.2f %.2f %.2f; at 50%%: %.2f %.2f %.2f\n"):format(r, g, b, S.Colour(0.5)))

-- The inspect sheet's line: another level 30 in level 20 greens, no weapons.
rawset(_G, "UnitExists", function() return true end)
rawset(_G, "UnitGUID", function(unit) return unit == "player" and "Player-1" or "Player-2" end)
OUT:write("== inspect line: " .. Plain(tostring(CUI.GearScoreLine("target"))) .. "\n")

-- The character sheet's line.
local sheet = rawget(_G, "CharacterFrame")
if sheet then
    if not rawget(_G, "CharacterLevelText") then
        rawset(_G, "CharacterLevelText", sheet:CreateFontString(nil, "OVERLAY"))
    end
    sheet:Hide()
    sheet:Show()
    local line = GS.SheetText()
    OUT:write("== character sheet: " .. Plain(tostring(line)) .. "\n")
end
