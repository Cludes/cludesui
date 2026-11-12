if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_Tank_Options.lua
--  The Tank Kit pages of the CludesUI settings panel: Frame, Alerts, Tools.
--  Every setting reads and writes the module's own saved table (ns.DB()) and
--  calls the module's refresh functions, so a change shows on the frame at once.
-------------------------------------------------------------------------------
local ADDON_NAME = "CludesUITank"
local ns = CludesUI._ModuleNS[ADDON_NAME]  -- module namespace (published by the module at its load)
if not ns then return end  -- module disabled: no options page

local PAGE_FRAME  = "Frame"
local PAGE_ALERTS = "Alerts"
local PAGE_TOOLS  = "Tools"

local GLOBAL_FONT = "__global"   -- dropdown key for "use the CludesUI font"

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if not CludesUI or not CludesUI.RegisterModule then return end

    local K = ns.K
    local function DB() return ns.DB() end
    local function Frame() return _G.CoTankAuras end
    local function Round(v) return math.floor(v + 0.5) end

    -- A blank right-hand slot.
    local EMPTY = { type = "label", text = "" }

    -- Rebuilds the open page after a change that adds or removes rows.
    local function Rebuild()
        CludesUI:InvalidatePageCache()
        CludesUI:RefreshPage(true)
    end

    local function IconsChanged()
        ns.RefreshAllIconSettings()
        local f = Frame()
        if ns.isTestMode and f then f:UpdateDebuffs() end
    end

    -- { values, order } for a dropdown, from one of the module's {id, label} lists.
    local function Choices(list)
        local values, order = {}, {}
        for _, item in ipairs(list) do
            values[item.id] = item.label
            order[#order + 1] = item.id
        end
        return values, order
    end

    -- A slider bound to one numeric setting.
    local function Slider(text, key, default, min, max, step, apply, tooltip)
        return { type = "slider", text = text, min = min, max = max, step = step or 1, tooltip = tooltip,
            getValue = function() return ns.SettingNumber(key, default) end,
            setValue = function(v)
                DB()[key] = Round(v)
                if apply then apply(Round(v)) end
            end }
    end

    -- A switch bound to one on/off setting.
    local function Toggle(text, key, apply, tooltip)
        return { type = "toggle", text = text, tooltip = tooltip,
            getValue = function() return DB()[key] and true or false end,
            setValue = function(v)
                DB()[key] = v and true or false
                if apply then apply(v) end
            end }
    end

    -- A colour picker bound to one of the module's text colours.
    local function Colour(text, key, apply)
        return { type = "colorpicker", text = text, hasAlpha = false,
            getValue = function() return ns.FontColor(key) end,
            setValue = function(r, g, b)
                ns.SetFontColor(key, r, g, b)
                if apply then apply() end
            end }
    end

    ---------------------------------------------------------------------------
    --  Frame page
    ---------------------------------------------------------------------------
    local function BuildFramePage(_, parent, yOffset)
        local W = CludesUI.Widgets
        local y = yOffset
        local _, h

        CludesUI:ClearContentHeader()

        _, h = W:SectionHeader(parent, "TEXT", y);  y = y - h

        local fontValues, fontOrder = { [GLOBAL_FONT] = "CludesUI Global Font" }, { GLOBAL_FONT }
        for _, f in ipairs(ns.FontList()) do
            fontValues[f.id] = f.label
            fontOrder[#fontOrder + 1] = f.id
        end
        local flagValues, flagOrder = Choices(K.FONT_FLAGS)
        _, h = W:DualRow(parent, y,
            { type = "dropdown", text = "Font", values = fontValues, order = fontOrder,
              tooltip = "CludesUI Global Font follows the font chosen under Global Settings > Fonts.",
              getValue = function() return DB().fontFace or GLOBAL_FONT end,
              setValue = function(v)
                  DB().fontFace = (v ~= GLOBAL_FONT) and v or nil
                  ns.RefreshAllFonts()
              end },
            { type = "dropdown", text = "Font Outline", values = flagValues, order = flagOrder,
              getValue = function() return DB().fontFlags or "OUTLINE" end,
              setValue = function(v) DB().fontFlags = v; ns.RefreshAllFonts() end }
        );  y = y - h

        _, h = W:DualRow(parent, y,
            Slider("Name Size", "nameFontSize", K.DEFAULT_NAME_FONT_SIZE, K.MIN_FONT_SIZE, K.MAX_FONT_SIZE, 1, ns.RefreshAllFonts),
            Slider("Health Text Size", "hpFontSize", K.DEFAULT_HP_FONT_SIZE, K.MIN_FONT_SIZE, K.MAX_FONT_SIZE, 1, ns.RefreshAllFonts)
        );  y = y - h

        _, h = W:DualRow(parent, y,
            Colour("Name Colour", "nameTextColor", ns.RefreshAllFonts),
            Colour("Health Text Colour", "hpTextColor", ns.RefreshAllFonts)
        );  y = y - h

        _, h = W:SectionHeader(parent, "FRAME SIZE", y);  y = y - h

        _, h = W:DualRow(parent, y,
            Slider("Width", "frameWidth", K.DEFAULT_WIDTH, K.MIN_WIDTH, K.MAX_WIDTH, 5, function(v)
                local f = Frame()
                if f and not InCombatLockdown() then f:SetWidth(v); f:FitNameToWidth() end
            end),
            Slider("Height", "frameHeight", K.DEFAULT_HEIGHT, K.MIN_HEIGHT, K.MAX_HEIGHT, 5, function(v)
                local f = Frame()
                if f and not InCombatLockdown() then f:SetHeight(v) end
                ns.RefreshAuraContainerLayout(f)
                ns.RestyleAuraButtons()
            end)
        );  y = y - h

        _, h = W:SectionHeader(parent, "CO-TANK DEBUFFS", y);  y = y - h

        local filterValues, filterOrder = Choices(K.DEBUFF_FILTER_MODES)
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Show Co-Tank Debuffs",
              tooltip = "The row of harmful effects on your co-tank.",
              getValue = function() return ns.DebuffsEnabled() end,
              setValue = function(v)
                  if (ns.DebuffsEnabled() and true or false) ~= (v and true or false) then ns.ToggleDebuffs() end
              end },
            { type = "dropdown", text = "Debuffs to Show", values = filterValues, order = filterOrder,
              tooltip = "The game applies this filter itself, so it holds during boss fights.",
              getValue = function() return DB().debuffFilter or "ALL" end,
              setValue = function(v) DB().debuffFilter = v; ns.RefreshDebuffFilter() end }
        );  y = y - h

        _, h = W:DualRow(parent, y,
            Slider("Debuff Icons", "maxDebuffs", K.DEBUFF_DEFAULT_COUNT, K.DEBUFF_MIN_COUNT, K.DEBUFF_MAX_COUNT, 1, function(v)
                local f = Frame()
                if f then
                    f:UpdateAndRefreshDebuffLayout(v)
                    if ns.isTestMode then f:ShowMockDebuffs() end
                end
            end),
            Slider("Debuff Icon Gap", "debuffSpacing", K.DEBUFF_SPACING, K.ICON_SPACING_MIN, K.ICON_SPACING_MAX, 1, ns.RefreshDebuffSpacing)
        );  y = y - h

        _, h = W:DualRow(parent, y,
            Slider("Highlight at Stacks", "stackHighlightAt", K.STACK_HIGHLIGHT_DEFAULT, K.STACK_HIGHLIGHT_MIN, K.STACK_HIGHLIGHT_MAX, 1, IconsChanged,
                "A debuff that reaches this many stacks gets a coloured border. 0 turns it off."),
            Colour("Highlight Colour", "stackHighlightColor", IconsChanged)
        );  y = y - h

        _, h = W:DualRow(parent, y,
            Toggle("Alert Text at That Stack Count", "stackBanner", IconsChanged,
                "Shows the alert text on screen when a debuff reaches the highlight stack count."),
            Toggle("Colour Borders by Debuff Type", "debuffTypeBorders", IconsChanged)
        );  y = y - h

        _, h = W:DualRow(parent, y,
            Toggle("Hide Icon Tooltips in Combat", "hideTooltipsInCombat", IconsChanged),
            Slider("Defensive Icons", "maxDefensives", K.BIG_DEFENSIVES_DEFAULT_COUNT, K.BIG_DEFENSIVES_MIN_COUNT, K.BIG_DEFENSIVES_MAX_COUNT, 1, function(v)
                local f = Frame()
                if f then
                    f:UpdateAndRefreshDefensiveLayout(v)
                    if ns.isTestMode then f:UpdateBigDefensives() end
                end
            end, "Your co-tank's active defensive cooldowns. 0 hides the row.")
        );  y = y - h

        _, h = W:SectionHeader(parent, "ICON LABELS", y);  y = y - h

        local posValues, posOrder = Choices(K.STACK_COUNT_POSITIONS)
        _, h = W:DualRow(parent, y,
            Slider("Stack Count Size", "stackCountSize", K.STACK_COUNT_DEFAULT_SIZE, K.STACK_COUNT_MIN_SIZE, K.STACK_COUNT_MAX_SIZE, 1, ns.RefreshAllIconSettings,
                "0 hides the stack count."),
            { type = "dropdown", text = "Stack Count Position", values = posValues, order = posOrder,
              getValue = function() return DB().stackCountPos or "BR_IN" end,
              setValue = function(v) DB().stackCountPos = v; ns.RefreshAllIconSettings() end }
        );  y = y - h

        _, h = W:DualRow(parent, y,
            Slider("Stack Count Nudge X", "stackCountNudgeX", 0, K.STACK_NUDGE_MIN, K.STACK_NUDGE_MAX, 1, ns.RefreshAllIconSettings),
            Slider("Stack Count Nudge Y", "stackCountNudgeY", 0, K.STACK_NUDGE_MIN, K.STACK_NUDGE_MAX, 1, ns.RefreshAllIconSettings)
        );  y = y - h

        _, h = W:DualRow(parent, y,
            { type = "dropdown", text = "Timer Position",
              values = { icon = "On Icon", above = "Above Icon" }, order = { "icon", "above" },
              getValue = function() return DB().cdAbove and "above" or "icon" end,
              setValue = function(v) DB().cdAbove = (v == "above"); ns.RefreshAllIconSettings() end },
            Slider("On-Icon Timer Scale", "cdFontScale", K.CD_FONT_SCALE_DEFAULT, K.CD_FONT_SCALE_MIN, K.CD_FONT_SCALE_MAX, 1, ns.RefreshAllIconSettings,
                "0 hides the timer on the icon. 10 is full size.")
        );  y = y - h

        _, h = W:DualRow(parent, y,
            Slider("Above-Icon Timer Size", "timerTextSize", K.TIMER_TEXT_DEFAULT_SIZE, K.TIMER_TEXT_MIN_SIZE, K.TIMER_TEXT_MAX_SIZE, 1, ns.RefreshAllIconSettings),
            EMPTY
        );  y = y - h

        _, h = W:DualRow(parent, y,
            Colour("Stack Count Colour", "stackCountColor", ns.RefreshAllFonts),
            Colour("Timer Colour", "timerTextColor", ns.RefreshAllFonts)
        );  y = y - h

        _, h = W:SectionHeader(parent, "PRIVATE AURAS", y);  y = y - h

        local growValues, growOrder = Choices(K.PRIVATE_AURA_GROW_DIRECTIONS)
        _, h = W:DualRow(parent, y,
            Slider("Private Aura Slots", "maxPrivateAuras", K.PRIVATE_AURAS_DEFAULT_COUNT, K.PRIVATE_AURAS_MIN_COUNT, K.PRIVATE_AURAS_MAX_COUNT, 1, function(v)
                local f = Frame()
                if f then
                    f:UpdateAndRefreshAuraLayout(v)
                    if ns.isTestMode then f:ShowMockPrivateAuras() end
                end
            end, "Boss effects the game draws itself, shown above the frame."),
            Slider("Private Aura Size", "privateAuraSize", K.PRIVATE_AURA_SIZE_DEFAULT, K.PRIVATE_AURA_SIZE_MIN, K.PRIVATE_AURA_SIZE_MAX, 2, function()
                ns.RefreshPrivateAuraSize()
                local f = Frame()
                if ns.isTestMode and f then f:ShowMockPrivateAuras() end
            end)
        );  y = y - h

        _, h = W:DualRow(parent, y,
            { type = "dropdown", text = "Grow Direction", values = growValues, order = growOrder,
              getValue = function() return DB().privateAuraGrowDir or "LEFT" end,
              setValue = function(v) DB().privateAuraGrowDir = v; ns.RefreshPrivateAuraGrow() end },
            Slider("Private Aura Gap", "privateAuraSpacing", K.DEBUFF_SPACING, K.ICON_SPACING_MIN, K.ICON_SPACING_MAX, 1, ns.RefreshPrivateAuraSpacing)
        );  y = y - h

        _, h = W:DualRow(parent, y,
            Slider("Border Scale", "privateAuraBorderScale", K.PRIVATE_AURA_BORDER_SCALE_DEFAULT, K.PRIVATE_AURA_BORDER_SCALE_MIN, K.PRIVATE_AURA_BORDER_SCALE_MAX, 1, ns.RefreshPrivateAuraGrow,
                "0 hides the border."),
            Slider("Stack and Timer Scale", "privateAuraStackScale", K.PRIVATE_AURA_STACK_SCALE_DEFAULT, K.PRIVATE_AURA_STACK_SCALE_MIN, K.PRIVATE_AURA_STACK_SCALE_MAX, 1, ns.RefreshPrivateAuraGrow)
        );  y = y - h

        return math.abs(y)
    end

    ---------------------------------------------------------------------------
    --  Alerts page
    ---------------------------------------------------------------------------
    local function ResyncSounds()
        local f = Frame()
        ns.Alert:RegisterAuraSounds(f and f:GetAttribute("unit"))
    end

    -- One alert: a switch on the left, its stack threshold on the right.
    local function AlertRow(W, parent, y, label, key, tooltip)
        local function Entry()
            local alerts = DB().spellAlerts
            return alerts and alerts[key]
        end
        local _, h = W:DualRow(parent, y,
            { type = "toggle", text = label, tooltip = tooltip,
              getValue = function() local a = Entry(); return a and a.enabled and true or false end,
              setValue = function(v)
                  local db = DB()
                  db.spellAlerts = db.spellAlerts or {}
                  db.spellAlerts[key] = db.spellAlerts[key] or { threshold = 1 }
                  db.spellAlerts[key].enabled = v and true or false
                  ResyncSounds()
              end },
            { type = "slider", text = "Alert at Stacks", min = 1, max = 20, step = 1,
              getValue = function() local a = Entry(); return (a and tonumber(a.threshold)) or 1 end,
              setValue = function(v)
                  local a = Entry()
                  if a then a.threshold = Round(v) end
              end })
        return h
    end

    local function BuildAlertsPage(_, parent, yOffset)
        local W = CludesUI.Widgets
        local y = yOffset
        local _, h
        local db = DB()

        CludesUI:ClearContentHeader()
        ns.SpellData.SeedDefaults(db)

        _, h = W:SectionHeader(parent, "ALERT", y);  y = y - h

        _, h = W:DualRow(parent, y,
            { type = "input", text = "Alert Text", inputWidth = 170, placeholder = "TAUNT",
              tooltip = "The words shown on screen when an alert fires. Press Enter to save.",
              getValue = function() return DB().alertText or "TAUNT" end,
              setValue = function(text) ns.Alert:SetText(text) end },
            { type = "slider", text = "Alert Text Size", min = 12, max = 48, step = 1,
              getValue = function() return ns.SettingNumber("alertTextSize", 22) end,
              setValue = function(v) ns.Alert:SetTextSize(Round(v)) end }
        );  y = y - h

        _, h = W:DualRow(parent, y,
            { type = "labeledButton", text = "Try the Alert", buttonText = "Test", width = 90,
              tooltip = "Fires the flash, sound and text once.",
              onClick = function() ns.Alert:Test() end },
            { type = "input", text = "Add a Spell ID", inputStyle = "popup", placeholder = "Spell ID", inputWidth = 110,
              tooltip = "Type the spell ID of a tank debuff and press Enter. It is added below at 1 stack; change the count there.",
              getValue = function() return "" end,
              setValue = function(text)
                  local sid = tonumber(text)
                  if not sid or sid <= 0 then return end
                  sid = math.floor(sid)
                  local d = DB()
                  d.spellAlerts = d.spellAlerts or {}
                  local existing = d.spellAlerts[sid]
                  d.spellAlerts[sid] = { enabled = true,
                      threshold = (existing and existing.threshold) or 1,
                      preset = ns.SpellData.IsPreset(sid) or nil }
                  ResyncSounds()
                  Rebuild()
              end }
        );  y = y - h

        local custom = ns.SpellData.CustomAlerts(db)
        if #custom > 0 then
            _, h = W:SectionHeader(parent, "YOUR ALERTS", y);  y = y - h
            for _, entry in ipairs(custom) do
                local name = ns.Alert.SpellName(entry.id) or ("Spell " .. entry.id)
                y = y - AlertRow(W, parent, y, name, entry.key, "Spell ID " .. entry.id)
                _, h = W:DualRow(parent, y,
                    { type = "labeledButton", text = "Remove " .. name, buttonText = "Remove", width = 90,
                      onClick = function()
                          local alerts = DB().spellAlerts
                          if alerts then alerts[entry.key] = nil end
                          ResyncSounds()
                          Rebuild()
                      end },
                    EMPTY
                );  y = y - h
            end
        end

        for _, raid in ipairs(ns.SpellData.raids) do
            _, h = W:SectionHeader(parent, raid.name:upper(), y);  y = y - h
            for _, boss in ipairs(raid.bosses) do
                for _, spell in ipairs(boss.spells) do
                    local label = boss.name .. ": " .. spell.name
                    y = y - AlertRow(W, parent, y, label, spell.id,
                        (spell.note and (spell.note .. ". ") or "") .. "Spell ID " .. spell.id)
                end
            end
        end

        return math.abs(y)
    end

    ---------------------------------------------------------------------------
    --  Tools page
    ---------------------------------------------------------------------------
    local function BuildToolsPage(_, parent, yOffset)
        local W = CludesUI.Widgets
        local y = yOffset
        local _, h

        CludesUI:ClearContentHeader()

        _, h = W:SectionHeader(parent, "FRAME", y);  y = y - h

        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Test Mode",
              tooltip = "Shows the frame on yourself with sample debuffs, so you can set it up without a co-tank. Not available in combat.",
              getValue = function() return ns.isTestMode and true or false end,
              setValue = function(v)
                  if not ns.SetTestMode(v and true or false) then Rebuild() end
              end },
            Toggle("Lock Frame", "frameLocked", nil, "Stops the frame being dragged. Unlocked, drag it with the left mouse button.")
        );  y = y - h

        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Click-Through",
              tooltip = "The frame ignores the mouse. Not available in combat.",
              getValue = function() return DB().clickThrough and true or false end,
              setValue = function(v)
                  if InCombatLockdown() then Rebuild(); return end
                  DB().clickThrough = v and true or false
                  local f = Frame()
                  if f then f:EnableMouse(not v) end
              end },
            { type = "labeledButton", text = "Frame Position", buttonText = "Reset", width = 90,
              tooltip = "Moves the frame back to the middle of the screen. Not available in combat.",
              onClick = function()
                  local f = Frame()
                  if f and not InCombatLockdown() then ns.ResetPosition(f) end
              end }
        );  y = y - h

        _, h = W:SectionHeader(parent, "CO-TANK", y);  y = y - h

        local pinned = DB().pinnedTank
        local found = ns.FindCoTank()
        local foundName = found and UnitName(found)
        local status = pinned and ("Pinned: " .. pinned)
            or ("Auto-detect: " .. ((type(foundName) == "string" and foundName) or "none found"))
        _, h = W:DualRow(parent, y,
            { type = "input", text = "Pin a Co-Tank by Name", inputWidth = 170, placeholder = "Player name",
              tooltip = status .. ". Pin a player when there are more than two tanks in the group. Press Enter to save.",
              getValue = function() return DB().pinnedTank or "" end,
              setValue = function(text)
                  text = text and text:match("^%s*(.-)%s*$") or ""
                  DB().pinnedTank = (text ~= "") and text or nil
                  Rebuild()
              end },
            { type = "labeledButton", text = status, buttonText = pinned and "Unpin" or "Pin Current", width = 110,
              onClick = function()
                  if DB().pinnedTank then
                      DB().pinnedTank = nil
                  else
                      local unit = ns.FindCoTank()
                      local name = unit and UnitName(unit)
                      if type(name) == "string" then DB().pinnedTank = name end
                  end
                  Rebuild()
              end }
        );  y = y - h

        return math.abs(y)
    end

    ---------------------------------------------------------------------------
    --  Register the module
    ---------------------------------------------------------------------------
    CludesUI:RegisterModule(ADDON_NAME, {
        title       = "Tank Kit",
        description = "For tanks: your co-tank's health, debuffs and defensives, and TAUNT alerts.",
        pages       = { PAGE_FRAME, PAGE_ALERTS, PAGE_TOOLS },
        buildPage   = function(pageName, parent, yOffset)
            if pageName == PAGE_FRAME then return BuildFramePage(pageName, parent, yOffset) end
            if pageName == PAGE_ALERTS then return BuildAlertsPage(pageName, parent, yOffset) end
            if pageName == PAGE_TOOLS then return BuildToolsPage(pageName, parent, yOffset) end
        end,
        onReset = function()
            if InCombatLockdown() then return end
            wipe(ns.DB())
            ns.SpellData.SeedDefaults(ns.DB())
            local f = Frame()
            if f then ns.ResetPosition(f) end
            CludesUI:InvalidatePageCache()
            ReloadUI()
        end,
    })

    -- /ctank and /tankkit live in the module (CludesUITank/Core.lua) and open these pages.
end)
-- LoadOnDemand: this addon loads after PLAYER_LOGIN, so the event above will never fire; run the init now.
if IsLoggedIn() then initFrame:GetScript("OnEvent")(initFrame) end
