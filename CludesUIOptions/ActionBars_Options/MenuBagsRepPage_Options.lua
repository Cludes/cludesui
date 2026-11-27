if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-------------------------------------------------------------------------------
--  ActionBars_Options\MenuBagsRepPage_Options.lua
--  Action Bars options: the Menu, Bags & Rep Bars page (BuildMenuBagsRepPage)
--  and the data bar kit it shares with the XP Bar page (ns.ABO_DataBarKit):
--  the data bar rows and controls (Visibility, Orientation and its Vertical
--  Text cog, Width | Height, the border rows, the fill colour swatches, Bar
--  Texture, Text Size and its cog, Click Through) and the per-bar section the
--  reputation and House Favor bars use; the XP Bar page lays the same pieces
--  out its own way. Definitions only; the shared helpers come from
--  ns._ABO_OptEnv (filled by CUI_ActionBars_Options.lua).
-------------------------------------------------------------------------------
local mod = CUI._ModuleNS["CludesUIActionBars"]
if not mod then return end -- module disabled: no options page

---------------------------------------------------------------------------
--  Data bar kit  (XP Bar and Menu, Bags & Rep Bars pages)
---------------------------------------------------------------------------

-- The data bars this client builds (WoW Forever has no House Favor bar).
local DATA_BAR_KEYS = CUI.IS_FOREVER and { "XPBar", "RepBar" } or { "XPBar", "RepBar", "FavorBar" }
local DATA_BAR_LABELS = { XPBar = "XP Bar", RepBar = "Reputation Bar", FavorBar = "House Favor Bar" }
-- The bars whose borders sync with each other: the rep bars. The XP bar's
-- border is its own and never syncs (a lone rep bar, on Forever, has nothing
-- to sync with).
local BORDER_SYNC_KEYS = CUI.IS_FOREVER and { "RepBar" } or { "RepBar", "FavorBar" }
local BORDER_SYNCS = {}
for _, keyName in ipairs(BORDER_SYNC_KEYS) do
    BORDER_SYNCS[keyName] = #BORDER_SYNC_KEYS > 1
end
local ORIENT_VALUES = { HORIZONTAL = "Horizontal", VERTICAL = "Vertical" }
local ORIENT_ORDER = { "HORIZONTAL", "VERTICAL" }
-- Representative colors for the "Reactive (Default)" swatch.
local REACTIVE_PREVIEW = {
    XPBar = { 0.60, 0.40, 0.85 },
    RepBar = { 0.30, 0.70, 0.25 },
    FavorBar = { 0.85, 0.64, 0.22 },
}

-- After a change to Use Blizzard's Rep Bars or the XP Bar Style: the page
-- re-reads its values, and a change that leaves our bars wanted but never
-- built (they are built at login only while Blizzard's are off), or brings
-- Blizzard's bars back after their events were dropped, asks for the reload
-- that applies it.
local function AfterDataBarSwitch(needsReload)
    CUI:RefreshPage()
    if needsReload then
        CUI:ShowConfirmPopup({
            title = "Reload Required",
            message = mod.EAB.db.profile.useBlizzardDataBars
                    and "Blizzard's XP and reputation bars return after a UI reload."
                or "Your own XP and reputation bars are created on reload.",
            confirmText = "Reload Now",
            cancelText = "Later",
            reload = true,
        })
    end
end

-- The kit for one page build on `parent`. Every builder takes the page's y
-- cursor and returns the new one.
local function DataBarKit(hostFrame)
    local environ = mod._ABO_OptEnv
    local ApplyVisibilityKey, ABAR, GetVisibilityKey =
        environ.ApplyVisibilityKey, environ.EAB, environ.GetVisibilityKey
    local ShownBorderDefaults = environ.ShownBorderDefaults
    local W = CUI.Widgets
    local K = { AfterSwitch = AfterDataBarSwitch }

    local BLIZZ_DIS_TIP = "This option does not work with Blizzard Bars. Please use Blizzard Edit Mode."
    local function _blizzDataBarsOn() return ABAR.db.profile.useBlizzardDataBars end
    K.BLIZZ_DIS_TIP, K.BlizzDis = BLIZZ_DIS_TIP, _blizzDataBarsOn

    -- Shared visibility row: left vis dropdown + right "Visibility Options" CB dropdown.
    -- trackNeverFlip: data-bar sections hide dependent rows while visibility is Never, so a
    -- Never <-> not-Never flip forces a full page rebuild (fresh closure each rebuild).
    local function BarIsNever(barId)
        local cfg = ABAR.db.profile.bars[barId]
        if not cfg then return false end
        GetVisibilityKey(cfg) -- normalize legacy booleans into barVisibility
        return cfg.barVisibility == "never" or cfg.alwaysHidden == true
    end
    -- Returns the row config rather than building it, so two bars can share one
    -- row (rightVis) instead of each taking a half-empty one.
    local function VisibilityOptions(barId, leftLabel, disabledFn, disTip, trackNeverFlip)
        local wasNever = trackNeverFlip and BarIsNever(barId)
        return {
            getStore = function()
                local s = ABAR.db.profile.bars[barId]
                -- Normalize first: extra-bar defaults may carry only legacy booleans, no barVisibility key yet.
                if s then GetVisibilityKey(s) end
                return s
            end,
            legacyKey = "barVisibility",
            label = leftLabel,
            -- noOverrideMouseover: this module's hover wiring reads the STORED
            -- mouseoverEnabled, which an override does not write, so a Mouseover
            -- override would silently behave like Always. Offered as locked rather
            -- than looking available and doing nothing.
            caps = {
                partyIncludesRaid = false,
                luaDragonriding = true,
                noOverrideMouseover = true,
            },
            applyScalarFn = function(s, mode) ApplyVisibilityKey(s, mode) end,
            disabledFn = disabledFn,
            disabledTooltip = disTip,
            rawTooltip = disTip and true or nil,
            onChanged = function()
                ABAR:RefreshRuntimeVisibility()
                ABAR:RefreshMouseover()
                ABAR:ApplyCombatVisibility()
                if trackNeverFlip and BarIsNever(barId) ~= wasNever then CUI:RefreshPage(true) end
            end,
            -- Option axes recompile the secure driver through the same chain the
            -- old Visibility Options dropdown used. The gate refresh first: a lane
            -- click can be what just armed (or disarmed) the soft-target machinery,
            -- and the two calls below must see the current flags, not last click's.
            onOptionChanged = function()
                ABAR:_RefreshSoftTargetGate()
                ABAR:UpdateHousingVisibility()
                ABAR:ApplyCombatVisibility()
            end,
        }
    end
    K.VisOpts = VisibilityOptions

    -- Single-bar row (data bar sections): one Visibility control; rightCfg is
    -- any ordinary widget for the right slot (nil = blank). Returns the row
    -- and the new y.
    local function BuildVisRow(cursorY, barId, leftLabel, disabledFn, disTip, trackNeverFlip, rightCfg)
        local visRow, visH = CUI.BuildVisibilityRow(
            W,
            hostFrame,
            cursorY,
            VisibilityOptions(barId, leftLabel, disabledFn, disTip, trackNeverFlip),
            rightCfg
        )
        return visRow, cursorY - visH
    end

    K.BarIsNever = BarIsNever
    -- A data bar's Visibility row with rightCfg in its right slot (nil =
    -- blank), locked under Blizzard's bars; a Never flip rebuilds the page.
    function K.VisRow(cursorY, barId, visLabel, rightCfg)
        return BuildVisRow(cursorY, barId, visLabel, _blizzDataBarsOn, BLIZZ_DIS_TIP, true, rightCfg)
    end

    -- Orientation for `keys`, the data bars it flips together (the first
    -- one's setting is shown). A width or height match across the edge of
    -- those bars (one of them follows an element outside them, or another
    -- data bar built here follows one of them) locks it: a flip swaps both
    -- axes, and such a match would pull one straight back or reshape the
    -- other bar. A match between two of the bars flips with them.
    function K.OrientCfg(keyList)
        local set = {}
        for _, keyName in ipairs(keyList) do
            set[keyName] = true
        end
        local function OutsideSizeMatch()
            for _, keyName in ipairs(DATA_BAR_KEYS) do
                local t = CUI.GetWidthMatchTarget(keyName)
                if t and not set[keyName] ~= not set[t] then return keyName, t end
                t = CUI.GetHeightMatchTarget(keyName)
                if t and not set[keyName] ~= not set[t] then return keyName, t end
            end
        end
        return {
            type = "dropdown",
            text = "Orientation",
            values = ORIENT_VALUES,
            order = ORIENT_ORDER,
            disabled = function() return _blizzDataBarsOn() or OutsideSizeMatch() ~= nil end,
            disabledTooltip = function()
                if _blizzDataBarsOn() then return BLIZZ_DIS_TIP end
                local keyName, t = OutsideSizeMatch()
                if not keyName then return nil end
                return CUI.GetBarLabel(keyName)
                    .. ": "
                    .. CUI.Lf(
                        "Size matched to %1$s. Unmatch in Edit Layout to edit.",
                        CUI.GetBarLabel(t)
                    )
            end,
            rawTooltip = true,
            getValue = function()
                local b = ABAR.db.profile.bars[keyList[1]]
                return b and b.orientation or "HORIZONTAL"
            end,
            setValue = function(val)
                -- Every bar of the group takes the orientation, one not built
                -- on this client included, so they keep one shared value in a
                -- profile carried to another client. A flip swaps a bar's
                -- width and height while its shape suits the old orientation,
                -- so it keeps its length and thickness (400 x 18 horizontal
                -- becomes 18 x 400 vertical); a bar already shaped for the new
                -- one keeps its size. Every bar is written before any is laid
                -- out, so a size match between two of them reads the new sizes
                -- when the first one resizes.
                local barList = ABAR.db.profile.bars
                for _, keyName in ipairs(keyList) do
                    local b = barList[keyName]
                    if b then
                        local bw, bh = b.width or 400, b.height or 18
                        if (b.orientation or "HORIZONTAL") ~= val and (val == "VERTICAL") == (bw > bh) then
                            b.width, b.height = bh, bw
                        end
                        b.orientation = val
                    end
                end
                for _, keyName in ipairs(keyList) do
                    if barList[keyName] then mod.ApplyDataBarLayout(keyName) end
                end
                -- Rebuild: the Width and Height sliders take their ranges from
                -- the orientation when they are built.
                CUI:RefreshPage(true)
            end,
        }
    end

    -- The Vertical Text cog on an Orientation control (locked unless
    -- Vertical): runs the bar text (and, with dividers, the divider labels)
    -- along the bar. Each setting goes to every bar of `keys`, as the
    -- orientation does.
    function K.OrientCog(regionFrame, keyList, dividers)
        if CUI._prebuilding then return end
        local lead = keyList[1]
        local function Flag(key)
            local b = ABAR.db.profile.bars[lead]
            return b and b[key] and true or false
        end
        local function SetFlag(key, val)
            for _, keyName in ipairs(keyList) do
                local b = ABAR.db.profile.bars[keyName]
                if b then
                    b[key] = val
                    mod.ApplyDataBarLayout(keyName)
                end
            end
        end
        local rowList = {
            {
                type = "toggle",
                label = "Rotate Bar Text",
                tooltip = "Runs the bar text along the bar.",
                get = function() return Flag("rotateText") end,
                set = function(val) SetFlag("rotateText", val) end,
            },
        }
        if dividers then
            rowList[#rowList + 1] = {
                type = "toggle",
                label = "Rotate Divider Labels",
                tooltip = "Runs the divider percentages along the bar.",
                get = function() return Flag("rotateDividerText") end,
                set = function(val) SetFlag("rotateDividerText", val) end,
            }
        end
        rowList[#rowList + 1] = {
            type = "toggle",
            label = "Read Downward",
            tooltip = "Rotated text reads from top to bottom.",
            disabled = function() return not (Flag("rotateText") or (dividers and Flag("rotateDividerText"))) end,
            disabledTooltip = dividers and "This option requires Rotate Bar Text or Rotate Divider Labels."
                or "This option requires Rotate Bar Text.",
            rawTooltip = true,
            get = function() return Flag("textReadDown") end,
            set = function(val) SetFlag("textReadDown", val) end,
        }
        CUI.BuildInlineCog(regionFrame, {
            title = "Vertical Text",
            anchorTo = regionFrame._control,
            disabled = function()
                if _blizzDataBarsOn() then return true end
                local b = ABAR.db.profile.bars[lead]
                return not (b and b.orientation == "VERTICAL")
            end,
            disabledTooltip = function()
                if _blizzDataBarsOn() then return BLIZZ_DIS_TIP end
                return "This option requires the Vertical orientation."
            end,
            rawTooltip = true,
            rows = rowList,
        })
    end

    -- A style row: leftCfg | Orientation for `keys` with its Vertical Text
    -- cog (dividers: the bars draw dividers, so the cog also offers Rotate
    -- Divider Labels).
    function K.StyleRow(cursorY, leftCfg, keyList, dividers)
        local row, height = W:DualRow(hostFrame, cursorY, leftCfg, K.OrientCfg(keyList))
        K.OrientCog(row._rightRegion, keyList, dividers)
        return cursorY - height
    end

    -- Shared bar-texture dropdown tables (built-ins + SharedMedia) with menu preview backgrounds, same treatment as the nameplate Bar Texture dropdown.
    local dbTexValues, dbTexOrder = {}, {}
    do
        local nameList = mod.dataBarTextureNames or {}
        local lookup = mod.dataBarTextures or {}
        for _, key in ipairs(mod.dataBarTextureOrder or {}) do
            if key ~= "---" then dbTexValues[key] = nameList[key] or key end
            dbTexOrder[#dbTexOrder + 1] = key
        end
        dbTexValues._menuOpts = {
            itemHeight = 28,
            background = function(key)
                if not key or key == "---" or key == "none" then return nil end
                if CUI.ResolveTexturePath then return CUI.ResolveTexturePath(lookup, key, nil) end
                return lookup[key]
            end,
        }
    end
    local function RefreshDataBar(bk)
        local f = mod.dataBarFrames and mod.dataBarFrames[bk]
        if f and f._updateFunc then f._updateFunc() end
        mod.RefreshDataBarPreview(bk, true)
    end

    -- Custom Border (each data-bar section's opt-in). Its two sync links copy
    -- between the built rep bars (BORDER_SYNC_KEYS) only. The style link
    -- carries the style, its offsets, shifts and Show Behind plus the colour
    -- a style pick seeds; the size link carries the size and the colour. Both
    -- turn the target's Custom Border on, so a target never holds values it
    -- does not draw.
    local function DataBarTextured(cfg)
        local t = cfg.borderTexture or "solid"
        return t ~= "" and t ~= "solid"
    end
    local function CopyDataBarColor(dst, source)
        local color = source.borderColor
        if color then dst.borderColor = { r = color.r, g = color.g, b = color.b, a = color.a } end
    end
    local function CopyDataBarStyle(dst, source)
        dst.customBorder = true
        dst.borderTexture = source.borderTexture
        dst.borderTextureOffset, dst.borderTextureOffsetY =
            source.borderTextureOffset, source.borderTextureOffsetY
        dst.borderTextureShiftX, dst.borderTextureShiftY =
            source.borderTextureShiftX, source.borderTextureShiftY
        dst.borderBehind = source.borderBehind
        CopyDataBarColor(dst, source)
    end
    local function CopyDataBarSize(dst, source)
        dst.customBorder = true
        dst.borderThickness = source.borderThickness
        local val = source.borderThicknessPx
        if val == nil and dst.borderThicknessPx ~= nil then val = false end -- false travels, nil would not
        dst.borderThicknessPx = val
        CopyDataBarColor(dst, source)
    end
    local function SameDataBarStyle(tbl, cfg)
        return tbl.customBorder == true
            and (tbl.borderTexture or "solid") == (cfg.borderTexture or "solid")
            and tbl.borderTextureOffset == cfg.borderTextureOffset
            and tbl.borderTextureOffsetY == cfg.borderTextureOffsetY
            and tbl.borderTextureShiftX == cfg.borderTextureShiftX
            and tbl.borderTextureShiftY == cfg.borderTextureShiftY
            and (tbl.borderBehind or false) == (cfg.borderBehind or false)
    end
    local function SameDataBarSize(tbl, cfg)
        if tbl.customBorder ~= true then return false end
        if (tbl.borderThickness or "thin") ~= (cfg.borderThickness or "thin") then return false end
        if (tbl.borderThicknessPx or false) ~= (cfg.borderThicknessPx or false) then return false end -- nil and false render alike
        local a, b = tbl.borderColor, cfg.borderColor
        return (a and a.r or 0) == (b and b.r or 0)
            and (a and a.g or 0) == (b and b.g or 0)
            and (a and a.b or 0) == (b and b.b or 0)
            and (a and a.a or 1) == (b and b.a or 1)
    end
    -- One "Apply to: All | Multiple" link on a Custom Border row half. A target
    -- whose Custom Border was off gains rows, and one that moves between Solid
    -- and a textured style gains or loses its offset row, so those rebuild the
    -- page.
    local function DataBarSyncIcon(regionFrame, srcKey, tooltip, copyFn, sameFn)
        local function ApplyTo(keyList)
            local source = ABAR.db.profile.bars[srcKey]
            local reveal = false
            for _, keyName in ipairs(keyList) do
                local dst = ABAR.db.profile.bars[keyName]
                if dst and dst ~= source then
                    if dst.customBorder ~= true then reveal = true end
                    local wasTex = DataBarTextured(dst)
                    copyFn(dst, source)
                    if DataBarTextured(dst) ~= wasTex then reveal = true end
                    mod.ApplyDataBarLayout(keyName)
                end
            end
            CUI:RefreshPage(reveal)
        end
        CUI.BuildSyncIcon({
            region = regionFrame,
            tooltip = tooltip,
            onClick = function() ApplyTo(BORDER_SYNC_KEYS) end,
            isSynced = function()
                local source = ABAR.db.profile.bars[srcKey]
                for _, keyName in ipairs(BORDER_SYNC_KEYS) do
                    local t = ABAR.db.profile.bars[keyName]
                    if t and not sameFn(t, source) then return false end
                end
                return true
            end,
            flashTargets = function() return { regionFrame } end,
            multiApply = {
                elementKeys = BORDER_SYNC_KEYS,
                elementLabels = DATA_BAR_LABELS,
                getCurrentKey = function() return srcKey end,
                onApply = ApplyTo,
            },
        })
    end

    -- One bar's border rows: Border Style | Border Size (with the colour, the
    -- Border Options cog and, on a rep bar, the two sync links), then Width
    -- Offset | Height Offset for a textured style. implicit (the XP Bar page,
    -- which has no Custom Border toggle): until the bar's Custom Border is on,
    -- the rows show the plain line it draws (Solid, 1px, black) and the first
    -- edit turns it on from those values, dropping what a border once turned
    -- off left behind.
    local NO_BORDER = {}
    function K.BorderRows(cursorY, barId, implicit)
        local _, height
        local function BarCfg() return ABAR.db.profile.bars[barId] end
        local function V()
            local cfg = BarCfg()
            if implicit and cfg.customBorder ~= true then return NO_BORDER end
            return cfg
        end
        local turnedOn = false
        local function Wr()
            local cfg = BarCfg()
            if implicit and cfg.customBorder ~= true then
                cfg.borderTexture, cfg.borderThickness, cfg.borderThicknessPx = nil, nil, nil
                cfg.borderColor, cfg.borderBehind = nil, nil
                cfg.borderTextureOffset, cfg.borderTextureOffsetY = nil, nil
                cfg.borderTextureShiftX, cfg.borderTextureShiftY = nil, nil
                cfg.customBorder = true
                turnedOn = true
            end
            return cfg
        end
        -- After a write: lay the bar out and refresh the page, or rebuild it
        -- when that write turned the border on (its sync links appear).
        local function FinishToggle()
            mod.ApplyDataBarLayout(barId)
            if turnedOn then
                turnedOn = false
                CUI:RefreshPage(true)
            else
                CUI:RefreshPage()
            end
        end
        local texValues, texOrder = CUI.GetBorderTextureDropdown()
        local function Textured() return DataBarTextured(V()) end
        local function BorderOff() return (mod.ResolveBorderThickness(V())) <= 0 end
        local brdRow
        brdRow, height = W:DualRow(
            hostFrame,
            cursorY,
            {
                type = "dropdown",
                text = "Border Style",
                disabled = _blizzDataBarsOn,
                disabledTooltip = BLIZZ_DIS_TIP,
                rawTooltip = true,
                values = texValues,
                order = texOrder,
                getValue = function() return V().borderTexture or "solid" end,
                -- The offset row exists only for a textured style, so only a
                -- Solid <-> textured flip rebuilds the page.
                setValue = CUI.DependentSetValue(Textured, function(val)
                    local cfg = Wr()
                    local defTh = CUI.GetBorderDefaultSize("actionbars", val)
                    -- An unregistered SharedMedia border answers the NUMBER 1; this key stores labels.
                    if type(defTh) == "number" then defTh = CUI.BORDER_LABEL_OF_STEP[defTh] or "thin" end
                    local col, behind = CUI.GetBorderStyleSelectDefaults(val)
                    cfg.borderTexture = val
                    cfg.borderTextureOffset, cfg.borderTextureOffsetY = nil, nil
                    cfg.borderTextureShiftX, cfg.borderTextureShiftY = nil, nil
                    -- A style pick resets the size: a set exact size goes with it (false travels, nil would not).
                    if cfg.borderThicknessPx then cfg.borderThicknessPx = false end
                    cfg.borderColor = { r = col.r, g = col.g, b = col.b, a = 1 }
                    cfg.borderBehind = behind
                    if defTh then cfg.borderThickness = defTh end
                    FinishToggle()
                end),
            },
            CUI.BorderPxSliderCfg({
                text = "Border Size",
                disabled = _blizzDataBarsOn,
                disabledTooltip = BLIZZ_DIS_TIP,
                rawTooltip = true,
                -- The step the bar renders with (ResolveBorderThickness): an
                -- unknown thickness is thin.
                getStep = function()
                    local record = mod.BORDER_THICKNESS[V().borderThickness or "thin"]
                        or mod.BORDER_THICKNESS.thin
                    return record.regular
                end,
                setStep = function(step) Wr().borderThickness = CUI.BORDER_LABEL_OF_STEP[step] end,
                getTex = function() return V().borderTexture or "solid" end,
                getPx = function() return V().borderThicknessPx end,
                setPx = function(val) Wr().borderThicknessPx = val end,
                apply = FinishToggle,
            })
        )
        cursorY = cursorY - height

        -- Width Offset | Height Offset: the textured border's outward offsets
        -- (Solid has none). Shown = the override, else the "actionbars"
        -- registry default for the step and thickness key the bar renders
        -- with, scaled to an exact size as drawn.
        if Textured() then
            local ocfgL, ocfgR = CUI.BorderOffsetRowCfgs({
                addonKey = "actionbars",
                tooltip = "How far the border reaches past the bar.",
                disabled = _blizzDataBarsOn,
                disabledTooltip = BLIZZ_DIS_TIP,
                rawTooltip = true,
                getTex = function() return V().borderTexture or "solid" end,
                getStep = function() return (mod.ResolveBorderThickness(V())) end,
                getSizeKey = function() return V().borderThickness or "thin" end,
                getPx = function() return V().borderThicknessPx end,
                getX = function() return V().borderTextureOffset end,
                setX = function(val) Wr().borderTextureOffset = val end,
                getY = function() return V().borderTextureOffsetY end,
                setY = function(val) Wr().borderTextureOffsetY = val end,
                apply = FinishToggle,
            })
            _, height = W:DualRow(hostFrame, cursorY, ocfgL, ocfgR)
            cursorY = cursorY - height
        end

        -- Row chrome (frames: never on the search pre-build's absorber rows).
        if not CUI._prebuilding then
            -- Border Options cog (Shift X / Shift Y / Show Behind): textured
            -- styles only, hidden (not dimmed) for Solid and under Blizzard bars.
            local lRgn = brdRow._leftRegion
            local function BorderDefaults()
                local cfg = V()
                local step, px = mod.ResolveBorderThickness(cfg)
                return ShownBorderDefaults(
                    cfg.borderTexture or "solid",
                    cfg.borderThickness or "thin",
                    step,
                    px
                )
            end
            -- Landing on the shift the slider shows by default stores nil
            -- (follow the style again); any other value is an override.
            local function SetShift(key, val, def)
                if val == math.floor(def + 0.5) then val = nil end
                Wr()[key] = val
                FinishToggle()
            end
            local cogBtn = CUI.BuildInlineCog(lRgn, {
                anchorTo = lRgn._control,
                title = "Border Options",
                tip = "Fine-tunes the textured border's position and draws it under the bar fill when Show Behind is on.",
                captureRegion = lRgn,
                rows = {
                    {
                        type = "slider",
                        label = "Shift X",
                        min = -10,
                        max = 10,
                        step = 1,
                        get = function()
                            local val = V().borderTextureShiftX
                            if val ~= nil then return val end
                            local _, _, dsx = BorderDefaults()
                            return dsx
                        end,
                        set = function(val)
                            local _, _, dsx = BorderDefaults()
                            SetShift("borderTextureShiftX", val, dsx)
                        end,
                    },
                    {
                        type = "slider",
                        label = "Shift Y",
                        min = -10,
                        max = 10,
                        step = 1,
                        get = function()
                            local val = V().borderTextureShiftY
                            if val ~= nil then return val end
                            local _, _, _, dsy = BorderDefaults()
                            return dsy
                        end,
                        set = function(val)
                            local _, _, _, dsy = BorderDefaults()
                            SetShift("borderTextureShiftY", val, dsy)
                        end,
                    },
                    {
                        type = "toggle",
                        label = "Show Behind",
                        get = function() return V().borderBehind or false end,
                        set = function(val)
                            Wr().borderBehind = val and true or false
                            FinishToggle()
                        end,
                    },
                },
            })
            if cogBtn then
                local function UpdateCogVis() cogBtn:SetShown(Textured() and not _blizzDataBarsOn()) end
                CUI.RegisterWidgetRefresh(UpdateCogVis)
                UpdateCogVis()
            end

            -- Border color with alpha, left of the Border Size slider.
            CUI.BuildInlineSwatches(brdRow._rightRegion, {
                {
                    tooltip = "Border Color",
                    hasAlpha = true,
                    getValue = function()
                        local color = V().borderColor
                        if color then return color.r or 0, color.g or 0, color.b or 0, color.a or 1 end
                        return 0, 0, 0, 1
                    end,
                    setValue = function(red, green, blue, a)
                        Wr().borderColor = { r = red, g = green, b = blue, a = a or 1 }
                        FinishToggle()
                    end,
                },
            }, {
                size = 20,
                disabled = function() return _blizzDataBarsOn() or BorderOff() end,
                disabledTooltip = function()
                    if _blizzDataBarsOn() then return BLIZZ_DIS_TIP end
                    return "This option requires a Border Size above 0."
                end,
                rawTooltip = true,
            })

            if BarCfg().customBorder == true and BORDER_SYNCS[barId] then
                DataBarSyncIcon(
                    lRgn,
                    barId,
                    "Apply Border Style to all Rep Bars",
                    CopyDataBarStyle,
                    SameDataBarStyle
                )
                DataBarSyncIcon(
                    brdRow._rightRegion,
                    barId,
                    "Apply Border Size and Color to all Rep Bars",
                    CopyDataBarSize,
                    SameDataBarSize
                )
            end
        end
        return cursorY
    end

    -- Width | Height. The ranges follow the orientation (a flip rebuilds the
    -- page): the bar's length runs up to the screen's width (Width,
    -- horizontal) or height (Height, vertical), its thickness up to 100. A
    -- size set outside them elsewhere (Unlock Mode, a size match) shows at the
    -- nearest end of its slider.
    function K.SizeRow(cursorY, barId)
        local _, height
        local function BarCfg() return ABAR.db.profile.bars[barId] end
        local wDis, wTip, wRaw = CUI.MatchGuard(barId, "Width", _blizzDataBarsOn, BLIZZ_DIS_TIP)
        local hDis, hTip, hRaw = CUI.MatchGuard(barId, "Height", _blizzDataBarsOn, BLIZZ_DIS_TIP)
        local _dbVert = (BarCfg().orientation == "VERTICAL")
        local _dbLenMax = math.floor(_dbVert and UIParent:GetHeight() or UIParent:GetWidth())
        local _dbWMin, _dbWMax = (_dbVert and 4 or 50), (_dbVert and 100 or _dbLenMax)
        local _dbHMin, _dbHMax = (_dbVert and 50 or 4), (_dbVert and _dbLenMax or 100)
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "slider",
            text = "Width",
            min = _dbWMin,
            max = _dbWMax,
            step = 1,
            disabled = wDis,
            disabledTooltip = wTip,
            rawTooltip = wRaw,
            getValue = function() return BarCfg().width or 400 end,
            setValue = function(val)
                BarCfg().width = val
                mod.ApplyDataBarLayout(barId)
            end,
        }, {
            type = "slider",
            text = "Height",
            min = _dbHMin,
            max = _dbHMax,
            step = 1,
            disabled = hDis,
            disabledTooltip = hTip,
            rawTooltip = hRaw,
            getValue = function() return BarCfg().height or 18 end,
            setValue = function(val)
                BarCfg().height = val
                mod.ApplyDataBarLayout(barId)
            end,
        })
        cursorY = cursorY - height
        return cursorY
    end

    -- The fill colour swatches of a bar's Color control: Custom, Accent and
    -- Reactive (Default), the active one bright (multiSwatch or inline).
    function K.ColorSwatches(barId)
        local function BarCfg() return ABAR.db.profile.bars[barId] end
        local rp = REACTIVE_PREVIEW[barId] or { 1, 1, 1 }
        return {
            {
                tooltip = "Custom Color",
                getValue = function()
                    local color = BarCfg().customColor
                    if color then return color.r or 1, color.g or 1, color.b or 1 end
                    return 1, 1, 1
                end,
                setValue = function(red, green, blue)
                    BarCfg().customColor = { r = red, g = green, b = blue }
                    BarCfg().colorMode = "custom"
                    RefreshDataBar(barId)
                end,
                onClick = function(self)
                    if BarCfg().colorMode ~= "custom" then
                        BarCfg().colorMode = "custom"
                        RefreshDataBar(barId)
                        CUI:RefreshPage()
                        return
                    end
                    if self._eabOrigClick then self._eabOrigClick(self) end
                end,
                refreshAlpha = function() return BarCfg().colorMode == "custom" and 1 or 0.3 end,
            },
            {
                tooltip = "Accent Color",
                getValue = function()
                    local ACC = CUI.CLUDES_GREEN
                    if ACC then return ACC.r or 0.298, ACC.g or 0.788, ACC.b or 0.941 end
                    return 0.298, 0.788, 0.941
                end,
                setValue = function() end,
                onClick = function()
                    BarCfg().colorMode = "accent"
                    RefreshDataBar(barId)
                    CUI:RefreshPage()
                end,
                refreshAlpha = function() return BarCfg().colorMode == "accent" and 1 or 0.3 end,
            },
            {
                tooltip = "Reactive (Default)",
                getValue = function() return rp[1], rp[2], rp[3] end,
                setValue = function() end,
                onClick = function()
                    BarCfg().colorMode = nil
                    RefreshDataBar(barId)
                    CUI:RefreshPage()
                end,
                refreshAlpha = function()
                    local m = BarCfg().colorMode
                    return (m ~= "custom" and m ~= "accent") and 1 or 0.3
                end,
            },
        }
    end

    function K.TexCfg(barId)
        local function BarCfg() return ABAR.db.profile.bars[barId] end
        return {
            type = "dropdown",
            text = "Bar Texture",
            values = dbTexValues,
            order = dbTexOrder,
            disabled = _blizzDataBarsOn,
            disabledTooltip = BLIZZ_DIS_TIP,
            rawTooltip = true,
            getValue = function() return BarCfg().barTexture or "none" end,
            setValue = function(val)
                BarCfg().barTexture = val
                mod.ApplyDataBarLayout(barId)
            end,
        }
    end

    function K.ClickThroughCfg(barId)
        local function BarCfg() return ABAR.db.profile.bars[barId] end
        return {
            type = "toggle",
            text = "Click Through",
            getValue = function() return BarCfg().clickThrough end,
            setValue = function(val)
                BarCfg().clickThrough = val
                ABAR:ApplyClickThroughForBar(barId)
            end,
        }
    end
    -- The same toggle as a cog row (the XP bar's Visibility cog).
    function K.ClickThroughRow(barId)
        local rowConf = K.ClickThroughCfg(barId)
        return { type = "toggle", label = rowConf.text, get = rowConf.getValue, set = rowConf.setValue }
    end

    function K.TextSizeCfg(barId)
        local function BarCfg() return ABAR.db.profile.bars[barId] end
        return {
            type = "slider",
            text = "Text Size",
            min = 6,
            max = 24,
            step = 1,
            disabled = _blizzDataBarsOn,
            disabledTooltip = BLIZZ_DIS_TIP,
            rawTooltip = true,
            getValue = function() return BarCfg().textSize or 9 end,
            setValue = function(val)
                BarCfg().textSize = val
                mod.ApplyDataBarLayout(barId)
            end,
        }
    end

    -- The Bar Text Offsets cog on a Text Size control: the anchor and
    -- offsets, then extraRows (the XP bar text's Show Rested).
    function K.TextCog(regionFrame, barId, extraRows)
        if CUI._prebuilding then return end
        local function BarCfg() return ABAR.db.profile.bars[barId] end
        local textRows = {
            {
                type = "dropdown",
                label = "Anchor",
                tooltip = "Where the bar text sits inside the bar; the offsets nudge it from there.",
                values = { center = "Center", top = "Top", bottom = "Bottom", left = "Left", right = "Right" },
                order = { "center", "top", "bottom", "left", "right" },
                get = function() return BarCfg().textAnchor or "center" end,
                set = function(val)
                    BarCfg().textAnchor = val
                    mod.ApplyDataBarLayout(barId)
                end,
            },
            {
                type = "slider",
                label = "X Offset",
                min = -150,
                max = 150,
                step = 1,
                get = function() return BarCfg().textOffsetX or 0 end,
                set = function(val)
                    BarCfg().textOffsetX = val
                    mod.ApplyDataBarLayout(barId)
                end,
            },
            {
                type = "slider",
                label = "Y Offset",
                min = -150,
                max = 150,
                step = 1,
                get = function() return BarCfg().textOffsetY or 0 end,
                set = function(val)
                    BarCfg().textOffsetY = val
                    mod.ApplyDataBarLayout(barId)
                end,
            },
        }
        if extraRows then
            for _, r in ipairs(extraRows) do
                textRows[#textRows + 1] = r
            end
        end
        CUI.BuildInlineCog(regionFrame, {
            anchorTo = regionFrame._control,
            title = "Bar Text Offsets",
            disabled = _blizzDataBarsOn,
            disabledTooltip = BLIZZ_DIS_TIP,
            rawTooltip = true,
            rows = textRows,
        })
    end

    -- One data bar's section (the Menu, Bags & Rep Bars page): lead's rows
    -- (optional, lead(y) -> y; built even while Never), Visibility | Custom
    -- Border, its border rows while on, Width | Height, Color | Bar Texture,
    -- Click Through | Text Size. While Never only the rows up to Visibility
    -- are built. Returns the new y and the Visibility row.
    function K.Section(cursorY, barId, sectionTitle, visLabel, lead)
        local _, height, heading
        local function BarCfg() return ABAR.db.profile.bars[barId] end

        heading, height = W:SectionHeader(hostFrame, sectionTitle, cursorY)
        cursorY = cursorY - height
        -- The Move in Unlock Mode button on this bar's section: greyed while
        -- Blizzard's bars are in use, since our bar (and its mover) is not built then.
        CUI.BuildSectionUnlockJump(
            heading,
            { key = barId, disabled = _blizzDataBarsOn, disabledTooltip = BLIZZ_DIS_TIP, rawTooltip = true }
        )
        if lead then cursorY = lead(cursorY) end
        -- Custom Border, the opt-in for this bar's own border style, size and
        -- color, fills the Visibility row's free slot. Its rows below are built
        -- only while it is on (the toggle rebuilds the page). Left out while
        -- Never, so that section keeps its lone Visibility row.
        local customCfg
        if not BarIsNever(barId) then
            customCfg = {
                type = "toggle",
                text = "Custom Border",
                tooltip = "Draws this bar's border in your own border style, size and color instead of the thin black line.",
                disabled = _blizzDataBarsOn,
                disabledTooltip = BLIZZ_DIS_TIP,
                rawTooltip = true,
                getValue = function() return BarCfg().customBorder or false end,
                setValue = CUI.SectionToggleSetValue(function(val)
                    BarCfg().customBorder = val and true or false
                    mod.ApplyDataBarLayout(barId)
                end),
            }
        end
        local visRow
        visRow, cursorY = K.VisRow(cursorY, barId, visLabel, customCfg)
        if BarIsNever(barId) then return cursorY, visRow end

        if BarCfg().customBorder then cursorY = K.BorderRows(cursorY, barId) end
        cursorY = K.SizeRow(cursorY, barId)
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            { type = "multiSwatch", text = "Color", swatches = K.ColorSwatches(barId) },
            K.TexCfg(barId)
        )
        cursorY = cursorY - height
        local textRow
        textRow, height = W:DualRow(hostFrame, cursorY, K.ClickThroughCfg(barId), K.TextSizeCfg(barId))
        cursorY = cursorY - height
        K.TextCog(textRow._rightRegion, barId)
        return cursorY, visRow
    end
    return K
end

-- Used by XPBarPage_Options.lua (at page build)
mod.ABO_DataBarKit = DataBarKit

---------------------------------------------------------------------------
--  Menu, Bags & Rep Bars page  (dedicated tab)
---------------------------------------------------------------------------

local function BuildMenuBagsRepPage(page, hostFrame, yOffset)
    local environ = mod._ABO_OptEnv
    local ABAR, EndCapsCtl = environ.EAB, environ.EndCapsCtl
    local W = CUI.Widgets
    local K = DataBarKit(hostFrame)
    local VisibilityOptions = K.VisOpts
    local cursorY = yOffset
    local _, height

    -- Global settings page, no bar selector header
    CUI:ClearContentHeader()
    hostFrame._showRowDivider = true

    -------------------------------------------------------------------
    --  MICRO MENU & BAGS
    -------------------------------------------------------------------
    _, height = W:SectionHeader(hostFrame, "MICRO MENU & BAGS", cursorY)
    cursorY = cursorY - height
    -- Both bars' Visibility in ONE row: same kind of control, and pairing them
    -- leaves no half-empty slot behind now that Visibility Options is folded in.
    do
        local microOpts = VisibilityOptions("MicroBar", "Micro Menu Visibility")
        microOpts.rightVis = VisibilityOptions("BagBar", "Bag Bar Visibility")
        _, height = CUI.BuildVisibilityRow(W, hostFrame, cursorY, microOpts)
        cursorY = cursorY - height
    end
    -- Their skins: the Blizzard Skins+ Micro Menu and Bag Bar cards' style,
    -- mirrored (one setting; none while that module is off, and no Bag Bar
    -- skin off WoW Forever). Then their end caps, as an action bar's (sized
    -- from Action Bar 1's buttons; no Apply to All link: a first-install span
    -- makes the two differ on purpose). Without the Bag Bar skin the slots
    -- fill in order, so no blank is left mid-section.
    do
        local SkinCfg = CUI.WindowSkinStyleCfg
        local microSkin = SkinCfg
            and SkinCfg(
                "micromenu",
                "Micro Menu Skin",
                "Same setting as the Micro Menu card on Window Skins > Window Skins."
            )
        local bagSkin = SkinCfg
            and SkinCfg(
                "bagbar",
                "Bag Bar Skin",
                "Same setting as the Bag Bar card on Window Skins > Window Skins."
            )
        local function Ctl(key, labelText)
            return EndCapsCtl({
                key = function() return key end,
                store = function() return ABAR.db.profile.bars[key] end,
                label = labelText,
                vertical = function() return mod.AB_ExtraCapsVertical(key) end,
                write = function(keyName, val)
                    if keyName then ABAR.db.profile.bars[key][keyName] = val end
                    mod.AB_ExtraCaps(key)
                    CUI:RefreshPage()
                end,
            })
        end
        local mc, bc = Ctl("MicroBar", "Micro Menu End Caps"), Ctl("BagBar", "Bag Bar End Caps")
        local row
        if microSkin and bagSkin then
            _, height = W:DualRow(hostFrame, cursorY, microSkin, bagSkin)
            cursorY = cursorY - height
        end
        if microSkin and not bagSkin then
            row, height = W:DualRow(hostFrame, cursorY, microSkin, mc.Cfg())
            cursorY = cursorY - height
            mc.Build(row._rightRegion)
            row, height = W:DualRow(hostFrame, cursorY, bc.Cfg(), CUI.BlankRowCfg())
            cursorY = cursorY - height
            bc.Build(row._leftRegion)
        else
            row, height = W:DualRow(hostFrame, cursorY, mc.Cfg(), bc.Cfg())
            cursorY = cursorY - height
            mc.Build(row._leftRegion)
            bc.Build(row._rightRegion)
        end
    end

    _, height = W:Spacer(hostFrame, cursorY, 12)
    cursorY = cursorY - height

    -------------------------------------------------------------------
    --  REPUTATION BAR / HOUSE FAVOR BAR
    -------------------------------------------------------------------
    -- The Reputation Bar section opens with Use Blizzard's Rep Bars, the one
    -- saved switch for Blizzard's XP, reputation and House Favor bars (shared
    -- with the XP Bar page's Style, its Blizz Default) | Orientation, which
    -- flips the reputation and House Favor bars together.
    cursorY = K.Section(cursorY, "RepBar", "REPUTATION BAR", "Rep Bar Visibility", function(ry)
        return K.StyleRow(ry, {
            type = "toggle",
            text = "Use Blizzard's Rep Bars",
            tooltip = "Tied to the XP bar: Blizzard's XP and reputation bars switch together, so this also sets the XP Bar style to Blizz Default.",
            getValue = function() return ABAR.db.profile.useBlizzardDataBars end,
            setValue = function(val) K.AfterSwitch(mod.SetUseBlizzardDataBars(val)) end,
        }, { "RepBar", "FavorBar" })
    end)
    if not CUI.IS_FOREVER then
        _, height = W:Spacer(hostFrame, cursorY, 12)
        cursorY = cursorY - height
        cursorY = K.Section(cursorY, "FavorBar", "HOUSE FAVOR BAR", "Favor Bar Visibility")
    end -- not IS_FOREVER

    _, height = W:Spacer(hostFrame, cursorY, 12)
    cursorY = cursorY - height

    -------------------------------------------------------------------
    --  VEHICLE BAR
    -------------------------------------------------------------------
    _, height = W:SectionHeader(hostFrame, "VEHICLE BAR", cursorY)
    cursorY = cursorY - height

    _, height = W:DualRow(hostFrame, cursorY, {
        type = "toggle",
        text = "Hide Blizzard's Vehicle Bar",
        getValue = function() return ABAR.db.profile.hideBlizzardVehicleBar end,
        setValue = function(val)
            ABAR.db.profile.hideBlizzardVehicleBar = val
            if ABAR.UpdateVehicleBarWatch then ABAR:UpdateVehicleBarWatch() end
            CUI:RefreshPage()
        end,
        tooltip = "Hide Blizzard's stock vehicle and override bar.",
    }, { type = "label", text = "" })
    cursorY = cursorY - height

    return math.abs(cursorY)
end

-- Used by CUI_ActionBars_Options.lua
mod.ABO_BuildMenuBagsRepPage = BuildMenuBagsRepPage
