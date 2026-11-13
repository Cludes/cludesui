if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if not (CludesUI and CludesUI.IS_FOREVER) then return end
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
    hideDone = false, questPins = true, pinGrey = false, chainsOnly = false, pinSize = 20,
    rarePins = true, rarePinsKilled = false, rareHideKilled = false,
    rareAlert = true, rareAlertKilled = false, rareAlertSkull = false, rareSound = true, rareAlertTime = 20,
}, { point = "CENTER", relPoint = "CENTER", x = 0, y = 260 })
local Get = F.Get
local function On() return DF.Enabled() end

local ACCENT = CludesUI.Kit.SyncAccent({})  -- refreshed on each draw
local MUTED = { 0.6, 0.65, 0.7 }
local GOLD = { 1, 0.82, 0 }
local CHECK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:0|t"
local NONE = {}
local function Muted(text) return "|cff9aa6b2" .. text .. "|r" end
local function Secret(v) return issecretvalue ~= nil and issecretvalue(v) end
local function Font() return CludesUI.GetFontPath("essentials") end
local SAME_MAPS = { [2665] = 2521 }
local function SameMap(map) return map and (SAME_MAPS[map] or map) end

local QD, RD
local function QuestData()
    if not QD then QD = module.QuestData(); module.QuestData = nil end
    return QD
end
local function RareData()
    if not RD then RD = module.RareData(); module.RareData = nil end
    return RD
end

local function CharKey() return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?") end
local function CharStore(key)
    local cfg = F.Cfg()
    cfg[key] = cfg[key] or {}
    local char = CharKey()
    cfg[key][char] = cfg[key][char] or {}
    return cfg[key][char]
end

local Link = module.DiscoveryLink
local ZoneName = module.DiscoveryZoneName

-------------------------------------------------------------------------------
--  Quest rules
-------------------------------------------------------------------------------
local Q = {}
do
    local NAME, LEVEL, REQ_LEVEL, SIDE, RACES, CLASSES, MAP, X, Y, GIVER, ITEM = 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
    local ALLIANCE, HORDE = 1, 2
    local RACE_BITS = { [1] = 0, [2] = 1, [3] = 2, [4] = 3, [5] = 4, [6] = 5, [7] = 6, [8] = 7, [95] = 32, [96] = 33 }
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

    local function HasBit(mask, bit) return math.floor(mask / 2 ^ bit) % 2 == 1 end

    local function ForMe(quest, side, raceBit, classBit)
        if quest[SIDE] == ALLIANCE and side ~= ALLIANCE then return false end
        if quest[SIDE] == HORDE and side ~= HORDE then return false end
        if quest[RACES] > 0 and raceBit and not HasBit(quest[RACES], raceBit) then return false end
        if quest[CLASSES] > 0 and classBit and not HasBit(quest[CLASSES], classBit) then return false end
        return true
    end

    local function OwnSteps(steps)
        local own = {}
        for _, step in ipairs(steps) do
            local ids = {}
            for _, id in ipairs(step) do
                if mine[id] then ids[#ids + 1] = id end
            end
            ids.any = step.any
            if #ids > 0 then own[#own + 1] = ids end
        end
        return own
    end

    local function AddChain(own)
        local first = D.Quests[own[1][1]]
        local chain = { steps = own, name = first[NAME], level = first[LEVEL], id = #chains + 1 }
        chains[#chains + 1] = chain
        for _, ids in ipairs(own) do
            for _, id in ipairs(ids) do chainOf[id] = chain end
        end
    end

    local function AddCloser(id, other)
        if not mine[id] then return end
        local list = closers[id]
        if not list then list = {}; closers[id] = list end
        list[#list + 1] = other
    end

    local function IndexClosers()
        closers, recipes, factions = {}, {}, {}
        needs, teaches, ranks, untils = D.Profession or NONE, D.Recipe or NONE, D.SkillRank or NONE, D.Until or NONE
        maxLevels, minReps, maxReps = D.MaxLevel or NONE, D.MinReputation or NONE, D.MaxReputation or NONE
        local groupOf = {}
        for _, group in ipairs(D.Exclusive or NONE) do
            for _, id in ipairs(group) do
                groupOf[id] = group
                for _, other in ipairs(group) do
                    if other ~= id then AddCloser(id, other) end
                end
            end
        end
        for id, target in pairs(D.Breadcrumb or NONE) do
            AddCloser(id, target)
            for _, other in ipairs(groupOf[target] or NONE) do
                if other ~= target then AddCloser(id, other) end
            end
        end
        for id, elements in pairs(D.Requires) do
            for _, element in ipairs(elements) do
                if type(element) == "table" then
                    for _, before in ipairs(element) do AddCloser(before, id) end
                else
                    AddCloser(element, id)
                end
            end
        end
        for id, others in pairs(D.ClosedBy or NONE) do
            for _, other in ipairs(others) do AddCloser(id, other) end
        end
        for _, spell in pairs(teaches) do recipes[spell] = true end
        for _, rep in pairs(minReps) do factions[rep[1]] = true end
        for _, rep in pairs(maxReps) do factions[rep[1]] = true end
    end

    local function Prepare()
        if mine then return end
        D = QuestData()
        mine, zoneOf, chains, chainOf = {}, {}, {}, {}
        local side = UnitFactionGroup("player") == "Horde" and HORDE or ALLIANCE
        local raceBit = RACE_BITS[select(3, UnitRace("player"))]
        local classID = select(3, UnitClass("player"))
        local classBit = classID and classID - 1
        for id, quest in pairs(D.Quests) do
            if ForMe(quest, side, raceBit, classBit) then mine[id] = true end
        end
        for id in pairs(CharStore("mine")) do
            if D.Quests[id] then mine[id] = true end
        end
        for _, zone in ipairs(D.Zones) do
            for _, id in ipairs(zone.quests) do zoneOf[id] = zone end
        end
        for _, steps in ipairs(D.Chains) do
            local own = OwnSteps(steps)
            if #own > 1 then AddChain(own) end
        end
        IndexClosers()
    end
    Q.Prepare = Prepare

    local function AddSkills(...)
        for i = 1, select("#", ...) do
            local index = select(i, ...)
            if index then
                local rank, _, _, _, line = select(3, GetProfessionInfo(index))
                if line then skills[line] = rank end
            end
        end
    end

    local function ReadKnown()
        wipe(skills)
        AddSkills(GetProfessions())
        wipe(known)
        for spell in pairs(recipes) do known[spell] = C_SpellBook.IsSpellKnown(spell) end
        wipe(standings)
        for faction in pairs(factions) do
            local data = C_Reputation.GetFactionDataByID(faction)
            standings[faction] = data and data.currentStanding
        end
        wipe(logged)
        for i = 1, C_QuestLog.GetNumQuestLogEntries() do
            local id = C_QuestLog.GetQuestIDForLogIndex(i)
            if id then logged[id] = true end
        end
    end

    local function Outgrown(id)
        local level, rep = maxLevels[id], maxReps[id]
        if level and UnitLevel("player") > level then return true end
        local standing = rep and standings[rep[1]]
        return standing ~= nil and standing >= rep[2]
    end

    local function ShortOfReputation(id)
        local rep = minReps[id]
        local standing = rep and standings[rep[1]]
        return standing ~= nil and standing < rep[2]
    end

    local function Closed(id)
        local state
        local skill = needs[id]
        if skill and (skills[skill] or 0) < (ranks[id] or 1) then
            state = "skill"
        elseif known[teaches[id]] or done[untils[id]] or Outgrown(id) then
            state = "closed"
        else
            local list = closers[id] or NONE
            for i = 1, #list do
                if done[list[i]] or logged[list[i]] then
                    state = "closed"
                    break
                end
            end
        end
        if not state and ShortOfReputation(id) then state = "rep" end
        if state and not reopened[id] then return state end
    end

    local function ZoneTurnIns(id)
        local zone = zoneOf and zoneOf[id]
        return zone and CharStore("turnIns")[zone.map] or 0
    end

    local function QuestLevel(id) return D.Quests[id][LEVEL] end

    local function SortKey(entry)
        if type(entry) == "table" then return entry.level, entry.name end
        local quest = D.Quests[entry]
        return quest[LEVEL], quest[NAME]
    end

    local function ByLevel(a, b)
        local la, na = SortKey(a)
        local lb, nb = SortKey(b)
        if la ~= lb then return la < lb end
        return na < nb
    end

    local function FoundKey(id)
        local chain = chainOf[id]
        if not chain then return QuestLevel(id), 0, 0 end
        return chain.level, chain.id, (Q.ChainStep(id))
    end

    local function FoundOrder(a, b)
        local la, ca, sa = FoundKey(a)
        local lb, cb, sb = FoundKey(b)
        if la ~= lb then return la < lb end
        if ca ~= cb then return ca < cb end
        if sa ~= sb then return sa < sb end
        return D.Quests[a][NAME] < D.Quests[b][NAME]
    end

    local function Matches(quest, text)
        if quest[NAME]:lower():find(text, 1, true) then return true end
        return quest[GIVER] ~= nil and quest[GIVER]:lower():find(text, 1, true) ~= nil
    end

    local function Index()
        if byMap then return end
        byMap = {}
        for id, quest in pairs(D.Quests) do
            local map = quest[MAP]
            if map and mine[id] then
                byMap[map] = byMap[map] or {}
                table.insert(byMap[map], id)
            end
        end
    end

    local function RecycleGivers()
        for i = #givers, 1, -1 do
            local entry = givers[i]
            wipe(entry.quests)
            spare[#spare + 1] = entry
            givers[i] = nil
        end
        wipe(giverAt)
    end

    local function GiverEntry(quest)
        local key = quest[X] .. ":" .. quest[Y]
        local entry = giverAt[key]
        if entry then return entry end
        entry = table.remove(spare) or { quests = {} }
        entry.x, entry.y, entry.grey, entry.repeatable, entry.dungeon = quest[X], quest[Y], true, true, false
        giverAt[key] = entry
        givers[#givers + 1] = entry
        return entry
    end

    local function AddToLists(id)
        local chain = chainOf[id]
        if not chain then
            zoneSingles[#zoneSingles + 1] = id
            return
        end
        if seenChain[chain] then return end
        seenChain[chain] = true
        zoneChains[#zoneChains + 1] = chain
    end

    local function Wanted(id, chainsOnly)
        return Q.Available(id) and (chainOf[id] ~= nil or not chainsOnly or Q.Dungeon(id))
    end

    local function AddToGiver(id, trivial)
        local entry = GiverEntry(D.Quests[id])
        table.insert(entry.quests, id)
        if not trivial then entry.grey = false end
        if not Q.Repeatable(id) then entry.repeatable = false end
        if Q.Dungeon(id) and not Q.Battleground(id) then entry.dungeon = true end
    end

    function Q.Refresh()
        Prepare()
        opened, reopened = CharStore("opened"), CharStore("reopened")
        ReadKnown()
        wipe(done)
        local all = C_QuestLog.GetAllCompletedQuestIDs and C_QuestLog.GetAllCompletedQuestIDs()
        if all then
            for i = 1, #all do done[all[i]] = true end
            return
        end
        for id in pairs(mine) do
            if C_QuestLog.IsQuestFlaggedCompleted(id) then done[id] = true end
        end
    end

    function Q.Done(id) return done[id] == true end
    function Q.InLog(id) return C_QuestLog.GetLogIndexForQuestID(id) ~= nil end
    function Q.Mine(id) return mine[id] == true end
    function Q.Name(id) return D.Quests[id][NAME] end
    function Q.Level(id) return QuestLevel(id) end

    function Q.SetMine(ids)
        Prepare()
        local store
        for id in pairs(ids) do
            if not mine[id] and D.Quests[id] then
                store = store or CharStore("mine")
                store[id] = true
            end
        end
        if not store then return end
        mine, byMap = nil, nil
        Prepare()
    end

    function Q.RequiredLevel(id)
        local quest = D.Quests[id]
        return math.max(quest[REQ_LEVEL], quest[LEVEL] - MAX_UNDER)
    end

    function Q.Zone(id) return zoneOf[id] end
    function Q.Chain(id) return chainOf[id] end
    function Q.Zones() Prepare(); return D.Zones end
    function Q.Giver(id) return D.Quests[id][GIVER] end
    function Q.Item(id) return D.Quests[id][ITEM] end
    function Q.Repeatable(id) return D.Repeatable ~= nil and D.Repeatable[id] == true end
    function Q.Dungeon(id) return D.Dungeon ~= nil and D.Dungeon[id] == true end
    function Q.Battleground(id) return D.Battleground ~= nil and D.Battleground[id] == true end
    function Q.Elsewhere(id) return D.Elsewhere ~= nil and D.Elsewhere[id] == true end

    function Q.Spot(id)
        local quest = D.Quests[id]
        if quest[MAP] then return quest[MAP], quest[X], quest[Y] end
    end

    function Q.StepDone(step)
        for _, id in ipairs(step) do
            if done[id] and step.any then return true end
            if not done[id] and not step.any then return false end
        end
        return not step.any
    end

    function Q.ChainAt(chain)
        local steps = chain.steps
        for i = #steps, 1, -1 do
            if Q.StepDone(steps[i]) then return i + 1, #steps end
        end
        return 1, #steps
    end

    function Q.NotOffered(id)
        local entry = CharStore("notOffered")[id]
        if not entry then return false end
        if (entry[3] or 1) >= MISSES_HELD then return true end
        return entry[1] == UnitLevel("player") and entry[2] == ZoneTurnIns(id)
    end

    function Q.SetOffered(id, offered)
        local store = CharStore("notOffered")
        local entry, level = store[id], UnitLevel("player")
        if offered then
            store[id] = nil
        elseif not entry then
            store[id] = { level, ZoneTurnIns(id), 1 }
        else
            if entry[1] ~= level then entry[3] = (entry[3] or 1) + 1 end
            entry[1], entry[2] = level, ZoneTurnIns(id)
        end
    end

    function Q.CountTurnIn(id)
        Prepare()
        local zone = zoneOf[id]
        if not zone then return end
        local turnIns = CharStore("turnIns")
        turnIns[zone.map] = (turnIns[zone.map] or 0) + 1
    end

    function Q.State(id)
        local state = Q.Expected(id)
        if state == "open" and Q.NotOffered(id) then return "held" end
        return state
    end

    local function Counts(id) return mine[id] or not D.Quests[id] end

    local function Met(element)
        if type(element) == "number" then return done[element] or not Counts(element) end
        local counted = false
        for _, id in ipairs(element) do
            if done[id] then return true end
            if Counts(id) then counted = true end
        end
        return not counted
    end

    function Q.Opened(id)
        for _, element in ipairs(D.Requires[id] or NONE) do
            if not Met(element) then return opened[id] == true end
        end
        return true
    end

    function Q.SetOpened(id) CharStore("opened")[id] = true end
    function Q.SetReopened(id) CharStore("reopened")[id] = true end

    function Q.Blocking(id)
        wipe(blocking)
        for _, element in ipairs(D.Requires[id] or NONE) do
            if not Met(element) then
                local first = element
                if type(element) == "table" then
                    for _, other in ipairs(element) do
                        if Counts(other) then first = other break end
                    end
                end
                blocking[#blocking + 1] = first
            end
        end
        return blocking
    end

    function Q.Title(id)
        local quest = D.Quests[id]
        return quest and quest[NAME] or C_QuestLog.GetTitleForQuestID(id)
    end

    function Q.Expected(id)
        if done[id] then return "done" end
        if Q.InLog(id) then return "log" end
        local closed = Closed(id)
        if closed then return closed end
        if not Q.Opened(id) then return "later" end
        if UnitLevel("player") < Q.RequiredLevel(id) then return "low" end
        return "open"
    end

    function Q.ZoneProgress(zone)
        local n, total, low, high = 0, 0, nil, nil
        for _, id in ipairs(zone.quests) do
            if mine[id] and not Q.Repeatable(id) and not Q.Dungeon(id) and not Q.Elsewhere(id)
                and (done[id] or not Closed(id) or Q.InLog(id)) then
                total = total + 1
                if done[id] then n = n + 1 end
                local level = QuestLevel(id)
                if level > 0 then
                    low = math.min(low or level, level)
                    high = math.max(high or level, level)
                end
            end
        end
        return n, total, low, high
    end

    function Q.Progress()
        local n, total = 0, 0
        for _, zone in ipairs(D.Zones) do
            local zn, zt = Q.ZoneProgress(zone)
            n, total = n + zn, total + zt
        end
        return n, total
    end

    function Q.ZoneLists(zone)
        wipe(zoneChains)
        wipe(zoneSingles)
        wipe(seenChain)
        for _, id in ipairs(zone.quests) do
            if mine[id] then AddToLists(id) end
        end
        table.sort(zoneChains, ByLevel)
        table.sort(zoneSingles, ByLevel)
        return zoneChains, zoneSingles
    end

    function Q.ChainStep(id)
        local chain = chainOf[id]
        if not chain then return end
        for i, step in ipairs(chain.steps) do
            for _, other in ipairs(step) do
                if other == id then return i, #chain.steps end
            end
        end
    end

    function Q.Search(text, limit)
        Prepare()
        wipe(found)
        local n = 0
        for _, zone in ipairs(D.Zones) do
            local entry = foundIn[zone] or { zone = zone, ids = {} }
            foundIn[zone] = entry
            local ids = wipe(entry.ids)
            for _, id in ipairs(zone.quests) do
                if mine[id] and Matches(D.Quests[id], text) then
                    n = n + 1
                    if n <= limit then ids[#ids + 1] = id end
                end
            end
            if #ids > 0 then
                table.sort(ids, FoundOrder)
                found[#found + 1] = entry
            end
        end
        return found, n
    end

    function Q.CurrentZone()
        Prepare()
        local map = SameMap(C_Map.GetBestMapForUnit("player"))
        while map do
            for _, zone in ipairs(D.Zones) do
                if zone.map == map then return zone end
            end
            local info = C_Map.GetMapInfo(map)
            map = info and info.parentMapID ~= 0 and info.parentMapID or nil
        end
    end

    function Q.Link(id)
        local map, x, y = Q.Spot(id)
        if map then Link(Q.Name(id), map, x, y, Q.Giver(id) and ("(" .. Q.Giver(id) .. ")")) end
    end

    function Q.Trivial(id)
        local level = QuestLevel(id)
        if level <= 0 then return false end
        if QuestDifficultyColors and QuestDifficultyColors.trivial then
            return GetQuestDifficultyColor(level) == QuestDifficultyColors.trivial
        end
        local green = GetQuestGreenRange and GetQuestGreenRange() or CLASSIC_GREEN_RANGE
        return level < UnitLevel("player") - green
    end

    function Q.Available(id) return mine[id] == true and Q.State(id) == "open" end

    function Q.GiverQuests(name, mapID)
        if Secret(name) then return NONE end
        Prepare()
        Index()
        wipe(named)
        for _, id in ipairs(byMap[mapID] or NONE) do
            if D.Quests[id][GIVER] == name then named[#named + 1] = id end
        end
        return named
    end

    function Q.Givers(mapID, grey, chainsOnly)
        Prepare()
        Index()
        RecycleGivers()
        for _, id in ipairs(byMap[SameMap(mapID)] or NONE) do
            if Wanted(id, chainsOnly) then
                local trivial = Q.Trivial(id)
                if grey or not trivial then AddToGiver(id, trivial) end
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

    local function ReadableGUID(unit)
        local guid = UnitGUID(unit)
        if not Secret(guid) then return guid end
    end

    local function Learn(unit)
        if not UnitExists(unit) or UnitIsPlayer(unit) then return end
        local zone = Q.CurrentZone()
        if not zone then return end
        Q.Refresh()
        Q.SetMine(offered)
        local trivial = C_Minimap and C_Minimap.IsFilteredOut and Enum.MinimapTrackingFilter
            and not C_Minimap.IsFilteredOut(Enum.MinimapTrackingFilter.TrivialQuests)
        for _, id in ipairs(Q.GiverQuests(UnitName(unit), zone.map)) do
            if offered[id] and CLOSED[Q.Expected(id)] then Q.SetReopened(id) end
            if offered[id] and Q.Expected(id) == "later" then Q.SetOpened(id) end
            if Q.Expected(id) == "open" and (trivial or not Q.Trivial(id)) then
                Q.SetOffered(id, offered[id] == true)
            end
        end
    end

    giverEvents:SetScript("OnEvent", function(_, event, questID)
        if event == "GOSSIP_SHOW" then
            wipe(offered)
            for _, quest in ipairs(C_GossipInfo.GetAvailableQuests() or NONE) do
                if quest.questID then offered[quest.questID] = true end
            end
            listed = ReadableGUID("npc")
            Learn("npc")
        elseif event == "QUEST_GREETING" then
            wipe(offered)
            wipe(titles)
            for i = 1, GetNumAvailableQuests() do
                local id = GetAvailableQuestInfo and select(5, GetAvailableQuestInfo(i))
                if id then offered[id] = true else titles[GetAvailableTitle(i) or ""] = true end
            end
            if next(titles) then
                local zone = Q.CurrentZone()
                if zone then
                    for _, id in ipairs(Q.GiverQuests(UnitName("npc"), zone.map)) do
                        if titles[Q.Name(id)] then offered[id] = true end
                    end
                end
            end
            listed = ReadableGUID("npc")
            Learn("npc")
        elseif event == "QUEST_DETAIL" then
            local guid = ReadableGUID("questnpc")
            if not guid or guid == listed then return end
            wipe(offered)
            offered[GetQuestID()] = true
            Learn("questnpc")
        elseif event == "QUEST_TURNED_IN" then
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
    local list, found, foundIn, lowered = {}, {}, {}, {}

    local function Prepare()
        if mine then return end
        D = RareData()
        mine = {}
        local react = UnitFactionGroup("player") == "Horde" and REACT_H or REACT_A
        for npc, rare in pairs(D.Rares) do
            if rare[react] ~= 1 then mine[npc] = true end
        end
    end
    R.Prepare = Prepare

    local function Kills() return CharStore("rareKills") end
    local function Drops() return CharStore("rareDrops") end
    local function Changed(npc) for _, fn in ipairs(listeners) do fn(npc) end end

    local function ZoneFor(map)
        for _, zone in ipairs(D.Zones) do
            if zone.map == map then return zone end
        end
    end

    local function Nearest(points, px, py, bx, by, bestD)
        for i = 1, #points, 2 do
            local dx, dy = points[i] / 100 - px, points[i + 1] / 100 - py
            local d = dx * dx + dy * dy
            if not bestD or d < bestD then bx, by, bestD = points[i], points[i + 1], d end
        end
        return bx, by, bestD
    end

    function R.NpcOf(guid)
        if type(guid) ~= "string" or Secret(guid) then return end
        local kind, _, _, _, _, id = strsplit("-", guid)
        if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
    end

    function R.Known(npc) Prepare(); return D.Rares[npc] ~= nil end
    function R.Name(npc) return D.Rares[npc][NAME] end
    function R.Elite(npc) return D.Rares[npc][ELITE] == 1 end
    function R.Map(npc) return D.Rares[npc][MAP] end
    function R.Levels(npc) local rare = D.Rares[npc]; return rare[LOW], rare[HIGH] end
    function R.LevelText(npc)
        local low, high = R.Levels(npc)
        if low <= 0 then return "??" end
        if low == high then return tostring(low) end
        return ("%d-%d"):format(low, high)
    end
    function R.Mine(npc) Prepare(); return mine[npc] == true end
    function R.OnChange(fn) listeners[#listeners + 1] = fn end
    function R.Killed(npc) return Kills()[npc] ~= nil end
    function R.Record(npc) return Kills()[npc] end

    function R.AddKill(npc, guid)
        local all = Kills()
        local record = all[npc] or { n = 0 }
        record.n = record.n + 1
        record.at = time()
        record.guid = guid
        all[npc] = record
        Changed(npc)
    end

    function R.SetKilled(npc, killed)
        local all = Kills()
        all[npc] = killed and (all[npc] or { n = 0, at = time() }) or nil
        Changed(npc)
    end

    function R.Dropped(npc, itemID)
        local items = Drops()[npc]
        return items ~= nil and items[itemID] ~= nil
    end

    function R.AddDrop(npc, itemID)
        local all = Drops()
        all[npc] = all[npc] or {}
        if all[npc][itemID] then return end
        all[npc][itemID] = time()
        Changed(npc)
    end

    function R.ZoneProgress(zone)
        Prepare()
        local all = Kills()
        local n, total, low, high = 0, 0, nil, nil
        for _, npc in ipairs(zone.rares) do
            if mine[npc] then
                total = total + 1
                if all[npc] then n = n + 1 end
                local lo, hi = R.Levels(npc)
                if lo > 0 then
                    low = math.min(low or lo, lo)
                    high = math.max(high or hi, hi)
                end
            end
        end
        return n, total, low, high
    end

    function R.Progress()
        Prepare()
        local n, total = 0, 0
        for _, zone in ipairs(D.Zones) do
            local zn, zt = R.ZoneProgress(zone)
            n, total = n + zn, total + zt
        end
        return n, total
    end

    function R.Zones() Prepare(); return D.Zones end

    function R.ZoneList(zone)
        Prepare()
        wipe(list)
        for _, npc in ipairs(zone.rares) do
            if mine[npc] then list[#list + 1] = npc end
        end
        return list
    end

    function R.CurrentZone()
        Prepare()
        local map = SameMap(C_Map.GetBestMapForUnit("player"))
        while map do
            local zone = ZoneFor(map)
            if zone then return zone end
            local info = C_Map.GetMapInfo(map)
            map = info and info.parentMapID ~= 0 and info.parentMapID or nil
        end
    end

    function R.Search(text, limit)
        Prepare()
        wipe(found)
        local n = 0
        for _, zone in ipairs(D.Zones) do
            local entry = foundIn[zone] or { zone = zone, ids = {} }
            foundIn[zone] = entry
            local ids = wipe(entry.ids)
            for _, npc in ipairs(zone.rares) do
                local name = lowered[npc]
                if not name then name = D.Rares[npc][NAME]:lower(); lowered[npc] = name end
                if mine[npc] and name:find(text, 1, true) then
                    n = n + 1
                    if n <= limit then ids[#ids + 1] = npc end
                end
            end
            if #ids > 0 then found[#found + 1] = entry end
        end
        return found, n
    end

    function R.Spot(npc)
        local rare = D.Rares[npc]
        local spots = rare[SPOTS]
        if #spots == 0 then return end
        local pos = SameMap(C_Map.GetBestMapForUnit("player")) == rare[MAP] and C_Map.GetPlayerMapPosition(rare[MAP], "player")
        if not pos or Secret(pos) then return rare[MAP], spots[1], spots[2] end
        local px, py = pos:GetXY()
        local bx, by, bestD = Nearest(spots, px, py, spots[1], spots[2], nil)
        if rare[TRAIL] then bx, by = Nearest(rare[TRAIL], px, py, bx, by, bestD) end
        return rare[MAP], bx, by
    end

    function R.Spots(npc) return D.Rares[npc][SPOTS] end
    function R.Loot(npc) return D.Loot and D.Loot[npc] end

    function R.AddLoot(tip, npc)
        local loot = R.Loot(npc)
        if not loot then return end
        tip:AddLine(" ")
        tip:AddLine("Drops", unpack(GOLD))
        for _, item in ipairs(loot) do
            local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[item[LOOT_QUALITY]] or { r = 1, g = 1, b = 1 }
            local icon = C_Item.GetItemIconByID(item[LOOT_ID])
            local name = (icon and ("|T%s:14:14|t "):format(icon) or "") .. item[LOOT_NAME]
                .. (item[LOOT_NEW] == 1 and " " .. CludesUI.Kit.AccentHex() .. "(new in Forever)|r" or "")
                .. (R.Dropped(npc, item[LOOT_ID]) and " |cff60d080(you got it)|r" or "")
            local chance = item[LOOT_CHANCE]
            tip:AddDoubleLine(name, chance >= 1 and ("%d%%"):format(math.floor(chance + 0.5)) or ("%.1f%%"):format(chance),
                c.r, c.g, c.b, unpack(MUTED))
        end
        if loot.more then tip:AddLine(("And %d more"):format(loot.more), unpack(MUTED)) end
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
        local map, x, y = R.Spot(npc)
        if map then Link(R.Name(npc), map, x, y) end
    end

    -- Kills: a rare you targeted dying while yours, or a corpse you loot.
    local counted = {}
    local watching

    local function Count(guid)
        local npc = R.NpcOf(guid)
        if not npc or not R.Known(npc) or counted[guid] then return end
        counted[guid] = true
        local record = R.Record(npc)
        if record and record.guid == guid then return end
        R.AddKill(npc, guid)
    end

    local function StopWatching()
        watching = nil
        killEvents:UnregisterEvent("UNIT_HEALTH")
    end

    killEvents:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_TARGET_CHANGED" then
            StopWatching()
            local guid = UnitGUID("target")
            local npc = R.NpcOf(guid)
            if not npc or not R.Known(npc) or counted[guid] then return end
            local dead, denied = UnitIsDead("target"), UnitIsTapDenied("target")
            if Secret(dead) or Secret(denied) then return end
            if dead then
                if not denied then Count(guid) end
                return
            end
            watching = guid
            killEvents:RegisterUnitEvent("UNIT_HEALTH", "target")
        elseif event == "UNIT_HEALTH" then
            local guid = UnitGUID("target")
            if Secret(guid) or guid ~= watching then return end
            local dead, denied = UnitIsDead("target"), UnitIsTapDenied("target")
            if Secret(dead) or Secret(denied) or not dead then return end
            if not denied then Count(guid) end
            StopWatching()
        elseif event == "LOOT_READY" then
            for slot = 1, GetNumLootItems() do
                local link = GetLootSlotLink(slot)
                local itemID = type(link) == "string" and not Secret(link) and tonumber(link:match("item:(%d+)")) or nil
                local sources = { GetLootSourceInfo(slot) }
                for i = 1, #sources, 2 do
                    local guid = sources[i]
                    if not Secret(guid) then
                        Count(guid)
                        local npc = R.NpcOf(guid)
                        if itemID and npc and R.Known(npc) then R.AddDrop(npc, itemID) end
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
    local card, target
    local shownNpc, shownGuid
    local alerted = {}

    local function HideTarget()
        if target and target:IsShown() and not InCombatLockdown() then target:Hide() end
    end

    local function HideAlert()
        if not card then return end
        HideTarget()
        card.fade:Stop()
        card:Hide()
        shownNpc, shownGuid = nil, nil
        alertEvents:UnregisterEvent("UNIT_FLAGS")
    end
    RareAlert.Hide = HideAlert

    local function BuildTarget()
        target = CreateFrame("Button", "CludesUIRareAlertTarget", UIParent, "SecureActionButtonTemplate")
        target:SetFrameStrata("DIALOG")
        target:RegisterForClicks("AnyUp", "AnyDown")
        target:SetAttribute("type1", "macro")
        target:SetScript("PostClick", function(_, button, down) if button == "RightButton" and not down then HideAlert() end end)
        target:SetScript("OnEnter", function()
            GameTooltip:SetOwner(card, "ANCHOR_TOP")
            GameTooltip:SetText(card.name:GetText() or "Rare", 1, 1, 1)
            GameTooltip:AddLine("Left-click to target it. Right-click to close it.", unpack(ACCENT))
            GameTooltip:Show()
        end)
        target:SetScript("OnLeave", function() GameTooltip:Hide(); HideTarget() end)
        target:SetScript("OnShow", function(self) self:RegisterEvent("PLAYER_REGEN_DISABLED") end)
        target:SetScript("OnHide", function(self) self:UnregisterEvent("PLAYER_REGEN_DISABLED") end)
        target:SetScript("OnEvent", target.Hide)
        target:Hide()
    end

    -- A secure button of its own over the card (never its child, so the card
    -- can still show and hide in combat), set and shown only out of combat.
    local function CoverCard()
        if InCombatLockdown() then return end
        local seen = card.seen
        local name = not card.preview and seen and seen.name and seen.name:gsub("%c", "") or nil
        local left = card:GetLeft()
        if not (name and left) then return HideTarget() end
        if not target then BuildTarget() end
        local scale = card:GetEffectiveScale() / UIParent:GetEffectiveScale()
        local macro = Get("rareAlertSkull") and ("/cleartarget\n/targetexact %s\n/tm !8") or "/targetexact %s"
        target:SetAttribute("macrotext1", macro:format(name))
        target:ClearAllPoints()
        target:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left * scale, card:GetBottom() * scale)
        target:SetSize(card:GetWidth() * scale, card:GetHeight() * scale)
        target:Show()
    end

    local function Build()
        card = CreateFrame("Button", "CludesUIRareAlert", UIParent)
        card:SetSize(W, H)
        card:SetFrameStrata("HIGH")
        card:SetClampedToScreen(true)
        CludesUI.Kit.Panel(card, 0.92)
        card:RegisterForClicks("RightButtonUp")
        card:SetScript("OnClick", function(_, button) if button == "RightButton" then HideAlert() end end)
        card:SetScript("OnEnter", function()
            CoverCard()
            GameTooltip:SetOwner(card, "ANCHOR_TOP")
            GameTooltip:SetText(card.name:GetText() or "Rare", 1, 1, 1)
            GameTooltip:AddLine("Right-click to close it.", unpack(ACCENT))
            GameTooltip:Show()
        end)
        card:SetScript("OnLeave", function()
            if target and target:IsShown() and target:IsMouseOver() then return end
            GameTooltip:Hide()
            HideTarget()
        end)
        card.model = CreateFrame("PlayerModel", nil, card)
        card.model:SetSize(H - 12, H - 12)
        card.model:SetPoint("LEFT", 6, 0)
        card.star = card:CreateTexture(nil, "ARTWORK")
        card.star:SetSize(32, 32)
        card.star:SetPoint("CENTER", card.model, "CENTER")
        card.star:SetAtlas("VignetteKill")
        card.name = card:CreateFontString(nil, "OVERLAY")
        CludesUI.Kit.Font(card.name, 14, "essentials")
        card.name:SetPoint("TOPLEFT", card.model, "TOPRIGHT", 8, -4)
        card.name:SetPoint("RIGHT", -8, 0)
        card.name:SetJustifyH("LEFT")
        card.name:SetWordWrap(false)
        card.detail = card:CreateFontString(nil, "OVERLAY")
        CludesUI.Kit.Font(card.detail, 11, "essentials")
        card.detail:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -4)
        card.detail:SetPoint("RIGHT", -8, 0)
        card.detail:SetJustifyH("LEFT")
        card.detail:SetTextColor(unpack(MUTED))
        card.fade = card:CreateAnimationGroup()
        local fadeIn = card.fade:CreateAnimation("Alpha")
        fadeIn:SetFromAlpha(0); fadeIn:SetToAlpha(1); fadeIn:SetDuration(0.3); fadeIn:SetOrder(1)
        card.fadeOut = card.fade:CreateAnimation("Alpha")
        card.fadeOut:SetFromAlpha(1); card.fadeOut:SetToAlpha(0); card.fadeOut:SetDuration(0.3); card.fadeOut:SetOrder(2)
        card.fade:SetScript("OnFinished", HideAlert)
        card:Hide()
    end
    RareAlert.Frame = function(build) if build and not card then Build() end return card end

    local function Paint(seen)
        local level = seen.level and (seen.level == -1 and "??" or tostring(seen.level)) or (seen.npc and R.Known(seen.npc) and R.LevelText(seen.npc)) or nil
        card.name:SetText((seen.name or "Rare") .. (seen.elite and " |cffffb040Elite|r" or ""))
        local bits = {}
        if level then bits[#bits + 1] = "Level " .. level end
        local record = seen.npc and R.Known(seen.npc) and R.Record(seen.npc)
        if record then bits[#bits + 1] = record.n > 1 and ("killed %d times"):format(record.n) or "killed before" end
        if seen.tapped then bits[#bits + 1] = "|cffff6060tapped by someone else|r" end
        if seen.map then bits[#bits + 1] = ("%s %.1f, %.1f"):format(ZoneName(seen.map), seen.x or 0, seen.y or 0) end
        card.detail:SetText(table.concat(bits, "  "))
    end

    local function Show(seen, quiet)
        if not card then Build() end
        if not CludesUI._unlockActive then F.Place(card) end
        shownNpc, shownGuid = not quiet and seen.npc or nil, not quiet and seen.guid or nil
        card.preview = quiet == true
        card.seen = seen
        card.model:ClearModel()
        local shown = false
        if seen.unit and UnitExists(seen.unit) then card.model:SetUnit(seen.unit); shown = true
        elseif seen.npc then card.model:SetCreature(seen.npc); shown = true end
        card.model:SetShown(shown)
        if shown then card.model:SetPortraitZoom(1) end
        card.star:SetShown(not shown)
        Paint(seen)
        card.fade:Stop()
        card:SetAlpha(1)
        card:Show()
        if target and target:IsShown() then CoverCard() end
        if not quiet then
            alertEvents:RegisterEvent("UNIT_FLAGS")
            card.fadeOut:SetStartDelay(Get("rareAlertTime"))
            card.fade:Play()
            if Get("rareSound") then PlaySoundFile(598196, "Master") end
            if FlashClientIcon then FlashClientIcon() end
        end
    end
    RareAlert.Show = Show

    local function Due(key, npc)
        if alerted[key] and GetTime() - alerted[key] < AGAIN_AFTER then return false end
        return not (npc and R.Known(npc) and R.Killed(npc) and not Get("rareAlertKilled"))
    end

    local function Alert(key, seen)
        if not Due(key, seen.npc) then return end
        alerted[key] = GetTime()
        Show(seen)
    end

    local function Retap(unit)
        local denied = UnitIsTapDenied(unit)
        if Secret(denied) or not card then return end
        local seen = card.seen
        if (seen.tapped == true) == (denied == true) then return end
        seen.tapped = denied or nil
        Paint(seen)
    end

    local function Check(unit)
        if not UnitExists(unit) then return end
        local kind = UnitClassification(unit)
        if Secret(kind) or not RARE[kind] then return end
        local guid = UnitGUID(unit)
        if Secret(guid) or not guid then return end
        local npc = R.NpcOf(guid)
        local dead, hostile = UnitIsDead(unit), UnitCanAttack("player", unit)
        if not npc or Secret(dead) or Secret(hostile) or dead or not hostile then return end
        if npc == shownNpc then
            shownGuid = shownGuid or guid
            if guid == shownGuid then Retap(unit) end
        end
        local name, level = UnitName(unit), UnitLevel(unit)
        if Secret(name) then return end
        if Secret(level) then level = nil end
        if not Due(npc, npc) then return end
        local denied = UnitIsTapDenied(unit)
        Alert(npc, { name = name, level = level, npc = npc, guid = guid, unit = unit, elite = kind == "rareelite",
            tapped = not Secret(denied) and denied or nil })
    end

    local function CheckVignette(id)
        local info = C_VignetteInfo.GetVignetteInfo(id)
        if not info or Secret(info.objectGUID) or Secret(info.name) then return end
        local npc = R.NpcOf(info.objectGUID)
        local atlas = type(info.atlasName) == "string" and not Secret(info.atlasName) and info.atlasName or ""
        if not npc or not (R.Known(npc) or atlas:find("Kill")) then return end
        if R.Known(npc) and not R.Mine(npc) then return end
        local known = R.Known(npc)
        local map = C_Map.GetBestMapForUnit("player")
        local pos = map and C_VignetteInfo.GetVignettePosition and C_VignetteInfo.GetVignettePosition(id, map)
        local x, y
        if pos and not Secret(pos) then x, y = pos:GetXY() end
        Alert(npc, { name = info.name or (known and R.Name(npc)) or "Rare", level = known and R.Levels(npc) or nil, npc = npc,
            map = x and map or nil, x = x and x * 100, y = y and y * 100 })
    end

    alertEvents:SetScript("OnEvent", function(_, event, unit, onMinimap)
        if event == "UNIT_FLAGS" then
            if not shownGuid then return end
            local guid = UnitGUID(unit)
            if Secret(guid) or guid ~= shownGuid then return end
            local dead = UnitIsDead(unit)
            if not Secret(dead) and not dead then Retap(unit) end
        elseif event == "NAME_PLATE_UNIT_ADDED" then
            Check(unit)
        elseif event == "PLAYER_TARGET_CHANGED" then
            Check("target")
        elseif event == "UPDATE_MOUSEOVER_UNIT" then
            Check("mouseover")
        elseif event == "VIGNETTE_MINIMAP_UPDATED" then
            if onMinimap and not Secret(unit) then CheckVignette(unit) end
        end
    end)

    R.OnChange(function(npc) if shownNpc and npc == shownNpc and R.Killed(npc) then HideAlert() end end)

    function RareAlert.Apply()
        alertEvents:UnregisterAllEvents()
        if not (On() and Get("rareAlert")) then return HideAlert() end
        alertEvents:RegisterEvent("NAME_PLATE_UNIT_ADDED")
        alertEvents:RegisterEvent("PLAYER_TARGET_CHANGED")
        alertEvents:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
        if C_VignetteInfo and C_VignetteInfo.GetVignetteInfo then alertEvents:RegisterEvent("VIGNETTE_MINIMAP_UPDATED") end
        if shownNpc then alertEvents:RegisterEvent("UNIT_FLAGS") end
    end

    function RareAlert.Test()
        local guid = UnitGUID("target")
        if guid and not Secret(guid) and UnitExists("target") then
            Show({ name = UnitName("target"), level = UnitLevel("target"), npc = R.NpcOf(guid), guid = guid, unit = "target" })
        else
            Show({ name = "Mist Howler", level = 22, npc = 10644 })
        end
    end

    function RareAlert.Preview(on)
        if on then Show({ name = "Mist Howler", level = 22, npc = 10644 }, true) elseif card and card.preview then HideAlert() end
    end
end

-------------------------------------------------------------------------------
--  Map pins: a ! at each giver with a quest for you, a star at each rare
-------------------------------------------------------------------------------
local provider, layer, waiter
local added = false
local pins, pinsUsed = {}, 0

local function PinsWanted() return On() and (Get("questPins") or Get("rarePins")) end

local function Anchor(p)
    local canvas = layer:GetParent()
    local w, h = canvas:GetSize()
    local cs = canvas:GetScale()
    p:SetScale(1 / cs)
    p:ClearAllPoints()
    p:SetPoint("CENTER", canvas, "TOPLEFT", p.x * w * cs, -p.y * h * cs)
end

local function ClearPins()
    for i = 1, pinsUsed do pins[i]:Hide() end
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
    p:SetScript("OnLeave", function() GameTooltip:Hide() end)
    p:SetScript("OnClick", function(self) if self.onClick then self.onClick() end end)
    if not InCombatLockdown() then p:SetPassThroughButtons("RightButton") end
    return p
end

local function Pin(x, y, size, tip, onClick)
    pinsUsed = pinsUsed + 1
    local p = pins[pinsUsed] or NewPin()
    pins[pinsUsed] = p
    p:SetSize(size, size)
    p.x, p.y = x / 100, y / 100
    p.icon:SetVertexColor(1, 1, 1)
    p.icon:SetDesaturated(false)
    p.tip, p.onClick = tip, onClick
    Anchor(p)
    p:Show()
    return p
end

local STATE_WORDS = {
    done = "Done", log = "In your quest log", open = "Open", low = "Needs level %d", later = "Needs an earlier quest",
    closed = "Not offered any more", skill = "Needs a profession", rep = "Needs reputation", held = "Not offered yet",
}

local function StateText(id, state)
    local words = STATE_WORDS[state] or state
    if state == "low" then words = words:format(Q.RequiredLevel(id)) end
    return words
end

local function QuestTip(id)
    return function(tip)
        local c = GetQuestDifficultyColor(Q.Level(id))
        tip:SetText(Q.Name(id), c.r, c.g, c.b)
        local bits = { ("Level %d"):format(Q.Level(id)) }
        if Q.Dungeon(id) then bits[#bits + 1] = Q.Battleground(id) and "Battleground" or "Dungeon" end
        if Q.Repeatable(id) then bits[#bits + 1] = "Repeatable" end
        tip:AddLine(table.concat(bits, ", "), unpack(MUTED))
        if Q.Giver(id) then tip:AddLine(Q.Giver(id), 1, 1, 1) end
        local state = Q.State(id)
        tip:AddLine(StateText(id, state), unpack(state == "open" and GOLD or MUTED))
        if state == "later" then
            for _, before in ipairs(Q.Blocking(id)) do tip:AddLine("Requires: " .. (Q.Title(before) or ("quest " .. before)), 1, 0.5, 0.5, true) end
        end
        local step, steps = Q.ChainStep(id)
        if step then tip:AddLine(("Step %d of %d of %s"):format(step, steps, Q.Chain(id).name), unpack(ACCENT)) end
    end
end

local function RareTip(npc)
    return function(tip)
        tip:SetText(R.Name(npc) .. (R.Elite(npc) and " |cffffb040Elite|r" or ""), 1, 1, 1)
        tip:AddLine("Level " .. R.LevelText(npc), unpack(MUTED))
        local record = R.Record(npc)
        if record then tip:AddLine(record.n > 1 and ("Killed %d times"):format(record.n) or "Killed", 0.38, 0.85, 0.5) end
        R.AddLoot(tip, npc)
    end
end

local function DrawPins()
    CludesUI.Kit.SyncAccent(ACCENT)
    ClearPins()
    if not PinsWanted() then return end
    local mapID = WorldMapFrame:GetMapID()
    if not mapID then return end
    local size = Get("pinSize")
    if Get("questPins") then
        Q.Refresh()
        for _, giver in ipairs(Q.Givers(mapID, Get("pinGrey"), Get("chainsOnly"))) do
            local quests = giver.quests
            local p = Pin(giver.x, giver.y, size * 0.8, function(tip)
                for i, id in ipairs(quests) do
                    if i > 1 then tip:AddLine(" ") end
                    if i == 1 then QuestTip(id)(tip) else
                        local c = GetQuestDifficultyColor(Q.Level(id))
                        tip:AddLine(Q.Name(id) .. Muted(("  (%d)"):format(Q.Level(id))), c.r, c.g, c.b)
                    end
                end
            end, function() Q.Link(quests[1]) end)
            local atlas = giver.repeatable and "QuestDaily" or giver.grey and "TrivialQuests" or "QuestNormal"
            if not (C_Texture.GetAtlasInfo(atlas) and p.icon:SetAtlas(atlas)) then
                p.icon:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
            end
            if giver.dungeon and not giver.repeatable then p.icon:SetVertexColor(0.4, 1, 0.4) end
        end
    end
    if Get("rarePins") then
        for _, npc in ipairs(R.OnMap(mapID)) do
            if Get("rarePinsKilled") or not R.Killed(npc) then
                local spots = R.Spots(npc)
                local p = Pin(spots[1], spots[2], size, RareTip(npc), function() R.Link(npc) end)
                if not (C_Texture.GetAtlasInfo("VignetteKill") and p.icon:SetAtlas("VignetteKill")) then
                    p.icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8")
                end
                if R.Killed(npc) then p.icon:SetDesaturated(true) else p.icon:SetDesaturated(false) end
            end
        end
    end
end

local function RescalePins() for i = 1, pinsUsed do Anchor(pins[i]) end end

local function PinsApply()
    if not PinsWanted() then
        if added then WorldMapFrame:RemoveDataProvider(provider); added = false end
        if layer then ClearPins() end
        return
    end
    if not provider then
        if not C_AddOns.IsAddOnLoaded("Blizzard_WorldMap") then
            if not waiter then
                waiter = CreateFrame("Frame")
                waiter:SetScript("OnEvent", function(self, _, name)
                    if name ~= "Blizzard_WorldMap" then return end
                    self:UnregisterEvent("ADDON_LOADED")
                    PinsApply()
                end)
            end
            waiter:RegisterEvent("ADDON_LOADED")
            return
        end
        layer = CreateFrame("Frame", nil, WorldMapFrame.ScrollContainer.Child)
        layer:SetAllPoints()
        layer:SetFrameLevel(WorldMapFrame:GetPinFrameLevelsManager():GetValidFrameLevel("PIN_FRAME_LEVEL_AREA_POI"))
        provider = CreateFromMixins(MapCanvasDataProviderMixin)
        provider.OnMapChanged = DrawPins
        provider.RefreshAllData = DrawPins
        provider.RemoveAllData = ClearPins
        provider.OnCanvasScaleChanged = RescalePins
    end
    if not added then WorldMapFrame:AddDataProvider(provider); added = true end
    if WorldMapFrame:IsShown() then DrawPins() end
end

-------------------------------------------------------------------------------
--  The Quest List and Rares tabs
-------------------------------------------------------------------------------
local questZone, rareZone, questSearch, rareSearch = nil, nil, "", ""
local tools = {}
local STATE_COLOUR = { done = MUTED, log = GOLD, open = { 1, 1, 1 }, low = { 1, 0.5, 0.25 } }

local function ZoneMenu(owner, zones, progress, choose)
    CludesUI.Kit.ContextMenu(owner, function(_, root)
        root:CreateButton("Your zone", function() choose(nil) end)
        root:CreateButton("All zones", function() choose(false) end)
        for _, part in ipairs({ { 0, "Eastern Kingdoms" }, { 1, "Kalimdor" } }) do
            local continent, label = part[1], part[2]
            local sub = root:CreateButton(label)
            for _, zone in ipairs(zones) do
                if zone.continent == continent then
                    local n, total = progress(zone)
                    sub:CreateButton(("%s  %d/%d"):format(zone.name, n, total), function() choose(zone) end)
                end
            end
        end
        local other = root:CreateButton("Other")
        for _, zone in ipairs(zones) do
            if zone.continent ~= 0 and zone.continent ~= 1 then
                local n, total = progress(zone)
                other:CreateButton(("%s  %d/%d"):format(zone.name, n, total), function() choose(zone) end)
            end
        end
    end)
end

local function Tools(parent, key, onZone, onSearch, getSearch, extra)
    local t = tools[key]
    if not t then
        t = {}
        t.zone = CludesUI.Kit.Button(parent, "", 90, 22, nil, { key = "essentials" })
        t.zone:SetSize(200, 22)
        t.zone:SetPoint("LEFT", parent, "LEFT", 0, 0)
        t.zone:SetScript("OnClick", function(self) onZone(self) end)
        t.search = CludesUI.Kit.Input(parent, 160, 22, "Search", "essentials")
        t.search:SetPoint("LEFT", t.zone, "RIGHT", 10, 0)
        t.search:HookScript("OnTextChanged", function(self, user) if user then onSearch(self:GetText()) end end)
        t.check = CludesUI.Kit.Check(parent, "", function(self) extra.set(self:GetChecked()) end, "essentials")
        t.check:SetPoint("LEFT", t.search, "RIGHT", 12, 0)
        tools[key] = t
    end
    t.zone:Show(); t.search:Show(); t.check:Show()
    t.check:SetLabel(extra.label)
    t.check:SetChecked(extra.get())
    return t
end

local function QuestRow(R2, id, indent)
    local state = Q.State(id)
    local c = GetQuestDifficultyColor(Q.Level(id))
    local name = ("|cff%02x%02x%02x[%d]|r %s"):format(c.r * 255, c.g * 255, c.b * 255, Q.Level(id), Q.Name(id))
    if state == "done" then name = CHECK .. " " .. Muted(("[%d] %s"):format(Q.Level(id), Q.Name(id))) end
    local sub
    if state == "later" then
        local names = {}
        for i, before in ipairs(Q.Blocking(id)) do
            if i > 3 then names[#names + 1] = "..." break end
            names[#names + 1] = Q.Title(before) or ("quest " .. before)
        end
        sub = "Requires: " .. table.concat(names, ", ")
    elseif Q.Giver(id) and state ~= "done" then
        sub = Q.Giver(id)
    end
    R2:Line(name .. (sub and ("\n" .. Muted(sub)) or ""), { indent = indent,
        right = state ~= "done" and StateText(id, state) or nil,
        rightColour = STATE_COLOUR[state] or MUTED, tip = QuestTip(id),
        onClick = function() Q.Link(id) end })
end

local function DrawQuestZone(R2, zone)
    local n, total, low, high = Q.ZoneProgress(zone)
    R2:Line(("%s  %s"):format(zone.name, Muted(("%d of %d done%s"):format(n, total, low and ("  levels %d-%d"):format(low, high) or ""))),
        { size = 15, colour = ACCENT })
    local chains, singles = Q.ZoneLists(zone)
    local hide = Get("hideDone")
    if #chains > 0 then
        R2:Gap(4)
        R2:Line("Chains", { size = 13, colour = GOLD })
        for _, chain in ipairs(chains) do
            local at, steps = Q.ChainAt(chain)
            if not (hide and at > steps) then
                R2:Line(("%s  %s"):format(chain.name, Muted(at > steps and "done" or ("step %d of %d"):format(at, steps))),
                    { indent = 4, colour = at > steps and MUTED or { 1, 1, 1 } })
                for i, step in ipairs(chain.steps) do
                    if not (hide and Q.StepDone(step)) and (i >= at - 1 or not hide) then
                        for _, id in ipairs(step) do QuestRow(R2, id, 18) end
                    end
                end
            end
        end
    end
    local shown = false
    for _, id in ipairs(singles) do
        local state = Q.State(id)
        if not (hide and state == "done") then
            if not shown then
                R2:Gap(4)
                R2:Line("Quests", { size = 13, colour = GOLD })
                shown = true
            end
            QuestRow(R2, id, 4)
        end
    end
end

local function DrawQuests(R2, parent)
    CludesUI.Kit.SyncAccent(ACCENT)
    Q.Refresh()
    local t = Tools(parent, "quests", function(self)
        ZoneMenu(self, Q.Zones(), Q.ZoneProgress, function(zone) questZone = zone; module.DiscoveryRedraw() end)
    end, function(text) questSearch = text; module.DiscoveryRedraw() end, function() return questSearch end,
        { label = "Hide done", get = function() return Get("hideDone") end,
          set = function(v) F.Cfg().hideDone = v and true or false; module.DiscoveryRedraw() end })
    local n, total = Q.Progress()
    local search = questSearch:lower()
    if #search >= 2 then
        t.zone:SetText("Search results")
        local found, count = Q.Search(search, 200)
        R2:Line(("%d quests match"):format(count), { colour = MUTED })
        for _, entry in ipairs(found) do
            R2:Gap(4)
            R2:Line(entry.zone.name, { size = 13, colour = GOLD })
            for _, id in ipairs(entry.ids) do QuestRow(R2, id, 4) end
        end
        return
    end
    if questZone == false then
        t.zone:SetText("All zones")
        R2:Line(("Quest List  %s"):format(Muted(("%d of %d done"):format(n, total))), { size = 16, colour = ACCENT })
        for _, zone in ipairs(Q.Zones()) do
            local zn, zt, low, high = Q.ZoneProgress(zone)
            if zt > 0 then
                R2:Line(zone.name, { right = ("%d / %d%s"):format(zn, zt, low and ("   %d-%d"):format(low, high) or ""),
                    rightColour = zn == zt and { 0.38, 0.85, 0.5 } or MUTED,
                    onClick = function() questZone = zone; module.DiscoveryRedraw() end })
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
    local name = (killed and (CHECK .. " ") or "") .. R.Name(npc) .. (R.Elite(npc) and " |cffffb040Elite|r" or "")
    R2:Line(killed and Muted(name) or name, { indent = 4, right = "Level " .. R.LevelText(npc), tip = RareTip(npc),
        onClick = function()
            if IsShiftKeyDown() then
                local record = R.Record(npc)
                if not record then R.SetKilled(npc, true) elseif record.n == 0 then R.SetKilled(npc, false) end
                module.DiscoveryRedraw()
            else
                R.Link(npc)
            end
        end })
end

local function DrawRares(R2, parent)
    CludesUI.Kit.SyncAccent(ACCENT)
    local t = Tools(parent, "rares", function(self)
        ZoneMenu(self, R.Zones(), R.ZoneProgress, function(zone) rareZone = zone; module.DiscoveryRedraw() end)
    end, function(text) rareSearch = text; module.DiscoveryRedraw() end, function() return rareSearch end,
        { label = "Hide killed", get = function() return Get("rareHideKilled") end,
          set = function(v) F.Cfg().rareHideKilled = v and true or false; module.DiscoveryRedraw() end })
    local search = rareSearch:lower()
    local hide = Get("rareHideKilled")
    if #search >= 2 then
        t.zone:SetText("Search results")
        local found, count = R.Search(search, 200)
        R2:Line(("%d rares match"):format(count), { colour = MUTED })
        for _, entry in ipairs(found) do
            R2:Gap(4)
            R2:Line(entry.zone.name, { size = 13, colour = GOLD })
            for _, npc in ipairs(entry.ids) do RareRow(R2, npc) end
        end
        return
    end
    local n, total = R.Progress()
    if rareZone == false then
        t.zone:SetText("All zones")
        R2:Line(("Rares  %s"):format(Muted(("%d of %d killed"):format(n, total))), { size = 16, colour = ACCENT })
        for _, zone in ipairs(R.Zones()) do
            local zn, zt, low, high = R.ZoneProgress(zone)
            if zt > 0 then
                R2:Line(zone.name, { right = ("%d / %d%s"):format(zn, zt, low and ("   %d-%d"):format(low, high) or ""),
                    onClick = function() rareZone = zone; module.DiscoveryRedraw() end })
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
    R2:Line(("%s  %s"):format(zone.name, Muted(("%d of %d killed"):format(zn, zt))), { size = 15, colour = ACCENT })
    R2:Line("Kills count from when Discovery is on. Shift-click a rare you killed before to tick it off.", { colour = MUTED })
    R2:Gap(4)
    for _, npc in ipairs(R.ZoneList(zone)) do
        if not (hide and R.Killed(npc)) then RareRow(R2, npc) end
    end
end

module.DiscoveryAddTab({ key = "quests", label = "Quest List", order = 40, draw = DrawQuests })
module.DiscoveryAddTab({ key = "rares", label = "Rares", order = 50, draw = DrawRares })

R.OnChange(function() module.DiscoveryRedraw() end)

-------------------------------------------------------------------------------
--  Events and apply
-------------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function()
    if added and WorldMapFrame:IsShown() then DrawPins() end
    module.DiscoveryRedraw()
end)

function module.QuestListApply()
    giverEvents:UnregisterAllEvents()
    killEvents:UnregisterAllEvents()
    ev:UnregisterAllEvents()
    if On() then
        for _, e in ipairs({ "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_TURNED_IN" }) do giverEvents:RegisterEvent(e) end
        killEvents:RegisterEvent("PLAYER_TARGET_CHANGED")
        killEvents:RegisterEvent("LOOT_READY")
        for _, e in ipairs({ "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED", "PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED" }) do
            pcall(ev.RegisterEvent, ev, e)
        end
    end
    PinsApply()
    RareAlert.Apply()
end

CludesUI._QuestList = { Get = Get, Cfg = F.Cfg, Apply = function() module.QuestListApply() end, TestAlert = RareAlert.Test }

F.Start(function() end, {
    key = "CUI_RareAlert", label = "Rare Alert", order = 757,
    shown = function() return On() and Get("rareAlert") end,
    frame = function(build)
        local card = RareAlert.Frame(build)
        if build and CludesUI._unlockActive then RareAlert.Preview(true) end
        return card
    end,
    size = function() return 260, 64 end,
    noAnchorTarget = true, noSizeMatchTarget = true,
})
