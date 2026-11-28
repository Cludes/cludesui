if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
if not (CUI and CUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_XP.lua  (WoW Forever only)
--  XP per Hour: this session's XP per hour, the time to your next level at
--  that rate, an arrow when the rate is rising or falling, the session's time,
--  and how long your last levels took. Pause and reset buttons on the card;
--  /cxp start, pause or reset. Hidden at max level and, if you like, while
--  resting.
--  Group XP: a bar per group member with their level and XP. It needs them to
--  run an addon that sends the "CludesGroupXP" message (CludesUI does),
--  so each sees the other's bars. Members without one show "no addon".
-------------------------------------------------------------------------------
local _, module = ...

local function Typeface() return CUI.GetFontPath("essentials") end
local function Secret(val) return issecretvalue and issecretvalue(val) end
local HOUR, MINUTE = 3600, 60

local function TopLvl() return (GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion()) or 60 end
local function AtTop() return UnitLevel("player") >= TopLvl() or (IsXPUserDisabled and IsXPUserDisabled()) end

local function Lacking(num)
    if num >= 1e6 then return ("%.1fm"):format(num / 1e6) end
    if num >= 1e3 then return ("%.1fk"):format(num / 1e3) end
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
local TREND_FRAME, TREND_LEAST_SHARE = 180, 0.05

local tileWindow
local visitStart, visitXP = 0, 0
local paused, pausedAt, pausedTotal = false, nil, 0
local lastXP, lastXPTop
local current, anchor -- the level being timed, and when its clock last started
local trendBase, trendAt, trendDir = 0, 0, 0

-- Per character: { current = { level, base, partial }, levels = { [level] = { total } } }
local function Splits()
    local c = X.Cfg()
    c.chars = c.chars or {}
    local unitId = UnitGUID("player")
    if not unitId then return nil end
    c.chars[unitId] = c.chars[unitId] or { levels = {} }
    return c.chars[unitId]
end

local function LvlTime() return current and (current.base + (anchor and GetTime() - anchor or 0)) or 0 end

local function StartLvl(cfg, fromStart, lvl)
    current = { level = lvl or UnitLevel("player"), base = 0, partial = not fromStart }
    anchor = not paused and GetTime() or nil
    cfg.current = current
end

local function TrackSplits(freshLvl)
    local cfg = Splits()
    if not cfg then return end
    if not current then
        local saved = cfg.current
        if saved and saved.level == UnitLevel("player") then
            current, anchor = saved, not paused and GetTime() or nil
        else
            StartLvl(cfg, UnitXP("player") == 0)
        end
    end
    local lvl = freshLvl or UnitLevel("player")
    if lvl > current.level then
        cfg.levels[current.level] = { total = not current.partial and LvlTime() or nil }
        StartLvl(cfg, true, lvl)
    elseif not anchor and not paused then
        anchor = GetTime()
    end
end

local function Btn(hostWindow, labelValue, hintLabel, func)
    local widget = CreateFrame("Button", nil, hostWindow)
    widget:SetSize(16, 16)
    widget.t = widget:CreateFontString(nil, "OVERLAY")
    CUI.Kit.Font(widget.t, 12, "essentials")
    widget.t:SetPoint("CENTER")
    widget.t:SetText(labelValue)
    widget:SetScript("OnClick", func)
    widget:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(hintLabel)
        GameTooltip:Show()
    end)
    widget:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return widget
end

local Refresh
function module.XPStart()
    if not paused then return end
    pausedTotal = pausedTotal + GetTime() - pausedAt
    paused, pausedAt = false, nil
    if current then anchor = GetTime() end
    if Refresh then Refresh() end
end
function module.XPPause()
    if paused then return end
    paused, pausedAt = true, GetTime()
    if current and anchor then
        current.base, anchor = LvlTime(), nil
    end
    if Refresh then Refresh() end
end
function module.XPReset()
    visitStart, visitXP, pausedTotal = GetTime(), 0, 0
    trendBase, trendAt, trendDir = 0, visitStart, 0
    if paused then pausedAt = visitStart end
    if Refresh then Refresh() end
end

local function Make()
    if tileWindow then return tileWindow end
    tileWindow = CreateFrame("Frame", "CludesUIXPTicker", UIParent)
    tileWindow:SetSize(190, 60)
    CUI.Kit.Panel(tileWindow, 0.75)
    tileWindow.rate = tileWindow:CreateFontString(nil, "OVERLAY")
    tileWindow.rate:SetPoint("TOPLEFT", 8, -6)
    tileWindow.info = tileWindow:CreateFontString(nil, "OVERLAY")
    tileWindow.info:SetPoint("TOPLEFT", tileWindow.rate, "BOTTOMLEFT", 0, -3)
    tileWindow.info:SetJustifyH("LEFT")
    tileWindow.bar = CreateFrame("StatusBar", nil, tileWindow)
    tileWindow.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    tileWindow.bar:SetStatusBarColor(0.58, 0.0, 0.55)
    tileWindow.bar:SetMinMaxValues(0, 1)
    tileWindow.bar:SetPoint("BOTTOMLEFT", 1, 1)
    tileWindow.bar:SetPoint("BOTTOMRIGHT", -1, 1)
    tileWindow.bar:SetHeight(3)
    tileWindow.rested = tileWindow.bar:CreateTexture(nil, "BACKGROUND")
    tileWindow.rested:SetColorTexture(0.0, 0.39, 0.88, 0.6)
    tileWindow.rested:SetPoint("TOPLEFT")
    tileWindow.rested:SetPoint("BOTTOMLEFT")
    tileWindow.toggle = Btn(tileWindow, "||", "Pause or start the session", function()
        if paused then
            module.XPStart()
        else
            module.XPPause()
        end
    end)
    tileWindow.toggle:SetPoint("TOPRIGHT", -22, -4)
    tileWindow.reset = Btn(tileWindow, "o", "Reset the session to zero", module.XPReset)
    tileWindow.reset:SetPoint("TOPRIGHT", -4, -4)
    return tileWindow
end

Refresh = function()
    if not tileWindow then return end
    if
        not X.Enabled()
        or (not CUI._unlockActive and (AtTop() or (X.Get("hideResting") and IsResting())))
    then
        tileWindow:Hide()
        return
    end
    local dims = X.Get("size")
    CUI.Kit.Font(tileWindow.rate, dims + 4, "essentials")
    CUI.Kit.Font(tileWindow.info, dims - 3, "essentials")
    local nowTime = GetTime()
    local elapsed = nowTime - visitStart - pausedTotal - (paused and nowTime - pausedAt or 0)
    local rate = visitXP / (math.max(elapsed, MINUTE) / HOUR)
    if not paused and nowTime - trendAt >= TREND_FRAME then
        local diff = rate - trendBase
        trendDir = (trendBase > 0 and math.abs(diff) > trendBase * TREND_LEAST_SHARE) and (diff > 0 and 1 or -1)
            or 0
        trendBase, trendAt = rate, nowTime
    end
    local arrow = trendDir > 0 and " |cff60d080+|r" or (trendDir < 0 and " |cffff6060-|r" or "")
    if visitXP > 0 then
        tileWindow.rate:SetText(
            ("%s%s|r |cff9aa6b2xp/hr|r%s"):format(CUI.Kit.AccentHex(), Lacking(rate), arrow)
        )
    else
        tileWindow.rate:SetText("|cff9aa6b2no XP yet|r")
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
            Clock(LvlTime()),
            current.partial and "+" or ""
        )
    end
    if X.Get("splits") then
        local cfg = Splits()
        local idRoster = {}
        for lvl, rec in pairs(cfg and cfg.levels or {}) do
            if type(lvl) == "number" and rec.total and (not current or lvl < current.level) then
                idRoster[#idRoster + 1] = lvl
            end
        end
        table.sort(idRoster, function(lhs, rhs) return lhs > rhs end)
        for catalog = 1, math.min(#idRoster, X.Get("history")) do
            lines[#lines + 1] = ("|cff9aa6b2Level %d  %s|r"):format(
                idRoster[catalog],
                Clock(cfg.levels[idRoster[catalog]].total)
            )
        end
    end
    tileWindow.info:SetText(table.concat(lines, "\n"))
    local top = UnitXPMax("player")
    if top > 0 then
        local share = UnitXP("player") / top
        tileWindow.bar:SetValue(share)
        local rested = math.min((GetXPExhaustion() or 0) / top, 1 - share)
        tileWindow.rested:SetWidth(math.max(0.01, (share + rested) * tileWindow.bar:GetWidth()))
    end
    tileWindow.toggle.t:SetText(paused and ">" or "||")
    tileWindow:SetSize(
        math.max(150, tileWindow.rate:GetStringWidth() + 50, tileWindow.info:GetStringWidth() + 16),
        tileWindow.rate:GetStringHeight() + tileWindow.info:GetStringHeight() + 20
    )
    tileWindow:Show()
end

local xEv = CreateFrame("Frame")
xEv:SetScript("OnEvent", function(_, evt, arg1)
    if evt == "PLAYER_LOGOUT" then
        if current then current.base = LvlTime() end
        return
    end
    if evt == "PLAYER_XP_UPDATE" then
        local xp, top = UnitXP("player"), UnitXPMax("player")
        local gained = xp >= lastXP and xp - lastXP or (lastXPTop - lastXP) + xp
        lastXP, lastXPTop = xp, top
        if not paused then visitXP = visitXP + gained end
    end
    TrackSplits(evt == "PLAYER_LEVEL_UP" and arg1 or nil)
    Refresh()
end)

local clock
local function XUse()
    if not X.Enabled() then
        if current and anchor then
            current.base, anchor = LvlTime(), nil
        end
        xEv:UnregisterAllEvents()
        if clock then
            clock:Cancel()
            clock = nil
        end
        if tileWindow then tileWindow:Hide() end
        return
    end
    if not tileWindow then
        Make()
        visitStart, visitXP = GetTime(), 0
        trendAt = visitStart
    end
    if not CUI._unlockActive then X.Place(tileWindow) end
    lastXP, lastXPTop = UnitXP("player"), UnitXPMax("player")
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
    if not clock then clock = C_Timer.NewTicker(1, Refresh) end
    Refresh()
end

X.Start(XUse, {
    key = "CUI_XPTicker",
    label = "XP per Hour",
    order = 751,
    frame = function(make)
        if make then
            Make()
            Refresh()
        end
        return tileWindow
    end,
    size = function() return 190, 60 end,
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
        CUI.Print("|cff4cc9f0XP:|r /cxp start, pause or reset")
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
local LEAD = "CludesGroupXP"
local ASK = "R"
local MESSAGE = "2 %s %d %d %d"
local MESSAGE_PATTERN = "^2 (%S+) (%d+) (%d+) (%d+)$"
local GROUP_CHANNELS = { PARTY = true, RAID = true, INSTANCE_CHAT = true }
local TOP_XP = 2 ^ 31

local gWindow
local others, lineRoster = {}, {}
local sendQueued, sendLaterCombat, requestPending

local function Medium()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
end

local function Send()
    local medium = Medium()
    if not medium then
        requestPending = false
        return
    end
    if InCombatLockdown() then
        sendLaterCombat = true
        return
    end
    if requestPending then
        requestPending = false
        C_ChatInfo.SendAddonMessage(LEAD, ASK, medium)
    end
    C_ChatInfo.SendAddonMessage(
        LEAD,
        MESSAGE:format(UnitGUID("player"), UnitLevel("player"), UnitXP("player"), UnitXPMax("player")),
        medium
    )
end

local function SendSoon(request)
    if request then requestPending = true end
    if sendQueued then return end
    sendQueued = true
    C_Timer.After(2, function()
        sendQueued = false
        Send()
    end)
end

local function Roster()
    local items, units = {}, { "player" }
    if IsInRaid() then
        for catalog = 1, GetNumGroupMembers() do
            local me = UnitIsUnit("raid" .. catalog, "player")
            if not Secret(me) and not me then units[#units + 1] = "raid" .. catalog end
        end
    else
        for catalog = 1, GetNumSubgroupMembers() do
            units[#units + 1] = "party" .. catalog
        end
    end
    for _, unitToken in ipairs(units) do
        local title, unitId = UnitName(unitToken), UnitGUID(unitToken)
        local _, calling = UnitClass(unitToken)
        if title and unitId and not (Secret(title) or Secret(unitId) or Secret(calling)) then
            items[#items + 1] = { unit = unitToken, name = title, class = calling, guid = unitId }
        end
    end
    return items
end

-- The sender must be the group member whose GUID the message carries.
local function SenderIs(sender, unitId)
    local lacking = Ambiguate(sender, "none")
    for _, m in ipairs(Roster()) do
        if m.guid == unitId then return m.name == lacking or lacking:find("^" .. m.name) ~= nil end
    end
    return false
end

local function Line(catalog)
    local line = lineRoster[catalog]
    if line then return line end
    line = CreateFrame("Frame", nil, gWindow)
    line.name = line:CreateFontString(nil, "OVERLAY")
    line.name:SetPoint("LEFT")
    line.name:SetJustifyH("LEFT")
    line.name:SetWordWrap(false)
    line.bar = CreateFrame("StatusBar", nil, line)
    line.bar:SetPoint("BOTTOMRIGHT")
    line.bar:SetMinMaxValues(0, 1)
    line.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    line.bar:SetStatusBarColor(CUI.Kit.Accent())
    CUI.Kit.Panel(line.bar, 0.85)
    line.text = line.bar:CreateFontString(nil, "OVERLAY")
    line.text:SetPoint("CENTER")
    lineRoster[catalog] = line
    return line
end

local SAMPLE = {
    { name = "Tank", class = "WARRIOR", data = { level = 24, xp = 11000, max = 12200 } },
    { name = "Healer", class = "PRIEST", data = { level = 25, xp = 3100, max = 13100 } },
    { name = "Rogue", class = "ROGUE", level = 23 },
}

local function GRenew()
    if not gWindow then return end
    local items = {}
    if CUI._unlockActive and G.Enabled() then
        items = SAMPLE
    elseif G.Enabled() and IsInGroup() and (G.Get("raid") or not IsInRaid()) then
        for _, m in ipairs(Roster()) do
            if m.unit ~= "player" or G.Get("showSelf") then
                local lvl = UnitLevel(m.unit)
                if Secret(lvl) then lvl = nil end
                local payload = m.unit == "player"
                        and { level = UnitLevel("player"), xp = UnitXP("player"), max = UnitXPMax("player") }
                    or others[m.guid]
                local current = payload and payload.level or lvl
                if not (current and current >= TopLvl()) then
                    items[#items + 1] = { name = m.name, class = m.class, level = lvl, data = payload }
                end
            end
        end
    end
    if #items == 0 then
        gWindow:Hide()
        return
    end
    local dims = G.Get("size")
    local lineH = math.max(18, dims + 6)
    local titleW = 90 * dims / 12
    gWindow:SetSize(G.Get("width"), #items * (lineH + 2) - 2)
    for catalog, m in ipairs(items) do
        local region = Line(catalog)
        region:ClearAllPoints()
        region:SetPoint("TOPLEFT", 0, -(catalog - 1) * (lineH + 2))
        region:SetPoint("TOPRIGHT", 0, -(catalog - 1) * (lineH + 2))
        region:SetHeight(lineH)
        CUI.Kit.Font(region.name, dims, "essentials")
        region.name:SetWidth(titleW - 4)
        CUI.Kit.Font(region.text, dims - 1, "essentials")
        region.bar:SetPoint("TOPLEFT", titleW, 0)
        local tint = m.class and RAID_CLASS_COLORS[m.class]
        region.name:SetText(m.name)
        if tint then
            region.name:SetTextColor(tint.r, tint.g, tint.b)
        else
            region.name:SetTextColor(1, 1, 1)
        end
        local skinInfo = m.data
        if not skinInfo then
            region.bar:SetValue(0)
            region.text:SetText(
                (m.level and m.level > 0 and ("Lv " .. m.level) or "Lv ?") .. "  |cff9ca3afno addon|r"
            )
        elseif skinInfo.level >= TopLvl() or skinInfo.max <= 0 then
            region.bar:SetValue(1)
            region.text:SetText("Lv " .. skinInfo.level .. "  Max")
        else
            local pct = skinInfo.xp / skinInfo.max
            region.bar:SetValue(pct)
            region.text:SetText(("Lv %d  %.1f%%"):format(skinInfo.level, pct * 100))
        end
        region:Show()
    end
    for catalog = #items + 1, #lineRoster do
        lineRoster[catalog]:Hide()
    end
    gWindow:Show()
end

local gEv = CreateFrame("Frame")
gEv:SetScript("OnEvent", function(_, evt, leadLabel, message, medium, sender)
    if evt == "CHAT_MSG_ADDON" then
        if Secret(leadLabel) or Secret(message) or Secret(medium) or Secret(sender) then return end
        if leadLabel ~= LEAD or not GROUP_CHANNELS[medium] then return end
        if message == ASK then
            SendSoon()
            return
        end
        local unitId, lvl, xp, top = message:match(MESSAGE_PATTERN)
        if not unitId or not unitId:find("^Player%-") or unitId == UnitGUID("player") then return end
        lvl, xp, top = tonumber(lvl), tonumber(xp), tonumber(top)
        if lvl > 1000 or xp > TOP_XP or top > TOP_XP or not SenderIs(sender, unitId) then return end
        others[unitId] = { level = lvl, xp = xp, max = top }
        return GRenew()
    elseif evt == "GROUP_ROSTER_UPDATE" or evt == "PLAYER_ENTERING_WORLD" then
        local inGroup = {}
        for _, m in ipairs(Roster()) do
            inGroup[m.guid] = true
        end
        for unitId in pairs(others) do
            if not inGroup[unitId] then others[unitId] = nil end
        end
        SendSoon(evt == "PLAYER_ENTERING_WORLD")
    elseif evt == "PLAYER_XP_UPDATE" or evt == "PLAYER_LEVEL_UP" then
        SendSoon()
    elseif evt == "PLAYER_REGEN_ENABLED" then
        if sendLaterCombat then
            sendLaterCombat = false
            Send()
        end
        return
    end
    GRenew()
end)

local function GUse()
    gEv:UnregisterAllEvents()
    if not G.Enabled() then
        if gWindow then gWindow:Hide() end
        return
    end
    if not gWindow then gWindow = CreateFrame("Frame", "CludesUIGroupXP", UIParent) end
    C_ChatInfo.RegisterAddonMessagePrefix(LEAD)
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
    if not CUI._unlockActive then G.Place(gWindow) end
    SendSoon(true)
    GRenew()
end

G.Start(GUse, {
    key = "CUI_GroupXP",
    label = "Group XP",
    order = 752,
    frame = function(make)
        if make and not gWindow then gWindow = CreateFrame("Frame", "CludesUIGroupXP", UIParent) end
        if make then GRenew() end
        return gWindow
    end,
    size = function() return G.Get("width"), 3 * 20 end,
    noAnchorTarget = true,
    noSizeMatchTarget = true,
})

CUI._XP = {
    ticker = { Get = X.Get, Cfg = X.Cfg, Apply = XUse },
    group = { Get = G.Get, Cfg = G.Cfg, Apply = GUse },
}
