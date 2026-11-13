if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if not (CludesUI and CludesUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_Auction.lua  (WoW Forever only)
--  Auction Prices: the lowest buyout of every item, per realm and faction.
--  Prices come from the release's snapshot of every Forever auction house
--  (CludesUIForeverEssentials_AuctionFeed.lua) until you scan: a Scan Prices
--  button on the auction house reads every listing (Blizzard allows one fast
--  scan every 15 minutes; between them it reads page by page), and full
--  scans other addons start are kept too. Which house is yours is matched
--  from your own scan; until then a price is the middle of your faction's.
--  Item tooltips show the price and its age, Junk Items and the Loot Feed
--  price with it when Auctionator is not installed, and a Market panel
--  beside the auction house has your Watch List (/cwatch) and what your
--  bags would fetch.
-------------------------------------------------------------------------------
local _, module = ...

local F = module.Feature("auction", {
    enabled = false, scanButton = true, tooltip = true, capture = true, autoScan = false, autoMinutes = 30,
    panel = true,
})
local Get, On = F.Get, F.Enabled

local SCAN_COOLDOWN, CHUNK, TIMEOUT, BROWSE_TIMEOUT = 900, 1000, 60, 30
local BLACKWATER = "Blackwater"
local FEED_BASE, FEED_DIGITS = 36, 6
local MATCH_MIN, MATCH_SPREAD = 20, 0.01
local COIN = 12
local function Print(msg) CludesUI.Print("|cff4cc9f0Auction Prices:|r " .. msg) end
local function Coins(copper) return C_CurrencyInfo.GetCoinTextureString(copper, COIN) end
local function Font() return (CludesUI.GetFontPath and CludesUI.GetFontPath()) or STANDARD_TEXT_FONT end

local function Age(seconds)
    if seconds < 3600 then return math.max(1, math.floor(seconds / 60)) .. "m" end
    if seconds < 86400 then return math.floor(seconds / 3600) .. "h" end
    return math.floor(seconds / 86400) .. "d"
end

-------------------------------------------------------------------------------
--  Prices: your own scan, else the release's
-------------------------------------------------------------------------------
local faction, atNeutral = nil, false
local houseKeys = {}
local feedTried, feedHouses, feedTime
local feeds = {}
local decoded, decodedListed = {}, {}

local function Side(other)
    faction = faction or UnitFactionGroup("player")
    if not faction then return end
    if atNeutral ~= (other == true) then return BLACKWATER end
    return faction
end

local function Key(other)
    local side = Side(other)
    local key = side and houseKeys[side]
    if not key then
        key = GetRealmName() .. "-" .. (side or "")
        if side then houseKeys[side] = key end
    end
    return key
end

local function House(create, other)
    local cfg = create and F.Cfg() or F.Read()
    local houses = cfg.houses
    if not houses then
        if not create then return end
        houses = {}
        cfg.houses = houses
    end
    local key = Key(other)
    if create and not houses[key] then houses[key] = { prices = {} } end
    return houses[key]
end

local function FeedHouses(side)
    if not side then return end
    if not feedTried then
        feedTried = true
        local feed = module.AuctionFeedData and module.AuctionFeedData()
        module.AuctionFeedData = nil
        local region = feed and feed.regions[GetCurrentRegion()]
        for id, house in pairs(region or {}) do
            local tag = house.faction
            if (tag == faction or tag == BLACKWATER) and house.prices ~= "" then
                feedHouses = feedHouses or {}
                feedHouses[tag] = feedHouses[tag] or {}
                feedHouses[tag][id] = house.prices
            end
        end
        feedTime = feed and feed.time
    end
    return feedHouses and feedHouses[side]
end

-- tonumber with a base is 32-bit on Windows, so long numbers are read in two parts.
local function Number(text)
    if #text <= FEED_DIGITS then return tonumber(text, FEED_BASE) end
    return tonumber(text:sub(1, -FEED_DIGITS - 1), FEED_BASE) * FEED_BASE ^ FEED_DIGITS
        + tonumber(text:sub(-FEED_DIGITS), FEED_BASE)
end

local function Decode(houses, id)
    if not decoded[id] then
        local prices, listed, item = {}, {}, 0
        for step, price, count in houses[id]:gmatch("(%w+):(%w+):?(%w*)") do
            item = item + Number(step)
            prices[item] = Number(price)
            if count ~= "" then listed[item] = Number(count) end
        end
        decoded[id], decodedListed[id] = prices, listed
    end
    return decoded[id], decodedListed[id]
end

local function Matches(own, feed)
    local count = 0
    for item, price in pairs(own) do
        local other = feed[item]
        if other and math.abs(other - price) <= price * MATCH_SPREAD then count = count + 1 end
    end
    return count
end

local function MatchHouse(house, houses)
    local best, most = false, MATCH_MIN - 1
    for id in pairs(houses) do
        local count = Matches(house.prices, Decode(houses, id))
        if count > most then best, most = id, count end
    end
    return best
end

local function Forget(houses, keep)
    for id in pairs(houses) do
        if id ~= keep then decoded[id], decodedListed[id] = nil, nil end
    end
end

local function Median(houses, feed)
    if not feed.median then
        local all = {}
        for id in pairs(houses) do
            for item, price in pairs(Decode(houses, id)) do
                all[item] = all[item] or {}
                all[item][#all[item] + 1] = price
            end
        end
        local median, medianListed = {}, {}
        for item, list in pairs(all) do
            table.sort(list)
            median[item] = list[math.ceil(#list / 2)]
        end
        for id in pairs(houses) do
            local prices, listed = Decode(houses, id)
            for item, price in pairs(prices) do
                local count = listed[item]
                if price == median[item] and count and count > (medianListed[item] or 0) then medianListed[item] = count end
            end
        end
        Forget(houses)
        feed.median, feed.medianListed = median, medianListed
    end
    return feed.median, feed.medianListed
end

local function FeedPrices(other)
    local side = Side(other)
    local houses = FeedHouses(side)
    if not houses then return end
    local feed = feeds[side]
    if not feed then feed = {}; feeds[side] = feed end
    if feed.matched == nil then
        local house = House(false, other)
        feed.matched = house and house.time and MatchHouse(house, houses) or false
        if feed.matched then
            Forget(houses, feed.matched)
            feed.median, feed.medianListed = nil, nil
        end
    end
    if feed.matched then return Decode(houses, feed.matched) end
    return Median(houses, feed)
end

local function Matched(other)
    local feed = feeds[Side(other)]
    return feed and feed.matched
end

-- The middle of every house may be other realms', so it never outranks a scan of your own.
local function FeedFirst(at, other)
    return not at or Matched(other) and at < feedTime
end

local function Lookup(itemID, other)
    local house = House(false, other)
    local feed, listed = FeedPrices(other)
    local own = house and house.prices[itemID]
    local at = own and (house.seen and house.seen[itemID] or house.time)
    if feed and feed[itemID] and FeedFirst(at, other) then
        return feed[itemID], feedTime, listed and listed[itemID]
    end
    if at then return own, at, house.listed and house.listed[itemID] end
end

local function ItemID(item)
    if type(item) == "number" then return item end
    if type(item) ~= "string" or (issecretvalue and issecretvalue(item)) then return end
    return (C_Item.GetItemInfoInstant(item))
end

--- The lowest buyout of one, and when it was seen (server time).
function module.MarketPrice(item)
    if not On() then return end
    local id = ItemID(item)
    if not id then return end
    local price, at = Lookup(id)
    return price, at
end

local function ScanTime()
    local house, feed = House(), FeedPrices()
    if feed and FeedFirst(house and house.time) then return feedTime, true end
    return house and house.time, false
end

local function Summary()
    local at, fromFeed = ScanTime()
    if not at then return "no prices yet for this realm and faction." end
    local house = House()
    local count = 0
    for _ in pairs(fromFeed and (FeedPrices() or {}) or (house and house.prices or {})) do count = count + 1 end
    return ("%s from %s ago: %s items priced."):format(fromFeed and "release prices" or "your last scan",
        Age(GetServerTime() - at), BreakUpLargeNumbers(count))
end

-------------------------------------------------------------------------------
--  Scanning
-------------------------------------------------------------------------------
local BROWSE_EVENTS = { "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_RESULTS_ADDED",
    "AUCTION_HOUSE_BROWSE_FAILURE", "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" }
local scanning, scanGen, ownScan, houseOpen, hooked = nil, 0, nil, nil, nil
local browsing, browseHooked, browseSent, browseSending, browseWaiting
local browseCount = 0
local button
local events = CreateFrame("Frame")
local OnScanned

local function Label(text) if button then button:SetText(text) end end

local function Wait()
    local house = House()
    local last = house and house.requested
    return last and SCAN_COOLDOWN - (GetServerTime() - last)
end

local function EndBrowse()
    browsing, browseWaiting = nil, nil
    for _, event in ipairs(BROWSE_EVENTS) do events:UnregisterEvent(event) end
end

local function Stop(message)
    scanning = nil
    scanGen = scanGen + 1
    events:UnregisterEvent("REPLICATE_ITEM_LIST_UPDATE")
    EndBrowse()
    Label("Scan Prices")
    if message and ownScan then Print(message) end
    ownScan = nil
end

local function ReadListing(prices, listed, i)
    local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = C_AuctionHouse.GetReplicateItemInfo(i)
    if not (itemID and buyout and buyout > 0 and count and count > 0) then return end
    local each = math.floor(buyout / count)
    if not prices[itemID] or each < prices[itemID] then prices[itemID] = each end
    listed[itemID] = (listed[itemID] or 0) + 1
end

local function ReadRow(prices, listed, i, rows)
    local row = rows[i + 1]
    local price = row.minPrice
    if price <= 0 then return end
    local itemID = row.itemKey.itemID
    if not prices[itemID] or price < prices[itemID] then prices[itemID] = price end
    listed[itemID] = (listed[itemID] or 0) + row.totalQuantity
end

local function Finish(prices, listed)
    local house = House(true)
    house.prices, house.listed, house.time, house.seen = prices, listed, GetServerTime(), nil
    local feed = feeds[Side()]
    if feed then feed.matched = nil end
    Stop()
    Print(Summary())
    if OnScanned then OnScanned() end
end

local function ReadAll(total, ReadOne, rows)
    scanning = true
    scanGen = scanGen + 1
    if total == 0 then return Stop("the auction house returned no listings. Try again in a moment.") end
    local prices, listed, index, gen = {}, {}, 0, scanGen
    local function Step()
        if gen ~= scanGen then return end
        local last = math.min(index + CHUNK, total) - 1
        for i = index, last do ReadOne(prices, listed, i, rows) end
        index = last + 1
        if index < total then
            Label(("Scanning %d%%"):format(math.floor(index * 100 / total)))
            C_Timer.After(0, Step)
            return
        end
        Finish(prices, listed)
    end
    Step()
end

local function Read()
    events:UnregisterEvent("REPLICATE_ITEM_LIST_UPDATE")
    EndBrowse()
    House(true).requested = GetServerTime()
    ReadAll(C_AuctionHouse.GetNumReplicateItems(), ReadListing)
end

local BROWSE_QUERY
local function Ask()
    scanGen = scanGen + 1
    local gen = scanGen
    C_Timer.After(BROWSE_TIMEOUT, function()
        if gen == scanGen and browsing then Stop("scan stopped: no answer from the auction house. Try again in a moment.") end
    end)
    browseWaiting = not C_AuctionHouse.IsThrottledMessageSystemReady()
    if browseWaiting then return end
    if browseSent then return C_AuctionHouse.RequestMoreBrowseResults() end
    browseSent, browseSending = true, true
    C_AuctionHouse.SendBrowseQuery(BROWSE_QUERY)
    browseSending = nil
end

local function OnBrowsed(added)
    if browseSending or not browseSent then return end
    if C_AuctionHouse.HasFullBrowseResults() then
        EndBrowse()
        local rows = C_AuctionHouse.GetBrowseResults()
        return ReadAll(#rows, ReadRow, rows)
    end
    browseCount = added and browseCount + #added or #C_AuctionHouse.GetBrowseResults()
    Label(("%d items"):format(browseCount))
    Ask()
end

local function Browse(message)
    if not BROWSE_QUERY then
        BROWSE_QUERY = {
            searchString = "",
            sorts = { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false },
                { sortOrder = Enum.AuctionHouseSortOrder.Name, reverseSort = false } },
            filters = { Enum.AuctionHouseFilter.PoorQuality, Enum.AuctionHouseFilter.CommonQuality,
                Enum.AuctionHouseFilter.UncommonQuality, Enum.AuctionHouseFilter.RareQuality,
                Enum.AuctionHouseFilter.EpicQuality, Enum.AuctionHouseFilter.LegendaryQuality },
        }
    end
    if not browseHooked then
        browseHooked = true
        local function Other() if browsing and not browseSending then Stop("scan stopped: another search took its place.") end end
        hooksecurefunc(C_AuctionHouse, "SendBrowseQuery", Other)
        if C_AuctionHouse.SearchForFavorites then hooksecurefunc(C_AuctionHouse, "SearchForFavorites", Other) end
    end
    scanning, ownScan, browsing = true, true, true
    browseSent, browseCount = nil, 0
    Label("Scanning...")
    Print(message)
    for _, event in ipairs(BROWSE_EVENTS) do events:RegisterEvent(event) end
    Ask()
end

local function Scan()
    if scanning then return end
    local wait = Wait()
    if wait and wait > 0 then
        return Browse(("the fast scan is free again in %dm, so this one reads the auction house page by page."):format(math.ceil(wait / 60)))
    end
    scanning, ownScan = true, true
    scanGen = scanGen + 1
    local gen = scanGen
    House(true).requested = GetServerTime()
    Label("Scanning...")
    Print("please wait while the auction house scan completes.")
    events:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE")
    C_AuctionHouse.ReplicateItems()
    C_Timer.After(TIMEOUT, function()
        if gen ~= scanGen or not scanning then return end
        local own = ownScan
        Stop()
        events:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE")
        if own then Browse("no answer from the auction house to the fast scan, so this one reads it page by page.") end
    end)
end

-- A full scan another addon starts: its listings are kept too.
local function HookReplicate()
    if hooked or not Get("capture") then return end
    hooked = true
    hooksecurefunc(C_AuctionHouse, "ReplicateItems", function()
        if (scanning and not browsing) or not (houseOpen and On() and Get("capture")) then return end
        House(true).requested = GetServerTime()
        events:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE")
        if browsing then return end
        scanning = true
        scanGen = scanGen + 1
        local gen = scanGen
        C_Timer.After(TIMEOUT, function() if gen == scanGen and scanning then Stop() end end)
    end)
end

-------------------------------------------------------------------------------
--  Watch List: a chat line after each scan for an item at or under its price
-------------------------------------------------------------------------------
local function Watches()
    local cfg = F.Cfg()
    cfg.watch = cfg.watch or {}
    return cfg.watch
end

local function ItemName(id) return C_Item.GetItemNameByID(id) or ("item " .. id) end

local function CheckWatches()
    for id, target in pairs(Watches()) do
        local price = module.MarketPrice(id)
        if price and price <= target then
            Print(("%s is at %s (your price %s)."):format(select(2, C_Item.GetItemInfo(id)) or ItemName(id), Coins(price), Coins(target)))
        end
    end
end

-- "12g50s", "12g", "50s3c", "1.5" (gold) or plain copper digits with a c.
local function ParseMoney(text)
    text = (text or ""):lower():gsub("%s", "")
    if text == "" then return end
    if text:find("[gsc]") then
        local g = tonumber(text:match("(%d+)g")) or 0
        local s = tonumber(text:match("(%d+)s")) or 0
        local c = tonumber(text:match("(%d+)c")) or 0
        return g * 10000 + s * 100 + c
    end
    local gold = tonumber(text)
    return gold and math.floor(gold * 10000 + 0.5) or nil
end

-------------------------------------------------------------------------------
--  Bag worth: what your bags would fetch at auction
-------------------------------------------------------------------------------
local function BagWorth()
    local total, list, seen = 0, {}, {}
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID and not info.isBound and not (issecretvalue and issecretvalue(info.itemID)) then
                local price = module.MarketPrice(info.itemID)
                if price then
                    local worth = price * (info.stackCount or 1)
                    total = total + worth
                    local e = seen[info.itemID]
                    if not e then e = { id = info.itemID, worth = 0, count = 0 }; seen[info.itemID] = e; list[#list + 1] = e end
                    e.worth, e.count = e.worth + worth, e.count + (info.stackCount or 1)
                end
            end
        end
    end
    table.sort(list, function(a, b) return a.worth > b.worth end)
    return total, list
end

-------------------------------------------------------------------------------
--  The Market panel beside the auction house
-------------------------------------------------------------------------------
local panel, panelRows
local PANEL_W = 280

local function DrawPanel()
    if not (panel and panel:IsShown()) then return end
    local R = panelRows
    R:Reset()
    R:Line(Summary(), { colour = { 0.6, 0.65, 0.7 } })
    R:Gap(6)
    R:Line("Watch List", { size = 13, colour = { 1, 0.82, 0 } })
    local any = false
    local ids = {}
    for id in pairs(Watches()) do ids[#ids + 1] = id end
    table.sort(ids, function(a, b) return ItemName(a) < ItemName(b) end)
    for _, id in ipairs(ids) do
        any = true
        local target = Watches()[id]
        local price = module.MarketPrice(id)
        local cheap = price and price <= target
        R:Line(ItemName(id) .. "\n" .. "|cff9aa6b2at or under " .. Coins(target) .. "|r", {
            icon = C_Item.GetItemIconByID(id) or 134400,
            right = price and Coins(price) or "no price", rightColour = cheap and { 0.38, 0.85, 0.5 } or { 1, 1, 1 },
            tip = function(tip)
                tip:SetItemByID(id)
                tip:AddLine("Click to search for it. Shift-click to stop watching it.", 0.3, 0.79, 0.94)
            end,
            onClick = function()
                if IsShiftKeyDown() then
                    Watches()[id] = nil
                    DrawPanel()
                elseif AuctionHouseFrame and AuctionHouseFrame.SearchBar and AuctionHouseFrame.SearchBar.SearchBox then
                    AuctionHouseFrame.SearchBar.SearchBox:SetText(C_Item.GetItemNameByID(id) or "")
                    if AuctionHouseFrame.SearchBar.StartSearch then AuctionHouseFrame.SearchBar:StartSearch() end
                end
            end })
    end
    if not any then R:Line("Nothing watched. Type /cwatch, Shift-click an item into it and give a price (12g50s).", { colour = { 0.6, 0.65, 0.7 } }) end
    R:Gap(6)
    local total, list = BagWorth()
    R:Line("Your Bags", { size = 13, colour = { 1, 0.82, 0 }, right = Coins(total) })
    for i = 1, math.min(8, #list) do
        local e = list[i]
        R:Line(ItemName(e.id) .. (e.count > 1 and (" |cff9aa6b2x" .. e.count .. "|r") or ""), { icon = C_Item.GetItemIconByID(e.id) or 134400,
            right = Coins(e.worth), tip = function(tip) tip:SetItemByID(e.id) end })
    end
    panel:SetHeight(math.min(600, R:Height() + 66))
end

local function BuildPanel()
    local house = _G.AuctionHouseFrame
    panel = CreateFrame("Frame", "CludesUIMarketPanel", house, "BackdropTemplate")
    panel:SetSize(PANEL_W, 300)
    panel:SetPoint("TOPLEFT", house, "TOPRIGHT", 4, 0)
    panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    panel:SetBackdropColor(0.06, 0.07, 0.09, 0.95)
    panel:SetBackdropBorderColor(0.30, 0.79, 0.94, 0.8)
    local title = panel:CreateFontString(nil, "OVERLAY")
    title:SetFont(Font(), 14, "OUTLINE")
    title:SetPoint("TOPLEFT", 10, -8)
    title:SetText("|cff4cc9f0Market|r")
    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() panel:Hide() end)
    button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    button:SetSize(130, 22)
    button:SetPoint("TOPLEFT", 10, -30)
    button:SetText("Scan Prices")
    button:SetScript("OnClick", Scan)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Scan Prices", 1, 1, 1)
        GameTooltip:AddLine("Keeps the lowest buyout of every item, shown on item tooltips. Blizzard allows one fast scan every 15 minutes; between them it reads page by page.", 0.3, 0.79, 0.94, true)
        GameTooltip:AddLine(Summary(), 0.6, 0.65, 0.7, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local body = CreateFrame("Frame", nil, panel)
    body:SetPoint("TOPLEFT", 10, -58)
    body:SetSize(PANEL_W - 20, 10)
    panelRows = module.DiscoveryRows and module.DiscoveryRows(body)
end

local function ShowPanel()
    if not (_G.AuctionHouseFrame and Get("panel")) then return end
    if not panel then BuildPanel() end
    panel:Show()
    DrawPanel()
end

OnScanned = function()
    CheckWatches()
    DrawPanel()
end

-------------------------------------------------------------------------------
--  Tooltip
-------------------------------------------------------------------------------
local tooltipHooked
local function HookTooltip()
    if tooltipHooked then return end
    tooltipHooked = true
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
        if not (On() and Get("tooltip")) then return end
        local id = data and data.id
        if not id or (issecretvalue and issecretvalue(id)) then return end
        local price, at = module.MarketPrice(id)
        if not price then return end
        local age = Age(GetServerTime() - at)
        tooltip:AddDoubleLine("|cff4cc9f0Market Price|r", Coins(price) .. " |cff808080each, " .. age .. " ago|r", 1, 1, 1, 1, 1, 1)
        local watch = F.Read().watch and F.Read().watch[id]
        if watch then tooltip:AddDoubleLine("|cff9aa6b2Watching at|r", Coins(watch), 1, 1, 1, 1, 1, 1) end
    end)
end

-------------------------------------------------------------------------------
--  Events, apply, /cwatch
-------------------------------------------------------------------------------
events:SetScript("OnEvent", function(_, event, added)
    if event == "AUCTION_HOUSE_SHOW" then
        houseOpen = true
        atNeutral = UnitExists("npc") and UnitFactionGroup("npc") ~= UnitFactionGroup("player")
            and C_PvP.GetZonePVPInfo() ~= "friendly" or false
        ShowPanel()
        if Get("autoScan") then
            C_Timer.After(1, function()
                local house = House()
                local at = house and house.time
                if houseOpen and not scanning and not (at and GetServerTime() - at < Get("autoMinutes") * 60) then Scan() end
            end)
        end
    elseif event == "AUCTION_HOUSE_CLOSED" then
        houseOpen = nil
        Stop(scanning and "scan stopped: the auction house closed.")
        atNeutral = false
    elseif event == "REPLICATE_ITEM_LIST_UPDATE" then
        Read()
    elseif event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
        if browseWaiting then Ask() end
    elseif event == "AUCTION_HOUSE_BROWSE_FAILURE" then
        Stop("scan stopped: no answer from the auction house. Try again in a moment.")
    elseif event == "BAG_UPDATE_DELAYED" then
        DrawPanel()
    else
        OnBrowsed(event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" and added)
    end
end)

local function Apply()
    events:UnregisterEvent("AUCTION_HOUSE_SHOW")
    events:UnregisterEvent("AUCTION_HOUSE_CLOSED")
    events:UnregisterEvent("BAG_UPDATE_DELAYED")
    if not On() then
        if panel then panel:Hide() end
        return
    end
    events:RegisterEvent("AUCTION_HOUSE_SHOW")
    events:RegisterEvent("AUCTION_HOUSE_CLOSED")
    events:RegisterEvent("BAG_UPDATE_DELAYED")
    HookReplicate()
    HookTooltip()
    if houseOpen then ShowPanel() end
end

SLASH_CUIWATCH1 = "/cwatch"
SlashCmdList.CUIWATCH = function(msg)
    if not On() then Print("turn on Auction Prices in CludesUI Forever Tools first.") return end
    msg = msg or ""
    local link = msg:match("|H(item:[^|]+)|h")
    local id = link and tonumber(link:match("item:(%d+)")) or tonumber(msg:match("^%s*(%d+)"))
    if not id then
        local n = 0
        for wid, target in pairs(Watches()) do
            n = n + 1
            local price = module.MarketPrice(wid)
            Print(("%s at or under %s, now %s"):format(ItemName(wid), Coins(target), price and Coins(price) or "no price"))
        end
        if n == 0 then Print("type /cwatch, Shift-click an item, and add a price (12g50s). /cwatch <item> off stops watching it.") end
        return
    end
    local rest = msg:gsub("|c%x+|H.-|h.-|h|r", ""):gsub("^%s*%d+%s*", "", link and 0 or 1)
    rest = strtrim(rest)
    if rest:lower() == "off" then
        Watches()[id] = nil
        Print(("stopped watching %s."):format(ItemName(id)))
    else
        local target = ParseMoney(rest) or module.MarketPrice(id)
        if not target then return Print("give it a price, for example /cwatch <item> 12g50s.") end
        Watches()[id] = target
        Print(("watching %s at or under %s."):format(ItemName(id), Coins(target)))
    end
    DrawPanel()
end

CludesUI._Auction = { Get = Get, Cfg = F.Cfg, Apply = Apply, Summary = Summary }

F.Start(Apply)
