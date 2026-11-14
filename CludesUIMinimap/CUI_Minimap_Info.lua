if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_Minimap_Info.lua
--
--  The clock, coordinates and location text: font, colours, anchors and
--  their update functions.
--  Reads the earlier Minimap files through ns._internals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._internals
-- CludesUIMinimap.lua or an earlier CUI_Minimap_*.lua file failed to load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local SKIN, ACC = Inner.EBS, Inner.EG

-- Shared state: one copy per file. A write goes through the Set<Name>
-- function of ns._internals, which hands the value to every copy.
local coordFrame
Inner.coordFrameSetters[#Inner.coordFrameSetters + 1] = function(val)
    coordFrame = val
end
local clockFrame
Inner.clockFrameSetters[#Inner.clockFrameSetters + 1] = function(val)
    clockFrame = val
end
local locationFrame
Inner.locationFrameSetters[#Inner.locationFrameSetters + 1] = function(val)
    locationFrame = val
end
local locationBg
Inner.locationBgSetters[#Inner.locationBgSetters + 1] = function(val)
    locationBg = val
end

local function ApplyMinimapFont(fontStr, size)
    CludesUI.ApplyModuleFont(fontStr, nil, size, "minimap")
end

-- Description-text colour (clock AM/PM, the "fps"/"ms" suffixes): custom fpsColor swatch or the live accent; the dynamic values stay white. Returns r, g, b, hex.
local function GetDescColor(mp)
    local r, g, b
    if mp and mp.fpsUseAccent then
        r, g, b = ACC.r, ACC.g, ACC.b
    else
        local c = mp and mp.fpsColor
        if c then
            r, g, b = c.r or 1, c.g or 1, c.b or 1
        else
            r, g, b = 1, 1, 1
        end
    end
    return r,
        g,
        b,
        format(
            "%02x%02x%02x",
            math.floor(r * 255 + 0.5),
            math.floor(g * 255 + 0.5),
            math.floor(b * 255 + 0.5)
        )
end

-- Cache clock CVars so we don't read them every second
local cachedUse24h, cachedUseLocal
local function RefreshClockCVars()
    cachedUse24h = GetCVar("timeMgrUseMilitaryTime") == "1"
    cachedUseLocal = GetCVar("timeMgrUseLocalTime") == "1"
end

local function UpdateClock()
    if not clockFrame then
        return
    end
    if cachedUse24h == nil then
        RefreshClockCVars()
    end
    local hgt, m
    if cachedUseLocal then
        local t = date("*t")
        hgt, m = t.hour, t.min
    else
        hgt, m = GetGameTime()
    end
    if cachedUse24h then
        clockFrame:SetText(format("%02d:%02d", hgt, m))
    else
        -- Unpadded hour in 12h (1:03, not 01:03) matching Blizzard; 24h keeps the pad. AM/PM takes the description colour only when opted in; digits stay white.
        local ampm = hgt >= 12 and "PM" or "AM"
        hgt = hgt % 12
        if hgt == 0 then
            hgt = 12
        end
        local mp = SKIN.db and SKIN.db.profile.minimap
        if mp and mp.fpsColorClockAMPM then
            local _, _, _, hex = GetDescColor(mp)
            clockFrame:SetFormattedText("%d:%02d |cff%s%s|r", hgt, m, hex, ampm)
        else
            clockFrame:SetFormattedText("%d:%02d %s", hgt, m, ampm)
        end
    end
end

-- Coords mode/position with legacy fallback: pre-dropdown exports carry only coordsBelow (true = always-on below the map, else hover-only at the top left).
local function GetCoordsModePos(mp)
    if not mp then
        return "always", "topLeft"
    end
    local mode = mp.coordsMode or (mp.coordsBelow and "always") or "always"
    local place = mp.coordsPosition or (mp.coordsBelow and "belowMap") or "topLeft"
    return mode, place
end

-- Clock/location legacy fallback: pre-dropdown data carries clockInside/zoneInside
-- (default ON/OFF) plus the removed Zone/Clock checkboxes (showClock == false / hideZoneText == true meant hidden).
local function GetElementModes(mp)
    if not mp then
        return "inside", "inside"
    end
    local clockMode = mp.clockMode
    if clockMode == nil then
        if mp.showClock == false then
            clockMode = "none"
        else
            clockMode = (mp.clockInside == false) and "edge" or "inside"
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

-- position key -> element point, map relPoint, base X, base Y (inside flavor). Shared by the coordinates, clock and zone text elements.
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

-- An inside-map offset under the WoW Forever look's Forever Square: the rim
-- and its dark line cover the map's outer 3px and its inner shadow reaches
-- 5px (FOREVER_HEAVY.band and .shade at the window scale, less the rim's
-- EBS.FV_SQUARE_OUT outside the map), over the 4px inset above, so an
-- element inside the map steps 2px further in on each axis it is inset on
-- (6px from the edge; the title bar's divider and its shadow reach no
-- further). pos: a MAP_POS_ANCHORS key (nil: inside the map). Above Map
-- rises over the title bar while it shows, keeping its gap to the frame;
-- Below Map, and every other look, keep their offsets. Blizzard Style's slim
-- square keeps the 4px inset (its line's inner shadow ends at the map's
-- edge). An EBS field.
function SKIN._FvInsideXY(place, posX, posY)
    if not SKIN._fvSquare or place == "belowMap" then
        return posX, posY
    end
    if place == "aboveMap" then
        if SKIN._fvTitleOn then
            posY = posY + SKIN._SqTitle() - SKIN._SqOut()
        end
        return posX, posY
    end
    if SKIN._sqSlim then
        return posX, posY
    end
    if posX ~= 0 then
        posX = posX + (posX > 0 and 2 or -2)
    end
    if posY ~= 0 then
        posY = posY + (posY > 0 and 2 or -2)
    end
    return posX, posY
end

-- Anchor for the clock/zone text bar. Inside keeps the 4px map inset (7px under
-- Forever Square, past the heavy band); edge flips it so the box straddles the
-- border (7px out on squares, 3px in on circles -- the round mask curves away
-- from the frame edge). Above/Below Map float outside in both.
local function ResolveElementAnchor(place, style, isCircle)
    local a = MAP_POS_ANCHORS[place] or MAP_POS_ANCHORS.top
    local posX, posY = a[3], a[4]
    if style == "edge" and place ~= "belowMap" and place ~= "aboveMap" then
        if posX ~= 0 then
            posX = isCircle and (posX > 0 and 3 or -3) or (posX > 0 and -7 or 7)
        end
        if posY ~= 0 then
            posY = isCircle and (posY > 0 and 3 or -3) or (posY > 0 and -7 or 7)
        end
    else
        posX, posY = SKIN._FvInsideXY(place, posX, posY)
    end
    return a[1], a[2], posX, posY
end

-- Cache coord format string so we don't rebuild it every 0.5s
local cachedCoordPrec, cachedCoordFmt
local function UpdateCoords()
    if not coordFrame then
        return
    end
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then
        coordFrame:SetText("")
        return
    end
    local place = C_Map.GetPlayerMapPosition(mapID, "player")
    if not place then
        coordFrame:SetText("")
        return
    end
    local posX, posY = place:GetXY()
    local p = SKIN.db and SKIN.db.profile.minimap
    local prec = p and p.coordPrecision or 1
    if prec ~= cachedCoordPrec then
        cachedCoordPrec = prec
        cachedCoordFmt = format("%%.%df, %%.%df", prec, prec)
    end
    coordFrame:SetText(format(cachedCoordFmt, posX * 100, posY * 100))
end

-- Reactive zone coloring: tint by the current zone's PvP ruleset (friendly green, hostile/arena/combat red, sanctuary blue, contested/unknown yellow).
local function GetZoneReactionColor()
    local pvpType = C_PvP and C_PvP.GetZonePVPInfo and C_PvP.GetZonePVPInfo()
    if pvpType == "friendly" then
        return 0.05, 0.85, 0.03
    elseif pvpType == "sanctuary" then
        return 0.035, 0.58, 0.84
    elseif pvpType == "arena" or pvpType == "hostile" or pvpType == "combat" then
        return 0.84, 0.03, 0.03
    end
    return 0.9, 0.85, 0.05
end

local lastLocationText
local function UpdateLocation()
    if not locationFrame then
        return
    end
    if InCombatLockdown() then
        return
    end
    -- Colour before the text dedup so toggles/ruleset changes repaint the same zone.
    local mp = SKIN.db and SKIN.db.profile.minimap
    if mp and mp.zoneReactiveColor then
        local r, g, b = GetZoneReactionColor()
        locationFrame:SetTextColor(r, g, b, 0.9)
    else
        locationFrame:SetTextColor(1, 1, 1, 0.9)
    end
    local textValue
    if mp and mp.zoneShowSubZone then
        local sub = GetSubZoneText()
        textValue = (sub and sub ~= "") and sub or (GetZoneText() or "")
    else
        textValue = GetZoneText() or ""
    end
    if textValue == lastLocationText then
        return
    end
    lastLocationText = textValue
    locationFrame:SetText(textValue)
    if locationBg then
        local tw = locationFrame:GetStringWidth() or 0
        locationBg:SetSize(tw + 20, 18)
    end
end

Inner.ApplyMinimapFont, Inner.GetCoordsModePos = ApplyMinimapFont, GetCoordsModePos
Inner.GetDescColor, Inner.GetElementModes = GetDescColor, GetElementModes
Inner.MAP_POS_ANCHORS, Inner.RefreshClockCVars = MAP_POS_ANCHORS, RefreshClockCVars
Inner.ResolveElementAnchor, Inner.UpdateClock = ResolveElementAnchor, UpdateClock
Inner.UpdateCoords, Inner.UpdateLocation = UpdateCoords, UpdateLocation
Inner.broken = false
