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

local SENDER_GUID_ARG = 10
local WHO_FIELDS = 6
local LABEL_GAP = 8
local ROW_TAIL = 16
local ROW_MARGIN = 26
local TIP_SPACING, TIP_MARGIN = 8, 11
local ROLES_SPACE = 160
local ROLES_SHRINK = 0.75
local WHERE_LINK = "addon:CludesUI:where:"
local GREY_WRAP = "|cff999999%s|r"
local TAG_EVENTS = { "CHAT_MSG_CHANNEL", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_WHISPER" }
local LEARN_EVENTS = { "GUILD_ROSTER_UPDATE", "FRIENDLIST_UPDATE", "BN_FRIEND_INFO_CHANGED", "GROUP_ROSTER_UPDATE",
    "WHO_LIST_UPDATE", "CHAT_MSG_SYSTEM" }

local AddChatFilter = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
local RemoveChatFilter = (ChatFrameUtil and ChatFrameUtil.RemoveMessageEventFilter) or ChatFrame_RemoveMessageEventFilter

local seen = {} -- name -> { zone, level, at }
local awaitingWho = {} -- names a [Where?] click is waiting on
local tagging, finderHooked, whereHooked = false, false, false
local whoLinePatterns
local listingLabels = setmetatable({}, { __mode = "k" })
local shrunkRows = setmetatable({}, { __mode = "k" })
local tooltipLabels = setmetatable({}, { __mode = "k" })
local events = CreateFrame("Frame")

local function Secret(v)
    return issecretvalue and issecretvalue(v)
end

local function TagsOn() return Enabled() and Get("chat") end
local function ListingsOn() return Enabled() and Get("finder") end

local function PlainName(name)
    if not name or Secret(name) or name == "" then return nil end
    return Ambiguate(name, "none")
end

local function NoteWhere(name, place, level)
    local who = PlainName(name)
    if not who or not place or Secret(place) or place == "" then return end
    level = not Secret(level) and tonumber(level) or nil
    seen[who] = { place = place, level = level and level > 0 and level or nil, seenAt = GetTime() }
end

local function Recent(who)
    local item = who and seen[who]
    if item and GetTime() - item.seenAt <= Get("maxAge") * 60 then return item end
end

local function ZonePrefix(item, guid)
    local prefix = "[" .. item.place
    if Get("level") and item.level then prefix = prefix .. " " .. item.level end
    prefix = prefix .. "]"
    local tint
    if Get("classColor") and guid and not Secret(guid) and guid ~= "" then
        local _, class = GetPlayerInfoByGUID(guid)
        tint = class and C_ClassColor and C_ClassColor.GetClassColor(class)
    end
    return (tint and tint:WrapTextInColorCode(prefix) or GREY_WRAP:format(prefix)) .. " "
end

-------------------------------------------------------------------------------
--  Where players are: the Group Finder, guild, friends, group and /who
-------------------------------------------------------------------------------
local function FromListing(id)
    local result = C_LFGList.GetSearchResultInfo(id)
    if not result or Secret(result.isDelisted) or Secret(result.numMembers) or result.isDelisted then return end
    for i = 1, result.numMembers or 0 do
        local p = C_LFGList.GetSearchResultPlayerInfo(id, i)
        if p then NoteWhere(p.name, p.areaName, p.level) end
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
        local name, _, _, level, _, place, _, _, online = GetGuildRosterInfo(i)
        if online then NoteWhere(name, place, level) end
    end
end

local function FromFriends()
    for i = 1, C_FriendList.GetNumFriends() do
        local f = C_FriendList.GetFriendInfoByIndex(i)
        if f and f.connected then NoteWhere(f.name, f.area, f.level) end
    end
    if not (BNGetNumFriends and C_BattleNet and C_BattleNet.GetFriendAccountInfo) then return end
    for i = 1, (BNGetNumFriends() or 0) do
        local bnet = C_BattleNet.GetFriendAccountInfo(i)
        local char = bnet and bnet.gameAccountInfo
        if char and char.isOnline and char.clientProgram == BNET_CLIENT_WOW and char.wowProjectID == WOW_PROJECT_ID then
            NoteWhere(char.characterName, char.areaName, char.characterLevel)
        end
    end
end

local function FromParty()
    for i = 1, GetNumGroupMembers() do
        local name, _, _, level, _, _, place, online = GetRaidRosterInfo(i)
        if online then NoteWhere(name, place, level) end
    end
end

local function FromWhoList()
    for i = 1, C_FriendList.GetNumWhoResults() do
        local w = C_FriendList.GetWhoInfo(i)
        if w then
            NoteWhere(w.fullName, w.area, w.level)
            local who = PlainName(w.fullName)
            if who and awaitingWho[who] and w.area then
                awaitingWho[who] = nil
                CUI.Print(("|cff4cc9f0Chat Zones:|r %s is in %s, level %s."):format(who, w.area, tostring(w.level)))
            end
        end
    end
end

local function WhoLinePattern(template)
    if type(template) ~= "string" then return nil end
    local escaped = template:gsub("([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1")
    escaped = escaped:gsub("%%d", "(%%d+)"):gsub("%%s", "(.-)")
    return "^" .. escaped .. "$"
end

-- A short /who answers in chat, one line per player.
local function FromWhoLine(line)
    if not line or Secret(line) or not line:find("|Hplayer:", 1, true) then return end
    whoLinePatterns = whoLinePatterns or { WhoLinePattern(WHO_LIST_GUILD_FORMAT), WhoLinePattern(WHO_LIST_FORMAT) }
    for _, pattern in ipairs(whoLinePatterns) do
        local fields = { line:match(pattern) }
        if #fields >= WHO_FIELDS then
            NoteWhere(fields[1], fields[#fields], fields[3])
            local who = PlainName(fields[1])
            if who then awaitingWho[who] = nil end
            return
        end
    end
end

-------------------------------------------------------------------------------
--  Chat
-------------------------------------------------------------------------------
local function WhereLinkText(who)
    return "|H" .. WHERE_LINK .. who .. "|h" .. GREY_WRAP:format("[Where?]") .. "|h"
end

local function OnWhereLink(_, link)
    if type(link) ~= "string" or link:sub(1, #WHERE_LINK) ~= WHERE_LINK then return end
    local who = link:sub(#WHERE_LINK + 1)
    if who == "" then return end
    awaitingWho[who] = true
    C_FriendList.SendWho(('n-"%s"'):format(who:match("^[^-]+")))
end

local function TagChat(_, event, line, author, ...)
    if Secret(line) or Secret(author) then return false end
    local who = PlainName(author)
    if not who or who == UnitName("player") then return false end
    local item = Recent(who)
    if not item then
        if event == "CHAT_MSG_WHISPER" and Get("where") then
            return false, line .. " " .. WhereLinkText(who), author, ...
        end
        return false
    end
    return false, ZonePrefix(item, select(SENDER_GUID_ARG, ...)) .. line, author, ...
end

-------------------------------------------------------------------------------
--  Group Finder: the leader's zone on each listing, members' on hover
-------------------------------------------------------------------------------
local function ZoneLabel(labels, owner, fontObject)
    local label = labels[owner]
    if not label then
        label = owner:CreateFontString(nil, "ARTWORK", fontObject)
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

local function ShrinkRoles(item, on)
    local display = item.DataDisplay
    if not display or (not on and not shrunkRows[item]) then return end
    display:SetScale(on and ROLES_SHRINK or 1)
    shrunkRows[item] = on or nil
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
                local rowX = part:GetLeft()
                if Secret(rowX) then return rowX end
                if rowX then
                    rowX = rowX * part:GetEffectiveScale()
                    if not leftmost or rowX < leftmost then leftmost = rowX end
                end
            end
        end
    end
    return leftmost
end
function LeftEdgeIn(frame, leftmost)
    return LeftEdgeAmong(LeftEdgeAmong(leftmost, frame:GetRegions()), frame:GetChildren())
end

local function ZoneRoom(item)
    local rolesLeft = item.DataDisplay and LeftEdgeIn(item.DataDisplay)
    local nameRight = item.ActivityName:GetRight()
    if Secret(rolesLeft) or Secret(nameRight) then return nil end
    if rolesLeft and nameRight then return (rolesLeft / item:GetEffectiveScale()) - nameRight - ROW_TAIL end
    local room, nameW = item:GetWidth(), item.ActivityName:GetStringWidth()
    if Secret(room) or Secret(nameW) then return nil end
    return room - ROLES_SPACE - ROW_MARGIN - nameW
end

local function PaintListing(item)
    if not item.ActivityName then return end
    ShrinkRoles(item, ListingsOn())
    local place = ListingsOn() and item.resultID and item:IsShown() and LeaderArea(item.resultID)
    local room = place and not Secret(place) and place ~= "" and ZoneRoom(item)
    if not room then
        if listingLabels[item] then listingLabels[item]:Hide() end
        return
    end
    local label = ZoneLabel(listingLabels, item, "GameFontDisableSmallLeft")
    local path, size, flags = item.ActivityName:GetFont()
    if path then label:SetFont(path, size, flags) end
    label:SetTextColor(0.6, 0.6, 0.6)
    label:ClearAllPoints()
    label:SetPoint("LEFT", item.ActivityName, "RIGHT", LABEL_GAP, 0)
    label:SetWidth(math.max(1, room))
    label:SetText(place)
    label:Show()
end

local function RowRightEdge(row)
    local edge = row.Level and row.Level:IsShown() and row.Level:GetRight() or 0
    if Secret(edge) then return nil end
    for _, roleIcon in ipairs(row.Roles or {}) do
        local iconEdge = roleIcon:IsShown() and roleIcon:GetRight()
        if Secret(iconEdge) then return nil end
        if iconEdge then edge = math.max(edge, iconEdge) end
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

local function TooltipMemberRows(tip)
    local memberRows = {}
    if tip.Leader and tip.Leader:IsShown() then memberRows[1] = tip.Leader end
    if tip.memberPool then
        for frame in tip.memberPool:EnumerateActive() do
            memberRows[#memberRows + 1] = frame
        end
    end
    return memberRows
end

local function LabelMemberArea(row, areas, edge)
    local name = row.Name and row.Name:GetText()
    if Secret(name) then return 0 end
    local who = PlainName(name)
    local recent = who and Recent(who)
    local place = name and areas[name] or recent and recent.place
    local rowX = row:GetLeft()
    if not (place and rowX) or Secret(rowX) then return 0 end
    local label = ZoneLabel(tooltipLabels, row, "GameFontHighlightSmallLeft")
    label:ClearAllPoints()
    label:SetPoint("LEFT", row, "LEFT", edge - rowX + TIP_SPACING, 0)
    label:SetText(place)
    label:Show()
    return label:GetStringWidth()
end

local function PaintListingTooltip(tip, resultID)
    for _, label in pairs(tooltipLabels) do
        label:Hide()
    end
    local result = ListingsOn() and resultID and C_LFGList.GetSearchResultInfo(resultID)
    if not result or Secret(result.numMembers) then return end
    local areas = AreasByMember(result, resultID)
    local memberRows = TooltipMemberRows(tip)
    local edge = 0
    for _, row in ipairs(memberRows) do
        local rowRight = RowRightEdge(row)
        if not rowRight then return end
        edge = math.max(edge, rowRight)
    end
    if edge == 0 then return end
    local widestLabel = 0
    for _, row in ipairs(memberRows) do
        widestLabel = math.max(widestLabel, LabelMemberArea(row, areas, edge))
    end
    local tipX, tipW = tip:GetLeft(), tip:GetWidth()
    if widestLabel > 0 and tipX and not Secret(tipX) and not Secret(tipW) then
        local wanted = edge - tipX + TIP_SPACING + widestLabel + TIP_MARGIN
        if tipW < wanted then tip:SetWidth(wanted) end
    end
end

local function HookFinderFrames()
    if finderHooked or not _G.LFGBrowseSearchEntry_Update then return end
    finderHooked = true
    hooksecurefunc("LFGBrowseSearchEntry_Update", PaintListing)
    if _G.LFGBrowseSearchEntryTooltip_UpdateAndShow then
        hooksecurefunc("LFGBrowseSearchEntryTooltip_UpdateAndShow", PaintListingTooltip)
    end
end

-------------------------------------------------------------------------------
--  Events and Apply
-------------------------------------------------------------------------------
events:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        HookFinderFrames()
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
        FromWhoList()
    elseif event == "CHAT_MSG_SYSTEM" then
        FromWhoLine(...)
    elseif event == "CHAT_MSG_GUILD" or event == "CHAT_MSG_OFFICER" then
        local who = PlainName((select(2, ...)))
        if who and not Recent(who) and C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
    end
end)

local function StopListening()
    events:UnregisterAllEvents()
    if tagging then
        for _, event in ipairs(TAG_EVENTS) do
            RemoveChatFilter(event, TagChat)
        end
        tagging = false
    end
    if not ListingsOn() then
        for _, label in pairs(listingLabels) do
            label:Hide()
        end
        for item in pairs(shrunkRows) do
            ShrinkRoles(item, false)
        end
    end
end

local function Apply()
    StopListening()
    if not Enabled() then
        wipe(seen)
        wipe(awaitingWho)
        return
    end
    for _, event in ipairs(LEARN_EVENTS) do
        events:RegisterEvent(event)
    end
    if C_LFGList and C_LFGList.GetSearchResultPlayerInfo then
        events:RegisterEvent("LFG_LIST_SEARCH_RESULTS_RECEIVED")
        events:RegisterEvent("LFG_LIST_SEARCH_RESULT_UPDATED")
    end
    if TagsOn() and AddChatFilter then
        if not whereHooked and EventRegistry then
            whereHooked = true
            EventRegistry:RegisterCallback("SetItemRef", function(...)
                if TagsOn() then OnWhereLink(...) end
            end, events)
        end
        events:RegisterEvent("CHAT_MSG_GUILD")
        events:RegisterEvent("CHAT_MSG_OFFICER")
        for _, event in ipairs(TAG_EVENTS) do
            AddChatFilter(event, TagChat)
        end
        tagging = true
    end
    if ListingsOn() then
        HookFinderFrames()
        if not finderHooked then events:RegisterEvent("ADDON_LOADED") end
    end
    if IsInGuild() then FromGuild() end
    FromFriends()
    FromParty()
end

module.ChatZones = { Recent = Recent, NoteWhere = NoteWhere }
CUI._ChatZones = {
    Get = Get,
    Cfg = F.Cfg,
    Apply = Apply,
    Recent = Recent,
    TagChat = TagChat,
}

F.Start(Apply)
