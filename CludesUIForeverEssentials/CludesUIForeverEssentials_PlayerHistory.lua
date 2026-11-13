if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if not (CludesUI and CludesUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_PlayerHistory.lua  (WoW Forever only)
--  Player History: the players you group with, remembered on this computer:
--  how often you grouped, the dungeons and raids you ran together, the last
--  sessions, and (if you like) your last whispers and group chat with them.
--  Your notes: right-click a player for "Player Note" to give them a tag
--  (Great Tank, Great Healer, Great DPS, Friendly, Avoid) and a note; both
--  show on their tooltip. /chistory lists everyone, searchable.
--  A group counts once it lasts a minute; a reload or relog within five
--  minutes carries the group on. Forgets players unseen for a set number of
--  days (notes are kept), and keeps at most 1000.
-------------------------------------------------------------------------------
local _, module = ...

local F = module.Feature("playerHistory", { enabled = false, chats = true, days = 90, tooltip = true })
local Get, Enabled = F.Get, F.Enabled

local MAX_PLAYERS, MAX_SESSIONS, MAX_CHATS = 1000, 10, 10
local MIN_SESSION, RESUME = 60, 300
local MAX_TEXT, MAX_NOTE = 200, 120
local DAY = 86400
local TAGS = {
    { key = "tank", label = "Great Tank", good = true }, { key = "healer", label = "Great Healer", good = true },
    { key = "dps", label = "Great DPS", good = true }, { key = "friendly", label = "Friendly", good = true },
    { key = "avoid", label = "Avoid", good = false },
}
local TAG = {}
for _, t in ipairs(TAGS) do TAG[t.key] = t end
local CHANNEL = {
    CHAT_MSG_WHISPER = "WHISPER", CHAT_MSG_WHISPER_INFORM = "WHISPER",
    CHAT_MSG_PARTY = "PARTY", CHAT_MSG_PARTY_LEADER = "PARTY",
    CHAT_MSG_RAID = "RAID", CHAT_MSG_RAID_LEADER = "RAID", CHAT_MSG_RAID_WARNING = "RAID",
    CHAT_MSG_INSTANCE_CHAT = "INSTANCE_CHAT", CHAT_MSG_INSTANCE_CHAT_LEADER = "INSTANCE_CHAT",
}

local function Secret(v) return issecretvalue and issecretvalue(v) end
local function Readable(v) return type(v) == "string" and not Secret(v) and v ~= "" end
local function IsPlayerGUID(g) return type(g) == "string" and not Secret(g) and #g <= 64 and g:find("^Player%-") ~= nil end
local function Font() return (CludesUI.GetFontPath and CludesUI.GetFontPath()) or STANDARD_TEXT_FONT end

local function Cap(text, max)
    if #text <= max then return text end
    local cut = max
    while cut > 0 do
        local b = text:byte(cut + 1)
        if b < 128 or b > 191 then break end
        cut = cut - 1
    end
    return text:sub(1, cut)
end

local function Clean(text, max)
    if text:find("|", 1, true) then
        text = text:gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", ""):gsub("|A.-|a", "")
            :gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|n", " ")
    end
    if text == "" then return nil end
    return Cap(text, max)
end

local players, notes, count, myGUID
local open, seen, curInst, curPlace, curType = {}, {}, nil, nil, nil
local resume, resumeAt

local function Load()
    if players then return true end
    local c = F.Cfg()
    c.players = c.players or {}
    c.notes = c.notes or {}
    players, notes = c.players, c.notes
    local cutoff = time() - math.max(7, math.min(365, Get("days"))) * DAY
    count = 0
    for guid, rec in pairs(players) do
        if type(rec) ~= "table" or (rec.lastSeen or 0) < cutoff and not notes[guid] then players[guid] = nil
        else count = count + 1 end
    end
    if c.resume and type(c.resume) == "table" then resume, resumeAt = c.resume, c.resume.at end
    c.resume = nil
    return true
end

local function Push(list, cap)
    for i = math.min(#list, cap - 1), 1, -1 do list[i + 1] = list[i] end
    for i = cap + 1, #list do list[i] = nil end
    local e = {}
    list[1] = e
    return e
end

local function Record(guid, now)
    local rec = players[guid]
    if rec then return rec end
    if count >= MAX_PLAYERS then
        local oldest, at
        for g, r in pairs(players) do
            if not open[g] and not notes[g] and (not at or r.lastSeen < at) then oldest, at = g, r.lastSeen end
        end
        if not oldest then return nil end
        players[oldest] = nil
        count = count - 1
    end
    rec = { sessions = {}, chats = {}, firstSeen = now, lastSeen = now, groups = 0, dungeons = 0, raids = 0 }
    if notes[guid] and notes[guid].name then rec.name = notes[guid].name end
    players[guid] = rec
    count = count + 1
    return rec
end

local function Learn(rec, unit)
    local first, second = UnitFullName(unit)
    if Readable(first) and not Secret(second) then rec.name = Readable(second) and (first .. " " .. second) or first end
    local _, class = UnitClass(unit)
    if Readable(class) then rec.classFile = class end
end

local function Enter(st)
    if st.inst == curInst then return end
    st.inst, st.place, st.instance = curInst, curPlace, curType
    if curType == "raid" then st.raids = st.raids + 1 else st.dungeons = st.dungeons + 1 end
end

local function Open(guid, unit, now, raid)
    local rec = Record(guid, now)
    if not rec then return end
    Learn(rec, unit)
    rec.lastSeen = now
    local st = { at = now, raid = raid, dungeons = 0, raids = 0, extend = false }
    local r = resume and resume[guid]
    if resume then resume[guid] = nil end
    if type(r) == "table" and resumeAt and now - resumeAt <= RESUME and r.at and r.at <= now then
        st.at, st.raid = r.at, st.raid or r.raid
        st.inst, st.place, st.instance = r.inst, r.place, r.instance
        st.dungeons, st.raids = r.dungeons or 0, r.raids or 0
        local lastS = rec.sessions[1]
        st.extend = r.kept == true and lastS ~= nil and lastS.at == r.at
    end
    open[guid] = st
    if curInst then Enter(st) end
end

local function Close(guid, now)
    local st, rec = open[guid], players[guid]
    local seconds = now - st.at
    if rec and (st.extend or seconds >= MIN_SESSION) then
        local s = st.extend and rec.sessions[1]
        if not s then s = Push(rec.sessions, MAX_SESSIONS); rec.groups = rec.groups + 1 end
        s.at, s.seconds, s.kind, s.place, s.instance = st.at, seconds, st.raid and "raid" or "party", st.place, st.instance
        rec.dungeons, rec.raids = rec.dungeons + st.dungeons, rec.raids + st.raids
        rec.lastSeen = now
    end
    open[guid] = nil
end

local function Scan(now)
    wipe(seen)
    local members = GetNumGroupMembers() or 0
    local function Seen(unit, raid)
        local guid = UnitGUID(unit)
        if not IsPlayerGUID(guid) or guid == myGUID then return end
        seen[guid] = true
        if open[guid] then if raid then open[guid].raid = true end else Open(guid, unit, now, raid) end
    end
    if IsInRaid() then for i = 1, math.min(members, 40) do Seen("raid" .. i, true) end
    elseif members > 0 then for i = 1, 4 do Seen("party" .. i, false) end end
    for guid in pairs(open) do if not seen[guid] then Close(guid, now) end end
end

local function Instance()
    local name, kind, _, _, _, _, _, id = GetInstanceInfo()
    if Secret(kind) or Secret(id) or Secret(name) or (kind ~= "party" and kind ~= "raid") or type(id) ~= "number" then
        curInst, curPlace, curType = nil, nil, nil
        return
    end
    curInst, curType, curPlace = id, kind, (type(name) == "string" and name ~= "") and name or nil
    for _, st in pairs(open) do Enter(st) end
end

local function Logout()
    local now, saved = time(), nil
    for guid, st in pairs(open) do
        local kept = st.extend or now - st.at >= MIN_SESSION
        saved = saved or {}
        saved[guid] = { at = st.at, raid = st.raid, inst = st.inst, place = st.place, instance = st.instance,
            kept = kept, dungeons = kept and 0 or st.dungeons, raids = kept and 0 or st.raids }
        Close(guid, now)
    end
    if saved then saved.at = now; F.Cfg().resume = saved end
end

local function AddChat(rec, now, mine, channel, text)
    local e = Push(rec.chats, MAX_CHATS)
    e.at, e.mine, e.channel, e.text = now, mine, channel, text
    rec.lastSeen = now
end

local function Chat(event, text, sender, _, _, _, _, _, _, _, _, _, guid)
    if type(guid) ~= "string" or Secret(guid) or Secret(text) or Secret(sender) or type(text) ~= "string" then return end
    local channel = CHANNEL[event]
    if channel == "WHISPER" then
        if guid == myGUID or not IsPlayerGUID(guid) then return end
        local clean = Clean(text, MAX_TEXT)
        if not clean then return end
        local rec = Record(guid, time())
        if not rec then return end
        if not rec.name and Readable(sender) then rec.name = Ambiguate(sender, "none") end
        if not rec.classFile then
            local _, class = GetPlayerInfoByGUID(guid)
            if Readable(class) then rec.classFile = class end
        end
        AddChat(rec, time(), event == "CHAT_MSG_WHISPER_INFORM", "WHISPER", clean)
    elseif guid == myGUID then
        if next(open) == nil or IsInRaid() then return end
        local clean = Clean(text, MAX_TEXT)
        if not clean then return end
        for other in pairs(open) do if players[other] then AddChat(players[other], time(), true, channel, clean) end end
    elseif open[guid] and players[guid] then
        local clean = Clean(text, MAX_TEXT)
        if clean then AddChat(players[guid], time(), false, channel, clean) end
    end
end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event, ...)
    if CHANNEL[event] then return Chat(event, ...) end
    if event == "GROUP_ROSTER_UPDATE" then Scan(time())
    elseif event == "PLAYER_LOGOUT" then Logout()
    else Instance(); Scan(time()) end
end)

-------------------------------------------------------------------------------
--  Notes
-------------------------------------------------------------------------------
function module.PlayerNote(guid) Load(); return notes[guid] end

function module.SetPlayerNote(guid, text, tag, name)
    if not IsPlayerGUID(guid) or guid == UnitGUID("player") then return false end
    if tag ~= nil and not TAG[tag] then return false end
    Load()
    text = (type(text) == "string" and not Secret(text)) and Clean(text, MAX_NOTE) or nil
    if not text and not tag then notes[guid] = nil return true end
    local note = notes[guid] or {}
    note.text, note.tag, note.at = text, tag, time()
    if Readable(name) then
        note.name = name
        if players[guid] then players[guid].name = name end
    end
    notes[guid] = note
    return true
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip, data)
        if not Get("tooltip") or (tooltip.IsForbidden and tooltip:IsForbidden()) then return end
        local guid = data and data.guid
        if type(guid) ~= "string" or Secret(guid) then return end
        Load()
        local note, rec = notes[guid], players[guid]
        if note then
            local t = TAG[note.tag]
            if t then
                if t.good then tooltip:AddLine(t.label, 0.4, 0.9, 0.5) else tooltip:AddLine(t.label, 1, 0.3, 0.3) end
            else
                tooltip:AddLine("Note", 0.3, 0.79, 0.94)
            end
            if note.text then tooltip:AddLine(note.text, 1, 1, 1, true) end
        end
        if rec and Enabled() and (rec.groups or 0) > 0 then
            tooltip:AddLine(("Grouped %d time%s, %d dungeon%s, %d raid%s"):format(rec.groups, rec.groups == 1 and "" or "s",
                rec.dungeons, rec.dungeons == 1 and "" or "s", rec.raids, rec.raids == 1 and "" or "s"), 0.6, 0.6, 0.6)
        end
    end)
end

StaticPopupDialogs["CLUDESUI_PLAYER_NOTE"] = {
    text = "Note on %s",
    button1 = ACCEPT, button2 = CANCEL,
    hasEditBox = true, maxLetters = MAX_NOTE,
    OnShow = function(self, data)
        local note = module.PlayerNote(data.guid)
        local box = self.editBox or self.EditBox
        box:SetText(note and note.text or "")
        box:HighlightText()
    end,
    OnAccept = function(self, data)
        local box = self.editBox or self.EditBox
        local note = module.PlayerNote(data.guid)
        module.SetPlayerNote(data.guid, box:GetText(), note and note.tag, data.name)
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        StaticPopupDialogs["CLUDESUI_PLAYER_NOTE"].OnAccept(parent, parent.data)
        parent:Hide()
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

local menusAdded
local function AddMenus()
    if menusAdded or not (Menu and Menu.ModifyMenu) then return end
    menusAdded = true
    local function Entries(_, root, ctx)
        if type(ctx) ~= "table" then return end
        local guid, name
        local unit = ctx.unit
        if type(unit) == "string" and not Secret(unit) then
            if UnitIsUnit(unit, "player") then return end
            guid = UnitGUID(unit)
            local first, second = UnitFullName(unit)
            if Readable(first) then name = Readable(second) and (first .. " " .. second) or first end
        else
            guid = ctx.playerLocation and ctx.playerLocation.GetGUID and ctx.playerLocation:GetGUID()
            name = Readable(ctx.name) and ctx.name or nil
        end
        if not IsPlayerGUID(guid) then return end
        root:CreateDivider()
        local sub = root:CreateButton("Player Note")
        sub:CreateButton("Write a Note", function() StaticPopup_Show("CLUDESUI_PLAYER_NOTE", name or "this player", nil, { guid = guid, name = name }) end)
        for _, t in ipairs(TAGS) do
            sub:CreateRadio(t.label, function() local n = module.PlayerNote(guid); return n and n.tag == t.key end,
                function()
                    local n = module.PlayerNote(guid)
                    local tag = (n and n.tag == t.key) and nil or t.key
                    module.SetPlayerNote(guid, n and n.text, tag, name)
                end)
        end
        sub:CreateButton("Clear Note", function() module.SetPlayerNote(guid, nil, nil) end)
    end
    for _, which in ipairs({ "PLAYER", "TARGET", "FOCUS", "PARTY", "RAID_PLAYER", "RAID", "FRIEND", "CHAT_ROSTER",
                             "COMMUNITIES_GUILD_MEMBER", "COMMUNITIES_WOW_MEMBER", "GUILD" }) do
        pcall(Menu.ModifyMenu, "MENU_UNIT_" .. which, function(owner, root, ctx) pcall(Entries, owner, root, ctx) end)
    end
end

-------------------------------------------------------------------------------
--  Window
-------------------------------------------------------------------------------
local win, rows, scroll, content, search
local function Ago(s)
    if s < 3600 then return math.floor(s / 60) .. "m" end
    if s < DAY then return math.floor(s / 3600) .. "h" end
    return math.floor(s / DAY) .. "d"
end

local function Refresh()
    if not (win and win:IsShown()) then return end
    Load()
    local filter = (search:GetText() or ""):lower()
    local list = {}
    local seenG = {}
    for guid, rec in pairs(players) do
        seenG[guid] = true
        local note = notes[guid]
        local hay = ((rec.name or "") .. " " .. (note and note.text or "")):lower()
        if filter == "" or hay:find(filter, 1, true) then list[#list + 1] = { guid = guid, rec = rec, note = note } end
    end
    for guid, note in pairs(notes) do
        if not seenG[guid] then
            local hay = ((note.name or "") .. " " .. (note.text or "")):lower()
            if filter == "" or hay:find(filter, 1, true) then list[#list + 1] = { guid = guid, rec = { name = note.name, lastSeen = note.at, groups = 0, dungeons = 0, raids = 0 }, note = note } end
        end
    end
    table.sort(list, function(a, b) return (a.rec.lastSeen or 0) > (b.rec.lastSeen or 0) end)
    rows = rows or {}
    for i, e in ipairs(list) do
        local r = rows[i]
        if not r then
            r = content:CreateFontString(nil, "OVERLAY")
            r:SetFont(Font(), 12, "")
            r:SetJustifyH("LEFT")
            r:SetWidth(500)
            r:SetWordWrap(false)
            rows[i] = r
        end
        local rec, note = e.rec, e.note
        local c = rec.classFile and RAID_CLASS_COLORS[rec.classFile]
        local name = rec.name or "?"
        if c then name = c:WrapTextInColorCode(name) end
        local tag = note and TAG[note.tag]
        r:SetPoint("TOPLEFT", 0, -(i - 1) * 16)
        r:SetText(("%s  |cff9aa6b2%d groups, %d dungeons, %d raids, %s ago|r%s%s"):format(name, rec.groups or 0, rec.dungeons or 0,
            rec.raids or 0, Ago(time() - (rec.lastSeen or time())),
            tag and ((tag.good and "  |cff60d080" or "  |cffff5050") .. tag.label .. "|r") or "",
            note and note.text and ("  |cffffffff" .. note.text .. "|r") or ""))
        r:Show()
    end
    for i = #list + 1, #rows do rows[i]:Hide() end
    content:SetHeight(math.max(1, #list) * 16)
    win.count:SetText(#list .. " players")
end

function module.ShowPlayerHistory()
    if not win then
        win = CreateFrame("Frame", "CludesUIPlayerHistory", UIParent, "BackdropTemplate")
        win:SetSize(540, 420)
        win:SetPoint("CENTER")
        win:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        win:SetBackdropColor(0.06, 0.07, 0.09, 0.95)
        win:SetBackdropBorderColor(0.30, 0.79, 0.94, 0.8)
        win:SetMovable(true); win:EnableMouse(true); win:RegisterForDrag("LeftButton")
        win:SetScript("OnDragStart", win.StartMoving)
        win:SetScript("OnDragStop", win.StopMovingOrSizing)
        win:SetFrameStrata("HIGH")
        local t = win:CreateFontString(nil, "OVERLAY")
        t:SetFont(Font(), 15, "OUTLINE")
        t:SetPoint("TOPLEFT", 10, -8)
        t:SetText("|cff4cc9f0Player History|r")
        win.count = win:CreateFontString(nil, "OVERLAY")
        win.count:SetFont(Font(), 11, "")
        win.count:SetPoint("LEFT", t, "RIGHT", 10, 0)
        local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", 2, 2)
        search = CreateFrame("EditBox", nil, win, "InputBoxTemplate")
        search:SetSize(200, 20)
        search:SetPoint("TOPLEFT", 14, -30)
        search:SetAutoFocus(false)
        search:SetScript("OnTextChanged", Refresh)
        scroll = CreateFrame("ScrollFrame", nil, win, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 10, -58)
        scroll:SetPoint("BOTTOMRIGHT", -30, 10)
        content = CreateFrame("Frame", nil, scroll)
        content:SetSize(500, 10)
        scroll:SetScrollChild(content)
        tinsert(UISpecialFrames, "CludesUIPlayerHistory")
    end
    win:Show()
    Refresh()
end

function module.ClearPlayerHistory(which)
    Load()
    if which == "notes" then wipe(notes) else wipe(players); count = 0; wipe(open); resume = nil end
    Refresh()
end

-------------------------------------------------------------------------------
--  Apply
-------------------------------------------------------------------------------
local active
local function Apply()
    AddMenus()
    if Enabled() then
        Load()
        myGUID = UnitGUID("player")
        if players[myGUID] then players[myGUID] = nil; count = count - 1 end
        for _, e in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "PLAYER_LOGOUT" }) do ev:RegisterEvent(e) end
        for event in pairs(CHANNEL) do
            if Get("chats") then ev:RegisterEvent(event) else ev:UnregisterEvent(event) end
        end
        if not active then active = true; Instance(); Scan(time()) end
    elseif active then
        active = false
        ev:UnregisterAllEvents()
        local now = time()
        for guid in pairs(open) do Close(guid, now) end
    end
end

CludesUI._PlayerHistory = { Get = Get, Cfg = F.Cfg, Apply = Apply, Show = function() module.ShowPlayerHistory() end,
    Clear = module.ClearPlayerHistory }

SLASH_CUIHISTORY1 = "/chistory"
SlashCmdList.CUIHISTORY = function() module.ShowPlayerHistory() end

F.Start(Apply)
