if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-------------------------------------------------------------------------------
--  CUI_Colors_Options.lua -- Global Settings > Colors. It registers nothing:
--  the Global Settings module (CUI__General_Options.lua) dispatches its builder.
-------------------------------------------------------------------------------
local Pix = CUI.PanelPP

-- Options page pool (CludesUI_FramePool.lua): frames made here on a pool
-- host are reset and dressed again by the next build instead of made anew;
-- elsewhere this is CreateFrame.
local CreateFrame = CUI._Pool.CreateFrame

---------------------------------------------------------------------------
--  Colors Page
---------------------------------------------------------------------------
local CLASS_ORDER = CUI.CLASS_TOKEN_ORDER
local CLASS_LABELS = {
    WARRIOR = "Warrior",
    PALADIN = "Paladin",
    HUNTER = "Hunter",
    ROGUE = "Rogue",
    PRIEST = "Priest",
    DEATHKNIGHT = "Death Knight",
    SHAMAN = "Shaman",
    MAGE = "Mage",
    WARLOCK = "Warlock",
    MONK = "Monk",
    DRUID = "Druid",
    DEMONHUNTER = "Demon Hunter",
    EVOKER = "Evoker",
}
local POWER_LABELS = {
    MANA = "Mana",
    RAGE = "Rage",
    FOCUS = "Focus",
    ENERGY = "Energy",
    RUNIC_POWER = "Runic Power",
    LUNAR_POWER = "Astral Power",
    INSANITY = "Insanity",
    MAELSTROM = "Maelstrom",
    FURY = "Fury",
    PAIN = "Pain",
    EBON_MIGHT = "Ebon Might",
}
local RESOURCE_LABELS = {
    ComboPoints = "Combo Points",
    HolyPower = "Holy Power",
    Chi = "Chi",
    SoulShards = "Soul Shards",
    ArcaneCharges = "Arcane Charges",
    Essence = "Essence",
    Runes = "Runes",
    SoulFragments = "Soul Fragments",
}
local GRADIENT_DIR_VALUES = {
    ["HORIZONTAL"] = "Left to Right",
    ["HORIZONTAL_REV"] = "Right to Left",
    ["VERTICAL"] = "Top to Bottom",
    ["VERTICAL_REV"] = "Bottom to Top",
}
local GRADIENT_DIR_ORDER = { "HORIZONTAL", "HORIZONTAL_REV", "VERTICAL", "VERTICAL_REV" }

function _G._CUI_BuildColorsPage(page, hostFrame, yOffset)
    local W = CUI.Widgets
    local cursorY = yOffset
    local _, height
    local MakeFont = CUI.MakeFont
    -- Swatches read/write the EFFECTIVE palette, resolved per section (per-profile
    -- -> the active profile's own; global -> that section's source profile's). Every
    -- editable case IS the active profile's table; the one locked case (a global
    -- section viewed from a non-source profile) is gated by that section's overlay below.
    local GetCustomColorsDB = CUI.GetCustomColorsDB
    local CLASS_COLOR_MAP = CUI.CLASS_COLOR_MAP
    local DEFAULT_POWER_COLORS = CUI.DEFAULT_POWER_COLORS
    local CONTENT_PAD = CUI.CONTENT_PAD or 20

    hostFrame._showRowDivider = true

    -- Helper to save a color entry
    local function SaveColorEntry(category, key, payload)
        local saved = GetCustomColorsDB()
        if not saved[category] then saved[category] = {} end
        saved[category][key] = payload
        CUI.ApplyColorsToOUF()
    end

    -------------------------------------------------------------------
    --  Shared 4-column color grid builder
    -------------------------------------------------------------------
    local GRID_COLS = 4
    local GRID_ROW_H = 50
    local GRID_PAD = CONTENT_PAD
    local GRID_SIDE_PAD = 20
    local SWATCH_SZ = 20

    -- items = { { label, classToken, getColor, setColor, resetFn }, ... }
    local function BuildColorGrid(par, yPos, itemList)
        local totalRows = math.ceil(#itemList / GRID_COLS)
        local totalW = par:GetWidth() - GRID_PAD * 2
        local colW = math.floor(totalW / GRID_COLS)

        for row = 0, totalRows - 1 do
            local rowFrame = CreateFrame("Frame", nil, par)
            Pix.Size(rowFrame, totalW, GRID_ROW_H)
            Pix.Point(rowFrame, "TOPLEFT", par, "TOPLEFT", GRID_PAD, yPos - row * GRID_ROW_H)
            rowFrame._skipRowDivider = true
            CUI.RowBg(rowFrame, par)

            -- Column dividers
            for d = 1, GRID_COLS - 1 do
                local div = rowFrame:CreateTexture(nil, "ARTWORK")
                div:SetColorTexture(1, 1, 1, 0.06)
                if div.SetSnapToPixelGrid then
                    div:SetSnapToPixelGrid(false)
                    div:SetTexelSnappingBias(0)
                end
                div:SetWidth(1)
                local xPos = d * colW
                Pix.Point(div, "TOP", rowFrame, "TOPLEFT", xPos, 0)
                Pix.Point(div, "BOTTOM", rowFrame, "BOTTOMLEFT", xPos, 0)
            end

            for col = 0, GRID_COLS - 1 do
                local position = row * GRID_COLS + col + 1
                local entry = itemList[position]
                if not entry then break end

                local cell = CreateFrame("Frame", nil, rowFrame)
                cell:SetSize(colW, GRID_ROW_H)
                cell:SetPoint("TOPLEFT", rowFrame, "TOPLEFT", col * colW, 0)

                -- Class-colored label (or white for power colors)
                local cr, cg, checkBtn = 1, 1, 1
                if entry.classToken then
                    local classColor = RAID_CLASS_COLORS and RAID_CLASS_COLORS[entry.classToken]
                    if classColor then
                        cr, cg, checkBtn = classColor.r, classColor.g, classColor.b
                    end
                end
                local labelText = MakeFont(cell, 13, nil, cr, cg, checkBtn)
                labelText:SetPoint("LEFT", cell, "LEFT", GRID_SIDE_PAD, 0)
                labelText:SetText(entry.label)

                -- Color swatch (right side)
                local colorSwatch, updateSwatch = CUI.BuildColorSwatch(
                    cell,
                    cell:GetFrameLevel() + 2,
                    function()
                        local color = entry.getColor()
                        return color.r, color.g, color.b, 1
                    end,
                    function(red, green, blue)
                        local color = entry.getColor()
                        color.r = red
                        color.g = green
                        color.b = blue
                        entry.setColor(color)
                        local refreshList = CUI._widgetRefreshList
                        if refreshList then
                            for i2 = 1, #refreshList do
                                refreshList[i2]()
                            end
                        end
                    end,
                    false,
                    SWATCH_SZ
                )
                colorSwatch:SetPoint("RIGHT", cell, "RIGHT", -GRID_SIDE_PAD, 0)
                -- Repaint on page refresh/show (SelectPage re-runs the refresh list on show) so swatches survive a profile/global-source change.
                CUI.RegisterWidgetRefresh(updateSwatch)

                -- Undo (reset) button
                local undoBtn = CreateFrame("Button", nil, cell)
                undoBtn:SetSize(18, 18)
                undoBtn:SetPoint("RIGHT", colorSwatch, "LEFT", -10, 0)
                undoBtn:SetFrameLevel(cell:GetFrameLevel() + 3)
                undoBtn:SetAlpha(0.3)
                local undoTex = undoBtn:CreateTexture(nil, "ARTWORK")
                undoTex:SetAllPoints()
                undoTex:SetTexture(CUI.UNDO_ICON)
                undoBtn:SetScript("OnEnter", function(self)
                    self:SetAlpha(0.6)
                    CUI.ShowWidgetTooltip(self, "Reset to default")
                end)
                undoBtn:SetScript("OnLeave", function(self)
                    self:SetAlpha(0.3)
                    CUI.HideWidgetTooltip()
                end)
                undoBtn:SetScript("OnClick", function()
                    entry.resetFn()
                    CUI.ApplyColorsToOUF()
                    updateSwatch()
                    local refreshList = CUI._widgetRefreshList
                    if refreshList then
                        for i2 = 1, #refreshList do
                            refreshList[i2]()
                        end
                    end
                end)
            end
        end

        return totalRows * GRID_ROW_H
    end

    -------------------------------------------------------------------
    --  DARK MODE section (per-profile, never subject to "Apply to All
    --  Profiles"). One palette drives Unit Frames, Raid Frames and
    --  Resource Bars (RB ignores the opacity sliders). "Darken" sliders
    --  blacken class/power/class-resource colours inside the colour getters, reaching every module with no extra wiring.
    -------------------------------------------------------------------
    _, height = W:SectionHeader(hostFrame, "DARK MODE", cursorY)
    cursorY = cursorY - height
    do
        local DM_DEF = CUI.DEFAULT_DARK_MODE

        -- Dark Mode: one checkbox dropdown with each module's own Dark Mode, a
        -- pure view over the registered per-module providers (no stored key). A
        -- tick writes through SetDarkModeAll with a one-provider filter, so its
        -- tail rechecks the override condition exactly as before. The Dark Mode
        -- override condition still reads "every provider but the class resource
        -- bar on" (DarkModeMasterOn), which is what the old main toggle showed.
        -- Those providers are its inputs, so they lock while a Dark Mode override
        -- is edited (an override must not capture a change that flips its own
        -- condition); the class resource bar never does.
        local DM_ITEMS = {
            { key = "unitFrames", label = "Unit Frames" },
            { key = "raidFrames", label = "Raid & Party Frames" },
            { key = "resourceBars", label = "Class Resource Bar" },
        }
        local function DMProvider(ident)
            for _, p in ipairs(CUI._darkModeToggles) do
                if p.id == ident then return p end
            end
        end
        local function CondEditLocked()
            return CUI.SpecOverrides_DarkCondEditActive ~= nil
                    and CUI.SpecOverrides_DarkCondEditActive()
                or false
        end
        local dmItems = {}
        for _, it in ipairs(DM_ITEMS) do
            -- A module that is off registers no provider: no row for it.
            if DMProvider(it.key) then
                if it.key ~= "resourceBars" then
                    it.lockedFn = CondEditLocked
                    it.lockedTooltip =
                        "Dark Mode drives a Dark Mode override condition and can't be changed while editing an override"
                end
                dmItems[#dmItems + 1] = it
            end
        end

        -- Row 1: Dark Mode (checkbox dropdown) | Color Darkening (slider
        -- dropdown: the class / resource / power / BG power darken amounts).
        local dmRow
        dmRow, height = W:DualRow(hostFrame, cursorY, {
            type = "dropdown",
            text = "Dark Mode",
            tooltip = "Turns Dark Mode on or off for each module.",
            values = { ["_placeholder"] = "..." },
            order = { "_placeholder" },
            getValue = function() return "_placeholder" end,
            setValue = function() end,
        }, {
            type = "dropdown",
            text = "Color Darkening",
            tooltip = "Darkens class, resource and power colors.",
            values = { ["_placeholder"] = "..." },
            order = { "_placeholder" },
            getValue = function() return "_placeholder" end,
            setValue = function() end,
        })
        cursorY = cursorY - height

        -- Row 2: Dark Mode Fill | Background -- each an opacity slider with its
        -- colour as an inline swatch (Resource Bars use the colours but ignore
        -- the opacity).
        local fillRow
        fillRow, height = W:DualRow(hostFrame, cursorY, {
            type = "slider",
            text = "Dark Mode Fill",
            min = 0,
            max = 100,
            step = 5,
            trackWidth = 120,
            tooltip = "Fill color and opacity of Dark Mode bars.",
            tooltipOnControl = "Fill Opacity",
            getValue = function()
                local darkDB = CUI.GetDarkModeDB()
                return math.floor((darkDB.fillA or DM_DEF.fillA) * 100 + 0.5)
            end,
            setValue = function(val)
                local darkDB = CUI.GetDarkModeDB()
                darkDB.fillA = val / 100
                CUI.RefreshDarkMode()
            end,
        }, {
            type = "slider",
            text = "Background",
            min = 0,
            max = 100,
            step = 5,
            trackWidth = 120,
            tooltip = "Color and opacity behind Dark Mode bars.",
            tooltipOnControl = "Background Opacity",
            getValue = function()
                local darkDB = CUI.GetDarkModeDB()
                return math.floor((darkDB.bgA or DM_DEF.bgA) * 100 + 0.5)
            end,
            setValue = function(val)
                local darkDB = CUI.GetDarkModeDB()
                darkDB.bgA = val / 100
                CUI.RefreshDarkMode()
            end,
        })
        cursorY = cursorY - height

        if not CUI._prebuilding then
            local region = dmRow._leftRegion
            if region._control then region._control:Hide() end
            local checkDrop, cbDDRefresh = CUI.BuildVisOptsCBDropdown(
                region,
                210,
                region:GetFrameLevel() + 2,
                dmItems,
                function(ident)
                    local p = DMProvider(ident)
                    if not p then return false end
                    local success, enabled = pcall(p.isOn)
                    return (success and enabled) and true or false
                end,
                function(ident, val)
                    CUI.SetDarkModeAll(val, function(profile) return profile.id == ident end)
                    CUI:RefreshPage()
                end
            )
            Pix.Point(checkDrop, "RIGHT", region, "RIGHT", -20, 0)
            region._control = checkDrop
            region._lastInline = nil
            CUI.RegisterWidgetRefresh(cbDDRefresh)

            -- The four darken amounts (same keys and ranges the old rows had).
            local function DarkenRow(key, labelText, tipText)
                return {
                    label = labelText,
                    tooltip = tipText,
                    min = 0,
                    max = 100,
                    step = 5,
                    get = function() return CUI.GetDarkModeDB()[key] or 0 end,
                    set = function(val)
                        CUI.GetDarkModeDB()[key] = val
                        CUI.RefreshDarkMode()
                    end,
                }
            end
            local drgn = dmRow._rightRegion
            if drgn._control then drgn._control:Hide() end
            local sDD, sDDRefresh = CUI.BuildSliderDropdown(drgn, 210, drgn:GetFrameLevel() + 2, {
                DarkenRow("classDarken", "Class", "Darkens every class color."),
                DarkenRow("resourceDarken", "Resource", "Darkens every class resource color."),
                DarkenRow("powerDarken", "Power", "Darkens every power color."),
                DarkenRow("powerBgDarken", "BG Power", "Darkens power-colored bar backgrounds."),
            })
            Pix.Point(sDD, "RIGHT", drgn, "RIGHT", -20, 0)
            drgn._control = sDD
            drgn._lastInline = nil
            CUI.RegisterWidgetRefresh(sDDRefresh)

            CUI.BuildInlineSwatches(fillRow._leftRegion, {
                {
                    tooltip = "Fill Color",
                    getValue = function()
                        local darkDB = CUI.GetDarkModeDB()
                        return darkDB.fillR or DM_DEF.fillR,
                            darkDB.fillG or DM_DEF.fillG,
                            darkDB.fillB or DM_DEF.fillB,
                            1
                    end,
                    setValue = function(red, green, blue)
                        local darkDB = CUI.GetDarkModeDB()
                        darkDB.fillR, darkDB.fillG, darkDB.fillB = red, green, blue
                        CUI.RefreshDarkMode()
                    end,
                },
            }, { size = 20 })
            CUI.BuildInlineSwatches(fillRow._rightRegion, {
                {
                    tooltip = "Background Color",
                    getValue = function()
                        local darkDB = CUI.GetDarkModeDB()
                        return darkDB.bgR or DM_DEF.bgR, darkDB.bgG or DM_DEF.bgG, darkDB.bgB or DM_DEF.bgB, 1
                    end,
                    setValue = function(red, green, blue)
                        local darkDB = CUI.GetDarkModeDB()
                        darkDB.bgR, darkDB.bgG, darkDB.bgB = red, green, blue
                        CUI.RefreshDarkMode()
                    end,
                },
            }, { size = 20 })
        end
    end

    _, height = W:Spacer(hostFrame, cursorY, 20)
    cursorY = cursorY - height

    -------------------------------------------------------------------
    --  Colour sections. Each opens with its own "Apply to All Profiles" |
    --  "Pull Colors From" row (CludesUI.ColorSectionApplyAll / ColorSectionPullFrom;
    --  a section with no setting of its own reads the old shared pair). While a
    --  section mirrors another profile's colours (global mode, viewed from a
    --  different profile) its grid -- not its source row -- gets a click-blocking
    --  overlay, built at the end of this builder from the bounds captured below.
    -------------------------------------------------------------------
    local profileOrder = select(1, CUI.GetProfileList()) or {}
    local pullValues = {}
    for _, num in ipairs(profileOrder) do
        pullValues[num] = num
    end
    local _colorGates = {} -- { section, top, bot } per section grid
    local function AddSourceRow(section)
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Apply to All Profiles",
            tooltip = "Share this section's colors across profiles.",
            getValue = function() return CUI.ColorSectionApplyAll(section) end,
            setValue = function(val)
                CUI.SetColorSectionApplyAll(section, val)
                CUI.ApplyColorsToOUF()
                -- Force rebuild: the toggle flips the dropdown's enabled state and the section's gate.
                CUI:RefreshPage(true)
            end,
        }, {
            type = "dropdown",
            text = "Pull Colors From",
            tooltip = "Copies this section's colours from another profile.",
            values = pullValues,
            order = profileOrder,
            disabled = function() return not CUI.ColorSectionApplyAll(section) end,
            disabledTooltip = "Apply to All Profiles",
            getValue = function() return CUI.ColorSectionPullFrom(section) end,
            setValue = function(val)
                CUI.SetColorSectionPullFrom(section, val)
                CUI.ApplyColorsToOUF()
                CUI:RefreshPage()
            end,
        })
        cursorY = cursorY - height
        _colorGates[#_colorGates + 1] = { section = section, top = cursorY }
    end

    -------------------------------------------------------------------
    --  CLASS COLORS section
    -------------------------------------------------------------------
    _, height = W:SectionHeader(hostFrame, "CLASS COLORS", cursorY)
    cursorY = cursorY - height
    AddSourceRow("class")

    local classItems = {}
    for _, token in ipairs(CLASS_ORDER) do
        -- Class names are Blizzard-localized in every client language; use the client's own names, falling back to our English labels.
        local labelFS = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[token])
            or CLASS_LABELS[token]
        local def = CLASS_COLOR_MAP[token] or { r = 1, g = 1, b = 1 }
        classItems[#classItems + 1] = {
            label = CUI.L(labelFS),
            classToken = token,
            getColor = function()
                local saved = GetCustomColorsDB()
                if saved.class and saved.class[token] then return saved.class[token] end
                return { r = def.r, g = def.g, b = def.b }
            end,
            setColor = function(c) SaveColorEntry("class", token, c) end,
            resetFn = function()
                local saved = GetCustomColorsDB()
                if saved.class then saved.class[token] = nil end
            end,
        }
    end

    height = BuildColorGrid(hostFrame, cursorY, classItems)
    cursorY = cursorY - height
    _colorGates[#_colorGates].bot = cursorY

    _, height = W:Spacer(hostFrame, cursorY, 20)
    cursorY = cursorY - height

    -------------------------------------------------------------------
    --  POWER COLORS section
    -------------------------------------------------------------------
    _, height = W:SectionHeader(hostFrame, "POWER COLORS", cursorY)
    cursorY = cursorY - height
    AddSourceRow("power")

    local POWER_ORDER = {
        "MANA",
        "RAGE",
        "FOCUS",
        "ENERGY",
        "RUNIC_POWER",
        "FURY",
        "LUNAR_POWER",
        "INSANITY",
        "MAELSTROM",
        "EBON_MIGHT",
    }
    local powerItems = {}
    for _, pk in ipairs(POWER_ORDER) do
        -- Power names are Blizzard global strings (already localized); fall back to our English labels for non-standard entries (e.g. Ebon Might).
        local labelFS = _G[pk] or POWER_LABELS[pk] or pk
        local def = DEFAULT_POWER_COLORS[pk] or { r = 1, g = 1, b = 1 }
        powerItems[#powerItems + 1] = {
            label = CUI.L(labelFS),
            classToken = nil,
            getColor = function()
                local saved = GetCustomColorsDB()
                if saved.power and saved.power[pk] then return saved.power[pk] end
                return { r = def.r, g = def.g, b = def.b }
            end,
            setColor = function(c) SaveColorEntry("power", pk, c) end,
            resetFn = function() CUI.ResetPowerColor(pk) end,
        }
    end

    height = BuildColorGrid(hostFrame, cursorY, powerItems)
    cursorY = cursorY - height
    _colorGates[#_colorGates].bot = cursorY

    _, height = W:Spacer(hostFrame, cursorY, 20)
    cursorY = cursorY - height

    -------------------------------------------------------------------
    --  CLASS RESOURCE COLORS section -- standalone swatches mirroring the
    --  POWER COLORS pattern, saved under the "classResource" custom-colors category (not yet consumed).
    -------------------------------------------------------------------
    _, height = W:SectionHeader(hostFrame, "CLASS RESOURCE COLORS", cursorY)
    cursorY = cursorY - height
    AddSourceRow("classResource")
    do
        -- Order + labels only; defaults live in the shared DEFAULT_CLASS_RESOURCE_COLORS, the source the resource bar's "Class Resource
        -- Color" fill mode reads.
        local itemList = {
            { key = "ComboPoints", label = "Combo Points" },
            { key = "Runes", label = "Runes" },
            { key = "SoulShards", label = "Soul Shards" },
            { key = "HolyPower", label = "Holy Power" },
            { key = "ArcaneCharges", label = "Arcane Charges" },
            { key = "Icicles", label = "Icicles" },
            { key = "Chi", label = "Chi" },
            { key = "Essence", label = "Essence" },
            { key = "SoulFragments", label = "Soul Fragments" },
            { key = "MaelstromWeapon", label = "Maelstrom Weapon" },
            { key = "TipOfTheSpear", label = "Tip of the Spear" },
            { key = "WhirlwindStacks", label = "Whirlwind Stacks" },
            { key = "SweepingStrikes", label = "Sweeping Strikes" },
        }
        local resourceItems = {}
        for _, it in ipairs(itemList) do
            local key = it.key
            resourceItems[#resourceItems + 1] = {
                label = CUI.L(it.label),
                getColor = function() return CUI.GetClassResourceColor(key) or { r = 1, g = 1, b = 1 } end,
                setColor = function(c) SaveColorEntry("classResource", key, c) end,
                resetFn = function()
                    local cdb = GetCustomColorsDB()
                    if cdb.classResource then cdb.classResource[key] = nil end
                end,
            }
        end
        height = BuildColorGrid(hostFrame, cursorY, resourceItems)
    end
    cursorY = cursorY - height
    _colorGates[#_colorGates].bot = cursorY

    _, height = W:Spacer(hostFrame, cursorY, 20)
    cursorY = cursorY - height

    -- Colour-edit gate: a GLOBAL-mode section takes its palette from ONE profile, so its editing is blocked while viewing any other. ONE
    -- overlay PER SECTION, sized to that section's grid, judged by that section's own setting. Always created; a shared refresh callback
    -- shows/hides them and updates the message, so they stay correct after a profile or source change even on a cached page.
    do
        local gates = {}
        local CPAD = CUI.CONTENT_PAD or 20 -- side inset so the overlay matches the grid content width
        local function MakeColorGate(section, topY, botY)
            if not topY or not botY then return end
            local shade = CreateFrame("Frame", nil, hostFrame)
            shade:SetPoint("TOPLEFT", hostFrame, "TOPLEFT", CPAD, topY)
            shade:SetPoint("TOPRIGHT", hostFrame, "TOPRIGHT", -CPAD, topY)
            shade:SetHeight(math.abs(botY - topY))
            shade:SetFrameLevel(hostFrame:GetFrameLevel() + 100)
            shade:EnableMouse(true)
            shade:Hide()
            local texture = shade:CreateTexture(nil, "OVERLAY")
            texture:SetAllPoints()
            texture:SetColorTexture(17 / 255, 15 / 255, 12 / 255, 0.98)
            local msg = CUI.MakeFont(shade, 13, nil, 1, 1, 1)
            msg:SetTextColor(1, 1, 1, 0.56)
            msg:SetWidth(hostFrame:GetWidth() - 100)
            msg:SetJustifyH("CENTER")
            msg:SetPoint("CENTER", shade, "CENTER", 0, 0)
            shade._msg = msg
            shade._section = section
            gates[#gates + 1] = shade
        end
        for _, g in ipairs(_colorGates) do
            MakeColorGate(g.section, g.top, g.bot)
        end
        local function UpdateColorGate()
            for _, shade in ipairs(gates) do
                if CUI.IsColorEditingLocked(shade._section) then
                    local srcName = CUI.ColorSectionPullFrom(shade._section) or ""
                    shade._msg:SetText(
                        CUI.Lf(
                            'Colors are shared globally from the "%1$s" profile.\nSwitch to it (or set Pull Colors From to this profile) to edit.',
                            srcName
                        )
                    )
                    shade:Show()
                else
                    shade:Hide()
                end
            end
        end
        UpdateColorGate()
        CUI.RegisterWidgetRefresh(UpdateColorGate)
    end

    return math.abs(cursorY)
end
