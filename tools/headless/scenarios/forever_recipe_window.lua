-- Forever: the recipe window (CludesUIForeverEssentials_CraftWindow.lua) over
-- the game's profession window. Professions and Recipe Window on; a stand-in
-- trade skill API with Blacksmithing 95/150 and three recipes you know (two
-- categories, one with a cooldown, one you can make 7 of), reagents in your
-- bags and bank. Shows the game's window and snapshots ours; picks a recipe
-- and presses Create All and Create (records the CraftRecipe calls); searches
-- by a reagent's name; the Have Materials filter; right-click favourites a
-- recipe; skill-up chances per row, the threshold line and the Best for
-- Skill-ups sort (the bracers and belt are coloured yellow/green by the game
-- but grey by the data, so they show no number); the Not learned tab and one recipe's source lines; the overview
-- page's cards. Each step's state is written as == lines.
local CUI = rawget(_G, "CludesUI")
local RW = CUI and CUI._RecipeWindow
OUT:write("== recipe window " .. tostring(RW ~= nil) .. "\n")
if not RW then return end

CludesUIDB.professions = { enabled = true, craftWindow = true, rankAlert = true }

local crafted = {}
local recipes = {
    [2662] = {
        recipeID = 2662,
        name = "Runed Copper Bracers",
        icon = 132605,
        learned = true,
        categoryID = 10,
        relativeDifficulty = 1,
    },
    [2663] = {
        recipeID = 2663,
        name = "Copper Chain Belt",
        icon = 132492,
        learned = true,
        categoryID = 11,
        relativeDifficulty = 2,
    },
    [2738] = {
        recipeID = 2738,
        name = "Copper Axe",
        icon = 132400,
        learned = true,
        categoryID = 11,
        relativeDifficulty = 2,
    },
}
local schematics = {
    [2662] = {
        outputItemID = 2854,
        quantityMin = 1,
        reagentSlotSchematics = {
            { quantityRequired = 10, reagents = { { itemID = 2840 } } },
            { quantityRequired = 3, reagents = { { itemID = 3470 } } },
        },
    },
    [2663] = {
        outputItemID = 2851,
        quantityMin = 1,
        reagentSlotSchematics = {
            { quantityRequired = 6, reagents = { { itemID = 2840 } } },
        },
    },
    [2738] = {
        outputItemID = 2845,
        quantityMin = 1,
        reagentSlotSchematics = {
            { quantityRequired = 6, reagents = { { itemID = 2880 } } },
        },
    },
}
local bags = { [2840] = 72, [3470] = 43, [2880] = 0 }
local bank = { [2840] = 5 }
local names = { [2840] = "Copper Bar", [3470] = "Rough Grinding Stone", [2880] = "Weak Flux" }

local T = C_TradeSkillUI
local function Set(name, fn) rawset(T, name, fn) end
Set("IsTradeSkillLinked", function() return false end)
Set("IsTradeSkillGuild", function() return false end)
Set("IsNPCCrafting", function() return false end)
Set("GetChildProfessionInfo", function() return nil end)
Set(
    "GetBaseProfessionInfo",
    function()
        return { professionID = 164, professionName = "Blacksmithing", skillLevel = 95, maxSkillLevel = 150 }
    end
)
Set("GetAllRecipeIDs", function() return { 2662, 2663, 2738 } end)
Set("GetRecipeInfo", function(id) return recipes[id] end)
Set(
    "GetCategoryInfo",
    function(id)
        return (
            { [10] = { name = "Mail Bracers", uiOrder = 1 }, [11] = { name = "Mail Belts", uiOrder = 2 } }
        )[id]
    end
)
Set("GetRecipeSchematic", function(id) return schematics[id] end)
Set(
    "GetRecipeRequirements",
    function(id) return { { name = "Anvil", met = true }, { name = "Blacksmith Hammer", met = id ~= 2738 } } end
)
Set("GetRecipeCooldown", function(id) return id == 2663 and 3600 or 0 end)
Set("GetRecipeDescription", function() return "" end)
Set("IsRecipeTracked", function() return false end)
Set("SetRecipeTracked", function() return true end)
Set("SetRecipeFavorite", function() end)
Set("GetRecipeLink", function(id) return "[" .. id .. "]" end)
local LINK = "|cffffd000|Htrade:Player-1-00000001:2018:164|h[Blacksmithing]|h|r"
local linkedTo
Set("CanTradeSkillListLink", function() return linkedTo == nil end)
Set("GetTradeSkillListLink", function() return LINK end)
Set("CraftRecipe", function(id, count) crafted[#crafted + 1] = id .. "x" .. tostring(count) end)
rawset(
    C_Item,
    "GetItemCount",
    function(id, includeBank) return (bags[id] or 0) + (includeBank and (bank[id] or 0) or 0) end
)
rawset(C_Item, "GetItemNameByID", function(id) return names[id] or ("Item " .. id) end)
rawset(C_Item, "GetItemIconByID", function() return 134400 end)
rawset(C_Item, "GetItemMaxStackSizeByID", function() return 20 end)
rawset(C_Container, "GetContainerNumSlots", function(bag) return bag == 0 and 16 or 0 end)
rawset(C_Container, "GetContainerNumFreeSlots", function(bag) return bag == 0 and 16 or 0, 0 end)
rawset(C_Container, "GetContainerItemInfo", function() return nil end)

local frame = ProfessionsFrame
OUT:write("== game frame " .. tostring(frame ~= nil) .. "\n")
if not frame then return end
frame.BookPage = nil
frame:Hide()
CUI._Professions.Apply()
HARNESS_ADVANCE(0.2)
frame:Show()
HARNESS_FIRE_EVENT("TRADE_SKILL_SHOW")
HARNESS_ADVANCE(0.5)

local win = rawget(_G, "CludesUIRecipeWindow")
local S, W = RW.State, RW.Window
local function Report(label)
    local rows = {}
    for _, row in ipairs(win and win.rows or {}) do
        if row:IsShown() and row.name:GetText() then
            rows[#rows + 1] = row.name:GetText() .. "|" .. tostring(row.count:GetText() or "")
        end
    end
    OUT:write(
        ("== %s: shown=%s game alpha=%s tab=%s selected=%s rows=[%s]\n"):format(
            label,
            tostring(win and win:IsShown()),
            tostring(frame:GetAlpha()),
            tostring(S.tab),
            tostring(S.selected),
            table.concat(rows, "; ")
        )
    )
    if win and win.detail:IsShown() then
        OUT:write(
            ("   detail: %s | %s | %s | %s | create all: %s\n"):format(
                tostring(win.detail.name:GetText()),
                tostring(win.detail.sub:GetText()),
                (tostring(win.detail.needs:GetText()):gsub("|", "!"):gsub("\n", " / ")),
                tostring(win.detail.reagents.rows[1].name:GetText())
                    .. " need "
                    .. tostring(win.detail.reagents.rows[1].need:GetText())
                    .. " bags "
                    .. tostring(win.detail.reagents.rows[1].bags:GetText())
                    .. " bank "
                    .. tostring(win.detail.reagents.rows[1].bank:GetText()),
                tostring(win.detail.createAll:GetText())
            )
        )
    end
end
Report("opened")
if not win then return end
SNAP("recipe window", win)

-- Pick the first recipe, Create All and Create 3.
local function RowNamed(text)
    for _, row in ipairs(win.rows) do
        if row:IsShown() and row.name:GetText() == text then return row end
    end
end
local row = RowNamed("Runed Copper Bracers")
if row then row:GetScript("OnClick")(row, "LeftButton") end
win.detail.createAll:GetScript("OnClick")(win.detail.createAll)
win.detail.qty:SetText("3")
win.detail.create:GetScript("OnClick")(win.detail.create)
OUT:write("== crafted: " .. table.concat(crafted, ", ") .. "\n")
Report("after create")

-- Pick the one with a cooldown.
row = RowNamed("Copper Chain Belt")
if row then row:GetScript("OnClick")(row, "LeftButton") end
Report("cooldown recipe")

-- Search by a reagent name, then clear.
local function Type(text)
    win.search:SetText(text)
    win.search:GetScript("OnTextChanged")(win.search, true)
end
Type("flux")
Report("search flux")
Type("")

-- Filters: Have Materials.
CludesUIDB.professions.windowFilters = { materials = true }
W.Render()
Report("have materials")
CludesUIDB.professions.windowFilters = {}
W.Render()

-- Right-click favourites the axe.
row = RowNamed("Copper Axe")
if row then row:GetScript("OnClick")(row, "RightButton") end
OUT:write("== favourite axe: " .. tostring(CludesUIDB.professions.favorites ~= nil) .. "\n")
CludesUIDB.professions.windowFilters = { favorite = true }
W.Render()
Report("favourites only")
CludesUIDB.professions.windowFilters = {}

-- Skill-ups: each row's chance, the picked recipe's threshold line, then the
-- Best for Skill-ups sort.
local function Chances(label)
    local rows = {}
    for _, r in ipairs(win.rows) do
        if r:IsShown() and r.name:GetText() then
            rows[#rows + 1] = r.name:GetText() .. "=" .. tostring(r.chance and r.chance:GetText() or "nil")
        end
    end
    OUT:write(("== %s: %s\n"):format(label, table.concat(rows, "; ")))
end
W.Render()
Chances("chances")
row = RowNamed("Runed Copper Bracers")
if row then row:GetScript("OnClick")(row, "LeftButton") end
OUT:write("== thresholds: " .. (tostring(win.detail.needs:GetText()):gsub("|", "!"):gsub("\n", " / ")) .. "\n")
CludesUIDB.professions.sortSkillUps = true
W.Render()
Chances("best for skill-ups")
CludesUIDB.professions.sortSkillUps = nil
W.Render()

-- Not learned tab and the first recipe's source lines.
win.tabs[2]:GetScript("OnClick")(win.tabs[2])
Report("not learned")
for _, r in ipairs(win.rows) do
    if r:IsShown() and r.entry and r.entry.unlearned and r.entry.unlearned.r.source == "trainer" then
        r:GetScript("OnClick")(r, "LeftButton")
        break
    end
end
local lines = {}
for _, line in ipairs(win.learn.lines) do
    if line:IsShown() then
        lines[#lines + 1] = (line.text:GetText() or ""):gsub("|", "!") .. (line.npc and " [pin]" or "")
    end
end
OUT:write(
    ("== learn: %s | %s\n   %s\n"):format(
        tostring(win.learn.name:GetText()),
        tostring(win.learn.req:GetText()),
        table.concat(lines, "\n   ")
    )
)

rawset(_G, "GetProfessions", function() return 1, 2 end)
rawset(_G, "GetProfessionInfo", function(i)
    if i == 1 then return "Blacksmithing", 136241, 95, 150, 0, 0, 164, 0 end
    return "Mining", 136248, 51, 150, 0, 0, 186, 0
end)

-- Title buttons: Link on your own profession; opening it saves your link for
-- your alts; Alts shows once another character on this realm has saved one.
local function Buttons(label)
    local shown = {}
    for _, child in ipairs({ win.head:GetChildren() }) do
        if child:IsShown() and child.GetText and child:GetText() then shown[#shown + 1] = child:GetText() end
    end
    OUT:write(("== %s: title=%s buttons=[%s]\n"):format(label, tostring(win.title:GetText()), table.concat(shown, ", ")))
end
win.tabs[1]:GetScript("OnClick")(win.tabs[1])
HARNESS_FIRE_EVENT("TRADE_SKILL_LIST_UPDATE")
HARNESS_ADVANCE(0.5)
Buttons("own")
local saved = {}
for guid, alt in pairs(CludesUIDB.professions.profLinks or {}) do
    for id, link in pairs(alt.links) do
        saved[#saved + 1] = tostring(guid ~= nil) .. " " .. tostring(alt.name) .. " " .. id .. " " .. tostring(link.name)
    end
end
OUT:write("== saved links: " .. table.concat(saved, "; ") .. "\n")
CludesUIDB.professions.profLinks["Player-1-00000002"] = {
    name = "Ironhide",
    class = "WARRIOR",
    realm = GetRealmName(),
    faction = UnitFactionGroup("player"),
    links = { [164] = { link = LINK, name = "Blacksmithing" } },
}
W.Render()
Buttons("with an alt")
local alts = {}
for _, alt in ipairs(RW.Alts.List()) do
    alts[#alts + 1] = alt.who .. " - " .. alt.prof
end
OUT:write("== alts: " .. table.concat(alts, "; ") .. "\n")
local refs = {}
local realRef = rawget(_G, "SetItemRef")
rawset(_G, "SetItemRef", function(target, _, button) refs[#refs + 1] = tostring(target) .. " " .. tostring(button) end)
RW.Alts.Open(RW.Alts.List()[1])
rawset(_G, "SetItemRef", realRef)
OUT:write("== open alt: " .. table.concat(refs, "; ") .. "\n")

-- Someone's Blacksmithing from a trade link: their name on the title, no
-- Not learned tab, no Create footer, no skill-up numbers, no Link button.
linkedTo = "Thrall"
Set("IsTradeSkillLinked", function() return true, linkedTo end)
HARNESS_FIRE_EVENT("TRADE_SKILL_DATA_SOURCE_CHANGED")
HARNESS_ADVANCE(0.5)
Buttons("linked")
Chances("linked chances")
OUT:write(
    ("== linked: shown=%s tab2=%s footer=%s track=%s selected=%s\n"):format(
        tostring(win:IsShown()),
        tostring(win.tabs[2]:IsShown()),
        tostring(win.detail.foot:IsShown()),
        tostring(win.detail.track:IsShown()),
        tostring(S.selected)
    )
)

-- A craft order to Thrall: 2x the bracers bringing the Copper Bar, 1x the
-- belt bringing nothing, a 2g 50s tip; Ask whispers (not grouped), Invite.
local sent = {}
local function Record(message, channel, _, to)
    sent[#sent + 1] = channel .. (to and (">" .. to) or "") .. ": " .. message:gsub("|", "!")
end
if C_ChatInfo then rawset(C_ChatInfo, "SendChatMessage", Record) end
rawset(_G, "SendChatMessage", Record)
local invited = {}
if C_PartyInfo then rawset(C_PartyInfo, "InviteUnit", function(who) invited[#invited + 1] = who end) end
rawset(_G, "InviteUnit", function(who) invited[#invited + 1] = who end)
local pane, col = win.detail, nil
row = RowNamed("Runed Copper Bracers")
if row then row:GetScript("OnClick")(row, "LeftButton") end
OUT:write(
    ("== order foot: shown=%s add=%s bankHead=%s\n"):format(
        tostring(pane.orderFoot and pane.orderFoot:IsShown()),
        tostring(pane.orderFoot and pane.orderFoot.add:GetText()),
        tostring(pane.reagents.bankHead:GetText())
    )
)
pane.orderFoot.qty:SetText("2")
pane.orderFoot.qty:GetScript("OnTextChanged")(pane.orderFoot.qty, true)
local check = pane.reagents.rows[1].bringCheck
check:GetScript("PreClick")(check)
check:GetScript("OnClick")(check)
pane.orderFoot.add:GetScript("OnClick")(pane.orderFoot.add)
row = RowNamed("Copper Chain Belt")
if row then row:GetScript("OnClick")(row, "LeftButton") end
pane.orderFoot.add:GetScript("OnClick")(pane.orderFoot.add)
col = win:GetParent() and nil
for _, child in ipairs({ win:GetChildren() }) do
    if child.invite then col = child end
end
local function Column(label)
    local rows = {}
    for _, r in ipairs(col.rows) do
        if r:IsShown() then rows[#rows + 1] = r.name:GetText() .. " (" .. r.sub:GetText() .. ")" end
    end
    OUT:write(
        ("== %s: shown=%s title=%s ask=%s rows=[%s] empty=%s\n"):format(
            label,
            tostring(col:IsShown()),
            tostring(col.title:GetText()),
            tostring(col.ask:GetText()),
            table.concat(rows, "; "),
            tostring(col.empty:IsShown() and col.empty:GetText())
        )
    )
end
Column("order")
col.tip:SetText("2g 50s")
col.tip:GetScript("OnEditFocusLost")(col.tip)
OUT:write("== tip: " .. tostring(col.tip:GetText()) .. "\n")
col.ask:GetScript("OnClick")(col.ask)
for _ = 1, 10 do HARNESS_ADVANCE(0.2) end
OUT:write("== sent:\n   " .. table.concat(sent, "\n   ") .. "\n")
Column("after ask")
col.invite:GetScript("OnClick")(col.invite)
OUT:write("== invited: " .. table.concat(invited, ", ") .. " / " .. tostring(sent[#sent]) .. "\n")
-- An alt's profession: no order column.
linkedTo = "Ironhide"
HARNESS_FIRE_EVENT("TRADE_SKILL_DATA_SOURCE_CHANGED")
HARNESS_ADVANCE(0.5)
OUT:write("== alt linked: column=" .. tostring(col:IsShown()) .. " title=" .. tostring(win.title:GetText()) .. "\n")

linkedTo = nil
Set("IsTradeSkillLinked", function() return false end)
HARNESS_FIRE_EVENT("TRADE_SKILL_DATA_SOURCE_CHANGED")
HARNESS_ADVANCE(0.5)
Buttons("own again")

-- Skill-up Plan: 95 to 150 from the axe and the trainer recipes in the data.
local planButton
for _, child in ipairs({ win.head:GetChildren() }) do
    if child.GetText and child:GetText() == "Skill-up Plan" then planButton = child end
end
planButton:GetScript("OnClick")(planButton)
local plan = RW.Plan.pane
local steps = {}
for _, r in ipairs(plan.rows) do
    if r:IsShown() then
        steps[#steps + 1] = r.name:GetText() .. " " .. r.range:GetText() .. " " .. r.crafts:GetText()
    end
end
OUT:write(
    ("== plan: shown=%s detail=%s | %s | %s | %s\n   %s\n"):format(
        tostring(plan:IsShown()),
        tostring(win.detail:IsShown()),
        tostring(plan.sub:GetText()),
        tostring(plan.total:GetText()),
        tostring(plan.more:GetText()),
        table.concat(steps, "\n   ")
    )
)
planButton:GetScript("OnClick")(planButton)
OUT:write("== plan closed: " .. tostring(plan:IsShown()) .. " detail=" .. tostring(win.detail:IsShown()) .. "\n")

-- The overview page: Blacksmithing 95/150 and Mining 51/150 learned.
local book = CreateFrame("Frame", nil, frame)
book.ProfessionsContentFrame = CreateFrame("Frame", nil, book)
frame.BookPage = book
book:Show()
W.Render()
CUI._RecipeWindow.Apply()
HARNESS_ADVANCE(0.5)
local cards = {}
for _, card in ipairs(win.book.cards) do
    cards[#cards + 1] = tostring(card.name:GetText())
        .. ":"
        .. tostring(card.bar:IsShown() and card.barText:GetText() or card.missing:GetText())
end
OUT:write("== book shown=" .. tostring(win.book:IsShown()) .. " cards: " .. table.concat(cards, "; ") .. "\n")

-- Closing the game's window hides ours and puts its alpha back.
frame:Hide()
HARNESS_ADVANCE(0.2)
OUT:write(
    ("== closed: ours shown=%s game alpha=%s\n"):format(tostring(win:IsShown()), tostring(frame:GetAlpha()))
)
