if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_Minimap_Options.lua
--  Registers the Minimap module with CludesUI.
--  All get/set calls go through the global bridge to the addon's DB profile.
-------------------------------------------------------------------------------
local ADDON_NAME = "CludesUIMinimap"
local mod = CludesUI._ModuleNS[ADDON_NAME] -- module namespace (published by the module at its load)
if not mod then
    return
end -- module disabled: no options page

local PAGE_CHAT = "Chat"
local PAGE_MINIMAP = "Minimap"
local PAGE_FRIENDS = "Friends"
local PAGE_QUEST_TRACKER = "Quest Tracker"
local PAGE_CURSOR = "Cursor"
local PAGE_DMG_METERS = "Damage Meters"

local SECTION_CHAT = "CHAT"
local SECTION_MINIMAP = "DISPLAY"

-- Page reuse: the frames this file builds go through the options frame pool
-- (CludesUI_FramePool.lua, the options addon's first file), which hands a
-- kept page its previous build's frames back reset to new; on any other
-- parent it is the plain CreateFrame.
local CreateFrame = CludesUI._Pool.CreateFrame
local PoolIsIdle = CludesUI._Pool.IsIdle

CludesUI.AtOptionsLogin(function()
    ---------------------------------------------------------------------------
    --  DB helpers
    ---------------------------------------------------------------------------
    local saved

    C_Timer.After(0, function()
        saved = _G._CUMM_DB
    end)

    local function DB()
        if not saved then
            saved = _G._CUMM_DB
        end
        return saved and saved.profile
    end

    local function ChatDB()
        local p = DB()
        return p and p.chat
    end

    local function MinimapDB()
        local p = DB()
        return p and p.minimap
    end

    -- Square and Rectangular share the rect layout/border engine (not the circle wrap).
    -- The WoW Forever look's Forever Square is the square map whatever Shape is stored.
    local function ShapeUsesRectLayout()
        if mod.MinimapFvSquare() then
            return true
        end
        local mapDB = MinimapDB()
        local s = mapDB and mapDB.shape or "square"
        return s == "square" or s == "rectangular"
    end

    local function FriendsDB()
        local p = DB()
        return p and p.friends
    end

    ---------------------------------------------------------------------------
    --  Refresh helpers
    ---------------------------------------------------------------------------
    local function RefreshChat()
        if _G._CUBS_ApplyChat then
            _G._CUBS_ApplyChat()
        end
    end

    local function RefreshMinimap()
        if _G._CUMM_ApplyMinimap then
            _G._CUMM_ApplyMinimap()
        end
    end

    -- A minimap setting read with its default, and written: false (nothing
    -- written) while the minimap's settings do not exist yet, else written
    -- and the minimap redrawn.
    local function MapGet(key, default)
        local mapDB = MinimapDB()
        return mapDB and mapDB[key] or default
    end
    -- A row getter over MapGet: the key's value, or the default given.
    local function MapGetRow(key, default)
        return function()
            return MapGet(key, default)
        end
    end
    local function MapSet(key, value)
        local mapDB = MinimapDB()
        if not mapDB then
            return false
        end
        mapDB[key] = value
        RefreshMinimap()
        return true
    end
    -- Row setters over MapSet: the key written with the row's value.
    local function MapSetRow(key)
        return function(value)
            MapSet(key, value)
        end
    end

    -- A cog slider over one minimap setting (min to max in steps of step).
    local function MapSlider(label, key, default, minV, maxV, step)
        return {
            type = "slider",
            label = label,
            min = minV,
            max = maxV,
            step = step,
            get = function()
                return MapGet(key, default)
            end,
            set = function(value)
                MapSet(key, value)
            end,
        }
    end

    local function FullRebuildMinimap()
        if _G._CUMM_FullRebuildMinimap then
            _G._CUMM_FullRebuildMinimap()
        else
            RefreshMinimap()
        end
    end

    local function RefreshFriends()
        if _G._CUBS_ApplyFriends then
            _G._CUBS_ApplyFriends()
        end
    end

    local function RefreshAll()
        if _G._CUBS_ApplyAll then
            _G._CUBS_ApplyAll()
        end
    end

    ---------------------------------------------------------------------------
    --  Visibility row builder (reused across all pages)
    ---------------------------------------------------------------------------
    local Pix = CludesUI.PP
    -- One control for both halves (see CludesUI.BuildVisibilityRow): the mode axes
    -- and the option axes are Show/Hide lanes of the same list now. Storage is
    -- unchanged, so nothing else in this module had to move. The right DualRow slot
    -- the old Visibility Options dropdown occupied is free.
    local function BuildVisibilityRow(W, hostFrame, cursorY, getCfg, refreshFn, rightCfg)
        local visRow, visH = CludesUI.BuildVisibilityRow(W, hostFrame, cursorY, {
            getStore = getCfg,
            legacyKey = "visibility",
            caps = { partyIncludesRaid = false, luaDragonriding = true },
            onChanged = function()
                if refreshFn then
                    refreshFn()
                end
                if _G._CUBS_UpdateVisibility then
                    _G._CUBS_UpdateVisibility()
                end
            end,
            -- Option axes only need the dispatcher pass; the page rebuild is
            -- deferred to menu close by the row itself.
            onOptionChanged = function()
                if _G._CUBS_UpdateVisibility then
                    _G._CUBS_UpdateVisibility()
                end
            end,
        }, rightCfg)
        return visH, visRow
    end

    ---------------------------------------------------------------------------
    --  Chat Page
    ---------------------------------------------------------------------------

    ---------------------------------------------------------------------------
    --  Minimap Page
    ---------------------------------------------------------------------------
    -- The Size slider's drag cover: our own texture on the map, built on the
    -- first drag and kept here (never as a key on Blizzard's frame).
    local sizeDragOverlay

    local function BuildMinimapPage(page, hostFrame, yOffset)
        local W = CludesUI.Widgets
        local cursorY = yOffset
        local _, height

        hostFrame._showRowDivider = true
        CludesUI:ClearContentHeader()

        local heading
        heading, height = W:SectionHeader(hostFrame, SECTION_MINIMAP, cursorY)
        cursorY = cursorY - height
        CludesUI.BuildSectionUnlockJump(heading, { key = "EBS_Minimap" })
        cursorY = CludesUI.BlizzStyle.Note(hostFrame, cursorY, "minimap")

        -- A square frame on the Forever client (the WoW Forever look's Forever
        -- Square, or Blizzard Style's Square in the slim line): the map renders
        -- the CludesUI look's layout in that frame, so the rows that lay that
        -- look out stay live (Gate, BlockInline); the shape and border rows wait
        -- for the CludesUI look under every stock look (BlizzStyle.Gate).
        -- Latched for the session, like the look.
        local fvSquare = mod.MinimapFvSquare()
        local function Gate(rowConf)
            if fvSquare then
                return rowConf
            end
            return CludesUI.BlizzStyle.Gate("minimap", rowConf)
        end
        local function BlockInline(widget)
            if not fvSquare then
                CludesUI.BlizzStyle.BlockInline("minimap", widget)
            end
        end

        -- Row 1: Visibility | Shape. On the WoW Forever look its Border Style
        -- takes the slot, as the shape is part of it: Forever Circle ("circle"),
        -- the variant's round map in Blizzard's Forever ring, Forever Square
        -- (the default there),
        -- the CludesUI look's square map in the bronze frame of Forever's
        -- own windows, or Slim Square ("slim"), that map in the slim bronze
        -- line. Blizzard Style on the Forever client has its own (below).
        -- Each choice renders its own layout and latches with the look, so a change
        -- asks for a reload. A changed pick also moves the clock to that border's
        -- spot (BorderClock), the one the Style page's seed gives a first visit.
        -- Square: inside the map at its bottom, no offset (the title bar holds
        -- the zone name). Circle: at its top, 10px down.
        local function BorderClock(m, square)
            if square then
                m.clockPosition, m.clockOffsetY = "bottom", 0
            else
                m.clockPosition, m.clockOffsetY = "top", -10
            end
        end
        local shapeCfg
        if CludesUI.BlizzStyle.Forever("minimap") then
            shapeCfg = {
                type = "dropdown",
                text = "Border Style",
                tooltip = "Forever Circle: the round map in WoW Forever's ring. Forever Square: the CludesUI square map in the bronze frame of WoW Forever's windows, with the zone name in its title bar. Slim Square: the same square map in a thin bronze frame. Applies after a UI reload.",
                values = { circle = "Forever Circle", square = "Forever Square", slim = "Slim Square" },
                order = { "circle", "square", "slim" },
                disabled = function()
                    return not CludesUI.ForeverHeavyOK()
                end,
                disabledTooltip = "This client is missing WoW Forever's window frame art.",
                rawTooltip = true,
                getValue = function()
                    local mapDB = MinimapDB()
                    local fb = mapDB and mapDB.foreverBorder
                    return (fb == "circle" or fb == "slim") and fb or "square"
                end,
                setValue = function(value)
                    local mapDB = MinimapDB()
                    if not mapDB then
                        return
                    end
                    -- Forever Square is the default: the round map saves "circle",
                    -- the slim square "slim".
                    local square = value ~= "circle"
                    if square ~= (mapDB.foreverBorder ~= "circle") then
                        BorderClock(mapDB, square)
                    end
                    mapDB.foreverBorder = value
                    -- A reload only when the frame that renders changes (square
                    -- or not, heavy or slim): the module latches it.
                    if not mod.MinimapFvBorderChanged(mapDB) then
                        return
                    end
                    CludesUI:ShowConfirmPopup({
                        title = "Reload Required",
                        message = "Border Style changed. A UI reload is needed to apply it.",
                        confirmText = "Reload Now",
                        cancelText = "Later",
                        reload = true,
                    })
                end,
            }
        elseif CludesUI.IS_FOREVER and CludesUI.BlizzStyle.Active("minimap") == "blizzard" then
            -- Blizzard Style on the Forever client: a Border Style of its own,
            -- Circle (the WoW Forever look's Forever Circle exactly) or Square
            -- (the default there: the same square layout in the slim bronze
            -- line). Latched with the look, as above.
            shapeCfg = {
                type = "segmented",
                text = "Border Style",
                tooltip = "Circle: the round map in WoW Forever's ring. Square: the CludesUI square map in a thin bronze frame, with the zone name in its title bar. Applies after a UI reload.",
                values = { circle = "Circle", square = "Square" },
                order = { "circle", "square" },
                getValue = function()
                    local mapDB = MinimapDB()
                    return (mapDB and mapDB.blizzBorder == "circle") and "circle" or "square"
                end,
                setValue = function(value)
                    local mapDB = MinimapDB()
                    if not mapDB then
                        return
                    end
                    -- Square is the default: the round map saves "circle".
                    local square = value == "square"
                    if square ~= (mapDB.blizzBorder ~= "circle") then
                        BorderClock(mapDB, square)
                    end
                    mapDB.blizzBorder = square and "square" or "circle"
                    if square == mod.MinimapFvSquare() then
                        return
                    end
                    CludesUI:ShowConfirmPopup({
                        title = "Reload Required",
                        message = "Border Style changed. A UI reload is needed to apply it.",
                        confirmText = "Reload Now",
                        cancelText = "Later",
                        reload = true,
                    })
                end,
            }
        else
            shapeCfg = CludesUI.BlizzStyle.Gate("minimap", {
                type = "dropdown",
                text = "Shape",
                values = {
                    square = "Square",
                    rectangular = "Rectangular",
                    circle = "Circle",
                    textured_circle = "Textured Circle",
                },
                order = { "square", "rectangular", "circle", "textured_circle" },
                getValue = MapGetRow("shape", "square"),
                setValue = function(value)
                    if not MapSet("shape", value) then
                        return
                    end
                    -- Rebuild: the Width | Height Offset row exists only on the rect layout.
                    CludesUI:RefreshPage(true)
                end,
            })
        end
        local visRow
        height, visRow = BuildVisibilityRow(W, hostFrame, cursorY, MinimapDB, RefreshMinimap, shapeCfg)
        cursorY = cursorY - height
        -- Inline cog on Visibility: Opacity of the shown map (showing and hiding stay
        -- with Visibility). Greyed while the map never shows; the checklist refreshes
        -- the page on close, which re-runs the cog's disabled state.
        if not CludesUI._prebuilding then
            CludesUI.BuildInlineCog(visRow._leftRegion, {
                title = "Minimap Opacity",
                disabled = function()
                    local mapDB = MinimapDB()
                    return mapDB ~= nil and (CludesUI.VisOverrideValue(mapDB) or mapDB.visibility) == "never"
                end,
                disabledTooltip = "This option requires a Visibility other than Never",
                rows = {
                    {
                        type = "slider",
                        label = "Opacity",
                        min = 10,
                        max = 100,
                        step = 1,
                        tooltip = "Fades the minimap while it is shown. Visibility still decides when it shows.",
                        get = function()
                            local mapDB = MinimapDB()
                            return (mapDB and mapDB.opacity) or 100
                        end,
                        set = function(value)
                            local mapDB = MinimapDB()
                            if not mapDB then
                                return
                            end
                            mapDB.opacity = value
                            -- One SetAlpha, not a full apply pass.
                            if _G._CUMM_ApplyMapAlpha then
                                _G._CUMM_ApplyMapAlpha()
                            end
                        end,
                    },
                },
            })
        end

        -- Row 2: Size (+ Icon Size cog) | Interactable Button Size
        local sizeRow
        sizeRow, height = W:DualRow(hostFrame, cursorY, {
            type = "slider",
            text = "Size",
            min = 100,
            max = 600,
            step = 1,
            getValue = MapGetRow("mapSize", 140),
            setValue = function(value)
                local mapDB = MinimapDB()
                if not mapDB then
                    return
                end
                mapDB.mapSize = value
                -- Cover the map render during drag to mask the zoom-nudge blink.
                -- Borders, buttons, etc. remain visible above the overlay.
                local minimap = _G.Minimap
                if minimap then
                    if not sizeDragOverlay then
                        sizeDragOverlay = minimap:CreateTexture(nil, "BACKGROUND", nil, 7)
                        sizeDragOverlay:SetAllPoints(minimap)
                    end
                    local shape = mod.MinimapShape()
                    if shape == "circle" or shape == "textured_circle" then
                        sizeDragOverlay:SetTexture("Interface\\Common\\CommonMaskCircle")
                        sizeDragOverlay:SetVertexColor(0, 0, 0, 1)
                    elseif shape == "rectangular" then
                        sizeDragOverlay:SetTexture(
                            "Interface\\AddOns\\CludesUIMinimap\\Media\\minimap_rectangular-mask.blp"
                        )
                        sizeDragOverlay:SetVertexColor(0, 0, 0, 1)
                    else
                        sizeDragOverlay:SetColorTexture(0, 0, 0, 1)
                    end
                    sizeDragOverlay:Show()
                end
                RefreshMinimap()
                if not _G._CUBS_SizeDragTimer then
                    _G._CUBS_SizeDragTimer = C_Timer.NewTimer(0, function() end)
                end
                _G._CUBS_SizeDragTimer:Cancel()
                _G._CUBS_SizeDragTimer = C_Timer.NewTimer(0.15, function()
                    if sizeDragOverlay then
                        sizeDragOverlay:Hide()
                    end
                end)
            end,
        }, {
            type = "slider",
            text = "Interactable Button Size",
            min = 16,
            max = 40,
            step = 1,
            tooltip = "Size of mail, calendar, tracking, and minimap button group toggle",
            getValue = MapGetRow("interactableBtnSize", 21),
            setValue = MapSetRow("interactableBtnSize"),
        })
        cursorY = cursorY - height
        -- Icon Size in a cog on Size: Blizzard's Edit Mode Icon Size (the scale of
        -- the icons on the map), kept here and applied to the map itself, so the
        -- Edit Mode layout is never written. Unset shows Edit Mode's value.
        if not CludesUI._prebuilding then
            CludesUI.BuildInlineCog(sizeRow._leftRegion, {
                title = "Minimap Icons",
                rows = {
                    {
                        type = "slider",
                        label = "Icon Size",
                        min = 50,
                        max = 200,
                        step = 10,
                        tooltip = "Size of the icons on the map, such as group members, quest objectives and gathering nodes. The same setting as Blizzard's Edit Mode Icon Size.",
                        get = function()
                            local mapDB = MinimapDB()
                            local value = mapDB and mapDB.iconScale
                            if value then
                                return value
                            end
                            return (_G._CUMM_EditModeIconScale and _G._CUMM_EditModeIconScale()) or 100
                        end,
                        set = function(value)
                            local mapDB = MinimapDB()
                            if not mapDB then
                                return
                            end
                            mapDB.iconScale = value
                            if _G._CUMM_ApplyIconScale then
                                _G._CUMM_ApplyIconScale()
                            end
                        end,
                    },
                },
            })
        end

        -- Row 3: Border Style (+ options cog) | Border Size (+ class/custom swatches)
        local texValues, texOrder = CludesUI.GetBorderTextureDropdown()
        local borderRow
        borderRow, height = W:DualRow(
            hostFrame,
            cursorY,
            CludesUI.BlizzStyle.Gate("minimap", {
                type = "dropdown",
                text = "Border Style",
                values = texValues,
                order = texOrder,
                disabled = function()
                    return not ShapeUsesRectLayout()
                end,
                disabledTooltip = "Square or Rectangular Shape",
                getValue = function()
                    local mapDB = MinimapDB()
                    return (mapDB and mapDB.borderTexture) or "solid"
                end,
                setValue = function(value)
                    local mapDB = MinimapDB()
                    if not mapDB then
                        return
                    end
                    mapDB.borderTexture = value
                    mapDB.borderTextureOffset = nil
                    mapDB.borderTextureOffsetY = nil
                    mapDB.borderTextureShiftX = nil
                    mapDB.borderTextureShiftY = nil
                    local _bcol, _bbehind = CludesUI.GetBorderStyleSelectDefaults(value)
                    mapDB.borderColor = _bcol
                    mapDB.borderA = 1
                    mapDB.borderBehind = _bbehind
                    mapDB.borderUseClassColor = false
                    mapDB.useClassColor = false
                    local defSz = CludesUI.GetBorderDefaultSize("minimap", value)
                    if defSz then
                        mapDB.borderSize = defSz
                    end
                    if mapDB.borderSizePx then
                        mapDB.borderSizePx = false
                    end
                    RefreshMinimap()
                    -- Rebuild: the Width | Height Offset row follows the Solid / textured pick.
                    CludesUI:RefreshPage(true)
                end,
            }),
            -- Exact pixels over borderSize + borderSizePx (CludesUI.BorderPx). Only the
            -- square and rectangular border reads the texture and the exact size; the
            -- circle disc grows by the legacy step alone, so there the slider is a plain
            -- 0-4 view of that step and never stores an exact size it cannot draw.
            CludesUI.BlizzStyle.Gate(
                "minimap",
                CludesUI.BorderPxSliderCfg({
                    text = "Border Size",
                    trackWidth = 120,
                    getStep = function()
                        local mapDB = MinimapDB()
                        return (mapDB and mapDB.borderSize) or 1
                    end,
                    setStep = function(value)
                        local mapDB = MinimapDB()
                        if mapDB then
                            mapDB.borderSize = value
                        end
                    end,
                    getTex = function()
                        if not ShapeUsesRectLayout() then
                            return "solid"
                        end
                        local mapDB = MinimapDB()
                        return (mapDB and mapDB.borderTexture) or "solid"
                    end,
                    getPx = function()
                        if not ShapeUsesRectLayout() then
                            return nil
                        end
                        local mapDB = MinimapDB()
                        return mapDB and mapDB.borderSizePx
                    end,
                    setPx = function(value)
                        if not ShapeUsesRectLayout() then
                            return
                        end
                        local mapDB = MinimapDB()
                        if mapDB then
                            mapDB.borderSizePx = value
                        end
                    end,
                    apply = RefreshMinimap,
                })
            )
        )
        cursorY = cursorY - height

        -- Row 3b: Width Offset | Height Offset. The textured border's outward offsets
        -- as their own row, present only while the rect layout draws a textured style
        -- (the circle ignores textures); the shape and style setters rebuild the page.
        -- Each slider shows what is drawn (override, else the "minimap" registry
        -- default for the step) and stores nothing while the value follows the default.
        do
            local mapDB = MinimapDB()
            local texture = (mapDB and mapDB.borderTexture) or "solid"
            if ShapeUsesRectLayout() and texture ~= "" and texture ~= "solid" then
                local ocfgL, ocfgR = CludesUI.BorderOffsetRowCfgs({
                    addonKey = "minimap",
                    getTex = function()
                        local mapDB = MinimapDB()
                        return (mapDB and mapDB.borderTexture) or "solid"
                    end,
                    getStep = function()
                        local mapDB = MinimapDB()
                        return (mapDB and mapDB.borderSize) or 1
                    end,
                    getSizeKey = function()
                        local mapDB = MinimapDB()
                        return (mapDB and mapDB.borderSize) or 1
                    end,
                    getPx = function()
                        local mapDB = MinimapDB()
                        return mapDB and mapDB.borderSizePx
                    end,
                    getX = function()
                        local mapDB = MinimapDB()
                        return mapDB and mapDB.borderTextureOffset
                    end,
                    setX = function(value)
                        local mapDB = MinimapDB()
                        if mapDB then
                            mapDB.borderTextureOffset = value
                        end
                    end,
                    getY = function()
                        local mapDB = MinimapDB()
                        return mapDB and mapDB.borderTextureOffsetY
                    end,
                    setY = function(value)
                        local mapDB = MinimapDB()
                        if mapDB then
                            mapDB.borderTextureOffsetY = value
                        end
                    end,
                    apply = RefreshMinimap,
                })
                _, height = W:DualRow(
                    hostFrame,
                    cursorY,
                    CludesUI.BlizzStyle.Gate("minimap", ocfgL),
                    CludesUI.BlizzStyle.Gate("minimap", ocfgR)
                )
                cursorY = cursorY - height
            end
        end

        -- Inline cog for border options (left region); only shown for textured styles
        if not CludesUI._prebuilding then
            local region = borderRow._leftRegion
            local function BorderTex()
                local mapDB = MinimapDB()
                return (mapDB and mapDB.borderTexture) or "solid"
            end
            local function BorderSz()
                local mapDB = MinimapDB()
                return (mapDB and mapDB.borderSize) or 1
            end
            local cogBtn = CludesUI.BuildInlineCog(region, {
                title = "Border Options",
                rows = {
                    {
                        type = "slider",
                        label = "Shift X",
                        min = -10,
                        max = 10,
                        step = 1,
                        get = function()
                            local mapDB = MinimapDB()
                            local value = mapDB and mapDB.borderTextureShiftX
                            if value then
                                return value
                            end
                            local _, _, dsx = CludesUI.GetBorderDefaults("minimap", BorderTex(), BorderSz())
                            return dsx
                        end,
                        set = function(value)
                            local mapDB = MinimapDB()
                            if not mapDB then
                                return
                            end
                            mapDB.borderTextureShiftX = (value ~= 0) and value or nil
                            RefreshMinimap()
                        end,
                    },
                    {
                        type = "slider",
                        label = "Shift Y",
                        min = -10,
                        max = 10,
                        step = 1,
                        get = function()
                            local mapDB = MinimapDB()
                            local value = mapDB and mapDB.borderTextureShiftY
                            if value then
                                return value
                            end
                            local _, _, _, dsy =
                                CludesUI.GetBorderDefaults("minimap", BorderTex(), BorderSz())
                            return dsy
                        end,
                        set = function(value)
                            local mapDB = MinimapDB()
                            if not mapDB then
                                return
                            end
                            mapDB.borderTextureShiftY = (value ~= 0) and value or nil
                            RefreshMinimap()
                        end,
                    },
                    {
                        type = "toggle",
                        label = "Show Behind",
                        get = function()
                            local mapDB = MinimapDB()
                            return (mapDB and mapDB.borderBehind) or false
                        end,
                        set = function(value)
                            if not MapSet("borderBehind", value) then
                                return
                            end
                            CludesUI:RefreshPage()
                        end,
                    },
                },
            })
            local function UpdateCogVis()
                local rect = ShapeUsesRectLayout() and not CludesUI.BlizzStyle.Get("minimap")
                if rect and BorderTex() ~= "solid" then
                    cogBtn:Show()
                else
                    cogBtn:Hide()
                end
            end
            CludesUI.RegisterWidgetRefresh(UpdateCogVis)
            UpdateCogVis()
        end
        -- Inline accent + class + custom colour swatches on the Border Size
        -- slider. Modes are mutually exclusive: class > accent > custom.
        if not CludesUI._prebuilding then
            local region = borderRow._rightRegion
            local PPl = CludesUI.PP

            -- Accent swatch (nearest the control): live theme accent.
            local accentSwatch, updateAccent = CludesUI.BuildColorSwatch(
                region,
                borderRow:GetFrameLevel() + 3,
                function()
                    local ar, ag, ab = CludesUI.GetAccentColor()
                    return ar, ag, ab, 1
                end,
                function() end,
                false,
                18
            )
            accentSwatch:SetScript("OnClick", function()
                local mapDB = MinimapDB()
                if not mapDB then
                    return
                end
                mapDB.useClassColor = true
                mapDB.borderUseClassColor = false
                RefreshMinimap()
                CludesUI:RefreshPage()
            end)
            PPl.Point(accentSwatch, "RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
            region._lastInline = accentSwatch

            -- Class-colour swatch (to the left of accent): live player class colour.
            local classSwatch, updateClass = CludesUI.BuildColorSwatch(
                region,
                borderRow:GetFrameLevel() + 3,
                function()
                    local classColor = CludesUI.GetClassColor(select(2, UnitClass("player")))
                    if classColor then
                        return classColor.r, classColor.g, classColor.b, 1
                    end
                    return 1, 1, 1, 1
                end,
                function() end,
                false,
                18
            )
            classSwatch:SetScript("OnClick", function()
                local mapDB = MinimapDB()
                if not mapDB then
                    return
                end
                mapDB.borderUseClassColor = true
                mapDB.useClassColor = false
                RefreshMinimap()
                CludesUI:RefreshPage()
            end)
            PPl.Point(classSwatch, "RIGHT", region._lastInline, "LEFT", -8, 0)
            region._lastInline = classSwatch

            -- Custom-colour swatch (outermost): stored custom colour.
            local customSwatch, updateCustom = CludesUI.BuildColorSwatch(
                region,
                borderRow:GetFrameLevel() + 3,
                function()
                    local mapDB = MinimapDB()
                    local c = mapDB and mapDB.borderColor
                    if c then
                        return c.r, c.g, c.b, mapDB.borderA or 1
                    end
                    -- Legacy: pre-style users' border colour keys
                    if mapDB then
                        return mapDB.borderR or 0, mapDB.borderG or 0, mapDB.borderB or 0, mapDB.borderA or 1
                    end
                    return 0, 0, 0, 1
                end,
                function(red, green, blue, a)
                    local mapDB = MinimapDB()
                    if not mapDB then
                        return
                    end
                    mapDB.borderColor = { r = red, g = green, b = blue }
                    mapDB.borderA = a
                    RefreshMinimap()
                end,
                true,
                18
            )
            -- Preserve BuildColorSwatch's picker click, but while class or accent
            -- mode is on a click just switches back to custom mode instead.
            local openPicker = customSwatch:GetScript("OnClick")
            customSwatch:SetScript("OnClick", function(self)
                local mapDB = MinimapDB()
                if mapDB and (mapDB.borderUseClassColor or mapDB.useClassColor) then
                    mapDB.borderUseClassColor = false
                    mapDB.useClassColor = false
                    RefreshMinimap()
                    CludesUI:RefreshPage()
                    return
                end
                if openPicker then
                    openPicker(self)
                end
            end)
            PPl.Point(customSwatch, "RIGHT", region._lastInline, "LEFT", -8, 0)
            region._lastInline = customSwatch

            accentSwatch:HookScript("OnEnter", function()
                CludesUI.ShowWidgetTooltip(accentSwatch, "Accent Color")
            end)
            accentSwatch:HookScript("OnLeave", function()
                CludesUI.HideWidgetTooltip()
            end)
            classSwatch:HookScript("OnEnter", function()
                CludesUI.ShowWidgetTooltip(classSwatch, "Class Color")
            end)
            classSwatch:HookScript("OnLeave", function()
                CludesUI.HideWidgetTooltip()
            end)
            customSwatch:HookScript("OnEnter", function()
                CludesUI.ShowWidgetTooltip(customSwatch, "Custom Color")
            end)
            customSwatch:HookScript("OnLeave", function()
                CludesUI.HideWidgetTooltip()
            end)

            local function UpdateState()
                if updateAccent then
                    updateAccent()
                end
                if updateClass then
                    updateClass()
                end
                if updateCustom then
                    updateCustom()
                end
                -- Blizzard Style draws the stock ring: every border colour is inert.
                if CludesUI.BlizzStyle.Get("minimap") then
                    accentSwatch:SetAlpha(0.3)
                    classSwatch:SetAlpha(0.3)
                    customSwatch:SetAlpha(0.3)
                    return
                end
                local mapDB = MinimapDB()
                local useClass = mapDB and mapDB.borderUseClassColor
                local useAccent = (not useClass) and mapDB and mapDB.useClassColor
                accentSwatch:SetAlpha(useAccent and 1 or 0.3)
                classSwatch:SetAlpha(useClass and 1 or 0.3)
                customSwatch:SetAlpha((useClass or useAccent) and 0.3 or 1)
            end
            CludesUI.RegisterWidgetRefresh(UpdateState)
            UpdateState()
            CludesUI.BlizzStyle.BlockInline("minimap", accentSwatch)
            CludesUI.BlizzStyle.BlockInline("minimap", classSwatch)
            CludesUI.BlizzStyle.BlockInline("minimap", customSwatch)
        end

        -- Reset Zoom (+ seconds) | Rotate Minimap. Off (default) keeps the
        -- rotateMinimap CVar at 0; on sets it to 1 (enforced in ApplyMinimap).
        local fmRow
        fmRow, height = W:DualRow(hostFrame, cursorY, {
            type = "slider",
            text = "Reset Zoom",
            min = 0,
            max = 15,
            step = 1,
            tooltip = "Automatically zoom back out to maximum distance after this many seconds of no manual zoom change. 0 disables the reset.",
            getValue = MapGetRow("zoomResetSeconds", 0),
            setValue = MapSetRow("zoomResetSeconds"),
        }, {
            type = "toggle",
            text = "Rotate Minimap",
            getValue = MapGetRow("rotateMinimap", false),
            setValue = MapSetRow("rotateMinimap"),
        })
        cursorY = cursorY - height

        -- "(seconds)" suffix next to the Reset Zoom slider (mirrors Damage
        -- Meters' Refresh Rate suffix). Prebuild-guarded like the Nameplates
        -- "(Percent)" suffix: the hidden search-index pass has no use for it.
        if not CludesUI._prebuilding then
            local region = fmRow._leftRegion
            local suffix = region:CreateFontString(nil, "OVERLAY")
            suffix:SetFont(CludesUI.EXPRESSWAY, 11, "")
            suffix:SetTextColor(1, 1, 1, 0.35)
            local rzLabel
            -- An idle pooled region keeps its last build's text: skip it.
            local regions = { region:GetRegions() }
            for idx = 1, #regions do
                local reg = regions[idx]
                if
                    reg
                    and reg.GetText
                    and not PoolIsIdle(reg)
                    and CludesUI.EnKey(reg:GetText()) == "Reset Zoom"
                then
                    rzLabel = reg
                    break
                end
            end
            if rzLabel then
                suffix:SetPoint("LEFT", rzLabel, "RIGHT", 5, 0)
            else
                suffix:SetPoint("LEFT", region, "LEFT", 150, 0)
            end
            suffix:SetText(CludesUI.L("(seconds)"))
        end

        cursorY = cursorY - 10

        -- MINIMAP & QOL BUTTONS section header
        _, height = W:SectionHeader(hostFrame, "MINIMAP & QOL BUTTONS", cursorY)
        cursorY = cursorY - height

        -- Ungroup Minimap Buttons | In-Group Button Size
        -- A lone minimap button always shows ungrouped, so the choice needs two or more.
        local function TooFewButtons()
            local vis, num = _G._CUBS_AddonVisible or {}, 0
            for _, button in ipairs(_G._CUBS_CachedAddonButtons or {}) do
                if vis[button] ~= false and button:GetName() then
                    num = num + 1
                end
            end
            return num < 2
        end
        local ungroupRow
        ungroupRow, height = W:DualRow(hostFrame, cursorY, {
            type = "dropdown",
            text = "Ungroup Minimap Buttons",
            values = { __placeholder = "..." },
            order = { "__placeholder" },
            disabled = TooFewButtons,
            disabledTooltip = "This option requires 2 or more minimap buttons.",
            rawTooltip = true,
            getValue = function()
                return "__placeholder"
            end,
            setValue = function() end,
        }, {
            type = "slider",
            text = "In-Group Button Size",
            min = 14,
            max = 40,
            step = 1,
            tooltip = "Size of addon minimap buttons in the flyout grid",
            getValue = MapGetRow("addonBtnSize", 24),
            setValue = MapSetRow("addonBtnSize"),
        })
        cursorY = cursorY - height

        -- Replace placeholder dropdown with checkbox dropdown
        if not CludesUI._prebuilding then
            local leftRegion = ungroupRow._leftRegion
            if leftRegion._control then
                leftRegion._control:Hide()
            end

            -- Build items from currently collected minimap buttons. Ungrouped
            -- buttons come first in their stored drag order (legacy boolean
            -- entries sort last among them), the rest alphabetically.
            local function GetUngroupItems()
                local itemList = {}
                local btns = _G._CUBS_CachedAddonButtons or {}
                local vis = _G._CUBS_AddonVisible or {}
                local mapDB = MinimapDB()
                local ug = mapDB and mapDB.ungroupedButtons or {}
                for _, button in ipairs(btns) do
                    local name = button:GetName()
                    if name and vis[button] ~= false then
                        local labelText = name:gsub("^LibDBIcon10_", "")
                            :gsub("^Lib_GPI_Minimap_", "")
                            :gsub("MinimapButton$", "")
                            :gsub("_MinimapButton$", "")
                        itemList[#itemList + 1] = { key = name, label = labelText }
                    end
                end
                local function OrderOf(key)
                    local value = ug[key]
                    if type(value) == "number" then
                        return value
                    end
                    if value then
                        return math.huge
                    end
                    return nil
                end
                table.sort(itemList, function(lhs, rhs)
                    local oa, ob = OrderOf(lhs.key), OrderOf(rhs.key)
                    if oa and ob then
                        if oa ~= ob then
                            return oa < ob
                        end
                        return lhs.label < rhs.label
                    end
                    if oa then
                        return true
                    end
                    if ob then
                        return false
                    end
                    return lhs.label < rhs.label
                end)
                return itemList
            end

            local checkDrop, cbDDRefresh = CludesUI.BuildReorderCBDropdown(
                leftRegion,
                210,
                leftRegion:GetFrameLevel() + 2,
                GetUngroupItems(),
                function(keyName)
                    local mapDB = MinimapDB()
                    if not mapDB then
                        return false
                    end
                    return mapDB.ungroupedButtons and mapDB.ungroupedButtons[keyName] and true or false
                end,
                function(keyName, value)
                    local mapDB = MinimapDB()
                    if not mapDB then
                        return
                    end
                    if not mapDB.ungroupedButtons then
                        mapDB.ungroupedButtons = {}
                    end
                    if value then
                        local maxOrder = 0
                        for _, ord in pairs(mapDB.ungroupedButtons) do
                            if type(ord) == "number" and ord > maxOrder then
                                maxOrder = ord
                            end
                        end
                        mapDB.ungroupedButtons[keyName] = maxOrder + 1
                    else
                        mapDB.ungroupedButtons[keyName] = nil
                    end
                    FullRebuildMinimap()
                end,
                {
                    hint = "Drag to Reorder Buttons",
                    setOrder = function(orderedKeys)
                        local mapDB = MinimapDB()
                        if not mapDB or not mapDB.ungroupedButtons then
                            return
                        end
                        -- Renumber only the ungrouped entries; unticked rows
                        -- have no stored order.
                        for idx, keyName in ipairs(orderedKeys) do
                            if mapDB.ungroupedButtons[keyName] then
                                mapDB.ungroupedButtons[keyName] = idx
                            end
                        end
                        FullRebuildMinimap()
                    end,
                }
            )
            local Pix = CludesUI.PP
            CludesUI.PanelPP.Point(checkDrop, "RIGHT", leftRegion, "RIGHT", -20, 0)
            leftRegion._control = checkDrop
            leftRegion._lastInline = nil
            CludesUI.RegisterWidgetRefresh(cbDDRefresh)

            -- The checkbox dropdown has no disabled state of its own: grey it and
            -- block clicks; the row's disabled overlay shows the requirement.
            local function ApplyUngroupDisabled()
                local off = TooFewButtons()
                checkDrop:SetAlpha(off and 0.3 or 1)
                checkDrop:EnableMouse(not off)
            end
            ApplyUngroupDisabled()
            CludesUI.RegisterWidgetRefresh(ApplyUngroupDisabled)
        end

        -- Show Extra Buttons (checkbox dropdown with drag-to-reorder)
        local extraBtnRow
        extraBtnRow, height = W:DualRow(hostFrame, cursorY, {
            type = "dropdown",
            text = "Show Extra Buttons",
            values = { __placeholder = "..." },
            order = { "__placeholder" },
            getValue = function()
                return "__placeholder"
            end,
            setValue = function() end,
        }, {
            type = "toggle",
            text = "Mouseover Extra Buttons",
            tooltip = "When enabled, the extra buttons (Great Vault, M+ Portals, Friends Online, Group Button) and any ungrouped minimap buttons only show while the mouse is over the minimap. The M+ Portals flyout keeps them shown until it closes.",
            getValue = MapGetRow("mouseoverExtraBtns", false),
            setValue = function(value)
                local mapDB = MinimapDB()
                if mapDB then
                    mapDB.mouseoverExtraBtns = value
                    RefreshMinimap()
                end
            end,
        })
        cursorY = cursorY - height

        -- Replace placeholder with checkbox dropdown
        if not CludesUI._prebuilding then
            local leftRegion = extraBtnRow._leftRegion
            if leftRegion._control then
                leftRegion._control:Hide()
            end

            -- Checked = shown (stored inverted in hideExtraBtns, so existing
            -- profiles carry over with no migration). Movable rows follow the saved
            -- extraBtnOrder; the Group Button anchors the row and is checkbox-only.
            local EXTRA_BTN_LABELS = {
                greatVault = "Great Vault",
                friendsOnline = "Friends Online",
                portals = "M+ Portals",
            }
            local EXTRA_BTN_DEFAULT_ORDER = { "greatVault", "friendsOnline", "portals" }
            -- WoW Forever has no Great Vault and no keystone portals: the module
            -- never builds those two buttons there, so the list offers Friends
            -- Online only (a saved order still carrying the keys is skipped below).
            if CludesUI.IS_FOREVER then
                EXTRA_BTN_LABELS.greatVault, EXTRA_BTN_LABELS.portals = nil, nil
                EXTRA_BTN_DEFAULT_ORDER = { "friendsOnline" }
            end
            local function GetExtraBtnItems()
                local mapDB = MinimapDB()
                local sequence = mapDB and mapDB.extraBtnOrder
                local itemList, added = {}, {}
                if type(sequence) == "table" then
                    for _, keyName in ipairs(sequence) do
                        if EXTRA_BTN_LABELS[keyName] and not added[keyName] then
                            added[keyName] = true
                            itemList[#itemList + 1] = { key = keyName, label = EXTRA_BTN_LABELS[keyName] }
                        end
                    end
                end
                for _, keyName in ipairs(EXTRA_BTN_DEFAULT_ORDER) do
                    if not added[keyName] then
                        itemList[#itemList + 1] = { key = keyName, label = EXTRA_BTN_LABELS[keyName] }
                    end
                end
                itemList[#itemList + 1] = { key = "groupButton", label = "Group Button", fixed = true }
                return itemList
            end

            local checkDrop, cbDDRefresh = CludesUI.BuildReorderCBDropdown(
                leftRegion,
                210,
                leftRegion:GetFrameLevel() + 2,
                GetExtraBtnItems(),
                function(keyName)
                    local mapDB = MinimapDB()
                    if not mapDB then
                        return true
                    end
                    local heb = mapDB.hideExtraBtns
                    return not (heb and heb[keyName])
                end,
                function(keyName, value)
                    local mapDB = MinimapDB()
                    if not mapDB then
                        return
                    end
                    if not mapDB.hideExtraBtns then
                        mapDB.hideExtraBtns = {}
                    end
                    mapDB.hideExtraBtns[keyName] = not value
                    RefreshMinimap()
                end,
                {
                    hint = "Drag to Reorder Buttons",
                    setOrder = function(orderedKeys)
                        local mapDB = MinimapDB()
                        if not mapDB then
                            return
                        end
                        local t = {}
                        for idx, keyName in ipairs(orderedKeys) do
                            t[idx] = keyName
                        end
                        mapDB.extraBtnOrder = t
                        RefreshMinimap()
                    end,
                }
            )
            local Pix = CludesUI.PP
            CludesUI.PanelPP.Point(checkDrop, "RIGHT", leftRegion, "RIGHT", -20, 0)
            leftRegion._control = checkDrop
            leftRegion._lastInline = nil
            CludesUI.RegisterWidgetRefresh(cbDDRefresh)
        end

        -- M+ Portals Scale | Open Micro Menu on Middle Click
        -- (no keystone portals on WoW Forever: the middle-click toggle takes the left slot there)
        local portalsScaleCfg = {
            type = "slider",
            text = "M+ Portals Scale",
            min = 0.5,
            max = 2.0,
            step = 0.01,
            tooltip = "Scales the M+ Portals flyout the portals button opens.",
            getValue = MapGetRow("extraFlyoutScale", 1.0),
            setValue = function(value)
                local mapDB = MinimapDB()
                if not mapDB then
                    return
                end
                mapDB.extraFlyoutScale = value
            end,
        }
        local middleClickCfg = {
            type = "toggle",
            text = "Open Micro Menu on Middle Click",
            tooltip = "Middle-click the minimap to open the CludesUI micro menu. When off, middle-click does nothing.",
            getValue = function()
                local mapDB = MinimapDB()
                return mapDB and mapDB.openMicroMenuOnMiddleClick ~= false
            end,
            setValue = function(value)
                local mapDB = MinimapDB()
                if not mapDB then
                    return
                end
                mapDB.openMicroMenuOnMiddleClick = value
            end,
        }
        if CludesUI.IS_FOREVER then
            _, height = W:DualRow(hostFrame, cursorY, middleClickCfg, { type = "label", text = "" })
        else
            _, height = W:DualRow(hostFrame, cursorY, portalsScaleCfg, middleClickCfg)
        end
        cursorY = cursorY - height

        -- Friends Tooltip Cap (+ cog: Show Notes) | Custom Tooltip Size
        local friendsCapRow
        friendsCapRow, height = W:DualRow(hostFrame, cursorY, {
            type = "slider",
            text = "Friends Tooltip Cap",
            min = 0,
            max = 30,
            step = 1,
            tooltip = "Max rows per section in the Friends Online tooltip (0 = the 30-row max). The cog can show each note under its row.",
            getValue = MapGetRow("friendsMaxRows", 0),
            setValue = function(value)
                local mapDB = MinimapDB()
                if not mapDB then
                    return
                end
                mapDB.friendsMaxRows = value
            end,
        }, {
            type = "slider",
            text = "Custom Tooltip Size",
            min = 0.5,
            max = 2.0,
            step = 0.01,
            tooltip = "Scales the custom tooltips shown by the unique minimap buttons (Great Vault, friends, calendar, mail, tracking).",
            getValue = MapGetRow("customTooltipScale", 1.0),
            setValue = function(value)
                local mapDB = MinimapDB()
                if not mapDB then
                    return
                end
                mapDB.customTooltipScale = value
            end,
        })
        cursorY = cursorY - height
        -- Inline cog on Friends Tooltip Cap: Show Notes
        if not CludesUI._prebuilding then
            CludesUI.BuildInlineCog(friendsCapRow._leftRegion, {
                title = "Friends Tooltip",
                rows = {
                    {
                        type = "toggle",
                        label = "Show Notes",
                        tooltip = "Shows each guild or friend note on a second line under its row. The tooltip gets taller.",
                        get = MapGetRow("friendsShowNotes", false),
                        set = function(value)
                            local mapDB = MinimapDB()
                            if not mapDB then
                                return
                            end
                            mapDB.friendsShowNotes = value
                        end,
                    },
                },
            })
        end

        -- Shared row-position choices (QoL button row + Blizzard element row).
        -- The two rows are mutually exclusive per position: a value picked on
        -- one dropdown is disabled on the other.
        local ROW_POS_VALUES = {
            blUp = "Bottom Left, Grow Up",
            blRight = "Bottom Left, Grow Right",
            tlDown = "Top Left, Grow Down",
            tlRight = "Top Left, Grow Right",
            brUp = "Bottom Right, Grow Up",
            brLeft = "Bottom Right, Grow Left",
            trLeft = "Top Right, Grow Left",
            trDown = "Top Right, Grow Down",
        }
        local ROW_POS_ORDER = { "blUp", "blRight", "tlDown", "tlRight", "brUp", "brLeft", "trLeft", "trDown" }
        local function BtnRowPos()
            local mapDB = MinimapDB()
            return (mapDB and mapDB.btnRowPosition) or "blUp"
        end
        local function ElementRowPos()
            local mapDB = MinimapDB()
            return (mapDB and mapDB.elementRowPosition) or "tlDown"
        end

        -- Button Row Position (+ spacing cog) | Free Move Buttons (+ cog: Button Backgrounds; "Reset" link)
        local btnRowRow
        btnRowRow, height = W:DualRow(hostFrame, cursorY, {
            type = "dropdown",
            text = "Button Row Position",
            tooltip = "Which minimap corner the button row builds out from and the direction it grows.",
            values = ROW_POS_VALUES,
            order = ROW_POS_ORDER,
            itemDisabled = function(val)
                return val == ElementRowPos()
            end,
            itemDisabledTooltip = function(val)
                if val == ElementRowPos() then
                    return "Already used by Element Row Position"
                end
            end,
            getValue = BtnRowPos,
            setValue = MapSetRow("btnRowPosition"),
        }, {
            type = "toggle",
            text = "Free Move Buttons",
            tooltip = "When enabled, Shift+Click any minimap button (mail, calendar, tracking, addon buttons) to drag it to a custom position.",
            getValue = function()
                local mapDB = MinimapDB()
                return mapDB and mapDB.freeMoveBtns
            end,
            setValue = function(value)
                local mapDB = MinimapDB()
                if not mapDB then
                    return
                end
                mapDB.freeMoveBtns = value
                if not value then
                    mapDB.btnPositions = {}
                end
                RefreshMinimap()
                CludesUI:RefreshPage()
            end,
        })
        cursorY = cursorY - height
        -- Inline cog on Button Row Position for icon spacing
        if not CludesUI._prebuilding then
            local region = btnRowRow._leftRegion
            CludesUI.BuildInlineCog(region, {
                title = "Button Row Settings",
                rows = {
                    {
                        type = "slider",
                        pixel = true,
                        label = "Icon Spacing",
                        min = -20,
                        max = 40,
                        step = 1,
                        get = MapGetRow("btnRowSpacing", 0),
                        set = MapSetRow("btnRowSpacing"),
                    },
                    MapSlider("Distance from Map", "btnRowDistance", 0, -20, 60, 1),
                    {
                        type = "dropdown",
                        label = "Grow Tooltip/Popup",
                        values = { auto = "Auto", up = "Up", down = "Down", left = "Left", right = "Right" },
                        order = { "auto", "up", "down", "left", "right" },
                        get = function()
                            local mapDB = MinimapDB()
                            return (mapDB and mapDB.flyoutGrowDir) or "auto"
                        end,
                        set = MapSetRow("flyoutGrowDir"),
                    },
                },
            })
        end

        -- Inline cog on Free Move Buttons: Button Backgrounds. Then the "Reset"
        -- link (only visible while free move is on) to the cog's left.
        if not CludesUI._prebuilding then
            local region = btnRowRow._rightRegion
            local cogBtn = CludesUI.BuildInlineCog(region, {
                title = "Button Settings",
                rows = {
                    {
                        type = "toggle",
                        label = "Button Backgrounds",
                        tooltip = "Show black backgrounds behind minimap indicator buttons (tracking, calendar, mail, crafting, addon buttons, flyout toggle).",
                        get = function()
                            local mapDB = MinimapDB()
                            return mapDB and mapDB.btnBackgrounds ~= false
                        end,
                        set = function(value)
                            local mapDB = MinimapDB()
                            if not mapDB then
                                return
                            end
                            mapDB.btnBackgrounds = value
                            FullRebuildMinimap()
                        end,
                    },
                },
            })
            -- The stock looks and Forever Square draw no button boxes (every
            -- button wears the ring dress), so the cog waits under all of them.
            CludesUI.BlizzStyle.BlockInline("minimap", cogBtn)

            local resetFS = region:CreateFontString(nil, "OVERLAY")
            resetFS:SetFont(CludesUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF", 12, "")
            resetFS:SetTextColor(1, 1, 1, 0.8)
            resetFS:SetText(CludesUI.L("Reset"))
            resetFS:SetPoint("RIGHT", cogBtn, "LEFT", -8, 0)
            local hitBtn = CreateFrame("Button", nil, region)
            hitBtn:SetAllPoints(resetFS)
            hitBtn:SetFrameLevel(region:GetFrameLevel() + 5)
            hitBtn:SetScript("OnEnter", function()
                resetFS:SetTextColor(1, 0.3, 0.3, 1)
            end)
            hitBtn:SetScript("OnLeave", function()
                resetFS:SetTextColor(1, 1, 1, 0.8)
            end)
            hitBtn:SetScript("OnClick", function()
                local mapDB = MinimapDB()
                if not mapDB then
                    return
                end
                mapDB.btnPositions = {}
                RefreshMinimap()
            end)
            local function UpdateResetVis()
                local mapDB = MinimapDB()
                local enabled = mapDB and mapDB.freeMoveBtns
                resetFS:SetShown(enabled)
                hitBtn:SetShown(enabled)
            end
            UpdateResetVis()
            CludesUI.RegisterWidgetRefresh(UpdateResetVis)
        end

        cursorY = cursorY - 10

        -- BLIZZARD ELEMENTS section header
        _, height = W:SectionHeader(hostFrame, "BLIZZARD ELEMENTS", cursorY)
        cursorY = cursorY - height

        -- Show Omnium Folio (expansion landing page button) | inline X/Y cog
        -- Legacy fallback mirrors the runtime: pre-dropdown data carries the
        -- showOmniumFolio toggle (default ON; only false is ever stored).
        -- No expansion landing page on WoW Forever: the row is not built there.
        if not CludesUI.IS_FOREVER then
            local function OmniumMode()
                local mapDB = MinimapDB()
                if not mapDB then
                    return "always"
                end
                if mapDB.omniumFolioMode then
                    return mapDB.omniumFolioMode
                end
                if mapDB.showOmniumFolio == false then
                    return "never"
                end
                return "always"
            end
            local omniumRow
            omniumRow, height = W:DualRow(hostFrame, cursorY, {
                type = "dropdown",
                text = "Show Omnium Folio",
                tooltip = "Show the expansion landing page (Omnium Folio) button on the minimap. Use the cog to choose its corner and nudge its position.",
                values = { never = "Never", hover = "On Hover", always = "Always" },
                order = { "never", "hover", "always" },
                getValue = OmniumMode,
                setValue = function(value)
                    if not MapSet("omniumFolioMode", value) then
                        return
                    end
                    CludesUI:RefreshPage()
                end,
            }, {
                type = "slider",
                text = "Omnium Folio Scale",
                min = 0.5,
                max = 1.5,
                step = 0.05,
                disabled = function()
                    return OmniumMode() == "never"
                end,
                disabledTooltip = "Show Omnium Folio",
                getValue = function()
                    local mapDB = MinimapDB()
                    return (mapDB and mapDB.omniumFolioScale) or 0.75
                end,
                setValue = MapSetRow("omniumFolioScale"),
            })
            cursorY = cursorY - height
            if not CludesUI._prebuilding then
                local region = omniumRow._leftRegion
                local function omniumOff()
                    return OmniumMode() == "never"
                end
                CludesUI.BuildInlineCog(region, {
                    disabled = omniumOff,
                    disabledTooltip = "Show Omnium Folio",
                    title = "Omnium Folio Position",
                    rows = {
                        {
                            type = "dropdown",
                            label = "Corner",
                            values = {
                                ["BOTTOMLEFT"] = "Bottom Left",
                                ["BOTTOMRIGHT"] = "Bottom Right",
                                ["TOPLEFT"] = "Top Left",
                                ["TOPRIGHT"] = "Top Right",
                            },
                            order = { "BOTTOMLEFT", "BOTTOMRIGHT", "TOPLEFT", "TOPRIGHT" },
                            get = function()
                                local mapDB = MinimapDB()
                                return (mapDB and mapDB.omniumFolioCorner) or "BOTTOMLEFT"
                            end,
                            set = MapSetRow("omniumFolioCorner"),
                        },
                        -- "X Offset" / "Y Offset" (not "X" / "Y"): labels under ~10px wide make
                        -- BuildCogPopup fall back to a 60px label column, which left the old cog
                        -- with a big gap before the sliders. Longer labels avoid that fallback.
                        {
                            type = "slider",
                            label = "X Offset",
                            min = -1000,
                            max = 1000,
                            step = 1,
                            get = function()
                                local mapDB = MinimapDB()
                                return (mapDB and mapDB.omniumFolioX) or 0
                            end,
                            set = MapSetRow("omniumFolioX"),
                        },
                        {
                            type = "slider",
                            label = "Y Offset",
                            min = -1000,
                            max = 1000,
                            step = 1,
                            get = function()
                                local mapDB = MinimapDB()
                                return (mapDB and mapDB.omniumFolioY) or 0
                            end,
                            set = MapSetRow("omniumFolioY"),
                        },
                    },
                })
            end
        end -- not IS_FOREVER

        -- Show Addon Compartment (Blizzard's addon menu button) | inline cog.
        -- Blizzard parents it into MinimapCluster, which this module hides, so
        -- the runtime reparents it onto our minimap and pins it to a corner --
        -- same treatment (and same controls) as the Omnium Folio above.
        local function CompartmentOff()
            local mapDB = MinimapDB()
            return (mapDB and mapDB.hideAddonCompartment) or false
        end
        local compartmentRow
        compartmentRow, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Show Addon Compartment",
            tooltip = "Show Blizzard's addon compartment button on the minimap. Use the cog to choose its corner and nudge its position.",
            getValue = function()
                return not CompartmentOff()
            end,
            setValue = function(value)
                local mapDB = MinimapDB()
                if not mapDB then
                    return
                end
                mapDB.hideAddonCompartment = not value
                RefreshMinimap()
                CludesUI:RefreshPage()
            end,
        }, {
            type = "slider",
            text = "Addon Compartment Scale",
            min = 0.5,
            max = 1.5,
            step = 0.05,
            disabled = CompartmentOff,
            disabledTooltip = "Show Addon Compartment",
            getValue = function()
                local mapDB = MinimapDB()
                return (mapDB and mapDB.addonCompartmentScale) or 0.9
            end,
            setValue = MapSetRow("addonCompartmentScale"),
        })
        cursorY = cursorY - height
        if not CludesUI._prebuilding then
            local region = compartmentRow._leftRegion
            CludesUI.BuildInlineCog(region, {
                disabled = CompartmentOff,
                disabledTooltip = "Show Addon Compartment",
                title = "Addon Compartment Position",
                rows = {
                    {
                        type = "dropdown",
                        label = "Corner",
                        values = {
                            ["BOTTOMLEFT"] = "Bottom Left",
                            ["BOTTOMRIGHT"] = "Bottom Right",
                            ["TOPLEFT"] = "Top Left",
                            ["TOPRIGHT"] = "Top Right",
                        },
                        order = { "BOTTOMLEFT", "BOTTOMRIGHT", "TOPLEFT", "TOPRIGHT" },
                        get = function()
                            local mapDB = MinimapDB()
                            return (mapDB and mapDB.addonCompartmentCorner) or "TOPRIGHT"
                        end,
                        set = MapSetRow("addonCompartmentCorner"),
                    },
                    {
                        type = "slider",
                        label = "X Offset",
                        min = -1000,
                        max = 1000,
                        step = 1,
                        get = function()
                            local mapDB = MinimapDB()
                            return (mapDB and mapDB.addonCompartmentX) or 0
                        end,
                        set = MapSetRow("addonCompartmentX"),
                    },
                    {
                        type = "slider",
                        label = "Y Offset",
                        min = -1000,
                        max = 1000,
                        step = 1,
                        get = function()
                            local mapDB = MinimapDB()
                            return (mapDB and mapDB.addonCompartmentY) or 0
                        end,
                        set = MapSetRow("addonCompartmentY"),
                    },
                },
            })
        end

        -- Show Blizzard Elements | Scroll to Zoom
        local blizzElements = {
            { key = "calendar", label = "Calendar", hideKey = "hideGameTime" },
            { key = "mail", label = "Mail", hideKey = "hideMail" },
            { key = "tracking", label = "Tracking", hideKey = "hideTrackingButton" },
            { key = "crafting", label = "Crafting Order", hideKey = "hideCraftingOrder" },
            {
                key = "difficulty",
                label = "Difficulty",
                hideKey = "hideRaidDifficulty",
                -- Overridden while the difficulty shows as text (Text section)
                lockedFn = function()
                    local mapDB = MinimapDB()
                    return (mapDB and mapDB.diffTextEnabled) or false
                end,
            },
            { key = "zoom", label = "Zoom +/- Icons", hideKey = "hideZoomButtons" },
        }
        local blizzRow
        blizzRow, height = W:DualRow(hostFrame, cursorY, {
            type = "dropdown",
            text = "Show Blizzard Elements",
            values = { ["_placeholder"] = "..." },
            order = { "_placeholder" },
            getValue = function()
                return "_placeholder"
            end,
            setValue = function() end,
        }, {
            type = "toggle",
            text = "Scroll to Zoom",
            getValue = function()
                local mapDB = MinimapDB()
                return mapDB and mapDB.scrollZoom
            end,
            setValue = MapSetRow("scrollZoom"),
        })
        cursorY = cursorY - height
        if not CludesUI._prebuilding then
            local region = blizzRow._leftRegion
            if region._control then
                region._control:Hide()
            end
            local checkDrop, cbDDRefresh = CludesUI.BuildVisOptsCBDropdown(
                region,
                210,
                region:GetFrameLevel() + 2,
                blizzElements,
                function(keyName)
                    local mapDB = MinimapDB()
                    if not mapDB then
                        return false
                    end
                    for _, el in ipairs(blizzElements) do
                        if el.key == keyName then
                            if el.direct then
                                return mapDB[el.hideKey] or false
                            else
                                return not mapDB[el.hideKey]
                            end
                        end
                    end
                    return false
                end,
                function(keyName, value)
                    local mapDB = MinimapDB()
                    if not mapDB then
                        return
                    end
                    for _, el in ipairs(blizzElements) do
                        if el.key == keyName then
                            if el.direct then
                                mapDB[el.hideKey] = value
                            else
                                mapDB[el.hideKey] = not value
                            end
                            break
                        end
                    end
                    RefreshMinimap()
                    CludesUI:RefreshPage()
                end
            )
            CludesUI.PanelPP.Point(checkDrop, "RIGHT", region, "RIGHT", -20, 0)
            region._control = checkDrop
            region._lastInline = nil
            CludesUI.RegisterWidgetRefresh(cbDDRefresh)
        end

        -- Element Row Position (+ spacing cog) | (empty)
        local elRowRow
        elRowRow, height = W:DualRow(
            hostFrame,
            cursorY,
            -- Blizzard Style lays the elements out round the stock top bar.
            Gate({
                type = "dropdown",
                text = "Element Row Position",
                tooltip = "Which minimap corner the Blizzard element row (tracking, calendar, mail, crafting) builds out from and the direction it grows.",
                values = ROW_POS_VALUES,
                order = ROW_POS_ORDER,
                disabled = function()
                    return not ShapeUsesRectLayout()
                end,
                disabledTooltip = "Square or Rectangular Shape",
                itemDisabled = function(val)
                    return val == BtnRowPos()
                end,
                itemDisabledTooltip = function(val)
                    if val == BtnRowPos() then
                        return "Already used by Button Row Position"
                    end
                end,
                getValue = ElementRowPos,
                setValue = MapSetRow("elementRowPosition"),
            }),
            {
                type = "dropdown",
                text = "Mail Position",
                values = {
                    button = "Minimap Button",
                    TOPRIGHT = "Top Right",
                    TOPLEFT = "Top Left",
                    BOTTOMRIGHT = "Bottom Right",
                    BOTTOMLEFT = "Bottom Left",
                },
                order = { "button", "TOPRIGHT", "TOPLEFT", "BOTTOMRIGHT", "BOTTOMLEFT" },
                disabled = function()
                    local mapDB = MinimapDB()
                    return mapDB and mapDB.hideMail
                end,
                disabledTooltip = "Mail in Show Blizzard Elements",
                getValue = MapGetRow("mailPosition", "button"),
                setValue = function(value)
                    if not MapSet("mailPosition", value) then
                        return
                    end
                    CludesUI:RefreshPage()
                end,
            }
        )
        cursorY = cursorY - height
        -- Inline offset cog on Mail Position (corner modes only)
        if not CludesUI._prebuilding then
            local region = elRowRow._rightRegion
            local function mailOff()
                local mapDB = MinimapDB()
                return not mapDB or mapDB.hideMail or (mapDB.mailPosition or "button") == "button"
            end
            CludesUI.BuildInlineCog(region, {
                disabled = mailOff,
                disabledTooltip = function()
                    local mapDB = MinimapDB()
                    return (mapDB and mapDB.hideMail) and "Mail in Show Blizzard Elements" or "a Mail Position corner"
                end,
                title = "Mail Position",
                rows = {
                    MapSlider("X Offset", "mailOffsetX", 0, -100, 100, 1),
                    MapSlider("Y Offset", "mailOffsetY", 0, -500, 500, 1),
                },
            })
        end
        -- Inline cog on Element Row Position for icon spacing
        if not CludesUI._prebuilding then
            local region = elRowRow._leftRegion
            local function elOff()
                return not ShapeUsesRectLayout()
            end
            local cogBtn = CludesUI.BuildInlineCog(region, {
                disabled = elOff,
                disabledTooltip = "Square or Rectangular Shape",
                title = "Element Row Spacing",
                rows = {
                    {
                        type = "slider",
                        pixel = true,
                        label = "Icon Spacing",
                        min = -20,
                        max = 40,
                        step = 1,
                        get = MapGetRow("elementRowSpacing", 0),
                        set = MapSetRow("elementRowSpacing"),
                    },
                    MapSlider("Distance from Map", "elementRowDistance", 0, -20, 60, 1),
                },
            })
            BlockInline(cogBtn)
        end

        cursorY = cursorY - 10

        -- TEXT section header
        _, height = W:SectionHeader(hostFrame, "TEXT", cursorY)
        cursorY = cursorY - height

        -- Shared anchor-position choices (clock, zone text, coordinates)
        local MAP_POS_VALUES = {
            belowMap = "Below Map",
            aboveMap = "Above Map",
            topLeft = "Top Left",
            top = "Top",
            topRight = "Top Right",
            left = "Left",
            right = "Right",
            bottomLeft = "Bottom Left",
            bottom = "Bottom",
            bottomRight = "Bottom Right",
        }
        local MAP_POS_ORDER = {
            "belowMap",
            "aboveMap",
            "topLeft",
            "top",
            "topRight",
            "left",
            "right",
            "bottomLeft",
            "bottom",
            "bottomRight",
        }

        -- Clock Style | Clock Position (with cog: Scale + X/Y offset)
        -- Legacy fallback mirrors the runtime: pre-dropdown data carries the
        -- clockInside toggle (defaulted ON) and the removed Show Blizzard
        -- Elements Clock checkbox (showClock == false meant hidden).
        local function ClockMode()
            local mapDB = MinimapDB()
            if not mapDB then
                return "inside"
            end
            if mapDB.clockMode ~= nil then
                return mapDB.clockMode
            end
            if mapDB.showClock == false then
                return "none"
            end
            return (mapDB.clockInside == false) and "edge" or "inside"
        end
        local clockRow
        clockRow, height = W:DualRow(hostFrame, cursorY, {
            type = "dropdown",
            text = "Clock Style",
            values = { none = "None", inside = "Inside Map", edge = "Edge Box" },
            order = { "none", "inside", "edge" },
            getValue = ClockMode,
            setValue = function(value)
                if not MapSet("clockMode", value) then
                    return
                end
                CludesUI:RefreshPage()
            end,
        }, {
            type = "dropdown",
            text = "Clock Position",
            values = MAP_POS_VALUES,
            order = MAP_POS_ORDER,
            disabled = function()
                return ClockMode() == "none"
            end,
            disabledTooltip = "Clock Style",
            getValue = MapGetRow("clockPosition", "top"),
            setValue = MapSetRow("clockPosition"),
        })
        cursorY = cursorY - height
        -- Inline cog on Clock Position for scale + X/Y offset
        if not CludesUI._prebuilding then
            local region = clockRow._rightRegion
            local function clockOff()
                return ClockMode() == "none"
            end
            CludesUI.BuildInlineCog(region, {
                chain = false,
                disabled = clockOff,
                disabledTooltip = "Clock Style",
                title = "Clock Size and Position",
                rows = {
                    {
                        type = "slider",
                        label = "Scale",
                        min = 0.5,
                        max = 2.0,
                        step = 0.01,
                        get = MapGetRow("clockScale", 1.15),
                        set = function(value)
                            local mapDB = MinimapDB()
                            if not mapDB then
                                return
                            end
                            mapDB.clockScale = value
                            local backdrop = _G._CUBS_ClockBg
                            if backdrop then
                                backdrop:SetScale(value)
                            end
                        end,
                    },
                    MapSlider("X Offset", "clockOffsetX", 0, -500, 500, 1),
                    MapSlider("Y Offset", "clockOffsetY", 0, -500, 500, 1),
                },
            })
        end

        -- Zone Text Style | Zone Position (with cog: Scale + X/Y offset)
        -- Legacy fallback mirrors the runtime: pre-dropdown data carries the
        -- zoneInside toggle (defaulted OFF) and the removed Show Blizzard
        -- Elements Zone checkbox (hideZoneText == true meant hidden). The stock
        -- looks put the zone text in their top bar and Forever Square in its
        -- frame's title bar, so Zone Position waits for the CludesUI look
        -- under all of them (the cog's scale and offsets still apply).
        local function LocationMode()
            local mapDB = MinimapDB()
            if not mapDB then
                return "inside"
            end
            if mapDB.locationMode ~= nil then
                return mapDB.locationMode
            end
            if mapDB.hideZoneText == true then
                return "none"
            end
            return mapDB.zoneInside and "inside" or "edge"
        end
        local zoneRow
        zoneRow, height = W:DualRow(
            hostFrame,
            cursorY,
            {
                type = "dropdown",
                text = "Zone Text Style",
                tooltip = CludesUI.BlizzStyle.Active("minimap") ~= "cui"
                        and "On this look, Inside Map and Edge Box both show the zone name in the map's top bar."
                    or nil,
                values = { none = "None", inside = "Inside Map", edge = "Edge Box" },
                order = { "none", "inside", "edge" },
                getValue = LocationMode,
                setValue = function(value)
                    if not MapSet("locationMode", value) then
                        return
                    end
                    CludesUI:RefreshPage()
                end,
            },
            CludesUI.BlizzStyle.Gate("minimap", {
                type = "dropdown",
                text = "Zone Position",
                values = MAP_POS_VALUES,
                order = MAP_POS_ORDER,
                disabled = function()
                    return LocationMode() == "none"
                end,
                disabledTooltip = "Zone Text Style",
                getValue = MapGetRow("locationPosition", "bottom"),
                setValue = MapSetRow("locationPosition"),
            })
        )
        cursorY = cursorY - height
        -- Inline cog on Zone Text Style: reactive zone coloring
        if not CludesUI._prebuilding then
            local region = zoneRow._leftRegion
            local function styleOff()
                return LocationMode() == "none"
            end
            CludesUI.BuildInlineCog(region, {
                disabled = styleOff,
                disabledTooltip = "Zone Text Style",
                title = "Zone Text Settings",
                rows = {
                    {
                        type = "toggle",
                        label = "Display Sub Zone",
                        get = MapGetRow("zoneShowSubZone", false),
                        set = MapSetRow("zoneShowSubZone"),
                    },
                    {
                        type = "toggle",
                        label = "Reactive Coloring",
                        get = MapGetRow("zoneReactiveColor", false),
                        set = MapSetRow("zoneReactiveColor"),
                    },
                },
            })
        end
        -- Inline cog on Zone Position for scale + X/Y offset
        if not CludesUI._prebuilding then
            local region = zoneRow._rightRegion
            local function locOff()
                return LocationMode() == "none"
            end
            CludesUI.BuildInlineCog(region, {
                chain = false,
                disabled = locOff,
                disabledTooltip = "Zone Text Style",
                title = "Zone Text Size and Position",
                rows = {
                    {
                        type = "slider",
                        label = "Scale",
                        min = 0.5,
                        max = 2.0,
                        step = 0.01,
                        get = MapGetRow("locationScale", 1.15),
                        set = function(value)
                            local mapDB = MinimapDB()
                            if not mapDB then
                                return
                            end
                            mapDB.locationScale = value
                            local backdrop = _G._CUBS_LocationBg
                            if backdrop then
                                backdrop:SetScale(value)
                            end
                        end,
                    },
                    MapSlider("X Offset", "locationOffsetX", 0, -500, 500, 1),
                    MapSlider("Y Offset", "locationOffsetY", 0, -500, 500, 1),
                },
            })
        end

        -- Show Coordinates | Coordinates Position (with cog: X/Y offset)
        -- Legacy fallback mirrors the runtime: pre-dropdown data only carries
        -- coordsBelow (true = always-on below the map).
        local function CoordsMode()
            local mapDB = MinimapDB()
            if not mapDB then
                return "always"
            end
            return mapDB.coordsMode or (mapDB.coordsBelow and "always") or "always"
        end
        local coordsRow
        coordsRow, height = W:DualRow(hostFrame, cursorY, {
            type = "dropdown",
            text = "Show Coordinates",
            values = { never = "Never", hover = "On Hover", always = "Always" },
            order = { "never", "hover", "always" },
            getValue = CoordsMode,
            setValue = function(value)
                if not MapSet("coordsMode", value) then
                    return
                end
                CludesUI:RefreshPage()
            end,
        }, {
            type = "dropdown",
            text = "Coordinates Position",
            values = MAP_POS_VALUES,
            order = MAP_POS_ORDER,
            disabled = function()
                return CoordsMode() == "never"
            end,
            disabledTooltip = "Show Coordinates",
            getValue = function()
                local mapDB = MinimapDB()
                if not mapDB then
                    return "topLeft"
                end
                return mapDB.coordsPosition or (mapDB.coordsBelow and "belowMap") or "topLeft"
            end,
            setValue = MapSetRow("coordsPosition"),
        })
        cursorY = cursorY - height
        -- Inline cog on Show Coordinates for decimal precision
        if not CludesUI._prebuilding then
            local region = coordsRow._leftRegion
            local function coordsOff()
                return CoordsMode() == "never"
            end
            CludesUI.BuildInlineCog(region, {
                disabled = coordsOff,
                disabledTooltip = "Show Coordinates",
                title = "Coordinate Precision",
                rows = {
                    MapSlider("Decimal Places", "coordPrecision", 0, 0, 2, 1),
                },
            })
        end
        -- Inline cog on Coordinates Position for X/Y offset
        if not CludesUI._prebuilding then
            local region = coordsRow._rightRegion
            local function coordsOff()
                return CoordsMode() == "never"
            end
            CludesUI.BuildInlineCog(region, {
                chain = false,
                disabled = coordsOff,
                disabledTooltip = "Show Coordinates",
                title = "Coordinates Size and Position",
                rows = {
                    {
                        type = "slider",
                        label = "Scale",
                        min = 0.5,
                        max = 2.0,
                        step = 0.01,
                        get = MapGetRow("coordsScale", 1.0),
                        set = function(value)
                            local mapDB = MinimapDB()
                            if not mapDB then
                                return
                            end
                            mapDB.coordsScale = value
                            local castFrame = _G._CUBS_CoordFrame
                            if castFrame then
                                castFrame:SetScale(value)
                            end
                        end,
                    },
                    MapSlider("X Offset", "coordsBelowOffsetX", 0, -500, 500, 1),
                    MapSlider("Y Offset", "coordsBelowOffsetY", 0, -500, 500, 1),
                },
            })
        end

        -- Show FPS/MS (+ swatch + cog, mirrors QoL Show FPS Counter) | FPS/MS Position (+ offset cog)
        local function FpsOff()
            local mapDB = MinimapDB()
            return not (mapDB and mapDB.showFPS)
        end
        local fpsRow
        fpsRow, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Show FPS/MS",
            getValue = MapGetRow("showFPS", false),
            setValue = function(value)
                if not MapSet("showFPS", value) then
                    return
                end
                CludesUI:RefreshPage()
            end,
        }, {
            type = "dropdown",
            text = "FPS/MS Position",
            values = MAP_POS_VALUES,
            order = MAP_POS_ORDER,
            disabled = FpsOff,
            disabledTooltip = "Show FPS/MS",
            getValue = MapGetRow("fpsPosition", "bottomLeft"),
            setValue = MapSetRow("fpsPosition"),
        })
        cursorY = cursorY - height
        -- Inline cog on Show FPS/MS (text size + which MS readouts show).
        -- The description-colour swatches live on the Accented Text row at
        -- the bottom of this section.
        if not CludesUI._prebuilding then
            local leftRegion = fpsRow._leftRegion

            CludesUI.BuildInlineCog(leftRegion, {
                gap = 9,
                disabled = FpsOff,
                disabledTooltip = "Show FPS/MS",
                title = "FPS/MS Settings",
                rows = {
                    MapSlider("Text Size", "fpsTextSize", 12, 8, 30, 1),
                    {
                        type = "toggle",
                        label = "Show Local MS",
                        get = function()
                            local mapDB = MinimapDB()
                            local sl = mapDB and mapDB.fpsShowLocalMS
                            if sl == nil then
                                return true
                            end
                            return sl
                        end,
                        set = MapSetRow("fpsShowLocalMS"),
                    },
                    {
                        type = "toggle",
                        label = "Show World MS",
                        get = MapGetRow("fpsShowWorldMS", false),
                        set = MapSetRow("fpsShowWorldMS"),
                    },
                    MapSlider("Update Interval", "fpsUpdateInterval", 3, 1, 5, 1),
                },
            })
        end
        -- Inline offset cog on FPS/MS Position
        if not CludesUI._prebuilding then
            local region = fpsRow._rightRegion
            CludesUI.BuildInlineCog(region, {
                chain = false,
                disabled = FpsOff,
                disabledTooltip = "Show FPS/MS",
                title = "FPS/MS Size and Position",
                rows = {
                    {
                        type = "slider",
                        label = "Scale",
                        min = 0.5,
                        max = 2.0,
                        step = 0.01,
                        get = MapGetRow("fpsScale", 1.0),
                        set = function(value)
                            local mapDB = MinimapDB()
                            if not mapDB then
                                return
                            end
                            mapDB.fpsScale = value
                            local fb = _G._CUBS_FpsBg
                            if fb then
                                fb:SetScale(value)
                            end
                        end,
                    },
                    MapSlider("X Offset", "fpsOffsetX", 0, -500, 500, 1),
                    MapSlider("Y Offset", "fpsOffsetY", 0, -500, 500, 1),
                },
            })
        end

        -- Show on FPS/MS Hover | Show on Clock Hover
        local HOVER_TT_VALUES = { none = "None", lockouts = "Instance Lockouts", vault = "Great Vault" }
        local HOVER_TT_ORDER = { "none", "lockouts", "vault" }
        -- No Great Vault on WoW Forever: the entry is dropped and a saved "vault"
        -- shows as None (the module reads it as none too and never rewrites it).
        if CludesUI.IS_FOREVER then
            HOVER_TT_VALUES.vault = nil
            HOVER_TT_ORDER = { "none", "lockouts" }
        end
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "dropdown",
            text = "Show on FPS/MS Hover",
            values = HOVER_TT_VALUES,
            order = HOVER_TT_ORDER,
            disabled = FpsOff,
            disabledTooltip = "Show FPS/MS",
            getValue = function()
                local mapDB = MinimapDB()
                local value = mapDB and mapDB.fpsHoverTooltip or "none"
                if CludesUI.IS_FOREVER and value == "vault" then
                    value = "none"
                end
                return value
            end,
            setValue = MapSetRow("fpsHoverTooltip"),
        }, {
            type = "dropdown",
            text = "Show on Clock Hover",
            values = HOVER_TT_VALUES,
            order = HOVER_TT_ORDER,
            disabled = function()
                return ClockMode() == "none"
            end,
            disabledTooltip = "Clock Style",
            getValue = function()
                local mapDB = MinimapDB()
                local value = mapDB and mapDB.clockHoverTooltip or "none"
                if CludesUI.IS_FOREVER and value == "vault" then
                    value = "none"
                end
                return value
            end,
            setValue = function(value)
                local mapDB = MinimapDB()
                if not mapDB then
                    return
                end
                mapDB.clockHoverTooltip = value
            end,
        })
        cursorY = cursorY - height

        -- Show Instance Difficulty as Text | Difficulty Position (+ size/offset cog)
        local function DiffTextOn()
            local mapDB = MinimapDB()
            return (mapDB and mapDB.diffTextEnabled) or false
        end
        local diffRow
        diffRow, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Show Instance Difficulty as Text",
            getValue = DiffTextOn,
            setValue = function(value)
                local mapDB = MinimapDB()
                if not mapDB then
                    return
                end
                mapDB.diffTextEnabled = value and true or false
                RefreshMinimap()
                CludesUI:RefreshPage()
            end,
        }, {
            type = "dropdown",
            text = "Difficulty Position",
            values = MAP_POS_VALUES,
            order = MAP_POS_ORDER,
            disabled = function()
                return not DiffTextOn()
            end,
            disabledTooltip = "Show Instance Difficulty as Text",
            getValue = MapGetRow("diffTextPosition", "topLeft"),
            setValue = MapSetRow("diffTextPosition"),
        })
        cursorY = cursorY - height
        -- Inline cog on Difficulty Position for text size + X/Y offset
        if not CludesUI._prebuilding then
            local region = diffRow._rightRegion
            local function diffOff()
                return not DiffTextOn()
            end
            CludesUI.BuildInlineCog(region, {
                chain = false,
                disabled = diffOff,
                disabledTooltip = "Show Instance Difficulty as Text",
                title = "Difficulty Text Size and Position",
                rows = {
                    MapSlider("Text Size", "diffTextSize", 12, 8, 24, 1),
                    MapSlider("X Offset", "diffTextOffsetX", 0, -500, 500, 1),
                    MapSlider("Y Offset", "diffTextOffsetY", 0, -500, 500, 1),
                },
            })
        end

        -- Accented Text | (empty) -- which Text elements colour their
        -- description parts (clock AM/PM, FPS/MS suffixes, difficulty letter) with the
        -- accent/custom colour from the inline swatches. Dynamic values always render
        -- white. Difficulty and Difficulty (Reactive) are mutually exclusive: flat
        -- accent/custom colour vs colour-by-tier. Each locks while the other is
        -- checked, and the setters clear the sibling as a consistency net (the locked
        -- state repaints on the next menu open).
        local accentItems = {
            { key = "clock", label = "Clock" },
            { key = "fpsms", label = "FPS/MS" },
            {
                key = "difficulty",
                label = "Difficulty",
                lockedFn = function()
                    local mapDB = MinimapDB()
                    return (mapDB and mapDB.diffTextReactive) or false
                end,
            },
            {
                key = "difficultyReactive",
                label = "Difficulty (Reactive)",
                lockedFn = function()
                    local mapDB = MinimapDB()
                    return (mapDB and mapDB.diffTextAccent) or false
                end,
            },
        }
        local accentRow
        accentRow, height = W:DualRow(hostFrame, cursorY, {
            type = "dropdown",
            text = "Accented Text",
            values = { ["_placeholder"] = "..." },
            order = { "_placeholder" },
            getValue = function()
                return "_placeholder"
            end,
            setValue = function() end,
        }, { type = "label", text = "" })
        cursorY = cursorY - height
        if not CludesUI._prebuilding then
            local region = accentRow._leftRegion
            if region._control then
                region._control:Hide()
            end
            local checkDrop, cbDDRefresh = CludesUI.BuildVisOptsCBDropdown(
                region,
                210,
                region:GetFrameLevel() + 2,
                accentItems,
                function(keyName)
                    local mapDB = MinimapDB()
                    if not mapDB then
                        return false
                    end
                    if keyName == "clock" then
                        return mapDB.fpsColorClockAMPM or false
                    end
                    if keyName == "fpsms" then
                        local value = mapDB.fpsColorSuffix
                        if value == nil then
                            return true
                        end
                        return value
                    end
                    if keyName == "difficulty" then
                        return mapDB.diffTextAccent or false
                    end
                    if keyName == "difficultyReactive" then
                        return mapDB.diffTextReactive or false
                    end
                    return false
                end,
                function(keyName, value)
                    local mapDB = MinimapDB()
                    if not mapDB then
                        return
                    end
                    if keyName == "clock" then
                        mapDB.fpsColorClockAMPM = value
                    elseif keyName == "fpsms" then
                        mapDB.fpsColorSuffix = value
                    elseif keyName == "difficulty" then
                        mapDB.diffTextAccent = value
                        if value then
                            mapDB.diffTextReactive = false
                        end
                    elseif keyName == "difficultyReactive" then
                        mapDB.diffTextReactive = value
                        if value then
                            mapDB.diffTextAccent = false
                        end
                    end
                    RefreshMinimap()
                end
            )
            CludesUI.PanelPP.Point(checkDrop, "RIGHT", region, "RIGHT", -20, 0)
            region._control = checkDrop
            region._lastInline = nil
            CludesUI.RegisterWidgetRefresh(cbDDRefresh)

            -- Accent swatch (nearest the control): live theme accent.
            local accentSwatch, updateAccent = CludesUI.BuildColorSwatch(
                region,
                region:GetFrameLevel() + 5,
                function()
                    local ar, ag, ab = CludesUI.GetAccentColor()
                    return ar, ag, ab, 1
                end,
                function() end,
                false,
                18
            )
            accentSwatch:SetScript("OnClick", function()
                local mapDB = MinimapDB()
                if not mapDB then
                    return
                end
                mapDB.fpsUseAccent = true
                RefreshMinimap()
                CludesUI:RefreshPage()
            end)
            Pix.Point(accentSwatch, "RIGHT", checkDrop, "LEFT", -12, 0)
            region._lastInline = accentSwatch

            -- Custom swatch (to the left of accent): stored custom colour.
            local customSwatch, updateCustom = CludesUI.BuildColorSwatch(
                region,
                region:GetFrameLevel() + 5,
                function()
                    local mapDB = MinimapDB()
                    local c = mapDB and mapDB.fpsColor
                    if c then
                        return c.r or 1, c.g or 1, c.b or 1, 1
                    end
                    return 1, 1, 1, 1
                end,
                function(red, green, blue)
                    local mapDB = MinimapDB()
                    if not mapDB then
                        return
                    end
                    mapDB.fpsColor = { r = red, g = green, b = blue }
                    RefreshMinimap()
                end,
                false,
                18
            )
            local openPicker = customSwatch:GetScript("OnClick")
            customSwatch:SetScript("OnClick", function(self)
                local mapDB = MinimapDB()
                if mapDB and mapDB.fpsUseAccent then
                    mapDB.fpsUseAccent = false
                    RefreshMinimap()
                    CludesUI:RefreshPage()
                    return
                end
                if openPicker then
                    openPicker(self)
                end
            end)
            Pix.Point(customSwatch, "RIGHT", accentSwatch, "LEFT", -8, 0)
            region._lastInline = customSwatch

            accentSwatch:HookScript("OnEnter", function()
                CludesUI.ShowWidgetTooltip(accentSwatch, "Accent Color")
            end)
            accentSwatch:HookScript("OnLeave", function()
                CludesUI.HideWidgetTooltip()
            end)
            customSwatch:HookScript("OnEnter", function()
                CludesUI.ShowWidgetTooltip(customSwatch, "Custom Color")
            end)
            customSwatch:HookScript("OnLeave", function()
                CludesUI.HideWidgetTooltip()
            end)

            CludesUI.RegisterWidgetRefresh(function()
                if updateAccent then
                    updateAccent()
                end
                if updateCustom then
                    updateCustom()
                end
                local mapDB = MinimapDB()
                local useAccent = mapDB and mapDB.fpsUseAccent
                accentSwatch:SetAlpha(useAccent and 1 or 0.3)
                customSwatch:SetAlpha(useAccent and 0.3 or 1)
            end)
            local mInit = MinimapDB()
            local initAccent = mInit and mInit.fpsUseAccent
            accentSwatch:SetAlpha(initAccent and 1 or 0.3)
            customSwatch:SetAlpha(initAccent and 0.3 or 1)
        end

        return math.abs(cursorY)
    end

    ---------------------------------------------------------------------------
    --  Register the module
    ---------------------------------------------------------------------------
    CludesUI:RegisterModule("CludesUIMinimap", {
        title = "Minimap",
        description = "Custom minimap skin and layout.",
        pages = { "Minimap" },
        buildPage = function(page, hostFrame, yOffset)
            if page == "Minimap" then
                return BuildMinimapPage(page, hostFrame, yOffset)
            end
        end,
        onReset = function()
            if _G._CUMM_DB and _G._CUMM_DB.ResetProfile then
                _G._CUMM_DB:ResetProfile()
            end
            CludesUI:InvalidatePageCache()
            if _G._CUMM_ApplyMinimap then
                _G._CUMM_ApplyMinimap()
            end
        end,
    })

    SLASH_EMM1 = "/cmm"
    SlashCmdList.EMM = function()
        if InCombatLockdown and InCombatLockdown() then
            return
        end
        CludesUI:ShowModule("CludesUIMinimap")
    end
end)
