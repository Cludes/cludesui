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
        function fs:SetTextColor(r, g, b) self.color = string.format("%.2f,%.2f,%.2f", r, g, b) end
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
        Line(i).text, Line(i).color = t[i], nil
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

local payloadLines = {}
local function Hover(label, level, effective, ...)
    Fill(...)
    target.level, target.effective = level, effective
    local ok, err = pcall(hook, tip, { guid = "Player-1-BEPPEE", lines = payloadLines })
    OUT:write("== " .. label .. (ok and "" or (" ERR " .. tostring(err))) .. "\n")
    for i = 1, 6 do
        local t = lines[i] and lines[i].text
        if t then OUT:write("   " .. i .. ": " .. t:gsub("|", "!") .. (lines[i].color and ("  [" .. lines[i].color .. "]") or "") .. "\n") end
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

-- The other line colours: class line (after the level line, not the PvP line),
-- faction line, and a guildmate's guild line in its guild forms. A level-like
-- guild name must not be taken for the level line.
local guildmate = false
local function StubGuild(e) e.UnitIsInMyGuild = function() return guildmate end end
StubGuild(_G)
CludesUIDB.tooltipClassLineColor, CludesUIDB.tooltipFactionColor, CludesUIDB.tooltipGuildmateColor = true, true, true
local function Extras(suffix)
    Hover("extras, plain guild" .. suffix, 54, 54, "Beppee-Lightbane", "Ironworks", "Level 54 Undead", "Paladin", FACTION_HORDE)
    Hover("extras, guild-realm" .. suffix, 54, 54, "Beppee-Lightbane", "Ironworks-Lightbane", "Level 54 Undead", "Paladin", FACTION_ALLIANCE)
    Hover("extras, guild (rank)" .. suffix, 54, 54, "Beppee-Lightbane", "Ironworks (Officer)", "Level 54 Undead", PVP_ENABLED, "Paladin")
    Hover("extras, guild [rank]" .. suffix, -1, -1, "Beppee-Lightbane", "Ironworks [Officer]", "|cffff2020Level ??|r Undead", "Paladin")
    Hover("extras, not the guild" .. suffix, 54, 54, "Beppee-Lightbane", "Ironworksmen", "Level 54 Undead", "Paladin")
    Hover("extras, no level line" .. suffix, 54, 54, "Beppee-Lightbane", "Ironworks", "Paladin", FACTION_HORDE)
end
Extras("")
guildmate = true
Extras(", guildmate")
local realGuild = GetGuildInfo
GetGuildInfo = function() return "Level 70 Club" end
Hover("guild named like a level, guildmate", 54, 54, "Beppee-Lightbane", "Level 70 Club", "Level 54 Undead", "Paladin")
GetGuildInfo = realGuild
-- The client tags the level line in the tooltip data: that index wins even when
-- the text reads like no level format.
payloadLines = { { type = Enum.TooltipDataLineType.UnitLevel, lineIndex = 3 } }
CludesUIDB.tooltipLevelColor = true
Hover("tagged level line", 54, 54, "Beppee-Lightbane", "Ironworks", "Stufe 54 Untoter", "Paladin")
Hover("tagged hidden level line", -1, -1, "Beppee-Lightbane", "Ironworks", "Stufe ?? Untoter", "Paladin")
payloadLines = {}
CludesUIDB.tooltipCompactLevel = true
Hover("compact and colour", 54, 54, "Beppee-Lightbane", "Ironworks", "Level 54 Undead", "Paladin", FACTION_HORDE)
CludesUIDB.tooltipLevelColor, CludesUIDB.tooltipCompactLevel = nil, nil
CludesUIDB.tooltipClassLineColor, CludesUIDB.tooltipFactionColor, CludesUIDB.tooltipGuildmateColor = nil, nil, nil
guildmate = false

-- The level-line patterns the skin built from the client's level formats.
local isLevel
for i = 1, 60 do
    local n, v = debug.getupvalue(hook, i)
    if not n then break end
    if n == "_ttLineColors" then
        for j = 1, 60 do
            local n2, v2 = debug.getupvalue(v, j)
            if not n2 then break end
            if n2 == "_isLevelText" then isLevel = v2 end
        end
    end
end
if isLevel then
    for j = 1, 10 do
        local n, v = debug.getupvalue(isLevel, j)
        if not n then break end
        if type(v) == "table" then
            for k, pat in ipairs(v) do
                OUT:write("== pattern " .. k .. ": " .. pat .. "\n")
            end
        end
    end
    for _, text in ipairs({ "Level 54", "Level 54 Undead", "Level 54 (Undead)", "Level ??", "|cff00ff00Level 12|r Beast", "Leveling Coach", "Level up!", "Ironworks", "54 Undead" }) do
        OUT:write("== is level " .. text:gsub("|", "!") .. ": " .. tostring(isLevel(text)) .. "\n")
    end
else
    OUT:write("== level check not found\n")
end
