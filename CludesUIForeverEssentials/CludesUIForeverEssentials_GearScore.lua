if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
if not (CUI and CUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_GearScore.lua  (WoW Forever only)
--  Gear Score: one number for a character's gear on the item level scale
--  (26.4 = worth a full set of level 26 epics). Each item counts as the item
--  level of an epic with its stats (level x SCALE + SHIFT for its quality),
--  each slot weighted by the stats it carries; an empty slot counts 0 and a
--  two-hander takes both hands' weight. The constants are fitted to WoW
--  Forever's own item table (build 1.60.1).
--  Its colour: its share of a level's goal, epics five levels over it
--  (grey, white, green, blue, purple, then orange at the goal).
--  Shown on player tooltips (yours from your gear; others' from any inspect,
--  and the player you hover is inspected in the background, one at a time,
--  out of combat and in range), under your level on the character sheet,
--  under item level on the inspect sheet, and in Group Inspect.
-------------------------------------------------------------------------------
local _, module = ...

local F = module.Feature("gearScore", { enabled = true, tooltip = true, hoverInspect = true })
local Get, On = F.Get, F.Enabled

local SLOTS = {
    [1] = 1.01, [2] = 0.54, [3] = 0.76, [5] = 1, [6] = 0.75, [7] = 1.01, [8] = 0.75, [9] = 0.55,
    [10] = 0.75, [11] = 0.54, [12] = 0.54, [13] = 0.7, [14] = 0.7, [15] = 0.55, [16] = 0.41,
    [17] = 0.54, [18] = 0.31,
}
local SCALE = { [0] = 0.39, [1] = 0.59, [2] = 0.65, [3] = 0.8 }
local SHIFT = { [0] = -3, [1] = -4.5, [2] = -4.9, [3] = -2.1 }
local ORDER = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 } -- main hand before off hand
local MAIN, OFF = 16, 17
local TOTAL = 0
for _, slot in ipairs(ORDER) do
    TOTAL = TOTAL + SLOTS[slot]
end
-- The colour ramp: { share, r, g, b }, grey -> white -> green -> blue -> purple -> orange.
local RAMP = {
    { 0.00, 0.62, 0.62, 0.62 }, { 0.15, 1.00, 1.00, 1.00 }, { 0.25, 0.78, 1.00, 0.70 },
    { 0.35, 0.50, 1.00, 0.40 }, { 0.45, 0.12, 1.00, 0.00 }, { 0.55, 0.20, 0.75, 1.00 },
    { 0.65, 0.00, 0.44, 0.87 }, { 0.72, 0.40, 0.36, 1.00 }, { 0.80, 0.64, 0.21, 0.93 },
    { 0.88, 0.82, 0.32, 0.88 }, { 0.94, 1.00, 0.66, 0.25 }, { 1.00, 1.00, 0.50, 0.00 },
}
local KEEP = 600 -- seconds an inspected score is kept
local INSPECT_SPACING = 2

local Score = {}

-- An item as epic item levels (never below 0).
function Score.Epic(lvl, quality)
    return math.max(0, lvl * (SCALE[quality] or 1) + (SHIFT[quality] or 0))
end

-- read(slot) -> item level, quality, two-hander. Returns the score, and
-- whether every item's data was there.
function Score.Of(load)
    local sum, complete, twoHand = 0, true, false
    for _, slot in ipairs(ORDER) do
        if not (slot == OFF and twoHand) then
            local weight = SLOTS[slot]
            local lvl, quality, two = load(slot)
            if slot == MAIN and two then
                twoHand = true
                weight = weight + SLOTS[OFF]
            end
            if lvl then
                if not quality then complete = false end
                sum = sum + weight * Score.Epic(lvl, quality)
            end
        end
    end
    return sum / TOTAL, complete
end

local function LoadLink(link)
    if not link then return end
    local lvl = C_Item.GetDetailedItemLevelInfo(link)
    local _, _, quality = C_Item.GetItemInfo(link)
    local _, _, _, equip = C_Item.GetItemInfoInstant(link)
    return lvl or 0, lvl and quality, equip == "INVTYPE_2HWEAPON"
end

function Score.Links(links) return Score.Of(function(slot) return LoadLink(links[slot]) end) end

function Score.Unit(unit)
    local links = {}
    for slot in pairs(SLOTS) do
        links[slot] = GetInventoryItemLink(unit, slot)
    end
    return Score.Links(links)
end

-- A level's goal: epics five levels over it (level 65 at the cap, about the
-- first raid tier), so level-fit blues read blue and only top gear orange.
function Score.Goal(lvl)
    return Score.Epic(math.min(lvl or 60, 60) + 5, 4)
end

function Score.Colour(share)
    share = math.max(0, math.min(1, share))
    for index = 2, #RAMP do
        local upper = RAMP[index]
        if share <= upper[1] then
            local lower = RAMP[index - 1]
            local t = upper[1] > lower[1] and (share - lower[1]) / (upper[1] - lower[1]) or 1
            return lower[2] + (upper[2] - lower[2]) * t, lower[3] + (upper[3] - lower[3]) * t, lower[4] + (upper[4] - lower[4]) * t
        end
    end
    return 1, 0.5, 0
end

-- "26.4" in its colour, and "92%" of the level's goal.
function Score.Text(score, lvl)
    local share = score / Score.Goal(lvl)
    local hex = CUI.HexColor(Score.Colour(share))
    return ("%s%.1f|r"):format(hex, score), ("%s%d%%|r"):format(hex, math.floor(math.min(share, 1) * 100 + 0.5))
end

-------------------------------------------------------------------------------
--  Others' scores: from every inspect answer, kept by GUID
-------------------------------------------------------------------------------
local learned = {} -- guid -> { score, level, complete, when }

-- A unit's GUID, or nil while the game hands it back as a secret value (those
-- can be neither compared nor used as a table key).
local function Guid(unit)
    local guid = unit and UnitGUID(unit)
    if guid and issecretvalue and issecretvalue(guid) then return nil end
    return guid
end
local inspecting -- { guid, unit, at } our own background inspect

function Score.Known(guid)
    local entry = guid and learned[guid]
    if entry and GetTime() - entry.when < KEEP then return entry end
end

local function Remember(unit)
    local guid = Guid(unit)
    if not guid then return end
    local score, complete = Score.Unit(unit)
    learned[guid] = { score = score, level = UnitLevel(unit), complete = complete, when = GetTime() }
    return learned[guid]
end

-- The player you hover: inspected when nothing else is (the game keeps one
-- inspect at a time), in range, out of combat, never over your own Inspect.
local lastAsk = 0
local function Hovered(unit)
    if not (On() and Get("hoverInspect")) or InCombatLockdown() then return end
    if not (UnitIsPlayer(unit) and not UnitIsUnit(unit, "player") and CanInspect(unit, false)) then return end
    if not CheckInteractDistance(unit, 1) then return end
    local inspect = rawget(_G, "InspectFrame")
    if inspect and inspect:IsShown() then return end
    if inspecting or GetTime() - lastAsk < INSPECT_SPACING then return end
    local guid = Guid(unit)
    if not guid or Score.Known(guid) then return end
    lastAsk = GetTime()
    inspecting = { guid = guid, unit = unit }
    NotifyInspect(unit)
    C_Timer.After(INSPECT_SPACING * 2, function()
        if inspecting and inspecting.guid == guid then inspecting = nil end
    end)
end

-------------------------------------------------------------------------------
--  Tooltips
-------------------------------------------------------------------------------
local function TooltipLine(tooltip, unit)
    local label, share
    if UnitIsUnit(unit, "player") then
        label, share = Score.Text(Score.Unit("player"), UnitLevel("player"))
    else
        local entry = Score.Known(Guid(unit))
        if entry then
            label, share = Score.Text(entry.score, entry.level)
        else
            Hovered(unit)
            return
        end
    end
    local r, g, b = CUI.Kit.Accent()
    tooltip:AddDoubleLine("Gear Score", label .. "  " .. share, r, g, b, 1, 1, 1)
end

local hooked = false
local function HookTooltip()
    if hooked or not (TooltipDataProcessor and Enum.TooltipDataType) then return end
    hooked = true
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
        if not (On() and Get("tooltip")) or tooltip ~= GameTooltip then return end
        local _, unit = tooltip:GetUnit()
        if unit and not (issecretvalue and issecretvalue(unit)) and UnitIsPlayer(unit) then TooltipLine(tooltip, unit) end
    end)
end

-------------------------------------------------------------------------------
--  The character sheet: under your level line
-------------------------------------------------------------------------------
local sheetLine
local function RenderSheet()
    local lvl = rawget(_G, "CharacterLevelText")
    if not lvl then return end
    if not sheetLine then
        -- On a layer of its own over the slot buttons (the sheet's slots
        -- otherwise draw over its left end).
        local host = lvl:GetParent()
        local layer = CreateFrame("Frame", nil, host)
        layer:SetAllPoints(host)
        layer:SetFrameLevel(host:GetFrameLevel() + 30)
        sheetLine = layer:CreateFontString(nil, "OVERLAY")
        CUI.Kit.Font(sheetLine, CUI.Kit.TEXT_SIZE, "essentials")
        sheetLine:SetPoint("TOP", lvl, "BOTTOM", 0, -3)
    end
    sheetLine:SetShown(On())
    if not On() then return end
    local label, share = Score.Text(Score.Unit("player"), UnitLevel("player"))
    sheetLine:SetText("Gear Score " .. label .. "  " .. share)
end

-- The inspect sheet's line under item level (empty on Forever) asks here.
function CUI.GearScoreLine(unit)
    if not (On() and unit and UnitExists(unit)) then return end
    local theirs = Remember(unit)
    if not theirs then return end
    local label = Score.Text(theirs.score, theirs.level)
    local mine = Score.Text(Score.Unit("player"), UnitLevel("player"))
    return ("Gear Score %s%s  |cffa3adb5(you %s)|r"):format(label, theirs.complete and "" or " ...", mine)
end

-------------------------------------------------------------------------------
--  Events
-------------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, arg)
    if event == "INSPECT_READY" then
        local unit = inspecting and inspecting.guid == arg and inspecting.unit
        if not unit then
            for _, token in ipairs({ "target", "mouseover", "focus" }) do
                if Guid(token) == arg then unit = token end
            end
        end
        if unit and Guid(unit) == arg then Remember(unit) end
        if inspecting and inspecting.guid == arg then
            inspecting = nil
            -- Our background ask: the game's inspect data is released for the next.
            if ClearInspectPlayer and not (rawget(_G, "InspectFrame") and InspectFrame:IsShown()) then ClearInspectPlayer() end
            if GameTooltip:IsShown() then
                local _, hovered = GameTooltip:GetUnit()
                if hovered and Guid(hovered) == arg then GameTooltip:SetUnit(hovered) end
            end
        end
    elseif event == "UNIT_INVENTORY_CHANGED" then
        local guid = Guid(arg)
        if guid then learned[guid] = nil end
        if arg == "player" and sheetLine then RenderSheet() end
    elseif event == "PLAYER_EQUIPMENT_CHANGED" or event == "PLAYER_LEVEL_UP" then
        RenderSheet()
    end
end)

local sheetHooked = false
local function Apply()
    events:UnregisterAllEvents()
    if sheetLine then sheetLine:SetShown(On()) end
    if not On() then return end
    for _, event in ipairs({ "INSPECT_READY", "UNIT_INVENTORY_CHANGED", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP" }) do
        events:RegisterEvent(event)
    end
    HookTooltip()
    local sheet = rawget(_G, "CharacterFrame")
    if sheet and not sheetHooked then
        sheetHooked = true
        sheet:HookScript("OnShow", RenderSheet)
    end
end

module.GearScore = Score
CUI._GearScore = {
    Get = Get,
    Cfg = F.Cfg,
    Apply = Apply,
    Score = Score,
    SheetText = function() return sheetLine and sheetLine:IsShown() and sheetLine:GetText() end,
}

F.Start(Apply)
