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
local ns = CludesUI._ModuleNS[ADDON_NAME]
if not ns then
    return
end

local PAGE = "Title Line"

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if not CludesUI or not CludesUI.RegisterModule then
        return
    end

    local function DB()
        return _G.CludesUITitleLineDB or {}
    end

    local function Toggle(text, key, tooltip, default)
        return {
            type = "toggle",
            text = text,
            tooltip = tooltip,
            getValue = function()
                local v = DB()[key]
                if v == nil then
                    return default and true or false
                end
                return v and true or false
            end,
            setValue = function(v)
                DB()[key] = v and true or false
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
            setValue = function(v)
                local db = DB()
                db.hidden = db.hidden or {}
                db.hidden[tier.key] = (not v) or nil
                if ns.Graph and ns.Graph.Refresh then
                    ns.Graph:Refresh()
                end
            end,
        }
    end

    local function BuildPage(_, parent, yOffset)
        local W = CludesUI.Widgets
        local y = yOffset
        local _, h

        CludesUI:ClearContentHeader()

        _, h = W:SectionHeader(parent, "GRAPH", y)
        y = y - h

        _, h = W:DualRow(parent, y, {
            type = "labeledButton",
            text = "Season Graph",
            buttonText = "Open",
            width = 90,
            tooltip = "Your Mythic+ rating through the season against the title lines. /titleline does the same.",
            onClick = function()
                if ns.Graph and ns.Graph.Toggle then
                    ns.Graph:Toggle()
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
            setValue = function(v)
                DB().scale = math.floor(v + 0.5) / 100
                if ns.Graph and ns.Graph.ApplyScale then
                    ns.Graph:ApplyScale()
                end
            end,
        })
        y = y - h

        local tiers = ns.TIERS or {}
        if #tiers > 0 then
            _, h = W:DualRow(
                parent,
                y,
                LineToggle(tiers[1]),
                tiers[2] and LineToggle(tiers[2]) or { type = "label", text = "" }
            )
            y = y - h
        end

        _, h = W:SectionHeader(parent, "MESSAGES", y)
        y = y - h

        _, h = W:DualRow(
            parent,
            y,
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
        y = y - h

        return math.abs(y)
    end

    CludesUI:RegisterModule(ADDON_NAME, {
        title = "Title Line",
        description = "Your Mythic+ rating against the 0.1% and 1% title lines.",
        pages = { PAGE },
        buildPage = function(pageName, parent, yOffset)
            if pageName == PAGE then
                return BuildPage(pageName, parent, yOffset)
            end
        end,
    })
end)
if IsLoggedIn() then
    initFrame:GetScript("OnEvent")(initFrame)
end
