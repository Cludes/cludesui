if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_QoL_AutoLogging_Options.lua - the lower part of Utilities > QoL.
--
--  Not a tab of its own: BuildQoLPage (CUI_QoL_Options.lua) chains into it
--  through _G._CUI_BuildAutoLoggingPage. Sections, top to bottom: the /keys
--  popup and the LFG reminder (retail only), the /way command, auto combat
--  logging, then the alert, battle res and bloodlust sections that their own
--  files build. Like every section builder it lays out from yOffset and
--  returns the height it used.
--
--  Each feature's settings are a table of its own in CludesUIDB. Rows that
--  only matter while a feature is on are left out while it is off (a
--  DependentSetValue on the switch rebuilds the page when it flips).
-------------------------------------------------------------------------------
if not CludesUI._ModuleNS["CludesUIQoL"] then
    return -- the module is disabled: no page
end

-- The auto-logging defaults; must match TRIGGER_DEFAULTS in the runtime.
local LOG_DEFAULTS = {
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

local TRIGGERS = {
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
-- WoW Forever: every raid logs on the Raids trigger (the Normal Raid key and
-- its default) and every dungeon on Dungeons (a key only that client has,
-- off until turned on); retail's difficulties, Mythic+, arena, scenarios and
-- rated battlegrounds have nothing to match there.
if CludesUI.IS_FOREVER then
    TRIGGERS = {
        { key = "logNormal", label = "Raids" },
        { key = "logDungeon", label = "Dungeons" },
    }
end

-- A feature's settings table in CludesUIDB (made on first use).
local function Store(name)
    if not CludesUIDB then
        return {}
    end
    CludesUIDB[name] = CludesUIDB[name] or {}
    return CludesUIDB[name]
end
local function Logging()
    return Store("autoLogging")
end
local function Keys()
    return Store("keystonePopup")
end
local function Teleport()
    return Store("teleportPrompt")
end

-- /way's table is only made by a change, so viewing the page saves nothing.
local NONE = {}
local function Way()
    return CludesUIDB and CludesUIDB.waypointCmd or NONE
end
local function SetWay(key, value)
    if CludesUIDB then
        CludesUIDB.waypointCmd = CludesUIDB.waypointCmd or {}
        CludesUIDB.waypointCmd[key] = value
    end
end

local function Call(name)
    local hook = _G[name]
    if hook then
        hook()
    end
end

local function AskReload(what)
    CludesUI:ShowConfirmPopup({
        title = "Reload Required",
        message = "Changing the " .. what .. " requires a reload to update slash command registration.",
        confirmText = "Reload",
        cancelText = "Later",
        reload = true,
    })
end

-- A percent slider over a 0..x scale stored as a fraction (default 1.05).
local function ScaleRow(store, tooltip, applied, extra)
    local row = {
        type = "slider",
        text = "Window Scale",
        min = 50,
        max = 150,
        step = 5,
        tooltip = tooltip,
        getValue = function()
            return math.floor((store().scale or 1.05) * 100 + 0.5)
        end,
        setValue = function(val)
            store().scale = val / 100
            applied(val / 100)
        end,
    }
    for k, v in pairs(extra or {}) do
        row[k] = v
    end
    return row
end

local function Section(W, host, y, title)
    local _, h = W:SectionHeader(host, title, y)
    return y - h
end
local function Gap(W, host, y)
    local _, h = W:Spacer(host, y, 20)
    return y - h
end

-- KEYSTONE CHECK POPUP (/keys)
local function KeysSection(W, host, y)
    y = Section(W, host, y, "KEYSTONE CHECK POPUP")
    local function On()
        return Keys().enabled ~= false
    end
    local _, h = W:DualRow(host, y, {
        type = "toggle",
        text = "Enable /keys Popup (or /ckeys)",
        tooltip = "Shows a popup with party and guild keystones when typing /keys.",
        getValue = On,
        -- Window Scale below shows only while the popup is on.
        setValue = CludesUI.DependentSetValue(On, function(val)
            Keys().enabled = val
            CludesUI:RefreshPage()
            AskReload("/keys popup")
        end),
    }, {
        type = "slider",
        text = "Text Size",
        min = 8,
        max = 16,
        step = 1,
        disabled = function()
            return not On()
        end,
        disabledTooltip = "/keys Popup",
        tooltip = "Font size for keystone entries in the popup (does not affect the header).",
        getValue = function()
            return Keys().textSize or 11
        end,
        setValue = function(val)
            Keys().textSize = val
            Call("_CUI_RefreshKeystonePopup")
        end,
    })
    y = y - h
    if On() then
        _, h = W:DualRow(
            host,
            y,
            ScaleRow(Keys, "Scale of the /keys popup window.", function(scale)
                local popup = _G.CUIKeysPopup
                if popup then
                    popup:SetScale(scale)
                end
            end),
            { type = "label", text = "" }
        )
        y = y - h
    end
    return Gap(W, host, y)
end

-- LFG REMINDER (the dungeon teleport popup)
local function ReminderSection(W, host, y)
    y = Section(W, host, y, "LFG REMINDER")
    local function On()
        return Teleport().enabled ~= false
    end
    local _, h = W:DualRow(
        host,
        y,
        {
            type = "toggle",
            text = "Enable LFG Reminder",
            tooltip = "When you join a Group Finder group for a dungeon that has a teleport, shows a small movable popup with the dungeon name and a one-click teleport button. It hides when you enter the dungeon, leave the group, or enter combat.",
            getValue = On,
            -- The 'Disable Feature' row below shows only while it is on.
            setValue = CludesUI.DependentSetValue(On, function(val)
                Teleport().enabled = val
                CludesUI:RefreshPage()
                -- Live both ways: on builds the popup, off hides it and stops listening.
                Call("_CUI_ApplyTeleportPrompt")
            end),
        },
        ScaleRow(Teleport, "Scale of the LFG Reminder popup window.", function()
            Call("_CUI_RefreshTeleportPrompt")
        end, {
            disabled = function()
                return not On()
            end,
            disabledTooltip = "LFG Reminder",
        })
    )
    y = y - h
    if On() then
        _, h = W:DualRow(host, y, {
            type = "toggle",
            text = "Show 'Disable Feature' Text",
            tooltip = "Shows the 'Disable Feature' text below the teleport button. When off, the text is hidden and the window is 20px shorter.",
            getValue = function()
                return Teleport().showDisable ~= false
            end,
            setValue = function(val)
                Teleport().showDisable = val
                Call("_CUI_RefreshTeleportPrompt")
            end,
        }, { type = "label", text = "" })
        y = y - h
    end
    return Gap(W, host, y)
end

-- WAYPOINT COMMAND (/way; runtime in CludesUIQoL_Waypoint.lua). Off by default.
local function WaySection(W, host, y)
    y = Section(W, host, y, "WAYPOINT COMMAND")
    local row, h = W:DualRow(host, y, {
        type = "toggle",
        text = "Enable /way Command",
        tooltip = "Adds /way, which prints a map pin link.",
        getValue = function()
            return Way().enabled == true
        end,
        setValue = function(val)
            SetWay("enabled", val or nil)
            CludesUI:RefreshPage()
            AskReload("/way command")
        end,
    }, CludesUI.BlankRowCfg())
    y = y - h
    -- Arrival at hand-placed pins (off by default). The runtime listens for
    -- arrivals only while this or a /way list needs them, so it re-syncs.
    CludesUI.BuildInlineCog(row._leftRegion, {
        title = "/way Command",
        disabled = function()
            return Way().enabled ~= true
        end,
        disabledTooltip = "Enable /way Command",
        rows = {
            {
                type = "toggle",
                label = "Hand-Placed Pin Arrival",
                tooltip = "Also announces arrival at pins you place.",
                get = function()
                    return Way().manualArrival == true
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
    return Gap(W, host, y)
end

-- The triggers checklist on the right of the Enable row. DualRow has no
-- checkbox-dropdown type, so the row is built with a stand-in dropdown and
-- the checklist takes its place; it greys out while logging is off.
local function TriggersChecklist(region, Pix)
    if region._control then
        region._control:Hide()
    end
    local function Get(key)
        local v = Logging()[key]
        if v == nil then
            return LOG_DEFAULTS[key]
        end
        return v
    end
    local list, refresh = CludesUI.BuildVisOptsCBDropdown(
        region,
        210,
        region:GetFrameLevel() + 2,
        TRIGGERS,
        Get,
        function(key, val)
            Logging()[key] = val
            Call("_CUI_AutoLogging_Check")
        end
    )
    Pix.Point(list, "RIGHT", region, "RIGHT", -20, 0)
    region._control = list
    region._lastInline = nil
    CludesUI.RegisterWidgetRefresh(refresh)
    local function Grey()
        local off = Logging().enabled ~= true
        list:SetAlpha(off and 0.3 or 1)
        list:EnableMouse(not off)
        if region._label then
            region._label:SetAlpha(off and 0.3 or 1)
        end
    end
    Grey()
    CludesUI.RegisterWidgetRefresh(Grey)
end

-- AUTO COMBAT LOGGING
local function LoggingSection(W, host, y)
    y = Section(W, host, y, "AUTO COMBAT LOGGING")
    local function On()
        return Logging().enabled == true
    end
    local row, h = W:DualRow(host, y, {
        type = "toggle",
        text = "Enable Auto Logging",
        tooltip = "Automatically starts and stops combat logging when entering or leaving a loggable instance.",
        getValue = On,
        -- The Warcraft Recorder row below shows only while logging is on.
        setValue = CludesUI.DependentSetValue(On, function(val)
            Logging().enabled = val or nil
            Call("_CUI_AutoLogging_Check")
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
    y = y - h
    TriggersChecklist(row._rightRegion, CludesUI.PanelPP)
    if On() then
        local _
        _, h = W:DualRow(host, y, {
            type = "toggle",
            text = "Warcraft Recorder Compatibility",
            tooltip = "Delays stopping combat logging by 30 seconds after leaving an instance. Recommended for Warcraft Recorder compatibility.",
            getValue = function()
                local v = Logging().delaystop
                if v == nil then
                    return LOG_DEFAULTS.delaystop
                end
                return v
            end,
            setValue = function(val)
                Logging().delaystop = val
            end,
        }, {
            type = "toggle",
            text = "Chat Notification",
            tooltip = "Prints a chat message when auto logging starts or stops.",
            getValue = function()
                return Logging().notify == true
            end,
            setValue = function(val)
                Logging().notify = val or nil
            end,
        })
        y = y - h
    end
    return Gap(W, host, y)
end

-- A section another file builds (alerts, battle res, bloodlust), if loaded.
local function External(name, host, y, W)
    local build = _G[name]
    if not build then
        return y
    end
    return y - build(host, y, W, CludesUI.PP)
end

local function Build(_, host, yOffset)
    local W = CludesUI.Widgets
    host._showRowDivider = true
    local y = yOffset
    -- No keystones or dungeon teleports on WoW Forever.
    if not CludesUI.IS_FOREVER then
        y = KeysSection(W, host, y)
        y = ReminderSection(W, host, y)
    end
    y = WaySection(W, host, y)
    y = LoggingSection(W, host, y)
    y = External("_CUI_BuildAlertsSection", host, y, W)
    -- No shared battle res charges or raid-wide lust on WoW Forever.
    if not CludesUI.IS_FOREVER then
        y = External("_CUI_BuildBattleResSection", host, y, W)
        y = External("_CUI_BuildBloodlustSection", host, y, W)
    end
    return math.abs(y - yOffset)
end

_G._CUI_BuildAutoLoggingPage = Build
