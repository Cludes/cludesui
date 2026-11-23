-- Forever: Talent Builds (CludesUIForeverEssentials_TalentBuilds.lua). A
-- stand-in two-tree class: tree 1 has A (row 0, 5 ranks) and C (row 1, 3
-- ranks), tree 2 has B (row 0, 5 ranks). You hold A 2/5, B 1/5, 3 points
-- unspent. Save Current (row order: A, A, B), Export and Import it back; a
-- hand-made build "A x5, C x3"; follow it: the next talent, Learn spends the
-- 3 points (records PurchaseRank and the commit), the level-up line; the
-- window. Each step's state is written as == lines.
local CUI = rawget(_G, "CludesUI")
local TB = CUI and CUI._TalentBuilds
OUT:write("== talent builds " .. tostring(TB ~= nil) .. "\n")
if not TB then return end
local B = TB.Builds
CludesUIDB.talentBuilds = { enabled = true }
TB.Apply()

local ranks = { [101] = 2, [102] = 0, [201] = 1 }
local maxRanks = { [101] = 5, [102] = 3, [201] = 5 }
local spells = { [101] = 1001, [102] = 1002, [201] = 2001 }
local names = { [1001] = "Improved Strike", [1002] = "Deep Cuts", [2001] = "Toughness" }
local unspent = 3
local calls = {}
CUI.ForeverTalentTrees = function()
    return 7, 70, {
        { groupID = 1, name = "Arms", nodes = { 101, 102 } },
        { groupID = 2, name = "Guard", nodes = { 201 } },
    }
end
CUI.TalentTreeGrid = function(_, nodes)
    local cells = { [101] = { row = 0, col = 1 }, [102] = { row = 1, col = 1 }, [201] = { row = 0, col = 0 } }
    local out = {}
    for _, n in ipairs(nodes) do out[n] = cells[n] end
    return out
end
rawset(C_Traits, "GetNodeInfo", function(_, node)
    return { activeRank = ranks[node], maxRanks = maxRanks[node], entryIDs = { node * 10 } }
end)
rawset(C_Traits, "GetEntryInfo", function(_, entry) return { definitionID = entry } end)
rawset(C_Traits, "GetDefinitionInfo", function(def) return { spellID = spells[def / 10] } end)
rawset(C_Traits, "GetTreeCurrencyInfo", function() return { { quantity = unspent } } end)
rawset(C_Traits, "PurchaseRank", function(_, node)
    if unspent <= 0 or ranks[node] >= maxRanks[node] then return false end
    ranks[node], unspent = ranks[node] + 1, unspent - 1
    calls[#calls + 1] = "buy " .. node
    return true
end)
rawset(C_Traits, "RollbackConfig", function() calls[#calls + 1] = "rollback" end)
rawset(C_ClassTalents, "CommitConfig", function(id) calls[#calls + 1] = "commit " .. tostring(id); return true end)
rawset(C_ClassTalents, "GetLastSelectedSavedConfigID", function() return nil end)
rawset(C_Spell, "GetSpellName", function(id) return names[id] end)
rawset(C_Spell, "GetSpellTexture", function() return 134400 end)

local function Points(build)
    local out = {}
    for i, n in ipairs(build.points) do out[i] = n end
    return table.concat(out, ",")
end

local saved = B.FromCurrent("Mine")
OUT:write("== save current: " .. Points(saved) .. "\n")
B.Add(saved)
local line = B.Export(saved)
OUT:write("== export: " .. line:gsub("^CUIB1:%d+:", "CUIB1:<class>:") .. "\n")
local back, why = B.Import(line)
OUT:write("== import back: " .. tostring(back and (back.name .. " " .. Points(back)) or why) .. "\n")
OUT:write("== import junk: " .. tostring(select(2, B.Import("hello"))) .. "\n")

local plan = { name = "Strike", points = { 101, 101, 101, 101, 101, 102, 102, 102 } }
B.Add(plan)
B.Follow(plan)
local node, at = B.Next(plan, 7)
OUT:write(("== following %s: next %s (point %s), unspent %d\n"):format(
    tostring(B.Followed() and B.Followed().name), tostring(B.TalentName(7, node)), tostring(at), B.Unspent()))

local said = {}
local realPrint = CUI.Print
CUI.Print = function(text) said[#said + 1] = (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local learned = B.Learn(plan)
OUT:write(("== learn: %d -> %s | A %d/5 C %d/3 unspent %d\n"):format(learned, table.concat(calls, ", "), ranks[101], ranks[102], unspent))
unspent = 1
HARNESS_FIRE_EVENT("PLAYER_LEVEL_UP")
for _ = 1, 5 do HARNESS_ADVANCE(0.3) end
CUI.Print = realPrint
OUT:write("== level up: " .. table.concat(said, " / ") .. "\n")

SlashCmdList.CUITALENTBUILDS()
local win = rawget(_G, "CludesUITalentBuilds")
local rows = {}
for _, r in ipairs(win and win.rows or {}) do
    if r:IsShown() then rows[#rows + 1] = (r.name:GetText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) .. " [" .. r.right:GetText() .. "]" end
end
OUT:write(("== window: %s | %s\n   %s\n   next %s | %s\n"):format(
    tostring(win and win:IsShown()), tostring(win.sub:GetText()), table.concat(rows, "\n   "),
    tostring(win.nextName:GetText()), tostring(win.learn:GetText())))
SNAP("talent builds", win)
