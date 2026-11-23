-- Zone Info (CludesUIForeverEssentials_ZoneInfo.lua): the Barrens' panel
-- from CludesUI's own data (levels, dungeons, fishing, travel, gathering),
-- a section switched off, a continent map hiding it, and off.
local CUI = rawget(_G, "CludesUI")
local ZI = CUI._ZoneInfo
OUT:write("== zone info " .. tostring(ZI ~= nil) .. "\n")
if not ZI then return end

local T = Enum.UIMapType
local maps = {
    [1413] = { mapID = 1413, name = "The Barrens", mapType = T.Zone, parentMapID = 1414 },
    [1414] = { mapID = 1414, name = "Kalimdor", mapType = T.Continent, parentMapID = 947 },
    [1411] = { mapID = 1411, name = "Durotar", mapType = T.Zone, parentMapID = 1414 },
    [1412] = { mapID = 1412, name = "Mulgore", mapType = T.Zone, parentMapID = 1414 },
    [1440] = { mapID = 1440, name = "Ashenvale", mapType = T.Zone, parentMapID = 1414 },
    [1442] = { mapID = 1442, name = "Stonetalon Mountains", mapType = T.Zone, parentMapID = 1414 },
    [1445] = { mapID = 1445, name = "Dustwallow Marsh", mapType = T.Zone, parentMapID = 1414 },
    [1441] = { mapID = 1441, name = "Thousand Needles", mapType = T.Zone, parentMapID = 1414 },
}
C_Map.GetMapInfo = function(id) return maps[id] end
C_Map.GetAreaInfo = function() return nil end
local shownMap = 1413
WorldMapFrame.GetMapID = function() return shownMap end
WorldMapFrame.OnMapChanged = WorldMapFrame.OnMapChanged or function() end
GetRealZoneText = function(id) return ({ [43] = "Wailing Caverns", [47] = "Razorfen Kraul", [129] = "Razorfen Downs" })[id] or "" end
UnitLevel = function() return 15 end
UnitFactionGroup = function() return "Horde" end
GetProfessions = function() return nil, nil, nil, 3 end
GetProfessionInfo = function() return "Fishing", 0, 60, 300, 0, 0, 356, 0 end

local function Dump(tag)
    local panel = _G.CludesUIZoneInfo
    local out = {}
    if panel and panel:IsShown() then
        for _, r in ipairs({ panel:GetRegions() }) do
            if r.GetText and r:IsShown() and r:GetText() and r:GetText() ~= "Zone Info" then out[#out + 1] = r:GetText() end
        end
    end
    OUT:write(("== %s: shown=%s | %s\n"):format(tag, tostring(panel and panel:IsShown()), table.concat(out, " / ")))
end

ZI.Cfg().enabled = true
WorldMapFrame:Show()
ZI.Apply()
Dump("The Barrens")
ZI.Cfg().travel = false
ZI.Apply()
Dump("travel off")
ZI.Cfg().travel = nil
shownMap = 1414
WorldMapFrame:OnMapChanged()
Dump("Kalimdor (continent)")
shownMap = 1413
ZI.Cfg().enabled = false
ZI.Apply()
Dump("off")
