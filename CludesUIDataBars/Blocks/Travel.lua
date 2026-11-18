if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-- Blocks\Travel.lua
-- Travel block factory (hearthstones and M+ teleports).

local ADDON_NAME, mod = ...
local L = mod.L
local K = mod.BlockKit

-- Upvalues
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local C_Timer = C_Timer
local GetTime = GetTime
local ipairs = ipairs
local type = type
local pcall = pcall
local floor = math.floor
local max = math.max
local min = math.min
local mrandom = math.random

local ICON_GAP = K.ICON_GAP
local CONTENT_BASE = K.CONTENT_BASE
local InstKey = K.InstKey
local MakeEventFrame = K.MakeEventFrame
local RegisterInstEvents = K.RegisterInstEvents
local UnregisterInstEvents = K.UnregisterInstEvents
local HBudget = K.HBudget
local VSlotW = K.VSlotW
local MaybeRelayout = K.MaybeRelayout
local AttachTextOffset = K.AttachTextOffset
local BlockColorOf = K.BlockColorOf
local IconColorOf = K.IconColorOf
local ParkSecureFrame = K.ParkSecureFrame

-------------------------------------------------------------------------------
--  TRAVEL (Hearthstone + M+ teleports; SECURE hearth button)
-------------------------------------------------------------------------------
-- Static hearthstone pool (all expansions) shared by every instance.
local HEARTHSTONE_IDS = {
    -- Midnight
    263933,
    265100,
    263489,
    264367,
    -- The War Within
    257736,
    246565,
    245970,
    228940,
    212337,
    209035,
    208704,
    210455,
    -- Dragonflight
    236687,
    235016,
    200630,
    193588,
    -- Shadowlands
    190196,
    190237,
    188952,
    184353,
    182773,
    180290,
    183716,
    172179,
    -- Seasonal / Holiday
    163045,
    162973,
    165669,
    165670,
    165802,
    166746,
    166747,
    -- Legacy / Misc
    6948,
    64488,
    28585,
    93672,
    142542,
    142298,
    168907,
    54452,
}

-- Standalone travel-cooldown entries listed under the Hearthstone tooltip line
-- when owned. Each has its OWN cooldown, separate from the shared hearthstone
-- one -- why Astral Recall is here, not the pool above, despite also returning
-- to the bind point. Spell IDs: Dalaran 222695, Arcantina 1255801, Garrison 171253.
local TRAVEL_EXTRAS = {
    140192, -- Dalaran Hearthstone
    253629, -- Key to the Arcantina
    110560, -- Garrison Hearthstone
    556, -- Astral Recall (a spell, hence the per-entry kind probe below)
    128353, -- Admiral's Compass (a plain item, not a toy)
    193753, -- Dreamwalk (druid)
    18960, -- Teleport: Moonglade (druid)
    50977, -- Death Gate (death knight)
    193759, -- Teleport: Hall of the Guardian (mage)
    126892, -- Zen Pilgrimage (monk)
    1238686, -- Rootwalking (Haranir)
}
local TRAVEL_EXTRA_SET = {}
for _, ident in ipairs(TRAVEL_EXTRAS) do
    TRAVEL_EXTRA_SET[ident] = true
end
-- Entries that are not toys.
local TRAVEL_EXTRA_KIND = {
    [556] = "spell",
    [193753] = "spell",
    [18960] = "spell",
    [50977] = "spell",
    [193759] = "spell",
    [126892] = "spell",
    [1238686] = "spell",
    [128353] = "item",
}
-- Hidden while the player knows the replacement.
local TRAVEL_EXTRA_SUPERSEDED_BY = { [18960] = 193753 }

-- Hearthstones share one cooldown, so polling a single owned one suffices.
-- Engine-level cache: the underlying cooldown is shared game-wide.
local travelPrimaryHearthId

local function TravelIsUsable(ident)
    if not ident then
        return false
    end
    -- A race-restricted hearthstone toy counts only on the races that can use it.
    if not CludesUI.CanUseHearthToy(ident) then
        return false
    end
    if PlayerHasToy(ident) then
        return true
    end
    if IsPlayerSpell(ident) then
        return true
    end
    return (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(ident) or 0) > 0
end

local function TravelExtraKind(ident)
    local sup = TRAVEL_EXTRA_SUPERSEDED_BY[ident]
    if sup and IsPlayerSpell(sup) then
        return nil
    end
    local kind = TRAVEL_EXTRA_KIND[ident]
    if kind == "spell" then
        return IsPlayerSpell(ident) and kind or nil
    end
    if kind == "item" then
        return (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(ident) or 0) > 0 and kind or nil
    end
    return PlayerHasToy(ident) and "toy" or nil
end

-- nil until the game has cached the name.
local function TravelEntryName(ident)
    if TRAVEL_EXTRA_SET[ident] and TravelExtraKind(ident) == "spell" then
        local details = C_Spell.GetSpellInfo(ident)
        return details and details.name
    end
    if C_ToyBox and C_ToyBox.GetToyInfo then
        local _, tn = C_ToyBox.GetToyInfo(ident)
        if tn then
            return tn
        end
    end
    if C_Item and C_Item.GetItemNameByID then
        local num = C_Item.GetItemNameByID(ident)
        if num then
            return num
        end
    end
    return nil
end

-- Options-side exports.
mod.TravelHearthstoneIDs = HEARTHSTONE_IDS
mod.TravelIsUsable = TravelIsUsable
mod.TravelExtraIDs = TRAVEL_EXTRAS
mod.TravelExtraUsable = function(ident)
    return TravelExtraKind(ident) ~= nil
end
mod.TravelEntryName = TravelEntryName

-- Returns remaining, known. In restricted combat cooldown numbers are SECRET: comparing
-- or dead-reckoning them throws (type() still says "number"), so those report 0, false and
-- callers degrade -- tooltip "-" on gray rows, block tints as cooling, probe keeps ticking and self-corrects on a clean read.
local function TravelGetRemainingCooldown(ident, isSpell)
    local startTime, duration
    if isSpell then
        local details = C_Spell.GetSpellCooldown(ident)
        if details then
            startTime, duration = details.startTime, details.duration
        end
    else
        if C_Item and C_Item.GetItemCooldown then
            startTime, duration = C_Item.GetItemCooldown(ident)
        elseif C_Container and C_Container.GetItemCooldown then
            startTime, duration = C_Container.GetItemCooldown(ident)
        end
    end
    if issecretvalue(startTime) or issecretvalue(duration) then
        return 0, false
    end
    -- 2s or less is the global cooldown, which these APIs also report on travel items: read as ready.
    if type(startTime) == "number" and type(duration) == "number" and duration > 2 then
        return max(0, startTime + duration - GetTime()), true
    end
    return 0, true
end

-- Player housing: a "house:<guid>" click uses Blizzard's teleporthome secure action
-- (returnhome while a return trip is available). The house list arrives
-- asynchronously; its listener registers only while a click or the options page needs it.
local HOUSE_PREFIX = "house:"
local travelHouses
-- Bumped on every list arrival (ns.TravelHouseListGen): the options refill their menus on a change.
local travelHousesGen = 0
local houseWatchers = {}
local houseOptionsWaiting
local houseEv = CreateFrame("Frame")

local function TravelHousingAvailable()
    return not CludesUI.IS_FOREVER and C_Housing and C_Housing.GetPlayerOwnedHouses ~= nil
end

-- As the house favor bar: no request in a keystone or raid; world entry retries.
local function TravelHousingBlocked()
    if
        C_ChallengeMode
        and C_ChallengeMode.IsChallengeModeActive
        and C_ChallengeMode.IsChallengeModeActive()
    then
        return true
    end
    local inInst, instType = IsInInstance()
    return (inInst and instType == "raid") and true or false
end

local function TravelRequestHouses()
    if TravelHousingBlocked() then
        return
    end
    C_Housing.GetPlayerOwnedHouses()
end

local function TravelSyncHouseEvents()
    local watching = next(houseWatchers) ~= nil
    if watching or houseOptionsWaiting then
        houseEv:RegisterEvent("PLAYER_HOUSE_LIST_UPDATED")
    else
        houseEv:UnregisterEvent("PLAYER_HOUSE_LIST_UPDATED")
    end
    if watching then
        houseEv:RegisterEvent("PLAYER_ENTERING_WORLD")
    else
        houseEv:UnregisterEvent("PLAYER_ENTERING_WORLD")
    end
end

houseEv:SetScript("OnEvent", function(_, evt, houses)
    if evt == "PLAYER_ENTERING_WORLD" then
        TravelRequestHouses()
        return
    end
    travelHouses = type(houses) == "table" and houses or {}
    travelHousesGen = travelHousesGen + 1
    local onLoaded = houseOptionsWaiting
    houseOptionsWaiting = nil
    TravelSyncHouseEvents()
    for instance in next, houseWatchers do
        instance:OnHouseList()
    end
    if onLoaded then
        onLoaded()
    end
end)

local function TravelWatchHouses(instance, on)
    on = on and TravelHousingAvailable() or false
    if (houseWatchers[instance] == true) == on then
        return
    end
    houseWatchers[instance] = on or nil
    TravelSyncHouseEvents()
    if on and not travelHouses then
        TravelRequestHouses()
    end
end

function mod.TravelRequestHouseList(onLoaded)
    if travelHouses or houseOptionsWaiting or not TravelHousingAvailable() or TravelHousingBlocked() then
        return
    end
    houseOptionsWaiting = onLoaded
    TravelSyncHouseEvents()
    TravelRequestHouses()
end

local function TravelIsHouseChoice(choice)
    return type(choice) == "string" and choice:find(HOUSE_PREFIX, 1, true) == 1
end

local function TravelUsableHouse(hgt)
    return hgt
        and hgt.houseGUID
        and hgt.neighborhoodGUID
        and hgt.plotID
        and not issecretvalue(hgt.houseGUID)
        and not issecretvalue(hgt.neighborhoodGUID)
end

local function TravelFindHouse(choice)
    if not (travelHouses and TravelIsHouseChoice(choice)) then
        return nil
    end
    local unitGuid = choice:sub(#HOUSE_PREFIX + 1)
    for _, hgt in ipairs(travelHouses) do
        if TravelUsableHouse(hgt) and hgt.houseGUID == unitGuid then
            return hgt
        end
    end
    return nil
end

-- Skips the opaque placeholder name some clients report.
local function TravelHouseName(hgt)
    local num = hgt and hgt.houseName
    if num and not issecretvalue(num) and num ~= "" and not num:match("^Home%-opaque%-%d+$") then
        return num
    end
    return L["HOME"]
end

local function TravelCanReturnHome()
    local frame = C_HousingNeighborhood and C_HousingNeighborhood.CanReturnAfterVisitingHouse
    if not frame then
        return false
    end
    local success, can = pcall(frame)
    return success and can == true
end

-- Returns remaining, known; 2s or less is the global cooldown, read as ready.
local function TravelHouseCooldown()
    local details = C_Housing and C_Housing.GetVisitCooldownInfo and C_Housing.GetVisitCooldownInfo()
    if not details or not details.isEnabled then
        return 0, true
    end
    if issecretvalue(details.startTime) or issecretvalue(details.duration) then
        return 0, false
    end
    local rem = 0
    if (details.duration or 0) > 2 and (details.startTime or 0) > 0 then
        rem = max(0, details.startTime + details.duration - GetTime())
    end
    return rem, true
end

function mod.TravelHouseListGen()
    return travelHousesGen
end

-- Options-side: owned houses as { key = "house:<guid>", name = ... }.
function mod.TravelHouseChoices()
    local result = {}
    if travelHouses then
        for _, hgt in ipairs(travelHouses) do
            if TravelUsableHouse(hgt) then
                result[#result + 1] = { key = HOUSE_PREFIX .. hgt.houseGUID, name = TravelHouseName(hgt) }
            end
        end
    end
    return result
end

local _hearthList = {}
local _hearthListCount = 0
local function TravelGetAvailableHearthstones()
    _hearthListCount = 0
    for _, ident in ipairs(HEARTHSTONE_IDS) do
        if TravelIsUsable(ident) then
            _hearthListCount = _hearthListCount + 1
            _hearthList[_hearthListCount] = ident
        end
    end
    for index = _hearthListCount + 1, #_hearthList do
        _hearthList[index] = nil
    end
    return _hearthList
end

local function TravelBuildMacro(ident)
    if PlayerHasToy(ident) then
        return "/use item:" .. ident
    end
    if IsPlayerSpell(ident) then
        local details = C_Spell.GetSpellInfo(ident)
        if details and details.name then
            return "/cast " .. details.name
        end
    end
    return "/use item:" .. ident
end

local function TravelPickHearthstone(randomize)
    local entries = TravelGetAvailableHearthstones()
    if #entries == 0 then
        return nil
    end
    if randomize then
        return entries[mrandom(#entries)]
    end
    for _, ident in ipairs(entries) do
        if ident == 6948 then
            return ident
        end
    end
    return entries[1]
end

-- Per button (1 left, 2 right, 3 middle): "none", "random", "house:<guid>" or an id.
local function TravelClickChoice(dt, button)
    local c
    if button == 1 then
        c = dt.hsChoice
        if c == nil then
            c = dt.randomizeHs and "random" or 6948
        end
    elseif button == 2 then
        c = dt.hsChoiceRight
        if c == nil then
            c = "random"
        end
    else
        c = dt.hsChoiceMiddle
        if c == nil then
            c = "none"
        end
    end
    return c
end
mod.TravelClickChoice = TravelClickChoice

-- Id a choice fires now: nil for "none"; an entry the player lacks falls back to the hearthstone.
local function TravelResolveChoice(choice)
    if choice == "none" then
        return nil
    end
    if choice == "random" then
        return TravelPickHearthstone(true)
    end
    if TRAVEL_EXTRA_SET[choice] then
        if TravelExtraKind(choice) then
            return choice
        end
    elseif type(choice) == "number" and TravelIsUsable(choice) then
        return choice
    end
    return TravelPickHearthstone(false)
end

-- Negative-result cache: with NO usable hearthstone the 1s cooling probe would re-scan all
-- ~40 candidates every second forever. Ownership only changes via edges the block already
-- listens to (hearth bind, world entry, bag/spell changes), which clear this through ns.TravelInvalidateHearthCache.
local travelNoHearth
function mod.TravelInvalidateHearthCache()
    travelNoHearth = nil
    travelPrimaryHearthId = nil
end
local function TravelGetPrimaryCooldown()
    -- The cached id is trusted between ownership edges: re-validating per 1s probe costs a
    -- GetItemCount bag walk every second, and item loss always fires BAG_UPDATE_DELAYED
    -- (spells: SPELLS_CHANGED), which clears the cache via ns.TravelInvalidateHearthCache and forces a re-pick here.
    if not travelPrimaryHearthId then
        if travelNoHearth then
            return 0, true
        end
        travelPrimaryHearthId = TravelPickHearthstone(false)
        if not travelPrimaryHearthId then
            travelNoHearth = true
            return 0, true
        end
    end
    return TravelGetRemainingCooldown(travelPrimaryHearthId, false)
end

-- Show Other Characters (block setting altHearths, off by default): every
-- character's hearthstone, account-wide in CludesUIDB.travelHearths, keyed
-- by CludesUI.CharKey("-") (Name-Realm on retail, the character's GUID on
-- WoW Forever) = { name (with the surname on WoW Forever), class, bind,
-- readyAt }. readyAt is a time() stamp (0 = ready): item cooldowns keep
-- running while logged out, so an alt's row counts down from what it last
-- saved. A character saves itself on each
-- block refresh while the setting is on, but writes only when its bind or
-- ready time changed (the refresh runs every second while the tooltip or a
-- cooldown shows); a secret (combat) read saves nothing.
local function TravelHearthStore()
    local saved = _G.CludesUIDB
    if type(saved) ~= "table" then
        return nil
    end
    local storage = saved.travelHearths
    if type(storage) ~= "table" then
        storage = {}
        saved.travelHearths = storage
    end
    return storage
end

-- This character's key and full name, read once a session, and what it last
-- wrote (the first save of a session always writes).
local _myHearthKey, _myHearthName, _savedBind, _savedReadyAt
local function TravelSaveMyHearth()
    local storage = TravelHearthStore()
    if not storage then
        return
    end
    if not _myHearthKey then
        _myHearthKey = CludesUI.CharKey("-", storage)
        if not _myHearthKey then
            return
        end
        -- The full name whatever the show-surname preference: two WoW Forever
        -- characters can share a first name.
        local name, surname = (UnitNameUnmodified or UnitName)("player")
        _myHearthName = CludesUI.WithSurname(name, surname, true)
    end
    local cd, known = TravelGetPrimaryCooldown()
    if not known then
        return
    end
    local bind = GetBindLocation()
    local readyAt = (cd > 0) and (time() + cd) or 0
    local e = storage[_myHearthKey]
    -- Unchanged: same bind, same ready time give or take a second of drift.
    if
        type(e) == "table"
        and bind == _savedBind
        and _savedReadyAt
        and math.abs(readyAt - _savedReadyAt) <= 1
    then
        return
    end
    if type(e) ~= "table" then
        e = {}
        storage[_myHearthKey] = e
    end
    local _, class = UnitClass("player")
    e.name = _myHearthName
    e.class = class
    e.bind = bind
    e.readyAt = readyAt
    _savedBind, _savedReadyAt = bind, readyAt
end

-- The other characters' rows, sorted by name (reused buffers: the open tooltip
-- refreshes every second). Ctrl + Alt + Left Click on a row stops following
-- that character, as the Gold block's Remove Character; onRemoved closes the
-- tip. Returns the number of rows.
local _altBuf, _altKeyOf = {}, {}
local function TravelAltSort(a, z)
    return (a.name or "") < (z.name or "")
end
local function TravelAddAltRows(ar, ag, ab, onRemoved)
    local storage = TravelHearthStore()
    if not storage then
        return 0
    end
    local mine = _myHearthKey or CludesUI.CharKey("-")
    local num = 0
    wipe(_altKeyOf)
    for key, e in pairs(storage) do
        if key ~= mine and type(e) == "table" and e.name then
            num = num + 1
            _altBuf[num] = e
            _altKeyOf[e] = key
        end
    end
    for index = num + 1, #_altBuf do
        _altBuf[index] = nil
    end
    if num == 0 then
        return 0
    end
    table.sort(_altBuf, TravelAltSort)
    mod.Tip_AddLine(" ")
    mod.Tip_AddLine(L["OTHER_CHARACTERS"], ar, ag, ab)
    local nowTime = time()
    for index = 1, num do
        local e = _altBuf[index]
        local cc = e.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[e.class]
        local cr, cg, callback = 1, 1, 1
        if cc then
            cr, cg, callback = cc.r, cc.g, cc.b
        end
        local rem = (e.readyAt or 0) - nowTime
        local cdStr, rr, rg, rb = L["READY"], 0, 1, 0
        if rem > 0 then
            cdStr = mod.FormatCooldown(rem) or L["READY"]
            rr, rg, rb = 0.5, 0.5, 0.5
        end
        local key = _altKeyOf[e]
        mod.Tip_AddClickable(e.name .. " (" .. (e.bind or "?") .. ")", cdStr, function(mouseButton)
            if mouseButton ~= "LeftButton" then
                return
            end
            if not (IsControlKeyDown() and IsAltKeyDown()) then
                return
            end
            local s = TravelHearthStore()
            if s then
                s[key] = nil
            end
            if onRemoved then
                onRemoved()
            end
        end, cr, cg, callback, rr, rg, rb)
    end
    return num
end

-- "smart": the cooldown while cooling, else the destination.
local TEXT_KEYS = { "textLeft", "textRight", "textMiddle" }
local function TravelClickTextMode(dt, button)
    local m = dt[TEXT_KEYS[button]]
    if m ~= nil then
        return m
    end
    return button == 1 and "location" or "none"
end
mod.TravelClickTextMode = TravelClickTextMode

local function TravelAnyTimerText(dt)
    for button = 1, 3 do
        local m = TravelClickTextMode(dt, button)
        if m == "smart" or m == "both" or m == "cooldown" then
            return true
        end
    end
    return false
end

local TRAVEL_DESTINATIONS = {
    [140192] = { global = "DUNGEON_FLOOR_DALARANCITY1" },
    [253629] = { key = "TRAVEL_ARCANTINA" },
    [110560] = { global = "GARRISON_LOCATION_TOOLTIP" },
    [193753] = { global = "ORDER_HALL_DRUID" },
    [18960] = { key = "TRAVEL_MOONGLADE" },
    [50977] = { global = "ORDER_HALL_DEATHKNIGHT" },
    [193759] = { global = "ORDER_HALL_MAGE" },
    [126892] = { global = "ORDER_HALL_MONK" },
}

local HOUSE_ZONE_LABELS = { [2352] = "HOME_ALLIANCE", [2351] = "HOME_HORDE" } -- Founder's Point, Razorwind Shores

-- Bar destination of a choice; nil means the bind location.
local function TravelBarDestination(choice, tagHouses)
    local hgt = TravelFindHouse(choice)
    if hgt then
        if not tagHouses then
            return CludesUI.L(L["HOME"])
        end
        local frame = C_Housing.GetUIMapIDForNeighborhood
        local success, mapID = false, nil
        if frame then
            success, mapID = pcall(frame, hgt.neighborhoodGUID)
        end
        local key = success and HOUSE_ZONE_LABELS[mapID]
        if key then
            return CludesUI.L(L[key])
        end
        return CludesUI.L(TravelHouseName(hgt))
    end
    if TRAVEL_EXTRA_SET[choice] and TravelExtraKind(choice) then
        local skinData = TRAVEL_DESTINATIONS[choice]
        local name = skinData and ((skinData.global and _G[skinData.global]) or (skinData.key and CludesUI.L(L[skinData.key])))
        if name then
            return name
        end
        if choice ~= 556 then
            return TravelEntryName(choice)
        end -- Astral Recall: the bind point
    end
    return nil
end

local function TravelChoiceCooldown(choice)
    if TravelFindHouse(choice) then
        if TravelCanReturnHome() then
            return 0, true
        end
        return TravelHouseCooldown()
    end
    if TRAVEL_EXTRA_SET[choice] then
        local kind = TravelExtraKind(choice)
        if kind then
            return TravelGetRemainingCooldown(choice, kind == "spell")
        end
    end
    return TravelGetPrimaryCooldown()
end

local function TravelShownCooldown(dt, button)
    local choice = TravelClickChoice(dt, button)
    if choice == "none" or TravelClickTextMode(dt, button) == "none" then
        return nil
    end
    return TravelChoiceCooldown(choice)
end

-- One bit per shown click that is cooling (unknown counts); the left click when none shows.
local CLICK_BITS = { 1, 2, 4 }
local function TravelCoolingMask(dt)
    local mask, shownMask = 0, 0
    for button = 1, 3 do
        local cd, known = TravelShownCooldown(dt, button)
        if cd then
            shownMask = shownMask + CLICK_BITS[button]
            if not known or cd > 0 then
                mask = mask + CLICK_BITS[button]
            end
        end
    end
    if shownMask == 0 then
        local cd, known = TravelChoiceCooldown(TravelClickChoice(dt, 1))
        if not known or cd > 0 then
            mask = 1
        end
    end
    return mask
end

-- Cooling parts are wrapped in gray unless plain. Returns text, timerShown
-- (a shown timer is counting down), coolingMask, iconDim.
local _textParts, _textRaw = {}, {}
local function TravelBarText(dt, bind, plain)
    local firstHouse, tagHouses = nil, false
    for button = 1, 3 do
        if TravelClickTextMode(dt, button) ~= "none" then
            local hgt = TravelFindHouse(TravelClickChoice(dt, button))
            if hgt then
                if not firstHouse then
                    firstHouse = hgt.houseGUID
                elseif hgt.houseGUID ~= firstHouse then
                    tagHouses = true
                end
            end
        end
    end
    local num, timer, mask, shownMask = 0, false, 0, 0
    for button = 1, 3 do
        local cd, known = TravelShownCooldown(dt, button)
        if cd then
            local mode = TravelClickTextMode(dt, button)
            local choice = TravelClickChoice(dt, button)
            local cooling = not known or cd > 0
            shownMask = shownMask + CLICK_BITS[button]
            if cooling then
                mask = mask + CLICK_BITS[button]
            end
            local dest = TravelBarDestination(choice, tagHouses) or bind
            local part = dest
            if mode ~= "location" then
                local cdStr = known and mod.FormatCooldown(cd) or nil
                if cdStr then
                    timer = true
                end
                if mode == "smart" then
                    part = cdStr or dest
                elseif mode == "both" then
                    part = cdStr and (dest .. " " .. cdStr) or dest
                else
                    part = cdStr or (known and CludesUI.L(L["READY"]) or "-")
                end
            end
            local dup = false
            for index = 1, num do
                if _textRaw[index] == part then
                    dup = true
                    break
                end
            end
            if not dup then
                num = num + 1
                _textRaw[num] = part
                _textParts[num] = (cooling and not plain) and ("|cff808080" .. part .. "|r") or part
            end
        end
    end
    for index = num + 1, #_textParts do
        _textParts[index] = nil
        _textRaw[index] = nil
    end
    local iconDim
    if shownMask == 0 then
        local cd, known = TravelChoiceCooldown(TravelClickChoice(dt, 1))
        iconDim = not known or cd > 0
        mask = iconDim and 1 or 0
    else
        iconDim = mask == shownMask
    end
    if num == 0 then
        return "", timer, mask, iconDim
    end
    return table.concat(_textParts, " / ", 1, num), timer, mask, iconDim
end

local function TravelResolveMythicId(idOrTable)
    if type(idOrTable) == "table" then
        for _, ident in ipairs(idOrTable) do
            if IsPlayerSpell(ident) then
                return ident
            end
        end
        return nil
    end
    if IsPlayerSpell(idOrTable) then
        return idOrTable
    end
    return nil
end

-- Season M+ teleports from the shared season list (one update per season).
local SEASON_TELEPORTS = {}
for _, e in ipairs(CludesUI.SEASON_PORTALS) do
    local ids = e.spellID
    if e.altSpellIDs then
        ids = { e.spellID }
        for _, a in ipairs(e.altSpellIDs) do
            ids[#ids + 1] = a
        end
    end
    SEASON_TELEPORTS[#SEASON_TELEPORTS + 1] = { spellIds = ids, dungeonId = e.dungeonID }
end

mod.BlockFactories.travel = function(blockCfg, slot, contentFrame, barCtx)
    local instance = { cfg = blockCfg, slot = slot, content = contentFrame, ctx = barCtx }
    instance.key = InstKey(barCtx, blockCfg)
    -- BAG_UPDATE_DELAYED / SPELLS_CHANGED: ownership edges that must clear the negative hearthstone cache (rare at idle, cheap refresh).
    -- Cooldown-START edges ride a player-filtered UNIT_SPELLCAST_SUCCEEDED
    -- registered in Enable (RegisterInstEvents cannot unit-filter): every
    -- hearth start IS a player cast, and BAG_UPDATE_COOLDOWN measured
    -- idle-chatty (~0.7 Hz ambient with nothing cooling).
    instance.events = { "HEARTHSTONE_BOUND", "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED", "SPELLS_CHANGED" }

    local mouseOver = false
    -- Heartbeat demand-gate: the 1s tick runs ONLY while something is cooling,
    -- a timer shows on the bar, or the tooltip is open (live M:SS columns).
    -- Otherwise no tick at all; a player cast announces every start edge and re-arms.
    local ticking = false
    local TravelSyncTicker -- forward declaration, filled in after TravelTick

    -- Pre-allocated tooltip line buffers (no per-show garbage). `spellId` is the static teleport spell ID (click overlay attribute), not the shown `name`.
    local _mythicLinesBuf = {}
    for index = 1, #SEASON_TELEPORTS do
        _mythicLinesBuf[index] = { name = "", cd = 0, cdKnown = true, spellId = nil }
    end
    local _mythicLineCount = 0

    local function D()
        return blockCfg.settings or {}
    end
    local function BC()
        return barCtx.cfg
    end

    local built = false
    local hearthButton, hearthIcon, hearthText
    local placeholder

    local function RefreshTravelTooltip()
        local ar, ag, ab = 1, 1, 1
        mod.Tip_Begin(hearthButton)
        -- Hover-persistent like the spec tip: the cursor can travel onto it to click ready teleport rows, even when no row is clickable right now.
        mod.Tip_MarkInteractive()
        mod.Tip_AddLine("|cFFFFFFFF[|r" .. L["TRAVEL_COOLDOWNS"] .. "|cFFFFFFFF]|r", ar, ag, ab)
        mod.Tip_AddLine(" ")
        local cd2, cdKnown = TravelGetPrimaryCooldown()
        local cdStr
        if cdKnown then
            cdStr = mod.FormatCooldown(cd2)
            if not cdStr then
                cdStr = L["READY"]
            end
        else
            cdStr = "-"
        end
        local ready = cdKnown and cd2 <= 0
        local rr, rg, rb = 0.5, 0.5, 0.5
        if ready then
            rr, rg, rb = 0, 1, 0
        end
        -- Click-to-use when ready (shared overlay), always a hearthstone: the left click's when
        -- it is one. White while ready, M+ "On Cooldown" gray otherwise; plain label so state and
        -- hover color the whole line; the plain-state row is pad-marked to match the clickable row.
        local hsLabel = L["HEARTHSTONE"] .. " (" .. (GetBindLocation() or "?") .. ")"
        local hsMacro
        if ready then
            local choice = TravelClickChoice(D(), 1)
            local hsId
            if type(choice) == "number" and not TRAVEL_EXTRA_SET[choice] and TravelIsUsable(choice) then
                hsId = choice
            else
                hsId = TravelPickHearthstone(choice == "random")
            end
            if hsId then
                hsMacro = TravelBuildMacro(hsId)
            end
        end
        if hsMacro then
            mod.Tip_AddMacroActionDouble(hsLabel, cdStr, hsMacro, 1, 1, 1, rr, rg, rb)
        else
            local hg = ready and 1 or 0.65
            mod.Tip_AddDouble(hsLabel, cdStr, hg, hg, hg, rr, rg, rb)
            mod.Tip_PadRow()
        end

        -- Travel entries ride the same section, each with its own cooldown. A spell entry
        -- takes the spell-side name/cooldown/click overlay, and IsPlayerSpell gates it to its
        -- class. Name lookups can be nil on a cold cache: the row appears on the next tooltip refresh.
        for _, entryId in ipairs(TRAVEL_EXTRAS) do
            local kind = TravelExtraKind(entryId)
            local isSpell = kind == "spell"
            if kind then
                local entryName
                if isSpell then
                    local sInfo = C_Spell.GetSpellInfo(entryId)
                    entryName = sInfo and sInfo.name
                else
                    if C_ToyBox and C_ToyBox.GetToyInfo then
                        local _, tn = C_ToyBox.GetToyInfo(entryId)
                        entryName = tn
                    end
                    if not entryName and C_Item and C_Item.GetItemInfo then
                        entryName = C_Item.GetItemInfo(entryId)
                    end
                end
                if entryName then
                    local tcd, tKnown = TravelGetRemainingCooldown(entryId, isSpell)
                    local tstr
                    if tKnown then
                        tstr = mod.FormatCooldown(tcd)
                        if not tstr then
                            tstr = L["READY"]
                        end
                    else
                        tstr = "-"
                    end
                    local tready = tKnown and tcd <= 0
                    local tr, tg, tb = 0.5, 0.5, 0.5
                    if tready then
                        tr, tg, tb = 0, 1, 0
                    end
                    if tready then
                        -- Ready: click-to-use, same secure overlay contract as the M+ rows
                        -- (degrades to text in combat). Both helpers take the same args; only the seeded secure attribute differs.
                        if kind == "item" then
                            mod.Tip_AddMacroActionDouble(
                                entryName,
                                tstr,
                                TravelBuildMacro(entryId),
                                1,
                                1,
                                1,
                                tr,
                                tg,
                                tb
                            )
                        else
                            local AddActionRow = isSpell and mod.Tip_AddActionDouble
                                or mod.Tip_AddToyActionDouble
                            AddActionRow(entryName, tstr, entryId, 1, 1, 1, tr, tg, tb)
                        end
                    else
                        -- On cooldown: same gray as the M+ "On Cooldown" label.
                        mod.Tip_AddDouble(entryName, tstr, 0.65, 0.65, 0.65, tr, tg, tb)
                    end
                end
            end
        end

        local dt = D()
        -- All houses share one visit cooldown.
        local house = TravelFindHouse(TravelClickChoice(dt, 1))
            or TravelFindHouse(TravelClickChoice(dt, 2))
            or TravelFindHouse(TravelClickChoice(dt, 3))
        if house then
            local hstr, hready = "-", false
            local returnTrip = TravelCanReturnHome()
            if returnTrip then
                hstr, hready = L["RETURN_AVAILABLE"], true
            else
                local rem, known = TravelHouseCooldown()
                if known then
                    hstr = mod.FormatCooldown(rem) or L["READY"]
                    hready = rem <= 0
                end
            end
            if hready then
                mod.Tip_AddHouseActionDouble(
                    TravelHouseName(house),
                    hstr,
                    house,
                    returnTrip,
                    1,
                    1,
                    1,
                    0,
                    1,
                    0
                )
            else
                mod.Tip_AddDouble(TravelHouseName(house), hstr, 0.65, 0.65, 0.65, 0.5, 0.5, 0.5)
                mod.Tip_PadRow()
            end
        end

        local altRows = 0
        if dt.altHearths == true then
            altRows = TravelAddAltRows(ar, ag, ab, function()
                mod.Tip_Hide(hearthButton)
            end)
        end

        -- Show M+ Portals: nil reads as shown (no migration needed). OFF skips the section and its spell-resolution work entirely.
        -- WoW Forever has no Mythic+ teleports: the section never builds there.
        _mythicLineCount = 0
        if not CludesUI.IS_FOREVER and D().clickableTeleports ~= false then
            for _, record in ipairs(SEASON_TELEPORTS) do
                local spellId = TravelResolveMythicId(record.spellIds)
                if spellId then
                    local dName = nil
                    if record.dungeonId and GetLFGDungeonInfo then
                        dName = GetLFGDungeonInfo(record.dungeonId)
                    end
                    local spInfo = C_Spell.GetSpellInfo(spellId)
                    local spName = spInfo and spInfo.name
                    local name2 = dName
                    if not name2 then
                        name2 = spName
                    end
                    if not name2 then
                        name2 = tostring(spellId)
                    end
                    _mythicLineCount = _mythicLineCount + 1
                    local mcd, mKnown = TravelGetRemainingCooldown(spellId, true)
                    _mythicLinesBuf[_mythicLineCount].name = name2
                    _mythicLinesBuf[_mythicLineCount].cd = mcd
                    _mythicLinesBuf[_mythicLineCount].cdKnown = mKnown
                    _mythicLinesBuf[_mythicLineCount].spellId = spellId
                end
            end
        end
        if _mythicLineCount > 0 then
            mod.Tip_AddLine(" ")
            mod.Tip_AddLine(L["MYTHIC_TELEPORTS"], ar, ag, ab)
            -- Insertion sort on active entries only (max ~8)
            for index = 2, _mythicLineCount do
                local jdx = index
                while jdx > 1 and _mythicLinesBuf[jdx].name < _mythicLinesBuf[jdx - 1].name do
                    _mythicLinesBuf[jdx].name, _mythicLinesBuf[jdx - 1].name =
                        _mythicLinesBuf[jdx - 1].name, _mythicLinesBuf[jdx].name
                    _mythicLinesBuf[jdx].cd, _mythicLinesBuf[jdx - 1].cd =
                        _mythicLinesBuf[jdx - 1].cd, _mythicLinesBuf[jdx].cd
                    _mythicLinesBuf[jdx].cdKnown, _mythicLinesBuf[jdx - 1].cdKnown =
                        _mythicLinesBuf[jdx - 1].cdKnown, _mythicLinesBuf[jdx].cdKnown
                    _mythicLinesBuf[jdx].spellId, _mythicLinesBuf[jdx - 1].spellId =
                        _mythicLinesBuf[jdx - 1].spellId, _mythicLinesBuf[jdx].spellId
                    jdx = jdx - 1
                end
            end
            -- Ready rows are always click-to-teleport (not configurable). On-cooldown teleports share one group, collapsing into one "On Cooldown" line (soonest remaining).
            local cdMin, cdUnknown
            for index = 1, _mythicLineCount do
                local e = _mythicLinesBuf[index]
                if not e.cdKnown then
                    -- Secret cooldown (restricted combat): state unknowable,
                    -- fold into the collapsed On Cooldown line below.
                    cdUnknown = true
                elseif e.cd <= 0 then
                    -- Ready teleport: left-click casts it (secure overlay button
                    -- keyed to the static spell ID; row highlights on hover).
                    mod.Tip_AddActionDouble(e.name, L["READY"], e.spellId, 0.8, 0.8, 0.8, 0, 1, 0)
                elseif not cdMin or e.cd < cdMin then
                    cdMin = e.cd
                end
            end
            if cdMin then
                local cs = mod.FormatCooldown(cdMin)
                if not cs then
                    cs = L["READY"]
                end
                mod.Tip_AddDouble(L["ON_COOLDOWN"], cs, 0.65, 0.65, 0.65, 0.5, 0.5, 0.5)
            elseif cdUnknown then
                mod.Tip_AddDouble(L["ON_COOLDOWN"], "-", 0.65, 0.65, 0.65, 0.5, 0.5, 0.5)
            end
        end
        mod.Tip_AddLine(" ")
        for button = 1, 3 do
            local choice = TravelClickChoice(dt, button)
            if choice ~= "none" then
                local what
                local hgt = TravelFindHouse(choice)
                if choice == "random" then
                    what = L["RANDOM_HEARTHSTONE"]
                elseif hgt then
                    what = TravelCanReturnHome() and L["RETURN_FROM_HOME"] or TravelHouseName(hgt)
                elseif TRAVEL_EXTRA_SET[choice] and TravelExtraKind(choice) then
                    what = TravelEntryName(choice) or L["USE_HEARTHSTONE"]
                else
                    what = L["USE_HEARTHSTONE"]
                end
                local labelText = (button == 1 and L["LEFT_CLICK"])
                    or (button == 2 and L["RIGHT_CLICK"])
                    or L["MIDDLE_CLICK"]
                mod.Tip_AddDouble(labelText, what, 1, 1, 1, ar, ag, ab)
            end
        end
        if altRows > 0 then
            mod.Tip_AddDouble(L["CTRL_ALT_LEFT_CLICK"], L["REMOVE_CHARACTER"], 1, 1, 1, ar, ag, ab)
        end
        mod.Tip_Show()
    end

    local function Build()
        if built then
            return
        end
        built = true
        if placeholder then
            placeholder:Hide()
        end

        hearthButton = CreateFrame(
            "Button",
            "CludesUIDataBarsHearth_" .. instance.key,
            contentFrame,
            "SecureActionButtonTemplate"
        )
        -- Up only + useOnKeyDown=false: registering both Up and Down lets the
        -- ActionButtonUseKeyDown CVar fire the macro twice (2nd /use cancels the cast).
        hearthButton:SetAllPoints()
        hearthButton:EnableMouse(true)
        hearthButton:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
        hearthButton:SetAttribute("useOnKeyDown", false)
        -- One explicit pair per button (1 left, 2 right, 3 middle), not an unsuffixed fallback.
        for button = 1, 3 do
            hearthButton:SetAttribute("*type" .. button, "macro")
            hearthButton:SetAttribute("*macrotext" .. button, "")
        end

        hearthIcon = hearthButton:CreateTexture(nil, "OVERLAY")
        hearthText = hearthButton:CreateFontString(nil, "OVERLAY")
        AttachTextOffset(instance, hearthText)

        local function SeedMacro()
            if InCombatLockdown() then
                return
            end
            local dt = D()
            local canReturn
            for button = 1, 3 do
                local choice = TravelClickChoice(dt, button)
                local house = TravelFindHouse(choice)
                if house then
                    if canReturn == nil then
                        canReturn = TravelCanReturnHome()
                    end
                    hearthButton:SetAttribute("*type" .. button, canReturn and "returnhome" or "teleporthome")
                    hearthButton:SetAttribute("*house-neighborhood-guid" .. button, house.neighborhoodGUID)
                    hearthButton:SetAttribute("*house-guid" .. button, house.houseGUID)
                    hearthButton:SetAttribute("*house-plot-id" .. button, house.plotID)
                    hearthButton:SetAttribute("*macrotext" .. button, "")
                else
                    hearthButton:SetAttribute("*type" .. button, "macro")
                    local ident = TravelResolveChoice(choice)
                    hearthButton:SetAttribute("*macrotext" .. button, ident and TravelBuildMacro(ident) or "")
                end
            end
        end

        -- Reseed on every PreClick (OOC only) so each click fires its current choice
        -- without a protected call from OnClick. SetScript is fine here: WE created this button.
        hearthButton:SetScript("PreClick", function()
            if InCombatLockdown() then
                return
            end
            SeedMacro()
        end)

        hearthButton:SetScript("OnEnter", function()
            mouseOver = true
            instance:Refresh()
            RefreshTravelTooltip()
        end)
        hearthButton:SetScript("OnLeave", function()
            mouseOver = false
            -- Interactive tip (clickable M+ rows): the keep-alive poll owns
            -- dismissal so the cursor can travel onto the tip to click a row.
            mod.Tip_HideUnlessInteractive(hearthButton)
            instance:Refresh()
        end)

        -- Seed macrotext shortly after build so a first-combat click works.
        C_Timer.After(1, SeedMacro)
        instance._seedClicks = SeedMacro
    end

    local enabled = false
    local function SyncHouseWatch()
        local dt = D()
        local uses = TravelIsHouseChoice(TravelClickChoice(dt, 1))
            or TravelIsHouseChoice(TravelClickChoice(dt, 2))
            or TravelIsHouseChoice(TravelClickChoice(dt, 3))
        TravelWatchHouses(instance, enabled and uses)
    end

    function instance:OnHouseList()
        if self._seedClicks then
            self._seedClicks()
        end
        self:Refresh()
    end

    -- Combat-deferred construction: dimmed non-interactive icon until OOC.
    if InCombatLockdown() then
        placeholder = contentFrame:CreateTexture(nil, "OVERLAY")
        K.SetBlockIcon(placeholder, blockCfg)
        placeholder:SetVertexColor(0.6, 0.6, 0.6, 0.6)
        placeholder:SetSize(16, 16)
        placeholder:SetPoint("CENTER")
        mod.DeferUntilOOC("edbbuild:" .. instance.key, function()
            if instance._dead then
                return
            end
            Build()
            instance:Refresh()
        end)
    else
        Build()
    end

    local function RelayoutAfterCombat()
        if not instance._dead then
            instance:Refresh()
        end
    end
    local layoutKey = "edbtravellayout:" .. instance.key
    -- What the bar shows (text, cooling parts, dimmed icon) as last laid out,
    -- and a counting timer's shape (digits as 0s) whose width is reserved.
    local drawnState, drawnZeros

    -- Bags, spells and the ticker call this often: nothing if the bar would
    -- show the same; at a held timer width just the new digits; else a pass.
    local function Update()
        if not built then
            return
        end
        SyncHouseWatch()
        if D().altHearths == true then
            TravelSaveMyHearth()
        end
        local location, barTimer, coolMask, iconDim = TravelBarText(D(), GetBindLocation() or "?", mouseOver)
        local state = location .. "|" .. coolMask .. "|" .. tostring(iconDim)
        if state == drawnState then
            TravelSyncTicker(mouseOver or coolMask ~= 0 or barTimer)
            return
        end
        if
            barTimer
            and drawnZeros
            and not InCombatLockdown()
            and not barCtx.IsVertical()
            and location:gsub("%d", "0") == drawnZeros
        then
            hearthText:SetText(location)
            instance._barTimer, instance._lastCoolMask = barTimer, coolMask
            drawnState = state
            TravelSyncTicker(true)
            return
        end
        instance:Refresh()
    end

    function instance:Refresh()
        SyncHouseWatch()
        if D().altHearths == true then
            TravelSaveMyHearth()
        end
        if not built then
            return
        end
        K.SetBlockIcon(hearthIcon, blockCfg)
        local barCfg = BC()
        local barH = barCtx.GetThickness()
        local fontSize = max(9, floor(CONTENT_BASE * 0.4333 + 0.5))
        local isSide = barCtx.IsVertical()

        local location, barTimer, coolMask, iconDim = TravelBarText(D(), GetBindLocation() or "?", mouseOver)
        instance._barTimer = barTimer
        instance._lastCoolMask = coolMask
        drawnState = location .. "|" .. coolMask .. "|" .. tostring(iconDim)
        drawnZeros = nil

        mod.SetFont(hearthText, fontSize, barCfg)

        hearthText:SetText(location)

        TravelSyncTicker(mouseOver or coolMask ~= 0 or barTimer)

        -- Cooling parts carry their own gray; the icon dims only when every shown part cools.
        if mouseOver then
            local ar, ag, ab = mod.GetAccent()
            hearthText:SetTextColor(ar, ag, ab, 1)
            hearthIcon:SetVertexColor(ar, ag, ab, 1)
        else
            local br, bgr, bb = BlockColorOf(blockCfg)
            hearthText:SetTextColor(br, bgr, bb, 1)
            if iconDim then
                hearthIcon:SetVertexColor(0.5, 0.5, 0.5, 1)
            else
                local ir, ig, ib = IconColorOf(blockCfg)
                hearthIcon:SetVertexColor(ir, ig, ib, 1)
            end
        end

        -- The secure button cannot resize in combat: lay out again once it ends.
        if InCombatLockdown() then
            mod.DeferUntilOOC(layoutKey, RelayoutAfterCombat)
            return
        end

        -- +2 icon size, -2 gap: hearthstone runs bigger and tighter than default.
        local iconSz, gap = fontSize + 2, ICON_GAP - 2
        if isSide then
            iconSz = min(iconSz, max(14, floor(CONTENT_BASE * 0.72 + 0.5)))
        end
        hearthIcon:ClearAllPoints()
        hearthIcon:SetSize(iconSz, iconSz)

        if isSide then
            local slotW = VSlotW(instance)
            local innerW = max(30, slotW - 8)
            local totalH = 8 + iconSz + 2

            contentFrame:SetWidth(slotW)
            hearthButton:SetWidth(slotW)
            hearthIcon:SetPoint("TOP", hearthButton, "TOP", 0, -4)

            mod.SetWrappedText(hearthText, innerW, "CENTER")
            hearthText:ClearAllPoints()
            hearthText:SetPoint("TOP", hearthIcon, "BOTTOM", 0, -2)
            totalH = totalH + mod.SnapToPixelGrid(hearthText:GetStringHeight())

            totalH = max(totalH, barH)
            contentFrame:SetHeight(totalH)
            hearthButton:SetHeight(totalH)
        else
            local slotW = HBudget(instance, 120)
            mod.SetFont(hearthText, fontSize, barCfg)
            hearthText:SetText(location)
            -- +2 matches the top-of-Refresh sizing: this branch re-derives iconSz, which would otherwise silently swallow earlier size bumps.
            iconSz = min(fontSize + 2, max(14, floor(CONTENT_BASE * 0.72 + 0.5)))
            hearthIcon:SetSize(iconSz, iconSz)
            mod.ResetInlineText(hearthText, "LEFT")
            local tw = mod.SnapToPixelGrid(hearthText:GetStringWidth())
            -- A counting timer sizes as all-zero digits (measured off screen) and never
            -- shrinks, so the bar holds still.
            if instance._barTimer then
                local zeroW = 0
                local mfs = mod.MeasureFS()
                local zeros = location:gsub("%d", "0")
                if mfs then
                    mod.SetFont(mfs, fontSize, barCfg)
                    mfs:SetText(zeros)
                    zeroW = mod.SnapToPixelGrid(mfs:GetStringWidth())
                end
                tw = max(tw, zeroW, instance._trvPeakW or 0)
                instance._trvPeakW = tw
                -- The width holds while the timer keeps this shape (see Update).
                drawnZeros = zeros
            else
                instance._trvPeakW = nil
            end
            if location == "" then
                tw = 0
                gap = 0
            end
            local totalW = min(slotW, iconSz + gap + tw + 4)
            contentFrame:SetSize(totalW, barH)
            hearthButton:SetSize(totalW, barH)
            hearthIcon:SetPoint("LEFT", hearthButton, "LEFT", 0, 0)
            hearthText:ClearAllPoints()
            hearthText:SetPoint("LEFT", hearthButton, "LEFT", iconSz + gap, 0)
        end
        MaybeRelayout(instance)
    end

    -- 1s heartbeat. Hovered: the open tooltip's M:SS columns need per-second full
    -- refreshes. Un-hovered: a cooling probe of the shown parts; Refresh runs when
    -- any part's state changes, and each second while a timer shows on the bar.
    local function TravelTick()
        if built and mouseOver and mod.Tip_IsOwned(hearthButton) then
            Update()
            RefreshTravelTooltip()
            return
        end
        -- Unknown (secret) cooldowns count as cooling: the probe keeps ticking through combat and self-corrects on the first clean read.
        local coolMask = TravelCoolingMask(D())
        if coolMask ~= instance._lastCoolMask or instance._barTimer then
            Update()
        elseif coolMask == 0 and not mouseOver then
            -- Settled ready with no edge to paint: nothing left to watch.
            TravelSyncTicker(false)
        end
    end

    -- Fills the forward declaration above. Register/unregister is flag-guarded
    -- so redundant syncs cost one boolean test.
    TravelSyncTicker = function(wanted)
        if wanted then
            if not ticking then
                ticking = true
                mod.RegisterHeartbeat("travel:" .. instance.key, TravelTick)
            end
        elseif ticking then
            ticking = false
            mod.UnregisterHeartbeat("travel:" .. instance.key)
        end
    end

    instance.eventFrame = MakeEventFrame(instance, function(self, evt)
        if evt == "UNIT_SPELLCAST_SUCCEEDED" then
            -- Cooldown-START lane (player casts only; every hearth start is
            -- one): never invalidates the hearthstone pick, and while the
            -- ticker already runs there is nothing to learn. One probe on a
            -- start edge re-arms the tick; zero fires standing idle.
            -- With timer text on, a full Refresh also reads the click cooldowns
            -- the hearthstone probe does not watch.
            if not ticking then
                if TravelAnyTimerText(D()) and not InCombatLockdown() then
                    self:Refresh()
                else
                    TravelTick()
                end
            end
            return
        end
        mod.TravelInvalidateHearthCache()
        Update()
    end)

    function instance:Enable()
        enabled = true
        SyncHouseWatch()
        contentFrame:Show()
        RegisterInstEvents(self)
        -- Player-filtered registration; Disable's UnregisterAllEvents drops it,
        -- so it re-registers here (re-registration is idempotent).
        pcall(self.eventFrame.RegisterUnitEvent, self.eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player")
        -- Armed at enable as a belt; the first settled ready read stands it
        -- down (TravelTick's else branch or any Refresh).
        TravelSyncTicker(true)
    end

    function instance:Disable()
        enabled = false
        TravelWatchHouses(self, false)
        TravelSyncTicker(false)
        UnregisterInstEvents(self)
        contentFrame:Hide()
    end

    function instance:GetAutoLength()
        if not built then
            return 40
        end
        local barH = barCtx.GetThickness()
        if barCtx.IsVertical() then
            local fontSize = max(9, floor(CONTENT_BASE * 0.4333 + 0.5))
            local iconSz = fontSize
            local textH = hearthText:GetStringHeight() or fontSize
            return max(8 + iconSz + 2 + textH + 4, barH, 50)
        end
        return max(contentFrame:GetWidth() or 120, 40)
    end

    function instance:Destroy()
        self._dead = true
        enabled = false
        TravelWatchHouses(self, false)
        if hearthButton then
            ParkSecureFrame(hearthButton, self.key .. "_hearth")
        end
        contentFrame:Hide()
    end

    return instance
end
