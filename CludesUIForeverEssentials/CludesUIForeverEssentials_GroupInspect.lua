if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if not (CludesUI and CludesUI.IS_FOREVER) then
    return
end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_GroupInspect.lua  (WoW Forever only)
--  Group Inspect: one window with everyone in your party or raid: class,
--  level, item level and the enchantable slots they have left bare. Open it
--  with /cinspect or from Forever Tools > General. Click a row to open the
--  game's own inspect window on that player (gear and talents in full).
--
--  The game inspects one player at a time, so the window asks for each in
--  turn, a second and a half apart, and only players in range answer. What
--  it learns is kept for the session, so reopening the window is instant.
-------------------------------------------------------------------------------
local _, module = ...

local PACE = 1.5
-- Classic-era enchantable slots and their names.
local ENCHANT_SLOTS = {
    [5] = "Chest",
    [7] = "Legs",
    [8] = "Feet",
    [9] = "Wrist",
    [10] = "Hands",
    [15] = "Back",
    [16] = "Main Hand",
}

local cache = {} -- guid -> { name, class, level, ilvl, bare = {...}, when }
local queue, asking = {}, nil
local window, rowList = nil, {}

local function Font()
    return CludesUI.GetFontPath("essentials")
end
local function Secret(val)
    return issecretvalue and issecretvalue(val)
end

local function Members()
    local result = {}
    if IsInRaid() then
        for index = 1, GetNumGroupMembers() do
            result[#result + 1] = "raid" .. index
        end
    else
        result[1] = "player"
        for index = 1, GetNumSubgroupMembers() do
            result[#result + 1] = "party" .. index
        end
    end
    return result
end

local function BareSlots(unitToken)
    local bare = {}
    for slot, name in pairs(ENCHANT_SLOTS) do
        local itemLink = GetInventoryItemLink(unitToken, slot)
        if itemLink and not Secret(itemLink) then
            local enchant = itemLink:match("item:%d+:(%d*)")
            if enchant == nil or enchant == "" or enchant == "0" then
                bare[#bare + 1] = name
            end
        end
    end
    table.sort(bare)
    return bare
end

local function Read(unitToken)
    local unitGuid = UnitGUID(unitToken)
    if not unitGuid or Secret(unitGuid) then
        return
    end
    local _, class = UnitClass(unitToken)
    local ilvl
    if UnitIsUnit(unitToken, "player") then
        local _, equipped = GetAverageItemLevel()
        ilvl = equipped
    elseif C_PaperDollInfo and C_PaperDollInfo.GetInspectItemLevel then
        ilvl = C_PaperDollInfo.GetInspectItemLevel(unitToken)
    end
    if Secret(ilvl) then
        ilvl = nil
    end
    cache[unitGuid] = {
        name = UnitName(unitToken),
        class = class,
        level = UnitLevel(unitToken),
        ilvl = ilvl,
        bare = BareSlots(unitToken),
        when = GetTime(),
    }
end

local Refresh

local function AskNext()
    asking = nil
    while #queue > 0 do
        local unitToken = table.remove(queue, 1)
        if UnitExists(unitToken) and UnitIsConnected(unitToken) then
            if UnitIsUnit(unitToken, "player") then
                Read(unitToken)
            elseif CanInspect(unitToken, false) and not InCombatLockdown() then
                asking = { unit = unitToken, guid = UnitGUID(unitToken) }
                NotifyInspect(unitToken)
                C_Timer.After(PACE, function()
                    if asking and asking.unit == unitToken then
                        AskNext()
                    end -- no answer: move on
                end)
                return
            end
        end
    end
    if Refresh then
        Refresh()
    end
end

local function ScanGroup()
    wipe(queue)
    for _, unitToken in ipairs(Members()) do
        queue[#queue + 1] = unitToken
    end
    if not asking then
        AskNext()
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("INSPECT_READY")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:SetScript("OnEvent", function(_, evt, unitGuid)
    if evt == "GROUP_ROSTER_UPDATE" then
        if window and window:IsShown() then
            ScanGroup()
        end
        return
    end
    if not (asking and asking.guid == unitGuid) then
        return
    end
    local unitToken = asking.unit
    Read(unitToken)
    -- Leave the game's own inspect window alone if the player opened it.
    if not (InspectFrame and InspectFrame:IsShown()) then
        ClearInspectPlayer()
    end
    if Refresh then
        Refresh()
    end
    C_Timer.After(PACE, function()
        if asking and asking.guid == unitGuid then
            AskNext()
        end
    end)
end)

-------------------------------------------------------------------------------
--  Window
-------------------------------------------------------------------------------
local ROW_H = 18

local function Build()
    if window then
        return
    end
    window = CreateFrame("Frame", "CludesUIGroupInspect", UIParent)
    window:SetSize(460, 60)
    window:SetPoint("CENTER", 0, 120)
    CludesUI.Kit.Panel(window, 0.94)
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    window:SetFrameStrata("HIGH")
    local title = window:CreateFontString(nil, "OVERLAY")
    CludesUI.Kit.Font(title, 15, "essentials")
    title:SetPoint("TOPLEFT", 10, -8)
    title:SetText("Group Inspect")
    CludesUI.Kit.AccentText(title)
    local close = CludesUI.Kit.Glyph(window, "x", function()
        window:Hide()
    end, nil, "essentials")
    close:SetPoint("TOPRIGHT", -5, -5)
    window:Hide()
    tinsert(UISpecialFrames, "CludesUIGroupInspect")
end

local function Row(index)
    local region = rowList[index]
    if not region then
        region = CreateFrame("Button", nil, window)
        region:SetSize(440, ROW_H)
        region.text = region:CreateFontString(nil, "OVERLAY")
        CludesUI.Kit.Font(region.text, 12, "essentials")
        region.text:SetPoint("LEFT")
        region.text:SetJustifyH("LEFT")
        region.text:SetWidth(440)
        region.text:SetWordWrap(false)
        local highlight = region:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 1, 1, 0.06)
        region:SetScript("OnClick", function(self)
            if self.unit and UnitExists(self.unit) and CanInspect(self.unit, true) then
                InspectUnit(self.unit)
            end
        end)
        rowList[index] = region
    end
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", window, "TOPLEFT", 10, -30 - (index - 1) * ROW_H)
    region:Show()
    return region
end

Refresh = function()
    if not (window and window:IsShown()) then
        return
    end
    local entries = {}
    for _, unitToken in ipairs(Members()) do
        local unitGuid = UnitGUID(unitToken)
        local c = unitGuid and not Secret(unitGuid) and cache[unitGuid]
        local _, class = UnitClass(unitToken)
        local colour = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        local name = UnitName(unitToken) or "?"
        if colour then
            name = colour:WrapTextInColorCode(name)
        end
        local textValue
        if c then
            textValue = ("%s  |cff9aa6b2%d|r  %s"):format(
                name,
                c.level or 0,
                c.ilvl and ("ilvl %.1f"):format(c.ilvl) or "|cff9aa6b2ilvl ?|r"
            )
            if #c.bare > 0 then
                textValue = textValue .. "  |cffffb040no enchant: " .. table.concat(c.bare, ", ") .. "|r"
            end
        else
            textValue = name .. "  |cff9aa6b2out of range or not yet asked|r"
        end
        entries[#entries + 1] = { unit = unitToken, text = textValue, ilvl = c and c.ilvl or -1 }
    end
    table.sort(entries, function(lhs, rhs)
        return lhs.ilvl > rhs.ilvl
    end)
    for index, l in ipairs(entries) do
        local region = Row(index)
        region.unit = l.unit
        region.text:SetText(l.text)
    end
    for index = #entries + 1, #rowList do
        rowList[index]:Hide()
    end
    window:SetHeight(40 + #entries * ROW_H)
end

function module.ShowGroupInspect()
    Build()
    window:Show()
    Refresh()
    ScanGroup()
end

CludesUI._GroupInspect = { Show = module.ShowGroupInspect }

SLASH_CUIGROUPINSPECT1 = "/cinspect"
SlashCmdList.CUIGROUPINSPECT = function()
    if window and window:IsShown() then
        window:Hide()
    else
        module.ShowGroupInspect()
    end
end
