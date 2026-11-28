if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
if not (CUI and CUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_CCMarks.lua  (WoW Forever only)
--  CC Marker Bar: the eight raid marks and a Clear on a small bar (each a
--  secure /tm button, so marking works in combat too), plus:
--    CC        target a mob and press it: picks the crowd control that
--              works on that mob's type (and that it is not immune to, from
--              Creature Scout's data), from someone in your group who can
--              cast it and is not already given one, marks the mob with that
--              control's mark and, with Announce on, says it in group chat.
--    Say       posts every assignment and the kill marks: "{rt8} kill first,
--              {rt5} Polymorph: Frostbolt".
--    Reset     forgets the assignments (they also clear when a fight ends).
--  The controls, by Forever's trainers (classic rules):
--    Polymorph (Mage, 8)        Humanoid, Beast, Critter      Moon
--    Sap (Rogue, 10)            Humanoid, before the pull     Star
--    Shackle Undead (Priest, 20) Undead                       Triangle
--    Hibernate (Druid, 18)      Beast, Dragonkin              Circle
--    Banish (Warlock, 28)       Demon, Elemental              Diamond
--    Freezing Trap (Hunter, 20) anything                      Square
--  Picking a control changes the CC button's mark attribute, which the game
--  only allows out of combat: in combat CC says why and does nothing.
--  /ccmark toggles the bar; a key binding presses CC.
-------------------------------------------------------------------------------
local _, module = ...

local F = module.Feature("ccMarks", {
    enabled = false,
    instancesOnly = true,
    announce = true,
    whisper = false,
    resetAfterCombat = true,
    scale = 1,
}, { point = "TOP", relPoint = "TOP", x = 0, y = -120 })
local Get, Enabled, Cfg = F.Get, F.Enabled, F.Cfg
local Kit = CUI.Kit
local Pal = Kit.Palette

_G.BINDING_HEADER_CUI_CCMARKS = "CludesUI CC Marker Bar"
_G["BINDING_NAME_CLICK CludesUICCAssign:LeftButton"] = "Assign Crowd Control to Target"

local MARK = { STAR = 1, CIRCLE = 2, DIAMOND = 3, TRIANGLE = 4, MOON = 5, SQUARE = 6, CROSS = 7, SKULL = 8 }
local MARK_NAMES = { "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull" }
local ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_%d"

-- In the order they are tried; Freezing Trap last, as it holds anything.
local CONTROLS = {
    { class = "MAGE", spell = 118, name = "Polymorph", level = 8, mark = MARK.MOON, mechanic = 17,
        types = { Humanoid = true, Beast = true, Critter = true } },
    { class = "PRIEST", spell = 9484, name = "Shackle Undead", level = 20, mark = MARK.TRIANGLE, mechanic = 20,
        types = { Undead = true } },
    { class = "WARLOCK", spell = 710, name = "Banish", level = 28, mark = MARK.DIAMOND, mechanic = 18,
        types = { Demon = true, Elemental = true } },
    { class = "DRUID", spell = 2637, name = "Hibernate", level = 18, mark = MARK.CIRCLE, mechanic = 10,
        types = { Beast = true, Dragonkin = true } },
    { class = "ROGUE", spell = 6770, name = "Sap", level = 10, mark = MARK.STAR, beforePull = true,
        types = { Humanoid = true } },
    { class = "HUNTER", spell = 1499, name = "Freezing Trap", level = 20, mark = MARK.SQUARE },
}
CUI._CCControls = CONTROLS

local assigned = {} -- mark -> { mob, control, player }
local bar, assignButton, sayButton, listText
local queued -- a show/hide waiting for combat to end

local function Secret(v) return v ~= nil and issecretvalue and issecretvalue(v) end

-------------------------------------------------------------------------------
--  Who can do what
-------------------------------------------------------------------------------
local function GroupUnits()
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
    return units
end

-- Everyone in the group: { name, class, level }.
local function Roster()
    local list = {}
    for _, unit in ipairs(GroupUnits()) do
        if UnitExists(unit) then
            local name = UnitName(unit)
            local _, class = UnitClass(unit)
            local level = UnitLevel(unit)
            if name and not Secret(name) and class and not Secret(level) then
                list[#list + 1] = { name = name, class = class, level = level or 0, unit = unit }
            end
        end
    end
    return list
end

local function Busy(name)
    for _, a in pairs(assigned) do
        if a.player == name then return true end
    end
    return false
end

-- Immune by Creature Scout's data (nil when it is not loaded).
local function Immune(npc, control)
    if not (control.mechanic and npc and CUI._Scout and CUI._Scout.Lookup) then return false end
    local _, _, stats = CUI._Scout.Lookup(npc)
    local mask = stats and stats[3]
    return mask ~= nil and bit.band(mask, bit.lshift(1, control.mechanic - 1)) ~= 0
end

local function NpcID(guid)
    if type(guid) ~= "string" or Secret(guid) then return nil end
    local kind, _, _, _, _, entry = strsplit("-", guid)
    if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
    return tonumber(entry)
end

-- The mark already given to a mob, by its GUID.
local function MarkOf(guid)
    for mark, a in pairs(assigned) do
        if a.guid == guid then return mark end
    end
end

-- The best control for the target: control, player name, mark, or nil and why.
local function Pick(unit)
    unit = unit or "target"
    if not UnitExists(unit) or UnitIsPlayer(unit) or UnitIsDead(unit) then return nil, "Target an enemy first." end
    local hostile = UnitCanAttack("player", unit)
    if Secret(hostile) or not hostile then return nil, "Target an enemy first." end
    local kind = UnitCreatureType(unit)
    if Secret(kind) then return nil, "The game hides what that is right now." end
    local guid = UnitGUID(unit)
    local npc = NpcID(guid)
    local inCombat = UnitAffectingCombat(unit)
    local roster = Roster()
    local blocked
    for _, control in ipairs(CONTROLS) do
        local fits = not control.types or (kind and control.types[kind])
        if fits and control.beforePull and inCombat and not Secret(inCombat) then fits = false end
        if fits and Immune(npc, control) then
            fits = false
            blocked = ("It is immune to %s."):format(control.name)
        end
        if fits then
            for _, member in ipairs(roster) do
                if member.class == control.class and member.level >= control.level and not Busy(member.name) then
                    local mark = control.mark
                    if assigned[mark] and assigned[mark].guid ~= guid then
                        mark = nil
                        for m = 1, 6 do
                            if not assigned[m] then
                                mark = m
                                break
                            end
                        end
                    end
                    if mark then return control, member.name, mark, guid, UnitName(unit) end
                end
            end
        end
    end
    return nil, blocked or ("Nobody free in your group can crowd control a %s."):format(kind or "creature")
end
CUI._CCPick = Pick

-------------------------------------------------------------------------------
--  Chat
-------------------------------------------------------------------------------
local function GroupChannel()
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
end

local function Send(text)
    local channel = GroupChannel()
    if not channel or (C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown()) then
        CUI.Print("|cff4cc9f0CC:|r " .. text:gsub("{rt(%d)}", function(i) return "|T" .. ICON:format(i) .. ":0|t" end))
        return
    end
    C_ChatInfo.SendChatMessage(text, channel)
end

local function AssignmentText(mark, a) return ("{rt%d} %s: %s"):format(mark, a.control.name, a.player) end

local function Announce()
    local parts = {}
    for mark = 1, 6 do
        if assigned[mark] then parts[#parts + 1] = AssignmentText(mark, assigned[mark]) end
    end
    if #parts == 0 then
        CUI.Print("|cff4cc9f0CC:|r nothing is assigned yet. Target a mob and press CC.")
        return
    end
    Send(table.concat(parts, ", ") .. ". Kill {rt8} then {rt7}.")
end

local function RefreshList()
    if not listText then return end
    local lines = {}
    for mark = 1, 6 do
        local a = assigned[mark]
        if a then
            lines[#lines + 1] = ("|T%s:0|t %s: %s (%s)"):format(ICON:format(mark), a.control.name, a.player, a.mob or "?")
        end
    end
    listText:SetText(table.concat(lines, "\n"))
end

local function ClearAssignments()
    wipe(assigned)
    RefreshList()
end

-- After the CC button's mark went on: record it and say so.
local function Assigned(control, player, mark, guid, mob)
    assigned[mark] = { control = control, player = player, guid = guid, mob = mob }
    RefreshList()
    if Get("announce") then Send(AssignmentText(mark, assigned[mark]) .. (mob and (" (" .. mob .. ")") or "")) end
    if Get("whisper") and player ~= UnitName("player") and not (C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown()) then
        C_ChatInfo.SendChatMessage(("%s the {rt%d} please."):format(control.name, mark), "WHISPER", nil, player)
    end
end

-------------------------------------------------------------------------------
--  The bar
-------------------------------------------------------------------------------
local BTN, GAP = 24, 3

local function CreateMarkButton(parent, index, x)
    local b = Kit.SecureButton(parent, nil, "", BTN, BTN, { key = "essentials" })
    b:SetAttribute("type", "macro")
    b:SetAttribute("macrotext", ("/tm %d"):format(index))
    local tex = b:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("TOPLEFT", 3, -3)
    tex:SetPoint("BOTTOMRIGHT", -3, 3)
    if index > 0 then
        tex:SetTexture(ICON:format(index))
    else
        b:SetText("x")
    end
    b:SetPoint("LEFT", x, 0)
    b:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(index > 0 and ("Mark your target: " .. MARK_NAMES[index]) or "Clear your target's mark")
        GameTooltip:Show()
    end)
    b:HookScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

local pending
local function BuildBar()
    if bar then return bar end
    bar = CreateFrame("Frame", "CludesUICCMarkBar", UIParent)
    local count = 9
    local width = count * (BTN + GAP) + 3 * (44 + GAP) + 6
    bar:SetSize(width, BTN + 6)
    Kit.Panel(bar)
    bar:SetMovable(true)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function(self)
        if IsShiftKeyDown() and not InCombatLockdown() then self:StartMoving() end
    end)
    bar:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint(1)
        Cfg().pos = { point = point, relPoint = relPoint, x = x, y = y }
    end)
    local x = 3
    for _, index in ipairs({ 8, 7, 1, 2, 3, 4, 5, 6, 0 }) do
        CreateMarkButton(bar, index, x)
        x = x + BTN + GAP
    end
    assignButton = Kit.SecureButton(bar, "CludesUICCAssign", "CC", 44, BTN, { key = "essentials" })
    assignButton:RegisterForClicks("AnyDown")
    assignButton:SetAttribute("type", "macro")
    assignButton:SetAttribute("macrotext", "")
    assignButton:SetPoint("LEFT", x, 0)
    assignButton:SetScript("PreClick", function(self)
        pending = nil
        if InCombatLockdown() then
            CUI.Print("|cff4cc9f0CC:|r assign crowd control before the pull: the game blocks it in combat.")
            return
        end
        local control, player, mark, guid, mob = Pick("target")
        if not control then
            self:SetAttribute("macrotext", "")
            CUI.Print("|cff4cc9f0CC:|r " .. player)
            return
        end
        local already = MarkOf(guid)
        if already then assigned[already] = nil end
        self:SetAttribute("macrotext", ("/tm %d"):format(mark))
        pending = { control, player, mark, guid, mob }
    end)
    assignButton:SetScript("PostClick", function()
        if pending then Assigned(unpack(pending)) end
        pending = nil
    end)
    assignButton:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Assign Crowd Control")
        local control, player, mark = Pick("target")
        if control then
            GameTooltip:AddLine(("%s from %s, marked %s"):format(control.name, player, MARK_NAMES[mark]), 1, 1, 1)
        else
            GameTooltip:AddLine(player, 1, 0.6, 0.6, true)
        end
        GameTooltip:Show()
    end)
    assignButton:HookScript("OnLeave", function() GameTooltip:Hide() end)
    x = x + 44 + GAP
    sayButton = Kit.Button(bar, "Say", 44, BTN, Announce, { key = "essentials", tip = "Post every assignment and the kill order in group chat." })
    sayButton:SetPoint("LEFT", x, 0)
    x = x + 44 + GAP
    local resetButton = Kit.Button(bar, "Reset", 44, BTN, ClearAssignments, { key = "essentials", tip = "Forget the assignments." })
    resetButton:SetPoint("LEFT", x, 0)
    listText = bar:CreateFontString(nil, "OVERLAY")
    Kit.Font(listText, Kit.SMALL_SIZE, "essentials")
    listText:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 4, -4)
    listText:SetJustifyH("LEFT")
    listText:SetTextColor(Pal.text[1], Pal.text[2], Pal.text[3])
    F.Place(bar)
    bar:Hide()
    return bar
end

local function BarWanted()
    if not Enabled() then return false end
    if not Get("instancesOnly") then return true end
    local inside, kind = IsInInstance()
    return inside and (kind == "party" or kind == "raid")
end

local function Sync()
    if InCombatLockdown() then
        queued = true
        return
    end
    queued = false
    local want = BarWanted()
    if want then BuildBar() end
    if bar then
        bar:SetScale(Get("scale") or 1)
        bar:SetShown(want)
    end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        if Get("resetAfterCombat") and next(assigned) then ClearAssignments() end
        if queued then Sync() end
        return
    end
    Sync()
end)

local function Apply()
    events:UnregisterAllEvents()
    if Enabled() then
        events:RegisterEvent("PLAYER_ENTERING_WORLD")
        events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
        events:RegisterEvent("GROUP_ROSTER_UPDATE")
    end
    Sync()
end

CUI._CCMarks = {
    Get = Get,
    Cfg = Cfg,
    Apply = Apply,
    Pick = Pick,
    Assigned = Assigned,
    Announce = Announce,
    Reset = ClearAssignments,
    State = function() return assigned end,
    Toggle = function()
        if InCombatLockdown() then return end
        BuildBar()
        bar:SetShown(not bar:IsShown())
    end,
}

SLASH_CUICCMARK1 = "/ccmark"
SlashCmdList.CUICCMARK = function() CUI._CCMarks.Toggle() end

F.Start(Apply, {
    key = "CUIFE_CCMarks",
    label = "CC Marker Bar",
    order = 62,
    frame = function(build)
        if build then BuildBar() end
        return bar
    end,
    size = function() return bar and bar:GetWidth() or 400, bar and bar:GetHeight() or 30 end,
})
