if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_Bags_Data.lua
--
--  Layout constants, the selection and item-panel state, the visual sort,
--  the expansion and armory buckets, the slot data pool with saved order
--  and swap detection, the slot pools and the Pawn arrows.
--  Reads the earlier Bags files through ns and ns._bagsInternals.
-------------------------------------------------------------------------------
local mod = select(2, ...)
local Inner = mod._bagsInternals
-- CludesUIBags.lua or an earlier CUI_Bags_*.lua file failed to load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local GetItemInfo = C_Item.GetItemInfo
local GetItemInfoInstant = C_Item.GetItemInfoInstant
local CUI = CludesUI
local GetUpgradeTrack = CUI.GetUpgradeTrack

local BP, SetSelectedCategoryIndex = Inner.BP, Inner.SetSelectedCategoryIndex
local SetSelectedGroupName, SetAnyItemPanelOpen = Inner.SetSelectedGroupName, Inner.SetAnyItemPanelOpen
local SetPaintedPanelOpen = Inner.SetPaintedPanelOpen

-------------------------------------------------------------------------------
--  Sidebar constants
-------------------------------------------------------------------------------
local SIDEBAR_W_EXPANDED = 160
local SIDEBAR_W_COLLAPSED = 32
local SIDEBAR_BTN_H = 26
local SIDEBAR_ICON_SIZE = 18
local SIDEBAR_PAD = 2
local SIDEBAR_INDENT = 16
local HEADER_H = 35
local FOOTER_H = 28

-- Runtime state (never persisted; always "All" on load)
local selectedCategoryIndex = 0 -- 0 = All Items, -1 = OneBag, -2 = MultiBag, >0 = category index
local selectedGroupName = nil -- set when a group header is clicked (overrides selectedCategoryIndex)
Inner.categoryIndexSetters[#Inner.categoryIndexSetters + 1] = function(val)
    selectedCategoryIndex = val
end
Inner.groupNameSetters[#Inner.groupNameSetters + 1] = function(val)
    selectedGroupName = val
end

-- Invalidate categories after the equipment-set list changes (event or the
-- split-mode toggle). Re-resolves the selection by stable key: the rebuild
-- shifts indices, and "EquipSet:"..setID survives renames; a vanished
-- category/group falls back to All Items.
function CUI_Bags.InvalidateSetCategories()
    local mgr = _G.CUI_CategoryManager
    if not mgr then
        return
    end
    local selKey
    if selectedCategoryIndex > 0 then
        local category = mgr:GetCategories()[selectedCategoryIndex]
        selKey = category and category._defaultName
    end
    mgr:OnEquipmentSetsChanged()
    if selKey then
        local found = 0
        for i, category in ipairs(mgr:GetCategories()) do
            if category._defaultName == selKey then
                found = i
                break
            end
        end
        SetSelectedCategoryIndex(found)
    end
    if selectedGroupName then
        local alive = false
        for _, category in ipairs(mgr:GetCategories()) do
            if category.groupName == selectedGroupName then
                alive = true
                break
            end
        end
        if not alive then
            SetSelectedGroupName(nil)
            SetSelectedCategoryIndex(0)
        end
    end
end

-- Visual sort: quality desc > name > itemID > bag > slot; the bag+slot tiebreaker makes output deterministic (Lua 5.1 sort is unstable).
local _trackRank = CUI._TRACK_RANK
-- Gear category lookup: built lazily, maps catIdx -> true for gear categories
local _gearCatSet
Inner.gearCatSetSetters[#Inner.gearCatSetSetters + 1] = function(val)
    _gearCatSet = val
end
local function IsGearCategory(catIdx)
    if not _gearCatSet then
        _gearCatSet = {}
        local cats = CUI_CategoryManager and CUI_CategoryManager:GetCategories()
        if cats then
            for i, category in ipairs(cats) do
                if
                    category.isSetGear
                    or (
                        category.types
                        and (
                            category._defaultName == "Armor"
                            or category._defaultName == "Weapons / Trinkets"
                        )
                    )
                then
                    _gearCatSet[i] = true
                end
            end
        end
    end
    return _gearCatSet[catIdx]
end

-- Item panels (mail/trade/AH/vendor/bank/guildbank) take one bag slot at a time; a merged button
-- only hands over the slot behind it (3 merged mails would mail 1), so duplicates stay unmerged while any panel is open. bagMergeDuplicates disables merging outright.
local _openItemPanels = {}
local _anyItemPanelOpen = false
Inner.anyItemPanelOpenSetters[#Inner.anyItemPanelOpenSetters + 1] = function(val)
    _anyItemPanelOpen = val
end
-- Returns true when the aggregate state flipped and the bags' view merges, so
-- the caller can refresh. A view that does not merge paints the same either
-- way: its painted state just follows, so neither this nor OnShow repaints.
local function SetItemPanelOpen(key, open)
    _openItemPanels[key] = open or nil
    local any = next(_openItemPanels) ~= nil
    if any == _anyItemPanelOpen then
        return false
    end
    SetAnyItemPanelOpen(any)
    local merges = BP().bagMergeDuplicates ~= false
    if not merges then
        SetPaintedPanelOpen(any)
    end
    return merges
end

-- Pre-cache sort fields onto item data tables to avoid API calls in comparator.
-- The per-table _sortCached flag only covers repeats within one pass: every
-- physical-sort retry builds fresh item tables, so it re-ran GetItemInfo and
-- GetItemUpgradeInfo for every item on every pass. All five fields are pure
-- functions of the item link, so memo them on the link instead. Incomplete
-- item data (nil name) is never stored and still resolves on a later pass.
-- _sortGear stays per item: it follows the category, not the link.
local PreCacheSortFields
do
    local cache = {}
    local cacheCount = 0
    PreCacheSortFields = function(items)
        for _, skinData in ipairs(items) do
            if skinData.itemLink and not skinData._sortCached then
                local c = cache[skinData.itemLink]
                if not c then
                    local name, _, quality, ilvl, _, itemType = GetItemInfo(skinData.itemLink)
                    local rank = 0
                    if GetUpgradeTrack and _trackRank then
                        local _, color = GetUpgradeTrack(skinData.itemLink)
                        rank = color and _trackRank[color] or 0
                        local craftedColor = CUI.GetCraftedTrackColor(skinData.itemLink)
                        if craftedColor then
                            rank = _trackRank[craftedColor]
                            ilvl = C_Item.GetDetailedItemLevelInfo(skinData.itemLink) or ilvl
                        end
                    end
                    c = {
                        name = name or "",
                        quality = quality or 0,
                        ilvl = ilvl or 0,
                        itemType = itemType or "",
                        rank = rank,
                        complete = name ~= nil,
                    }
                    if c.complete then
                        -- Links are per-item-instance, so the table would grow
                        -- with every distinct item seen in a session.
                        if cacheCount >= 4000 then
                            wipe(cache)
                            cacheCount = 0
                        end
                        cache[skinData.itemLink] = c
                        cacheCount = cacheCount + 1
                    end
                end
                skinData._sortName = c.name
                skinData._sortQuality = c.quality
                skinData._sortIlvl = c.ilvl
                skinData._sortType = c.itemType
                skinData._sortTrackRank = c.rank
                skinData._sortGear = skinData.categoryIndex and IsGearCategory(skinData.categoryIndex) or false
                if c.complete then
                    skinData._sortCached = true
                end
            end
        end
    end
end

local function VisualSortCompare(a, b)
    -- Gear sort: track (descending) > ilvl (descending) -- only for gear categories
    if a._sortGear and b._sortGear then
        if a._sortTrackRank ~= b._sortTrackRank then
            return a._sortTrackRank > b._sortTrackRank
        end
        if a._sortTrackRank > 0 and b._sortTrackRank > 0 then
            if a._sortIlvl ~= b._sortIlvl then
                return a._sortIlvl > b._sortIlvl
            end
        end
    end
    -- Category grouping; skipped for gear so track/ilvl win in merged gear groups
    local aCat = a.categoryIndex or 9999
    local bCat = b.categoryIndex or 9999
    if aCat ~= bCat and not (a._sortGear and b._sortGear) then
        return aCat < bCat
    end
    -- Sub-type grouping within merged categories (e.g. Professions vs Recipes)
    if a._sortType ~= b._sortType then
        return a._sortType < b._sortType
    end
    -- Fallback: rarity > name > itemID > bag:slot
    if a._sortQuality ~= b._sortQuality then
        return a._sortQuality > b._sortQuality
    end
    if a._sortName ~= b._sortName then
        return a._sortName < b._sortName
    end
    local ai = (a.info and a.info.itemID) or 0
    local bi = (b.info and b.info.itemID) or 0
    if ai ~= bi then
        return ai < bi
    end
    if a.bag ~= b.bag then
        return a.bag < b.bag
    end
    return a.slot < b.slot
end

-------------------------------------------------------------------------------
--  Expansion nesting (All Items view): C_Item.GetItemInfo expansionID + labels
-------------------------------------------------------------------------------
local EXPANSION_ID_OVERRIDES = {
    [180653] = 11,
}

local function GetItemExpansionIDFromLink(itemLink)
    if not itemLink then
        return nil
    end
    local itemId = tonumber(itemLink:match("item:(%d+)")) or tonumber(itemLink:match("keystone:(%d+)"))
    if itemId and EXPANSION_ID_OVERRIDES[itemId] then
        return EXPANSION_ID_OVERRIDES[itemId]
    end
    if C_Item and C_Item.GetItemInfo then
        local _, _, _, _, _, _, _, _, _, _, _, _, _, _, expID = C_Item.GetItemInfo(itemLink)
        return expID
    end
    return select(15, GetItemInfo(itemLink))
end

-- The game's own name for an expansion ID, in the client's language; the
-- fallbacks cover an ID this client has no name for.
local function ExpansionName(ident)
    local name = _G["EXPANSION_NAME" .. ident]
    if name and name ~= "" then
        return name
    end
    if ident == 11 then
        return "Midnight"
    end
    return CludesUI.Lf("Expansion %1$d", ident)
end

-- sortKey: higher = newer expansion, shown first. Unknown / uncached last.
local function GetExpansionBucketKeyAndLabel(itemLink)
    local expID = GetItemExpansionIDFromLink(itemLink)
    if expID == nil then
        return -999, (UNKNOWN or CludesUI.L("Unknown"))
    end
    local ident = tonumber(expID)
    if ident == nil then
        return -999, (UNKNOWN or CludesUI.L("Unknown"))
    end
    -- Classic-era sentinel from some clients / items
    if ident == 254 or ident == 255 then
        local name = _G["EXPANSION_NAME0"] or CludesUI.L("Classic")
        return 0, name
    end
    return ident, ExpansionName(ident)
end

local function BuildExpansionBuckets(itemList)
    local byKey = {}
    for _, payload in ipairs(itemList) do
        local sk, labelText
        if payload.itemLink then
            local _, _, _, ilvl = GetItemInfo(payload.itemLink)
            if ilvl and ilvl >= 180 then
                sk, labelText = 11, ExpansionName(11)
            end
        end
        if not sk then
            sk, labelText = GetExpansionBucketKeyAndLabel(payload.itemLink)
        end
        local b = byKey[sk]
        if not b then
            b = { sortKey = sk, label = labelText, items = {} }
            byKey[sk] = b
        end
        b.items[#b.items + 1] = payload
    end
    local keyList = {}
    for sk in pairs(byKey) do
        keyList[#keyList + 1] = sk
    end
    table.sort(keyList, function(lhs, rhs)
        return lhs > rhs
    end)
    local result = {}
    for _, sk in ipairs(keyList) do
        result[#result + 1] = byKey[sk]
    end
    return result
end

-------------------------------------------------------------------------------
--  Armory slot grouping: equip-slot sub-headers inside gear-only sidebar groups
-------------------------------------------------------------------------------
local IC_WEAPON = Enum.ItemClass.Weapon
local IC_ARMOR = Enum.ItemClass.Armor

local function IsArmoryGearCategory(category)
    if not category then
        return false
    end
    if category.isEquipSet then
        return true
    end
    if category.isSetGear then
        return true
    end
    return category._defaultName == "Weapons / Trinkets" or category._defaultName == "Armor"
end

local function IsGearOnlyGroup(groupName)
    if not groupName or not CUI_CategoryManager then
        return false
    end
    local members = CUI_CategoryManager:GetGroupMembers(groupName)
    if not members or #members == 0 then
        return false
    end
    local cats = CUI_CategoryManager:GetCategories()
    if not cats then
        return false
    end
    for _, mi in ipairs(members) do
        if not IsArmoryGearCategory(cats[mi]) then
            return false
        end
    end
    return true
end

-- Constants hoisted out of the per-item path (built once at load).
local ARMORY_IDS = {
    wand = (Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Wand) or 19,
    bow = (Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Bow) or 2,
    gun = (Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Gun) or 3,
    crossbow = (Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Crossbow) or 18,
    cosmetic = Enum.ItemArmorSubclass and Enum.ItemArmorSubclass.Cosmetic,
}
-- equipSlot -> { sortKey, Blizzard global-string name for the label }
local ARMORY_ARMOR_SLOTS = {
    INVTYPE_HEAD = { 10, "INVTYPE_HEAD" },
    INVTYPE_NECK = { 20, "INVTYPE_NECK" },
    INVTYPE_SHOULDER = { 30, "INVTYPE_SHOULDER" },
    INVTYPE_CLOAK = { 40, "INVTYPE_CLOAK" },
    INVTYPE_CHEST = { 50, "INVTYPE_CHEST" },
    INVTYPE_ROBE = { 50, "INVTYPE_CHEST" },
    INVTYPE_BODY = { 60, "INVTYPE_BODY" },
    INVTYPE_TABARD = { 70, "INVTYPE_TABARD" },
    INVTYPE_WRIST = { 80, "INVTYPE_WRIST" },
    INVTYPE_HAND = { 90, "INVTYPE_HAND" },
    INVTYPE_WAIST = { 100, "INVTYPE_WAIST" },
    INVTYPE_LEGS = { 110, "INVTYPE_LEGS" },
    INVTYPE_FEET = { 120, "INVTYPE_FEET" },
    INVTYPE_FINGER = { 140, "INVTYPE_FINGER" },
    INVTYPE_TRINKET = { 150, "INVTYPE_TRINKET" },
}

-- Sort key + label for one item's equip slot. Item facts are fetched lazily
-- (GetItemInfoInstant, local client DB) and cached on the slot table -- the
-- refresh pre-cache deliberately does not fill them, so this runs only for
-- gear items and only while Group Gear by Slot is on (grid, Compact and the
-- List display's gear categories).
local function GetArmorySlotBucket(payload)
    local equipSlot = payload._equipSlot
    local classID = payload._classID
    local subclassID = payload._subclassID
    if payload.itemLink and classID == nil then
        local _
        _, _, _, equipSlot, _, classID, subclassID = GetItemInfoInstant(payload.itemLink)
        payload._equipSlot, payload._classID, payload._subclassID = equipSlot, classID, subclassID
    end

    if classID == IC_ARMOR and ARMORY_IDS.cosmetic and subclassID == ARMORY_IDS.cosmetic then
        return 130, CludesUI.L("Cosmetic")
    end

    equipSlot = equipSlot or ""

    if
        equipSlot == "INVTYPE_WEAPONOFFHAND"
        or equipSlot == "INVTYPE_HOLDABLE"
        or equipSlot == "INVTYPE_SHIELD"
    then
        return 180, CludesUI.L("OH")
    end

    if classID == IC_WEAPON then
        if subclassID == ARMORY_IDS.wand then
            return 170, CludesUI.L("1H")
        end
        if
            subclassID == ARMORY_IDS.bow
            or subclassID == ARMORY_IDS.gun
            or subclassID == ARMORY_IDS.crossbow
        then
            return 190, _G["INVTYPE_RANGED"] or CludesUI.L("Ranged")
        end
        if equipSlot == "INVTYPE_2HWEAPON" then
            return 160, CludesUI.L("2H")
        end
        if equipSlot == "INVTYPE_RANGED" or equipSlot == "INVTYPE_RANGEDRIGHT" then
            return 190, _G["INVTYPE_RANGED"] or CludesUI.L("Ranged")
        end
        if equipSlot == "INVTYPE_WEAPON" or equipSlot == "INVTYPE_WEAPONMAINHAND" then
            return 170, CludesUI.L("1H")
        end
    end

    local record = ARMORY_ARMOR_SLOTS[equipSlot]
    if record then
        return record[1], _G[record[2]] or equipSlot
    end

    return 999, CludesUI.L("Other")
end

local function BuildSlotBuckets(itemList)
    local byKey = {}
    for _, payload in ipairs(itemList) do
        local sk, labelText = GetArmorySlotBucket(payload)
        local b = byKey[sk]
        if not b then
            b = { sortKey = sk, label = labelText, items = {} }
            byKey[sk] = b
        end
        b.items[#b.items + 1] = payload
    end
    local keyList = {}
    for sk in pairs(byKey) do
        keyList[#keyList + 1] = sk
    end
    table.sort(keyList)
    local result = {}
    for _, sk in ipairs(keyList) do
        local b = byKey[sk]
        if #b.items > 0 then
            PreCacheSortFields(b.items)
            table.sort(b.items, VisualSortCompare)
            result[#result + 1] = b
        end
    end
    return result
end

local function ArmorySlotGroupingEnabled()
    if not BP().bagArmoryGroupBySlot then
        return false
    end
    local dc = BP().bagDisabledCategories
    return not (dc and dc["Armor"])
end

-------------------------------------------------------------------------------
--  Slot data table pool (avoids ~200 table allocations per refresh)
-------------------------------------------------------------------------------
local _slotPool = {}
local _slotPoolN = 0
local _activeSlotTables = {}
local _activeSlotN = 0

local function AcquireSlotTable()
    local t
    if _slotPoolN > 0 then
        t = _slotPool[_slotPoolN]
        _slotPool[_slotPoolN] = nil
        _slotPoolN = _slotPoolN - 1
        wipe(t)
    else
        t = {}
    end
    _activeSlotN = _activeSlotN + 1
    _activeSlotTables[_activeSlotN] = t
    return t
end

local function ReleaseAllSlotTables()
    for i = 1, _activeSlotN do
        _slotPoolN = _slotPoolN + 1
        _slotPool[_slotPoolN] = _activeSlotTables[i]
        _activeSlotTables[i] = nil
    end
    _activeSlotN = 0
end

-- Merge duplicate non-gear items by itemLink within an already-ordered list.
-- itemLink encodes stats/bonuses, so items with different stats stay separate.
-- Must run AFTER ApplySavedOrder so the first occurrence in visual order wins.
-- Returns a new list; the caller's tables are NEVER modified. A merged winner is
-- replaced in the returned list by a pooled, display-only shallow copy carrying
-- the aggregate in _mergedCount. Invariant: only those copies ever carry
-- _mergedCount, which is also the "already a copy" test below. If anyone ever
-- writes _mergedCount back onto a canonical slot table, both break.
-- The result must not outlive the render pass that produced it: the copies come
-- from the slot pool and are recycled by ReleaseAllSlotTables on the next refresh.
local function MergeDuplicates(items)
    -- Record what this paint was built with, so the bags OnShow can tell that
    -- the state changed while they were hidden and repaint (see OnShow).
    SetPaintedPanelOpen(_anyItemPanelOpen)
    if _anyItemPanelOpen or BP().bagMergeDuplicates == false then
        return items
    end
    -- Session-only unmerge marks (CUI_Bags._unmergedLinks: set by the split
    -- dialog, wiped when the bags close, never persisted): a marked item keeps
    -- its real stacks apart so a split's pieces are visible in these views.
    local unmerged = CUI_Bags._unmergedLinks
    -- Painted-with-marks state, the same job _paintedPanelOpen does: the bags
    -- OnShow repaints when the marks were wiped by the close that hid them.
    CUI_Bags._paintedUnmerged = (unmerged ~= nil and next(unmerged) ~= nil) or nil
    local seen = {}
    local result = {}
    for _, payload in ipairs(items) do
        local key = payload.itemLink
        if key and not IsGearCategory(payload.categoryIndex or 0) and not (unmerged and unmerged[key]) then
            local position = seen[key]
            if position then
                local previous = result[position]
                if not previous._mergedCount then
                    -- First duplicate for this key: swap the winner out for a copy.
                    -- The aggregate cannot live on the winner itself, because the
                    -- OneBag/MultiBag bag grid paints those same slot tables with no
                    -- merge pass of its own and would show one slot's count inflated
                    -- by its twins. data.info stays shared by reference on purpose.
                    local proxy = AcquireSlotTable()
                    for k, val in pairs(previous) do
                        proxy[k] = val
                    end
                    proxy._mergedCount = previous.info.stackCount or 1
                    result[position] = proxy
                    previous = proxy
                end
                previous._mergedCount = previous._mergedCount + (payload.info.stackCount or 1)
            else
                result[#result + 1] = payload
                seen[key] = #result
            end
        else
            result[#result + 1] = payload
        end
    end
    return result
end

-- Saved visual order per category/group in BP().bagVisualOrder, keyed by category index
-- (number) or group name (string): an ordered list of "bag:slot" strings; missing items append to the end.
local function GetVisualOrder()
    if not BP().bagVisualOrder then
        BP().bagVisualOrder = {}
    end
    return BP().bagVisualOrder
end

-- A virtual category's order is kept for the session under its own key: its
-- index is no stable key, and nothing of it is saved.
local _virtualOrder = {}
local function OrderFor(key)
    if CUI_CategoryManager:IsVirtual(key) then
        return _virtualOrder, CUI_CategoryManager:GetCategories()[key]._defaultName
    end
    return GetVisualOrder(), key
end

local function SaveCategoryOrder(key, items)
    local sequence, k = OrderFor(key)
    local entries = {}
    for i, payload in ipairs(items) do
        entries[i] = payload.info and payload.info.itemID or 0
    end
    sequence[k] = entries
end

local function ApplySavedOrder(key, items)
    local sequence, k = OrderFor(key)
    local saved = sequence[k]
    if not saved or #saved == 0 then
        return
    end

    -- Build position queues per itemID: each ID maps to its saved positions
    local posQueues = {}
    for i, ident in ipairs(saved) do
        if not posQueues[ident] then
            posQueues[ident] = {}
        end
        local q = posQueues[ident]
        q[#q + 1] = i
    end

    -- Assign each item a saved position (consume from queue) or append to end
    local consumed = {}
    local nextUnsaved = #saved + 1
    for _, payload in ipairs(items) do
        local ident = payload.info and payload.info.itemID or 0
        local q = posQueues[ident]
        local ci = consumed[ident] or 1
        if q and ci <= #q then
            payload._savedPos = q[ci]
            consumed[ident] = ci + 1
        else
            payload._savedPos = nextUnsaved
            nextUnsaved = nextUnsaved + 1
        end
    end

    table.sort(items, function(lhs, rhs)
        if lhs._savedPos ~= rhs._savedPos then
            return lhs._savedPos < rhs._savedPos
        end
        if lhs.bag ~= rhs.bag then
            return lhs.bag < rhs.bag
        end
        return lhs.slot < rhs.slot
    end)
end

-- Clear saved visual order for a group (called when ungrouping)
local function ClearGroupOrder(groupName)
    if not groupName then
        return
    end
    local sequence = GetVisualOrder()
    sequence[groupName] = nil
end

-- Bag snapshot: tracks bag:slot -> itemID between refreshes for swap detection
local _bagSnapshot = {}

local function TakeBagSnapshot(tempItems)
    wipe(_bagSnapshot)
    for _, skinData in ipairs(tempItems) do
        if skinData.info and skinData.info.itemID then
            _bagSnapshot[skinData.bag * 1000 + skinData.slot] = skinData.info.itemID
        end
    end
end

-- Detect manual item swaps; with applySwap, also updates the saved visual order. Returns true if a swap was detected.
local function DetectAndApplySwaps(tempItems, applySwap)
    if not next(_bagSnapshot) then
        return false
    end

    local current = {}
    for _, skinData in ipairs(tempItems) do
        if skinData.info and skinData.info.itemID then
            current[skinData.bag * 1000 + skinData.slot] = skinData.info.itemID
        end
    end

    local swapChanges = {}
    for key, oldID in pairs(_bagSnapshot) do
        local curID = current[key]
        if curID and curID ~= oldID then
            swapChanges[#swapChanges + 1] = { curID = curID, oldID = oldID }
        end
    end

    -- Swap pattern: exactly 2 item-to-item changes that cross-match
    if #swapChanges == 2 then
        local c1, c2 = swapChanges[1], swapChanges[2]
        if c1.curID == c2.oldID and c2.curID == c1.oldID and c1.curID ~= c2.curID then
            if applySwap then
                local id1, id2 = c1.curID, c2.curID
                -- The saved orders, then the virtual categories' session orders
                local vo = GetVisualOrder()
                for pass = 1, 2 do
                    for _, saved in pairs(vo) do
                        local idx1, idx2
                        for i, spellRef in ipairs(saved) do
                            if spellRef == id1 and not idx1 then
                                idx1 = i
                            elseif spellRef == id2 and not idx2 then
                                idx2 = i
                            end
                        end
                        if idx1 and idx2 then
                            saved[idx1], saved[idx2] = saved[idx2], saved[idx1]
                        end
                    end
                    vo = _virtualOrder
                end
            end
            return true
        end
    end
    return false
end

-- Category indices + group names needing re-sort: filled by ResortAfterGroupChange, consumed by RefreshInventory.
local _pendingResortCats = {}
local _pendingResortGroups = {}

-- Invalidate saved order; RefreshInventory does the re-sort on already-scanned items.
local function ResortAfterGroupChange(catIndices, groupName)
    local sequence = GetVisualOrder()
    for _, ci in ipairs(catIndices) do
        sequence[ci] = nil
        _pendingResortCats[ci] = true
    end
    if groupName then
        sequence[groupName] = nil
        _pendingResortGroups[groupName] = true
    end
end

-------------------------------------------------------------------------------
--  Slot pools
-------------------------------------------------------------------------------
local itemSlots = {}
local reagentSlots = {}
local bagSlots = {}

-------------------------------------------------------------------------------
--  Pawn bag upgrade advisor integration
-------------------------------------------------------------------------------
local pawnRegistered = false
local pawnPending = setmetatable({}, { __mode = "k" })
local pawnPositioned = setmetatable({}, { __mode = "k" })
local pawnRetryScheduled = false
local UpdatePawnArrow

local function RetryPawnArrows()
    pawnRetryScheduled = false
    local pending = pawnPending
    pawnPending = setmetatable({}, { __mode = "k" })

    for button, expectedLink in pairs(pending) do
        local hostFrame = button:GetParent()
        local currentLink = hostFrame and C_Container.GetContainerItemLink(hostFrame:GetID(), button:GetID())
        if button:IsShown() and currentLink == expectedLink then
            UpdatePawnArrow(button, currentLink)
        end
    end
end

UpdatePawnArrow = function(button, itemLink)
    if not pawnRegistered or not button.UpgradeIcon then
        return
    end
    if not pawnPositioned[button] then
        button.UpgradeIcon:ClearAllPoints()
        button.UpgradeIcon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
        button.UpgradeIcon:SetSize(16, 16)
        pawnPositioned[button] = true
    end
    button.UpgradeIcon:Hide()

    if not itemLink or not PawnCommon or not PawnCommon.ShowBagUpgradeAdvisor then
        pawnPending[button] = nil
        return
    end

    local isUpgrade = PawnShouldItemLinkHaveUpgradeArrow(itemLink, true)
    if isUpgrade == nil then
        pawnPending[button] = itemLink
        if not pawnRetryScheduled then
            pawnRetryScheduled = true
            C_Timer.After(0, RetryPawnArrows)
        end
    else
        pawnPending[button] = nil
        button.UpgradeIcon:SetShown(isUpgrade)
    end
end

local function RefreshPawnArrows()
    if CUI_Bags:IsVisible() then
        CUI_Bags:RefreshInventory()
    end
    if CUI_BagsReagent:IsVisible() then
        CUI_BagsReagent:RefreshInventory()
    end
end

local function RegisterPawnIntegration()
    if pawnRegistered or BP().enhancedBags == false then
        return
    end
    if
        type(PawnRegisterThirdPartyBag) ~= "function"
        or type(PawnShouldItemLinkHaveUpgradeArrow) ~= "function"
    then
        return
    end

    pawnRegistered = true
    PawnRegisterThirdPartyBag("CludesUI Bags", {
        RefreshAll = RefreshPawnArrows,
    })
end

-------------------------------------------------------------------------------
--  Per-category state (for targeted sidebar updates on item count changes)
-------------------------------------------------------------------------------
local _slotCategories = {} -- bag*1000+slot -> categoryIndex from last full refresh

Inner._anyItemPanelOpen, Inner._openItemPanels = _anyItemPanelOpen, _openItemPanels
Inner._pendingResortCats, Inner._pendingResortGroups = _pendingResortCats, _pendingResortGroups
Inner._slotCategories, Inner.AcquireSlotTable = _slotCategories, AcquireSlotTable
Inner.ApplySavedOrder, Inner.ArmorySlotGroupingEnabled = ApplySavedOrder, ArmorySlotGroupingEnabled
Inner.bagSlots, Inner.BuildExpansionBuckets = bagSlots, BuildExpansionBuckets
Inner.BuildSlotBuckets, Inner.ClearGroupOrder = BuildSlotBuckets, ClearGroupOrder
Inner.DetectAndApplySwaps, Inner.FOOTER_H = DetectAndApplySwaps, FOOTER_H
Inner.GetArmorySlotBucket, Inner.HEADER_H = GetArmorySlotBucket, HEADER_H
Inner.IsArmoryGearCategory, Inner.IsGearOnlyGroup = IsArmoryGearCategory, IsGearOnlyGroup
Inner.itemSlots, Inner.MergeDuplicates = itemSlots, MergeDuplicates
Inner.PreCacheSortFields, Inner.reagentSlots = PreCacheSortFields, reagentSlots
Inner.RegisterPawnIntegration = RegisterPawnIntegration
Inner.ReleaseAllSlotTables, Inner.ResortAfterGroupChange = ReleaseAllSlotTables, ResortAfterGroupChange
Inner.SaveCategoryOrder, Inner.selectedCategoryIndex = SaveCategoryOrder, selectedCategoryIndex
Inner.SetItemPanelOpen, Inner.SIDEBAR_BTN_H = SetItemPanelOpen, SIDEBAR_BTN_H
Inner.SIDEBAR_ICON_SIZE, Inner.SIDEBAR_INDENT = SIDEBAR_ICON_SIZE, SIDEBAR_INDENT
Inner.SIDEBAR_PAD, Inner.SIDEBAR_W_COLLAPSED = SIDEBAR_PAD, SIDEBAR_W_COLLAPSED
Inner.SIDEBAR_W_EXPANDED, Inner.TakeBagSnapshot = SIDEBAR_W_EXPANDED, TakeBagSnapshot
Inner.UpdatePawnArrow, Inner.VisualSortCompare = UpdatePawnArrow, VisualSortCompare
Inner.broken = false
