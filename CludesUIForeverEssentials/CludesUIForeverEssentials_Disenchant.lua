if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
if not (CUI and CUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_Disenchant.lua  (WoW Forever only)
--  Disenchant tools (Professions on, Disenchant on):
--    Window    every bag item Disenchant can take, in a grid. Right-click
--              keeps that one, Shift-right-click keeps every copy; Disenchant
--              All (N) disenchants the next one per click (the game wants a
--              click for each), skipping ones the game refuses. /cde, or the
--              Disenchant button on the recipe window while Enchanting is open.
--    Tooltips  green, blue and purple gear says what it disenchants into,
--              about what that is worth at your scanned auction prices, and
--              the Enchanting skill it needs (red when yours is lower).
-------------------------------------------------------------------------------
local _, module = ...
local Prof = module.Prof
if not Prof then return end
local F = Prof.F
local Get = F.Get

local SPELL, ENCHANTING = 13262, 333
local WEAPON, ARMOR = 2, 4
local UNCOMMON, RARE, EPIC = 2, 3, 4
local CUT = 0.95
local NEVER_SLOTS = { INVTYPE_BODY = true, INVTYPE_TABARD = true }
local NO_DISENCHANT = {
    [11287] = true, [11288] = true, [11289] = true, [20406] = true, [20407] = true, [20408] = true,
    [44803] = true, [217287] = true, [249144] = true, [249232] = true, [249234] = true, [249237] = true,
}

-------------------------------------------------------------------------------
--  What gear disenchants into, by quality and item level
--  uncommon: { from, to, dust, essence, shard, armour dust %, armour essence %,
--              weapon dust %, weapon essence %, dust min, max, essence min, max }
-------------------------------------------------------------------------------
local OUTCOMES = {
    [UNCOMMON] = {
        { 5, 15, 10940, 10938, nil, 80, 20, 20, 80, 1, 2, 1, 2 },
        { 16, 20, 10940, 10939, 10978, 75, 20, 20, 75, 2, 3, 1, 2 },
        { 21, 25, 10940, 10998, 10978, 75, 15, 15, 75, 4, 6, 1, 2 },
        { 26, 30, 11083, 11082, 11084, 75, 20, 20, 75, 1, 2, 1, 2 },
        { 31, 35, 11083, 11134, 11138, 75, 20, 20, 75, 2, 5, 1, 2 },
        { 36, 40, 11137, 11135, 11139, 75, 20, 20, 75, 1, 2, 1, 2 },
        { 41, 45, 11137, 11174, 11177, 75, 20, 20, 75, 2, 5, 1, 2 },
        { 46, 50, 11176, 11175, 11178, 75, 20, 20, 75, 1, 2, 1, 2 },
        { 51, 55, 11176, 16202, 14343, 75, 20, 22, 75, 2, 5, 1, 2 },
        { 56, 60, 16204, 16203, 14344, 75, 20, 22, 75, 1, 2, 1, 2 },
        { 61, 65, 16204, 16203, 14344, 75, 20, 22, 75, 2, 5, 2, 3 },
    },
    -- rare: { from, to, shard, (crystal at 0.5%) }
    [RARE] = {
        { 1, 25, 10978 }, { 26, 30, 11084 }, { 31, 35, 11138 }, { 36, 40, 11139 },
        { 41, 45, 11177 }, { 46, 50, 11178 }, { 51, 55, 14343 }, { 56, 80, 14344, 20725 },
    },
    -- epic: { from, to, shard or crystal, min, max }
    [EPIC] = {
        { 40, 45, 11177, 2, 4 }, { 46, 50, 11178, 2, 4 }, { 51, 55, 14343, 2, 4 },
        { 56, 60, 20725, 1, 1 }, { 61, 88, 20725, 1, 2 },
    },
}

local Values = {}

function Values.Takes(itemID, classID, quality, equip)
    return not NO_DISENCHANT[itemID]
        and (classID == WEAPON or classID == ARMOR)
        and not NEVER_SLOTS[equip or ""]
        and type(quality) == "number" and quality >= UNCOMMON and quality <= EPIC
end

-- The Enchanting skill an item needs, from its level and quality.
function Values.Skill(level, quality)
    if not (level and level >= 1 and quality) then return end
    if quality >= RARE and level <= 25 then return 25 end
    if level <= 20 then return 1 end
    return math.max(25, (math.ceil(level / 5) - 4) * 25)
end

-- { { itemID, chance %, min, max }, ... } or nil.
function Values.Outcomes(classID, quality, level)
    for _, row in ipairs(OUTCOMES[quality] or {}) do
        if level >= row[1] and level <= row[2] then
            if quality == UNCOMMON then
                local weapon = classID == WEAPON
                local dust, essence = row[weapon and 8 or 6], row[weapon and 9 or 7]
                local list = { { row[3], dust, row[10], row[11] }, { row[4], essence, row[12], row[13] } }
                if row[5] then list[#list + 1] = { row[5], 100 - dust - essence, 1, 1 } end
                return list
            elseif quality == RARE then
                if row[4] then return { { row[3], 99.5, 1, 1 }, { row[4], 0.5, 1, 1 } } end
                return { { row[3], 100, 1, 1 } }
            end
            return { { row[3], 100, row[4], row[5] } }
        end
    end
end

-- The average worth of what it disenchants into, at your auction prices
-- (nil when a material has no price).
function Values.Expected(outcomes, priceOf)
    local total = 0
    for _, o in ipairs(outcomes) do
        local each = priceOf(o[1])
        if not each then return end
        total = total + o[2] / 100 * (o[3] + o[4]) / 2 * each
    end
    return math.floor(total)
end

local function PriceOf(itemID)
    local market = CUI._Market
    if module.AuctionAPI() then
        local link = select(2, C_Item.GetItemInfo(itemID)) or ("item:" .. itemID)
        return module.AuctionPrice(link)
    end
    return market and market.Get("enabled") and (market.Market.Price(itemID)) or nil
end

-- Your Enchanting skill, or nil.
local function EnchantingSkill()
    for _, index in pairs({ GetProfessions() }) do
        local _, _, rank, _, _, _, line, modifier = GetProfessionInfo(index)
        if line == ENCHANTING then return (rank or 0) + (modifier or 0) end
    end
end

-------------------------------------------------------------------------------
--  The bag items it takes, the ones you keep, and which one is next
-------------------------------------------------------------------------------
local D = { records = {}, failed = {}, misses = {} }

local function Store(key)
    local conf = F.Cfg()
    conf[key] = conf[key] or {}
    return conf[key]
end

function D.Known() return C_SpellBook.IsSpellKnown(SPELL) == true end

function D.Collect()
    wipe(D.records)
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                local _, _, _, equip, _, classID = C_Item.GetItemInfoInstant(info.itemID)
                local quality = info.quality or C_Item.GetItemQualityByID(info.itemID)
                if Values.Takes(info.itemID, classID, quality, equip) then
                    local location = ItemLocation:CreateFromBagAndSlot(bag, slot)
                    local guid = C_Item.GetItemGUID and location:IsValid() and C_Item.GetItemGUID(location) or nil
                    D.records[#D.records + 1] = {
                        bag = bag,
                        slot = slot,
                        itemID = info.itemID,
                        link = info.hyperlink,
                        icon = info.iconFileID,
                        quality = quality,
                        locked = info.isLocked == true,
                        guid = guid,
                        key = guid or (bag * 1000 + slot),
                    }
                end
            end
        end
    end
    return D.records
end

function D.KeptAll(r) return Store("disenchantKeep")[r.itemID] == true end
function D.KeptCopy(r) return r.guid ~= nil and Store("disenchantKeepCopy")[r.guid] == true end
function D.Kept(r) return D.KeptAll(r) or D.KeptCopy(r) end

function D.ToggleKeep(r, every)
    local all, copies = Store("disenchantKeep"), Store("disenchantKeepCopy")
    local copy = D.KeptCopy(r)
    if r.guid then copies[r.guid] = nil end
    if every or not r.guid or all[r.itemID] then
        all[r.itemID] = not all[r.itemID] or nil
    elseif not copy then
        copies[r.guid] = true
    end
end

function D.Ready(r) return not (r.locked or D.Kept(r) or D.failed[r.key]) end

-- The next one: ready, the fewest misses first.
function D.Next()
    local best
    for _, r in ipairs(D.records) do
        if D.Ready(r) and (not best or (D.misses[r.key] or 0) < (D.misses[best.key] or 0)) then best = r end
    end
    return best
end

function D.Counts()
    local ready, kept = 0, 0
    for _, r in ipairs(D.records) do
        if D.Kept(r) then
            kept = kept + 1
        elseif D.Ready(r) then
            ready = ready + 1
        end
    end
    return ready, kept
end

-------------------------------------------------------------------------------
--  The window
-------------------------------------------------------------------------------
local COLUMNS, ICON, GAP = 8, 36, 4
local GRID_W = COLUMNS * ICON + (COLUMNS - 1) * GAP
local WAIT_TIMEOUT = 8
local REFUSALS = { "SPELL_FAILED_CANT_BE_DISENCHANTED", "SPELL_FAILED_CANT_BE_DISENCHANTED_SKILL" }

local Window = {}
local window, slots, all = nil, {}, nil
local armed, waiting, trying = nil, false, {}
local waitGen = 0
local events = CreateFrame("Frame")

local function On() return F.Enabled() and Get("disenchant") ~= false end

local function Paint(button, r)
    button.record = r
    button.icon:SetTexture(r.icon)
    local kept, refused = D.Kept(r), D.failed[r.key]
    button.icon:SetDesaturated(kept or refused or r.locked)
    button.icon:SetAlpha((kept or refused) and 0.35 or 1)
    button.mark:SetShown(kept)
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[r.quality]
    CUI.Kit.Border(button, c and c.r or 0.3, c and c.g or 0.3, c and c.b or 0.3, 1)
    button.next:SetShown(r == armed)
    button:Show()
end

local function SlotTip(self)
    local r = self.record
    if not r then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetBagItem(r.bag, r.slot)
    local ar, ag, ab = CUI.Kit.Accent()
    if D.failed[r.key] then
        GameTooltip:AddLine("The game would not disenchant this (skill too low?). Skipped until you reload.", 1, 0.38, 0.38, true)
    elseif D.KeptAll(r) then
        GameTooltip:AddLine("Kept: every copy. Right-click to disenchant them again.", ar, ag, ab, true)
    elseif D.KeptCopy(r) then
        GameTooltip:AddLine("Kept: this one. Right-click to disenchant it again.", ar, ag, ab, true)
    else
        if r.guid then GameTooltip:AddLine("Right-click: keep this one", ar, ag, ab) end
        GameTooltip:AddLine("Shift-right-click: keep every copy", ar, ag, ab)
    end
    GameTooltip:Show()
end

local function NewSlot(index)
    local button = CreateFrame("Button", nil, window.grid)
    button:SetSize(ICON, ICON)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", 1, -1)
    button.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    button.mark = button:CreateFontString(nil, "OVERLAY")
    CUI.Kit.Font(button.mark, 10, "essentials")
    button.mark:SetPoint("BOTTOM", 0, 2)
    button.mark:SetTextColor(1, 0.38, 0.38)
    button.mark:SetText("Keep")
    button.next = button:CreateTexture(nil, "OVERLAY")
    button.next:SetPoint("BOTTOMLEFT", 2, 2)
    button.next:SetPoint("BOTTOMRIGHT", -2, 2)
    button.next:SetHeight(3)
    button.next:SetColorTexture(CUI.Kit.Accent())
    local hover = button:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, 0.15)
    local column, row = (index - 1) % COLUMNS, math.floor((index - 1) / COLUMNS)
    button:SetPoint("TOPLEFT", column * (ICON + GAP), -row * (ICON + GAP))
    button:SetScript("OnEnter", SlotTip)
    button:SetScript("OnLeave", GameTooltip_Hide)
    button:SetScript("OnClick", function(self, mouse)
        local r = self.record
        if not r then return end
        if mouse == "RightButton" then
            D.ToggleKeep(r, IsShiftKeyDown())
            Window.Redraw()
            if GameTooltip:IsOwned(self) then SlotTip(self) end
        elseif r.link then
            HandleModifiedItemClick(r.link)
        end
    end)
    slots[index] = button
    return button
end

-- Point the secure button at the next item (out of combat only).
local function Arm()
    if InCombatLockdown() then return end
    armed = not waiting and D.Next() or nil
    all:SetAttribute("type", armed and "macro" or nil)
    all:SetAttribute("macrotext", armed and ("/stopspelltarget\n/cast " .. (C_Spell.GetSpellName(SPELL) or "Disenchant")) or nil)
    all:SetAttribute("target-bag", armed and armed.bag or nil)
    all:SetAttribute("target-slot", armed and armed.slot or nil)
    all:SetAlpha(armed and 1 or 0.45)
end

function Window.Redraw()
    if not (window and window:IsShown()) then return end
    local list = D.Collect()
    Arm()
    for index, r in ipairs(list) do
        Paint(slots[index] or NewSlot(index), r)
    end
    for index = #list + 1, #slots do
        slots[index].record = nil
        slots[index]:Hide()
    end
    window.grid:SetHeight(math.max(math.ceil(#list / COLUMNS) * (ICON + GAP) - GAP, 1))
    window.empty:SetShown(#list == 0)
    local ready, kept = D.Counts()
    window.summary:SetText(("%d to disenchant, %d kept"):format(ready, kept))
    all.label:SetText(waiting and "Disenchanting..." or ready > 0 and ("Disenchant All (%d)"):format(ready) or "Disenchant All")
end

local function Release()
    waiting = false
    waitGen = waitGen + 1
end

local function Refuse()
    if not trying.key then return end
    D.failed[trying.key] = true
    CUI.Print(("%s could not be disenchanted, skipped until you reload."):format(trying.link or "That item"))
    trying.key = nil
end

local function Wait()
    waiting = true
    waitGen = waitGen + 1
    local gen = waitGen
    C_Timer.After(WAIT_TIMEOUT, function()
        if waiting and gen == waitGen then
            Release()
            if trying.key then D.misses[trying.key] = (D.misses[trying.key] or 0) + 1 end
            Window.Redraw()
        end
    end)
end

local function BuildAll()
    all = CreateFrame("Button", "CludesUIDisenchantAll", window, "SecureActionButtonTemplate")
    all:SetSize(160, 28)
    all:SetPoint("BOTTOMRIGHT", -12, 12)
    all:RegisterForClicks("LeftButtonUp")
    local bg = all:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.12, 0.13, 0.14, 1)
    CUI.Kit.Border(all, CUI.Kit.Accent())
    all.label = all:CreateFontString(nil, "OVERLAY")
    CUI.Kit.Font(all.label, 13, "essentials")
    all.label:SetPoint("CENTER")
    all:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(armed and ("Disenchants " .. (armed.link or "the next item") .. ".") or "Nothing left to disenchant.", 1, 1, 1)
        GameTooltip:AddLine("One item per click: the game needs a click for every disenchant.", 0.64, 0.68, 0.71, true)
        GameTooltip:Show()
    end)
    all:HookScript("OnLeave", GameTooltip_Hide)
    all:SetScript("PreClick", function()
        trying.key, trying.link = armed and armed.key, armed and armed.link
    end)
    all:SetScript("PostClick", function()
        if not trying.key then return end
        if SpellIsTargeting() then
            Refuse() -- the cursor stayed up: the game would not take it
        else
            Wait()
        end
        Window.Redraw()
    end)
end

local function Build()
    window = CUI.Kit.Window("CludesUIDisenchantWindow", GRID_W + 40, 440, "Disenchant", { key = "essentials" })
    window:Hide() -- a new frame starts shown; the first Show must run OnShow
    local sub = window:CreateFontString(nil, "OVERLAY")
    CUI.Kit.Font(sub, 11.5, "essentials")
    sub:SetTextColor(0.64, 0.68, 0.71)
    sub:SetPoint("TOPLEFT", 12, -36)
    sub:SetText("Right-click keeps one, Shift keeps every copy.")
    local scroll, content = CUI.Kit.Scroll(window)
    scroll:SetPoint("TOPLEFT", 14, -60)
    scroll:SetPoint("BOTTOMRIGHT", -24, 52)
    content:SetSize(GRID_W, 1)
    window.grid = content
    window.empty = window:CreateFontString(nil, "OVERLAY")
    CUI.Kit.Font(window.empty, 12.5, "essentials")
    window.empty:SetTextColor(0.64, 0.68, 0.71)
    window.empty:SetPoint("CENTER", scroll, "CENTER")
    window.empty:SetText("Nothing in your bags to disenchant.")
    window.summary = window:CreateFontString(nil, "OVERLAY")
    CUI.Kit.Font(window.summary, 12, "essentials")
    window.summary:SetTextColor(0.64, 0.68, 0.71)
    window.summary:SetPoint("BOTTOMLEFT", 14, 20)
    BuildAll()
    window:SetScript("OnShow", function()
        for _, event in ipairs({ "BAG_UPDATE_DELAYED", "ITEM_LOCK_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "UI_ERROR_MESSAGE" }) do
            events:RegisterEvent(event)
        end
        Window.Redraw()
    end)
    window:HookScript("OnHide", function()
        events:UnregisterAllEvents()
        waiting, trying.key = false, nil
        if not InCombatLockdown() then
            armed = nil
            Arm()
        end
    end)
end

events:SetScript("OnEvent", function(_, event, _, message)
    if event == "PLAYER_REGEN_DISABLED" then
        if window and not InCombatLockdown() then window:Hide() end
        return
    elseif event == "BAG_UPDATE_DELAYED" then
        Release()
        trying.key = nil
    elseif event == "UI_ERROR_MESSAGE" then
        local refused = false
        for _, name in ipairs(REFUSALS) do
            if _G[name] ~= nil and _G[name] == message then refused = true end
        end
        if not refused then return end
        Release()
        Refuse()
    end
    Window.Redraw()
end)

function Window.Open()
    if not On() then return CUI.Print("Turn on Disenchant in Forever Tools > Professions first.") end
    if not D.Known() then return CUI.Print("You do not know Disenchant.") end
    if InCombatLockdown() then return CUI.Print("The Disenchant window cannot open in combat.") end
    if not window then Build() end
    window:Show()
end

function Window.Toggle()
    if window and window:IsShown() then
        if not InCombatLockdown() then window:Hide() end
    else
        Window.Open()
    end
end

SLASH_CUIDISENCHANT1 = "/cde"
SlashCmdList.CUIDISENCHANT = function() Window.Toggle() end

-- A Disenchant button on the recipe window while Enchanting is open.
local RW = CUI._RecipeWindow
if RW and RW.Window.AddTitleButton then
    RW.Window.AddTitleButton({
        text = "Disenchant",
        width = 84,
        order = 1,
        tip = "The Disenchant window: everything in your bags Disenchant can take. Also /cde.",
        onClick = function() Window.Toggle() end,
        shown = function()
            local prof = RW.State.prof
            return On() and not RW.State.linked and prof ~= nil and prof.id == ENCHANTING and D.Known()
        end,
    })
end

-------------------------------------------------------------------------------
--  Tooltips: what it disenchants into
-------------------------------------------------------------------------------
local function Coins(copper)
    local fn = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or GetCoinTextureString
    return fn and fn(copper, 12) or tostring(copper)
end

-- left, right text for an item, or nil.
function Values.TooltipLine(itemID)
    local _, _, quality, level, _, _, _, _, equip, _, _, classID = C_Item.GetItemInfo(itemID)
    if not (level and Values.Takes(itemID, classID, quality, equip)) then return end
    local outcomes = Values.Outcomes(classID, quality, level)
    if not outcomes then return end
    local need, skill = Values.Skill(level, quality), EnchantingSkill()
    local worth = Values.Expected(outcomes, PriceOf)
    if not (worth or skill) then return end
    local right = worth and ("~" .. Coins(math.floor(worth * CUT))) or ""
    if need then
        local short = skill and skill < need
        right = right .. (right ~= "" and "  " or "") .. (short and "|cffff6161" or "|cff808080") .. "needs " .. need .. "|r"
    end
    return "Disenchant", right
end

local hooked = false
local function OnTooltip(tooltip, data)
    if not (On() and Get("disenchantTooltip") ~= false) then return end
    local itemID = data and data.id
    if type(itemID) ~= "number" then return end
    local left, right = Values.TooltipLine(itemID)
    if left then
        local r, g, b = CUI.Kit.Accent()
        tooltip:AddDoubleLine(left, right, r, g, b, 1, 1, 1)
    end
end

local function Apply()
    if window and not On() and not InCombatLockdown() then window:Hide() end
    if On() and not hooked and TooltipDataProcessor and Enum.TooltipDataType then
        hooked = true
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnTooltip)
    end
end

CUI._Disenchant = { Apply = Apply, On = On, Window = Window, D = D, Values = Values }

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    Apply()
end)
