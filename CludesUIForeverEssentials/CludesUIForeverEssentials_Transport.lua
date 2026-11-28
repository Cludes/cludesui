if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
if not (CUI and CUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_Transport.lua  (WoW Forever only)
--  Boat and Zeppelin Timers: when each ship leaves and arrives, on minimap
--  pins at its docks and on a Zone Timer listing the zone's ships.
--  How a ship gets timed:
--    a ride        riding along one of its trigger segments times it
--                  (TransportData.lua holds them);
--    a click       left-click a dock's pin as the ship arrives, right-click
--                  as it leaves;
--    a dockmaster  the Zephras Isle skycutter's arrival call;
--    others        with Share Timings on, CludesUI users in your group and
--                  guild (the "CludesShips" message) and ForeverTransport
--                  and NauticusClassic users nearby.
--                  A shared timing is never sent on again.
--    the schedule  until then, a starting timing from a ride on Forever.
--  Timings are kept per realm, on the server clock.
-------------------------------------------------------------------------------
local _, module = ...

local F = module.Feature(
    "transport",
    { enabled = false, share = true, zone = true, size = 13 },
    { point = "TOPRIGHT", relPoint = "TOPRIGHT", x = -220, y = -260 }
)
local Get, Enabled = F.Get, F.Enabled

local RouteList = module.TransportRoutes or {}
local Data = module.TransportData or {}
local Timetable = module.TransportSchedule or {}

local ARRIVE_EVENT, DEPART_EVENT = "arrival", "departure"
local MAP_ALIAS = { [2665] = 2521 }
local function AliasMap(map) return MAP_ALIAS[map] or map end
local function Secret(val) return issecretvalue and issecretvalue(val) end
local function Font() return CUI.GetFontPath("essentials") end

-------------------------------------------------------------------------------
--  Times (server clock, per realm)
-------------------------------------------------------------------------------
local OLD_CYCLES, TIMETABLE_CYCLES = 6, 300
local SHARPEN_BAND, BOARD_MISS, BOARD_BAND = 0.15, 3, 0.02
local TimesFor = {}

local docks = {}
for name, route in pairs(RouteList) do
    for index, dock in ipairs(route.docks) do
        docks[dock.stop] = { name = name, index = index }
    end
end

local function SavedTimes(slot)
    local cfg = F.Cfg()
    cfg[slot] = cfg[slot] or {}
    local realm = GetRealmName() or "?"
    cfg[slot][realm] = cfg[slot][realm] or {}
    return cfg[slot][realm]
end
local function RowList() return SavedTimes("sightings") end
local function RideList() return SavedTimes("rides") end

local function Sharpen(elapsed, loopSecs)
    local loops = math.ceil(elapsed / (loopSecs * (1 + SHARPEN_BAND)))
    if loops < 1 or loops ~= math.floor(elapsed / (loopSecs * (1 - SHARPEN_BAND))) then return nil end
    return elapsed / loops
end

function TimesFor.Prune(nowTime)
    local reset = nowTime + (C_DateAndTime.GetSecondsUntilWeeklyReset() or 0) - 7 * 86400
    for key, row in pairs(RowList()) do
        if row.last < reset or not Data[key] then RowList()[key] = nil end
    end
    for name in pairs(RideList()) do
        if not RouteList[name] then RideList()[name] = nil end
    end
end

function TimesFor.RouteAt(key)
    local skinData = docks[key]
    if skinData then return skinData.name, skinData.index end
end

local function WithinBand(loopSecs, route) return math.abs(loopSecs - route.period) <= BOARD_BAND * route.period end

local function Save(name, route, since, loopSecs, shared)
    local rides = RideList()
    local row = rides[name]
    if row and since == row.at then return false end
    if row then
        local p = row.period or route.period
        local loops = math.floor((since - row.base) / p + 0.5)
        local timedAt = loops >= 1 and (since - row.base) / loops
        if loops >= 0 and math.abs(since - row.base - loops * p) <= BOARD_MISS then
            if timedAt and WithinBand(timedAt, route) then row.period = timedAt end
            row.at, row.shared = since, shared
            return true
        end
    end
    rides[name] = { base = since, at = since, period = loopSecs, shared = shared }
    return true
end

function TimesFor.Ride(name, since)
    local route = RouteList[name]
    if not route or not Save(name, route, since) then return false end
    if TimesFor.OnTimed then TimesFor.OnTimed(name) end
    return true
end

function TimesFor.Shared(name, at, loopSecs, nowTime)
    local route = RouteList[name]
    if not route or at > nowTime + BOARD_MISS then return false end
    if loopSecs and not WithinBand(loopSecs, route) then return false end
    local row = RideList()[name]
    if row and row.at >= at then return false end
    return Save(name, route, at, loopSecs, true)
end

function TimesFor.Latest(name)
    local row = RideList()[name]
    if row and not row.shared then return row.at, row.period end
end

function TimesFor.Dock(name, index, nowTime)
    local route = RouteList[name]
    local ride = route and RideList()[name]
    local row = ride or (route and Timetable[name])
    if not row then return nil, "new" end
    if nowTime < row.at then return nil, "stale" end
    local dock = route.docks[index]
    local loopSecs = row.period or route.period
    if not ride and nowTime - row.at > TIMETABLE_CYCLES * loopSecs then return nil, "expired" end
    local offset = (nowTime - row.at) % loopSecs
    if offset >= dock.arrive and offset < dock.leave then return dock.leave - offset, DEPART_EVENT end
    return (dock.arrive - offset) % loopSecs, ARRIVE_EVENT
end

function TimesFor.Record(key, kind, nowTime)
    local timing = Data[key]
    if not timing or (kind ~= ARRIVE_EVENT and kind ~= DEPART_EVENT) then return false end
    local name, index = TimesFor.RouteAt(key)
    if name then
        local dock = RouteList[name].docks[index]
        return TimesFor.Ride(name, nowTime - (kind == ARRIVE_EVENT and dock.arrive or dock.leave))
    end
    local rowList = RowList()
    local row = rowList[key]
    if row and nowTime == row.last then return false end
    local loopSecs = row and row.period
    if row and row.kind == kind and nowTime > row.last then
        loopSecs = Sharpen(nowTime - row.last, timing.period) or loopSecs
    end
    rowList[key] = {
        arrival = kind == ARRIVE_EVENT and nowTime or nowTime - timing.dwell,
        last = nowTime,
        kind = kind,
        period = loopSecs,
    }
    return true
end

function TimesFor.Next(key, nowTime)
    local name, index = TimesFor.RouteAt(key)
    if name then return TimesFor.Dock(name, index, nowTime) end
    local timing = Data[key]
    local row = timing and RowList()[key]
    if not row then return nil, "new" end
    if nowTime < row.last then return nil, "stale" end
    local loopSecs = row.period or timing.period
    if nowTime - row.last > OLD_CYCLES * loopSecs then return nil, "expired" end
    local offset = (nowTime - row.arrival) % loopSecs
    if offset < timing.dwell then return timing.dwell - offset, DEPART_EVENT end
    return loopSecs - offset, ARRIVE_EVENT
end
module.TransportTimes = TimesFor

-------------------------------------------------------------------------------
--  Ride: timed from where you ride along a trigger segment
-------------------------------------------------------------------------------
local POLL_SECONDS, DOCK_YARDS, PACE_BAND, HEADING_SLACK, QUIET_SECONDS = 0.8, 20, 0.35, 0.9, 30
local watched = {}
for _, route in pairs(RouteList) do
    for _, map in ipairs(route.zones) do
        watched[map] = true
    end
end
local rideTimer, last
local timed = {}

local function CheckDock(posX, posY, continent, dx, dy, elapsed, nowTime)
    local moved = math.sqrt(dx * dx + dy * dy)
    if moved <= 0 then return end
    for name, route in pairs(RouteList) do
        if not timed[name] or nowTime - timed[name] >= QUIET_SECONDS then
            for _, t in ipairs(route.triggers) do
                local sx, sy = t.bx - t.ax, t.by - t.ay
                local length = math.sqrt(sx * sx + sy * sy)
                local along = ((posX - t.ax) * sx + (posY - t.ay) * sy) / (length * length)
                local fx, fy = t.ax + sx * along - posX, t.ay + sy * along - posY
                if
                    t.continent == continent
                    and along >= 0
                    and along <= 1
                    and fx * fx + fy * fy <= DOCK_YARDS ^ 2
                then
                    local speed = length / t.span
                    if
                        math.abs(moved / elapsed - speed) <= PACE_BAND * speed
                        and (dx * sx + dy * sy) / (moved * length) >= HEADING_SLACK
                    then
                        timed[name] = nowTime
                        TimesFor.Ride(name, GetServerTime() - (t.at + t.span * along))
                        return
                    end
                end
            end
        end
    end
end

local function OnRideTick()
    if UnitOnTaxi("player") or IsSwimming() then
        last = nil
        return
    end
    local posX, posY, _, continent = UnitPosition("player")
    if not posX or Secret(posX) then
        last = nil
        return
    end
    local nowTime = GetTime()
    if last and last.continent == continent and nowTime > last.time then
        CheckDock(posX, posY, continent, posX - last.x, posY - last.y, nowTime - last.time, nowTime)
    end
    last = last or {}
    last.x, last.y, last.continent, last.time = posX, posY, continent, nowTime
end

local function WatchRide(map)
    local details = map and C_Map.GetMapInfo(map)
    local wanted = map
        and (watched[AliasMap(map)] or (details and details.mapType == Enum.UIMapType.Continent))
    if wanted and not rideTimer then
        rideTimer = C_Timer.NewTicker(POLL_SECONDS, OnRideTick)
    elseif not wanted and rideTimer then
        rideTimer:Cancel()
        rideTimer, last = nil, nil
    end
end

-------------------------------------------------------------------------------
--  Dockmaster calls (the Zephras Isle skycutter)
-------------------------------------------------------------------------------
local CALL_SOURCES = { [256306] = "1416:Zeppelin to Zephras Isle", [275269] = "2521:Zeppelin to Dalaran" }
local callZones, silentUntil = {}, {}
for _, stop in pairs(CALL_SOURCES) do
    if Data[stop] then callZones[Data[stop].map] = true end
end
local callFrame
local function WatchCalls(map)
    local wanted = map ~= nil and callZones[AliasMap(map)] == true
    if wanted and not callFrame then
        callFrame = CreateFrame("Frame")
        callFrame:SetScript("OnEvent", function(_, _, ...)
            local unitGuid = select(12, ...)
            if not unitGuid or Secret(unitGuid) then return end
            local stop = CALL_SOURCES[tonumber(unitGuid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"))]
            if not stop or (silentUntil[stop] and GetTime() < silentUntil[stop]) then return end
            local name, index = TimesFor.RouteAt(stop)
            local dock = RouteList[name].docks[index]
            silentUntil[stop] = GetTime() + dock.leave - dock.arrive + 5
            TimesFor.Record(stop, ARRIVE_EVENT, GetServerTime())
        end)
    end
    if not callFrame then return end
    for _, event in ipairs({
        "CHAT_MSG_MONSTER_SAY",
        "CHAT_MSG_MONSTER_YELL",
        "CHAT_MSG_MONSTER_EMOTE",
        "CHAT_MSG_RAID_BOSS_EMOTE",
    }) do
        if wanted then
            callFrame:RegisterEvent(event)
        else
            callFrame:UnregisterEvent(event)
        end
    end
end

-------------------------------------------------------------------------------
--  Sharing: our own (CludesShips) and ForeverTransport / NauticusClassic users
-------------------------------------------------------------------------------
local PREFIX, ASK_TAG = "CludesShips", "Q"
local TIMES_FORMAT = "T %s %.3f %.3f %s"
local TIMES_PATTERN = "^T (Player%-%d+%-%x+) (%d+%.?%d*) (%d+%.?%d*) (.+)$"
local SHARE_TO = { PARTY = true, RAID = true, INSTANCE_CHAT = true, GUILD = true }
local PEER_PREFIX, NT_PREFIX = "FTrans2", "NauticSync"
local PEER_ASK = "Q|5"
local PEER_TIMING = "^A|(%d+)|(%d+)|(%d+%.?%d*)|(%d+%.?%d*)|"
local NT_HEAD = "KWN4 4 "
local NT_TIMING = "^KWN4 4 ([^ ]+) ([^ ]+)$"
local NT_DIGITS = "0123456789ABCDEFGHIJKLMNOPQRTUVWXYZabcdefghijklmnopqrtuvwxyz!\"#$&'()*+-./;<=>?@[\\]^_`{}~"
    .. "\001\002\003\004\005\006\007\008\011\012"
    .. "\014\015\016\017\018\019\020\021\022\023\024\025\026\027\028\029\030\031\127"
local PEER_FRESH = { PARTY = true, RAID = true, GUILD = true, YELL = true, WHISPER = true }
local OLD_SHIP_ALIAS = 5

local own, inGroup, guildAskedAt, guildAnsweredAt
local pending, asked = {}, {}
local named, docked, digit = {}, {}, {}
for name, route in pairs(RouteList) do
    if route.nauticus then named[route.nauticus] = name end
    for _, dock in ipairs(route.docks) do
        if Data[dock.stop] then docked[Data[dock.stop].map] = true end
    end
end
local base = #NT_DIGITS
for index = 1, base do
    digit[NT_DIGITS:byte(index)] = index - 1
end

local function Unpack(textValue)
    if not textValue or #textValue > 8 then return nil end
    local number, place = 0, 1
    for index = 1, #textValue do
        local value = digit[textValue:byte(index)]
        if not value then return nil end
        number, place = number + value * place, place * base
    end
    return number
end
local function Pack(number)
    local textValue = ""
    repeat
        local remain = number % base
        textValue = textValue .. NT_DIGITS:sub(remain + 1, remain + 1)
        number = (number - remain) / base
    until number == 0
    return textValue
end
local function Checksum(textValue)
    local counter, length = 1, #textValue
    for index = 1, length, 3 do
        counter = (counter * 8161) % 4294967279
            + textValue:byte(index) * 16776193
            + (textValue:byte(index + 1) or length - index + 256) * 8372226
            + (textValue:byte(index + 2) or length - index + 256) * 3932164
    end
    return counter % 4294967291
end
local ntAsk
do
    local ids = {}
    for ident in pairs(named) do
        if ident ~= OLD_SHIP_ALIAS then ids[#ids + 1] = ident end
    end
    table.sort(ids)
    for index, ident in ipairs(ids) do
        ids[index] = Pack(ident)
    end
    local entries = table.concat(ids, ",")
    ntAsk = NT_HEAD .. entries .. " " .. Pack(Checksum(entries))
end

local function PartyChannel()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
end

local function SharingOn() return Enabled() and Get("share") end

local function Broadcast(name, channel)
    local at, loopSecs = TimesFor.Latest(name)
    if at and own then
        C_ChatInfo.SendAddonMessage(PREFIX, TIMES_FORMAT:format(own, at, loopSecs or 0, name), channel)
    end
end

TimesFor.OnTimed = function(name)
    if not SharingOn() then return end
    local set = PartyChannel()
    if set then Broadcast(name, set) end
    if IsInGuild() then Broadcast(name, "GUILD") end
end

local function ReplyShortly(channel)
    if pending[channel] then return end
    if channel == "GUILD" then
        if guildAnsweredAt and GetTime() - guildAnsweredAt < 30 then return end
        guildAnsweredAt = GetTime()
    end
    local nameList
    for name in pairs(RouteList) do
        if TimesFor.Latest(name) then
            nameList = nameList or {}
            nameList[name] = true
        end
    end
    if not nameList then return end
    pending[channel] = nameList
    C_Timer.After(math.random(1, 30) / 10, function()
        local entries = pending[channel]
        pending[channel] = nil
        if entries and SharingOn() then
            for name in pairs(entries) do
                Broadcast(name, channel)
            end
        end
    end)
end

-- The sender must be the group or guild member whose GUID the message carries.
local function FromSender(sender, unitGuid)
    local success, _, _, _, _, _, name = pcall(GetPlayerInfoByGUID, unitGuid)
    if not success or type(name) ~= "string" or Secret(name) then return false end
    local short = Ambiguate(sender, "none")
    return short == name or short:find("^" .. name) ~= nil
end

local function AskPeers(channel)
    if asked[channel] and GetTime() - asked[channel] < 120 then return end
    asked[channel] = GetTime()
    C_ChatInfo.SendAddonMessage(PEER_PREFIX, PEER_ASK, channel)
    C_ChatInfo.SendAddonMessage(NT_PREFIX, ntAsk, channel)
end

local function SecondsBefore(name, start, moment)
    local loopSecs = RouteList[name].period
    return start + math.floor((moment - start) / loopSecs) * loopSecs
end

local shareFrame = CreateFrame("Frame")
shareFrame:SetScript("OnEvent", function(_, evt, prefixValue, message, channel, sender)
    if evt == "CHAT_MSG_ADDON" then
        if Secret(prefixValue) or Secret(message) or Secret(channel) or Secret(sender) then return end
        local nowTime = GetServerTime()
        if prefixValue == PREFIX and SHARE_TO[channel] then
            if message == ASK_TAG then return ReplyShortly(channel) end
            local unitGuid, at, loopSecs, name = message:match(TIMES_PATTERN)
            at, loopSecs = tonumber(at), tonumber(loopSecs)
            if
                not unitGuid
                or not own
                or unitGuid == own
                or not at
                or not RouteList[name]
                or not FromSender(sender, unitGuid)
            then
                return
            end
            TimesFor.Shared(name, at, loopSecs ~= 0 and loopSecs or nil, nowTime)
            for _, entries in pairs(pending) do
                local ours = TimesFor.Latest(name)
                if entries[name] and (not ours or ours <= at) then entries[name] = nil end
            end
        elseif PEER_FRESH[channel] and prefixValue == PEER_PREFIX then
            local ident, index, arrival, seenAt = message:match(PEER_TIMING)
            local name = named[tonumber(ident)]
            local dock = name and RouteList[name].docks[tonumber(index)]
            if dock then
                TimesFor.Shared(
                    name,
                    SecondsBefore(name, tonumber(arrival) - dock.arrive, tonumber(seenAt)),
                    nil,
                    nowTime
                )
            end
        elseif PEER_FRESH[channel] and prefixValue == NT_PREFIX then
            local entries, hash = message:match(NT_TIMING)
            if not entries or Unpack(hash) ~= Checksum(entries) then return end
            local _, _, lag = GetNetStats()
            for record in entries:gmatch("[^,]+") do
                local ident, since = record:match("^([^:]+):([^:]+)")
                ident, since = Unpack(ident), Unpack(since)
                local name = ident ~= OLD_SHIP_ALIAS and named[ident]
                if name and since and since <= 3.2e10 then
                    TimesFor.Shared(
                        name,
                        nowTime - ((since + (lag or 0)) / 1000) % RouteList[name].period,
                        nil,
                        nowTime
                    )
                end
            end
        end
        return
    end
    own = own or UnitGUID("player")
    local set = PartyChannel()
    if set and not inGroup then
        C_ChatInfo.SendAddonMessage(PREFIX, ASK_TAG, set)
        for name in pairs(RouteList) do
            Broadcast(name, set)
        end
    end
    inGroup = set ~= nil
    if not guildAskedAt and IsInGuild() then
        guildAskedAt = true
        C_ChatInfo.SendAddonMessage(PREFIX, ASK_TAG, "GUILD")
    end
    if IsInRaid(LE_PARTY_CATEGORY_HOME) then
        AskPeers("RAID")
    elseif IsInGroup(LE_PARTY_CATEGORY_HOME) then
        AskPeers("PARTY")
    end
    if evt ~= "GROUP_ROSTER_UPDATE" then
        if IsInGuild() then AskPeers("GUILD") end
        local map = C_Map.GetBestMapForUnit("player")
        if map and docked[AliasMap(map)] and not IsInInstance() then AskPeers("YELL") end
    end
end)

local function ApplySharing()
    shareFrame:UnregisterAllEvents()
    if not SharingOn() then
        wipe(pending)
        inGroup, guildAskedAt = false, false
        return
    end
    for _, p in ipairs({ PREFIX, PEER_PREFIX, NT_PREFIX }) do
        C_ChatInfo.RegisterAddonMessagePrefix(p)
    end
    for _, event in ipairs({
        "CHAT_MSG_ADDON",
        "PLAYER_ENTERING_WORLD",
        "GROUP_ROSTER_UPDATE",
        "ZONE_CHANGED_NEW_AREA",
    }) do
        shareFrame:RegisterEvent(event)
    end
end

-------------------------------------------------------------------------------
--  Minimap pins
-------------------------------------------------------------------------------
local Layer = {}
Layer.__index = Layer

local function FitPhase(self, mapID)
    local cont, o = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(0, 0))
    local _, u = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(1, 0))
    local _, val = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(0, 1))
    if not (o and u and val) then return false end
    self.cont, self.ox, self.oy = cont, o:GetXY()
    local ux, uy = u:GetXY()
    local vx, vy = val:GetXY()
    self.ux, self.uy, self.vx, self.vy = ux - self.ox, uy - self.oy, vx - self.ox, vy - self.oy
    self.det = self.ux * self.vy - self.uy * self.vx
    self.width, self.height = C_Map.GetMapWorldSize(mapID)
    return self.det ~= 0
end

local function HideSource(self, first)
    for index = first, #self.pins do
        self.pins[index]:Hide()
        self.pins[index].spot = nil
    end
end

function Layer:Place()
    local wx, wy, _, cont = UnitPosition("player")
    if not wx or Secret(wx) or cont ~= self.cont then return HideSource(self, 1) end
    local rx, ry = wx - self.ox, wy - self.oy
    local px, py = (rx * self.vy - ry * self.vx) / self.det, (self.ux * ry - self.uy * rx) / self.det
    local radius = C_Minimap.GetViewRadius()
    if not self.at or radius ~= self.radius or (wx - self.at[1]) ^ 2 + (wy - self.at[2]) ^ 2 > 1600 then
        self.at, self.radius = { wx, wy }, radius
        wipe(self.near)
        for index = 1, self.count do
            local posX, posY = self.opts.xy(self.spots, index)
            local dx, dy = (posX - px) * self.width, (py - posY) * self.height
            if dx * dx + dy * dy <= (radius * 2) ^ 2 then self.near[#self.near + 1] = index end
        end
    end
    local facing = C_CVar.GetCVarBool("rotateMinimap") and GetPlayerFacing() or 0
    local sin, cos = math.sin(facing), math.cos(facing)
    local square = GetMinimapShape and GetMinimapShape() == "SQUARE"
    local scaleX, scaleY = Minimap:GetWidth() / 2 / radius, Minimap:GetHeight() / 2 / radius
    local num = 0
    for _, index in ipairs(self.near) do
        if num >= self.opts.max then break end
        local posX, posY = self.opts.xy(self.spots, index)
        local dx, dy = (posX - px) * self.width, (py - posY) * self.height
        dx, dy = dx * cos + dy * sin, dy * cos - dx * sin
        local inside = square and (math.abs(dx) <= radius and math.abs(dy) <= radius)
            or (dx * dx + dy * dy <= radius * radius)
        if inside then
            num = num + 1
            local pin = self.pins[num] or self.opts.new(num)
            self.pins[num] = pin
            if pin.spot ~= index then
                pin.spot = index
                self.opts.paint(pin, self.spots, index)
            end
            pin:ClearAllPoints()
            pin:SetPoint("CENTER", Minimap, "CENTER", dx * scaleX, dy * scaleY)
            pin:Show()
        end
    end
    HideSource(self, num + 1)
end

local function AddLayer(options)
    local self = setmetatable({ opts = options, pins = {}, near = {}, count = 0 }, Layer)
    self.frame = CreateFrame("Frame")
    self.frame.since = 0
    local function IsLive()
        local live = self.count > 0 and (self.moving or C_CVar.GetCVarBool("rotateMinimap"))
        self.frame:SetScript("OnUpdate", live and function(frame, e)
            frame.since = frame.since + e
            if frame.since >= 0.05 then
                frame.since = 0
                self:Place()
            end
        end or nil)
    end
    self.Live = IsLive
    self.frame:SetScript("OnEvent", function(_, evt)
        if evt ~= "MINIMAP_UPDATE_ZOOM" then self.moving = evt == "PLAYER_STARTED_MOVING" end
        self:Place()
        IsLive()
    end)
    return self
end

function Layer:Set(mapID, spots, total)
    self.spots, self.count, self.at = spots, 0, nil
    if mapID and spots and total > 0 and FitPhase(self, mapID) then self.count = total end
    for _, pin in ipairs(self.pins) do
        pin.spot = nil
    end
    for _, event in ipairs({ "PLAYER_STARTED_MOVING", "PLAYER_STOPPED_MOVING", "MINIMAP_UPDATE_ZOOM" }) do
        if self.count > 0 then
            self.frame:RegisterEvent(event)
        else
            self.frame:UnregisterEvent(event)
        end
    end
    if self.count > 0 then
        self.moving = IsPlayerMoving()
        self:Place()
    else
        HideSource(self, 1)
    end
    self.Live()
end

--- Minimap pins for other features (the town map): NewLayer({ max, new, paint, xy }).
module.MinimapLayer = AddLayer

-------------------------------------------------------------------------------
--  Tooltips, pins, Zone Timer
-------------------------------------------------------------------------------
local DEPARTING_SOON = 30
local AT_DOCK, DEPARTING, UNDERWAY = { 1, 0.82, 0 }, { 1, 0.25, 0.25 }, { 0.25, 1, 0.25 }
local CITY_MAPS = { [1454] = 1411, [1456] = 1412, [1457] = 1438, [1458] = 1420 }

local function TintFor(kind, seconds)
    if kind == ARRIVE_EVENT then return UNDERWAY end
    return seconds > DEPARTING_SOON and AT_DOCK or DEPARTING
end
local function MS(seconds)
    local region = math.ceil(seconds)
    return math.floor(region / 60), region % 60
end
local function CountdownText(seconds, kind)
    return ((kind == ARRIVE_EVENT) and "Arrives in %d:%02d" or "Departs in %d:%02d"):format(MS(seconds))
end
local function TintedText(textValue, cfg)
    return ("|cff%02x%02x%02x%s|r"):format(cfg[1] * 255, cfg[2] * 255, cfg[3] * 255, textValue)
end

local function ClockText(key, nowTime)
    local seconds, kind = TimesFor.Next(key, nowTime)
    if seconds then return CountdownText(seconds, kind), TintFor(kind, seconds) end
    local named = TimesFor.RouteAt(key) ~= nil
    local textValue = kind == "stale" and "Server clock changed; time it again."
        or kind == "expired" and "Estimate out of date"
        or "Not timed yet"
    return textValue,
        { 0.6, 0.6, 0.6 },
        named and "Ride it once to time it." or "Time it from its minimap pin at the dock."
end

local function ShowTimesTip(pin)
    local nowTime = GetServerTime()
    GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
    local name = TimesFor.RouteAt(pin.key)
    if name then
        GameTooltip:SetText(name, 0.25, 0.75, 1)
        local any
        for index, dock in ipairs(RouteList[name].docks) do
            local zone = Data[dock.stop] and C_Map.GetMapInfo(Data[dock.stop].map)
            GameTooltip:AddLine(zone and (dock.place .. ", " .. zone.name) or dock.place, 1, 1, 1)
            local seconds, kind = TimesFor.Dock(name, index, nowTime)
            if seconds then
                any = true
                local c = TintFor(kind, seconds)
                GameTooltip:AddDoubleLine(
                    kind == ARRIVE_EVENT and "Arrival:" or "Departure:",
                    ("%dm %02ds"):format(MS(seconds)),
                    1,
                    0.82,
                    0,
                    c[1],
                    c[2],
                    c[3]
                )
            else
                GameTooltip:AddLine(
                    kind == "stale" and "Server clock changed; time it again." or "Not timed yet",
                    0.6,
                    0.6,
                    0.6
                )
            end
        end
        if not any then GameTooltip:AddLine("Ride it once to time it.", 0.6, 0.6, 0.6) end
    else
        local routes = Data[pin.key].routes
        GameTooltip:SetText(routes[1], 1, 1, 1)
        for index = 2, #routes do
            GameTooltip:AddLine(routes[index], 1, 1, 1)
        end
        local textValue, c = ClockText(pin.key, nowTime)
        GameTooltip:AddLine(textValue, c[1], c[2], c[3])
    end
    GameTooltip:AddLine("Left-click when it arrives, right-click when it leaves.", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local layer, board
local spots, zoneDocks = {}, {}

local function MakePin()
    local pin = CreateFrame("Button", nil, Minimap)
    pin:SetSize(16, 16)
    pin.icon = pin:CreateTexture(nil, "ARTWORK")
    pin.icon:SetAllPoints()
    pin:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    pin:SetScript("OnClick", function(self, btnFrame)
        TimesFor.Record(self.key, btnFrame == "LeftButton" and ARRIVE_EVENT or DEPART_EVENT, GetServerTime())
        ShowTimesTip(self)
    end)
    pin:SetScript("OnEnter", function(self)
        ShowTimesTip(self)
        self.since = 0
        self:SetScript("OnUpdate", function(cfg, e)
            cfg.since = cfg.since + e
            if cfg.since >= 1 then
                cfg.since = 0
                ShowTimesTip(cfg)
            end
        end)
    end)
    pin:SetScript("OnLeave", function(self)
        self:SetScript("OnUpdate", nil)
        GameTooltip:Hide()
    end)
    return pin
end

local function DrawPin(pin, entries, index)
    pin.key = entries[index]
    local route = Data[pin.key].routes[1] or ""
    pin.icon:SetAtlas(route:find("^Zeppelin") and "vehicle-air-horde" or "flightmasterferry")
end

local function MakeBoard()
    if board then return board end
    board = CreateFrame("Frame", "CludesUIShipTimer", UIParent)
    CUI.Kit.Panel(board, 0.7)
    board.names = board:CreateFontString(nil, "OVERLAY")
    board.names:SetPoint("TOPLEFT", 8, -6)
    board.names:SetJustifyH("LEFT")
    board.names:SetTextColor(1, 0.82, 0)
    board.times = board:CreateFontString(nil, "OVERLAY")
    board.times:SetPoint("TOPRIGHT", -8, -6)
    board.times:SetJustifyH("RIGHT")
    board.since = 0
    board:SetScript("OnUpdate", function(self, e)
        self.since = self.since + e
        if self.since >= 1 then
            self.since = 0
            module.TransportDrawZone()
        end
    end)
    board:Hide()
    return board
end

function module.TransportDrawZone()
    if not board then return end
    local show = Enabled() and Get("zone") and (zoneDocks[1] ~= nil or CUI._unlockActive)
    if not show then
        board:Hide()
        return
    end
    local nameList, times, nowTime = {}, {}, GetServerTime()
    for index, key in ipairs(zoneDocks) do
        nameList[index] = table.concat(Data[key].routes, " / ")
        local textValue, c = ClockText(key, nowTime)
        times[index] = TintedText(textValue, c)
    end
    if #nameList == 0 then
        nameList[1], times[1] = "Boat to Booty Bay", TintedText("Departs in 0:42", AT_DOCK)
    end
    local size = Get("size")
    CUI.Kit.Font(board.names, size, "essentials")
    CUI.Kit.Font(board.times, size, "essentials")
    board.names:SetText(table.concat(nameList, "\n"))
    board.times:SetText(table.concat(times, "\n"))
    board:SetSize(
        board.names:GetStringWidth() + 12 + board.times:GetStringWidth() + 16,
        board.names:GetStringHeight() + 12
    )
    board:Show()
end

local function Redraw()
    wipe(spots)
    wipe(zoneDocks)
    local map = Enabled() and C_Map.GetBestMapForUnit("player")
    if map then
        local side = UnitFactionGroup("player") == "Horde" and "H" or "A"
        local same = AliasMap(map)
        local zone = CITY_MAPS[same] or same
        for key, stop in pairs(Data) do
            if stop.map == same and stop.side:find(side, 1, true) then
                if not stop.mapX then
                    local _, position =
                        C_Map.GetMapPosFromWorldPos(stop.continent, CreateVector2D(stop.x, stop.y), map)
                    if position then
                        stop.mapX, stop.mapY = position:GetXY()
                    end
                end
                if stop.mapX then spots[#spots + 1] = key end
            end
            if stop.map == zone and stop.side:find(side, 1, true) then zoneDocks[#zoneDocks + 1] = key end
        end
        table.sort(zoneDocks)
    end
    WatchRide(map)
    WatchCalls(map)
    module.TransportDrawZone()
    if not layer and #spots == 0 then return end
    layer = layer
        or AddLayer({
            max = 3,
            new = MakePin,
            paint = DrawPin,
            xy = function(entries, index) return Data[entries[index]].mapX, Data[entries[index]].mapY end,
        })
    layer:Set(map, spots, #spots)
end

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, evt)
    if evt == "PLAYER_ENTERING_WORLD" then TimesFor.Prune(GetServerTime()) end
    Redraw()
end)

--- For other maps (the world map's docks): "Departs in 1:20" and its colour for a stop key.
function module.TransportTimeText(key) return ClockText(key, GetServerTime()) end

local function Apply()
    eventFrame:UnregisterAllEvents()
    if Enabled() then
        for _, event in ipairs({
            "PLAYER_ENTERING_WORLD",
            "ZONE_CHANGED_NEW_AREA",
            "ZONE_CHANGED",
            "ZONE_CHANGED_INDOORS",
        }) do
            eventFrame:RegisterEvent(event)
        end
        if IsLoggedIn() then TimesFor.Prune(GetServerTime()) end
        if Get("zone") then MakeBoard() end
        if board and not CUI._unlockActive then F.Place(board) end
    end
    ApplySharing()
    Redraw()
end

CUI._Transport = { Get = Get, Cfg = F.Cfg, Apply = Apply }

F.Start(Apply, {
    key = "CUI_ShipTimer",
    label = "Boat and Zeppelin Timer",
    order = 754,
    shown = function() return Enabled() and Get("zone") end,
    frame = function(build)
        if build then
            MakeBoard()
            module.TransportDrawZone()
        end
        return board
    end,
    size = function() return 220, 40 end,
    noAnchorTarget = true,
    noSizeMatchTarget = true,
})
