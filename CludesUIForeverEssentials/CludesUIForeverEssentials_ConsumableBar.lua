if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if not (CludesUI and CludesUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_ConsumableBar.lua  (WoW Forever only)
--  Consumable Bar: the consumables in your bags on a bar you can click,
--  one icon per item with how many you carry and its cooldown. Items are
--  found by their item class (Consumable) and subclass, so nothing needs a
--  hand-kept list: potions, elixirs and flasks, scrolls, food and drink,
--  bandages, explosives, and "other" (sharpening and weight stones, oils,
--  healthstones), which must have a use to count.
--
--  The icons are secure item buttons and work in combat. Counts and
--  cooldowns update in combat; the row itself is laid out again only out of
--  combat, so an item used up in a fight leaves its icon (at 0) until then.
-------------------------------------------------------------------------------
local _, module = ...

-- Consumable subclasses (wago.tools ItemSubClass, ClassID 0, build 1.60.1.70888).
local SUB = { explosive = 0, potion = 1, elixir = 2, flask = 3, scroll = 4, food = 5, bandage = 7, other = 8 }
local CATEGORIES = {   -- key, label, subclasses, in bar order
    { key = "potions",   label = "Potions",          subs = { SUB.potion } },
    { key = "elixirs",   label = "Elixirs and Flasks", subs = { SUB.elixir, SUB.flask } },
    { key = "food",      label = "Food and Drink",   subs = { SUB.food } },
    { key = "bandages",  label = "Bandages",         subs = { SUB.bandage } },
    { key = "scrolls",   label = "Scrolls",          subs = { SUB.scroll } },
    { key = "other",     label = "Stones, Oils and Healthstones", subs = { SUB.other } },
    { key = "explosives", label = "Explosives",      subs = { SUB.explosive } },
}
module.CONSUMABLE_CATEGORIES = CATEGORIES

local DEFAULTS = {
    enabled = false, iconSize = 32, maxIcons = 12,
    potions = true, elixirs = true, food = true, bandages = true, scrolls = true, other = true, explosives = false,
}
local F = module.Feature("consumableBar", DEFAULTS, { point = "CENTER", relPoint = "CENTER", x = 0, y = -280 })
local Get, Enabled = F.Get, F.Enabled

local GAP = 3
local holder
local buttons = {}
local dirty = true

local function Font() return CludesUI.GetFontPath("essentials") end

-- subclass -> category order index, for the categories turned on.
local function WantedSubs()
    local want = {}
    for i, c in ipairs(CATEGORIES) do
        if Get(c.key) then for _, s in ipairs(c.subs) do want[s] = i end end
    end
    return want
end

-- The items to show: { {id, order}, ... } in bar order.
local function Collect()
    local want, seen, list = WantedSubs(), {}, {}
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local id = C_Container.GetContainerItemID(bag, slot)
            if id and not seen[id] then
                seen[id] = true
                local _, _, _, _, _, classID, subID = C_Item.GetItemInfoInstant(id)
                local order = classID == Enum.ItemClass.Consumable and want[subID]
                if order and (subID ~= SUB.other or C_Item.GetItemSpell(id)) then
                    list[#list + 1] = { id = id, order = order }
                end
            end
        end
    end
    table.sort(list, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.id < b.id
    end)
    return list
end

local function Button(i)
    local b = buttons[i]
    if b then return b end
    b = CreateFrame("Button", nil, holder, "SecureActionButtonTemplate")
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetAttribute("type", "item")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local border = b:CreateTexture(nil, "BACKGROUND")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(0, 0, 0, 1)
    b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cd:SetAllPoints()
    b.count = b:CreateFontString(nil, "OVERLAY")
    CludesUI.Kit.Font(b.count, 11, "essentials")
    b.count:SetPoint("BOTTOMRIGHT", -2, 2)
    b:SetScript("OnEnter", function(self)
        if not self.itemID then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetItemByID(self.itemID)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    buttons[i] = b
    return b
end

-- Counts and cooldowns: plain frames, fine in combat.
local function Paint()
    for _, b in ipairs(buttons) do
        if b:IsShown() and b.itemID then
            local n = C_Item.GetItemCount(b.itemID, false, true) or 0
            b.count:SetText(n > 1 and n or (n == 0 and "|cffff40400|r" or ""))
            b.icon:SetDesaturated(n == 0)
            local start, duration, enable = C_Container.GetItemCooldown(b.itemID)
            if start and duration and duration > 1.5 and enable ~= 0 then
                b.cd:SetCooldown(start, duration)
            else
                b.cd:Clear()
            end
        end
    end
end

-- Lays the row out again; out of combat only, the buttons are secure.
local function Layout()
    if not holder then return end
    if InCombatLockdown() then dirty = true; Paint(); return end
    dirty = false
    local size, max = Get("iconSize"), Get("maxIcons")
    local list = Enabled() and Collect() or {}
    local n = math.min(#list, max)
    for i = 1, n do
        local id = list[i].id
        local b = Button(i)
        b.itemID = id
        b:SetAttribute("item", "item:" .. id)
        b.icon:SetTexture(C_Item.GetItemIconByID(id))
        b:SetSize(size, size)
        b:ClearAllPoints()
        b:SetPoint("LEFT", holder, "LEFT", (i - 1) * (size + GAP), 0)
        b:Show()
    end
    for i = n + 1, #buttons do buttons[i]:Hide(); buttons[i].itemID = nil end
    holder:SetSize(math.max(1, n) * (size + GAP) - GAP, size)
    Paint()
end

local function Build()
    if holder then return holder end
    holder = CreateFrame("Frame", "CludesUIConsumableBar", UIParent)
    holder:SetSize(Get("iconSize"), Get("iconSize"))
    return holder
end

local ev = CreateFrame("Frame")
local queued
ev:SetScript("OnEvent", function(_, event)
    if event == "BAG_UPDATE_COOLDOWN" then return Paint() end
    if event == "PLAYER_REGEN_ENABLED" and not dirty then return end
    if queued then return end
    queued = true
    C_Timer.After(0.3, function() queued = nil; Layout() end)
end)

local function Apply()
    if Enabled() then
        Build()
        ev:RegisterEvent("BAG_UPDATE_DELAYED")
        ev:RegisterEvent("BAG_UPDATE_COOLDOWN")
        ev:RegisterEvent("PLAYER_REGEN_ENABLED")
        ev:RegisterEvent("PLAYER_ENTERING_WORLD")
        ev:RegisterEvent("GET_ITEM_INFO_RECEIVED")
        if not CludesUI._unlockActive and not InCombatLockdown() then F.Place(holder) end
    else
        ev:UnregisterAllEvents()
    end
    Layout()
end

CludesUI._ConsumableBar = { Get = Get, Read = F.Read, Cfg = F.Cfg, Apply = Apply, Categories = CATEGORIES }

F.Start(Apply, {
    key = "CUI_ConsumableBar", label = "Consumable Bar", order = 738,
    frame = function(build) if build then Build() end; return holder end,
    size = function()
        local size = Get("iconSize")
        return size * 6 + GAP * 5, size
    end,
    noAnchorTarget = true, noSizeMatchTarget = true,
})
