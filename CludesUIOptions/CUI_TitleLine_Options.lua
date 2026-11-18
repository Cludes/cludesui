if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_TitleLine_Options.lua
--  The Title Line page of the CludesUI settings panel. Title Line's graph is
--  its own window (it is a chart, not settings); this page holds its settings
--  and a button that opens the graph.
-------------------------------------------------------------------------------
local ADDON_NAME = "CludesUITitleLine"
local mod = CludesUI._ModuleNS[ADDON_NAME]
if not mod then
    return
end

local PAGE = "Title Line"

CludesUI.AtOptionsLogin(function()

    local function DB()
        return _G.CludesUITitleLineDB or {}
    end

    local function Toggle(textValue, key, tooltip, default)
        return {
            type = "toggle",
            text = textValue,
            tooltip = tooltip,
            getValue = function()
                local val = DB()[key]
                if val == nil then
                    return default and true or false
                end
                return val and true or false
            end,
            setValue = function(val)
                DB()[key] = val and true or false
            end,
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
                if mod.Graph and mod.Graph.Refresh then
                    mod.Graph:Refresh()
                end
            end,
        }
    end

    local function BuildPage(_, hostFrame, yOffset)
        local W = CludesUI.Widgets
        local posY = yOffset
        local _, hgt

        CludesUI:ClearContentHeader()

        _, hgt = W:SectionHeader(hostFrame, "GRAPH", posY)
        posY = posY - hgt

        _, hgt = W:DualRow(hostFrame, posY, {
            type = "labeledButton",
            text = "Season Graph",
            buttonText = "Open",
            width = 90,
            tooltip = "Your Mythic+ rating through the season against the title lines. /titleline does the same.",
            onClick = function()
                if mod.Graph and mod.Graph.Toggle then
                    mod.Graph:Toggle()
                end
            end,
        }, {
            type = "slider",
            text = "Graph Window Scale",
            min = 70,
            max = 200,
            step = 5,
            tooltip = "The size of the graph window, in percent.",
            getValue = function()
                return math.floor((DB().scale or 1.15) * 100 + 0.5)
            end,
            setValue = function(val)
                DB().scale = math.floor(val + 0.5) / 100
                if mod.Graph and mod.Graph.ApplyScale then
                    mod.Graph:ApplyScale()
                end
            end,
        })
        posY = posY - hgt

        local tiers = mod.TIERS or {}
        if #tiers > 0 then
            _, hgt = W:DualRow(
                hostFrame,
                posY,
                LineToggle(tiers[1]),
                tiers[2] and LineToggle(tiers[2]) or { type = "label", text = "" }
            )
            posY = posY - hgt
        end

        _, hgt = W:SectionHeader(hostFrame, "MESSAGES", posY)
        posY = posY - hgt

        _, hgt = W:DualRow(
            hostFrame,
            posY,
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
        posY = posY - hgt

        return math.abs(posY)
    end

    CludesUI:RegisterModule(ADDON_NAME, {
        title = "Title Line",
        description = "Your Mythic+ rating against the 0.1% and 1% title lines.",
        pages = { PAGE },
        buildPage = function(page, hostFrame, yOffset)
            if page == PAGE then
                return BuildPage(page, hostFrame, yOffset)
            end
        end,
    })
end)
