if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if not (CludesUI and CludesUI.IS_FOREVER) then return end
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

local function Font() return CludesUI.GetFontPath("essentials") end
local function Secret(val) return issecretvalue and issecretvalue(val) end
local function Known(ident)
    return C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(ident)
end
local _, CLASS = UnitClass("player")

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
local WEAPON_CLASS, THROWN_SUBCLASS = 2, 16
local THROWN_CLASSES = { ROGUE = true, WARRIOR = true }
local FOOD_CLASS, FOOD_SUBCLASS, OTHER_SUBCLASS = 0, 5, 8
local FOOD_SPELL, NUTRITIOUS_DRINK, DRINK_ITEM = 433, 1249920, 159
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

local function Target(itemId)
    local tbl = R.Read().targets
    return (tbl and tbl[itemId]) or TARGETS[itemId]
end

local pending = {}
local rEvents = CreateFrame("Frame")
local function RequestItem(ident)
    if pending[ident] then return end
    pending[ident] = true
    rEvents:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    C_Item.RequestLoadItemDataByID(ident)
end

local function ItemName(ident) return C_Item.GetItemNameByID(ident) or ("item " .. ident) end

local function KnownReagent(family)
    local entry
    for _, rank in ipairs(family) do
        if Known(rank[1]) then entry = rank[2] end
    end
    return entry
end

local function CarriedAmmo()
    if THROWN_CLASSES[CLASS] then
        local entry = GetInventoryItemID("player", RANGED_SLOT)
        if entry then
            local _, _, _, _, _, classID, subID = C_Item.GetItemInfoInstant(entry)
            if classID == WEAPON_CLASS and subID == THROWN_SUBCLASS then
                local stack = select(8, C_Item.GetItemInfo(entry))
                if not stack then
                    RequestItem(entry)
                    return
                end
                if stack > 1 then return entry end
                return
            end
        end
    end
    return GetInventoryItemID("player", AMMO_SLOT)
end

local function Wanted()
    local wanted = {}
    if R.Get("reagents") then
        for _, frame in ipairs(FAMILIES) do
            local entry = frame.class == CLASS and KnownReagent(frame)
            if entry and Target(entry) > 0 then wanted[entry] = Target(entry) end
        end
    end
    local ammo = R.Get("ammo") and CarriedAmmo()
    if ammo and ammo > 0 then wanted[ammo] = R.Get("ammoTarget") end
    return wanted
end

local function HunterAmmoOn() return CLASS == "HUNTER" and R.Get("hunterAmmo") end

local function ScanBags()
    local food, drink, junk, free = 0, 0, 0, 0
    local drinkSpell = C_Item.GetItemSpell(DRINK_ITEM)
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
                local _, _, _, _, _, classID, subID = C_Item.GetItemInfoInstant(details.itemID)
                local isFood = classID == FOOD_CLASS and (subID == FOOD_SUBCLASS or subID == OTHER_SUBCLASS)
                local level = isFood and select(5, C_Item.GetItemInfo(details.itemID))
                if isFood and not level then RequestItem(details.itemID) end
                if level and level >= R.Get("foodMinLevel") and level <= R.Get("foodMaxLevel") then
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
    for ident, target in pairs(Wanted()) do
        local have = C_Item.GetItemCount(ident)
        local hunterAmmo = HunterAmmoOn() and ident == GetInventoryItemID("player", AMMO_SLOT)
        if not hunterAmmo and have < target then
            lines[#lines + 1] = ("%s  %d / %d"):format(ItemName(ident), have, target)
        end
    end
    table.sort(lines)
    if HunterAmmoOn() then
        local ammo = GetInventoryItemID("player", AMMO_SLOT)
        if ammo and ammo > 0 then
            local have, below = C_Item.GetItemCount(ammo), R.Get("hunterAmmoBelow")
            if have <= below then lines[#lines + 1] = ("%s  %d / %d"):format(ItemName(ammo), have, below) end
        end
    end
    local food, junk, free, drink = ScanBags()
    local below = R.Get("foodBelow")
    if R.Get("food") and food < below then lines[#lines + 1] = ("Food  %d left"):format(food) end
    if R.Get("food") and not NO_DRINK[CLASS] and drink < below then
        lines[#lines + 1] = ("Drink  %d left"):format(drink)
    end
    if R.Get("vendor") then
        if junk > 0 then lines[#lines + 1] = ("Junk to sell  %d"):format(junk) end
        if free < R.Get("bagsBelow") then lines[#lines + 1] = ("Bags nearly full  %d free"):format(free) end
    end
    return lines
end

local alert, flash
local function BuildAlert()
    if alert then return alert end
    alert = CreateFrame("Frame", "CludesUIRestock", UIParent)
    alert:SetSize(240, 60)
    -- A font first: the client refuses text on a FontString without one.
    alert.title = alert:CreateFontString(nil, "OVERLAY")
    alert.title:SetPoint("TOP", 0, -4)
    CludesUI.Kit.Font(alert.title, R.Get("size") + 6, "essentials")
    alert.title:SetTextColor(CludesUI.Kit.Accent())
    alert.title:SetText("Restock")
    alert.text = alert:CreateFontString(nil, "OVERLAY")
    alert.text:SetPoint("TOP", alert.title, "BOTTOM", 0, -4)
    alert.text:SetJustifyH("CENTER")
    CludesUI.Kit.Font(alert.text, R.Get("size"), "essentials")
    flash = alert:CreateAnimationGroup()
    flash:SetLooping("BOUNCE")
    flash:SetScript("OnLoop", function(self)
        self.loops = (self.loops or 0) + 1
        if self.loops >= 6 then self:Stop() end
    end)
    local pulse = flash:CreateAnimation("Alpha")
    pulse:SetFromAlpha(1)
    pulse:SetToAlpha(0.35)
    pulse:SetDuration(0.6)
    alert:Hide()
    return alert
end

local function HideAlert()
    if alert then
        if flash then flash:Stop() end
        alert:Hide()
    end
end

local function ShowAlert(lines)
    BuildAlert()
    local size = R.Get("size")
    CludesUI.Kit.Font(alert.title, size + 6, "essentials")
    CludesUI.Kit.Font(alert.text, size, "essentials")
    alert.text:SetText(table.concat(lines, "\n"))
    alert:SetSize(
        math.max(alert.title:GetStringWidth(), alert.text:GetStringWidth()) + 16,
        alert.title:GetStringHeight() + alert.text:GetStringHeight() + 12
    )
    if not alert:IsShown() then
        alert:Show()
        flash.loops = 0
        flash:Play()
    end
end

local function Check()
    if CludesUI._unlockActive and R.Enabled() then
        ShowAlert({ "Arcane Powder  3 / 20", "Junk to sell  6" })
        return
    end
    if
        not R.Enabled()
        or not IsResting()
        or InCombatLockdown()
        or IsInInstance()
        or (MerchantFrame and MerchantFrame:IsShown())
    then
        HideAlert()
        return
    end
    local lines = Lines()
    if #lines > 0 then
        ShowAlert(lines)
    else
        HideAlert()
    end
end

-- Buys whole bundles up to each target, as far as gold and the vendor's stock allow.
local function Buy()
    if not (R.Enabled() and R.Get("buy")) then return end
    local wanted = Wanted()
    local money = GetMoney()
    local spent, bought = 0, {}
    for index = 1, GetMerchantNumItems() do
        local ident = tonumber((GetMerchantItemLink(index) or ""):match("item:(%d+)"))
        local target = ident and wanted[ident]
        local details = target and C_MerchantFrame.GetItemInfo(index)
        if details and details.isPurchasable and not details.hasExtendedCost then
            local bundle = math.max(details.stackCount, 1)
            local bundles = math.ceil((target - C_Item.GetItemCount(ident)) / bundle)
            if details.numAvailable and details.numAvailable >= 0 then
                bundles = math.min(bundles, details.numAvailable)
            end
            if details.price > 0 then bundles = math.min(bundles, math.floor(money / details.price)) end
            local perBuy = math.max(math.floor(GetMerchantItemMaxStack(index) / bundle), 1)
            if bundles > 0 then
                local leftX = bundles
                while leftX > 0 do
                    local take = math.min(leftX, perBuy)
                    BuyMerchantItem(index, take * bundle)
                    leftX = leftX - take
                end
                money = money - bundles * details.price
                spent = spent + bundles * details.price
                bought[#bought + 1] = bundles * bundle .. "x " .. ItemName(ident)
            end
        end
    end
    if #bought > 0 then
        CludesUI.Print(
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
        return Check()
    end
    if evt == "MERCHANT_SHOW" then
        HideAlert()
        Buy()
    elseif evt == "MERCHANT_CLOSED" then
        C_Timer.After(0.5, Check)
    elseif evt == "PLAYER_REGEN_DISABLED" then
        HideAlert()
    elseif evt == "PLAYER_UPDATE_RESTING" or evt == "PLAYER_ENTERING_WORLD" then
        local resting = IsResting()
        if resting and not wasResting then Check() end
        if not resting then HideAlert() end
        wasResting = resting
    else
        Check()
    end
end)

local function RApply()
    rEvents:UnregisterAllEvents()
    if not R.Enabled() then
        HideAlert()
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
    RequestItem(DRINK_ITEM)
    wasResting = IsResting()
    if alert and not CludesUI._unlockActive then R.Place(alert) end
    Check()
end

--- This class's reagents, for the options page: { {item, name, target}, ... }.
local function ClassReagents()
    local result, seen = {}, {}
    for _, frame in ipairs(FAMILIES) do
        if frame.class == CLASS then
            for _, rank in ipairs(frame) do
                local entry = rank[2]
                if not seen[entry] then
                    seen[entry] = true
                    result[#result + 1] = { item = entry, name = ItemName(entry) }
                end
            end
        end
    end
    return result
end

R.Start(RApply, {
    key = "CUI_Restock",
    label = "Restock Reminder",
    order = 748,
    frame = function(build)
        if build then
            BuildAlert()
            Check()
        end
        return alert
    end,
    size = function() return 240, 60 end,
    noAnchorTarget = true,
    noSizeMatchTarget = true,
})

-------------------------------------------------------------------------------
--  Lockpicking Skill
-------------------------------------------------------------------------------
local LOCKBOX_SKILL = {
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
local lockSkill, lockName
local function ReadSkill()
    local details = C_SkillInfo
        and C_SkillInfo.GetSkillLineInfoByID
        and C_SkillInfo.GetSkillLineInfoByID(LOCKPICKING)
    lockSkill = details and (details.rank + details.modifier)
    lockName = (details and details.name ~= "" and details.name)
        or (C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillDisplayName and C_TradeSkillUI.GetTradeSkillDisplayName(
            LOCKPICKING
        ))
        or "Lockpicking"
end
local lockEv = CreateFrame("Frame")
lockEv:SetScript("OnEvent", ReadSkill)
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, payload)
        if not L.Enabled() then return end
        local ident = payload and payload.id
        if not ident or Secret(ident) then return end
        local need = LOCKBOX_SKILL[ident]
        if not need then return end
        if not lockName then ReadSkill() end
        local red, green, blue
        if not lockSkill then
            red, green, blue = 1, 0.8, 0.2
        elseif lockSkill < need then
            red, green, blue = 1, 0.3, 0.3
        else
            red, green, blue = 0.4, 0.9, 0.5
        end
        tooltip:AddLine(ITEM_MIN_SKILL:format(lockName, need), red, green, blue)
    end)
end
L.Start(function()
    if L.Enabled() then
        lockEv:RegisterEvent("SKILL_LINES_CHANGED")
        ReadSkill()
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
local gFrame
local gIcons, dismissed = {}, {}
local function GOn() return G.Get("worn") or G.Get("pole") end

local function Wearing(wid, ident)
    if wid.item then return ident == wid.item end
    local _, _, _, _, _, classID, subID = C_Item.GetItemInfoInstant(ident)
    return classID == Enum.ItemClass.Weapon and subID == Enum.ItemWeaponSubclass[wid.weapon]
end

local function WornHere(wid, here)
    if wid.instance then return wid.instance == here end
    if wid.where and G.Get(wid.where) == "instance" then
        local _, kind = IsInInstance()
        return kind == "party" or kind == "raid"
    end
    return true
end

local GUpdate
local function Icon(index)
    local widget = gIcons[index]
    if widget then return widget end
    widget = CreateFrame("Button", nil, gFrame)
    widget.tex = widget:CreateTexture(nil, "ARTWORK")
    widget.tex:SetAllPoints()
    widget.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    widget:SetScript("OnEnter", function(self)
        if not self.slot then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetInventoryItem("player", self.slot)
        GameTooltip:AddLine(CludesUI.L("You are wearing this."), CludesUI.Kit.Accent())
        GameTooltip:AddLine(CludesUI.L("Ctrl-click to hide it until you take it off."), 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    widget:SetScript("OnLeave", function() GameTooltip:Hide() end)
    widget:SetScript("OnMouseUp", function(self)
        if self.slot and IsControlKeyDown() then
            dismissed[self.slot] = GetInventoryItemID("player", self.slot)
            GUpdate()
        end
    end)
    gIcons[index] = widget
    return widget
end

GUpdate = function()
    if not gFrame then return end
    local size = G.Get("size")
    local here = select(8, GetInstanceInfo())
    local isShown = 0
    for _, wid in ipairs(WORN) do
        local ident = GetInventoryItemID("player", wid.slot)
        if dismissed[wid.slot] ~= ident then dismissed[wid.slot] = nil end
        local show, texture, slot
        if CludesUI._unlockActive then
            show, texture = G.Get(wid.setting), C_Item.GetItemIconByID(wid.item or wid.sample)
        elseif
            ident
            and not dismissed[wid.slot]
            and G.Get(wid.setting)
            and WornHere(wid, here)
            and Wearing(wid, ident)
        then
            show, texture, slot = true, C_Item.GetItemIconByID(ident), wid.slot
        end
        if show then
            isShown = isShown + 1
            local widget = Icon(isShown)
            widget:SetSize(size, size)
            widget:ClearAllPoints()
            widget:SetPoint("LEFT", gFrame, "LEFT", (isShown - 1) * (size + 4), 0)
            widget.tex:SetTexture(texture)
            widget.slot = slot
            widget:Show()
        end
    end
    for index = isShown + 1, #gIcons do
        gIcons[index]:Hide()
    end
    gFrame:SetSize(math.max(isShown, 1) * (size + 4) - 4, size)
end

local gEv = CreateFrame("Frame")
gEv:SetScript("OnEvent", function(_, evt, slot, hasCurrent)
    if evt == "PLAYER_EQUIPMENT_CHANGED" and not hasCurrent then dismissed[slot] = nil end
    GUpdate()
end)

local function GApply()
    gEv:UnregisterAllEvents()
    if not GOn() then
        if gFrame then gFrame:Hide() end
        return
    end
    if not gFrame then gFrame = CreateFrame("Frame", "CludesUIGearReminders", UIParent) end
    if not CludesUI._unlockActive then G.Place(gFrame) end
    gFrame:Show()
    for _, event in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }) do
        gEv:RegisterEvent(event)
    end
    GUpdate()
end

G.Start(GApply, {
    key = "CUI_GearReminders",
    label = "Gear Reminders",
    order = 749,
    shown = GOn,
    frame = function(build)
        if build and not gFrame then gFrame = CreateFrame("Frame", "CludesUIGearReminders", UIParent) end
        if build then GUpdate() end
        return gFrame
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
local tFrame, tCombat
local function TBuild()
    if tFrame then return tFrame end
    tFrame = CreateFrame("Frame", "CludesUITalentPoints", UIParent)
    tFrame:SetSize(300, 32)
    tFrame.text = tFrame:CreateFontString(nil, "OVERLAY")
    tFrame.text:SetPoint("CENTER")
    tFrame.text:SetTextColor(1, 0.82, 0)
    tFrame:Hide()
    return tFrame
end
local function TUpdate()
    if not tFrame then return end
    CludesUI.Kit.Font(tFrame.text, T.Get("size"), "essentials")
    local points
    if CludesUI._unlockActive and T.Enabled() then
        points = 2
    elseif T.Enabled() and not tCombat and C_ClassTalents and C_ClassTalents.HasUnspentTalentPoints then
        local unspent, classPoints, specPoints = C_ClassTalents.HasUnspentTalentPoints()
        if unspent then points = (classPoints or 0) + (specPoints or 0) end
    end
    if points and points > 0 then
        tFrame.text:SetText(
            points == 1 and CludesUI.L("1 Unspent Talent Point") or (points .. " Unspent Talent Points")
        )
        tFrame:Show()
    else
        tFrame:Hide()
    end
end
local tEv = CreateFrame("Frame")
tEv:SetScript("OnEvent", function(_, evt)
    if evt == "PLAYER_REGEN_DISABLED" then
        tCombat = true
    elseif evt == "PLAYER_REGEN_ENABLED" then
        tCombat = false
    end
    TUpdate()
end)
local function TApply()
    tEv:UnregisterAllEvents()
    if not T.Enabled() then
        if tFrame then tFrame:Hide() end
        return
    end
    TBuild()
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
    if not CludesUI._unlockActive then T.Place(tFrame) end
    TUpdate()
end
T.Start(TApply, {
    key = "CUI_TalentPoints",
    label = "Talent Points",
    order = 750,
    frame = function(build)
        if build then
            TBuild()
            TUpdate()
        end
        return tFrame
    end,
    size = function() return 300, 32 end,
    noAnchorTarget = true,
    noSizeMatchTarget = true,
})

CludesUI._Reminders = {
    restock = {
        Get = R.Get,
        Cfg = R.Cfg,
        Read = R.Read,
        Apply = RApply,
        Reagents = ClassReagents,
        Target = Target,
        Class = CLASS,
    },
    lock = { Get = L.Get, Cfg = L.Cfg },
    gear = { Get = G.Get, Cfg = G.Cfg, Apply = GApply },
    talents = { Get = T.Get, Cfg = T.Cfg, Apply = TApply },
}
