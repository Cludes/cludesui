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
local Prof, Slots = module.Prof, module.EnchantSlots
local RW = CUI._RecipeWindow
if not (Prof and Slots and RW) then return end
local F = Prof.F
local Get = F.Get
local PALETTE = CUI.Kit.Palette

local ENCHANTING = 333
local MAX_ROWS, ROW = 8, 28
local CHAT = {
    "CHAT_MSG_WHISPER",
    "CHAT_MSG_PARTY",
    "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_INSTANCE_CHAT",
    "CHAT_MSG_INSTANCE_CHAT_LEADER",
}

local TE = { asked = {}, askers = 0 }

local function On() return F.Enabled() and Get("tradeEnchants") ~= false end

local function Bit(mask, n) return math.floor(mask / 2 ^ n) % 2 == 1 end

function TE.Fits(slot, class, subclass, inv)
    if slot[1] ~= class then return false end
    return (slot[3] == 0 or Bit(slot[3], subclass)) and (slot[2] == 0 or Bit(slot[2], inv))
end

function TE.Asked(guid, recipeID)
    local set = guid and TE.asked[guid]
    return set ~= nil and set[recipeID] == true
end

-- Enchant links in chat: remember who asked for what (the last 20 people).
function TE.OnChat(text, guid)
    if not (type(text) == "string" and type(guid) == "string") then return end
    if issecretvalue and (issecretvalue(text) or issecretvalue(guid)) then return end
    for id in text:gmatch("|Henchant:(%d+)") do
        id = tonumber(id)
        if Slots[id] then
            if not TE.asked[guid] then
                if TE.askers >= 20 then
                    wipe(TE.asked)
                    TE.askers = 0
                end
                TE.asked[guid], TE.askers = {}, TE.askers + 1
            end
            TE.asked[guid][id] = true
        end
    end
end

-- Your own Enchanting is open in the recipe window's backend.
function TE.EnchantingOpen()
    local frame = rawget(_G, "ProfessionsFrame")
    if not (frame and frame:IsShown() and RW.Data.Own()) then return false end
    local prof = RW.Data.Profession()
    return prof ~= nil and prof.id == ENCHANTING
end

-- The enchants you know that fit an item link, asked-for first, then the
-- highest level first.
function TE.List(link, guid)
    local list = {}
    local _, _, _, _, _, class, subclass = C_Item.GetItemInfoInstant(link)
    local inv = C_Item.GetItemInventoryTypeByID(link)
    if not (class and inv) then return list end
    for _, id in ipairs(C_TradeSkillUI.GetAllRecipeIDs() or {}) do
        local slot = Slots[id]
        if slot and TE.Fits(slot, class, subclass, inv) then
            local info = C_TradeSkillUI.GetRecipeInfo(id)
            if info and info.learned then list[#list + 1] = info end
        end
    end
    table.sort(list, function(lhs, rhs)
        local a, b = TE.Asked(guid, lhs.recipeID), TE.Asked(guid, rhs.recipeID)
        if a ~= b then return a end
        if (lhs.maxTrivialLevel or 0) ~= (rhs.maxTrivialLevel or 0) then
            return (lhs.maxTrivialLevel or 0) > (rhs.maxTrivialLevel or 0)
        end
        return lhs.name < rhs.name
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
local function PreClick(self)
    local go = self.recipeID ~= nil and not IsModifiedClick() and not SpellIsTargeting() and TE.EnchantingOpen()
    self:SetAttribute("type", go and "click" or nil)
    if go then C_TradeSkillUI.CraftRecipe(self.recipeID) end
end

local function NewRow(index)
    local row = CreateFrame("Frame", nil, panel)
    row:SetHeight(ROW - 2)
    row:SetPoint("TOPLEFT", 8, -34 - (index - 1) * ROW)
    row:SetPoint("TOPRIGHT", -8, -34 - (index - 1) * ROW)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(20, 20)
    row.icon:SetPoint("LEFT", 2, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local button = CUI.Kit.SecureButton(row, nil, "Enchant", 64, 22, { key = "essentials" })
    button:SetPoint("RIGHT")
    button:SetAttribute("clickbutton", rawget(_G, "TradeRecipientItem7ItemButton"))
    button:SetScript("PreClick", PreClick)
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

local function Build()
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
    panel.note:SetTextColor(unpack(PALETTE.muted))
    panel.note:SetJustifyH("LEFT")
    panel.note:SetWordWrap(true)
    panel.rows = {}
    panel:SetScript("OnMouseWheel", function(_, delta)
        state.offset = state.offset - delta
        TE.Render()
    end)
    panel:Hide()
end

function TE.Render()
    state.pending = false
    local link = state.trading and GetTradeTargetItemLink(TRADE_ENCHANT_SLOT or 7)
    if not (link and On() and C_SpellBook.IsSpellKnown(13262)) or InCombatLockdown() then
        if panel then panel:Hide() end
        return
    end
    if not panel then Build() end
    if panel.dismissed then return end
    local list = TE.EnchantingOpen() and TE.List(link, state.partner)
    local n = list and #list or 0
    state.offset = math.max(0, math.min(state.offset, n - MAX_ROWS))
    local shown = math.min(n, MAX_ROWS)
    for index = 1, shown do
        local info = list[index + state.offset]
        local row = panel.rows[index] or NewRow(index)
        row.icon:SetTexture(info.icon)
        row.name:SetText(info.name)
        row.note:SetText(TE.Asked(state.partner, info.recipeID) and "asked for" or "")
        row.button.recipeID = info.recipeID
        local ready = RW.Data.Craftable(info) > 0
        row.name:SetTextColor(unpack(ready and PALETTE.text or PALETTE.muted))
        row.button:SetEnabled(ready)
        row.button:SetAlpha(ready and 1 or 0.45)
        row:Show()
    end
    for index = shown + 1, #panel.rows do
        panel.rows[index]:Hide()
    end
    local note = not list and "Open Enchanting to list your enchants for this item."
        or n == 0 and "None of your enchants go on this item."
        or n > MAX_ROWS and ("%d enchants: scroll for more."):format(n)
        or ""
    panel.note:SetText(note)
    panel.note:ClearAllPoints()
    panel.note:SetPoint("TOPLEFT", 10, -36 - shown * ROW)
    panel.note:SetPoint("RIGHT", -10, 0)
    panel:SetHeight(42 + shown * ROW + (note ~= "" and 22 or 0))
    panel:ClearAllPoints()
    local trade = rawget(_G, "TradeFrame")
    if trade then
        panel:SetPoint("TOPLEFT", trade, "TOPRIGHT", 6, 0)
    else
        panel:SetPoint("CENTER")
    end
    panel:Show()
end

local function Queue()
    if state.pending then return end
    state.pending = true
    C_Timer.After(0.1, TE.Render)
end

local events = CreateFrame("Frame")
local OPEN = {
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
        return TE.OnChat(text, guid)
    elseif event == "TRADE_SHOW" then
        state.trading, state.partner, state.offset = true, UnitGUID("NPC"), 0
        if panel then panel.dismissed = nil end
        for _, e in ipairs(OPEN) do
            events:RegisterEvent(e)
        end
    elseif event == "TRADE_CLOSED" then
        state.trading, state.partner = false, nil
        for _, e in ipairs(OPEN) do
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
    Queue()
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
    for _, e in ipairs(CHAT) do
        pcall(events.RegisterEvent, events, e)
    end
end

CUI._TradeEnchants = { Apply = Apply, TE = TE }

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    Apply()
end)
