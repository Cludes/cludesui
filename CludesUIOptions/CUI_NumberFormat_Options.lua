if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
--------------------------------------------------------------------------------
--  CUI_NumberFormat_Options.lua - Global Settings > Numbers.
--
--  How large numbers are shortened (CludesUI_NumberFormat.lua). Each value
--  type (health, max health, absorb, boss health, meter) has its own
--  Precision and threshold, set in the page header for the type picked in
--  its tabs; the page body holds the Unit Style and Letter Case every type
--  shares.
--
--  Everything is saved in the active profile's numberFormat table: the page
--  writes it and calls CludesUI.RefreshNumberFormat. Global Settings calls
--  the builders below; the header is never indexed by the search, so the
--  page registers the header's two settings itself, once per value type.
--  cui-style: allow comment-budget (file header below the client gate)
--------------------------------------------------------------------------------

-- Frames made on an options page come from the page pool (CludesUI_FramePool.lua).
local CreateFrame = CludesUI._Pool.CreateFrame

local TYPES = CludesUI.NUMBER_FORMAT_TYPES

-- Per value type: its tab, the name of its Precision setting (each type
-- its own, so a search hit brings back the right type) and that setting's
-- tooltip.
local TYPE_INFO = {
    health = {
        tab = "Health",
        precision = "Health Precision",
        tip = "Current health values on Unit Frames, Raid Frames, Nameplates and the Resource Bars health bar. Standard keeps the default format. Smart shows three digits (1.23M, 12.3M, 123M).",
    },
    maxHealth = {
        tab = "Max Health",
        precision = "Max Health Precision",
        tip = "Maximum health values on Unit Frames, Raid Frames, Nameplates and the Resource Bars health bar. Standard keeps the default format. Smart shows three digits (1.23M, 12.3M, 123M).",
    },
    absorb = {
        tab = "Absorb",
        precision = "Absorb Precision",
        tip = "Absorb and heal absorb values on Unit Frames, Raid Frames and Nameplates. Standard keeps the default format. Smart shows three digits (1.23M, 12.3M, 123M).",
    },
    bossHealth = {
        tab = "Boss Health",
        precision = "Boss Health Precision",
        tip = "Current and maximum health on the Unit Frames boss frames. Standard keeps the default format. Smart shows three digits (1.23M, 12.3M, 123M).",
    },
    meter = {
        tab = "Damage Meter",
        precision = "Damage Meter Precision",
        -- WoW Forever has no Mythic+ run summary; its threat meter uses this type instead.
        tip = CludesUI.IS_FOREVER
                and "Damage Meters and the threat meter. Standard keeps the Damage Meters' own format. Smart shows three digits (1.23M, 12.3M, 123M)."
            or "Damage Meters and the Mythic+ run summary. Standard keeps the Damage Meters' own format. Smart shows three digits (1.23M, 12.3M, 123M).",
    },
}

local PRECISION_CHOICES = {
    values = {
        standard = "Standard",
        smart = "Smart (3 Digits)",
        [0] = "0 Decimals",
        [1] = "1 Decimal",
        [2] = "2 Decimals",
    },
    order = { "standard", "smart", 0, 1, 2 },
}
local THRESHOLD_CHOICES = {
    values = { [1000] = "1,000", [10000] = "10,000", [100000] = "100,000" },
    order = { 1000, 10000, 100000 },
}
local THRESHOLD_LABEL = "Start Abbreviating At"
local THRESHOLD_TIP = "Numbers below this stay whole."
local THRESHOLD_LOCK = "This option requires a Precision other than Standard"

-- The header preview: these numbers, each above what the shown type makes of it.
local PREVIEW_VALUES = { 8765, 45320, 1234567, 2345678901 }
local PREVIEW_COLUMN_W = 130

local INFO_ICON = [[Interface\AddOns\CludesUI\media\icons\cui-info.png]]
local INFO_ALPHA, INFO_ALPHA_HOVER = 0.45, 0.9

--------------------------------------------------------------------------------
--  The shown value type
--------------------------------------------------------------------------------
-- Picked in the header tabs, or set by a search jump to one type's setting.
local shownType = TYPES[1]

CludesUI._setNumberFormatType = function(valueType)
    shownType = valueType
end

-- The search builds the page once per type (its "variants").
function _G._CUI_NumberFormatVariants()
    return { setter = CludesUI._setNumberFormatType, keys = TYPES, currentKey = shownType }
end

--------------------------------------------------------------------------------
--  Reading and writing the settings
--------------------------------------------------------------------------------
-- A type's Precision and threshold as the engine applies them.
local function Precision(valueType)
    local precision = CludesUI.NumberFormatTypeSettings(valueType)
    return precision
end

local function Threshold(valueType)
    local _, threshold = CludesUI.NumberFormatTypeSettings(valueType)
    return threshold
end

local function EveryTypeStandard()
    for _, valueType in ipairs(TYPES) do
        if Precision(valueType) ~= "standard" then
            return false
        end
    end
    return true
end

-- Repaints the header for the shown type; set once the header is built.
local RefreshHeader

-- After any change: the engine, the header, then the page's rows.
local function Applied()
    CludesUI.RefreshNumberFormat()
    if RefreshHeader then
        RefreshHeader()
    end
    CludesUI:RefreshPage()
end

-- One setting of one value type. Standard Precision is saved as no value.
local function SetTypeSetting(valueType, key, value)
    local saved = CludesUI.GetNumberFormatDB(true)
    if not saved then
        return
    end
    saved.types = saved.types or {}
    local forType = saved.types[valueType] or {}
    saved.types[valueType] = forType
    if key == "precision" and value == "standard" then
        value = nil
    end
    forType[key] = value
    Applied()
end

-- One setting shared by every value type.
local function SetSharedSetting(key, value)
    local saved = CludesUI.GetNumberFormatDB(true)
    if not saved then
        return
    end
    saved[key] = value
    Applied()
end

-- A shared setting as its row shows it: the saved value when it is the
-- other choice, else the default.
local function SharedChoice(key, other, default)
    local saved = CludesUI.GetNumberFormatDB()
    if saved and saved[key] == other then
        return other
    end
    return default
end

--------------------------------------------------------------------------------
--  Module settings that win over this page
--------------------------------------------------------------------------------
-- Unit Frames' Show Decimal on Health Text (not in its percent-only form).
local function UnitFramesDecimalsOn()
    local mod = CludesUI.ModuleNS("CludesUIUnitFrames")
    local profile = mod and mod.db and mod.db.profile
    return profile ~= nil and profile.showDecimalOnText == true and profile.showDecimalPercentOnly ~= true
end

-- Damage Meters' Force English Units, which only overrides anything while
-- the Unit Style shows the client's own units.
local function MetersForceEnglishOn()
    local db = _G._CUDM_DB
    local meters = db and db.profile and db.profile.dm
    return meters ~= nil and meters.forceEnglishUnits == true and CludesUI.NumberFormatUsesGlyphs()
end

local OVERRIDES = {
    meter = {
        active = MetersForceEnglishOn,
        note = "Damage Meters' Force English Units overrides the Unit Style on Damage Meters",
        module = "CludesUIDamageMeters",
        page = "Damage Meters",
        section = "BAR TEXT",
        setting = "Force English Units (K/M/B)",
    },
    other = {
        active = UnitFramesDecimalsOn,
        note = "Unit Frames' Show Decimal on Health Text overrides this on Unit Frames",
        module = "CludesUIUnitFrames",
        page = "Main Frames",
        section = "DISPLAY",
        setting = "Show Decimal on Health Text",
    },
}

-- The override for a value type, unpacked as the link row takes it: whether
-- it is on, its note, then where the setting is (module, page, section, row).
local function Override(valueType)
    local o = OVERRIDES[valueType] or OVERRIDES.other
    return o.active(), o.note, o.module, o.page, o.section, o.setting
end

--------------------------------------------------------------------------------
--  Header
--------------------------------------------------------------------------------
-- The value type tabs. Returns the control, its height and its refresh.
local function BuildTypeTabs(heading)
    local labels = {}
    for _, valueType in ipairs(TYPES) do
        labels[valueType] = TYPE_INFO[valueType].tab
    end
    return CludesUI.BuildSegmentedControl({
        parent = heading,
        keys = TYPES,
        labels = labels,
        autoWidth = true,
        square = true,
        getChecked = function(key)
            return key == shownType
        end,
        -- The rest of the header and the page read the shown type live, so a
        -- pick only refreshes them.
        onToggle = function(key)
            if key == shownType then
                return
            end
            shownType = key
            RefreshHeader()
            CludesUI:RefreshPage()
        end,
    })
end

-- One column per preview value, centred on the header: the number small,
-- and the result in the accent under it. Returns the result strings.
local function BuildPreview(heading, posY)
    local PP = CludesUI.PanelPP
    local accent = CludesUI.CLUDES_GREEN
    local count = #PREVIEW_VALUES
    local results = {}
    for i, value in ipairs(PREVIEW_VALUES) do
        local posX = (i - (count + 1) / 2) * PREVIEW_COLUMN_W
        local number = CludesUI.MakeFont(heading, 11, nil, 1, 1, 1, 0.4)
        number:SetText(BreakUpLargeNumbers(value))
        PP.Point(number, "TOP", heading, "TOP", posX, posY)
        local result = CludesUI.MakeFont(heading, 20, nil, accent.r, accent.g, accent.b, 1)
        PP.Point(result, "TOP", heading, "TOP", posX, posY - 16)
        results[i] = result
    end
    return results
end

-- A header label and its dropdown, the setting's tooltip on the label.
-- With info set, an (i) follows the label (lowered by info.dy) and lights
-- up with the tooltip. Placing the label and dropdown is the caller's.
local function BuildHeaderSetting(heading, spec)
    local label = CludesUI.MakeFont(heading, 14, nil, 1, 1, 1, 1)
    label:SetText(CludesUI.L(spec.label))
    local dropdown = CludesUI.BuildDropdownControl(
        heading,
        spec.width,
        heading:GetFrameLevel() + 5,
        spec.choices.values,
        spec.choices.order,
        spec.get,
        spec.set
    )
    local icon
    if spec.info then
        icon = heading:CreateTexture(nil, "OVERLAY")
        icon:SetTexture(INFO_ICON)
        icon:SetVertexColor(1, 1, 1, INFO_ALPHA)
        CludesUI.PanelPP.Size(icon, 12, 12)
        icon:SetPoint("LEFT", label, "RIGHT", 5, spec.info.dy)
    end
    local hover = CreateFrame("Frame", nil, heading)
    hover:SetPoint("TOPLEFT", label, "TOPLEFT", 0, 0)
    hover:SetPoint("BOTTOMRIGHT", icon or label, "BOTTOMRIGHT", 0, 0)
    hover:SetMouseClickEnabled(false)
    hover:SetMouseMotionEnabled(true)
    hover:SetScript("OnEnter", function()
        if icon then
            icon:SetVertexColor(1, 1, 1, INFO_ALPHA_HOVER)
        end
        CludesUI.ShowWidgetTooltip(label, spec.tooltip())
    end)
    hover:SetScript("OnLeave", function()
        if icon then
            icon:SetVertexColor(1, 1, 1, INFO_ALPHA)
        end
        CludesUI.HideWidgetTooltip()
    end)
    return label, dropdown
end

-- The cover over the threshold while the shown type is on Standard: it
-- takes the mouse and shows the row lock tooltip.
local function BuildThresholdLock(heading, label, dropdown)
    local lock = CreateFrame("Frame", nil, heading)
    lock:SetPoint("TOPLEFT", label, "TOPLEFT", 0, 0)
    lock:SetPoint("BOTTOMRIGHT", dropdown, "BOTTOMRIGHT", 0, 0)
    lock:SetFrameLevel(dropdown:GetFrameLevel() + 10)
    lock:EnableMouse(true)
    lock:SetScript("OnEnter", function()
        CludesUI.ShowWidgetTooltip(dropdown, CludesUI.DisabledTooltip(THRESHOLD_LOCK))
    end)
    lock:SetScript("OnLeave", function()
        CludesUI.HideWidgetTooltip()
    end)
    return lock
end

-- Tabs, preview, then the shown type's Precision and threshold either side
-- of the middle. Returns the header's height.
local function BuildHeader(heading)
    local PP = CludesUI.PanelPP
    local L = CludesUI.L
    local posY = -16

    local tabs, tabsH, refreshTabs = BuildTypeTabs(heading)
    tabs:SetFrameLevel(heading:GetFrameLevel() + 5)
    PP.Point(tabs, "TOP", heading, "TOP", 0, posY)
    posY = posY - tabsH - 20

    local results = BuildPreview(heading, posY)
    posY = posY - 58

    -- Precision: its (i) names the modules the type covers and how it cuts.
    -- The label is centred on the dropdown, and the (i) sits 3px lower to
    -- meet the label's optical middle.
    local precisionLabel, precisionDropdown = BuildHeaderSetting(heading, {
        label = TYPE_INFO[shownType].precision,
        tooltip = function()
            return L(TYPE_INFO[shownType].tip) .. "\n\n" .. CludesUI.L("Numbers are cut, not rounded.")
        end,
        width = 170,
        choices = PRECISION_CHOICES,
        get = function()
            return Precision(shownType)
        end,
        set = function(value)
            SetTypeSetting(shownType, "precision", value)
        end,
        info = { dy = -3 },
    })
    PP.Point(precisionDropdown, "TOPRIGHT", heading, "TOP", -20, posY)
    precisionLabel:SetPoint("RIGHT", precisionDropdown, "LEFT", -(12 + 12 + 5), 0)

    local thresholdLabel, thresholdDropdown = BuildHeaderSetting(heading, {
        label = THRESHOLD_LABEL,
        tooltip = function()
            return L(THRESHOLD_TIP)
        end,
        width = 110,
        choices = THRESHOLD_CHOICES,
        get = function()
            return Threshold(shownType)
        end,
        set = function(value)
            SetTypeSetting(shownType, "threshold", value)
        end,
    })
    thresholdLabel:SetPoint("TOPLEFT", heading, "TOP", 20, posY - 8)
    thresholdDropdown:SetPoint("LEFT", thresholdLabel, "RIGHT", 12, 0)
    local thresholdLock = BuildThresholdLock(heading, thresholdLabel, thresholdDropdown)
    posY = posY - 46

    RefreshHeader = function()
        local valueType = shownType
        precisionLabel:SetText(L(TYPE_INFO[valueType].precision))
        for i, result in ipairs(results) do
            result:SetText(CludesUI.AbbreviateValue(PREVIEW_VALUES[i], valueType))
        end
        local locked = Precision(valueType) == "standard"
        local alpha = locked and 0.3 or 1
        thresholdLabel:SetAlpha(alpha)
        thresholdDropdown:SetAlpha(alpha)
        thresholdDropdown:EnableMouse(not locked)
        thresholdLock:SetShown(locked)
        precisionDropdown._refreshLabel()
        thresholdDropdown._refreshLabel()
        if refreshTabs then
            refreshTabs()
        end
    end
    RefreshHeader()

    return math.abs(posY)
end

function _G._CUI_NumberFormatHeaderBuilder()
    return BuildHeader
end

function _G._CUI_NumberFormatRefreshHeader()
    if RefreshHeader then
        RefreshHeader()
    end
end

--------------------------------------------------------------------------------
--  Page
--------------------------------------------------------------------------------
-- The header's two settings for the shown type, as search entries tagged
-- with the type: a jump picks the type and stops there (their section is
-- not on the page). The body rows are shared by every type and stay
-- untagged, so a jump to one keeps the shown type.
local function RegisterHeaderSearch(valueType)
    local L = CludesUI.L
    local module, page = CludesUI._buildingModule, CludesUI._buildingPage
    local entries = {
        { TYPE_INFO[valueType].precision, TYPE_INFO[valueType].tip },
        { THRESHOLD_LABEL, THRESHOLD_TIP },
    }
    for _, entry in ipairs(entries) do
        local label, tip = entry[1], entry[2]
        local localized = L(label)
        CludesUI._RegisterSearchEntry(
            label,
            localized ~= label and localized or nil,
            tip,
            module,
            page,
            "PRECISION",
            CludesUI._setNumberFormatType,
            valueType
        )
    end
end

-- The two shared settings' rows (new tables for every build).
local function LetterCaseRow()
    return {
        type = "segmented",
        text = "Letter Case",
        tooltip = "Upper or lower case unit letters, for every value type with a Precision other than Standard.",
        values = { upper = "K M B", lower = "k m b" },
        order = { "upper", "lower" },
        getValue = function()
            return SharedChoice("case", "lower", "upper")
        end,
        setValue = function(value)
            SetSharedSetting("case", value ~= "upper" and value or nil)
        end,
        disabled = function()
            return EveryTypeStandard() or CludesUI.NumberFormatUsesGlyphs()
        end,
        disabledTooltip = function()
            if CludesUI.NumberFormatUsesGlyphs() then
                return "Your client's units have no letter case"
            end
            return "This option requires a value type with a Precision other than Standard"
        end,
        rawTooltip = true,
    }
end

local function UnitStyleRow()
    return {
        type = "dropdown",
        text = "Unit Style",
        tooltip = "Client Language uses your language's own units (ten-thousand groups in Chinese and Korean). Western always uses K, M and B. Applies to every value type.",
        values = { auto = "Client Language", western = "Western (K, M, B)" },
        order = { "auto", "western" },
        getValue = function()
            return SharedChoice("units", "western", "auto")
        end,
        setValue = function(value)
            SetSharedSetting("units", value ~= "auto" and value or nil)
        end,
        disabled = function()
            return not CludesUI.LocaleHasNumberAbbreviation()
        end,
        disabledTooltip = "Only East Asian clients have their own units",
        rawTooltip = true,
    }
end

-- The note naming a module setting that overrides the shown type, with a
-- jump to it. That setting is on another page, so the row is always built
-- (last, so hiding it moves nothing) and re-aimed and shown or hidden on
-- every refresh (a type pick, a cache restore). The inline search leaves
-- it alone: clearing a search shows every row it collected.
local function BuildOverrideNote(hostFrame, posY)
    local active, note, module, page, section, setting = Override(shownType)
    local row
    posY, row = CludesUI.BuildLinkRow(hostFrame, posY, note, module, page, section, setting, { warn = true })
    row._searchIgnore = true
    row:SetShown(active)
    CludesUI.RegisterWidgetRefresh(function()
        local on, text, m, p, s, hl = Override(shownType)
        row:Relink(text, m, p, s, hl)
        row:SetShown(on)
    end)
    return posY
end

-- Builds the page into hostFrame from yOffset down; returns its height.
function _G._CUI_BuildNumberFormatPage(pageName, hostFrame, yOffset)
    local W = CludesUI.Widgets
    local posY = yOffset
    local _, hgt

    CludesUI:SetContentHeader(BuildHeader)
    RegisterHeaderSearch(shownType)

    hostFrame._showRowDivider = true

    _, hgt = W:SectionHeader(hostFrame, "UNITS (GLOBAL)", posY)
    posY = posY - hgt

    _, hgt = W:DualRow(hostFrame, posY, LetterCaseRow(), UnitStyleRow())
    posY = posY - hgt

    posY = BuildOverrideNote(hostFrame, posY)

    -- The page framework takes the content height as a positive number.
    return math.abs(posY)
end
