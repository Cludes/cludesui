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
local function Secret(v) return issecretvalue and issecretvalue(v) end
local function Known(id) return C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(id) end
local _, CLASS = UnitClass("player")

-------------------------------------------------------------------------------
--  Restock
-------------------------------------------------------------------------------
-- Per class: a spell family, its ranks as { spellID, reagent itemID }.
local FAMILIES = {
    { class = "DRUID", name = "Rebirth", { 20484, 17034 }, { 20739, 17035 }, { 20742, 17036 }, { 20747, 17037 }, { 20748, 17038 } },
    { class = "DRUID", name = "Gift of the Wild", { 21849, 17021 }, { 21850, 17026 } },
    { class = "MAGE", name = "Arcane Brilliance", { 23028, 17020 } },
    { class = "MAGE", name = "Teleports", { 3561, 17031 }, { 3562, 17031 }, { 3563, 17031 }, { 3565, 17031 },
      { 3566, 17031 }, { 3567, 17031 }, { 1297659, 17031 } },
    { class = "MAGE", name = "Portals", { 10059, 17032 }, { 11416, 17032 }, { 11417, 17032 }, { 11418, 17032 },
      { 11419, 17032 }, { 11420, 17032 } },
    { class = "PALADIN", name = "Divine Intervention", { 19752, 17033 } },
    { class = "PALADIN", name = "Greater Blessings", { 25782, 21177 }, { 25916, 21177 }, { 25890, 21177 },
      { 25894, 21177 }, { 25918, 21177 }, { 25895, 21177 }, { 25898, 21177 } },
    { class = "PRIEST", name = "Prayer of Fortitude", { 21562, 17028 }, { 21564, 17029 } },
    { class = "PRIEST", name = "Prayer of Spirit", { 27681, 17029 } },
    { class = "PRIEST", name = "Prayer of Shadow Protection", { 27683, 17029 } },
    { class = "SHAMAN", name = "Reincarnation", { 20608, 17030 }, { 21169, 17030 }, { 27740, 17030 } },
    { class = "WARLOCK", name = "Ritual of Doom", { 18540, 16583 } },
    { class = "WARLOCK", name = "Inferno", { 1122, 5565 }, { 24670, 5565 } },
    { class = "ROGUE", name = "Vanish", { 1856, 5140 }, { 1857, 5140 }, { 27617, 5140 }, { 457437, 5140 }, { 1285372, 5140 } },
}
local TARGETS = {
    [17034] = 5, [17035] = 5, [17036] = 5, [17037] = 5, [17038] = 5, [17021] = 20, [17026] = 20,
    [17020] = 20, [17031] = 10, [17032] = 10, [17033] = 5, [21177] = 100, [17028] = 20, [17029] = 20,
    [17030] = 5, [16583] = 5, [5565] = 5, [5140] = 20,
}
local FOOD_AND_DRINK = {
    [13724] = true, [19301] = true, [20031] = true, [21215] = true, [21537] = true, [23172] = true,
    [23176] = true, [262433] = true, [282018] = true, [3448] = true, [20388] = true, [20389] = true, [20390] = true,
}
local AMMO_SLOT, RANGED_SLOT = 0, 18
local WEAPON_CLASS, THROWN_SUBCLASS = 2, 16
local THROWN_CLASSES = { ROGUE = true, WARRIOR = true }
local FOOD_CLASS, FOOD_SUBCLASS, OTHER_SUBCLASS = 0, 5, 8
local FOOD_SPELL, NUTRITIOUS_DRINK, DRINK_ITEM = 433, 1249920, 159
local NO_DRINK = { WARRIOR = true, ROGUE = true }

local R = module.Feature("restock", { enabled = true, reagents = true, ammo = true, ammoTarget = 1000,
    food = true, foodBelow = 10, foodMinLevel = 0, foodMaxLevel = 60, vendor = true, bagsBelow = 4,
    buy = false, hunterAmmo = false, hunterAmmoBelow = 500, size = 16 },
    { point = "CENTER", relPoint = "CENTER", x = 0, y = 120 })

local function Target(itemID)
    local t = R.Read().targets
    return (t and t[itemID]) or TARGETS[itemID]
end

local pending = {}
local rEvents = CreateFrame("Frame")
local function RequestItem(id)
    if pending[id] then return end
    pending[id] = true
    rEvents:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    C_Item.RequestLoadItemDataByID(id)
end

local function ItemName(id) return C_Item.GetItemNameByID(id) or ("item " .. id) end

local function KnownReagent(family)
    local item
    for _, rank in ipairs(family) do if Known(rank[1]) then item = rank[2] end end
    return item
end

local function CarriedAmmo()
    if THROWN_CLASSES[CLASS] then
        local item = GetInventoryItemID("player", RANGED_SLOT)
        if item then
            local _, _, _, _, _, classID, subID = C_Item.GetItemInfoInstant(item)
            if classID == WEAPON_CLASS and subID == THROWN_SUBCLASS then
                local stack = select(8, C_Item.GetItemInfo(item))
                if not stack then RequestItem(item) return end
                if stack > 1 then return item end
                return
            end
        end
    end
    return GetInventoryItemID("player", AMMO_SLOT)
end

local function Wanted()
    local want = {}
    if R.Get("reagents") then
        for _, f in ipairs(FAMILIES) do
            local item = f.class == CLASS and KnownReagent(f)
            if item and Target(item) > 0 then want[item] = Target(item) end
        end
    end
    local ammo = R.Get("ammo") and CarriedAmmo()
    if ammo and ammo > 0 then want[ammo] = R.Get("ammoTarget") end
    return want
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
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info then
                if info.quality == Enum.ItemQuality.Poor and not info.hasNoValue then junk = junk + 1 end
                local _, _, _, _, _, classID, subID = C_Item.GetItemInfoInstant(info.itemID)
                local isFood = classID == FOOD_CLASS and (subID == FOOD_SUBCLASS or subID == OTHER_SUBCLASS)
                local level = isFood and select(5, C_Item.GetItemInfo(info.itemID))
                if isFood and not level then RequestItem(info.itemID) end
                if level and level >= R.Get("foodMinLevel") and level <= R.Get("foodMaxLevel") then
                    local spell = C_Item.GetItemSpell(info.itemID)
                    if FOOD_AND_DRINK[info.itemID] then
                        food, drink = food + info.stackCount, drink + info.stackCount
                    elseif spell and (spell == drinkSpell or spell == nutritious) then
                        drink = drink + info.stackCount
                    elseif subID == FOOD_SUBCLASS or spell == foodSpell then
                        food = food + info.stackCount
                    end
                end
            end
        end
    end
    return food, junk, free, drink
end

local function Lines()
    local lines = {}
    for id, target in pairs(Wanted()) do
        local have = C_Item.GetItemCount(id)
        local hunterAmmo = HunterAmmoOn() and id == GetInventoryItemID("player", AMMO_SLOT)
        if not hunterAmmo and have < target then lines[#lines + 1] = ("%s  %d / %d"):format(ItemName(id), have, target) end
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
    if R.Get("food") and not NO_DRINK[CLASS] and drink < below then lines[#lines + 1] = ("Drink  %d left"):format(drink) end
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
    alert.title = alert:CreateFontString(nil, "OVERLAY")
    alert.title:SetPoint("TOP", 0, -4)
    alert.title:SetTextColor(CludesUI.Kit.Accent())
    alert.title:SetText("Restock")
    alert.text = alert:CreateFontString(nil, "OVERLAY")
    alert.text:SetPoint("TOP", alert.title, "BOTTOM", 0, -4)
    alert.text:SetJustifyH("CENTER")
    flash = alert:CreateAnimationGroup()
    flash:SetLooping("BOUNCE")
    flash:SetScript("OnLoop", function(self)
        self.loops = (self.loops or 0) + 1
        if self.loops >= 6 then self:Stop() end
    end)
    local pulse = flash:CreateAnimation("Alpha")
    pulse:SetFromAlpha(1); pulse:SetToAlpha(0.35); pulse:SetDuration(0.6)
    alert:Hide()
    return alert
end

local function HideAlert() if alert then flash:Stop(); alert:Hide() end end

local function ShowAlert(lines)
    BuildAlert()
    local size = R.Get("size")
    CludesUI.Kit.Font(alert.title, size + 6, "essentials")
    CludesUI.Kit.Font(alert.text, size, "essentials")
    alert.text:SetText(table.concat(lines, "\n"))
    alert:SetSize(math.max(alert.title:GetStringWidth(), alert.text:GetStringWidth()) + 16,
        alert.title:GetStringHeight() + alert.text:GetStringHeight() + 12)
    if not alert:IsShown() then
        alert:Show()
        flash.loops = 0
        flash:Play()
    end
end

local function Check()
    if CludesUI._unlockActive and R.Enabled() then ShowAlert({ "Arcane Powder  3 / 20", "Junk to sell  6" }) return end
    if not R.Enabled() or not IsResting() or InCombatLockdown() or IsInInstance()
        or (MerchantFrame and MerchantFrame:IsShown()) then
        HideAlert()
        return
    end
    local lines = Lines()
    if #lines > 0 then ShowAlert(lines) else HideAlert() end
end

-- Buys whole bundles up to each target, as far as gold and the vendor's stock allow.
local function Buy()
    if not (R.Enabled() and R.Get("buy")) then return end
    local want = Wanted()
    local money = GetMoney()
    local spent, bought = 0, {}
    for index = 1, GetMerchantNumItems() do
        local id = tonumber((GetMerchantItemLink(index) or ""):match("item:(%d+)"))
        local target = id and want[id]
        local info = target and C_MerchantFrame.GetItemInfo(index)
        if info and info.isPurchasable and not info.hasExtendedCost then
            local bundle = math.max(info.stackCount, 1)
            local bundles = math.ceil((target - C_Item.GetItemCount(id)) / bundle)
            if info.numAvailable and info.numAvailable >= 0 then bundles = math.min(bundles, info.numAvailable) end
            if info.price > 0 then bundles = math.min(bundles, math.floor(money / info.price)) end
            local perBuy = math.max(math.floor(GetMerchantItemMaxStack(index) / bundle), 1)
            if bundles > 0 then
                local left = bundles
                while left > 0 do
                    local take = math.min(left, perBuy)
                    BuyMerchantItem(index, take * bundle)
                    left = left - take
                end
                money = money - bundles * info.price
                spent = spent + bundles * info.price
                bought[#bought + 1] = bundles * bundle .. "x " .. ItemName(id)
            end
        end
    end
    if #bought > 0 then
        CludesUI.Print("|cff4cc9f0Restocked|r " .. table.concat(bought, ", ") .. " for "
            .. C_CurrencyInfo.GetCoinTextureString(math.floor(spent)))
    end
end

local wasResting
rEvents:SetScript("OnEvent", function(_, event, id)
    if event == "GET_ITEM_INFO_RECEIVED" then
        if not pending[id] then return end
        pending[id] = nil
        if not next(pending) then rEvents:UnregisterEvent("GET_ITEM_INFO_RECEIVED") end
        return Check()
    end
    if event == "MERCHANT_SHOW" then
        HideAlert()
        Buy()
    elseif event == "MERCHANT_CLOSED" then
        C_Timer.After(0.5, Check)
    elseif event == "PLAYER_REGEN_DISABLED" then
        HideAlert()
    elseif event == "PLAYER_UPDATE_RESTING" or event == "PLAYER_ENTERING_WORLD" then
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
    if not R.Enabled() then HideAlert() return end
    for id in pairs(TARGETS) do C_Item.RequestLoadItemDataByID(id) end
    for _, e in ipairs({ "MERCHANT_SHOW", "MERCHANT_CLOSED", "PLAYER_UPDATE_RESTING", "PLAYER_ENTERING_WORLD",
                         "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "BAG_UPDATE_DELAYED" }) do
        rEvents:RegisterEvent(e)
    end
    if R.Get("ammo") or HunterAmmoOn() then rEvents:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player") end
    RequestItem(DRINK_ITEM)
    wasResting = IsResting()
    if alert and not CludesUI._unlockActive then R.Place(alert) end
    Check()
end

--- This class's reagents, for the options page: { {item, name, target}, ... }.
local function ClassReagents()
    local out, seen = {}, {}
    for _, f in ipairs(FAMILIES) do
        if f.class == CLASS then
            for _, rank in ipairs(f) do
                local item = rank[2]
                if not seen[item] then
                    seen[item] = true
                    out[#out + 1] = { item = item, name = ItemName(item) }
                end
            end
        end
    end
    return out
end

R.Start(RApply, {
    key = "CUI_Restock", label = "Restock Reminder", order = 748,
    frame = function(build) if build then BuildAlert(); Check() end; return alert end,
    size = function() return 240, 60 end,
    noAnchorTarget = true, noSizeMatchTarget = true,
})

-------------------------------------------------------------------------------
--  Lockpicking Skill
-------------------------------------------------------------------------------
local LOCKBOX_SKILL = {
    [4632] = 1, [4633] = 25, [4634] = 70, [4636] = 125, [4637] = 175, [4638] = 225, [5046] = 70,
    [5758] = 225, [5759] = 225, [5760] = 225, [6354] = 1, [6355] = 70, [6712] = 1, [7209] = 1,
    [7869] = 70, [12033] = 275, [13875] = 175, [13918] = 250, [16882] = 1, [16883] = 70, [16884] = 175,
    [16885] = 250, [208838] = 1, [227937] = 175,
}
local LOCKPICKING = 633
local L = module.Feature("lockboxSkill", { enabled = false })
local lockSkill, lockName
local function ReadSkill()
    local info = C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID and C_SkillInfo.GetSkillLineInfoByID(LOCKPICKING)
    lockSkill = info and (info.rank + info.modifier)
    lockName = (info and info.name ~= "" and info.name)
        or (C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillDisplayName and C_TradeSkillUI.GetTradeSkillDisplayName(LOCKPICKING))
        or "Lockpicking"
end
local lockEv = CreateFrame("Frame")
lockEv:SetScript("OnEvent", ReadSkill)
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
        if not L.Enabled() then return end
        local id = data and data.id
        if not id or Secret(id) then return end
        local need = LOCKBOX_SKILL[id]
        if not need then return end
        if not lockName then ReadSkill() end
        local r, g, b
        if not lockSkill then r, g, b = 1, 0.8, 0.2
        elseif lockSkill < need then r, g, b = 1, 0.3, 0.3
        else r, g, b = 0.4, 0.9, 0.5 end
        tooltip:AddLine(ITEM_MIN_SKILL:format(lockName, need), r, g, b)
    end)
end
L.Start(function()
    if L.Enabled() then lockEv:RegisterEvent("SKILL_LINES_CHANGED"); ReadSkill() else lockEv:UnregisterAllEvents() end
end)

-------------------------------------------------------------------------------
--  Gear Reminders
-------------------------------------------------------------------------------
local WORN = {
    { item = 273084, slot = 15, instance = 43, setting = "worn" },                       -- Cloak of Hermitic Bliss, Wailing Caverns
    { weapon = "Fishingpole", sample = 6256, slot = 16, where = "poleWhere", setting = "pole" },
}
local G = module.Feature("gearReminders", { worn = false, pole = false, poleWhere = "always", size = 48 },
    { point = "TOP", relPoint = "TOP", x = 0, y = -290 })
local gFrame
local gIcons, dismissed = {}, {}
local function GOn() return G.Get("worn") or G.Get("pole") end

local function Wearing(w, id)
    if w.item then return id == w.item end
    local _, _, _, _, _, classID, subID = C_Item.GetItemInfoInstant(id)
    return classID == Enum.ItemClass.Weapon and subID == Enum.ItemWeaponSubclass[w.weapon]
end

local function WornHere(w, here)
    if w.instance then return w.instance == here end
    if w.where and G.Get(w.where) == "instance" then
        local _, kind = IsInInstance()
        return kind == "party" or kind == "raid"
    end
    return true
end

local GUpdate
local function Icon(i)
    local b = gIcons[i]
    if b then return b end
    b = CreateFrame("Button", nil, gFrame)
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetAllPoints()
    b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b:SetScript("OnEnter", function(self)
        if not self.slot then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetInventoryItem("player", self.slot)
        GameTooltip:AddLine(CludesUI.L("You are wearing this."), CludesUI.Kit.Accent())
        GameTooltip:AddLine(CludesUI.L("Ctrl-click to hide it until you take it off."), 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnMouseUp", function(self)
        if self.slot and IsControlKeyDown() then
            dismissed[self.slot] = GetInventoryItemID("player", self.slot)
            GUpdate()
        end
    end)
    gIcons[i] = b
    return b
end

GUpdate = function()
    if not gFrame then return end
    local size = G.Get("size")
    local here = select(8, GetInstanceInfo())
    local shown = 0
    for _, w in ipairs(WORN) do
        local id = GetInventoryItemID("player", w.slot)
        if dismissed[w.slot] ~= id then dismissed[w.slot] = nil end
        local show, tex, slot
        if CludesUI._unlockActive then
            show, tex = G.Get(w.setting), C_Item.GetItemIconByID(w.item or w.sample)
        elseif id and not dismissed[w.slot] and G.Get(w.setting) and WornHere(w, here) and Wearing(w, id) then
            show, tex, slot = true, C_Item.GetItemIconByID(id), w.slot
        end
        if show then
            shown = shown + 1
            local b = Icon(shown)
            b:SetSize(size, size)
            b:ClearAllPoints()
            b:SetPoint("LEFT", gFrame, "LEFT", (shown - 1) * (size + 4), 0)
            b.tex:SetTexture(tex)
            b.slot = slot
            b:Show()
        end
    end
    for i = shown + 1, #gIcons do gIcons[i]:Hide() end
    gFrame:SetSize(math.max(shown, 1) * (size + 4) - 4, size)
end

local gEv = CreateFrame("Frame")
gEv:SetScript("OnEvent", function(_, event, slot, hasCurrent)
    if event == "PLAYER_EQUIPMENT_CHANGED" and not hasCurrent then dismissed[slot] = nil end
    GUpdate()
end)

local function GApply()
    gEv:UnregisterAllEvents()
    if not GOn() then if gFrame then gFrame:Hide() end return end
    if not gFrame then gFrame = CreateFrame("Frame", "CludesUIGearReminders", UIParent) end
    if not CludesUI._unlockActive then G.Place(gFrame) end
    gFrame:Show()
    for _, e in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }) do gEv:RegisterEvent(e) end
    GUpdate()
end

G.Start(GApply, {
    key = "CUI_GearReminders", label = "Gear Reminders", order = 749,
    shown = GOn,
    frame = function(build)
        if build and not gFrame then gFrame = CreateFrame("Frame", "CludesUIGearReminders", UIParent) end
        if build then GUpdate() end
        return gFrame
    end,
    size = function() return G.Get("size") * 2 + 4, G.Get("size") end,
    noAnchorTarget = true, noSizeMatchTarget = true,
})

-------------------------------------------------------------------------------
--  Talent Points
-------------------------------------------------------------------------------
local T = module.Feature("talentPoints", { enabled = false, size = 22 },
    { point = "CENTER", relPoint = "CENTER", x = 0, y = 300 })
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
        tFrame.text:SetText(points == 1 and CludesUI.L("1 Unspent Talent Point") or (points .. " Unspent Talent Points"))
        tFrame:Show()
    else
        tFrame:Hide()
    end
end
local tEv = CreateFrame("Frame")
tEv:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then tCombat = true elseif event == "PLAYER_REGEN_ENABLED" then tCombat = false end
    TUpdate()
end)
local function TApply()
    tEv:UnregisterAllEvents()
    if not T.Enabled() then if tFrame then tFrame:Hide() end return end
    TBuild()
    tCombat = UnitAffectingCombat("player")
    for _, e in ipairs({ "PLAYER_LEVEL_UP", "TRAIT_CONFIG_UPDATED", "TRAIT_TREE_CURRENCY_INFO_UPDATED",
                         "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD" }) do
        pcall(tEv.RegisterEvent, tEv, e)
    end
    if not CludesUI._unlockActive then T.Place(tFrame) end
    TUpdate()
end
T.Start(TApply, {
    key = "CUI_TalentPoints", label = "Talent Points", order = 750,
    frame = function(build) if build then TBuild(); TUpdate() end; return tFrame end,
    size = function() return 300, 32 end,
    noAnchorTarget = true, noSizeMatchTarget = true,
})

CludesUI._Reminders = {
    restock = { Get = R.Get, Cfg = R.Cfg, Read = R.Read, Apply = RApply, Reagents = ClassReagents, Target = Target, Class = CLASS },
    lock = { Get = L.Get, Cfg = L.Cfg },
    gear = { Get = G.Get, Cfg = G.Cfg, Apply = GApply },
    talents = { Get = T.Get, Cfg = T.Cfg, Apply = TApply },
}
