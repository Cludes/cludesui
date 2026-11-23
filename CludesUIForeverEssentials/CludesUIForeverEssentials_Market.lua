if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
if not (CUI and CUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_Market.lua  (WoW Forever only)
--  The Market, part one: auction prices. A Scan Prices button on the auction
--  house reads every listing (the game allows one such scan every 15
--  minutes) and keeps each item's lowest buyout and how many are up, for
--  this realm and faction (the neutral houses kept apart). Your own searches
--  and other addons' full scans keep prices fresh too. Item tooltips show the
--  price and its age, and Loot Feed, Junk Items and the recipe window use it
--  when Auctionator is not there.
-------------------------------------------------------------------------------
local _, module = ...

local F = module.Feature("market", {
    enabled = false,
    tooltip = true,
    autoScan = false,
    autoMinutes = 30,
    capture = true,
    panel = true,
    undercutAlert = true,
    duration = 2,
})
local Get, On = F.Get, F.Enabled

local COOLDOWN, TIMEOUT, CHUNK = 900, 60, 1000
local NEUTRAL = "Neutral"

local Market = {}
local state = { neutral = false }
local button
local events = CreateFrame("Frame")

local function Tag() return CUI.HexColor(CUI.Kit.Accent()) .. "CludesUI Market|r: " end
local function Say(text) CUI.Print(Tag() .. text) end

-------------------------------------------------------------------------------
--  The store: CludesUIDB.market.houses["Realm-Faction"] =
--    { time, requested, prices = { [itemID] = copper }, listed = { [itemID] = n },
--      seen = { [itemID] = time } }   (seen: priced since the last full scan)
-------------------------------------------------------------------------------
local function Key(neutral)
    local side = neutral and NEUTRAL or UnitFactionGroup("player")
    return side and (GetRealmName() .. "-" .. side)
end

function Market.House(create, neutral)
    if neutral == nil then neutral = state.neutral end
    local key = Key(neutral)
    if not key then return end
    local conf = create and F.Cfg() or F.Read()
    local houses = conf.houses
    if not houses then
        if not create then return end
        houses = {}
        conf.houses = houses
    end
    if create and not houses[key] then houses[key] = { prices = {}, listed = {} } end
    return houses[key]
end

-- Lowest buyout for one, and when it was seen (your own faction's house
-- away from the auction house; the one you stand at while there).
function Market.Price(itemID)
    local house = itemID and Market.House(false)
    local price = house and house.prices[itemID]
    if not price then return end
    return price, house.seen and house.seen[itemID] or house.time
end

-- A price seen just now (the Market panel's listings): this house's price.
function Market.Seen(itemID, price)
    local house = Market.House(true)
    house.seen = house.seen or {}
    house.prices[itemID], house.seen[itemID] = price, GetServerTime()
end

function Market.Listed(itemID)
    local house = itemID and Market.House(false)
    return house and house.listed and house.listed[itemID]
end

function Market.Age(seconds)
    if seconds < 3600 then return math.max(1, math.floor(seconds / 60)) .. "m" end
    if seconds < 86400 then return math.floor(seconds / 3600) .. "h" end
    return math.floor(seconds / 86400) .. "d"
end

function Market.Summary()
    local house = Market.House(false)
    if not (house and house.time) then return "No scan yet for this realm and faction." end
    local count = 0
    for _ in pairs(house.prices) do
        count = count + 1
    end
    return ("Last scan %s ago: %s items priced."):format(
        Market.Age(GetServerTime() - house.time),
        BreakUpLargeNumbers and BreakUpLargeNumbers(count) or count
    )
end

-- Seconds until the game allows the next full scan here (0 when free).
function Market.Wait()
    local house = Market.House(false)
    local last = house and house.requested
    return last and math.max(0, COOLDOWN - (GetServerTime() - last)) or 0
end

-------------------------------------------------------------------------------
--  The full scan
-------------------------------------------------------------------------------
local function Label(text)
    if button then button:SetText(text) end
end

local function ShowAge()
    if not (button and button.age) then return end
    local house = Market.House(false)
    button.age:SetText(
        house and house.time and ("Last scan %s ago"):format(Market.Age(GetServerTime() - house.time))
            or "No scan yet"
    )
end

local function Stop(message)
    state.scanning, state.gen = nil, (state.gen or 0) + 1
    events:UnregisterEvent("REPLICATE_ITEM_LIST_UPDATE")
    Label("Scan Prices")
    if message and state.own then Say(message) end
    state.own = nil
end

local function Finish(prices, listed)
    local house = Market.House(true)
    house.prices, house.listed, house.time, house.seen = prices, listed, GetServerTime(), nil
    local own = state.own
    Stop()
    ShowAge()
    if own then Say(Market.Summary()) end
    if CUI._RecipeWindow then CUI._RecipeWindow.Render() end
end

-- Read the scan a chunk a frame, so a big house does not freeze the game.
local function Read()
    events:UnregisterEvent("REPLICATE_ITEM_LIST_UPDATE")
    local total = C_AuctionHouse.GetNumReplicateItems() or 0
    if total == 0 then return Stop("The auction house sent no listings. Try again in a moment.") end
    state.scanning, state.gen = true, (state.gen or 0) + 1
    local gen, prices, listed, index = state.gen, {}, {}, 0
    local function Step()
        if gen ~= state.gen then return end
        local last = math.min(index + CHUNK, total) - 1
        for at = index, last do
            local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID =
                C_AuctionHouse.GetReplicateItemInfo(at)
            if itemID and buyout and buyout > 0 and count and count > 0 then
                local each = math.floor(buyout / count)
                if not prices[itemID] or each < prices[itemID] then prices[itemID] = each end
                listed[itemID] = (listed[itemID] or 0) + count
            end
        end
        index = last + 1
        if index < total then
            Label(("Scanning %d%%"):format(math.floor(index * 100 / total)))
            C_Timer.After(0, Step)
        else
            Finish(prices, listed)
        end
    end
    Step()
end

local function Waiting(gen)
    C_Timer.After(TIMEOUT, function()
        if gen == state.gen and state.scanning then Stop("No answer from the auction house. Try again in a moment.") end
    end)
end

function Market.Scan()
    if state.scanning or not state.open then return end
    local wait = Market.Wait()
    if wait > 0 then
        return Say(("The game allows the next full scan in %dm."):format(math.ceil(wait / 60)))
    end
    state.scanning, state.own, state.gen = true, true, (state.gen or 0) + 1
    Market.House(true).requested = GetServerTime()
    Label("Scanning...")
    Say("scanning the auction house, this takes a moment.")
    events:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE")
    state.asking = true
    C_AuctionHouse.ReplicateItems()
    state.asking = nil
    Waiting(state.gen)
end

-- Another addon's full scan: keep its prices too.
local function OnOtherScan()
    if state.asking or state.scanning or not (state.open and On() and Get("capture")) then return end
    Market.House(true).requested = GetServerTime()
    state.scanning, state.gen = true, (state.gen or 0) + 1
    events:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE")
    Waiting(state.gen)
end

-- Your own searches: each result row is that item's cheapest listing now.
local function OnBrowse()
    if not On() then return end
    local rows = C_AuctionHouse.GetBrowseResults and C_AuctionHouse.GetBrowseResults()
    if not (rows and #rows > 0) then return end
    local house, now = Market.House(true), GetServerTime()
    house.seen = house.seen or {}
    house.listed = house.listed or {}
    for _, row in ipairs(rows) do
        local itemID = row.itemKey and row.itemKey.itemID
        if itemID and (row.minPrice or 0) > 0 then
            house.prices[itemID], house.seen[itemID] = row.minPrice, now
            if row.totalQuantity then house.listed[itemID] = row.totalQuantity end
        end
    end
end

-------------------------------------------------------------------------------
--  The button on the auction house, after its last tab
-------------------------------------------------------------------------------
local function ShowButton()
    local frame = rawget(_G, "AuctionHouseFrame")
    if not frame then return end
    if not button then
        button = CUI.Kit.Button(frame, "Scan Prices", 120, 24, function() Market.Scan() end, {
            key = "essentials",
            tip = "Reads every listing and keeps each item's lowest buyout, shown on item tooltips. The game allows one full scan every 15 minutes.",
        })
        button.age = button:CreateFontString(nil, "OVERLAY")
        CUI.Kit.Font(button.age, 11, "essentials")
        button.age:SetTextColor(0.64, 0.68, 0.71)
        button.age:SetPoint("LEFT", button, "RIGHT", 8, 0)
    end
    button:ClearAllPoints()
    local tab = frame.AuctionsTab
    if tab then
        button:SetPoint("LEFT", tab, "RIGHT", 8, 0)
    else
        button:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", -8, -4)
    end
    button:SetShown(On())
    ShowAge()
end

-------------------------------------------------------------------------------
--  Tooltips (Auctionator adds its own, so ours step aside while it is there)
-------------------------------------------------------------------------------
local function Coins(copper)
    local fn = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or GetCoinTextureString
    return fn and fn(copper, 12) or tostring(copper)
end

function Market.TooltipLine(itemID)
    local price, at = Market.Price(itemID)
    if not price then return end
    return Coins(price) .. (" |cff808080each, %s ago|r"):format(Market.Age(GetServerTime() - at))
end

local tooltipHooked = false
local function OnTooltip(tooltip, data)
    if not (On() and Get("tooltip")) or module.AuctionAPI() then return end
    local itemID = data and data.id
    if type(itemID) ~= "number" then return end
    local line = Market.TooltipLine(itemID)
    if line then
        local r, g, b = CUI.Kit.Accent()
        tooltip:AddDoubleLine("Auction", line, r, g, b, 1, 1, 1)
    end
end

local function HookTooltip()
    if tooltipHooked or not (TooltipDataProcessor and Enum.TooltipDataType) then return end
    tooltipHooked = true
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnTooltip)
end

-------------------------------------------------------------------------------
--  Events
-------------------------------------------------------------------------------
local hooked = false
events:SetScript("OnEvent", function(_, event)
    if event == "AUCTION_HOUSE_SHOW" then
        state.open = true
        -- A neutral house: its auctioneer is of neither faction, outside your own lands.
        state.neutral = UnitExists("npc")
            and UnitFactionGroup("npc") ~= UnitFactionGroup("player")
            and C_PvP.GetZonePVPInfo() ~= "friendly"
            or false
        if not hooked and C_AuctionHouse.ReplicateItems then
            hooked = true
            hooksecurefunc(C_AuctionHouse, "ReplicateItems", OnOtherScan)
        end
        ShowButton()
        if Get("autoScan") then
            C_Timer.After(1, function()
                local house = Market.House(false)
                local old = not (house and house.time) or GetServerTime() - house.time > Get("autoMinutes") * 60
                if state.open and old and Market.Wait() == 0 then Market.Scan() end
            end)
        end
    elseif event == "AUCTION_HOUSE_CLOSED" then
        if state.scanning then Stop("Scan stopped: the auction house closed.") end
        state.open, state.neutral = false, false
    elseif event == "REPLICATE_ITEM_LIST_UPDATE" then
        Read()
    else
        OnBrowse()
    end
end)

local function Apply()
    if CUI._MarketPanel then CUI._MarketPanel.Apply() end
    events:UnregisterAllEvents()
    if button then button:SetShown(On() and state.open == true) end
    if not On() then return end
    for _, event in ipairs({
        "AUCTION_HOUSE_SHOW",
        "AUCTION_HOUSE_CLOSED",
        "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED",
        "AUCTION_HOUSE_BROWSE_RESULTS_ADDED",
    }) do
        pcall(events.RegisterEvent, events, event)
    end
    if state.scanning then events:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE") end
    HookTooltip()
end

module.Market = Market
CUI._Market = { Get = Get, Cfg = F.Cfg, Apply = Apply, Market = Market }

F.Start(Apply)
