if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if not (CludesUI and CludesUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_BagSpace.lua  (WoW Forever only)
--  Bag Space: free bag slots on screen ("Bags 28/52"), amber when under a
--  tenth are free and red when full, with a chat warning as they run out.
--  Its tooltip lists the cheapest items you carry by vendor value, so you
--  know what to sell or drop. Click it to open your bags.
--  Only general bags count: quivers, ammo pouches and soul bags hold
--  nothing else, so their free slots would mislead.
-------------------------------------------------------------------------------
local _, module = ...

local F = module.Feature("bagSpace", { enabled = false, warn = true },
    { point = "BOTTOMRIGHT", relPoint = "BOTTOMRIGHT", x = -260, y = 60 })
local Get, Enabled = F.Get, F.Enabled

local CHEAPEST = 6
local frame, text
local warnedAt

local function Font() return (CludesUI.GetFontPath and CludesUI.GetFontPath()) or STANDARD_TEXT_FONT end

--- free, total for general bags.
local function Space()
    local free, total = 0, 0
    for bag = 0, NUM_BAG_SLOTS or 4 do
        local n, family = C_Container.GetContainerNumFreeSlots(bag)
        if (family or 0) == 0 then
            free = free + (n or 0)
            total = total + (C_Container.GetContainerNumSlots(bag) or 0)
        end
    end
    return free, total
end
module.BagSpace = Space

local function Cheapest()
    local list = {}
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID and not info.hasNoValue then
                local price = select(11, C_Item.GetItemInfo(info.itemID))
                if price and price > 0 then
                    list[#list + 1] = { link = info.hyperlink, value = price * (info.stackCount or 1) }
                end
            end
        end
    end
    table.sort(list, function(a, b) return a.value < b.value end)
    return list
end

local function Paint()
    if not frame then return end
    if not Enabled() then frame:Hide(); return end
    local free, total = Space()
    local colour = free == 0 and "|cffff4040" or (free < total / 10 and "|cffffb040" or "|cff4cc9f0")
    text:SetText(("%sBags %d/%d|r"):format(colour, free, total))
    frame:SetWidth(text:GetStringWidth() + 8)
    frame:Show()
    if Get("warn") then
        if free <= 2 and warnedAt ~= free then
            warnedAt = free
            CludesUI.Print(free == 0 and "|cffff4040Your bags are full.|r" or ("|cffffb040Only %d bag slot%s left.|r"):format(free, free == 1 and "" or "s"))
        elseif free > 2 then
            warnedAt = nil
        end
    end
end

local function Build()
    if frame then return frame end
    frame = CreateFrame("Button", "CludesUIBagSpace", UIParent)
    frame:SetSize(90, 20)
    text = frame:CreateFontString(nil, "OVERLAY")
    text:SetFont(Font(), 13, "OUTLINE")
    text:SetPoint("CENTER")
    frame:SetScript("OnClick", function() if ToggleAllBags then ToggleAllBags() end end)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(CludesUI.L("Cheapest items you carry"), 0.3, 0.79, 0.94)
        local list = Cheapest()
        if #list == 0 then GameTooltip:AddLine(CludesUI.L("Nothing a vendor buys."), 0.6, 0.6, 0.6) end
        for i = 1, math.min(CHEAPEST, #list) do
            GameTooltip:AddDoubleLine(list[i].link, GetCoinTextureString(list[i].value), 1, 1, 1, 1, 1, 1)
        end
        GameTooltip:AddLine(CludesUI.L("Click to open your bags."), 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return frame
end

local ev = CreateFrame("Frame")
local queued
ev:SetScript("OnEvent", function()
    if queued then return end
    queued = true
    C_Timer.After(0.2, function() queued = nil; Paint() end)
end)

local function Apply()
    if Enabled() then
        Build()
        ev:RegisterEvent("BAG_UPDATE_DELAYED")
        ev:RegisterEvent("PLAYER_ENTERING_WORLD")
        if not CludesUI._unlockActive then F.Place(frame) end
    else
        ev:UnregisterAllEvents()
    end
    Paint()
end

CludesUI._BagSpace = { Get = Get, Cfg = F.Cfg, Apply = Apply }

F.Start(Apply, {
    key = "CUI_BagSpace", label = "Bag Space", order = 745,
    frame = function(build) if build then Build(); Paint() end; return frame end,
    size = function() return 90, 20 end,
    noAnchorTarget = true, noSizeMatchTarget = true,
})
