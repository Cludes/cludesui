if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
if not (CUI and CUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_TradeEnchants.lua  (WoW Forever only)
--  Trade Enchants (Professions on, Trade Enchants on): while you trade with
--  Enchanting open and someone puts an item in the "Will not be traded" slot,
--  a panel beside the trade window lists your enchants that go on it, the
--  ones they linked to you in whisper, party or instance chat first. Enchant
--  casts it on their item in one click.
-------------------------------------------------------------------------------
local _, module = ...
local Professions, SlotsFor = module.Prof, module.EnchantSlots
local ROW_WIDTH = CUI._RecipeWindow
if not (Professions and SlotsFor and ROW_WIDTH) then return end
local F = Professions.F
local Get = F.Get
local COLOURS = CUI.Kit.Palette

local ENCHANTING_ID = 333
local ROWS_MAX, ROW_HEIGHT = 8, 28
local LINK_CHANNELS = {
    "CHAT_MSG_WHISPER",
    "CHAT_MSG_PARTY",
    "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_INSTANCE_CHAT",
    "CHAT_MSG_INSTANCE_CHAT_LEADER",
}

local TradeRules = { asked = {}, askers = 0 }

local function On() return F.Enabled() and Get("tradeEnchants") ~= false end

local function HasBit(mask, n) return math.floor(mask / 2 ^ n) % 2 == 1 end

function TradeRules.Fits(slot, class, subClass, invType)
    if slot[1] ~= class then return false end
    return (slot[3] == 0 or HasBit(slot[3], subClass)) and (slot[2] == 0 or HasBit(slot[2], invType))
end

function TradeRules.Asked(guid, recipeID)
    local set = guid and TradeRules.asked[guid]
    return set ~= nil and set[recipeID] == true
end

-- Enchant links in chat: remember who asked for what (the last 20 people).
function TradeRules.OnChat(text, guid)
    if not (type(text) == "string" and type(guid) == "string") then return end
    if issecretvalue and (issecretvalue(text) or issecretvalue(guid)) then return end
    for id in text:gmatch("|Henchant:(%d+)") do
        id = tonumber(id)
        if SlotsFor[id] then
            if not TradeRules.asked[guid] then
                if TradeRules.askers >= 20 then
                    wipe(TradeRules.asked)
                    TradeRules.askers = 0
                end
                TradeRules.asked[guid], TradeRules.askers = {}, TradeRules.askers + 1
            end
            TradeRules.asked[guid][id] = true
        end
    end
end

-- Your own Enchanting is open in the recipe window's backend.
function TradeRules.EnchantingOpen()
    local frame = rawget(_G, "ProfessionsFrame")
    if not (frame and frame:IsShown() and ROW_WIDTH.Data.Own()) then return false end
    local skillLine = ROW_WIDTH.Data.Profession()
    return skillLine ~= nil and skillLine.id == ENCHANTING_ID
end

-- The enchants you know that fit an item link, asked-for first, then the
-- highest level first.
function TradeRules.List(link, guid)
    local list = {}
    local _, _, _, _, _, class, subClass = C_Item.GetItemInfoInstant(link)
    local invType = C_Item.GetItemInventoryTypeByID(link)
    if not (class and invType) then return list end
    for _, id in ipairs(C_TradeSkillUI.GetAllRecipeIDs() or {}) do
        local slot = SlotsFor[id]
        if slot and TradeRules.Fits(slot, class, subClass, invType) then
            local info = C_TradeSkillUI.GetRecipeInfo(id)
            if info and info.learned then list[#list + 1] = info end
        end
    end
    table.sort(list, function(left, right)
        local a, b = TradeRules.Asked(guid, left.recipeID), TradeRules.Asked(guid, right.recipeID)
        if a ~= b then return a end
        if (left.maxTrivialLevel or 0) ~= (right.maxTrivialLevel or 0) then
            return (left.maxTrivialLevel or 0) > (right.maxTrivialLevel or 0)
        end
        return left.name < right.name
    end)
    return list
end

-------------------------------------------------------------------------------
--  The panel beside the trade window
-------------------------------------------------------------------------------
local panel
local state = { trading = false, offset = 0 }

-- The enchant goes up as a spell on the cursor; the same click then clicks
-- the trade window's "Will not be traded" item (a secure click), which casts
-- it there.
local function ArmEnchantButton(self)
    local castOn = self.recipeID ~= nil and not IsModifiedClick() and not SpellIsTargeting() and TradeRules.EnchantingOpen()
    self:SetAttribute("type", castOn and "click" or nil)
    if castOn then C_TradeSkillUI.CraftRecipe(self.recipeID) end
end

local function CreateRow(index)
    local row = CreateFrame("Frame", nil, panel)
    row:SetHeight(ROW_HEIGHT - 2)
    row:SetPoint("TOPLEFT", 8, -34 - (index - 1) * ROW_HEIGHT)
    row:SetPoint("TOPRIGHT", -8, -34 - (index - 1) * ROW_HEIGHT)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(20, 20)
    row.icon:SetPoint("LEFT", 2, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local button = CUI.Kit.SecureButton(row, nil, "Enchant", 64, 22, { key = "essentials" })
    button:SetPoint("RIGHT")
    button:SetAttribute("clickbutton", rawget(_G, "TradeRecipientItem7ItemButton"))
    button:SetScript("PreClick", ArmEnchantButton)
    button:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Casts this enchant on the item they put in the trade window.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    button:HookScript("OnLeave", GameTooltip_Hide)
    row.button = button
    row.note = row:CreateFontString(nil, "OVERLAY")
    CUI.Kit.Font(row.note, CUI.Kit.SMALL_SIZE, "essentials")
    row.note:SetPoint("RIGHT", button, "LEFT", -6, 0)
    row.note:SetTextColor(CUI.Kit.Accent())
    row.name = row:CreateFontString(nil, "OVERLAY")
    CUI.Kit.Font(row.name, CUI.Kit.TEXT_SIZE, "essentials")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
    row.name:SetPoint("RIGHT", row.note, "LEFT", -6, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    panel.rows[index] = row
    return row
end

local function BuildPanel()
    panel = CreateFrame("Frame", "CludesUITradeEnchants", UIParent)
    panel:SetSize(300, 60)
    panel:SetFrameStrata("HIGH")
    panel:EnableMouse(true)
    panel:EnableMouseWheel(true)
    CUI.Kit.Panel(panel, 0.97)
    CUI.Kit.Header(panel, "Trade Enchants", function()
        panel.dismissed = true
        panel:Hide()
    end, { key = "essentials", closeTip = "Hides this until the next trade." })
    panel.note = panel:CreateFontString(nil, "OVERLAY")
    CUI.Kit.Font(panel.note, CUI.Kit.SMALL_SIZE, "essentials")
    panel.note:SetTextColor(unpack(COLOURS.muted))
    panel.note:SetJustifyH("LEFT")
    panel.note:SetWordWrap(true)
    panel.rows = {}
    panel:SetScript("OnMouseWheel", function(_, step)
        state.offset = state.offset - step
        TradeRules.Render()
    end)
    panel:Hide()
end

function TradeRules.Render()
    state.pending = false
    local link = state.trading and GetTradeTargetItemLink(TRADE_ENCHANT_SLOT or 7)
    if not (link and On() and C_SpellBook.IsSpellKnown(13262)) or InCombatLockdown() then
        if panel then panel:Hide() end
        return
    end
    if not panel then BuildPanel() end
    if panel.dismissed then return end
    local list = TradeRules.EnchantingOpen() and TradeRules.List(link, state.partner)
    local n = list and #list or 0
    state.offset = math.max(0, math.min(state.offset, n - ROWS_MAX))
    local shown = math.min(n, ROWS_MAX)
    for index = 1, shown do
        local info = list[index + state.offset]
        local row = panel.rows[index] or CreateRow(index)
        row.icon:SetTexture(info.icon)
        row.name:SetText(info.name)
        row.note:SetText(TradeRules.Asked(state.partner, info.recipeID) and "asked for" or "")
        row.button.recipeID = info.recipeID
        local ready = ROW_WIDTH.Data.Craftable(info) > 0
        row.name:SetTextColor(unpack(ready and COLOURS.text or COLOURS.muted))
        row.button:SetEnabled(ready)
        row.button:SetAlpha(ready and 1 or 0.45)
        row:Show()
    end
    for index = shown + 1, #panel.rows do
        panel.rows[index]:Hide()
    end
    local note = not list and "Open Enchanting to list your enchants for this item."
        or n == 0 and "None of your enchants go on this item."
        or n > ROWS_MAX and ("%d enchants: scroll for more."):format(n)
        or ""
    panel.note:SetText(note)
    panel.note:ClearAllPoints()
    panel.note:SetPoint("TOPLEFT", 10, -36 - shown * ROW_HEIGHT)
    panel.note:SetPoint("RIGHT", -10, 0)
    panel:SetHeight(42 + shown * ROW_HEIGHT + (note ~= "" and 22 or 0))
    panel:ClearAllPoints()
    local trade = rawget(_G, "TradeFrame")
    if trade then
        panel:SetPoint("TOPLEFT", trade, "TOPRIGHT", 6, 0)
    else
        panel:SetPoint("CENTER")
    end
    panel:Show()
end

local function QueueRefresh()
    if state.pending then return end
    state.pending = true
    C_Timer.After(0.1, TradeRules.Render)
end

local events = CreateFrame("Frame")
local PROFESSION_OPEN = {
    "TRADE_SKILL_SHOW",
    "TRADE_SKILL_CLOSE",
    "TRADE_SKILL_LIST_UPDATE",
    "BAG_UPDATE_DELAYED",
    "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED",
}
events:SetScript("OnEvent", function(_, event, ...)
    if event:find("^CHAT_MSG_") then
        local text, _, _, _, _, _, _, _, _, _, _, guid = ...
        return TradeRules.OnChat(text, guid)
    elseif event == "TRADE_SHOW" then
        state.trading, state.partner, state.offset = true, UnitGUID("NPC"), 0
        if panel then panel.dismissed = nil end
        for _, e in ipairs(PROFESSION_OPEN) do
            events:RegisterEvent(e)
        end
    elseif event == "TRADE_CLOSED" then
        state.trading, state.partner = false, nil
        for _, e in ipairs(PROFESSION_OPEN) do
            events:UnregisterEvent(e)
        end
        if panel and not InCombatLockdown() then panel:Hide() end
        return
    elseif event == "TRADE_TARGET_ITEM_CHANGED" then
        if ... ~= (TRADE_ENCHANT_SLOT or 7) then return end
        state.offset = 0
    elseif event == "PLAYER_REGEN_DISABLED" then
        if panel then panel:Hide() end
        return
    end
    QueueRefresh()
end)

local function Apply()
    events:UnregisterAllEvents()
    if not On() then
        state.trading = false
        if panel and not InCombatLockdown() then panel:Hide() end
        return
    end
    for _, e in ipairs({ "TRADE_SHOW", "TRADE_CLOSED", "TRADE_TARGET_ITEM_CHANGED" }) do
        events:RegisterEvent(e)
    end
    for _, e in ipairs(LINK_CHANNELS) do
        pcall(events.RegisterEvent, events, e)
    end
end

CUI._TradeEnchants = { Apply = Apply, TE = TradeRules }

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    Apply()
end)
