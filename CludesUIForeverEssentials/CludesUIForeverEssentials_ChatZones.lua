if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
if not (CUI and CUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_ChatZones.lua  (WoW Forever only)
--  Chat Zones: the zone (and level) of whoever speaks in a chat channel,
--  guild chat or a whisper, in front of their message; the leader's zone on
--  each Group Finder listing, and every member's zone when you hover one.
--  The game never says where a stranger is, so a player is tagged once they
--  turn up in the Group Finder, your guild, your friends or your group, or a
--  /who. A whisper from someone not known yet ends in a [Where?] link that
--  runs a /who for them. Zones older than Forget After are dropped.
-------------------------------------------------------------------------------
local _, module = ...

local F = module.Feature("chatZones", {
    enabled = false,
    chat = true,
    level = true,
    classColor = true,
    where = true,
    finder = true,
    maxAge = 15,
})
local Get, Enabled = F.Get, F.Enabled

local SENDER_ID_ARG = 10
local WHO_FIELDS = 6
local LABEL_SPACING = 8
local LINE_TAIL = 16
local LINE_MARGIN = 26
local HINT_SPACING, HINT_MARGIN = 8, 11
local ROLES_SPACE = 160
local ROLES_SHRINK = 0.75
local WHERE_CHAIN = "addon:CludesUI:where:"
local GREY_WRAP = "|cff999999%s|r"
local LABEL_EVENTS = { "CHAT_MSG_CHANNEL", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_WHISPER" }
local GATHER_EVENTS = { "GUILD_ROSTER_UPDATE", "FRIENDLIST_UPDATE", "BN_FRIEND_INFO_CHANGED", "GROUP_ROSTER_UPDATE",
    "WHO_LIST_UPDATE", "CHAT_MSG_SYSTEM" }

local PutTalkSieve = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
local RemoveTalkSieve = (ChatFrameUtil and ChatFrameUtil.RemoveMessageEventFilter) or ChatFrame_RemoveMessageEventFilter

local spotted = {} -- name -> { zone, level, at }
local awaitingWho = {} -- names a [Where?] click is waiting on
local tagging, finderHooked, whereHooked = false, false, false
local whoRowPatterns
local listingLabels = setmetatable({}, { __mode = "k" })
local shrunkLines = setmetatable({}, { __mode = "k" })
local tooltipLabels = setmetatable({}, { __mode = "k" })
local events = CreateFrame("Frame")

local function Secret(v)
    return issecretvalue and issecretvalue(v)
end

local function LabelsOn() return Enabled() and Get("chat") end
local function ListingsOn() return Enabled() and Get("finder") end

local function PlainTitle(title)
    if not title or Secret(title) or title == "" then return nil end
    return Ambiguate(title, "none")
end

local function JotWhere(title, place, lvl)
    local who = PlainTitle(title)
    if not who or not place or Secret(place) or place == "" then return end
    lvl = not Secret(lvl) and tonumber(lvl) or nil
    spotted[who] = { place = place, level = lvl and lvl > 0 and lvl or nil, seenAt = GetTime() }
end

local function Recent(who)
    local thing = who and spotted[who]
    if thing and GetTime() - thing.seenAt <= Get("maxAge") * 60 then return thing end
end

local function AreaLead(thing, guid)
    local lead = "[" .. thing.place
    if Get("level") and thing.level then lead = lead .. " " .. thing.level end
    lead = lead .. "]"
    local tint
    if Get("classColor") and guid and not Secret(guid) and guid ~= "" then
        local _, calling = GetPlayerInfoByGUID(guid)
        tint = calling and C_ClassColor and C_ClassColor.GetClassColor(calling)
    end
    return (tint and tint:WrapTextInColorCode(lead) or GREY_WRAP:format(lead)) .. " "
end

-------------------------------------------------------------------------------
--  Where players are: the Group Finder, guild, friends, group and /who
-------------------------------------------------------------------------------
local function FromListing(id)
    local result = C_LFGList.GetSearchResultInfo(id)
    if not result or Secret(result.isDelisted) or Secret(result.numMembers) or result.isDelisted then return end
    for i = 1, result.numMembers or 0 do
        local p = C_LFGList.GetSearchResultPlayerInfo(id, i)
        if p then JotWhere(p.name, p.areaName, p.level) end
    end
end

local function FromSearch()
    local _, results = C_LFGList.GetSearchResults()
    for _, id in ipairs(results or {}) do
        FromListing(id)
    end
end

local function FromGuild()
    for i = 1, GetNumGuildMembers() do
        local title, _, _, lvl, _, place, _, _, online = GetGuildRosterInfo(i)
        if online then JotWhere(title, place, lvl) end
    end
end

local function FromFriends()
    for i = 1, C_FriendList.GetNumFriends() do
        local f = C_FriendList.GetFriendInfoByIndex(i)
        if f and f.connected then JotWhere(f.name, f.area, f.level) end
    end
    if not (BNGetNumFriends and C_BattleNet and C_BattleNet.GetFriendAccountInfo) then return end
    for i = 1, (BNGetNumFriends() or 0) do
        local bnet = C_BattleNet.GetFriendAccountInfo(i)
        local char = bnet and bnet.gameAccountInfo
        if char and char.isOnline and char.clientProgram == BNET_CLIENT_WOW and char.wowProjectID == WOW_PROJECT_ID then
            JotWhere(char.characterName, char.areaName, char.characterLevel)
        end
    end
end

local function FromParty()
    for i = 1, GetNumGroupMembers() do
        local title, _, _, lvl, _, _, place, online = GetRaidRosterInfo(i)
        if online then JotWhere(title, place, lvl) end
    end
end

local function FromWhoRoster()
    for i = 1, C_FriendList.GetNumWhoResults() do
        local w = C_FriendList.GetWhoInfo(i)
        if w then
            JotWhere(w.fullName, w.area, w.level)
            local who = PlainTitle(w.fullName)
            if who and awaitingWho[who] and w.area then
                awaitingWho[who] = nil
                CUI.Print(("|cff4cc9f0Chat Zones:|r %s is in %s, level %s."):format(who, w.area, tostring(w.level)))
            end
        end
    end
end

local function WhoRowPattern(template)
    if type(template) ~= "string" then return nil end
    local escaped = template:gsub("([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1")
    escaped = escaped:gsub("%%d", "(%%d+)"):gsub("%%s", "(.-)")
    return "^" .. escaped .. "$"
end

-- A short /who answers in chat, one line per player.
local function FromWhoRow(line)
    if not line or Secret(line) or not line:find("|Hplayer:", 1, true) then return end
    whoRowPatterns = whoRowPatterns or { WhoRowPattern(WHO_LIST_GUILD_FORMAT), WhoRowPattern(WHO_LIST_FORMAT) }
    for _, pattern in ipairs(whoRowPatterns) do
        local fields = { line:match(pattern) }
        if #fields >= WHO_FIELDS then
            JotWhere(fields[1], fields[#fields], fields[3])
            local who = PlainTitle(fields[1])
            if who then awaitingWho[who] = nil end
            return
        end
    end
end

-------------------------------------------------------------------------------
--  Chat
-------------------------------------------------------------------------------
local function WhereChainLabel(who)
    return "|H" .. WHERE_CHAIN .. who .. "|h" .. GREY_WRAP:format("[Where?]") .. "|h"
end

local function OnWhereChain(_, chain)
    if type(chain) ~= "string" or chain:sub(1, #WHERE_CHAIN) ~= WHERE_CHAIN then return end
    local who = chain:sub(#WHERE_CHAIN + 1)
    if who == "" then return end
    awaitingWho[who] = true
    C_FriendList.SendWho(('n-"%s"'):format(who:match("^[^-]+")))
end

local function LabelTalk(_, event, line, author, ...)
    if Secret(line) or Secret(author) then return false end
    local who = PlainTitle(author)
    if not who or who == UnitName("player") then return false end
    local thing = Recent(who)
    if not thing then
        if event == "CHAT_MSG_WHISPER" and Get("where") then
            return false, line .. " " .. WhereChainLabel(who), author, ...
        end
        return false
    end
    return false, AreaLead(thing, select(SENDER_ID_ARG, ...)) .. line, author, ...
end

-------------------------------------------------------------------------------
--  Group Finder: the leader's zone on each listing, members' on hover
-------------------------------------------------------------------------------
local function AreaLabel(labels, owner, typefaceObject)
    local label = labels[owner]
    if not label then
        label = owner:CreateFontString(nil, "ARTWORK", typefaceObject)
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
        labels[owner] = label
    end
    return label
end

local function LeaderArea(resultID)
    local leader = C_LFGList.GetSearchResultLeaderInfo and C_LFGList.GetSearchResultLeaderInfo(resultID)
    if leader and leader.areaName then return leader.areaName end
    local first = C_LFGList.GetSearchResultPlayerInfo(resultID, 1)
    return first and first.areaName
end

local function ShrinkRoles(thing, on)
    local display = thing.DataDisplay
    if not display or (not on and not shrunkLines[thing]) then return end
    display:SetScale(on and ROLES_SHRINK or 1)
    shrunkLines[thing] = on or nil
end

local LeftEdgeIn
local function LeftEdgeAmong(leftmost, ...)
    for i = 1, select("#", ...) do
        local part = select(i, ...)
        if Secret(leftmost) then return leftmost end
        if part:IsVisible() then
            if part.GetChildren then
                leftmost = LeftEdgeIn(part, leftmost)
            else
                local lineX = part:GetLeft()
                if Secret(lineX) then return lineX end
                if lineX then
                    lineX = lineX * part:GetEffectiveScale()
                    if not leftmost or lineX < leftmost then leftmost = lineX end
                end
            end
        end
    end
    return leftmost
end
function LeftEdgeIn(window, leftmost)
    return LeftEdgeAmong(LeftEdgeAmong(leftmost, window:GetRegions()), window:GetChildren())
end

local function AreaRoom(thing)
    local rolesLeft = thing.DataDisplay and LeftEdgeIn(thing.DataDisplay)
    local titleRight = thing.ActivityName:GetRight()
    if Secret(rolesLeft) or Secret(titleRight) then return nil end
    if rolesLeft and titleRight then return (rolesLeft / thing:GetEffectiveScale()) - titleRight - LINE_TAIL end
    local room, titleW = thing:GetWidth(), thing.ActivityName:GetStringWidth()
    if Secret(room) or Secret(titleW) then return nil end
    return room - ROLES_SPACE - LINE_MARGIN - titleW
end

local function RenderListing(thing)
    if not thing.ActivityName then return end
    ShrinkRoles(thing, ListingsOn())
    local place = ListingsOn() and thing.resultID and thing:IsShown() and LeaderArea(thing.resultID)
    local room = place and not Secret(place) and place ~= "" and AreaRoom(thing)
    if not room then
        if listingLabels[thing] then listingLabels[thing]:Hide() end
        return
    end
    local label = AreaLabel(listingLabels, thing, "GameFontDisableSmallLeft")
    local path, dims, flags = thing.ActivityName:GetFont()
    if path then label:SetFont(path, dims, flags) end
    label:SetTextColor(0.6, 0.6, 0.6)
    label:ClearAllPoints()
    label:SetPoint("LEFT", thing.ActivityName, "RIGHT", LABEL_SPACING, 0)
    label:SetWidth(math.max(1, room))
    label:SetText(place)
    label:Show()
end

local function LineRightEdge(row)
    local edge = row.Level and row.Level:IsShown() and row.Level:GetRight() or 0
    if Secret(edge) then return nil end
    for _, roleGlyph in ipairs(row.Roles or {}) do
        local glyphEdge = roleGlyph:IsShown() and roleGlyph:GetRight()
        if Secret(glyphEdge) then return nil end
        if glyphEdge then edge = math.max(edge, glyphEdge) end
    end
    return edge
end

local function AreasByMember(result, resultID)
    local areas = {}
    for i = 1, result.numMembers or 0 do
        local p = C_LFGList.GetSearchResultPlayerInfo(resultID, i)
        if p and p.name and p.areaName and not Secret(p.name) and not Secret(p.areaName) then
            areas[p.name] = p.areaName
        end
    end
    return areas
end

local function TooltipMemberLines(hint)
    local memberLines = {}
    if hint.Leader and hint.Leader:IsShown() then memberLines[1] = hint.Leader end
    if hint.memberPool then
        for window in hint.memberPool:EnumerateActive() do
            memberLines[#memberLines + 1] = window
        end
    end
    return memberLines
end

local function LabelMemberArea(row, areas, edge)
    local title = row.Name and row.Name:GetText()
    if Secret(title) then return 0 end
    local who = PlainTitle(title)
    local recent = who and Recent(who)
    local place = title and areas[title] or recent and recent.place
    local lineX = row:GetLeft()
    if not (place and lineX) or Secret(lineX) then return 0 end
    local label = AreaLabel(tooltipLabels, row, "GameFontHighlightSmallLeft")
    label:ClearAllPoints()
    label:SetPoint("LEFT", row, "LEFT", edge - lineX + HINT_SPACING, 0)
    label:SetText(place)
    label:Show()
    return label:GetStringWidth()
end

local function RenderListingTooltip(hint, resultID)
    for _, label in pairs(tooltipLabels) do
        label:Hide()
    end
    local result = ListingsOn() and resultID and C_LFGList.GetSearchResultInfo(resultID)
    if not result or Secret(result.numMembers) then return end
    local areas = AreasByMember(result, resultID)
    local memberLines = TooltipMemberLines(hint)
    local edge = 0
    for _, row in ipairs(memberLines) do
        local lineRight = LineRightEdge(row)
        if not lineRight then return end
        edge = math.max(edge, lineRight)
    end
    if edge == 0 then return end
    local widestLabel = 0
    for _, row in ipairs(memberLines) do
        widestLabel = math.max(widestLabel, LabelMemberArea(row, areas, edge))
    end
    local hintX, hintW = hint:GetLeft(), hint:GetWidth()
    if widestLabel > 0 and hintX and not Secret(hintX) and not Secret(hintW) then
        local desired = edge - hintX + HINT_SPACING + widestLabel + HINT_MARGIN
        if hintW < desired then hint:SetWidth(desired) end
    end
end

local function AttachFinderFrames()
    if finderHooked or not _G.LFGBrowseSearchEntry_Update then return end
    finderHooked = true
    hooksecurefunc("LFGBrowseSearchEntry_Update", RenderListing)
    if _G.LFGBrowseSearchEntryTooltip_UpdateAndShow then
        hooksecurefunc("LFGBrowseSearchEntryTooltip_UpdateAndShow", RenderListingTooltip)
    end
end

-------------------------------------------------------------------------------
--  Events and Apply
-------------------------------------------------------------------------------
events:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        AttachFinderFrames()
        if finderHooked then events:UnregisterEvent("ADDON_LOADED") end
    elseif event == "LFG_LIST_SEARCH_RESULTS_RECEIVED" then
        FromSearch()
    elseif event == "LFG_LIST_SEARCH_RESULT_UPDATED" then
        FromListing(...)
    elseif event == "GUILD_ROSTER_UPDATE" then
        FromGuild()
    elseif event == "FRIENDLIST_UPDATE" or event == "BN_FRIEND_INFO_CHANGED" then
        FromFriends()
    elseif event == "GROUP_ROSTER_UPDATE" then
        FromParty()
    elseif event == "WHO_LIST_UPDATE" then
        FromWhoRoster()
    elseif event == "CHAT_MSG_SYSTEM" then
        FromWhoRow(...)
    elseif event == "CHAT_MSG_GUILD" or event == "CHAT_MSG_OFFICER" then
        local who = PlainTitle((select(2, ...)))
        if who and not Recent(who) and C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
    end
end)

local function HaltListening()
    events:UnregisterAllEvents()
    if tagging then
        for _, event in ipairs(LABEL_EVENTS) do
            RemoveTalkSieve(event, LabelTalk)
        end
        tagging = false
    end
    if not ListingsOn() then
        for _, label in pairs(listingLabels) do
            label:Hide()
        end
        for thing in pairs(shrunkLines) do
            ShrinkRoles(thing, false)
        end
    end
end

local function Apply()
    HaltListening()
    if not Enabled() then
        wipe(spotted)
        wipe(awaitingWho)
        return
    end
    for _, event in ipairs(GATHER_EVENTS) do
        events:RegisterEvent(event)
    end
    if C_LFGList and C_LFGList.GetSearchResultPlayerInfo then
        events:RegisterEvent("LFG_LIST_SEARCH_RESULTS_RECEIVED")
        events:RegisterEvent("LFG_LIST_SEARCH_RESULT_UPDATED")
    end
    if LabelsOn() and PutTalkSieve then
        if not whereHooked and EventRegistry then
            whereHooked = true
            EventRegistry:RegisterCallback("SetItemRef", function(...)
                if LabelsOn() then OnWhereChain(...) end
            end, events)
        end
        events:RegisterEvent("CHAT_MSG_GUILD")
        events:RegisterEvent("CHAT_MSG_OFFICER")
        for _, event in ipairs(LABEL_EVENTS) do
            PutTalkSieve(event, LabelTalk)
        end
        tagging = true
    end
    if ListingsOn() then
        AttachFinderFrames()
        if not finderHooked then events:RegisterEvent("ADDON_LOADED") end
    end
    if IsInGuild() then FromGuild() end
    FromFriends()
    FromParty()
end

module.ChatZones = { Recent = Recent, NoteWhere = JotWhere }
CUI._ChatZones = {
    Get = Get,
    Cfg = F.Cfg,
    Apply = Apply,
    Recent = Recent,
    TagChat = LabelTalk,
}

F.Start(Apply)
