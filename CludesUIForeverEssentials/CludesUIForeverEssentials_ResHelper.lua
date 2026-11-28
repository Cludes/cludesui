if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
if not (CUI and CUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_ResHelper.lua  (WoW Forever only)
--  Res Helper: after a wipe, a small list of your dead group members, each a
--  button that casts your resurrection on them (your highest rank). Shown
--  only out of combat, in a group, while someone is dead and you know a
--  resurrection: Resurrection (Priest), Redemption (Paladin), Ancestral
--  Spirit (Shaman) or Rebirth (Druid). A player already being resurrected is
--  marked, and casting one says "Resurrecting <name>" in group chat so two
--  healers do not pick the same body. Move it in Edit Layout.
--  The buttons are secure (they cast), so they are set up out of combat;
--  in combat the list stays as it was (a druid's Rebirth still works from it).
-------------------------------------------------------------------------------
local _, module = ...

local F = module.Feature("resHelper", { enabled = false, announce = true },
    { point = "CENTER", relPoint = "CENTER", x = 260, y = 60 })
local Get, Enabled, Cfg = F.Get, F.Enabled, F.Cfg
local Kit = CUI.Kit
local Pal = Kit.Palette

local RES_SPELLS = { 2006, 7328, 2008, 20484 } -- Resurrection, Redemption, Ancestral Spirit, Rebirth
local MAX_ROWS = 10
local ROW_W, ROW_H, GAP = 170, 22, 3

local panel, title, rows = nil, nil, {}
local pendingTarget -- the name a click is casting on
local dirty = false

local function Secret(v) return v ~= nil and issecretvalue and issecretvalue(v) end

-- Your resurrection: its spell id and name, or nil.
local function MyResurrection()
    for _, id in ipairs(RES_SPELLS) do
        local known = (IsPlayerSpell and IsPlayerSpell(id)) or (IsSpellKnown and IsSpellKnown(id))
        if known then return id, C_Spell.GetSpellName(id) end
    end
end

local function GroupUnits()
    local units = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            units[#units + 1] = "raid" .. i
        end
    else
        for i = 1, GetNumSubgroupMembers() do
            units[#units + 1] = "party" .. i
        end
    end
    return units
end

-- The dead group members: { unit, name, class, ghost, incoming }.
local function DeadMembers()
    local out = {}
    for _, unit in ipairs(GroupUnits()) do
        if UnitExists(unit) and not UnitIsUnit(unit, "player") then
            local dead = UnitIsDeadOrGhost(unit)
            if dead and not Secret(dead) and UnitIsConnected(unit) then
                local name = UnitName(unit)
                local _, class = UnitClass(unit)
                if name and not Secret(name) then
                    out[#out + 1] = {
                        unit = unit,
                        name = name,
                        class = class,
                        ghost = UnitIsGhost and UnitIsGhost(unit) or false,
                        incoming = UnitHasIncomingResurrection and UnitHasIncomingResurrection(unit) or false,
                    }
                end
            end
        end
    end
    return out
end
CUI._ResDeadMembers = DeadMembers

local function ClassHex(class)
    local cc = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    return cc and ("|cff%02x%02x%02x"):format(cc.r * 255, cc.g * 255, cc.b * 255) or "|cffffffff"
end

local function Row(i)
    local row = rows[i]
    if row then return row end
    row = Kit.SecureButton(panel, "CludesUIResHelperRow" .. i, "", ROW_W, ROW_H, { key = "essentials" })
    row:SetAttribute("type", "spell")
    row:SetPoint("TOPLEFT", 6, -(Kit.HEADER_H + 4 + (i - 1) * (ROW_H + GAP)))
    row.label:ClearAllPoints()
    row.label:SetPoint("LEFT", 8, 0)
    row.label:SetPoint("RIGHT", -8, 0)
    row.label:SetJustifyH("LEFT")
    row:HookScript("PreClick", function(self) pendingTarget = self.who end)
    rows[i] = row
    return row
end

local function Build()
    if panel then return panel end
    panel = CreateFrame("Frame", "CludesUIResHelper", UIParent)
    panel:SetSize(ROW_W + 12, Kit.HEADER_H + 8)
    panel:SetFrameStrata("MEDIUM")
    panel:SetClampedToScreen(true)
    Kit.Panel(panel)
    title = panel:CreateFontString(nil, "OVERLAY")
    Kit.Font(title, Kit.SMALL_SIZE, "essentials")
    title:SetPoint("TOPLEFT", 8, -8)
    title:SetTextColor(Kit.Accent())
    F.Place(panel)
    panel:Hide()
    return panel
end

-- Lays the list out again. Secure buttons change only out of combat.
local function Refresh()
    if InCombatLockdown() then
        dirty = true
        return
    end
    dirty = false
    local spellId, spellName = MyResurrection()
    local dead = (Enabled() and spellId and IsInGroup()) and DeadMembers() or {}
    if #dead == 0 then
        if panel then panel:Hide() end
        return
    end
    Build()
    title:SetText(("%s (%d)"):format(spellName or "Resurrect", #dead))
    local shown = math.min(#dead, MAX_ROWS)
    for i = 1, shown do
        local d = dead[i]
        local row = Row(i)
        row:SetAttribute("spell", spellName)
        row:SetAttribute("unit", d.unit)
        row.who = d.name
        local note = d.incoming and "  |cff60d080being resurrected|r" or d.ghost and "  |cffa3adb5released|r" or ""
        row:SetText(ClassHex(d.class) .. d.name .. "|r" .. note)
        row:SetAlpha(d.incoming and 0.55 or 1)
        row:Show()
    end
    for i = shown + 1, #rows do
        rows[i]:Hide()
    end
    panel:SetHeight(Kit.HEADER_H + 8 + shown * (ROW_H + GAP))
    panel:Show()
end

local function Channel()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
end

local events = CreateFrame("Frame")
local queued = false
events:SetScript("OnEvent", function(_, event, unit, _, spellId)
    if event == "UNIT_SPELLCAST_START" then
        if unit ~= "player" or Secret(spellId) or spellId ~= (MyResurrection()) then return end
        if pendingTarget and Get("announce") and not (C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown()) then
            local channel = Channel()
            if channel then C_ChatInfo.SendChatMessage("Resurrecting " .. pendingTarget, channel) end
        end
        pendingTarget = nil
        return
    end
    if event == "UNIT_HEALTH" or event == "UNIT_FLAGS" then
        -- Many of these arrive at once: one refresh shortly after.
        if queued then return end
        queued = true
        C_Timer.After(0.3, function()
            queued = false
            Refresh()
        end)
        return
    end
    Refresh()
end)

local function Apply()
    events:UnregisterAllEvents()
    if not Enabled() then
        if panel and not InCombatLockdown() then panel:Hide() end
        return
    end
    for _, ev in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD",
        "INCOMING_RESURRECT_CHANGED", "SPELLS_CHANGED" }) do
        events:RegisterEvent(ev)
    end
    events:RegisterEvent("UNIT_HEALTH")
    events:RegisterEvent("UNIT_FLAGS")
    events:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
    Refresh()
end

CUI._ResHelper = { Get = Get, Cfg = Cfg, Apply = Apply, Refresh = Refresh, DeadMembers = DeadMembers }

F.Start(Apply, {
    key = "CUIFE_ResHelper",
    label = "Res Helper",
    order = 63,
    shown = function() return Enabled() end,
    frame = function(build)
        if build then Build() end
        return panel
    end,
    size = function() return ROW_W + 12, panel and panel:GetHeight() or (Kit.HEADER_H + 8 + 3 * (ROW_H + GAP)) end,
})
