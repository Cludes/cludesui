if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if not (CludesUI and CludesUI.IS_FOREVER) then return end
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
local ACCENT, MUTED, GOLD = { 0.30, 0.79, 0.94 }, { 0.6, 0.65, 0.7 }, { 1, 0.82, 0 }
local ORANGE, YELLOW, GREEN, GREY = { 1, 0.5, 0.25 }, { 1, 1, 0 }, { 0.25, 0.75, 0.25 }, { 0.5, 0.5, 0.5 }
local function Muted(text) return "|cff9aa6b2" .. text .. "|r" end
local function Print(msg) CludesUI.Print("|cff4cc9f0Professions:|r " .. msg) end
local function Font() return (CludesUI.GetFontPath and CludesUI.GetFontPath()) or STANDARD_TEXT_FONT end

local RD
local function RecipeData()
    if not RD then RD = module.RecipeData(); module.RecipeData = nil end
    return RD
end

local function Faction() return UnitFactionGroup("player") == "Horde" and "H" or "A" end
local function ForMe(fac) return fac == "-" or (fac or ""):find(Faction(), 1, true) ~= nil end
local function Money(copper)
    if not copper or copper <= 0 then return "free" end
    return C_CurrencyInfo.GetCoinTextureString(copper, 12)
end
local function ZoneName(map)
    local info = map and map > 0 and C_Map.GetMapInfo(map)
    return info and info.name or "?"
end
local function AreaName(id) return id and C_Map.GetAreaInfo(id) or "?" end
local function ItemName(id, fallback)
    local name = id and C_Item.GetItemNameByID(id)
    if name then return name end
    if id then C_Item.RequestLoadItemDataByID(id) end
    return fallback or "its recipe"
end

local function CharStore(key)
    local cfg = F.Cfg()
    cfg[key] = cfg[key] or {}
    local char = (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
    cfg[key][char] = cfg[key][char] or {}
    return cfg[key][char]
end

-------------------------------------------------------------------------------
--  What you know: read from the profession window, kept per character
-------------------------------------------------------------------------------
local function Learned(spell)
    if CharStore("known")[spell] then return true end
    return C_SpellBook.IsSpellKnown(spell)
end

local function ReadTradeSkill()
    if not (C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs) then return end
    if C_TradeSkillUI.IsTradeSkillLinked and C_TradeSkillUI.IsTradeSkillLinked() then return end
    if C_TradeSkillUI.IsTradeSkillGuild and C_TradeSkillUI.IsTradeSkillGuild() then return end
    if C_TradeSkillUI.IsNPCCrafting and C_TradeSkillUI.IsNPCCrafting() then return end
    local known = CharStore("known")
    for _, id in ipairs(C_TradeSkillUI.GetAllRecipeIDs() or {}) do
        local info = C_TradeSkillUI.GetRecipeInfo(id)
        if info and info.learned then known[id] = true end
    end
end

-- A trainer's own skill and cost for a recipe beat the data's (Forever moved some).
local function ScanTrainer()
    if not (IsTradeskillTrainer and IsTradeskillTrainer()) then return end
    local byName, lineOf = {}, {}
    for line, data in pairs(RecipeData()) do
        lineOf[C_Spell.GetSpellName(data.skillSpell) or ""] = line
        for _, r in ipairs(data.recipes) do
            local name = C_Spell.GetSpellName(r.spell)
            if name then
                byName[name] = byName[name] or {}
                byName[name][#byName[name] + 1] = { r = r, line = line }
            end
        end
    end
    local overrides = F.Cfg()
    overrides.trainer = overrides.trainer or {}
    for i = 1, GetNumTrainerServices() do
        local name, _, category = GetTrainerServiceInfo(i)
        local skillName, rank = GetTrainerServiceSkillReq(i)
        if name and category ~= "header" and rank and byName[name] then
            local line = lineOf[skillName or ""]
            for _, m in ipairs(byName[name]) do
                if not line or m.line == line then overrides.trainer[m.r.spell] = { rank, GetTrainerServiceCost(i) } end
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
local function WorldPos(map, x, y)
    local ok, cont, pos = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(x, y))
    if ok and cont and pos then return cont, pos end
end

local function Nearest(npcs, n)
    local map = C_Map.GetBestMapForUnit("player")
    local here = map and C_Map.GetPlayerMapPosition(map, "player")
    local cont, pos
    if here and not (issecretvalue and issecretvalue(here)) then cont, pos = WorldPos(map, here:GetXY()) end
    local out = {}
    for _, npc in ipairs(npcs or {}) do
        if ForMe(npc[NPC_FACTION]) then
            local dist = math.huge
            if cont and npc[NPC_MAP] > 0 then
                local c, p = WorldPos(npc[NPC_MAP], npc[NPC_X] / 100, npc[NPC_Y] / 100)
                if c == cont then
                    local x1, y1 = pos:GetXY()
                    local x2, y2 = p:GetXY()
                    dist = (x1 - x2) ^ 2 + (y1 - y2) ^ 2
                end
            end
            out[#out + 1] = { npc = npc, dist = dist }
        end
    end
    table.sort(out, function(a, b)
        if a.dist ~= b.dist then return a.dist < b.dist end
        return a.npc[NPC_NAME] < b.npc[NPC_NAME]
    end)
    local picked = {}
    for i = 1, math.min(n or #out, #out) do picked[i] = out[i].npc end
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
    return ("%s - %s %.1f, %.1f%s"):format(npc[NPC_NAME], ZoneName(npc[NPC_MAP]), npc[NPC_X], npc[NPC_Y], extra or "")
end

local function Rows(indices, data)
    if not indices or type(indices[1]) ~= "number" then return indices or {} end
    local rows = {}
    for i, index in ipairs(indices) do rows[i] = data.trainers[index] end
    return rows
end

-------------------------------------------------------------------------------
--  Ranks, and gathering professions' trainers from the town map
-------------------------------------------------------------------------------
local gathered = {}
local function ProfData(line)
    local all = RecipeData()
    if all[line] then return all[line] end
    local title, mining = GATHERING[line], all[MINING]
    if not (title and mining and module.TownNPCList) then return end
    if not gathered[line] then
        local trainers = {}
        for map, npcs in pairs(module.TownNPCList()) do
            for _, n in ipairs(npcs) do
                if n[3] == "profession" and n[5] == title then
                    trainers[#trainers + 1] = { n[8] or 0, n[4], n[7] or "AH", map, n[1], n[2] }
                end
            end
        end
        local ranks = {}
        for i, rank in ipairs(mining.ranks) do ranks[i] = { cap = rank.cap, skill = rank.skill, cost = rank.cost } end
        gathered[line] = { trainers = trainers, ranks = ranks, recipes = {} }
    end
    return gathered[line]
end

local function NextRank(data, max)
    for _, rank in ipairs(data.ranks or {}) do
        if rank.cap > max then return rank end
    end
end

local function RankName(rank, prof)
    if rank.name then return rank.name end
    if RANK_TITLE[rank.cap] then return RANK_TITLE[rank.cap] .. " " .. prof end
    return ("the next rank of %s (cap %d)"):format(prof, rank.cap)
end

-- How to get a rank: a line of text and the nearest NPC for it.
local function RankWhere(data, rank)
    if rank.item then
        local npc = Nearest(rank.vendors, 1)[1]
        return npc, ("Buy and read %s (%s)"):format(ItemName(rank.item, "its book"), Money(npc and npc[NPC_PRICE]))
    elseif rank.quest then
        local id = rank.quest[Faction()]
        local title = id and C_QuestLog.GetTitleForQuestID(id) or rank.questName or "its quest"
        return Nearest(rank.teachers, 1)[1], ("Do the quest %s"):format(title)
    end
    return Nearest(rank.t and Rows(rank.t, data) or data.trainers, 1)[1], ("Train it for %s"):format(Money(rank.cost))
end

local function RankReady(line, skill, max, prof)
    local data = ProfData(line)
    local rank = data and (max or 0) > 0 and NextRank(data, max)
    if not rank or (skill or 0) < rank.skill then return end
    if UnitLevel("player") < (rank.level or RANK_LEVEL[rank.cap] or 0) then return end
    local npc, how = RankWhere(data, rank)
    return { rankName = RankName(rank, prof or ""), how = how, npc = npc, cap = rank.cap }
end

local function Professions()
    local list = {}
    for _, index in pairs({ GetProfessions() }) do
        if index then
            local name, icon, skill, max, _, _, line = GetProfessionInfo(index)
            if name and line then list[#list + 1] = { name = name, icon = icon, skill = skill or 0, max = max or 0, line = line } end
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

local function CheckRanks(force)
    local announced = CharStore("rankAlerted")
    local any = false
    for _, p in ipairs(Professions()) do
        local a = RankReady(p.line, p.skill, p.max, p.name)
        if a and (force or announced[p.line] ~= a.cap) then
            announced[p.line] = a.cap
            Print(("%s is ready for |cff4cc9f0%s|r. %s%s. /cprof for where."):format(p.name, a.rankName, a.how,
                a.npc and (" from " .. a.npc[NPC_NAME]) or ""))
            any = true
        end
    end
    if any then pcall(PlaySound, SOUNDKIT.IG_QUEST_LIST_OPEN)
    elseif force then Print("no profession is ready for its next rank yet.") end
end

-------------------------------------------------------------------------------
--  A recipe's source, as tooltip lines and its nearest NPC
-------------------------------------------------------------------------------
local SOURCE_TAG = { trainer = "Trainer", teacher = "Trainer", vendor = "Vendor", drop = "Drop", quest = "Quest", unknown = "?" }

local function Describe(r, data, tip)
    local function Line(text, c) tip:AddLine(text, (c or MUTED)[1], (c or MUTED)[2], (c or MUTED)[3], true) end
    local npc
    if r.source == "trainer" then
        Line(("Trainer: %s.%s"):format(Money(Cost(r)), r.quest and (" Also a reward from the quest " .. r.quest .. ".") or ""), { 1, 1, 1 })
        local list = Nearest(r.t and Rows(r.t, data) or data.trainers, 3)
        npc = list[1]
        for _, v in ipairs(list) do Line(NpcText(v)) end
    elseif r.source == "teacher" then
        Line("Taught for free by the Artisan doctor:", { 1, 1, 1 })
        for _, rank in ipairs(data.ranks) do
            if rank.teachers then
                local v = Nearest(rank.teachers, 1)[1]
                if v then npc = npc or v; Line(NpcText(v)) end
            end
        end
    elseif r.source == "vendor" then
        local sellers = Nearest(r.vendors)
        local unplaced = {}
        for _, s in ipairs(r.sellers or {}) do
            if ForMe(s[2]) then unplaced[#unplaced + 1] = s end
        end
        if #sellers == 0 and #unplaced == 0 then
            Line(ItemName(r.recipe, "Recipe") .. ": only the other faction sells it; try the Auction House.", { 1, 1, 1 })
        else
            local price = sellers[1] and sellers[1][NPC_PRICE] or unplaced[1] and unplaced[1][4]
            Line(("%s, sold for %s%s by:"):format(ItemName(r.recipe, "Recipe"), Money(price), r.rep and (" (needs " .. r.rep .. ")") or ""), { 1, 1, 1 })
            npc = sellers[1]
            for i = 1, math.min(3, #sellers) do Line(NpcText(sellers[i])) end
            for _, s in ipairs(unplaced) do Line(("%s - %s"):format(s[1], AreaName(s[3]))) end
        end
    elseif r.source == "drop" and r.bosses then
        Line(ItemName(r.recipe, "Recipe") .. " drops from:", { 1, 1, 1 })
        for _, b in ipairs(r.bosses) do Line(("%s - %s"):format(b[1], b[2] and AreaName(b[2]) or "?")) end
    elseif r.source == "drop" and r.world then
        Line(("%s: a world drop%s. Also try the Auction House."):format(ItemName(r.recipe, "Recipe"),
            r.world > 1 and (", from mobs around level " .. r.world) or ""), { 1, 1, 1 })
    elseif r.source == "drop" then
        local extra = {}
        if r.chests then extra[#extra + 1] = "chests and lockboxes" end
        if r.fished then extra[#extra + 1] = "fishing" end
        if r.pickpocket then extra[#extra + 1] = "pickpocketing" end
        local kinds = #extra > 0 and table.concat(extra, ", ") or nil
        local from = (r.mobs or 0) > 0 and (("a world drop from %d kinds of mob"):format(r.mobs) .. (kinds and (", " .. kinds) or ""))
            or (kinds and ("found through " .. kinds) or "found")
        Line(("%s: %s.%s"):format(ItemName(r.recipe, "Recipe"), from, #(r.drops or {}) > 0 and " Best odds:" or ""), { 1, 1, 1 })
        for _, d in ipairs(r.drops or {}) do
            local level = d[3] == d[4] and tostring(d[3]) or (d[3] .. "-" .. d[4])
            Line(("%s (%s) - %s, %.1f%%"):format(d[1], level, AreaName(d[2]), d[5]))
        end
    elseif r.source == "quest" then
        local mine = {}
        for _, q in ipairs(r.quests or {}) do if ForMe(q.side or "AH") then mine[#mine + 1] = q end end
        if #mine == 0 then
            Line(ItemName(r.recipe, "Recipe") .. ": a quest reward for the other faction; try the Auction House.", { 1, 1, 1 })
        else
            local names = {}
            for i, q in ipairs(mine) do names[i] = (q.id and C_QuestLog.GetTitleForQuestID(q.id)) or q.name or "?" end
            Line(ItemName(r.recipe, "Recipe") .. ": a reward from the quest " .. table.concat(names, " or ") .. ".", { 1, 1, 1 })
            for _, q in ipairs(mine) do
                if q.npc then npc = npc or q.npc; Line(NpcText(q.npc, "  (quest giver)")) end
            end
        end
    else
        Line(ItemName(r.recipe, "Recipe") .. ": where it comes from is not recorded yet; try the Auction House.", { 1, 1, 1 })
    end
    return npc
end

local function NearestFor(r, data)
    local sink = setmetatable({}, { __index = function() return function() end end })
    return Describe(r, data, sink)
end

-------------------------------------------------------------------------------
--  Window
-------------------------------------------------------------------------------
local WIN_W, WIN_H = 600, 520
local win, content, rows, tabButtons = nil, nil, nil, {}
local currentLine

local function Colour(r, skill)
    local yellow, grey = r.yellow or r.skill, r.grey or (r.skill + 40)
    local green = math.floor((yellow + grey) / 2)
    if skill < yellow then return ORANGE, "orange" end
    if skill < green then return YELLOW, "yellow" end
    if skill < grey then return GREEN, "green" end
    return GREY, "grey"
end

local function RecipeName(r)
    return C_Spell.GetSpellName(r.spell) or ItemName(r.item, ("recipe %d"):format(r.spell))
end

local function RecipeIcon(r)
    return (r.item and C_Item.GetItemIconByID(r.item)) or C_Spell.GetSpellTexture(r.spell) or 134400
end

local function Draw()
    if not (win and win:IsShown()) then return end
    rows:Reset()
    local profs = Professions()
    local x = 0
    for i, p in ipairs(profs) do
        local b = tabButtons[i]
        if not b then
            b = CreateFrame("Button", nil, win.tabBar, "UIPanelButtonTemplate")
            b:SetHeight(22)
            tabButtons[i] = b
        end
        b:SetText(p.name)
        b:SetWidth(math.max(80, b:GetFontString():GetStringWidth() + 24))
        b:ClearAllPoints()
        b:SetPoint("LEFT", win.tabBar, "LEFT", x, 0)
        b:SetScript("OnClick", function() currentLine = p.line; Draw() end)
        b:Show()
        x = x + b:GetWidth() + 4
    end
    for i = #profs + 1, #tabButtons do tabButtons[i]:Hide() end
    local prof
    for _, p in ipairs(profs) do if p.line == currentLine then prof = p end end
    prof = prof or profs[1]
    for i, p in ipairs(profs) do
        if p == prof then tabButtons[i]:LockHighlight() else tabButtons[i]:UnlockHighlight() end
    end
    if not prof then
        rows:Line("You have no professions yet.", { colour = MUTED })
        content:SetHeight(rows:Height() + 10)
        return
    end
    currentLine = prof.line
    local data = ProfData(prof.line)
    rows:Line(("%s  %s"):format(prof.name, Muted(("%d / %d"):format(prof.skill, prof.max))), { size = 16, colour = ACCENT, icon = prof.icon })
    if not data then
        rows:Line("No recipe data for this profession.", { colour = MUTED })
        content:SetHeight(rows:Height() + 10)
        return
    end
    -- Next rank.
    local rank = NextRank(data, prof.max)
    if rank then
        local npc, how = RankWhere(data, rank)
        local ready = prof.skill >= rank.skill and UnitLevel("player") >= (rank.level or RANK_LEVEL[rank.cap] or 0)
        rows:Gap(4)
        rows:Line(("Next rank: %s"):format(RankName(rank, prof.name)), { size = 13, colour = GOLD,
            right = ready and "ready" or ("at skill %d"):format(rank.skill), rightColour = ready and { 0.38, 0.85, 0.5 } or MUTED })
        rows:Line(how .. (npc and (Muted("\n" .. NpcText(npc))) or ""), { indent = 14,
            onClick = npc and function() LinkNpc(npc) end,
            tip = npc and function(tip) tip:SetText(npc[NPC_NAME], 1, 1, 1); tip:AddLine("Click to link its map pin in chat.", unpack(MUTED)) end })
    end
    -- Skill-ups from what you know.
    local ups = {}
    for _, r in ipairs(data.recipes) do
        if Learned(r.spell) and prof.skill < (r.grey or 0) and prof.skill < prof.max then ups[#ups + 1] = r end
    end
    table.sort(ups, function(a, b) return (a.grey or 0) < (b.grey or 0) end)
    if #ups > 0 then
        rows:Gap(6)
        rows:Line("Skill-ups", { size = 13, colour = GOLD })
        for _, r in ipairs(ups) do
            local c = Colour(r, prof.skill)
            rows:Line(RecipeName(r), { icon = RecipeIcon(r), colour = c,
                right = ("%d / %d / %d"):format(r.yellow or r.skill, math.floor(((r.yellow or r.skill) + (r.grey or 0)) / 2), r.grey or 0),
                tip = function(tip)
                    if r.item then tip:SetItemByID(r.item) else tip:SetSpellByID(r.spell) end
                    tip:AddLine(("Yellow at %d, green at %d, grey at %d."):format(r.yellow or r.skill,
                        math.floor(((r.yellow or r.skill) + (r.grey or 0)) / 2), r.grey or 0), unpack(ACCENT))
                end })
        end
    end
    -- Recipe Finder.
    local now, later = {}, {}
    for _, r in ipairs(data.recipes) do
        if not Learned(r.spell) then
            if prof.skill >= Skill(r) then now[#now + 1] = r elseif Get("showLater") then later[#later + 1] = r end
        end
    end
    local function BySkill(a, b) if Skill(a) ~= Skill(b) then return Skill(a) < Skill(b) end return a.spell < b.spell end
    table.sort(now, BySkill)
    table.sort(later, BySkill)
    local function FinderRow(r, ready)
        local tag = SOURCE_TAG[r.source] or "?"
        rows:Line(RecipeName(r) .. "\n" .. Muted(tag .. (r.source == "trainer" and (" " .. Money(Cost(r))) or "")), {
            icon = RecipeIcon(r), colour = ready and { 0.38, 0.85, 0.5 } or (prof.max < Skill(r) and { 1, 0.5, 0.25 } or { 1, 1, 1 }),
            right = ("%d"):format(Skill(r)),
            tip = function(tip)
                tip:SetText(RecipeName(r), 1, 1, 1)
                tip:AddLine(("Requires %s %d (you: %d/%d)"):format(prof.name, Skill(r), prof.skill, prof.max), unpack(GOLD))
                if r.yellow and r.grey then
                    tip:AddLine(("Yellow at %d, green at %d, grey at %d."):format(r.yellow, math.floor((r.yellow + r.grey) / 2), r.grey), unpack(ACCENT))
                end
                Describe(r, data, tip)
                tip:AddLine("Click to link the nearest one's map pin in chat.", unpack(MUTED))
            end,
            onClick = function()
                local npc = NearestFor(r, data)
                if npc then LinkNpc(npc) end
            end })
    end
    if #now > 0 then
        rows:Gap(6)
        rows:Line(("You can learn now  %s"):format(Muted(#now)), { size = 13, colour = GOLD })
        for _, r in ipairs(now) do FinderRow(r, true) end
    end
    if #later > 0 then
        rows:Gap(6)
        rows:Line(("Later  %s"):format(Muted(#later)), { size = 13, colour = GOLD })
        for _, r in ipairs(later) do FinderRow(r, false) end
    end
    if #now == 0 and #later == 0 and #data.recipes > 0 then
        rows:Gap(6)
        rows:Line("You know every recipe the data has for this profession.", { colour = MUTED })
    end
    content:SetHeight(rows:Height() + 10)
end

local function BuildWindow()
    win = CreateFrame("Frame", "CludesUIProfessions", UIParent, "BackdropTemplate")
    win:SetSize(WIN_W, WIN_H)
    win:SetPoint("CENTER", 0, 30)
    win:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    win:SetBackdropColor(0.06, 0.07, 0.09, 0.96)
    win:SetBackdropBorderColor(0.30, 0.79, 0.94, 0.8)
    win:SetMovable(true); win:EnableMouse(true); win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    win:SetFrameStrata("HIGH")
    win:SetClampedToScreen(true)
    local title = win:CreateFontString(nil, "OVERLAY")
    title:SetFont(Font(), 15, "OUTLINE")
    title:SetPoint("TOPLEFT", 10, -8)
    title:SetText("|cff4cc9f0Professions|r")
    local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    win.tabBar = CreateFrame("Frame", nil, win)
    win.tabBar:SetPoint("TOPLEFT", 10, -32)
    win.tabBar:SetSize(WIN_W - 20, 22)
    local scroll = CreateFrame("ScrollFrame", nil, win, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 10, -60)
    scroll:SetPoint("BOTTOMRIGHT", -30, 10)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(WIN_W - 44, 10)
    scroll:SetScrollChild(content)
    rows = module.DiscoveryRows(content)
    win:Hide()
    tinsert(UISpecialFrames, "CludesUIProfessions")
end

local function Open(line)
    if not win then BuildWindow() end
    if line then currentLine = line end
    win:Show()
    Draw()
end

-------------------------------------------------------------------------------
--  Events and apply
-------------------------------------------------------------------------------
local queued
local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event)
    if event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_LIST_UPDATE" or event == "NEW_RECIPE_LEARNED" then
        ReadTradeSkill()
    elseif event == "TRAINER_SHOW" or event == "TRAINER_UPDATE" then
        C_Timer.After(0.2, ScanTrainer)
    end
    if queued then return end
    queued = true
    C_Timer.After(1, function()
        queued = false
        if Get("rankAlert") and On() then CheckRanks(false) end
        Draw()
    end)
end)

local function Apply()
    ev:UnregisterAllEvents()
    if not On() then
        if win then win:Hide() end
        return
    end
    for _, e in ipairs({ "SKILL_LINES_CHANGED", "PLAYER_LEVEL_UP", "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE",
                         "NEW_RECIPE_LEARNED", "TRAINER_SHOW", "TRAINER_UPDATE", "LEARNED_SPELL_IN_TAB" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    if Get("rankAlert") then C_Timer.After(5, function() if On() then CheckRanks(false) end end) end
end

SLASH_CUIPROF1 = "/cprof"
SlashCmdList.CUIPROF = function(msg)
    if not On() then Print("turn on Professions in CludesUI Forever Tools first.") return end
    if (msg or ""):lower():find("rank") then return CheckRanks(true) end
    if win and win:IsShown() then win:Hide() else Open() end
end

CludesUI._Professions = { Get = Get, Cfg = F.Cfg, Apply = Apply, Open = function() Open() end, CheckRanks = function() CheckRanks(true) end }

F.Start(Apply)
