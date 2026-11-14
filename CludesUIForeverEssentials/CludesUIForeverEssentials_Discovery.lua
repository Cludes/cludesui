if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if not (CludesUI and CludesUI.IS_FOREVER) then return end
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
    enabled = false, tracker = true, bagTracker = true, mapPins = true, bagMapPins = true, mapTurnIn = true,
    pinSize = 20, nearby = true, nearbyRange = 40, nearbyPing = true, nearbyChat = true, fieldJournal = true,
}, { point = "RIGHT", relPoint = "RIGHT", x = -260, y = -120 })
local Get, On = F.Get, F.Enabled

local SPOT_MAP, SPOT_X, SPOT_Y, SPOT_PLACE, SPOT_NOTE = 1, 2, 3, 4, 5
local TURN_IN = "librarian"
local SLEEPING_BAG = 211527
local CHECK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:0|t"
local ACCENT = CludesUI.Kit.SyncAccent({})  -- refreshed on each draw
local MUTED = { 0.6, 0.65, 0.7 }
local GOLD = { 1, 0.82, 0 }
local READY = { 0.38, 0.85, 0.5 }
local function Font() return CludesUI.GetFontPath("essentials") end
local function Print(msg) CludesUI.Print("|cff4cc9f0Discovery:|r " .. msg) end
local function Muted(text) return "|cff9aa6b2" .. text .. "|r" end

local D
local function Data()
    if not D then
        D = module.DiscoveryData()
        module.DiscoveryData = nil
    end
    return D
end

-- A map pin link in chat (as /way prints it); a click on it places the pin.
local function Link(title, map, x, y, note)
    if not (map and C_Map.CanSetUserWaypointOnMap(map)) then return Print("this place cannot take a map pin.") end
    local link = ("|cffffff00|Hworldmap:%d:%d:%d|h[%s]|h|r"):format(map, math.floor(x * 100 + 0.5), math.floor(y * 100 + 0.5),
        MAP_PIN_HYPERLINK or "Map Pin")
    local function Say()
        CludesUI.Print("|cff4cc9f0Discovery:|r " .. link .. " " .. title .. (note and (" " .. Muted(note)) or "")
            .. " " .. Muted(("%.1f, %.1f"):format(x, y)))
    end
    if InCombatLockdown() and CludesUI.CombatQueue then CludesUI.CombatQueue.Defer("DiscoveryLink", Say) else Say() end
end

local function ZoneName(mapID)
    local info = mapID and C_Map.GetMapInfo(mapID)
    return info and info.name or ("map " .. tostring(mapID))
end

local function PlayerZone()
    local id = C_Map.GetBestMapForUnit("player")
    local info = id and C_Map.GetMapInfo(id)
    while info and info.mapType and info.mapType > Enum.UIMapType.Zone and info.parentMapID and info.parentMapID ~= 0 do
        id = info.parentMapID
        info = C_Map.GetMapInfo(id)
    end
    return id
end

local function Side() return UnitFactionGroup("player") == "Horde" and "H" or "A" end
local function Done(quest) return C_QuestLog.IsQuestFlaggedCompleted(quest) end

-------------------------------------------------------------------------------
--  Library books
-------------------------------------------------------------------------------
local Library = {}

function Library.ForMe(book) return not book.missing and (book.side == "B" or book.side == Side()) end
function Library.Done(book) return Done(book.quest) end
function Library.Stored(book)
    if Library.Done(book) then return nil end
    if C_Item.GetItemCount(book.item) > 0 then return "bags" end
    if C_Item.GetItemCount(book.item, true) > 0 then return "bank" end
end
local function BookState(book)
    if Library.Done(book) then return "done" end
    if C_Item.GetItemCount(book.item, true) > 0 then return "carried" end
    return "find"
end
function Library.ToFind(book) return Library.ForMe(book) and BookState(book) == "find" end
function Library.TurnIn(book) return Data().LibraryTurnIns[book.turnIn or TURN_IN][Side()] end
function Library.Librarian() return Data().LibraryTurnIns[TURN_IN][Side()] end

function Library.Spots(mapID, state)
    local out = {}
    if not mapID then return out end
    for _, book in ipairs(Data().LibraryBooks) do
        if Library.ForMe(book) and BookState(book) == state then
            for _, spot in ipairs(book.spots) do
                if spot[SPOT_MAP] == mapID then out[#out + 1] = { book, spot } end
            end
        end
    end
    return out
end

function Library.Progress()
    local done, total = 0, 0
    for _, book in ipairs(Data().LibraryBooks) do
        if book.turnIn == TURN_IN and Library.ForMe(book) then
            total = total + 1
            if Library.Done(book) then done = done + 1 end
        end
    end
    return done, total
end

function Library.NextGoal()
    for _, goal in ipairs(Data().LibraryGoals) do
        if not Done(goal.quest) then return goal end
    end
end

function Library.GoalState(goal, done)
    if Done(goal.quest) then return "claimed" end
    if done < goal.books then return "ahead" end
    if goal.level and UnitLevel("player") < goal.level then return "level" end
    return "ready"
end

function Library.Where(spot)
    local coords = ("(%.1f, %.1f)"):format(spot[SPOT_X], spot[SPOT_Y])
    return spot[SPOT_PLACE] and (spot[SPOT_PLACE] .. " " .. coords) or coords
end

function Library.LinkBook(book, spot)
    Link(book.name, spot[SPOT_MAP], spot[SPOT_X], spot[SPOT_Y], spot[SPOT_PLACE] and ("(" .. spot[SPOT_PLACE] .. ")"))
end

function Library.Title(book)
    if Library.Done(book) then return CHECK .. " " .. Muted(book.name) end
    local c = GetQuestDifficultyColor(book.tier)
    return ("|cff%02x%02x%02x(%d)|r %s"):format(c.r * 255, c.g * 255, c.b * 255, book.tier, book.name)
end

-------------------------------------------------------------------------------
--  The Cozy Sleeping Bag chain
-------------------------------------------------------------------------------
local Bag = {}

function Bag.Steps() return Data().SleepingBag.steps[Side()] end
function Bag.StepDone(step)
    if step.started then return Done(step.started) or C_QuestLog.IsOnQuest(step.started) end
    return Done(step.done)
end
function Bag.Current()
    for i, step in ipairs(Bag.Steps()) do
        if not Bag.StepDone(step) then return step, i end
    end
end
function Bag.Owned() return C_Item.GetItemCount(SLEEPING_BAG, true) > 0 end
function Bag.Level() return UnitLevel("player") >= Data().SleepingBag.level end
function Bag.Name(step)
    for _, other in ipairs(Bag.Steps()) do
        if other ~= step and other.object == step.object and other.map ~= step.map then
            return ("%s (%s)"):format(step.object, ZoneName(step.map))
        end
    end
    return step.object
end
function Bag.Where(step) return ("%s, %s (%.1f, %.1f)"):format(ZoneName(step.map), step.place, step.x, step.y) end
function Bag.Link(step) Link(step.object, step.map, step.x, step.y, "(" .. step.place .. ")") end

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

local function Plain(v) return not (issecretvalue and issecretvalue(v)) end

local function Lookup()
    if lookup then return lookup end
    local FJ = Data().FieldJournal
    lookup = { fish = {}, herbs = {}, dishes = {}, nodes = {} }
    for _, entry in ipairs(FJ.fish) do lookup.fish[entry.item] = entry end
    for _, entry in ipairs(FJ.herbs) do
        lookup.herbs[entry.item] = entry
        for _, node in ipairs(entry.nodes) do lookup.nodes[node] = true end
    end
    for _, entry in ipairs(FJ.dishes) do lookup.dishes[entry.spell] = entry end
    return lookup
end

local function FieldStore(create)
    local guid = UnitGUID("player")
    if not guid then return end
    local cfg = create and F.Cfg() or F.Read()
    local all = cfg.field
    if not all then
        if not create then return end
        all = {}
        cfg.field = all
    end
    local mine = all[guid]
    if not mine and create then
        mine = {}
        all[guid] = mine
    end
    if mine and create then
        for _, page in ipairs(PAGES) do mine[page] = mine[page] or {} end
    end
    return mine
end

local function FieldAdd(page, id, n)
    local mine = FieldStore(true)
    if not mine then return end
    mine[page][id] = (mine[page][id] or 0) + n
    if OnFieldChange then OnFieldChange(page) end
end

function Field.On() return On() and Get("fieldJournal") end
function Field.Entries(page) return Data().FieldJournal[page] end
function Field.Key(entry) return entry.spell or entry.item end
function Field.Count(page, entry)
    local mine = FieldStore(false)
    local done = mine and mine[page]
    return done and done[Field.Key(entry)]
end
function Field.SetHad(page, entry, had)
    local mine = FieldStore(true)
    if not mine then return end
    local key = Field.Key(entry)
    if had then
        mine[page][key] = mine[page][key] or 0
    elseif mine[page][key] == 0 then
        mine[page][key] = nil
    end
    if OnFieldChange then OnFieldChange(page) end
end
function Field.Progress(page)
    local mine = FieldStore(false)
    local had = mine and mine[page]
    local list = Field.Entries(page)
    local done = 0
    if had then
        for _, entry in ipairs(list) do
            if had[Field.Key(entry)] ~= nil then done = done + 1 end
        end
    end
    return done, #list
end
function Field.Rank(skill)
    if not skill then return nil end
    for i, cap in ipairs(RANK_CAPS) do
        if skill <= cap then return i end
    end
    return #RANK_CAPS + 1
end

local function FieldZones(entry, withChance)
    local names = {}
    local zones = entry.zones or {}
    local stride = withChance and 2 or 1
    for i = 1, #zones, stride do
        local name = ZoneName(zones[i])
        if withChance then name = ("%s %d%%"):format(name, math.max(1, math.floor(zones[i + 1] + 0.5))) end
        names[#names + 1] = name
    end
    return table.concat(names, ", ")
end

function Field.Source(entry) return entry[Side()] or entry.B end

function Field.Where(page, entry)
    if page == "dishes" then
        local how, from = entry.how, Field.Source(entry)
        if how == "trainer" then return "Taught by cooking trainers" end
        if how == "world" then return "A world drop" end
        if how == "unknown" then return "Where to learn it is not known yet" end
        if not from then
            if how == "vendor" and not (entry.A or entry.H) then return "Sold by a vendor" end
            return "Only for the other faction"
        end
        if how == "vendor" then return ("Sold by %s, %s"):format(from[1], ZoneName(from[2])) end
        if how == "quest" then return ("From the quest %s"):format(from[1]) end
        return ("Drops from %s"):format(from[1])
    end
    if page == "herbs" then return FieldZones(entry, false) end
    if not entry.zones then return "Caught from schools of fish" end
    local zones = FieldZones(entry, true)
    return entry.schools and (zones .. ", and from schools of fish") or zones
end

function Field.Link(entry)
    local from = Field.Source(entry)
    if from and from[2] then Link(from[5] or from[1], from[2], from[3], from[4]) end
end

local function FromNode(guid)
    if type(guid) ~= "string" or not Plain(guid) then return false end
    return Lookup().nodes[tonumber(guid:match(GUID_OBJECT) or "")] == true
end

local function LootForget() wipe(lootPage); wipe(lootItem); wipe(lootQty) end

local function LootOpened()
    LootForget()
    local fishing = IsFishingLoot()
    local known = Lookup()
    for slot = 1, GetNumLootItems() do
        local link = GetLootSlotLink(slot)
        local item = link and Plain(link) and C_Item.GetItemInfoInstant(link) or nil
        local page
        if item and fishing and known.fish[item] then
            page = "fish"
        elseif item and not fishing and known.herbs[item] and FromNode(GetLootSourceInfo(slot)) then
            page = "herbs"
        end
        local _, _, quantity = GetLootSlotInfo(slot)
        if page and Plain(quantity) and quantity and quantity > 0 then
            lootPage[slot], lootItem[slot], lootQty[slot] = page, item, quantity
        end
    end
end

local function FieldApply()
    if not Field.On() then
        if fieldEvents then fieldEvents:UnregisterAllEvents() end
        LootForget()
        return
    end
    if not fieldEvents then
        fieldEvents = CreateFrame("Frame")
        fieldEvents:SetScript("OnEvent", function(self, event, a, _, spellID)
            if event == "LOOT_OPENED" then
                LootOpened()
            elseif event == "LOOT_SLOT_CLEARED" then
                local page = lootPage[a]
                if page then
                    lootPage[a] = nil
                    FieldAdd(page, lootItem[a], lootQty[a])
                end
            elseif event == "LOOT_CLOSED" then
                LootForget()
            elseif event == "TRADE_SKILL_SHOW" then
                self:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
            elseif event == "TRADE_SKILL_CLOSE" then
                self:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
            elseif event == "UNIT_SPELLCAST_SUCCEEDED" and Plain(spellID) and Lookup().dishes[spellID] then
                FieldAdd("dishes", spellID, 1)
            end
        end)
    end
    for _, e in ipairs({ "LOOT_OPENED", "LOOT_SLOT_CLEARED", "LOOT_CLOSED", "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE" }) do
        fieldEvents:RegisterEvent(e)
    end
end

-------------------------------------------------------------------------------
--  Nearby alert: a ping and a chat line within range of a book you need
-------------------------------------------------------------------------------
local nearTicker, nearZone, nearTargets
local nearEvents = CreateFrame("Frame")
local alerted = {}

local function WorldPos(mapID, x, y)
    local _, pos = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(x, y))
    return pos
end

local function NearCheck()
    if not (nearZone and nearTargets) then return end
    local here = C_Map.GetPlayerMapPosition(nearZone, "player")
    if not here or (issecretvalue and issecretvalue(here)) then return end
    local me = WorldPos(nearZone, here:GetXY())
    if not me then return end
    local range = Get("nearbyRange")
    local mx, my = me:GetXY()
    for _, target in ipairs(nearTargets) do
        local tx, ty = target[3]:GetXY()
        local dist = math.sqrt((tx - mx) ^ 2 + (ty - my) ^ 2)
        local quest = target[1].quest
        if dist <= range and not alerted[quest] then
            alerted[quest] = true
            if Get("nearbyPing") then PlaySound(SOUNDKIT.MAP_PING, "Master") end
            if Get("nearbyChat") then
                local place = target[2][SPOT_PLACE]
                Print(("library book nearby: %s, %d yards%s"):format(target[1].name, math.floor(dist), place and (" - " .. place) or ""))
            end
        elseif dist > range * 1.5 then
            alerted[quest] = nil
        end
    end
end

local function NearStop()
    if nearTicker then nearTicker:Cancel(); nearTicker = nil end
    nearZone, nearTargets = nil, nil
    nearEvents:UnregisterEvent("PLAYER_STARTED_MOVING")
    nearEvents:UnregisterEvent("PLAYER_STOPPED_MOVING")
end

local function NearRefresh()
    if not (On() and Get("nearby")) or IsInInstance() then return NearStop() end
    local id = PlayerZone()
    local list = {}
    for _, item in ipairs(Library.Spots(id, "find")) do
        local spot = item[2]
        local pos = WorldPos(id, spot[SPOT_X] / 100, spot[SPOT_Y] / 100)
        if pos then list[#list + 1] = { item[1], spot, pos } end
    end
    if #list == 0 then return NearStop() end
    nearZone, nearTargets = id, list
    nearEvents:RegisterEvent("PLAYER_STARTED_MOVING")
    nearEvents:RegisterEvent("PLAYER_STOPPED_MOVING")
    NearCheck()
    if IsPlayerMoving() then
        nearTicker = nearTicker or C_Timer.NewTicker(1, NearCheck)
    elseif nearTicker then
        nearTicker:Cancel(); nearTicker = nil
    end
end

nearEvents:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_STARTED_MOVING" then
        nearTicker = nearTicker or C_Timer.NewTicker(1, NearCheck)
    elseif event == "PLAYER_STOPPED_MOVING" then
        if nearTicker then nearTicker:Cancel(); nearTicker = nil end
        NearCheck()
    else
        NearRefresh()
    end
end)

-------------------------------------------------------------------------------
--  Rows: the window and the tracker draw with the same pooled lines
-------------------------------------------------------------------------------
local function NewRows(content)
    local R = { content = content, pool = {}, used = 0, y = 0 }

    local function Acquire()
        R.used = R.used + 1
        local r = R.pool[R.used]
        if not r then
            r = CreateFrame("Button", nil, content)
            r:RegisterForClicks("AnyUp")
            r.icon = r:CreateTexture(nil, "ARTWORK")
            r.icon:SetSize(18, 18)
            r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            r.text = r:CreateFontString(nil, "OVERLAY")
            r.text:SetJustifyH("LEFT")
            r.text:SetWordWrap(true)
            r.right = r:CreateFontString(nil, "OVERLAY")
            r.right:SetJustifyH("RIGHT")
            -- Fonts now: Acquire clears the right text before Line sizes it,
            -- and the client refuses text on a FontString without a font.
            CludesUI.Kit.Font(r.text, 12, "essentials")
            CludesUI.Kit.Font(r.right, 11, "essentials")
            r.hl = r:CreateTexture(nil, "HIGHLIGHT")
            r.hl:SetAllPoints()
            r.hl:SetColorTexture(1, 1, 1, 0.05)
            r:SetScript("OnEnter", function(self)
                if not self.tip then return end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                self.tip(GameTooltip)
                GameTooltip:Show()
            end)
            r:SetScript("OnLeave", function() GameTooltip:Hide() end)
            r:SetScript("OnClick", function(self, button) if self.onClick then self.onClick(button) end end)
            R.pool[R.used] = r
        end
        r.tip, r.onClick = nil, nil
        r:ClearAllPoints()
        r.icon:Hide()
        r.text:ClearAllPoints()
        r.right:SetText("")
        r:Show()
        return r
    end

    function R:Reset()
        for i = 1, self.used do self.pool[i]:Hide() end
        self.used, self.y = 0, 0
    end

    -- A line of text; opts: size, colour, indent, icon, right, onClick, tip.
    function R:Line(text, opts)
        opts = opts or {}
        local r = Acquire()
        local width = content:GetWidth()
        local indent = opts.indent or 0
        local size = opts.size or 12
        CludesUI.Kit.Font(r.text, size, "essentials")
        r.text:SetTextColor(unpack(opts.colour or { 1, 1, 1 }))
        local left = indent
        if opts.icon then
            r.icon:SetTexture(opts.icon)
            r.icon:ClearAllPoints()
            r.icon:SetPoint("TOPLEFT", r, "TOPLEFT", indent, -1)
            r.icon:Show()
            left = indent + 24
        end
        r.text:SetPoint("TOPLEFT", r, "TOPLEFT", left, -2)
        local rightW = 0
        if opts.right then
            CludesUI.Kit.Font(r.right, 11, "essentials")
            r.right:SetTextColor(unpack(opts.rightColour or MUTED))
            r.right:SetText(opts.right)
            r.right:ClearAllPoints()
            r.right:SetPoint("TOPRIGHT", r, "TOPRIGHT", -4, -3)
            rightW = r.right:GetStringWidth() + 10
        end
        r.text:SetWidth(math.max(40, width - left - rightW - 6))
        r.text:SetText(text)
        local h = math.max(opts.icon and 22 or 16, r.text:GetStringHeight() + 5)
        r:SetSize(width, h)
        r:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -self.y)
        r.tip, r.onClick = opts.tip, opts.onClick
        r:EnableMouse(opts.tip ~= nil or opts.onClick ~= nil)
        self.y = self.y + h
        return r
    end

    function R:Gap(n) self.y = self.y + (n or 6) end
    function R:Height() return self.y end
    return R
end

-------------------------------------------------------------------------------
--  Window
-------------------------------------------------------------------------------
local WIN_W, WIN_H = 620, 540
local win, scroll, content, rows
local tabs, tabButtons = {}, {}
local currentTab
local fieldPage = "fish"
local Redraw

local function TabOrder()
    local list = {}
    for key, tab in pairs(tabs) do list[#list + 1] = tab end
    table.sort(list, function(a, b) return a.order < b.order end)
    return list
end

local function BuildWindow()
    win = CreateFrame("Frame", "CludesUIDiscovery", UIParent)
    win:SetSize(WIN_W, WIN_H)
    win:SetPoint("CENTER", 0, 30)
    CludesUI.Kit.Panel(win, 0.96)
    win:SetMovable(true); win:EnableMouse(true); win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    win:SetFrameStrata("HIGH")
    win:SetClampedToScreen(true)
    local title = win:CreateFontString(nil, "OVERLAY")
    CludesUI.Kit.Font(title, 15, "essentials")
    title:SetPoint("TOPLEFT", 10, -8)
    title:SetText("Discovery")
    CludesUI.Kit.AccentText(title)
    local close = CludesUI.Kit.Glyph(win, "x", function() win:Hide() end, nil, "essentials")
    close:SetPoint("TOPRIGHT", -5, -5)
    win.tabBar = CreateFrame("Frame", nil, win)
    win.tabBar:SetPoint("TOPLEFT", 10, -32)
    win.tabBar:SetSize(WIN_W - 20, 22)
    win.tools = CreateFrame("Frame", nil, win)
    win.tools:SetPoint("TOPLEFT", 10, -58)
    win.tools:SetSize(WIN_W - 20, 24)
    scroll = (CludesUI.Kit.Scroll(win))
    scroll:SetPoint("TOPLEFT", 10, -86)
    scroll:SetPoint("BOTTOMRIGHT", -30, 10)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(WIN_W - 44, 10)
    scroll:SetScrollChild(content)
    rows = NewRows(content)
    win:Hide()
    tinsert(UISpecialFrames, "CludesUIDiscovery")
end

local function PaintTabs()
    local x = 0
    for i, tab in ipairs(TabOrder()) do
        local b = tabButtons[i]
        if not b then
            b = CludesUI.Kit.Button(win.tabBar, "", 90, 22, nil, { key = "essentials" })
            b:SetHeight(22)
            tabButtons[i] = b
        end
        b:SetText(tab.label)
        b:SetWidth(math.max(80, b:GetTextWidth() + 24))
        b:ClearAllPoints()
        b:SetPoint("LEFT", win.tabBar, "LEFT", x, 0)
        b:SetScript("OnClick", function() currentTab = tab.key; Redraw() end)
        if tab.key == currentTab then b:SetActive(true) else b:SetActive(false) end
        b:Show()
        x = x + b:GetWidth() + 4
    end
end

function Redraw()
    if not (win and win:IsShown()) then return end
    CludesUI.Kit.SyncAccent(ACCENT)
    PaintTabs()
    rows:Reset()
    for _, child in ipairs({ win.tools:GetChildren() }) do child:Hide() end
    local tab = tabs[currentTab] or TabOrder()[1]
    currentTab = tab.key
    tab.draw(rows, win.tools)
    content:SetHeight(rows:Height() + 10)
end

local redrawQueued
local function RedrawSoon()
    if redrawQueued or not (win and win:IsShown()) then return end
    redrawQueued = true
    C_Timer.After(0.2, function() redrawQueued = false; Redraw() end)
end
OnFieldChange = RedrawSoon

local function OpenWindow(tab)
    if not win then BuildWindow() end
    if tab then currentTab = tab end
    win:Show()
    Redraw()
end

--- Other files add a tab: { key, label, order, draw = function(rows, tools) }.
function module.DiscoveryAddTab(tab) tabs[tab.key] = tab end
module.DiscoveryRows = NewRows
module.DiscoveryRedraw = RedrawSoon
module.DiscoveryLink = Link
module.DiscoveryZoneName = ZoneName
module.DiscoveryPlayerZone = PlayerZone

-------------------------------------------------------------------------------
--  Library Books tab
-------------------------------------------------------------------------------
local function GoalLine(goal, done)
    local state = Library.GoalState(goal, done)
    local words, colour
    if state == "claimed" then words, colour = "Claimed", MUTED
    elseif state == "ready" then words, colour = "Ready to hand in", READY
    elseif state == "level" then words, colour = ("At level %d"):format(goal.level), GOLD
    else words, colour = ("%d to go"):format(goal.books - done), { 1, 1, 1 } end
    local names = {}
    for _, reward in ipairs(goal.rewards) do names[#names + 1] = C_Item.GetItemNameByID(reward[1]) or reward[2] end
    return ("%s (%d)"):format(goal.name, goal.books), words, colour, table.concat(names, " or ")
end

local function BookTip(book, spot)
    return function(tip)
        tip:SetText(book.name, 1, 1, 1)
        local c = GetQuestDifficultyColor(book.tier)
        tip:AddLine(("Level %d"):format(book.tier), c.r, c.g, c.b)
        if spot then
            tip:AddLine(ZoneName(spot[SPOT_MAP]) .. ", " .. Library.Where(spot), unpack(MUTED))
            if spot[SPOT_NOTE] then tip:AddLine(spot[SPOT_NOTE], 1, 1, 1, true) end
        end
        local npc = Library.TurnIn(book)
        tip:AddLine(("Hand in to %s, %s"):format(npc.name, npc.place), ACCENT[1], ACCENT[2], ACCENT[3], true)
        if spot then tip:AddLine("Click to link its map pin in chat.", unpack(MUTED)) end
    end
end

local function DrawBooks(R)
    local done, total = Library.Progress()
    R:Line(("Library Books  %s"):format(Muted(("%d of %d handed in"):format(done, total))), { size = 16, colour = ACCENT })
    local librarian = Library.Librarian()
    R:Line(("Hand them in to %s, %s."):format(librarian.name, librarian.place), { colour = MUTED,
        onClick = function() Link(librarian.name, librarian.map, librarian.x, librarian.y) end })
    R:Gap(4)
    for _, goal in ipairs(Data().LibraryGoals) do
        local name, words, colour, rewards = GoalLine(goal, done)
        R:Line(name, { size = 13, colour = GOLD, right = words, rightColour = colour })
        R:Line(rewards, { indent = 14, colour = MUTED })
    end
    local tiers, order = {}, {}
    for _, book in ipairs(Data().LibraryBooks) do
        if Library.ForMe(book) then
            if not tiers[book.tier] then tiers[book.tier] = {}; order[#order + 1] = book.tier end
            table.insert(tiers[book.tier], book)
        end
    end
    table.sort(order)
    for _, tier in ipairs(order) do
        R:Gap(6)
        R:Line(("Level %d books"):format(tier), { size = 14, colour = GOLD })
        for _, book in ipairs(tiers[tier]) do
            local stored = Library.Stored(book)
            local right = Library.Done(book) and "handed in" or stored == "bags" and "in your bags"
                or stored == "bank" and "in your bank" or nil
            local spot = book.spots[1]
            local icon = C_Item.GetItemIconByID(book.item) or 134400
            local where = book.unplaced and "Not found on Forever yet" or spot and (ZoneName(spot[SPOT_MAP]) .. ", " .. Library.Where(spot)) or ""
            R:Line(Library.Title(book) .. "\n" .. Muted(where), { icon = icon, right = right,
                rightColour = right == "handed in" and MUTED or GOLD, tip = BookTip(book, spot),
                onClick = spot and function() Library.LinkBook(book, spot) end })
            for i = 2, #book.spots do
                local other = book.spots[i]
                R:Line(Muted("or " .. ZoneName(other[SPOT_MAP]) .. ", " .. Library.Where(other)), { indent = 24,
                    tip = BookTip(book, other), onClick = function() Library.LinkBook(book, other) end })
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
    R:Line(owned and "You have the Cozy Sleeping Bag." or (not Bag.Level() and ("The chain opens at level %d."):format(SB.level))
        or "A hidden chain of things to click across Azeroth. Click a step to link its map pin in chat.", { colour = MUTED })
    R:Gap(4)
    for i, step in ipairs(Bag.Steps()) do
        local done = Bag.StepDone(step)
        local now = step == current
        local name = (done and (CHECK .. " ") or (i .. ". ")) .. Bag.Name(step)
        R:Line(done and Muted(name) or name, { size = 13, colour = now and GOLD or { 1, 1, 1 },
            onClick = function() Bag.Link(step) end,
            tip = function(tip)
                tip:SetText(Bag.Name(step), 1, 1, 1)
                tip:AddLine(Bag.Where(step), unpack(MUTED))
                if step.tip then tip:AddLine(step.tip, 1, 1, 1, true) end
            end })
        R:Line(Bag.Where(step), { indent = 18, colour = MUTED })
        if now and step.tip then R:Line(step.tip, { indent = 18, colour = ACCENT }) end
    end
    local opt = SB.optional
    if opt then
        R:Gap(6)
        local done = Done(opt.done)
        R:Line((done and (CHECK .. " ") or "") .. opt.object .. Muted("  (optional: " .. opt.quest .. ")"), { size = 13,
            onClick = function() Link(opt.object, opt.map, opt.x, opt.y, "(" .. opt.place .. ")") end })
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
        local x = 0
        for _, page in ipairs(PAGES) do
            local b = CludesUI.Kit.Button(tools, "", 90, 22, nil, { key = "essentials" })
            b:SetSize(90, 22)
            b:SetPoint("LEFT", tools, "LEFT", x, 0)
            b:SetText(PAGE_NAMES[page])
            b:SetScript("OnClick", function() fieldPage = page; Redraw() end)
            fieldSwitch[page] = b
            x = x + 94
        end
    end
    for page, b in pairs(fieldSwitch) do
        b:Show()
        if page == fieldPage then b:SetActive(true) else b:SetActive(false) end
    end
    local page = fieldPage
    local done, total = Field.Progress(page)
    R:Line(("%s  %s"):format(PAGE_NAMES[page], Muted(("%d of %d"):format(done, total))), { size = 16, colour = ACCENT })
    R:Line(Field.On() and "Counted as you fish, pick and cook. Shift-click to tick one off by hand."
        or "Turn on the Field Journal in Forever Tools to count what you catch, pick and cook.", { colour = MUTED })
    local byRank = {}
    for _, entry in ipairs(Field.Entries(page)) do
        local rank = Field.Rank(entry.skill) or 0
        byRank[rank] = byRank[rank] or {}
        table.insert(byRank[rank], entry)
    end
    for rank = 1, #RANK_NAMES do
        if byRank[rank] then
            R:Gap(6)
            R:Line(RANK_NAMES[rank], { size = 14, colour = GOLD })
            for _, entry in ipairs(byRank[rank]) do
                local count = Field.Count(page, entry)
                local name = C_Item.GetItemNameByID(entry.item) or ("item " .. entry.item)
                if not C_Item.GetItemNameByID(entry.item) and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(entry.item) end
                R:Line((count and (CHECK .. " ") or "") .. name .. "\n" .. Muted(Field.Where(page, entry)), {
                    icon = C_Item.GetItemIconByID(entry.item) or 134400,
                    right = (entry.skill and (entry.skill .. "  ") or "") .. (count and count > 0 and ("x" .. count) or ""),
                    tip = function(tip)
                        tip:SetItemByID(entry.item)
                        if Field.Source(entry) and Field.Source(entry)[2] then tip:AddLine("Click to link where to get it.", unpack(MUTED)) end
                    end,
                    onClick = function()
                        if IsShiftKeyDown() then
                            local had = Field.Count(page, entry)
                            Field.SetHad(page, entry, had == nil)
                            Redraw()
                        else
                            Field.Link(entry)
                        end
                    end })
            end
        end
    end
    if byRank[0] then
        R:Gap(6)
        R:Line("Schools of fish", { size = 14, colour = GOLD })
        for _, entry in ipairs(byRank[0]) do
            local count = Field.Count(page, entry)
            R:Line((count and (CHECK .. " ") or "") .. (C_Item.GetItemNameByID(entry.item) or ("item " .. entry.item))
                .. "\n" .. Muted(Field.Where(page, entry)), { icon = C_Item.GetItemIconByID(entry.item) or 134400,
                right = count and count > 0 and ("x" .. count) or nil,
                tip = function(tip) tip:SetItemByID(entry.item) end,
                onClick = function() if IsShiftKeyDown() then Field.SetHad(page, entry, Field.Count(page, entry) == nil); Redraw() end end })
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
    local close = CludesUI.Kit.Glyph(tracker, "x", function() tracker:Hide() end, nil, "essentials")
    close:SetSize(20, 20)
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() dismissedZone = PlayerZone(); tracker:Hide() end)
    local open = CreateFrame("Button", nil, tracker)
    open:SetPoint("TOPLEFT", 4, -2)
    open:SetSize(120, 18)
    open:SetScript("OnClick", function() OpenWindow() end)
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
            if Library.ForMe(book) and Library.Stored(book) then carried = carried + 1 end
        end
        if #find > 0 or carried > 0 or CludesUI._unlockActive then
            any = true
            local done, total = Library.Progress()
            R:Line(("Library Books  %s"):format(Muted(("%d / %d"):format(done, total))), { colour = GOLD })
            if carried > 0 then
                local npc = Library.Librarian()
                R:Line(("%d in your bags or bank"):format(carried), { indent = 6, colour = GOLD,
                    tip = function(tip) tip:SetText(("Hand in to %s, %s"):format(npc.name, npc.place), 1, 1, 1, 1, true) end,
                    onClick = function() Link(npc.name, npc.map, npc.x, npc.y) end })
            end
            for _, item in ipairs(find) do
                local book, spot = item[1], item[2]
                R:Line(book.name .. "\n" .. Muted(Library.Where(spot) .. (book.turnIn == "trainer" and ", mage trainer" or "")),
                    { indent = 6, tip = BookTip(book, spot), onClick = function() Library.LinkBook(book, spot) end })
            end
        end
    end
    if Get("bagTracker") and Bag.Level() and not Bag.Owned() then
        local step, i = Bag.Current()
        if step then
            any = true
            R:Gap(4)
            R:Line(("Sleeping Bag  %s"):format(Muted(("step %d of %d"):format(i, #Bag.Steps()))), { colour = GOLD })
            R:Line(Bag.Name(step) .. "\n" .. Muted(Bag.Where(step)), { indent = 6, onClick = function() Bag.Link(step) end,
                tip = function(tip)
                    tip:SetText(Bag.Name(step), 1, 1, 1)
                    if step.tip then tip:AddLine(step.tip, 1, 1, 1, true) end
                end })
        end
    end
    return any
end

local function TrackerRefresh()
    trackerQueued = false
    if not TrackerWanted() then
        if tracker then tracker:Hide() end
        return
    end
    local zone = PlayerZone()
    if zone ~= dismissedZone then dismissedZone = nil end
    if dismissedZone and not CludesUI._unlockActive then
        if tracker then tracker:Hide() end
        return
    end
    if not tracker then BuildTracker() end
    if not CludesUI._unlockActive then F.Place(tracker) end
    local any = FillTracker(zone)
    if not any and not CludesUI._unlockActive then tracker:Hide() return end
    tracker:SetHeight(trackerRows:Height() + 32)
    tracker:Show()
end

local function TrackerSoon()
    if trackerQueued then return end
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

local function PinsWanted() return On() and (Get("mapPins") or Get("bagMapPins")) end

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

local function Pin(x, y, icon, tip, onClick)
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
        p:SetScript("OnLeave", function() GameTooltip:Hide() end)
        p:SetScript("OnClick", function(self) if self.onClick then self.onClick() end end)
        if not InCombatLockdown() then p:SetPassThroughButtons("RightButton") end
        pins[pinsUsed] = p
    end
    local size = Get("pinSize")
    p:SetSize(size, size)
    p.x, p.y = x / 100, y / 100
    p.icon:SetTexture(icon)
    p.tip, p.onClick = tip, onClick
    Anchor(p)
    p:Show()
end

local function DrawPins()
    ClearPins()
    if not PinsWanted() then return end
    local mapID = WorldMapFrame:GetMapID()
    if not mapID then return end
    if Get("mapPins") then
        for _, item in ipairs(Library.Spots(mapID, "find")) do
            local book, spot = item[1], item[2]
            Pin(spot[SPOT_X], spot[SPOT_Y], C_Item.GetItemIconByID(book.item) or "Interface\\Icons\\INV_Misc_Book_11",
                BookTip(book, spot), function() Library.LinkBook(book, spot) end)
        end
        if Get("mapTurnIn") then
            local counts = {}
            for _, book in ipairs(Data().LibraryBooks) do
                if Library.ForMe(book) and Library.Stored(book) then
                    local kind = book.turnIn or TURN_IN
                    counts[kind] = (counts[kind] or 0) + 1
                end
            end
            for kind, n in pairs(counts) do
                local npc = Data().LibraryTurnIns[kind][Side()]
                if npc.map == mapID then
                    Pin(npc.x, npc.y, "Interface\\Icons\\INV_Misc_Book_07", function(tip)
                        tip:SetText(npc.name, 1, 1, 1)
                        tip:AddLine(n == 1 and "Takes the book you carry." or ("Takes the %d books you carry."):format(n), unpack(GOLD))
                    end, function() Link(npc.name, npc.map, npc.x, npc.y) end)
                end
            end
        end
    end
    if Get("bagMapPins") and Bag.Level() and not Bag.Owned() then
        local step = Bag.Current()
        if step and step.map == mapID then
            Pin(step.x, step.y, "Interface\\Icons\\INV_Misc_Bag_08", function(tip)
                tip:SetText(Bag.Name(step), 1, 1, 1)
                tip:AddLine("Cozy Sleeping Bag, next step", unpack(GOLD))
                tip:AddLine(Bag.Where(step), unpack(MUTED))
                if step.tip then tip:AddLine(step.tip, 1, 1, 1, true) end
            end, function() Bag.Link(step) end)
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
--  Events and apply
-------------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        NearRefresh()
    elseif event == "BAG_UPDATE_DELAYED" or event == "QUEST_TURNED_IN" or event == "QUEST_LOG_UPDATE" then
        if event ~= "QUEST_LOG_UPDATE" then NearRefresh() end
        if added and WorldMapFrame:IsShown() then DrawPins() end
    end
    TrackerSoon()
    RedrawSoon()
end)

local function Apply()
    ev:UnregisterAllEvents()
    if On() then
        for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "BAG_UPDATE_DELAYED", "QUEST_TURNED_IN",
                             "QUEST_LOG_UPDATE", "PLAYER_LEVEL_UP" }) do
            ev:RegisterEvent(e)
        end
    end
    NearRefresh()
    FieldApply()
    PinsApply()
    TrackerRefresh()
    if module.QuestListApply then module.QuestListApply() end
end

SLASH_CUIDISCOVERY1 = "/cdiscovery"
SlashCmdList.CUIDISCOVERY = function(msg)
    if not On() then Print("turn on Discovery in CludesUI Forever Tools first.") return end
    msg = (msg or ""):lower()
    if win and win:IsShown() and msg == "" then win:Hide() return end
    OpenWindow(tabs[msg] and msg or nil)
end

CludesUI._Discovery = { Get = Get, Cfg = F.Cfg, Apply = Apply, Open = OpenWindow }
module.DiscoveryFeature = F
module.DiscoveryOpen = OpenWindow

F.Start(Apply, {
    key = "CUI_DiscoveryTracker", label = "Discovery Tracker", order = 756,
    shown = function() return TrackerWanted() end,
    frame = function(build)
        if build and not tracker then BuildTracker() end
        if build then
            FillTracker(PlayerZone())
            tracker:SetHeight(trackerRows:Height() + 32)
        end
        return tracker
    end,
    size = function() return TRACK_W, tracker and tracker:GetHeight() or 60 end,
    noAnchorTarget = true, noSizeMatchTarget = true,
})
