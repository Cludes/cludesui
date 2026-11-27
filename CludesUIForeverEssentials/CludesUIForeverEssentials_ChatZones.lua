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

local GUID_ARG = 10
local WHO_CAPTURES = 6
local ZONE_GAP = 8
local ROW_END_GAP = 16
local ROW_EDGE = 26
local TIP_GAP, TIP_PAD = 8, 11
local DATA_DISPLAY_SPACE = 160
local ROLE_SCALE = 0.75
local LINK = "addon:CludesUI:where:"
local MUTED = "|cff999999%s|r"
local TAGGED = { "CHAT_MSG_CHANNEL", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_WHISPER" }
local EVENTS = { "GUILD_ROSTER_UPDATE", "FRIENDLIST_UPDATE", "BN_FRIEND_INFO_CHANGED", "GROUP_ROSTER_UPDATE",
    "WHO_LIST_UPDATE", "CHAT_MSG_SYSTEM" }

local AddFilter = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
local RemoveFilter = (ChatFrameUtil and ChatFrameUtil.RemoveMessageEventFilter) or ChatFrame_RemoveMessageEventFilter

local known = {} -- name -> { zone, level, at }
local looking = {} -- names a [Where?] click is waiting on
local filtering, hooked, linkHooked = false, false, false
local whoPatterns
local rowText = setmetatable({}, { __mode = "k" })
local scaled = setmetatable({}, { __mode = "k" })
local tipText = setmetatable({}, { __mode = "k" })
local events = CreateFrame("Frame")

local function Secret(v)
    return issecretvalue and issecretvalue(v)
end

local function ChatOn() return Enabled() and Get("chat") end
local function FinderOn() return Enabled() and Get("finder") end

local function Key(name)
    if not name or Secret(name) or name == "" then return nil end
    return Ambiguate(name, "none")
end

local function Remember(name, zone, level)
    local key = Key(name)
    if not key or not zone or Secret(zone) or zone == "" then return end
    level = not Secret(level) and tonumber(level) or nil
    known[key] = { zone = zone, level = level and level > 0 and level or nil, at = GetTime() }
end

local function Fresh(key)
    local entry = key and known[key]
    if entry and GetTime() - entry.at <= Get("maxAge") * 60 then return entry end
end

local function Tag(entry, guid)
    local text = "[" .. entry.zone
    if Get("level") and entry.level then text = text .. " " .. entry.level end
    text = text .. "]"
    local color
    if Get("classColor") and guid and not Secret(guid) and guid ~= "" then
        local _, class = GetPlayerInfoByGUID(guid)
        color = class and C_ClassColor and C_ClassColor.GetClassColor(class)
    end
    return (color and color:WrapTextInColorCode(text) or MUTED:format(text)) .. " "
end

-------------------------------------------------------------------------------
--  Where players are: the Group Finder, guild, friends, group and /who
-------------------------------------------------------------------------------
local function ReadGroupFinder(id)
    local info = C_LFGList.GetSearchResultInfo(id)
    if not info or Secret(info.isDelisted) or Secret(info.numMembers) or info.isDelisted then return end
    for i = 1, info.numMembers or 0 do
        local p = C_LFGList.GetSearchResultPlayerInfo(id, i)
        if p then Remember(p.name, p.areaName, p.level) end
    end
end

local function ReadGroupFinderAll()
    local _, results = C_LFGList.GetSearchResults()
    for _, id in ipairs(results or {}) do
        ReadGroupFinder(id)
    end
end

local function ReadGuild()
    for i = 1, GetNumGuildMembers() do
        local name, _, _, level, _, zone, _, _, online = GetGuildRosterInfo(i)
        if online then Remember(name, zone, level) end
    end
end

local function ReadFriends()
    for i = 1, C_FriendList.GetNumFriends() do
        local f = C_FriendList.GetFriendInfoByIndex(i)
        if f and f.connected then Remember(f.name, f.area, f.level) end
    end
    if not (BNGetNumFriends and C_BattleNet and C_BattleNet.GetFriendAccountInfo) then return end
    for i = 1, (BNGetNumFriends() or 0) do
        local account = C_BattleNet.GetFriendAccountInfo(i)
        local game = account and account.gameAccountInfo
        if game and game.isOnline and game.clientProgram == BNET_CLIENT_WOW and game.wowProjectID == WOW_PROJECT_ID then
            Remember(game.characterName, game.areaName, game.characterLevel)
        end
    end
end

local function ReadGroup()
    for i = 1, GetNumGroupMembers() do
        local name, _, _, level, _, _, zone, online = GetRaidRosterInfo(i)
        if online then Remember(name, zone, level) end
    end
end

local function ReadWho()
    for i = 1, C_FriendList.GetNumWhoResults() do
        local w = C_FriendList.GetWhoInfo(i)
        if w then
            Remember(w.fullName, w.area, w.level)
            local key = Key(w.fullName)
            if key and looking[key] and w.area then
                looking[key] = nil
                CUI.Print(("|cff4cc9f0Chat Zones:|r %s is in %s, level %s."):format(key, w.area, tostring(w.level)))
            end
        end
    end
end

local function WhoPattern(fmt)
    if type(fmt) ~= "string" then return nil end
    local out = fmt:gsub("([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1")
    out = out:gsub("%%d", "(%%d+)"):gsub("%%s", "(.-)")
    return "^" .. out .. "$"
end

-- A short /who answers in chat, one line per player.
local function ReadWhoLine(msg)
    if not msg or Secret(msg) or not msg:find("|Hplayer:", 1, true) then return end
    whoPatterns = whoPatterns or { WhoPattern(WHO_LIST_GUILD_FORMAT), WhoPattern(WHO_LIST_FORMAT) }
    for _, pattern in ipairs(whoPatterns) do
        local caps = { msg:match(pattern) }
        if #caps >= WHO_CAPTURES then
            Remember(caps[1], caps[#caps], caps[3])
            local key = Key(caps[1])
            if key then looking[key] = nil end
            return
        end
    end
end

-------------------------------------------------------------------------------
--  Chat
-------------------------------------------------------------------------------
local function WhereLink(key)
    return "|H" .. LINK .. key .. "|h" .. MUTED:format("[Where?]") .. "|h"
end

local function OnLinkClick(_, link)
    if type(link) ~= "string" or link:sub(1, #LINK) ~= LINK then return end
    local key = link:sub(#LINK + 1)
    if key == "" then return end
    looking[key] = true
    C_FriendList.SendWho(('n-"%s"'):format(key:match("^[^-]+")))
end

local function Filter(_, event, msg, author, ...)
    if Secret(msg) or Secret(author) then return false end
    local key = Key(author)
    if not key or key == UnitName("player") then return false end
    local entry = Fresh(key)
    if not entry then
        if event == "CHAT_MSG_WHISPER" and Get("where") then
            return false, msg .. " " .. WhereLink(key), author, ...
        end
        return false
    end
    return false, Tag(entry, select(GUID_ARG, ...)) .. msg, author, ...
end

-------------------------------------------------------------------------------
--  Group Finder: the leader's zone on each listing, members' on hover
-------------------------------------------------------------------------------
local function ZoneString(store, parent, font)
    local fs = store[parent]
    if not fs then
        fs = parent:CreateFontString(nil, "ARTWORK", font)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        store[parent] = fs
    end
    return fs
end

local function LeaderZone(resultID)
    local leader = C_LFGList.GetSearchResultLeaderInfo and C_LFGList.GetSearchResultLeaderInfo(resultID)
    if leader and leader.areaName then return leader.areaName end
    local first = C_LFGList.GetSearchResultPlayerInfo(resultID, 1)
    return first and first.areaName
end

local function ScaleRoles(entry, on)
    local display = entry.DataDisplay
    if not display or (not on and not scaled[entry]) then return end
    display:SetScale(on and ROLE_SCALE or 1)
    scaled[entry] = on or nil
end

local LeftmostShown
local function LeftmostOf(best, ...)
    for i = 1, select("#", ...) do
        local region = select(i, ...)
        if Secret(best) then return best end
        if region:IsVisible() then
            if region.GetChildren then
                best = LeftmostShown(region, best)
            else
                local left = region:GetLeft()
                if Secret(left) then return left end
                if left then
                    left = left * region:GetEffectiveScale()
                    if not best or left < best then best = left end
                end
            end
        end
    end
    return best
end
function LeftmostShown(frame, best)
    return LeftmostOf(LeftmostOf(best, frame:GetRegions()), frame:GetChildren())
end

local function RowZoneWidth(entry)
    local stop = entry.DataDisplay and LeftmostShown(entry.DataDisplay)
    local start = entry.ActivityName:GetRight()
    if Secret(stop) or Secret(start) then return nil end
    if stop and start then return (stop / entry:GetEffectiveScale()) - start - ROW_END_GAP end
    local width, nameWidth = entry:GetWidth(), entry.ActivityName:GetStringWidth()
    if Secret(width) or Secret(nameWidth) then return nil end
    return width - DATA_DISPLAY_SPACE - ROW_EDGE - nameWidth
end

local function UpdateRow(entry)
    if not entry.ActivityName then return end
    ScaleRoles(entry, FinderOn())
    local zone = FinderOn() and entry.resultID and entry:IsShown() and LeaderZone(entry.resultID)
    local width = zone and not Secret(zone) and zone ~= "" and RowZoneWidth(entry)
    if not width then
        if rowText[entry] then rowText[entry]:Hide() end
        return
    end
    local fs = ZoneString(rowText, entry, "GameFontDisableSmallLeft")
    local path, size, flags = entry.ActivityName:GetFont()
    if path then fs:SetFont(path, size, flags) end
    fs:SetTextColor(0.6, 0.6, 0.6)
    fs:ClearAllPoints()
    fs:SetPoint("LEFT", entry.ActivityName, "RIGHT", ZONE_GAP, 0)
    fs:SetWidth(math.max(1, width))
    fs:SetText(zone)
    fs:Show()
end

local function LineRight(row)
    local right = row.Level and row.Level:IsShown() and row.Level:GetRight() or 0
    if Secret(right) then return nil end
    for _, icon in ipairs(row.Roles or {}) do
        local iconRight = icon:IsShown() and icon:GetRight()
        if Secret(iconRight) then return nil end
        if iconRight then right = math.max(right, iconRight) end
    end
    return right
end

local function MemberZones(info, resultID)
    local zones = {}
    for i = 1, info.numMembers or 0 do
        local p = C_LFGList.GetSearchResultPlayerInfo(resultID, i)
        if p and p.name and p.areaName and not Secret(p.name) and not Secret(p.areaName) then
            zones[p.name] = p.areaName
        end
    end
    return zones
end

local function MemberRows(tip)
    local rows = {}
    if tip.Leader and tip.Leader:IsShown() then rows[1] = tip.Leader end
    if tip.memberPool then
        for frame in tip.memberPool:EnumerateActive() do
            rows[#rows + 1] = frame
        end
    end
    return rows
end

local function ShowMemberZone(row, zones, right)
    local name = row.Name and row.Name:GetText()
    if Secret(name) then return 0 end
    local key = Key(name)
    local cached = key and Fresh(key)
    local zone = name and zones[name] or cached and cached.zone
    local left = row:GetLeft()
    if not (zone and left) or Secret(left) then return 0 end
    local fs = ZoneString(tipText, row, "GameFontHighlightSmallLeft")
    fs:ClearAllPoints()
    fs:SetPoint("LEFT", row, "LEFT", right - left + TIP_GAP, 0)
    fs:SetText(zone)
    fs:Show()
    return fs:GetStringWidth()
end

local function UpdateTooltip(tip, resultID)
    for _, fs in pairs(tipText) do
        fs:Hide()
    end
    local info = FinderOn() and resultID and C_LFGList.GetSearchResultInfo(resultID)
    if not info or Secret(info.numMembers) then return end
    local zones = MemberZones(info, resultID)
    local rows = MemberRows(tip)
    local right = 0
    for _, row in ipairs(rows) do
        local rowRight = LineRight(row)
        if not rowRight then return end
        right = math.max(right, rowRight)
    end
    if right == 0 then return end
    local widest = 0
    for _, row in ipairs(rows) do
        widest = math.max(widest, ShowMemberZone(row, zones, right))
    end
    local tipLeft, tipWidth = tip:GetLeft(), tip:GetWidth()
    if widest > 0 and tipLeft and not Secret(tipLeft) and not Secret(tipWidth) then
        local need = right - tipLeft + TIP_GAP + widest + TIP_PAD
        if tipWidth < need then tip:SetWidth(need) end
    end
end

local function HookFinder()
    if hooked or not _G.LFGBrowseSearchEntry_Update then return end
    hooked = true
    hooksecurefunc("LFGBrowseSearchEntry_Update", UpdateRow)
    if _G.LFGBrowseSearchEntryTooltip_UpdateAndShow then
        hooksecurefunc("LFGBrowseSearchEntryTooltip_UpdateAndShow", UpdateTooltip)
    end
end

-------------------------------------------------------------------------------
--  Events and Apply
-------------------------------------------------------------------------------
events:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        HookFinder()
        if hooked then events:UnregisterEvent("ADDON_LOADED") end
    elseif event == "LFG_LIST_SEARCH_RESULTS_RECEIVED" then
        ReadGroupFinderAll()
    elseif event == "LFG_LIST_SEARCH_RESULT_UPDATED" then
        ReadGroupFinder(...)
    elseif event == "GUILD_ROSTER_UPDATE" then
        ReadGuild()
    elseif event == "FRIENDLIST_UPDATE" or event == "BN_FRIEND_INFO_CHANGED" then
        ReadFriends()
    elseif event == "GROUP_ROSTER_UPDATE" then
        ReadGroup()
    elseif event == "WHO_LIST_UPDATE" then
        ReadWho()
    elseif event == "CHAT_MSG_SYSTEM" then
        ReadWhoLine(...)
    elseif event == "CHAT_MSG_GUILD" or event == "CHAT_MSG_OFFICER" then
        local key = Key((select(2, ...)))
        if key and not Fresh(key) and C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
    end
end)

local function Stop()
    events:UnregisterAllEvents()
    if filtering then
        for _, event in ipairs(TAGGED) do
            RemoveFilter(event, Filter)
        end
        filtering = false
    end
    if not FinderOn() then
        for _, fs in pairs(rowText) do
            fs:Hide()
        end
        for entry in pairs(scaled) do
            ScaleRoles(entry, false)
        end
    end
end

local function Apply()
    Stop()
    if not Enabled() then
        wipe(known)
        wipe(looking)
        return
    end
    for _, event in ipairs(EVENTS) do
        events:RegisterEvent(event)
    end
    if C_LFGList and C_LFGList.GetSearchResultPlayerInfo then
        events:RegisterEvent("LFG_LIST_SEARCH_RESULTS_RECEIVED")
        events:RegisterEvent("LFG_LIST_SEARCH_RESULT_UPDATED")
    end
    if ChatOn() and AddFilter then
        if not linkHooked and EventRegistry then
            linkHooked = true
            EventRegistry:RegisterCallback("SetItemRef", function(...)
                if ChatOn() then OnLinkClick(...) end
            end, events)
        end
        events:RegisterEvent("CHAT_MSG_GUILD")
        events:RegisterEvent("CHAT_MSG_OFFICER")
        for _, event in ipairs(TAGGED) do
            AddFilter(event, Filter)
        end
        filtering = true
    end
    if FinderOn() then
        HookFinder()
        if not hooked then events:RegisterEvent("ADDON_LOADED") end
    end
    if IsInGuild() then ReadGuild() end
    ReadFriends()
    ReadGroup()
end

module.ChatZones = { Fresh = Fresh, Remember = Remember }
CUI._ChatZones = {
    Get = Get,
    Cfg = F.Cfg,
    Apply = Apply,
    Fresh = Fresh,
    Filter = Filter,
}

F.Start(Apply)
