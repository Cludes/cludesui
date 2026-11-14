if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_UnitFrames_Options.lua
--  Registers the Unit Frames module with CludesUI
--  4 tabs: Main Frames, Boss Frames, Mini Frames, Player Aura Bars
-------------------------------------------------------------------------------
local ADDON_NAME = "CludesUIUnitFrames"
local mod = CludesUI._ModuleNS[ADDON_NAME] -- module namespace (published by the module at its load)
if not mod then
    return
end -- module disabled: no options page

-- Page reuse: the frames this file builds under a kept page, header or row go
-- through the options frame pool (CludesUI_FramePool.lua), which hands the
-- next build the previous build's frames reset to new; on any other parent it
-- is the plain CreateFrame.
local CreateFrame = CludesUI._Pool.CreateFrame
-- The pool's other calls this file makes, read once here as CreateFrame is:
-- the page path never calls the pool through its public slot, which
-- another addon could replace.
local PoolGen, PoolIsIdle, PoolKeep = CludesUI._Pool.Gen, CludesUI._Pool.IsIdle, CludesUI._Pool.Keep

local PAGE_DISPLAY = "Main Frames"
local PAGE_BOSS = "Boss Frames"
local PAGE_MINI = "Mini Frames"
local PAGE_AURA_BARS = "Player Aura Bars"
local PAGE_UNLOCK = "Layout Mode"

-- Threat % Position dropdown (WoW Forever only, so nil on retail). On ns: the
-- Main Frames page builder is near its 60-upvalue cap, and the Forever
-- Essentials Threat page reads the same lists. Outside = beside the whole
-- frame, clear of an attached portrait.
if CludesUI.IS_FOREVER then
    mod._threatPctPositions = {
        RIGHT = "Inside Right",
        LEFT = "Inside Left",
        CENTER = "Inside Center",
        OUTRIGHT = "Outside Right",
        OUTLEFT = "Outside Left",
    }
    mod._threatPctPositionOrder = { "RIGHT", "LEFT", "CENTER", "OUTRIGHT", "OUTLEFT" }
end

-- Settings-cog rows of a text slot that can show a name: its Name Format.
-- prefix is the slot's key prefix ("leftText", "btbLeft"): content at
-- <prefix>Content, format at <prefix>NameFormat. get(key, default) /
-- set(key, v) are the page's accessors. On ns for the same upvalue cap.
do
    local HAS_NAME =
        { name = true, levelname = true, namelevel = true, nametotarget = true, targetname = true }
    -- A custom format shows a name when its parse holds a name tag.
    function mod.UF_ContentShowsName(contentFrame, customFmt)
        if contentFrame ~= "custom" then
            return HAS_NAME[contentFrame] or false
        end
        local parsed = CludesUI.TextTags.Parse(mod.UF_TextTags, customFmt)
        return parsed ~= nil and (parsed.has.name or parsed.has.target) == true
    end
    -- contentKey: the slot's content key when it is not <prefix>Content
    -- (the power text's powerTextFormat). A unit frame text can show an enemy's
    -- name (target, focus, boss, a Name > Target text).
    local ENEMIES = { enemies = true }
    function mod.UF_NameFormatRows(prefixText, contentDefault, get, set, rowList, contentKey)
        local formatKey = prefixText .. "NameFormat"
        contentKey = contentKey or (prefixText .. "Content")
        local row = CludesUI.NameFormatCogRow(function()
            return get(formatKey)
        end, function(v)
            set(formatKey, v)
        end, ENEMIES)
        row.disabled = function()
            return not mod.UF_ContentShowsName(
                get(contentKey, contentDefault),
                get(prefixText .. "CustomFormat")
            )
        end
        row.disabledTooltip = "This option only applies when the text shows a name."
        table.insert(rowList, 1, row)
        return rowList
    end
end

-- The same slots for the Forever Essentials NAME FORMAT section, a page that
-- exists on WoW Forever only.
if CludesUI.IS_FOREVER then
    local MAIN = { "leftText", "rightText", "centerText", "extraText", "btbLeft", "btbRight", "btbCenter" }
    local BOSS = { "leftText", "rightText", "centerText", "extraText" }
    local MINI = { "leftText", "rightText", "centerText" }
    local slots = {}
    for _, set in ipairs({
        { "player", MAIN },
        { "target", MAIN },
        { "focus", MAIN },
        { "boss", BOSS },
        { "targettarget", MINI },
        { "focustarget", MINI },
        { "pet", MINI },
    }) do
        for _, pre in ipairs(set[2]) do
            slots[#slots + 1] = {
                unit = set[1],
                content = pre .. "Content",
                custom = pre .. "CustomFormat",
                format = pre .. "NameFormat",
                btb = pre:sub(1, 3) == "btb",
            }
        end
    end
    -- The power text: a name only through a custom format, shown while
    -- its Text Position is not None (power = that position key).
    for _, unitToken in ipairs({ "player", "target", "focus", "boss", "pet" }) do
        slots[#slots + 1] = {
            unit = unitToken,
            content = "powerTextFormat",
            custom = "powerTextCustomFormat",
            format = "powerTextNameFormat",
            power = "powerPercentText",
        }
    end
    mod.UF_NAME_FORMAT_SLOTS = slots
end

-- Classic WoW UI: a cast bar section's closing Border Size row (the odd last
-- slot), sizing the vanilla frame round the bar. getS() returns the unit's
-- settings table and `key` its frame-size key (ns.UF_CastClassicKey);
-- onChange repaints. `matchKey` names the cast bar's unlock element (nil on
-- the boss page, which has none): its size matches read the frame's reach
-- and are re-applied when it changes. `sync` (main frames page only) adds
-- the apply-to-all icon: { units, labels, current(), db(unit), reload }; a
-- unit's element is "<unit>Castbar". `right` (optional) fills the free right
-- slot. Returns the row height, 0 (nothing built) off the style, and the row.
-- On ns: the page builders sit at the local cap.
function mod.UF_ClassicCastBorderRow(W, hostFrame, posY, getS, key, onChange, sync, matchKey, right)
    local BS = CludesUI.BlizzStyle
    if not (BS and BS.Active("unitframes") == "classic") then
        return 0
    end
    local row, hgt = W:DualRow(
        hostFrame,
        posY,
        BS.ClassicBorderSizeCfg(function()
            local s = getS()
            return s and s[key]
        end, function(v)
            local s = getS()
            if not s then
                return
            end
            s[key] = v
            onChange()
            if matchKey and CludesUI.ReapplyMatchPads then
                CludesUI.ReapplyMatchPads(matchKey)
            end
        end),
        right or CludesUI.BlankRowCfg()
    )
    if sync and not CludesUI._prebuilding then
        local rgn = row._leftRegion
        local function apply(units)
            local s = getS()
            local v = s and s[key]
            for idx = 1, #units do
                local t = sync.db(units[idx])
                if t then
                    t[mod.UF_CastClassicKey(units[idx])] = v
                end
            end
            sync.reload()
            for idx = 1, #units do
                CludesUI.ReapplyMatchPads(units[idx] .. "Castbar")
            end
            CludesUI:RefreshPage()
        end
        CludesUI.BuildSyncIcon({
            region = rgn,
            tooltip = "Apply Border Size to all Frames",
            onClick = function()
                apply(sync.units)
            end,
            isSynced = function()
                local s = getS()
                local v = s and s[key]
                for idx = 1, #sync.units do
                    local t = sync.db(sync.units[idx])
                    if t and t[mod.UF_CastClassicKey(sync.units[idx])] ~= v then
                        return false
                    end
                end
                return true
            end,
            flashTargets = function()
                return { rgn }
            end,
            multiApply = {
                elementKeys = sync.units,
                elementLabels = sync.labels,
                getCurrentKey = sync.current,
                onApply = apply,
            },
        })
    end
    return hgt, row
end

-- The 3D portrait performance warning, shown until confirmed once (account-
-- wide). Returns true when it asked (onConfirm runs on Enable, Cancel refreshes
-- the page), false when it was already dismissed and the caller applies the
-- pick itself. On ns: the page builders sit at their upvalue caps.
function mod.UF_Ask3DPortraits(onConfirm)
    if CludesUIDB and CludesUIDB.dismissed3DWarning then
        return false
    end
    CludesUI:ShowConfirmPopup({
        title = "3D Portraits",
        message = "3D portraits may cause a slight loss in performance efficiency. Do you want to enable them?",
        confirmText = "Enable",
        cancelText = "Cancel",
        onConfirm = function()
            if not CludesUIDB then
                CludesUIDB = {}
            end
            CludesUIDB.dismissed3DWarning = true
            onConfirm()
        end,
        onCancel = function()
            CludesUI:RefreshPage()
        end,
    })
    return true
end

-- Separate acknowledgement: enabling 3D does not opt into 2D model lookups.
-- onCancel (optional) replaces the plain page refresh on Cancel.
function mod.UF_Ask2DMirroredPortraits(onConfirm, onCancel)
    if CludesUIDB and CludesUIDB.dismissed2DMirrorWarning then
        return false
    end
    CludesUI:ShowConfirmPopup({
        title = "2D Mirrored Portraits",
        message = "2D mirrored portraits may cause a slight loss in performance efficiency. Do you want to enable them?",
        confirmText = "Enable",
        cancelText = "Cancel",
        onConfirm = function()
            if not CludesUIDB then
                CludesUIDB = {}
            end
            CludesUIDB.dismissed2DMirrorWarning = true
            onConfirm()
        end,
        onCancel = onCancel or function()
            CludesUI:RefreshPage()
        end,
    })
    return true
end

-- Frames already set to Mirror Portrait in 2D mode get the same warning once,
-- the first time Unit Frames options open in a session: Enable keeps them,
-- Cancel turns Mirror Portrait off on those frames. Class mode is not asked:
-- there Mirror Portrait also flips the class art, which costs nothing.
do
    local asked
    local UNITS = { "player", "target", "focus", "targettarget", "focustarget", "pet", "boss" }
    function mod.UF_AskExisting2DMirror()
        if asked or CludesUI._prebuilding then
            return
        end
        asked = true
        if (CludesUIDB and CludesUIDB.dismissed2DMirrorWarning) or mod.UF_Blizz() then
            return
        end
        local prof = mod.db and mod.db.profile
        if not prof then
            return
        end
        local enabled
        for _, k in ipairs(UNITS) do
            local s = prof[k]
            if
                type(s) == "table"
                and s.portraitMirror
                and (s.portraitMode or prof.portraitMode or "2d") == "2d"
                and (s.portraitStyle or prof.portraitStyle) ~= "none"
            then
                enabled = enabled or {}
                enabled[#enabled + 1] = k
            end
        end
        if not enabled then
            return
        end
        mod.UF_Ask2DMirroredPortraits(function() end, function()
            for _, k in ipairs(enabled) do
                prof[k].portraitMirror = false
                mod.UF_RefreshPortraitMirror(k)
            end
            CludesUI:RefreshPage()
        end)
    end
end

-- Dragon Strata dropdown (the PORTRAIT section's dragon cog): Match Frame
-- keeps the frame's own strata, then the base stratas.
do
    local values, sequence = { inherit = "Match Frame" }, { "inherit" }
    for _, k in ipairs(CludesUI.FRAME_STRATA_ORDER_BASE) do
        values[k] = CludesUI.FRAME_STRATA_LABELS[k]
        sequence[#sequence + 1] = k
    end
    mod._ufDragonStrataValues, mod._ufDragonStrataOrder = values, sequence
end

-- Custom Border Style rows of a cast bar section, built only while the Cast
-- Bar cog's "Custom Border Style" opt-in is on: Border Style (+ a DIRECTIONS
-- cog for textured styles: Shift X, Shift Y, Show Behind) | Border Size (+ a
-- colour swatch), then Width Offset | Height Offset while the style is
-- textured. Every slot is BlizzStyle.Gate'd, so a stock style drops the rows
-- and the Classic-only Border Size row stays the section's odd last slot.
-- getS() returns the unit's settings table; onChange repaints; matchKey names
-- the cast bar's unlock element (nil on the boss page, which has none): its
-- size matches read the border's reach and re-apply on a change. sync (main
-- frames page only) adds the two apply-to-all links: { units, labels,
-- current(), db(unit) }. Returns the height built. On ns: the page builders
-- sit at their upvalue caps.
function mod.UF_CastBorderRows(W, hostFrame, posY, getS, onChange, matchKey, sync)
    local BS = CludesUI.BlizzStyle
    local y0 = posY
    local function Changed()
        onChange()
        if matchKey then
            CludesUI.ReapplyMatchPads(matchKey)
        end
    end
    local texValues, texOrder = CludesUI.GetBorderTextureDropdown()
    local row, hgt = W:DualRow(
        hostFrame,
        posY,
        BS.Gate("unitframes", {
            type = "dropdown",
            text = "Border Style",
            tooltip = "Border art drawn around the cast bar.",
            values = texValues,
            order = texOrder,
            getValue = function()
                return getS().castBorderStyle or "solid"
            end,
            setValue = function(v)
                local s = getS()
                s.castBorderStyle = v
                s.castBorderOffsetX, s.castBorderOffsetY = nil, nil
                s.castBorderShiftX, s.castBorderShiftY = nil, nil
                local col, behind = CludesUI.GetBorderStyleSelectDefaults(v)
                s.castBorderColor, s.castBorderAlpha, s.castBorderBehind = col, 1, behind
                local defSz = CludesUI.GetBorderDefaultSize("unitframes", v)
                if defSz then
                    s.castBorderSize = defSz
                end
                -- A style pick returns the bar to its legacy step; clear a set
                -- exact size (false travels through mirror sync, nil would not).
                if s.castBorderSizePx then
                    s.castBorderSizePx = false
                end
                Changed()
                -- The Width / Height Offset row exists only under a textured style.
                CludesUI:RefreshPage(true)
            end,
        }),
        BS.Gate(
            "unitframes",
            CludesUI.BorderPxSliderCfg({
                text = "Border Size",
                trackWidth = 120,
                getStep = function()
                    return getS().castBorderSize or 1
                end,
                setStep = function(step)
                    getS().castBorderSize = step
                end,
                getTex = function()
                    return getS().castBorderStyle or "solid"
                end,
                getPx = function()
                    return getS().castBorderSizePx
                end,
                setPx = function(v)
                    getS().castBorderSizePx = v
                end,
                -- The refresh dims the colour swatch at 0.
                apply = function()
                    Changed()
                    CludesUI:RefreshPage()
                end,
            })
        )
    )
    posY = posY - hgt
    -- Width Offset | Height Offset: a textured style's outward offsets.
    do
        local texture = getS().castBorderStyle or "solid"
        if texture ~= "solid" and texture ~= "" then
            local ocfgL, ocfgR = CludesUI.BorderOffsetRowCfgs({
                addonKey = "unitframes",
                getTex = function()
                    return getS().castBorderStyle or "solid"
                end,
                getStep = function()
                    return getS().castBorderSize or 1
                end,
                getSizeKey = function()
                    return getS().castBorderSize or 1
                end,
                getPx = function()
                    return getS().castBorderSizePx
                end,
                getX = function()
                    return getS().castBorderOffsetX
                end,
                setX = function(v)
                    getS().castBorderOffsetX = v
                end,
                getY = function()
                    return getS().castBorderOffsetY
                end,
                setY = function(v)
                    getS().castBorderOffsetY = v
                end,
                apply = Changed,
            })
            local _, oh =
                W:DualRow(hostFrame, posY, BS.Gate("unitframes", ocfgL), BS.Gate("unitframes", ocfgR))
            posY = posY - oh
        end
    end
    if CludesUI._prebuilding then
        return y0 - posY
    end

    -- Border Options cog (left): shifts and layering, textured styles only.
    do
        -- A stored shift, else the registry default for the style and size.
        local function Shift(key, isY)
            local s = getS()
            if s[key] then
                return s[key]
            end
            local _, _, dsx, dsy =
                CludesUI.GetBorderDefaults("unitframes", s.castBorderStyle or "solid", s.castBorderSize or 1)
            if isY then
                return dsy
            end
            return dsx
        end
        -- The shown default stores nil, any other value (0 included) is kept.
        local function SetShift(key, isY, v)
            local s = getS()
            s[key] = nil
            if v ~= Shift(key, isY) then
                s[key] = v
            end
            Changed()
        end
        local cogBtn = CludesUI.BuildInlineCog(row._leftRegion, {
            title = "Border Options",
            rows = {
                {
                    type = "slider",
                    label = "Shift X",
                    min = -10,
                    max = 10,
                    step = 1,
                    get = function()
                        return Shift("castBorderShiftX", false)
                    end,
                    set = function(v)
                        SetShift("castBorderShiftX", false, v)
                    end,
                },
                {
                    type = "slider",
                    label = "Shift Y",
                    min = -10,
                    max = 10,
                    step = 1,
                    get = function()
                        return Shift("castBorderShiftY", true)
                    end,
                    set = function(v)
                        SetShift("castBorderShiftY", true, v)
                    end,
                },
                {
                    type = "toggle",
                    label = "Show Behind",
                    tooltip = "Draws the border behind the cast bar instead of over it.",
                    get = function()
                        return getS().castBorderBehind == true
                    end,
                    set = function(v)
                        getS().castBorderBehind = v
                        Changed()
                    end,
                },
            },
        })
        local function UpdateCogVis()
            local texture = getS().castBorderStyle or "solid"
            if texture == "solid" or texture == "" or BS.Get("unitframes") then
                cogBtn:Hide()
            else
                cogBtn:Show()
            end
        end
        CludesUI.RegisterWidgetRefresh(UpdateCogVis)
        UpdateCogVis()
    end

    -- Colour swatch (with alpha) on Border Size; greyed and blocked at 0.
    do
        local rgn = row._rightRegion
        local sw, updateSw = CludesUI.BuildColorSwatch(rgn, row:GetFrameLevel() + 3, function()
            local s = getS()
            local c = s.castBorderColor
            return c and c.r or 0, c and c.g or 0, c and c.b or 0, s.castBorderAlpha or 1
        end, function(r, g, b, a)
            local s = getS()
            s.castBorderColor = { r = r, g = g, b = b }
            s.castBorderAlpha = a
            onChange()
        end, true, 20)
        CludesUI.PanelPP.Point(sw, "RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
        sw:SetScript("OnEnter", function()
            CludesUI.ShowWidgetTooltip(sw, "Border")
        end)
        sw:SetScript("OnLeave", function()
            CludesUI.HideWidgetTooltip()
        end)
        rgn._lastInline = sw
        local block = CreateFrame("Frame", nil, sw)
        block:SetAllPoints()
        block:SetFrameLevel(sw:GetFrameLevel() + 10)
        block:EnableMouse(true)
        block:SetScript("OnEnter", function()
            CludesUI.ShowWidgetTooltip(
                sw,
                CludesUI.DisabledTooltip("This option requires a Border Size above 0.")
            )
        end)
        block:SetScript("OnLeave", function()
            CludesUI.HideWidgetTooltip()
        end)
        local function UpdateSw()
            updateSw()
            if (getS().castBorderSize or 1) == 0 then
                sw:SetAlpha(0.3)
                block:Show()
            else
                sw:SetAlpha(1)
                block:Hide()
            end
        end
        CludesUI.RegisterWidgetRefresh(UpdateSw)
        UpdateSw()
    end

    -- Apply-to-all links (main frames page): the style link carries the style,
    -- its offsets, shifts, layering and colour; the size link the size, its
    -- exact px, colour and style. Both carry the opt-in itself.
    if sync then
        local function CopyTo(units, withSize)
            local source = getS()
            for idx = 1, #units do
                local d = sync.db(units[idx])
                if d and d ~= source then
                    d.castBorderCustom = source.castBorderCustom
                    d.castBorderStyle = source.castBorderStyle
                    d.castBorderOffsetX, d.castBorderOffsetY =
                        source.castBorderOffsetX, source.castBorderOffsetY
                    d.castBorderShiftX, d.castBorderShiftY = source.castBorderShiftX, source.castBorderShiftY
                    local c = source.castBorderColor
                    if c then
                        d.castBorderColor = { r = c.r, g = c.g, b = c.b }
                    end
                    d.castBorderAlpha = source.castBorderAlpha
                    if withSize then
                        d.castBorderSize = source.castBorderSize
                        -- Verbatim; a source with no exact size clears a set one
                        -- with false (nil would not travel through mirror sync).
                        local v = source.castBorderSizePx
                        if v == nil and d.castBorderSizePx ~= nil then
                            v = false
                        end
                        d.castBorderSizePx = v
                    else
                        d.castBorderBehind = source.castBorderBehind
                    end
                end
            end
            onChange()
            for idx = 1, #units do
                CludesUI.ReapplyMatchPads(units[idx] .. "Castbar")
            end
            CludesUI:RefreshPage()
        end
        local function StyleSynced()
            local source = getS()
            local bt = source.castBorderStyle or "solid"
            for idx = 1, #sync.units do
                local d = sync.db(sync.units[idx])
                if d then
                    if (d.castBorderCustom == true) ~= (source.castBorderCustom == true) then
                        return false
                    end
                    if (d.castBorderStyle or "solid") ~= bt then
                        return false
                    end
                    if
                        d.castBorderOffsetX ~= source.castBorderOffsetX
                        or d.castBorderOffsetY ~= source.castBorderOffsetY
                    then
                        return false
                    end
                    if
                        d.castBorderShiftX ~= source.castBorderShiftX
                        or d.castBorderShiftY ~= source.castBorderShiftY
                    then
                        return false
                    end
                    if (d.castBorderBehind == true) ~= (source.castBorderBehind == true) then
                        return false
                    end
                end
            end
            return true
        end
        local function SizeSynced()
            local source = getS()
            local bs, bt = source.castBorderSize or 1, source.castBorderStyle or "solid"
            -- Exact sizes compare as rendered (a cleared or stale value equals none).
            local bpx = CludesUI.BorderPx(source.castBorderSizePx, bs, bt)
            for idx = 1, #sync.units do
                local d = sync.db(sync.units[idx])
                if d then
                    if (d.castBorderCustom == true) ~= (source.castBorderCustom == true) then
                        return false
                    end
                    if (d.castBorderSize or 1) ~= bs then
                        return false
                    end
                    if (d.castBorderStyle or "solid") ~= bt then
                        return false
                    end
                    if CludesUI.BorderPx(d.castBorderSizePx, bs, bt) ~= bpx then
                        return false
                    end
                end
            end
            return true
        end
        local lr, rr = row._leftRegion, row._rightRegion
        CludesUI.BuildSyncIcon({
            region = lr,
            tooltip = "Apply Cast Bar Border Style to all Frames",
            onClick = function()
                CopyTo(sync.units, false)
            end,
            isSynced = StyleSynced,
            flashTargets = function()
                return { lr }
            end,
            multiApply = {
                elementKeys = sync.units,
                elementLabels = sync.labels,
                getCurrentKey = sync.current,
                onApply = function(keyList)
                    CopyTo(keyList, false)
                end,
            },
        })
        CludesUI.BuildSyncIcon({
            region = rr,
            tooltip = "Apply Cast Bar Border to all Frames",
            onClick = function()
                CopyTo(sync.units, true)
            end,
            isSynced = SizeSynced,
            flashTargets = function()
                return { rr }
            end,
            multiApply = {
                elementKeys = sync.units,
                elementLabels = sync.labels,
                getCurrentKey = sync.current,
                onApply = function(keyList)
                    CopyTo(keyList, true)
                end,
            },
        })
    end
    return y0 - posY
end

-- Boss Frames DISPLAY "Border Style | Border Size": the boss frames' own frame
-- border. "Inherit (Main Frames)" (the first entry; boss borderCustom false)
-- keeps the mini frame donor's border, as before; any other pick stores the
-- boss table's own border, and the size, colour and Border Options cog then
-- edit it (while inheriting they show what is drawn, greyed). A textured style
-- adds Width Offset | Height Offset. Every slot is BlizzStyle.Gate'd, so the
-- stock styles drop the rows. B = the boss settings table (boss1-5 share it);
-- onChange repaints. Returns the height built. On ns: the page builders sit at
-- their upvalue caps.
function mod.UF_BossFrameBorderRows(W, hostFrame, posY, B, onChange)
    local BS = CludesUI.BlizzStyle
    local y0 = posY
    local function Inheriting()
        return B.borderCustom ~= true
    end
    -- What the live frames draw: the donor's border while inheriting.
    local function Src()
        return mod.UF_BossBorderSettings()
    end
    local NEEDS_STYLE = "This option requires a Border Style other than Inherit (Main Frames)."
    local texValues, texOrder = CludesUI.GetBorderTextureDropdown()
    table.insert(texOrder, 1, "inherit")
    texValues.inherit = "Inherit (Main Frames)"
    local row, hgt = W:DualRow(
        hostFrame,
        posY,
        BS.Gate("unitframes", {
            type = "dropdown",
            text = "Border Style",
            tooltip = "Border art drawn around the boss frames. Inherit (Main Frames) uses the main frames' border.",
            values = texValues,
            order = texOrder,
            getValue = function()
                if Inheriting() then
                    return "inherit"
                end
                return B.borderTexture or "solid"
            end,
            setValue = function(v)
                if v == "inherit" then
                    B.borderCustom = false
                    -- Show Behind and Power Bar Seam read the boss table in
                    -- either mode, and their cog hides while inheriting.
                    if B.borderBehind then
                        B.borderBehind = false
                    end
                    if B.borderPowerSeam then
                        B.borderPowerSeam = false
                    end
                else
                    B.borderCustom = true
                    B.borderTexture = v
                    B.borderTextureOffset, B.borderTextureOffsetY = nil, nil
                    B.borderTextureShiftX, B.borderTextureShiftY = nil, nil
                    local col, behind = CludesUI.GetBorderStyleSelectDefaults(v)
                    B.borderColor, B.borderAlpha, B.borderBehind = col, 1, behind
                    local defSz = CludesUI.GetBorderDefaultSize("unitframes", v)
                    if defSz then
                        B.borderSize = defSz
                    end
                    -- A style pick returns the frames to their legacy step; clear a
                    -- set exact size (false travels through mirror sync, nil would not).
                    if B.borderSizePx then
                        B.borderSizePx = false
                    end
                end
                onChange()
                -- The Width / Height Offset row exists only under a textured style.
                CludesUI:RefreshPage(true)
            end,
        }),
        BS.Gate(
            "unitframes",
            CludesUI.BorderPxSliderCfg({
                text = "Border Size",
                trackWidth = 120,
                disabled = Inheriting,
                disabledTooltip = NEEDS_STYLE,
                rawTooltip = true,
                getStep = function()
                    return Src().borderSize or 1
                end,
                setStep = function(step)
                    B.borderSize = step
                end,
                getTex = function()
                    return Src().borderTexture or "solid"
                end,
                getPx = function()
                    return Src().borderSizePx
                end,
                setPx = function(v)
                    B.borderSizePx = v
                end,
                -- The refresh dims the colour swatch at 0.
                apply = function()
                    onChange()
                    CludesUI:RefreshPage()
                end,
            })
        )
    )
    posY = posY - hgt
    -- Width Offset | Height Offset: a textured style's outward offsets.
    do
        local texture = B.borderTexture or "solid"
        if not Inheriting() and texture ~= "solid" and texture ~= "" then
            local ocfgL, ocfgR = CludesUI.BorderOffsetRowCfgs({
                addonKey = "unitframes",
                getTex = function()
                    return B.borderTexture or "solid"
                end,
                getStep = function()
                    return B.borderSize or 1
                end,
                getSizeKey = function()
                    return B.borderSize or 1
                end,
                getPx = function()
                    return B.borderSizePx
                end,
                getX = function()
                    return B.borderTextureOffset
                end,
                setX = function(v)
                    B.borderTextureOffset = v
                end,
                getY = function()
                    return B.borderTextureOffsetY
                end,
                setY = function(v)
                    B.borderTextureOffsetY = v
                end,
                apply = onChange,
            })
            local _, oh =
                W:DualRow(hostFrame, posY, BS.Gate("unitframes", ocfgL), BS.Gate("unitframes", ocfgR))
            posY = posY - oh
        end
    end
    if CludesUI._prebuilding then
        return y0 - posY
    end

    -- Border Options cog (left): shifts and layering, own textured styles only.
    do
        -- A stored shift, else the registry default for the style and size.
        local function Shift(key, isY)
            if B[key] then
                return B[key]
            end
            local _, _, dsx, dsy =
                CludesUI.GetBorderDefaults("unitframes", B.borderTexture or "solid", B.borderSize or 1)
            if isY then
                return dsy
            end
            return dsx
        end
        -- The shown default stores nil, any other value (0 included) is kept.
        local function SetShift(key, isY, v)
            B[key] = nil
            if v ~= Shift(key, isY) then
                B[key] = v
            end
            onChange()
        end
        local cogBtn = CludesUI.BuildInlineCog(row._leftRegion, {
            title = "Border Options",
            rows = {
                {
                    type = "slider",
                    label = "Shift X",
                    min = -10,
                    max = 10,
                    step = 1,
                    get = function()
                        return Shift("borderTextureShiftX", false)
                    end,
                    set = function(v)
                        SetShift("borderTextureShiftX", false, v)
                    end,
                },
                {
                    type = "slider",
                    label = "Shift Y",
                    min = -10,
                    max = 10,
                    step = 1,
                    get = function()
                        return Shift("borderTextureShiftY", true)
                    end,
                    set = function(v)
                        SetShift("borderTextureShiftY", true, v)
                    end,
                },
                {
                    type = "toggle",
                    label = "Show Behind",
                    get = function()
                        return B.borderBehind == true
                    end,
                    set = function(v)
                        B.borderBehind = v
                        onChange()
                    end,
                },
                {
                    type = "toggle",
                    label = "Power Bar Seam",
                    tooltip = "Draws the border style's seam art between the health bar and an attached power bar.",
                    disabled = function()
                        local place = B.powerPosition or "below"
                        local border = Src()
                        return not (
                            CludesUI.GetBorderCompanion(border.borderTexture or "solid", "sepH")
                            and (B.borderSizeOverride or border.borderSize or 1) > 0
                            and (place == "above" or place == "below")
                            and (B.powerHeight or 6) > 0
                        )
                    end,
                    disabledTooltip = "This option requires an attached Power Bar, a Border Size above 0 and a border style with seam art.",
                    rawTooltip = true,
                    get = function()
                        return B.borderPowerSeam == true
                    end,
                    set = function(v)
                        B.borderPowerSeam = v
                        onChange()
                    end,
                },
            },
        })
        local function UpdateCogVis()
            local texture = B.borderTexture or "solid"
            if Inheriting() or texture == "solid" or texture == "" or BS.Get("unitframes") then
                cogBtn:Hide()
            else
                cogBtn:Show()
            end
        end
        CludesUI.RegisterWidgetRefresh(UpdateCogVis)
        UpdateCogVis()
    end

    -- Colour swatch (with alpha) on Border Size: shows what is drawn; greyed
    -- and blocked while inheriting or at 0.
    do
        local rgn = row._rightRegion
        -- Corner Radius (CludesUI_RoundedCorners.lua): the boss table's own,
        -- beside the control with the swatch left of it; while inheriting the
        -- main frames' radius applies.
        CludesUI.BuildInlineCog(rgn, {
            title = "Corner Radius",
            tip = "Corner Radius",
            disabled = function()
                return Inheriting() or not CludesUI.RoundedStyleOK(B.borderTexture)
            end,
            disabledTooltip = function()
                if Inheriting() then
                    return NEEDS_STYLE
                end
                return "This option requires the Solid, Glow or Shadow border style."
            end,
            rows = CludesUI.RoundedJoinRow(
                CludesUI.RoundedCornerRows({
                    {
                        type = "slider",
                        label = "Corner Radius",
                        min = 0,
                        max = CludesUI.ROUNDED_MAX_RADIUS,
                        step = 1,
                        get = function()
                            return Src().cornerRadius or 0
                        end,
                        set = function(v)
                            B.cornerRadius = v
                            onChange()
                        end,
                    },
                }, function()
                    return Src().cornerMask
                end, function(v)
                    B.cornerMask = v
                    onChange()
                end),
                "Join Power Bar",
                "Rounds a detached power bar right above or below the frame as one shape with it.",
                function()
                    return B.cornerJoinPower
                end,
                function(v)
                    B.cornerJoinPower = v
                    onChange()
                end,
                function()
                    local place = B.powerPosition or "below"
                    return place == "detached_top" or place == "detached_bottom"
                end,
                "Detached Power Bar"
            ),
        })
        local sw, updateSw = CludesUI.BuildColorSwatch(rgn, row:GetFrameLevel() + 3, function()
            local s = Src()
            local c = s.borderColor
            return c and c.r or 0, c and c.g or 0, c and c.b or 0, s.borderAlpha or 1
        end, function(r, g, b, a)
            B.borderColor = { r = r, g = g, b = b }
            B.borderAlpha = a
            onChange()
        end, true, 20)
        CludesUI.PanelPP.Point(sw, "RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
        sw:SetScript("OnEnter", function()
            CludesUI.ShowWidgetTooltip(sw, "Border")
        end)
        sw:SetScript("OnLeave", function()
            CludesUI.HideWidgetTooltip()
        end)
        rgn._lastInline = sw
        local block = CreateFrame("Frame", nil, sw)
        block:SetAllPoints()
        block:SetFrameLevel(sw:GetFrameLevel() + 10)
        block:EnableMouse(true)
        block:SetScript("OnEnter", function()
            local req = Inheriting() and NEEDS_STYLE or "This option requires a Border Size above 0."
            CludesUI.ShowWidgetTooltip(sw, CludesUI.DisabledTooltip(req))
        end)
        block:SetScript("OnLeave", function()
            CludesUI.HideWidgetTooltip()
        end)
        local function UpdateSw()
            updateSw()
            if Inheriting() or (B.borderSize or 1) == 0 then
                sw:SetAlpha(0.3)
                block:Show()
            else
                sw:SetAlpha(1)
                block:Hide()
            end
        end
        CludesUI.RegisterWidgetRefresh(UpdateSw)
        UpdateSw()
    end
    return y0 - posY
end

-- Tracked Auras popup for target/focus/boss debuff filters ("Edit Tracked
-- Auras" pinned action; shared chrome in CludesUI_Widgets.lua). Tri-state
-- lists on the unit's settings table (s.debuffInclude/s.debuffExclude); boss1-5
-- share one "boss" table. Copy row clones both lists from another unit. Engine
-- wiring: include link + shared excludes in CUI_UnitFrames_AuraContainers.lua.
local TRACKED_UNITS = {
    { key = "target", label = "Target" },
    { key = "focus", label = "Focus" },
    { key = "boss", label = "Boss" },
}
local TRACKED_TITLES = {
    target = "Target Tracked Auras",
    focus = "Focus Tracked Auras",
    boss = "Boss Tracked Auras",
}
local function TrackedList(unitKey, field)
    local saved = mod.db
    local s = saved and saved.profile and saved.profile[unitKey]
    if not s then
        return nil
    end
    if not s[field] then
        s[field] = {}
    end
    return s[field]
end
function mod.UFOpt_ShowTrackedAuras(unitKey)
    local choices = {}
    for idx = 1, #TRACKED_UNITS do
        local u = TRACKED_UNITS[idx]
        if u.key ~= unitKey then
            choices[#choices + 1] = u
        end
    end
    local function Changed()
        if mod.ReloadFrames then
            mod.ReloadFrames()
        end
        if mod.UpdatePreview then
            mod.UpdatePreview()
        end
        -- Non-force: the Debuff Filter dropdown's empty warning (Only Tracked
        -- Auras with its list emptied) re-reads live, without rebuilding the
        -- page under the popup.
        CludesUI:RefreshPage()
    end
    CludesUI.ShowTrackedAurasPopup({
        eyebrow = "UNIT FRAME AURA FILTERS",
        title = TRACKED_TITLES[unitKey] or "Tracked Auras",
        subtitle = "Included debuffs show in addition to your Debuff Filter selection (unless it is set to Only Tracked Auras).",
        includeGet = function()
            return TrackedList(unitKey, "debuffInclude")
        end,
        excludeGet = function()
            return TrackedList(unitKey, "debuffExclude")
        end,
        -- Caster scope per entry (the MINE tag on each row). Boss includes default
        -- to Only My Casts (nameplate parity) with an any-caster OPT-OUT map;
        -- target/focus includes default to any caster with a MINE OPT-IN map.
        -- Engine: AppendIncludeLinks in CUI_UnitFrames_AuraContainers.lua.
        includeMine = (unitKey == "boss") and {
            anyGet = function()
                return TrackedList(unitKey, "debuffIncludeAnyCaster")
            end,
        } or {
            mineGet = function()
                return TrackedList(unitKey, "debuffIncludeMine")
            end,
        },
        includePrompt = "Enter the spell ID to always show on this frame.",
        excludePrompt = "Enter the spell ID to exclude from this frame.",
        onChanged = Changed,
        copyFrom = {
            label = "Copy Included/Excluded Spells From:",
            choices = choices,
            apply = function(srcKey)
                local saved = mod.db
                local source = saved and saved.profile and saved.profile[srcKey]
                local dst = saved and saved.profile and saved.profile[unitKey]
                if not (source and dst) then
                    return
                end
                local function Clone(t)
                    if not t then
                        return nil
                    end
                    local c = {}
                    for k, v in pairs(t) do
                        c[k] = v
                    end
                    return c
                end
                dst.debuffInclude = Clone(source.debuffInclude)
                dst.debuffExclude = Clone(source.debuffExclude)
                -- The caster-scope maps have opposite polarity per unit kind (boss:
                -- any-caster opt-out; target/focus: MINE opt-in). Same kind copies
                -- them as-is; across kinds the set is inverted so every copied
                -- entry keeps the scope it showed with.
                local srcBoss, dstBoss = srcKey == "boss", unitKey == "boss"
                if srcBoss == dstBoss then
                    dst.debuffIncludeAnyCaster = Clone(source.debuffIncludeAnyCaster)
                    dst.debuffIncludeMine = Clone(source.debuffIncludeMine)
                else
                    local srcMap = srcBoss and source.debuffIncludeAnyCaster or source.debuffIncludeMine
                    local inv = {}
                    for ident in pairs(source.debuffInclude or {}) do
                        if not (srcMap and srcMap[ident]) then
                            inv[ident] = true
                        end
                    end
                    if dstBoss then
                        dst.debuffIncludeAnyCaster = inv
                        dst.debuffIncludeMine = nil
                    else
                        dst.debuffIncludeMine = inv
                        dst.debuffIncludeAnyCaster = nil
                    end
                end
                Changed()
            end,
        },
    })
end

-- Options preview: the first fake buff stands in for a purgeable one while
-- Purgeable Buff Glow is set on target/focus and this character can purge or
-- spellsteal (the live frame's own gate). The host is our own frame.
function mod.UFOpt_PreviewPurgeGlow(bf, unitKey, s, wid, hgt)
    local Glows = CludesUI.Glows
    if not mod.UF_PurgeGlowSpec then
        return
    end
    local g = (unitKey == "target" or unitKey == "focus") and s and s.buffPurgeGlow
    local enabled = type(g) == "number" and g > 0
    if enabled then
        local AK = CludesUI.AuraKit
        local magic, enrage = false, false
        if AK and AK.OffensiveDispelTypes then
            magic, enrage = AK.OffensiveDispelTypes()
        end
        enabled = magic or enrage
    end
    local host = bf._purgeGlow
    if not enabled then
        if host then
            if host._cuiGlowActive then
                Glows.StopGlow(host)
            end
            host:Hide()
        end
        return
    end
    if not host then
        host = CreateFrame("Frame", nil, bf)
        host:SetAllPoints(bf)
        host:SetFrameLevel(bf:GetFrameLevel() + 2)
        bf._purgeGlow = host
    end
    host:Show()
    -- The live renderer's own spec, so the preview is the live look.
    Glows.StartSpecGlow(host, mod.UF_PurgeGlowSpec(s), wid, hgt, "engine", Glows.PANEL_EXTRA)
end

-- Target/focus/boss Debuff Filter: ONE single-select mode, an engine VIEW over
-- the legacy keys (ns.UF_DebuffFilterMode in CUI_UnitFrames_AuraContainers.lua;
-- nothing is rewritten on update, the first pick writes s.debuffFilterMode --
-- the only key this dropdown ever writes). "Edit Tracked Auras" is an action
-- row above a divider; Tracked Auras are additional tracking in every mode,
-- and Only Tracked Auras is the one mode that can render nothing (its tooltip
-- points at the action row, AttachDebuffModeWarn carries the empty warning).
local DEBUFF_MODE_ORDER = {
    "__editTracked",
    "---",
    "all",
    "tracked",
    "own",
    "important",
    "importantOwn",
    "importantOrOwn",
}
local DEBUFF_MODE_TIPS = {
    all = "Shows every debuff on this frame.",
    tracked = "Shows only this frame's Tracked Auras; add them with Edit Tracked Auras at the top of this menu.",
    own = "Shows only the debuffs you apply.",
    important = "Shows only debuffs Blizzard flags as important.",
    importantOwn = "Shows only the debuffs you apply that Blizzard also flags as important.",
    importantOrOwn = "Shows the debuffs you apply plus important debuffs from anyone.",
}
local function DebuffModeDropdownCfg(textValue, unitKey, getS, onChanged, extra)
    local values = {
        __editTracked = {
            text = "Edit Tracked Auras",
            action = function()
                mod.UFOpt_ShowTrackedAuras(unitKey)
            end,
        },
        all = "Show All",
        tracked = "Only Tracked Auras",
        own = "Own Only",
        important = "Important Only",
        importantOwn = "Important and Own",
        importantOrOwn = "Important or Own",
        _menuOpts = {
            onItemHover = function(key, item)
                local tipText = DEBUFF_MODE_TIPS[key]
                if tipText and item then
                    CludesUI.ShowWidgetTooltip(item, tipText)
                end
            end,
            onItemLeave = function()
                CludesUI.HideWidgetTooltip()
            end,
        },
    }
    local conf = {
        type = "dropdown",
        text = textValue,
        values = values,
        order = DEBUFF_MODE_ORDER,
        getValue = function()
            return mod.UF_DebuffFilterMode(getS())
        end,
        setValue = function(v)
            getS().debuffFilterMode = v
            onChanged()
        end,
    }
    if extra then
        for k, val in pairs(extra) do
            conf[k] = val
        end
    end
    return conf
end
-- Hide Exhaustion: the Debuff Filter cog row of target, focus and boss (their
-- filter is a single-pick mode list; the player's checkbox Debuff Filter has
-- the same toggle as a row). s.debuffHideExhaustion, nil = on: the Bloodlust
-- lockouts stay hidden until it is turned off (stored as false).
local function HideExhaustionRow(getS, onChanged)
    return {
        type = "toggle",
        label = "Hide Exhaustion",
        tooltip = "Hides Sated, Exhaustion, Temporal Displacement and the other Bloodlust lockout debuffs.",
        get = function()
            return getS().debuffHideExhaustion ~= false
        end,
        set = function(v)
            if v then
                getS().debuffHideExhaustion = nil
            else
                getS().debuffHideExhaustion = false
            end
            onChanged()
        end,
    }
end
-- The standard red empty-selection warning on the mode dropdown built by a
-- DualRow slot (rgn._control): shown while Only Tracked Auras has no active
-- entry and the column is not already dimmed by its Display = None.
local function AttachDebuffModeWarn(rgn, getS, offFn)
    local dropdown = rgn and rgn._control
    if not dropdown then
        return
    end
    CludesUI.AttachEmptyFilterWarn(
        rgn,
        dropdown,
        CludesUI.L("You are displaying NO debuffs at all."),
        function()
            if offFn() then
                return true
            end
            local s = getS()
            return mod.UF_DebuffFilterMode(s) ~= "tracked" or mod.UF_DebuffHasIncludes(s)
        end
    )
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    -- Init fn on the namespace; the main addon calls it from SetupOptionsPanel()
    -- once ns.db/ns.frames are ready, or immediately if that already ran.
    mod._InitCUIModule = function()
        if not CludesUI or not CludesUI.RegisterModule then
            return
        end
        if not mod.db then
            return
        end

        local Pix = CludesUI.PanelPP
        local saved = mod.db
        local frameList = mod.frames
        local ReloadFrames = mod.ReloadFrames
        local ResolveFontPath = mod.ResolveFontPath

        local floor = math.floor
        local abs = math.abs

        -- The preview's texts show names as the frames do, so they take a font
        -- family as live; every font write to them goes through here.
        local SetPVFont = CludesUI.ApplyModuleFontFamily

        ---------------------------------------------------------------------------
        --  Shared helpers
        ---------------------------------------------------------------------------
        local activePreview
        local allPreviews = {}

        -- Mutable state the page builders share. A table instead of locals so the
        -- builders under UnitFrames_Options\ read and write the live values.
        local optionState = {}
        optionState.showCombatIndicatorPreview = false
        optionState.showHealAbsorbPreview = false -- eyeball toggle for the Heal Absorb Style preview
        optionState.showMaxHealthPreview = false -- eyeball toggle for the Max Health Style preview
        optionState.showDispelOverlayPreview = false -- eyeball toggle for the player dispel overlay preview
        -- Preview hover-highlight hint text (shared across Single/Multi tabs)
        optionState._ufPreviewHintFS_display = nil -- hint FontString for the Main Frames page
        local _displayHeaderBaseH = 0 -- display header height WITHOUT hint

        local function IsPreviewHintDismissed()
            return CludesUIDB and CludesUIDB.previewHintDismissed
        end

        -- Preview click -> scroll to and glow the mapped row (Main, Mini and Boss
        -- pages). A target may be a resolver function (e.g. boss buff/debuff icons,
        -- which point to Simple Display or Location depending on the mode). On ns
        -- to stay clear of the 200-local cap; dismissHint is Main-page only.
        mod._UFNavigateToSetting = function(targets, key, playGlow, dismissHint)
            if not targets then
                return
            end
            local m = targets[key]
            if type(m) == "function" then
                m = m()
            end
            if not m or not m.section or not m.target then
                return
            end
            if dismissHint then
                CludesUI.DismissPreviewHint(optionState._ufPreviewHintFS_display, _displayHeaderBaseH, 29, 17)
            end
            local scrollFrame = CludesUI._scrollFrame
            if not scrollFrame then
                return
            end
            local _, _, _, _, headerY = m.section:GetPoint(1)
            if not headerY then
                return
            end
            local scrollPos = math.max(0, math.abs(headerY) - 40)
            CludesUI.SmoothScrollTo(scrollPos)
            local glowTarget = m.target
            if m.slotSide and m.target then
                local regionFrame = (m.slotSide == "left") and m.target._leftRegion or m.target._rightRegion
                if regionFrame then
                    glowTarget = regionFrame
                end
            end
            -- A page rebuilt before the glow plays (page reuse) has parked or dressed
            -- its rows again: a target that moved on gets no glow.
            local gen = PoolGen(glowTarget)
            C_Timer.After(0.15, function()
                if PoolGen(glowTarget) ~= gen or PoolIsIdle(glowTarget) then
                    return
                end
                playGlow(glowTarget)
            end)
        end

        -- allPreviews: unit -> its preview. An entry whose frame a kept header root
        -- dressed again for another unit (pv._pvUnit) is stale and skipped.
        local function UpdatePreview()
            for k, pv in pairs(allPreviews) do
                if pv and pv._pvUnit == k and pv.Update then
                    pv:Update()
                end
            end
            -- Sync in-game boss preview fake debuffs with live edits (location, simple display, size).
            if mod.RefreshBossPreviewDebuffs then
                mod.RefreshBossPreviewDebuffs()
            end
        end

        local function ReloadAndUpdate()
            -- Resolve at call time: ns.ReloadFrames is wrapped after this file's setup
            -- (aura containers, dispel overlay); a load-time capture bypasses those hooks.
            local rf = mod.ReloadFrames or ReloadFrames
            if rf then
                rf()
            end
            UpdatePreview()
        end

        CludesUI:RegisterOnShow(UpdatePreview)
        mod.UpdatePreview = UpdatePreview

        -- Re-run preview Update() when panel scale changes so border pixel sizes refresh
        if not CludesUI._onScaleChanged then
            CludesUI._onScaleChanged = {}
        end
        CludesUI._onScaleChanged[#CludesUI._onScaleChanged + 1] = UpdatePreview

        -- Hide UIParent-parented disabled overlays when the options window closes
        CludesUI:RegisterOnHide(function()
            for k, pv in pairs(allPreviews) do
                if pv and pv._pvUnit == k and pv._disabledOverlay then
                    pv._disabledOverlay:Hide()
                end
            end
            -- Auto-disable in-game boss preview so live boss frames don't linger on close.
            if mod._bossPreviewActive and mod.SetBossPreview then
                mod.SetBossPreview(false)
            end
            -- Player Aura Bars root lives on the shared live scrollFrame, not a page's
            -- own `parent`; only fires on full window close (cf. _bmRoot/_dmRoot/_ccRoot
            -- cleanup in CUI_RaidFrames_Options.lua). Module switching is handled below via SelectModule.
            -- The root is kept for the session (its next render dresses it again):
            -- parked hidden, off the scroll frame; nil means "needs a render".
            if mod._pabRoot then
                mod.PABMP_ParkRoot()
            end
        end)

        -- Rebuild Player Aura Bars on re-open while already on that page: RegisterOnHide
        -- tore _pabRoot down, and unlike a tab switch (buildPage/onPageCacheRestore) a
        -- plain re-open rebuilds nothing. Mirrors RF's RegisterOnShow in CUI_RaidFrames_Options.lua.
        CludesUI:RegisterOnShow(function()
            if
                CludesUI:GetActiveModule() == "CludesUIUnitFrames"
                and CludesUI:GetActivePage() == PAGE_AURA_BARS
                and not mod._pabRoot
            then
                C_Timer.After(0, function()
                    if
                        CludesUI:GetActiveModule() == "CludesUIUnitFrames"
                        and CludesUI:GetActivePage() == PAGE_AURA_BARS
                        and mod.PABMP_BuildPage
                    then
                        mod.PABMP_BuildPage(PAGE_AURA_BARS, nil, -6)
                    end
                end)
            end
        end)

        -- Tear down _pabRoot on switch to a DIFFERENT top-level module: window stays
        -- open (RegisterOnHide never fires) and the root would overlap the new module's
        -- content. Mirrors RF's SelectModule cleanup in CUI_RaidFrames_Options.lua.
        if CludesUI.SelectModule then
            hooksecurefunc(CludesUI, "SelectModule", function(_, folderName)
                if folderName ~= "CludesUIUnitFrames" and mod._pabRoot then
                    mod.PABMP_ParkRoot()
                end
            end)
        end

        ---------------------------------------------------------------------------
        --  Individual Display unit selector
        ---------------------------------------------------------------------------
        optionState.selectedUnit = "player"

        -- External unit pre-select: direct setter + pending override consumed at page build.
        CludesUI._setUnitFrameUnit = function(unitToken)
            optionState.selectedUnit = unitToken
        end
        CludesUI._consumePendingUnitSelect = function()
            local pending = CludesUI._pendingUnitSelect
            if pending then
                optionState.selectedUnit = pending
                CludesUI._pendingUnitSelect = nil
            end
        end

        local unitLabels = {
            ["player"] = "Player",
            ["target"] = "Target",
            ["focus"] = "Focus",
            ["targettarget"] = "Target of Target",
            ["focustarget"] = "Focus Target",
            ["pet"] = "Pet",
            ["boss"] = "Boss",
        }
        local unitOrder = { "player", "target", "focus" }

        -- Side mapping: which side the portrait sits on for each unit
        local unitSide = {
            ["player"] = "left",
            ["target"] = "right",
            ["focus"] = "right",
            ["targettarget"] = "left",
            ["focustarget"] = "left",
            ["pet"] = "left",
            ["boss"] = "right",
        }

        ---------------------------------------------------------------------------
        --  Group editing state  (sync icon targets)
        ---------------------------------------------------------------------------
        local UNIT_DB_MAP = {
            player = function()
                return saved.profile.player
            end,
            target = function()
                return saved.profile.target
            end,
            focus = function()
                return saved.profile.focus
            end,
            targettarget = function()
                return saved.profile.targettarget
            end,
            focustarget = function()
                return saved.profile.focustarget
            end,
            pet = function()
                return saved.profile.pet
            end,
            boss = function()
                return saved.profile.boss
            end,
        }

        ---------------------------------------------------------------------------
        --  Glow site: the target/focus Purgeable Buff Glow as a shared glow
        --  descriptor over one unit's settings (getS), used by the Buffs cog and the
        --  Global Settings Glows page. Engine aura buttons: C-side styles only; an
        --  unset color is the suite default (gold).
        ---------------------------------------------------------------------------
        local function UF_PurgeGlowDesc(getS)
            -- Blizzard Border: Blizzard's static stealable art, outside the style list.
            local border = CludesUI.Glows.STEALABLE_BORDER
            return {
                host = "engine",
                extras = { { value = border, label = "Blizzard Border", style = border } },
                caps = { mode = true, params = true, bg = true },
                defaultColor = CludesUI.Glows.DEFAULT_COLOR,
                onChange = ReloadAndUpdate,
                get = function(f)
                    local s = getS()
                    if f == "style" then
                        return s.buffPurgeGlow or 0
                    elseif f == "mode" then
                        return s.buffPurgeGlowColorMode or (s.buffPurgeGlowColor and "custom" or "default")
                    end
                    return CludesUI.GlowOptions.FlatGet(s, "buffPurgeGlow", f)
                end,
                set = function(f, a, b, c)
                    local s = getS()
                    if f == "style" then
                        s.buffPurgeGlow = (a ~= 0) and a or nil
                    elseif f == "mode" then
                        s.buffPurgeGlowColorMode = a
                    else
                        CludesUI.GlowOptions.FlatSet(s, "buffPurgeGlow", f, a, b, c)
                    end
                end,
            }
        end
        -- Target/focus Important Cast Glow: a bar host storing shared style
        -- indices (every style but Shape); an unset mode is the stored custom color.
        local function UF_ImpCastGlowDesc(getS, onChange)
            return {
                host = "bar",
                caps = { mode = true, params = true, bg = true },
                defaultColor = { r = 1, g = 0.2, b = 0.2 },
                onChange = onChange or ReloadAndUpdate,
                isOff = function()
                    return getS().castbarImportantGlow ~= true
                end,
                get = function(f)
                    local s = getS()
                    if f == "style" then
                        return s.castbarImportantGlowStyle or 1
                    elseif f == "mode" then
                        return s.castbarImportantGlowColorMode or "custom"
                    end
                    return CludesUI.GlowOptions.FlatGet(s, "castbarImportantGlow", f)
                end,
                set = function(f, a, b, c)
                    local s = getS()
                    if f == "style" then
                        if a == 0 then
                            s.castbarImportantGlow = false
                        else
                            s.castbarImportantGlow = true
                            s.castbarImportantGlowStyle = a
                        end
                    elseif f == "mode" then
                        s.castbarImportantGlowColorMode = a
                    else
                        CludesUI.GlowOptions.FlatSet(s, "castbarImportantGlow", f, a, b, c)
                    end
                end,
            }
        end
        do
            local GO = CludesUI.GlowOptions
            -- Open Settings selects the unit first (the page shows one unit at a time).
            local function SelectUnit(unitToken)
                return function()
                    CludesUI._setUnitFrameUnit(unitToken)
                    CludesUI._pendingUnitSelect = unitToken
                end
            end
            GO.RegisterSite({
                id = "uf_purge_target",
                label = "Target Purgeable Buff Glow",
                group = "module",
                module = "CludesUIUnitFrames",
                page = PAGE_DISPLAY,
                section = "BUFFS AND DEBUFFS",
                preSelect = SelectUnit("target"),
                -- The Purgeable Buffs cog sits on the unit's Buff Filter row.
                highlight = "Buff Filter",
                desc = UF_PurgeGlowDesc(UNIT_DB_MAP.target),
            })
            GO.RegisterSite({
                id = "uf_purge_focus",
                label = "Focus Purgeable Buff Glow",
                group = "module",
                module = "CludesUIUnitFrames",
                page = PAGE_DISPLAY,
                section = "BUFFS AND DEBUFFS",
                preSelect = SelectUnit("focus"),
                highlight = "Buff Filter",
                desc = UF_PurgeGlowDesc(UNIT_DB_MAP.focus),
            })
            GO.RegisterSite({
                id = "uf_importantcast_target",
                label = "Target Important Cast Glow",
                group = "module",
                module = "CludesUIUnitFrames",
                page = PAGE_DISPLAY,
                section = "CAST BAR",
                preSelect = SelectUnit("target"),
                highlight = "Important Cast Glow",
                desc = UF_ImpCastGlowDesc(UNIT_DB_MAP.target),
            })
            GO.RegisterSite({
                id = "uf_importantcast_focus",
                label = "Focus Important Cast Glow",
                group = "module",
                module = "CludesUIUnitFrames",
                page = PAGE_DISPLAY,
                section = "CAST BAR",
                preSelect = SelectUnit("focus"),
                highlight = "Important Cast Glow",
                desc = UF_ImpCastGlowDesc(UNIT_DB_MAP.focus),
            })
        end

        local GROUP_UNIT_ORDER = { "player", "target", "focus" }
        local SHORT_LABELS = {
            player = "Player",
            target = "Target",
            focus = "Focus",
            targettarget = "Target of Target",
            focustarget = "Focus Target",
            pet = "Pet",
            boss = "Boss",
        }

        ---------------------------------------------------------------------------
        --  Health display dropdown values
        ---------------------------------------------------------------------------
        local healthDisplayValues = {
            ["both"] = "Current HP | Percent",
            ["curhpshort"] = "Current HP Only",
            ["perhp"] = "Percent Only",
        }
        local healthDisplayOrder = { "both", "curhpshort", "perhp" }

        ---------------------------------------------------------------------------
        --  Health bar texture dropdown -- built LIVE each render (mirrors
        --  GetBorderTextureDropdown) so SharedMedia textures registered after login
        --  always appear; an LSM callback also keeps the shared ns tables current.
        ---------------------------------------------------------------------------
        local function BuildBarTexDropdown()
            -- Refresh shared snapshot from LSM; first call also registers the
            -- late-registration callback (idempotent after).
            CludesUI.AppendSharedMediaTextures(
                mod.healthBarTextureNames or {},
                mod.healthBarTextureOrder or {},
                nil,
                mod.healthBarTextures
            )

            local hbtValues, hbtOrder = {}, {}
            local texNames = mod.healthBarTextureNames or {}
            local texOrder2 = mod.healthBarTextureOrder or {}
            for _, key in ipairs(texOrder2) do
                if key ~= "---" then
                    hbtValues[key] = texNames[key] or key
                    hbtOrder[#hbtOrder + 1] = key
                end
            end
            -- _menuOpts: texture preview backgrounds on each item
            local texLookup = mod.healthBarTextures or {}
            hbtValues._menuOpts = {
                itemHeight = 28,
                background = function(key)
                    return texLookup[key]
                end,
                onItemHover = function(key)
                    local texPath = texLookup[key]
                    for k, pv in pairs(allPreviews) do
                        if pv and pv._pvUnit == k then
                            local hFill = pv._healthFill
                            if hFill then
                                if texPath then
                                    hFill:SetTexture(texPath)
                                    hFill:SetVertexColor(pv._hR or 0.8, pv._hG or 0.2, pv._hB or 0.2, 1)
                                else
                                    hFill:SetVertexColor(1, 1, 1, 1)
                                    hFill:SetColorTexture(pv._hR or 0.8, pv._hG or 0.2, pv._hB or 0.2, 1)
                                end
                            end
                            local pFill = pv._powerFill
                            if pFill then
                                local pvR, pvG, pvB = pv._pR or 0, pv._pG or 0, pv._pB or 1
                                if texPath then
                                    pFill:SetTexture(texPath)
                                    pFill:SetVertexColor(pvR, pvG, pvB, 1)
                                else
                                    pFill:SetVertexColor(1, 1, 1, 1)
                                    pFill:SetColorTexture(pvR, pvG, pvB, 1)
                                end
                            end
                        end
                    end
                end,
                onItemLeave = function(key)
                    -- Revert to the saved texture
                    for k, pv in pairs(allPreviews) do
                        if pv and pv._pvUnit == k and pv.Update then
                            pv:Update()
                        end
                    end
                end,
            }
            return hbtValues, hbtOrder
        end

        ---------------------------------------------------------------------------
        --  Buff anchor / growth direction dropdown values
        ---------------------------------------------------------------------------
        local buffAnchorValues = {
            ["none"] = "None",
            ["topleft"] = "Top Left",
            ["topright"] = "Top Right",
            ["bottomleft"] = "Bottom Left",
            ["bottomright"] = "Bottom Right",
            ["left"] = "Left",
            ["right"] = "Right",
        }
        local buffAnchorOrder =
            { "none", "topleft", "topright", "bottomleft", "bottomright", "left", "right" }

        local buffGrowthValues = {
            ["auto"] = "Auto",
            ["up"] = "Up",
            ["down"] = "Down",
            ["left"] = "Left",
            ["right"] = "Right",
        }
        local buffGrowthOrder = { "auto", "up", "down", "left", "right" }

        local classPowerStyleValues = {
            ["none"] = "None",
            ["modern"] = "Modern",
            ["blizzard"] = "Blizzard",
        }
        local classPowerStyleOrder = { "none", "modern", "blizzard" }

        local classPowerPosValues = {
            ["top"] = "Top",
            ["bottom"] = "Bottom",
            ["above"] = "Above Health Bar",
        }
        local classPowerPosOrder = { "top", "bottom", "above" }

        ---------------------------------------------------------------------------
        --  Text content dropdown values (left / right text)
        ---------------------------------------------------------------------------
        -- Health bar text dropdown values (no power options)
        local healthTextValues = {
            ["name"] = "Name",
            ["nametotarget"] = "Name > Target",
            ["targetname"] = "Target",
            ["levelname"] = "Level | Name",
            ["namelevel"] = "Name | Level",
            ["level"] = "Level",
            ["perhp"] = "Health %",
            ["perhpnosign"] = "Health % (No Sign)",
            ["curhpshort"] = "Health #",
            ["healthshort"] = "Health # Short (230.5K)",
            ["curmaxhp"] = "Health # / Max #",
            ["perhpnum"] = "Health % | #",
            ["both"] = "Health # | %",
            ["bothdash"] = "Health # - %",
            ["perhpnumdash"] = "Health % - #",
            ["absorb"] = "Absorb Amount",
            ["absorbshort"] = "Absorb Short (230k)",
            ["healabsorb"] = "Heal Absorb Amount",
            ["healabsorbshort"] = "Heal Absorb Short (80k)",
            ["group"] = "Group Number",
            ["custom"] = "Custom",
            ["none"] = "None",
        }
        local healthTextOrder = {
            "none",
            "---",
            "custom",
            "---",
            "name",
            "levelname",
            "namelevel",
            "level",
            "perhp",
            "perhpnosign",
            "curhpshort",
            "healthshort",
            "curmaxhp",
            "perhpnum",
            "both",
        }
        -- Boss frames also get "Name > Target" (the boss's target); ToT/FoT/Pet do not.
        local healthTextOrderBoss = {
            "none",
            "---",
            "custom",
            "---",
            "name",
            "nametotarget",
            "targetname",
            "levelname",
            "namelevel",
            "level",
            "perhp",
            "perhpnosign",
            "curhpshort",
            "healthshort",
            "curmaxhp",
            "perhpnum",
            "both",
            "bothdash",
            "perhpnumdash",
            "absorb",
            "absorbshort",
            "healabsorb",
            "healabsorbshort",
        }
        local healthTextOrderPlayer = {
            "none",
            "---",
            "custom",
            "---",
            "name",
            "nametotarget",
            "targetname",
            "levelname",
            "namelevel",
            "level",
            "perhp",
            "perhpnosign",
            "curhpshort",
            "healthshort",
            "curmaxhp",
            "perhpnum",
            "both",
            "bothdash",
            "perhpnumdash",
            "absorb",
            "absorbshort",
            "healabsorb",
            "healabsorbshort",
            "group",
        }
        -- Target/Focus: player's absorb options minus "group" (raid group number is meaningless off the player).
        local healthTextOrderTargetFocus = {
            "none",
            "---",
            "custom",
            "---",
            "name",
            "nametotarget",
            "targetname",
            "levelname",
            "namelevel",
            "level",
            "perhp",
            "perhpnosign",
            "curhpshort",
            "healthshort",
            "curmaxhp",
            "perhpnum",
            "both",
            "bothdash",
            "perhpnumdash",
            "absorb",
            "absorbshort",
            "healabsorb",
            "healabsorbshort",
        }

        -- Text bar (BTB) text dropdown values (includes power options)
        local btbTextValues = {
            ["name"] = "Name",
            ["perhp"] = "Health %",
            ["perhpnosign"] = "Health % (No Sign)",
            ["curhpshort"] = "Health #",
            ["healthshort"] = "Health # Short (230.5K)",
            ["curmaxhp"] = "Health # / Max #",
            ["perhpnum"] = "Health % | #",
            ["both"] = "Health # | %",
            ["perpp"] = "Power %",
            ["curpp"] = "Power Value",
            ["curmaxpp"] = "Power Value / Max",
            ["curhp_curpp"] = "Health | Power Value",
            ["perhp_perpp"] = "Health | Power %",
            ["custom"] = "Custom",
            ["none"] = "None",
        }
        local btbTextOrder = {
            "none",
            "---",
            "custom",
            "---",
            "name",
            "perhp",
            "perhpnosign",
            "curhpshort",
            "healthshort",
            "curmaxhp",
            "perhpnum",
            "both",
            "perpp",
            "curpp",
            "curmaxpp",
            "curhp_curpp",
            "perhp_perpp",
        }

        -- Class theme portrait icons: full-size versions of the sidebar class art.
        local ICONS_PATH = "Interface\\AddOns\\CludesUI\\media\\icons\\"
        local CLASS_FULL_SPRITE_BASE = ICONS_PATH .. "class-full\\"

        local CLASS_FULL_COORDS = CludesUI.CLASS_ICON_SPRITE_COORDS

        local classIconValues = {
            ["none"] = "None",
            ["modern"] = "Modern",
            ["arcade"] = "Arcade",
            ["glyph"] = "Glyph",
            ["legend"] = "Legend",
            ["midnight"] = "Midnight",
            ["pixel"] = "Pixel",
            ["pixelsComic"] = "Comic",
            ["runic"] = "Runic",
            _menuOpts = {
                itemHeight = 32,
                icon = function(key)
                    if key == "none" then
                        return nil
                    end
                    local _, ct = UnitClass("player")
                    if not ct then
                        return nil
                    end
                    local coords = CLASS_FULL_COORDS[ct]
                    if not coords then
                        return nil
                    end
                    return CLASS_FULL_SPRITE_BASE .. key .. ".tga", coords[1], coords[2], coords[3], coords[4]
                end,
            },
        }
        local classIconOrder = {
            "none",
            "---",
            "arcade",
            "glyph",
            "legend",
            "midnight",
            "modern",
            "pixel",
            "pixelsComic",
            "runic",
        }
        local classIconLocValues = { ["left"] = "Left", ["center"] = "Center", ["right"] = "Right" }
        local classIconLocOrder = { "left", "center", "right" }

        -- Buff and debuff stacks never share a spot. Moves one stack (changedKey
        -- "buffAnchor" or "debuffAnchor") to newVal; the other stack, when its
        -- stored spot is newVal, takes this stack's previous spot, or the first
        -- free corner when that spot is None or newVal itself. A hidden buff
        -- stack's stored corner counts both ways, so buffs turned back on by any
        -- path (a Spec Override, an import) never land on the debuffs. Buffs turn
        -- off through showBuffs (their corner is kept, never "none"); None never
        -- collides.
        local AURA_FREE_CORNERS = { "topleft", "bottomleft", "topright", "bottomright" }
        local function SwapAuraSlot(t, changedKey, newVal)
            local isBuff = (changedKey == "buffAnchor")
            local prev
            if isBuff then
                prev = t.buffAnchor or "topleft"
                if newVal == "none" then
                    t.showBuffs = false
                    return
                end
                t.showBuffs = true
            else
                prev = t.debuffAnchor or "bottomleft"
            end
            t[changedKey] = newVal
            if newVal == "none" then
                return
            end
            local other
            if isBuff then
                other = t.debuffAnchor or "bottomleft"
            else
                other = t.buffAnchor or "topleft"
            end
            if other ~= newVal then
                return
            end
            local dest = prev
            if dest == "none" or dest == newVal then
                for idx = 1, #AURA_FREE_CORNERS do
                    if AURA_FREE_CORNERS[idx] ~= newVal then
                        dest = AURA_FREE_CORNERS[idx]
                        break
                    end
                end
            end
            if isBuff then
                t.debuffAnchor = dest
            else
                t.buffAnchor = dest
            end
        end

        ---------------------------------------------------------------------------
        --  Preview builder: cosmetic health/power bar + portrait + castbar preview
        ---------------------------------------------------------------------------
        local PREVIEW_FONT = (CludesUI.GetFontPath("unitFrames"))
            or "Interface\\AddOns\\CludesUI\\media\\fonts\\Expressway.TTF"
        local SOLID_BACKDROP = { bgFile = "Interface\\Buttons\\WHITE8X8" }
        local BORDER_BACKDROP = { edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 }

        -- Generic portrait image for NPC previews (player uses SetPortraitTexture)

        -- Portrait mask/border media paths (for detached portrait shape preview)
        local PORTRAIT_MASKS_P = CludesUI.SHAPE_MASKS
        local PORTRAIT_BORDERS_P = CludesUI.SHAPE_BORDERS

        -- Top pixel inset for each mask shape (px from edge to visible portrait area)
        local MASK_INSETS = CludesUI.SHAPE_INSETS

        -- mirror = true swaps the cell's left/right coords (Mirror Portrait).
        local function ApplyClassIconTexture_Preview(texture, classToken, style, mirror)
            local coords = CLASS_FULL_COORDS[classToken]
            if not coords then
                return false
            end
            texture:SetTexture(CLASS_FULL_SPRITE_BASE .. style .. ".tga")
            if mirror then
                texture:SetTexCoord(coords[2], coords[1], coords[3], coords[4])
            else
                texture:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
            end
            return true
        end

        -- Apply detached portrait shape to preview portraitFrame pFrame; s = per-unit settings.
        local function ApplyPreviewPortraitShape(pFrame, s)
            if not pFrame then
                return
            end
            local isDetached = (s.portraitStyle or saved.profile.portraitStyle or "attached") == "detached"
            local shape = s.detachedPortraitShape or "portrait"
            local showBorder = true
            local borderOpacity = (s.detachedPortraitBorderOpacity or 100) / 100
            local borderColor = s.detachedPortraitBorderColor or { r = 0, g = 0, b = 0 }
            local useClassColor = s.detachedPortraitClassColor or false
            local rawBorderSize = s.detachedPortraitBorderSize or 7
            local bExp = 7 - rawBorderSize -- scale border UP; mask clips inner portion
            -- Use the resolved art mode so NPC fallbacks keep their own zoom.
            local classInset
            if pFrame._previewMode == "class" then
                local bh = pFrame:GetHeight()
                if bh < 1 then
                    bh = 46
                end
                classInset = math.floor(bh * 0.08)
            end

            local bR, bG, bB = borderColor.r, borderColor.g, borderColor.b
            if useClassColor then
                local _, ct = UnitClass("player")
                if ct then
                    local c = RAID_CLASS_COLORS[ct]
                    if c then
                        bR, bG, bB = c.r, c.g, c.b
                    end
                end
            end

            if pFrame._previewBg then
                local bgc = isDetached and s.detachedPortraitBgColor
                if bgc then
                    pFrame._previewBg:SetColorTexture(bgc.r, bgc.g, bgc.b, bgc.a or 1)
                else
                    pFrame._previewBg:SetColorTexture(0.082, 0.082, 0.082, 1)
                end
            end

            local texList = {}
            if pFrame._previewTex then
                table.insert(texList, pFrame._previewTex)
            end
            if pFrame._previewBg then
                table.insert(texList, pFrame._previewBg)
            end

            -- Remove mask when not detached
            if not isDetached then
                if pFrame._shapeMask then
                    for _, texture in ipairs(texList) do
                        texture:RemoveMaskTexture(pFrame._shapeMask)
                    end
                    pFrame._shapeMask:Hide()
                end
                if pFrame._shapeBorderTex then
                    pFrame._shapeBorderTex:Hide()
                end
                if pFrame._sqBorderTexs then
                    for _, t in ipairs(pFrame._sqBorderTexs) do
                        t:Hide()
                    end
                end
                -- Reset texture positions to default (detached mode expands them for mask fill)
                if pFrame._previewTex then
                    if classInset then
                        mod.UF_SetClassPortraitPoints(
                            pFrame._previewTex,
                            pFrame,
                            s.portraitClassZoom,
                            classInset,
                            classInset
                        )
                    else
                        pFrame._previewTex:ClearAllPoints()
                        pFrame._previewTex:SetPoint("TOPLEFT", pFrame, "TOPLEFT", 0, 0)
                        pFrame._previewTex:SetPoint("BOTTOMRIGHT", pFrame, "BOTTOMRIGHT", 0, 0)
                    end
                end
                if pFrame._previewModel then
                    pFrame._previewModel:ClearAllPoints()
                    pFrame._previewModel:SetPoint("TOPLEFT", pFrame, "TOPLEFT", 0, 0)
                    pFrame._previewModel:SetPoint("BOTTOMRIGHT", pFrame, "BOTTOMRIGHT", 0, 0)
                end
                mod.UF_PortraitExtras(pFrame, nil)
                return
            end

            -- === MASK ===
            if shape == "none" then
                -- "None": remove mask, border, and background
                if pFrame._previewBg then
                    pFrame._previewBg:Hide()
                end
                if pFrame._shapeMask then
                    for _, texture in ipairs(texList) do
                        pcall(texture.RemoveMaskTexture, texture, pFrame._shapeMask)
                    end
                    pFrame._shapeMask:Hide()
                end
                if pFrame._shapeBorderTex then
                    pFrame._shapeBorderTex:Hide()
                end
                if pFrame._sqBorderTexs then
                    for _, t in ipairs(pFrame._sqBorderTexs) do
                        t:Hide()
                    end
                end
                if pFrame._previewTex then
                    if classInset then
                        mod.UF_SetClassPortraitPoints(
                            pFrame._previewTex,
                            pFrame,
                            s.portraitClassZoom,
                            classInset,
                            classInset
                        )
                    else
                        pFrame._previewTex:ClearAllPoints()
                        pFrame._previewTex:SetPoint("TOPLEFT", pFrame, "TOPLEFT", 0, 0)
                        pFrame._previewTex:SetPoint("BOTTOMRIGHT", pFrame, "BOTTOMRIGHT", 0, 0)
                    end
                end
                if pFrame._previewModel then
                    pFrame._previewModel:ClearAllPoints()
                    pFrame._previewModel:SetPoint("TOPLEFT", pFrame, "TOPLEFT", 0, 0)
                    pFrame._previewModel:SetPoint("BOTTOMRIGHT", pFrame, "BOTTOMRIGHT", 0, 0)
                end
                mod.UF_PortraitExtras(pFrame, nil)
                return
            end
            if pFrame._previewBg then
                pFrame._previewBg:Show()
            end
            local maskPath = PORTRAIT_MASKS_P[shape]
            if maskPath then
                if not pFrame._shapeMask then
                    pFrame._shapeMask = pFrame:CreateMaskTexture()
                    pFrame._shapeMask:SetAllPoints(pFrame)
                end
                pFrame._shapeMask:SetTexture(maskPath, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                pFrame._shapeMask:Show()
                for _, texture in ipairs(texList) do
                    texture:AddMaskTexture(pFrame._shapeMask)
                end
            end

            -- Hide old square border textures if they exist on this frame
            if pFrame._sqBorderTexs then
                for _, t in ipairs(pFrame._sqBorderTexs) do
                    t:Hide()
                end
            end

            -- === TGA BORDER OVERLAY ===
            if not pFrame._shapeBorderTex then
                pFrame._shapeBorderTex = pFrame:CreateTexture(nil, "OVERLAY")
                if pFrame._shapeBorderTex.SetSnapToPixelGrid then
                    pFrame._shapeBorderTex:SetSnapToPixelGrid(false)
                    pFrame._shapeBorderTex:SetTexelSnappingBias(0)
                end
            end
            -- Pixels Circle (ns.UF_UNMASKED_RING) keeps its ring outside the mask,
            -- inset from the frame edge, exactly as on the live portrait.
            local ringInset = mod.UF_UNMASKED_RING[shape]
            local off = bExp - (ringInset or 0)
            pFrame._shapeBorderTex:ClearAllPoints()
            Pix.Point(pFrame._shapeBorderTex, "TOPLEFT", pFrame, "TOPLEFT", -off, off)
            Pix.Point(pFrame._shapeBorderTex, "BOTTOMRIGHT", pFrame, "BOTTOMRIGHT", off, -off)
            -- Add border to mask so the mask clips its inner edge
            if pFrame._shapeMask then
                pcall(pFrame._shapeBorderTex.RemoveMaskTexture, pFrame._shapeBorderTex, pFrame._shapeMask)
                if not ringInset then
                    pFrame._shapeBorderTex:AddMaskTexture(pFrame._shapeMask)
                end
            end
            if showBorder then
                local bp = PORTRAIT_BORDERS_P[shape]
                if bp then
                    pFrame._shapeBorderTex:SetTexture(bp)
                    pFrame._shapeBorderTex:SetVertexColor(bR, bG, bB, borderOpacity)
                    pFrame._shapeBorderTex:Show()
                else
                    pFrame._shapeBorderTex:Hide()
                end
            else
                pFrame._shapeBorderTex:Hide()
            end

            -- Scale portrait content so its visible area fills the mask opening;
            -- border size does not affect content.
            local insetPx = MASK_INSETS[shape] or 17
            local bw = pFrame:GetWidth()
            local bh2 = pFrame:GetHeight()
            if bw < 1 then
                bw = 46
            end
            if bh2 < 1 then
                bh2 = 46
            end
            local visRatio = (128 - 2 * insetPx) / 128
            local cScale = 1 / visRatio
            -- Apply user art scale (100 = default, stored as percentage)
            local artScale = (s.portraitArtScale or 100) / 100
            cScale = cScale * artScale
            local expand = (cScale - 1) * 0.5
            local oL = -(expand * bw)
            local oR = (expand * bw)
            local oT = (expand * bh2)
            local oB = -(expand * bh2)
            if pFrame._previewTex then
                if classInset then
                    mod.UF_SetClassPortraitPoints(
                        pFrame._previewTex,
                        pFrame,
                        s.portraitClassZoom,
                        classInset + oL,
                        classInset - oT
                    )
                else
                    pFrame._previewTex:ClearAllPoints()
                    Pix.Point(pFrame._previewTex, "TOPLEFT", pFrame, "TOPLEFT", oL, oT)
                    Pix.Point(pFrame._previewTex, "BOTTOMRIGHT", pFrame, "BOTTOMRIGHT", oR, oB)
                end
            end
            -- 3D Portrait Below Border: the model inside the ring and under it,
            -- as on the live portrait; off, it fills the frame over the ring.
            mod.UF_PortraitShapeModel(
                pFrame,
                pFrame._shapeBorderTex,
                pFrame._previewModel,
                pFrame._previewMode == "3d" and s.portrait3dBelowBorder == true,
                shape,
                rawBorderSize
            )

            -- Outer Ring / Inner Shadow: the live portrait's own helper. A shown
            -- Outer Ring and an unmasked ring below Size 7 reach past the frame,
            -- so the detached preview stops clipping (every layout branch of
            -- Update sets its clip again first; the Portrait Dragon lifts it on
            -- its own after this).
            mod.UF_PortraitExtras(pFrame, s, shape)
            if ringInset or (pFrame._outerRing and pFrame._outerRing:IsShown()) then
                pFrame:SetClipsChildren(false)
            end
        end

        -- Portrait art style dropdown values
        local classThemeSubValues = {
            ["modern"] = "Modern",
            ["arcade"] = "Arcade",
            ["glyph"] = "Glyph",
            ["legend"] = "Legend",
            ["midnight"] = "Midnight",
            ["pixel"] = "Pixel",
            ["pixelsComic"] = "Comic",
            ["runic"] = "Runic",
        }
        local classThemeSubOrder =
            { "modern", "arcade", "glyph", "legend", "midnight", "pixel", "pixelsComic", "runic" }
        local portraitArtValues = {
            ["3d"] = "3D Portrait",
            ["2d"] = "2D Portrait",
            ["class"] = {
                text = "Class",
                subnav = {
                    order = classThemeSubOrder,
                    values = classThemeSubValues,
                    onSelect = nil, -- wired per-unit below
                    icon = nil, -- wired per-unit below
                    itemHeight = 32,
                },
            },
        }
        local portraitArtOrder = { "3d", "2d", "class" }

        -- What a non-player shows on a Class art frame (class art is player-only).
        local portraitNonPlayerValues = {
            ["2d"] = "2D Portrait",
            ["none"] = "Nothing",
            ["3d"] = "3D Portrait",
        }
        local portraitNonPlayerOrder = { "2d", "none", "3d" }

        -- Portrait mode dropdown values; "none" hides the portrait entirely.
        local portraitModeValues2 = {
            ["none"] = "None",
            ["attached"] = "Attached",
            ["detached"] = "Detached",
        }
        local portraitModeOrder2 = { "none", "attached", "detached" }

        -- Detached portrait shape dropdown values
        local detPortraitShapeValues = {
            ["none"] = "None",
            ["portrait"] = "Portrait",
            ["circle"] = "Circle",
            ["pixelsCircle"] = "Pixels Circle",
            ["square"] = "Square",
            ["csquare"] = "Rounded Square",
            ["diamond"] = "Diamond",
            ["hexagon"] = "Hexagon",
            ["shield"] = "Shield",
        }
        local detPortraitShapeOrder = {
            "none",
            "portrait",
            "circle",
            "pixelsCircle",
            "square",
            "csquare",
            "diamond",
            "hexagon",
            "shield",
        }

        -- Text Bar position dropdown values
        local btbPositionValues = {
            ["top"] = "Top",
            ["bottom"] = "Bottom",
            ["detached_top"] = "Detached Top",
            ["detached_bottom"] = "Detached Bottom",
        }
        local btbPositionOrder = { "top", "bottom", "detached_top", "detached_bottom" }

        -- Enemy NPC names for preview (randomized on tab switch)
        local PREVIEW_ENEMY_NAMES = {
            "Doomguard",
            "Dreadlord",
            "Infernal",
            "Sea Giant",
            "Ogre Mage",
            "Satyr",
            "Stone Golem",
            "Water Elemental",
            "Silithid",
            "Naga Siren",
        }
        local PREVIEW_BOSS_NAMES = {
            "The Lich King",
            "Varimathras",
            "Cenarius",
            "Ragnaros",
            "Kel'Thuzad",
            "Archimonde",
            "Kil'jaeden",
            "Deathwing",
            "Yogg-Saron",
            "C'Thun",
        }
        -- Persistent random creature names per unit -- regenerated only on tab switch
        local _previewCreatureNames = {}

        -- Class cast spells for player preview (cast-time spells only; icons resolved
        -- at runtime via C_Spell.GetSpellInfo).
        local CLASS_CAST_SPELLS = {
            WARRIOR = { { name = "Slam", castTime = 1.5 }, { name = "Whirlwind", castTime = 1.5 } },
            PALADIN = {
                { name = "Flash of Light", castTime = 1.5 },
                { name = "Holy Light", castTime = 2.5 },
                { name = "Hammer of Wrath", castTime = 1.0 },
            },
            HUNTER = {
                { name = "Aimed Shot", castTime = 2.5 },
                { name = "Steady Shot", castTime = 1.8 },
                { name = "Cobra Shot", castTime = 2.0 },
            },
            ROGUE = { { name = "Kidney Shot", castTime = 1.5 } },
            PRIEST = {
                { name = "Flash Heal", castTime = 1.5 },
                { name = "Smite", castTime = 1.5 },
                { name = "Mind Blast", castTime = 1.5 },
                { name = "Greater Heal", castTime = 2.5 },
            },
            DEATHKNIGHT = {
                { name = "Death Coil", castTime = 1.5 },
                { name = "Howling Blast", castTime = 1.5 },
            },
            SHAMAN = {
                { name = "Lightning Bolt", castTime = 2.0 },
                { name = "Chain Lightning", castTime = 2.0 },
                { name = "Lava Burst", castTime = 2.0 },
                { name = "Healing Wave", castTime = 2.5 },
            },
            MAGE = {
                { name = "Fireball", castTime = 2.25 },
                { name = "Frostbolt", castTime = 2.0 },
                { name = "Arcane Blast", castTime = 2.25 },
                { name = "Pyroblast", castTime = 4.0 },
            },
            WARLOCK = {
                { name = "Shadow Bolt", castTime = 2.0 },
                { name = "Chaos Bolt", castTime = 3.0 },
                { name = "Incinerate", castTime = 2.0 },
            },
            MONK = { { name = "Vivify", castTime = 1.5 }, { name = "Spinning Crane Kick", castTime = 1.5 } },
            DRUID = {
                { name = "Wrath", castTime = 1.5 },
                { name = "Starfire", castTime = 2.25 },
                { name = "Regrowth", castTime = 1.5 },
                { name = "Healing Touch", castTime = 2.5 },
            },
            DEMONHUNTER = { { name = "Eye Beam", castTime = 2.0 } },
            EVOKER = {
                { name = "Fire Breath", castTime = 2.5 },
                { name = "Disintegrate", castTime = 3.0 },
                { name = "Living Flame", castTime = 1.5 },
                { name = "Eternity Surge", castTime = 2.5 },
            },
        }
        -- Fallback spells if class pool yields nothing with a cast time
        local FALLBACK_CAST_SPELLS = {
            { name = "Cosmic Hearthstone", spellID = 1242509, castTime = 5.0 },
            { name = "Teleport Home", spellID = 1233637, castTime = 10.0 },
        }
        -- Universal hearthstone spells added to every class pool
        local UNIVERSAL_CAST_SPELLS = {
            { name = "Cosmic Hearthstone", spellID = 1242509, castTime = 5.0 },
            { name = "Teleport Home", spellID = 1233637, castTime = 10.0 },
        }
        -- Returns icon fileID + castTime (seconds) from the API, so instant-cast
        -- spells never reach the preview.
        local function ResolveSpellInfo(spellNameOrID)
            local details = C_Spell.GetSpellInfo(spellNameOrID)
            if details then
                local icon = details.iconID or 136197
                local ct = (details.castTime or 0) / 1000 -- API returns ms
                return icon, ct
            end
            return 136197, 0
        end
        optionState._previewCastSpell = nil -- {icon, name, castTime} -- randomized on tab switch
        optionState._previewCastFill = nil -- 0.4 0.9 fill for the cast bar

        -- Class-specific common proc/buff icons for player preview (icon IDs)
        local CLASS_BUFF_ICONS = {
            WARRIOR = { 132404, 132352, 132333, 136012, 458972 },
            PALADIN = { 135964, 236254, 135993, 135920, 461860 },
            HUNTER = { 132242, 132176, 132312, 132329, 461846 },
            ROGUE = { 132290, 132350, 136206, 132301, 236279 },
            PRIEST = { 135936, 135987, 237548, 135940, 136207 },
            DEATHKNIGHT = { 237517, 135834, 135833, 237511, 135840 },
            SHAMAN = { 136048, 136052, 136042, 136044, 136053 },
            MAGE = { 135812, 135846, 135735, 135808, 236219 },
            WARLOCK = { 136197, 136145, 136188, 136169, 136162 },
            MONK = { 606551, 627606, 775461, 606543, 620827 },
            DRUID = { 136096, 136048, 136041, 136085, 136060 },
            DEMONHUNTER = { 1344649, 1247262, 1344650, 1344652, 1344651 },
            EVOKER = { 4622462, 4622460, 4622468, 4622464, 4622466 },
        }
        local FALLBACK_BUFF_ICONS = { 135932, 135981, 136075, 136205, 135987 }
        local _previewBuffIcons = {} -- 2 randomized buff icons for player preview

        optionState._previewHealthPct = 0.70 -- randomized health percentage for preview
        optionState._previewPowerPct = 0.85 -- randomized power percentage for preview

        local function RandomizePreviewCreatures()
            _previewCreatureNames.target = PREVIEW_ENEMY_NAMES[math.random(#PREVIEW_ENEMY_NAMES)]
            _previewCreatureNames.focus = PREVIEW_ENEMY_NAMES[math.random(#PREVIEW_ENEMY_NAMES)]
            _previewCreatureNames.pet = PREVIEW_ENEMY_NAMES[math.random(#PREVIEW_ENEMY_NAMES)]
            _previewCreatureNames.targettarget = PREVIEW_ENEMY_NAMES[math.random(#PREVIEW_ENEMY_NAMES)]
            _previewCreatureNames.focustarget = PREVIEW_ENEMY_NAMES[math.random(#PREVIEW_ENEMY_NAMES)]
            _previewCreatureNames.boss = PREVIEW_BOSS_NAMES[math.random(#PREVIEW_BOSS_NAMES)]
            -- Cast spell: class pool + universal hearthstones, cast time validated via API.
            local _, classToken = UnitClass("player")
            local classPool = CLASS_CAST_SPELLS[classToken] or {}
            local pool = {}
            for _, s in ipairs(classPool) do
                pool[#pool + 1] = s
            end
            for _, s in ipairs(UNIVERSAL_CAST_SPELLS) do
                pool[#pool + 1] = s
            end
            -- Shuffle pool (Fisher-Yates) then pick first spell with a real cast time
            for idx = #pool, 2, -1 do
                local jdx = math.random(idx)
                pool[idx], pool[jdx] = pool[jdx], pool[idx]
            end
            local chosen = nil
            for _, s in ipairs(pool) do
                local icon, ct = ResolveSpellInfo(s.spellID or s.name)
                if ct and ct > 0 then
                    chosen = { icon = icon, name = s.name, castTime = ct }
                    break
                end
            end
            -- No cast-time spell found: fall back to the first table entry.
            if not chosen then
                local fb = FALLBACK_CAST_SPELLS[1]
                chosen = { icon = 136197, name = fb.name, castTime = fb.castTime }
            end
            optionState._previewCastSpell = chosen
            optionState._previewCastFill = 0.40 + math.random() * 0.50
            optionState._previewHealthPct = 0.60 + math.random() * 0.30
            optionState._previewPowerPct = 0.50 + math.random() * 0.45
            -- Two distinct buff icons for the player preview.
            local buffPool = CLASS_BUFF_ICONS[classToken] or FALLBACK_BUFF_ICONS
            local i1 = math.random(#buffPool)
            local i2 = i1
            while i2 == i1 and #buffPool > 1 do
                i2 = math.random(#buffPool)
            end
            _previewBuffIcons[1] = buffPool[i1]
            _previewBuffIcons[2] = buffPool[i2]
        end

        -- Blizzard Style preview: the stock geometry the live layout pass uses
        -- (module table), resolved for this unit + Portrait Side exactly as
        -- ns.UF_BlizzResolve does it for the live frame. nil while the style is
        -- not active this session, and the preview then mocks the CUI look.
        local function ResolveBlizzPreview(unitKey, s)
            local BS = CludesUI.BlizzStyle
            if not (BS and BS.Get and BS.Get("unitframes")) then
                return nil
            end
            local UFB = mod.UF_BLIZZ
            if not (UFB and mod.UF_BlizzSide and mod.UF_PaintBlizzArt) then
                return nil
            end
            local kind
            if unitKey == "player" then
                kind = "player"
            elseif unitKey == "target" or unitKey == "focus" or unitKey == "boss" then
                kind = "target"
            elseif unitKey == "pet" and UFB.pet then
                kind = "pet"
            else
                kind = "mini"
            end
            local native = UFB[kind]
            local side = mod.UF_BlizzSide(s, native)
            local G, mirror = native, nil
            if native.small then
                if side ~= native.side then
                    mirror = true
                end
            elseif side == "right" then
                G = UFB.target
            else
                G = UFB.player
            end
            return G, mirror, (G.rep and kind == "target") or nil
        end
        -- Frame Scale (the style's stand-in for Bar Width / Health Bar Height).
        local function BlizzPreviewScale(s)
            local sc = s and s.blizzScale or 1
            if sc < 0.5 then
                sc = 0.5
            elseif sc > 2 then
                sc = 2
            end
            return sc
        end

        ---------------------------------------------------------------------------
        --  Page Builders
        ---------------------------------------------------------------------------

        -- Per-unit settings live in DISPLAY sections; positioning in Unlock Mode.

        ---------------------------------------------------------------------------
        --  MULTI FRAME EDIT TAB  (checkbox selector + shared per-unit settings)
        ---------------------------------------------------------------------------
        local function RegisterWidgetRefresh(func)
            if not CludesUI._widgetRefreshList then
                CludesUI._widgetRefreshList = {}
            end
            table.insert(CludesUI._widgetRefreshList, func)
        end

        -- Dark Mode flattens the health bar to a fixed dark color, so fill/background
        -- color settings do nothing: grey out and block the whole DualRow region (every
        -- swatch/slider/cog/sync in it). A widget-refresh callback tracks the toggle live
        -- (RefreshPage's fast path re-runs these without a full rebuild).
        local function AddDarkModeBlock(rgn, unitFn)
            if not rgn then
                return
            end
            local block = CreateFrame("Frame", nil, rgn)
            block:SetAllPoints()
            block:SetFrameLevel(rgn:GetFrameLevel() + 50)
            block:EnableMouse(true)
            block:SetScript("OnEnter", function()
                CludesUI.ShowWidgetTooltip(
                    block,
                    "Not available in Dark Mode. Dark Mode colors can be adjusted in Global Settings -> Colors."
                )
            end)
            block:SetScript("OnLeave", function()
                CludesUI.HideWidgetTooltip()
            end)
            local function Update()
                if mod.UF_DarkThemeOn(unitFn()) then
                    rgn:SetAlpha(0.3)
                    block:Show()
                else
                    rgn:SetAlpha(1)
                    block:Hide()
                end
            end
            Update()
            RegisterWidgetRefresh(Update)
        end

        ---------------------------------------------------------------------------
        --  Unified settings builder  (shared settings for the Main Frames page)
        ---------------------------------------------------------------------------
        local UNIT_SUPPORTS = {
            powerHeight = { player = true, target = true, focus = true },
            showPlayerAbsorb = { player = true, target = true, focus = true },
            absorbCleanAlpha = { player = true, target = true, focus = true },
            absorbOpacity = { player = true, target = true, focus = true },
            absorbColor = { player = true, target = true, focus = true },
            absorbEdgeMode = { player = true, target = true, focus = true },
            showOvershield = { player = true, target = true, focus = true },
            overshieldMode = { player = true, target = true, focus = true },
            absorbGlowLine = { player = true, target = true, focus = true },
            absorbGlowLineTexture = { player = true, target = true, focus = true },
            healAbsorbStyle = { player = true, target = true, focus = true },
            healAbsorbOpacity = { player = true, target = true, focus = true },
            healAbsorbColor = { player = true, target = true, focus = true },
            healAbsorbEdgeMode = { player = true, target = true, focus = true },
            healAbsorbBgOpacity = { player = true, target = true, focus = true },
            maxHealthStyle = { player = true, target = true, focus = true },
            maxHealthOpacity = { player = true, target = true, focus = true },
            maxHealthColor = { player = true, target = true, focus = true },
            maxHealthBgOpacity = { player = true, target = true, focus = true },
            healPrediction = { player = true, target = true, focus = true },
            healPredOpacity = { player = true, target = true, focus = true },
            healPredOverheal = { player = true, target = true, focus = true },
            healPredTexture = { player = true, target = true, focus = true },
            absorbBarPosition = { player = true, target = true, focus = true },
            absorbBarHeight = { player = true, target = true, focus = true },
            absorbBarColor = { player = true, target = true, focus = true },
            healAbsorbBarPosition = { player = true, target = true, focus = true },
            healAbsorbBarHeight = { player = true, target = true, focus = true },
            healAbsorbBarColor = { player = true, target = true, focus = true },
            showBuffs = { player = true, target = true, focus = true },
            combatIndicatorStyle = { player = true, target = true },
            combatIndicatorColor = { player = true, target = true },
            combatIndicatorCustomColor = { player = true, target = true },
            combatIndicatorPosition = { player = true, target = true },
            combatIndicatorSize = { player = true, target = true },
            combatIndicatorX = { player = true, target = true },
            combatIndicatorY = { player = true, target = true },
            leaderIndicatorEnabled = { player = true, target = true },
            leaderIndicatorSize = { player = true, target = true },
            leaderIndicatorPosition = { player = true, target = true },
            leaderIndicatorX = { player = true, target = true },
            leaderIndicatorY = { player = true, target = true },
            leaderIndicatorStyle = { player = true, target = true },
            eliteIndicatorEnabled = { target = true },
            eliteIndicatorSize = { target = true },
            eliteIndicatorPosition = { target = true },
            eliteIndicatorX = { target = true },
            eliteIndicatorY = { target = true },
            eliteIndicatorShowInInstances = { target = true },
            eliteIndicatorStyle = { target = true },
            factionIndicatorMode = { player = true, target = true },
            factionIndicatorStyle = { player = true, target = true },
            factionIndicatorPlayersOnly = { target = true },
            factionIndicatorPvP = { player = true, target = true },
            factionIndicatorSize = { player = true, target = true },
            factionIndicatorPosition = { player = true, target = true },
            factionIndicatorX = { player = true, target = true },
            factionIndicatorY = { player = true, target = true },
            buffAnchor = { player = true, target = true, focus = true },
            buffGrowth = { player = true, target = true, focus = true },
            maxBuffs = { player = true, target = true, focus = true },
            showPlayerCastbar = { player = true },
            showPlayerCastIcon = { player = true },
            playerCastbarIconInWidth = { player = true },
            playerCastbarHeight = { player = true },
            showCastbar = { target = true, focus = true },
            showCastIcon = { target = true, focus = true },
            castbarIconInWidth = { target = true, focus = true },
            castbarHeight = { target = true, focus = true },
            castbarHideWhenInactive = { player = true, target = true, focus = true },
            castSpellNameSize = { player = true, target = true, focus = true },
            castSpellNameColor = { player = true, target = true, focus = true },
            castDurationSize = { player = true, target = true, focus = true },
            castDurationColor = { player = true, target = true, focus = true },
            castSpellTargetSize = { player = true, target = true, focus = true },
            castSpellTargetColor = { player = true, target = true, focus = true },
            showCastDuration = { player = true, target = true, focus = true },
            showCastTarget = { player = true, target = true, focus = true },
            castSpellNameSide = { player = true, target = true, focus = true },
            castSpellTargetSide = { player = true, target = true, focus = true },
            castDurationSide = { player = true, target = true, focus = true },
            castbarFillColor = { player = true, target = true, focus = true },
            castbarInterruptReadyColor = { target = true, focus = true },
            castbarKickTickEnabled = { target = true, focus = true },
            castbarImportantGlow = { target = true, focus = true },
            castCombineNameTarget = { target = true, focus = true },
            castFullCraftTime = { player = true },
            castFitSpellName = { player = true, target = true, focus = true },
            showClassPowerBar = { player = true },
            lockClassPowerToFrame = { player = true },
            classPowerStyle = { player = true },
            classPowerPosition = { player = true },
            classPowerBarX = { player = true },
            classPowerBarY = { player = true },
            classPowerSize = { player = true },
            classPowerSpacing = { player = true },
            classPowerClassColor = { player = true },
            classPowerCustomColor = { player = true },
            classPowerBgColor = { player = true },
            classPowerEmptyColor = { player = true },
            foreverComboLocation = { player = true },
            showInRaid = { player = true, target = true, focus = true },
            showInParty = { player = true, target = true, focus = true },
            showSolo = { player = true, target = true, focus = true },
        }
        local UNIT_LABELS_SUP = { player = "Player", target = "Target", focus = "Focus" }

        -- Shown in place of a unit's settings when it isn't on the CludesUI frame
        -- (Blizzard default / hidden); the inapplicable controls are never built.
        -- Returns the new y.
        local function BuildInactiveNotice(hostFrame, posY, source)
            local CPAD = CludesUI.CONTENT_PAD or 10
            local note = CludesUI.MakeFont(hostFrame, 13, nil, 1, 1, 1)
            note:SetTextColor(1, 1, 1, 0.55)
            note:SetPoint("TOPLEFT", hostFrame, "TOPLEFT", CPAD + 4, posY - 18)
            note:SetPoint("TOPRIGHT", hostFrame, "TOPRIGHT", -(CPAD + 4), posY - 18)
            note:SetJustifyH("LEFT")
            note:SetText(
                source == "blizzard"
                        and CludesUI.L(
                            "This unit uses the Blizzard default frame -- there are no CludesUI settings to configure here."
                        )
                    or CludesUI.L(
                        "This unit's frame is hidden -- there are no CludesUI settings to configure here."
                    )
            )
            return posY - 54
        end

        -- A unit whose source was Blizzard/Hidden at login has no spawned CUI frame this
        -- session (and Blizzard's frame can't be torn down live), so a visibility/enable
        -- change can't apply live -- prompt for a /reload. unitKeys: "boss" checks boss1.
        local function PromptReloadIfUnspawned(unitKeys)
            local f = mod.frames
            if not f then
                return
            end
            local missing = false
            for _, u in ipairs(unitKeys) do
                local spawned = (u == "boss") and f.boss1 or f[u]
                if not spawned then
                    missing = true
                    break
                end
            end
            if not missing then
                return
            end
            CludesUI:ShowConfirmPopup({
                title = "Reload Required",
                message = "This frame's source changes require a UI reload to take effect.",
                confirmText = "Reload Now",
                cancelText = "Later",
                reload = true,
            })
        end

        -- Inline "Frame Source" cog next to a unit's Visibility dropdown / Enable
        -- toggle: one dropdown, CludesUI (our skinned frame) or Blizzard Default
        -- (leave Blizzard's frame alone). Hiding stays on the host widget ("Never
        -- Show" / Enable), so "Hidden" is not duplicated; the stored style survives
        -- hiding and resumes on re-enable. opts: tooltip, disabled/disabledTooltip
        -- (ToT/FoT parent gating), onBeforeSet(v) (boss stops its live preview).
        local function AttachFrameSourceCog(rgn, unitKey, options)
            options = options or {}
            local function StoredStyle()
                local fontStr = saved.profile.frameSource and saved.profile.frameSource[unitKey]
                return fontStr == "blizzard" and "blizzard" or "cui"
            end
            local fsShow -- forward decl: set() below closes the popup through it
            local _
            local rowList = {
                {
                    type = "dropdown",
                    label = "Frame Source",
                    values = { cui = "CludesUI", blizzard = "Blizzard Default" },
                    order = { "cui", "blizzard" },
                    tooltip = options.tooltip,
                    disabled = options.disabled,
                    disabledTooltip = options.disabledTooltip,
                    get = StoredStyle,
                    set = function(v)
                        if v == StoredStyle() then
                            return
                        end
                        if options.onBeforeSet then
                            options.onBeforeSet(v)
                        end
                        -- Also re-enables a hidden frame (see ns.SetUnitFrameSource).
                        mod.SetUnitFrameSource(unitKey, v)
                        if mod.UpdateFrameVisibility then
                            mod.UpdateFrameVisibility()
                        end
                        ReloadAndUpdate()
                        CludesUI:RefreshPage(true)
                        -- Close the cog popup before the reload prompt: the page under
                        -- it was just rebuilt, so it would float stale rows behind the dialog.
                        -- (The popup is kept by its cog button, not built by the page: the
                        -- rebuild leaves it showing where it was, for this Hide.)
                        if fsShow and fsShow._popupFrame and fsShow._popupFrame:IsShown() then
                            fsShow._popupFrame:Hide()
                        end
                        CludesUI:ShowConfirmPopup({
                            title = "Reload Required",
                            message = "Changing the frame source requires a UI reload to take effect.",
                            confirmText = "Reload Now",
                            cancelText = "Later",
                            reload = true,
                        })
                    end,
                },
            }
            -- Callers can fold extra rows into the same popup (the Visibility row hosts
            -- the Out of Combat fade, so it carries ONE cog instead of two).
            if options.extraRows then
                for _, r in ipairs(options.extraRows) do
                    rowList[#rowList + 1] = r
                end
            end
            _, fsShow = CludesUI.BuildInlineCog(rgn, {
                title = options.title or "Frame Source",
                bgAlpha = 1,
                frameStrata = "FULLSCREEN_DIALOG",
                frameLevel = 500,
                rows = rowList,
                tip = CludesUI.L(options.cogTooltip or "Frame Source"),
            })
        end

        ---------------------------------------------------------------------------
        --  "Apply All Settings From" -- bulk copy between frames of the same group
        ---------------------------------------------------------------------------
        -- Copies every group-shared setting (UNION of source+dest keys, so dest-only
        -- overrides get cleared) from the CHOSEN unit onto the frame whose page the
        -- row sits on. A key is shared unless
        -- UNIT_SUPPORTS restricts it or it's absent from some group units' defaults.
        -- Positions/enable state (db.profile.positions/enabledFrames) are never touched.
        -- Exception: target<->focus copies check sharedness against just that pair, so
        -- their shared cast bar section (which player lacks) transfers; player copies use
        -- the full-group rule, so cast bar settings never cross to/from player.
        local MINI_GROUP_ORDER = { "targettarget", "focustarget", "pet" }
        local TARGET_FOCUS_PAIR = { "target", "focus" }
        local function IsGroupSharedKey(key, groupUnits)
            -- Visibility mode stays with the frame: it pairs with enabledFrames (never
            -- copied) and copying one alone desyncs them. Underscore keys are runtime
            -- memos (e.g. _preHiddenBarVisibility), not settings.
            if type(key) ~= "string" then
                return false
            end
            -- visibilityMatch only modifies barVisibility's selection, so it has to stay
            -- with the frame for the same reason: copying the modifier to a frame that kept
            -- its own mode changes how that mode reads.
            if key == "barVisibility" or key == "visibilityMatch" or key:sub(1, 1) == "_" then
                return false
            end
            -- WoW Forever: the pet's power bar position has no counterpart on the
            -- other small frames (theirs never shows), so it stays with the pet.
            if key == "powerPosition" and mod.UF_PetHasPower and groupUnits == MINI_GROUP_ORDER then
                return false
            end
            -- The pet's buffs and debuffs stay with the pet: the other small frames
            -- have none, so a copy either way would only clear or plant aura keys.
            if
                groupUnits == MINI_GROUP_ORDER
                and (
                    key:find("^buff")
                    or key:find("^debuff")
                    or key == "showBuffs"
                    or key == "maxBuffs"
                    or key == "maxDebuffs"
                    or key == "auraSource"
                )
            then
                return false
            end
            local sup = UNIT_SUPPORTS[key]
            if sup then
                for _, u in ipairs(groupUnits) do
                    if not sup[u] then
                        return false
                    end
                end
            end
            local defs = saved._profileDefaults or {}
            local inAny, inAll = false, true
            for _, u in ipairs(groupUnits) do
                local d = defs[u]
                if d and d[key] ~= nil then
                    inAny = true
                else
                    inAll = false
                end
            end
            if inAny and not inAll then
                return false
            end
            return true
        end
        local function CopyAllGroupSettings(srcUnit, dstUnit, groupUnits)
            if
                (srcUnit == "target" or srcUnit == "focus")
                and (dstUnit == "target" or dstUnit == "focus")
            then
                groupUnits = TARGET_FOCUS_PAIR
            end
            local source = UNIT_DB_MAP[srcUnit]()
            local dst = UNIT_DB_MAP[dstUnit]()
            -- A target on the old "wingless" Elite/Rare style shows its dragon
            -- through a view (ns.UF_DragonLegacy) over target-only keys this copy
            -- never moves: pin both tables onto the dragon's own keys first.
            mod.UF_PinLegacyDragon(source)
            mod.UF_PinLegacyDragon(dst)
            local keyList = {}
            for k in pairs(source) do
                keyList[k] = true
            end
            for k in pairs(dst) do
                keyList[k] = true
            end
            for k in pairs(keyList) do
                if IsGroupSharedKey(k, groupUnits) then
                    local v = source[k]
                    if type(v) == "table" then
                        dst[k] = CludesUI.Lite.DeepCopy(v)
                    else
                        dst[k] = v
                    end
                end
            end
            ReloadAndUpdate()
            CludesUI:RefreshPage(true)
        end
        -- "Copy Look From" (a mini frame's, beside its Apply All Settings From): the
        -- main frame it copies its border, bar texture and hover highlight from.
        -- The dropdown shows the frame in use, from the runtime's own pick (the
        -- chosen frame while it can lend its look, else focus, then target, then
        -- player). No choice (lookSource nil) keeps following that order:
        -- re-picking the frame shown stores nothing, and Focus, which behaves
        -- exactly as no choice, is stored as none.
        local function BuildLookSourcePair(row, unitKey, ddW)
            local function Shown()
                return mod.UF_MiniDonorKey(unitKey)
            end
            local ddBtn = CludesUI.BuildDropdownControl(
                row,
                ddW,
                row:GetFrameLevel() + 2,
                { target = "Target", focus = "Focus", player = "Player" },
                { "target", "focus", "player" },
                Shown,
                function(v)
                    if v == Shown() then
                        return
                    end
                    saved.profile[unitKey].lookSource = (v ~= "focus") and v or nil
                    ReloadAndUpdate()
                    CludesUI:RefreshPage(true)
                end
            )
            ddBtn._ttText =
                "The main frame this frame copies its border, bar texture and hover highlight from."
            CludesUI.RegisterWidgetRefresh(function()
                ddBtn._refreshLabel()
            end)

            local labelText = CludesUI.MakeFont(row, 14, nil, 1, 1, 1)
            labelText:SetText(CludesUI.L("Copy Look From"))
            labelText:SetTextColor(1, 1, 1, 0.6)
            return labelText, ddBtn
        end

        -- Centered label + action dropdown atop a unit's settings: lists the group's
        -- other frames and copies FROM the chosen one onto this frame after a
        -- confirm popup. getValue always returns the placeholder so the dropdown
        -- stores nothing; the registered widget refresh snaps the label back after
        -- each pick.
        --
        -- The FIRST use asks the user to type Confirm: this control used to copy
        -- the OTHER way (onto the chosen frame), and the flipped direction has to
        -- be acknowledged once before it overwrites anything. The acknowledgment
        -- is account-wide (CludesUIDB root, not per-profile) and covers every
        -- frame's row -- it educates the user, not a profile.
        --
        -- withLook (the mini frames) puts the frame's Copy Look From pair beside it,
        -- the two pairs centred as one line.
        local function BuildApplyAllRow(hostFrame, posY, groupUnits, curUnit, withLook)
            local ddValues = { [""] = "Choose Frame..." }
            local ddOrder = {}
            for _, key in ipairs(groupUnits) do
                if key ~= curUnit then
                    ddValues[key] = SHORT_LABELS[key] or key
                    ddOrder[#ddOrder + 1] = key
                end
            end

            local ROW_H = 50
            local contentPad = CludesUI.CONTENT_PAD or 45
            local row = CreateFrame("Frame", nil, hostFrame)
            Pix.Size(row, hostFrame:GetWidth() - contentPad * 2, ROW_H)
            Pix.Point(row, "TOPLEFT", hostFrame, "TOPLEFT", contentPad, posY)

            local labelText = CludesUI.MakeFont(row, 14, nil, 1, 1, 1)
            labelText:SetText(CludesUI.L("Apply All Settings From"))
            labelText:SetTextColor(1, 1, 1, 0.6)

            local DD_W, GAP, PAIR_GAP = 180, 12, 40
            local ddBtn = CludesUI.BuildDropdownControl(
                row,
                DD_W,
                row:GetFrameLevel() + 2,
                ddValues,
                ddOrder,
                function()
                    return ""
                end,
                function(srcUnit)
                    if srcUnit == "" then
                        return
                    end
                    local srcLabel = SHORT_LABELS[srcUnit] or srcUnit
                    local curLabel = SHORT_LABELS[curUnit] or curUnit
                    local acked = CludesUIDB and CludesUIDB.ufApplyFromAck
                    CludesUI:ShowConfirmPopup({
                        title = "Apply All Settings",
                        message = acked
                                and CludesUI.Lf(
                                    "Copy all shared settings from %1$s to %2$s?",
                                    srcLabel,
                                    curLabel
                                )
                            or CludesUI.Lf(
                                "This control recently changed direction: it now copies FROM the frame you choose. Confirming will copy all shared settings FROM %1$s TO %2$s.",
                                srcLabel,
                                curLabel
                            ),
                        disclaimer = "This overwrites this frame's current settings. Frame position, visibility, and enable state are not changed.",
                        confirmText = "Apply",
                        cancelText = "Cancel",
                        typeToConfirm = (not acked) and "Confirm" or nil,
                        onConfirm = function()
                            if CludesUIDB then
                                CludesUIDB.ufApplyFromAck = true
                            end
                            CopyAllGroupSettings(srcUnit, curUnit, groupUnits)
                        end,
                    })
                end
            )
            ddBtn._ttText = "Copy every shared setting from another frame in this group to this frame."
            CludesUI.RegisterWidgetRefresh(function()
                ddBtn._refreshLabel()
            end)

            -- Center the label + dropdown pair (both pairs with withLook) as one line
            local totalW = labelText:GetStringWidth() + GAP + DD_W
            local lookLabel, lookDD
            if withLook then
                lookLabel, lookDD = BuildLookSourcePair(row, curUnit, DD_W)
                totalW = totalW + PAIR_GAP + lookLabel:GetStringWidth() + GAP + DD_W
            end
            labelText:SetPoint("LEFT", row, "CENTER", -totalW / 2, 0)
            ddBtn:SetPoint("LEFT", labelText, "RIGHT", GAP, 0)
            if lookLabel then
                lookLabel:SetPoint("LEFT", ddBtn, "RIGHT", PAIR_GAP, 0)
                lookDD:SetPoint("LEFT", lookLabel, "RIGHT", GAP, 0)
            end

            return row, ROW_H
        end

        local function BuildSharedSettings(hostFrame, posY)
            local W = CludesUI.Widgets
            local _, hgt
            local row

            ---------------------------------------------------------------
            --  Unified Get / Set / DB abstraction
            ---------------------------------------------------------------
            local function SGet(key)
                return UNIT_DB_MAP[optionState.selectedUnit]()[key]
            end
            local function SSet(key, val)
                UNIT_DB_MAP[optionState.selectedUnit]()[key] = val
                ReloadAndUpdate()
            end
            local function SDB()
                return UNIT_DB_MAP[optionState.selectedUnit]()
            end
            local function SVal(key, default)
                local v = UNIT_DB_MAP[optionState.selectedUnit]()[key]
                if v ~= nil then
                    return v
                end
                return default
            end
            -- Set that also writes to the current unit (for UNIT_SUPPORTS keys)
            local function SSetSupported(key, val)
                UNIT_DB_MAP[optionState.selectedUnit]()[key] = val
                ReloadAndUpdate()
                UpdatePreview()
            end
            local function SGetSupported(key)
                return UNIT_DB_MAP[optionState.selectedUnit]()[key]
            end
            local function SValSupported(key, default)
                local v = UNIT_DB_MAP[optionState.selectedUnit]()[key]
                if v == nil then
                    return default
                end
                return v
            end
            -- Check if current unit supports a setting
            local function SVisible(key)
                local sup = UNIT_SUPPORTS[key]
                if not sup then
                    return true
                end
                return sup[optionState.selectedUnit] == true
            end
            -- Dim a row region and add a tooltip when the current unit doesn't support
            -- the key; unsupportedTip (optional) shows over the dimmed row.
            local function SApplySupport(regionFrame, key, unsupportedTip)
                local visible = SVisible(key)
                if not visible then
                    regionFrame:SetAlpha(0.35)
                    if regionFrame._control and regionFrame._control.Disable then
                        regionFrame._control:Disable()
                    end
                end
                local tipText = not visible and unsupportedTip or nil
                if tipText then
                    local function MakeSupportHit(anchor)
                        if not anchor then
                            return
                        end
                        local hitFrame = CreateFrame("Frame", nil, regionFrame)
                        hitFrame:SetPoint("TOPLEFT", anchor, "TOPLEFT", -5, 5)
                        hitFrame:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 5, -5)
                        hitFrame:SetFrameLevel(regionFrame:GetFrameLevel() + 10)
                        hitFrame:EnableMouse(true)
                        hitFrame:SetScript("OnEnter", function()
                            CludesUI.ShowWidgetTooltip(anchor, tipText)
                        end)
                        hitFrame:SetScript("OnLeave", function()
                            CludesUI.HideWidgetTooltip()
                        end)
                        securecallfunction(
                            hitFrame.SetPassThroughButtons,
                            hitFrame,
                            "LeftButton",
                            "RightButton"
                        )
                    end
                    MakeSupportHit(regionFrame._label)
                    MakeSupportHit(regionFrame._control)
                end
            end

            hostFrame._showRowDivider = true

            row, hgt = BuildApplyAllRow(hostFrame, posY, GROUP_UNIT_ORDER, optionState.selectedUnit)
            posY = posY - hgt

            -- The sections live in UnitFrames_Options\Shared*_Options.lua and read
            -- this page's accessors through ctx. Each returns the new y plus the rows
            -- the click mapping below points at; Display returns true second when
            -- the unit has no CUI frame (only the inactive notice is built).
            local context = {
                W = W,
                SGet = SGet,
                SSet = SSet,
                SDB = SDB,
                SVal = SVal,
                SSetSupported = SSetSupported,
                SGetSupported = SGetSupported,
                SValSupported = SValSupported,
                SVisible = SVisible,
                SApplySupport = SApplySupport,
            }
            local inactive
            posY, inactive = mod.UFO_BuildDisplaySection(hostFrame, posY, context)
            if inactive then
                return posY
            end
            local sharedPortraitHeader, sharedPortraitModeRow
            posY, sharedPortraitHeader, sharedPortraitModeRow =
                mod.UFO_BuildPortraitSection(hostFrame, posY, context)
            local sharedBarsHeader, sharedScaleRow, sharedSizeRow, sharedTextRow, sharedCenterTextRow
            posY, sharedBarsHeader, sharedScaleRow, sharedSizeRow, sharedTextRow, sharedCenterTextRow =
                mod.UFO_BuildHealthBarSection(hostFrame, posY, context)
            local sharedPowerHeader, sharedPowerRow1, sharedPowerRow2
            posY, sharedPowerHeader, sharedPowerRow1, sharedPowerRow2 =
                mod.UFO_BuildPowerBarSection(hostFrame, posY, context)
            local sharedCastHeader, sharedCastRow1, castRow2, castTextRow, castTargetRow
            posY, sharedCastHeader, sharedCastRow1, castRow2, castTextRow, castTargetRow =
                mod.UFO_BuildCastBarSection(hostFrame, posY, context)
            local sharedBtbHeader, sharedBtbToggleRow, sharedBtbTextRow, sharedBtbCenterRow
            posY, sharedBtbHeader, sharedBtbToggleRow, sharedBtbTextRow, sharedBtbCenterRow =
                mod.UFO_BuildTextBarSection(hostFrame, posY, context)
            local sharedClassResHeader, sharedClassResRow
            posY, sharedClassResHeader, sharedClassResRow =
                mod.UFO_BuildClassResourceSection(hostFrame, posY, context)
            local sharedBuffDebuffHeader, sharedAddRow2, sharedAddRow3
            posY, sharedBuffDebuffHeader, sharedAddRow2, sharedAddRow3 =
                mod.UFO_BuildBuffsDebuffsSection(hostFrame, posY, context)
            local sharedAbsorbsHeader, absorbRow, healAbsorbRow
            posY, sharedAbsorbsHeader, absorbRow, healAbsorbRow =
                mod.UFO_BuildAbsorbsHealsSection(hostFrame, posY, context)
            local sharedAddHeader, sharedAddRow1, sharedAddRow4, sharedAddRow5
            posY, sharedAddHeader, sharedAddRow1, sharedAddRow4, sharedAddRow5 =
                mod.UFO_BuildExtrasSection(hostFrame, posY, context)

            -------------------------------------------------------------------
            --  Return click mapping targets + total height
            -------------------------------------------------------------------
            hostFrame._sharedClickTargets = {
                healthBar = { section = sharedBarsHeader, target = sharedScaleRow or sharedSizeRow },
                absorbs = { section = sharedAbsorbsHeader, target = absorbRow, slotSide = "left" },
                healAbsorb = { section = sharedAbsorbsHeader, target = healAbsorbRow, slotSide = "left" },
                powerBar = { section = sharedPowerHeader, target = sharedPowerRow1, slotSide = "left" },
                powerBarText = { section = sharedPowerHeader, target = sharedPowerRow2, slotSide = "left" },
                portrait = {
                    section = sharedPortraitHeader,
                    target = sharedPortraitModeRow,
                    slotSide = "left",
                },
                nameText = mod.UFO_TextClickTarget(hostFrame, "leftText", sharedBarsHeader, sharedTextRow),
                healthText = mod.UFO_TextClickTarget(hostFrame, "rightText", sharedBarsHeader, sharedTextRow),
                centerText = mod.UFO_TextClickTarget(
                    hostFrame,
                    "centerText",
                    sharedBarsHeader,
                    sharedTextRow
                ),
                extraText = mod.UFO_TextClickTarget(hostFrame, "extraText", sharedBarsHeader, sharedTextRow),
                classResource = {
                    section = sharedClassResHeader,
                    target = sharedClassResRow,
                    slotSide = "left",
                },
                btbBar = { section = sharedBtbHeader, target = sharedBtbToggleRow, slotSide = "left" },
                btbLeftText = { section = sharedBtbHeader, target = sharedBtbTextRow, slotSide = "left" },
                btbRightText = {
                    section = sharedBtbHeader,
                    target = sharedBtbTextRow,
                    slotSide = "right",
                },
                btbCenterText = {
                    section = sharedBtbHeader,
                    target = sharedBtbCenterRow,
                    slotSide = "left",
                },
                btbClassIcon = {
                    section = sharedBtbHeader,
                    target = sharedBtbCenterRow,
                    slotSide = "right",
                },
                combatIndicator = { section = sharedAddHeader, target = sharedAddRow1, slotSide = "left" },
                buffIcon = { section = sharedBuffDebuffHeader, target = sharedAddRow2, slotSide = "left" },
                debuffIcon = { section = sharedBuffDebuffHeader, target = sharedAddRow3, slotSide = "left" },
                raidMarker = { section = sharedAddHeader, target = sharedAddRow4, slotSide = "left" },
                leaderIndicator = { section = sharedAddHeader, target = sharedAddRow5, slotSide = "left" },
                castBar = { section = sharedCastHeader, target = sharedCastRow1 },
                castIcon = { section = sharedCastHeader, target = castRow2, slotSide = "left" },
                castName = { section = sharedCastHeader, target = castTextRow, slotSide = "left" },
                castTime = { section = sharedCastHeader, target = castTextRow, slotSide = "right" },
                castTarget = { section = sharedCastHeader, target = castTargetRow, slotSide = "left" },
                -- Blizzard Style level number -> Show Level (+ its cog).
                levelText = { section = sharedBarsHeader, target = hostFrame._ufLevelRow, slotSide = "left" },
            }
            -- Rows that exist only for some frames (Elite/Rare: target; Faction: player + target).
            if optionState.selectedUnit == "target" and hostFrame._ufEliteRow then
                hostFrame._sharedClickTargets.eliteIndicator =
                    { section = sharedAddHeader, target = hostFrame._ufEliteRow, slotSide = "left" }
            end
            if
                (optionState.selectedUnit == "player" or optionState.selectedUnit == "target")
                and hostFrame._ufFactionRow
            then
                hostFrame._sharedClickTargets.factionIndicator =
                    { section = sharedAddHeader, target = hostFrame._ufFactionRow, slotSide = "left" }
            end

            return posY
        end -- BuildSharedSettings

        ---------------------------------------------------------------------------
        --  Main Frames page  (dropdown selector + shared/mini settings)
        ---------------------------------------------------------------------------
        local _displayHeaderBuilder
        local displayHeaderFixedH = 0

        local function BuildFrameDisplayPage(pageName, hostFrame, yOffset)
            -- Consume any pending unit selection from Element Options navigation
            if CludesUI._consumePendingUnitSelect then
                CludesUI._consumePendingUnitSelect()
            end

            -- Tag every option built on this page with the selected unit, so a global-
            -- search jump to a unit-specific setting can restore this unit first via
            -- CludesUI._setUnitFrameUnit (see the matching CludesUI._buildingSelector
            -- comment in CUI_CooldownManager_Options.lua for the full reasoning).
            CludesUI._buildingSelector =
                { setter = CludesUI._setUnitFrameUnit, key = optionState.selectedUnit }

            local W = CludesUI.Widgets
            local posY = yOffset
            local _, hgt

            activePreview = nil

            -------------------------------------------------------------------
            --  CONTENT HEADER  (dropdown + preview)
            -------------------------------------------------------------------
            _displayHeaderBuilder = function(heading, hdrW)
                local DD_H = 34
                local fy = -20

                -- Centered dropdown (matches Action Bars Single Bar Edit)
                local ddW = 350
                local ddBtn, ddLbl = CludesUI.BuildDropdownControl(
                    heading,
                    ddW,
                    heading:GetFrameLevel() + 5,
                    unitLabels,
                    unitOrder,
                    function()
                        return optionState.selectedUnit
                    end,
                    function(v)
                        -- Preserve scroll position across the unit swap; capture BEFORE the
                        -- rebuild since the header relayout can clobber the live value.
                        -- Settings sit below the fixed header, so the same offset lands on the same section for any unit.
                        local savedScroll = CludesUI.GetContentScroll and CludesUI.GetContentScroll() or 0
                        optionState.selectedUnit = v
                        -- One pass builds the page and its header together (buildPage
                        -- sets the header for the new unit).
                        CludesUI:RefreshPage(true)
                        CludesUI.SmoothScrollTo(savedScroll)
                        -- Preview:Update() runs DURING the rebuild above, before the header
                        -- layout settles, so its sizing pass lands on stale geometry (spacing
                        -- wrong, debuff row missing until a slider nudge). Initial page load
                        -- gets a settled pass via RegisterOnShow; a unit switch does not, so re-run the preview next frame once layout has settled.
                        C_Timer.After(0, UpdatePreview)
                    end
                )
                Pix.Point(ddBtn, "TOP", heading, "TOP", 0, fy)
                ddBtn:SetHeight(DD_H)
                fy = fy - DD_H - 20

                local side = unitSide[optionState.selectedUnit] or "left"
                local preview = mod.UFO_BuildUnitPreview(heading, optionState.selectedUnit, side)
                activePreview = preview
                local previewScale = preview._previewScale or 1
                local initBuffTopPad = preview._buffTopPad or 0
                preview._headerDropdownOY = math.abs(fy)
                preview:ClearAllPoints()
                Pix.Point(preview, "TOP", heading, "TOP", 0, (fy - initBuffTopPad) / previewScale)
                preview._lastOY = (fy - initBuffTopPad) / previewScale
                preview:Update()
                local previewH = preview:GetHeight() * preview:GetScale()
                local buffExtra = preview._buffExtra or 0
                local detTopExtra = preview._detTopExtra or 0
                fy = fy - previewH - buffExtra - detTopExtra - 20

                displayHeaderFixedH = 20 + DD_H + 20 + 20
                if preview then
                    preview._headerFixedH = displayHeaderFixedH
                end

                -- Hint text
                if
                    optionState._ufPreviewHintFS_display
                    and not optionState._ufPreviewHintFS_display:GetParent()
                then
                    optionState._ufPreviewHintFS_display = nil
                end
                local hintH = 0
                if not IsPreviewHintDismissed() then
                    if not optionState._ufPreviewHintFS_display then
                        -- Held across builds by optState: it leaves the preview's
                        -- region pool (Pool.Keep), so no later build hands it out
                        -- for another text; it is still hidden at its host's reset.
                        optionState._ufPreviewHintFS_display =
                            PoolKeep(CludesUI.MakeFont(preview or heading, 11, nil, 1, 1, 1))
                        optionState._ufPreviewHintFS_display:SetAlpha(0.45)
                        optionState._ufPreviewHintFS_display:SetText(
                            CludesUI.L("Click elements to scroll to and highlight their options")
                        )
                    end
                    optionState._ufPreviewHintFS_display:SetParent(preview or heading)
                    optionState._ufPreviewHintFS_display:ClearAllPoints()
                    optionState._ufPreviewHintFS_display:SetPoint("BOTTOM", heading, "BOTTOM", 0, 17)
                    optionState._ufPreviewHintFS_display:SetAlpha(0.45)
                    optionState._ufPreviewHintFS_display:Show()
                    hintH = 29
                elseif optionState._ufPreviewHintFS_display then
                    optionState._ufPreviewHintFS_display:Hide()
                end

                _displayHeaderBaseH = math.abs(fy)
                return _displayHeaderBaseH + hintH
            end
            CludesUI:SetContentHeader(_displayHeaderBuilder)

            hostFrame._showRowDivider = true

            -------------------------------------------------------------------
            --  Route to shared settings or mini builders
            -------------------------------------------------------------------
            if
                optionState.selectedUnit == "player"
                or optionState.selectedUnit == "target"
                or optionState.selectedUnit == "focus"
            then
                posY = BuildSharedSettings(hostFrame, posY)
            elseif optionState.selectedUnit == "targettarget" then
                posY = -mod.UFO_BuildFoTToTOptions(
                    W,
                    hostFrame,
                    posY,
                    saved.profile.targettarget,
                    "targettarget"
                )
            elseif optionState.selectedUnit == "focustarget" then
                posY =
                    -mod.UFO_BuildFoTToTOptions(W, hostFrame, posY, saved.profile.focustarget, "focustarget")
            elseif optionState.selectedUnit == "pet" then
                posY = -mod.UFO_BuildPetOptions(W, hostFrame, posY)
            elseif optionState.selectedUnit == "boss" then
                posY = -mod.UFO_BuildBossOptions(W, hostFrame, posY)
            end

            -------------------------------------------------------------------
            --  CLICK NAVIGATION
            -------------------------------------------------------------------
            local PlaySettingGlow = CludesUI.MakeSettingGlow({ color = CludesUI.CLUDES_GREEN })
            local function NavigateToSetting(key)
                mod._UFNavigateToSetting(
                    hostFrame._sharedClickTargets or hostFrame._ufClickTargets,
                    key,
                    PlaySettingGlow,
                    true
                )
            end
            local function CreateHitOverlay(element, mappingKey, isText, frameLevelOverride, options)
                return (
                    CludesUI.CreatePreviewHitOverlay(
                        element,
                        NavigateToSetting,
                        mappingKey,
                        isText,
                        frameLevelOverride,
                        options
                    )
                )
            end

            -- Create hit overlays on preview elements. Never from the global search's
            -- hidden prebuild: the preview is live header content, not this hidden job's.
            local textOverlays = {}
            if activePreview and not CludesUI._prebuilding then
                local pv = activePreview
                local baseLevel = (pv._health and pv._health:GetFrameLevel() or 20) + 15
                local textLevel = baseLevel + 10
                if pv._health then
                    CreateHitOverlay(pv._health, "healthBar", false, baseLevel)
                end
                -- Absorb segments: hit area follows each absorb bar's FILL texture (the
                -- bar frame spans the whole health width), above the health overlay so it
                -- routes to Absorbs. No :IsShown() guard needed: as a fill-anchored child it
                -- auto-hides/shows with the bar; both bars get an overlay so whichever the heal-absorb eyeball shows stays click-navigable.
                if pv._absorbBar then
                    local absFill = pv._absorbBar:GetStatusBarTexture()
                    if absFill then
                        CreateHitOverlay(
                            absFill,
                            "absorbs",
                            false,
                            baseLevel + 5,
                            { parent = pv._health, showWith = pv._absorbBar }
                        )
                    end
                end
                if pv._healAbsorbBar then
                    local haFill = pv._healAbsorbBar:GetStatusBarTexture()
                    if haFill then
                        CreateHitOverlay(
                            haFill,
                            "healAbsorb",
                            false,
                            baseLevel + 5,
                            { parent = pv._health, showWith = pv._healAbsorbBar }
                        )
                    end
                end
                if pv._power then
                    CreateHitOverlay(pv._power, "powerBar", false, baseLevel)
                end
                if pv._portraitFrame and pv._portraitFrame:IsShown() then
                    CreateHitOverlay(pv._portraitFrame, "portrait", false, baseLevel)
                end
                if pv._castbar then
                    local castLevel = pv._castbar:GetFrameLevel() + 20
                    CreateHitOverlay(pv._castbar, "castBar", false, castLevel)
                    if pv._castIconFrame then
                        CreateHitOverlay(pv._castIconFrame, "castIcon", false, castLevel)
                    end
                    if pv._castNameFS then
                        textOverlays[#textOverlays + 1] =
                            CreateHitOverlay(pv._castNameFS, "castName", true, castLevel + 5)
                    end
                    if pv._castTimeFS and pv._castTimeFS:IsShown() then
                        textOverlays[#textOverlays + 1] =
                            CreateHitOverlay(pv._castTimeFS, "castTime", true, castLevel + 5)
                    end
                    if pv._castTargetFS and pv._castTargetFS:IsShown() then
                        textOverlays[#textOverlays + 1] =
                            CreateHitOverlay(pv._castTargetFS, "castTarget", true, castLevel + 5)
                    end
                end
                if pv._nameFS and pv._nameFS:IsShown() then
                    textOverlays[#textOverlays + 1] =
                        CreateHitOverlay(pv._nameFS, "nameText", true, textLevel)
                end
                if pv._hpFS and pv._hpFS:IsShown() then
                    textOverlays[#textOverlays + 1] =
                        CreateHitOverlay(pv._hpFS, "healthText", true, textLevel)
                end
                if pv._centerFS and pv._centerFS:IsShown() then
                    textOverlays[#textOverlays + 1] =
                        CreateHitOverlay(pv._centerFS, "centerText", true, textLevel)
                end
                if pv._extraFS and pv._extraFS:IsShown() then
                    textOverlays[#textOverlays + 1] =
                        CreateHitOverlay(pv._extraFS, "extraText", true, textLevel)
                end
                -- Blizzard Style level number: built whenever the art has a level
                -- circle and shown with the text (the preview toggles it).
                if pv._levelFS then
                    local lvOv = CreateHitOverlay(pv._levelFS, "levelText", true, textLevel)
                    pv._levelOv = lvOv
                    if not pv._levelFS:IsShown() then
                        lvOv:Hide()
                    end
                    textOverlays[#textOverlays + 1] = lvOv
                end
                if pv._ppFS and pv._ppFS:IsShown() then
                    textOverlays[#textOverlays + 1] =
                        CreateHitOverlay(pv._ppFS, "powerBarText", true, textLevel)
                end
                -- Overlay EVERY buff/debuff frame, not just currently-shown ones: each
                -- overlay is a SetAllPoints child of its icon, so it hides/shows and
                -- re-anchors with it. A prior ":IsShown()" guard tied clickability to
                -- build-time visibility, so icons shown later (header is cached, not rebuilt) had no overlay.
                if pv._buffIcons then
                    for idx = 1, #pv._buffIcons do
                        if pv._buffIcons[idx] then
                            CreateHitOverlay(pv._buffIcons[idx], "buffIcon", false, baseLevel)
                        end
                    end
                end
                if pv._debuffIcons then
                    for idx = 1, #pv._debuffIcons do
                        if pv._debuffIcons[idx] then
                            CreateHitOverlay(pv._debuffIcons[idx], "debuffIcon", false, baseLevel)
                        end
                    end
                end
                if pv._btbFrame then
                    local btbLevel = pv._btbFrame:GetFrameLevel() + 20
                    CreateHitOverlay(pv._btbFrame, "btbBar", false, btbLevel)
                    local btbTextLevel = btbLevel + 5
                    if pv._btbLeftFS then
                        textOverlays[#textOverlays + 1] =
                            CreateHitOverlay(pv._btbLeftFS, "btbLeftText", true, btbTextLevel)
                    end
                    if pv._btbRightFS then
                        textOverlays[#textOverlays + 1] =
                            CreateHitOverlay(pv._btbRightFS, "btbRightText", true, btbTextLevel)
                    end
                    if pv._btbCenterFS then
                        textOverlays[#textOverlays + 1] =
                            CreateHitOverlay(pv._btbCenterFS, "btbCenterText", true, btbTextLevel)
                    end
                    if pv._btbClassIcon then
                        local ciOv =
                            CreateHitOverlay(pv._btbClassIcon, "btbClassIcon", false, btbTextLevel + 2)
                        pv._btbClassIconOv = ciOv
                        if not pv._btbClassIcon:IsShown() then
                            ciOv:Hide()
                        end
                    end
                end
                if pv._cpPipContainer and pv._cpPipContainer:IsShown() then
                    pv._cpPipOv = CreateHitOverlay(pv._cpPipContainer, "classResource", false, baseLevel + 10)
                end
                if pv._combatIndicator and pv._combatIndicator:IsShown() then
                    CreateHitOverlay(pv._combatIndicator, "combatIndicator", false, baseLevel + 20)
                end
                -- Indicator badges (eye toggles): overlays made up front, shown and hidden
                -- with their badge by the preview update, so a badge switched on later is
                -- clickable straight away.
                local targets = hostFrame._sharedClickTargets or {}
                pv._badgeOv = {}
                for _, b in ipairs({
                    { pv._pvRaid, "raidMarker" },
                    { pv._pvLeader, "leaderIndicator" },
                    { pv._pvElite, "eliteIndicator" },
                    { pv._factionIndicator, "factionIndicator" },
                }) do
                    if b[1] and targets[b[2]] then
                        local shade = CreateHitOverlay(b[1], b[2], false, baseLevel + 20)
                        shade:SetShown(b[1]:IsShown())
                        pv._badgeOv[b[1]] = shade
                    end
                end
                pv._textOverlays = textOverlays
            end

            return abs(posY)
        end

        ---------------------------------------------------------------------------
        --  Mini Frames page  (dropdown selector + mini builders)
        ---------------------------------------------------------------------------
        local selectedMiniUnit = "targettarget"
        local miniUnitLabels = {
            ["targettarget"] = "Target of Target",
            ["focustarget"] = "Focus Target",
            ["pet"] = "Pet",
        }
        local miniUnitOrder = { "targettarget", "focustarget", "pet" }

        -- Allow Unlock Mode's "Element Options" to pre-select a mini unit before the
        -- Mini Frames page builds (mirrors the Main Frames _setUnitFrameUnit /
        -- _pendingUnitSelect mechanism). Field assignments -- no new locals.
        CludesUI._setMiniUnit = function(unitToken)
            selectedMiniUnit = unitToken
        end
        CludesUI._consumePendingMiniSelect = function()
            local pending = CludesUI._pendingMiniSelect
            if pending then
                selectedMiniUnit = pending
                CludesUI._pendingMiniSelect = nil
            end
        end

        local _miniHeaderBuilder
        local miniHeaderFixedH = 0

        local function BuildMiniPage(pageName, hostFrame, yOffset)
            -- Consume any pending mini selection from Element Options navigation
            if CludesUI._consumePendingMiniSelect then
                CludesUI._consumePendingMiniSelect()
            end

            -- Tag every option built on this page with the selected mini unit, so a
            -- global-search jump to a unit-specific setting can restore this selection
            -- first via CludesUI._setMiniUnit (see the matching CludesUI._buildingSelector
            -- comment in CUI_CooldownManager_Options.lua for the full reasoning).
            CludesUI._buildingSelector = { setter = CludesUI._setMiniUnit, key = selectedMiniUnit }

            local W = CludesUI.Widgets
            local posY = yOffset
            local _, hgt

            activePreview = nil

            -------------------------------------------------------------------
            --  CONTENT HEADER  (dropdown + preview)
            -------------------------------------------------------------------
            _miniHeaderBuilder = function(heading, hdrW)
                local DD_H = 34
                local fy = -20

                -- Centered dropdown (matches Action Bars Single Bar Edit)
                local ddW = 350
                local ddBtn, ddLbl = CludesUI.BuildDropdownControl(
                    heading,
                    ddW,
                    heading:GetFrameLevel() + 5,
                    miniUnitLabels,
                    miniUnitOrder,
                    function()
                        return selectedMiniUnit
                    end,
                    function(v)
                        selectedMiniUnit = v
                        -- One pass builds the page and its header together.
                        CludesUI:RefreshPage(true)
                        CludesUI.SmoothScrollTo(0)
                        -- Re-run the preview next frame once the rebuilt layout has
                        -- settled (same fix as the Main Frames unit selector).
                        C_Timer.After(0, UpdatePreview)
                    end
                )
                Pix.Point(ddBtn, "TOP", heading, "TOP", 0, fy)
                ddBtn:SetHeight(DD_H)
                fy = fy - DD_H - 20

                local side = unitSide[selectedMiniUnit] or "left"
                local preview = mod.UFO_BuildUnitPreview(heading, selectedMiniUnit, side)
                activePreview = preview
                local previewScale = preview._previewScale or 1
                local initBuffTopPad = preview._buffTopPad or 0
                preview._headerDropdownOY = math.abs(fy)
                preview:ClearAllPoints()
                Pix.Point(preview, "TOP", heading, "TOP", 0, (fy - initBuffTopPad) / previewScale)
                preview._lastOY = (fy - initBuffTopPad) / previewScale
                preview:Update()
                local previewH = preview:GetHeight() * preview:GetScale()
                local buffExtra = preview._buffExtra or 0
                local detTopExtra = preview._detTopExtra or 0
                fy = fy - previewH - buffExtra - detTopExtra - 20
                miniHeaderFixedH = 20 + DD_H + 20 + 20
                if preview then
                    preview._headerFixedH = miniHeaderFixedH
                end

                local _miniHeaderBaseH = math.abs(fy)
                return _miniHeaderBaseH
            end
            CludesUI:SetContentHeader(_miniHeaderBuilder)

            hostFrame._showRowDivider = true

            -------------------------------------------------------------------
            --  Route to mini builders
            -------------------------------------------------------------------
            if selectedMiniUnit == "targettarget" then
                posY = -mod.UFO_BuildFoTToTOptions(
                    W,
                    hostFrame,
                    posY,
                    saved.profile.targettarget,
                    "targettarget"
                )
            elseif selectedMiniUnit == "focustarget" then
                posY =
                    -mod.UFO_BuildFoTToTOptions(W, hostFrame, posY, saved.profile.focustarget, "focustarget")
            elseif selectedMiniUnit == "pet" then
                posY = -mod.UFO_BuildPetOptions(W, hostFrame, posY)
            end

            -------------------------------------------------------------------
            --  CLICK NAVIGATION
            -------------------------------------------------------------------
            local PlaySettingGlow = CludesUI.MakeSettingGlow({ color = CludesUI.CLUDES_GREEN })
            local function NavigateToSetting(key)
                mod._UFNavigateToSetting(hostFrame._ufClickTargets, key, PlaySettingGlow)
            end
            local hitStyle = { container = true }
            local function CreateHitOverlay(element, mappingKey, isText, frameLevelOverride, options)
                return (
                    CludesUI.CreatePreviewHitOverlay(
                        element,
                        NavigateToSetting,
                        mappingKey,
                        isText,
                        frameLevelOverride,
                        options,
                        hitStyle
                    )
                )
            end

            -- Create hit overlays on preview elements (never from the global search's
            -- hidden prebuild: the preview is live header content)
            if activePreview and not CludesUI._prebuilding then
                local pv = activePreview
                local baseLevel = (pv._health and pv._health:GetFrameLevel() or 20) + 15
                local textLevel = baseLevel + 10
                if pv._health then
                    CreateHitOverlay(
                        pv._health,
                        "healthBar",
                        false,
                        baseLevel,
                        { hlAnchor = pv._border or pv._health }
                    )
                end
                -- WoW Forever's pet: power bar, power text and happiness icon (the
                -- other mini previews build none of them).
                if pv._power then
                    CreateHitOverlay(pv._power, "powerBar", false, baseLevel)
                end
                if pv._ppFS and pv._ppFS:IsShown() then
                    CreateHitOverlay(pv._ppFS, "powerBarText", true, textLevel)
                end
                if pv._happyInd then
                    CreateHitOverlay(pv._happyInd, "petHappiness", false, baseLevel + 20)
                end
                if pv._portraitFrame and pv._portraitFrame:IsShown() then
                    CreateHitOverlay(pv._portraitFrame, "portrait", false, baseLevel)
                end
                if pv._castbar then
                    local castLevel = pv._castbar:GetFrameLevel() + 20
                    CreateHitOverlay(pv._castbar, "castBar", false, castLevel)
                end
                if pv._nameFS and pv._nameFS:IsShown() then
                    CreateHitOverlay(pv._nameFS, "nameText", true, textLevel)
                end
                if pv._hpFS and pv._hpFS:IsShown() then
                    CreateHitOverlay(pv._hpFS, "healthText", true, textLevel)
                end
                if pv._extraFS and pv._extraFS:IsShown() then
                    CreateHitOverlay(pv._extraFS, "extraText", true, textLevel)
                end
                if pv._centerFS and pv._centerFS:IsShown() then
                    CreateHitOverlay(pv._centerFS, "centerText", true, textLevel)
                end
                -- The pet's buff/debuff icons -> Buffs / Debuffs Location. Every icon,
                -- so one shown later stays clickable without a header rebuild (the
                -- other mini frames show none).
                if selectedMiniUnit == "pet" then
                    if pv._buffIcons then
                        for idx = 1, #pv._buffIcons do
                            if pv._buffIcons[idx] then
                                CreateHitOverlay(pv._buffIcons[idx], "buffIcon", false, baseLevel)
                            end
                        end
                    end
                    if pv._debuffIcons then
                        for idx = 1, #pv._debuffIcons do
                            if pv._debuffIcons[idx] then
                                CreateHitOverlay(pv._debuffIcons[idx], "debuffIcon", false, baseLevel)
                            end
                        end
                    end
                end
            end

            return abs(posY)
        end

        ---------------------------------------------------------------------------
        --  Boss Frames page  (single-unit page; no unit dropdown -- boss only)
        ---------------------------------------------------------------------------
        -- Stored on ns (not init-function locals) to stay clear of the Lua 5.1 200-local
        -- cap. Header builder mirrors the Mini page's minus the unit dropdown (boss is the
        -- only unit here); click-navigation block reuses the Mini page's machinery.
        mod._bossHeaderBuilder = nil
        mod._BuildBossPage = function(pageName, hostFrame, yOffset)
            local W = CludesUI.Widgets
            local posY = yOffset

            activePreview = nil

            -------------------------------------------------------------------
            --  CONTENT HEADER  (preview only, no dropdown)
            -------------------------------------------------------------------
            mod._bossHeaderBuilder = function(heading, hdrW)
                local fy = -20
                local side = unitSide.boss or "right"
                local preview = mod.UFO_BuildUnitPreview(heading, "boss", side)
                activePreview = preview
                local previewScale = preview._previewScale or 1
                local initBuffTopPad = preview._buffTopPad or 0
                preview._headerDropdownOY = math.abs(fy)
                preview:ClearAllPoints()
                Pix.Point(preview, "TOP", heading, "TOP", 0, (fy - initBuffTopPad) / previewScale)
                preview._lastOY = (fy - initBuffTopPad) / previewScale
                preview:Update()
                local previewH = preview:GetHeight() * preview:GetScale()
                local buffExtra = preview._buffExtra or 0
                local detTopExtra = preview._detTopExtra or 0
                fy = fy - previewH - buffExtra - detTopExtra - 20
                preview._headerFixedH = 20 + 20
                return math.abs(fy)
            end
            CludesUI:SetContentHeader(mod._bossHeaderBuilder)

            hostFrame._showRowDivider = true

            -------------------------------------------------------------------
            --  Boss section
            -------------------------------------------------------------------
            posY = -mod.UFO_BuildBossOptions(W, hostFrame, posY)

            -------------------------------------------------------------------
            --  CLICK NAVIGATION  (mirrors the Mini Frames page)
            -------------------------------------------------------------------
            local PlaySettingGlow = CludesUI.MakeSettingGlow({ color = CludesUI.CLUDES_GREEN })
            local function NavigateToSetting(key)
                mod._UFNavigateToSetting(hostFrame._ufClickTargets, key, PlaySettingGlow)
            end
            local hitStyle = { container = true }
            local function CreateHitOverlay(element, mappingKey, isText, frameLevelOverride, options)
                return (
                    CludesUI.CreatePreviewHitOverlay(
                        element,
                        NavigateToSetting,
                        mappingKey,
                        isText,
                        frameLevelOverride,
                        options,
                        hitStyle
                    )
                )
            end

            -- Create hit overlays on preview elements (never from the global search's
            -- hidden prebuild: the preview is live header content)
            if activePreview and not CludesUI._prebuilding then
                local pv = activePreview
                local baseLevel = (pv._health and pv._health:GetFrameLevel() or 20) + 15
                local textLevel = baseLevel + 10
                -- Health bar and power bar are separately clickable, each covering just
                -- its own bar (replacing the old ambiguous whole-frame overlay).
                if pv._health then
                    CreateHitOverlay(pv._health, "healthBar", false, baseLevel)
                end
                if pv._power then
                    CreateHitOverlay(pv._power, "powerBar", false, baseLevel)
                end
                if pv._ppFS and pv._ppFS:IsShown() then
                    CreateHitOverlay(pv._ppFS, "powerBarText", true, textLevel)
                end
                if pv._portraitFrame and pv._portraitFrame:IsShown() then
                    CreateHitOverlay(pv._portraitFrame, "portrait", false, baseLevel)
                end
                if pv._castbar then
                    local castLevel = pv._castbar:GetFrameLevel() + 20
                    CreateHitOverlay(pv._castbar, "castBar", false, castLevel)
                    -- Spell icon -> Show Cast Icon setting.
                    if pv._castIconFrame then
                        CreateHitOverlay(pv._castIconFrame, "castIcon", false, castLevel)
                    end
                end
                if pv._nameFS and pv._nameFS:IsShown() then
                    CreateHitOverlay(pv._nameFS, "nameText", true, textLevel)
                end
                if pv._hpFS and pv._hpFS:IsShown() then
                    CreateHitOverlay(pv._hpFS, "healthText", true, textLevel)
                end
                if pv._extraFS and pv._extraFS:IsShown() then
                    CreateHitOverlay(pv._extraFS, "extraText", true, textLevel)
                end
                if pv._centerFS and pv._centerFS:IsShown() then
                    CreateHitOverlay(pv._centerFS, "centerText", true, textLevel)
                end
                -- Blizzard Style level number: built whenever the art has a level
                -- circle and shown with the text (the preview toggles it).
                if pv._levelFS then
                    local lvOv = CreateHitOverlay(pv._levelFS, "levelText", true, textLevel)
                    pv._levelOv = lvOv
                    if not pv._levelFS:IsShown() then
                        lvOv:Hide()
                    end
                end
                -- Buff/Debuff icons -> their aura settings (Simple Display or Location,
                -- resolved at click time). Overlay every icon so newly shown ones stay
                -- clickable without a header rebuild.
                if pv._buffIcons then
                    for idx = 1, #pv._buffIcons do
                        if pv._buffIcons[idx] then
                            CreateHitOverlay(pv._buffIcons[idx], "buffIcon", false, baseLevel)
                        end
                    end
                end
                if pv._debuffIcons then
                    for idx = 1, #pv._debuffIcons do
                        if pv._debuffIcons[idx] then
                            CreateHitOverlay(pv._debuffIcons[idx], "debuffIcon", false, baseLevel)
                        end
                    end
                end
            end

            return abs(posY)
        end

        ---------------------------------------------------------------------------
        --  Unlock Mode page  (stub SelectPage intercepts this before buildPage)
        ---------------------------------------------------------------------------
        local function BuildUnlockPage(pageName, hostFrame, yOffset)
            -- SelectPage() intercepts "Unlock Mode" and fires _openUnlockMode directly.
            -- This stub exists only as a safety net in case buildPage is ever called.
            if CludesUI._openUnlockMode then
                C_Timer.After(0, CludesUI._openUnlockMode)
            end
            return 100
        end

        ---------------------------------------------------------------------------
        --  Register the module
        ---------------------------------------------------------------------------
        local ufSearchTerms = {}
        for _, labelText in pairs(unitLabels) do
            ufSearchTerms[#ufSearchTerms + 1] = labelText
        end
        for _, labelText in pairs(miniUnitLabels) do
            ufSearchTerms[#ufSearchTerms + 1] = labelText
        end
        -- "external defensives" matches the External Defensive aura-filter
        -- checkbox and the External Defensives bar inside Player Aura Bars.
        local _paTerms = { "external defensives", "externals", "pain suppression" }
        for _, t in ipairs(_paTerms) do
            ufSearchTerms[#ufSearchTerms + 1] = t
        end
        local _pabTerms = {
            "aura bars",
            "player aura bars",
            "buff bar",
            "debuff bar",
            "cooldown bars",
            "dispel colors",
            "grow direction",
        }
        for _, t in ipairs(_pabTerms) do
            ufSearchTerms[#ufSearchTerms + 1] = t
        end

        -- Rebuild preview when spec changes (class resource pips may appear/disappear)
        local ufOptSpecFrame = CreateFrame("Frame")
        ufOptSpecFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        ufOptSpecFrame:SetScript("OnEvent", function(_, _, unitToken)
            if unitToken ~= "player" then
                return
            end
            -- Only invalidate + rebuild when the panel is actually open. Invalidating while
            -- closed destroys all cached pages, causing a blank panel on next open.
            if CludesUI._mainFrame and CludesUI._mainFrame:IsShown() then
                CludesUI:InvalidatePageCache()
                C_Timer.After(0.2, function()
                    CludesUI:RefreshPage(true)
                end)
            end
        end)
        -- Textured Background: the Texture Settings cog row, shared by the Main and
        -- Mini Frames pages and Global Settings > Textures. unitFn returns the
        -- frame's settings (nil unitFn: the cast bar row); mini: a mini frame's key,
        -- which follows its main frame while its Bar Texture is Inherit; apply: the
        -- page's own refresh after a write.
        local function TexBgRowCfg(unitFn, apply, mini)
            if not unitFn then
                return {
                    type = "toggle",
                    label = "Textured Background",
                    tooltip = "Draws the bar texture on the cast bar backgrounds too.",
                    disabled = function()
                        return saved.profile.castBarTexture == "blizzard"
                    end,
                    disabledTooltip = "This option requires a Cast Bar Texture other than Blizzard.",
                    get = function()
                        return saved.profile.castTextureBg == true
                    end,
                    set = function(v)
                        saved.profile.castTextureBg = v and true or false
                        apply()
                    end,
                }
            end
            local function Inheriting(s)
                local v = mini and s.healthBarTexture
                return mini and (v == nil or v == "inherit")
            end
            local function Tex(s)
                return s.healthBarTexture or saved.profile.healthBarTexture or "none"
            end
            return {
                type = "toggle",
                label = "Textured Background",
                tooltip = "Draws the bar texture on the health and power backgrounds too.",
                disabled = function()
                    local s = unitFn()
                    if not s or Inheriting(s) then
                        return true
                    end
                    return Tex(s) == "none" or not mod.UF_HealthOpaque(s)
                end,
                disabledTooltip = function()
                    local s = unitFn()
                    if not s then
                        return nil
                    end
                    if Inheriting(s) then
                        return "This option requires a Bar Texture other than Inherit (Main Frames)."
                    end
                    if Tex(s) == "none" then
                        return "This option requires a Bar Texture other than None."
                    end
                    if mod.UF_DarkThemeOn(s) then
                        return "This option requires a Dark Mode Fill of 100 (Global Settings > Colors)."
                    end
                    if mini == "boss" then
                        return "This option requires a health Fill Color of 100."
                    end
                    return "This option requires a health Fill Opacity of 100."
                end,
                get = function()
                    local s = unitFn()
                    if not s then
                        return false
                    end
                    if Inheriting(s) then
                        return mod.UF_TexBgOn(mini)
                    end
                    return s.textureBg == true
                end,
                set = function(v)
                    local s = unitFn()
                    if not s then
                        return
                    end
                    s.textureBg = v and true or false
                    apply()
                end,
            }
        end

        -- Shared helpers and state for the builders under UnitFrames_Options\
        -- (loaded before this file, read when a page builds).
        mod._UFO_OptEnv = {
            TexBgRowCfg = TexBgRowCfg,
            _previewBuffIcons = _previewBuffIcons,
            _previewCreatureNames = _previewCreatureNames,
            abs = abs,
            AddDarkModeBlock = AddDarkModeBlock,
            allPreviews = allPreviews,
            ApplyClassIconTexture_Preview = ApplyClassIconTexture_Preview,
            ApplyPreviewPortraitShape = ApplyPreviewPortraitShape,
            AttachDebuffModeWarn = AttachDebuffModeWarn,
            AttachFrameSourceCog = AttachFrameSourceCog,
            BlizzPreviewScale = BlizzPreviewScale,
            btbPositionOrder = btbPositionOrder,
            btbPositionValues = btbPositionValues,
            btbTextOrder = btbTextOrder,
            btbTextValues = btbTextValues,
            buffAnchorOrder = buffAnchorOrder,
            buffAnchorValues = buffAnchorValues,
            buffGrowthOrder = buffGrowthOrder,
            buffGrowthValues = buffGrowthValues,
            BuildApplyAllRow = BuildApplyAllRow,
            BuildBarTexDropdown = BuildBarTexDropdown,
            BuildInactiveNotice = BuildInactiveNotice,
            CLASS_FULL_COORDS = CLASS_FULL_COORDS,
            CLASS_FULL_SPRITE_BASE = CLASS_FULL_SPRITE_BASE,
            classIconLocOrder = classIconLocOrder,
            classIconLocValues = classIconLocValues,
            classIconOrder = classIconOrder,
            classIconValues = classIconValues,
            classPowerPosOrder = classPowerPosOrder,
            classPowerPosValues = classPowerPosValues,
            classPowerStyleOrder = classPowerStyleOrder,
            classPowerStyleValues = classPowerStyleValues,
            classThemeSubOrder = classThemeSubOrder,
            classThemeSubValues = classThemeSubValues,
            db = saved,
            DebuffModeDropdownCfg = DebuffModeDropdownCfg,
            detPortraitShapeOrder = detPortraitShapeOrder,
            detPortraitShapeValues = detPortraitShapeValues,
            frames = frameList,
            GROUP_UNIT_ORDER = GROUP_UNIT_ORDER,
            HideExhaustionRow = HideExhaustionRow,
            healthTextOrder = healthTextOrder,
            healthTextOrderBoss = healthTextOrderBoss,
            healthTextOrderPlayer = healthTextOrderPlayer,
            healthTextOrderTargetFocus = healthTextOrderTargetFocus,
            healthTextValues = healthTextValues,
            MINI_GROUP_ORDER = MINI_GROUP_ORDER,
            optState = optionState,
            portraitArtOrder = portraitArtOrder,
            portraitArtValues = portraitArtValues,
            portraitModeOrder2 = portraitModeOrder2,
            portraitModeValues2 = portraitModeValues2,
            portraitNonPlayerOrder = portraitNonPlayerOrder,
            portraitNonPlayerValues = portraitNonPlayerValues,
            PP = Pix,
            PREVIEW_FONT = PREVIEW_FONT,
            PromptReloadIfUnspawned = PromptReloadIfUnspawned,
            RegisterWidgetRefresh = RegisterWidgetRefresh,
            ReloadAndUpdate = ReloadAndUpdate,
            ResolveBlizzPreview = ResolveBlizzPreview,
            SetPVFont = SetPVFont,
            SHORT_LABELS = SHORT_LABELS,
            SOLID_BACKDROP = SOLID_BACKDROP,
            SwapAuraSlot = SwapAuraSlot,
            UF_ImpCastGlowDesc = UF_ImpCastGlowDesc,
            UF_PurgeGlowDesc = UF_PurgeGlowDesc,
            UNIT_DB_MAP = UNIT_DB_MAP,
            UNIT_LABELS_SUP = UNIT_LABELS_SUP,
            unitSide = unitSide,
            UpdatePreview = UpdatePreview,
        }

        ---------------------------------------------------------------------------
        --  Player Aura Bars page (External Defensives lives inside it, as a
        --  third built-in bar -- see CUI_PlayerAuraBars_ManagerPages.lua)
        ---------------------------------------------------------------------------

        CludesUI:RegisterModule("CludesUIUnitFrames", {
            title = "Unit Frames",
            description = "Configure unit frame appearance and behavior.",
            pages = { PAGE_DISPLAY, PAGE_BOSS, PAGE_MINI, PAGE_AURA_BARS },
            -- Player Aura Bars draws over the scroll frame: no inline search there.
            noSearchPages = { [PAGE_AURA_BARS] = true },
            searchTerms = ufSearchTerms,
            buildPage = function(pageName, hostFrame, yOffset)
                if CludesUI._prebuilding and pageName == PAGE_AURA_BARS then
                    return
                end
                -- Clean up Player Aura Bars root when switching away. Needed here AND in
                -- onPageCacheRestore below: this covers a fresh build of the destination
                -- page, that one covers a cache-restored destination -- without both,
                -- cleanup is inconsistent across tab switches (mirrors CUI_RaidFrames_Options.lua's _bmRoot/_dmRoot/_ccRoot pattern).
                -- Never from the global search's hidden prebuild of another page: the
                -- root is the live page's.
                if pageName ~= PAGE_AURA_BARS and mod._pabRoot and not CludesUI._prebuilding then
                    mod.PABMP_ParkRoot()
                end
                -- Randomize preview creature IDs on every tab switch
                RandomizePreviewCreatures()
                mod.UF_AskExisting2DMirror()
                if pageName == PAGE_DISPLAY then
                    return BuildFrameDisplayPage(pageName, hostFrame, yOffset)
                elseif pageName == PAGE_BOSS then
                    return mod._BuildBossPage(pageName, hostFrame, yOffset)
                elseif pageName == PAGE_MINI then
                    return BuildMiniPage(pageName, hostFrame, yOffset)
                elseif pageName == PAGE_AURA_BARS then
                    if mod.PABMP_BuildPage then
                        return mod.PABMP_BuildPage(pageName, hostFrame, yOffset)
                    end
                end
            end,
            getHeaderBuilder = function(pageName)
                if pageName == PAGE_DISPLAY then
                    return _displayHeaderBuilder
                elseif pageName == PAGE_BOSS then
                    return mod._bossHeaderBuilder
                elseif pageName == PAGE_MINI then
                    return _miniHeaderBuilder
                end
                return nil
            end,
            -- Main/Mini Frames content gates on whichever unit is selected (default
            -- always "player"/"targettarget"), so a hidden pre-build that only builds the
            -- default leaves other units' settings unsearchable until picked live. Both
            -- unit lists are small and fixed, so build once per unit rather than collapsing to representative shapes.
            getPrebuildVariants = function(pageName)
                if pageName == PAGE_DISPLAY then
                    return {
                        setter = CludesUI._setUnitFrameUnit,
                        keys = unitOrder,
                        currentKey = optionState.selectedUnit,
                    }
                elseif pageName == PAGE_MINI then
                    return {
                        setter = CludesUI._setMiniUnit,
                        keys = miniUnitOrder,
                        currentKey = selectedMiniUnit,
                    }
                end
                return nil
            end,
            onPageCacheRestore = function(pageName)
                local textCheck = mod._ufTextChecks and mod._ufTextChecks[pageName]
                if textCheck and textCheck() then
                    C_Timer.After(0, function()
                        if
                            CludesUI:GetActiveModule() == "CludesUIUnitFrames"
                            and CludesUI:GetActivePage() == pageName
                        then
                            CludesUI:RefreshPage(true)
                        end
                    end)
                end
                -- Clean up Player Aura Bars root when switching away
                if pageName ~= PAGE_AURA_BARS and mod._pabRoot then
                    mod.PABMP_ParkRoot()
                elseif pageName == PAGE_AURA_BARS and not mod._pabRoot then
                    -- PABMP_BuildPage bypasses `parent` and builds onto the live shared
                    -- scrollFrame into ns._pabRoot (see buildPage's _prebuilding guard
                    -- above). The framework's page cache doesn't know about that
                    -- self-managed root: on a cache-restore decision, content already torn
                    -- down by an earlier switch-away never gets rebuilt. Mirrors
                    -- CUI__General_Options.lua's PAGE_PROFILES/PAGE_OVERRIDES fix (CleanupProfilesRoot + deferred RefreshPage(true) guarded by GetActiveModule/GetActivePage).
                    C_Timer.After(0, function()
                        if
                            CludesUI:GetActiveModule() == "CludesUIUnitFrames"
                            and CludesUI:GetActivePage() == pageName
                        then
                            CludesUI:RefreshPage(true)
                        end
                    end)
                end
                RandomizePreviewCreatures()
                mod.UF_AskExisting2DMirror()
                -- Hide all UIParent-parented disabled overlays before restoring
                -- (they persist across tab switches since they're not children of pf)
                for k, pv in pairs(allPreviews) do
                    if pv and pv._pvUnit == k and pv._disabledOverlay then
                        pv._disabledOverlay:Hide()
                    end
                end
                -- Force re-anchor previews after cache restore (parent changed)
                for k, pv in pairs(allPreviews) do
                    if pv and pv._pvUnit == k then
                        pv._lastOY = nil
                        -- Reset portrait anchor flag so Update() re-anchors it
                        if pv._portraitFrame then
                            pv._portraitFrame._anchored = false
                        end
                        -- Reset health anchor key so Update() re-anchors health bar
                        if pv._health then
                            pv._health._anchorKey = nil
                        end
                    end
                end
                UpdatePreview()
                -- Refresh hint visibility on cache restore
                local dismissed = IsPreviewHintDismissed()
                if pageName == PAGE_DISPLAY and optionState._ufPreviewHintFS_display then
                    if dismissed then
                        optionState._ufPreviewHintFS_display:Hide()
                    else
                        optionState._ufPreviewHintFS_display:SetAlpha(0.45)
                        optionState._ufPreviewHintFS_display:Show()
                    end
                end
            end,
            onReset = function()
                saved:ResetProfile()
                -- No reload here: Reset CUI Module Settings reloads after this returns.
            end,
            -- Tears down Boss Preview on module switch (RegisterOnHide above
            -- only covers closing the whole options window).
            onModuleLeave = function()
                if mod._bossPreviewActive and mod.SetBossPreview then
                    mod.SetBossPreview(false)
                end
            end,
        })

        ---------------------------------------------------------------------------
        --  Slash command  /cuf
        ---------------------------------------------------------------------------
        SLASH_CLUDESUNITFRAMES1 = "/cuf"
        SlashCmdList.CLUDESUNITFRAMES = function(msg)
            if InCombatLockdown and InCombatLockdown() then
                print("Cannot open options in combat")
                return
            end

            if msg == "reset" then
                -- The reload first (RequestReload); the reset lands before it.
                CludesUI.RequestReload()
                saved:ResetProfile()
                return
            end

            CludesUI:ShowModule("CludesUIUnitFrames")
        end
    end -- ns._InitCUIModule

    -- If SetupOptionsPanel already ran before PLAYER_LOGIN (unlikely but safe),
    -- fire immediately
    if mod.db then
        mod._InitCUIModule()
    end
end)
-- LoadOnDemand: this addon loads after PLAYER_LOGIN, so the event above will never fire; run the init now.
if IsLoggedIn() then
    initFrame:GetScript("OnEvent")(initFrame)
end
