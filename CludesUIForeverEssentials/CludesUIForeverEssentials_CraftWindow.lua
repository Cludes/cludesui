if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
if not (CUI and CUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_CraftWindow.lua  (WoW Forever only)
--  The recipe window: CludesUI's own window over the game's profession window
--  (Recipe Window, Professions on Forever Tools). The game's window stays the
--  crafting backend: it is kept open but invisible underneath, its profession
--  tabs are moved beside ours, and on its overview page its profession cards
--  (with their spell and unlearn buttons) are moved into ours.
--    Left:   search, Filter, Learned / Not learned, the recipe list
--            (categories, difficulty colours, how many you can make, favourites)
--    Right:  the picked recipe (reagents with bags and bank, requirements,
--            cooldown, room in your bags, Track, Create, Create All) or, for a
--            recipe not learned yet, what it needs and where to learn it
--    Top:    the profession, its skill bar, and a banner when the next rank is
--            ready to learn (click for its map pin)
--  Uses the Professions feature's recipe data (CludesUIForeverEssentials_
--  Professions.lua, module.Prof) for recipes you have not learned yet.
-------------------------------------------------------------------------------
local _, module = ...
local Prof = module.Prof
if not Prof then return end
local Kit = CUI.Kit
local F = Prof.F
local Get = F.Get

local LAYOUT = { W = 844, H = 620, HEAD = 52, LEFT = 318, ROW = Kit.ROW_H, PAD = 12, REAGENT = 34, MAX_REAGENTS = 8 }
local COLOUR = {
    muted = Kit.Palette.muted,
    text = Kit.Palette.text,
    red = Kit.Palette.red,
    green = Kit.Palette.green,
    line = Kit.Palette.line,
    panel = { 0.11, 0.12, 0.135 },
    sidebar = { 0.085, 0.093, 0.105 },
    -- the game's recipe difficulty colours: optimal, medium, easy, trivial
    difficulty = {
        [0] = { 1, 0.5, 0.25 },
        [1] = { 1, 0.82, 0 },
        [2] = { 0.25, 0.75, 0.25 },
        [3] = { 0.55, 0.55, 0.55 },
    },
}
local RANK_TITLE = { [75] = "Apprentice", [150] = "Journeyman", [225] = "Expert", [300] = "Artisan" }
local SOURCE_FILTERS = {
    { key = "trainer", text = "Trainer" },
    { key = "vendor", text = "Vendor" },
    { key = "drop", text = "Drop" },
    { key = "quest", text = "Quest" },
}
local LOGO = "Interface\\AddOns\\CludesUI\\media\\logo-full-thin.png"

local state = { query = "", tab = "learned", offset = 0, stale = true, collapsed = {} }
local win -- the window, built on first use

local function On() return F.Enabled() and Get("craftWindow") end

local function NewText(parent, size, colour, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    Kit.Font(fs, size, "essentials")
    local c = colour or COLOUR.text
    fs:SetTextColor(c[1], c[2], c[3])
    fs:SetWordWrap(false)
    return fs
end

local function Fill(parent, colour, alpha, layer)
    local tex = parent:CreateTexture(nil, layer or "BACKGROUND")
    tex:SetColorTexture(colour[1], colour[2], colour[3], alpha or 1)
    return tex
end

local function Paint(fs, colour) fs:SetTextColor(colour[1], colour[2], colour[3]) end

-------------------------------------------------------------------------------
--  The open profession and its recipes
-------------------------------------------------------------------------------
local Data = { reagents = {}, outputs = {}, waiting = {} }

function Data.Own()
    local T = C_TradeSkillUI
    if T.IsTradeSkillLinked and T.IsTradeSkillLinked() then return false end
    if T.IsTradeSkillGuild and T.IsTradeSkillGuild() then return false end
    if T.IsNPCCrafting and T.IsNPCCrafting() then return false end
    return true
end

-- Whose profession a trade link opened ("" when the game gives no name), or nil.
function Data.Linked()
    local T = C_TradeSkillUI
    if not T.IsTradeSkillLinked or (T.IsTradeSkillGuild and T.IsTradeSkillGuild()) then return end
    local linked, name = T.IsTradeSkillLinked()
    if linked then return name or "" end
end

-- The profession on show: its id, name, skill and cap (a child profession
-- such as a specialisation counts when it has a cap of its own).
function Data.Profession()
    local child, base = C_TradeSkillUI.GetChildProfessionInfo(), C_TradeSkillUI.GetBaseProfessionInfo()
    local src = (child and (child.maxSkillLevel or 0) > 0) and child or base
    if not src then return end
    return {
        id = base and base.professionID or src.professionID,
        parent = src.parentProfessionID,
        name = (base and base.professionName) or src.professionName or "",
        skill = src.skillLevel or 0,
        max = src.maxSkillLevel or 0,
        modifier = src.skillModifier or 0,
    }
end

-- The skill line the recipe data knows this profession by.
function Data.Line(prof)
    local all = Prof.RecipeData()
    if all[prof.id] then return prof.id end
    if prof.parent and all[prof.parent] then return prof.parent end
    for line, payload in pairs(all) do
        if prof.name == C_Spell.GetSpellName(payload.skillSpell) then return line end
    end
end

function Data.Reagents(recipeID)
    local cached = Data.reagents[recipeID]
    if cached then return cached end
    local list = {}
    local ok, schematic = pcall(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
    if ok and schematic and schematic.reagentSlotSchematics then
        for _, slot in ipairs(schematic.reagentSlotSchematics) do
            local reagent = slot.reagents and slot.reagents[1]
            if slot.required ~= false and reagent and reagent.itemID then
                list[#list + 1] = { itemID = reagent.itemID, need = slot.quantityRequired or 1 }
            end
        end
        Data.reagents[recipeID] = list
    end
    return list
end

-- What a recipe makes: item, fewest made, most made.
function Data.Output(recipeID)
    local cached = Data.outputs[recipeID]
    if cached then return cached[1], cached[2], cached[3] end
    local ok, schematic = pcall(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
    local itemID = ok and schematic and schematic.outputItemID
    if itemID and itemID > 0 then
        local made = math.max(1, schematic.quantityMin or 1)
        Data.outputs[recipeID] = { itemID, made, math.max(made, schematic.quantityMax or made) }
        return itemID, made, Data.outputs[recipeID][3]
    end
end

function Data.ItemName(itemID)
    local name = itemID and C_Item.GetItemNameByID(itemID)
    if itemID and not name and not Data.waiting[itemID] then
        Data.waiting[itemID] = true
        C_Item.RequestLoadItemDataByID(itemID)
    end
    return name
end

function Data.Bags(itemID) return C_Item.GetItemCount(itemID, false, false, true) or 0 end
function Data.Bank(itemID)
    return math.max(0, (C_Item.GetItemCount(itemID, true, false, true) or 0) - Data.Bags(itemID))
end

function Data.Craftable(info)
    if (info.numAvailable or 0) > 0 then return info.numAvailable end
    local reagents = Data.Reagents(info.recipeID)
    if #reagents == 0 then return 0 end
    local most = math.huge
    for _, reagent in ipairs(reagents) do
        most = math.min(most, math.floor(Data.Bags(reagent.itemID) / math.max(reagent.need, 1)))
    end
    return most
end

-- How many crafts the bags have room for. Each craft needs room for what it
-- makes (in a stack of it or a free slot that takes it); using up a reagent's
-- last stack frees that slot, smallest stacks first, as the game takes them.
function Data.BagRoom(recipeID, limit)
    local output, made = Data.Output(recipeID)
    if not output or limit < 1 then return limit end
    local stack = C_Item.GetItemMaxStackSizeByID and C_Item.GetItemMaxStackSizeByID(output)
        or select(8, C_Item.GetItemInfo(output))
    if not stack or stack < 1 then return limit end
    local family = C_Item.GetItemFamily and C_Item.GetItemFamily(output) or 0
    local reagents = Data.Reagents(recipeID)
    local stacks = {}
    for _, reagent in ipairs(reagents) do
        stacks[reagent.itemID] = {}
    end
    local free, room = 0, 0
    for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do
        local _, bagType = C_Container.GetContainerNumFreeSlots(bag)
        local takes = (bagType or 0) == 0 or bit.band(family, bagType) ~= 0
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local item = C_Container.GetContainerItemInfo(bag, slot)
            if not item then
                if takes then free = free + 1 end
            elseif item.itemID == output then
                if takes then room = room + math.max(0, stack - (item.stackCount or 0)) end
            elseif stacks[item.itemID] then
                local list = stacks[item.itemID]
                list[#list + 1] = { count = item.stackCount or 1, takes = takes }
            end
        end
    end
    for _, list in pairs(stacks) do
        table.sort(list, function(lhs, rhs) return lhs.count < rhs.count end)
    end
    for crafted = 1, limit do
        if room >= made then
            room = room - made
        else
            local slots = math.ceil((made - room) / stack)
            if free < slots then return crafted - 1 end
            free, room = free - slots, room + slots * stack - made
        end
        for _, reagent in ipairs(reagents) do
            local need = reagent.need
            for _, held in ipairs(stacks[reagent.itemID]) do
                if need <= 0 then break end
                local take = math.min(need, held.count)
                held.count, need = held.count - take, need - take
                if take > 0 and held.count == 0 and held.takes then free = free + 1 end
            end
        end
    end
    return limit
end

-- Your recipes by category, in the game's category order.
function Data.Collect()
    local categories, byID = {}, {}
    for _, recipeID in ipairs(C_TradeSkillUI.GetAllRecipeIDs() or {}) do
        local info = C_TradeSkillUI.GetRecipeInfo(recipeID)
        if info and info.learned then
            local catID = info.categoryID or 0
            local cat = byID[catID]
            if not cat then
                local catInfo = catID > 0 and C_TradeSkillUI.GetCategoryInfo(catID)
                cat = {
                    key = "cat" .. catID,
                    name = catInfo and catInfo.name or OTHER or "Other",
                    order = catInfo and catInfo.uiOrder or 999,
                    recipes = {},
                }
                byID[catID] = cat
                categories[#categories + 1] = cat
            end
            cat.recipes[#cat.recipes + 1] = info
        end
    end
    table.sort(categories, function(lhs, rhs)
        if lhs.order ~= rhs.order then return lhs.order < rhs.order end
        return lhs.name < rhs.name
    end)
    return categories
end

-- Recipes of this profession you have not learned yet, by when you can.
function Data.Unlearned(line, prof)
    local payload = line and Prof.ProfData(line)
    if not payload then return {} end
    local list = {}
    for _, region in ipairs(payload.recipes or {}) do
        if not Prof.Learned(region.spell) then
            local need = Prof.Skill(region)
            local status = prof.skill >= need and "ready" or prof.max < need and "rank" or "later"
            list[#list + 1] = { r = region, status = status, need = need }
        end
    end
    table.sort(list, function(lhs, rhs)
        if lhs.need ~= rhs.need then return lhs.need < rhs.need end
        return lhs.r.spell < rhs.r.spell
    end)
    return list, payload
end

-------------------------------------------------------------------------------
--  Favourites (per character, by spell) and the Filter menu (account-wide)
-------------------------------------------------------------------------------
local function IsFavourite(spell, info)
    local own = Prof.CharStore("favorites")[spell]
    if own ~= nil then return own end
    return info ~= nil and info.favorite == true
end

local function ToggleFavourite(spell, info)
    local on = not IsFavourite(spell, info)
    Prof.CharStore("favorites")[spell] = on
    if info and C_TradeSkillUI.SetRecipeFavorite then pcall(C_TradeSkillUI.SetRecipeFavorite, spell, on) end
end

local function Filters()
    local conf = F.Cfg()
    conf.windowFilters = conf.windowFilters or {}
    return conf.windowFilters
end

local function FilterCount()
    local n = 0
    for _, on in pairs(Filters()) do
        if on then n = n + 1 end
    end
    return n
end

local function PassesLearned(info)
    local f = Filters()
    if f.favorite and not IsFavourite(info.recipeID, info) then return false end
    if f.materials and Data.Craftable(info) == 0 then return false end
    if f.skillUp and info.relativeDifficulty == 3 then return false end
    return true
end

local function PassesUnlearned(entry)
    local f = Filters()
    if f.favorite and not IsFavourite(entry.r.spell) then return false end
    if f.materials then return false end
    local any, source = false, entry.r.source == "teacher" and "trainer" or entry.r.source
    for _, s in ipairs(SOURCE_FILTERS) do
        if f["src_" .. s.key] then
            if s.key == source then return true end
            any = true
        end
    end
    return not any
end

local function Matches(name, recipeID)
    if state.query == "" then return true end
    if name and name:lower():find(state.query, 1, true) then return true end
    for _, reagent in ipairs(recipeID and Data.Reagents(recipeID) or {}) do
        local reagentName = Data.ItemName(reagent.itemID)
        if reagentName and reagentName:lower():find(state.query, 1, true) then return true end
    end
    return false
end

-------------------------------------------------------------------------------
--  The list's entries: headers, your recipes, recipes not learned yet
-------------------------------------------------------------------------------
local entries = {}
local learnedCount, unlearnedCount = 0, 0
local UNLEARNED_GROUPS = {
    { status = "ready", name = "LEARNABLE NOW" },
    { status = "later", name = "NEEDS MORE SKILL" },
    { status = "rank", name = "NEEDS THE NEXT RANK" },
}

local function Collapsed(key)
    if state.query ~= "" then return false end
    return state.collapsed[key] == true
end

-------------------------------------------------------------------------------
--  Skill-ups: a recipe's chance to raise your skill, from its yellow and grey
--  levels in the recipe data (the game's own grey level wins when it gives
--  one). Bands are the game's: 0 orange, 1 yellow, 2 green, 3 grey.
-------------------------------------------------------------------------------
local SkillUps = {}

function SkillUps.Entry(spell)
    local index = state.spellIndex
    if not index then
        index = {}
        for _, region in ipairs(state.payload and state.payload.recipes or {}) do
            index[region.spell] = region
        end
        state.spellIndex = index
    end
    return index[spell]
end

function SkillUps.Chance(skill, yellow, grey)
    if skill >= grey then return 0, 3 end
    if skill < yellow then return 1, 0 end
    return (grey - skill) / (grey - yellow), skill < math.floor((yellow + grey) / 2) and 1 or 2
end

function SkillUps.Skill()
    local prof = state.prof
    return prof and prof.skill + (prof.modifier or 0)
end

-- learn, yellow, grey for a recipe the data knows.
function SkillUps.Range(spell, liveGrey)
    local region = SkillUps.Entry(spell)
    if not (region and region.yellow) then return end
    local grey = (type(liveGrey) == "number" and liveGrey > 0) and liveGrey or region.grey
    if not grey or region.yellow > grey then return end
    return Prof.Skill(region), region.yellow, grey
end

-- yellow, grey for a recipe you know, only when the data agrees with the
-- colour the game gives it (the game is right when they differ).
function SkillUps.Levels(info)
    if state.linked then return end
    local _, yellow, grey = SkillUps.Range(info.recipeID, info.maxTrivialLevel)
    local skill = SkillUps.Skill()
    if not (yellow and skill) then return end
    local chance, band = SkillUps.Chance(skill, yellow, grey)
    if info.relativeDifficulty and info.relativeDifficulty ~= band then return end
    return yellow, grey, chance
end

function SkillUps.ForRecipe(info)
    if state.linked then return end
    if info.relativeDifficulty == 0 then return 1, 0 end
    if info.relativeDifficulty == 3 then return 0, 3 end
    local _, _, chance = SkillUps.Levels(info)
    return chance, info.relativeDifficulty
end

-- "Skill-ups: yellow 100, green 112, grey 125  (now 60%)", each level in its colour.
function SkillUps.Thresholds(info)
    local yellow, grey, chance = SkillUps.Levels(info)
    if not yellow then return end
    local function Level(band, name, level)
        local c = COLOUR.difficulty[band]
        return CUI.HexColor(c[1], c[2], c[3]) .. name .. " " .. level .. "|r"
    end
    local text = "Skill-ups: "
        .. Level(1, "yellow", yellow)
        .. ", "
        .. Level(2, "green", math.floor((yellow + grey) / 2))
        .. ", "
        .. Level(3, "grey", grey)
    return text .. ("  (now %d%%)"):format(math.floor(chance * 100 + 0.5))
end

function SkillUps.ForUnlearned(entry)
    local region, skill = entry.r, SkillUps.Skill()
    if entry.status ~= "ready" or not (region.yellow and region.grey and skill) or region.yellow > region.grey then
        return
    end
    return SkillUps.Chance(skill, region.yellow, region.grey)
end

-- Best for Skill-ups: every recipe that can still raise your skill, likeliest first.
local function BestForSkillUps()
    local shown = {}
    for _, cat in ipairs(state.categories or {}) do
        for _, info in ipairs(cat.recipes) do
            local chance = SkillUps.ForRecipe(info)
            if chance ~= 0 and Matches(info.name, info.recipeID) and PassesLearned(info) then
                shown[#shown + 1] = { info = info, chance = chance or -1 }
            end
        end
    end
    table.sort(shown, function(lhs, rhs)
        if lhs.chance ~= rhs.chance then return lhs.chance > rhs.chance end
        return lhs.info.recipeID < rhs.info.recipeID
    end)
    return shown
end

local function BuildEntries()
    wipe(entries)
    local first, found
    learnedCount = 0
    local bySkill = state.tab == "learned" and Get("sortSkillUps") and not state.linked
    if bySkill then
        local shown = BestForSkillUps()
        learnedCount = #shown
        if #shown > 0 then
            entries[#entries + 1] = { head = "best", name = "BEST FOR SKILL-UPS", count = #shown }
            for _, item in ipairs(shown) do
                first = first or item.info
                if state.selected == item.info.recipeID then found = true end
                if not Collapsed("best") then entries[#entries + 1] = { info = item.info } end
            end
        end
    end
    for _, cat in ipairs(bySkill and {} or state.categories or {}) do
        local shown = {}
        for _, info in ipairs(cat.recipes) do
            if Matches(info.name, info.recipeID) and PassesLearned(info) then shown[#shown + 1] = info end
        end
        learnedCount = learnedCount + #shown
        if #shown > 0 and state.tab == "learned" then
            entries[#entries + 1] = { head = cat.key, name = cat.name:upper(), count = #shown }
            for _, info in ipairs(shown) do
                first = first or info
                if state.selected == info.recipeID then found = true end
                if not Collapsed(cat.key) then entries[#entries + 1] = { info = info } end
            end
        end
    end
    unlearnedCount = 0
    local groups = {}
    for _, entry in ipairs(state.unlearned or {}) do
        local name = C_Spell.GetSpellName(entry.r.spell)
        if Matches(name) and PassesUnlearned(entry) then
            unlearnedCount = unlearnedCount + 1
            groups[entry.status] = groups[entry.status] or {}
            table.insert(groups[entry.status], entry)
        end
    end
    if state.tab == "unlearned" then
        for _, group in ipairs(UNLEARNED_GROUPS) do
            local list = groups[group.status]
            if list then
                entries[#entries + 1] = { head = "u_" .. group.status, name = group.name, count = #list }
                for _, entry in ipairs(list) do
                    if not Collapsed("u_" .. group.status) then
                        entries[#entries + 1] = { unlearned = entry }
                    end
                end
            end
        end
    end
    if state.tab == "learned" and not found then state.selected = first and first.recipeID or nil end
end

-------------------------------------------------------------------------------
--  Window parts
-------------------------------------------------------------------------------
-- hooks.detail(info) runs after the picked recipe is drawn, hooks.render()
-- after the whole window (CludesUIForeverEssentials_CraftWindowPlus.lua).
local Window = { hooks = { detail = {}, render = {} } }
function Window.Win() return win end

local function SetTip(frame, fill)
    frame:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        fill(GameTooltip, self)
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", GameTooltip_Hide)
end

-- Druids craft out of their forms: a secure /cancelform layer over a button
-- (out of combat only) runs before the button's own click.
local covered = {}
local function CoverForForm(button)
    if select(2, UnitClass("player")) ~= "DRUID" then return end
    local layer = CreateFrame("Button", nil, button, "SecureActionButtonTemplate")
    layer:SetAllPoints()
    layer:SetFrameLevel(button:GetFrameLevel() + 2)
    layer:RegisterForClicks("LeftButtonUp")
    layer:SetAttribute("type", "macro")
    layer:SetAttribute("macrotext", "/cancelform")
    layer:SetPropagateMouseMotion(true)
    layer:SetScript("PostClick", function()
        if button:IsEnabled() then button:Click() end
    end)
    covered[#covered + 1] = layer
end

local function BuildHeader()
    local head = CreateFrame("Frame", nil, win)
    head:SetPoint("TOPLEFT", 1, -1)
    head:SetPoint("TOPRIGHT", -1, -1)
    head:SetHeight(LAYOUT.HEAD)
    Fill(head, COLOUR.sidebar):SetAllPoints()
    local rule = Fill(head, COLOUR.line, 1, "BORDER")
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")
    rule:SetHeight(1)
    win.logo = head:CreateTexture(nil, "ARTWORK")
    win.logo:SetTexture(LOGO)
    win.logo:SetSize(20, 20)
    win.logo:SetPoint("LEFT", 14, 0)
    win.title = NewText(head, 17, COLOUR.text)
    win.title:SetPoint("LEFT", win.logo, "RIGHT", 10, 1)
    win.rankTitle = NewText(head, 12.5, COLOUR.muted)
    win.rankTitle:SetPoint("BOTTOMLEFT", win.title, "BOTTOMRIGHT", 8, 1)
    local bar = CreateFrame("StatusBar", nil, head)
    bar:SetSize(240, 16)
    bar:SetPoint("LEFT", win.rankTitle, "RIGHT", 16, 0)
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    Fill(bar, { 0.06, 0.065, 0.075 }):SetAllPoints()
    Kit.Border(bar, COLOUR.line[1], COLOUR.line[2], COLOUR.line[3], 1)
    bar.text = NewText(bar, 11.5, { 1, 1, 1 })
    bar.text:SetPoint("CENTER")
    win.skillBar = bar
    win.close = Kit.Glyph(head, "x", function() HideUIPanel(ProfessionsFrame) end, nil, "essentials")
    win.close:SetPoint("RIGHT", -10, 0)
    head:EnableMouse(true)
    head:RegisterForDrag("LeftButton")
    head:SetScript("OnDragStart", function() Window.DragStart() end)
    head:SetScript("OnDragStop", function() Window.DragStop() end)
    win.head = head
end

local function BuildBanner()
    local banner = CreateFrame("Button", nil, win)
    banner:SetPoint("TOPLEFT", win.head, "BOTTOMLEFT", 0, 0)
    banner:SetPoint("TOPRIGHT", win.head, "BOTTOMRIGHT", 0, 0)
    banner:SetHeight(36)
    local tint = Fill(banner, { 1, 0.82, 0 }, 0.08)
    tint:SetAllPoints()
    banner.text = NewText(banner, 12.5, COLOUR.text)
    banner.text:SetPoint("LEFT", 14, 0)
    banner.text:SetPoint("RIGHT", -110, 0)
    banner.text:SetJustifyH("LEFT")
    banner.pin = Kit.Button(banner, "Map Pin", 86, 22, function()
        if banner.npc then Prof.LinkNpc(banner.npc) end
    end, { key = "essentials" })
    banner.pin:SetPoint("RIGHT", -12, 0)
    banner:Hide()
    win.banner = banner
end

-- Learned / Not learned, under the search box.
local function BuildTabs(aside)
    win.tabs = {}
    local prev
    for _, tab in ipairs({
        { key = "learned", text = "Learned" },
        { key = "unlearned", text = "Not learned" },
    }) do
        local button = CreateFrame("Button", nil, aside)
        button:SetHeight(28)
        button.text = NewText(button, 13, COLOUR.muted)
        button.text:SetPoint("LEFT")
        button.count = NewText(button, 11.5, COLOUR.muted)
        button.count:SetPoint("LEFT", button.text, "RIGHT", 5, 0)
        button.line = Fill(button, { 1, 1, 1 }, 1, "ARTWORK")
        button.line:SetPoint("BOTTOMLEFT")
        button.line:SetPoint("BOTTOMRIGHT")
        button.line:SetHeight(2)
        button.text:SetText(tab.text)
        button.key = tab.key
        if prev then
            button:SetPoint("LEFT", prev, "RIGHT", 16, 0)
        else
            button:SetPoint("TOPLEFT", aside, "TOPLEFT", LAYOUT.PAD, -46)
        end
        button:SetScript("OnClick", function()
            state.tab, state.offset = tab.key, 0
            Window.Render()
        end)
        win.tabs[#win.tabs + 1] = button
        prev = button
    end
    local rule = Fill(aside, COLOUR.line, 1, "BORDER")
    rule:SetPoint("TOPLEFT", aside, "TOPLEFT", 0, -74)
    rule:SetPoint("TOPRIGHT", aside, "TOPRIGHT", 0, -74)
    rule:SetHeight(1)
end

local function OpenFilterMenu()
    Kit.ContextMenu(win.filter, function(_, root)
        local f = Filters()
        local function Toggle(key)
            return function()
                f[key] = not f[key] or nil
                state.offset = 0
                Window.Render()
            end
        end
        root:CreateTitle("Filter")
        root:CreateCheckbox("Favorites", function() return f.favorite end, Toggle("favorite"))
        root:CreateCheckbox("Have Materials", function() return f.materials end, Toggle("materials"))
        root:CreateCheckbox("Has Skill-Up", function() return f.skillUp end, Toggle("skillUp"))
        root:CreateDivider()
        root:CreateTitle("Your recipes: sort")
        local function Sort(bySkill)
            return function()
                F.Cfg().sortSkillUps = bySkill
                state.offset = 0
                Window.Render()
            end
        end
        root:CreateRadio("By Category", function() return not Get("sortSkillUps") end, Sort(false))
        root:CreateRadio("Best for Skill-ups", function() return Get("sortSkillUps") == true end, Sort(true))
        root:CreateDivider()
        root:CreateTitle("Not learned: comes from")
        for _, s in ipairs(SOURCE_FILTERS) do
            root:CreateCheckbox(s.text, function() return f["src_" .. s.key] end, Toggle("src_" .. s.key))
        end
        root:CreateDivider()
        root:CreateButton("Reset Filters", function()
            wipe(f)
            state.offset = 0
            Window.Render()
        end)
    end)
end

local function BuildAside()
    local aside = CreateFrame("Frame", nil, win)
    aside:SetPoint("TOPLEFT", win.head, "BOTTOMLEFT", 0, 0)
    aside:SetPoint("BOTTOMLEFT", 1, 1)
    aside:SetWidth(LAYOUT.LEFT)
    Fill(aside, COLOUR.sidebar, 0.85):SetAllPoints()
    local edge = Fill(aside, COLOUR.line, 1, "BORDER")
    edge:SetPoint("TOPRIGHT")
    edge:SetPoint("BOTTOMRIGHT")
    edge:SetWidth(1)
    win.search = Kit.Input(aside, LAYOUT.LEFT - LAYOUT.PAD * 2 - 76, 28, "Search recipes", "essentials")
    win.search:SetPoint("TOPLEFT", LAYOUT.PAD, -LAYOUT.PAD)
    win.search:HookScript("OnTextChanged", function(self)
        state.query, state.offset = (self:GetText() or ""):lower(), 0
        Window.Render()
    end)
    win.filter = Kit.Button(aside, "Filter", 70, 28, OpenFilterMenu, { key = "essentials" })
    win.filter:SetPoint("LEFT", win.search, "RIGHT", 6, 0)
    BuildTabs(aside)
    local list = CreateFrame("Frame", nil, aside)
    list:SetPoint("TOPLEFT", 0, -80)
    list:SetPoint("BOTTOMRIGHT", -8, 4)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta)
        local most = math.max(0, #entries - Window.VisibleRows())
        state.offset = math.max(0, math.min(most, state.offset - delta * 3))
        Window.RenderList()
    end)
    list:SetScript("OnSizeChanged", function()
        if win:IsShown() and win.aside:IsShown() then Window.RenderList() end
    end)
    win.list = list
    win.rows = {}
    local thumb = Fill(aside, { 1, 1, 1 }, 0.7, "ARTWORK")
    thumb:SetWidth(3)
    win.thumb = thumb
    win.aside = aside
end

local function NewRow(index)
    local row = CreateFrame("Button", nil, win.list)
    row:SetHeight(LAYOUT.ROW)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * LAYOUT.ROW)
    row:SetPoint("TOPRIGHT", 0, -(index - 1) * LAYOUT.ROW)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row.sel = Fill(row, { 1, 1, 1 }, 0.06)
    row.sel:SetAllPoints()
    row.edge = Fill(row, { 1, 1, 1 }, 1, "ARTWORK")
    row.edge:SetPoint("TOPLEFT")
    row.edge:SetPoint("BOTTOMLEFT")
    row.edge:SetWidth(3)
    row.hover = Fill(row, { 1, 1, 1 }, 0.04, "HIGHLIGHT")
    row.hover:SetAllPoints()
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(17, 17)
    row.icon:SetPoint("LEFT", 14, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.count = NewText(row, 12, COLOUR.text)
    row.count:SetPoint("RIGHT", -10, 0)
    row.count:SetJustifyH("RIGHT")
    row.chance = NewText(row, 11, COLOUR.muted)
    row.chance:SetPoint("RIGHT", row.count, "LEFT", -6, 0)
    row.chance:SetJustifyH("RIGHT")
    row.star = row:CreateTexture(nil, "ARTWORK")
    row.star:SetSize(12, 12)
    row.star:SetTexture("Interface\\COMMON\\ReputationStar")
    row.star:SetTexCoord(0, 0.5, 0, 0.5)
    row.name = NewText(row, 13, COLOUR.text)
    row.name:SetJustifyH("LEFT")
    row:SetScript("OnClick", function(self, button) Window.RowClick(self, button) end)
    row:SetScript("OnEnter", function(self) Window.RowTip(self) end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    row:SetScript("OnMouseWheel", function(_, delta) win.list:GetScript("OnMouseWheel")(win.list, delta) end)
    win.rows[index] = row
    return row
end

-------------------------------------------------------------------------------
--  The picked recipe (right side)
-------------------------------------------------------------------------------
local function BuildReagents(pane)
    local card = CreateFrame("Frame", nil, pane)
    card:SetPoint("LEFT", LAYOUT.PAD + 6, 0)
    card:SetPoint("RIGHT", -LAYOUT.PAD - 6, 0)
    Fill(card, COLOUR.panel):SetAllPoints()
    Kit.Border(card, COLOUR.line[1], COLOUR.line[2], COLOUR.line[3], 1)
    local function Column(text, right)
        local fs = NewText(card, 11, COLOUR.muted)
        fs:SetPoint("TOPRIGHT", card, "TOPRIGHT", right, -9)
        fs:SetText(text)
        return fs
    end
    local title = NewText(card, 11, COLOUR.muted)
    title:SetPoint("TOPLEFT", 12, -9)
    title:SetText("REAGENTS")
    card.bankHead = Column("BANK", -12)
    Column("BAGS", -68)
    Column("NEED", -124)
    local rule = Fill(card, COLOUR.line, 1, "BORDER")
    rule:SetPoint("TOPLEFT", 1, -28)
    rule:SetPoint("TOPRIGHT", -1, -28)
    rule:SetHeight(1)
    card.rows = {}
    for index = 1, LAYOUT.MAX_REAGENTS do
        local row = CreateFrame("Button", nil, card)
        row:SetHeight(LAYOUT.REAGENT)
        row:SetPoint("TOPLEFT", 1, -29 - (index - 1) * LAYOUT.REAGENT)
        row:SetPoint("TOPRIGHT", -1, -29 - (index - 1) * LAYOUT.REAGENT)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(22, 22)
        row.icon:SetPoint("LEFT", 11, 0)
        row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        row.bank = NewText(row, 13, COLOUR.muted)
        row.bank:SetPoint("RIGHT", -12, 0)
        row.bags = NewText(row, 13, COLOUR.green)
        row.bags:SetPoint("RIGHT", -68, 0)
        row.need = NewText(row, 13, COLOUR.text)
        row.need:SetPoint("RIGHT", -124, 0)
        row.name = NewText(row, 13, COLOUR.text)
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 9, 0)
        row.name:SetPoint("RIGHT", row.need, "LEFT", -12, 0)
        row.name:SetJustifyH("LEFT")
        row.hover = Fill(row, { 1, 1, 1 }, 0.04, "HIGHLIGHT")
        row.hover:SetAllPoints()
        SetTip(row, function(tip, self)
            if self.itemID then tip:SetItemByID(self.itemID) end
        end)
        row:SetScript("OnClick", function(self)
            if self.itemID and IsModifiedClick("CHATLINK") then
                local _, link = C_Item.GetItemInfo(self.itemID)
                if link then ChatFrameUtil.InsertLink(link) end
            end
        end)
        card.rows[index] = row
    end
    pane.reagents = card
end

local function BuildCraftFooter(pane)
    local foot = CreateFrame("Frame", nil, pane)
    foot:SetPoint("BOTTOMLEFT", LAYOUT.PAD + 6, 10)
    foot:SetPoint("BOTTOMRIGHT", -LAYOUT.PAD - 6, 10)
    foot:SetHeight(32)
    local rule = Fill(pane, COLOUR.line, 1, "BORDER")
    rule:SetPoint("BOTTOMLEFT", foot, "TOPLEFT", 0, 10)
    rule:SetPoint("BOTTOMRIGHT", foot, "TOPRIGHT", 0, 10)
    rule:SetHeight(1)
    pane.createAll = Kit.Button(
        foot,
        "Create All",
        130,
        30,
        function() Window.Craft(pane.createAll.count or 0) end,
        { key = "essentials", size = 13 }
    )
    pane.createAll:SetPoint("LEFT")
    pane.create = Kit.Button(
        foot,
        "Create",
        110,
        30,
        function() Window.Craft(Window.Quantity()) end,
        { key = "essentials", size = 13 }
    )
    pane.create:SetPoint("RIGHT")
    pane.create:SetActive(true)
    local plus = Kit.Button(foot, "+", 26, 30, function() Window.StepQuantity(1) end, { key = "essentials" })
    plus:SetPoint("RIGHT", pane.create, "LEFT", -10, 0)
    pane.qty = Kit.Input(foot, 40, 30, nil, "essentials")
    pane.qty:SetNumeric(true)
    pane.qty:SetMaxLetters(3)
    pane.qty:SetJustifyH("CENTER")
    pane.qty:SetText("1")
    pane.qty:SetPoint("RIGHT", plus, "LEFT", -2, 0)
    local minus = Kit.Button(
        foot,
        "-",
        26,
        30,
        function() Window.StepQuantity(-1) end,
        { key = "essentials" }
    )
    minus:SetPoint("RIGHT", pane.qty, "LEFT", -2, 0)
    CoverForForm(pane.create)
    CoverForForm(pane.createAll)
    pane.track = Kit.Check(foot, "Track Recipe", function(self)
        local info = Window.Selected()
        if not (info and pcall(C_TradeSkillUI.SetRecipeTracked, info.recipeID, self:GetChecked(), false)) then
            self:SetChecked(not self:GetChecked())
        end
    end, "essentials")
    pane.track:SetPoint("BOTTOMLEFT", foot, "TOPLEFT", 0, 22)
    pane.foot, pane.footRule = foot, rule
end

local function BuildDetail()
    local pane = CreateFrame("Frame", nil, win)
    pane:SetPoint("TOPLEFT", win.aside, "TOPRIGHT", 0, 0)
    pane:SetPoint("BOTTOMRIGHT", -1, 1)
    local iconButton = CreateFrame("Button", nil, pane)
    iconButton:SetSize(46, 46)
    iconButton:SetPoint("TOPLEFT", LAYOUT.PAD + 6, -16)
    pane.icon = iconButton:CreateTexture(nil, "ARTWORK")
    pane.icon:SetAllPoints()
    pane.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    Kit.Border(iconButton, COLOUR.line[1], COLOUR.line[2], COLOUR.line[3], 1)
    pane.made = NewText(iconButton, 13, { 1, 1, 1 })
    pane.made:SetPoint("BOTTOMRIGHT", -2, 2)
    SetTip(iconButton, function(tip)
        local info = Window.Selected()
        if info and not pcall(tip.SetRecipeResultItem, tip, info.recipeID) then
            tip:SetSpellByID(info.recipeID)
        end
    end)
    pane.star = Kit.Button(pane, "", 28, 28, function()
        local info = Window.Selected()
        if info then
            ToggleFavourite(info.recipeID, info)
            Window.Render()
        end
    end, {
        key = "essentials",
        tip = "Favorite: a star in the list, and the Filter menu's Favorites shows only them. Right-click a recipe in the list does the same.",
    })
    pane.star:SetPoint("TOPRIGHT", -LAYOUT.PAD - 6, -18)
    pane.starIcon = pane.star:CreateTexture(nil, "OVERLAY")
    pane.starIcon:SetSize(14, 14)
    pane.starIcon:SetPoint("CENTER")
    pane.starIcon:SetTexture("Interface\\COMMON\\ReputationStar")
    pane.name = NewText(pane, 19, COLOUR.text)
    pane.name:SetPoint("TOPLEFT", iconButton, "TOPRIGHT", 14, -4)
    pane.name:SetPoint("RIGHT", pane.star, "LEFT", -10, 0)
    pane.name:SetJustifyH("LEFT")
    pane.sub = NewText(pane, 12.5, COLOUR.muted)
    pane.sub:SetPoint("TOPLEFT", pane.name, "BOTTOMLEFT", 0, -5)
    pane.sub:SetPoint("RIGHT", pane.star, "LEFT", -10, 0)
    pane.sub:SetJustifyH("LEFT")
    pane.needs = NewText(pane, 12.5, COLOUR.text)
    pane.needs:SetPoint("TOPLEFT", iconButton, "BOTTOMLEFT", 0, -14)
    pane.needs:SetPoint("RIGHT", -LAYOUT.PAD - 6, 0)
    pane.needs:SetJustifyH("LEFT")
    pane.needs:SetWordWrap(true)
    pane.desc = NewText(pane, 12, COLOUR.muted)
    pane.desc:SetPoint("TOPLEFT", pane.needs, "BOTTOMLEFT", 0, -8)
    pane.desc:SetPoint("RIGHT", -LAYOUT.PAD - 6, 0)
    pane.desc:SetJustifyH("LEFT")
    pane.desc:SetWordWrap(true)
    BuildReagents(pane)
    BuildCraftFooter(pane)
    win.detail = pane
    win.empty = NewText(win, 13, COLOUR.muted)
    win.empty:SetPoint("CENTER", pane, "CENTER")
    win.empty:SetText("No recipes match.")
end

-------------------------------------------------------------------------------
--  A recipe not learned yet (right side)
-------------------------------------------------------------------------------
local function BuildLearn()
    local pane = CreateFrame("Frame", nil, win)
    pane:SetAllPoints(win.detail)
    pane.icon = pane:CreateTexture(nil, "ARTWORK")
    pane.icon:SetSize(46, 46)
    pane.icon:SetPoint("TOPLEFT", LAYOUT.PAD + 6, -16)
    pane.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    pane.name = NewText(pane, 19, COLOUR.text)
    pane.name:SetPoint("TOPLEFT", pane.icon, "TOPRIGHT", 14, -4)
    pane.name:SetPoint("RIGHT", -LAYOUT.PAD - 6, 0)
    pane.name:SetJustifyH("LEFT")
    pane.req = NewText(pane, 12.5, COLOUR.muted)
    pane.req:SetPoint("TOPLEFT", pane.name, "BOTTOMLEFT", 0, -5)
    pane.lines = {}
    pane.hint = NewText(pane, 11.5, COLOUR.muted)
    pane.hint:SetPoint("BOTTOMLEFT", LAYOUT.PAD + 6, 14)
    pane.hint:SetText("Click a trainer, vendor or quest giver to link its map pin in chat.")
    pane:Hide()
    win.learn = pane
end

local function LearnLine(index)
    local pane = win.learn
    local line = pane.lines[index]
    if line then return line end
    line = CreateFrame("Button", nil, pane)
    line:SetPoint("LEFT", LAYOUT.PAD + 6, 0)
    line:SetPoint("RIGHT", -LAYOUT.PAD - 6, 0)
    line.text = NewText(line, 12.5, COLOUR.text)
    line.text:SetPoint("TOPLEFT")
    line.text:SetPoint("TOPRIGHT")
    line.text:SetJustifyH("LEFT")
    line.text:SetWordWrap(true)
    line:SetScript("OnClick", function(self)
        if self.npc then Prof.LinkNpc(self.npc) end
    end)
    pane.lines[index] = line
    return line
end

-------------------------------------------------------------------------------
--  The overview page: a card per profession, holding the game's own card
--  (its spell and unlearn buttons) over our look
-------------------------------------------------------------------------------
local BOOK_ORDER = {
    "PrimaryProfession1",
    "PrimaryProfession2",
    "SecondaryProfession1",
    "SecondaryProfession2",
    "SecondaryProfession3",
}
local BOOK_ART =
    { "Background", "ProfessionName", "specialization", "missingHeader", "missingText", "StatusBar" }
local docked = {}

local function BuildBook()
    local book = CreateFrame("Frame", nil, win)
    book:SetPoint("TOPLEFT", win.head, "BOTTOMLEFT", LAYOUT.PAD, -LAYOUT.PAD)
    book:SetPoint("BOTTOMRIGHT", -LAYOUT.PAD, LAYOUT.PAD)
    book.cards = {}
    local innerW = LAYOUT.W - LAYOUT.PAD * 2 - 2
    local thirdW = (innerW - 16) / 3
    for index = 1, #BOOK_ORDER do
        local card = CreateFrame("Frame", nil, book)
        Fill(card, COLOUR.panel):SetAllPoints()
        Kit.Border(card, COLOUR.line[1], COLOUR.line[2], COLOUR.line[3], 1)
        card.primary = index <= 2
        if card.primary then
            card:SetPoint("TOPLEFT", 0, -(index - 1) * 136)
            card:SetSize(innerW, 128)
        else
            local x = (index - 3) * (thirdW + 8)
            card:SetPoint("TOPLEFT", x, -272)
            card:SetPoint("BOTTOMLEFT", book, "BOTTOMLEFT", x, 0)
            card:SetWidth(thirdW)
        end
        card.name = NewText(card, 14, COLOUR.text)
        card.bar = CreateFrame("StatusBar", nil, card)
        card.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        card.bar:SetHeight(16)
        Fill(card.bar, { 0.06, 0.065, 0.075 }):SetAllPoints()
        Kit.Border(card.bar, COLOUR.line[1], COLOUR.line[2], COLOUR.line[3], 1)
        card.barText = NewText(card.bar, 11.5, { 1, 1, 1 })
        card.barText:SetPoint("CENTER")
        if card.primary then
            card.name:SetPoint("TOPLEFT", 14, -12)
            card.bar:SetPoint("TOPLEFT", 250, -52)
            card.bar:SetPoint("RIGHT", -44, 0)
        else
            card.name:SetPoint("TOP", 0, -12)
            card.bar:SetPoint("TOPLEFT", 12, -38)
            card.bar:SetPoint("TOPRIGHT", -12, -38)
        end
        card.missing = NewText(card, 12.5, COLOUR.muted)
        card.missing:SetPoint("CENTER")
        card.rank = CreateFrame("Button", nil, card)
        card.rank:SetPoint("TOPLEFT", card.bar, "BOTTOMLEFT", 0, -6)
        card.rank:SetPoint("TOPRIGHT", card.bar, "BOTTOMRIGHT", 0, -6)
        card.rank:SetHeight(38)
        card.rank:SetFrameLevel(card:GetFrameLevel() + 12)
        Fill(card.rank, { 1, 0.82, 0 }, 0.08):SetAllPoints()
        card.rank.text = NewText(card.rank, 12, COLOUR.text)
        card.rank.text:SetPoint("TOPLEFT", 8, -6)
        card.rank.text:SetPoint("TOPRIGHT", -8, -6)
        card.rank.text:SetJustifyH("LEFT")
        card.rank.text:SetWordWrap(true)
        card.rank:SetScript("OnClick", function(self)
            if self.npc then Prof.LinkNpc(self.npc) end
        end)
        card.rank:Hide()
        book.cards[index] = card
    end
    book:Hide()
    win.book = book
end

local function DockCards(on)
    if InCombatLockdown() then
        state.dockPending = on
        return
    end
    state.dockPending = nil
    if not on then
        for frame, saved in pairs(docked) do
            frame:SetParent(saved.parent)
            frame:ClearAllPoints()
            for _, pt in ipairs(saved.points) do
                frame:SetPoint(unpack(pt))
            end
            frame:SetFrameStrata(saved.strata)
            frame:SetFrameLevel(saved.level)
            for region, alpha in pairs(saved.art) do
                region:SetAlpha(alpha)
            end
        end
        wipe(docked)
        return
    end
    local content = ProfessionsFrame.BookPage and ProfessionsFrame.BookPage.ProfessionsContentFrame
    if not content then return end
    for index, key in ipairs(BOOK_ORDER) do
        local frame, card = content[key], win.book.cards[index]
        if frame and not docked[frame] then
            local saved = {
                parent = frame:GetParent(),
                strata = frame:GetFrameStrata(),
                level = frame:GetFrameLevel(),
                points = {},
                art = {},
            }
            for point = 1, frame:GetNumPoints() do
                saved.points[point] = { frame:GetPoint(point) }
            end
            for _, artKey in ipairs(BOOK_ART) do
                local region = frame[artKey]
                if type(region) == "table" and region.SetAlpha then
                    saved.art[region] = region:GetAlpha()
                    region:SetAlpha(0)
                end
            end
            docked[frame] = saved
            frame:SetParent(card)
            frame:ClearAllPoints()
            frame:SetAllPoints(card)
            frame:SetFrameLevel(card:GetFrameLevel() + 3)
        end
    end
end

-------------------------------------------------------------------------------
--  Drawing
-------------------------------------------------------------------------------
-- The list's rows: its height, or (before it is laid out) the window's less
-- the header, the banner and the search/tabs block above the list.
function Window.VisibleRows()
    local height = win.list:GetHeight()
    if not height or height < LAYOUT.ROW then
        height = win:GetHeight() - LAYOUT.HEAD - 84 - (win.banner:IsShown() and 36 or 0)
    end
    return math.max(1, math.floor(height / LAYOUT.ROW))
end

function Window.Selected()
    if state.tab ~= "learned" or not state.selected then return end
    return C_TradeSkillUI.GetRecipeInfo(state.selected)
end

function Window.Quantity() return math.max(1, tonumber(win.detail.qty:GetText()) or 1) end
function Window.StepQuantity(by)
    win.detail.qty:SetText(tostring(math.max(1, math.min(999, Window.Quantity() + by))))
end

function Window.Craft(count)
    local info = Window.Selected()
    if not info or count < 1 then return end
    local ok, err = pcall(C_TradeSkillUI.CraftRecipe, info.recipeID, count)
    if not ok then CUI.Print("|cff4cc9f0Professions:|r could not craft: " .. tostring(err)) end
end

function Window.RowClick(row, button)
    local entry = row.entry
    if not entry then return end
    if button == "RightButton" then
        if entry.info then ToggleFavourite(entry.info.recipeID, entry.info) end
        if entry.unlearned then ToggleFavourite(entry.unlearned.r.spell) end
        return Window.Render()
    end
    if entry.head then
        state.collapsed[entry.head] = not state.collapsed[entry.head] or nil
        return Window.Render()
    end
    if entry.unlearned then
        state.picked = entry.unlearned
    elseif IsModifiedClick("CHATLINK") then
        local link = C_TradeSkillUI.GetRecipeLink(entry.info.recipeID)
        if link then ChatFrameUtil.InsertLink(link) end
        return
    else
        if state.selected ~= entry.info.recipeID then win.detail.qty:SetText("1") end
        state.selected = entry.info.recipeID
    end
    Window.RenderList()
    Window.RenderRight()
end

function Window.RowTip(row)
    local entry = row.entry
    if not entry or entry.head then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if entry.info then
        if not pcall(GameTooltip.SetRecipeResultItem, GameTooltip, entry.info.recipeID) then
            GameTooltip:SetSpellByID(entry.info.recipeID)
        end
    else
        GameTooltip:SetSpellByID(entry.unlearned.r.spell)
        GameTooltip:AddLine(
            ("Requires skill %d  (%s)"):format(
                entry.unlearned.need,
                Prof.SOURCE_TAG[entry.unlearned.r.source] or "?"
            ),
            1,
            1,
            1
        )
    end
    GameTooltip:Show()
end

local function UnlearnedColour(entry)
    if entry.status == "ready" then return COLOUR.green end
    if entry.status == "rank" then return COLOUR.difficulty[0] end
    return COLOUR.muted
end

function Window.RenderList()
    local visible = Window.VisibleRows()
    state.offset = math.max(0, math.min(state.offset, #entries - visible))
    local r, g, b = Kit.Accent()
    for index = 1, visible do
        local entry = entries[index + state.offset]
        local row = win.rows[index] or NewRow(index)
        row.entry = entry
        if not entry then
            row:Hide()
        else
            row.sel:Hide()
            row.edge:Hide()
            row.star:Hide()
            row.chance:SetText("")
            row.name:ClearAllPoints()
            if entry.head then
                row.icon:Hide()
                row.name:SetPoint("LEFT", 12, 0)
                row.name:SetText((Collapsed(entry.head) and "+  " or "-  ") .. entry.name)
                Kit.Font(row.name, 11, "essentials")
                Paint(row.name, COLOUR.muted)
                row.count:SetText(entry.count)
                Paint(row.count, COLOUR.muted)
            else
                Kit.Font(row.name, 13, "essentials")
                row.icon:Show()
                row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
                local favourite, chance, band
                if entry.info then
                    local info = entry.info
                    row.icon:SetTexture(info.icon)
                    row.name:SetText(info.name)
                    Paint(row.name, COLOUR.difficulty[info.relativeDifficulty] or COLOUR.text)
                    local can = Data.Craftable(info)
                    row.count:SetText(can > 0 and can or "")
                    Paint(row.count, COLOUR.text)
                    favourite = IsFavourite(info.recipeID, info)
                    chance, band = SkillUps.ForRecipe(info)
                    local picked = info.recipeID == state.selected
                    row.sel:SetShown(picked)
                    row.edge:SetShown(picked)
                else
                    local unlearned = entry.unlearned
                    local spell = unlearned.r.spell
                    row.icon:SetTexture(
                        (unlearned.r.item and C_Item.GetItemIconByID(unlearned.r.item))
                            or C_Spell.GetSpellTexture(spell)
                            or 134400
                    )
                    row.name:SetText(C_Spell.GetSpellName(spell) or ("Recipe " .. spell))
                    Paint(row.name, UnlearnedColour(unlearned))
                    row.count:SetText(unlearned.need)
                    Paint(row.count, UnlearnedColour(unlearned))
                    favourite = IsFavourite(spell)
                    chance, band = SkillUps.ForUnlearned(unlearned)
                    local picked = unlearned == state.picked
                    row.sel:SetShown(picked)
                    row.edge:SetShown(picked)
                end
                -- A skill-up chance only where it is not certain either way.
                local showChance = Get("skillUpChances") ~= false and chance and chance > 0 and chance < 1
                if showChance then
                    row.chance:SetText(("%d%%"):format(math.floor(chance * 100 + 0.5)))
                    Paint(row.chance, COLOUR.difficulty[band] or COLOUR.muted)
                end
                local right = showChance and row.chance or row.count
                row.star:SetShown(favourite)
                row.star:ClearAllPoints()
                row.star:SetPoint("RIGHT", right, "LEFT", -6, 0)
                row.name:SetPoint("RIGHT", favourite and row.star or right, "LEFT", -6, 0)
            end
            row.edge:SetColorTexture(r, g, b, 1)
            row:Show()
        end
    end
    for index = visible + 1, #win.rows do
        win.rows[index]:Hide()
    end
    -- the scroll thumb
    local most = #entries - visible
    if most > 0 then
        local height = win.list:GetHeight()
        local thumbH = math.max(20, height * visible / #entries)
        win.thumb:SetColorTexture(r, g, b, 0.7)
        win.thumb:ClearAllPoints()
        win.thumb:SetPoint("TOPRIGHT", win.list, "TOPRIGHT", 6, -(height - thumbH) * state.offset / most)
        win.thumb:SetHeight(thumbH)
        win.thumb:Show()
    else
        win.thumb:Hide()
    end
end

local function NeedsLine(info, output, made, can)
    local parts = {}
    local ok, reqs = pcall(C_TradeSkillUI.GetRecipeRequirements, info.recipeID)
    local unmet = false
    if ok and reqs then
        for _, req in ipairs(reqs) do
            if req.met == false then unmet = true end
            local c = req.met == false and COLOUR.red or COLOUR.green
            parts[#parts + 1] = CUI.HexColor(c[1], c[2], c[3]) .. req.name .. "|r"
        end
    end
    local lines = {}
    if #parts > 0 then lines[1] = "Requires: " .. table.concat(parts, ", ") end
    local okCooldown, cooldown = pcall(C_TradeSkillUI.GetRecipeCooldown, info.recipeID)
    if okCooldown and cooldown and cooldown > 0 then
        local left = SecondsToTime and SecondsToTime(cooldown) or (math.ceil(cooldown / 60) .. " min")
        lines[#lines + 1] = "|cffff6060Cooldown: " .. tostring(left) .. "|r"
    end
    local room = output and Data.BagRoom(info.recipeID, can) or can
    if room < can then lines[#lines + 1] = ("|cffff6060Bags: room for %d of %d.|r"):format(room, can) end
    return table.concat(lines, "\n"), unmet, math.min(can, room)
end

function Window.RenderDetail()
    local pane = win.detail
    local info = Window.Selected()
    win.learn:Hide()
    pane:SetShown(info ~= nil)
    win.empty:SetShown(info == nil)
    if not info then return end
    local output, made, most = Data.Output(info.recipeID)
    pane.icon:SetTexture(info.icon)
    pane.made:SetText(most and most > made and (made .. "-" .. most) or (made and made > 1 and made or ""))
    pane.name:SetText(info.name)
    Paint(pane.name, COLOUR.difficulty[info.relativeDifficulty] or COLOUR.text)
    local catInfo = info.categoryID and C_TradeSkillUI.GetCategoryInfo(info.categoryID)
    pane.sub:SetText(catInfo and catInfo.name or "")
    local favourite = IsFavourite(info.recipeID, info)
    pane.starIcon:SetTexCoord(favourite and 0 or 0.5, favourite and 0.5 or 1, 0, 0.5)
    local can = Data.Craftable(info)
    local needs, unmet, allowed = NeedsLine(info, output, made, can)
    local thresholds = Get("skillThresholds") ~= false and SkillUps.Thresholds(info)
    if thresholds then needs = needs ~= "" and (thresholds .. "\n" .. needs) or thresholds end
    pane.needs:SetText(needs)
    local okDesc, desc = pcall(C_TradeSkillUI.GetRecipeDescription, info.recipeID, {})
    pane.desc:SetText(okDesc and desc or "")
    local reagents = Data.Reagents(info.recipeID)
    local card = pane.reagents
    card:ClearAllPoints()
    card:SetPoint(
        "TOPLEFT",
        (pane.desc:GetText() or "") ~= "" and pane.desc or pane.needs,
        "BOTTOMLEFT",
        0,
        -14
    )
    card:SetPoint("RIGHT", -LAYOUT.PAD - 6, 0)
    local shown = math.min(#reagents, LAYOUT.MAX_REAGENTS)
    card:SetHeight(29 + math.max(shown, 1) * LAYOUT.REAGENT)
    for index, row in ipairs(card.rows) do
        local reagent = reagents[index]
        row.itemID = reagent and reagent.itemID
        if reagent and index <= shown then
            local bags = Data.Bags(reagent.itemID)
            row.icon:SetTexture(C_Item.GetItemIconByID(reagent.itemID))
            row.name:SetText(Data.ItemName(reagent.itemID) or "")
            row.need:SetText(reagent.need)
            row.bags:SetText(bags)
            Paint(row.bags, bags >= reagent.need and COLOUR.green or COLOUR.red)
            row.bank:SetText(Data.Bank(reagent.itemID))
            row:Show()
        else
            row:Hide()
        end
    end
    -- Another player's recipe: nothing to create here.
    pane.foot:SetShown(not state.linked)
    pane.footRule:SetShown(not state.linked)
    local okTrack, tracked = pcall(C_TradeSkillUI.IsRecipeTracked, info.recipeID, false)
    pane.track:SetShown(okTrack and C_TradeSkillUI.SetRecipeTracked ~= nil and not state.linked)
    pane.track:SetChecked(okTrack and tracked == true)
    pane.createAll.count = allowed
    pane.createAll:SetText(("Create All (%d)"):format(allowed))
    pane.createAll:SetEnabled(not unmet and allowed > 0)
    pane.create:SetEnabled(not unmet)
    pane.createAll:SetAlpha((not unmet and allowed > 0) and 1 or 0.45)
    pane.create:SetAlpha(not unmet and 1 or 0.45)
    for _, hook in ipairs(Window.hooks.detail) do
        hook(info)
    end
end

-- A recipe not learned yet: what it needs, and the source lines /cprof shows.
function Window.RenderLearn()
    local entry = state.picked
    local pane = win.learn
    win.detail:Hide()
    win.empty:SetShown(entry == nil)
    pane:SetShown(entry ~= nil)
    if not entry then return end
    local region = entry.r
    pane.icon:SetTexture(
        (region.item and C_Item.GetItemIconByID(region.item))
            or C_Spell.GetSpellTexture(region.spell)
            or 134400
    )
    pane.name:SetText(C_Spell.GetSpellName(region.spell) or ("Recipe " .. region.spell))
    Paint(pane.name, UnlearnedColour(entry))
    local prof = state.prof
    pane.req:SetText(("Requires %s %d   (you: %d/%d)"):format(prof.name, entry.need, prof.skill, prof.max))
    local collected = {}
    local sink = {
        AddLine = function(_, text, red, green, blue)
            collected[#collected + 1] = { text = text, colour = { red or 1, green or 1, blue or 1 } }
        end,
    }
    local npcByText = {}
    local nearest = Prof.Describe(region, state.payload, sink)
    -- Lines naming an NPC link its pin: match each "Name - Zone x, y" line to its NPC.
    if nearest then npcByText[Prof.NpcText(nearest)] = nearest end
    for _, npc in ipairs(region.vendors or {}) do
        npcByText[Prof.NpcText(npc)] = npc
    end
    for _, npc in ipairs(state.payload and state.payload.trainers or {}) do
        npcByText[Prof.NpcText(npc)] = npc
    end
    for _, rank in ipairs(state.payload and state.payload.ranks or {}) do
        for _, npc in ipairs(rank.teachers or {}) do
            npcByText[Prof.NpcText(npc)] = npc
        end
    end
    for _, q in ipairs(region.quests or {}) do
        if q.npc then npcByText[Prof.NpcText(q.npc, "  (quest giver)")] = q.npc end
    end
    local y = -86
    for index, item in ipairs(collected) do
        local line = LearnLine(index)
        line:ClearAllPoints()
        line:SetPoint("TOPLEFT", LAYOUT.PAD + 6, y)
        line:SetPoint("RIGHT", -LAYOUT.PAD - 6, 0)
        line.npc = npcByText[item.text]
        line.text:SetText(item.text)
        if line.npc then
            line.text:SetTextColor(Kit.Accent())
        else
            Paint(line.text, item.colour)
        end
        local height = math.max(16, line.text:GetStringHeight())
        line:SetHeight(height)
        line:Show()
        y = y - height - 6
    end
    for index = #collected + 1, #pane.lines do
        pane.lines[index]:Hide()
    end
end

function Window.RenderRight()
    if state.tab == "unlearned" then return Window.RenderLearn() end
    Window.RenderDetail()
end

-- Buttons on the title bar, right to left from the close button by order.
-- spec = { text, width, order, tip, onClick(button), shown() }
local titleSpecs = {}
function Window.AddTitleButton(spec)
    titleSpecs[#titleSpecs + 1] = spec
    table.sort(titleSpecs, function(lhs, rhs) return lhs.order < rhs.order end)
end

local function LayoutTitleButtons()
    local anchor = win.close
    for _, spec in ipairs(titleSpecs) do
        if not spec.button then
            spec.button = Kit.Button(
                win.head,
                spec.text,
                spec.width or 64,
                24,
                function() spec.onClick(spec.button) end,
                { key = "essentials", tip = spec.tip }
            )
        end
        local show = not spec.shown or spec.shown()
        spec.button:SetShown(show)
        if show then
            spec.button:ClearAllPoints()
            spec.button:SetPoint("RIGHT", anchor, "LEFT", -8, 0)
            anchor = spec.button
        end
    end
end

function Window.RenderHeader(prof)
    win.title:SetText(state.linked and (state.linked ~= "" and (state.linked .. "'s " .. prof.name)) or prof.name)
    win.rankTitle:SetText(RANK_TITLE[prof.max] or "")
    LayoutTitleButtons()
    local r, g, b = Kit.Accent()
    win.logo:SetVertexColor(r, g, b)
    win.skillBar:SetStatusBarColor(r, g, b, 0.85)
    win.skillBar:SetMinMaxValues(0, math.max(prof.max, 1))
    win.skillBar:SetValue(prof.skill)
    win.skillBar.text:SetText(("%d / %d"):format(prof.skill, prof.max))
    local ready = state.line and not state.linked and Prof.RankReady(state.line, prof.skill, prof.max, prof.name)
    local banner = win.banner
    banner.npc = ready and ready.npc
    banner:SetShown(ready ~= nil and Get("rankAlert") ~= false)
    if ready then
        banner.text:SetText(
            ("|cffffd100%s is ready to learn.|r  %s%s"):format(
                ready.rankName,
                ready.how,
                ready.npc and (", " .. ready.npc[2]) or ""
            )
        )
        banner.pin:SetShown(ready.npc ~= nil)
    end
    local top = banner:IsShown() and -36 or 0
    win.aside:SetPoint("TOPLEFT", win.head, "BOTTOMLEFT", 0, top)
end

function Window.RenderTabs()
    local r, g, b = Kit.Accent()
    win.tabs[2]:SetShown(not state.linked)
    for _, tab in ipairs(win.tabs) do
        local on = tab.key == state.tab
        Paint(tab.text, on and { 1, 1, 1 } or COLOUR.muted)
        tab.count:SetText(tab.key == "learned" and learnedCount or unlearnedCount)
        tab.line:SetColorTexture(r, g, b, 1)
        tab.line:SetShown(on)
        tab:SetWidth(tab.text:GetStringWidth() + 5 + tab.count:GetStringWidth())
    end
    local n = FilterCount()
    win.filter:SetText(n > 0 and ("Filter (%d)"):format(n) or "Filter")
end

-- Reread the profession when it changed, then draw everything.
function Window.Render()
    if not win then return end
    local prof = Data.Profession()
    if not prof then return end
    if
        state.stale
        or not state.prof
        or state.prof.id ~= prof.id
        or state.prof.skill ~= prof.skill
        or state.prof.max ~= prof.max
        or state.readFor ~= state.linked
    then
        state.stale = false
        state.readFor = state.linked
        state.line = Data.Line(prof)
        state.categories = Data.Collect()
        state.unlearned, state.payload = Data.Unlearned(state.line, prof)
        -- Someone else's recipes: what they have not learned is not yours to know.
        if state.linked then state.unlearned = {} end
        state.spellIndex = nil
        wipe(Data.reagents)
    end
    state.prof = prof
    Window.RenderHeader(prof)
    BuildEntries()
    Window.RenderTabs()
    Window.RenderList()
    Window.RenderRight()
    for _, hook in ipairs(Window.hooks.render) do
        hook()
    end
end

function Window.RenderBook()
    win.title:SetText(TRADE_SKILLS or "Professions")
    win.rankTitle:SetText("")
    win.skillBar:Hide()
    local r, g, b = Kit.Accent()
    win.logo:SetVertexColor(r, g, b)
    local prof1, prof2, firstAid, fishing, cooking = GetProfessions()
    local indices = { prof1, prof2, cooking, fishing, firstAid }
    local names = {
        PROFESSIONS_COOKING or "Cooking",
        PROFESSIONS_FISHING or "Fishing",
        PROFESSIONS_FIRST_AID or "First Aid",
    }
    for index, card in ipairs(win.book.cards) do
        local slot = indices[index]
        if slot then
            local name, _, rank, maxRank, _, _, line, modifier = GetProfessionInfo(slot)
            card.name:SetText(name)
            card.name:SetTextColor(r, g, b)
            card.bar:SetStatusBarColor(r, g, b, 0.85)
            card.bar:SetMinMaxValues(0, math.max(maxRank or 0, 1))
            card.bar:SetValue(rank or 0)
            card.barText:SetText(
                ("%d / %d%s"):format(
                    rank or 0,
                    maxRank or 0,
                    (modifier or 0) > 0 and (" (+" .. modifier .. ")") or ""
                )
            )
            card.bar:Show()
            card.missing:Hide()
            local ready = Prof.RankReady(line, rank, maxRank, name)
            card.rank:SetShown(ready ~= nil)
            if ready then
                card.rank.npc = ready.npc
                card.rank.text:SetText(
                    ("|cffffd100%s is ready to learn.|r %s.%s"):format(
                        ready.rankName,
                        ready.how,
                        ready.npc and ("  " .. Prof.NpcText(ready.npc)) or ""
                    )
                )
            end
        else
            card.name:SetText(
                card.primary and (PROFESSIONS_FIRST_PROFESSION or "Primary Profession") or names[index - 2]
            )
            Paint(card.name, COLOUR.muted)
            card.missing:SetText(
                card.primary
                        and (PROFESSIONS_MISSING_PROFESSION or "Visit a profession trainer to learn one.")
                    or "Not learned yet."
            )
            card.bar:Hide()
            card.missing:Show()
            card.rank:Hide()
        end
    end
end

-------------------------------------------------------------------------------
--  Taking the game's window over
-------------------------------------------------------------------------------
local tabs = {}

local function DockTabs(on)
    local head = ProfessionsFrame and ProfessionsFrame.ProfessionsOverviewTab
    if not head then return end
    if on then
        if not tabs.points then
            tabs.points = {}
            for point = 1, head:GetNumPoints() do
                tabs.points[point] = { head:GetPoint(point) }
            end
        end
        head:ClearAllPoints()
        head:SetPoint("TOPLEFT", win, "TOPRIGHT", 0, -60)
    elseif tabs.points then
        head:ClearAllPoints()
        for _, pt in ipairs(tabs.points) do
            head:SetPoint(unpack(pt))
        end
        tabs.points = nil
    end
    if head.SetIgnoreParentAlpha then head:SetIgnoreParentAlpha(on) end
    for _, tab in ipairs(ProfessionsFrame.rightProfessionTabs or {}) do
        if tab.SetIgnoreParentAlpha then tab:SetIgnoreParentAlpha(on) end
    end
end

-- Our window sits on the game's window; dragging ours moves both, and the
-- spot is kept.
function Window.DragStart()
    if InCombatLockdown() then return end
    local left, top = win:GetLeft(), win:GetTop()
    win:ClearAllPoints()
    win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    win:StartMoving()
    state.moving = true
end

function Window.Follow()
    local pos = Get("windowPos")
    if not (pos and ProfessionsFrame) then return end
    if InCombatLockdown() then
        state.followPending = true
        return
    end
    state.followPending, state.following = nil, true
    local scale = win:GetEffectiveScale() / ProfessionsFrame:GetEffectiveScale()
    ProfessionsFrame:ClearAllPoints()
    ProfessionsFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x * scale, pos.y * scale)
    state.following = false
    win:ClearAllPoints()
    win:SetPoint("TOPLEFT", ProfessionsFrame, "TOPLEFT", 0, 0)
end

function Window.DragStop()
    if not state.moving then return end
    state.moving = false
    win:StopMovingOrSizing()
    F.Cfg().windowPos = { x = win:GetLeft(), y = win:GetTop() }
    Window.Follow()
end

local function Build()
    win = CreateFrame("Frame", "CludesUIRecipeWindow", UIParent)
    win:SetSize(LAYOUT.W, LAYOUT.H)
    win:SetMovable(true)
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    Kit.Panel(win, 0.97)
    BuildHeader()
    BuildBanner()
    BuildAside()
    BuildDetail()
    BuildLearn()
    BuildBook()
    win:Hide()
    win:SetPoint("TOPLEFT", ProfessionsFrame, "TOPLEFT", 0, 0)
end

local function Deactivate()
    if win then
        if InCombatLockdown() and win:IsProtected() then
            win:SetAlpha(0)
        else
            win:Hide()
        end
    end
    if ProfessionsFrame and state.active then
        DockTabs(false)
        DockCards(false)
        ProfessionsFrame:SetAlpha(1)
    end
    state.active = false
end

local function BookOpen()
    local book = ProfessionsFrame.BookPage
    return book and book:IsShown()
end

local function Activate(mode)
    if not win then Build() end
    -- A druid's Create buttons carry secure layers, which makes our window
    -- protected: in combat it cannot be shown, so the game's window stays.
    if InCombatLockdown() and win:IsProtected() and not win:IsShown() then
        ProfessionsFrame:SetAlpha(1)
        return
    end
    ProfessionsFrame:SetAlpha(0)
    win:SetAlpha(1)
    win:SetFrameStrata(ProfessionsFrame:GetFrameStrata() == "HIGH" and "DIALOG" or "HIGH")
    if not win:IsShown() then
        state.selected, state.picked, state.offset = nil, nil, 0
        state.stale = true
        win:Show()
        Window.Follow()
    end
    state.active = true
    DockTabs(true)
    local book = mode == "book"
    win.aside:SetShown(not book)
    win.detail:SetShown(not book)
    win.learn:SetShown(false)
    win.empty:SetShown(false)
    win.banner:SetShown(false)
    win.skillBar:SetShown(not book)
    win.book:SetShown(book)
    DockCards(book)
    if book then
        Window.RenderBook()
    else
        Window.Render()
    end
end

local function Update()
    if not (On() and ProfessionsFrame and ProfessionsFrame:IsShown()) then return Deactivate() end
    local linked = Data.Linked()
    if linked then
        if not Data.Profession() then return Deactivate() end
        if state.linked ~= linked then state.selected, state.offset = nil, 0 end
        state.linked, state.tab = linked, "learned"
        return Activate("craft")
    end
    state.linked = nil
    if not Data.Own() then return Deactivate() end
    if BookOpen() then return Activate("book") end
    if Data.Profession() then return Activate("craft") end
    Deactivate()
end

local queued = false
local function Queue(delay)
    if queued then return end
    queued = true
    C_Timer.After(delay or 0, function()
        queued = false
        Update()
    end)
end

local hooked = false
local function Hook()
    if hooked or not ProfessionsFrame then return end
    hooked = true
    ProfessionsFrame:HookScript("OnShow", function()
        if On() then ProfessionsFrame:SetAlpha(0) end
        Queue()
    end)
    ProfessionsFrame:HookScript("OnHide", Deactivate)
    hooksecurefunc(ProfessionsFrame, "SetPoint", function()
        if win and win:IsShown() and not state.following then Window.Follow() end
    end)
    local book = ProfessionsFrame.BookPage
    if book then
        book:HookScript("OnShow", function() Queue() end)
        book:HookScript("OnHide", function() Queue() end)
    end
end

local events = CreateFrame("Frame")
local QUIET = {
    BAG_UPDATE_DELAYED = true,
    ITEM_DATA_LOAD_RESULT = true,
    SPELL_UPDATE_USABLE = true,
    TRACKED_RECIPE_UPDATE = true,
    PLAYERBANKSLOTS_CHANGED = true,
}
local REREAD = {
    TRADE_SKILL_SHOW = true,
    TRADE_SKILL_DATA_SOURCE_CHANGED = true,
    NEW_RECIPE_LEARNED = true,
    SKILL_LINES_CHANGED = true,
    TRADE_SKILL_FAVORITES_CHANGED = true,
    TRADE_SKILL_LIST_UPDATE = true,
}
events:SetScript("OnEvent", function(_, event, arg)
    if event == "ADDON_LOADED" then
        if arg ~= "Blizzard_Professions" then return end
        events:UnregisterEvent("ADDON_LOADED")
    elseif event == "ITEM_DATA_LOAD_RESULT" then
        if not Data.waiting[arg] then return end
        Data.waiting[arg] = nil
    elseif event == "PLAYER_REGEN_ENABLED" then
        if state.dockPending ~= nil then DockCards(state.dockPending) end
        if state.followPending then Window.Follow() end
    end
    Hook()
    if REREAD[event] then state.stale = true end
    if QUIET[event] and not (win and win:IsShown()) then return end
    Queue(QUIET[event] and 0.1 or 0)
end)

local function Apply()
    events:UnregisterAllEvents()
    if not On() then return Deactivate() end
    for _, event in ipairs({
        "TRADE_SKILL_SHOW",
        "TRADE_SKILL_CLOSE",
        "TRADE_SKILL_LIST_UPDATE",
        "TRADE_SKILL_DATA_SOURCE_CHANGED",
        "NEW_RECIPE_LEARNED",
        "SKILL_LINES_CHANGED",
        "BAG_UPDATE_DELAYED",
        "ITEM_DATA_LOAD_RESULT",
        "SPELL_UPDATE_USABLE",
        "PLAYER_REGEN_ENABLED",
        "TRADE_SKILL_FAVORITES_CHANGED",
        "TRACKED_RECIPE_UPDATE",
        "PLAYERBANKSLOTS_CHANGED",
    }) do
        pcall(events.RegisterEvent, events, event)
    end
    Hook()
    if not hooked then events:RegisterEvent("ADDON_LOADED") end
    Queue()
end

CUI._RecipeWindow = {
    Apply = Apply,
    Render = function()
        if win and win:IsShown() then Window.Render() end
    end,
    State = state,
    Data = Data,
    Window = Window,
    SkillUps = SkillUps,
    Colour = COLOUR,
}

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    Apply()
end)
