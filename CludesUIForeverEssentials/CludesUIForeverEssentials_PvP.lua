if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if not (CludesUI and CludesUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_PvP.lua  (WoW Forever only)
--  PvP: enemy players around you, Kill on Sight, the last hour, statistics.
--    Nearby       enemy players seen from their nameplates, your target, focus
--                 and mouseover, rescanned every second; an alert sound, a
--                 warning when one goes into stealth or prowl.
--    Kill on Sight  mark an enemy (with reasons); a warning and alarm when
--                 one is seen, and optionally when someone of their guild is.
--    Last Hour    everyone seen in the last hour.
--    Ignore       enemies that never alert.
--    Statistics   every enemy you have met, searchable, with your wins and
--                 losses against them.
--    Sharing      sightings go to your party, raid and guild, and theirs come
--                 back, in Spy's own message format, so Spy users and CludesUI
--                 users see each other's sightings.
--    Extras       announce an enemy to a chat channel (Local Defense too: the
--                 game lets only you post there, so the message is put in your
--                 chat box for Enter); a Kill on Sight button on an enemy
--                 target's frame; level and class of known enemies on the
--                 minimap tracking tooltip.
--    Watch List   players of your OWN faction to remember (a ninja looter):
--                 a warning when one is near you or in your group.
--    Combat Map   every win and loss as a skull on the world map where you
--                 stood (green a win, red a loss).
--    Off Zones    zones (or subzones) to stay off in, by name.
--  WoW Forever gives addons no combat log, so a win is your (or your pet's)
--  killing blow from PARTY_KILL, and a loss is the killer in your death
--  recap, else the only enemy who had you targeted just before you died.
--  The list rows are secure buttons (a click targets the player), so the
--  window cannot change in combat; what changes then shows after the fight.
-------------------------------------------------------------------------------
local _, module = ...

local F = module.Feature("pvp", {
    enabled = false, sound = true, stealthWarn = true, kosWarn = true, kosGuildWarn = true,
    share = true, useShared = true, announceKoS = false, removeAfter = 60, battlegrounds = false,
    autoShow = true, rows = 10, kosButton = true, minimapTip = true,
    watchWarn = true, watchGroupWarn = true, combatMap = true, offZones = "",
}, { point = "TOPLEFT", relPoint = "TOPLEFT", x = 20, y = -220 })
local Get, Enabled = F.Get, F.Enabled

local PREFIX = "[Spy]"
local SPY_VERSION = "1.3.8"
local SCAN = 1
local CAST_DEDUP = 1
local TARGETING_WINDOW = 6
local HOUR = 3600
local PURGE_DAYS = 90
local SKULL = -1
local MAX_LEVEL = 60
local STEALTH = { [1784] = true, [1785] = true, [1786] = true, [1787] = true, [1856] = true, [1857] = true }
local PROWL = { [5215] = true, [6783] = true, [9913] = true }
local WATCHED = { target = true, focus = true, mouseover = true }

-- The CludesUI theme colour, read each time so a theme change follows.
local function Accent() return CludesUI.GetAccentColor() end
local function AccentHex() return CludesUI.HexColor(Accent()) end
local function Say(text) CludesUI.Print(AccentHex() .. "PvP:|r " .. text) end
local function Font() return (CludesUI.GetFontPath and CludesUI.GetFontPath()) or STANDARD_TEXT_FONT end
local function Secret(v) return issecretvalue and issecretvalue(v) end
local function R(v) if v == nil or Secret(v) then return nil end return v end

-------------------------------------------------------------------------------
--  Store (account-wide: Forever names are unique for the region)
-------------------------------------------------------------------------------
local function Store()
    local c = F.Cfg()
    c.players = c.players or {}   -- name -> { class, level, race, guild, faction, guess, first, last, zone, sub, wins, losses }
    c.kos = c.kos or {}           -- name -> time added
    c.reasons = c.reasons or {}   -- name -> { reason = true }
    c.ignore = c.ignore or {}     -- name -> time added
    c.watch = c.watch or {}       -- own-faction name -> { added, reason, class, level, guild, seen, zone }
    c.fights = c.fights or {}     -- { name, result "W"|"L", map, x, y, when }, newest last
    return c
end

local nearby = {}       -- name -> last seen (GetTime), this session
local active = {}       -- name -> last action (GetTime)
local lastHour = {}     -- name -> last seen (time())
local warned = {}       -- name -> GetTime of the last alert, so a pass does not spam
local plates = {}
local targetingMe = {}
local recentCasts = {}
local guidNames = {}
local Refresh           -- the window's repaint

local function Zoned()
    local inside, kind = IsInInstance()
    if inside and (kind == "party" or kind == "raid" or kind == "scenario") then return false end
    if inside and (kind == "pvp" or kind == "arena") and not Get("battlegrounds") then return false end
    local zoneType = C_PvP and C_PvP.GetZonePVPInfo and R(C_PvP.GetZonePVPInfo())
    return zoneType ~= "sanctuary"
end

local function OffZone()
    local list = Get("offZones")
    if type(list) ~= "string" or list == "" then return false end
    local zone, sub = (R(GetZoneText()) or ""):lower(), (R(GetSubZoneText()) or ""):lower()
    for name in list:gmatch("[^,]+") do
        name = name:match("^%s*(.-)%s*$"):lower()
        if name ~= "" and (name == zone or name == sub) then return true end
    end
    return false
end

local function Live() return Enabled() and Zoned() and not OffZone() end

local function PlayerName(unit)
    if not R(UnitExists(unit)) or not R(UnitIsPlayer(unit)) then return nil end
    local name, realm = UnitName(unit)
    if Secret(name) or Secret(realm) or type(name) ~= "string" or name == "" or name == UNKNOWNOBJECT then return nil end
    if type(realm) == "string" and realm ~= "" then name = name .. "-" .. realm end
    return name
end

local function Data(name, create)
    local p = Store().players[name]
    if not p and create then p = { first = time(), wins = 0, losses = 0 }; Store().players[name] = p end
    return p
end

local function Here()
    return R(GetZoneText()) or "", R(GetSubZoneText()) or ""
end

-------------------------------------------------------------------------------
--  Alerts
-------------------------------------------------------------------------------
local alertFrame
local function Warn(text, r, g, b, alarm)
    if not alertFrame then
        alertFrame = CreateFrame("Frame", "CludesUIPvPAlert", UIParent)
        alertFrame:SetSize(400, 40)
        alertFrame:SetPoint("TOP", 0, -170)
        alertFrame.text = alertFrame:CreateFontString(nil, "OVERLAY")
        alertFrame.text:SetFont(Font(), 22, "OUTLINE")
        alertFrame.text:SetPoint("CENTER")
        local ag = alertFrame:CreateAnimationGroup()
        local hold = ag:CreateAnimation("Alpha"); hold:SetFromAlpha(1); hold:SetToAlpha(1); hold:SetDuration(2.5); hold:SetOrder(1)
        local out = ag:CreateAnimation("Alpha"); out:SetFromAlpha(1); out:SetToAlpha(0); out:SetDuration(0.8); out:SetOrder(2)
        ag:SetScript("OnFinished", function() alertFrame:Hide() end)
        alertFrame.ag = ag
    end
    alertFrame.text:SetText(text)
    alertFrame.text:SetTextColor(r, g, b)
    alertFrame.ag:Stop()
    alertFrame:SetAlpha(1)
    alertFrame:Show()
    alertFrame.ag:Play()
    if Get("sound") then PlaySound(alarm and SOUNDKIT.RAID_WARNING or SOUNDKIT.IG_PLAYER_INVITE, "Master") end
end

local function ClassColour(class)
    local c = class and RAID_CLASS_COLORS[class]
    return c and c:GenerateHexColor() or "ffffffff"
end

local function Label(name)
    local p = Data(name)
    return ("|c%s%s|r"):format(ClassColour(p and p.class), name:gsub("%-", " "))
end

-------------------------------------------------------------------------------
--  Sharing (Spy's message format)
-------------------------------------------------------------------------------
local function Share(name)
    if not Get("share") then return end
    local p = Data(name)
    if not p then return end
    local zone, sub = Here()
    local level = (p.level and not p.guess) and p.level or ""
    local msg = table.concat({ SPY_VERSION, name, p.class or "", level, p.race or "", zone, sub, "", "", p.guild or "", "" }, "|")
    if #msg >= 240 then return end
    if IsInRaid() then C_ChatInfo.SendAddonMessage(PREFIX, msg, "RAID")
    elseif IsInGroup() then C_ChatInfo.SendAddonMessage(PREFIX, msg, "PARTY") end
    if IsInGuild() and not IsInInstance() then C_ChatInfo.SendAddonMessage(PREFIX, msg, "GUILD") end
end

-------------------------------------------------------------------------------
--  Detection
-------------------------------------------------------------------------------
local function Detected(name, acted, fromShare)
    local now = GetTime()
    local fresh = not nearby[name]
    nearby[name] = now
    if acted then active[name] = now end
    lastHour[name] = time()
    local p = Data(name, true)
    p.last = time()
    p.zone, p.sub = Here()
    if Store().ignore[name] then return end
    if fresh and (not warned[name] or now - warned[name] > Get("removeAfter")) then
        warned[name] = now
        local kos = Store().kos[name]
        if kos and Get("kosWarn") then
            Warn("Kill on Sight: " .. Label(name), 1, 0.35, 0.35, true)
            if Get("announceKoS") and IsInGroup() then
                SendChatMessage(("Kill on Sight nearby: %s%s"):format(name:gsub("%-", " "), p.level and (" (" .. p.level .. ")") or ""), IsInRaid() and "RAID" or "PARTY")
            end
        elseif Get("kosGuildWarn") and p.guild then
            for k in pairs(Store().kos) do
                local other = Data(k)
                if other and other.guild == p.guild and k ~= name then
                    Warn(("%s of <%s> (a Kill on Sight guild)"):format(Label(name), p.guild), 1, 0.6, 0.2, false)
                    break
                end
            end
        elseif Get("sound") then
            PlaySound(SOUNDKIT.IG_PLAYER_INVITE, "Master")
        end
        -- A sighting someone else sent is not sent on again (no echo between users).
        if not fromShare then Share(name) end
        if Get("autoShow") and module.ShowPvP then module.ShowPvP(true) end
    end
    if Refresh then Refresh() end
end

local function ScanUnit(unit)
    local name = PlayerName(unit)
    if not name then return nil end
    local guid = R(UnitGUID(unit))
    if type(guid) == "string" then guidNames[guid] = name end
    local enemy = R(UnitIsEnemy("player", unit))
    if enemy == false and module.PvPWatchSeen then module.PvPWatchSeen(name, unit) end
    if not enemy then return nil end
    local p = Data(name, true)
    p.class = R((select(2, UnitClass(unit)))) or p.class
    p.race = R((UnitRace(unit))) or p.race
    p.guild = R((GetGuildInfo(unit))) or p.guild
    p.faction = R((UnitFactionGroup(unit))) or p.faction
    local level = tonumber(R(UnitLevel(unit)))
    if level == SKULL then
        if not p.level or p.guess then p.level, p.guess = math.min(UnitLevel("player") + 10, MAX_LEVEL), true end
    elseif level then
        p.level, p.guess = level, false
    end
    if Store().ignore[name] then return nil end
    Detected(name, false)
    return name
end

local function NoteTargetingMe(unit, name)
    local ok, same = pcall(UnitIsUnit, unit .. "target", "player")
    if ok and R(same) then targetingMe[name] = GetTime() end
end

local function Tick()
    if not Live() then return end
    for unit in pairs(plates) do
        if R(UnitExists(unit)) then
            local name = ScanUnit(unit)
            if name then NoteTargetingMe(unit, name) end
        else
            plates[unit] = nil
        end
    end
    for _, unit in ipairs({ "target", "focus" }) do
        local name = ScanUnit(unit)
        if name then NoteTargetingMe(unit, name) end
    end
    local now = GetTime()
    local changed
    for name, seen in pairs(nearby) do
        if now - seen > Get("removeAfter") then nearby[name], active[name] = nil, nil; changed = true end
    end
    for name, when in pairs(targetingMe) do if now - when > 60 then targetingMe[name] = nil end end
    for key, when in pairs(recentCasts) do if now - when > CAST_DEDUP then recentCasts[key] = nil end end
    local cutoff = time() - HOUR
    for name, when in pairs(lastHour) do if when < cutoff then lastHour[name] = nil; changed = true end end
    if changed and Refresh then Refresh() end
end

local function OnCast(unit, spellID)
    if not (type(unit) == "string" and (WATCHED[unit] or unit:find("^nameplate%d+$"))) then return end
    local name = ScanUnit(unit)
    spellID = R(spellID)
    if not name or type(spellID) ~= "number" then return end
    local key = name .. ":" .. spellID
    if recentCasts[key] and GetTime() - recentCasts[key] < CAST_DEDUP then return end
    recentCasts[key] = GetTime()
    active[name] = GetTime()
    NoteTargetingMe(unit, name)
    if Get("stealthWarn") and not Store().ignore[name] then
        if STEALTH[spellID] then Warn(Label(name) .. " went into Stealth!", 1, 0.85, 0.2, true)
        elseif PROWL[spellID] then Warn(Label(name) .. " started Prowling!", 1, 0.85, 0.2, true) end
    end
end

local function NameFromGUID(guid)
    guid = R(guid)
    if type(guid) ~= "string" or not guid:find("^Player%-") then return nil end
    if guidNames[guid] then return guidNames[guid] end
    local ok, _, _, _, _, _, name, realm = pcall(GetPlayerInfoByGUID, guid)
    if not ok or Secret(name) or Secret(realm) or type(name) ~= "string" or name == "" then return nil end
    if type(realm) == "string" and realm ~= "" then name = name .. "-" .. realm end
    return Store().players[name] and name or nil
end

local function IsMine(guid)
    return guid == R(UnitGUID("player")) or guid == R(UnitGUID("pet"))
end

local function OnPartyKill(attacker, victim)
    attacker = R(attacker)
    if not attacker or not IsMine(attacker) then return end
    local name = NameFromGUID(victim)
    local p = name and Data(name)
    if p then
        p.wins = (p.wins or 0) + 1
        if module.PvPRecordFight then module.PvPRecordFight(name, "W") end
        Say(("you killed %s (%d win%s, %d loss%s)."):format(Label(name), p.wins, p.wins == 1 and "" or "s",
            p.losses or 0, (p.losses or 0) == 1 and "" or "es"))
        if Refresh then Refresh() end
    end
end

local lastRecap
local function KillerFromRecap()
    if not (C_DeathRecap and C_DeathRecap.GetRecapEvents) then return nil, true end
    local okLink, link = pcall(C_DeathRecap.GetRecapLink)
    local id = okLink and R(link) and tonumber(tostring(link):match("death:(%d+)"))
    if id and id == lastRecap then return nil, true end
    lastRecap = id
    local ok, events = pcall(C_DeathRecap.GetRecapEvents)
    if not ok or type(events) ~= "table" or (issecrettable and issecrettable(events)) then return nil, true end
    local e = events[1]
    if type(e) ~= "table" or (issecrettable and issecrettable(e)) then return nil, true end
    if R(e.hideCaster) then return nil, true end
    local name = NameFromGUID(e.sourceGUID)
    return name, false
end

local function OnDeath()
    -- Where we fell, read now: the recap comes later, maybe after a release.
    local where = module.PvPPosition and module.PvPPosition()
    local suspects, now = {}, GetTime()
    for name, when in pairs(targetingMe) do if now - when <= TARGETING_WINDOW then suspects[#suspects + 1] = name end end
    C_Timer.After(0.5, function()
        local killer, unknown = KillerFromRecap()
        if not killer and unknown and #suspects == 1 then killer = suspects[1] end
        local p = killer and Data(killer)
        if p then
            p.losses = (p.losses or 0) + 1
            if module.PvPRecordFight then module.PvPRecordFight(killer, "L", where) end
            Say(("%s killed you (%d win%s, %d loss%s)."):format(Label(killer), p.wins or 0, (p.wins or 0) == 1 and "" or "s",
                p.losses, p.losses == 1 and "" or "es"))
            if Refresh then Refresh() end
        end
    end)
end

local function OnShared(msg, sender)
    if not Get("useShared") or not Live() then return end
    if type(msg) ~= "string" or Secret(msg) or Secret(sender) then return end
    local me = UnitName("player")
    if Ambiguate(sender, "none") == me then return end
    local _, name, class, level, race, zone, _, _, _, guild = strsplit("|", msg)
    if not name or name == "" or #name > 40 then return end
    if zone ~= (R(GetZoneText()) or "") then return end
    if class ~= "" and not RAID_CLASS_COLORS[class] then return end
    level = tonumber(level)
    if level and (level < 1 or level > MAX_LEVEL or level ~= math.floor(level)) then level = nil end
    local p = Data(name, true)
    if class ~= "" then p.class = class end
    if level then p.level, p.guess = level, false end
    if race and race ~= "" then p.race = race end
    if guild and guild ~= "" then p.guild = guild end
    if not Store().ignore[name] then Detected(name, false, true) end
end

-------------------------------------------------------------------------------
--  Lists
-------------------------------------------------------------------------------
function module.PvPToggleKoS(name, on)
    local s = Store()
    if on == nil then on = not s.kos[name] end
    s.kos[name] = on and time() or nil
    if on then s.ignore[name] = nil; Data(name, true) end
    Say(("%s %s Kill on Sight."):format(Label(name), on and "added to" or "removed from"))
    if Refresh then Refresh() end
end

function module.PvPToggleIgnore(name, on)
    local s = Store()
    if on == nil then on = not s.ignore[name] end
    s.ignore[name] = on and time() or nil
    if on then s.kos[name] = nil; nearby[name] = nil end
    if Refresh then Refresh() end
end

local function Announce(name, channel)
    local p = Data(name) or {}
    local zone, sub = Here()
    local text = ("Enemy: %s%s%s%s at %s%s"):format(name:gsub("%-", " "),
        p.level and (" " .. (p.guess and "~" or "") .. p.level) or "",
        p.class and (" " .. (LOCALIZED_CLASS_NAMES_MALE[p.class] or p.class)) or "",
        p.guild and (" <" .. p.guild .. ">") or "", zone, sub ~= "" and (", " .. sub) or "")
    if channel == "SELF" then return Say(text) end
    if channel == "LOCALDEFENSE" then
        -- The game refuses an addon post in a public channel: the message goes in
        -- the chat box, and your Enter sends it.
        local id
        local list = { GetChannelList() }
        for i = 1, #list, 3 do
            local cid, cname = R(list[i]), R(list[i + 1])
            local lower = type(cname) == "string" and cname:lower() or ""
            if type(cid) == "number" and (lower:find("^localdefense") or lower:find("^local defense")) then
                id = cid
                break
            end
        end
        if not id then return Say("you are not in the Local Defense channel.") end
        local open = (ChatFrameUtil and ChatFrameUtil.OpenChat) or ChatFrame_OpenChat
        if open then pcall(open, "/" .. id .. " " .. text) end
        return
    end
    SendChatMessage(text, channel)
end

-- Purge: forgotten enemies older than 90 days, unless Kill on Sight or with wins or losses.
local function Purge()
    local cutoff = time() - PURGE_DAYS * 86400
    local s = Store()
    for name, p in pairs(s.players) do
        if (p.last or 0) < cutoff and not s.kos[name] and (p.wins or 0) == 0 and (p.losses or 0) == 0 then
            s.players[name] = nil
        end
    end
end

-------------------------------------------------------------------------------
--  Window
-------------------------------------------------------------------------------
local TABS = { "Nearby", "Last Hour", "Kill on Sight", "Ignore" }
local ROW_H, W = 18, 250
local win, rows, tab = nil, {}, 1
local dirtyInCombat

local function TargetMacro(name)
    local first, second = name:match("^([^%-]+)%-(.+)$")
    if not first then return "/targetexact " .. name end
    return table.concat({ "/cleartarget", "/targetexact " .. first .. " " .. second,
        "/targetexact [noexists] " .. name, "/targetexact [noexists] " .. first,
        "/target [noexists] " .. first .. " " .. second }, "\n")
end

local function RowMenu(owner, name)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(name:gsub("%-", " "))
        local s = Store()
        root:CreateButton(s.kos[name] and "Remove Kill on Sight" or "Kill on Sight", function() module.PvPToggleKoS(name) end)
        root:CreateButton(s.ignore[name] and "Stop Ignoring" or "Ignore", function() module.PvPToggleIgnore(name) end)
        if s.kos[name] then
            local reasons = root:CreateButton("Kill on Sight Reasons")
            for _, r in ipairs({ "Ganked me", "Camped me", "Killed a low level", "Griefed a quest", "Ninja looted" }) do
                reasons:CreateCheckbox(r, function() return s.reasons[name] and s.reasons[name][r] end,
                    function() s.reasons[name] = s.reasons[name] or {}; s.reasons[name][r] = not s.reasons[name][r] or nil end)
            end
        end
        local ann = root:CreateButton("Announce")
        for _, c in ipairs({ { "Say", "SAY" }, { "Party", "PARTY" }, { "Raid", "RAID" }, { "Guild", "GUILD" }, { "Local Defense", "LOCALDEFENSE" }, { "Yourself", "SELF" } }) do
            ann:CreateButton(c[1], function() Announce(name, c[2]) end)
        end
        root:CreateButton("Remove from List", function() nearby[name], lastHour[name] = nil, nil; if Refresh then Refresh() end end)
    end)
end

local function Row(i)
    local r = rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, win, "SecureActionButtonTemplate")
    r:SetSize(W - 12, ROW_H)
    r:RegisterForClicks("AnyUp")
    r:SetAttribute("type1", "macro")
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.text = r:CreateFontString(nil, "OVERLAY")
    r.text:SetFont(Font(), 12, "")
    r.text:SetPoint("LEFT", 4, 0)
    r.text:SetWidth(W - 60)
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(false)
    r.right = r:CreateFontString(nil, "OVERLAY")
    r.right:SetFont(Font(), 11, "")
    r.right:SetPoint("RIGHT", -4, 0)
    r:SetScript("PostClick", function(self, button)
        if not self.player then return end
        if button == "RightButton" then RowMenu(self, self.player)
        elseif IsControlKeyDown() then module.PvPToggleIgnore(self.player)
        elseif IsShiftKeyDown() then module.PvPToggleKoS(self.player) end
    end)
    r:SetScript("OnEnter", function(self)
        local p = self.player and Data(self.player)
        if not p then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(Label(self.player))
        local facts = {}
        if p.level then facts[#facts + 1] = "Level " .. (p.guess and "~" or "") .. p.level end
        if p.race then facts[#facts + 1] = p.race end
        if p.class then facts[#facts + 1] = LOCALIZED_CLASS_NAMES_MALE[p.class] or p.class end
        if #facts > 0 then GameTooltip:AddLine(table.concat(facts, " "), 1, 1, 1) end
        if p.guild then GameTooltip:AddLine("<" .. p.guild .. ">", 0.6, 0.8, 1) end
        if p.zone and p.zone ~= "" then GameTooltip:AddLine("Last seen: " .. p.zone .. (p.sub ~= "" and (", " .. p.sub) or ""), 0.7, 0.7, 0.7) end
        GameTooltip:AddLine(("Wins %d   Losses %d"):format(p.wins or 0, p.losses or 0), 0.4, 0.9, 0.5)
        local reasons = Store().reasons[self.player]
        if reasons and next(reasons) then
            local list = {}
            for k in pairs(reasons) do list[#list + 1] = k end
            GameTooltip:AddLine("Reasons: " .. table.concat(list, ", "), 1, 0.5, 0.5, true)
        end
        GameTooltip:AddLine("Click: target   Shift: Kill on Sight   Ctrl: ignore   Right: menu", 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rows[i] = r
    return r
end

local function Entries()
    local list, s, now = {}, Store(), GetTime()
    if tab == 1 then
        for name, seen in pairs(nearby) do
            if not s.ignore[name] then
                list[#list + 1] = { name = name, kos = s.kos[name] and 1 or 0, act = (active[name] and now - active[name] < 10) and 1 or 0, at = seen }
            end
        end
        table.sort(list, function(a, b)
            if a.kos ~= b.kos then return a.kos > b.kos end
            if a.act ~= b.act then return a.act > b.act end
            return a.at > b.at
        end)
    else
        local src = tab == 2 and lastHour or (tab == 3 and s.kos or s.ignore)
        for name, at in pairs(src) do list[#list + 1] = { name = name, at = at } end
        table.sort(list, function(a, b) return a.at > b.at end)
    end
    return list
end

local function Ago(seconds)
    seconds = math.max(0, math.floor(seconds))
    if seconds < 60 then return seconds .. "s" end
    if seconds < HOUR then return math.floor(seconds / 60) .. "m" end
    if seconds < 86400 then return math.floor(seconds / HOUR) .. "h" end
    return math.floor(seconds / 86400) .. "d"
end

Refresh = function()
    if not (win and win:IsShown()) then return end
    if InCombatLockdown() then dirtyInCombat = true; return end
    dirtyInCombat = false
    win.title:SetText(AccentHex() .. TABS[tab] .. "|r")
    local ar, ag, ab = Accent()
    win:SetBackdropBorderColor(ar, ag, ab, 0.8)
    local list = Entries()
    local n = math.min(#list, Get("rows"))
    local s = Store()
    for i = 1, n do
        local e = list[i]
        local r = Row(i)
        r.player = e.name
        r:SetAttribute("macrotext1", TargetMacro(e.name))
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", win, "TOPLEFT", 6, -26 - (i - 1) * ROW_H)
        local p = Data(e.name) or {}
        r.text:SetText(Label(e.name) .. (p.level and ("  |cff9aa6b2" .. (p.guess and "~" or "") .. p.level .. "|r") or ""))
        local when = tab == 1 and (GetTime() - e.at) or (time() - e.at)
        r.right:SetText("|cff9aa6b2" .. Ago(when) .. "|r")
        if s.kos[e.name] then r.bg:SetColorTexture(1, 0.35, 0.35, 0.22)
        elseif tab == 1 and e.act == 1 then r.bg:SetColorTexture(ar, ag, ab, 0.22)
        else r.bg:SetColorTexture(1, 1, 1, 0.03) end
        r:Show()
    end
    for i = n + 1, #rows do rows[i]:Hide(); rows[i].player = nil end
    win:SetHeight(32 + math.max(n, 1) * ROW_H)
end

local function Build()
    if win then return win end
    win = CreateFrame("Frame", "CludesUIPvP", UIParent, "BackdropTemplate")
    win:SetSize(W, 50)
    win:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    win:SetBackdropColor(0.06, 0.07, 0.09, 0.9)
    win:SetBackdropBorderColor(0, 0, 0, 1)
    win:SetMovable(true); win:EnableMouse(true); win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        F.Cfg().pos = { point = point, relPoint = relPoint, x = x, y = y }
    end)
    win:SetClampedToScreen(true)
    win.title = win:CreateFontString(nil, "OVERLAY")
    win.title:SetFont(Font(), 13, "OUTLINE")
    win.title:SetPoint("TOPLEFT", 8, -6)
    local function Btn(text, x, fn, tip)
        local b = CreateFrame("Button", nil, win)
        b:SetSize(18, 18)
        b:SetPoint("TOPRIGHT", x, -3)
        b.t = b:CreateFontString(nil, "OVERLAY")
        b.t:SetFont(Font(), 13, "OUTLINE")
        b.t:SetPoint("CENTER")
        b.t:SetText(text)
        b:SetScript("OnClick", fn)
        b.t:SetTextColor(0.8, 0.8, 0.8)
        b:SetScript("OnEnter", function(self)
            self.t:SetTextColor(Accent())
            GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(tip); GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function(self) self.t:SetTextColor(0.8, 0.8, 0.8); GameTooltip:Hide() end)
    end
    Btn("x", -2, function() if not InCombatLockdown() then win:Hide() end end, "Close (it opens again when an enemy is seen)")
    Btn(">", -22, function() tab = tab % #TABS + 1; Refresh() end, "Next list")
    Btn("<", -42, function() tab = (tab - 2) % #TABS + 1; Refresh() end, "Previous list")
    Btn("c", -62, function() wipe(nearby); wipe(active); Refresh() end, "Clear the Nearby list")
    Btn("s", -82, function() module.ShowPvPStats() end, "Statistics")
    win:Hide()
    F.Place(win)
    return win
end

--- Shows the window (on the Nearby list when auto is true). Not in combat.
function module.ShowPvP(auto)
    if InCombatLockdown() then return end
    Build()
    if auto then
        if win:IsShown() and tab == 1 then return end
        tab = 1
    end
    win:Show()
    Refresh()
end

-------------------------------------------------------------------------------
--  Statistics window
-------------------------------------------------------------------------------
local stats, statRows, statScroll, statContent, statSearch = nil, {}, nil, nil, nil
local function StatsRefresh()
    if not (stats and stats:IsShown()) then return end
    local filter = (statSearch:GetText() or ""):lower()
    local list, s = {}, Store()
    for name, p in pairs(s.players) do
        if filter == "" or name:lower():find(filter, 1, true) or (p.guild and p.guild:lower():find(filter, 1, true)) then
            list[#list + 1] = { name = name, p = p }
        end
    end
    table.sort(list, function(a, b) return (a.p.last or 0) > (b.p.last or 0) end)
    for i, e in ipairs(list) do
        local r = statRows[i]
        if not r then
            r = statContent:CreateFontString(nil, "OVERLAY")
            r:SetFont(Font(), 12, "")
            r:SetJustifyH("LEFT")
            r:SetWidth(440)
            r:SetWordWrap(false)
            statRows[i] = r
        end
        local p = e.p
        r:SetPoint("TOPLEFT", 0, -(i - 1) * 16)
        r:SetText(("%s%s  |cff9aa6b2%s%s|r  |cff60d080W %d|r |cffff6060L %d|r  |cff9aa6b2%s ago|r"):format(
            s.kos[e.name] and "|cffff5959KoS|r " or "", Label(e.name),
            p.level and ((p.guess and "~" or "") .. p.level .. " ") or "", p.guild and ("<" .. p.guild .. ">") or "",
            p.wins or 0, p.losses or 0, Ago(time() - (p.last or time()))))
        r:Show()
    end
    for i = #list + 1, #statRows do statRows[i]:Hide() end
    statContent:SetHeight(math.max(1, #list) * 16)
    stats.count:SetText(#list .. " enemies")
end

function module.ShowPvPStats()
    if not stats then
        stats = CreateFrame("Frame", "CludesUIPvPStats", UIParent, "BackdropTemplate")
        stats:SetSize(480, 420)
        stats:SetPoint("CENTER")
        stats:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        stats:SetBackdropColor(0.06, 0.07, 0.09, 0.95)
        stats:SetBackdropBorderColor(Accent())
        stats:SetMovable(true); stats:EnableMouse(true); stats:RegisterForDrag("LeftButton")
        stats:SetScript("OnDragStart", stats.StartMoving)
        stats:SetScript("OnDragStop", stats.StopMovingOrSizing)
        stats:SetFrameStrata("HIGH")
        local t = stats:CreateFontString(nil, "OVERLAY")
        t:SetFont(Font(), 15, "OUTLINE")
        t:SetPoint("TOPLEFT", 10, -8)
        t:SetText("PvP Statistics")
        stats.title = t
        stats.count = stats:CreateFontString(nil, "OVERLAY")
        stats.count:SetFont(Font(), 11, "")
        stats.count:SetPoint("LEFT", t, "RIGHT", 10, 0)
        local close = CreateFrame("Button", nil, stats)
        close:SetSize(20, 20)
        close:SetPoint("TOPRIGHT", -4, -4)
        close.t = close:CreateFontString(nil, "OVERLAY")
        close.t:SetFont(Font(), 14, "OUTLINE")
        close.t:SetPoint("CENTER")
        close.t:SetText("x")
        close.t:SetTextColor(0.8, 0.8, 0.8)
        close:SetScript("OnClick", function() stats:Hide() end)
        close:SetScript("OnEnter", function(self) self.t:SetTextColor(Accent()) end)
        close:SetScript("OnLeave", function(self) self.t:SetTextColor(0.8, 0.8, 0.8) end)
        statSearch = CreateFrame("EditBox", nil, stats, "InputBoxTemplate")
        statSearch:SetSize(200, 20)
        statSearch:SetPoint("TOPLEFT", 14, -30)
        statSearch:SetAutoFocus(false)
        statSearch:SetScript("OnTextChanged", StatsRefresh)
        local hint = stats:CreateFontString(nil, "OVERLAY")
        hint:SetFont(Font(), 11, "")
        hint:SetPoint("LEFT", statSearch, "RIGHT", 8, 0)
        hint:SetText("|cff9aa6b2search a name or guild|r")
        statScroll = CreateFrame("ScrollFrame", nil, stats, "UIPanelScrollFrameTemplate")
        statScroll:SetPoint("TOPLEFT", 10, -58)
        statScroll:SetPoint("BOTTOMRIGHT", -30, 10)
        statContent = CreateFrame("Frame", nil, statScroll)
        statContent:SetSize(440, 10)
        statScroll:SetScrollChild(statContent)
        tinsert(UISpecialFrames, "CludesUIPvPStats")
    end
    stats.title:SetTextColor(Accent())
    local ar, ag, ab = Accent()
    stats:SetBackdropBorderColor(ar, ag, ab, 0.8)
    stats:Show()
    StatsRefresh()
end

-------------------------------------------------------------------------------
--  Kill on Sight button on the target frame
-------------------------------------------------------------------------------
local kosButton
local function KoSButtonUpdate()
    if not kosButton then return end
    local name = Get("kosButton") and Enabled() and PlayerName("target")
    if name and R(UnitIsEnemy("player", "target")) then
        kosButton.player = name
        kosButton.t:SetText(Store().kos[name] and "|cffff5959KoS|r" or (AccentHex() .. "KoS|r"))
        kosButton:Show()
    else
        kosButton:Hide()
    end
end
local function BuildKoSButton()
    if kosButton then return end
    local parent = TargetFrame or UIParent
    kosButton = CreateFrame("Button", "CludesUIPvPKoSButton", parent)
    kosButton:SetSize(34, 16)
    kosButton:SetPoint("BOTTOMRIGHT", parent, "TOPRIGHT", -20, -6)
    kosButton.t = kosButton:CreateFontString(nil, "OVERLAY")
    kosButton.t:SetFont(Font(), 12, "OUTLINE")
    kosButton.t:SetPoint("CENTER")
    kosButton:RegisterForClicks("AnyUp")
    kosButton:SetScript("OnClick", function(self, button)
        if not self.player then return end
        if button == "RightButton" then RowMenu(self, self.player) else module.PvPToggleKoS(self.player) end
        KoSButtonUpdate()
    end)
    kosButton:Hide()
end

-------------------------------------------------------------------------------
--  Minimap tracking tooltip
-------------------------------------------------------------------------------
local lastTip
local function DecorateMinimapTip()
    if not (Enabled() and Get("minimapTip")) or GameTooltip:GetOwner() ~= Minimap then return end
    local fs = GameTooltipTextLeft1
    local text = fs and fs:GetText()
    if not text or Secret(text) or text == lastTip then return end
    local out, changed = {}, false
    for line in text:gmatch("[^\n]+") do
        local plain = line:gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):match("^%s*(.-)%s*$")
        local key = plain:gsub(" ", "-")
        local p = Store().players[key] or Store().players[plain]
        if p and p.class then
            line = line .. ("|r |c%s[%s%s]|r"):format(ClassColour(p.class), p.level and (p.level .. " ") or "",
                LOCALIZED_CLASS_NAMES_MALE[p.class] or p.class)
            changed = true
            if Live() and not Store().ignore[Store().players[key] and key or plain] then Detected(Store().players[key] and key or plain, false) end
        end
        out[#out + 1] = line
    end
    if changed then
        lastTip = table.concat(out, "\n")
        fs:SetText(lastTip)
        GameTooltip:Show()
    end
end

-------------------------------------------------------------------------------
--  Watch list (own faction)
-------------------------------------------------------------------------------
local WATCH_COOLDOWN = 300
local watchAlerted, watchInGroup = {}, {}

local function WatchRemember(entry, unit)
    if unit then
        entry.class = R((select(2, UnitClass(unit)))) or entry.class
        local level = tonumber(R(UnitLevel(unit)))
        if level and level > 0 then entry.level = level end
        entry.guild = R((GetGuildInfo(unit))) or entry.guild
    end
    entry.seen = time()
    local zone, sub = Here()
    entry.zone = (sub ~= "" and sub ~= zone) and (sub .. ", " .. zone) or zone
end

local function WatchAlert(name, how)
    local e = Store().watch[name]
    if not e then return end
    local text = (how == "group" and "Watched player in your group: " or "Watched player nearby: ") .. (name:gsub("%-", " "))
        .. (e.reason and (" (" .. e.reason .. ")") or "")
    Say(text)
    Warn(text, 1, 0.75, 0.2, true)
end

function module.PvPWatchSeen(name, unit)
    local e = Store().watch[name]
    if not e then return end
    WatchRemember(e, unit)
    if not Get("watchWarn") then return end
    if watchAlerted[name] and GetTime() - watchAlerted[name] < WATCH_COOLDOWN then return end
    watchAlerted[name] = GetTime()
    WatchAlert(name, "nearby")
end

local function CheckWatchedGroup()
    local present = {}
    local count = GetNumGroupMembers() or 0
    if count > 0 then
        local raid = IsInRaid()
        for i = 1, raid and count or math.min(count, 4) do
            local unit = (raid and "raid" or "party") .. i
            local name = PlayerName(unit)
            if name and Store().watch[name] then present[name] = unit end
        end
    end
    for name, unit in pairs(present) do
        if not watchInGroup[name] then
            WatchRemember(Store().watch[name], unit)
            watchAlerted[name] = GetTime()
            if Enabled() and Get("watchGroupWarn") then WatchAlert(name, "group") end
        end
    end
    watchInGroup = present
end

function module.PvPToggleWatch(name, reason)
    local w = Store().watch
    if w[name] then
        w[name] = nil
        Say((name:gsub("%-", " ")) .. " removed from your watch list.")
    else
        w[name] = { added = time(), reason = reason }
        Say((name:gsub("%-", " ")) .. " added to your watch list" .. (reason and (" (" .. reason .. ")") or "") .. ".")
        CheckWatchedGroup()
    end
end

-- Kill on Sight and Watch on the game's own player menus (target, party, raid, chat names).
local menusAdded
local function AddMenus()
    if menusAdded or not (Menu and Menu.ModifyMenu) then return end
    menusAdded = true
    local function Entries(_, root, ctx)
        if not Enabled() or type(ctx) ~= "table" then return end
        local name, enemy
        local unit = R(ctx.unit)
        if type(unit) == "string" then
            if R(UnitIsUnit(unit, "player")) then return end
            name, enemy = PlayerName(unit), R(UnitIsEnemy("player", unit))
        else
            name = R(ctx.name)
            if type(name) ~= "string" or name == "" or name == UnitName("player") then return end
            local server = R(ctx.server)
            if not name:find("-", 1, true) and type(server) == "string" and server ~= "" then name = name .. "-" .. server end
            local p = Store().players[name]
            enemy = p and p.faction and p.faction ~= UnitFactionGroup("player")
        end
        if not name then return end
        root:CreateDivider()
        root:CreateTitle("CludesUI PvP")
        if enemy then
            root:CreateButton(Store().kos[name] and "Remove Kill on Sight" or "Kill on Sight", function() module.PvPToggleKoS(name) end)
        else
            root:CreateButton(Store().watch[name] and "Stop Watching" or "Watch This Player", function() module.PvPToggleWatch(name) end)
        end
    end
    for _, which in ipairs({ "PLAYER", "TARGET", "FOCUS", "PARTY", "RAID_PLAYER", "RAID", "FRIEND", "ENEMY_PLAYER",
                             "CHAT_ROSTER", "COMMUNITIES_GUILD_MEMBER", "COMMUNITIES_WOW_MEMBER", "GUILD" }) do
        pcall(Menu.ModifyMenu, "MENU_UNIT_" .. which, function(owner, root, ctx) pcall(Entries, owner, root, ctx) end)
    end
end

-------------------------------------------------------------------------------
--  Combat map
-------------------------------------------------------------------------------
local FIGHT_LIMIT = 500
local SKULL_TEX = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"

function module.PvPPosition()
    local mapID = R(C_Map.GetBestMapForUnit("player"))
    if type(mapID) ~= "number" then return nil end
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos or Secret(pos) then return nil end
    local x, y = pos:GetXY()
    if not (R(x) and R(y)) then return nil end
    return { map = mapID, x = x, y = y }
end

local mapLayer, mapProvider, mapPins, mapAdded = nil, nil, {}, false
local function DrawFights()
    if not mapLayer then return end
    for _, pin in ipairs(mapPins) do pin:Hide() end
    if not (Enabled() and Get("combatMap")) then return end
    local mapID = WorldMapFrame:GetMapID()
    local w, h = mapLayer:GetWidth(), mapLayer:GetHeight()
    local scale = 1 / math.max(WorldMapFrame:GetCanvasScale() or 1, 0.1)
    local n = 0
    for _, f in ipairs(Store().fights) do
        if f.map == mapID then
            n = n + 1
            local pin = mapPins[n]
            if not pin then
                pin = CreateFrame("Frame", nil, mapLayer)
                pin.tex = pin:CreateTexture(nil, "OVERLAY")
                pin.tex:SetAllPoints()
                pin.tex:SetTexture(SKULL_TEX)
                pin:SetScript("OnEnter", function(self)
                    local fight = self.fight
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:AddLine((fight.result == "W" and "|cff60ff60Win|r against " or "|cffff6060Loss|r to ") .. Label(fight.name))
                    GameTooltip:AddLine(date("%d %b %Y %H:%M", fight.when), 0.7, 0.7, 0.7)
                    GameTooltip:Show()
                end)
                pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
                mapPins[n] = pin
            end
            pin.fight = f
            pin:SetSize(16 * scale, 16 * scale)
            if f.result == "W" then pin.tex:SetVertexColor(0.3, 1, 0.3) else pin.tex:SetVertexColor(1, 0.3, 0.3) end
            pin:ClearAllPoints()
            pin:SetPoint("CENTER", mapLayer, "TOPLEFT", f.x * w, -f.y * h)
            pin:Show()
        end
    end
end

local function MapApply()
    local want = Enabled() and Get("combatMap")
    if not want then
        if mapAdded then WorldMapFrame:RemoveDataProvider(mapProvider); mapAdded = false end
        for _, pin in ipairs(mapPins) do pin:Hide() end
        return
    end
    if not (WorldMapFrame and C_AddOns.IsAddOnLoaded("Blizzard_WorldMap")) then return end
    if not mapProvider then
        mapLayer = CreateFrame("Frame", nil, WorldMapFrame.ScrollContainer.Child)
        mapLayer:SetAllPoints()
        mapLayer:SetFrameLevel(WorldMapFrame:GetPinFrameLevelsManager():GetValidFrameLevel("PIN_FRAME_LEVEL_MAP_LINK"))
        mapProvider = CreateFromMixins(MapCanvasDataProviderMixin)
        mapProvider.OnMapChanged = DrawFights
        mapProvider.RefreshAllData = DrawFights
        mapProvider.RemoveAllData = function() for _, pin in ipairs(mapPins) do pin:Hide() end end
        mapProvider.OnCanvasScaleChanged = DrawFights
    end
    if not mapAdded then WorldMapFrame:AddDataProvider(mapProvider); mapAdded = true end
end

function module.PvPRecordFight(name, result, where)
    where = where or module.PvPPosition()
    if not where then return end
    local list = Store().fights
    list[#list + 1] = { name = name, result = result, map = where.map, x = where.x, y = where.y, when = time() }
    while #list > FIGHT_LIMIT do table.remove(list, 1) end
end

-------------------------------------------------------------------------------
--  Events
-------------------------------------------------------------------------------
local ev = CreateFrame("Frame")
local ticker
ev:SetScript("OnEvent", function(_, event, a1, a2, a3, a4)
    if event == "CHAT_MSG_ADDON" then
        if a1 == PREFIX then OnShared(a2, a4) end
        return
    end
    if event == "PLAYER_TARGET_CHANGED" then KoSButtonUpdate() end
    if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then CheckWatchedGroup() end
    if event == "ADDON_LOADED" then
        if a1 == "Blizzard_WorldMap" then MapApply() end
        return
    end
    if not Live() then
        if event == "PLAYER_REGEN_ENABLED" and dirtyInCombat then Refresh() end
        return
    end
    if event == "NAME_PLATE_UNIT_ADDED" then plates[a1] = true; ScanUnit(a1)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then plates[a1] = nil
    elseif event == "PLAYER_TARGET_CHANGED" then ScanUnit("target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then ScanUnit("mouseover")
    elseif event == "PLAYER_FOCUS_CHANGED" then ScanUnit("focus")
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then OnCast(a1, a3)
    elseif event == "PARTY_KILL" then OnPartyKill(a1, a2)
    elseif event == "PLAYER_DEAD" then OnDeath()
    elseif event == "PLAYER_REGEN_ENABLED" then if dirtyInCombat then Refresh() end
    end
end)

local EVENTS = { "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT",
    "PLAYER_FOCUS_CHANGED", "UNIT_SPELLCAST_SUCCEEDED", "PARTY_KILL", "PLAYER_DEAD", "PLAYER_REGEN_ENABLED",
    "CHAT_MSG_ADDON", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "ADDON_LOADED" }

local tipHooked
local function Apply()
    if Enabled() then
        for _, e in ipairs(EVENTS) do pcall(ev.RegisterEvent, ev, e) end
        C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
        if not ticker then ticker = C_Timer.NewTicker(SCAN, Tick) end
        BuildKoSButton()
        if not tipHooked then
            tipHooked = true
            GameTooltip:HookScript("OnShow", DecorateMinimapTip)
            GameTooltip:HookScript("OnUpdate", DecorateMinimapTip)
            GameTooltip:HookScript("OnHide", function() lastTip = nil end)
        end
        Purge()
        AddMenus()
        if GetCVar and GetCVar("nameplateShowEnemies") == "0" then
            Say("enemy nameplates are off, so only your target, focus and mouseover are seen. Turn them on (Ctrl+V) for the full picture.")
        end
    else
        ev:UnregisterAllEvents()
        if ticker then ticker:Cancel(); ticker = nil end
        if win and not InCombatLockdown() then win:Hide() end
    end
    KoSButtonUpdate()
    MapApply()
end

CludesUI._PvP = { Get = Get, Cfg = F.Cfg, Apply = Apply, Show = function() module.ShowPvP() end,
    Stats = function() module.ShowPvPStats() end }

SLASH_CUIPVP1 = "/cpvp"
SlashCmdList.CUIPVP = function(msg)
    local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    if cmd == "stats" then module.ShowPvPStats()
    elseif cmd == "kos" and rest ~= "" then module.PvPToggleKoS((rest:gsub(" ", "-")))
    elseif cmd == "ignore" and rest ~= "" then module.PvPToggleIgnore((rest:gsub(" ", "-")))
    elseif cmd == "watch" then
        local typed, reason = rest:match("^([^:]*):(.*)$")
        typed = (typed or rest):match("^%s*(.-)%s*$")
        reason = reason and reason:match("^%s*(.-)%s*$") or nil
        if reason == "" then reason = nil end
        local name = typed ~= "" and (typed:gsub(" ", "-")) or PlayerName("target")
        if not name then return Say("target a player or type /cpvp watch First Last: reason") end
        module.PvPToggleWatch(name, reason)
    elseif cmd == "watchlist" then
        local n = 0
        for name, e in pairs(Store().watch) do
            n = n + 1
            Say(("%s%s%s"):format(name:gsub("%-", " "), e.reason and (" (" .. e.reason .. ")") or "",
                e.seen and (", last seen " .. Ago(time() - e.seen) .. " ago in " .. (e.zone or "?")) or ""))
        end
        if n == 0 then Say("your watch list is empty.") end
    elseif cmd == "clear" then wipe(nearby); wipe(active); if Refresh then Refresh() end
    else module.ShowPvP() end
end

F.Start(Apply)
