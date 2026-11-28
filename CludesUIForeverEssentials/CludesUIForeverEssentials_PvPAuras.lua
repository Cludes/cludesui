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

local ABILITIES = module.PVP_AURA_SPELLS or { crowdControl = {}, otherCrowdControl = {}, debuffs = {} }
local CC_LEAD, HARM_LEAD = "cc_", "debuff_"

local PRESETS = {
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
for _, item in ipairs(ABILITIES.crowdControl) do
    PRESETS[CC_LEAD .. item.key] = true
end
for _, item in ipairs(ABILITIES.debuffs) do
    PRESETS[HARM_LEAD .. item.key] = false
end

local F = module.Feature("pvpAuras", PRESETS, { point = "CENTER", relPoint = "CENTER", x = 240, y = -60 })
-- The focus panel's own spot (only its pos is kept there).
local FF = module.Feature("pvpAurasFocus", {}, { point = "CENTER", relPoint = "CENTER", x = 240, y = -180 })
-- Battleground Countdown: on = moved; its holder's spot is Blizzard's own by default.
local FT = module.Feature("bgCountdown", { enabled = false }, { point = "TOP", relPoint = "TOP", x = 0, y = -155 })
local Get, Enabled = F.Get, F.Enabled

local LINES = { "buffs", "cc", "debuffs" }
local TOP_ID = { buffs = "buffMax", cc = "ccMax", debuffs = "debuffMax" }
local SIEVE = { buffs = "HELPFUL", cc = "HARMFUL", debuffs = "HARMFUL" }
local TOP_GLYPHS = 10
local GLYPH_SPACING, LINE_SPACING, TITLE_SPACING = 3, 4, 6
local EDGE = 1
local TRIM = 0.08
local TIME_DIMS, TALLY_DIMS, TITLE_DIMS, SHIELD_DIMS = 0.34, 0.3, 0.42, 0.42
local LEAST_LABEL = 8
local FLASH = 0.5
local CAUTION_WINDOW = 2
local IVORY, GOLDEN, CRIMSON, PALE = { 1, 1, 1, 1 }, { 1, 0.82, 0, 1 }, { 1, 0.2, 0.2, 1 }, { 1, 0.2, 0.2, 0.3 }
local SHIELD_TONE = { 0.55, 0.82, 1 }
local SHIELD_GLYPH = "|TInterface\\Icons\\Spell_Holy_PowerWordShield:0:0:0:0:64:64:5:59:5:59|t "
local CALLING_GLYPHS = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
local TALLY_W, TALLY_H, TALLY_TOP = 206, 26, 155

local VIEWS = {
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
local pending, reskinPending = false, false
local clockOptions, clockSig
local eventWindow = CreateFrame("Frame")

local function Locked() return InCombatLockdown() or (AK and AK.AurasRestricted()) or false end
local function Secret(v) return issecretvalue and issecretvalue(v) end
local function Typeface() return CUI.GetFontPath("essentials") end
local function LabelDims(ratio) return math.max(LEAST_LABEL, math.floor(Get("size") * ratio + 0.5)) end
local function DisplayOn(d) return Enabled() and (d.switch == nil or Get(d.switch) == true) end

-------------------------------------------------------------------------------
--  Filters
-------------------------------------------------------------------------------

-- The ids of every picked entry; n = how many ids.
local function Chosen(items, lead, into)
    local n = 0
    for _, item in ipairs(items) do
        if Get(lead .. item.key) then
            for ident in pairs(item.ids) do
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
local function Sieves()
    local cc, debuffs = {}, {}
    local nCC = Chosen(ABILITIES.crowdControl, CC_LEAD, cc)
    if Get("ccOther") then
        for ident in pairs(ABILITIES.otherCrowdControl) do
            cc[ident] = true
            nCC = nCC + 1
        end
    end
    local nDebuffs = Chosen(ABILITIES.debuffs, HARM_LEAD, debuffs)
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

local function Tint(c) return CreateColor(c[1], c[2], c[3], c[4]) end

-- Warn Before It Ends: white, yellow under twice Red Under, red under it,
-- blinking red with Blink When Red.
local function CautionRamp(cautionAt, flash)
    local ramp = C_CurveUtil.CreateColorCurve()
    ramp:SetType(Enum.LuaCurveType.Step)
    ramp:AddPoint(0, Tint(CRIMSON))
    if flash then
        local at, pale = FLASH, true
        while at < cautionAt do
            ramp:AddPoint(at, Tint(pale and PALE or CRIMSON))
            at, pale = at + FLASH, not pale
        end
    end
    ramp:AddPoint(cautionAt, Tint(GOLDEN))
    ramp:AddPoint(cautionAt * CAUTION_WINDOW, Tint(IVORY))
    return ramp
end

-- The time-left binding options, rebuilt only when the warn settings change.
local function ClockOptions()
    local caution = Get("warn") == true
    local sig = (caution and "1" or "0") .. Get("warnAt") .. (Get("warnBlink") and "1" or "0")
    if sig ~= clockSig then
        clockSig = sig
        local ramp = caution and C_CurveUtil and C_CurveUtil.CreateColorCurve and CautionRamp(Get("warnAt"), Get("warnBlink") == true)
        clockOptions = AK.BuildDurationTextOpts(AK.GetDurationFormatter(false), ramp or nil)
    end
    return clockOptions, sig
end

local function Typefaces(r)
    r.time:SetFont(Typeface(), LabelDims(TIME_DIMS), "OUTLINE")
    r.count:SetFont(Typeface(), LabelDims(TALLY_DIMS), "OUTLINE")
end

-- Size, fonts, which texts show and the time-left binding. Only out of the
-- restriction (the buttons are forbidden while auras are secret).
local function SkinBtn(btn)
    local r = regions[btn]
    if not r then return end
    local dims = Get("size")
    btn:SetSize(dims, dims)
    Typefaces(r)
    r.time:SetShown(Get("timer") == true)
    r.count:SetShown(Get("count") == true)
    if Get("timer") then
        local opts, sig = ClockOptions()
        if r.timerSig ~= sig then
            r.timerSig = sig
            -- A fresh copy: the safe setter strips a refused colour off what it is given.
            local copy = {}
            for k, v in pairs(opts) do
                copy[k] = v
            end
            AK.SetDurationTextSafe(btn, r.time, copy)
        end
    end
end

-- initializeFrame: every region made and given its font before the button
-- registers any of them (each registration paints through them at once).
local function SetupBtn(btn)
    local ground = btn:CreateTexture(nil, "BACKGROUND")
    ground:SetAllPoints()
    ground:SetColorTexture(0, 0, 0, 1)
    local glyph = btn:CreateTexture(nil, "ARTWORK")
    glyph:SetPoint("TOPLEFT", EDGE, -EDGE)
    glyph:SetPoint("BOTTOMRIGHT", -EDGE, EDGE)
    glyph:SetTexCoord(TRIM, 1 - TRIM, TRIM, 1 - TRIM)
    local swipe = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
    swipe:SetAllPoints(glyph)
    swipe:SetDrawEdge(false)
    swipe:SetHideCountdownNumbers(true)
    swipe:SetReverse(true)
    local labelHost = CreateFrame("Frame", nil, btn)
    labelHost:SetAllPoints()
    labelHost:SetFrameLevel(swipe:GetFrameLevel() + 1)
    local timeLabel = labelHost:CreateFontString(nil, "OVERLAY")
    timeLabel:SetPoint("BOTTOM", 0, 2)
    local tallyLabel = labelHost:CreateFontString(nil, "OVERLAY")
    tallyLabel:SetPoint("TOPRIGHT", -2, -2)
    local r = { time = timeLabel, count = tallyLabel }
    regions[btn] = r
    Typefaces(r)
    btn:SetIcon(glyph)
    btn:SetDurationCooldown(swipe)
    btn:SetApplicationCount(tallyLabel)
    buttons[#buttons + 1] = btn
    SkinBtn(btn)
end

local function ReskinButtons()
    if Locked() then
        reskinPending = true
        return
    end
    reskinPending = false
    for i = 1, #buttons do
        SkinBtn(buttons[i])
    end
end

-------------------------------------------------------------------------------
--  Panels
-------------------------------------------------------------------------------

-- The absorb: a clear bar whose value is the amount; its text sits in a clip
-- on the fill, so it shows only while the fill has width.
local function FreshShield(box)
    local bar = CreateFrame("StatusBar", nil, box)
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

local function FreshHeading(box)
    local heading = CreateFrame("Frame", nil, box)
    heading.class = heading:CreateTexture(nil, "ARTWORK")
    heading.class:SetTexture(CALLING_GLYPHS)
    heading.class:SetPoint("LEFT")
    heading.name = heading:CreateFontString(nil, "OVERLAY")
    heading.name:SetPoint("LEFT", heading.class, "RIGHT", TITLE_SPACING, 0)
    heading.name:SetJustifyH("LEFT")
    heading.name:SetWordWrap(false)
    return heading
end

-- Each row on its own line. The icons' size is their own (StyleButton), so a
-- size change never touches the container's layout.
local LINE_ARRANGE = { elementSpacing = GLYPH_SPACING, lineSpacing = LINE_SPACING, groupLineSpacing = LINE_SPACING, forceNewLine = true }

-- The panel's frame (cheap, any time) and its container (out of combat and
-- restriction only; false = not yet).
local function Box(d)
    if d.holder then return d.holder end
    local box = CreateFrame("Frame", d.frameName, UIParent)
    box:SetSize(Get("size"), Get("size"))
    box:Hide()
    d.holder = box
    d.absorb = FreshShield(box)
    if d.nameKey then d.header = FreshHeading(box) end
    return box
end

local function MakeBox(d)
    if d.container then return true end
    if d.failed or Locked() then return false end
    if C_AddOns and not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
        pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
    end
    local box = Box(d)
    local sieves, has = Sieves()
    local success, err = pcall(function()
        local c = CreateFrame("AuraContainer", nil, box, "CustomAuraContainerTemplate")
        c:SetPoint("TOPLEFT")
        c:SetSize(1, 1)
        for _, row in ipairs(LINES) do
            c:AddAuraGroup(row, SIEVE[row], {
                maxFrameCount = TOP_GLYPHS,
                sortMethod = AuraContainerSortMethod and AuraContainerSortMethod.Default or 0,
                initializeFrame = SetupBtn,
                layout = LINE_ARRANGE,
                candidateFilters = has[row] and sieves[row] or nil,
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
local function UseLines(d)
    local c = d.container
    local sieves, has = Sieves()
    for _, row in ipairs(LINES) do
        local on = Get(d.rows[row]) == true and has[row]
        if on then c:SetAuraGroupCandidateFilters(row, sieves[row]) end
        c:SetAuraGroupMaxFrameCount(row, on and Get(TOP_ID[row]) or 0)
        if c.SetAuraGroupEnabled then c:SetAuraGroupEnabled(row, on) end
    end
end

-- The panel's size: the rows that can show something (ticked, with spells to
-- match), as wide as the widest cap.
local function PaneDims(d)
    local _, has = Sieves()
    local dims, lines, wide = Get("size"), 0, 1
    for _, row in ipairs(LINES) do
        if Get(d.rows[row]) and has[row] then lines, wide = lines + 1, math.max(wide, Get(TOP_ID[row])) end
    end
    lines = math.max(lines, 1)
    return wide * dims + (wide - 1) * GLYPH_SPACING, lines * dims + (lines - 1) * LINE_SPACING
end

local function Arrange(d)
    local dims = Get("size")
    d.holder:SetSize(PaneDims(d))
    local shieldDims = LabelDims(SHIELD_DIMS)
    d.absorb.text:SetFont(Typeface(), shieldDims, "OUTLINE")
    d.absorb.text:SetTextColor(SHIELD_TONE[1], SHIELD_TONE[2], SHIELD_TONE[3])
    d.absorb:SetSize(dims * 2, shieldDims + 4)
    d.absorb:ClearAllPoints()
    d.absorb:SetPoint("RIGHT", d.holder, "TOPLEFT", -TITLE_SPACING, -dims / 2)
    if d.header then
        local titleDims = LabelDims(TITLE_DIMS)
        d.header.name:SetFont(Typeface(), titleDims, "OUTLINE")
        d.header.class:SetSize(titleDims + 4, titleDims + 4)
        d.header:SetSize(d.holder:GetWidth(), titleDims + 4)
        d.header:ClearAllPoints()
        d.header:SetPoint("BOTTOMLEFT", d.holder, "TOPLEFT", 0, LINE_SPACING)
    end
end

local function RefreshShield(d)
    local bar = d.absorb
    if not (bar and bar:IsShown()) then return end
    if not UnitExists(d.unit) then
        bar:SetValue(0)
        return
    end
    local amount = UnitGetTotalAbsorbs(d.unit)
    bar:SetValue(amount or 0)
    bar.text:SetFormattedText(SHIELD_GLYPH .. "%d", amount or 0)
end

-- The focus panel's name, tinted by class, with the class icon.
local function RefreshHeading(d)
    local heading = d.header
    if not heading then return end
    local shown = Get(d.nameKey) == true and UnitExists(d.unit)
    heading:SetShown(shown and true or false)
    if not shown then return end
    heading.name:SetText(UnitName(d.unit))
    local _, callingFile = UnitClass(d.unit)
    local plain = callingFile and not Secret(callingFile)
    local tint = plain and RAID_CLASS_COLORS and RAID_CLASS_COLORS[callingFile]
    local coords = plain and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[callingFile]
    if tint then
        heading.name:SetTextColor(tint.r, tint.g, tint.b)
    else
        heading.name:SetTextColor(1, 1, 1)
    end
    heading.class:SetShown(coords ~= nil)
    if coords then heading.class:SetTexCoord(coords[1], coords[2], coords[3], coords[4]) end
end

-- The focus panel steps aside (alpha) while the focus is your target: the
-- target panel already shows them.
local function FocalIsAim()
    if not (UnitExists("focus") and UnitExists("target")) then return false end
    local same = UnitIsUnit("focus", "target")
    return not Secret(same) and same == true
end

local function RefreshFocalDim()
    local d = VIEWS[2]
    if d.holder then d.holder:SetAlpha((FocalIsAim() and not CUI._unlockActive) and 0 or 1) end
end

local function ConcealPane(d)
    if d.container then d.container:SetEnabled(false) end
    if d.holder then d.holder:Hide() end
end

local function RevealPane(d)
    Box(d)
    if not MakeBox(d) then return false end
    UseLines(d)
    Arrange(d)
    if not CUI._unlockActive then d.feat.Place(d.holder) end
    d.container:SetEnabled(true)
    d.holder:Show()
    d.absorb:SetShown(Get("absorb") == true)
    d.container:UpdateAllAuras()
    RefreshShield(d)
    RefreshHeading(d)
    return true
end

-------------------------------------------------------------------------------
--  Battleground Countdown
-------------------------------------------------------------------------------

local tallyBox, tallyHung

local function TallyBox()
    if not tallyBox then
        tallyBox = CreateFrame("Frame", "CludesUIBGCountdown", UIParent)
        tallyBox:SetSize(TALLY_W, TALLY_H)
    end
    return tallyBox
end

-- Blizzard's tracker spans the screen and stacks its bars from 155 below
-- its top, its big digits on its centre: on, it keeps that size and hangs
-- from the holder; off, it goes back over the screen.
local function UseTimer()
    local tracker = _G.TimerTracker
    if not tracker then return end
    if FT.Enabled() then
        local box = TallyBox()
        if not CUI._unlockActive then FT.Place(box) end
        tracker:ClearAllPoints()
        tracker:SetSize(UIParent:GetWidth(), UIParent:GetHeight())
        tracker:SetPoint("TOP", box, "TOP", 0, TALLY_TOP)
        tallyHung = true
    elseif tallyHung then
        tallyHung = false
        tracker:ClearAllPoints()
        tracker:SetAllPoints(UIParent)
    end
end

-------------------------------------------------------------------------------
--  Apply and events
-------------------------------------------------------------------------------

local function Apply()
    UseTimer()
    if FT.Enabled() then
        eventWindow:RegisterEvent("UI_SCALE_CHANGED")
        eventWindow:RegisterEvent("DISPLAY_SIZE_CHANGED")
    else
        eventWindow:UnregisterEvent("UI_SCALE_CHANGED")
        eventWindow:UnregisterEvent("DISPLAY_SIZE_CHANGED")
    end
    if not Enabled() and not (VIEWS[1].holder or VIEWS[2].holder) then return end
    if Locked() then
        pending = true
        eventWindow:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    pending = false
    for _, d in ipairs(VIEWS) do
        eventWindow:UnregisterEvent(d.changed)
    end
    eventWindow:UnregisterEvent("UNIT_ABSORB_AMOUNT_CHANGED")
    local shieldUnits = {}
    for _, d in ipairs(VIEWS) do
        if DisplayOn(d) and RevealPane(d) then
            eventWindow:RegisterEvent(d.changed)
            if Get("absorb") then shieldUnits[#shieldUnits + 1] = d.unit end
        else
            ConcealPane(d)
        end
    end
    if shieldUnits[1] then
        eventWindow:RegisterUnitEvent("UNIT_ABSORB_AMOUNT_CHANGED", shieldUnits[1], shieldUnits[2])
    end
    ReskinButtons()
    RefreshFocalDim()
end

eventWindow:SetScript("OnEvent", function(_, evt, unit)
    if evt == "UNIT_ABSORB_AMOUNT_CHANGED" then
        for _, d in ipairs(VIEWS) do
            if d.unit == unit then RefreshShield(d) end
        end
    elseif evt == "PLAYER_TARGET_CHANGED" or evt == "PLAYER_FOCUS_CHANGED" then
        for _, d in ipairs(VIEWS) do
            if evt == d.changed and d.container then
                d.container:UpdateAllAuras()
                RefreshShield(d)
                RefreshHeading(d)
            end
        end
        RefreshFocalDim()
    elseif evt == "PLAYER_REGEN_ENABLED" then
        if pending then Apply() end
        if reskinPending then ReskinButtons() end
        -- A restricted answer can hold for the rest of the frame it was read
        -- in: what is still waiting tries once more a moment later.
        if pending or reskinPending then
            C_Timer.After(0.2, function()
                if pending then Apply() end
                if reskinPending then ReskinButtons() end
            end)
        end
    else
        -- UI_SCALE_CHANGED / DISPLAY_SIZE_CHANGED: the tracker spans the screen.
        UseTimer()
    end
end)

if AK and AK.OnRestrictionLift then
    AK.OnRestrictionLift(function()
        if pending then Apply() end
        if reskinPending then ReskinButtons() end
    end)
end

CUI._PvPAuras = {
    Get = Get,
    Cfg = F.Cfg,
    Apply = Apply,
    Spells = ABILITIES,
    CC_PREFIX = CC_LEAD,
    DEBUFF_PREFIX = HARM_LEAD,
    CountdownGet = FT.Get,
    CountdownCfg = FT.Cfg,
}

for _, d in ipairs(VIEWS) do
    d.feat.Start(d == VIEWS[1] and Apply or function() end, {
        key = d.key,
        label = d.label,
        order = d.order,
        shown = function() return DisplayOn(d) end,
        frame = function(make)
            if make then Box(d) end
            return d.holder
        end,
        size = function() return PaneDims(d) end,
        noAnchorTarget = true,
        noSizeMatchTarget = true,
    })
end
FT.Start(function() end, {
    key = "CUI_BGCountdown",
    label = "Battleground Countdown",
    order = 760,
    frame = function(make)
        if make then TallyBox() end
        return tallyBox
    end,
    size = function() return TALLY_W, TALLY_H end,
    noAnchorTarget = true,
    noSizeMatchTarget = true,
})
