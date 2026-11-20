if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  RaidFrames_Options\CUI_RaidFrames_TextDisplay_Options.lua
--  Raid Frames options: the texts of the Text Display section. One tile per
--  shown text (ns.RF_TEXTS), labelled with its position: the row label moves
--  it (texts may share a position), the dropdown picks its mode or removes
--  it, "+ Add Text" shows a hidden one. Every text keeps its own keys.
-------------------------------------------------------------------------------
local mod = CludesUI._ModuleNS["CludesUIRaidFrames"]
if not mod then
    return
end -- module disabled: no options page

-- Dropdown entries per kind; "none" is the dropdown's Remove.
local MODE_VALUES = {
    name = { none = "Remove", name = "Name", levelname = "Level Name", levelnameDiv = "Level | Name" },
    level = { none = "Remove", level = "Level" },
    hp = {
        none = "Remove",
        percent = "Health %",
        percentNoSign = "Health % (No Sign)",
        number = "Health #",
        numberPercent = "Health # | %",
        percentNumber = "Health % | #",
        missing = "Health Missing #",
    },
    pp = {
        none = "Remove",
        percent = "Power %",
        percentNoSign = "Power % (No Sign)",
        number = "Power #",
        numberPercent = "Power # | %",
        percentNumber = "Power % | #",
    },
    ha = { none = "Remove", short = "Heal Absorb Short (80k)", amount = "Heal Absorb Amount" },
    custom = { none = "Remove" },
}
local MODE_ORDER = {
    name = { "none", "---", "name", "levelname", "levelnameDiv" },
    level = { "none", "---", "level" },
    hp = { "none", "---", "percent", "percentNoSign", "number", "numberPercent", "percentNumber", "missing" },
    pp = { "none", "---", "percent", "percentNoSign", "number", "numberPercent", "percentNumber" },
    ha = { "none", "---", "short", "amount" },
    custom = { "none", "---", "custom" },
}
-- The mode a text shown from "+ Add Text" starts with.
local FIRST_MODE = { hp = "percent", pp = "percent", ha = "short" }
-- The level in front of the name, as the name tile's dropdown names it.
local ATTACH_VALUE = { name = "levelname", nameDiv = "levelnameDiv" }

-- Power Colored: Power Text and Custom (whose tags may read power) only.
local function AllowsPower(tbl)
    return tbl.kind == "pp" or tbl.kind == "custom"
end

-------------------------------------------------------------------------------
--  Custom text: the template popup over the module's catalog (ns.RF_TextTags)
--  and the dropdown copy whose Custom entry opens it.
-------------------------------------------------------------------------------
local CustomText = {}
do
    -- The text's colour mode as the preview shows it, for the player's class and power.
    function CustomText.Color(tbl)
        local SVal = mod._RFO_OptEnv.SVal
        local _, classTok = UnitClass("player")
        local _, pTok = UnitPowerType("player")
        local red, green, blue = mod.RF_PreviewTextColor(SVal(tbl.cm, "custom"), SVal(tbl.col), classTok, 1, 1, 1, pTok)
        return { r = red, g = green, b = blue }
    end

    -- key: the format key (party-aware through the page's SVal/SWrite); onSave
    -- runs after the format is stored.
    function CustomText.Edit(key, color, onSave)
        local environ = mod._RFO_OptEnv
        CludesUI.TextTags.EditPopup({
            cat = mod.RF_TextTags,
            color = color,
            onSave = onSave,
            tagNotes = { hp = CludesUI.L("shows DEAD or OFFLINE") },
            get = function()
                return environ.SVal(key)
            end,
            set = function(txt)
                environ.SWrite(key, txt)
            end,
        })
    end

    -- A copy of a mode list whose Custom entry is an action that opens the popup,
    -- beside Remove in the house red.
    function CustomText.Values(values, edit)
        return CludesUI.TextTags.MenuValues(values, edit, { removeKey = "none" })
    end

    -- The popup writes the format directly, so Spec Overrides needs an accessor.
    function CustomText.AddAccessor(region, labelText, key)
        local environ = mod._RFO_OptEnv
        CludesUI.TextTags.AddFormatAccessor(region, labelText, function()
            return environ.SVal(key)
        end, function(val)
            environ.SSet(key, val)
        end)
    end
end

-------------------------------------------------------------------------------
--  The text list
-------------------------------------------------------------------------------
-- Builds the tiles at y under the Text Display header. opts.page: the page
-- being built (cache check); opts.party: the Party tab (its textDisplay keys).
-- Returns y and the first row.
function mod.RFO_BuildTextDisplay(W, hostFrame, cursorY, options)
    -- The text files did not load: no text section, the page still builds.
    if not (mod.RF_TEXTS and mod.RF_TEXT_POSITIONS and mod.RF_TextShown and mod.RF_TEXT_SIG_KEYS) then
        return cursorY
    end
    local environ = mod._RFO_OptEnv
    local SVal, SWrite, ReloadAndUpdate = environ.SVal, environ.SWrite, environ.ReloadAndUpdate
    local TEXTS, POSITIONS, POS_INDEX = mod.RF_TEXTS, mod.RF_TEXT_POSITIONS, mod.RF_TEXT_POS_INDEX
    local POS = CludesUI.POSITION_GRID_VALUES
    local LEVEL_DEFAULT = mod.RF_LEVEL_DEFAULT

    local function PosOf(tbl)
        if tbl.kind == "level" then
            return SVal(tbl.pos, LEVEL_DEFAULT)
        end
        return SVal(tbl.pos, "center")
    end
    -- Shown by the engine's own rule, read through the page's (party-aware) SVal.
    local view = setmetatable({}, {
        __index = function(_, keyName)
            return SVal(keyName)
        end,
    })
    local function Shown(t)
        return mod.RF_TextShown(t, view, SVal("levelTextPosition", LEVEL_DEFAULT)) ~= nil
    end
    -- The value the tile's dropdown shows.
    local function ModeOf(tbl)
        if tbl.kind == "name" then
            return ATTACH_VALUE[SVal("levelTextPosition", LEVEL_DEFAULT)] or "name"
        end
        if tbl.mode then
            return SVal(tbl.mode, "none")
        end
        return tbl.kind
    end
    -- The first position no shown text uses, else pref.
    local function FreePos(pref)
        local used = {}
        for idx = 1, #TEXTS do
            if Shown(TEXTS[idx]) then
                used[PosOf(TEXTS[idx])] = true
            end
        end
        if not used[pref] then
            return pref
        end
        for idx = 1, #POSITIONS do
            if not used[POSITIONS[idx]] then
                return POSITIONS[idx]
            end
        end
        return pref
    end
    local function Notify(tbl)
        mod._rfTextNotify = { page = options.page, key = tbl.id }
    end
    local function ApplyTextDisplay()
        ReloadAndUpdate()
        CludesUI:RefreshPage(true)
    end

    -- A dropdown pick: a mode, the level format in front of the name, or Remove.
    local function SetMode(tbl, val)
        if tbl.kind == "name" then
            if val == "none" then
                SWrite(tbl.pos, "none")
            else
                local lp = SVal("levelTextPosition", LEVEL_DEFAULT)
                if val == "levelname" then
                    SWrite("levelTextPosition", "name")
                elseif val == "levelnameDiv" then
                    SWrite("levelTextPosition", "nameDiv")
                elseif ATTACH_VALUE[lp] then
                    SWrite("levelTextPosition", "none")
                end
            end
        elseif tbl.kind == "level" or tbl.kind == "custom" then
            if val == "none" then
                SWrite(tbl.pos, "none")
            end
        elseif val ~= SVal(tbl.mode, "none") then
            SWrite(tbl.mode, val)
        end
        ApplyTextDisplay()
    end
    local function Move(tbl, place)
        if place == PosOf(tbl) then
            return
        end
        SWrite(tbl.pos, place)
        Notify(tbl)
        ApplyTextDisplay()
    end
    -- "+ Add Text": a hidden text comes back with its own stored settings; a
    -- Custom text asks for its template first.
    local function Show(tbl)
        if tbl.kind == "custom" then
            CustomText.Edit(tbl.fmt, CustomText.Color(tbl), function()
                SWrite(tbl.pos, FreePos("center"))
                Notify(tbl)
                ApplyTextDisplay()
            end)
            return
        end
        if tbl.kind == "name" then
            SWrite(tbl.pos, FreePos("topleft"))
        elseif tbl.kind == "level" then
            SWrite(tbl.pos, FreePos("topright"))
        else
            -- The second Health Text has no upstream spot of its own: a free one
            -- (looked up while it is still hidden).
            if tbl.id == "hp2" then
                SWrite(tbl.pos, FreePos(SVal(tbl.pos, "bottom")))
            end
            SWrite(tbl.mode, FIRST_MODE[tbl.kind])
        end
        Notify(tbl)
        ApplyTextDisplay()
    end

    -- The cog (nearest the dropdown), the swatches left of it (Custom first,
    -- then Class, Accent, Power) and the colour mode accessor of one shown
    -- text. The level is drawn in the name's colour: no swatches of its own.
    local function Decorate(region, cell)
        local tbl = cell.text
        local rowList = {
            {
                type = "slider",
                label = "Size",
                min = 6,
                max = 26,
                step = 1,
                get = function()
                    return SVal(tbl.size, 10)
                end,
                set = function(val)
                    environ.SSet(tbl.size, val)
                end,
            },
            {
                type = "slider",
                label = "X Offset",
                min = -500,
                max = 500,
                step = 1,
                get = function()
                    return SVal(tbl.x, 0)
                end,
                set = function(val)
                    environ.SSet(tbl.x, val)
                end,
            },
            {
                type = "slider",
                label = "Y Offset",
                min = -500,
                max = 500,
                step = 1,
                get = function()
                    return SVal(tbl.y, 0)
                end,
                set = function(val)
                    environ.SSet(tbl.y, val)
                end,
            },
        }
        -- The name length is shared by every name text of the view (Name Format
        -- has its own row: it shapes the Top Name Bar too).
        local showsName = tbl.kind == "name"
        if tbl.kind == "custom" then
            local parsed = CludesUI.TextTags.Parse(mod.RF_TextTags, SVal(tbl.fmt))
            showsName = parsed and parsed.has and parsed.has.name and true or false
        end
        if showsName then
            rowList[#rowList + 1] = {
                type = "slider",
                label = "Max Characters (0=off)",
                min = 0,
                max = 30,
                step = 1,
                get = function()
                    return SVal("nameMaxLength", 15)
                end,
                set = function(val)
                    environ.SSet("nameMaxLength", val)
                end,
            }
        end
        -- Show Above Icons: the name's own key; every other text follows it until set here.
        if tbl.kind == "name" then
            rowList[#rowList + 1] = {
                type = "toggle",
                label = "Show Above Icons",
                tooltip = "Render the name above buff and debuff icons. Texts without a setting of their own follow it.",
                get = function()
                    return SVal(tbl.above, false) and true or false
                end,
                set = function(val)
                    environ.SSet(tbl.above, val)
                end,
            }
        else
            rowList[#rowList + 1] = {
                type = "toggle",
                label = "Show Above Icons",
                tooltip = "Render this text above buff and debuff icons. Follows the name's setting until changed here.",
                get = function()
                    local val = SVal(tbl.above)
                    if val == nil then
                        val = SVal("nameTextAboveIcons", false)
                    end
                    return val and true or false
                end,
                set = function(val)
                    environ.SSet(tbl.above, val)
                end,
            }
        end
        CludesUI.BuildInlineCog(region, {
            title = CludesUI.Lf("%1$s Settings", CludesUI.L(tbl.label)),
            rows = rowList,
        })
        if tbl.kind ~= "level" then
            local modeKey = tbl.cm
            local function AddColorSwatch(getColor, setColor, mode, opensPicker, tooltip)
                local sw = CludesUI.BuildColorSwatch(
                    region,
                    region:GetFrameLevel() + 5,
                    getColor,
                    setColor,
                    false,
                    20
                )
                environ.PP.Point(sw, "RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
                region._lastInline = sw
                sw._eabOrigClick = sw:GetScript("OnClick")
                sw:SetScript("OnClick", function(self)
                    if SVal(modeKey, "custom") ~= mode then
                        -- Attribution read before the write: the rebuild dresses the swatch again.
                        local snap = CludesUI._SOAttribution(self)
                        environ.SSet(modeKey, mode)
                        CludesUI._NotifySettingWrite(self, snap)
                        CludesUI:RefreshPage()
                        return
                    end
                    if opensPicker and self._eabOrigClick then
                        self._eabOrigClick(self)
                    end
                end)
                sw:HookScript("OnEnter", function()
                    CludesUI.ShowWidgetTooltip(sw, tooltip)
                end)
                sw:HookScript("OnLeave", function()
                    CludesUI.HideWidgetTooltip()
                end)
                local function vis()
                    sw:SetAlpha(SVal(modeKey, "custom") == mode and 1 or 0.3)
                end
                CludesUI.RegisterWidgetRefresh(vis)
                vis()
            end
            AddColorSwatch(function()
                local color = SVal(tbl.col)
                if color then
                    return color.r or 1, color.g or 1, color.b or 1, 1
                end
                return 1, 1, 1, 1
            end, function(red, green, blue)
                SWrite(tbl.col, { r = red, g = green, b = blue })
                ReloadAndUpdate()
            end, "custom", true, "Custom Color")
            AddColorSwatch(function()
                local _, classTok = UnitClass("player")
                local classColor = classTok and CludesUI.GetClassColor(classTok)
                if classColor then
                    return classColor.r, classColor.g, classColor.b, 1
                end
                return 1, 1, 1, 1
            end, function() end, "class", false, "Class Color")
            AddColorSwatch(function()
                local red, green, blue = CludesUI.ResolveActiveAccent()
                return red or 1, green or 1, blue or 1, 1
            end, function() end, "accent", false, "Accent Color")
            if AllowsPower(tbl) then
                AddColorSwatch(function()
                    local _, pToken = UnitPowerType("player")
                    local details = CludesUI.GetPowerColor(pToken or "MANA")
                    if details then
                        return details.r, details.g, details.b, 1
                    end
                    return 0, 0.5, 1, 1
                end, function() end, "power", false, "Power Colored Text")
            end
            -- The mode is written only by the swatch clicks above.
            local modeValues = { custom = "Custom Color", class = "Class Color", accent = "Accent Color" }
            local modeOrder = { "custom", "class", "accent" }
            if AllowsPower(tbl) then
                modeValues.power = "Power Colored Text"
                modeOrder[4] = "power"
            end
            CludesUI.AddCaptureAccessor(region, {
                type = "dropdown",
                text = tbl.label .. " Color Mode",
                values = modeValues,
                order = modeOrder,
                getValue = function()
                    return SVal(modeKey, "custom")
                end,
                setValue = function(val)
                    environ.SSet(modeKey, val)
                end,
            })
        end
    end

    -- Shown texts in grid order (a shared position: in text order).
    local isShown = {}
    for idx = 1, #TEXTS do
        local t = TEXTS[idx]
        if Shown(t) then
            isShown[#isShown + 1] = { text = t, i = idx, pos = PosOf(t) }
        end
    end
    table.sort(isShown, function(lhs, rhs)
        local pa, pb = POS_INDEX[lhs.pos] or 99, POS_INDEX[rhs.pos] or 99
        if pa ~= pb then
            return pa < pb
        end
        return lhs.i < rhs.i
    end)

    local kit = mod.RF_OptPartyKit()
    local cells = {}
    for jdx = 1, #isShown do
        local cell = isShown[jdx]
        local tbl = cell.text
        local rowConf = {
            type = "dropdown",
            text = POS[cell.pos] or cell.pos,
            order = MODE_ORDER[tbl.kind],
            getValue = function()
                return ModeOf(tbl)
            end,
            setValue = function(val)
                SetMode(tbl, val)
            end,
        }
        if tbl.kind == "pp" then
            rowConf.tooltip = "Shows only on frames whose power bar shows."
        elseif tbl.kind == "name" and kit then
            rowConf.tooltip =
                "On Party Frames style the name keeps the frame's own spot; its offsets still apply."
        elseif tbl.kind == "level" then
            rowConf.tooltip = "Drawn in the name's colour."
        end
        rowConf.values = CustomText.Values(MODE_VALUES[tbl.kind], tbl.kind == "custom" and function()
            CustomText.Edit(tbl.fmt, CustomText.Color(tbl), function()
                Notify(tbl)
                ApplyTextDisplay()
            end)
        end or nil)
        cell.cfg = rowConf
        cells[#cells + 1] = cell
    end

    -- "+ Add Text": every hidden text; the Custom texts as one entry (the next free
    -- one) on top, an action in the accent colour with the edit pencil, as in the
    -- tile dropdowns.
    local addOrder, addValues, addText = {}, {}, {}
    local customId
    local nameShown = Shown(TEXTS[1])
    for idx = 1, #TEXTS do
        local tbl = TEXTS[idx]
        local hidden = not Shown(tbl)
        -- An attached level shows in the name tile while the name does; with the
        -- name hidden (the Top Name Bar may still use it) it can go on its own spot.
        if tbl.kind == "level" and ATTACH_VALUE[PosOf(tbl)] and nameShown then
            hidden = false
        end
        if hidden and tbl.kind == "custom" then
            if not customId then
                customId = tbl.id
                addValues[tbl.id] = {
                    text = "Custom Text",
                    action = function()
                        Show(tbl)
                    end,
                }
            end
        elseif hidden then
            addOrder[#addOrder + 1] = tbl.id
            addValues[tbl.id] = tbl.label
            -- An attached level placed on its own spot leaves the Top Name Bar's prefix.
            if tbl.kind == "level" and ATTACH_VALUE[PosOf(tbl)] and SVal("topNameBarEnabled", false) then
                addValues[tbl.id] = "Level (moves it off the Top Name Bar)"
            end
            addText[tbl.id] = tbl
        end
    end
    if customId then
        table.insert(addOrder, 1, customId)
        if #addOrder > 1 then
            table.insert(addOrder, 2, "---")
        end
        addValues._menuOpts = {
            icon = function(key)
                if key == customId then
                    return CludesUI.TextTags.EDIT_ICON
                end
            end,
            iconSize = function()
                return 12
            end,
            iconClearScroll = true,
            iconColor = function(key)
                if key == customId then
                    return 1, 1, 1, 1
                end
            end,
        }
    end
    local addOpen
    local addCfg = {
        type = "button",
        text = "+ Add Text",
        width = 220,
        onClick = function()
            if addOpen then
                addOpen()
            end
        end,
        disabled = function()
            return #addOrder == 0
        end,
        disabledTooltip = "Every text is shown.",
    }
    cells[#cells + 1] = addCfg

    local function Config(cfg)
        if not cfg then
            return CludesUI.BlankRowCfg()
        end
        return cfg.cfg or cfg
    end
    local firstRow
    local function Finish(row, side, cell)
        if not cell then
            return
        end
        firstRow = firstRow or row
        local region = row[side]
        if cell == addCfg then
            if not CludesUI._prebuilding then
                addOpen = CludesUI.AttachButtonMenu(region._control, {
                    width = 220,
                    order = addOrder,
                    values = addValues,
                    setValue = function(ident)
                        if addText[ident] then
                            Show(addText[ident])
                        end
                    end,
                })
            end
            return
        end
        if CludesUI._prebuilding then
            return
        end
        local tbl = cell.text
        -- Spec Overrides name a captured write after the text, not its position
        -- (several texts may share one).
        if region._captureCfg then
            region._captureCfg = setmetatable({ text = tbl.label }, { __index = region._captureCfg })
        end
        CludesUI.BuildRowLabelMenu(region, {
            order = POSITIONS,
            values = POS,
            getValue = function()
                return PosOf(tbl)
            end,
            setValue = function(val)
                Move(tbl, val)
            end,
            tooltip = "Choose this text's position.",
        })
        Decorate(region, cell)
        if tbl.kind == "custom" then
            CustomText.AddAccessor(region, tbl.label, tbl.fmt)
        end
        local pending = mod._rfTextNotify
        if pending and pending.page == options.page and pending.key == tbl.id then
            mod._rfTextNotify = nil
            -- The text read now, while this build's cell is its dress.
            local snap = CludesUI._SOAttribution(region)
            CludesUI._NotifySettingWrite(region, snap)
        end
    end
    for idx = 1, #cells, 2 do
        local row, height = W:DualRow(hostFrame, cursorY, Config(cells[idx]), Config(cells[idx + 1]))
        cursorY = cursorY - height
        Finish(row, "_leftRegion", cells[idx])
        Finish(row, "_rightRegion", cells[idx + 1])
    end

    if not CludesUI._prebuilding and options.page then
        -- Presets, spec changes and profile switches can alter the list while
        -- the page is cached: what decides the tiles as built, against the stored.
        -- A Custom text's template counts too (its cog's name row follows it).
        local SIG_KEYS = mod.RF_TEXT_SIG_KEYS
        local function Sig(get)
            local parts = {}
            for idx = 1, #SIG_KEYS do
                parts[idx] = tostring(get(SIG_KEYS[idx]))
            end
            return table.concat(parts, "\31")
        end
        local saved = Sig(SVal)
        local party = options.party
        mod._rfTextChecks = mod._rfTextChecks or {}
        mod._rfTextChecks[options.page] = function()
            local popFrame = mod.db and mod.db.profile
            if not popFrame then
                return false
            end
            local own = party and mod._IsPartySectionCustom and mod._IsPartySectionCustom("textDisplay")
            return Sig(function(keyName)
                local val
                if own then
                    val = popFrame["party_" .. keyName]
                end
                if val == nil then
                    val = popFrame[keyName]
                end
                return val
            end) ~= saved
        end
    end
    return cursorY, firstRow
end
