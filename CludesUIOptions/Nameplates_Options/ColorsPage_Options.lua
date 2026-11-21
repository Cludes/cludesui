if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-------------------------------------------------------------------------------
--  Nameplates_Options\ColorsPage_Options.lua
--  Nameplates options: the Colors page (BuildColorsPage) and the mini preview
--  bars of its color rows (MakeColorPreviewBar, built lazily through
--  LazyColorPreviewBar in CUI_Nameplates_Options.lua). Definitions only; the
--  shared helpers come from ns._NPO_OptEnv.
-------------------------------------------------------------------------------
local mod = CUI._ModuleNS["CludesUINameplates"]
if not mod then return end -- module disabled: no options page

-- The options page frame pool (CludesUI_FramePool.lua): frames made under a
-- pooled page part are handed back to the page's next build.
local CreateFrame = CUI._Pool.CreateFrame

-- The nameplate Threat % cog's rows (WoW Forever): get(key) reads the
-- profile, set(key, v) writes it and refreshes the text.
if CUI.IS_FOREVER then
    function mod.NPO_ThreatPctRows(get, set)
        local function Slider(colorKey, labelText, lo, hi)
            return {
                type = "slider",
                label = labelText,
                min = lo,
                max = hi,
                step = 1,
                get = function() return get(colorKey) end,
                set = function(val) set(colorKey, val) end,
            }
        end
        -- The gap colours show while the gap is picked and coloured.
        local function GapColorOff() return get("threatPctMode") ~= "gap" or not get("threatPctColorByThreat") end
        local function GapColor(colorKey, labelText, tipText)
            return {
                type = "colorpicker",
                label = labelText,
                tooltip = tipText,
                hidden = GapColorOff,
                get = function()
                    local color = get(colorKey)
                    if color then return color.r, color.g, color.b end
                    return 1, 1, 1
                end,
                set = function(red, green, blue) set(colorKey, { r = red, g = green, b = blue }) end,
            }
        end
        return {
            {
                type = "dropdown",
                label = "Text Shows",
                values = { percent = "Threat %", gap = "Threat Gap" },
                order = { "percent", "gap" },
                tooltip = "Threat Gap shows on your target's plate only.",
                get = function() return get("threatPctMode") or "percent" end,
                set = function(val) set("threatPctMode", val) end,
            },
            {
                type = "toggle",
                label = "Color by Threat",
                tooltip = "Colors the number. Off shows it in white.",
                get = function() return get("threatPctColorByThreat") end,
                set = function(val) set("threatPctColorByThreat", val) end,
            },
            GapColor("threatGapAheadColor", "Ahead Color", "When your threat is higher."),
            GapColor("threatGapBehindColor", "Behind Color", "When theirs is higher."),
            Slider("threatPctSize", "Size", 6, 20),
            Slider("threatPctXOffset", "X Offset", -300, 300),
            Slider("threatPctYOffset", "Y Offset", -300, 300),
        }
    end
end

-- CUI_DEBUFF_COLORS: the per-class debuff lists (the list kit lives in
-- CludesUINameplates_DebuffColors.lua). One expandable card
-- per class that holds an entry, its icon and its name in its class color on
-- the header; Add Class, one wide button below them, starts one. Inside, the debuffs run down the left column
-- and the combos down the right, each with up/down arrows beside its name
-- that reorder it (the higher entry wins) and an Add button closing its
-- column. Every edit reaches the plates as it is made (the runtime
-- rebuilds at most once a frame, and only for the player's own class); a
-- color drag waits for the picker to close. debuffColorAdded: the entry Add
-- just made, kept across the page rebuild Add runs so the rebuilt row
-- reports the write to Spec Overrides. debuffColorOpen: the expanded cards
-- by class token, for the session (the player's starts expanded).
local addedDebuff
local debuffColorOpen = {}
function mod.NP_BuildDebuffColorsOptions(hostFrame, cursorY)
    local DC = mod.DebuffColorKit
    if not DC then return cursorY end
    local W = CUI.Widgets
    local Pix = CUI.PanelPP
    local function Get(colorKey)
        local saved = mod.db and mod.db.profile
        if saved and saved[colorKey] ~= nil then return saved[colorKey] end
        return mod.defaults[colorKey]
    end
    local function Off() return Get("debuffColorsEnabled") ~= true end
    local function Read(classFile) return DC.Read(classFile, Get) end
    -- Every edit applies at once. The color picker writes on every frame of a
    -- drag, so while it is open the refresh waits for it to close.
    local function ApplyColors()
        if CUI._colorPickerOpen then
            CUI._deferredDriftChecks = CUI._deferredDriftChecks or {}
            CUI._deferredDriftChecks[mod.DebuffColors_RequestRefresh] = true
        else
            mod.DebuffColors_RequestRefresh()
        end
    end
    -- rgn: the row reporting the write to Spec Overrides, its slot read before the
    -- write (a structure change then rebuilds the page, dressing the row again).
    local function Write(classFile, singles, combos, region)
        local snap = region and CUI._SOAttribution(region)
        mod.db.profile[DC.Key(classFile)] = DC.Encode(singles, combos)
        if region then CUI._NotifySettingWrite(region, snap) end
        ApplyColors()
    end
    local function Rebuild() CUI:RefreshPage(true) end
    local function SpellName(ident, fallback)
        return (ident and C_Spell and C_Spell.GetSpellName(ident)) or fallback
    end
    local function SpellIcon(ident)
        if not ident then return end
        local texture = C_Spell and C_Spell.GetSpellTexture(ident)
        if texture then return texture end
        local details = C_Spell and C_Spell.GetSpellInfo(ident)
        local preset = mod.DebuffColorPresetByID[ident]
        return (details and details.iconID)
            or (preset and preset[4])
            or "Interface\\Icons\\INV_Misc_QuestionMark"
    end
    local function CopyColor(color) return { r = color.r, g = color.g, b = color.b } end
    -- A list's chosen spells, each once, in priority order.
    local function Chosen(singles)
        local result, seen = {}, {}
        for _, entry in ipairs(singles) do
            if entry.spell > 0 and not seen[entry.spell] then
                seen[entry.spell] = true
                result[#result + 1] = entry.spell
            end
        end
        return result
    end

    -- Classes: the player's first, then the rest alphabetically. Only the
    -- classes this client has (a class's saved list elsewhere stays as is).
    local _, playerClass = UnitClass("player")
    local NAME, ORDER = {}, {}
    if CUI.IS_FOREVER then
        for _, texFile in ipairs(CUI.ForeverClasses()) do
            NAME[texFile] = CUI.ForeverClassName(texFile)
            ORDER[#ORDER + 1] = texFile
        end
    else
        for idx = 1, (GetNumClasses and GetNumClasses() or 0) do
            local name, texFile = GetClassInfo(idx)
            if name and texFile then
                NAME[texFile] = name
                ORDER[#ORDER + 1] = texFile
            end
        end
    end
    table.sort(ORDER, function(lhs, rhs)
        if (lhs == playerClass) ~= (rhs == playerClass) then return lhs == playerClass end
        return NAME[lhs] < NAME[rhs]
    end)
    local CLASS_VALUES = { _noLoc = true }
    for _, classFile in ipairs(ORDER) do
        local color = CUI.GetClassColor(classFile)
        CLASS_VALUES[classFile] = CUI.HexColor(color.r, color.g, color.b) .. NAME[classFile] .. "|r"
    end

    -- The presets for the spell menus (WoW Forever lists none: they are
    -- retail spell IDs). A debuff row offers only its own class's presets, in
    -- the preset table's order; any other spell it holds reads as custom.
    local classPresets = {}
    if not CUI.IS_FOREVER then
        for _, spellRec in ipairs(mod.DebuffColorPresets) do
            local token = spellRec[3]:gsub("%s", ""):upper()
            local set = classPresets[token]
            if not set then
                set = { order = { "remove", "custom" }, byKey = {} }
                classPresets[token] = set
            end
            local colorKey = tostring(spellRec[1])
            set.order[#set.order + 1] = colorKey
            set.byKey[colorKey] =
                { id = spellRec[1], name = SpellName(spellRec[1], spellRec[2]), class = spellRec[3] }
        end
    end
    local NO_PRESETS = { order = { "remove", "custom" }, byKey = {} }
    local function Presets(classFile) return classPresets[classFile] or NO_PRESETS end
    -- A class's custom spells: every spell its lists hold that is not one of
    -- its presets, once each, debuffs first. Each is an item of the class's
    -- spell menus for as long as something holds it.
    local function Customs(classFile)
        local own, result, seen = Presets(classFile).byKey, {}, {}
        local singles, combos = Read(classFile)
        local function Add(ident)
            local colorKey = tostring(ident)
            if ident > 0 and not own[colorKey] and not seen[colorKey] then
                seen[colorKey] = true
                result[#result + 1] = colorKey
            end
        end
        for _, entry in ipairs(singles) do
            Add(entry.spell)
        end
        for _, keyName in ipairs(combos) do
            for _, ident in ipairs(keyName.spells) do
                Add(ident)
            end
        end
        return result
    end

    -- A row reads by its place on its class's card ("1. Debuff"). FullLabel
    -- names it across classes: its popup title, and the text Spec Overrides
    -- keys its entry by (two classes' rows share a visible label).
    local function Label(swatchCell)
        if swatchCell.kind == "combo" then return CUI.Lf("%1$d. Combo", swatchCell.n) end
        return CUI.Lf("%1$d. Debuff", swatchCell.n)
    end
    local function MissingOf(swatchCell)
        local e = Read(swatchCell.class)[swatchCell.n]
        return e ~= nil and e.missing == true
    end
    local function FullLabel(swatchCell)
        if swatchCell.kind == "combo" then
            return CUI.Lf("%1$s Combo %2$d", NAME[swatchCell.class], swatchCell.n)
        end
        return CUI.Lf("%1$s Debuff %2$d", NAME[swatchCell.class], swatchCell.n)
    end
    local function SpellOf(swatchCell)
        local e = Read(swatchCell.class)[swatchCell.n]
        return e and e.spell or 0
    end
    -- A spell another debuff of the class already holds in the same state:
    -- picking it again would only duplicate that row, so its menu item is greyed
    -- with the reason and Custom Spell... refuses it (the arrows move a debuff).
    local IN_USE = "Already in use. Use the arrows to reorder."
    local function HeldElsewhere(swatchCell, ident, missing, singles)
        if missing == nil then missing = MissingOf(swatchCell) end
        for num, entry in ipairs(singles or Read(swatchCell.class)) do
            if num ~= swatchCell.n and entry.spell == ident and (entry.missing == true) == missing then
                return true
            end
        end
        return false
    end
    -- Whether MAX_MISSING other rows already color a chosen debuff while it is
    -- missing (the plates draw no more). above: only rows higher in the list
    -- count, as the plates keep the first MAX_MISSING.
    local MISSING_FULL = CUI.Lf("Up to %1$d debuffs can be Missing.", DC.MAX_MISSING)
    local function MissingFull(swatchCell, singles, above)
        local ids, num = {}, 0
        for idx, entry in ipairs(singles or Read(swatchCell.class)) do
            if above and idx >= swatchCell.n then break end
            if idx ~= swatchCell.n and entry.missing and entry.spell > 0 and not ids[entry.spell] then
                ids[entry.spell], num = true, num + 1
            end
        end
        return num >= DC.MAX_MISSING
    end
    local function ComboSpells(swatchCell)
        local _, combos = Read(swatchCell.class)
        local keyName = combos[swatchCell.n]
        return keyName and keyName.spells or {}
    end

    -- List edits. Structure changes (add, remove, reorder) rebuild the page;
    -- the edited or new row reports the write to Spec Overrides.
    local function SetSpell(swatchCell, ident, region)
        local singles, combos = Read(swatchCell.class)
        local entry = singles[swatchCell.n]
        if not entry or entry.spell == ident then return end
        entry.spell = ident
        Write(swatchCell.class, singles, combos, region)
        CUI:RefreshPage()
    end
    local function SetMissing(swatchCell, missing)
        local singles, combos = Read(swatchCell.class)
        singles[swatchCell.n].missing = missing or nil
        Write(swatchCell.class, singles, combos, swatchCell.rgn)
        CUI:RefreshPage()
    end
    local function Move(swatchCell, dir)
        local singles, combos = Read(swatchCell.class)
        local entries = swatchCell.kind == "combo" and combos or singles
        local jdx = swatchCell.n + dir
        if not (entries[swatchCell.n] and entries[jdx]) then return end
        entries[swatchCell.n], entries[jdx] = entries[jdx], entries[swatchCell.n]
        Write(swatchCell.class, singles, combos, swatchCell.rgn)
        Rebuild()
    end
    local function Remove(swatchCell)
        local singles, combos = Read(swatchCell.class)
        local entries = swatchCell.kind == "combo" and combos or singles
        if not entries[swatchCell.n] then return end
        table.remove(entries, swatchCell.n)
        Write(swatchCell.class, singles, combos, swatchCell.rgn)
        Rebuild()
    end
    -- A new debuff starts unchosen; a new combo pairs the class's top two.
    local function AddSingle(classFile)
        local singles, combos = Read(classFile)
        if #singles >= DC.MAX_SINGLES then return end
        singles[#singles + 1] = { spell = 0, color = CopyColor(DC.SINGLE_COLOR) }
        Write(classFile, singles, combos)
        debuffColorOpen[classFile] = true
        addedDebuff = { kind = "single", class = classFile, n = #singles }
        Rebuild()
        addedDebuff = nil
    end
    local function ComboRoom(classFile)
        local singles, combos = Read(classFile)
        return #combos < DC.MAX_COMBOS and #Chosen(singles) >= 2
    end
    local function AddCombo(classFile)
        if not ComboRoom(classFile) then return end
        local singles, combos = Read(classFile)
        local picks = Chosen(singles)
        combos[#combos + 1] = { spells = { picks[1], picks[2] }, color = CopyColor(DC.COMBO_COLOR) }
        Write(classFile, singles, combos)
        addedDebuff = { kind = "combo", class = classFile, n = #combos }
        Rebuild()
        addedDebuff = nil
    end

    -- Debuff Coloring: a pure view over debuffColorsEnabled (off = None) and
    -- the module's mode (DC.Mode: Texture Nameplate and Color Name in
    -- debuffColorsMode, else debuffColorsBorder picks Color Border or Color
    -- Nameplate). Color Border's cog (Extra Border Size) shows only over a
    -- Basic or Custom Solid border; a textured custom border is recolored as it
    -- is. Both checks follow the runtime's border reading (BorderSpec in the module).
    local function Mode()
        if Off() then return "none" end
        return DC.Mode(Get)
    end
    local function NoBorder()
        if CUI.BlizzStyle.Get("nameplates") then return true end
        if Get("customBorderEnabled") then
            if (Get("customBorderSize") or 0) <= 0 then return true end
            -- A textured border whose art no longer resolves (its media pack
            -- removed) draws nothing.
            local texture = Get("customBorderTexture")
            return texture ~= nil
                and texture ~= ""
                and texture ~= "solid"
                and not CUI.ResolveBorderTexture(texture)
        end
        return Get("showBorder") == false
    end
    local function StripBorder()
        if NoBorder() then return false end
        if Get("customBorderEnabled") then
            local texture = Get("customBorderTexture")
            return not texture or texture == "" or texture == "solid"
        end
        return true
    end
    local _, height, modeRow
    _, height = W:SectionHeader(hostFrame, "DEBUFF BASED NAMEPLATE COLORING", cursorY)
    cursorY = cursorY - height
    modeRow, height = W:DualRow(hostFrame, cursorY, {
        type = "dropdown",
        text = "Debuff Coloring",
        values = {
            none = "None",
            nameplate = "Color Nameplate",
            texture = "Texture Nameplate",
            border = "Color Border",
            name = "Color Name",
        },
        order = { "none", "nameplate", "texture", "border", "name" },
        disabledValues = function(colorKey)
            if colorKey == "border" and NoBorder() then
                return "This option requires a Border to be selected"
            end
            if colorKey == "name" and not mod.FindNameSlot() then
                return "This option requires the enemy name to be shown"
            end
            return false
        end,
        getValue = Mode,
        setValue = CUI.SectionToggleSetValue(function(val)
            local saved = mod.db.profile
            saved.debuffColorsEnabled = val ~= "none"
            if val ~= "none" then
                saved.debuffColorsBorder = val == "border"
                saved.debuffColorsMode = (val == "texture" or val == "name") and val or nil
            end
            mod.DebuffColors_Refresh()
        end),
        tooltip = "Colors enemy health bars, their borders or their names while the chosen debuffs are on them.",
    }, {
        type = "toggle",
        text = "Only My Debuffs",
        getValue = function() return Get("debuffColorsPlayerOnly") ~= false end,
        setValue = function(val)
            mod.db.profile.debuffColorsPlayerOnly = val
            ApplyColors()
        end,
        disabled = Off,
        disabledTooltip = "Debuff Coloring",
        tooltip = "Counts only the debuffs you applied.",
    })
    cursorY = cursorY - height

    -- Color Border's cog, built while it is picked (the dropdown rebuilds the
    -- page) and shown only over a border drawn as strips; a border change on
    -- the Display page reaches it through the page's refreshers.
    if Mode() == "border" and not CUI._prebuilding then
        local cog = CUI.BuildInlineCog(modeRow._leftRegion, {
            title = "Color Border",
            rows = {
                {
                    type = "slider",
                    label = "Extra Border Size",
                    min = 0,
                    max = 4,
                    step = 1,
                    tooltip = "Thickens the border by this many pixels while it shows a debuff color.",
                    get = function() return Get("debuffColorsBorderExtra") or 0 end,
                    set = function(val)
                        mod.db.profile.debuffColorsBorderExtra = val
                        ApplyColors()
                    end,
                },
            },
        })
        local function ShowCog() cog:SetShown(StripBorder()) end
        ShowCog()
        CUI.RegisterWidgetRefresh(ShowCog)
    end

    -- Texture Nameplate's texture, the row below while it is picked (unset reads
    -- the health bar's own).
    if Mode() == "texture" then
        local environ = mod._NPO_OptEnv
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "dropdown",
            text = "Texture",
            values = environ.hbtValues,
            order = environ.hbtOrder,
            tooltip = "The texture the debuff color is drawn in.",
            getValue = function() return Get("debuffColorsTexture") or Get("healthBarTexture") or "none" end,
            setValue = function(val)
                mod.db.profile.debuffColorsTexture = val
                ApplyColors()
            end,
        }, CUI.BlankRowCfg())
        cursorY = cursorY - height
    end

    -- Section gate: the rows below exist only while Debuff Coloring is on (the
    -- dropdown's SectionToggleSetValue rebuilds the page).
    if Off() then
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        return cursorY
    end

    -- Up/down arrows beside a row's name (white, the accent while hovered;
    -- a darker white when the accent itself is white). The first entry
    -- cannot move up nor the last down.
    local UP_ICON = "Interface\\AddOns\\CludesUI\\media\\icons\\cui-arrow-up3.png"
    local DOWN_ICON = "Interface\\AddOns\\CludesUI\\media\\icons\\cui-arrow-down3.png"
    local function HoverColor()
        local ac = CUI.CLUDES_GREEN
        if ac.r > 0.9 and ac.g > 0.9 and ac.b > 0.9 then return 0.72, 0.72, 0.72 end
        return ac.r, ac.g, ac.b
    end
    local function Arrow(region, texture, tipText, enabled, onClick)
        local button = CreateFrame("Button", nil, region)
        button:SetFrameLevel(region:GetFrameLevel() + 12)
        button:SetSize(16, 20)
        local iconTex = button:CreateTexture(nil, "ARTWORK")
        iconTex:SetTexture(texture)
        iconTex:SetSize(16, 16)
        iconTex:SetPoint("CENTER")
        if not enabled then
            iconTex:SetAlpha(0.2)
            button:EnableMouse(false)
            return button
        end
        button:SetScript("OnEnter", function()
            iconTex:SetVertexColor(HoverColor())
            CUI.ShowWidgetTooltip(button, tipText)
        end)
        button:SetScript("OnLeave", function()
            iconTex:SetVertexColor(1, 1, 1)
            CUI.HideWidgetTooltip()
        end)
        button:SetScript("OnClick", function()
            CUI.HideWidgetTooltip()
            onClick()
        end)
        return button
    end
    local function ReorderArrows(region, swatchCell)
        local labelText = region._label
        local up = Arrow(region, UP_ICON, "Move Up", swatchCell.n > 1, function() Move(swatchCell, -1) end)
        up:SetPoint("LEFT", labelText, "LEFT", math.ceil(labelText:GetStringWidth()) + 6, -1)
        local down = Arrow(
            region,
            DOWN_ICON,
            "Move Down",
            swatchCell.n < swatchCell.count,
            function() Move(swatchCell, 1) end
        )
        down:SetPoint("LEFT", up, "RIGHT", 0, 0)
    end

    local SINGLE_TIP = "Higher in the list wins when several are up."
    local COMBO_TIP = "Combos win over single debuffs; higher in the list wins."
    local STATE_ORDER = { "applied", "missing" }
    local STATE_VALUES = {
        applied = "Applied",
        missing = "Missing",
        _menuOpts = {
            onItemHover = function(colorKey, entry)
                if colorKey == "missing" then
                    CUI.ShowWidgetTooltip(
                        entry,
                        CUI.L("Colors enemies you fight without this debuff.")
                    )
                end
            end,
            onItemLeave = function() CUI.HideWidgetTooltip() end,
        },
    }

    -- A debuff: its spell menu (Remove, Custom Spell..., the class's presets,
    -- then its custom spells) with its color inline. The custom tail follows
    -- edits on every row of the class (cell.syncCustoms, run by the row's
    -- refresher); Custom Spell... is an action: it adds a spell and keeps its label.
    local function SingleCfg(swatchCell)
        local own = Presets(swatchCell.class)
        local values = {
            _noLoc = true,
            none = CUI.L("None"),
            remove = {
                text = CUI.L("Remove"),
                action = function() Remove(swatchCell) end,
            },
        }
        for colorKey, s in pairs(own.byKey) do
            values[colorKey] = s.name
        end
        local sequence = {}
        for idx, colorKey in ipairs(own.order) do
            sequence[idx] = colorKey
        end
        local base = #sequence
        -- True when the menu's items changed (it must rebuild).
        function swatchCell.syncCustoms()
            local customs, changed = Customs(swatchCell.class), false
            for idx, colorKey in ipairs(customs) do
                if sequence[base + idx] ~= colorKey then
                    sequence[base + idx] = colorKey
                    changed = true
                end
                local name = SpellName(tonumber(colorKey), "Spell " .. colorKey)
                if values[colorKey] ~= name then
                    values[colorKey] = name
                    changed = true
                end
            end
            for idx = #sequence, base + #customs + 1, -1 do
                sequence[idx] = nil
                changed = true
            end
            return changed
        end
        swatchCell.syncCustoms()
        values.custom = {
            text = CUI.L("Custom Spell..."),
            action = function()
                CUI:ShowInputPopup({
                    title = FullLabel(swatchCell),
                    confirmText = "Add",
                    cancelText = "Cancel",
                    message = "Enter the debuff's spell ID.",
                    placeholder = "Spell ID",
                    maxLetters = 10,
                    onConfirm = function(textValue)
                        local value = DC.SpellID((textValue or ""):match("^%s*(%d+)%s*$"))
                        if not (value and C_Spell and C_Spell.GetSpellInfo(value)) then
                            CUI.PrintError(CUI.L("Enter a valid debuff spell ID."))
                            return
                        end
                        if HeldElsewhere(swatchCell, value) then
                            CUI.PrintError(CUI.L("Already in use. Use the arrows to reorder."))
                            return
                        end
                        if
                            MissingOf(swatchCell) and MissingFull(swatchCell, nil, SpellOf(swatchCell) > 0)
                        then
                            CUI.PrintError(MISSING_FULL)
                            return
                        end
                        SetSpell(swatchCell, value, swatchCell.rgn)
                    end,
                })
            end,
        }
        values._menuOpts = {
            searchable = true,
            itemHeight = 28,
            maxHeight = 280,
            iconNativeColor = true,
            icon = function(colorKey)
                local ident = tonumber(colorKey)
                return SpellIcon(ident and ident > 0 and ident), 0.08, 0.92, 0.08, 0.92
            end,
            onItemHover = function(colorKey, entry)
                local spellRec = own.byKey[colorKey]
                if spellRec then
                    CUI.ShowWidgetTooltip(
                        entry,
                        spellRec.class .. " | " .. CUI.Lf("Spell ID: %1$s", spellRec.id)
                    )
                elseif tonumber(colorKey) then
                    CUI.ShowWidgetTooltip(entry, CUI.Lf("Spell ID: %1$s", colorKey))
                end
            end,
            onItemLeave = function() CUI.HideWidgetTooltip() end,
        }
        return {
            type = "dropdown",
            text = Label(swatchCell),
            values = values,
            order = sequence,
            getValue = function()
                local ident = SpellOf(swatchCell)
                if ident == 0 then return "none" end
                return tostring(ident)
            end,
            setValue = function(val)
                local ident = DC.SpellID(val)
                if ident then SetSpell(swatchCell, ident) end
            end,
            -- Never the row's own spell (a list saved with a duplicate keeps
            -- its label lit). A Missing row past MAX_MISSING shows why it colors
            -- nothing; an unchosen one may not take a spell once the rest are full.
            disabledValues = function(colorKey)
                local ident, singles = tonumber(colorKey), Read(swatchCell.class)
                local entry = singles[swatchCell.n]
                if not ident or (entry and entry.spell == ident) then return false end
                local missing = entry ~= nil and entry.missing == true
                if HeldElsewhere(swatchCell, ident, missing, singles) then return IN_USE end
                return missing and MissingFull(swatchCell, singles, entry.spell > 0) and MISSING_FULL or false
            end,
            tooltip = SINGLE_TIP,
        }
    end
    -- Applied / Missing, beside the spell menu; a state a same-spell row holds is
    -- greyed, and Missing once MAX_MISSING rows use it.
    local function StateDropdown(region, swatchCell)
        local dropdown = CUI.BuildDropdownControl(
            region,
            90,
            region:GetFrameLevel() + 3,
            STATE_VALUES,
            STATE_ORDER,
            function() return MissingOf(swatchCell) and "missing" or "applied" end,
            function(val) SetMissing(swatchCell, val == "missing") end,
            function(colorKey)
                local singles, missing = Read(swatchCell.class), colorKey == "missing"
                local entry = singles[swatchCell.n]
                if not entry or missing == (entry.missing == true) then return false end
                if missing and MissingFull(swatchCell, singles) then return MISSING_FULL end
                return entry.spell > 0
                        and HeldElsewhere(swatchCell, entry.spell, missing, singles)
                        and "Another row already uses this debuff this way."
                    or false
            end
        )
        Pix.Point(dropdown, "RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
        region._lastInline = dropdown
        CUI.RegisterWidgetRefresh(dropdown._refreshLabel)
    end
    local function SingleChrome(region, swatchCell)
        ReorderArrows(region, swatchCell)
        -- The menu rebuilds only when its custom spells change.
        local function Sync()
            local control = region._control
            if swatchCell.syncCustoms() and control._invalidateMenu then control._invalidateMenu() end
            if control._refreshLabel then control._refreshLabel() end
        end
        Sync()
        CUI.RegisterWidgetRefresh(Sync)
        StateDropdown(region, swatchCell)
        CUI.BuildInlineSwatches(region, {
            {
                tooltip = "Debuff Color",
                getValue = function()
                    local e = Read(swatchCell.class)[swatchCell.n]
                    local color = e and e.color or DC.SINGLE_COLOR
                    return color.r, color.g, color.b
                end,
                setValue = function(red, green, blue)
                    local singles, combos = Read(swatchCell.class)
                    local entry = singles[swatchCell.n]
                    if not entry then return end
                    entry.color = { r = red, g = green, b = blue }
                    Write(swatchCell.class, singles, combos)
                end,
                disabled = function() return SpellOf(swatchCell) == 0 end,
                disabledTooltip = "This option requires a debuff to be selected",
            },
        })
    end

    -- A combo: a checkbox list of its class's debuffs (two to four checked),
    -- Remove above them, its color inline. The row's own dropdown, hidden
    -- under the list, reads and writes the combo's spells.
    local function SetComboSpells(swatchCell, spells, region)
        local singles, combos = Read(swatchCell.class)
        local keyName = combos[swatchCell.n]
        if not keyName then return end
        keyName.spells = spells
        Write(swatchCell.class, singles, combos, region)
    end
    local COMBO_VALUES = setmetatable({}, {
        __index = function(_, colorKey)
            if type(colorKey) ~= "string" or colorKey:sub(1, 1) == "_" then return nil end
            local nameList = {}
            for ident in colorKey:gmatch("%d+") do
                nameList[#nameList + 1] = SpellName(tonumber(ident), "Spell " .. ident)
            end
            return #nameList > 0 and table.concat(nameList, " + ") or nil
        end,
    })
    local function ComboCfg(swatchCell)
        return {
            type = "dropdown",
            text = Label(swatchCell),
            values = COMBO_VALUES,
            order = {},
            getValue = function() return table.concat(ComboSpells(swatchCell), "+") end,
            setValue = function(val)
                local spells = {}
                for ident in tostring(val):gmatch("%d+") do
                    ident = DC.SpellID(ident)
                    if ident and #spells < DC.MAX_COMBO_SPELLS then spells[#spells + 1] = ident end
                end
                SetComboSpells(swatchCell, spells)
            end,
            tooltip = COMBO_TIP,
        }
    end
    local function ComboChrome(region, swatchCell)
        ReorderArrows(region, swatchCell)
        local function Has(ident)
            for _, s in ipairs(ComboSpells(swatchCell)) do
                if s == ident then return true end
            end
            return false
        end
        local function Valid()
            local seen, num = {}, 0
            for _, s in ipairs(ComboSpells(swatchCell)) do
                if not seen[s] then
                    seen[s] = true
                    num = num + 1
                end
            end
            return num >= 2
        end
        -- Its class's chosen debuffs, then any spell only the combo holds.
        local function Items()
            local itemList = {
                {
                    key = "_remove",
                    label = "Remove",
                    isTopAction = true,
                    onClick = function() Remove(swatchCell) end,
                },
            }
            local listed = {}
            local function Add(ident)
                if listed[ident] then return end
                listed[ident] = true
                itemList[#itemList + 1] = {
                    key = tostring(ident),
                    label = SpellName(ident, "Spell " .. ident),
                    icon = SpellIcon(ident),
                    lockedFn = function()
                        return not Has(ident) and #ComboSpells(swatchCell) >= DC.MAX_COMBO_SPELLS
                    end,
                    lockedTooltip = "A combo holds up to four debuffs.",
                }
            end
            for _, ident in ipairs(Chosen((Read(swatchCell.class)))) do
                Add(ident)
            end
            for _, ident in ipairs(ComboSpells(swatchCell)) do
                Add(ident)
            end
            return itemList
        end
        local control = region._control
        local ddW = control and control:GetWidth() or 0
        if ddW < 50 then ddW = 170 end
        local pulse
        local checkDrop, cbRefresh = CUI.BuildVisOptsCBDropdown(
            region,
            ddW,
            region:GetFrameLevel() + 2,
            Items,
            function(colorKey) return Has(tonumber(colorKey)) end,
            function(colorKey, on)
                local ident = tonumber(colorKey)
                local spells = {}
                for _, s in ipairs(ComboSpells(swatchCell)) do
                    if s ~= ident then spells[#spells + 1] = s end
                end
                if on and #spells < DC.MAX_COMBO_SPELLS then spells[#spells + 1] = ident end
                SetComboSpells(swatchCell, spells)
            end,
            nil,
            8,
            false,
            false,
            function()
                if pulse then pulse() end
            end,
            {
                notifyWrites = true,
                noAllLabel = true,
                separatorFn = function() return " + " end,
            }
        )
        local p1, rel, p2, ax, ay
        if control then
            p1, rel, p2, ax, ay = control:GetPoint(1)
            control:Hide()
        end
        if p1 then
            checkDrop:SetPoint(p1, rel, p2, ax, ay)
        else
            Pix.Point(checkDrop, "RIGHT", region, "RIGHT", -20, 0)
        end
        region._control = checkDrop
        region._lastInline = nil
        CUI.RegisterWidgetRefresh(cbRefresh)
        pulse =
            CUI.AttachEmptyFilterWarn(region, checkDrop, CUI.L("Pick at least two debuffs"), Valid)
        CUI.BuildInlineSwatches(region, {
            {
                tooltip = "Combo Color",
                getValue = function()
                    local _, combos = Read(swatchCell.class)
                    local keyName = combos[swatchCell.n]
                    local color = keyName and keyName.color or DC.COMBO_COLOR
                    return color.r, color.g, color.b
                end,
                setValue = function(red, green, blue)
                    local singles, combos = Read(swatchCell.class)
                    local keyName = combos[swatchCell.n]
                    if not keyName then return end
                    keyName.color = { r = red, g = green, b = blue }
                    Write(swatchCell.class, singles, combos)
                end,
            },
        })
    end

    -- Add Class opens the classes that have no card yet (the standard
    -- dropdown menu, as wide as the button, built on first open).
    local ADD_W, CLASS_W = 220, 450
    local NO_PAINT = { SetColor = function() end, SetColorTexture = function() end }
    local function AddPicker(button, sequence, pick)
        -- Its own hover look, kept past the menu wiring (which takes the scripts).
        local enter, leave = button:GetScript("OnEnter"), button:GetScript("OnLeave")
        local proxyLbl = CUI.MakeFont(button, 12, nil, 1, 1, 1)
        proxyLbl:Hide()
        local dropMenu
        local function EnsureMenu()
            if dropMenu then return dropMenu end
            local refresh
            dropMenu, _, refresh = CUI.BuildDropdownMenu(
                button,
                CLASS_W,
                sequence,
                CLASS_VALUES,
                function() return nil end,
                pick,
                proxyLbl,
                "regular"
            )
            CUI.WireDropdownScripts(
                button,
                proxyLbl,
                NO_PAINT,
                NO_PAINT,
                dropMenu,
                refresh,
                CUI.RD_DD_COLOURS,
                true
            )
            button:HookScript("OnEnter", enter)
            button:HookScript("OnLeave", function(self)
                if not dropMenu:IsShown() then leave(self) end
            end)
            dropMenu:HookScript("OnHide", function()
                if not button:IsMouseOver() then leave(button) end
            end)
            return dropMenu
        end
        button:HookScript("OnHide", function()
            if dropMenu then dropMenu:Hide() end
        end)
        return function()
            local m = EnsureMenu()
            if m:IsShown() then
                m:Hide()
            else
                m:Show()
            end
        end
    end
    local function SingleRoom(classFile) return #Read(classFile) < DC.MAX_SINGLES end
    local function AddSingleCfg(classFile)
        return {
            type = "button",
            text = "+ Add Debuff",
            width = ADD_W,
            onClick = function() AddSingle(classFile) end,
            disabled = function() return not SingleRoom(classFile) end,
            disabledTooltip = "This class has ten debuffs.",
            rawTooltip = true,
        }
    end
    local function AddComboCfg(classFile)
        return {
            type = "button",
            text = "+ Add Combo",
            width = ADD_W,
            onClick = function() AddCombo(classFile) end,
            disabled = function() return not ComboRoom(classFile) end,
            disabledTooltip = "This option requires two debuffs for the same class",
        }
    end

    local function CellCfg(cfg)
        if cfg == nil then return CUI.BlankRowCfg() end
        if cfg.type then return cfg end
        return cfg.kind == "combo" and ComboCfg(cfg) or SingleCfg(cfg)
    end
    local function CellChrome(region, cfg)
        if CUI._prebuilding or cfg == nil or cfg.type then return end
        cfg.rgn = region
        if region._captureCfg then
            region._captureCfg = setmetatable({ text = FullLabel(cfg) }, { __index = region._captureCfg })
        end
        if cfg.kind == "combo" then
            ComboChrome(region, cfg)
        else
            SingleChrome(region, cfg)
        end
        -- The entry Add just made: its own row takes the write (its slot read now,
        -- while this build's row is its dress).
        local a = addedDebuff
        if a and a.kind == cfg.kind and a.class == cfg.class and a.n == cfg.n then
            addedDebuff = nil
            local snap = CUI._SOAttribution(region)
            CUI._NotifySettingWrite(region, snap)
        end
    end

    -- A class card's rows: its debuffs down the left column, its combos down
    -- the right, each column closed by its Add button. The shorter column
    -- leaves its slots blank so both read top to bottom in priority order.
    local DEBUFFS, COMBOS = "Debuffs", "Combos"
    local function ClassRows(classFile, singles, combos, cy)
        local titles, ch
        titles, ch = W:DualRow(
            hostFrame,
            cy,
            { type = "label", text = "DEBUFFS", tooltip = SINGLE_TIP },
            { type = "label", text = "COMBOS", tooltip = COMBO_TIP }
        )
        cy = cy - ch
        -- The column titles read as section headers: their size and tint.
        local tint = CUI.TEXT_SECTION
        for _, region in ipairs({ titles._leftRegion, titles._rightRegion }) do
            local font, _, flags = region._label:GetFont()
            region._label:SetFont(font, 12, flags)
            region._label:SetTextColor(tint.r, tint.g, tint.b, tint.a)
        end
        local leftX, right = {}, {}
        for num = 1, #singles do
            leftX[num] = { kind = "single", class = classFile, n = num, count = #singles }
        end
        leftX[#leftX + 1] = AddSingleCfg(classFile)
        for num = 1, #combos do
            right[num] = { kind = "combo", class = classFile, n = num, count = #combos }
        end
        right[#right + 1] = AddComboCfg(classFile)
        for keyName = 1, math.max(#leftX, #right) do
            local l, r = leftX[keyName], right[keyName]
            local row
            row, ch = W:DualRow(hostFrame, cy, CellCfg(l), CellCfg(r))
            cy = cy - ch
            CellChrome(row._leftRegion, l)
            CellChrome(row._rightRegion, r)
        end
        return cy
    end
    -- The class icon on a card's header, in a 1px black border: the
    -- stock sheet's cell cropped past its own beveled frame (WoW Forever:
    -- the class's first spec icon; a class without one gets none).
    local CLASS_ICONS = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
    local ICON_CROP = 0.1
    local function ClassGlyph(heading, classFile)
        local boxFrame = CreateFrame("Frame", nil, heading)
        Pix.Size(boxFrame, 24, 24)
        Pix.Point(boxFrame, "LEFT", heading, "LEFT", 14, 0)
        local iconTex = boxFrame:CreateTexture(nil, "ARTWORK")
        iconTex:SetAllPoints()
        local texCoords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile]
        if CUI.IS_FOREVER then
            iconTex:SetTexture(CUI.ForeverClassIcon(classFile))
            iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        elseif texCoords then
            local du = (texCoords[2] - texCoords[1]) * ICON_CROP
            local dv = (texCoords[4] - texCoords[3]) * ICON_CROP
            iconTex:SetTexture(CLASS_ICONS)
            iconTex:SetTexCoord(texCoords[1] + du, texCoords[2] - du, texCoords[3] + dv, texCoords[4] - dv)
        end
        CUI.MakeBorder(boxFrame, 0, 0, 0, 1, Pix)
    end

    -- A class has a card while it holds an entry, the player's first; Add
    -- Class offers the rest.
    local listed, unlisted = {}, {}
    for _, classFile in ipairs(ORDER) do
        local singles, combos = Read(classFile)
        if #singles > 0 or #combos > 0 then
            listed[#listed + 1] = { class = classFile, singles = singles, combos = combos }
        else
            unlisted[#unlisted + 1] = classFile
        end
    end

    -- The cards (the house module card, as on Global Settings > Fonts), the
    -- first right under the settings above.
    if debuffColorOpen[playerClass] == nil then debuffColorOpen[playerClass] = true end
    for _, record in ipairs(listed) do
        local classFile, singles, combos = record.class, record.singles, record.combos
        local tile = {
            key = classFile,
            display = NAME[classFile],
            desc = CUI.L(DEBUFFS) .. ": " .. #singles .. "    " .. CUI.L(COMBOS) .. ": " .. #combos,
            buildContent = function(_, cy) return ClassRows(classFile, singles, combos, cy) end,
        }
        cursorY = CUI.BuildModuleCard(hostFrame, cursorY, W, tile, {
            enabled = true,
            expanded = debuffColorOpen,
            descW = 440,
            searchDesc = "Debuff Coloring",
            glyph = function(heading) ClassGlyph(heading, classFile) end,
        })
        -- The card's title (its description line hangs off it) takes the
        -- class color at full strength.
        local _, title = tile._descFS:GetPoint(1)
        if title and title.SetTextColor then
            local color = CUI.GetClassColor(classFile)
            title:SetTextColor(color.r, color.g, color.b, 1)
        end
    end

    -- Add Class: a first, unchosen debuff gives the picked class its card.
    if #unlisted > 0 then
        local openClass, wide
        wide, height = W:WideButton(hostFrame, "+ Add Class", cursorY, function()
            if openClass then openClass() end
        end, CLASS_W)
        cursorY = cursorY - height
        if not CUI._prebuilding then
            -- The row's button: its one shown child (page reuse keeps the row's
            -- children of its earlier dresses among its children, hidden).
            local button
            local kids = { wide:GetChildren() }
            for idx = 1, #kids do
                if kids[idx]:IsShown() then
                    button = kids[idx]
                    break
                end
            end
            if button then openClass = AddPicker(button, unlisted, AddSingle) end
        end
    end
    _, height = W:Spacer(hostFrame, cursorY, 20)
    cursorY = cursorY - height
    return cursorY
end

-- Mini preview bar builder for color swatches. type: "health"/"cast"/"castLocked". colorKey: DB key for the bar color (read live). parentRow: frame to attach to. anchorFrame: optional override anchor (e.g. DualRow half-region).
local function MakeColorPreviewBar(parentRow, colorType, colorKey, anchorFrame)
    local environ = mod._NPO_OptEnv
    local DB, DBVal, defaultSet, GetFocusLetterAnchor =
        environ.DB, environ.DBVal, environ.defaults, environ.GetFocusLetterAnchor
    local GetNPOptOutline, NextCastFill, NextCastIcon, Pix =
        environ.GetNPOptOutline, environ.NextCastFill, environ.NextCastIcon, environ.PP
    local SetPVFont = environ.SetPVFont
    local MEDIA = "Interface\\AddOns\\CludesUINameplates\\Media\\"
    local isHalf = anchorFrame and true or false
    local BAR_W = isHalf and 161 or 180
    local BAR_H = 20
    local SWATCH_SZ = 24
    local SWATCH_GAP = isHalf and 27 or 52
    local fontFile = (CUI.GetFontPath("nameplates")) or DBVal("font")
    local anchor = anchorFrame or parentRow

    local boxHolder = CreateFrame("Frame", nil, parentRow)
    Pix.Size(boxHolder, BAR_W + 2, BAR_H + 2) -- +2 for border
    -- Position: to the left of the swatch (swatch is at RIGHT -SIDE_PAD, 24px wide)
    Pix.Point(boxHolder, "RIGHT", anchor, "RIGHT", -(20 + SWATCH_SZ + SWATCH_GAP), 0)
    boxHolder:SetFrameLevel(parentRow:GetFrameLevel() + 2)

    -- Simple 1px solid border using the user's nameplate border color; two-point anchoring for pixel-perfect rendering inside the scroll frame.
    local function MakePreviewBorder(hostFrame)
        local bc = (DB() and DB().borderColor) or defaultSet.borderColor
        local edges = {}
        local function mkE()
            local tex = hostFrame:CreateTexture(nil, "OVERLAY", nil, 7)
            tex:SetColorTexture(bc.r, bc.g, bc.b, 1)
            edges[#edges + 1] = tex
            return tex
        end
        local t = mkE()
        t:SetPoint("TOPLEFT")
        t:SetPoint("TOPRIGHT")
        t:SetHeight(1)
        local widget = mkE()
        widget:SetPoint("BOTTOMLEFT")
        widget:SetPoint("BOTTOMRIGHT")
        widget:SetHeight(1)
        local l = mkE()
        l:SetPoint("TOPLEFT", t, "BOTTOMLEFT")
        l:SetPoint("BOTTOMLEFT", widget, "TOPLEFT")
        l:SetWidth(1)
        local r = mkE()
        r:SetPoint("TOPRIGHT", t, "BOTTOMRIGHT")
        r:SetPoint("BOTTOMRIGHT", widget, "TOPRIGHT")
        r:SetWidth(1)
        return edges
    end

    if colorType == "health" then
        -- Health bar preview: random fill 60-75%, colored by the swatch color
        local FAKE_MAX_HP = 10000
        local healthPercent = math.floor(60 + math.random() * 15)
        local healthVal = math.floor(FAKE_MAX_HP * healthPercent / 100)

        local healthBar = CreateFrame("StatusBar", nil, boxHolder)
        healthBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
        healthBar:SetMinMaxValues(0, 100)
        healthBar:SetValue(healthPercent)
        healthBar:SetAllPoints()

        local backdrop = healthBar:CreateTexture(nil, "BACKGROUND")
        backdrop:SetAllPoints()
        backdrop:SetColorTexture(0.20, 0.20, 0.20, 1.0)

        -- 1px solid border on a dedicated frame ABOVE the health StatusBar (child frames cover parent textures); parented to container, not health, so it stays full opacity when the bar dims via SetDisabled.
        local brdFrame = CreateFrame("Frame", nil, boxHolder)
        brdFrame:SetAllPoints()
        brdFrame:SetFrameLevel(healthBar:GetFrameLevel() + 2)
        local brdEdges = MakePreviewBorder(brdFrame)
        boxHolder._brdEdges = brdEdges
        boxHolder._health = healthBar -- exposed for proxy color override / dimming

        -- Always create both FontStrings (shown/hidden dynamically), parented to a text frame ABOVE the overlay clips so focus texture never covers the health numbers.
        local textHolder = CreateFrame("Frame", nil, healthBar)
        textHolder:SetAllPoints()
        textHolder:SetFrameLevel(healthBar:GetFrameLevel() + 3)

        local percentText = textHolder:CreateFontString(nil, "OVERLAY")
        local initHpSz = 10
        SetPVFont(percentText, fontFile, initHpSz, GetNPOptOutline())
        percentText:Hide()

        local numberText = textHolder:CreateFontString(nil, "OVERLAY")
        SetPVFont(numberText, fontFile, initHpSz, GetNPOptOutline())
        numberText:Hide()

        -- Full refresh: re-reads DB settings, repositions, updates text & values
        local function RefreshHealthText()
            local hpFS = 10
            -- Use the largest text slot size (capped at 13 for mini bars)
            for _, sk in ipairs({ "textSlotRight", "textSlotLeft", "textSlotCenter" }) do
                local el = DBVal(sk) or defaultSet[sk]
                if el and el ~= "none" and not mod.IsNameElement(el) then
                    hpFS = math.min(DBVal(sk .. "Size") or defaultSet[sk .. "Size"] or 10, 13)
                    break
                end
            end
            local curFont = (CUI.GetFontPath("nameplates")) or DBVal("font")
            local curOutline = GetNPOptOutline()

            -- Hide both FontStrings first
            SetPVFont(percentText, curFont, hpFS, curOutline)
            percentText:ClearAllPoints()
            percentText:Hide()
            SetPVFont(numberText, curFont, hpFS, curOutline)
            numberText:ClearAllPoints()
            numberText:Hide()

            -- Bar slots: show health text based on slot assignments
            local barSlots = {
                { key = "textSlotRight", anchor = "RIGHT", xOff = -2 },
                { key = "textSlotLeft", anchor = "LEFT", xOff = 2 },
                { key = "textSlotCenter", anchor = "CENTER", xOff = 0 },
            }
            for _, slotIndex in ipairs(barSlots) do
                local element = DBVal(slotIndex.key) or defaultSet[slotIndex.key]
                local swatchColor = (DB() and DB()[slotIndex.key .. "Color"])
                    or defaultSet[slotIndex.key .. "Color"]
                -- This bar stands for a hostile NPC at the player's level: Hostility /
                -- Class shows the Hostile name colour, Level Difficulty that level's
                -- colour, as the plate would.
                local mode = mod.NP_SlotColorMode(slotIndex.key, DB())
                if mode == "class" then
                    swatchColor = (DB() and DB().enemyNameHostileColor) or defaultSet.hostile
                elseif mode == "level" then
                    local red, green, blue = mod.NP_UnitLevelColor("player")
                    if red then swatchColor = { r = red, g = green, b = blue } end
                end
                if element == "healthPercent" or element == "healthPercentNoSign" then
                    percentText:SetTextColor(swatchColor.r, swatchColor.g, swatchColor.b, 1)
                    percentText:SetText(
                        element == "healthPercentNoSign" and tostring(healthPercent) or (healthPercent .. "%")
                    )
                    percentText:SetPoint(slotIndex.anchor, healthBar, slotIndex.anchor, slotIndex.xOff, 0)
                    percentText:Show()
                elseif element == "healthNumber" then
                    numberText:SetTextColor(swatchColor.r, swatchColor.g, swatchColor.b, 1)
                    local valStr =
                        tostring(healthVal):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
                    numberText:SetText(valStr)
                    numberText:SetPoint(slotIndex.anchor, healthBar, slotIndex.anchor, slotIndex.xOff, 0)
                    numberText:Show()
                elseif mod.IsComboHealthText(element) then
                    local valStr =
                        tostring(healthVal):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
                    percentText:SetTextColor(swatchColor.r, swatchColor.g, swatchColor.b, 1)
                    local maxStr =
                        tostring(FAKE_MAX_HP):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
                    mod.SetCombinedHealthText(percentText, element, healthPercent .. "%", valStr, maxStr)
                    percentText:SetPoint(slotIndex.anchor, healthBar, slotIndex.anchor, slotIndex.xOff, 0)
                    percentText:Show()
                end
            end
        end

        -- Run initial layout
        RefreshHealthText()

        -- Color the bar from the swatch's DB value
        local color = (DB() and DB()[colorKey]) or defaultSet[colorKey]
        healthBar:SetStatusBarColor(color.r, color.g, color.b, 1)

        -- Focus overlay on the focus preview bar: clip frames for non-overlapping fixed-size textures
        local overlayFillClip, overlayFillTex, overlayBgClip, overlayBgTex

        -- Helper: create a clipped overlay frame+texture pair for the focus bar
        local function MakeOverlayClip(tlAnchor, tlRelPoint, brAnchor, brRelPoint, sublayer)
            local clipFrame = CreateFrame("Frame", nil, healthBar)
            clipFrame:SetClipsChildren(true)
            -- Full bar height (top/bottom from the bar) with horizontal edges from the passed fill/health anchors, matching the live nameplate overlay (same full-height stripes).
            clipFrame:SetPoint("TOP", healthBar, "TOP", 0, 0)
            clipFrame:SetPoint("BOTTOM", healthBar, "BOTTOM", 0, 0)
            clipFrame:SetPoint("LEFT", tlAnchor, tlRelPoint, 0, 0)
            clipFrame:SetPoint("RIGHT", brAnchor, brRelPoint, 0, 0)
            clipFrame:SetFrameLevel(healthBar:GetFrameLevel() + 1)
            local texture = clipFrame:CreateTexture(nil, "ARTWORK", nil, sublayer)
            texture:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
            texture:SetPoint("BOTTOMLEFT", healthBar, "BOTTOMLEFT", 0, 0)
            texture:SetWidth(BAR_W)
            return clipFrame, texture
        end

        local _overlayTexKey = (colorKey == "target") and "targetOverlayTexture" or "focusOverlayTexture"
        local _overlayAlphaKey = (colorKey == "target") and "targetOverlayAlpha" or "focusOverlayAlpha"
        local _overlayColorKey = (colorKey == "target") and "targetOverlayColor" or "focusOverlayColor"
        local _overlayFullBgKey = (colorKey == "target") and "targetOverlayFullBgAlpha"
            or "focusOverlayFullBgAlpha"
        -- Empty-portion (bg) opacity: full when "Full alpha on empty part of bar" is on, else dimmed to 30% (matches live plates).
        local function _overlayBgAlpha(oAlpha)
            local full = DBVal(_overlayFullBgKey)
            if full == nil then full = defaultSet[_overlayFullBgKey] end
            if full then return oAlpha end
            return oAlpha * 0.3
        end
        if colorKey == "focus" or colorKey == "target" then
            local texture = DBVal(_overlayTexKey) or defaultSet[_overlayTexKey]
            if texture ~= "none" then
                local fillRef = healthBar:GetStatusBarTexture()
                local oAlpha = DBVal(_overlayAlphaKey) or defaultSet[_overlayAlphaKey]
                local popout = (DB() and DB()[_overlayColorKey]) or defaultSet[_overlayColorKey]
                overlayFillClip, overlayFillTex =
                    MakeOverlayClip(fillRef, "TOPLEFT", fillRef, "BOTTOMRIGHT", 2)
                overlayFillTex:SetTexture(
                    mod.ResolveOverlayTexPath and mod.ResolveOverlayTexPath(texture)
                        or (MEDIA .. texture .. ".png")
                )
                overlayFillTex:SetAlpha(oAlpha)
                overlayFillTex:SetVertexColor(popout.r, popout.g, popout.b)
                overlayBgClip, overlayBgTex =
                    MakeOverlayClip(fillRef, "TOPRIGHT", healthBar, "BOTTOMRIGHT", 1)
                overlayBgTex:SetTexture(
                    mod.ResolveOverlayTexPath and mod.ResolveOverlayTexPath(texture)
                        or (MEDIA .. texture .. ".png")
                )
                overlayBgTex:SetAlpha(_overlayBgAlpha(oAlpha))
                overlayBgTex:SetVertexColor(popout.r, popout.g, popout.b)
            end
        end

        local focusLetter
        local function RefreshFocusLetter()
            if colorKey ~= "focus" then return end
            if DBVal("focusLetterEnabled") ~= true then
                if focusLetter then focusLetter:Hide() end
                return
            end
            if not focusLetter then
                focusLetter = textHolder:CreateFontString(nil, "OVERLAY")
                focusLetter:SetJustifyH("CENTER")
                focusLetter:SetJustifyV("MIDDLE")
            end
            local size = DBVal("focusLetterSize") or defaultSet.focusLetterSize
            local anchor = GetFocusLetterAnchor()
            local posX = DBVal("focusLetterX") or defaultSet.focusLetterX
            local cursorY = DBVal("focusLetterY") or defaultSet.focusLetterY
            local curFont = (CUI.GetFontPath("nameplates")) or DBVal("font")
            SetPVFont(focusLetter, curFont, size, GetNPOptOutline())
            focusLetter:SetText("F")
            focusLetter:ClearAllPoints()
            focusLetter:SetPoint(anchor, healthBar, anchor, posX, cursorY)
            focusLetter:SetTextColor(1, 1, 1, 1)
            focusLetter:Show()
        end
        RefreshFocusLetter()

        -- Live update hook: re-color when swatch changes
        boxHolder.UpdateColor = function()
            local classColor = (DB() and DB()[colorKey]) or defaultSet[colorKey]
            healthBar:SetStatusBarColor(classColor.r, classColor.g, classColor.b, 1)
        end
        -- Live update hook: refresh overlay texture from DB
        boxHolder.UpdateOverlay = function()
            if colorKey ~= "focus" and colorKey ~= "target" then return end
            local texture = DBVal(_overlayTexKey) or defaultSet[_overlayTexKey]
            if texture == "none" then
                if overlayFillClip then overlayFillClip:Hide() end
                if overlayBgClip then overlayBgClip:Hide() end
            else
                local fillRef = healthBar:GetStatusBarTexture()
                local oAlpha = DBVal(_overlayAlphaKey) or defaultSet[_overlayAlphaKey]
                local popout = (DB() and DB()[_overlayColorKey]) or defaultSet[_overlayColorKey]
                if not overlayFillClip then
                    overlayFillClip, overlayFillTex =
                        MakeOverlayClip(fillRef, "TOPLEFT", fillRef, "BOTTOMRIGHT", 2)
                end
                overlayFillTex:SetTexture(
                    mod.ResolveOverlayTexPath and mod.ResolveOverlayTexPath(texture)
                        or (MEDIA .. texture .. ".png")
                )
                overlayFillTex:SetAlpha(oAlpha)
                overlayFillTex:SetVertexColor(popout.r, popout.g, popout.b)
                overlayFillClip:Show()
                if not overlayBgClip then
                    overlayBgClip, overlayBgTex =
                        MakeOverlayClip(fillRef, "TOPRIGHT", healthBar, "BOTTOMRIGHT", 1)
                end
                overlayBgTex:SetTexture(
                    mod.ResolveOverlayTexPath and mod.ResolveOverlayTexPath(texture)
                        or (MEDIA .. texture .. ".png")
                )
                overlayBgTex:SetAlpha(_overlayBgAlpha(oAlpha))
                overlayBgTex:SetVertexColor(popout.r, popout.g, popout.b)
                overlayBgClip:Show()
            end
            RefreshFocusLetter()
        end
        boxHolder.Randomize = function()
            healthPercent = math.floor(60 + math.random() * 15)
            healthVal = math.floor(FAKE_MAX_HP * healthPercent / 100)
            healthBar:SetValue(healthPercent)
            RefreshHealthText()
        end
        -- Exposed so cache-restore / refresh-all can update text from current DB
        boxHolder.RefreshHealthText = RefreshHealthText
        boxHolder.RefreshBorderStyle = function() end -- no style toggle needed for 1px solid
        boxHolder.RefreshBorderColor = function()
            local bc = (DB() and DB().borderColor) or defaultSet.borderColor
            for _, texture in ipairs(boxHolder._brdEdges) do
                texture:SetColorTexture(bc.r, bc.g, bc.b, 1)
            end
        end
    elseif colorType == "cast" or colorType == "castLocked" then
        Pix.Size(boxHolder, BAR_W + 2, BAR_H + 2)

        local castBar = CreateFrame("StatusBar", nil, boxHolder)
        castBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
        castBar:SetMinMaxValues(0, 1)
        castBar:SetValue(NextCastFill())
        castBar:SetAllPoints()

        local castBG = castBar:CreateTexture(nil, "BACKGROUND")
        castBG:SetAllPoints()
        castBG:SetColorTexture(0.20, 0.20, 0.20, 0.9)

        local spark = castBar:CreateTexture(nil, "OVERLAY", nil, 1)
        spark:SetTexture(MEDIA .. "cast_spark.tga")
        spark:SetSize(8, BAR_H)
        spark:SetPoint("CENTER", castBar:GetStatusBarTexture(), "RIGHT", 0, 0)
        spark:SetBlendMode("ADD")
        -- Show Spark (Cast Color cog): default on; explicit false hides it.
        spark:SetShown(DBVal("castBarSparkEnabled") ~= false)

        -- Cast icon frame (to the left) no border for Colors tab previews
        local iconFrame = CreateFrame("Frame", nil, castBar)
        iconFrame:SetSize(BAR_H + 2, BAR_H + 2)
        iconFrame:SetPoint("RIGHT", castBar, "LEFT", 0, 0)
        iconFrame:SetFrameLevel(castBar:GetFrameLevel() + 1)
        local iconTex = iconFrame:CreateTexture(nil, "ARTWORK")
        iconTex:SetAllPoints()
        iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        iconTex:SetTexture(NextCastIcon())

        -- Cast text
        local cns = math.min(DBVal("castNameSize") or defaultSet.castNameSize, 13)
        local cts = math.min(DBVal("castTargetSize") or defaultSet.castTargetSize, 13)
        local cnc = (DB() and DB().castNameColor) or defaultSet.castNameColor

        local dbRef = DB()
        local colShowTimer = defaultSet.showCastTimer
        if dbRef and dbRef.showCastTimer ~= nil then colShowTimer = dbRef.showCastTimer end
        local colCtmSz = math.min((dbRef and dbRef.castTimerSize) or defaultSet.castTimerSize, 13)
        local colCtmC = (dbRef and dbRef.castTimerColor) or defaultSet.castTimerColor
        local colNameSide = (dbRef and dbRef.castNameSide) or defaultSet.castNameSide
        local colTargetSide = (dbRef and dbRef.castTargetSide) or defaultSet.castTargetSide
        local colTimerSide = (dbRef and dbRef.castTimerSide) or defaultSet.castTimerSide
        local colCombine = dbRef and dbRef.castCombineNameTarget == true
        local colTimerW = colCtmSz * 2.2
        -- Per-element cast text truncation (% of bar width + wrap), mirroring runtime.
        local colNameW = BAR_W * ((dbRef and dbRef.castNameWidthPct) or defaultSet.castNameWidthPct) / 100
        local colTgtW = BAR_W * ((dbRef and dbRef.castTargetWidthPct) or defaultSet.castTargetWidthPct) / 100
        local colNameWrap = (dbRef and dbRef.castNameWrap) == true
        local colTgtWrap = (dbRef and dbRef.castTargetWrap) == true

        -- Spell name
        local nameText = castBar:CreateFontString(nil, "OVERLAY")
        SetPVFont(nameText, fontFile, cns, GetNPOptOutline())
        nameText:SetWordWrap(colNameWrap)
        nameText:SetMaxLines(colNameWrap and 2 or 1)
        nameText:SetText(CUI.L("Spell Name"))
        nameText:SetTextColor(cnc.r, cnc.g, cnc.b, 1)
        if colNameSide == "none" then
            nameText:Hide()
        else
            local pt, xb, jh = mod.GetCastTextAnchor(
                colNameSide,
                colShowTimer and colTimerSide == colNameSide,
                colTimerW,
                false
            )
            nameText:SetWidth(
                colCombine
                        and (BAR_W * ((dbRef and dbRef.castCombinedWidthPct) or defaultSet.castCombinedWidthPct) / 100)
                    or colNameW
            )
            nameText:SetJustifyH(jh)
            nameText:SetPoint(pt, castBar, pt, xb, 0)
        end

        -- Cast timer (side only "left"/"right"; visibility via showCastTimer)
        local timerText = castBar:CreateFontString(nil, "OVERLAY")
        SetPVFont(timerText, fontFile, colCtmSz, GetNPOptOutline())
        timerText:SetWordWrap(false)
        timerText:SetMaxLines(1)
        timerText:SetTextColor(colCtmC.r, colCtmC.g, colCtmC.b, 1)
        timerText:SetText("2.3")
        if colShowTimer then
            local tpt, txb, tjh = mod.GetCastTextAnchor(colTimerSide, false, colTimerW, true)
            timerText:SetWidth(colTimerW)
            timerText:SetJustifyH(tjh)
            timerText:SetPoint(tpt, castBar, tpt, txb, 0)
        else
            timerText:Hide()
        end

        -- Spell target
        local targetText = castBar:CreateFontString(nil, "OVERLAY")
        SetPVFont(targetText, fontFile, cts, GetNPOptOutline())
        targetText:SetWordWrap(colTgtWrap)
        targetText:SetNonSpaceWrap(false)
        targetText:SetMaxLines(colTgtWrap and 2 or 1)
        local colTargetText = isHalf and (UnitName("player") or CUI.L("Target"))
            or (UnitName("player") or CUI.L("Spell Target"))
        targetText:SetText(colTargetText)
        local useClassColor = defaultSet.castTargetClassColor
        if dbRef and dbRef.castTargetClassColor ~= nil then useClassColor = dbRef.castTargetClassColor end
        local colTargetHex
        if useClassColor then
            local _, pClass = UnitClass("player")
            local color = pClass and RAID_CLASS_COLORS and RAID_CLASS_COLORS[pClass]
            if color then
                targetText:SetTextColor(color.r, color.g, color.b, 1)
                colTargetHex = (color.GenerateHexColor and color:GenerateHexColor())
                    or color.colorStr
                    or "ffffffff"
            else
                targetText:SetTextColor(1, 1, 1, 1)
                colTargetHex = "ffffffff"
            end
        else
            local ctc = (dbRef and dbRef.castTargetColor) or defaultSet.castTargetColor
            targetText:SetTextColor(ctc.r, ctc.g, ctc.b, 1)
            colTargetHex = string.format(
                "ff%02x%02x%02x",
                math.floor(ctc.r * 255 + 0.5),
                math.floor(ctc.g * 255 + 0.5),
                math.floor(ctc.b * 255 + 0.5)
            )
        end
        if colCombine then
            nameText:SetFormattedText(
                "%s - |c" .. colTargetHex .. "%s|r",
                CUI.L("Spell Name"),
                colTargetText
            )
        end
        if colCombine or colTargetSide == "none" then
            targetText:Hide()
        else
            local pt, xb, jh = mod.GetCastTextAnchor(
                colTargetSide,
                colShowTimer and colTimerSide == colTargetSide,
                colTimerW,
                false
            )
            targetText:SetWidth(colTgtW)
            targetText:SetJustifyH(jh)
            targetText:SetPoint(pt, castBar, pt, xb, 0)
        end

        -- Shield for uninterruptible
        if colorType == "castLocked" then
            local shieldH = BAR_H * 0.75
            local shieldW = shieldH * (29 / 35)
            local shieldFrame = CreateFrame("Frame", nil, castBar)
            shieldFrame:SetSize(shieldW, shieldH)
            shieldFrame:SetPoint("CENTER", castBar, "LEFT", 0, 0)
            shieldFrame:SetFrameLevel(castBar:GetFrameLevel() + 10)
            local shield = shieldFrame:CreateTexture(nil, "OVERLAY")
            shield:SetAllPoints()
            shield:SetTexture(MEDIA .. "shield.png")
        end

        -- Color the bar
        local color = (DB() and DB()[colorKey]) or defaultSet[colorKey]
        castBar:SetStatusBarColor(color.r, color.g, color.b, 1)

        -- Shift container left to account for cast icon hanging outside
        boxHolder:ClearAllPoints()
        Pix.Point(boxHolder, "RIGHT", anchor, "RIGHT", -(20 + SWATCH_SZ + SWATCH_GAP), 0)

        boxHolder.UpdateColor = function()
            local classColor = (DB() and DB()[colorKey]) or defaultSet[colorKey]
            castBar:SetStatusBarColor(classColor.r, classColor.g, classColor.b, 1)
        end
        boxHolder.Randomize = function()
            castBar:SetValue(NextCastFill())
            iconTex:SetTexture(NextCastIcon())
        end
        boxHolder.RefreshBorderStyle = function() end
        boxHolder.RefreshBorderColor = function() end
    end

    return boxHolder
end

local function BuildColorsPage(page, hostFrame, yOffset)
    local environ = mod._NPO_OptEnv
    local _colorPagePreviews, DB, DBColor, DBVal =
        environ._colorPagePreviews, environ.DB, environ.DBColor, environ.DBVal
    local defaultSet, optionState, pairs, Pix = environ.defaults, environ.optState, environ.pairs, environ.PP
    local RefreshAllPlates, SECTION_ENEMY, SECTION_THREAT, THREAT_PCT_POSITION_ORDER =
        environ.RefreshAllPlates,
        environ.SECTION_ENEMY,
        environ.SECTION_THREAT,
        environ.THREAT_PCT_POSITION_ORDER
    local THREAT_PCT_POSITIONS = environ.THREAT_PCT_POSITIONS
    local W = CUI.Widgets
    local cursorY = yOffset
    local _, height

    -- No content header on Colors tab (presets are inline in scroll area)
    CUI:ClearContentHeader()

    -- Enable per-row center divider for the dual-column layout (same as Display tab)
    hostFrame._showRowDivider = true

    -- Track all mini previews for border style refresh
    _G._CUI_ColorPreviews = {}

    -- LazyColorPreviewBar and _colorPagePreviews live at init scope (shared between Display and Colors pages).

    -----------------------------------------------------------------------
    --  ENEMY COLORS
    -----------------------------------------------------------------------
    _, height = W:SectionHeader(hostFrame, SECTION_ENEMY, cursorY)
    cursorY = cursorY - height

    -- Modify Out of Combat is a view over darkenEnemiesOOC + darkenOOCRecolor (the
    -- runtime ignores the recolor flag while darkening is off): No Change = off,
    -- Darken = on, Change Color = on with the recolor. A pick writes only the keys
    -- whose value it changes.
    local function OOCOn()
        local saved = DB()
        if saved and saved.darkenEnemiesOOC ~= nil then return saved.darkenEnemiesOOC end
        return defaultSet.darkenEnemiesOOC
    end
    local function OOCRecolorOn()
        local saved = DB()
        local val = saved and saved.darkenOOCRecolor
        if val == nil then val = defaultSet.darkenOOCRecolor end
        return val
    end
    local function OOCMode()
        if not OOCOn() then return "none" end
        return OOCRecolorOn() and "color" or "darken"
    end

    -- Enemy Types | Modify Out of Combat
    local enemyTypesRow
    enemyTypesRow, height = W:DualRow(hostFrame, cursorY, {
        type = "multiSwatch",
        text = "Enemy Types",
        swatches = {
            {
                tooltip = "Enemies",
                getValue = function() return DBColor("enemyInCombat") end,
                setValue = function(red, green, blue)
                    DB().enemyInCombat = { r = red, g = green, b = blue }
                    RefreshAllPlates()
                end,
            },
            {
                tooltip = "Spell Casters",
                getValue = function() return DBColor("caster") end,
                setValue = function(red, green, blue)
                    DB().caster = { r = red, g = green, b = blue }
                    RefreshAllPlates()
                end,
            },
            {
                tooltip = "Mini-Bosses",
                getValue = function() return DBColor("miniboss") end,
                setValue = function(red, green, blue)
                    DB().miniboss = { r = red, g = green, b = blue }
                    RefreshAllPlates()
                end,
            },
            {
                tooltip = "Bosses",
                getValue = function() return DBColor("boss") end,
                setValue = function(red, green, blue)
                    DB().boss = { r = red, g = green, b = blue }
                    RefreshAllPlates()
                end,
            },
        },
    }, {
        type = "dropdown",
        text = "Modify Out of Combat",
        values = { none = "No Change", darken = "Darken", color = "Change Color" },
        order = { "none", "darken", "color" },
        getValue = OOCMode,
        -- The inline color swatch exists only for Change Color: rebuild when that flips.
        setValue = CUI.DependentSetValue(function() return OOCMode() == "color" end, function(val)
            local on = val ~= "none"
            local saved = DB()
            if OOCOn() ~= on then saved.darkenEnemiesOOC = on end
            if on and OOCRecolorOn() ~= (val == "color") then saved.darkenOOCRecolor = (val == "color") end
            if mod.NP_CastTintsDirty then mod.NP_CastTintsDirty() end
            for _, backing in pairs(mod.plates) do
                backing:UpdateHealthColor()
            end
            CUI:RefreshPage()
        end),
        tooltip = "How enemy plates look while out of combat.",
    })
    cursorY = cursorY - height

    -- Change Color's flat color (MaybeDarken), inline beside the dropdown while
    -- that mode is picked.
    if not CUI._prebuilding and OOCMode() == "color" then
        CUI.BuildInlineSwatches(enemyTypesRow._rightRegion, {
            {
                tooltip = "Out of Combat Color",
                getValue = function()
                    local saved = DB()
                    local color = (saved and saved.darkenOOCColor) or defaultSet.darkenOOCColor
                    return color.r, color.g, color.b
                end,
                setValue = function(red, green, blue)
                    DB().darkenOOCColor = { r = red, g = green, b = blue }
                    if mod.NP_CastTintsDirty then mod.NP_CastTintsDirty() end
                    for _, backing in pairs(mod.plates) do
                        backing:UpdateHealthColor()
                    end
                end,
            },
        })
    end

    -- Inline cog on "Enemy Types": Simple Coloring When Not In M+. On: outside 5-man dungeons, Mini/Caster/Miniboss/Boss all use the flat "All Enemies" color below (Neutral keeps its own); off (default) has no effect anywhere. Keys keep their owBasic* names from before the current UI label.
    if not CUI._prebuilding then
        local leftRegion = enemyTypesRow._leftRegion
        local isOWOff = function()
            local val = DBVal("owBasicColoring")
            if val == nil then return not defaultSet.owBasicColoring end
            return not val
        end
        CUI.BuildInlineCog(leftRegion, {
            title = "Enemy Colors",
            rows = {
                {
                    type = "toggle",
                    label = "Simple Coloring When Not In M+",
                    get = function()
                        local val = DBVal("owBasicColoring")
                        if val == nil then return defaultSet.owBasicColoring end
                        return val
                    end,
                    set = function(val)
                        DB().owBasicColoring = val
                        RefreshAllPlates()
                    end,
                },
                {
                    type = "colorpicker",
                    label = "All Enemies",
                    get = function() return DBColor("owBasicColor") end,
                    set = function(red, green, blue)
                        DB().owBasicColor = { r = red, g = green, b = blue }
                        RefreshAllPlates()
                    end,
                    disabled = isOWOff,
                    disabledTooltip = "Simple Coloring When Not In M+",
                },
            },
        })
    end

    -- Neutral & Mini Enemies | Enable Quest Mob Color
    local neutralMiniRow
    neutralMiniRow, height = W:DualRow(hostFrame, cursorY, {
        type = "multiSwatch",
        text = "Neutral & Mini Enemies",
        swatches = {
            {
                tooltip = "Neutral",
                getValue = function() return DBColor("neutral") end,
                setValue = function(red, green, blue)
                    DB().neutral = { r = red, g = green, b = blue }
                    RefreshAllPlates()
                end,
            },
            {
                tooltip = "Mini Enemies",
                -- Until explicitly set, views the user's "Enemies" color so the swatch starts matching enemyInCombat (see GetReactionColor).
                getValue = function()
                    local saved = DB()
                    local color = (saved and saved.miniEnemy)
                        or (saved and saved.enemyInCombat)
                        or defaultSet.enemyInCombat
                    return color.r, color.g, color.b
                end,
                setValue = function(red, green, blue)
                    DB().miniEnemy = { r = red, g = green, b = blue }
                    RefreshAllPlates()
                end,
            },
        },
    }, {
        type = "toggle",
        text = "Enable Quest Mob Color",
        getValue = function() return DBVal("questMobColorEnabled") == true end,
        setValue = function(val)
            DB().questMobColorEnabled = val
            for _, backing in pairs(mod.plates) do
                backing:UpdateHealthColor()
            end
            CUI:RefreshPage()
        end,
        tooltip = "Colors enemy nameplates for quest mobs you still need to kill.",
    })
    cursorY = cursorY - height

    -- Inline Quest Mob Color swatch
    if not CUI._prebuilding then
        local rightRegion = neutralMiniRow._rightRegion
        local questColorGet = function()
            local color = DB().questMobColor or defaultSet.questMobColor
            return color.r, color.g, color.b
        end
        local questColorSet = function(red, green, blue)
            DB().questMobColor = { r = red, g = green, b = blue }
            RefreshAllPlates()
        end
        local isQuestOff = function() return DBVal("questMobColorEnabled") ~= true end
        local colorSwatch, updateSwatch = CUI.BuildColorSwatch(
            rightRegion,
            rightRegion:GetFrameLevel() + 5,
            questColorGet,
            questColorSet,
            nil,
            20
        )
        Pix.Point(colorSwatch, "RIGHT", rightRegion._control, "LEFT", -12, 0)
        CUI.RegisterWidgetRefresh(function()
            local off = isQuestOff()
            colorSwatch:SetAlpha(off and 0.15 or 1)
            colorSwatch:EnableMouse(not off)
            updateSwatch()
        end)
        local off = isQuestOff()
        colorSwatch:SetAlpha(off and 0.15 or 1)
        colorSwatch:EnableMouse(not off)
    end

    -- Inline cog on "Neutral & Mini Enemies": "Mini Coloring M+ Only" toggle. On (default) restricts the Mini Enemies color to 5-man dungeons; off applies it everywhere.
    if not CUI._prebuilding then
        local leftRegion = neutralMiniRow._leftRegion
        CUI.BuildInlineCog(leftRegion, {
            title = "Mini Enemies",
            rows = {
                {
                    type = "toggle",
                    label = "Mini Coloring M+ Only",
                    get = function()
                        local val = DBVal("miniColoringMPlusOnly")
                        if val == nil then return defaultSet.miniColoringMPlusOnly end
                        return val
                    end,
                    set = function(val)
                        DB().miniColoringMPlusOnly = val
                        RefreshAllPlates()
                    end,
                },
            },
        })
    end

    -- Color Casting Enemies | Enemy Players Use Enemy Color
    local castingRow
    castingRow, height = W:DualRow(hostFrame, cursorY, {
        type = "toggle",
        text = "Color Casting Enemies",
        getValue = function() return DBVal("castingEnemyColors") == true end,
        setValue = function(val)
            DB().castingEnemyColors = val
            RefreshAllPlates()
            CUI:RefreshPage()
        end,
        tooltip = "Enemies not colored as Spell Casters take the Interruptible Caster or Uninterruptible Caster color once they cast a spell that can or cannot be interrupted.",
    }, {
        type = "toggle",
        text = "Enemy Players Use Enemy Color",
        getValue = function() return DBVal("enemyPlayerEnemyColor") == true end,
        setValue = function(val)
            DB().enemyPlayerEnemyColor = val
            RefreshAllPlates()
        end,
        tooltip = "Enemy players take the Enemies color instead of their class color.",
    })
    cursorY = cursorY - height

    -- Inline cog with the mob types each applies to, then the Interruptible / Uninterruptible swatches.
    if not CUI._prebuilding then
        local region = castingRow._leftRegion
        local isCastingOff = function() return DBVal("castingEnemyColors") ~= true end
        local typeItems = {
            { key = "Normal", label = "Normal / Trivial", fixed = true },
            { key = "Elite", label = "Elite", fixed = true },
            { key = "MiniBoss", label = "Mini-Bosses", fixed = true },
            { key = "Boss", label = "Bosses", fixed = true },
        }
        local function TypeRow(labelText, prefixText)
            -- hint replaces the widget's "Drag to Reorder": every row is fixed.
            return {
                type = "reordercheck",
                label = labelText,
                ddWidth = 170,
                items = typeItems,
                hint = "Enemy Types",
                get = function(colorKey) return DBVal(prefixText .. colorKey) end,
                set = function(colorKey, val)
                    DB()[prefixText .. colorKey] = val
                    RefreshAllPlates()
                end,
            }
        end
        CUI.BuildInlineCog(region, {
            title = "Casting Enemies",
            disabled = isCastingOff,
            disabledTooltip = "Color Casting Enemies",
            rows = {
                TypeRow("Interruptible Applies To", "castingInt"),
                TypeRow("Uninterruptible Applies To", "castingUnint"),
            },
        })
        CUI.BuildInlineSwatches(region, {
            {
                tooltip = "Interruptible Caster",
                getValue = function() return DBColor("castingIntColor") end,
                setValue = function(red, green, blue)
                    DB().castingIntColor = { r = red, g = green, b = blue }
                    RefreshAllPlates()
                end,
            },
            {
                tooltip = "Uninterruptible Caster",
                getValue = function() return DBColor("castingUnintColor") end,
                setValue = function(red, green, blue)
                    DB().castingUnintColor = { r = red, g = green, b = blue }
                    RefreshAllPlates()
                end,
            },
        }, { disabled = isCastingOff, disabledTooltip = "Color Casting Enemies" })
    end

    _, height = W:Spacer(hostFrame, cursorY, 20)
    cursorY = cursorY - height

    -----------------------------------------------------------------------
    --  THREAT COLORS
    -----------------------------------------------------------------------
    _, height = W:SectionHeader(hostFrame, SECTION_THREAT, cursorY)
    cursorY = cursorY - height

    -- Show Threat Colors (threatColorMode): Never / Instances (dungeons, raids and
    -- delves) / Group or Pet ("always": everywhere) / Always ("alwaysSolo"); an unknown
    -- saved value reads as the default. Never locks every threat-color control below.
    -- The WoW Forever Threat % rows are their own feature and stay live. Under the first
    -- two, damage dealers and healers get the colors in a group or with a pet out; Always
    -- drops that rule. On WoW Forever the tank shapes and Righteous Fury count as tanking
    -- while nobody in the group has the tank role.
    local function threatModeGet()
        local val = DBVal("threatColorMode")
        if val ~= "never" and val ~= "instances" and val ~= "always" and val ~= "alwaysSolo" then
            val = defaultSet.threatColorMode
        end
        return val
    end
    local function noThreat() return threatModeGet() == "never" end

    -- Row 1: Show Threat Colors (left) ---- Tank Threat (right)
    _, height = W:DualRow(hostFrame, cursorY, {
        type = "dropdown",
        text = "Show Threat Colors",
        tooltip = "Where nameplates show threat colors.",
        values = { never = "Never", instances = "Instances", always = "Group or Pet", alwaysSolo = "Always" },
        order = { "never", "instances", "always", "alwaysSolo" },
        getValue = threatModeGet,
        setValue = function(val)
            DB().threatColorMode = val
            mod.NP_ApplyThreatColorMode()
            CUI:RefreshPage()
        end,
    }, {
        type = "multiSwatch",
        text = "Tank Threat",
        disabled = noThreat,
        disabledTooltip = "Show Threat Colors",
        swatches = {
            {
                tooltip = "Losing Aggro",
                getValue = function() return DBColor("tankLosingAggro") end,
                setValue = function(red, green, blue)
                    DB().tankLosingAggro = { r = red, g = green, b = blue }
                    RefreshAllPlates()
                end,
            },
            {
                tooltip = "No Aggro",
                getValue = function() return DBColor("tankNoAggro") end,
                setValue = function(red, green, blue)
                    DB().tankNoAggro = { r = red, g = green, b = blue }
                    RefreshAllPlates()
                end,
            },
        },
    })
    cursorY = cursorY - height

    -- Disabled-state helpers (shared across the toggle rows' swatches and cogs)
    local function isTankHasAggroDisabled()
        local saved = DB()
        if saved and saved.tankHasAggroEnabled ~= nil then return not saved.tankHasAggroEnabled end
        return not defaultSet.tankHasAggroEnabled
    end
    local function isClassicTankAggroDisabled()
        local saved = DB()
        if saved and saved.classicTankAggro ~= nil then return not saved.classicTankAggro end
        return not defaultSet.classicTankAggro
    end
    local function isOffTankDisabled()
        local saved = DB()
        if saved and saved.offTankAggroEnabled ~= nil then return not saved.offTankAggroEnabled end
        return not defaultSet.offTankAggroEnabled
    end
    local function isDpsNoAggroDisabled()
        local saved = DB()
        if saved and saved.dpsNoAggroEnabled ~= nil then return not saved.dpsNoAggroEnabled end
        return not defaultSet.dpsNoAggroEnabled
    end
    -- The Override toggles only reorder the health bar's color priority, so the No Aggro
    -- and Has Aggro cogs (Override rows only) lock while Show Threat On leaves the Health Bar out.
    local function isThreatHealthOff() return not mod.GetThreatColorHealth() end

    -- Inline swatch lock for the toggle rows: dimmed and click-blocked while its own
    -- toggle is off or Show Threat Colors is Never; the block names the missing one.
    local function LockThreatSwatch(colorSwatch, updateSwatch, ownOff, ownReq)
        local tipCfg = {
            disabledTooltip = function()
                if noThreat() then return "Show Threat Colors" end
                return ownReq
            end,
        }
        local block = CUI.NewSwatchBlocker(colorSwatch)
        block:SetScript(
            "OnEnter",
            function() CUI.ShowWidgetTooltip(colorSwatch, CUI.ResolveDisabledTip(tipCfg)) end
        )
        block:SetScript("OnLeave", function() CUI.HideWidgetTooltip() end)
        local function State()
            local off = noThreat() or ownOff()
            colorSwatch:SetAlpha(off and 0.3 or 1)
            block:SetShown(off)
        end
        CUI.RegisterWidgetRefresh(function()
            State()
            updateSwatch()
        end)
        State()
    end

    -- Row 2: Non-Tank Threat (left) ---- DPS: Show Special "No Aggro" Color (right)
    local nonTankRow
    nonTankRow, height = W:DualRow(hostFrame, cursorY, {
        type = "multiSwatch",
        text = "Non-Tank Threat",
        disabled = noThreat,
        disabledTooltip = "Show Threat Colors",
        swatches = {
            {
                tooltip = "Has Aggro",
                getValue = function() return DBColor("dpsHasAggro") end,
                setValue = function(red, green, blue)
                    DB().dpsHasAggro = { r = red, g = green, b = blue }
                    RefreshAllPlates()
                end,
            },
            {
                tooltip = "Near Aggro",
                getValue = function() return DBColor("dpsNearAggro") end,
                setValue = function(red, green, blue)
                    DB().dpsNearAggro = { r = red, g = green, b = blue }
                    RefreshAllPlates()
                end,
            },
        },
    }, {
        type = "toggle",
        text = 'DPS: Show Special "No Aggro" Color',
        tooltip = "Shows a special color for non caster/mini-boss enemies when you do not have aggro on them.",
        disabled = noThreat,
        disabledTooltip = "Show Threat Colors",
        getValue = function()
            local saved = DB()
            if saved and saved.dpsNoAggroEnabled ~= nil then return saved.dpsNoAggroEnabled end
            return defaultSet.dpsNoAggroEnabled
        end,
        setValue = function(val)
            DB().dpsNoAggroEnabled = val
            RefreshAllPlates()
            CUI:RefreshPage()
        end,
    })
    cursorY = cursorY - height

    -- Inline cog on "Non-Tank Threat": steady red execute-style glow
    -- while the Near Aggro color is active (see EnsureNearAggroGlow).
    if not CUI._prebuilding then
        CUI.BuildInlineCog(nonTankRow._leftRegion, {
            disabled = noThreat,
            disabledTooltip = "Show Threat Colors",
            title = "Near Aggro",
            rows = {
                {
                    type = "toggle",
                    label = "Glow Nameplate When Near Aggro",
                    tooltip = "Adds a steady red glow around the nameplate while the Near Aggro color is active.",
                    get = function()
                        local saved = DB()
                        local val = saved and saved.threatNearAggroGlow
                        if val == nil then val = defaultSet.threatNearAggroGlow end
                        return val
                    end,
                    set = function(val)
                        DB().threatNearAggroGlow = val and true or false
                        for _, backing in pairs(mod.plates) do
                            backing:UpdateHealthColor()
                        end
                    end,
                },
            },
        })
    end

    -- Inline cog next to the DPS toggle, then the "No Aggro" color swatch left of it
    if not CUI._prebuilding then
        local region = nonTankRow._rightRegion
        local dpsNoAggroColorGet = function() return DBColor("dpsNoAggro") end
        local dpsNoAggroColorSet = function(red, green, blue)
            DB().dpsNoAggro = { r = red, g = green, b = blue }
            RefreshAllPlates()
        end

        -- Inline cog: independent "Override Mini-Boss colors" / "Override Caster colors" / "Override Boss colors" toggles promote the DPS No Aggro color above that single mob-type color (kept separate for contrast); dimmed while off.
        CUI.BuildInlineCog(region, {
            disabled = function() return noThreat() or isDpsNoAggroDisabled() or isThreatHealthOff() end,
            disabledTooltip = function()
                if noThreat() then return "Show Threat Colors" end
                if isDpsNoAggroDisabled() then return 'DPS: Show Special "No Aggro" Color' end
                return "Health Bar"
            end,
            title = "No Aggro",
            rows = {
                {
                    type = "toggle",
                    label = "Override Mini-Boss colors",
                    get = function()
                        local saved = DB()
                        if saved and saved.dpsNoAggroOverrideMiniBoss ~= nil then
                            return saved.dpsNoAggroOverrideMiniBoss
                        end
                        return defaultSet.dpsNoAggroOverrideMiniBoss
                    end,
                    set = function(val)
                        DB().dpsNoAggroOverrideMiniBoss = val
                        RefreshAllPlates()
                    end,
                },
                {
                    type = "toggle",
                    label = "Override Caster colors",
                    get = function()
                        local saved = DB()
                        if saved and saved.dpsNoAggroOverrideCaster ~= nil then
                            return saved.dpsNoAggroOverrideCaster
                        end
                        return defaultSet.dpsNoAggroOverrideCaster
                    end,
                    set = function(val)
                        DB().dpsNoAggroOverrideCaster = val
                        RefreshAllPlates()
                    end,
                },
                {
                    type = "toggle",
                    label = "Override Boss colors",
                    get = function()
                        local saved = DB()
                        if saved and saved.dpsNoAggroOverrideBoss ~= nil then
                            return saved.dpsNoAggroOverrideBoss
                        end
                        return defaultSet.dpsNoAggroOverrideBoss
                    end,
                    set = function(val)
                        DB().dpsNoAggroOverrideBoss = val
                        RefreshAllPlates()
                    end,
                },
            },
        })
        local colorSwatch, updateSwatch = CUI.BuildColorSwatch(
            region,
            region:GetFrameLevel() + 5,
            dpsNoAggroColorGet,
            dpsNoAggroColorSet,
            nil,
            20
        )
        Pix.Point(colorSwatch, "RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
        region._lastInline = colorSwatch
        LockThreatSwatch(
            colorSwatch,
            updateSwatch,
            isDpsNoAggroDisabled,
            'DPS: Show Special "No Aggro" Color'
        )
    end

    -- Row 3: Classic Tank Aggro (left) ---- Tank: Show Special "Has Aggro" Color (right)
    local tankAggroRow
    tankAggroRow, height = W:DualRow(hostFrame, cursorY, {
        type = "toggle",
        text = "Classic Tank Aggro",
        tooltip = "Enables a three-tier tank aggro system: has aggro, losing aggro, and no aggro colors override all mob-type colors.",
        disabled = noThreat,
        disabledTooltip = "Show Threat Colors",
        getValue = function()
            local saved = DB()
            if saved and saved.classicTankAggro ~= nil then return saved.classicTankAggro end
            return defaultSet.classicTankAggro
        end,
        setValue = function(val)
            DB().classicTankAggro = val
            RefreshAllPlates()
            CUI:RefreshPage()
        end,
    }, {
        type = "toggle",
        text = 'Tank: Show Special "Has Aggro" Color',
        tooltip = "Shows a special color for non caster/mini-boss enemies when you have aggro on them.",
        disabled = noThreat,
        disabledTooltip = "Show Threat Colors",
        getValue = function()
            local saved = DB()
            if saved and saved.tankHasAggroEnabled ~= nil then return saved.tankHasAggroEnabled end
            return defaultSet.tankHasAggroEnabled
        end,
        setValue = function(val)
            DB().tankHasAggroEnabled = val
            RefreshAllPlates()
            CUI:RefreshPage()
        end,
    })
    cursorY = cursorY - height

    -- Inline "Has Aggro" color swatch next to Classic Tank Aggro toggle
    if not CUI._prebuilding then
        local region = tankAggroRow._leftRegion
        local aggroColorGet = function() return DBColor("tankHasAggro") end
        local aggroColorSet = function(red, green, blue)
            DB().tankHasAggro = { r = red, g = green, b = blue }
            RefreshAllPlates()
        end
        local colorSwatch, updateSwatch = CUI.BuildColorSwatch(
            region,
            region:GetFrameLevel() + 5,
            aggroColorGet,
            aggroColorSet,
            nil,
            20
        )
        Pix.Point(colorSwatch, "RIGHT", region._control, "LEFT", -12, 0)
        LockThreatSwatch(colorSwatch, updateSwatch, isClassicTankAggroDisabled, "Classic Tank Aggro")
    end

    -- Inline cog next to the tank Has Aggro toggle, then the "Has Aggro" color swatch left of it
    if not CUI._prebuilding then
        local region = tankAggroRow._rightRegion
        local tankAggroColorGet = function() return DBColor("tankHasAggro") end
        local tankAggroColorSet = function(red, green, blue)
            DB().tankHasAggro = { r = red, g = green, b = blue }
            RefreshAllPlates()
        end

        -- Inline cog "Override Mini-Boss and Caster colors" promotes the tank has-aggro color above the mini-boss/caster priority steps; dimmed while Has Aggro is off.
        CUI.BuildInlineCog(region, {
            disabled = function() return noThreat() or isTankHasAggroDisabled() or isThreatHealthOff() end,
            disabledTooltip = function()
                if noThreat() then return "Show Threat Colors" end
                if isTankHasAggroDisabled() then return 'Tank: Show Special "Has Aggro" Color' end
                return "Health Bar"
            end,
            title = "Has Aggro",
            rows = {
                {
                    type = "toggle",
                    label = "Override Mini-Boss and Caster colors",
                    get = function()
                        local saved = DB()
                        if saved and saved.tankHasAggroOverrideMobType ~= nil then
                            return saved.tankHasAggroOverrideMobType
                        end
                        return defaultSet.tankHasAggroOverrideMobType
                    end,
                    set = function(val)
                        DB().tankHasAggroOverrideMobType = val
                        RefreshAllPlates()
                    end,
                },
                {
                    type = "toggle",
                    label = "Override Boss colors",
                    get = function()
                        local saved = DB()
                        if saved and saved.tankHasAggroOverrideBoss ~= nil then
                            return saved.tankHasAggroOverrideBoss
                        end
                        return defaultSet.tankHasAggroOverrideBoss
                    end,
                    set = function(val)
                        DB().tankHasAggroOverrideBoss = val
                        RefreshAllPlates()
                    end,
                },
            },
        })
        local colorSwatch, updateSwatch = CUI.BuildColorSwatch(
            region,
            region:GetFrameLevel() + 5,
            tankAggroColorGet,
            tankAggroColorSet,
            nil,
            20
        )
        Pix.Point(colorSwatch, "RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
        region._lastInline = colorSwatch
        LockThreatSwatch(
            colorSwatch,
            updateSwatch,
            isTankHasAggroDisabled,
            'Tank: Show Special "Has Aggro" Color'
        )
    end

    -- Show Threat On: which parts of the plate carry the threat colors above. Border and
    -- Name are second signals beside the Health Bar, so the bar can keep its Enemy Types
    -- color (Caster / Mini-Boss / Boss) while the border and the name show aggro.
    -- Border locks while no CUI border is drawn (None, or a stock style). Built as a
    -- placeholder dropdown (its disabled config dims the label and blocks the slot) and
    -- replaced below in whichever half of chanRow holds it.
    local chanCfg = {
        type = "dropdown",
        text = "Show Threat On",
        disabled = noThreat,
        disabledTooltip = "Show Threat Colors",
        values = { __placeholder = "..." },
        order = { "__placeholder" },
        getValue = function() return "__placeholder" end,
        setValue = function() end,
    }

    -- WoW Forever Threat % helpers and toggle (nil on retail, where Show Threat On
    -- takes the Off-Tank row's right slot instead).
    local threatPctOff, ThreatPctSet, offTankRightCfg
    if CUI.IS_FOREVER then
        threatPctOff = function() return not DBVal("threatPctEnabled") end
        ThreatPctSet = function(colorKey, val)
            DB()[colorKey] = val
            mod.RefreshThreatPct()
        end
        offTankRightCfg = {
            type = "toggle",
            text = "Show Threat % on Nameplates",
            tooltip = "Shows your threat percentage on each enemy nameplate while you are in combat with it.",
            getValue = function() return DBVal("threatPctEnabled") end,
            setValue = function(val)
                ThreatPctSet("threatPctEnabled", val)
                CUI:RefreshPage()
            end,
        }
    else
        offTankRightCfg = chanCfg
    end

    -- Row 4: Tank: Show Special "Off-Tank" Color (left) ---- Show Threat On (right);
    -- on WoW Forever the right slot is Show Threat % on Nameplates.
    local offTankRow
    offTankRow, height = W:DualRow(hostFrame, cursorY, {
        type = "toggle",
        text = 'Tank: Show Special "Off-Tank" Color',
        tooltip = "Shows a special color for nameplates that another tank in your raid has aggro on.",
        disabled = noThreat,
        disabledTooltip = "Show Threat Colors",
        getValue = function()
            local saved = DB()
            if saved and saved.offTankAggroEnabled ~= nil then return saved.offTankAggroEnabled end
            return defaultSet.offTankAggroEnabled
        end,
        setValue = function(val)
            DB().offTankAggroEnabled = val
            RefreshAllPlates()
            CUI:RefreshPage()
        end,
    }, offTankRightCfg)
    cursorY = cursorY - height

    -- Inline "Off-Tank" color swatch next to the Off-Tank toggle
    if not CUI._prebuilding then
        local region = offTankRow._leftRegion
        local otColorGet = function() return DBColor("offTankAggro") end
        local otColorSet = function(red, green, blue)
            DB().offTankAggro = { r = red, g = green, b = blue }
            RefreshAllPlates()
        end
        local colorSwatch, updateSwatch =
            CUI.BuildColorSwatch(region, region:GetFrameLevel() + 5, otColorGet, otColorSet, nil, 20)
        Pix.Point(colorSwatch, "RIGHT", region._control, "LEFT", -12, 0)
        LockThreatSwatch(colorSwatch, updateSwatch, isOffTankDisabled, 'Tank: Show Special "Off-Tank" Color')
    end

    -- Row 5 (WoW Forever only): Threat % Position (left) ---- Show Threat On (right).
    local chanRow = offTankRow
    if CUI.IS_FOREVER then
        local threatPctRow
        threatPctRow, height = W:DualRow(hostFrame, cursorY, {
            type = "dropdown",
            text = "Threat % Position",
            values = THREAT_PCT_POSITIONS,
            order = THREAT_PCT_POSITION_ORDER,
            disabled = threatPctOff,
            disabledTooltip = "Show Threat % on Nameplates",
            getValue = function() return DBVal("threatPctPosition") end,
            setValue = function(val) ThreatPctSet("threatPctPosition", val) end,
        }, chanCfg)
        cursorY = cursorY - height
        chanRow = threatPctRow

        if not CUI._prebuilding then
            CUI.BuildInlineCog(threatPctRow._leftRegion, {
                title = "Threat %",
                disabled = threatPctOff,
                disabledTooltip = "Show Threat % on Nameplates",
                rows = mod.NPO_ThreatPctRows(DBVal, ThreatPctSet),
            })
        end
    end

    -- Replace the Show Threat On placeholder with a multi-select checkbox dropdown,
    -- in whichever half of chanRow was built from chanCfg.
    if not CUI._prebuilding then
        local region = chanRow._rightRegion
        if chanRow._leftRegion._cfg == chanCfg then region = chanRow._leftRegion end
        if region._control then region._control:Hide() end
        -- A locked Border also drops out of the summary, which then reads what is drawn.
        local function isThreatBorderLocked()
            return not (mod.IsBorderEnabled() or mod.IsCustomBorderEnabled())
        end
        local chanItems = {
            { key = "health", label = "Health Bar" },
            {
                key = "border",
                label = "Border",
                lockedFn = isThreatBorderLocked,
                excludeFromSummaryFn = isThreatBorderLocked,
                lockedTooltip = function()
                    if CUI.BlizzStyle.Get("nameplates") then
                        return CUI.DisabledTooltip(CUI.BlizzStyle.Label("nameplates"), "disabled")
                    end
                    return "This option requires a Border to be selected"
                end,
            },
            { key = "name", label = "Name" },
        }
        local checkDrop, cbDDRefresh = CUI.BuildVisOptsCBDropdown(
            region,
            170,
            region:GetFrameLevel() + 2,
            chanItems,
            function(keyName)
                if keyName == "health" then return mod.GetThreatColorHealth() end
                if keyName == "border" then return mod.GetThreatColorBorder() end
                if keyName == "name" then return mod.GetThreatColorName() end
                return false
            end,
            function(keyName, val)
                if keyName == "health" then
                    DB().threatColorHealth = val
                elseif keyName == "border" then
                    DB().threatColorBorder = val
                elseif keyName == "name" then
                    DB().threatColorName = val
                end
                RefreshAllPlates()
                -- Health Bar gates the No Aggro and Has Aggro cogs.
                CUI:RefreshPage()
            end
        )
        Pix.Point(checkDrop, "RIGHT", region, "RIGHT", -20, 0)
        region._control = checkDrop
        checkDrop:HookScript(
            "OnEnter",
            function()
                CUI.ShowWidgetTooltip(
                    checkDrop,
                    "Chooses which parts of the nameplate show the threat colors; with Health Bar off, the bar keeps its Enemy Types color."
                )
            end
        )
        checkDrop:HookScript("OnLeave", function() CUI.HideWidgetTooltip() end)
        CUI.RegisterWidgetRefresh(cbDDRefresh)
        -- The checkbox dropdown has no disabled state of its own: grey it and block
        -- clicks while Show Threat Colors is Never; the placeholder's disabled overlay
        -- over the same slot shows the requirement.
        local function ApplyChanDisabled()
            local off = noThreat()
            checkDrop:SetAlpha(off and 0.3 or 1)
            checkDrop:EnableMouse(not off)
        end
        ApplyChanDisabled()
        CUI.RegisterWidgetRefresh(ApplyChanDisabled)
    end

    _, height = W:Spacer(hostFrame, cursorY, 20)
    cursorY = cursorY - height

    cursorY = mod.NP_BuildDebuffColorsOptions(hostFrame, cursorY)

    -- Build a refresh-all function for page cache restore
    optionState._colorPreviewRefreshAll = function()
        for _, previous in ipairs(_G._CUI_ColorPreviews) do
            if previous.UpdateColor then previous.UpdateColor() end
            if previous.UpdateOverlay then previous.UpdateOverlay() end
            if previous.RefreshBorderColor then previous.RefreshBorderColor() end
            if previous.RefreshHealthText then previous.RefreshHealthText() end
        end
        for _, previous in ipairs(_colorPagePreviews) do
            if previous.UpdateColor then previous.UpdateColor() end
            if previous.UpdateOverlay then previous.UpdateOverlay() end
            if previous.RefreshBorderColor then previous.RefreshBorderColor() end
            if previous.RefreshHealthText then previous.RefreshHealthText() end
        end
    end
    for _, previous in ipairs(_colorPagePreviews) do
        if previous.UpdateColor then CUI.RegisterWidgetRefresh(previous.UpdateColor) end
        if previous.UpdateOverlay then CUI.RegisterWidgetRefresh(previous.UpdateOverlay) end
    end

    return math.abs(cursorY)
end

-- Used by CUI_Nameplates_Options.lua
mod.NPO_MakeColorPreviewBar = MakeColorPreviewBar
mod.NPO_BuildColorsPage = BuildColorsPage
