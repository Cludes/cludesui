if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
if not (CUI and CUI.IS_FOREVER) then return end
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

local function WatchFont() return CUI.GetFontPath("essentials") end
local function Secret(val) return issecretvalue and issecretvalue(val) end
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
local rowList, members, list, tracked, rank, units, watchers = {}, {}, {}, {}, {}, {}, {}
local RAID, PARTY = {}, {}
for index = 1, 40 do
    RAID[index] = "raid" .. index
end
for index = 1, 4 do
    PARTY[index] = "party" .. index
end

local function HealerManaWanted()
    if not IsInGroup() then return false end
    if HM.Get("where") == "group" then return true end
    local _, kind = IsInInstance()
    return kind == "party" or kind == "raid"
end

local function IsHealerUnit(unitToken, class)
    local role = UnitGroupRolesAssigned(unitToken)
    if Secret(role) then role = nil end
    if role == "HEALER" then return true end
    if role == "TANK" or role == "DAMAGER" then return false end
    return HEALER_CLASSES[class] == true
end

local function WatchedUnits()
    wipe(units)
    if HM.Get("showSelf") then units[1] = "player" end
    if IsInRaid() then
        for index = 1, math.min(GetNumGroupMembers(), 40) do
            local me = UnitIsUnit(RAID[index], "player")
            if not Secret(me) and not me then units[#units + 1] = RAID[index] end
        end
    else
        for index = 1, math.min(GetNumSubgroupMembers(), 4) do
            units[#units + 1] = PARTY[index]
        end
    end
    return units
end

local function HealerRoster()
    wipe(list)
    wipe(tracked)
    for _, unitToken in ipairs(WatchedUnits()) do
        local name, unitGuid = UnitName(unitToken), UnitGUID(unitToken)
        local _, class = UnitClass(unitToken)
        if
            name
            and unitGuid
            and not (Secret(name) or Secret(unitGuid) or Secret(class))
            and IsHealerUnit(unitToken, class)
        then
            local num = #list + 1
            local m = members[num] or {}
            members[num] = m
            if m.guid ~= unitGuid then
                m.pct, m.drinking = nil, false
            end
            m.unit, m.name, m.class, m.guid = unitToken, name, class, unitGuid
            list[num], tracked[unitToken] = m, m
        end
    end
end

local function CanSeeDrinking()
    if not HM.Get("drinking") or AurasSecret() then return false end
    drinkName = drinkName or C_Spell.GetSpellName(DRINK_SPELL)
    return drinkName ~= nil
end

local function ReadDrinking(m)
    if not (CanSeeDrinking() and C_UnitAuras.GetAuraDataBySpellName) then return end
    local aura = C_UnitAuras.GetAuraDataBySpellName(m.unit, drinkName, "HELPFUL")
    m.drinking = aura ~= nil
    m.drinkID = aura and aura.auraInstanceID or nil
end

-- True when the drinking state changed (an aura update for this unit).
local function DrinkingChanged(m, details)
    if not CanSeeDrinking() then return false end
    local was = m.drinking
    if not details or details.isFullUpdate then
        ReadDrinking(m)
        return m.drinking ~= was
    end
    for _, a in ipairs(details.addedAuras or {}) do
        if not Secret(a.name) and a.name == drinkName then
            m.drinking, m.drinkID = true, a.auraInstanceID
        end
    end
    local ident = m.drinkID
    if ident then
        for _, region in ipairs(details.removedAuraInstanceIDs or {}) do
            if region == ident then
                m.drinking, m.drinkID = false, nil
            end
        end
    end
    return m.drinking ~= was
end

local function ReadMember(m)
    local online, dead = UnitIsConnected(m.unit), UnitIsDeadOrGhost(m.unit)
    if Secret(online) then online = true end
    if Secret(dead) then dead = false end
    m.state = (not online and OFFLINE) or (dead and DEAD) or nil
    local current, max = UnitPower(m.unit, MANA), UnitPowerMax(m.unit, MANA)
    m.secret = (Secret(current) or Secret(max)) == true
    if not m.secret and max > 0 then m.pct = current / max end
end

local function HealerOrder(a, b)
    if (a.state ~= nil) ~= (b.state ~= nil) then return b.state ~= nil end
    local pa, pb = a.pct or NO_RANK, b.pct or NO_RANK
    if pa ~= pb then return pa < pb end
    if a.name ~= b.name then return a.name < b.name end
    return a.guid < b.guid
end

-- While any mana is secret, keep the last order (it cannot be compared).
local function KeepLastOrder(a, b)
    local ra, rb = rank[a.guid] or NO_RANK, rank[b.guid] or NO_RANK
    if ra ~= rb then return ra < rb end
    return a.guid < b.guid
end

local function SortHealers()
    for index = 1, #list do
        if list[index].secret then
            table.sort(list, KeepLastOrder)
            return
        end
    end
    table.sort(list, HealerOrder)
    wipe(rank)
    for index = 1, #list do
        rank[list[index].guid] = index
    end
end

local function ShowSecretMana(fontStr, unitToken)
    if not (UnitPowerPercent and C_CurveUtil) then return false end
    if not shareCurve then
        shareCurve = C_CurveUtil.CreateCurve()
        shareCurve:SetType(Enum.LuaCurveType.Linear)
        shareCurve:AddPoint(0, 0)
        shareCurve:AddPoint(1, 100)
    end
    fontStr:SetFormattedText("%.1f%%", UnitPowerPercent(unitToken, MANA, false, shareCurve))
    return true
end

local SAMPLE = {
    { name = "Priest", class = "PRIEST", guid = "1", pct = 0.18 },
    { name = "Druid", class = "DRUID", guid = "2", pct = 0.47, drinking = true },
    { name = "Shaman", class = "SHAMAN", guid = "3", pct = 0.83 },
    { name = "Paladin", class = "PALADIN", guid = "4", state = DEAD },
}

local function HealerRow(index)
    local row = rowList[index]
    if row then return row end
    row = CreateFrame("Frame", nil, hmFrame)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetTexture(DRINK_ICON)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.icon:SetPoint("LEFT", 0, -1)
    row.pct = row:CreateFontString(nil, "OVERLAY")
    row.pct:SetPoint("RIGHT")
    row.pct:SetJustifyH("RIGHT")
    row.name = row:CreateFontString(nil, "OVERLAY")
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    rowList[index] = row
    return row
end

local function FillRows(entries)
    local size, drinks = HM.Get("size"), HM.Get("drinking")
    local step = size + ROW_PAD
    hmFrame:SetSize(HM.Get("width"), #entries * step + 2 * PAD)
    for index, m in ipairs(entries) do
        local region = HealerRow(index)
        region:ClearAllPoints()
        region:SetPoint("TOPLEFT", PAD, -PAD - (index - 1) * step)
        region:SetPoint("TOPRIGHT", -PAD, -PAD - (index - 1) * step)
        region:SetHeight(step)
        CUI.Kit.Font(region.name, size, "essentials")
        CUI.Kit.Font(region.pct, size, "essentials")
        region.icon:SetSize(size, size)
        region.name:ClearAllPoints()
        region.name:SetPoint("LEFT", drinks and (size + ICON_GAP) or 0, 0)
        region.name:SetPoint("RIGHT", region.pct, "LEFT", -8, 0)
        region.name:SetText(m.name)
        local color = RAID_CLASS_COLORS[m.class]
        if color then
            region.name:SetTextColor(color.r, color.g, color.b)
        else
            region.name:SetTextColor(1, 1, 1)
        end
        region.icon:SetShown(drinks and m.drinking == true)
        if m.state then
            region.pct:SetText(m.state)
            if m.state == DEAD then
                region.pct:SetTextColor(1, 0.3, 0.3)
            else
                region.pct:SetTextColor(0.6, 0.6, 0.6)
            end
        elseif m.secret then
            region.pct:SetTextColor(1, 1, 1)
            if not ShowSecretMana(region.pct, m.unit) then region.pct:SetText(UNKNOWN) end
        elseif m.pct then
            region.pct:SetText(("%.1f%%"):format(math.floor(m.pct * 1000 + 0.5) / 10))
            if m.pct < OUT then
                region.pct:SetTextColor(1, 0.3, 0.3)
            elseif m.pct < LOW then
                region.pct:SetTextColor(1, 0.8, 0.2)
            else
                region.pct:SetTextColor(0.4, 0.9, 0.5)
            end
        else
            region.pct:SetText(UNKNOWN)
            region.pct:SetTextColor(0.6, 0.6, 0.6)
        end
        region:Show()
    end
    for index = #entries + 1, #rowList do
        rowList[index]:Hide()
    end
end

local function RedrawHealers()
    if not hmFrame then return end
    if CUI._unlockActive and HM.Enabled() then
        FillRows(SAMPLE)
        hmFrame:Show()
        return
    end
    if not (HM.Enabled() and HealerManaWanted()) or #list == 0 then
        hmFrame:Hide()
        return
    end
    for index = 1, #list do
        ReadMember(list[index])
    end
    SortHealers()
    FillRows(list)
    hmFrame:Show()
end

local hmPending
local function RedrawHealersSoon()
    if hmPending then return end
    hmPending = true
    C_Timer.After(0.25, function()
        hmPending = false
        RedrawHealers()
    end)
end

local function OnHealerEvent(wid, evt, _, arg)
    if evt == "UNIT_POWER_UPDATE" and (Secret(arg) or arg ~= MANA_TOKEN) then return end
    local m = tracked[wid.unit]
    if not m then return end
    if evt == "UNIT_AURA" and not DrinkingChanged(m, arg) then return end
    RedrawHealersSoon()
end

local function WatchHealers()
    for index, m in ipairs(list) do
        local wid = watchers[index]
        if not wid then
            wid = CreateFrame("Frame")
            wid:SetScript("OnEvent", OnHealerEvent)
            watchers[index] = wid
        end
        if wid.unit ~= m.unit then
            wid:UnregisterAllEvents()
            wid.unit = m.unit
            for _, event in ipairs(UNIT_EVENTS) do
                wid:RegisterUnitEvent(event, m.unit)
            end
        end
    end
    for index = #list + 1, #watchers do
        watchers[index]:UnregisterAllEvents()
        watchers[index].unit = nil
    end
end

local hmEvents = CreateFrame("Frame")
local HMApply
local rosterPending
hmEvents:SetScript("OnEvent", function(_, evt)
    if evt == "PLAYER_ENTERING_WORLD" then return HMApply() end
    if rosterPending then return end
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
        WatchHealers()
        if hmFrame then hmFrame:Hide() end
        return
    end
    if not hmFrame then
        hmFrame = CreateFrame("Frame", "CludesUIHealerMana", UIParent)
        CUI.Kit.Panel(hmFrame, 0.75)
    end
    for _, event in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED", "PLAYER_ENTERING_WORLD" }) do
        hmEvents:RegisterEvent(event)
    end
    wipe(list)
    wipe(tracked)
    if HealerManaWanted() then
        HealerRoster()
        for index = 1, #list do
            ReadDrinking(list[index])
        end
    end
    WatchHealers()
    if not CUI._unlockActive then HM.Place(hmFrame) end
    RedrawHealers()
end

HM.Start(HMApply, {
    key = "CUI_HealerMana",
    label = "Healer Mana",
    order = 746,
    frame = function(build)
        if build and not hmFrame then HMApply() end
        if build and hmFrame then RedrawHealers() end
        return hmFrame
    end,
    size = function() return HM.Get("width"), #SAMPLE * (HM.Get("size") + ROW_PAD) + 2 * PAD end,
    noAnchorTarget = true,
    noSizeMatchTarget = true,
})

-------------------------------------------------------------------------------
--  Pet Tracker
-------------------------------------------------------------------------------
local PT = module.Feature("petTracker", {
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
}, { point = "CENTER", relPoint = "CENTER", x = 0, y = 260 })

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

local function KnowsSpell(ident)
    return C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(ident)
end

local function BuildPetWarning()
    if ptFrame then return ptFrame end
    ptFrame = CreateFrame("Frame", "CludesUIPetTracker", UIParent)
    ptFrame.icon = ptFrame:CreateTexture(nil, "ARTWORK")
    ptFrame.icon:SetTexture(PET_ICON)
    ptFrame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    ptFrame.text = ptFrame:CreateFontString(nil, "OVERLAY")
    ptFrame.text:SetTextColor(1, 0.2, 0.2)
    ptFrame:Hide()
    return ptFrame
end

local function StylePetWarning()
    local size = PT.Get("size")
    CUI.Kit.Font(ptFrame.text, size, "essentials")
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
local function BuildFadeCurve()
    local below = PT.Get("lowBelow") / 100
    curve = curve or C_CurveUtil.CreateCurve()
    curve:SetType(Enum.LuaCurveType.Step)
    curve:ClearPoints()
    curve:AddPoint(0, 1)
    curve:AddPoint(below - 0.001, 1)
    curve:AddPoint(below, 0)
    curve:AddPoint(1, 0)
end

local function ExpectsPet()
    if CLASS == "HUNTER" then return KnowsSpell(CALL_PET) end
    if CLASS == "WARLOCK" then return KnowsSpell(SUMMON_IMP) and not sacrificed end
    return false
end

local function SacrificeActive()
    if CLASS ~= "WARLOCK" or AurasSecret() then return end
    sacrificed = false
    for _, ident in ipairs(SACRIFICE_BUFFS) do
        if C_UnitAuras.GetPlayerAuraBySpellID(ident) then
            sacrificed = true
            return
        end
    end
end

local function PetIsPassive()
    if not PetHasActionBar() then return false end
    for index = 1, NUM_PET_ACTION_SLOTS do
        local name, _, _, isActive = GetPetActionInfo(index)
        if name == "PET_MODE_PASSIVE" then return isActive == true end
    end
    return false
end

local function PetWarningText()
    if UnitIsDeadOrGhost("player") or UnitOnTaxi("player") then return end
    if PT.Get("hideMounted") and (mounted or dismountTimer) then return end
    if PT.Get("combatOnly") and not UnitAffectingCombat("player") then return end
    if PT.Get("instanceOnly") and not IsInInstance() then return end
    if not ExpectsPet() then return end
    if not UnitExists("pet") then
        if CLASS == "HUNTER" and (KnowsSpell(LONE_WOLF) or KnowsSpell(LONE_WOLF_TAUGHT)) then return end
        return "missingText"
    end
    if PT.Get("passive") and PetIsPassive() then return "passiveText" end
    if PT.Get("lowHealth") and not UnitIsDeadOrGhost("pet") then return "lowText", true end
end

local function RefreshPetWarning()
    if not ptFrame then return end
    if CUI._unlockActive and PT.Enabled() then
        ptFrame.text:SetText(PT.Get("missingText"))
        ptFrame:SetAlpha(1)
        ptFrame:Show()
        return
    end
    local key, low = PetWarningText()
    if not key then
        ptFrame:Hide()
        return
    end
    ptFrame.text:SetText(PT.Get(key))
    ptFrame:SetAlpha(low and UnitHealthPercent("pet", true, curve) or 1)
    ptFrame:Show()
end

local ptEvents = CreateFrame("Frame")
ptEvents:SetScript("OnEvent", function(_, evt, unitToken)
    if evt == "PLAYER_MOUNT_DISPLAY_CHANGED" then
        local was = mounted
        mounted = IsMounted()
        if dismountTimer then
            dismountTimer:Cancel()
            dismountTimer = nil
        end
        if was and not mounted then
            dismountTimer = C_Timer.NewTimer(DISMOUNT_DELAY, function()
                dismountTimer = nil
                RefreshPetWarning()
            end)
        end
    elseif evt == "UNIT_AURA" or evt == "PLAYER_REGEN_ENABLED" then
        SacrificeActive()
    elseif evt == "UNIT_HEALTH" and unitToken ~= "pet" then
        return
    end
    RefreshPetWarning()
end)

local function ApplyPetTracker()
    ptEvents:UnregisterAllEvents()
    if not PT.Enabled() then
        if dismountTimer then
            dismountTimer:Cancel()
            dismountTimer = nil
        end
        if ptFrame then ptFrame:Hide() end
        return
    end
    BuildPetWarning()
    StylePetWarning()
    BuildFadeCurve()
    mounted = IsMounted()
    SacrificeActive()
    for _, event in ipairs(PT_EVENTS) do
        ptEvents:RegisterEvent(event)
    end
    ptEvents:RegisterUnitEvent("UNIT_PET", "player")
    ptEvents:RegisterUnitEvent("UNIT_HEALTH", "pet")
    ptEvents:RegisterUnitEvent("UNIT_MAXHEALTH", "pet")
    if CLASS == "WARLOCK" then ptEvents:RegisterUnitEvent("UNIT_AURA", "player") end
    if not CUI._unlockActive then PT.Place(ptFrame) end
    RefreshPetWarning()
end

PT.Start(ApplyPetTracker, {
    key = "CUI_PetTracker",
    label = "Pet Tracker",
    order = 747,
    frame = function(build)
        if build then
            BuildPetWarning()
            StylePetWarning()
            RefreshPetWarning()
        end
        return ptFrame
    end,
    size = function() return 220, PT.Get("size") + 16 end,
    noAnchorTarget = true,
    noSizeMatchTarget = true,
})

CUI._GroupWatch = {
    healer = { Get = HM.Get, Cfg = HM.Cfg, Apply = HMApply },
    pet = { Get = PT.Get, Cfg = PT.Cfg, Apply = ApplyPetTracker },
}
