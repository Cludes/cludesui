if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUIBags_Offline.lua
--  offline bank: saves every character's bags, bank and the warband bank
--  account-wide so the viewer can show them anywhere, plus tooltip counts.
--
--  store: CludesUIBagsInventoryDB (its own saved vars, so profile exports
--  and sync never carry inventories)
--    chars[key] = { name, realm, class, level, bagsTime, bankTime,
--                   bags = { container... }, bank = { container... } }
--    warband    = { time, tabs = { container... } }
--    container  = { size, name?, icon?, items = { [slot] = item string },
--                   counts = { [slot] = count } } (counts only above 1)
--  bags[i] is bag i - 1 (false when that bag slot's empty), bank[i] and
--  tabs[i] are the i-th bank tab. pets and keystones keep their full link,
--  since their string alone can't name them.
--  key = "Name-Realm" (CludesUI.CharKey).
--  wow forever: keyed by guid like the gold ledger, since a first name isn't
--  unique there, and the name keeps its surname. a bank tab is a bag put in a
--  bank slot (up to 9), so its size follows that bag and a tab with no bag
--  saves as false. no warband bank there.
--
--  both switches are account-wide (CludesUIDB.bagOfflineBank /
--  .bagTooltipCounts), like the data. read only: a bag saves after
--  BAG_UPDATE_DELAYED when it changed, banks while a banker's open. nothing
--  gets saved, hooked or listened to while both are off.
-------------------------------------------------------------------------------
local CUI = CludesUI
local mod = select(2, ...)

local _emptyP = {}
local function Acct() return _G.CludesUIDB or _emptyP end

local Offline = {}
mod.Offline = Offline

function Offline.Enabled() return Acct().bagOfflineBank == true end
function Offline.CountsEnabled() return Acct().bagTooltipCounts == true end
local function Active() return Offline.Enabled() or Offline.CountsEnabled() end

-------------------------------------------------------------------------------
--  item strings
-------------------------------------------------------------------------------
-- "item:..." for items, the whole link for anything else
local function ItemString(itemLink)
    local s = itemLink:match("|H(item:[^|]+)|h")
    return s or itemLink
end
Offline.ItemString = ItemString

-- item id from a string or link (pet cages count as the cage item)
local function ItemID(text)
    local kind, ident = text:match("^(%a+):(%d+)")
    if not kind then
        kind, ident = text:match("|H(%a+):(%d+)")
    end
    if kind == "battlepet" then return 82800 end
    return tonumber(ident)
end
Offline.ItemID = ItemID

-------------------------------------------------------------------------------
--  store
-------------------------------------------------------------------------------
local rev = 0 -- goes up on every write so the tooltip index knows to rebuild
local listeners = {}
local index, indexRev -- tooltip index, below
-- per saved list: goes up only when that list changes, so a view of it can
-- tell its own list apart from every other save
local listRev = setmetatable({}, { __mode = "k" })
local listGen = 0
local function Bump(entries)
    listGen = listGen + 1
    listRev[entries] = listGen
end
function Offline.ListRev(entries) return entries and listRev[entries] or 0 end

-- saves from before item strings kept whole colored links
local function Upgrade(entries)
    if type(entries) ~= "table" then return end
    for _, t in ipairs(entries) do
        if type(t) == "table" and type(t.links) == "table" then
            local itemList = {}
            for slot, itemLink in pairs(t.links) do
                itemList[slot] = ItemString(itemLink)
            end
            t.items, t.links = itemList, nil
        end
    end
end

function Offline.Store()
    local saved = _G.CludesUIBagsInventoryDB
    if type(saved) ~= "table" then
        saved = { v = 2 }
        _G.CludesUIBagsInventoryDB = saved
    end
    if type(saved.chars) ~= "table" then saved.chars = {} end
    if type(saved.warband) ~= "table" then saved.warband = { tabs = {} } end
    if type(saved.warband.tabs) ~= "table" then saved.warband.tabs = {} end
    if saved.v ~= 2 then
        for _, c in pairs(saved.chars) do
            if type(c) == "table" then
                Upgrade(c.bags)
                Upgrade(c.bank)
            end
        end
        Upgrade(saved.warband.tabs)
        saved.v = 2
    end
    return saved
end

local function OwnKey()
    if CUI.IS_FOREVER then return CUI.GetGoldLedger().CharKey() end
    return CUI.CharKey("-")
end
Offline.CurrentKey = OwnKey

-- a class's colour code, custom class colours included
local function ClassHex(class)
    local color = class and CUI.GetClassColor(class)
    return color and CUI.HexColor(color.r, color.g, color.b) or "|cffffffff"
end
Offline.ClassHex = ClassHex

function Offline.Char(key)
    if not key then return nil end
    return Offline.Store().chars[key]
end
function Offline.Warband() return Offline.Store().warband end
-- forever has no warband bank
function Offline.HasWarband() return not CUI.IS_FOREVER end
function Offline.Rev() return rev end

-- something changed, so the viewer and tooltip index catch up. patched: the
-- index was already fixed up in place for this write
local function IndexChanged(what, patched)
    local current = patched and index and indexRev == rev
    rev = rev + 1
    if current then indexRev = rev end
    for _, func in ipairs(listeners) do
        func(what)
    end
end
function Offline.OnChange(func) listeners[#listeners + 1] = func end

function Offline.CanForget(key) return key ~= nil and key ~= OwnKey() end

function Offline.Forget(key)
    if not Offline.CanForget(key) then return end
    local c = Offline.Store().chars[key]
    if type(c) == "table" then
        if type(c.bags) == "table" then Bump(c.bags) end
        if type(c.bank) == "table" then Bump(c.bank) end
    end
    Offline.Store().chars[key] = nil
    IndexChanged("forget")
end

-- characters for the picker, by realm then name, current one flagged
function Offline.Characters()
    local entries, me = {}, OwnKey()
    for key, c in pairs(Offline.Store().chars) do
        if type(c) == "table" then
            entries[#entries + 1] = {
                key = key,
                name = c.name or key,
                realm = c.realm or "",
                class = c.class,
                current = key == me,
            }
        end
    end
    table.sort(entries, function(lhs, rhs)
        if lhs.realm ~= rhs.realm then return lhs.realm < rhs.realm end
        return lhs.name < rhs.name
    end)
    return entries
end

local function MyEntry()
    local key = OwnKey()
    if not key then return nil end
    local chars = Offline.Store().chars
    local c = chars[key]
    if not c then
        c = {}
        chars[key] = c
    end
    local _, class = UnitClass("player")
    local name = UnitName("player")
    if CUI.IS_FOREVER then
        -- the full name whatever the show-surname preference, as the gold ledger keeps it
        local first, surname = (UnitNameUnmodified or UnitName)("player")
        name = CUI.WithSurname(first, surname, true)
    end
    c.name, c.realm, c.class, c.level = name, CUI.RealmGroupName(), class, UnitLevel("player")
    -- a rename keeps the guid: its old entry goes and the bank moves over (the
    -- bags save again at once). a new character under a reused name has another
    -- guid and starts empty. a realm transfer gets a new guid too, so its old
    -- entry stays until it's deleted from the picker.
    local unitGuid = UnitGUID("player")
    if unitGuid and c.guid ~= unitGuid then
        local moved = c.guid ~= nil
        if moved then
            c.bags, c.bank, c.bagsTime, c.bankTime = nil, nil, nil, nil
        end
        c.guid = unitGuid
        for k, o in pairs(chars) do
            if k ~= key and type(o) == "table" and o.guid == unitGuid then
                if c.bank == nil then
                    c.bank, c.bankTime = o.bank, o.bankTime
                end
                chars[k] = nil
                moved = true
            end
        end
        if moved then IndexChanged("forget") end
    end
    return c
end

-- one container's stuff, nil if the game says it has no slots
local function ReadContainer(bagID)
    local size = C_Container.GetContainerNumSlots(bagID) or 0
    if size <= 0 then return nil end
    local itemList, counts = {}, {}
    for slot = 1, size do
        local details = C_Container.GetContainerItemInfo(bagID, slot)
        local itemLink = details and (details.hyperlink or C_Container.GetContainerItemLink(bagID, slot))
        if itemLink then
            itemList[slot] = ItemString(itemLink)
            if (details.stackCount or 1) > 1 then counts[slot] = details.stackCount end
        end
    end
    return { size = size, items = itemList, counts = counts }
end

-- true when two saved containers hold the same items
local function SameMap(a, b)
    for key, val in pairs(a) do
        if b[key] ~= val then return false end
    end
    for key in pairs(b) do
        if a[key] == nil then return false end
    end
    return true
end
local function Same(posX, posY)
    if type(posX) ~= type(posY) then return false end
    if type(posX) ~= "table" then return posX == posY end
    return posX.size == posY.size
        and posX.name == posY.name
        and posX.icon == posY.icon
        and SameMap(posX.items, posY.items)
        and SameMap(posX.counts, posY.counts)
end

local Patch -- below, with the tooltip index

-------------------------------------------------------------------------------
--  snapshots: only the containers that changed get read again
-------------------------------------------------------------------------------
local BAGS = { 0, 1, 2, 3, 4, 5 }
local CHAR_BANK, WARBAND_BANK = {}, {}
for i = 1, CUI.IS_FOREVER and 9 or 6 do
    local ident = Enum.BagIndex["CharacterBankTab_" .. i]
    if ident then CHAR_BANK[#CHAR_BANK + 1] = ident end
end
for i = 1, 5 do
    local ident = Enum.BagIndex["AccountBankTab_" .. i]
    if ident then WARBAND_BANK[#WARBAND_BANK + 1] = ident end
end
-- bag id -> its spot in the saved list
local BAG_POS, CHAR_POS, WARBAND_POS = {}, {}, {}
for i, ident in ipairs(BAGS) do
    BAG_POS[ident] = i
end
for i, ident in ipairs(CHAR_BANK) do
    CHAR_POS[ident] = i
end
for i, ident in ipairs(WARBAND_BANK) do
    WARBAND_POS[ident] = i
end

local dirty = {} -- bag ids to read on the next save

local function MarkDirty(ids)
    for _, ident in ipairs(ids) do
        dirty[ident] = true
    end
end

-- read the dirty ones of ids into list; true if anything changed
local function SaveList(entries, ids, place, field, ownerFrame, meta)
    local changed = false
    for _, ident in ipairs(ids) do
        if dirty[ident] then
            dirty[ident] = nil
            local i = place[ident]
            local new = ReadContainer(ident)
            if new and meta then
                local m = meta[i]
                new.name, new.icon = m and m.name, m and m.icon
            end
            -- bag slots can be empty (false), so can a bought forever tab with
            -- no bag in it. unbought bank tabs just stay unsaved
            if not new and (not meta or (CUI.IS_FOREVER and meta[i])) then new = false end
            if new ~= nil and not Same(entries[i], new) then
                Patch(entries[i], new, field, ownerFrame)
                entries[i] = new
                changed = true
            end
        end
    end
    if changed then Bump(entries) end
    return changed
end

local function SaveBags()
    local c = MyEntry()
    if not c then return end
    c.bagsTime = time()
    if type(c.bags) ~= "table" then c.bags = {} end
    -- most bag updates move nothing we keep (cooldowns, locks): no change then
    if SaveList(c.bags, BAGS, BAG_POS, "bags", OwnKey()) then IndexChanged("bags", true) end
end

local function Meta(bankType)
    return C_Bank and C_Bank.FetchPurchasedBankTabData and C_Bank.FetchPurchasedBankTabData(bankType)
end

local atBank, atCharBank = false, false

local function SaveBanks()
    if not atBank then return end
    local changed = false
    if atCharBank then
        local c = MyEntry()
        if c then
            c.bankTime = time()
            if type(c.bank) ~= "table" then c.bank = {} end
            changed =
                SaveList(c.bank, CHAR_BANK, CHAR_POS, "bank", OwnKey(), Meta(Enum.BankType.Character) or {})
        end
    end
    local locked = C_Bank
        and C_Bank.FetchBankLockedReason
        and C_Bank.FetchBankLockedReason(Enum.BankType.Account)
    if locked == nil and Offline.HasWarband() then
        local wid = Offline.Store().warband
        wid.time = time()
        if SaveList(wid.tabs, WARBAND_BANK, WARBAND_POS, nil, nil, Meta(Enum.BankType.Account) or {}) then
            changed = true
        end
    end
    if changed then IndexChanged("bank", true) end
end

-- a burst of updates only saves once
local pendingBags, pendingBank = false, false
local function Flush()
    -- a save queued just before both switches went off (the Bags reset) is dropped
    if not Active() then
        pendingBags, pendingBank = false, false
        return
    end
    if pendingBags then
        pendingBags = false
        SaveBags()
    end
    if pendingBank then
        pendingBank = false
        SaveBanks()
    end
end
local flushQueued = false
local function FlushQueued()
    flushQueued = false
    Flush()
end
local function QueueSave(bags, bank)
    if bags then pendingBags = true end
    if bank then pendingBank = true end
    if flushQueued then return end
    flushQueued = true
    C_Timer.After(0.5, FlushQueued)
end

-------------------------------------------------------------------------------
--  events (only registered while an option needs them)
-------------------------------------------------------------------------------
local PIT = Enum.PlayerInteractionType
-- banker types: true for a character bank. some bankers open it as
-- CharacterBanker (67) rather than Banker
local BANKERS = {}
if PIT.Banker then BANKERS[PIT.Banker] = true end
if PIT.CharacterBanker then BANKERS[PIT.CharacterBanker] = true end
if PIT.AccountBanker then BANKERS[PIT.AccountBanker] = false end
local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, evt, arg)
    if evt == "BAG_UPDATE" then
        if BAG_POS[arg] then
            dirty[arg] = true
        elseif atBank and (CHAR_POS[arg] or WARBAND_POS[arg]) then
            dirty[arg] = true
            QueueSave(false, true)
        end
    elseif evt == "BAG_UPDATE_DELAYED" then
        QueueSave(true, false)
    elseif evt == "BAG_CONTAINER_UPDATE" then
        MarkDirty(BAGS)
        QueueSave(true, false)
        -- forever: a bag went in or out of a bank tab
        if atCharBank and CUI.IS_FOREVER then
            MarkDirty(CHAR_BANK)
            QueueSave(false, true)
        end
    elseif evt == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
        if BANKERS[arg] ~= nil then
            atBank, atCharBank = true, BANKERS[arg]
            MarkDirty(CHAR_BANK)
            MarkDirty(WARBAND_BANK)
            QueueSave(false, true)
        end
    elseif evt == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
        if BANKERS[arg] ~= nil then
            Flush() -- save before the contents go unreadable
            atBank, atCharBank = false, false
        end
    elseif atBank then
        -- a tab bought or renamed (BANK_TABS_CHANGED / BANK_TAB_SETTINGS_UPDATED,
        -- arg = its bank type): that bank's tabs, for their names and icons.
        -- slot changes come through BAG_UPDATE with the tab's bag id
        if arg == Enum.BankType.Account then
            MarkDirty(WARBAND_BANK)
            QueueSave(false, true)
        elseif arg == Enum.BankType.Character then
            MarkDirty(CHAR_BANK)
            QueueSave(false, true)
        end
    end
end)
local EVENTS = {
    "BAG_UPDATE_DELAYED",
    "BAG_UPDATE",
    "BAG_CONTAINER_UPDATE",
    "PLAYER_INTERACTION_MANAGER_FRAME_SHOW",
    "PLAYER_INTERACTION_MANAGER_FRAME_HIDE",
    "BANK_TABS_CHANGED",
    "BANK_TAB_SETTINGS_UPDATED",
}

local listening = false
local IndexSoon -- below
function Offline.Sync()
    local enabled = Active()
    if enabled == listening then return end
    listening = enabled
    for _, event in ipairs(EVENTS) do
        if enabled then
            pcall(eventFrame.RegisterEvent, eventFrame, event)
        else
            eventFrame:UnregisterEvent(event)
        end
    end
    if enabled then
        MarkDirty(BAGS)
        QueueSave(true, false)
    end
end

-- the bags module reset: every saved inventory goes
function Offline.Wipe()
    _G.CludesUIBagsInventoryDB = nil
    index = nil
    wipe(listRev)
    listGen = listGen + 1
    IndexChanged("forget")
    -- this character saves again right away
    MarkDirty(BAGS)
    if listening then QueueSave(true, false) end
end

-- an options toggle: key is bagOfflineBank or bagTooltipCounts
function Offline.Set(key, enabled)
    if not _G.CludesUIDB then return end
    _G.CludesUIDB[key] = enabled and true or nil
    Offline.Sync()
    Offline.SyncTooltip()
    Offline.SyncButton()
end

-------------------------------------------------------------------------------
--  tooltip item counts
-------------------------------------------------------------------------------
-- index: chars[itemID][key] = { bags, bank }, warband[itemID].n
-- sign -1 takes a container back out (rows that hit zero go away)
local function AddContainer(tbl, into, field, ownerFrame, sign)
    if type(tbl) ~= "table" or type(tbl.items) ~= "table" then return end
    for slot, s in pairs(tbl.items) do
        local ident = ItemID(s)
        if ident then
            local num = ((tbl.counts and tbl.counts[slot]) or 1) * sign
            local row = into[ident]
            if not row then
                row = {}
                into[ident] = row
            end
            if ownerFrame then
                local e = row[ownerFrame]
                if not e then
                    e = { bags = 0, bank = 0 }
                    row[ownerFrame] = e
                end
                e[field] = e[field] + num
                if e.bags + e.bank <= 0 then row[ownerFrame] = nil end
            else
                row.n = (row.n or 0) + num
                if row.n <= 0 then row.n = nil end
            end
            if next(row) == nil then into[ident] = nil end
        end
    end
end

local function Index()
    if index and indexRev == rev then return index end
    local chars, war = {}, {}
    local saved = Offline.Store()
    for key, c in pairs(saved.chars) do
        if type(c) == "table" then
            for _, t in ipairs(type(c.bags) == "table" and c.bags or _emptyP) do
                AddContainer(t, chars, "bags", key, 1)
            end
            for _, t in ipairs(type(c.bank) == "table" and c.bank or _emptyP) do
                AddContainer(t, chars, "bank", key, 1)
            end
        end
    end
    for _, tab in ipairs(saved.warband.tabs) do
        AddContainer(tab, war, nil, nil, 1)
    end
    index, indexRev = { chars = chars, warband = war }, rev
    return index
end

-- one container swapped for another: fix the index up in place instead of a
-- full rebuild on the next hover (Changed keeps it current). no owner = warband
Patch = function(old, new, field, ownerFrame)
    if not (index and indexRev == rev) then return end
    local into = ownerFrame and index.chars or index.warband
    AddContainer(old, into, field, ownerFrame, -1)
    AddContainer(new, into, field, ownerFrame, 1)
end

-- built a moment after login, not inside the first hover
IndexSoon = function()
    C_Timer.After(3, function()
        if listening and Offline.CountsEnabled() then Index() end
    end)
end

-- finished lines per item id, until the next write
local lineCache, lineRev = {}, -1
local sameName = {}
local function BuildLines(ident)
    local position = Index()
    local row, war = position.chars[ident], position.warband[ident]
    if not row and not (war and war.n) then return false end
    local saved, lines, sum = Offline.Store(), {}, 0
    -- two characters of one name (other realms) get their realm added
    wipe(sameName)
    for key in pairs(row or _emptyP) do
        local c = saved.chars[key]
        if c and c.name then sameName[c.name] = (sameName[c.name] or 0) + 1 end
    end
    for key, entry in pairs(row or _emptyP) do
        local c = saved.chars[key]
        local num = entry.bags + entry.bank
        if c and num > 0 then
            local parts = {}
            if entry.bags > 0 then parts[#parts + 1] = CludesUI.Lf("Bags %1$d", entry.bags) end
            if entry.bank > 0 then parts[#parts + 1] = CludesUI.Lf("Bank %1$d", entry.bank) end
            local name = c.name or "?"
            if (sameName[name] or 0) > 1 and c.realm and c.realm ~= "" then name = name .. "-" .. c.realm end
            lines[#lines + 1] =
                { ClassHex(c.class) .. name .. "|r", table.concat(parts, "  "), 1, 1, 1, n = num }
            sum = sum + num
        end
    end
    table.sort(lines, function(lhs, rhs) return lhs.n > rhs.n end)
    if war and war.n then
        sum = sum + war.n
        lines[#lines + 1] = { CludesUI.L("Warband Bank"), war.n, 0.4, 0.78, 1 }
    end
    if #lines > 1 then lines[#lines + 1] = { CludesUI.L("Total"), sum, 1, 0.82, 0, total = true } end
    return lines
end

local function OnItemTooltip(tooltip, payload)
    if not (listening and Offline.CountsEnabled()) then return end
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
    if tooltip:IsForbidden() then return end
    local ident = payload and payload.id
    if type(ident) ~= "number" or (issecretvalue and issecretvalue(ident)) then return end
    if lineRev ~= rev then
        wipe(lineCache)
        lineRev = rev
    end
    local lines = lineCache[ident]
    if lines == nil then
        lines = BuildLines(ident)
        lineCache[ident] = lines
    end
    if not lines then return end
    tooltip:AddLine(" ")
    for _, l in ipairs(lines) do
        if l.total then
            tooltip:AddDoubleLine(l[1], l[2], l[3], l[4], l[5], 1, 1, 1)
        else
            tooltip:AddDoubleLine(l[1], l[2], l[3], l[4], l[5], 0.8, 0.8, 0.8)
        end
    end
end

-- the post call can't be unhooked, so it just bails while off
local hooked = false
function Offline.SyncTooltip()
    if not (listening and Offline.CountsEnabled()) then return end
    IndexSoon()
    if hooked then return end
    if not (TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall) then return end
    hooked = true
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItemTooltip)
end

-------------------------------------------------------------------------------
--  login
-------------------------------------------------------------------------------
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    -- old saves upgrade once; nothing is created for a player who never turned a switch on
    if Active() or _G.CludesUIBagsInventoryDB ~= nil then Offline.Store() end
    Offline.Sync()
    Offline.SyncTooltip()
end)
