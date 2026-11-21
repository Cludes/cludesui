if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
-- CUI_GroupFinder_Search.lua: the premade search panel (rows, menus, filters,
-- list tweaks, bottom buttons).
-------------------------------------------------------------------------------
local ADDON_NAME, mod = ...
if CludesUI.HELD_BACK_ADDONS[ADDON_NAME] then return end -- held back (CludesUIGroupFinder.lua)
local FOLDER = ADDON_NAME
local CUI = CludesUI

local DUNGEONS = GROUP_FINDER_CATEGORY_ID_DUNGEONS or 2
local DELVES = GROUP_FINDER_CATEGORY_ID_DELVES or 121
local RAIDS = GROUP_FINDER_CATEGORY_ID_RAIDS or 3
local GOLD_R, GOLD_G, GOLD_B = 1, 0.82, 0
local MEDIA = "Interface\\AddOns\\CludesUI\\media\\icons\\"
local COG_TEX = CludesUI.COGS_ICON -- the inline cogs' icon
local X_TEX = MEDIA .. "cui-close.png"

local ROW1_Y = -42 -- row 1 centre
local ROW1_H = 24
local BTN = 28 -- row 2 square size (layout resizes it)
local DIFF_W = 110
local SQ_GAP = 3 -- gap between everything
local ROW2_Y = ROW1_Y - ROW1_H / 2 - SQ_GAP
local CD_SEARCH = 2
-- bottom buttons sit this far up (blizzard uses 4).
local BOTTOM_Y = 8
local CD_FAILED = 6

local FFD = setmetatable({}, { __mode = "k" })
-- shared helpers (lua 5.1 caps a chunk at 200 locals).
local Finder = {}
-- grey for our white glyphs
Finder.GLYPH = 0.78
-- dimmed tooltip lines, gold bountiful line
Finder.DIM_HEX = CUI.HexColor(0.7, 0.7, 0.7)
Finder.GOLD_HEX = CUI.HexColor(GOLD_R, GOLD_G, GOLD_B)
-- shared empty list (never written)
Finder.EMPTY = {}
-- plain tooltip, extra lines dimmed
function Finder.Tip(ownerFrame, title, ...)
    local textValue = title
    for index = 1, select("#", ...) do
        local line = select(index, ...)
        if line then
            if line:sub(1, 2) == "|c" then
                textValue = textValue .. "\n" .. line
            else
                textValue = textValue .. "\n" .. Finder.DIM_HEX .. line .. "|r"
            end
        end
    end
    Finder.tipOwner = ownerFrame
    CUI.ShowWidgetTooltip(ownerFrame, textValue)
end
function Finder.ClassLine(classFile, textValue)
    local color = C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(classFile)
    return color and color:WrapTextInColorCode(textValue) or textValue
end
function Finder.Untip()
    Finder.tipOwner = nil
    CUI.HideWidgetTooltip()
end

-- our text in the module's font
function Finder.Font(fontStr, px, flags) CUI.ApplyModuleFont(fontStr, nil, px, ADDON_NAME, flags or "") end

-- blizzard's frames only move out of combat: queued till it ends
function Finder.Defer(filterKey, func) mod.CombatQueue.Defer(filterKey, func) end

-- click-outside close for our menus
function Finder.ClickOff(menu, inside)
    menu:SetScript("OnEvent", function(self, _, btnFrame)
        if btnFrame == "LeftButton" and not inside(self) then self:Hide() end
    end)
    menu:HookScript("OnShow", function(self) self:RegisterEvent("GLOBAL_MOUSE_DOWN") end)
    menu:HookScript("OnHide", function(self) self:UnregisterEvent("GLOBAL_MOUSE_DOWN") end)
end

local SP
local line, difficultyBtn, dropMenu, resetBtn, refreshButton, gfFont
local pending = false -- filters changed since the last search
local cdUntil = 0
local squares = {}
local dungeons -- this season's dungeons
local delves -- delves category
local delveByActivity -- activityID -> groupID, tier
local bountiful = {} -- delve name -> bountiful today
local delveSquares = {}
local tierBtn, tierMenu
local bosses -- current raid bosses
local raidByActivity -- activityID -> journal instance
local bossSquares = {}
local raidList -- current raids, blizzard's order
local raidBtn, raidMenu
local raidDiffMenu

local DIFFS = {
    { key = "difficultyNormal", label = PLAYER_DIFFICULTY1 or "Normal" },
    { key = "difficultyHeroic", label = PLAYER_DIFFICULTY2 or "Heroic" },
    { key = "difficultyMythic", label = PLAYER_DIFFICULTY6 or "Mythic" },
    { key = "difficultyMythicPlus", label = PLAYER_DIFFICULTY_MYTHIC_PLUS or "Mythic+" },
}

local function FinderCfg() return mod.Cfg() end
local function AccentRGB()
    local a = CUI.CLUDES_GREEN
    return a.r, a.g, a.b
end
-- the skin's window engine, so our buttons follow its theme
local function WindowSkin()
    local skinNS = CUI._ModuleNS.CludesUIBlizzardSkin
    return skinNS and skinNS.WSkin
end
-- cui's group finder skin is on; off, our parts take blizzard's look. read once per session, at login,
-- when the window skin itself installs: a card toggle swaps both with the reload it asks for
function Finder.SkinOn()
    local isOn = Finder.skinOn
    if isOn ~= nil then return isOn end
    local style = CUI.GetBlizzWindowStyle -- nil while blizzard skins+ is off
    isOn = (WindowSkin() ~= nil and style ~= nil and style("lfg") ~= "off") and true or false
    if IsLoggedIn() then Finder.skinOn = isOn end
    return isOn
end
mod.SkinOn = Finder.SkinOn
local function ThemeBorder()
    if not Finder.SkinOn() then return 0.38, 0.38, 0.38, 1 end -- blizzard's search box grey
    local S = WindowSkin()
    local T = S and S.Theme
    if T and T.brdR then return T.brdR, T.brdG, T.brdB, T.brdA end
    return 0.2, 0.2, 0.2, 1
end
mod.Skin, mod.ThemeBorder = WindowSkin, ThemeBorder
-- an unpicked square's edge: the theme's, or none on blizzard's rounded button
function Finder.RestBorder(frame)
    if Finder.SkinOn() then
        CUI.PanelPP.SetBorderColor(frame, ThemeBorder())
    else
        CUI.PanelPP.SetBorderColor(frame, 0, 0, 0, 0)
    end
end
-- a picked square: a white edge, or blizzard's highlight held on
function Finder.PickBorder(square, edge, isOn)
    if Finder.SkinOn() then
        if isOn then
            CUI.PanelPP.SetBorderColor(edge, 1, 1, 1, 1)
        else
            Finder.RestBorder(edge)
        end
        return
    end
    Finder.RestBorder(edge)
    if isOn then
        square:LockHighlight()
    else
        square:UnlockHighlight()
    end
end
mod.BOTTOM_Y = BOTTOM_Y
local function SetBorderColor(widget, red, green, blue, a)
    CUI.PanelPP.SetBorderColor(widget, red, green, blue, a)
end

-------------------------------------------------------------------------------
-- season dungeons and the advanced filter
-------------------------------------------------------------------------------
local function GroupsFor(filter)
    local success, groups = pcall(C_LFGList.GetAvailableActivityGroups, DUNGEONS, filter)
    return (success and type(groups) == "table") and groups or {}
end

local function SeasonFilter()
    local F = Enum.LFGListFilter
    return bit.bor(F.CurrentSeason, F.PvE)
end

local function AllDungeonGroups()
    local F = Enum.LFGListFilter
    local all = {}
    for _, group in ipairs(GroupsFor(SeasonFilter())) do
        all[#all + 1] = group
    end
    for _, group in ipairs(GroupsFor(bit.bor(F.CurrentExpansion, F.NotCurrentSeason, F.PvE))) do
        all[#all + 1] = group
    end
    return all
end

local function BuildDungeons()
    local CMode = C_ChallengeMode
    local maps = CMode and CMode.GetMapTable and CMode.GetMapTable()
    if type(maps) ~= "table" or #maps == 0 then return nil end
    local byMap, byName = {}, {}
    for _, groupId in ipairs(GroupsFor(SeasonFilter())) do
        local gname = C_LFGList.GetActivityGroupInfo(groupId)
        if gname then byName[gname] = groupId end
        for _, aid in ipairs(C_LFGList.GetAvailableActivities(DUNGEONS, groupId) or {}) do
            local details = C_LFGList.GetActivityInfoTable(aid)
            if details and details.mapID then byMap[details.mapID] = groupId end
        end
    end
    local result = {}
    for _, cmID in ipairs(maps) do
        local label, _, _, texture, _, mapID = CMode.GetMapUIInfo(cmID)
        local groupId = (mapID and byMap[mapID]) or (label and byName[label])
        if groupId then
            result[#result + 1] = { cmID = cmID, name = label, icon = texture, groupID = groupId }
        end
    end
    table.sort(result, function(lhs, rhs) return (lhs.name or "") < (rhs.name or "") end)
    return #result > 0 and result or nil
end

-- season dungeons, rebuilt after the m+ maps update
function Finder.Dungeons()
    if not dungeons or Finder.dungeonsDirty then
        Finder.dungeonsDirty = nil
        dungeons = BuildDungeons() or dungeons
    end
    return dungeons
end

local function Contains(entries, val)
    for index = 1, #entries do
        if entries[index] == val then return index end
    end
    return nil
end

-- no dungeon restriction: none or all picked
local function DungeonsDefault(frame)
    local acts = frame.activities or {}
    if #acts == 0 or not dungeons then return true end
    for _, skinData in ipairs(dungeons) do
        if not Contains(acts, skinData.groupID) then return false end
    end
    return true
end

local function DiffAllOrNone(frame)
    local count = 0
    for _, skinData in ipairs(DIFFS) do
        if frame[skinData.key] then count = count + 1 end
    end
    return count == 0 or count == #DIFFS, count
end

local Paint, PaintRefresh

-- dimmed: blizzard's search goes wide so left out groups come back to dim, the
-- picks stay with us and get checked on our side
local PICK_KEYS = {
    "activities",
    "minimumRating",
    "hasTank",
    "hasHealer",
    "needsTank",
    "needsHealer",
    "needsDamage",
    "needsMyClass",
    "difficultyNormal",
    "difficultyHeroic",
    "difficultyMythic",
    "difficultyMythicPlus",
    "generalPlaystyle1",
    "generalPlaystyle2",
    "generalPlaystyle3",
    "generalPlaystyle4",
}

local function DimOn() return mod.OwnListGet and mod.OwnListGet("visibility") == "dimmed" end

local function Picks(frame)
    local p = {}
    for _, key in ipairs(PICK_KEYS) do
        p[key] = frame[key]
    end
    return p
end

local function Widen(frame)
    frame.activities = AllDungeonGroups()
    frame.minimumRating = 0
    frame.hasTank, frame.hasHealer = false, false
    frame.needsTank, frame.needsHealer, frame.needsDamage, frame.needsMyClass = false, false, false, false
    for _, skinData in ipairs(DIFFS) do
        frame[skinData.key] = true
    end
    for index = 1, 4 do
        frame["generalPlaystyle" .. index] = true
    end
end

-- keep this character's picks so another character's don't carry over
function Finder.Remember(frame)
    if frame then mod.SetCharBlizzFilter(Picks(frame)) end
end

function Finder.GetFilter()
    local frame = C_LFGList.GetAdvancedFilter()
    local p = frame and DimOn() and FinderCfg().dimPicks
    if type(p) == "table" then
        for _, key in ipairs(PICK_KEYS) do
            frame[key] = p[key]
        end
    end
    return frame
end

-- filter changes only save, the search waits for search again
local function Apply(frame)
    if DimOn() then
        FinderCfg().dimPicks = Picks(frame)
        Widen(frame)
    end
    C_LFGList.SaveAdvancedFilter(frame)
    Finder.Remember(frame)
    pending = true
    Paint()
    PaintRefresh()
end

-- once per session, when premade groups first opens: put back this character's
-- picks. not at login: blizzard sets its filter back to every dungeon after
-- that, which would undo it. The first time, the character keeps the picks
-- blizzard holds now (the account's, from before)
function Finder.RestoreCharFilter()
    if Finder.filterRestored then return end
    local frame = C_LFGList.GetAdvancedFilter()
    if not frame then return end
    local saved = mod.CharBlizzFilter()
    if type(saved) == "table" then
        for _, key in ipairs(PICK_KEYS) do
            frame[key] = saved[key]
        end
    end
    Finder.filterRestored = true
    -- dimmed keeps the picks with us and blizzard's search wide
    local cfg = FinderCfg()
    if DimOn() then
        if type(cfg.dimPicks) ~= "table" then cfg.dimPicks = Picks(frame) end
        Widen(frame)
    elseif type(cfg.dimPicks) == "table" then
        for _, key in ipairs(PICK_KEYS) do
            frame[key] = cfg.dimPicks[key]
        end
        cfg.dimPicks = nil
    end
    C_LFGList.SaveAdvancedFilter(frame)
    Finder.Remember(frame)
end

local function ToggleDungeon(groupId)
    local frame = Finder.GetFilter()
    if DungeonsDefault(frame) then
        frame.activities = { groupId }
    else
        local acts = frame.activities
        local at = Contains(acts, groupId)
        if at then
            table.remove(acts, at)
        else
            acts[#acts + 1] = groupId
        end
        if #acts == 0 or DungeonsDefault(frame) then frame.activities = AllDungeonGroups() end
    end
    Apply(frame)
end

local function SetDifficulty(filterKey, isOn)
    local frame = Finder.GetFilter()
    local _, n = DiffAllOrNone(frame)
    if n == 0 then
        for _, skinData in ipairs(DIFFS) do
            frame[skinData.key] = true
        end
    end
    if filterKey then
        frame[filterKey] = isOn
    else
        for _, skinData in ipairs(DIFFS) do
            frame[skinData.key] = true
        end
    end
    local _, after = DiffAllOrNone(frame)
    if after == 0 then
        for _, skinData in ipairs(DIFFS) do
            frame[skinData.key] = true
        end
    end
    Apply(frame)
end

-------------------------------------------------------------------------------
-- region filter (us regions, eu languages)
-------------------------------------------------------------------------------
-- the list comes from CUI_GroupFinder_Regions.lua (us regions, eu languages)
local function Regions() return mod.RegionList() or Finder.EMPTY end

local SecretVal = CludesUI.IsSecret
local function RegionsAvailable() return mod.RegionList() ~= nil end

local function ChosenRegions()
    local cfg = FinderCfg()
    return type(cfg.regions) == "table" and cfg.regions or nil
end

local function RegionFilterActive()
    local region = RegionsAvailable() and ChosenRegions()
    if not region then return false end
    local count = 0
    for _, skinData in ipairs(Regions()) do
        if region[skinData.key] then count = count + 1 end
    end
    return count > 0 and count < #Regions()
end

local function ResultInfo(resultID)
    local details = C_LFGList.GetSearchResultInfo(resultID)
    if not details or SecretVal(details) or (canaccesstable and not canaccesstable(details)) then
        return nil
    end
    return details
end

function Finder.Num(counts, filterKey)
    local val = counts[filterKey]
    return (type(val) == "number" and not SecretVal(val)) and val or nil
end

-- activity info, cached per session
Finder.actInfo = {}
function Finder.ActInfo(activity)
    local activityInfo = Finder.actInfo[activity]
    if activityInfo == nil then
        activityInfo = C_LFGList.GetActivityInfoTable(activity)
        if type(activityInfo) ~= "table" then return nil end
        Finder.actInfo[activity] = activityInfo
    end
    return activityInfo
end

-- realm -> region, cached
Finder.regionByRealm = {}
local function LeaderRegion(details)
    local leader = details and details.leaderName
    if not leader or SecretVal(leader) then return nil end
    local realm = leader:match("%-(.+)$") or (GetNormalizedRealmName and GetNormalizedRealmName())
    if not realm or SecretVal(realm) then return nil end
    local regionFrame = Finder.regionByRealm[realm]
    if not regionFrame then
        regionFrame = mod.RegionOfRealm(realm)
        Finder.regionByRealm[realm] = regionFrame
    end
    return regionFrame
end

-------------------------------------------------------------------------------
-- delves: a square per delve, gold underline for bountiful, tier menu
-------------------------------------------------------------------------------
local SKIP_WORDS = { the = true, of = true, a = true, an = true }

-- up to 3 letters: initials, or a single word's first three (utf-8 safe)
local function Abbrev(label)
    local initials = {}
    for word in (label:gsub("\226\128\153", " ")):gmatch("[^%s%-':]+") do
        if not SKIP_WORDS[word:lower()] then initials[#initials + 1] = word end
    end
    local firstChar = function(wid) return wid:match("^[%z\1-\127\194-\244][\128-\191]*") or "" end
    if #initials == 1 then
        local wid, result, n = initials[1], {}, 0
        for ch in wid:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
            n = n + 1
            result[n] = (n == 1) and ch:upper() or ch:lower()
            if n == 3 then break end
        end
        return table.concat(result)
    end
    local result = {}
    for index = 1, math.min(3, #initials) do
        result[index] = firstChar(initials[index]):upper()
    end
    return table.concat(result)
end

-- tier from the activity name; '?' is 12 and '??' is 13.
function Finder.TierOf(fullName)
    if type(fullName) ~= "string" or SecretVal(fullName) then return nil end
    local n = tonumber(fullName:match("(%d+)%D*$"))
    if n then return n end
    local q = fullName:match("(%?+)[^%?]*$")
    if q == "??" then
        return 13
    elseif q == "?" then
        return 12
    end
    return nil
end
Finder.TierLabel = function(t)
    if t == 12 then
        return CludesUI.L("Tier ?")
    elseif t == 13 then
        return CludesUI.L("Tier ??")
    end
    return CludesUI.Lf("Tier %d", t)
end

local function BuildDelves()
    local F = Enum.LFGListFilter
    local seen, entries, byAct = {}, {}, {}
    for _, filter in ipairs({ bit.bor(F.CurrentExpansion, F.PvE), bit.bor(F.CurrentSeason, F.PvE) }) do
        local success, groups = pcall(C_LFGList.GetAvailableActivityGroups, DELVES, filter)
        for _, groupId in ipairs(success and type(groups) == "table" and groups or {}) do
            if not seen[groupId] then
                seen[groupId] = true
                local label = C_LFGList.GetActivityGroupInfo(groupId)
                if label then
                    entries[#entries + 1] = { groupID = groupId, name = label, abbr = Abbrev(label) }
                    for _, aid in ipairs(C_LFGList.GetAvailableActivities(DELVES, groupId) or {}) do
                        local details = C_LFGList.GetActivityInfoTable(aid)
                        local tier = Finder.TierOf(details and details.fullName)
                        byAct[aid] = { groupID = groupId, tier = tier }
                    end
                end
            end
        end
    end
    table.sort(entries, function(lhs, rhs) return lhs.name < rhs.name end)
    if #entries == 0 then return nil end
    return entries, byAct
end

-- Bountiful delves today: check the delve pins for the bountiful art. Only
-- this season's delves count. At most once a minute. The first scan walks
-- every zone under the world map and remembers the zones that hold delves;
-- later scans check only those.
Finder.bountifulScanAt = nil
Finder.delveZones = nil -- map IDs of the zones with delve pins
function Finder.ScanZone(POI, mapID, season)
    local okPins, pins = pcall(POI.GetDelvesForMap, mapID)
    if not (okPins and type(pins) == "table") then return false end
    for _, poiID in ipairs(pins) do
        local pin = POI.GetAreaPOIInfo(mapID, poiID)
        local label, art = pin and pin.name, pin and pin.atlasName
        if label and season[label] and type(art) == "string" and art:find("bountiful", 1, true) then
            bountiful[label] = true
        end
    end
    return #pins > 0
end
local function ScanBountiful()
    local nowTime = GetTime()
    if Finder.bountifulScanAt and nowTime - Finder.bountifulScanAt < 60 then return end
    local POI, MAP = C_AreaPoiInfo, C_Map
    if not (POI and POI.GetDelvesForMap and POI.GetAreaPOIInfo and MAP and MAP.GetMapChildrenInfo) then
        return
    end
    local season = {}
    for _, skinData in ipairs(delves or {}) do
        season[skinData.name] = true
    end
    if not next(season) then return end
    Finder.bountifulScanAt = nowTime
    wipe(bountiful)
    if Finder.delveZones then
        for _, mapID in ipairs(Finder.delveZones) do
            Finder.ScanZone(POI, mapID, season)
        end
        return
    end
    local found = {}
    local okZones, zones = pcall(MAP.GetMapChildrenInfo, 946, Enum.UIMapType.Zone, true)
    for _, zone in ipairs(okZones and type(zones) == "table" and zones or {}) do
        if Finder.ScanZone(POI, zone.mapID, season) then found[#found + 1] = zone.mapID end
    end
    if #found > 0 then Finder.delveZones = found end
end

local function ChosenDelves()
    local cfg = FinderCfg()
    return type(cfg.delves) == "table" and next(cfg.delves) and cfg.delves or nil
end

local MAX_TIER = 13 -- 1-11, then ? and ??

local function PickedTiers()
    local tbl = FinderCfg().delveTiers
    if type(tbl) ~= "table" then return nil end
    local count = 0
    for index = 1, MAX_TIER do
        if tbl[index] then count = count + 1 end
    end
    return (count > 0 and count < MAX_TIER) and tbl or nil, count
end

local function DelveFilterActive()
    return SP and SP.categoryID == DELVES and (ChosenDelves() ~= nil or PickedTiers() ~= nil) or false
end

-- delve / tier filter (unknown activity passes).
local function DelveKeep(details)
    local acts = details and details.activityIDs
    local activity = type(acts) == "table" and not SecretVal(acts) and acts[1]
    local skinData = activity and not SecretVal(activity) and delveByActivity and delveByActivity[activity]
    if not skinData then return true end
    local chosen = ChosenDelves()
    if chosen and not chosen[skinData.groupID] then return false end
    local tiers = PickedTiers()
    if tiers and skinData.tier and not tiers[skinData.tier] then return false end
    return true
end

-------------------------------------------------------------------------------
-- raid bosses: a square per boss with its journal portrait.
-------------------------------------------------------------------------------
local function RaidsCurrent()
    local frame = SP and SP.filters
    return SP
            and SP.categoryID == RAIDS
            and type(frame) == "number"
            and bit.band(frame, Enum.LFGListFilter.Recommended) ~= 0
        or false
end

-- fallback: newest tier's journal raids by name.
local function JournalRaidsByName()
    local result = {}
    if not (EJ_GetNumTiers and EJ_SelectTier and EJ_GetInstanceByIndex) then return result end
    local previous = EJ_GetCurrentTier and EJ_GetCurrentTier()
    EJ_SelectTier(EJ_GetNumTiers())
    for index = 1, 20 do
        local joinId, label = EJ_GetInstanceByIndex(index, true)
        if not joinId then break end
        result[label] = joinId
    end
    if previous then EJ_SelectTier(previous) end
    return result
end

local function RaidGroups()
    local F = Enum.LFGListFilter
    local success, groups = pcall(C_LFGList.GetAvailableActivityGroups, RAIDS, bit.bor(F.Recommended, F.PvE))
    return success and type(groups) == "table" and groups or {}
end

local function JournalInstance(details, groupName, byName)
    local CEJ = C_EncounterJournal
    local joinId = details
        and details.mapID
        and CEJ
        and CEJ.GetInstanceForGameMap
        and CEJ.GetInstanceForGameMap(details.mapID)
    if joinId then return joinId end
    return groupName and byName()[groupName] or nil
end

local RAID_DIFFS = { 14, 15, 16, 17 }
local function Encounters(joinId)
    local result = {}
    if not (EJ_SelectInstance and EJ_GetEncounterInfoByIndex) then return result end
    local EJ = EncounterJournal
    local prevInst = EJ and EJ.instanceID
    local prevDiff = EJ_GetDifficulty and EJ_GetDifficulty()
    EJ_SelectInstance(joinId)
    for _, diff in ipairs(RAID_DIFFS) do
        if EJ_SetDifficulty and EJ_IsValidInstanceDifficulty and EJ_IsValidInstanceDifficulty(diff) then
            EJ_SetDifficulty(diff)
            break
        end
    end
    for index = 1, 30 do
        local label, _, encID = EJ_GetEncounterInfoByIndex(index)
        if not label then break end
        local iconTex = EJ_GetCreatureInfo and select(5, EJ_GetCreatureInfo(1, encID))
        result[#result + 1] = { key = encID, name = label, icon = iconTex }
    end
    if prevInst then EJ_SelectInstance(prevInst) end
    if prevDiff and EJ_SetDifficulty then EJ_SetDifficulty(prevDiff) end
    return result
end

-- current raid bosses in blizzard's order, nil till the journal has data
-- this season's raids: the season filter, else the journal's newest tier
function Finder.SeasonRaidSets()
    local F = Enum.LFGListFilter
    local groups = {}
    local success, g = pcall(C_LFGList.GetAvailableActivityGroups, RAIDS, bit.bor(F.CurrentSeason, F.PvE))
    if success and type(g) == "table" then
        for _, groupId in ipairs(g) do
            groups[groupId] = true
        end
    end
    local tier = {}
    if EJ_GetNumTiers and EJ_SelectTier and EJ_GetInstanceByIndex then
        local previous = EJ_GetCurrentTier and EJ_GetCurrentTier()
        EJ_SelectTier(EJ_GetNumTiers())
        for index = 1, 20 do
            local joinId = EJ_GetInstanceByIndex(index, true)
            if not joinId then break end
            tier[joinId] = true
        end
        if previous then EJ_SelectTier(previous) end
    end
    return groups, tier
end

local function BuildBosses()
    if not (EJ_SelectInstance and EJ_GetEncounterInfoByIndex) then return nil end
    local seasonGroups, seasonTier = Finder.SeasonRaidSets()
    local byGroup, byTier = {}, {}
    local entries, byAct, seen, raids = {}, {}, {}, {}
    local current = {}
    local nameList
    local function byName()
        nameList = nameList or JournalRaidsByName()
        return nameList
    end
    for _, groupId in ipairs(RaidGroups()) do
        local groupName = C_LFGList.GetActivityGroupInfo(groupId)
        for _, aid in ipairs(C_LFGList.GetAvailableActivities(RAIDS, groupId) or {}) do
            local details = C_LFGList.GetActivityInfoTable(aid)
            local joinId = JournalInstance(details, groupName, byName)
            if joinId then
                byAct[aid] = joinId
                if details and details.isCurrentRaidActivity then current[joinId] = true end
                if seasonGroups[groupId] then byGroup[joinId] = true end
                if seasonTier[joinId] then byTier[joinId] = true end
                if not seen[joinId] then
                    seen[joinId] = true
                    local raidName = EJ_GetInstanceInfo and EJ_GetInstanceInfo(joinId)
                    local n = #entries
                    for _, b in ipairs(Encounters(joinId)) do
                        b.raid, b.raidName = joinId, raidName
                        entries[#entries + 1] = b
                    end
                    if #entries > n then
                        raids[#raids + 1] = { jid = joinId, name = raidName or groupName or "?" }
                    end
                end
            end
        end
    end
    if #entries == 0 then return nil end
    -- none flagged = all count
    wipe(Finder.raidCurrent)
    if next(byGroup) then
        current = byGroup
    elseif next(byTier) then
        current = byTier
    end
    if next(current) then
        for _, raid in ipairs(raids) do
            Finder.raidCurrent[raid.jid] = current[raid.jid] == true
        end
    end
    return entries, byAct, raids
end

-- current season only, older raids are out
Finder.raidCurrent = {}
function Finder.SeasonOnly() return FinderCfg().extraSeasonRaids ~= false end
function Finder.RaidEligible(joinId) return not (Finder.SeasonOnly() and Finder.raidCurrent[joinId] == false) end

-- raids show unless hidden in the raid menu
local function RaidShown(joinId)
    if not Finder.RaidEligible(joinId) then return false end
    local hgt = FinderCfg().raidsHidden
    if not (type(hgt) == "table" and hgt[joinId]) then return true end
    for _, raid in ipairs(raidList or {}) do
        if Finder.RaidEligible(raid.jid) and not hgt[raid.jid] then return false end
    end
    return true
end

function Finder.AnyRaidHidden()
    for _, raid in ipairs(raidList or {}) do
        if Finder.RaidEligible(raid.jid) and not RaidShown(raid.jid) then return true end
    end
    return false
end

local function ChosenBosses()
    local cfg = FinderCfg()
    return type(cfg.bosses) == "table" and next(cfg.bosses) and cfg.bosses or nil
end

local function BossFilterActive() return RaidsCurrent() and ChosenBosses() ~= nil or false end

-- scratch set of a group's killed bosses
Finder.dead = {}
local function BossKeep(resultID, details)
    local acts = details and details.activityIDs
    local activity = type(acts) == "table" and not SecretVal(acts) and acts[1]
    local raid = activity and not SecretVal(activity) and raidByActivity and raidByActivity[activity]
    if not raid then return true end
    local done = C_LFGList.GetSearchResultEncounterInfo(resultID)
    if done and (SecretVal(done) or (canaccesstable and not canaccesstable(done))) then return true end
    local dead = wipe(Finder.dead)
    for _, label in ipairs(done or Finder.EMPTY) do
        if SecretVal(label) then return true end
        dead[label] = true
    end
    -- c.bosses[key]: true = must be alive, "dead" = must be dead
    local chosen, wanted = ChosenBosses(), false
    for _, b in ipairs(bosses or {}) do
        local pick = b.raid == raid and chosen[b.key]
        if pick then
            if (pick == "dead") ~= (dead[b.name] == true) then return false end
            wanted = true
        end
    end
    return wanted
end

-------------------------------------------------------------------------------
-- raids: difficulty and world bosses
-------------------------------------------------------------------------------
local RAID_DIFFS_MENU = {
    { key = "normal", label = PLAYER_DIFFICULTY1 or "Normal" },
    { key = "heroic", label = PLAYER_DIFFICULTY2 or "Heroic" },
    { key = "mythic", label = PLAYER_DIFFICULTY6 or "Mythic" },
}

local function ChosenRaidDiffs()
    local tbl = FinderCfg().raidDiffs
    if type(tbl) ~= "table" then return nil, 0 end
    local count = 0
    for _, skinData in ipairs(RAID_DIFFS_MENU) do
        if tbl[skinData.key] then count = count + 1 end
    end
    return (count > 0 and count < #RAID_DIFFS_MENU) and tbl or nil, count
end

local function HideWorldBosses() return FinderCfg().hideWorldBosses == true end

-- playstyles (generalPlaystyle 1-4).
local PLAYSTYLES = {
    GROUP_FINDER_GENERAL_PLAYSTYLE1 or "Learning",
    GROUP_FINDER_GENERAL_PLAYSTYLE2 or "Relaxed",
    GROUP_FINDER_GENERAL_PLAYSTYLE3 or "Competitive",
    GROUP_FINDER_GENERAL_PLAYSTYLE4 or "Carry Offered",
}

local function ChosenRaidPlaystyles()
    local tbl = FinderCfg().raidPlaystyles
    if type(tbl) ~= "table" then return nil, 0 end
    local count = 0
    for index = 1, #PLAYSTYLES do
        if tbl[index] then count = count + 1 end
    end
    return (count > 0 and count < #PLAYSTYLES) and tbl or nil, count
end

-- dungeon playstyles from the advanced filter; nil when all or none.
local function DungeonPlaystyles(frame)
    local count = 0
    for index = 1, #PLAYSTYLES do
        if frame["generalPlaystyle" .. index] then count = count + 1 end
    end
    return (count > 0 and count < #PLAYSTYLES) and frame or nil, count
end

-- roles (the advanced filter's needs* keys).
local ROLES = {
    { key = "needsTank", label = CludesUI.L("Tank Available") },
    { key = "needsHealer", label = CludesUI.L("Healer Available") },
    { key = "needsDamage", label = CludesUI.L("Damage Available") },
}

local function ChosenRaidRoles()
    local t = FinderCfg().raidRoles
    return type(t) == "table" and next(t) and t or nil
end

local function DungeonRolesSet(frame)
    for _, region in ipairs(ROLES) do
        if frame[region.key] then return true end
    end
    return (frame.needsMyClass or frame.hasTank or frame.hasHealer) and true or false
end

local function RaidListFilterActive()
    return SP
            and SP.categoryID == RAIDS
            and (ChosenRaidDiffs() ~= nil or HideWorldBosses() or ChosenRaidPlaystyles() ~= nil or ChosenRaidRoles() ~= nil or Finder.AnyRaidHidden())
        or false
end

-- difficultyID first since the is*activity flags aren't reliable on raids.
local RAID_DIFF_BY_ID = {
    [14] = "normal",
    [15] = "heroic",
    [16] = "mythic",
    [3] = "normal",
    [4] = "normal",
    [5] = "heroic",
    [6] = "heroic",
    [9] = "normal",
}
Finder.DIFF_WORDS = {
    mythic = PLAYER_DIFFICULTY6 or "Mythic",
    heroic = PLAYER_DIFFICULTY2 or "Heroic",
    normal = PLAYER_DIFFICULTY1 or "Normal",
}
local function ActivityDiffKey(activityInfo)
    local byID = RAID_DIFF_BY_ID[activityInfo.difficultyID]
        or RAID_DIFF_BY_ID[activityInfo.redirectedDifficultyID]
    if byID then return byID end
    if activityInfo.isMythicActivity then return "mythic" end
    if activityInfo.isHeroicActivity then return "heroic" end
    if activityInfo.isNormalActivity then return "normal" end
    -- last resort: the difficulty word in the name.
    local label = activityInfo.fullName
    if type(label) == "string" and not SecretVal(label) then
        for filterKey, word in pairs(Finder.DIFF_WORDS) do
            if label:find(word, 1, true) then return filterKey end
        end
    end
    return nil
end

local function IsWorldBoss(activityInfo)
    local g = activityInfo and activityInfo.groupFinderActivityGroupID
    return activityInfo and activityInfo.categoryID == RAIDS and (g == nil or g == 0) or false
end

local function RaidListKeep(resultID, details)
    local acts = details and details.activityIDs
    local activity = type(acts) == "table" and not SecretVal(acts) and acts[1]
    local activityInfo = activity and not SecretVal(activity) and Finder.ActInfo(activity)
    if not activityInfo then return true end
    if HideWorldBosses() and IsWorldBoss(activityInfo) then return false end
    local joinId = raidByActivity and raidByActivity[activity]
    if joinId and not RaidShown(joinId) then return false end
    local diffs = ChosenRaidDiffs()
    local filterKey = diffs and ActivityDiffKey(activityInfo)
    if filterKey and not diffs[filterKey] then return false end
    local styles = ChosenRaidPlaystyles()
    local ps = styles and details.generalPlaystyle
    if type(ps) == "number" and not SecretVal(ps) and ps >= 1 and ps <= #PLAYSTYLES and not styles[ps] then
        return false
    end
    local roles = ChosenRaidRoles()
    if roles then
        local c = C_LFGList.GetSearchResultMemberCounts(resultID)
        if type(c) == "table" and not SecretVal(c) then
            local num = Finder.Num
            -- match any role
            if mod.ExtraRolesAny and mod.ExtraRolesAny() then
                return (roles.needsTank and (num(c, "TANK_REMAINING") or 1) > 0)
                    or (roles.needsHealer and (num(c, "HEALER_REMAINING") or 1) > 0)
                    or (roles.needsDamage and (num(c, "DAMAGER_REMAINING") or 1) > 0)
                    or false
            end
            if roles.needsTank and (num(c, "TANK_REMAINING") or 1) <= 0 then return false end
            if roles.needsHealer and (num(c, "HEALER_REMAINING") or 1) <= 0 then return false end
            if roles.needsDamage and (num(c, "DAMAGER_REMAINING") or 1) <= 0 then return false end
        end
    end
    return true
end

-------------------------------------------------------------------------------
-- extra filters (filters menu, client side)
-------------------------------------------------------------------------------
Finder.LUST_CLASSES = { SHAMAN = true, MAGE = true, HUNTER = true, EVOKER = true }
Finder.BREZ_CLASSES = { DRUID = true, DEATHKNIGHT = true, WARLOCK = true, PALADIN = true }
Finder.COUNT_ROLES = {
    { key = "TANK", label = CludesUI.L("Tanks") },
    { key = "HEALER", label = CludesUI.L("Healers") },
    { key = "DAMAGER", label = CludesUI.L("DPS") },
}
Finder.COUNT_OPS = {
    { key = "lt", label = "<  " .. CludesUI.L("Less Than") },
    { key = "gt", label = ">  " .. CludesUI.L("More Than") },
    { key = "eq", label = "=  " .. CludesUI.L("Equal To") },
}
Finder.COUNT_OP_LABEL = { lt = "<", gt = ">", eq = "=" }
-- member-count keys for the open slots of each role.
Finder.REMAINING = { TANK = "TANK_REMAINING", HEALER = "HEALER_REMAINING", DAMAGER = "DAMAGER_REMAINING" }
Finder.PARTY = { "party1", "party2", "party3", "party4" }

function Finder.CountRule(roleName)
    local tbl = FinderCfg().roleCounts
    local region = type(tbl) == "table" and tbl[roleName]
    local n = type(region) == "table" and region.on and tonumber(region.n)
    if n then return region.op or "lt", n end
    return nil
end

function Finder.ExtraFilterActive()
    if not SP or (SP.categoryID ~= DUNGEONS and SP.categoryID ~= RAIDS) then return false end
    local cfg = FinderCfg()
    if cfg.partyFit or cfg.notDeclined or cfg.hasLust or cfg.hasBrez then return true end
    if mod.ExtraClassKeep and cfg[SP.categoryID == RAIDS and "raidMyClass" or "extraMyClass"] then
        return true
    end
    if mod.ExtraExprActive and mod.ExtraExprActive() then return true end
    for _, region in ipairs(Finder.COUNT_ROLES) do
        if Finder.CountRule(region.key) then return true end
    end
    return false
end

-- info: the result's readable info, or false when it has none.
function Finder.IsDeclinedResult(ident, details)
    local _, status = C_LFGList.GetApplicationInfo(ident)
    if SecretVal(status) then return false end
    if status == "declined" or status == "declined_full" or status == "declined_delisted" then return true end
    local unitGuid = details and details.partyGUID
    local declines = LFGListFrame and LFGListFrame.declines
    return (declines and unitGuid and not SecretVal(unitGuid) and declines[unitGuid]) and true or false
end

-- your party's roles, nil while one reads secret
function Finder.PartyNeeds(need)
    need.TANK, need.HEALER, need.DAMAGER = 0, 0, 0
    local members = IsInRaid() and 0 or GetNumSubgroupMembers()
    for index = 0, math.min(members, #Finder.PARTY) do
        local roleName, secret = CUI.UnitEffectiveRole(index == 0 and "player" or Finder.PARTY[index])
        if secret then return nil end
        if roleName == "TANK" or roleName == "HEALER" then
            need[roleName] = need[roleName] + 1
        else
            need.DAMAGER = need.DAMAGER + 1
        end
    end
    return need
end

function Finder.ExtraKeep(ident, details, need)
    local cfg = FinderCfg()
    if cfg.notDeclined and Finder.IsDeclinedResult(ident, details) then return false end
    local counts = C_LFGList.GetSearchResultMemberCounts(ident)
    if type(counts) == "table" and not SecretVal(counts) then
        local num = Finder.Num
        if cfg.partyFit and need then
            for roleName, n in pairs(need) do
                local leftX = num(counts, Finder.REMAINING[roleName])
                if leftX and leftX < n then return false end
            end
        end
        -- match any role
        local any = mod.ExtraRolesAny and mod.ExtraRolesAny()
        local anySet, anyHit = false, false
        for _, region in ipairs(Finder.COUNT_ROLES) do
            local op, n = Finder.CountRule(region.key)
            local have = op and num(counts, region.key)
            if have then
                local success = (op == "lt" and have < n)
                    or (op == "gt" and have > n)
                    or (op == "eq" and have == n)
                if any then
                    anySet, anyHit = true, anyHit or success
                elseif not success then
                    return false
                end
            end
        end
        if anySet and not anyHit then return false end
    end
    -- the expressions box
    if mod.ExtraExprKeep and not mod.ExtraExprKeep(ident, details) then return false end
    -- has / missing bloodlust, battle res and your class
    if mod.ExtraClassKeep then
        if not mod.ExtraClassKeep(ident, details, cfg, SP and SP.categoryID == RAIDS) then return false end
    elseif cfg.hasLust or cfg.hasBrez then
        local n = details and details.numMembers
        if type(n) == "number" and not SecretVal(n) then
            local lust, brez = false, false
            for index = 1, n do
                local p = C_LFGList.GetSearchResultPlayerInfo(ident, index)
                local cls = p and p.classFilename
                if cls and not SecretVal(cls) then
                    if Finder.LUST_CLASSES[cls] then lust = true end
                    if Finder.BREZ_CLASSES[cls] then brez = true end
                end
            end
            if cfg.hasLust and not lust then return false end
            if cfg.hasBrez and not brez then return false end
        end
    end
    return true
end

-- results are secret in restricted content: filters stay out of it.
function Finder.ResultsSecret()
    local res = SP and SP.results
    local first = type(res) == "table" and res[1]
    if not first then return false end
    if SecretVal(first) then return true end
    local details = C_LFGList.GetSearchResultInfo(first)
    if not details then return false end
    if SecretVal(details) or (canaccesstable and not canaccesstable(details)) then return true end
    return SecretVal(details.activityIDs) and true or false
end

-- one pass shares secrecy, active filters and party fit's needs (once per frame)
Finder.pass = { needT = { TANK = 0, HEALER = 0, DAMAGER = 0 } }
function Finder.Pass()
    local P = Finder.pass
    local nowTime = GetTime()
    local res = SP and SP.results
    if P.at == nowTime and P.res == res then return P end
    P.at, P.res = nowTime, res
    P.secret = Finder.ResultsSecret()
    P.regions = RegionFilterActive()
    P.delveOn = DelveFilterActive()
    P.bossOn = BossFilterActive()
    P.raidOn = RaidListFilterActive()
    P.extraOn = Finder.ExtraFilterActive()
    P.dimOn = Finder.DimActive()
    P.any = P.regions or P.delveOn or P.bossOn or P.raidOn or P.extraOn or P.dimOn
    P.need = (P.extraOn and FinderCfg().partyFit) and Finder.PartyNeeds(P.needT) or nil
    return P
end
function Finder.NewPass() Finder.pass.at = nil end

-- any picks waiting on our side?
function Finder.DimActive()
    local p = SP and SP.categoryID == DUNGEONS and DimOn() and FinderCfg().dimPicks
    if type(p) ~= "table" then return false end
    return (
        not DungeonsDefault(p)
        or not DiffAllOrNone(p)
        or DungeonPlaystyles(p)
        or DungeonRolesSet(p)
        or (tonumber(p.minimumRating) or 0) > 0
    )
            and true
        or false
end

-- blizzard's search would have done this if it wasn't wide
function Finder.DimKeep(ident, details)
    local p = FinderCfg().dimPicks
    if not details then return true end
    local acts = details.activityIDs
    local activity = type(acts) == "table" and not SecretVal(acts) and acts[1]
    local activityInfo = activity and not SecretVal(activity) and C_LFGList.GetActivityInfoTable(activity)
    if activityInfo and not SecretVal(activityInfo) then
        local groupId = activityInfo.groupFinderActivityGroupID
        if not DungeonsDefault(p) and not SecretVal(groupId) and not Contains(p.activities, groupId) then
            return false
        end
        if not DiffAllOrNone(p) then
            local filterKey = ActivityDiffKey(activityInfo)
            if activityInfo.isMythicPlusActivity then
                filterKey = "difficultyMythicPlus"
            elseif filterKey then
                filterKey = "difficulty" .. filterKey:sub(1, 1):upper() .. filterKey:sub(2)
            end
            if filterKey and not p[filterKey] then return false end
        end
    end
    local min = tonumber(p.minimumRating) or 0
    local score = details.leaderOverallDungeonScore
    if min > 0 and not SecretVal(score) and type(score) == "number" and score < min then return false end
    local ps = details.generalPlaystyle
    if
        DungeonPlaystyles(p)
        and not SecretVal(ps)
        and type(ps) == "number"
        and ps > 0
        and not p["generalPlaystyle" .. ps]
    then
        return false
    end
    if DungeonRolesSet(p) then
        local counts = C_LFGList.GetSearchResultMemberCounts(ident)
        if type(counts) == "table" and not SecretVal(counts) then
            local num = Finder.Num
            if p.hasTank and (num(counts, "TANK") or 1) < 1 then return false end
            if p.hasHealer and (num(counts, "HEALER") or 1) < 1 then return false end
            if p.needsTank and (num(counts, "TANK_REMAINING") or 1) < 1 then return false end
            if p.needsHealer and (num(counts, "HEALER_REMAINING") or 1) < 1 then return false end
            if p.needsDamage and (num(counts, "DAMAGER_REMAINING") or 1) < 1 then return false end
        end
        if p.needsMyClass then
            local _, mine = UnitClass("player")
            local n = details.numMembers
            for index = 1, (type(n) == "number" and not SecretVal(n)) and n or 0 do
                local member = C_LFGList.GetSearchResultPlayerInfo(ident, index)
                local cls = member and member.classFilename
                if cls and not SecretVal(cls) and cls == mine then return false end
            end
        end
    end
    return true
end

-- visibility switched: move the picks to where they now belong
function mod.DimFiltersChanged()
    if not SP then return end
    local frame = C_LFGList.GetAdvancedFilter()
    if not frame then return end
    local cfg = FinderCfg()
    if DimOn() then
        cfg.dimPicks = Picks(frame)
        Widen(frame)
    else
        local p = cfg.dimPicks
        if type(p) == "table" then
            for _, key in ipairs(PICK_KEYS) do
                frame[key] = p[key]
            end
        end
        cfg.dimPicks = nil
    end
    C_LFGList.SaveAdvancedFilter(frame)
    Finder.Remember(frame)
    pending = true
    Paint()
    PaintRefresh()
end

-- does a group pass the client-side filters? info: readable info, false if none,
-- nil to fetch it
function Finder.PassesFilters(ident, details)
    local P = Finder.Pass()
    if not SP or P.secret or not P.any then return true end
    local cfg = FinderCfg()
    local _, appStatus = C_LFGList.GetApplicationInfo(ident)
    if SecretVal(appStatus) then return true end
    if details == nil then details = ResultInfo(ident) or false end
    if appStatus and appStatus ~= "none" then
        -- applied groups stay lit, unless declined with not declined on.
        return not (P.extraOn and cfg.notDeclined and Finder.IsDeclinedResult(ident, details))
    end
    if P.dimOn and not Finder.DimKeep(ident, details) then return false end
    if P.regions then
        local regionFrame = LeaderRegion(details)
        if regionFrame ~= nil and not ChosenRegions()[regionFrame] then return false end
    end
    if P.delveOn and not DelveKeep(details) then return false end
    if P.bossOn and not BossKeep(ident, details) then return false end
    if P.raidOn and not RaidListKeep(ident, details) then return false end
    if P.extraOn and not Finder.ExtraKeep(ident, details, P.need) then return false end
    return true
end

-- read-only filter checks for our results list
mod.ExtraPasses = function(ident) return Finder.PassesFilters(ident) end
mod.ExtraResultsSecret = function() return Finder.ResultsSecret() end

-- filters changed: re-fade the visible rows, no search.
function Finder.RefilterEntry(record)
    local ident = record.resultID
    if ident then record:SetAlpha(Finder.PassesFilters(ident) and 1 or Finder.DIM_ALPHA) end
end
local function RunFilters()
    Finder.NewPass()
    if mod.ExtraRefilter then mod.ExtraRefilter() end -- our results list
    if not (SP and SP:IsVisible()) then return end
    -- blizzard's rows hidden under ours stay as they are
    if mod.OwnListActive and mod.OwnListActive() then return end
    local checkBox = SP.ScrollBox
    if checkBox and checkBox.ForEachFrame then checkBox:ForEachFrame(Finder.RefilterEntry) end
end

-------------------------------------------------------------------------------
-- result rows and tooltip
-------------------------------------------------------------------------------
local function Opt(filterKey)
    local val = FinderCfg()[filterKey]
    if val == nil then return true end
    return val and true or false
end

local seenResults, prevResults = {}, nil -- latest / previous search's result IDs
local prevCategory

-- spec icons by class + spec name (the search API only gives names).
local specIcon, specIconAny
local function SpecIcon(classFile, specName)
    if not specName then return nil end
    if not specIcon then
        specIcon, specIconAny = {}, {}
        for c = 1, (GetNumClasses and GetNumClasses() or 0) do
            local _, file, classID = GetClassInfo(c)
            if file and classID then
                specIcon[file] = {}
                for sx = 1, 5 do
                    local ident, label, _, iconTex = GetSpecializationInfoForClassID(classID, sx)
                    if not ident then break end
                    if label then
                        specIcon[file][label] = iconTex
                        specIconAny[label] = specIconAny[label] or iconTex
                    end
                end
            end
        end
    end
    return (specIcon[classFile] and specIcon[classFile][specName]) or specIconAny[specName]
end

-- locked to this activity's instance and difficulty?
local function LockedOut(activityInfo, resultID)
    if not (activityInfo and activityInfo.mapID and GetNumSavedInstances) then return false end
    for index = 1, GetNumSavedInstances() do
        local _, _, _, diffID, locked, _, _, _, _, _, numBosses, _, _, instanceID =
            GetSavedInstanceInfo(index)
        if locked and instanceID == activityInfo.mapID and diffID == activityInfo.difficultyID then
            local perBoss = (activityInfo.maxNumPlayers or 5) > 5 and diffID ~= 16
            if not perBoss then return true end
            if not (GetSavedInstanceEncounterInfo and resultID) then return false end
            local done = C_LFGList.GetSearchResultEncounterInfo(resultID)
            if done and (SecretVal(done) or (canaccesstable and not canaccesstable(done))) then
                return false
            end
            local dead = wipe(Finder.dead)
            for _, label in ipairs(done or Finder.EMPTY) do
                if SecretVal(label) then return false end
                dead[label] = true
            end
            local anyAlive = false
            for jdx = 1, (tonumber(numBosses) or 0) do
                local boss, _, killed = GetSavedInstanceEncounterInfo(index, jdx)
                if boss and not dead[boss] then
                    anyAlive = true
                    if not killed then return false end
                end
            end
            return anyAlive
        end
    end
    return false
end

-- raider.io's api, looked up once (each global read logs a taint line)
local rioApi
local function RatingColor(score)
    if rioApi == nil then rioApi = _G.RaiderIO or false end
    if Opt("rioRatingColors") and rioApi and rioApi.GetScoreColor then
        local success, red, green, blue = pcall(rioApi.GetScoreColor, score)
        if success and type(red) == "number" then return red, green, blue end
    end
    local color = C_ChallengeMode
        and C_ChallengeMode.GetDungeonScoreRarityColor
        and C_ChallengeMode.GetDungeonScoreRarityColor(score)
    if color then return color.r, color.g, color.b end
    return 1, 1, 1
end

local ROLE_BY_ATLAS
local function AtlasRole(atlas)
    if not ROLE_BY_ATLAS then
        ROLE_BY_ATLAS = {
            ["groupfinder-icon-role-micro-tank"] = "TANK",
            ["groupfinder-icon-role-micro-heal"] = "HEALER",
            ["groupfinder-icon-role-micro-dps"] = "DAMAGER",
        }
        for roleName, a in pairs(LFG_LIST_GROUP_DATA_ATLASES or {}) do
            if roleName == "TANK" or roleName == "HEALER" or roleName == "DAMAGER" then
                ROLE_BY_ATLAS[a] = roleName
            end
        end
    end
    return atlas and ROLE_BY_ATLAS[atlas]
end
local MISSING_ATLAS = {
    TANK = "groupfinder-icon-role-micro-tank",
    HEALER = "groupfinder-icon-role-micro-heal",
    DAMAGER = "groupfinder-icon-role-micro-dps",
}

-- our own drawing over one of blizzard's role icons.
local function IconLayer(iconTex)
    local skinData = FFD[iconTex]
    if skinData then return skinData end
    skinData = {}
    FFD[iconTex] = skinData
    local frame = CreateFrame("Frame", nil, iconTex)
    frame:SetAllPoints(iconTex)
    frame:SetFrameLevel(iconTex:GetFrameLevel() + 2)
    frame:EnableMouse(false)
    skinData.frame = frame
    skinData.circle = frame:CreateTexture(nil, "ARTWORK", nil, 1)
    skinData.circle:SetSize(16, 16)
    skinData.circle:SetPoint("CENTER")
    skinData.ring = frame:CreateTexture(nil, "ARTWORK", nil, 1)
    skinData.ring:SetSize(18, 18)
    skinData.ring:SetPoint("CENTER")
    skinData.spec = frame:CreateTexture(nil, "ARTWORK", nil, 2)
    skinData.spec:SetSize(16, 16)
    skinData.spec:SetPoint("CENTER")
    skinData.spec:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- past the icon art's own border
    for _, texture in ipairs({ skinData.ring, skinData.spec }) do
        local mask = frame.CreateMaskTexture and frame:CreateMaskTexture()
        if mask then
            mask:SetTexture(
                "Interface\\CharacterFrame\\TempPortraitAlphaMask",
                "CLAMPTOBLACKADDITIVE",
                "CLAMPTOBLACKADDITIVE"
            )
            mask:SetAllPoints(texture)
            texture:AddMaskTexture(mask)
        end
    end
    skinData.role = frame:CreateTexture(nil, "ARTWORK", nil, 3)
    skinData.role:SetSize(12, 12)
    skinData.role:SetPoint("CENTER")
    skinData.full = frame:CreateTexture(nil, "ARTWORK", nil, 1)
    skinData.full:SetAllPoints(frame)
    skinData.crown = frame:CreateTexture(nil, "OVERLAY")
    skinData.crown:SetAtlas("groupfinder-icon-leader", false)
    skinData.crown:SetSize(10, 6)
    skinData.crown:SetPoint("BOTTOM", iconTex, "TOP", 0, 1)
    -- blizzard's leaver mark is under our layer, so it's drawn again up here
    skinData.leaver = frame:CreateTexture(nil, "OVERLAY", nil, 1)
    skinData.leaver:SetAtlas("groupfinder-icon-leaver", false)
    skinData.leaver:SetSize(12, 12)
    skinData.leaver:SetPoint("TOPRIGHT", iconTex, "TOPRIGHT", 4, 2)
    return skinData
end

local function ClearLayer(skinData)
    skinData.circle:Hide()
    skinData.ring:Hide()
    skinData.spec:Hide()
    skinData.role:Hide()
    skinData.full:Hide()
    skinData.crown:Hide()
    skinData.leaver:Hide()
end

-- clear our layers on rows we skip (recycled rows keep old art)
function Finder.ClearIcons(record)
    local enum = record.DataDisplay and record.DataDisplay.Enumerate
    local icons = enum and enum.Icons
    if not icons then return end
    for index = 1, #icons do
        local skinData = FFD[icons[index]]
        if skinData then ClearLayer(skinData) end
    end
end

Finder.members, Finder.used, Finder.missing = {}, {}, {}
Finder.ROLE_RANK = { TANK = 1, HEALER = 2, DAMAGER = 3 }
Finder.ROLE_ORDER = { "TANK", "HEALER", "DAMAGER" }
Finder.FIVE_SLOTS = { TANK = 1, HEALER = 1, DAMAGER = 3 } -- a 5-player group's roles
function Finder.ByOrder(posX, posY) return posX._cmOrder < posY._cmOrder end

local function DecorateIcons(record, resultID, details, activityInfo)
    local enum = record.DataDisplay and record.DataDisplay.Enumerate
    local icons = enum and enum.Icons
    if not icons then return end
    local isShown = enum:IsShown()
    -- none = no missing roles
    local crownOn, specOn = Opt("leaderCrown"), Opt("specIcons")
    local missOn = not (mod.OwnListGet and mod.OwnListGet("missingIcons") == "none")
    local disabled = (not SecretVal(details.isDelisted) and details.isDelisted) and true or false
    -- sort like blizzard fills its icons
    local members = wipe(Finder.members)
    local n = details.numMembers
    if isShown and (crownOn or specOn) and type(n) == "number" and not SecretVal(n) then
        for index = 1, n do
            local p = C_LFGList.GetSearchResultPlayerInfo(resultID, index)
            if p and not SecretVal(p.classFilename) and not SecretVal(p.assignedRole) then
                members[#members + 1] = p
            end
        end
        for key, p in ipairs(members) do
            p._cmOrder = (Finder.ROLE_RANK[p.assignedRole] or 4) * 100 + key
        end
        table.sort(members, Finder.ByOrder)
    end
    local maxN = activityInfo and activityInfo.maxNumPlayers or 0
    local counts = isShown and missOn and maxN == 5 and C_LFGList.GetSearchResultMemberCounts(resultID)
    local missing
    if type(counts) == "table" and not SecretVal(counts) then
        missing = wipe(Finder.missing)
        for _, roleName in ipairs(Finder.ROLE_ORDER) do
            local have = counts[roleName]
            if SecretVal(have) then
                missing = nil
                break
            end
            for _ = 1, math.max(0, Finder.FIVE_SLOTS[roleName] - (tonumber(have) or 0)) do
                missing[#missing + 1] = roleName
            end
        end
    end
    local used, mi = wipe(Finder.used), 0
    -- right to left like blizzard; empty slots end up leftmost.
    for index = #icons, 1, -1 do
        local iconTex = icons[index]
        local skinData = IconLayer(iconTex)
        ClearLayer(skinData)
        local live = isShown and iconTex:IsShown()
        local cc, ri, backdrop = iconTex.ClassCircle, iconTex.RoleIcon, iconTex.RoleIconWithBackground
        local ccAtlas = live and cc and cc:IsShown() and cc:GetAtlas()
        local riAtlas = live and ri and ri:IsShown() and ri:GetAtlas()
        local bgAtlas = live and backdrop and backdrop:IsShown() and backdrop:GetAtlas()
        if live and (SecretVal(ccAtlas) or SecretVal(riAtlas) or SecretVal(bgAtlas)) then
            -- restricted row: its art reads secret, blizzard's stays
            local a = disabled and 0.5 or 1
            if cc then cc:SetAlpha(a) end
            if ri then ri:SetAlpha(a) end
            if backdrop then backdrop:SetAlpha(a) end
        elseif live then
            if bgAtlas == "groupfinder-icon-emptyslot" then
                if cc then cc:SetAlpha(0) end
                if ri then ri:SetAlpha(0) end
                if backdrop then backdrop:SetAlpha(0) end
                mi = mi + 1
                local roleName = missing and missing[mi]
                if roleName then
                    skinData.role:SetAtlas(MISSING_ATLAS[roleName], false)
                    skinData.role:SetDesaturated(true)
                    skinData.role:SetAlpha(0.6)
                    skinData.role:Show()
                else
                    skinData.full:SetAtlas(bgAtlas, false)
                    skinData.full:SetDesaturated(disabled)
                    skinData.full:SetAlpha(disabled and 0.5 or 1)
                    skinData.full:Show()
                end
            else
                local roleName, class
                if ccAtlas then
                    class = ccAtlas:match("^groupfinder%-icon%-class%-color%-(.+)$")
                    roleName = AtlasRole(riAtlas)
                else
                    roleName = AtlasRole(bgAtlas)
                end
                -- match role + class, then role, then whoever's next.
                local m
                for pass = 1, 3 do
                    for key, p in ipairs(members) do
                        if
                            not used[key]
                            and (
                                pass == 3
                                or (
                                    p.assignedRole == roleName
                                    and (pass == 2 or not class or p.classFilename == class)
                                )
                            )
                        then
                            used[key] = true
                            m = p
                            break
                        end
                    end
                    if m then break end
                end
                if not specOn then
                    -- spec icons off: the game's icons stay, only the crown is ours
                    local a = disabled and 0.5 or 1
                    if cc then cc:SetAlpha(a) end
                    if ri then ri:SetAlpha(a) end
                    if backdrop then backdrop:SetAlpha(a) end
                else
                    if cc then cc:SetAlpha(0) end
                    if ri then ri:SetAlpha(0) end
                    if backdrop then backdrop:SetAlpha(0) end
                    local specInfo = m
                        and m.specName
                        and not SecretVal(m.specName)
                        and SpecIcon(m.classFilename, m.specName)
                    if ccAtlas then
                        skinData.circle:SetAtlas(ccAtlas, false)
                        skinData.circle:SetDesaturated(disabled)
                        skinData.circle:SetAlpha(disabled and 0.5 or 1)
                        skinData.circle:Show()
                        if specInfo then
                            skinData.circle:Hide()
                            local red, green, blue = ThemeBorder()
                            skinData.ring:SetColorTexture(red, green, blue, disabled and 0.5 or 1)
                            skinData.ring:Show()
                            skinData.spec:SetTexture(specInfo)
                            skinData.spec:SetDesaturated(disabled)
                            skinData.spec:SetAlpha(disabled and 0.5 or 1)
                            skinData.spec:Show()
                        elseif riAtlas then
                            skinData.role:SetAtlas(riAtlas, false)
                            skinData.role:SetDesaturated(disabled)
                            skinData.role:SetAlpha(disabled and 0.5 or 1)
                            skinData.role:Show()
                        end
                    elseif bgAtlas then
                        if specInfo then
                            skinData.circle:Hide()
                            local red, green, blue = ThemeBorder()
                            skinData.ring:SetColorTexture(red, green, blue, disabled and 0.5 or 1)
                            skinData.ring:Show()
                            skinData.spec:SetTexture(specInfo)
                            skinData.spec:SetDesaturated(disabled)
                            skinData.spec:SetAlpha(disabled and 0.5 or 1)
                            skinData.spec:Show()
                        else
                            skinData.full:SetAtlas(bgAtlas, false)
                            skinData.full:SetDesaturated(disabled)
                            skinData.full:SetAlpha(disabled and 0.5 or 1)
                            skinData.full:Show()
                        end
                    end
                    local lv = iconTex.LeaverIcon
                    local leaver = lv and lv:IsShown()
                    if not SecretVal(leaver) and leaver then
                        skinData.leaver:SetDesaturated(disabled)
                        skinData.leaver:SetAlpha(disabled and 0.5 or 1)
                        skinData.leaver:Show()
                    end
                end
                if m and crownOn and not SecretVal(m.isLeader) and m.isLeader then
                    skinData.crown:SetDesaturated(disabled)
                    skinData.crown:Show()
                end
            end
        end
    end
end

-------------------------------------------------------------------------------
-- cancel oldest application
-------------------------------------------------------------------------------
-- the pending application closest to timing out.
function Finder.OldestApplication()
    local oldest, leftX = nil, math.huge
    for _, ident in ipairs(C_LFGList.GetApplications() or {}) do
        local _, status, pendingStatus, duration = C_LFGList.GetApplicationInfo(ident)
        if status == "applied" and not pendingStatus and type(duration) == "number" and duration < leftX then
            oldest, leftX = ident, duration
        end
    end
    return oldest
end

-- at the limit and hovering a group you could sign up to.
function Finder.ShouldCancelOldest(resultID)
    if not FinderCfg().cancelOldest or not resultID or Finder.ResultsSecret() then return false end
    local _, isActive = C_LFGList.GetNumApplications()
    if type(isActive) ~= "number" or isActive < (MAX_LFG_LIST_APPLICATIONS or 5) then return false end
    local _, status, pendingStatus = C_LFGList.GetApplicationInfo(resultID)
    if status ~= "none" or pendingStatus then return false end
    local details = ResultInfo(resultID)
    return details ~= nil and not SecretVal(details.isDelisted) and not details.isDelisted
end

-- same for our rows
function mod.GFCancelOldest(resultID)
    if not Finder.ShouldCancelOldest(resultID) then return end
    local oldest = Finder.OldestApplication()
    if oldest then C_LFGList.CancelApplication(oldest) end
end

-- rows decorate only while the panel shows
local function DecorateEntry(record)
    local resultID = record and record.resultID
    if not resultID or not SP or not SP:IsVisible() then return end
    -- our results list covers blizzard's: its hidden rows are left alone
    -- (ns.RedecorateRows catches them up when it hands the panel back)
    if mod.OwnListActive and mod.OwnListActive() then return end
    local frameData = FFD[record]
    if not frameData then
        frameData = {}
        FFD[record] = frameData
        local frame = CreateFrame("Frame", nil, record)
        frame:SetAllPoints(record)
        frame:SetFrameLevel(record:GetFrameLevel() + 3)
        frame:EnableMouse(false)
        frameData.rating = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        frameData.rating:SetJustifyH("RIGHT")
        record:HookScript("OnClick", function(self, btnFrame)
            if btnFrame ~= "LeftButton" or not Finder.ShouldCancelOldest(self.resultID) then return end
            local oldest = Finder.OldestApplication()
            if oldest then C_LFGList.CancelApplication(oldest) end
        end)
    end
    frameData.rating:Hide()
    record:SetAlpha(1)
    Finder.CancelLook(record)
    -- secret results: leave the row alone.
    if Finder.Pass().secret then
        Finder.ClearIcons(record)
        return
    end
    local details = ResultInfo(resultID)
    -- filtered out: faded
    if not Finder.PassesFilters(resultID, details or false) then record:SetAlpha(Finder.DIM_ALPHA) end
    if not details then
        Finder.ClearIcons(record)
        return
    end
    local acts = details.activityIDs
    local activity = type(acts) == "table" and not SecretVal(acts) and acts[1]
    local activityInfo = activity and not SecretVal(activity) and Finder.ActInfo(activity)

    -- name colour (blizzard already reds declined ones).
    local delisted, censored = details.isDelisted, details.censored
    if SecretVal(delisted) or SecretVal(censored) then
        Finder.ClearIcons(record)
        return
    end
    if FinderCfg().nameColors == true and record.Name and not delisted and not censored then
        local _, appStatus = C_LFGList.GetApplicationInfo(resultID)
        local declined = appStatus == "declined"
            or appStatus == "declined_full"
            or appStatus == "declined_delisted"
        if declined or LockedOut(activityInfo, resultID) then
            record.Name:SetTextColor(1, 0.25, 0.25)
        elseif prevResults and not prevResults[resultID] and (appStatus == "none" or appStatus == nil) then
            record.Name:SetTextColor(0.3, 1, 0.3)
        end
    end

    local enum = record.DataDisplay and record.DataDisplay.Enumerate
    local score = details.leaderOverallDungeonScore
    if
        Opt("leaderRating")
        and enum
        and enum:IsShown()
        and record.DataDisplay:IsShown()
        and type(score) == "number"
        and not SecretVal(score)
        and score > 0
    then
        local n = activityInfo and activityInfo.maxNumPlayers or 5
        local leftX = enum.Icons and enum.Icons[math.min(n, #enum.Icons)]
        if leftX then
            frameData.rating:ClearAllPoints()
            frameData.rating:SetPoint("RIGHT", leftX, "LEFT", -4, 0)
            frameData.rating:SetFormattedText("%d", math.floor(score))
            frameData.rating:SetTextColor(RatingColor(score))
            frameData.rating:Show()
        end
    end

    -- scale the icon strip and trim names to fit (out of combat only)
    local scale = math.max(1, math.min(2, (tonumber(FinderCfg().iconSize) or 125) / 100))
    if enum and enum.SetScale and InCombatLockdown() then
        Finder.Defer("rows", Finder.Redecorate)
    elseif enum and enum.SetScale then
        enum:SetScale(scale)
        local extra = math.floor((scale - 1) * 102 + 0.5) -- 5 icons 18 apart + 12 gap
        if extra > 0 then
            local actName = record.ActivityName
            if actName then actName:SetWidth(176 - extra) end
            local label = record.Name
            if label and not censored then
                local success, wid = pcall(label.GetWidth, label)
                local cap = (record.isApplication and 165 or 176) - extra
                if success and type(wid) == "number" and not SecretVal(wid) and wid > cap then
                    label:SetWidth(cap)
                end
            end
        end
    end

    DecorateIcons(record, resultID, details, activityInfo)
end

-- our rows use the same settings
mod.GFRatingColor = RatingColor
mod.GFOpt = Opt
mod.GFSpecIcon = SpecIcon
-- the name colour a row gets (nil = blizzard's own): red when declined or
-- locked out, green when new since the last search
function mod.GFNameColor(resultID, details, activityInfo)
    if FinderCfg().nameColors ~= true then return nil end
    local delisted, censored = details.isDelisted, details.censored
    if SecretVal(delisted) or SecretVal(censored) or delisted or censored then return nil end
    local _, appStatus = C_LFGList.GetApplicationInfo(resultID)
    if SecretVal(appStatus) then return nil end
    local declined = appStatus == "declined"
        or appStatus == "declined_full"
        or appStatus == "declined_delisted"
    if declined or LockedOut(activityInfo, resultID) then return 1, 0.25, 0.25 end
    if prevResults and not prevResults[resultID] and (appStatus == "none" or appStatus == nil) then
        return 0.3, 1, 0.3
    end
    return nil
end

-- display settings changed: redecorate the visible rows.
function Finder.Redecorate()
    Finder.NewPass()
    if mod.OwnListPreviewPaint then mod.OwnListPreviewPaint() end
    if not (SP and SP:IsVisible()) then return end
    local checkBox = SP.ScrollBox
    if checkBox and checkBox.ForEachFrame then checkBox:ForEachFrame(DecorateEntry) end
    if mod.ExtraRedecorate then mod.ExtraRedecorate() end
end

-- our results list handed the panel back: blizzard's rows take their look
function mod.RedecorateRows()
    Finder.NewPass()
    if not (SP and SP:IsVisible()) then return end
    local checkBox = SP.ScrollBox
    if checkBox and checkBox.ForEachFrame then checkBox:ForEachFrame(DecorateEntry) end
end

-- tooltip hint while a click would cancel your oldest application.
function Finder.CancelHint(tooltip, resultID)
    if not (tooltip and tooltip.IsShown and tooltip:IsShown()) or not Finder.ShouldCancelOldest(resultID) then
        return
    end
    tooltip:AddLine(" ")
    tooltip:AddLine(CludesUI.L("Click: cancel your oldest application to sign up here"), 1, 0.35, 0.35, true)
    tooltip:Show()
end

-- member list in the tooltip, tanks then healers then dps.
local ROLE_ICON = {
    TANK = "groupfinder-icon-role-micro-tank",
    HEALER = "groupfinder-icon-role-micro-heal",
    DAMAGER = "groupfinder-icon-role-micro-dps",
}
local function AddClassesByRole(tooltip, resultID)
    if not Opt("classTooltip") or not (tooltip and tooltip.IsShown and tooltip:IsShown()) then return end
    if Finder.ResultsSecret() then return end
    local details = ResultInfo(resultID)
    if not details or SecretVal(details.isDelisted) or details.isDelisted then return end
    local acts = details.activityIDs
    local activity = type(acts) == "table" and not SecretVal(acts) and acts[1]
    local activityInfo = activity and not SecretVal(activity) and Finder.ActInfo(activity)
    if not activityInfo then return end
    local n = details.numMembers
    if type(n) ~= "number" or SecretVal(n) or n < 1 then return end
    local players = {}
    for index = 1, n do
        players[index] = C_LFGList.GetSearchResultPlayerInfo(resultID, index) or false
    end
    local DT = Enum.LFGListDisplayType
    Finder.AddMembers(
        tooltip,
        players,
        DT and (activityInfo.displayType == DT.RoleEnumerate or activityInfo.displayType == DT.ClassEnumerate)
    )
end

-- the member lines from player info tables (the settings preview hands its own)
function Finder.AddMembers(tooltip, players, enumerate)
    local byRole = { TANK = {}, HEALER = {}, DAMAGER = {} }
    for _, p in ipairs(players) do
        local roleName, class = p and p.assignedRole, p and p.classFilename
        if roleName and class and not SecretVal(roleName) and not SecretVal(class) and byRole[roleName] then
            local entries = byRole[roleName]
            entries[#entries + 1] = p
        end
    end
    -- dungeons/arenas already list roles and classes, so just add the names.
    if enumerate then
        local nameList = {}
        for _, roleName in ipairs(Finder.ROLE_ORDER) do
            for _, p in ipairs(byRole[roleName]) do
                local label = p.name and not SecretVal(p.name) and p.name
                if label then
                    local colour = RAID_CLASS_COLORS[p.classFilename]
                    nameList[#nameList + 1] = (colour and colour.colorStr)
                            and ("|c" .. colour.colorStr .. label .. "|r")
                        or label
                end
            end
        end
        if #nameList == 0 then return end
        tooltip:AddLine(" ")
        tooltip:AddLine(
            CludesUI.L("Names:") .. " " .. table.concat(nameList, Finder.DIM_HEX .. ",|r "),
            1,
            0.82,
            0,
            true
        )
        tooltip:Show()
        return
    end
    local added = false
    for _, roleName in ipairs(Finder.ROLE_ORDER) do
        for _, p in ipairs(byRole[roleName]) do
            if not added then
                tooltip:AddLine(" ")
                added = true
            end
            local colour = RAID_CLASS_COLORS[p.classFilename] or NORMAL_FONT_COLOR
            local className = (not SecretVal(p.className) and p.className)
                or (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[p.classFilename])
                or p.classFilename
            local specInfo = p.specName and not SecretVal(p.specName) and p.specName
            local iconTex = CreateAtlasMarkup and CreateAtlasMarkup(ROLE_ICON[roleName], 12, 12) or ""
            local crown = (p.isLeader and CreateAtlasMarkup)
                    and (" " .. CreateAtlasMarkup("groupfinder-icon-leader", 12, 8))
                or ""
            local leftX = iconTex .. " " .. (specInfo and (specInfo .. " ") or "") .. className .. crown
            local label = p.name and not SecretVal(p.name) and p.name or ""
            tooltip:AddDoubleLine(leftX, label, colour.r, colour.g, colour.b, colour.r, colour.g, colour.b)
        end
    end
    if added then tooltip:Show() end
end
mod.GFTooltipMembers = Finder.AddMembers

local ITEM_H, CHECK_SZ, ITEM_FONT = 20, 12, 9

local function ThemeFill()
    local S = WindowSkin()
    local T = S and S.Theme
    if T and T.bgR then return T.bgR, T.bgG, T.bgB end
    return 0.08, 0.08, 0.08
end

local function MenuItem(hostFrame, posY, textValue, onClick)
    local entry = CreateFrame("Button", nil, hostFrame)
    entry:SetHeight(ITEM_H)
    entry:SetPoint("TOPLEFT", hostFrame, "TOPLEFT", 1, -posY)
    entry:SetPoint("TOPRIGHT", hostFrame, "TOPRIGHT", -1, -posY)
    local callback = CreateFrame("Frame", nil, entry)
    callback:SetSize(CHECK_SZ, CHECK_SZ)
    callback:SetPoint("LEFT", entry, "LEFT", 8, 0)
    local cbBg = callback:CreateTexture(nil, "BACKGROUND")
    cbBg:SetAllPoints()
    cbBg:SetColorTexture(0.12, 0.12, 0.12, 1)
    entry.ring = CUI.MakeBorder(callback, 0.25, 0.25, 0.25, 0.6, CUI.PanelPP)
    entry.fill = callback:CreateTexture(nil, "ARTWORK")
    entry.fill:SetPoint("TOPLEFT", callback, "TOPLEFT", 3, -3)
    entry.fill:SetPoint("BOTTOMRIGHT", callback, "BOTTOMRIGHT", -3, 3)
    local tR, tG, tB, tA = CUI.TEXT_DIM_R, CUI.TEXT_DIM_G, CUI.TEXT_DIM_B, CUI.TEXT_DIM_A
    entry.label = entry:CreateFontString(nil, "OVERLAY")
    Finder.Font(entry.label, ITEM_FONT)
    entry.label:SetPoint("LEFT", callback, "RIGHT", 7, 0)
    entry.label:SetPoint("RIGHT", entry, "RIGHT", -4, 0)
    entry.label:SetJustifyH("LEFT")
    entry.label:SetWordWrap(false)
    entry.label:SetText(textValue)
    entry.label:SetTextColor(tR, tG, tB, tA)
    local highlight = entry:CreateTexture(nil, "ARTWORK", nil, -1)
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0)
    entry:SetScript("OnEnter", function()
        entry.label:SetTextColor(1, 1, 1, 1)
        highlight:SetColorTexture(1, 1, 1, CUI.DD_ITEM_HL_A)
    end)
    entry:SetScript("OnLeave", function()
        entry.label:SetTextColor(tR, tG, tB, tA)
        highlight:SetColorTexture(1, 1, 1, 0)
    end)
    entry:SetScript("OnClick", onClick)
    -- dimmed + unclickable
    function entry:SetDimmed(off)
        self:EnableMouse(not off)
        self:SetAlpha(off and 0.35 or 1)
    end
    function entry:SetChecked(isOn)
        local red, green, blue = AccentRGB()
        self.fill:SetColorTexture(red, green, blue, 1)
        self.fill:SetShown(isOn)
        if isOn then
            self.ring:SetColor(red, green, blue, 0.8)
        else
            self.ring:SetColor(0.25, 0.25, 0.25, 0.6)
        end
    end
    return entry
end

-- section title, with a divider above all but the first.
-- menu dividers: one screen pixel tall at the window's scale, fitted again each
-- time their menu shows (the window can be rescaled in between)
local hairlines = {} -- parent -> its dividers
local function FitHairline(texture)
    local es = texture:GetParent():GetEffectiveScale()
    if es and es > 0 then texture:SetHeight(CUI.PP.perfect / es) end
end
function Finder.Hairline(texture)
    local p = texture:GetParent()
    local entries = hairlines[p]
    if not entries then
        entries = {}
        hairlines[p] = entries
        p:HookScript("OnShow", function()
            for _, t in ipairs(entries) do
                FitHairline(t)
            end
        end)
    end
    entries[#entries + 1] = texture
    FitHairline(texture)
end
mod.GFHairline = Finder.Hairline

local function AddSection(menu, posY, title)
    if posY > 4 then
        local div = menu:CreateTexture(nil, "ARTWORK")
        Finder.Hairline(div)
        div:SetColorTexture(1, 1, 1, 0.10)
        div:SetPoint("TOPLEFT", menu, "TOPLEFT", 10, -posY - 3)
        div:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -10, -posY - 3)
        posY = posY + 7
    else
        posY = posY + 2
    end
    local fontStr = menu:CreateFontString(nil, "OVERLAY")
    Finder.Font(fontStr, ITEM_FONT)
    fontStr:SetTextColor(0.55, 0.55, 0.55, 1)
    fontStr:SetJustifyH("LEFT")
    fontStr:SetPoint("TOPLEFT", menu, "TOPLEFT", 9, -posY - 2)
    fontStr:SetText(title)
    return posY + 14
end

-- playstyles: dungeons apply on search again, raids right away
local function AddPlaystyleItems(menu, posY, raids)
    posY = AddSection(menu, posY, CludesUI.L("Playstyle"))
    for index, labelText in ipairs(PLAYSTYLES) do
        menu.items["style_" .. index] = MenuItem(menu, posY, labelText, function()
            if raids then
                local cfg = FinderCfg()
                if type(cfg.raidPlaystyles) ~= "table" then cfg.raidPlaystyles = {} end
                cfg.raidPlaystyles[index] = (not cfg.raidPlaystyles[index]) or nil
                local _, n = ChosenRaidPlaystyles()
                if n == #PLAYSTYLES then wipe(cfg.raidPlaystyles) end
                RunFilters()
                Paint()
            else
                local frame = Finder.GetFilter()
                local filterKey = "generalPlaystyle" .. index
                if DungeonPlaystyles(frame) == nil then
                    for k = 1, #PLAYSTYLES do
                        frame["generalPlaystyle" .. k] = (k == index)
                    end
                else
                    frame[filterKey] = not frame[filterKey]
                    local _, n = DungeonPlaystyles(frame)
                    if n == 0 or n == #PLAYSTYLES then
                        for k = 1, #PLAYSTYLES do
                            frame["generalPlaystyle" .. k] = true
                        end
                    end
                end
                Apply(frame)
            end
        end)
        posY = posY + ITEM_H
    end
    return posY
end

local function PaintPlaystyleItems(menu, raids)
    local chosen
    if raids then
        chosen = ChosenRaidPlaystyles()
    else
        chosen = DungeonPlaystyles(Finder.GetFilter())
    end
    for index = 1, #PLAYSTYLES do
        local entry = menu.items["style_" .. index]
        if entry then
            local isOn
            if raids then
                isOn = chosen ~= nil and chosen[index] == true
            else
                isOn = chosen ~= nil and chosen["generalPlaystyle" .. index] == true
            end
            entry:SetChecked(isOn)
        end
    end
end

local function AddRoleItems(menu, posY, raids)
    posY = AddSection(menu, posY, CludesUI.L("Roles"))
    -- helpers for our rows
    local K = mod.ExtraClassRows
        and {
            Cfg = FinderCfg,
            Refilter = RunFilters,
            Paint = Paint,
            Font = Finder.Font,
            ITEM_H = ITEM_H,
            ITEM_FONT = ITEM_FONT,
            CHECK_SZ = CHECK_SZ,
            ThemeBorder = ThemeBorder,
            ThemeFill = ThemeFill,
            ClickOff = Finder.ClickOff,
            Tip = Finder.Tip,
            Untip = Finder.Untip,
            Accent = AccentRGB,
            parent = SP,
            MenuItem = MenuItem,
            ClassLine = Finder.ClassLine,
            FLAG_KEYS = Finder.FLAG_KEYS,
            raids = raids,
            AddCountRow = Finder.AddCountRow,
            COUNT_ROLES = Finder.COUNT_ROLES,
            OpListOver = function()
                return Finder.opList and Finder.opList:IsShown() and Finder.opList:IsMouseOver() or false
            end,
        }
    for _, region in ipairs(ROLES) do
        local filterKey = region.key
        menu.items["role_" .. filterKey] = MenuItem(menu, posY, region.label, function()
            if raids then
                local cfg = FinderCfg()
                if type(cfg.raidRoles) ~= "table" then cfg.raidRoles = {} end
                cfg.raidRoles[filterKey] = (not cfg.raidRoles[filterKey]) or nil
                RunFilters()
                Paint()
            else
                local frame = Finder.GetFilter()
                frame[filterKey] = not frame[filterKey]
                Apply(frame)
            end
        end)
        posY = posY + ITEM_H
    end
    if K and mod.ExtraClassRows then
        posY = mod.ExtraClassRows(menu, posY, K) -- has / missing dropdown rows
    else
        posY = Finder.AddFlagItem(menu, posY, "hasLust", CludesUI.L("Has Bloodlust"), {
            CludesUI.L("A member whose class has one of these spells:"),
            Finder.ClassLine("SHAMAN", CludesUI.L("Bloodlust / Heroism (Shaman)")),
            Finder.ClassLine("MAGE", CludesUI.L("Time Warp (Mage)")),
            Finder.ClassLine("HUNTER", CludesUI.L("Primal Rage (Hunter pet)")),
            Finder.ClassLine("EVOKER", CludesUI.L("Fury of the Aspects (Evoker)")),
            CludesUI.L("Drums and other items don't count."),
        })
        posY = Finder.AddFlagItem(menu, posY, "hasBrez", CludesUI.L("Has Battle Res"), {
            CludesUI.L("A member whose class has one of these spells:"),
            Finder.ClassLine("DRUID", CludesUI.L("Rebirth (Druid)")),
            Finder.ClassLine("DEATHKNIGHT", CludesUI.L("Raise Ally (Death Knight)")),
            Finder.ClassLine("WARLOCK", CludesUI.L("Soulstone (Warlock)")),
            Finder.ClassLine("PALADIN", CludesUI.L("Intercession (Paladin)")),
            CludesUI.L("Engineering and other items don't count."),
        })
    end
    -- match any / exactly + count rows under one button
    if K and mod.ExtraRoleCounts then
        posY = mod.ExtraRoleCounts(menu, posY, K)
    else
        for _, region in ipairs(Finder.COUNT_ROLES) do
            posY = Finder.AddCountRow(menu, posY, region.key, region.label)
        end
    end
    return posY
end

-- shared less than / more than / equal to list.
function Finder.OpenOpList(button, roleName)
    local OpList = Finder.opList
    if not OpList then
        OpList = CreateFrame("Frame", nil, SP)
        Finder.opList = OpList
        OpList:SetFrameStrata("FULLSCREEN_DIALOG")
        OpList:SetFrameLevel(330)
        OpList:SetClampedToScreen(true)
        OpList:EnableMouse(true)
        OpList:SetWidth(92)
        local backdrop = OpList:CreateTexture(nil, "BACKGROUND")
        backdrop:SetAllPoints()
        backdrop:SetColorTexture(0, 0, 0, 1)
        CUI.MakeBorder(OpList, ThemeBorder())
        OpList.items = {}
        for index, o in ipairs(Finder.COUNT_OPS) do
            local entry = CreateFrame("Button", nil, OpList)
            entry:SetHeight(ITEM_H)
            entry:SetPoint("TOPLEFT", OpList, "TOPLEFT", 1, -(2 + (index - 1) * ITEM_H))
            entry:SetPoint("TOPRIGHT", OpList, "TOPRIGHT", -1, -(2 + (index - 1) * ITEM_H))
            entry.text = entry:CreateFontString(nil, "OVERLAY")
            Finder.Font(entry.text, ITEM_FONT)
            entry.text:SetPoint("LEFT", entry, "LEFT", 8, 0)
            entry.text:SetText(o.label)
            local highlight = entry:CreateTexture(nil, "HIGHLIGHT")
            highlight:SetAllPoints()
            highlight:SetColorTexture(1, 1, 1, CUI.DD_ITEM_HL_A)
            entry.opKey = o.key
            entry:SetScript("OnClick", function()
                local cfg = FinderCfg()
                if type(cfg.roleCounts) ~= "table" then cfg.roleCounts = {} end
                local region = cfg.roleCounts[OpList.role] or {}
                region.op = o.key
                cfg.roleCounts[OpList.role] = region
                OpList:Hide()
                RunFilters()
                Paint()
            end)
            OpList.items[index] = entry
        end
        OpList:SetHeight(4 + #Finder.COUNT_OPS * ITEM_H)
        Finder.ClickOff(
            OpList,
            function(self) return self:IsMouseOver() or (self.owner and self.owner:IsMouseOver()) end
        )
        OpList:Hide()
    end
    if OpList:IsShown() and OpList.owner == button then
        OpList:Hide()
        return
    end
    OpList.owner, OpList.role = button, roleName
    local rule = (FinderCfg().roleCounts or Finder.EMPTY)[roleName]
    local current = (type(rule) == "table" and rule.op) or "lt"
    local ar, ag, ab = AccentRGB()
    local tR, tG, tB, tA = CUI.TEXT_DIM_R, CUI.TEXT_DIM_G, CUI.TEXT_DIM_B, CUI.TEXT_DIM_A
    for _, entry in ipairs(OpList.items) do
        if entry.opKey == current then
            entry.text:SetTextColor(ar, ag, ab, 1)
        else
            entry.text:SetTextColor(tR, tG, tB, tA)
        end
    end
    OpList:ClearAllPoints()
    OpList:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -2)
    OpList:Show()
end

-- small black input box.
function Finder.MenuBox(hostFrame, wid, letters)
    local checkBox = CreateFrame("EditBox", nil, hostFrame)
    checkBox:SetSize(wid, 16)
    checkBox:SetAutoFocus(false)
    checkBox:SetNumeric(true)
    checkBox:SetMaxLetters(letters)
    Finder.Font(checkBox, ITEM_FONT)
    checkBox:SetTextColor(1, 1, 1, 1)
    checkBox:SetJustifyH("CENTER")
    local backdrop = checkBox:CreateTexture(nil, "BACKGROUND")
    backdrop:SetAllPoints()
    backdrop:SetColorTexture(0, 0, 0, 1)
    CUI.MakeBorder(checkBox, ThemeBorder())
    checkBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    checkBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return checkBox
end

-- 'Tanks [Less Than] [n]' row; empty box means no check.
function Finder.AddCountRow(menu, posY, roleName, textValue)
    local function Rule()
        local cfg = FinderCfg()
        if type(cfg.roleCounts) ~= "table" then cfg.roleCounts = {} end
        local region = cfg.roleCounts[roleName] or {}
        cfg.roleCounts[roleName] = region
        return region
    end
    local rowF = CreateFrame("Frame", nil, menu)
    rowF:SetHeight(ITEM_H + 2)
    rowF:SetPoint("TOPLEFT", menu, "TOPLEFT", 1, -posY)
    rowF:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -1, -posY)
    local swatchBtn = CreateFrame("Button", nil, rowF)
    swatchBtn:SetSize(CHECK_SZ, CHECK_SZ)
    swatchBtn:SetPoint("LEFT", rowF, "LEFT", 8, 0)
    local sbg = swatchBtn:CreateTexture(nil, "BACKGROUND")
    sbg:SetAllPoints()
    sbg:SetColorTexture(0.12, 0.12, 0.12, 1)
    swatchBtn.ring = CUI.MakeBorder(swatchBtn, 0.25, 0.25, 0.25, 0.6, CUI.PanelPP)
    swatchBtn.fill = swatchBtn:CreateTexture(nil, "ARTWORK")
    swatchBtn.fill:SetPoint("TOPLEFT", swatchBtn, "TOPLEFT", 3, -3)
    swatchBtn.fill:SetPoint("BOTTOMRIGHT", swatchBtn, "BOTTOMRIGHT", -3, 3)
    swatchBtn:SetScript("OnClick", function()
        local region = Rule()
        region.on = (not region.on) or nil
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        RunFilters()
        Paint()
        if region.on and menu.counts and menu.counts[roleName] then menu.counts[roleName].box:SetFocus() end
    end)
    local op = CreateFrame("Button", nil, rowF)
    op:SetSize(20, 16)
    op:SetPoint("LEFT", swatchBtn, "RIGHT", 7, 0)
    local obg = op:CreateTexture(nil, "BACKGROUND")
    obg:SetAllPoints()
    obg:SetColorTexture(0, 0, 0, 1)
    CUI.MakeBorder(op, ThemeBorder())
    op.text = op:CreateFontString(nil, "OVERLAY")
    Finder.Font(op.text, ITEM_FONT + 1)
    op.text:SetTextColor(CUI.TEXT_DIM_R, CUI.TEXT_DIM_G, CUI.TEXT_DIM_B, CUI.TEXT_DIM_A)
    op.text:SetPoint("CENTER", 0, 1)
    local highlight = op:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.08)
    op:SetScript("OnClick", function(self) Finder.OpenOpList(self, roleName) end)
    local checkBox = Finder.MenuBox(rowF, 22, 2)
    checkBox:SetPoint("LEFT", op, "RIGHT", 3, 0)
    checkBox:SetScript("OnTextChanged", function(self, user)
        if not user then return end
        Rule().n = tonumber(self:GetText())
        RunFilters()
        Paint()
    end)
    local labelText = rowF:CreateFontString(nil, "OVERLAY")
    Finder.Font(labelText, ITEM_FONT)
    labelText:SetTextColor(CUI.TEXT_DIM_R, CUI.TEXT_DIM_G, CUI.TEXT_DIM_B, CUI.TEXT_DIM_A)
    labelText:SetPoint("LEFT", checkBox, "RIGHT", 6, 0)
    labelText:SetText(textValue)
    menu.counts = menu.counts or {}
    menu.counts[roleName] = { box = checkBox, op = op, sw = swatchBtn, label = labelText }
    return posY + ITEM_H + 2
end

function Finder.PaintCountRows(menu)
    for _, region in ipairs(Finder.COUNT_ROLES) do
        local line = menu.counts and menu.counts[region.key]
        if line then
            local rule = (FinderCfg().roleCounts or Finder.EMPTY)[region.key]
            local isOn = type(rule) == "table" and rule.on == true
            line.op.text:SetText(Finder.COUNT_OP_LABEL[(type(rule) == "table" and rule.op) or "lt"])
            if not line.box:HasFocus() then
                local n = type(rule) == "table" and tonumber(rule.n)
                line.box:SetText(n and tostring(n) or "")
            end
            local swatchBtn = line.sw
            local ar, ag, ab = AccentRGB()
            swatchBtn.fill:SetColorTexture(ar, ag, ab, 1)
            swatchBtn.fill:SetShown(isOn)
            if isOn then
                swatchBtn.ring:SetColor(ar, ag, ab, 0.8)
            else
                swatchBtn.ring:SetColor(0.25, 0.25, 0.25, 0.6)
            end
            local a = isOn and 1 or 0.4
            line.op:SetAlpha(a)
            line.box:SetAlpha(a)
            if not isOn and line.box:HasFocus() then line.box:ClearFocus() end
            line.box:SetEnabled(isOn)
            line.label:SetAlpha(a)
        end
    end
end

-- toggles both menus share
function Finder.AddFlagItem(menu, posY, filterKey, textValue, tipText)
    local entry = MenuItem(menu, posY, textValue, function()
        local cfg = FinderCfg()
        cfg[filterKey] = (not cfg[filterKey]) or nil
        RunFilters()
        Paint()
    end)
    menu.items["flag_" .. filterKey] = entry
    if tipText then
        entry:HookScript("OnEnter", function(self)
            if type(tipText) == "table" then
                Finder.Tip(self, textValue, unpack(tipText))
            else
                Finder.Tip(self, textValue, tipText)
            end
        end)
        entry:HookScript("OnLeave", Finder.Untip)
    end
    return posY + ITEM_H
end

Finder.FLAG_KEYS = { "partyFit", "notDeclined", "hasLust", "hasBrez" }
function Finder.PaintFlagItems(menu)
    local cfg = FinderCfg()
    for _, filterKey in ipairs(Finder.FLAG_KEYS) do
        local entry = menu.items["flag_" .. filterKey]
        if entry then entry:SetChecked(cfg[filterKey] == true) end
    end
end

local function PaintRoleItems(menu, raids)
    local source = raids and (ChosenRaidRoles() or Finder.EMPTY) or Finder.GetFilter()
    for _, region in ipairs(ROLES) do
        local entry = menu.items["role_" .. region.key]
        if entry then entry:SetChecked(source[region.key] == true) end
    end
    Finder.PaintFlagItems(menu)
    Finder.PaintCountRows(menu)
end

-- min. rating: the leader's m+ rating, applied on search again
local function AddRatingRow(menu, posY)
    local function Send()
        local cfg = FinderCfg()
        local val = cfg.ratingOn and (tonumber(cfg.ratingValue) or 0) or 0
        local frame = Finder.GetFilter()
        if (frame.minimumRating or 0) ~= val then
            frame.minimumRating = val
            Apply(frame)
        end
    end
    local rowF = CreateFrame("Frame", nil, menu)
    -- a row like the others, so it lines up with the other column's rows
    rowF:SetHeight(ITEM_H)
    rowF:SetPoint("TOPLEFT", menu, "TOPLEFT", 1, -posY)
    rowF:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -1, -posY)
    local RATING = CludesUI.L("Min. Rating")
    local RATING_TIP =
        CludesUI.L("Only groups whose leader has at least this Mythic+ rating. Applied on Search Again.")
    rowF:EnableMouse(true)
    rowF:SetScript("OnEnter", function(self) Finder.Tip(self, RATING, RATING_TIP) end)
    rowF:SetScript("OnLeave", Finder.Untip)
    local callback = CreateFrame("Button", nil, rowF)
    callback:SetSize(CHECK_SZ, CHECK_SZ)
    callback:SetPoint("LEFT", rowF, "LEFT", 8, 0)
    callback:SetScript("OnEnter", function(self) Finder.Tip(self, RATING, RATING_TIP) end)
    callback:SetScript("OnLeave", Finder.Untip)
    local cbg = callback:CreateTexture(nil, "BACKGROUND")
    cbg:SetAllPoints()
    cbg:SetColorTexture(0.12, 0.12, 0.12, 1)
    callback.ring = CUI.MakeBorder(callback, 0.25, 0.25, 0.25, 0.6, CUI.PanelPP)
    callback.fill = callback:CreateTexture(nil, "ARTWORK")
    callback.fill:SetPoint("TOPLEFT", callback, "TOPLEFT", 3, -3)
    callback.fill:SetPoint("BOTTOMRIGHT", callback, "BOTTOMRIGHT", -3, 3)
    callback:SetScript("OnClick", function()
        local cfg = FinderCfg()
        cfg.ratingOn = (not cfg.ratingOn) or nil
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        Send()
        Paint()
        if cfg.ratingOn and menu.rating then menu.rating.box:SetFocus() end
    end)
    local labelText = rowF:CreateFontString(nil, "OVERLAY")
    Finder.Font(labelText, ITEM_FONT)
    labelText:SetTextColor(CUI.TEXT_DIM_R, CUI.TEXT_DIM_G, CUI.TEXT_DIM_B, CUI.TEXT_DIM_A)
    labelText:SetPoint("LEFT", callback, "RIGHT", 7, 0)
    labelText:SetText(RATING)
    local checkBox = Finder.MenuBox(rowF, 44, 4)
    checkBox:SetPoint("RIGHT", rowF, "RIGHT", -7, 0)
    checkBox:SetScript("OnEditFocusLost", function(self)
        FinderCfg().ratingValue = tonumber(self:GetText())
        Send()
        Paint()
    end)
    menu.rating = { box = checkBox, cb = callback, label = labelText }
    return posY + ITEM_H
end

-- restore the saved rating when ticked again.
function Finder.AdoptRating()
    local cfg = FinderCfg()
    if cfg.ratingOn ~= nil or cfg.ratingValue ~= nil then return end
    local frame = Finder.GetFilter()
    local val = frame and tonumber(frame.minimumRating) or 0
    if val > 0 then
        cfg.ratingOn, cfg.ratingValue = true, val
    end
end

function Finder.PaintRating(menu)
    local region = menu and menu.rating
    if not region then return end
    local cfg = FinderCfg()
    local isOn = cfg.ratingOn == true
    local ar, ag, ab = AccentRGB()
    region.cb.fill:SetColorTexture(ar, ag, ab, 1)
    region.cb.fill:SetShown(isOn)
    if isOn then
        region.cb.ring:SetColor(ar, ag, ab, 0.8)
    else
        region.cb.ring:SetColor(0.25, 0.25, 0.25, 0.6)
    end
    if not region.box:HasFocus() then
        local val = tonumber(cfg.ratingValue)
        region.box:SetText(val and val > 0 and tostring(val) or "")
    end
    local a = isOn and 1 or 0.4
    region.label:SetAlpha(a)
    region.box:SetAlpha(a)
    if not isOn and region.box:HasFocus() then region.box:ClearFocus() end
    region.box:SetEnabled(isOn)
end

local function AddRegionItems(menu, posY)
    if not RegionsAvailable() then return posY end
    -- eu lists languages, short names in two columns
    local lang = mod.RegionIsLanguage()
    posY = AddSection(menu, posY, lang and CludesUI.L("Language") or CludesUI.L("Region"))
    for index, region in ipairs(Regions()) do
        local filterKey = region.key
        local entry = MenuItem(menu, posY, lang and region.tag or region.label, function()
            local cfg = FinderCfg()
            if type(cfg.regions) ~= "table" then cfg.regions = {} end
            cfg.regions[filterKey] = (not cfg.regions[filterKey]) or nil
            local count = 0
            for _, o in ipairs(Regions()) do
                if cfg.regions[o.key] then count = count + 1 end
            end
            if count == #Regions() then wipe(cfg.regions) end
            RunFilters()
            Paint()
        end)
        menu.items["region_" .. filterKey] = entry
        if lang then
            entry:ClearAllPoints()
            if index % 2 == 1 then
                entry:SetPoint("TOPLEFT", menu, "TOPLEFT", 1, -posY)
                entry:SetPoint("TOPRIGHT", menu, "TOP", 0, -posY)
            else
                entry:SetPoint("TOPLEFT", menu, "TOP", 0, -posY)
                entry:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -1, -posY)
            end
            if index % 2 == 0 or index == #Regions() then posY = posY + ITEM_H end
        else
            posY = posY + ITEM_H
        end
    end
    return posY
end

local function PaintRegionItems(menu)
    local chosen = RegionFilterActive() and ChosenRegions()
    for _, region in ipairs(Regions()) do
        local entry = menu.items["region_" .. region.key]
        if entry then entry:SetChecked(chosen and chosen[region.key] == true or false) end
    end
end

local function PaintMenu()
    if raidDiffMenu and raidDiffMenu:IsShown() then
        local chosen = ChosenRaidDiffs()
        for _, skinData in ipairs(RAID_DIFFS_MENU) do
            raidDiffMenu.items[skinData.key]:SetChecked(chosen ~= nil and chosen[skinData.key] == true)
        end
        PaintRoleItems(raidDiffMenu, true)
        Finder.PaintFlagItems(raidDiffMenu.side)
        PaintRegionItems(raidDiffMenu.side)
        PaintPlaystyleItems(raidDiffMenu.side, true)
    end
    if not (dropMenu and dropMenu:IsShown()) then return end
    local frame = Finder.GetFilter()
    local all = DiffAllOrNone(frame)
    for _, skinData in ipairs(DIFFS) do
        dropMenu.items[skinData.key]:SetChecked(not all and frame[skinData.key] == true)
    end
    Finder.PaintRating(dropMenu.side)
    PaintRoleItems(dropMenu, false)
    Finder.PaintFlagItems(dropMenu.side)
    PaintRegionItems(dropMenu.side)
    PaintPlaystyleItems(dropMenu.side, false)
end

-- filters menu side panel: region, playstyle, then the extra toggles.
Finder.DIM_ALPHA = 0.35
local function DimForMenu(isOn)
    local a = isOn and Finder.DIM_ALPHA or 1
    if line then line:SetAlpha(a) end
    local face = Finder.FilterFace()
    if face then face:SetAlpha(a) end
    if SP.ScrollBox then SP.ScrollBox:SetAlpha(a) end
    if SP.ScrollBar then SP.ScrollBar:SetAlpha(a) end
    if mod.ExtraOnDim then mod.ExtraOnDim(isOn) end -- row 1 blocked too
end

local function BuildSidePanel(menu, raids)
    local sidePane = CreateFrame("Frame", nil, SP)
    sidePane:SetFrameStrata("FULLSCREEN_DIALOG")
    sidePane:EnableMouse(true)
    sidePane:SetFrameLevel(300)
    sidePane:SetClampedToScreen(true)
    sidePane:SetWidth(140)
    sidePane:SetPoint("TOPRIGHT", menu, "TOPLEFT", 0, 0)
    local backdrop = sidePane:CreateTexture(nil, "BACKGROUND")
    backdrop:SetAllPoints()
    local red, green, blue = ThemeFill()
    backdrop:SetColorTexture(red, green, blue, 0.98)
    sidePane.items = {}
    local posY = 3
    posY = AddRegionItems(sidePane, posY)
    posY = AddPlaystyleItems(sidePane, posY, raids)
    sidePane.extraMiscY = posY -- where misc starts
    posY = AddSection(sidePane, posY, CludesUI.L("Misc"))
    sidePane.extraMiscRowsY = posY
    posY = Finder.AddFlagItem(
        sidePane,
        posY,
        "partyFit",
        CludesUI.L("Party Fit"),
        CludesUI.L("Only groups with open slots for your role, or for your whole party's roles.")
    )
    posY = Finder.AddFlagItem(
        sidePane,
        posY,
        "notDeclined",
        CludesUI.L("Not Declined"),
        CludesUI.L("Hides groups that have declined you this session.")
    )
    if not raids then posY = AddRatingRow(sidePane, posY) end
    sidePane.extraEndY = posY
    -- both columns the same height, one border around them
    local hgt = math.max(posY + 3, menu:GetHeight() or 0)
    sidePane:SetHeight(hgt)
    menu:SetHeight(hgt)
    local edge = CreateFrame("Frame", nil, sidePane)
    edge:SetPoint("TOPLEFT", sidePane, "TOPLEFT", 0, 0)
    edge:SetPoint("BOTTOMRIGHT", menu, "BOTTOMRIGHT", 0, 0)
    edge:SetFrameLevel(menu:GetFrameLevel() + 10)
    edge:EnableMouse(false)
    local S = WindowSkin()
    if S and S.AddBorder then
        S.AddBorder(edge)
    else
        CUI.MakeBorder(edge, ThemeBorder())
    end
    sidePane:Hide()
    menu.side = sidePane
    menu:SetScript("OnShow", function()
        sidePane:Show()
        DimForMenu(true)
    end)
    menu:SetScript("OnHide", function()
        sidePane:Hide()
        DimForMenu(false)
        if Finder.opList then Finder.opList:Hide() end
    end)
    Finder.ClickOff(menu, Finder.FiltersInside)
    return sidePane
end

-- clicks on the menu, side panel, button or operator list keep it open
function Finder.FiltersInside(menu)
    return menu:IsMouseOver()
        or (difficultyBtn and difficultyBtn:IsMouseOver())
        or menu.side:IsMouseOver()
        or (Finder.opList and Finder.opList:IsShown() and Finder.opList:IsMouseOver())
        or (mod.ExtraInside and mod.ExtraInside()) -- our dropdowns
        or false
end

-- filters menu, border around it and the side panel
local function BuildMenu()
    dropMenu = CreateFrame("Frame", nil, SP)
    dropMenu:SetFrameStrata("FULLSCREEN_DIALOG")
    dropMenu:EnableMouse(true)
    dropMenu:SetFrameLevel(300)
    dropMenu:SetClampedToScreen(true)
    local backdrop = dropMenu:CreateTexture(nil, "BACKGROUND")
    backdrop:SetAllPoints()
    local red, green, blue = ThemeFill()
    backdrop:SetColorTexture(red, green, blue, 0.98)
    dropMenu.items = {}
    local posY = 3
    posY = AddSection(dropMenu, posY, CludesUI.L("Difficulty"))
    for _, skinData in ipairs(DIFFS) do
        local filterKey = skinData.key
        dropMenu.items[filterKey] = MenuItem(dropMenu, posY, skinData.label, function()
            local frame = Finder.GetFilter()
            local all = DiffAllOrNone(frame)
            if all then
                for _, o in ipairs(DIFFS) do
                    frame[o.key] = (o.key == filterKey)
                end
                Apply(frame)
            else
                SetDifficulty(filterKey, not frame[filterKey])
            end
        end)
        posY = posY + ITEM_H
    end
    posY = AddRoleItems(dropMenu, posY, false)
    dropMenu:SetHeight(posY + 3)
    BuildSidePanel(dropMenu, false)
    if mod.ExtraDecorateMenu then mod.ExtraDecorateMenu(dropMenu, dropMenu.side) end
    dropMenu:Hide()
end

-- raids version of the filters menu (no mythic+), applies right away.
local function BuildRaidDiffMenu()
    local menu = CreateFrame("Frame", nil, SP)
    raidDiffMenu = menu
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:EnableMouse(true)
    menu:SetFrameLevel(300)
    menu:SetClampedToScreen(true)
    local backdrop = menu:CreateTexture(nil, "BACKGROUND")
    backdrop:SetAllPoints()
    local red, green, blue = ThemeFill()
    backdrop:SetColorTexture(red, green, blue, 0.98)
    local function Diffs()
        local cfg = FinderCfg()
        if type(cfg.raidDiffs) ~= "table" then cfg.raidDiffs = {} end
        return cfg.raidDiffs
    end
    menu.items = {}
    local posY = 3
    posY = AddSection(menu, posY, CludesUI.L("Difficulty"))
    for _, skinData in ipairs(RAID_DIFFS_MENU) do
        local filterKey = skinData.key
        menu.items[filterKey] = MenuItem(menu, posY, skinData.label, function()
            local tbl = Diffs()
            tbl[filterKey] = (not tbl[filterKey]) or nil
            local _, n = ChosenRaidDiffs()
            if n == #RAID_DIFFS_MENU then wipe(tbl) end
            RunFilters()
            Paint()
        end)
        posY = posY + ITEM_H
    end
    -- gap for the missing m+ row, keeps roles lined up
    if mod.ExtraClassRows then posY = posY + math.max(0, #DIFFS - #RAID_DIFFS_MENU) * ITEM_H end
    posY = AddRoleItems(menu, posY, true)
    menu:SetHeight(posY + 3)
    BuildSidePanel(menu, true)
    if mod.ExtraDecorateMenu then mod.ExtraDecorateMenu(menu, menu.side) end
    menu:Hide()
end

local function ToggleMenu()
    if SP.categoryID == RAIDS then
        if not raidDiffMenu then BuildRaidDiffMenu() end
        if raidDiffMenu:IsShown() then
            raidDiffMenu:Hide()
            return
        end
        raidDiffMenu:ClearAllPoints()
        raidDiffMenu:SetPoint("TOPLEFT", difficultyBtn, "BOTTOMLEFT", 0, -SQ_GAP)
        raidDiffMenu:SetPoint("TOPRIGHT", refreshButton or difficultyBtn, "BOTTOMRIGHT", 0, -SQ_GAP)
        if mod.ExtraWidenMenu then
            mod.ExtraWidenMenu(raidDiffMenu, difficultyBtn, SQ_GAP, refreshButton or difficultyBtn)
        end
        raidDiffMenu:Show()
        PaintMenu()
        return
    end
    if not dropMenu then BuildMenu() end
    if dropMenu:IsShown() then
        dropMenu:Hide()
        return
    end
    dropMenu:ClearAllPoints()
    dropMenu:SetPoint("TOPLEFT", difficultyBtn, "BOTTOMLEFT", 0, -SQ_GAP)
    dropMenu:SetPoint("TOPRIGHT", refreshButton or difficultyBtn, "BOTTOMRIGHT", 0, -SQ_GAP)
    if mod.ExtraWidenMenu then
        mod.ExtraWidenMenu(dropMenu, difficultyBtn, SQ_GAP, refreshButton or difficultyBtn)
    end
    dropMenu:Show()
    PaintMenu()
end

-------------------------------------------------------------------------------
-- buttons
-------------------------------------------------------------------------------
-- button in the skin's look (WSkin.button); skin off, blizzard's rounded menu button
local function SkinnedButton(hostFrame, wid, hgt, keepKeys, decorate)
    local stock = not Finder.SkinOn()
    local widget = CreateFrame("Button", nil, hostFrame, stock and "UIMenuButtonStretchTemplate" or nil)
    widget:SetSize(wid, hgt)
    widget:SetNormalFontObject("GameFontHighlight")
    widget:SetHighlightFontObject("GameFontHighlight")
    widget:SetDisabledFontObject("GameFontDisable")
    widget:SetText(" ")
    if decorate then decorate(widget) end
    local S = WindowSkin()
    if stock then
        -- no edge of ours: a picked square holds the template's highlight on (XF.PickBorder), and a
        -- border colour write on a frame with no border does nothing
        return widget
    elseif S and S.Button then
        S.Button(widget, keepKeys)
    else
        local backdrop = widget:CreateTexture(nil, "BACKGROUND")
        backdrop:SetAllPoints()
        backdrop:SetColorTexture(0.06, 0.06, 0.06, 0.95)
        CUI.MakeBorder(widget, 0.25, 0.25, 0.25, 1, CUI.PanelPP)
        local highlight = widget:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 1, 1, 0.1)
    end
    return widget
end

local function DropButton(hostFrame, wid, hgt)
    local widget = SkinnedButton(hostFrame, wid, hgt, { "Arrow" }, function(button)
        button.Arrow = button:CreateTexture(nil, "OVERLAY")
        button.Arrow:SetAtlas("Azerite-PointingArrow")
        button.Arrow:SetDesaturated(true)
        button.Arrow:SetVertexColor(1, 1, 1, 0.8)
        button.Arrow:SetSize(11, 8)
        button.Arrow:SetPoint("RIGHT", button, "RIGHT", -8, 0)
    end)
    local fontStr = widget:GetFontString()
    fontStr:ClearAllPoints()
    fontStr:SetPoint("LEFT", widget, "LEFT", 9, 0)
    fontStr:SetPoint("RIGHT", widget.Arrow, "LEFT", -4, 0)
    fontStr:SetJustifyH("LEFT")
    fontStr:SetWordWrap(false)
    widget.label = fontStr
    return widget
end

-- square glyph button; atlas = true means tex is an atlas.
local function GlyphButton(hostFrame, px, texture, atlas)
    return SkinnedButton(hostFrame, px, px, { "Glyph" }, function(button)
        button:SetText("")
        button.Glyph = button:CreateTexture(nil, "OVERLAY")
        if atlas then
            button.Glyph:SetAtlas(texture, false)
            button.Glyph:SetDesaturated(true)
        else
            button.Glyph:SetTexture(texture)
        end
        button.Glyph:SetPoint("CENTER")
        button.Glyph:SetAlpha(0.8)
    end)
end

-- blizzard's cancel x restyled, its button still gets the click
function Finder.CancelLook(record)
    local callback = record and record.CancelButton
    if type(callback) ~= "table" or not callback.GetRegions or not Finder.SkinOn() then return end
    local skinData = FFD[callback]
    if not skinData then
        skinData = {}
        FFD[callback] = skinData
        for _, region in ipairs({ callback:GetRegions() }) do
            region:SetAlpha(0)
        end
        local highlight = callback.GetHighlightTexture and callback:GetHighlightTexture()
        if highlight then highlight:SetAlpha(0) end
        local lookName = GlyphButton(callback, ROW1_H - 4, X_TEX)
        lookName:EnableMouse(false)
        lookName:SetPoint("CENTER", callback, "CENTER", 0, 0)
        lookName:SetFrameLevel(callback:GetFrameLevel() + 1)
        lookName.Glyph:SetSize(11, 11)
        lookName.Glyph:SetVertexColor(Finder.GLYPH, Finder.GLYPH, Finder.GLYPH, 1)
        skinData.look = lookName
        callback:HookScript("OnEnter", function(self)
            if not self:IsEnabled() then return end
            SetBorderColor(skinData.look, 1, 0.15, 0.15, 1)
            skinData.look.Glyph:SetVertexColor(1, 0.15, 0.15, 1)
            skinData.look.Glyph:SetAlpha(1)
        end)
        callback:HookScript("OnLeave", function(self)
            SetBorderColor(skinData.look, ThemeBorder())
            skinData.look.Glyph:SetVertexColor(Finder.GLYPH, Finder.GLYPH, Finder.GLYPH, 1)
            skinData.look.Glyph:SetAlpha(self:IsEnabled() and 0.8 or 0.35)
        end)
    end
    skinData.look.Glyph:SetAlpha(callback:IsEnabled() and 0.8 or 0.35)
end

mod.GlyphButton = GlyphButton
mod.GLYPH = Finder.GLYPH
mod.Redecorate = Finder.Redecorate -- for the settings page

local function SquareEnter(self)
    local skinData = self.dungeon
    if not skinData then return end
    Finder.Tip(self, skinData.name or "?", CludesUI.L("Click to toggle"))
end

-- dungeon square: a skinned button with the icon inset 1px.
local function MakeSquare(hostFrame)
    local px = Finder.SkinOn() and CUI.PP.mult or 3 -- blizzard's button: its black inside
    local widget = SkinnedButton(hostFrame, BTN, BTN, { "Icon" }, function(button)
        button:SetText("")
        button.Icon = button:CreateTexture(nil, "ARTWORK")
        button.Icon:SetPoint("TOPLEFT", button, "TOPLEFT", px, -px)
        button.Icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -px, px)
        button.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        if not Finder.SkinOn() then
            -- rounded corners, to sit inside blizzard's rounded button
            local mask = button:CreateMaskTexture()
            mask:SetAtlas("UI-HUD-ActionBar-IconFrame-Mask")
            -- the mask's own clear margin sits outside the icon, so the icon keeps its size
            mask:SetPoint("TOPLEFT", button.Icon, "TOPLEFT", -3, 3)
            mask:SetPoint("BOTTOMRIGHT", button.Icon, "BOTTOMRIGHT", 3, -3)
            button.Icon:AddMaskTexture(mask)
        end
    end)
    widget.icon = widget.Icon
    widget:SetScript("OnEnter", SquareEnter)
    widget:SetScript("OnLeave", Finder.Untip)
    widget:SetScript("OnClick", function(self)
        if self.dungeon then ToggleDungeon(self.dungeon.groupID) end
        if Finder.tipOwner == self then SquareEnter(self) end
    end)
    return widget
end

local function DelveEnter(self)
    local skinData = self.delve
    if not skinData then return end
    Finder.Tip(
        self,
        skinData.name or "?",
        bountiful[skinData.name] and (Finder.GOLD_HEX .. CludesUI.L("Bountiful today") .. "|r") or nil,
        CludesUI.L("Click to toggle")
    )
end

-- delve square: same button with the short name.
local function MakeDelveSquare(hostFrame)
    local widget = SkinnedButton(hostFrame, BTN, BTN, nil, function(button) button:SetText("") end)
    local fontStr = widget:GetFontString()
    fontStr:ClearAllPoints()
    fontStr:SetPoint("CENTER")
    fontStr:SetWordWrap(false)
    local function Layer(level)
        local frame = CreateFrame("Frame", nil, widget)
        frame:SetAllPoints(widget)
        frame:SetFrameLevel(widget:GetFrameLevel() + level)
        frame:EnableMouse(false)
        return frame
    end
    widget.gold = Layer(2)
    widget.edge = Layer(3)
    local line = widget.gold:CreateTexture(nil, "OVERLAY")
    line:SetColorTexture(GOLD_R, GOLD_G, GOLD_B, 1)
    line:SetPoint("TOPLEFT", fontStr, "BOTTOMLEFT", 0, -1)
    line:SetPoint("TOPRIGHT", fontStr, "BOTTOMRIGHT", 0, -1)
    line:SetHeight(2)
    if Finder.SkinOn() then
        local red, green, blue, a = ThemeBorder()
        CUI.PanelPP.CreateBorder(widget.edge, red, green, blue, a, 1, "OVERLAY", 7)
    end
    widget.gold:Hide()
    widget:SetScript("OnEnter", DelveEnter)
    widget:SetScript("OnLeave", Finder.Untip)
    widget:SetScript("OnClick", function(self)
        local skinData = self.delve
        if not skinData then return end
        local cfg = FinderCfg()
        if type(cfg.delves) ~= "table" then cfg.delves = {} end
        cfg.delves[skinData.groupID] = (not cfg.delves[skinData.groupID]) or nil
        local count = 0
        for _, o in ipairs(delves or {}) do
            if cfg.delves[o.groupID] then count = count + 1 end
        end
        if count == #(delves or {}) then wipe(cfg.delves) end
        RunFilters()
        Paint()
        if Finder.tipOwner == self then DelveEnter(self) end
    end)
    return widget
end

-- grid slot i after the reset, right-aligned, wrapping.
local function PlaceGrid(entries, index, px, after, cols, slots)
    local square = entries[index]
    square:SetSize(px, px)
    square:ClearAllPoints()
    if index == 1 then
        square:SetPoint("LEFT", after, "RIGHT", SQ_GAP + (slots - cols) * (px + SQ_GAP), 0)
    elseif (index - 1) % cols == 0 then
        square:SetPoint("TOPLEFT", entries[index - cols], "BOTTOMLEFT", 0, -SQ_GAP)
    else
        square:SetPoint("LEFT", entries[index - 1], "RIGHT", SQ_GAP, 0)
    end
    square:Show()
end

local function LayoutDelves(px, after, show, cols, slots)
    local entries = delves or {}
    local font = gfFont or "GameFontHighlight"
    -- one scrolling line, like the raid bosses
    if mod.ExtraDelveStrip then
        mod.GFDressDelve = function(square, skinData)
            square:SetNormalFontObject(font)
            square:SetHighlightFontObject(font)
            square:SetText(skinData.abbr)
        end
        return mod.ExtraDelveStrip(
            entries,
            delveSquares,
            function() return MakeDelveSquare(line) end,
            px,
            after,
            show,
            cols,
            slots,
            line,
            SQ_GAP,
            function() Paint() end
        )
    end
    for index = 1, math.max(#entries, #delveSquares) do
        local skinData = entries[index]
        local square = delveSquares[index]
        if skinData and show then
            if not square then
                square = MakeDelveSquare(line)
                delveSquares[index] = square
            end
            square.delve = skinData
            square:SetNormalFontObject(font)
            square:SetHighlightFontObject(font)
            square:SetText(skinData.abbr)
            PlaceGrid(delveSquares, index, px, after, cols, slots)
        elseif square then
            square.delve = nil
            square:Hide()
        end
    end
    return (show and #entries > 0) and math.ceil(#entries / cols) or 1
end

local function BossEnter(self)
    local b = self.boss
    if not b then return end
    local pick = FinderCfg().bosses
    pick = type(pick) == "table" and pick[b.key]
    Finder.Tip(
        self,
        b.name or "?",
        b.raidName,
        pick == "dead" and CludesUI.L("Groups with this boss dead")
            or pick and CludesUI.L("Groups with this boss alive")
            or CludesUI.L("Click to filter by this boss")
    )
end

-- boss pick: one list under the clicked square, as wide as it
local BOSS_PICKS = {
    {
        value = true,
        tex = "Interface\\AddOns\\" .. FOLDER .. "\\media\\icons\\cui-heart.png",
        tip = CludesUI.L("Boss Alive"),
        r = 0.2,
        g = 1,
        b = 0.3,
    },
    {
        value = "dead",
        tex = "Interface\\AddOns\\" .. FOLDER .. "\\media\\icons\\cui-skull.png",
        tip = CludesUI.L("Boss Dead"),
        r = 1,
        g = 0.15,
        b = 0.15,
    },
    { tex = X_TEX, tip = CludesUI.L("No Filter"), r = 0.6, g = 0.6, b = 0.6 },
}
local bossPick

local function BossPickList()
    if bossPick then return bossPick end
    local entries = CreateFrame("Frame", nil, SP)
    entries:SetFrameStrata("FULLSCREEN_DIALOG")
    entries:SetFrameLevel(330)
    entries:SetClampedToScreen(true)
    entries:EnableMouse(true)
    local backdrop = entries:CreateTexture(nil, "BACKGROUND")
    backdrop:SetAllPoints()
    local red, green, blue = ThemeFill()
    backdrop:SetColorTexture(red, green, blue, 0.98)
    CUI.MakeBorder(entries, ThemeBorder())
    entries.rows = {}
    for index, p in ipairs(BOSS_PICKS) do
        local entry = CreateFrame("Button", nil, entries)
        entry.Icon = entry:CreateTexture(nil, "ARTWORK")
        entry.Icon:SetTexture(p.tex)
        entry.Icon:SetPoint("CENTER")
        entry.Icon:SetVertexColor(p.r, p.g, p.b)
        entry.cur = entry:CreateTexture(nil, "BACKGROUND")
        entry.cur:SetAllPoints()
        entry.cur:SetColorTexture(1, 1, 1, 0.12)
        local highlight = entry:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 1, 1, CUI.DD_ITEM_HL_A or 0.08)
        entry:SetScript("OnEnter", function(self) Finder.Tip(self, p.tip) end)
        entry:SetScript("OnLeave", Finder.Untip)
        entry:SetScript("OnClick", function()
            local skinData = entries.owner and entries.owner.boss
            entries:Hide()
            if not skinData then return end
            local cfg = FinderCfg()
            if type(cfg.bosses) ~= "table" then cfg.bosses = {} end
            cfg.bosses[skinData.key] = p.value
            RunFilters()
            Paint()
        end)
        entries.rows[index] = entry
    end
    Finder.ClickOff(
        entries,
        function(self) return self:IsMouseOver() or (self.owner and self.owner:IsMouseOver()) end
    )
    entries:SetScript("OnHide", Finder.Untip)
    entries:Hide()
    bossPick = entries
    -- a strip that scrolls takes the square away from its list
    mod.ExtraHideBossPick = function() entries:Hide() end
    return entries
end

local function OpenBossPick(square)
    local entries = BossPickList()
    if entries:IsShown() and entries.owner == square then
        entries:Hide()
        return
    end
    Finder.Untip()
    entries.owner = square
    local wid = square:GetWidth()
    local iconTex = math.floor(wid * 0.6 + 0.5)
    local cfg = FinderCfg()
    local current = type(cfg.bosses) == "table" and square.boss and cfg.bosses[square.boss.key] or nil
    for index, entry in ipairs(entries.rows) do
        entry:SetSize(wid, wid)
        entry:ClearAllPoints()
        entry:SetPoint("TOP", entries, "TOP", 0, -(index - 1) * wid)
        entry.Icon:SetSize(iconTex, iconTex)
        -- a light wash behind the current pick
        entry.cur:SetShown(BOSS_PICKS[index].value == current)
    end
    entries:SetSize(wid, wid * #BOSS_PICKS)
    entries:ClearAllPoints()
    entries:SetPoint("TOP", square, "BOTTOM", 0, -2)
    entries:Show()
end

-- boss square with the journal portrait cropped to the middle.
local function MakeBossSquare(hostFrame)
    local widget = MakeSquare(hostFrame)
    widget.icon:SetTexCoord(0.25, 0.75, 0, 1)
    if not Finder.SkinOn() then
        -- alive / dead outline around the icon, above blizzard's rounded edge
        widget.state = CreateFrame("Frame", nil, widget)
        widget.state:SetPoint("TOPLEFT", widget.icon, "TOPLEFT", -1, 1)
        widget.state:SetPoint("BOTTOMRIGHT", widget.icon, "BOTTOMRIGHT", 1, -1)
        widget.state:SetFrameLevel(widget:GetFrameLevel() + 2)
        widget.state:EnableMouse(false)
        CUI.PanelPP.CreateBorder(widget.state, 0, 0, 0, 0, 1, "OVERLAY", 7)
    end
    widget:SetScript("OnEnter", BossEnter)
    widget:SetScript("OnClick", function(self)
        if self.boss then OpenBossPick(self) end
    end)
    return widget
end

local function LayoutBosses(px, after, show, cols, slots)
    local entries = {}
    for _, b in ipairs(bosses or {}) do
        if RaidShown(b.raid) then entries[#entries + 1] = b end
    end
    -- one scrolling line instead of a grid
    if mod.ExtraBossStrip then
        return mod.ExtraBossStrip(
            entries,
            bossSquares,
            function() return MakeBossSquare(line) end,
            px,
            after,
            show,
            cols,
            slots,
            line,
            SQ_GAP,
            function() Paint() end
        )
    end
    for index = 1, math.max(#entries, #bossSquares) do
        local skinData = entries[index]
        local square = bossSquares[index]
        if skinData and show then
            if not square then
                square = MakeBossSquare(line)
                bossSquares[index] = square
            end
            square.boss = skinData
            square.icon:SetTexture(skinData.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            PlaceGrid(bossSquares, index, px, after, cols, slots)
        elseif square then
            square.boss = nil
            square:Hide()
        end
    end
    return (show and #entries > 0) and math.ceil(#entries / cols) or 1
end

-- raid menu (map button): a toggle per current raid.
local function BuildRaidMenu()
    raidMenu = CreateFrame("Frame", nil, SP)
    raidMenu:SetFrameStrata("FULLSCREEN_DIALOG")
    raidMenu:EnableMouse(true)
    raidMenu:SetFrameLevel(300)
    raidMenu:SetClampedToScreen(true)
    raidMenu:SetWidth(190)
    local backdrop = raidMenu:CreateTexture(nil, "BACKGROUND")
    backdrop:SetAllPoints()
    local red, green, blue = ThemeFill()
    backdrop:SetColorTexture(red, green, blue, 0.98)
    local S = WindowSkin()
    if S and S.AddBorder then
        S.AddBorder(raidMenu)
    else
        CUI.MakeBorder(raidMenu, ThemeBorder())
    end
    raidMenu.items = {}
    local posY = 3
    -- current season only, older raids dimmed and out
    raidMenu.items.season = MenuItem(raidMenu, posY, CludesUI.L("Current Season Only"), function()
        local cfg = FinderCfg()
        cfg.extraSeasonRaids = not Finder.SeasonOnly()
        if type(cfg.bosses) == "table" then
            for _, bo in ipairs(bosses or {}) do
                if not RaidShown(bo.raid) then cfg.bosses[bo.key] = nil end
            end
        end
        mod.Search_Layout()
        RunFilters()
    end)
    posY = posY + ITEM_H
    local sdiv = raidMenu:CreateTexture(nil, "ARTWORK")
    Finder.Hairline(sdiv)
    sdiv:SetColorTexture(1, 1, 1, 0.10)
    sdiv:SetPoint("TOPLEFT", raidMenu, "TOPLEFT", 1, -posY - 3)
    sdiv:SetPoint("TOPRIGHT", raidMenu, "TOPRIGHT", -1, -posY - 3)
    posY = posY + 7
    for _, raid in ipairs(raidList or {}) do
        local joinId = raid.jid
        raidMenu.items[joinId] = MenuItem(raidMenu, posY, raid.name, function()
            local cfg = FinderCfg()
            if type(cfg.raidsHidden) ~= "table" then cfg.raidsHidden = {} end
            if RaidShown(joinId) then
                -- keep at least one raid ticked.
                local isShown = 0
                for _, o in ipairs(raidList or {}) do
                    if RaidShown(o.jid) then isShown = isShown + 1 end
                end
                if isShown <= 1 then return end
            end
            cfg.raidsHidden[joinId] = (not cfg.raidsHidden[joinId]) or nil
            if cfg.raidsHidden[joinId] and type(cfg.bosses) == "table" then
                for _, bo in ipairs(bosses or {}) do
                    if bo.raid == joinId then cfg.bosses[bo.key] = nil end
                end
            end
            mod.Search_Layout()
            RunFilters()
        end)
        posY = posY + ITEM_H
    end
    local div = raidMenu:CreateTexture(nil, "ARTWORK")
    Finder.Hairline(div)
    div:SetColorTexture(1, 1, 1, 0.10)
    div:SetPoint("TOPLEFT", raidMenu, "TOPLEFT", 1, -posY - 3)
    div:SetPoint("TOPRIGHT", raidMenu, "TOPRIGHT", -1, -posY - 3)
    posY = posY + 7
    raidMenu.items.worldBosses = MenuItem(raidMenu, posY, CludesUI.L("World Bosses"), function()
        local cfg = FinderCfg()
        cfg.hideWorldBosses = (not cfg.hideWorldBosses) or nil
        RunFilters()
        Paint()
    end)
    posY = posY + ITEM_H
    raidMenu:SetHeight(posY + 3)
    Finder.ClickOff(
        raidMenu,
        function(menu) return menu:IsMouseOver() or (raidBtn and raidBtn:IsMouseOver()) end
    )
    raidMenu:Hide()
end

local function PaintRaidMenu()
    if not (raidMenu and raidMenu:IsShown()) then return end
    for _, raid in ipairs(raidList or {}) do
        local entry = raidMenu.items[raid.jid]
        if entry then
            entry:SetChecked(RaidShown(raid.jid))
            entry:SetDimmed(not Finder.RaidEligible(raid.jid))
        end
    end
    if raidMenu.items.season then raidMenu.items.season:SetChecked(Finder.SeasonOnly()) end
    if raidMenu.items.worldBosses then raidMenu.items.worldBosses:SetChecked(not HideWorldBosses()) end
end

local function ToggleRaidMenu()
    if not raidMenu then BuildRaidMenu() end
    if raidMenu:IsShown() then
        raidMenu:Hide()
        return
    end
    raidMenu:ClearAllPoints()
    raidMenu:SetPoint("TOPLEFT", raidBtn, "BOTTOMLEFT", 0, -SQ_GAP)
    raidMenu:Show()
    PaintRaidMenu()
end

-- tier menu: all + tiers, applies right away.
local function BuildTierMenu()
    tierMenu = CreateFrame("Frame", nil, SP)
    tierMenu:SetFrameStrata("FULLSCREEN_DIALOG")
    tierMenu:EnableMouse(true)
    tierMenu:SetFrameLevel(300)
    tierMenu:SetClampedToScreen(true)
    local backdrop = tierMenu:CreateTexture(nil, "BACKGROUND")
    backdrop:SetAllPoints()
    local red, green, blue = ThemeFill()
    backdrop:SetColorTexture(red, green, blue, 0.98)
    local S = WindowSkin()
    if S and S.AddBorder then
        S.AddBorder(tierMenu)
    else
        CUI.MakeBorder(tierMenu, ThemeBorder())
    end
    local function Tiers()
        local cfg = FinderCfg()
        if type(cfg.delveTiers) ~= "table" then cfg.delveTiers = {} end
        return cfg.delveTiers
    end
    tierMenu.items = {}
    local posY = 3
    tierMenu.items.all = MenuItem(tierMenu, posY, ALL or "All", function()
        wipe(Tiers())
        RunFilters()
        Paint()
    end)
    posY = posY + ITEM_H
    local div = tierMenu:CreateTexture(nil, "ARTWORK")
    Finder.Hairline(div)
    div:SetColorTexture(1, 1, 1, 0.10)
    div:SetPoint("TOPLEFT", tierMenu, "TOPLEFT", 1, -posY - 3)
    div:SetPoint("TOPRIGHT", tierMenu, "TOPRIGHT", -1, -posY - 3)
    posY = posY + 7
    for tier = 1, MAX_TIER do
        tierMenu.items[tier] = MenuItem(tierMenu, posY, Finder.TierLabel(tier), function()
            local tbl = Tiers()
            tbl[tier] = (not tbl[tier]) or nil
            local _, n = PickedTiers()
            if n == MAX_TIER then wipe(tbl) end
            RunFilters()
            Paint()
        end)
        posY = posY + ITEM_H
    end
    tierMenu:SetHeight(posY + 3)
    tierMenu:SetScript("OnShow", function() DimForMenu(true) end)
    tierMenu:SetScript("OnHide", function() DimForMenu(false) end)
    Finder.ClickOff(
        tierMenu,
        function(menu) return menu:IsMouseOver() or (tierBtn and tierBtn:IsMouseOver()) end
    )
    tierMenu:Hide()
end

local function PaintTierMenu()
    if not (tierMenu and tierMenu:IsShown()) then return end
    local chosen = PickedTiers()
    tierMenu.items.all:SetChecked(chosen == nil)
    for tier = 1, MAX_TIER do
        tierMenu.items[tier]:SetChecked(chosen ~= nil and chosen[tier] == true)
    end
end

local function ToggleTierMenu()
    if not tierMenu then BuildTierMenu() end
    if tierMenu:IsShown() then
        tierMenu:Hide()
        return
    end
    tierMenu:ClearAllPoints()
    tierMenu:SetPoint("TOPLEFT", tierBtn, "BOTTOMLEFT", 0, -SQ_GAP)
    tierMenu:SetPoint("TOPRIGHT", refreshButton or tierBtn, "BOTTOMRIGHT", 0, -SQ_GAP)
    tierMenu:Show()
    PaintTierMenu()
end

local function BuildRow()
    line = CreateFrame("Frame", nil, SP)
    line:SetHeight(BTN)
    line:SetFrameLevel(SP:GetFrameLevel() + 5)
    difficultyBtn = DropButton(SP, DIFF_W, ROW1_H)
    difficultyBtn:SetFrameLevel(SP:GetFrameLevel() + 5)
    difficultyBtn:SetScript("OnClick", ToggleMenu)
    difficultyBtn:SetScript("OnHide", function()
        if dropMenu then dropMenu:Hide() end
        if raidDiffMenu then raidDiffMenu:Hide() end
    end)
    difficultyBtn:SetScript("OnLeave", Finder.PaintLabel)
    tierBtn = DropButton(SP, DIFF_W, ROW1_H)
    tierBtn:SetFrameLevel(SP:GetFrameLevel() + 5)
    tierBtn:SetScript("OnClick", ToggleTierMenu)
    tierBtn:SetScript("OnHide", function()
        if tierMenu then tierMenu:Hide() end
    end)
    tierBtn:SetScript("OnLeave", Finder.PaintLabel)
end

-- a drop button's label color from its last paint
function Finder.PaintLabel(button)
    if button.active then
        button.label:SetTextColor(AccentRGB())
    else
        button.label:SetTextColor(1, 1, 1, 1)
    end
end

-- repaint the filter row
Paint = function()
    if not SP then return end
    local frame = Finder.GetFilter()
    if not frame then return end
    if difficultyBtn then
        local isActive
        if SP.categoryID == RAIDS then
            isActive = ChosenRaidDiffs() or ChosenRaidPlaystyles() or ChosenRaidRoles()
        else
            isActive = not DiffAllOrNone(frame)
                or DungeonPlaystyles(frame)
                or DungeonRolesSet(frame)
                or (frame.minimumRating or 0) ~= 0
        end
        difficultyBtn.active = (isActive or RegionFilterActive() or Finder.ExtraFilterActive()) and true
            or false
        -- green edge while a filter's on, same as the expressions button
        if not difficultyBtn.activeEdge then
            local edge = CreateFrame("Frame", nil, difficultyBtn)
            edge:SetAllPoints()
            edge:SetFrameLevel(difficultyBtn:GetFrameLevel() + 3)
            edge:EnableMouse(false)
            CUI.MakeBorder(edge, 0.3, 0.85, 0.4, 1, CUI.PanelPP)
            difficultyBtn.activeEdge = edge
        end
        difficultyBtn.activeEdge:SetShown(difficultyBtn.active)
        difficultyBtn:SetText(CludesUI.L("Filters"))
        Finder.PaintLabel(difficultyBtn)
    end
    if tierBtn then
        local chosen, n = PickedTiers()
        if chosen then
            local textValue = CludesUI.Lf("Tier (%d)", n)
            if n == 1 then
                for index = 1, MAX_TIER do
                    if chosen[index] then textValue = Finder.TierLabel(index) end
                end
            end
            tierBtn:SetText(textValue)
        else
            tierBtn:SetText(CludesUI.L("Tier"))
        end
        tierBtn.active = chosen ~= nil
        Finder.PaintLabel(tierBtn)
    end
    local chosenDelves = ChosenDelves()
    for _, square in ipairs(delveSquares) do
        if square:IsShown() and square.delve then
            local isOn = chosenDelves and chosenDelves[square.delve.groupID] == true or false
            square.on = isOn
            square:GetFontString():SetAlpha(isOn and 1 or 0.4)
            Finder.PickBorder(square, square.edge, isOn)
            square.gold:SetShown(bountiful[square.delve.name] == true)
        end
    end
    PaintTierMenu()
    PaintRaidMenu()
    if raidBtn then
        local hidden = false
        for _, raid in ipairs(raidList or Finder.EMPTY) do
            if Finder.RaidEligible(raid.jid) and not RaidShown(raid.jid) then hidden = true end
        end
        if HideWorldBosses() then hidden = true end
        if hidden then
            raidBtn.Glyph:SetVertexColor(AccentRGB())
        else
            raidBtn.Glyph:SetVertexColor(1, 1, 1)
        end
    end
    -- bosses: all coloured until one's picked, then the rest grey out.
    local chosenBosses = ChosenBosses()
    for _, square in ipairs(bossSquares) do
        if square:IsShown() and square.boss then
            local pick = chosenBosses and chosenBosses[square.boss.key]
            local isOn = pick and true or false
            square.on = isOn
            square.icon:SetDesaturated(chosenBosses ~= nil and not isOn)
            square.icon:SetAlpha((chosenBosses == nil or isOn) and 1 or 0.45)
            -- green: alive, red: dead
            local edge = square.state or square
            if pick == "dead" then
                SetBorderColor(edge, 1, 0.15, 0.15, 1)
            elseif isOn then
                SetBorderColor(edge, 0.2, 1, 0.3, 1)
            else
                Finder.RestBorder(edge)
            end
            if not Finder.SkinOn() then
                if isOn then
                    square:LockHighlight()
                else
                    square:UnlockHighlight()
                end
            end
        end
    end
    local def = DungeonsDefault(frame)
    for _, square in ipairs(squares) do
        if square:IsShown() and square.dungeon then
            local isOn = not def and Contains(frame.activities, square.dungeon.groupID) ~= nil
            square.on = isOn
            square.icon:SetDesaturated(not def and not isOn)
            square.icon:SetAlpha((def or isOn) and 1 or 0.45)
            Finder.PickBorder(square, square, isOn)
        end
    end
    local filter = SP.FilterButton
    local frameData = filter and FFD[filter]
    if frameData then
        local callback = filter.isDefaultCallback
        local isDefault = true
        if callback then
            local success, val = pcall(callback)
            isDefault = (not success) or (val and true or false)
        end
        if Finder.DimActive() then isDefault = false end
        if
            RegionFilterActive()
            or DelveFilterActive()
            or BossFilterActive()
            or (ChosenRaidDiffs() or ChosenRaidPlaystyles() or ChosenRaidRoles()) and SP.categoryID == RAIDS
            or Finder.ExtraFilterActive()
        then
            isDefault = false
        end
        if resetBtn then
            resetBtn.active = not isDefault
            resetBtn.Glyph:SetAlpha(isDefault and 0.35 or 0.9)
        end
    end
    PaintMenu()
end

-- search again glyph: dim on cooldown, accent when filters changed.
PaintRefresh = function()
    if not refreshButton then return end
    if refreshButton.cover then refreshButton.cover:SetShown(GetTime() < cdUntil) end
    local g = refreshButton.Glyph
    if GetTime() < cdUntil then
        g:SetVertexColor(1, 1, 1)
        g:SetAlpha(0.3)
    elseif pending then
        g:SetVertexColor(AccentRGB())
        g:SetAlpha(1)
    else
        g:SetVertexColor(1, 1, 1)
        g:SetAlpha(refreshButton.hover and 1 or 0.8)
    end
end

local function StartCooldown(sec)
    local nowTime = GetTime()
    if nowTime + sec <= cdUntil then return end
    cdUntil = nowTime + sec
    if refreshButton and refreshButton.cd then refreshButton.cd:SetCooldown(nowTime, sec) end
    PaintRefresh()
    C_Timer.After(sec, PaintRefresh)
end

-------------------------------------------------------------------------------
-- layout
-------------------------------------------------------------------------------
-- the top-row settings button as seen
function Finder.FilterFace()
    local frame = SP and SP.FilterButton
    local skinData = frame and FFD[frame]
    return skinData and skinData.face or frame
end
mod.GFFilterFace = Finder.FilterFace

-- blizzard's filter dropdown becomes our settings cog.
local function CogFilterButton(button)
    if not button or FFD[button] then return end
    local skinData = { size = BTN }
    FFD[button] = skinData
    if button.Text then button.Text:SetAlpha(0) end
    if button.Background then button.Background:SetAlpha(0) end
    -- our own fixed-size face. blizzard's button grows with its text and
    -- only shrinks out of combat, so the row anchors to this
    button:SetAlpha(0)
    skinData.face = SkinnedButton(SP, BTN, BTN)
    skinData.face:EnableMouse(false) -- the catcher takes clicks
    skinData.face:SetFrameLevel(line:GetFrameLevel() + 3)
    skinData.cogFrame = CreateFrame("Frame", nil, skinData.face)
    skinData.cogFrame:SetAllPoints(skinData.face)
    skinData.cogFrame:SetFrameLevel(skinData.face:GetFrameLevel() + 3)
    skinData.cogFrame:EnableMouse(false)
    skinData.cog = skinData.cogFrame:CreateTexture(nil, "OVERLAY")
    skinData.cog:SetTexture(COG_TEX)
    skinData.cog:SetSize(14, 14)
    skinData.cog:SetDesaturated(true)
    skinData.cog:SetVertexColor(Finder.GLYPH, Finder.GLYPH, Finder.GLYPH)
    skinData.cog:SetPoint("CENTER")
    skinData.cog:SetAlpha(0.8)
    if button.ResetButton then
        button.ResetButton:SetAlpha(0)
        button.ResetButton:EnableMouse(false)
    end
    -- blizzard resizes it with its text; size it back (after combat if in it).
    hooksecurefunc(button, "UpdateText", function(self)
        local frameData = FFD[self]
        if not frameData then return end
        if InCombatLockdown() then
            Finder.Defer("layout", Finder.Layout)
            return
        end
        self:SetSize(frameData.size, frameData.size)
    end)
    -- opens the group finder settings: a click catcher sits over it
    button:EnableMouse(false)
    local catcher = CreateFrame("Button", nil, line)
    catcher:SetAllPoints(skinData.face)
    catcher:SetFrameLevel(skinData.face:GetFrameLevel() + 6)
    local wash = catcher:CreateTexture(nil, "HIGHLIGHT")
    wash:SetAllPoints()
    wash:SetColorTexture(1, 1, 1, 0.1)
    catcher:SetScript("OnEnter", function(self)
        skinData.cog:SetAlpha(1)
        Finder.Tip(self, CludesUI.L("Group Filters Settings"))
    end)
    catcher:SetScript("OnLeave", function()
        skinData.cog:SetAlpha(0.8)
        Finder.Untip()
    end)
    catcher:SetScript("OnClick", function()
        Finder.Untip()
        if InCombatLockdown() then
            CUI.PrintError(CludesUI.L("Cannot open options during combat."))
            return
        end
        CUI:ShowModule(ADDON_NAME)
    end)
    skinData.catcher = catcher

    -- reset uses blizzard's own defaults.
    resetBtn = GlyphButton(line, BTN, X_TEX)
    resetBtn.Glyph:SetVertexColor(Finder.GLYPH, Finder.GLYPH, Finder.GLYPH)
    resetBtn:SetScript("OnClick", function()
        local frame = Finder.GetFilter()
        frame.needsTank, frame.needsHealer, frame.needsDamage, frame.needsMyClass = false, false, false, false
        frame.hasTank, frame.hasHealer = false, false
        frame.minimumRating = 0
        FinderCfg().ratingOn = nil
        for index = 1, 4 do
            frame["generalPlaystyle" .. index] = true
        end
        for _, skinData in ipairs(DIFFS) do
            frame[skinData.key] = true
        end
        frame.activities = AllDungeonGroups()
        local cfg = FinderCfg()
        if type(cfg.regions) == "table" then wipe(cfg.regions) end
        if type(cfg.delves) == "table" then wipe(cfg.delves) end
        if type(cfg.delveTiers) == "table" then wipe(cfg.delveTiers) end
        if type(cfg.bosses) == "table" then wipe(cfg.bosses) end
        if type(cfg.raidDiffs) == "table" then wipe(cfg.raidDiffs) end
        if type(cfg.raidPlaystyles) == "table" then wipe(cfg.raidPlaystyles) end
        if type(cfg.raidRoles) == "table" then wipe(cfg.raidRoles) end
        cfg.partyFit, cfg.notDeclined, cfg.hasLust, cfg.hasBrez = nil, nil, nil, nil
        cfg.extraMyClass, cfg.raidMyClass = nil, nil
        if mod.ExtraExprReset then mod.ExtraExprReset() end
        if type(cfg.roleCounts) == "table" then wipe(cfg.roleCounts) end
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        Apply(frame)
        RunFilters()
    end)
    resetBtn:SetScript("OnEnter", function(self)
        self.Glyph:SetAlpha(1)
        Finder.Tip(self, CludesUI.L("Reset Filters"), not self.active and CludesUI.L("No filters set") or nil)
    end)
    resetBtn:SetScript("OnLeave", function(self)
        Finder.Untip()
        self.Glyph:SetAlpha(self.active and 0.9 or 0.35)
    end)
end

-- short dungeon name ('Altar of Fangs' -> AoF)
Finder.SMALL_WORDS = { of = true, the = true, ["and"] = true, to = true, ["in"] = true, on = true, at = true }
function Finder.Abbr(label)
    if type(label) ~= "string" then return "" end
    label = label:match("^([^,:]+)") or label
    local result = {}
    for word in label:gmatch("[^%s%-]+") do
        local wid = word:gsub("[^%a]", "")
        if wid ~= "" then
            local c = wid:sub(1, 1)
            if #result > 0 and Finder.SMALL_WORDS[wid:lower()] then
                c = c:lower()
            else
                c = c:upper()
            end
            result[#result + 1] = c
        end
    end
    local abbr = table.concat(result)
    if abbr == "" then abbr = Abbrev(label) end
    if abbr == "" then abbr = label end
    local shade = CludesUI._dungeonAbbrevOverride
    if shade and shade[abbr] then abbr = shade[abbr] end
    return abbr
end

-- the season's portal label when it's a seasonal dungeon, else initials
local portalShort, portalsDone
function Finder.ShortName(label)
    if type(label) ~= "string" or SecretVal(label) then return "" end
    if not portalsDone then
        -- dungeon names can be missing right after login, so keep asking until they're all in
        portalShort, portalsDone = {}, true
        for _, entry in ipairs(CludesUI.SEASON_PORTALS or Finder.EMPTY) do
            for _, n in ipairs(entry.names) do
                portalShort[n] = entry.short
            end
            local localized = GetLFGDungeonInfo and GetLFGDungeonInfo(entry.dungeonID)
            if type(localized) == "string" then
                portalShort[localized:lower()] = entry.short
            else
                portalsDone = false
            end
        end
    end
    local base = label:gsub("%s*%b()", "")
    local short = portalShort[base:lower()]
    return short and CludesUI.L(short) or Finder.Abbr(base)
end
mod.GFShortName = Finder.ShortName

-- text layer over a square, above its border
function Finder.SquareOverlay(square)
    local frame = square.overlay
    if not frame then
        frame = CreateFrame("Frame", nil, square)
        frame:SetAllPoints(square)
        frame:SetFrameLevel(square:GetFrameLevel() + 3)
        frame:EnableMouse(false)
        square.overlay = frame
    end
    return frame
end

-- short name on a square: at the top when keystone level shows too
function Finder.SquareAbbr(square, skinData, px)
    local isOn = FinderCfg().dungeonAbbr == true and skinData ~= nil
    if isOn and not square.abbr then
        square.abbr = Finder.SquareOverlay(square):CreateFontString(nil, "OVERLAY")
        square.abbr:SetJustifyH("CENTER")
        square.abbr:SetWordWrap(false)
    end
    if not square.abbr then return end
    if isOn then
        square.abbr:ClearAllPoints()
        if FinderCfg().dungeonScore == true then
            local posY = Finder.SkinOn() and -2 or -4 -- clear of blizzard's rounded edge
            square.abbr:SetPoint("TOPLEFT", square, "TOPLEFT", -4, posY)
            square.abbr:SetPoint("TOPRIGHT", square, "TOPRIGHT", 4, posY)
            square.abbr:SetJustifyV("TOP")
        else
            square.abbr:SetPoint("LEFT", square, "LEFT", -4, 0)
            square.abbr:SetPoint("RIGHT", square, "RIGHT", 4, 0)
            square.abbr:SetJustifyV("MIDDLE")
        end
        local fontStr = math.max(8, math.floor(px * 0.36))
        Finder.Font(square.abbr, fontStr, "OUTLINE")
        square.abbr:SetText(Finder.ShortName(skinData.name))
        while
            fontStr > 8
            and ((square.abbr.GetUnboundedStringWidth and square.abbr:GetUnboundedStringWidth()) or 0)
                > px - 4
        do
            fontStr = fontStr - 1
            Finder.Font(square.abbr, fontStr, "OUTLINE")
        end
        square.abbr:SetTextColor(1, 1, 1, 1)
    end
    square.abbr:SetShown(isOn)
end

-- best keystone level on a square, colored by its score
function Finder.SquareScore(square, skinData, px)
    local best
    if FinderCfg().dungeonScore == true and skinData ~= nil then
        local intime, overtime = C_MythicPlus.GetSeasonBestForMap(skinData.cmID)
        best = intime
        if overtime and (not best or overtime.dungeonScore >= best.dungeonScore) then best = overtime end
        if best and best.level <= 0 then best = nil end
    end
    if best and not square.score then
        square.score = Finder.SquareOverlay(square):CreateFontString(nil, "OVERLAY")
        square.score:SetWordWrap(false)
    end
    local fontStr = square.score
    if not fontStr then return end
    if best then
        local _, overall = C_MythicPlus.GetSeasonBestAffixScoreInfoForMap(skinData.cmID)
        local color = C_ChallengeMode.GetSpecificDungeonOverallScoreRarityColor(overall or best.dungeonScore)
        Finder.Font(fontStr, math.max(8, math.floor(px * 0.42)), "")
        fontStr:ClearAllPoints()
        if FinderCfg().dungeonAbbr == true then
            fontStr:SetPoint("BOTTOM", square, "BOTTOM", 0, Finder.SkinOn() and 2 or 4)
        else
            fontStr:SetPoint("CENTER", square, "CENTER", 0, 0)
        end
        fontStr:SetText(best.level)
        if color then
            fontStr:SetTextColor(color.r, color.g, color.b, 1)
        else
            fontStr:SetTextColor(1, 1, 1, 1)
        end
    end
    fontStr:SetShown(best ~= nil)
end

local function LayoutSquares(px, after, show)
    local entries = dungeons or {}
    local previous = after
    for index = 1, math.max(#entries, #squares) do
        local skinData = entries[index]
        local square = squares[index]
        if skinData and show then
            if not square then
                square = MakeSquare(line)
                squares[index] = square
            end
            square.dungeon = skinData
            square:SetSize(px, px)
            square:ClearAllPoints()
            square:SetPoint("LEFT", previous, "RIGHT", SQ_GAP, 0)
            square.icon:SetTexture(skinData.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            Finder.SquareScore(square, skinData, px)
            Finder.SquareAbbr(square, skinData, px)
            square:Show()
            previous = square
        elseif square then
            square.dungeon = nil
            square:Hide()
        end
    end
end

-- back / sign up's font, a size smaller
function Finder.ButtonFont()
    local source = SP and (SP.BackButton or SP.SignUpButton)
    local fontStr = source and source.GetFontString and source:GetFontString()
    local filePath, px, flags
    if fontStr then
        filePath, px, flags = fontStr:GetFont()
    end
    if not filePath then return nil end
    if not gfFont then gfFont = CreateFont("CUIGroupFinderButtonFont") end
    gfFont:SetFont(filePath, math.max(8, px - 1), flags or "")
    gfFont:SetTextColor(1, 1, 1)
    return gfFont
end

local function MatchButtonFont(checkBox)
    if not Finder.ButtonFont() then return end
    difficultyBtn:SetNormalFontObject(gfFont)
    difficultyBtn:SetHighlightFontObject(gfFont)
    tierBtn:SetNormalFontObject(gfFont)
    tierBtn:SetHighlightFontObject(gfFont)
    if checkBox then
        checkBox:SetFontObject(gfFont)
        if checkBox.Instructions then
            checkBox.Instructions:SetFontObject(gfFont)
            checkBox.Instructions:SetTextColor(0.4, 0.4, 0.4)
        end
    end
end

-- row positions, for the applications card.
function mod.Search_Rows()
    local padding = tonumber(FinderCfg().padding) or 12
    local wid = SP and SP:GetWidth()
    if not wid or wid < 100 then wid = 338 end
    local entries = Finder.Dungeons()
    local n = (entries and #entries > 0) and #entries or 8
    return ROW1_Y, ROW2_Y, math.max(18, (wid - padding * 2 - (n + 1) * SQ_GAP) / (n + 2)), ROW1_H
end

-- lays the panel out. blizzard's frames only move out of combat
local function LayoutPanel()
    if not (SP and SP:IsVisible()) then return end
    if InCombatLockdown() then
        Finder.Defer("layout", Finder.Layout)
        Paint()
        return
    end
    Finder.NewPass()
    local cfg = FinderCfg()
    local padding = tonumber(cfg.padding) or 12
    local showFilters = SP.categoryID == DUNGEONS
    local showDiff = SP.categoryID == DUNGEONS or SP.categoryID == RAIDS
    local showDelves = SP.categoryID == DELVES
    local showBosses = RaidsCurrent()
    if not line then BuildRow() end
    local entries = Finder.Dungeons()
    if showDelves then
        if not delves then
            delves, delveByActivity = BuildDelves()
        end
        ScanBountiful()
    end
    if showBosses and not bosses then
        bosses, raidByActivity, raidList = BuildBosses()
    end

    -- one square size that fills row 2 exactly.
    local rowW = (SP:GetWidth() or 338) - padding * 2
    local n = (entries and #entries > 0) and #entries or 8
    local px = math.max(18, (rowW - (n + 1) * SQ_GAP) / (n + 2))

    -- row 1: search box, filters, search again.
    local filter, checkBox, title = SP.FilterButton, SP.SearchBox, SP.CategoryName
    if title then title:SetAlpha(0) end
    if not refreshButton then
        local refreshBtn = SP.RefreshButton
        refreshButton = GlyphButton(SP, ROW1_H, "UI-RefreshButton", true)
        refreshButton:SetFrameLevel(SP:GetFrameLevel() + 5)
        refreshButton:EnableMouse(false) -- blizzard's button underneath takes the click
        refreshButton.Glyph:SetSize(14, 14)
        local px = CUI.PP.mult
        local cd = CreateFrame("Cooldown", nil, refreshButton, "CooldownFrameTemplate")
        cd:SetPoint("TOPLEFT", refreshButton, "TOPLEFT", px, -px)
        cd:SetPoint("BOTTOMRIGHT", refreshButton, "BOTTOMRIGHT", -px, px)
        if cd.SetDrawEdge then cd:SetDrawEdge(false) end
        if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end
        if cd.SetSwipeColor then cd:SetSwipeColor(0, 0, 0, 0.65) end
        refreshButton.cd = cd
        local function Tip(ownerFrame)
            refreshButton.hover = true
            refreshButton:LockHighlight()
            PaintRefresh()
            Finder.Tip(
                ownerFrame,
                LFG_LIST_SEARCH_AGAIN or "Search Again",
                CludesUI.Lf("Limited to every %d seconds to prevent lock-out", CD_SEARCH),
                pending and CludesUI.L("Filters changed: search to update the list") or nil
            )
        end
        local function Untip()
            refreshButton.hover = nil
            refreshButton:UnlockHighlight()
            PaintRefresh()
            Finder.Untip()
        end
        if refreshBtn then
            refreshBtn:SetAlpha(0)
            refreshBtn:HookScript("OnEnter", Tip)
            refreshBtn:HookScript("OnLeave", Untip)
        end
        local cover = CreateFrame("Button", nil, SP)
        cover:SetAllPoints(refreshButton)
        cover:SetFrameLevel(refreshButton:GetFrameLevel() + 8)
        cover:SetScript("OnEnter", Tip)
        cover:SetScript("OnLeave", Untip)
        cover:Hide()
        refreshButton.cover = cover
        PaintRefresh()
    end
    refreshButton:ClearAllPoints()
    refreshButton:SetPoint("RIGHT", SP, "TOPRIGHT", -padding, ROW1_Y)
    local blzRefresh = SP.RefreshButton
    if blzRefresh then
        blzRefresh:ClearAllPoints()
        blzRefresh:SetAllPoints(refreshButton)
        blzRefresh:SetFrameLevel(refreshButton:GetFrameLevel() + 4)
    end
    -- a button left of refresh; row 1 ends at it
    local row1End = refreshButton
    if mod.ExtraExprButton then
        row1End = mod.ExtraExprButton(
            SP,
            refreshButton,
            SP.categoryID == DUNGEONS or SP.categoryID == RAIDS,
            {
                GlyphButton = GlyphButton,
                ROW1_H = ROW1_H,
                GAP = SQ_GAP,
                Refilter = RunFilters,
                Tip = Finder.Tip,
                Untip = Finder.Untip,
                ClickOff = Finder.ClickOff,
                Font = Finder.Font,
                ThemeFill = ThemeFill,
                ThemeBorder = ThemeBorder,
                Accent = AccentRGB,
                GLYPH = Finder.GLYPH,
                Dim = DimForMenu,
                Filters = difficultyBtn,
                DIM_ALPHA = Finder.DIM_ALPHA,
                FiltersOpen = function()
                    return (dropMenu and dropMenu:IsShown())
                        or (raidDiffMenu and raidDiffMenu:IsShown())
                        or false
                end,
            }
        ) or refreshButton
    end
    difficultyBtn:ClearAllPoints()
    difficultyBtn:SetPoint("RIGHT", row1End, "LEFT", -SQ_GAP, 0)
    difficultyBtn:SetShown(showDiff)
    if not showDiff or SP.categoryID ~= RAIDS then
        if raidDiffMenu then raidDiffMenu:Hide() end
    end
    if SP.categoryID ~= DUNGEONS and dropMenu then dropMenu:Hide() end
    tierBtn:ClearAllPoints()
    tierBtn:SetPoint("RIGHT", row1End, "LEFT", -SQ_GAP, 0)
    tierBtn:SetShown(showDelves)
    if checkBox then
        checkBox:ClearAllPoints()
        checkBox:SetPoint("LEFT", SP, "TOPLEFT", padding, ROW1_Y)
        checkBox:SetPoint(
            "RIGHT",
            (showDiff and difficultyBtn) or (showDelves and tierBtn) or row1End,
            "LEFT",
            -SQ_GAP,
            0
        )
        checkBox:SetHeight(ROW1_H)
        SetBorderColor(checkBox, ThemeBorder())
        -- shorter prompt (runs after blizzard sets its own).
        if checkBox.Instructions then
            checkBox.Instructions:SetText(CludesUI.Lf("%s (e.g. 10-12)", SEARCH or "Search"))
        end
    end
    MatchButtonFont(checkBox)

    -- row 2: cog, reset, dungeon squares.
    line:ClearAllPoints()
    line:SetPoint("TOPLEFT", SP, "TOPLEFT", padding, ROW2_Y)
    line:SetPoint("TOPRIGHT", SP, "TOPRIGHT", -padding, ROW2_Y)
    line:SetHeight(px)
    line:Show()
    if filter then
        CogFilterButton(filter)
        local frameData = FFD[filter]
        frameData.size = px
        frameData.cog:SetSize(math.floor(px * 0.55), math.floor(px * 0.55))
        filter:SetSize(px, px)
        filter:ClearAllPoints()
        filter:SetPoint("LEFT", line, "LEFT", 0, 0)
        frameData.face:SetSize(px, px)
        frameData.face:ClearAllPoints()
        frameData.face:SetPoint("LEFT", line, "LEFT", 0, 0)
        frameData.face:Show()
        filter = frameData.face -- the row anchors to our face from here
    end
    if resetBtn then
        resetBtn:SetSize(px, px)
        resetBtn.Glyph:SetSize(math.floor(px * 0.5), math.floor(px * 0.5))
        resetBtn:ClearAllPoints()
        if filter then
            resetBtn:SetPoint("LEFT", filter, "RIGHT", SQ_GAP, 0)
        else
            resetBtn:SetPoint("LEFT", line, "LEFT", 0, 0)
        end
        resetBtn:Show()
    end
    LayoutSquares(px, resetBtn or filter, showFilters)
    -- delves: right-aligned grid, list moves down for extra lines.
    local lines = LayoutDelves(px, resetBtn or filter, showDelves, math.max(1, n - 1), n)
    -- raids: map button after the reset, bosses in the grid.
    if showBosses and not raidBtn then
        raidBtn = GlyphButton(line, BTN, mod.ExtraRaidTex)
        raidBtn:SetScript("OnClick", ToggleRaidMenu)
        raidBtn:SetScript("OnHide", function()
            if raidMenu then raidMenu:Hide() end
        end)
        raidBtn:SetScript("OnEnter", function(self)
            self.Glyph:SetAlpha(1)
            Finder.Tip(self, CludesUI.L("Raids"), CludesUI.L("Choose which raids' bosses are shown"))
        end)
        raidBtn:SetScript("OnLeave", function(self)
            self.Glyph:SetAlpha(0.8)
            Finder.Untip()
        end)
    end
    if raidBtn then
        raidBtn:SetShown(showBosses and raidList ~= nil)
        raidBtn:SetSize(px, px)
        raidBtn.Glyph:SetSize(math.floor(px * 0.55), math.floor(px * 0.55))
        raidBtn:ClearAllPoints()
        local after = resetBtn or filter
        if after then
            raidBtn:SetPoint("LEFT", after, "RIGHT", SQ_GAP, 0)
        else
            raidBtn:SetPoint("LEFT", line, "LEFT", 0, 0)
        end
    end
    lines = math.max(lines, LayoutBosses(px, resetBtn or filter, showBosses, math.max(1, n - 1), n))

    -- result list fills the space between row 2 and the bottom buttons.
    local ROW_INSET = 3
    local topY = ROW2_Y - lines * px - (lines - 1) * SQ_GAP - SQ_GAP
    local bottom = BOTTOM_Y + 22 + SQ_GAP
    local scroll, barFrame, inset = SP.ScrollBox, SP.ScrollBar, SP.ResultsInset
    if barFrame then
        barFrame:ClearAllPoints()
        barFrame:SetPoint("TOP", SP, "TOPRIGHT", -padding / 2, topY)
        barFrame:SetPoint("BOTTOM", SP, "BOTTOMRIGHT", -padding / 2, bottom)
    end
    if scroll then
        scroll:ClearAllPoints()
        scroll:SetPoint("TOPLEFT", SP, "TOPLEFT", padding - ROW_INSET, topY)
        scroll:SetPoint("BOTTOMRIGHT", SP, "BOTTOMRIGHT", -padding + ROW_INSET, bottom)
    end
    if inset then
        inset:ClearAllPoints()
        inset:SetPoint("TOPLEFT", SP, "TOPLEFT", padding, topY)
        inset:SetPoint("BOTTOMRIGHT", SP, "BOTTOMRIGHT", -padding, bottom)
    end
    Finder.PinBottomButtons(SP, Finder.SEARCH_LEFT, "SignUpButton")
    Paint()
end
mod.Search_Layout = LayoutPanel
Finder.Layout = LayoutPanel
Finder.SEARCH_LEFT = { "BackButton", "BackToGroupButton" }

-- first show asks for this season's m+ maps
function Finder.PanelShown()
    Finder.RestoreCharFilter()
    if not Finder.mapInfoAsked then
        Finder.mapInfoAsked = true
        if C_MythicPlus and C_MythicPlus.RequestMapInfo then C_MythicPlus.RequestMapInfo() end
    end
    LayoutPanel()
end

-- bottom row: the buttons split the width.
local function PinBottomButtons(panelFrame, lefts, right)
    if not panelFrame or InCombatLockdown() then return end
    if type(lefts) ~= "table" then lefts = { lefts } end
    local padding = tonumber(FinderCfg().padding) or 12
    local x0 = padding
    local pw = panelFrame:GetWidth()
    local wid = (type(pw) == "number" and pw > 0) and (pw - padding - x0 - SQ_GAP) / 2 or nil
    for _, key in ipairs(lefts) do
        local widget = panelFrame[key]
        if type(widget) == "table" then
            widget:ClearAllPoints()
            widget:SetPoint("BOTTOMLEFT", panelFrame, "BOTTOMLEFT", x0, BOTTOM_Y)
            if wid then widget:SetWidth(wid) end
        end
    end
    local rb = panelFrame[right]
    if type(rb) == "table" then
        rb:ClearAllPoints()
        rb:SetPoint("BOTTOMRIGHT", panelFrame, "BOTTOMRIGHT", -padding, BOTTOM_Y)
        if wid then rb:SetWidth(wid) end
    end
end
Finder.PinBottomButtons = PinBottomButtons

-- category list spans the side padding (out of combat, else once it ends).
local function LayoutCategoryList()
    if InCombatLockdown() then
        Finder.Defer("categoryList", LayoutCategoryList)
        return
    end
    local CS = LFGListFrame and LFGListFrame.CategorySelection
    local cfg = FinderCfg()
    if not (CS and type(CS.CategoryButtons) == "table") then return end
    local padding = tonumber(cfg.padding) or 12
    for index, btn in ipairs(CS.CategoryButtons) do
        btn:ClearAllPoints()
        if index == 1 then
            btn:SetPoint("TOPLEFT", CS, "TOPLEFT", padding, -77)
            btn:SetPoint("TOPRIGHT", CS, "TOPRIGHT", -padding, -77)
        else
            local previous = CS.CategoryButtons[index - 1]
            btn:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -3)
            btn:SetPoint("TOPRIGHT", previous, "BOTTOMRIGHT", 0, -3)
        end
    end
end

local function LayoutCategoryButtons()
    if InCombatLockdown() then
        Finder.Defer("categoryButtons", LayoutCategoryButtons)
        return
    end
    PinBottomButtons(
        LFGListFrame and LFGListFrame.CategorySelection,
        { "StartGroupButton" },
        "FindGroupButton"
    )
    LayoutCategoryList()
end

-- blizzard dropdown in our filters button look.
local function StyleEntryDropdown(dropdown)
    if not dropdown then return end
    SetBorderColor(dropdown, ThemeBorder())
    local labelText = dropdown.Text
    local font = gfFont or Finder.ButtonFont()
    if labelText and font then
        labelText:SetFontObject(font)
        labelText:SetTextColor(1, 1, 1, 1)
        labelText:ClearAllPoints()
        labelText:SetPoint("LEFT", dropdown, "LEFT", 9, 0)
        labelText:SetPoint("RIGHT", dropdown, "RIGHT", -24, 0)
        labelText:SetJustifyH("LEFT")
    end
    for _, region in ipairs({ dropdown:GetRegions() }) do
        if region.GetAtlas and region:GetAtlas() == "Azerite-PointingArrow" then
            region:SetDesaturated(true)
            region:SetVertexColor(1, 1, 1, 0.8)
            region:SetSize(11, 8)
            region:ClearAllPoints()
            region:SetPoint("RIGHT", dropdown, "RIGHT", -8, 0)
        end
    end
end

-- start a group option rows
Finder.ENTRY_BOX_ROWS = { "MythicPlusRating", "PVPRating", "ItemLevel", "PvpItemLevel", "VoiceChat" }
Finder.ENTRY_CHECK_ROWS =
    { "MythicPlusRating", "PVPRating", "ItemLevel", "PvpItemLevel", "VoiceChat", "CrossFactionGroup" }
Finder.ENTRY_SWITCH_ROWS = {
    "MythicPlusRating",
    "PVPRating",
    "ItemLevel",
    "PvpItemLevel",
    "VoiceChat",
    "CrossFactionGroup",
    "PrivateGroup",
}
Finder.TXT_X, Finder.TXT_Y = 6, 4 -- text padding inside the boxes

-- start a group: lined up on the bottom buttons' padding
local function LayoutEntryFields()
    if InCombatLockdown() then
        Finder.Defer("entryFields", LayoutEntryFields)
        return
    end
    local EntryCreate = LFGListFrame and LFGListFrame.EntryCreation
    local cfg = FinderCfg()
    if not EntryCreate then return end
    local padding = tonumber(cfg.padding) or 12
    local W = EntryCreate:GetWidth()
    if type(W) ~= "number" or W <= 0 then return end
    local inner = W - padding * 2
    local set, activity = EntryCreate.GroupDropdown, EntryCreate.ActivityDropdown
    if set then
        set:ClearAllPoints()
        set:SetPoint("TOPLEFT", EntryCreate, "TOPLEFT", padding, -76)
        if activity and activity:IsShown() then
            local half = (inner - SQ_GAP) / 2
            set:SetWidth(half)
            activity:ClearAllPoints()
            activity:SetPoint("LEFT", set, "RIGHT", SQ_GAP, 0)
            activity:SetWidth(half)
        else
            set:SetWidth(inner)
        end
    end
    local nameLabel, descLabel = EntryCreate.NameLabel, EntryCreate.DescriptionLabel
    if nameLabel then
        nameLabel:ClearAllPoints()
        nameLabel:SetPoint("TOPLEFT", EntryCreate, "TOPLEFT", padding, -120)
    end
    local label = EntryCreate.Name
    if label and nameLabel then
        label:ClearAllPoints()
        label:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 0, -5)
        label:SetPoint("TOPRIGHT", nameLabel, "BOTTOMLEFT", inner, -5)
    end
    local desc = EntryCreate.Description
    if desc and descLabel then
        desc:ClearAllPoints()
        desc:SetPoint("TOPLEFT", descLabel, "BOTTOMLEFT", 0, -10)
        desc:SetPoint("TOPRIGHT", descLabel, "BOTTOMLEFT", inner, -10)
        if desc.EditBox then desc.EditBox:SetWidth(inner - 18) end
    end
    local TXT_X, TXT_Y = Finder.TXT_X, Finder.TXT_Y
    if label and label.SetTextInsets then
        pcall(label.SetTextInsets, label, TXT_X, TXT_X, 0, 0)
        local ins = label.Instructions
        if type(ins) == "table" then
            ins:ClearAllPoints()
            ins:SetPoint("TOPLEFT", label, "TOPLEFT", TXT_X, 0)
            ins:SetPoint("BOTTOMRIGHT", label, "BOTTOMRIGHT", -TXT_X, 0)
        end
    end
    local deb = desc and desc.EditBox
    if deb and deb.SetTextInsets then
        pcall(deb.SetTextInsets, deb, TXT_X, TXT_X, TXT_Y, TXT_Y)
        if type(deb.Instructions) == "table" then
            deb.Instructions:ClearAllPoints()
            deb.Instructions:SetPoint("TOPLEFT", deb, "TOPLEFT", TXT_X, -TXT_Y)
            deb.Instructions:SetWidth(inner - TXT_X * 2)
        end
    end
    -- shorter placeholders (voice chat says discord).
    local vc = EntryCreate.VoiceChat and EntryCreate.VoiceChat.EditBox
    if vc and type(vc.Instructions) == "table" then vc.Instructions:SetText("Discord") end
    local il = EntryCreate.ItemLevel and EntryCreate.ItemLevel.EditBox
    if il and type(il.Instructions) == "table" then il.Instructions:SetAlpha(0) end
    local style = EntryCreate.PlayStyleDropdown
    if style and desc then
        style:ClearAllPoints()
        style:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -20)
        style:SetPoint("TOPRIGHT", desc, "BOTTOMRIGHT", 0, -20)
    end
    StyleEntryDropdown(set)
    StyleEntryDropdown(activity)
    StyleEntryDropdown(style)
    -- option rows line up a frame later, once the layout settles
    if not Finder.alignQueued then
        Finder.alignQueued = true
        C_Timer.After(0, Finder.AlignEntryRows)
    end
end

-- the switch's width, or blizzard's check box with the skin off
function Finder.CheckW(callback)
    if Finder.SkinOn() then return 30 end
    local wid = callback:GetWidth()
    return (type(wid) == "number" and wid > 0) and wid or 22
end

-- option row alignment
function Finder.AlignEntryRows()
    Finder.alignQueued = nil
    if InCombatLockdown() then
        Finder.Defer("entryFields", LayoutEntryFields)
        return
    end
    local EntryCreate = LFGListFrame and LFGListFrame.EntryCreation
    local style = EntryCreate and EntryCreate.PlayStyleDropdown
    local sr = style and style:GetRight()
    if not sr then return end
    local TXT_X = Finder.TXT_X
    local lg = EntryCreate.ListGroupButton
    local bw = type(lg) == "table" and lg:GetWidth()
    for _, key in ipairs(Finder.ENTRY_BOX_ROWS) do
        local line = EntryCreate[key]
        local checkBox = type(line) == "table" and line.EditBox
        local rr = type(line) == "table" and line.GetRight and line:GetRight()
        if checkBox and rr then
            local off = sr - rr
            checkBox:ClearAllPoints()
            checkBox:SetPoint("RIGHT", line, "RIGHT", off, 0)
            checkBox:SetWidth((type(bw) == "number" and bw > 0) and bw or (125 + 5 + off))
            if checkBox.SetTextInsets then pcall(checkBox.SetTextInsets, checkBox, TXT_X, TXT_X, 0, 0) end
            local ins = checkBox.Instructions
            if type(ins) == "table" then
                ins:ClearAllPoints()
                ins:SetPoint("LEFT", checkBox, "LEFT", TXT_X, 0)
                ins:SetPoint("RIGHT", checkBox, "RIGHT", -TXT_X, 0)
            end
        end
    end
    local sl = style:GetLeft()
    for _, key in ipairs(Finder.ENTRY_CHECK_ROWS) do
        local line = EntryCreate[key]
        local callback = type(line) == "table" and line.CheckButton
        local rl = type(line) == "table" and line.GetLeft and line:GetLeft()
        if type(callback) == "table" and sl and rl then
            callback:ClearAllPoints()
            callback:SetPoint("LEFT", line, "LEFT", sl - rl, 0)
            if line.Label then
                line.Label:ClearAllPoints()
                line.Label:SetPoint("LEFT", callback, "LEFT", Finder.CheckW(callback) + 6, 0)
            end
        end
    end
    local vbox = EntryCreate.VoiceChat and EntryCreate.VoiceChat.EditBox
    local prow = EntryCreate.PrivateGroup
    local pcb = type(prow) == "table" and prow.CheckButton
    local bl = type(vbox) == "table" and vbox:GetLeft()
    local pl = type(prow) == "table" and prow.GetLeft and prow:GetLeft()
    if type(pcb) == "table" and bl and pl then
        pcb:ClearAllPoints()
        pcb:SetPoint("LEFT", prow, "LEFT", bl - pl, 0)
        if prow.Label then
            prow.Label:ClearAllPoints()
            prow.Label:SetPoint("LEFT", pcb, "LEFT", Finder.CheckW(pcb) + 6, 0)
        end
    end
end

-------------------------------------------------------------------------------
-- start a group options (min. iLvl, min. rating, voice chat, ...) as switches
-------------------------------------------------------------------------------
local SW_W, SW_H, SW_PAD = 30, 16, 2

-- checked state; it can be secret (e.g. editing a listing mid-encounter), then
-- returns nil, true.
local function CheckedState(callback)
    local val = callback:GetChecked()
    if SecretVal(val) then return nil, true end
    return val and true or false, false
end

local function PaintSwitch(callback)
    local skinData = FFD[callback]
    if not skinData then return end
    local raw = callback:GetChecked()
    local enabled = callback:IsEnabled()
    local swatchBtn = skinData.switch
    local red, green, blue = AccentRGB()
    swatchBtn.trackOn:SetColorTexture(red, green, blue, 0.75)
    if SecretVal(raw) then
        -- secret: draw both looks and let the value pick one.
        swatchBtn.trackOn:SetAlphaFromBoolean(raw, 1, 0)
        swatchBtn.knobOn:SetAlphaFromBoolean(raw, 1, 0)
        swatchBtn.trackOff:SetAlphaFromBoolean(raw, 0, 1)
        swatchBtn.knobOff:SetAlphaFromBoolean(raw, 0, 1)
        swatchBtn:SetAlpha(enabled and 1 or 0.4)
        return
    end
    local isOn = raw and true or false
    swatchBtn.trackOn:SetAlpha(isOn and 1 or 0)
    swatchBtn.knobOn:SetAlpha(isOn and 1 or 0)
    swatchBtn.trackOff:SetAlpha(isOn and 0 or 1)
    swatchBtn.knobOff:SetAlpha(isOn and 0 or 1)
    swatchBtn:SetAlpha(enabled and 1 or 0.4)
    local line = skinData.row
    local dim = (isOn and enabled) and 1 or 0.45
    if line and line.Label then line.Label:SetAlpha(dim) end
    local checkBox = line and line.EditBox
    if checkBox then
        checkBox:SetAlpha(dim)
        -- no typing while it's off.
        if not (isOn and enabled) and checkBox.HasFocus and checkBox:HasFocus() then checkBox:ClearFocus() end
        if checkBox.SetEnabled then checkBox:SetEnabled(isOn and enabled) end
    end
end

local function SwitchCheckbox(line)
    if type(line) ~= "table" then return end
    local callback = line.CheckButton
    if type(callback) ~= "table" then return end
    if not FFD[callback] then
        local skinData = { row = line }
        FFD[callback] = skinData
        for _, childFrame in ipairs({ callback:GetChildren() }) do
            childFrame:SetAlpha(0)
        end
        local swatchBtn = CreateFrame("Frame", nil, callback)
        swatchBtn:SetSize(SW_W, SW_H)
        swatchBtn:SetPoint("LEFT", callback, "LEFT", 0, 0)
        swatchBtn:SetFrameLevel(callback:GetFrameLevel() + 3)
        swatchBtn:EnableMouse(false)
        swatchBtn.trackOff = swatchBtn:CreateTexture(nil, "BACKGROUND")
        swatchBtn.trackOff:SetAllPoints()
        swatchBtn.trackOff:SetColorTexture(0.267, 0.267, 0.267, 0.65)
        swatchBtn.trackOn = swatchBtn:CreateTexture(nil, "BACKGROUND", nil, 1)
        swatchBtn.trackOn:SetAllPoints()
        swatchBtn.knobOff = swatchBtn:CreateTexture(nil, "ARTWORK")
        swatchBtn.knobOff:SetSize(SW_H - SW_PAD * 2, SW_H - SW_PAD * 2)
        swatchBtn.knobOff:SetPoint("LEFT", swatchBtn, "LEFT", SW_PAD, 0)
        swatchBtn.knobOff:SetColorTexture(1, 1, 1, 0.5)
        swatchBtn.knobOn = swatchBtn:CreateTexture(nil, "ARTWORK", nil, 1)
        swatchBtn.knobOn:SetSize(SW_H - SW_PAD * 2, SW_H - SW_PAD * 2)
        swatchBtn.knobOn:SetPoint("RIGHT", swatchBtn, "RIGHT", -SW_PAD, 0)
        swatchBtn.knobOn:SetColorTexture(1, 1, 1, 1)
        skinData.switch = swatchBtn
        if line.Label then
            line.Label:ClearAllPoints()
            line.Label:SetPoint("LEFT", line, "LEFT", SW_W + 6, 0)
        end
        skinData.curOn = CheckedState(callback)
        hooksecurefunc(callback, "SetChecked", function(self, val)
            local frameData = FFD[self]
            if frameData then
                -- don't remember secret values.
                local nowTime = nil
                if not SecretVal(val) then nowTime = val and true or false end
                frameData.prevOn, frameData.curOn, frameData.setAt = frameData.curOn, nowTime, GetTime()
            end
            PaintSwitch(self)
        end)
        if callback.SetEnabled then hooksecurefunc(callback, "SetEnabled", PaintSwitch) end
        callback:HookScript("OnClick", function(self)
            local frameData = FFD[self]
            local isOn = CheckedState(self)
            if frameData then frameData.curOn = isOn end
            PaintSwitch(self)
            -- blizzard focuses the box before we enable it.
            local checkBox = frameData and frameData.row and frameData.row.EditBox
            if checkBox and isOn and checkBox.SetFocus then checkBox:SetFocus() end
        end)
        if line.EditBox and line.EditBox.HookScript then
            -- blizzard re-enables these, so refuse focus while off
            line.EditBox:HookScript("OnEditFocusGained", function(checkBox)
                if CheckedState(callback) == false then checkBox:ClearFocus() end
            end)
            if line.EditBox.SetEnabled then
                hooksecurefunc(line.EditBox, "SetEnabled", function(checkBox, val)
                    if
                        not SecretVal(val)
                        and val
                        and CheckedState(callback) == false
                        and not FFD[callback].reEnable
                    then
                        FFD[callback].reEnable = true
                        checkBox:SetEnabled(false)
                        FFD[callback].reEnable = nil
                    end
                end)
            end
            line.EditBox:HookScript("OnEditFocusLost", function()
                local frameData = FFD[callback]
                if
                    frameData
                    and frameData.prevOn
                    and frameData.curOn == false
                    and frameData.setAt == GetTime()
                then
                    callback:SetChecked(true)
                end
            end)
        end
    end
    PaintSwitch(callback)
end

-- option check buttons as switches
local function LayoutEntrySwitches()
    if InCombatLockdown() then
        Finder.Defer("entrySwitches", LayoutEntrySwitches)
        return
    end
    local EntryCreate = LFGListFrame and LFGListFrame.EntryCreation
    if not EntryCreate or not Finder.SkinOn() then return end
    for _, key in ipairs(Finder.ENTRY_SWITCH_ROWS) do
        SwitchCheckbox(EntryCreate[key])
    end
end

local function LayoutEntryButtons()
    if InCombatLockdown() then
        Finder.Defer("entryButtons", LayoutEntryButtons)
        return
    end
    PinBottomButtons(LFGListFrame and LFGListFrame.EntryCreation, { "CancelButton" }, "ListGroupButton")
    LayoutEntryFields()
    LayoutEntrySwitches()
end
mod.Search_LayoutEntry = LayoutEntryButtons

-- the listed group's bottom row: three equal buttons
local function LayoutViewerButtons(AppViewer)
    local padding = tonumber(FinderCfg().padding) or 12
    local x0 = padding
    local pw = AppViewer:GetWidth()
    if not (type(pw) == "number" and pw > 0) then return end
    local wid = (pw - padding - x0 - SQ_GAP * 2) / 3
    local browse, delist, edit =
        AppViewer.BrowseGroupsButton, AppViewer.RemoveEntryButton, AppViewer.EditButton
    browse:ClearAllPoints()
    browse:SetPoint("BOTTOMLEFT", AppViewer, "BOTTOMLEFT", x0, BOTTOM_Y)
    browse:SetWidth(wid)
    delist:ClearAllPoints()
    delist:SetPoint("BOTTOMLEFT", AppViewer, "BOTTOMLEFT", x0 + wid + SQ_GAP, BOTTOM_Y)
    delist:SetWidth(wid)
    edit:ClearAllPoints()
    edit:SetPoint("BOTTOMRIGHT", AppViewer, "BOTTOMRIGHT", -padding, BOTTOM_Y)
    edit:SetWidth(wid)
end

-- same look as search again, blizzard's button underneath takes the click
local function LayoutViewerRefresh(AppViewer)
    local refreshBtn = AppViewer.RefreshButton
    if not Finder.viewerRefresh then
        local lookName = GlyphButton(AppViewer, ROW1_H, "UI-RefreshButton", true)
        lookName:SetFrameLevel(AppViewer:GetFrameLevel() + 5)
        lookName:EnableMouse(false)
        lookName.Glyph:SetSize(14, 14)
        local px = CUI.PP.mult
        local cd = CreateFrame("Cooldown", nil, lookName, "CooldownFrameTemplate")
        cd:SetPoint("TOPLEFT", lookName, "TOPLEFT", px, -px)
        cd:SetPoint("BOTTOMRIGHT", lookName, "BOTTOMRIGHT", -px, px)
        if cd.SetDrawEdge then cd:SetDrawEdge(false) end
        if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end
        if cd.SetSwipeColor then cd:SetSwipeColor(0, 0, 0, 0.65) end
        refreshBtn:HookScript("OnClick", function() cd:SetCooldown(GetTime(), 1) end)
        refreshBtn:SetAlpha(0)
        refreshBtn:HookScript("OnEnter", function()
            lookName:LockHighlight()
            lookName.Glyph:SetAlpha(1)
        end)
        refreshBtn:HookScript("OnLeave", function()
            lookName:UnlockHighlight()
            lookName.Glyph:SetAlpha(0.8)
        end)
        Finder.viewerRefresh = lookName
    end
    local lookName = Finder.viewerRefresh
    lookName:Show()
    refreshBtn:SetAlpha(0)
    local padding = tonumber(FinderCfg().padding) or 12
    local ar, ir = AppViewer:GetRight(), AppViewer.Inset:GetRight()
    lookName:ClearAllPoints()
    -- 3 in from the rows' edge, over the decline buttons
    lookName:SetPoint(
        "BOTTOMRIGHT",
        AppViewer.Inset,
        "TOPRIGHT",
        (ar and ir) and (ar - ir - padding - 3) or 0,
        0
    )
    refreshBtn:ClearAllPoints()
    refreshBtn:SetAllPoints(lookName)
    refreshBtn:SetFrameLevel(lookName:GetFrameLevel() + 4)
end

-- own list off: back to blizzard's layout
local function RestoreViewer(AppViewer)
    if not Finder.viewerLaid then return end
    Finder.viewerLaid = nil
    AppViewer.BrowseGroupsButton:ClearAllPoints()
    AppViewer.BrowseGroupsButton:SetPoint("BOTTOMLEFT", AppViewer, "BOTTOMLEFT", -3, 4)
    AppViewer.BrowseGroupsButton:SetWidth(145)
    AppViewer.RemoveEntryButton:SetWidth(90)
    AppViewer.RemoveEntryButton:ClearAllPoints()
    if UnitIsGroupLeader("player", LE_PARTY_CATEGORY_HOME) then
        AppViewer.RemoveEntryButton:SetPoint("LEFT", AppViewer.BrowseGroupsButton, "RIGHT", 15, 0)
    else
        AppViewer.RemoveEntryButton:SetPoint("BOTTOMLEFT", AppViewer, "BOTTOMLEFT", -3, 4)
    end
    AppViewer.EditButton:ClearAllPoints()
    AppViewer.EditButton:SetPoint("BOTTOMRIGHT", AppViewer, "BOTTOMRIGHT", -3, 4)
    AppViewer.EditButton:SetWidth(90)
    Finder.viewerRefresh:Hide()
    local refreshBtn = AppViewer.RefreshButton
    refreshBtn:SetAlpha(1)
    refreshBtn:ClearAllPoints()
    refreshBtn:SetPoint("BOTTOMRIGHT", AppViewer.Inset, "TOPRIGHT", 21, 0)
    refreshBtn:SetFrameLevel(AppViewer:GetFrameLevel() + 1)
end

local function LayoutViewer()
    local AppViewer = LFGListFrame and LFGListFrame.ApplicationViewer
    if not (AppViewer and AppViewer:IsVisible()) then return end
    if InCombatLockdown() then
        Finder.Defer("viewerLayout", LayoutViewer)
        return
    end
    if not mod.ApplicantListOn() then
        RestoreViewer(AppViewer)
        return
    end
    Finder.viewerLaid = true
    LayoutViewerButtons(AppViewer)
    LayoutViewerRefresh(AppViewer)
end
mod.LayoutViewer = LayoutViewer

-------------------------------------------------------------------------------
-- boot
-------------------------------------------------------------------------------
local function Init()
    SP = LFGListFrame and LFGListFrame.SearchPanel
    if not SP then return end
    -- the picks come back when premade groups first opens, before "find group"
    -- runs its first search (and again on the search panel's show, XF.PanelShown)
    if LFGListFrame:IsVisible() then Finder.RestoreCharFilter() end
    LFGListFrame:HookScript("OnShow", Finder.RestoreCharFilter)
    SP:HookScript("OnShow", Finder.PanelShown)
    local CS = LFGListFrame.CategorySelection
    if CS then
        CS:HookScript("OnShow", LayoutCategoryButtons)
        if LFGListCategorySelection_AddButton then
            hooksecurefunc("LFGListCategorySelection_AddButton", LayoutCategoryList)
        end
        if CS:IsShown() then LayoutCategoryButtons() end
    end
    local EntryCreate = LFGListFrame.EntryCreation
    if EntryCreate then
        EntryCreate:HookScript("OnShow", LayoutEntryButtons)
        if LFGListEntryCreation_Select then
            hooksecurefunc("LFGListEntryCreation_Select", function()
                if EntryCreate:IsShown() then
                    LayoutEntryFields()
                    LayoutEntrySwitches()
                end
            end)
        end
        if EntryCreate:IsShown() then LayoutEntryButtons() end
    end
    local AppViewer = LFGListFrame.ApplicationViewer
    if
        AppViewer
        and AppViewer.Inset
        and AppViewer.RefreshButton
        and AppViewer.BrowseGroupsButton
        and AppViewer.RemoveEntryButton
        and AppViewer.EditButton
    then
        AppViewer:HookScript("OnShow", LayoutViewer)
        -- blizzard re-anchors delist on every update
        if LFGListApplicationViewer_UpdateInfo then
            hooksecurefunc("LFGListApplicationViewer_UpdateInfo", LayoutViewer)
        end
        LayoutViewer()
    end
    -- A new category: the row filters start over.
    hooksecurefunc("LFGListSearchPanel_SetCategory", function()
        Finder.NewPass()
        LayoutPanel()
    end)
    -- remember results for the new-group color
    hooksecurefunc("LFGListSearchPanel_UpdateResultList", function()
        local res = SP.results
        if SP.searching or type(res) ~= "table" or not SP:IsVisible() then return end
        for index = 1, #res do
            local ident = res[index]
            if not SecretVal(ident) then seenResults[ident] = true end
        end
    end)
    if LFGListUtil_SetSearchEntryTooltip then
        hooksecurefunc("LFGListUtil_SetSearchEntryTooltip", AddClassesByRole)
        hooksecurefunc("LFGListUtil_SetSearchEntryTooltip", Finder.CancelHint)
    end
    if LFGListSearchEntry_Update then hooksecurefunc("LFGListSearchEntry_Update", DecorateEntry) end
    -- every search clears the changed hint and starts the sweep
    hooksecurefunc("LFGListSearchPanel_DoSearch", function()
        -- previous search, same category only.
        prevResults = (prevCategory == SP.categoryID) and seenResults or nil
        prevCategory = SP.categoryID
        seenResults = {}
        if Finder.filterRestored then Finder.Remember(C_LFGList.GetAdvancedFilter()) end
        pending = false
        StartCooldown(CD_SEARCH)
        if SP:IsVisible() then Paint() end
    end)
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("CHALLENGE_MODE_MAPS_UPDATE")
    eventFrame:RegisterEvent("LFG_LIST_SEARCH_FAILED")
    Finder.AdoptRating()
    eventFrame:SetScript("OnEvent", function(_, evt)
        if evt == "LFG_LIST_SEARCH_FAILED" then
            -- server refused a search: wait longer.
            pending = true
            StartCooldown(CD_FAILED)
            return
        end
        -- new m+ maps: squares rebuild on the next layout
        Finder.dungeonsDirty = true
        LayoutPanel()
    end)
    LayoutPanel()
end

function mod.Search_OnEnable()
    if C_AddOns.IsAddOnLoaded("Blizzard_GroupFinder") and LFGListFrame then
        Init()
        return
    end
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("ADDON_LOADED")
    frame:SetScript("OnEvent", function(self, _, label)
        if label == "Blizzard_GroupFinder" then
            self:UnregisterEvent("ADDON_LOADED")
            Init()
        end
    end)
end
