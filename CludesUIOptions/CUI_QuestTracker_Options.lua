if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
-- CUI_QuestTracker_Options.lua
--
-- Options page for the Blizzard-backed quest tracker. All legacy display,
-- font, and color options from the custom-tracker era have been removed.
-- Surviving options are: enable, visibility mode, auto-hide rules,
-- auto-accept / auto-turn-in, quest item hotkey, and skin toggles.
-------------------------------------------------------------------------------
local mod = CludesUI._ModuleNS["CludesUIQuestTracker"] -- module namespace (published by the module at its load)
if not mod then
    return
end -- module disabled: no options page
local EQT = mod.EQT

-- Page reuse: the frames this file builds go through the options frame pool
-- (CludesUI_FramePool.lua, the options addon's first file), which hands a
-- kept page its previous build's frames back reset to new; on any other
-- parent it is the plain CreateFrame.
local CreateFrame = CludesUI._Pool.CreateFrame

CludesUI.AtOptionsLogin(function()
    if not EQT then
        return
    end

    local function DB()
        local db = _G._CUQT_DB
        if db and db.profile and db.profile.questTracker then
            return db.profile.questTracker
        end
        return {}
    end
    local function TrackerGet(keyName)
        return DB()[keyName]
    end
    -- Row getters over Cfg: a key's value (or a default), or whether it is true.
    local function CfgOr(key, default)
        return function()
            return TrackerGet(key) or default
        end
    end
    local function CfgIs(key)
        return function()
            return TrackerGet(key) == true
        end
    end
    local function Set(keyName, val)
        DB()[keyName] = val
    end

    local function RefreshTracker()
        if EQT.RefreshStateDriver then
            EQT.RefreshStateDriver()
        end
        if EQT.UpdateVisibility then
            EQT.UpdateVisibility()
        end
        if EQT.RestyleAll then
            EQT.RestyleAll()
        end
        if EQT.ApplyBackground then
            EQT.ApplyBackground()
        end
        if EQT.ApplyMasterHeaderVisibility then
            EQT.ApplyMasterHeaderVisibility()
        end
    end
    -- Row setters over Set: the key written with the row's value, then RefreshAll() for the Then form.
    local function SetRow(key)
        return function(value)
            Set(key, value)
        end
    end
    local function SetRowThen(key)
        return function(value)
            Set(key, value)
            RefreshTracker()
        end
    end

    local function BuildPage(_, hostFrame, yOffset)
        local W = CludesUI.Widgets
        local Pix = CludesUI.PP
        local cursorY = yOffset
        local row, height

        if CludesUI.ClearContentHeader then
            CludesUI:ClearContentHeader()
        end
        hostFrame._showRowDivider = true
        -- WoW Forever: our own tracker frame (latched until reload).
        local CUSTOM = mod.UseCustomTracker()

        -- Drag instructions (centered, above settings). Wrapped in a Frame so the
        -- search system collects it as an orphan and auto-hides it during search.
        do
            local fontFile = CludesUI.GetFontPath() or STANDARD_TEXT_FONT
            local infoFrame = CreateFrame("Frame", nil, hostFrame)
            infoFrame:SetSize(hostFrame:GetWidth() or 400, 20)
            infoFrame:SetPoint("TOP", hostFrame, "TOP", 0, cursorY - 20)
            infoFrame._isSpacer = true
            local infoLabel = infoFrame:CreateFontString(nil, "OVERLAY")
            infoLabel:SetFont(fontFile, 15, "")
            infoLabel:SetTextColor(1, 1, 1, 0.75)
            infoLabel:SetPoint("CENTER")
            infoLabel:SetJustifyH("CENTER")
            infoLabel:SetText(
                CUSTOM and CludesUI.L("Reposition this element within Layout Mode")
                    or CludesUI.L("Reposition this element within Blizzard Edit Mode")
            )

            -- Accent toggle beneath the label. "Force Quest Tracker on Screen" keeps
            -- the tracker clamped to the screen; clicking again ("Allow Quest Tracker
            -- to be Moved Offscreen") releases it so it can be dragged off-screen. The
            -- choice is saved in the quest tracker DB (forceOnScreen) and re-applied at
            -- load by EQT.ApplyForceOnScreen(), so it persists through reload/logout.
            -- Edit Mode is opened so the user can reposition the frame after toggling.
            local ACC = CludesUI.CLUDES_GREEN
            local fosBtn = CreateFrame("Button", nil, hostFrame)
            local fosFS = fosBtn:CreateFontString(nil, "OVERLAY")
            fosFS:SetFont(fontFile, 15, "")
            fosFS:SetTextColor(ACC.r, ACC.g, ACC.b, 0.75)
            fosFS:SetPoint("CENTER")
            local function UpdateForceOnScreenLabel()
                local enabled = TrackerGet("forceOnScreen") == true
                fosFS:SetText(
                    CludesUI.L(
                        enabled and "Allow Quest Tracker to be Moved Offscreen"
                            or "Force Quest Tracker on Screen"
                    )
                )
                fosBtn:SetSize(fosFS:GetStringWidth() + 12, 18)
            end
            UpdateForceOnScreenLabel()
            fosBtn:SetPoint("TOP", infoLabel, "BOTTOM", 0, -10)
            fosBtn:SetScript("OnEnter", function()
                fosFS:SetTextColor(ACC.r, ACC.g, ACC.b, 1)
            end)
            fosBtn:SetScript("OnLeave", function()
                fosFS:SetTextColor(ACC.r, ACC.g, ACC.b, 0.75)
            end)
            fosBtn:SetScript("OnClick", function()
                if InCombatLockdown() then
                    return
                end
                Set("forceOnScreen", not (TrackerGet("forceOnScreen") == true))
                if EQT.ApplyForceOnScreen then
                    EQT.ApplyForceOnScreen()
                end
                UpdateForceOnScreenLabel()
                if EditModeManagerFrame and not CUSTOM then
                    ShowUIPanel(EditModeManagerFrame)
                end
            end)
            cursorY = cursorY - 68
        end

        -- Stock styles (Blizzard Style / Classic WoW UI) keep Blizzard's own
        -- tracker art, text and quest icons: the background, font and colour
        -- rows only apply to the CludesUI look.
        local BS = CludesUI.BlizzStyle
        local STOCK = BS and BS.Get("questtracker") and not CUSTOM
        -- WoW Forever's quest tools and objective colors (none of their rows on retail).
        local FOREVER = CludesUI.IS_FOREVER

        -- -- CUSTOM TRACKER (WoW Forever) ------------------------------------
        if CludesUI.IS_FOREVER then
            _, height = W:SectionHeader(hostFrame, "CUSTOM TRACKER", cursorY)
            cursorY = cursorY - height
            local function Off()
                return not CUSTOM
            end

            -- Custom Quest Tracker | Group Quests by Zone. The toggle shows what
            -- the profile asks for (its own pick, else on under the CludesUI
            -- style alone); the tracker in use changes at the reload.
            local zoneRow
            zoneRow, height = W:DualRow(hostFrame, cursorY, {
                type = "toggle",
                text = "Custom Quest Tracker",
                tooltip = "Replaces Blizzard's tracker with CludesUI's own quest tracker, which never touches Blizzard's tracker or watch list. On by default under the CludesUI style. Requires a UI reload.",
                getValue = function()
                    return mod.CustomTrackerWanted(DB())
                end,
                setValue = function(val)
                    mod.SetCustomTrackerWanted(DB(), val)
                    CludesUI:ShowConfirmPopup({
                        title = "Reload Required",
                        message = "Switching quest trackers requires a UI reload to apply.",
                        confirmText = "Reload Now",
                        cancelText = "Later",
                        reload = true,
                    })
                end,
            }, {
                type = "toggle",
                text = "Group Quests by Zone",
                tooltip = "Lists quests under their quest log zone headers. Click a zone to collapse it.",
                disabled = Off,
                disabledTooltip = "Custom Quest Tracker",
                getValue = function()
                    return TrackerGet("customGroupByZone") ~= false
                end,
                setValue = function(val)
                    Set("customGroupByZone", val)
                    RefreshTracker()
                    CludesUI:RefreshPage()
                end,
            })
            cursorY = cursorY - height

            -- Zone header colour, on the Group Quests by Zone slot: Custom
            -- Colored | Accent Colored. With no pick the headers follow the
            -- Header Color, so the lit swatch is the one they show now.
            if not CludesUI._prebuilding then
                local function ZoneAccent()
                    return (select(4, EQT.CustomZoneRGB()))
                end
                local function PickZone(accent)
                    local was = TrackerGet("customZoneUseAccent")
                    Set("customZoneUseAccent", accent)
                    EQT.RefreshCustom()
                    if was ~= accent then
                        CludesUI:RefreshPage()
                    end
                end
                CludesUI.BuildInlineSwatches(zoneRow._rightRegion, {
                    {
                        tooltip = "Custom Colored",
                        hasAlpha = false,
                        getValue = function()
                            if TrackerGet("customZoneUseAccent") == nil and not ZoneAccent() then
                                local red, green, b = EQT.CustomZoneRGB()
                                return red, green, b
                            end
                            return TrackerGet("customZoneR") or 1, TrackerGet("customZoneG") or 1, TrackerGet("customZoneB") or 1
                        end,
                        setValue = function(red, green, blue)
                            Set("customZoneR", red)
                            Set("customZoneG", green)
                            Set("customZoneB", blue)
                            PickZone(false)
                        end,
                        onClick = function(self)
                            if ZoneAccent() then
                                PickZone(false)
                                return
                            end
                            if self._eabOrigClick then
                                self._eabOrigClick(self)
                            end
                        end,
                        refreshAlpha = function()
                            return ZoneAccent() and 0.3 or 1
                        end,
                    },
                    {
                        tooltip = "Accent Colored",
                        hasAlpha = false,
                        getValue = function()
                            return CludesUI.ResolveActiveAccent()
                        end,
                        setValue = function() end,
                        onClick = function()
                            PickZone(true)
                        end,
                        refreshAlpha = function()
                            return ZoneAccent() and 1 or 0.3
                        end,
                    },
                }, {
                    disabled = function()
                        return Off() or TrackerGet("customGroupByZone") == false
                    end,
                    disabledTooltip = function()
                        return Off() and "Custom Quest Tracker" or "Group Quests by Zone"
                    end,
                })
            end

            -- Width | Max Height (also the mover's size rows in Unlock Mode)
            local wMin, wMax, hMin, hMax = EQT.CustomSizeRange()
            local function ApplySize()
                if EQT.SyncPosition then
                    EQT.SyncPosition()
                end
            end
            _, height = W:DualRow(hostFrame, cursorY, {
                type = "slider",
                text = "Width",
                min = wMin,
                max = wMax,
                step = 1,
                disabled = Off,
                disabledTooltip = "Custom Quest Tracker",
                getValue = CfgOr("customWidth", 260),
                setValue = function(val)
                    Set("customWidth", val)
                    ApplySize()
                end,
            }, {
                type = "slider",
                text = "Max Height",
                tooltip = "The tracker grows with your quests up to this height, then scrolls.",
                min = hMin,
                max = hMax,
                step = 1,
                disabled = Off,
                disabledTooltip = "Custom Quest Tracker",
                getValue = CfgOr("customMaxHeight", 450),
                setValue = function(val)
                    Set("customMaxHeight", val)
                    ApplySize()
                end,
            })
            cursorY = cursorY - height

            -- Grow Direction | Scrollbar
            _, height = W:DualRow(hostFrame, cursorY, {
                type = "segmented",
                text = "Grow Direction",
                tooltip = "Which way the tracker grows as quests are added. Up keeps its bottom edge in place.",
                values = { DOWN = "Down", UP = "Up" },
                order = { "DOWN", "UP" },
                disabled = Off,
                disabledTooltip = "Custom Quest Tracker",
                getValue = function()
                    return TrackerGet("customGrowUp") and "UP" or "DOWN"
                end,
                setValue = function(val)
                    EQT.SetCustomGrowUp(val == "UP")
                end,
            }, {
                type = "dropdown",
                text = "Scrollbar",
                tooltip = "When the scrollbar shows while the list is taller than the tracker. The mouse wheel scrolls either way.",
                values = { always = "Always", hover = "Hovered", hidden = "Hidden" },
                order = { "always", "hover", "hidden" },
                disabled = Off,
                disabledTooltip = "Custom Quest Tracker",
                getValue = CfgOr("customScrollbar", "always"),
                setValue = SetRowThen("customScrollbar"),
            })
            cursorY = cursorY - height

            -- Quest Click | Collapse Completed Quests
            _, height = W:DualRow(hostFrame, cursorY, {
                type = "dropdown",
                text = "Quest Click",
                tooltip = "What left-clicking a quest does. Open Quest Details shows CludesUI's own details window and works in combat. Open Quest Log works out of combat only, for quests tracked in the quest log. Ctrl-click still collapses.",
                values = { collapse = "Collapse", map = "Open Quest Log", details = "Open Quest Details" },
                order = { "collapse", "map", "details" },
                disabled = Off,
                disabledTooltip = "Custom Quest Tracker",
                getValue = CfgOr("customClickAction", "collapse"),
                setValue = SetRowThen("customClickAction"),
            }, {
                type = "toggle",
                text = "Collapse Completed Quests",
                tooltip = "Hides the objectives of quests that are ready to turn in. Click a quest to expand it.",
                disabled = Off,
                disabledTooltip = "Custom Quest Tracker",
                getValue = CfgOr("customCollapseCompleted", false),
                setValue = SetRowThen("customCollapseCompleted"),
            })
            cursorY = cursorY - height

            -- Quest Spacing | Objective Spacing
            _, height = W:DualRow(hostFrame, cursorY, {
                type = "slider",
                text = "Quest Spacing",
                min = 0,
                max = 20,
                step = 1,
                disabled = Off,
                disabledTooltip = "Custom Quest Tracker",
                getValue = CfgOr("customQuestSpacing", 4),
                setValue = SetRowThen("customQuestSpacing"),
            }, {
                type = "slider",
                text = "Objective Spacing",
                min = 0,
                max = 10,
                step = 1,
                disabled = Off,
                disabledTooltip = "Custom Quest Tracker",
                getValue = CfgOr("customObjSpacing", 1),
                setValue = SetRowThen("customObjSpacing"),
            })
            cursorY = cursorY - height

            -- Quest Focus | Wrap Quest Names
            _, height = W:DualRow(hostFrame, cursorY, {
                type = "toggle",
                text = "Quest Focus",
                tooltip = "Adds a focus button beside each quest, and Focus to its right-click menu. A focused quest gets the map waypoint.",
                disabled = Off,
                disabledTooltip = "Custom Quest Tracker",
                getValue = CfgOr("customFocusClick", false),
                setValue = SetRowThen("customFocusClick"),
            }, {
                type = "toggle",
                text = "Wrap Quest Names",
                tooltip = "Long quest and zone names wrap onto more lines. Off: one line, cut short with ...",
                disabled = Off,
                disabledTooltip = "Custom Quest Tracker",
                getValue = function()
                    return TrackerGet("customWrapTitles") ~= false
                end,
                setValue = SetRowThen("customWrapTitles"),
            })
            cursorY = cursorY - height

            -- Wrap Objectives | Zone Header Font Size
            _, height = W:DualRow(hostFrame, cursorY, {
                type = "toggle",
                text = "Wrap Objectives",
                tooltip = "Long objectives wrap onto more lines. Off: one line, cut short with ...",
                disabled = Off,
                disabledTooltip = "Custom Quest Tracker",
                getValue = function()
                    return TrackerGet("customWrapObjectives") ~= false
                end,
                setValue = SetRowThen("customWrapObjectives"),
            }, {
                type = "slider",
                text = "Zone Header Font Size",
                min = 8,
                max = 24,
                step = 1,
                disabled = Off,
                disabledTooltip = "Custom Quest Tracker",
                getValue = CfgOr("customZoneFontSize", 13),
                setValue = SetRowThen("customZoneFontSize"),
            })
            cursorY = cursorY - height

            -- Quest Item Buttons | Flash Objective Updates
            _, height = W:DualRow(hostFrame, cursorY, {
                type = "toggle",
                text = "Quest Item Buttons",
                tooltip = "Adds a button beside quests that have a usable item. In combat, buttons stay where they are until combat ends.",
                disabled = Off,
                disabledTooltip = "Custom Quest Tracker",
                getValue = CfgOr("customItemButtons", false),
                setValue = SetRowThen("customItemButtons"),
            }, {
                type = "toggle",
                text = "Flash Objective Updates",
                tooltip = "Briefly highlights an objective when its progress changes.",
                disabled = Off,
                disabledTooltip = "Custom Quest Tracker",
                getValue = CfgOr("customFlashUpdates", false),
                setValue = SetRowThen("customFlashUpdates"),
            })
            cursorY = cursorY - height

            cursorY = cursorY - 10
        end

        -- -- DISPLAY ---------------------------------------------------------
        _, height = W:SectionHeader(hostFrame, "DISPLAY", cursorY)
        cursorY = cursorY - height
        if BS then
            cursorY = BS.Note(hostFrame, cursorY, "questtracker")
        end

        -- Row 1: Visibility | Hide When In Raid. The raid-hide dropdown moved up from
        -- the Background Opacity row into the slot the old Visibility Options dropdown
        -- left behind: it answers the same question the Visibility control does.
        _, height = CludesUI.BuildVisibilityRow(W, hostFrame, cursorY, {
            getStore = DB,
            legacyKey = "visibility",
            caps = { partyIncludesRaid = false, luaDragonriding = true },
            onChanged = function()
                RefreshTracker()
            end,
            onOptionChanged = function()
                RefreshTracker()
            end,
        }, {
            type = "dropdown",
            text = "Hide When In Raid",
            tooltip = "Always: hide the tracker the whole time you are in a raid.\nBoss Combat: keep it visible and only hide during boss encounters.\nNever: keep it visible in raids; only the Visibility options hide it.",
            values = { always = "Always", boss = "Boss Combat", never = "Never" },
            order = { "always", "boss", "never" },
            getValue = CfgOr("hideInRaidMode", "boss"),
            setValue = function(val)
                Set("hideInRaidMode", val)
                if EQT.UpdateVisibility then
                    EQT.UpdateVisibility()
                end
            end,
        })
        cursorY = cursorY - height

        if not STOCK then
            -- Row 2: Background Opacity (slider + inline color swatch) | Show Top Line.
            -- Show Top Line moved up from the old trailing half-row to close the gap left
            -- by Hide When In Raid; both settings describe the tracker's background chrome.
            local bgRow
            bgRow, height = W:DualRow(hostFrame, cursorY, {
                type = "slider",
                text = "Background Opacity",
                min = 0,
                max = 1,
                step = 0.05,
                getValue = CfgOr("bgAlpha", 0.5),
                setValue = function(val)
                    Set("bgAlpha", val)
                    if EQT.ApplyBackground then
                        EQT.ApplyBackground()
                    end
                end,
            }, {
                type = "toggle",
                text = "Show Top Line",
                tooltip = "Draws a 1px accent line above the background at the top of the tracker.",
                getValue = function()
                    return TrackerGet("showTopLine") ~= false
                end,
                setValue = function(val)
                    Set("showTopLine", val)
                    if EQT.ApplyBackground then
                        EQT.ApplyBackground()
                    end
                end,
            })
            if not CludesUI._prebuilding then
                local region = bgRow._leftRegion
                local control = region._control
                -- The custom tracker can hide its background until hovered.
                if CUSTOM then
                    CludesUI.BuildInlineCog(region, {
                        title = "Background Settings",
                        rows = {
                            {
                                type = "toggle",
                                label = "Show Only When Hovered",
                                get = CfgOr("customBgHover", false),
                                set = SetRowThen("customBgHover"),
                            },
                            {
                                type = "toggle",
                                label = "Fade In and Out",
                                disabled = function()
                                    return not TrackerGet("customBgHover")
                                end,
                                disabledTooltip = "Requires Show Only When Hovered.",
                                rawTooltip = true,
                                get = function()
                                    return TrackerGet("customBgFade") ~= false
                                end,
                                set = SetRow("customBgFade"),
                            },
                        },
                    })
                end
                local bgSwatch, bgSwatchRefresh = CludesUI.BuildColorSwatch(
                    region,
                    bgRow:GetFrameLevel() + 3,
                    function()
                        return (TrackerGet("bgR") or 0), (TrackerGet("bgG") or 0), (TrackerGet("bgB") or 0)
                    end,
                    function(red, green, blue)
                        Set("bgR", red)
                        Set("bgG", green)
                        Set("bgB", blue)
                        if EQT.ApplyBackground then
                            EQT.ApplyBackground()
                        end
                    end,
                    false,
                    20
                )
                Pix.Point(bgSwatch, "RIGHT", region._lastInline or control, "LEFT", -8, 0)
                region._lastInline = bgSwatch
                CludesUI.RegisterWidgetRefresh(function()
                    bgSwatchRefresh()
                end)
            end
            cursorY = cursorY - height

            -- Row 3: Header Font Size | Title Font Size
            _, height = W:DualRow(hostFrame, cursorY, {
                type = "slider",
                text = "Header Font Size",
                min = 8,
                max = 24,
                step = 1,
                getValue = CfgOr("headerFontSize", 13),
                setValue = SetRowThen("headerFontSize"),
            }, {
                type = "slider",
                text = "Title Font Size",
                min = 8,
                max = 24,
                step = 1,
                getValue = CfgOr("titleFontSize", 12),
                setValue = SetRowThen("titleFontSize"),
            })
            cursorY = cursorY - height

            -- Row 3b: Objective Font Size | Font
            do
                local fontValues, fontOrder = CludesUI.BuildFontDropdownData()
                _, height = W:DualRow(hostFrame, cursorY, {
                    type = "slider",
                    text = "Objective Font Size",
                    min = 8,
                    max = 24,
                    step = 1,
                    getValue = CfgOr("objectiveFontSize", 10),
                    setValue = SetRowThen("objectiveFontSize"),
                }, {
                    type = "dropdown",
                    text = "Font",
                    values = fontValues,
                    order = fontOrder,
                    getValue = CfgOr("font", "__global"),
                    setValue = function(val)
                        Set("font", val)
                        -- The custom tracker restyles live.
                        if CUSTOM then
                            RefreshTracker()
                            return
                        end
                        CludesUI:ShowConfirmPopup({
                            title = "Reload Required",
                            message = "Font changed. A UI reload is needed to apply the new font.",
                            confirmText = "Reload Now",
                            cancelText = "Later",
                            reload = true,
                        })
                    end,
                })
            end
            cursorY = cursorY - height
        end -- not STOCK

        -- Row 4: Show Quest Icons | Hide All Objectives. Both stock styles show
        -- Blizzard's native icons, so the toggle is gated there.
        local questIconsCfg = {
            type = "toggle",
            text = "Show Quest Icons",
            tooltip = "Show Blizzard's native quest type icons/buttons on the right instead of CludesUI's custom icons. Requires a UI reload.",
            getValue = CfgOr("showQuestIcons", false),
            setValue = function(val)
                Set("showQuestIcons", val)
                CludesUI:ShowConfirmPopup({
                    title = "Reload Required",
                    message = "Changing quest icons requires a UI reload to apply.",
                    confirmText = "Reload Now",
                    cancelText = "Later",
                    reload = true,
                })
            end,
        }
        if BS then
            BS.Gate("questtracker", questIconsCfg)
        end
        if not CUSTOM then
            _, height = W:DualRow(hostFrame, cursorY, questIconsCfg, {
                type = "toggle",
                text = "Hide All Objectives",
                tooltip = STOCK
                        and "Hides the master header and its minimize button at the top of the tracker."
                    or "Hides the master header and its minimize button at the top of the tracker. When shown, it's skinned to match the section headers below it (Quests, Achievements, ...).",
                -- The module's own rule, so the per-style default (hidden under
                -- the CludesUI look, shown under the stock styles) reads true.
                getValue = function()
                    if EQT.ShouldHideMasterHeader then
                        return EQT.ShouldHideMasterHeader()
                    end
                    return TrackerGet("hideAllObjectivesHeader") ~= false
                end,
                setValue = function(val)
                    Set("hideAllObjectivesHeader", val)
                    if EQT.ApplyMasterHeaderVisibility then
                        EQT.ApplyMasterHeaderVisibility()
                    end
                    if EQT.QueueResize then
                        EQT.QueueResize()
                    end
                end,
            })
            cursorY = cursorY - height
        end -- not CUSTOM

        if not STOCK then
            -- -- COLORS ----------------------------------------------------------
            _, height = W:SectionHeader(hostFrame, "COLORS", cursorY)
            cursorY = cursorY - height

            -- `default` must mirror the fallback in the matching Get*RGB()
            -- function in CludesUIQuestTracker_Skin.lua, or the swatch will
            -- show a color (black) that doesn't match what's actually rendered
            -- until the user picks one explicitly.
            local TITLE_KEYS, TITLE_DEFAULT =
                { r = "titleR", g = "titleG", b = "titleB" }, { 1.0, 0.910, 0.471 }
            local DONE_KEYS, DONE_DEFAULT =
                { r = "completedR", g = "completedG", b = "completedB" }, { 0.251, 1.0, 0.349 }
            local function ColorGetter(keyList, default)
                return function()
                    return (TrackerGet(keyList.r) or default[1]),
                        (TrackerGet(keyList.g) or default[2]),
                        (TrackerGet(keyList.b) or default[3])
                end
            end
            local function ColorSetter(keyList)
                return function(cr, cg, checkBtn)
                    Set(keyList.r, cr)
                    Set(keyList.g, cg)
                    Set(keyList.b, checkBtn)
                    RefreshTracker()
                end
            end
            local function WireColorSwatch(r, region, keyList, default)
                local sw, swRefresh = CludesUI.BuildColorSwatch(
                    region,
                    r:GetFrameLevel() + 3,
                    ColorGetter(keyList, default),
                    ColorSetter(keyList),
                    false,
                    20
                )
                Pix.Point(sw, "RIGHT", region, "RIGHT", -20, 0)
                CludesUI.RegisterWidgetRefresh(function()
                    swRefresh()
                end)
            end
            local function MakeColorRow(leftLabel, leftKeys, leftDefault, rightLabel, rightKeys, rightDefault)
                local r, rowH = W:DualRow(
                    hostFrame,
                    cursorY,
                    { type = "label", text = leftLabel },
                    { type = "label", text = rightLabel }
                )
                if not CludesUI._prebuilding then
                    WireColorSwatch(r, r._leftRegion, leftKeys, leftDefault)
                    if rightKeys then
                        WireColorSwatch(r, r._rightRegion, rightKeys, rightDefault)
                    end
                end
                return r, rowH
            end

            if FOREVER then
                -- Title Difficulty Colors | Completed Color. The toggle is the
                -- game's own showQuestDifficultyColor option (EQT.TitleDifficultyOn),
                -- which Blizzard's tracker and quest log follow and the custom
                -- tracker reads; its inline swatch, the Title Color, greys out
                -- while it is on. Retail has no quest title difficulty colors.
                local r
                r, height = W:DualRow(hostFrame, cursorY, {
                    type = "toggle",
                    text = "Title Difficulty Colors",
                    tooltip = "Colors quest titles by difficulty for your level. This is the game's own option, so its quest log follows it too.",
                    getValue = function()
                        return EQT.TitleDifficultyOn()
                    end,
                    setValue = function(val)
                        CludesUI.SetCVar(
                            "showQuestDifficultyColor",
                            val and "1" or "0",
                            "CludesUIQuestTracker"
                        )
                        RefreshTracker()
                        CludesUI:RefreshPage()
                    end,
                }, { type = "label", text = "Completed Color" })
                if not CludesUI._prebuilding then
                    CludesUI.BuildInlineSwatches(r._leftRegion, {
                        {
                            tooltip = "Title Color",
                            hasAlpha = false,
                            getValue = ColorGetter(TITLE_KEYS, TITLE_DEFAULT),
                            setValue = ColorSetter(TITLE_KEYS),
                        },
                    }, {
                        disabled = EQT.TitleDifficultyOn,
                        disabledTooltip = "Title Difficulty Colors",
                        requireState = "disabled",
                    })
                    WireColorSwatch(r, r._rightRegion, DONE_KEYS, DONE_DEFAULT)
                end
            else
                _, height = MakeColorRow(
                    "Title Color",
                    TITLE_KEYS,
                    TITLE_DEFAULT,
                    "Completed Color",
                    DONE_KEYS,
                    DONE_DEFAULT
                )
            end
            cursorY = cursorY - height

            -- Header Color / Line Color: each offers Class Color, Custom Color
            -- (free RGB picker, same swatch behavior as the rows above) and
            -- Accent Color. Default is Accent Color for both (headerUseAccent /
            -- lineUseAccent are treated as true until explicitly set to false).
            -- `customDefault` must mirror the fallback baked into the matching
            -- Get*RGB() function in CludesUIQuestTracker_Skin.lua.
            local function MakeColorModeSwatches(prefixText, customDefault)
                local classKey = prefixText .. "ShowClassColor"
                local accentKey = prefixText .. "UseAccent"
                local rKey, gKey, bKey = prefixText .. "R", prefixText .. "G", prefixText .. "B"

                local function isClass()
                    return TrackerGet(classKey) == true
                end
                local function isAccent()
                    return not isClass() and TrackerGet(accentKey) ~= false
                end

                local classSwatch = {
                    tooltip = "Class Color",
                    hasAlpha = false,
                    getValue = function()
                        local classColor = CludesUI._playerClass and CludesUI.GetClassColor(CludesUI._playerClass)
                        if classColor then
                            return classColor.r, classColor.g, classColor.b
                        end
                        return 1.0, 1.0, 1.0
                    end,
                    setValue = function() end,
                    onClick = function()
                        Set(classKey, true)
                        Set(accentKey, false)
                        RefreshTracker()
                        CludesUI:RefreshPage()
                    end,
                    refreshAlpha = function()
                        return isClass() and 1 or 0.3
                    end,
                }

                local customSwatch = {
                    tooltip = "Custom Color",
                    hasAlpha = false,
                    getValue = function()
                        return (TrackerGet(rKey) or customDefault[1]),
                            (TrackerGet(gKey) or customDefault[2]),
                            (TrackerGet(bKey) or customDefault[3])
                    end,
                    setValue = function(red, green, blue)
                        Set(rKey, red)
                        Set(gKey, green)
                        Set(bKey, blue)
                        Set(classKey, false)
                        Set(accentKey, false)
                        RefreshTracker()
                        CludesUI:RefreshPage()
                    end,
                    onClick = function(self)
                        if isClass() or isAccent() then
                            Set(classKey, false)
                            Set(accentKey, false)
                            RefreshTracker()
                            CludesUI:RefreshPage()
                            return
                        end
                        if self._eabOrigClick then
                            self._eabOrigClick(self)
                        end
                    end,
                    refreshAlpha = function()
                        if isClass() then
                            return 0.15
                        end
                        return isAccent() and 0.3 or 1
                    end,
                }

                local accentSwatch = {
                    tooltip = "Accent Color",
                    hasAlpha = false,
                    getValue = function()
                        return CludesUI.ResolveActiveAccent()
                    end,
                    setValue = function() end,
                    onClick = function()
                        Set(classKey, false)
                        Set(accentKey, true)
                        RefreshTracker()
                        CludesUI:RefreshPage()
                    end,
                    refreshAlpha = function()
                        return isAccent() and 1 or 0.3
                    end,
                }

                return classSwatch, customSwatch, accentSwatch
            end

            -- Focused Color | Header Color
            do
                local hClass, hCustom, hAccent = MakeColorModeSwatches("header", { 1.0, 1.0, 1.0 })
                local r, rowH = W:DualRow(
                    hostFrame,
                    cursorY,
                    { type = "label", text = "Focused Color" },
                    { type = "multiSwatch", text = "Header Color", swatches = { hClass, hCustom, hAccent } }
                )
                if not CludesUI._prebuilding then
                    local sw, swRefresh = CludesUI.BuildColorSwatch(
                        r._leftRegion,
                        r:GetFrameLevel() + 3,
                        function()
                            return (TrackerGet("focusR") or 0.871), (TrackerGet("focusG") or 0.251), (TrackerGet("focusB") or 1.0)
                        end,
                        function(cr, cg, checkBtn)
                            Set("focusR", cr)
                            Set("focusG", cg)
                            Set("focusB", checkBtn)
                            RefreshTracker()
                        end,
                        false,
                        20
                    )
                    Pix.Point(sw, "RIGHT", r._leftRegion, "RIGHT", -20, 0)
                    CludesUI.RegisterWidgetRefresh(function()
                        swRefresh()
                    end)
                end
                height = rowH
            end
            cursorY = cursorY - height

            -- Line Color | Color Objectives by Progress (+ color stops cog). The
            -- objective colors are WoW Forever only; retail keeps the spacer.
            do
                local lClass, lCustom, lAccent = MakeColorModeSwatches("line", { 1.0, 1.0, 1.0 })
                local r
                r, height = W:DualRow(
                    hostFrame,
                    cursorY,
                    { type = "multiSwatch", text = "Line Color", swatches = { lClass, lCustom, lAccent } },
                    FOREVER
                            and {
                                type = "toggle",
                                text = "Color Objectives by Progress",
                                tooltip = "Colors objectives by how far along they are.",
                                getValue = CfgOr("objProgressColor", false),
                                setValue = function(val)
                                    Set("objProgressColor", val)
                                    RefreshTracker()
                                    CludesUI:RefreshPage()
                                end,
                            }
                        or { type = "spacer" }
                )
                if FOREVER then
                    local function Stop(labelText, name)
                        local d = EQT.OBJ_STOPS[name]
                        local kr, kg, kb = "obj" .. name .. "R", "obj" .. name .. "G", "obj" .. name .. "B"
                        return {
                            type = "colorpicker",
                            label = labelText,
                            get = function()
                                return TrackerGet(kr) or d[1], TrackerGet(kg) or d[2], TrackerGet(kb) or d[3]
                            end,
                            set = function(cr, cg, checkBtn)
                                Set(kr, cr)
                                Set(kg, cg)
                                Set(kb, checkBtn)
                                RefreshTracker()
                            end,
                        }
                    end
                    CludesUI.BuildInlineCog(r._rightRegion, {
                        disabled = function()
                            return not TrackerGet("objProgressColor")
                        end,
                        disabledTooltip = "Color Objectives by Progress",
                        title = "Progress Colors",
                        rows = {
                            Stop("Start Color", "Start"),
                            Stop("Halfway Color", "Mid"),
                            Stop("End Color", "End"),
                        },
                    })
                end
            end
            cursorY = cursorY - height

            -- Dim Completed Objectives (+ opacity cog) | blank (WoW Forever only)
            if FOREVER then
                row, height = W:DualRow(hostFrame, cursorY, {
                    type = "toggle",
                    text = "Dim Completed Objectives",
                    tooltip = "Fades objective lines that are already done.",
                    getValue = CfgOr("objDimCompleted", false),
                    setValue = function(val)
                        Set("objDimCompleted", val)
                        RefreshTracker()
                        CludesUI:RefreshPage()
                    end,
                }, CludesUI.BlankRowCfg())
                CludesUI.BuildInlineCog(row._leftRegion, {
                    disabled = function()
                        return not TrackerGet("objDimCompleted")
                    end,
                    disabledTooltip = "Dim Completed Objectives",
                    title = "Dim Settings",
                    rows = {
                        {
                            type = "slider",
                            label = "Opacity",
                            min = 10,
                            max = 100,
                            step = 5,
                            get = CfgOr("objDimAlpha", 45),
                            set = SetRowThen("objDimAlpha"),
                        },
                    },
                })
                cursorY = cursorY - height
            end

            cursorY = cursorY - 10
        end -- not STOCK

        if FOREVER then
            -- -- TRACKING (WoW Forever only) --------------------------------------
            -- Sorting and filters edit the watch list; filtered quests are
            -- untracked and come back once they pass again. They wait behind the
            -- Experimental Quest Tools switch, which warns before it turns on.
            _, height = W:SectionHeader(hostFrame, "TRACKING", cursorY)
            cursorY = cursorY - height
            -- The rows change nothing while the map is open (watch list edits wait
            -- for it to close, CanEditWatches), so the note says so up front.
            -- The custom tracker sorts its own list, so none of that applies there.
            if not CUSTOM then
                cursorY = CludesUI.BuildNoteRow(
                    hostFrame,
                    cursorY,
                    "Sorting, filtering and auto-tracking don't update while the map or quest log is open, in combat or in dungeons. Close the map to apply them.",
                    { banner = true }
                )
            end

            local ApplyWatches, ApplyProgress = EQT.ApplyQuestWatches, EQT.ApplyQuestProgress
            -- Quest Log Order is the base sort mode (a saved "default", the retired
            -- Blizzard order mode, reads as it).
            local function SortModeCfg()
                local m = TrackerGet("questSortMode")
                if m == nil or m == "default" then
                    return "log"
                end
                return m
            end
            -- Section gate: Sort Quests, Filter Quests and Auto Track Zone Quests are
            -- built only while Experimental Quest Tools is on; turning
            -- it on or off rebuilds the page. The progress rows always show.
            -- The custom tracker needs no switch: it never edits the watch list.
            local toolsOn = CUSTOM or TrackerGet("questWatchExperimental") == true
            local function FilterRow(key, labelText)
                return {
                    type = "toggle",
                    label = labelText,
                    get = function()
                        return TrackerGet(key) or false
                    end,
                    set = function(val)
                        Set(key, val)
                        ApplyWatches()
                    end,
                }
            end

            local expCfg = {
                type = "toggle",
                text = "Experimental Quest Tools",
                tooltip = "Unlocks Sort Quests, Filter Quests and Auto Track Zone Quests.",
                disabled = function()
                    return CUSTOM
                end,
                disabledTooltip = "Always on with the Custom Quest Tracker.",
                rawTooltip = CUSTOM or nil,
                getValue = function()
                    return CUSTOM or TrackerGet("questWatchExperimental") == true
                end,
                setValue = function(val)
                    if not val then
                        Set("questWatchExperimental", false)
                        ApplyWatches()
                        CludesUI:RefreshPage(true)
                        return
                    end
                    -- Saved only once the warning is confirmed.
                    CludesUI:ShowConfirmPopup({
                        title = CludesUI.L("Experimental Feature"),
                        message = CludesUI.L(
                            "Quest sorting, filtering and zone auto-tracking are experimental and may cause occasional Lua errors. If you run into one, type /reload or turn this option off."
                        ),
                        confirmText = CludesUI.L("Enable"),
                        cancelText = CludesUI.L("Cancel"),
                        onConfirm = function()
                            Set("questWatchExperimental", true)
                            ApplyWatches()
                            CludesUI:RefreshPage(true)
                        end,
                        onCancel = function()
                            CludesUI:RefreshPage()
                        end,
                    })
                end,
            }

            local sndValues, sndOrder = CludesUI.BuildSoundDropdownValues(EQT.Sounds())
            -- Preview through the module so the peon FileDataIDs play correctly.
            sndValues._menuOpts.iconOnClick = EQT.PlaySoundKey
            local announceCfg = {
                type = "toggle",
                text = "Announce Progress",
                tooltip = "Posts each quest objective you complete to party or instance chat, with a link to the quest. Never in raids.",
                getValue = CfgOr("announceProgress", false),
                setValue = function(val)
                    Set("announceProgress", val)
                    ApplyProgress()
                end,
            }
            local objSoundCfg = {
                type = "dropdown",
                text = "Objective Complete Sound",
                values = sndValues,
                order = sndOrder,
                getValue = CfgOr("soundObjective", "none"),
                setValue = function(val)
                    Set("soundObjective", val)
                    ApplyProgress()
                end,
            }
            local questSoundCfg = {
                type = "dropdown",
                text = "Quest Complete Sound",
                values = sndValues,
                order = sndOrder,
                getValue = CfgOr("soundQuest", "none"),
                setValue = function(val)
                    Set("soundQuest", val)
                    ApplyProgress()
                end,
            }

            if not toolsOn then
                -- Experimental Quest Tools | Announce Progress, then the two sounds.
                _, height = W:DualRow(hostFrame, cursorY, expCfg, announceCfg)
                cursorY = cursorY - height
                _, height = W:DualRow(hostFrame, cursorY, objSoundCfg, questSoundCfg)
                cursorY = cursorY - height
            else
                -- Experimental Quest Tools | Sort Quests (+ completed placement cog)
                row, height = W:DualRow(hostFrame, cursorY, expCfg, {
                    type = "dropdown",
                    text = "Sort Quests",
                    tooltip = "Reorders your tracked quests; Quest Log Order lists them as your quest log does.",
                    values = {
                        log = "Quest Log Order",
                        zone = "Zone",
                        level = "Level",
                        name = "Name",
                        progress = "Progress",
                        type = "Quest Type",
                    },
                    order = { "log", "zone", "level", "name", "progress", "type" },
                    getValue = SortModeCfg,
                    setValue = function(val)
                        Set("questSortMode", val)
                        ApplyWatches()
                    end,
                })
                CludesUI.BuildInlineCog(row._rightRegion, {
                    title = "Sort Settings",
                    rows = {
                        {
                            type = "dropdown",
                            label = "Completed Quests",
                            values = { mixed = "Mixed In", top = "Top", bottom = "Bottom" },
                            order = { "mixed", "top", "bottom" },
                            get = CfgOr("questSortCompleted", "mixed"),
                            set = function(val)
                                Set("questSortCompleted", val)
                                ApplyWatches()
                            end,
                        },
                        {
                            type = "dropdown",
                            label = "Then By",
                            values = {
                                none = "None",
                                zone = "Zone",
                                level = "Level",
                                name = "Name",
                                progress = "Progress",
                                type = "Quest Type",
                            },
                            order = { "none", "zone", "level", "name", "progress", "type" },
                            disabled = function()
                                return SortModeCfg() == "log"
                            end,
                            disabledTooltip = "Requires Sort Quests set to something other than Quest Log Order.",
                            rawTooltip = true,
                            get = CfgOr("questSortThenBy", "none"),
                            set = function(val)
                                Set("questSortThenBy", val)
                                ApplyWatches()
                            end,
                        },
                    },
                })
                cursorY = cursorY - height

                -- Filter Quests (+ filters cog) | Auto Track Zone Quests
                row, height = W:DualRow(hostFrame, cursorY, {
                    type = "toggle",
                    text = "Filter Quests",
                    tooltip = "Untracks quests that match the filters in the cog until they no longer match.",
                    getValue = CfgOr("filterEnabled", false),
                    setValue = function(val)
                        Set("filterEnabled", val)
                        ApplyWatches()
                        CludesUI:RefreshPage()
                    end,
                }, {
                    type = "toggle",
                    text = "Auto Track Zone Quests",
                    tooltip = "Tracks your current zone's or dungeon's quests and untracks them when you leave.",
                    getValue = CfgOr("autoTrackZone", false),
                    setValue = function(val)
                        Set("autoTrackZone", val)
                        ApplyWatches()
                    end,
                })
                CludesUI.BuildInlineCog(row._leftRegion, {
                    -- Open while the header button shows too: it turns Filter Quests
                    -- off, and its own row is in here.
                    disabled = function()
                        return not TrackerGet("filterEnabled") and not TrackerGet("filterHeaderToggle")
                    end,
                    disabledTooltip = "Filter Quests",
                    title = "Filter Settings",
                    rows = {
                        FilterRow("filterZone", "Current Zone Only"),
                        FilterRow("filterCompleted", "Hide Completed Quests"),
                        FilterRow("filterTrivial", "Hide Low Level Quests"),
                        FilterRow("filterRepeatable", "Hide Daily & Weekly Quests"),
                        FilterRow("filterHeaderToggle", "Show Toggle on Quests Header"),
                    },
                })
                cursorY = cursorY - height

                -- Announce Progress | Objective Complete Sound, then Quest Complete Sound
                _, height = W:DualRow(hostFrame, cursorY, announceCfg, objSoundCfg)
                cursorY = cursorY - height
                _, height = W:DualRow(hostFrame, cursorY, questSoundCfg, CludesUI.BlankRowCfg())
                cursorY = cursorY - height
            end

            cursorY = cursorY - 10
        end -- FOREVER

        -- -- EXTRAS ----------------------------------------------------------
        _, height = W:SectionHeader(hostFrame, "EXTRAS", cursorY)
        cursorY = cursorY - height

        row, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Auto Accept Quests",
            getValue = CfgOr("autoAccept", false),
            setValue = function(val)
                Set("autoAccept", val)
                if EQT.SyncAutoQuests then
                    EQT.SyncAutoQuests()
                end
            end,
        }, {
            type = "toggle",
            text = "Auto Turn In Quests",
            getValue = CfgOr("autoTurnIn", false),
            setValue = function(val)
                Set("autoTurnIn", val)
                if EQT.SyncAutoQuests then
                    EQT.SyncAutoQuests()
                end
            end,
        })
        local acceptRows = {
            {
                type = "toggle",
                label = "Prevent Multi Quest Accept",
                get = function()
                    return TrackerGet("autoAcceptPreventMulti") ~= false
                end,
                set = SetRow("autoAcceptPreventMulti"),
            },
            -- Hold Shift to Enable and Hold Shift to Skip are opposites: turning one on turns the other off.
            {
                type = "toggle",
                label = "Hold Shift to Enable",
                get = CfgIs("autoAcceptShiftEnable"),
                set = function(val)
                    Set("autoAcceptShiftEnable", val)
                    if val then
                        Set("autoAcceptShiftSkip", false)
                    end
                end,
            },
            {
                type = "toggle",
                label = "Hold Shift to Skip",
                get = function()
                    return TrackerGet("autoAcceptShiftSkip") ~= false
                end,
                set = function(val)
                    Set("autoAcceptShiftSkip", val)
                    if val then
                        Set("autoAcceptShiftEnable", false)
                    end
                end,
            },
            {
                type = "toggle",
                label = "Ignore Low Level Quests",
                get = CfgOr("autoAcceptIgnoreTrivial", false),
                set = SetRow("autoAcceptIgnoreTrivial"),
            },
        }
        -- WoW Forever has no older expansions to skip.
        if not CludesUI.IS_FOREVER then
            acceptRows[#acceptRows + 1] = {
                type = "toggle",
                label = "Ignore Older Expansion Quests",
                get = CfgOr("autoAcceptIgnoreOldExpansion", false),
                set = SetRow("autoAcceptIgnoreOldExpansion"),
            }
        end
        CludesUI.BuildInlineCog(row._leftRegion, {
            title = "Auto Accept Settings",
            rows = acceptRows,
        })

        CludesUI.BuildInlineCog(row._rightRegion, {
            title = "Auto Turn In Settings",
            rows = {
                {
                    type = "toggle",
                    label = "Hold Shift to Enable",
                    get = CfgIs("autoTurnInShiftEnable"),
                    set = function(val)
                        Set("autoTurnInShiftEnable", val)
                        if val then
                            Set("autoTurnInShiftSkip", false)
                        end
                    end,
                },
                {
                    type = "toggle",
                    label = "Hold Shift to Skip",
                    get = function()
                        return TrackerGet("autoTurnInShiftSkip") ~= false
                    end,
                    set = function(val)
                        Set("autoTurnInShiftSkip", val)
                        if val then
                            Set("autoTurnInShiftEnable", false)
                        end
                    end,
                },
            },
        })
        cursorY = cursorY - height

        -- Quest Item Hotkey row
        local kbRow
        kbRow, height = W:DualRow(hostFrame, cursorY, { type = "label", text = "" }, {
            type = "toggle",
            text = "Wowhead Quest Links",
            tooltip = "Adds a copyable Wowhead link to the right-click menu of quests in the quest tracker and quest log.",
            getValue = CfgIs("wowheadQuestLinks"),
            setValue = function(val)
                Set("wowheadQuestLinks", val)
                EQT.ApplyQuestLinks()
                CludesUI:RefreshPage()
            end,
        })
        CludesUI.BuildInlineCog(kbRow._rightRegion, {
            title = "Wowhead Link Settings",
            disabled = function()
                return not TrackerGet("wowheadQuestLinks")
            end,
            disabledTooltip = "Wowhead Quest Links",
            rows = {
                {
                    type = "toggle",
                    label = "Use Client Language",
                    get = CfgIs("wowheadQuestClientLanguage"),
                    set = SetRow("wowheadQuestClientLanguage"),
                },
                {
                    type = "toggle",
                    label = "Jump to Comments",
                    get = CfgIs("wowheadQuestComments"),
                    set = SetRow("wowheadQuestComments"),
                },
            },
        })
        if not CludesUI._prebuilding then
            local region = kbRow._leftRegion
            local SIDE_PAD = 20

            local labelText = CludesUI.MakeFont(
                region,
                14,
                nil,
                CludesUI.TEXT_WHITE_R,
                CludesUI.TEXT_WHITE_G,
                CludesUI.TEXT_WHITE_B
            )
            Pix.Point(labelText, "LEFT", region, "LEFT", SIDE_PAD, 0)
            labelText:SetText(CludesUI.L("Quest Item Hotkey"))

            local kbBtn, refresh = CludesUI.BuildKeybindButton(region, {
                w = 120,
                h = 26,
                pp = Pix,
                level = 5,
                get = function()
                    return TrackerGet("questItemHotkey")
                end,
                set = function(val)
                    Set("questItemHotkey", val)
                    if EQT.ApplyQuestItemHotkey then
                        EQT.ApplyQuestItemHotkey()
                    end
                end,
            })
            Pix.Point(kbBtn, "RIGHT", region, "RIGHT", -SIDE_PAD, 0)
            CludesUI.RegisterWidgetRefresh(refresh)
        end
        cursorY = cursorY - height

        return math.abs(cursorY)
    end

    _G._CUBS_BuildQuestTrackerPage = BuildPage

    CludesUI:RegisterModule("CludesUIQuestTracker", {
        title = "Quest Tracker",
        description = "Blizzard tracker skin, visibility rules, auto-accept/turn-in, quest-item hotkey.",
        pages = { "Quest Tracker" },
        buildPage = function(page, p, yOffset)
            return BuildPage(page, p, yOffset)
        end,
        onReset = function()
            local db = _G._CUQT_DB
            if db and db.ResetProfile then
                db:ResetProfile()
            end
            RefreshTracker()
            CludesUI:InvalidatePageCache()
        end,
    })

    SLASH_EQTOPTS1 = "/cqtopts"
    SlashCmdList.EQTOPTS = function()
        if InCombatLockdown and InCombatLockdown() then
            return
        end
        CludesUI:ShowModule("CludesUIQuestTracker")
    end
end)
