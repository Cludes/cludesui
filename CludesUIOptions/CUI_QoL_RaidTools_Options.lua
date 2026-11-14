if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_QoL_RaidTools_Options.lua -- Raid Tools page of the QoL module
--
--  Not its own module: the page is registered by CUI_QoL_Options.lua, which
--  dispatches to the builder this file publishes as _G._CUI_BuildRaidToolsPage.
--  Same arrangement as the Cursor and Upgrade Calculator pages.
-------------------------------------------------------------------------------
local mod = CludesUI._ModuleNS["CludesUIQoL"] -- module namespace (published by the module at its load)
if not mod then
    return
end -- module disabled: no options page

-- Page reuse: frames this file builds go through the options frame pool
-- (CludesUI_FramePool.lua), which hands a kept page its previous build's
-- frames back reset to new; on any other parent it is the plain CreateFrame.
local CreateFrame = CludesUI._Pool.CreateFrame

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    -- NOT gated on CludesUI.Widgets: on this LoadOnDemand addon the
    -- IsLoggedIn() re-fire below runs this handler at FILE SCOPE, before
    -- EnsureLoaded drains _deferredInits -- and the whole Widgets factory
    -- lives in a deferred body, so Widgets is always nil here. BuildPage
    -- reads it at panel-open time, after the drain, which is the only
    -- moment it is needed.
    if not CludesUI then
        return
    end

    -- Settings live in one slice of the shared QoL profile, so every read here
    -- goes through the same handle the runtime publishes.
    --
    -- A PURE READ, with no `or {}` seeding: every getter on this page runs
    -- through it during a Spec Overrides capture, which swaps the profile for
    -- a read-tracking proxy. Writing back what was just read stores a proxy in
    -- the real table and each later call wraps it again, until reading a leaf
    -- overflows the C stack. DB_DEFAULTS guarantees the slice exists.
    local function SavedDB()
        local get = _G._CUI_RaidTools_DB
        local root = get and get()
        return root and root.profile and root.profile.raidTools
    end

    local function Cfg(key)
        local p = SavedDB()
        return p and p[key]
    end

    local function Set(key, val)
        local p = SavedDB()
        if p then
            p[key] = val
        end
    end

    local function Refresh()
        if _G._CUI_RaidTools_Apply then
            _G._CUI_RaidTools_Apply()
        end
    end

    local function Disabled()
        return (Cfg("mode") or "never") == "never"
    end

    local function QuickFireDisabled()
        return Disabled() or Cfg("quickFire") ~= true
    end

    -- The runtime owns the normalize (unknown values retain One Window).
    local function ShowAsVal()
        if mod.ShowAs then
            return mod.ShowAs()
        end
        return Cfg("showAs") or "one"
    end

    local function LegacyDisabled()
        return Disabled() or ShowAsVal() == "compact"
    end
    local function RoleCheckDisabled()
        return Disabled() or ShowAsVal() == "markers"
    end
    local function FullPanelButtonDisabled()
        local modeName = ShowAsVal()
        return Disabled() or modeName == "compact" or modeName == "markers"
    end
    -- Raid Buff Check is retail only: its rows are not built on WoW Forever.
    local function BuffCheckOff()
        return Cfg("buffCheck") ~= true
    end
    local function PullDisabled()
        return Disabled() or ShowAsVal() == "markers"
    end

    -- Pull durations live in a fixed 3-slot array; each slider owns one slot.
    local function PullGet(idx)
        local t = Cfg("pullTimes")
        return (t and t[idx]) or mod.PULL_DEFAULTS[idx]
    end

    local function PullSet(idx, v)
        local t = Cfg("pullTimes")
        if not t then
            return
        end
        t[idx] = v
        Refresh()
    end

    local function BuildPage(page, hostFrame, yOffset)
        local W = CludesUI.Widgets
        local posY = yOffset
        local _, hgt, heading

        CludesUI:ClearContentHeader()

        -- Settings preview: with this page in front the windows force shown and fully
        -- expanded, so every change lands visibly instead of the collapse/visibility
        -- rules eating it (the TBB placeholder-mode arrangement). NEVER during Global
        -- Search's hidden pre-build, which builds every page once at startup.
        if not CludesUI._prebuilding and _G._CUI_RaidTools_Preview then
            _G._CUI_RaidTools_Preview(true)
        end

        -- GENERAL
        heading, hgt = W:SectionHeader(hostFrame, "GENERAL", posY)
        posY = posY - hgt
        -- The Show as choice decides which shell has a mover: the Compact
        -- Band, the Markers window alone, or the Group & Pull window (which
        -- is also the One Window shell and the first of Two Windows).
        CludesUI.BuildSectionUnlockJump(heading, {
            key = function()
                local showAs = ShowAsVal()
                if showAs == "compact" then
                    return "CUI_RaidTools_Compact"
                end
                if showAs == "markers" then
                    return "CUI_RaidTools_Markers"
                end
                return "CUI_RaidTools_Group"
            end,
            disabled = Disabled,
            disabledTooltip = "Show Raid Tools",
        })

        -- Row 1: Show Raid Tools mode | Toggle Raid Tools keybind.
        -- The mode dropdown IS the on/off switch: Never means nothing is
        -- built at all (no frames, events, bindings or unlock rows), which is
        -- why there is no separate Enable toggle.
        local kbRow
        kbRow, hgt = W:DualRow(hostFrame, posY, {
            type = "dropdown",
            text = "Show Raid Tools",
            tooltip = "A raid control panel with ready check, pull timer and raid markers. In a raid it only shows while you are the leader or an assistant, since none of its buttons work without that; in a party it always shows.",
            values = {
                never = "Never",
                raid = "In Raid Group",
                group = "In Any Group",
                always = "Always",
            },
            order = { "never", "raid", "group", "always" },
            getValue = function()
                return Cfg("mode") or "never"
            end,
            setValue = function(v)
                Set("mode", v)
                Refresh()
                CludesUI:RefreshPage()
            end,
        }, { type = "label", text = "Toggle Raid Tools" })
        posY = posY - hgt

        -- Keybind button in the label's slot -- the exact Toggle Action Bar
        -- Visibility arrangement from Action Bars: profile-stored key, click
        -- to capture, right-click to unbind, Escape cancels. The bound key is
        -- an override binding on the secure toggle button, so pressing it
        -- works in combat; only the (re)binding itself waits for combat end.
        if not CludesUI._prebuilding then
            local rgn = kbRow._rightRegion
            local kbBtn, refresh = CludesUI.BuildKeybindButton(rgn, {
                w = 126,
                h = 29,
                level = 4,
                get = function()
                    return Cfg("toggleKey")
                end,
                -- Spec Overrides: the slot is read before the write (a write
                -- that rebuilds the page dresses this region again).
                set = function(v)
                    local snap = CludesUI._SOAttribution(rgn)
                    Set("toggleKey", v or false)
                    Refresh()
                    CludesUI._NotifySettingWrite(rgn, snap)
                end,
                disabled = Disabled,
                disabledTip = "Show Raid Tools",
                tooltip = "Toggles the Raid Tools panels, in or out of combat.\n\nLeft-click to set a keybind.\nRight-click to unbind.",
            })
            CludesUI.PanelPP.Point(kbBtn, "RIGHT", rgn, "RIGHT", -20, 0)
            CludesUI.RegisterWidgetRefresh(refresh)

            -- Spec Overrides capture: bespoke widget, so its SLOT opts in with a
            -- synthetic accessor (the label cfg carries no get/set of its own).
            CludesUI.AddCaptureAccessor(rgn, {
                type = "keybind",
                text = "Toggle Raid Tools",
                getValue = function()
                    return Cfg("toggleKey")
                end,
                setValue = function(v)
                    Set("toggleKey", v)
                    Refresh()
                    refresh()
                end,
            })
        end

        -- Row 2: collapsed-when-shown default | window composition.
        _, hgt = W:DualRow(hostFrame, posY, {
            type = "toggle",
            text = "Default to Collapsed When Shown",
            tooltip = "Full-window modes only. Shows start as a small icon, and the keybind switches between the icon and the full windows.",
            disabled = LegacyDisabled,
            getValue = function()
                return Cfg("collapsedIcon") ~= false
            end,
            setValue = function(v)
                Set("collapsedIcon", v)
                Refresh()
            end,
        }, {
            type = "dropdown",
            text = "Show as",
            tooltip = "Compact Band puts markers, ready check and pull timer in one resizable row. The other choices keep the original window layouts.",
            disabled = Disabled,
            values = {
                compact = "Compact Band",
                one = "One Window",
                two = "Two Windows",
                group = "Only Group & Pull",
                markers = "Only Markers",
            },
            order = { "compact", "one", "two", "group", "markers" },
            getValue = function()
                return ShowAsVal()
            end,
            setValue = function(v)
                Set("showAs", v)
                Refresh()
                CludesUI:RefreshPage()
            end,
        })
        posY = posY - hgt

        -- Row 3: one scale for every layout | legacy menu grow direction.
        _, hgt = W:DualRow(hostFrame, posY, {
            type = "slider",
            text = "Window Scale",
            min = 0.5,
            max = 2.0,
            step = 0.05,
            disabled = Disabled,
            getValue = function()
                return Cfg("scale") or 1
            end,
            setValue = function(v)
                Set("scale", v)
                Refresh()
            end,
        }, {
            type = "dropdown",
            text = "Menu Grow Direction",
            tooltip = "Full-window modes only. Which way the windows extend from the collapsed icon when they open.",
            disabled = LegacyDisabled,
            values = {
                downright = "Down Right",
                upright = "Up Right",
                downleft = "Down Left",
                upleft = "Up Left",
            },
            order = { "downright", "upright", "downleft", "upleft" },
            getValue = function()
                return Cfg("growDir") or "downright"
            end,
            setValue = function(v)
                Set("growDir", v)
                Refresh()
            end,
        })
        posY = posY - hgt

        -- QUICK FIRE
        -- An explicitly enabled, empty-by-default set of world-marker binds.
        _, hgt = W:SectionHeader(hostFrame, "QUICK FIRE", posY)
        posY = posY - hgt

        local qfEnableRow
        qfEnableRow, hgt = W:DualRow(hostFrame, posY, {
            type = "toggle",
            text = "Enable Quick Fire",
            tooltip = "Adds three optional world-marker keybinds that remain usable in combat. Place drops the first free marker at the cursor in Star to Skull order; Undo removes the last marker placed through Quick Fire; Clear removes all world markers. Every binding starts empty. Marker changes made elsewhere during combat are picked up afterward.",
            disabled = Disabled,
            getValue = function()
                return Cfg("quickFire") == true
            end,
            setValue = function(v)
                Set("quickFire", v)
                Refresh()
                CludesUI:RefreshPage()
            end,
        }, { type = "label", text = "Place World Marker" })
        posY = posY - hgt

        local qfKeysRow
        qfKeysRow, hgt = W:DualRow(
            hostFrame,
            posY,
            { type = "label", text = "Undo Last Marker" },
            { type = "label", text = "Clear All Markers" }
        )
        posY = posY - hgt

        if not CludesUI._prebuilding then
            local Pix = CludesUI.PanelPP

            local function AddQuickFireKeybind(regionFrame, key)
                local btnFrame, refresh = CludesUI.BuildKeybindButton(regionFrame, {
                    w = 126,
                    h = 29,
                    level = 4,
                    mouse = true,
                    get = function()
                        return Cfg(key)
                    end,
                    set = function(v)
                        local snap = CludesUI._SOAttribution(regionFrame)
                        Set(key, v or false)
                        Refresh()
                        CludesUI._NotifySettingWrite(regionFrame, snap)
                    end,
                    disabled = QuickFireDisabled,
                    disabledTip = function()
                        return Disabled() and "Show Raid Tools" or "Enable Quick Fire"
                    end,
                })
                Pix.Point(btnFrame, "RIGHT", regionFrame, "RIGHT", -20, 0)
                CludesUI.RegisterWidgetRefresh(refresh)
                CludesUI.AddCaptureAccessor(regionFrame, {
                    type = "keybind",
                    text = regionFrame._label and regionFrame._label:GetText() or key,
                    getValue = function()
                        return Cfg(key)
                    end,
                    setValue = function(v)
                        Set(key, v)
                        Refresh()
                        refresh()
                    end,
                })
            end

            AddQuickFireKeybind(qfEnableRow._rightRegion, "quickFirePlaceKey")
            AddQuickFireKeybind(qfKeysRow._leftRegion, "quickFireUndoKey")
            AddQuickFireKeybind(qfKeysRow._rightRegion, "quickFireClearKey")
        end

        -- GROUP BUTTONS
        --
        -- One switch per optional action. Ready Check has none: it is the
        -- reason the panel exists. Turning a button off closes the gap it
        -- leaves -- the survivors re-flow across the rows.
        _, hgt = W:SectionHeader(hostFrame, "GROUP BUTTONS", posY)
        posY = posY - hgt

        local function ButtonToggle(key, textValue, tooltip, disabled)
            return {
                type = "toggle",
                text = textValue,
                tooltip = tooltip,
                disabled = disabled or Disabled,
                getValue = function()
                    return Cfg(key) ~= false
                end,
                setValue = function(v)
                    Set(key, v)
                    Refresh()
                end,
            }
        end

        _, hgt = W:DualRow(
            hostFrame,
            posY,
            ButtonToggle(
                "showRoleCheck",
                "Show Role Check",
                "Shows the Role Check button in window layouts and enables Right Click: Role Check on Compact Band.",
                RoleCheckDisabled
            ),
            ButtonToggle(
                "showConvert",
                "Show Convert to Raid",
                "Shows the Convert to Raid button, which reads Convert to Party while you are in a raid.",
                FullPanelButtonDisabled
            )
        )
        posY = posY - hgt
        _, hgt = W:DualRow(
            hostFrame,
            posY,
            ButtonToggle(
                "showDisband",
                "Show Disband",
                "Shows the Disband button. It always asks before disbanding, but hiding it puts it out of misclick range for good.",
                FullPanelButtonDisabled
            ),
            CludesUI.IS_FOREVER and { type = "spacer" }
                or {
                    type = "toggle",
                    text = "Show Buff Check",
                    tooltip = "Shows the Buff Check button. On Compact Band it is Shift + Left Click on the ready check button.",
                    disabled = function()
                        return RoleCheckDisabled() or BuffCheckOff()
                    end,
                    disabledTooltip = function()
                        if BuffCheckOff() then
                            return "Raid Buff Check"
                        end
                        if Disabled() then
                            return "Show Raid Tools"
                        end
                        return "This option requires a Show as layout with the group buttons."
                    end,
                    getValue = function()
                        return Cfg("showBuffCheck") == true
                    end,
                    setValue = function(v)
                        Set("showBuffCheck", v)
                        Refresh()
                    end,
                }
        )
        posY = posY - hgt

        -- RAID BUFF CHECK (retail only)
        if not CludesUI.IS_FOREVER then
            _, hgt = W:SectionHeader(hostFrame, "RAID BUFF CHECK", posY)
            posY = posY - hgt

            _, hgt = W:DualRow(hostFrame, posY, {
                type = "toggle",
                text = "Raid Buff Check",
                tooltip = "A window of each group member's flask, food, augment and vantus runes and missing raid buffs.",
                getValue = function()
                    return Cfg("buffCheck") == true
                end,
                setValue = function(v)
                    Set("buffCheck", v)
                    Refresh()
                    CludesUI:RefreshPage()
                end,
            }, {
                type = "toggle",
                text = "Open on Ready Check",
                tooltip = "Opens the window on ready checks while you lead the group or assist.",
                disabled = BuffCheckOff,
                disabledTooltip = "Raid Buff Check",
                getValue = function()
                    return Cfg("buffCheckOnReady") ~= false
                end,
                setValue = function(v)
                    Set("buffCheckOnReady", v)
                    Refresh()
                end,
            })
            posY = posY - hgt
        end -- not IS_FOREVER

        -- PULL TIMER
        _, hgt = W:SectionHeader(hostFrame, "PULL TIMER", posY)
        posY = posY - hgt

        local PULL_LABELS = { "First Timer", "Second Timer", "Third Timer" }
        local PULL_TIP =
            "Countdown length in seconds. Compact Band uses First with Ctrl + Left Click, Second with Shift + Left Click, Third with Left Click, and Right Click stops the timer. Set a timer to 0 to disable that shortcut."
        local function PullSlider(idx)
            return {
                type = "slider",
                text = PULL_LABELS[idx],
                min = 0,
                max = 60,
                step = 1,
                tooltip = PULL_TIP,
                disabled = PullDisabled,
                getValue = function()
                    return PullGet(idx)
                end,
                setValue = function(v)
                    PullSet(idx, v)
                end,
            }
        end

        _, hgt = W:DualRow(hostFrame, posY, PullSlider(1), PullSlider(2))
        posY = posY - hgt
        _, hgt = W:DualRow(hostFrame, posY, PullSlider(3), { type = "spacer" })
        posY = posY - hgt

        return math.abs(posY)
    end

    _G._CUI_BuildRaidToolsPage = BuildPage

    -- Preview exits that the page dispatcher cannot see: the options window
    -- closing, and a switch to another MODULE (switching pages inside QoL is
    -- handled by the dispatcher in CUI_QoL_Options.lua). Both are idempotent
    -- no-ops when the preview is already off.
    local function StopPreview()
        if _G._CUI_RaidTools_Preview then
            _G._CUI_RaidTools_Preview(false)
        end
    end
    CludesUI:RegisterOnHide(StopPreview)
    -- REOPENING the window fires neither buildPage nor onPageCacheRestore --
    -- it just Shows with the previous layout intact -- so the show-side
    -- callback re-enters the preview when our page is still the one in front.
    -- The page string must match PAGE_RAIDTOOLS in CUI_QoL_Options.lua.
    CludesUI:RegisterOnShow(function()
        if
            CludesUI:GetActiveModule() == "CludesUIQoL"
            and CludesUI:GetActivePage() == "Raid Tools"
            and _G._CUI_RaidTools_Preview
        then
            _G._CUI_RaidTools_Preview(true)
        end
    end)
    if CludesUI.SelectModule then
        hooksecurefunc(CludesUI, "SelectModule", function(_, folderName)
            if folderName ~= "CludesUIQoL" then
                StopPreview()
            end
        end)
    end
end)
-- LoadOnDemand: this addon loads after PLAYER_LOGIN, so the event above will never fire; run the init now.
if IsLoggedIn() then
    initFrame:GetScript("OnEvent")(initFrame)
end
