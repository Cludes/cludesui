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

local function Typeface() return CUI.GetFontPath("essentials") end
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
local DRINK_GLYPH = "Interface\\Icons\\INV_Drink_07"
local HEALER_CALLINGS = { PRIEST = true, PALADIN = true, DRUID = true, SHAMAN = true }
local LOWER, OUT = 0.6, 0.3
local LINE_PAD, PAD, GLYPH_SPACING = 4, 6, 4
local DEAD, OFFLINE, UNKNOWN = "Dead", "Offline", "--"
local NO_TIER = math.huge
local UNIT_EVENTS =
    { "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER", "UNIT_CONNECTION", "UNIT_AURA" }

local hmWindow, drinkTitle, shareRamp
local lineRoster, members, roster, tracked, tier, units, watchers = {}, {}, {}, {}, {}, {}, {}
local RAID, PARTY = {}, {}
for catalog = 1, 40 do
    RAID[catalog] = "raid" .. catalog
end
for catalog = 1, 4 do
    PARTY[catalog] = "party" .. catalog
end

local function HMHere()
    if not IsInGroup() then return false end
    if HM.Get("where") == "group" then return true end
    local _, kind = IsInInstance()
    return kind == "party" or kind == "raid"
end

local function IsHealer(unitToken, calling)
    local role = UnitGroupRolesAssigned(unitToken)
    if Secret(role) then role = nil end
    if role == "HEALER" then return true end
    if role == "TANK" or role == "DAMAGER" then return false end
    return HEALER_CALLINGS[calling] == true
end

local function Units()
    wipe(units)
    if HM.Get("showSelf") then units[1] = "player" end
    if IsInRaid() then
        for catalog = 1, math.min(GetNumGroupMembers(), 40) do
            local me = UnitIsUnit(RAID[catalog], "player")
            if not Secret(me) and not me then units[#units + 1] = RAID[catalog] end
        end
    else
        for catalog = 1, math.min(GetNumSubgroupMembers(), 4) do
            units[#units + 1] = PARTY[catalog]
        end
    end
    return units
end

local function Roster()
    wipe(roster)
    wipe(tracked)
    for _, unitToken in ipairs(Units()) do
        local title, unitId = UnitName(unitToken), UnitGUID(unitToken)
        local _, calling = UnitClass(unitToken)
        if
            title
            and unitId
            and not (Secret(title) or Secret(unitId) or Secret(calling))
            and IsHealer(unitToken, calling)
        then
            local num = #roster + 1
            local m = members[num] or {}
            members[num] = m
            if m.guid ~= unitId then
                m.pct, m.drinking = nil, false
            end
            m.unit, m.name, m.class, m.guid = unitToken, title, calling, unitId
            roster[num], tracked[unitToken] = m, m
        end
    end
end

local function CanLoadDrink()
    if not HM.Get("drinking") or AurasSecret() then return false end
    drinkTitle = drinkTitle or C_Spell.GetSpellName(DRINK_SPELL)
    return drinkTitle ~= nil
end

local function Drinking(m)
    if not (CanLoadDrink() and C_UnitAuras.GetAuraDataBySpellName) then return end
    local aura = C_UnitAuras.GetAuraDataBySpellName(m.unit, drinkTitle, "HELPFUL")
    m.drinking = aura ~= nil
    m.drinkID = aura and aura.auraInstanceID or nil
end

-- True when the drinking state changed (an aura update for this unit).
local function DrinkAltered(m, details)
    if not CanLoadDrink() then return false end
    local was = m.drinking
    if not details or details.isFullUpdate then
        Drinking(m)
        return m.drinking ~= was
    end
    for _, a in ipairs(details.addedAuras or {}) do
        if not Secret(a.name) and a.name == drinkTitle then
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

local function Load(m)
    local online, dead = UnitIsConnected(m.unit), UnitIsDeadOrGhost(m.unit)
    if Secret(online) then online = true end
    if Secret(dead) then dead = false end
    m.state = (not online and OFFLINE) or (dead and DEAD) or nil
    local current, top = UnitPower(m.unit, MANA), UnitPowerMax(m.unit, MANA)
    m.secret = (Secret(current) or Secret(top)) == true
    if not m.secret and top > 0 then m.pct = current / top end
end

local function Less(a, b)
    if (a.state ~= nil) ~= (b.state ~= nil) then return b.state ~= nil end
    local pa, pb = a.pct or NO_TIER, b.pct or NO_TIER
    if pa ~= pb then return pa < pb end
    if a.name ~= b.name then return a.name < b.name end
    return a.guid < b.guid
end

-- While any mana is secret, keep the last order (it cannot be compared).
local function Kept(a, b)
    local ra, rb = tier[a.guid] or NO_TIER, tier[b.guid] or NO_TIER
    if ra ~= rb then return ra < rb end
    return a.guid < b.guid
end

local function Order()
    for catalog = 1, #roster do
        if roster[catalog].secret then
            table.sort(roster, Kept)
            return
        end
    end
    table.sort(roster, Less)
    wipe(tier)
    for catalog = 1, #roster do
        tier[roster[catalog].guid] = catalog
    end
end

local function SecretShare(typefaceStr, unitToken)
    if not (UnitPowerPercent and C_CurveUtil) then return false end
    if not shareRamp then
        shareRamp = C_CurveUtil.CreateCurve()
        shareRamp:SetType(Enum.LuaCurveType.Linear)
        shareRamp:AddPoint(0, 0)
        shareRamp:AddPoint(1, 100)
    end
    typefaceStr:SetFormattedText("%.1f%%", UnitPowerPercent(unitToken, MANA, false, shareRamp))
    return true
end

local SAMPLE = {
    { name = "Priest", class = "PRIEST", guid = "1", pct = 0.18 },
    { name = "Druid", class = "DRUID", guid = "2", pct = 0.47, drinking = true },
    { name = "Shaman", class = "SHAMAN", guid = "3", pct = 0.83 },
    { name = "Paladin", class = "PALADIN", guid = "4", state = DEAD },
}

local function Line(catalog)
    local row = lineRoster[catalog]
    if row then return row end
    row = CreateFrame("Frame", nil, hmWindow)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetTexture(DRINK_GLYPH)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.icon:SetPoint("LEFT", 0, -1)
    row.pct = row:CreateFontString(nil, "OVERLAY")
    row.pct:SetPoint("RIGHT")
    row.pct:SetJustifyH("RIGHT")
    row.name = row:CreateFontString(nil, "OVERLAY")
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    lineRoster[catalog] = row
    return row
end

local function RenderLines(items)
    local dims, drinks = HM.Get("size"), HM.Get("drinking")
    local step = dims + LINE_PAD
    hmWindow:SetSize(HM.Get("width"), #items * step + 2 * PAD)
    for catalog, m in ipairs(items) do
        local region = Line(catalog)
        region:ClearAllPoints()
        region:SetPoint("TOPLEFT", PAD, -PAD - (catalog - 1) * step)
        region:SetPoint("TOPRIGHT", -PAD, -PAD - (catalog - 1) * step)
        region:SetHeight(step)
        CUI.Kit.Font(region.name, dims, "essentials")
        CUI.Kit.Font(region.pct, dims, "essentials")
        region.icon:SetSize(dims, dims)
        region.name:ClearAllPoints()
        region.name:SetPoint("LEFT", drinks and (dims + GLYPH_SPACING) or 0, 0)
        region.name:SetPoint("RIGHT", region.pct, "LEFT", -8, 0)
        region.name:SetText(m.name)
        local tint = RAID_CLASS_COLORS[m.class]
        if tint then
            region.name:SetTextColor(tint.r, tint.g, tint.b)
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
            if not SecretShare(region.pct, m.unit) then region.pct:SetText(UNKNOWN) end
        elseif m.pct then
            region.pct:SetText(("%.1f%%"):format(math.floor(m.pct * 1000 + 0.5) / 10))
            if m.pct < OUT then
                region.pct:SetTextColor(1, 0.3, 0.3)
            elseif m.pct < LOWER then
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
    for catalog = #items + 1, #lineRoster do
        lineRoster[catalog]:Hide()
    end
end

local function HMRedraw()
    if not hmWindow then return end
    if CUI._unlockActive and HM.Enabled() then
        RenderLines(SAMPLE)
        hmWindow:Show()
        return
    end
    if not (HM.Enabled() and HMHere()) or #roster == 0 then
        hmWindow:Hide()
        return
    end
    for catalog = 1, #roster do
        Load(roster[catalog])
    end
    Order()
    RenderLines(roster)
    hmWindow:Show()
end

local hmPending
local function HMSoon()
    if hmPending then return end
    hmPending = true
    C_Timer.After(0.25, function()
        hmPending = false
        HMRedraw()
    end)
end

local function OnUnitEvent(wid, evt, _, arg)
    if evt == "UNIT_POWER_UPDATE" and (Secret(arg) or arg ~= MANA_TOKEN) then return end
    local m = tracked[wid.unit]
    if not m then return end
    if evt == "UNIT_AURA" and not DrinkAltered(m, arg) then return end
    HMSoon()
end

local function Watch()
    for catalog, m in ipairs(roster) do
        local wid = watchers[catalog]
        if not wid then
            wid = CreateFrame("Frame")
            wid:SetScript("OnEvent", OnUnitEvent)
            watchers[catalog] = wid
        end
        if wid.unit ~= m.unit then
            wid:UnregisterAllEvents()
            wid.unit = m.unit
            for _, event in ipairs(UNIT_EVENTS) do
                wid:RegisterUnitEvent(event, m.unit)
            end
        end
    end
    for catalog = #roster + 1, #watchers do
        watchers[catalog]:UnregisterAllEvents()
        watchers[catalog].unit = nil
    end
end

local hmEvents = CreateFrame("Frame")
local HMUse
local rosterPending
hmEvents:SetScript("OnEvent", function(_, evt)
    if evt == "PLAYER_ENTERING_WORLD" then return HMUse() end
    if rosterPending then return end
    rosterPending = true
    C_Timer.After(0.25, function()
        rosterPending = false
        HMUse()
    end)
end)

HMUse = function()
    if not HM.Enabled() then
        hmEvents:UnregisterAllEvents()
        wipe(roster)
        wipe(tracked)
        Watch()
        if hmWindow then hmWindow:Hide() end
        return
    end
    if not hmWindow then
        hmWindow = CreateFrame("Frame", "CludesUIHealerMana", UIParent)
        CUI.Kit.Panel(hmWindow, 0.75)
    end
    for _, event in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED", "PLAYER_ENTERING_WORLD" }) do
        hmEvents:RegisterEvent(event)
    end
    wipe(roster)
    wipe(tracked)
    if HMHere() then
        Roster()
        for catalog = 1, #roster do
            Drinking(roster[catalog])
        end
    end
    Watch()
    if not CUI._unlockActive then HM.Place(hmWindow) end
    HMRedraw()
end

HM.Start(HMUse, {
    key = "CUI_HealerMana",
    label = "Healer Mana",
    order = 746,
    frame = function(make)
        if make and not hmWindow then HMUse() end
        if make and hmWindow then HMRedraw() end
        return hmWindow
    end,
    size = function() return HM.Get("width"), #SAMPLE * (HM.Get("size") + LINE_PAD) + 2 * PAD end,
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
local PET_GLYPH = 132161
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

local ptWindow, ramp, mounted, dismountClock, sacrificed
local _, CALLING = UnitClass("player")

local function Learned(ident)
    return C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(ident)
end

local function PTMake()
    if ptWindow then return ptWindow end
    ptWindow = CreateFrame("Frame", "CludesUIPetTracker", UIParent)
    ptWindow.icon = ptWindow:CreateTexture(nil, "ARTWORK")
    ptWindow.icon:SetTexture(PET_GLYPH)
    ptWindow.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    ptWindow.text = ptWindow:CreateFontString(nil, "OVERLAY")
    ptWindow.text:SetTextColor(1, 0.2, 0.2)
    ptWindow:Hide()
    return ptWindow
end

local function Reskin()
    local dims = PT.Get("size")
    CUI.Kit.Font(ptWindow.text, dims, "essentials")
    ptWindow.text:ClearAllPoints()
    if PT.Get("showIcon") then
        ptWindow.icon:SetSize(dims + 12, dims + 12)
        ptWindow.icon:SetPoint("LEFT")
        ptWindow.icon:Show()
        ptWindow.text:SetPoint("LEFT", ptWindow.icon, "RIGHT", 8, 0)
    else
        ptWindow.icon:Hide()
        ptWindow.text:SetPoint("CENTER")
    end
    ptWindow:SetSize(220, dims + 16)
end

-- The warning fades out above the low-health line: 1 below it, 0 above.
local function MakeRamp()
    local below = PT.Get("lowBelow") / 100
    ramp = ramp or C_CurveUtil.CreateCurve()
    ramp:SetType(Enum.LuaCurveType.Step)
    ramp:ClearPoints()
    ramp:AddPoint(0, 1)
    ramp:AddPoint(below - 0.001, 1)
    ramp:AddPoint(below, 0)
    ramp:AddPoint(1, 0)
end

local function ShouldHavePet()
    if CALLING == "HUNTER" then return Learned(CALL_PET) end
    if CALLING == "WARLOCK" then return Learned(SUMMON_IMP) and not sacrificed end
    return false
end

local function TestSacrifice()
    if CALLING ~= "WARLOCK" or AurasSecret() then return end
    sacrificed = false
    for _, ident in ipairs(SACRIFICE_BUFFS) do
        if C_UnitAuras.GetPlayerAuraBySpellID(ident) then
            sacrificed = true
            return
        end
    end
end

local function IsPassive()
    if not PetHasActionBar() then return false end
    for catalog = 1, NUM_PET_ACTION_SLOTS do
        local title, _, _, isActive = GetPetActionInfo(catalog)
        if title == "PET_MODE_PASSIVE" then return isActive == true end
    end
    return false
end

local function Warning()
    if UnitIsDeadOrGhost("player") or UnitOnTaxi("player") then return end
    if PT.Get("hideMounted") and (mounted or dismountClock) then return end
    if PT.Get("combatOnly") and not UnitAffectingCombat("player") then return end
    if PT.Get("instanceOnly") and not IsInInstance() then return end
    if not ShouldHavePet() then return end
    if not UnitExists("pet") then
        if CALLING == "HUNTER" and (Learned(LONE_WOLF) or Learned(LONE_WOLF_TAUGHT)) then return end
        return "missingText"
    end
    if PT.Get("passive") and IsPassive() then return "passiveText" end
    if PT.Get("lowHealth") and not UnitIsDeadOrGhost("pet") then return "lowText", true end
end

local function PTRefresh()
    if not ptWindow then return end
    if CUI._unlockActive and PT.Enabled() then
        ptWindow.text:SetText(PT.Get("missingText"))
        ptWindow:SetAlpha(1)
        ptWindow:Show()
        return
    end
    local id, lower = Warning()
    if not id then
        ptWindow:Hide()
        return
    end
    ptWindow.text:SetText(PT.Get(id))
    ptWindow:SetAlpha(lower and UnitHealthPercent("pet", true, ramp) or 1)
    ptWindow:Show()
end

local ptEvents = CreateFrame("Frame")
ptEvents:SetScript("OnEvent", function(_, evt, unitToken)
    if evt == "PLAYER_MOUNT_DISPLAY_CHANGED" then
        local was = mounted
        mounted = IsMounted()
        if dismountClock then
            dismountClock:Cancel()
            dismountClock = nil
        end
        if was and not mounted then
            dismountClock = C_Timer.NewTimer(DISMOUNT_DELAY, function()
                dismountClock = nil
                PTRefresh()
            end)
        end
    elseif evt == "UNIT_AURA" or evt == "PLAYER_REGEN_ENABLED" then
        TestSacrifice()
    elseif evt == "UNIT_HEALTH" and unitToken ~= "pet" then
        return
    end
    PTRefresh()
end)

local function PTUse()
    ptEvents:UnregisterAllEvents()
    if not PT.Enabled() then
        if dismountClock then
            dismountClock:Cancel()
            dismountClock = nil
        end
        if ptWindow then ptWindow:Hide() end
        return
    end
    PTMake()
    Reskin()
    MakeRamp()
    mounted = IsMounted()
    TestSacrifice()
    for _, event in ipairs(PT_EVENTS) do
        ptEvents:RegisterEvent(event)
    end
    ptEvents:RegisterUnitEvent("UNIT_PET", "player")
    ptEvents:RegisterUnitEvent("UNIT_HEALTH", "pet")
    ptEvents:RegisterUnitEvent("UNIT_MAXHEALTH", "pet")
    if CALLING == "WARLOCK" then ptEvents:RegisterUnitEvent("UNIT_AURA", "player") end
    if not CUI._unlockActive then PT.Place(ptWindow) end
    PTRefresh()
end

PT.Start(PTUse, {
    key = "CUI_PetTracker",
    label = "Pet Tracker",
    order = 747,
    frame = function(make)
        if make then
            PTMake()
            Reskin()
            PTRefresh()
        end
        return ptWindow
    end,
    size = function() return 220, PT.Get("size") + 16 end,
    noAnchorTarget = true,
    noSizeMatchTarget = true,
})

CUI._GroupWatch = {
    healer = { Get = HM.Get, Cfg = HM.Cfg, Apply = HMUse },
    pet = { Get = PT.Get, Cfg = PT.Cfg, Apply = PTUse },
}
