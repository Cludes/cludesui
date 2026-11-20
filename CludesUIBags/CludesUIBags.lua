if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUIBags.lua -- Enhanced Bags System for CludesUI (Midnight): sidebar category filter + flat item grid layout.
-------------------------------------------------------------------------------
if
    not (
        CludesUI
        and CludesUI._ModuleNS
        and CludesUI.NewInternals
        and CludesUI.NewCombatQueue
        and CludesUI.CreateQuantityDialog
        and CludesUI.ReleaseStaleHold
        and CludesUI.ForeverLookMajority
        and CludesUI.ForeverHeavyOK
        and CludesUI.ForeverHeavy
        and CludesUI.ForeverHeavySeat
        and CludesUI.ForeverHeavyTitle
        and CludesUI.ForeverBorder
        and CludesUI.ForeverBorderSeat
        and CludesUI.ForeverBorderPaint
    )
then
    CUI_CLIENT_BLOCKED = true
    return
end -- stale-parent guard: a partially updated install (old parent, new child) goes dormant via the line-1 failsafe instead of erroring (the stack splitter is the parent's quantity window; ReleaseStaleHold / DropHold, the sort's sound effects mute; the WoW Forever style draws the parent's Forever frames and follows its look majority)
local mod = select(2, ...)
CludesUI._ModuleNS["CludesUIBags"] = mod -- LOD options files read this module ns via the registry
mod.CombatQueue = CludesUI.NewCombatQueue(CreateFrame("Frame"))

CUI_Bags = CreateFrame("Frame", "CUI_MainBagFrame", UIParent)
CUI_Bags:SetToplevel(true)
CUI_Bags:Hide()
-- Auto-size state: reset on close (next open sizes from its first/active tab);
-- while open it only grows, never shrinks.
CUI_Bags:HookScript("OnHide", function(self)
    -- WoW Forever and the Compact display size every open to its content: a hidden UI (Alt-Z) is not a close, keep the size.
    if (CludesUI.IS_FOREVER or CUI_Bags.IsCompactMode()) and self:IsShown() then
        return
    end
    self._asCols = nil
    self._asMaxGridW = nil
    self._asMaxH = nil
    -- The Compact display's grow-only width (RefreshInventory)
    self._compactCols, self._compactW = nil, nil
end)

CUI_BagsReagent = CreateFrame("Frame", "CUI_ReagentBagFrame", UIParent)
CUI_BagsReagent:Hide()

CUI_BagsWindow = CreateFrame("Frame", "CUI_BagsWindowFrame", UIParent)
CUI_BagsWindow:Hide()

local SLOT_SIZE, SPACING = 34, 4
local GetItemInfoInstant = C_Item.GetItemInfoInstant
local IsEquippableItem = C_Item.IsEquippableItem

-- Red-tint usability test (shared with the bank module via CUI). Tooltip must come from
-- the real item, never GetItemByID: scaling gear's bonus IDs lower its required level, but
-- GetItemByID shows the unscaled base item's level (reads red). Prefer bag slot > link > ID; cache by link, wipe on level-up.
local _canUseCache = {}
local ITEM_CLASS_RECIPE = Enum.ItemClass.Recipe
local function BagsItemUnusable(bagID, slot, itemLink, itemId)
    local entry = itemLink or itemId
    if not entry then
        return false
    end
    local cached = _canUseCache[entry]
    if cached ~= nil then
        return cached
    end
    local unusable = false

    -- Recipes also have a spell (the teach effect), so they'd hit the tooltip scan
    -- below. Skip that: the scan can see red from the crafted item's own preview
    -- stats, not just from the recipe's learn requirements. Use the usable check
    -- instead, which reflects skill/known state directly.
    local _, _, _, _, _, classID = GetItemInfoInstant(entry)
    if classID == ITEM_CLASS_RECIPE then
        local usable = C_Item.IsUsableItem(entry)
        unusable = not usable
        _canUseCache[entry] = unusable
        return unusable
    end

    if IsEquippableItem(entry) or C_Item.GetItemSpell(entry) then
        -- Only use a tooltip from the real bag slot or real item link; both carry
        -- bonus IDs, which set the item's true required level. A bare itemID lacks
        -- those and can read the wrong level requirement either way.
        local tipText, reliable
        if bagID and slot then
            tipText = C_TooltipInfo.GetBagItem(bagID, slot)
            reliable = true
        elseif itemLink then
            tipText = C_TooltipInfo.GetHyperlink(itemLink)
            reliable = true
        end
        if tipText and tipText.lines then
            for _, row in ipairs(tipText.lines) do
                local lc = row.leftColor
                -- Tolerance, not exact equality: rounding can put red just under r=1.
                if
                    lc
                    and lc.r > 0.9
                    and lc.g < 0.2
                    and lc.b < 0.2
                    and row.leftText ~= ITEM_SCRAPABLE_NOT
                    and row.leftText ~= CANNOT_UNEQUIP_COMBAT
                    and row.leftText ~= ITEM_DISENCHANT_NOT_DISENCHANTABLE
                then
                    unusable = true
                    break
                end
                local rc = row.rightColor
                if rc and rc.r > 0.9 and rc.g < 0.2 and rc.b < 0.2 then
                    unusable = true
                    break
                end
            end
        end
        if not reliable then
            -- No bag slot or link yet, so don't cache a guess. A later call with
            -- real data will compute and cache the right answer.
            return unusable
        end
    end
    _canUseCache[entry] = unusable
    return unusable
end
CludesUI._BagsItemUnusable = BagsItemUnusable -- local CUI alias is declared further down
do
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_LEVEL_UP")
    frame:RegisterEvent("PLAYER_LEVEL_CHANGED")
    frame:SetScript("OnEvent", function()
        wipe(_canUseCache)
    end)
end
-- WoW Forever: the player's bags (1-4) that hold one kind of item only --
-- quivers, ammo pouches, soul, herb and enchanting bags, by their non-zero bag
-- family. Like the reagent bag they get their own category and sections and
-- stay out of Main Bags, the header count, OneBag's sort, Auto Split and drop
-- placement. nil on retail or with none equipped; the next call reuses the
-- set, so read it right away.
do
    local special = {}
    function mod.SpecialBags()
        if not CludesUI.IS_FOREVER then
            return nil
        end
        wipe(special)
        local any = false
        for bag = 1, 4 do
            local _, family = C_Container.GetContainerNumFreeSlots(bag)
            if family and family ~= 0 then
                special[bag] = true
                any = true
            end
        end
        return any and special or nil
    end

    -- Auto Split's target bags for a stack in bag, in order: the reagent bag
    -- and a special bag split into themselves first, and no other bag's stack
    -- goes into a special bag.
    function mod.SplitTargetBags(bag)
        local sp = mod.SpecialBags()
        if not sp then
            return bag == 5 and { 5, 0, 1, 2, 3, 4 } or { 0, 1, 2, 3, 4 }
        end
        local t = (sp[bag] or bag == 5) and { bag } or {}
        for b = 0, 4 do
            if not sp[b] then
                t[#t + 1] = b
            end
        end
        return t
    end
end
-- Weak-keyed bank-deposit routing state: custom keys written onto a ContainerFrameItemButtonTemplate
-- in PreClick taint the secure execution chain -> UseContainerItem() ADDON_ACTION_FORBIDDEN.
local _bankRouted = setmetatable({}, { __mode = "k" })

local CUI = CludesUI
-- Profile access helper (DB created in CUI_Bags_Options.lua, loaded first per TOC)
local _emptyP = {}
local function BP()
    return (CUI._bagsDB and CUI._bagsDB.profile) or _emptyP
end

-- Uninstall CUI: Sort to Bottom flips Blizzard's own sort direction, so the
-- player's is handed back, as turning the option off does.
CUI.OnUninstall(function()
    local profile = BP()
    if profile.bagSortToBottom and profile.bagSortBlizzRTLWas ~= nil then
        C_Container.SetSortBagsRightToLeft(profile.bagSortBlizzRTLWas)
    end
end)

-- Windows of the Auto Open / Auto Close Bags dropdowns. frame: Blizzard's name.
do
    local windows = {
        { key = "merchant", label = "Merchant", frame = "MerchantFrame" },
        { key = "mail", label = "Mailbox", frame = "MailFrame" },
        { key = "bank", label = "Bank", frame = "BankFrame" },
        { key = "auction", label = "Auction House", frame = "AuctionHouseFrame" },
    }
    if not CUI.IS_FOREVER then
        windows[#windows + 1] = { key = "scrapper", label = "Scrapper", frame = "ScrappingMachineFrame" }
        windows[#windows + 1] =
            { key = "itemInteraction", label = "Item Interaction", frame = "ItemInteractionFrame" }
        windows[#windows + 1] = { key = "azerite", label = "Azerite Essences", frame = "AzeriteEssenceUI" }
    end
    mod.BAG_AUTO_WINDOWS = windows

    local keyByName = {}
    for _, wid in ipairs(windows) do
        keyByName[wid.frame] = wid.key
    end
    -- nil for a window not listed
    function mod.BagAutoWindowKey(widget)
        local name = widget and widget:GetName()
        return name and keyByName[name]
    end
    -- setting: bagAutoOpenWindows or bagAutoCloseWindows, which hold false for an
    -- unselected window. A window not listed is always on.
    function mod.BagAutoWindowOn(setting, key)
        local tbl = BP()[setting]
        return not (key and tbl and tbl[key] == false)
    end
end

-- Frame Strata: the layer of the bags and the bank. Unset reads the retired
-- Allow Windows Over Bags toggle (off = High), so its choice carries over.
function mod.BagFrameStrata()
    local profile = BP()
    return profile.bagFrameStrata or (profile.bagAllowWindowsOverBags == false and "HIGH" or "MEDIUM")
end

local layerUpdateFrame = CreateFrame("Frame")
function CUI_Bags:ApplyWindowLayering()
    -- The bank's purchase buttons are secure, so defer layer changes in combat.
    if InCombatLockdown() then
        layerUpdateFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    layerUpdateFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
    local strata = mod.BagFrameStrata()
    self:SetFrameStrata(strata)
    -- High starts above that layer's other windows, as the retired toggle's
    -- off state did; every other layer starts at its bottom
    self:SetFrameLevel(strata == "HIGH" and 100 or 1)
    CUI_BagsWindow:SetFrameStrata(strata)
    CUI_BagsReagent:SetFrameStrata(strata)
    local scrollFrame = self._scrollFrame
    if scrollFrame and not self._assignSelectMode and not self._pinSelectMode then
        scrollFrame:SetFrameStrata(strata)
    end
    local bank = _G.CUI_BankFrame
    if bank and bank.ApplyWindowLayering then
        bank:ApplyWindowLayering()
    end
    self:RepinIconLevels()
end

-- Item buttons hold fixed levels (ns.PinItemButton): re-pin them after anything that
-- can move a window's level, the layering above and every Raise
function CUI_Bags:RepinIconLevels()
    local Inner = mod._bagsInternals
    mod.PinItemPool(Inner.itemSlots, self, "_slotPinLevel")
    mod.PinItemPool(Inner.reagentSlots, CUI_BagsReagent, "_slotPinLevel")
    mod.ResyncListRowLevels()
end
layerUpdateFrame:SetScript("OnEvent", function()
    CUI_Bags:ApplyWindowLayering()
end)

-- Tracked currencies are PER CHARACTER: their input feed (Blizzard's currency
-- tab via the TokenFrame.OnTokenWatchChanged sync below) is per-character, so
-- a shared store can only bleed across characters. Stored at the CludesUIDB
-- ROOT beside the module's other per-character data (goldLedger,
-- bagPinnedByChar, bagItemAssignments), NEVER in the bag profile:
-- ApplyProfileData wipes db.profile wholesale on import (would erase every
-- character's currencies), and profile exports must not ship a character
-- roster (the PRIVATE_ADDON_KEYS leak class).
local _bagsCharKey -- session-constant; UpdateCurrencyDisplays is a render path
local function BagsCharKey()
    if not _bagsCharKey then
        -- nil too early; do not cache a stub
        _bagsCharKey = CludesUI.CharKey(" - ", CludesUIDB and CludesUIDB.bagCurrencyByChar)
    end
    return _bagsCharKey
end

-- The per-character order table, seeded on this character's first use.
-- Returns nil only when the DB or the player identity is not up yet (callers
-- already handle that).
local function CurrencyOrder()
    if not CludesUIDB then
        return nil
    end
    local key = BagsCharKey()
    if not key then
        return nil
    end
    local byChar = CludesUIDB.bagCurrencyByChar
    if type(byChar) ~= "table" then
        byChar = {}
        CludesUIDB.bagCurrencyByChar = byChar
    end
    local tbl = byChar[key]
    if type(tbl) ~= "table" then
        tbl = {}
        -- Seed once per character from the legacy shared profile table. The
        -- legacy table is deliberately never deleted: a per-character
        -- migration is never a one-shot (a character that has not logged in
        -- yet still seeds from it later), and nothing writes it any more.
        local legacy = BP().currencyOrder
        if type(legacy) == "table" then
            for cID, sequence in pairs(legacy) do
                if type(sequence) == "number" then
                    tbl[cID] = sequence
                end
            end
        end
        byChar[key] = tbl
    end
    return tbl
end
CUI._BagsCurrencyOrder = CurrencyOrder

-- The pin table in use. Each character has its own (Pins per Character, on
-- unless CludesUIDB.bagPinsPerCharacter is false): its table in
-- CludesUIDB.bagPinnedByChar, by BagsCharKey. A character reads the shared
-- pins (bagPinnedItems) until its first pin or unpin, which copies them into
-- its own table; after that the shared pins are neither read nor written for
-- it. With the option off every character reads and writes the shared pins,
-- and the copies stay as they are for when it is turned on again.
-- create: a pin action is about to write. nil then means there is no table
-- to write (the character's identity is not readable yet): callers skip.
local function PinnedItems(create)
    local saved = CludesUIDB
    if not saved then
        return nil
    end
    if saved.bagPinsPerCharacter == false then
        if create and not saved.bagPinnedItems then
            saved.bagPinnedItems = {}
        end
        return saved.bagPinnedItems
    end
    local key = BagsCharKey()
    local byChar = saved.bagPinnedByChar
    local own = key and type(byChar) == "table" and byChar[key]
    if type(own) == "table" then
        return own
    end
    if not create then
        return saved.bagPinnedItems
    end
    if not key then
        return nil
    end
    own = {}
    local shared = saved.bagPinnedItems
    if type(shared) == "table" then
        for key, val in pairs(shared) do
            own[key] = val
        end
    end
    if type(byChar) ~= "table" then
        byChar = {}
        saved.bagPinnedByChar = byChar
    end
    byChar[key] = own
    return own
end
mod.PinnedItems = PinnedItems

-- Default bag-type view ("all"|"onebag"|"multibag"), falling back to legacy
-- bagDefaultOneBag bool (imports converted in ApplyProfileData before DeepMergeDefaults masks it); exposed on CUI so bank file matches.
local function GetDefaultBagType()
    local val = BP().bagDefaultBagType
    if val == "all" or val == "onebag" or val == "multibag" then
        return val
    end
    return BP().bagDefaultOneBag and "onebag" or "all"
end
CUI._GetBagDefaultType = GetDefaultBagType

-- Bag display mode ("grid" | "list" | "compact"), latched on the first read
-- after the profile loads: switching needs a reload, so only one mode ever
-- builds frames in a session. nil = profile not loaded yet (nothing latched).
-- Any other saved value reads as "grid".
local _listMode
function CUI_Bags.IsListMode()
    if _listMode == nil then
        if not CUI.Lite.IsDBReady() then
            return nil
        end
        local mode = BP().bagDisplayMode
        _listMode = mode == "list"
        CUI_Bags._compactMode = mode == "compact"
        CUI_Bags._modernMode = mode == "modern"
    end
    return _listMode
end
-- Modern display (CUI_Bags_Modern.lua): the Grid display with category chips
-- in place of the sidebar, on IsListMode's latch
function CUI_Bags.IsModernMode()
    if CUI_Bags.IsListMode() == nil then
        return nil
    end
    return CUI_Bags._modernMode
end
-- Compact display (CludesUIBags_Compact.lua), on IsListMode's latch
function CUI_Bags.IsCompactMode()
    if CUI_Bags.IsListMode() == nil then
        return nil
    end
    return CUI_Bags._compactMode
end
-- Auto-Size to Fit: not offered with the List display (its rows take the
-- grip-set width), so a value saved under another display stays off there
function CUI_Bags.AutoSizeOn()
    return BP().bagAutoSize == true and not CUI_Bags.IsListMode()
end

local function ApplyBagScale()
    local s = BP().bagScale or 1
    if CUI_Bags then
        CUI_Bags:SetScale(s)
    end
    if CUI_BagsReagent then
        CUI_BagsReagent:SetScale(s)
    end
    if CUI_BagsWindow then
        CUI_BagsWindow:SetScale(s)
    end
end

-- Locale-safe gear detection: GetItemInfo type strings are localized ("Armor" only on enUS), so use GetItemInfoInstant's numeric classID.
local ITEM_CLASS_WEAPON = Enum.ItemClass.Weapon -- 2
local ITEM_CLASS_ARMOR = Enum.ItemClass.Armor -- 4
local function IsGearItem(itemLink)
    if not itemLink then
        return false
    end
    local _, _, _, _, _, classID = GetItemInfoInstant(itemLink)
    return classID == ITEM_CLASS_WEAPON or classID == ITEM_CLASS_ARMOR
end
-- Pin identity: bare itemID can't distinguish two different upgrade tracks
-- (e.g. Mythic vs Hero) of the same base item -- those share one itemID and
-- only differ in the bonus IDs encoded on the item LINK. The RAW link is not
-- a safe persistent key either: it also embeds linkLevel, specializationID,
-- enchant and gem fields, so the same item's link drifts on level-up, spec
-- swap or re-gem -- a raw-link pin would silently stop matching AND leak its
-- stale entry in the account-global store forever (unpin only removes the
-- current key). The pin key is therefore itemID + the bonus ID list: bonus
-- IDs carry the upgrade track (the exact thing being distinguished) and hold
-- steady across spec, level, enchants and gems. Cached per link string, the
-- same shape as the sort cache -- IsItemPinned runs per item per refresh.
-- itemID stays supported read-only as a legacy fallback: entries written
-- before the link-era fix are itemID-keyed and still match every track, same
-- as before, until the middle-click self-heal clears them.
local pinKeyCache = {}
local function NormalizePinKey(itemLink, itemId)
    if type(itemLink) ~= "string" then
        return itemId
    end
    local cached = pinKeyCache[itemLink]
    if cached then
        return cached
    end
    local key
    local payload = itemLink:match("|Hitem:([^|]*)|h")
    if payload then
        -- Split keeping empty fields. After "item:": 1 itemID, 2 enchant,
        -- 3-6 gems, 7 suffix, 8 uniqueID, 9 linkLevel, 10 specID,
        -- 11 modifiersMask, 12 itemContext, 13 numBonusIDs, 14.. bonusIDs.
        local frame = {}
        for field in (payload .. ":"):gmatch("([^:]*):") do
            frame[#frame + 1] = field
        end
        local ident = frame[1]
        if ident and ident ~= "" then
            local num = tonumber(frame[13]) or 0
            key = "p" .. ident
            for index = 1, num do
                key = key .. ":" .. (frame[13 + index] or "")
            end
        end
    end
    key = key or itemId
    if key then
        pinKeyCache[itemLink] = key
    end
    return key
end
local function IsItemPinned(pinnedSet, itemLink, itemId)
    if not pinnedSet then
        return nil
    end
    local nk = itemLink and NormalizePinKey(itemLink, nil)
    return (nk and pinnedSet[nk]) or (itemId and pinnedSet[itemId])
end
mod.IsItemPinned = IsItemPinned
local function GetItemLevelAtLocation(loc, itemLink)
    if loc and loc:IsValid() and C_Item.DoesItemExist(loc) then
        local level = C_Item.GetCurrentItemLevel(loc)
        if level and level > 0 then
            return level
        end
    end
    return itemLink and C_Item.GetDetailedItemLevelInfo(itemLink) or nil
end
local function GetFont()
    return CUI.GetFontPath("bags")
end
local function SetBagFont(fontStr, size)
    CludesUI.PrimeFontShadow(fontStr, true)
    fontStr:SetFont(GetFont(), size, CUI.GetFontOutlineFlag("bags"))
end
local function GetAccentRGB()
    if CUI.GetAccentColor then
        return CUI.GetAccentColor()
    end
    return 0.298, 0.788, 0.941
end

local function GetColumns()
    -- Auto-size overrides the user's column count with one that keeps the base aspect ratio while fitting the active tab.
    if CUI_Bags and CUI_Bags._asCols and CUI_Bags.AutoSizeOn() then
        return CUI_Bags._asCols
    end
    return BP().bagColumns or 12
end
local function GetCatTitleSize()
    return BP().bagCatTitleSize or 11
end

-- Abbreviate a dungeon name to initials (skipping connector words); Cyrillic entries cover clients where GetMapUIInfo returns translated names.
local _dungeonAbbrCache = {}
local _skipWords = {
    ["of"] = true,
    ["the"] = true,
    ["a"] = true,
    ["an"] = true,
    ["из"] = true,
    ["за"] = true,
    ["в"] = true,
    ["на"] = true,
    ["и"] = true,
    ["под"] = true,
    ["с"] = true,
}
local function AbbrevDungeon(mapID)
    local cached = _dungeonAbbrCache[mapID]
    if cached then
        return cached
    end
    local name = C_ChallengeMode and C_ChallengeMode.GetMapUIInfo and C_ChallengeMode.GetMapUIInfo(mapID)
    if not name or name == "" then
        return ""
    end
    local abbr = ""
    -- Split on whitespace AND hyphens so "Nexus-Point Xenas" abbreviates to NPX.
    for word in name:gmatch("[^%s%-]+") do
        if not _skipWords[word:lower()] then
            -- First whole UTF-8 char (sub(1,1) would split Cyrillic; same for ASCII)
            local wordUpper = word:upper()
            local firstChar = wordUpper:match("^[%z\1-\127\194-\244][\128-\191]*")
            abbr = abbr .. (firstChar or "")
        end
    end
    -- Locale files may register CludesUI._dungeonAbbrevOverride (plain data) for locale-specific cuts; applied here at the single render source, not via hook.
    local shade = CludesUI and CludesUI._dungeonAbbrevOverride
    if shade and shade[abbr] then
        abbr = shade[abbr]
    end
    _dungeonAbbrCache[mapID] = abbr
    return abbr
end

-- Main-chunk locals of this file the CUI_Bags_*.lua files re-import by name;
-- each of them adds what the files behind it need.
-- categoryIndexSetters and the lists beside it: every file that reads one of
-- these values keeps its own copy and adds a setter here; each place that
-- assigns it writes through the Set<Name> function built below, which runs
-- them all.
-- broken: true while an CUI_Bags_*.lua file loads; a file that fails leaves
-- it set, and the files behind it return at their first lines.
CludesUI.NewInternals(mod, "_bagsInternals", {
    _bankRouted = _bankRouted,
    AbbrevDungeon = AbbrevDungeon,
    ApplyBagScale = ApplyBagScale,
    BagsItemUnusable = BagsItemUnusable,
    BP = BP,
    CurrencyOrder = CurrencyOrder,
    GetAccentRGB = GetAccentRGB,
    GetCatTitleSize = GetCatTitleSize,
    GetColumns = GetColumns,
    GetDefaultBagType = GetDefaultBagType,
    GetFont = GetFont,
    GetItemLevelAtLocation = GetItemLevelAtLocation,
    IsGearItem = IsGearItem,
    IsItemPinned = IsItemPinned,
    NormalizePinKey = NormalizePinKey,
    PinnedItems = PinnedItems,
    SetBagFont = SetBagFont,
    SLOT_SIZE = SLOT_SIZE,
    SPACING = SPACING,
    categoryIndexSetters = {},
    groupNameSetters = {},
    gearCatSetSetters = {},
    anyItemPanelOpenSetters = {},
    paintedPanelOpenSetters = {},
    slotMetricSetters = {},
}, {
    SetSelectedCategoryIndex = "categoryIndexSetters",
    SetSelectedGroupName = "groupNameSetters",
    SetGearCatSet = "gearCatSetSetters",
    SetAnyItemPanelOpen = "anyItemPanelOpenSetters",
    SetPaintedPanelOpen = "paintedPanelOpenSetters",
    SetSlotMetrics = "slotMetricSetters",
})

-- slot size and spacing come from the profile. each file that lays out slots
-- keeps its own copy (OnSlotMetrics gets { size, spacing }), and frames made
-- through SizeSlot get resized on a change
local slotFrames = setmetatable({}, { __mode = "k" })
function mod.SizeSlot(frame)
    slotFrames[frame] = true
    frame:SetSize(SLOT_SIZE, SLOT_SIZE)
end
function mod.OnSlotMetrics(func)
    local entries = mod._bagsInternals.slotMetricSetters
    entries[#entries + 1] = func
end
-- both refreshes call this first; a change made in combat waits for the next one
function mod.ApplySlotMetrics()
    local profile = BP()
    -- the sliders' ranges: a hand-edited or imported 0 would divide by zero
    local size = math.min(math.max(tonumber(profile.bagSlotSize) or 34, 24), 56)
    local gap = math.min(math.max(tonumber(profile.bagSlotSpacing) or 4, 0), 12)
    if (size == SLOT_SIZE and gap == SPACING) or InCombatLockdown() then
        return
    end
    SLOT_SIZE, SPACING = size, gap
    mod.SLOT_SIZE, mod.SPACING = size, gap
    for frame in pairs(slotFrames) do
        frame:SetSize(size, size)
    end
    mod._bagsInternals.SetSlotMetrics({ size, gap })
end
