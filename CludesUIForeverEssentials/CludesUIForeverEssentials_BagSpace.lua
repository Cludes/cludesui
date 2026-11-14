if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if not (CludesUI and CludesUI.IS_FOREVER) then
    return
end
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

local F = module.Feature(
    "bagSpace",
    { enabled = false, warn = true },
    { point = "BOTTOMRIGHT", relPoint = "BOTTOMRIGHT", x = -260, y = 60 }
)
local Get, Enabled = F.Get, F.Enabled

local CHEAPEST = 6
local widget, textValue
local warnedAt

local function Font()
    return CludesUI.GetFontPath("essentials")
end

--- free, total for general bags.
local function Space()
    local free, sum = 0, 0
    for bag = 0, NUM_BAG_SLOTS or 4 do
        local num, family = C_Container.GetContainerNumFreeSlots(bag)
        if (family or 0) == 0 then
            free = free + (num or 0)
            sum = sum + (C_Container.GetContainerNumSlots(bag) or 0)
        end
    end
    return free, sum
end
module.BagSpace = Space

local function Cheapest()
    local entries = {}
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local details = C_Container.GetContainerItemInfo(bag, slot)
            if details and details.itemID and not details.hasNoValue then
                local price = select(11, C_Item.GetItemInfo(details.itemID))
                if price and price > 0 then
                    entries[#entries + 1] =
                        { link = details.hyperlink, value = price * (details.stackCount or 1) }
                end
            end
        end
    end
    table.sort(entries, function(a, b)
        return a.value < b.value
    end)
    return entries
end

local function Paint()
    if not widget then
        return
    end
    if not Enabled() then
        widget:Hide()
        return
    end
    local free, sum = Space()
    local colour = free == 0 and "|cffff4040"
        or (free < sum / 10 and "|cffffb040" or CludesUI.Kit.AccentHex())
    textValue:SetText(("%sBags %d/%d|r"):format(colour, free, sum))
    widget:SetWidth(textValue:GetStringWidth() + 8)
    widget:Show()
    if Get("warn") then
        if free <= 2 and warnedAt ~= free then
            warnedAt = free
            CludesUI.Print(
                free == 0 and "|cffff4040Your bags are full.|r"
                    or ("|cffffb040Only %d bag slot%s left.|r"):format(free, free == 1 and "" or "s")
            )
        elseif free > 2 then
            warnedAt = nil
        end
    end
end

local function Build()
    if widget then
        return widget
    end
    widget = CreateFrame("Button", "CludesUIBagSpace", UIParent)
    widget:SetSize(90, 20)
    textValue = widget:CreateFontString(nil, "OVERLAY")
    CludesUI.Kit.Font(textValue, 13, "essentials")
    textValue:SetPoint("CENTER")
    widget:SetScript("OnClick", function()
        if ToggleAllBags then
            ToggleAllBags()
        end
    end)
    widget:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(CludesUI.L("Cheapest items you carry"), CludesUI.Kit.Accent())
        local entries = Cheapest()
        if #entries == 0 then
            GameTooltip:AddLine(CludesUI.L("Nothing a vendor buys."), 0.6, 0.6, 0.6)
        end
        for idx = 1, math.min(CHEAPEST, #entries) do
            GameTooltip:AddDoubleLine(
                entries[idx].link,
                GetCoinTextureString(entries[idx].value),
                1,
                1,
                1,
                1,
                1,
                1
            )
        end
        GameTooltip:AddLine(CludesUI.L("Click to open your bags."), 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    widget:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    return widget
end

local ev = CreateFrame("Frame")
local queued
ev:SetScript("OnEvent", function()
    if queued then
        return
    end
    queued = true
    C_Timer.After(0.2, function()
        queued = nil
        Paint()
    end)
end)

local function Apply()
    if Enabled() then
        Build()
        ev:RegisterEvent("BAG_UPDATE_DELAYED")
        ev:RegisterEvent("PLAYER_ENTERING_WORLD")
        if not CludesUI._unlockActive then
            F.Place(widget)
        end
    else
        ev:UnregisterAllEvents()
    end
    Paint()
end

CludesUI._BagSpace = { Get = Get, Cfg = F.Cfg, Apply = Apply }

F.Start(Apply, {
    key = "CUI_BagSpace",
    label = "Bag Space",
    order = 745,
    frame = function(build)
        if build then
            Build()
            Paint()
        end
        return widget
    end,
    size = function()
        return 90, 20
    end,
    noAnchorTarget = true,
    noSizeMatchTarget = true,
})
