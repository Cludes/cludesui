if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if not (CludesUI and CludesUI.IS_FOREVER) then return end
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
--                  guild (the "NaowhShips" message, which Naowh Forever uses
--                  too) and ForeverTransport and NauticusClassic users nearby.
--                  A shared timing is never sent on again.
--    the schedule  until then, a starting timing from a ride on Forever.
--  Timings are kept per realm, on the server clock.
-------------------------------------------------------------------------------
local _, module = ...

local F = module.Feature("transport", { enabled = false, share = true, zone = true, size = 13 },
    { point = "TOPRIGHT", relPoint = "TOPRIGHT", x = -220, y = -260 })
local Get, Enabled = F.Get, F.Enabled

local Routes = module.TransportRoutes or {}
local Data = module.TransportData or {}
local Schedule = module.TransportSchedule or {}

local ARRIVAL, DEPARTURE = "arrival", "departure"
local SAME_MAP = { [2665] = 2521 }
local function SameMap(map) return SAME_MAP[map] or map end
local function Secret(v) return issecretvalue and issecretvalue(v) end
local function Font() return CludesUI.GetFontPath("essentials") end

-------------------------------------------------------------------------------
--  Times (server clock, per realm)
-------------------------------------------------------------------------------
local STALE_CYCLES, SCHEDULE_CYCLES = 6, 300
local REFINE_BAND, RIDE_MISS, RIDE_BAND = 0.15, 3, 0.02
local Times = {}

local docks = {}
for name, route in pairs(Routes) do
    for index, dock in ipairs(route.docks) do docks[dock.stop] = { name = name, index = index } end
end

local function Saved(slot)
    local c = F.Cfg()
    c[slot] = c[slot] or {}
    local realm = GetRealmName() or "?"
    c[slot][realm] = c[slot][realm] or {}
    return c[slot][realm]
end
local function Rows() return Saved("sightings") end
local function Rides() return Saved("rides") end

local function Refine(elapsed, period)
    local cycles = math.ceil(elapsed / (period * (1 + REFINE_BAND)))
    if cycles < 1 or cycles ~= math.floor(elapsed / (period * (1 - REFINE_BAND))) then return nil end
    return elapsed / cycles
end

function Times.Prune(now)
    local reset = now + (C_DateAndTime.GetSecondsUntilWeeklyReset() or 0) - 7 * 86400
    for key, row in pairs(Rows()) do if row.last < reset or not Data[key] then Rows()[key] = nil end end
    for name in pairs(Rides()) do if not Routes[name] then Rides()[name] = nil end end
end

function Times.RouteAt(key)
    local d = docks[key]
    if d then return d.name, d.index end
end

local function InBand(period, route) return math.abs(period - route.period) <= RIDE_BAND * route.period end

local function Store(name, route, since, period, shared)
    local rides = Rides()
    local row = rides[name]
    if row and since == row.at then return false end
    if row then
        local p = row.period or route.period
        local cycles = math.floor((since - row.base) / p + 0.5)
        local measured = cycles >= 1 and (since - row.base) / cycles
        if cycles >= 0 and math.abs(since - row.base - cycles * p) <= RIDE_MISS then
            if measured and InBand(measured, route) then row.period = measured end
            row.at, row.shared = since, shared
            return true
        end
    end
    rides[name] = { base = since, at = since, period = period, shared = shared }
    return true
end

function Times.Ride(name, since)
    local route = Routes[name]
    if not route or not Store(name, route, since) then return false end
    if Times.OnTimed then Times.OnTimed(name) end
    return true
end

function Times.Shared(name, at, period, now)
    local route = Routes[name]
    if not route or at > now + RIDE_MISS then return false end
    if period and not InBand(period, route) then return false end
    local row = Rides()[name]
    if row and row.at >= at then return false end
    return Store(name, route, at, period, true)
end

function Times.Latest(name)
    local row = Rides()[name]
    if row and not row.shared then return row.at, row.period end
end

function Times.Dock(name, index, now)
    local route = Routes[name]
    local ride = route and Rides()[name]
    local row = ride or (route and Schedule[name])
    if not row then return nil, "new" end
    if now < row.at then return nil, "stale" end
    local dock = route.docks[index]
    local period = row.period or route.period
    if not ride and now - row.at > SCHEDULE_CYCLES * period then return nil, "expired" end
    local phase = (now - row.at) % period
    if phase >= dock.arrive and phase < dock.leave then return dock.leave - phase, DEPARTURE end
    return (dock.arrive - phase) % period, ARRIVAL
end

function Times.Record(key, kind, now)
    local timing = Data[key]
    if not timing or (kind ~= ARRIVAL and kind ~= DEPARTURE) then return false end
    local name, index = Times.RouteAt(key)
    if name then
        local dock = Routes[name].docks[index]
        return Times.Ride(name, now - (kind == ARRIVAL and dock.arrive or dock.leave))
    end
    local rows = Rows()
    local row = rows[key]
    if row and now == row.last then return false end
    local period = row and row.period
    if row and row.kind == kind and now > row.last then period = Refine(now - row.last, timing.period) or period end
    rows[key] = { arrival = kind == ARRIVAL and now or now - timing.dwell, last = now, kind = kind, period = period }
    return true
end

function Times.Next(key, now)
    local name, index = Times.RouteAt(key)
    if name then return Times.Dock(name, index, now) end
    local timing = Data[key]
    local row = timing and Rows()[key]
    if not row then return nil, "new" end
    if now < row.last then return nil, "stale" end
    local period = row.period or timing.period
    if now - row.last > STALE_CYCLES * period then return nil, "expired" end
    local phase = (now - row.arrival) % period
    if phase < timing.dwell then return timing.dwell - phase, DEPARTURE end
    return period - phase, ARRIVAL
end
module.TransportTimes = Times

-------------------------------------------------------------------------------
--  Ride: timed from where you ride along a trigger segment
-------------------------------------------------------------------------------
local POLL, TRIGGER_RADIUS, SPEED_BAND, HEADING_MATCH, LOCKOUT = 0.8, 20, 0.35, 0.9, 30
local watched = {}
for _, route in pairs(Routes) do for _, map in ipairs(route.zones) do watched[map] = true end end
local rideTicker, last
local timed = {}

local function Check(x, y, continent, dx, dy, elapsed, now)
    local moved = math.sqrt(dx * dx + dy * dy)
    if moved <= 0 then return end
    for name, route in pairs(Routes) do
        if not timed[name] or now - timed[name] >= LOCKOUT then
            for _, t in ipairs(route.triggers) do
                local sx, sy = t.bx - t.ax, t.by - t.ay
                local length = math.sqrt(sx * sx + sy * sy)
                local along = ((x - t.ax) * sx + (y - t.ay) * sy) / (length * length)
                local fx, fy = t.ax + sx * along - x, t.ay + sy * along - y
                if t.continent == continent and along >= 0 and along <= 1 and fx * fx + fy * fy <= TRIGGER_RADIUS ^ 2 then
                    local speed = length / t.span
                    if math.abs(moved / elapsed - speed) <= SPEED_BAND * speed and (dx * sx + dy * sy) / (moved * length) >= HEADING_MATCH then
                        timed[name] = now
                        Times.Ride(name, GetServerTime() - (t.at + t.span * along))
                        return
                    end
                end
            end
        end
    end
end

local function RideTick()
    if UnitOnTaxi("player") or IsSwimming() then last = nil return end
    local x, y, _, continent = UnitPosition("player")
    if not x or Secret(x) then last = nil return end
    local now = GetTime()
    if last and last.continent == continent and now > last.time then
        Check(x, y, continent, x - last.x, y - last.y, now - last.time, now)
    end
    last = last or {}
    last.x, last.y, last.continent, last.time = x, y, continent, now
end

local function RideWatch(map)
    local info = map and C_Map.GetMapInfo(map)
    local wanted = map and (watched[SameMap(map)] or (info and info.mapType == Enum.UIMapType.Continent))
    if wanted and not rideTicker then rideTicker = C_Timer.NewTicker(POLL, RideTick)
    elseif not wanted and rideTicker then rideTicker:Cancel(); rideTicker, last = nil, nil end
end

-------------------------------------------------------------------------------
--  Dockmaster calls (the Zephras Isle skycutter)
-------------------------------------------------------------------------------
local CALLERS = { [256306] = "1416:Zeppelin to Zephras Isle", [275269] = "2521:Zeppelin to Dalaran" }
local callMaps, quietUntil = {}, {}
for _, stop in pairs(CALLERS) do if Data[stop] then callMaps[Data[stop].map] = true end end
local callEv
local function CallsWatch(map)
    local wanted = map ~= nil and callMaps[SameMap(map)] == true
    if wanted and not callEv then
        callEv = CreateFrame("Frame")
        callEv:SetScript("OnEvent", function(_, _, ...)
            local guid = select(12, ...)
            if not guid or Secret(guid) then return end
            local stop = CALLERS[tonumber(guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"))]
            if not stop or (quietUntil[stop] and GetTime() < quietUntil[stop]) then return end
            local name, index = Times.RouteAt(stop)
            local dock = Routes[name].docks[index]
            quietUntil[stop] = GetTime() + dock.leave - dock.arrive + 5
            Times.Record(stop, ARRIVAL, GetServerTime())
        end)
    end
    if not callEv then return end
    for _, e in ipairs({ "CHAT_MSG_MONSTER_SAY", "CHAT_MSG_MONSTER_YELL", "CHAT_MSG_MONSTER_EMOTE", "CHAT_MSG_RAID_BOSS_EMOTE" }) do
        if wanted then callEv:RegisterEvent(e) else callEv:UnregisterEvent(e) end
    end
end

-------------------------------------------------------------------------------
--  Sharing: our own (NaowhShips) and ForeverTransport / NauticusClassic users
-------------------------------------------------------------------------------
local PREFIX, ASK = "NaowhShips", "Q"
local TIMING_FORMAT = "T %s %.3f %.3f %s"
local TIMING_PATTERN = "^T (Player%-%d+%-%x+) (%d+%.?%d*) (%d+%.?%d*) (.+)$"
local SHARE_CHANNELS = { PARTY = true, RAID = true, INSTANCE_CHAT = true, GUILD = true }
local FOREVER_PREFIX, NAUTICUS_PREFIX = "FTrans2", "NauticSync"
local FOREVER_ASK = "Q|5"
local FOREVER_TIMING = "^A|(%d+)|(%d+)|(%d+%.?%d*)|(%d+%.?%d*)|"
local NAUTICUS_HEAD = "KWN4 4 "
local NAUTICUS_TIMING = "^KWN4 4 ([^ ]+) ([^ ]+)$"
local NAUTICUS_DIGITS = "0123456789ABCDEFGHIJKLMNOPQRTUVWXYZabcdefghijklmnopqrtuvwxyz!\"#$&'()*+-./;<=>?@[\\]^_`{}~"
    .. "\001\002\003\004\005\006\007\008\011\012"
    .. "\014\015\016\017\018\019\020\021\022\023\024\025\026\027\028\029\030\031\127"
local PEER_HEARD = { PARTY = true, RAID = true, GUILD = true, YELL = true, WHISPER = true }
local LEGACY_BRAVERY = 5

local own, inGroup, guildAsked, lastGuildAnswer
local pending, asked = {}, {}
local named, docked, digit = {}, {}, {}
for name, route in pairs(Routes) do
    if route.nauticus then named[route.nauticus] = name end
    for _, dock in ipairs(route.docks) do if Data[dock.stop] then docked[Data[dock.stop].map] = true end end
end
local base = #NAUTICUS_DIGITS
for i = 1, base do digit[NAUTICUS_DIGITS:byte(i)] = i - 1 end

local function Uncrunch(text)
    if not text or #text > 8 then return nil end
    local number, place = 0, 1
    for i = 1, #text do
        local value = digit[text:byte(i)]
        if not value then return nil end
        number, place = number + value * place, place * base
    end
    return number
end
local function Crunch(number)
    local text = ""
    repeat
        local remain = number % base
        text = text .. NAUTICUS_DIGITS:sub(remain + 1, remain + 1)
        number = (number - remain) / base
    until number == 0
    return text
end
local function Hash(text)
    local counter, length = 1, #text
    for i = 1, length, 3 do
        counter = (counter * 8161) % 4294967279 + text:byte(i) * 16776193
            + (text:byte(i + 1) or length - i + 256) * 8372226
            + (text:byte(i + 2) or length - i + 256) * 3932164
    end
    return counter % 4294967291
end
local nauticusAsk
do
    local ids = {}
    for id in pairs(named) do if id ~= LEGACY_BRAVERY then ids[#ids + 1] = id end end
    table.sort(ids)
    for i, id in ipairs(ids) do ids[i] = Crunch(id) end
    local list = table.concat(ids, ",")
    nauticusAsk = NAUTICUS_HEAD .. list .. " " .. Crunch(Hash(list))
end

local function GroupChannel()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
end

local function ShareOn() return Enabled() and Get("share") end

local function SendTo(name, channel)
    local at, period = Times.Latest(name)
    if at and own then C_ChatInfo.SendAddonMessage(PREFIX, TIMING_FORMAT:format(own, at, period or 0, name), channel) end
end

Times.OnTimed = function(name)
    if not ShareOn() then return end
    local group = GroupChannel()
    if group then SendTo(name, group) end
    if IsInGuild() then SendTo(name, "GUILD") end
end

local function AnswerSoon(channel)
    if pending[channel] then return end
    if channel == "GUILD" then
        if lastGuildAnswer and GetTime() - lastGuildAnswer < 30 then return end
        lastGuildAnswer = GetTime()
    end
    local names
    for name in pairs(Routes) do if Times.Latest(name) then names = names or {}; names[name] = true end end
    if not names then return end
    pending[channel] = names
    C_Timer.After(math.random(1, 30) / 10, function()
        local list = pending[channel]
        pending[channel] = nil
        if list and ShareOn() then for name in pairs(list) do SendTo(name, channel) end end
    end)
end

-- The sender must be the group or guild member whose GUID the message carries.
local function SenderIs(sender, guid)
    local ok, _, _, _, _, _, name = pcall(GetPlayerInfoByGUID, guid)
    if not ok or type(name) ~= "string" or Secret(name) then return false end
    local short = Ambiguate(sender, "none")
    return short == name or short:find("^" .. name) ~= nil
end

local function Ask(channel)
    if asked[channel] and GetTime() - asked[channel] < 120 then return end
    asked[channel] = GetTime()
    C_ChatInfo.SendAddonMessage(FOREVER_PREFIX, FOREVER_ASK, channel)
    C_ChatInfo.SendAddonMessage(NAUTICUS_PREFIX, nauticusAsk, channel)
end

local function Before(name, start, moment)
    local period = Routes[name].period
    return start + math.floor((moment - start) / period) * period
end

local shareEv = CreateFrame("Frame")
shareEv:SetScript("OnEvent", function(_, event, prefix, msg, channel, sender)
    if event == "CHAT_MSG_ADDON" then
        if Secret(prefix) or Secret(msg) or Secret(channel) or Secret(sender) then return end
        local now = GetServerTime()
        if prefix == PREFIX and SHARE_CHANNELS[channel] then
            if msg == ASK then return AnswerSoon(channel) end
            local guid, at, period, name = msg:match(TIMING_PATTERN)
            at, period = tonumber(at), tonumber(period)
            if not guid or not own or guid == own or not at or not Routes[name] or not SenderIs(sender, guid) then return end
            Times.Shared(name, at, period ~= 0 and period or nil, now)
            for _, list in pairs(pending) do
                local ours = Times.Latest(name)
                if list[name] and (not ours or ours <= at) then list[name] = nil end
            end
        elseif PEER_HEARD[channel] and prefix == FOREVER_PREFIX then
            local id, index, arrival, observed = msg:match(FOREVER_TIMING)
            local name = named[tonumber(id)]
            local dock = name and Routes[name].docks[tonumber(index)]
            if dock then Times.Shared(name, Before(name, tonumber(arrival) - dock.arrive, tonumber(observed)), nil, now) end
        elseif PEER_HEARD[channel] and prefix == NAUTICUS_PREFIX then
            local list, hash = msg:match(NAUTICUS_TIMING)
            if not list or Uncrunch(hash) ~= Hash(list) then return end
            local _, _, lag = GetNetStats()
            for entry in list:gmatch("[^,]+") do
                local id, since = entry:match("^([^:]+):([^:]+)")
                id, since = Uncrunch(id), Uncrunch(since)
                local name = id ~= LEGACY_BRAVERY and named[id]
                if name and since and since <= 3.2e10 then
                    Times.Shared(name, now - ((since + (lag or 0)) / 1000) % Routes[name].period, nil, now)
                end
            end
        end
        return
    end
    own = own or UnitGUID("player")
    local group = GroupChannel()
    if group and not inGroup then
        C_ChatInfo.SendAddonMessage(PREFIX, ASK, group)
        for name in pairs(Routes) do SendTo(name, group) end
    end
    inGroup = group ~= nil
    if not guildAsked and IsInGuild() then guildAsked = true; C_ChatInfo.SendAddonMessage(PREFIX, ASK, "GUILD") end
    if IsInRaid(LE_PARTY_CATEGORY_HOME) then Ask("RAID") elseif IsInGroup(LE_PARTY_CATEGORY_HOME) then Ask("PARTY") end
    if event ~= "GROUP_ROSTER_UPDATE" then
        if IsInGuild() then Ask("GUILD") end
        local map = C_Map.GetBestMapForUnit("player")
        if map and docked[SameMap(map)] and not IsInInstance() then Ask("YELL") end
    end
end)

local function ShareApply()
    shareEv:UnregisterAllEvents()
    if not ShareOn() then wipe(pending); inGroup, guildAsked = false, false return end
    for _, p in ipairs({ PREFIX, FOREVER_PREFIX, NAUTICUS_PREFIX }) do C_ChatInfo.RegisterAddonMessagePrefix(p) end
    for _, e in ipairs({ "CHAT_MSG_ADDON", "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "ZONE_CHANGED_NEW_AREA" }) do
        shareEv:RegisterEvent(e)
    end
end

-------------------------------------------------------------------------------
--  Minimap pins
-------------------------------------------------------------------------------
local Layer = {}
Layer.__index = Layer

local function Fit(self, mapID)
    local cont, o = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(0, 0))
    local _, u = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(1, 0))
    local _, v = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(0, 1))
    if not (o and u and v) then return false end
    self.cont, self.ox, self.oy = cont, o:GetXY()
    local ux, uy = u:GetXY()
    local vx, vy = v:GetXY()
    self.ux, self.uy, self.vx, self.vy = ux - self.ox, uy - self.oy, vx - self.ox, vy - self.oy
    self.det = self.ux * self.vy - self.uy * self.vx
    self.width, self.height = C_Map.GetMapWorldSize(mapID)
    return self.det ~= 0
end

local function HideFrom(self, first)
    for i = first, #self.pins do self.pins[i]:Hide(); self.pins[i].spot = nil end
end

function Layer:Place()
    local wx, wy, _, cont = UnitPosition("player")
    if not wx or Secret(wx) or cont ~= self.cont then return HideFrom(self, 1) end
    local rx, ry = wx - self.ox, wy - self.oy
    local px, py = (rx * self.vy - ry * self.vx) / self.det, (self.ux * ry - self.uy * rx) / self.det
    local radius = C_Minimap.GetViewRadius()
    if not self.at or radius ~= self.radius or (wx - self.at[1]) ^ 2 + (wy - self.at[2]) ^ 2 > 1600 then
        self.at, self.radius = { wx, wy }, radius
        wipe(self.near)
        for i = 1, self.count do
            local x, y = self.opts.xy(self.spots, i)
            local dx, dy = (x - px) * self.width, (py - y) * self.height
            if dx * dx + dy * dy <= (radius * 2) ^ 2 then self.near[#self.near + 1] = i end
        end
    end
    local facing = C_CVar.GetCVarBool("rotateMinimap") and GetPlayerFacing() or 0
    local sin, cos = math.sin(facing), math.cos(facing)
    local square = GetMinimapShape and GetMinimapShape() == "SQUARE"
    local scaleX, scaleY = Minimap:GetWidth() / 2 / radius, Minimap:GetHeight() / 2 / radius
    local n = 0
    for _, i in ipairs(self.near) do
        if n >= self.opts.max then break end
        local x, y = self.opts.xy(self.spots, i)
        local dx, dy = (x - px) * self.width, (py - y) * self.height
        dx, dy = dx * cos + dy * sin, dy * cos - dx * sin
        local inside = square and (math.abs(dx) <= radius and math.abs(dy) <= radius) or (dx * dx + dy * dy <= radius * radius)
        if inside then
            n = n + 1
            local pin = self.pins[n] or self.opts.new(n)
            self.pins[n] = pin
            if pin.spot ~= i then pin.spot = i; self.opts.paint(pin, self.spots, i) end
            pin:ClearAllPoints()
            pin:SetPoint("CENTER", Minimap, "CENTER", dx * scaleX, dy * scaleY)
            pin:Show()
        end
    end
    HideFrom(self, n + 1)
end

local function NewLayer(opts)
    local self = setmetatable({ opts = opts, pins = {}, near = {}, count = 0 }, Layer)
    self.frame = CreateFrame("Frame")
    self.frame.since = 0
    local function Live()
        local live = self.count > 0 and (self.moving or C_CVar.GetCVarBool("rotateMinimap"))
        self.frame:SetScript("OnUpdate", live and function(f, e)
            f.since = f.since + e
            if f.since >= 0.05 then f.since = 0; self:Place() end
        end or nil)
    end
    self.Live = Live
    self.frame:SetScript("OnEvent", function(_, event)
        if event ~= "MINIMAP_UPDATE_ZOOM" then self.moving = event == "PLAYER_STARTED_MOVING" end
        self:Place()
        Live()
    end)
    return self
end

function Layer:Set(mapID, spots, count)
    self.spots, self.count, self.at = spots, 0, nil
    if mapID and spots and count > 0 and Fit(self, mapID) then self.count = count end
    for _, pin in ipairs(self.pins) do pin.spot = nil end
    for _, e in ipairs({ "PLAYER_STARTED_MOVING", "PLAYER_STOPPED_MOVING", "MINIMAP_UPDATE_ZOOM" }) do
        if self.count > 0 then self.frame:RegisterEvent(e) else self.frame:UnregisterEvent(e) end
    end
    if self.count > 0 then self.moving = IsPlayerMoving(); self:Place() else HideFrom(self, 1) end
    self.Live()
end

--- Minimap pins for other features (the town map): NewLayer({ max, new, paint, xy }).
module.MinimapLayer = NewLayer

-------------------------------------------------------------------------------
--  Tooltips, pins, Zone Timer
-------------------------------------------------------------------------------
local LEAVING_SOON = 30
local DOCKED, LEAVING, SAILING = { 1, 0.82, 0 }, { 1, 0.25, 0.25 }, { 0.25, 1, 0.25 }
local CITY_ZONES = { [1454] = 1411, [1456] = 1412, [1457] = 1438, [1458] = 1420 }

local function Colour(kind, seconds)
    if kind == ARRIVAL then return SAILING end
    return seconds > LEAVING_SOON and DOCKED or LEAVING
end
local function MS(seconds)
    local r = math.ceil(seconds)
    return math.floor(r / 60), r % 60
end
local function Countdown(seconds, kind)
    return ((kind == ARRIVAL) and "Arrives in %d:%02d" or "Departs in %d:%02d"):format(MS(seconds))
end
local function Tinted(text, c) return ("|cff%02x%02x%02x%s|r"):format(c[1] * 255, c[2] * 255, c[3] * 255, text) end

local function TimeText(key, now)
    local seconds, kind = Times.Next(key, now)
    if seconds then return Countdown(seconds, kind), Colour(kind, seconds) end
    local named = Times.RouteAt(key) ~= nil
    local text = kind == "stale" and "Server clock changed; time it again." or kind == "expired" and "Estimate out of date" or "Not timed yet"
    return text, { 0.6, 0.6, 0.6 }, named and "Ride it once to time it." or "Time it from its minimap pin at the dock."
end

local function ShowTip(pin)
    local now = GetServerTime()
    GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
    local name = Times.RouteAt(pin.key)
    if name then
        GameTooltip:SetText(name, 0.25, 0.75, 1)
        local any
        for index, dock in ipairs(Routes[name].docks) do
            local zone = Data[dock.stop] and C_Map.GetMapInfo(Data[dock.stop].map)
            GameTooltip:AddLine(zone and (dock.place .. ", " .. zone.name) or dock.place, 1, 1, 1)
            local seconds, kind = Times.Dock(name, index, now)
            if seconds then
                any = true
                local c = Colour(kind, seconds)
                GameTooltip:AddDoubleLine(kind == ARRIVAL and "Arrival:" or "Departure:", ("%dm %02ds"):format(MS(seconds)), 1, 0.82, 0, c[1], c[2], c[3])
            else
                GameTooltip:AddLine(kind == "stale" and "Server clock changed; time it again." or "Not timed yet", 0.6, 0.6, 0.6)
            end
        end
        if not any then GameTooltip:AddLine("Ride it once to time it.", 0.6, 0.6, 0.6) end
    else
        local routes = Data[pin.key].routes
        GameTooltip:SetText(routes[1], 1, 1, 1)
        for i = 2, #routes do GameTooltip:AddLine(routes[i], 1, 1, 1) end
        local text, c = TimeText(pin.key, now)
        GameTooltip:AddLine(text, c[1], c[2], c[3])
    end
    GameTooltip:AddLine("Left-click when it arrives, right-click when it leaves.", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local layer, hud
local spots, zoneSpots = {}, {}

local function NewPin()
    local pin = CreateFrame("Button", nil, Minimap)
    pin:SetSize(16, 16)
    pin.icon = pin:CreateTexture(nil, "ARTWORK")
    pin.icon:SetAllPoints()
    pin:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    pin:SetScript("OnClick", function(self, button)
        Times.Record(self.key, button == "LeftButton" and ARRIVAL or DEPARTURE, GetServerTime())
        ShowTip(self)
    end)
    pin:SetScript("OnEnter", function(self)
        ShowTip(self)
        self.since = 0
        self:SetScript("OnUpdate", function(s, e) s.since = s.since + e; if s.since >= 1 then s.since = 0; ShowTip(s) end end)
    end)
    pin:SetScript("OnLeave", function(self) self:SetScript("OnUpdate", nil); GameTooltip:Hide() end)
    return pin
end

local function PaintPin(pin, list, i)
    pin.key = list[i]
    local route = Data[pin.key].routes[1] or ""
    pin.icon:SetAtlas(route:find("^Zeppelin") and "vehicle-air-horde" or "flightmasterferry")
end

local function HudBuild()
    if hud then return hud end
    hud = CreateFrame("Frame", "CludesUIShipTimer", UIParent)
    CludesUI.Kit.Panel(hud, 0.7)
    hud.names = hud:CreateFontString(nil, "OVERLAY")
    hud.names:SetPoint("TOPLEFT", 8, -6)
    hud.names:SetJustifyH("LEFT")
    hud.names:SetTextColor(1, 0.82, 0)
    hud.times = hud:CreateFontString(nil, "OVERLAY")
    hud.times:SetPoint("TOPRIGHT", -8, -6)
    hud.times:SetJustifyH("RIGHT")
    hud.since = 0
    hud:SetScript("OnUpdate", function(self, e)
        self.since = self.since + e
        if self.since >= 1 then self.since = 0; module.TransportDrawZone() end
    end)
    hud:Hide()
    return hud
end

function module.TransportDrawZone()
    if not hud then return end
    local show = Enabled() and Get("zone") and (zoneSpots[1] ~= nil or CludesUI._unlockActive)
    if not show then hud:Hide() return end
    local names, times, now = {}, {}, GetServerTime()
    for i, key in ipairs(zoneSpots) do
        names[i] = table.concat(Data[key].routes, " / ")
        local text, c = TimeText(key, now)
        times[i] = Tinted(text, c)
    end
    if #names == 0 then names[1], times[1] = "Boat to Booty Bay", Tinted("Departs in 0:42", DOCKED) end
    local size = Get("size")
    CludesUI.Kit.Font(hud.names, size, "essentials")
    CludesUI.Kit.Font(hud.times, size, "essentials")
    hud.names:SetText(table.concat(names, "\n"))
    hud.times:SetText(table.concat(times, "\n"))
    hud:SetSize(hud.names:GetStringWidth() + 12 + hud.times:GetStringWidth() + 16, hud.names:GetStringHeight() + 12)
    hud:Show()
end

local function Refresh()
    wipe(spots); wipe(zoneSpots)
    local map = Enabled() and C_Map.GetBestMapForUnit("player")
    if map then
        local side = UnitFactionGroup("player") == "Horde" and "H" or "A"
        local same = SameMap(map)
        local zone = CITY_ZONES[same] or same
        for key, stop in pairs(Data) do
            if stop.map == same and stop.side:find(side, 1, true) then
                if not stop.mapX then
                    local _, pos = C_Map.GetMapPosFromWorldPos(stop.continent, CreateVector2D(stop.x, stop.y), map)
                    if pos then stop.mapX, stop.mapY = pos:GetXY() end
                end
                if stop.mapX then spots[#spots + 1] = key end
            end
            if stop.map == zone and stop.side:find(side, 1, true) then zoneSpots[#zoneSpots + 1] = key end
        end
        table.sort(zoneSpots)
    end
    RideWatch(map)
    CallsWatch(map)
    module.TransportDrawZone()
    if not layer and #spots == 0 then return end
    layer = layer or NewLayer({ max = 3, new = NewPin, paint = PaintPin, xy = function(list, i) return Data[list[i]].mapX, Data[list[i]].mapY end })
    layer:Set(map, spots, #spots)
end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then Times.Prune(GetServerTime()) end
    Refresh()
end)

--- For other maps (the world map's docks): "Departs in 1:20" and its colour for a stop key.
function module.TransportTimeText(key) return TimeText(key, GetServerTime()) end

local function Apply()
    ev:UnregisterAllEvents()
    if Enabled() then
        for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS" }) do ev:RegisterEvent(e) end
        if IsLoggedIn() then Times.Prune(GetServerTime()) end
        if Get("zone") then HudBuild() end
        if hud and not CludesUI._unlockActive then F.Place(hud) end
    end
    ShareApply()
    Refresh()
end

CludesUI._Transport = { Get = Get, Cfg = F.Cfg, Apply = Apply }

F.Start(Apply, {
    key = "CUI_ShipTimer", label = "Boat and Zeppelin Timer", order = 754,
    shown = function() return Enabled() and Get("zone") end,
    frame = function(build) if build then HudBuild(); module.TransportDrawZone() end; return hud end,
    size = function() return 220, 40 end,
    noAnchorTarget = true, noSizeMatchTarget = true,
})
