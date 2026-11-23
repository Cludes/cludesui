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
--  Title buttons and events
-------------------------------------------------------------------------------
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

RW.Alts, RW.Link = Alts, Link
