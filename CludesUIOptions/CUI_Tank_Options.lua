if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_Tank_Options.lua
--  The Tank Kit pages of the CludesUI settings panel: Frame, Alerts, Tools.
--  Every setting reads and writes the module's own saved table (ns.DB()) and
--  calls the module's refresh functions, so a change shows on the frame at once.
-------------------------------------------------------------------------------
local ADDON_NAME = "CludesUITank"
local mod = CludesUI._ModuleNS[ADDON_NAME] -- module namespace (published by the module at its load)
if not mod then
    return
end -- module disabled: no options page

local PAGE_FRAME = "Frame"
local PAGE_ALERTS = "Alerts"
local PAGE_TOOLS = "Tools"

local GLOBAL_FONT = "__global" -- dropdown key for "use the CludesUI font"

CludesUI.AtOptionsLogin(function()

    local K = mod.K
    local function DB()
        return mod.DB()
    end
    local function Frame()
        return _G.CoTankAuras
    end
    local function Round(val)
        return math.floor(val + 0.5)
    end

    -- A blank right-hand slot.
    local EMPTY = { type = "label", text = "" }

    -- Rebuilds the open page after a change that adds or removes rows.
    local function Rebuild()
        CludesUI:InvalidatePageCache()
        CludesUI:RefreshPage(true)
    end

    local function IconsChanged()
        mod.RefreshAllIconSettings()
        local f = Frame()
        if mod.isTestMode and f then
            f:UpdateDebuffs()
        end
    end

    -- { values, order } for a dropdown, from one of the module's {id, label} lists.
    local function Choices(entries)
        local values, sequence = {}, {}
        for _, entry in ipairs(entries) do
            values[entry.id] = entry.label
            sequence[#sequence + 1] = entry.id
        end
        return values, sequence
    end

    -- A slider bound to one numeric setting.
    local function Slider(textValue, key, default, min, max, step, apply, tooltip)
        return {
            type = "slider",
            text = textValue,
            min = min,
            max = max,
            step = step or 1,
            tooltip = tooltip,
            getValue = function()
                return mod.SettingNumber(key, default)
            end,
            setValue = function(val)
                DB()[key] = Round(val)
                if apply then
                    apply(Round(val))
                end
            end,
        }
    end

    -- A switch bound to one on/off setting.
    local function Toggle(textValue, key, apply, tooltip)
        return {
            type = "toggle",
            text = textValue,
            tooltip = tooltip,
            getValue = function()
                return DB()[key] and true or false
            end,
            setValue = function(val)
                DB()[key] = val and true or false
                if apply then
                    apply(val)
                end
            end,
        }
    end

    -- A colour picker bound to one of the module's text colours.
    local function Colour(textValue, key, apply)
        return {
            type = "colorpicker",
            text = textValue,
            hasAlpha = false,
            getValue = function()
                return mod.FontColor(key)
            end,
            setValue = function(r, g, b)
                mod.SetFontColor(key, r, g, b)
                if apply then
                    apply()
                end
            end,
        }
    end

    ---------------------------------------------------------------------------
    --  Frame page
    ---------------------------------------------------------------------------
    local function BuildFramePage(_, hostFrame, yOffset)
        local W = CludesUI.Widgets
        local cursorY = yOffset
        local _, height

        CludesUI:ClearContentHeader()

        _, height = W:SectionHeader(hostFrame, "TEXT", cursorY)
        cursorY = cursorY - height

        local fontValues, fontOrder = { [GLOBAL_FONT] = "CludesUI Global Font" }, { GLOBAL_FONT }
        for _, f in ipairs(mod.FontList()) do
            fontValues[f.id] = f.label
            fontOrder[#fontOrder + 1] = f.id
        end
        local flagValues, flagOrder = Choices(K.FONT_FLAGS)
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "dropdown",
            text = "Font",
            values = fontValues,
            order = fontOrder,
            tooltip = "CludesUI Global Font follows the font chosen under Global Settings > Fonts.",
            getValue = function()
                return DB().fontFace or GLOBAL_FONT
            end,
            setValue = function(val)
                DB().fontFace = (val ~= GLOBAL_FONT) and val or nil
                mod.RefreshAllFonts()
            end,
        }, {
            type = "dropdown",
            text = "Font Outline",
            values = flagValues,
            order = flagOrder,
            getValue = function()
                return DB().fontFlags or "OUTLINE"
            end,
            setValue = function(val)
                DB().fontFlags = val
                mod.RefreshAllFonts()
            end,
        })
        cursorY = cursorY - height

        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Slider(
                "Name Size",
                "nameFontSize",
                K.DEFAULT_NAME_FONT_SIZE,
                K.MIN_FONT_SIZE,
                K.MAX_FONT_SIZE,
                1,
                mod.RefreshAllFonts
            ),
            Slider(
                "Health Text Size",
                "hpFontSize",
                K.DEFAULT_HP_FONT_SIZE,
                K.MIN_FONT_SIZE,
                K.MAX_FONT_SIZE,
                1,
                mod.RefreshAllFonts
            )
        )
        cursorY = cursorY - height

        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Colour("Name Colour", "nameTextColor", mod.RefreshAllFonts),
            Colour("Health Text Colour", "hpTextColor", mod.RefreshAllFonts)
        )
        cursorY = cursorY - height

        _, height = W:SectionHeader(hostFrame, "FRAME SIZE", cursorY)
        cursorY = cursorY - height

        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Slider("Width", "frameWidth", K.DEFAULT_WIDTH, K.MIN_WIDTH, K.MAX_WIDTH, 5, function(val)
                local f = Frame()
                if f and not InCombatLockdown() then
                    f:SetWidth(val)
                    f:FitNameToWidth()
                end
            end),
            Slider("Height", "frameHeight", K.DEFAULT_HEIGHT, K.MIN_HEIGHT, K.MAX_HEIGHT, 5, function(val)
                local f = Frame()
                if f and not InCombatLockdown() then
                    f:SetHeight(val)
                end
                mod.RefreshAuraContainerLayout(f)
                mod.RestyleAuraButtons()
            end)
        )
        cursorY = cursorY - height

        _, height = W:SectionHeader(hostFrame, "CO-TANK DEBUFFS", cursorY)
        cursorY = cursorY - height

        local filterValues, filterOrder = Choices(K.DEBUFF_FILTER_MODES)
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Show Co-Tank Debuffs",
            tooltip = "The row of harmful effects on your co-tank.",
            getValue = function()
                return mod.DebuffsEnabled()
            end,
            setValue = function(val)
                if (mod.DebuffsEnabled() and true or false) ~= (val and true or false) then
                    mod.ToggleDebuffs()
                end
            end,
        }, {
            type = "dropdown",
            text = "Debuffs to Show",
            values = filterValues,
            order = filterOrder,
            tooltip = "The game applies this filter itself, so it holds during boss fights.",
            getValue = function()
                return DB().debuffFilter or "ALL"
            end,
            setValue = function(val)
                DB().debuffFilter = val
                mod.RefreshDebuffFilter()
            end,
        })
        cursorY = cursorY - height

        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Slider(
                "Debuff Icons",
                "maxDebuffs",
                K.DEBUFF_DEFAULT_COUNT,
                K.DEBUFF_MIN_COUNT,
                K.DEBUFF_MAX_COUNT,
                1,
                function(val)
                    local f = Frame()
                    if f then
                        f:UpdateAndRefreshDebuffLayout(val)
                        if mod.isTestMode then
                            f:ShowMockDebuffs()
                        end
                    end
                end
            ),
            Slider(
                "Debuff Icon Gap",
                "debuffSpacing",
                K.DEBUFF_SPACING,
                K.ICON_SPACING_MIN,
                K.ICON_SPACING_MAX,
                1,
                mod.RefreshDebuffSpacing
            )
        )
        cursorY = cursorY - height

        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Slider(
                "Highlight at Stacks",
                "stackHighlightAt",
                K.STACK_HIGHLIGHT_DEFAULT,
                K.STACK_HIGHLIGHT_MIN,
                K.STACK_HIGHLIGHT_MAX,
                1,
                IconsChanged,
                "A debuff that reaches this many stacks gets a coloured border. 0 turns it off."
            ),
            Colour("Highlight Colour", "stackHighlightColor", IconsChanged)
        )
        cursorY = cursorY - height

        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Toggle(
                "Alert Text at That Stack Count",
                "stackBanner",
                IconsChanged,
                "Shows the alert text on screen when a debuff reaches the highlight stack count."
            ),
            Toggle("Colour Borders by Debuff Type", "debuffTypeBorders", IconsChanged)
        )
        cursorY = cursorY - height

        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Toggle("Hide Icon Tooltips in Combat", "hideTooltipsInCombat", IconsChanged),
            Slider(
                "Defensive Icons",
                "maxDefensives",
                K.BIG_DEFENSIVES_DEFAULT_COUNT,
                K.BIG_DEFENSIVES_MIN_COUNT,
                K.BIG_DEFENSIVES_MAX_COUNT,
                1,
                function(val)
                    local f = Frame()
                    if f then
                        f:UpdateAndRefreshDefensiveLayout(val)
                        if mod.isTestMode then
                            f:UpdateBigDefensives()
                        end
                    end
                end,
                "Your co-tank's active defensive cooldowns. 0 hides the row."
            )
        )
        cursorY = cursorY - height

        _, height = W:SectionHeader(hostFrame, "EXTERNALS ON YOU", cursorY)
        cursorY = cursorY - height

        local EXT = mod.EXT
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            {
                type = "toggle",
                text = "Show Externals on You",
                tooltip = "A row of the big defensives other players put on you, such as Pain Suppression or Ironbark. It shows only in a tank spec. Move it in Layout Mode.",
                getValue = function()
                    return mod.ExternalsEnabled()
                end,
                setValue = function(val)
                    DB().extEnabled = val and true or false
                    mod.RefreshExternals()
                end,
            },
            Slider(
                "Icons",
                "extCount",
                EXT.DEFAULT_COUNT,
                0,
                EXT.MAX_COUNT,
                1,
                mod.RefreshExternals,
                "How many externals the row can show at once. 0 hides it."
            )
        )
        cursorY = cursorY - height

        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Slider("Icon Size", "extSize", EXT.DEFAULT_SIZE, EXT.MIN_SIZE, EXT.MAX_SIZE, 1, function()
                mod.RefreshExternals()
                mod.RestyleAuraButtons()
            end),
            Slider(
                "Icon Gap",
                "extSpacing",
                K.DEBUFF_SPACING,
                K.ICON_SPACING_MIN,
                K.ICON_SPACING_MAX,
                1,
                mod.RefreshExternals
            )
        )
        cursorY = cursorY - height

        _, height = W:SectionHeader(hostFrame, "ICON LABELS", cursorY)
        cursorY = cursorY - height

        local posValues, posOrder = Choices(K.STACK_COUNT_POSITIONS)
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Slider(
                "Stack Count Size",
                "stackCountSize",
                K.STACK_COUNT_DEFAULT_SIZE,
                K.STACK_COUNT_MIN_SIZE,
                K.STACK_COUNT_MAX_SIZE,
                1,
                mod.RefreshAllIconSettings,
                "0 hides the stack count."
            ),
            {
                type = "dropdown",
                text = "Stack Count Position",
                values = posValues,
                order = posOrder,
                getValue = function()
                    return DB().stackCountPos or "BR_IN"
                end,
                setValue = function(val)
                    DB().stackCountPos = val
                    mod.RefreshAllIconSettings()
                end,
            }
        )
        cursorY = cursorY - height

        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Slider(
                "Stack Count Nudge X",
                "stackCountNudgeX",
                0,
                K.STACK_NUDGE_MIN,
                K.STACK_NUDGE_MAX,
                1,
                mod.RefreshAllIconSettings
            ),
            Slider(
                "Stack Count Nudge Y",
                "stackCountNudgeY",
                0,
                K.STACK_NUDGE_MIN,
                K.STACK_NUDGE_MAX,
                1,
                mod.RefreshAllIconSettings
            )
        )
        cursorY = cursorY - height

        _, height = W:DualRow(
            hostFrame,
            cursorY,
            {
                type = "segmented",
                text = "Timer Position",
                values = { icon = "On Icon", above = "Above Icon" },
                order = { "icon", "above" },
                getValue = function()
                    return DB().cdAbove and "above" or "icon"
                end,
                setValue = function(val)
                    DB().cdAbove = (val == "above")
                    mod.RefreshAllIconSettings()
                end,
            },
            Slider(
                "On-Icon Timer Scale",
                "cdFontScale",
                K.CD_FONT_SCALE_DEFAULT,
                K.CD_FONT_SCALE_MIN,
                K.CD_FONT_SCALE_MAX,
                1,
                mod.RefreshAllIconSettings,
                "0 hides the timer on the icon. 10 is full size."
            )
        )
        cursorY = cursorY - height

        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Slider(
                "Above-Icon Timer Size",
                "timerTextSize",
                K.TIMER_TEXT_DEFAULT_SIZE,
                K.TIMER_TEXT_MIN_SIZE,
                K.TIMER_TEXT_MAX_SIZE,
                1,
                mod.RefreshAllIconSettings
            ),
            EMPTY
        )
        cursorY = cursorY - height

        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Colour("Stack Count Colour", "stackCountColor", mod.RefreshAllFonts),
            Colour("Timer Colour", "timerTextColor", mod.RefreshAllFonts)
        )
        cursorY = cursorY - height

        _, height = W:SectionHeader(hostFrame, "PRIVATE AURAS", cursorY)
        cursorY = cursorY - height

        local growValues, growOrder = Choices(K.PRIVATE_AURA_GROW_DIRECTIONS)
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Slider(
                "Private Aura Slots",
                "maxPrivateAuras",
                K.PRIVATE_AURAS_DEFAULT_COUNT,
                K.PRIVATE_AURAS_MIN_COUNT,
                K.PRIVATE_AURAS_MAX_COUNT,
                1,
                function(val)
                    local f = Frame()
                    if f then
                        f:UpdateAndRefreshAuraLayout(val)
                        if mod.isTestMode then
                            f:ShowMockPrivateAuras()
                        end
                    end
                end,
                "Boss effects the game draws itself, shown above the frame."
            ),
            Slider(
                "Private Aura Size",
                "privateAuraSize",
                K.PRIVATE_AURA_SIZE_DEFAULT,
                K.PRIVATE_AURA_SIZE_MIN,
                K.PRIVATE_AURA_SIZE_MAX,
                2,
                function()
                    mod.RefreshPrivateAuraSize()
                    local f = Frame()
                    if mod.isTestMode and f then
                        f:ShowMockPrivateAuras()
                    end
                end
            )
        )
        cursorY = cursorY - height

        _, height = W:DualRow(
            hostFrame,
            cursorY,
            {
                type = "dropdown",
                text = "Grow Direction",
                values = growValues,
                order = growOrder,
                getValue = function()
                    return DB().privateAuraGrowDir or "LEFT"
                end,
                setValue = function(val)
                    DB().privateAuraGrowDir = val
                    mod.RefreshPrivateAuraGrow()
                end,
            },
            Slider(
                "Private Aura Gap",
                "privateAuraSpacing",
                K.DEBUFF_SPACING,
                K.ICON_SPACING_MIN,
                K.ICON_SPACING_MAX,
                1,
                mod.RefreshPrivateAuraSpacing
            )
        )
        cursorY = cursorY - height

        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Slider(
                "Border Scale",
                "privateAuraBorderScale",
                K.PRIVATE_AURA_BORDER_SCALE_DEFAULT,
                K.PRIVATE_AURA_BORDER_SCALE_MIN,
                K.PRIVATE_AURA_BORDER_SCALE_MAX,
                1,
                mod.RefreshPrivateAuraGrow,
                "0 hides the border."
            ),
            Slider(
                "Stack and Timer Scale",
                "privateAuraStackScale",
                K.PRIVATE_AURA_STACK_SCALE_DEFAULT,
                K.PRIVATE_AURA_STACK_SCALE_MIN,
                K.PRIVATE_AURA_STACK_SCALE_MAX,
                1,
                mod.RefreshPrivateAuraGrow
            )
        )
        cursorY = cursorY - height

        return math.abs(cursorY)
    end

    ---------------------------------------------------------------------------
    --  Alerts page
    ---------------------------------------------------------------------------
    local function ResyncSounds()
        local f = Frame()
        mod.Alert:RegisterAuraSounds(f and f:GetAttribute("unit"))
    end

    -- One alert: a switch on the left, its stack threshold on the right.
    local function AlertRow(W, hostFrame, cursorY, labelText, key, tooltip)
        local function Entry()
            local alerts = DB().spellAlerts
            return alerts and alerts[key]
        end
        local _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = labelText,
            tooltip = tooltip,
            getValue = function()
                local a = Entry()
                return a and a.enabled and true or false
            end,
            setValue = function(val)
                local saved = DB()
                saved.spellAlerts = saved.spellAlerts or {}
                saved.spellAlerts[key] = saved.spellAlerts[key] or { threshold = 1 }
                saved.spellAlerts[key].enabled = val and true or false
                ResyncSounds()
            end,
        }, {
            type = "slider",
            text = "Alert at Stacks",
            min = 1,
            max = 20,
            step = 1,
            getValue = function()
                local a = Entry()
                return (a and tonumber(a.threshold)) or 1
            end,
            setValue = function(val)
                local a = Entry()
                if a then
                    a.threshold = Round(val)
                end
            end,
        })
        return height
    end

    local function BuildAlertsPage(_, hostFrame, yOffset)
        local W = CludesUI.Widgets
        local cursorY = yOffset
        local _, height
        local saved = DB()

        CludesUI:ClearContentHeader()
        mod.SpellData.SeedDefaults(saved)

        _, height = W:SectionHeader(hostFrame, "ALERT", cursorY)
        cursorY = cursorY - height

        _, height = W:DualRow(hostFrame, cursorY, {
            type = "input",
            text = "Alert Text",
            inputWidth = 170,
            placeholder = "TAUNT",
            tooltip = "The words shown on screen when an alert fires. Press Enter to save.",
            getValue = function()
                return DB().alertText or "TAUNT"
            end,
            setValue = function(textValue)
                mod.Alert:SetText(textValue)
            end,
        }, {
            type = "slider",
            text = "Alert Text Size",
            min = 12,
            max = 48,
            step = 1,
            getValue = function()
                return mod.SettingNumber("alertTextSize", 22)
            end,
            setValue = function(val)
                mod.Alert:SetTextSize(Round(val))
            end,
        })
        cursorY = cursorY - height

        _, height = W:DualRow(hostFrame, cursorY, {
            type = "labeledButton",
            text = "Try the Alert",
            buttonText = "Test",
            width = 90,
            tooltip = "Fires the flash, sound and text once.",
            onClick = function()
                mod.Alert:Test()
            end,
        }, {
            type = "input",
            text = "Add a Spell ID",
            inputStyle = "popup",
            placeholder = "Spell ID",
            inputWidth = 110,
            tooltip = "Type the spell ID of a tank debuff and press Enter. It is added below at 1 stack; change the count there.",
            getValue = function()
                return ""
            end,
            setValue = function(textValue)
                local spellRef = tonumber(textValue)
                if not spellRef or spellRef <= 0 then
                    return
                end
                spellRef = math.floor(spellRef)
                local d = DB()
                d.spellAlerts = d.spellAlerts or {}
                local existing = d.spellAlerts[spellRef]
                d.spellAlerts[spellRef] = {
                    enabled = true,
                    threshold = (existing and existing.threshold) or 1,
                    preset = mod.SpellData.IsPreset(spellRef) or nil,
                }
                ResyncSounds()
                Rebuild()
            end,
        })
        cursorY = cursorY - height

        local custom = mod.SpellData.CustomAlerts(saved)
        if #custom > 0 then
            _, height = W:SectionHeader(hostFrame, "YOUR ALERTS", cursorY)
            cursorY = cursorY - height
            for _, record in ipairs(custom) do
                local name = mod.Alert.SpellName(record.id) or ("Spell " .. record.id)
                cursorY = cursorY - AlertRow(W, hostFrame, cursorY, name, record.key, "Spell ID " .. record.id)
                _, height = W:DualRow(hostFrame, cursorY, {
                    type = "labeledButton",
                    text = "Remove " .. name,
                    buttonText = "Remove",
                    width = 90,
                    onClick = function()
                        local alerts = DB().spellAlerts
                        if alerts then
                            alerts[record.key] = nil
                        end
                        ResyncSounds()
                        Rebuild()
                    end,
                }, EMPTY)
                cursorY = cursorY - height
            end
        end

        for _, raid in ipairs(mod.SpellData.raids) do
            _, height = W:SectionHeader(hostFrame, raid.name:upper(), cursorY)
            cursorY = cursorY - height
            for _, boss in ipairs(raid.bosses) do
                for _, spell in ipairs(boss.spells) do
                    local labelText = boss.name .. ": " .. spell.name
                    cursorY = cursorY
                        - AlertRow(
                            W,
                            hostFrame,
                            cursorY,
                            labelText,
                            spell.id,
                            (spell.note and (spell.note .. ". ") or "") .. "Spell ID " .. spell.id
                        )
                end
            end
        end

        return math.abs(cursorY)
    end

    ---------------------------------------------------------------------------
    --  Tools page
    ---------------------------------------------------------------------------
    local function BuildToolsPage(_, hostFrame, yOffset)
        local W = CludesUI.Widgets
        local cursorY = yOffset
        local _, height

        CludesUI:ClearContentHeader()

        _, height = W:SectionHeader(hostFrame, "FRAME", cursorY)
        cursorY = cursorY - height

        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Test Mode",
            tooltip = "Shows the frame on yourself with sample debuffs, so you can set it up without a co-tank. Not available in combat.",
            getValue = function()
                return mod.isTestMode and true or false
            end,
            setValue = function(val)
                if not mod.SetTestMode(val and true or false) then
                    Rebuild()
                end
            end,
        }, {
            type = "labeledButton",
            text = "Move the Co-Tank Frame and Externals",
            buttonText = "Layout Mode",
            width = 120,
            tooltip = "Opens Layout Mode, where every CludesUI frame is moved and resized.",
            onClick = function()
                if InCombatLockdown() then
                    return
                end
                CludesUI:EnsureUnlockCore()
                if CludesUI._openUnlockMode then
                    CludesUI._openUnlockMode()
                end
            end,
        })
        cursorY = cursorY - height

        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Click-Through",
            tooltip = "The frame ignores the mouse. Not available in combat.",
            getValue = function()
                return DB().clickThrough and true or false
            end,
            setValue = function(val)
                if InCombatLockdown() then
                    Rebuild()
                    return
                end
                DB().clickThrough = val and true or false
                local f = Frame()
                if f then
                    f:EnableMouse(not val)
                end
            end,
        }, {
            type = "labeledButton",
            text = "Co-Tank Frame Position",
            buttonText = "Reset",
            width = 90,
            tooltip = "Moves the co-tank frame back to the middle of the screen. Not available in combat.",
            onClick = function()
                local f = Frame()
                if f and not InCombatLockdown() then
                    mod.ResetPosition(f)
                end
            end,
        })
        cursorY = cursorY - height

        _, height = W:SectionHeader(hostFrame, "CO-TANK", cursorY)
        cursorY = cursorY - height

        local pinned = DB().pinnedTank
        local found = mod.FindCoTank()
        local foundName = found and UnitName(found)
        local status = pinned and ("Pinned: " .. pinned)
            or ("Auto-detect: " .. ((type(foundName) == "string" and foundName) or "none found"))
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "input",
            text = "Pin a Co-Tank by Name",
            inputWidth = 170,
            placeholder = "Player name",
            tooltip = status
                .. ". Pin a player when there are more than two tanks in the group. Press Enter to save.",
            getValue = function()
                return DB().pinnedTank or ""
            end,
            setValue = function(textValue)
                textValue = textValue and textValue:match("^%s*(.-)%s*$") or ""
                DB().pinnedTank = (textValue ~= "") and textValue or nil
                Rebuild()
            end,
        }, {
            type = "labeledButton",
            text = status,
            buttonText = pinned and "Unpin" or "Pin Current",
            width = 110,
            onClick = function()
                if DB().pinnedTank then
                    DB().pinnedTank = nil
                else
                    local unitToken = mod.FindCoTank()
                    local name = unitToken and UnitName(unitToken)
                    if type(name) == "string" then
                        DB().pinnedTank = name
                    end
                end
                Rebuild()
            end,
        })
        cursorY = cursorY - height

        return math.abs(cursorY)
    end

    ---------------------------------------------------------------------------
    --  Register the module
    ---------------------------------------------------------------------------
    CludesUI:RegisterModule(ADDON_NAME, {
        title = "Tank Kit",
        description = "For tanks: your co-tank's health, debuffs and defensives, and TAUNT alerts.",
        pages = { PAGE_FRAME, PAGE_ALERTS, PAGE_TOOLS },
        buildPage = function(page, hostFrame, yOffset)
            if page == PAGE_FRAME then
                return BuildFramePage(page, hostFrame, yOffset)
            end
            if page == PAGE_ALERTS then
                return BuildAlertsPage(page, hostFrame, yOffset)
            end
            if page == PAGE_TOOLS then
                return BuildToolsPage(page, hostFrame, yOffset)
            end
        end,
        onReset = function()
            if InCombatLockdown() then
                return
            end
            wipe(mod.DB())
            mod.SpellData.SeedDefaults(mod.DB())
            local f = Frame()
            if f then
                mod.ResetPosition(f)
            end
            CludesUI:InvalidatePageCache()
            ReloadUI()
        end,
    })

    -- /ctank and /tankkit live in the module (CludesUITank/Core.lua) and open these pages.
end)
