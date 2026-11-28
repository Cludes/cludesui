if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
if not (CUI and CUI.IS_FOREVER) then return end
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

local TOP_PEOPLE, TOP_VISITS, TOP_TALKS = 1000, 10, 10
local LEAST_VISIT, CONTINUE = 60, 300
local TOP_LABEL, TOP_JOT = 200, 120
local DAILY = 86400
local LABELS = {
    { key = "tank", label = "Great Tank", good = true },
    { key = "healer", label = "Great Healer", good = true },
    { key = "dps", label = "Great DPS", good = true },
    { key = "friendly", label = "Friendly", good = true },
    { key = "avoid", label = "Avoid", good = false },
}
local LABEL = {}
for _, tag in ipairs(LABELS) do
    LABEL[tag.key] = tag
end
local MEDIUM = {
    CHAT_MSG_WHISPER = "WHISPER",
    CHAT_MSG_WHISPER_INFORM = "WHISPER",
    CHAT_MSG_PARTY = "PARTY",
    CHAT_MSG_PARTY_LEADER = "PARTY",
    CHAT_MSG_RAID = "RAID",
    CHAT_MSG_RAID_LEADER = "RAID",
    CHAT_MSG_RAID_WARNING = "RAID",
    CHAT_MSG_INSTANCE_CHAT = "INSTANCE_CHAT",
    CHAT_MSG_INSTANCE_CHAT_LEADER = "INSTANCE_CHAT",
}

local function Secret(v) return issecretvalue and issecretvalue(v) end
local function Plain(v) return type(v) == "string" and not Secret(v) and v ~= "" end
local function IsPersonId(g)
    return type(g) == "string" and not Secret(g) and #g <= 64 and g:find("^Player%-") ~= nil
end
local function Typeface() return CUI.GetFontPath("essentials") end

local function Limit(text, top)
    if #text <= top then return text end
    local cut = top
    while cut > 0 do
        local b = text:byte(cut + 1)
        if b < 128 or b > 191 then break end
        cut = cut - 1
    end
    return text:sub(1, cut)
end

local function Tidy(text, top)
    if text:find("|", 1, true) then
        text = text:gsub("|H.-|h(.-)|h", "%1")
            :gsub("|T.-|t", "")
            :gsub("|A.-|a", "")
            :gsub("|c%x%x%x%x%x%x%x%x", "")
            :gsub("|r", "")
            :gsub("|n", " ")
    end
    if text == "" then return nil end
    return Limit(text, top)
end

local people, notes, tally, myId
local reveal, spotted, curInst, curPlace, curType = {}, {}, nil, nil, nil
local continue, continueAt

local function Read()
    if people then return true end
    local cfg = F.Cfg()
    cfg.players = cfg.players or {}
    cfg.notes = cfg.notes or {}
    people, notes = cfg.players, cfg.notes
    local cutoff = time() - math.max(7, math.min(365, Get("days"))) * DAILY
    tally = 0
    for guid, rec in pairs(people) do
        if type(rec) ~= "table" or (rec.lastSeen or 0) < cutoff and not notes[guid] then
            people[guid] = nil
        else
            tally = tally + 1
        end
    end
    if cfg.resume and type(cfg.resume) == "table" then
        continue, continueAt = cfg.resume, cfg.resume.at
    end
    cfg.resume = nil
    return true
end

local function Append(roster, limit)
    for i = math.min(#roster, limit - 1), 1, -1 do
        roster[i + 1] = roster[i]
    end
    for i = limit + 1, #roster do
        roster[i] = nil
    end
    local e = {}
    roster[1] = e
    return e
end

local function Log(guid, now)
    local rec = people[guid]
    if rec then return rec end
    if tally >= TOP_PEOPLE then
        local oldest, at
        for g, region in pairs(people) do
            if not reveal[g] and not notes[g] and (not at or region.lastSeen < at) then
                oldest, at = g, region.lastSeen
            end
        end
        if not oldest then return nil end
        people[oldest] = nil
        tally = tally - 1
    end
    rec = { sessions = {}, chats = {}, firstSeen = now, lastSeen = now, groups = 0, dungeons = 0, raids = 0 }
    if notes[guid] and notes[guid].name then rec.name = notes[guid].name end
    people[guid] = rec
    tally = tally + 1
    return rec
end

local function Gather(rec, unit)
    local first, second = UnitFullName(unit)
    if Plain(first) and not Secret(second) then
        rec.name = Plain(second) and (first .. " " .. second) or first
    end
    local _, calling = UnitClass(unit)
    if Plain(calling) then rec.classFile = calling end
end

local function Join(st)
    if st.inst == curInst then return end
    st.inst, st.place, st.instance = curInst, curPlace, curType
    if curType == "raid" then
        st.raids = st.raids + 1
    else
        st.dungeons = st.dungeons + 1
    end
end

local function Reveal(guid, unit, now, raid)
    local rec = Log(guid, now)
    if not rec then return end
    Gather(rec, unit)
    rec.lastSeen = now
    local st = { at = now, raid = raid, dungeons = 0, raids = 0, extend = false }
    local region = continue and continue[guid]
    if continue then continue[guid] = nil end
    if
        type(region) == "table"
        and continueAt
        and now - continueAt <= CONTINUE
        and region.at
        and region.at <= now
    then
        st.at, st.raid = region.at, st.raid or region.raid
        st.inst, st.place, st.instance = region.inst, region.place, region.instance
        st.dungeons, st.raids = region.dungeons or 0, region.raids or 0
        local lastS = rec.sessions[1]
        st.extend = region.kept == true and lastS ~= nil and lastS.at == region.at
    end
    reveal[guid] = st
    if curInst then Join(st) end
end

local function Shut(guid, now)
    local st, rec = reveal[guid], people[guid]
    local seconds = now - st.at
    if rec and (st.extend or seconds >= LEAST_VISIT) then
        local cfg = st.extend and rec.sessions[1]
        if not cfg then
            cfg = Append(rec.sessions, TOP_VISITS)
            rec.groups = rec.groups + 1
        end
        cfg.at, cfg.seconds, cfg.kind, cfg.place, cfg.instance =
            st.at, seconds, st.raid and "raid" or "party", st.place, st.instance
        rec.dungeons, rec.raids = rec.dungeons + st.dungeons, rec.raids + st.raids
        rec.lastSeen = now
    end
    reveal[guid] = nil
end

local function Sweep(now)
    wipe(spotted)
    local members = GetNumGroupMembers() or 0
    local function Spotted(unit, raid)
        local guid = UnitGUID(unit)
        if not IsPersonId(guid) or guid == myId then return end
        spotted[guid] = true
        if reveal[guid] then
            if raid then reveal[guid].raid = true end
        else
            Reveal(guid, unit, now, raid)
        end
    end
    if IsInRaid() then
        for i = 1, math.min(members, 40) do
            Spotted("raid" .. i, true)
        end
    elseif members > 0 then
        for i = 1, 4 do
            Spotted("party" .. i, false)
        end
    end
    for guid in pairs(reveal) do
        if not spotted[guid] then Shut(guid, now) end
    end
end

local function Dungeon()
    local title, kind, _, _, _, _, _, id = GetInstanceInfo()
    if
        Secret(kind)
        or Secret(id)
        or Secret(title)
        or (kind ~= "party" and kind ~= "raid")
        or type(id) ~= "number"
    then
        curInst, curPlace, curType = nil, nil, nil
        return
    end
    curInst, curType, curPlace = id, kind, (type(title) == "string" and title ~= "") and title or nil
    for _, st in pairs(reveal) do
        Join(st)
    end
end

local function Leave()
    local now, saved = time(), nil
    for guid, st in pairs(reveal) do
        local kept = st.extend or now - st.at >= LEAST_VISIT
        saved = saved or {}
        saved[guid] = {
            at = st.at,
            raid = st.raid,
            inst = st.inst,
            place = st.place,
            instance = st.instance,
            kept = kept,
            dungeons = kept and 0 or st.dungeons,
            raids = kept and 0 or st.raids,
        }
        Shut(guid, now)
    end
    if saved then
        saved.at = now
        F.Cfg().resume = saved
    end
end

local function PutTalk(rec, now, mine, medium, text)
    local e = Append(rec.chats, TOP_TALKS)
    e.at, e.mine, e.channel, e.text = now, mine, medium, text
    rec.lastSeen = now
end

local function Talk(event, text, sender, _, _, _, _, _, _, _, _, _, guid)
    if type(guid) ~= "string" or Secret(guid) or Secret(text) or Secret(sender) or type(text) ~= "string" then
        return
    end
    local medium = MEDIUM[event]
    if medium == "WHISPER" then
        if guid == myId or not IsPersonId(guid) then return end
        local tidy = Tidy(text, TOP_LABEL)
        if not tidy then return end
        local rec = Log(guid, time())
        if not rec then return end
        if not rec.name and Plain(sender) then rec.name = Ambiguate(sender, "none") end
        if not rec.classFile then
            local _, calling = GetPlayerInfoByGUID(guid)
            if Plain(calling) then rec.classFile = calling end
        end
        PutTalk(rec, time(), event == "CHAT_MSG_WHISPER_INFORM", "WHISPER", tidy)
    elseif guid == myId then
        if next(reveal) == nil or IsInRaid() then return end
        local tidy = Tidy(text, TOP_LABEL)
        if not tidy then return end
        for other in pairs(reveal) do
            if people[other] then PutTalk(people[other], time(), true, medium, tidy) end
        end
    elseif reveal[guid] and people[guid] then
        local tidy = Tidy(text, TOP_LABEL)
        if tidy then PutTalk(people[guid], time(), false, medium, tidy) end
    end
end

local eventWindow = CreateFrame("Frame")
eventWindow:SetScript("OnEvent", function(_, event, ...)
    if MEDIUM[event] then return Talk(event, ...) end
    if event == "GROUP_ROSTER_UPDATE" then
        Sweep(time())
    elseif event == "PLAYER_LOGOUT" then
        Leave()
    else
        Dungeon()
        Sweep(time())
    end
end)

-------------------------------------------------------------------------------
--  Notes
-------------------------------------------------------------------------------
function module.PlayerNote(guid)
    Read()
    return notes[guid]
end

function module.SetPlayerNote(guid, text, tag, title)
    if not IsPersonId(guid) or guid == UnitGUID("player") then return false end
    if tag ~= nil and not LABEL[tag] then return false end
    Read()
    text = (type(text) == "string" and not Secret(text)) and Tidy(text, TOP_JOT) or nil
    if not text and not tag then
        notes[guid] = nil
        return true
    end
    local jot = notes[guid] or {}
    jot.text, jot.tag, jot.at = text, tag, time()
    if Plain(title) then
        jot.name = title
        if people[guid] then people[guid].name = title end
    end
    notes[guid] = jot
    return true
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip, info)
        if not Get("tooltip") or (tooltip.IsForbidden and tooltip:IsForbidden()) then return end
        local guid = info and info.guid
        if type(guid) ~= "string" or Secret(guid) then return end
        Read()
        local jot, rec = notes[guid], people[guid]
        if jot then
            local tbl = LABEL[jot.tag]
            if tbl then
                if tbl.good then
                    tooltip:AddLine(tbl.label, 0.4, 0.9, 0.5)
                else
                    tooltip:AddLine(tbl.label, 1, 0.3, 0.3)
                end
            else
                tooltip:AddLine("Note", CUI.Kit.Accent())
            end
            if jot.text then tooltip:AddLine(jot.text, 1, 1, 1, true) end
        end
        if rec and Enabled() and (rec.groups or 0) > 0 then
            tooltip:AddLine(
                ("Grouped %d time%s, %d dungeon%s, %d raid%s"):format(
                    rec.groups,
                    rec.groups == 1 and "" or "s",
                    rec.dungeons,
                    rec.dungeons == 1 and "" or "s",
                    rec.raids,
                    rec.raids == 1 and "" or "s"
                ),
                0.6,
                0.6,
                0.6
            )
        end
    end)
end

StaticPopupDialogs["CLUDESUI_PLAYER_NOTE"] = {
    text = "Note on %s",
    button1 = ACCEPT,
    button2 = CANCEL,
    hasEditBox = true,
    maxLetters = TOP_JOT,
    OnShow = function(self, info)
        local jot = module.PlayerNote(info.guid)
        local box = self.editBox or self.EditBox
        box:SetText(jot and jot.text or "")
        box:HighlightText()
    end,
    OnAccept = function(self, info)
        local box = self.editBox or self.EditBox
        local jot = module.PlayerNote(info.guid)
        module.SetPlayerNote(info.guid, box:GetText(), jot and jot.tag, info.name)
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        StaticPopupDialogs["CLUDESUI_PLAYER_NOTE"].OnAccept(parent, parent.data)
        parent:Hide()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

local optionsAdded
local function PutOptions()
    if optionsAdded or not (Menu and Menu.ModifyMenu) then return end
    optionsAdded = true
    local function Items(_, root, ctx)
        if type(ctx) ~= "table" then return end
        local guid, title
        local unit = ctx.unit
        if type(unit) == "string" and not Secret(unit) then
            if UnitIsUnit(unit, "player") then return end
            guid = UnitGUID(unit)
            local first, second = UnitFullName(unit)
            if Plain(first) then title = Plain(second) and (first .. " " .. second) or first end
        else
            guid = ctx.playerLocation and ctx.playerLocation.GetGUID and ctx.playerLocation:GetGUID()
            title = Plain(ctx.name) and ctx.name or nil
        end
        if not IsPersonId(guid) then return end
        root:CreateDivider()
        local sub = root:CreateButton("Player Note")
        sub:CreateButton(
            "Write a Note",
            function()
                StaticPopup_Show(
                    "CLUDESUI_PLAYER_NOTE",
                    title or "this player",
                    nil,
                    { guid = guid, name = title }
                )
            end
        )
        for _, tag in ipairs(LABELS) do
            sub:CreateRadio(tag.label, function()
                local n = module.PlayerNote(guid)
                return n and n.tag == tag.key
            end, function()
                local n = module.PlayerNote(guid)
                local tag = (n and n.tag == tag.key) and nil or tag.key
                module.SetPlayerNote(guid, n and n.text, tag, title)
            end)
        end
        sub:CreateButton("Clear Note", function() module.SetPlayerNote(guid, nil, nil) end)
    end
    for _, which in ipairs({
        "PLAYER",
        "TARGET",
        "FOCUS",
        "PARTY",
        "RAID_PLAYER",
        "RAID",
        "FRIEND",
        "CHAT_ROSTER",
        "COMMUNITIES_GUILD_MEMBER",
        "COMMUNITIES_WOW_MEMBER",
        "GUILD",
    }) do
        pcall(
            Menu.ModifyMenu,
            "MENU_UNIT_" .. which,
            function(owner, root, ctx) pcall(Items, owner, root, ctx) end
        )
    end
end

-------------------------------------------------------------------------------
--  Window
-------------------------------------------------------------------------------
local win, lines, scroll, content, search
local function Since(s)
    if s < 3600 then return math.floor(s / 60) .. "m" end
    if s < DAILY then return math.floor(s / 3600) .. "h" end
    return math.floor(s / DAILY) .. "d"
end

local function Renew()
    if not (win and win:IsShown()) then return end
    Read()
    local sieve = (search:GetText() or ""):lower()
    local roster = {}
    local spottedG = {}
    for guid, rec in pairs(people) do
        spottedG[guid] = true
        local jot = notes[guid]
        local hay = ((rec.name or "") .. " " .. (jot and jot.text or "")):lower()
        if sieve == "" or hay:find(sieve, 1, true) then
            roster[#roster + 1] = { guid = guid, rec = rec, note = jot }
        end
    end
    for guid, jot in pairs(notes) do
        if not spottedG[guid] then
            local hay = ((jot.name or "") .. " " .. (jot.text or "")):lower()
            if sieve == "" or hay:find(sieve, 1, true) then
                roster[#roster + 1] = {
                    guid = guid,
                    rec = { name = jot.name, lastSeen = jot.at, groups = 0, dungeons = 0, raids = 0 },
                    note = jot,
                }
            end
        end
    end
    table.sort(roster, function(lhs, rhs) return (lhs.rec.lastSeen or 0) > (rhs.rec.lastSeen or 0) end)
    lines = lines or {}
    for i, item in ipairs(roster) do
        local region = lines[i]
        if not region then
            region = content:CreateFontString(nil, "OVERLAY")
            CUI.Kit.Font(region, 12, "essentials")
            region:SetJustifyH("LEFT")
            region:SetWidth(500)
            region:SetWordWrap(false)
            lines[i] = region
        end
        local rec, jot = item.rec, item.note
        local c = rec.classFile and RAID_CLASS_COLORS[rec.classFile]
        local title = rec.name or "?"
        if c then title = c:WrapTextInColorCode(title) end
        local tag = jot and LABEL[jot.tag]
        region:SetPoint("TOPLEFT", 0, -(i - 1) * 16)
        region:SetText(
            ("%s  |cff9aa6b2%d groups, %d dungeons, %d raids, %s ago|r%s%s"):format(
                title,
                rec.groups or 0,
                rec.dungeons or 0,
                rec.raids or 0,
                Since(time() - (rec.lastSeen or time())),
                tag and ((tag.good and "  |cff60d080" or "  |cffff5050") .. tag.label .. "|r") or "",
                jot and jot.text and ("  |cffffffff" .. jot.text .. "|r") or ""
            )
        )
        region:Show()
    end
    for i = #roster + 1, #lines do
        lines[i]:Hide()
    end
    content:SetHeight(math.max(1, #roster) * 16)
    win.count:SetText(#roster .. " players")
end

function module.ShowPlayerHistory()
    if not win then
        win = CreateFrame("Frame", "CludesUIPlayerHistory", UIParent)
        win:SetSize(540, 420)
        win:SetPoint("CENTER")
        CUI.Kit.Panel(win, 0.95)
        win:SetMovable(true)
        win:EnableMouse(true)
        win:RegisterForDrag("LeftButton")
        win:SetScript("OnDragStart", win.StartMoving)
        win:SetScript("OnDragStop", win.StopMovingOrSizing)
        win:SetFrameStrata("HIGH")
        local label = win:CreateFontString(nil, "OVERLAY")
        CUI.Kit.Font(label, 15, "essentials")
        label:SetPoint("TOPLEFT", 10, -8)
        label:SetText("Player History")
        CUI.Kit.AccentText(label)
        win.count = win:CreateFontString(nil, "OVERLAY")
        CUI.Kit.Font(win.count, 11, "essentials")
        win.count:SetPoint("LEFT", label, "RIGHT", 10, 0)
        local shut = CUI.Kit.Glyph(win, "x", function() win:Hide() end, nil, "essentials")
        shut:SetPoint("TOPRIGHT", -5, -5)
        search = CUI.Kit.Input(win, 200, 20, "Search a name or tag", "essentials")
        search:SetPoint("TOPLEFT", 10, -34)
        search:HookScript("OnTextChanged", Renew)
        scroll = (CUI.Kit.Scroll(win))
        scroll:SetPoint("TOPLEFT", 10, -58)
        scroll:SetPoint("BOTTOMRIGHT", -30, 10)
        content = CreateFrame("Frame", nil, scroll)
        content:SetSize(500, 10)
        scroll:SetScrollChild(content)
        tinsert(UISpecialFrames, "CludesUIPlayerHistory")
    end
    win:Show()
    Renew()
end

function module.ClearPlayerHistory(which)
    Read()
    if which == "notes" then
        wipe(notes)
    else
        wipe(people)
        tally = 0
        wipe(reveal)
        continue = nil
    end
    Renew()
end

-------------------------------------------------------------------------------
--  Apply
-------------------------------------------------------------------------------
local active
local function Apply()
    PutOptions()
    if Enabled() then
        Read()
        myId = UnitGUID("player")
        if people[myId] then
            people[myId] = nil
            tally = tally - 1
        end
        for _, event in ipairs({
            "GROUP_ROSTER_UPDATE",
            "PLAYER_ENTERING_WORLD",
            "ZONE_CHANGED_NEW_AREA",
            "PLAYER_LOGOUT",
        }) do
            eventWindow:RegisterEvent(event)
        end
        for event in pairs(MEDIUM) do
            if Get("chats") then
                eventWindow:RegisterEvent(event)
            else
                eventWindow:UnregisterEvent(event)
            end
        end
        if not active then
            active = true
            Dungeon()
            Sweep(time())
        end
    elseif active then
        active = false
        eventWindow:UnregisterAllEvents()
        local now = time()
        for guid in pairs(reveal) do
            Shut(guid, now)
        end
    end
end

CUI._PlayerHistory = {
    Get = Get,
    Cfg = F.Cfg,
    Apply = Apply,
    Show = function() module.ShowPlayerHistory() end,
    Clear = module.ClearPlayerHistory,
}

SLASH_CUIHISTORY1 = "/chistory"
SlashCmdList.CUIHISTORY = function() module.ShowPlayerHistory() end

F.Start(Apply)
