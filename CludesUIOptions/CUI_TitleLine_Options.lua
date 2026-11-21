if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-------------------------------------------------------------------------------
--  CUI_TitleLine_Options.lua
--  The Title Line page of the CludesUI settings panel. Title Line's graph is
--  its own window (it is a chart, not settings); this page holds its settings
--  and a button that opens the graph.
-------------------------------------------------------------------------------
local ADDON_NAME = "CludesUITitleLine"
local mod = CUI._ModuleNS[ADDON_NAME]
if not mod then return end

local PAGE = "Title Line"

CUI.AtOptionsLogin(function()
    local function DB() return _G.CludesUITitleLineDB or {} end

    local function Toggle(textValue, key, tooltip, default)
        return {
            type = "toggle",
            text = textValue,
            tooltip = tooltip,
            getValue = function()
                local val = DB()[key]
                if val == nil then return default and true or false end
                return val and true or false
            end,
            setValue = function(val) DB()[key] = val and true or false end,
        }
    end

    -- A line is shown unless it is in the hidden list.
    local function LineToggle(tier)
        return {
            type = "toggle",
            text = "Show the " .. tier.label .. " Line",
            getValue = function()
                local hidden = DB().hidden
                return not (hidden and hidden[tier.key])
            end,
            setValue = function(val)
                local saved = DB()
                saved.hidden = saved.hidden or {}
                saved.hidden[tier.key] = (not val) or nil
                if mod.Graph and mod.Graph.Refresh then mod.Graph:Refresh() end
            end,
        }
    end

    local function BuildPage(_, hostFrame, yOffset)
        local W = CUI.Widgets
        local cursorY = yOffset
        local _, height

        CUI:ClearContentHeader()

        _, height = W:SectionHeader(hostFrame, "GRAPH", cursorY)
        cursorY = cursorY - height

        _, height = W:DualRow(hostFrame, cursorY, {
            type = "labeledButton",
            text = "Season Graph",
            buttonText = "Open",
            width = 90,
            tooltip = "Your Mythic+ rating through the season against the title lines. /titleline does the same.",
            onClick = function()
                if mod.Graph and mod.Graph.Toggle then mod.Graph:Toggle() end
            end,
        }, {
            type = "slider",
            text = "Graph Window Scale",
            min = 70,
            max = 200,
            step = 5,
            tooltip = "The size of the graph window, in percent.",
            getValue = function() return math.floor((DB().scale or 1.15) * 100 + 0.5) end,
            setValue = function(val)
                DB().scale = math.floor(val + 0.5) / 100
                if mod.Graph and mod.Graph.ApplyScale then mod.Graph:ApplyScale() end
            end,
        })
        cursorY = cursorY - height

        local tiers = mod.TIERS or {}
        if #tiers > 0 then
            _, height = W:DualRow(
                hostFrame,
                cursorY,
                LineToggle(tiers[1]),
                tiers[2] and LineToggle(tiers[2]) or { type = "label", text = "" }
            )
            cursorY = cursorY - height
        end

        _, height = W:SectionHeader(hostFrame, "MESSAGES", cursorY)
        cursorY = cursorY - height

        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Toggle(
                "Distance to the Lines After a Key",
                "chat",
                "After each key, a chat line says how far you are from each title line.",
                true
            ),
            Toggle(
                "Line Alerts",
                "alerts",
                "A warning on screen when you pass a title line, or a line passes you.",
                true
            )
        )
        cursorY = cursorY - height

        return math.abs(cursorY)
    end

    CUI:RegisterModule(ADDON_NAME, {
        title = "Title Line",
        description = "Your Mythic+ rating against the 0.1% and 1% title lines.",
        pages = { PAGE },
        buildPage = function(page, hostFrame, yOffset)
            if page == PAGE then return BuildPage(page, hostFrame, yOffset) end
        end,
    })
end)
