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
local function Secret(val)
    return issecretvalue and issecretvalue(val)
end
local HOUR, MINUTE = 3600, 60

local function MaxLevel()
    return (GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion()) or 60
end
local function AtMax()
    return UnitLevel("player") >= MaxLevel() or (IsXPUserDisabled and IsXPUserDisabled())
end

local function Short(num)
    if num >= 1e6 then
        return ("%.1fm"):format(num / 1e6)
    end
    if num >= 1e3 then
        return ("%.1fk"):format(num / 1e3)
    end
    return tostring(math.floor(num))
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

local cardFrame
local sessionStart, sessionXP = 0, 0
local paused, pausedAt, pausedTotal = false, nil, 0
local lastXP, lastXPMax
local current, anchor -- the level being timed, and when its clock last started
local trendBase, trendAt, trendDir = 0, 0, 0

-- Per character: { current = { level, base, partial }, levels = { [level] = { total } } }
local function Splits()
    local c = X.Cfg()
    c.chars = c.chars or {}
    local unitGuid = UnitGUID("player")
    if not unitGuid then
        return nil
    end
    c.chars[unitGuid] = c.chars[unitGuid] or { levels = {} }
    return c.chars[unitGuid]
end

local function LevelTime()
    return current and (current.base + (anchor and GetTime() - anchor or 0)) or 0
end

local function StartLevel(cfg, fromStart, level)
    current = { level = level or UnitLevel("player"), base = 0, partial = not fromStart }
    anchor = not paused and GetTime() or nil
    cfg.current = current
end

local function TrackSplits(newLevel)
    local cfg = Splits()
    if not cfg then
        return
    end
    if not current then
        local saved = cfg.current
        if saved and saved.level == UnitLevel("player") then
            current, anchor = saved, not paused and GetTime() or nil
        else
            StartLevel(cfg, UnitXP("player") == 0)
        end
    end
    local level = newLevel or UnitLevel("player")
    if level > current.level then
        cfg.levels[current.level] = { total = not current.partial and LevelTime() or nil }
        StartLevel(cfg, true, level)
    elseif not anchor and not paused then
        anchor = GetTime()
    end
end

local function Btn(hostFrame, textValue, tipText, func)
    local widget = CreateFrame("Button", nil, hostFrame)
    widget:SetSize(16, 16)
    widget.t = widget:CreateFontString(nil, "OVERLAY")
    CludesUI.Kit.Font(widget.t, 12, "essentials")
    widget.t:SetPoint("CENTER")
    widget.t:SetText(textValue)
    widget:SetScript("OnClick", func)
    widget:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(tipText)
        GameTooltip:Show()
    end)
    widget:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    return widget
end

local Update
function module.XPStart()
    if not paused then
        return
    end
    pausedTotal = pausedTotal + GetTime() - pausedAt
    paused, pausedAt = false, nil
    if current then
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
    if current and anchor then
        current.base, anchor = LevelTime(), nil
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
    if cardFrame then
        return cardFrame
    end
    cardFrame = CreateFrame("Frame", "CludesUIXPTicker", UIParent)
    cardFrame:SetSize(190, 60)
    CludesUI.Kit.Panel(cardFrame, 0.75)
    cardFrame.rate = cardFrame:CreateFontString(nil, "OVERLAY")
    cardFrame.rate:SetPoint("TOPLEFT", 8, -6)
    cardFrame.info = cardFrame:CreateFontString(nil, "OVERLAY")
    cardFrame.info:SetPoint("TOPLEFT", cardFrame.rate, "BOTTOMLEFT", 0, -3)
    cardFrame.info:SetJustifyH("LEFT")
    cardFrame.bar = CreateFrame("StatusBar", nil, cardFrame)
    cardFrame.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    cardFrame.bar:SetStatusBarColor(0.58, 0.0, 0.55)
    cardFrame.bar:SetMinMaxValues(0, 1)
    cardFrame.bar:SetPoint("BOTTOMLEFT", 1, 1)
    cardFrame.bar:SetPoint("BOTTOMRIGHT", -1, 1)
    cardFrame.bar:SetHeight(3)
    cardFrame.rested = cardFrame.bar:CreateTexture(nil, "BACKGROUND")
    cardFrame.rested:SetColorTexture(0.0, 0.39, 0.88, 0.6)
    cardFrame.rested:SetPoint("TOPLEFT")
    cardFrame.rested:SetPoint("BOTTOMLEFT")
    cardFrame.toggle = Btn(cardFrame, "||", "Pause or start the session", function()
        if paused then
            module.XPStart()
        else
            module.XPPause()
        end
    end)
    cardFrame.toggle:SetPoint("TOPRIGHT", -22, -4)
    cardFrame.reset = Btn(cardFrame, "o", "Reset the session to zero", module.XPReset)
    cardFrame.reset:SetPoint("TOPRIGHT", -4, -4)
    return cardFrame
end

Update = function()
    if not cardFrame then
        return
    end
    if
        not X.Enabled()
        or (not CludesUI._unlockActive and (AtMax() or (X.Get("hideResting") and IsResting())))
    then
        cardFrame:Hide()
        return
    end
    local size = X.Get("size")
    CludesUI.Kit.Font(cardFrame.rate, size + 4, "essentials")
    CludesUI.Kit.Font(cardFrame.info, size - 3, "essentials")
    local nowTime = GetTime()
    local elapsed = nowTime - sessionStart - pausedTotal - (paused and nowTime - pausedAt or 0)
    local rate = sessionXP / (math.max(elapsed, MINUTE) / HOUR)
    if not paused and nowTime - trendAt >= TREND_WINDOW then
        local diff = rate - trendBase
        trendDir = (trendBase > 0 and math.abs(diff) > trendBase * TREND_MIN_SHARE) and (diff > 0 and 1 or -1)
            or 0
        trendBase, trendAt = rate, nowTime
    end
    local arrow = trendDir > 0 and " |cff60d080+|r" or (trendDir < 0 and " |cffff6060-|r" or "")
    if sessionXP > 0 then
        cardFrame.rate:SetText(
            ("%s%s|r |cff9aa6b2xp/hr|r%s"):format(CludesUI.Kit.AccentHex(), Short(rate), arrow)
        )
    else
        cardFrame.rate:SetText("|cff9aa6b2no XP yet|r")
    end
    local lines = {}
    if rate > 0 then
        local ding = (UnitXPMax("player") - UnitXP("player")) / rate * HOUR
        lines[#lines + 1] = "Ding in " .. Clock(ding)
    end
    lines[#lines + 1] = (paused and "|cffffb040paused|r  " or "") .. "Session " .. Clock(elapsed)
    if current then
        lines[#lines + 1] = ("Level %d  %s%s"):format(
            current.level,
            Clock(LevelTime()),
            current.partial and "+" or ""
        )
    end
    if X.Get("splits") then
        local cfg = Splits()
        local keyList = {}
        for level, rec in pairs(cfg and cfg.levels or {}) do
            if type(level) == "number" and rec.total and (not current or level < current.level) then
                keyList[#keyList + 1] = level
            end
        end
        table.sort(keyList, function(lhs, rhs)
            return lhs > rhs
        end)
        for index = 1, math.min(#keyList, X.Get("history")) do
            lines[#lines + 1] = ("|cff9aa6b2Level %d  %s|r"):format(
                keyList[index],
                Clock(cfg.levels[keyList[index]].total)
            )
        end
    end
    cardFrame.info:SetText(table.concat(lines, "\n"))
    local max = UnitXPMax("player")
    if max > 0 then
        local share = UnitXP("player") / max
        cardFrame.bar:SetValue(share)
        local rested = math.min((GetXPExhaustion() or 0) / max, 1 - share)
        cardFrame.rested:SetWidth(math.max(0.01, (share + rested) * cardFrame.bar:GetWidth()))
    end
    cardFrame.toggle.t:SetText(paused and ">" or "||")
    cardFrame:SetSize(
        math.max(150, cardFrame.rate:GetStringWidth() + 50, cardFrame.info:GetStringWidth() + 16),
        cardFrame.rate:GetStringHeight() + cardFrame.info:GetStringHeight() + 20
    )
    cardFrame:Show()
end

local xEv = CreateFrame("Frame")
xEv:SetScript("OnEvent", function(_, evt, arg1)
    if evt == "PLAYER_LOGOUT" then
        if current then
            current.base = LevelTime()
        end
        return
    end
    if evt == "PLAYER_XP_UPDATE" then
        local xp, max = UnitXP("player"), UnitXPMax("player")
        local gained = xp >= lastXP and xp - lastXP or (lastXPMax - lastXP) + xp
        lastXP, lastXPMax = xp, max
        if not paused then
            sessionXP = sessionXP + gained
        end
    end
    TrackSplits(evt == "PLAYER_LEVEL_UP" and arg1 or nil)
    Update()
end)

local clock
local function XApply()
    if not X.Enabled() then
        if current and anchor then
            current.base, anchor = LevelTime(), nil
        end
        xEv:UnregisterAllEvents()
        if clock then
            clock:Cancel()
            clock = nil
        end
        if cardFrame then
            cardFrame:Hide()
        end
        return
    end
    if not cardFrame then
        Build()
        sessionStart, sessionXP = GetTime(), 0
        trendAt = sessionStart
    end
    if not CludesUI._unlockActive then
        X.Place(cardFrame)
    end
    lastXP, lastXPMax = UnitXP("player"), UnitXPMax("player")
    for _, event in ipairs({
        "PLAYER_XP_UPDATE",
        "PLAYER_UPDATE_RESTING",
        "PLAYER_LEVEL_UP",
        "PLAYER_LOGOUT",
        "UPDATE_EXHAUSTION",
    }) do
        xEv:RegisterEvent(event)
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
        return cardFrame
    end,
    size = function()
        return 190, 60
    end,
    noAnchorTarget = true,
    noSizeMatchTarget = true,
})

SLASH_CUIXP1 = "/cxp"
SlashCmdList.CUIXP = function(message)
    local run = ({ start = module.XPStart, pause = module.XPPause, reset = module.XPReset })[(message or "")
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
local others, rowList = {}, {}
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
    local entries, units = {}, { "player" }
    if IsInRaid() then
        for index = 1, GetNumGroupMembers() do
            local me = UnitIsUnit("raid" .. index, "player")
            if not Secret(me) and not me then
                units[#units + 1] = "raid" .. index
            end
        end
    else
        for index = 1, GetNumSubgroupMembers() do
            units[#units + 1] = "party" .. index
        end
    end
    for _, unitToken in ipairs(units) do
        local name, unitGuid = UnitName(unitToken), UnitGUID(unitToken)
        local _, class = UnitClass(unitToken)
        if name and unitGuid and not (Secret(name) or Secret(unitGuid) or Secret(class)) then
            entries[#entries + 1] = { unit = unitToken, name = name, class = class, guid = unitGuid }
        end
    end
    return entries
end

-- The sender must be the group member whose GUID the message carries.
local function SenderIs(sender, unitGuid)
    local short = Ambiguate(sender, "none")
    for _, m in ipairs(Roster()) do
        if m.guid == unitGuid then
            return m.name == short or short:find("^" .. m.name) ~= nil
        end
    end
    return false
end

local function Row(index)
    local region = rowList[index]
    if region then
        return region
    end
    region = CreateFrame("Frame", nil, gFrame)
    region.name = region:CreateFontString(nil, "OVERLAY")
    region.name:SetPoint("LEFT")
    region.name:SetJustifyH("LEFT")
    region.name:SetWordWrap(false)
    region.bar = CreateFrame("StatusBar", nil, region)
    region.bar:SetPoint("BOTTOMRIGHT")
    region.bar:SetMinMaxValues(0, 1)
    region.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    region.bar:SetStatusBarColor(CludesUI.Kit.Accent())
    CludesUI.Kit.Panel(region.bar, 0.85)
    region.text = region.bar:CreateFontString(nil, "OVERLAY")
    region.text:SetPoint("CENTER")
    rowList[index] = region
    return region
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
    local entries = {}
    if CludesUI._unlockActive and G.Enabled() then
        entries = SAMPLE
    elseif G.Enabled() and IsInGroup() and (G.Get("raid") or not IsInRaid()) then
        for _, m in ipairs(Roster()) do
            if m.unit ~= "player" or G.Get("showSelf") then
                local level = UnitLevel(m.unit)
                if Secret(level) then
                    level = nil
                end
                local payload = m.unit == "player"
                        and { level = UnitLevel("player"), xp = UnitXP("player"), max = UnitXPMax("player") }
                    or others[m.guid]
                local current = payload and payload.level or level
                if not (current and current >= MaxLevel()) then
                    entries[#entries + 1] = { name = m.name, class = m.class, level = level, data = payload }
                end
            end
        end
    end
    if #entries == 0 then
        gFrame:Hide()
        return
    end
    local size = G.Get("size")
    local rowH = math.max(18, size + 6)
    local nameW = 90 * size / 12
    gFrame:SetSize(G.Get("width"), #entries * (rowH + 2) - 2)
    for index, m in ipairs(entries) do
        local region = Row(index)
        region:ClearAllPoints()
        region:SetPoint("TOPLEFT", 0, -(index - 1) * (rowH + 2))
        region:SetPoint("TOPRIGHT", 0, -(index - 1) * (rowH + 2))
        region:SetHeight(rowH)
        CludesUI.Kit.Font(region.name, size, "essentials")
        region.name:SetWidth(nameW - 4)
        CludesUI.Kit.Font(region.text, size - 1, "essentials")
        region.bar:SetPoint("TOPLEFT", nameW, 0)
        local c = m.class and RAID_CLASS_COLORS[m.class]
        region.name:SetText(m.name)
        if c then
            region.name:SetTextColor(c.r, c.g, c.b)
        else
            region.name:SetTextColor(1, 1, 1)
        end
        local skinData = m.data
        if not skinData then
            region.bar:SetValue(0)
            region.text:SetText(
                (m.level and m.level > 0 and ("Lv " .. m.level) or "Lv ?") .. "  |cff9ca3afno addon|r"
            )
        elseif skinData.level >= MaxLevel() or skinData.max <= 0 then
            region.bar:SetValue(1)
            region.text:SetText("Lv " .. skinData.level .. "  Max")
        else
            local pct = skinData.xp / skinData.max
            region.bar:SetValue(pct)
            region.text:SetText(("Lv %d  %.1f%%"):format(skinData.level, pct * 100))
        end
        region:Show()
    end
    for index = #entries + 1, #rowList do
        rowList[index]:Hide()
    end
    gFrame:Show()
end

local gEv = CreateFrame("Frame")
gEv:SetScript("OnEvent", function(_, evt, prefixText, message, channel, sender)
    if evt == "CHAT_MSG_ADDON" then
        if Secret(prefixText) or Secret(message) or Secret(channel) or Secret(sender) then
            return
        end
        if prefixText ~= PREFIX or not GROUP_CHANNELS[channel] then
            return
        end
        if message == ASK then
            SendSoon()
            return
        end
        local unitGuid, level, xp, max = message:match(MESSAGE_PATTERN)
        if not unitGuid or not unitGuid:find("^Player%-") or unitGuid == UnitGUID("player") then
            return
        end
        level, xp, max = tonumber(level), tonumber(xp), tonumber(max)
        if level > 1000 or xp > MAX_XP or max > MAX_XP or not SenderIs(sender, unitGuid) then
            return
        end
        others[unitGuid] = { level = level, xp = xp, max = max }
        return GRefresh()
    elseif evt == "GROUP_ROSTER_UPDATE" or evt == "PLAYER_ENTERING_WORLD" then
        local inGroup = {}
        for _, m in ipairs(Roster()) do
            inGroup[m.guid] = true
        end
        for unitGuid in pairs(others) do
            if not inGroup[unitGuid] then
                others[unitGuid] = nil
            end
        end
        SendSoon(evt == "PLAYER_ENTERING_WORLD")
    elseif evt == "PLAYER_XP_UPDATE" or evt == "PLAYER_LEVEL_UP" then
        SendSoon()
    elseif evt == "PLAYER_REGEN_ENABLED" then
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
    for _, event in ipairs({
        "CHAT_MSG_ADDON",
        "GROUP_ROSTER_UPDATE",
        "PLAYER_ENTERING_WORLD",
        "PLAYER_XP_UPDATE",
        "PLAYER_LEVEL_UP",
        "UNIT_LEVEL",
        "PLAYER_REGEN_ENABLED",
    }) do
        gEv:RegisterEvent(event)
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
