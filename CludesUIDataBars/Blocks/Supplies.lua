if CUI_CLIENT_BLOCKED then
    return
end
if not CludesUI.IS_FOREVER then
    return
end
-- Carried class resources on WoW Forever. Banks and crafting materials are excluded.
local ADDON_NAME, mod = ...
local K = mod.BlockKit
local max, floor = math.max, math.floor
local QUESTION_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

-- Spell reagents span several item classes; projectile/thrown IDs are discovered.
local CLASS_ITEMS = {
    WARLOCK = { { 6265, "Soul Shard" }, { 5565, "Infernal Stone" }, { 16583, "Demonic Figurine" } },
    MAGE = {
        { 17020, "Arcane Powder" },
        { 17031, "Rune of Teleportation" },
        { 17032, "Rune of Portals" },
        { 17056, "Light Feather" },
    },
    PRIEST = { { 17028, "Holy Candle" }, { 17029, "Sacred Candle" }, { 17056, "Light Feather" } },
    PALADIN = { { 21177, "Symbol of Kings" }, { 17033, "Symbol of Divinity" } },
    DRUID = {
        { 17021, "Wild Berries" },
        { 17026, "Wild Thornroot" },
        { 17034, "Maple Seed" },
        { 17035, "Stranglethorn Seed" },
        { 17036, "Ashwood Seed" },
        { 17037, "Hornbeam Seed" },
        { 17038, "Ironwood Seed" },
    },
    SHAMAN = { { 17030, "Ankh" }, { 17057, "Shiny Fish Scales" }, { 17058, "Fish Oil" } },
    ROGUE = {
        { 5140, "Flash Powder", spells = { 1856, 1857, 26889 } },
        { 5530, "Blinding Powder", spells = { 2094 } },
        { 5060, "Thieves' Tools", spells = { 1804 }, tooltipOnly = true },
        {
            6947,
            "Instant Poison",
            ranks = {
                { 6947, 8681 },
                { 6949, 8687 },
                { 6950, 8691 },
                { 8926, 11341 },
                { 8927, 11342 },
                { 8928, 11343 },
            },
        },
        {
            2892,
            "Deadly Poison",
            ranks = { { 2892, 2835 }, { 2893, 2837 }, { 8984, 11357 }, { 8985, 11358 }, { 20844, 25347 } },
        },
        { 3775, "Crippling Poison", ranks = { { 3775, 3420 }, { 3776, 3421 } } },
        { 5237, "Mind-numbing Poison", ranks = { { 5237, 5763 }, { 6951, 8694 }, { 9186, 11400 } } },
        {
            10918,
            "Wound Poison",
            ranks = { { 10918, 13220 }, { 10920, 13228 }, { 10921, 13229 }, { 10922, 13230 } },
        },
    },
}

local RANGED_CLASS = { HUNTER = true, ROGUE = true, WARRIOR = true }

-- Ammo and thrown come first for ranged classes. Spell requirements are
-- normalised to the ranks' {itemID, spellID} shape.
local function BuildResources(class)
    local resources, byID = {}, {}
    if RANGED_CLASS[class] then
        resources[1] = { key = "ammo", label = "Ammo", fallback = "Interface\\Icons\\INV_Ammo_Arrow_02" }
        resources[2] =
            { key = "thrown", label = "Thrown", fallback = "Interface\\Icons\\INV_ThrowingKnife_02" }
    end
    for _, specInfo in ipairs(CLASS_ITEMS[class] or {}) do
        local ident = specInfo[1]
        local resource = {
            key = ident,
            id = ident,
            label = specInfo[2],
            ranks = specInfo.ranks,
            learn = specInfo.ranks,
            tooltipOnly = specInfo.tooltipOnly,
        }
        if specInfo.spells then
            resource.learn = {}
            for idx, spellId in ipairs(specInfo.spells) do
                resource.learn[idx] = { ident, spellId }
            end
        end
        for _, rank in ipairs(specInfo.ranks or {}) do
            byID[rank[1]] = resource
        end
        byID[ident] = resource
        resources[#resources + 1] = resource
    end
    return resources, byID
end

function mod.ClassResourceShown(prefs, key)
    local hidden = prefs.hiddenItems
    return not (hidden and hidden[key])
end

function mod.ClassResourceChoices()
    local _, class = UnitClass("player")
    local choices = BuildResources(class)
    for _, choice in ipairs(choices) do
        choice.label = choice.id and C_Item.GetItemNameByID(choice.id) or choice.label
    end
    return choices
end

mod.BlockFactories.supplies = function(blockCfg, slot, contentFrame, barCtx)
    local instance = { cfg = blockCfg, slot = slot, content = contentFrame, ctx = barCtx }
    instance.key = K.InstKey(barCtx, blockCfg)
    instance.events = { "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED", "GET_ITEM_INFO_RECEIVED" }
    local _, class = UnitClass("player")
    -- Equipped ammo and thrown weapons change outside the bags. Ammo itself
    -- lives in the bags (BAG_UPDATE_DELAYED); UNIT_INVENTORY_CHANGED only
    -- matters for a stacked thrown weapon (see the handler).
    if RANGED_CLASS[class] then
        instance.events[#instance.events + 1] = "UNIT_INVENTORY_CHANGED"
        instance.events[#instance.events + 1] = "PLAYER_EQUIPMENT_CHANGED"
        instance.events[#instance.events + 1] = "UPDATE_INVENTORY_DURABILITY"
    end
    if class == "ROGUE" then
        instance.events[#instance.events + 1] = "SPELLS_CHANGED"
        instance.events[#instance.events + 1] = "PLAYER_LEVEL_UP"
        instance.events[#instance.events + 1] = "SKILL_LINES_CHANGED"
    end
    local resources, byID = BuildResources(class)
    local itemCounts, itemOrder, pending, itemUses = {}, {}, {}, {}
    local rangedClass = RANGED_CLASS[class]
    local ammoSlot = rangedClass and GetInventorySlotInfo("AmmoSlot")
    local rangedSlot = rangedClass and GetInventorySlotInfo("RangedSlot")
    local ammo, thrown, rangedCount
    if rangedClass then
        ammo, thrown = resources[1], resources[2]
    end
    -- Nothing to show: a dim "None" (no icon or count) keeps the hover and
    -- right-click target.
    local empty = {}
    local dirty, hovered = true, false
    local btnFrame = CreateFrame("Button", nil, contentFrame)
    btnFrame:SetAllPoints()
    btnFrame:EnableMouse(true)
    btnFrame:RegisterForClicks("RightButtonUp")
    local rowList = {}

    local function AddItem(resource, ident, amount)
        resource.present = true
        resource.count = resource.count + amount
        if not resource.firstID or ident < resource.firstID then
            resource.firstID = ident
        end
        if not itemCounts[ident] then
            itemOrder[#itemOrder + 1] = ident
        end
        itemCounts[ident] = (itemCounts[ident] or 0) + amount
    end

    local function Request(ident)
        if pending[ident] then
            return
        end
        pending[ident] = true
        C_Item.RequestLoadItemDataByID(ident)
    end

    local function RangedResource(ident)
        if ammo.id == ident then
            return ammo
        end
        local _, _, _, _, _, itemClass, subclass = C_Item.GetItemInfoInstant(ident)
        if itemClass == Enum.ItemClass.Projectile then
            return ammo
        end
        if itemClass == Enum.ItemClass.Weapon and subclass == Enum.ItemWeaponSubclass.Thrown then
            return thrown
        end
        if not itemClass then
            ammo.unknown, thrown.unknown = true, true
            Request(ident)
        end
    end

    local function Sample()
        dirty = false
        wipe(itemCounts)
        wipe(itemOrder)
        wipe(itemUses)
        if thrown then
            thrown.id = nil
        end
        for _, resource in ipairs(resources) do
            resource.count, resource.firstID, resource.unknown, resource.present = 0, nil, false, false
            -- Every class reagent shows by default (0 when missing); the player
            -- hides unwanted ones. Only spell-gated entries wait to be learned.
            resource.available = not resource.learn
            if resource.learn then
                for _, pair in ipairs(resource.learn) do
                    if C_SpellBook.IsSpellKnown(pair[2]) then
                        resource.available, resource.zeroID = true, pair[1]
                    end
                end
            end
            -- Keep learned reagents visible at zero; poison ranks are added below.
            if resource.id and resource ~= ammo and not resource.ranks and resource.available then
                itemCounts[resource.id] = 0
                itemOrder[#itemOrder + 1] = resource.id
            end
        end
        if ammo then
            ammo.id = GetInventoryItemID("player", ammoSlot)
            local rangedID = GetInventoryItemID("player", rangedSlot)
            local _, _, _, _, _, itemClass, subclass = C_Item.GetItemInfoInstant(rangedID or 0)
            ammo.active = itemClass == Enum.ItemClass.Weapon
                and (
                    subclass == Enum.ItemWeaponSubclass.Bows
                    or subclass == Enum.ItemWeaponSubclass.Guns
                    or subclass == Enum.ItemWeaponSubclass.Crossbow
                )
            if rangedID and not itemClass then
                Request(rangedID)
            end
            rangedCount = GetInventoryItemCount("player", rangedSlot)
        end
        -- Every carried bag, the reagent bag included.
        for bag = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4 do
            for bagSlot = 1, C_Container.GetContainerNumSlots(bag) do
                -- The ID read allocates nothing; the info table only for our items.
                local itemId = C_Container.GetContainerItemID(bag, bagSlot)
                if itemId then
                    local resource = byID[itemId]
                    if not resource and rangedClass then
                        resource = RangedResource(itemId)
                    end
                    if resource and resource ~= thrown then
                        local usable = resource.available
                        if resource.ranks then
                            local _, _, _, _, requiredLevel = C_Item.GetItemInfo(itemId)
                            if requiredLevel then
                                usable = UnitLevel("player") >= requiredLevel
                            else
                                usable = false
                                resource.unknown = true
                                Request(itemId)
                            end
                        end
                        if usable then
                            local details = C_Container.GetContainerItemInfo(bag, bagSlot)
                            AddItem(resource, itemId, details and details.stackCount or 0)
                            resource.available = true
                        end
                    end
                end
            end
        end
        -- Only the equipped thrown weapon contributes uses or stack units.
        if thrown then
            local ident = GetInventoryItemID("player", rangedSlot)
            if ident and RangedResource(ident) == thrown then
                local current, maximum = GetInventoryItemDurability(rangedSlot)
                if current ~= nil and maximum and maximum > 0 then
                    AddItem(thrown, ident, current)
                    itemUses[ident] = true
                    -- Durable thrown weapons spend durability instead of stack units.
                    thrown.id, thrown.count = ident, current
                    thrown.unknown = false
                else
                    AddItem(thrown, ident, GetInventoryItemCount("player", rangedSlot) or 0)
                end
            end
        end
        if ammo then
            -- The ammo slot already counts the selected item across carried
            -- stacks. Do not add it to the bags or combine other projectile IDs.
            local ident = ammo.id
            local total = ident and GetInventoryItemCount("player", ammoSlot)
            ammo.id, ammo.firstID = ident, nil
            ammo.icon = ident and GetInventoryItemTexture("player", ammoSlot) or nil
            ammo.count, ammo.unknown = total or 0, ident ~= nil and total == nil
            if ident then
                if not itemCounts[ident] then
                    itemOrder[#itemOrder + 1] = ident
                end
                itemCounts[ident] = total
                if not C_Item.GetItemNameByID(ident) then
                    Request(ident)
                end
            end
        end
        for ident in pairs(pending) do
            if C_Item.GetItemCount(ident, false, false, false, false) == 0 then
                pending[ident] = nil
            end
        end
        for _, resource in ipairs(resources) do
            if resource.ranks and resource.available and not resource.present then
                local ident = resource.zeroID or resource.id
                itemCounts[ident] = 0
                itemOrder[#itemOrder + 1] = ident
            end
        end
        table.sort(itemOrder)
    end

    local function Name(resource)
        return (resource.id and C_Item.GetItemNameByID(resource.id)) or CludesUI.L(resource.label)
    end

    local function ShowTooltip()
        mod.Tip_Begin(btnFrame)
        mod.Tip_AddLine(CludesUI.L("Class Resources"), 1, 1, 1)
        local isShown = 0
        for _, ident in ipairs(itemOrder) do
            local resource = byID[ident] or (rangedClass and RangedResource(ident))
            if
                resource
                and (resource ~= ammo or ammo.active)
                and mod.ClassResourceShown(blockCfg.settings or {}, resource.key)
            then
                local name = C_Item.GetItemNameByID(ident) or Name(resource)
                if itemUses[ident] then
                    name = name .. " - " .. CludesUI.L("Remaining uses")
                end
                local value = itemCounts[ident] == nil and "?" or tostring(itemCounts[ident])
                if resource.tooltipOnly then
                    value = CludesUI.L(itemCounts[ident] > 0 and "Available" or "Missing")
                end
                mod.Tip_AddDouble(name, value, 0.8, 0.8, 0.8, 1, 1, 1)
                isShown = isShown + 1
            end
        end
        if isShown == 0 then
            mod.Tip_AddLine(CludesUI.L("No class resources in inventory"), 0.6, 0.6, 0.6)
        end
        if next(pending) then
            mod.Tip_AddLine(CludesUI.L("Loading item data..."), 0.6, 0.6, 0.6)
        end
        mod.Tip_AddLine(" ")
        mod.Tip_AddLine(CludesUI.L("Right-click to edit visible items."), 0.6, 0.6, 0.6)
        mod.Tip_Show()
    end

    -- Per-refresh layout state shared with Draw, so no closure is built per refresh.
    local s, fontSize, iconSize, vertical, width, posX, posY, used
    local tr, tg, tb, ir, ig, ib

    local function Draw(resource)
        used = used + 1
        local row = rowList[used]
        if not row then
            row = {
                icon = btnFrame:CreateTexture(nil, "OVERLAY"),
                text = btnFrame:CreateFontString(nil, "OVERLAY"),
            }
            rowList[used] = row
            K.AttachTextOffset(instance, row.text)
        end
        local isEmpty = resource == empty
        local value
        if isEmpty then
            value = CludesUI.L("None")
        else
            value = resource.unknown and "?"
                or (BreakUpLargeNumbers and BreakUpLargeNumbers(resource.count) or tostring(resource.count))
            -- Without icons, names keep unrelated resource counts identifiable.
            if s.showLabel or iconSize == 0 then
                value = Name(resource) .. ": " .. value
            end
        end
        mod.SetFont(row.text, fontSize, barCtx.cfg)
        row.text:SetText(value)
        row.alpha = isEmpty and 0.5 or 1
        row.text:SetTextColor(tr, tg, tb, row.alpha)
        row.text:ClearAllPoints()
        row.text:Show()
        local ident = resource.id or resource.firstID
        row.icon:SetTexture(
            resource.icon or (ident and C_Item.GetItemIconByID(ident)) or resource.fallback or QUESTION_ICON
        )
        K.CropStockIcon(row.icon)
        row.icon:SetVertexColor(ir, ig, ib, 1)
        row.icon:ClearAllPoints()
        local iconShown = iconSize > 0 and not isEmpty
        if iconShown then
            row.icon:SetSize(iconSize, iconSize)
            row.icon:Show()
        else
            row.icon:Hide()
        end
        if vertical then
            mod.SetWrappedText(row.text, max(24, width - 8), "CENTER")
            if iconShown then
                row.icon:SetPoint("TOP", btnFrame, "TOP", 0, -posY)
                posY = posY + iconSize + 2
            end
            row.text:SetPoint("TOP", btnFrame, "TOP", 0, -posY)
            posY = posY + mod.SnapToPixelGrid(row.text:GetStringHeight()) + 4
        else
            mod.ResetInlineText(row.text, "LEFT")
            if used > 1 then
                posX = posX + 12
            end
            if iconShown then
                row.icon:SetPoint("LEFT", btnFrame, "LEFT", posX, 0)
                posX = posX + iconSize + K.ICON_GAP
            end
            row.text:SetPoint("LEFT", btnFrame, "LEFT", posX, 0)
            posX = posX + mod.SnapToPixelGrid(row.text:GetStringWidth())
        end
    end

    function instance:Refresh()
        if dirty then
            Sample()
        end
        s = blockCfg.settings or {}
        fontSize = max(9, floor(K.CONTENT_BASE * 0.4333 + 0.5))
        iconSize = s.showIcon ~= false and fontSize + 2 or 0
        vertical = barCtx.IsVertical()
        local barH = barCtx.GetThickness()
        width = vertical and K.VSlotW(instance) or 0
        posX, posY, used = 0, 4, 0
        tr, tg, tb = K.BlockColorOf(blockCfg)
        if hovered then
            tr, tg, tb = mod.GetAccent()
        end
        ir, ig, ib = K.IconColorOf(blockCfg)
        for _, resource in ipairs(resources) do
            if
                not resource.tooltipOnly
                and (resource.available or resource.unknown)
                and mod.ClassResourceShown(s, resource.key)
                and (resource ~= ammo or ammo.active)
                and (resource ~= thrown or thrown.present)
            then
                Draw(resource)
            end
        end
        if used == 0 then
            Draw(empty)
        end
        for idx = used + 1, #rowList do
            rowList[idx].icon:Hide()
            rowList[idx].text:Hide()
        end
        if vertical then
            contentFrame:SetSize(width, max(barH, posY))
        else
            contentFrame:SetSize(max(10, posX + 4), barH)
        end
        K.MaybeRelayout(instance)
        if hovered then
            ShowTooltip()
        end
    end

    -- Hover only recolors the drawn rows unless the data is stale.
    local function Recolor()
        local r, g, b
        if hovered then
            r, g, b = mod.GetAccent()
        else
            r, g, b = K.BlockColorOf(blockCfg)
        end
        for idx = 1, used or 0 do
            rowList[idx].text:SetTextColor(r, g, b, rowList[idx].alpha)
        end
    end
    btnFrame:SetScript("OnEnter", function()
        hovered = true
        if dirty or not used then
            instance:Refresh()
        else
            Recolor()
            ShowTooltip()
        end
    end)
    btnFrame:SetScript("OnLeave", function()
        hovered = false
        mod.Tip_Hide(btnFrame)
        Recolor()
    end)
    btnFrame:SetScript("OnClick", function(_, mouseButton)
        if mouseButton ~= "RightButton" then
            return
        end
        -- The options never open in combat.
        if InCombatLockdown() then
            CludesUI.PrintError("Cannot open options during combat.")
            return
        end
        if not mod.OpenBlockSettings then
            CludesUI:EnsureLoaded()
        end
        if mod.OpenBlockSettings then
            mod.OpenBlockSettings(barCtx.id, blockCfg.id, "resources")
        end
    end)
    instance.eventFrame = K.MakeEventFrame(instance, function(self, evt, arg, success)
        -- Every shot fires this; rescan only when the equipped ranged stack changed.
        if
            evt == "UNIT_INVENTORY_CHANGED"
            and (arg ~= "player" or GetInventoryItemCount("player", rangedSlot) == rangedCount)
        then
            return
        end
        if evt == "PLAYER_EQUIPMENT_CHANGED" and arg ~= ammoSlot and arg ~= rangedSlot then
            return
        end
        -- Armor wear too: only an equipped durable thrown weapon reads durability.
        if evt == "UPDATE_INVENTORY_DURABILITY" and not (thrown and thrown.id) then
            return
        end
        if evt == "GET_ITEM_INFO_RECEIVED" then
            if not success or (not pending[arg] and not byID[arg] and not itemCounts[arg]) then
                return
            end
            pending[arg] = nil
        end
        dirty = true
        self:Refresh()
    end)
    function instance:Enable()
        dirty = true
        contentFrame:Show()
        K.RegisterInstEvents(self)
    end
    function instance:Disable()
        K.UnregisterInstEvents(self)
        hovered = false
        mod.Tip_Hide(btnFrame)
        contentFrame:Hide()
    end
    function instance:GetAutoLength()
        if barCtx.IsVertical() then
            return max(contentFrame:GetHeight(), 30)
        end
        return max(contentFrame:GetWidth(), 24)
    end
    function instance:Destroy()
        self._dead = true
        self:Disable()
    end
    return instance
end
