if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if not (CludesUI and CludesUI.IS_FOREVER) then
    return
end
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

local F = module.Feature("professions", { enabled = false, rankAlert = true, showLater = true })
local Get, On = F.Get, F.Enabled

local NPC_ID, NPC_NAME, NPC_FACTION, NPC_MAP, NPC_X, NPC_Y, NPC_PRICE = 1, 2, 3, 4, 5, 6, 7
local RANK_LEVEL = { [150] = 10, [225] = 20, [300] = 35 }
local RANK_TITLE = { [150] = "Journeyman", [225] = "Expert", [300] = "Artisan" }
local GATHERING = { [182] = "Herbalism Trainer", [393] = "Skinning Trainer" }
local MINING = 186
local ACCENT, MUTED, GOLD = CludesUI.Kit.SyncAccent({}), { 0.6, 0.65, 0.7 }, { 1, 0.82, 0 }
local ORANGE, YELLOW, GREEN, GREY = { 1, 0.5, 0.25 }, { 1, 1, 0 }, { 0.25, 0.75, 0.25 }, { 0.5, 0.5, 0.5 }
local function Muted(textValue)
    return "|cff9aa6b2" .. textValue .. "|r"
end
local function Print(msg)
    CludesUI.Print("|cff4cc9f0Professions:|r " .. msg)
end
local function Font()
    return CludesUI.GetFontPath("essentials")
end

local RD
local function RecipeData()
    if not RD then
        RD = module.RecipeData()
        module.RecipeData = nil
    end
    return RD
end

local function Faction()
    return UnitFactionGroup("player") == "Horde" and "H" or "A"
end
local function ForMe(fac)
    return fac == "-" or (fac or ""):find(Faction(), 1, true) ~= nil
end
local function Money(copper)
    if not copper or copper <= 0 then
        return "free"
    end
    return C_CurrencyInfo.GetCoinTextureString(copper, 12)
end
local function ZoneName(map)
    local details = map and map > 0 and C_Map.GetMapInfo(map)
    return details and details.name or "?"
end
local function AreaName(ident)
    return ident and C_Map.GetAreaInfo(ident) or "?"
end
local function ItemName(ident, fallback)
    local name = ident and C_Item.GetItemNameByID(ident)
    if name then
        return name
    end
    if ident then
        C_Item.RequestLoadItemDataByID(ident)
    end
    return fallback or "its recipe"
end

local function CharStore(key)
    local conf = F.Cfg()
    conf[key] = conf[key] or {}
    local char = (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
    conf[key][char] = conf[key][char] or {}
    return conf[key][char]
end

-------------------------------------------------------------------------------
--  What you know: read from the profession window, kept per character
-------------------------------------------------------------------------------
local function Learned(spell)
    if CharStore("known")[spell] then
        return true
    end
    return C_SpellBook.IsSpellKnown(spell)
end

local function ReadTradeSkill()
    if not (C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs) then
        return
    end
    if C_TradeSkillUI.IsTradeSkillLinked and C_TradeSkillUI.IsTradeSkillLinked() then
        return
    end
    if C_TradeSkillUI.IsTradeSkillGuild and C_TradeSkillUI.IsTradeSkillGuild() then
        return
    end
    if C_TradeSkillUI.IsNPCCrafting and C_TradeSkillUI.IsNPCCrafting() then
        return
    end
    local known = CharStore("known")
    for _, ident in ipairs(C_TradeSkillUI.GetAllRecipeIDs() or {}) do
        local details = C_TradeSkillUI.GetRecipeInfo(ident)
        if details and details.learned then
            known[ident] = true
        end
    end
end

-- A trainer's own skill and cost for a recipe beat the data's (Forever moved some).
local function ScanTrainer()
    if not (IsTradeskillTrainer and IsTradeskillTrainer()) then
        return
    end
    local byName, lineOf = {}, {}
    for lineTex, payload in pairs(RecipeData()) do
        lineOf[C_Spell.GetSpellName(payload.skillSpell) or ""] = lineTex
        for _, r in ipairs(payload.recipes) do
            local name = C_Spell.GetSpellName(r.spell)
            if name then
                byName[name] = byName[name] or {}
                byName[name][#byName[name] + 1] = { r = r, line = lineTex }
            end
        end
    end
    local overrides = F.Cfg()
    overrides.trainer = overrides.trainer or {}
    for idx = 1, GetNumTrainerServices() do
        local name, _, category = GetTrainerServiceInfo(idx)
        local skillName, rank = GetTrainerServiceSkillReq(idx)
        if name and category ~= "header" and rank and byName[name] then
            local lineTex = lineOf[skillName or ""]
            for _, m in ipairs(byName[name]) do
                if not lineTex or m.line == lineTex then
                    overrides.trainer[m.r.spell] = { rank, GetTrainerServiceCost(idx) }
                end
            end
        end
    end
end

local function Skill(r)
    local o = F.Read().trainer and F.Read().trainer[r.spell]
    return o and o[1] or r.skill
end
local function Cost(r)
    local o = F.Read().trainer and F.Read().trainer[r.spell]
    return o and o[2] or r.cost
end

-------------------------------------------------------------------------------
--  Where things are: nearest first
-------------------------------------------------------------------------------
local function WorldPos(map, posX, posY)
    local success, cont, place = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(posX, posY))
    if success and cont and place then
        return cont, place
    end
end

local function Nearest(npcs, num)
    local map = C_Map.GetBestMapForUnit("player")
    local here = map and C_Map.GetPlayerMapPosition(map, "player")
    local cont, place
    if here and not (issecretvalue and issecretvalue(here)) then
        cont, place = WorldPos(map, here:GetXY())
    end
    local result = {}
    for _, npc in ipairs(npcs or {}) do
        if ForMe(npc[NPC_FACTION]) then
            local dist = math.huge
            if cont and npc[NPC_MAP] > 0 then
                local c, p = WorldPos(npc[NPC_MAP], npc[NPC_X] / 100, npc[NPC_Y] / 100)
                if c == cont then
                    local x1, y1 = place:GetXY()
                    local x2, y2 = p:GetXY()
                    dist = (x1 - x2) ^ 2 + (y1 - y2) ^ 2
                end
            end
            result[#result + 1] = { npc = npc, dist = dist }
        end
    end
    table.sort(result, function(a, b)
        if a.dist ~= b.dist then
            return a.dist < b.dist
        end
        return a.npc[NPC_NAME] < b.npc[NPC_NAME]
    end)
    local picked = {}
    for idx = 1, math.min(num or #result, #result) do
        picked[idx] = result[idx].npc
    end
    return picked
end

local function LinkNpc(npc)
    if npc and npc[NPC_MAP] and npc[NPC_MAP] > 0 and module.DiscoveryLink then
        module.DiscoveryLink(npc[NPC_NAME], npc[NPC_MAP], npc[NPC_X], npc[NPC_Y])
    elseif npc then
        Print(npc[NPC_NAME] .. (npc[NPC_MAP] and npc[NPC_MAP] > 0 and (", " .. ZoneName(npc[NPC_MAP])) or ""))
    end
end

local function NpcText(npc, extra)
    return ("%s - %s %.1f, %.1f%s"):format(
        npc[NPC_NAME],
        ZoneName(npc[NPC_MAP]),
        npc[NPC_X],
        npc[NPC_Y],
        extra or ""
    )
end

local function Rows(indices, payload)
    if not indices or type(indices[1]) ~= "number" then
        return indices or {}
    end
    local rowList = {}
    for idx, slotPos in ipairs(indices) do
        rowList[idx] = payload.trainers[slotPos]
    end
    return rowList
end

-------------------------------------------------------------------------------
--  Ranks, and gathering professions' trainers from the town map
-------------------------------------------------------------------------------
local gathered = {}
local function ProfData(lineTex)
    local all = RecipeData()
    if all[lineTex] then
        return all[lineTex]
    end
    local titleText, mining = GATHERING[lineTex], all[MINING]
    if not (titleText and mining and module.TownNPCList) then
        return
    end
    if not gathered[lineTex] then
        local trainers = {}
        for map, npcs in pairs(module.TownNPCList()) do
            for _, num in ipairs(npcs) do
                if num[3] == "profession" and num[5] == titleText then
                    trainers[#trainers + 1] = { num[8] or 0, num[4], num[7] or "AH", map, num[1], num[2] }
                end
            end
        end
        local ranks = {}
        for idx, rank in ipairs(mining.ranks) do
            ranks[idx] = { cap = rank.cap, skill = rank.skill, cost = rank.cost }
        end
        gathered[lineTex] = { trainers = trainers, ranks = ranks, recipes = {} }
    end
    return gathered[lineTex]
end

local function NextRank(payload, upper)
    for _, rank in ipairs(payload.ranks or {}) do
        if rank.cap > upper then
            return rank
        end
    end
end

local function RankName(rank, prof)
    if rank.name then
        return rank.name
    end
    if RANK_TITLE[rank.cap] then
        return RANK_TITLE[rank.cap] .. " " .. prof
    end
    return ("the next rank of %s (cap %d)"):format(prof, rank.cap)
end

-- How to get a rank: a line of text and the nearest NPC for it.
local function RankWhere(payload, rank)
    if rank.item then
        local npc = Nearest(rank.vendors, 1)[1]
        return npc,
            ("Buy and read %s (%s)"):format(ItemName(rank.item, "its book"), Money(npc and npc[NPC_PRICE]))
    elseif rank.quest then
        local ident = rank.quest[Faction()]
        local titleText = ident and C_QuestLog.GetTitleForQuestID(ident) or rank.questName or "its quest"
        return Nearest(rank.teachers, 1)[1], ("Do the quest %s"):format(titleText)
    end
    return Nearest(rank.t and Rows(rank.t, payload) or payload.trainers, 1)[1],
        ("Train it for %s"):format(Money(rank.cost))
end

local function RankReady(lineTex, skill, upper, prof)
    local payload = ProfData(lineTex)
    local rank = payload and (upper or 0) > 0 and NextRank(payload, upper)
    if not rank or (skill or 0) < rank.skill then
        return
    end
    if UnitLevel("player") < (rank.level or RANK_LEVEL[rank.cap] or 0) then
        return
    end
    local npc, how = RankWhere(payload, rank)
    return { rankName = RankName(rank, prof or ""), how = how, npc = npc, cap = rank.cap }
end

local function Professions()
    local entries = {}
    for _, slotPos in pairs({ GetProfessions() }) do
        if slotPos then
            local name, glyph, skill, upper, _, _, lineTex = GetProfessionInfo(slotPos)
            if name and lineTex then
                entries[#entries + 1] =
                    { name = name, icon = glyph, skill = skill or 0, max = upper or 0, line = lineTex }
            end
        end
    end
    table.sort(entries, function(a, b)
        return a.name < b.name
    end)
    return entries
end

local function CheckRanks(force)
    local announced = CharStore("rankAlerted")
    local any = false
    for _, p in ipairs(Professions()) do
        local a = RankReady(p.line, p.skill, p.max, p.name)
        if a and (force or announced[p.line] ~= a.cap) then
            announced[p.line] = a.cap
            Print(
                ("%s is ready for |cff4cc9f0%s|r. %s%s. /cprof for where."):format(
                    p.name,
                    a.rankName,
                    a.how,
                    a.npc and (" from " .. a.npc[NPC_NAME]) or ""
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
local SOURCE_TAG = {
    trainer = "Trainer",
    teacher = "Trainer",
    vendor = "Vendor",
    drop = "Drop",
    quest = "Quest",
    unknown = "?",
}

local function Describe(r, payload, tipText)
    local function Line(textValue, c)
        tipText:AddLine(textValue, (c or MUTED)[1], (c or MUTED)[2], (c or MUTED)[3], true)
    end
    local npc
    if r.source == "trainer" then
        Line(
            ("Trainer: %s.%s"):format(
                Money(Cost(r)),
                r.quest and (" Also a reward from the quest " .. r.quest .. ".") or ""
            ),
            { 1, 1, 1 }
        )
        local entries = Nearest(r.t and Rows(r.t, payload) or payload.trainers, 3)
        npc = entries[1]
        for _, val in ipairs(entries) do
            Line(NpcText(val))
        end
    elseif r.source == "teacher" then
        Line("Taught for free by the Artisan doctor:", { 1, 1, 1 })
        for _, rank in ipairs(payload.ranks) do
            if rank.teachers then
                local val = Nearest(rank.teachers, 1)[1]
                if val then
                    npc = npc or val
                    Line(NpcText(val))
                end
            end
        end
    elseif r.source == "vendor" then
        local sellers = Nearest(r.vendors)
        local unplaced = {}
        for _, s in ipairs(r.sellers or {}) do
            if ForMe(s[2]) then
                unplaced[#unplaced + 1] = s
            end
        end
        if #sellers == 0 and #unplaced == 0 then
            Line(
                ItemName(r.recipe, "Recipe") .. ": only the other faction sells it; try the Auction House.",
                { 1, 1, 1 }
            )
        else
            local price = sellers[1] and sellers[1][NPC_PRICE] or unplaced[1] and unplaced[1][4]
            Line(
                ("%s, sold for %s%s by:"):format(
                    ItemName(r.recipe, "Recipe"),
                    Money(price),
                    r.rep and (" (needs " .. r.rep .. ")") or ""
                ),
                { 1, 1, 1 }
            )
            npc = sellers[1]
            for idx = 1, math.min(3, #sellers) do
                Line(NpcText(sellers[idx]))
            end
            for _, s in ipairs(unplaced) do
                Line(("%s - %s"):format(s[1], AreaName(s[3])))
            end
        end
    elseif r.source == "drop" and r.bosses then
        Line(ItemName(r.recipe, "Recipe") .. " drops from:", { 1, 1, 1 })
        for _, b in ipairs(r.bosses) do
            Line(("%s - %s"):format(b[1], b[2] and AreaName(b[2]) or "?"))
        end
    elseif r.source == "drop" and r.world then
        Line(
            ("%s: a world drop%s. Also try the Auction House."):format(
                ItemName(r.recipe, "Recipe"),
                r.world > 1 and (", from mobs around level " .. r.world) or ""
            ),
            { 1, 1, 1 }
        )
    elseif r.source == "drop" then
        local extra = {}
        if r.chests then
            extra[#extra + 1] = "chests and lockboxes"
        end
        if r.fished then
            extra[#extra + 1] = "fishing"
        end
        if r.pickpocket then
            extra[#extra + 1] = "pickpocketing"
        end
        local kinds = #extra > 0 and table.concat(extra, ", ") or nil
        local from = (r.mobs or 0) > 0
                and (("a world drop from %d kinds of mob"):format(r.mobs) .. (kinds and (", " .. kinds) or ""))
            or (kinds and ("found through " .. kinds) or "found")
        Line(
            ("%s: %s.%s"):format(
                ItemName(r.recipe, "Recipe"),
                from,
                #(r.drops or {}) > 0 and " Best odds:" or ""
            ),
            { 1, 1, 1 }
        )
        for _, d in ipairs(r.drops or {}) do
            local level = d[3] == d[4] and tostring(d[3]) or (d[3] .. "-" .. d[4])
            Line(("%s (%s) - %s, %.1f%%"):format(d[1], level, AreaName(d[2]), d[5]))
        end
    elseif r.source == "quest" then
        local mine = {}
        for _, q in ipairs(r.quests or {}) do
            if ForMe(q.side or "AH") then
                mine[#mine + 1] = q
            end
        end
        if #mine == 0 then
            Line(
                ItemName(r.recipe, "Recipe")
                    .. ": a quest reward for the other faction; try the Auction House.",
                { 1, 1, 1 }
            )
        else
            local nameList = {}
            for idx, q in ipairs(mine) do
                nameList[idx] = (q.id and C_QuestLog.GetTitleForQuestID(q.id)) or q.name or "?"
            end
            Line(
                ItemName(r.recipe, "Recipe")
                    .. ": a reward from the quest "
                    .. table.concat(nameList, " or ")
                    .. ".",
                { 1, 1, 1 }
            )
            for _, q in ipairs(mine) do
                if q.npc then
                    npc = npc or q.npc
                    Line(NpcText(q.npc, "  (quest giver)"))
                end
            end
        end
    else
        Line(
            ItemName(r.recipe, "Recipe")
                .. ": where it comes from is not recorded yet; try the Auction House.",
            { 1, 1, 1 }
        )
    end
    return npc
end

local function NearestFor(r, payload)
    local sink = setmetatable({}, {
        __index = function()
            return function() end
        end,
    })
    return Describe(r, payload, sink)
end

-------------------------------------------------------------------------------
--  Window
-------------------------------------------------------------------------------
local WIN_W, WIN_H = 600, 520
local window, contentFrame, rowList, tabButtons = nil, nil, nil, {}
local currentLine

local function Colour(r, skill)
    local yellow, grey = r.yellow or r.skill, r.grey or (r.skill + 40)
    local green = math.floor((yellow + grey) / 2)
    if skill < yellow then
        return ORANGE, "orange"
    end
    if skill < green then
        return YELLOW, "yellow"
    end
    if skill < grey then
        return GREEN, "green"
    end
    return GREY, "grey"
end

local function RecipeName(r)
    return C_Spell.GetSpellName(r.spell) or ItemName(r.item, ("recipe %d"):format(r.spell))
end

local function RecipeIcon(r)
    return (r.item and C_Item.GetItemIconByID(r.item)) or C_Spell.GetSpellTexture(r.spell) or 134400
end

local function Draw()
    if not (window and window:IsShown()) then
        return
    end
    CludesUI.Kit.SyncAccent(ACCENT)
    rowList:Reset()
    local profs = Professions()
    local posX = 0
    for idx, p in ipairs(profs) do
        local b = tabButtons[idx]
        if not b then
            b = CludesUI.Kit.Button(window.tabBar, "", 90, 22, nil, { key = "essentials" })
            b:SetHeight(22)
            tabButtons[idx] = b
        end
        b:SetText(p.name)
        b:SetWidth(math.max(80, b:GetTextWidth() + 24))
        b:ClearAllPoints()
        b:SetPoint("LEFT", window.tabBar, "LEFT", posX, 0)
        b:SetScript("OnClick", function()
            currentLine = p.line
            Draw()
        end)
        b:Show()
        posX = posX + b:GetWidth() + 4
    end
    for idx = #profs + 1, #tabButtons do
        tabButtons[idx]:Hide()
    end
    local prof
    for _, p in ipairs(profs) do
        if p.line == currentLine then
            prof = p
        end
    end
    prof = prof or profs[1]
    for idx, p in ipairs(profs) do
        if p == prof then
            tabButtons[idx]:SetActive(true)
        else
            tabButtons[idx]:SetActive(false)
        end
    end
    if not prof then
        rowList:Line("You have no professions yet.", { colour = MUTED })
        contentFrame:SetHeight(rowList:Height() + 10)
        return
    end
    currentLine = prof.line
    local payload = ProfData(prof.line)
    rowList:Line(
        ("%s  %s"):format(prof.name, Muted(("%d / %d"):format(prof.skill, prof.max))),
        { size = 16, colour = ACCENT, icon = prof.icon }
    )
    if not payload then
        rowList:Line("No recipe data for this profession.", { colour = MUTED })
        contentFrame:SetHeight(rowList:Height() + 10)
        return
    end
    -- Next rank.
    local rank = NextRank(payload, prof.max)
    if rank then
        local npc, how = RankWhere(payload, rank)
        local ready = prof.skill >= rank.skill
            and UnitLevel("player") >= (rank.level or RANK_LEVEL[rank.cap] or 0)
        rowList:Gap(4)
        rowList:Line(("Next rank: %s"):format(RankName(rank, prof.name)), {
            size = 13,
            colour = GOLD,
            right = ready and "ready" or ("at skill %d"):format(rank.skill),
            rightColour = ready and { 0.38, 0.85, 0.5 } or MUTED,
        })
        rowList:Line(how .. (npc and (Muted("\n" .. NpcText(npc))) or ""), {
            indent = 14,
            onClick = npc and function()
                LinkNpc(npc)
            end,
            tip = npc and function(tipText)
                tipText:SetText(npc[NPC_NAME], 1, 1, 1)
                tipText:AddLine("Click to link its map pin in chat.", unpack(MUTED))
            end,
        })
    end
    -- Skill-ups from what you know.
    local ups = {}
    for _, r in ipairs(payload.recipes) do
        if Learned(r.spell) and prof.skill < (r.grey or 0) and prof.skill < prof.max then
            ups[#ups + 1] = r
        end
    end
    table.sort(ups, function(a, b)
        return (a.grey or 0) < (b.grey or 0)
    end)
    if #ups > 0 then
        rowList:Gap(6)
        rowList:Line("Skill-ups", { size = 13, colour = GOLD })
        for _, r in ipairs(ups) do
            local c = Colour(r, prof.skill)
            rowList:Line(RecipeName(r), {
                icon = RecipeIcon(r),
                colour = c,
                right = ("%d / %d / %d"):format(
                    r.yellow or r.skill,
                    math.floor(((r.yellow or r.skill) + (r.grey or 0)) / 2),
                    r.grey or 0
                ),
                tip = function(tipText)
                    if r.item then
                        tipText:SetItemByID(r.item)
                    else
                        tipText:SetSpellByID(r.spell)
                    end
                    tipText:AddLine(
                        ("Yellow at %d, green at %d, grey at %d."):format(
                            r.yellow or r.skill,
                            math.floor(((r.yellow or r.skill) + (r.grey or 0)) / 2),
                            r.grey or 0
                        ),
                        unpack(ACCENT)
                    )
                end,
            })
        end
    end
    -- Recipe Finder.
    local nowTime, later = {}, {}
    for _, r in ipairs(payload.recipes) do
        if not Learned(r.spell) then
            if prof.skill >= Skill(r) then
                nowTime[#nowTime + 1] = r
            elseif Get("showLater") then
                later[#later + 1] = r
            end
        end
    end
    local function BySkill(a, b)
        if Skill(a) ~= Skill(b) then
            return Skill(a) < Skill(b)
        end
        return a.spell < b.spell
    end
    table.sort(nowTime, BySkill)
    table.sort(later, BySkill)
    local function FinderRow(r, ready)
        local tag = SOURCE_TAG[r.source] or "?"
        rowList:Line(
            RecipeName(r) .. "\n" .. Muted(tag .. (r.source == "trainer" and (" " .. Money(Cost(r))) or "")),
            {
                icon = RecipeIcon(r),
                colour = ready and { 0.38, 0.85, 0.5 }
                    or (prof.max < Skill(r) and { 1, 0.5, 0.25 } or { 1, 1, 1 }),
                right = ("%d"):format(Skill(r)),
                tip = function(tipText)
                    tipText:SetText(RecipeName(r), 1, 1, 1)
                    tipText:AddLine(
                        ("Requires %s %d (you: %d/%d)"):format(prof.name, Skill(r), prof.skill, prof.max),
                        unpack(GOLD)
                    )
                    if r.yellow and r.grey then
                        tipText:AddLine(
                            ("Yellow at %d, green at %d, grey at %d."):format(
                                r.yellow,
                                math.floor((r.yellow + r.grey) / 2),
                                r.grey
                            ),
                            unpack(ACCENT)
                        )
                    end
                    Describe(r, payload, tipText)
                    tipText:AddLine("Click to link the nearest one's map pin in chat.", unpack(MUTED))
                end,
                onClick = function()
                    local npc = NearestFor(r, payload)
                    if npc then
                        LinkNpc(npc)
                    end
                end,
            }
        )
    end
    if #nowTime > 0 then
        rowList:Gap(6)
        rowList:Line(("You can learn now  %s"):format(Muted(#nowTime)), { size = 13, colour = GOLD })
        for _, r in ipairs(nowTime) do
            FinderRow(r, true)
        end
    end
    if #later > 0 then
        rowList:Gap(6)
        rowList:Line(("Later  %s"):format(Muted(#later)), { size = 13, colour = GOLD })
        for _, r in ipairs(later) do
            FinderRow(r, false)
        end
    end
    if #nowTime == 0 and #later == 0 and #payload.recipes > 0 then
        rowList:Gap(6)
        rowList:Line("You know every recipe the data has for this profession.", { colour = MUTED })
    end
    contentFrame:SetHeight(rowList:Height() + 10)
end

local function BuildWindow()
    window = CreateFrame("Frame", "CludesUIProfessions", UIParent)
    window:SetSize(WIN_W, WIN_H)
    window:SetPoint("CENTER", 0, 30)
    CludesUI.Kit.Panel(window, 0.96)
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    window:SetFrameStrata("HIGH")
    window:SetClampedToScreen(true)
    local titleText = window:CreateFontString(nil, "OVERLAY")
    CludesUI.Kit.Font(titleText, 15, "essentials")
    titleText:SetPoint("TOPLEFT", 10, -8)
    titleText:SetText("Professions")
    CludesUI.Kit.AccentText(titleText)
    local close = CludesUI.Kit.Glyph(window, "x", function()
        window:Hide()
    end, nil, "essentials")
    close:SetPoint("TOPRIGHT", -5, -5)
    window.tabBar = CreateFrame("Frame", nil, window)
    window.tabBar:SetPoint("TOPLEFT", 10, -32)
    window.tabBar:SetSize(WIN_W - 20, 22)
    local scroll = (CludesUI.Kit.Scroll(window))
    scroll:SetPoint("TOPLEFT", 10, -60)
    scroll:SetPoint("BOTTOMRIGHT", -30, 10)
    contentFrame = CreateFrame("Frame", nil, scroll)
    contentFrame:SetSize(WIN_W - 44, 10)
    scroll:SetScrollChild(contentFrame)
    rowList = module.DiscoveryRows(contentFrame)
    window:Hide()
    tinsert(UISpecialFrames, "CludesUIProfessions")
end

local function Open(lineTex)
    if not window then
        BuildWindow()
    end
    if lineTex then
        currentLine = lineTex
    end
    window:Show()
    Draw()
end

-------------------------------------------------------------------------------
--  Events and apply
-------------------------------------------------------------------------------
local queued
local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, evt)
    if evt == "TRADE_SKILL_SHOW" or evt == "TRADE_SKILL_LIST_UPDATE" or evt == "NEW_RECIPE_LEARNED" then
        ReadTradeSkill()
    elseif evt == "TRAINER_SHOW" or evt == "TRAINER_UPDATE" then
        C_Timer.After(0.2, ScanTrainer)
    end
    if queued then
        return
    end
    queued = true
    C_Timer.After(1, function()
        queued = false
        if Get("rankAlert") and On() then
            CheckRanks(false)
        end
        Draw()
    end)
end)

local function Apply()
    ev:UnregisterAllEvents()
    if not On() then
        if window then
            window:Hide()
        end
        return
    end
    for _, e in ipairs({
        "SKILL_LINES_CHANGED",
        "PLAYER_LEVEL_UP",
        "TRADE_SKILL_SHOW",
        "TRADE_SKILL_LIST_UPDATE",
        "NEW_RECIPE_LEARNED",
        "TRAINER_SHOW",
        "TRAINER_UPDATE",
        "LEARNED_SPELL_IN_TAB",
    }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    if Get("rankAlert") then
        C_Timer.After(5, function()
            if On() then
                CheckRanks(false)
            end
        end)
    end
end

SLASH_CUIPROF1 = "/cprof"
SlashCmdList.CUIPROF = function(msg)
    if not On() then
        Print("turn on Professions in CludesUI Forever Tools first.")
        return
    end
    if (msg or ""):lower():find("rank") then
        return CheckRanks(true)
    end
    if window and window:IsShown() then
        window:Hide()
    else
        Open()
    end
end

CludesUI._Professions = {
    Get = Get,
    Cfg = F.Cfg,
    Apply = Apply,
    Open = function()
        Open()
    end,
    CheckRanks = function()
        CheckRanks(true)
    end,
}

F.Start(Apply)
