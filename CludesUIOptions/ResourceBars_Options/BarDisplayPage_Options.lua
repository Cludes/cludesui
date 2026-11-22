if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  ResourceBars_Options\BarDisplayPage_Options.lua
--  Resource Bars options: Class, Power and Health Bars page. Definitions only; the shared
--  helpers come from ns._CURB_OptEnv (filled by CUI_ResourceBars_Options.lua).
-------------------------------------------------------------------------------
local mod = CludesUI._ModuleNS["CludesUIResourceBars"]
if not mod then return end -- module disabled: no options page
local CreateFrame = CludesUI._Pool.CreateFrame

-- Bar Display page
function mod.ERB_BuildBarDisplayPage(page, hostFrame, yOffset)
    local environ = mod._CURB_OptEnv
    local DB, Pix, Refresh, GentleRefresh = environ.DB, environ.PP, environ.Refresh, environ.SmoothRefresh
    local TexBgRowCfg = environ.TexBgRowCfg
    local RebuildClass, RebuildPower, RebuildHealth, _clickMappings =
        environ.RebuildClass, environ.RebuildPower, environ.RebuildHealth, environ._clickMappings
    local _previewHeaderBuilder, CLASSIC_SYNC_KEYS, CLASSIC_MATCH_KEYS =
        environ._previewHeaderBuilder, environ.CLASSIC_SYNC_KEYS, environ.CLASSIC_MATCH_KEYS
    local W = CludesUI.Widgets
    local cursorY = yOffset
    local _, height

    hostFrame._showRowDivider = true

    -- Shared row references for sync icon flashTargets, filled per section
    local _syncRows = {}

    -- Preview eye beside a section title: shows or hides that bar in the
    -- preview header. Session state only (ns._erbPvHidden), so every bar
    -- starts shown. Open eye = shown; a bar that cannot show (off, none for
    -- this spec) gets a dimmed crossed eye whose tooltip names what it needs.
    -- UpdatePreviewHeader re-reads every eye (ns._erbPvEyes): not every flip
    -- that blocks a bar rebuilds the page. `after`: the title's Move in Unlock
    -- Mode button, which the eye then follows instead of the title itself.
    mod._erbPvHidden = mod._erbPvHidden or {}
    if not CludesUI._prebuilding then mod._erbPvEyes = {} end
    local function AddPreviewEye(heading, labelText, settingKey, after)
        if CludesUI._prebuilding or not heading then return end
        local hidden = mod._erbPvHidden
        local labelFS
        for _, region in ipairs({ heading:GetRegions() }) do
            if region.GetText and CludesUI.EnKey(region:GetText()) == labelText then
                labelFS = region
                break
            end
        end
        local eyeButton = CreateFrame("Button", nil, heading)
        Pix.Size(eyeButton, 24, 24)
        if after then
            Pix.Point(eyeButton, "LEFT", after, "RIGHT", 4, 0)
        elseif labelFS then
            Pix.Point(eyeButton, "LEFT", labelFS, "RIGHT", 5, 0)
        else
            Pix.Point(eyeButton, "LEFT", heading, "BOTTOMLEFT", 85, 8)
        end
        eyeButton:SetFrameLevel(heading:GetFrameLevel() + 5)
        local eyeTex = eyeButton:CreateTexture(nil, "OVERLAY")
        eyeTex:SetAllPoints()
        local function Blocked()
            local profile = DB()
            return profile and environ.PreviewAvail(profile, settingKey) or nil
        end
        -- A button the pool dressed again since (another page) is not this eye any more.
        local gen = CludesUI._Pool.Gen(eyeButton)
        local function RefreshEye()
            if CludesUI._Pool.Gen(eyeButton) ~= gen then return end
            local isBlocked = Blocked()
            local isShown = not isBlocked and not hidden[settingKey]
            -- The art is named the other way round: EYE_INVISIBLE_ICON is the open eye.
            eyeTex:SetTexture(isShown and CludesUI.EYE_INVISIBLE_ICON or CludesUI.EYE_VISIBLE_ICON)
            CludesUI.SetGlyphAlpha(eyeButton, isBlocked and 0.15 or 0.4)
        end
        mod._erbPvEyes[settingKey] = RefreshEye
        RefreshEye()
        eyeButton:SetScript("OnClick", function()
            if Blocked() then return end
            hidden[settingKey] = not hidden[settingKey] or nil
            environ.UpdatePreviewHeader()
        end)
        eyeButton:SetScript("OnEnter", function(self)
            local isBlocked = Blocked()
            if isBlocked then
                CludesUI.ShowWidgetTooltip(self, isBlocked)
                return
            end
            CludesUI.SetGlyphAlpha(self, 0.7)
            CludesUI.ShowWidgetTooltip(
                self,
                hidden[settingKey] and CludesUI.L("Show in preview") or CludesUI.L("Hide in preview")
            )
        end)
        eyeButton:SetScript("OnLeave", function()
            RefreshEye()
            CludesUI.HideWidgetTooltip()
        end)
    end

    -- Bar texture dropdown values from the _ERB globals. SharedMedia is re-appended here because options open later than init, so SM packs that register textures lazily are available by now.
    CludesUI.AppendSharedMediaTextures(
        _G._CURB_BarTextureNames or {},
        _G._CURB_BarTextureOrder or {},
        nil,
        _G._CURB_BarTextures
    )
    local hbtValues = {}
    local hbtOrder = {}
    do
        local texNames = _G._CURB_BarTextureNames or {}
        local texOrder2 = _G._CURB_BarTextureOrder or {}
        local texLookup = _G._CURB_BarTextures or {}
        for _, settingKey in ipairs(texOrder2) do
            if settingKey ~= "---" then hbtValues[settingKey] = texNames[settingKey] or settingKey end
            hbtOrder[#hbtOrder + 1] = settingKey
        end
        hbtValues._menuOpts = {
            itemHeight = 28,
            background = function(settingKey) return texLookup[settingKey] end,
        }
    end
    -- Own values/order copy per extra texture dropdown (the Texture cog's per-bar
    -- rows), so no two dropdowns share one table pair.
    local function CopyTexDD()
        local value, o = {}, {}
        for keyName, name in pairs(hbtValues) do
            value[keyName] = name
        end
        for idx = 1, #hbtOrder do
            o[idx] = hbtOrder[idx]
        end
        return value, o
    end

    -- Randomize the preview fill on every visit to this page
    local minPips = math.floor(5 * 0.50 + 0.5)
    local maxPips = math.floor(5 * 0.75 + 0.5)
    environ.SetDisplayPreviewValues(math.random(minPips, maxPips), math.random(30, 80))

    CludesUI:SetContentHeader(_previewHeaderBuilder)

    -- _clickMappings is ONE module-shared table read by the LIVE preview headers' clicks: this page
    -- clears only its own keys (the Cast Bar page's cached preview keeps its own), and a hidden
    -- search pre-build clears nothing.
    if not CludesUI._prebuilding then
        _clickMappings.classResource, _clickMappings.countText = nil, nil
        _clickMappings.power, _clickMappings.health = nil, nil
        _clickMappings.arcaneSoul = nil
    end

    -- Per-spec editing lives in the shared Spec Overrides system (spec groups + editing-as); legacy Advanced data migrates via MigrateRBAdvancedProfile.

    local generalSection
    generalSection, height = W:SectionHeader(hostFrame, "BAR DISPLAY", cursorY)
    cursorY = cursorY - height

    -- Row 1: Visibility | Visibility Options. One control drives all three bars: the scalar and the multi-select set write to health/primary/secondary in lockstep; reads come from secondary, the representative.
    local function ApplyVisScalarAll(_, modeName)
        local profile = DB()
        if not profile then return end
        profile.secondary.visibility = modeName
        profile.health.visibility = modeName
        profile.primary.visibility = modeName
    end
    local function MirrorVisModes()
        local profile = DB()
        if not profile then return end
        local source = profile.secondary.visibilityModes
        if source then
            local c1, c2 = {}, {}
            for keyName in pairs(source) do
                c1[keyName] = true
                c2[keyName] = true
            end
            profile.health.visibilityModes = c1
            profile.primary.visibilityModes = c2
        else
            profile.health.visibilityModes = nil
            profile.primary.visibilityModes = nil
        end
    end
    -- One control for all three bars: the scalar, the multi-select set and the option
    -- booleans all fan out to health/primary/secondary; reads come from secondary,
    -- the representative.
    local visRow
    visRow, height = CludesUI.BuildVisibilityRow(
        W,
        hostFrame,
        cursorY,
        {
            getStore = function()
                local profile = DB()
                return profile and profile.secondary
            end,
            -- The override marker fans out like the scalar and the option lanes do;
            -- secondary leads, matching getStore above.
            getStores = function()
                local profile = DB()
                if not profile then return nil end
                -- Built by presence, never as a literal triple: a nil in the middle
                -- would leave a hole the # operator reads past.
                local result = {}
                if profile.secondary then result[#result + 1] = profile.secondary end
                if profile.health then result[#result + 1] = profile.health end
                if profile.primary then result[#result + 1] = profile.primary end
                return result
            end,
            legacyKey = "visibility",
            caps = { partyIncludesRaid = false, luaDragonriding = true },
            applyScalarFn = ApplyVisScalarAll,
            getOption = function(keyName)
                local profile = DB()
                if not profile then return false end
                return profile.secondary[keyName] or false
            end,
            setOption = function(keyName, value)
                local profile = DB()
                if not profile then return end
                profile.secondary[keyName] = value
                profile.health[keyName] = value
                profile.primary[keyName] = value
            end,
            onChanged = function()
                MirrorVisModes()
                Refresh()
            end,
            onOptionChanged = function() Refresh() end,
        },
        -- Smooth Bars: placeholder slot, swapped for the checkbox dropdown below.
        {
            type = "dropdown",
            text = "Smooth Bars",
            values = { __placeholder = "..." },
            order = { "__placeholder" },
            getValue = function() return "__placeholder" end,
            setValue = function() end,
        }
    )
    cursorY = cursorY - height

    -- Smooth Bars checkbox dropdown. Each item enables native StatusBar interpolation
    -- on its bar; off = a plain SetValue with zero added cost. Defaults all off.
    if not CludesUI._prebuilding then
        local rightRegion = visRow._rightRegion
        if rightRegion._control then rightRegion._control:Hide() end
        local smoothItems = {
            { key = "secondary", label = "Class Resource Bar" },
            { key = "primary", label = "Power Bar" },
            { key = "health", label = "Health Bar" },
        }
        local checkDrop, cbDDRefresh = CludesUI.BuildVisOptsCBDropdown(
            rightRegion,
            210,
            rightRegion:GetFrameLevel() + 2,
            smoothItems,
            function(keyName)
                local profile = DB()
                if not profile then return false end
                return (profile[keyName] and profile[keyName].smoothBars) or false
            end,
            function(keyName, value)
                local profile = DB()
                if not profile then return end
                if profile[keyName] then profile[keyName].smoothBars = value end
                if _G._CURB_ApplySmoothing then _G._CURB_ApplySmoothing() end
            end
        )
        Pix.Point(checkDrop, "RIGHT", rightRegion, "RIGHT", -20, 0)
        rightRegion._control = checkDrop
        rightRegion._lastInline = nil
        CludesUI.RegisterWidgetRefresh(cbDDRefresh)
    end

    -- Row 2: Dark Mode Class Resource | Background Color. Dark mode applies ONLY to the class
    -- resource bar (secondary), using the same flat dark fill/bg as Unit Frames / Raid Frames;
    -- secondary.darkTheme is the single source of truth, health/primary are never darkened.
    -- Background is shared by Health & Power, plus the class resource bar while Dark Mode is off
    -- (the label says so). With splitBg on (the cog's "Choose background per bar") the
    -- per-bar rows below own Health & Power and this row narrows to the class resource bar; it
    -- stays live in every case, never disabled.
    local backgroundLabel = "Background"
    do
        local profile = DB()
        if profile and profile.splitBg == true then
            backgroundLabel = "Background (Class Resource)"
        elseif profile and profile.secondary.darkTheme then
            backgroundLabel = "Background (Health & Power)"
        end
    end
    local bgRow
    bgRow, height = W:DualRow(hostFrame, cursorY, {
        type = "toggle",
        text = "Dark Mode Class Resource",
        getValue = function()
            local profile = DB()
            if not profile then return false end
            return profile.secondary.darkTheme
        end,
        setValue = function(value)
            local profile = DB()
            if not profile then return end
            profile.secondary.darkTheme = value
            RebuildClass()
            -- Full rebuild so the Background label re-renders
            CludesUI:RefreshPage(true)
        end,
    }, {
        type = "slider",
        text = backgroundLabel,
        min = 0,
        max = 100,
        step = 1,
        trackWidth = 120,
        getValue = function()
            local profile = DB()
            if not profile then return 75 end
            if profile.splitBg == true then
                return math.floor(((profile.secondary.barBgA or 0.5) * 100) + 0.5)
            end
            return math.floor(((profile.health.bgA or 0.75) * 100) + 0.5)
        end,
        setValue = function(value)
            local profile = DB()
            if not profile then return end
            local a = value / 100
            if profile.splitBg == true then
                -- Split mode: Health/Power own their keys via the rows below, this row still owns the class resource bar
                profile.secondary.barBgA = a
            else
                profile.health.bgA = a
                profile.primary.bgA = a
                profile.secondary.barBgA = a
            end
            GentleRefresh()
            CludesUI:RefreshPage()
        end,
    })
    cursorY = cursorY - height
    -- Background inline swatch is color-only: opacity lives in the slider, a view over the same bgA keys.
    if not CludesUI._prebuilding then
        local region = bgRow._rightRegion
        local control = region._control

        -- Split cog. The feature is an options-side VIEW: the bars already read their own keys
        -- at runtime (health.bg*, primary.bg*, secondary.barBg*) and the unified row just writes
        -- them in lockstep, so splitting only changes which rows write which keys -- zero runtime
        -- change, nothing hits the DB unless opted in. splitCogShow MUST be declared BEFORE the
        -- build so the toggle's set closure (built inside the argument table) captures it as an
        -- upvalue (assigning on the same line would leave the closure seeing nil). The popup frame
        -- is built LAZILY on first show, so the closure reaches it via showFn._popupFrame, stamped
        -- by the show wrapper on first open.
        local _, splitCog
        _, splitCog = CludesUI.BuildInlineCog(region, {
            title = "Background",
            minWidth = 290,
            rows = {
                {
                    type = "toggle",
                    label = "Choose background per bar",
                    get = function()
                        local profile = DB()
                        return (profile and profile.splitBg) == true
                    end,
                    set = function(value)
                        local profile = DB()
                        if not profile then return end
                        if value then
                            profile.splitBg = true
                            -- Close the popup so the newly revealed per-bar rows are visible (frame always exists here, but guard anyway)
                            local pfr = splitCog and splitCog._popupFrame
                            if pfr then pfr:Hide() end
                        else
                            -- Split OFF re-unifies from Health (the unified row's read source) so "off" really means one background, not silently diverged bars.
                            -- Stored false, not nil: profile sync copies only keys that exist.
                            profile.splitBg = false
                            local healthCfg = profile.health
                            profile.primary.bgR, profile.primary.bgG, profile.primary.bgB, profile.primary.bgA =
                                healthCfg.bgR, healthCfg.bgG, healthCfg.bgB, healthCfg.bgA
                            profile.secondary.barBgR, profile.secondary.barBgG, profile.secondary.barBgB, profile.secondary.barBgA =
                                healthCfg.bgR, healthCfg.bgG, healthCfg.bgB, healthCfg.bgA
                            GentleRefresh()
                        end
                        CludesUI:RefreshPage(true)
                    end,
                },
            },
        })

        local bgSwatch, bgUpdateSwatch = CludesUI.BuildColorSwatch(
            region,
            bgRow:GetFrameLevel() + 3,
            function()
                local profile = DB()
                if profile and profile.splitBg == true then
                    return profile.secondary.barBgR or 0,
                        profile.secondary.barBgG or 0,
                        profile.secondary.barBgB or 0
                end
                return (profile and profile.health.bgR or 0x11 / 255),
                    (profile and profile.health.bgG or 0x11 / 255),
                    (profile and profile.health.bgB or 0x11 / 255)
            end,
            function(red, green, blue)
                local profile = DB()
                if not profile then return end
                if profile.splitBg == true then
                    profile.secondary.barBgR, profile.secondary.barBgG, profile.secondary.barBgB =
                        red, green, blue
                else
                    profile.health.bgR, profile.health.bgG, profile.health.bgB = red, green, blue
                    profile.primary.bgR, profile.primary.bgG, profile.primary.bgB = red, green, blue
                    profile.secondary.barBgR, profile.secondary.barBgG, profile.secondary.barBgB =
                        red, green, blue
                end
                GentleRefresh()
                CludesUI:RefreshPage()
            end,
            nil,
            20
        )
        Pix.Point(bgSwatch, "RIGHT", region._lastInline or control, "LEFT", -8, 0)
        region._lastInline = bgSwatch
        CludesUI.RegisterWidgetRefresh(bgUpdateSwatch)
    end

    -- Split rows are built ONLY while the split is enabled, so the page is byte-identical for
    -- everyone else. Health writes health.*, Power writes primary.* only; the class resource's
    -- barBg* stays with the unified Background row above, which relabels and narrows to those keys.
    do
        local profile = DB()
        if profile and profile.splitBg == true then
            local splitRow
            splitRow, height = W:DualRow(hostFrame, cursorY, {
                type = "slider",
                text = "Health Background",
                min = 0,
                max = 100,
                step = 1,
                trackWidth = 120,
                getValue = function()
                    local profile = DB()
                    return math.floor(((profile and profile.health.bgA or 0.75) * 100) + 0.5)
                end,
                setValue = function(value)
                    local profile = DB()
                    if not profile then return end
                    profile.health.bgA = value / 100
                    GentleRefresh()
                    CludesUI:RefreshPage()
                end,
            }, {
                type = "slider",
                text = "Power Background",
                min = 0,
                max = 100,
                step = 1,
                trackWidth = 120,
                getValue = function()
                    local profile = DB()
                    return math.floor(((profile and profile.primary.bgA or 0.75) * 100) + 0.5)
                end,
                setValue = function(value)
                    local profile = DB()
                    if not profile then return end
                    profile.primary.bgA = value / 100
                    GentleRefresh()
                    CludesUI:RefreshPage()
                end,
            })
            cursorY = cursorY - height
            if not CludesUI._prebuilding then
                local region = splitRow._leftRegion
                local control = region._control
                local hSwatch, hUpdateSwatch = CludesUI.BuildColorSwatch(
                    region,
                    splitRow:GetFrameLevel() + 3,
                    function()
                        local profile = DB()
                        return (profile and profile.health.bgR or 0x11 / 255),
                            (profile and profile.health.bgG or 0x11 / 255),
                            (profile and profile.health.bgB or 0x11 / 255)
                    end,
                    function(red, green, blue)
                        local profile = DB()
                        if not profile then return end
                        profile.health.bgR, profile.health.bgG, profile.health.bgB = red, green, blue
                        GentleRefresh()
                        CludesUI:RefreshPage()
                    end,
                    nil,
                    20
                )
                Pix.Point(hSwatch, "RIGHT", control, "LEFT", -8, 0)
                CludesUI.RegisterWidgetRefresh(hUpdateSwatch)
            end
            if not CludesUI._prebuilding then
                local region = splitRow._rightRegion
                local control = region._control
                local pSwatch, pUpdateSwatch = CludesUI.BuildColorSwatch(
                    region,
                    splitRow:GetFrameLevel() + 3,
                    function()
                        local profile = DB()
                        return (profile and profile.primary.bgR or 0x11 / 255),
                            (profile and profile.primary.bgG or 0x11 / 255),
                            (profile and profile.primary.bgB or 0x11 / 255)
                    end,
                    function(red, green, blue)
                        local profile = DB()
                        if not profile then return end
                        profile.primary.bgR, profile.primary.bgG, profile.primary.bgB = red, green, blue
                        GentleRefresh()
                        CludesUI:RefreshPage()
                    end,
                    nil,
                    20
                )
                Pix.Point(pSwatch, "RIGHT", control, "LEFT", -8, 0)
                CludesUI.RegisterWidgetRefresh(pUpdateSwatch)
            end
        end
    end

    -- Row 3: Texture | Frame Strata. Each sets all three bars; its cog gives the health and
    -- power bars their own (Match Main follows the row). A bar's own texture is written
    -- through ns.ERB_SetBarTexture, which keeps splitTex in step (the runtime, the Style
    -- page's slots and the Global Settings Textures page read it); a bar's own strata is
    -- health.frameStrata / primary.frameStrata. Match Main is stored false, not nil:
    -- profile sync copies only keys that exist.
    local strataValues = CludesUI.FRAME_STRATA_LABELS
    local strataOrder = CludesUI.FRAME_STRATA_ORDER_BASE
    local textureRow
    textureRow, height = W:DualRow(hostFrame, cursorY, {
        type = "dropdown",
        text = "Texture",
        values = hbtValues,
        order = hbtOrder,
        getValue = function()
            local profile = DB()
            if not profile then return "none" end
            return profile.general.barTexture or "none"
        end,
        setValue = function(value)
            local profile = DB()
            if not profile then return end
            profile.general.barTexture = value
            GentleRefresh()
        end,
    }, {
        type = "dropdown",
        text = "Frame Strata",
        tooltip = "Controls the order that overlapping elements display in. Set higher to show above other elements.",
        values = strataValues,
        order = strataOrder,
        getValue = function()
            local profile = DB()
            return profile and profile.general.frameStrata or "MEDIUM"
        end,
        setValue = function(value)
            local profile = DB()
            if not profile then return end
            profile.general.frameStrata = value
            GentleRefresh()
        end,
    })
    cursorY = cursorY - height
    if not CludesUI._prebuilding then
        local function BarTextureRow(labelText, barId)
            local value, o = CopyTexDD()
            value.__match = "Match Main Texture"
            table.insert(o, 1, "---")
            table.insert(o, 1, "__match")
            return {
                type = "dropdown",
                label = labelText,
                values = value,
                order = o,
                ddWidth = 170,
                get = function()
                    local profile = DB()
                    return profile and mod.ERB_BarTexture(profile, barId) or "__match"
                end,
                set = function(val)
                    local profile = DB()
                    if not profile then return end
                    local was = profile.splitTex == true
                    mod.ERB_SetBarTexture(profile, barId, val ~= "__match" and val)
                    GentleRefresh()
                    -- The Global Settings Textures page shows the health and power rows
                    -- only while one has its own texture: drop its cached build on a flip.
                    if (profile.splitTex == true) ~= was then
                        CludesUI:InvalidateModulePageCache("_CUIGlobal")
                    end
                end,
            }
        end
        local function BarStrataRow(labelText, barId)
            local value, o = { __match = "Match Main Strata" }, { "__match", "---" }
            for idx = 1, #strataOrder do
                local keyName = strataOrder[idx]
                value[keyName] = strataValues[keyName]
                o[#o + 1] = keyName
            end
            return {
                type = "dropdown",
                label = labelText,
                values = value,
                order = o,
                ddWidth = 150,
                get = function()
                    local profile = DB()
                    return profile and profile[barId].frameStrata or "__match"
                end,
                set = function(val)
                    local profile = DB()
                    if not profile then return end
                    profile[barId].frameStrata = val ~= "__match" and val or false
                    GentleRefresh()
                end,
            }
        end
        CludesUI.BuildInlineCog(textureRow._leftRegion, {
            title = "Texture Settings",
            captureRegion = textureRow._leftRegion,
            rows = {
                BarTextureRow("Health Texture", "health"),
                BarTextureRow("Power Texture", "primary"),
                {
                    type = "toggle",
                    label = "Blizzard Class Resource Bar Texture",
                    tooltip = "Bar-style class resources (Insanity, Maelstrom, Astral Power, etc.) use Blizzard's default player frame bar artwork instead of the texture above.",
                    get = function()
                        local profile = DB()
                        return (profile and profile.secondary.useBlizzardAtlas) or false
                    end,
                    set = function(value)
                        local profile = DB()
                        if not profile then return end
                        profile.secondary.useBlizzardAtlas = value
                        RebuildClass()
                        if value then
                            CludesUI:ShowConfirmPopup({
                                title = "Blizzard Class Resource Bar Texture",
                                message = "Blizzard's bar artwork is never recolored, so fill color modes and threshold colors will not tint the bar while this is enabled. To keep threshold colors visible, use Recolor Text Instead.",
                                confirmText = "Okay",
                            })
                        end
                    end,
                },
                {
                    type = "toggle",
                    label = "Continuous Texture for Pip Resources",
                    tooltip = "Spreads the texture across all pips instead of restarting it on each one. Useful for gradient textures.",
                    get = function()
                        local profile = DB()
                        return (profile and profile.secondary.useContinuousTexture) or false
                    end,
                    set = function(value)
                        local profile = DB()
                        if not profile then return end
                        profile.secondary.useContinuousTexture = value
                        RebuildClass()
                    end,
                },
                TexBgRowCfg("bars", GentleRefresh),
            },
        })
        CludesUI.BuildInlineCog(textureRow._rightRegion, {
            title = "Frame Strata Settings",
            captureRegion = textureRow._rightRegion,
            rows = {
                BarStrataRow("Health Strata", "health"),
                BarStrataRow("Power Strata", "primary"),
            },
        })
    end

    -- Row 4: Blizzard Class Resource Art | Border Around All (stock styles
    -- only; a blank slot otherwise). Border Around All draws one frame round
    -- the resource bars as a group; greyed only while off, so a setting whose
    -- bars stop lining up can still be turned off.
    local borderAllOn = mod.ERB_BorderAllRow()
    local borderAllCfg = CludesUI.BlankRowCfg()
    if borderAllOn then
        borderAllCfg = {
            type = "toggle",
            text = "Border Around All",
            tooltip = "Draws one frame around the resource bars instead of one per bar.",
            disabled = function()
                local profile = DB()
                if not profile then return true end
                if profile.general.classicBorderAll then return false end
                return not mod.ERB_GroupCheck(profile)
            end,
            disabledTooltip = function()
                local _, why = mod.ERB_GroupCheck(DB())
                if why == "count" then
                    return "This option requires at least two resource bars to be shown."
                end
                if why == "orient" then
                    return "This option requires the resource bars to share one orientation."
                end
                return "This option requires the resource bars to be width matched to each other or to have matching widths."
            end,
            rawTooltip = true,
            getValue = function()
                local profile = DB()
                return (profile and profile.general.classicBorderAll) and true or false
            end,
            setValue = function(value)
                local profile = DB()
                if not profile then return end
                profile.general.classicBorderAll = value and true or false
                -- One classic frame, one size: the lead bar's Border Size
                -- for all three (Blizzard Style has no Border Size).
                if value and mod.ERB_ClassicBorderRow() then
                    local s = mod.ERB_GroupLeadCfg(profile).stockBorderScale
                    for idx = 1, #CLASSIC_SYNC_KEYS do
                        profile[CLASSIC_SYNC_KEYS[idx]].stockBorderScale = s
                    end
                end
                Refresh()
                -- The size-match pads follow the shared scale.
                for idx = 1, #CLASSIC_MATCH_KEYS do
                    CludesUI.ReapplyMatchPads(CLASSIC_MATCH_KEYS[idx])
                end
                CludesUI:RefreshPage()
            end,
        }
    end
    local blizzArtRow
    blizzArtRow, height = W:DualRow(hostFrame, cursorY, {
        type = "toggle",
        text = "Blizzard Class Resource Art",
        tooltip = "Replaces the class resource bar with Blizzard's own class resource frame, such as Holy Power, Combo Points, Chi, Soul Shards, Arcane Charges, Essence or Runes.",
        -- Greyed on specs whose class resource Blizzard draws as a bar or not
        -- at all, and while the Unit Frames "Blizzard" class resource style
        -- holds that frame (Unit Frames wins it). Greyed only while off, so
        -- it can still be turned off there.
        disabled = function()
            local profile = DB()
            if not profile then return true end
            if profile.secondary.blizzardClassArt then return false end
            return not (mod.ERB_BlizzClassArtSupported and mod.ERB_BlizzClassArtSupported())
        end,
        disabledTooltip = function()
            local why = mod.ERB_BlizzClassArtSupported and select(2, mod.ERB_BlizzClassArtSupported())
            if why == "uf" then
                return "This option can't be used while the Unit Frames class resource is set to Blizzard."
            end
            if why == "client" then return "This option is not available on this client." end
            if why == "prd" then
                return "This option can't be used while the Personal Resource Display hides the player frame's class resource."
            end
            return "This option requires a class resource that Blizzard shows as its own frame, such as Holy Power, Combo Points, Chi, Soul Shards, Arcane Charges, Essence or Runes."
        end,
        rawTooltip = true,
        getValue = function()
            local profile = DB()
            return (profile and profile.secondary.blizzardClassArt) and true or false
        end,
        setValue = function(value)
            local profile = DB()
            if not profile then return end
            profile.secondary.blizzardClassArt = value and true or false
            RebuildClass()
            CludesUI:RefreshPage()
        end,
    }, borderAllCfg)
    cursorY = cursorY - height
    -- Inline scale cog on "Blizzard Class Resource Art". Greyed while the
    -- toggle is off (its setter refreshes the page).
    if not CludesUI._prebuilding then
        local region = blizzArtRow._leftRegion
        local function artOff()
            local profile = DB()
            return not (profile and profile.secondary.blizzardClassArt)
        end
        CludesUI.BuildInlineCog(region, {
            disabled = artOff,
            disabledTooltip = "Blizzard Class Resource Art",
            title = "Blizzard Class Resource Art",
            rows = {
                {
                    type = "slider",
                    label = "Scale",
                    min = 50,
                    max = 200,
                    step = 5,
                    get = function()
                        local profile = DB()
                        return math.floor(
                            ((profile and profile.secondary.blizzardClassArtScale) or 1) * 100 + 0.5
                        )
                    end,
                    set = function(value)
                        local profile = DB()
                        if not profile then return end
                        profile.secondary.blizzardClassArtScale = value / 100
                        if mod.ERB_ApplyBlizzClassArt then mod.ERB_ApplyBlizzClassArt() end
                    end,
                },
            },
        })
    end
    -- Inline cog on "Border Around All" (stock styles only): the separator
    -- line between the grouped bars. Greyed while the toggle is off (its
    -- setter refreshes the page).
    if borderAllOn and not CludesUI._prebuilding then
        local region = blizzArtRow._rightRegion
        local function groupOff()
            local profile = DB()
            return not (profile and profile.general.classicBorderAll)
        end
        local function redraw()
            if mod.ERB_GroupDirty then mod.ERB_GroupDirty() end
        end
        CludesUI.BuildInlineCog(region, {
            disabled = groupOff,
            disabledTooltip = "Border Around All",
            title = "Border Around All",
            rows = {
                {
                    type = "slider",
                    label = "Separator Border",
                    min = 0,
                    max = 5,
                    step = 1,
                    get = function()
                        local profile = DB()
                        local value = profile and profile.general.classicBorderAllSepSize
                        if value == nil then value = 1 end
                        return value
                    end,
                    set = function(value)
                        local profile = DB()
                        if not profile then return end
                        profile.general.classicBorderAllSepSize = value
                        redraw()
                    end,
                },
                {
                    type = "colorpicker",
                    label = "Separator Color",
                    get = function()
                        local profile = DB()
                        local g = profile and profile.general
                        return (g and g.classicBorderAllSepR) or 0,
                            (g and g.classicBorderAllSepG) or 0,
                            (g and g.classicBorderAllSepB) or 0,
                            1
                    end,
                    set = function(red, green, blue)
                        local profile = DB()
                        if not profile then return end
                        profile.general.classicBorderAllSepR, profile.general.classicBorderAllSepG, profile.general.classicBorderAllSepB =
                            red, green, blue
                        redraw()
                    end,
                },
            },
        })
    end

    _, height = W:Spacer(hostFrame, cursorY, 16)
    cursorY = cursorY - height

    -- BAR SHIFTING: what the bars and the elements anchored to them do while
    -- the class resource or the power bar is missing.
    _, height = W:SectionHeader(hostFrame, "BAR SHIFTING", cursorY)
    cursorY = cursorY - height

    -- Row 1: Expand Power Bar if No Resource | Shift Elements if No Resource
    local shiftRow
    shiftRow, height = W:DualRow(hostFrame, cursorY, {
        type = "toggle",
        text = "Expand Power Bar if No Resource",
        tooltip = "When the class resource bar is not shown, this automatically adds the class resource height to the power bar.",
        -- Mutually exclusive with "Shift Elements if No Resource": grey this while shift is set, but only when this is itself OFF so a legacy profile with both on can still turn this off (no deadlock).
        disabled = function()
            local profile = DB()
            if not profile then return false end
            if not profile.primary.enabled then return true end
            if CludesUI.GetHeightMatchTarget and CludesUI.GetHeightMatchTarget("ERB_Power") then
                return true
            end
            -- Shift blocks expand when the dropdown is set to Up/Down. Independent of "Show Class Resource" -- toggling the resource bar must NOT change this control's disabled state.
            local shiftOn = (profile.secondary.shiftElementsIfNoResource or "None") ~= "None"
            return shiftOn and not profile.primary.expandIfNoResource and true or false
        end,
        disabledTooltip = function()
            local profile = DB()
            if profile and not profile.primary.enabled then return "Power Bar" end
            if CludesUI.GetHeightMatchTarget and CludesUI.GetHeightMatchTarget("ERB_Power") then
                return "This option can't be used while you have the Power Bar Height Matched in the Layout Mode."
            end
            return "This option can't be used while Shift Elements if No Resource is enabled."
        end,
        getValue = function()
            -- Force off when height matched
            if CludesUI.GetHeightMatchTarget and CludesUI.GetHeightMatchTarget("ERB_Power") then
                return false
            end
            local profile = DB()
            return profile and profile.primary.expandIfNoResource
        end,
        setValue = function(value)
            -- Block enable when height matched
            if value and CludesUI.GetHeightMatchTarget and CludesUI.GetHeightMatchTarget("ERB_Power") then
                return
            end
            local profile = DB()
            if not profile then return end
            profile.primary.expandIfNoResource = value
            -- Enabling expand turns off the mutually-exclusive shift option.
            if value then profile.secondary.shiftElementsIfNoResource = "None" end
            Refresh()
            CludesUI:RefreshPage()
        end,
    }, {
        type = "segmented",
        text = "Shift Elements if No Resource",
        tooltip = "Shifts any elements anchored to the class resource bar up or down to offset the missing class resource.",
        -- Mutually exclusive with "Expand Power Bar if No Resource": grey this while expand is on,
        -- but only when this is itself OFF (== "None") so a legacy profile with both on can still
        -- turn this off (no deadlock). Independent of "Show Class Resource" -- the shift setting is
        -- exactly what's wanted while the resource bar is hidden, so that toggle must NOT change this control's disabled state.
        disabled = function()
            local profile = DB()
            if not profile then return false end
            -- Expand only blocks shift when EFFECTIVELY on (power bar enabled and not height-matched)
            local matchedHeight = CludesUI.GetHeightMatchTarget and CludesUI.GetHeightMatchTarget("ERB_Power")
            local expandOn = profile.primary.enabled
                and profile.primary.expandIfNoResource
                and not matchedHeight
            local shiftOff = (profile.secondary.shiftElementsIfNoResource or "None") == "None"
            return expandOn and shiftOff and true or false
        end,
        disabledTooltip = "This option can't be used while Expand Power Bar if No Resource is enabled.",
        values = { None = "None", Up = "Up", Down = "Down" },
        order = { "None", "Up", "Down" },
        getValue = function()
            local profile = DB()
            return (profile and profile.secondary.shiftElementsIfNoResource) or "None"
        end,
        setValue = function(value)
            local profile = DB()
            if not profile then return end
            profile.secondary.shiftElementsIfNoResource = value
            -- Enabling shift turns off the mutually-exclusive expand option.
            if value ~= "None" then profile.primary.expandIfNoResource = false end
            RebuildClass()
            CludesUI:RefreshPage()
        end,
    })
    cursorY = cursorY - height
    -- Inline reposition cog on "Expand Power Bar if No Resource": Extra Y Offset.
    -- Greyed whenever the expand cannot apply (the toggle off, the Power Bar
    -- off, or the bar Height Matched), with the toggle's own reasons.
    if not CludesUI._prebuilding then
        local region = shiftRow._leftRegion
        local function matchedHeight()
            return CludesUI.GetHeightMatchTarget and CludesUI.GetHeightMatchTarget("ERB_Power")
        end
        CludesUI.BuildInlineCog(region, {
            disabled = function()
                local profile = DB()
                if not (profile and profile.primary.enabled and profile.primary.expandIfNoResource) then
                    return true
                end
                return matchedHeight() and true or false
            end,
            disabledTooltip = function()
                local profile = DB()
                if profile and not profile.primary.enabled then return "Power Bar" end
                if matchedHeight() then
                    return "This option can't be used while you have the Power Bar Height Matched in the Layout Mode."
                end
                return "Expand Power Bar if No Resource"
            end,
            title = "Expand Offset",
            rows = {
                {
                    type = "slider",
                    pixel = true,
                    label = "Extra Y Offset",
                    min = -50,
                    max = 50,
                    step = 1,
                    get = function()
                        local profile = DB()
                        return (profile and profile.primary.expandIfNoResourceExtraY) or 0
                    end,
                    set = function(value)
                        local profile = DB()
                        if not profile then return end
                        profile.primary.expandIfNoResourceExtraY = value
                        Refresh()
                    end,
                },
            },
        })
    end
    -- Inline reposition cog on "Shift Elements if No Resource": Extra Y Offset
    if not CludesUI._prebuilding then
        local region = shiftRow._rightRegion
        CludesUI.BuildInlineCog(region, {
            title = "Shift Offset",
            rows = {
                {
                    type = "slider",
                    pixel = true,
                    label = "Extra Y Offset",
                    min = -50,
                    max = 50,
                    step = 1,
                    get = function()
                        local profile = DB()
                        return (profile and profile.secondary.shiftElementsIfNoResourceExtraY) or 0
                    end,
                    set = function(value)
                        local profile = DB()
                        if not profile then return end
                        profile.secondary.shiftElementsIfNoResourceExtraY = value
                        RebuildClass()
                        -- BuildBars' cascade is edge-gated on the shift
                        -- DIRECTION, which a magnitude edit never flips --
                        -- re-cascade explicitly so the slider applies live
                        -- while the shift is active.
                        if CludesUI.PropagateAnchorChain then
                            CludesUI.PropagateAnchorChain("ERB_ClassResource")
                        end
                    end,
                },
            },
        })
    end

    -- Row 2: Shift Elements if No Power | Hide Power Bar if Resource
    local shiftRow2
    shiftRow2, height = W:DualRow(hostFrame, cursorY, {
        type = "segmented",
        text = "Shift Elements if No Power",
        tooltip = "Shifts any elements anchored to the power bar up or down to offset the missing power bar. Applies both when the Power Bar is disabled and for specs that have no power (for example, Beast Mastery and Marksmanship Hunters, whose Focus shows as the class resource bar).",
        -- Intentionally NOT disabled when the Power Bar is off: this setting is meant to fire precisely when the bar is disabled, so it must stay configurable in that state.
        values = { None = "None", Up = "Up", Down = "Down" },
        order = { "None", "Up", "Down" },
        getValue = function()
            local profile = DB()
            return (profile and profile.primary.shiftElementsIfNoPower) or "None"
        end,
        setValue = function(value)
            local profile = DB()
            if not profile then return end
            profile.primary.shiftElementsIfNoPower = value
            RebuildPower()
            CludesUI:RefreshPage()
        end,
    }, {
        type = "toggle",
        text = "Hide Power Bar if Resource",
        tooltip = "Hides the power bar whenever the class resource bar is showing.",
        disabled = function()
            local profile = DB()
            return not (profile and profile.secondary.enabled)
        end,
        disabledTooltip = "Class Resource",
        getValue = function()
            local profile = DB()
            return (profile and profile.secondary.hidePowerIfResource) and true or false
        end,
        setValue = function(value)
            local profile = DB()
            if not profile then return end
            profile.secondary.hidePowerIfResource = value
            RebuildClass()
        end,
    })
    cursorY = cursorY - height
    -- Inline reposition cog on "Shift Elements if No Power": Extra Y Offset
    if not CludesUI._prebuilding then
        local region = shiftRow2._leftRegion
        CludesUI.BuildInlineCog(region, {
            title = "Shift Offset",
            rows = {
                {
                    type = "slider",
                    pixel = true,
                    label = "Extra Y Offset",
                    min = -50,
                    max = 50,
                    step = 1,
                    get = function()
                        local profile = DB()
                        return (profile and profile.primary.shiftElementsIfNoPowerExtraY) or 0
                    end,
                    set = function(value)
                        local profile = DB()
                        if not profile then return end
                        profile.primary.shiftElementsIfNoPowerExtraY = value
                        RebuildPower()
                        -- Same explicit re-cascade as the class-resource
                        -- Shift Offset cog: the direction edge gate never
                        -- fires on a magnitude edit.
                        if CludesUI.PropagateAnchorChain then CludesUI.PropagateAnchorChain("ERB_Power") end
                    end,
                },
            },
        })
    end

    _, height = W:Spacer(hostFrame, cursorY, 16)
    cursorY = cursorY - height

    -- CLASS RESOURCE BAR (header + Row 1 etc. now via the shared builder)
    local classPart, classEnableRow, classResourceTextRow, classJump
    cursorY, classPart, classEnableRow, classResourceTextRow, classJump =
        mod.ERB_BuildClassResourceSection(hostFrame, cursorY, {
            cfg = function() return DB().secondary end,
            advanced = false,
            syncRows = _syncRows,
        })
    AddPreviewEye(classPart, "CLASS RESOURCE BAR", "classResource", classJump)

    -- Row: Anchor to Cursor | Cursor Position (cog: X + Y). Appended outside the shared section builder, so it carries its own hidden-while-disabled gate (the builder's toggle rebuilds on flips)
    if DB().secondary.enabled then
        local _, cursorHeight = CludesUI.BuildCursorAnchorRow({
            W = W,
            parent = hostFrame,
            y = cursorY,
            getData = function()
                local profile = DB()
                return profile and profile.secondary or {}
            end,
            onApply = function()
                RebuildClass()
                GentleRefresh()
            end,
        })
        cursorY = cursorY - cursorHeight
    end

    _, height = W:Spacer(hostFrame, cursorY, 16)
    cursorY = cursorY - height

    -- POWER BAR (section header + Row 1 now via the shared builder)
    local powerPart, powerEnableRow, powerJump
    cursorY, powerPart, powerEnableRow, powerJump = mod.ERB_BuildPowerSection(hostFrame, cursorY, {
        cfg = function() return DB().primary end,
        advanced = false,
        syncRows = _syncRows,
    })
    AddPreviewEye(powerPart, "POWER BAR", "power", powerJump)

    -- Row: Anchor to Cursor | Cursor Position (cog: X + Y). Appended outside the shared section builder, so it carries its own hidden-while-disabled gate (the builder's toggle rebuilds on flips)
    if DB().primary.enabled then
        local _, cursorHeight = CludesUI.BuildCursorAnchorRow({
            W = W,
            parent = hostFrame,
            y = cursorY,
            getData = function()
                local profile = DB()
                return profile and profile.primary or {}
            end,
            onApply = function()
                RebuildPower()
                GentleRefresh()
            end,
        })
        cursorY = cursorY - cursorHeight
    end

    -- Row 7: Power Type override (spec-dependent, like UF Power Type dropdown). Hidden with the rest of the Power section while the bar is off.
    if DB().primary.enabled then
        local _, classFile = UnitClass("player")
        -- A spec's third label is an extra choice ("always": Balance's Mana in
        -- every form); tip = the row's tooltip for the class.
        local SPEC_POWER_ALTS = {
            DRUID = {
                [1] = { "Match Form", "Astral Power", "Mana" },
                [2] = { "Match Form", "Mana" },
                [3] = { "Match Form", "Mana" },
                [4] = { "Match Form", "Mana" },
                tip = "The first choice follows your form: Energy in Cat Form, Rage in Bear Form and Mana in the others. The other choices keep their power in every form.",
            },
            PRIEST = { [3] = { "Mana", "Insanity" } },
            SHAMAN = { [1] = { "Mana", "Maelstrom" } },
            EVOKER = { [3] = { "Ebon Might", "Mana" } },
        }
        local classOptions = SPEC_POWER_ALTS[classFile]
        -- Retail only: WoW Forever has no specs (see the druid row below).
        if classOptions and not CludesUI.IS_FOREVER then
            local specInfo = GetSpecialization and GetSpecialization()
            local payload = specInfo and classOptions[specInfo]
            if payload then
                local ptValues = { ["default"] = payload[1], ["alt"] = payload[2], ["always"] = payload[3] }
                local ptOrder = { "default", "alt" }
                if payload[3] then ptOrder[3] = "always" end
                local powerKindRow
                powerKindRow, height = W:DualRow(hostFrame, cursorY, {
                    type = "dropdown",
                    text = "Power Type",
                    tooltip = classOptions.tip,
                    values = ptValues,
                    order = ptOrder,
                    -- Stored by SPEC ID, not the GetSpecialization() index:
                    -- one profile holds one set, so an index key collides
                    -- across classes (slot 3 is Guardian, Shadow AND
                    -- Augmentation, which want three different power types).
                    -- classAlts stays index-keyed, it is already per class.
                    getValue = function()
                        local s = GetSpecialization and GetSpecialization()
                        if not s or not classOptions[s] then return "default" end
                        local spellRef = C_SpecializationInfo
                            and C_SpecializationInfo.GetSpecializationInfo(s)
                        if not spellRef then return "default" end
                        local profile = DB()
                        if not profile then return "default" end
                        local shade = profile.primary.powerTypeOverride
                        if shade and shade[spellRef] == "mana" then return "always" end
                        if shade and shade[spellRef] then return "alt" end
                        return "default"
                    end,
                    setValue = function(value)
                        local s = GetSpecialization and GetSpecialization()
                        if not s then return end
                        local spellRef = C_SpecializationInfo
                            and C_SpecializationInfo.GetSpecializationInfo(s)
                        if not spellRef then return end
                        local profile = DB()
                        if not profile then return end
                        if value == "alt" then
                            if not profile.primary.powerTypeOverride then
                                profile.primary.powerTypeOverride = {}
                            end
                            profile.primary.powerTypeOverride[spellRef] = true
                        elseif value == "always" then
                            if not profile.primary.powerTypeOverride then
                                profile.primary.powerTypeOverride = {}
                            end
                            profile.primary.powerTypeOverride[spellRef] = "mana"
                        else
                            if profile.primary.powerTypeOverride then
                                profile.primary.powerTypeOverride[spellRef] = nil
                            end
                        end
                        RebuildPower()
                    end,
                }, { type = "label", text = "" })
                cursorY = cursorY - height

                local function UpdatePowerTypeRow()
                    local s = GetSpecialization and GetSpecialization()
                    if s and classOptions[s] then
                        powerKindRow:Show()
                    else
                        powerKindRow:Hide()
                    end
                end
                CludesUI.RegisterWidgetRefresh(UpdatePowerTypeRow)
                UpdatePowerTypeRow()
            end
        end
        -- WoW Forever: Mana Regen Spark and Spell Cost Prediction close the
        -- section (none for warriors and rogues). Other classes pair the two;
        -- a druid's spark shares its row with Power Type (one choice for all
        -- forms, stored under a string key so it never meets a retail spec
        -- ID), then Mana Bar while Shapeshifted, then Spell Cost Prediction.
        -- The cost row needs its engine loaded: the swatch reads its color rule.
        if CludesUI.IS_FOREVER then
            local SCP = CludesUI.SpellCostPrediction
            -- Off or one of two modes: a view over manaRegenSpark (on/off) and
            -- manaRegenSparkMode (nil = 5-Second Rule), so saved choices read as before.
            local sparkCfg = {
                type = "dropdown",
                text = "Mana Regen Spark",
                tooltip = "5-Second Rule sweeps a spark across the bar for 5 seconds after you spend mana, until mana regen resumes. Regen Ticks then keeps sweeping every 2 seconds while mana regenerates.",
                values = { off = "Off", fsr = "5-Second Rule", ticks = "Regen Ticks" },
                order = { "off", "fsr", "ticks" },
                getValue = function()
                    local profile = DB()
                    if not (profile and profile.primary.manaRegenSpark) then return "off" end
                    return profile.primary.manaRegenSparkMode == "ticks" and "ticks" or "fsr"
                end,
                setValue = function(value)
                    local profile = DB()
                    if not profile then return end
                    profile.primary.manaRegenSpark = value ~= "off"
                    if value ~= "off" then
                        profile.primary.manaRegenSparkMode = (value == "ticks") and "ticks" or nil
                    end
                    RebuildPower()
                end,
            }
            local costCfg = {
                type = "toggle",
                text = "Spell Cost Prediction",
                tooltip = "While you cast, shows on the bar the mana the spell will cost.",
                getValue = function()
                    local profile = DB()
                    return profile and profile.primary.powerCostPrediction == true or false
                end,
                setValue = function(value)
                    local profile = DB()
                    if not profile then return end
                    profile.primary.powerCostPrediction = value
                    RebuildPower()
                    CludesUI:RefreshPage()
                end,
            }
            -- Spell Cost Color, left of the toggle: dimmed and blocked
            -- while Spell Cost Prediction is off.
            local function CostSwatch(region)
                if CludesUI._prebuilding then return end
                CludesUI.BuildInlineSwatches(region, {
                    {
                        tooltip = "Spell Cost Color",
                        getValue = function()
                            local profile = DB()
                            local red, green, b = SCP.Color(profile and profile.primary)
                            return red, green, b, 1
                        end,
                        setValue = function(red, green, blue)
                            local profile = DB()
                            if not profile then return end
                            profile.primary.powerCostColor = { r = red, g = green, b = blue }
                        end,
                    },
                }, {
                    disabled = function()
                        local profile = DB()
                        return not (profile and profile.primary.powerCostPrediction == true)
                    end,
                    disabledTooltip = "Spell Cost Prediction",
                    size = 20,
                })
            end
            if classFile == "DRUID" then
                _, height = W:DualRow(hostFrame, cursorY, {
                    type = "segmented",
                    text = "Power Type",
                    tooltip = "Mana keeps the bar on Mana in Bear and Cat Form.",
                    values = { ["default"] = "Match Form", ["alt"] = "Mana" },
                    order = { "default", "alt" },
                    getValue = function()
                        local profile = DB()
                        local shade = profile and profile.primary.powerTypeOverride
                        return (shade and shade.foreverDruid) and "alt" or "default"
                    end,
                    setValue = function(value)
                        local profile = DB()
                        if not profile then return end
                        if value == "alt" then
                            if not profile.primary.powerTypeOverride then
                                profile.primary.powerTypeOverride = {}
                            end
                            profile.primary.powerTypeOverride.foreverDruid = true
                        elseif profile.primary.powerTypeOverride then
                            profile.primary.powerTypeOverride.foreverDruid = nil
                        end
                        RebuildPower()
                        CludesUI:RefreshPage()
                    end,
                }, sparkCfg)
                cursorY = cursorY - height

                -- Mana Bar while Shapeshifted (CUI_ResourceBars_ForeverDruidMana.lua):
                -- a thin mana bar attached to the Power Bar in Bear and Cat Form.
                -- Its settings exist only on Forever (defaults primary.foreverDruidMana).
                -- Edits go straight to the module: the companion is not part of the
                -- bar build, so a full ApplyAll would rebuild every bar.
                local function FdmCfg()
                    local profile = DB()
                    return profile and profile.primary.foreverDruidMana
                end
                local function FdmTypeMana()
                    local profile = DB()
                    local shade = profile and profile.primary.powerTypeOverride
                    return (shade and shade.foreverDruid) and true or false
                end
                local function DruidManaOff()
                    if FdmTypeMana() then return true end
                    local druidMana = FdmCfg()
                    return not (druidMana and druidMana.enabled)
                end
                local function FdmOffTip()
                    if FdmTypeMana() then return "This option requires Power Type to be set to Match Form" end
                    return "Mana Bar while Shapeshifted"
                end
                local function FdmTextDis()
                    if DruidManaOff() then return true end
                    local druidMana = FdmCfg()
                    return (druidMana and druidMana.textFormat or "none") == "none"
                end
                local function FdmTextDisTip()
                    if DruidManaOff() then return FdmOffTip() end
                    return "This option requires a Mana Bar Text format other than None"
                end
                local function ApplyDruidMana()
                    if mod.FDM_Apply then mod.FDM_Apply() end
                end
                local fdmLine
                fdmLine, height = W:DualRow(hostFrame, cursorY, {
                    type = "toggle",
                    text = "Mana Bar while Shapeshifted",
                    tooltip = "Shows a thin mana bar with the Power Bar while in Bear and Cat Form.",
                    disabled = FdmTypeMana,
                    disabledTooltip = "This option requires Power Type to be set to Match Form",
                    getValue = function()
                        local druidMana = FdmCfg()
                        return druidMana and druidMana.enabled or false
                    end,
                    setValue = function(value)
                        local druidMana = FdmCfg()
                        if not druidMana then return end
                        druidMana.enabled = value
                        ApplyDruidMana()
                        CludesUI:RefreshPage()
                    end,
                }, {
                    type = "dropdown",
                    text = "Mana Bar Text",
                    disabled = DruidManaOff,
                    disabledTooltip = FdmOffTip,
                    values = {
                        none = "None",
                        smart = "Smart Text",
                        curpp = "Power Value",
                        curmaxpp = "Power Value / Max",
                        perpp = "Power %",
                        both = "Power Value | Power %",
                    },
                    -- WoW Forever lists no Smart Text (CludesUI.PowerTextFormat).
                    order = CludesUI.PowerTextFormatOrder({
                        "none",
                        "smart",
                        "curpp",
                        "curmaxpp",
                        "perpp",
                        "both",
                    }),
                    getValue = function()
                        local druidMana = FdmCfg()
                        return CludesUI.PowerTextFormat(druidMana and druidMana.textFormat or "none")
                    end,
                    setValue = function(value)
                        local druidMana = FdmCfg()
                        if not druidMana then return end
                        druidMana.textFormat = value
                        ApplyDruidMana()
                        CludesUI:RefreshPage()
                    end,
                })
                cursorY = cursorY - height
                if not CludesUI._prebuilding then
                    -- Placement cog: position, gap, height, offsets
                    CludesUI.BuildInlineCog(fdmLine._leftRegion, {
                        disabled = DruidManaOff,
                        disabledTooltip = FdmOffTip,
                        title = "Mana Bar",
                        rows = {
                            {
                                type = "dropdown",
                                label = "Position",
                                values = { below = "Below", above = "Above", inside = "Inside" },
                                order = { "below", "above", "inside" },
                                tooltip = "On a vertical Power Bar, Below is the right side and Above is the left side.",
                                get = function()
                                    local druidMana = FdmCfg()
                                    return druidMana and druidMana.position or "below"
                                end,
                                set = function(value)
                                    local druidMana = FdmCfg()
                                    if not druidMana then return end
                                    druidMana.position = value
                                    ApplyDruidMana()
                                end,
                            },
                            {
                                type = "slider",
                                pixel = true,
                                label = "Gap",
                                min = 0,
                                max = 20,
                                step = 1,
                                disabled = function()
                                    local druidMana = FdmCfg()
                                    return (druidMana and druidMana.position == "inside") and true or false
                                end,
                                disabledTooltip = "This option requires Position to be Below or Above",
                                get = function()
                                    local druidMana = FdmCfg()
                                    return druidMana and druidMana.gap or 2
                                end,
                                set = function(value)
                                    local druidMana = FdmCfg()
                                    if not druidMana then return end
                                    druidMana.gap = value
                                    ApplyDruidMana()
                                end,
                            },
                            {
                                type = "slider",
                                label = "Height",
                                min = 2,
                                max = 30,
                                step = 1,
                                get = function()
                                    local druidMana = FdmCfg()
                                    return druidMana and druidMana.height or 6
                                end,
                                set = function(value)
                                    local druidMana = FdmCfg()
                                    if not druidMana then return end
                                    druidMana.height = value
                                    ApplyDruidMana()
                                end,
                            },
                            {
                                type = "slider",
                                label = "X Offset",
                                min = -100,
                                max = 100,
                                step = 1,
                                get = function()
                                    local druidMana = FdmCfg()
                                    return druidMana and druidMana.offsetX or 0
                                end,
                                set = function(value)
                                    local druidMana = FdmCfg()
                                    if not druidMana then return end
                                    druidMana.offsetX = value
                                    ApplyDruidMana()
                                end,
                            },
                            {
                                type = "slider",
                                label = "Y Offset",
                                min = -100,
                                max = 100,
                                step = 1,
                                get = function()
                                    local druidMana = FdmCfg()
                                    return druidMana and druidMana.offsetY or 0
                                end,
                                set = function(value)
                                    local druidMana = FdmCfg()
                                    if not druidMana then return end
                                    druidMana.offsetY = value
                                    ApplyDruidMana()
                                end,
                            },
                        },
                    })
                    -- Text cog: the Power Text cog's options plus Text Size
                    CludesUI.BuildInlineCog(fdmLine._rightRegion, {
                        disabled = FdmTextDis,
                        disabledTooltip = FdmTextDisTip,
                        title = "Mana Bar Text",
                        rows = {
                            {
                                type = "slider",
                                label = "Text Size",
                                min = 8,
                                max = 24,
                                step = 1,
                                get = function()
                                    local druidMana = FdmCfg()
                                    return druidMana and druidMana.textSize or 8
                                end,
                                set = function(value)
                                    local druidMana = FdmCfg()
                                    if not druidMana then return end
                                    druidMana.textSize = value
                                    ApplyDruidMana()
                                end,
                            },
                            {
                                type = "toggle",
                                label = "Show %",
                                get = function()
                                    local druidMana = FdmCfg()
                                    return (not druidMana) or druidMana.showPercent ~= false
                                end,
                                set = function(value)
                                    local druidMana = FdmCfg()
                                    if not druidMana then return end
                                    druidMana.showPercent = value
                                    ApplyDruidMana()
                                end,
                            },
                            {
                                type = "dropdown",
                                label = "Anchor",
                                values = { LEFT = "Left", CENTER = "Center", RIGHT = "Right" },
                                order = { "LEFT", "CENTER", "RIGHT" },
                                tooltip = "Anchor the text inside the bar. The X/Y offsets move it from there.",
                                get = function()
                                    local druidMana = FdmCfg()
                                    return druidMana and druidMana.textAnchor or "CENTER"
                                end,
                                set = function(value)
                                    local druidMana = FdmCfg()
                                    if not druidMana then return end
                                    druidMana.textAnchor = value
                                    ApplyDruidMana()
                                end,
                            },
                            {
                                type = "slider",
                                label = "X Offset",
                                min = -100,
                                max = 100,
                                step = 1,
                                get = function()
                                    local druidMana = FdmCfg()
                                    return druidMana and druidMana.textXOffset or 0
                                end,
                                set = function(value)
                                    local druidMana = FdmCfg()
                                    if not druidMana then return end
                                    druidMana.textXOffset = value
                                    ApplyDruidMana()
                                end,
                            },
                            {
                                type = "slider",
                                label = "Y Offset",
                                min = -100,
                                max = 100,
                                step = 1,
                                get = function()
                                    local druidMana = FdmCfg()
                                    return druidMana and druidMana.textYOffset or 0
                                end,
                                set = function(value)
                                    local druidMana = FdmCfg()
                                    if not druidMana then return end
                                    druidMana.textYOffset = value
                                    ApplyDruidMana()
                                end,
                            },
                        },
                    })
                    -- Text colour, left of the text cog: custom colour or the
                    -- mana colour, like the Power Text swatches.
                    CludesUI.BuildInlineSwatches(fdmLine._rightRegion, {
                        {
                            tooltip = "Custom Colored",
                            hasAlpha = true,
                            getValue = function()
                                local druidMana = FdmCfg()
                                if not druidMana then return 1, 1, 1, 1 end
                                return druidMana.textFillR or 1,
                                    druidMana.textFillG or 1,
                                    druidMana.textFillB or 1,
                                    druidMana.textFillA or 1
                            end,
                            setValue = function(red, green, blue, a)
                                local druidMana = FdmCfg()
                                if not druidMana then return end
                                druidMana.textFillR, druidMana.textFillG, druidMana.textFillB, druidMana.textFillA =
                                    red, green, blue, a
                                ApplyDruidMana()
                            end,
                            onClick = function(self)
                                local druidMana = FdmCfg()
                                if not druidMana then return end
                                if druidMana.textCustomColored == false then
                                    druidMana.textCustomColored = true
                                    ApplyDruidMana()
                                    CludesUI:RefreshPage()
                                    return
                                end
                                if self._eabOrigClick then self._eabOrigClick(self) end
                            end,
                            refreshAlpha = function()
                                local druidMana = FdmCfg()
                                return (druidMana and druidMana.textCustomColored == false) and 0.3 or 1
                            end,
                        },
                        {
                            tooltip = "Mana Colored",
                            getValue = function()
                                local pc = _G._CURB_PowerColors and _G._CURB_PowerColors.MANA
                                if pc then return pc[1], pc[2], pc[3], 1 end
                                return 0x23 / 255, 0x8F / 255, 0xE7 / 255, 1
                            end,
                            setValue = function() end,
                            onClick = function()
                                local druidMana = FdmCfg()
                                if not druidMana then return end
                                druidMana.textCustomColored = false
                                ApplyDruidMana()
                                CludesUI:RefreshPage()
                            end,
                            refreshAlpha = function()
                                local druidMana = FdmCfg()
                                return (druidMana and druidMana.textCustomColored == false) and 1 or 0.3
                            end,
                        },
                    }, {
                        disabled = FdmTextDis,
                        disabledTooltip = FdmTextDisTip,
                        size = 20,
                    })
                end
                if SCP then
                    local costLine
                    costLine, height = W:DualRow(hostFrame, cursorY, costCfg, CludesUI.BlankRowCfg())
                    cursorY = cursorY - height
                    CostSwatch(costLine._leftRegion)
                end
            elseif CludesUI.ManaRegenSpark then
                if SCP then
                    local costLine
                    costLine, height = W:DualRow(hostFrame, cursorY, costCfg, sparkCfg)
                    cursorY = cursorY - height
                    CostSwatch(costLine._leftRegion)
                else
                    _, height = W:DualRow(hostFrame, cursorY, sparkCfg, CludesUI.BlankRowCfg())
                    cursorY = cursorY - height
                end
            end
        end
    end

    _, height = W:Spacer(hostFrame, cursorY, 16)
    cursorY = cursorY - height

    -- HEALTH BAR (section header + Row 1 now via the shared builder)
    local healthPart, healthEnableRow, healthJump
    cursorY, healthPart, healthEnableRow, healthJump = mod.ERB_BuildHealthSection(hostFrame, cursorY, {
        cfg = function() return DB().health end,
        advanced = false,
        syncRows = _syncRows,
    })
    AddPreviewEye(healthPart, "HEALTH BAR", "health", healthJump)

    -- Row: Anchor to Cursor | Cursor Position (cog: X + Y). Appended outside the shared section builder, so it carries its own hidden-while-disabled gate (the builder's toggle rebuilds on flips)
    if DB().health.enabled then
        local _, cursorHeight = CludesUI.BuildCursorAnchorRow({
            W = W,
            parent = hostFrame,
            y = cursorY,
            getData = function()
                local profile = DB()
                return profile and profile.health or {}
            end,
            onApply = function()
                RebuildHealth()
                GentleRefresh()
            end,
        })
        cursorY = cursorY - cursorHeight
    end

    _, height = W:Spacer(hostFrame, cursorY, 16)
    cursorY = cursorY - height

    -- ARCANE SOUL (SUNFURY)
    -- Mage-only: the section is absent entirely for every other class rather
    -- than built and disabled, since nothing in it can ever apply to them.
    -- Absent on WoW Forever too, which has no Arcane spec or Sunfury.
    -- The spec/hero-tree gate itself lives in the module (it changes at
    -- runtime); this only decides whether the controls exist at all.
    local asSection, asEnableRow
    if select(2, UnitClass("player")) == "MAGE" and not CludesUI.IS_FOREVER then
        -- Straight to the module: this display is not part of the bar build,
        -- so a full ApplyAll would rebuild every bar to retint one string.
        -- The preview header shows the same sample, so it follows too.
        local function ApplyArcaneSoul()
            if mod.AS_Apply then mod.AS_Apply() end
            environ.UpdatePreviewHeader()
        end
        local asOff = function()
            local profile = DB()
            return profile and not profile.arcaneSoul.enabled
        end
        local AS_TIP = "Arcane Soul Helper"

        asSection, height = W:SectionHeader(hostFrame, "ARCANE SOUL (SUNFURY)", cursorY)
        cursorY = cursorY - height
        local asJump = CludesUI.BuildSectionUnlockJump(
            asSection,
            { key = "CUI_ArcaneSoul", disabled = asOff, disabledTooltip = AS_TIP }
        )
        AddPreviewEye(asSection, "ARCANE SOUL (SUNFURY)", "arcaneSoul", asJump)

        -- Row: Enable Arcane Soul Helper (+ position cog) | Show Threshold
        asEnableRow, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Enable Arcane Soul Helper",
            tooltip = "Shows a countdown to the Arcane Soul window over the last seconds of Arcane Surge, then the time left inside it. Sunfury Arcane Mages only.",
            getValue = function()
                local profile = DB()
                return profile and profile.arcaneSoul.enabled
            end,
            setValue = function(value)
                local profile = DB()
                if not profile then return end
                profile.arcaneSoul.enabled = value
                ApplyArcaneSoul()
                CludesUI:RefreshPage()
            end,
        }, {
            type = "slider",
            text = "Show Threshold",
            min = 1,
            max = 15,
            step = 1,
            tooltip = "Seconds of Arcane Surge left when the countdown appears. Always in seconds, including in GCD mode.",
            disabled = asOff,
            disabledTooltip = AS_TIP,
            getValue = function()
                local profile = DB()
                return profile and profile.arcaneSoul.threshold or 5
            end,
            setValue = function(value)
                local profile = DB()
                if not profile then return end
                profile.arcaneSoul.threshold = value
                ApplyArcaneSoul()
            end,
        })
        cursorY = cursorY - height

        -- Inline position cog (X/Y + unlock) on Enable, as on the GCD Bar page
        if not CludesUI._prebuilding then
            local region = asEnableRow._leftRegion
            CludesUI.BuildInlineCog(region, {
                disabled = function()
                    local profile = DB()
                    return profile and not profile.arcaneSoul.enabled
                end,
                disabledTooltip = AS_TIP,
                title = "Arcane Soul Position",
                rows = {
                    {
                        type = "slider",
                        label = "X Offset",
                        min = -600,
                        max = 600,
                        step = 1,
                        get = function()
                            local profile = DB()
                            if not profile then return 0 end
                            local arcaneCfg = profile.arcaneSoul
                            return (arcaneCfg.unlockPos and arcaneCfg.unlockPos.x) or 0
                        end,
                        set = function(value)
                            local profile = DB()
                            if not profile then return end
                            local arcaneCfg = profile.arcaneSoul
                            -- No separate offset pair for this display: the cog edits
                            -- the same saved position the mover writes, seeding it
                            -- from the default the renderer falls back to.
                            arcaneCfg.unlockPos = arcaneCfg.unlockPos
                                or { point = "CENTER", relPoint = "CENTER", x = 0, y = -150 }
                            arcaneCfg.unlockPos.x = value
                            ApplyArcaneSoul()
                        end,
                    },
                    {
                        type = "slider",
                        label = "Y Offset",
                        min = -600,
                        max = 600,
                        step = 1,
                        get = function()
                            local profile = DB()
                            if not profile then return -150 end
                            local arcaneCfg = profile.arcaneSoul
                            return (arcaneCfg.unlockPos and arcaneCfg.unlockPos.y) or -150
                        end,
                        set = function(value)
                            local profile = DB()
                            if not profile then return end
                            local arcaneCfg = profile.arcaneSoul
                            arcaneCfg.unlockPos = arcaneCfg.unlockPos
                                or { point = "CENTER", relPoint = "CENTER", x = 0, y = -150 }
                            arcaneCfg.unlockPos.y = value
                            ApplyArcaneSoul()
                        end,
                    },
                },
                footer = { unlockKey = "CUI_ArcaneSoul" },
            })
        end

        -- Row: Countdown Format | Text Size
        local asFormatValues = {
            ["seconds"] = { text = "Seconds" },
            ["gcd"] = { text = "GCD Count" },
            ["secondsGcd"] = { text = "Seconds + GCD in Soul" },
        }
        local asFormatOrder = { "seconds", "gcd", "secondsGcd" }
        -- The LAST warning only exists where the Soul window counts Barrages.
        local function AsSoulCountsGcd()
            local profile = DB()
            local m = profile and profile.arcaneSoul.countMode
            return m == "gcd" or m == "secondsGcd"
        end
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "dropdown",
            text = "Countdown Format",
            tooltip = "Seconds counts the time down in tenths. GCD Count counts whole global cooldowns instead, so inside Arcane Soul it reads as the number of Arcane Barrages that still fit, ending on a coloured LAST. Seconds + GCD in Soul mixes the two: tenths counting down to the window, Barrage count once it opens.",
            disabled = asOff,
            disabledTooltip = AS_TIP,
            values = asFormatValues,
            order = asFormatOrder,
            getValue = function()
                local profile = DB()
                return profile and profile.arcaneSoul.countMode or "seconds"
            end,
            setValue = function(value)
                local profile = DB()
                if not profile then return end
                profile.arcaneSoul.countMode = value
                ApplyArcaneSoul()
            end,
        }, {
            type = "slider",
            text = "Text Size",
            min = 10,
            max = 48,
            step = 1,
            disabled = asOff,
            disabledTooltip = AS_TIP,
            getValue = function()
                local profile = DB()
                return profile and profile.arcaneSoul.textSize or 24
            end,
            setValue = function(value)
                local profile = DB()
                if not profile then return end
                profile.arcaneSoul.textSize = value
                ApplyArcaneSoul()
                if CludesUI.NotifyElementResized then CludesUI.NotifyElementResized("CUI_ArcaneSoul") end
            end,
        })
        cursorY = cursorY - height

        -- Row: Font | Font Outline (mirrors the Battle Res text controls)
        do
            local asFontValues, asFontOrder = CludesUI.BuildFontDropdownData()
            local asOutlineValues = {
                ["__global"] = { text = "CUI Global Default" },
                ["none"] = { text = "Drop Shadow" },
                ["outline"] = { text = "Outline" },
                ["thick"] = { text = "Thick Outline" },
            }
            local asOutlineOrder = { "__global", "none", "outline", "thick" }
            _, height = W:DualRow(hostFrame, cursorY, {
                type = "dropdown",
                text = "Font",
                disabled = asOff,
                disabledTooltip = AS_TIP,
                values = asFontValues,
                order = asFontOrder,
                getValue = function()
                    local profile = DB()
                    return profile and profile.arcaneSoul.font or "__global"
                end,
                setValue = function(value)
                    local profile = DB()
                    if not profile then return end
                    profile.arcaneSoul.font = value
                    ApplyArcaneSoul()
                end,
            }, {
                type = "dropdown",
                text = "Font Outline",
                disabled = asOff,
                disabledTooltip = AS_TIP,
                values = asOutlineValues,
                order = asOutlineOrder,
                getValue = function()
                    local profile = DB()
                    return profile and profile.arcaneSoul.outlineMode or "__global"
                end,
                setValue = function(value)
                    local profile = DB()
                    if not profile then return end
                    profile.arcaneSoul.outlineMode = value
                    ApplyArcaneSoul()
                end,
            })
            cursorY = cursorY - height
        end

        -- Row: Colors (pre-Soul / in-Soul / final GCD)
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "multiSwatch",
            text = "Colors",
            disabled = asOff,
            disabledTooltip = AS_TIP,
            swatches = {
                {
                    tooltip = "Countdown to Soul",
                    hasAlpha = false,
                    getValue = function()
                        local profile = DB()
                        if not profile then return 1, 1, 1 end
                        local arcaneCfg = profile.arcaneSoul
                        return arcaneCfg.preR or 0.64, arcaneCfg.preG or 0.21, arcaneCfg.preB or 0.93
                    end,
                    setValue = function(red, green, blue)
                        local profile = DB()
                        if not profile then return end
                        local arcaneCfg = profile.arcaneSoul
                        arcaneCfg.preR, arcaneCfg.preG, arcaneCfg.preB = red, green, blue
                        ApplyArcaneSoul()
                    end,
                },
                {
                    tooltip = "Inside Soul",
                    hasAlpha = false,
                    getValue = function()
                        local profile = DB()
                        if not profile then return 1, 1, 1 end
                        local arcaneCfg = profile.arcaneSoul
                        return arcaneCfg.soulR or 0.64, arcaneCfg.soulG or 0.21, arcaneCfg.soulB or 0.93
                    end,
                    setValue = function(red, green, blue)
                        local profile = DB()
                        if not profile then return end
                        local arcaneCfg = profile.arcaneSoul
                        arcaneCfg.soulR, arcaneCfg.soulG, arcaneCfg.soulB = red, green, blue
                        ApplyArcaneSoul()
                    end,
                },
                -- Only ever rendered in GCD Count mode (the LAST warning).
                {
                    tooltip = "Last Barrage",
                    hasAlpha = false,
                    disabled = function()
                        local profile = DB()
                        return not profile or not profile.arcaneSoul.enabled or not AsSoulCountsGcd()
                    end,
                    disabledTooltip = "This option requires Countdown Format to count GCDs inside Arcane Soul",
                    getValue = function()
                        local profile = DB()
                        if not profile then return 1, 1, 1 end
                        local arcaneCfg = profile.arcaneSoul
                        return arcaneCfg.lastR or 1.0, arcaneCfg.lastG or 0.25, arcaneCfg.lastB or 0.25
                    end,
                    setValue = function(red, green, blue)
                        local profile = DB()
                        if not profile then return end
                        local arcaneCfg = profile.arcaneSoul
                        arcaneCfg.lastR, arcaneCfg.lastG, arcaneCfg.lastB = red, green, blue
                        ApplyArcaneSoul()
                    end,
                },
            },
        }, { type = "label", text = "" })
        cursorY = cursorY - height

        _, height = W:Spacer(hostFrame, cursorY, 16)
        cursorY = cursorY - height
    end

    -- Wire up click mappings for preview hit overlays (never from a hidden pre-build: the shared live table would end up pointing at off-screen rows).
    if not CludesUI._prebuilding then
        _clickMappings.classResource = { section = classPart, target = classEnableRow }
        -- The Resource Text row lives inside the shared class-resource section builder, so it must be returned from there -- naming a local from that scope here silently resolves to nil and the count-text click does nothing.
        _clickMappings.countText = { section = classPart, target = classResourceTextRow, slotSide = "left" }
        _clickMappings.power = { section = powerPart, target = powerEnableRow }
        _clickMappings.health = { section = healthPart, target = healthEnableRow }
        if asSection then _clickMappings.arcaneSoul = { section = asSection, target = asEnableRow } end
    end

    return math.abs(cursorY)
end
