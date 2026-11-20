if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_Minimap_Info.lua - the clock, location and coordinates text.
--
--  Their font, colours, where they sit around the map, and the functions that
--  write them. The clock ticks every 10 seconds and the coordinates every half
--  second (CUI_Minimap_Apply.lua runs the tickers); each writes its text only
--  when the shown value changed. The location follows the zone events.
--
--  Reads the earlier Minimap files through ns._internals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._internals
-- CludesUIMinimap.lua or an earlier CUI_Minimap_*.lua file failed to load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local SKIN, ACCENT = Inner.EBS, Inner.EG
local floor = math.floor

-- The text frames, made by CUI_Minimap_Apply.lua: each file keeps its own
-- copy, and Inner.Set<Name> hands a new value to every copy.
local coordFrame, clockFrame, locationFrame, locationBg
Inner.coordFrameSetters[#Inner.coordFrameSetters + 1] = function(v)
    coordFrame = v
end
Inner.clockFrameSetters[#Inner.clockFrameSetters + 1] = function(v)
    clockFrame = v
end
Inner.locationFrameSetters[#Inner.locationFrameSetters + 1] = function(v)
    locationFrame = v
end
Inner.locationBgSetters[#Inner.locationBgSetters + 1] = function(v)
    locationBg = v
end

local function Profile()
    return SKIN.db and SKIN.db.profile.minimap
end

local function ApplyMinimapFont(text, size)
    CludesUI.ApplyModuleFont(text, nil, size, "minimap")
end

-- The colour of the descriptive bits (the clock's AM/PM, "fps"/"ms"): the
-- accent, the chosen colour, or white; the values themselves stay white.
-- Returns r, g, b and the hex.
local function GetDescColor(mp)
    local red, green, blue = 1, 1, 1
    if mp and mp.fpsUseAccent then
        red, green, blue = ACCENT.r, ACCENT.g, ACCENT.b
    elseif mp and mp.fpsColor then
        local c = mp.fpsColor
        red, green, blue = c.r or 1, c.g or 1, c.b or 1
    end
    local hex = format("%02x%02x%02x", floor(red * 255 + 0.5), floor(green * 255 + 0.5), floor(blue * 255 + 0.5))
    return red, green, blue, hex
end

-------------------------------------------------------------------------------
--  Clock
-------------------------------------------------------------------------------
-- The game's clock settings, read once and again on CVAR_UPDATE.
local use24, useLocal
local function RefreshClockCVars()
    use24 = GetCVar("timeMgrUseMilitaryTime") == "1"
    useLocal = GetCVar("timeMgrUseLocalTime") == "1"
end

-- Like the game's clock: 24 hour padded (01:04), 12 hour not (1:04 PM). The
-- AM/PM takes the descriptive colour only when that option is on.
local shownClock -- the clock text as last written
local function UpdateClock()
    if not clockFrame then
        return
    end
    if use24 == nil then
        RefreshClockCVars()
    end
    local hour, minute
    if useLocal then
        local now = date("*t")
        hour, minute = now.hour, now.min
    else
        hour, minute = GetGameTime()
    end
    local text
    if use24 then
        text = format("%02d:%02d", hour, minute)
    else
        local suffix = hour >= 12 and "PM" or "AM"
        hour = hour % 12
        if hour == 0 then
            hour = 12
        end
        local mp = Profile()
        if mp and mp.fpsColorClockAMPM then
            local _, _, _, hex = GetDescColor(mp)
            text = format("%d:%02d |cff%s%s|r", hour, minute, hex, suffix)
        else
            text = format("%d:%02d %s", hour, minute, suffix)
        end
    end
    -- The frame is reused when the clock is hidden and shown again, so its
    -- text is compared, not just the last string written.
    if text == shownClock and clockFrame:GetText() == text then
        return
    end
    shownClock = text
    clockFrame:SetText(text)
end

-------------------------------------------------------------------------------
--  Where the texts go
-------------------------------------------------------------------------------
-- Coordinates' mode and place. Exports made before those were dropdowns
-- carry only coordsBelow (true = always shown below the map, else on hover
-- at the top left).
local function GetCoordsModePos(mp)
    if not mp then
        return "always", "topLeft"
    end
    local mode = mp.coordsMode or "always"
    local place = mp.coordsPosition or (mp.coordsBelow and "belowMap") or "topLeft"
    return mode, place
end

-- The clock's and the location's modes. Older data had clockInside /
-- zoneInside (default on / off) and the removed Zone / Clock checkboxes
-- (showClock == false or hideZoneText == true meant hidden).
local function GetElementModes(mp)
    if not mp then
        return "inside", "inside"
    end
    local clockMode = mp.clockMode
    if clockMode == nil then
        if mp.showClock == false then
            clockMode = "none"
        else
            clockMode = mp.clockInside == false and "edge" or "inside"
        end
    end
    local locationMode = mp.locationMode
    if locationMode == nil then
        if mp.hideZoneText == true then
            locationMode = "none"
        else
            locationMode = mp.zoneInside and "inside" or "edge"
        end
    end
    return clockMode, locationMode
end

-- Place -> { the text's point, the map's point, x, y } (inside the map).
-- Shared by the coordinates, the clock and the location.
local MAP_POS_ANCHORS = {
    belowMap = { "TOP", "BOTTOM", 0, -5 },
    aboveMap = { "BOTTOM", "TOP", 0, 5 },
    topLeft = { "TOPLEFT", "TOPLEFT", 4, -4 },
    top = { "TOP", "TOP", 0, -4 },
    topRight = { "TOPRIGHT", "TOPRIGHT", -4, -4 },
    left = { "LEFT", "LEFT", 4, 0 },
    right = { "RIGHT", "RIGHT", -4, 0 },
    bottomLeft = { "BOTTOMLEFT", "BOTTOMLEFT", 4, 4 },
    bottom = { "BOTTOM", "BOTTOM", 0, 4 },
    bottomRight = { "BOTTOMRIGHT", "BOTTOMRIGHT", -4, 4 },
}

-- An inside offset under the WoW Forever look's Forever Square: its rim and
-- dark line cover the map's outer 3px and the inner shadow reaches 5px
-- (FOREVER_HEAVY.band and .shade at the window scale, less the rim's
-- EBS.FV_SQUARE_OUT outside the map), so on each axis it is inset on, a text
-- steps 2px further in (6px from the edge). Above Map rises over the title
-- bar while it shows; Below Map and every other look keep their offsets, and
-- Blizzard Style's slim square keeps the 4px (its shadow ends at the edge).
-- place: a MAP_POS_ANCHORS key. An EBS field.
function SKIN._FvInsideXY(place, x, y)
    if not SKIN._fvSquare or place == "belowMap" then
        return x, y
    end
    if place == "aboveMap" then
        if SKIN._fvTitleOn then
            y = y + SKIN._SqTitle() - SKIN._SqOut()
        end
        return x, y
    end
    if SKIN._sqSlim then
        return x, y
    end
    if x ~= 0 then
        x = x + (x > 0 and 2 or -2)
    end
    if y ~= 0 then
        y = y + (y > 0 and 2 or -2)
    end
    return x, y
end

-- Where the clock or location box goes. Inside keeps the 4px inset (more
-- under Forever Square). On the edge the box straddles the border: 7px out
-- on squares, 3px in on circles (the round mask curves away from the frame's
-- corner). Above and Below Map float outside either way.
local function ResolveElementAnchor(place, style, isCircle)
    local a = MAP_POS_ANCHORS[place] or MAP_POS_ANCHORS.top
    local x, y = a[3], a[4]
    if style == "edge" and place ~= "belowMap" and place ~= "aboveMap" then
        local function Edge(v)
            if v == 0 then
                return 0
            end
            if isCircle then
                return v > 0 and 3 or -3
            end
            return v > 0 and -7 or 7
        end
        x, y = Edge(x), Edge(y)
    else
        x, y = SKIN._FvInsideXY(place, x, y)
    end
    return a[1], a[2], x, y
end

-------------------------------------------------------------------------------
--  Coordinates
-------------------------------------------------------------------------------
local precision, pattern -- the format for the current precision
local function UpdateCoords()
    if not coordFrame then
        return
    end
    local mapID = C_Map.GetBestMapForUnit("player")
    local spot = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
    local text = ""
    if spot then
        local x, y = spot:GetXY()
        local mp = Profile()
        local wanted = mp and mp.coordPrecision or 1
        if wanted ~= precision then
            precision = wanted
            pattern = format("%%.%df, %%.%df", wanted, wanted)
        end
        text = format(pattern, x * 100, y * 100)
    end
    -- Twice a second: standing still writes nothing.
    if coordFrame:GetText() ~= text then
        coordFrame:SetText(text)
    end
end

-------------------------------------------------------------------------------
--  Location
-------------------------------------------------------------------------------
-- The zone's PvP state as a colour: friendly green, hostile / arena / combat
-- red, sanctuary blue, contested or unknown yellow. The Info Bar's Location
-- block uses the same colours.
local function GetZoneReactionColor()
    local pvp = C_PvP and C_PvP.GetZonePVPInfo and C_PvP.GetZonePVPInfo()
    if pvp == "friendly" then
        return 0.05, 0.85, 0.03
    elseif pvp == "sanctuary" then
        return 0.035, 0.58, 0.84
    elseif pvp == "arena" or pvp == "hostile" or pvp == "combat" then
        return 0.84, 0.03, 0.03
    end
    return 0.9, 0.85, 0.05
end

local shownLocation
local function UpdateLocation()
    if not locationFrame or InCombatLockdown() then
        return
    end
    -- The colour first: a setting change or a new ruleset repaints the same name.
    local mp = Profile()
    if mp and mp.zoneReactiveColor then
        local red, green, blue = GetZoneReactionColor()
        locationFrame:SetTextColor(red, green, blue, 0.9)
    else
        locationFrame:SetTextColor(1, 1, 1, 0.9)
    end
    local text = GetZoneText() or ""
    if mp and mp.zoneShowSubZone then
        local sub = GetSubZoneText()
        if sub and sub ~= "" then
            text = sub
        end
    end
    if text == shownLocation then
        return
    end
    shownLocation = text
    locationFrame:SetText(text)
    if locationBg then
        locationBg:SetSize((locationFrame:GetStringWidth() or 0) + 20, 18)
    end
end

Inner.ApplyMinimapFont, Inner.GetCoordsModePos = ApplyMinimapFont, GetCoordsModePos
Inner.GetDescColor, Inner.GetElementModes = GetDescColor, GetElementModes
Inner.MAP_POS_ANCHORS, Inner.RefreshClockCVars = MAP_POS_ANCHORS, RefreshClockCVars
Inner.ResolveElementAnchor, Inner.UpdateClock = ResolveElementAnchor, UpdateClock
Inner.UpdateCoords, Inner.UpdateLocation = UpdateCoords, UpdateLocation
Inner.broken = false
