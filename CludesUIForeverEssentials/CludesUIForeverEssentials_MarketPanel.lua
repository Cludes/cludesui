if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
if not (CUI and CUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_MarketPanel.lua  (WoW Forever only)
--  The Market, part two: a panel docked to the right of the auction house
--  (The Market on, Market Panel on). The game's own window stays as it is.
--    Sell         what your bags can post, most valuable first. Pick one: its
--                 listings are searched and the price is set one step under
--                 the cheapest that is not yours (or yours, or your scan, or
--                 the game's default from the vendor price). Quantity,
--                 duration, deposit, Post; a warning when a vendor pays more.
--    My Auctions  your auctions, each checked against the listings, one
--                 search at a time: undercut ones first, with Cancel, and a
--                 chat line saying how many are undercut.
--    DE Deals     gear worth more disenchanted than it costs.
--    Shopping     what your RestedXP steps and quest log still want.
-------------------------------------------------------------------------------
local _, module = ...
local Market = module.Market
local MK = CUI._Market
if not (Market and MK) then return end
local Get = MK.Get

local W, H, PAD, ROW = 340, 716, 10, CUI.Kit.ROW_H
local PAGE_H = H - 100 -- the space under the tabs and above the message line
local PALETTE = CUI.Kit.Palette
local MUTED, TEXT = PALETTE.muted, PALETTE.text
local GREEN, RED, AMBER = PALETTE.green, PALETTE.red, PALETTE.amber
local CUT = 0.95
local SEARCH_TIMEOUT, POST_TIMEOUT = 6, 10
local DURATIONS = { { 1, "12h" }, { 2, "24h" }, { 3, "48h" } }

local Panel = { page = "sell" }
local Deals, RenderDeals, BuildDeals -- DE Deals, further down
local Shop, NewRow
local panel

local function Kit() return CUI.Kit end

local function Money(copper)
    copper = math.floor(copper or 0)
    local gold, silver, rest = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if gold > 0 then parts[#parts + 1] = gold .. "g" end
    if silver > 0 then parts[#parts + 1] = silver .. "s" end
    if rest > 0 or #parts == 0 then parts[#parts + 1] = rest .. "c" end
    return table.concat(parts, " ")
end

-- "2g 50s", "75s", "30c", or "2.5" for gold. Anything else gives nil.
local function Parse(text)
    text = (text or ""):lower():gsub("%s", "")
    if text == "" then return end
    local gold = tonumber(text)
    if gold then return math.max(0, math.floor(gold * 10000 + 0.5)) end
    local total = 0
    local rest = text:gsub("([%d%.]+)([gsc])", function(amount, coin)
        total = total + (tonumber(amount) or 0) * (coin == "g" and 10000 or coin == "s" and 100 or 1)
        return ""
    end)
    if rest ~= "" then return end
    return math.floor(total + 0.5)
end

local function Paint(fs, c) fs:SetTextColor(c[1], c[2], c[3]) end

local function Label(parent, size, colour)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    Kit().Font(fs, size, "essentials")
    Paint(fs, colour or TEXT)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    return fs
end

local function Enable(button, on)
    button:SetEnabled(on)
    button:SetAlpha(on and 1 or 0.45)
end

-------------------------------------------------------------------------------
--  Bags: what the auction house takes, one entry per item
-------------------------------------------------------------------------------
local Bags = { entries = {}, byKey = {} }

function Bags.Read()
    wipe(Bags.entries)
    wipe(Bags.byKey)
    local loading = false
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID and not info.isBound then
                local here = ItemLocation:CreateFromBagAndSlot(bag, slot)
                if C_AuctionHouse.IsSellItemValid(here, false) then
                    local status = C_AuctionHouse.GetItemCommodityStatus(here)
                    if status == Enum.ItemCommodityStatus.Unknown then
                        loading = true
                        C_Item.RequestLoadItemData(here)
                    else
                        local commodity = status == Enum.ItemCommodityStatus.Commodity
                        local key = commodity and info.itemID or info.hyperlink
                        local entry = Bags.byKey[key]
                        if not entry then
                            entry = {
                                key = key,
                                itemID = info.itemID,
                                link = info.hyperlink,
                                icon = info.iconFileID,
                                commodity = commodity,
                                bag = bag,
                                slot = slot,
                                count = 0,
                            }
                            Bags.byKey[key] = entry
                            Bags.entries[#Bags.entries + 1] = entry
                        end
                        entry.count = entry.count + (info.stackCount or 1)
                    end
                end
            end
        end
    end
    return loading
end

-- A bag slot holding the entry now (stacks move), as an ItemLocation.
function Bags.Location(entry)
    local function Holds(bag, slot)
        local info = C_Container.GetContainerItemInfo(bag, slot)
        return info and info.itemID == entry.itemID and not info.isLocked
            and (entry.commodity or info.hyperlink == entry.link)
    end
    if Holds(entry.bag, entry.slot) then return ItemLocation:CreateFromBagAndSlot(entry.bag, entry.slot) end
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            if Holds(bag, slot) then return ItemLocation:CreateFromBagAndSlot(bag, slot) end
        end
    end
end

-------------------------------------------------------------------------------
--  Listings: one item's listings, cheapest first ({ price, quantity, own })
-------------------------------------------------------------------------------
local Listings = { rows = {}, gen = 0 }
local SORT_PRICE = { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } }
local SORT_BUYOUT = { { sortOrder = Enum.AuctionHouseSortOrder.Buyout, reverseSort = false } }

local function ListingsDone(state)
    Listings.state = state
    if state == "listed" and Listings.want then
        local other = Listings.Cheapest()
        if other and Listings.want.itemID then Market.Seen(Listings.want.itemID, other) end
    end
    if Listings.onDone then Listings.onDone() end
end

function Listings.Send()
    local want = Listings.want
    if not want then return end
    if not C_AuctionHouse.IsThrottledMessageSystemReady() then
        Listings.state = "waiting"
        return
    end
    Listings.gen = Listings.gen + 1
    local gen = Listings.gen
    Listings.state = "searching"
    if want.commodity then
        C_AuctionHouse.SendSearchQuery(C_AuctionHouse.MakeItemKey(want.itemID), SORT_PRICE, true)
    else
        local key = want.itemKey
        if not key then
            local location = want.bag and Bags.Location(want)
            key = location and C_AuctionHouse.GetItemKeyFromItem(location)
        end
        if not key then return ListingsDone("listed") end
        C_AuctionHouse.SendSearchQuery(key, SORT_BUYOUT, true)
    end
    C_Timer.After(SEARCH_TIMEOUT, function()
        if gen == Listings.gen and Listings.state == "searching" then ListingsDone("noanswer") end
    end)
end

function Listings.Want(entry, onDone)
    Listings.want, Listings.onDone = entry, onDone
    wipe(Listings.rows)
    Listings.state = nil
    if entry then Listings.Send() end
end

local function ReadCommodities(itemID)
    wipe(Listings.rows)
    for index = 1, math.min(C_AuctionHouse.GetNumCommoditySearchResults(itemID) or 0, 50) do
        local r = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, index)
        if r then
            Listings.rows[#Listings.rows + 1] =
                { price = r.unitPrice, quantity = r.quantity, own = r.numOwnerItems or 0 }
        end
    end
end

local function ReadItems(itemKey)
    wipe(Listings.rows)
    for index = 1, math.min(C_AuctionHouse.GetNumItemSearchResults(itemKey) or 0, 50) do
        local r = C_AuctionHouse.GetItemSearchResultInfo(itemKey, index)
        if r and r.buyoutAmount then
            local own = r.containsOwnerItem and r.quantity or 0
            local last = Listings.rows[#Listings.rows]
            if last and last.price == r.buyoutAmount then
                last.quantity, last.own = last.quantity + r.quantity, last.own + own
            else
                Listings.rows[#Listings.rows + 1] = { price = r.buyoutAmount, quantity = r.quantity, own = own }
            end
        end
    end
end

function Listings.OnEvent(event, arg)
    local want = Listings.want
    if event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
        if Listings.state == "waiting" then Listings.Send() end
        return
    end
    if not want or Listings.state ~= "searching" then return end
    if event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
        if want.commodity and arg == want.itemID then
            ReadCommodities(arg)
            ListingsDone("listed")
        end
    elseif not want.commodity and type(arg) == "table" and arg.itemID == want.itemID then
        ReadItems(arg)
        ListingsDone("listed")
    end
end

-- The cheapest listing that is not yours, and your cheapest.
function Listings.Cheapest(rows)
    local other, own
    for _, row in ipairs(rows or Listings.rows) do
        if not own and row.own > 0 then own = row.price end
        if not other and row.quantity > row.own then other = row.price end
    end
    return other, own
end

-------------------------------------------------------------------------------
--  Sell: the queue, the suggested price, posting
-------------------------------------------------------------------------------
-- rows/state: the picked item's listings (a copy: My Auctions' checks reuse
-- the one search after them).
local Sell = { queue = {}, priceSet = {}, quantitySet = {}, rows = {} }
local Mine

local function Copper(entry) return entry.commodity and C_AuctionHouse.SupportsCopperValues() end
local function Step(entry) return Copper(entry) and 1 or 100 end
local function Floor(entry, price)
    local step = Step(entry)
    return math.max(step, math.floor(price / step) * step)
end

function Sell.Read()
    local loading = Bags.Read()
    wipe(Sell.queue)
    for _, entry in ipairs(Bags.entries) do
        entry.scan = (Market.Price(entry.itemID))
        entry.vendor = select(11, C_Item.GetItemInfo(entry.itemID)) or 0
        entry.vendorBetter = entry.scan ~= nil and entry.vendor > 0 and entry.vendor >= entry.scan * CUT
        entry.worth = (entry.vendorBetter and entry.vendor or entry.scan or 0) * entry.count
        Sell.queue[#Sell.queue + 1] = entry
    end
    table.sort(Sell.queue, function(lhs, rhs)
        if lhs.vendorBetter ~= rhs.vendorBetter then return not lhs.vendorBetter end
        if (lhs.scan ~= nil) ~= (rhs.scan ~= nil) then return lhs.scan ~= nil end
        if lhs.worth ~= rhs.worth then return lhs.worth > rhs.worth end
        return lhs.itemID < rhs.itemID
    end)
    return loading
end

function Sell.Focus() return Sell.focus and Bags.byKey[Sell.focus] end

-- price, why ("under" | "yours" | "scan" | "vendor"), the price it came from
function Sell.Suggest(entry)
    local other, own = Listings.Cheapest(Sell.rows)
    if other and not (own and own <= other) then
        return Floor(entry, other - Step(entry)), "under", other
    end
    if own then return own, "yours", own end
    if entry.scan then return Floor(entry, entry.scan), "scan", entry.scan end
    local multiplier = Constants and Constants.AuctionConstants
        and Constants.AuctionConstants.DEFAULT_AUCTION_PRICE_MULTIPLIER or 1.5
    return Floor(entry, math.max(entry.vendor, 1) * multiplier), "vendor", entry.vendor
end

function Sell.Price(entry)
    local set = Sell.priceSet[entry.key]
    if set then return set, "hand" end
    return Sell.Suggest(entry)
end

function Sell.Quantity(entry)
    return math.min(Sell.quantitySet[entry.key] or entry.count, entry.count)
end

function Sell.Duration() return Get("duration") or 2 end

function Sell.Deposit(entry, quantity)
    local deposit
    if entry.commodity then
        deposit = C_AuctionHouse.CalculateCommodityDeposit(entry.itemID, Sell.Duration(), quantity)
    else
        local location = Bags.Location(entry)
        deposit = location and C_AuctionHouse.CalculateItemDeposit(location, Sell.Duration(), quantity)
    end
    return deposit
end

function Sell.Pick(key)
    Sell.focus = key
    local entry = Sell.Focus()
    wipe(Sell.rows)
    Sell.state = entry and "searching" or nil
    Mine.checking = nil -- a check cut short runs again after
    Listings.Want(entry, function()
        for index, row in ipairs(Listings.rows) do
            Sell.rows[index] = row
        end
        Sell.state = Listings.state
        Panel.Render()
        Mine.Resume()
    end)
    Panel.Render()
end

-- The next item that is worth posting, after the one on show.
function Sell.Next()
    local start = 0
    for index, entry in ipairs(Sell.queue) do
        if entry.key == Sell.focus then start = index end
    end
    for offset = 1, #Sell.queue do
        local entry = Sell.queue[(start + offset - 1) % #Sell.queue + 1]
        if not entry.vendorBetter and entry.key ~= Sell.focus then return Sell.Pick(entry.key) end
    end
    Sell.Pick(nil)
end

local posting = { gen = 0 }

local function PostDone(ok)
    if not posting.waiting then return end
    posting.waiting, posting.confirm = false, nil
    posting.gen = posting.gen + 1
    if ok then
        local entry = posting.entry
        Panel.posted = (Panel.posted or 0) + posting.quantity * posting.price
        Sell.priceSet[entry.key], Sell.quantitySet[entry.key] = nil, nil
        Panel.message = ("Posted %dx %s at %s each."):format(
            posting.quantity,
            C_Item.GetItemNameByID(entry.itemID) or "item",
            Money(posting.price)
        )
        Sell.Read()
        if Bags.byKey[entry.key] then Sell.Pick(entry.key) else Sell.Next() end
    else
        Panel.message = "The auction house did not take that post."
        Panel.Render()
    end
end

local function PostWait()
    posting.gen = posting.gen + 1
    local gen = posting.gen
    C_Timer.After(POST_TIMEOUT, function()
        if gen == posting.gen then PostDone(false) end
    end)
end

-- The game asks before a post far under the going price: its own popup, and
-- our post goes on only when you accept it there.
local warningHooked = false
local function HookWarning()
    if warningHooked then return end
    local dialog = StaticPopupDialogs and StaticPopupDialogs.AUCTION_HOUSE_POST_WARNING
    if not dialog then return end
    warningHooked = true
    hooksecurefunc(dialog, "OnAccept", function()
        local args = posting.confirm
        if not args then return end
        posting.confirm = nil
        if args.commodity then
            C_AuctionHouse.ConfirmPostCommodity(args.location, args.duration, args.quantity, args.price)
        else
            C_AuctionHouse.ConfirmPostItem(args.location, args.duration, args.quantity, nil, args.price)
        end
        PostWait()
    end)
    hooksecurefunc(dialog, "OnHide", function()
        if posting.confirm then PostDone(false) end
    end)
end

function Sell.Post()
    local entry = Sell.Focus()
    if not entry or posting.waiting or not C_AuctionHouse.IsThrottledMessageSystemReady() then return end
    local location = Bags.Location(entry)
    if not location then return end
    local quantity, price, duration = Sell.Quantity(entry), (Sell.Price(entry)), Sell.Duration()
    local needsConfirm
    if entry.commodity then
        needsConfirm = C_AuctionHouse.PostCommodity(location, duration, quantity, price)
    else
        needsConfirm = C_AuctionHouse.PostItem(location, duration, quantity, nil, price)
    end
    posting.entry, posting.quantity, posting.price = entry, quantity, price
    posting.multisell = not entry.commodity and quantity > 1
    posting.waiting = true
    Panel.message = nil
    if needsConfirm then
        posting.confirm = {
            commodity = entry.commodity,
            location = location,
            duration = duration,
            quantity = quantity,
            price = price,
        }
        HookWarning()
    else
        PostWait()
    end
    Panel.Render()
end

function Sell.OnEvent(event, created, total)
    if not posting.waiting or posting.confirm then return end
    if event == "AUCTION_HOUSE_AUCTION_CREATED" then
        if posting.multisell then PostWait() else PostDone(true) end
    elseif event == "AUCTION_MULTISELL_UPDATE" then
        if created >= total then PostDone(true) else PostWait() end
    elseif event == "AUCTION_MULTISELL_FAILURE" or event == "AUCTION_HOUSE_POST_ERROR" then
        PostDone(false)
    end
end

-------------------------------------------------------------------------------
--  My Auctions: each checked against the listings, one search at a time
-------------------------------------------------------------------------------
Mine = { list = {}, lowest = {}, checked = {}, cancelled = {} }
local SORT_OWNED = {
    { sortOrder = Enum.AuctionHouseSortOrder.Name, reverseSort = false },
    { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false },
}

local function KeyOf(auction)
    local k = auction.itemKey
    if auction.commodity then return k.itemID end
    return k.itemID .. ":" .. (k.itemLevel or 0) .. ":" .. (k.itemSuffix or 0)
end

function Mine.Status(auction)
    if auction.sold then return "sold" end
    if not Mine.checked[auction.key] then return "checking" end
    local low = Mine.lowest[auction.key]
    if low == false then return "noanswer" end
    if low and auction.price and low < auction.price then return "undercut" end
    return "lowest"
end

function Mine.Request()
    Mine.wanted = true
    if not C_AuctionHouse.IsThrottledMessageSystemReady() then return end
    Mine.wanted = false
    C_AuctionHouse.QueryOwnedAuctions(SORT_OWNED)
end

local function CheckNext()
    Mine.checking = nil
    -- The Sell page's search goes first; it resumes the checks when done.
    if Sell.state == "searching" then return end
    for _, auction in ipairs(Mine.list) do
        if not auction.sold and auction.key and not Mine.checked[auction.key] then
            Mine.checking = auction
            break
        end
    end
    if not Mine.checking then
        Listings.Want(nil)
        if not Mine.alerted and #Mine.list > 0 then
            Mine.alerted = true
            local undercut = Mine.Counts()
            if undercut > 0 and Get("undercutAlert") ~= false then
                CUI.Print(
                    CUI.HexColor(Kit().Accent())
                        .. "CludesUI Market|r: "
                        .. (undercut == 1 and "1 of your auctions is undercut." or (undercut .. " of your auctions are undercut."))
                )
            end
        end
        return Panel.Render()
    end
    local auction = Mine.checking
    Listings.Want(
        { itemID = auction.itemID, commodity = auction.commodity, itemKey = auction.itemKey },
        function()
            -- nil: nobody else lists it; false: the search got no answer.
            if Listings.state == "listed" then
                Mine.lowest[auction.key] = (Listings.Cheapest())
            else
                Mine.lowest[auction.key] = false
            end
            Mine.checked[auction.key] = true
            CheckNext()
        end
    )
end

function Mine.Resume()
    if not Mine.checking then CheckNext() end
end

function Mine.Read()
    wipe(Mine.list)
    wipe(Mine.cancelled)
    for index = 1, C_AuctionHouse.GetNumOwnedAuctions() or 0 do
        local info = C_AuctionHouse.GetOwnedAuctionInfo(index)
        if info then
            local keyInfo = C_AuctionHouse.GetItemKeyInfo(info.itemKey)
            local auction = {
                auctionID = info.auctionID,
                itemKey = info.itemKey,
                itemID = info.itemKey.itemID,
                link = info.itemLink,
                quantity = info.quantity,
                price = info.buyoutAmount,
                seconds = info.timeLeftSeconds,
                sold = info.status == Enum.AuctionStatus.Sold,
                commodity = keyInfo and keyInfo.isCommodity,
            }
            auction.key = keyInfo and KeyOf(auction)
            Mine.list[#Mine.list + 1] = auction
        end
    end
    local order = { undercut = 1, checking = 2, noanswer = 3, lowest = 4, sold = 5 }
    table.sort(Mine.list, function(lhs, rhs)
        local a, b = order[Mine.Status(lhs)], order[Mine.Status(rhs)]
        if a ~= b then return a < b end
        return lhs.auctionID < rhs.auctionID
    end)
    if not Mine.checking then CheckNext() end
end

function Mine.Counts()
    local undercut = 0
    for _, auction in ipairs(Mine.list) do
        if Mine.Status(auction) == "undercut" then undercut = undercut + 1 end
    end
    return undercut
end

function Mine.CanCancel(auction)
    return not auction.sold and not Mine.cancelled[auction.auctionID]
        and C_AuctionHouse.CanCancelAuction(auction.auctionID)
end

function Mine.Cancel(auction)
    if not Mine.CanCancel(auction) then return end
    C_AuctionHouse.CancelAuction(auction.auctionID)
    Mine.cancelled[auction.auctionID] = true
    Panel.Render()
end

function Mine.CancelNext()
    for _, auction in ipairs(Mine.list) do
        if Mine.Status(auction) == "undercut" and Mine.CanCancel(auction) then return Mine.Cancel(auction) end
    end
end

function Mine.Start()
    wipe(Mine.lowest)
    wipe(Mine.checked)
    Mine.checking = nil
    Mine.Request()
end

-------------------------------------------------------------------------------
--  DE Deals (Disenchant tools on, Disenchant known): items in your last scan
--  whose average disenchant value after the cut beats their price, best
--  profit first. A click searches it in the game's Buy tab.
-------------------------------------------------------------------------------
Deals = { list = {}, gen = 0, mine = true }
local DEALS_CHUNK, DEALS_TOP = 300, 40

function Deals.On()
    local DE = CUI._Disenchant
    return DE ~= nil and DE.On() and DE.D.Known()
end

local function DealsSkill()
    for _, index in pairs({ GetProfessions() }) do
        local _, _, rank, _, _, _, line, modifier = GetProfessionInfo(index)
        if line == 333 then return (rank or 0) + (modifier or 0) end
    end
end

-- Works through the price list a chunk a frame (item info is the slow part).
function Deals.Find()
    local DE = CUI._Disenchant
    local house = Market.House(false)
    wipe(Deals.list)
    Deals.gen = Deals.gen + 1
    local gen = Deals.gen
    if not (DE and house and house.prices) then
        Deals.state = "noscan"
        return Panel.Render()
    end
    local V, skill = DE.Values, DealsSkill()
    local ids = {}
    for itemID in pairs(house.prices) do
        ids[#ids + 1] = itemID
    end
    Deals.state, Deals.loading, Deals.done, Deals.total = "working", 0, 0, #ids
    local index = 0
    local function Step()
        if gen ~= Deals.gen then return end
        local last = math.min(index + DEALS_CHUNK, #ids)
        for at = index + 1, last do
            local itemID = ids[at]
            local name, link, quality, level, _, _, _, _, equip, icon, _, classID = C_Item.GetItemInfo(itemID)
            if not name then
                local _, _, _, instantEquip, _, instantClass = C_Item.GetItemInfoInstant(itemID)
                if instantClass == 2 or instantClass == 4 then
                    Deals.loading = Deals.loading + 1
                    C_Item.RequestLoadItemDataByID(itemID)
                end
            elseif V.Takes(itemID, classID, quality, equip) then
                local outcomes = V.Outcomes(classID, quality, level)
                local worth = outcomes and V.Expected(outcomes, function(id) return house.prices[id] end)
                local need = V.Skill(level, quality)
                if worth and not (Deals.mine and skill and need and need > skill) then
                    local price = house.prices[itemID]
                    local value = math.floor(worth * CUT)
                    if value > price then
                        Deals.list[#Deals.list + 1] = {
                            itemID = itemID,
                            name = name,
                            link = link,
                            icon = icon,
                            price = price,
                            value = value,
                            profit = value - price,
                            need = need,
                        }
                    end
                end
            end
        end
        index, Deals.done = last, last
        if index < #ids then
            C_Timer.After(0, Step)
        else
            table.sort(Deals.list, function(lhs, rhs)
                if lhs.profit ~= rhs.profit then return lhs.profit > rhs.profit end
                return lhs.itemID < rhs.itemID
            end)
            for at = #Deals.list, DEALS_TOP + 1, -1 do
                Deals.list[at] = nil
            end
            Deals.state = "done"
        end
        Panel.Render()
    end
    Step()
end

-- The game's Buy tab, searching this item by name.
function Deals.Search(deal)
    local house = rawget(_G, "AuctionHouseFrame")
    local bar = house and house.SearchBar
    if not (bar and bar.SetSearchText and bar.StartSearch) then return end
    bar:SetSearchText(deal.name)
    bar:StartSearch()
end

BuildDeals = function(page)
    local K = Kit()
    page.find = K.Button(page, "Find Deals", 110, 24, function() Deals.Find() end, {
        key = "essentials",
        tip = "Goes through your last price scan for gear whose disenchant is worth more, after the cut, than it costs.",
    })
    page.find:SetPoint("TOPLEFT", PAD, -4)
    page.find:SetActive(true)
    page.mineOnly = K.Check(page, "Only what I can disenchant", function(self)
        Deals.mine = self:GetChecked()
        Deals.Find()
    end, "essentials")
    page.mineOnly:SetPoint("LEFT", page.find, "RIGHT", 12, 0)
    page.mineOnly:SetChecked(true)
    page.status = Label(page, CUI.Kit.SMALL_SIZE, MUTED)
    page.status:SetPoint("TOPLEFT", PAD, -36)
    page.status:SetPoint("RIGHT", -PAD, 0)
    page.status:SetWordWrap(true)
    page.rows = {}
end

RenderDeals = function()
    local page = panel.deals
    local status
    if Deals.state == "noscan" then
        status = "Scan Prices first: deals come from your last scan."
    elseif Deals.state == "working" then
        status = ("Working through %d of %d prices..."):format(Deals.done or 0, Deals.total or 0)
    elseif Deals.state == "done" then
        status = (#Deals.list == 0 and "No deals in your last scan." or ("%d deals, best first."):format(#Deals.list))
            .. ((Deals.loading or 0) > 0 and (" %d items still loading: Find again in a moment."):format(Deals.loading) or "")
    else
        status = "Find Deals goes through your last price scan."
    end
    page.status:SetText(status)
    local shown = math.max(0, math.floor((PAGE_H - 70) / ROW))
    for index = 1, math.max(shown, #page.rows) do
        local deal = index <= shown and Deals.list[index] or nil
        local row = page.rows[index]
        if not row and deal then
            row = NewRow(page, index, -64, function(self)
                if self.deal then Deals.Search(self.deal) end
            end)
            page.rows[index] = row
        end
        if row then
            row.deal, row.link = deal, deal and deal.link
            row:SetShown(deal ~= nil)
            if deal then
                row.icon:SetTexture(deal.icon)
                row.name:SetText(deal.name)
                row.right:SetText(("%s  |cff5ec46b+%s|r"):format(Money(deal.price), Money(deal.profit)))
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Shopping (Shopping Tab on): what the current RestedXP steps and your quest
--  log still want, so it can be bought here. A click searches it in the
--  game's Buy tab.
-------------------------------------------------------------------------------
Shop = { list = {} }

function Shop.On() return Get("shopping") ~= false end

-- "Linen Cloth: 3/10" or "3/10 Linen Cloth" -> "Linen Cloth".
local function ObjectiveName(text)
    if type(text) ~= "string" then return end
    local name = text:gsub("%d+%s*/%s*%d+", ""):gsub("^[%s:]+", ""):gsub("[%s:]+$", "")
    return name ~= "" and name or nil
end

local QUEST_ITEM = 12 -- Enum.ItemClass.Questitem

-- One RestedXP step line that wants an item (.buy or .collect): its item and
-- count from the line's own fields, else from its text ("Gorilla Fang: 8/10").
-- nil when it wants nothing or has it all; "loading" while the game loads it.
local function GuideItem(element)
    local tag = type(element.tag) == "string" and element.tag or ""
    if not (tag:find("^buy") or tag:find("^collect")) then return end
    local id = tonumber(element.id or element.itemId or element.itemID)
    local need = tonumber(element.qty or element.count)
    local have
    if not (id and need) then
        local fs = element.frame and element.frame.text
        local shown = fs and fs.GetText and fs:GetText() or element.text
        if type(shown) ~= "string" then return end
        shown = shown:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T[^|]*|t", ""):gsub("|H[^|]*|h", ""):gsub("|h", "")
        local name, got, want = shown:match("^%s*(.-):%s*(%d+)%s*/%s*(%d+)%s*$")
        if not name then return end
        name = name:gsub("^%[", ""):gsub("%]$", "")
        id, have, need = C_Item.GetItemInfoInstant(name), tonumber(got), tonumber(want)
        if not id then return end
    end
    have = C_Item.GetItemCount(id) or have or 0
    if have >= need then return end
    local name, link, _, _, _, _, _, _, _, icon = C_Item.GetItemInfo(id)
    if not name then
        C_Item.RequestLoadItemDataByID(id)
        return "loading"
    end
    return { name = name, link = link, icon = icon, have = have, need = need, from = "Guide" }
end

function Shop.Read()
    local list, seen = {}, {}
    Shop.loading = 0
    local function Add(entry)
        local key = entry.name:lower()
        if seen[key] then return end
        seen[key] = true
        list[#list + 1] = entry
    end
    local rxp = rawget(_G, "RXP")
    local steps = rxp and rxp.RXPFrame and rxp.RXPFrame.activeSteps
    for _, step in ipairs(type(steps) == "table" and steps or {}) do
        if step.active then
            for _, element in ipairs(step.elements or {}) do
                local entry = not element.skip and GuideItem(element)
                if entry == "loading" then
                    Shop.loading = Shop.loading + 1
                elseif entry then
                    Add(entry)
                end
            end
        end
    end
    for index = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(index)
        if info and not info.isHeader and info.questID then
            for _, objective in ipairs(C_QuestLog.GetQuestObjectives(info.questID) or {}) do
                local name = objective.type == "item" and not objective.finished and ObjectiveName(objective.text)
                -- Only items the auction house can sell: quest-only items (a head,
                -- a letter) and items the game does not know yet are left out.
                local itemID, _, _, _, icon, classID = C_Item.GetItemInfoInstant(name or "")
                if name and itemID and classID ~= QUEST_ITEM then
                    local link = select(2, C_Item.GetItemInfo(itemID))
                    Add({ name = name, link = link, icon = icon, have = objective.numFulfilled or 0,
                        need = objective.numRequired or 0, from = "Quest" })
                end
            end
        end
    end
    Shop.list = list
    -- Guide items the game had not loaded yet: read again once it has.
    if Shop.loading > 0 and not Shop.retry then
        Shop.retry = true
        C_Timer.After(1, function()
            Shop.retry = false
            if Panel.page == "shop" then Panel.Render() end
        end)
    end
end

local function BuildShop(page)
    page.status = Label(page, CUI.Kit.SMALL_SIZE, MUTED)
    page.status:SetPoint("TOPLEFT", PAD, -8)
    page.status:SetPoint("RIGHT", -PAD, 0)
    page.status:SetWordWrap(true)
    page.rows = {}
end

local function RenderShop()
    local page = panel.shop
    Shop.Read()
    page.status:SetText(#Shop.list == 0
        and "Nothing to buy: no RestedXP buy step or quest item is waiting."
        or ("%d to buy for your guide and quests. Click one to search for it."):format(#Shop.list))
    local shown = math.max(0, math.floor((PAGE_H - 40) / ROW))
    for index = 1, math.max(shown, #page.rows) do
        local entry = index <= shown and Shop.list[index] or nil
        local row = page.rows[index]
        if not row and entry then
            row = NewRow(page, index, -34, function(self)
                if self.entry then Deals.Search(self.entry) end
            end)
            page.rows[index] = row
        end
        if row then
            row.entry, row.link = entry, entry and entry.link
            row:SetShown(entry ~= nil)
            if entry then
                row.icon:SetTexture(entry.icon)
                row.name:SetText(entry.name)
                row.right:SetText(("|cff8a8f98%s|r  %d/%d"):format(entry.from, entry.have, entry.need))
            end
        end
    end
end

-------------------------------------------------------------------------------
--  The panel
-------------------------------------------------------------------------------
NewRow = function(parent, index, top, onClick)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW)
    row:SetPoint("TOPLEFT", PAD, top - (index - 1) * ROW)
    row:SetPoint("TOPRIGHT", -PAD, top - (index - 1) * ROW)
    row.hover = row:CreateTexture(nil, "HIGHLIGHT")
    row.hover:SetAllPoints()
    row.hover:SetColorTexture(1, 1, 1, 0.04)
    row.sel = row:CreateTexture(nil, "BACKGROUND")
    row.sel:SetAllPoints()
    row.sel:SetColorTexture(1, 1, 1, 0.07)
    row.sel:Hide()
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(16, 16)
    row.icon:SetPoint("LEFT", 4, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.right = Label(row, CUI.Kit.TEXT_SIZE, TEXT)
    row.right:SetPoint("RIGHT", -4, 0)
    row.right:SetJustifyH("RIGHT")
    row.name = Label(row, CUI.Kit.TEXT_SIZE, TEXT)
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.name:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
    row:SetScript("OnClick", onClick)
    row:SetScript("OnEnter", function(self)
        if not self.link then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(self.link)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    return row
end

local function BuildSell(page)
    local K = Kit()
    local card = CreateFrame("Frame", nil, page)
    card:SetPoint("TOPLEFT", 0, 0)
    card:SetPoint("TOPRIGHT", 0, 0)
    card:SetHeight(248)
    page.card = card
    card.icon = card:CreateTexture(nil, "ARTWORK")
    card.icon:SetSize(36, 36)
    card.icon:SetPoint("TOPLEFT", PAD, -10)
    card.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    card.name = Label(card, 14, TEXT)
    card.name:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 10, -2)
    card.name:SetPoint("RIGHT", -PAD, 0)
    card.sub = Label(card, CUI.Kit.SMALL_SIZE, MUTED)
    card.sub:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -4)
    card.sub:SetPoint("RIGHT", -PAD, 0)
    card.reason = Label(card, CUI.Kit.SMALL_SIZE, MUTED)
    card.reason:SetPoint("TOPLEFT", card.icon, "BOTTOMLEFT", 0, -10)
    card.reason:SetPoint("RIGHT", -PAD, 0)
    card.reason:SetWordWrap(true)

    local priceLabel = Label(card, CUI.Kit.SMALL_SIZE, MUTED)
    priceLabel:SetPoint("TOPLEFT", PAD, -96)
    priceLabel:SetText("Price each")
    card.price = K.Input(card, 120, 24, nil, "essentials")
    card.price:SetMaxLetters(16)
    card.price:SetPoint("LEFT", priceLabel, "LEFT", 74, 0)
    card.price:HookScript("OnEditFocusLost", function(self)
        local entry, amount = Sell.Focus(), Parse(self:GetText())
        if entry then Sell.priceSet[entry.key] = amount and amount > 0 and Floor(entry, amount) or nil end
        Panel.Render()
    end)

    local qtyLabel = Label(card, CUI.Kit.SMALL_SIZE, MUTED)
    qtyLabel:SetPoint("TOPLEFT", PAD, -128)
    qtyLabel:SetText("Quantity")
    card.qty = K.Input(card, 50, 24, nil, "essentials")
    card.qty:SetNumeric(true)
    card.qty:SetMaxLetters(4)
    card.qty:SetJustifyH("CENTER")
    card.qty:SetPoint("LEFT", qtyLabel, "LEFT", 74, 0)
    card.qty:HookScript("OnEditFocusLost", function(self)
        local entry, n = Sell.Focus(), tonumber(self:GetText() or "")
        if entry then Sell.quantitySet[entry.key] = n and n > 0 and n or nil end
        Panel.Render()
    end)
    card.all = K.Button(card, "All", 40, 24, function()
        local entry = Sell.Focus()
        if entry then Sell.quantitySet[entry.key] = nil end
        Panel.Render()
    end, { key = "essentials" })
    card.all:SetPoint("LEFT", card.qty, "RIGHT", 6, 0)
    -- Duration: its own row under Quantity (12h, 24h, 48h left to right).
    local durLabel = Label(card, CUI.Kit.SMALL_SIZE, MUTED)
    durLabel:SetPoint("TOPLEFT", PAD, -160)
    durLabel:SetText("Duration")
    card.durations = {}
    local prev
    for index = #DURATIONS, 1, -1 do
        local d = DURATIONS[index]
        local b = K.Button(card, d[2], 40, 24, function()
            MK.Cfg().duration = d[1]
            Panel.Render()
        end, { key = "essentials", tip = "How long the auction runs. Longer costs a bigger deposit." })
        if prev then b:SetPoint("RIGHT", prev, "LEFT", -4, 0) else b:SetPoint("LEFT", durLabel, "LEFT", 74 + 2 * 44, 0) end
        b.duration = d[1]
        card.durations[index], prev = b, b
    end
    card.deposit = Label(card, CUI.Kit.SMALL_SIZE, MUTED)
    card.deposit:SetPoint("TOPLEFT", PAD, -192)
    card.deposit:SetPoint("RIGHT", -PAD, 0)
    card.post = K.Button(card, "Post", 90, 28, function() Sell.Post() end, { key = "essentials", size = 13 })
    card.post:SetPoint("TOPRIGHT", -PAD, -212)
    card.post:SetActive(true)
    card.skip = K.Button(card, "Skip", 60, 28, function() Sell.Next() end, { key = "essentials" })
    card.skip:SetPoint("RIGHT", card.post, "LEFT", -6, 0)
    card.empty = Label(card, CUI.Kit.TEXT_SIZE, MUTED)
    card.empty:SetPoint("TOPLEFT", PAD, -14)
    card.empty:SetPoint("RIGHT", -PAD, 0)
    card.empty:SetWordWrap(true)

    local head = Label(page, 11, MUTED)
    head:SetPoint("TOPLEFT", PAD, -258)
    head:SetText("LISTINGS")
    page.listHead = head
    page.listings = {}
    for index = 1, 5 do
        local row = NewRow(page, index, -274, function(self)
            local entry = Sell.Focus()
            if entry and self.listing then
                local l = self.listing
                Sell.priceSet[entry.key] = l.quantity > l.own and Floor(entry, l.price - Step(entry)) or l.price
                Panel.Render()
            end
        end)
        row.icon:Hide()
        row.name:ClearAllPoints()
        row.name:SetPoint("LEFT", 4, 0)
        row.name:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
        page.listings[index] = row
    end
    local queueHead = Label(page, 11, MUTED)
    queueHead:SetPoint("TOPLEFT", PAD, -392)
    queueHead:SetText("YOUR BAGS")
    page.queueHead = queueHead
    page.queue = {}
end

local function BuildMine(page)
    local K = Kit()
    page.summary = Label(page, CUI.Kit.TEXT_SIZE, TEXT)
    page.summary:SetPoint("TOPLEFT", PAD, -8)
    page.summary:SetPoint("RIGHT", -150, 0)
    page.next = K.Button(page, "Cancel Next Undercut", 140, 24, function() Mine.CancelNext() end, {
        key = "essentials",
        tip = "Cancels your next undercut auction, one press at a time. The deposit is not returned.",
    })
    page.next:SetPoint("TOPRIGHT", -PAD, -4)
    page.rows = {}
end

local function Build()
    local house = rawget(_G, "AuctionHouseFrame")
    local K = Kit()
    panel = CreateFrame("Frame", "CludesUIMarketPanel", house)
    panel:SetPoint("TOPLEFT", house, "TOPRIGHT", 4, 0)
    panel:SetHeight(H)
    panel:SetWidth(W)
    panel:EnableMouse(true)
    K.Panel(panel, 0.97)
    K.Header(panel, "The Market", function()
        Panel.closed = true
        panel:Hide()
    end, { key = "essentials", closeTip = "Hides the panel until your next visit." })
    panel.tabs = {}
    local prev
    local widths = { sell = 52, mine = 110, deals = 72, shop = 70 }
    for _, t in ipairs({ { "sell", "Sell" }, { "mine", "My Auctions" }, { "deals", "DE Deals" }, { "shop", "Shopping" } }) do
        local tab = K.Button(panel, t[2], widths[t[1]], 26, function()
            Panel.page = t[1]
            if t[1] == "mine" then Mine.Start() elseif t[1] == "sell" then Sell.Read() end
            Panel.Render()
        end, { key = "essentials" })
        if prev then tab:SetPoint("LEFT", prev, "RIGHT", 6, 0) else tab:SetPoint("TOPLEFT", PAD, -38) end
        tab.key, prev = t[1], tab
        panel.tabs[#panel.tabs + 1] = tab
    end
    panel.message = Label(panel, CUI.Kit.SMALL_SIZE, MUTED)
    panel.message:SetPoint("BOTTOMLEFT", PAD, 10)
    panel.message:SetPoint("RIGHT", -PAD, 0)
    for _, key in ipairs({ "sell", "mine", "deals", "shop" }) do
        local page = CreateFrame("Frame", nil, panel)
        page:SetPoint("TOPLEFT", 0, -72)
        page:SetPoint("BOTTOMRIGHT", 0, 28)
        panel[key] = page
    end
    BuildSell(panel.sell)
    BuildMine(panel.mine)
    BuildDeals(panel.deals)
    BuildShop(panel.shop)
end

local function QueueRows(page)
    return math.max(0, math.floor((PAGE_H - 408) / ROW))
end

local function RenderSell()
    local page, card = panel.sell, panel.sell.card
    local entry = Sell.Focus()
    for _, child in ipairs({ card:GetChildren() }) do
        child:SetShown(entry ~= nil)
    end
    for _, fs in ipairs({ card.name, card.sub, card.reason, card.deposit }) do
        fs:SetShown(entry ~= nil)
    end
    card.icon:SetShown(entry ~= nil)
    card.empty:SetShown(entry == nil)
    card.empty:SetText(#Sell.queue == 0 and "Nothing in your bags the auction house takes." or "Pick an item below to price and post it.")
    if entry then
        card.icon:SetTexture(entry.icon)
        card.name:SetText(C_Item.GetItemNameByID(entry.itemID) or entry.link or "")
        card.sub:SetText(("%d in your bags%s"):format(entry.count, entry.scan and (", scan " .. Money(entry.scan) .. " each") or ""))
        local price, why, from = Sell.Price(entry)
        local other = Listings.Cheapest(Sell.rows)
        local reason
        if Sell.state == "searching" then
            reason = "Searching the listings..."
        elseif why == "hand" then
            reason = other and (price < other and "Your price, under the cheapest at " .. Money(other))
                or (other and "Your price, the cheapest is " .. Money(other)) or "Your price."
        elseif why == "under" then
            reason = "One step under the cheapest listing, " .. Money(from) .. "."
        elseif why == "yours" then
            reason = "Yours is already the cheapest, at " .. Money(from) .. "."
        elseif why == "scan" then
            reason = "No listings now: your scan's price."
        else
            reason = "No listings or scan: the game's default from the vendor price."
        end
        local warn = entry.vendor > 0 and price * CUT <= entry.vendor
        if warn then reason = reason .. "\n|cffff6161A vendor pays " .. Money(entry.vendor) .. " each, more than this after the cut.|r" end
        card.reason:SetText(reason)
        if not card.price:HasFocus() then card.price:SetText(Money(price)) end
        local quantity = Sell.Quantity(entry)
        if not card.qty:HasFocus() then card.qty:SetText(tostring(quantity)) end
        local duration = Sell.Duration()
        for _, b in ipairs(card.durations) do
            b:SetActive(b.duration == duration)
        end
        local deposit = Sell.Deposit(entry, quantity)
        card.deposit:SetText(
            ("Deposit %s  |  You get %s"):format(Money(deposit or 0), Money(math.floor(price * quantity * CUT)))
        )
        Enable(card.post, not posting.waiting)
        card.post:SetText(posting.waiting and "Posting..." or "Post")
    end
    -- Listings
    page.listHead:SetShown(entry ~= nil)
    local price = entry and (Sell.Price(entry))
    for index, row in ipairs(page.listings) do
        local l = entry and Sell.rows[index]
        row.listing = l
        row:SetShown(l ~= nil)
        if l then
            row.name:SetText(Money(l.price) .. (l.own > 0 and "  |cff5ec46b(yours)|r" or ""))
            row.right:SetText(l.quantity .. " up")
            Paint(row.name, price and l.price < price and AMBER or TEXT)
        end
    end
    -- Your bags
    local shown = QueueRows(page)
    for index = 1, math.max(shown, #page.queue) do
        local row = page.queue[index]
        local e = index <= shown and Sell.queue[index]
        if not row and e then
            row = NewRow(page, index, -408, function(self)
                if self.entry then Sell.Pick(self.entry.key) end
            end)
            page.queue[index] = row
        end
        if row then
            row.entry, row.link = e or nil, e and e.link
            row:SetShown(e ~= nil and e ~= false)
            if e then
                row.icon:SetTexture(e.icon)
                row.name:SetText(("%s x%d"):format(C_Item.GetItemNameByID(e.itemID) or "?", e.count))
                Paint(row.name, e.vendorBetter and MUTED or TEXT)
                row.right:SetText(e.vendorBetter and "vendor" or (e.scan and Money(e.worth) or "no price"))
                row.sel:SetShown(e.key == Sell.focus)
            end
        end
    end
end

local STATUS = {
    undercut = { "undercut", RED },
    lowest = { "lowest", GREEN },
    checking = { "checking...", MUTED },
    noanswer = { "no answer", MUTED },
    sold = { "sold", GREEN },
}

local function RenderMine()
    local page = panel.mine
    local undercut = Mine.Counts()
    page.summary:SetText(
        #Mine.list == 0 and "You have no auctions here."
            or (("%d auctions, %s"):format(#Mine.list, undercut > 0 and ("|cffff6161" .. undercut .. " undercut|r") or "none undercut"))
    )
    Enable(page.next, undercut > 0)
    local shown = math.max(0, math.floor((PAGE_H - 40) / ROW))
    for index = 1, math.max(shown, #page.rows) do
        local auction = index <= shown and Mine.list[index] or nil
        local row = page.rows[index]
        if not row and auction then
            row = NewRow(page, index, -36, function() end)
            row.cancel = Kit().Button(row, "Cancel", 56, 20, function(self)
                if self:GetParent().auction then Mine.Cancel(self:GetParent().auction) end
            end, { key = "essentials", size = 11 })
            row.cancel:SetPoint("RIGHT", -2, 0)
            row.right:ClearAllPoints()
            row.right:SetPoint("RIGHT", row.cancel, "LEFT", -6, 0)
            page.rows[index] = row
        end
        if row then
            row.auction, row.link = auction, auction and auction.link
            row:SetShown(auction ~= nil)
            if auction then
                row.icon:SetTexture(C_Item.GetItemIconByID(auction.itemID))
                row.name:SetText(("%s x%d"):format(C_Item.GetItemNameByID(auction.itemID) or "?", auction.quantity or 1))
                local status = STATUS[Mine.Status(auction)]
                local low = Mine.lowest[auction.key]
                row.right:SetText(
                    (auction.price and Money(auction.price) or "")
                        .. "  " .. CUI.HexColor(status[2][1], status[2][2], status[2][3]) .. status[1]
                        .. (status[1] == "undercut" and low and (" " .. Money(low)) or "") .. "|r"
                )
                local can = Mine.CanCancel(auction)
                row.cancel:SetShown(not auction.sold)
                Enable(row.cancel, can)
            end
        end
    end
end

function Panel.Render()
    if not (panel and panel:IsShown()) then return end
    for _, tab in ipairs(panel.tabs) do
        tab:SetActive(tab.key == Panel.page)
    end
    local undercut = Mine.Counts()
    panel.tabs[2]:SetText(undercut > 0 and ("My Auctions (" .. undercut .. ")") or "My Auctions")
    panel.sell:SetShown(Panel.page == "sell")
    panel.mine:SetShown(Panel.page == "mine")
    panel.tabs[3]:SetShown(Deals.On())
    panel.tabs[4]:SetShown(Shop.On())
    if (Panel.page == "deals" and not Deals.On()) or (Panel.page == "shop" and not Shop.On()) then Panel.page = "sell" end
    -- Line the shown tabs up, so a hidden one leaves no gap.
    local prev
    for _, tab in ipairs(panel.tabs) do
        if tab:IsShown() then
            tab:ClearAllPoints()
            if prev then tab:SetPoint("LEFT", prev, "RIGHT", 6, 0) else tab:SetPoint("TOPLEFT", PAD, -38) end
            prev = tab
        end
    end
    panel.sell:SetShown(Panel.page == "sell")
    panel.mine:SetShown(Panel.page == "mine")
    panel.deals:SetShown(Panel.page == "deals")
    panel.shop:SetShown(Panel.page == "shop")
    if Panel.page == "sell" then
        RenderSell()
    elseif Panel.page == "mine" then
        RenderMine()
    elseif Panel.page == "shop" then
        RenderShop()
    else
        RenderDeals()
    end
    panel.message:SetText(Panel.message or ("Posted this visit: " .. Money(Panel.posted or 0)))
end

-------------------------------------------------------------------------------
--  Events
-------------------------------------------------------------------------------
local events = CreateFrame("Frame")
local EVENTS = {
    "AUCTION_HOUSE_SHOW",
    "AUCTION_HOUSE_CLOSED",
    "COMMODITY_SEARCH_RESULTS_UPDATED",
    "ITEM_SEARCH_RESULTS_UPDATED",
    "AUCTION_HOUSE_THROTTLED_SYSTEM_READY",
    "AUCTION_HOUSE_AUCTION_CREATED",
    "AUCTION_MULTISELL_UPDATE",
    "AUCTION_MULTISELL_FAILURE",
    "AUCTION_HOUSE_POST_ERROR",
    "OWNED_AUCTIONS_UPDATED",
    "AUCTION_CANCELED",
    "BAG_UPDATE_DELAYED",
    "QUEST_LOG_UPDATE",
}

local function PanelOn() return Get("enabled") and Get("panel") ~= false end

events:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "AUCTION_HOUSE_SHOW" then
        if not PanelOn() or not rawget(_G, "AuctionHouseFrame") then return end
        if not panel then Build() end
        Panel.closed, Panel.posted, Panel.message, Mine.alerted = false, 0, nil, false
        panel:Show()
        Sell.Read()
        Mine.Start()
        if Panel.page == "sell" and not Sell.Focus() then Sell.Next() end
        Panel.Render()
        return
    elseif event == "AUCTION_HOUSE_CLOSED" then
        Listings.Want(nil)
        posting.waiting, posting.confirm = false, nil
        Sell.focus, Sell.state, Mine.checking = nil, nil, nil
        return
    end
    if not (panel and panel:IsShown()) then return end
    if event == "OWNED_AUCTIONS_UPDATED" then
        Mine.Read()
        Panel.Render()
    elseif event == "AUCTION_CANCELED" then
        Mine.Request()
    elseif event == "BAG_UPDATE_DELAYED" then
        if Panel.page == "sell" and not posting.waiting then
            Sell.Read()
            Panel.Render()
        elseif Panel.page == "shop" then
            Panel.Render()
        end
    elseif event == "QUEST_LOG_UPDATE" then
        if Panel.page == "shop" then Panel.Render() end
    elseif event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
        if Mine.wanted then Mine.Request() end
        Listings.OnEvent(event)
    elseif event:find("SEARCH_RESULTS") then
        Listings.OnEvent(event, arg1)
    else
        Sell.OnEvent(event, arg1, arg2)
    end
end)

local function Apply()
    events:UnregisterAllEvents()
    if panel and not PanelOn() then panel:Hide() end
    if not PanelOn() then return end
    for _, event in ipairs(EVENTS) do
        pcall(events.RegisterEvent, events, event)
    end
end

CUI._MarketPanel = { Apply = Apply, Panel = Panel, Sell = Sell, Mine = Mine, Listings = Listings, Deals = Deals, Shop = Shop }

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    Apply()
end)
