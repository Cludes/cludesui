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
local TOP_LINES, LINE = 8, 28
local TALK = {
    "CHAT_MSG_WHISPER",
    "CHAT_MSG_PARTY",
    "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_INSTANCE_CHAT",
    "CHAT_MSG_INSTANCE_CHAT_LEADER",
}

local TE = { asked = {}, askers = 0 }

local function On() return F.Enabled() and Get("tradeEnchants") ~= false end

local function Bit(mask, n) return math.floor(mask / 2 ^ n) % 2 == 1 end

function TE.Fits(slot, calling, subclass, inv)
    if slot[1] ~= calling then return false end
    return (slot[3] == 0 or Bit(slot[3], subclass)) and (slot[2] == 0 or Bit(slot[2], inv))
end

function TE.Asked(guid, recipeID)
    local assign = guid and TE.asked[guid]
    return assign ~= nil and assign[recipeID] == true
end

-- Enchant links in chat: remember who asked for what (the last 20 people).
function TE.OnChat(label, guid)
    if not (type(label) == "string" and type(guid) == "string") then return end
    if issecretvalue and (issecretvalue(label) or issecretvalue(guid)) then return end
    for id in label:gmatch("|Henchant:(%d+)") do
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
function TE.List(chain, guid)
    local roster = {}
    local _, _, _, _, _, calling, subclass = C_Item.GetItemInfoInstant(chain)
    local inv = C_Item.GetItemInventoryTypeByID(chain)
    if not (calling and inv) then return roster end
    for _, id in ipairs(C_TradeSkillUI.GetAllRecipeIDs() or {}) do
        local slot = Slots[id]
        if slot and TE.Fits(slot, calling, subclass, inv) then
            local info = C_TradeSkillUI.GetRecipeInfo(id)
            if info and info.learned then roster[#roster + 1] = info end
        end
    end
    table.sort(roster, function(lhs, rhs)
        local a, b = TE.Asked(guid, lhs.recipeID), TE.Asked(guid, rhs.recipeID)
        if a ~= b then return a end
        if (lhs.maxTrivialLevel or 0) ~= (rhs.maxTrivialLevel or 0) then
            return (lhs.maxTrivialLevel or 0) > (rhs.maxTrivialLevel or 0)
        end
        return lhs.name < rhs.name
    end)
    return roster
end

-------------------------------------------------------------------------------
--  The panel beside the trade window
-------------------------------------------------------------------------------
local pane
local status = { trading = false, offset = 0 }

-- The enchant goes up as a spell on the cursor; the same click then clicks
-- the trade window's "Will not be traded" item (a secure click), which casts
-- it there.
local function PreClick(self)
    local go = self.recipeID ~= nil and not IsModifiedClick() and not SpellIsTargeting() and TE.EnchantingOpen()
    self:SetAttribute("type", go and "click" or nil)
    if go then C_TradeSkillUI.CraftRecipe(self.recipeID) end
end

local function FreshLine(catalog)
    local line = CreateFrame("Frame", nil, pane)
    line:SetHeight(LINE - 2)
    line:SetPoint("TOPLEFT", 8, -34 - (catalog - 1) * LINE)
    line:SetPoint("TOPRIGHT", -8, -34 - (catalog - 1) * LINE)
    line.icon = line:CreateTexture(nil, "ARTWORK")
    line.icon:SetSize(20, 20)
    line.icon:SetPoint("LEFT", 2, 0)
    line.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local btn = CUI.Kit.SecureButton(line, nil, "Enchant", 64, 22, { key = "essentials" })
    btn:SetPoint("RIGHT")
    btn:SetAttribute("clickbutton", rawget(_G, "TradeRecipientItem7ItemButton"))
    btn:SetScript("PreClick", PreClick)
    btn:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Casts this enchant on the item they put in the trade window.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    btn:HookScript("OnLeave", GameTooltip_Hide)
    line.button = btn
    line.note = line:CreateFontString(nil, "OVERLAY")
    CUI.Kit.Font(line.note, CUI.Kit.SMALL_SIZE, "essentials")
    line.note:SetPoint("RIGHT", btn, "LEFT", -6, 0)
    line.note:SetTextColor(CUI.Kit.Accent())
    line.name = line:CreateFontString(nil, "OVERLAY")
    CUI.Kit.Font(line.name, CUI.Kit.TEXT_SIZE, "essentials")
    line.name:SetPoint("LEFT", line.icon, "RIGHT", 8, 0)
    line.name:SetPoint("RIGHT", line.note, "LEFT", -6, 0)
    line.name:SetJustifyH("LEFT")
    line.name:SetWordWrap(false)
    pane.rows[catalog] = line
    return line
end

local function Make()
    pane = CreateFrame("Frame", "CludesUITradeEnchants", UIParent)
    pane:SetSize(300, 60)
    pane:SetFrameStrata("HIGH")
    pane:EnableMouse(true)
    pane:EnableMouseWheel(true)
    CUI.Kit.Panel(pane, 0.97)
    CUI.Kit.Header(pane, "Trade Enchants", function()
        pane.dismissed = true
        pane:Hide()
    end, { key = "essentials", closeTip = "Hides this until the next trade." })
    pane.note = pane:CreateFontString(nil, "OVERLAY")
    CUI.Kit.Font(pane.note, CUI.Kit.SMALL_SIZE, "essentials")
    pane.note:SetTextColor(unpack(PALETTE.muted))
    pane.note:SetJustifyH("LEFT")
    pane.note:SetWordWrap(true)
    pane.rows = {}
    pane:SetScript("OnMouseWheel", function(_, delta)
        status.offset = status.offset - delta
        TE.Render()
    end)
    pane:Hide()
end

function TE.Render()
    status.pending = false
    local chain = status.trading and GetTradeTargetItemLink(TRADE_ENCHANT_SLOT or 7)
    if not (chain and On() and C_SpellBook.IsSpellKnown(13262)) or InCombatLockdown() then
        if pane then pane:Hide() end
        return
    end
    if not pane then Make() end
    if pane.dismissed then return end
    local roster = TE.EnchantingOpen() and TE.List(chain, status.partner)
    local n = roster and #roster or 0
    status.offset = math.max(0, math.min(status.offset, n - TOP_LINES))
    local shown = math.min(n, TOP_LINES)
    for catalog = 1, shown do
        local info = roster[catalog + status.offset]
        local line = pane.rows[catalog] or FreshLine(catalog)
        line.icon:SetTexture(info.icon)
        line.name:SetText(info.name)
        line.note:SetText(TE.Asked(status.partner, info.recipeID) and "asked for" or "")
        line.button.recipeID = info.recipeID
        local ready = RW.Data.Craftable(info) > 0
        line.name:SetTextColor(unpack(ready and PALETTE.text or PALETTE.muted))
        line.button:SetEnabled(ready)
        line.button:SetAlpha(ready and 1 or 0.45)
        line:Show()
    end
    for catalog = shown + 1, #pane.rows do
        pane.rows[catalog]:Hide()
    end
    local jot = not roster and "Open Enchanting to list your enchants for this item."
        or n == 0 and "None of your enchants go on this item."
        or n > TOP_LINES and ("%d enchants: scroll for more."):format(n)
        or ""
    pane.note:SetText(jot)
    pane.note:ClearAllPoints()
    pane.note:SetPoint("TOPLEFT", 10, -36 - shown * LINE)
    pane.note:SetPoint("RIGHT", -10, 0)
    pane:SetHeight(42 + shown * LINE + (jot ~= "" and 22 or 0))
    pane:ClearAllPoints()
    local trade = rawget(_G, "TradeFrame")
    if trade then
        pane:SetPoint("TOPLEFT", trade, "TOPRIGHT", 6, 0)
    else
        pane:SetPoint("CENTER")
    end
    pane:Show()
end

local function Line()
    if status.pending then return end
    status.pending = true
    C_Timer.After(0.1, TE.Render)
end

local events = CreateFrame("Frame")
local REVEAL = {
    "TRADE_SKILL_SHOW",
    "TRADE_SKILL_CLOSE",
    "TRADE_SKILL_LIST_UPDATE",
    "BAG_UPDATE_DELAYED",
    "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED",
}
events:SetScript("OnEvent", function(_, event, ...)
    if event:find("^CHAT_MSG_") then
        local label, _, _, _, _, _, _, _, _, _, _, guid = ...
        return TE.OnChat(label, guid)
    elseif event == "TRADE_SHOW" then
        status.trading, status.partner, status.offset = true, UnitGUID("NPC"), 0
        if pane then pane.dismissed = nil end
        for _, e in ipairs(REVEAL) do
            events:RegisterEvent(e)
        end
    elseif event == "TRADE_CLOSED" then
        status.trading, status.partner = false, nil
        for _, e in ipairs(REVEAL) do
            events:UnregisterEvent(e)
        end
        if pane and not InCombatLockdown() then pane:Hide() end
        return
    elseif event == "TRADE_TARGET_ITEM_CHANGED" then
        if ... ~= (TRADE_ENCHANT_SLOT or 7) then return end
        status.offset = 0
    elseif event == "PLAYER_REGEN_DISABLED" then
        if pane then pane:Hide() end
        return
    end
    Line()
end)

local function Apply()
    events:UnregisterAllEvents()
    if not On() then
        status.trading = false
        if pane and not InCombatLockdown() then pane:Hide() end
        return
    end
    for _, e in ipairs({ "TRADE_SHOW", "TRADE_CLOSED", "TRADE_TARGET_ITEM_CHANGED" }) do
        events:RegisterEvent(e)
    end
    for _, e in ipairs(TALK) do
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
