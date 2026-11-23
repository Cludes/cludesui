if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
if not (CUI and CUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_ZoneInfo.lua  (WoW Forever only)
--  Zone Info: a CludesUI panel beside the world map for the zone it shows:
--  its level range against yours, then (each its own switch)
--    Dungeons & Raids   the instance entrances in the zone
--    Fishing            the skill it needs (catch / no fish escape) and yours
--    Travel             its flight masters for your side, its boats, trams
--                       and zeppelins with where they go, and its roads out
--    Herbs & Mining     the herbs and ore that grow there, by skill, against
--                       yours (only the gathering skills you have, by default)
--  The data is CludesUI's own: Show Zone Levels' ranges and fishing, Map
--  Markers' places, Town Map's flight masters and Glimmer's spots; nothing
--  needs those features switched on. From Naowh Forever's Zone Info (with
--  permission), redrawn. Shown only on a zone's map, never in combat changes.
-------------------------------------------------------------------------------
local _, module = ...

local F = module.Feature("zoneInfo", {
    enabled = false,
    dungeons = true,
    fishing = true,
    travel = true,
    gathering = true,
    onlyMyProfessions = true,
})
local Get, Enabled = F.Get, F.Enabled

local WIDTH = 250
local PAD = 10
local LINE_GAP = 2
local SECTION_GAP = 8
local MAX_PARENTS = 12
local HERBALISM, MINING = 182, 186
local TRANSPORT = { boat = "Boat", zeppelin = "Zeppelin", tram = "Tram", portal = "Portal", skycutter = "Skycutter" }

local panel, lines, used, hooked
local EMPTY = {}

local function Plain(v) return not (issecretvalue and issecretvalue(v)) end

-- The zone a map belongs to (a city or a cave counts as its own zone while
-- it has level or fishing data, else its parent zone); nil on a continent.
local function ZoneOf(mapID)
    local ZL = CUI._ZoneLevels
    for _ = 1, MAX_PARENTS do
        local info = mapID and C_Map.GetMapInfo(mapID)
        if not info then return end
        if (ZL and (ZL.Levels(mapID) or ZL.Fishing(mapID))) or info.mapType == Enum.UIMapType.Zone then
            return mapID, info
        end
        if info.mapType <= Enum.UIMapType.Continent or not info.parentMapID or info.parentMapID <= 0 then return end
        mapID = info.parentMapID
    end
end

local function Skills()
    local out, fishing = {}, nil
    local first, second, _, fish = GetProfessions()
    for _, index in ipairs({ first or false, second or false }) do
        if index then
            local _, _, rank, _, _, _, line, modifier = GetProfessionInfo(index)
            if Plain(line) and Plain(rank) and line then out[line] = (rank or 0) + (modifier or 0) end
        end
    end
    if fish then
        local _, _, rank, _, _, _, _, modifier = GetProfessionInfo(fish)
        if Plain(rank) and rank then fishing = rank + (modifier or 0) end
    end
    return out, fishing
end

-------------------------------------------------------------------------------
--  The panel
-------------------------------------------------------------------------------

local function Build()
    if panel then return panel end
    local Kit = CUI.Kit
    panel = CreateFrame("Frame", "CludesUIZoneInfo", WorldMapFrame)
    panel:SetWidth(WIDTH)
    panel:SetFrameStrata("HIGH")
    Kit.Panel(panel)
    Kit.Header(panel, CUI.L("Zone Info"), nil, { key = "essentials" })
    lines, used = {}, 0
    return panel
end

local function Line(textValue, color, size, indent)
    used = used + 1
    local fs = lines[used]
    if not fs then
        fs = panel:CreateFontString(nil, "OVERLAY")
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(true)
        lines[used] = fs
    end
    CUI.Kit.Font(fs, size or CUI.Kit.SMALL_SIZE, "essentials")
    fs:SetWidth(WIDTH - 2 * PAD - (indent or 0))
    fs:SetText(textValue)
    fs:SetTextColor(color[1], color[2], color[3])
    fs.indent = indent or 0
    fs:Show()
    return fs
end

local function Section(title)
    local r, g, b = CUI.Kit.Accent()
    local fs = Line(CUI.L(title), { r, g, b }, CUI.Kit.TEXT_SIZE)
    fs.section = true
end

local function Entry(textValue, detail, color)
    local P = CUI.Kit.Palette
    local fs = Line(textValue .. (detail and ("  |cffa3adb5" .. detail .. "|r") or ""), color or P.text, nil, 8)
    fs.section = false
end

local function Note(textValue)
    local fs = Line(CUI.L(textValue), CUI.Kit.Palette.muted, nil, 8)
    fs.section = false
end

local function Layout()
    local y = -(CUI.Kit.HEADER_H + PAD)
    for i = 1, used do
        local fs = lines[i]
        if fs.section and i > 1 then y = y - SECTION_GAP end
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", PAD + fs.indent, y)
        y = y - fs:GetStringHeight() - LINE_GAP
    end
    for i = used + 1, #lines do
        lines[i]:Hide()
    end
    panel:SetHeight(math.max(60, -y + PAD))
end

local GREEN, AMBER, RED = { 0.37, 0.77, 0.42 }, { 1, 0.7, 0.25 }, { 1, 0.38, 0.38 }

local function Dungeons(zone, places)
    Section("Dungeons & Raids")
    local list = places and places.instances and places.instances[zone] or EMPTY
    local named = {}
    for _, e in ipairs(list) do
        local name = GetRealZoneText(e[3])
        if name and name ~= "" and not named[name] then
            named[name] = true
            Entry(name, e[5] and CUI.L(e[5]) or (e[4] and CUI.L("Raid")) or nil)
        end
    end
    if not next(named) then Note("No dungeon entrances are recorded for this zone.") end
end

local function Fishing(zone, fishing)
    Section("Fishing")
    local ZL = CUI._ZoneLevels
    local low, high
    if ZL then low, high = ZL.Fishing(zone) end
    if not low then return Note("Fishing requirements are not recorded for this zone.") end
    local mine, color = CUI.L("Fishing not learned"), nil
    if fishing then
        local state
        if fishing < low then
            state, color = CUI.L("below the minimum"), RED
        elseif fishing < high then
            state, color = CUI.L("fish may escape"), AMBER
        else
            state, color = CUI.L("reliable"), GREEN
        end
        mine = CUI.Lf("yours %1$d, %2$s", fishing, state)
    end
    Entry(CUI.Lf("%1$d to catch, %2$d for none to escape", low, high), mine, color)
end

local function Travel(zone, places)
    Section("Travel")
    local count = 0
    local side = UnitFactionGroup("player") == "Horde" and "H" or "A"
    local npcs = module.TownNPCList and module.TownNPCList()
    for _, npc in ipairs(npcs and npcs[zone] or EMPTY) do
        if npc[3] == "flight" and (npc[7] or ""):find(side, 1, true) then
            Entry(npc[4], CUI.L("Flight Master"))
            count = count + 1
        end
    end
    for _, t in ipairs(places and places.transports and places.transports[zone] or EMPTY) do
        local to = C_Map.GetMapInfo(t[4])
        local area = t[5] and C_Map.GetAreaInfo and C_Map.GetAreaInfo(t[5])
        Entry(CUI.L(TRANSPORT[t[3]] or "Transport"), CUI.Lf("to %1$s", area or (to and to.name) or "?"))
        count = count + 1
    end
    for _, e in ipairs(places and places.exits and places.exits[zone] or EMPTY) do
        local to = C_Map.GetMapInfo(e[3])
        if to then
            Entry(CUI.Lf("Road to %1$s", to.name))
            count = count + 1
        end
    end
    if count == 0 then Note("No travel connections are recorded for this zone.") end
end

local function Gathering(zone, skills)
    Section("Herbs & Mining")
    local GL = CUI._Glimmer
    local list = GL and GL.ZoneNodes(zone)
    if not list then return Note("Gathering details are available after combat.") end
    local count = 0
    for _, node in ipairs(list) do
        local skill = skills[node.kind == "herb" and HERBALISM or MINING]
        if skill or not Get("onlyMyProfessions") then
            local color = not skill and CUI.Kit.Palette.muted or (skill >= node.need and GREEN or RED)
            Entry(CUI.L(node.name), skill and CUI.Lf("needs %1$d, yours %2$d", node.need, skill) or CUI.Lf("needs %1$d", node.need), color)
            count = count + 1
        end
    end
    if count == 0 then
        Note(#list == 0 and "No gathering locations are recorded for this zone." or "No matching gathering profession learned.")
    end
end

local function Fill()
    if not (panel and Enabled() and WorldMapFrame:IsShown()) then
        if panel then panel:Hide() end
        return
    end
    local zone, info = ZoneOf(WorldMapFrame:GetMapID())
    if not zone then
        panel:Hide()
        return
    end
    used = 0
    local P = CUI.Kit.Palette
    Line(info.name, P.text, CUI.Kit.TEXT_SIZE + 2)
    local ZL = CUI._ZoneLevels
    local range = ZL and ZL.Levels(zone)
    if range then
        local level = UnitLevel("player")
        local text = range[1] == range[2] and CUI.Lf("Level %1$d", range[1]) or CUI.Lf("Level %1$d-%2$d", range[1], range[2])
        local rating, color = "", P.muted
        if level < range[1] then
            rating, color = CUI.L("above your level"), RED
        elseif level > range[2] then
            rating, color = CUI.L("below your level"), P.muted
        else
            rating, color = CUI.L("good for your level"), GREEN
        end
        Line(text .. ", " .. rating, color)
    end
    local places = CUI._MapTravel and CUI._MapTravel.Places and CUI._MapTravel.Places()
    local skills, fishing = Skills()
    if Get("dungeons") then Dungeons(zone, places) end
    if Get("fishing") then Fishing(zone, fishing) end
    if Get("travel") then Travel(zone, places) end
    if Get("gathering") then Gathering(zone, skills) end
    Layout()
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", WorldMapFrame, "TOPRIGHT", 4, 0)
    panel:Show()
end

local function Apply()
    if not Enabled() then
        if panel then panel:Hide() end
        return
    end
    if not (WorldMapFrame and WorldMapFrame.GetMapID) then
        local waiter = CreateFrame("Frame")
        waiter:RegisterEvent("ADDON_LOADED")
        waiter:SetScript("OnEvent", function(self, _, name)
            if name ~= "Blizzard_WorldMap" then return end
            self:UnregisterAllEvents()
            Apply()
        end)
        return
    end
    Build()
    if not hooked then
        hooked = true
        if WorldMapFrame.OnMapChanged then hooksecurefunc(WorldMapFrame, "OnMapChanged", Fill) end
        WorldMapFrame:HookScript("OnShow", Fill)
        WorldMapFrame:HookScript("OnHide", function() if panel then panel:Hide() end end)
    end
    Fill()
end

CUI._ZoneInfo = { Get = Get, Cfg = F.Cfg, Apply = Apply, Fill = Fill }
F.Start(Apply)
