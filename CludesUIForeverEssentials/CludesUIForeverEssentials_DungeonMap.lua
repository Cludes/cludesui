if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_DungeonMap.lua  (WoW Forever only)
--  Dungeon Map: inside a WoW Forever dungeon, a small window with that
--  dungeon's map and its route. The bosses are numbered in kill order and
--  joined by a line; the next boss is ringed, ones you have killed this run
--  are dimmed, and the map turns to the next boss's floor. A kill moves the
--  route on by itself (the game's encounter end, or the boss dying).
--    /cdmap   shows or hides it (outside a dungeon: the last one you were in).
--  Maps, pins and kill order come from the Dungeon Journal (Journal.lua,
--  JournalData.lua).
--
--  Where you are: the maps are pictures with pins, not game coordinates.
--  Where the game gives your position inside a dungeon (UnitPosition), the
--  map learns how its picture lines up with the world from real readings:
--  where you stand on entering (the entrance pin) and at each boss kill
--  (that boss's pin). Each picture axis is a straight fit of one world axis
--  (north-up maps: across from west, down from north), saved per dungeon
--  floor, so later runs line up from the start. Two readings on a floor are
--  enough; the fit is trusted only while its across and down scales keep
--  the picture's 3:2 shape and the readings sit within FIT_YARDS of it.
--  Then the map shows you, a line to the next boss, and (where the game
--  gives your facing) an arrow and the yards to go. Inside dungeons the game
--  hides your world position (UnitPosition), so the readings then use your
--  place on the game's own dungeon map (C_Map.GetPlayerMapPosition), fitted
--  the same way, per floor and per game map. Where both are hidden, the
--  footer says so and the route works as before.
-------------------------------------------------------------------------------
local CUI = CludesUI
if not (CUI and CUI.IS_FOREVER) then return end
local _, module = ...

local F = module.Feature("dungeonMap", { enabled = true, autoShow = true }, { point = "RIGHT", relPoint = "RIGHT", x = -40, y = 80 })
local Get, On, Cfg = F.Get, F.Enabled, F.Cfg
local J = module.Journal

local MAP_W = 340
local MAP_H = math.floor(MAP_W * 2 / 3)
local PAD = 8
local FOOT_H = 24
local WIN_W = MAP_W + PAD * 2
local WIN_H = CUI.Kit.HEADER_H + PAD + MAP_H + FOOT_H + PAD
local PIN, PIN_SMALL, PIN_NEXT = 20, 14, 26
local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local TAG_SHORT = { rare = "R", optional = "O", quest = "Q", chest = "C" }

local Pal = CUI.Kit.Palette
local window, canvas, picture, floorBar, floorName, footText
local pins, lines = {}, {}
local dungeon, map -- the dungeon on show and its map record
local route = {} -- { boss, number, floor, x, y } in kill order
local killed = {} -- npc id -> true, this run
local floor -- the floor on show
local manualFloor = false -- a < > pick holds until the next kill
local autoShown = false -- opened by entering a dungeon (leaving closes it again)
local FIT_YARDS = 40 -- the furthest a reading may sit from the fit
local FIT_MAP = 0.06 -- the same, for readings on the game's map (a share of its width)
local MAX_READINGS = 12 -- per floor, oldest dropped
local youDot, youLine, arrow, yardsText, ticker
local Fit, DrawYou, PositionShown -- below, used by Draw
local fits = {} -- floor -> fit, for the dungeon on show (nil: not worked out yet)

-------------------------------------------------------------------------------
--  Route
-------------------------------------------------------------------------------
local function BossTag(boss)
    return boss.rare and "rare" or boss.optional and "optional" or boss.quest and "quest" or boss.chest and "chest" or nil
end
local function BossKey(boss) return boss.npc or (boss.chest and -boss.chest) or nil end

local function BuildRoute()
    wipe(route)
    if not (dungeon and map) then return end
    local number = 0
    for _, wing in ipairs(dungeon.wings or {}) do
        for _, boss in ipairs(wing.bosses or {}) do
            local key = BossKey(boss)
            local spot = key and map.pins and map.pins[key]
            if spot and not boss.trash then
                local tag = BossTag(boss)
                local entry = { boss = boss, tag = tag, floor = spot[1], x = spot[2], y = spot[3] }
                if not tag then
                    number = number + 1
                    entry.number = number
                end
                route[#route + 1] = entry
            end
        end
    end
end

local function NextStop()
    for _, entry in ipairs(route) do
        if entry.number and not killed[entry.boss.npc] then return entry end
    end
end

local function RouteCount()
    local done, total = 0, 0
    for _, entry in ipairs(route) do
        if entry.number then
            total = total + 1
            if killed[entry.boss.npc] then done = done + 1 end
        end
    end
    return done, total
end

local function FloorImage(n)
    local image = map.images and map.images[n]
    if not image and map.image then image = n > 1 and map.image .. n or map.image end
    return image
end
local function FloorName(n) return map.names and map.names[n] or ("Floor %d"):format(n) end

-------------------------------------------------------------------------------
--  Drawing
-------------------------------------------------------------------------------
local function Round(frame, texture)
    local mask = frame:CreateMaskTexture()
    mask:SetAllPoints(texture)
    mask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    texture:AddMaskTexture(mask)
end

local function PinEnter(pin)
    local entry = pin.entry
    if not entry then return end
    GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
    local title = entry.number and (entry.number .. ". " .. entry.boss.name) or entry.boss.name
    GameTooltip:AddLine(title, 1, 1, 1)
    if entry.tag then GameTooltip:AddLine(CUI.L(({ rare = "Rare", optional = "Optional", quest = "Quest boss", chest = "Chest" })[entry.tag]), Pal.muted[1], Pal.muted[2], Pal.muted[3]) end
    if killed[entry.boss.npc] then GameTooltip:AddLine(CUI.L("Killed this run"), Pal.green[1], Pal.green[2], Pal.green[3]) end
    if module.BossKills then module.BossKills.AddToTooltip(GameTooltip, entry.boss) end
    GameTooltip:Show()
end

local function NewPin()
    local pin = CreateFrame("Frame", nil, canvas)
    pin:SetFrameLevel(canvas:GetFrameLevel() + 5)
    pin.ring = pin:CreateTexture(nil, "BORDER")
    pin.ring:SetPoint("CENTER")
    Round(pin, pin.ring)
    pin.plate = pin:CreateTexture(nil, "ARTWORK")
    pin.plate:SetColorTexture(0.06, 0.07, 0.09, 1)
    Round(pin, pin.plate)
    pin.text = pin:CreateFontString(nil, "OVERLAY")
    CUI.Kit.Font(pin.text, 11, "essentials")
    pin.text:SetPoint("CENTER")
    pin:SetScript("OnEnter", PinEnter)
    pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return pin
end

local function At(frame, x, y)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", canvas, "TOPLEFT", x * MAP_W, -y * MAP_H)
end

local function Line(n)
    local line = lines[n]
    if not line then
        line = canvas:CreateLine(nil, "ARTWORK")
        line:SetThickness(2)
        lines[n] = line
    end
    return line
end

local function Draw()
    if not (window and picture and window:IsShown()) then return end
    for _, pin in ipairs(pins) do pin:Hide() end
    for _, line in ipairs(lines) do line:Hide() end
    if not (dungeon and map) then
        window.title:SetText(CUI.L("Dungeon Map"))
        picture:SetTexture(nil)
        footText:SetText(CUI.L("Enter a dungeon to see its map and route."))
        floorBar:Hide()
        return
    end
    local nextStop = NextStop()
    if not manualFloor then floor = nextStop and nextStop.floor or floor or (map.entrance and map.entrance[1]) or 1 end
    window.title:SetText(dungeon.name)
    picture:SetTexture(FloorImage(floor), nil, nil, "TRILINEAR")
    picture:SetTexCoord(0, 1, 0, map.imageBottom or (683 / 1024))
    local accent = { CUI.Kit.Accent() }

    -- The route line: entrance to the first boss, then boss to boss, on this floor.
    local used, prev = 0, nil
    if map.entrance and map.entrance[1] == floor then prev = { x = map.entrance[2], y = map.entrance[3], done = true } end
    for _, entry in ipairs(route) do
        if entry.number then
            local here = entry.floor == floor
            if here and prev then
                used = used + 1
                local line = Line(used)
                line:SetStartPoint("TOPLEFT", canvas, prev.x * MAP_W, -prev.y * MAP_H)
                line:SetEndPoint("TOPLEFT", canvas, entry.x * MAP_W, -entry.y * MAP_H)
                local walked = prev.done and killed[entry.boss.npc]
                line:SetColorTexture(accent[1], accent[2], accent[3], walked and 0.25 or 0.8)
                line:Show()
            end
            prev = here and { x = entry.x, y = entry.y, done = killed[entry.boss.npc] } or nil
        end
    end

    -- The pins: route bosses numbered, the rest (rares, chests) small and grey.
    local shown = 0
    for _, entry in ipairs(route) do
        if entry.floor == floor then
            shown = shown + 1
            local pin = pins[shown] or NewPin()
            pins[shown] = pin
            pin.entry = entry
            local isNext = entry == nextStop
            local size = isNext and PIN_NEXT or (entry.number and PIN or PIN_SMALL)
            pin:SetSize(size, size)
            pin.ring:SetSize(size + 4, size + 4)
            pin.plate:SetSize(size, size)
            pin.plate:SetPoint("CENTER")
            if entry.number then
                pin.ring:SetColorTexture(accent[1], accent[2], accent[3], 1)
                pin.text:SetText(entry.number)
            else
                pin.ring:SetColorTexture(0.6, 0.65, 0.7, 1)
                pin.text:SetText(TAG_SHORT[entry.tag] or "")
            end
            if isNext then pin.plate:SetColorTexture(accent[1] * 0.35, accent[2] * 0.35, accent[3] * 0.35, 1)
            else pin.plate:SetColorTexture(0.06, 0.07, 0.09, 1) end
            pin:SetAlpha(killed[entry.boss.npc] and 0.35 or 1)
            At(pin, entry.x, entry.y)
            pin:Show()
        end
    end

    local done, total = RouteCount()
    if nextStop then
        local away = nextStop.floor ~= floor and ("  |cffa3adb5(" .. FloorName(nextStop.floor) .. ")|r") or ""
        footText:SetText(("%s %d. %s%s  |cffa3adb5%d/%d|r"):format(CUI.L("Next:"), nextStop.number, nextStop.boss.name, away, done, total))
    else
        footText:SetText(("%s  |cffa3adb5%d/%d|r"):format(CUI.L("Every boss down."), done, total))
    end
    local floors = map.floors or 1
    floorBar:SetShown(floors > 1)
    floorName:SetText(FloorName(floor))
    DrawYou()
end

-------------------------------------------------------------------------------
--  Where you are
-------------------------------------------------------------------------------
local function Secret(v) return v ~= nil and issecretvalue and issecretvalue(v) end

-- Your position in the dungeon (world yards, x north, y west), or nil.
-- Where you are: world yards (x north, y west) and source "", or, where the
-- game hides those, your place on its dungeon map (x east, y south, 0 to 1)
-- and source "#<map id>". nil when both are hidden.
local function Position()
    local x, y = UnitPosition("player")
    if x ~= nil and not Secret(x) and not Secret(y) then return x, y, "" end
    local mapID = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not mapID or Secret(mapID) then return nil end
    local at = C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(mapID, "player")
    if not at or Secret(at) then return nil end
    local mx, my = at:GetXY()
    if mx == nil or Secret(mx) or Secret(my) or (mx == 0 and my == 0) then return nil end
    return mx, my, "#" .. mapID
end

local function Readings(floorNumber, create, source)
    if not dungeon then return nil end
    local all = create and Cfg() or F.Read()
    local byKey = all.readings
    if not byKey then
        if not create then return nil end
        byKey = {}
        all.readings = byKey
    end
    local key = dungeon.key .. (source or "")
    local mine = byKey[key]
    if not mine then
        if not create then return nil end
        mine = {}
        byKey[key] = mine
    end
    local list = mine[floorNumber]
    if not list and create then
        list = {}
        mine[floorNumber] = list
    end
    return list
end

-- A straight fit of picture across (u) on world y and down (v) on world x.
local function LineFit(list, wi, pi)
    local n, sw, sp, sww, swp = #list, 0, 0, 0, 0
    for _, r in ipairs(list) do
        local w, q = r[wi], r[pi]
        sw, sp, sww, swp = sw + w, sp + q, sww + w * w, swp + w * q
    end
    local d = n * sww - sw * sw
    if n < 2 or math.abs(d) < 1e-6 then return nil end
    local slope = (n * swp - sw * sp) / d
    return slope, (sp - slope * sw) / n
end

-- World readings: u from world y and v from world x, both falling (north up:
-- west is left, north is up), across 1.5 times down (the picture's 3:2).
-- Map readings: u from map x and v from map y, both rising, and the game's
-- map is 3:2 as well, so the two scales match.
function Fit(floorNumber, source)
    source = source or ""
    local key = floorNumber .. source
    if fits[key] ~= nil then return fits[key] or nil end
    local list = Readings(floorNumber, false, source)
    local onMap = source ~= ""
    local fit = false
    if list and #list >= 2 then
        local ui, vi = onMap and 1 or 2, onMap and 2 or 1
        local su, au = LineFit(list, ui, 3)
        local sv, av = LineFit(list, vi, 4)
        local sign = onMap and 1 or -1
        if su and sv and su * sign > 0 and sv * sign > 0 then
            local shape = sv / su
            local worst = 0
            for _, r in ipairs(list) do
                local du, dv = (su * r[ui] + au - r[3]) / su, (sv * r[vi] + av - r[4]) / sv
                worst = math.max(worst, math.sqrt(du * du + dv * dv))
            end
            local low, high, limit = 1.2, 1.8, FIT_YARDS
            if onMap then low, high, limit = 0.6, 1.6, FIT_MAP end
            if shape > low and shape < high and worst <= limit then
                fit = { su = su, au = au, sv = sv, av = av, onMap = onMap }
            end
        end
    end
    fits[key] = fit
    return fit or nil
end

local function Note(floorNumber, u, v)
    local x, y, source = Position()
    if not x then return end
    local list = Readings(floorNumber, true, source)
    list[#list + 1] = { x, y, u, v }
    while #list > MAX_READINGS do
        table.remove(list, 1)
    end
    fits[floorNumber .. source] = nil
end

local function ToPicture(fit, x, y)
    if fit.onMap then return fit.su * x + fit.au, fit.sv * y + fit.av end
    return fit.su * y + fit.au, fit.sv * x + fit.av
end
local function ToWorld(fit, u, v)
    if fit.onMap then return (u - fit.au) / fit.su, (v - fit.av) / fit.sv end
    return (v - fit.av) / fit.sv, (u - fit.au) / fit.su
end

-- From you to a point, as world yards north (dx) and west (dy); nil where a
-- map reading has no size for its map.
local function Toward(source, x, y, tx, ty)
    if source == "" then return tx - x, ty - y end
    local mapID = tonumber(source:sub(2))
    local w, h
    if C_Map.GetMapWorldSize then w, h = C_Map.GetMapWorldSize(mapID) end
    if not w or Secret(w) or Secret(h) or w <= 0 or h <= 0 then return nil end
    return -(ty - y) * h, -(tx - x) * w
end

-- The you dot, the line on to the next boss and the arrow, kept current.
function DrawYou()
    if not (window and window:IsShown() and youDot) then return end
    local x, y, source = Position()
    local fit = x and dungeon and Fit(floor or 1, source)
    local nextStop = fit and NextStop()
    if not fit then
        youDot:Hide()
        youLine:Hide()
        arrow:Hide()
        -- While the map learns how it lines up (it needs the entrance and a
        -- kill) the footer says so. Where the game hides your position, as
        -- in every Forever dungeon, it says nothing: there is nothing to wait for.
        yardsText:SetText((dungeon and x) and CUI.L("learning map") or "")
        return
    end
    local u, v = ToPicture(fit, x, y)
    local inside = u >= 0 and u <= 1 and v >= 0 and v <= 1
    youDot:SetShown(inside)
    if inside then At(youDot, u, v) end
    if nextStop and nextStop.floor == floor and inside then
        youLine:SetStartPoint("TOPLEFT", canvas, u * MAP_W, -v * MAP_H)
        youLine:SetEndPoint("TOPLEFT", canvas, nextStop.x * MAP_W, -nextStop.y * MAP_H)
        youLine:Show()
    else
        youLine:Hide()
    end
    if not (nextStop and nextStop.floor == floor) then
        arrow:Hide()
        yardsText:SetText("")
        return
    end
    local tx, ty = ToWorld(fit, nextStop.x, nextStop.y)
    local dx, dy = Toward(source, x, y, tx, ty)
    if not dx then
        arrow:Hide()
        yardsText:SetText("")
        return
    end
    yardsText:SetText(("%d yd"):format(math.sqrt(dx * dx + dy * dy)))
    local facing = GetPlayerFacing and GetPlayerFacing()
    if facing and not Secret(facing) then
        arrow:SetRotation(math.atan2(dy, dx) - facing + math.pi)
        arrow:Show()
    else
        arrow:Hide()
    end
end

-- Whether the game gives your position here: true, false, or nil outside.
function PositionShown()
    if not dungeon then return nil end
    return Position() ~= nil
end

-------------------------------------------------------------------------------
--  Window
-------------------------------------------------------------------------------
local function StepFloor(by)
    local floors = map and map.floors or 1
    floor = ((floor or 1) - 1 + by) % floors + 1
    manualFloor = true
    Draw()
end

local function Build()
    if window then return window end
    window = CUI.Kit.Window("CludesUIDungeonMap", WIN_W, WIN_H, CUI.L("Dungeon Map"), { key = "essentials", special = false })
    window:SetFrameStrata("MEDIUM")
    window:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint(1)
        Cfg().pos = { point = point, relPoint = relPoint, x = x, y = y }
    end)
    F.Place(window)
    canvas = CreateFrame("Frame", nil, window)
    canvas:SetSize(MAP_W, MAP_H)
    canvas:SetPoint("TOPLEFT", PAD, -(CUI.Kit.HEADER_H + PAD))
    canvas:SetClipsChildren(true)
    CUI.Kit.Border(canvas, 0, 0, 0, 1)
    picture = canvas:CreateTexture(nil, "BACKGROUND")
    picture:SetAllPoints()
    footText = window:CreateFontString(nil, "OVERLAY")
    CUI.Kit.Font(footText, CUI.Kit.TEXT_SIZE, "essentials")
    footText:SetPoint("BOTTOMLEFT", PAD + 2, PAD + 4)
    footText:SetPoint("RIGHT", window, "RIGHT", -PAD, 0)
    footText:SetJustifyH("LEFT")
    footText:SetWordWrap(false)
    footText:SetTextColor(Pal.text[1], Pal.text[2], Pal.text[3])
    -- Floors: < name > in the title bar, for dungeons with more than one.
    floorBar = CreateFrame("Frame", nil, window)
    floorBar:SetSize(170, 20)
    floorBar:SetPoint("TOPRIGHT", window, "TOPRIGHT", -28, -4)
    local down = CUI.Kit.Button(floorBar, "<", 20, 18, function() StepFloor(-1) end, { key = "essentials" })
    down:SetPoint("LEFT", 0, 0)
    local up = CUI.Kit.Button(floorBar, ">", 20, 18, function() StepFloor(1) end, { key = "essentials" })
    up:SetPoint("RIGHT", 0, 0)
    floorName = floorBar:CreateFontString(nil, "OVERLAY")
    CUI.Kit.Font(floorName, CUI.Kit.SMALL_SIZE, "essentials")
    floorName:SetPoint("LEFT", down, "RIGHT", 4, 0)
    floorName:SetPoint("RIGHT", up, "LEFT", -4, 0)
    floorName:SetWordWrap(false)
    -- Quests: hover for the dungeon's quests, click to share yours (DungeonQuests.lua).
    local questsButton = CUI.Kit.Button(window, CUI.L("Quests"), 54, 18, function()
        if module.DungeonQuests and dungeon then module.DungeonQuests.ShareAll(dungeon) end
    end, { key = "essentials" })
    questsButton:SetPoint("RIGHT", floorBar, "LEFT", -6, 0)
    questsButton:HookScript("OnEnter", function(self)
        if not (module.DungeonQuests and dungeon) then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        module.DungeonQuests.FillTooltip(GameTooltip, dungeon)
        GameTooltip:Show()
    end)
    questsButton:HookScript("OnLeave", function() GameTooltip:Hide() end)
    window.questsButton = questsButton
    floorName:SetTextColor(Pal.muted[1], Pal.muted[2], Pal.muted[3])
    youLine = canvas:CreateLine(nil, "OVERLAY")
    youLine:SetThickness(2)
    youLine:SetColorTexture(1, 1, 1, 0.7)
    youDot = canvas:CreateTexture(nil, "OVERLAY", nil, 7)
    youDot:SetSize(10, 10)
    youDot:SetTexture("Interface\\AddOns\\CludesUI\\media\\white-square.png")
    youDot:SetVertexColor(1, 1, 1, 1)
    arrow = window:CreateTexture(nil, "OVERLAY")
    arrow:SetTexture("Interface\\AddOns\\CludesUI\\media\\icons\\cui-arrow-down3.png")
    arrow:SetSize(18, 18)
    arrow:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -PAD, PAD + 1)
    arrow:SetVertexColor(CUI.Kit.Accent())
    yardsText = window:CreateFontString(nil, "OVERLAY")
    CUI.Kit.Font(yardsText, CUI.Kit.SMALL_SIZE, "essentials")
    yardsText:SetPoint("RIGHT", arrow, "LEFT", -4, 0)
    yardsText:SetTextColor(Pal.muted[1], Pal.muted[2], Pal.muted[3])
    footText:SetPoint("RIGHT", window, "RIGHT", -(PAD + 80), 0)
    window:SetScript("OnShow", function()
        Draw()
        if not ticker then ticker = C_Timer.NewTicker(0.2, DrawYou) end
    end)
    window:SetScript("OnHide", function()
        if ticker then
            ticker:Cancel()
            ticker = nil
        end
    end)
    window:Hide()
    return window
end

-------------------------------------------------------------------------------
--  Where you are, and kills
-------------------------------------------------------------------------------
local function Detect()
    local inside, kind = IsInInstance()
    if not (inside and (kind == "party" or kind == "raid")) then return nil end
    local name, _, _, _, _, _, _, id = GetInstanceInfo()
    for _, d in ipairs(J and J.dungeons or {}) do
        if (d.instance and d.instance == id) or d.name == name then
            if J.Maps and J.Maps[d.key] then return d end
        end
    end
end

local function Enter(zonedIn)
    local found = Detect()
    if found and found ~= dungeon then
        -- A different dungeon: a new run.
        dungeon, map = found, J.Maps[found.key]
        wipe(killed)
        wipe(fits)
        floor, manualFloor = nil, false
        BuildRoute()
    end
    -- Zoning in puts you at the entrance: a reading of where it is.
    if found and zonedIn and map.entrance then
        local e = map.entrance
        C_Timer.After(1.5, function()
            if dungeon == found then
                Note(e[1], e[2], e[3])
                Draw()
            end
        end)
    end
    if found and Get("autoShow") and not (window and window:IsShown()) then
        Build():Show()
        autoShown = true
    elseif not found and autoShown and window then
        window:Hide()
        autoShown = false
    end
    Draw()
end

local function Killed(npc)
    if not (npc and dungeon) then return end
    for _, entry in ipairs(route) do
        if entry.boss.npc == npc and not killed[npc] then
            killed[npc] = true
            Note(entry.floor, entry.x, entry.y)
            manualFloor = false
            Draw()
            return
        end
    end
end

local function KilledEncounter(encounterID)
    if not dungeon then return end
    for _, entry in ipairs(route) do
        for _, id in ipairs(entry.boss.encounters or {}) do
            if id == encounterID and not killed[entry.boss.npc] then
                killed[entry.boss.npc] = true
                Note(entry.floor, entry.x, entry.y)
            end
        end
    end
    manualFloor = false
    Draw()
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, ...)
    if event == "ENCOUNTER_END" then
        local encounterID, _, _, _, success = ...
        if success == 1 then KilledEncounter(encounterID) end
    elseif event == "BOSS_KILL" then
        KilledEncounter((...))
    elseif event == "PLAYER_ENTERING_WORLD" then
        local login, reload = ...
        Enter(not (login or reload))
    else
        Enter()
    end
end)

local function Apply()
    events:UnregisterAllEvents()
    if not On() then
        if window then window:Hide() end
        return
    end
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "ENCOUNTER_END", "BOSS_KILL" }) do
        events:RegisterEvent(event)
    end
    Enter()
end

SLASH_CUIDUNGEONMAP1 = "/cdmap"
SlashCmdList.CUIDUNGEONMAP = function()
    if not On() then
        CUI.Print(CUI.L("Dungeon Map is off: turn it on under Forever Tools > Dungeons & Raids > Dungeon Journal."))
        return
    end
    local w = Build()
    autoShown = false
    w:SetShown(not w:IsShown())
end

F.Start(Apply, {
    key = "CUIFE_DungeonMap",
    label = "Dungeon Map",
    order = 60,
    frame = function(build)
        if build then return Build() end
        return window
    end,
    size = function() return WIN_W, WIN_H end,
})

CUI._DungeonMap = {
    Get = Get,
    Cfg = Cfg,
    Apply = Apply,
    Toggle = SlashCmdList.CUIDUNGEONMAP,
    -- For tests: the dungeon on show, its route and the next stop.
    State = function() return dungeon, route, NextStop(), killed end,
    Fit = function(n, source) return Fit(n or floor or 1, source) end,
    Map = function() return map, floor end,
    PositionShown = function() return PositionShown() end,
    DrawYou = function() DrawYou() end,
    You = function() return youDot, youLine, arrow, yardsText end,
    Enter = Enter,
    KilledEncounter = KilledEncounter,
    Killed = Killed,
}
