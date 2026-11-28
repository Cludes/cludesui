if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
if not (CUI and CUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_PvPAuras.lua  (WoW Forever only)
--  PvP Auras: your target's short buffs, the crowd control on them and the
--  debuffs you pick, as large icons that keep working in combat; a second
--  panel for your focus (its name and class on top); the shields still
--  absorbing. Battleground Countdown: the start countdown, movable.
--  (The battleground scores move with Top Bar Event Text, QoL > Shifter.)
--
--  How: WoW Forever gives addons no aura data in combat or PvP. Blizzard's
--  aura container does: each panel is one container on its unit, with a
--  group per row (buffs, crowd control, debuffs) filtered by the engine:
--  buffs by their length (and Magic only), the other two by spell ID
--  (CludesUIForeverEssentials_PvPAurasData.lua, every rank of each ability).
--  The icons are the container's own buttons, dressed once as they are made
--  (initializeFrame). They are forbidden while auras are secret, so a look
--  change made then waits for the restriction to lift; so do settings
--  changes, which also wait out combat. The time left turns yellow and red
--  (and blinks) near the end through a colour curve the engine runs.
--  The absorb amount is never compared in Lua: it is the value of a clear
--  bar whose fill clips the text, so the text shows only while it is above 0.
-------------------------------------------------------------------------------
local _, module = ...

local SPELLS = module.PVP_AURA_SPELLS or { crowdControl = {}, otherCrowdControl = {}, debuffs = {} }
local CC_PREFIX, DEBUFF_PREFIX = "cc_", "debuff_"

local DEFAULTS = {
    enabled = false,
    size = 36,
    timer = true,
    count = true,
    warn = true,
    warnAt = 3,
    warnBlink = true,
    buffs = true,
    buffLength = 30,
    buffMagicOnly = false,
    buffMax = 6,
    absorb = true,
    cc = true,
    ccMax = 4,
    ccOther = true,
    debuffs = false,
    debuffMax = 4,
    debuffExtra = "",
    focus = false,
    focusName = true,
    focusBuffs = false,
    focusCC = true,
    focusDebuffs = false,
}
for _, entry in ipairs(SPELLS.crowdControl) do
    DEFAULTS[CC_PREFIX .. entry.key] = true
end
for _, entry in ipairs(SPELLS.debuffs) do
    DEFAULTS[DEBUFF_PREFIX .. entry.key] = false
end

local F = module.Feature("pvpAuras", DEFAULTS, { point = "CENTER", relPoint = "CENTER", x = 240, y = -60 })
-- The focus panel's own spot (only its pos is kept there).
local FF = module.Feature("pvpAurasFocus", {}, { point = "CENTER", relPoint = "CENTER", x = 240, y = -180 })
-- Battleground Countdown: on = moved; its holder's spot is Blizzard's own by default.
local FT = module.Feature("bgCountdown", { enabled = false }, { point = "TOP", relPoint = "TOP", x = 0, y = -155 })
local Get, Enabled = F.Get, F.Enabled

local ROWS = { "buffs", "cc", "debuffs" }
local MAX_KEY = { buffs = "buffMax", cc = "ccMax", debuffs = "debuffMax" }
local FILTER = { buffs = "HELPFUL", cc = "HARMFUL", debuffs = "HARMFUL" }
local MAX_ICONS = 10
local ICON_GAP, ROW_GAP, NAME_GAP = 3, 4, 6
local BORDER = 1
local CROP = 0.08
local TIME_SIZE, COUNT_SIZE, NAME_SIZE, ABSORB_SIZE = 0.34, 0.3, 0.42, 0.42
local MIN_TEXT = 8
local BLINK = 0.5
local WARN_SPAN = 2
local WHITE, YELLOW, RED, FAINT = { 1, 1, 1, 1 }, { 1, 0.82, 0, 1 }, { 1, 0.2, 0.2, 1 }, { 1, 0.2, 0.2, 0.3 }
local ABSORB_RGB = { 0.55, 0.82, 1 }
local ABSORB_ICON = "|TInterface\\Icons\\Spell_Holy_PowerWordShield:0:0:0:0:64:64:5:59:5:59|t "
local CLASS_ICONS = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
local COUNT_W, COUNT_H, COUNT_TOP = 206, 26, 155

local DISPLAYS = {
    {
        unit = "target",
        feat = F,
        frameName = "CludesUIPvPAuras",
        key = "CUI_PvPAuras",
        label = "PvP Auras",
        order = 758,
        changed = "PLAYER_TARGET_CHANGED",
        rows = { buffs = "buffs", cc = "cc", debuffs = "debuffs" },
    },
    {
        unit = "focus",
        feat = FF,
        frameName = "CludesUIPvPAurasFocus",
        key = "CUI_PvPAurasFocus",
        label = "PvP Auras: Focus",
        order = 759,
        changed = "PLAYER_FOCUS_CHANGED",
        switch = "focus",
        nameKey = "focusName",
        rows = { buffs = "focusBuffs", cc = "focusCC", debuffs = "focusDebuffs" },
    },
}

local AK = CUI.AuraKit
local buttons, regions = {}, setmetatable({}, { __mode = "k" })
local pending, restylePending = false, false
local timerOpts, timerSig
local eventFrame = CreateFrame("Frame")

local function AurasRestricted() return InCombatLockdown() or (AK and AK.AurasRestricted()) or false end
local function Secret(v) return issecretvalue and issecretvalue(v) end
local function AuraFont() return CUI.GetFontPath("essentials") end
local function FontSizeFor(ratio) return math.max(MIN_TEXT, math.floor(Get("size") * ratio + 0.5)) end
local function DisplayOn(d) return Enabled() and (d.switch == nil or Get(d.switch) == true) end

-------------------------------------------------------------------------------
--  Filters
-------------------------------------------------------------------------------

-- The ids of every picked entry; n = how many ids.
local function IsPicked(entries, prefix, into)
    local n = 0
    for _, entry in ipairs(entries) do
        if Get(prefix .. entry.key) then
            for ident in pairs(entry.ids) do
                into[ident] = true
                n = n + 1
            end
        end
    end
    return n
end

-- The candidate filters per row, and per row whether it has anything to
-- show: an empty spell list is never handed to the engine (it would read as
-- no filter at all), its row is switched off instead.
local function AuraFilters()
    local cc, debuffs = {}, {}
    local nCC = IsPicked(SPELLS.crowdControl, CC_PREFIX, cc)
    if Get("ccOther") then
        for ident in pairs(SPELLS.otherCrowdControl) do
            cc[ident] = true
            nCC = nCC + 1
        end
    end
    local nDebuffs = IsPicked(SPELLS.debuffs, DEBUFF_PREFIX, debuffs)
    for ident in tostring(Get("debuffExtra") or ""):gmatch("%d+") do
        debuffs[tonumber(ident)] = true
        nDebuffs = nDebuffs + 1
    end
    local buffs = { maxDuration = Get("buffLength") }
    if Get("buffMagicOnly") then buffs.includeDispelTypes = { Magic = true } end
    return { buffs = buffs, cc = { includeSpellIDs = cc }, debuffs = { includeSpellIDs = debuffs } },
        { buffs = true, cc = nCC > 0, debuffs = nDebuffs > 0 }
end

-------------------------------------------------------------------------------
--  Icons
-------------------------------------------------------------------------------

local function Color(c) return CreateColor(c[1], c[2], c[3], c[4]) end

-- Warn Before It Ends: white, yellow under twice Red Under, red under it,
-- blinking red with Blink When Red.
local function WarningCurve(warnAt, blink)
    local curve = C_CurveUtil.CreateColorCurve()
    curve:SetType(Enum.LuaCurveType.Step)
    curve:AddPoint(0, Color(RED))
    if blink then
        local at, faint = BLINK, true
        while at < warnAt do
            curve:AddPoint(at, Color(faint and FAINT or RED))
            at, faint = at + BLINK, not faint
        end
    end
    curve:AddPoint(warnAt, Color(YELLOW))
    curve:AddPoint(warnAt * WARN_SPAN, Color(WHITE))
    return curve
end

-- The time-left binding options, rebuilt only when the warn settings change.
local function CountdownOptions()
    local warn = Get("warn") == true
    local sig = (warn and "1" or "0") .. Get("warnAt") .. (Get("warnBlink") and "1" or "0")
    if sig ~= timerSig then
        timerSig = sig
        local curve = warn and C_CurveUtil and C_CurveUtil.CreateColorCurve and WarningCurve(Get("warnAt"), Get("warnBlink") == true)
        timerOpts = AK.BuildDurationTextOpts(AK.GetDurationFormatter(false), curve or nil)
    end
    return timerOpts, sig
end

local function ApplyFonts(r)
    r.time:SetFont(AuraFont(), FontSizeFor(TIME_SIZE), "OUTLINE")
    r.count:SetFont(AuraFont(), FontSizeFor(COUNT_SIZE), "OUTLINE")
end

-- Size, fonts, which texts show and the time-left binding. Only out of the
-- restriction (the buttons are forbidden while auras are secret).
local function StyleAuraButton(button)
    local r = regions[button]
    if not r then return end
    local size = Get("size")
    button:SetSize(size, size)
    ApplyFonts(r)
    r.time:SetShown(Get("timer") == true)
    r.count:SetShown(Get("count") == true)
    if Get("timer") then
        local opts, sig = CountdownOptions()
        if r.timerSig ~= sig then
            r.timerSig = sig
            -- A fresh copy: the safe setter strips a refused colour off what it is given.
            local copy = {}
            for k, v in pairs(opts) do
                copy[k] = v
            end
            AK.SetDurationTextSafe(button, r.time, copy)
        end
    end
end

-- initializeFrame: every region made and given its font before the button
-- registers any of them (each registration paints through them at once).
local function SetupAuraButton(button)
    local ground = button:CreateTexture(nil, "BACKGROUND")
    ground:SetAllPoints()
    ground:SetColorTexture(0, 0, 0, 1)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", BORDER, -BORDER)
    icon:SetPoint("BOTTOMRIGHT", -BORDER, BORDER)
    icon:SetTexCoord(CROP, 1 - CROP, CROP, 1 - CROP)
    local swipe = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    swipe:SetAllPoints(icon)
    swipe:SetDrawEdge(false)
    swipe:SetHideCountdownNumbers(true)
    swipe:SetReverse(true)
    local textHost = CreateFrame("Frame", nil, button)
    textHost:SetAllPoints()
    textHost:SetFrameLevel(swipe:GetFrameLevel() + 1)
    local timeText = textHost:CreateFontString(nil, "OVERLAY")
    timeText:SetPoint("BOTTOM", 0, 2)
    local countText = textHost:CreateFontString(nil, "OVERLAY")
    countText:SetPoint("TOPRIGHT", -2, -2)
    local r = { time = timeText, count = countText }
    regions[button] = r
    ApplyFonts(r)
    button:SetIcon(icon)
    button:SetDurationCooldown(swipe)
    button:SetApplicationCount(countText)
    buttons[#buttons + 1] = button
    StyleAuraButton(button)
end

local function RestyleButtons()
    if AurasRestricted() then
        restylePending = true
        return
    end
    restylePending = false
    for i = 1, #buttons do
        StyleAuraButton(buttons[i])
    end
end

-------------------------------------------------------------------------------
--  Panels
-------------------------------------------------------------------------------

-- The absorb: a clear bar whose value is the amount; its text sits in a clip
-- on the fill, so it shows only while the fill has width.
local function CreateAbsorbBar(holder)
    local bar = CreateFrame("StatusBar", nil, holder)
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    bar:SetStatusBarColor(0, 0, 0, 0)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    local clip = CreateFrame("Frame", nil, bar)
    clip:SetClipsChildren(true)
    clip:SetPoint("TOPLEFT", bar:GetStatusBarTexture(), "TOPLEFT")
    clip:SetPoint("BOTTOMRIGHT", bar:GetStatusBarTexture(), "BOTTOMRIGHT")
    bar.text = clip:CreateFontString(nil, "OVERLAY")
    bar.text:SetPoint("RIGHT", bar, "RIGHT")
    bar.text:SetJustifyH("RIGHT")
    return bar
end

local function CreateAuraHeader(holder)
    local header = CreateFrame("Frame", nil, holder)
    header.class = header:CreateTexture(nil, "ARTWORK")
    header.class:SetTexture(CLASS_ICONS)
    header.class:SetPoint("LEFT")
    header.name = header:CreateFontString(nil, "OVERLAY")
    header.name:SetPoint("LEFT", header.class, "RIGHT", NAME_GAP, 0)
    header.name:SetJustifyH("LEFT")
    header.name:SetWordWrap(false)
    return header
end

-- Each row on its own line. The icons' size is their own (StyleButton), so a
-- size change never touches the container's layout.
local ROW_LAYOUT = { elementSpacing = ICON_GAP, lineSpacing = ROW_GAP, groupLineSpacing = ROW_GAP, forceNewLine = true }

-- The panel's frame (cheap, any time) and its container (out of combat and
-- restriction only; false = not yet).
local function IconFrame(d)
    if d.holder then return d.holder end
    local holder = CreateFrame("Frame", d.frameName, UIParent)
    holder:SetSize(Get("size"), Get("size"))
    holder:Hide()
    d.holder = holder
    d.absorb = CreateAbsorbBar(holder)
    if d.nameKey then d.header = CreateAuraHeader(holder) end
    return holder
end

local function BuildAuraFrame(d)
    if d.container then return true end
    if d.failed or AurasRestricted() then return false end
    if C_AddOns and not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
        pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
    end
    local holder = IconFrame(d)
    local filters, has = AuraFilters()
    local success, err = pcall(function()
        local c = CreateFrame("AuraContainer", nil, holder, "CustomAuraContainerTemplate")
        c:SetPoint("TOPLEFT")
        c:SetSize(1, 1)
        for _, row in ipairs(ROWS) do
            c:AddAuraGroup(row, FILTER[row], {
                maxFrameCount = MAX_ICONS,
                sortMethod = AuraContainerSortMethod and AuraContainerSortMethod.Default or 0,
                initializeFrame = SetupAuraButton,
                layout = ROW_LAYOUT,
                candidateFilters = has[row] and filters[row] or nil,
            })
        end
        c:SetUnit(d.unit)
        d.container = c
    end)
    if not success then
        d.failed = true
        CUI.Print("|cffff4040PvP Auras could not be set up:|r " .. tostring(err))
        return false
    end
    return true
end

-- Rows on, caps and filters, from the settings.
local function LayoutRows(d)
    local c = d.container
    local filters, has = AuraFilters()
    for _, row in ipairs(ROWS) do
        local on = Get(d.rows[row]) == true and has[row]
        if on then c:SetAuraGroupCandidateFilters(row, filters[row]) end
        c:SetAuraGroupMaxFrameCount(row, on and Get(MAX_KEY[row]) or 0)
        if c.SetAuraGroupEnabled then c:SetAuraGroupEnabled(row, on) end
    end
end

-- The panel's size: the rows that can show something (ticked, with spells to
-- match), as wide as the widest cap.
local function PanelDimensions(d)
    local _, has = AuraFilters()
    local size, rows, wide = Get("size"), 0, 1
    for _, row in ipairs(ROWS) do
        if Get(d.rows[row]) and has[row] then rows, wide = rows + 1, math.max(wide, Get(MAX_KEY[row])) end
    end
    rows = math.max(rows, 1)
    return wide * size + (wide - 1) * ICON_GAP, rows * size + (rows - 1) * ROW_GAP
end

local function LayoutPanel(d)
    local size = Get("size")
    d.holder:SetSize(PanelDimensions(d))
    local absorbSize = FontSizeFor(ABSORB_SIZE)
    d.absorb.text:SetFont(AuraFont(), absorbSize, "OUTLINE")
    d.absorb.text:SetTextColor(ABSORB_RGB[1], ABSORB_RGB[2], ABSORB_RGB[3])
    d.absorb:SetSize(size * 2, absorbSize + 4)
    d.absorb:ClearAllPoints()
    d.absorb:SetPoint("RIGHT", d.holder, "TOPLEFT", -NAME_GAP, -size / 2)
    if d.header then
        local nameSize = FontSizeFor(NAME_SIZE)
        d.header.name:SetFont(AuraFont(), nameSize, "OUTLINE")
        d.header.class:SetSize(nameSize + 4, nameSize + 4)
        d.header:SetSize(d.holder:GetWidth(), nameSize + 4)
        d.header:ClearAllPoints()
        d.header:SetPoint("BOTTOMLEFT", d.holder, "TOPLEFT", 0, ROW_GAP)
    end
end

local function RefreshAbsorb(d)
    local bar = d.absorb
    if not (bar and bar:IsShown()) then return end
    if not UnitExists(d.unit) then
        bar:SetValue(0)
        return
    end
    local amount = UnitGetTotalAbsorbs(d.unit)
    bar:SetValue(amount or 0)
    bar.text:SetFormattedText(ABSORB_ICON .. "%d", amount or 0)
end

-- The focus panel's name, tinted by class, with the class icon.
local function RefreshHeader(d)
    local header = d.header
    if not header then return end
    local shown = Get(d.nameKey) == true and UnitExists(d.unit)
    header:SetShown(shown and true or false)
    if not shown then return end
    header.name:SetText(UnitName(d.unit))
    local _, classFile = UnitClass(d.unit)
    local plain = classFile and not Secret(classFile)
    local color = plain and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    local coords = plain and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile]
    if color then
        header.name:SetTextColor(color.r, color.g, color.b)
    else
        header.name:SetTextColor(1, 1, 1)
    end
    header.class:SetShown(coords ~= nil)
    if coords then header.class:SetTexCoord(coords[1], coords[2], coords[3], coords[4]) end
end

-- The focus panel steps aside (alpha) while the focus is your target: the
-- target panel already shows them.
local function FocusIsTarget()
    if not (UnitExists("focus") and UnitExists("target")) then return false end
    local same = UnitIsUnit("focus", "target")
    return not Secret(same) and same == true
end

local function RefreshFocusFade()
    local d = DISPLAYS[2]
    if d.holder then d.holder:SetAlpha((FocusIsTarget() and not CUI._unlockActive) and 0 or 1) end
end

local function HidePanel(d)
    if d.container then d.container:SetEnabled(false) end
    if d.holder then d.holder:Hide() end
end

local function ShowPanel(d)
    IconFrame(d)
    if not BuildAuraFrame(d) then return false end
    LayoutRows(d)
    LayoutPanel(d)
    if not CUI._unlockActive then d.feat.Place(d.holder) end
    d.container:SetEnabled(true)
    d.holder:Show()
    d.absorb:SetShown(Get("absorb") == true)
    d.container:UpdateAllAuras()
    RefreshAbsorb(d)
    RefreshHeader(d)
    return true
end

-------------------------------------------------------------------------------
--  Battleground Countdown
-------------------------------------------------------------------------------

local countHolder, countHung

local function CountFrame()
    if not countHolder then
        countHolder = CreateFrame("Frame", "CludesUIBGCountdown", UIParent)
        countHolder:SetSize(COUNT_W, COUNT_H)
    end
    return countHolder
end

-- Blizzard's tracker spans the screen and stacks its bars from 155 below
-- its top, its big digits on its centre: on, it keeps that size and hangs
-- from the holder; off, it goes back over the screen.
local function ConfigureCountdown()
    local tracker = _G.TimerTracker
    if not tracker then return end
    if FT.Enabled() then
        local holder = CountFrame()
        if not CUI._unlockActive then FT.Place(holder) end
        tracker:ClearAllPoints()
        tracker:SetSize(UIParent:GetWidth(), UIParent:GetHeight())
        tracker:SetPoint("TOP", holder, "TOP", 0, COUNT_TOP)
        countHung = true
    elseif countHung then
        countHung = false
        tracker:ClearAllPoints()
        tracker:SetAllPoints(UIParent)
    end
end

-------------------------------------------------------------------------------
--  Apply and events
-------------------------------------------------------------------------------

local function Apply()
    ConfigureCountdown()
    if FT.Enabled() then
        eventFrame:RegisterEvent("UI_SCALE_CHANGED")
        eventFrame:RegisterEvent("DISPLAY_SIZE_CHANGED")
    else
        eventFrame:UnregisterEvent("UI_SCALE_CHANGED")
        eventFrame:UnregisterEvent("DISPLAY_SIZE_CHANGED")
    end
    if not Enabled() and not (DISPLAYS[1].holder or DISPLAYS[2].holder) then return end
    if AurasRestricted() then
        pending = true
        eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    pending = false
    for _, d in ipairs(DISPLAYS) do
        eventFrame:UnregisterEvent(d.changed)
    end
    eventFrame:UnregisterEvent("UNIT_ABSORB_AMOUNT_CHANGED")
    local absorbUnits = {}
    for _, d in ipairs(DISPLAYS) do
        if DisplayOn(d) and ShowPanel(d) then
            eventFrame:RegisterEvent(d.changed)
            if Get("absorb") then absorbUnits[#absorbUnits + 1] = d.unit end
        else
            HidePanel(d)
        end
    end
    if absorbUnits[1] then
        eventFrame:RegisterUnitEvent("UNIT_ABSORB_AMOUNT_CHANGED", absorbUnits[1], absorbUnits[2])
    end
    RestyleButtons()
    RefreshFocusFade()
end

eventFrame:SetScript("OnEvent", function(_, evt, unit)
    if evt == "UNIT_ABSORB_AMOUNT_CHANGED" then
        for _, d in ipairs(DISPLAYS) do
            if d.unit == unit then RefreshAbsorb(d) end
        end
    elseif evt == "PLAYER_TARGET_CHANGED" or evt == "PLAYER_FOCUS_CHANGED" then
        for _, d in ipairs(DISPLAYS) do
            if evt == d.changed and d.container then
                d.container:UpdateAllAuras()
                RefreshAbsorb(d)
                RefreshHeader(d)
            end
        end
        RefreshFocusFade()
    elseif evt == "PLAYER_REGEN_ENABLED" then
        if pending then Apply() end
        if restylePending then RestyleButtons() end
        -- A restricted answer can hold for the rest of the frame it was read
        -- in: what is still waiting tries once more a moment later.
        if pending or restylePending then
            C_Timer.After(0.2, function()
                if pending then Apply() end
                if restylePending then RestyleButtons() end
            end)
        end
    else
        -- UI_SCALE_CHANGED / DISPLAY_SIZE_CHANGED: the tracker spans the screen.
        ConfigureCountdown()
    end
end)

if AK and AK.OnRestrictionLift then
    AK.OnRestrictionLift(function()
        if pending then Apply() end
        if restylePending then RestyleButtons() end
    end)
end

CUI._PvPAuras = {
    Get = Get,
    Cfg = F.Cfg,
    Apply = Apply,
    Spells = SPELLS,
    CC_PREFIX = CC_PREFIX,
    DEBUFF_PREFIX = DEBUFF_PREFIX,
    CountdownGet = FT.Get,
    CountdownCfg = FT.Cfg,
}

for _, d in ipairs(DISPLAYS) do
    d.feat.Start(d == DISPLAYS[1] and Apply or function() end, {
        key = d.key,
        label = d.label,
        order = d.order,
        shown = function() return DisplayOn(d) end,
        frame = function(build)
            if build then IconFrame(d) end
            return d.holder
        end,
        size = function() return PanelDimensions(d) end,
        noAnchorTarget = true,
        noSizeMatchTarget = true,
    })
end
FT.Start(function() end, {
    key = "CUI_BGCountdown",
    label = "Battleground Countdown",
    order = 760,
    frame = function(build)
        if build then CountFrame() end
        return countHolder
    end,
    size = function() return COUNT_W, COUNT_H end,
    noAnchorTarget = true,
    noSizeMatchTarget = true,
})
