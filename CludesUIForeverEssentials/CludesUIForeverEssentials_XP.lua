if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if not (CludesUI and CludesUI.IS_FOREVER) then
    return
end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_XP.lua  (WoW Forever only)
--  XP per Hour: this session's XP per hour, the time to your next level at
--  that rate, an arrow when the rate is rising or falling, the session's time,
--  and how long your last levels took. Pause and reset buttons on the card;
--  /cxp start, pause or reset. Hidden at max level and, if you like, while
--  resting.
--  Group XP: a bar per group member with their level and XP. It needs them to
--  run CludesUI or Naowh Forever: both send the same "NaowhGroupXP" message,
--  so each sees the other's bars. Members without either show "no addon".
-------------------------------------------------------------------------------
local _, module = ...

local function Font()
    return CludesUI.GetFontPath("essentials")
end
local function Secret(v)
    return issecretvalue and issecretvalue(v)
end
local HOUR, MINUTE = 3600, 60

local function MaxLevel()
    return (GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion()) or 60
end
local function AtMax()
    return UnitLevel("player") >= MaxLevel() or (IsXPUserDisabled and IsXPUserDisabled())
end

local function Short(n)
    if n >= 1e6 then
        return ("%.1fm"):format(n / 1e6)
    end
    if n >= 1e3 then
        return ("%.1fk"):format(n / 1e3)
    end
    return tostring(math.floor(n))
end

local function Clock(s)
    s = math.max(0, math.floor(s + 0.5))
    if s >= 86400 then
        return ("%dd %dh %dm"):format(
            math.floor(s / 86400),
            math.floor(s / HOUR) % 24,
            math.floor(s / MINUTE) % 60
        )
    end
    if s >= HOUR then
        return ("%d:%02d:%02d"):format(math.floor(s / HOUR), math.floor(s / MINUTE) % 60, s % 60)
    end
    return ("%d:%02d"):format(math.floor(s / MINUTE), s % 60)
end

-------------------------------------------------------------------------------
--  XP per Hour
-------------------------------------------------------------------------------
local X = module.Feature(
    "xpTicker",
    { enabled = false, hideResting = true, splits = true, history = 5, size = 16 },
    { point = "CENTER", relPoint = "CENTER", x = -300, y = 0 }
)
local TREND_WINDOW, TREND_MIN_SHARE = 180, 0.05

local card
local sessionStart, sessionXP = 0, 0
local paused, pausedAt, pausedTotal = false, nil, 0
local lastXP, lastXPMax
local cur, anchor -- the level being timed, and when its clock last started
local trendBase, trendAt, trendDir = 0, 0, 0

-- Per character: { current = { level, base, partial }, levels = { [level] = { total } } }
local function Splits()
    local c = X.Cfg()
    c.chars = c.chars or {}
    local guid = UnitGUID("player")
    if not guid then
        return nil
    end
    c.chars[guid] = c.chars[guid] or { levels = {} }
    return c.chars[guid]
end

local function LevelTime()
    return cur and (cur.base + (anchor and GetTime() - anchor or 0)) or 0
end

local function StartLevel(s, fromStart, level)
    cur = { level = level or UnitLevel("player"), base = 0, partial = not fromStart }
    anchor = not paused and GetTime() or nil
    s.current = cur
end

local function TrackSplits(newLevel)
    local s = Splits()
    if not s then
        return
    end
    if not cur then
        local saved = s.current
        if saved and saved.level == UnitLevel("player") then
            cur, anchor = saved, not paused and GetTime() or nil
        else
            StartLevel(s, UnitXP("player") == 0)
        end
    end
    local level = newLevel or UnitLevel("player")
    if level > cur.level then
        s.levels[cur.level] = { total = not cur.partial and LevelTime() or nil }
        StartLevel(s, true, level)
    elseif not anchor and not paused then
        anchor = GetTime()
    end
end

local function Btn(parent, text, tip, fn)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(16, 16)
    b.t = b:CreateFontString(nil, "OVERLAY")
    CludesUI.Kit.Font(b.t, 12, "essentials")
    b.t:SetPoint("CENTER")
    b.t:SetText(text)
    b:SetScript("OnClick", fn)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(tip)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    return b
end

local Update
function module.XPStart()
    if not paused then
        return
    end
    pausedTotal = pausedTotal + GetTime() - pausedAt
    paused, pausedAt = false, nil
    if cur then
        anchor = GetTime()
    end
    if Update then
        Update()
    end
end
function module.XPPause()
    if paused then
        return
    end
    paused, pausedAt = true, GetTime()
    if cur and anchor then
        cur.base, anchor = LevelTime(), nil
    end
    if Update then
        Update()
    end
end
function module.XPReset()
    sessionStart, sessionXP, pausedTotal = GetTime(), 0, 0
    trendBase, trendAt, trendDir = 0, sessionStart, 0
    if paused then
        pausedAt = sessionStart
    end
    if Update then
        Update()
    end
end

local function Build()
    if card then
        return card
    end
    card = CreateFrame("Frame", "CludesUIXPTicker", UIParent)
    card:SetSize(190, 60)
    CludesUI.Kit.Panel(card, 0.75)
    card.rate = card:CreateFontString(nil, "OVERLAY")
    card.rate:SetPoint("TOPLEFT", 8, -6)
    card.info = card:CreateFontString(nil, "OVERLAY")
    card.info:SetPoint("TOPLEFT", card.rate, "BOTTOMLEFT", 0, -3)
    card.info:SetJustifyH("LEFT")
    card.bar = CreateFrame("StatusBar", nil, card)
    card.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    card.bar:SetStatusBarColor(0.58, 0.0, 0.55)
    card.bar:SetMinMaxValues(0, 1)
    card.bar:SetPoint("BOTTOMLEFT", 1, 1)
    card.bar:SetPoint("BOTTOMRIGHT", -1, 1)
    card.bar:SetHeight(3)
    card.rested = card.bar:CreateTexture(nil, "BACKGROUND")
    card.rested:SetColorTexture(0.0, 0.39, 0.88, 0.6)
    card.rested:SetPoint("TOPLEFT")
    card.rested:SetPoint("BOTTOMLEFT")
    card.toggle = Btn(card, "||", "Pause or start the session", function()
        if paused then
            module.XPStart()
        else
            module.XPPause()
        end
    end)
    card.toggle:SetPoint("TOPRIGHT", -22, -4)
    card.reset = Btn(card, "o", "Reset the session to zero", module.XPReset)
    card.reset:SetPoint("TOPRIGHT", -4, -4)
    return card
end

Update = function()
    if not card then
        return
    end
    if
        not X.Enabled()
        or (not CludesUI._unlockActive and (AtMax() or (X.Get("hideResting") and IsResting())))
    then
        card:Hide()
        return
    end
    local size = X.Get("size")
    CludesUI.Kit.Font(card.rate, size + 4, "essentials")
    CludesUI.Kit.Font(card.info, size - 3, "essentials")
    local now = GetTime()
    local elapsed = now - sessionStart - pausedTotal - (paused and now - pausedAt or 0)
    local rate = sessionXP / (math.max(elapsed, MINUTE) / HOUR)
    if not paused and now - trendAt >= TREND_WINDOW then
        local diff = rate - trendBase
        trendDir = (trendBase > 0 and math.abs(diff) > trendBase * TREND_MIN_SHARE) and (diff > 0 and 1 or -1)
            or 0
        trendBase, trendAt = rate, now
    end
    local arrow = trendDir > 0 and " |cff60d080+|r" or (trendDir < 0 and " |cffff6060-|r" or "")
    if sessionXP > 0 then
        card.rate:SetText(("%s%s|r |cff9aa6b2xp/hr|r%s"):format(CludesUI.Kit.AccentHex(), Short(rate), arrow))
    else
        card.rate:SetText("|cff9aa6b2no XP yet|r")
    end
    local lines = {}
    if rate > 0 then
        local ding = (UnitXPMax("player") - UnitXP("player")) / rate * HOUR
        lines[#lines + 1] = "Ding in " .. Clock(ding)
    end
    lines[#lines + 1] = (paused and "|cffffb040paused|r  " or "") .. "Session " .. Clock(elapsed)
    if cur then
        lines[#lines + 1] = ("Level %d  %s%s"):format(
            cur.level,
            Clock(LevelTime()),
            cur.partial and "+" or ""
        )
    end
    if X.Get("splits") then
        local s = Splits()
        local keys = {}
        for level, rec in pairs(s and s.levels or {}) do
            if type(level) == "number" and rec.total and (not cur or level < cur.level) then
                keys[#keys + 1] = level
            end
        end
        table.sort(keys, function(a, b)
            return a > b
        end)
        for i = 1, math.min(#keys, X.Get("history")) do
            lines[#lines + 1] = ("|cff9aa6b2Level %d  %s|r"):format(keys[i], Clock(s.levels[keys[i]].total))
        end
    end
    card.info:SetText(table.concat(lines, "\n"))
    local max = UnitXPMax("player")
    if max > 0 then
        local share = UnitXP("player") / max
        card.bar:SetValue(share)
        local rested = math.min((GetXPExhaustion() or 0) / max, 1 - share)
        card.rested:SetWidth(math.max(0.01, (share + rested) * card.bar:GetWidth()))
    end
    card.toggle.t:SetText(paused and ">" or "||")
    card:SetSize(
        math.max(150, card.rate:GetStringWidth() + 50, card.info:GetStringWidth() + 16),
        card.rate:GetStringHeight() + card.info:GetStringHeight() + 20
    )
    card:Show()
end

local xEv = CreateFrame("Frame")
xEv:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_LOGOUT" then
        if cur then
            cur.base = LevelTime()
        end
        return
    end
    if event == "PLAYER_XP_UPDATE" then
        local xp, max = UnitXP("player"), UnitXPMax("player")
        local gained = xp >= lastXP and xp - lastXP or (lastXPMax - lastXP) + xp
        lastXP, lastXPMax = xp, max
        if not paused then
            sessionXP = sessionXP + gained
        end
    end
    TrackSplits(event == "PLAYER_LEVEL_UP" and arg1 or nil)
    Update()
end)

local clock
local function XApply()
    if not X.Enabled() then
        if cur and anchor then
            cur.base, anchor = LevelTime(), nil
        end
        xEv:UnregisterAllEvents()
        if clock then
            clock:Cancel()
            clock = nil
        end
        if card then
            card:Hide()
        end
        return
    end
    if not card then
        Build()
        sessionStart, sessionXP = GetTime(), 0
        trendAt = sessionStart
    end
    if not CludesUI._unlockActive then
        X.Place(card)
    end
    lastXP, lastXPMax = UnitXP("player"), UnitXPMax("player")
    for _, e in ipairs({
        "PLAYER_XP_UPDATE",
        "PLAYER_UPDATE_RESTING",
        "PLAYER_LEVEL_UP",
        "PLAYER_LOGOUT",
        "UPDATE_EXHAUSTION",
    }) do
        xEv:RegisterEvent(e)
    end
    TrackSplits()
    if not clock then
        clock = C_Timer.NewTicker(1, Update)
    end
    Update()
end

X.Start(XApply, {
    key = "CUI_XPTicker",
    label = "XP per Hour",
    order = 751,
    frame = function(build)
        if build then
            Build()
            Update()
        end
        return card
    end,
    size = function()
        return 190, 60
    end,
    noAnchorTarget = true,
    noSizeMatchTarget = true,
})

SLASH_CUIXP1 = "/cxp"
SlashCmdList.CUIXP = function(msg)
    local run = ({ start = module.XPStart, pause = module.XPPause, reset = module.XPReset })[(msg or "")
        :lower()
        :match("%S+") or ""]
    if run then
        run()
    else
        CludesUI.Print("|cff4cc9f0XP:|r /cxp start, pause or reset")
    end
end

-------------------------------------------------------------------------------
--  Group XP
-------------------------------------------------------------------------------
local G = module.Feature(
    "groupXP",
    { enabled = false, showSelf = true, raid = false, width = 260, size = 12 },
    { point = "LEFT", relPoint = "LEFT", x = 40, y = 120 }
)
local PREFIX = "NaowhGroupXP"
local ASK = "R"
local MESSAGE = "2 %s %d %d %d"
local MESSAGE_PATTERN = "^2 (%S+) (%d+) (%d+) (%d+)$"
local GROUP_CHANNELS = { PARTY = true, RAID = true, INSTANCE_CHAT = true }
local MAX_XP = 2 ^ 31

local gFrame
local others, rows = {}, {}
local sendQueued, sendAfterCombat, requestPending

local function Channel()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        return "INSTANCE_CHAT"
    end
    if IsInRaid() then
        return "RAID"
    end
    if IsInGroup() then
        return "PARTY"
    end
end

local function Send()
    local channel = Channel()
    if not channel then
        requestPending = false
        return
    end
    if InCombatLockdown() then
        sendAfterCombat = true
        return
    end
    if requestPending then
        requestPending = false
        C_ChatInfo.SendAddonMessage(PREFIX, ASK, channel)
    end
    C_ChatInfo.SendAddonMessage(
        PREFIX,
        MESSAGE:format(UnitGUID("player"), UnitLevel("player"), UnitXP("player"), UnitXPMax("player")),
        channel
    )
end

local function SendSoon(request)
    if request then
        requestPending = true
    end
    if sendQueued then
        return
    end
    sendQueued = true
    C_Timer.After(2, function()
        sendQueued = false
        Send()
    end)
end

local function Roster()
    local list, units = {}, { "player" }
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local me = UnitIsUnit("raid" .. i, "player")
            if not Secret(me) and not me then
                units[#units + 1] = "raid" .. i
            end
        end
    else
        for i = 1, GetNumSubgroupMembers() do
            units[#units + 1] = "party" .. i
        end
    end
    for _, unit in ipairs(units) do
        local name, guid = UnitName(unit), UnitGUID(unit)
        local _, class = UnitClass(unit)
        if name and guid and not (Secret(name) or Secret(guid) or Secret(class)) then
            list[#list + 1] = { unit = unit, name = name, class = class, guid = guid }
        end
    end
    return list
end

-- The sender must be the group member whose GUID the message carries.
local function SenderIs(sender, guid)
    local short = Ambiguate(sender, "none")
    for _, m in ipairs(Roster()) do
        if m.guid == guid then
            return m.name == short or short:find("^" .. m.name) ~= nil
        end
    end
    return false
end

local function Row(i)
    local r = rows[i]
    if r then
        return r
    end
    r = CreateFrame("Frame", nil, gFrame)
    r.name = r:CreateFontString(nil, "OVERLAY")
    r.name:SetPoint("LEFT")
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.bar = CreateFrame("StatusBar", nil, r)
    r.bar:SetPoint("BOTTOMRIGHT")
    r.bar:SetMinMaxValues(0, 1)
    r.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    r.bar:SetStatusBarColor(CludesUI.Kit.Accent())
    CludesUI.Kit.Panel(r.bar, 0.85)
    r.text = r.bar:CreateFontString(nil, "OVERLAY")
    r.text:SetPoint("CENTER")
    rows[i] = r
    return r
end

local SAMPLE = {
    { name = "Tank", class = "WARRIOR", data = { level = 24, xp = 11000, max = 12200 } },
    { name = "Healer", class = "PRIEST", data = { level = 25, xp = 3100, max = 13100 } },
    { name = "Rogue", class = "ROGUE", level = 23 },
}

local function GRefresh()
    if not gFrame then
        return
    end
    local list = {}
    if CludesUI._unlockActive and G.Enabled() then
        list = SAMPLE
    elseif G.Enabled() and IsInGroup() and (G.Get("raid") or not IsInRaid()) then
        for _, m in ipairs(Roster()) do
            if m.unit ~= "player" or G.Get("showSelf") then
                local level = UnitLevel(m.unit)
                if Secret(level) then
                    level = nil
                end
                local data = m.unit == "player"
                        and { level = UnitLevel("player"), xp = UnitXP("player"), max = UnitXPMax("player") }
                    or others[m.guid]
                local current = data and data.level or level
                if not (current and current >= MaxLevel()) then
                    list[#list + 1] = { name = m.name, class = m.class, level = level, data = data }
                end
            end
        end
    end
    if #list == 0 then
        gFrame:Hide()
        return
    end
    local size = G.Get("size")
    local rowH = math.max(18, size + 6)
    local nameW = 90 * size / 12
    gFrame:SetSize(G.Get("width"), #list * (rowH + 2) - 2)
    for i, m in ipairs(list) do
        local r = Row(i)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 0, -(i - 1) * (rowH + 2))
        r:SetPoint("TOPRIGHT", 0, -(i - 1) * (rowH + 2))
        r:SetHeight(rowH)
        CludesUI.Kit.Font(r.name, size, "essentials")
        r.name:SetWidth(nameW - 4)
        CludesUI.Kit.Font(r.text, size - 1, "essentials")
        r.bar:SetPoint("TOPLEFT", nameW, 0)
        local c = m.class and RAID_CLASS_COLORS[m.class]
        r.name:SetText(m.name)
        if c then
            r.name:SetTextColor(c.r, c.g, c.b)
        else
            r.name:SetTextColor(1, 1, 1)
        end
        local d = m.data
        if not d then
            r.bar:SetValue(0)
            r.text:SetText(
                (m.level and m.level > 0 and ("Lv " .. m.level) or "Lv ?") .. "  |cff9ca3afno addon|r"
            )
        elseif d.level >= MaxLevel() or d.max <= 0 then
            r.bar:SetValue(1)
            r.text:SetText("Lv " .. d.level .. "  Max")
        else
            local pct = d.xp / d.max
            r.bar:SetValue(pct)
            r.text:SetText(("Lv %d  %.1f%%"):format(d.level, pct * 100))
        end
        r:Show()
    end
    for i = #list + 1, #rows do
        rows[i]:Hide()
    end
    gFrame:Show()
end

local gEv = CreateFrame("Frame")
gEv:SetScript("OnEvent", function(_, event, prefix, msg, channel, sender)
    if event == "CHAT_MSG_ADDON" then
        if Secret(prefix) or Secret(msg) or Secret(channel) or Secret(sender) then
            return
        end
        if prefix ~= PREFIX or not GROUP_CHANNELS[channel] then
            return
        end
        if msg == ASK then
            SendSoon()
            return
        end
        local guid, level, xp, max = msg:match(MESSAGE_PATTERN)
        if not guid or not guid:find("^Player%-") or guid == UnitGUID("player") then
            return
        end
        level, xp, max = tonumber(level), tonumber(xp), tonumber(max)
        if level > 1000 or xp > MAX_XP or max > MAX_XP or not SenderIs(sender, guid) then
            return
        end
        others[guid] = { level = level, xp = xp, max = max }
        return GRefresh()
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        local inGroup = {}
        for _, m in ipairs(Roster()) do
            inGroup[m.guid] = true
        end
        for guid in pairs(others) do
            if not inGroup[guid] then
                others[guid] = nil
            end
        end
        SendSoon(event == "PLAYER_ENTERING_WORLD")
    elseif event == "PLAYER_XP_UPDATE" or event == "PLAYER_LEVEL_UP" then
        SendSoon()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if sendAfterCombat then
            sendAfterCombat = false
            Send()
        end
        return
    end
    GRefresh()
end)

local function GApply()
    gEv:UnregisterAllEvents()
    if not G.Enabled() then
        if gFrame then
            gFrame:Hide()
        end
        return
    end
    if not gFrame then
        gFrame = CreateFrame("Frame", "CludesUIGroupXP", UIParent)
    end
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    for _, e in ipairs({
        "CHAT_MSG_ADDON",
        "GROUP_ROSTER_UPDATE",
        "PLAYER_ENTERING_WORLD",
        "PLAYER_XP_UPDATE",
        "PLAYER_LEVEL_UP",
        "UNIT_LEVEL",
        "PLAYER_REGEN_ENABLED",
    }) do
        gEv:RegisterEvent(e)
    end
    if not CludesUI._unlockActive then
        G.Place(gFrame)
    end
    SendSoon(true)
    GRefresh()
end

G.Start(GApply, {
    key = "CUI_GroupXP",
    label = "Group XP",
    order = 752,
    frame = function(build)
        if build and not gFrame then
            gFrame = CreateFrame("Frame", "CludesUIGroupXP", UIParent)
        end
        if build then
            GRefresh()
        end
        return gFrame
    end,
    size = function()
        return G.Get("width"), 3 * 20
    end,
    noAnchorTarget = true,
    noSizeMatchTarget = true,
})

CludesUI._XP = {
    ticker = { Get = X.Get, Cfg = X.Cfg, Apply = XApply },
    group = { Get = G.Get, Cfg = G.Cfg, Apply = GApply },
}
