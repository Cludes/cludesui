if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
if not (CUI and CUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_CraftWindowPlus.lua  (WoW Forever only)
--  Title bar extras for the recipe window (CludesUIForeverEssentials_
--  CraftWindow.lua):
--    Alts   your other characters' professions on this realm and faction:
--           each character saves its own profession links when it opens
--           them, and picking one opens it here as a linked view
--    Link   posts the open profession's trade link to party, raid, guild,
--           your target, or into the chat box
--    Skill-up Plan  the fewest crafts from your skill to your cap
--    Orders on someone else's profession: an order column (recipes, crafts,
--           the materials you bring, one tip) and Ask / Invite
-------------------------------------------------------------------------------
local _, module = ...
local Prof = module.Prof
local RW = CUI._RecipeWindow
if not (Prof and RW) then return end
local F = Prof.F
local Get = F.Get
local T = C_TradeSkillUI

local OPEN_WAIT = 5

-------------------------------------------------------------------------------
--  Alts: saved per character (by GUID) in the account-wide professions store
-------------------------------------------------------------------------------
local Alts = {}

local function AltsOn() return F.Enabled() and Get("altProfessions") ~= false end

local function Store()
    local conf = F.Cfg()
    conf.profLinks = conf.profLinks or {}
    return conf.profLinks
end

-- Drop links for professions this character no longer has.
local function Forget(links)
    local have = {}
    for _, index in pairs({ GetProfessions() }) do
        local line = select(7, GetProfessionInfo(index))
        if line then have[line] = true end
    end
    for id in pairs(links) do
        if not have[id] then links[id] = nil end
    end
end

function Alts.Save()
    if not (AltsOn() and RW.Data.Own() and T.CanTradeSkillListLink and T.CanTradeSkillListLink()) then return end
    local base = T.GetBaseProfessionInfo()
    local id = base and base.professionID
    local link = id and id > 0 and T.GetTradeSkillListLink()
    local guid = UnitGUID("player")
    if not (link and guid) then return end
    local mine = Store()[guid] or {}
    Store()[guid] = mine
    mine.name, mine.class = UnitName("player"), select(2, UnitClass("player"))
    mine.realm, mine.faction = GetRealmName(), UnitFactionGroup("player")
    mine.links = mine.links or {}
    mine.links[id] = { link = link, name = base.professionName }
    Forget(mine.links)
end

-- Other characters on this realm and faction, by name then profession.
function Alts.List()
    local list = {}
    local me, realm, faction = UnitGUID("player"), GetRealmName(), UnitFactionGroup("player")
    for guid, alt in pairs(F.Cfg().profLinks or {}) do
        if guid ~= me and alt.realm == realm and alt.faction == faction then
            for _, saved in pairs(alt.links or {}) do
                list[#list + 1] = { who = alt.name, class = alt.class, prof = saved.name, link = saved.link }
            end
        end
    end
    table.sort(list, function(lhs, rhs)
        if lhs.who ~= rhs.who then return lhs.who < rhs.who end
        return lhs.prof < rhs.prof
    end)
    return list
end

local opens = 0
function Alts.Open(alt)
    local target = alt.link:match("|H(.-)|h")
    if not target then return end
    opens = opens + 1
    local mine = opens
    SetItemRef(target, alt.link, "LeftButton")
    C_Timer.After(OPEN_WAIT, function()
        if mine == opens and not RW.Data.Linked() then
            CUI.Print(("%s's %s did not open."):format(alt.who, alt.prof))
        end
    end)
end

function Alts.Menu(owner)
    CUI.Kit.ContextMenu(owner, function(_, root)
        root:CreateTitle("Your Alts' Professions")
        for _, alt in ipairs(Alts.List()) do
            local c = CUI.GetClassColor(alt.class)
            local text = CUI.HexColor(c.r, c.g, c.b) .. alt.who .. "|r - " .. alt.prof
            root:CreateButton(text, function() Alts.Open(alt) end)
        end
    end)
end

-------------------------------------------------------------------------------
--  Link: post the open profession's trade link
-------------------------------------------------------------------------------
local Link = {}

function Link.Can()
    return RW.Data.Own() and T.CanTradeSkillListLink and T.CanTradeSkillListLink() == true
end

local function Send(channel, to)
    local link = T.GetTradeSkillListLink()
    if not link then return end
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    send(link, channel, nil, to)
end

local function FriendlyTarget()
    if UnitIsPlayer("target") and UnitIsFriend("player", "target") and not UnitIsUnit("player", "target") then
        local name, realm = UnitName("target")
        return realm and realm ~= "" and (name .. "-" .. realm) or name
    end
end

function Link.Menu(owner)
    local locked = C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown()
    local target = FriendlyTarget()
    CUI.Kit.ContextMenu(owner, function(_, root)
        root:CreateTitle("Link your profession")
        if not locked then
            if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
                root:CreateButton("Instance", function() Send("INSTANCE_CHAT") end)
            elseif IsInRaid() then
                root:CreateButton("Raid", function() Send("RAID") end)
            elseif IsInGroup() then
                root:CreateButton("Party", function() Send("PARTY") end)
            end
            if IsInGuild() then root:CreateButton("Guild", function() Send("GUILD") end) end
            if target then root:CreateButton("Whisper " .. target, function() Send("WHISPER", target) end) end
        end
        root:CreateButton("Into the chat box", function()
            local link = T.GetTradeSkillListLink()
            if link and not ChatEdit_InsertLink(link) then ChatFrame_OpenChat(link) end
        end)
    end)
end

-------------------------------------------------------------------------------
--  Craft orders: on someone else's profession (not your alt's), pick recipes,
--  how many, which materials you bring and a tip, then ask them in one go
--  (party chat when they are in your party, else a whisper). Kept for the
--  session, per crafter.
-------------------------------------------------------------------------------
local Orders = { MAX = 9, byCrafter = {} }
local MAX_MESSAGE, MESSAGE_GAP = 255, 0.4
local ASK = {
    "Could you make %dx %s for me?",
    "Would you be able to craft %dx %s for me?",
    "Any chance of %dx %s from you?",
    "Could I order %dx %s from you?",
}
local INVITE = {
    "Hi! Inviting you for a few crafts from your profession, tip included.",
    "Hey, sending an invite: I'd like to order some crafts from you.",
    "Hi there, invite on its way. Got a small crafting order for you if you're free.",
}
local MUTED, TEXT = { 0.64, 0.68, 0.71 }, { 0.9, 0.91, 0.92 }

local picks = {}
local function Pick(lines)
    local n = (picks[lines] or 0) % #lines + 1
    picks[lines] = n
    return lines[n]
end

local function Bare(name) return name and Ambiguate(name, "none") end

function Orders.On()
    local who = RW.State.linked
    if not (F.Enabled() and Get("craftOrders") ~= false and who and who ~= "") then return false end
    for _, alt in ipairs(Alts.List()) do
        if alt.who == Bare(who) then return false end
    end
    return true
end

function Orders.Get()
    local who = RW.State.linked
    if not who or who == "" then return end
    local o = Orders.byCrafter[who]
    if not o then
        o = { who = who, list = {}, drafts = {} }
        Orders.byCrafter[who] = o
    end
    return o
end

function Orders.Draft(info)
    local o = info and Orders.Get()
    if not o then return end
    local d = o.drafts[info.recipeID]
    if not d then
        d = {
            recipeID = info.recipeID,
            name = info.name,
            icon = info.icon,
            output = RW.Data.Output(info.recipeID),
            crafts = 1,
            bring = {},
        }
        o.drafts[info.recipeID] = d
    end
    d.reagents = RW.Data.Reagents(info.recipeID)
    return d
end

function Orders.Index(o, d)
    for index, entry in ipairs(o.list) do
        if entry == d then return index end
    end
end

-- "2g 50s", "75s", "30c", or "2.5" for gold. Empty gives nil.
function Orders.Parse(text)
    text = (text or ""):lower():gsub("%s", "")
    if text == "" then return end
    local gold = tonumber(text)
    if gold then return math.max(0, math.floor(gold * 10000 + 0.5)) end
    local total = 0
    local rest = text:gsub("([%d%.]+)([gsc])", function(amount, coin)
        total = total + (tonumber(amount) or 0) * (coin == "g" and 10000 or coin == "s" and 100 or 1)
        return ""
    end)
    if rest ~= "" then return end
    return math.floor(total + 0.5)
end

function Orders.Money(copper)
    local gold, silver, rest = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if gold > 0 then parts[#parts + 1] = gold .. "g" end
    if silver > 0 then parts[#parts + 1] = silver .. "s" end
    if rest > 0 or #parts == 0 then parts[#parts + 1] = rest .. "c" end
    return table.concat(parts, " ")
end

local function ItemLink(itemID, fallback)
    local _, link = C_Item.GetItemInfo(itemID)
    return link or ("[" .. (RW.Data.ItemName(itemID) or fallback or ("Item " .. itemID)) .. "]")
end

-- How many of a draft's materials you bring: brought, total.
function Orders.Brings(d)
    local brought = 0
    for _, reagent in ipairs(d.reagents) do
        if d.bring[reagent.itemID] then brought = brought + 1 end
    end
    return brought, #d.reagents
end

local function Split(pieces)
    local out, line = {}, ""
    for _, piece in ipairs(pieces) do
        local joined = line == "" and piece or (line .. " " .. piece)
        if #joined > MAX_MESSAGE and line ~= "" then
            out[#out + 1], line = line, piece
        else
            line = joined
        end
    end
    if line ~= "" then out[#out + 1] = line end
    return out
end

-- One message (or more, past 255 letters) per craft; the tip on the last.
function Orders.Messages(o, prefix)
    local messages = {}
    for index, d in ipairs(o.list) do
        local what = d.output and ItemLink(d.output, d.name)
            or C_TradeSkillUI.GetRecipeLink(d.recipeID)
            or ("[" .. d.name .. "]")
        local ask = Pick(ASK):format(d.crafts, what)
        if prefix then ask = prefix .. ", " .. ask:sub(1, 1):lower() .. ask:sub(2) end
        local pieces, mats = { ask }, {}
        for _, reagent in ipairs(d.reagents) do
            if d.bring[reagent.itemID] then
                mats[#mats + 1] = ("%dx %s"):format(reagent.need * d.crafts, ItemLink(reagent.itemID))
            end
        end
        if #mats > 0 then
            pieces[#pieces + 1] = "I'll bring"
            for at, mat in ipairs(mats) do
                pieces[#pieces + 1] = mat .. (at < #mats and "," or ".")
            end
        elseif #d.reagents > 0 then
            pieces[#pieces + 1] = "Your materials, please."
        end
        if index == #o.list and o.tip and o.tip > 0 then
            pieces[#pieces + 1] = ("Tip: %s%s."):format(Orders.Money(o.tip), #o.list > 1 and " for the lot" or "")
        end
        for _, message in ipairs(Split(pieces)) do
            messages[#messages + 1] = message
        end
    end
    return messages
end

-- PARTY (or INSTANCE_CHAT) when the crafter is in your party, else WHISPER.
function Orders.Channel(o)
    if not IsInGroup() or IsInRaid() then return "WHISPER" end
    for index = 1, GetNumSubgroupMembers() do
        if Bare(GetUnitName("party" .. index, true)) == Bare(o.who) then
            return IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and "INSTANCE_CHAT" or "PARTY"
        end
    end
    return "WHISPER"
end

function Orders.Send()
    local o = Orders.Get()
    if not (o and #o.list > 0) then return end
    local channel = Orders.Channel(o)
    local short = Ambiguate(o.who, "short")
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    for index, message in ipairs(Orders.Messages(o, channel ~= "WHISPER" and short or nil)) do
        C_Timer.After((index - 1) * MESSAGE_GAP, function()
            send(message, channel, nil, channel == "WHISPER" and o.who or nil)
        end)
    end
    o.sent = ("Asked %s %sfor %s."):format(
        short,
        channel == "WHISPER" and "" or channel == "PARTY" and "in party chat " or "in instance chat ",
        #o.list == 1 and "1 craft" or (#o.list .. " crafts")
    )
    wipe(o.list)
    wipe(o.drafts)
    o.tip = nil
end

function Orders.Invite()
    local o = Orders.Get()
    if not o then return end
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    send(Pick(INVITE), "WHISPER", nil, o.who)
    local invite = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
    invite(o.who)
end

-------------------------------------------------------------------------------
--  Orders in the window: the footer under the picked recipe, "I bring" ticks
--  on the reagents, and the order column on the window's left edge
-------------------------------------------------------------------------------
local Panel = {}

local function Label(parent, size, colour)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    CUI.Kit.Font(fs, size, "essentials")
    fs:SetTextColor(colour[1], colour[2], colour[3])
    fs:SetWordWrap(false)
    return fs
end

local function Changed() RW.Render() end

local function Current() return Orders.On() and Orders.Draft(RW.Window.Selected()) or nil end

local function SetCrafts(n)
    local d = Current()
    if not d then return end
    d.crafts = math.max(1, math.min(99, n))
    Changed()
end

local function BuildFooter(pane)
    local Kit = CUI.Kit
    local foot = CreateFrame("Frame", nil, pane)
    foot:SetAllPoints(pane.foot)
    foot:Hide()
    foot.add = Kit.Button(foot, "Add to Order", 130, 30, function()
        local d, o = Current(), Orders.Get()
        if not (d and o) then return end
        local at = Orders.Index(o, d)
        if at then
            table.remove(o.list, at)
        elseif #o.list < Orders.MAX then
            o.list[#o.list + 1], o.sent = d, nil
        end
        Changed()
    end, {
        key = "essentials",
        size = 13,
        tip = "Puts this recipe on the order, with the crafts and the materials you bring. Up to 9 recipes.",
    })
    foot.add:SetPoint("RIGHT")
    foot.add:SetActive(true)
    local plus = Kit.Button(foot, "+", 26, 30, function()
        local d = Current()
        if d then SetCrafts(d.crafts + 1) end
    end, { key = "essentials" })
    plus:SetPoint("RIGHT", foot.add, "LEFT", -10, 0)
    foot.qty = Kit.Input(foot, 40, 30, nil, "essentials")
    foot.qty:SetNumeric(true)
    foot.qty:SetMaxLetters(2)
    foot.qty:SetJustifyH("CENTER")
    foot.qty:SetPoint("RIGHT", plus, "LEFT", -2, 0)
    foot.qty:SetScript("OnTextChanged", function(self, user)
        local n = tonumber(self:GetText() or "")
        if user and n and n > 0 then SetCrafts(n) end
    end)
    local minus = Kit.Button(foot, "-", 26, 30, function()
        local d = Current()
        if d then SetCrafts(d.crafts - 1) end
    end, { key = "essentials" })
    minus:SetPoint("RIGHT", foot.qty, "LEFT", -2, 0)
    local label = Label(foot, 13, MUTED)
    label:SetPoint("RIGHT", minus, "LEFT", -10, 0)
    label:SetText("Crafts")
    pane.orderFoot = foot
end

local function BringCheck(row)
    if row.bringCheck then return row.bringCheck end
    local check = CUI.Kit.Check(row, "", function(self)
        local d = Current()
        if d and row.itemID then d.bring[row.itemID] = self:GetChecked() or nil end
        Changed()
    end, "essentials")
    check:SetPoint("RIGHT", -22, 0)
    row.bringCheck = check
    return check
end

function Panel.Detail(info)
    local pane = RW.Window.Win().detail
    if not pane.orderFoot then BuildFooter(pane) end
    local d = Orders.On() and Orders.Draft(info) or nil
    pane.orderFoot:SetShown(d ~= nil)
    pane.footRule:SetShown(d ~= nil or not RW.State.linked)
    pane.reagents.bankHead:SetText(d and "I BRING" or "BANK")
    for _, row in ipairs(pane.reagents.rows) do
        local check = (d or row.bringCheck) and BringCheck(row)
        if check then
            check:SetShown(d ~= nil and row:IsShown())
            check:SetChecked(d ~= nil and row.itemID ~= nil and d.bring[row.itemID] == true)
        end
        row.bank:SetShown(d == nil)
    end
    if not d then return end
    local o = Orders.Get()
    local added = Orders.Index(o, d)
    pane.orderFoot.add:SetText(added and "Remove" or "Add to Order")
    pane.orderFoot.add:SetEnabled(added ~= nil or #o.list < Orders.MAX)
    if not pane.orderFoot.qty:HasFocus() then pane.orderFoot.qty:SetText(tostring(d.crafts)) end
end

local ROW_H = 40

local function NewOrderRow(col, index)
    local row = CreateFrame("Button", nil, col)
    row:SetHeight(ROW_H - 4)
    row:SetPoint("TOPLEFT", 6, -58 - (index - 1) * ROW_H)
    row:SetPoint("TOPRIGHT", -6, -58 - (index - 1) * ROW_H)
    row.hover = row:CreateTexture(nil, "HIGHLIGHT")
    row.hover:SetAllPoints()
    row.hover:SetColorTexture(1, 1, 1, 0.04)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(26, 26)
    row.icon:SetPoint("LEFT", 4, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.remove = CUI.Kit.Glyph(row, "x", function()
        local o = Orders.Get()
        local at = o and Orders.Index(o, row.draft)
        if at then table.remove(o.list, at) end
        Changed()
    end, "Take this craft off the order.", "essentials")
    row.remove:SetPoint("RIGHT", -4, 0)
    row.name = Label(row, 12.5, TEXT)
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, -1)
    row.name:SetPoint("RIGHT", row.remove, "LEFT", -6, 0)
    row.name:SetJustifyH("LEFT")
    row.sub = Label(row, 11, MUTED)
    row.sub:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
    row.sub:SetPoint("RIGHT", row.remove, "LEFT", -6, 0)
    row.sub:SetJustifyH("LEFT")
    row:SetScript("OnClick", function(self)
        if self.draft then
            RW.State.selected = self.draft.recipeID
            Changed()
        end
    end)
    return row
end

local function BuildColumn()
    local Kit = CUI.Kit
    local win = RW.Window.Win()
    local col = CreateFrame("Frame", nil, win)
    col:SetPoint("TOPRIGHT", win, "TOPLEFT", -4, 0)
    col:SetPoint("BOTTOMRIGHT", win, "BOTTOMLEFT", -4, 0)
    col:SetWidth(260)
    col:EnableMouse(true)
    Kit.Panel(col, 0.97)
    col.label = Label(col, 11, MUTED)
    col.label:SetPoint("TOPLEFT", 12, -12)
    col.label:SetText("ORDER FOR")
    col.title = Label(col, 16, TEXT)
    col.title:SetPoint("TOPLEFT", col.label, "BOTTOMLEFT", 0, -4)
    col.title:SetPoint("RIGHT", -84, 0)
    col.title:SetJustifyH("LEFT")
    col.invite = Kit.Button(col, "Invite", 64, 24, function()
        Orders.Invite()
        Changed()
    end, {
        key = "essentials",
        tip = "Invites them to your group with a short whisper. Once they are in your party, Ask uses party chat.",
    })
    col.invite:SetPoint("TOPRIGHT", -10, -14)
    col.rows = {}
    for index = 1, Orders.MAX do
        col.rows[index] = NewOrderRow(col, index)
    end
    col.empty = Label(col, 12, MUTED)
    col.empty:SetPoint("TOPLEFT", 14, -64)
    col.empty:SetPoint("RIGHT", -14, 0)
    col.empty:SetJustifyH("LEFT")
    col.empty:SetWordWrap(true)
    col.ask = Kit.Button(col, "Ask by Whisper", 150, 28, function()
        col.tip:ClearFocus()
        Orders.Send()
        Changed()
    end, {
        key = "essentials",
        tip = "Sends one message per craft: how many, the materials you bring, and your tip on the last one. The order empties once sent.",
    })
    col.ask:SetPoint("BOTTOMLEFT", 10, 10)
    col.ask:SetActive(true)
    col.clear = Kit.Button(col, "Clear", 80, 28, function()
        local o = Orders.Get()
        if o then wipe(o.list) end
        Changed()
    end, { key = "essentials", tip = "Empties the order without sending it." })
    col.clear:SetPoint("BOTTOMRIGHT", -10, 10)
    col.tip = Kit.Input(col, 110, 26, "e.g. 2g 50s", "essentials")
    col.tip:SetMaxLetters(16)
    col.tip:SetPoint("BOTTOMRIGHT", col.clear, "TOPRIGHT", 0, 10)
    col.tip:HookScript("OnEditFocusLost", function(self)
        local o = Orders.Get()
        if o then o.tip = Orders.Parse(self:GetText()) end
        Changed()
    end)
    local tipLabel = Label(col, 12.5, MUTED)
    tipLabel:SetPoint("BOTTOMLEFT", col.ask, "TOPLEFT", 2, 16)
    tipLabel:SetText("Tip for the order")
    Panel.col = col
    return col
end

function Panel.Render()
    local on = Orders.On()
    if not (on or Panel.col) then return end
    local col = Panel.col or BuildColumn()
    col:SetShown(on)
    if not on then return end
    local o = Orders.Get()
    col.title:SetText(Ambiguate(o.who, "short"))
    local mayInvite = not IsInGroup() or UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
    col.invite:SetEnabled(Orders.Channel(o) == "WHISPER" and mayInvite)
    for index, row in ipairs(col.rows) do
        local d = o.list[index]
        row.draft = d
        row:SetShown(d ~= nil)
        if d then
            row.icon:SetTexture(d.icon or (d.output and C_Item.GetItemIconByID(d.output)) or 134400)
            row.name:SetText(("%dx %s"):format(d.crafts, d.name))
            local brought, total = Orders.Brings(d)
            row.sub:SetText(
                total == 0 and "" or brought == 0 and "Their materials"
                    or brought == total and "You bring all materials"
                    or ("You bring %d of %d materials"):format(brought, total)
            )
        end
    end
    col.empty:SetShown(#o.list == 0)
    col.empty:SetText(o.sent or "Pick a recipe, set the crafts, tick the materials you bring, then Add to Order.")
    if o.sent then
        col.empty:SetTextColor(CUI.Kit.Accent())
    else
        col.empty:SetTextColor(MUTED[1], MUTED[2], MUTED[3])
    end
    if not col.tip:HasFocus() then col.tip:SetText(o.tip and Orders.Money(o.tip) or "") end
    local channel = Orders.Channel(o)
    col.ask:SetText(channel == "WHISPER" and "Ask by Whisper" or channel == "PARTY" and "Ask in Party" or "Ask in Instance")
    col.ask:SetEnabled(#o.list > 0)
    col.clear:SetEnabled(#o.list > 0)
end

table.insert(RW.Window.hooks.detail, Panel.Detail)
table.insert(RW.Window.hooks.render, Panel.Render)

-------------------------------------------------------------------------------
--  Skill-up Plan: the fewest crafts from your skill to your cap, from the
--  recipes you know plus trainer recipes you can learn on the way (no
--  cooldown recipes). Each point takes the recipe likeliest to raise it,
--  fewer materials breaking ties; a pick holds until another is clearly
--  (10%) better, so the plan does not flip back and forth.
-------------------------------------------------------------------------------
local Plan = {}
local STICKY = 0.9

local function MaterialCount(recipeID)
    local n = 0
    for _, reagent in ipairs(RW.Data.Reagents(recipeID)) do
        n = n + reagent.need
    end
    return n
end

local function HasCooldown(recipeID)
    local ok, cooldown, isDaily, charges = pcall(C_TradeSkillUI.GetRecipeCooldown, recipeID)
    return ok and ((cooldown or 0) > 0 or isDaily == true or (charges or 0) > 0)
end

function Plan.Candidates()
    local list, SU = {}, RW.SkillUps
    for _, cat in ipairs(RW.State.categories or {}) do
        for _, info in ipairs(cat.recipes) do
            local learn, yellow, grey = SU.Range(info.recipeID, info.maxTrivialLevel)
            if yellow and not HasCooldown(info.recipeID) then
                list[#list + 1] = {
                    id = info.recipeID,
                    name = info.name,
                    icon = info.icon,
                    from = learn or 0,
                    yellow = yellow,
                    grey = grey,
                    mats = MaterialCount(info.recipeID),
                }
            end
        end
    end
    local max = RW.State.prof and RW.State.prof.max or 0
    for _, entry in ipairs(RW.State.unlearned or {}) do
        local r = entry.r
        if (r.source == "trainer" or r.source == "teacher") and r.yellow and r.grey and entry.need < max then
            list[#list + 1] = {
                spell = r.spell,
                name = C_Spell.GetSpellName(r.spell) or ("Recipe " .. r.spell),
                icon = C_Spell.GetSpellTexture(r.spell),
                from = entry.need,
                yellow = r.yellow,
                grey = r.grey,
                mats = 0,
                train = true,
            }
        end
    end
    return list
end

-- { steps = { {c, from, to, crafts, band} }, crafts, skill, max, stuck }
function Plan.Build()
    local prof = RW.State.prof
    local skill, max = RW.SkillUps.Skill(), prof.max
    local plan = { steps = {}, crafts = 0, skill = skill, max = max }
    local candidates, pick, pickScore = Plan.Candidates(), nil, nil
    for at = skill, max - 1 do
        local best, bestScore
        for _, c in ipairs(candidates) do
            if c.from <= at and at < c.grey then
                local chance = RW.SkillUps.Chance(at, c.yellow, c.grey)
                local score = 1 / chance + c.mats * 0.001
                if not bestScore or score < bestScore then best, bestScore = c, score end
            end
        end
        if pick and pick.from <= at and at < pick.grey then
            pickScore = 1 / RW.SkillUps.Chance(at, pick.yellow, pick.grey) + pick.mats * 0.001
            if bestScore and bestScore >= pickScore * STICKY then best, bestScore = pick, pickScore end
        end
        if not best then
            plan.stuck = at
            break
        end
        pick = best
        local chance, band = RW.SkillUps.Chance(at, best.yellow, best.grey)
        local step = plan.steps[#plan.steps]
        if not (step and step.c == best) then
            step = { c = best, from = at, to = at, crafts = 0, band = band }
            plan.steps[#plan.steps + 1] = step
        end
        step.to = at + 1
        step.crafts = step.crafts + 1 / chance
        plan.crafts = plan.crafts + 1 / chance
    end
    return plan
end

local PLAN_ROWS, PLAN_ROW = 18, 22

local function BuildPlanPane()
    local win = RW.Window.Win()
    local pane = CreateFrame("Frame", nil, win)
    pane:SetPoint("TOPLEFT", win.aside, "TOPRIGHT", 0, 0)
    pane:SetPoint("BOTTOMRIGHT", -1, 1)
    pane:Hide()
    pane.title = Label(pane, 18, TEXT)
    pane.title:SetPoint("TOPLEFT", 18, -18)
    pane.title:SetText("Skill-up Plan")
    pane.sub = Label(pane, 12.5, MUTED)
    pane.sub:SetPoint("TOPLEFT", pane.title, "BOTTOMLEFT", 0, -5)
    pane.close = CUI.Kit.Button(pane, "Back", 64, 24, function()
        Plan.open = false
        Changed()
    end, { key = "essentials" })
    pane.close:SetPoint("TOPRIGHT", -18, -18)
    pane.rows = {}
    for index = 1, PLAN_ROWS do
        local row = CreateFrame("Button", nil, pane)
        row:SetHeight(PLAN_ROW)
        row:SetPoint("TOPLEFT", 12, -66 - (index - 1) * PLAN_ROW)
        row:SetPoint("TOPRIGHT", -12, -66 - (index - 1) * PLAN_ROW)
        row.hover = row:CreateTexture(nil, "HIGHLIGHT")
        row.hover:SetAllPoints()
        row.hover:SetColorTexture(1, 1, 1, 0.04)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(17, 17)
        row.icon:SetPoint("LEFT", 6, 0)
        row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        row.crafts = Label(row, 12.5, TEXT)
        row.crafts:SetPoint("RIGHT", -6, 0)
        row.crafts:SetWidth(44)
        row.crafts:SetJustifyH("RIGHT")
        row.range = Label(row, 12, MUTED)
        row.range:SetPoint("RIGHT", row.crafts, "LEFT", -8, 0)
        row.range:SetWidth(64)
        row.range:SetJustifyH("RIGHT")
        row.name = Label(row, 13, TEXT)
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
        row.name:SetPoint("RIGHT", row.range, "LEFT", -8, 0)
        row.name:SetJustifyH("LEFT")
        row:SetScript("OnClick", function(self)
            if self.step and self.step.c.id then
                Plan.open = false
                RW.State.selected = self.step.c.id
                Changed()
            end
        end)
        pane.rows[index] = row
    end
    pane.more = Label(pane, 12, MUTED)
    pane.more:SetPoint("TOPLEFT", pane.rows[PLAN_ROWS], "BOTTOMLEFT", 6, -4)
    pane.total = Label(pane, 13, TEXT)
    pane.total:SetPoint("BOTTOMLEFT", 18, 38)
    pane.note = Label(pane, 11.5, MUTED)
    pane.note:SetPoint("BOTTOMLEFT", 18, 18)
    pane.note:SetText("Crafts are averages: the game rolls each skill-up.")
    Plan.pane = pane
    return pane
end

function Plan.Shown()
    return Plan.open and RW.State.prof and not RW.State.linked and RW.State.tab == "learned"
end

function Plan.Render()
    if not Plan.Shown() then
        if Plan.pane then Plan.pane:Hide() end
        return
    end
    local win = RW.Window.Win()
    local pane = Plan.pane or BuildPlanPane()
    win.detail:Hide()
    win.learn:Hide()
    win.empty:Hide()
    pane:Show()
    local plan, colours = Plan.Build(), RW.Colour.difficulty
    if plan.skill >= plan.max then
        pane.sub:SetText(("At your cap of %d."):format(plan.max))
    elseif plan.stuck and #plan.steps == 0 then
        pane.sub:SetText(("Nothing you know or can train raises you past %d."):format(plan.stuck))
    else
        pane.sub:SetText(("From %d to your cap of %d"):format(plan.skill, plan.max))
    end
    for index, row in ipairs(pane.rows) do
        local step = plan.steps[index]
        row.step = step
        row:SetShown(step ~= nil)
        if step then
            local c = step.c
            row.icon:SetTexture(c.icon or 134400)
            if c.train then
                local ready = c.from <= plan.skill
                row.name:SetText((ready and "Train: " or ("Train at %d: "):format(c.from)) .. c.name)
                local colour = ready and { 0.37, 0.77, 0.42 } or MUTED
                row.name:SetTextColor(colour[1], colour[2], colour[3])
            else
                row.name:SetText(c.name)
                local colour = colours[step.band] or TEXT
                row.name:SetTextColor(colour[1], colour[2], colour[3])
            end
            row.range:SetText(step.from .. "-" .. step.to)
            row.crafts:SetText("x" .. math.ceil(step.crafts))
        end
    end
    local extra = #plan.steps - PLAN_ROWS
    pane.more:SetText(extra > 0 and ("+%d more steps"):format(extra) or "")
    local reach = plan.stuck or plan.max
    pane.total:SetText(
        #plan.steps == 0 and ""
            or ("%d skill-ups: about %d crafts%s"):format(
                reach - plan.skill,
                math.ceil(plan.crafts),
                plan.stuck and (", then stuck at " .. plan.stuck) or ""
            )
    )
end

table.insert(RW.Window.hooks.render, Plan.Render)

-------------------------------------------------------------------------------
--  Title buttons and events
-------------------------------------------------------------------------------
RW.Window.AddTitleButton({
    text = "Skill-up Plan",
    width = 100,
    order = 5,
    tip = "The fewest crafts from your skill to your cap, with the trainer recipes to learn on the way.",
    onClick = function()
        Plan.open = not Plan.open
        RW.State.tab = "learned"
        Changed()
    end,
    shown = function()
        local prof = RW.State.prof
        return Get("skillUpPlan") ~= false and not RW.State.linked and prof ~= nil and prof.skill < prof.max
    end,
})
RW.Window.AddTitleButton({
    text = "Link",
    width = 54,
    order = 7,
    tip = "Post your profession's link in chat, so others can see your recipes.",
    onClick = Link.Menu,
    shown = Link.Can,
})
RW.Window.AddTitleButton({
    text = "Alts",
    width = 54,
    order = 6,
    tip = "Your alts' professions on this realm. Each one shows here once that character has opened it.",
    onClick = Alts.Menu,
    shown = function() return AltsOn() and #Alts.List() > 0 end,
})

local events = CreateFrame("Frame")
for _, event in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_DATA_SOURCE_CHANGED", "TRADE_SKILL_LIST_UPDATE" }) do
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function() Alts.Save() end)

RW.Alts, RW.Link, RW.Orders, RW.Plan = Alts, Link, Orders, Plan
