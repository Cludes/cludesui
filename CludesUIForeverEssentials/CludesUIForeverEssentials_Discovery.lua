if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if not (CludesUI and CludesUI.IS_FOREVER) then
    return
end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_Discovery.lua  (WoW Forever only)
--  Discovery (/cdiscovery): a window with
--    Library Books   every library book for your faction by tier, where it
--                    lies, whether you carry it or handed it in, and the road
--                    to the Friend of the Library rewards.
--    Sleeping Bag    the Cozy Sleeping Bag's hidden quest chain, step by step.
--    Field Journal   every fish, herb and dish: where to find it and how many
--                    this character caught, picked or cooked (counted while
--                    the journal is on; Shift-click ticks one off by hand).
--  Quest List and Rares (CludesUIForeverEssentials_QuestList.lua) add their
--  own tabs. A tracker lists the books in your zone and the bag's next step,
--  map pins mark both, and a ping warns you near a book you still need.
--  Clicking a place prints its map pin link in chat; click the link to pin it.
--  Places: CludesUIForeverEssentials_DiscoveryData.lua.
-------------------------------------------------------------------------------
local _, module = ...

local F = module.Feature("discovery", {
    enabled = false,
    tracker = true,
    bagTracker = true,
    mapPins = true,
    bagMapPins = true,
    mapTurnIn = true,
    pinSize = 20,
    nearby = true,
    nearbyRange = 40,
    nearbyPing = true,
    nearbyChat = true,
    fieldJournal = true,
}, { point = "RIGHT", relPoint = "RIGHT", x = -260, y = -120 })
local Get, On = F.Get, F.Enabled

local SPOT_MAP, SPOT_X, SPOT_Y, SPOT_PLACE, SPOT_NOTE = 1, 2, 3, 4, 5
local TURN_IN = "librarian"
local SLEEPING_BAG = 211527
local CHECK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:0|t"
local ACCENT = CludesUI.Kit.SyncAccent({}) -- refreshed on each draw
local MUTED = { 0.6, 0.65, 0.7 }
local GOLD = { 1, 0.82, 0 }
local READY = { 0.38, 0.85, 0.5 }
local function Font()
    return CludesUI.GetFontPath("essentials")
end
local function Print(message)
    CludesUI.Print("|cff4cc9f0Discovery:|r " .. message)
end
local function Muted(textValue)
    return "|cff9aa6b2" .. textValue .. "|r"
end

local D
local function Data()
    if not D then
        D = module.DiscoveryData()
        module.DiscoveryData = nil
    end
    return D
end

-- A map pin link in chat (as /way prints it); a click on it places the pin.
local function Link(title, map, posX, posY, note)
    if not (map and C_Map.CanSetUserWaypointOnMap(map)) then
        return Print("this place cannot take a map pin.")
    end
    local itemLink = ("|cffffff00|Hworldmap:%d:%d:%d|h[%s]|h|r"):format(
        map,
        math.floor(posX * 100 + 0.5),
        math.floor(posY * 100 + 0.5),
        MAP_PIN_HYPERLINK or "Map Pin"
    )
    local function Say()
        CludesUI.Print(
            "|cff4cc9f0Discovery:|r "
                .. itemLink
                .. " "
                .. title
                .. (note and (" " .. Muted(note)) or "")
                .. " "
                .. Muted(("%.1f, %.1f"):format(posX, posY))
        )
    end
    if InCombatLockdown() and CludesUI.CombatQueue then
        CludesUI.CombatQueue.Defer("DiscoveryLink", Say)
    else
        Say()
    end
end

local function ZoneName(mapID)
    local details = mapID and C_Map.GetMapInfo(mapID)
    return details and details.name or ("map " .. tostring(mapID))
end

local function PlayerZone()
    local ident = C_Map.GetBestMapForUnit("player")
    local details = ident and C_Map.GetMapInfo(ident)
    while
        details
        and details.mapType
        and details.mapType > Enum.UIMapType.Zone
        and details.parentMapID
        and details.parentMapID ~= 0
    do
        ident = details.parentMapID
        details = C_Map.GetMapInfo(ident)
    end
    return ident
end

local function Side()
    return UnitFactionGroup("player") == "Horde" and "H" or "A"
end
local function Done(quest)
    return C_QuestLog.IsQuestFlaggedCompleted(quest)
end

-------------------------------------------------------------------------------
--  Library books
-------------------------------------------------------------------------------
local Library = {}

function Library.ForMe(book)
    return not book.missing and (book.side == "B" or book.side == Side())
end
function Library.Done(book)
    return Done(book.quest)
end
function Library.Stored(book)
    if Library.Done(book) then
        return nil
    end
    if C_Item.GetItemCount(book.item) > 0 then
        return "bags"
    end
    if C_Item.GetItemCount(book.item, true) > 0 then
        return "bank"
    end
end
local function BookState(book)
    if Library.Done(book) then
        return "done"
    end
    if C_Item.GetItemCount(book.item, true) > 0 then
        return "carried"
    end
    return "find"
end
function Library.ToFind(book)
    return Library.ForMe(book) and BookState(book) == "find"
end
function Library.TurnIn(book)
    return Data().LibraryTurnIns[book.turnIn or TURN_IN][Side()]
end
function Library.Librarian()
    return Data().LibraryTurnIns[TURN_IN][Side()]
end

function Library.Spots(mapID, status)
    local result = {}
    if not mapID then
        return result
    end
    for _, book in ipairs(Data().LibraryBooks) do
        if Library.ForMe(book) and BookState(book) == status then
            for _, spot in ipairs(book.spots) do
                if spot[SPOT_MAP] == mapID then
                    result[#result + 1] = { book, spot }
                end
            end
        end
    end
    return result
end

function Library.Progress()
    local done, sum = 0, 0
    for _, book in ipairs(Data().LibraryBooks) do
        if book.turnIn == TURN_IN and Library.ForMe(book) then
            sum = sum + 1
            if Library.Done(book) then
                done = done + 1
            end
        end
    end
    return done, sum
end

function Library.NextGoal()
    for _, goal in ipairs(Data().LibraryGoals) do
        if not Done(goal.quest) then
            return goal
        end
    end
end

function Library.GoalState(goal, done)
    if Done(goal.quest) then
        return "claimed"
    end
    if done < goal.books then
        return "ahead"
    end
    if goal.level and UnitLevel("player") < goal.level then
        return "level"
    end
    return "ready"
end

function Library.Where(spot)
    local coords = ("(%.1f, %.1f)"):format(spot[SPOT_X], spot[SPOT_Y])
    return spot[SPOT_PLACE] and (spot[SPOT_PLACE] .. " " .. coords) or coords
end

function Library.LinkBook(book, spot)
    Link(
        book.name,
        spot[SPOT_MAP],
        spot[SPOT_X],
        spot[SPOT_Y],
        spot[SPOT_PLACE] and ("(" .. spot[SPOT_PLACE] .. ")")
    )
end

function Library.Title(book)
    if Library.Done(book) then
        return CHECK .. " " .. Muted(book.name)
    end
    local color = GetQuestDifficultyColor(book.tier)
    return ("|cff%02x%02x%02x(%d)|r %s"):format(color.r * 255, color.g * 255, color.b * 255, book.tier, book.name)
end

-------------------------------------------------------------------------------
--  The Cozy Sleeping Bag chain
-------------------------------------------------------------------------------
local Bag = {}

function Bag.Steps()
    return Data().SleepingBag.steps[Side()]
end
function Bag.StepDone(step)
    if step.started then
        return Done(step.started) or C_QuestLog.IsOnQuest(step.started)
    end
    return Done(step.done)
end
function Bag.Current()
    for index, step in ipairs(Bag.Steps()) do
        if not Bag.StepDone(step) then
            return step, index
        end
    end
end
function Bag.Owned()
    return C_Item.GetItemCount(SLEEPING_BAG, true) > 0
end
function Bag.Level()
    return UnitLevel("player") >= Data().SleepingBag.level
end
function Bag.Name(step)
    for _, other in ipairs(Bag.Steps()) do
        if other ~= step and other.object == step.object and other.map ~= step.map then
            return ("%s (%s)"):format(step.object, ZoneName(step.map))
        end
    end
    return step.object
end
function Bag.Where(step)
    return ("%s, %s (%.1f, %.1f)"):format(ZoneName(step.map), step.place, step.x, step.y)
end
function Bag.Link(step)
    Link(step.object, step.map, step.x, step.y, "(" .. step.place .. ")")
end

-------------------------------------------------------------------------------
--  Field Journal: counted per character
-------------------------------------------------------------------------------
local Field = {}
local PAGES = { "fish", "herbs", "dishes" }
local PAGE_NAMES = { fish = "Fish", herbs = "Herbs", dishes = "Cooking" }
local RANK_CAPS = { 75, 150, 225 }
local RANK_NAMES = { "Apprentice", "Journeyman", "Expert", "Artisan" }
local GUID_OBJECT = "^GameObject%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"
local lookup, fieldEvents
local lootPage, lootItem, lootQty = {}, {}, {}
local OnFieldChange

local function Plain(val)
    return not (issecretvalue and issecretvalue(val))
end

local function Lookup()
    if lookup then
        return lookup
    end
    local FJ = Data().FieldJournal
    lookup = { fish = {}, herbs = {}, dishes = {}, nodes = {} }
    for _, record in ipairs(FJ.fish) do
        lookup.fish[record.item] = record
    end
    for _, record in ipairs(FJ.herbs) do
        lookup.herbs[record.item] = record
        for _, node in ipairs(record.nodes) do
            lookup.nodes[node] = true
        end
    end
    for _, record in ipairs(FJ.dishes) do
        lookup.dishes[record.spell] = record
    end
    return lookup
end

local function FieldStore(create)
    local unitGuid = UnitGUID("player")
    if not unitGuid then
        return
    end
    local conf = create and F.Cfg() or F.Read()
    local all = conf.field
    if not all then
        if not create then
            return
        end
        all = {}
        conf.field = all
    end
    local mine = all[unitGuid]
    if not mine and create then
        mine = {}
        all[unitGuid] = mine
    end
    if mine and create then
        for _, page in ipairs(PAGES) do
            mine[page] = mine[page] or {}
        end
    end
    return mine
end

local function FieldAdd(page, ident, num)
    local mine = FieldStore(true)
    if not mine then
        return
    end
    mine[page][ident] = (mine[page][ident] or 0) + num
    if OnFieldChange then
        OnFieldChange(page)
    end
end

function Field.On()
    return On() and Get("fieldJournal")
end
function Field.Entries(page)
    return Data().FieldJournal[page]
end
function Field.Key(record)
    return record.spell or record.item
end
function Field.Count(page, record)
    local mine = FieldStore(false)
    local done = mine and mine[page]
    return done and done[Field.Key(record)]
end
function Field.SetHad(page, record, had)
    local mine = FieldStore(true)
    if not mine then
        return
    end
    local key = Field.Key(record)
    if had then
        mine[page][key] = mine[page][key] or 0
    elseif mine[page][key] == 0 then
        mine[page][key] = nil
    end
    if OnFieldChange then
        OnFieldChange(page)
    end
end
function Field.Progress(page)
    local mine = FieldStore(false)
    local had = mine and mine[page]
    local entries = Field.Entries(page)
    local done = 0
    if had then
        for _, record in ipairs(entries) do
            if had[Field.Key(record)] ~= nil then
                done = done + 1
            end
        end
    end
    return done, #entries
end
function Field.Rank(skill)
    if not skill then
        return nil
    end
    for index, cap in ipairs(RANK_CAPS) do
        if skill <= cap then
            return index
        end
    end
    return #RANK_CAPS + 1
end

local function FieldZones(record, withChance)
    local nameList = {}
    local zones = record.zones or {}
    local stride = withChance and 2 or 1
    for index = 1, #zones, stride do
        local name = ZoneName(zones[index])
        if withChance then
            name = ("%s %d%%"):format(name, math.max(1, math.floor(zones[index + 1] + 0.5)))
        end
        nameList[#nameList + 1] = name
    end
    return table.concat(nameList, ", ")
end

function Field.Source(record)
    return record[Side()] or record.B
end

function Field.Where(page, record)
    if page == "dishes" then
        local how, from = record.how, Field.Source(record)
        if how == "trainer" then
            return "Taught by cooking trainers"
        end
        if how == "world" then
            return "A world drop"
        end
        if how == "unknown" then
            return "Where to learn it is not known yet"
        end
        if not from then
            if how == "vendor" and not (record.A or record.H) then
                return "Sold by a vendor"
            end
            return "Only for the other faction"
        end
        if how == "vendor" then
            return ("Sold by %s, %s"):format(from[1], ZoneName(from[2]))
        end
        if how == "quest" then
            return ("From the quest %s"):format(from[1])
        end
        return ("Drops from %s"):format(from[1])
    end
    if page == "herbs" then
        return FieldZones(record, false)
    end
    if not record.zones then
        return "Caught from schools of fish"
    end
    local zones = FieldZones(record, true)
    return record.schools and (zones .. ", and from schools of fish") or zones
end

function Field.Link(record)
    local from = Field.Source(record)
    if from and from[2] then
        Link(from[5] or from[1], from[2], from[3], from[4])
    end
end

local function FromNode(unitGuid)
    if type(unitGuid) ~= "string" or not Plain(unitGuid) then
        return false
    end
    return Lookup().nodes[tonumber(unitGuid:match(GUID_OBJECT) or "")] == true
end

local function LootForget()
    wipe(lootPage)
    wipe(lootItem)
    wipe(lootQty)
end

local function LootOpened()
    LootForget()
    local fishing = IsFishingLoot()
    local known = Lookup()
    for slot = 1, GetNumLootItems() do
        local itemLink = GetLootSlotLink(slot)
        local entry = itemLink and Plain(itemLink) and C_Item.GetItemInfoInstant(itemLink) or nil
        local page
        if entry and fishing and known.fish[entry] then
            page = "fish"
        elseif entry and not fishing and known.herbs[entry] and FromNode(GetLootSourceInfo(slot)) then
            page = "herbs"
        end
        local _, _, quantity = GetLootSlotInfo(slot)
        if page and Plain(quantity) and quantity and quantity > 0 then
            lootPage[slot], lootItem[slot], lootQty[slot] = page, entry, quantity
        end
    end
end

local function FieldApply()
    if not Field.On() then
        if fieldEvents then
            fieldEvents:UnregisterAllEvents()
        end
        LootForget()
        return
    end
    if not fieldEvents then
        fieldEvents = CreateFrame("Frame")
        fieldEvents:SetScript("OnEvent", function(self, evt, a, _, spellId)
            if evt == "LOOT_OPENED" then
                LootOpened()
            elseif evt == "LOOT_SLOT_CLEARED" then
                local page = lootPage[a]
                if page then
                    lootPage[a] = nil
                    FieldAdd(page, lootItem[a], lootQty[a])
                end
            elseif evt == "LOOT_CLOSED" then
                LootForget()
            elseif evt == "TRADE_SKILL_SHOW" then
                self:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
            elseif evt == "TRADE_SKILL_CLOSE" then
                self:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
            elseif evt == "UNIT_SPELLCAST_SUCCEEDED" and Plain(spellId) and Lookup().dishes[spellId] then
                FieldAdd("dishes", spellId, 1)
            end
        end)
    end
    for _, event in ipairs({
        "LOOT_OPENED",
        "LOOT_SLOT_CLEARED",
        "LOOT_CLOSED",
        "TRADE_SKILL_SHOW",
        "TRADE_SKILL_CLOSE",
    }) do
        fieldEvents:RegisterEvent(event)
    end
end

-------------------------------------------------------------------------------
--  Nearby alert: a ping and a chat line within range of a book you need
-------------------------------------------------------------------------------
local nearTicker, nearZone, nearTargets
local nearEvents = CreateFrame("Frame")
local alerted = {}

local function WorldPos(mapID, posX, posY)
    local _, position = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(posX, posY))
    return position
end

local function NearCheck()
    if not (nearZone and nearTargets) then
        return
    end
    local here = C_Map.GetPlayerMapPosition(nearZone, "player")
    if not here or (issecretvalue and issecretvalue(here)) then
        return
    end
    local me = WorldPos(nearZone, here:GetXY())
    if not me then
        return
    end
    local range = Get("nearbyRange")
    local mx, my = me:GetXY()
    for _, target in ipairs(nearTargets) do
        local tx, ty = target[3]:GetXY()
        local dist = math.sqrt((tx - mx) ^ 2 + (ty - my) ^ 2)
        local quest = target[1].quest
        if dist <= range and not alerted[quest] then
            alerted[quest] = true
            if Get("nearbyPing") then
                PlaySound(SOUNDKIT.MAP_PING, "Master")
            end
            if Get("nearbyChat") then
                local place = target[2][SPOT_PLACE]
                Print(
                    ("library book nearby: %s, %d yards%s"):format(
                        target[1].name,
                        math.floor(dist),
                        place and (" - " .. place) or ""
                    )
                )
            end
        elseif dist > range * 1.5 then
            alerted[quest] = nil
        end
    end
end

local function NearStop()
    if nearTicker then
        nearTicker:Cancel()
        nearTicker = nil
    end
    nearZone, nearTargets = nil, nil
    nearEvents:UnregisterEvent("PLAYER_STARTED_MOVING")
    nearEvents:UnregisterEvent("PLAYER_STOPPED_MOVING")
end

local function NearRefresh()
    if not (On() and Get("nearby")) or IsInInstance() then
        return NearStop()
    end
    local ident = PlayerZone()
    local entries = {}
    for _, entry in ipairs(Library.Spots(ident, "find")) do
        local spot = entry[2]
        local position = WorldPos(ident, spot[SPOT_X] / 100, spot[SPOT_Y] / 100)
        if position then
            entries[#entries + 1] = { entry[1], spot, position }
        end
    end
    if #entries == 0 then
        return NearStop()
    end
    nearZone, nearTargets = ident, entries
    nearEvents:RegisterEvent("PLAYER_STARTED_MOVING")
    nearEvents:RegisterEvent("PLAYER_STOPPED_MOVING")
    NearCheck()
    if IsPlayerMoving() then
        nearTicker = nearTicker or C_Timer.NewTicker(1, NearCheck)
    elseif nearTicker then
        nearTicker:Cancel()
        nearTicker = nil
    end
end

nearEvents:SetScript("OnEvent", function(_, evt)
    if evt == "PLAYER_STARTED_MOVING" then
        nearTicker = nearTicker or C_Timer.NewTicker(1, NearCheck)
    elseif evt == "PLAYER_STOPPED_MOVING" then
        if nearTicker then
            nearTicker:Cancel()
            nearTicker = nil
        end
        NearCheck()
    else
        NearRefresh()
    end
end)

-------------------------------------------------------------------------------
--  Rows: the window and the tracker draw with the same pooled lines
-------------------------------------------------------------------------------
local function NewRows(contentFrame)
    local R = { content = contentFrame, pool = {}, used = 0, y = 0 }

    local function Acquire()
        R.used = R.used + 1
        local region = R.pool[R.used]
        if not region then
            region = CreateFrame("Button", nil, contentFrame)
            region:RegisterForClicks("AnyUp")
            region.icon = region:CreateTexture(nil, "ARTWORK")
            region.icon:SetSize(18, 18)
            region.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            region.text = region:CreateFontString(nil, "OVERLAY")
            region.text:SetJustifyH("LEFT")
            region.text:SetWordWrap(true)
            region.right = region:CreateFontString(nil, "OVERLAY")
            region.right:SetJustifyH("RIGHT")
            -- Fonts now: Acquire clears the right text before Line sizes it,
            -- and the client refuses text on a FontString without a font.
            CludesUI.Kit.Font(region.text, 12, "essentials")
            CludesUI.Kit.Font(region.right, 11, "essentials")
            region.hl = region:CreateTexture(nil, "HIGHLIGHT")
            region.hl:SetAllPoints()
            region.hl:SetColorTexture(1, 1, 1, 0.05)
            region:SetScript("OnEnter", function(self)
                if not self.tip then
                    return
                end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                self.tip(GameTooltip)
                GameTooltip:Show()
            end)
            region:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)
            region:SetScript("OnClick", function(self, btnFrame)
                if self.onClick then
                    self.onClick(btnFrame)
                end
            end)
            R.pool[R.used] = region
        end
        region.tip, region.onClick = nil, nil
        region:ClearAllPoints()
        region.icon:Hide()
        region.text:ClearAllPoints()
        region.right:SetText("")
        region:Show()
        return region
    end

    function R:Reset()
        for index = 1, self.used do
            self.pool[index]:Hide()
        end
        self.used, self.y = 0, 0
    end

    -- A line of text; opts: size, colour, indent, icon, right, onClick, tip.
    function R:Line(textValue, options)
        options = options or {}
        local region = Acquire()
        local width = contentFrame:GetWidth()
        local indent = options.indent or 0
        local size = options.size or 12
        CludesUI.Kit.Font(region.text, size, "essentials")
        region.text:SetTextColor(unpack(options.colour or { 1, 1, 1 }))
        local leftX = indent
        if options.icon then
            region.icon:SetTexture(options.icon)
            region.icon:ClearAllPoints()
            region.icon:SetPoint("TOPLEFT", region, "TOPLEFT", indent, -1)
            region.icon:Show()
            leftX = indent + 24
        end
        region.text:SetPoint("TOPLEFT", region, "TOPLEFT", leftX, -2)
        local rightW = 0
        if options.right then
            CludesUI.Kit.Font(region.right, 11, "essentials")
            region.right:SetTextColor(unpack(options.rightColour or MUTED))
            region.right:SetText(options.right)
            region.right:ClearAllPoints()
            region.right:SetPoint("TOPRIGHT", region, "TOPRIGHT", -4, -3)
            rightW = region.right:GetStringWidth() + 10
        end
        region.text:SetWidth(math.max(40, width - leftX - rightW - 6))
        region.text:SetText(textValue)
        local hgt = math.max(options.icon and 22 or 16, region.text:GetStringHeight() + 5)
        region:SetSize(width, hgt)
        region:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, -self.y)
        region.tip, region.onClick = options.tip, options.onClick
        region:EnableMouse(options.tip ~= nil or options.onClick ~= nil)
        self.y = self.y + hgt
        return region
    end

    function R:Gap(num)
        self.y = self.y + (num or 6)
    end
    function R:Height()
        return self.y
    end
    return R
end

-------------------------------------------------------------------------------
--  Window
-------------------------------------------------------------------------------
local WIN_W, WIN_H = 620, 540
local window, scroll, contentFrame, rowList
local tabs, tabButtons = {}, {}
local currentTab
local fieldPage = "fish"
local Redraw

local function TabOrder()
    local entries = {}
    for key, tab in pairs(tabs) do
        entries[#entries + 1] = tab
    end
    table.sort(entries, function(lhs, rhs)
        return lhs.order < rhs.order
    end)
    return entries
end

local function BuildWindow()
    window = CreateFrame("Frame", "CludesUIDiscovery", UIParent)
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
    local title = window:CreateFontString(nil, "OVERLAY")
    CludesUI.Kit.Font(title, 15, "essentials")
    title:SetPoint("TOPLEFT", 10, -8)
    title:SetText("Discovery")
    CludesUI.Kit.AccentText(title)
    local close = CludesUI.Kit.Glyph(window, "x", function()
        window:Hide()
    end, nil, "essentials")
    close:SetPoint("TOPRIGHT", -5, -5)
    window.tabBar = CreateFrame("Frame", nil, window)
    window.tabBar:SetPoint("TOPLEFT", 10, -32)
    window.tabBar:SetSize(WIN_W - 20, 22)
    window.tools = CreateFrame("Frame", nil, window)
    window.tools:SetPoint("TOPLEFT", 10, -58)
    window.tools:SetSize(WIN_W - 20, 24)
    scroll = (CludesUI.Kit.Scroll(window))
    scroll:SetPoint("TOPLEFT", 10, -86)
    scroll:SetPoint("BOTTOMRIGHT", -30, 10)
    contentFrame = CreateFrame("Frame", nil, scroll)
    contentFrame:SetSize(WIN_W - 44, 10)
    scroll:SetScrollChild(contentFrame)
    rowList = NewRows(contentFrame)
    window:Hide()
    tinsert(UISpecialFrames, "CludesUIDiscovery")
end

local function PaintTabs()
    local posX = 0
    for index, tab in ipairs(TabOrder()) do
        local b = tabButtons[index]
        if not b then
            b = CludesUI.Kit.Button(window.tabBar, "", 90, 22, nil, { key = "essentials" })
            b:SetHeight(22)
            tabButtons[index] = b
        end
        b:SetText(tab.label)
        b:SetWidth(math.max(80, b:GetTextWidth() + 24))
        b:ClearAllPoints()
        b:SetPoint("LEFT", window.tabBar, "LEFT", posX, 0)
        b:SetScript("OnClick", function()
            currentTab = tab.key
            Redraw()
        end)
        if tab.key == currentTab then
            b:SetActive(true)
        else
            b:SetActive(false)
        end
        b:Show()
        posX = posX + b:GetWidth() + 4
    end
end

function Redraw()
    if not (window and window:IsShown()) then
        return
    end
    CludesUI.Kit.SyncAccent(ACCENT)
    PaintTabs()
    rowList:Reset()
    for _, childFrame in ipairs({ window.tools:GetChildren() }) do
        childFrame:Hide()
    end
    local tab = tabs[currentTab] or TabOrder()[1]
    currentTab = tab.key
    tab.draw(rowList, window.tools)
    contentFrame:SetHeight(rowList:Height() + 10)
end

local redrawQueued
local function RedrawSoon()
    if redrawQueued or not (window and window:IsShown()) then
        return
    end
    redrawQueued = true
    C_Timer.After(0.2, function()
        redrawQueued = false
        Redraw()
    end)
end
OnFieldChange = RedrawSoon

local function OpenWindow(tab)
    if not window then
        BuildWindow()
    end
    if tab then
        currentTab = tab
    end
    window:Show()
    Redraw()
end

--- Other files add a tab: { key, label, order, draw = function(rows, tools) }.
function module.DiscoveryAddTab(tab)
    tabs[tab.key] = tab
end
module.DiscoveryRows = NewRows
module.DiscoveryRedraw = RedrawSoon
module.DiscoveryLink = Link
module.DiscoveryZoneName = ZoneName
module.DiscoveryPlayerZone = PlayerZone

-------------------------------------------------------------------------------
--  Library Books tab
-------------------------------------------------------------------------------
local function GoalLine(goal, done)
    local status = Library.GoalState(goal, done)
    local words, colour
    if status == "claimed" then
        words, colour = "Claimed", MUTED
    elseif status == "ready" then
        words, colour = "Ready to hand in", READY
    elseif status == "level" then
        words, colour = ("At level %d"):format(goal.level), GOLD
    else
        words, colour = ("%d to go"):format(goal.books - done), { 1, 1, 1 }
    end
    local nameList = {}
    for _, reward in ipairs(goal.rewards) do
        nameList[#nameList + 1] = C_Item.GetItemNameByID(reward[1]) or reward[2]
    end
    return ("%s (%d)"):format(goal.name, goal.books), words, colour, table.concat(nameList, " or ")
end

local function BookTip(book, spot)
    return function(tipText)
        tipText:SetText(book.name, 1, 1, 1)
        local color = GetQuestDifficultyColor(book.tier)
        tipText:AddLine(("Level %d"):format(book.tier), color.r, color.g, color.b)
        if spot then
            tipText:AddLine(ZoneName(spot[SPOT_MAP]) .. ", " .. Library.Where(spot), unpack(MUTED))
            if spot[SPOT_NOTE] then
                tipText:AddLine(spot[SPOT_NOTE], 1, 1, 1, true)
            end
        end
        local npc = Library.TurnIn(book)
        tipText:AddLine(
            ("Hand in to %s, %s"):format(npc.name, npc.place),
            ACCENT[1],
            ACCENT[2],
            ACCENT[3],
            true
        )
        if spot then
            tipText:AddLine("Click to link its map pin in chat.", unpack(MUTED))
        end
    end
end

local function DrawBooks(R)
    local done, sum = Library.Progress()
    R:Line(
        ("Library Books  %s"):format(Muted(("%d of %d handed in"):format(done, sum))),
        { size = 16, colour = ACCENT }
    )
    local librarian = Library.Librarian()
    R:Line(("Hand them in to %s, %s."):format(librarian.name, librarian.place), {
        colour = MUTED,
        onClick = function()
            Link(librarian.name, librarian.map, librarian.x, librarian.y)
        end,
    })
    R:Gap(4)
    for _, goal in ipairs(Data().LibraryGoals) do
        local name, words, colour, rewards = GoalLine(goal, done)
        R:Line(name, { size = 13, colour = GOLD, right = words, rightColour = colour })
        R:Line(rewards, { indent = 14, colour = MUTED })
    end
    local tiers, sequence = {}, {}
    for _, book in ipairs(Data().LibraryBooks) do
        if Library.ForMe(book) then
            if not tiers[book.tier] then
                tiers[book.tier] = {}
                sequence[#sequence + 1] = book.tier
            end
            table.insert(tiers[book.tier], book)
        end
    end
    table.sort(sequence)
    for _, tier in ipairs(sequence) do
        R:Gap(6)
        R:Line(("Level %d books"):format(tier), { size = 14, colour = GOLD })
        for _, book in ipairs(tiers[tier]) do
            local stored = Library.Stored(book)
            local right = Library.Done(book) and "handed in"
                or stored == "bags" and "in your bags"
                or stored == "bank" and "in your bank"
                or nil
            local spot = book.spots[1]
            local iconTex = C_Item.GetItemIconByID(book.item) or 134400
            local where = book.unplaced and "Not found on Forever yet"
                or spot and (ZoneName(spot[SPOT_MAP]) .. ", " .. Library.Where(spot))
                or ""
            R:Line(Library.Title(book) .. "\n" .. Muted(where), {
                icon = iconTex,
                right = right,
                rightColour = right == "handed in" and MUTED or GOLD,
                tip = BookTip(book, spot),
                onClick = spot and function()
                    Library.LinkBook(book, spot)
                end,
            })
            for index = 2, #book.spots do
                local other = book.spots[index]
                R:Line(Muted("or " .. ZoneName(other[SPOT_MAP]) .. ", " .. Library.Where(other)), {
                    indent = 24,
                    tip = BookTip(book, other),
                    onClick = function()
                        Library.LinkBook(book, other)
                    end,
                })
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Sleeping Bag tab
-------------------------------------------------------------------------------
local function DrawBag(R)
    local SB = Data().SleepingBag
    R:Line("Cozy Sleeping Bag", { size = 16, colour = ACCENT })
    local owned = Bag.Owned()
    local current = Bag.Current()
    R:Line(
        owned and "You have the Cozy Sleeping Bag."
            or (not Bag.Level() and ("The chain opens at level %d."):format(SB.level))
            or "A hidden chain of things to click across Azeroth. Click a step to link its map pin in chat.",
        { colour = MUTED }
    )
    R:Gap(4)
    for index, step in ipairs(Bag.Steps()) do
        local done = Bag.StepDone(step)
        local nowTime = step == current
        local name = (done and (CHECK .. " ") or (index .. ". ")) .. Bag.Name(step)
        R:Line(done and Muted(name) or name, {
            size = 13,
            colour = nowTime and GOLD or { 1, 1, 1 },
            onClick = function()
                Bag.Link(step)
            end,
            tip = function(tipText)
                tipText:SetText(Bag.Name(step), 1, 1, 1)
                tipText:AddLine(Bag.Where(step), unpack(MUTED))
                if step.tip then
                    tipText:AddLine(step.tip, 1, 1, 1, true)
                end
            end,
        })
        R:Line(Bag.Where(step), { indent = 18, colour = MUTED })
        if nowTime and step.tip then
            R:Line(step.tip, { indent = 18, colour = ACCENT })
        end
    end
    local opt = SB.optional
    if opt then
        R:Gap(6)
        local done = Done(opt.done)
        R:Line((done and (CHECK .. " ") or "") .. opt.object .. Muted("  (optional: " .. opt.quest .. ")"), {
            size = 13,
            onClick = function()
                Link(opt.object, opt.map, opt.x, opt.y, "(" .. opt.place .. ")")
            end,
        })
        R:Line(opt.tip, { indent = 18, colour = MUTED })
    end
end

-------------------------------------------------------------------------------
--  Field Journal tab
-------------------------------------------------------------------------------
local fieldSwitch
local function DrawField(R, tools)
    if not fieldSwitch then
        fieldSwitch = {}
        local posX = 0
        for _, page in ipairs(PAGES) do
            local b = CludesUI.Kit.Button(tools, "", 90, 22, nil, { key = "essentials" })
            b:SetSize(90, 22)
            b:SetPoint("LEFT", tools, "LEFT", posX, 0)
            b:SetText(PAGE_NAMES[page])
            b:SetScript("OnClick", function()
                fieldPage = page
                Redraw()
            end)
            fieldSwitch[page] = b
            posX = posX + 94
        end
    end
    for page, b in pairs(fieldSwitch) do
        b:Show()
        if page == fieldPage then
            b:SetActive(true)
        else
            b:SetActive(false)
        end
    end
    local page = fieldPage
    local done, sum = Field.Progress(page)
    R:Line(
        ("%s  %s"):format(PAGE_NAMES[page], Muted(("%d of %d"):format(done, sum))),
        { size = 16, colour = ACCENT }
    )
    R:Line(
        Field.On() and "Counted as you fish, pick and cook. Shift-click to tick one off by hand."
            or "Turn on the Field Journal in Forever Tools to count what you catch, pick and cook.",
        { colour = MUTED }
    )
    local byRank = {}
    for _, record in ipairs(Field.Entries(page)) do
        local rank = Field.Rank(record.skill) or 0
        byRank[rank] = byRank[rank] or {}
        table.insert(byRank[rank], record)
    end
    for rank = 1, #RANK_NAMES do
        if byRank[rank] then
            R:Gap(6)
            R:Line(RANK_NAMES[rank], { size = 14, colour = GOLD })
            for _, record in ipairs(byRank[rank]) do
                local count = Field.Count(page, record)
                local name = C_Item.GetItemNameByID(record.item) or ("item " .. record.item)
                if not C_Item.GetItemNameByID(record.item) and C_Item.RequestLoadItemDataByID then
                    C_Item.RequestLoadItemDataByID(record.item)
                end
                R:Line((count and (CHECK .. " ") or "") .. name .. "\n" .. Muted(Field.Where(page, record)), {
                    icon = C_Item.GetItemIconByID(record.item) or 134400,
                    right = (record.skill and (record.skill .. "  ") or "")
                        .. (count and count > 0 and ("x" .. count) or ""),
                    tip = function(tipText)
                        tipText:SetItemByID(record.item)
                        if Field.Source(record) and Field.Source(record)[2] then
                            tipText:AddLine("Click to link where to get it.", unpack(MUTED))
                        end
                    end,
                    onClick = function()
                        if IsShiftKeyDown() then
                            local had = Field.Count(page, record)
                            Field.SetHad(page, record, had == nil)
                            Redraw()
                        else
                            Field.Link(record)
                        end
                    end,
                })
            end
        end
    end
    if byRank[0] then
        R:Gap(6)
        R:Line("Schools of fish", { size = 14, colour = GOLD })
        for _, record in ipairs(byRank[0]) do
            local count = Field.Count(page, record)
            R:Line(
                (count and (CHECK .. " ") or "")
                    .. (C_Item.GetItemNameByID(record.item) or ("item " .. record.item))
                    .. "\n"
                    .. Muted(Field.Where(page, record)),
                {
                    icon = C_Item.GetItemIconByID(record.item) or 134400,
                    right = count and count > 0 and ("x" .. count) or nil,
                    tip = function(tipText)
                        tipText:SetItemByID(record.item)
                    end,
                    onClick = function()
                        if IsShiftKeyDown() then
                            Field.SetHad(page, record, Field.Count(page, record) == nil)
                            Redraw()
                        end
                    end,
                }
            )
        end
    end
end

module.DiscoveryAddTab({ key = "books", label = "Library Books", order = 10, draw = DrawBooks })
module.DiscoveryAddTab({ key = "bag", label = "Sleeping Bag", order = 20, draw = DrawBag })
module.DiscoveryAddTab({ key = "field", label = "Field Journal", order = 30, draw = DrawField })

-------------------------------------------------------------------------------
--  Tracker: the books in your zone and the Sleeping Bag's next step
-------------------------------------------------------------------------------
local tracker, trackerRows
local dismissedZone, trackerQueued
local TRACK_W = 250

local function TrackerWanted()
    return On() and (Get("tracker") or Get("bagTracker"))
end

local function BuildTracker()
    tracker = CreateFrame("Frame", "CludesUIDiscoveryTracker", UIParent)
    tracker:SetSize(TRACK_W, 60)
    CludesUI.Kit.Panel(tracker, 0.85)
    tracker:SetClampedToScreen(true)
    tracker.title = tracker:CreateFontString(nil, "OVERLAY")
    CludesUI.Kit.Font(tracker.title, 12, "essentials")
    tracker.title:SetTextColor(unpack(ACCENT))
    tracker.title:SetPoint("TOPLEFT", 8, -6)
    tracker.title:SetText("DISCOVERY")
    local close = CludesUI.Kit.Glyph(tracker, "x", function()
        tracker:Hide()
    end, nil, "essentials")
    close:SetSize(20, 20)
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function()
        dismissedZone = PlayerZone()
        tracker:Hide()
    end)
    local open = CreateFrame("Button", nil, tracker)
    open:SetPoint("TOPLEFT", 4, -2)
    open:SetSize(120, 18)
    open:SetScript("OnClick", function()
        OpenWindow()
    end)
    tracker.body = CreateFrame("Frame", nil, tracker)
    tracker.body:SetPoint("TOPLEFT", 8, -24)
    tracker.body:SetSize(TRACK_W - 16, 10)
    trackerRows = NewRows(tracker.body)
    tracker:Hide()
end

local function FillTracker(zone)
    local R = trackerRows
    R:Reset()
    local any = false
    if Get("tracker") then
        local find = Library.Spots(zone, "find")
        local carried = 0
        for _, book in ipairs(Data().LibraryBooks) do
            if Library.ForMe(book) and Library.Stored(book) then
                carried = carried + 1
            end
        end
        if #find > 0 or carried > 0 or CludesUI._unlockActive then
            any = true
            local done, sum = Library.Progress()
            R:Line(("Library Books  %s"):format(Muted(("%d / %d"):format(done, sum))), { colour = GOLD })
            if carried > 0 then
                local npc = Library.Librarian()
                R:Line(("%d in your bags or bank"):format(carried), {
                    indent = 6,
                    colour = GOLD,
                    tip = function(tipText)
                        tipText:SetText(("Hand in to %s, %s"):format(npc.name, npc.place), 1, 1, 1, 1, true)
                    end,
                    onClick = function()
                        Link(npc.name, npc.map, npc.x, npc.y)
                    end,
                })
            end
            for _, entry in ipairs(find) do
                local book, spot = entry[1], entry[2]
                R:Line(
                    book.name
                        .. "\n"
                        .. Muted(Library.Where(spot) .. (book.turnIn == "trainer" and ", mage trainer" or "")),
                    {
                        indent = 6,
                        tip = BookTip(book, spot),
                        onClick = function()
                            Library.LinkBook(book, spot)
                        end,
                    }
                )
            end
        end
    end
    if Get("bagTracker") and Bag.Level() and not Bag.Owned() then
        local step, index = Bag.Current()
        if step then
            any = true
            R:Gap(4)
            R:Line(
                ("Sleeping Bag  %s"):format(Muted(("step %d of %d"):format(index, #Bag.Steps()))),
                { colour = GOLD }
            )
            R:Line(Bag.Name(step) .. "\n" .. Muted(Bag.Where(step)), {
                indent = 6,
                onClick = function()
                    Bag.Link(step)
                end,
                tip = function(tipText)
                    tipText:SetText(Bag.Name(step), 1, 1, 1)
                    if step.tip then
                        tipText:AddLine(step.tip, 1, 1, 1, true)
                    end
                end,
            })
        end
    end
    return any
end

local function TrackerRefresh()
    trackerQueued = false
    if not TrackerWanted() then
        if tracker then
            tracker:Hide()
        end
        return
    end
    local zone = PlayerZone()
    if zone ~= dismissedZone then
        dismissedZone = nil
    end
    if dismissedZone and not CludesUI._unlockActive then
        if tracker then
            tracker:Hide()
        end
        return
    end
    if not tracker then
        BuildTracker()
    end
    if not CludesUI._unlockActive then
        F.Place(tracker)
    end
    local any = FillTracker(zone)
    if not any and not CludesUI._unlockActive then
        tracker:Hide()
        return
    end
    tracker:SetHeight(trackerRows:Height() + 32)
    tracker:Show()
end

local function TrackerSoon()
    if trackerQueued then
        return
    end
    trackerQueued = true
    C_Timer.After(0.2, TrackerRefresh)
end

-------------------------------------------------------------------------------
--  Map pins: books to find, your librarian while you carry books, and the
--  Sleeping Bag's next step
-------------------------------------------------------------------------------
local provider, layer, waiter
local added = false
local pins, pinsUsed = {}, 0

local function PinsWanted()
    return On() and (Get("mapPins") or Get("bagMapPins"))
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

local function Pin(posX, posY, iconTex, tipText, onClick)
    pinsUsed = pinsUsed + 1
    local p = pins[pinsUsed]
    if not p then
        p = CreateFrame("Button", nil, layer)
        p:RegisterForClicks("LeftButtonUp")
        p.edge = p:CreateTexture(nil, "BACKGROUND")
        p.edge:SetAllPoints()
        p.edge:SetColorTexture(0, 0, 0, 1)
        p.icon = p:CreateTexture(nil, "ARTWORK")
        p.icon:SetPoint("TOPLEFT", 1, -1)
        p.icon:SetPoint("BOTTOMRIGHT", -1, 1)
        p.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
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
        pins[pinsUsed] = p
    end
    local size = Get("pinSize")
    p:SetSize(size, size)
    p.x, p.y = posX / 100, posY / 100
    p.icon:SetTexture(iconTex)
    p.tip, p.onClick = tipText, onClick
    Anchor(p)
    p:Show()
end

local function DrawPins()
    ClearPins()
    if not PinsWanted() then
        return
    end
    local mapID = WorldMapFrame:GetMapID()
    if not mapID then
        return
    end
    if Get("mapPins") then
        for _, entry in ipairs(Library.Spots(mapID, "find")) do
            local book, spot = entry[1], entry[2]
            Pin(
                spot[SPOT_X],
                spot[SPOT_Y],
                C_Item.GetItemIconByID(book.item) or "Interface\\Icons\\INV_Misc_Book_11",
                BookTip(book, spot),
                function()
                    Library.LinkBook(book, spot)
                end
            )
        end
        if Get("mapTurnIn") then
            local counts = {}
            for _, book in ipairs(Data().LibraryBooks) do
                if Library.ForMe(book) and Library.Stored(book) then
                    local kind = book.turnIn or TURN_IN
                    counts[kind] = (counts[kind] or 0) + 1
                end
            end
            for kind, num in pairs(counts) do
                local npc = Data().LibraryTurnIns[kind][Side()]
                if npc.map == mapID then
                    Pin(npc.x, npc.y, "Interface\\Icons\\INV_Misc_Book_07", function(tipText)
                        tipText:SetText(npc.name, 1, 1, 1)
                        tipText:AddLine(
                            num == 1 and "Takes the book you carry."
                                or ("Takes the %d books you carry."):format(num),
                            unpack(GOLD)
                        )
                    end, function()
                        Link(npc.name, npc.map, npc.x, npc.y)
                    end)
                end
            end
        end
    end
    if Get("bagMapPins") and Bag.Level() and not Bag.Owned() then
        local step = Bag.Current()
        if step and step.map == mapID then
            Pin(step.x, step.y, "Interface\\Icons\\INV_Misc_Bag_08", function(tipText)
                tipText:SetText(Bag.Name(step), 1, 1, 1)
                tipText:AddLine("Cozy Sleeping Bag, next step", unpack(GOLD))
                tipText:AddLine(Bag.Where(step), unpack(MUTED))
                if step.tip then
                    tipText:AddLine(step.tip, 1, 1, 1, true)
                end
            end, function()
                Bag.Link(step)
            end)
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
--  Events and apply
-------------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, evt)
    if evt == "PLAYER_ENTERING_WORLD" or evt == "ZONE_CHANGED_NEW_AREA" then
        NearRefresh()
    elseif evt == "BAG_UPDATE_DELAYED" or evt == "QUEST_TURNED_IN" or evt == "QUEST_LOG_UPDATE" then
        if evt ~= "QUEST_LOG_UPDATE" then
            NearRefresh()
        end
        if added and WorldMapFrame:IsShown() then
            DrawPins()
        end
    end
    TrackerSoon()
    RedrawSoon()
end)

local function Apply()
    eventFrame:UnregisterAllEvents()
    if On() then
        for _, event in ipairs({
            "PLAYER_ENTERING_WORLD",
            "ZONE_CHANGED_NEW_AREA",
            "BAG_UPDATE_DELAYED",
            "QUEST_TURNED_IN",
            "QUEST_LOG_UPDATE",
            "PLAYER_LEVEL_UP",
        }) do
            eventFrame:RegisterEvent(event)
        end
    end
    NearRefresh()
    FieldApply()
    PinsApply()
    TrackerRefresh()
    if module.QuestListApply then
        module.QuestListApply()
    end
end

SLASH_CUIDISCOVERY1 = "/cdiscovery"
SlashCmdList.CUIDISCOVERY = function(message)
    if not On() then
        Print("turn on Discovery in CludesUI Forever Tools first.")
        return
    end
    message = (message or ""):lower()
    if window and window:IsShown() and message == "" then
        window:Hide()
        return
    end
    OpenWindow(tabs[message] and message or nil)
end

CludesUI._Discovery = { Get = Get, Cfg = F.Cfg, Apply = Apply, Open = OpenWindow }
module.DiscoveryFeature = F
module.DiscoveryOpen = OpenWindow

F.Start(Apply, {
    key = "CUI_DiscoveryTracker",
    label = "Discovery Tracker",
    order = 756,
    shown = function()
        return TrackerWanted()
    end,
    frame = function(build)
        if build and not tracker then
            BuildTracker()
        end
        if build then
            FillTracker(PlayerZone())
            tracker:SetHeight(trackerRows:Height() + 32)
        end
        return tracker
    end,
    size = function()
        return TRACK_W, tracker and tracker:GetHeight() or 60
    end,
    noAnchorTarget = true,
    noSizeMatchTarget = true,
})
