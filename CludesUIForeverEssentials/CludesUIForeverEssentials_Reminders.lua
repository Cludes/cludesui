if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
if not (CUI and CUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_Reminders.lua  (WoW Forever only)
--  Four reminders:
--    Restock Reminder   when you reach a city or inn, a flashing list of what
--                       you are short on: class reagents (matched to the
--                       highest rank you know), ammo, food and drink, junk to
--                       sell, nearly full bags. Buy at Vendors (off by
--                       default, it spends gold) tops reagents and ammo up at
--                       a vendor who sells them. Repair and junk selling are
--                       Utilities' (Auto Repair, Auto Sell Junk).
--    Lockpicking Skill  a lockbox's tooltip says the Lockpicking it needs,
--                       coloured by yours.
--    Gear Reminders     an icon while you wear gear with a drawback where you
--                       are: Cloak of Hermitic Bliss in Wailing Caverns, or a
--                       fishing pole. Ctrl-click hides it until you take it off.
--    Talent Points      text on screen while you have talent points to spend.
-------------------------------------------------------------------------------
local _, module = ...

local function Typeface() return CUI.GetFontPath("essentials") end
local function Secret(val) return issecretvalue and issecretvalue(val) end
local function Learned(ident)
    return C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(ident)
end
local _, CALLING = UnitClass("player")

-------------------------------------------------------------------------------
--  Restock
-------------------------------------------------------------------------------
-- Per class: a spell family, its ranks as { spellID, reagent itemID }.
local FAMILIES = {
    {
        class = "DRUID",
        name = "Rebirth",
        { 20484, 17034 },
        { 20739, 17035 },
        { 20742, 17036 },
        { 20747, 17037 },
        { 20748, 17038 },
    },
    { class = "DRUID", name = "Gift of the Wild", { 21849, 17021 }, { 21850, 17026 } },
    { class = "MAGE", name = "Arcane Brilliance", { 23028, 17020 } },
    {
        class = "MAGE",
        name = "Teleports",
        { 3561, 17031 },
        { 3562, 17031 },
        { 3563, 17031 },
        { 3565, 17031 },
        { 3566, 17031 },
        { 3567, 17031 },
        { 1297659, 17031 },
    },
    {
        class = "MAGE",
        name = "Portals",
        { 10059, 17032 },
        { 11416, 17032 },
        { 11417, 17032 },
        { 11418, 17032 },
        { 11419, 17032 },
        { 11420, 17032 },
    },
    { class = "PALADIN", name = "Divine Intervention", { 19752, 17033 } },
    {
        class = "PALADIN",
        name = "Greater Blessings",
        { 25782, 21177 },
        { 25916, 21177 },
        { 25890, 21177 },
        { 25894, 21177 },
        { 25918, 21177 },
        { 25895, 21177 },
        { 25898, 21177 },
    },
    { class = "PRIEST", name = "Prayer of Fortitude", { 21562, 17028 }, { 21564, 17029 } },
    { class = "PRIEST", name = "Prayer of Spirit", { 27681, 17029 } },
    { class = "PRIEST", name = "Prayer of Shadow Protection", { 27683, 17029 } },
    { class = "SHAMAN", name = "Reincarnation", { 20608, 17030 }, { 21169, 17030 }, { 27740, 17030 } },
    { class = "WARLOCK", name = "Ritual of Doom", { 18540, 16583 } },
    { class = "WARLOCK", name = "Inferno", { 1122, 5565 }, { 24670, 5565 } },
    {
        class = "ROGUE",
        name = "Vanish",
        { 1856, 5140 },
        { 1857, 5140 },
        { 27617, 5140 },
        { 457437, 5140 },
        { 1285372, 5140 },
    },
}
local TARGETS = {
    [17034] = 5,
    [17035] = 5,
    [17036] = 5,
    [17037] = 5,
    [17038] = 5,
    [17021] = 20,
    [17026] = 20,
    [17020] = 20,
    [17031] = 10,
    [17032] = 10,
    [17033] = 5,
    [21177] = 100,
    [17028] = 20,
    [17029] = 20,
    [17030] = 5,
    [16583] = 5,
    [5565] = 5,
    [5140] = 20,
}
local FOOD_AND_DRINK = {
    [13724] = true,
    [19301] = true,
    [20031] = true,
    [21215] = true,
    [21537] = true,
    [23172] = true,
    [23176] = true,
    [262433] = true,
    [282018] = true,
    [3448] = true,
    [20388] = true,
    [20389] = true,
    [20390] = true,
}
local AMMO_SLOT, RANGED_SLOT = 0, 18
local WEAPON_CALLING, THROWN_SUBCLASS = 2, 16
local THROWN_CALLINGS = { ROGUE = true, WARRIOR = true }
local FOOD_CALLING, FOOD_SUBCLASS, OTHER_SUBCLASS = 0, 5, 8
local FOOD_SPELL, NUTRITIOUS_DRINK, DRINK_THING = 433, 1249920, 159
local NO_DRINK = { WARRIOR = true, ROGUE = true }

local R = module.Feature("restock", {
    enabled = true,
    reagents = true,
    ammo = true,
    ammoTarget = 1000,
    food = true,
    foodBelow = 10,
    foodMinLevel = 0,
    foodMaxLevel = 60,
    vendor = true,
    bagsBelow = 4,
    buy = false,
    hunterAmmo = false,
    hunterAmmoBelow = 500,
    size = 16,
}, { point = "CENTER", relPoint = "CENTER", x = 0, y = 120 })

local function Aim(thingId)
    local tbl = R.Read().targets
    return (tbl and tbl[thingId]) or TARGETS[thingId]
end

local pending = {}
local rEvents = CreateFrame("Frame")
local function RequestThing(ident)
    if pending[ident] then return end
    pending[ident] = true
    rEvents:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    C_Item.RequestLoadItemDataByID(ident)
end

local function ThingTitle(ident) return C_Item.GetItemNameByID(ident) or ("item " .. ident) end

local function LearnedReagent(family)
    local entry
    for _, tier in ipairs(family) do
        if Learned(tier[1]) then entry = tier[2] end
    end
    return entry
end

local function CarriedAmmo()
    if THROWN_CALLINGS[CALLING] then
        local entry = GetInventoryItemID("player", RANGED_SLOT)
        if entry then
            local _, _, _, _, _, callingID, subID = C_Item.GetItemInfoInstant(entry)
            if callingID == WEAPON_CALLING and subID == THROWN_SUBCLASS then
                local stack = select(8, C_Item.GetItemInfo(entry))
                if not stack then
                    RequestThing(entry)
                    return
                end
                if stack > 1 then return entry end
                return
            end
        end
    end
    return GetInventoryItemID("player", AMMO_SLOT)
end

local function Desired()
    local desired = {}
    if R.Get("reagents") then
        for _, window in ipairs(FAMILIES) do
            local entry = window.class == CALLING and LearnedReagent(window)
            if entry and Aim(entry) > 0 then desired[entry] = Aim(entry) end
        end
    end
    local ammo = R.Get("ammo") and CarriedAmmo()
    if ammo and ammo > 0 then desired[ammo] = R.Get("ammoTarget") end
    return desired
end

local function HunterAmmoOn() return CALLING == "HUNTER" and R.Get("hunterAmmo") end

local function SweepBags()
    local food, drink, junk, free = 0, 0, 0, 0
    local drinkSpell = C_Item.GetItemSpell(DRINK_THING)
    local nutritious = C_Spell.GetSpellName(NUTRITIOUS_DRINK)
    local foodSpell = C_Spell.GetSpellName(FOOD_SPELL)
    for bag = 0, NUM_BAG_SLOTS or 4 do
        local slots, family = C_Container.GetContainerNumFreeSlots(bag)
        if (family or 0) == 0 then free = free + (slots or 0) end
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local details = C_Container.GetContainerItemInfo(bag, slot)
            if details then
                if details.quality == Enum.ItemQuality.Poor and not details.hasNoValue then
                    junk = junk + 1
                end
                local _, _, _, _, _, callingID, subID = C_Item.GetItemInfoInstant(details.itemID)
                local isFood = callingID == FOOD_CALLING and (subID == FOOD_SUBCLASS or subID == OTHER_SUBCLASS)
                local lvl = isFood and select(5, C_Item.GetItemInfo(details.itemID))
                if isFood and not lvl then RequestThing(details.itemID) end
                if lvl and lvl >= R.Get("foodMinLevel") and lvl <= R.Get("foodMaxLevel") then
                    local spell = C_Item.GetItemSpell(details.itemID)
                    if FOOD_AND_DRINK[details.itemID] then
                        food, drink = food + details.stackCount, drink + details.stackCount
                    elseif spell and (spell == drinkSpell or spell == nutritious) then
                        drink = drink + details.stackCount
                    elseif subID == FOOD_SUBCLASS or spell == foodSpell then
                        food = food + details.stackCount
                    end
                end
            end
        end
    end
    return food, junk, free, drink
end

local function Lines()
    local lines = {}
    for ident, aim in pairs(Desired()) do
        local have = C_Item.GetItemCount(ident)
        local hunterAmmo = HunterAmmoOn() and ident == GetInventoryItemID("player", AMMO_SLOT)
        if not hunterAmmo and have < aim then
            lines[#lines + 1] = ("%s  %d / %d"):format(ThingTitle(ident), have, aim)
        end
    end
    table.sort(lines)
    if HunterAmmoOn() then
        local ammo = GetInventoryItemID("player", AMMO_SLOT)
        if ammo and ammo > 0 then
            local have, below = C_Item.GetItemCount(ammo), R.Get("hunterAmmoBelow")
            if have <= below then lines[#lines + 1] = ("%s  %d / %d"):format(ThingTitle(ammo), have, below) end
        end
    end
    local food, junk, free, drink = SweepBags()
    local below = R.Get("foodBelow")
    if R.Get("food") and food < below then lines[#lines + 1] = ("Food  %d left"):format(food) end
    if R.Get("food") and not NO_DRINK[CALLING] and drink < below then
        lines[#lines + 1] = ("Drink  %d left"):format(drink)
    end
    if R.Get("vendor") then
        if junk > 0 then lines[#lines + 1] = ("Junk to sell  %d"):format(junk) end
        if free < R.Get("bagsBelow") then lines[#lines + 1] = ("Bags nearly full  %d free"):format(free) end
    end
    return lines
end

local warn, flash
local function MakeWarn()
    if warn then return warn end
    warn = CreateFrame("Frame", "CludesUIRestock", UIParent)
    warn:SetSize(240, 60)
    -- A font first: the client refuses text on a FontString without one.
    warn.title = warn:CreateFontString(nil, "OVERLAY")
    warn.title:SetPoint("TOP", 0, -4)
    CUI.Kit.Font(warn.title, R.Get("size") + 6, "essentials")
    warn.title:SetTextColor(CUI.Kit.Accent())
    warn.title:SetText("Restock")
    warn.text = warn:CreateFontString(nil, "OVERLAY")
    warn.text:SetPoint("TOP", warn.title, "BOTTOM", 0, -4)
    warn.text:SetJustifyH("CENTER")
    CUI.Kit.Font(warn.text, R.Get("size"), "essentials")
    flash = warn:CreateAnimationGroup()
    flash:SetLooping("BOUNCE")
    flash:SetScript("OnLoop", function(self)
        self.loops = (self.loops or 0) + 1
        if self.loops >= 6 then self:Stop() end
    end)
    local pulse = flash:CreateAnimation("Alpha")
    pulse:SetFromAlpha(1)
    pulse:SetToAlpha(0.35)
    pulse:SetDuration(0.6)
    warn:Hide()
    return warn
end

local function ConcealWarn()
    if warn then
        if flash then flash:Stop() end
        warn:Hide()
    end
end

local function RevealWarn(lines)
    MakeWarn()
    local dims = R.Get("size")
    CUI.Kit.Font(warn.title, dims + 6, "essentials")
    CUI.Kit.Font(warn.text, dims, "essentials")
    warn.text:SetText(table.concat(lines, "\n"))
    warn:SetSize(
        math.max(warn.title:GetStringWidth(), warn.text:GetStringWidth()) + 16,
        warn.title:GetStringHeight() + warn.text:GetStringHeight() + 12
    )
    if not warn:IsShown() then
        warn:Show()
        flash.loops = 0
        flash:Play()
    end
end

local function Test()
    if CUI._unlockActive and R.Enabled() then
        RevealWarn({ "Arcane Powder  3 / 20", "Junk to sell  6" })
        return
    end
    if
        not R.Enabled()
        or not IsResting()
        or InCombatLockdown()
        or IsInInstance()
        or (MerchantFrame and MerchantFrame:IsShown())
    then
        ConcealWarn()
        return
    end
    local lines = Lines()
    if #lines > 0 then
        RevealWarn(lines)
    else
        ConcealWarn()
    end
end

-- Buys whole bundles up to each target, as far as gold and the vendor's stock allow.
local function Buy()
    if not (R.Enabled() and R.Get("buy")) then return end
    local desired = Desired()
    local money = GetMoney()
    local spent, bought = 0, {}
    for catalog = 1, GetMerchantNumItems() do
        local ident = tonumber((GetMerchantItemLink(catalog) or ""):match("item:(%d+)"))
        local aim = ident and desired[ident]
        local details = aim and C_MerchantFrame.GetItemInfo(catalog)
        if details and details.isPurchasable and not details.hasExtendedCost then
            local bundle = math.max(details.stackCount, 1)
            local bundles = math.ceil((aim - C_Item.GetItemCount(ident)) / bundle)
            if details.numAvailable and details.numAvailable >= 0 then
                bundles = math.min(bundles, details.numAvailable)
            end
            if details.price > 0 then bundles = math.min(bundles, math.floor(money / details.price)) end
            local perBuy = math.max(math.floor(GetMerchantItemMaxStack(catalog) / bundle), 1)
            if bundles > 0 then
                local leftX = bundles
                while leftX > 0 do
                    local take = math.min(leftX, perBuy)
                    BuyMerchantItem(catalog, take * bundle)
                    leftX = leftX - take
                end
                money = money - bundles * details.price
                spent = spent + bundles * details.price
                bought[#bought + 1] = bundles * bundle .. "x " .. ThingTitle(ident)
            end
        end
    end
    if #bought > 0 then
        CUI.Print(
            "|cff4cc9f0Restocked|r "
                .. table.concat(bought, ", ")
                .. " for "
                .. C_CurrencyInfo.GetCoinTextureString(math.floor(spent))
        )
    end
end

local wasResting
rEvents:SetScript("OnEvent", function(_, evt, ident)
    if evt == "GET_ITEM_INFO_RECEIVED" then
        if not pending[ident] then return end
        pending[ident] = nil
        if not next(pending) then rEvents:UnregisterEvent("GET_ITEM_INFO_RECEIVED") end
        return Test()
    end
    if evt == "MERCHANT_SHOW" then
        ConcealWarn()
        Buy()
    elseif evt == "MERCHANT_CLOSED" then
        C_Timer.After(0.5, Test)
    elseif evt == "PLAYER_REGEN_DISABLED" then
        ConcealWarn()
    elseif evt == "PLAYER_UPDATE_RESTING" or evt == "PLAYER_ENTERING_WORLD" then
        local resting = IsResting()
        if resting and not wasResting then Test() end
        if not resting then ConcealWarn() end
        wasResting = resting
    else
        Test()
    end
end)

local function RUse()
    rEvents:UnregisterAllEvents()
    if not R.Enabled() then
        ConcealWarn()
        return
    end
    for ident in pairs(TARGETS) do
        C_Item.RequestLoadItemDataByID(ident)
    end
    for _, event in ipairs({
        "MERCHANT_SHOW",
        "MERCHANT_CLOSED",
        "PLAYER_UPDATE_RESTING",
        "PLAYER_ENTERING_WORLD",
        "PLAYER_REGEN_DISABLED",
        "PLAYER_REGEN_ENABLED",
        "BAG_UPDATE_DELAYED",
    }) do
        rEvents:RegisterEvent(event)
    end
    if R.Get("ammo") or HunterAmmoOn() then rEvents:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player") end
    RequestThing(DRINK_THING)
    wasResting = IsResting()
    if warn and not CUI._unlockActive then R.Place(warn) end
    Test()
end

--- This class's reagents, for the options page: { {item, name, target}, ... }.
local function CallingMats()
    local result, spotted = {}, {}
    for _, window in ipairs(FAMILIES) do
        if window.class == CALLING then
            for _, tier in ipairs(window) do
                local entry = tier[2]
                if not spotted[entry] then
                    spotted[entry] = true
                    result[#result + 1] = { item = entry, name = ThingTitle(entry) }
                end
            end
        end
    end
    return result
end

R.Start(RUse, {
    key = "CUI_Restock",
    label = "Restock Reminder",
    order = 748,
    frame = function(make)
        if make then
            MakeWarn()
            Test()
        end
        return warn
    end,
    size = function() return 240, 60 end,
    noAnchorTarget = true,
    noSizeMatchTarget = true,
})

-------------------------------------------------------------------------------
--  Lockpicking Skill
-------------------------------------------------------------------------------
local LOCKBOX_CRAFT = {
    [4632] = 1,
    [4633] = 25,
    [4634] = 70,
    [4636] = 125,
    [4637] = 175,
    [4638] = 225,
    [5046] = 70,
    [5758] = 225,
    [5759] = 225,
    [5760] = 225,
    [6354] = 1,
    [6355] = 70,
    [6712] = 1,
    [7209] = 1,
    [7869] = 70,
    [12033] = 275,
    [13875] = 175,
    [13918] = 250,
    [16882] = 1,
    [16883] = 70,
    [16884] = 175,
    [16885] = 250,
    [208838] = 1,
    [227937] = 175,
}
local LOCKPICKING = 633
local L = module.Feature("lockboxSkill", { enabled = false })
local lockCraft, lockTitle
local function LoadCraft()
    local details = C_SkillInfo
        and C_SkillInfo.GetSkillLineInfoByID
        and C_SkillInfo.GetSkillLineInfoByID(LOCKPICKING)
    lockCraft = details and (details.rank + details.modifier)
    lockTitle = (details and details.name ~= "" and details.name)
        or (C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillDisplayName and C_TradeSkillUI.GetTradeSkillDisplayName(
            LOCKPICKING
        ))
        or "Lockpicking"
end
local lockEv = CreateFrame("Frame")
lockEv:SetScript("OnEvent", LoadCraft)
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, payload)
        if not L.Enabled() then return end
        local ident = payload and payload.id
        if not ident or Secret(ident) then return end
        local need = LOCKBOX_CRAFT[ident]
        if not need then return end
        if not lockTitle then LoadCraft() end
        local crimson, green, blue
        if not lockCraft then
            crimson, green, blue = 1, 0.8, 0.2
        elseif lockCraft < need then
            crimson, green, blue = 1, 0.3, 0.3
        else
            crimson, green, blue = 0.4, 0.9, 0.5
        end
        tooltip:AddLine(ITEM_MIN_SKILL:format(lockTitle, need), crimson, green, blue)
    end)
end
L.Start(function()
    if L.Enabled() then
        lockEv:RegisterEvent("SKILL_LINES_CHANGED")
        LoadCraft()
    else
        lockEv:UnregisterAllEvents()
    end
end)

-------------------------------------------------------------------------------
--  Gear Reminders
-------------------------------------------------------------------------------
local WORN = {
    { item = 273084, slot = 15, instance = 43, setting = "worn" }, -- Cloak of Hermitic Bliss, Wailing Caverns
    { weapon = "Fishingpole", sample = 6256, slot = 16, where = "poleWhere", setting = "pole" },
}
local G = module.Feature(
    "gearReminders",
    { worn = false, pole = false, poleWhere = "always", size = 48 },
    { point = "TOP", relPoint = "TOP", x = 0, y = -290 }
)
local gWindow
local gGlyphs, dismissed = {}, {}
local function GOn() return G.Get("worn") or G.Get("pole") end

local function Wearing(wid, ident)
    if wid.item then return ident == wid.item end
    local _, _, _, _, _, callingID, subID = C_Item.GetItemInfoInstant(ident)
    return callingID == Enum.ItemClass.Weapon and subID == Enum.ItemWeaponSubclass[wid.weapon]
end

local function WornHere(wid, here)
    if wid.instance then return wid.instance == here end
    if wid.where and G.Get(wid.where) == "instance" then
        local _, kind = IsInInstance()
        return kind == "party" or kind == "raid"
    end
    return true
end

local GRefresh
local function Glyph(catalog)
    local widget = gGlyphs[catalog]
    if widget then return widget end
    widget = CreateFrame("Button", nil, gWindow)
    widget.tex = widget:CreateTexture(nil, "ARTWORK")
    widget.tex:SetAllPoints()
    widget.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    widget:SetScript("OnEnter", function(self)
        if not self.slot then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetInventoryItem("player", self.slot)
        GameTooltip:AddLine(CUI.L("You are wearing this."), CUI.Kit.Accent())
        GameTooltip:AddLine(CUI.L("Ctrl-click to hide it until you take it off."), 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    widget:SetScript("OnLeave", function() GameTooltip:Hide() end)
    widget:SetScript("OnMouseUp", function(self)
        if self.slot and IsControlKeyDown() then
            dismissed[self.slot] = GetInventoryItemID("player", self.slot)
            GRefresh()
        end
    end)
    gGlyphs[catalog] = widget
    return widget
end

GRefresh = function()
    if not gWindow then return end
    local dims = G.Get("size")
    local here = select(8, GetInstanceInfo())
    local isShown = 0
    for _, wid in ipairs(WORN) do
        local ident = GetInventoryItemID("player", wid.slot)
        if dismissed[wid.slot] ~= ident then dismissed[wid.slot] = nil end
        local reveal, texture, slot
        if CUI._unlockActive then
            reveal, texture = G.Get(wid.setting), C_Item.GetItemIconByID(wid.item or wid.sample)
        elseif
            ident
            and not dismissed[wid.slot]
            and G.Get(wid.setting)
            and WornHere(wid, here)
            and Wearing(wid, ident)
        then
            reveal, texture, slot = true, C_Item.GetItemIconByID(ident), wid.slot
        end
        if reveal then
            isShown = isShown + 1
            local widget = Glyph(isShown)
            widget:SetSize(dims, dims)
            widget:ClearAllPoints()
            widget:SetPoint("LEFT", gWindow, "LEFT", (isShown - 1) * (dims + 4), 0)
            widget.tex:SetTexture(texture)
            widget.slot = slot
            widget:Show()
        end
    end
    for catalog = isShown + 1, #gGlyphs do
        gGlyphs[catalog]:Hide()
    end
    gWindow:SetSize(math.max(isShown, 1) * (dims + 4) - 4, dims)
end

local gEv = CreateFrame("Frame")
gEv:SetScript("OnEvent", function(_, evt, slot, hasCurrent)
    if evt == "PLAYER_EQUIPMENT_CHANGED" and not hasCurrent then dismissed[slot] = nil end
    GRefresh()
end)

local function GUse()
    gEv:UnregisterAllEvents()
    if not GOn() then
        if gWindow then gWindow:Hide() end
        return
    end
    if not gWindow then gWindow = CreateFrame("Frame", "CludesUIGearReminders", UIParent) end
    if not CUI._unlockActive then G.Place(gWindow) end
    gWindow:Show()
    for _, event in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }) do
        gEv:RegisterEvent(event)
    end
    GRefresh()
end

G.Start(GUse, {
    key = "CUI_GearReminders",
    label = "Gear Reminders",
    order = 749,
    shown = GOn,
    frame = function(make)
        if make and not gWindow then gWindow = CreateFrame("Frame", "CludesUIGearReminders", UIParent) end
        if make then GRefresh() end
        return gWindow
    end,
    size = function() return G.Get("size") * 2 + 4, G.Get("size") end,
    noAnchorTarget = true,
    noSizeMatchTarget = true,
})

-------------------------------------------------------------------------------
--  Talent Points
-------------------------------------------------------------------------------
local T = module.Feature(
    "talentPoints",
    { enabled = false, size = 22 },
    { point = "CENTER", relPoint = "CENTER", x = 0, y = 300 }
)
local tWindow, tCombat
local function TMake()
    if tWindow then return tWindow end
    tWindow = CreateFrame("Frame", "CludesUITalentPoints", UIParent)
    tWindow:SetSize(300, 32)
    tWindow.text = tWindow:CreateFontString(nil, "OVERLAY")
    tWindow.text:SetPoint("CENTER")
    tWindow.text:SetTextColor(1, 0.82, 0)
    tWindow:Hide()
    return tWindow
end
local function TRefresh()
    if not tWindow then return end
    CUI.Kit.Font(tWindow.text, T.Get("size"), "essentials")
    local points
    if CUI._unlockActive and T.Enabled() then
        points = 2
    elseif T.Enabled() and not tCombat and C_ClassTalents and C_ClassTalents.HasUnspentTalentPoints then
        local unspent, callingPoints, specPoints = C_ClassTalents.HasUnspentTalentPoints()
        if unspent then points = (callingPoints or 0) + (specPoints or 0) end
    end
    if points and points > 0 then
        tWindow.text:SetText(
            points == 1 and CUI.L("1 Unspent Talent Point") or (points .. " Unspent Talent Points")
        )
        tWindow:Show()
    else
        tWindow:Hide()
    end
end
local tEv = CreateFrame("Frame")
tEv:SetScript("OnEvent", function(_, evt)
    if evt == "PLAYER_REGEN_DISABLED" then
        tCombat = true
    elseif evt == "PLAYER_REGEN_ENABLED" then
        tCombat = false
    end
    TRefresh()
end)
local function TUse()
    tEv:UnregisterAllEvents()
    if not T.Enabled() then
        if tWindow then tWindow:Hide() end
        return
    end
    TMake()
    tCombat = UnitAffectingCombat("player")
    for _, event in ipairs({
        "PLAYER_LEVEL_UP",
        "TRAIT_CONFIG_UPDATED",
        "TRAIT_TREE_CURRENCY_INFO_UPDATED",
        "PLAYER_REGEN_DISABLED",
        "PLAYER_REGEN_ENABLED",
        "PLAYER_ENTERING_WORLD",
    }) do
        pcall(tEv.RegisterEvent, tEv, event)
    end
    if not CUI._unlockActive then T.Place(tWindow) end
    TRefresh()
end
T.Start(TUse, {
    key = "CUI_TalentPoints",
    label = "Talent Points",
    order = 750,
    frame = function(make)
        if make then
            TMake()
            TRefresh()
        end
        return tWindow
    end,
    size = function() return 300, 32 end,
    noAnchorTarget = true,
    noSizeMatchTarget = true,
})

CUI._Reminders = {
    restock = {
        Get = R.Get,
        Cfg = R.Cfg,
        Read = R.Read,
        Apply = RUse,
        Reagents = CallingMats,
        Target = Aim,
        Class = CALLING,
    },
    lock = { Get = L.Get, Cfg = L.Cfg },
    gear = { Get = G.Get, Cfg = G.Cfg, Apply = GUse },
    talents = { Get = T.Get, Cfg = T.Cfg, Apply = TUse },
}
