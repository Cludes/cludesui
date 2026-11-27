if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-------------------------------------------------------------------------------
--  ActionBars_Options\BarVisibilityLayout_Options.lua
--  Action Bars options: the Bar 10 caution and the Visibility & Fading and
--  Layout sections of the Bar Display page. Called by BuildSharedBarSettings;
--  returns y. Shared helpers come from ns._ABO_OptEnv, the per-build helpers
--  from ctx.
-------------------------------------------------------------------------------
local mod = CUI._ModuleNS["CludesUIActionBars"]
if not mod then return end -- module disabled: no options page
-- Options page pool (CludesUI_FramePool.lua, first in this addon): a frame
-- made here on a pool host (a kept page and every frame it hands out) is reset
-- and dressed again by the next build instead of made anew; on any other
-- parent this is CreateFrame.
local CreateFrame = CUI._Pool.CreateFrame

local function BuildBarVisibilityLayout(hostFrame, cursorY, context)
    local environ = mod._ABO_OptEnv
    local ApplyVisibilityKey, BAR_LOOKUP, CopyVisibilitySettings, ABAR =
        environ.ApplyVisibilityKey, environ.BAR_LOOKUP, environ.CopyVisibilitySettings, environ.EAB
    local FirstBarButton, floor, GetVisibilityKey =
        environ.FirstBarButton, environ.floor, environ.GetVisibilityKey
    local GROUP_BAR_ORDER, IsDataBar, Pix, SB =
        environ.GROUP_BAR_ORDER, environ.IsDataBar, environ.PP, environ.SB
    local SECTION_LAYOUT, SECTION_VISIBILITY, SelectedKey, SHORT_NAMES =
        environ.SECTION_LAYOUT, environ.SECTION_VISIBILITY, environ.SelectedKey, environ.SHORT_LABELS
    local SettingsDB, ReadSetting, WriteSetting = context.SDB, context.SGet, context.SSet
    local SUpdatePreview, SUpdatePreviewAndResize, SettingOr =
        context.SUpdatePreview, context.SUpdatePreviewAndResize, context.SVal
    local visOnly = context.visOnly
    local W = context.W
    -- Visibility updates do not run ApplyAll. Recompile page-cycle macros when
    -- the set of reserved action pages changes (never/always etc.).
    local function RefreshPageCycle() mod.RefreshPagingCycleMacros() end
    local _, height, heading
    local row

    -- Global search sees row labels and tooltips only. A checkbox dropdown
    -- row's entry, registered right before its row (the index keeps the first
    -- entry of a label), carries its tooltip, its items' names and the rows its
    -- cog holds as search text; it is never shown.
    local function IndexChecklistRow(labelText, tooltip, words)
        if not CUI._RegisterSearchEntry then return end
        local textValue = {}
        local function Add(s)
            textValue[#textValue + 1] = s
            local loc = CUI.L(s)
            if loc ~= s then textValue[#textValue + 1] = loc end
        end
        Add(tooltip)
        for idx = 1, #words do
            Add(words[idx])
        end
        local labelLoc = CUI.L(labelText)
        local sel = CUI._buildingSelector
        CUI._RegisterSearchEntry(
            labelText,
            labelLoc ~= labelText and labelLoc or nil,
            table.concat(textValue, " "),
            CUI._buildingModule,
            CUI._buildingPage,
            hostFrame._currentSection and hostFrame._currentSection._sectionName,
            sel and sel.setter,
            sel and sel.key
        )
    end

    -----------------------------------------------------------------------
    --  Bar 10 / Moonkin Form caution
    -----------------------------------------------------------------------
    -- Action page 10 (Bar 10's slots) is also the Druid Moonkin Form bonus bar, so editing either edits both. Shown for all classes; text self-qualifies.
    if SelectedKey() == "Bar10" then
        local Pix = CUI.PanelPP
        local PAD = CUI.CONTENT_PAD
        local warnW = hostFrame:GetWidth() - PAD * 2
        cursorY = cursorY - 5 -- 5px spacing above the caution
        local warnHost = CreateFrame("Frame", nil, hostFrame)
        Pix.Point(warnHost, "TOPLEFT", hostFrame, "TOPLEFT", PAD, cursorY)
        local warnFS = CUI.MakeFont(warnHost, 14, nil, 1, 0.82, 0)
        warnFS:SetWidth(warnW)
        warnFS:SetWordWrap(true)
        warnFS:SetJustifyH("CENTER")
        warnFS:SetPoint("TOPLEFT", warnHost, "TOPLEFT", 0, 0)
        warnFS:SetText(
            CUI.L(
                "This Action Bar is also used as the Moonkin Form bar.\nChanging spells on a Druid for this bar will also change them on your Moonkin Form bar."
            )
        )
        local warnH = math.ceil(warnFS:GetStringHeight()) + 4
        Pix.Size(warnHost, warnW, warnH)
        cursorY = cursorY - (warnH + 12)
    end

    -----------------------------------------------------------------------
    --  VISIBILITY & FADING
    -----------------------------------------------------------------------
    heading, height = W:SectionHeader(hostFrame, SECTION_VISIBILITY, cursorY)
    cursorY = cursorY - height
    -- The Move in Unlock Mode button on the selected bar's first section: the
    -- key is read at the click, so it highlights the bar the selector shows.
    CUI.BuildSectionUnlockJump(heading, { key = SelectedKey })

    -- A data bar under Blizzard's own data bars: the rows CUI cannot apply to it grey out.
    local _visBlizzDis
    local _VIS_BLIZZ_TIP = "This option does not work with Blizzard Bars. Please use Blizzard Edit Mode."
    if IsDataBar() then _visBlizzDis = function() return ABAR.db.profile.useBlizzardDataBars end end

    do
        -- Pet Bar cannot express group modes: lock them with an explanation instead of offering silent no-ops.
        -- noOverrideMouseover: see the caps on the bar row above.
        local visCaps = { partyIncludesRaid = false, noOverrideMouseover = true }
        if SelectedKey() == "PetBar" then
            visCaps.noGroupModes = true
            visCaps.lockedTooltips = {
                in_raid = "The Pet Bar cannot use group-based visibility.",
                in_party = "The Pet Bar cannot use group-based visibility.",
                solo = "The Pet Bar cannot use group-based visibility.",
            }
        end
        -- Data bars evaluate in Lua (non-secure), so dragonriding items depend on the gliding
        -- edge event; secure bars' drivers re-evaluate natively and never lock.
        if IsDataBar() then visCaps.luaDragonriding = true end

        -- Visibility Extras: the times this bar shows beyond its Visibility
        -- setting, one checkbox per setting, each a view over its own key.
        local VIS_EXTRAS = "Visibility Extras"
        local VIS_EXTRAS_TIP = "More times this bar shows, beyond its Visibility setting."
        IndexChecklistRow(
            VIS_EXTRAS,
            VIS_EXTRAS_TIP,
            { "Show When Spellbook Is Open", "Show During Drag", "Show All Bars on Mouseover" }
        )

        local visRow1
        visRow1, height = CUI.BuildVisibilityRow(
            W,
            hostFrame,
            cursorY,
            {
                getStore = function()
                    local barCfg = SB()
                    GetVisibilityKey(barCfg)
                    return barCfg
                end,
                legacyKey = "barVisibility",
                caps = visCaps,
                applyScalarFn = function(s, mode) ApplyVisibilityKey(s, mode) end,
                disabledFn = _visBlizzDis,
                disabledTooltip = _visBlizzDis and _VIS_BLIZZ_TIP or nil,
                rawTooltip = true,
                onChanged = function()
                    if ABAR.ClearVisToggleOverride then ABAR:ClearVisToggleOverride(SelectedKey()) end
                    if ABAR.RebuildVisToggleBindings then ABAR:RebuildVisToggleBindings() end
                    ABAR:RefreshRuntimeVisibility()
                    ABAR:RefreshMouseover()
                    ABAR:ApplyCombatVisibility()
                    RefreshPageCycle()
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
            },
            -- The placeholder the Visibility Extras checklist replaces. Its getter
            -- reads the three keys the checklist writes, so the Spec Overrides
            -- gold walk marks the slot while one of them is overridden.
            {
                type = "dropdown",
                text = VIS_EXTRAS,
                tooltip = VIS_EXTRAS_TIP,
                values = { __placeholder = "..." },
                order = { "__placeholder" },
                getValue = function()
                    local barCfg = SB()
                    local _ = barCfg.spellbookShow
                    _ = barCfg.dragShow
                    _ = ABAR.db.profile.mouseoverShowAll
                    return "__placeholder"
                end,
                setValue = function() end,
            }
        )
        cursorY = cursorY - height

        do
            local region = visRow1._leftRegion
            local function CopyTo(key, source) CopyVisibilitySettings(ABAR.db.profile.bars[key], source, key) end
            CUI.BuildSyncIcon({
                region = region,
                tooltip = "Apply Visibility to all Bars",
                onClick = function()
                    local source = SB()
                    for _, key in ipairs(GROUP_BAR_ORDER) do
                        CopyTo(key, source)
                    end
                    ABAR:RefreshRuntimeVisibility()
                    ABAR:RefreshMouseover()
                    ABAR:ApplyCombatVisibility()
                    RefreshPageCycle()
                    CUI:RefreshPage()
                end,
                isSynced = function()
                    local source = SB()
                    for _, key in ipairs(GROUP_BAR_ORDER) do
                        local dst = ABAR.db.profile.bars[key]
                        if not CUI.VisFullEquals(source, "barVisibility", dst, "barVisibility") then
                            return false
                        end
                        if (source.dragShow or false) ~= (dst.dragShow or false) then return false end
                    end
                    return true
                end,
                flashTargets = function() return { region } end,
                multiApply = {
                    elementKeys = GROUP_BAR_ORDER,
                    elementLabels = SHORT_NAMES,
                    getCurrentKey = function() return SelectedKey() end,
                    onApply = function(checkedKeys)
                        local source = SB()
                        for _, key in ipairs(checkedKeys) do
                            CopyTo(key, source)
                        end
                        ABAR:RefreshRuntimeVisibility()
                        ABAR:RefreshMouseover()
                        ABAR:ApplyCombatVisibility()
                        RefreshPageCycle()
                        CUI:RefreshPage()
                    end,
                },
            })
        end
        if not CUI._prebuilding then
            local region = visRow1._rightRegion
            -- Show During Drag applies only while THIS bar's visibility is Never
            -- (other modes already surface during a drag); the item is always
            -- listed, locked with a requirement tooltip in the other modes.
            local function NeverOnly()
                local barCfg = SB()
                return not (barCfg.barVisibility == "never" or barCfg.alwaysHidden)
            end
            -- Show All Bars on Mouseover is one setting for every bar (the
            -- profile's). It links every bar set to Mouseover, action bars, the
            -- micro menu, the bag bar and the data bars alike (the runtime's
            -- mouseoverEnabled), so it is offered while any of them is.
            local function AnyMouseoverBar()
                for _, s in pairs(ABAR.db.profile.bars) do
                    if type(s) == "table" and s.mouseoverEnabled then return true end
                end
                return false
            end
            local itemList = {
                -- Available in EVERY visibility mode (unlike Show During Drag,
                -- whose behavior IS the default outside Never).
                {
                    key = "spellbookShow",
                    label = "Show When Spellbook Is Open",
                    tooltip = "While the spellbook or macro panel is open, this bar appears so you can drag abilities onto it.",
                },
                {
                    key = "dragShow",
                    label = "Show During Drag",
                    tooltip = "While dragging a spell or item, this bar appears so you can drop onto it.",
                    lockedFn = NeverOnly,
                    lockedTooltip = function() return CUI.DisabledTooltip("Visibility set to Never") end,
                },
                {
                    key = "mouseoverShowAll",
                    label = "Show All Bars on Mouseover",
                    tooltip = "Hovering one Mouseover bar shows them all.",
                    lockedFn = function() return not AnyMouseoverBar() end,
                    lockedTooltip = "This option requires a bar set to Mouseover",
                },
            }
            if region._control then region._control:Hide() end
            -- Wider than the standard 170: its longest rows ("Show When Spellbook
            -- Is Open") must fit on the closed button and in the list.
            local checkDrop, cbDDRefresh = CUI.BuildVisOptsCBDropdown(
                region,
                240,
                region:GetFrameLevel() + 2,
                itemList,
                function(keyName)
                    if keyName == "mouseoverShowAll" then
                        return ABAR.db.profile.mouseoverShowAll and true or false
                    end
                    return SB()[keyName] == true
                end,
                function(keyName, value)
                    if keyName == "spellbookShow" then
                        SB().spellbookShow = value or nil
                        -- Resync drops/replants the override live (covers
                        -- toggling while the spellbook is already open).
                        ABAR._UpdateSpellbookNeverBars(true)
                    elseif keyName == "dragShow" then
                        SB().dragShow = value
                        -- The Apply Visibility link compares this setting.
                        CUI:RefreshPage()
                    else
                        ABAR.db.profile.mouseoverShowAll = value
                    end
                end,
                nil,
                nil,
                nil,
                nil,
                nil,
                -- Spec Overrides see each click as it happens (the slot's capture).
                { notifyWrites = true, dimLocked = true }
            )
            Pix.Point(checkDrop, "RIGHT", region, "RIGHT", -20, 0)
            region._control = checkDrop
            region._lastInline = nil
            CUI.RegisterWidgetRefresh(cbDDRefresh)
        end
    end

    -----------------------------------------------------------------------
    --  ADVANCED FADE: the conditions are the setting (none checked is off),
    --  their cog holds Advanced Fade Opacity and the two fade times, and one
    --  Apply link copies all of it.
    -----------------------------------------------------------------------
    local fadeItems, ApplyAdvancedFadeTo, AdvancedFadeSynced
    -- The opacity and the fade times wait for a condition (and stand down with
    -- a data bar under Blizzard's own bars, as the conditions do).
    local function AdvancedFadeOff()
        return not ABAR.AdvancedFadeOn(SB()) or (_visBlizzDis ~= nil and _visBlizzDis())
    end
    local function AdvancedFadeOffTip()
        if _visBlizzDis ~= nil and _visBlizzDis() then return _VIS_BLIZZ_TIP end
        return "This option requires an Advanced Fade condition to be checked"
    end
    do
        local FADE_ORDER = {
            "combat",
            "party",
            "raid",
            "instance",
            "mounted",
            "flying",
            "target",
            "enemy_target",
            "mouseover",
        }
        local FADE_LABELS = {
            combat = "In Combat",
            party = "In Party",
            raid = "In Raid",
            instance = "In Instance",
            mounted = "Mounted",
            flying = "Skyriding (Airborne)",
            target = "Target",
            enemy_target = "Enemy Target",
            mouseover = "Mouseover",
        }

        local function CopyAdvancedFade(dst, source)
            local result, sc = {}, source.advancedFadeConditions
            if type(sc) == "table" then
                for idx = 1, #FADE_ORDER do
                    local keyName = FADE_ORDER[idx]
                    if sc[keyName] then result[keyName] = true end
                end
            end
            dst.advancedFadeConditions = result
            dst.fadeMaxAlpha = source.fadeMaxAlpha ~= nil and source.fadeMaxAlpha or 1
            dst.fadeInSpeed = source.fadeInSpeed or 0.15
            dst.fadeOutSpeed = source.fadeOutSpeed or 0.15
        end

        local function AdvancedFadeEqual(a, b)
            local ac, bc = a.advancedFadeConditions, b.advancedFadeConditions
            for idx = 1, #FADE_ORDER do
                local keyName = FADE_ORDER[idx]
                if
                    (type(ac) == "table" and ac[keyName] and true or false)
                    ~= (type(bc) == "table" and bc[keyName] and true or false)
                then
                    return false
                end
            end
            if
                (a.fadeMaxAlpha ~= nil and a.fadeMaxAlpha or 1)
                ~= (b.fadeMaxAlpha ~= nil and b.fadeMaxAlpha or 1)
            then
                return false
            end
            if (a.fadeInSpeed or 0.15) ~= (b.fadeInSpeed or 0.15) then return false end
            return (a.fadeOutSpeed or 0.15) == (b.fadeOutSpeed or 0.15)
        end

        -- A bar the copy leaves with no condition hands its alpha back at
        -- once; the others repaint with the copied values.
        ApplyAdvancedFadeTo = function(keyList)
            local source = SB()
            for _, key in ipairs(keyList) do
                local dst = ABAR.db.profile.bars[key]
                if dst and dst ~= source then CopyAdvancedFade(dst, source) end
            end
            ABAR:RefreshAdvancedFadeEnabled(keyList)
            ABAR:RefreshAllCustomFade(true, true)
            CUI:RefreshPage()
        end

        AdvancedFadeSynced = function()
            local source = SB()
            for _, key in ipairs(GROUP_BAR_ORDER) do
                local dst = ABAR.db.profile.bars[key]
                if dst and not AdvancedFadeEqual(source, dst) then return false end
            end
            return true
        end

        -- No skyriding on WoW Forever.
        fadeItems = {}
        for idx = 1, #FADE_ORDER do
            local keyName = FADE_ORDER[idx]
            if keyName ~= "flying" or not CUI.IS_FOREVER then
                fadeItems[#fadeItems + 1] = { key = keyName, label = FADE_LABELS[keyName] }
            end
        end
    end

    -- Bar Opacity, with Advanced Fade beside it. Advanced Fade's own dropdown
    -- is a stand-in: the conditions' checkbox dropdown below takes its place as
    -- the half's control.
    do
        local words = { "Advanced Fade Opacity", "Fade In Time", "Fade Out Time" }
        for idx = 1, #fadeItems do
            words[#words + 1] = fadeItems[idx].label
        end
        IndexChecklistRow(
            "Advanced Fade",
            "Fades this bar to Advanced Fade Opacity while one of the conditions you check holds (in combat, with a target, mounted and more). With none checked, Bar Opacity and Visibility alone decide.",
            words
        )
    end
    row, height = W:DualRow(
        hostFrame,
        cursorY,
        {
            type = "slider",
            text = "Bar Opacity",
            min = 0,
            max = 100,
            step = 5,
            getValue = function()
                local bs = SB()
                if bs.mouseoverEnabled then return floor((bs._savedBarAlpha or 1) * 100 + 0.5) end
                return floor((bs.mouseoverAlpha or 1) * 100 + 0.5)
            end,
            setValue = function(value)
                local bs = SB()
                if bs.mouseoverEnabled then
                    bs._savedBarAlpha = value / 100
                    -- The Advanced Fade layer rests on this value.
                    if ABAR.AdvancedFadeOn(bs) then ABAR:RefreshCustomFadeForBar(SelectedKey(), false) end
                else
                    WriteSetting("mouseoverAlpha", value / 100, function(keyName) ABAR:ApplyBarOpacity(keyName) end)
                end
                SUpdatePreview()
            end,
        },
        -- Its getter reads the opacity the cog holds, so the Spec Overrides gold
        -- walk marks the slot while Advanced Fade Opacity is overridden.
        {
            type = "dropdown",
            text = "Advanced Fade",
            tooltip = "Fades this bar to Advanced Fade Opacity while one of the conditions you check holds (in combat, with a target, mounted and more). With none checked, Bar Opacity and Visibility alone decide.",
            values = { ["_placeholder"] = "..." },
            order = { "_placeholder" },
            getValue = function()
                local _ = SB().fadeMaxAlpha
                return "_placeholder"
            end,
            setValue = function() end,
        }
    )
    cursorY = cursorY - height
    local fadeRow = row
    do
        local region = row._leftRegion
        CUI.BuildSyncIcon({
            region = region,
            tooltip = "Apply Bar Opacity to all Bars",
            onClick = function()
                local value = SB().mouseoverAlpha or 1
                for _, key in ipairs(GROUP_BAR_ORDER) do
                    ABAR.db.profile.bars[key].mouseoverAlpha = value
                    ABAR:ApplyBarOpacity(key)
                end
                CUI:RefreshPage()
            end,
            isSynced = function()
                local current = SB()
                local value = current.mouseoverEnabled and 1 or (current.mouseoverAlpha or 1)
                for _, key in ipairs(GROUP_BAR_ORDER) do
                    local bs = ABAR.db.profile.bars[key]
                    local bv = bs.mouseoverEnabled and 1 or (bs.mouseoverAlpha or 1)
                    if bv ~= value then return false end
                end
                return true
            end,
            flashTargets = function() return { region } end,
            multiApply = {
                elementKeys = GROUP_BAR_ORDER,
                elementLabels = SHORT_NAMES,
                getCurrentKey = function() return SelectedKey() end,
                onApply = function(checkedKeys)
                    local value = SB().mouseoverAlpha or 1
                    for _, key in ipairs(checkedKeys) do
                        ABAR.db.profile.bars[key].mouseoverAlpha = value
                        ABAR:ApplyBarOpacity(key)
                    end
                    CUI:RefreshPage()
                end,
            },
        })
    end

    if not CUI._prebuilding then
        local region = fadeRow._rightRegion
        if region._control then region._control:Hide() end
        local checkDrop, cbDDRefresh = CUI.BuildVisOptsCBDropdown(
            region,
            170,
            region:GetFrameLevel() + 2,
            fadeItems,
            function(keyName)
                local c = SB().advancedFadeConditions
                return type(c) == "table" and c[keyName] == true
            end,
            function(keyName, value)
                local bs = SB()
                if type(bs.advancedFadeConditions) ~= "table" then bs.advancedFadeConditions = {} end
                bs.advancedFadeConditions[keyName] = value and true or nil
                -- The first condition arms the layer's hooks; the last one
                -- unchecked hands the bar's alpha back.
                local key = SelectedKey()
                ABAR:RefreshAdvancedFadeEnabled(key)
                ABAR:RefreshCustomFadeForBar(key, true)
                CUI:RefreshPage()
            end,
            nil,
            nil,
            nil,
            nil,
            nil,
            {
                disabled = _visBlizzDis,
                disabledTooltip = _visBlizzDis and _VIS_BLIZZ_TIP or nil,
                rawTooltip = true,
            }
        )
        Pix.Point(checkDrop, "RIGHT", region, "RIGHT", -20, 0)
        region._control = checkDrop
        region._lastInline = nil
        CUI.RegisterWidgetRefresh(cbDDRefresh)
        CUI.BuildInlineCog(region, {
            title = "Advanced Fade",
            disabled = AdvancedFadeOff,
            disabledTooltip = AdvancedFadeOffTip,
            rawTooltip = true,
            rows = {
                {
                    type = "slider",
                    label = "Advanced Fade Opacity",
                    min = 0,
                    max = 100,
                    step = 1,
                    tooltip = "The opacity the bar fades to while one of its Advanced Fade conditions holds, above or below Bar Opacity. Visibility still decides whether the bar shows at all.",
                    disabled = AdvancedFadeOff,
                    disabledTooltip = AdvancedFadeOffTip,
                    rawTooltip = true,
                    get = function()
                        return floor(((SB().fadeMaxAlpha ~= nil and SB().fadeMaxAlpha or 1) * 100) + 0.5)
                    end,
                    set = function(value)
                        WriteSetting(
                            "fadeMaxAlpha",
                            value / 100,
                            function(keyName) ABAR:RefreshCustomFadeForBar(keyName, true) end
                        )
                    end,
                },
                {
                    type = "slider",
                    label = "Fade In Time",
                    min = 0.01,
                    max = 2,
                    step = 0.01,
                    tooltip = "Seconds the fade to Advanced Fade Opacity takes.",
                    get = function() return SB().fadeInSpeed or 0.15 end,
                    set = function(value) WriteSetting("fadeInSpeed", value) end,
                },
                {
                    type = "slider",
                    label = "Fade Out Time",
                    min = 0.01,
                    max = 2,
                    step = 0.01,
                    tooltip = "Seconds the fade back to Bar Opacity takes.",
                    get = function() return SB().fadeOutSpeed or 0.15 end,
                    set = function(value) WriteSetting("fadeOutSpeed", value) end,
                },
            },
        })
        CUI.BuildSyncIcon({
            region = region,
            tooltip = "Apply Advanced Fade to all Bars",
            onClick = function() ApplyAdvancedFadeTo(GROUP_BAR_ORDER) end,
            isSynced = AdvancedFadeSynced,
            flashTargets = function() return { region } end,
            multiApply = {
                elementKeys = GROUP_BAR_ORDER,
                elementLabels = SHORT_NAMES,
                getCurrentKey = function() return SelectedKey() end,
                onApply = ApplyAdvancedFadeTo,
            },
        })
    end

    -- Toggle Action Bar beside Always Show Buttons; a visibility-only bar has no
    -- toggle keybind, so Always Show Buttons sits alone there.
    local alwaysShowCfg = {
        type = "toggle",
        text = "Always Show Buttons",
        getValue = function()
            local value = ReadSetting("alwaysShowButtons")
            if value == nil then return true end
            return value
        end,
        setValue = function(value)
            WriteSetting("alwaysShowButtons", value, function(keyName)
                ABAR:ApplyAlwaysShowButtons(keyName)
                ABAR:ApplyPaddingForBar(keyName)
                ABAR:ApplyBackgroundForBar(keyName)
            end)
            SUpdatePreview()
        end,
        tooltip = "Show button backgrounds even if a spell is not assigned to that slot.",
    }
    if visOnly then
        _, height = W:DualRow(hostFrame, cursorY, alwaysShowCfg, CUI.BlankRowCfg())
        cursorY = cursorY - height
    else
        local toggleRow
        toggleRow, height =
            W:DualRow(hostFrame, cursorY, { type = "label", text = "Toggle Action Bar" }, alwaysShowCfg)
        cursorY = cursorY - height
        -- "Toggle Action Bar" keybind: bound key flips the bar shown/hidden at runtime
        -- without writing saved visibility. Enabled only for Always/Never; out of combat
        -- only. The button takes the slot its label names.
        do
            local region = toggleRow._leftRegion
            local kbBtn, refresh = CUI.BuildKeybindButton(region, {
                w = 126,
                h = 29,
                level = 4,
                get = function() return SB().toggleVisKey end,
                set = function(value)
                    -- Spec Overrides: the slot is read before the write, as
                    -- a rebuild may dress this row again for another setting.
                    local snap = CUI._SOAttribution(region)
                    SB().toggleVisKey = value
                    ABAR:RebuildVisToggleBindings()
                    CUI._NotifySettingWrite(region, snap)
                end,
                disabled = function()
                    local value = SB().barVisibility or "always"
                    return value ~= "always" and value ~= "never"
                end,
                disabledTip = "Visibility set to Always or Never",
                tooltip = "Toggling an action bar is only available out of combat\n\nLeft-click to set a keybind.\nRight-click to unbind.",
            })
            Pix.Point(kbBtn, "RIGHT", region, "RIGHT", -20, 0)
            CUI.RegisterWidgetRefresh(refresh)

            -- Spec Overrides capture: bespoke widget opts in with a synthetic accessor (left half is a plain label cfg, no get/set).
            CUI.AddCaptureAccessor(region, {
                type = "keybind",
                text = "Toggle Action Bar",
                getValue = function() return SB().toggleVisKey end,
                setValue = function(value)
                    SB().toggleVisKey = value
                    ABAR:RebuildVisToggleBindings()
                    refresh()
                end,
            })
        end
    end

    -----------------------------------------------------------------------
    --  LAYOUT  (hidden when visibility-only)
    -----------------------------------------------------------------------
    if not visOnly then
        _, height = W:SectionHeader(hostFrame, SECTION_LAYOUT, cursorY)
        cursorY = cursorY - height

        -- Icon Spacing's search entry also answers to "Button Spacing".
        IndexChecklistRow("Icon Spacing", "Button Spacing", {})
        local iconSizeRow
        iconSizeRow, height = W:DualRow(hostFrame, cursorY, {
            type = "slider",
            text = "Icon Size",
            min = 16,
            max = 120,
            step = 1,
            -- Every style sizes from this slider (stock styles scale Blizzard's
            -- native-size button to it); only a size match locks it.
            disabled = function()
                local keyName = SelectedKey()
                if CUI.GetWidthMatchTarget and CUI.GetWidthMatchTarget(keyName) then return true end
                if CUI.GetHeightMatchTarget and CUI.GetHeightMatchTarget(keyName) then
                    return true
                end
                return false
            end,
            disabledTooltip = function()
                local keyName = SelectedKey()
                local wt = CUI.GetWidthMatchTarget and CUI.GetWidthMatchTarget(keyName)
                local ht = CUI.GetHeightMatchTarget and CUI.GetHeightMatchTarget(keyName)
                local target = wt or ht
                if target then
                    local name = (CUI.GetBarLabel and CUI.GetBarLabel(target)) or target
                    return CUI.Lf("Size matched to %1$s. Unmatch in Edit Layout to edit.", name)
                end
                return nil
            end,
            rawTooltip = true,
            getValue = function()
                local barCfg = SB()
                if barCfg.buttonWidth and barCfg.buttonWidth > 0 then return barCfg.buttonWidth end
                local details = BAR_LOOKUP[SelectedKey()]
                local btn1 = FirstBarButton(SelectedKey())
                return btn1 and math.floor((btn1:GetWidth() or 36) + 0.5) or 36
            end,
            setValue = function(value)
                SB().buttonWidth = value
                SB().buttonHeight = value
                SB()._matchExtraPixels = nil
                SB()._matchExtraPixelsH = nil
                ABAR:ApplyButtonSizeForBar(SelectedKey())
                SUpdatePreviewAndResize()
                CUI:RefreshPage()
            end,
        }, {
            type = "slider",
            pixel = true,
            text = "Icon Spacing",
            min = -10,
            max = 20,
            step = 1,
            getValue = function() return SettingOr("buttonPadding", 2) end,
            setValue = function(value)
                WriteSetting("buttonPadding", value, function(keyName) ABAR:ApplyPaddingForBar(keyName) end)
                SUpdatePreview()
            end,
        })
        cursorY = cursorY - height
        do
            local region = iconSizeRow._leftRegion
            CUI.BuildSyncIcon({
                region = region,
                tooltip = "Apply Icon Size to all Bars",
                onClick = function()
                    local barCfg = SB()
                    local details = BAR_LOOKUP[SelectedKey()]
                    local btn1 = FirstBarButton(SelectedKey())
                    local value = (barCfg.buttonWidth and barCfg.buttonWidth > 0) and barCfg.buttonWidth
                        or (btn1 and math.floor((btn1:GetWidth() or 36) + 0.5))
                        or 36
                    for _, key in ipairs(GROUP_BAR_ORDER) do
                        ABAR.db.profile.bars[key].buttonWidth = value
                        ABAR.db.profile.bars[key].buttonHeight = value
                        ABAR:ApplyButtonSizeForBar(key)
                    end
                    CUI:RefreshPage()
                end,
                isSynced = function()
                    local barCfg = SB()
                    local details = BAR_LOOKUP[SelectedKey()]
                    local btn1 = FirstBarButton(SelectedKey())
                    local value = (barCfg.buttonWidth and barCfg.buttonWidth > 0) and barCfg.buttonWidth
                        or (btn1 and math.floor((btn1:GetWidth() or 36) + 0.5))
                        or 36
                    for _, key in ipairs(GROUP_BAR_ORDER) do
                        local ks = ABAR.db.profile.bars[key]
                        local kv = (ks.buttonWidth and ks.buttonWidth > 0) and ks.buttonWidth or value
                        if kv ~= value then return false end
                    end
                    return true
                end,
                flashTargets = function() return { region } end,
                multiApply = {
                    elementKeys = GROUP_BAR_ORDER,
                    elementLabels = SHORT_NAMES,
                    getCurrentKey = function() return SelectedKey() end,
                    onApply = function(checkedKeys)
                        local barCfg = SB()
                        local details = BAR_LOOKUP[SelectedKey()]
                        local btn1 = FirstBarButton(SelectedKey())
                        local value = (barCfg.buttonWidth and barCfg.buttonWidth > 0) and barCfg.buttonWidth
                            or (btn1 and math.floor((btn1:GetWidth() or 36) + 0.5))
                            or 36
                        for _, key in ipairs(checkedKeys) do
                            ABAR.db.profile.bars[key].buttonWidth = value
                            ABAR.db.profile.bars[key].buttonHeight = value
                            ABAR:ApplyButtonSizeForBar(key)
                        end
                        CUI:RefreshPage()
                    end,
                },
            })
        end
        do
            local region = iconSizeRow._rightRegion
            CUI.BuildSyncIcon({
                region = region,
                tooltip = "Apply Icon Spacing to all Bars",
                onClick = function()
                    local value = SB().buttonPadding or 2
                    for _, key in ipairs(GROUP_BAR_ORDER) do
                        ABAR.db.profile.bars[key].buttonPadding = value
                        ABAR:ApplyPaddingForBar(key)
                    end
                    CUI:RefreshPage()
                end,
                isSynced = function()
                    local value = SB().buttonPadding or 2
                    for _, key in ipairs(GROUP_BAR_ORDER) do
                        if (ABAR.db.profile.bars[key].buttonPadding or 2) ~= value then return false end
                    end
                    return true
                end,
                flashTargets = function() return { region } end,
                multiApply = {
                    elementKeys = GROUP_BAR_ORDER,
                    elementLabels = SHORT_NAMES,
                    getCurrentKey = function() return SelectedKey() end,
                    onApply = function(checkedKeys)
                        local value = SB().buttonPadding or 2
                        for _, key in ipairs(checkedKeys) do
                            ABAR.db.profile.bars[key].buttonPadding = value
                            ABAR:ApplyPaddingForBar(key)
                        end
                        CUI:RefreshPage()
                    end,
                },
            })
        end

        row, height = W:DualRow(hostFrame, cursorY, {
            type = "slider",
            text = "Number of Icons",
            min = 1,
            max = 12,
            step = 1,
            disabled = function()
                local details = BAR_LOOKUP[SelectedKey()]
                return details and details.isStance
            end,
            getValue = function()
                local value = ReadSetting("overrideNumIcons")
                if value and value > 0 then return value end
                local barCfg = SB()
                if barCfg and barCfg.numIcons and barCfg.numIcons > 0 then return barCfg.numIcons end
                return 12
            end,
            setValue = function(value)
                WriteSetting("overrideNumIcons", value, function(keyName) ABAR:ApplyIconRowOverrides(keyName) end)
                SUpdatePreviewAndResize()
            end,
        }, {
            type = "slider",
            text = "Number of Rows",
            min = 1,
            max = 12,
            step = 1,
            getValue = function()
                local value = ReadSetting("overrideNumRows")
                if value and value > 0 then return value end
                local barCfg = SB()
                if barCfg and barCfg.numRows and barCfg.numRows > 0 then return barCfg.numRows end
                return 1
            end,
            setValue = function(value)
                WriteSetting("overrideNumRows", value, function(keyName) ABAR:ApplyIconRowOverrides(keyName) end)
                SUpdatePreviewAndResize()
            end,
        })
        cursorY = cursorY - height
        do
            local region = row._leftRegion
            CUI.BuildSyncIcon({
                region = region,
                tooltip = "Apply Number of Icons to all Bars",
                onClick = function()
                    local value = SB().overrideNumIcons or 12
                    for _, key in ipairs(GROUP_BAR_ORDER) do
                        ABAR.db.profile.bars[key].overrideNumIcons = value
                        ABAR:ApplyIconRowOverrides(key)
                    end
                    CUI:RefreshPage()
                end,
                isSynced = function()
                    local value = SB().overrideNumIcons or 12
                    for _, key in ipairs(GROUP_BAR_ORDER) do
                        if (ABAR.db.profile.bars[key].overrideNumIcons or 12) ~= value then return false end
                    end
                    return true
                end,
                flashTargets = function() return { region } end,
                multiApply = {
                    elementKeys = GROUP_BAR_ORDER,
                    elementLabels = SHORT_NAMES,
                    getCurrentKey = function() return SelectedKey() end,
                    onApply = function(checkedKeys)
                        local value = SB().overrideNumIcons or 12
                        for _, key in ipairs(checkedKeys) do
                            ABAR.db.profile.bars[key].overrideNumIcons = value
                            ABAR:ApplyIconRowOverrides(key)
                        end
                        CUI:RefreshPage()
                    end,
                },
            })
        end
        do
            local region = row._rightRegion
            CUI.BuildSyncIcon({
                region = region,
                tooltip = "Apply Number of Rows to all Bars",
                onClick = function()
                    local value = SB().overrideNumRows or 1
                    for _, key in ipairs(GROUP_BAR_ORDER) do
                        ABAR.db.profile.bars[key].overrideNumRows = value
                        ABAR:ApplyIconRowOverrides(key)
                    end
                    CUI:RefreshPage()
                end,
                isSynced = function()
                    local value = SB().overrideNumRows or 1
                    for _, key in ipairs(GROUP_BAR_ORDER) do
                        if (ABAR.db.profile.bars[key].overrideNumRows or 1) ~= value then return false end
                    end
                    return true
                end,
                flashTargets = function() return { region } end,
                multiApply = {
                    elementKeys = GROUP_BAR_ORDER,
                    elementLabels = SHORT_NAMES,
                    getCurrentKey = function() return SelectedKey() end,
                    onApply = function(checkedKeys)
                        local value = SB().overrideNumRows or 1
                        for _, key in ipairs(checkedKeys) do
                            ABAR.db.profile.bars[key].overrideNumRows = value
                            ABAR:ApplyIconRowOverrides(key)
                        end
                        CUI:RefreshPage()
                    end,
                },
            })
        end
        do
            local rightRegion = row._rightRegion
            local isVert = SettingOr("orientation", "horizontal") == "vertical"
            local growDirValues, growDirOrder
            if isVert then
                growDirValues = { up = "Up", down = "Down", center = "Centered" }
                growDirOrder = { "up", "down", "center" }
            else
                growDirValues = { left = "Left", right = "Right", center = "Centered" }
                growDirOrder = { "left", "right", "center" }
            end
            CUI.BuildInlineCog(rightRegion, {
                title = "Row Settings",
                anchorTo = rightRegion._control,
                rows = {
                    {
                        type = "dropdown",
                        label = "Grow Direction",
                        values = growDirValues,
                        order = growDirOrder,
                        get = function()
                            local val = SettingOr("growDirection", "up")
                            if not growDirValues[val] then return "center" end
                            return val
                        end,
                        set = function(value)
                            WriteSetting(
                                "growDirection",
                                value,
                                function(keyName) ABAR:ApplyIconRowOverrides(keyName) end
                            )
                            SUpdatePreviewAndResize()
                        end,
                    },
                },
            })
        end

        -- Icon Order "default"/"reversed" map onto the legacy reverseIconOrder boolean (kept in
        -- sync for older readers); corner values place button 1 in that corner of the grid.
        do
            local orientRow
            orientRow, height = W:DualRow(hostFrame, cursorY, {
                type = "toggle",
                text = "Vertical Orientation",
                disabled = function() return not ABAR:BarSupportsOrientation(SelectedKey()) end,
                disabledTooltip = "This option is not supported for this bar type",
                rawTooltip = true,
                getValue = function() return not ABAR:GetOrientationForBar(SelectedKey()) end,
                setValue = function(value)
                    ABAR:SetOrientationForBar(SelectedKey(), not value)
                    SUpdatePreviewAndResize()
                    CUI:RefreshPage()
                end,
            }, {
                type = "dropdown",
                text = "Icon Order",
                values = {
                    default = "Default",
                    reversed = "Reversed",
                    TOPLEFT = "Top Left",
                    TOPRIGHT = "Top Right",
                    BOTTOMLEFT = "Bottom Left",
                    BOTTOMRIGHT = "Bottom Right",
                },
                order = { "default", "reversed", "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" },
                getValue = function()
                    local value = SettingOr("iconOrder", nil)
                    if value == nil then
                        value = SettingOr("reverseIconOrder", false) and "reversed" or "default"
                    end
                    return value
                end,
                setValue = function(value)
                    SettingsDB().reverseIconOrder = (value == "reversed")
                    WriteSetting("iconOrder", value, function(keyName) ABAR:ApplyIconRowOverrides(keyName) end)
                    SUpdatePreviewAndResize()
                end,
            })
            cursorY = cursorY - height
            do
                local region = orientRow._leftRegion
                CUI.BuildSyncIcon({
                    region = region,
                    tooltip = "Apply Orientation to all Bars",
                    onClick = function()
                        local isHoriz = ABAR:GetOrientationForBar(SelectedKey())
                        for _, key in ipairs(GROUP_BAR_ORDER) do
                            if ABAR:BarSupportsOrientation(key) then
                                ABAR:SetOrientationForBar(key, isHoriz)
                            end
                        end
                        CUI:RefreshPage()
                    end,
                    isSynced = function()
                        local isHoriz = ABAR:GetOrientationForBar(SelectedKey())
                        for _, key in ipairs(GROUP_BAR_ORDER) do
                            if
                                ABAR:BarSupportsOrientation(key)
                                and ABAR:GetOrientationForBar(key) ~= isHoriz
                            then
                                return false
                            end
                        end
                        return true
                    end,
                    flashTargets = function() return { region } end,
                    multiApply = {
                        elementKeys = GROUP_BAR_ORDER,
                        elementLabels = SHORT_NAMES,
                        getCurrentKey = function() return SelectedKey() end,
                        onApply = function(checkedKeys)
                            local isHoriz = ABAR:GetOrientationForBar(SelectedKey())
                            for _, key in ipairs(checkedKeys) do
                                if ABAR:BarSupportsOrientation(key) then
                                    ABAR:SetOrientationForBar(key, isHoriz)
                                end
                            end
                            CUI:RefreshPage()
                        end,
                    },
                })
            end
        end
    end -- if not visOnly

    return cursorY
end

-- Used by CUI_ActionBars_Options.lua
mod.ABO_BuildBarVisibilityLayout = BuildBarVisibilityLayout
