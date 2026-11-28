if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
if not (CUI and CUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_Professions.lua  (WoW Forever only)
--  Professions (/cprof): a page for each of your professions with
--    Next rank      the rank your skill is ready for, and where to get it
--                   (a trainer and its cost, a book and who sells it, or the
--                   quest and its giver), nearest first.
--    Skill-ups      the recipes you know that still give skill, coloured as
--                   the game colours them: orange, yellow, green.
--    Recipe Finder  every recipe you have not learned, the skill it needs,
--                   and where it comes from: the trainer and its cost, the
--                   vendors that sell it, the mobs that drop it with their
--                   odds, or the quest that gives it.
--  Rank Alert: a chat line once when a profession is ready for its next rank.
--  What you know is read from the profession window when it opens (and
--  the spellbook), kept per character. Click a row to link the nearest
--  NPC's map pin in chat. Data: CludesUIForeverEssentials_RecipeData.lua.
-------------------------------------------------------------------------------
local _, module = ...

local F =
    module.Feature("professions", {
        enabled = false,
        rankAlert = true,
        showLater = true,
        craftWindow = true,
        skillUpChances = true,
        skillThresholds = true,
        sortSkillUps = false,
        altProfessions = true,
        craftOrders = true,
        skillUpPlan = true,
        craftProfit = true,
        disenchant = true,
        disenchantTooltip = true,
        tradeEnchants = true,
    })
local Get, On = F.Get, F.Enabled

local NPC_ID, NPC_TITLE, NPC_FACTION, NPC_CHART, NPC_X, NPC_Y, NPC_PRICE = 1, 2, 3, 4, 5, 6, 7
local TIER_LVL = { [150] = 10, [225] = 20, [300] = 35 }
local TIER_HEADING = { [150] = "Journeyman", [225] = "Expert", [300] = "Artisan" }
local GATHERING = { [182] = "Herbalism Trainer", [393] = "Skinning Trainer" }
local MINING = 186
local BRAND, DIM, AMBER = CUI.Kit.SyncAccent({}), { 0.6, 0.65, 0.7 }, { 1, 0.82, 0 }
local ORANGE, GOLDEN, GREEN, GREY = { 1, 0.5, 0.25 }, { 1, 1, 0 }, { 0.25, 0.75, 0.25 }, { 0.5, 0.5, 0.5 }
local function Dim(labelValue) return "|cff9aa6b2" .. labelValue .. "|r" end
local function Print(message) CUI.Print("|cff4cc9f0Professions:|r " .. message) end
local function Typeface() return CUI.GetFontPath("essentials") end

local RD
local function RecipeInfo()
    if not RD then
        RD = module.RecipeData()
        module.RecipeData = nil
    end
    return RD
end

local function Faction() return UnitFactionGroup("player") == "Horde" and "H" or "A" end
local function ForMe(fac) return fac == "-" or (fac or ""):find(Faction(), 1, true) ~= nil end
local function Money(copper)
    if not copper or copper <= 0 then return "free" end
    return C_CurrencyInfo.GetCoinTextureString(copper, 12)
end
local function ZoneName(chart)
    local details = chart and chart > 0 and C_Map.GetMapInfo(chart)
    return details and details.name or "?"
end
local function AreaTitle(ident) return ident and C_Map.GetAreaInfo(ident) or "?" end
local function ThingTitle(ident, fallback)
    local name = ident and C_Item.GetItemNameByID(ident)
    if name then return name end
    if ident then C_Item.RequestLoadItemDataByID(ident) end
    return fallback or "its recipe"
end

local function CharKeep(key)
    local conf = F.Cfg()
    conf[key] = conf[key] or {}
    local char = (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
    conf[key][char] = conf[key][char] or {}
    return conf[key][char]
end

-------------------------------------------------------------------------------
--  What you know: read from the profession window, kept per character
-------------------------------------------------------------------------------
local function Trained(spell)
    if CharKeep("known")[spell] then return true end
    return C_SpellBook.IsSpellKnown(spell)
end

local function LoadTradeCraft()
    if not (C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs) then return end
    if C_TradeSkillUI.IsTradeSkillLinked and C_TradeSkillUI.IsTradeSkillLinked() then return end
    if C_TradeSkillUI.IsTradeSkillGuild and C_TradeSkillUI.IsTradeSkillGuild() then return end
    if C_TradeSkillUI.IsNPCCrafting and C_TradeSkillUI.IsNPCCrafting() then return end
    local known = CharKeep("known")
    for _, ident in ipairs(C_TradeSkillUI.GetAllRecipeIDs() or {}) do
        local details = C_TradeSkillUI.GetRecipeInfo(ident)
        if details and details.learned then known[ident] = true end
    end
end

-- A trainer's own skill and cost for a recipe beat the data's (Forever moved some).
local function SweepTrainer()
    if not (IsTradeskillTrainer and IsTradeskillTrainer()) then return end
    local byTitle, rowOf = {}, {}
    for line, payload in pairs(RecipeInfo()) do
        rowOf[C_Spell.GetSpellName(payload.skillSpell) or ""] = line
        for _, region in ipairs(payload.recipes) do
            local name = C_Spell.GetSpellName(region.spell)
            if name then
                byTitle[name] = byTitle[name] or {}
                byTitle[name][#byTitle[name] + 1] = { r = region, line = line }
            end
        end
    end
    local overrides = F.Cfg()
    overrides.trainer = overrides.trainer or {}
    for idx = 1, GetNumTrainerServices() do
        local name, _, category = GetTrainerServiceInfo(idx)
        local craftTitle, tier = GetTrainerServiceSkillReq(idx)
        if name and category ~= "header" and tier and byTitle[name] then
            local line = rowOf[craftTitle or ""]
            for _, m in ipairs(byTitle[name]) do
                if not line or m.line == line then
                    overrides.trainer[m.r.spell] = { tier, GetTrainerServiceCost(idx) }
                end
            end
        end
    end
end

local function Craft(region)
    local o = F.Read().trainer and F.Read().trainer[region.spell]
    return o and o[1] or region.skill
end
local function Cost(region)
    local o = F.Read().trainer and F.Read().trainer[region.spell]
    return o and o[2] or region.cost
end

-------------------------------------------------------------------------------
--  Where things are: nearest first
-------------------------------------------------------------------------------
local function WorldPos(chart, posX, posY)
    local success, cont, place = pcall(C_Map.GetWorldPosFromMapPos, chart, CreateVector2D(posX, posY))
    if success and cont and place then return cont, place end
end

local function Closest(npcs, num)
    local chart = C_Map.GetBestMapForUnit("player")
    local here = chart and C_Map.GetPlayerMapPosition(chart, "player")
    local cont, place
    if here and not (issecretvalue and issecretvalue(here)) then
        cont, place = WorldPos(chart, here:GetXY())
    end
    local result = {}
    for _, npc in ipairs(npcs or {}) do
        if ForMe(npc[NPC_FACTION]) then
            local dist = math.huge
            if cont and npc[NPC_CHART] > 0 then
                local c, p = WorldPos(npc[NPC_CHART], npc[NPC_X] / 100, npc[NPC_Y] / 100)
                if c == cont then
                    local x1, y1 = place:GetXY()
                    local x2, y2 = p:GetXY()
                    dist = (x1 - x2) ^ 2 + (y1 - y2) ^ 2
                end
            end
            result[#result + 1] = { npc = npc, dist = dist }
        end
    end
    table.sort(result, function(lhs, rhs)
        if lhs.dist ~= rhs.dist then return lhs.dist < rhs.dist end
        return lhs.npc[NPC_TITLE] < rhs.npc[NPC_TITLE]
    end)
    local chosen = {}
    for idx = 1, math.min(num or #result, #result) do
        chosen[idx] = result[idx].npc
    end
    return chosen
end

local function ChainNpc(npc)
    if npc and npc[NPC_CHART] and npc[NPC_CHART] > 0 and module.DiscoveryLink then
        module.DiscoveryLink(npc[NPC_TITLE], npc[NPC_CHART], npc[NPC_X], npc[NPC_Y])
    elseif npc then
        Print(npc[NPC_TITLE] .. (npc[NPC_CHART] and npc[NPC_CHART] > 0 and (", " .. ZoneName(npc[NPC_CHART])) or ""))
    end
end

local function NpcLabel(npc, extra)
    return ("%s - %s %.1f, %.1f%s"):format(
        npc[NPC_TITLE],
        ZoneName(npc[NPC_CHART]),
        npc[NPC_X],
        npc[NPC_Y],
        extra or ""
    )
end

local function Lines(indices, payload)
    if not indices or type(indices[1]) ~= "number" then return indices or {} end
    local lineRoster = {}
    for idx, index in ipairs(indices) do
        lineRoster[idx] = payload.trainers[index]
    end
    return lineRoster
end

-------------------------------------------------------------------------------
--  Ranks, and gathering professions' trainers from the town map
-------------------------------------------------------------------------------
local gathered = {}
local function TradeInfo(line)
    local all = RecipeInfo()
    if all[line] then return all[line] end
    local heading, mining = GATHERING[line], all[MINING]
    if not (heading and mining and module.TownNPCList) then return end
    if not gathered[line] then
        local trainers = {}
        for chart, npcs in pairs(module.TownNPCList()) do
            for _, num in ipairs(npcs) do
                if num[3] == "profession" and num[5] == heading then
                    trainers[#trainers + 1] = { num[8] or 0, num[4], num[7] or "AH", chart, num[1], num[2] }
                end
            end
        end
        local ranks = {}
        for idx, tier in ipairs(mining.ranks) do
            ranks[idx] = { cap = tier.cap, skill = tier.skill, cost = tier.cost }
        end
        gathered[line] = { trainers = trainers, ranks = ranks, recipes = {} }
    end
    return gathered[line]
end

local function NextTier(payload, top)
    for _, tier in ipairs(payload.ranks or {}) do
        if tier.cap > top then return tier end
    end
end

local function TierTitle(tier, trade)
    if tier.name then return tier.name end
    if TIER_HEADING[tier.cap] then return TIER_HEADING[tier.cap] .. " " .. trade end
    return ("the next rank of %s (cap %d)"):format(trade, tier.cap)
end

-- How to get a rank: a line of text and the nearest NPC for it.
local function TierWhere(payload, tier)
    if tier.item then
        local npc = Closest(tier.vendors, 1)[1]
        return npc,
            ("Buy and read %s (%s)"):format(ThingTitle(tier.item, "its book"), Money(npc and npc[NPC_PRICE]))
    elseif tier.quest then
        local ident = tier.quest[Faction()]
        local heading = ident and C_QuestLog.GetTitleForQuestID(ident) or tier.questName or "its quest"
        return Closest(tier.teachers, 1)[1], ("Do the quest %s"):format(heading)
    end
    return Closest(tier.t and Lines(tier.t, payload) or payload.trainers, 1)[1],
        ("Train it for %s"):format(Money(tier.cost))
end

local function TierReady(line, craft, top, trade)
    local payload = TradeInfo(line)
    local tier = payload and (top or 0) > 0 and NextTier(payload, top)
    if not tier or (craft or 0) < tier.skill then return end
    if UnitLevel("player") < (tier.level or TIER_LVL[tier.cap] or 0) then return end
    local npc, how = TierWhere(payload, tier)
    return { rankName = TierTitle(tier, trade or ""), how = how, npc = npc, cap = tier.cap }
end

local function Professions()
    local items = {}
    for _, index in pairs({ GetProfessions() }) do
        if index then
            local name, glyphTex, craft, top, _, _, line = GetProfessionInfo(index)
            if name and line then
                items[#items + 1] =
                    { name = name, icon = glyphTex, skill = craft or 0, max = top or 0, line = line }
            end
        end
    end
    table.sort(items, function(lhs, rhs) return lhs.name < rhs.name end)
    return items
end

local function TestRanks(force)
    local announced = CharKeep("rankAlerted")
    local any = false
    for _, p in ipairs(Professions()) do
        local a = TierReady(p.line, p.skill, p.max, p.name)
        if a and (force or announced[p.line] ~= a.cap) then
            announced[p.line] = a.cap
            Print(
                ("%s is ready for |cff4cc9f0%s|r. %s%s. /cprof for where."):format(
                    p.name,
                    a.rankName,
                    a.how,
                    a.npc and (" from " .. a.npc[NPC_TITLE]) or ""
                )
            )
            any = true
        end
    end
    if any then
        pcall(PlaySound, SOUNDKIT.IG_QUEST_LIST_OPEN)
    elseif force then
        Print("no profession is ready for its next rank yet.")
    end
end

-------------------------------------------------------------------------------
--  A recipe's source, as tooltip lines and its nearest NPC
-------------------------------------------------------------------------------
local ORIGIN_LABEL = {
    trainer = "Trainer",
    teacher = "Trainer",
    vendor = "Vendor",
    drop = "Drop",
    quest = "Quest",
    unknown = "?",
}

local function Describe(region, payload, hintLabel)
    local function Row(labelValue, c)
        hintLabel:AddLine(labelValue, (c or DIM)[1], (c or DIM)[2], (c or DIM)[3], true)
    end
    local npc
    if region.source == "trainer" then
        Row(
            ("Trainer: %s.%s"):format(
                Money(Cost(region)),
                region.quest and (" Also a reward from the quest " .. region.quest .. ".") or ""
            ),
            { 1, 1, 1 }
        )
        local items = Closest(region.t and Lines(region.t, payload) or payload.trainers, 3)
        npc = items[1]
        for _, val in ipairs(items) do
            Row(NpcLabel(val))
        end
    elseif region.source == "teacher" then
        Row("Taught for free by the Artisan doctor:", { 1, 1, 1 })
        for _, tier in ipairs(payload.ranks) do
            if tier.teachers then
                local val = Closest(tier.teachers, 1)[1]
                if val then
                    npc = npc or val
                    Row(NpcLabel(val))
                end
            end
        end
    elseif region.source == "vendor" then
        local sellers = Closest(region.vendors)
        local unplaced = {}
        for _, s in ipairs(region.sellers or {}) do
            if ForMe(s[2]) then unplaced[#unplaced + 1] = s end
        end
        if #sellers == 0 and #unplaced == 0 then
            Row(
                ThingTitle(region.recipe, "Recipe")
                    .. ": only the other faction sells it; try the Auction House.",
                { 1, 1, 1 }
            )
        else
            local price = sellers[1] and sellers[1][NPC_PRICE] or unplaced[1] and unplaced[1][4]
            Row(
                ("%s, sold for %s%s by:"):format(
                    ThingTitle(region.recipe, "Recipe"),
                    Money(price),
                    region.rep and (" (needs " .. region.rep .. ")") or ""
                ),
                { 1, 1, 1 }
            )
            npc = sellers[1]
            for idx = 1, math.min(3, #sellers) do
                Row(NpcLabel(sellers[idx]))
            end
            for _, s in ipairs(unplaced) do
                Row(("%s - %s"):format(s[1], AreaTitle(s[3])))
            end
        end
    elseif region.source == "drop" and region.bosses then
        Row(ThingTitle(region.recipe, "Recipe") .. " drops from:", { 1, 1, 1 })
        for _, b in ipairs(region.bosses) do
            Row(("%s - %s"):format(b[1], b[2] and AreaTitle(b[2]) or "?"))
        end
    elseif region.source == "drop" and region.world then
        Row(
            ("%s: a world drop%s. Also try the Auction House."):format(
                ThingTitle(region.recipe, "Recipe"),
                region.world > 1 and (", from mobs around level " .. region.world) or ""
            ),
            { 1, 1, 1 }
        )
    elseif region.source == "drop" then
        local extra = {}
        if region.chests then extra[#extra + 1] = "chests and lockboxes" end
        if region.fished then extra[#extra + 1] = "fishing" end
        if region.pickpocket then extra[#extra + 1] = "pickpocketing" end
        local kinds = #extra > 0 and table.concat(extra, ", ") or nil
        local from = (region.mobs or 0) > 0
                and (("a world drop from %d kinds of mob"):format(region.mobs) .. (kinds and (", " .. kinds) or ""))
            or (kinds and ("found through " .. kinds) or "found")
        Row(
            ("%s: %s.%s"):format(
                ThingTitle(region.recipe, "Recipe"),
                from,
                #(region.drops or {}) > 0 and " Best odds:" or ""
            ),
            { 1, 1, 1 }
        )
        for _, skinInfo in ipairs(region.drops or {}) do
            local lvl = skinInfo[3] == skinInfo[4] and tostring(skinInfo[3])
                or (skinInfo[3] .. "-" .. skinInfo[4])
            Row(("%s (%s) - %s, %.1f%%"):format(skinInfo[1], lvl, AreaTitle(skinInfo[2]), skinInfo[5]))
        end
    elseif region.source == "quest" then
        local mine = {}
        for _, q in ipairs(region.quests or {}) do
            if ForMe(q.side or "AH") then mine[#mine + 1] = q end
        end
        if #mine == 0 then
            Row(
                ThingTitle(region.recipe, "Recipe")
                    .. ": a quest reward for the other faction; try the Auction House.",
                { 1, 1, 1 }
            )
        else
            local titleRoster = {}
            for idx, q in ipairs(mine) do
                titleRoster[idx] = (q.id and C_QuestLog.GetTitleForQuestID(q.id)) or q.name or "?"
            end
            Row(
                ThingTitle(region.recipe, "Recipe")
                    .. ": a reward from the quest "
                    .. table.concat(titleRoster, " or ")
                    .. ".",
                { 1, 1, 1 }
            )
            for _, q in ipairs(mine) do
                if q.npc then
                    npc = npc or q.npc
                    Row(NpcLabel(q.npc, "  (quest giver)"))
                end
            end
        end
    else
        Row(
            ThingTitle(region.recipe, "Recipe")
                .. ": where it comes from is not recorded yet; try the Auction House.",
            { 1, 1, 1 }
        )
    end
    return npc
end

local function ClosestFor(region, payload)
    local sink = setmetatable({}, {
        __index = function()
            return function() end
        end,
    })
    return Describe(region, payload, sink)
end

-------------------------------------------------------------------------------
--  Window
-------------------------------------------------------------------------------
local WIN_W, WIN_H = 600, 520
local frame, contentWindow, lineRoster, pageButtons = nil, nil, nil, {}
local currentRow

local function Tint(region, craft)
    local golden, grey = region.yellow or region.skill, region.grey or (region.skill + 40)
    local green = math.floor((golden + grey) / 2)
    if craft < golden then return ORANGE, "orange" end
    if craft < green then return GOLDEN, "yellow" end
    if craft < grey then return GREEN, "green" end
    return GREY, "grey"
end

local function RecipeTitle(region)
    return C_Spell.GetSpellName(region.spell) or ThingTitle(region.item, ("recipe %d"):format(region.spell))
end

local function RecipeGlyph(region)
    return (region.item and C_Item.GetItemIconByID(region.item))
        or C_Spell.GetSpellTexture(region.spell)
        or 134400
end

local function Render()
    if not (frame and frame:IsShown()) then return end
    CUI.Kit.SyncAccent(BRAND)
    lineRoster:Reset()
    local profs = Professions()
    local posX = 0
    for idx, p in ipairs(profs) do
        local widget = pageButtons[idx]
        if not widget then
            widget = CUI.Kit.Button(frame.tabBar, "", 90, 22, nil, { key = "essentials" })
            widget:SetHeight(22)
            pageButtons[idx] = widget
        end
        widget:SetText(p.name)
        widget:SetWidth(math.max(80, widget:GetTextWidth() + 24))
        widget:ClearAllPoints()
        widget:SetPoint("LEFT", frame.tabBar, "LEFT", posX, 0)
        widget:SetScript("OnClick", function()
            currentRow = p.line
            Render()
        end)
        widget:Show()
        posX = posX + widget:GetWidth() + 4
    end
    for idx = #profs + 1, #pageButtons do
        pageButtons[idx]:Hide()
    end
    local trade
    for _, p in ipairs(profs) do
        if p.line == currentRow then trade = p end
    end
    trade = trade or profs[1]
    for idx, p in ipairs(profs) do
        if p == trade then
            pageButtons[idx]:SetActive(true)
        else
            pageButtons[idx]:SetActive(false)
        end
    end
    if not trade then
        lineRoster:Line("You have no professions yet.", { colour = DIM })
        contentWindow:SetHeight(lineRoster:Height() + 10)
        return
    end
    currentRow = trade.line
    local payload = TradeInfo(trade.line)
    lineRoster:Line(
        ("%s  %s"):format(trade.name, Dim(("%d / %d"):format(trade.skill, trade.max))),
        { size = 16, colour = BRAND, icon = trade.icon }
    )
    if not payload then
        lineRoster:Line("No recipe data for this profession.", { colour = DIM })
        contentWindow:SetHeight(lineRoster:Height() + 10)
        return
    end
    -- Next rank.
    local tier = NextTier(payload, trade.max)
    if tier then
        local npc, how = TierWhere(payload, tier)
        local ready = trade.skill >= tier.skill
            and UnitLevel("player") >= (tier.level or TIER_LVL[tier.cap] or 0)
        lineRoster:Gap(4)
        lineRoster:Line(("Next rank: %s"):format(TierTitle(tier, trade.name)), {
            size = 13,
            colour = AMBER,
            right = ready and "ready" or ("at skill %d"):format(tier.skill),
            rightColour = ready and { 0.38, 0.85, 0.5 } or DIM,
        })
        lineRoster:Line(how .. (npc and (Dim("\n" .. NpcLabel(npc))) or ""), {
            indent = 14,
            onClick = npc and function() ChainNpc(npc) end,
            tip = npc and function(hintLabel)
                hintLabel:SetText(npc[NPC_TITLE], 1, 1, 1)
                hintLabel:AddLine("Click to link its map pin in chat.", unpack(DIM))
            end,
        })
    end
    -- Skill-ups from what you know.
    local gains = {}
    for _, region in ipairs(payload.recipes) do
        if Trained(region.spell) and trade.skill < (region.grey or 0) and trade.skill < trade.max then
            gains[#gains + 1] = region
        end
    end
    table.sort(gains, function(lhs, rhs) return (lhs.grey or 0) < (rhs.grey or 0) end)
    if #gains > 0 then
        lineRoster:Gap(6)
        lineRoster:Line("Skill-ups", { size = 13, colour = AMBER })
        for _, region in ipairs(gains) do
            local c = Tint(region, trade.skill)
            lineRoster:Line(RecipeTitle(region), {
                icon = RecipeGlyph(region),
                colour = c,
                right = ("%d / %d / %d"):format(
                    region.yellow or region.skill,
                    math.floor(((region.yellow or region.skill) + (region.grey or 0)) / 2),
                    region.grey or 0
                ),
                tip = function(hintLabel)
                    if region.item then
                        hintLabel:SetItemByID(region.item)
                    else
                        hintLabel:SetSpellByID(region.spell)
                    end
                    hintLabel:AddLine(
                        ("Yellow at %d, green at %d, gray at %d."):format(
                            region.yellow or region.skill,
                            math.floor(((region.yellow or region.skill) + (region.grey or 0)) / 2),
                            region.grey or 0
                        ),
                        unpack(BRAND)
                    )
                end,
            })
        end
    end
    -- Recipe Finder.
    local nowTime, later = {}, {}
    for _, region in ipairs(payload.recipes) do
        if not Trained(region.spell) then
            if trade.skill >= Craft(region) then
                nowTime[#nowTime + 1] = region
            elseif Get("showLater") then
                later[#later + 1] = region
            end
        end
    end
    local function ByCraft(a, b)
        if Craft(a) ~= Craft(b) then return Craft(a) < Craft(b) end
        return a.spell < b.spell
    end
    table.sort(nowTime, ByCraft)
    table.sort(later, ByCraft)
    local function FinderLine(region, ready)
        local label = ORIGIN_LABEL[region.source] or "?"
        lineRoster:Line(
            RecipeTitle(region)
                .. "\n"
                .. Dim(label .. (region.source == "trainer" and (" " .. Money(Cost(region))) or "")),
            {
                icon = RecipeGlyph(region),
                colour = ready and { 0.38, 0.85, 0.5 }
                    or (trade.max < Craft(region) and { 1, 0.5, 0.25 } or { 1, 1, 1 }),
                right = ("%d"):format(Craft(region)),
                tip = function(hintLabel)
                    hintLabel:SetText(RecipeTitle(region), 1, 1, 1)
                    hintLabel:AddLine(
                        ("Requires %s %d (you: %d/%d)"):format(trade.name, Craft(region), trade.skill, trade.max),
                        unpack(AMBER)
                    )
                    if region.yellow and region.grey then
                        hintLabel:AddLine(
                            ("Yellow at %d, green at %d, gray at %d."):format(
                                region.yellow,
                                math.floor((region.yellow + region.grey) / 2),
                                region.grey
                            ),
                            unpack(BRAND)
                        )
                    end
                    Describe(region, payload, hintLabel)
                    hintLabel:AddLine("Click to link the nearest one's map pin in chat.", unpack(DIM))
                end,
                onClick = function()
                    local npc = ClosestFor(region, payload)
                    if npc then ChainNpc(npc) end
                end,
            }
        )
    end
    if #nowTime > 0 then
        lineRoster:Gap(6)
        lineRoster:Line(("You can learn now  %s"):format(Dim(#nowTime)), { size = 13, colour = AMBER })
        for _, region in ipairs(nowTime) do
            FinderLine(region, true)
        end
    end
    if #later > 0 then
        lineRoster:Gap(6)
        lineRoster:Line(("Later  %s"):format(Dim(#later)), { size = 13, colour = AMBER })
        for _, region in ipairs(later) do
            FinderLine(region, false)
        end
    end
    if #nowTime == 0 and #later == 0 and #payload.recipes > 0 then
        lineRoster:Gap(6)
        lineRoster:Line("You know every recipe the data has for this profession.", { colour = DIM })
    end
    contentWindow:SetHeight(lineRoster:Height() + 10)
end

local function MakeFrame()
    frame = CreateFrame("Frame", "CludesUIProfessions", UIParent)
    frame:SetSize(WIN_W, WIN_H)
    frame:SetPoint("CENTER", 0, 30)
    CUI.Kit.Panel(frame, 0.96)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    local heading = frame:CreateFontString(nil, "OVERLAY")
    CUI.Kit.Font(heading, 15, "essentials")
    heading:SetPoint("TOPLEFT", 10, -8)
    heading:SetText("Professions")
    CUI.Kit.AccentText(heading)
    local shut = CUI.Kit.Glyph(frame, "x", function() frame:Hide() end, nil, "essentials")
    shut:SetPoint("TOPRIGHT", -5, -5)
    frame.tabBar = CreateFrame("Frame", nil, frame)
    frame.tabBar:SetPoint("TOPLEFT", 10, -32)
    frame.tabBar:SetSize(WIN_W - 20, 22)
    local scroll = (CUI.Kit.Scroll(frame))
    scroll:SetPoint("TOPLEFT", 10, -60)
    scroll:SetPoint("BOTTOMRIGHT", -30, 10)
    contentWindow = CreateFrame("Frame", nil, scroll)
    contentWindow:SetSize(WIN_W - 44, 10)
    scroll:SetScrollChild(contentWindow)
    lineRoster = module.DiscoveryRows(contentWindow)
    frame:Hide()
    tinsert(UISpecialFrames, "CludesUIProfessions")
end

local function Reveal(line)
    if not frame then MakeFrame() end
    if line then currentRow = line end
    frame:Show()
    Render()
end

-------------------------------------------------------------------------------
--  Events and apply
-------------------------------------------------------------------------------
local queued
local eventWindow = CreateFrame("Frame")
eventWindow:SetScript("OnEvent", function(_, evt)
    if evt == "TRADE_SKILL_SHOW" or evt == "TRADE_SKILL_LIST_UPDATE" or evt == "NEW_RECIPE_LEARNED" then
        LoadTradeCraft()
    elseif evt == "TRAINER_SHOW" or evt == "TRAINER_UPDATE" then
        C_Timer.After(0.2, SweepTrainer)
    end
    if queued then return end
    queued = true
    C_Timer.After(1, function()
        queued = false
        if Get("rankAlert") and On() then TestRanks(false) end
        Render()
    end)
end)

local function Apply()
    eventWindow:UnregisterAllEvents()
    if CUI._RecipeWindow then CUI._RecipeWindow.Apply() end
    if CUI._Disenchant then CUI._Disenchant.Apply() end
    if CUI._TradeEnchants then CUI._TradeEnchants.Apply() end
    if not On() then
        if frame then frame:Hide() end
        return
    end
    for _, event in ipairs({
        "SKILL_LINES_CHANGED",
        "PLAYER_LEVEL_UP",
        "TRADE_SKILL_SHOW",
        "TRADE_SKILL_LIST_UPDATE",
        "NEW_RECIPE_LEARNED",
        "TRAINER_SHOW",
        "TRAINER_UPDATE",
        "LEARNED_SPELL_IN_TAB",
    }) do
        pcall(eventWindow.RegisterEvent, eventWindow, event)
    end
    if Get("rankAlert") then
        C_Timer.After(5, function()
            if On() then TestRanks(false) end
        end)
    end
end

SLASH_CUIPROF1 = "/cprof"
SlashCmdList.CUIPROF = function(message)
    if not On() then
        Print("turn on Professions in CludesUI Forever Tools first.")
        return
    end
    if (message or ""):lower():find("rank") then return TestRanks(true) end
    if frame and frame:IsShown() then
        frame:Hide()
    else
        Reveal()
    end
end

CUI._Professions = {
    Get = Get,
    Cfg = F.Cfg,
    Apply = Apply,
    Open = function() Reveal() end,
    CheckRanks = function() TestRanks(true) end,
}

-- What the recipe window (CludesUIForeverEssentials_CraftWindow.lua) shares with /cprof.
module.Prof = {
    F = F,
    RecipeData = RecipeInfo,
    ProfData = TradeInfo,
    Learned = Trained,
    Skill = Craft,
    Cost = Cost,
    Describe = Describe,
    NearestFor = ClosestFor,
    LinkNpc = ChainNpc,
    NpcText = NpcLabel,
    RankReady = TierReady,
    CharStore = CharKeep,
    Money = Money,
    SOURCE_TAG = ORIGIN_LABEL,
}

F.Start(Apply)
