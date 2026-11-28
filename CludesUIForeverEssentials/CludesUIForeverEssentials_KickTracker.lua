if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
if not (CUI and CUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_KickTracker.lua  (WoW Forever only)
--  Interrupt Tracker: your group's interrupts in a small list: who has one
--  (Kick, Pummel or Shield Bash, Earth Shock, Counterspell), whether it is
--  ready or how long until it is. The first ready one is marked "next".
--  Read from the group's own casts (UNIT_SPELLCAST_SUCCEEDED; the game keeps
--  the combat log from addons on this client), so it works for everyone, with
--  or without CludesUI. Shown in dungeons and raids (or everywhere); move it
--  in Edit Layout.
--  Ranks and learn levels are Forever's trainers'; cooldowns the game's own
--  base cooldown for the spell (the numbers below only if the game has none).
-------------------------------------------------------------------------------
local _, module = ...

local F = module.Feature("kickTracker", { enabled = false, instancesOnly = true },
    { point = "CENTER", relPoint = "CENTER", x = -280, y = 40 })
local Get, Enabled, Cfg = F.Get, F.Enabled, F.Cfg
local Kit = CUI.Kit
local Pal = Kit.Palette

-- Every rank's spell id -> the interrupt it is, and each class's interrupts by level.
local INTERRUPTS = {
    KICK = { name = "Kick", ids = { 1766, 1767, 1768, 1769 }, cooldown = 10 },
    PUMMEL = { name = "Pummel", ids = { 6552, 6554 }, cooldown = 10 },
    SHIELD_BASH = { name = "Shield Bash", ids = { 72, 1671, 1672 }, cooldown = 12 },
    EARTH_SHOCK = { name = "Earth Shock", ids = { 8042, 8044, 8045, 8046, 10412, 10413, 10414 }, cooldown = 6 },
    COUNTERSPELL = { name = "Counterspell", ids = { 2139 }, cooldown = 24 },
}
local BY_CLASS = {
    ROGUE = { { level = 12, kick = "KICK" } },
    WARRIOR = { { level = 38, kick = "PUMMEL" }, { level = 12, kick = "SHIELD_BASH" } },
    SHAMAN = { { level = 4, kick = "EARTH_SHOCK" } },
    MAGE = { { level = 24, kick = "COUNTERSPELL" } },
}
local KICK_OF_SPELL = {}
for key, info in pairs(INTERRUPTS) do
    for _, id in ipairs(info.ids) do
        KICK_OF_SPELL[id] = key
    end
end

local ROW_W, ROW_H = 200, 18
local MAX_ROWS = 10

local readyAt = {} -- guid -> time the interrupt is ready again
local cooldownOf = {} -- interrupt key -> seconds
local panel, rows, ticker = nil, {}, nil

local function Secret(v) return v ~= nil and issecretvalue and issecretvalue(v) end

local function Cooldown(key)
    if cooldownOf[key] then return cooldownOf[key] end
    local info = INTERRUPTS[key]
    local ms = GetSpellBaseCooldown and GetSpellBaseCooldown(info.ids[1])
    cooldownOf[key] = (type(ms) == "number" and ms > 0) and ms / 1000 or info.cooldown
    return cooldownOf[key]
end

local function KickFor(class, level)
    for _, option in ipairs(BY_CLASS[class] or {}) do
        if (level or 0) >= option.level then return option.kick end
    end
end

-- The group's interrupters: { guid, name, class, kick }.
local function Interrupters()
    local units = { "player" }
    if IsInRaid() then
        units = {}
        for i = 1, GetNumGroupMembers() do
            units[#units + 1] = "raid" .. i
        end
    else
        for i = 1, GetNumSubgroupMembers() do
            units[#units + 1] = "party" .. i
        end
    end
    local out = {}
    for _, unit in ipairs(units) do
        if UnitExists(unit) then
            local guid, name = UnitGUID(unit), UnitName(unit)
            local _, class = UnitClass(unit)
            local level = UnitLevel(unit)
            if not (Secret(guid) or Secret(name) or Secret(level)) then
                local kick = KickFor(class, level)
                if kick and guid and name then out[#out + 1] = { guid = guid, name = name, class = class, kick = kick } end
            end
        end
    end
    return out
end
CUI._KickInterrupters = Interrupters

local function Wanted()
    if not Enabled() then return false end
    if not Get("instancesOnly") then return true end
    local inside, kind = IsInInstance()
    return inside and (kind == "party" or kind == "raid")
end

local function Build()
    if panel then return panel end
    panel = CreateFrame("Frame", "CludesUIKickTracker", UIParent)
    panel:SetSize(ROW_W + 12, Kit.HEADER_H + 8)
    panel:SetFrameStrata("MEDIUM")
    panel:SetClampedToScreen(true)
    Kit.Panel(panel)
    local title = panel:CreateFontString(nil, "OVERLAY")
    Kit.Font(title, Kit.SMALL_SIZE, "essentials")
    title:SetPoint("TOPLEFT", 8, -8)
    title:SetText(CUI.L("Interrupts"))
    title:SetTextColor(Kit.Accent())
    F.Place(panel)
    panel:Hide()
    return panel
end

local function Row(i)
    local row = rows[i]
    if row then return row end
    row = CreateFrame("Frame", nil, panel)
    row:SetSize(ROW_W, ROW_H)
    row:SetPoint("TOPLEFT", 6, -(Kit.HEADER_H + 2 + (i - 1) * ROW_H))
    row.name = row:CreateFontString(nil, "OVERLAY")
    Kit.Font(row.name, Kit.SMALL_SIZE, "essentials")
    row.name:SetPoint("LEFT", 2, 0)
    row.name:SetWidth(ROW_W - 70)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.state = row:CreateFontString(nil, "OVERLAY")
    Kit.Font(row.state, Kit.SMALL_SIZE, "essentials")
    row.state:SetPoint("RIGHT", -2, 0)
    row.state:SetJustifyH("RIGHT")
    rows[i] = row
    return row
end

local function ClassHex(class)
    local cc = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    return cc and ("|cff%02x%02x%02x"):format(cc.r * 255, cc.g * 255, cc.b * 255) or "|cffffffff"
end

local function Draw()
    if not Wanted() then
        if panel then panel:Hide() end
        if ticker then
            ticker:Cancel()
            ticker = nil
        end
        return
    end
    local list = Interrupters()
    if #list == 0 then
        if panel then panel:Hide() end
        return
    end
    Build()
    local now = GetTime()
    for _, entry in ipairs(list) do
        entry.left = math.max(0, (readyAt[entry.guid] or 0) - now)
    end
    -- Ready ones first, then the soonest.
    table.sort(list, function(a, b)
        if (a.left == 0) ~= (b.left == 0) then return a.left == 0 end
        if a.left ~= b.left then return a.left < b.left end
        return a.name < b.name
    end)
    local shown = math.min(#list, MAX_ROWS)
    for i = 1, shown do
        local entry = list[i]
        local row = Row(i)
        row.name:SetText(("%s%s|r  |cffa3adb5%s|r"):format(ClassHex(entry.class), entry.name, INTERRUPTS[entry.kick].name))
        if entry.left == 0 then
            row.state:SetText(i == 1 and "|cff60d080next|r" or "|cff60d080ready|r")
        else
            row.state:SetText(("|cffffb040%ds|r"):format(math.ceil(entry.left)))
        end
        row:Show()
    end
    for i = shown + 1, #rows do
        rows[i]:Hide()
    end
    panel:SetHeight(Kit.HEADER_H + 8 + shown * ROW_H)
    panel:Show()
    if not ticker then ticker = C_Timer.NewTicker(0.25, Draw) end
end

local events = CreateFrame("Frame")
-- The units whose casts count: you and your party or raid.
local MEMBER = { player = true }
for i = 1, 4 do
    MEMBER["party" .. i] = true
end
for i = 1, 40 do
    MEMBER["raid" .. i] = true
end

events:SetScript("OnEvent", function(_, event, unit, _, spellId)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        if Secret(unit) or Secret(spellId) or not MEMBER[unit] then return end
        local kick = KICK_OF_SPELL[spellId]
        local guid = kick and UnitGUID(unit)
        if guid and not Secret(guid) then readyAt[guid] = GetTime() + Cooldown(kick) end
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then wipe(readyAt) end
    Draw()
end)

local function Apply()
    events:UnregisterAllEvents()
    if not Enabled() then
        Draw()
        return
    end
    for _, ev in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "GROUP_ROSTER_UPDATE", "UNIT_SPELLCAST_SUCCEEDED" }) do
        events:RegisterEvent(ev)
    end
    Draw()
end

CUI._KickTracker = {
    Get = Get,
    Cfg = Cfg,
    Apply = Apply,
    Draw = Draw,
    State = function() return readyAt end,
}

F.Start(Apply, {
    key = "CUIFE_KickTracker",
    label = "Interrupt Tracker",
    order = 64,
    frame = function(build)
        if build then Build() end
        return panel
    end,
    size = function() return ROW_W + 12, panel and panel:GetHeight() or (Kit.HEADER_H + 8 + 4 * ROW_H) end,
})
