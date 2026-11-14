if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_QoL_AutoLogging_Options.lua
--  Options page for the Auto Combat Logging feature.
-------------------------------------------------------------------------------

-- Must match TRIGGER_DEFAULTS in the runtime.
if not CludesUI._ModuleNS["CludesUIQoL"] then
    return
end -- module disabled: no options page

local TRIGGER_DEFAULTS = {
    logMythic = true,
    logHeroic = true,
    logNormal = true,
    logLFR = true,
    log5pp = true,
    logArena = true,
    logScenario = false,
    logRBG = false,
    logBlitz = false,
    delaystop = true,
}

local TRIGGER_ITEMS = {
    { key = "logMythic", label = "Mythic Raid" },
    { key = "logHeroic", label = "Heroic Raid" },
    { key = "logNormal", label = "Normal Raid" },
    { key = "logLFR", label = "LFR" },
    { key = "log5pp", label = "Mythic+ Dungeons" },
    { key = "logArena", label = "Arena" },
    { key = "logScenario", label = "Scenarios" },
    { key = "logRBG", label = "Rated Battlegrounds" },
    { key = "logBlitz", label = "Battleground Blitz" },
}
-- WoW Forever: every raid instance logs on the Raids trigger (the Normal Raid
-- key and its default) and every dungeon on the Dungeons trigger (a key only
-- that client offers, off until the player turns it on). The retail
-- difficulty, Mythic+, arena, scenario and rated battleground rows have
-- nothing to match there.
if CludesUI.IS_FOREVER then
    TRIGGER_ITEMS = {
        { key = "logNormal", label = "Raids" },
        { key = "logDungeon", label = "Dungeons" },
    }
end

local function Cfg()
    if not CludesUIDB then
        return {}
    end
    CludesUIDB.autoLogging = CludesUIDB.autoLogging or {}
    return CludesUIDB.autoLogging
end

local function Recheck()
    if _G._CUI_AutoLogging_Check then
        _G._CUI_AutoLogging_Check()
    end
end

local function KeysCfg()
    if not CludesUIDB then
        return {}
    end
    CludesUIDB.keystonePopup = CludesUIDB.keystonePopup or {}
    return CludesUIDB.keystonePopup
end

local function TeleCfg()
    if not CludesUIDB then
        return {}
    end
    CludesUIDB.teleportPrompt = CludesUIDB.teleportPrompt or {}
    return CludesUIDB.teleportPrompt
end

-- Read-only: the /way table appears on the first write, so viewing the page
-- saves nothing.
local NO_WAY_CFG = {}
local function WayCfg()
    return CludesUIDB and CludesUIDB.waypointCmd or NO_WAY_CFG
end

local function SetWay(key, value)
    if not CludesUIDB then
        return
    end
    CludesUIDB.waypointCmd = CludesUIDB.waypointCmd or {}
    CludesUIDB.waypointCmd[key] = value
end

-- Built as the tail of the Quality of Life page (chained from BuildQoLPage),
-- not as its own tab. Lays out from yOffset and returns the height used,
-- like every other section builder.
local function BuildAutoLoggingPage(page, hostFrame, yOffset)
    local W = CludesUI.Widgets
    local Pix = CludesUI.PanelPP
    local posY = yOffset
    local _, hgt

    hostFrame._showRowDivider = true

    ---------------------------------------------------------------------------
    --  KEYSTONE CHECK POPUP (no keystones on WoW Forever: the section and the
    --  /keys file behind it do not exist there)
    ---------------------------------------------------------------------------
    if not CludesUI.IS_FOREVER then
        _, hgt = W:SectionHeader(hostFrame, "KEYSTONE CHECK POPUP", posY)
        posY = posY - hgt

        _, hgt = W:DualRow(hostFrame, posY, {
            type = "toggle",
            text = "Enable /keys Popup (or /ckeys)",
            tooltip = "Shows a popup with party and guild keystones when typing /keys.",
            -- DependentSetValue: the Window Scale row below is hidden while the
            -- popup is off; the flip forces the full rebuild.
            setValue = CludesUI.DependentSetValue(function()
                return KeysCfg().enabled ~= false
            end, function(val)
                KeysCfg().enabled = val
                CludesUI:RefreshPage()
                CludesUI:ShowConfirmPopup({
                    title = "Reload Required",
                    message = "Changing the /keys popup requires a reload to update slash command registration.",
                    confirmText = "Reload",
                    cancelText = "Later",
                    reload = true,
                })
            end),
            getValue = function()
                return KeysCfg().enabled ~= false
            end,
        }, {
            type = "slider",
            text = "Text Size",
            min = 8,
            max = 16,
            step = 1,
            disabled = function()
                return KeysCfg().enabled == false
            end,
            disabledTooltip = "/keys Popup",
            tooltip = "Font size for keystone entries in the popup (does not affect the header).",
            getValue = function()
                return KeysCfg().textSize or 11
            end,
            setValue = function(val)
                KeysCfg().textSize = val
                if _G._CUI_RefreshKeystonePopup then
                    _G._CUI_RefreshKeystonePopup()
                end
            end,
        })
        posY = posY - hgt

        -- Window Scale row: HIDDEN entirely while the /keys popup is off.
        if KeysCfg().enabled ~= false then
            _, hgt = W:DualRow(hostFrame, posY, {
                type = "slider",
                text = "Window Scale",
                min = 50,
                max = 150,
                step = 5,
                tooltip = "Scale of the /keys popup window.",
                getValue = function()
                    return math.floor((KeysCfg().scale or 1.05) * 100 + 0.5)
                end,
                setValue = function(val)
                    KeysCfg().scale = val / 100
                    local dialog = _G.CUIKeysPopup
                    if dialog then
                        dialog:SetScale(val / 100)
                    end
                end,
            }, { type = "label", text = "" })
            posY = posY - hgt
        end -- close /keys popup hidden-while-disabled gate

        _, hgt = W:Spacer(hostFrame, posY, 20)
        posY = posY - hgt
    end -- not IS_FOREVER

    ---------------------------------------------------------------------------
    --  LFG REMINDER (no dungeon teleports on WoW Forever: the section and the
    --  reminder runtime behind it do not exist there)
    ---------------------------------------------------------------------------
    if not CludesUI.IS_FOREVER then
        _, hgt = W:SectionHeader(hostFrame, "LFG REMINDER", posY)
        posY = posY - hgt

        _, hgt = W:DualRow(hostFrame, posY, {
            type = "toggle",
            text = "Enable LFG Reminder",
            tooltip = "When you join a Group Finder group for a dungeon that has a teleport, shows a small movable popup with the dungeon name and a one-click teleport button. It hides when you enter the dungeon, leave the group, or enter combat.",
            getValue = function()
                return TeleCfg().enabled ~= false
            end,
            -- DependentSetValue: the Show 'Disable Feature' Text row below is
            -- hidden while the reminder is off; the flip forces the rebuild.
            setValue = CludesUI.DependentSetValue(function()
                return TeleCfg().enabled ~= false
            end, function(val)
                TeleCfg().enabled = val
                CludesUI:RefreshPage()
                -- Applies live in both directions: enable builds the popup and
                -- registers events, disable hides and unregisters.
                if _G._CUI_ApplyTeleportPrompt then
                    _G._CUI_ApplyTeleportPrompt()
                end
            end),
        }, {
            type = "slider",
            text = "Window Scale",
            min = 50,
            max = 150,
            step = 5,
            disabled = function()
                return TeleCfg().enabled == false
            end,
            disabledTooltip = "LFG Reminder",
            tooltip = "Scale of the LFG Reminder popup window.",
            getValue = function()
                return math.floor((TeleCfg().scale or 1.05) * 100 + 0.5)
            end,
            setValue = function(val)
                TeleCfg().scale = val / 100
                if _G._CUI_RefreshTeleportPrompt then
                    _G._CUI_RefreshTeleportPrompt()
                end
            end,
        })
        posY = posY - hgt

        -- Show 'Disable Feature' Text row: HIDDEN while the reminder is off.
        if TeleCfg().enabled ~= false then
            _, hgt = W:DualRow(hostFrame, posY, {
                type = "toggle",
                text = "Show 'Disable Feature' Text",
                tooltip = "Shows the 'Disable Feature' text below the teleport button. When off, the text is hidden and the window is 20px shorter.",
                getValue = function()
                    return TeleCfg().showDisable ~= false
                end,
                setValue = function(val)
                    TeleCfg().showDisable = val
                    if _G._CUI_RefreshTeleportPrompt then
                        _G._CUI_RefreshTeleportPrompt()
                    end
                end,
            }, { type = "label", text = "" })
            posY = posY - hgt
        end -- close LFG Reminder hidden-while-disabled gate

        _, hgt = W:Spacer(hostFrame, posY, 20)
        posY = posY - hgt
    end -- not IS_FOREVER

    ---------------------------------------------------------------------------
    --  WAYPOINT COMMAND (/way, runtime in CludesUIQoL_Waypoint.lua)
    ---------------------------------------------------------------------------
    _, hgt = W:SectionHeader(hostFrame, "WAYPOINT COMMAND", posY)
    posY = posY - hgt

    local wayRow
    wayRow, hgt = W:DualRow(hostFrame, posY, {
        type = "toggle",
        text = "Enable /way Command",
        tooltip = "Adds /way, which prints a map pin link.",
        -- Off by default.
        getValue = function()
            return WayCfg().enabled == true
        end,
        setValue = function(val)
            SetWay("enabled", val or nil)
            CludesUI:RefreshPage()
            CludesUI:ShowConfirmPopup({
                title = "Reload Required",
                message = "Changing the /way command requires a reload to update slash command registration.",
                confirmText = "Reload",
                cancelText = "Later",
                reload = true,
            })
        end,
    }, CludesUI.BlankRowCfg())
    posY = posY - hgt

    -- The arrival message for hand-placed pins (off by default). The runtime
    -- reads it live and listens for arrivals only while it or a /way list
    -- needs them, so a change re-syncs that listener.
    CludesUI.BuildInlineCog(wayRow._leftRegion, {
        title = "/way Command",
        disabled = function()
            return WayCfg().enabled ~= true
        end,
        disabledTooltip = "Enable /way Command",
        rows = {
            {
                type = "toggle",
                label = "Hand-Placed Pin Arrival",
                tooltip = "Also announces arrival at pins you place.",
                get = function()
                    return WayCfg().manualArrival == true
                end,
                set = function(val)
                    SetWay("manualArrival", val or nil)
                    local sync = CludesUI._ModuleNS["CludesUIQoL"].WaypointArrivalSync
                    if sync then
                        sync()
                    end
                end,
            },
        },
    })

    _, hgt = W:Spacer(hostFrame, posY, 20)
    posY = posY - hgt

    ---------------------------------------------------------------------------
    --  AUTO COMBAT LOGGING
    ---------------------------------------------------------------------------
    _, hgt = W:SectionHeader(hostFrame, "AUTO COMBAT LOGGING", posY)
    posY = posY - hgt

    local trigRow, trigH = W:DualRow(hostFrame, posY, {
        type = "toggle",
        text = "Enable Auto Logging",
        tooltip = "Automatically starts and stops combat logging when entering or leaving a loggable instance.",
        getValue = function()
            return Cfg().enabled == true
        end,
        -- DependentSetValue: the Warcraft Recorder row below is hidden
        -- while auto logging is off; the flip forces the full rebuild.
        setValue = CludesUI.DependentSetValue(function()
            return Cfg().enabled == true
        end, function(val)
            Cfg().enabled = val or nil
            Recheck()
            CludesUI:RefreshPage()
        end),
    }, {
        type = "dropdown",
        text = "Auto-Log Triggers",
        values = { __placeholder = "..." },
        order = { "__placeholder" },
        getValue = function()
            return "__placeholder"
        end,
        setValue = function() end,
    })
    posY = posY - trigH

    -- Replace dummy dropdown with a checkbox dropdown.
    do
        local rightRgn = trigRow._rightRegion
        if rightRgn._control then
            rightRgn._control:Hide()
        end

        local cbDD, cbDDRefresh = CludesUI.BuildVisOptsCBDropdown(
            rightRgn,
            210,
            rightRgn:GetFrameLevel() + 2,
            TRIGGER_ITEMS,
            function(k)
                local val = Cfg()[k]
                if val == nil then
                    return TRIGGER_DEFAULTS[k]
                end
                return val
            end,
            function(k, val)
                Cfg()[k] = val
                Recheck()
            end
        )
        Pix.Point(cbDD, "RIGHT", rightRgn, "RIGHT", -20, 0)
        rightRgn._control = cbDD
        rightRgn._lastInline = nil

        CludesUI.RegisterWidgetRefresh(cbDDRefresh)

        -- Gray + block the triggers dropdown (and its label) while Auto
        -- Logging is off; the CB dropdown has no native disabled handling.
        local function UpdateTrigDisabled()
            local off = Cfg().enabled ~= true
            cbDD:SetAlpha(off and 0.3 or 1)
            cbDD:EnableMouse(not off)
            if rightRgn._label then
                rightRgn._label:SetAlpha(off and 0.3 or 1)
            end
        end
        UpdateTrigDisabled()
        CludesUI.RegisterWidgetRefresh(UpdateTrigDisabled)
    end

    -- Warcraft Recorder row: HIDDEN entirely while Auto Logging is off.
    if Cfg().enabled == true then
        _, hgt = W:DualRow(hostFrame, posY, {
            type = "toggle",
            text = "Warcraft Recorder Compatibility",
            tooltip = "Delays stopping combat logging by 30 seconds after leaving an instance. Recommended for Warcraft Recorder compatibility.",
            getValue = function()
                local val = Cfg().delaystop
                if val == nil then
                    return TRIGGER_DEFAULTS.delaystop
                end
                return val
            end,
            setValue = function(val)
                Cfg().delaystop = val
            end,
        }, {
            type = "toggle",
            text = "Chat Notification",
            tooltip = "Prints a chat message when auto logging starts or stops.",
            getValue = function()
                return Cfg().notify == true
            end,
            setValue = function(val)
                Cfg().notify = val or nil
            end,
        })
        posY = posY - hgt
    end -- close Auto Logging hidden-while-disabled gate

    _, hgt = W:Spacer(hostFrame, posY, 20)
    posY = posY - hgt

    ---------------------------------------------------------------------------
    --  ALERTS (Combat Alert, Potion Ready, Unspent Talents; one shared anchor)
    ---------------------------------------------------------------------------
    if _G._CUI_BuildAlertsSection then
        local alertsH = _G._CUI_BuildAlertsSection(hostFrame, posY, W, CludesUI.PP)
        posY = posY - alertsH
    end

    ---------------------------------------------------------------------------
    --  BATTLE RES (no shared battle res charges on WoW Forever: the indicator
    --  runtime builds nothing there and the section is not built)
    ---------------------------------------------------------------------------
    if _G._CUI_BuildBattleResSection and not CludesUI.IS_FOREVER then
        local brezH = _G._CUI_BuildBattleResSection(hostFrame, posY, W, CludesUI.PP)
        posY = posY - brezH
    end

    ---------------------------------------------------------------------------
    --  BLOODLUST TRACKER (no raid-wide lust on WoW Forever: the tracker
    --  runtime returns at load there and the section is not built)
    ---------------------------------------------------------------------------
    if _G._CUI_BuildBloodlustSection and not CludesUI.IS_FOREVER then
        local lustH = _G._CUI_BuildBloodlustSection(hostFrame, posY, W, CludesUI.PP)
        posY = posY - lustH
    end

    return math.abs(posY - yOffset)
end

_G._CUI_BuildAutoLoggingPage = BuildAutoLoggingPage
