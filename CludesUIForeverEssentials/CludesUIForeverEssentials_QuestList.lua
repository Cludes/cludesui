if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if not (CludesUI and CludesUI.IS_FOREVER) then
    return
end
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
if not DF then
    return
end

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
local function On()
    return DF.Enabled()
end

local ACCENT = CludesUI.Kit.SyncAccent({}) -- refreshed on each draw
local MUTED = { 0.6, 0.65, 0.7 }
local GOLD = { 1, 0.82, 0 }
local CHECK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:0|t"
local NONE = {}
local function Muted(textValue)
    return "|cff9aa6b2" .. textValue .. "|r"
end
local function Secret(val)
    return issecretvalue ~= nil and issecretvalue(val)
end
local function Font()
    return CludesUI.GetFontPath("essentials")
end
local SAME_MAPS = { [2665] = 2521 }
local function SameMap(map)
    return map and (SAME_MAPS[map] or map)
end

local QD, RD
local function QuestData()
    if not QD then
        QD = module.QuestData()
        module.QuestData = nil
    end
    return QD
end
local function RareData()
    if not RD then
        RD = module.RareData()
        module.RareData = nil
    end
    return RD
end

local function CharKey()
    return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end
local function CharStore(key)
    local conf = F.Cfg()
    conf[key] = conf[key] or {}
    local char = CharKey()
    conf[key][char] = conf[key][char] or {}
    return conf[key][char]
end

local Link = module.DiscoveryLink
local ZoneName = module.DiscoveryZoneName

-------------------------------------------------------------------------------
--  Quest rules
-------------------------------------------------------------------------------
local Q = {}
do
    local NAME, LEVEL, REQ_LEVEL, SIDE, RACES, CLASSES, MAP, X, Y, GIVER, ITEM =
        1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
    local ALLIANCE, HORDE = 1, 2
    local RACE_BITS =
        { [1] = 0, [2] = 1, [3] = 2, [4] = 3, [5] = 4, [6] = 5, [7] = 6, [8] = 7, [95] = 32, [96] = 33 }
    local MAX_UNDER, CLASSIC_GREEN_RANGE, MISSES_HELD = 10, 8, 2
    local D
    local mine, zoneOf, chains, chainOf, closers, recipes, needs, teaches
    local ranks, untils, maxLevels, minReps, maxReps, factions
    local opened, reopened = {}, {}
    local done, logged, skills, known, standings = {}, {}, {}, {}, {}
    local byMap
    local zoneChains, zoneSingles, seenChain = {}, {}, {}
    local found, foundIn = {}, {}
    local named = {}
    local givers, spare, giverAt = {}, {}, {}
    local blocking = {}

    local function HasBit(mask, bit)
        return math.floor(mask / 2 ^ bit) % 2 == 1
    end

    local function ForMe(quest, side, raceBit, classBit)
        if quest[SIDE] == ALLIANCE and side ~= ALLIANCE then
            return false
        end
        if quest[SIDE] == HORDE and side ~= HORDE then
            return false
        end
        if quest[RACES] > 0 and raceBit and not HasBit(quest[RACES], raceBit) then
            return false
        end
        if quest[CLASSES] > 0 and classBit and not HasBit(quest[CLASSES], classBit) then
            return false
        end
        return true
    end

    local function OwnSteps(steps)
        local own = {}
        for _, step in ipairs(steps) do
            local ids = {}
            for _, ident in ipairs(step) do
                if mine[ident] then
                    ids[#ids + 1] = ident
                end
            end
            ids.any = step.any
            if #ids > 0 then
                own[#own + 1] = ids
            end
        end
        return own
    end

    local function AddChain(own)
        local first = D.Quests[own[1][1]]
        local chain = { steps = own, name = first[NAME], level = first[LEVEL], id = #chains + 1 }
        chains[#chains + 1] = chain
        for _, ids in ipairs(own) do
            for _, ident in ipairs(ids) do
                chainOf[ident] = chain
            end
        end
    end

    local function AddCloser(ident, other)
        if not mine[ident] then
            return
        end
        local entries = closers[ident]
        if not entries then
            entries = {}
            closers[ident] = entries
        end
        entries[#entries + 1] = other
    end

    local function IndexClosers()
        closers, recipes, factions = {}, {}, {}
        needs, teaches, ranks, untils =
            D.Profession or NONE, D.Recipe or NONE, D.SkillRank or NONE, D.Until or NONE
        maxLevels, minReps, maxReps = D.MaxLevel or NONE, D.MinReputation or NONE, D.MaxReputation or NONE
        local groupOf = {}
        for _, set in ipairs(D.Exclusive or NONE) do
            for _, ident in ipairs(set) do
                groupOf[ident] = set
                for _, other in ipairs(set) do
                    if other ~= ident then
                        AddCloser(ident, other)
                    end
                end
            end
        end
        for ident, target in pairs(D.Breadcrumb or NONE) do
            AddCloser(ident, target)
            for _, other in ipairs(groupOf[target] or NONE) do
                if other ~= target then
                    AddCloser(ident, other)
                end
            end
        end
        for ident, elements in pairs(D.Requires) do
            for _, element in ipairs(elements) do
                if type(element) == "table" then
                    for _, before in ipairs(element) do
                        AddCloser(before, ident)
                    end
                else
                    AddCloser(element, ident)
                end
            end
        end
        for ident, others in pairs(D.ClosedBy or NONE) do
            for _, other in ipairs(others) do
                AddCloser(ident, other)
            end
        end
        for _, spell in pairs(teaches) do
            recipes[spell] = true
        end
        for _, rep in pairs(minReps) do
            factions[rep[1]] = true
        end
        for _, rep in pairs(maxReps) do
            factions[rep[1]] = true
        end
    end

    local function Prepare()
        if mine then
            return
        end
        D = QuestData()
        mine, zoneOf, chains, chainOf = {}, {}, {}, {}
        local side = UnitFactionGroup("player") == "Horde" and HORDE or ALLIANCE
        local raceBit = RACE_BITS[select(3, UnitRace("player"))]
        local classID = select(3, UnitClass("player"))
        local classBit = classID and classID - 1
        for ident, quest in pairs(D.Quests) do
            if ForMe(quest, side, raceBit, classBit) then
                mine[ident] = true
            end
        end
        for ident in pairs(CharStore("mine")) do
            if D.Quests[ident] then
                mine[ident] = true
            end
        end
        for _, zone in ipairs(D.Zones) do
            for _, ident in ipairs(zone.quests) do
                zoneOf[ident] = zone
            end
        end
        for _, steps in ipairs(D.Chains) do
            local own = OwnSteps(steps)
            if #own > 1 then
                AddChain(own)
            end
        end
        IndexClosers()
    end
    Q.Prepare = Prepare

    local function AddSkills(...)
        for index = 1, select("#", ...) do
            local index = select(index, ...)
            if index then
                local rank, _, _, _, line = select(3, GetProfessionInfo(index))
                if line then
                    skills[line] = rank
                end
            end
        end
    end

    local function ReadKnown()
        wipe(skills)
        AddSkills(GetProfessions())
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
        for index = 1, C_QuestLog.GetNumQuestLogEntries() do
            local ident = C_QuestLog.GetQuestIDForLogIndex(index)
            if ident then
                logged[ident] = true
            end
        end
    end

    local function Outgrown(ident)
        local level, rep = maxLevels[ident], maxReps[ident]
        if level and UnitLevel("player") > level then
            return true
        end
        local standing = rep and standings[rep[1]]
        return standing ~= nil and standing >= rep[2]
    end

    local function ShortOfReputation(ident)
        local rep = minReps[ident]
        local standing = rep and standings[rep[1]]
        return standing ~= nil and standing < rep[2]
    end

    local function Closed(ident)
        local status
        local skill = needs[ident]
        if skill and (skills[skill] or 0) < (ranks[ident] or 1) then
            status = "skill"
        elseif known[teaches[ident]] or done[untils[ident]] or Outgrown(ident) then
            status = "closed"
        else
            local entries = closers[ident] or NONE
            for index = 1, #entries do
                if done[entries[index]] or logged[entries[index]] then
                    status = "closed"
                    break
                end
            end
        end
        if not status and ShortOfReputation(ident) then
            status = "rep"
        end
        if status and not reopened[ident] then
            return status
        end
    end

    local function ZoneTurnIns(ident)
        local zone = zoneOf and zoneOf[ident]
        return zone and CharStore("turnIns")[zone.map] or 0
    end

    local function QuestLevel(ident)
        return D.Quests[ident][LEVEL]
    end

    local function SortKey(entry)
        if type(entry) == "table" then
            return entry.level, entry.name
        end
        local quest = D.Quests[entry]
        return quest[LEVEL], quest[NAME]
    end

    local function ByLevel(a, b)
        local la, na = SortKey(a)
        local lb, nb = SortKey(b)
        if la ~= lb then
            return la < lb
        end
        return na < nb
    end

    local function FoundKey(ident)
        local chain = chainOf[ident]
        if not chain then
            return QuestLevel(ident), 0, 0
        end
        return chain.level, chain.id, (Q.ChainStep(ident))
    end

    local function FoundOrder(a, b)
        local la, ca, sa = FoundKey(a)
        local lb, callback, scrollBar = FoundKey(b)
        if la ~= lb then
            return la < lb
        end
        if ca ~= callback then
            return ca < callback
        end
        if sa ~= scrollBar then
            return sa < scrollBar
        end
        return D.Quests[a][NAME] < D.Quests[b][NAME]
    end

    local function Matches(quest, textValue)
        if quest[NAME]:lower():find(textValue, 1, true) then
            return true
        end
        return quest[GIVER] ~= nil and quest[GIVER]:lower():find(textValue, 1, true) ~= nil
    end

    local function Index()
        if byMap then
            return
        end
        byMap = {}
        for ident, quest in pairs(D.Quests) do
            local map = quest[MAP]
            if map and mine[ident] then
                byMap[map] = byMap[map] or {}
                table.insert(byMap[map], ident)
            end
        end
    end

    local function RecycleGivers()
        for index = #givers, 1, -1 do
            local entry = givers[index]
            wipe(entry.quests)
            spare[#spare + 1] = entry
            givers[index] = nil
        end
        wipe(giverAt)
    end

    local function GiverEntry(quest)
        local key = quest[X] .. ":" .. quest[Y]
        local entry = giverAt[key]
        if entry then
            return entry
        end
        entry = table.remove(spare) or { quests = {} }
        entry.x, entry.y, entry.grey, entry.repeatable, entry.dungeon = quest[X], quest[Y], true, true, false
        giverAt[key] = entry
        givers[#givers + 1] = entry
        return entry
    end

    local function AddToLists(ident)
        local chain = chainOf[ident]
        if not chain then
            zoneSingles[#zoneSingles + 1] = ident
            return
        end
        if seenChain[chain] then
            return
        end
        seenChain[chain] = true
        zoneChains[#zoneChains + 1] = chain
    end

    local function Wanted(ident, chainsOnly)
        return Q.Available(ident) and (chainOf[ident] ~= nil or not chainsOnly or Q.Dungeon(ident))
    end

    local function AddToGiver(ident, trivial)
        local entry = GiverEntry(D.Quests[ident])
        table.insert(entry.quests, ident)
        if not trivial then
            entry.grey = false
        end
        if not Q.Repeatable(ident) then
            entry.repeatable = false
        end
        if Q.Dungeon(ident) and not Q.Battleground(ident) then
            entry.dungeon = true
        end
    end

    function Q.Refresh()
        Prepare()
        opened, reopened = CharStore("opened"), CharStore("reopened")
        ReadKnown()
        wipe(done)
        local all = C_QuestLog.GetAllCompletedQuestIDs and C_QuestLog.GetAllCompletedQuestIDs()
        if all then
            for index = 1, #all do
                done[all[index]] = true
            end
            return
        end
        for ident in pairs(mine) do
            if C_QuestLog.IsQuestFlaggedCompleted(ident) then
                done[ident] = true
            end
        end
    end

    function Q.Done(ident)
        return done[ident] == true
    end
    function Q.InLog(ident)
        return C_QuestLog.GetLogIndexForQuestID(ident) ~= nil
    end
    function Q.Mine(ident)
        return mine[ident] == true
    end
    function Q.Name(ident)
        return D.Quests[ident][NAME]
    end
    function Q.Level(ident)
        return QuestLevel(ident)
    end

    function Q.SetMine(ids)
        Prepare()
        local storage
        for ident in pairs(ids) do
            if not mine[ident] and D.Quests[ident] then
                storage = storage or CharStore("mine")
                storage[ident] = true
            end
        end
        if not storage then
            return
        end
        mine, byMap = nil, nil
        Prepare()
    end

    function Q.RequiredLevel(ident)
        local quest = D.Quests[ident]
        return math.max(quest[REQ_LEVEL], quest[LEVEL] - MAX_UNDER)
    end

    function Q.Zone(ident)
        return zoneOf[ident]
    end
    function Q.Chain(ident)
        return chainOf[ident]
    end
    function Q.Zones()
        Prepare()
        return D.Zones
    end
    function Q.Giver(ident)
        return D.Quests[ident][GIVER]
    end
    function Q.Item(ident)
        return D.Quests[ident][ITEM]
    end
    function Q.Repeatable(ident)
        return D.Repeatable ~= nil and D.Repeatable[ident] == true
    end
    function Q.Dungeon(ident)
        return D.Dungeon ~= nil and D.Dungeon[ident] == true
    end
    function Q.Battleground(ident)
        return D.Battleground ~= nil and D.Battleground[ident] == true
    end
    function Q.Elsewhere(ident)
        return D.Elsewhere ~= nil and D.Elsewhere[ident] == true
    end

    function Q.Spot(ident)
        local quest = D.Quests[ident]
        if quest[MAP] then
            return quest[MAP], quest[X], quest[Y]
        end
    end

    function Q.StepDone(step)
        for _, ident in ipairs(step) do
            if done[ident] and step.any then
                return true
            end
            if not done[ident] and not step.any then
                return false
            end
        end
        return not step.any
    end

    function Q.ChainAt(chain)
        local steps = chain.steps
        for index = #steps, 1, -1 do
            if Q.StepDone(steps[index]) then
                return index + 1, #steps
            end
        end
        return 1, #steps
    end

    function Q.NotOffered(ident)
        local entry = CharStore("notOffered")[ident]
        if not entry then
            return false
        end
        if (entry[3] or 1) >= MISSES_HELD then
            return true
        end
        return entry[1] == UnitLevel("player") and entry[2] == ZoneTurnIns(ident)
    end

    function Q.SetOffered(ident, offered)
        local storage = CharStore("notOffered")
        local entry, level = storage[ident], UnitLevel("player")
        if offered then
            storage[ident] = nil
        elseif not entry then
            storage[ident] = { level, ZoneTurnIns(ident), 1 }
        else
            if entry[1] ~= level then
                entry[3] = (entry[3] or 1) + 1
            end
            entry[1], entry[2] = level, ZoneTurnIns(ident)
        end
    end

    function Q.CountTurnIn(ident)
        Prepare()
        local zone = zoneOf[ident]
        if not zone then
            return
        end
        local turnIns = CharStore("turnIns")
        turnIns[zone.map] = (turnIns[zone.map] or 0) + 1
    end

    function Q.State(ident)
        local status = Q.Expected(ident)
        if status == "open" and Q.NotOffered(ident) then
            return "held"
        end
        return status
    end

    local function Counts(ident)
        return mine[ident] or not D.Quests[ident]
    end

    local function Met(element)
        if type(element) == "number" then
            return done[element] or not Counts(element)
        end
        local counted = false
        for _, ident in ipairs(element) do
            if done[ident] then
                return true
            end
            if Counts(ident) then
                counted = true
            end
        end
        return not counted
    end

    function Q.Opened(ident)
        for _, element in ipairs(D.Requires[ident] or NONE) do
            if not Met(element) then
                return opened[ident] == true
            end
        end
        return true
    end

    function Q.SetOpened(ident)
        CharStore("opened")[ident] = true
    end
    function Q.SetReopened(ident)
        CharStore("reopened")[ident] = true
    end

    function Q.Blocking(ident)
        wipe(blocking)
        for _, element in ipairs(D.Requires[ident] or NONE) do
            if not Met(element) then
                local first = element
                if type(element) == "table" then
                    for _, other in ipairs(element) do
                        if Counts(other) then
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
        local quest = D.Quests[ident]
        return quest and quest[NAME] or C_QuestLog.GetTitleForQuestID(ident)
    end

    function Q.Expected(ident)
        if done[ident] then
            return "done"
        end
        if Q.InLog(ident) then
            return "log"
        end
        local closed = Closed(ident)
        if closed then
            return closed
        end
        if not Q.Opened(ident) then
            return "later"
        end
        if UnitLevel("player") < Q.RequiredLevel(ident) then
            return "low"
        end
        return "open"
    end

    function Q.ZoneProgress(zone)
        local num, sum, low, high = 0, 0, nil, nil
        for _, ident in ipairs(zone.quests) do
            if
                mine[ident]
                and not Q.Repeatable(ident)
                and not Q.Dungeon(ident)
                and not Q.Elsewhere(ident)
                and (done[ident] or not Closed(ident) or Q.InLog(ident))
            then
                sum = sum + 1
                if done[ident] then
                    num = num + 1
                end
                local level = QuestLevel(ident)
                if level > 0 then
                    low = math.min(low or level, level)
                    high = math.max(high or level, level)
                end
            end
        end
        return num, sum, low, high
    end

    function Q.Progress()
        local num, sum = 0, 0
        for _, zone in ipairs(D.Zones) do
            local zn, zt = Q.ZoneProgress(zone)
            num, sum = num + zn, sum + zt
        end
        return num, sum
    end

    function Q.ZoneLists(zone)
        wipe(zoneChains)
        wipe(zoneSingles)
        wipe(seenChain)
        for _, ident in ipairs(zone.quests) do
            if mine[ident] then
                AddToLists(ident)
            end
        end
        table.sort(zoneChains, ByLevel)
        table.sort(zoneSingles, ByLevel)
        return zoneChains, zoneSingles
    end

    function Q.ChainStep(ident)
        local chain = chainOf[ident]
        if not chain then
            return
        end
        for index, step in ipairs(chain.steps) do
            for _, other in ipairs(step) do
                if other == ident then
                    return index, #chain.steps
                end
            end
        end
    end

    function Q.Search(textValue, limit)
        Prepare()
        wipe(found)
        local num = 0
        for _, zone in ipairs(D.Zones) do
            local entry = foundIn[zone] or { zone = zone, ids = {} }
            foundIn[zone] = entry
            local ids = wipe(entry.ids)
            for _, ident in ipairs(zone.quests) do
                if mine[ident] and Matches(D.Quests[ident], textValue) then
                    num = num + 1
                    if num <= limit then
                        ids[#ids + 1] = ident
                    end
                end
            end
            if #ids > 0 then
                table.sort(ids, FoundOrder)
                found[#found + 1] = entry
            end
        end
        return found, num
    end

    function Q.CurrentZone()
        Prepare()
        local map = SameMap(C_Map.GetBestMapForUnit("player"))
        while map do
            for _, zone in ipairs(D.Zones) do
                if zone.map == map then
                    return zone
                end
            end
            local details = C_Map.GetMapInfo(map)
            map = details and details.parentMapID ~= 0 and details.parentMapID or nil
        end
    end

    function Q.Link(ident)
        local map, posX, posY = Q.Spot(ident)
        if map then
            Link(Q.Name(ident), map, posX, posY, Q.Giver(ident) and ("(" .. Q.Giver(ident) .. ")"))
        end
    end

    function Q.Trivial(ident)
        local level = QuestLevel(ident)
        if level <= 0 then
            return false
        end
        if QuestDifficultyColors and QuestDifficultyColors.trivial then
            return GetQuestDifficultyColor(level) == QuestDifficultyColors.trivial
        end
        local green = GetQuestGreenRange and GetQuestGreenRange() or CLASSIC_GREEN_RANGE
        return level < UnitLevel("player") - green
    end

    function Q.Available(ident)
        return mine[ident] == true and Q.State(ident) == "open"
    end

    function Q.GiverQuests(name, mapID)
        if Secret(name) then
            return NONE
        end
        Prepare()
        Index()
        wipe(named)
        for _, ident in ipairs(byMap[mapID] or NONE) do
            if D.Quests[ident][GIVER] == name then
                named[#named + 1] = ident
            end
        end
        return named
    end

    function Q.Givers(mapID, grey, chainsOnly)
        Prepare()
        Index()
        RecycleGivers()
        for _, ident in ipairs(byMap[SameMap(mapID)] or NONE) do
            if Wanted(ident, chainsOnly) then
                local trivial = Q.Trivial(ident)
                if grey or not trivial then
                    AddToGiver(ident, trivial)
                end
            end
        end
        return givers
    end
end

-------------------------------------------------------------------------------
--  Givers: learn from the quest givers you speak to what they really offer
-------------------------------------------------------------------------------
local giverEvents = CreateFrame("Frame")
do
    local CLOSED = { closed = true, skill = true, rep = true }
    local offered, titles = {}, {}
    local listed

    local function ReadableGUID(unitToken)
        local unitGuid = UnitGUID(unitToken)
        if not Secret(unitGuid) then
            return unitGuid
        end
    end

    local function Learn(unitToken)
        if not UnitExists(unitToken) or UnitIsPlayer(unitToken) then
            return
        end
        local zone = Q.CurrentZone()
        if not zone then
            return
        end
        Q.Refresh()
        Q.SetMine(offered)
        local trivial = C_Minimap
            and C_Minimap.IsFilteredOut
            and Enum.MinimapTrackingFilter
            and not C_Minimap.IsFilteredOut(Enum.MinimapTrackingFilter.TrivialQuests)
        for _, ident in ipairs(Q.GiverQuests(UnitName(unitToken), zone.map)) do
            if offered[ident] and CLOSED[Q.Expected(ident)] then
                Q.SetReopened(ident)
            end
            if offered[ident] and Q.Expected(ident) == "later" then
                Q.SetOpened(ident)
            end
            if Q.Expected(ident) == "open" and (trivial or not Q.Trivial(ident)) then
                Q.SetOffered(ident, offered[ident] == true)
            end
        end
    end

    giverEvents:SetScript("OnEvent", function(_, evt, questID)
        if evt == "GOSSIP_SHOW" then
            wipe(offered)
            for _, quest in ipairs(C_GossipInfo.GetAvailableQuests() or NONE) do
                if quest.questID then
                    offered[quest.questID] = true
                end
            end
            listed = ReadableGUID("npc")
            Learn("npc")
        elseif evt == "QUEST_GREETING" then
            wipe(offered)
            wipe(titles)
            for index = 1, GetNumAvailableQuests() do
                local ident = GetAvailableQuestInfo and select(5, GetAvailableQuestInfo(index))
                if ident then
                    offered[ident] = true
                else
                    titles[GetAvailableTitle(index) or ""] = true
                end
            end
            if next(titles) then
                local zone = Q.CurrentZone()
                if zone then
                    for _, ident in ipairs(Q.GiverQuests(UnitName("npc"), zone.map)) do
                        if titles[Q.Name(ident)] then
                            offered[ident] = true
                        end
                    end
                end
            end
            listed = ReadableGUID("npc")
            Learn("npc")
        elseif evt == "QUEST_DETAIL" then
            local unitGuid = ReadableGUID("questnpc")
            if not unitGuid or unitGuid == listed then
                return
            end
            wipe(offered)
            offered[GetQuestID()] = true
            Learn("questnpc")
        elseif evt == "QUEST_TURNED_IN" then
            Q.CountTurnIn(questID)
        end
    end)
end

-------------------------------------------------------------------------------
--  Rare rules and kills
-------------------------------------------------------------------------------
local R = {}
local killEvents = CreateFrame("Frame")
do
    local NAME, LOW, HIGH, ELITE, REACT_A, REACT_H, MAP, SPOTS, TRAIL = 1, 2, 3, 4, 5, 6, 7, 8, 9
    local LOOT_ID, LOOT_QUALITY, LOOT_CHANCE, LOOT_NAME, LOOT_NEW = 1, 2, 3, 4, 5
    local D
    local mine, byMap
    local listeners = {}
    local entries, found, foundIn, lowered = {}, {}, {}, {}

    local function Prepare()
        if mine then
            return
        end
        D = RareData()
        mine = {}
        local react = UnitFactionGroup("player") == "Horde" and REACT_H or REACT_A
        for npc, rare in pairs(D.Rares) do
            if rare[react] ~= 1 then
                mine[npc] = true
            end
        end
    end
    R.Prepare = Prepare

    local function Kills()
        return CharStore("rareKills")
    end
    local function Drops()
        return CharStore("rareDrops")
    end
    local function Changed(npc)
        for _, func in ipairs(listeners) do
            func(npc)
        end
    end

    local function ZoneFor(map)
        for _, zone in ipairs(D.Zones) do
            if zone.map == map then
                return zone
            end
        end
    end

    local function Nearest(points, px, py, bx, by, bestD)
        for index = 1, #points, 2 do
            local dx, dy = points[index] / 100 - px, points[index + 1] / 100 - py
            local skinData = dx * dx + dy * dy
            if not bestD or skinData < bestD then
                bx, by, bestD = points[index], points[index + 1], skinData
            end
        end
        return bx, by, bestD
    end

    function R.NpcOf(unitGuid)
        if type(unitGuid) ~= "string" or Secret(unitGuid) then
            return
        end
        local kind, _, _, _, _, ident = strsplit("-", unitGuid)
        if kind == "Creature" or kind == "Vehicle" then
            return tonumber(ident)
        end
    end

    function R.Known(npc)
        Prepare()
        return D.Rares[npc] ~= nil
    end
    function R.Name(npc)
        return D.Rares[npc][NAME]
    end
    function R.Elite(npc)
        return D.Rares[npc][ELITE] == 1
    end
    function R.Map(npc)
        return D.Rares[npc][MAP]
    end
    function R.Levels(npc)
        local rare = D.Rares[npc]
        return rare[LOW], rare[HIGH]
    end
    function R.LevelText(npc)
        local low, high = R.Levels(npc)
        if low <= 0 then
            return "??"
        end
        if low == high then
            return tostring(low)
        end
        return ("%d-%d"):format(low, high)
    end
    function R.Mine(npc)
        Prepare()
        return mine[npc] == true
    end
    function R.OnChange(func)
        listeners[#listeners + 1] = func
    end
    function R.Killed(npc)
        return Kills()[npc] ~= nil
    end
    function R.Record(npc)
        return Kills()[npc]
    end

    function R.AddKill(npc, unitGuid)
        local all = Kills()
        local record = all[npc] or { n = 0 }
        record.n = record.n + 1
        record.at = time()
        record.guid = unitGuid
        all[npc] = record
        Changed(npc)
    end

    function R.SetKilled(npc, killed)
        local all = Kills()
        all[npc] = killed and (all[npc] or { n = 0, at = time() }) or nil
        Changed(npc)
    end

    function R.Dropped(npc, itemId)
        local itemList = Drops()[npc]
        return itemList ~= nil and itemList[itemId] ~= nil
    end

    function R.AddDrop(npc, itemId)
        local all = Drops()
        all[npc] = all[npc] or {}
        if all[npc][itemId] then
            return
        end
        all[npc][itemId] = time()
        Changed(npc)
    end

    function R.ZoneProgress(zone)
        Prepare()
        local all = Kills()
        local num, sum, low, high = 0, 0, nil, nil
        for _, npc in ipairs(zone.rares) do
            if mine[npc] then
                sum = sum + 1
                if all[npc] then
                    num = num + 1
                end
                local lo, hi = R.Levels(npc)
                if lo > 0 then
                    low = math.min(low or lo, lo)
                    high = math.max(high or hi, hi)
                end
            end
        end
        return num, sum, low, high
    end

    function R.Progress()
        Prepare()
        local num, sum = 0, 0
        for _, zone in ipairs(D.Zones) do
            local zn, zt = R.ZoneProgress(zone)
            num, sum = num + zn, sum + zt
        end
        return num, sum
    end

    function R.Zones()
        Prepare()
        return D.Zones
    end

    function R.ZoneList(zone)
        Prepare()
        wipe(entries)
        for _, npc in ipairs(zone.rares) do
            if mine[npc] then
                entries[#entries + 1] = npc
            end
        end
        return entries
    end

    function R.CurrentZone()
        Prepare()
        local map = SameMap(C_Map.GetBestMapForUnit("player"))
        while map do
            local zone = ZoneFor(map)
            if zone then
                return zone
            end
            local details = C_Map.GetMapInfo(map)
            map = details and details.parentMapID ~= 0 and details.parentMapID or nil
        end
    end

    function R.Search(textValue, limit)
        Prepare()
        wipe(found)
        local num = 0
        for _, zone in ipairs(D.Zones) do
            local entry = foundIn[zone] or { zone = zone, ids = {} }
            foundIn[zone] = entry
            local ids = wipe(entry.ids)
            for _, npc in ipairs(zone.rares) do
                local name = lowered[npc]
                if not name then
                    name = D.Rares[npc][NAME]:lower()
                    lowered[npc] = name
                end
                if mine[npc] and name:find(textValue, 1, true) then
                    num = num + 1
                    if num <= limit then
                        ids[#ids + 1] = npc
                    end
                end
            end
            if #ids > 0 then
                found[#found + 1] = entry
            end
        end
        return found, num
    end

    function R.Spot(npc)
        local rare = D.Rares[npc]
        local spots = rare[SPOTS]
        if #spots == 0 then
            return
        end
        local place = SameMap(C_Map.GetBestMapForUnit("player")) == rare[MAP]
            and C_Map.GetPlayerMapPosition(rare[MAP], "player")
        if not place or Secret(place) then
            return rare[MAP], spots[1], spots[2]
        end
        local px, py = place:GetXY()
        local bx, by, bestD = Nearest(spots, px, py, spots[1], spots[2], nil)
        if rare[TRAIL] then
            bx, by = Nearest(rare[TRAIL], px, py, bx, by, bestD)
        end
        return rare[MAP], bx, by
    end

    function R.Spots(npc)
        return D.Rares[npc][SPOTS]
    end
    function R.Loot(npc)
        return D.Loot and D.Loot[npc]
    end

    function R.AddLoot(tipText, npc)
        local loot = R.Loot(npc)
        if not loot then
            return
        end
        tipText:AddLine(" ")
        tipText:AddLine("Drops", unpack(GOLD))
        for _, entry in ipairs(loot) do
            local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[entry[LOOT_QUALITY]]
                or { r = 1, g = 1, b = 1 }
            local iconTex = C_Item.GetItemIconByID(entry[LOOT_ID])
            local name = (iconTex and ("|T%s:14:14|t "):format(iconTex) or "")
                .. entry[LOOT_NAME]
                .. (entry[LOOT_NEW] == 1 and " " .. CludesUI.Kit.AccentHex() .. "(new in Forever)|r" or "")
                .. (R.Dropped(npc, entry[LOOT_ID]) and " |cff60d080(you got it)|r" or "")
            local chance = entry[LOOT_CHANCE]
            tipText:AddDoubleLine(
                name,
                chance >= 1 and ("%d%%"):format(math.floor(chance + 0.5)) or ("%.1f%%"):format(chance),
                c.r,
                c.g,
                c.b,
                unpack(MUTED)
            )
        end
        if loot.more then
            tipText:AddLine(("And %d more"):format(loot.more), unpack(MUTED))
        end
    end

    function R.OnMap(mapID)
        Prepare()
        if not byMap then
            byMap = {}
            for npc, rare in pairs(D.Rares) do
                if mine[npc] and #rare[SPOTS] > 0 then
                    byMap[rare[MAP]] = byMap[rare[MAP]] or {}
                    table.insert(byMap[rare[MAP]], npc)
                end
            end
        end
        return byMap[SameMap(mapID)] or NONE
    end

    function R.Link(npc)
        local map, posX, posY = R.Spot(npc)
        if map then
            Link(R.Name(npc), map, posX, posY)
        end
    end

    -- Kills: a rare you targeted dying while yours, or a corpse you loot.
    local counted = {}
    local watching

    local function Count(unitGuid)
        local npc = R.NpcOf(unitGuid)
        if not npc or not R.Known(npc) or counted[unitGuid] then
            return
        end
        counted[unitGuid] = true
        local record = R.Record(npc)
        if record and record.guid == unitGuid then
            return
        end
        R.AddKill(npc, unitGuid)
    end

    local function StopWatching()
        watching = nil
        killEvents:UnregisterEvent("UNIT_HEALTH")
    end

    killEvents:SetScript("OnEvent", function(_, evt)
        if evt == "PLAYER_TARGET_CHANGED" then
            StopWatching()
            local unitGuid = UnitGUID("target")
            local npc = R.NpcOf(unitGuid)
            if not npc or not R.Known(npc) or counted[unitGuid] then
                return
            end
            local dead, denied = UnitIsDead("target"), UnitIsTapDenied("target")
            if Secret(dead) or Secret(denied) then
                return
            end
            if dead then
                if not denied then
                    Count(unitGuid)
                end
                return
            end
            watching = unitGuid
            killEvents:RegisterUnitEvent("UNIT_HEALTH", "target")
        elseif evt == "UNIT_HEALTH" then
            local unitGuid = UnitGUID("target")
            if Secret(unitGuid) or unitGuid ~= watching then
                return
            end
            local dead, denied = UnitIsDead("target"), UnitIsTapDenied("target")
            if Secret(dead) or Secret(denied) or not dead then
                return
            end
            if not denied then
                Count(unitGuid)
            end
            StopWatching()
        elseif evt == "LOOT_READY" then
            for slot = 1, GetNumLootItems() do
                local itemLink = GetLootSlotLink(slot)
                local itemId = type(itemLink) == "string"
                        and not Secret(itemLink)
                        and tonumber(itemLink:match("item:(%d+)"))
                    or nil
                local sources = { GetLootSourceInfo(slot) }
                for index = 1, #sources, 2 do
                    local unitGuid = sources[index]
                    if not Secret(unitGuid) then
                        Count(unitGuid)
                        local npc = R.NpcOf(unitGuid)
                        if itemId and npc and R.Known(npc) then
                            R.AddDrop(npc, itemId)
                        end
                    end
                end
            end
        end
    end)
end

-------------------------------------------------------------------------------
--  Rare Alerts: a card when a rare is near; left-click targets it
-------------------------------------------------------------------------------
local RareAlert = {}
local alertEvents = CreateFrame("Frame")
do
    local AGAIN_AFTER = 300
    local RARE = { rare = true, rareelite = true }
    local W, H = 260, 64
    local cardFrame, target
    local shownNpc, shownGuid
    local alerted = {}

    local function HideTarget()
        if target and target:IsShown() and not InCombatLockdown() then
            target:Hide()
        end
    end

    local function HideAlert()
        if not cardFrame then
            return
        end
        HideTarget()
        cardFrame.fade:Stop()
        cardFrame:Hide()
        shownNpc, shownGuid = nil, nil
        alertEvents:UnregisterEvent("UNIT_FLAGS")
    end
    RareAlert.Hide = HideAlert

    local function BuildTarget()
        target = CreateFrame("Button", "CludesUIRareAlertTarget", UIParent, "SecureActionButtonTemplate")
        target:SetFrameStrata("DIALOG")
        target:RegisterForClicks("AnyUp", "AnyDown")
        target:SetAttribute("type1", "macro")
        target:SetScript("PostClick", function(_, btnFrame, down)
            if btnFrame == "RightButton" and not down then
                HideAlert()
            end
        end)
        target:SetScript("OnEnter", function()
            GameTooltip:SetOwner(cardFrame, "ANCHOR_TOP")
            GameTooltip:SetText(cardFrame.name:GetText() or "Rare", 1, 1, 1)
            GameTooltip:AddLine("Left-click to target it. Right-click to close it.", unpack(ACCENT))
            GameTooltip:Show()
        end)
        target:SetScript("OnLeave", function()
            GameTooltip:Hide()
            HideTarget()
        end)
        target:SetScript("OnShow", function(self)
            self:RegisterEvent("PLAYER_REGEN_DISABLED")
        end)
        target:SetScript("OnHide", function(self)
            self:UnregisterEvent("PLAYER_REGEN_DISABLED")
        end)
        target:SetScript("OnEvent", target.Hide)
        target:Hide()
    end

    -- A secure button of its own over the card (never its child, so the card
    -- can still show and hide in combat), set and shown only out of combat.
    local function CoverCard()
        if InCombatLockdown() then
            return
        end
        local seen = cardFrame.seen
        local name = not cardFrame.preview and seen and seen.name and seen.name:gsub("%c", "") or nil
        local leftX = cardFrame:GetLeft()
        if not (name and leftX) then
            return HideTarget()
        end
        if not target then
            BuildTarget()
        end
        local scale = cardFrame:GetEffectiveScale() / UIParent:GetEffectiveScale()
        local macro = Get("rareAlertSkull") and "/cleartarget\n/targetexact %s\n/tm !8" or "/targetexact %s"
        target:SetAttribute("macrotext1", macro:format(name))
        target:ClearAllPoints()
        target:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", leftX * scale, cardFrame:GetBottom() * scale)
        target:SetSize(cardFrame:GetWidth() * scale, cardFrame:GetHeight() * scale)
        target:Show()
    end

    local function Build()
        cardFrame = CreateFrame("Button", "CludesUIRareAlert", UIParent)
        cardFrame:SetSize(W, H)
        cardFrame:SetFrameStrata("HIGH")
        cardFrame:SetClampedToScreen(true)
        CludesUI.Kit.Panel(cardFrame, 0.92)
        cardFrame:RegisterForClicks("RightButtonUp")
        cardFrame:SetScript("OnClick", function(_, btnFrame)
            if btnFrame == "RightButton" then
                HideAlert()
            end
        end)
        cardFrame:SetScript("OnEnter", function()
            CoverCard()
            GameTooltip:SetOwner(cardFrame, "ANCHOR_TOP")
            GameTooltip:SetText(cardFrame.name:GetText() or "Rare", 1, 1, 1)
            GameTooltip:AddLine("Right-click to close it.", unpack(ACCENT))
            GameTooltip:Show()
        end)
        cardFrame:SetScript("OnLeave", function()
            if target and target:IsShown() and target:IsMouseOver() then
                return
            end
            GameTooltip:Hide()
            HideTarget()
        end)
        cardFrame.model = CreateFrame("PlayerModel", nil, cardFrame)
        cardFrame.model:SetSize(H - 12, H - 12)
        cardFrame.model:SetPoint("LEFT", 6, 0)
        cardFrame.star = cardFrame:CreateTexture(nil, "ARTWORK")
        cardFrame.star:SetSize(32, 32)
        cardFrame.star:SetPoint("CENTER", cardFrame.model, "CENTER")
        cardFrame.star:SetAtlas("VignetteKill")
        cardFrame.name = cardFrame:CreateFontString(nil, "OVERLAY")
        CludesUI.Kit.Font(cardFrame.name, 14, "essentials")
        cardFrame.name:SetPoint("TOPLEFT", cardFrame.model, "TOPRIGHT", 8, -4)
        cardFrame.name:SetPoint("RIGHT", -8, 0)
        cardFrame.name:SetJustifyH("LEFT")
        cardFrame.name:SetWordWrap(false)
        cardFrame.detail = cardFrame:CreateFontString(nil, "OVERLAY")
        CludesUI.Kit.Font(cardFrame.detail, 11, "essentials")
        cardFrame.detail:SetPoint("TOPLEFT", cardFrame.name, "BOTTOMLEFT", 0, -4)
        cardFrame.detail:SetPoint("RIGHT", -8, 0)
        cardFrame.detail:SetJustifyH("LEFT")
        cardFrame.detail:SetTextColor(unpack(MUTED))
        cardFrame.fade = cardFrame:CreateAnimationGroup()
        local fadeIn = cardFrame.fade:CreateAnimation("Alpha")
        fadeIn:SetFromAlpha(0)
        fadeIn:SetToAlpha(1)
        fadeIn:SetDuration(0.3)
        fadeIn:SetOrder(1)
        cardFrame.fadeOut = cardFrame.fade:CreateAnimation("Alpha")
        cardFrame.fadeOut:SetFromAlpha(1)
        cardFrame.fadeOut:SetToAlpha(0)
        cardFrame.fadeOut:SetDuration(0.3)
        cardFrame.fadeOut:SetOrder(2)
        cardFrame.fade:SetScript("OnFinished", HideAlert)
        cardFrame:Hide()
    end
    RareAlert.Frame = function(build)
        if build and not cardFrame then
            Build()
        end
        return cardFrame
    end

    local function Paint(seen)
        local level = seen.level and (seen.level == -1 and "??" or tostring(seen.level))
            or (seen.npc and R.Known(seen.npc) and R.LevelText(seen.npc))
            or nil
        cardFrame.name:SetText((seen.name or "Rare") .. (seen.elite and " |cffffb040Elite|r" or ""))
        local bits = {}
        if level then
            bits[#bits + 1] = "Level " .. level
        end
        local record = seen.npc and R.Known(seen.npc) and R.Record(seen.npc)
        if record then
            bits[#bits + 1] = record.n > 1 and ("killed %d times"):format(record.n) or "killed before"
        end
        if seen.tapped then
            bits[#bits + 1] = "|cffff6060tapped by someone else|r"
        end
        if seen.map then
            bits[#bits + 1] = ("%s %.1f, %.1f"):format(ZoneName(seen.map), seen.x or 0, seen.y or 0)
        end
        cardFrame.detail:SetText(table.concat(bits, "  "))
    end

    local function Show(seen, quiet)
        if not cardFrame then
            Build()
        end
        if not CludesUI._unlockActive then
            F.Place(cardFrame)
        end
        shownNpc, shownGuid = not quiet and seen.npc or nil, not quiet and seen.guid or nil
        cardFrame.preview = quiet == true
        cardFrame.seen = seen
        cardFrame.model:ClearModel()
        local isShown = false
        if seen.unit and UnitExists(seen.unit) then
            cardFrame.model:SetUnit(seen.unit)
            isShown = true
        elseif seen.npc then
            cardFrame.model:SetCreature(seen.npc)
            isShown = true
        end
        cardFrame.model:SetShown(isShown)
        if isShown then
            cardFrame.model:SetPortraitZoom(1)
        end
        cardFrame.star:SetShown(not isShown)
        Paint(seen)
        cardFrame.fade:Stop()
        cardFrame:SetAlpha(1)
        cardFrame:Show()
        if target and target:IsShown() then
            CoverCard()
        end
        if not quiet then
            alertEvents:RegisterEvent("UNIT_FLAGS")
            cardFrame.fadeOut:SetStartDelay(Get("rareAlertTime"))
            cardFrame.fade:Play()
            if Get("rareSound") then
                PlaySoundFile(598196, "Master")
            end
            if FlashClientIcon then
                FlashClientIcon()
            end
        end
    end
    RareAlert.Show = Show

    local function Due(key, npc)
        if alerted[key] and GetTime() - alerted[key] < AGAIN_AFTER then
            return false
        end
        return not (npc and R.Known(npc) and R.Killed(npc) and not Get("rareAlertKilled"))
    end

    local function Alert(key, seen)
        if not Due(key, seen.npc) then
            return
        end
        alerted[key] = GetTime()
        Show(seen)
    end

    local function Retap(unitToken)
        local denied = UnitIsTapDenied(unitToken)
        if Secret(denied) or not cardFrame then
            return
        end
        local seen = cardFrame.seen
        if (seen.tapped == true) == (denied == true) then
            return
        end
        seen.tapped = denied or nil
        Paint(seen)
    end

    local function Check(unitToken)
        if not UnitExists(unitToken) then
            return
        end
        local kind = UnitClassification(unitToken)
        if Secret(kind) or not RARE[kind] then
            return
        end
        local unitGuid = UnitGUID(unitToken)
        if Secret(unitGuid) or not unitGuid then
            return
        end
        local npc = R.NpcOf(unitGuid)
        local dead, hostile = UnitIsDead(unitToken), UnitCanAttack("player", unitToken)
        if not npc or Secret(dead) or Secret(hostile) or dead or not hostile then
            return
        end
        if npc == shownNpc then
            shownGuid = shownGuid or unitGuid
            if unitGuid == shownGuid then
                Retap(unitToken)
            end
        end
        local name, level = UnitName(unitToken), UnitLevel(unitToken)
        if Secret(name) then
            return
        end
        if Secret(level) then
            level = nil
        end
        if not Due(npc, npc) then
            return
        end
        local denied = UnitIsTapDenied(unitToken)
        Alert(npc, {
            name = name,
            level = level,
            npc = npc,
            guid = unitGuid,
            unit = unitToken,
            elite = kind == "rareelite",
            tapped = not Secret(denied) and denied or nil,
        })
    end

    local function CheckVignette(ident)
        local details = C_VignetteInfo.GetVignetteInfo(ident)
        if not details or Secret(details.objectGUID) or Secret(details.name) then
            return
        end
        local npc = R.NpcOf(details.objectGUID)
        local atlas = type(details.atlasName) == "string"
                and not Secret(details.atlasName)
                and details.atlasName
            or ""
        if not npc or not (R.Known(npc) or atlas:find("Kill")) then
            return
        end
        if R.Known(npc) and not R.Mine(npc) then
            return
        end
        local known = R.Known(npc)
        local map = C_Map.GetBestMapForUnit("player")
        local place = map
            and C_VignetteInfo.GetVignettePosition
            and C_VignetteInfo.GetVignettePosition(ident, map)
        local posX, posY
        if place and not Secret(place) then
            posX, posY = place:GetXY()
        end
        Alert(npc, {
            name = details.name or (known and R.Name(npc)) or "Rare",
            level = known and R.Levels(npc) or nil,
            npc = npc,
            map = posX and map or nil,
            x = posX and posX * 100,
            y = posY and posY * 100,
        })
    end

    alertEvents:SetScript("OnEvent", function(_, evt, unitToken, onMinimap)
        if evt == "UNIT_FLAGS" then
            if not shownGuid then
                return
            end
            local unitGuid = UnitGUID(unitToken)
            if Secret(unitGuid) or unitGuid ~= shownGuid then
                return
            end
            local dead = UnitIsDead(unitToken)
            if not Secret(dead) and not dead then
                Retap(unitToken)
            end
        elseif evt == "NAME_PLATE_UNIT_ADDED" then
            Check(unitToken)
        elseif evt == "PLAYER_TARGET_CHANGED" then
            Check("target")
        elseif evt == "UPDATE_MOUSEOVER_UNIT" then
            Check("mouseover")
        elseif evt == "VIGNETTE_MINIMAP_UPDATED" then
            if onMinimap and not Secret(unitToken) then
                CheckVignette(unitToken)
            end
        end
    end)

    R.OnChange(function(npc)
        if shownNpc and npc == shownNpc and R.Killed(npc) then
            HideAlert()
        end
    end)

    function RareAlert.Apply()
        alertEvents:UnregisterAllEvents()
        if not (On() and Get("rareAlert")) then
            return HideAlert()
        end
        alertEvents:RegisterEvent("NAME_PLATE_UNIT_ADDED")
        alertEvents:RegisterEvent("PLAYER_TARGET_CHANGED")
        alertEvents:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
        if C_VignetteInfo and C_VignetteInfo.GetVignetteInfo then
            alertEvents:RegisterEvent("VIGNETTE_MINIMAP_UPDATED")
        end
        if shownNpc then
            alertEvents:RegisterEvent("UNIT_FLAGS")
        end
    end

    function RareAlert.Test()
        local unitGuid = UnitGUID("target")
        if unitGuid and not Secret(unitGuid) and UnitExists("target") then
            Show({
                name = UnitName("target"),
                level = UnitLevel("target"),
                npc = R.NpcOf(unitGuid),
                guid = unitGuid,
                unit = "target",
            })
        else
            Show({ name = "Mist Howler", level = 22, npc = 10644 })
        end
    end

    function RareAlert.Preview(enabled)
        if enabled then
            Show({ name = "Mist Howler", level = 22, npc = 10644 }, true)
        elseif cardFrame and cardFrame.preview then
            HideAlert()
        end
    end
end

-------------------------------------------------------------------------------
--  Map pins: a ! at each giver with a quest for you, a star at each rare
-------------------------------------------------------------------------------
local provider, layer, waiter
local added = false
local pins, pinsUsed = {}, 0

local function PinsWanted()
    return On() and (Get("questPins") or Get("rarePins"))
end

local function Anchor(p)
    local canvas = layer:GetParent()
    local wid, hgt = canvas:GetSize()
    local cs = canvas:GetScale()
    p:SetScale(1 / cs)
    p:ClearAllPoints()
    p:SetPoint("CENTER", canvas, "TOPLEFT", p.x * wid * cs, -p.y * hgt * cs)
end

local function ClearPins()
    for index = 1, pinsUsed do
        pins[index]:Hide()
    end
    pinsUsed = 0
end

local function NewPin()
    local p = CreateFrame("Button", nil, layer)
    p:RegisterForClicks("LeftButtonUp")
    p.icon = p:CreateTexture(nil, "ARTWORK")
    p.icon:SetAllPoints()
    p:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        self.tip(GameTooltip)
        GameTooltip:AddLine("Click to link its map pin in chat.", unpack(MUTED))
        GameTooltip:Show()
    end)
    p:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    p:SetScript("OnClick", function(self)
        if self.onClick then
            self.onClick()
        end
    end)
    if not InCombatLockdown() then
        p:SetPassThroughButtons("RightButton")
    end
    return p
end

local function Pin(posX, posY, size, tipText, onClick)
    pinsUsed = pinsUsed + 1
    local p = pins[pinsUsed] or NewPin()
    pins[pinsUsed] = p
    p:SetSize(size, size)
    p.x, p.y = posX / 100, posY / 100
    p.icon:SetVertexColor(1, 1, 1)
    p.icon:SetDesaturated(false)
    p.tip, p.onClick = tipText, onClick
    Anchor(p)
    p:Show()
    return p
end

local STATE_WORDS = {
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

local function StateText(ident, status)
    local words = STATE_WORDS[status] or status
    if status == "low" then
        words = words:format(Q.RequiredLevel(ident))
    end
    return words
end

local function QuestTip(ident)
    return function(tipText)
        local color = GetQuestDifficultyColor(Q.Level(ident))
        tipText:SetText(Q.Name(ident), color.r, color.g, color.b)
        local bits = { ("Level %d"):format(Q.Level(ident)) }
        if Q.Dungeon(ident) then
            bits[#bits + 1] = Q.Battleground(ident) and "Battleground" or "Dungeon"
        end
        if Q.Repeatable(ident) then
            bits[#bits + 1] = "Repeatable"
        end
        tipText:AddLine(table.concat(bits, ", "), unpack(MUTED))
        if Q.Giver(ident) then
            tipText:AddLine(Q.Giver(ident), 1, 1, 1)
        end
        local status = Q.State(ident)
        tipText:AddLine(StateText(ident, status), unpack(status == "open" and GOLD or MUTED))
        if status == "later" then
            for _, before in ipairs(Q.Blocking(ident)) do
                tipText:AddLine("Requires: " .. (Q.Title(before) or ("quest " .. before)), 1, 0.5, 0.5, true)
            end
        end
        local step, steps = Q.ChainStep(ident)
        if step then
            tipText:AddLine(("Step %d of %d of %s"):format(step, steps, Q.Chain(ident).name), unpack(ACCENT))
        end
    end
end

local function RareTip(npc)
    return function(tipText)
        tipText:SetText(R.Name(npc) .. (R.Elite(npc) and " |cffffb040Elite|r" or ""), 1, 1, 1)
        tipText:AddLine("Level " .. R.LevelText(npc), unpack(MUTED))
        local record = R.Record(npc)
        if record then
            tipText:AddLine(
                record.n > 1 and ("Killed %d times"):format(record.n) or "Killed",
                0.38,
                0.85,
                0.5
            )
        end
        R.AddLoot(tipText, npc)
    end
end

local function DrawPins()
    CludesUI.Kit.SyncAccent(ACCENT)
    ClearPins()
    if not PinsWanted() then
        return
    end
    local mapID = WorldMapFrame:GetMapID()
    if not mapID then
        return
    end
    local size = Get("pinSize")
    if Get("questPins") then
        Q.Refresh()
        for _, giver in ipairs(Q.Givers(mapID, Get("pinGrey"), Get("chainsOnly"))) do
            local quests = giver.quests
            local p = Pin(giver.x, giver.y, size * 0.8, function(tipText)
                for index, ident in ipairs(quests) do
                    if index > 1 then
                        tipText:AddLine(" ")
                    end
                    if index == 1 then
                        QuestTip(ident)(tipText)
                    else
                        local color = GetQuestDifficultyColor(Q.Level(ident))
                        tipText:AddLine(
                            Q.Name(ident) .. Muted(("  (%d)"):format(Q.Level(ident))),
                            color.r,
                            color.g,
                            color.b
                        )
                    end
                end
            end, function()
                Q.Link(quests[1])
            end)
            local atlas = giver.repeatable and "QuestDaily" or giver.grey and "TrivialQuests" or "QuestNormal"
            if not (C_Texture.GetAtlasInfo(atlas) and p.icon:SetAtlas(atlas)) then
                p.icon:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
            end
            if giver.dungeon and not giver.repeatable then
                p.icon:SetVertexColor(0.4, 1, 0.4)
            end
        end
    end
    if Get("rarePins") then
        for _, npc in ipairs(R.OnMap(mapID)) do
            if Get("rarePinsKilled") or not R.Killed(npc) then
                local spots = R.Spots(npc)
                local p = Pin(spots[1], spots[2], size, RareTip(npc), function()
                    R.Link(npc)
                end)
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

local function RescalePins()
    for index = 1, pinsUsed do
        Anchor(pins[index])
    end
end

local function PinsApply()
    if not PinsWanted() then
        if added then
            WorldMapFrame:RemoveDataProvider(provider)
            added = false
        end
        if layer then
            ClearPins()
        end
        return
    end
    if not provider then
        if not C_AddOns.IsAddOnLoaded("Blizzard_WorldMap") then
            if not waiter then
                waiter = CreateFrame("Frame")
                waiter:SetScript("OnEvent", function(self, _, name)
                    if name ~= "Blizzard_WorldMap" then
                        return
                    end
                    self:UnregisterEvent("ADDON_LOADED")
                    PinsApply()
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
        provider.OnMapChanged = DrawPins
        provider.RefreshAllData = DrawPins
        provider.RemoveAllData = ClearPins
        provider.OnCanvasScaleChanged = RescalePins
    end
    if not added then
        WorldMapFrame:AddDataProvider(provider)
        added = true
    end
    if WorldMapFrame:IsShown() then
        DrawPins()
    end
end

-------------------------------------------------------------------------------
--  The Quest List and Rares tabs
-------------------------------------------------------------------------------
local questZone, rareZone, questSearch, rareSearch = nil, nil, "", ""
local tools = {}
local STATE_COLOUR = { done = MUTED, log = GOLD, open = { 1, 1, 1 }, low = { 1, 0.5, 0.25 } }

local function ZoneMenu(ownerFrame, zones, progress, choose)
    CludesUI.Kit.ContextMenu(ownerFrame, function(_, root)
        root:CreateButton("Your zone", function()
            choose(nil)
        end)
        root:CreateButton("All zones", function()
            choose(false)
        end)
        for _, part in ipairs({ { 0, "Eastern Kingdoms" }, { 1, "Kalimdor" } }) do
            local continent, labelText = part[1], part[2]
            local sub = root:CreateButton(labelText)
            for _, zone in ipairs(zones) do
                if zone.continent == continent then
                    local num, sum = progress(zone)
                    sub:CreateButton(("%s  %d/%d"):format(zone.name, num, sum), function()
                        choose(zone)
                    end)
                end
            end
        end
        local other = root:CreateButton("Other")
        for _, zone in ipairs(zones) do
            if zone.continent ~= 0 and zone.continent ~= 1 then
                local num, sum = progress(zone)
                other:CreateButton(("%s  %d/%d"):format(zone.name, num, sum), function()
                    choose(zone)
                end)
            end
        end
    end)
end

local function Tools(hostFrame, key, onZone, onSearch, getSearch, extra)
    local t = tools[key]
    if not t then
        t = {}
        t.zone = CludesUI.Kit.Button(hostFrame, "", 90, 22, nil, { key = "essentials" })
        t.zone:SetSize(200, 22)
        t.zone:SetPoint("LEFT", hostFrame, "LEFT", 0, 0)
        t.zone:SetScript("OnClick", function(self)
            onZone(self)
        end)
        t.search = CludesUI.Kit.Input(hostFrame, 160, 22, "Search", "essentials")
        t.search:SetPoint("LEFT", t.zone, "RIGHT", 10, 0)
        t.search:HookScript("OnTextChanged", function(self, user)
            if user then
                onSearch(self:GetText())
            end
        end)
        t.check = CludesUI.Kit.Check(hostFrame, "", function(self)
            extra.set(self:GetChecked())
        end, "essentials")
        t.check:SetPoint("LEFT", t.search, "RIGHT", 12, 0)
        tools[key] = t
    end
    t.zone:Show()
    t.search:Show()
    t.check:Show()
    t.check:SetLabel(extra.label)
    t.check:SetChecked(extra.get())
    return t
end

local function QuestRow(R2, ident, indent)
    local status = Q.State(ident)
    local color = GetQuestDifficultyColor(Q.Level(ident))
    local name = ("|cff%02x%02x%02x[%d]|r %s"):format(
        color.r * 255,
        color.g * 255,
        color.b * 255,
        Q.Level(ident),
        Q.Name(ident)
    )
    if status == "done" then
        name = CHECK .. " " .. Muted(("[%d] %s"):format(Q.Level(ident), Q.Name(ident)))
    end
    local sub
    if status == "later" then
        local nameList = {}
        for index, before in ipairs(Q.Blocking(ident)) do
            if index > 3 then
                nameList[#nameList + 1] = "..."
                break
            end
            nameList[#nameList + 1] = Q.Title(before) or ("quest " .. before)
        end
        sub = "Requires: " .. table.concat(nameList, ", ")
    elseif Q.Giver(ident) and status ~= "done" then
        sub = Q.Giver(ident)
    end
    R2:Line(name .. (sub and ("\n" .. Muted(sub)) or ""), {
        indent = indent,
        right = status ~= "done" and StateText(ident, status) or nil,
        rightColour = STATE_COLOUR[status] or MUTED,
        tip = QuestTip(ident),
        onClick = function()
            Q.Link(ident)
        end,
    })
end

local function DrawQuestZone(R2, zone)
    local num, sum, low, high = Q.ZoneProgress(zone)
    R2:Line(
        ("%s  %s"):format(
            zone.name,
            Muted(("%d of %d done%s"):format(num, sum, low and ("  levels %d-%d"):format(low, high) or ""))
        ),
        { size = 15, colour = ACCENT }
    )
    local chains, singles = Q.ZoneLists(zone)
    local hide = Get("hideDone")
    if #chains > 0 then
        R2:Gap(4)
        R2:Line("Chains", { size = 13, colour = GOLD })
        for _, chain in ipairs(chains) do
            local at, steps = Q.ChainAt(chain)
            if not (hide and at > steps) then
                R2:Line(
                    ("%s  %s"):format(
                        chain.name,
                        Muted(at > steps and "done" or ("step %d of %d"):format(at, steps))
                    ),
                    { indent = 4, colour = at > steps and MUTED or { 1, 1, 1 } }
                )
                for index, step in ipairs(chain.steps) do
                    if not (hide and Q.StepDone(step)) and (index >= at - 1 or not hide) then
                        for _, ident in ipairs(step) do
                            QuestRow(R2, ident, 18)
                        end
                    end
                end
            end
        end
    end
    local isShown = false
    for _, ident in ipairs(singles) do
        local status = Q.State(ident)
        if not (hide and status == "done") then
            if not isShown then
                R2:Gap(4)
                R2:Line("Quests", { size = 13, colour = GOLD })
                isShown = true
            end
            QuestRow(R2, ident, 4)
        end
    end
end

local function DrawQuests(R2, hostFrame)
    CludesUI.Kit.SyncAccent(ACCENT)
    Q.Refresh()
    local t = Tools(hostFrame, "quests", function(self)
        ZoneMenu(self, Q.Zones(), Q.ZoneProgress, function(zone)
            questZone = zone
            module.DiscoveryRedraw()
        end)
    end, function(textValue)
        questSearch = textValue
        module.DiscoveryRedraw()
    end, function()
        return questSearch
    end, {
        label = "Hide done",
        get = function()
            return Get("hideDone")
        end,
        set = function(val)
            F.Cfg().hideDone = val and true or false
            module.DiscoveryRedraw()
        end,
    })
    local num, sum = Q.Progress()
    local search = questSearch:lower()
    if #search >= 2 then
        t.zone:SetText("Search results")
        local found, count = Q.Search(search, 200)
        R2:Line(("%d quests match"):format(count), { colour = MUTED })
        for _, entry in ipairs(found) do
            R2:Gap(4)
            R2:Line(entry.zone.name, { size = 13, colour = GOLD })
            for _, ident in ipairs(entry.ids) do
                QuestRow(R2, ident, 4)
            end
        end
        return
    end
    if questZone == false then
        t.zone:SetText("All zones")
        R2:Line(
            ("Quest List  %s"):format(Muted(("%d of %d done"):format(num, sum))),
            { size = 16, colour = ACCENT }
        )
        for _, zone in ipairs(Q.Zones()) do
            local zn, zt, low, high = Q.ZoneProgress(zone)
            if zt > 0 then
                R2:Line(zone.name, {
                    right = ("%d / %d%s"):format(zn, zt, low and ("   %d-%d"):format(low, high) or ""),
                    rightColour = zn == zt and { 0.38, 0.85, 0.5 } or MUTED,
                    onClick = function()
                        questZone = zone
                        module.DiscoveryRedraw()
                    end,
                })
            end
        end
        return
    end
    local zone = questZone or Q.CurrentZone()
    if not zone then
        t.zone:SetText("Pick a zone")
        R2:Line("This place has no quests in the list. Pick a zone above.", { colour = MUTED })
        return
    end
    t.zone:SetText(zone.name)
    DrawQuestZone(R2, zone)
end

local function RareRow(R2, npc)
    local killed = R.Killed(npc)
    local name = (killed and (CHECK .. " ") or "")
        .. R.Name(npc)
        .. (R.Elite(npc) and " |cffffb040Elite|r" or "")
    R2:Line(killed and Muted(name) or name, {
        indent = 4,
        right = "Level " .. R.LevelText(npc),
        tip = RareTip(npc),
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

local function DrawRares(R2, hostFrame)
    CludesUI.Kit.SyncAccent(ACCENT)
    local t = Tools(hostFrame, "rares", function(self)
        ZoneMenu(self, R.Zones(), R.ZoneProgress, function(zone)
            rareZone = zone
            module.DiscoveryRedraw()
        end)
    end, function(textValue)
        rareSearch = textValue
        module.DiscoveryRedraw()
    end, function()
        return rareSearch
    end, {
        label = "Hide killed",
        get = function()
            return Get("rareHideKilled")
        end,
        set = function(val)
            F.Cfg().rareHideKilled = val and true or false
            module.DiscoveryRedraw()
        end,
    })
    local search = rareSearch:lower()
    local hide = Get("rareHideKilled")
    if #search >= 2 then
        t.zone:SetText("Search results")
        local found, count = R.Search(search, 200)
        R2:Line(("%d rares match"):format(count), { colour = MUTED })
        for _, entry in ipairs(found) do
            R2:Gap(4)
            R2:Line(entry.zone.name, { size = 13, colour = GOLD })
            for _, npc in ipairs(entry.ids) do
                RareRow(R2, npc)
            end
        end
        return
    end
    local num, sum = R.Progress()
    if rareZone == false then
        t.zone:SetText("All zones")
        R2:Line(
            ("Rares  %s"):format(Muted(("%d of %d killed"):format(num, sum))),
            { size = 16, colour = ACCENT }
        )
        for _, zone in ipairs(R.Zones()) do
            local zn, zt, low, high = R.ZoneProgress(zone)
            if zt > 0 then
                R2:Line(zone.name, {
                    right = ("%d / %d%s"):format(zn, zt, low and ("   %d-%d"):format(low, high) or ""),
                    onClick = function()
                        rareZone = zone
                        module.DiscoveryRedraw()
                    end,
                })
            end
        end
        return
    end
    local zone = rareZone or R.CurrentZone()
    if not zone then
        t.zone:SetText("Pick a zone")
        R2:Line("This place has no rares in the list. Pick a zone above.", { colour = MUTED })
        return
    end
    t.zone:SetText(zone.name)
    local zn, zt = R.ZoneProgress(zone)
    R2:Line(
        ("%s  %s"):format(zone.name, Muted(("%d of %d killed"):format(zn, zt))),
        { size = 15, colour = ACCENT }
    )
    R2:Line(
        "Kills count from when Discovery is on. Shift-click a rare you killed before to tick it off.",
        { colour = MUTED }
    )
    R2:Gap(4)
    for _, npc in ipairs(R.ZoneList(zone)) do
        if not (hide and R.Killed(npc)) then
            RareRow(R2, npc)
        end
    end
end

module.DiscoveryAddTab({ key = "quests", label = "Quest List", order = 40, draw = DrawQuests })
module.DiscoveryAddTab({ key = "rares", label = "Rares", order = 50, draw = DrawRares })

R.OnChange(function()
    module.DiscoveryRedraw()
end)

-------------------------------------------------------------------------------
--  Events and apply
-------------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function()
    if added and WorldMapFrame:IsShown() then
        DrawPins()
    end
    module.DiscoveryRedraw()
end)

function module.QuestListApply()
    giverEvents:UnregisterAllEvents()
    killEvents:UnregisterAllEvents()
    eventFrame:UnregisterAllEvents()
    if On() then
        for _, event in ipairs({ "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_TURNED_IN" }) do
            giverEvents:RegisterEvent(event)
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
            pcall(eventFrame.RegisterEvent, eventFrame, event)
        end
    end
    PinsApply()
    RareAlert.Apply()
end

CludesUI._QuestList = {
    Get = Get,
    Cfg = F.Cfg,
    Apply = function()
        module.QuestListApply()
    end,
    TestAlert = RareAlert.Test,
}

F.Start(function() end, {
    key = "CUI_RareAlert",
    label = "Rare Alert",
    order = 757,
    shown = function()
        return On() and Get("rareAlert")
    end,
    frame = function(build)
        local cardFrame = RareAlert.Frame(build)
        if build and CludesUI._unlockActive then
            RareAlert.Preview(true)
        end
        return cardFrame
    end,
    size = function()
        return 260, 64
    end,
    noAnchorTarget = true,
    noSizeMatchTarget = true,
})
