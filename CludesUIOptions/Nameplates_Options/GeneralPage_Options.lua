if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  Nameplates_Options\GeneralPage_Options.lua
--  Nameplates options: the General page (BuildGeneralPage). Definitions only;
--  the shared helpers come from ns._NPO_OptEnv (filled by
--  CUI_Nameplates_Options.lua).
-------------------------------------------------------------------------------
local mod = CludesUI._ModuleNS["CludesUINameplates"]
if not mod then return end -- module disabled: no options page

-- The options page frame pool (CludesUI_FramePool.lua): frames made under a
-- pooled page part are handed back to the page's next build.
local CreateFrame = CludesUI._Pool.CreateFrame

-- A row half's slider label, for a "(Percent)" suffix beside it: the half's own
-- label (a page built again keeps its earlier dresses' font strings, idle,
-- among the half's regions).
local function SliderLabel(region, textValue)
    local labelText = region._label
    if labelText and labelText.GetText and CludesUI.EnKey(labelText:GetText()) == textValue then
        return labelText
    end
end

---------------------------------------------------------------------------
--  General page (Friendly settings, Spacing, Show All Debuffs); two-column DualRow layout where possible
---------------------------------------------------------------------------
local function BuildGeneralPage(page, hostFrame, yOffset)
    local environ = mod._NPO_OptEnv
    local DB, DBVal, defaultSet, FOCUS_LETTER_ANCHOR_ORDER =
        environ.DB, environ.DBVal, environ.defaults, environ.FOCUS_LETTER_ANCHOR_ORDER
    -- Row getters over DBVal: a key's value (or a default), or whether it is true.
    local function DBValOr(key, default)
        return function() return DBVal(key) or default end
    end
    local function DBValIs(key)
        return function() return DBVal(key) == true end
    end
    local FOCUS_LETTER_ANCHORS, GetFocusLetterAnchor, GetNPOptOutline, npDispelGlowDesc =
        environ.FOCUS_LETTER_ANCHORS,
        environ.GetFocusLetterAnchor,
        environ.GetNPOptOutline,
        environ.npDispelGlowDesc
    local npPandemicGlowDesc = environ.npPandemicGlowDesc
    local pairs, pcall, plates, Pix = environ.pairs, environ.pcall, environ.plates, environ.PP
    local RefreshAllAuras, RefreshAllPlates, SECTION_AURA, SECTION_ENEMY_NP =
        environ.RefreshAllAuras, environ.RefreshAllPlates, environ.SECTION_AURA, environ.SECTION_ENEMY_NP
    local SECTION_FRIENDLY, SECTION_MISC, UpdatePreview =
        environ.SECTION_FRIENDLY, environ.SECTION_MISC, environ.UpdatePreview
    local W = CludesUI.Widgets
    local cursorY = yOffset
    local _, height

    -- No preview on General tab
    CludesUI:ClearContentHeader()

    -- Enable per-row center divider for the dual-column layout
    hostFrame._showRowDivider = true

    -----------------------------------------------------------------------
    --  FRIENDLY NAMEPLATES
    -----------------------------------------------------------------------
    _, height = W:SectionHeader(hostFrame, SECTION_FRIENDLY, cursorY)
    cursorY = cursorY - height

    local function friendlyPlayersOff() return DBVal("showFriendlyPlayers") == false end
    local function friendlyPlateOff() return friendlyPlayersOff() or DBVal("friendlyNameOnly") ~= false end
    local function nameOnlyOff() return friendlyPlayersOff() or DBVal("friendlyNameOnly") == false end
    -- Title renders INLINE with the name (one string, takes the name's own font/size/color); only the guild line below is styled by the size/color/bracket controls, so those gate on a mode that includes guild.
    local function subtitleGuildOff()
        local m = DBVal("friendlyBelowName") or "none"
        return friendlyPlayersOff() or (m ~= "guild" and m ~= "both")
    end

    local friendlyRow
    _, height = W:DualRow(hostFrame, cursorY, {
        type = "toggle",
        text = "Show CUI Friendly Player Nameplates",
        tooltip = "When disabled, CUI relinquishes full control of friendly player nameplates to Blizzard. Use Blizzard's own Nameplate settings (Esc > Options > Nameplates) to control them.",
        getValue = function() return DBVal("showFriendlyPlayers") ~= false end,
        setValue = function(val)
            DB().showFriendlyPlayers = val
            do
                if val then
                    -- Enabling: re-assert every friendly-player CVar that SetupAuraCVars sets on load (it skips these while the toggle is off) -- runtime is the only restore path short of /reload.
                    local profile = DB()
                    local nameOnly = (profile and profile.friendlyNameOnly ~= false)
                    local classColor = (profile and profile.classColorFriendly ~= false)
                    -- One of only two places CUI is allowed to force friendly plates visible; also clears any follower-dungeon capture.
                    if mod.ForceFriendlyPlayerCVarsOn then mod.ForceFriendlyPlayerCVarsOn() end
                    pcall(CludesUI.SetCVar, "UnitNameFriendlyPlayerName", 1, "CludesUINameplates")
                    pcall(
                        CludesUI.SetCVar,
                        "nameplateShowOnlyNameForFriendlyPlayerUnits",
                        nameOnly and 1 or 0,
                        "CludesUINameplates"
                    )
                    pcall(
                        CludesUI.SetCVar,
                        "ShowClassColorInFriendlyNameplate",
                        classColor and 1 or 0,
                        "CludesUINameplates"
                    )
                    pcall(
                        CludesUI.SetCVar,
                        "nameplateUseClassColorForFriendlyPlayerUnitNames",
                        mod.FriendlyNameClassCVar(profile),
                        "CludesUINameplates"
                    )
                else
                    -- Disabling: reset the three CVars CUI uniquely manages (name-only override + class color) to Blizzard defaults for a clean slate; visibility CVars stay untouched so Blizzard's panel keeps the user's values.
                    if GetCVarDefault then
                        for _, cvar in ipairs({
                            "nameplateShowOnlyNameForFriendlyPlayerUnits",
                            "ShowClassColorInFriendlyNameplate",
                            "nameplateUseClassColorForFriendlyPlayerUnitNames",
                        }) do
                            local d = GetCVarDefault(cvar)
                            if d ~= nil then pcall(CludesUI.SetCVar, cvar, d, "CludesUINameplates") end
                        end
                    end
                end
            end
            if mod.UpdateFriendlyNameplateSystem then mod.UpdateFriendlyNameplateSystem() end
            -- Re-assert stacking after friendly CVar changes (Blizzard can reset the stacking bitfield as a side effect).
            mod.RefreshStackingMotion()
            CludesUI:RefreshPage()
        end,
    }, {
        type = "toggle",
        text = "Make Friendly Nameplates Name Only",
        tooltip = "Hide friendly player health bars and instead only see their names.\n\nRequires 'Simplified Friendly Nameplates' to be disabled in Blizzard's Nameplate settings (Esc > Options > Nameplates).",
        getValue = function() return DBVal("friendlyNameOnly") ~= false end,
        setValue = function(val)
            DB().friendlyNameOnly = val
            pcall(
                CludesUI.SetCVar,
                "nameplateShowOnlyNameForFriendlyPlayerUnits",
                val and 1 or 0,
                "CludesUINameplates"
            )
            -- Turning name-only ON means the user wants to SEE friendly plates -- the second sanctioned force-visible point.
            if val and mod.ForceFriendlyPlayerCVarsOn then mod.ForceFriendlyPlayerCVarsOn() end
            if mod.UpdateFriendlyNameplateSystem then mod.UpdateFriendlyNameplateSystem() end
            CludesUI:RefreshPage()
        end,
        disabled = friendlyPlayersOff,
        disabledTooltip = "Show CUI Friendly Player Nameplates",
    })
    friendlyRow = _
    cursorY = cursorY - height

    ---------------------------------------------------------------
    --  Friendly Player cog popup (size, health text, class colours, target border)
    ---------------------------------------------------------------
    if not CludesUI._prebuilding then
        CludesUI.BuildInlineCog(friendlyRow._leftRegion, {
            chain = false,
            disabled = friendlyPlateOff,
            disabledTooltip = "Requires Name Only setting to be disabled",
            rawTooltip = true,
            title = "Friendly Nameplate Settings",
            rows = {
                {
                    type = "slider",
                    label = "Distance",
                    min = -50,
                    max = 50,
                    step = 1,
                    get = DBValOr("friendlyPlateYOffset", 0),
                    set = function(val)
                        DB().friendlyPlateYOffset = val
                        if mod.RefreshFriendlyPlateYOffset then mod.RefreshFriendlyPlateYOffset() end
                    end,
                },
                {
                    type = "slider",
                    label = "Height",
                    min = 6,
                    max = 40,
                    step = 1,
                    get = function()
                        return DBVal("friendlyHealthBarHeight") or defaultSet.friendlyHealthBarHeight
                    end,
                    set = function(val)
                        DB().friendlyHealthBarHeight = val
                        if mod.RefreshFriendlyPlateSize then mod.RefreshFriendlyPlateSize() end
                    end,
                },
                {
                    type = "slider",
                    label = "Width",
                    min = 80,
                    max = 250,
                    step = 1,
                    get = function()
                        return DBVal("friendlyHealthBarWidth") or defaultSet.friendlyHealthBarWidth
                    end,
                    set = function(val)
                        DB().friendlyHealthBarWidth = val
                        if mod.RefreshFriendlyPlateSize then mod.RefreshFriendlyPlateSize() end
                    end,
                },
                {
                    type = "slider",
                    label = "Name Size",
                    min = 6,
                    max = 30,
                    step = 1,
                    get = function() return DBVal("friendlyNameTextSize") or defaultSet.friendlyNameTextSize end,
                    set = function(val)
                        DB().friendlyNameTextSize = val
                        if mod.RefreshFriendlyNameTextSize then mod.RefreshFriendlyNameTextSize() end
                    end,
                },
                {
                    type = "toggle",
                    label = "Show Health Percent",
                    get = function()
                        local saved = DB()
                        return not (saved and saved.friendlyHideHealthText)
                    end,
                    set = function(val)
                        DB().friendlyHideHealthText = not val
                        if mod.RefreshFriendlyHealthText then mod.RefreshFriendlyHealthText() end
                    end,
                },
                {
                    type = "toggle",
                    label = "Class Colored Health Bar",
                    get = function() return DBVal("classColorFriendly") ~= false end,
                    set = function(val)
                        DB().classColorFriendly = val and true or false
                        -- Blizzard's instance plates colour their names by this CVar.
                        if not InCombatLockdown() then
                            pcall(
                                CludesUI.SetCVar,
                                "nameplateUseClassColorForFriendlyPlayerUnitNames",
                                mod.FriendlyNameClassCVar(DB()),
                                "CludesUINameplates"
                            )
                        end
                        mod.RefreshAllSettings()
                    end,
                },
                {
                    type = "colorpicker",
                    label = "Health Bar Color",
                    tooltip = "Health bar color for friendly players when Class Colored Health Bar is off.",
                    disabled = function() return DBVal("classColorFriendly") ~= false end,
                    disabledTooltip = "Class Colored Health Bar",
                    requireState = "disabled",
                    get = function()
                        local color = DBVal("friendlyBarColor") or defaultSet.friendlyBarColor
                        return color.r, color.g, color.b
                    end,
                    set = function(red, green, blue)
                        DB().friendlyBarColor = { r = red, g = green, b = blue }
                        mod.RefreshFriendlyColors()
                    end,
                },
                {
                    type = "toggle",
                    label = "Class Colored Names",
                    get = DBValIs("friendlyNameClassColor"),
                    set = function(val)
                        DB().friendlyNameClassColor = val and true or false
                        if not InCombatLockdown() then
                            pcall(
                                CludesUI.SetCVar,
                                "nameplateUseClassColorForFriendlyPlayerUnitNames",
                                mod.FriendlyNameClassCVar(DB()),
                                "CludesUINameplates"
                            )
                        end
                        mod.RefreshFriendlyColors()
                    end,
                },
                {
                    type = "toggle",
                    label = "Target Border Effects",
                    tooltip = "Also applies the target Border Color and Border Size effects to friendly nameplates.",
                    -- Borders stand down under the stock styles.
                    disabled = function()
                        return CludesUI.BlizzStyle.Get("nameplates")
                            or not (mod.GetTargetGlowBorderColor() or mod.GetTargetGlowBorderSize())
                    end,
                    disabledTooltip = function()
                        if CludesUI.BlizzStyle.Get("nameplates") then
                            return CludesUI.BlizzStyle.Label("nameplates")
                        end
                        return "This option requires the Border Color or Border Size target effect."
                    end,
                    rawTooltip = function() return not CludesUI.BlizzStyle.Get("nameplates") end,
                    requireState = "disabled",
                    get = DBValIs("friendlyTargetBorderFx"),
                    set = function(val)
                        DB().friendlyTargetBorderFx = val
                        -- Applies to (or restores) the friendly target now.
                        for _, fp in pairs(mod.friendlyPlates) do
                            fp:ApplyTarget()
                        end
                        UpdatePreview()
                    end,
                },
            },
        })
    end

    ---------------------------------------------------------------
    --  Name Only inline swatches (White + Class Color) mirror the Target Arrows double-swatch pattern: classColorFriendly picks the active swatch (inactive dims); neither opens a picker (White fixed, Class = player's class color). Both gray out when Name Only is off.
    ---------------------------------------------------------------
    if not CludesUI._prebuilding then
        local rightRegion = friendlyRow._rightRegion
        local whiteSwatch, updateWhite, classSwatch, updateClass
        local function refreshNameSwatches()
            if updateWhite then updateWhite() end
            if updateClass then updateClass() end
            local off = nameOnlyOff()
            local useClass = DBVal("classColorFriendly") ~= false
            whiteSwatch:SetAlpha(off and 0.15 or (useClass and 0.3 or 1))
            classSwatch:SetAlpha(off and 0.15 or (useClass and 1 or 0.3))
            whiteSwatch:SetMouseClickEnabled(not off)
            classSwatch:SetMouseClickEnabled(not off)
        end
        local function ApplyClassColored(useClass)
            DB().classColorFriendly = useClass and true or false
            pcall(
                CludesUI.SetCVar,
                "ShowClassColorInFriendlyNameplate",
                useClass and 1 or 0,
                "CludesUINameplates"
            )
            pcall(
                CludesUI.SetCVar,
                "nameplateUseClassColorForFriendlyPlayerUnitNames",
                mod.FriendlyNameClassCVar(DB()),
                "CludesUINameplates"
            )
            if mod.RefreshAllSettings then mod.RefreshAllSettings() end
            refreshNameSwatches()
        end
        -- White swatch: fixed white, not editable; clicking only selects the non-class-colored mode (default OnClick picker replaced below).
        whiteSwatch, updateWhite = CludesUI.BuildColorSwatch(
            rightRegion,
            rightRegion:GetFrameLevel() + 5,
            function() return 1, 1, 1 end,
            function() end,
            nil,
            20
        )
        Pix.Point(whiteSwatch, "RIGHT", rightRegion._control, "LEFT", -8, 0)
        whiteSwatch:SetScript("OnClick", function()
            if nameOnlyOff() then return end
            ApplyClassColored(false)
        end)
        CludesUI.HoverTip(whiteSwatch, "White")
        -- Class color swatch: player's class color; selects class-colored mode.
        classSwatch, updateClass = CludesUI.BuildColorSwatch(
            rightRegion,
            rightRegion:GetFrameLevel() + 5,
            function()
                local _, classTok = UnitClass("player")
                local classColor = classTok and C_ClassColor and C_ClassColor.GetClassColor(classTok)
                if classColor then return classColor.r, classColor.g, classColor.b end
                return 1, 1, 1
            end,
            function() end,
            nil,
            20
        )
        Pix.Point(classSwatch, "RIGHT", whiteSwatch, "LEFT", -8, 0)
        rightRegion._lastInline = classSwatch
        classSwatch:SetScript("OnClick", function()
            if nameOnlyOff() then return end
            ApplyClassColored(true)
        end)
        CludesUI.HoverTip(classSwatch, "Class Color")
        CludesUI.RegisterWidgetRefresh(refreshNameSwatches)
        refreshNameSwatches()
    end

    ---------------------------------------------------------------
    --  Subtitle Text: title renders inline with the name, guild sits on its own line below. The colour pair styles ONLY the guild line -- the inline title is part of the name string, using its colour.
    ---------------------------------------------------------------
    -- Custom/Class pair follows the multiSwatch convention: clicking the INACTIVE custom swatch only selects custom mode (click again to open the picker); the inactive swatch dims, both grey out together.
    local function MakeGuildColorSwatches()
        return {
            {
                tooltip = "Custom Color",
                hasAlpha = false,
                getValue = function()
                    local color = DBVal("friendlyBelowNameColor") or defaultSet.friendlyBelowNameColor
                    return color.r, color.g, color.b
                end,
                setValue = function(red, green, blue)
                    DB().friendlyBelowNameColor = { r = red, g = green, b = blue }
                    if mod.RefreshFriendlyBelowName then mod.RefreshFriendlyBelowName() end
                end,
                onClick = function(self)
                    if DBVal("friendlyBelowNameClassColor") == true then
                        DB().friendlyBelowNameClassColor = false
                        if mod.RefreshFriendlyBelowName then mod.RefreshFriendlyBelowName() end
                        CludesUI:RefreshPage()
                        return
                    end
                    if self._eabOrigClick then self._eabOrigClick(self) end
                end,
                refreshAlpha = function()
                    if subtitleGuildOff() then return 0.15 end
                    return (DBVal("friendlyBelowNameClassColor") == true) and 0.3 or 1
                end,
            },
            {
                tooltip = "Class Color",
                hasAlpha = false,
                getValue = function()
                    local _, ct = UnitClass("player")
                    local classColor = ct and C_ClassColor and C_ClassColor.GetClassColor(ct)
                    if classColor then return classColor.r, classColor.g, classColor.b end
                    return 1, 1, 1
                end,
                setValue = function() end,
                onClick = function()
                    DB().friendlyBelowNameClassColor = true
                    if mod.RefreshFriendlyBelowName then mod.RefreshFriendlyBelowName() end
                    CludesUI:RefreshPage()
                end,
                refreshAlpha = function()
                    if subtitleGuildOff() then return 0.15 end
                    return (DBVal("friendlyBelowNameClassColor") == true) and 1 or 0.3
                end,
            },
        }
    end

    local subtitleRow
    subtitleRow, height = W:DualRow(hostFrame, cursorY, {
        type = "dropdown",
        text = "Subtitle Text",
        tooltip = "Show the player's title inline with their name, and/or their guild on a line below it, on friendly nameplates.",
        disabled = friendlyPlayersOff,
        disabledTooltip = "Show CUI Friendly Player Nameplates",
        values = { none = "None", title = "Player Title", guild = "Guild Name", both = "Title & Guild" },
        order = { "none", "title", "guild", "both" },
        getValue = DBValOr("friendlyBelowName", "none"),
        setValue = function(val)
            DB().friendlyBelowName = val
            if mod.RefreshFriendlyBelowName then mod.RefreshFriendlyBelowName() end
            CludesUI:RefreshPage()
        end,
    }, {
        type = "multiSwatch",
        text = "Guild Text Color",
        disabled = subtitleGuildOff,
        disabledTooltip = function()
            if friendlyPlayersOff() then return "Show CUI Friendly Player Nameplates" end
            return "This option requires Subtitle Text to include the Guild Name"
        end,
        rawTooltip = function() return not friendlyPlayersOff() end,
        swatches = MakeGuildColorSwatches(),
    })
    cursorY = cursorY - height

    -- Subtitle Text inline cog: Name Text Settings, headed by the friendly Name
    -- Format (a friendly player's name, in both modes), so the cog opens
    -- whenever friendly players show and the guild row carries the guild
    -- requirement itself.
    if not CludesUI._prebuilding then
        CludesUI.BuildInlineCog(subtitleRow._leftRegion, {
            chain = false,
            disabled = friendlyPlayersOff,
            disabledTooltip = "Show CUI Friendly Player Nameplates",
            title = "Name Text Settings",
            rows = {
                -- WoW Forever names it for players, as Forever Essentials' Name
                -- Format section does (it only ever shaped players' names).
                CludesUI.NameFormatCogRow(function() return DBVal("friendlyNameFormat") end, function(val)
                    DB().friendlyNameFormat = val
                    mod.NP_SyncFriendlyNameFormat()
                end, CludesUI.IS_FOREVER == true and {
                    label = "Player Name Format",
                    tooltip = "Friendly player names on nameplates, in both modes.",
                } or nil),
                {
                    type = "toggle",
                    label = "Show Level",
                    get = DBValIs("friendlyShowLevel"),
                    set = function(val)
                        DB().friendlyShowLevel = val and true or false
                        if mod.RefreshFriendlyBelowName then mod.RefreshFriendlyBelowName() end
                    end,
                },
                {
                    type = "toggle",
                    label = "Color Level by Difficulty",
                    disabled = function() return DBVal("friendlyShowLevel") ~= true end,
                    disabledTooltip = "This option requires Show Level",
                    rawTooltip = true,
                    get = DBValIs("friendlyLevelDiffColor"),
                    set = function(val)
                        DB().friendlyLevelDiffColor = val and true or false
                        if mod.RefreshFriendlyBelowName then mod.RefreshFriendlyBelowName() end
                    end,
                },
                {
                    type = "toggle",
                    label = "Show <> Around Guild",
                    disabled = subtitleGuildOff,
                    disabledTooltip = "This option requires Subtitle Text to include the Guild Name",
                    rawTooltip = true,
                    get = function() return DBVal("friendlyBelowNameGuildBrackets") ~= false end,
                    set = function(val)
                        DB().friendlyBelowNameGuildBrackets = val and true or false
                        if mod.RefreshFriendlyBelowName then mod.RefreshFriendlyBelowName() end
                    end,
                },
            },
        })
    end

    local npcRow
    npcRow, height = W:DualRow(hostFrame, cursorY, {
        type = "toggle",
        text = "Show Friendly NPC Nameplates",
        getValue = DBValIs("showFriendlyNPCs"),
        setValue = function(val)
            DB().showFriendlyNPCs = val
            pcall(CludesUI.SetCVar, "nameplateShowFriendlyNPCs", val and 1 or 0, "CludesUINameplates")
            pcall(CludesUI.SetCVar, "nameplateShowFriendlyNpcs", val and 1 or 0, "CludesUINameplates")
            if mod.UpdateFriendlyNameplateSystem then mod.UpdateFriendlyNameplateSystem() end
            CludesUI:RefreshPage()
        end,
    }, {
        type = "slider",
        text = "Friendly Name Size",
        trackWidth = 120,
        min = 8,
        max = 30,
        step = 1,
        disabled = nameOnlyOff,
        disabledTooltip = "Make Friendly Nameplates Name Only",
        getValue = function() return DBVal("friendlyNameSize") or defaultSet.friendlyNameSize end,
        setValue = function(val)
            DB().friendlyNameSize = val
            if mod.RefreshFriendlyNameSize then mod.RefreshFriendlyNameSize() end
        end,
        tooltip = "Adjusts the size of friendly player names shown in Name Only mode. Default is 15.",
    })
    cursorY = cursorY - height

    -- Cog popup for NPC nameplate settings (Show NPC Titles)
    do
        local function npcOff() return DBVal("showFriendlyNPCs") ~= true end
        -- Every row here styles the name-only overlay, so the mode gate lives
        -- on the cog button; only the title rows need a gate of their own.
        local function npcCogOff() return npcOff() or nameOnlyOff() end
        local function titleOff() return DBVal("showNPCTitles") == false end
        -- The overlay's marker follows the Raid Marker element, as the friendly plates' does.
        local function markerOff() return (DBVal("raidMarkerPos") or defaultSet.raidMarkerPos) == "none" end

        local region = npcRow._leftRegion
        local button = CludesUI.BuildInlineCog(region, {
            chain = false,
            disabled = npcCogOff,
            disabledTooltip = function()
                return npcOff() and "Requires Show Friendly NPC Nameplates to be enabled"
                    or "Requires Name Only mode"
            end,
            rawTooltip = true,
            title = "Friendly NPC Settings",
            rows = {
                CludesUI.NameFormatCogRow(function() return DBVal("friendlyNPCNameFormat") end, function(val)
                    DB().friendlyNPCNameFormat = val
                    if mod.RefreshAllNPCOverlays then mod.RefreshAllNPCOverlays() end
                end),
                {
                    type = "toggle",
                    label = "Show NPC Titles",
                    get = function() return DBVal("showNPCTitles") ~= false end,
                    set = function(val)
                        DB().showNPCTitles = val and true or false
                        if mod.RefreshAllNPCOverlays then mod.RefreshAllNPCOverlays() end
                    end,
                },
                {
                    type = "toggle",
                    label = "Show Raid Marker",
                    get = function() return DBVal("showNPCRaidMarker") ~= false end,
                    set = function(val)
                        DB().showNPCRaidMarker = val and true or false
                        if mod.RefreshAllNPCOverlays then mod.RefreshAllNPCOverlays() end
                    end,
                    disabled = markerOff,
                    disabledTooltip = "Raid Marker",
                },
                {
                    type = "slider",
                    label = "Name Size",
                    min = 6,
                    max = 30,
                    step = 1,
                    get = function() return DBVal("friendlyNPCNameSize") or defaultSet.friendlyNPCNameSize end,
                    set = function(val)
                        DB().friendlyNPCNameSize = val
                        if mod.RefreshNPCOverlayStyle then mod.RefreshNPCOverlayStyle() end
                    end,
                },
                {
                    type = "slider",
                    label = "Title Size",
                    min = 6,
                    max = 30,
                    step = 1,
                    get = function() return DBVal("friendlyNPCTitleSize") or defaultSet.friendlyNPCTitleSize end,
                    set = function(val)
                        DB().friendlyNPCTitleSize = val
                        if mod.RefreshNPCOverlayStyle then mod.RefreshNPCOverlayStyle() end
                    end,
                    disabled = titleOff,
                    disabledTooltip = "Show NPC Titles",
                },
                {
                    type = "colorpicker",
                    label = "Name Color",
                    get = function()
                        local color = DBVal("friendlyNPCNameColor") or defaultSet.friendlyNPCNameColor
                        return color.r, color.g, color.b
                    end,
                    set = function(red, green, blue)
                        DB().friendlyNPCNameColor = { r = red, g = green, b = blue }
                        if mod.RefreshNPCOverlayStyle then mod.RefreshNPCOverlayStyle() end
                    end,
                },
                {
                    type = "colorpicker",
                    label = "Title Color",
                    hasAlpha = true,
                    get = function()
                        local color = DBVal("friendlyNPCTitleColor") or defaultSet.friendlyNPCTitleColor
                        return color.r, color.g, color.b, color.a or 1
                    end,
                    set = function(red, green, blue, a)
                        DB().friendlyNPCTitleColor = { r = red, g = green, b = blue, a = a or 1 }
                        if mod.RefreshNPCOverlayStyle then mod.RefreshNPCOverlayStyle() end
                    end,
                    disabled = titleOff,
                    disabledTooltip = "Show NPC Titles",
                },
            },
        })

        -- Inline swatch: friendly NPC bar & name color, full-plate mode only -- the exact complement of the cog beside it, which owns the name-only colors.
        local function npcColorOff() return npcOff() or friendlyPlateOff() end
        local npcSwatch, updateNpcSwatch
        local function refreshNpcSwatch()
            if updateNpcSwatch then updateNpcSwatch() end
            local off = npcColorOff()
            npcSwatch:SetAlpha(off and 0.3 or 1)
            npcSwatch:SetMouseClickEnabled(not off)
        end
        npcSwatch, updateNpcSwatch = CludesUI.BuildColorSwatch(region, region:GetFrameLevel() + 5, function()
            local color = DBVal("friendlyNPCColor") or defaultSet.friendlyNPCColor
            return color.r, color.g, color.b
        end, function(red, green, blue)
            DB().friendlyNPCColor = { r = red, g = green, b = blue }
            mod.RefreshFriendlyColors()
            refreshNpcSwatch()
        end, nil, 20)
        Pix.Point(npcSwatch, "RIGHT", button or region._control, "LEFT", -8, 0)
        region._lastInline = npcSwatch
        local origNpcClick = npcSwatch:GetScript("OnClick")
        npcSwatch:SetScript("OnClick", function(self, ...)
            if npcColorOff() then return end
            if origNpcClick then origNpcClick(self, ...) end
        end)
        npcSwatch:SetScript("OnEnter", function(self)
            if npcOff() then
                CludesUI.ShowWidgetTooltip(self, "Requires Show Friendly NPC Nameplates to be enabled")
            elseif DBVal("friendlyNameOnly") ~= false then
                CludesUI.ShowWidgetTooltip(self, "Requires Name Only mode to be disabled")
            else
                CludesUI.ShowWidgetTooltip(self, "NPC Bar & Name Color")
            end
        end)
        npcSwatch:SetScript("OnLeave", function() CludesUI.HideWidgetTooltip() end)
        CludesUI.RegisterWidgetRefresh(refreshNpcSwatch)
        refreshNpcSwatch()
    end

    _, height = W:DualRow(hostFrame, cursorY, {
        type = "toggle",
        text = "Friendly Names Not Clickable",
        tooltip = "Make friendly player and NPC nameplates click-through so their names never block your mouse or cause accidental friendly targeting.\n\nUse this when friendly names get in the way of clicking the world or the enemy nameplates behind them.",
        getValue = DBValIs("friendlyClickThrough"),
        setValue = function(val)
            DB().friendlyClickThrough = val
            if mod.UpdateFriendlyClickThrough then mod.UpdateFriendlyClickThrough() end
        end,
    }, {
        type = "toggle",
        text = "Show Enemy Pet Nameplates",
        getValue = DBValIs("showEnemyPets"),
        setValue = function(val)
            DB().showEnemyPets = val
            pcall(CludesUI.SetCVar, "nameplateShowEnemyPets", val and 1 or 0, "CludesUINameplates")
        end,
        tooltip = "Toggle visibility of enemy pet nameplates.",
    })
    cursorY = cursorY - height

    -- Inline DIRECTIONS cog on Friendly Name Size: name-only vertical distance
    if not CludesUI._prebuilding then
        CludesUI.BuildInlineCog(npcRow._rightRegion, {
            disabled = nameOnlyOff,
            title = "Name Distance",
            rows = {
                {
                    type = "slider",
                    label = "Distance",
                    min = -50,
                    max = 50,
                    step = 1,
                    get = function()
                        return DBVal("friendlyNameOnlyYOffset") or defaultSet.friendlyNameOnlyYOffset
                    end,
                    set = function(val)
                        DB().friendlyNameOnlyYOffset = val
                        if mod.RefreshFriendlyNameOnlyOffset then mod.RefreshFriendlyNameOnlyOffset() end
                    end,
                },
            },
        })
    end

    _, height = W:Spacer(hostFrame, cursorY, 20)
    cursorY = cursorY - height

    -----------------------------------------------------------------------
    --  ENEMY NAMEPLATE SPACING
    -----------------------------------------------------------------------
    _, height = W:SectionHeader(hostFrame, SECTION_ENEMY_NP, cursorY)
    cursorY = cursorY - height

    local stackingRow
    stackingRow, height = W:DualRow(hostFrame, cursorY, {
        type = "dropdown",
        text = "Stacking Nameplates",
        values = { __placeholder = "..." },
        order = { "__placeholder" },
        getValue = function() return "__placeholder" end,
        setValue = function() end,
    }, {
        type = "slider",
        text = "Stacked Nameplate Spacing",
        trackWidth = 130,
        min = 50,
        max = 200,
        step = 5,
        getValue = function() return DBVal("stackSpacingScale") or defaultSet.stackSpacingScale end,
        setValue = function(val)
            DB().stackSpacingScale = val
            mod.RefreshStackingBounds()
        end,
        tooltip = "Adjusts the vertical spacing between stacked nameplates. 100% = default, lower = tighter, higher = more spread.",
    })
    cursorY = cursorY - height

    -- Replace the placeholder dropdown with a multi-select checkbox dropdown; Enemy and Friendly stacking are independent toggles over the Midnight stacking bitfield. Friendly locks out while CUI isn't managing friendly plates (Blizzard owns that bit then).
    if not CludesUI._prebuilding then
        local leftRegion = stackingRow._leftRegion
        if leftRegion._control then leftRegion._control:Hide() end
        local stackItems = {
            { key = "enemy", label = "Enemy Nameplates" },
            {
                key = "friendly",
                label = "Friendly Nameplates",
                lockedFn = function() return DBVal("showFriendlyPlayers") == false end,
            },
        }
        local checkDrop, cbDDRefresh = CludesUI.BuildVisOptsCBDropdown(
            leftRegion,
            170,
            leftRegion:GetFrameLevel() + 2,
            stackItems,
            function(keyName)
                if keyName == "enemy" then return DBVal("stackingEnabled") ~= false end
                if keyName == "friendly" then return DBVal("stackingFriendly") == true end
                return false
            end,
            function(keyName, val)
                if keyName == "enemy" then
                    DB().stackingEnabled = val
                elseif keyName == "friendly" then
                    DB().stackingFriendly = val
                end
                mod.RefreshStackingMotion()
            end
        )
        Pix.Point(checkDrop, "RIGHT", leftRegion, "RIGHT", -20, 0)
        leftRegion._control = checkDrop
        checkDrop:HookScript(
            "OnEnter",
            function()
                CludesUI.ShowWidgetTooltip(
                    checkDrop,
                    "Choose which nameplates stack vertically instead of overlapping."
                )
            end
        )
        checkDrop:HookScript("OnLeave", function() CludesUI.HideWidgetTooltip() end)
        CludesUI.RegisterWidgetRefresh(cbDDRefresh)
    end

    local hitboxRow
    hitboxRow, height = W:DualRow(hostFrame, cursorY, {
        type = "slider",
        text = "Hitbox Size X",
        min = 50,
        max = 250,
        step = 5,
        getValue = function() return DBVal("hitboxScaleX") or defaultSet.hitboxScaleX end,
        setValue = function(val)
            DB().hitboxScaleX = val
            mod.RefreshHitboxSize()
        end,
        tooltip = "Widens the clickable hitbox of enemy nameplates. 100% = matches bar width. Increase to make nameplates easier to click.",
    }, {
        type = "slider",
        text = "Hitbox Size Y",
        min = 50,
        max = 250,
        step = 5,
        getValue = function() return DBVal("hitboxScaleY") or defaultSet.hitboxScaleY end,
        setValue = function(val)
            DB().hitboxScaleY = val
            mod.RefreshHitboxSize()
        end,
        tooltip = "Increases the clickable hitbox height of enemy nameplates. 100% = matches bar height. Increase to make nameplates easier to click.",
    })
    cursorY = cursorY - height

    -- Eyeball toggle on Hitbox Size X: translucent overlay on real enemy nameplates marking the clickable area, for visual slider tuning; runtime-only, auto-hides when the panel closes. None in the search pre-build: it indexes nothing, and the row is a stand-in there.
    if not CludesUI._prebuilding then
        local EYE_VISIBLE = CludesUI.EYE_VISIBLE_ICON
        local EYE_INVISIBLE = CludesUI.EYE_INVISIBLE_ICON
        local leftRegion = hitboxRow._leftRegion
        local eyeButton, eyeTex = CludesUI.NewInlineEye(leftRegion)
        local function RefreshEyeIcon()
            eyeTex:SetTexture(mod._hitboxOverlayShown and EYE_INVISIBLE or EYE_VISIBLE)
        end
        RefreshEyeIcon()
        eyeButton:SetScript("OnClick", function()
            if mod.SetHitboxOverlayShown then mod.SetHitboxOverlayShown(not mod._hitboxOverlayShown) end
            RefreshEyeIcon()
        end)
        eyeButton:SetScript("OnEnter", function(self)
            CludesUI.SetGlyphAlpha(self, 0.7)
            CludesUI.ShowWidgetTooltip(self, "Show/Hide Hitbox Overlay", { width = 175 })
        end)
        eyeButton:SetScript("OnLeave", function(self)
            CludesUI.SetGlyphAlpha(self, 0.4)
            CludesUI.HideWidgetTooltip()
        end)
        -- Auto-hide the overlay when the options panel closes (hook once).
        if not mod._hitboxOverlayCloseHook and CludesUI._mainFrame then
            mod._hitboxOverlayCloseHook = true
            CludesUI._mainFrame:HookScript("OnHide", function()
                if mod._hitboxOverlayShown and mod.SetHitboxOverlayShown then
                    mod.SetHitboxOverlayShown(false)
                end
            end)
        end
    end

    -- Stacking Speed | Top Screen Inset: CVars Blizzard restored in 12.1.5,
    -- so each slider exists only on a client that has its CVar. The client
    -- does not save either one across a game restart, so a slider keeps its
    -- value account-wide and the module writes it again at login
    -- (ns.KeepNameplateCVar); nothing is written until a slider moves. Speed
    -- reads as a percent of the client's own default; the inset as a percent
    -- of the screen's height (raw values if the client's default is not a
    -- fraction).
    do
        local function CVarDefault(name) return tonumber(C_CVar.GetCVarDefault(name)) end
        local cvarRows = {}
        if C_CVar.GetCVarInfo("nameplateMotionSpeed") then
            cvarRows[#cvarRows + 1] = {
                type = "slider",
                text = "Stacking Speed",
                min = 25,
                max = 400,
                step = 5,
                getValue = function()
                    local def, current =
                        CVarDefault("nameplateMotionSpeed"), tonumber(GetCVar("nameplateMotionSpeed"))
                    if not (def and def > 0 and current) then return 100 end
                    return math.floor(current / def * 100 + 0.5)
                end,
                setValue = function(val)
                    if InCombatLockdown() then return end
                    local def = CVarDefault("nameplateMotionSpeed")
                    if not (def and def > 0) then return end
                    mod.KeepNameplateCVar("nameplateMotionSpeed", def * val / 100)
                end,
                tooltip = "How fast stacked nameplates slide into place. 100% is Blizzard's default.",
            }
        end
        if C_CVar.GetCVarInfo("nameplateTopInset") then
            local def = CVarDefault("nameplateTopInset")
            local frac = not def or def <= 1
            cvarRows[#cvarRows + 1] = {
                type = "slider",
                text = "Top Screen Inset",
                min = 0,
                max = frac and 50 or math.max(100, math.ceil((def or 0) * 4)),
                step = 1,
                getValue = function()
                    local current = tonumber(GetCVar("nameplateTopInset")) or 0
                    if frac then return math.floor(current * 100 + 0.5) end
                    return current
                end,
                setValue = function(val)
                    if InCombatLockdown() then return end
                    mod.KeepNameplateCVar("nameplateTopInset", frac and val / 100 or val)
                end,
                tooltip = "How far from the top of the screen nameplates stop. 0 lets them reach the edge.",
            }
        end
        for idx = 1, #cvarRows, 2 do
            _, height =
                W:DualRow(hostFrame, cursorY, cvarRows[idx], cvarRows[idx + 1] or CludesUI.BlankRowCfg())
            cursorY = cursorY - height
        end
    end

    _, height = W:Spacer(hostFrame, cursorY, 20)
    cursorY = cursorY - height

    -----------------------------------------------------------------------
    --  EXTRA AURA OPTIONS
    -----------------------------------------------------------------------
    _, height = W:SectionHeader(hostFrame, SECTION_AURA, cursorY)
    cursorY = cursorY - height

    local maxDbfOriginal = DBVal("maxDebuffs") or defaultSet.maxDebuffs
    local maxDbfPendingPopup
    local maxDbfCfg = {
        type = "slider",
        text = "Max Debuffs",
        min = 1,
        max = 10,
        step = 1,
        getValue = function() return DBVal("maxDebuffs") or defaultSet.maxDebuffs end,
        setValue = function(val)
            DB().maxDebuffs = val
            -- 12.1 containers raise/lower the group's frame cap live via SetAuraGroupMaxFrameCount inside the reload's cfg pass.
            if mod.NPC_ReloadAll then
                mod.NPC_ReloadAll()
                return
            end
            -- Legacy pools are sized at plate creation: show the reload popup once after the slider drag ends (debounced).
            if val ~= maxDbfOriginal then
                if maxDbfPendingPopup then maxDbfPendingPopup:Cancel() end
                maxDbfPendingPopup = C_Timer.NewTimer(0.5, function()
                    maxDbfPendingPopup = nil
                    if (DB().maxDebuffs or defaultSet.maxDebuffs) ~= maxDbfOriginal then
                        CludesUI:ShowConfirmPopup({
                            title = "Reload Required",
                            message = "Changing Max Debuffs requires a UI reload to take effect.",
                            confirmText = "Reload Now",
                            cancelText = "Later",
                            reload = true,
                        })
                    end
                end)
            end
        end,
        tooltip = "Maximum number of debuff icons shown on enemy nameplates.",
    }
    local debuffRow1
    debuffRow1, height = W:DualRow(hostFrame, cursorY, maxDbfCfg, {
        type = "toggle",
        text = "Show Buff / Debuff Tooltips",
        tooltip = "Show the spell tooltip when you hover a buff or debuff icon on a nameplate.\n\nWhile the cursor is over an icon, the plate behind it will not highlight or take mouseover targeting.",
        getValue = DBValIs("showAuraTooltips"),
        setValue = function(val)
            DB().showAuraTooltips = val
            if mod.NPC_ReloadAll then mod.NPC_ReloadAll() end
        end,
    })
    cursorY = cursorY - height

    local GO = CludesUI.GlowOptions

    -- --- Pandemic Glow -------------------------------------------------
    -- Style with its color swatches and cog, the preview in the right half.
    local panDesc = npPandemicGlowDesc
    local panRow
    panRow, height = W:DualRow(
        hostFrame,
        cursorY,
        GO.DropdownSpec(
            panDesc,
            "Pandemic Glow Style",
            "Show a glow on your debuffs while they can be refreshed without losing any duration."
        ),
        { type = "label", text = "Pandemic Glow Preview" }
    )
    cursorY = cursorY - height
    GO.AttachInline(panRow._leftRegion, panDesc)

    if not CludesUI._prebuilding then
        -- A pandemic debuff of the player's class (Rip, Moonfire, Festering
        -- Wound, Vampiric Touch / Shadow Word: Pain, Agony, Rupture), any of
        -- them otherwise; the first the client knows from a random start.
        local BY_CLASS = {
            DRUID = { 1079, 8921 },
            DEATHKNIGHT = { 194310 },
            PRIEST = { 34914, 589 },
            WARLOCK = { 980 },
            ROGUE = { 1943 },
        }
        local pool = BY_CLASS[select(2, UnitClass("player"))] or { 1079, 8921, 194310, 34914, 980, 1943 }
        local icon = 136197
        local start = math.random(#pool)
        for idx = 0, #pool - 1 do
            local details = C_Spell.GetSpellInfo(pool[(start + idx - 1) % #pool + 1])
            if details and details.iconID then
                icon = details.iconID
                break
            end
        end
        local rightRegion = panRow._rightRegion
        GO.BuildPreview(
            rightRegion,
            panDesc,
            { anchor = rightRegion, point = "RIGHT", relPoint = "RIGHT", x = -20, icon = icon }
        )
        -- The preview's label dims with it while no glow is picked.
        local previewLabel = rightRegion._label
        local function DimPreviewLabel() previewLabel:SetAlpha(GO.Renders(panDesc) and 1 or 0.3) end
        CludesUI.RegisterWidgetRefresh(DimPreviewLabel)
        DimPreviewLabel()

        -- Apply to all: the CDM pandemic sync (only while that module is loaded).
        if CludesUI.ApplyPandemicGlowToAll then
            CludesUI.BuildSyncIcon({
                region = panRow._leftRegion,
                tooltip = "Apply this pandemic glow to all CDM bars and tracking bars. A surface that can't show a style uses its closest match.",
                isSynced = function()
                    return CludesUI.IsPandemicGlowSyncedToAll(
                        CludesUI.PandemicPayloadFromNameplate(DB()),
                        { skipNameplates = true }
                    )
                end,
                onClick = function()
                    CludesUI.ApplyPandemicGlowToAll(
                        CludesUI.PandemicPayloadFromNameplate(DB()),
                        { skipNameplates = true }
                    )
                    C_Timer.After(0, function() CludesUI:RefreshPage() end)
                end,
            })
        end
    end

    -- --- Dispellable Buff Glow ----------------------------------------
    local dispelDesc = npDispelGlowDesc
    local dispelGlowDropdown = GO.DropdownSpec(dispelDesc, "Dispel Glow Style")
    -- Enemy Buff Filter (replaces the retired Show All Enemy Buffs toggle;
    -- npEnemyBuffFilter, default "important", "showall" on WoW Forever; the
    -- old key is an inert orphan). UNION semantics: Important = important OR
    -- dispellable (two engine groups); Dispellable = dispellable only; Show
    -- All = every buff; the removed "all" value reads back as important.
    -- On retail, the cog's Dispellable By Me narrows "dispellable" in
    -- Important and Dispellable to the group's own dispels.
    -- The Dispel Glow never changes the filters -- it is just the style the
    -- dispellable group wears, so every shown dispellable buff glows when a
    -- style is set.
    local buffFilterDropdown = {
        type = "dropdown",
        text = "Enemy Buff Filter",
        tooltip = "Which enemy buffs show on nameplates. Important shows the buffs Blizzard flags for enemy nameplates plus anything dispellable; Only Dispellable shows just the buffs that can be dispelled, purged or soothed; Show All shows every buff. With a Dispel Glow style set, every dispellable buff shown glows.",
        values = { important = "Important", dispellable = "Only Dispellable", showall = "Show All" },
        order = { "important", "dispellable", "showall" },
        getValue = function()
            local m = DBVal("npEnemyBuffFilter")
            if m == "dispellable" or m == "showall" then return m end
            return "important"
        end,
        setValue = function(val)
            DB().npEnemyBuffFilter = val
            -- Applies live: RefreshAllAuras drives the container reload;
            -- its cfg pass re-drives both buff group filter strings and
            -- parks/unparks the plain remainder group.
            RefreshAllAuras()
            UpdatePreview()
            C_Timer.After(0, function() CludesUI:RefreshPage() end)
        end,
    }
    local dispelGlowRow
    dispelGlowRow, height = W:DualRow(hostFrame, cursorY, buffFilterDropdown, dispelGlowDropdown)
    cursorY = cursorY - height

    GO.AttachInline(dispelGlowRow._rightRegion, dispelDesc)

    -- "Dispellable By Me" (retail only, off by default): Important and Only Dispellable count only your group's dispels.
    if not CludesUI._prebuilding and not CludesUI.IS_FOREVER then
        CludesUI.BuildInlineCog(dispelGlowRow._leftRegion, {
            disabled = function() return DBVal("npEnemyBuffFilter") == "showall" end,
            disabledTooltip = "Requires Enemy Buff Filter set to Important or Only Dispellable",
            rawTooltip = true,
            title = "Enemy Buff Filter",
            rows = {
                {
                    type = "toggle",
                    label = "Dispellable By Me",
                    tooltip = "With Important or Only Dispellable, count only the buffs you or your group can dispel, purge or soothe as dispellable, instead of every dispellable buff.",
                    get = DBValIs("npEnemyBuffDispelByMe"),
                    set = function(val)
                        DB().npEnemyBuffDispelByMe = val or nil
                        RefreshAllAuras()
                        UpdatePreview()
                    end,
                },
            },
        })
    end

    _, height = W:Spacer(hostFrame, cursorY, 20)
    cursorY = cursorY - height

    -----------------------------------------------------------------------
    --  TARGET AND FOCUS EFFECTS
    -----------------------------------------------------------------------
    _, height = W:SectionHeader(hostFrame, "TARGET AND FOCUS EFFECTS", cursorY)
    cursorY = cursorY - height

    local function hashLineOff() return not (DBVal("hashLineEnabled")) end

    local row
    row, height = W:DualRow(hostFrame, cursorY, {
        type = "toggle",
        text = "Show Hash Line on Target at Percent",
        getValue = DBValOr("hashLineEnabled", false),
        setValue = function(val)
            DB().hashLineEnabled = val
            RefreshAllPlates()
            UpdatePreview()
            CludesUI:RefreshPage()
        end,
    }, {
        type = "slider",
        text = "Hash Line Location",
        min = 0,
        max = 100,
        step = 1,
        disabled = hashLineOff,
        disabledTooltip = "Show Hash Line on Target at Percent",
        getValue = function() return DBVal("hashLinePercent") or defaultSet.hashLinePercent end,
        setValue = function(val)
            DB().hashLinePercent = val
            RefreshAllPlates()
            UpdatePreview()
        end,
    })
    cursorY = cursorY - height

    -- Add "(Percent)" suffix in smaller, dimmer text next to the slider label
    if not CludesUI._prebuilding then
        local rightFrame = row._rightRegion
        if rightFrame then
            local suffixFS = rightFrame:CreateFontString(nil, "OVERLAY")
            suffixFS:SetFont(CludesUI.EXPRESSWAY, 11, GetNPOptOutline())
            suffixFS:SetTextColor(1, 1, 1, 0.35)
            local sliderLabel = SliderLabel(rightFrame, "Hash Line Location")
            if sliderLabel then
                suffixFS:SetPoint("LEFT", sliderLabel, "RIGHT", 5, -1)
            else
                suffixFS:SetPoint("LEFT", rightFrame, "LEFT", 180, -1)
            end
            suffixFS:SetText(CludesUI.L("(Percent)"))
            -- Gray out suffix when hash line is off
            CludesUI.RegisterWidgetRefresh(function() suffixFS:SetAlpha(hashLineOff() and 0.10 or 0.35) end)
            suffixFS:SetAlpha(hashLineOff() and 0.10 or 0.35)
        end
    end

    -- Inline color swatch for hash line custom color
    if not CludesUI._prebuilding then
        local hashColorGet = function()
            local color = (DB() and DB().hashLineColor) or defaultSet.hashLineColor
            return color.r, color.g, color.b
        end
        local hashColorSet = function(red, green, blue)
            DB().hashLineColor = { r = red, g = green, b = blue }
            RefreshAllPlates()
            UpdatePreview()
        end
        local leftRegion = row._leftRegion
        local colorSwatch, updateSwatch = CludesUI.BuildColorSwatch(
            leftRegion,
            leftRegion:GetFrameLevel() + 5,
            hashColorGet,
            hashColorSet,
            nil,
            20
        )
        Pix.Point(colorSwatch, "RIGHT", leftRegion._control, "LEFT", -12, 0)
        -- Gray out swatch when hash line is off
        CludesUI.RegisterWidgetRefresh(function()
            local off = hashLineOff()
            colorSwatch:SetAlpha(off and 0.15 or 1)
            colorSwatch:EnableMouse(not off)
            updateSwatch()
        end)
        colorSwatch:SetAlpha(hashLineOff() and 0.15 or 1)
        colorSwatch:EnableMouse(not hashLineOff())
    end

    -- Row 2: Scale Target Nameplate | Non-Target Opacity
    local tfScaleRow
    tfScaleRow, height = W:DualRow(hostFrame, cursorY, {
        type = "slider",
        text = "Scale Target Nameplate",
        trackWidth = 110,
        min = 50,
        max = 200,
        step = 5,
        getValue = function() return DBVal("targetScale") or defaultSet.targetScale end,
        setValue = function(val)
            DB().targetScale = val
            for _, backing in pairs(plates) do
                backing:ApplyScale()
            end
        end,
        tooltip = "Scales your current target's nameplate. 100% = no change.",
    }, {
        type = "slider",
        text = "Non-Target Opacity",
        tooltip = "Fades enemy nameplates that are not your current target or focus while you have a target. 100 = no fading.",
        min = 0,
        max = 100,
        step = 1,
        getValue = DBValOr("nonTargetAlpha", 100),
        setValue = function(val)
            DB().nonTargetAlpha = val
            if mod.NT_RefreshSetting then mod.NT_RefreshSetting() end
            CludesUI:RefreshPage() -- update the cog disabled state
        end,
    })
    cursorY = cursorY - height
    -- "(Percent)" suffix on the target scale slider
    if not CludesUI._prebuilding then
        local leftFrame = tfScaleRow._leftRegion
        if leftFrame then
            local suffixFS = leftFrame:CreateFontString(nil, "OVERLAY")
            suffixFS:SetFont(CludesUI.EXPRESSWAY, 11, GetNPOptOutline())
            suffixFS:SetTextColor(1, 1, 1, 0.35)
            local sliderLabel = SliderLabel(leftFrame, "Scale Target Nameplate")
            if sliderLabel then
                suffixFS:SetPoint("LEFT", sliderLabel, "RIGHT", 5, -1)
            else
                suffixFS:SetPoint("LEFT", leftFrame, "LEFT", 180, -1)
            end
            suffixFS:SetText(CludesUI.L("(Percent)"))
        end
    end
    -- Inline cog on Scale Target Nameplate: the enemy type scales.
    if not CludesUI._prebuilding then
        local function TypeScaleRow(labelText, key, tipText)
            return {
                type = "slider",
                label = labelText,
                tooltip = tipText,
                min = 25,
                max = 125,
                step = 5,
                get = function() return DBVal(key) or defaultSet[key] end,
                set = function(val)
                    DB()[key] = val
                    if mod.NP_RefreshTypeScaleSetting then mod.NP_RefreshTypeScaleSetting() end
                end,
            }
        end
        CludesUI.BuildInlineCog(tfScaleRow._leftRegion, {
            title = "Scale Target Nameplate",
            rows = {
                TypeScaleRow(
                    "Minor Enemy Scale (Percent)",
                    "minorEnemyScale",
                    "Scales the nameplates of minor and trivial enemies; 100% = no change."
                ),
                TypeScaleRow(
                    "Non-Elite Enemy Scale (Percent)",
                    "nonEliteEnemyScale",
                    "Scales the nameplates of non-elite enemies in dungeons only; 100% = no change."
                ),
            },
        })
    end
    -- Inline cog on Non-Target Opacity: the focus exemption, which Out of Combat
    -- Opacity (Extras) reads too, and the casting one.
    if not CludesUI._prebuilding then
        local function ntOff()
            return (DBVal("nonTargetAlpha") or 100) >= 100 and (DBVal("outOfCombatAlpha") or 100) >= 100
        end
        local region = tfScaleRow._rightRegion
        CludesUI.BuildInlineCog(region, {
            disabled = ntOff,
            disabledTooltip = "This option requires Non-Target Opacity or Out of Combat Opacity to be below 100",
            title = "Non-Target Opacity",
            rows = {
                {
                    type = "toggle",
                    label = "Keep Focus Full Opacity",
                    tooltip = "Your focus target's nameplate never fades with Non-Target Opacity or Out of Combat Opacity.",
                    get = function() return DBVal("nonTargetKeepFocus") ~= false end,
                    set = function(val)
                        DB().nonTargetKeepFocus = val
                        if mod.NT_RefreshSetting then mod.NT_RefreshSetting() end
                    end,
                },
                -- One dropdown over nonTargetCastFull + nonTargetCastImportantOnly.
                {
                    type = "dropdown",
                    label = "Full Opacity While Casting",
                    values = { off = "Off", all = "All Casts", important = "Important Casts" },
                    order = { "off", "all", "important" },
                    tooltip = "A casting enemy's nameplate skips Non-Target Opacity while the cast lasts.",
                    disabled = function() return (DBVal("nonTargetAlpha") or 100) >= 100 end,
                    disabledTooltip = "Non-Target Opacity below 100",
                    get = function()
                        if DBVal("nonTargetCastFull") ~= true then return "off" end
                        return DBVal("nonTargetCastImportantOnly") == true and "important" or "all"
                    end,
                    set = function(val)
                        DB().nonTargetCastFull = val ~= "off"
                        DB().nonTargetCastImportantOnly = val == "important"
                        if mod.NT_RefreshSetting then mod.NT_RefreshSetting() end
                    end,
                },
            },
        })
    end

    -- Row 3: Focus Cast Height | Focus Letter
    local focusLetterOff = function() return DBVal("focusLetterEnabled") ~= true end
    local tfFocusRow
    tfFocusRow, height = W:DualRow(hostFrame, cursorY, {
        type = "slider",
        text = "Focus Cast Height",
        trackWidth = 110,
        min = 100,
        max = 200,
        step = 5,
        getValue = function() return DBVal("focusCastHeight") or defaultSet.focusCastHeight end,
        setValue = function(val)
            DB().focusCastHeight = val
            mod.RefreshAllSettings()
        end,
        tooltip = "Increases the cast bar height on your focus target's nameplate. 100% = normal height.",
    }, {
        type = "toggle",
        text = "Focus Letter",
        tooltip = "Draws a white letter F on your current focus target's nameplate.",
        getValue = DBValIs("focusLetterEnabled"),
        setValue = function(val)
            DB().focusLetterEnabled = val
            RefreshAllPlates()
            CludesUI:RefreshPage()
        end,
    })
    cursorY = cursorY - height
    -- "(Percent)" suffix on Focus Cast Height
    if not CludesUI._prebuilding then
        local leftFrame = tfFocusRow._leftRegion
        if leftFrame then
            local suffixFS = leftFrame:CreateFontString(nil, "OVERLAY")
            suffixFS:SetFont(CludesUI.EXPRESSWAY, 11, GetNPOptOutline())
            suffixFS:SetTextColor(1, 1, 1, 0.35)
            local sliderLabel = SliderLabel(leftFrame, "Focus Cast Height")
            if sliderLabel then
                suffixFS:SetPoint("LEFT", sliderLabel, "RIGHT", 5, -1)
            else
                suffixFS:SetPoint("LEFT", leftFrame, "LEFT", 180, -1)
            end
            suffixFS:SetText(CludesUI.L("(Percent)"))
        end
    end

    if not CludesUI._prebuilding then
        local region = tfFocusRow._rightRegion
        CludesUI.BuildInlineCog(region, {
            disabled = focusLetterOff,
            disabledTooltip = "Focus Letter",
            title = "Focus Letter",
            rows = {
                {
                    type = "dropdown",
                    label = "Anchor",
                    values = FOCUS_LETTER_ANCHORS,
                    order = FOCUS_LETTER_ANCHOR_ORDER,
                    get = GetFocusLetterAnchor,
                    set = function(val)
                        DB().focusLetterAnchor = val
                        RefreshAllPlates()
                    end,
                },
                {
                    type = "slider",
                    label = "Size",
                    min = 6,
                    max = 40,
                    step = 1,
                    get = function() return DBVal("focusLetterSize") or defaultSet.focusLetterSize end,
                    set = function(val)
                        DB().focusLetterSize = val
                        RefreshAllPlates()
                    end,
                },
                {
                    type = "slider",
                    label = "X",
                    min = -100,
                    max = 100,
                    step = 1,
                    get = function() return DBVal("focusLetterX") or defaultSet.focusLetterX end,
                    set = function(val)
                        DB().focusLetterX = val
                        RefreshAllPlates()
                    end,
                },
                {
                    type = "slider",
                    label = "Y",
                    min = -100,
                    max = 100,
                    step = 1,
                    get = function() return DBVal("focusLetterY") or defaultSet.focusLetterY end,
                    set = function(val)
                        DB().focusLetterY = val
                        RefreshAllPlates()
                    end,
                },
            },
        })
    end

    -- Row 4: Distance to Target Text
    local tfRangeOff = function() return DBVal("rangeTextEnabled") ~= true end
    local tfRangeRow
    tfRangeRow, height = W:DualRow(hostFrame, cursorY, {
        type = "toggle",
        text = "Distance to Target Text (Range)",
        tooltip = "Shows the approximate distance to your current target on its nameplate as a range bracket, e.g. 15+ when the target is 15-20 yards away.",
        getValue = DBValIs("rangeTextEnabled"),
        setValue = function(val)
            DB().rangeTextEnabled = val
            if mod.RangeText_Apply then mod.RangeText_Apply() end
            CludesUI:RefreshPage()
        end,
    }, { type = "label", text = "" })
    cursorY = cursorY - height
    -- RESIZE cog: text size + X/Y offsets (mirrors the raid-marker cog), beside the toggle
    if not CludesUI._prebuilding then
        local region = tfRangeRow._leftRegion
        CludesUI.BuildInlineCog(region, {
            disabled = tfRangeOff,
            disabledTooltip = "Distance to Target Text (Range)",
            title = "Distance Text",
            rows = {
                {
                    type = "slider",
                    label = "Text Size",
                    min = 6,
                    max = 32,
                    step = 1,
                    get = function() return DBVal("rangeTextSize") or defaultSet.rangeTextSize end,
                    set = function(val)
                        DB().rangeTextSize = val
                        if mod.RangeText_Refresh then mod.RangeText_Refresh() end
                    end,
                },
                {
                    type = "slider",
                    label = "Offset X",
                    min = -200,
                    max = 200,
                    step = 1,
                    get = DBValOr("rangeTextOffsetX", 0),
                    set = function(val)
                        DB().rangeTextOffsetX = val
                        if mod.RangeText_Refresh then mod.RangeText_Refresh() end
                    end,
                },
                {
                    type = "slider",
                    label = "Offset Y",
                    min = -200,
                    max = 200,
                    step = 1,
                    get = DBValOr("rangeTextOffsetY", 0),
                    set = function(val)
                        DB().rangeTextOffsetY = val
                        if mod.RangeText_Refresh then mod.RangeText_Refresh() end
                    end,
                },
            },
        })
    end
    -- Inline color swatch (default light orange), left of the cog
    if not CludesUI._prebuilding then
        local region = tfRangeRow._leftRegion
        local rangeColorGet = function()
            local color = (DB() and DB().rangeTextColor) or defaultSet.rangeTextColor
            return color.r, color.g, color.b
        end
        local rangeColorSet = function(red, green, blue)
            DB().rangeTextColor = { r = red, g = green, b = blue }
            if mod.RangeText_Refresh then mod.RangeText_Refresh() end
        end
        local colorSwatch, updateSwatch = CludesUI.BuildColorSwatch(
            region,
            region:GetFrameLevel() + 5,
            rangeColorGet,
            rangeColorSet,
            nil,
            20
        )
        Pix.Point(colorSwatch, "RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
        region._lastInline = colorSwatch
        CludesUI.RegisterWidgetRefresh(function()
            local off = tfRangeOff()
            colorSwatch:SetAlpha(off and 0.15 or 1)
            colorSwatch:EnableMouse(not off)
            updateSwatch()
        end)
        colorSwatch:SetAlpha(tfRangeOff() and 0.15 or 1)
        colorSwatch:EnableMouse(not tfRangeOff())
    end

    _, height = W:Spacer(hostFrame, cursorY, 20)
    cursorY = cursorY - height

    -----------------------------------------------------------------------
    --  EXTRAS
    -----------------------------------------------------------------------
    _, height = W:SectionHeader(hostFrame, SECTION_MISC, cursorY)
    cursorY = cursorY - height

    -- Row 1: Scale Nameplate on Cast | Hide Enemy Name While Casting
    local exCastRow
    exCastRow, height = W:DualRow(hostFrame, cursorY, {
        type = "slider",
        text = "Scale Nameplate On Cast",
        trackWidth = 110,
        min = 50,
        max = 200,
        step = 5,
        getValue = function() return DBVal("castScale") or defaultSet.castScale end,
        setValue = function(val) DB().castScale = val end,
        tooltip = "Scales enemy nameplates while they are casting. 100% = no change.",
    }, {
        type = "toggle",
        text = "Hide Enemy Name While Casting",
        tooltip = "Hide the enemy name text while that nameplate's cast bar is visible.",
        getValue = DBValIs("hideEnemyNameWhileCasting"),
        setValue = function(val)
            DB().hideEnemyNameWhileCasting = val
            mod.RefreshAllSettings()
            UpdatePreview()
        end,
    })
    cursorY = cursorY - height
    -- "(Percent)" suffix on the cast scale slider
    if not CludesUI._prebuilding then
        local leftFrame = exCastRow._leftRegion
        if leftFrame then
            local suffixFS = leftFrame:CreateFontString(nil, "OVERLAY")
            suffixFS:SetFont(CludesUI.EXPRESSWAY, 11, GetNPOptOutline())
            suffixFS:SetTextColor(1, 1, 1, 0.35)
            local sliderLabel = SliderLabel(leftFrame, "Scale Nameplate On Cast")
            if sliderLabel then
                suffixFS:SetPoint("LEFT", sliderLabel, "RIGHT", 5, -1)
            else
                suffixFS:SetPoint("LEFT", leftFrame, "LEFT", 180, -1)
            end
            suffixFS:SetText(CludesUI.L("(Percent)"))
        end
    end

    -- Row 2: Name Raid Marker (target marker shown directly before the enemy name; size lives on inline cog) | Experimental: Cast Lockout as CC Icon.
    local nameRaidMarkerRow
    nameRaidMarkerRow, height = W:DualRow(hostFrame, cursorY, {
        type = "toggle",
        text = "Name Raid Marker",
        tooltip = "Shows the target marker directly before the enemy name text. Uses its own size and does not use the Core Positions raid marker slot.",
        getValue = DBValIs("nameRaidMarkerEnabled"),
        setValue = function(val)
            DB().nameRaidMarkerEnabled = val
            mod.RefreshAllSettings()
            UpdatePreview()
            CludesUI:RefreshPage()
        end,
    }, {
        type = "toggle",
        text = "Experimental: Cast Lockout as CC Icon",
        tooltip = "Show successful interrupt lockouts in the crowd-control icon slot.\n\nDue to addon restrictions, the duration shown is a generic 4 seconds for all classes, so it is not 100% accurate.",
        getValue = DBValIs("showCastLockoutAsCrowdControl"),
        setValue = function(val)
            DB().showCastLockoutAsCrowdControl = val
            RefreshAllAuras()
        end,
    })
    cursorY = cursorY - height

    if not CludesUI._prebuilding then
        local function nameRaidMarkerOff() return DBVal("nameRaidMarkerEnabled") ~= true end
        local region = nameRaidMarkerRow._leftRegion
        CludesUI.BuildInlineCog(region, {
            disabled = nameRaidMarkerOff,
            disabledTooltip = "Name Raid Marker",
            title = "Name Raid Marker",
            rows = {
                {
                    type = "slider",
                    label = "Size",
                    min = 6,
                    max = 32,
                    step = 1,
                    get = function() return DBVal("nameRaidMarkerSize") or defaultSet.nameRaidMarkerSize end,
                    set = function(val)
                        DB().nameRaidMarkerSize = val
                        mod.RefreshAllSettings()
                        UpdatePreview()
                    end,
                },
            },
        })
    end

    -- Row 3: Out of Combat Opacity | Line of Sight Opacity
    _, height = W:DualRow(
        hostFrame,
        cursorY,
        {
            type = "slider",
            text = "Out of Combat Opacity",
            tooltip = "Fades the nameplates of enemies that are not in combat with anyone, such as packs you have not pulled. Your target, and your focus while Keep Focus Full Opacity is on, are never faded by this. Multiplies with Non-Target Opacity. 100 = no fading.",
            min = 0,
            max = 100,
            step = 1,
            getValue = DBValOr("outOfCombatAlpha", 100),
            setValue = function(val)
                DB().outOfCombatAlpha = val
                if mod.NT_RefreshSetting then mod.NT_RefreshSetting() end
                CludesUI:RefreshPage() -- the Keep Focus cog's disabled state
            end,
        },
        -- Line of Sight Opacity: pure CVar passthrough (like Lag Tolerance). Nothing stored in our DB -- getValue reflects the live CVar, setValue only writes on slider move; combat-guarded, mirrors SetCVarSafe.
        {
            type = "slider",
            text = "Line of Sight Opacity",
            tooltip = "Nameplates opacity for units that are out of line of sight. 0 = fully transparent, 1 = fully opaque.",
            min = 0,
            max = 1,
            step = 0.01,
            getValue = function() return tonumber(GetCVar("nameplateOccludedAlphaMult")) or 0 end,
            setValue = function(val)
                if InCombatLockdown() then return end
                CludesUI.SetCVar("nameplateOccludedAlphaMult", val, "CludesUINameplates")
            end,
        }
    )
    cursorY = cursorY - height

    -- Row 4: Range Check (custom cutoff in the inline cog) | Out of Range Opacity
    local rangeCheckRow
    rangeCheckRow, height = W:DualRow(hostFrame, cursorY, {
        type = "dropdown",
        text = "Range Check",
        values = { disabled = "Disabled", auto = "Auto (Class/Spec)", custom = "Custom" },
        order = { "disabled", "auto", "custom" },
        tooltip = "Disabled runs no nameplate range checks. Auto uses your class and specialization's normal attack range. Custom uses the range set in the cog beside this option.",
        getValue = function() return DBVal("outOfRangeMode") or defaultSet.outOfRangeMode end,
        setValue = function(val)
            local prev = DBVal("outOfRangeMode") or defaultSet.outOfRangeMode
            local function ApplyMode(mode)
                DB().outOfRangeMode = mode
                if mode == "custom" and DB().outOfRangeCustomRange == nil then
                    DB().outOfRangeCustomRange = CludesUI.Range_GetAttackCutoff()
                end
                if mod.RangeText_Apply then mod.RangeText_Apply() end
                CludesUI:RefreshPage()
            end
            -- Performance confirm on the disabled -> enabled edge only:
            -- the sweep range-checks every visible nameplate continuously.
            if prev == "disabled" and val ~= "disabled" then
                CludesUI:ShowConfirmPopup({
                    title = "Out of Range Opacity",
                    message = "This feature runs continuous range checks against every visible enemy nameplate. It is one of the more expensive features in CludesUI and can measurably increase CPU usage in crowded areas.",
                    confirmText = "Enable",
                    cancelText = "Cancel",
                    onConfirm = function() ApplyMode(val) end,
                    onCancel = function() CludesUI:RefreshPage() end,
                })
                return
            end
            ApplyMode(val)
        end,
    }, {
        type = "slider",
        text = "Out of Range Opacity",
        tooltip = "Opacity used for enemy nameplates outside the selected attack range.",
        min = 0,
        max = 100,
        step = 1,
        disabled = function() return (DBVal("outOfRangeMode") or defaultSet.outOfRangeMode) == "disabled" end,
        disabledTooltip = "Range Check: Auto or Custom",
        getValue = function() return DBVal("outOfRangeAlpha") or defaultSet.outOfRangeAlpha end,
        setValue = function(val)
            DB().outOfRangeAlpha = val
            if mod.RangeText_Apply then mod.RangeText_Apply() end
        end,
    })
    cursorY = cursorY - height

    -- Inline cog on Range Check: the custom cutoff lives here.
    if not CludesUI._prebuilding then
        local function customOff() return (DBVal("outOfRangeMode") or defaultSet.outOfRangeMode) ~= "custom" end
        local region = rangeCheckRow._leftRegion
        CludesUI.BuildInlineCog(region, {
            disabled = customOff,
            disabledTooltip = "Range Check: Custom",
            title = "Range Check",
            rows = {
                {
                    type = "slider",
                    label = "Custom Range",
                    min = 5,
                    max = 50,
                    step = 5,
                    tooltip = "Attack-range cutoff used by Out of Range Opacity. Five-yard steps match the available fallback range checks.",
                    disabled = customOff,
                    disabledTooltip = "Range Check: Custom",
                    get = function()
                        return DBVal("outOfRangeCustomRange") or CludesUI.Range_GetAttackCutoff()
                    end,
                    set = function(val)
                        DB().outOfRangeCustomRange = val
                        if mod.RangeText_Apply then mod.RangeText_Apply() end
                    end,
                },
            },
        })
    end

    -- Row 5: Execute Pulse Glow | Hide Enemy Nameplates out of Combat
    _, height = W:DualRow(hostFrame, cursorY, {
        type = "toggle",
        text = "Execute Pulse Glow",
        tooltip = "Pulses a red glow on enemy nameplates below 30% health.",
        getValue = DBValIs("lowHpGlow"),
        setValue = function(val)
            DB().lowHpGlow = val
            mod.RefreshAllSettings()
        end,
    }, {
        type = "toggle",
        text = "Hide Enemy Nameplates out of Combat",
        tooltip = "Hide enemy nameplates while you are out of combat; they return the moment combat starts. Drives the same game setting as the Show Enemy Name Plates keybind.",
        getValue = DBValIs("hideEnemyPlatesOOC"),
        setValue = function(val)
            DB().hideEnemyPlatesOOC = val
            if mod.ApplyOOCPlates then mod.ApplyOOCPlates() end
        end,
    })
    cursorY = cursorY - height

    -- Row 6: the class option, if any, built only when there is one. Hide Copies
    -- of Blood Plague (Blood Death Knight only) and Show Sunder Armor (WoW Forever
    -- warriors only) are not built at all for anyone else -- each only affects
    -- that class's debuff.
    local classCfg
    do
        local _, class = UnitClass("player")
        local specIdx = C_SpecializationInfo.GetSpecialization()
        local specID = specIdx and C_SpecializationInfo.GetSpecializationInfo(specIdx)
        if class == "DEATHKNIGHT" and specID == 250 then
            classCfg = {
                type = "toggle",
                text = "Hide Copies of Blood Plague",
                tooltip = "Shows a single Blood Plague debuff on enemy nameplates instead of one per copy (Blood Boil from weapon copies).",
                getValue = function() return DBVal("hideBloodPlagueCopies") ~= false end,
                setValue = function(val)
                    DB().hideBloodPlagueCopies = val
                    if mod.NPC_ReloadAll then mod.NPC_ReloadAll() end
                end,
            }
        elseif CludesUI.IS_FOREVER and class == "WARRIOR" then
            classCfg = {
                type = "toggle",
                text = "Show Sunder Armor",
                tooltip = "Shows Sunder Armor and its stacks on enemy nameplates, including stacks applied by other warriors.",
                getValue = DBValIs("showSunderArmor"),
                setValue = function(val)
                    DB().showSunderArmor = val
                    if mod.NPC_ReloadAll then mod.NPC_ReloadAll() end
                end,
            }
        end
    end
    if classCfg then
        _, height = W:DualRow(hostFrame, cursorY, classCfg, CludesUI.BlankRowCfg())
        cursorY = cursorY - height
    end

    return math.abs(cursorY)
end

-- Used by CUI_Nameplates_Options.lua
mod.NPO_BuildGeneralPage = BuildGeneralPage
