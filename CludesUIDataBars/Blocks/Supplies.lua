if CUI_CLIENT_BLOCKED then
    return
end
if not CludesUI.IS_FOREVER then
    return
end
-------------------------------------------------------------------------------
--  Blocks\Supplies.lua - Info Bar block (WoW Forever): class resources.
--
--  The reagents a class carries for its spells (soul shards, candles,
--  powders, poisons...), plus ammo and the thrown weapon for hunters, rogues
--  and warriors. Counted from the carried bags (the reagent bag too), never
--  the bank, and crafting materials do not count. Each shows its icon and
--  count (or name: count); right-click picks which to show.
--
--  What counts:
--    - plain reagents show at 0 when missing; ones a spell needs (flash
--      powder, poisons) only once the spell is known;
--    - a poison counts only at a rank the player is high enough to use;
--    - ammo is the equipped ammo, counted by the ammo slot (and shown only
--      with a bow, gun or crossbow);
--    - a thrown weapon counts its durability (uses left), or its stack.
--
--  Bags change constantly, so a bag update redraws only when a shown count or
--  icon changed.
--
--  Settings (blockCfg.settings): showIcon (default on), showLabel,
--  hiddenItems = { [key] = true }.
-------------------------------------------------------------------------------
local _, mod = ...
local K = mod.BlockKit
local max, floor = math.max, math.floor
local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

-- Per class: { item id, English name, spells = known-spell gate, ranks =
-- { item id, spell id } per rank, tooltipOnly = listed in the tooltip only }.
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

local RANGED = { HUNTER = true, ROGUE = true, WARRIOR = true }

-- The class's resource list (ammo and thrown first for ranged classes) and an
-- item id -> resource map. A spell gate becomes { item, spell } pairs, the
-- same shape as the ranks.
local function Resources(class)
    local list, byItem = {}, {}
    if RANGED[class] then
        list[1] = { key = "ammo", label = "Ammo", fallback = "Interface\\Icons\\INV_Ammo_Arrow_02" }
        list[2] = { key = "thrown", label = "Thrown", fallback = "Interface\\Icons\\INV_ThrowingKnife_02" }
    end
    for _, spec in ipairs(CLASS_ITEMS[class] or {}) do
        local id = spec[1]
        local res = { key = id, id = id, label = spec[2], ranks = spec.ranks, tooltipOnly = spec.tooltipOnly }
        res.learn = spec.ranks
        if spec.spells then
            res.learn = {}
            for i, spell in ipairs(spec.spells) do
                res.learn[i] = { id, spell }
            end
        end
        for _, rank in ipairs(spec.ranks or {}) do
            byItem[rank[1]] = res
        end
        byItem[id] = res
        list[#list + 1] = res
    end
    return list, byItem
end

function mod.ClassResourceShown(prefs, key)
    local hidden = prefs.hiddenItems
    return not (hidden and hidden[key])
end

-- For the settings' show/hide list: the class's resources with item names.
function mod.ClassResourceChoices()
    local _, class = UnitClass("player")
    local choices = Resources(class)
    for _, choice in ipairs(choices) do
        choice.label = choice.id and C_Item.GetItemNameByID(choice.id) or choice.label
    end
    return choices
end

local function IsLauncher(subclass)
    local W = Enum.ItemWeaponSubclass
    return subclass == W.Bows or subclass == W.Guns or subclass == W.Crossbow
end

mod.BlockFactories.supplies = function(blockCfg, slot, contentFrame, barCtx)
    local inst = { cfg = blockCfg, slot = slot, content = contentFrame, ctx = barCtx }
    inst.key = K.InstKey(barCtx, blockCfg)
    inst.events = { "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED", "GET_ITEM_INFO_RECEIVED" }
    local _, class = UnitClass("player")
    local ranged = RANGED[class]
    if ranged then
        -- The equipped ammo and thrown weapon change outside the bags.
        local e = inst.events
        e[#e + 1] = "UNIT_INVENTORY_CHANGED"
        e[#e + 1] = "PLAYER_EQUIPMENT_CHANGED"
        e[#e + 1] = "UPDATE_INVENTORY_DURABILITY"
    end
    if class == "ROGUE" then
        -- Learning a poison or powder spell, or a level that unlocks a rank.
        local e = inst.events
        e[#e + 1] = "SPELLS_CHANGED"
        e[#e + 1] = "PLAYER_LEVEL_UP"
        e[#e + 1] = "SKILL_LINES_CHANGED"
    end

    local resources, byItem = Resources(class)
    local ammo, thrown = nil, nil
    if ranged then
        ammo, thrown = resources[1], resources[2]
    end
    local ammoSlot = ranged and GetInventorySlotInfo("AmmoSlot")
    local rangedSlot = ranged and GetInventorySlotInfo("RangedSlot")
    local rangedCount -- the ranged slot's count at the last scan

    -- The last scan: count per item id, the ids in order, ids whose data is
    -- loading, and thrown weapons counted by uses.
    local counts, order, loading, byUses = {}, {}, {}, {}
    local stale, hovered = true, false
    local none = {} -- the dim "None" row: nothing to show, but still a target

    local button = CreateFrame("Button", nil, contentFrame)
    button:SetAllPoints()
    button:EnableMouse(true)
    button:RegisterForClicks("RightButtonUp")
    local rows = {}

    local function Load(id)
        if not loading[id] then
            loading[id] = true
            C_Item.RequestLoadItemDataByID(id)
        end
    end

    local function Add(res, id, amount)
        res.present = true
        res.count = res.count + amount
        if not res.firstID or id < res.firstID then
            res.firstID = id
        end
        if not counts[id] then
            order[#order + 1] = id
        end
        counts[id] = (counts[id] or 0) + amount
    end

    -- Ammo or thrown, for a ranged class's item; nil if neither (or unknown yet).
    local function RangedKind(id)
        if ammo.id == id then
            return ammo
        end
        local _, _, _, _, _, itemClass, subclass = C_Item.GetItemInfoInstant(id)
        if itemClass == Enum.ItemClass.Projectile then
            return ammo
        end
        if itemClass == Enum.ItemClass.Weapon and subclass == Enum.ItemWeaponSubclass.Thrown then
            return thrown
        end
        if not itemClass then
            ammo.unknown, thrown.unknown = true, true
            Load(id)
        end
    end

    -- Resets each resource and marks which the player can use now.
    local function ResetResources()
        for _, res in ipairs(resources) do
            res.count, res.firstID, res.unknown, res.present = 0, nil, false, false
            -- Plain reagents always show (0 when missing); gated ones once learned.
            res.available = not res.learn
            for _, pair in ipairs(res.learn or {}) do
                if C_SpellBook.IsSpellKnown(pair[2]) then
                    res.available, res.zeroID = true, pair[1]
                end
            end
            if res.id and res ~= ammo and not res.ranks and res.available then
                counts[res.id] = 0
                order[#order + 1] = res.id
            end
        end
    end

    local function ReadRangedSlots()
        ammo.id = GetInventoryItemID("player", ammoSlot)
        local launcher = GetInventoryItemID("player", rangedSlot)
        local _, _, _, _, _, itemClass, subclass = C_Item.GetItemInfoInstant(launcher or 0)
        ammo.active = itemClass == Enum.ItemClass.Weapon and IsLauncher(subclass)
        if launcher and not itemClass then
            Load(launcher)
        end
        rangedCount = GetInventoryItemCount("player", rangedSlot)
    end

    -- Every carried bag; a poison counts only at a rank the player can use.
    local function ScanBags()
        for bag = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4 do
            for bagSlot = 1, C_Container.GetContainerNumSlots(bag) do
                -- The id read allocates nothing; the info table is read only for ours.
                local id = C_Container.GetContainerItemID(bag, bagSlot)
                local res = id and (byItem[id] or (ranged and RangedKind(id)))
                if res and res ~= thrown then
                    local usable = res.available
                    if res.ranks then
                        local _, _, _, _, needLevel = C_Item.GetItemInfo(id)
                        if needLevel then
                            usable = UnitLevel("player") >= needLevel
                        else
                            usable = false
                            res.unknown = true
                            Load(id)
                        end
                    end
                    if usable then
                        local info = C_Container.GetContainerItemInfo(bag, bagSlot)
                        Add(res, id, info and info.stackCount or 0)
                        res.available = true
                    end
                end
            end
        end
    end

    -- Only the equipped thrown weapon counts: its durability, or its stack.
    local function CountThrown()
        local id = GetInventoryItemID("player", rangedSlot)
        if not id or RangedKind(id) ~= thrown then
            return
        end
        local current, most = GetInventoryItemDurability(rangedSlot)
        if current ~= nil and most and most > 0 then
            Add(thrown, id, current)
            byUses[id] = true
            thrown.id, thrown.count, thrown.unknown = id, current, false
        else
            Add(thrown, id, GetInventoryItemCount("player", rangedSlot) or 0)
        end
    end

    -- The ammo slot counts the equipped ammo across every carried stack, so it
    -- is not added to the bags, and other ammo is not combined with it.
    local function CountAmmo()
        local id = ammo.id
        local total = id and GetInventoryItemCount("player", ammoSlot)
        ammo.firstID = nil
        ammo.icon = id and GetInventoryItemTexture("player", ammoSlot) or nil
        ammo.count, ammo.unknown = total or 0, id ~= nil and total == nil
        if id then
            if not counts[id] then
                order[#order + 1] = id
            end
            counts[id] = total
            if not C_Item.GetItemNameByID(id) then
                Load(id)
            end
        end
    end

    local function Scan()
        stale = false
        wipe(counts)
        wipe(order)
        wipe(byUses)
        if thrown then
            thrown.id = nil
        end
        ResetResources()
        if ammo then
            ReadRangedSlots()
        end
        ScanBags()
        if thrown then
            CountThrown()
        end
        if ammo then
            CountAmmo()
        end
        -- Data still loading for an item no longer carried is no longer waited for.
        for id in pairs(loading) do
            if C_Item.GetItemCount(id, false, false, false, false) == 0 then
                loading[id] = nil
            end
        end
        -- A learned poison with none carried shows at 0, under its learned rank.
        for _, res in ipairs(resources) do
            if res.ranks and res.available and not res.present then
                local id = res.zeroID or res.id
                counts[id] = 0
                order[#order + 1] = id
            end
        end
        table.sort(order)
    end

    local function Name(res)
        return (res.id and C_Item.GetItemNameByID(res.id)) or CludesUI.L(res.label)
    end

    local function ShowTooltip()
        local s = blockCfg.settings or {}
        mod.Tip_Begin(button)
        mod.Tip_AddLine(CludesUI.L("Class Resources"), 1, 1, 1)
        local listed = 0
        for _, id in ipairs(order) do
            local res = byItem[id] or (ranged and RangedKind(id))
            if res and (res ~= ammo or ammo.active) and mod.ClassResourceShown(s, res.key) then
                local name = C_Item.GetItemNameByID(id) or Name(res)
                if byUses[id] then
                    name = name .. " - " .. CludesUI.L("Remaining uses")
                end
                local value = counts[id] == nil and "?" or tostring(counts[id])
                if res.tooltipOnly then
                    value = CludesUI.L(counts[id] > 0 and "Available" or "Missing")
                end
                mod.Tip_AddDouble(name, value, 0.8, 0.8, 0.8, 1, 1, 1)
                listed = listed + 1
            end
        end
        if listed == 0 then
            mod.Tip_AddLine(CludesUI.L("No class resources in inventory"), 0.6, 0.6, 0.6)
        end
        if next(loading) then
            mod.Tip_AddLine(CludesUI.L("Loading item data..."), 0.6, 0.6, 0.6)
        end
        mod.Tip_AddLine(" ")
        mod.Tip_AddLine(CludesUI.L("Right-click to edit visible items."), 0.6, 0.6, 0.6)
        mod.Tip_Show()
    end

    -- The resources drawn on the bar, in order.
    local function Shown(s)
        local out = {}
        for _, res in ipairs(resources) do
            if
                not res.tooltipOnly
                and (res.available or res.unknown)
                and mod.ClassResourceShown(s, res.key)
                and (res ~= ammo or ammo.active)
                and (res ~= thrown or thrown.present)
            then
                out[#out + 1] = res
            end
        end
        if #out == 0 then
            out[1] = none
        end
        return out
    end

    local function Icon(res)
        local id = res.id or res.firstID
        return res.icon or (id and C_Item.GetItemIconByID(id)) or res.fallback or UNKNOWN_ICON
    end

    -- Everything the drawn rows show, as one string: equal = nothing to redraw.
    local function Fingerprint(list)
        local parts = {}
        for i, res in ipairs(list) do
            parts[i] = res == none and "none"
                or table.concat(
                    { tostring(res.key), res.count, tostring(res.unknown), Icon(res), Name(res) },
                    ":"
                )
        end
        return table.concat(parts, "|")
    end
    local drawn, used -- the fingerprint on screen, and the rows it took

    -- Layout of one Refresh, shared by DrawRow.
    local pass = {}

    local function DrawRow(res)
        used = used + 1
        local row = rows[used]
        if not row then
            row = {
                icon = button:CreateTexture(nil, "OVERLAY"),
                text = button:CreateFontString(nil, "OVERLAY"),
            }
            rows[used] = row
            K.AttachTextOffset(inst, row.text)
        end
        local blank = res == none
        local value
        if blank then
            value = CludesUI.L("None")
        else
            value = res.unknown and "?"
                or (BreakUpLargeNumbers and BreakUpLargeNumbers(res.count) or tostring(res.count))
            -- With no icons the names tell the counts apart.
            if pass.s.showLabel or pass.iconSize == 0 then
                value = Name(res) .. ": " .. value
            end
        end
        local text, iconTex = row.text, row.icon
        mod.SetFont(text, pass.fontSize, barCtx.cfg)
        text:SetText(value)
        row.alpha = blank and 0.5 or 1
        text:SetTextColor(pass.r, pass.g, pass.b, row.alpha)
        text:ClearAllPoints()
        text:Show()
        iconTex:SetTexture(Icon(res))
        K.CropStockIcon(iconTex)
        iconTex:SetVertexColor(pass.ir, pass.ig, pass.ib, 1)
        iconTex:ClearAllPoints()
        local withIcon = pass.iconSize > 0 and not blank
        if withIcon then
            iconTex:SetSize(pass.iconSize, pass.iconSize)
            iconTex:Show()
        else
            iconTex:Hide()
        end
        if pass.vertical then
            -- Stacked: icon, then its count, down the slot.
            mod.SetWrappedText(text, max(24, pass.width - 8), "CENTER")
            if withIcon then
                iconTex:SetPoint("TOP", button, "TOP", 0, -pass.y)
                pass.y = pass.y + pass.iconSize + 2
            end
            text:SetPoint("TOP", button, "TOP", 0, -pass.y)
            pass.y = pass.y + mod.SnapToPixelGrid(text:GetStringHeight()) + 4
        else
            -- In a row, 12px between resources.
            mod.ResetInlineText(text, "LEFT")
            if used > 1 then
                pass.x = pass.x + 12
            end
            if withIcon then
                iconTex:SetPoint("LEFT", button, "LEFT", pass.x, 0)
                pass.x = pass.x + pass.iconSize + K.ICON_GAP
            end
            text:SetPoint("LEFT", button, "LEFT", pass.x, 0)
            pass.x = pass.x + mod.SnapToPixelGrid(text:GetStringWidth())
        end
    end

    local function Draw(list)
        local s = blockCfg.settings or {}
        pass.s = s
        pass.fontSize = max(9, floor(K.CONTENT_BASE * 0.4333 + 0.5))
        pass.iconSize = s.showIcon ~= false and pass.fontSize + 2 or 0
        pass.vertical = barCtx.IsVertical()
        pass.width = pass.vertical and K.VSlotW(inst) or 0
        pass.x, pass.y = 0, 4
        used = 0
        if hovered then
            pass.r, pass.g, pass.b = mod.GetAccent()
        else
            pass.r, pass.g, pass.b = K.BlockColorOf(blockCfg)
        end
        pass.ir, pass.ig, pass.ib = K.IconColorOf(blockCfg)
        for _, res in ipairs(list) do
            DrawRow(res)
        end
        for i = used + 1, #rows do
            rows[i].icon:Hide()
            rows[i].text:Hide()
        end
        local barH = barCtx.GetThickness()
        if pass.vertical then
            contentFrame:SetSize(pass.width, max(barH, pass.y))
        else
            contentFrame:SetSize(max(10, pass.x + 4), barH)
        end
        drawn = Fingerprint(list)
        K.MaybeRelayout(inst)
    end

    -- A full pass (settings, the bar's layout): always draws.
    function inst:Refresh()
        if stale then
            Scan()
        end
        Draw(Shown(blockCfg.settings or {}))
        if hovered then
            ShowTooltip()
        end
    end

    -- Hover recolours the drawn rows only (unless the counts are stale).
    local function Recolour()
        local region, g, b
        if hovered then
            region, g, b = mod.GetAccent()
        else
            region, g, b = K.BlockColorOf(blockCfg)
        end
        for i = 1, used or 0 do
            rows[i].text:SetTextColor(region, g, b, rows[i].alpha)
        end
    end
    button:SetScript("OnEnter", function()
        hovered = true
        if stale or not used then
            inst:Refresh()
        else
            Recolour()
            ShowTooltip()
        end
    end)
    button:SetScript("OnLeave", function()
        hovered = false
        mod.Tip_Hide(button)
        Recolour()
    end)
    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton ~= "RightButton" then
            return
        end
        if InCombatLockdown() then
            CludesUI.PrintError("Cannot open options during combat.")
            return
        end
        if not mod.OpenBlockSettings then
            CludesUI:EnsureLoaded() -- the settings load on demand
        end
        if mod.OpenBlockSettings then
            mod.OpenBlockSettings(barCtx.id, blockCfg.id, "resources")
        end
    end)

    inst.eventFrame = K.MakeEventFrame(inst, function(_, event, arg, success)
        -- Every shot sends this; only a change of the ranged slot's count matters.
        if
            event == "UNIT_INVENTORY_CHANGED"
            and (arg ~= "player" or GetInventoryItemCount("player", rangedSlot) == rangedCount)
        then
            return
        end
        if event == "PLAYER_EQUIPMENT_CHANGED" and arg ~= ammoSlot and arg ~= rangedSlot then
            return
        end
        -- Armour wears too; only an equipped thrown weapon counts durability.
        if event == "UPDATE_INVENTORY_DURABILITY" and not (thrown and thrown.id) then
            return
        end
        if event == "GET_ITEM_INFO_RECEIVED" then
            if not success or (not loading[arg] and not byItem[arg] and not counts[arg]) then
                return
            end
            loading[arg] = nil
        end
        Scan()
        local list = Shown(blockCfg.settings or {})
        if Fingerprint(list) ~= drawn then
            Draw(list)
        end
        -- The tooltip also lists items the bar does not draw.
        if hovered then
            ShowTooltip()
        end
    end)

    function inst:Enable()
        stale = true
        contentFrame:Show()
        K.RegisterInstEvents(self)
    end
    function inst:Disable()
        K.UnregisterInstEvents(self)
        hovered = false
        mod.Tip_Hide(button)
        contentFrame:Hide()
    end
    function inst:GetAutoLength()
        if barCtx.IsVertical() then
            return max(contentFrame:GetHeight(), 30)
        end
        return max(contentFrame:GetWidth(), 24)
    end
    function inst:Destroy()
        self._dead = true
        self:Disable()
    end
    return inst
end
