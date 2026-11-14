if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if not (CludesUI and CludesUI.IS_FOREVER) then
    return
end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_GroupWatch.lua  (WoW Forever only)
--  Healer Mana: every healer in your group and their mana, lowest first,
--  with a cup beside one who is drinking. Dead and offline healers go last.
--  A healer is whoever has the healer role, or with no role set a priest,
--  paladin, druid or shaman. While the game keeps mana secret, the game
--  writes the percent itself and the list holds its last order.
--
--  Pet Tracker: a warning while a hunter or warlock has no pet out (or, if
--  turned on, while it is passive or low on health). A warlock who has
--  sacrificed their demon, and a hunter with Lone Wolf, are left alone.
--  Hidden while mounted and for a few seconds after, while the pet returns.
-------------------------------------------------------------------------------
local _, module = ...

local function Font()
    return CludesUI.GetFontPath("essentials")
end
local function Secret(v)
    return issecretvalue and issecretvalue(v)
end
local function AurasSecret()
    return C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret()
end

-------------------------------------------------------------------------------
--  Healer Mana
-------------------------------------------------------------------------------
local HM = module.Feature(
    "healerMana",
    { enabled = false, where = "instance", showSelf = true, drinking = true, width = 160, size = 12 },
    { point = "LEFT", relPoint = "LEFT", x = 40, y = -120 }
)

local MANA, MANA_TOKEN = 0, "MANA"
local DRINK_SPELL = 430
local DRINK_ICON = "Interface\\Icons\\INV_Drink_07"
local HEALER_CLASSES = { PRIEST = true, PALADIN = true, DRUID = true, SHAMAN = true }
local LOW, OUT = 0.6, 0.3
local ROW_PAD, PAD, ICON_GAP = 4, 6, 4
local DEAD, OFFLINE, UNKNOWN = "Dead", "Offline", "--"
local NO_RANK = math.huge
local UNIT_EVENTS =
    { "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER", "UNIT_CONNECTION", "UNIT_AURA" }

local hmFrame, drinkName, shareCurve
local rows, members, list, tracked, rank, units, watchers = {}, {}, {}, {}, {}, {}, {}
local RAID, PARTY = {}, {}
for i = 1, 40 do
    RAID[i] = "raid" .. i
end
for i = 1, 4 do
    PARTY[i] = "party" .. i
end

local function HMHere()
    if not IsInGroup() then
        return false
    end
    if HM.Get("where") == "group" then
        return true
    end
    local _, kind = IsInInstance()
    return kind == "party" or kind == "raid"
end

local function IsHealer(unit, class)
    local role = UnitGroupRolesAssigned(unit)
    if Secret(role) then
        role = nil
    end
    if role == "HEALER" then
        return true
    end
    if role == "TANK" or role == "DAMAGER" then
        return false
    end
    return HEALER_CLASSES[class] == true
end

local function Units()
    wipe(units)
    if HM.Get("showSelf") then
        units[1] = "player"
    end
    if IsInRaid() then
        for i = 1, math.min(GetNumGroupMembers(), 40) do
            local me = UnitIsUnit(RAID[i], "player")
            if not Secret(me) and not me then
                units[#units + 1] = RAID[i]
            end
        end
    else
        for i = 1, math.min(GetNumSubgroupMembers(), 4) do
            units[#units + 1] = PARTY[i]
        end
    end
    return units
end

local function Roster()
    wipe(list)
    wipe(tracked)
    for _, unit in ipairs(Units()) do
        local name, guid = UnitName(unit), UnitGUID(unit)
        local _, class = UnitClass(unit)
        if
            name
            and guid
            and not (Secret(name) or Secret(guid) or Secret(class))
            and IsHealer(unit, class)
        then
            local n = #list + 1
            local m = members[n] or {}
            members[n] = m
            if m.guid ~= guid then
                m.pct, m.drinking = nil, false
            end
            m.unit, m.name, m.class, m.guid = unit, name, class, guid
            list[n], tracked[unit] = m, m
        end
    end
end

local function CanReadDrink()
    if not HM.Get("drinking") or AurasSecret() then
        return false
    end
    drinkName = drinkName or C_Spell.GetSpellName(DRINK_SPELL)
    return drinkName ~= nil
end

local function Drinking(m)
    if not (CanReadDrink() and C_UnitAuras.GetAuraDataBySpellName) then
        return
    end
    local aura = C_UnitAuras.GetAuraDataBySpellName(m.unit, drinkName, "HELPFUL")
    m.drinking = aura ~= nil
    m.drinkID = aura and aura.auraInstanceID or nil
end

-- True when the drinking state changed (an aura update for this unit).
local function DrinkChanged(m, info)
    if not CanReadDrink() then
        return false
    end
    local was = m.drinking
    if not info or info.isFullUpdate then
        Drinking(m)
        return m.drinking ~= was
    end
    for _, a in ipairs(info.addedAuras or {}) do
        if not Secret(a.name) and a.name == drinkName then
            m.drinking, m.drinkID = true, a.auraInstanceID
        end
    end
    local id = m.drinkID
    if id then
        for _, r in ipairs(info.removedAuraInstanceIDs or {}) do
            if r == id then
                m.drinking, m.drinkID = false, nil
            end
        end
    end
    return m.drinking ~= was
end

local function Read(m)
    local online, dead = UnitIsConnected(m.unit), UnitIsDeadOrGhost(m.unit)
    if Secret(online) then
        online = true
    end
    if Secret(dead) then
        dead = false
    end
    m.state = (not online and OFFLINE) or (dead and DEAD) or nil
    local cur, max = UnitPower(m.unit, MANA), UnitPowerMax(m.unit, MANA)
    m.secret = (Secret(cur) or Secret(max)) == true
    if not m.secret and max > 0 then
        m.pct = cur / max
    end
end

local function Less(a, b)
    if (a.state ~= nil) ~= (b.state ~= nil) then
        return b.state ~= nil
    end
    local pa, pb = a.pct or NO_RANK, b.pct or NO_RANK
    if pa ~= pb then
        return pa < pb
    end
    if a.name ~= b.name then
        return a.name < b.name
    end
    return a.guid < b.guid
end

-- While any mana is secret, keep the last order (it cannot be compared).
local function Held(a, b)
    local ra, rb = rank[a.guid] or NO_RANK, rank[b.guid] or NO_RANK
    if ra ~= rb then
        return ra < rb
    end
    return a.guid < b.guid
end

local function Sort()
    for i = 1, #list do
        if list[i].secret then
            table.sort(list, Held)
            return
        end
    end
    table.sort(list, Less)
    wipe(rank)
    for i = 1, #list do
        rank[list[i].guid] = i
    end
end

local function SecretShare(fs, unit)
    if not (UnitPowerPercent and C_CurveUtil) then
        return false
    end
    if not shareCurve then
        shareCurve = C_CurveUtil.CreateCurve()
        shareCurve:SetType(Enum.LuaCurveType.Linear)
        shareCurve:AddPoint(0, 0)
        shareCurve:AddPoint(1, 100)
    end
    fs:SetFormattedText("%.1f%%", UnitPowerPercent(unit, MANA, false, shareCurve))
    return true
end

local SAMPLE = {
    { name = "Priest", class = "PRIEST", guid = "1", pct = 0.18 },
    { name = "Druid", class = "DRUID", guid = "2", pct = 0.47, drinking = true },
    { name = "Shaman", class = "SHAMAN", guid = "3", pct = 0.83 },
    { name = "Paladin", class = "PALADIN", guid = "4", state = DEAD },
}

local function Row(i)
    local r = rows[i]
    if r then
        return r
    end
    r = CreateFrame("Frame", nil, hmFrame)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetTexture(DRINK_ICON)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.icon:SetPoint("LEFT", 0, -1)
    r.pct = r:CreateFontString(nil, "OVERLAY")
    r.pct:SetPoint("RIGHT")
    r.pct:SetJustifyH("RIGHT")
    r.name = r:CreateFontString(nil, "OVERLAY")
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    rows[i] = r
    return r
end

local function PaintRows(entries)
    local size, drinks = HM.Get("size"), HM.Get("drinking")
    local step = size + ROW_PAD
    hmFrame:SetSize(HM.Get("width"), #entries * step + 2 * PAD)
    for i, m in ipairs(entries) do
        local r = Row(i)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", PAD, -PAD - (i - 1) * step)
        r:SetPoint("TOPRIGHT", -PAD, -PAD - (i - 1) * step)
        r:SetHeight(step)
        CludesUI.Kit.Font(r.name, size, "essentials")
        CludesUI.Kit.Font(r.pct, size, "essentials")
        r.icon:SetSize(size, size)
        r.name:ClearAllPoints()
        r.name:SetPoint("LEFT", drinks and (size + ICON_GAP) or 0, 0)
        r.name:SetPoint("RIGHT", r.pct, "LEFT", -8, 0)
        r.name:SetText(m.name)
        local c = RAID_CLASS_COLORS[m.class]
        if c then
            r.name:SetTextColor(c.r, c.g, c.b)
        else
            r.name:SetTextColor(1, 1, 1)
        end
        r.icon:SetShown(drinks and m.drinking == true)
        if m.state then
            r.pct:SetText(m.state)
            if m.state == DEAD then
                r.pct:SetTextColor(1, 0.3, 0.3)
            else
                r.pct:SetTextColor(0.6, 0.6, 0.6)
            end
        elseif m.secret then
            r.pct:SetTextColor(1, 1, 1)
            if not SecretShare(r.pct, m.unit) then
                r.pct:SetText(UNKNOWN)
            end
        elseif m.pct then
            r.pct:SetText(("%.1f%%"):format(math.floor(m.pct * 1000 + 0.5) / 10))
            if m.pct < OUT then
                r.pct:SetTextColor(1, 0.3, 0.3)
            elseif m.pct < LOW then
                r.pct:SetTextColor(1, 0.8, 0.2)
            else
                r.pct:SetTextColor(0.4, 0.9, 0.5)
            end
        else
            r.pct:SetText(UNKNOWN)
            r.pct:SetTextColor(0.6, 0.6, 0.6)
        end
        r:Show()
    end
    for i = #entries + 1, #rows do
        rows[i]:Hide()
    end
end

local function HMRedraw()
    if not hmFrame then
        return
    end
    if CludesUI._unlockActive and HM.Enabled() then
        PaintRows(SAMPLE)
        hmFrame:Show()
        return
    end
    if not (HM.Enabled() and HMHere()) or #list == 0 then
        hmFrame:Hide()
        return
    end
    for i = 1, #list do
        Read(list[i])
    end
    Sort()
    PaintRows(list)
    hmFrame:Show()
end

local hmPending
local function HMSoon()
    if hmPending then
        return
    end
    hmPending = true
    C_Timer.After(0.25, function()
        hmPending = false
        HMRedraw()
    end)
end

local function OnUnitEvent(w, event, _, arg)
    if event == "UNIT_POWER_UPDATE" and (Secret(arg) or arg ~= MANA_TOKEN) then
        return
    end
    local m = tracked[w.unit]
    if not m then
        return
    end
    if event == "UNIT_AURA" and not DrinkChanged(m, arg) then
        return
    end
    HMSoon()
end

local function Watch()
    for i, m in ipairs(list) do
        local w = watchers[i]
        if not w then
            w = CreateFrame("Frame")
            w:SetScript("OnEvent", OnUnitEvent)
            watchers[i] = w
        end
        if w.unit ~= m.unit then
            w:UnregisterAllEvents()
            w.unit = m.unit
            for _, e in ipairs(UNIT_EVENTS) do
                w:RegisterUnitEvent(e, m.unit)
            end
        end
    end
    for i = #list + 1, #watchers do
        watchers[i]:UnregisterAllEvents()
        watchers[i].unit = nil
    end
end

local hmEvents = CreateFrame("Frame")
local HMApply
local rosterPending
hmEvents:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
        return HMApply()
    end
    if rosterPending then
        return
    end
    rosterPending = true
    C_Timer.After(0.25, function()
        rosterPending = false
        HMApply()
    end)
end)

HMApply = function()
    if not HM.Enabled() then
        hmEvents:UnregisterAllEvents()
        wipe(list)
        wipe(tracked)
        Watch()
        if hmFrame then
            hmFrame:Hide()
        end
        return
    end
    if not hmFrame then
        hmFrame = CreateFrame("Frame", "CludesUIHealerMana", UIParent)
        CludesUI.Kit.Panel(hmFrame, 0.75)
    end
    for _, e in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED", "PLAYER_ENTERING_WORLD" }) do
        hmEvents:RegisterEvent(e)
    end
    wipe(list)
    wipe(tracked)
    if HMHere() then
        Roster()
        for i = 1, #list do
            Drinking(list[i])
        end
    end
    Watch()
    if not CludesUI._unlockActive then
        HM.Place(hmFrame)
    end
    HMRedraw()
end

HM.Start(HMApply, {
    key = "CUI_HealerMana",
    label = "Healer Mana",
    order = 746,
    frame = function(build)
        if build and not hmFrame then
            HMApply()
        end
        if build and hmFrame then
            HMRedraw()
        end
        return hmFrame
    end,
    size = function()
        return HM.Get("width"), #SAMPLE * (HM.Get("size") + ROW_PAD) + 2 * PAD
    end,
    noAnchorTarget = true,
    noSizeMatchTarget = true,
})

-------------------------------------------------------------------------------
--  Pet Tracker
-------------------------------------------------------------------------------
local PT = module.Feature(
    "petTracker",
    {
        enabled = false,
        passive = true,
        lowHealth = false,
        lowBelow = 25,
        instanceOnly = false,
        combatOnly = false,
        hideMounted = true,
        showIcon = true,
        size = 20,
        missingText = "Pet Missing",
        passiveText = "Pet Passive",
        lowText = "Pet Low HP",
    },
    { point = "CENTER", relPoint = "CENTER", x = 0, y = 260 }
)

local CALL_PET, SUMMON_IMP = 883, 688
local LONE_WOLF, LONE_WOLF_TAUGHT = 415370, 409979
local PET_ICON = 132161
local SACRIFICE_BUFFS = { 18789, 18790, 18791, 18792 }
local DISMOUNT_DELAY = 5
local PT_EVENTS = {
    "PET_BAR_UPDATE",
    "PLAYER_MOUNT_DISPLAY_CHANGED",
    "PLAYER_DEAD",
    "PLAYER_ALIVE",
    "PLAYER_UNGHOST",
    "SPELLS_CHANGED",
    "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED",
    "PLAYER_ENTERING_WORLD",
    "PLAYER_CONTROL_LOST",
    "PLAYER_CONTROL_GAINED",
}

local ptFrame, curve, mounted, dismountTimer, sacrificed
local _, CLASS = UnitClass("player")

local function Known(id)
    return C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(id)
end

local function PTBuild()
    if ptFrame then
        return ptFrame
    end
    ptFrame = CreateFrame("Frame", "CludesUIPetTracker", UIParent)
    ptFrame.icon = ptFrame:CreateTexture(nil, "ARTWORK")
    ptFrame.icon:SetTexture(PET_ICON)
    ptFrame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    ptFrame.text = ptFrame:CreateFontString(nil, "OVERLAY")
    ptFrame.text:SetTextColor(1, 0.2, 0.2)
    ptFrame:Hide()
    return ptFrame
end

local function Restyle()
    local size = PT.Get("size")
    CludesUI.Kit.Font(ptFrame.text, size, "essentials")
    ptFrame.text:ClearAllPoints()
    if PT.Get("showIcon") then
        ptFrame.icon:SetSize(size + 12, size + 12)
        ptFrame.icon:SetPoint("LEFT")
        ptFrame.icon:Show()
        ptFrame.text:SetPoint("LEFT", ptFrame.icon, "RIGHT", 8, 0)
    else
        ptFrame.icon:Hide()
        ptFrame.text:SetPoint("CENTER")
    end
    ptFrame:SetSize(220, size + 16)
end

-- The warning fades out above the low-health line: 1 below it, 0 above.
local function BuildCurve()
    local below = PT.Get("lowBelow") / 100
    curve = curve or C_CurveUtil.CreateCurve()
    curve:SetType(Enum.LuaCurveType.Step)
    curve:ClearPoints()
    curve:AddPoint(0, 1)
    curve:AddPoint(below - 0.001, 1)
    curve:AddPoint(below, 0)
    curve:AddPoint(1, 0)
end

local function ShouldHavePet()
    if CLASS == "HUNTER" then
        return Known(CALL_PET)
    end
    if CLASS == "WARLOCK" then
        return Known(SUMMON_IMP) and not sacrificed
    end
    return false
end

local function CheckSacrifice()
    if CLASS ~= "WARLOCK" or AurasSecret() then
        return
    end
    sacrificed = false
    for _, id in ipairs(SACRIFICE_BUFFS) do
        if C_UnitAuras.GetPlayerAuraBySpellID(id) then
            sacrificed = true
            return
        end
    end
end

local function IsPassive()
    if not PetHasActionBar() then
        return false
    end
    for i = 1, NUM_PET_ACTION_SLOTS do
        local name, _, _, isActive = GetPetActionInfo(i)
        if name == "PET_MODE_PASSIVE" then
            return isActive == true
        end
    end
    return false
end

local function Warning()
    if UnitIsDeadOrGhost("player") or UnitOnTaxi("player") then
        return
    end
    if PT.Get("hideMounted") and (mounted or dismountTimer) then
        return
    end
    if PT.Get("combatOnly") and not UnitAffectingCombat("player") then
        return
    end
    if PT.Get("instanceOnly") and not IsInInstance() then
        return
    end
    if not ShouldHavePet() then
        return
    end
    if not UnitExists("pet") then
        if CLASS == "HUNTER" and (Known(LONE_WOLF) or Known(LONE_WOLF_TAUGHT)) then
            return
        end
        return "missingText"
    end
    if PT.Get("passive") and IsPassive() then
        return "passiveText"
    end
    if PT.Get("lowHealth") and not UnitIsDeadOrGhost("pet") then
        return "lowText", true
    end
end

local function PTUpdate()
    if not ptFrame then
        return
    end
    if CludesUI._unlockActive and PT.Enabled() then
        ptFrame.text:SetText(PT.Get("missingText"))
        ptFrame:SetAlpha(1)
        ptFrame:Show()
        return
    end
    local key, low = Warning()
    if not key then
        ptFrame:Hide()
        return
    end
    ptFrame.text:SetText(PT.Get(key))
    ptFrame:SetAlpha(low and UnitHealthPercent("pet", true, curve) or 1)
    ptFrame:Show()
end

local ptEvents = CreateFrame("Frame")
ptEvents:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_MOUNT_DISPLAY_CHANGED" then
        local was = mounted
        mounted = IsMounted()
        if dismountTimer then
            dismountTimer:Cancel()
            dismountTimer = nil
        end
        if was and not mounted then
            dismountTimer = C_Timer.NewTimer(DISMOUNT_DELAY, function()
                dismountTimer = nil
                PTUpdate()
            end)
        end
    elseif event == "UNIT_AURA" or event == "PLAYER_REGEN_ENABLED" then
        CheckSacrifice()
    elseif event == "UNIT_HEALTH" and unit ~= "pet" then
        return
    end
    PTUpdate()
end)

local function PTApply()
    ptEvents:UnregisterAllEvents()
    if not PT.Enabled() then
        if dismountTimer then
            dismountTimer:Cancel()
            dismountTimer = nil
        end
        if ptFrame then
            ptFrame:Hide()
        end
        return
    end
    PTBuild()
    Restyle()
    BuildCurve()
    mounted = IsMounted()
    CheckSacrifice()
    for _, e in ipairs(PT_EVENTS) do
        ptEvents:RegisterEvent(e)
    end
    ptEvents:RegisterUnitEvent("UNIT_PET", "player")
    ptEvents:RegisterUnitEvent("UNIT_HEALTH", "pet")
    ptEvents:RegisterUnitEvent("UNIT_MAXHEALTH", "pet")
    if CLASS == "WARLOCK" then
        ptEvents:RegisterUnitEvent("UNIT_AURA", "player")
    end
    if not CludesUI._unlockActive then
        PT.Place(ptFrame)
    end
    PTUpdate()
end

PT.Start(PTApply, {
    key = "CUI_PetTracker",
    label = "Pet Tracker",
    order = 747,
    frame = function(build)
        if build then
            PTBuild()
            Restyle()
            PTUpdate()
        end
        return ptFrame
    end,
    size = function()
        return 220, PT.Get("size") + 16
    end,
    noAnchorTarget = true,
    noSizeMatchTarget = true,
})

CludesUI._GroupWatch = {
    healer = { Get = HM.Get, Cfg = HM.Cfg, Apply = HMApply },
    pet = { Get = PT.Get, Cfg = PT.Cfg, Apply = PTApply },
}
