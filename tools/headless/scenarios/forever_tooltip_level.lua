-- Forever: the unit tooltip's level line for a player whose level is hidden
-- ("Level ??"). You are level 38; the hovered player is level 54, hidden to
-- you, remembered by the PvP feature (or, as measured in game, UnitLevel
-- answers while the shown level hides). The game draws a hidden level in a
-- difficulty colour, so the level line can start with a colour escape. The
-- tooltip should show the level in place of "??" (Known Levels on), coloured
-- or plain, and leave the line alone with the option off or for a level that
-- reads.
local CUI = rawget(_G, "CludesUI")
local tip = rawget(_G, "GameTooltip")
if not (CUI and tip and CUI.KnownHiddenLevel) then
    OUT:write("== no tooltip or lookup\n")
    return
end
-- The skin's unit handler: registered with the tooltip data processor at load
-- (the harness keeps registrations), else the older OnTooltipSetUnit script.
local hook
for _, rec in ipairs(rawget(_G, "TooltipDataProcessor") and TooltipDataProcessor.postCalls or {}) do
    local info = debug.getinfo(rec[2], "S")
    if info and info.source:find("TooltipSkin", 1, true) and rec[1] == Enum.TooltipDataType.Unit then
        hook = rec[2]
        break
    end
end
hook = hook or (tip["\0scripts"] and tip["\0scripts"].OnTooltipSetUnit)
OUT:write("== unit handler found " .. tostring(hook ~= nil) .. "\n")
if not hook then
    return
end

local target = { name = "Beppee", realm = "Lightbane", level = -1, effective = -1 }
local lines = {}
local function Line(i)
    local fs = lines[i]
    if not fs then
        fs = { text = nil }
        function fs:GetText() return self.text end
        function fs:SetText(t) self.text = t end
        function fs:SetTextColor() end
        function fs:GetFont() return "Fonts\\FRIZQT__.TTF", 12, "" end
        function fs:SetFont() end
        lines[i] = fs
        rawset(_G, "GameTooltipTextLeft" .. i, fs)
    end
    return fs
end
local function Fill(...)
    local t = { ... }
    for i = 1, 8 do
        Line(i).text = t[i]
    end
    tip.NumLines = function() return #t end
end

local function Stub(e)
    e.UnitExists = function(u) return u == "mouseover" or u == "player" end
    e.UnitIsPlayer = function() return true end
    e.UnitName = function(u)
        if u == "player" then return "Me", nil end
        return target.name, target.realm
    end
    e.UnitGUID = function(u) return u == "player" and "Player-1-ME" or "Player-1-BEPPEE" end
    e.UnitLevel = function(u)
        if u == "player" then return 38 end
        return target.level
    end
    e.UnitEffectiveLevel = function(u)
        if u == "player" then return 38 end
        return target.effective
    end
    e.UnitClass = function() return "Paladin", "PALADIN" end
    e.UnitRace = function() return "Undead" end
    e.GetGuildInfo = function() return "Ironworks" end
    e.GetPlayerInfoByGUID = function() return "Paladin", "PALADIN", "Undead", "Scourge", 2, target.name, target.realm end
    e.UnitIsUnit = function(a, b) return a == b end
    e.UnitFactionGroup = function() return "Horde" end
    e.UnitIsAFK = function() return false end
    e.UnitIsDND = function() return false end
    e.UnitIsInMyGuild = function() return false end
    e.UnitIsWildBattlePet = function() return false end
    e.UnitIsBattlePetCompanion = function() return false end
    e.UnitClassification = function() return "normal" end
    e.UnitCreatureType = function() return "Humanoid" end
end
Stub(getfenv(CUI.KnownHiddenLevel))
Stub(_G)
-- The fake client's stand-in answers nil; the level colour needs a number.
rawset(C_QuestLog, "GetTrivialRange", function() return 8 end)
tip.GetUnit = function() return target.name, "mouseover" end
tip.IsForbidden = function() return false end

CludesUIDB.pvp = { enabled = false, players = { ["Beppee-Lightbane"] = { level = 54 } } }

local function Hover(label, level, effective, ...)
    Fill(...)
    target.level, target.effective = level, effective
    local ok, err = pcall(hook, tip, { guid = "Player-1-BEPPEE", lines = {} })
    OUT:write("== " .. label .. (ok and "" or (" ERR " .. tostring(err))) .. "\n")
    for i = 1, 5 do
        local t = lines[i] and lines[i].text
        if t then OUT:write("   " .. i .. ": " .. t:gsub("|", "!") .. "\n") end
    end
end

local plain = "Level ?? Undead"
local coloured = "|cffff2020Level ??|r Undead"
local function Cases(suffix)
    Hover("coloured, remembered 54" .. suffix, -1, -1, "Beppee-Lightbane", "Ironworks", coloured, "Paladin", "Horde")
    Hover("plain, remembered 54" .. suffix, -1, -1, "Beppee-Lightbane", "Ironworks", plain, "Paladin", "Horde")
    Hover("coloured, real 54 shown hidden" .. suffix, 54, -1, "Beppee-Lightbane", "Ironworks", coloured, "Paladin")
    Hover("coloured, no guild line" .. suffix, -1, -1, "Beppee-Lightbane", coloured, "Paladin", "Horde")
    CludesUIDB.pvp.knownLevels = false
    Hover("coloured, Known Levels off" .. suffix, -1, -1, "Beppee-Lightbane", "Ironworks", coloured, "Paladin")
    CludesUIDB.pvp.knownLevels = nil
    Hover("level that reads (60)" .. suffix, 60, 60, "Beppee-Lightbane", "Ironworks", "|cffff2020Level 60|r Undead", "Paladin")
end
CludesUIDB.tooltipLevelColor, CludesUIDB.tooltipCompactLevel = nil, nil
Cases("")
CludesUIDB.tooltipLevelColor = true
Cases(", level colour on")
CludesUIDB.tooltipLevelColor, CludesUIDB.tooltipCompactLevel = nil, true
Cases(", compact line on")
CludesUIDB.tooltipLevelColor, CludesUIDB.tooltipCompactLevel = nil, nil
