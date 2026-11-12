if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if not (CludesUI and CludesUI.IS_FOREVER) then return end
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
local ENCHANT_SLOTS = { [5] = "Chest", [7] = "Legs", [8] = "Feet", [9] = "Wrist", [10] = "Hands",
                        [15] = "Back", [16] = "Main Hand" }

local cache = {}          -- guid -> { name, class, level, ilvl, bare = {...}, when }
local queue, asking = {}, nil
local win, rows = nil, {}

local function Font() return (CludesUI.GetFontPath and CludesUI.GetFontPath()) or STANDARD_TEXT_FONT end
local function Secret(v) return issecretvalue and issecretvalue(v) end

local function Members()
    local out = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do out[#out + 1] = "raid" .. i end
    else
        out[1] = "player"
        for i = 1, GetNumSubgroupMembers() do out[#out + 1] = "party" .. i end
    end
    return out
end

local function BareSlots(unit)
    local bare = {}
    for slot, name in pairs(ENCHANT_SLOTS) do
        local link = GetInventoryItemLink(unit, slot)
        if link and not Secret(link) then
            local enchant = link:match("item:%d+:(%d*)")
            if enchant == nil or enchant == "" or enchant == "0" then bare[#bare + 1] = name end
        end
    end
    table.sort(bare)
    return bare
end

local function Read(unit)
    local guid = UnitGUID(unit)
    if not guid or Secret(guid) then return end
    local _, class = UnitClass(unit)
    local ilvl
    if UnitIsUnit(unit, "player") then
        local _, equipped = GetAverageItemLevel()
        ilvl = equipped
    elseif C_PaperDollInfo and C_PaperDollInfo.GetInspectItemLevel then
        ilvl = C_PaperDollInfo.GetInspectItemLevel(unit)
    end
    if Secret(ilvl) then ilvl = nil end
    cache[guid] = { name = UnitName(unit), class = class, level = UnitLevel(unit),
                    ilvl = ilvl, bare = BareSlots(unit), when = GetTime() }
end

local Refresh

local function AskNext()
    asking = nil
    while #queue > 0 do
        local unit = table.remove(queue, 1)
        if UnitExists(unit) and UnitIsConnected(unit) then
            if UnitIsUnit(unit, "player") then
                Read(unit)
            elseif CanInspect(unit, false) and not InCombatLockdown() then
                asking = { unit = unit, guid = UnitGUID(unit) }
                NotifyInspect(unit)
                C_Timer.After(PACE, function()
                    if asking and asking.unit == unit then AskNext() end   -- no answer: move on
                end)
                return
            end
        end
    end
    if Refresh then Refresh() end
end

local function ScanGroup()
    wipe(queue)
    for _, unit in ipairs(Members()) do queue[#queue + 1] = unit end
    if not asking then AskNext() end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("INSPECT_READY")
ev:RegisterEvent("GROUP_ROSTER_UPDATE")
ev:SetScript("OnEvent", function(_, event, guid)
    if event == "GROUP_ROSTER_UPDATE" then
        if win and win:IsShown() then ScanGroup() end
        return
    end
    if not (asking and asking.guid == guid) then return end
    local unit = asking.unit
    Read(unit)
    -- Leave the game's own inspect window alone if the player opened it.
    if not (InspectFrame and InspectFrame:IsShown()) then ClearInspectPlayer() end
    if Refresh then Refresh() end
    C_Timer.After(PACE, function() if asking and asking.guid == guid then AskNext() end end)
end)

-------------------------------------------------------------------------------
--  Window
-------------------------------------------------------------------------------
local ROW_H = 18

local function Build()
    if win then return end
    win = CreateFrame("Frame", "CludesUIGroupInspect", UIParent, "BackdropTemplate")
    win:SetSize(460, 60)
    win:SetPoint("CENTER", 0, 120)
    win:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    win:SetBackdropColor(0.06, 0.07, 0.09, 0.94)
    win:SetBackdropBorderColor(0.30, 0.79, 0.94, 0.8)
    win:SetMovable(true); win:EnableMouse(true); win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    win:SetFrameStrata("HIGH")
    local title = win:CreateFontString(nil, "OVERLAY")
    title:SetFont(Font(), 15, "OUTLINE")
    title:SetPoint("TOPLEFT", 10, -8)
    title:SetText("|cff4cc9f0Group Inspect|r")
    local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    win:Hide()
    tinsert(UISpecialFrames, "CludesUIGroupInspect")
end

local function Row(i)
    local r = rows[i]
    if not r then
        r = CreateFrame("Button", nil, win)
        r:SetSize(440, ROW_H)
        r.text = r:CreateFontString(nil, "OVERLAY")
        r.text:SetFont(Font(), 12, "")
        r.text:SetPoint("LEFT")
        r.text:SetJustifyH("LEFT")
        r.text:SetWidth(440)
        r.text:SetWordWrap(false)
        local hl = r:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.06)
        r:SetScript("OnClick", function(self)
            if self.unit and UnitExists(self.unit) and CanInspect(self.unit, true) then InspectUnit(self.unit) end
        end)
        rows[i] = r
    end
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", win, "TOPLEFT", 10, -30 - (i - 1) * ROW_H)
    r:Show()
    return r
end

Refresh = function()
    if not (win and win:IsShown()) then return end
    local list = {}
    for _, unit in ipairs(Members()) do
        local guid = UnitGUID(unit)
        local c = guid and not Secret(guid) and cache[guid]
        local _, class = UnitClass(unit)
        local colour = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        local name = UnitName(unit) or "?"
        if colour then name = colour:WrapTextInColorCode(name) end
        local text
        if c then
            text = ("%s  |cff9aa6b2%d|r  %s"):format(name, c.level or 0,
                c.ilvl and ("ilvl %.1f"):format(c.ilvl) or "|cff9aa6b2ilvl ?|r")
            if #c.bare > 0 then text = text .. "  |cffffb040no enchant: " .. table.concat(c.bare, ", ") .. "|r" end
        else
            text = name .. "  |cff9aa6b2out of range or not yet asked|r"
        end
        list[#list + 1] = { unit = unit, text = text, ilvl = c and c.ilvl or -1 }
    end
    table.sort(list, function(a, b) return a.ilvl > b.ilvl end)
    for i, l in ipairs(list) do
        local r = Row(i)
        r.unit = l.unit
        r.text:SetText(l.text)
    end
    for i = #list + 1, #rows do rows[i]:Hide() end
    win:SetHeight(40 + #list * ROW_H)
end

function module.ShowGroupInspect()
    Build()
    win:Show()
    Refresh()
    ScanGroup()
end

CludesUI._GroupInspect = { Show = module.ShowGroupInspect }

SLASH_CUIGROUPINSPECT1 = "/cinspect"
SlashCmdList.CUIGROUPINSPECT = function()
    if win and win:IsShown() then win:Hide() else module.ShowGroupInspect() end
end
