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

local W, H, PAD, LINE = 340, 716, 10, CUI.Kit.ROW_H
local PAGE_H = H - 100 -- the space under the tabs and above the message line
local PALETTE = CUI.Kit.Palette
local DIM, LABEL = PALETTE.muted, PALETTE.text
local GREEN, CRIMSON, AMBER = PALETTE.green, PALETTE.red, PALETTE.amber
local CUT = 0.95
local SEARCH_TIMEOUT, POST_TIMEOUT = 6, 10
local DURATIONS = { { 1, "12h" }, { 2, "24h" }, { 3, "48h" } }

local Pane = { page = "sell" }
local Deals, RenderDeals, MakeDeals -- DE Deals, further down
local Shop, FreshLine
local pane

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

local function Label(parent, dims, tint)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    Kit().Font(fs, dims, "essentials")
    Paint(fs, tint or LABEL)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    return fs
end

local function Enable(btn, on)
    btn:SetEnabled(on)
    btn:SetAlpha(on and 1 or 0.45)
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
local ORDER_PRICE = { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } }
local ORDER_BUYOUT = { { sortOrder = Enum.AuctionHouseSortOrder.Buyout, reverseSort = false } }

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
        C_AuctionHouse.SendSearchQuery(C_AuctionHouse.MakeItemKey(want.itemID), ORDER_PRICE, true)
    else
        local key = want.itemKey
        if not key then
            local location = want.bag and Bags.Location(want)
            key = location and C_AuctionHouse.GetItemKeyFromItem(location)
        end
        if not key then return ListingsDone("listed") end
        C_AuctionHouse.SendSearchQuery(key, ORDER_BUYOUT, true)
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

local function LoadCommodities(thingID)
    wipe(Listings.rows)
    for catalog = 1, math.min(C_AuctionHouse.GetNumCommoditySearchResults(thingID) or 0, 50) do
        local r = C_AuctionHouse.GetCommoditySearchResultInfo(thingID, catalog)
        if r then
            Listings.rows[#Listings.rows + 1] =
                { price = r.unitPrice, quantity = r.quantity, own = r.numOwnerItems or 0 }
        end
    end
end

local function LoadItems(thingId)
    wipe(Listings.rows)
    for catalog = 1, math.min(C_AuctionHouse.GetNumItemSearchResults(thingId) or 0, 50) do
        local r = C_AuctionHouse.GetItemSearchResultInfo(thingId, catalog)
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
            LoadCommodities(arg)
            ListingsDone("listed")
        end
    elseif not want.commodity and type(arg) == "table" and arg.itemID == want.itemID then
        LoadItems(arg)
        ListingsDone("listed")
    end
end

-- The cheapest listing that is not yours, and your cheapest.
function Listings.Cheapest(lines)
    local other, own
    for _, row in ipairs(lines or Listings.rows) do
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
    local assign = Sell.priceSet[entry.key]
    if assign then return assign, "hand" end
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
        for catalog, row in ipairs(Listings.rows) do
            Sell.rows[catalog] = row
        end
        Sell.state = Listings.state
        Pane.Render()
        Mine.Resume()
    end)
    Pane.Render()
end

-- The next item that is worth posting, after the one on show.
function Sell.Next()
    local start = 0
    for catalog, entry in ipairs(Sell.queue) do
        if entry.key == Sell.focus then start = catalog end
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
        Pane.posted = (Pane.posted or 0) + posting.quantity * posting.price
        Sell.priceSet[entry.key], Sell.quantitySet[entry.key] = nil, nil
        Pane.message = ("Posted %dx %s at %s each."):format(
            posting.quantity,
            C_Item.GetItemNameByID(entry.itemID) or "item",
            Money(posting.price)
        )
        Sell.Read()
        if Bags.byKey[entry.key] then Sell.Pick(entry.key) else Sell.Next() end
    else
        Pane.message = "The auction house did not take that post."
        Pane.Render()
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
local function AttachWarning()
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
    local requiresConfirm
    if entry.commodity then
        requiresConfirm = C_AuctionHouse.PostCommodity(location, duration, quantity, price)
    else
        requiresConfirm = C_AuctionHouse.PostItem(location, duration, quantity, nil, price)
    end
    posting.entry, posting.quantity, posting.price = entry, quantity, price
    posting.multisell = not entry.commodity and quantity > 1
    posting.waiting = true
    Pane.message = nil
    if requiresConfirm then
        posting.confirm = {
            commodity = entry.commodity,
            location = location,
            duration = duration,
            quantity = quantity,
            price = price,
        }
        AttachWarning()
    else
        PostWait()
    end
    Pane.Render()
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
local ORDER_OWNED = {
    { sortOrder = Enum.AuctionHouseSortOrder.Name, reverseSort = false },
    { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false },
}

local function IdOf(auction)
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
    C_AuctionHouse.QueryOwnedAuctions(ORDER_OWNED)
end

local function TestNext()
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
        return Pane.Render()
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
            TestNext()
        end
    )
end

function Mine.Resume()
    if not Mine.checking then TestNext() end
end

function Mine.Read()
    wipe(Mine.list)
    wipe(Mine.cancelled)
    for catalog = 1, C_AuctionHouse.GetNumOwnedAuctions() or 0 do
        local info = C_AuctionHouse.GetOwnedAuctionInfo(catalog)
        if info then
            local idInfo = C_AuctionHouse.GetItemKeyInfo(info.itemKey)
            local auction = {
                auctionID = info.auctionID,
                itemKey = info.itemKey,
                itemID = info.itemKey.itemID,
                link = info.itemLink,
                quantity = info.quantity,
                price = info.buyoutAmount,
                seconds = info.timeLeftSeconds,
                sold = info.status == Enum.AuctionStatus.Sold,
                commodity = idInfo and idInfo.isCommodity,
            }
            auction.key = idInfo and IdOf(auction)
            Mine.list[#Mine.list + 1] = auction
        end
    end
    local order = { undercut = 1, checking = 2, noanswer = 3, lowest = 4, sold = 5 }
    table.sort(Mine.list, function(lhs, rhs)
        local a, b = order[Mine.Status(lhs)], order[Mine.Status(rhs)]
        if a ~= b then return a < b end
        return lhs.auctionID < rhs.auctionID
    end)
    if not Mine.checking then TestNext() end
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
    Pane.Render()
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

local function DealsCraft()
    for _, catalog in pairs({ GetProfessions() }) do
        local _, _, tier, _, _, _, line, modifier = GetProfessionInfo(catalog)
        if line == 333 then return (tier or 0) + (modifier or 0) end
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
        return Pane.Render()
    end
    local V, craft = DE.Values, DealsCraft()
    local ids = {}
    for thingID in pairs(house.prices) do
        ids[#ids + 1] = thingID
    end
    Deals.state, Deals.loading, Deals.done, Deals.total = "working", 0, 0, #ids
    local catalog = 0
    local function Step()
        if gen ~= Deals.gen then return end
        local last = math.min(catalog + DEALS_CHUNK, #ids)
        for at = catalog + 1, last do
            local thingID = ids[at]
            local title, chain, grade, lvl, _, _, _, _, equip, glyph, _, callingID = C_Item.GetItemInfo(thingID)
            if not title then
                local _, _, _, instantEquip, _, instantCalling = C_Item.GetItemInfoInstant(thingID)
                if instantCalling == 2 or instantCalling == 4 then
                    Deals.loading = Deals.loading + 1
                    C_Item.RequestLoadItemDataByID(thingID)
                end
            elseif V.Takes(thingID, callingID, grade, equip) then
                local outcomes = V.Outcomes(callingID, grade, lvl)
                local worth = outcomes and V.Expected(outcomes, function(id) return house.prices[id] end)
                local need = V.Skill(lvl, grade)
                if worth and not (Deals.mine and craft and need and need > craft) then
                    local price = house.prices[thingID]
                    local value = math.floor(worth * CUT)
                    if value > price then
                        Deals.list[#Deals.list + 1] = {
                            itemID = thingID,
                            name = title,
                            link = chain,
                            icon = glyph,
                            price = price,
                            value = value,
                            profit = value - price,
                            need = need,
                        }
                    end
                end
            end
        end
        catalog, Deals.done = last, last
        if catalog < #ids then
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
        Pane.Render()
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

MakeDeals = function(page)
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
    page.status = Label(page, CUI.Kit.SMALL_SIZE, DIM)
    page.status:SetPoint("TOPLEFT", PAD, -36)
    page.status:SetPoint("RIGHT", -PAD, 0)
    page.status:SetWordWrap(true)
    page.rows = {}
end

RenderDeals = function()
    local page = pane.deals
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
    local shown = math.max(0, math.floor((PAGE_H - 70) / LINE))
    for catalog = 1, math.max(shown, #page.rows) do
        local deal = catalog <= shown and Deals.list[catalog] or nil
        local row = page.rows[catalog]
        if not row and deal then
            row = FreshLine(page, catalog, -64, function(self)
                if self.deal then Deals.Search(self.deal) end
            end)
            page.rows[catalog] = row
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
local function ObjectiveTitle(text)
    if type(text) ~= "string" then return end
    local title = text:gsub("%d+%s*/%s*%d+", ""):gsub("^[%s:]+", ""):gsub("[%s:]+$", "")
    return title ~= "" and title or nil
end

local TASK_THING = 12 -- Enum.ItemClass.Questitem

-- One RestedXP step line that wants an item (.buy or .collect): its item and
-- count from the line's own fields, else from its text ("Gorilla Fang: 8/10").
-- nil when it wants nothing or has it all; "loading" while the game loads it.
local function GuideThing(element)
    local label = type(element.tag) == "string" and element.tag or ""
    if not (label:find("^buy") or label:find("^collect")) then return end
    local id = tonumber(element.id or element.itemId or element.itemID)
    local need = tonumber(element.qty or element.count)
    local have
    if not (id and need) then
        local fs = element.frame and element.frame.text
        local shown = fs and fs.GetText and fs:GetText() or element.text
        if type(shown) ~= "string" then return end
        shown = shown:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T[^|]*|t", ""):gsub("|H[^|]*|h", ""):gsub("|h", "")
        local title, got, want = shown:match("^%s*(.-):%s*(%d+)%s*/%s*(%d+)%s*$")
        if not title then return end
        title = title:gsub("^%[", ""):gsub("%]$", "")
        id, have, need = C_Item.GetItemInfoInstant(title), tonumber(got), tonumber(want)
        if not id then return end
    end
    have = C_Item.GetItemCount(id) or have or 0
    if have >= need then return end
    local title, chain, _, _, _, _, _, _, _, glyph = C_Item.GetItemInfo(id)
    if not title then
        C_Item.RequestLoadItemDataByID(id)
        return "loading"
    end
    return { name = title, link = chain, icon = glyph, have = have, need = need, from = "Guide" }
end

function Shop.Read()
    local roster, spotted = {}, {}
    Shop.loading = 0
    local function Put(entry)
        local key = entry.name:lower()
        if spotted[key] then return end
        spotted[key] = true
        roster[#roster + 1] = entry
    end
    local rxp = rawget(_G, "RXP")
    local stages = rxp and rxp.RXPFrame and rxp.RXPFrame.activeSteps
    for _, step in ipairs(type(stages) == "table" and stages or {}) do
        if step.active then
            for _, element in ipairs(step.elements or {}) do
                local entry = not element.skip and GuideThing(element)
                if entry == "loading" then
                    Shop.loading = Shop.loading + 1
                elseif entry then
                    Put(entry)
                end
            end
        end
    end
    for catalog = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(catalog)
        if info and not info.isHeader and info.questID then
            for _, objective in ipairs(C_QuestLog.GetQuestObjectives(info.questID) or {}) do
                local title = objective.type == "item" and not objective.finished and ObjectiveTitle(objective.text)
                -- Only items the auction house can sell: quest-only items (a head,
                -- a letter) and items the game does not know yet are left out.
                local thingID, _, _, _, glyph, callingID = C_Item.GetItemInfoInstant(title or "")
                if title and thingID and callingID ~= TASK_THING then
                    local chain = select(2, C_Item.GetItemInfo(thingID))
                    Put({ name = title, link = chain, icon = glyph, have = objective.numFulfilled or 0,
                        need = objective.numRequired or 0, from = "Quest" })
                end
            end
        end
    end
    Shop.list = roster
    -- Guide items the game had not loaded yet: read again once it has.
    if Shop.loading > 0 and not Shop.retry then
        Shop.retry = true
        C_Timer.After(1, function()
            Shop.retry = false
            if Pane.page == "shop" then Pane.Render() end
        end)
    end
end

local function MakeShop(page)
    page.status = Label(page, CUI.Kit.SMALL_SIZE, DIM)
    page.status:SetPoint("TOPLEFT", PAD, -8)
    page.status:SetPoint("RIGHT", -PAD, 0)
    page.status:SetWordWrap(true)
    page.rows = {}
end

local function RenderShop()
    local page = pane.shop
    Shop.Read()
    page.status:SetText(#Shop.list == 0
        and "Nothing to buy: no RestedXP buy step or quest item is waiting."
        or ("%d to buy for your guide and quests. Click one to search for it."):format(#Shop.list))
    local shown = math.max(0, math.floor((PAGE_H - 40) / LINE))
    for catalog = 1, math.max(shown, #page.rows) do
        local entry = catalog <= shown and Shop.list[catalog] or nil
        local row = page.rows[catalog]
        if not row and entry then
            row = FreshLine(page, catalog, -34, function(self)
                if self.entry then Deals.Search(self.entry) end
            end)
            page.rows[catalog] = row
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
FreshLine = function(parent, catalog, top, onClick)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(LINE)
    row:SetPoint("TOPLEFT", PAD, top - (catalog - 1) * LINE)
    row:SetPoint("TOPRIGHT", -PAD, top - (catalog - 1) * LINE)
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
    row.right = Label(row, CUI.Kit.TEXT_SIZE, LABEL)
    row.right:SetPoint("RIGHT", -4, 0)
    row.right:SetJustifyH("RIGHT")
    row.name = Label(row, CUI.Kit.TEXT_SIZE, LABEL)
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

local function MakeSell(page)
    local K = Kit()
    local tile = CreateFrame("Frame", nil, page)
    tile:SetPoint("TOPLEFT", 0, 0)
    tile:SetPoint("TOPRIGHT", 0, 0)
    tile:SetHeight(248)
    page.card = tile
    tile.icon = tile:CreateTexture(nil, "ARTWORK")
    tile.icon:SetSize(36, 36)
    tile.icon:SetPoint("TOPLEFT", PAD, -10)
    tile.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    tile.name = Label(tile, 14, LABEL)
    tile.name:SetPoint("TOPLEFT", tile.icon, "TOPRIGHT", 10, -2)
    tile.name:SetPoint("RIGHT", -PAD, 0)
    tile.sub = Label(tile, CUI.Kit.SMALL_SIZE, DIM)
    tile.sub:SetPoint("TOPLEFT", tile.name, "BOTTOMLEFT", 0, -4)
    tile.sub:SetPoint("RIGHT", -PAD, 0)
    tile.reason = Label(tile, CUI.Kit.SMALL_SIZE, DIM)
    tile.reason:SetPoint("TOPLEFT", tile.icon, "BOTTOMLEFT", 0, -10)
    tile.reason:SetPoint("RIGHT", -PAD, 0)
    tile.reason:SetWordWrap(true)

    local priceLabel = Label(tile, CUI.Kit.SMALL_SIZE, DIM)
    priceLabel:SetPoint("TOPLEFT", PAD, -96)
    priceLabel:SetText("Price each")
    tile.price = K.Input(tile, 120, 24, nil, "essentials")
    tile.price:SetMaxLetters(16)
    tile.price:SetPoint("LEFT", priceLabel, "LEFT", 74, 0)
    tile.price:HookScript("OnEditFocusLost", function(self)
        local entry, amount = Sell.Focus(), Parse(self:GetText())
        if entry then Sell.priceSet[entry.key] = amount and amount > 0 and Floor(entry, amount) or nil end
        Pane.Render()
    end)

    local qtyLabel = Label(tile, CUI.Kit.SMALL_SIZE, DIM)
    qtyLabel:SetPoint("TOPLEFT", PAD, -128)
    qtyLabel:SetText("Quantity")
    tile.qty = K.Input(tile, 50, 24, nil, "essentials")
    tile.qty:SetNumeric(true)
    tile.qty:SetMaxLetters(4)
    tile.qty:SetJustifyH("CENTER")
    tile.qty:SetPoint("LEFT", qtyLabel, "LEFT", 74, 0)
    tile.qty:HookScript("OnEditFocusLost", function(self)
        local entry, n = Sell.Focus(), tonumber(self:GetText() or "")
        if entry then Sell.quantitySet[entry.key] = n and n > 0 and n or nil end
        Pane.Render()
    end)
    tile.all = K.Button(tile, "All", 40, 24, function()
        local entry = Sell.Focus()
        if entry then Sell.quantitySet[entry.key] = nil end
        Pane.Render()
    end, { key = "essentials" })
    tile.all:SetPoint("LEFT", tile.qty, "RIGHT", 6, 0)
    -- Duration: its own row under Quantity (12h, 24h, 48h left to right).
    local durLabel = Label(tile, CUI.Kit.SMALL_SIZE, DIM)
    durLabel:SetPoint("TOPLEFT", PAD, -160)
    durLabel:SetText("Duration")
    tile.durations = {}
    local prev
    for catalog = #DURATIONS, 1, -1 do
        local d = DURATIONS[catalog]
        local b = K.Button(tile, d[2], 40, 24, function()
            MK.Cfg().duration = d[1]
            Pane.Render()
        end, { key = "essentials", tip = "How long the auction runs. Longer costs a bigger deposit." })
        if prev then b:SetPoint("RIGHT", prev, "LEFT", -4, 0) else b:SetPoint("LEFT", durLabel, "LEFT", 74 + 2 * 44, 0) end
        b.duration = d[1]
        tile.durations[catalog], prev = b, b
    end
    tile.deposit = Label(tile, CUI.Kit.SMALL_SIZE, DIM)
    tile.deposit:SetPoint("TOPLEFT", PAD, -192)
    tile.deposit:SetPoint("RIGHT", -PAD, 0)
    tile.post = K.Button(tile, "Post", 90, 28, function() Sell.Post() end, { key = "essentials", size = 13 })
    tile.post:SetPoint("TOPRIGHT", -PAD, -212)
    tile.post:SetActive(true)
    tile.skip = K.Button(tile, "Skip", 60, 28, function() Sell.Next() end, { key = "essentials" })
    tile.skip:SetPoint("RIGHT", tile.post, "LEFT", -6, 0)
    tile.empty = Label(tile, CUI.Kit.TEXT_SIZE, DIM)
    tile.empty:SetPoint("TOPLEFT", PAD, -14)
    tile.empty:SetPoint("RIGHT", -PAD, 0)
    tile.empty:SetWordWrap(true)

    local head = Label(page, 11, DIM)
    head:SetPoint("TOPLEFT", PAD, -258)
    head:SetText("LISTINGS")
    page.listHead = head
    page.listings = {}
    for catalog = 1, 5 do
        local row = FreshLine(page, catalog, -274, function(self)
            local entry = Sell.Focus()
            if entry and self.listing then
                local l = self.listing
                Sell.priceSet[entry.key] = l.quantity > l.own and Floor(entry, l.price - Step(entry)) or l.price
                Pane.Render()
            end
        end)
        row.icon:Hide()
        row.name:ClearAllPoints()
        row.name:SetPoint("LEFT", 4, 0)
        row.name:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
        page.listings[catalog] = row
    end
    local lineHead = Label(page, 11, DIM)
    lineHead:SetPoint("TOPLEFT", PAD, -392)
    lineHead:SetText("YOUR BAGS")
    page.queueHead = lineHead
    page.queue = {}
end

local function MakeMine(page)
    local K = Kit()
    page.summary = Label(page, CUI.Kit.TEXT_SIZE, LABEL)
    page.summary:SetPoint("TOPLEFT", PAD, -8)
    page.summary:SetPoint("RIGHT", -150, 0)
    page.next = K.Button(page, "Cancel Next Undercut", 140, 24, function() Mine.CancelNext() end, {
        key = "essentials",
        tip = "Cancels your next undercut auction, one press at a time. The deposit is not returned.",
    })
    page.next:SetPoint("TOPRIGHT", -PAD, -4)
    page.rows = {}
end

local function Make()
    local house = rawget(_G, "AuctionHouseFrame")
    local K = Kit()
    pane = CreateFrame("Frame", "CludesUIMarketPanel", house)
    pane:SetPoint("TOPLEFT", house, "TOPRIGHT", 4, 0)
    pane:SetHeight(H)
    pane:SetWidth(W)
    pane:EnableMouse(true)
    K.Panel(pane, 0.97)
    K.Header(pane, "The Market", function()
        Pane.closed = true
        pane:Hide()
    end, { key = "essentials", closeTip = "Hides the panel until your next visit." })
    pane.tabs = {}
    local prev
    local widths = { sell = 52, mine = 110, deals = 72, shop = 70 }
    for _, t in ipairs({ { "sell", "Sell" }, { "mine", "My Auctions" }, { "deals", "DE Deals" }, { "shop", "Shopping" } }) do
        local tab = K.Button(pane, t[2], widths[t[1]], 26, function()
            Pane.page = t[1]
            if t[1] == "mine" then Mine.Start() elseif t[1] == "sell" then Sell.Read() end
            Pane.Render()
        end, { key = "essentials" })
        if prev then tab:SetPoint("LEFT", prev, "RIGHT", 6, 0) else tab:SetPoint("TOPLEFT", PAD, -38) end
        tab.key, prev = t[1], tab
        pane.tabs[#pane.tabs + 1] = tab
    end
    pane.message = Label(pane, CUI.Kit.SMALL_SIZE, DIM)
    pane.message:SetPoint("BOTTOMLEFT", PAD, 10)
    pane.message:SetPoint("RIGHT", -PAD, 0)
    for _, key in ipairs({ "sell", "mine", "deals", "shop" }) do
        local page = CreateFrame("Frame", nil, pane)
        page:SetPoint("TOPLEFT", 0, -72)
        page:SetPoint("BOTTOMRIGHT", 0, 28)
        pane[key] = page
    end
    MakeSell(pane.sell)
    MakeMine(pane.mine)
    MakeDeals(pane.deals)
    MakeShop(pane.shop)
end

local function LineLines(page)
    return math.max(0, math.floor((PAGE_H - 408) / LINE))
end

local function RenderSell()
    local page, tile = pane.sell, pane.sell.card
    local entry = Sell.Focus()
    for _, child in ipairs({ tile:GetChildren() }) do
        child:SetShown(entry ~= nil)
    end
    for _, fs in ipairs({ tile.name, tile.sub, tile.reason, tile.deposit }) do
        fs:SetShown(entry ~= nil)
    end
    tile.icon:SetShown(entry ~= nil)
    tile.empty:SetShown(entry == nil)
    tile.empty:SetText(#Sell.queue == 0 and "Nothing in your bags the auction house takes." or "Pick an item below to price and post it.")
    if entry then
        tile.icon:SetTexture(entry.icon)
        tile.name:SetText(C_Item.GetItemNameByID(entry.itemID) or entry.link or "")
        tile.sub:SetText(("%d in your bags%s"):format(entry.count, entry.scan and (", scan " .. Money(entry.scan) .. " each") or ""))
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
        local caution = entry.vendor > 0 and price * CUT <= entry.vendor
        if caution then reason = reason .. "\n|cffff6161A vendor pays " .. Money(entry.vendor) .. " each, more than this after the cut.|r" end
        tile.reason:SetText(reason)
        if not tile.price:HasFocus() then tile.price:SetText(Money(price)) end
        local quantity = Sell.Quantity(entry)
        if not tile.qty:HasFocus() then tile.qty:SetText(tostring(quantity)) end
        local duration = Sell.Duration()
        for _, b in ipairs(tile.durations) do
            b:SetActive(b.duration == duration)
        end
        local deposit = Sell.Deposit(entry, quantity)
        tile.deposit:SetText(
            ("Deposit %s  |  You get %s"):format(Money(deposit or 0), Money(math.floor(price * quantity * CUT)))
        )
        Enable(tile.post, not posting.waiting)
        tile.post:SetText(posting.waiting and "Posting..." or "Post")
    end
    -- Listings
    page.listHead:SetShown(entry ~= nil)
    local price = entry and (Sell.Price(entry))
    for catalog, row in ipairs(page.listings) do
        local l = entry and Sell.rows[catalog]
        row.listing = l
        row:SetShown(l ~= nil)
        if l then
            row.name:SetText(Money(l.price) .. (l.own > 0 and "  |cff5ec46b(yours)|r" or ""))
            row.right:SetText(l.quantity .. " up")
            Paint(row.name, price and l.price < price and AMBER or LABEL)
        end
    end
    -- Your bags
    local shown = LineLines(page)
    for catalog = 1, math.max(shown, #page.queue) do
        local row = page.queue[catalog]
        local e = catalog <= shown and Sell.queue[catalog]
        if not row and e then
            row = FreshLine(page, catalog, -408, function(self)
                if self.entry then Sell.Pick(self.entry.key) end
            end)
            page.queue[catalog] = row
        end
        if row then
            row.entry, row.link = e or nil, e and e.link
            row:SetShown(e ~= nil and e ~= false)
            if e then
                row.icon:SetTexture(e.icon)
                row.name:SetText(("%s x%d"):format(C_Item.GetItemNameByID(e.itemID) or "?", e.count))
                Paint(row.name, e.vendorBetter and DIM or LABEL)
                row.right:SetText(e.vendorBetter and "vendor" or (e.scan and Money(e.worth) or "no price"))
                row.sel:SetShown(e.key == Sell.focus)
            end
        end
    end
end

local STATUS = {
    undercut = { "undercut", CRIMSON },
    lowest = { "lowest", GREEN },
    checking = { "checking...", DIM },
    noanswer = { "no answer", DIM },
    sold = { "sold", GREEN },
}

local function RenderMine()
    local page = pane.mine
    local undercut = Mine.Counts()
    page.summary:SetText(
        #Mine.list == 0 and "You have no auctions here."
            or (("%d auctions, %s"):format(#Mine.list, undercut > 0 and ("|cffff6161" .. undercut .. " undercut|r") or "none undercut"))
    )
    Enable(page.next, undercut > 0)
    local shown = math.max(0, math.floor((PAGE_H - 40) / LINE))
    for catalog = 1, math.max(shown, #page.rows) do
        local auction = catalog <= shown and Mine.list[catalog] or nil
        local row = page.rows[catalog]
        if not row and auction then
            row = FreshLine(page, catalog, -36, function() end)
            row.cancel = Kit().Button(row, "Cancel", 56, 20, function(self)
                if self:GetParent().auction then Mine.Cancel(self:GetParent().auction) end
            end, { key = "essentials", size = 11 })
            row.cancel:SetPoint("RIGHT", -2, 0)
            row.right:ClearAllPoints()
            row.right:SetPoint("RIGHT", row.cancel, "LEFT", -6, 0)
            page.rows[catalog] = row
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

function Pane.Render()
    if not (pane and pane:IsShown()) then return end
    for _, tab in ipairs(pane.tabs) do
        tab:SetActive(tab.key == Pane.page)
    end
    local undercut = Mine.Counts()
    pane.tabs[2]:SetText(undercut > 0 and ("My Auctions (" .. undercut .. ")") or "My Auctions")
    pane.sell:SetShown(Pane.page == "sell")
    pane.mine:SetShown(Pane.page == "mine")
    pane.tabs[3]:SetShown(Deals.On())
    pane.tabs[4]:SetShown(Shop.On())
    if (Pane.page == "deals" and not Deals.On()) or (Pane.page == "shop" and not Shop.On()) then Pane.page = "sell" end
    -- Line the shown tabs up, so a hidden one leaves no gap.
    local prev
    for _, tab in ipairs(pane.tabs) do
        if tab:IsShown() then
            tab:ClearAllPoints()
            if prev then tab:SetPoint("LEFT", prev, "RIGHT", 6, 0) else tab:SetPoint("TOPLEFT", PAD, -38) end
            prev = tab
        end
    end
    pane.sell:SetShown(Pane.page == "sell")
    pane.mine:SetShown(Pane.page == "mine")
    pane.deals:SetShown(Pane.page == "deals")
    pane.shop:SetShown(Pane.page == "shop")
    if Pane.page == "sell" then
        RenderSell()
    elseif Pane.page == "mine" then
        RenderMine()
    elseif Pane.page == "shop" then
        RenderShop()
    else
        RenderDeals()
    end
    pane.message:SetText(Pane.message or ("Posted this visit: " .. Money(Pane.posted or 0)))
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

local function PaneOn() return Get("enabled") and Get("panel") ~= false end

events:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "AUCTION_HOUSE_SHOW" then
        if not PaneOn() or not rawget(_G, "AuctionHouseFrame") then return end
        if not pane then Make() end
        Pane.closed, Pane.posted, Pane.message, Mine.alerted = false, 0, nil, false
        pane:Show()
        Sell.Read()
        Mine.Start()
        if Pane.page == "sell" and not Sell.Focus() then Sell.Next() end
        Pane.Render()
        return
    elseif event == "AUCTION_HOUSE_CLOSED" then
        Listings.Want(nil)
        posting.waiting, posting.confirm = false, nil
        Sell.focus, Sell.state, Mine.checking = nil, nil, nil
        return
    end
    if not (pane and pane:IsShown()) then return end
    if event == "OWNED_AUCTIONS_UPDATED" then
        Mine.Read()
        Pane.Render()
    elseif event == "AUCTION_CANCELED" then
        Mine.Request()
    elseif event == "BAG_UPDATE_DELAYED" then
        if Pane.page == "sell" and not posting.waiting then
            Sell.Read()
            Pane.Render()
        elseif Pane.page == "shop" then
            Pane.Render()
        end
    elseif event == "QUEST_LOG_UPDATE" then
        if Pane.page == "shop" then Pane.Render() end
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
    if pane and not PaneOn() then pane:Hide() end
    if not PaneOn() then return end
    for _, event in ipairs(EVENTS) do
        pcall(events.RegisterEvent, events, event)
    end
end

CUI._MarketPanel = { Apply = Apply, Panel = Pane, Sell = Sell, Mine = Mine, Listings = Listings, Deals = Deals, Shop = Shop }

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    Apply()
end)
