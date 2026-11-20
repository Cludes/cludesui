if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUIBags_Categories.lua
--  Category system based on Enum.ItemClass numeric IDs (locale-safe).
--  Categories are hardcoded definitions. Users can rename, reorder, and group
--  them via sidebar context menus. Icons and type rules are not customizable.
-------------------------------------------------------------------------------

local CategoryManager = {}
-- Profile access helper (DB created in CUI_Bags_Options.lua, loaded first per TOC)
local CUI = CludesUI
local mod = select(2, ...)
local GetItemInfoInstant = C_Item.GetItemInfoInstant
local _emptyP = {}
local function BagsProfile()
    return (CUI._bagsDB and CUI._bagsDB.profile) or _emptyP
end

-- Enum.ItemClass numeric IDs (locale-independent)
local IC = Enum.ItemClass
local IC_CONSUMABLE = IC.Consumable -- 0
local IC_CONTAINER = IC.Container -- 1
local IC_WEAPON = IC.Weapon -- 2
local IC_GEM = IC.Gem -- 3
local IC_ARMOR = IC.Armor -- 4
local IC_REAGENT = IC.Reagent -- 5
local IC_TRADESKILL = IC.Tradegoods -- 7
local IC_ITEM_ENHANCE = IC.ItemEnhancement -- 8
local IC_RECIPE = IC.Recipe -- 9
local IC_QUEST = IC.Questitem -- 12
local IC_MISC = IC.Miscellaneous -- 15
local IC_PROFESSION = 19 -- Enum.ItemClass.Profession (Midnight)
local IC_HOUSING = 20 -- Enum.ItemClass.Housing (Midnight)

-- Hardcoded category definitions. Order here is the default order.
-- types = list of Enum.ItemClass numeric IDs to match
-- Empty types = catch-all (Uncategorized)
local DEFAULT_CATEGORIES = {
    {
        name = "Pinned Items",
        types = {},
        isPinned = true,
        noGroup = true,
        noMove = true,
        icon = "friendslist-recentallies-Pin-yellow",
        isAtlas = true,
    },
    {
        name = "Recent Items",
        types = {},
        isRecent = true,
        noGroup = true,
        noMove = true,
        icon = "auctionhouse-icon-clock",
        isAtlas = true,
    },
    { name = "Reagent Bag", types = {}, isReagentBag = true, noGroup = true, icon = 3622222 },
    { name = "Item Set Gear", types = { IC_ARMOR, IC_WEAPON }, isSetGear = true, icon = 4871338 },
    {
        name = "Quest Items",
        types = { IC_QUEST },
        icon = "Crosshair_Quest_64",
        isAtlas = true,
    },
    {
        name = "Weapons / Trinkets",
        types = { IC_WEAPON },
        equipSlots = { "INVTYPE_TRINKET" },
        icon = 3751725,
    },
    {
        name = "Armor",
        types = { IC_ARMOR },
        excludeEquipSlots = { "INVTYPE_TRINKET" },
        icon = 4382688,
    },
    { name = "Consumables", types = { IC_CONSUMABLE }, icon = 7548911 },
    { name = "Trade Goods", types = { IC_TRADESKILL, IC_REAGENT }, icon = 132996 },
    { name = "Gear Enhancements", types = { IC_GEM, IC_ITEM_ENHANCE }, icon = 7549094 },
    { name = "Professions", types = { IC_PROFESSION, IC_RECIPE }, icon = 7548925 },
    { name = "Housing", types = { IC_HOUSING }, icon = 7726459 },
    { name = "Miscellaneous", types = { IC_MISC, IC_CONTAINER }, isCatchAll = true, icon = 5524917 },
}

if CUI_CLIENT_FOREVER then
    local campItemIDs = {
        [279956] = true, -- Mana Well
        [279970] = true, -- Fermenter
        [279990] = true, -- Alchemy Laboratory
        [279944] = true, -- Sharpening Wheel
        [279988] = true, -- Anvil
        [279955] = true, -- Master Forge
        [279976] = true, -- Enchanted Lute
        [279985] = true, -- Arcane Salvager
        [279987] = true, -- Arcane Forge
        [279950] = true, -- Reagent Bot
        [279949] = true, -- Repair Bot
        [279989] = true, -- Anarchist's Workbench
        [279962] = true, -- Incense Candle
        [279964] = true, -- Greenhouse
        [279947] = true, -- Seed Hybridizer
        [279978] = true, -- Camp Tent
        [279941] = true, -- Tanning Rack
        [279945] = true, -- Sewing Machine
        [279960] = true, -- Lodestone
        [279948] = true, -- Rock Garden
        [279952] = true, -- Molten Foundry
        [279979] = true, -- Camp Chair
        [279969] = true, -- Field Guide
        [279938] = true, -- Trapper's Workbench
        [279973] = true, -- Faction Banner
        [279943] = true, -- Spinning Wheel
        [279959] = true, -- Loom
        [279981] = true, -- Basic Campfire Kit
        [279961] = true, -- Journeyman Campfire Kit
        [279957] = true, -- Cookie's Feast
        [279974] = true, -- Expert Campfire Kit
        [279982] = true, -- Iron Oven
        [279968] = true, -- First Aid Kit
        [279940] = true, -- Toxin Study
        [279951] = true, -- Plague Doctor's Laboratory
        [279967] = true, -- Fish Bowl
        [279965] = true, -- Fishing Rack
        [279966] = true, -- Fishing Hut
    }

    for _, catDef in ipairs(DEFAULT_CATEGORIES) do
        if catDef.name == "Consumables" or catDef.name == "Gear Enhancements" then
            catDef.defaultGroupName = "Adventure Prep"
        end
    end
    for i, catDef in ipairs(DEFAULT_CATEGORIES) do
        if catDef.name == "Gear Enhancements" then
            table.insert(DEFAULT_CATEGORIES, i + 1, {
                name = "Camp Items",
                itemIDs = campItemIDs,
                icon = 135805,
                defaultGroupName = "Adventure Prep",
            })
            break
        end
    end
    -- What the special bags hold (quivers, ammo pouches, soul, herb and
    -- enchanting bags; ns.SpecialBags). Appended last (only Junk follows), also
    -- in a profile with a saved category order: no saved category's index moves
    -- (bagVisualOrder).
    DEFAULT_CATEGORIES[#DEFAULT_CATEGORIES + 1] = {
        name = "Special Bags",
        types = {},
        isSpecialBag = true,
        noGroup = true,
        appendLast = true,
        icon = "Interface\\Icons\\INV_Misc_Bag_EnchantedRunecloth",
    }
    for i = #DEFAULT_CATEGORIES, 1, -1 do
        if DEFAULT_CATEGORIES[i].name == "Housing" then
            table.remove(DEFAULT_CATEGORIES, i)
        end
    end
end

-- Junk: always the last category (InitCategories puts it there, and drags and
-- moves never pass it), so turning the Junk Marker on or off never shifts
-- another category's index (bagVisualOrder is index-keyed). No types: grey items
-- and marks are its members. Its icon is the game's coin, as is the item badge
-- (only the header button draws our own coin art).
mod.JUNK_COIN = 133784
DEFAULT_CATEGORIES[#DEFAULT_CATEGORIES + 1] = {
    name = "Junk",
    types = {},
    isJunk = true,
    appendLast = true,
    noGroup = true,
    icon = mod.JUNK_COIN,
}

-- Providers of virtual categories (see RegisterVirtualCategory), sorted by
-- order then id; nil until the first registration.
local _virtual

-------------------------------------------------------------------------------
--  Init
--  Builds the runtime category list from hardcoded defaults + saved user state
--  (renames, reorder, grouping). Saved state keyed by default name.
-------------------------------------------------------------------------------
function CategoryManager:InitCategories()
    -- The category list is a DERIVATION of db.profile, cached in _categories
    -- and read BACK by SaveState. In a standalone build every file executes
    -- before the SavedVariables load, so an early build necessarily sees
    -- defaults and BP()'s empty-table fallback hides that. Record whether this
    -- build saw a trustworthy profile; GetCategories re-runs until one did.
    -- Missing framework counts as NOT ready, so the answer can only improve.
    local Lite = CludesUI and CludesUI.Lite
    self._builtReady = (Lite and Lite.IsDBReady and Lite.IsDBReady()) or false
    -- User state: { [defaultName] = { rename, groupName, groupNameCustom } }
    local customState = BagsProfile().bagCategoryState or {}
    -- User order: list of default names in display order
    local customOrder = BagsProfile().bagCategoryOrder

    -- Build ordered list of default names
    -- Index DEFAULT_CATEGORIES by name for fast lookup
    local defByName = {}
    for _, catDef in ipairs(DEFAULT_CATEGORIES) do
        defByName[catDef.name] = catDef
    end
    -- Index user-created custom categories by key
    local userCatByKey = {}
    local customCats = BagsProfile().bagUserCategories
    if customCats then
        for _, userCat in ipairs(customCats) do
            userCatByKey[userCat.key] = userCat
        end
    end

    local defOrder = {}
    if customOrder and #customOrder > 0 then
        -- Use saved order, restoring both built-in and custom categories
        -- at their saved positions
        local seen = {}
        for _, catName in ipairs(customOrder) do
            local catDef = defByName[catName]
            if catDef then
                defOrder[#defOrder + 1] = catDef
                seen[catName] = true
            elseif userCatByKey[catName] then
                -- Custom category placeholder: mark with _isCustom so the
                -- category builder below can create it at this position
                defOrder[#defOrder + 1] = { name = catName, _isCustom = true }
                seen[catName] = true
            end
        end
        -- Append any new built-in defaults not in the saved order
        for _, catDef in ipairs(DEFAULT_CATEGORIES) do
            if not seen[catDef.name] then
                if catDef.noMove then
                    -- noMove categories always go to the top
                    table.insert(defOrder, 1, catDef)
                elseif catDef.appendLast then
                    -- Last: no saved category's index moves (bagVisualOrder is
                    -- keyed by index)
                    defOrder[#defOrder + 1] = catDef
                else
                    -- Insert before catch-all
                    local insertIdx = #defOrder
                    for i, od in ipairs(defOrder) do
                        if od.isCatchAll then
                            insertIdx = i
                            break
                        end
                    end
                    table.insert(defOrder, insertIdx, catDef)
                end
            end
        end
    else
        for _, catDef in ipairs(DEFAULT_CATEGORIES) do
            defOrder[#defOrder + 1] = catDef
        end
    end

    -- Force noMove categories to the top (in their DEFAULT_CATEGORIES order)
    local pinnedSet = {}
    for _, catDef in ipairs(defOrder) do
        if catDef.noMove then
            pinnedSet[catDef.name] = true
        end
    end
    local pinned = {}
    -- Use DEFAULT_CATEGORIES order for noMove items (not saved order)
    for _, catDef in ipairs(DEFAULT_CATEGORIES) do
        if catDef.noMove and pinnedSet[catDef.name] then
            pinned[#pinned + 1] = catDef
        end
    end
    local rest, junkDef = {}, nil
    for _, catDef in ipairs(defOrder) do
        if catDef.isJunk then
            junkDef = catDef
        elseif not catDef.noMove then
            rest[#rest + 1] = catDef
        end
    end
    defOrder = {}
    for _, skinData in ipairs(pinned) do
        defOrder[#defOrder + 1] = skinData
    end
    for _, skinData in ipairs(rest) do
        defOrder[#defOrder + 1] = skinData
    end
    -- Junk goes last, and exists only while the Junk Marker is on (its marks
    -- stay saved meanwhile).
    if junkDef and self:IsJunkMarkerEnabled() then
        defOrder[#defOrder + 1] = junkDef
    end

    -- Build runtime categories from ordered defaults + user state.
    -- Custom category placeholders (_isCustom) are expanded inline so
    -- they keep their saved position relative to built-in categories.
    local categoryList = {}
    local customInserted = {}
    for _, catDef in ipairs(defOrder) do
        if catDef._isCustom then
            -- Expand custom category placeholder at its saved position
            local userCat = userCatByKey[catDef.name]
            if userCat then
                local userCatState = customState[userCat.key]
                local ucIcon = userCat.icon or 134400
                local ucIsAtlas = type(ucIcon) == "string"
                categoryList[#categoryList + 1] = {
                    _defaultName = userCat.key,
                    name = (userCatState and userCatState.rename) or userCat.name,
                    types = {},
                    icon = ucIcon,
                    isAtlas = ucIsAtlas or nil,
                    isUserCreated = true,
                    groupName = userCatState and userCatState.groupName,
                    groupNameCustom = userCatState and userCatState.groupNameCustom,
                }
                customInserted[userCat.key] = true
            end
        else
            local status = customState[catDef.name]
            -- The default group name stays raw: the seeded groups in
            -- CludesUIBags_DB.lua store it raw too, so both land in one group
            -- on every locale.
            local group
            if status and status.groupName ~= nil then
                group = status.groupName
            elseif catDef.defaultGroupName then
                group = catDef.defaultGroupName
            end
            categoryList[#categoryList + 1] = {
                _defaultName = catDef.name,
                name = (status and status.rename) or CludesUI.L(catDef.name),
                types = catDef.types,
                itemIDs = catDef.itemIDs,
                icon = catDef.icon,
                isAtlas = catDef.isAtlas,
                equipSlots = catDef.equipSlots,
                excludeEquipSlots = catDef.excludeEquipSlots,
                isCatchAll = catDef.isCatchAll,
                isSetGear = catDef.isSetGear,
                isReagentBag = catDef.isReagentBag,
                isSpecialBag = catDef.isSpecialBag,
                isJunk = catDef.isJunk,
                isPinned = catDef.isPinned,
                isRecent = catDef.isRecent,
                noGroup = catDef.noGroup,
                noMove = catDef.noMove,
                groupName = group,
                groupNameCustom = status and status.groupNameCustom,
                defaultGroupName = catDef.defaultGroupName,
            }
            -- Split mode: append one child category per equipment set right after
            -- the "Item Set Gear" anchor. Runtime-only -- SaveState skips them, so
            -- per-character set names never reach the shared profile; the sidebar
            -- renders them nested one level under the anchor, wherever it sits.
            if catDef.isSetGear and BagsProfile().bagSplitSetGearBySet then
                local setIDs = C_EquipmentSet.GetEquipmentSetIDs()
                if setIDs then
                    local sets = {}
                    for _, setId in ipairs(setIDs) do
                        local sname, sicon = C_EquipmentSet.GetEquipmentSetInfo(setId)
                        if sname then
                            sets[#sets + 1] = { id = setId, name = sname, icon = sicon }
                        end
                    end
                    table.sort(sets, function(lhs, rhs)
                        return lhs.name < rhs.name
                    end)
                    for _, s in ipairs(sets) do
                        categoryList[#categoryList + 1] = {
                            _defaultName = "EquipSet:" .. s.id,
                            name = s.name,
                            types = catDef.types,
                            icon = s.icon or catDef.icon,
                            isSetGear = true, -- keeps gear sorting/type-walk exclusion
                            isEquipSet = true,
                            equipSetID = s.id,
                            noGroup = true,
                        }
                    end
                end
            end
        end
    end

    -- Insert any new custom categories not in the saved order (freshly
    -- created since the last save) before the catch-all.
    if customCats then
        local catchAllIdx
        for i, c in ipairs(categoryList) do
            if c.isCatchAll then
                catchAllIdx = i
                break
            end
        end
        if not catchAllIdx then
            catchAllIdx = #categoryList + 1
        end
        for _, userCat in ipairs(customCats) do
            if not customInserted[userCat.key] then
                local userCatState = customState[userCat.key]
                local ucIcon = userCat.icon or 134400
                local ucIsAtlas = type(ucIcon) == "string"
                table.insert(categoryList, catchAllIdx, {
                    _defaultName = userCat.key,
                    name = (userCatState and userCatState.rename) or userCat.name,
                    types = {},
                    icon = ucIcon,
                    isAtlas = ucIsAtlas or nil,
                    isUserCreated = true,
                    groupName = userCatState and userCatState.groupName,
                    groupNameCustom = userCatState and userCatState.groupNameCustom,
                })
                catchAllIdx = catchAllIdx + 1
            end
        end
    end

    -- Virtual categories come last, after Junk: no saved index moves.
    if _virtual then
        for _, rec in ipairs(_virtual) do
            categoryList[#categoryList + 1] = {
                _defaultName = "Virtual:" .. rec.id,
                name = rec.name,
                types = {},
                icon = rec.icon,
                isAtlas = rec.isAtlas,
                isVirtual = true,
                noGroup = true,
                noMove = true,
            }
        end
    end

    self._categories = categoryList

    -- setID -> category index, for split-mode classification. The same pass
    -- notes whether any category carries a fixed item list, so ClassifyItem
    -- skips that scan entirely when none does (every retail category).
    local setCatIdx = {}
    local hasItemIDs = false
    for i, category in ipairs(categoryList) do
        if category.equipSetID then
            setCatIdx[category.equipSetID] = i
        end
        if category.itemIDs then
            hasItemIDs = true
        end
    end
    self._setCatIdxBySetID = setCatIdx
    self._hasItemIDCats = hasItemIDs

    -- Clean up legacy DB keys
    CludesUIDB.bagCategoryDefs = nil
    CludesUIDB.categoryItems = nil
    CludesUIDB.categoryPositions = nil
    CludesUIDB.categoryColumns = nil
end

-- Save user state (renames, grouping) and order back to DB
function CategoryManager:SaveState()
    -- Never write a snapshot built before the SavedVariables merged. This is
    -- the destructive half of the bug: the category list is cached and then
    -- written straight back, so a cache built from the pre-SavedVariables
    -- orphan profile does not merely display defaults, it stamps them over
    -- the user's real categories on the very next save.
    local Lite = CludesUI and CludesUI.Lite
    if Lite and Lite.IsDBReady and not Lite.IsDBReady() then
        return
    end
    local categoryList = self._categories
    if not categoryList then
        return
    end

    local customState = {}
    local customOrder = {}
    local sawJunk = false
    for _, category in ipairs(categoryList) do
        if category.isJunk then
            sawJunk = true
        end
        if category.isEquipSet or category.isVirtual then
            -- Runtime-only: children of the "Item Set Gear" anchor and virtual
            -- categories are never persisted; InitCategories re-appends them
            -- each rebuild.
            -- (skip)
        else
            customOrder[#customOrder + 1] = category._defaultName
            local stateKnown = false
            local record = {}
            -- Compare against the LOCALIZED default name. cat.name is the localized
            -- display string (state.rename or L(_defaultName)) while _defaultName is the
            -- English identity key. On a non-English client a plain inequality would see
            -- every untouched default category as "renamed" and freeze its localized name
            -- into the DB, so only treat it as a rename when it differs from the locale default.
            if category.name ~= CludesUI.L(category._defaultName) then
                record.rename = category.name
                stateKnown = true
            end
            if category.groupName then
                record.groupName = category.groupName
                stateKnown = true
            elseif category.defaultGroupName then
                record.groupName = false
                stateKnown = true
            end
            if category.groupNameCustom then
                record.groupNameCustom = category.groupNameCustom
                stateKnown = true
            end
            if stateKnown then
                customState[category._defaultName] = record
            end
        end
    end
    -- Junk is out of the list while the Junk Marker is off: keep its saved rename
    if not sawJunk then
        local old = BagsProfile().bagCategoryState
        if old and old[self.JUNK_KEY] then
            customState[self.JUNK_KEY] = old[self.JUNK_KEY]
        end
    end
    BagsProfile().bagCategoryState = customState
    BagsProfile().bagCategoryOrder = customOrder

    -- Rebuild user-created categories list from runtime state
    local ucList = {}
    for _, category in ipairs(categoryList) do
        if category.isUserCreated then
            ucList[#ucList + 1] =
                { key = category._defaultName, name = category._defaultName, icon = category.icon }
        end
    end
    BagsProfile().bagUserCategories = #ucList > 0 and ucList or nil
end

-------------------------------------------------------------------------------
--  Accessors
-------------------------------------------------------------------------------
function CategoryManager:GetCategories()
    -- Rebuild not just when empty, but while the cached list was built before
    -- the profile could be trusted. Pull, not push: a callback registered at
    -- file scope would depend on the framework having loaded first, which is
    -- the same ordering assumption that caused this bug -- and unverifiable in
    -- the standalone TOC. By the time anything READS categories the framework
    -- is certainly present.
    if not self._categories or not self._builtReady then
        self:InitCategories()
    end
    return self._categories
end

-- Categories that persist: all but the virtual tail (indices 1..n are the only
-- ones saved data may key on).
function CategoryManager:GetSavedCount()
    return #self:GetCategories() - (_virtual and #_virtual or 0)
end

-- Is this index a virtual category's? Costs nothing while none is registered.
function CategoryManager:IsVirtual(index)
    if not _virtual then
        return false
    end
    local category = self:GetCategories()[index]
    return category and category.isVirtual or false
end

-------------------------------------------------------------------------------
--  Classification
-------------------------------------------------------------------------------
-- Equipment set lookup: built once per ClassifyAll pass.
-- Maps "bag*1000+slot" -> setID. A slot in several sets keeps the first
-- (enumeration order), matching split-mode classification's first-set-wins.
local _setGearLookup = {}
-- setID -> set name, for the on-item set name label (no API call at stamp time)
local _setNames = {}
-- WoW Forever: itemID -> setID of the sets' items, refilled each pass
local _foreverSetItems = {}

local function BuildSetGearLookup()
    wipe(_setGearLookup)
    wipe(_setNames)
    local setIDs = C_EquipmentSet.GetEquipmentSetIDs()
    if not setIDs then
        return
    end
    -- Names only feed the on-item label; skip the API calls when it's off
    local wantNames = BagsProfile().bagShowSetGearName == true
    -- WoW Forever crashes the client inside GetItemLocations for some sets:
    -- there the sets' item IDs are matched against the container slots instead.
    local foreverList = CludesUI.IS_FOREVER and _foreverSetItems
    if foreverList then
        wipe(foreverList)
    end
    for _, setId in ipairs(setIDs) do
        if wantNames then
            _setNames[setId] = C_EquipmentSet.GetEquipmentSetInfo(setId)
        end
        local locs = not foreverList and C_EquipmentSet.GetItemLocations(setId)
        local ids = foreverList and C_EquipmentSet.GetItemIDs(setId)
        if ids then
            for _, itemId in pairs(ids) do
                if type(itemId) == "number" and itemId > 0 and not foreverList[itemId] then
                    foreverList[itemId] = setId
                end
            end
        end
        if locs then
            for _, loc in pairs(locs) do
                if loc and loc ~= 0 and loc ~= 1 and loc ~= -1 then
                    local payload = EquipmentManager_GetLocationData(loc)
                    if payload.isBags then
                        local key = payload.bag * 1000 + payload.slot
                        if not _setGearLookup[key] then
                            _setGearLookup[key] = setId
                        end
                    end
                end
            end
        end
    end
    if foreverList and next(foreverList) and Enum.BagIndex then
        -- Every container the client knows (bags, bank, keyring); a closed bank reads empty.
        for _, bagId in pairs(Enum.BagIndex) do
            for slotId = 1, C_Container.GetContainerNumSlots(bagId) or 0 do
                local setId = foreverList[C_Container.GetContainerItemID(bagId, slotId) or 0]
                if setId then
                    _setGearLookup[bagId * 1000 + slotId] = setId
                end
            end
        end
    end
end

-- Sell Junk's equipment set check: the lookup, rebuilt now
function CategoryManager:GetSetGearLookup()
    BuildSetGearLookup()
    return _setGearLookup
end

-- Manual overrides: itemID -> classID
local ITEM_TYPE_OVERRIDES = {
    [180653] = IC_MISC,
}

-- WoW Forever's special bags (ns.SpecialBags) for the running ClassifyAll pass
local _classifySpecial

-- A virtual provider's answer, set by AskVirtual inside securecallfunction
-- (stays false when the provider errors)
local _virtualClaim = false
local function AskVirtual(classify, ...)
    _virtualClaim = classify(...) and true or false
end
-- True while the providers are asked: a provider cannot register, unregister
-- or ask for a repaint from inside its own classify call
local _asking = false

-- Classify a single item. Returns category index (1-based) or nil for empty slots.
-- bag/slot are needed for C_Container.GetContainerItemQuestInfo; quality is
-- optional (resolved from the link when nil)
function CategoryManager:ClassifyItem(itemLink, itemId, bagId, slotId, quality)
    if not itemLink then
        return nil
    end

    local categoryList = self:GetCategories()

    -- Reagent bag items always go to the Reagent Bag category
    if bagId == 5 then
        for i, category in ipairs(categoryList) do
            if category.isReagentBag then
                return i
            end
        end
    end
    -- A WoW Forever special bag's items always go to Special Bags
    if _classifySpecial and _classifySpecial[bagId] then
        for i, category in ipairs(categoryList) do
            if category.isSpecialBag then
                return i
            end
        end
    end

    -- User item assignments: itemID -> category _defaultName.
    -- Checked before type matching so users can override auto-classification.
    if itemId then
        local assignMap = CludesUIDB and CludesUIDB.bagItemAssignments
        local assignedKey = assignMap and assignMap[itemId]
        if assignedKey then
            for i, category in ipairs(categoryList) do
                if category._defaultName == assignedKey then
                    return i
                end
            end
        end
    end

    -- Virtual categories: the providers answer before the built-in rules (their
    -- cats are the tail of the list). A provider error is reported, never stops
    -- the pass, and counts as "no". Junk is not offered: what Sell Junk sells
    -- stays in the Junk category.
    if _virtual and not self:IsJunk(itemId, quality) then
        local base = #categoryList - #_virtual
        local claimed
        _asking = true
        for i, rec in ipairs(_virtual) do
            _virtualClaim = false
            securecallfunction(AskVirtual, rec.classify, itemLink, itemId, bagId, slotId, quality)
            if _virtualClaim then
                claimed = base + i
                break
            end
        end
        _asking = false
        if claimed then
            return claimed
        end
    end

    -- Fixed item lists (Forever camp items) win over item-class matching; the
    -- scan runs only while some category carries one (see InitCategories).
    if itemId and self._hasItemIDCats then
        for i, category in ipairs(categoryList) do
            if category.itemIDs and category.itemIDs[itemId] then
                return i
            end
        end
    end

    -- Check manual overrides first
    if itemId and ITEM_TYPE_OVERRIDES[itemId] then
        local overrideClassID = ITEM_TYPE_OVERRIDES[itemId]
        for i, category in ipairs(categoryList) do
            if category.types then
                for _, kind in ipairs(category.types) do
                    if kind == overrideClassID then
                        return i
                    end
                end
            end
        end
    end

    -- Check quest status via dedicated API (catches "begins a quest" items too)
    if bagId and slotId then
        local questInfo = C_Container.GetContainerItemQuestInfo(bagId, slotId)
        if questInfo and (questInfo.isQuestItem or questInfo.questID) then
            for i, category in ipairs(categoryList) do
                if category.types then
                    for _, kind in ipairs(category.types) do
                        if kind == IC_QUEST then
                            return i
                        end
                    end
                end
            end
        end
    end

    -- Grey items go to Junk (no index while the Junk Marker is off); explicit
    -- assignments and quest items are resolved above.
    if self._junkCatIdx then
        if quality == nil then
            quality = select(3, C_Item.GetItemInfo(itemLink))
        end
        if quality == 0 then
            return self._junkCatIdx
        end
    end

    -- Get classID + equip slot via GetItemInfoInstant (locale-safe numeric IDs)
    local _, _, _, equipSlot, _, classID = GetItemInfoInstant(itemLink)
    if not classID then
        -- Item data not available; classify as catch-all for now
        for i, category in ipairs(categoryList) do
            if category.isCatchAll then
                return i
            end
        end
        return #categoryList
    end

    -- Equipment set gear check: if item is Armor/Weapon AND in an equipment set,
    -- route to its own set's category (split mode; first set wins for items in
    -- several) or the merged "Item Set Gear" category, before normal type matching
    if bagId and slotId and (classID == IC_ARMOR or classID == IC_WEAPON) then
        local setId = _setGearLookup[bagId * 1000 + slotId]
        if setId then
            local byID = self._setCatIdxBySetID
            local position = byID and byID[setId]
            if position then
                return position
            end
            for i, category in ipairs(categoryList) do
                -- Anchor explicitly: children are isSetGear too, and cats order
                -- can put them first after the anchor is drag-reordered
                if category.isSetGear and not category.isEquipSet then
                    return i
                end
            end
        end
    end

    -- Walk categories and check if item classID + equip slot matches
    for i, category in ipairs(categoryList) do
        if category.types and #category.types > 0 and not category.isSetGear then
            local typeMatch = false
            for _, kind in ipairs(category.types) do
                if kind == classID then
                    typeMatch = true
                    break
                end
            end

            -- equipSlots: match items of OTHER types that have these equip slots
            -- (e.g. trinkets are classID Armor but equipSlot "INVTYPE_TRINKET")
            if not typeMatch and category.equipSlots and equipSlot then
                for _, es in ipairs(category.equipSlots) do
                    if es == equipSlot then
                        typeMatch = true
                        break
                    end
                end
            end

            -- excludeEquipSlots: reject items that match the classID but have excluded equip slots
            if typeMatch and category.excludeEquipSlots and equipSlot then
                for _, es in ipairs(category.excludeEquipSlots) do
                    if es == equipSlot then
                        typeMatch = false
                        break
                    end
                end
            end

            if typeMatch then
                return i
            end
        end
    end

    -- No match: use catch-all category
    for i, category in ipairs(categoryList) do
        if category.isCatchAll then
            return i
        end
    end
    return #categoryList
end

-- Classify all items and return counts per category + total.
-- Each item in the array gets a .categoryIndex field set.
-- Reusable tables for ClassifyAll (wiped each call, avoids per-refresh allocation)
local _claCounts = {}
local _claDisabledIdxSet = {}

function CategoryManager:ClassifyAll(itemList)
    BuildSetGearLookup()
    _classifySpecial = mod.SpecialBags()
    local categoryList = self:GetCategories()
    -- Rebuild setID -> index every pass: drag-reorder and custom-category
    -- add/remove mutate cats in place without InitCategories, shifting indices.
    -- Refill gated on split mode (no children exist when it's off).
    local setCatIdx = self._setCatIdxBySetID or {}
    wipe(setCatIdx)
    if BagsProfile().bagSplitSetGearBySet then
        for i, category in ipairs(categoryList) do
            if category.equipSetID then
                setCatIdx[category.equipSetID] = i
            end
        end
    end
    self._setCatIdxBySetID = setCatIdx
    -- Junk's index too, for the same reason (nil while the Junk Marker is off).
    local junkIdx
    wipe(_claCounts)
    for i = 1, #categoryList do
        _claCounts[i] = 0
        if categoryList[i].isJunk then
            junkIdx = i
        end
    end
    self._junkCatIdx = junkIdx
    local counts = _claCounts
    local sum = 0

    -- Disabled categories: items route to catch-all instead (keyed by _defaultName)
    local disabledCats = BagsProfile().bagDisabledCategories
    local catchAllIdx
    wipe(_claDisabledIdxSet)
    local disabledIdxSet
    if disabledCats then
        disabledIdxSet = _claDisabledIdxSet
        for i, category in ipairs(categoryList) do
            if category.isCatchAll then
                catchAllIdx = i
            end
            if category._defaultName and disabledCats[category._defaultName] then
                disabledIdxSet[i] = true
            end
            -- Disabling the "Item Set Gear" anchor disables its set children too,
            -- or split mode would silently bypass the user's choice.
            if category.isEquipSet and disabledCats["Item Set Gear"] then
                disabledIdxSet[i] = true
            end
        end
    end

    -- On-item label stamping gated on its toggle (recycled tables are wiped on
    -- acquire, so no stale _setName survives while it's off)
    local stampNames = BagsProfile().bagShowSetGearName == true
    for _, payload in ipairs(itemList) do
        if payload.info and payload.itemLink then
            local position = self:ClassifyItem(
                payload.itemLink,
                payload.info.itemID,
                payload.bag,
                payload.slot,
                payload.info.quality
            )
            if stampNames then
                local spellRef = _setGearLookup[payload.bag * 1000 + payload.slot]
                payload._setName = spellRef and _setNames[spellRef] or nil
            end
            -- Reroute disabled categories to catch-all
            if disabledIdxSet and position and disabledIdxSet[position] and catchAllIdx then
                position = catchAllIdx
            end
            payload.categoryIndex = position
            if position then
                counts[position] = (counts[position] or 0) + 1
            end
            sum = sum + 1
        end
    end

    return counts, sum
end

-------------------------------------------------------------------------------
--  Rename / Reorder (user-facing operations)
-------------------------------------------------------------------------------
function CategoryManager:RenameCategory(index, renamed)
    local categoryList = self:GetCategories()
    if not categoryList[index] then
        return false
    end
    if not renamed or renamed == "" then
        return false
    end
    local prevGroup = categoryList[index].groupName
    local shouldRegenerate = prevGroup and not self:IsGroupNameCustom(prevGroup)
    categoryList[index].name = renamed
    if shouldRegenerate then
        self:RegenerateGroupName(prevGroup)
    end
    self:SaveState()
    return true
end

-- Move category from fromIndex to toIndex.
-- Callers should NOT adjust for remove/insert -- this function handles it internally.
function CategoryManager:ReorderCategory(fromIndex, toIndex)
    local categoryList = self:GetCategories()
    if not categoryList[fromIndex] then
        return
    end
    -- Equip-set categories move as a block via their anchor; a single one dragged
    -- out would snap back on the next rebuild (SaveState collapses the block).
    if categoryList[fromIndex].isEquipSet then
        return
    end
    -- Virtual categories are the list's tail: they never move, and nothing
    -- lands among or after them
    if categoryList[fromIndex].isVirtual then
        return
    end
    local last = self:GetSavedCount()
    if toIndex > last + 1 and toIndex <= #categoryList + 1 then
        toIndex = last + 1
    end
    -- Junk stays last: it never moves, and nothing lands after it
    if categoryList[fromIndex].isJunk then
        return
    end
    if categoryList[last].isJunk and toIndex > last then
        toIndex = last
    end
    if fromIndex == toIndex or toIndex < 1 or toIndex > #categoryList + 1 then
        return
    end
    local record = table.remove(categoryList, fromIndex)
    local insertAt = toIndex
    if fromIndex < toIndex then
        insertAt = toIndex - 1
    end
    table.insert(categoryList, insertAt, record)
    self:SaveState()
end

-------------------------------------------------------------------------------
--  Grouping
-------------------------------------------------------------------------------
-- Group two or more categories together under a shared name.
function CategoryManager:GroupCategories(indices, group)
    local categoryList = self:GetCategories()
    if not indices or #indices < 2 then
        return
    end
    if not group then
        local nameList = {}
        for _, position in ipairs(indices) do
            if categoryList[position] then
                nameList[#nameList + 1] = categoryList[position].name
            end
        end
        if #nameList == 2 then
            group = nameList[1] .. " & " .. nameList[2]
        elseif #nameList >= 3 then
            local last = nameList[#nameList]
            nameList[#nameList] = nil
            group = table.concat(nameList, ", ") .. ", & " .. last
        else
            group = "Group"
        end
    end
    for _, position in ipairs(indices) do
        if categoryList[position] then
            categoryList[position].groupName = group
            categoryList[position].groupNameCustom = nil
        end
    end
    self:SaveState()
end

-- Add a category to an existing group.
function CategoryManager:AddToGroup(catIdx, group)
    local categoryList = self:GetCategories()
    if not categoryList[catIdx] or not group then
        return
    end
    categoryList[catIdx].groupName = group
    self:RegenerateGroupName(group)
    self:SaveState()
end

-- Remove a category from its group.
function CategoryManager:UngroupCategory(catIdx)
    local categoryList = self:GetCategories()
    if not categoryList[catIdx] or not categoryList[catIdx].groupName then
        return
    end
    local prevGroup = categoryList[catIdx].groupName
    local wasCustom = self:IsGroupNameCustom(prevGroup)
    categoryList[catIdx].groupName = nil
    local remaining = {}
    for i, category in ipairs(categoryList) do
        if category.groupName == prevGroup then
            remaining[#remaining + 1] = i
        end
    end
    if #remaining == 0 then
        -- No members left, nothing to do
    elseif #remaining == 1 then
        -- Only 1 member left, auto-disband
        categoryList[remaining[1]].groupName = nil
    elseif not wasCustom then
        self:RegenerateGroupName(prevGroup)
    end
    self:SaveState()
end

-- Ungroup all members of a group.
function CategoryManager:DisbandGroup(group)
    local categoryList = self:GetCategories()
    for _, category in ipairs(categoryList) do
        if category.groupName == group then
            category.groupName = nil
        end
    end
    self:SaveState()
end

-- Rename a group (updates all members).
function CategoryManager:RenameGroup(oldName, renamed)
    if not renamed or renamed == "" then
        return
    end
    local categoryList = self:GetCategories()
    for _, category in ipairs(categoryList) do
        if category.groupName == oldName then
            category.groupName = renamed
        end
    end
    self:SaveState()
end

-- Built-in group names stay English in saved data (they are group keys);
-- translate them only where they are shown.
local DEFAULT_GROUP_NAMES = { ["The Armory"] = true, ["Adventure Prep"] = true }
function CategoryManager:GroupDisplayName(group)
    if group and DEFAULT_GROUP_NAMES[group] then
        return CludesUI.L(group)
    end
    return group
end

-- Check if the group name was manually customized by the user.
function CategoryManager:IsGroupNameCustom(group)
    local categoryList = self:GetCategories()
    for _, category in ipairs(categoryList) do
        if category.groupName == group and category.groupNameCustom then
            return true
        end
    end
    return false
end

-- Mark a group name as manually customized (set on all members).
function CategoryManager:SetGroupNameCustom(group, isCustom)
    local categoryList = self:GetCategories()
    for _, category in ipairs(categoryList) do
        if category.groupName == group then
            category.groupNameCustom = isCustom or nil
        end
    end
    self:SaveState()
end

-- Auto-regenerate group name from member names.
function CategoryManager:RegenerateGroupName(group)
    local categoryList = self:GetCategories()
    local nameList = {}
    for _, category in ipairs(categoryList) do
        if category.groupName == group then
            nameList[#nameList + 1] = category.name
        end
    end
    local renamed
    if #nameList == 2 then
        renamed = nameList[1] .. " & " .. nameList[2]
    elseif #nameList >= 3 then
        local last = nameList[#nameList]
        renamed = table.concat(nameList, ", ", 1, #nameList - 1) .. ", & " .. last
    else
        return
    end
    if renamed ~= group then
        self:RenameGroup(group, renamed)
        self:SetGroupNameCustom(renamed, false)
    end
end

-- Get all unique group names.
function CategoryManager:GetGroupNames()
    local categoryList = self:GetCategories()
    local seen = {}
    local groups = {}
    for _, category in ipairs(categoryList) do
        if category.groupName and not seen[category.groupName] then
            seen[category.groupName] = true
            groups[#groups + 1] = category.groupName
        end
    end
    return groups
end

-- Get all member indices for a group.
function CategoryManager:GetGroupMembers(group)
    local categoryList = self:GetCategories()
    local members = {}
    for i, category in ipairs(categoryList) do
        if category.groupName == group then
            members[#members + 1] = i
        end
    end
    return members
end

-------------------------------------------------------------------------------
--  Custom Category CRUD
-------------------------------------------------------------------------------
-- Create a new user category. Returns the new category index.
function CategoryManager:AddCustomCategory(name)
    if not name or name == "" then
        return nil
    end
    if not BagsProfile().bagUserCategories then
        BagsProfile().bagUserCategories = {}
    end

    -- Generate a unique key
    local maxN = 0
    for _, userCat in ipairs(BagsProfile().bagUserCategories) do
        local num = tonumber(userCat.key:match("Custom_(%d+)"))
        if num and num > maxN then
            maxN = num
        end
    end
    local key = "Custom_" .. (maxN + 1)

    BagsProfile().bagUserCategories[#BagsProfile().bagUserCategories + 1] = { key = key, name = name }

    -- Insert into runtime list before catch-all
    local categoryList = self:GetCategories()
    local catchAllIdx = #categoryList + 1
    for i, c in ipairs(categoryList) do
        if c.isCatchAll then
            catchAllIdx = i
            break
        end
    end
    table.insert(categoryList, catchAllIdx, {
        _defaultName = key,
        name = name,
        types = {},
        icon = "Petjournalv2-Icon-PlusButton",
        isAtlas = true,
        isUserCreated = true,
    })
    self:SaveState()
    return catchAllIdx
end

-- Remove a user-created category. Unassigns all items in it.
function CategoryManager:RemoveCustomCategory(catIdx)
    local categoryList = self:GetCategories()
    local category = categoryList[catIdx]
    if not category or not category.isUserCreated then
        return false
    end
    local key = category._defaultName

    -- Remove item assignments pointing to this category, and Junk marks'
    -- memory of it (its key comes back on the next new category)
    local assignMap = CludesUIDB and CludesUIDB.bagItemAssignments
    if assignMap then
        for itemId, aKey in pairs(assignMap) do
            if aKey == key then
                assignMap[itemId] = nil
            end
        end
    end
    local previous = CludesUIDB and CludesUIDB.bagJunkPrev
    if previous then
        for itemId, pKey in pairs(previous) do
            if pKey == key then
                previous[itemId] = nil
            end
        end
    end

    -- Remove from runtime list
    table.remove(categoryList, catIdx)

    -- Remove from disabled list
    if BagsProfile().bagDisabledCategories then
        BagsProfile().bagDisabledCategories[key] = nil
    end

    self:SaveState()
    return true
end

-------------------------------------------------------------------------------
--  Item Assignment (user overrides auto-classification)
-------------------------------------------------------------------------------
-- A Junk mark remembers the category the item was filed in (nil: none), kept
-- only while the item stays marked: CludesUIDB.bagJunkPrev[itemID].
local function SetJunkPrev(itemId, key)
    local previous = CludesUIDB.bagJunkPrev
    if key then
        if not previous then
            previous = {}
            CludesUIDB.bagJunkPrev = previous
        end
        previous[itemId] = key
    elseif previous then
        previous[itemId] = nil
    end
end

-- Assign an itemID to a category. Pass nil to unassign. Every route that marks
-- an item as junk (the coin, a drop on the Junk row, its "+") comes through
-- here, so each remembers the item's category and reports the mark
-- (OnJunkChanged); filing a marked item anywhere else ends the mark.
function CategoryManager:AssignItem(itemId, categoryKey)
    if not itemId then
        return
    end
    if categoryKey == nil then
        return self:UnassignItem(itemId)
    end
    if not CludesUIDB then
        CludesUIDB = {}
    end
    if not CludesUIDB.bagItemAssignments then
        CludesUIDB.bagItemAssignments = {}
    end
    local assignMap = CludesUIDB.bagItemAssignments
    local current = assignMap[itemId]
    if categoryKey == self.JUNK_KEY then
        if current ~= self.JUNK_KEY then
            SetJunkPrev(itemId, current)
        end
    elseif current == self.JUNK_KEY then
        SetJunkPrev(itemId, nil)
    end
    assignMap[itemId] = categoryKey
    if (current == self.JUNK_KEY) ~= (categoryKey == self.JUNK_KEY) then
        self:OnJunkChanged()
    end
end

-- Unassign an itemID (returns to auto-classification). Unmarking a junk item
-- files it back in the category it was marked from, while that category
-- still exists (a Bags reset or a profile without it leaves the item unfiled).
function CategoryManager:UnassignItem(itemId)
    if not itemId then
        return
    end
    local assignMap = CludesUIDB and CludesUIDB.bagItemAssignments
    if not assignMap then
        return
    end
    local wasJunk = assignMap[itemId] == self.JUNK_KEY
    local back
    if wasJunk then
        local previous = CludesUIDB.bagJunkPrev
        back = previous and previous[itemId]
        if back then
            local found
            for _, category in ipairs(self:GetCategories()) do
                if category._defaultName == back then
                    found = true
                    break
                end
            end
            if not found then
                back = nil
            end
        end
    end
    SetJunkPrev(itemId, nil)
    assignMap[itemId] = back
    if wasJunk then
        self:OnJunkChanged()
    end
end

-- Check if a category can accept item assignments (drag targets).
-- Excludes Pinned, Recent, Reagent Bag and Special Bags (physical bags, not logical).
function CategoryManager:CanAssignToCategory(catIdx)
    local categoryList = self:GetCategories()
    local category = categoryList[catIdx]
    if not category then
        return false
    end
    if category.isPinned or category.isRecent or category.isReagentBag or category.isSpecialBag then
        return false
    end
    if category.isEquipSet then
        return false
    end -- membership comes from the set itself
    if category.isVirtual then
        return false
    end -- ... or from its provider
    return true
end

-------------------------------------------------------------------------------
--  Junk Marker: a mark is an assignment to the Junk category's _defaultName
--  (rename-proof). The badge, Sell Junk and mark mode all ask IsJunk.
-------------------------------------------------------------------------------
CategoryManager.JUNK_KEY = "Junk"

-- The Junk Icon of Bag Top Bar Icons switches the whole Junk Marker
function CategoryManager:IsJunkMarkerEnabled()
    return BagsProfile().bagShowJunkIcon ~= false
end

-- Marked, or grey and not filed in another category (a grey quest item files as
-- a quest item, so it is never junk unmarked). quality is optional.
function CategoryManager:IsJunk(itemId, quality)
    if not self:IsJunkMarkerEnabled() or not itemId then
        return false
    end
    local assignMap = CludesUIDB and CludesUIDB.bagItemAssignments
    local assigned = assignMap and assignMap[itemId]
    if assigned == self.JUNK_KEY then
        return true
    end
    if assigned then
        return false
    end -- filed into some other category
    if quality == nil then
        quality = select(3, C_Item.GetItemInfo(itemId))
    end
    return quality == 0 and select(6, GetItemInfoInstant(itemId)) ~= IC_QUEST
end

-- Flips an item's mark (a grey item stays junk unmarked). Marking remembers the
-- category the item was filed in, and unmarking files it back there (both in
-- AssignItem / UnassignItem, so every other route does the same).
function CategoryManager:ToggleJunk(itemId)
    if not itemId then
        return
    end
    local assignMap = CludesUIDB and CludesUIDB.bagItemAssignments
    if assignMap and assignMap[itemId] == self.JUNK_KEY then
        self:UnassignItem(itemId)
    else
        self:AssignItem(itemId, self.JUNK_KEY)
    end
end

-- A mark came or went, or the Junk Marker was switched. WoW Forever's Junk
-- Items window (Forever Essentials) lists marked items, so it picks its list
-- again; that costs nothing while the window is inactive, and the window
-- exists on no other client.
function CategoryManager:OnJunkChanged()
    local junkItems = CUI._JunkItems
    if junkItems then
        junkItems.Refresh()
    end
end

-- Equipment sets changed (created/renamed/deleted): drop the cached list so the
-- next GetCategories rebuilds split-mode categories from the current sets.
function CategoryManager:OnEquipmentSetsChanged()
    self._categories = nil
end

-------------------------------------------------------------------------------
--  Virtual categories (public API for other addons)
--  Runtime-only categories filled by a callback. They sit after every saved
--  category and after Junk, so no saved index moves, and nothing about them is
--  ever written to the saved variables: a provider that goes away leaves no
--  trace. They cannot be renamed, moved, grouped, hidden or assigned to.
--    def.name      shown name
--    def.icon      file ID, path or atlas (default: the question mark)
--    def.isAtlas   true when def.icon is an atlas
--    def.order     virtual categories sort by this, then by id (default 0)
--    def.classify  function(itemLink, itemID, bag, slot, quality) -> true to
--                  claim the item. bag and slot are nil for another character's
--                  items; quality may be nil. The first claim by order wins.
--  Items the user filed or marked, junk (grey items while the Junk Marker is
--  on) and reagent / special bag items are not offered to providers. A change
--  repaints the bags once, on the next frame. A provider cannot register,
--  unregister or ask for a repaint from inside its own classify call.
-------------------------------------------------------------------------------
-- One repaint for every change made in a frame: a request shows a hidden frame
-- whose next update hides it, then repaints the bags and an open bank.
local _repaint
local function QueueRepaint()
    if not _repaint then
        _repaint = CreateFrame("Frame")
        _repaint:SetScript("OnUpdate", function(self)
            self:Hide()
            local bags = _G.CUI_Bags
            if bags and bags.RefreshInventory then
                bags:RefreshInventory()
            end
            if mod.RefreshOpenBank then
                mod.RefreshOpenBank()
            end
        end)
    end
    _repaint:Show()
end

-- The list changed: rebuild it now (the open view re-resolves by key), repaint next.
local function VirtualChanged(self)
    local bags = _G.CUI_Bags
    if bags and bags.InvalidateSetCategories then
        bags.InvalidateSetCategories()
    else
        self:OnEquipmentSetsChanged()
    end
    QueueRepaint()
end

local function VirtualBefore(a, b)
    if a.order ~= b.order then
        return a.order < b.order
    end
    return a.id < b.id
end

-- Registering an id again replaces it. Returns true when registered.
function CategoryManager:RegisterVirtualCategory(ident, catDef)
    if _asking then
        return false
    end
    if type(ident) ~= "string" or ident == "" then
        return false
    end
    if type(catDef) ~= "table" or type(catDef.classify) ~= "function" then
        return false
    end
    _virtual = _virtual or {}
    for i, rec in ipairs(_virtual) do
        if rec.id == ident then
            table.remove(_virtual, i)
            break
        end
    end
    _virtual[#_virtual + 1] = {
        id = ident,
        name = type(catDef.name) == "string" and catDef.name ~= "" and catDef.name or ident,
        icon = catDef.icon or 134400,
        isAtlas = catDef.isAtlas and true or nil,
        order = tonumber(catDef.order) or 0,
        classify = catDef.classify,
    }
    table.sort(_virtual, VirtualBefore)
    VirtualChanged(self)
    return true
end

-- Returns true when the id was registered.
function CategoryManager:UnregisterVirtualCategory(ident)
    if not _virtual or _asking then
        return false
    end
    for i, rec in ipairs(_virtual) do
        if rec.id == ident then
            table.remove(_virtual, i)
            if #_virtual == 0 then
                _virtual = nil
            end
            VirtualChanged(self)
            return true
        end
    end
    return false
end

-- A provider's answers changed (its data loaded, its rules changed): classify again.
function CategoryManager:RefreshVirtualCategories()
    if not _virtual or _asking then
        return
    end
    self:OnVirtualAnswersChanged()
    QueueRepaint()
end

-- What RefreshVirtualCategories reports through: the offline views watch this
-- one, so a provider's kept reference to the function above still reaches them.
function CategoryManager:OnVirtualAnswersChanged() end

-------------------------------------------------------------------------------
--  Global accessor
-------------------------------------------------------------------------------
if not _G.CUI_CategoryManager then
    _G.CUI_CategoryManager = CategoryManager
end

CategoryManager:InitCategories()
