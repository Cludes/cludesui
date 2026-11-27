if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  Nameplates_Options\DisplayLayout_Options.lua
--  Nameplates options: the Style, Core Positions and Core Text Positions
--  sections of the Display page. Called by BuildDisplayPage; returns y, the
--  rows and text cells its click navigation maps to, and the cog popup and
--  texture helpers DisplayBars_Options.lua uses. The Core Text Coloring
--  section under Core Text Positions lives in CoreTextColoring_Options.lua
--  (called from here; it reads the text slot table defined below). Shared
--  helpers come from ns._NPO_OptEnv, the per-build slot helpers from ctx.
-------------------------------------------------------------------------------
local mod = CludesUI._ModuleNS["CludesUINameplates"]
if not mod then return end -- module disabled: no options page

-- The options page frame pool (CludesUI_FramePool.lua): frames made under a
-- pooled page part are handed back to the page's next build.
local CreateFrame = CludesUI._Pool.CreateFrame
local PoolGen = CludesUI._Pool.Gen

-- Core Text Positions. KNOWN: the elements a text position draws; any other
-- saved value (None, unset, one this build does not know) shows nothing and
-- leaves the position free.
local KNOWN = {
    enemyName = true,
    levelName = true,
    nameLevel = true,
    level = true,
    targetOfTarget = true,
    healthPercent = true,
    healthPercentNoSign = true,
    healthNumber = true,
    healthPctNum = true,
    healthNumPct = true,
    healthPctNumDash = true,
    healthNumPctDash = true,
    healthNumMax = true,
    custom = true,
}
-- Add Text Slot's text: the first of these whose font string no shown text
-- uses (one per font string: name, health %, level, health #, Target of
-- Target).
local ADD_ORDER = { "enemyName", "healthPercent", "level", "healthNumber", "targetOfTarget" }
-- Keys a moved text takes along: as saved (MOVE_RAW), and as the difference
-- from each position's default (MOVE_OFFSETS). Its Size and colour mode go
-- along through MoveText too.
local MOVE_RAW = {
    "Strata",
    "Color",
    "NameColorOn",
    "NameColor",
    "LevelColorOn",
    "LevelColor",
    "LevelDiffOn",
    "WidthPct",
    "Wrap",
    "PctDecimal",
    "NameFormat",
    "CustomFormat",
}
local MOVE_OFFSETS = { "XOffset", "YOffset" }

-- The eight text positions, in the order of the Core Text Positions list, its
-- position menus and the Core Text Coloring section (CoreTextColoring_Options.lua
-- reads this table at build time).
mod.NPO_TEXT_SLOTS = {
    {
        key = "textSlotTop",
        label = "Top Text",
        menu = "Top",
        coloring = "Top Text Coloring",
    },
    {
        key = "textSlotTopLeft",
        label = "Top Left Text",
        menu = "Top Left",
        coloring = "Top Left Text Coloring",
    },
    {
        key = "textSlotTopRight",
        label = "Top Right Text",
        menu = "Top Right",
        coloring = "Top Right Text Coloring",
    },
    {
        key = "textSlotRight",
        label = "Right Text",
        menu = "Right",
        coloring = "Right Text Coloring",
    },
    {
        key = "textSlotLeft",
        label = "Left Text",
        menu = "Left",
        coloring = "Left Text Coloring",
    },
    {
        key = "textSlotCenter",
        label = "Center Text",
        menu = "Center",
        coloring = "Center Text Coloring",
    },
    {
        key = "textSlotBottomLeft",
        label = "Bottom Left Text",
        menu = "Bottom Left",
        coloring = "Bottom Left Text Coloring",
    },
    {
        key = "textSlotBottomRight",
        label = "Bottom Right Text",
        menu = "Bottom Right",
        coloring = "Bottom Right Text Coloring",
    },
}
local POS_ORDER, POS_VALUES = {}, {}
for idx = 1, #mod.NPO_TEXT_SLOTS do
    local cfg = mod.NPO_TEXT_SLOTS[idx]
    POS_ORDER[idx] = cfg.key
    POS_VALUES[cfg.key] = cfg.menu
end

-- Custom text popup for a text position: the template is stored in
-- <slot>CustomFormat, then onSave selects Custom for the position.
function mod.NPO_EditCustomText(slotKey, onSave)
    local environ = mod._NPO_OptEnv
    local key = slotKey .. "CustomFormat"
    -- The slot's colour as the nameplate preview paints it (Text Coloring mode),
    -- copied: the level colour is a reused table.
    local color = mod.NPO_PreviewSlotColor(slotKey)
    CludesUI.TextTags.EditPopup({
        cat = mod.NP_TextTags,
        color = color and { r = color.r, g = color.g, b = color.b },
        onSave = onSave,
        tagNotes = { hp = CludesUI.L("shows DEAD") },
        get = function() return environ.DB()[key] end,
        set = function(txt) environ.DB()[key] = txt end,
    })
end

-- A copy of the text dropdown's values whose Custom entry is an action that opens
-- the popup (edit), its pencil at full alpha while getValue() is "custom" (the menu
-- reads it when built; a selection rebuilds the page); Remove in the house red.
function mod.NPO_CustomTextValues(values, getValue, edit)
    return CludesUI.TextTags.MenuValues(values, edit, {
        removeKey = "none",
        selected = function() return getValue() == "custom" end,
    })
end

-- A position shows a text while its element is a KNOWN one.
function mod.NPO_TextSlotShown(slotKey) return KNOWN[mod._NPO_OptEnv.DBVal(slotKey)] == true end

-- The texts' structure: each position's element and, for a shown text, its
-- colour mode (which decides its Core Text Coloring controls). Taken at each
-- page build; a cached Display page whose structure changed behind it is
-- rebuilt on restore (CUI_Nameplates_Options.lua, onPageCacheRestore).
function mod.NPO_TextStructureFP()
    local environ = mod._NPO_OptEnv
    local DbValue, saved = environ.DBVal, environ.DB()
    local parts = {}
    for idx = 1, #POS_ORDER do
        local key = POS_ORDER[idx]
        local el = DbValue(key)
        parts[#parts + 1] = tostring(el)
        if KNOWN[el] then parts[#parts + 1] = mod.NP_SlotColorMode(key, saved) end
    end
    return table.concat(parts, "\31")
end

-- The Display page cog popup and the cog icon that owns it: built on the first
-- cog click and kept across page builds (ShowCogPopup below). cogPopupOwnerGen:
-- the owner's dress when it opened the popup (page reuse dresses the same button
-- again for a later build, which then is a new owner).
local cogPopup, cogPopupOwner, cogPopupOwnerGen

-- The cog that opened the popup, while it is still the dress that opened it.
local function LiveCogOwner()
    if cogPopupOwner and PoolGen(cogPopupOwner) == cogPopupOwnerGen then return cogPopupOwner end
end

-- True once the cog that opened the popup no longer stands for it: a later
-- page build dressed it again (for its element or another one), left it idle
-- or dropped the row it sits in. The popup would edit one element from
-- another one's control, or hang off a hidden frame, so it closes. A cog made
-- outside the page pool (every page while page reuse is off) has no
-- generation and never closes here.
local function CogOwnerGone()
    local ownerFrame = cogPopupOwner
    if not ownerFrame then return false end
    local g = PoolGen(ownerFrame)
    if g == nil and cogPopupOwnerGen == nil then return false end
    return g ~= cogPopupOwnerGen or not ownerFrame:IsVisible()
end

local function BuildDisplayLayout(hostFrame, cursorY, context)
    local environ = mod._NPO_OptEnv
    local DB, DbValue, defaultSet, GetNPOptOutline =
        environ.DB, environ.DBVal, environ.defaults, environ.GetNPOptOutline
    local hbtOrder, hbtValues, optionState, pairs =
        environ.hbtOrder, environ.hbtValues, environ.optState, environ.pairs
    local plates, Pix, RepaintPreview, RedrawPlates =
        environ.plates, environ.PP, environ.UpdatePreview, environ.RefreshAllPlates
    local GetElementAtPosition, RefreshAllSlots, SetElementAtPosition, SetTextElementAtSlot =
        context.GetElementAtPosition,
        context.RefreshAllSlots,
        context.SetElementAtPosition,
        context.SetTextElementAtSlot
    local W = context.W
    local _, height
    -- This build of the page (the serial moves after every page pass; page reuse
    -- keeps one wrapper, so the wrapper cannot tell two builds apart).
    local buildSerial = CludesUI._pageBuildSerial or 0

    -----------------------------------------------------------------------
    --  STYLE
    -----------------------------------------------------------------------
    local styleHeader
    styleHeader, height = W:SectionHeader(hostFrame, "STYLE", cursorY)
    cursorY = cursorY - height
    cursorY = CludesUI.BlizzStyle.Note(hostFrame, cursorY, "nameplates")

    local function RedrawTextures()
        mod.RefreshAllSettings()
        for _, backing in pairs(mod.friendlyPlates or {}) do
            if mod.ApplyHealthBarTexture then mod.ApplyHealthBarTexture(backing) end
            if mod.ApplyCastBarTexture then mod.ApplyCastBarTexture(backing) end
        end
    end

    -- Row 1: Border (None/Basic/Custom) | Border Size. Pure VIEW over showBorder + customBorderEnabled: None=off, Basic=standard border, Custom=custom border engine (reveals the Custom Border row below via page rebuild; None/Basic collapse it).
    -- Both stock styles gate both slots: they draw their own art (the stock background, the vanilla border sheets) and stand every CUI border down.
    local borderStyleRow
    borderStyleRow, height = W:DualRow(
        hostFrame,
        cursorY,
        CludesUI.BlizzStyle.Gate("nameplates", {
            type = "segmented",
            text = "Border",
            values = { none = "None", basic = "Basic", custom = "Custom" },
            order = { "none", "basic", "custom" },
            getValue = function()
                if DbValue("customBorderEnabled") then return "custom" end
                local scrollBar = DbValue("showBorder")
                if scrollBar == nil then scrollBar = defaultSet.showBorder end
                return scrollBar and "basic" or "none"
            end,
            setValue = function(val)
                if val == "custom" then
                    DB().customBorderEnabled = true
                elseif val == "basic" then
                    DB().customBorderEnabled = false
                    DB().showBorder = true
                else
                    DB().customBorderEnabled = false
                    DB().showBorder = false
                end
                mod.RefreshBorder()
                mod.RefreshBorderColor()
                RepaintPreview()
                -- Force rebuild so the Custom Border row shows/hides and rows below reflow.
                CludesUI:RefreshPage(true)
            end,
        }, CludesUI.BlizzStyle.Active("nameplates") == "classic"),
        CludesUI.BlizzStyle.Gate("nameplates", {
            type = "slider",
            text = "Border Size",
            min = 1,
            max = 4,
            step = 1,
            -- Only Basic uses this size (None has no border; Custom uses its own Custom Border Size below).
            disabled = function()
                if DbValue("customBorderEnabled") then return true end
                local val = DbValue("showBorder")
                if val == nil then return not defaultSet.showBorder end
                return not val
            end,
            disabledTooltip = "This option is only used by the Basic border.",
            rawTooltip = true,
            getValue = function() return DbValue("borderSize") or defaultSet.borderSize end,
            setValue = function(val)
                DB().borderSize = val
                mod.RefreshBorder()
                RepaintPreview()
            end,
        })
    )
    cursorY = cursorY - height
    -- Corner Radius (CludesUI_RoundedCorners.lua): an inline cog on the
    -- border size control. The stock styles keep every plate square, and so
    -- does Wrap Around Castbar (the plates stand rounding down while it is on).
    if not CludesUI._prebuilding then
        CludesUI.BuildInlineCog(borderStyleRow._rightRegion, {
            title = "Corner Radius",
            tip = "Corner Radius",
            disabled = function()
                if CludesUI.BlizzStyle.Get("nameplates") then return true end
                if DbValue("wrapBorderCastbar") == true then return true end
                return DbValue("customBorderEnabled")
                    and not CludesUI.RoundedStyleOK(
                        DbValue("customBorderTexture") or defaultSet.customBorderTexture
                    )
            end,
            disabledTooltip = function()
                if CludesUI.BlizzStyle.Get("nameplates") then
                    return CludesUI.BlizzStyle.Label("nameplates")
                end
                if DbValue("wrapBorderCastbar") == true then return "Wrap Around Castbar" end
                return "This option requires the Solid, Glow or Shadow border style."
            end,
            requireState = "disabled",
            rows = CludesUI.RoundedJoinRow(
                CludesUI.RoundedCornerRows({
                    {
                        type = "slider",
                        label = "Corner Radius",
                        min = 0,
                        max = CludesUI.ROUNDED_MAX_RADIUS,
                        step = 1,
                        get = function() return DbValue("cornerRadius") or 0 end,
                        set = function(val)
                            DB().cornerRadius = val
                            mod.RefreshBorder()
                            mod.RefreshCastBorder()
                            RepaintPreview()
                        end,
                    },
                }, function() return DbValue("cornerMask") end, function(val)
                    DB().cornerMask = val
                    mod.RefreshBorder()
                    mod.RefreshCastBorder()
                    RepaintPreview()
                end),
                "Join Cast Bar",
                "While a cast shows, rounds the health bar and the cast bar under it as one shape.",
                function() return DbValue("cornerJoinCast") end,
                function(val)
                    DB().cornerJoinCast = val
                    mod.RefreshBorder()
                    mod.RefreshCastBorder()
                    RepaintPreview()
                end
            ),
        })
    end
    -- Inline cog on the Border region: opt-in "Wrap Around Castbar" (beside the control; the colour swatch sits left of it); dimmed only for "None" mode (wrap applies to both Basic and Custom).
    if not CludesUI._prebuilding then
        local leftRegion = borderStyleRow._leftRegion
        local function wrapCogOff()
            -- Only "None" disables it; Basic and Custom both support the wrap.
            -- Neither stock style has an CUI border to wrap: Blizzard Style
            -- draws the stock background art, Classic WoW UI the vanilla
            -- border sheets, and both stand the CUI borders down.
            if mod.NP_Blizz() then return true end
            if DbValue("customBorderEnabled") then return false end
            local val = DbValue("showBorder")
            if val == nil then val = defaultSet.showBorder end
            return not val
        end
        local wrapRows = {
            {
                type = "toggle",
                label = "Wrap Around Castbar",
                -- Classic WoW UI draws the vanilla borders: nothing to wrap.
                disabled = function() return CludesUI.BlizzStyle.Active("nameplates") == "classic" end,
                disabledTooltip = function() return CludesUI.BlizzStyle.Label("nameplates") end,
                requireState = "disabled",
                get = function()
                    local val = DbValue("wrapBorderCastbar")
                    if val == nil then return defaultSet.wrapBorderCastbar end
                    return val
                end,
                set = function(val)
                    DB().wrapBorderCastbar = val
                    -- Unconditional re-apply so toggling OFF also unwraps any plate mid-cast and wrapped.
                    mod.ApplyBorderWrapToAll()
                    -- Corner Radius stands down while the wrap is on: square or re-round the plates.
                    if (DbValue("cornerRadius") or 0) > 0 then
                        mod.RefreshBorder()
                        mod.RefreshCastBorder()
                    end
                    RepaintPreview()
                    -- Show Seam Line's and Corner Radius's disabled states follow this toggle.
                    CludesUI:RefreshPage()
                end,
            },
        }
        -- Show Seam Line: the custom border's wrap only, so it is built only while
        -- Border = Custom (the Border setter rebuilds the page).
        if DbValue("customBorderEnabled") then
            wrapRows[#wrapRows + 1] = {
                type = "toggle",
                label = "Show Seam Line",
                tooltip = "Draws the border style's seam line between the health and cast bars.",
                disabled = function()
                    return DbValue("wrapBorderCastbar") ~= true
                        or not mod.NP_CanShowWrapSeam(
                            DbValue("customBorderTexture") or defaultSet.customBorderTexture
                        )
                end,
                -- Wrap off: the standard requirement line; wrap on: the style is the lock.
                disabledTooltip = function()
                    if DbValue("wrapBorderCastbar") ~= true then return "Wrap Around Castbar" end
                    return "This option requires the Pixels or Pixels Textured border style."
                end,
                rawTooltip = function() return DbValue("wrapBorderCastbar") == true end,
                get = function() return DbValue("wrapBorderSeam") == true end,
                set = function(val)
                    DB().wrapBorderSeam = val
                    mod.ApplyBorderWrapToAll()
                    RepaintPreview()
                end,
            }
        end
        CludesUI.BuildInlineCog(leftRegion, {
            disabled = wrapCogOff,
            disabledTooltip = "This option requires a Border to be selected",
            title = "Castbar Border",
            rows = wrapRows,
        })
    end

    -- Inline swatch on the Border dropdown: standard (Basic) border color, dimmed unless mode is Basic.
    if not CludesUI._prebuilding then
        local leftRegion = borderStyleRow._leftRegion
        local function isBorderOff()
            -- Off for None and Custom (standard border/color is inert then) -- only Basic uses it.
            if CludesUI.BlizzStyle.Get("nameplates") then return true end
            if DbValue("customBorderEnabled") then return true end
            local val = DbValue("showBorder")
            if val == nil then return not defaultSet.showBorder end
            return not val
        end
        local borderColorGet = function()
            local color = (DB() and DB().borderColor) or defaultSet.borderColor
            return color.r, color.g, color.b
        end
        local borderColorSet = function(red, green, blue)
            DB().borderColor = { r = red, g = green, b = blue }
            mod.RefreshBorderColor()
            RepaintPreview()
        end
        local colorSwatch, updateSwatch = CludesUI.BuildColorSwatch(
            leftRegion,
            leftRegion:GetFrameLevel() + 5,
            borderColorGet,
            borderColorSet,
            nil,
            20
        )
        Pix.Point(colorSwatch, "RIGHT", leftRegion._lastInline or leftRegion._control, "LEFT", -8, 0)
        leftRegion._lastInline = colorSwatch
        CludesUI.RegisterWidgetRefresh(function()
            local off = isBorderOff()
            colorSwatch:SetAlpha(off and 0.15 or 1)
            colorSwatch:EnableMouse(not off)
            updateSwatch()
        end)
        local off = isBorderOff()
        colorSwatch:SetAlpha(off and 0.15 or 1)
        colorSwatch:EnableMouse(not off)
    end

    -- Classic WoW UI only: the level, and the icon that replaces it on a
    -- boss, both seated in the health border's own plate. Each follows
    -- the bar's height until sized here, and each carries its X/Y nudges
    -- on an inline cog. Not built at all on the other styles, where there
    -- is no plate to fill; the if-body scopes its locals.
    if CludesUI.BlizzStyle.Active("nameplates") == "classic" then
        local classicPlateRow
        classicPlateRow, height = W:DualRow(hostFrame, cursorY, {
            type = "slider",
            text = "Level Size",
            min = 0,
            max = 40,
            step = 1,
            tooltip = "Size of the level in the border's plate. 0 follows the bar height.",
            getValue = function() return DbValue("classicLevelSize") or 0 end,
            setValue = function(val)
                DB().classicLevelSize = val
                mod.RefreshAllSettings()
                RepaintPreview()
            end,
        }, {
            type = "slider",
            text = "Elite Icon Size",
            min = 0,
            max = 40,
            step = 1,
            tooltip = "Size of the icon that replaces the level on a boss. 0 follows the bar height.",
            getValue = function() return DbValue("classicSkullSize") or 0 end,
            setValue = function(val)
                DB().classicSkullSize = val
                mod.RefreshAllSettings()
                RepaintPreview()
            end,
        })
        cursorY = cursorY - height
        -- Reached by the preview's click navigation (the level in the
        -- border's plate scrolls here), which is built further down.
        hostFrame._classicPlateRow = classicPlateRow
        if not CludesUI._prebuilding then
            local function PlateOffsetCog(region, title, xKey, yKey)
                CludesUI.BuildInlineCog(region, {
                    title = title,
                    rows = {
                        {
                            type = "slider",
                            label = "X Offset",
                            min = -50,
                            max = 50,
                            step = 1,
                            get = function() return DbValue(xKey) or 0 end,
                            set = function(val)
                                DB()[xKey] = val
                                mod.RefreshAllSettings()
                                RepaintPreview()
                            end,
                        },
                        {
                            type = "slider",
                            label = "Y Offset",
                            min = -50,
                            max = 50,
                            step = 1,
                            get = function() return DbValue(yKey) or 0 end,
                            set = function(val)
                                DB()[yKey] = val
                                mod.RefreshAllSettings()
                                RepaintPreview()
                            end,
                        },
                    },
                })
            end
            PlateOffsetCog(classicPlateRow._leftRegion, "Level Position", "classicLevelX", "classicLevelY")
            PlateOffsetCog(
                classicPlateRow._rightRegion,
                "Elite Icon Position",
                "classicSkullX",
                "classicSkullY"
            )
        end
    end

    -- Custom Border row: only built when Border dropdown = "Custom" (selecting it triggers a page rebuild that reveals this row and reflows rows below;
    -- None/Basic collapse it). Uses the shared border engine (identical to Unit Frames, full SharedMedia support); the if-body scopes its locals to avoid growing this builder's local count.
    if DbValue("customBorderEnabled") then
        -- Custom Border Style dropdown (+ options cog) | Custom Border Size (+ color swatch)
        local cbTexValues, cbTexOrder = CludesUI.GetBorderTextureDropdown()
        local customBorderRow
        customBorderRow, height = W:DualRow(
            hostFrame,
            cursorY,
            CludesUI.BlizzStyle.Gate("nameplates", {
                type = "dropdown",
                text = "Custom Border Style",
                values = cbTexValues,
                order = cbTexOrder,
                getValue = function() return DbValue("customBorderTexture") or defaultSet.customBorderTexture end,
                setValue = function(val)
                    DB().customBorderTexture = val
                    DB().customBorderOffset = nil
                    DB().customBorderOffsetY = nil
                    DB().customBorderShiftX = nil
                    DB().customBorderShiftY = nil
                    local _bcol, _bbehind = CludesUI.GetBorderStyleSelectDefaults(val)
                    DB().customBorderColor = _bcol
                    DB().customBorderAlpha = 1
                    DB().customBorderBehind = _bbehind
                    local defSz = CludesUI.GetBorderDefaultSize("nameplates", val)
                    if defSz then DB().customBorderSize = defSz end
                    if DB().customBorderSizePx then DB().customBorderSizePx = false end
                    mod.RefreshBorder()
                    RepaintPreview()
                    -- Full rebuild: the Width/Height Offset row below exists only for a textured style.
                    CludesUI:RefreshPage(true)
                end,
            }),
            CludesUI.BlizzStyle.Gate(
                "nameplates",
                CludesUI.BorderPxSliderCfg({
                    -- Narrower track: the slot also carries the colour swatch and the Icon Borders cog.
                    text = "Custom Border Size",
                    trackWidth = 120,
                    getStep = function() return DbValue("customBorderSize") or defaultSet.customBorderSize end,
                    setStep = function(step) DB().customBorderSize = step end,
                    getTex = function() return DbValue("customBorderTexture") or defaultSet.customBorderTexture end,
                    getPx = function() return DB() and DB().customBorderSizePx end,
                    setPx = function(val) DB().customBorderSizePx = val end,
                    apply = function()
                        mod.RefreshBorder()
                        RepaintPreview()
                    end,
                })
            )
        )
        cursorY = cursorY - height

        -- Width Offset | Height Offset: the textured border's outward offsets, shown only while a
        -- textured style is selected (Solid has none). Built during prebuild too so the y advance matches.
        do
            local cbTexNow = DbValue("customBorderTexture") or defaultSet.customBorderTexture
            if cbTexNow and cbTexNow ~= "" and cbTexNow ~= "solid" then
                local ocfgL, ocfgR = CludesUI.BorderOffsetRowCfgs({
                    addonKey = "nameplates",
                    getTex = function() return DbValue("customBorderTexture") or defaultSet.customBorderTexture end,
                    getStep = function() return DbValue("customBorderSize") or defaultSet.customBorderSize end,
                    getSizeKey = function() return DbValue("customBorderSize") or defaultSet.customBorderSize end,
                    getPx = function() return DB() and DB().customBorderSizePx end,
                    getX = function() return DB() and DB().customBorderOffset end,
                    setX = function(val) DB().customBorderOffset = val end,
                    getY = function() return DB() and DB().customBorderOffsetY end,
                    setY = function(val) DB().customBorderOffsetY = val end,
                    apply = function()
                        mod.RefreshBorder()
                        RepaintPreview()
                    end,
                })
                _, height = W:DualRow(
                    hostFrame,
                    cursorY,
                    CludesUI.BlizzStyle.Gate("nameplates", ocfgL),
                    CludesUI.BlizzStyle.Gate("nameplates", ocfgR)
                )
                cursorY = cursorY - height
            end
        end

        -- Inline "Border Options" cog on the Custom Border Style region (shifts + Show Behind)
        if not CludesUI._prebuilding then
            local leftRegion = customBorderRow._leftRegion
            -- Shift offsets only apply to textured styles (row only exists when Custom is selected, so no enable gate needed).
            local function cbCogOff()
                return (DbValue("customBorderTexture") or defaultSet.customBorderTexture) == "solid"
            end
            CludesUI.BuildInlineCog(leftRegion, {
                disabled = cbCogOff,
                disabledTooltip = "This option requires a textured border style",
                title = "Border Options",
                rows = {
                    {
                        type = "slider",
                        label = "Shift X",
                        min = -10,
                        max = 10,
                        step = 1,
                        get = function()
                            local val = DB() and DB().customBorderShiftX
                            if val then return val end
                            local texture = DbValue("customBorderTexture") or defaultSet.customBorderTexture
                            local sz = DbValue("customBorderSize") or defaultSet.customBorderSize
                            local _, _, dsx = CludesUI.GetBorderDefaults("nameplates", texture, sz)
                            return dsx
                        end,
                        set = function(val)
                            DB().customBorderShiftX = (val == 0 and nil or val)
                            mod.RefreshBorder()
                            RepaintPreview()
                        end,
                    },
                    {
                        type = "slider",
                        label = "Shift Y",
                        min = -10,
                        max = 10,
                        step = 1,
                        get = function()
                            local val = DB() and DB().customBorderShiftY
                            if val then return val end
                            local texture = DbValue("customBorderTexture") or defaultSet.customBorderTexture
                            local sz = DbValue("customBorderSize") or defaultSet.customBorderSize
                            local _, _, _, dsy = CludesUI.GetBorderDefaults("nameplates", texture, sz)
                            return dsy
                        end,
                        set = function(val)
                            DB().customBorderShiftY = (val == 0 and nil or val)
                            mod.RefreshBorder()
                            RepaintPreview()
                        end,
                    },
                    {
                        type = "toggle",
                        label = "Show Behind",
                        get = function()
                            local val = DbValue("customBorderBehind")
                            if val == nil then return defaultSet.customBorderBehind end
                            return val
                        end,
                        set = function(val)
                            DB().customBorderBehind = val
                            mod.RefreshBorder()
                            RepaintPreview()
                        end,
                    },
                },
            })
        end

        -- "Icon Borders" cog on the Custom Border Size region, beside the control (the colour
        -- swatch below chains left of it): the custom border on the aura icons and on the
        -- cast spell icon. A cog, not a row: both are niche, and the whole block exists
        -- only while Border = Custom. The if-body scopes its locals (builder budget).
        if not CludesUI._prebuilding then
            local rightRegion = customBorderRow._rightRegion
            CludesUI.BuildInlineCog(rightRegion, {
                title = "Icon Borders",
                captureRegion = rightRegion,
                rows = {
                    {
                        type = "toggle",
                        label = "Custom Border on Aura Icons",
                        tooltip = "Gives debuff, buff and crowd control icons the custom border instead of the 1-pixel border.",
                        disabled = function()
                            return DbValue("hideDebuffIconBorder") == true
                                and DbValue("hideBuffIconBorder") == true
                                and DbValue("hideCCIconBorder") == true
                        end,
                        disabledTooltip = "This option requires at least one aura type to show its border.",
                        rawTooltip = true,
                        get = function() return DbValue("auraIconCustomBorder") == true end,
                        set = function(val)
                            DB().auraIconCustomBorder = val
                            -- Fingerprint-gated aura restyle (the cast-lockout icon included).
                            mod.NPC_ReloadAll()
                            RepaintPreview()
                        end,
                    },
                    {
                        type = "toggle",
                        label = "Custom Border on Spell Icon",
                        tooltip = "Gives the cast bar spell icon the custom border instead of its 1-pixel border.",
                        disabled = function()
                            return DbValue("showCastIcon") == false
                                or DbValue("hideCastIconBorder") == true
                                or DbValue("castbarIconInWidth") == true
                        end,
                        disabledTooltip = function()
                            if DbValue("castbarIconInWidth") == true then
                                return "This option is disabled while Make Icon Part of the Bar is enabled."
                            end
                            return "This option requires the spell icon and its border to be shown."
                        end,
                        rawTooltip = true,
                        get = function() return DbValue("castIconCustomBorder") == true end,
                        set = function(val)
                            DB().castIconCustomBorder = val
                            -- Re-applies every plate's appearance (pooled plates too), which
                            -- builds or turns off the icon border.
                            mod.RefreshAllSettings()
                            RepaintPreview()
                        end,
                    },
                    {
                        type = "toggle",
                        label = "Vertical Separator",
                        tooltip = "Draws a divider between the integrated spell icon and the cast bar using the custom border appearance.",
                        disabled = function() return not mod.NP_CanShowCastIconSeparator(DB()) end,
                        disabledTooltip = "Requires Make Icon Part of the Bar, a shown non-full-sized icon, and a Solid or Pixels border with size above 0.",
                        rawTooltip = true,
                        get = function() return DbValue("castIconSeparator") == true end,
                        set = function(val)
                            DB().castIconSeparator = val
                            mod.RefreshAllSettings()
                            RepaintPreview()
                        end,
                    },
                },
            })
        end

        -- Inline color swatch (with alpha) on the Custom Border Size region
        if not CludesUI._prebuilding then
            local rightRegion = customBorderRow._rightRegion
            local cbColGet = function()
                local color = (DB() and DB().customBorderColor) or defaultSet.customBorderColor
                return color.r,
                    color.g,
                    color.b,
                    (DbValue("customBorderAlpha") or defaultSet.customBorderAlpha or 1)
            end
            local cbColSet = function(red, green, blue, a)
                DB().customBorderColor = { r = red, g = green, b = blue }
                if a ~= nil then DB().customBorderAlpha = a end
                mod.RefreshBorderColor()
                RepaintPreview()
            end
            local cbSwatch, cbUpdateSwatch = CludesUI.BuildColorSwatch(
                rightRegion,
                rightRegion:GetFrameLevel() + 5,
                cbColGet,
                cbColSet,
                true,
                20
            )
            Pix.Point(cbSwatch, "RIGHT", rightRegion._lastInline or rightRegion._control, "LEFT", -8, 0)
            rightRegion._lastInline = cbSwatch
            CludesUI.RegisterWidgetRefresh(function() cbUpdateSwatch() end)
        end
    end

    -- Row 2: Background (+swatch) | Absorb Style (+cog, preview eye) -- placed here so the section fills sequentially, no blank middle slot. Absorb Style options: Blizzard + the stripe overlay set (shared with Focus Texture) + Clean; stripe keys resolve via ns.ResolveOverlayTexPath.
    local absorbStyleValues = {
        ["blizzard"] = "Blizzard",
        ["striped"] = "Striped",
        ["striped-v2"] = "Stripes",
        ["striped-wide-v2"] = "Wide Stripes",
        ["stripes-medium"] = "Medium Stripes",
        ["stripes-small-close"] = "Small Dense Stripes",
        ["stripes-small-spread"] = "Small Spread Stripes",
        ["striped-tiny"] = "Tiny Stripes",
        ["clean"] = "Clean (Flat)",
        ["pixelsShield"] = "Pixels Shield",
        ["pixelsShieldEdge"] = "Pixels Shield Edge",
        ["pixelsShieldFill"] = "Pixels Shield Fill",
    }
    local absorbStyleOrder = {
        "blizzard",
        "striped",
        "striped-v2",
        "striped-wide-v2",
        "stripes-medium",
        "stripes-small-close",
        "stripes-small-spread",
        "striped-tiny",
        "clean",
        "pixelsShield",
        "pixelsShieldEdge",
        "pixelsShieldFill",
    }
    -- Append SharedMedia statusbar textures after a divider (mirrors Bar Texture). SM keys ("sm:") were added to the shared health-bar tables by AppendSharedMediaTextures; resolution flows via ns.ResolveOverlayTexPath -> health-bar lookup, so SM keys paint correctly here.
    do
        local sepAdded = false
        for _, keyName in ipairs(hbtOrder) do
            if keyName ~= "---" and keyName:find("^sm:") then
                if not sepAdded then
                    absorbStyleOrder[#absorbStyleOrder + 1] = "---"
                    sepAdded = true
                end
                absorbStyleOrder[#absorbStyleOrder + 1] = keyName
                absorbStyleValues[keyName] = hbtValues[keyName]
            end
        end
        -- Preview swatch behind each menu row resolves exactly like the render path: NP_ABSORB_STYLE_TEX for blizzard/striped/clean, then ns.ResolveOverlayTexPath for stripe overlays/SM keys.
        absorbStyleValues._menuOpts = {
            itemHeight = 28,
            background = function(key)
                if not key or key == "---" then return nil end
                return mod.NP_ABSORB_STYLE_TEX[key] or mod.ResolveOverlayTexPath(key)
            end,
        }
    end
    local bgHoverRow
    bgHoverRow, height = W:DualRow(
        hostFrame,
        cursorY,
        mod.NP_BlizzOnlyGate({
            type = "slider",
            text = "Background",
            min = 0,
            max = 100,
            step = 1,
            getValue = function() return math.floor(((DbValue("bgAlpha") or defaultSet.bgAlpha) * 100) + 0.5) end,
            setValue = function(val)
                DB().bgAlpha = val / 100
                local color = (DB() and DB().bgColor) or defaultSet.bgColor
                for _, backing in pairs(plates) do
                    backing.healthBG:SetColorTexture(color.r, color.g, color.b, val / 100)
                end
                RepaintPreview()
            end,
        }),
        {
            type = "dropdown",
            text = "Absorb Style",
            tooltip = "How shields are drawn on the health bar.",
            values = absorbStyleValues,
            order = absorbStyleOrder,
            getValue = function() return DbValue("absorbStyle") or "blizzard" end,
            setValue = function(val)
                DB().absorbStyle = val
                -- Selecting a style sets opacity to that style's default (Blizzard/Stripes 80%, Clean 30%); slider tweaks from there.
                DB().absorbAlpha = math.floor(((mod.NP_ABSORB_STYLE_ALPHA[val] or 0.8) * 100) + 0.5)
                mod.ApplyAbsorbStyleAll()
                RepaintPreview()
                -- Refresh so the color swatch enables/disables (Blizzard = off).
                CludesUI:RefreshPage()
            end,
        }
    )
    cursorY = cursorY - height
    -- Inline color swatch on Background (left region)
    if not CludesUI._prebuilding then
        local leftRegion = bgHoverRow._leftRegion
        local cbColorGet = function()
            local color = (DB() and DB().bgColor) or defaultSet.bgColor
            return color.r, color.g, color.b
        end
        local cbColorSet = function(red, green, blue)
            DB().bgColor = { r = red, g = green, b = blue }
            local a = DbValue("bgAlpha") or defaultSet.bgAlpha
            for _, backing in pairs(plates) do
                backing.healthBG:SetColorTexture(red, green, blue, a)
            end
            RepaintPreview()
        end
        local cbSwatch, cbUpdateSwatch = CludesUI.BuildColorSwatch(
            leftRegion,
            leftRegion:GetFrameLevel() + 5,
            cbColorGet,
            cbColorSet,
            nil,
            20
        )
        Pix.Point(cbSwatch, "RIGHT", leftRegion._control, "LEFT", -12, 0)
        leftRegion._lastInline = cbSwatch
        CludesUI.RegisterWidgetRefresh(function() cbUpdateSwatch() end)
        if mod.NP_BlizzOnly() then CludesUI.BlizzStyle.BlockInline("nameplates", cbSwatch) end
    end

    -- Inline "Absorb Settings" cog on the Absorb Style region (right of Row 2)
    if not CludesUI._prebuilding then
        local region = bgHoverRow._rightRegion
        CludesUI.BuildInlineCog(region, {
            title = "Absorb Settings",
            rows = {
                {
                    type = "slider",
                    label = "Opacity",
                    min = 5,
                    max = 100,
                    step = 1,
                    get = function()
                        local val = DbValue("absorbAlpha")
                        if val then return val end
                        -- Untouched profiles: show the active style's default.
                        local style = DbValue("absorbStyle") or "blizzard"
                        if style == "clean" then return DbValue("absorbCleanAlpha") or 30 end
                        return math.floor(((mod.NP_ABSORB_STYLE_ALPHA[style] or 0.8) * 100) + 0.5)
                    end,
                    set = function(val)
                        DB().absorbAlpha = val
                        mod.ApplyAbsorbStyleAll()
                        RepaintPreview()
                    end,
                },
                -- Same placements as the unit frames' Absorb Rendering cog, except
                -- that Overlay Reverse here keeps a shield larger than current
                -- health, as their Overlay Reverse (Full) does (their plain
                -- Overlay Reverse clips that excess).
                {
                    type = "dropdown",
                    label = "Placement",
                    tooltip = "Overlay fills empty health first, then draws any excess over current health. Overlay Reverse draws the shield back over current health; a shield larger than current health spans from the bar's left end. From Right Edge and From Left Edge grow the whole shield from that end of the bar.",
                    values = {
                        overlay = "Overlay",
                        overlayReverse = "Overlay Reverse",
                        right = "From Right Edge",
                        left = "From Left Edge",
                    },
                    order = { "overlay", "overlayReverse", "right", "left" },
                    get = function() return DbValue("absorbEdgeMode") or "overlay" end,
                    set = function(val)
                        DB().absorbEdgeMode = val
                        mod.ApplyAbsorbStyleAll()
                        RepaintPreview()
                    end,
                },
            },
        })
    end

    -- Inline absorb color swatch (right of Row 2): white by default, tints every style except Blizzard (disabled there since Blizzard keeps its own coloring); mirrors the Focus Texture swatch's disabled pattern.
    if not CludesUI._prebuilding then
        local region = bgHoverRow._rightRegion
        local acColorGet = function()
            local color = (DB() and DB().absorbColor) or defaultSet.absorbColor or { r = 1, g = 1, b = 1 }
            return color.r, color.g, color.b
        end
        local acColorSet = function(red, green, blue)
            DB().absorbColor = { r = red, g = green, b = blue }
            mod.ApplyAbsorbStyleAll()
            RepaintPreview()
        end
        local acSwatch, acUpdateSwatch =
            CludesUI.BuildColorSwatch(region, region:GetFrameLevel() + 5, acColorGet, acColorSet, nil, 20)
        Pix.Point(acSwatch, "RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
        region._lastInline = acSwatch
        local function absorbColorOff() return (DbValue("absorbStyle") or "blizzard") == "blizzard" end
        CludesUI.RegisterWidgetRefresh(function()
            local off = absorbColorOff()
            acSwatch:SetAlpha(off and 0.15 or 1)
            acSwatch:EnableMouse(not off)
            acUpdateSwatch()
        end)
        local off0 = absorbColorOff()
        acSwatch:SetAlpha(off0 and 0.15 or 1)
        acSwatch:EnableMouse(not off0)
    end

    -- Eye icon: toggle absorb preview on the preview nameplate
    if not CludesUI._prebuilding then
        local EYE_VISIBLE = CludesUI.EYE_VISIBLE_ICON
        local EYE_INVISIBLE = CludesUI.EYE_INVISIBLE_ICON
        local region = bgHoverRow._rightRegion
        local eyeButton = CreateFrame("Button", nil, region)
        eyeButton:SetSize(26, 26)
        eyeButton:SetPoint("RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
        region._lastInline = eyeButton
        eyeButton:SetFrameLevel(region:GetFrameLevel() + 5)
        CludesUI.SetGlyphAlpha(eyeButton, 0.4)
        local eyeTex = eyeButton:CreateTexture(nil, "OVERLAY")
        eyeTex:SetAllPoints()
        local function RefreshAbsorbEye()
            if optionState.showAbsorbPreview then
                eyeTex:SetTexture(EYE_INVISIBLE)
            else
                eyeTex:SetTexture(EYE_VISIBLE)
            end
        end
        RefreshAbsorbEye()
        eyeButton:SetScript("OnClick", function()
            optionState.showAbsorbPreview = not optionState.showAbsorbPreview
            RefreshAbsorbEye()
            RepaintPreview()
        end)
        eyeButton:SetScript("OnEnter", function(self) CludesUI.SetGlyphAlpha(self, 0.7) end)
        eyeButton:SetScript("OnLeave", function(self) CludesUI.SetGlyphAlpha(self, 0.4) end)
    end

    -- Row 3: Bar Texture | Cast Bar Texture -- share the same texture set (CUI built-ins + SharedMedia) and resolve identically; Bar Texture drives the health bar, Cast Bar Texture drives the cast bar.
    local texRow
    texRow, height = W:DualRow(
        hostFrame,
        cursorY,
        -- Bar Texture stays live under Blizzard Style: the health fill is the
        -- user's own texture under the stock background art.
        {
            type = "dropdown",
            text = "Bar Texture",
            values = hbtValues,
            order = hbtOrder,
            getValue = function() return DbValue("healthBarTexture") or "none" end,
            setValue = function(val)
                DB().healthBarTexture = val
                RedrawTextures()
                RepaintPreview()
            end,
        },
        mod.NP_BlizzOnlyGate({
            type = "dropdown",
            text = "Cast Bar Texture",
            tooltip = "The texture the cast bar is filled with.",
            values = hbtValues,
            order = hbtOrder,
            getValue = function() return DbValue("castBarTexture") or "none" end,
            setValue = function(val)
                DB().castBarTexture = val
                RedrawTextures()
                RepaintPreview()
            end,
        })
    )
    cursorY = cursorY - height
    -- Textured Background cogs on the two texture dropdowns, greyed while
    -- Blizzard Style draws its stock backgrounds (as Global Settings > Textures).
    if not CludesUI._prebuilding then
        local function TexBgApply()
            RedrawTextures()
            RepaintPreview()
        end
        local blizz = mod.NP_BlizzOnly()
        local function TexBgCog(region, kind)
            CludesUI.BuildInlineCog(region, {
                disabled = blizz and function() return true end or nil,
                disabledTooltip = blizz and CludesUI.BlizzStyle.Label("nameplates") or nil,
                requireState = blizz and "disabled" or nil,
                title = "Texture Settings",
                rows = { environ.TexBgRowCfg(kind, TexBgApply) },
            })
        end
        TexBgCog(texRow._leftRegion, "health")
        TexBgCog(texRow._rightRegion, "cast")
    end

    -- WoW Forever variant only (the Forever client): Show Level Box, the
    -- opt-out for the level box right of the health bar (nil = shown),
    -- last in the section so its blank slot is the odd last one. Off, the
    -- plates lay out as plain Blizzard Style; Left Text stays the user's
    -- to set to Level. Not built on any other look.
    if CludesUI.BlizzStyle.Forever("nameplates") then
        local foreverBoxRow
        foreverBoxRow, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Show Level Box",
            tooltip = "Shows the level box right of the health bar; with it off, Left Text can show the level instead.",
            getValue = function() return not DbValue("foreverHideLevelBox") end,
            setValue = function(val)
                DB().foreverHideLevelBox = (not val) or nil
                mod.RefreshAllSettings()
                RepaintPreview()
            end,
        }, CludesUI.BlankRowCfg())
        cursorY = cursorY - height
        -- Reached by the preview's click navigation (the level box).
        hostFrame._foreverBoxRow = foreverBoxRow
    end

    _, height = W:Spacer(hostFrame, cursorY, 20)
    cursorY = cursorY - height

    -----------------------------------------------------------------------
    --  CORE POSITIONS
    -----------------------------------------------------------------------
    local coreHeader
    coreHeader, height = W:SectionHeader(hostFrame, "CORE POSITIONS", cursorY)
    cursorY = cursorY - height

    -- Subtitle hint next to the section header's title (the header's own label:
    -- a page built again keeps its earlier dresses' font strings, idle, among
    -- the header's regions)
    do
        local region = coreHeader._label
        if region and CludesUI.EnKey(region:GetText()) == "CORE POSITIONS" then
            local subMenu = coreHeader:CreateFontString(nil, "OVERLAY")
            subMenu:SetFont(region:GetFont())
            subMenu:SetTextColor(1, 1, 1, 0.25)
            subMenu:SetText(CludesUI.L("(one slot per element)"))
            subMenu:SetPoint("LEFT", region, "RIGHT", 6, 0)
        end
    end

    local coreElementValues = {
        debuffs = "Debuffs",
        buffs = "Buffs",
        ccs = "Crowd Control",
        debuffsccs = "Debuffs + CC",
        raidmarker = "Raid Marker",
        classification = "Rare/Quest Indicator",
        faction = "Faction",
        classfaction = "Rare/Quest + Faction",
        none = "None",
    }
    local coreElementOrder = {
        "debuffs",
        "buffs",
        "ccs",
        "debuffsccs",
        "raidmarker",
        "classification",
        "faction",
        "classfaction",
        "none",
    }

    local coreRow1, coreRow2, coreRow3
    local _refreshCoreEyePos

    -- Never from the search pre-build: it builds no eye, and the shown page's
    -- Core Positions rows call this to move it.
    if not CludesUI._prebuilding then
        optionState.RefreshCoreEyes = function()
            if _refreshCoreEyePos then _refreshCoreEyePos() end
        end
    end

    -- Each slot's control is a checkbox dropdown with drag-to-reorder rows, one
    -- row per element: a view over the same stored keys the single-choice
    -- dropdowns wrote (each element's slot key, debuffIncludeCC and
    -- classificationIncludeFaction for the two pairs that merge into one
    -- element) plus classificationHideRare / classificationHideQuest, the two
    -- halves of the Rare/Quest indicator. The halves are one frame, so they
    -- always share a slot and move together. Any elements can share a slot:
    -- they sit one after another in the rows' order, saved per slot as
    -- <pos>SlotOrder (the row keys joined by commas; unset = the default order)
    -- and laid out by the Core Positions chain (ns.NP_CoreChain),
    -- <pos>SlotElementSpacing apart (the Element Spacing row of the slot's cog).
    -- Debuffs with Crowd Control still merge into one row, and the Elite/Rare
    -- and Quest Indicators with Faction into one stacked pair, as the old
    -- combined elements did. Quest Objective Text is an element of its own
    -- (questTextSlot), read through the runtime's view over the
    -- replaceQuestIconWithObjective key (ns.NP_GetQuestTextSlot,
    -- ns.NP_QuestIconOn) until one of its inputs is changed here, which first
    -- settles the view into its own keys (ns.NP_MaterializeQuestText). The
    -- single-choice dropdowns stay built, hidden, under the checkbox dropdowns
    -- (the row label's empty-slot state).
    local CORE_ORDER = { "debuffs", "buffs", "ccs", "raidmarker", "rare", "quest", "questtext", "faction" }
    local CORE_LABEL = {
        debuffs = "Debuffs",
        buffs = "Buffs",
        ccs = "Crowd Control",
        raidmarker = "Raid Marker",
        rare = "Elite/Rare Indicator",
        quest = "Quest Indicator",
        questtext = "Quest Objective Text",
        faction = "Faction",
    }
    local CORE_TIP = {
        rare = "Elite and rare marks. Always in the same slot as the Quest Indicator.",
        quest = "Marks mobs for your active quests. Always in the same slot as the Elite/Rare Indicator.",
        questtext = "Shows quest progress such as 2/6 on quest mobs.",
    }

    local function CoreHas(place, keyName)
        if keyName == "debuffs" then return DbValue("debuffSlot") == place end
        if keyName == "buffs" then return DbValue("buffSlot") == place end
        if keyName == "ccs" then
            return DbValue("ccSlot") == place
                or (DbValue("debuffIncludeCC") == true and DbValue("debuffSlot") == place)
        end
        if keyName == "raidmarker" then return DbValue("raidMarkerPos") == place end
        if keyName == "rare" then
            return DbValue("classificationSlot") == place and not DbValue("classificationHideRare")
        end
        if keyName == "quest" then
            return DbValue("classificationSlot") == place and mod.NP_QuestIconOn(DB())
        end
        if keyName == "questtext" then return mod.NP_GetQuestTextSlot(DB()) == place end
        if keyName == "faction" then
            -- While Rare/Quest + Faction is on, a leftover faction slot is ignored.
            if DbValue("classificationIncludeFaction") == true then
                return DbValue("classificationSlot") == place
            end
            return DbValue("factionSlot") == place
        end
        return false
    end

    -- The slot's row order: its saved order first, then every row it lacks in
    -- the default order. A saved order without Quest Objective Text takes it
    -- right after the Quest Indicator (the runtime chain reads it the same way).
    local function CoreOrderKeys(place)
        local keyList, seen = {}, {}
        local source = DbValue(place .. "SlotOrder")
        if type(source) == "string" then
            local qtAfterQuest = not string.find("," .. source .. ",", ",questtext,", 1, true)
            for keyName in string.gmatch(source, "[^,]+") do
                if CORE_LABEL[keyName] and not seen[keyName] then
                    seen[keyName] = true
                    keyList[#keyList + 1] = keyName
                    if keyName == "quest" and qtAfterQuest then
                        seen.questtext = true
                        keyList[#keyList + 1] = "questtext"
                    end
                end
            end
        end
        for idx = 1, #CORE_ORDER do
            local keyName = CORE_ORDER[idx]
            if not seen[keyName] then
                seen[keyName] = true
                keyList[#keyList + 1] = keyName
            end
        end
        return keyList
    end
    -- The default order saves as unset.
    local function CoreSaveOrder(place, keyList)
        local s = table.concat(keyList, ",")
        if s == table.concat(CORE_ORDER, ",") then s = nil end
        DB()[place .. "SlotOrder"] = s
    end

    local function CoreSet(place, keyName, val)
        local saved = DB()
        -- The Elite/Rare and Quest Indicators and Quest Objective Text are the
        -- view's inputs: the view settles into its own keys before any of them
        -- changes, so what the slots show stays as it was.
        if keyName == "rare" or keyName == "quest" or keyName == "questtext" then
            mod.NP_MaterializeQuestText(saved)
        end
        if keyName == "debuffs" then
            if val then
                local old = DbValue("debuffSlot")
                local merged = DbValue("debuffIncludeCC") == true
                if DbValue("ccSlot") == place then
                    -- CC already here on its own: the two become Debuffs + CC.
                    saved.ccSlot = "none"
                    merged = true
                elseif merged and old ~= place then
                    -- Leaving a Debuffs + CC slot: CC stays there on its own
                    -- unless it already has a slot elsewhere.
                    if old ~= "none" and DbValue("ccSlot") == "none" then saved.ccSlot = old end
                    merged = false
                end
                saved.debuffSlot = place
                saved.debuffIncludeCC = merged
            else
                if DbValue("debuffIncludeCC") == true and DbValue("ccSlot") == "none" then
                    saved.ccSlot = place
                end
                saved.debuffSlot = "none"
                saved.debuffIncludeCC = false
            end
        elseif keyName == "ccs" then
            if val then
                if DbValue("debuffSlot") == place then
                    saved.debuffIncludeCC = true
                    saved.ccSlot = "none"
                else
                    saved.debuffIncludeCC = false
                    saved.ccSlot = place
                end
            else
                if DbValue("debuffSlot") == place then saved.debuffIncludeCC = false end
                if DbValue("ccSlot") == place then saved.ccSlot = "none" end
            end
        elseif keyName == "buffs" then
            if val then
                saved.buffSlot = place
            elseif DbValue("buffSlot") == place then
                saved.buffSlot = "none"
            end
        elseif keyName == "raidmarker" then
            if val then
                saved.raidMarkerPos = place
            elseif DbValue("raidMarkerPos") == place then
                saved.raidMarkerPos = "none"
            end
        elseif keyName == "rare" or keyName == "quest" then
            local hideKey = (keyName == "rare") and "classificationHideRare" or "classificationHideQuest"
            local otherKey = (keyName == "rare") and "classificationHideQuest" or "classificationHideRare"
            if val then
                local old = DbValue("classificationSlot")
                if old ~= place then
                    -- Moving: a Faction badge riding along stays behind on its own.
                    if DbValue("classificationIncludeFaction") == true then
                        saved.classificationIncludeFaction = false
                        if old ~= "none" then saved.factionSlot = old end
                    end
                    -- Brought back from None: only the half that was checked.
                    if old == "none" then saved[otherKey] = true end
                    saved.classificationSlot = place
                    -- Faction already here on its own joins them.
                    if DbValue("factionSlot") == place then
                        saved.classificationIncludeFaction = true
                        saved.factionSlot = "none"
                    end
                end
                saved[hideKey] = false
            elseif DbValue(otherKey) then
                -- The last half goes: the indicator leaves the slot, a Faction
                -- badge riding along stays there on its own.
                if DbValue("classificationIncludeFaction") == true then
                    saved.classificationIncludeFaction = false
                    saved.factionSlot = place
                end
                saved.classificationSlot = "none"
                saved.classificationHideRare = false
                saved.classificationHideQuest = false
            else
                saved[hideKey] = true
            end
        elseif keyName == "faction" then
            if val then
                if DbValue("classificationSlot") == place then
                    saved.classificationIncludeFaction = true
                    saved.factionSlot = "none"
                else
                    saved.classificationIncludeFaction = false
                    saved.factionSlot = place
                end
            else
                if DbValue("classificationSlot") == place then saved.classificationIncludeFaction = false end
                if DbValue("factionSlot") == place then saved.factionSlot = "none" end
            end
        elseif keyName == "questtext" then
            if val then
                saved.questTextSlot = place
            elseif mod.NP_GetQuestTextSlot(saved) == place then
                saved.questTextSlot = "none"
            end
        end
    end

    local function InstallCoreCB(region, place)
        local control = region._control
        local ddW = control and control:GetWidth() or 0
        if ddW < 50 then ddW = 170 end
        -- The rows in the slot's saved order, so the button's label reads in
        -- that order before the list is first opened.
        local itemList = {}
        local keyList = CoreOrderKeys(place)
        for idx = 1, #keyList do
            local keyName = keyList[idx]
            itemList[idx] = { key = keyName, label = CORE_LABEL[keyName], tooltip = CORE_TIP[keyName] }
        end
        local checkDrop, cbDDRefresh = CludesUI.BuildReorderCBDropdown(
            region,
            ddW,
            region:GetFrameLevel() + 2,
            itemList,
            function(keyName) return CoreHas(place, keyName) end,
            function(keyName, val)
                CoreSet(place, keyName, val)
                -- The quest scan's caches are built for the quest elements
                -- shown: dropped, and every plate's indicators run again.
                if keyName == "rare" or keyName == "quest" or keyName == "questtext" then
                    mod.RefreshQuestObjective()
                end
                RefreshAllSlots()
                optionState.RefreshCoreEyes()
            end,
            {
                grip = true,
                openOrder = function() return CoreOrderKeys(place) end,
                setOrder = function(sequence)
                    CoreSaveOrder(place, sequence)
                    RefreshAllSlots()
                end,
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
        CludesUI.RegisterWidgetRefresh(cbDDRefresh)
    end

    -- Slot-based offsets: pos .. "SlotXOffset" / "SlotYOffset"

    local function CorePosXGet(place) return DbValue(place .. "SlotXOffset") or 0 end
    local function CorePosYGet(place) return DbValue(place .. "SlotYOffset") or 0 end
    local function CorePosXSet(place, val)
        DB()[place .. "SlotXOffset"] = val
        RefreshAllSlots()
    end
    local function CorePosYSet(place, val)
        DB()[place .. "SlotYOffset"] = val
        RefreshAllSlots()
    end
    -- A slot is empty while it holds none of the checkbox dropdown's elements
    -- (Quest Objective Text alone fills it; the Rare/Quest frame with both of
    -- its halves unchecked does not).
    local function CorePosLocked(place)
        for idx = 1, #CORE_ORDER do
            if CoreHas(place, CORE_ORDER[idx]) then return false end
        end
        return true
    end
    -- The hidden single-choice dropdowns (SetElementAtPosition settles the
    -- Quest Objective Text view before it writes).
    local function CoreSingleSet(place, val)
        SetElementAtPosition(place, val)
        mod.RefreshQuestObjective()
        RefreshAllSlots()
        optionState.RefreshCoreEyes()
    end

    -------------------------------------------------------------------
    --  Combined Settings Popup  (singleton, slide-up, pos + optional size)
    --  The Core Text Positions cogs below and the cast text and class
    --  resource cogs of DisplayBars_Options.lua open it.
    -------------------------------------------------------------------
    local function CogPopupOpen(button) return LiveCogOwner() == button and cogPopup:IsShown() end

    -- opts = { title, xGet, xSet, yGet, ySet,
    --   sizeGet, sizeSet, sizeMin, sizeMax, sizeStep, sizeLabel, sizeFirst (Size heads the rows),
    --   widthGet/Set (Width %), toggleLabel/Get/Set, wrapGet/Set (Wrap),
    --   dropdown2Label/Get/Set/Tooltip (Name Format), strataGet/Set (Strata) };
    -- a row shows while its getter is set.
    local function ShowCogPopup(anchorBtn, options)
        if not cogPopup then
            -- The refreshes the popup's sliders register while it is built.
            local refreshList = CludesUI._widgetRefreshList
            local firstRefresh = #refreshList + 1
            local SolidTex = CludesUI.SolidTex
            local MakeFont = CludesUI.MakeFont
            local BuildSliderCore = CludesUI.BuildSliderCore
            local BORDER_COLOR = CludesUI.BORDER_COLOR
            local SL_INPUT_A = CludesUI.SL_INPUT_A

            local SIDE_PAD = 14
            local INPUT_W = 34
            local SLIDER_INPUT_GAP = 8
            local LABEL_SLIDER_GAP = 12
            local TOP_PAD = 14
            local TITLE_H = 11
            local TITLE_GAP = 10
            local GAP = 10
            local SLIDER_H = 24

            -- Max height: title + X + Y + Size = 4 rows
            local MAX_H = TOP_PAD
                + TITLE_H
                + TITLE_GAP
                + GAP
                + SLIDER_H
                + GAP
                + SLIDER_H
                + GAP
                + SLIDER_H
                + TOP_PAD

            local popFrame = CreateFrame("Frame", nil, UIParent)
            popFrame:SetSize(260, MAX_H)
            popFrame:SetFrameStrata("DIALOG")
            popFrame:SetFrameLevel(200)
            popFrame:EnableMouse(true)
            popFrame:Hide()

            -- Match the panel/popup scale so this popup renders at the same size as the shared BuildCogPopup popups (else it stays scale 1.0 and looks oversized); registering it also tracks the panel scale slider.
            popFrame:SetScale((CludesUI.GetPopupScale()) or 1)
            if CludesUI._popupFrames then
                CludesUI._popupFrames[#CludesUI._popupFrames + 1] = { popup = popFrame }
            end

            local backdrop = SolidTex(popFrame, "BACKGROUND", 0.062, 0.070, 0.082, 0.95)
            backdrop:SetAllPoints()
            CludesUI.MakeRoundedBorder(
                popFrame,
                BORDER_COLOR.r,
                BORDER_COLOR.g,
                BORDER_COLOR.b,
                0.15,
                backdrop
            )

            local titleFS = MakeFont(popFrame, 11, "", 1, 1, 1)
            titleFS:SetAlpha(0.7)
            titleFS:SetPoint("TOP", popFrame, "TOP", 0, -TOP_PAD)
            popFrame._titleFS = titleFS

            -- The slider column starts past the widest of a fixed set of labels,
            -- so every cog that opens this popup lines its sliders up alike.
            local tmpFS = popFrame:CreateFontString(nil, "OVERLAY")
            tmpFS:SetFont(CludesUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF", 12, GetNPOptOutline())
            local labelTexts =
                { "X Offset", "Y Offset", "Size", "Width %", "Spacing", "Opacity", "Text Size" }
            local maxLblW = 0
            for _, txt in ipairs(labelTexts) do
                tmpFS:SetText(CludesUI.L(txt))
                local wid = tmpFS:GetStringWidth()
                if wid > maxLblW then maxLblW = wid end
            end
            tmpFS:Hide()
            if maxLblW < 10 then maxLblW = 28 end

            local SLIDER_LEFT = SIDE_PAD + maxLblW + LABEL_SLIDER_GAP
            local SLIDER_W = math.max(80, 260 - SLIDER_LEFT - SLIDER_INPUT_GAP - INPUT_W - SIDE_PAD)
            local POPUP_W = SLIDER_LEFT + SLIDER_W + SLIDER_INPUT_GAP + INPUT_W + SIDE_PAD
            if POPUP_W < 180 then POPUP_W = 180 end
            popFrame:SetSize(POPUP_W, popFrame:GetHeight())

            -- X slider row
            local X_ROW_Y = -(TOP_PAD + TITLE_H + TITLE_GAP + GAP)
            local xLabel = MakeFont(popFrame, 12, nil, 1, 1, 1)
            xLabel:SetAlpha(0.6)
            xLabel:SetText(CludesUI.L("X Offset"))
            xLabel:SetPoint("LEFT", popFrame, "TOPLEFT", SIDE_PAD, X_ROW_Y - SLIDER_H / 2)
            local xTrack, xValBox = BuildSliderCore(
                popFrame,
                SLIDER_W,
                4,
                12,
                INPUT_W,
                SLIDER_H,
                11,
                SL_INPUT_A,
                -300,
                300,
                1,
                function() return popFrame._xGet and popFrame._xGet() or 0 end,
                function(val)
                    if popFrame._xSet then popFrame._xSet(val) end
                end,
                true
            )
            xTrack:SetPoint("TOPLEFT", popFrame, "TOPLEFT", SLIDER_LEFT, X_ROW_Y - 2)
            xValBox:ClearAllPoints()
            xValBox:SetPoint("TOPRIGHT", popFrame, "TOPRIGHT", -SIDE_PAD, X_ROW_Y)

            popFrame._xTrack = xTrack
            popFrame._xValBox = xValBox
            popFrame._xLabel = xLabel

            -- Y slider row
            local Y_ROW_Y = X_ROW_Y - SLIDER_H - GAP
            local yLabel = MakeFont(popFrame, 12, nil, 1, 1, 1)
            yLabel:SetAlpha(0.6)
            yLabel:SetText(CludesUI.L("Y Offset"))
            yLabel:SetPoint("LEFT", popFrame, "TOPLEFT", SIDE_PAD, Y_ROW_Y - SLIDER_H / 2)
            local yTrack, yValBox = BuildSliderCore(
                popFrame,
                SLIDER_W,
                4,
                12,
                INPUT_W,
                SLIDER_H,
                11,
                SL_INPUT_A,
                -300,
                300,
                1,
                function() return popFrame._yGet and popFrame._yGet() or 0 end,
                function(val)
                    if popFrame._ySet then popFrame._ySet(val) end
                end,
                true
            )
            yTrack:SetPoint("TOPLEFT", popFrame, "TOPLEFT", SLIDER_LEFT, Y_ROW_Y - 2)
            yValBox:ClearAllPoints()
            yValBox:SetPoint("TOPRIGHT", popFrame, "TOPRIGHT", -SIDE_PAD, Y_ROW_Y)

            popFrame._yTrack = yTrack
            popFrame._yValBox = yValBox
            popFrame._yLabel = yLabel

            -- Size slider row (hidden when not needed)
            local S_ROW_Y = Y_ROW_Y - SLIDER_H - GAP
            local sLabel = MakeFont(popFrame, 12, nil, 1, 1, 1)
            sLabel:SetAlpha(0.6)
            sLabel:SetText(CludesUI.L("Size"))
            sLabel:SetPoint("LEFT", popFrame, "TOPLEFT", SIDE_PAD, S_ROW_Y - SLIDER_H / 2)
            popFrame._sLabel = sLabel

            -- Width % slider row (hidden unless a width-fit text element: enemy name, cast spell name, cast target); fixed range built once, reordered/repositioned per show via the seq block below.
            local W_ROW_Y = S_ROW_Y - SLIDER_H - GAP
            local wLabel = MakeFont(popFrame, 12, nil, 1, 1, 1)
            wLabel:SetAlpha(0.6)
            wLabel:SetText(CludesUI.L("Width %"))
            wLabel:SetPoint("LEFT", popFrame, "TOPLEFT", SIDE_PAD, W_ROW_Y - SLIDER_H / 2)
            wLabel:Hide()
            popFrame._wLabel = wLabel
            -- Invisible hover region for the label's tooltip (FontStrings aren't mouse-interactive); SetAllPoints tracks the label through repositioning, shown/hidden with the row.
            local wHover = CreateFrame("Frame", nil, popFrame)
            wHover:SetFrameLevel(popFrame:GetFrameLevel() + 10)
            wHover:SetAllPoints(wLabel)
            wHover:EnableMouse(true)
            wHover:Hide()
            wHover:SetScript(
                "OnEnter",
                function(self)
                    CludesUI.ShowWidgetTooltip(
                        self,
                        CludesUI.L(
                            "Maximum width the text can fill before it truncates, as a percentage of the bar."
                        ),
                        { width = 230 }
                    )
                end
            )
            wHover:SetScript("OnLeave", function() CludesUI.HideWidgetTooltip() end)
            popFrame._wHover = wHover
            local wTrack, wValBox = BuildSliderCore(
                popFrame,
                SLIDER_W,
                4,
                12,
                INPUT_W,
                SLIDER_H,
                11,
                SL_INPUT_A,
                10,
                150,
                1,
                function() return popFrame._wGet and popFrame._wGet() or 0 end,
                function(val)
                    if popFrame._wSet then popFrame._wSet(val) end
                end,
                true
            )
            wTrack:SetPoint("TOPLEFT", popFrame, "TOPLEFT", SLIDER_LEFT, W_ROW_Y - 2)
            wValBox:ClearAllPoints()
            wValBox:SetPoint("TOPRIGHT", popFrame, "TOPRIGHT", -SIDE_PAD, W_ROW_Y)
            wTrack:Hide()
            wValBox:Hide()
            popFrame._wTrack = wTrack
            popFrame._wValBox = wValBox

            -- Store layout values for dynamic size slider rebuild + reorder
            popFrame._SLIDER_LEFT = SLIDER_LEFT
            popFrame._SLIDER_W = SLIDER_W
            popFrame._X_ROW_Y = X_ROW_Y
            popFrame._Y_ROW_Y = Y_ROW_Y
            popFrame._S_ROW_Y = S_ROW_Y
            popFrame._ROW0 = X_ROW_Y
            popFrame._ROW_STEP = SLIDER_H + GAP

            -- The toggle and dropdown rows: shorter than a slider row, placed
            -- below the slider rows at layout time (T_ROW_Y: their first spot).
            local TOGGLE_ROW_H = 22
            local T_ROW_Y = S_ROW_Y - SLIDER_H - GAP
            popFrame._TOGGLE_ROW_H = TOGGLE_ROW_H

            -- Standard cog-popup dropdown sizing (matches BuildCogPopup's dropdown rows): 130px wide, rendered 10% smaller, right-aligned at layout time.
            -- Each menu parents to UIParent; its OnShow scales it to the control's
            -- whole scale chain (this 0.9, the popup, the Window Scale).
            local DD_W = 130
            local DD_SCALE = 0.9
            popFrame._DD_SCALE = DD_SCALE
            -- The Name Format list: one control for every text slot, built on
            -- first need; its getValue/setValue delegate to the per-show getter
            -- and setter. Its Character Count entry saves through the per-show
            -- setter, as a pick does. Enemy names show here, so retail warns
            -- that the game keeps them whole in restricted content.
            local nameFormatDD
            popFrame._NameFormatDD = function()
                if not nameFormatDD then
                    local values, sequence, getValue, setValue = CludesUI.NameFormatMenu(
                        function() return popFrame._dd2Get and popFrame._dd2Get() or "" end,
                        function(val)
                            if popFrame._dd2Set then popFrame._dd2Set(val) end
                        end,
                        {
                            onSaved = function() nameFormatDD._refreshLabel() end,
                            enemies = true,
                        }
                    )
                    nameFormatDD = CludesUI.BuildDropdownControl(
                        popFrame,
                        CludesUI.NAME_FORMAT_MENU_W,
                        popFrame:GetFrameLevel() + 6,
                        values,
                        sequence,
                        getValue,
                        setValue
                    )
                    nameFormatDD:SetScale(DD_SCALE)
                    nameFormatDD:Hide()
                end
                return nameFormatDD
            end

            -- Optional toggle row, anchored at layout time directly after the slider rows. Wired via pf._toggleGet/Set.
            local tLabel = MakeFont(popFrame, 12, nil, 1, 1, 1)
            tLabel:SetAlpha(0.6)
            tLabel:SetPoint("LEFT", popFrame, "TOPLEFT", SIDE_PAD, T_ROW_Y - TOGGLE_ROW_H / 2)
            tLabel:Hide()
            popFrame._tLabel = tLabel
            local tToggle, _, tToggleSnap = CludesUI.BuildToggleControl(
                popFrame,
                popFrame:GetFrameLevel() + 5,
                function() return popFrame._toggleGet and popFrame._toggleGet() or false end,
                function(val)
                    if popFrame._toggleSet then popFrame._toggleSet(val) end
                end,
                { sizeRatio = 0.8, noAnim = true }
            )
            tToggle:SetPoint("RIGHT", popFrame, "TOPRIGHT", -SIDE_PAD, T_ROW_Y - TOGGLE_ROW_H / 2)
            tToggle:Hide()
            popFrame._tToggle = tToggle
            popFrame._toggleSnap = tToggleSnap

            -- Optional "Strata" dropdown row (Core Text slots): the standard
            -- strata dropdown, static option set, positioned below the toggle
            -- row at layout time; wired via pf._strataGetFn/SetFn.
            local stLabel = MakeFont(popFrame, 12, nil, 1, 1, 1)
            stLabel:SetAlpha(0.6)
            stLabel:SetText(CludesUI.L("Strata"))
            stLabel:SetPoint("LEFT", popFrame, "TOPLEFT", SIDE_PAD, T_ROW_Y - TOGGLE_ROW_H / 2)
            stLabel:Hide()
            popFrame._stLabel = stLabel
            local stDD = CludesUI.BuildDropdownControl(
                popFrame,
                DD_W,
                popFrame:GetFrameLevel() + 6,
                CludesUI.FRAME_STRATA_LABELS,
                CludesUI.FRAME_STRATA_ORDER_BASE,
                function() return popFrame._strataGetFn and popFrame._strataGetFn() or "MEDIUM" end,
                function(val)
                    if popFrame._strataSetFn then popFrame._strataSetFn(val) end
                end
            )
            stDD:SetScale(DD_SCALE)
            stDD:Hide()
            popFrame._stDD = stDD

            -- Optional "Wrap" toggle row (own row), used by truncating text elements so it coexists with the generic toggle (e.g. health text keeps Decimal there, Wrap here); wired via pf._wrapGet/Set.
            local wrapLabel = MakeFont(popFrame, 12, nil, 1, 1, 1)
            wrapLabel:SetAlpha(0.6)
            wrapLabel:SetText(CludesUI.L("Wrap"))
            wrapLabel:SetPoint("LEFT", popFrame, "TOPLEFT", SIDE_PAD, T_ROW_Y - TOGGLE_ROW_H / 2)
            wrapLabel:Hide()
            popFrame._wrapLabel = wrapLabel
            -- Invisible hover region over the Wrap label for its tooltip (see the Width % hover above); tracks the label, shown/hidden with the row.
            local wrapHover = CreateFrame("Frame", nil, popFrame)
            wrapHover:SetFrameLevel(popFrame:GetFrameLevel() + 10)
            wrapHover:SetAllPoints(wrapLabel)
            wrapHover:EnableMouse(true)
            wrapHover:Hide()
            wrapHover:SetScript(
                "OnEnter",
                function(self)
                    CludesUI.ShowWidgetTooltip(
                        self,
                        CludesUI.L("Lets long text wrap onto a second line instead of being cut off."),
                        { width = 230 }
                    )
                end
            )
            wrapHover:SetScript("OnLeave", function() CludesUI.HideWidgetTooltip() end)
            popFrame._wrapHover = wrapHover
            local wrapToggle, _, wrapToggleSnap = CludesUI.BuildToggleControl(
                popFrame,
                popFrame:GetFrameLevel() + 5,
                function() return popFrame._wrapGet and popFrame._wrapGet() or false end,
                function(val)
                    if popFrame._wrapSet then popFrame._wrapSet(val) end
                end,
                { sizeRatio = 0.8, noAnim = true }
            )
            wrapToggle:SetPoint("RIGHT", popFrame, "TOPRIGHT", -SIDE_PAD, T_ROW_Y - TOGGLE_ROW_H / 2)
            wrapToggle:Hide()
            popFrame._wrapToggle = wrapToggle
            popFrame._wrapToggleSnap = wrapToggleSnap

            -- Optional Name Format dropdown row (own row, below Wrap), its control
            -- from pf._NameFormatDD; label per show, via pf._dd2Get/Set.
            local d2Label = MakeFont(popFrame, 12, nil, 1, 1, 1)
            d2Label:SetAlpha(0.6)
            d2Label:SetPoint("LEFT", popFrame, "TOPLEFT", SIDE_PAD, T_ROW_Y - TOGGLE_ROW_H / 2)
            d2Label:Hide()
            popFrame._d2Label = d2Label

            -- Layout constants stored for height calc
            popFrame._TOP_PAD = TOP_PAD
            popFrame._TITLE_H = TITLE_H
            popFrame._TITLE_GAP = TITLE_GAP
            popFrame._GAP = GAP
            popFrame._SLIDER_H = SLIDER_H
            popFrame._SIDE_PAD = SIDE_PAD
            popFrame._POPUP_W = POPUP_W

            -- Close on click outside
            local wasDown = false
            popFrame._clickOutside = function(self, dt)
                if CogOwnerGone() then
                    self:Hide()
                    return
                end
                local down = IsMouseButtonDown("LeftButton")
                if down and not wasDown then
                    -- The Strata and Name Format menus float outside this popup's rect; a click there must not count as click-outside.
                    local m2 = self._stDD and self._stDD._ddMenu
                    local m3 = self._d2DD and self._d2DD._ddMenu
                    local overMenu = (m2 and m2:IsShown() and m2:IsMouseOver())
                        or (m3 and m3:IsShown() and m3:IsMouseOver())
                    local ownerFrame = LiveCogOwner()
                    if
                        not self:IsMouseOver()
                        and not (ownerFrame and ownerFrame:IsMouseOver())
                        and not overMenu
                    then
                        self:Hide()
                    end
                end
                wasDown = down
            end

            popFrame:SetScript("OnHide", function(self)
                self:SetScript("OnUpdate", nil)
                local ownerFrame = LiveCogOwner()
                cogPopupOwner, cogPopupOwnerGen = nil, nil
                -- Every cog that opens this popup is a BuildInlineCog: its own
                -- state pass dims it again.
                if ownerFrame and ownerFrame._cuiCogState then ownerFrame._cuiCogState() end
            end)

            if CludesUI._mainFrame then
                CludesUI._mainFrame:HookScript("OnHide", function()
                    if popFrame:IsShown() then popFrame:Hide() end
                end)
            end

            popFrame._refreshFns = {}
            for idx = firstRefresh, #refreshList do
                popFrame._refreshFns[#popFrame._refreshFns + 1] = refreshList[idx]
            end
            popFrame._refreshSerial = buildSerial
            cogPopup = popFrame
        end
        -- Each page build starts a fresh refresh list: the first cog shown from
        -- a build the popup was not built on registers the popup's sliders there.
        if cogPopup._refreshSerial ~= buildSerial then
            for idx = 1, #cogPopup._refreshFns do
                CludesUI.RegisterWidgetRefresh(cogPopup._refreshFns[idx])
            end
            cogPopup._refreshSerial = buildSerial
        end

        -- Toggle off if same icon clicked again
        if LiveCogOwner() == anchorBtn and cogPopup:IsShown() then
            cogPopup:Hide()
            return
        end

        -- Wire getters/setters
        cogPopup._xGet = options.xGet
        cogPopup._xSet = options.xSet
        cogPopup._yGet = options.yGet
        cogPopup._ySet = options.ySet
        cogPopup._titleFS:SetText(CludesUI.L(options.title))
        local prevOwner = LiveCogOwner()
        cogPopupOwner, cogPopupOwnerGen = anchorBtn, PoolGen(anchorBtn)
        if prevOwner and prevOwner._cuiCogState then prevOwner._cuiCogState() end

        -- Show/hide size row and adjust height
        local hasSize = options.sizeGet ~= nil
        local hasWidth = options.widthGet ~= nil
        local hasToggle = options.toggleGet ~= nil
        local hasWrap = options.wrapGet ~= nil
        local hasDropdown2 = options.dropdown2Get ~= nil
        local hasStrata = options.strataGet ~= nil
        if hasSize then
            -- One size slider per range, built the first time a cog needs it and
            -- kept: a range change shows that range's slider and hides the last.
            local sStep = options.sizeStep or 1
            if
                cogPopup._curMin ~= options.sizeMin
                or cogPopup._curMax ~= options.sizeMax
                or cogPopup._curStep ~= sStep
            then
                if cogPopup._sTrack then cogPopup._sTrack:Hide() end
                if cogPopup._sValBox then cogPopup._sValBox:Hide() end
                local sliders = cogPopup._sSliders
                if not sliders then
                    sliders = {}
                    cogPopup._sSliders = sliders
                end
                local key = tostring(options.sizeMin)
                    .. "/"
                    .. tostring(options.sizeMax)
                    .. "/"
                    .. tostring(sStep)
                local record = sliders[key]
                if not record then
                    -- Registers itself with this page; later pages get it through
                    -- the popup's refresh list.
                    local sTrack, sValBox, sRefresh = CludesUI.BuildSliderCore(
                        cogPopup,
                        cogPopup._SLIDER_W,
                        4,
                        12,
                        34,
                        24,
                        11,
                        CludesUI.SL_INPUT_A,
                        options.sizeMin,
                        options.sizeMax,
                        sStep,
                        function() return cogPopup._sGet and cogPopup._sGet() or 0 end,
                        function(val)
                            if cogPopup._sSet then cogPopup._sSet(val) end
                        end,
                        true
                    )
                    sTrack:ClearAllPoints()
                    sTrack:SetPoint(
                        "TOPLEFT",
                        cogPopup,
                        "TOPLEFT",
                        cogPopup._SLIDER_LEFT,
                        cogPopup._S_ROW_Y - (cogPopup._SLIDER_H - 20) / 2
                    )
                    sValBox:ClearAllPoints()
                    sValBox:SetPoint("TOPRIGHT", cogPopup, "TOPRIGHT", -cogPopup._SIDE_PAD, cogPopup._S_ROW_Y)
                    record = { track = sTrack, valBox = sValBox }
                    sliders[key] = record
                    cogPopup._refreshFns[#cogPopup._refreshFns + 1] = sRefresh
                end
                cogPopup._sTrack = record.track
                cogPopup._sValBox = record.valBox
                cogPopup._curMin = options.sizeMin
                cogPopup._curMax = options.sizeMax
                cogPopup._curStep = sStep
            end
            cogPopup._sGet = options.sizeGet
            cogPopup._sSet = options.sizeSet
            cogPopup._sLabel:SetText(CludesUI.L(options.sizeLabel or "Size"))
            cogPopup._sLabel:Show()
            if cogPopup._sTrack then cogPopup._sTrack:Show() end
            if cogPopup._sValBox then cogPopup._sValBox:Show() end
        else
            cogPopup._sLabel:Hide()
            if cogPopup._sTrack then cogPopup._sTrack:Hide() end
            if cogPopup._sValBox then cogPopup._sValBox:Hide() end
        end

        -- Show/hide width % row
        if hasWidth then
            cogPopup._wGet = options.widthGet
            cogPopup._wSet = options.widthSet
            cogPopup._wLabel:Show()
            cogPopup._wTrack:Show()
            cogPopup._wValBox:Show()
            if cogPopup._wHover then cogPopup._wHover:Show() end
        else
            cogPopup._wGet = nil
            cogPopup._wSet = nil
            cogPopup._wLabel:Hide()
            cogPopup._wTrack:Hide()
            cogPopup._wValBox:Hide()
            if cogPopup._wHover then cogPopup._wHover:Hide() end
        end

        -- Show/hide toggle row
        if hasToggle then
            cogPopup._toggleGet = options.toggleGet
            cogPopup._toggleSet = options.toggleSet
            cogPopup._tLabel:SetText(CludesUI.L(options.toggleLabel or ""))
            cogPopup._tLabel:Show()
            cogPopup._tToggle:Show()
            if cogPopup._toggleSnap then cogPopup._toggleSnap() end
        else
            cogPopup._toggleGet = nil
            cogPopup._toggleSet = nil
            cogPopup._tLabel:Hide()
            cogPopup._tToggle:Hide()
        end

        -- Show/hide Wrap row (its own row)
        if hasWrap then
            cogPopup._wrapGet = options.wrapGet
            cogPopup._wrapSet = options.wrapSet
            cogPopup._wrapLabel:Show()
            cogPopup._wrapToggle:Show()
            if cogPopup._wrapToggleSnap then cogPopup._wrapToggleSnap() end
            if cogPopup._wrapHover then cogPopup._wrapHover:Show() end
        else
            cogPopup._wrapGet = nil
            cogPopup._wrapSet = nil
            cogPopup._wrapLabel:Hide()
            cogPopup._wrapToggle:Hide()
            if cogPopup._wrapHover then cogPopup._wrapHover:Hide() end
        end

        -- Show/hide the Name Format dropdown row
        if hasDropdown2 then
            cogPopup._dd2Get = options.dropdown2Get
            cogPopup._dd2Set = options.dropdown2Set
            local d2DD = cogPopup._NameFormatDD()
            cogPopup._d2DD = d2DD
            -- The Name Format control is shared by every slot: its tooltip is
            -- set again on each show.
            d2DD._ttText = options.dropdown2Tooltip
            d2DD._refreshLabel()
            d2DD:Show()
            cogPopup._d2Label:SetText(CludesUI.L(options.dropdown2Label or ""))
            cogPopup._d2Label:Show()
        else
            cogPopup._dd2Get = nil
            cogPopup._dd2Set = nil
            cogPopup._d2Label:Hide()
            if cogPopup._d2DD then cogPopup._d2DD:Hide() end
        end

        -- Show/hide Strata row (standard strata dropdown, its own row)
        if hasStrata then
            cogPopup._strataGetFn = options.strataGet
            cogPopup._strataSetFn = options.strataSet
            if cogPopup._stDD then
                -- Static option set: the kept menu stays; the selected-value label
                -- follows this cog's getter.
                cogPopup._stDD._refreshLabel()
                cogPopup._stDD:Show()
            end
            cogPopup._stLabel:Show()
        else
            cogPopup._strataGetFn = nil
            cogPopup._strataSetFn = nil
            cogPopup._stLabel:Hide()
            if cogPopup._stDD then cogPopup._stDD:Hide() end
        end

        -- Row order: cogs passing sizeFirst put Size at the top; others keep X, Y, Size. The toggle, Strata, Wrap and Name Format rows follow the slider rows in that order, Width % last.
        do
            local p = cogPopup
            local SH, SLEFT, SPAD = p._SLIDER_H, p._SLIDER_LEFT, p._SIDE_PAD
            local TRH = p._TOGGLE_ROW_H
            local DS = p._DD_SCALE or 1
            local function rowTop(idx) return p._ROW0 - (idx - 1) * p._ROW_STEP end
            local function anchorRow(labelFS, track, valBox, ry)
                labelFS:ClearAllPoints()
                labelFS:SetPoint("LEFT", p, "TOPLEFT", SPAD, ry - SH / 2)
                if track then
                    track:ClearAllPoints()
                    track:SetPoint("TOPLEFT", p, "TOPLEFT", SLEFT, ry - 2)
                end
                if valBox then
                    valBox:ClearAllPoints()
                    valBox:SetPoint("TOPRIGHT", p, "TOPRIGHT", -SPAD, ry)
                end
            end
            -- Width % is intentionally NOT in this data-row sequence -- it's repositioned to the very bottom (below Wrap) further down, so it never sits between Size and X/Y.
            local seq = {}
            if hasSize and options.sizeFirst then
                seq[#seq + 1] = { p._sLabel, p._sTrack, p._sValBox }
                seq[#seq + 1] = { p._xLabel, p._xTrack, p._xValBox }
                seq[#seq + 1] = { p._yLabel, p._yTrack, p._yValBox }
            else
                seq[#seq + 1] = { p._xLabel, p._xTrack, p._xValBox }
                seq[#seq + 1] = { p._yLabel, p._yTrack, p._yValBox }
                if hasSize then seq[#seq + 1] = { p._sLabel, p._sTrack, p._sValBox } end
            end
            for idx, r in ipairs(seq) do
                anchorRow(r[1], r[2], r[3], rowTop(idx))
            end
            -- The toggle row sits directly after the data rows.
            local toggleY = rowTop(#seq + 1)
            p._tLabel:ClearAllPoints()
            p._tLabel:SetPoint("LEFT", p, "TOPLEFT", SPAD, toggleY - TRH / 2)
            p._tToggle:ClearAllPoints()
            p._tToggle:SetPoint("RIGHT", p, "TOPRIGHT", -SPAD, toggleY - TRH / 2)
            -- Strata dropdown row: below the toggle row. Right-aligned like standard cog dropdowns; offsets divided by the control's scale so the scaled frame lands flush-right and vertically centered.
            local strataY = rowTop(#seq + 1 + (hasToggle and 1 or 0))
            p._stLabel:ClearAllPoints()
            p._stLabel:SetPoint("LEFT", p, "TOPLEFT", SPAD, strataY - TRH / 2)
            if p._stDD then
                p._stDD:ClearAllPoints()
                p._stDD:SetPoint("RIGHT", p, "TOPRIGHT", -SPAD / DS, (strataY - TRH / 2) / DS)
            end
            -- Rows consumed by the toggle and Strata rows (0-2).
            local extraRows = (hasToggle and 1 or 0) + (hasStrata and 1 or 0)
            -- Wrap sits in its own row, below the toggle and Strata rows when present, else after the data rows.
            local wrapY = rowTop(#seq + 1 + extraRows)
            p._wrapLabel:ClearAllPoints()
            p._wrapLabel:SetPoint("LEFT", p, "TOPLEFT", SPAD, wrapY - TRH / 2)
            p._wrapToggle:ClearAllPoints()
            p._wrapToggle:SetPoint("RIGHT", p, "TOPRIGHT", -SPAD, wrapY - TRH / 2)
            -- Name Format dropdown: its own row below Wrap.
            local d2RowIndex = #seq + 1 + extraRows + (hasWrap and 1 or 0)
            local d2Y = rowTop(d2RowIndex)
            p._d2Label:ClearAllPoints()
            p._d2Label:SetPoint("LEFT", p, "TOPLEFT", SPAD, d2Y - TRH / 2)
            if p._d2DD then
                p._d2DD:ClearAllPoints()
                p._d2DD:SetPoint("RIGHT", p, "TOPRIGHT", -SPAD / DS, (d2Y - TRH / 2) / DS)
            end
            -- Width % is the very last row, below Wrap and Name Format; stays a slider row, so anchorRow handles label+track+box.
            if hasWidth then
                anchorRow(p._wLabel, p._wTrack, p._wValBox, rowTop(d2RowIndex + (hasDropdown2 and 1 or 0)))
            end
        end

        -- Compute height based on visible rows
        do
            local p = cogPopup
            local rowH = p._SLIDER_H
            local gap = p._GAP
            local height = p._TOP_PAD
                + p._TITLE_H
                + p._TITLE_GAP
                + gap
                + rowH -- X
                + gap
                + rowH -- Y
            if hasSize then height = height + gap + rowH end
            if hasWidth then height = height + gap + rowH end
            -- The toggle, Wrap, Name Format and Strata rows each occupy their own row.
            if hasToggle then height = height + gap + p._TOGGLE_ROW_H end
            if hasWrap then height = height + gap + p._TOGGLE_ROW_H end
            if hasDropdown2 then height = height + gap + p._TOGGLE_ROW_H end
            if hasStrata then height = height + gap + p._TOGGLE_ROW_H end
            height = height + p._TOP_PAD
            cogPopup:SetHeight(height)
        end

        -- Anchor above the icon
        cogPopup:ClearAllPoints()
        cogPopup:SetPoint("BOTTOM", anchorBtn, "TOP", 0, 6)

        -- Slide-up animation
        cogPopup:SetAlpha(0)
        cogPopup:Show()
        local elapsed = 0
        local ANIM_DUR = 0.15
        cogPopup:SetScript("OnUpdate", function(self, dt)
            -- A build dressed the anchor again mid-slide.
            if CogOwnerGone() then
                self:Hide()
                return
            end
            elapsed = elapsed + dt
            local t = math.min(elapsed / ANIM_DUR, 1)
            self:SetAlpha(t)
            self:ClearAllPoints()
            self:SetPoint("BOTTOM", anchorBtn, "TOP", 0, 6 + (-8 * (1 - t)))
            if t >= 1 then self:SetScript("OnUpdate", self._clickOutside) end
        end)

        CludesUI:RefreshPage()
    end

    local DISABLED_TIP = "This option requires an aura or indicator to be assigned"

    -- Per-kind slot Tracked Auras popup (12.1). Filter composition is INTERNAL (debuffs=Default, dcc=CC+Default, cc=CC; Default is Blizzard's
    -- nameplateShowPersonal curation): holds only Show All Debuffs (debuffs only) + INCLUDED/EXCLUDED lists (debuff side shared by debuffs/dcc; cc has its own pair). Storage/engine groups live in the containers file (ns.NPF_Root/Include/Exclude, NPC_ReloadAll).
    local NPF_KIND_TITLES = {
        debuffs = "Debuff Custom Spell IDs",
        cc = "CC Custom Spell IDs",
        dcc = "Debuffs + CC Custom Spell IDs",
    }
    local function ShowFilterPopup(kind)
        local root = mod.NPF_Root and mod.NPF_Root()
        if not root then return end
        -- List side + Show All availability: only debuffs has Show All; dcc is always CC+Default, cc is always CC.
        local side = (kind == "cc") and "cc" or "debuff"
        -- Any-caster OPT-OUTS for INCLUDED entries: default is Only My Casts (npincmine); flagged ids ride npinc.
        local function AnyMap() return mod.NPF_IncludeAny and mod.NPF_IncludeAny(side) end
        local function Reload()
            if mod.NPC_ReloadAll then mod.NPC_ReloadAll() end
        end
        CludesUI.ShowTrackedAurasPopup({
            eyebrow = CludesUI.L("NAMEPLATE AURA FILTERS"),
            title = NPF_KIND_TITLES[kind] or "Filters",
            fontPath = (CludesUI.GetFontPath("nameplates")) or DbValue("font"),
            includeGet = function() return mod.NPF_Include and mod.NPF_Include(side) end,
            excludeGet = function() return mod.NPF_Exclude and mod.NPF_Exclude(side) end,
            includePrompt = CludesUI.L("Enter the spell ID to always show on nameplates."),
            excludePrompt = CludesUI.L("Enter the spell ID to exclude from nameplates."),
            includeMine = { anyGet = AnyMap },
            -- Fresh adds default to Only My Casts; a spell migrating to the exclude list drops any stale flag.
            onAdd = function(ident)
                local am = AnyMap()
                if am then am[ident] = nil end
            end,
            onChanged = Reload,
            showAll = (kind == "debuffs") and {
                label = CludesUI.L("Show All Debuffs"),
                get = function() return root.debuffs and root.debuffs.all end,
                set = function(val)
                    root.debuffs = root.debuffs or {}
                    root.debuffs.all = val
                    Reload()
                end,
            } or nil,
        })
    end

    -- The Core Positions cogs' shared tables: each aura row's own keys (by
    -- checkbox dropdown row), the corner slots' Grow lists, the faction badge's
    -- PvP Flag and Icon Style lists.
    local CoreCog = {
        AURA = {
            debuffs = {
                slot = "debuffSlot",
                spacing = "debuffSpacing",
                crop = "debuffCropIcons",
                cropPct = "debuffCropPercent",
                border = "hideDebuffIconBorder",
            },
            buffs = {
                slot = "buffSlot",
                spacing = "buffSpacing",
                crop = "buffCropIcons",
                cropPct = "buffCropPercent",
                border = "hideBuffIconBorder",
            },
            ccs = {
                slot = "ccSlot",
                spacing = "ccSpacing",
                crop = "ccCropIcons",
                cropPct = "ccCropPercent",
                border = "hideCCIconBorder",
            },
        },
        GROW = {
            topleft = {
                values = { left = "Left", right = "Right", up = "Up" },
                order = { "left", "right", "up" },
            },
            topright = {
                values = { right = "Right", left = "Left", up = "Up" },
                order = { "right", "left", "up" },
            },
        },
        PVP_VALUES = { dim = "Dim Unflagged", only = "Flagged Only", ignore = "Ignore" },
        PVP_ORDER = { "dim", "only", "ignore" },
        STYLE_VALUES = {},
    }
    for _, keyName in ipairs(CludesUI.FACTION_ART_ORDER) do
        CoreCog.STYLE_VALUES[keyName] = CludesUI.FACTION_ART_LABELS[keyName]
    end
    -- The first aura row in the slot's order that is a row of its own (Crowd
    -- Control inside the debuff row is that row's): the row the Auras section
    -- reads.
    function CoreCog.FirstAura(place)
        local keyList = CoreOrderKeys(place)
        for idx = 1, #keyList do
            local a = CoreCog.AURA[keyList[idx]]
            if a and DbValue(a.slot) == place then return keyList[idx] end
        end
        return "debuffs"
    end
    -- An Auras section value (field: "size" or a key of CoreCog.AURA's rows),
    -- read from the slot's first aura row.
    function CoreCog.AuraGet(place, field)
        local keyName = CoreCog.FirstAura(place)
        if field == "size" then return mod.NP_ElementSize(keyName, DB()) end
        return DbValue(CoreCog.AURA[keyName][field])
    end
    -- Written to every aura row the slot holds.
    function CoreCog.AuraSet(place, field, val)
        local saved = DB()
        for keyName, a in pairs(CoreCog.AURA) do
            if CoreHas(place, keyName) then
                saved[(field == "size") and mod.NP_CORE_SIZE_KEY[keyName] or a[field]] = val
            end
        end
    end

    -- A slot cog's sections: the slot's own rows and one section per unique
    -- element it holds, in a fixed order (Slot, Auras, Raid Marker, Elite/Rare
    -- Indicator, Quest Indicator, Quest Objective Text, Faction). An element's
    -- section shows while the slot holds it; with three or more showing they
    -- sit side by side as columns under their headers, else their rows stack
    -- in one column, the Slot rows last. Every aura row shares the Auras
    -- section, which reads the slot's first aura row and writes them all.
    function CoreCog.Sections(posKey)
        local function redraw()
            RefreshAllSlots()
            RepaintPreview()
        end
        local function Lacks(keyName)
            return function() return not CoreHas(posKey, keyName) end
        end
        local function SizeRow(elem)
            local key = mod.NP_CORE_SIZE_KEY[elem]
            return {
                type = "slider",
                label = "Size",
                min = 10,
                max = 50,
                step = 1,
                get = function() return mod.NP_ElementSize(elem, DB()) end,
                set = function(val)
                    DB()[key] = val
                    redraw()
                end,
            }
        end
        -- Show In Instances: the quest scan's caches follow it, so they are
        -- dropped and every plate's indicators run again.
        local function InstancesRow(kind)
            local key = mod.NP_SHOW_IN_INSTANCES_KEY[kind]
            return {
                type = "toggle",
                label = "Show In Instances",
                tooltip = "Also shows inside dungeons, raids and other instances.",
                get = function() return mod.NP_ShowInInstances(kind, DB()) end,
                set = function(val)
                    DB()[key] = val and true or false
                    mod.RefreshQuestObjective()
                    redraw()
                end,
            }
        end

        local slotRows = {
            {
                type = "slider",
                label = "X Offset",
                min = -300,
                max = 300,
                step = 1,
                get = function() return CorePosXGet(posKey) end,
                set = function(val) CorePosXSet(posKey, val) end,
            },
            {
                type = "slider",
                label = "Y Offset",
                min = -300,
                max = 300,
                step = 1,
                get = function() return CorePosYGet(posKey) end,
                set = function(val) CorePosYSet(posKey, val) end,
            },
        }
        local grow = CoreCog.GROW[posKey]
        if grow then
            local growthKey = posKey .. "SlotGrowth"
            slotRows[#slotRows + 1] = {
                type = "dropdown",
                label = "Grow",
                values = grow.values,
                order = grow.order,
                get = function() return DbValue(growthKey) end,
                set = function(val)
                    DB()[growthKey] = val
                    redraw()
                end,
            }
        end
        -- Element Spacing: the gap between the slot's elements, following the
        -- slot's Spacing (the first aura row's) until set.
        local esKey = posKey .. "SlotElementSpacing"
        slotRows[#slotRows + 1] = {
            type = "slider",
            label = "Element Spacing",
            min = -5,
            max = 20,
            step = 1,
            tooltip = "Space between the elements sharing this slot. Follows the slot's Spacing until you change it.",
            hidden = function() return mod.NP_CoreMemberCount(posKey) < 2 end,
            get = function() return mod.NP_CoreElementSpacing(posKey) end,
            set = function(val)
                DB()[esKey] = val
                redraw()
            end,
        }
        -- Raise Strata: bumps the slot's elements one strata level up so they
        -- render above the rest of the plate.
        local rsKey = posKey .. "SlotRaiseStrata"
        slotRows[#slotRows + 1] = {
            type = "toggle",
            label = "Raise Strata",
            tooltip = "Renders this slot's element above the rest of the nameplate.",
            get = function() return DbValue(rsKey) and true or false end,
            set = function(val)
                DB()[rsKey] = val and true or false
                redraw()
            end,
        }

        return {
            { title = "Slot", stackLast = true, rows = slotRows },
            {
                title = "Auras",
                hidden = function()
                    return not (
                        CoreHas(posKey, "debuffs")
                        or CoreHas(posKey, "buffs")
                        or CoreHas(posKey, "ccs")
                    )
                end,
                rows = {
                    {
                        type = "slider",
                        label = "Size",
                        min = 10,
                        max = 50,
                        step = 1,
                        get = function() return CoreCog.AuraGet(posKey, "size") end,
                        set = function(val)
                            CoreCog.AuraSet(posKey, "size", val)
                            redraw()
                        end,
                    },
                    {
                        type = "slider",
                        label = "Spacing",
                        min = -5,
                        max = 20,
                        step = 1,
                        get = function() return CoreCog.AuraGet(posKey, "spacing") end,
                        set = function(val)
                            CoreCog.AuraSet(posKey, "spacing", val)
                            redraw()
                        end,
                    },
                    -- Blizzard Style: the stock aura ring replaces the 1px border.
                    {
                        type = "toggle",
                        label = "Hide Border",
                        hidden = function() return CludesUI.BlizzStyle.Get("nameplates") and true or false end,
                        get = function() return CoreCog.AuraGet(posKey, "border") == true end,
                        set = function(val)
                            CoreCog.AuraSet(posKey, "border", val and true or false)
                            -- The live slot borders only catch up through a full settings pass.
                            mod.RefreshAllSettings()
                            redraw()
                        end,
                    },
                    {
                        type = "toggle",
                        label = "Cropped Icons",
                        get = function() return CoreCog.AuraGet(posKey, "crop") == true end,
                        set = function(val)
                            CoreCog.AuraSet(posKey, "crop", val and true or false)
                            redraw()
                        end,
                    },
                    -- Adjust Crop: per-side trim percentage for the cropped mode.
                    {
                        type = "slider",
                        label = "Adjust Crop",
                        min = 5,
                        max = 25,
                        step = 1,
                        tooltip = "How much is trimmed from the icon's top and bottom, as a percentage per side. 10% is the classic cropped look.",
                        disabled = function() return CoreCog.AuraGet(posKey, "crop") ~= true end,
                        disabledTooltip = "Cropped Icons",
                        get = function() return CoreCog.AuraGet(posKey, "cropPct") or 10 end,
                        set = function(val)
                            CoreCog.AuraSet(posKey, "cropPct", val)
                            redraw()
                        end,
                    },
                },
            },
            { title = "Raid Marker", hidden = Lacks("raidmarker"), rows = { SizeRow("raidmarker") } },
            {
                title = "Elite/Rare Indicator",
                hidden = Lacks("rare"),
                rows = { SizeRow("rare"), InstancesRow("rare") },
            },
            {
                title = "Quest Indicator",
                hidden = Lacks("quest"),
                rows = { SizeRow("quest"), InstancesRow("quest") },
            },
            {
                title = "Quest Objective Text",
                hidden = Lacks("questtext"),
                rows = {
                    {
                        type = "toggle",
                        label = "Objective Type Icon",
                        tooltip = "Shows a sword for kill objectives, a bag for item objectives, and the generic quest icon when the type cannot be matched exactly.",
                        get = function() return DbValue("showQuestObjectiveTypeIcon") == true end,
                        set = function(val)
                            DB().showQuestObjectiveTypeIcon = val
                            mod.RefreshQuestObjective()
                            redraw()
                        end,
                    },
                    {
                        type = "slider",
                        label = "Icon Scale",
                        min = 50,
                        max = 200,
                        step = 5,
                        hidden = function() return DbValue("showQuestObjectiveTypeIcon") ~= true end,
                        get = function() return DbValue("questObjectiveTypeIconScale") or 100 end,
                        set = function(val)
                            DB().questObjectiveTypeIconScale = val
                            redraw()
                        end,
                    },
                    {
                        type = "slider",
                        label = "Text Size",
                        min = 6,
                        max = 24,
                        step = 1,
                        tooltip = "Size of the quest progress text.",
                        get = function() return mod.NP_QuestTextSize(DB()) end,
                        set = function(val)
                            DB().questObjectiveTextSize = val
                            mod.RefreshQuestObjective()
                            redraw()
                        end,
                    },
                    InstancesRow("questtext"),
                },
            },
            {
                title = "Faction",
                hidden = Lacks("faction"),
                rows = {
                    SizeRow("faction"),
                    {
                        type = "dropdown",
                        label = "PvP Flag",
                        values = CoreCog.PVP_VALUES,
                        order = CoreCog.PVP_ORDER,
                        get = function() return DbValue("factionPvP") end,
                        set = function(val)
                            DB().factionPvP = val
                            redraw()
                        end,
                    },
                    {
                        type = "dropdown",
                        label = "Icon Style",
                        values = CoreCog.STYLE_VALUES,
                        order = CludesUI.FACTION_ART_ORDER,
                        get = function() return DbValue("factionStyle") end,
                        set = function(val)
                            DB().factionStyle = val
                            redraw()
                        end,
                    },
                    {
                        type = "toggle",
                        label = "Opposite Faction Only",
                        get = function() return DbValue("factionOppositeOnly") == true end,
                        set = function(val)
                            DB().factionOppositeOnly = val and true or false
                            redraw()
                        end,
                    },
                    {
                        type = "toggle",
                        label = "Players Only",
                        tooltip = "Hide the faction badge on faction NPCs such as guards.",
                        get = function() return DbValue("factionPlayersOnly") == true end,
                        set = function(val)
                            DB().factionPlayersOnly = val and true or false
                            redraw()
                        end,
                    },
                },
            },
        }
    end

    local function NewPosCog(row, regionKey, posKey, slotLabel)
        local region = row[regionKey]
        -- The shared cog popup, sectioned per element (CoreCog.Sections).
        local button = CludesUI.BuildInlineCog(region, {
            anchorTo = region._control,
            title = CludesUI.Lf("%1$s Slot Settings", CludesUI.L(slotLabel)),
            disabled = function() return CorePosLocked(posKey) end,
            disabledTooltip = DISABLED_TIP,
            rawTooltip = true,
            sections = CoreCog.Sections(posKey),
            columnsFrom = 3,
        })
        -- The core eyes anchor to THIS, not _lastInline: the tracked-auras
        -- link below becomes _lastInline but is HIDDEN for the raid marker,
        -- Rare/Quest and Quest Objective Text slots (the only slots the eyes
        -- land on), and a hidden frame keeps its width, so an eye left of it
        -- would sit far from the cog.
        region._coreCogBtn = button

        -- Edit Tracked Auras (slot filters): accent link left of the cog when this row holds a debuff-side aura element, opens the per-kind filter popup; refreshes on the same widget-refresh channel as the cog alpha.
        local itemLink = CreateFrame("Button", nil, region)
        itemLink:SetFrameLevel(region:GetFrameLevel() + 5)
        local lfp = (CludesUI.GetFontPath("nameplates")) or DbValue("font")
        local lfs = itemLink:CreateFontString(nil, "OVERLAY")
        lfs:SetFont(lfp, 12, "")
        lfs:SetTextColor(CludesUI.GetAccentColor())
        -- Keyed by the font string: the page pool forgets the entry when it resets it.
        CludesUI.RegAccent({
            type = "callback",
            obj = lfs,
            fn = function(red, green, blue) lfs:SetTextColor(red, green, blue) end,
        })
        lfs:SetAlpha(0.85)
        lfs:SetPoint("CENTER")
        lfs:SetText(CludesUI.L("Edit Tracked Auras"))
        itemLink:SetSize(lfs:GetStringWidth() + 6, 16)
        itemLink:SetPoint("RIGHT", button, "LEFT", -6, 0)
        region._lastInline = itemLink
        -- The core eyes hang left of this link while it shows.
        region._coreLink = itemLink
        -- The debuff side's filters whenever the slot holds the debuff row (with
        -- Crowd Control inside it: both), else Crowd Control's own.
        local function LinkKind()
            if CoreHas(posKey, "debuffs") then
                return (DbValue("debuffIncludeCC") == true) and "dcc" or "debuffs"
            elseif CoreHas(posKey, "ccs") then
                return "cc"
            end
        end
        local function UpdLink()
            local keyName = LinkKind()
            itemLink:SetShown(keyName ~= nil)
            if keyName then
                -- CC slots track only CC, so the link says so.
                lfs:SetText(CludesUI.L(keyName == "cc" and "Edit Tracked CC" or "Edit Tracked Auras"))
                itemLink:SetSize(lfs:GetStringWidth() + 6, 16)
            end
        end
        itemLink:SetScript("OnEnter", function() lfs:SetAlpha(1) end)
        itemLink:SetScript("OnLeave", function() lfs:SetAlpha(0.85) end)
        itemLink:SetScript("OnClick", function()
            local keyName = LinkKind()
            if keyName then ShowFilterPopup(keyName) end
        end)
        CludesUI.RegisterWidgetRefresh(UpdLink)
        UpdLink()
        return button
    end

    hostFrame._showRowDivider = true

    -- Row 1: Top | Right
    coreRow1, height = W:DualRow(hostFrame, cursorY, {
        type = "dropdown",
        text = "Top",
        values = coreElementValues,
        order = coreElementOrder,
        getValue = function() return GetElementAtPosition("top") end,
        setValue = function(val) CoreSingleSet("top", val) end,
        disabled = function() return CorePosLocked("top") end,
        disabledTooltip = "This option requires an aura or indicator to be assigned",
        rawTooltip = true,
        labelOnlyDisabled = true,
    }, {
        type = "dropdown",
        text = "Right",
        values = coreElementValues,
        order = coreElementOrder,
        getValue = function() return GetElementAtPosition("right") end,
        setValue = function(val) CoreSingleSet("right", val) end,
        disabled = function() return CorePosLocked("right") end,
        disabledTooltip = "This option requires an aura or indicator to be assigned",
        rawTooltip = true,
        labelOnlyDisabled = true,
    })
    cursorY = cursorY - height
    if not CludesUI._prebuilding then
        InstallCoreCB(coreRow1._leftRegion, "top")
        InstallCoreCB(coreRow1._rightRegion, "right")
        NewPosCog(coreRow1, "_leftRegion", "top", "Top")
        NewPosCog(coreRow1, "_rightRegion", "right", "Right")
    end

    -- Row 2: Left | Top Right
    coreRow2, height = W:DualRow(hostFrame, cursorY, {
        type = "dropdown",
        text = "Left",
        values = coreElementValues,
        order = coreElementOrder,
        getValue = function() return GetElementAtPosition("left") end,
        setValue = function(val) CoreSingleSet("left", val) end,
        disabled = function() return CorePosLocked("left") end,
        disabledTooltip = "This option requires an aura or indicator to be assigned",
        rawTooltip = true,
        labelOnlyDisabled = true,
    }, {
        type = "dropdown",
        text = "Top Right",
        values = coreElementValues,
        order = coreElementOrder,
        getValue = function() return GetElementAtPosition("topright") end,
        setValue = function(val) CoreSingleSet("topright", val) end,
        disabled = function() return CorePosLocked("topright") end,
        disabledTooltip = "This option requires an aura or indicator to be assigned",
        rawTooltip = true,
        labelOnlyDisabled = true,
    })
    cursorY = cursorY - height
    if not CludesUI._prebuilding then
        InstallCoreCB(coreRow2._leftRegion, "left")
        InstallCoreCB(coreRow2._rightRegion, "topright")
        NewPosCog(coreRow2, "_leftRegion", "left", "Left")
        NewPosCog(coreRow2, "_rightRegion", "topright", "Top Right")
    end

    -- Row 3: Top Left | Bottom
    coreRow3, height = W:DualRow(hostFrame, cursorY, {
        type = "dropdown",
        text = "Top Left",
        values = coreElementValues,
        order = coreElementOrder,
        getValue = function() return GetElementAtPosition("topleft") end,
        setValue = function(val) CoreSingleSet("topleft", val) end,
        disabled = function() return CorePosLocked("topleft") end,
        disabledTooltip = "This option requires an aura or indicator to be assigned",
        rawTooltip = true,
        labelOnlyDisabled = true,
    }, {
        type = "dropdown",
        text = "Bottom",
        values = coreElementValues,
        order = coreElementOrder,
        getValue = function() return GetElementAtPosition("bottom") end,
        setValue = function(val) CoreSingleSet("bottom", val) end,
        disabled = function() return CorePosLocked("bottom") end,
        disabledTooltip = "This option requires an aura or indicator to be assigned",
        rawTooltip = true,
        labelOnlyDisabled = true,
    })
    cursorY = cursorY - height
    if not CludesUI._prebuilding then
        InstallCoreCB(coreRow3._leftRegion, "topleft")
        InstallCoreCB(coreRow3._rightRegion, "bottom")
        NewPosCog(coreRow3, "_leftRegion", "topleft", "Top Left")
        NewPosCog(coreRow3, "_rightRegion", "bottom", "Bottom")
    end

    -- Map each position to { row, regionKey } for eye icon anchoring
    local posToRegion = {
        top = { coreRow1, "_leftRegion" },
        right = { coreRow1, "_rightRegion" },
        left = { coreRow2, "_leftRegion" },
        topright = { coreRow2, "_rightRegion" },
        topleft = { coreRow3, "_leftRegion" },
        bottom = { coreRow3, "_rightRegion" },
    }
    context.corePosToRegion = posToRegion

    -- Where the Core Positions eye hangs: left of the slot's cog, past its Edit
    -- Tracked Auras link while that shows (never while hidden: the link keeps
    -- its width, so the eye would sit far left).
    local function EyeAnchor(region)
        local itemLink = region._coreLink
        if itemLink and itemLink:IsShown() then return itemLink end
        return region._coreCogBtn or region._control
    end

    -- One eye for every Core Positions element the preview hides until asked
    -- (the raid marker, the Elite/Rare and Quest Indicators, Quest Objective
    -- Text): a click shows or hides them all together. It hangs on the first
    -- slot, in the rows' reading order, that holds one of them.
    if not CludesUI._prebuilding then
        local EYE_VISIBLE = CludesUI.EYE_VISIBLE_ICON
        local EYE_INVISIBLE = CludesUI.EYE_INVISIBLE_ICON
        local EYE_SLOTS = { "top", "right", "left", "topright", "topleft", "bottom" }
        local eyeButton = CreateFrame("Button", nil, hostFrame)
        eyeButton:SetSize(26, 26)
        eyeButton:SetFrameLevel(hostFrame:GetFrameLevel() + 10)
        CludesUI.SetGlyphAlpha(eyeButton, 0.4)
        local eyeTex = eyeButton:CreateTexture(nil, "OVERLAY")
        eyeTex:SetAllPoints()
        local function PreviewShown()
            return optionState.showRaidMarkerPreview
                or optionState.showClassificationPreview
                or optionState.showQuestTextPreview
        end
        local function RefreshIcon() eyeTex:SetTexture(PreviewShown() and EYE_INVISIBLE or EYE_VISIBLE) end
        RefreshIcon()
        eyeButton:SetScript("OnClick", function()
            local show = not PreviewShown()
            optionState.showRaidMarkerPreview = show
            optionState.showClassificationPreview = show
            optionState.showQuestTextPreview = show
            RefreshIcon()
            RepaintPreview()
        end)
        eyeButton:SetScript("OnEnter", function(self)
            CludesUI.SetGlyphAlpha(self, 0.7)
            CludesUI.ShowWidgetTooltip(self, "Show/Hide on Preview", { width = 155 })
        end)
        eyeButton:SetScript("OnLeave", function(self)
            CludesUI.SetGlyphAlpha(self, 0.4)
            CludesUI.HideWidgetTooltip()
        end)
        _refreshCoreEyePos = function()
            for idx = 1, #EYE_SLOTS do
                local place = EYE_SLOTS[idx]
                if
                    CoreHas(place, "raidmarker")
                    or CoreHas(place, "rare")
                    or CoreHas(place, "quest")
                    or CoreHas(place, "questtext")
                then
                    local details = posToRegion[place]
                    local region = details[1][details[2]]
                    eyeButton:ClearAllPoints()
                    eyeButton:SetParent(region)
                    eyeButton:SetPoint("RIGHT", EyeAnchor(region), "LEFT", -8, 0)
                    eyeButton:SetFrameLevel(region:GetFrameLevel() + 5)
                    eyeButton:Show()
                    return
                end
            end
            eyeButton:Hide()
        end
        _refreshCoreEyePos()
    end

    _, height = W:Spacer(hostFrame, cursorY, 20)
    cursorY = cursorY - height

    -----------------------------------------------------------------------
    --  CORE TEXT POSITIONS
    -----------------------------------------------------------------------
    local coreTextHeader
    coreTextHeader, height = W:SectionHeader(hostFrame, "CORE TEXT POSITIONS", cursorY)
    cursorY = cursorY - height

    -- Subtitle hint next to the section header's title (same style as Core Positions)
    do
        local region = coreTextHeader._label
        if region and CludesUI.EnKey(region:GetText()) == "CORE TEXT POSITIONS" then
            local subMenu = coreTextHeader:CreateFontString(nil, "OVERLAY")
            subMenu:SetFont(region:GetFont())
            subMenu:SetTextColor(1, 1, 1, 0.25)
            subMenu:SetText(CludesUI.L("(one per slot)"))
            subMenu:SetPoint("LEFT", region, "RIGHT", 6, 0)
        end
    end

    local textElementValues = {
        enemyName = "Enemy Name",
        levelName = "Level | Name",
        nameLevel = "Name | Level",
        level = "Level",
        targetOfTarget = "Target of Target",
        healthPercent = "Health %",
        healthPercentNoSign = "Health % (No Sign)",
        healthNumber = "Health #",
        healthPctNum = "Health % | #",
        healthNumPct = "Health # | %",
        healthPctNumDash = "Health % - #",
        healthNumPctDash = "Health # - %",
        healthNumMax = "Health # / Max #",
        custom = "Custom",
        none = "Remove",
    }
    local textElementOrder = {
        "none",
        "---",
        "custom",
        "---",
        "enemyName",
        "levelName",
        "nameLevel",
        "level",
        "targetOfTarget",
        "healthPercent",
        "healthPercentNoSign",
        "healthNumber",
        "healthPctNum",
        "healthNumPct",
        "healthPctNumDash",
        "healthNumPctDash",
        "healthNumMax",
    }

    local function TextSlotSetValue(slotKey, val)
        -- Target of Target starts in Class mode whenever a slot newly takes it;
        -- the slot's Text Coloring dropdown still switches it back. The mode is
        -- saved only when the slot would not already derive Class.
        local newToT = val == "targetOfTarget" and DbValue(slotKey) ~= "targetOfTarget"
        SetTextElementAtSlot(slotKey, val)
        if newToT then
            local saved = DB()
            saved[slotKey .. "ColorMode"] = nil
            if mod.NP_SlotColorMode(slotKey, saved) ~= "class" then
                saved[slotKey .. "ColorMode"] = "class"
            end
        end
        mod.RefreshAllSettings()
        -- Rebuild: the list and the Core Text Coloring section follow the
        -- slotted elements (a slot change can also clear another slot).
        RepaintPreview()
        CludesUI:RefreshPage(true)
    end

    local function TextOffsetRefresh()
        mod.RefreshAllSettings()
        RepaintPreview()
    end

    -- Text slot X/Y offset helpers (parallel to CorePosXGet etc.)
    local function TextPosXGet(slotKey) return DbValue(slotKey .. "XOffset") or 0 end
    local function TextPosYGet(slotKey) return DbValue(slotKey .. "YOffset") or 0 end
    local function TextPosXSet(slotKey, val)
        DB()[slotKey .. "XOffset"] = val
        TextOffsetRefresh()
    end
    local function TextPosYSet(slotKey, val)
        DB()[slotKey .. "YOffset"] = val
        TextOffsetRefresh()
    end
    local function TextPosDisabled(slotKey) return DbValue(slotKey) == "none" end

    local TEXT_DISABLED_TIP = "This option requires a text to be assigned"

    local function MakeTextCogIcon(row, regionKey, slotKey, slotLabel)
        local region = row[regionKey]
        -- The shared boxed cog; its click opens this page's popup (OpenCog below).
        local OpenCog
        local button = CludesUI.BuildInlineCog(region, {
            disabled = function() return TextPosDisabled(slotKey) end,
            disabledTooltip = TEXT_DISABLED_TIP,
            rawTooltip = true,
            isOpen = CogPopupOpen,
            show = function(self) OpenCog(self) end,
        })
        OpenCog = function(self)
            if TextPosDisabled(slotKey) then return end
            local sizeKey = slotKey .. "Size"
            local cogOpts = {
                title = CludesUI.Lf("%1$s Settings", CludesUI.L(slotLabel)),
                xGet = function() return TextPosXGet(slotKey) end,
                xSet = function(val) TextPosXSet(slotKey, val) end,
                yGet = function() return TextPosYGet(slotKey) end,
                ySet = function(val) TextPosYSet(slotKey, val) end,
                sizeGet = function() return DbValue(sizeKey) or defaultSet[sizeKey] end,
                sizeSet = function(val)
                    DB()[sizeKey] = val
                    TextOffsetRefresh()
                end,
                sizeMin = 6,
                sizeMax = 30,
                sizeLabel = "Size",
                sizeFirst = true,
            }
            -- Both name and health text here get Width % + Wrap (dedicated Wrap row). Name-family variants use the GLOBAL enemyName keys (one slot holds the name FontString at a time); health text uses PER-SLOT keys (100% = no clip) and keeps "Show % Decimal". The corner slots never truncate, so they get neither.
            local cornerSlot = slotKey == "textSlotBottomLeft"
                or slotKey == "textSlotBottomRight"
                or slotKey == "textSlotTopLeft"
                or slotKey == "textSlotTopRight"
            if mod.IsNameElement(DbValue(slotKey)) then
                if not cornerSlot then
                    cogOpts.widthGet = function()
                        return DbValue("enemyNameWidthPct") or defaultSet.enemyNameWidthPct
                    end
                    cogOpts.widthSet = function(val)
                        DB().enemyNameWidthPct = val
                        mod.RefreshAllSettings()
                        RepaintPreview()
                    end
                    cogOpts.wrapGet = function() return DbValue("enemyNameWrap") == true end
                    cogOpts.wrapSet = function(val)
                        DB().enemyNameWrap = val
                        mod.RefreshAllSettings()
                        RepaintPreview()
                    end
                end
            else
                if not cornerSlot then
                    local widthKey = slotKey .. "WidthPct"
                    local wrapKey = slotKey .. "Wrap"
                    cogOpts.widthGet = function() return DbValue(widthKey) or 100 end
                    cogOpts.widthSet = function(val)
                        DB()[widthKey] = val
                        mod.RefreshAllSettings()
                        RepaintPreview()
                    end
                    cogOpts.wrapGet = function() return DbValue(wrapKey) == true end
                    cogOpts.wrapSet = function(val)
                        DB()[wrapKey] = val
                        mod.RefreshAllSettings()
                        RepaintPreview()
                    end
                end
                cogOpts.toggleLabel = "Show % Decimal"
                cogOpts.toggleGet = function() return DbValue(slotKey .. "PctDecimal") == true end
                cogOpts.toggleSet = function(val)
                    DB()[slotKey .. "PctDecimal"] = val
                    mod.RefreshAllSettings()
                    RepaintPreview()
                end
            end
            -- Target of Target, the standalone level and Custom (its template writes the
            -- percent) have no use for "Show % Decimal".
            local slotEl = DbValue(slotKey)
            if slotEl == "targetOfTarget" or slotEl == "level" or slotEl == "custom" then
                cogOpts.toggleLabel, cogOpts.toggleGet, cogOpts.toggleSet = nil, nil, nil
            end
            -- Name Format, while this slot shows a name, the Target of Target
            -- name, or a custom template that reads one. Full name is stored as
            -- nil (the runtime's unchanged path).
            local parsed = slotEl == "custom" and mod.NP_CustomParse(slotKey, DB())
            if
                mod.IsNameElement(slotEl)
                or slotEl == "targetOfTarget"
                or (parsed and (parsed.has.name or parsed.has.target))
            then
                local nfKey = slotKey .. "NameFormat"
                cogOpts.dropdown2Label = "Name Format"
                -- WoW Forever: First / Last Name skip non-players there
                -- (CludesUI.UnitNameFormat), the other modes do not.
                if CludesUI.IS_FOREVER == true then
                    cogOpts.dropdown2Tooltip =
                        "First Name and Last Name only change players' names; Abbreviated and Character Count change every name."
                end
                cogOpts.dropdown2Get = function() return DbValue(nfKey) or "full" end
                cogOpts.dropdown2Set = function(val)
                    DB()[nfKey] = (val ~= "full") and val or nil
                    mod.RefreshAllSettings()
                    RepaintPreview()
                end
            end
            -- Per-slot strata (partner request): standard strata dropdown,
            -- defaulting to the shared text tier's MEDIUM.
            cogOpts.strataGet = function() return DbValue(slotKey .. "Strata") or "MEDIUM" end
            cogOpts.strataSet = function(val)
                DB()[slotKey .. "Strata"] = val
                mod.RefreshAllSettings()
                RepaintPreview()
            end
            ShowCogPopup(self, cogOpts)
        end
        return button
    end

    hostFrame._showRowDivider = true

    -- The list: one cell per position that shows a text, two to a row in
    -- position order, then Add Text Slot. A text's name opens the positions it
    -- can move to, its dropdown picks what it shows (Remove takes it off; the
    -- position keeps its other settings) and its cog holds Size, offsets and
    -- the rest. Every check runs at click time, so a menu that outlived a
    -- change writes nothing stale; each structure change rebuilds the page.
    local function IsAssigned(slotKey) return KNOWN[DbValue(slotKey)] == true end
    local function IsFree(slotKey) return not IsAssigned(slotKey) end

    -- Add Text Slot's text: the first of ADD_ORDER whose font string no shown
    -- text uses, so adding never takes one off (nil when every one is used).
    local function FontStringUsed(fsKey)
        for idx = 1, #POS_ORDER do
            local s = POS_ORDER[idx]
            if IsAssigned(s) and mod.NP_ElementFSKey(DbValue(s)) == fsKey then return true end
        end
        return false
    end
    local function AddCandidate()
        for idx = 1, #ADD_ORDER do
            local el = ADD_ORDER[idx]
            if not FontStringUsed(mod.NP_ElementFSKey(el)) then return el end
        end
    end
    -- Why Add Text Slot is greyed (nil while a text can be added).
    local function AddBlocked()
        local full = true
        for idx = 1, #POS_ORDER do
            if IsFree(POS_ORDER[idx]) then full = false end
        end
        if full then return "Every text position is full." end
        if not AddCandidate() then return "Every text is already shown." end
    end
    -- Adds AddCandidate's text at the free position P, exactly as picking that
    -- element in an empty slot (TextSlotSetValue rebuilds the page, where the
    -- new text's cell reports the write to Spec Overrides). A position taken
    -- or every font string used since the menu opened only resyncs the page.
    local function AddText(P)
        local cand = AddCandidate()
        if not IsFree(P) or not cand then
            CludesUI:RefreshPage(true)
            return
        end
        optionState._npNotifySlot = P
        TextSlotSetValue(P, cand)
        optionState._npNotifySlot = nil
    end

    -- Moves the text at S to the free position T with its look: its element,
    -- its effective Size, its offsets (the tweak from S's default, added to
    -- T's default), the MOVE_RAW keys as saved and its colour mode (saved only
    -- when T would derive another, as the coloring dropdown does). T's old
    -- keys are replaced; S keeps its other keys, unused. A cell gone stale
    -- since its menu opened only resyncs the page.
    local function MoveText(S, T)
        if S == T then return end
        if not IsAssigned(S) or not IsFree(T) then
            CludesUI:RefreshPage(true)
            return
        end
        local saved = DB()
        local mode = mod.NP_SlotColorMode(S, saved) -- read before any write
        local el = DbValue(S)
        local size = DbValue(S .. "Size")
        local tSize = DbValue(T .. "Size")
        for idx = 1, #MOVE_OFFSETS do
            local suf = MOVE_OFFSETS[idx]
            local sDef = defaultSet[S .. suf] or 0
            local sv = saved[S .. suf]
            if sv == nil then sv = sDef end
            local val = (defaultSet[T .. suf] or 0) + (sv - sDef)
            if saved[T .. suf] ~= val then saved[T .. suf] = val end
        end
        for idx = 1, #MOVE_RAW do
            local suf = MOVE_RAW[idx]
            -- The template moves only with Custom; otherwise T keeps its own.
            if suf ~= "CustomFormat" or el == "custom" then
                local val = saved[S .. suf]
                if type(val) == "table" then val = CopyTable(val) end
                saved[T .. suf] = val
            end
        end
        if size ~= tSize then saved[T .. "Size"] = size end
        saved[T] = el
        saved[S] = "none"
        saved[T .. "ColorMode"] = nil
        if mod.NP_SlotColorMode(T, saved) ~= mode then saved[T .. "ColorMode"] = mode end
        mod.RefreshAllSettings()
        RepaintPreview()
        -- The moved text's new cell reports the write to Spec Overrides.
        optionState._npNotifySlot = T
        CludesUI:RefreshPage(true)
        optionState._npNotifySlot = nil
    end

    -- A combined health text cannot sit Left or Right while a name is centered
    -- on the health bar (the texts would overlap).
    local function COMBO_VS_CENTER_NAME(keyName)
        if mod.IsComboHealthText(keyName) and mod.IsNameElement(DbValue("textSlotCenter")) then
            return "Disabled when the Name/Level text is centered on the health bar due to overlapping text"
        end
    end
    -- A text's position menu: its own position selected (picking it does
    -- nothing), a taken one greyed, Left / Right greyed by the rule above;
    -- every item greyed on a cell gone stale.
    local function MoveDisabled(S)
        return function(val)
            if not IsAssigned(S) then return true end
            if val == S then return nil end
            if IsAssigned(val) then return true end
            if val == "textSlotLeft" or val == "textSlotRight" then return COMBO_VS_CENTER_NAME(DbValue(S)) end
        end
    end

    local function TextCellCfg(cfg)
        local function readValue() return DbValue(cfg.key) end
        -- Custom opens its popup; a saved template selects it (the new cell reports
        -- the write to Spec Overrides, as Add Text Slot does).
        local values = mod.NPO_CustomTextValues(textElementValues, readValue, function()
            mod.NPO_EditCustomText(cfg.key, function()
                optionState._npNotifySlot = cfg.key
                TextSlotSetValue(cfg.key, "custom")
                optionState._npNotifySlot = nil
            end)
        end)
        return {
            type = "dropdown",
            text = cfg.label,
            values = values,
            order = textElementOrder,
            getValue = readValue,
            setValue = function(val) TextSlotSetValue(cfg.key, val) end,
            disabledValues = (cfg.key == "textSlotLeft" or cfg.key == "textSlotRight")
                    and COMBO_VS_CENTER_NAME
                or nil,
        }
    end
    local addOpen -- the Add Text Slot menu's toggle, once its row is built
    local addCfg = {
        type = "button",
        text = "+ Add Text Slot",
        width = 220,
        onClick = function()
            if addOpen then addOpen() end
        end,
        disabled = function() return AddBlocked() ~= nil end,
        disabledTooltip = function() return AddBlocked() end,
        rawTooltip = true,
    }

    local cells = {}
    for idx = 1, #mod.NPO_TEXT_SLOTS do
        local cfg = mod.NPO_TEXT_SLOTS[idx]
        if IsAssigned(cfg.key) then cells[#cells + 1] = cfg end
    end
    cells[#cells + 1] = addCfg
    local function CellCfg(c)
        if c == nil then return CludesUI.BlankRowCfg() end
        if c == addCfg then return addCfg end
        return TextCellCfg(c)
    end
    -- After its row: a text cell is recorded for the preview's click
    -- navigation (search pre-build too). Row chrome, never on the pre-build's
    -- rows: Add Text Slot's position menu, and a text's name menu, cog and
    -- Spec Overrides report.
    local textSlotCells, textFirstRow = {}, nil
    local function FinishCell(row, side, cfg)
        if cfg == nil then return end
        textFirstRow = textFirstRow or row
        local region = row[side]
        if cfg == addCfg then
            if not CludesUI._prebuilding then
                addOpen = CludesUI.AttachButtonMenu(region._control, {
                    width = 220,
                    order = POS_ORDER,
                    values = POS_VALUES,
                    setValue = AddText,
                    itemDisabled = function(val)
                        if IsAssigned(val) or not AddCandidate() then return true end
                    end,
                })
            end
            return
        end
        textSlotCells[cfg.key] = { row = row, side = side }
        if CludesUI._prebuilding then return end
        CludesUI.BuildRowLabelMenu(region, {
            order = POS_ORDER,
            values = POS_VALUES,
            getValue = function() return cfg.key end,
            setValue = function(val) MoveText(cfg.key, val) end,
            itemDisabled = MoveDisabled(cfg.key),
            tooltip = "Choose this text's slot position.",
        })
        MakeTextCogIcon(row, side, cfg.key, cfg.label)
        -- The popup writes the template directly: Spec Overrides reads it through
        -- an accessor, on a Custom text or one holding a template an override may
        -- switch back to.
        local fk = cfg.key .. "CustomFormat"
        if DbValue(cfg.key) == "custom" or type(DbValue(fk)) == "string" then
            CludesUI.TextTags.AddFormatAccessor(
                region,
                cfg.label,
                function() return DbValue(fk) end,
                function(val)
                    DB()[fk] = val
                    mod.RefreshAllSettings()
                    RepaintPreview()
                end
            )
        end
        if optionState._npNotifySlot == cfg.key then
            optionState._npNotifySlot = nil
            -- The slot read now, while this build's cell is its dress.
            local snap = CludesUI._SOAttribution(region)
            CludesUI._NotifySettingWrite(region, snap)
        end
    end
    for keyName = 1, #cells, 2 do
        local row
        row, height = W:DualRow(hostFrame, cursorY, CellCfg(cells[keyName]), CellCfg(cells[keyName + 1]))
        cursorY = cursorY - height
        FinishCell(row, "_leftRegion", cells[keyName])
        FinishCell(row, "_rightRegion", cells[keyName + 1])
    end

    _, height = W:Spacer(hostFrame, cursorY, 20)
    cursorY = cursorY - height

    cursorY = mod.NPO_BuildCoreTextColoring(hostFrame, cursorY, W)
    -- The structure this build shows, for the cached page's restore check.
    if not CludesUI._prebuilding then optionState._npTextFP = mod.NPO_TextStructureFP() end

    return cursorY,
        styleHeader,
        coreHeader,
        coreRow1,
        coreRow2,
        coreRow3,
        coreTextHeader,
        textSlotCells,
        textFirstRow,
        ShowCogPopup,
        CogPopupOpen,
        RedrawTextures
end

-- Used by CUI_Nameplates_Options.lua
mod.NPO_BuildDisplayLayout = BuildDisplayLayout
