if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
if not (CUI and CUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_QuestList.lua  (WoW Forever only)
--  Discovery's Quest List and Rares tabs.
--    Quest List   every quest of every zone for your character: how many you
--                 have done per zone, each chain's step you are on, and why a
--                 quest is not open yet (an earlier quest, a profession,
--                 reputation, not offered any more). Search names or givers.
--    Rares        every rare of every zone and which this character killed
--                 (counted from when Discovery is on; Shift-click ticks one
--                 off by hand), with their drops.
--  Quest pins put a ! at each giver with a quest for you, rare pins a star
--  where each rare spawns, and Rare Alerts show a card when a rare is near
--  (left-click it to target the rare). What a giver really offers you is
--  learned from its window, so a quest the data has wrong corrects itself.
--  Data: CludesUIForeverEssentials_QuestData.lua.
-------------------------------------------------------------------------------
local _, module = ...

local DF = module.DiscoveryFeature
if not DF then return end

local F = module.Feature("questList", {
    hideDone = false,
    questPins = true,
    pinGrey = false,
    chainsOnly = false,
    pinSize = 20,
    rarePins = true,
    rarePinsKilled = false,
    rareHideKilled = false,
    rareAlert = true,
    rareAlertKilled = false,
    rareAlertSkull = false,
    rareSound = true,
    rareAlertTime = 20,
}, { point = "CENTER", relPoint = "CENTER", x = 0, y = 260 })
local Get = F.Get
local function On() return DF.Enabled() end

local BRAND = CUI.Kit.SyncAccent({}) -- refreshed on each draw
local DIM = { 0.6, 0.65, 0.7 }
local AMBER = { 1, 0.82, 0 }
local TEST = "|TInterface\\RaidFrame\\ReadyCheck-Ready:0|t"
local NONE = {}
local function Dim(labelValue) return "|cff9aa6b2" .. labelValue .. "|r" end
local function Secret(val) return issecretvalue ~= nil and issecretvalue(val) end
local function Typeface() return CUI.GetFontPath("essentials") end
local SAME_MAPS = { [2665] = 2521 }
local function SameChart(chart) return chart and (SAME_MAPS[chart] or chart) end

local QD, RD
local function TaskInfo()
    if not QD then
        QD = module.QuestData()
        module.QuestData = nil
    end
    return QD
end
local function BossInfo()
    if not RD then
        RD = module.RareData()
        module.RareData = nil
    end
    return RD
end

local function CharId() return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?") end
local function CharKeep(key)
    local conf = F.Cfg()
    conf[key] = conf[key] or {}
    local char = CharId()
    conf[key][char] = conf[key][char] or {}
    return conf[key][char]
end

local Link = module.DiscoveryLink
local AreaHeading = module.DiscoveryZoneName

-------------------------------------------------------------------------------
--  Quest rules
-------------------------------------------------------------------------------
local Q = {}
do
    local HEADING, LVL, REQ_LVL, FACTION, FOLKS, CALLINGS, CHART, X, Y, ORIGIN, THING =
        1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
    local ALLIANCE, HORDE = 1, 2
    local FOLK_FLAGS =
        { [1] = 0, [2] = 1, [3] = 2, [4] = 3, [5] = 4, [6] = 5, [7] = 6, [8] = 7, [95] = 32, [96] = 33 }
    local TOP_BELOW, CLASSIC_GREEN_RANGE, GAPS_KEPT = 10, 8, 2
    local D
    local mine, areaOf, chains, linkOf, closers, recipes, requires, teaches
    local ranks, untils, topLevels, leastReps, topReps, factions
    local opened, reopened = {}, {}
    local done, logged, crafts, known, standings = {}, {}, {}, {}, {}
    local byChart
    local areaChains, areaSingles, spottedLink = {}, {}, {}
    local found, foundIn = {}, {}
    local named = {}
    local givers, spare, sourceAt = {}, {}, {}
    local blocking = {}

    local function HasBit(mask, bit) return math.floor(mask / 2 ^ bit) % 2 == 1 end

    local function ForMe(task, side, folkBit, callingBit)
        if task[FACTION] == ALLIANCE and side ~= ALLIANCE then return false end
        if task[FACTION] == HORDE and side ~= HORDE then return false end
        if task[FOLKS] > 0 and folkBit and not HasBit(task[FOLKS], folkBit) then return false end
        if task[CALLINGS] > 0 and callingBit and not HasBit(task[CALLINGS], callingBit) then return false end
        return true
    end

    local function MineStages(stages)
        local own = {}
        for _, step in ipairs(stages) do
            local ids = {}
            for _, ident in ipairs(step) do
                if mine[ident] then ids[#ids + 1] = ident end
            end
            ids.any = step.any
            if #ids > 0 then own[#own + 1] = ids end
        end
        return own
    end

    local function PutChain(own)
        local first = D.Quests[own[1][1]]
        local chain = { steps = own, name = first[HEADING], level = first[LVL], id = #chains + 1 }
        chains[#chains + 1] = chain
        for _, ids in ipairs(own) do
            for _, ident in ipairs(ids) do
                linkOf[ident] = chain
            end
        end
    end

    local function PutFinisher(ident, other)
        if not mine[ident] then return end
        local items = closers[ident]
        if not items then
            items = {}
            closers[ident] = items
        end
        items[#items + 1] = other
    end

    local function CatalogClosers()
        closers, recipes, factions = {}, {}, {}
        requires, teaches, ranks, untils =
            D.Profession or NONE, D.Recipe or NONE, D.SkillRank or NONE, D.Until or NONE
        topLevels, leastReps, topReps = D.MaxLevel or NONE, D.MinReputation or NONE, D.MaxReputation or NONE
        local groupOf = {}
        for _, assign in ipairs(D.Exclusive or NONE) do
            for _, ident in ipairs(assign) do
                groupOf[ident] = assign
                for _, other in ipairs(assign) do
                    if other ~= ident then PutFinisher(ident, other) end
                end
            end
        end
        for ident, aim in pairs(D.Breadcrumb or NONE) do
            PutFinisher(ident, aim)
            for _, other in ipairs(groupOf[aim] or NONE) do
                if other ~= aim then PutFinisher(ident, other) end
            end
        end
        for ident, elements in pairs(D.Requires) do
            for _, element in ipairs(elements) do
                if type(element) == "table" then
                    for _, before in ipairs(element) do
                        PutFinisher(before, ident)
                    end
                else
                    PutFinisher(element, ident)
                end
            end
        end
        for ident, others in pairs(D.ClosedBy or NONE) do
            for _, other in ipairs(others) do
                PutFinisher(ident, other)
            end
        end
        for _, spell in pairs(teaches) do
            recipes[spell] = true
        end
        for _, rep in pairs(leastReps) do
            factions[rep[1]] = true
        end
        for _, rep in pairs(topReps) do
            factions[rep[1]] = true
        end
    end

    local function Prepare()
        if mine then return end
        D = TaskInfo()
        mine, areaOf, chains, linkOf = {}, {}, {}, {}
        local side = UnitFactionGroup("player") == "Horde" and HORDE or ALLIANCE
        local folkBit = FOLK_FLAGS[select(3, UnitRace("player"))]
        local callingID = select(3, UnitClass("player"))
        local callingBit = callingID and callingID - 1
        for ident, task in pairs(D.Quests) do
            if ForMe(task, side, folkBit, callingBit) then mine[ident] = true end
        end
        for ident in pairs(CharKeep("mine")) do
            if D.Quests[ident] then mine[ident] = true end
        end
        for _, area in ipairs(D.Zones) do
            for _, ident in ipairs(area.quests) do
                areaOf[ident] = area
            end
        end
        for _, stages in ipairs(D.Chains) do
            local own = MineStages(stages)
            if #own > 1 then PutChain(own) end
        end
        CatalogClosers()
    end
    Q.Prepare = Prepare

    local function PutCrafts(...)
        for catalog = 1, select("#", ...) do
            local catalog = select(catalog, ...)
            if catalog then
                local tier, _, _, _, row = select(3, GetProfessionInfo(catalog))
                if row then crafts[row] = tier end
            end
        end
    end

    local function ReadTrained()
        wipe(crafts)
        PutCrafts(GetProfessions())
        wipe(known)
        for spell in pairs(recipes) do
            known[spell] = C_SpellBook.IsSpellKnown(spell)
        end
        wipe(standings)
        for faction in pairs(factions) do
            local payload = C_Reputation.GetFactionDataByID(faction)
            standings[faction] = payload and payload.currentStanding
        end
        wipe(logged)
        for catalog = 1, C_QuestLog.GetNumQuestLogEntries() do
            local ident = C_QuestLog.GetQuestIDForLogIndex(catalog)
            if ident then logged[ident] = true end
        end
    end

    local function Past(ident)
        local lvl, rep = topLevels[ident], topReps[ident]
        if lvl and UnitLevel("player") > lvl then return true end
        local standing = rep and standings[rep[1]]
        return standing ~= nil and standing >= rep[2]
    end

    local function LackingOfStanding(ident)
        local rep = leastReps[ident]
        local standing = rep and standings[rep[1]]
        return standing ~= nil and standing < rep[2]
    end

    local function Shut(ident)
        local status
        local craft = requires[ident]
        if craft and (crafts[craft] or 0) < (ranks[ident] or 1) then
            status = "skill"
        elseif known[teaches[ident]] or done[untils[ident]] or Past(ident) then
            status = "closed"
        else
            local items = closers[ident] or NONE
            for catalog = 1, #items do
                if done[items[catalog]] or logged[items[catalog]] then
                    status = "closed"
                    break
                end
            end
        end
        if not status and LackingOfStanding(ident) then status = "rep" end
        if status and not reopened[ident] then return status end
    end

    local function AreaHandBacks(ident)
        local area = areaOf and areaOf[ident]
        return area and CharKeep("turnIns")[area.map] or 0
    end

    local function TaskLvl(ident) return D.Quests[ident][LVL] end

    local function RankId(entry)
        if type(entry) == "table" then return entry.level, entry.name end
        local task = D.Quests[entry]
        return task[LVL], task[HEADING]
    end

    local function ByLvl(a, b)
        local la, na = RankId(a)
        local lb, nb = RankId(b)
        if la ~= lb then return la < lb end
        return na < nb
    end

    local function FoundId(ident)
        local chain = linkOf[ident]
        if not chain then return TaskLvl(ident), 0, 0 end
        return chain.level, chain.id, (Q.ChainStep(ident))
    end

    local function FoundTier(a, b)
        local la, ca, sa = FoundId(a)
        local lb, callback, scrollBar = FoundId(b)
        if la ~= lb then return la < lb end
        if ca ~= callback then return ca < callback end
        if sa ~= scrollBar then return sa < scrollBar end
        return D.Quests[a][HEADING] < D.Quests[b][HEADING]
    end

    local function Fits(task, labelValue)
        if task[HEADING]:lower():find(labelValue, 1, true) then return true end
        return task[ORIGIN] ~= nil and task[ORIGIN]:lower():find(labelValue, 1, true) ~= nil
    end

    local function Catalog()
        if byChart then return end
        byChart = {}
        for ident, task in pairs(D.Quests) do
            local chart = task[CHART]
            if chart and mine[ident] then
                byChart[chart] = byChart[chart] or {}
                table.insert(byChart[chart], ident)
            end
        end
    end

    local function ReuseSources()
        for catalog = #givers, 1, -1 do
            local entry = givers[catalog]
            wipe(entry.quests)
            spare[#spare + 1] = entry
            givers[catalog] = nil
        end
        wipe(sourceAt)
    end

    local function OriginThing(task)
        local key = task[X] .. ":" .. task[Y]
        local entry = sourceAt[key]
        if entry then return entry end
        entry = table.remove(spare) or { quests = {} }
        entry.x, entry.y, entry.grey, entry.repeatable, entry.dungeon = task[X], task[Y], true, true, false
        sourceAt[key] = entry
        givers[#givers + 1] = entry
        return entry
    end

    local function PutToRosters(ident)
        local chain = linkOf[ident]
        if not chain then
            areaSingles[#areaSingles + 1] = ident
            return
        end
        if spottedLink[chain] then return end
        spottedLink[chain] = true
        areaChains[#areaChains + 1] = chain
    end

    local function Desired(ident, chainsOnly)
        return Q.Available(ident) and (linkOf[ident] ~= nil or not chainsOnly or Q.Dungeon(ident))
    end

    local function PutToOrigin(ident, trivial)
        local entry = OriginThing(D.Quests[ident])
        table.insert(entry.quests, ident)
        if not trivial then entry.grey = false end
        if not Q.Repeatable(ident) then entry.repeatable = false end
        if Q.Dungeon(ident) and not Q.Battleground(ident) then entry.dungeon = true end
    end

    function Q.Refresh()
        Prepare()
        opened, reopened = CharKeep("opened"), CharKeep("reopened")
        ReadTrained()
        wipe(done)
        local all = C_QuestLog.GetAllCompletedQuestIDs and C_QuestLog.GetAllCompletedQuestIDs()
        if all then
            for catalog = 1, #all do
                done[all[catalog]] = true
            end
            return
        end
        for ident in pairs(mine) do
            if C_QuestLog.IsQuestFlaggedCompleted(ident) then done[ident] = true end
        end
    end

    function Q.Done(ident) return done[ident] == true end
    function Q.InLog(ident) return C_QuestLog.GetLogIndexForQuestID(ident) ~= nil end
    function Q.Mine(ident) return mine[ident] == true end
    function Q.Name(ident) return D.Quests[ident][HEADING] end
    function Q.Level(ident) return TaskLvl(ident) end

    function Q.SetMine(ids)
        Prepare()
        local storage
        for ident in pairs(ids) do
            if not mine[ident] and D.Quests[ident] then
                storage = storage or CharKeep("mine")
                storage[ident] = true
            end
        end
        if not storage then return end
        mine, byChart = nil, nil
        Prepare()
    end

    function Q.RequiredLevel(ident)
        local task = D.Quests[ident]
        return math.max(task[REQ_LVL], task[LVL] - TOP_BELOW)
    end

    function Q.Zone(ident) return areaOf[ident] end
    function Q.Chain(ident) return linkOf[ident] end
    function Q.Zones()
        Prepare()
        return D.Zones
    end
    function Q.Giver(ident) return D.Quests[ident][ORIGIN] end
    function Q.Item(ident) return D.Quests[ident][THING] end
    function Q.Repeatable(ident) return D.Repeatable ~= nil and D.Repeatable[ident] == true end
    function Q.Dungeon(ident) return D.Dungeon ~= nil and D.Dungeon[ident] == true end
    function Q.Battleground(ident) return D.Battleground ~= nil and D.Battleground[ident] == true end
    function Q.Elsewhere(ident) return D.Elsewhere ~= nil and D.Elsewhere[ident] == true end

    function Q.Spot(ident)
        local task = D.Quests[ident]
        if task[CHART] then return task[CHART], task[X], task[Y] end
    end

    function Q.StepDone(step)
        for _, ident in ipairs(step) do
            if done[ident] and step.any then return true end
            if not done[ident] and not step.any then return false end
        end
        return not step.any
    end

    function Q.ChainAt(chain)
        local stages = chain.steps
        for catalog = #stages, 1, -1 do
            if Q.StepDone(stages[catalog]) then return catalog + 1, #stages end
        end
        return 1, #stages
    end

    function Q.NotOffered(ident)
        local entry = CharKeep("notOffered")[ident]
        if not entry then return false end
        if (entry[3] or 1) >= GAPS_KEPT then return true end
        return entry[1] == UnitLevel("player") and entry[2] == AreaHandBacks(ident)
    end

    function Q.SetOffered(ident, offered)
        local storage = CharKeep("notOffered")
        local entry, lvl = storage[ident], UnitLevel("player")
        if offered then
            storage[ident] = nil
        elseif not entry then
            storage[ident] = { lvl, AreaHandBacks(ident), 1 }
        else
            if entry[1] ~= lvl then entry[3] = (entry[3] or 1) + 1 end
            entry[1], entry[2] = lvl, AreaHandBacks(ident)
        end
    end

    function Q.CountTurnIn(ident)
        Prepare()
        local area = areaOf[ident]
        if not area then return end
        local handBacks = CharKeep("turnIns")
        handBacks[area.map] = (handBacks[area.map] or 0) + 1
    end

    function Q.State(ident)
        local status = Q.Expected(ident)
        if status == "open" and Q.NotOffered(ident) then return "held" end
        return status
    end

    local function Tallies(ident) return mine[ident] or not D.Quests[ident] end

    local function Reached(element)
        if type(element) == "number" then return done[element] or not Tallies(element) end
        local counted = false
        for _, ident in ipairs(element) do
            if done[ident] then return true end
            if Tallies(ident) then counted = true end
        end
        return not counted
    end

    function Q.Opened(ident)
        for _, element in ipairs(D.Requires[ident] or NONE) do
            if not Reached(element) then return opened[ident] == true end
        end
        return true
    end

    function Q.SetOpened(ident) CharKeep("opened")[ident] = true end
    function Q.SetReopened(ident) CharKeep("reopened")[ident] = true end

    function Q.Blocking(ident)
        wipe(blocking)
        for _, element in ipairs(D.Requires[ident] or NONE) do
            if not Reached(element) then
                local first = element
                if type(element) == "table" then
                    for _, other in ipairs(element) do
                        if Tallies(other) then
                            first = other
                            break
                        end
                    end
                end
                blocking[#blocking + 1] = first
            end
        end
        return blocking
    end

    function Q.Title(ident)
        local task = D.Quests[ident]
        return task and task[HEADING] or C_QuestLog.GetTitleForQuestID(ident)
    end

    function Q.Expected(ident)
        if done[ident] then return "done" end
        if Q.InLog(ident) then return "log" end
        local shut = Shut(ident)
        if shut then return shut end
        if not Q.Opened(ident) then return "later" end
        if UnitLevel("player") < Q.RequiredLevel(ident) then return "low" end
        return "open"
    end

    function Q.ZoneProgress(area)
        local num, sum, low, upper = 0, 0, nil, nil
        for _, ident in ipairs(area.quests) do
            if
                mine[ident]
                and not Q.Repeatable(ident)
                and not Q.Dungeon(ident)
                and not Q.Elsewhere(ident)
                and (done[ident] or not Shut(ident) or Q.InLog(ident))
            then
                sum = sum + 1
                if done[ident] then num = num + 1 end
                local lvl = TaskLvl(ident)
                if lvl > 0 then
                    low = math.min(low or lvl, lvl)
                    upper = math.max(upper or lvl, lvl)
                end
            end
        end
        return num, sum, low, upper
    end

    function Q.Progress()
        local num, sum = 0, 0
        for _, area in ipairs(D.Zones) do
            local zn, zt = Q.ZoneProgress(area)
            num, sum = num + zn, sum + zt
        end
        return num, sum
    end

    function Q.ZoneLists(area)
        wipe(areaChains)
        wipe(areaSingles)
        wipe(spottedLink)
        for _, ident in ipairs(area.quests) do
            if mine[ident] then PutToRosters(ident) end
        end
        table.sort(areaChains, ByLvl)
        table.sort(areaSingles, ByLvl)
        return areaChains, areaSingles
    end

    function Q.ChainStep(ident)
        local chain = linkOf[ident]
        if not chain then return end
        for catalog, step in ipairs(chain.steps) do
            for _, other in ipairs(step) do
                if other == ident then return catalog, #chain.steps end
            end
        end
    end

    function Q.Search(labelValue, limit)
        Prepare()
        wipe(found)
        local num = 0
        for _, area in ipairs(D.Zones) do
            local entry = foundIn[area] or { zone = area, ids = {} }
            foundIn[area] = entry
            local ids = wipe(entry.ids)
            for _, ident in ipairs(area.quests) do
                if mine[ident] and Fits(D.Quests[ident], labelValue) then
                    num = num + 1
                    if num <= limit then ids[#ids + 1] = ident end
                end
            end
            if #ids > 0 then
                table.sort(ids, FoundTier)
                found[#found + 1] = entry
            end
        end
        return found, num
    end

    function Q.CurrentZone()
        Prepare()
        local chart = SameChart(C_Map.GetBestMapForUnit("player"))
        while chart do
            for _, area in ipairs(D.Zones) do
                if area.map == chart then return area end
            end
            local details = C_Map.GetMapInfo(chart)
            chart = details and details.parentMapID ~= 0 and details.parentMapID or nil
        end
    end

    function Q.Link(ident)
        local chart, posX, posY = Q.Spot(ident)
        if chart then
            Link(Q.Name(ident), chart, posX, posY, Q.Giver(ident) and ("(" .. Q.Giver(ident) .. ")"))
        end
    end

    function Q.Trivial(ident)
        local lvl = TaskLvl(ident)
        if lvl <= 0 then return false end
        if QuestDifficultyColors and QuestDifficultyColors.trivial then
            return GetQuestDifficultyColor(lvl) == QuestDifficultyColors.trivial
        end
        local green = GetQuestGreenRange and GetQuestGreenRange() or CLASSIC_GREEN_RANGE
        return lvl < UnitLevel("player") - green
    end

    function Q.Available(ident) return mine[ident] == true and Q.State(ident) == "open" end

    function Q.GiverQuests(title, chartID)
        if Secret(title) then return NONE end
        Prepare()
        Catalog()
        wipe(named)
        for _, ident in ipairs(byChart[chartID] or NONE) do
            if D.Quests[ident][ORIGIN] == title then named[#named + 1] = ident end
        end
        return named
    end

    function Q.Givers(chartID, grey, chainsOnly)
        Prepare()
        Catalog()
        ReuseSources()
        for _, ident in ipairs(byChart[SameChart(chartID)] or NONE) do
            if Desired(ident, chainsOnly) then
                local trivial = Q.Trivial(ident)
                if grey or not trivial then PutToOrigin(ident, trivial) end
            end
        end
        return givers
    end
end

-------------------------------------------------------------------------------
--  Givers: learn from the quest givers you speak to what they really offer
-------------------------------------------------------------------------------
local sourceEvents = CreateFrame("Frame")
do
    local SHUT = { closed = true, skill = true, rep = true }
    local offered, titles = {}, {}
    local listed

    local function PlainId(unitToken)
        local unitId = UnitGUID(unitToken)
        if not Secret(unitId) then return unitId end
    end

    local function Collect(unitToken)
        if not UnitExists(unitToken) or UnitIsPlayer(unitToken) then return end
        local area = Q.CurrentZone()
        if not area then return end
        Q.Refresh()
        Q.SetMine(offered)
        local trivial = C_Minimap
            and C_Minimap.IsFilteredOut
            and Enum.MinimapTrackingFilter
            and not C_Minimap.IsFilteredOut(Enum.MinimapTrackingFilter.TrivialQuests)
        for _, ident in ipairs(Q.GiverQuests(UnitName(unitToken), area.map)) do
            if offered[ident] and SHUT[Q.Expected(ident)] then Q.SetReopened(ident) end
            if offered[ident] and Q.Expected(ident) == "later" then Q.SetOpened(ident) end
            if Q.Expected(ident) == "open" and (trivial or not Q.Trivial(ident)) then
                Q.SetOffered(ident, offered[ident] == true)
            end
        end
    end

    sourceEvents:SetScript("OnEvent", function(_, evt, taskID)
        if evt == "GOSSIP_SHOW" then
            wipe(offered)
            for _, task in ipairs(C_GossipInfo.GetAvailableQuests() or NONE) do
                if task.questID then offered[task.questID] = true end
            end
            listed = PlainId("npc")
            Collect("npc")
        elseif evt == "QUEST_GREETING" then
            wipe(offered)
            wipe(titles)
            for catalog = 1, GetNumAvailableQuests() do
                local ident = GetAvailableQuestInfo and select(5, GetAvailableQuestInfo(catalog))
                if ident then
                    offered[ident] = true
                else
                    titles[GetAvailableTitle(catalog) or ""] = true
                end
            end
            if next(titles) then
                local area = Q.CurrentZone()
                if area then
                    for _, ident in ipairs(Q.GiverQuests(UnitName("npc"), area.map)) do
                        if titles[Q.Name(ident)] then offered[ident] = true end
                    end
                end
            end
            listed = PlainId("npc")
            Collect("npc")
        elseif evt == "QUEST_DETAIL" then
            local unitId = PlainId("questnpc")
            if not unitId or unitId == listed then return end
            wipe(offered)
            offered[GetQuestID()] = true
            Collect("questnpc")
        elseif evt == "QUEST_TURNED_IN" then
            Q.CountTurnIn(taskID)
        end
    end)
end

-------------------------------------------------------------------------------
--  Rare rules and kills
-------------------------------------------------------------------------------
local R = {}
local killEvents = CreateFrame("Frame")
do
    local HEADING, LOWER, UPPER, BOSS, STANCE_A, STANCE_H, CHART, PLACES, PATH = 1, 2, 3, 4, 5, 6, 7, 8, 9
    local SPOILS_ID, SPOILS_GRADE, SPOILS_ODDS, SPOILS_HEADING, SPOILS_FRESH = 1, 2, 3, 4, 5
    local D
    local mine, byChart
    local listeners = {}
    local items, found, foundIn, lowered = {}, {}, {}, {}

    local function Prepare()
        if mine then return end
        D = BossInfo()
        mine = {}
        local stance = UnitFactionGroup("player") == "Horde" and STANCE_H or STANCE_A
        for npc, rare in pairs(D.Rares) do
            if rare[stance] ~= 1 then mine[npc] = true end
        end
    end
    R.Prepare = Prepare

    local function Slain() return CharKeep("rareKills") end
    local function Drops() return CharKeep("rareDrops") end
    local function Altered(npc)
        for _, func in ipairs(listeners) do
            func(npc)
        end
    end

    local function AreaFor(chart)
        for _, area in ipairs(D.Zones) do
            if area.map == chart then return area end
        end
    end

    local function Closest(points, px, py, bx, by, topD)
        for catalog = 1, #points, 2 do
            local dx, dy = points[catalog] / 100 - px, points[catalog + 1] / 100 - py
            local skinInfo = dx * dx + dy * dy
            if not topD or skinInfo < topD then
                bx, by, topD = points[catalog], points[catalog + 1], skinInfo
            end
        end
        return bx, by, topD
    end

    function R.NpcOf(unitId)
        if type(unitId) ~= "string" or Secret(unitId) then return end
        local kind, _, _, _, _, ident = strsplit("-", unitId)
        if kind == "Creature" or kind == "Vehicle" then return tonumber(ident) end
    end

    function R.Known(npc)
        Prepare()
        return D.Rares[npc] ~= nil
    end
    function R.Name(npc) return D.Rares[npc][HEADING] end
    function R.Elite(npc) return D.Rares[npc][BOSS] == 1 end
    function R.Map(npc) return D.Rares[npc][CHART] end
    function R.Levels(npc)
        local rare = D.Rares[npc]
        return rare[LOWER], rare[UPPER]
    end
    function R.LevelText(npc)
        local low, upper = R.Levels(npc)
        if low <= 0 then return "??" end
        if low == upper then return tostring(low) end
        return ("%d-%d"):format(low, upper)
    end
    function R.Mine(npc)
        Prepare()
        return mine[npc] == true
    end
    function R.OnChange(func) listeners[#listeners + 1] = func end
    function R.Killed(npc) return Slain()[npc] ~= nil end
    function R.Record(npc) return Slain()[npc] end

    function R.AddKill(npc, unitId)
        local all = Slain()
        local record = all[npc] or { n = 0 }
        record.n = record.n + 1
        record.at = time()
        record.guid = unitId
        all[npc] = record
        Altered(npc)
    end

    function R.SetKilled(npc, killed)
        local all = Slain()
        all[npc] = killed and (all[npc] or { n = 0, at = time() }) or nil
        Altered(npc)
    end

    function R.Dropped(npc, thingId)
        local thingRoster = Drops()[npc]
        return thingRoster ~= nil and thingRoster[thingId] ~= nil
    end

    function R.AddDrop(npc, thingId)
        local all = Drops()
        all[npc] = all[npc] or {}
        if all[npc][thingId] then return end
        all[npc][thingId] = time()
        Altered(npc)
    end

    function R.ZoneProgress(area)
        Prepare()
        local all = Slain()
        local num, sum, low, upper = 0, 0, nil, nil
        for _, npc in ipairs(area.rares) do
            if mine[npc] then
                sum = sum + 1
                if all[npc] then num = num + 1 end
                local lo, hi = R.Levels(npc)
                if lo > 0 then
                    low = math.min(low or lo, lo)
                    upper = math.max(upper or hi, hi)
                end
            end
        end
        return num, sum, low, upper
    end

    function R.Progress()
        Prepare()
        local num, sum = 0, 0
        for _, area in ipairs(D.Zones) do
            local zn, zt = R.ZoneProgress(area)
            num, sum = num + zn, sum + zt
        end
        return num, sum
    end

    function R.Zones()
        Prepare()
        return D.Zones
    end

    function R.ZoneList(area)
        Prepare()
        wipe(items)
        for _, npc in ipairs(area.rares) do
            if mine[npc] then items[#items + 1] = npc end
        end
        return items
    end

    function R.CurrentZone()
        Prepare()
        local chart = SameChart(C_Map.GetBestMapForUnit("player"))
        while chart do
            local area = AreaFor(chart)
            if area then return area end
            local details = C_Map.GetMapInfo(chart)
            chart = details and details.parentMapID ~= 0 and details.parentMapID or nil
        end
    end

    function R.Search(labelValue, limit)
        Prepare()
        wipe(found)
        local num = 0
        for _, area in ipairs(D.Zones) do
            local entry = foundIn[area] or { zone = area, ids = {} }
            foundIn[area] = entry
            local ids = wipe(entry.ids)
            for _, npc in ipairs(area.rares) do
                local title = lowered[npc]
                if not title then
                    title = D.Rares[npc][HEADING]:lower()
                    lowered[npc] = title
                end
                if mine[npc] and title:find(labelValue, 1, true) then
                    num = num + 1
                    if num <= limit then ids[#ids + 1] = npc end
                end
            end
            if #ids > 0 then found[#found + 1] = entry end
        end
        return found, num
    end

    function R.Spot(npc)
        local rare = D.Rares[npc]
        local places = rare[PLACES]
        if #places == 0 then return end
        local place = SameChart(C_Map.GetBestMapForUnit("player")) == rare[CHART]
            and C_Map.GetPlayerMapPosition(rare[CHART], "player")
        if not place or Secret(place) then return rare[CHART], places[1], places[2] end
        local px, py = place:GetXY()
        local bx, by, topD = Closest(places, px, py, places[1], places[2], nil)
        if rare[PATH] then
            bx, by = Closest(rare[PATH], px, py, bx, by, topD)
        end
        return rare[CHART], bx, by
    end

    function R.Spots(npc) return D.Rares[npc][PLACES] end
    function R.Loot(npc) return D.Loot and D.Loot[npc] end

    function R.AddLoot(hintLabel, npc)
        local spoils = R.Loot(npc)
        if not spoils then return end
        hintLabel:AddLine(" ")
        hintLabel:AddLine("Drops", unpack(AMBER))
        for _, entry in ipairs(spoils) do
            local tint = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[entry[SPOILS_GRADE]]
                or { r = 1, g = 1, b = 1 }
            local glyphTex = C_Item.GetItemIconByID(entry[SPOILS_ID])
            local title = (glyphTex and ("|T%s:14:14|t "):format(glyphTex) or "")
                .. entry[SPOILS_HEADING]
                .. (entry[SPOILS_FRESH] == 1 and " " .. CUI.Kit.AccentHex() .. "(new in Forever)|r" or "")
                .. (R.Dropped(npc, entry[SPOILS_ID]) and " |cff60d080(you got it)|r" or "")
            local odds = entry[SPOILS_ODDS]
            hintLabel:AddDoubleLine(
                title,
                odds >= 1 and ("%d%%"):format(math.floor(odds + 0.5)) or ("%.1f%%"):format(odds),
                tint.r,
                tint.g,
                tint.b,
                unpack(DIM)
            )
        end
        if spoils.more then hintLabel:AddLine(("And %d more"):format(spoils.more), unpack(DIM)) end
    end

    function R.OnMap(chartID)
        Prepare()
        if not byChart then
            byChart = {}
            for npc, rare in pairs(D.Rares) do
                if mine[npc] and #rare[PLACES] > 0 then
                    byChart[rare[CHART]] = byChart[rare[CHART]] or {}
                    table.insert(byChart[rare[CHART]], npc)
                end
            end
        end
        return byChart[SameChart(chartID)] or NONE
    end

    function R.Link(npc)
        local chart, posX, posY = R.Spot(npc)
        if chart then Link(R.Name(npc), chart, posX, posY) end
    end

    -- Kills: a rare you targeted dying while yours, or a corpse you loot.
    local counted = {}
    local tracking

    local function Tally(unitId)
        local npc = R.NpcOf(unitId)
        if not npc or not R.Known(npc) or counted[unitId] then return end
        counted[unitId] = true
        local record = R.Record(npc)
        if record and record.guid == unitId then return end
        R.AddKill(npc, unitId)
    end

    local function HaltTracking()
        tracking = nil
        killEvents:UnregisterEvent("UNIT_HEALTH")
    end

    killEvents:SetScript("OnEvent", function(_, evt)
        if evt == "PLAYER_TARGET_CHANGED" then
            HaltTracking()
            local unitId = UnitGUID("target")
            local npc = R.NpcOf(unitId)
            if not npc or not R.Known(npc) or counted[unitId] then return end
            local dead, denied = UnitIsDead("target"), UnitIsTapDenied("target")
            if Secret(dead) or Secret(denied) then return end
            if dead then
                if not denied then Tally(unitId) end
                return
            end
            tracking = unitId
            killEvents:RegisterUnitEvent("UNIT_HEALTH", "target")
        elseif evt == "UNIT_HEALTH" then
            local unitId = UnitGUID("target")
            if Secret(unitId) or unitId ~= tracking then return end
            local dead, denied = UnitIsDead("target"), UnitIsTapDenied("target")
            if Secret(dead) or Secret(denied) or not dead then return end
            if not denied then Tally(unitId) end
            HaltTracking()
        elseif evt == "LOOT_READY" then
            for slot = 1, GetNumLootItems() do
                local thingChain = GetLootSlotLink(slot)
                local thingId = type(thingChain) == "string"
                        and not Secret(thingChain)
                        and tonumber(thingChain:match("item:(%d+)"))
                    or nil
                local sources = { GetLootSourceInfo(slot) }
                for catalog = 1, #sources, 2 do
                    local unitId = sources[catalog]
                    if not Secret(unitId) then
                        Tally(unitId)
                        local npc = R.NpcOf(unitId)
                        if thingId and npc and R.Known(npc) then R.AddDrop(npc, thingId) end
                    end
                end
            end
        end
    end)
end

-------------------------------------------------------------------------------
--  Rare Alerts: a card when a rare is near; left-click targets it
-------------------------------------------------------------------------------
local BossCaution = {}
local warnEvents = CreateFrame("Frame")
do
    local NEXT_LATER = 300
    local ELITE = { rare = true, rareelite = true }
    local W, H = 260, 64
    local tileWindow, aim
    local shownNpc, shownId
    local alerted = {}

    local function ConcealAim()
        if aim and aim:IsShown() and not InCombatLockdown() then aim:Hide() end
    end

    local function ConcealCaution()
        if not tileWindow then return end
        ConcealAim()
        tileWindow.fade:Stop()
        tileWindow:Hide()
        shownNpc, shownId = nil, nil
        warnEvents:UnregisterEvent("UNIT_FLAGS")
    end
    BossCaution.Hide = ConcealCaution

    local function BuildAim()
        aim = CreateFrame("Button", "CludesUIRareAlertTarget", UIParent, "SecureActionButtonTemplate")
        aim:SetFrameStrata("DIALOG")
        aim:RegisterForClicks("AnyUp", "AnyDown")
        aim:SetAttribute("type1", "macro")
        aim:SetScript("PostClick", function(_, btnWindow, down)
            if btnWindow == "RightButton" and not down then ConcealCaution() end
        end)
        aim:SetScript("OnEnter", function()
            GameTooltip:SetOwner(tileWindow, "ANCHOR_TOP")
            GameTooltip:SetText(tileWindow.name:GetText() or "Rare", 1, 1, 1)
            GameTooltip:AddLine("Left-click to target it. Right-click to close it.", unpack(BRAND))
            GameTooltip:Show()
        end)
        aim:SetScript("OnLeave", function()
            GameTooltip:Hide()
            ConcealAim()
        end)
        aim:SetScript("OnShow", function(self) self:RegisterEvent("PLAYER_REGEN_DISABLED") end)
        aim:SetScript("OnHide", function(self) self:UnregisterEvent("PLAYER_REGEN_DISABLED") end)
        aim:SetScript("OnEvent", aim.Hide)
        aim:Hide()
    end

    -- A secure button of its own over the card (never its child, so the card
    -- can still show and hide in combat), set and shown only out of combat.
    local function MaskTile()
        if InCombatLockdown() then return end
        local spotted = tileWindow.seen
        local title = not tileWindow.preview and spotted and spotted.name and spotted.name:gsub("%c", "") or nil
        local leftX = tileWindow:GetLeft()
        if not (title and leftX) then return ConcealAim() end
        if not aim then BuildAim() end
        local scale = tileWindow:GetEffectiveScale() / UIParent:GetEffectiveScale()
        local macro = Get("rareAlertSkull") and "/cleartarget\n/targetexact %s\n/tm !8" or "/targetexact %s"
        aim:SetAttribute("macrotext1", macro:format(title))
        aim:ClearAllPoints()
        aim:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", leftX * scale, tileWindow:GetBottom() * scale)
        aim:SetSize(tileWindow:GetWidth() * scale, tileWindow:GetHeight() * scale)
        aim:Show()
    end

    local function Build()
        tileWindow = CreateFrame("Button", "CludesUIRareAlert", UIParent)
        tileWindow:SetSize(W, H)
        tileWindow:SetFrameStrata("HIGH")
        tileWindow:SetClampedToScreen(true)
        CUI.Kit.Panel(tileWindow, 0.92)
        tileWindow:RegisterForClicks("RightButtonUp")
        tileWindow:SetScript("OnClick", function(_, btnWindow)
            if btnWindow == "RightButton" then ConcealCaution() end
        end)
        tileWindow:SetScript("OnEnter", function()
            MaskTile()
            GameTooltip:SetOwner(tileWindow, "ANCHOR_TOP")
            GameTooltip:SetText(tileWindow.name:GetText() or "Rare", 1, 1, 1)
            GameTooltip:AddLine("Right-click to close it.", unpack(BRAND))
            GameTooltip:Show()
        end)
        tileWindow:SetScript("OnLeave", function()
            if aim and aim:IsShown() and aim:IsMouseOver() then return end
            GameTooltip:Hide()
            ConcealAim()
        end)
        tileWindow.model = CreateFrame("PlayerModel", nil, tileWindow)
        tileWindow.model:SetSize(H - 12, H - 12)
        tileWindow.model:SetPoint("LEFT", 6, 0)
        tileWindow.star = tileWindow:CreateTexture(nil, "ARTWORK")
        tileWindow.star:SetSize(32, 32)
        tileWindow.star:SetPoint("CENTER", tileWindow.model, "CENTER")
        tileWindow.star:SetAtlas("VignetteKill")
        tileWindow.name = tileWindow:CreateFontString(nil, "OVERLAY")
        CUI.Kit.Font(tileWindow.name, 14, "essentials")
        tileWindow.name:SetPoint("TOPLEFT", tileWindow.model, "TOPRIGHT", 8, -4)
        tileWindow.name:SetPoint("RIGHT", -8, 0)
        tileWindow.name:SetJustifyH("LEFT")
        tileWindow.name:SetWordWrap(false)
        tileWindow.detail = tileWindow:CreateFontString(nil, "OVERLAY")
        CUI.Kit.Font(tileWindow.detail, 11, "essentials")
        tileWindow.detail:SetPoint("TOPLEFT", tileWindow.name, "BOTTOMLEFT", 0, -4)
        tileWindow.detail:SetPoint("RIGHT", -8, 0)
        tileWindow.detail:SetJustifyH("LEFT")
        tileWindow.detail:SetTextColor(unpack(DIM))
        tileWindow.fade = tileWindow:CreateAnimationGroup()
        local dimIn = tileWindow.fade:CreateAnimation("Alpha")
        dimIn:SetFromAlpha(0)
        dimIn:SetToAlpha(1)
        dimIn:SetDuration(0.3)
        dimIn:SetOrder(1)
        tileWindow.fadeOut = tileWindow.fade:CreateAnimation("Alpha")
        tileWindow.fadeOut:SetFromAlpha(1)
        tileWindow.fadeOut:SetToAlpha(0)
        tileWindow.fadeOut:SetDuration(0.3)
        tileWindow.fadeOut:SetOrder(2)
        tileWindow.fade:SetScript("OnFinished", ConcealCaution)
        tileWindow:Hide()
    end
    BossCaution.Frame = function(make)
        if make and not tileWindow then Build() end
        return tileWindow
    end

    local function Render(spotted)
        local lvl = spotted.level and (spotted.level == -1 and "??" or tostring(spotted.level))
            or (spotted.npc and R.Known(spotted.npc) and R.LevelText(spotted.npc))
            or nil
        tileWindow.name:SetText((spotted.name or "Rare") .. (spotted.elite and " |cffffb040Elite|r" or ""))
        local flags = {}
        if lvl then flags[#flags + 1] = "Level " .. lvl end
        local record = spotted.npc and R.Known(spotted.npc) and R.Record(spotted.npc)
        if record then
            flags[#flags + 1] = record.n > 1 and ("killed %d times"):format(record.n) or "killed before"
        end
        if spotted.tapped then flags[#flags + 1] = "|cffff6060tapped by someone else|r" end
        if spotted.map then
            flags[#flags + 1] = ("%s %.1f, %.1f"):format(AreaHeading(spotted.map), spotted.x or 0, spotted.y or 0)
        end
        tileWindow.detail:SetText(table.concat(flags, "  "))
    end

    local function Reveal(spotted, silent)
        if not tileWindow then Build() end
        if not CUI._unlockActive then F.Place(tileWindow) end
        shownNpc, shownId = not silent and spotted.npc or nil, not silent and spotted.guid or nil
        tileWindow.preview = silent == true
        tileWindow.seen = spotted
        tileWindow.model:ClearModel()
        local isShown = false
        if spotted.unit and UnitExists(spotted.unit) then
            tileWindow.model:SetUnit(spotted.unit)
            isShown = true
        elseif spotted.npc then
            tileWindow.model:SetCreature(spotted.npc)
            isShown = true
        end
        tileWindow.model:SetShown(isShown)
        if isShown then tileWindow.model:SetPortraitZoom(1) end
        tileWindow.star:SetShown(not isShown)
        Render(spotted)
        tileWindow.fade:Stop()
        tileWindow:SetAlpha(1)
        tileWindow:Show()
        if aim and aim:IsShown() then MaskTile() end
        if not silent then
            warnEvents:RegisterEvent("UNIT_FLAGS")
            tileWindow.fadeOut:SetStartDelay(Get("rareAlertTime"))
            tileWindow.fade:Play()
            if Get("rareSound") then PlaySoundFile(598196, "Master") end
            if FlashClientIcon then FlashClientIcon() end
        end
    end
    BossCaution.Show = Reveal

    local function Pending(key, npc)
        if alerted[key] and GetTime() - alerted[key] < NEXT_LATER then return false end
        return not (npc and R.Known(npc) and R.Killed(npc) and not Get("rareAlertKilled"))
    end

    local function Caution(key, spotted)
        if not Pending(key, spotted.npc) then return end
        alerted[key] = GetTime()
        Reveal(spotted)
    end

    local function Reclaim(unitToken)
        local denied = UnitIsTapDenied(unitToken)
        if Secret(denied) or not tileWindow then return end
        local spotted = tileWindow.seen
        if (spotted.tapped == true) == (denied == true) then return end
        spotted.tapped = denied or nil
        Render(spotted)
    end

    local function Check(unitToken)
        if not UnitExists(unitToken) then return end
        local kind = UnitClassification(unitToken)
        if Secret(kind) or not ELITE[kind] then return end
        local unitId = UnitGUID(unitToken)
        if Secret(unitId) or not unitId then return end
        local npc = R.NpcOf(unitId)
        local dead, hostile = UnitIsDead(unitToken), UnitCanAttack("player", unitToken)
        if not npc or Secret(dead) or Secret(hostile) or dead or not hostile then return end
        if npc == shownNpc then
            shownId = shownId or unitId
            if unitId == shownId then Reclaim(unitToken) end
        end
        local title, lvl = UnitName(unitToken), UnitLevel(unitToken)
        if Secret(title) then return end
        if Secret(lvl) then lvl = nil end
        if not Pending(npc, npc) then return end
        local denied = UnitIsTapDenied(unitToken)
        Caution(npc, {
            name = title,
            level = lvl,
            npc = npc,
            guid = unitId,
            unit = unitToken,
            elite = kind == "rareelite",
            tapped = not Secret(denied) and denied or nil,
        })
    end

    local function TestMarker(ident)
        local details = C_VignetteInfo.GetVignetteInfo(ident)
        if not details or Secret(details.objectGUID) or Secret(details.name) then return end
        local npc = R.NpcOf(details.objectGUID)
        local atlas = type(details.atlasName) == "string"
                and not Secret(details.atlasName)
                and details.atlasName
            or ""
        if not npc or not (R.Known(npc) or atlas:find("Kill")) then return end
        if R.Known(npc) and not R.Mine(npc) then return end
        local known = R.Known(npc)
        local chart = C_Map.GetBestMapForUnit("player")
        local place = chart
            and C_VignetteInfo.GetVignettePosition
            and C_VignetteInfo.GetVignettePosition(ident, chart)
        local posX, posY
        if place and not Secret(place) then
            posX, posY = place:GetXY()
        end
        Caution(npc, {
            name = details.name or (known and R.Name(npc)) or "Rare",
            level = known and R.Levels(npc) or nil,
            npc = npc,
            map = posX and chart or nil,
            x = posX and posX * 100,
            y = posY and posY * 100,
        })
    end

    warnEvents:SetScript("OnEvent", function(_, evt, unitToken, onMinimap)
        if evt == "UNIT_FLAGS" then
            if not shownId then return end
            local unitId = UnitGUID(unitToken)
            if Secret(unitId) or unitId ~= shownId then return end
            local dead = UnitIsDead(unitToken)
            if not Secret(dead) and not dead then Reclaim(unitToken) end
        elseif evt == "NAME_PLATE_UNIT_ADDED" then
            Check(unitToken)
        elseif evt == "PLAYER_TARGET_CHANGED" then
            Check("target")
        elseif evt == "UPDATE_MOUSEOVER_UNIT" then
            Check("mouseover")
        elseif evt == "VIGNETTE_MINIMAP_UPDATED" then
            if onMinimap and not Secret(unitToken) then TestMarker(unitToken) end
        end
    end)

    R.OnChange(function(npc)
        if shownNpc and npc == shownNpc and R.Killed(npc) then ConcealCaution() end
    end)

    function BossCaution.Apply()
        warnEvents:UnregisterAllEvents()
        if not (On() and Get("rareAlert")) then return ConcealCaution() end
        warnEvents:RegisterEvent("NAME_PLATE_UNIT_ADDED")
        warnEvents:RegisterEvent("PLAYER_TARGET_CHANGED")
        warnEvents:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
        if C_VignetteInfo and C_VignetteInfo.GetVignetteInfo then
            warnEvents:RegisterEvent("VIGNETTE_MINIMAP_UPDATED")
        end
        if shownNpc then warnEvents:RegisterEvent("UNIT_FLAGS") end
    end

    function BossCaution.Test()
        local unitId = UnitGUID("target")
        if unitId and not Secret(unitId) and UnitExists("target") then
            Reveal({
                name = UnitName("target"),
                level = UnitLevel("target"),
                npc = R.NpcOf(unitId),
                guid = unitId,
                unit = "target",
            })
        else
            Reveal({ name = "Mist Howler", level = 22, npc = 10644 })
        end
    end

    function BossCaution.Preview(enabled)
        if enabled then
            Reveal({ name = "Mist Howler", level = 22, npc = 10644 }, true)
        elseif tileWindow and tileWindow.preview then
            ConcealCaution()
        end
    end
end

-------------------------------------------------------------------------------
--  Map pins: a ! at each giver with a quest for you, a star at each rare
-------------------------------------------------------------------------------
local provider, layer, waiter
local added = false
local markers, markersUsed = {}, 0

local function MarkersDesired() return On() and (Get("questPins") or Get("rarePins")) end

local function Anchor(p)
    local canvas = layer:GetParent()
    local wid, hgt = canvas:GetSize()
    local cs = canvas:GetScale()
    p:SetScale(1 / cs)
    p:ClearAllPoints()
    p:SetPoint("CENTER", canvas, "TOPLEFT", p.x * wid * cs, -p.y * hgt * cs)
end

local function WipeMarkers()
    for catalog = 1, markersUsed do
        markers[catalog]:Hide()
    end
    markersUsed = 0
end

local function FreshMarker()
    local p = CreateFrame("Button", nil, layer)
    p:RegisterForClicks("LeftButtonUp")
    p.icon = p:CreateTexture(nil, "ARTWORK")
    p.icon:SetAllPoints()
    p:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        self.tip(GameTooltip)
        GameTooltip:AddLine("Click to link its map pin in chat.", unpack(DIM))
        GameTooltip:Show()
    end)
    p:SetScript("OnLeave", function() GameTooltip:Hide() end)
    p:SetScript("OnClick", function(self)
        if self.onClick then self.onClick() end
    end)
    if not InCombatLockdown() then p:SetPassThroughButtons("RightButton") end
    return p
end

local function Marker(posX, posY, dims, hintLabel, onClick)
    markersUsed = markersUsed + 1
    local p = markers[markersUsed] or FreshMarker()
    markers[markersUsed] = p
    p:SetSize(dims, dims)
    p.x, p.y = posX / 100, posY / 100
    p.icon:SetVertexColor(1, 1, 1)
    p.icon:SetDesaturated(false)
    p.tip, p.onClick = hintLabel, onClick
    Anchor(p)
    p:Show()
    return p
end

local STATUS_TERMS = {
    done = "Done",
    log = "In your quest log",
    open = "Open",
    low = "Needs level %d",
    later = "Needs an earlier quest",
    closed = "Not offered any more",
    skill = "Needs a profession",
    rep = "Needs reputation",
    held = "Not offered yet",
}

local function StatusLabel(ident, status)
    local terms = STATUS_TERMS[status] or status
    if status == "low" then terms = terms:format(Q.RequiredLevel(ident)) end
    return terms
end

local function TaskHint(ident)
    return function(hintLabel)
        local tint = GetQuestDifficultyColor(Q.Level(ident))
        hintLabel:SetText(Q.Name(ident), tint.r, tint.g, tint.b)
        local flags = { ("Level %d"):format(Q.Level(ident)) }
        if Q.Dungeon(ident) then flags[#flags + 1] = Q.Battleground(ident) and "Battleground" or "Dungeon" end
        if Q.Repeatable(ident) then flags[#flags + 1] = "Repeatable" end
        hintLabel:AddLine(table.concat(flags, ", "), unpack(DIM))
        if Q.Giver(ident) then hintLabel:AddLine(Q.Giver(ident), 1, 1, 1) end
        local status = Q.State(ident)
        hintLabel:AddLine(StatusLabel(ident, status), unpack(status == "open" and AMBER or DIM))
        if status == "later" then
            for _, before in ipairs(Q.Blocking(ident)) do
                hintLabel:AddLine("Requires: " .. (Q.Title(before) or ("quest " .. before)), 1, 0.5, 0.5, true)
            end
        end
        local step, stages = Q.ChainStep(ident)
        if step then
            hintLabel:AddLine(("Step %d of %d of %s"):format(step, stages, Q.Chain(ident).name), unpack(BRAND))
        end
    end
end

local function BossHint(npc)
    return function(hintLabel)
        hintLabel:SetText(R.Name(npc) .. (R.Elite(npc) and " |cffffb040Elite|r" or ""), 1, 1, 1)
        hintLabel:AddLine("Level " .. R.LevelText(npc), unpack(DIM))
        local record = R.Record(npc)
        if record then
            hintLabel:AddLine(
                record.n > 1 and ("Killed %d times"):format(record.n) or "Killed",
                0.38,
                0.85,
                0.5
            )
        end
        R.AddLoot(hintLabel, npc)
    end
end

local function RenderMarkers()
    CUI.Kit.SyncAccent(BRAND)
    WipeMarkers()
    if not MarkersDesired() then return end
    local chartID = WorldMapFrame:GetMapID()
    if not chartID then return end
    local dims = Get("pinSize")
    if Get("questPins") then
        Q.Refresh()
        for _, source in ipairs(Q.Givers(chartID, Get("pinGrey"), Get("chainsOnly"))) do
            local quests = source.quests
            local p = Marker(source.x, source.y, dims * 0.8, function(hintLabel)
                for catalog, ident in ipairs(quests) do
                    if catalog > 1 then hintLabel:AddLine(" ") end
                    if catalog == 1 then
                        TaskHint(ident)(hintLabel)
                    else
                        local tint = GetQuestDifficultyColor(Q.Level(ident))
                        hintLabel:AddLine(
                            Q.Name(ident) .. Dim(("  (%d)"):format(Q.Level(ident))),
                            tint.r,
                            tint.g,
                            tint.b
                        )
                    end
                end
            end, function() Q.Link(quests[1]) end)
            local atlas = source.repeatable and "QuestDaily" or source.grey and "TrivialQuests" or "QuestNormal"
            if not (C_Texture.GetAtlasInfo(atlas) and p.icon:SetAtlas(atlas)) then
                p.icon:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
            end
            if source.dungeon and not source.repeatable then p.icon:SetVertexColor(0.4, 1, 0.4) end
        end
    end
    if Get("rarePins") then
        for _, npc in ipairs(R.OnMap(chartID)) do
            if Get("rarePinsKilled") or not R.Killed(npc) then
                local places = R.Spots(npc)
                local p = Marker(places[1], places[2], dims, BossHint(npc), function() R.Link(npc) end)
                if not (C_Texture.GetAtlasInfo("VignetteKill") and p.icon:SetAtlas("VignetteKill")) then
                    p.icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8")
                end
                if R.Killed(npc) then
                    p.icon:SetDesaturated(true)
                else
                    p.icon:SetDesaturated(false)
                end
            end
        end
    end
end

local function ResizeMarkers()
    for catalog = 1, markersUsed do
        Anchor(markers[catalog])
    end
end

local function MarkersUse()
    if not MarkersDesired() then
        if added then
            WorldMapFrame:RemoveDataProvider(provider)
            added = false
        end
        if layer then WipeMarkers() end
        return
    end
    if not provider then
        if not C_AddOns.IsAddOnLoaded("Blizzard_WorldMap") then
            if not waiter then
                waiter = CreateFrame("Frame")
                waiter:SetScript("OnEvent", function(self, _, title)
                    if title ~= "Blizzard_WorldMap" then return end
                    self:UnregisterEvent("ADDON_LOADED")
                    MarkersUse()
                end)
            end
            waiter:RegisterEvent("ADDON_LOADED")
            return
        end
        layer = CreateFrame("Frame", nil, WorldMapFrame.ScrollContainer.Child)
        layer:SetAllPoints()
        layer:SetFrameLevel(
            WorldMapFrame:GetPinFrameLevelsManager():GetValidFrameLevel("PIN_FRAME_LEVEL_AREA_POI")
        )
        provider = CreateFromMixins(MapCanvasDataProviderMixin)
        provider.OnMapChanged = RenderMarkers
        provider.RefreshAllData = RenderMarkers
        provider.RemoveAllData = WipeMarkers
        provider.OnCanvasScaleChanged = ResizeMarkers
    end
    if not added then
        WorldMapFrame:AddDataProvider(provider)
        added = true
    end
    if WorldMapFrame:IsShown() then RenderMarkers() end
end

-------------------------------------------------------------------------------
--  The Quest List and Rares tabs
-------------------------------------------------------------------------------
local taskArea, eliteArea, taskSearch, eliteSearch = nil, nil, "", ""
local kit = {}
local STATUS_TINT = { done = DIM, log = AMBER, open = { 1, 1, 1 }, low = { 1, 0.5, 0.25 } }

local function AreaMenu(ownerWindow, zones, progress, choose)
    CUI.Kit.ContextMenu(ownerWindow, function(_, root)
        root:CreateButton("Your zone", function() choose(nil) end)
        root:CreateButton("All zones", function() choose(false) end)
        for _, part in ipairs({ { 0, "Eastern Kingdoms" }, { 1, "Kalimdor" } }) do
            local continent, labelLabel = part[1], part[2]
            local sub = root:CreateButton(labelLabel)
            for _, area in ipairs(zones) do
                if area.continent == continent then
                    local num, sum = progress(area)
                    sub:CreateButton(("%s  %d/%d"):format(area.name, num, sum), function() choose(area) end)
                end
            end
        end
        local other = root:CreateButton("Other")
        for _, area in ipairs(zones) do
            if area.continent ~= 0 and area.continent ~= 1 then
                local num, sum = progress(area)
                other:CreateButton(("%s  %d/%d"):format(area.name, num, sum), function() choose(area) end)
            end
        end
    end)
end

local function Tools(hostWindow, key, onArea, onSearch, fetchSearch, extra)
    local tbl = kit[key]
    if not tbl then
        tbl = {}
        tbl.zone = CUI.Kit.Button(hostWindow, "", 90, 22, nil, { key = "essentials" })
        tbl.zone:SetSize(200, 22)
        tbl.zone:SetPoint("LEFT", hostWindow, "LEFT", 0, 0)
        tbl.zone:SetScript("OnClick", function(self) onArea(self) end)
        tbl.search = CUI.Kit.Input(hostWindow, 160, 22, "Search", "essentials")
        tbl.search:SetPoint("LEFT", tbl.zone, "RIGHT", 10, 0)
        tbl.search:HookScript("OnTextChanged", function(self, user)
            if user then onSearch(self:GetText()) end
        end)
        tbl.check = CUI.Kit.Check(
            hostWindow,
            "",
            function(self) extra.set(self:GetChecked()) end,
            "essentials"
        )
        tbl.check:SetPoint("LEFT", tbl.search, "RIGHT", 12, 0)
        kit[key] = tbl
    end
    tbl.zone:Show()
    tbl.search:Show()
    tbl.check:Show()
    tbl.check:SetLabel(extra.label)
    tbl.check:SetChecked(extra.get())
    return tbl
end

local function TaskRow(R2, ident, indent)
    local status = Q.State(ident)
    local tint = GetQuestDifficultyColor(Q.Level(ident))
    local title = ("|cff%02x%02x%02x[%d]|r %s"):format(
        tint.r * 255,
        tint.g * 255,
        tint.b * 255,
        Q.Level(ident),
        Q.Name(ident)
    )
    if status == "done" then
        title = TEST .. " " .. Dim(("[%d] %s"):format(Q.Level(ident), Q.Name(ident)))
    end
    local sub
    if status == "later" then
        local titleRoster = {}
        for catalog, before in ipairs(Q.Blocking(ident)) do
            if catalog > 3 then
                titleRoster[#titleRoster + 1] = "..."
                break
            end
            titleRoster[#titleRoster + 1] = Q.Title(before) or ("quest " .. before)
        end
        sub = "Requires: " .. table.concat(titleRoster, ", ")
    elseif Q.Giver(ident) and status ~= "done" then
        sub = Q.Giver(ident)
    end
    R2:Line(title .. (sub and ("\n" .. Dim(sub)) or ""), {
        indent = indent,
        right = status ~= "done" and StatusLabel(ident, status) or nil,
        rightColour = STATUS_TINT[status] or DIM,
        tip = TaskHint(ident),
        onClick = function() Q.Link(ident) end,
    })
end

local function RenderTaskArea(R2, area)
    local num, sum, low, upper = Q.ZoneProgress(area)
    R2:Line(
        ("%s  %s"):format(
            area.name,
            Dim(("%d of %d done%s"):format(num, sum, low and ("  levels %d-%d"):format(low, upper) or ""))
        ),
        { size = 15, colour = BRAND }
    )
    local chains, singles = Q.ZoneLists(area)
    local conceal = Get("hideDone")
    if #chains > 0 then
        R2:Gap(4)
        R2:Line("Chains", { size = 13, colour = AMBER })
        for _, chain in ipairs(chains) do
            local at, stages = Q.ChainAt(chain)
            if not (conceal and at > stages) then
                R2:Line(
                    ("%s  %s"):format(
                        chain.name,
                        Dim(at > stages and "done" or ("step %d of %d"):format(at, stages))
                    ),
                    { indent = 4, colour = at > stages and DIM or { 1, 1, 1 } }
                )
                for catalog, step in ipairs(chain.steps) do
                    if not (conceal and Q.StepDone(step)) and (catalog >= at - 1 or not conceal) then
                        for _, ident in ipairs(step) do
                            TaskRow(R2, ident, 18)
                        end
                    end
                end
            end
        end
    end
    local isShown = false
    for _, ident in ipairs(singles) do
        local status = Q.State(ident)
        if not (conceal and status == "done") then
            if not isShown then
                R2:Gap(4)
                R2:Line("Quests", { size = 13, colour = AMBER })
                isShown = true
            end
            TaskRow(R2, ident, 4)
        end
    end
end

local function RenderQuests(R2, hostWindow)
    CUI.Kit.SyncAccent(BRAND)
    Q.Refresh()
    local tbl = Tools(hostWindow, "quests", function(self)
        AreaMenu(self, Q.Zones(), Q.ZoneProgress, function(area)
            taskArea = area
            module.DiscoveryRedraw()
        end)
    end, function(labelValue)
        taskSearch = labelValue
        module.DiscoveryRedraw()
    end, function() return taskSearch end, {
        label = "Hide done",
        get = function() return Get("hideDone") end,
        set = function(val)
            F.Cfg().hideDone = val and true or false
            module.DiscoveryRedraw()
        end,
    })
    local num, sum = Q.Progress()
    local search = taskSearch:lower()
    if #search >= 2 then
        tbl.zone:SetText("Search results")
        local found, tally = Q.Search(search, 200)
        R2:Line(("%d quests match"):format(tally), { colour = DIM })
        for _, entry in ipairs(found) do
            R2:Gap(4)
            R2:Line(entry.zone.name, { size = 13, colour = AMBER })
            for _, ident in ipairs(entry.ids) do
                TaskRow(R2, ident, 4)
            end
        end
        return
    end
    if taskArea == false then
        tbl.zone:SetText("All zones")
        R2:Line(
            ("Quest List  %s"):format(Dim(("%d of %d done"):format(num, sum))),
            { size = 16, colour = BRAND }
        )
        for _, area in ipairs(Q.Zones()) do
            local zn, zt, low, upper = Q.ZoneProgress(area)
            if zt > 0 then
                R2:Line(area.name, {
                    right = ("%d / %d%s"):format(zn, zt, low and ("   %d-%d"):format(low, upper) or ""),
                    rightColour = zn == zt and { 0.38, 0.85, 0.5 } or DIM,
                    onClick = function()
                        taskArea = area
                        module.DiscoveryRedraw()
                    end,
                })
            end
        end
        return
    end
    local area = taskArea or Q.CurrentZone()
    if not area then
        tbl.zone:SetText("Pick a zone")
        R2:Line("This place has no quests in the list. Pick a zone above.", { colour = DIM })
        return
    end
    tbl.zone:SetText(area.name)
    RenderTaskArea(R2, area)
end

local function BossRow(R2, npc)
    local killed = R.Killed(npc)
    local title = (killed and (TEST .. " ") or "")
        .. R.Name(npc)
        .. (R.Elite(npc) and " |cffffb040Elite|r" or "")
    R2:Line(killed and Dim(title) or title, {
        indent = 4,
        right = "Level " .. R.LevelText(npc),
        tip = BossHint(npc),
        onClick = function()
            if IsShiftKeyDown() then
                local record = R.Record(npc)
                if not record then
                    R.SetKilled(npc, true)
                elseif record.n == 0 then
                    R.SetKilled(npc, false)
                end
                module.DiscoveryRedraw()
            else
                R.Link(npc)
            end
        end,
    })
end

local function RenderRares(R2, hostWindow)
    CUI.Kit.SyncAccent(BRAND)
    local tbl = Tools(hostWindow, "rares", function(self)
        AreaMenu(self, R.Zones(), R.ZoneProgress, function(area)
            eliteArea = area
            module.DiscoveryRedraw()
        end)
    end, function(labelValue)
        eliteSearch = labelValue
        module.DiscoveryRedraw()
    end, function() return eliteSearch end, {
        label = "Hide killed",
        get = function() return Get("rareHideKilled") end,
        set = function(val)
            F.Cfg().rareHideKilled = val and true or false
            module.DiscoveryRedraw()
        end,
    })
    local search = eliteSearch:lower()
    local conceal = Get("rareHideKilled")
    if #search >= 2 then
        tbl.zone:SetText("Search results")
        local found, tally = R.Search(search, 200)
        R2:Line(("%d rares match"):format(tally), { colour = DIM })
        for _, entry in ipairs(found) do
            R2:Gap(4)
            R2:Line(entry.zone.name, { size = 13, colour = AMBER })
            for _, npc in ipairs(entry.ids) do
                BossRow(R2, npc)
            end
        end
        return
    end
    local num, sum = R.Progress()
    if eliteArea == false then
        tbl.zone:SetText("All zones")
        R2:Line(
            ("Rares  %s"):format(Dim(("%d of %d killed"):format(num, sum))),
            { size = 16, colour = BRAND }
        )
        for _, area in ipairs(R.Zones()) do
            local zn, zt, low, upper = R.ZoneProgress(area)
            if zt > 0 then
                R2:Line(area.name, {
                    right = ("%d / %d%s"):format(zn, zt, low and ("   %d-%d"):format(low, upper) or ""),
                    onClick = function()
                        eliteArea = area
                        module.DiscoveryRedraw()
                    end,
                })
            end
        end
        return
    end
    local area = eliteArea or R.CurrentZone()
    if not area then
        tbl.zone:SetText("Pick a zone")
        R2:Line("This place has no rares in the list. Pick a zone above.", { colour = DIM })
        return
    end
    tbl.zone:SetText(area.name)
    local zn, zt = R.ZoneProgress(area)
    R2:Line(
        ("%s  %s"):format(area.name, Dim(("%d of %d killed"):format(zn, zt))),
        { size = 15, colour = BRAND }
    )
    R2:Line(
        "Kills count from when Discovery is on. Shift-click a rare you killed before to tick it off.",
        { colour = DIM }
    )
    R2:Gap(4)
    for _, npc in ipairs(R.ZoneList(area)) do
        if not (conceal and R.Killed(npc)) then BossRow(R2, npc) end
    end
end

module.DiscoveryAddTab({ key = "quests", label = "Quest List", order = 40, draw = RenderQuests })
module.DiscoveryAddTab({ key = "rares", label = "Rares", order = 50, draw = RenderRares })

R.OnChange(function() module.DiscoveryRedraw() end)

-------------------------------------------------------------------------------
--  Events and apply
-------------------------------------------------------------------------------
local eventWindow = CreateFrame("Frame")
eventWindow:SetScript("OnEvent", function()
    if added and WorldMapFrame:IsShown() then RenderMarkers() end
    module.DiscoveryRedraw()
end)

function module.QuestListApply()
    sourceEvents:UnregisterAllEvents()
    killEvents:UnregisterAllEvents()
    eventWindow:UnregisterAllEvents()
    if On() then
        for _, event in ipairs({ "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_TURNED_IN" }) do
            sourceEvents:RegisterEvent(event)
        end
        killEvents:RegisterEvent("PLAYER_TARGET_CHANGED")
        killEvents:RegisterEvent("LOOT_READY")
        for _, event in ipairs({
            "QUEST_ACCEPTED",
            "QUEST_TURNED_IN",
            "QUEST_REMOVED",
            "PLAYER_LEVEL_UP",
            "SKILL_LINES_CHANGED",
        }) do
            pcall(eventWindow.RegisterEvent, eventWindow, event)
        end
    end
    MarkersUse()
    BossCaution.Apply()
end

CUI._QuestList = {
    Get = Get,
    Cfg = F.Cfg,
    Apply = function() module.QuestListApply() end,
    TestAlert = BossCaution.Test,
}

F.Start(function() end, {
    key = "CUI_RareAlert",
    label = "Rare Alert",
    order = 757,
    shown = function() return On() and Get("rareAlert") end,
    frame = function(make)
        local tileWindow = BossCaution.Frame(make)
        if make and CUI._unlockActive then BossCaution.Preview(true) end
        return tileWindow
    end,
    size = function() return 260, 64 end,
    noAnchorTarget = true,
    noSizeMatchTarget = true,
})
