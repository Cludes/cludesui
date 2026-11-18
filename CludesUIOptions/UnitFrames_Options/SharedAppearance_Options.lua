if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  UnitFrames_Options\SharedAppearance_Options.lua
--  Unit Frames options: Display, Portrait, Text Bar and Extras sections of the
--  shared (player/target/focus) settings. Definitions only; shared helpers
--  come from ns._UFO_OptEnv, the page accessors from ctx (both filled by
--  CUI_UnitFrames_Options.lua).
-------------------------------------------------------------------------------
local mod = CludesUI._ModuleNS["CludesUIUnitFrames"]
if not mod then
    return
end -- module disabled: no options page

-- Page reuse: the frames this file builds under a kept page go through the
-- options frame pool (CludesUI_FramePool.lua), which hands the next build
-- the previous build's frames reset to new; on any other parent it is the
-- plain CreateFrame.
local CreateFrame = CludesUI._Pool.CreateFrame

-- A textured border's offsets and shifts, which travel with its style.
local BORDER_TEX_KEYS =
    { "borderTextureOffset", "borderTextureOffsetY", "borderTextureShiftX", "borderTextureShiftY" }

-- A colour copied as a table of its own (r, g, b); nothing when there is none.
local function CopyColor(t, key, c)
    if c then
        t[key] = { r = c.r, g = c.g, b = c.b }
    end
end

-- The sync icon of a per-unit setting ("Apply <label> to all Frames"): it
-- copies the selected unit's setting to every main frame, or to the frames
-- ticked in its menu, and reads as synced while they all agree.
-- opts.copy(t, from) writes the setting from the selected unit's table into
-- another unit's t; opts.same(t, from) says whether t already agrees (both
-- get t's unit token third, for a setting stored under another key on one
-- frame). A
-- single value needs neither: opts.key, unset reading as opts.default (a
-- function for a default that is looked up). opts.self also writes the
-- selected unit itself (pinning its default). opts.units narrows the frames
-- (all main frames by default). opts.after runs once the values moved (by
-- default the frames reload and the page repaints). A setting that already
-- has its own mover passes opts.applyTo(list), which does the whole copy and
-- repaint, and opts.isSynced(). Shared by every Unit Frames options file.
function mod.UFO_UnitSync(rgn, label, opts)
    local env = mod._UFO_OptEnv
    local units, unitDB, state = opts.units or env.GROUP_UNIT_ORDER, env.UNIT_DB_MAP, env.optState
    local copy, same = opts.copy, opts.same
    if not copy then
        local key, default, unsetOnly = opts.key, opts.default, opts.unsetOnly
        -- The default stands in for an unset value, and for false unless
        -- opts.unsetOnly (a stored false is then a value of its own).
        local function Value(t)
            local v = t[key]
            if v == nil or (v == false and not unsetOnly) then
                if type(default) == "function" then
                    return default()
                end
                return default
            end
            return v
        end
        copy = function(t, from)
            t[key] = Value(from)
        end
        same = function(t, from)
            return Value(t) == Value(from)
        end
    end
    -- The menu never lists the selected unit, so only the All link can reach it.
    local Copy = opts.applyTo
        or function(list, includeSelf)
            local self = state.selectedUnit
            local from = unitDB[self]()
            for _, unit in ipairs(list) do
                if includeSelf or unit ~= self then
                    copy(unitDB[unit](), from, unit)
                end
            end
            if opts.after then
                opts.after(list)
            else
                env.ReloadAndUpdate()
                CludesUI:RefreshPage()
            end
        end
    CludesUI.BuildSyncIcon({
        region = rgn,
        tooltip = "Apply " .. label .. " to all Frames",
        onClick = function()
            Copy(units, opts.self)
        end,
        isSynced = opts.isSynced or function()
            local from = unitDB[state.selectedUnit]()
            for _, unit in ipairs(units) do
                if not same(unitDB[unit](), from, unit) then
                    return false
                end
            end
            return true
        end,
        flashTargets = function()
            return { rgn }
        end,
        -- opts.noMenu: the All link only (no Multiple menu).
        multiApply = not opts.noMenu and {
            elementKeys = units,
            elementLabels = env.SHORT_LABELS,
            getCurrentKey = function()
                return state.selectedUnit
            end,
            onApply = function(checked)
                Copy(checked, true)
            end,
        } or nil,
    })
end

-- The automatic / custom swatch pair left of a colour row's control. The
-- automatic swatch shows the class or power colour and picks it; the custom
-- swatch picks its own colour, opening its picker once it is the one in use.
-- The one not in use dims. opts: store() the settings table; flag (true = the
-- automatic colour, unset reads as flagDefault); autoGet() and autoTip;
-- colorKey, colorDefault ({ r, g, b }) and customTip; seed stores
-- colorDefault on the first switch to custom (unset, the bar would keep the
-- automatic colour); apply() runs after any write (a flag write also repaints
-- the page). Shared by every Unit Frames options file.
function mod.UFO_SwatchPair(rgn, opts)
    local env = mod._UFO_OptEnv
    local store, flag, apply = opts.store, opts.flag, opts.apply
    local function Auto()
        local v = store()[flag]
        if v == nil then
            return opts.flagDefault
        end
        return v
    end
    local function SetAuto(on)
        store()[flag] = on
        apply()
        CludesUI:RefreshPage()
    end
    local function Add(get, set, tip, onClick, isAuto)
        local sw, update = CludesUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5, get, set, false, 20)
        sw._eabOrigClick = sw:GetScript("OnClick")
        sw:SetScript("OnClick", onClick)
        sw:HookScript("OnEnter", function()
            CludesUI.ShowWidgetTooltip(sw, tip)
        end)
        sw:HookScript("OnLeave", function()
            CludesUI.HideWidgetTooltip()
        end)
        env.PP.Point(sw, "RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
        rgn._lastInline = sw
        local function Dim()
            sw:SetAlpha(((Auto() and true or false) == isAuto) and 1 or 0.3)
        end
        env.RegisterWidgetRefresh(function()
            update()
            Dim()
        end)
        Dim()
    end
    Add(opts.autoGet, function() end, opts.autoTip, function()
        SetAuto(true)
    end, true)
    local def = opts.colorDefault
    Add(
        function()
            local c = store()[opts.colorKey] or def
            return c.r, c.g, c.b
        end,
        function(r, g, b)
            store()[opts.colorKey] = { r = r, g = g, b = b }
            apply()
        end,
        opts.customTip,
        function(self)
            if Auto() then
                if opts.seed and store()[opts.colorKey] == nil then
                    store()[opts.colorKey] = { r = def.r, g = def.g, b = def.b }
                end
                SetAuto(false)
            elseif self._eabOrigClick then
                self._eabOrigClick(self)
            end
        end,
        false
    )
end

-- The sync icon of a text choice (a Text Bar slot, Power Text): the choice
-- (default when unset), with its own format when the choice is Custom (any
-- other choice leaves the format alone).
function mod.UFO_FormatSync(rgn, label, content, format, default)
    mod.UFO_UnitSync(rgn, label, {
        self = true,
        copy = function(t, from)
            local v = from[content] or default
            t[content] = v
            if v == "custom" then
                t[format] = from[format]
            end
        end,
        same = function(t, from)
            local v = from[content] or default
            return (t[content] or default) == v
                and (v ~= "custom" or (t[format] or "") == (from[format] or ""))
        end,
    })
end
local function TextSlotSync(rgn, label, slot)
    mod.UFO_FormatSync(rgn, label, "btb" .. slot .. "Content", "btb" .. slot .. "CustomFormat", "none")
end

function mod.UFO_BuildDisplaySection(hostFrame, posY, context)
    local environ = mod._UFO_OptEnv
    local AttachFrameSourceCog, BuildBarTexDropdown, BuildInactiveNotice, CLASS_FULL_COORDS =
        environ.AttachFrameSourceCog,
        environ.BuildBarTexDropdown,
        environ.BuildInactiveNotice,
        environ.CLASS_FULL_COORDS
    local CLASS_FULL_SPRITE_BASE, GROUP_UNIT_ORDER, Pix, PromptReloadIfUnspawned =
        environ.CLASS_FULL_SPRITE_BASE, environ.GROUP_UNIT_ORDER, environ.PP, environ.PromptReloadIfUnspawned
    local ReloadAndUpdate, UNIT_DB_MAP, UpdatePreview =
        environ.ReloadAndUpdate, environ.UNIT_DB_MAP, environ.UpdatePreview
    local saved, frameList, optionState, portraitArtValues =
        environ.db, environ.frames, environ.optState, environ.portraitArtValues
    local TexBgRowCfg = environ.TexBgRowCfg
    local W, SDB, SGet, SSet = context.W, context.SDB, context.SGet, context.SSet
    local SVal = context.SVal
    local _, hgt

    -------------------------------------------------------------------
    --  DISPLAY
    -------------------------------------------------------------------
    local sharedDisplayHeader
    sharedDisplayHeader, hgt = W:SectionHeader(hostFrame, "DISPLAY", posY)
    posY = posY - hgt
    -- The Move in Unlock Mode button on the unit's first section: the selected
    -- unit's own mover, which exists only for the CludesUI frame source (a
    -- Blizzard or hidden frame has none), so the button explains itself otherwise.
    CludesUI.BuildSectionUnlockJump(sharedDisplayHeader, {
        key = function()
            return optionState.selectedUnit
        end,
        disabled = function()
            return mod.GetUnitFrameSource(optionState.selectedUnit) ~= "cui"
        end,
        disabledTooltip = "This option requires the CludesUI Frame Source.",
    })
    posY = CludesUI.BlizzStyle.Note(hostFrame, posY, "unitframes")

    -- Wire class theme subnav callbacks (per-unit context)
    do
        local sn = portraitArtValues["class"].subnav
        sn.onSelect = function(styleKey)
            local d = UNIT_DB_MAP[optionState.selectedUnit]()
            d.portraitMode = "class"
            d.classThemeStyle = styleKey
            d.showPortrait = true
            -- The Art Style's leave-3D resets: Shape None and the Inside
            -- positions are 3D-only.
            if d.detachedPortraitShape == "none" then
                d.detachedPortraitShape = "portrait"
            end
            local side = d.portraitSide
            if side == "insideleft" or side == "insideright" or side == "insidecenter" then
                d.portraitSide = "left"
            end
            ReloadAndUpdate()
            UpdatePreview()
            C_Timer.After(0, function()
                local rl = CludesUI._widgetRefreshList
                if rl then
                    for ri = 1, #rl do
                        rl[ri]()
                    end
                end
            end)
        end
        sn.icon = function(styleKey)
            local _, classToken = UnitClass("player")
            if not classToken then
                return nil
            end
            local coords = CLASS_FULL_COORDS[classToken]
            if not coords then
                return nil
            end
            return CLASS_FULL_SPRITE_BASE .. styleKey .. ".tga", coords[1], coords[2], coords[3], coords[4]
        end
    end

    -- Row 1: Visibility | Visibility Options. Group-axis check for the legacy
    -- showInRaid/showInParty/showSolo trio: only group items constrain it
    -- (unconstrained = true), matching ToggleFrame's group gating for multi-select.
    local function GroupAxisPasses(vm, inRaid, inParty)
        -- A checked Hide lane vetoes whatever the Show lanes say, in both match
        -- modes; both lanes of one row at once counts as unconstrained.
        if
            (vm.hide_in_raid and not vm.in_raid and inRaid)
            or (vm.hide_in_party and not vm.in_party and inParty)
            or (vm.hide_solo and not vm.solo and not inRaid and not inParty)
        then
            return false
        end
        local g1, g2, g3 = vm.in_raid, vm.in_party, vm.solo
        if not (g1 or g2 or g3) or (g1 and g2 and g3) then
            return true
        end
        if g1 and inRaid then
            return true
        end
        if g2 and inParty then
            return true
        end
        if g3 and not inRaid and not inParty then
            return true
        end
        return false
    end
    -- Keeps the boolean trio in sync with the effective selection; the legacy
    -- branch leaves the trio untouched for in_combat/out_of_combat/mouseover.
    local function SyncUnitVisBooleans(s)
        local vm = s.visibilityModes
        if type(vm) == "table" and next(vm) then
            s.showInRaid = GroupAxisPasses(vm, true, false)
            s.showInParty = GroupAxisPasses(vm, false, true)
            s.showSolo = GroupAxisPasses(vm, false, false)
            return
        end
        local v = s.barVisibility or "always"
        if v == "always" then
            s.showInRaid = true
            s.showInParty = true
            s.showSolo = true
        elseif v == "never" then
            s.showInRaid = false
            s.showInParty = false
            s.showSolo = false
        elseif v == "in_raid" then
            s.showInRaid = true
            s.showInParty = false
            s.showSolo = false
        elseif v == "in_party" then
            s.showInRaid = false
            s.showInParty = true
            s.showSolo = false
        elseif v == "solo" then
            s.showInRaid = false
            s.showInParty = false
            s.showSolo = true
        end
    end
    local visRow
    visRow, hgt = CludesUI.BuildVisibilityRow(
        W,
        hostFrame,
        posY,
        {
            getStore = function()
                return UNIT_DB_MAP[optionState.selectedUnit]()
            end,
            legacyKey = "barVisibility",
            caps = { partyIncludesRaid = false, luaDragonriding = true },
            refreshPageArg = true,
            -- Visibility is a RUNTIME axis and never touches enabledFrames: that
            -- key decides whether the frame is built at all, once, at login, so a
            -- Spec Override carrying "never" used to leave the frame uncreated for
            -- the session with no way back but a /reload. "never" is hidden by the
            -- visibility pass instead (ns.UpdateFrameVisibility), which reverses.
            applyScalarFn = function(s, mode)
                s.barVisibility = mode
            end,
            onChanged = function()
                local s = UNIT_DB_MAP[optionState.selectedUnit]()
                SyncUnitVisBooleans(s)
                if mod.UpdateFrameVisibility then
                    mod.UpdateFrameVisibility()
                end
                ReloadAndUpdate()
                -- Un-hiding a frame whose CUI frame isn't spawned this session
                -- (source was Blizzard/Hidden at login) needs a /reload. The EFFECTIVE
                -- value decides: an override replaces the shared scalar, so an override
                -- of Always on a unit whose shared value is "never" un-hides it too.
                local visOv = CludesUI.VisOverrideValue(s)
                if (visOv or s.barVisibility or "always") ~= "never" then
                    PromptReloadIfUnspawned({ optionState.selectedUnit })
                end
            end,
            onOptionChanged = function()
                if mod.UpdateFrameVisibility then
                    mod.UpdateFrameVisibility()
                end
            end,
        },
        -- Show Nicknames moved up from the section's old trailing half-row into the
        -- slot the Visibility Options dropdown left behind, so neither row is half
        -- empty. ONE global toggle for all main frames (default OFF, not per-unit,
        -- hence db.profile). Gates ns.ResolveUnitNickname: off = raw names, on =
        -- provider nicknames.
        {
            type = "toggle",
            text = "Show Nicknames",
            tooltip = "Show player nicknames from supported addons instead of character names on your main frames.",
            getValue = function()
                return saved.profile.showNicknames or false
            end,
            setValue = function(v)
                saved.profile.showNicknames = v
                if mod.RefreshAllUnitNames then
                    mod.RefreshAllUnitNames()
                end
            end,
        }
    )
    posY = posY - hgt

    -- Inline cog on Visibility: ONE popup hosting Frame Source (CludesUI /
    -- Blizzard Default) plus Out of Combat fade. Hiding stays on the Visibility
    -- dropdown ("Never Show"). Fade dims the frame via ns.ResolveFrameAlpha in
    -- UpdateFrameVisibility (reacts to the regen path); reuses CDM fade strings
    -- for consistency. Fade rows appear only for the CludesUI source.
    local _visSrcIsEui = mod.GetUnitFrameSource(optionState.selectedUnit) == "cui"
    if not CludesUI._prebuilding then
        AttachFrameSourceCog(visRow._leftRegion, optionState.selectedUnit, {
            title = _visSrcIsEui and "Frame Source & Visibility" or "Frame Source",
            cogTooltip = _visSrcIsEui and "Frame Source & Visibility" or "Frame Source",
            extraRows = _visSrcIsEui
                and {
                    {
                        type = "toggle",
                        label = "Show When Health Missing",
                        tooltip = "Shows the frame while this unit is below full health; while enabled, a frame hidden by its visibility setting can still be clicked.",
                        disabled = function()
                            return InCombatLockdown()
                        end,
                        disabledTooltip = "Change health visibility out of combat",
                        get = function()
                            return SVal("showWhenHealthMissing", false) == true
                        end,
                        set = function(v)
                            SSet("showWhenHealthMissing", v)
                            if mod.UpdateFrameVisibility then
                                mod.UpdateFrameVisibility()
                            end
                        end,
                    },
                    {
                        type = "toggle",
                        label = "Fade Out of Combat",
                        tooltip = "Fades the entire frame (portrait, health and power bars, text) while out of combat.",
                        get = function()
                            return SVal("oocFadeEnabled", false) == true
                        end,
                        set = function(v)
                            SSet("oocFadeEnabled", v)
                            if mod.UpdateFrameVisibility then
                                mod.UpdateFrameVisibility()
                            end
                        end,
                    },
                    {
                        type = "slider",
                        label = "Out of Combat Alpha",
                        min = 0,
                        max = 100,
                        step = 1,
                        disabled = function()
                            return not SVal("oocFadeEnabled", false)
                        end,
                        disabledTooltip = "Enable Fade Out of Combat first",
                        rawTooltip = true,
                        get = function()
                            return math.floor((SVal("oocAlpha", 0.5)) * 100 + 0.5)
                        end,
                        set = function(v)
                            SSet("oocAlpha", v / 100)
                            if mod.UpdateFrameVisibility then
                                mod.UpdateFrameVisibility()
                            end
                        end,
                    },
                },
        })
    end

    -- Non-CUI source: no CUI frame spawned, so nothing below applies. Keep the
    -- Visibility row (hosts the Frame Source cog + "Never Show" way back), grey
    -- it for Blizzard source, and show a one-line notice in place of settings.
    if not CludesUI._prebuilding then
        local srcNow = mod.GetUnitFrameSource(optionState.selectedUnit)
        if srcNow ~= "cui" then
            -- The right slot used to hold this unit's Visibility Options and was hidden
            -- here because it is meaningless for a Blizzard frame. It now holds the
            -- profile-wide Show Nicknames toggle, which stays live for every source.
            if srcNow == "blizzard" then
                -- Visibility modes only drive the CUI frame: block the dropdown
                -- (the cog stays live to switch back).
                local ctl = visRow._leftRegion._control
                if visRow._leftRegion._label then
                    visRow._leftRegion._label:SetAlpha(0.3)
                end
                local dis = CreateFrame("Frame", nil, visRow)
                dis:SetPoint("TOPLEFT", ctl, "TOPLEFT", -2, 2)
                dis:SetPoint("BOTTOMRIGHT", ctl, "BOTTOMRIGHT", 2, -2)
                dis:SetFrameLevel(visRow:GetFrameLevel() + 10)
                dis:EnableMouse(true)
                local disTex = dis:CreateTexture(nil, "OVERLAY")
                disTex:SetAllPoints()
                disTex:SetColorTexture(0.062, 0.070, 0.082, 0.7)
                dis:SetScript("OnEnter", function(self)
                    CludesUI.ShowWidgetTooltip(
                        self,
                        CludesUI.DisabledTooltip("the Frame Source to be CludesUI")
                    )
                end)
                dis:SetScript("OnLeave", function()
                    CludesUI.HideWidgetTooltip()
                end)
            end
            return BuildInactiveNotice(hostFrame, posY, srcNow), true
        end
    end

    -- ONE sync icon now that both halves share a control: set-aware for correct
    -- multi-selection compare/copy, and VisFullCopy carries the option booleans too,
    -- plus each target's boolean-trio derivation.
    if not CludesUI._prebuilding then
        mod.UFO_UnitSync(visRow._leftRegion, "Visibility", {
            copy = function(t, from)
                CludesUI.VisFullCopy(t, from, "barVisibility", nil, function(dst, mode)
                    dst.barVisibility = mode
                end)
                SyncUnitVisBooleans(t)
            end,
            same = function(t, from)
                return CludesUI.VisFullEquals(from, "barVisibility", t, "barVisibility")
            end,
            -- A frame shown again that this session never spawned needs a reload.
            after = function(list)
                if mod.UpdateFrameVisibility then
                    mod.UpdateFrameVisibility()
                end
                ReloadAndUpdate()
                CludesUI:RefreshPage(true)
                if (UNIT_DB_MAP[optionState.selectedUnit]().barVisibility or "always") ~= "never" then
                    PromptReloadIfUnspawned(list)
                end
            end,
        })
    end

    -- Row 2: Bar Texture (per-unit + sync) | Dark Mode. healthBarTexture is
    -- per-unit (drives health/power/cast/absorb); db.profile.healthBarTexture is the fallback when unset.
    local barTexRow
    local hbtValues, hbtOrder = BuildBarTexDropdown()
    barTexRow, hgt = W:DualRow(hostFrame, posY, {
        type = "dropdown",
        text = "Bar Texture",
        values = hbtValues,
        order = hbtOrder,
        getValue = function()
            return SVal("healthBarTexture", saved.profile.healthBarTexture or "none")
        end,
        setValue = function(v)
            SSet("healthBarTexture", v)
            UpdatePreview()
            CludesUI:RefreshPage()
        end,
    }, {
        type = "toggle",
        text = "Dark Mode",
        tooltip = "Dark Mode for this frame. Global Settings > Colors switches every frame.",
        getValue = function()
            return mod.UF_DarkThemeOn(SDB())
        end,
        setValue = function(v)
            SSet("darkTheme", v)
            UpdatePreview()
            -- Dark Mode feeds the conditional-override condition.
            CludesUI.Conditions_Recheck()
            CludesUI:RefreshPage()
        end,
    })
    posY = posY - hgt
    -- This toggle IS the Dark Mode condition's input: lock it while a Dark Mode
    -- conditional is edited, or the override could capture a value flipping its own condition.
    if CludesUI.SpecOverrides_AttachEditLock and not CludesUI._prebuilding then
        CludesUI.SpecOverrides_AttachEditLock(
            barTexRow._rightRegion,
            "Dark Mode drives a Dark Mode override condition and can't be changed while editing an override",
            CludesUI.SpecOverrides_DarkCondEditActive
        )
    end
    -- Sync icon: Bar Texture (left region); an unset unit draws the profile's texture.
    if not CludesUI._prebuilding then
        local rgn = barTexRow._leftRegion
        mod.UFO_UnitSync(rgn, "Bar Texture", {
            key = "healthBarTexture",
            default = function()
                return saved.profile.healthBarTexture or "none"
            end,
            after = function()
                ReloadAndUpdate()
                UpdatePreview()
                CludesUI:RefreshPage()
            end,
        })
        -- Textured Background cog (same region, after the sync icon).
        CludesUI.BuildInlineCog(rgn, {
            title = "Texture Settings",
            rows = {
                TexBgRowCfg(function()
                    return UNIT_DB_MAP[optionState.selectedUnit]()
                end, ReloadAndUpdate),
            },
        })
    end

    -- Row 3: Border Style (+ cog) | Border (slider + double inline swatches)
    local sharedScaleBorderRow
    local texValues, texOrder = CludesUI.GetBorderTextureDropdown()
    sharedScaleBorderRow, hgt = W:DualRow(
        hostFrame,
        posY,
        CludesUI.BlizzStyle.Gate("unitframes", {
            type = "dropdown",
            text = "Border Style",
            values = texValues,
            order = texOrder,
            getValue = function()
                return SGet("borderTexture") or "solid"
            end,
            setValue = function(v)
                SSet("borderTexture", v)
                SSet("borderTextureOffset", nil)
                SSet("borderTextureOffsetY", nil)
                SSet("borderTextureShiftX", nil)
                SSet("borderTextureShiftY", nil)
                local _bcol, _bbehind = CludesUI.GetBorderStyleSelectDefaults(v)
                SSet("borderColor", _bcol)
                SSet("borderAlpha", 1)
                SSet("borderBehind", _bbehind)
                local defSz = CludesUI.GetBorderDefaultSize("unitframes", v)
                if defSz then
                    SSet("borderSize", defSz)
                end
                -- A style pick returns the frame to its legacy step; clear a set
                -- exact size (false travels through mirror sync, nil would not).
                if SGet("borderSizePx") then
                    SDB().borderSizePx = false
                end
                ReloadAndUpdate()
                -- The Width / Height Offset row exists only under a textured style.
                CludesUI:RefreshPage(true)
            end,
        }),
        CludesUI.BlizzStyle.Gate(
            "unitframes",
            CludesUI.BorderPxSliderCfg({
                text = "Border Size",
                trackWidth = 120,
                getStep = function()
                    return SVal("borderSize", 1)
                end,
                setStep = function(step)
                    SDB().borderSize = step
                end,
                getTex = function()
                    return SGet("borderTexture") or "solid"
                end,
                getPx = function()
                    return SGet("borderSizePx")
                end,
                setPx = function(v)
                    SDB().borderSizePx = v
                end,
                apply = ReloadAndUpdate,
            })
        )
    )
    posY = posY - hgt
    -- Width Offset | Height Offset: a textured style's outward offsets (a Solid
    -- border has none). The row shows what is drawn: the stored override, else
    -- the texture's default for this size, which keeps seeding until a real edit.
    do
        local bTex = SGet("borderTexture") or "solid"
        if bTex ~= "solid" and bTex ~= "" then
            local ocfgL, ocfgR = CludesUI.BorderOffsetRowCfgs({
                addonKey = "unitframes",
                getTex = function()
                    return SGet("borderTexture") or "solid"
                end,
                getStep = function()
                    return SVal("borderSize", 1)
                end,
                getSizeKey = function()
                    return SVal("borderSize", 1)
                end,
                getPx = function()
                    return SGet("borderSizePx")
                end,
                getX = function()
                    return SGet("borderTextureOffset")
                end,
                setX = function(v)
                    SDB().borderTextureOffset = v
                end,
                getY = function()
                    return SGet("borderTextureOffsetY")
                end,
                setY = function(v)
                    SDB().borderTextureOffsetY = v
                end,
                apply = ReloadAndUpdate,
            })
            _, hgt = W:DualRow(
                hostFrame,
                posY,
                CludesUI.BlizzStyle.Gate("unitframes", ocfgL),
                CludesUI.BlizzStyle.Gate("unitframes", ocfgR)
            )
            posY = posY - hgt
        end
    end
    -- Inline cog for border shift / layering (left region)
    if not CludesUI._prebuilding then
        local rgn = sharedScaleBorderRow._leftRegion
        local cogBtn = CludesUI.BuildInlineCog(rgn, {
            title = "Border Options",
            rows = {
                {
                    type = "slider",
                    label = "Shift X",
                    min = -10,
                    max = 10,
                    step = 1,
                    get = function()
                        local v = SGet("borderTextureShiftX")
                        if v then
                            return v
                        end
                        local texture = SGet("borderTexture") or "solid"
                        local sz = SVal("borderSize", 1)
                        local _, _, dsx = CludesUI.GetBorderDefaults("unitframes", texture, sz)
                        return dsx
                    end,
                    set = function(v)
                        SSet("borderTextureShiftX", v == 0 and nil or v)
                        ReloadAndUpdate()
                    end,
                },
                {
                    type = "slider",
                    label = "Shift Y",
                    min = -10,
                    max = 10,
                    step = 1,
                    get = function()
                        local v = SGet("borderTextureShiftY")
                        if v then
                            return v
                        end
                        local texture = SGet("borderTexture") or "solid"
                        local sz = SVal("borderSize", 1)
                        local _, _, _, dsy = CludesUI.GetBorderDefaults("unitframes", texture, sz)
                        return dsy
                    end,
                    set = function(v)
                        SSet("borderTextureShiftY", v == 0 and nil or v)
                        ReloadAndUpdate()
                    end,
                },
                {
                    type = "toggle",
                    label = "Show Behind",
                    get = function()
                        return SVal("borderBehind", false)
                    end,
                    set = function(v)
                        SSet("borderBehind", v)
                        ReloadAndUpdate()
                        CludesUI:RefreshPage()
                    end,
                },
                -- The style's separator art along the health / power join
                -- (ns.UpdatePowerSeam); only a style with seam art has one.
                {
                    type = "toggle",
                    label = "Power Bar Seam",
                    tooltip = "Draws the border style's seam art between the health bar and an attached power bar.",
                    disabled = function()
                        local place = SVal("powerPosition", "below")
                        return not (
                            CludesUI.GetBorderCompanion(SGet("borderTexture") or "solid", "sepH")
                            and SVal("borderSize", 1) > 0
                            and (place == "above" or place == "below")
                            and SVal("powerHeight", 6) > 0
                        )
                    end,
                    disabledTooltip = "This option requires an attached Power Bar, a Border Size above 0 and a border style with seam art.",
                    rawTooltip = true,
                    get = function()
                        return SVal("borderPowerSeam", false) == true
                    end,
                    set = function(v)
                        SSet("borderPowerSeam", v)
                    end,
                },
            },
        })
        local function UpdateCogVis()
            local texture = SGet("borderTexture") or "solid"
            if texture == "solid" or CludesUI.BlizzStyle.Get("unitframes") then
                cogBtn:Hide()
            else
                cogBtn:Show()
            end
        end
        CludesUI.RegisterWidgetRefresh(UpdateCogVis)
        UpdateCogVis()
    end
    -- Sync icons. Border Style carries what belongs to the style: the texture's
    -- offsets and shifts, layering, colour, alpha and the power seam. Border
    -- carries the size (step, exact pixels and corners) with the texture, its
    -- offsets, colour and the hover highlight. Each compares only what decides
    -- the look it names.
    if not CludesUI._prebuilding then
        mod.UFO_UnitSync(sharedScaleBorderRow._leftRegion, "Border Style", {
            copy = function(t, from)
                t.borderTexture = from.borderTexture or "solid"
                for _, k in ipairs(BORDER_TEX_KEYS) do
                    t[k] = from[k]
                end
                t.borderBehind = from.borderBehind
                CopyColor(t, "borderColor", from.borderColor)
                t.borderAlpha = from.borderAlpha
                t.borderPowerSeam = from.borderPowerSeam
            end,
            same = function(t, from)
                if
                    (t.borderTexture or "solid") ~= (from.borderTexture or "solid")
                    or (t.borderBehind or false) ~= (from.borderBehind or false)
                    or (t.borderPowerSeam == true) ~= (from.borderPowerSeam == true)
                then
                    return false
                end
                for _, k in ipairs(BORDER_TEX_KEYS) do
                    if t[k] ~= from[k] then
                        return false
                    end
                end
                return true
            end,
        })
        mod.UFO_UnitSync(sharedScaleBorderRow._rightRegion, "Border", {
            copy = function(t, from)
                local step, radius = from.borderSize, from.cornerRadius
                if step == nil then
                    step = 1
                end
                if radius == nil then
                    radius = 0
                end
                t.borderSize = step
                t.cornerRadius = radius
                -- A source with all corners, or no exact size, clears a value the
                -- target holds with 15 / false: nil would not travel through
                -- mirror sync. Join off is false for the same reason.
                local mask, px = from.cornerMask, from.borderSizePx
                if mask == nil and t.cornerMask ~= nil then
                    mask = 15
                end
                if px == nil and t.borderSizePx ~= nil then
                    px = false
                end
                t.cornerMask = mask
                t.cornerJoinPower = from.cornerJoinPower == true
                -- Verbatim (string / false / nil): it counts only beside the same step and texture.
                t.borderSizePx = px
                CopyColor(t, "borderColor", from.borderColor)
                if from.borderAlpha then
                    t.borderAlpha = from.borderAlpha
                end
                t.borderTexture = from.borderTexture or "solid"
                for _, k in ipairs(BORDER_TEX_KEYS) do
                    t[k] = from[k]
                end
                CopyColor(t, "highlightColor", from.highlightColor)
                if from.highlightAlpha then
                    t.highlightAlpha = from.highlightAlpha
                end
            end,
            same = function(t, from)
                local step, radius = from.borderSize, from.cornerRadius
                if step == nil then
                    step = 1
                end
                if radius == nil then
                    radius = 0
                end
                local tex = from.borderTexture or "solid"
                -- Exact sizes compare as drawn (a cleared or stale value equals none).
                return (t.borderSize or 1) == step
                    and (t.borderTexture or "solid") == tex
                    and CludesUI.BorderPx(t.borderSizePx, step, tex) == CludesUI.BorderPx(
                        from.borderSizePx,
                        step,
                        tex
                    )
                    and (t.cornerRadius or 0) == radius
                    and (t.cornerMask or 15) == (from.cornerMask or 15)
                    and (t.cornerJoinPower == true) == (from.cornerJoinPower == true)
            end,
        })
    end
    -- Inline Border color swatch; Highlight lives on "Hover Borders" below
    -- (same highlightColor var).
    if not CludesUI._prebuilding then
        local leftRgn = sharedScaleBorderRow._rightRegion
        local ctrl = leftRgn._control
        local Pix = CludesUI.PP

        -- Corner Radius (CludesUI_RoundedCorners.lua): an inline cog on the
        -- border size control.
        if not CludesUI._prebuilding then
            CludesUI.BuildInlineCog(sharedScaleBorderRow._rightRegion, {
                title = "Corner Radius",
                tip = "Corner Radius",
                disabled = function()
                    return not CludesUI.RoundedStyleOK(SGet("borderTexture"))
                end,
                disabledTooltip = "This option requires the Solid, Glow or Shadow border style.",
                rows = CludesUI.RoundedJoinRow(
                    CludesUI.RoundedCornerRows({
                        {
                            type = "slider",
                            label = "Corner Radius",
                            min = 0,
                            max = CludesUI.ROUNDED_MAX_RADIUS,
                            step = 1,
                            get = function()
                                return SVal("cornerRadius", 0)
                            end,
                            set = function(v)
                                SSet("cornerRadius", v)
                            end,
                        },
                    }, function()
                        return SGet("cornerMask")
                    end, function(v)
                        SSet("cornerMask", v)
                    end),
                    "Join Power Bar",
                    "Rounds a detached power bar right above or below the frame as one shape with it.",
                    function()
                        return SGet("cornerJoinPower")
                    end,
                    function(v)
                        SSet("cornerJoinPower", v)
                    end,
                    function()
                        local place = SGet("powerPosition") or "below"
                        return place == "detached_top" or place == "detached_bottom"
                    end,
                    "Detached Power Bar"
                ),
            })
        end

        -- Border color (with alpha), left of the Corner Radius cog
        local borderSwatch, updateBorderSwatch = CludesUI.BuildColorSwatch(
            leftRgn,
            sharedScaleBorderRow:GetFrameLevel() + 3,
            function()
                local c = SGet("borderColor") or { r = 0, g = 0, b = 0 }
                return c.r, c.g, c.b, SVal("borderAlpha", 1)
            end,
            function(r, g, b, a)
                UNIT_DB_MAP[optionState.selectedUnit]().borderColor = { r = r, g = g, b = b }
                UNIT_DB_MAP[optionState.selectedUnit]().borderAlpha = a
                ReloadAndUpdate()
            end,
            true,
            20
        )
        Pix.Point(borderSwatch, "RIGHT", leftRgn._lastInline or ctrl, "LEFT", -8, 0)
        leftRgn._lastInline = borderSwatch
        CludesUI.HoverTip(borderSwatch, "Border")

        CludesUI.RegisterWidgetRefresh(function()
            updateBorderSwatch()
        end)
    end

    -- Row 4: Show Tooltip For (checkbox-dropdown) | Frame Strata. "Show Tooltip
    -- For" is a pure VIEW over per-unit showUnitTooltip/showAuraTooltips (zero
    -- migration); both setters write EVERY unit key, including boss.
    local ufStrataValues = CludesUI.FRAME_STRATA_LABELS
    local ufStrataOrder = CludesUI.FRAME_STRATA_ORDER_BASE
    local tipStrataRow
    tipStrataRow, hgt = W:DualRow(hostFrame, posY, {
        type = "dropdown",
        text = "Show Tooltip For",
        tooltip = "Choose which tooltips appear on hover. Affects all unit frames, including boss frames.",
        values = { ["_placeholder"] = "..." },
        order = { "_placeholder" },
        getValue = function()
            return "_placeholder"
        end,
        setValue = function() end,
    }, {
        type = "dropdown",
        text = "Frame Strata",
        tooltip = "Controls the order that overlapping elements display in. Set higher to show above other elements.",
        values = ufStrataValues,
        order = ufStrataOrder,
        getValue = function()
            return SGet("frameStrata") or saved.profile.frameStrata or "MEDIUM"
        end,
        setValue = function(v)
            SSet("frameStrata", v)
        end,
    })
    posY = posY - hgt

    -- Show Tooltip For checkbox-dropdown (left region)
    if not CludesUI._prebuilding then
        local rgn = tipStrataRow._leftRegion
        if rgn._control then
            rgn._control:Hide()
        end
        local tipItems = {
            {
                key = "unit",
                label = "Unit Frame",
                tooltip = "Show the unit's tooltip when hovering the frame itself.",
            },
            {
                key = "auras",
                label = "Main Frames Auras",
                tooltip = "Show aura tooltips when hovering buff and debuff icons on all unit frames except boss frames.",
            },
            {
                key = "bossauras",
                label = "Boss Frames Auras",
                tooltip = "Show aura tooltips when hovering buff and debuff icons on boss frames.",
            },
        }
        -- Both aura items view the same per-unit showAuraTooltips key the runtime
        -- reads per element; they differ only in which units the setter fans to.
        local ALL_UNITS = { "player", "target", "focus", "targettarget", "focustarget", "pet", "boss" }
        local MAIN_UNITS = { "player", "target", "focus", "targettarget", "focustarget", "pet" }
        local Pix = CludesUI.PP
        local cbDD, cbDDRefresh = CludesUI.BuildVisOptsCBDropdown(
            rgn,
            210,
            rgn:GetFrameLevel() + 2,
            tipItems,
            function(k)
                if k == "unit" then
                    return SVal("showUnitTooltip", true)
                end
                if k == "auras" then
                    return SVal("showAuraTooltips", true)
                end
                if k == "bossauras" then
                    return UNIT_DB_MAP["boss"]().showAuraTooltips ~= false
                end
                return false
            end,
            function(k, v)
                if k == "unit" then
                    for _, key in ipairs(ALL_UNITS) do
                        UNIT_DB_MAP[key]().showUnitTooltip = v
                    end
                elseif k == "auras" then
                    for _, key in ipairs(MAIN_UNITS) do
                        UNIT_DB_MAP[key]().showAuraTooltips = v
                    end
                elseif k == "bossauras" then
                    UNIT_DB_MAP["boss"]().showAuraTooltips = v
                else
                    return
                end
                ReloadAndUpdate()
            end
        )
        CludesUI.PanelPP.Point(cbDD, "RIGHT", rgn, "RIGHT", -20, 0)
        rgn._control = cbDD
        rgn._lastInline = nil
        CludesUI.RegisterWidgetRefresh(cbDDRefresh)
    end

    -- Cog on Frame Strata: custom bar stratas for detached power/text bar
    if not CludesUI._prebuilding then
        local strataRgn = tipStrataRow
        if strataRgn and strataRgn._rightRegion then
            strataRgn = strataRgn._rightRegion
        end
        local barStrataValues = CludesUI.FRAME_STRATA_LABELS
        local barStrataOrder = CludesUI.FRAME_STRATA_ORDER_BASE
        if strataRgn then
            CludesUI.BuildInlineCog(strataRgn, {
                title = "Detached Bar Stratas",
                rows = {
                    {
                        type = "toggle",
                        label = "Custom Bar Stratas",
                        get = function()
                            return saved.profile.enableCustomBarStratas or false
                        end,
                        set = function(v)
                            saved.profile.enableCustomBarStratas = v
                            ReloadAndUpdate()
                        end,
                    },
                    {
                        type = "dropdown",
                        label = "Detached Power Bar",
                        values = barStrataValues,
                        order = barStrataOrder,
                        get = function()
                            return saved.profile.detachedPowerStrata or "HIGH"
                        end,
                        set = function(v)
                            saved.profile.detachedPowerStrata = v
                            ReloadAndUpdate()
                        end,
                    },
                    {
                        type = "dropdown",
                        label = "Detached Text Bar",
                        values = barStrataValues,
                        order = barStrataOrder,
                        get = function()
                            return saved.profile.detachedTextBarStrata or "DIALOG"
                        end,
                        set = function(v)
                            saved.profile.detachedTextBarStrata = v
                            ReloadAndUpdate()
                        end,
                    },
                },
            })
        end
    end

    -- Sync icon: Frame Strata (right region) -- pushes this unit's strata to
    -- the other main frames. Each frame keeps its own value; unset frames
    -- fall back to the profile-wide default.
    if not CludesUI._prebuilding then
        mod.UFO_UnitSync(tipStrataRow._rightRegion, "Frame Strata", {
            key = "frameStrata",
            default = function()
                return saved.profile.frameStrata or "MEDIUM"
            end,
        })
    end

    -- Show Decimal on Health Text (global): one decimal on health value (240.5k)
    -- and health percent (77.3%) for every unit. Default off.
    local decRow
    decRow, hgt = W:DualRow(hostFrame, posY, {
        type = "toggle",
        text = "Show Decimal on Health Text",
        tooltip = "Show one decimal place on health text: health values like 240.5k and health percent like 77.3%. Power text is unaffected. Off by default.",
        getValue = function()
            return saved.profile.showDecimalOnText
        end,
        setValue = function(v)
            saved.profile.showDecimalOnText = v
            if mod.ApplyTextDecimalGlobals then
                mod.ApplyTextDecimalGlobals()
            end
            ReloadAndUpdate()
            UpdatePreview()
            CludesUI:RefreshPage()
        end,
    }, {
        type = "dropdown",
        text = "Hover Borders",
        values = { __placeholder = "All" },
        order = { "__placeholder" },
        getValue = function()
            return "__placeholder"
        end,
        setValue = function() end,
    })
    posY = posY - hgt
    -- Dimmed "(Applies to All Units)" subtitle next to the label (CDM subtitle pattern).
    do
        local suffix = decRow._leftRegion:CreateFontString(nil, "OVERLAY")
        suffix:SetFont(CludesUI.EXPRESSWAY, 11, "")
        suffix:SetTextColor(1, 1, 1, 0.35)
        suffix:SetText(CludesUI.L("(Applies to All Units)"))
        local labelFS
        local regions = { decRow._leftRegion:GetRegions() }
        for idx = 1, #regions do
            local reg = regions[idx]
            if reg and reg.GetText and CludesUI.EnKey(reg:GetText()) == "Show Decimal on Health Text" then
                labelFS = reg
                break
            end
        end
        if labelFS then
            suffix:SetPoint("LEFT", labelFS, "RIGHT", 5, 0)
        else
            suffix:SetPoint("LEFT", decRow._leftRegion, "LEFT", 120, 0)
        end
    end

    -- Inline cog: extra decimal options. "Show 2 for Boss" (default on) gives boss
    -- frames a second decimal. Greyed out while the master decimal toggle is off.
    if not CludesUI._prebuilding then
        CludesUI.BuildInlineCog(decRow._leftRegion, {
            disabled = function()
                return not saved.profile.showDecimalOnText
            end,
            disabledTooltip = "Show Decimal on Health Text",
            title = "Health Text Decimals",
            rows = {
                {
                    type = "toggle",
                    label = "Only Show for % Health",
                    get = function()
                        return saved.profile.showDecimalPercentOnly == true
                    end,
                    set = function(v)
                        saved.profile.showDecimalPercentOnly = v
                        if mod.ApplyTextDecimalGlobals then
                            mod.ApplyTextDecimalGlobals()
                        end
                        ReloadAndUpdate()
                        UpdatePreview()
                    end,
                },
                {
                    type = "toggle",
                    label = "Show 2 for Boss",
                    get = function()
                        return saved.profile.showDecimalBoss2 ~= false
                    end,
                    set = function(v)
                        saved.profile.showDecimalBoss2 = v
                        if mod.ApplyTextDecimalGlobals then
                            mod.ApplyTextDecimalGlobals()
                        end
                        ReloadAndUpdate()
                        UpdatePreview()
                    end,
                },
                {
                    type = "toggle",
                    label = "Hide Trailing Zeros",
                    get = function()
                        return saved.profile.showDecimalTrimZeros == true
                    end,
                    set = function(v)
                        saved.profile.showDecimalTrimZeros = v
                        if mod.ApplyTextDecimalGlobals then
                            mod.ApplyTextDecimalGlobals()
                        end
                        ReloadAndUpdate()
                        UpdatePreview()
                    end,
                },
            },
        })
    end

    -- Hover Borders dropdown (mirrors Raid Frames): Highlight (per-unit hover
    -- border) + Player Threat (player frame only, global). Inline swatches:
    -- Highlight / Has Aggro / Close to Aggro.
    if not CludesUI._prebuilding then
        local rightRgn = decRow._rightRegion
        if rightRgn._control then
            rightRgn._control:Hide()
        end
        local isPlayer = (optionState.selectedUnit == "player")
        local hbItems = { { key = "highlight", label = "Highlight" } }
        if isPlayer then
            hbItems[#hbItems + 1] = {
                key = "playerThreat",
                label = "Player Threat (Non-Tank)",
                tooltip = "Adds a Shadow border to your player frame when you pull or hold threat as a non-tank. Only active in dungeons, raids and delves.",
            }
        end
        local UpdateHBSwatchVis -- forward declare; assigned after swatches
        local cbDD = CludesUI.BuildVisOptsCBDropdown(
            rightRgn,
            170,
            rightRgn:GetFrameLevel() + 2,
            hbItems,
            function(k)
                -- Highlight is shared across all 3 main frames; read the player copy.
                if k == "highlight" then
                    return UNIT_DB_MAP.player().highlightEnabled ~= false
                end
                if k == "playerThreat" then
                    return saved.profile.playerThreatBorderEnabled or false
                end
                return false
            end,
            function(k, v)
                if k == "highlight" then
                    -- Shared across all 3 main frames; threat stays player-only below.
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        UNIT_DB_MAP[key]().highlightEnabled = v
                    end
                    ReloadAndUpdate()
                elseif k == "playerThreat" then
                    saved.profile.playerThreatBorderEnabled = v
                    if mod.SetPlayerThreatEnabled then
                        mod.SetPlayerThreatEnabled(v)
                    end
                end
                if UpdateHBSwatchVis then
                    UpdateHBSwatchVis()
                end
            end
        )
        CludesUI.PanelPP.Point(cbDD, "RIGHT", rightRgn, "RIGHT", -20, 0)
        rightRgn._control = cbDD
        rightRgn._lastInline = nil

        local lvl = decRow:GetFrameLevel() + 3
        -- Highlight swatch (per-unit), nearest the dropdown.
        local hlSwatch, updHl = CludesUI.BuildColorSwatch(rightRgn, lvl, function()
            local c = UNIT_DB_MAP.player().highlightColor or { r = 1, g = 1, b = 1 }
            return c.r, c.g, c.b, UNIT_DB_MAP.player().highlightAlpha or 1
        end, function(r, g, b, a)
            -- Shared across all 3 main frames (see Highlight enable above).
            for _, key in ipairs(GROUP_UNIT_ORDER) do
                local d = UNIT_DB_MAP[key]()
                d.highlightColor = { r = r, g = g, b = b }
                d.highlightAlpha = a
            end
            ReloadAndUpdate()
        end, true, 20)
        hlSwatch:SetPoint("RIGHT", rightRgn._lastInline or rightRgn._control, "LEFT", -8, 0)
        rightRgn._lastInline = hlSwatch
        CludesUI.HoverTip(hlSwatch, "Highlight")

        local hasSwatch, updHas, nearSwatch, updNear
        if isPlayer then
            -- Has Aggro swatch (global), left of Highlight.
            hasSwatch, updHas = CludesUI.BuildColorSwatch(rightRgn, lvl, function()
                local c = saved.profile.playerThreatHasAggroColor or { r = 1, g = 0.5, b = 0 }
                return c.r, c.g, c.b, 1
            end, function(r, g, b)
                saved.profile.playerThreatHasAggroColor = { r = r, g = g, b = b }
                if mod.UpdatePlayerThreatBorder then
                    mod.UpdatePlayerThreatBorder()
                end
            end, false, 20)
            hasSwatch:SetPoint("RIGHT", rightRgn._lastInline, "LEFT", -8, 0)
            rightRgn._lastInline = hasSwatch
            CludesUI.HoverTip(hasSwatch, "Has Aggro")

            -- Close to Aggro swatch (global), left of Has Aggro.
            nearSwatch, updNear = CludesUI.BuildColorSwatch(rightRgn, lvl, function()
                local c = saved.profile.playerThreatNearAggroColor or { r = 0.81, g = 0.72, b = 0.19 }
                return c.r, c.g, c.b, 1
            end, function(r, g, b)
                saved.profile.playerThreatNearAggroColor = { r = r, g = g, b = b }
                if mod.UpdatePlayerThreatBorder then
                    mod.UpdatePlayerThreatBorder()
                end
            end, false, 20)
            nearSwatch:SetPoint("RIGHT", rightRgn._lastInline, "LEFT", -8, 0)
            rightRgn._lastInline = nearSwatch
            CludesUI.HoverTip(nearSwatch, "Close to Aggro")
        end

        -- Gray a swatch when its toggle is off (still clickable to pre-set).
        UpdateHBSwatchVis = function()
            hlSwatch:SetAlpha(UNIT_DB_MAP.player().highlightEnabled ~= false and 1 or 0.3)
            if hasSwatch then
                local enabled = saved.profile.playerThreatBorderEnabled
                hasSwatch:SetAlpha(enabled and 1 or 0.3)
                nearSwatch:SetAlpha(enabled and 1 or 0.3)
            end
        end
        CludesUI.RegisterWidgetRefresh(function()
            updHl()
            if updHas then
                updHas()
            end
            if updNear then
                updNear()
            end
            UpdateHBSwatchVis()
        end)
        UpdateHBSwatchVis()
    end

    -- Threat % text (WoW Forever only): one profile-wide setting for both
    -- frames, drawn on the CludesUI frames only. Built before the
    -- half-empty Blizz header row so its blank stays the last slot.
    if
        CludesUI.IS_FOREVER and (optionState.selectedUnit == "target" or optionState.selectedUnit == "focus")
    then
        local NO_FRAMES = "This option requires an CludesUI Target or Focus frame."
        local function noFrames()
            return not (frameList.target or frameList.focus)
        end
        local function pctOff()
            return noFrames() or not saved.profile.threatPctEnabled
        end
        local function pctOffTip()
            if noFrames() then
                return NO_FRAMES
            end
            return "Show Threat % on Target"
        end
        local function PctSet(key, v)
            saved.profile[key] = v
            mod.RefreshThreatPct()
        end
        local function PctSlider(key, labelText, lo, hi)
            return {
                type = "slider",
                label = labelText,
                min = lo,
                max = hi,
                step = 1,
                get = function()
                    return saved.profile[key]
                end,
                set = function(v)
                    PctSet(key, v)
                end,
            }
        end
        local pctRow
        pctRow, hgt = W:DualRow(hostFrame, posY, {
            type = "toggle",
            text = "Show Threat % on Target",
            tooltip = "Shows your threat percentage on the target frame while you are in combat with it. The cog adds the focus frame.",
            disabled = function()
                return noFrames() and not saved.profile.threatPctEnabled
            end,
            disabledTooltip = NO_FRAMES,
            getValue = function()
                return saved.profile.threatPctEnabled
            end,
            setValue = function(v)
                saved.profile.threatPctEnabled = v
                mod.SetThreatPctEnabled(v)
                CludesUI:RefreshPage()
            end,
        }, {
            type = "dropdown",
            text = "Threat % Position",
            values = mod._threatPctPositions,
            order = mod._threatPctPositionOrder,
            disabled = pctOff,
            disabledTooltip = pctOffTip,
            getValue = function()
                return saved.profile.threatPctPosition
            end,
            setValue = function(v)
                PctSet("threatPctPosition", v)
            end,
        })
        posY = posY - hgt
        if not CludesUI._prebuilding then
            CludesUI.BuildInlineCog(pctRow._leftRegion, {
                title = "Threat % Units",
                disabled = pctOff,
                disabledTooltip = pctOffTip,
                rows = {
                    {
                        type = "toggle",
                        label = "Show on Focus",
                        get = function()
                            return saved.profile.threatPctFocus
                        end,
                        set = function(v)
                            PctSet("threatPctFocus", v)
                        end,
                    },
                },
            })
            CludesUI.BuildInlineCog(pctRow._rightRegion, {
                title = "Threat %",
                disabled = pctOff,
                disabledTooltip = pctOffTip,
                rows = {
                    {
                        type = "toggle",
                        label = "Color by Threat",
                        tooltip = "Colors the number by threat status. Off shows it in white.",
                        get = function()
                            return saved.profile.threatPctColorByThreat
                        end,
                        set = function(v)
                            PctSet("threatPctColorByThreat", v)
                        end,
                    },
                    PctSlider("threatPctSize", "Size", 6, 20),
                    PctSlider("threatPctXOffset", "X Offset", -300, 300),
                    PctSlider("threatPctYOffset", "Y Offset", -300, 300),
                },
            })
        end
    end

    -- Blizzard Style, target frame: the coloured strip behind the name,
    -- or an uncoloured header matching the player frame.
    if optionState.selectedUnit == "target" and CludesUI.BlizzStyle.Active("unitframes") == "blizzard" then
        _, hgt = W:DualRow(hostFrame, posY, {
            type = "toggle",
            text = "Blizz Colored Target Header",
            tooltip = "Colors the strip behind the target's name by its reaction.",
            getValue = function()
                return UNIT_DB_MAP.target().blizzColoredHeader ~= false
            end,
            setValue = function(v)
                if v then
                    UNIT_DB_MAP.target().blizzColoredHeader = nil
                else
                    UNIT_DB_MAP.target().blizzColoredHeader = false
                end
                ReloadAndUpdate()
                UpdatePreview()
            end,
        }, { type = "label", text = "" })
        posY = posY - hgt
    end

    _, hgt = W:Spacer(hostFrame, posY, 20)
    posY = posY - hgt

    return posY
end

function mod.UFO_BuildPortraitSection(hostFrame, posY, context)
    local environ = mod._UFO_OptEnv
    local ReloadAndUpdate, UNIT_DB_MAP = environ.ReloadAndUpdate, environ.UNIT_DB_MAP
    local UpdatePreview, saved, detPortraitShapeOrder, detPortraitShapeValues =
        environ.UpdatePreview, environ.db, environ.detPortraitShapeOrder, environ.detPortraitShapeValues
    local optionState, portraitArtOrder, portraitArtValues, portraitModeOrder2 =
        environ.optState, environ.portraitArtOrder, environ.portraitArtValues, environ.portraitModeOrder2
    local portraitModeValues2, portraitNonPlayerOrder, portraitNonPlayerValues =
        environ.portraitModeValues2, environ.portraitNonPlayerOrder, environ.portraitNonPlayerValues
    local W, SDB, SGet, SSet = context.W, context.SDB, context.SGet, context.SSet
    local SVal = context.SVal
    local _, hgt

    -------------------------------------------------------------------
    --  PORTRAIT
    -------------------------------------------------------------------
    local sharedPortraitHeader
    sharedPortraitHeader, hgt = W:SectionHeader(hostFrame, "PORTRAIT", posY)
    posY = posY - hgt

    -- Forward declarations for cross-row updates
    local sharedDetShapeRow
    local sharedDetSizeRow

    -- Row 1: Portrait Mode + Art Style
    local sharedPortraitModeRow
    sharedPortraitModeRow, hgt = W:DualRow(
        hostFrame,
        posY,
        CludesUI.BlizzStyle.Gate("unitframes", {
            type = "dropdown",
            text = "Portrait Mode",
            values = portraitModeValues2,
            order = portraitModeOrder2,
            getValue = function()
                -- Blizzard Style always renders the attached portrait.
                if CludesUI.BlizzStyle.Get("unitframes") then
                    return "attached"
                end
                return SVal("portraitStyle", "attached")
            end,
            setValue = function(v)
                -- Any mode change flips row visibility below (Size/Position and the
                -- dragon row hidden at None, Shape detached-only), so a real
                -- change forces a rebuild.
                local prevStyle = SVal("portraitStyle", "attached")
                SSet("portraitStyle", v)
                -- Auto-set shape to "none" when entering detached + 3D
                if v == "detached" and SVal("portraitMode", "2d") == "3d" then
                    UNIT_DB_MAP[optionState.selectedUnit]().detachedPortraitShape = "none"
                end
                -- Reset detached-only settings when leaving detached mode
                if v ~= "detached" then
                    UNIT_DB_MAP[optionState.selectedUnit]().portraitSize = 0
                    local side = UNIT_DB_MAP[optionState.selectedUnit]().portraitSide
                    if
                        side == "top"
                        or side == "insideleft"
                        or side == "insideright"
                        or side == "insidecenter"
                    then
                        UNIT_DB_MAP[optionState.selectedUnit]().portraitSide = "left"
                    end
                end
                UNIT_DB_MAP[optionState.selectedUnit]().showPortrait = (v ~= "none")
                UpdatePreview()
                if v ~= prevStyle then
                    CludesUI:RefreshPage(true)
                    return
                end
                C_Timer.After(0, function()
                    local rl = CludesUI._widgetRefreshList
                    if rl then
                        for idx = 1, #rl do
                            rl[idx]()
                        end
                    end
                end)
            end,
        }),
        {
            type = "dropdown",
            text = "Art Style",
            values = portraitArtValues,
            order = portraitArtOrder,
            -- Blizzard Style renders the portrait whatever the saved mode says.
            disabled = function()
                return not CludesUI.BlizzStyle.Get("unitframes")
                    and SVal("portraitStyle", "attached") == "none"
            end,
            disabledTooltip = "Portrait Mode is set to None",
            rawTooltip = true,
            -- Blizzard Style masks the 2D art; a 3D model cannot be masked.
            itemDisabled = function(val)
                return val == "3d" and CludesUI.BlizzStyle.Get("unitframes")
            end,
            -- The active style's name as the requirement noun; the widget
            -- wraps and translates it once ("... to be disabled").
            itemDisabledTooltip = function(val)
                if val == "3d" then
                    return CludesUI.BlizzStyle.Label("unitframes")
                end
            end,
            itemRequireState = "disabled",
            getValue = function()
                local v = SGet("portraitMode")
                if v == "class" then
                    return SVal("classThemeStyle", "modern")
                end
                return v or "2d"
            end,
            setValue = function(v)
                local prefs = SDB()
                local function ApplyArt()
                    prefs.portraitMode = v
                    prefs.showPortrait = true
                    -- Auto-set shape to "none" when entering 3D + detached
                    if v == "3d" and prefs.portraitStyle == "detached" then
                        prefs.detachedPortraitShape = "none"
                    end
                    -- 3D-only options: reset when leaving 3D
                    if v ~= "3d" then
                        if prefs.detachedPortraitShape == "none" then
                            prefs.detachedPortraitShape = "portrait"
                        end
                        local side = prefs.portraitSide
                        if side == "insideleft" or side == "insideright" or side == "insidecenter" then
                            prefs.portraitSide = "left"
                        end
                    end
                    ReloadAndUpdate()
                    UpdatePreview()
                end
                local function ConfirmArt()
                    ApplyArt()
                    CludesUI:RefreshPage(true)
                end
                if v == "3d" and SVal("portraitMode", "2d") ~= "3d" and mod.UF_Ask3DPortraits(ConfirmArt) then
                    return
                end
                if
                    v == "2d"
                    and SVal("portraitMode", "2d") ~= "2d"
                    and prefs.portraitMirror
                    and not CludesUI.BlizzStyle.Get("unitframes")
                    and mod.UF_Ask2DMirroredPortraits(ConfirmArt)
                then
                    return
                end
                ApplyArt()
            end,
        }
    )
    posY = posY - hgt
    -- Sync icon: Portrait Mode (Style); a mode of None also hides the portrait.
    if not CludesUI._prebuilding then
        mod.UFO_UnitSync(sharedPortraitModeRow._leftRegion, "Portrait Mode", {
            copy = function(t, from)
                local style = from.portraitStyle or "attached"
                t.portraitStyle = style
                t.showPortrait = style ~= "none"
            end,
            same = function(t, from)
                return (t.portraitStyle or "attached") == (from.portraitStyle or "attached")
            end,
        })
    end
    -- Portrait settings; the separator is offered only for attached portraits.
    if not CludesUI._prebuilding then
        local rowList = {
            {
                type = "toggle",
                label = "Custom Non-Player Portrait",
                tooltip = "Pick what NPCs show in Class art instead of their 2D portrait.",
                get = function()
                    return SVal("portraitNonPlayerOn", false)
                end,
                set = function(v)
                    SSet("portraitNonPlayerOn", v or nil)
                    CludesUI:RefreshPage(true)
                end,
            },
        }
        if SVal("portraitStyle", "attached") == "attached" then
            rowList[#rowList + 1] = {
                type = "toggle",
                label = "Vertical Border Separator",
                tooltip = "Draws the selected border style between the attached portrait and the bars.",
                disabled = function()
                    return SVal("borderSize", 1) <= 0
                        or not CludesUI.GetBorderCompanion(SGet("borderTexture") or "solid", "sepV")
                end,
                disabledTooltip = "This option requires a border style with divider art and a Border Size above 0.",
                rawTooltip = true,
                get = function()
                    return SVal("portraitSeparator", false)
                end,
                set = function(v)
                    SSet("portraitSeparator", v or nil)
                end,
            }
        end
        if SVal("portraitStyle", "attached") == "detached" then
            rowList[#rowList + 1] = {
                type = "toggle",
                label = "Clickable Portrait",
                tooltip = "Clicking or hovering the detached portrait acts like clicking or hovering the frame's bars.",
                get = function()
                    return SVal("detachedPortraitClickable", false)
                end,
                set = function(v)
                    SSet("detachedPortraitClickable", v or nil)
                end,
            }
            rowList[#rowList + 1] = {
                type = "colorpicker",
                label = "Background Color",
                hasAlpha = true,
                tooltip = "Fill color behind the detached portrait.",
                disabled = function()
                    return SVal("detachedPortraitShape", "portrait") == "none"
                end,
                disabledTooltip = "This option requires a Shape other than None.",
                rawTooltip = true,
                get = function()
                    local c = SGet("detachedPortraitBgColor")
                    if c then
                        return c.r, c.g, c.b, c.a or 1
                    end
                    return 0.1, 0.1, 0.1, 1
                end,
                set = function(r, g, b, a)
                    SSet("detachedPortraitBgColor", { r = r, g = g, b = b, a = a or 1 })
                    UpdatePreview()
                end,
            }
            -- A 3D model draws over the shape's border; on, it sits inside the
            -- border and under it (ns.UF_PortraitShapeModel).
            rowList[#rowList + 1] = {
                type = "toggle",
                label = "3D Portrait Below Border",
                tooltip = "Draws a 3D portrait inside the shape's border instead of over it.",
                disabled = function()
                    return SVal("portraitMode", "2d") ~= "3d"
                        or SVal("detachedPortraitShape", "portrait") == "none"
                end,
                disabledTooltip = "This option requires the 3D Art Style and a Shape other than None.",
                rawTooltip = true,
                get = function()
                    return SVal("portrait3dBelowBorder", false)
                end,
                set = function(v)
                    SSet("portrait3dBelowBorder", v or nil)
                    UpdatePreview()
                end,
            }
        end
        CludesUI.BuildInlineCog(sharedPortraitModeRow._leftRegion, {
            title = "Portrait Settings",
            disabled = function()
                return CludesUI.BlizzStyle.Get("unitframes") or SVal("portraitStyle", "attached") == "none"
            end,
            disabledTooltip = function()
                if CludesUI.BlizzStyle.Get("unitframes") then
                    return CludesUI.BlizzStyle.Label("unitframes")
                end
                return "Portrait Mode is set to None"
            end,
            rawTooltip = function()
                return not CludesUI.BlizzStyle.Get("unitframes")
            end,
            requireState = "disabled",
            rows = rowList,
        })
    end
    -- Sync icon: Portrait Mode (Art Style), copied as stored (unset included).
    if not CludesUI._prebuilding then
        mod.UFO_UnitSync(sharedPortraitModeRow._rightRegion, "Art Style", {
            copy = function(t, from)
                t.portraitMode = from.portraitMode
            end,
            same = function(t, from)
                return (t.portraitMode or "none") == (from.portraitMode or "none")
            end,
        })
    end

    -- Row 1b: Non-Player Portrait (right half blank), built only while the
    -- Portrait Mode cog's opt-in is on and the portrait shows (Portrait
    -- Mode's setValue rebuilds the page on any mode change).
    if SVal("portraitNonPlayerOn", false) and SVal("portraitStyle", "attached") ~= "none" then
        local nonPlayerRow
        nonPlayerRow, hgt = W:DualRow(
            hostFrame,
            posY,
            CludesUI.BlizzStyle.Gate("unitframes", {
                type = "dropdown",
                text = "Non-Player Portrait",
                values = portraitNonPlayerValues,
                order = portraitNonPlayerOrder,
                disabled = function()
                    return SVal("portraitMode", "2d") ~= "class"
                end,
                disabledTooltip = "This option requires Art Style to be set to Class",
                rawTooltip = true,
                -- A 3D model cannot be masked: a Detached shape keeps NPCs on 2D.
                itemDisabled = function(v)
                    return v == "3d"
                        and SVal("portraitStyle", "attached") == "detached"
                        and SVal("detachedPortraitShape", "portrait") ~= "none"
                end,
                itemDisabledTooltip = function(v)
                    if v == "3d" then
                        return "Attached Portrait Mode"
                    end
                end,
                getValue = function()
                    return SVal("portraitNonPlayer", "2d")
                end,
                setValue = function(v)
                    if
                        v == "3d"
                        and SVal("portraitNonPlayer", "2d") ~= "3d"
                        and mod.UF_Ask3DPortraits(function()
                            SSet("portraitNonPlayer", "3d")
                            CludesUI:RefreshPage()
                        end)
                    then
                        return
                    end
                    SSet("portraitNonPlayer", v)
                end,
            }),
            CludesUI.BlankRowCfg()
        )
        posY = posY - hgt
        -- Sync icon: carries the opt-in with the choice.
        if not CludesUI._prebuilding then
            mod.UFO_UnitSync(nonPlayerRow._leftRegion, "Non-Player Portrait", {
                self = true,
                copy = function(t, from)
                    local choice = from.portraitNonPlayer
                    if choice == nil then
                        choice = "2d"
                    end
                    t.portraitNonPlayerOn = from.portraitNonPlayerOn
                    t.portraitNonPlayer = choice
                end,
                same = function(t, from)
                    return (t.portraitNonPlayerOn or false) == (from.portraitNonPlayerOn or false)
                        and (t.portraitNonPlayer or "2d") == (from.portraitNonPlayer or "2d")
                end,
            })
        end
    end -- close Non-Player Portrait opt-in gate

    -- Row 2: Size + Position. HIDDEN entirely while Portrait Mode is None
    -- (the mode dropdown's setValue forces the rebuild on any mode change).
    -- Blizzard Style always shows the portrait, so the row stays.
    if CludesUI.BlizzStyle.Get("unitframes") or SVal("portraitStyle", "attached") ~= "none" then
        local portraitLocationValues = {
            ["left"] = "Left",
            ["right"] = "Right",
            ["top"] = "Top",
            ["insideleft"] = "Inside Left",
            ["insideright"] = "Inside Right",
            ["insidecenter"] = "Inside Center",
        }
        local portraitLocationOrder = { "left", "right", "top", "insideleft", "insideright", "insidecenter" }
        local sharedSizePosRow
        sharedSizePosRow, hgt = W:DualRow(hostFrame, posY, {
            type = "slider",
            text = "Size",
            min = -50,
            max = 100,
            step = 1,
            disabled = function()
                local style = SVal("portraitStyle", "attached")
                local side = SVal("portraitSide", "left")
                local isInside = side == "insideleft" or side == "insideright" or side == "insidecenter"
                return style ~= "detached" and not isInside
            end,
            disabledTooltip = "Only available in Detached or Inside modes",
            rawTooltip = true,
            getValue = function()
                return SVal("portraitSize", 0)
            end,
            setValue = function(v)
                SSet("portraitSize", v)
                UpdatePreview()
            end,
        }, {
            type = "dropdown",
            text = "Position",
            values = portraitLocationValues,
            order = portraitLocationOrder,
            itemDisabled = function(v)
                local pStyle = SVal("portraitStyle", "attached")
                if v == "top" and pStyle == "attached" then
                    return true
                end
                if v == "insideleft" or v == "insideright" or v == "insidecenter" then
                    if SVal("portraitMode", "2d") ~= "3d" then
                        return true
                    end
                    if pStyle ~= "detached" then
                        return true
                    end
                end
                return false
            end,
            itemDisabledTooltip = function(v)
                if v == "top" then
                    return "Top position is only available in Detached mode"
                end
                if v == "insideleft" or v == "insideright" or v == "insidecenter" then
                    if SVal("portraitMode", "2d") ~= "3d" then
                        return "Inside positions require 3D Art Style"
                    end
                    return "Inside positions require Detached mode"
                end
            end,
            getValue = function()
                return SVal("portraitSide", "left")
            end,
            setValue = function(v)
                SSet("portraitSide", v)
                UpdatePreview()
            end,
        })
        posY = posY - hgt
        -- Sync icons: Portrait Size (left) and Portrait Side (right)
        if not CludesUI._prebuilding then
            local rgn = sharedSizePosRow._leftRegion
            mod.UFO_UnitSync(rgn, "Portrait Size", {
                key = "portraitSize",
                default = 0,
            })
            -- Zoom cog on Size slider
            local _, zoomShow
            _, zoomShow = CludesUI.BuildInlineCog(rgn, {
                title = "Portrait Zoom",
                rows = {
                    {
                        type = "slider",
                        label = "2D Zoom",
                        min = 50,
                        max = 100,
                        step = 1,
                        get = function()
                            return SVal("portraitArtScale", 100)
                        end,
                        set = function(v)
                            SSet("portraitArtScale", v)
                            UpdatePreview()
                        end,
                    },
                    {
                        type = "slider",
                        label = "3D Zoom",
                        min = 100,
                        max = 300,
                        step = 1,
                        get = function()
                            return SVal("portrait3dZoom", 100)
                        end,
                        set = function(v)
                            SSet("portrait3dZoom", v)
                            UpdatePreview()
                        end,
                    },
                    {
                        type = "slider",
                        label = "Class Zoom",
                        min = 50,
                        max = 200,
                        step = 1,
                        disabled = function()
                            return CludesUI.BlizzStyle.Get("unitframes")
                                or SVal("portraitMode", "2d") ~= "class"
                        end,
                        disabledTooltip = function()
                            if CludesUI.BlizzStyle.Get("unitframes") then
                                return CludesUI.BlizzStyle.Label("unitframes")
                            end
                            return "This option requires the Class Art Style."
                        end,
                        requireState = "disabled",
                        get = function()
                            return SVal("portraitClassZoom", 100)
                        end,
                        set = function(v)
                            SSet("portraitClassZoom", v)
                            UpdatePreview()
                        end,
                    },
                    -- The stock styles keep their full art.
                    {
                        type = "toggle",
                        label = "Mirror Portrait",
                        tooltip = "Mirrors playable-race portraits in 2D and 3D. Always flips class art horizontally.",
                        disabled = function()
                            return CludesUI.BlizzStyle.Get("unitframes")
                        end,
                        disabledTooltip = function()
                            return CludesUI.BlizzStyle.Label("unitframes")
                        end,
                        requireState = "disabled",
                        get = function()
                            return SVal("portraitMirror", false)
                        end,
                        set = function(v)
                            local unitKey, prefs = optionState.selectedUnit, SDB()
                            local function ApplyMirror()
                                prefs.portraitMirror = v
                                mod.UF_RefreshPortraitMirror(unitKey)
                                UpdatePreview()
                            end
                            if
                                v
                                and not prefs.portraitMirror
                                and SVal("portraitMode", "2d") == "2d"
                                and mod.UF_Ask2DMirroredPortraits(function()
                                    ApplyMirror()
                                    CludesUI:RefreshPage()
                                end)
                            then
                                if zoomShow and zoomShow._popupFrame then
                                    zoomShow._popupFrame:Hide()
                                end
                                return
                            end
                            ApplyMirror()
                        end,
                    },
                },
            })
        end
        if not CludesUI._prebuilding then
            local rgn = sharedSizePosRow._rightRegion
            mod.UFO_UnitSync(rgn, "Portrait Position", {
                key = "portraitSide",
                default = "left",
            })
        end
        sharedDetSizeRow = sharedSizePosRow
        -- Cog on Position for X/Y offsets
        if not CludesUI._prebuilding then
            local posRgn = sharedSizePosRow._rightRegion
            CludesUI.BuildInlineCog(posRgn, {
                disabled = function()
                    return SVal("portraitStyle", "attached") ~= "detached"
                end,
                disabledTooltip = "This option requires Portrait Mode to be set to Detached.",
                title = "Portrait Position Offsets",
                rows = {
                    {
                        type = "slider",
                        label = "X Offset",
                        min = -100,
                        max = 100,
                        step = 1,
                        get = function()
                            return SVal("portraitX", 0)
                        end,
                        set = function(v)
                            SSet("portraitX", v)
                            UpdatePreview()
                        end,
                    },
                    {
                        type = "slider",
                        label = "Y Offset",
                        min = -100,
                        max = 100,
                        step = 1,
                        get = function()
                            return SVal("portraitY", 0)
                        end,
                        set = function(v)
                            SSet("portraitY", v)
                            UpdatePreview()
                        end,
                    },
                },
            })
        end
    end -- close Size/Position hidden-at-None gate

    -- Row 3: Shape + Shape Border (swatch + cog). HIDDEN unless Portrait Mode is
    -- Detached; the mode dropdown's setValue forces the rebuild on any change.
    if SVal("portraitStyle", "attached") == "detached" then
        local sharedShapeBorderRow
        sharedShapeBorderRow, hgt = W:DualRow(hostFrame, posY, {
            type = "dropdown",
            text = "Shape",
            values = detPortraitShapeValues,
            order = detPortraitShapeOrder,
            itemDisabled = function(v)
                return v == "none" and SVal("portraitMode", "2d") ~= "3d"
            end,
            itemDisabledTooltip = function(v)
                if v == "none" then
                    return "None shape requires 3D Art Style"
                end
            end,
            getValue = function()
                return SVal("detachedPortraitShape", "portrait")
            end,
            setValue = function(v)
                SSet("detachedPortraitShape", v)
                UpdatePreview()
            end,
        }, {
            type = "multiSwatch",
            text = "Shape Border",
            swatches = {
                {
                    tooltip = "Custom Color",
                    hasAlpha = false,
                    getValue = function()
                        local c = SGet("detachedPortraitBorderColor")
                        c = c or { r = 0, g = 0, b = 0 }
                        return c.r, c.g, c.b
                    end,
                    setValue = function(r, g, b)
                        UNIT_DB_MAP[optionState.selectedUnit]().detachedPortraitBorderColor =
                            { r = r, g = g, b = b }
                        ReloadAndUpdate()
                        UpdatePreview()
                    end,
                    onClick = function(self)
                        if SVal("detachedPortraitClassColor", true) then
                            SSet("detachedPortraitClassColor", false)
                            ReloadAndUpdate()
                            UpdatePreview()
                            CludesUI:RefreshPage()
                            return
                        end
                        if self._eabOrigClick then
                            self._eabOrigClick(self)
                        end
                    end,
                    refreshAlpha = function()
                        return SVal("detachedPortraitClassColor", true) and 0.3 or 1
                    end,
                },
                {
                    tooltip = "Class Colored",
                    hasAlpha = false,
                    getValue = function()
                        local _, ct = UnitClass("player")
                        if ct and RAID_CLASS_COLORS[ct] then
                            local cc = RAID_CLASS_COLORS[ct]
                            return cc.r, cc.g, cc.b
                        end
                        return 1, 1, 1
                    end,
                    setValue = function() end,
                    onClick = function()
                        SSet("detachedPortraitClassColor", true)
                        ReloadAndUpdate()
                        UpdatePreview()
                        CludesUI:RefreshPage()
                    end,
                    refreshAlpha = function()
                        return SVal("detachedPortraitClassColor", true) and 1 or 0.3
                    end,
                },
            },
        })
        posY = posY - hgt
        -- Cog on Shape Border for border settings
        if not CludesUI._prebuilding then
            local borderRgn = sharedShapeBorderRow._rightRegion
            local borderCog = {
                disabled = function()
                    return SVal("portraitStyle", "attached") ~= "detached"
                end,
                disabledTooltip = "This option is only available when Portrait Mode is Detached.",
                title = "Shape Border Settings",
                rows = {
                    {
                        type = "slider",
                        label = "Size",
                        min = 1,
                        max = 7,
                        step = 1,
                        get = function()
                            return SVal("detachedPortraitBorderSize", 7)
                        end,
                        set = function(v)
                            SSet("detachedPortraitBorderSize", v)
                            UpdatePreview()
                        end,
                    },
                    {
                        type = "slider",
                        label = "Opacity",
                        min = 0,
                        max = 100,
                        step = 1,
                        get = function()
                            return SVal("detachedPortraitBorderOpacity", 100)
                        end,
                        set = function(v)
                            SSet("detachedPortraitBorderOpacity", v)
                            UpdatePreview()
                        end,
                    },
                    {
                        type = "toggle",
                        label = "Unit Color in Dark Mode",
                        tooltip = "Keeps the unit's class or reaction color on the ring in Dark Mode instead of your own class color.",
                        disabled = function()
                            return not (
                                SVal("detachedPortraitClassColor", true) and mod.UF_DarkThemeOn(SDB())
                            )
                        end,
                        disabledTooltip = "This option requires the Class Colored Shape Border and Dark Mode.",
                        rawTooltip = true,
                        get = function()
                            return SVal("detachedPortraitUnitColorDark", false)
                        end,
                        set = function(v)
                            SSet("detachedPortraitUnitColorDark", v)
                            UpdatePreview()
                        end,
                    },
                    {
                        type = "dropdown",
                        label = "Outer Ring",
                        values = {
                            ["none"] = "None",
                            ["border"] = "Match Frame Border",
                            ["pixels"] = "Pixels Ring",
                            ["pixels-textured"] = "Pixels Textured Ring",
                            ["pixels-shadow"] = "Pixels Ring Shadow",
                            ["pixels-textured-shadow"] = "Pixels Textured Ring Shadow",
                            ["thin-border"] = "Naowh Thin Circle",
                        },
                        order = {
                            "none",
                            "border",
                            "pixels",
                            "pixels-textured",
                            "pixels-shadow",
                            "pixels-textured-shadow",
                            "thin-border",
                        },
                        -- "Pixels Textured Ring Shadow" needs more than the 130px default.
                        ddWidth = 190,
                        tooltip = "Adds a second ring around a round portrait; Match Frame Border follows your frame border style.",
                        disabled = function()
                            return not mod.UF_ROUND_SHAPES[SVal("detachedPortraitShape", "portrait")]
                        end,
                        disabledTooltip = "This option requires a Circle or Pixels Circle Shape.",
                        rawTooltip = true,
                        get = function()
                            return SVal("detachedPortraitOuterRing", "none")
                        end,
                        set = function(v)
                            SSet("detachedPortraitOuterRing", v)
                            UpdatePreview()
                        end,
                    },
                    {
                        type = "slider",
                        label = "Outer Ring Size",
                        min = 100,
                        max = 140,
                        step = 1,
                        tooltip = "Size of the outer ring relative to the portrait.",
                        disabled = function()
                            return not mod.UF_ROUND_SHAPES[SVal("detachedPortraitShape", "portrait")]
                                or SVal("detachedPortraitOuterRing", "none") == "none"
                        end,
                        disabledTooltip = function()
                            if not mod.UF_ROUND_SHAPES[SVal("detachedPortraitShape", "portrait")] then
                                return "This option requires a Circle or Pixels Circle Shape."
                            end
                            return "This option requires an Outer Ring other than None."
                        end,
                        rawTooltip = true,
                        get = function()
                            return SVal("detachedPortraitOuterRingScale", 118)
                        end,
                        set = function(v)
                            SSet("detachedPortraitOuterRingScale", v)
                            UpdatePreview()
                        end,
                    },
                    -- The 3D model draws over the shadow texture, so 2D and class art only.
                    {
                        type = "toggle",
                        label = "Inner Shadow",
                        tooltip = "Adds a soft shadow inside a round portrait.",
                        disabled = function()
                            return not mod.UF_ROUND_SHAPES[SVal("detachedPortraitShape", "portrait")]
                                or SVal("portraitMode", "2d") == "3d"
                        end,
                        disabledTooltip = function()
                            if not mod.UF_ROUND_SHAPES[SVal("detachedPortraitShape", "portrait")] then
                                return "This option requires a Circle or Pixels Circle Shape."
                            end
                            return "This option requires a 2D Portrait or Class Art Style."
                        end,
                        rawTooltip = true,
                        get = function()
                            return SVal("detachedPortraitInnerShadow", false)
                        end,
                        set = function(v)
                            SSet("detachedPortraitInnerShadow", v)
                            UpdatePreview()
                        end,
                    },
                },
            }
            CludesUI.BuildInlineCog(borderRgn, borderCog)
        end
        -- Sync icons: Shape (left) and Shape Border (right)
        if not CludesUI._prebuilding then
            local rgn = sharedShapeBorderRow._leftRegion
            mod.UFO_UnitSync(rgn, "Portrait Shape", {
                key = "detachedPortraitShape",
                default = "portrait",
            })
        end
        if not CludesUI._prebuilding then
            local rgn = sharedShapeBorderRow._rightRegion
            -- The cog's ring rows travel with the sync (key = its default).
            local SB_EXTRAS = {
                detachedPortraitUnitColorDark = false,
                detachedPortraitOuterRing = "none",
                detachedPortraitOuterRingScale = 118,
                detachedPortraitInnerShadow = false,
            }
            -- Unset reads as its default on both sides: class colour on, size 7.
            local function Or(v, def)
                if v == nil then
                    return def
                end
                return v
            end
            mod.UFO_UnitSync(rgn, "Shape Border", {
                copy = function(t, from)
                    local c = from.detachedPortraitBorderColor
                    t.detachedPortraitBorderColor = c and { r = c.r, g = c.g, b = c.b } or nil
                    t.detachedPortraitBorderOpacity = from.detachedPortraitBorderOpacity
                    t.detachedPortraitBorderSize = from.detachedPortraitBorderSize
                    t.detachedPortraitClassColor = from.detachedPortraitClassColor
                    for k in pairs(SB_EXTRAS) do
                        t[k] = from[k]
                    end
                end,
                same = function(t, from)
                    if
                        Or(t.detachedPortraitClassColor, true)
                            ~= Or(from.detachedPortraitClassColor, true)
                        or (t.detachedPortraitBorderSize or 7) ~= (from.detachedPortraitBorderSize or 7)
                    then
                        return false
                    end
                    for k, def in pairs(SB_EXTRAS) do
                        if Or(t[k], def) ~= Or(from[k], def) then
                            return false
                        end
                    end
                    return true
                end,
            })
        end
    end -- close Shape/Shape Border detached-only gate

    -- Row 4: Portrait Dragon toggle | Dragon Size (+ cog with the rest). Any
    -- shape, on player, target and focus: the Player Frame Dragon always shows,
    -- the Elite Enemy Dragon marks elite/boss (gold) and rare (silver) enemies.
    -- HIDDEN while Portrait Mode is None (the mode dropdown rebuilds the page);
    -- a stock style gates both slots, which drops the row. Values read through
    -- ns.UF_DragonSettings (the "wingless" Elite/Rare style shows its own
    -- values); every setter pins that view first (ns.UF_PinLegacyDragon).
    if SVal("portraitStyle", "attached") ~= "none" then
        local playerDragon = optionState.selectedUnit == "player"
        local dragonName = playerDragon and "Player Frame Dragon" or "Elite Enemy Dragon"
        local function DVal(k)
            return mod.UF_DragonSettings(optionState.selectedUnit, SDB())[k]
        end
        local function DSet(key, v)
            mod.UF_PinLegacyDragon(SDB())
            SSet(key, v)
        end
        local function dragonOff()
            return not DVal("on")
        end
        local dragonRow
        dragonRow, hgt = W:DualRow(
            hostFrame,
            posY,
            CludesUI.BlizzStyle.Gate("unitframes", {
                type = "toggle",
                text = playerDragon and "Enable Player Frame Dragon" or "Enable Elite Enemy Dragon",
                tooltip = playerDragon and "Curls Blizzard's gold dragon around the portrait."
                    or "Curls a gold dragon around the portrait of elite and boss enemies, and a silver one around rares.",
                getValue = function()
                    return DVal("on")
                end,
                setValue = function(v)
                    DSet("detachedPortraitWinglessDragon", v)
                    CludesUI:RefreshPage()
                end,
            }),
            CludesUI.BlizzStyle.Gate("unitframes", {
                type = "slider",
                text = "Dragon Size",
                min = 50,
                max = 200,
                step = 1,
                tooltip = "Size of the dragon, as a percent of its fit around the portrait.",
                disabled = dragonOff,
                disabledTooltip = dragonName,
                getValue = function()
                    return DVal("scale")
                end,
                setValue = function(v)
                    DSet("detachedPortraitWinglessDragonScale", v)
                end,
            })
        )
        posY = posY - hgt
        if not CludesUI._prebuilding then
            local rowList = {
                {
                    type = "slider",
                    label = "X Offset",
                    min = -100,
                    max = 100,
                    step = 1,
                    get = function()
                        return DVal("x")
                    end,
                    set = function(v)
                        DSet("detachedPortraitWinglessDragonX", v)
                    end,
                },
                {
                    type = "slider",
                    label = "Y Offset",
                    min = -100,
                    max = 100,
                    step = 1,
                    get = function()
                        return DVal("y")
                    end,
                    set = function(v)
                        DSet("detachedPortraitWinglessDragonY", v)
                    end,
                },
                {
                    type = "toggle",
                    label = "Flip Dragon",
                    tooltip = "Turns the dragon to face the other way around the portrait.",
                    get = function()
                        return DVal("flip")
                    end,
                    set = function(v)
                        DSet("detachedPortraitWinglessDragonFlip", v)
                    end,
                },
                {
                    type = "toggle",
                    label = "Use Class Color",
                    tooltip = playerDragon and "Tints the dragon with your class color instead of gold."
                        or "Tints the dragon with your class color instead of gold or silver.",
                    get = function()
                        return DVal("classColor")
                    end,
                    set = function(v)
                        DSet("detachedPortraitWinglessDragonClassColor", v)
                    end,
                },
                {
                    type = "dropdown",
                    label = "Dragon Strata",
                    values = mod._ufDragonStrataValues,
                    order = mod._ufDragonStrataOrder,
                    tooltip = "Match Frame draws the dragon with the portrait. A higher strata draws it over the rest of the frame, border included.",
                    get = function()
                        return DVal("strata")
                    end,
                    set = function(v)
                        DSet("detachedPortraitWinglessDragonStrata", v)
                    end,
                },
                {
                    type = "slider",
                    label = "Dragon Frame Level",
                    min = 1,
                    max = 30,
                    step = 1,
                    tooltip = "Raises the dragon within its strata. Higher values draw it over more of the frame.",
                    get = function()
                        return DVal("level")
                    end,
                    set = function(v)
                        DSet("detachedPortraitWinglessDragonLevel", v)
                    end,
                },
            }
            -- The enemy dragon keeps the Elite/Rare Indicator's instance rule.
            if not playerDragon then
                rowList[#rowList + 1] = {
                    type = "toggle",
                    label = "Show in Instances",
                    tooltip = "Also show the dragon in dungeons and raids, where most enemies are elite.",
                    get = function()
                        return DVal("instances")
                    end,
                    set = function(v)
                        DSet("detachedPortraitWinglessDragonInstances", v)
                    end,
                }
            end
            CludesUI.BuildInlineCog(dragonRow._rightRegion, {
                title = dragonName,
                disabled = dragonOff,
                disabledTooltip = dragonName,
                rows = rowList,
            })
        end
    end -- close dragon row hidden-at-None gate

    _, hgt = W:Spacer(hostFrame, posY, 20)
    posY = posY - hgt

    return posY, sharedPortraitHeader, sharedPortraitModeRow
end

function mod.UFO_BuildTextBarSection(hostFrame, posY, context)
    local environ = mod._UFO_OptEnv
    local Pix, RegisterWidgetRefresh, ReloadAndUpdate =
        environ.PP, environ.RegisterWidgetRefresh, environ.ReloadAndUpdate
    local UNIT_DB_MAP, UpdatePreview, btbPositionOrder =
        environ.UNIT_DB_MAP, environ.UpdatePreview, environ.btbPositionOrder
    local btbPositionValues, btbTextOrder, btbTextValues, classIconLocOrder =
        environ.btbPositionValues, environ.btbTextOrder, environ.btbTextValues, environ.classIconLocOrder
    local classIconLocValues, classIconOrder, classIconValues, optionState =
        environ.classIconLocValues, environ.classIconOrder, environ.classIconValues, environ.optState
    local W, SGet, SSet, SVal = context.W, context.SGet, context.SSet, context.SVal
    local _, hgt

    -------------------------------------------------------------------
    --  TEXT BAR
    -------------------------------------------------------------------
    -- Blizzard Style hides the text bar, so the whole section goes; the
    -- row locals stay declared for the element-nav map.
    local sharedBtbHeader
    local _sharedBtbWidthRgn
    local sharedBtbToggleRow
    if not CludesUI.BlizzStyle.Get("unitframes") then
        _, hgt = W:Spacer(hostFrame, posY, 20)
        posY = posY - hgt
        sharedBtbHeader, hgt = W:SectionHeader(hostFrame, "TEXT BAR", posY)
        posY = posY - hgt

        -- Row 1: Enable Text Bar + Position
        sharedBtbToggleRow, hgt = W:DualRow(hostFrame, posY, {
            type = "toggle",
            text = "Enable Text Bar",
            getValue = function()
                return SVal("bottomTextBar", false)
            end,
            -- DependentSetValue: Rows 2-4 below are hidden while the Text
            -- Bar is off; the flip forces the full rebuild.
            setValue = CludesUI.DependentSetValue(function()
                return SVal("bottomTextBar", false)
            end, function(v)
                SSet("bottomTextBar", v)
                UpdatePreview()
                CludesUI:RefreshPage()
            end),
        }, {
            type = "dropdown",
            text = "Position",
            values = btbPositionValues,
            order = btbPositionOrder,
            disabled = function()
                return not SVal("bottomTextBar", false)
            end,
            disabledTooltip = "Text Bar",
            getValue = function()
                return SVal("btbPosition", "bottom")
            end,
            setValue = function(v)
                SSet("btbPosition", v)
                UpdatePreview()
                if _sharedBtbWidthRgn then
                    local isDet = (v == "detached_top" or v == "detached_bottom")
                    if _sharedBtbWidthRgn._control and _sharedBtbWidthRgn._control.SetEnabled then
                        _sharedBtbWidthRgn._control:SetEnabled(isDet)
                    end
                end
            end,
        })
        posY = posY - hgt
        -- Sync icon: Enable Text Bar
        if not CludesUI._prebuilding then
            local rgn = sharedBtbToggleRow._leftRegion
            mod.UFO_UnitSync(rgn, "Enable Text Bar", {
                key = "bottomTextBar",
                default = false,
            })
        end
        -- Sync icon: Text Bar Position (right region)
        if not CludesUI._prebuilding then
            local rgn = sharedBtbToggleRow._rightRegion
            mod.UFO_UnitSync(rgn, "Text Bar Position", {
                key = "btbPosition",
                default = "bottom",
            })
        end
        -- Inline color swatch for BTB background on Enable Text Bar
        if not CludesUI._prebuilding then
            local btbRgn = sharedBtbToggleRow._leftRegion
            local sw = CludesUI.BuildColorSwatch(btbRgn, btbRgn:GetFrameLevel() + 5, function()
                local c = SGet("btbBgColor")
                c = c or { r = 0.2, g = 0.2, b = 0.2 }
                local a = SGet("btbBgOpacity")
                return c.r, c.g, c.b, a or 1.0
            end, function(r, g, b, a)
                UNIT_DB_MAP[optionState.selectedUnit]().btbBgColor = { r = r, g = g, b = b }
                UNIT_DB_MAP[optionState.selectedUnit]().btbBgOpacity = a
                ReloadAndUpdate()
                UpdatePreview()
            end, true, 20)
            sw:SetPoint("RIGHT", btbRgn._lastInline or btbRgn._control, "LEFT", -12, 0)
            btbRgn._lastInline = sw
            -- Disabled state for swatch when text bar is off
            local function UpdateBtbSwatchState()
                local btbOn = SVal("bottomTextBar", false)
                if not btbOn then
                    sw:SetAlpha(0.15)
                    sw:Disable()
                    sw._disabledTooltip = "Text Bar"
                else
                    sw:SetAlpha(1)
                    sw:Enable()
                    sw._disabledTooltip = nil
                end
            end
            UpdateBtbSwatchState()
            RegisterWidgetRefresh(UpdateBtbSwatchState)
            sw:HookScript("OnEnter", function(self)
                if self._disabledTooltip then
                    CludesUI.ShowWidgetTooltip(self, CludesUI.DisabledTooltip(self._disabledTooltip))
                end
            end)
            sw:HookScript("OnLeave", function()
                CludesUI.HideWidgetTooltip()
            end)
        end
        -- Cog on Position for X/Y offsets
        if not CludesUI._prebuilding then
            local posRgn = sharedBtbToggleRow._rightRegion
            CludesUI.BuildInlineCog(posRgn, {
                disabled = function()
                    local place = SVal("btbPosition", "bottom")
                    return not SVal("bottomTextBar", false)
                        or (place ~= "detached_top" and place ~= "detached_bottom")
                end,
                disabledTooltip = function()
                    return not SVal("bottomTextBar", false) and "Text Bar"
                        or "This option requires a detached position to be active."
                end,
                title = "Detached Position Offsets",
                rows = {
                    {
                        type = "slider",
                        label = "X Offset",
                        min = -200,
                        max = 200,
                        step = 1,
                        get = function()
                            return SVal("btbX", 0)
                        end,
                        set = function(v)
                            SSet("btbX", v)
                            UpdatePreview()
                        end,
                    },
                    {
                        type = "slider",
                        label = "Y Offset",
                        min = -200,
                        max = 200,
                        step = 1,
                        get = function()
                            return SVal("btbY", 0)
                        end,
                        set = function(v)
                            SSet("btbY", v)
                            UpdatePreview()
                        end,
                    },
                },
            })
        end
    end -- close Blizzard Style text bar gate

    -- Rows 2-4 are HIDDEN while Enable Text Bar is off (DependentSetValue rebuilds
    -- on flips) and under Blizzard Style. Row locals referenced by the element-nav
    -- map are hoisted above the gate so the map never reads nil globals.
    local sharedBtbTextRow, sharedBtbCenterRow
    if SVal("bottomTextBar", false) and not CludesUI.BlizzStyle.Get("unitframes") then
        -- Row 2: Height + Width
        local sharedBtbHeightRow
        sharedBtbHeightRow, hgt = W:DualRow(hostFrame, posY, {
            type = "slider",
            text = "Height",
            min = 0,
            max = 100,
            step = 1,
            disabled = function()
                return not SVal("bottomTextBar", false)
            end,
            disabledTooltip = "Text Bar",
            getValue = function()
                return SVal("bottomTextBarHeight", 16)
            end,
            setValue = function(v)
                SSet("bottomTextBarHeight", v)
                UpdatePreview()
            end,
        }, {
            type = "slider",
            text = "Width",
            min = 0,
            max = 400,
            step = 1,
            disabled = function()
                if not SVal("bottomTextBar", false) then
                    return true
                end
                local place = SVal("btbPosition", "bottom")
                return place ~= "detached_top" and place ~= "detached_bottom"
            end,
            disabledTooltip = function()
                if not SVal("bottomTextBar", false) then
                    return "Text Bar"
                end
                return "This option requires the position setting to be detached"
            end,
            getValue = function()
                return SVal("btbWidth", 0)
            end,
            setValue = function(v)
                SSet("btbWidth", v)
                UpdatePreview()
            end,
        })
        posY = posY - hgt
        _sharedBtbWidthRgn = sharedBtbHeightRow._rightRegion
        do
            local place = SVal("btbPosition", "bottom")
            local isDet = (place == "detached_top" or place == "detached_bottom")
            if _sharedBtbWidthRgn._control and _sharedBtbWidthRgn._control.SetEnabled then
                _sharedBtbWidthRgn._control:SetEnabled(isDet)
            end
        end
        -- Sync icons: BTB Height (left) and BTB Width (right)
        if not CludesUI._prebuilding then
            local rgn = sharedBtbHeightRow._leftRegion
            mod.UFO_UnitSync(rgn, "Text Bar Height", {
                key = "bottomTextBarHeight",
                default = 16,
                self = true,
            })
        end
        if not CludesUI._prebuilding then
            local rgn = sharedBtbHeightRow._rightRegion
            mod.UFO_UnitSync(rgn, "Text Bar Width", {
                key = "btbWidth",
                default = 0,
                self = true,
            })
        end

        -- Custom on each slot opens the text slots' format popup; its format is
        -- the slot's own, so it is never cleared from the other slots. A selection
        -- keeps the page, so all three menus follow it.
        local function RefreshBtbMenus()
            local t, c = sharedBtbTextRow, sharedBtbCenterRow
            mod.UFO_RefreshMenus(t and t._leftRegion, t and t._rightRegion, c and c._leftRegion)
        end
        local function SetBtbLeft(v)
            SSet("btbLeftContent", v)
            if mod.UF_IsUniqueContent(v) then
                if SGet("btbRightContent") == v then
                    SSet("btbRightContent", "none")
                end
                if SGet("btbCenterContent") == v then
                    SSet("btbCenterContent", "none")
                end
            end
            ReloadAndUpdate()
            UpdatePreview()
            RefreshBtbMenus()
        end
        local function SetBtbRight(v)
            SSet("btbRightContent", v)
            if mod.UF_IsUniqueContent(v) then
                if SGet("btbLeftContent") == v then
                    SSet("btbLeftContent", "none")
                end
                if SGet("btbCenterContent") == v then
                    SSet("btbCenterContent", "none")
                end
            end
            ReloadAndUpdate()
            UpdatePreview()
            RefreshBtbMenus()
        end
        local function SetBtbCenter(v)
            SSet("btbCenterContent", v)
            if v ~= "none" then
                SSet("btbLeftContent", "none")
                SSet("btbRightContent", "none")
            end
            ReloadAndUpdate()
            UpdatePreview()
            RefreshBtbMenus()
        end
        local function BtbValues(prefixText, setValue)
            return mod.UFO_CustomTextValues(btbTextValues, function()
                return SVal(prefixText .. "Content", "none")
            end, function()
                mod.UFO_EditCustomText(prefixText, context.SDB(), optionState.selectedUnit, function()
                    setValue("custom")
                end)
            end)
        end

        -- Row 3: Left Text + Right Text
        sharedBtbTextRow, hgt = W:DualRow(hostFrame, posY, {
            type = "dropdown",
            text = "Left Text",
            values = BtbValues("btbLeft", SetBtbLeft),
            order = btbTextOrder,
            disabled = function()
                return not SVal("bottomTextBar", false)
            end,
            disabledTooltip = "Text Bar",
            getValue = function()
                return SVal("btbLeftContent", "none")
            end,
            setValue = SetBtbLeft,
        }, {
            type = "dropdown",
            text = "Right Text",
            values = BtbValues("btbRight", SetBtbRight),
            order = btbTextOrder,
            disabled = function()
                return not SVal("bottomTextBar", false)
            end,
            disabledTooltip = "Text Bar",
            getValue = function()
                return SVal("btbRightContent", "none")
            end,
            setValue = SetBtbRight,
        })
        posY = posY - hgt
        if not CludesUI._prebuilding then
            local apply = function()
                ReloadAndUpdate()
                UpdatePreview()
            end
            mod.UFO_AddCustomFormatAccessor(
                sharedBtbTextRow._leftRegion,
                "BTB Left Text",
                "btbLeft",
                SVal("btbLeftContent", "none"),
                context.SDB,
                apply
            )
            mod.UFO_AddCustomFormatAccessor(
                sharedBtbTextRow._rightRegion,
                "BTB Right Text",
                "btbRight",
                SVal("btbRightContent", "none"),
                context.SDB,
                apply
            )
        end
        -- Cogwheel on BTB Left Text
        if not CludesUI._prebuilding then
            local btbLRgn = sharedBtbTextRow._leftRegion
            CludesUI.BuildInlineCog(btbLRgn, {
                disabled = function()
                    return not SVal("bottomTextBar", false) or SVal("btbLeftContent", "none") == "none"
                end,
                disabledTooltip = function()
                    return not SVal("bottomTextBar", false) and "Text Bar"
                        or "This option requires a text selection other than none."
                end,
                title = "BTB Left Text Settings",
                rows = mod.UF_NameFormatRows("btbLeft", "none", SVal, SSet, {
                    {
                        type = "slider",
                        label = "Size",
                        min = 8,
                        max = 100,
                        step = 1,
                        get = function()
                            return SVal("btbLeftSize", 11)
                        end,
                        set = function(v)
                            SSet("btbLeftSize", v)
                            UpdatePreview()
                        end,
                    },
                    {
                        type = "slider",
                        label = "X Offset",
                        min = -100,
                        max = 100,
                        step = 1,
                        get = function()
                            return SVal("btbLeftX", 0)
                        end,
                        set = function(v)
                            SSet("btbLeftX", v)
                            UpdatePreview()
                        end,
                    },
                    {
                        type = "slider",
                        label = "Y Offset",
                        min = -60,
                        max = 60,
                        step = 1,
                        get = function()
                            return SVal("btbLeftY", 0)
                        end,
                        set = function(v)
                            SSet("btbLeftY", v)
                            UpdatePreview()
                        end,
                    },
                    {
                        type = "slider",
                        label = "Width %",
                        min = 20,
                        max = 200,
                        step = 5,
                        get = function()
                            return SVal("btbLeftWidthPct", 100)
                        end,
                        set = function(v)
                            SSet("btbLeftWidthPct", v)
                            UpdatePreview()
                        end,
                    },
                    {
                        type = "multiswatch",
                        label = "Indicator Color",
                        disabled = function()
                            return SVal("btbLeftContent", "none") ~= "nametotarget"
                        end,
                        disabledTooltip = "Only applies when Name > Target is selected.",
                        swatches = {
                            {
                                tooltip = "Custom Colored",
                                hasAlpha = false,
                                getValue = function()
                                    local c = SVal("btbLeftTargetSepColor", nil)
                                    if type(c) == "table" then
                                        return c.r or 1, c.g or 1, c.b or 1
                                    end
                                    return 1, 1, 1
                                end,
                                setValue = function(r, g, b)
                                    SSet("btbLeftTargetSepColor", { r = r, g = g, b = b })
                                    UpdatePreview()
                                end,
                                onClick = function(self)
                                    if SVal("btbLeftTargetSepClassColor", false) then
                                        SSet("btbLeftTargetSepClassColor", false)
                                        UpdatePreview()
                                        return
                                    end
                                    if self._eabOrigClick then
                                        self._eabOrigClick(self)
                                    end
                                end,
                                refreshAlpha = function()
                                    return SVal("btbLeftTargetSepClassColor", false) and 0.3 or 1
                                end,
                            },
                            {
                                tooltip = "Class Colored",
                                hasAlpha = false,
                                getValue = CludesUI.PlayerClassRGB,
                                setValue = function() end,
                                onClick = function()
                                    SSet("btbLeftTargetSepClassColor", true)
                                    UpdatePreview()
                                end,
                                refreshAlpha = function()
                                    return SVal("btbLeftTargetSepClassColor", false) and 1 or 0.3
                                end,
                            },
                        },
                    },
                    {
                        type = "input",
                        label = "Separator",
                        inputWidth = 60,
                        get = function()
                            return SVal("btbLeftTargetSep", ">")
                        end,
                        set = function(v)
                            v = tostring(v or ""):gsub("|", ""):gsub("^%s+", ""):gsub("%s+$", "")
                            if v == "" then
                                v = ">"
                            end
                            SSet("btbLeftTargetSep", v)
                            UpdatePreview()
                        end,
                        disabled = function()
                            return SVal("btbLeftContent", "none") ~= "nametotarget"
                        end,
                        disabledTooltip = "Only applies when Name > Target is selected.",
                    },
                }),
            })
        end
        -- Inline color swatches on BTB Left Text: Custom + Class (CDM Border Size
        -- pattern). Power Color stays in the cog; the three modes are mutually exclusive.
        if not CludesUI._prebuilding then
            local btbLRgn = sharedBtbTextRow._leftRegion
            local function blOff()
                return SVal("btbLeftContent", "none") == "none" or not SVal("bottomTextBar", false)
            end
            local blClassSwatch, blUpdateClassSwatch = CludesUI.BuildColorSwatch(
                btbLRgn,
                btbLRgn:GetFrameLevel() + 5,
                function()
                    local _, class = UnitClass("player")
                    local cc = class and CludesUI.GetClassColor(class)
                    if cc then
                        return cc.r, cc.g, cc.b
                    end
                    return 1, 1, 1
                end,
                function() end,
                nil,
                20
            )
            Pix.Point(blClassSwatch, "RIGHT", btbLRgn._lastInline or btbLRgn._control, "LEFT", -8, 0)
            blClassSwatch:SetScript("OnClick", function()
                if blOff() then
                    return
                end
                SSet("btbLeftClassColor", true)
                SSet("btbLeftPowerColor", false)
                UpdatePreview()
                CludesUI:RefreshPage()
            end)
            CludesUI.HoverTip(blClassSwatch, "Class Colored")
            local blSwGet = function()
                return SVal("btbLeftColorR", 1), SVal("btbLeftColorG", 1), SVal("btbLeftColorB", 1)
            end
            local blSwSet = function(r, g, b)
                SSet("btbLeftColorR", r)
                SSet("btbLeftColorG", g)
                SSet("btbLeftColorB", b)
                UpdatePreview()
            end
            local blSwatch, blUpdateSwatch =
                CludesUI.BuildColorSwatch(btbLRgn, btbLRgn:GetFrameLevel() + 5, blSwGet, blSwSet, nil, 20)
            Pix.Point(blSwatch, "RIGHT", blClassSwatch, "LEFT", -8, 0)
            btbLRgn._lastInline = blSwatch
            local blOrigClick = blSwatch:GetScript("OnClick")
            blSwatch:SetScript("OnClick", function(self, ...)
                if blOff() then
                    return
                end
                if SVal("btbLeftClassColor", false) or SVal("btbLeftPowerColor", false) then
                    SSet("btbLeftClassColor", false)
                    SSet("btbLeftPowerColor", false)
                    UpdatePreview()
                    CludesUI:RefreshPage()
                    return
                end
                if blOrigClick then
                    blOrigClick(self, ...)
                end
            end)
            CludesUI.HoverTip(blSwatch, "Custom Colored")
            -- Power Color swatch: shows the player's current power color; click to
            -- select power-colored mode. Same per-unit power resolution as the power
            -- bar text (white fallback when the power token can't resolve).
            local blPowerSwatch, blUpdatePowerSwatch = CludesUI.BuildColorSwatch(
                btbLRgn,
                btbLRgn:GetFrameLevel() + 5,
                function()
                    local _, pToken = UnitPowerType("player")
                    local details = CludesUI.GetPowerColor(pToken or "MANA")
                    if details then
                        return details.r, details.g, details.b
                    end
                    return 1, 1, 1
                end,
                function() end,
                nil,
                20
            )
            Pix.Point(blPowerSwatch, "RIGHT", blSwatch, "LEFT", -8, 0)
            btbLRgn._lastInline = blPowerSwatch
            blPowerSwatch:SetScript("OnClick", function()
                if blOff() then
                    return
                end
                SSet("btbLeftPowerColor", true)
                SSet("btbLeftClassColor", false)
                UpdatePreview()
                CludesUI:RefreshPage()
            end)
            CludesUI.HoverTip(blPowerSwatch, "Power Colored")
            local function UpdateBlSwatches()
                local off = blOff()
                local isClass = SVal("btbLeftClassColor", false)
                local isPower = SVal("btbLeftPowerColor", false)
                blSwatch:SetAlpha((isClass or isPower or off) and 0.3 or 1)
                blClassSwatch:SetAlpha((isClass and not off) and 1 or 0.3)
                blPowerSwatch:SetAlpha((isPower and not off) and 1 or 0.3)
            end
            RegisterWidgetRefresh(function()
                blUpdateSwatch()
                blUpdateClassSwatch()
                blUpdatePowerSwatch()
                UpdateBlSwatches()
            end)
            UpdateBlSwatches()
        end
        -- Cogwheel on BTB Right Text
        if not CludesUI._prebuilding then
            local btbRRgn = sharedBtbTextRow._rightRegion
            CludesUI.BuildInlineCog(btbRRgn, {
                disabled = function()
                    return not SVal("bottomTextBar", false) or SVal("btbRightContent", "none") == "none"
                end,
                disabledTooltip = function()
                    return not SVal("bottomTextBar", false) and "Text Bar"
                        or "This option requires a text selection other than none."
                end,
                title = "BTB Right Text Settings",
                rows = mod.UF_NameFormatRows("btbRight", "none", SVal, SSet, {
                    {
                        type = "slider",
                        label = "Size",
                        min = 8,
                        max = 100,
                        step = 1,
                        get = function()
                            return SVal("btbRightSize", 11)
                        end,
                        set = function(v)
                            SSet("btbRightSize", v)
                            UpdatePreview()
                        end,
                    },
                    {
                        type = "slider",
                        label = "X Offset",
                        min = -100,
                        max = 100,
                        step = 1,
                        get = function()
                            return SVal("btbRightX", 0)
                        end,
                        set = function(v)
                            SSet("btbRightX", v)
                            UpdatePreview()
                        end,
                    },
                    {
                        type = "slider",
                        label = "Y Offset",
                        min = -60,
                        max = 60,
                        step = 1,
                        get = function()
                            return SVal("btbRightY", 0)
                        end,
                        set = function(v)
                            SSet("btbRightY", v)
                            UpdatePreview()
                        end,
                    },
                    {
                        type = "slider",
                        label = "Width %",
                        min = 20,
                        max = 200,
                        step = 5,
                        get = function()
                            return SVal("btbRightWidthPct", 100)
                        end,
                        set = function(v)
                            SSet("btbRightWidthPct", v)
                            UpdatePreview()
                        end,
                    },
                    {
                        type = "multiswatch",
                        label = "Indicator Color",
                        disabled = function()
                            return SVal("btbRightContent", "none") ~= "nametotarget"
                        end,
                        disabledTooltip = "Only applies when Name > Target is selected.",
                        swatches = {
                            {
                                tooltip = "Custom Colored",
                                hasAlpha = false,
                                getValue = function()
                                    local c = SVal("btbRightTargetSepColor", nil)
                                    if type(c) == "table" then
                                        return c.r or 1, c.g or 1, c.b or 1
                                    end
                                    return 1, 1, 1
                                end,
                                setValue = function(r, g, b)
                                    SSet("btbRightTargetSepColor", { r = r, g = g, b = b })
                                    UpdatePreview()
                                end,
                                onClick = function(self)
                                    if SVal("btbRightTargetSepClassColor", false) then
                                        SSet("btbRightTargetSepClassColor", false)
                                        UpdatePreview()
                                        return
                                    end
                                    if self._eabOrigClick then
                                        self._eabOrigClick(self)
                                    end
                                end,
                                refreshAlpha = function()
                                    return SVal("btbRightTargetSepClassColor", false) and 0.3 or 1
                                end,
                            },
                            {
                                tooltip = "Class Colored",
                                hasAlpha = false,
                                getValue = CludesUI.PlayerClassRGB,
                                setValue = function() end,
                                onClick = function()
                                    SSet("btbRightTargetSepClassColor", true)
                                    UpdatePreview()
                                end,
                                refreshAlpha = function()
                                    return SVal("btbRightTargetSepClassColor", false) and 1 or 0.3
                                end,
                            },
                        },
                    },
                    {
                        type = "input",
                        label = "Separator",
                        inputWidth = 60,
                        get = function()
                            return SVal("btbRightTargetSep", ">")
                        end,
                        set = function(v)
                            v = tostring(v or ""):gsub("|", ""):gsub("^%s+", ""):gsub("%s+$", "")
                            if v == "" then
                                v = ">"
                            end
                            SSet("btbRightTargetSep", v)
                            UpdatePreview()
                        end,
                        disabled = function()
                            return SVal("btbRightContent", "none") ~= "nametotarget"
                        end,
                        disabledTooltip = "Only applies when Name > Target is selected.",
                    },
                }),
            })
        end
        -- Inline color swatches on BTB Right Text: Custom + Class (Power Color stays in
        -- the cog; the three modes are mutually exclusive).
        if not CludesUI._prebuilding then
            local btbRRgn = sharedBtbTextRow._rightRegion
            local function brOff()
                return SVal("btbRightContent", "none") == "none" or not SVal("bottomTextBar", false)
            end
            local brClassSwatch, brUpdateClassSwatch = CludesUI.BuildColorSwatch(
                btbRRgn,
                btbRRgn:GetFrameLevel() + 5,
                function()
                    local _, class = UnitClass("player")
                    local cc = class and CludesUI.GetClassColor(class)
                    if cc then
                        return cc.r, cc.g, cc.b
                    end
                    return 1, 1, 1
                end,
                function() end,
                nil,
                20
            )
            Pix.Point(brClassSwatch, "RIGHT", btbRRgn._lastInline or btbRRgn._control, "LEFT", -8, 0)
            brClassSwatch:SetScript("OnClick", function()
                if brOff() then
                    return
                end
                SSet("btbRightClassColor", true)
                SSet("btbRightPowerColor", false)
                UpdatePreview()
                CludesUI:RefreshPage()
            end)
            CludesUI.HoverTip(brClassSwatch, "Class Colored")
            local brSwGet = function()
                return SVal("btbRightColorR", 1), SVal("btbRightColorG", 1), SVal("btbRightColorB", 1)
            end
            local brSwSet = function(r, g, b)
                SSet("btbRightColorR", r)
                SSet("btbRightColorG", g)
                SSet("btbRightColorB", b)
                UpdatePreview()
            end
            local brSwatch, brUpdateSwatch =
                CludesUI.BuildColorSwatch(btbRRgn, btbRRgn:GetFrameLevel() + 5, brSwGet, brSwSet, nil, 20)
            Pix.Point(brSwatch, "RIGHT", brClassSwatch, "LEFT", -8, 0)
            btbRRgn._lastInline = brSwatch
            local brOrigClick = brSwatch:GetScript("OnClick")
            brSwatch:SetScript("OnClick", function(self, ...)
                if brOff() then
                    return
                end
                if SVal("btbRightClassColor", false) or SVal("btbRightPowerColor", false) then
                    SSet("btbRightClassColor", false)
                    SSet("btbRightPowerColor", false)
                    UpdatePreview()
                    CludesUI:RefreshPage()
                    return
                end
                if brOrigClick then
                    brOrigClick(self, ...)
                end
            end)
            CludesUI.HoverTip(brSwatch, "Custom Colored")
            -- Power Color swatch: shows the player's current power color; click to
            -- select power-colored mode. Same per-unit power resolution as the power
            -- bar text (white fallback when the power token can't resolve).
            local brPowerSwatch, brUpdatePowerSwatch = CludesUI.BuildColorSwatch(
                btbRRgn,
                btbRRgn:GetFrameLevel() + 5,
                function()
                    local _, pToken = UnitPowerType("player")
                    local details = CludesUI.GetPowerColor(pToken or "MANA")
                    if details then
                        return details.r, details.g, details.b
                    end
                    return 1, 1, 1
                end,
                function() end,
                nil,
                20
            )
            Pix.Point(brPowerSwatch, "RIGHT", brSwatch, "LEFT", -8, 0)
            btbRRgn._lastInline = brPowerSwatch
            brPowerSwatch:SetScript("OnClick", function()
                if brOff() then
                    return
                end
                SSet("btbRightPowerColor", true)
                SSet("btbRightClassColor", false)
                UpdatePreview()
                CludesUI:RefreshPage()
            end)
            CludesUI.HoverTip(brPowerSwatch, "Power Colored")
            local function UpdateBrSwatches()
                local off = brOff()
                local isClass = SVal("btbRightClassColor", false)
                local isPower = SVal("btbRightPowerColor", false)
                brSwatch:SetAlpha((isClass or isPower or off) and 0.3 or 1)
                brClassSwatch:SetAlpha((isClass and not off) and 1 or 0.3)
                brPowerSwatch:SetAlpha((isPower and not off) and 1 or 0.3)
            end
            RegisterWidgetRefresh(function()
                brUpdateSwatch()
                brUpdateClassSwatch()
                brUpdatePowerSwatch()
                UpdateBrSwatches()
            end)
            UpdateBrSwatches()
        end
        -- Sync icons: BTB Left Text (left) and BTB Right Text (right)
        if not CludesUI._prebuilding then
            local rgn = sharedBtbTextRow._leftRegion
            TextSlotSync(rgn, "Text Bar Left Text", "Left")
        end
        if not CludesUI._prebuilding then
            local rgn = sharedBtbTextRow._rightRegion
            TextSlotSync(rgn, "Text Bar Right Text", "Right")
        end

        -- Row 4: Center Text + Class Icon
        sharedBtbCenterRow, hgt = W:DualRow(hostFrame, posY, {
            type = "dropdown",
            text = "Center Text",
            values = BtbValues("btbCenter", SetBtbCenter),
            order = btbTextOrder,
            disabled = function()
                return not SVal("bottomTextBar", false)
            end,
            disabledTooltip = "Text Bar",
            getValue = function()
                return SVal("btbCenterContent", "none")
            end,
            setValue = SetBtbCenter,
        }, {
            type = "dropdown",
            text = "Class Icon",
            values = classIconValues,
            order = classIconOrder,
            disabled = function()
                return not SVal("bottomTextBar", false)
            end,
            disabledTooltip = "Text Bar",
            getValue = function()
                return SVal("btbClassIcon", "none")
            end,
            setValue = function(v)
                SSet("btbClassIcon", v)
                UpdatePreview()
            end,
        })
        posY = posY - hgt
        if not CludesUI._prebuilding then
            mod.UFO_AddCustomFormatAccessor(
                sharedBtbCenterRow._leftRegion,
                "BTB Center Text",
                "btbCenter",
                SVal("btbCenterContent", "none"),
                context.SDB,
                function()
                    ReloadAndUpdate()
                    UpdatePreview()
                end
            )
        end
        -- Cogwheel on BTB Center Text
        if not CludesUI._prebuilding then
            local btbCRgn = sharedBtbCenterRow._leftRegion
            CludesUI.BuildInlineCog(btbCRgn, {
                disabled = function()
                    return not SVal("bottomTextBar", false) or SVal("btbCenterContent", "none") == "none"
                end,
                disabledTooltip = function()
                    return not SVal("bottomTextBar", false) and "Text Bar"
                        or "This option requires a text selection other than none."
                end,
                title = "BTB Center Text Settings",
                rows = mod.UF_NameFormatRows("btbCenter", "none", SVal, SSet, {
                    {
                        type = "slider",
                        label = "Size",
                        min = 8,
                        max = 100,
                        step = 1,
                        get = function()
                            return SVal("btbCenterSize", 11)
                        end,
                        set = function(v)
                            SSet("btbCenterSize", v)
                            UpdatePreview()
                        end,
                    },
                    {
                        type = "slider",
                        label = "X Offset",
                        min = -100,
                        max = 100,
                        step = 1,
                        get = function()
                            return SVal("btbCenterX", 0)
                        end,
                        set = function(v)
                            SSet("btbCenterX", v)
                            UpdatePreview()
                        end,
                    },
                    {
                        type = "slider",
                        label = "Y Offset",
                        min = -60,
                        max = 60,
                        step = 1,
                        get = function()
                            return SVal("btbCenterY", 0)
                        end,
                        set = function(v)
                            SSet("btbCenterY", v)
                            UpdatePreview()
                        end,
                    },
                    {
                        type = "slider",
                        label = "Width %",
                        min = 20,
                        max = 200,
                        step = 5,
                        get = function()
                            return SVal("btbCenterWidthPct", 100)
                        end,
                        set = function(v)
                            SSet("btbCenterWidthPct", v)
                            UpdatePreview()
                        end,
                    },
                    {
                        type = "multiswatch",
                        label = "Indicator Color",
                        disabled = function()
                            return SVal("btbCenterContent", "none") ~= "nametotarget"
                        end,
                        disabledTooltip = "Only applies when Name > Target is selected.",
                        swatches = {
                            {
                                tooltip = "Custom Colored",
                                hasAlpha = false,
                                getValue = function()
                                    local c = SVal("btbCenterTargetSepColor", nil)
                                    if type(c) == "table" then
                                        return c.r or 1, c.g or 1, c.b or 1
                                    end
                                    return 1, 1, 1
                                end,
                                setValue = function(r, g, b)
                                    SSet("btbCenterTargetSepColor", { r = r, g = g, b = b })
                                    UpdatePreview()
                                end,
                                onClick = function(self)
                                    if SVal("btbCenterTargetSepClassColor", false) then
                                        SSet("btbCenterTargetSepClassColor", false)
                                        UpdatePreview()
                                        return
                                    end
                                    if self._eabOrigClick then
                                        self._eabOrigClick(self)
                                    end
                                end,
                                refreshAlpha = function()
                                    return SVal("btbCenterTargetSepClassColor", false) and 0.3 or 1
                                end,
                            },
                            {
                                tooltip = "Class Colored",
                                hasAlpha = false,
                                getValue = CludesUI.PlayerClassRGB,
                                setValue = function() end,
                                onClick = function()
                                    SSet("btbCenterTargetSepClassColor", true)
                                    UpdatePreview()
                                end,
                                refreshAlpha = function()
                                    return SVal("btbCenterTargetSepClassColor", false) and 1 or 0.3
                                end,
                            },
                        },
                    },
                    {
                        type = "input",
                        label = "Separator",
                        inputWidth = 60,
                        get = function()
                            return SVal("btbCenterTargetSep", ">")
                        end,
                        set = function(v)
                            v = tostring(v or ""):gsub("|", ""):gsub("^%s+", ""):gsub("%s+$", "")
                            if v == "" then
                                v = ">"
                            end
                            SSet("btbCenterTargetSep", v)
                            UpdatePreview()
                        end,
                        disabled = function()
                            return SVal("btbCenterContent", "none") ~= "nametotarget"
                        end,
                        disabledTooltip = "Only applies when Name > Target is selected.",
                    },
                }),
            })
        end
        -- Inline color swatches on BTB Center Text: Custom + Class (Power Color stays in
        -- the cog; the three modes are mutually exclusive).
        if not CludesUI._prebuilding then
            local btbCRgn = sharedBtbCenterRow._leftRegion
            local function bcOff()
                return SVal("btbCenterContent", "none") == "none" or not SVal("bottomTextBar", false)
            end
            local bcClassSwatch, bcUpdateClassSwatch = CludesUI.BuildColorSwatch(
                btbCRgn,
                btbCRgn:GetFrameLevel() + 5,
                function()
                    local _, class = UnitClass("player")
                    local cc = class and CludesUI.GetClassColor(class)
                    if cc then
                        return cc.r, cc.g, cc.b
                    end
                    return 1, 1, 1
                end,
                function() end,
                nil,
                20
            )
            Pix.Point(bcClassSwatch, "RIGHT", btbCRgn._lastInline or btbCRgn._control, "LEFT", -8, 0)
            bcClassSwatch:SetScript("OnClick", function()
                if bcOff() then
                    return
                end
                SSet("btbCenterClassColor", true)
                SSet("btbCenterPowerColor", false)
                UpdatePreview()
                CludesUI:RefreshPage()
            end)
            CludesUI.HoverTip(bcClassSwatch, "Class Colored")
            local bcSwGet = function()
                return SVal("btbCenterColorR", 1), SVal("btbCenterColorG", 1), SVal("btbCenterColorB", 1)
            end
            local bcSwSet = function(r, g, b)
                SSet("btbCenterColorR", r)
                SSet("btbCenterColorG", g)
                SSet("btbCenterColorB", b)
                UpdatePreview()
            end
            local bcSwatch, bcUpdateSwatch =
                CludesUI.BuildColorSwatch(btbCRgn, btbCRgn:GetFrameLevel() + 5, bcSwGet, bcSwSet, nil, 20)
            Pix.Point(bcSwatch, "RIGHT", bcClassSwatch, "LEFT", -8, 0)
            btbCRgn._lastInline = bcSwatch
            local bcOrigClick = bcSwatch:GetScript("OnClick")
            bcSwatch:SetScript("OnClick", function(self, ...)
                if bcOff() then
                    return
                end
                if SVal("btbCenterClassColor", false) or SVal("btbCenterPowerColor", false) then
                    SSet("btbCenterClassColor", false)
                    SSet("btbCenterPowerColor", false)
                    UpdatePreview()
                    CludesUI:RefreshPage()
                    return
                end
                if bcOrigClick then
                    bcOrigClick(self, ...)
                end
            end)
            CludesUI.HoverTip(bcSwatch, "Custom Colored")
            -- Power Color swatch: shows the player's current power color; click to
            -- select power-colored mode. Same per-unit power resolution as the power
            -- bar text (white fallback when the power token can't resolve).
            local bcPowerSwatch, bcUpdatePowerSwatch = CludesUI.BuildColorSwatch(
                btbCRgn,
                btbCRgn:GetFrameLevel() + 5,
                function()
                    local _, pToken = UnitPowerType("player")
                    local details = CludesUI.GetPowerColor(pToken or "MANA")
                    if details then
                        return details.r, details.g, details.b
                    end
                    return 1, 1, 1
                end,
                function() end,
                nil,
                20
            )
            Pix.Point(bcPowerSwatch, "RIGHT", bcSwatch, "LEFT", -8, 0)
            btbCRgn._lastInline = bcPowerSwatch
            bcPowerSwatch:SetScript("OnClick", function()
                if bcOff() then
                    return
                end
                SSet("btbCenterPowerColor", true)
                SSet("btbCenterClassColor", false)
                UpdatePreview()
                CludesUI:RefreshPage()
            end)
            CludesUI.HoverTip(bcPowerSwatch, "Power Colored")
            local function UpdateBcSwatches()
                local off = bcOff()
                local isClass = SVal("btbCenterClassColor", false)
                local isPower = SVal("btbCenterPowerColor", false)
                bcSwatch:SetAlpha((isClass or isPower or off) and 0.3 or 1)
                bcClassSwatch:SetAlpha((isClass and not off) and 1 or 0.3)
                bcPowerSwatch:SetAlpha((isPower and not off) and 1 or 0.3)
            end
            RegisterWidgetRefresh(function()
                bcUpdateSwatch()
                bcUpdateClassSwatch()
                bcUpdatePowerSwatch()
                UpdateBcSwatches()
            end)
            UpdateBcSwatches()
        end
        -- Cogwheel on Class Icon for size/location/x/y
        if not CludesUI._prebuilding then
            local ciRgn = sharedBtbCenterRow._rightRegion
            CludesUI.BuildInlineCog(ciRgn, {
                disabled = function()
                    return not SVal("bottomTextBar", false) or SVal("btbClassIcon", "none") == "none"
                end,
                disabledTooltip = function()
                    return not SVal("bottomTextBar", false) and "Text Bar"
                        or "This option requires a Class Icon other than None."
                end,
                title = "Class Icon Settings",
                rows = {
                    {
                        type = "slider",
                        label = "Size",
                        min = 8,
                        max = 60,
                        step = 1,
                        get = function()
                            return SVal("btbClassIconSize", 14)
                        end,
                        set = function(v)
                            SSet("btbClassIconSize", v)
                            UpdatePreview()
                        end,
                    },
                    {
                        type = "dropdown",
                        label = "Location",
                        values = classIconLocValues,
                        order = classIconLocOrder,
                        get = function()
                            return SVal("btbClassIconLocation", "left")
                        end,
                        set = function(v)
                            SSet("btbClassIconLocation", v)
                            UpdatePreview()
                        end,
                    },
                    {
                        type = "slider",
                        label = "X Offset",
                        min = -50,
                        max = 50,
                        step = 1,
                        get = function()
                            return SVal("btbClassIconX", 0)
                        end,
                        set = function(v)
                            SSet("btbClassIconX", v)
                            UpdatePreview()
                        end,
                    },
                    {
                        type = "slider",
                        label = "Y Offset",
                        min = -50,
                        max = 50,
                        step = 1,
                        get = function()
                            return SVal("btbClassIconY", 0)
                        end,
                        set = function(v)
                            SSet("btbClassIconY", v)
                            UpdatePreview()
                        end,
                    },
                },
            })
        end
        -- Sync icons: BTB Center Text (left) and Class Icon (right)
        if not CludesUI._prebuilding then
            local rgn = sharedBtbCenterRow._leftRegion
            TextSlotSync(rgn, "Text Bar Center Text", "Center")
        end
        if not CludesUI._prebuilding then
            local rgn = sharedBtbCenterRow._rightRegion
            mod.UFO_UnitSync(rgn, "Text Bar Class Icon", {
                key = "btbClassIcon",
                default = "none",
                self = true,
            })
        end
    end -- close Text Bar hidden-while-disabled gate

    return posY, sharedBtbHeader, sharedBtbToggleRow, sharedBtbTextRow, sharedBtbCenterRow
end

function mod.UFO_BuildExtrasSection(hostFrame, posY, context)
    local environ = mod._UFO_OptEnv
    local CLASS_FULL_COORDS, RegisterWidgetRefresh, ReloadAndUpdate =
        environ.CLASS_FULL_COORDS, environ.RegisterWidgetRefresh, environ.ReloadAndUpdate
    local UNIT_DB_MAP, UpdatePreview, saved = environ.UNIT_DB_MAP, environ.UpdatePreview, environ.db
    local optionState = environ.optState
    local W, SApplySupport, SDB, SGetSupported =
        context.W, context.SApplySupport, context.SDB, context.SGetSupported
    local SSetSupported, SValSupported, SVisible =
        context.SSetSupported, context.SValSupported, context.SVisible
    local hgt

    local sharedAddHeader
    -------------------------------------------------------------------
    --  EXTRAS
    -------------------------------------------------------------------
    sharedAddHeader, hgt = W:SectionHeader(hostFrame, "EXTRAS", posY)
    posY = posY - hgt

    -- Row 1: Combat Indicator (absorb settings live in the ABSORBS section above)
    -- Declared outside the gate: the click-mapping table at the bottom of
    -- this function references it (a block-local would be nil there).
    local sharedAddRow1
    local _showAbsorbsCombat = (
        optionState.selectedUnit == "player"
        or optionState.selectedUnit == "target"
        or optionState.selectedUnit == "focus"
    )
    if _showAbsorbsCombat then
        local COMBAT_MEDIA_P = "Interface\\AddOns\\CludesUI\\media\\combat\\"
        local combatIndValues = {
            ["none"] = "None",
            ["standard"] = "Standard",
            ["class"] = "Class Theme",
            _menuOpts = {
                itemHeight = 32,
                icon = function(key)
                    if key == "none" then
                        return nil
                    end
                    if key == "class" then
                        local _, ct = UnitClass("player")
                        if not ct then
                            return nil
                        end
                        local coords = CLASS_FULL_COORDS[ct]
                        if not coords then
                            return nil
                        end
                        return COMBAT_MEDIA_P .. "combat-indicator-class-custom.png",
                            coords[1],
                            coords[2],
                            coords[3],
                            coords[4]
                    elseif key == "standard" then
                        return COMBAT_MEDIA_P .. "combat-indicator-custom.png", 0, 1, 0, 1
                    else
                        -- New full-colour combat icons (combat0..combat5), shown as-is.
                        return COMBAT_MEDIA_P .. key .. ".tga", 0, 1, 0, 1
                    end
                end,
            },
        }
        local combatIndOrder = { "none", "standard", "class" }
        -- combat0..2 (Arcade/Dungeoneer/Classic) are shown as-is (non-colorable);
        -- combat3..5 (Cross/Circle/Square) are colorable like Standard/Class Theme.
        local _combatNames = {
            [0] = "Arcade",
            [1] = "Dungeoneer",
            [2] = "Classic",
            [3] = "Cross",
            [4] = "Circle",
            [5] = "Square",
        }
        for _i = 0, 5 do
            combatIndValues["combat" .. _i] = _combatNames[_i]
            combatIndOrder[#combatIndOrder + 1] = "combat" .. _i
        end
        -- Enemy Colors helper: custom reaction colors for non-player units.
        -- Global (one set shared by all frames); empty entries fall back to
        -- Blizzard defaults. Consumed by the Enemy Colors multiSwatch in slot 2.
        local function enemySwatch(key, defIdx, dr, dg, dbb, tipText)
            return {
                tooltip = tipText,
                getValue = function()
                    local ec = saved.profile.enemyColors or {}
                    local c = ec[key]
                    if c then
                        return c.r, c.g, c.b
                    end
                    local f = defIdx and FACTION_BAR_COLORS[defIdx]
                    if f then
                        return f.r, f.g, f.b
                    end
                    return dr, dg, dbb
                end,
                setValue = function(r, g, b)
                    saved.profile.enemyColors = saved.profile.enemyColors or {}
                    saved.profile.enemyColors[key] = { r = r, g = g, b = b }
                    if mod.ApplyEnemyColors then
                        mod.ApplyEnemyColors()
                    end
                end,
            }
        end
        sharedAddRow1, hgt = W:DualRow(hostFrame, posY, {
            type = "dropdown",
            text = "Combat Indicator",
            values = combatIndValues,
            order = combatIndOrder,
            -- Target ships disabled ("none"): opt-in, no change for existing users.
            getValue = function()
                return SValSupported(
                    "combatIndicatorStyle",
                    optionState.selectedUnit == "player" and "class" or "none"
                )
            end,
            setValue = function(v)
                SSetSupported("combatIndicatorStyle", v)
                ReloadAndUpdate()
                UpdatePreview()
            end,
        }, {
            type = "multiSwatch",
            text = "Enemy Colors",
            swatches = {
                enemySwatch("hostile", 2, 0.78, 0.25, 0.25, "Hostile"),
                enemySwatch("neutral", 4, 0.85, 0.77, 0.36, "Neutral"),
                enemySwatch("friendly", 5, 0.29, 0.68, 0.30, "Friendly NPC"),
                enemySwatch("tapped", nil, 0.6, 0.6, 0.6, "Tapped"),
            },
        })
        posY = posY - hgt
        if not CludesUI._prebuilding then
            SApplySupport(
                sharedAddRow1._leftRegion,
                "combatIndicatorStyle",
                "The Combat Indicator is not available for the Focus frame."
            )
        end
        -- Sync icon: Combat Indicator (player + target only -- focus has none)
        if SVisible("combatIndicatorStyle") and not CludesUI._prebuilding then
            mod.UFO_UnitSync(sharedAddRow1._leftRegion, "Combat Indicator Style", {
                units = { "player", "target" },
                key = "combatIndicatorStyle",
                default = "class",
                self = true,
            })
        end

        -- Eyeball toggle + cog + swatch on combat indicator dropdown
        -- (player + target only -- the focus row is dimmed with a tooltip)
        if SVisible("combatIndicatorStyle") and not CludesUI._prebuilding then
            local ciRgn = sharedAddRow1._leftRegion
            CludesUI.AddPreviewEye(ciRgn, optionState, "showCombatIndicatorPreview", "combat indicator", UpdatePreview)

            -- Cog popup for combat indicator settings
            -- "healthbar" is the long-standing stored value for centered-on-health-bar,
            -- shown as "Center". "center" (briefly stored by 8.4.9-era builds) maps to it.
            local combatPosValues = {
                ["topleft"] = "Top Left",
                ["topright"] = "Top Right",
                ["healthbar"] = "Center",
                ["bottomleft"] = "Bottom Left",
                ["bottomright"] = "Bottom Right",
                ["textbar"] = "Text Bar",
                ["portrait"] = "Portrait",
            }
            local combatPosOrder =
                { "topleft", "topright", "healthbar", "bottomleft", "bottomright", "textbar", "portrait" }

            CludesUI.BuildInlineCog(ciRgn, {
                title = "Combat Indicator Settings",
                rows = {
                    {
                        type = "toggle",
                        label = "Class Colored",
                        -- All custom combat icons (Arcade/Dungeoneer/Classic/Cross/Circle/
                        -- Square = combat0..5) are shown as-is, so class coloring doesn't
                        -- apply to them.
                        disabled = function()
                            local st = SValSupported("combatIndicatorStyle", "class")
                            return st:find("^combat%d") and true or false
                        end,
                        disabledTooltip = "Not available for this combat indicator style.",
                        rawTooltip = true,
                        get = function()
                            return SValSupported("combatIndicatorColor", "custom") == "classcolor"
                        end,
                        set = function(v)
                            SSetSupported("combatIndicatorColor", v and "classcolor" or "custom")
                            ReloadAndUpdate()
                            UpdatePreview()
                        end,
                    },
                    {
                        type = "dropdown",
                        label = "Position",
                        values = combatPosValues,
                        order = combatPosOrder,
                        get = function()
                            local place = SValSupported("combatIndicatorPosition", "healthbar")
                            if place == "center" then
                                place = "healthbar"
                            end
                            return combatPosValues[place] and place or "healthbar"
                        end,
                        set = function(v)
                            SSetSupported("combatIndicatorPosition", v)
                            ReloadAndUpdate()
                            UpdatePreview()
                        end,
                    },
                    {
                        type = "slider",
                        label = "Size",
                        min = 8,
                        max = 64,
                        step = 1,
                        get = function()
                            return SValSupported("combatIndicatorSize", 22)
                        end,
                        set = function(v)
                            SSetSupported("combatIndicatorSize", v)
                            ReloadAndUpdate()
                            UpdatePreview()
                        end,
                    },
                    {
                        type = "slider",
                        label = "X Offset",
                        min = -200,
                        max = 200,
                        step = 1,
                        get = function()
                            return SValSupported("combatIndicatorX", 0)
                        end,
                        set = function(v)
                            SSetSupported("combatIndicatorX", v)
                            ReloadAndUpdate()
                            UpdatePreview()
                        end,
                    },
                    {
                        type = "slider",
                        label = "Y Offset",
                        min = -200,
                        max = 200,
                        step = 1,
                        get = function()
                            return SValSupported("combatIndicatorY", 0)
                        end,
                        set = function(v)
                            SSetSupported("combatIndicatorY", v)
                            ReloadAndUpdate()
                            UpdatePreview()
                        end,
                    },
                },
            })

            -- Inline color swatch for custom color. Same order and spacing as
            -- the Heal Absorb Style row above: eye, cog, swatch at -8 gaps,
            -- with the swatch dimmed + click-blocked (never hidden, so the
            -- inline chain keeps its spacing) when the color doesn't apply.
            local combatSwatch = CludesUI.BuildColorSwatch(ciRgn, ciRgn:GetFrameLevel() + 5, function()
                local cc = SGetSupported("combatIndicatorCustomColor")
                cc = cc or { r = 1, g = 1, b = 1 }
                return cc.r, cc.g, cc.b, 1
            end, function(r, g, b)
                UNIT_DB_MAP[optionState.selectedUnit]().combatIndicatorCustomColor = { r = r, g = g, b = b }
                ReloadAndUpdate()
                UpdatePreview()
            end, false, 20)
            combatSwatch:SetPoint("RIGHT", ciRgn._lastInline or ciRgn._control, "LEFT", -8, 0)
            ciRgn._lastInline = combatSwatch
            local combatSwatchBlock = CreateFrame("Frame", nil, combatSwatch)
            combatSwatchBlock:SetAllPoints()
            combatSwatchBlock:SetFrameLevel(combatSwatch:GetFrameLevel() + 10)
            combatSwatchBlock:EnableMouse(true)
            combatSwatchBlock:Hide()
            local function UpdateSwatchVisibility()
                local colorMode = SValSupported("combatIndicatorColor", "custom")
                local style = SValSupported("combatIndicatorStyle", "class")
                -- All custom combat icons (combat0..5) are shown as-is, so the custom-
                -- color swatch doesn't apply to them.
                local isRawIcon = style:find("^combat%d") and true or false
                local usable = colorMode == "custom" and style ~= "none" and not isRawIcon
                combatSwatch:SetAlpha(usable and 1 or 0.3)
                if usable then
                    combatSwatchBlock:Hide()
                else
                    combatSwatchBlock:Show()
                end
            end
            UpdateSwatchVisibility()
            RegisterWidgetRefresh(UpdateSwatchVisibility)
        end
    end -- _showAbsorbsCombat

    -- Preview eye for an indicator row, like the Combat Indicator's: toggles
    -- ns._ufPvEyes[key], which the preview reads. The raid marker picks a
    -- random marker each time it is switched on. (Module-namespace fields,
    -- not locals: this builder is long.)
    mod._ufPvEyes = mod._ufPvEyes or {}
    mod._ufAddPvEye = function(rgn, key, what)
        if CludesUI._prebuilding or not rgn then
            return
        end
        if optionState.selectedUnit ~= "player" and optionState.selectedUnit ~= "target" then
            return
        end
        local eyes = mod._ufPvEyes
        local eyeBtn, eyeTex = CludesUI.NewInlineEye(rgn)
        local function RefreshEye()
            eyeTex:SetTexture(eyes[key] and CludesUI.EYE_INVISIBLE_ICON or CludesUI.EYE_VISIBLE_ICON)
        end
        RefreshEye()
        eyeBtn:SetScript("OnClick", function()
            eyes[key] = not eyes[key]
            if key == "raid" and eyes[key] then
                eyes.raidIndex = math.random(1, 8)
            end
            RefreshEye()
            UpdatePreview()
        end)
        eyeBtn:SetScript("OnEnter", function(self)
            CludesUI.SetGlyphAlpha(self, 0.7)
            CludesUI.ShowWidgetTooltip(self, (eyes[key] and "Hide " or "Show ") .. what .. " preview")
        end)
        eyeBtn:SetScript("OnLeave", function(self)
            CludesUI.SetGlyphAlpha(self, 0.4)
            CludesUI.HideWidgetTooltip()
        end)
    end

    -- Row 4: Raid Marker toggle | Icon Size slider + inline directions cog (X/Y)
    local function raidMarkerOff()
        return SValSupported("raidMarkerEnabled", false) == false
    end
    local sharedAddRow4
    sharedAddRow4, hgt = W:DualRow(hostFrame, posY, {
        type = "toggle",
        text = "Raid Marker",
        getValue = function()
            return SValSupported("raidMarkerEnabled", false)
        end,
        setValue = function(v)
            SSetSupported("raidMarkerEnabled", v)
            CludesUI:RefreshPage()
        end,
    }, {
        type = "slider",
        text = "Marker Size",
        min = 12,
        max = 64,
        step = 1,
        disabled = raidMarkerOff,
        disabledTooltip = "Raid Marker",
        getValue = function()
            return SValSupported("raidMarkerSize", 28)
        end,
        setValue = function(v)
            SSetSupported("raidMarkerSize", v)
        end,
    })
    posY = posY - hgt
    if not CludesUI._prebuilding then
        local rgn = sharedAddRow4._rightRegion
        local rmPosValues = { ["left"] = "Left", ["center"] = "Center", ["right"] = "Right" }
        local rmPosOrder = { "left", "center", "right" }
        CludesUI.BuildInlineCog(rgn, {
            disabled = raidMarkerOff,
            disabledTooltip = "Raid Marker",
            title = "Raid Marker Settings",
            rows = {
                {
                    type = "dropdown",
                    label = "Position",
                    values = rmPosValues,
                    order = rmPosOrder,
                    get = function()
                        return SValSupported("raidMarkerAlign", "right")
                    end,
                    set = function(v)
                        SSetSupported("raidMarkerAlign", v)
                    end,
                },
                {
                    type = "slider",
                    label = "X Offset",
                    min = -200,
                    max = 200,
                    step = 1,
                    get = function()
                        return SValSupported("raidMarkerX", 0)
                    end,
                    set = function(v)
                        SSetSupported("raidMarkerX", v)
                    end,
                },
                {
                    type = "slider",
                    label = "Y Offset",
                    min = -200,
                    max = 200,
                    step = 1,
                    get = function()
                        return SValSupported("raidMarkerY", 0)
                    end,
                    set = function(v)
                        SSetSupported("raidMarkerY", v)
                    end,
                },
            },
        })
    end
    -- Sync icons: Raid Marker (left) and Marker Size (right)
    if not CludesUI._prebuilding then
        mod.UFO_UnitSync(sharedAddRow4._leftRegion, "Raid Marker", {
            key = "raidMarkerEnabled",
            default = false,
            unsetOnly = true,
            self = true,
        })
    end
    if not CludesUI._prebuilding then
        local rgn = sharedAddRow4._rightRegion
        mod.UFO_UnitSync(rgn, "Marker Size", {
            key = "raidMarkerSize",
            default = 28,
            self = true,
        })
    end

    mod._ufAddPvEye(sharedAddRow4._leftRegion, "raid", "raid marker")

    -- Row 5: Leader Indicator toggle | Leader Icon Size slider + inline directions cog (X/Y)
    -- Visible for player and target.
    local sharedAddRow5, BuildLeaderSync
    local function leaderIndOff()
        return SValSupported("leaderIndicatorEnabled", true) == false
    end
    local function leaderIndSupported()
        return optionState.selectedUnit == "player" or optionState.selectedUnit == "target"
    end
    if leaderIndSupported() then
        local leaderSyncUnits = { "player", "target" }
        sharedAddRow5, hgt = W:DualRow(hostFrame, posY, {
            type = "toggle",
            text = "Leader Indicator",
            getValue = function()
                return SValSupported("leaderIndicatorEnabled", true)
            end,
            setValue = function(v)
                SSetSupported("leaderIndicatorEnabled", v)
                CludesUI:RefreshPage()
            end,
        }, {
            type = "slider",
            text = "Leader Icon Size",
            min = 8,
            max = 48,
            step = 1,
            disabled = leaderIndOff,
            disabledTooltip = "Leader Indicator",
            getValue = function()
                return SValSupported("leaderIndicatorSize", 16)
            end,
            setValue = function(v)
                SSetSupported("leaderIndicatorSize", v)
            end,
        })
        posY = posY - hgt
        SApplySupport(sharedAddRow5._leftRegion, "leaderIndicatorEnabled")
        SApplySupport(sharedAddRow5._rightRegion, "leaderIndicatorSize")
        if not CludesUI._prebuilding then
            local rgn = sharedAddRow5._rightRegion
            local leaderPosValues = {
                ["topleft"] = "Top Left",
                ["topright"] = "Top Right",
                ["bottomleft"] = "Bottom Left",
                ["bottomright"] = "Bottom Right",
                ["portrait"] = "Portrait",
            }
            local leaderPosOrder = { "topleft", "topright", "bottomleft", "bottomright", "portrait" }
            CludesUI.BuildInlineCog(rgn, {
                disabled = leaderIndOff,
                disabledTooltip = "Leader Indicator",
                title = "Leader Indicator Settings",
                rows = {
                    {
                        type = "dropdown",
                        label = "Icon Style",
                        tooltip = "Art used for the leader crown and the assistant icon.",
                        values = { blizzard = "Blizzard", pixels = "Pixels" },
                        order = { "blizzard", "pixels" },
                        get = function()
                            return SValSupported("leaderIndicatorStyle", "blizzard")
                        end,
                        set = function(v)
                            SSetSupported("leaderIndicatorStyle", v)
                        end,
                    },
                    {
                        type = "dropdown",
                        label = "Position",
                        values = leaderPosValues,
                        order = leaderPosOrder,
                        get = function()
                            return SValSupported("leaderIndicatorPosition", "topleft")
                        end,
                        set = function(v)
                            SSetSupported("leaderIndicatorPosition", v)
                        end,
                    },
                    {
                        type = "slider",
                        label = "X Offset",
                        min = -200,
                        max = 200,
                        step = 1,
                        get = function()
                            return SValSupported("leaderIndicatorX", 0)
                        end,
                        set = function(v)
                            SSetSupported("leaderIndicatorX", v)
                        end,
                    },
                    {
                        type = "slider",
                        label = "Y Offset",
                        min = -200,
                        max = 200,
                        step = 1,
                        get = function()
                            return SValSupported("leaderIndicatorY", 0)
                        end,
                        set = function(v)
                            SSetSupported("leaderIndicatorY", v)
                        end,
                    },
                },
            })
        end
        -- Player + target sync link; the Faction Indicator row below reuses it.
        BuildLeaderSync = function(rgn, key, default, label)
            mod.UFO_UnitSync(rgn, label, {
                units = leaderSyncUnits,
                key = key,
                default = default,
                unsetOnly = true,
                self = true,
            })
        end
        if not CludesUI._prebuilding then
            BuildLeaderSync(sharedAddRow5._leftRegion, "leaderIndicatorEnabled", true, "Leader Indicator")
            BuildLeaderSync(sharedAddRow5._rightRegion, "leaderIndicatorSize", 16, "Leader Icon Size")
        end
    end

    if sharedAddRow5 then
        mod._ufAddPvEye(sharedAddRow5._leftRegion, "leader", "leader indicator")
    end

    -- Row 5b: Elite/Rare Indicator (+ Show-in-Instances cog) | Icon Size (+ X/Y
    -- cog). Target only (classification is a property of the unit being looked at);
    -- same controls as Leader Indicator above, badge atlases match nameplates.
    if optionState.selectedUnit == "target" then
        -- A table on the "wingless" style belongs to the Portrait Dragon
        -- (ns.UF_DragonLegacy): the indicator reads as off and as Badge, and
        -- every setter pins that view over first.
        local function eliteLegacy()
            return mod.UF_DragonLegacy(SDB())
        end
        local function eliteSet(key, v)
            mod.UF_PinLegacyDragon(SDB())
            SSetSupported(key, v)
        end
        local function eliteIndOff()
            return SValSupported("eliteIndicatorEnabled", false) ~= true or eliteLegacy()
        end
        -- The Pixels Dragon style sits on the portrait: Size, Position and the
        -- X/Y offsets apply to the Badge style only. The stock styles always
        -- draw the Badge.
        local function eliteDragon()
            return not eliteLegacy()
                and SValSupported("eliteIndicatorStyle", "badge") ~= "badge"
                and not CludesUI.BlizzStyle.Get("unitframes")
        end
        local eliteRow
        eliteRow, hgt = W:DualRow(hostFrame, posY, {
            type = "toggle",
            text = "Elite/Rare Indicator",
            tooltip = "Marks elite, rare elite and rare targets; the Pixels Dragon style also marks players.",
            getValue = function()
                return not eliteIndOff()
            end,
            setValue = function(v)
                eliteSet("eliteIndicatorEnabled", v)
                CludesUI:RefreshPage()
            end,
        }, {
            type = "slider",
            text = "Elite Icon Size",
            min = 8,
            max = 48,
            step = 1,
            disabled = function()
                return eliteIndOff() or eliteDragon()
            end,
            disabledTooltip = function()
                if eliteIndOff() then
                    return "Elite/Rare Indicator"
                end
                return "This option only applies to the Badge style."
            end,
            getValue = function()
                return SValSupported("eliteIndicatorSize", 16)
            end,
            setValue = function(v)
                eliteSet("eliteIndicatorSize", v)
            end,
        })
        posY = posY - hgt
        SApplySupport(eliteRow._leftRegion, "eliteIndicatorEnabled")
        SApplySupport(eliteRow._rightRegion, "eliteIndicatorSize")
        if not CludesUI._prebuilding then
            CludesUI.BuildInlineCog(eliteRow._leftRegion, {
                disabled = eliteIndOff,
                disabledTooltip = "Elite/Rare Indicator",
                title = "Elite/Rare Indicator",
                rows = {
                    {
                        type = "toggle",
                        label = "Show in Instances",
                        tooltip = "Also show the badge in dungeons and raids, where most enemies are elite.",
                        get = function()
                            return SValSupported("eliteIndicatorShowInInstances", false) == true
                        end,
                        set = function(v)
                            eliteSet("eliteIndicatorShowInInstances", v)
                        end,
                    },
                },
            })
        end
        if not CludesUI._prebuilding then
            local elitePosValues = {
                ["topleft"] = "Top Left",
                ["topright"] = "Top Right",
                ["bottomleft"] = "Bottom Left",
                ["bottomright"] = "Bottom Right",
                ["portrait"] = "Portrait",
            }
            local elitePosOrder = { "topleft", "topright", "bottomleft", "bottomright", "portrait" }
            local function stockStyle()
                return CludesUI.BlizzStyle.Get("unitframes")
            end
            local function stockStyleTip()
                return CludesUI.BlizzStyle.Label("unitframes")
            end
            local badgeOnly = "This option only applies to the Badge style."
            CludesUI.BuildInlineCog(eliteRow._rightRegion, {
                disabled = eliteIndOff,
                disabledTooltip = "Elite/Rare Indicator",
                title = "Elite/Rare Indicator Settings",
                rows = {
                    {
                        type = "dropdown",
                        label = "Style",
                        tooltip = "Badge shows a small icon; Pixels Dragon wraps the portrait in classification art.",
                        values = { badge = "Badge", pixelsDragon = "Pixels Dragon" },
                        order = { "badge", "pixelsDragon" },
                        disabled = stockStyle,
                        disabledTooltip = stockStyleTip,
                        requireState = "disabled",
                        get = function()
                            if eliteLegacy() then
                                return "badge"
                            end
                            return SValSupported("eliteIndicatorStyle", "badge")
                        end,
                        -- Only dims or lifts the Badge-only controls.
                        set = function(v)
                            eliteSet("eliteIndicatorStyle", v)
                            CludesUI:RefreshPage()
                        end,
                    },
                    {
                        type = "dropdown",
                        label = "Position",
                        values = elitePosValues,
                        order = elitePosOrder,
                        disabled = eliteDragon,
                        disabledTooltip = badgeOnly,
                        rawTooltip = true,
                        get = function()
                            return SValSupported("eliteIndicatorPosition", "topleft")
                        end,
                        set = function(v)
                            eliteSet("eliteIndicatorPosition", v)
                        end,
                    },
                    {
                        type = "slider",
                        label = "X Offset",
                        min = -200,
                        max = 200,
                        step = 1,
                        disabled = eliteDragon,
                        disabledTooltip = badgeOnly,
                        rawTooltip = true,
                        get = function()
                            return SValSupported("eliteIndicatorX", 0)
                        end,
                        set = function(v)
                            eliteSet("eliteIndicatorX", v)
                        end,
                    },
                    {
                        type = "slider",
                        label = "Y Offset",
                        min = -200,
                        max = 200,
                        step = 1,
                        disabled = eliteDragon,
                        disabledTooltip = badgeOnly,
                        rawTooltip = true,
                        get = function()
                            return SValSupported("eliteIndicatorY", 0)
                        end,
                        set = function(v)
                            eliteSet("eliteIndicatorY", v)
                        end,
                    },
                },
            })
        end
        mod._ufAddPvEye(eliteRow._leftRegion, "elite", "elite/rare indicator")
        hostFrame._ufEliteRow = eliteRow
    end

    -- Row 5c: Faction Indicator (mode + filters cog) | Icon Size (+ position cog).
    -- Player and target. On the player frame it is a PvP-flagged indicator
    -- (PvP Flag defaults to Flagged Only there); Opposite Faction and Players
    -- Only are target-only.
    if optionState.selectedUnit == "player" or optionState.selectedUnit == "target" then
        local isTarget = optionState.selectedUnit == "target"
        local function factionIndOff()
            return SValSupported("factionIndicatorMode", "off") == "off"
        end
        local modeValues, modeOrder
        if isTarget then
            modeValues = { off = "Off", always = "Always", opposite = "Opposite Faction" }
            modeOrder = { "off", "always", "opposite" }
        else
            modeValues = { off = "Off", always = "On" }
            modeOrder = { "off", "always" }
        end
        local factionRow
        factionRow, hgt = W:DualRow(hostFrame, posY, {
            type = "dropdown",
            text = "Faction Indicator",
            values = modeValues,
            order = modeOrder,
            getValue = function()
                local v = SValSupported("factionIndicatorMode", "off")
                if not isTarget and v == "opposite" then
                    v = "always"
                end
                return v
            end,
            setValue = function(v)
                SSetSupported("factionIndicatorMode", v)
                CludesUI:RefreshPage()
            end,
        }, {
            type = "slider",
            text = "Faction Icon Size",
            min = 8,
            max = 48,
            step = 1,
            disabled = factionIndOff,
            disabledTooltip = "Faction Indicator",
            getValue = function()
                return SValSupported("factionIndicatorSize", 18)
            end,
            setValue = function(v)
                SSetSupported("factionIndicatorSize", v)
            end,
        })
        posY = posY - hgt
        SApplySupport(factionRow._leftRegion, "factionIndicatorMode")
        SApplySupport(factionRow._rightRegion, "factionIndicatorSize")
        if not CludesUI._prebuilding then
            local pvpValues = { dim = "Dim Unflagged", only = "Flagged Only", ignore = "Ignore" }
            local pvpOrder = { "dim", "only", "ignore" }
            local pvpDefault = isTarget and "dim" or "only"
            local rowList = {
                {
                    type = "dropdown",
                    label = "PvP Flag",
                    values = pvpValues,
                    order = pvpOrder,
                    get = function()
                        return SValSupported("factionIndicatorPvP", pvpDefault)
                    end,
                    set = function(v)
                        SSetSupported("factionIndicatorPvP", v)
                    end,
                },
            }
            if isTarget then
                rowList[#rowList + 1] = {
                    type = "toggle",
                    label = "Players Only",
                    tooltip = "Hide the faction badge on faction NPCs such as guards.",
                    get = function()
                        return SValSupported("factionIndicatorPlayersOnly", false) == true
                    end,
                    set = function(v)
                        SSetSupported("factionIndicatorPlayersOnly", v)
                    end,
                }
            end
            CludesUI.BuildInlineCog(factionRow._leftRegion, {
                disabled = factionIndOff,
                disabledTooltip = "Faction Indicator",
                title = "Faction Indicator",
                rows = rowList,
            })
        end
        if not CludesUI._prebuilding then
            local factionPosValues = {
                ["topleft"] = "Top Left",
                ["topright"] = "Top Right",
                ["bottomleft"] = "Bottom Left",
                ["bottomright"] = "Bottom Right",
                ["portrait"] = "Portrait",
            }
            local factionPosOrder = { "topleft", "topright", "bottomleft", "bottomright", "portrait" }
            CludesUI.BuildInlineCog(factionRow._rightRegion, {
                disabled = factionIndOff,
                disabledTooltip = "Faction Indicator",
                title = "Faction Indicator Settings",
                rows = {
                    {
                        type = "dropdown",
                        label = "Icon Style",
                        values = CludesUI.FACTION_ART_LABELS,
                        order = CludesUI.FACTION_ART_ORDER,
                        get = function()
                            return SValSupported("factionIndicatorStyle", "pvp")
                        end,
                        set = function(v)
                            SSetSupported("factionIndicatorStyle", v)
                        end,
                    },
                    {
                        type = "dropdown",
                        label = "Position",
                        values = factionPosValues,
                        order = factionPosOrder,
                        get = function()
                            return SValSupported("factionIndicatorPosition", "topright")
                        end,
                        set = function(v)
                            SSetSupported("factionIndicatorPosition", v)
                        end,
                    },
                    {
                        type = "slider",
                        label = "X Offset",
                        min = -200,
                        max = 200,
                        step = 1,
                        get = function()
                            return SValSupported("factionIndicatorX", 0)
                        end,
                        set = function(v)
                            SSetSupported("factionIndicatorX", v)
                        end,
                    },
                    {
                        type = "slider",
                        label = "Y Offset",
                        min = -200,
                        max = 200,
                        step = 1,
                        get = function()
                            return SValSupported("factionIndicatorY", 0)
                        end,
                        set = function(v)
                            SSetSupported("factionIndicatorY", v)
                        end,
                    },
                },
            })
        end
        -- Size only: the player's mode list (Off/On) differs from the target's
        -- (with Opposite Faction), so the mode has no clean cross-frame copy.
        if not CludesUI._prebuilding then
            BuildLeaderSync(factionRow._rightRegion, "factionIndicatorSize", 18, "Faction Icon Size")
        end
        mod._ufAddPvEye(factionRow._leftRegion, "faction", "faction indicator")
        hostFrame._ufFactionRow = factionRow
    end

    -- Row 6: Rested Indicator | blank (player only): Quality of Life's EXTRAS
    -- row mirrored, the same account-wide settings (CludesUI.RestedIndicatorCfg).
    if optionState.selectedUnit == "player" then
        local restRow
        restRow, hgt = W:DualRow(hostFrame, posY, CludesUI.RestedIndicatorCfg(), CludesUI.BlankRowCfg())
        posY = posY - hgt
        CludesUI.BuildRestedIndicatorCog(restRow._leftRegion)
    end

    -- Row 6: Targeting Sound Effects | blank (target only; one setting for the
    -- profile). Blizzard's own target frame plays them itself, so the row greys
    -- out while the Target frame is on Blizzard Default.
    if optionState.selectedUnit == "target" then
        local soundRow
        soundRow, hgt = W:DualRow(hostFrame, posY, {
            type = "toggle",
            text = "Targeting Sound Effects",
            tooltip = "Plays the game's sounds when you select or lose a target.",
            disabled = function()
                return mod.GetUnitFrameSource("target") == "blizzard"
            end,
            disabledTooltip = "Blizzard's target frame plays these sounds itself.",
            rawTooltip = true,
            getValue = function()
                return saved.profile.targetSounds == true
            end,
            setValue = function(v)
                saved.profile.targetSounds = v
                mod.UF_SyncTargetSounds()
            end,
        }, CludesUI.BlankRowCfg())
        posY = posY - hgt
    end

    return posY, sharedAddHeader, sharedAddRow1, sharedAddRow4, sharedAddRow5
end
