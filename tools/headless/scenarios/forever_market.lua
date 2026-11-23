-- Forever: The Market's auction prices (CludesUIForeverEssentials_Market.lua).
-- A stand-in auction house with five listings of three items: Scan Prices
-- reads them a chunk at a time (lowest buyout each, how many are up); a
-- second scan inside 15 minutes is refused; a search's results update one
-- price; item tooltips gain the Auction line; another addon's full scan is
-- kept; a neutral auction house keeps its own prices. Each step's state is
-- written as == lines.
local CUI = rawget(_G, "CludesUI")
local MK = CUI and CUI._Market
OUT:write("== market " .. tostring(MK ~= nil) .. "\n")
if not MK then return end
local M = MK.Market
rawset(_G, "BreakUpLargeNumbers", tostring)
rawset(_G, "GetCoinTextureString", function(c) return c .. "c" end)
if C_CurrencyInfo then rawset(C_CurrencyInfo, "GetCoinTextureString", nil) end

CludesUIDB.market = { enabled = true, tooltip = true, capture = true }
MK.Apply()

local said = {}
local realPrint = CUI.Print
CUI.Print = function(text) said[#said + 1] = (tostring(text):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

-- listings: count, buyout (for the stack), itemID
local listings = {
    { 5, 5000, 2840 },
    { 20, 16000, 2840 },
    { 1, 25000, 2851 },
    { 1, 22000, 2851 },
    { 10, 3000, 3470 },
}
local asked = 0
local AH = C_AuctionHouse or {}
rawset(_G, "C_AuctionHouse", AH)
rawset(AH, "ReplicateItems", function() asked = asked + 1 end)
rawset(AH, "GetNumReplicateItems", function() return #listings end)
rawset(AH, "GetReplicateItemInfo", function(index)
    local l = listings[index + 1]
    return "x", 0, l[1], 1, true, 1, "", 0, 0, l[2], 0, "", false, "", "", "", l[3]
end)
local browse = {}
rawset(AH, "GetBrowseResults", function() return browse end)

local house = CreateFrame("Frame", "AuctionHouseFrame", UIParent)
house.AuctionsTab = CreateFrame("Button", nil, house)
house:Show()
HARNESS_FIRE_EVENT("AUCTION_HOUSE_SHOW")
HARNESS_ADVANCE(0.2)

local button
for _, child in ipairs({ house:GetChildren() }) do
    if child.GetText and child:GetText() == "Scan Prices" then button = child end
end
OUT:write(("== button: %s %s\n"):format(tostring(button ~= nil), tostring(button and button.age:GetText())))
if not button then return end
SNAP("scan button", button)

button:GetScript("OnClick")(button)
OUT:write("== asked=" .. asked .. " label=" .. tostring(button:GetText()) .. "\n")
HARNESS_FIRE_EVENT("REPLICATE_ITEM_LIST_UPDATE")
for _ = 1, 5 do HARNESS_ADVANCE(0.1) end
local function Prices(label)
    local parts = {}
    for _, id in ipairs({ 2840, 2851, 3470 }) do
        parts[#parts + 1] = id .. "=" .. tostring((M.Price(id))) .. "/" .. tostring((M.Listed(id)))
    end
    OUT:write(("== %s: %s | %s\n"):format(label, table.concat(parts, " "), M.Summary()))
end
Prices("scanned")
OUT:write("== label=" .. tostring(button:GetText()) .. " age=" .. tostring(button.age:GetText()) .. "\n")

-- Inside 15 minutes: refused, with when.
button:GetScript("OnClick")(button)
OUT:write("== again: asked=" .. asked .. "\n")

-- A search: the bracers' cheapest now 180s.
browse = { { itemKey = { itemID = 2851 }, minPrice = 18000, totalQuantity = 3 } }
HARNESS_FIRE_EVENT("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
Prices("after search")

-- The tooltip line.
OUT:write("== tooltip: " .. tostring(M.TooltipLine(2840)):gsub("|", "!") .. "\n")

-- Another addon's full scan, an hour later.
local t0 = GetServerTime()
rawset(_G, "GetServerTime", function() return t0 + 3600 end)
listings[1] = { 5, 2500, 2840 }
C_AuctionHouse.ReplicateItems()
HARNESS_FIRE_EVENT("REPLICATE_ITEM_LIST_UPDATE")
for _ = 1, 5 do HARNESS_ADVANCE(0.1) end
Prices("other addon's scan")

-- A neutral house: its own prices, and ours come back after.
HARNESS_FIRE_EVENT("AUCTION_HOUSE_CLOSED")
rawset(_G, "UnitExists", function(u) return u == "player" or u == "npc" end)
local realSide = UnitFactionGroup
rawset(_G, "UnitFactionGroup", function(u) if u == "npc" then return nil end return realSide(u) end)
HARNESS_FIRE_EVENT("AUCTION_HOUSE_SHOW")
Prices("at a neutral house")
HARNESS_FIRE_EVENT("AUCTION_HOUSE_CLOSED")
Prices("closed")
local keys = {}
for key in pairs(CludesUIDB.market.houses) do keys[#keys + 1] = key end
table.sort(keys)
OUT:write("== houses: " .. table.concat(keys, ", ") .. "\n")
OUT:write("== said:\n   " .. table.concat(said, "\n   ") .. "\n")
CUI.Print = realPrint
