if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
local mod = CUI._ModuleNS["CludesUIUnitFrames"]
if not mod then return end

local MOVE_KEYS = {
    "X",
    "Y",
    "WidthPct",
    "ClassColor",
    "ColorR",
    "ColorG",
    "ColorB",
    "NameFormat",
    "TargetSep",
    "TargetPrefix",
    "TargetSepColor",
    "TargetSepClassColor",
    "CustomFormat",
}

-- False for content a slot keeps to itself: "none", and "custom", whose format
-- is stored per slot, so several slots may use it and none is picked for them.
function mod.UF_IsUniqueContent(val) return val ~= "none" and val ~= "custom" end

-- Custom text popup for any text slot. prefix names the slot's keys
-- (<prefix>CustomFormat, ClassColor, ColorR/G/B); db is the unit's settings;
-- onSave runs after the format is stored and selects Custom for the slot.
function mod.UFO_EditCustomText(prefixText, db, unitToken, onSave)
    local key = prefixText .. "CustomFormat"
    -- The preview in the slot's text colour, as the unit preview shows it.
    local color
    -- Power Colored: the page's unit while it exists (boss1 for Boss),
    -- else the player, as the unit preview shows it.
    local function PowerColor()
        local u = unitToken == "boss" and "boss1" or unitToken
        local red, green, blue = CUI.ResolveUnitPowerColor((u and UnitExists(u)) and u or "player")
        return red and { r = red, g = green, b = blue }
    end
    if prefixText == "powerText" then
        -- The power text's own keys: Power Colored, else powerTextColor.
        local pc = db.powerPercentTextPowerColor and PowerColor()
        color = pc or (not db.powerPercentTextPowerColor and db.powerTextColor) or { r = 1, g = 1, b = 1 }
    elseif db[prefixText .. "PowerColor"] then
        -- The text bar's Power Colored. Fixed for the popup: the bar uses it
        -- only while the format holds a power tag.
        color = PowerColor()
    elseif db[prefixText .. "ClassColor"] then
        if unitToken == "player" then
            local _, classTok = UnitClass("player")
            color = classTok and CUI.GetClassColor(classTok)
        else
            color = { r = 0.9, g = 0.3, b = 0.3 }
        end
    else
        color = {
            r = db[prefixText .. "ColorR"] or 1,
            g = db[prefixText .. "ColorG"] or 1,
            b = db[prefixText .. "ColorB"] or 1,
        }
    end
    CUI.TextTags.EditPopup({
        cat = mod.UF_TextTags,
        color = color,
        onSave = onSave,
        tagNotes = { hp = CUI.L("shows DEAD or OFFLINE") },
        get = function() return db[key] end,
        set = function(txt) db[key] = txt end,
    })
end

-- A copy of a slot's dropdown values whose Custom entry is an action that
-- opens the popup (edit), its pencil at full alpha while getValue() is
-- "custom". The menu reads the alpha when it is built, so a selection has
-- to rebuild it (page rebuild or _invalidateMenu).
function mod.UFO_CustomTextValues(values, getValue, edit)
    return CUI.TextTags.MenuValues(values, edit, {
        selected = function() return getValue() == "custom" end,
    })
end

-- For a dropdown whose selection keeps the page: rebuilds the given regions'
-- menus once the list has closed, for Custom's pencil to follow the selection.
-- The widget refresh is the menu's own deferred one, which Custom's popup path
-- never reaches: without it colour swatches and cogs keep the previous state.
function mod.UFO_RefreshMenus(...)
    local num, rgns = select("#", ...), { ... }
    C_Timer.After(0, function()
        for idx = 1, num do
            local dropdown = rgns[idx] and rgns[idx]._control
            if dropdown and dropdown._invalidateMenu then dropdown._invalidateMenu() end
        end
        local refreshList = CUI._widgetRefreshList
        if refreshList then
            for ri = 1, #refreshList do
                refreshList[ri]()
            end
        end
    end)
end

-- The power text cog (Main and Boss): Show % for the preset formats in pctOff's
-- complement; Custom writes its own %, so it keeps only the Name Format, and
-- only while the format shows a name.
local PCT_TIP = "This option is only available for formats that display a percentage."
function mod.UFO_PowerTextCog(get, set, pctOff, setShowPct)
    local rowList = mod.UF_NameFormatRows("powerText", "perpp", get, set, {
        {
            type = "toggle",
            label = "Show %",
            disabled = function() return get("powerTextFormat", "perpp") == "custom" end,
            disabledTooltip = PCT_TIP,
            get = function() return get("powerShowPercent", true) ~= false end,
            set = setShowPct,
        },
    }, "powerTextFormat")
    return {
        title = "Power Text",
        rows = rowList,
        disabled = function()
            local fmt = get("powerTextFormat", "perpp")
            if fmt == "custom" then return not mod.UF_ContentShowsName(fmt, get("powerTextCustomFormat")) end
            return pctOff[fmt] == true
        end,
        disabledTooltip = function()
            if get("powerTextFormat", "perpp") == "custom" then
                return "This option only applies when the text shows a name."
            end
            return PCT_TIP
        end,
    }
end

-- The popup writes the format directly, so Spec Overrides needs an accessor:
-- on a Custom slot, or one holding a format an override may switch back to.
function mod.UFO_AddCustomFormatAccessor(region, labelText, prefixText, contentFrame, getDB, apply)
    local fk = prefixText .. "CustomFormat"
    if contentFrame ~= "custom" and type(getDB()[fk]) ~= "string" then return end
    CUI.TextTags.AddFormatAccessor(region, labelText, function() return getDB()[fk] end, function(val)
        getDB()[fk] = val
        apply()
    end)
end

-- Level coloring is shared by the unit, and edited from its level-text cogs.
function mod.UF_CoreTextRows(prefixText, contentDefault, get, set, rowList)
    rowList = mod.UF_NameFormatRows(prefixText, contentDefault, get, set, rowList)
    local contentFrame = get(prefixText .. "Content", contentDefault)
    local parsed = contentFrame == "custom"
        and CUI.TextTags.Parse(mod.UF_TextTags, get(prefixText .. "CustomFormat"))
    local hasLevel = contentFrame == "level"
        or contentFrame == "levelname"
        or contentFrame == "namelevel"
        or (parsed and parsed.has.level)
    if not hasLevel then return rowList end
    rowList[#rowList + 1] = {
        type = "toggle",
        label = "Level Text: Difficulty Color",
        tooltip = "Colors level text by difficulty, from grey (trivial) through green, yellow and orange to red (5+ levels above you).",
        get = function() return get("levelDifficultyColor", false) == true end,
        set = function(val)
            set("levelDifficultyColor", val)
            mod._UFO_OptEnv.UpdatePreview()
        end,
    }
    rowList[#rowList + 1] = {
        type = "toggle",
        label = "Level Text: Include Friendly",
        tooltip = "Friendly units get their level's color too, instead of gold.",
        disabled = function() return get("levelDifficultyColor", false) ~= true end,
        disabledTooltip = "Level Text: Difficulty Color",
        get = function() return get("levelDifficultyColorFriendly", false) == true end,
        set = function(val)
            set("levelDifficultyColorFriendly", val)
            mod._UFO_OptEnv.UpdatePreview()
        end,
    }
    return rowList
end

-- Keep the unit-frame settings and inline controls; only the list changes.
function mod.UFO_BuildTextSlots(W, hostFrame, cursorY, options)
    local header, headerH = W:SectionHeader(hostFrame, "CORE TEXT POSITIONS", cursorY)
    cursorY = cursorY - headerH
    hostFrame._ufTextHeader = header
    local slots, sequence, values = options.slots, {}, {}
    local byKey, cells, targets = {}, {}, {}
    local textValues = CopyTable(options.values)
    -- Remove in the house BAD red with the close X at the row's right edge: 12px,
    -- at the list delete buttons' 0.75 alpha; both brighten on hover.
    textValues.none = "Remove"
    textValues._menuOpts = {
        icon = function(key)
            if key == "none" then return "Interface\\AddOns\\CludesUI\\media\\icons\\cui-close.png" end
        end,
        iconSize = function() return 12 end,
        iconClearScroll = true,
        iconColor = function() return 1, 0.35, 0.35, 0.75 end,
        labelColor = function(key)
            if key == "none" then return 1, 0.35, 0.35, 0.8 end
        end,
    }
    local function Notify(key) mod._ufTextNotify = { unit = options.unit, key = key } end
    for idx = 1, #slots do
        local cfg = slots[idx]
        sequence[idx], values[cfg.key], byKey[cfg.key] = cfg.key, cfg.position, cfg
        if textValues.custom then
            -- Custom is an action entry: it opens the format popup, and a saved
            -- format selects it for the slot (a selection rebuilds the page).
            cfg.cfg.values = mod.UFO_CustomTextValues(textValues, cfg.cfg.getValue, function()
                mod.UFO_EditCustomText(cfg.key, options.db(), options.unit, function()
                    Notify(cfg.key)
                    cfg.cfg.setValue("custom")
                end)
            end)
        else
            cfg.cfg.values = textValues
        end
        if cfg.cfg.getValue() ~= "none" then cells[#cells + 1] = cfg end
    end
    local function Assigned(key)
        local cfg = byKey[key]
        return cfg and cfg.cfg.getValue() ~= "none"
    end
    local function Full()
        for idx = 1, #slots do
            if not Assigned(slots[idx].key) then return false end
        end
        return true
    end
    local function Candidate()
        for idx = 1, #options.contentOrder do
            local val = options.contentOrder[idx]
            if val ~= "---" and mod.UF_IsUniqueContent(val) then
                local used = false
                for jdx = 1, #slots do
                    if slots[jdx].cfg.getValue() == val then
                        used = true
                        break
                    end
                end
                if not used then return val end
            end
        end
    end
    local function Add(key)
        local val = Candidate()
        if Assigned(key) or not byKey[key] or not val then
            CUI:RefreshPage(true)
            return
        end
        Notify(key)
        byKey[key].cfg.setValue(val)
    end
    local function Move(source, dest)
        if source == dest then return end
        if not Assigned(source) or not byKey[dest] or Assigned(dest) then
            CUI:RefreshPage(true)
            return
        end
        local db = options.db()
        local contentFrame = byKey[source].cfg.getValue()
        local size = db[source .. "Size"] or db.textSize or 12
        for idx = 1, #MOVE_KEYS do
            local suffix = MOVE_KEYS[idx]
            -- The format moves only with Custom; otherwise the destination keeps its own.
            if suffix ~= "CustomFormat" or contentFrame == "custom" then
                local val = db[source .. suffix]
                if type(val) == "table" then val = CopyTable(val) end
                db[dest .. suffix] = val
            end
        end
        db[dest .. "Size"] = size
        if dest == "extraText" then
            db.extraTextAlign = source == "rightText" and "right"
                or source == "centerText" and "center"
                or "left"
        end
        db[dest .. "Content"], db[source .. "Content"] = contentFrame, "none"
        Notify(dest)
        options.apply()
        CUI:RefreshPage(true)
    end

    local addOpen
    local addCfg = {
        type = "button",
        text = "+ Add Text Slot",
        width = 220,
        onClick = function()
            if addOpen then addOpen() end
        end,
        disabled = function() return Full() or Candidate() == nil end,
        disabledTooltip = "Every text position is full.",
    }
    cells[#cells + 1] = addCfg
    local function Config(cfg)
        if not cfg then return CUI.BlankRowCfg() end
        return cfg.cfg or cfg
    end
    local firstRow
    local function Finish(row, side, cell)
        if not cell then return end
        firstRow = firstRow or row
        local region = row[side]
        if cell == addCfg then
            if not CUI._prebuilding then
                addOpen = CUI.AttachButtonMenu(region._control, {
                    width = 220,
                    order = sequence,
                    values = values,
                    setValue = Add,
                    itemDisabled = function(val) return Assigned(val) or Candidate() == nil end,
                })
            end
            return
        end
        if not cell.key then return end
        targets[cell.key] = { row = row, side = side }
        if CUI._prebuilding then return end
        CUI.BuildRowLabelMenu(region, {
            order = sequence,
            values = values,
            getValue = function() return cell.key end,
            setValue = function(val) Move(cell.key, val) end,
            itemDisabled = function(val)
                if not Assigned(cell.key) then return true end
                if val ~= cell.key and Assigned(val) then return true end
            end,
            tooltip = "Choose this text's slot position.",
        })
        cell.decorate(region)
        if cell.cfg.values and cell.cfg.values.custom then
            mod.UFO_AddCustomFormatAccessor(
                region,
                cell.position,
                cell.key,
                cell.cfg.getValue(),
                options.db,
                options.apply
            )
        end
        local pending = mod._ufTextNotify
        if pending and pending.unit == options.unit and pending.key == cell.key then
            mod._ufTextNotify = nil
            -- The slot read now, while this build's cell is its dress.
            local snap = CUI._SOAttribution(region)
            CUI._NotifySettingWrite(region, snap)
        end
    end
    for idx = 1, #cells, 2 do
        local row, height = W:DualRow(hostFrame, cursorY, Config(cells[idx]), Config(cells[idx + 1]))
        cursorY = cursorY - height
        Finish(row, "_leftRegion", cells[idx])
        Finish(row, "_rightRegion", cells[idx + 1])
    end
    hostFrame._ufTextCells = targets
    if not CUI._prebuilding then
        -- Presets/spec changes can alter the list while the page is cached.
        local saved = {}
        for idx = 1, #slots do
            saved[idx] = slots[idx].cfg.getValue()
        end
        mod._ufTextChecks = mod._ufTextChecks or {}
        mod._ufTextChecks[options.page] = function()
            local db = options.liveDB()
            for idx = 1, #slots do
                if (db[slots[idx].key .. "Content"] or slots[idx].default) ~= saved[idx] then return true end
            end
            return false
        end
    end
    return cursorY, firstRow
end

function mod.UFO_TextClickTarget(hostFrame, key, section, fallback)
    local c = hostFrame._ufTextCells and hostFrame._ufTextCells[key]
    return {
        section = c and hostFrame._ufTextHeader or section,
        target = c and c.row or fallback,
        slotSide = c and (c.side == "_leftRegion" and "left" or "right") or nil,
    }
end
