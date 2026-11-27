if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-------------------------------------------------------------------------------
--  CUI_QoL_Shifter_Options.lua
--  Builds the "Shifter" page inside the Quality of Life module.
-------------------------------------------------------------------------------

-- "CharacterFrame" -> "Character", "AuctionHouseFrame" -> "Auction House", etc.
if not CUI._ModuleNS["CludesUIQoL"] then return end -- module disabled: no options page

-- Page reuse: frames this file builds go through the options frame pool
-- (CludesUI_FramePool.lua), which hands a kept page its previous build's
-- frames back reset to new; on any other parent it is the plain CreateFrame.
local CreateFrame = CUI._Pool.CreateFrame

-- The account-wide settings table, made if it is not there yet, for a write.
local function Account()
    if not CludesUIDB then CludesUIDB = {} end
    return CludesUIDB
end

local function PrettifyName(name)
    local pretty = name:gsub("Frame$", "")
    pretty = pretty:gsub("(%l)(%u)", "%1 %2"):gsub("(%u)(%u%l)", "%1 %2")
    return pretty
end

_G._CUI_BuildShifterPage = function(page, hostFrame, yOffset)
    local W = CUI.Widgets
    local cursorY = yOffset
    local _, height, heading

    -- Info text (top of page, matching bags pattern)
    do
        local fontFile = (CUI.GetFontPath()) or "Fonts\\FRIZQT__.TTF"
        local infoFrame = CreateFrame("Frame", nil, hostFrame)
        infoFrame:SetSize(hostFrame:GetWidth(), 34)
        infoFrame:SetPoint("TOP", hostFrame, "TOP", 0, cursorY - 10)
        infoFrame._isSpacer = true
        local line1 = infoFrame:CreateFontString(nil, "OVERLAY")
        line1:SetFont(fontFile, 15, "")
        line1:SetTextColor(1, 1, 1, 0.75)
        line1:SetPoint("TOP", infoFrame, "TOP", 0, 0)
        line1:SetJustifyH("CENTER")
        line1:SetText(CUI.L("Shift + Left-Click Drag to permanently save a panel's position."))
        local line2 = infoFrame:CreateFontString(nil, "OVERLAY")
        line2:SetFont(fontFile, 15, "")
        line2:SetTextColor(1, 1, 1, 0.75)
        line2:SetPoint("TOP", line1, "BOTTOM", 0, -2)
        line2:SetJustifyH("CENTER")
        line2:SetText(
            CUI.L("Ctrl + Left-Click Drag for a temporary move that resets when the panel closes.")
        )
        local line3 = infoFrame:CreateFontString(nil, "OVERLAY")
        line3:SetFont(fontFile, 15, "")
        line3:SetTextColor(1, 1, 1, 0.75)
        line3:SetPoint("TOP", line2, "BOTTOM", 0, -2)
        line3:SetJustifyH("CENTER")
        line3:SetText(
            CUI.L("Shift + Scroll to permanently zoom a panel. Ctrl + Scroll for a temporary zoom.")
        )
        cursorY = cursorY - 70
    end

    -- Reset All button
    _, height = W:WideButton(hostFrame, "Reset All Positions & Zoom", cursorY, function()
        CUI:ShowConfirmPopup({
            title = "Reset Shifter Positions & Zoom",
            message = "This will reset all saved panel positions and zoom levels and reload your UI.",
            confirmText = "Reset",
            cancelText = "Cancel",
            reload = true,
            onConfirm = function()
                if CUI._ResetShifterPositions then CUI._ResetShifterPositions() end
            end,
        })
    end)
    cursorY = cursorY - height

    ---------------------------------------------------------------------------
    --  SHIFTER
    ---------------------------------------------------------------------------
    _, height = W:SectionHeader(hostFrame, "SHIFTER", cursorY)
    cursorY = cursorY - height

    hostFrame._showRowDivider = true

    -- Build dropdown values for Reset Specific Window (any window with a
    -- saved position OR a saved zoom)
    local ddValues = { [""] = "Choose Window..." }
    local ddOrder = {}
    do
        local seen = {}
        local function collect(tbl)
            if not tbl then return end
            for name in pairs(tbl) do
                if not seen[name] then
                    seen[name] = true
                    ddValues[name] = PrettifyName(name)
                    ddOrder[#ddOrder + 1] = name
                end
            end
        end
        collect(CludesUIDB and CludesUIDB.shifterPositions)
        collect(CludesUIDB and CludesUIDB.shifterScales)
        table.sort(ddOrder, function(lhs, rhs) return ddValues[lhs] < ddValues[rhs] end)
    end

    -- Row 1: Enable Shifter | Reset Specific Window
    _, height = W:DualRow(hostFrame, cursorY, {
        type = "toggle",
        text = "Enable Shifter",
        tooltip = "Lets you move Blizzard windows.",
        getValue = function() return CludesUIDB and CludesUIDB.shifterEnabled or false end,
        setValue = function(val)
            Account().shifterEnabled = val
            if val and CUI._InitShifter then
                CUI._InitShifter()
            elseif not val and CUI._ShutdownShifter then
                CUI._ShutdownShifter()
            end
        end,
    }, {
        type = "dropdown",
        text = "Reset Specific Window",
        tooltip = "Puts one moved window back where it was.",
        values = ddValues,
        order = ddOrder,
        getValue = function() return "" end,
        setValue = function(frameName)
            if frameName == "" then return end
            local pretty = ddValues[frameName] or PrettifyName(frameName)
            CUI:ShowConfirmPopup({
                title = "Reset Window Position & Zoom",
                message = CUI.Lf(
                    "Reset %1$s to its default position and zoom and reload your UI?",
                    pretty
                ),
                confirmText = "Reset",
                cancelText = "Cancel",
                reload = true,
                onConfirm = function()
                    if CludesUIDB and CludesUIDB.shifterPositions then
                        CludesUIDB.shifterPositions[frameName] = nil
                    end
                    if CludesUIDB and CludesUIDB.shifterScales then
                        CludesUIDB.shifterScales[frameName] = nil
                    end
                end,
            })
        end,
    })
    cursorY = cursorY - height

    -- Row 2: Move windows without shift
    _, height = W:DualRow(hostFrame, cursorY, {
        type = "toggle",
        text = "Move Windows Without Shift",
        tooltip = "When enabled, left-click dragging a window will save its position without needing to hold Shift. Ctrl+drag still does a temporary move.",
        getValue = function() return CludesUIDB and CludesUIDB.shifterNoShift or false end,
        setValue = function(val) Account().shifterNoShift = val end,
    }, { type = "label", text = "" })
    cursorY = cursorY - height

    ---------------------------------------------------------------------------
    --  LOOT WINDOWS
    ---------------------------------------------------------------------------
    heading, height = W:SectionHeader(hostFrame, "LOOT WINDOWS", cursorY)
    cursorY = cursorY - height

    local function lootUnlockOff() return not (CludesUIDB and CludesUIDB.shifterLootUnlock) end
    -- One toggle adds all three loot movers, so the button takes the first.
    CUI.BuildSectionUnlockJump(heading, {
        key = "CUI_BonusRoll",
        disabled = lootUnlockOff,
        disabledTooltip = "Move Loot Windows in Edit Layout",
    })

    _, height = W:DualRow(hostFrame, cursorY, {
        type = "toggle",
        text = "Move Loot Windows in Edit Layout",
        tooltip = "Adds Bonus Roll, Group Loot, and Alert Toast movers to Edit Layout.",
        getValue = function() return CludesUIDB and CludesUIDB.shifterLootUnlock or false end,
        setValue = function(val)
            Account().shifterLootUnlock = val
            if val then
                if CUI._InitShifterLootWindows then CUI._InitShifterLootWindows() end
            else
                if CUI._DisableShifterLootWindows then CUI._DisableShifterLootWindows() end
            end
            CUI:RefreshPage() -- update the overlay toggle disabled state
        end,
    }, {
        type = "toggle",
        text = "Hide Edit Layout Overlays",
        tooltip = "Hides the loot window movers in Edit Layout while keeping their saved positions applied.",
        disabled = lootUnlockOff,
        disabledTooltip = "Move Loot Windows in Edit Layout",
        getValue = function() return CludesUIDB and CludesUIDB.shifterLootHideOverlays or false end,
        setValue = function(val) Account().shifterLootHideOverlays = val end,
    })
    cursorY = cursorY - height

    ---------------------------------------------------------------------------
    --  BLIZZARD TOP BAR EVENT TEXT
    ---------------------------------------------------------------------------
    heading, height = W:SectionHeader(hostFrame, "BLIZZARD TOP BAR EVENT TEXT", cursorY)
    cursorY = cursorY - height

    local function topBarUnlockOff() return not (CludesUIDB and CludesUIDB.shifterTopBarUnlock) end
    CUI.BuildSectionUnlockJump(heading, {
        key = "CUI_TopBarEventText",
        disabled = topBarUnlockOff,
        disabledTooltip = "Move Top Bar Event Text in Edit Layout",
    })

    _, height = W:DualRow(hostFrame, cursorY, {
        type = "toggle",
        text = "Move Top Bar Event Text in Edit Layout",
        tooltip = "Adds a mover for Blizzard's top-center event text and widgets (scenario, event, and encounter bars).",
        getValue = function() return CludesUIDB and CludesUIDB.shifterTopBarUnlock or false end,
        setValue = function(val)
            Account().shifterTopBarUnlock = val
            if val then
                if CUI._InitShifterTopBar then CUI._InitShifterTopBar() end
            else
                if CUI._DisableShifterTopBar then CUI._DisableShifterTopBar() end
            end
            CUI:RefreshPage() -- update the overlay toggle disabled state
        end,
    }, {
        type = "toggle",
        text = "Hide Edit Layout Overlay",
        tooltip = "Hides the Top Bar Event Text mover in Edit Layout while keeping its saved position applied.",
        disabled = topBarUnlockOff,
        disabledTooltip = "Move Top Bar Event Text in Edit Layout",
        getValue = function() return CludesUIDB and CludesUIDB.shifterTopBarHideOverlay or false end,
        setValue = function(val) Account().shifterTopBarHideOverlay = val end,
    })
    cursorY = cursorY - height

    ---------------------------------------------------------------------------
    --  BATTLEGROUND FRAMES
    ---------------------------------------------------------------------------
    heading, height = W:SectionHeader(hostFrame, "BATTLEGROUND FRAMES", cursorY)
    cursorY = cursorY - height

    local function battlegroundUnlockOff() return not (CludesUIDB and CludesUIDB.shifterBattlegroundUnlock) end
    -- One toggle adds both battleground movers, so the button takes the flag carriers'.
    CUI.BuildSectionUnlockJump(heading, {
        key = "CUI_FlagCarriers",
        disabled = battlegroundUnlockOff,
        disabledTooltip = "Move Battleground Frames in Edit Layout",
    })

    _, height = W:DualRow(hostFrame, cursorY, {
        type = "toggle",
        text = "Move Battleground Frames in Edit Layout",
        tooltip = "Adds movers for the battleground flag carriers and the capture bar to Edit Layout.",
        getValue = function() return CludesUIDB and CludesUIDB.shifterBattlegroundUnlock or false end,
        setValue = function(val)
            Account().shifterBattlegroundUnlock = val
            if CUI._InitShifterLootWindows then CUI._InitShifterLootWindows() end
            if CUI._SyncShifterCarriers then CUI._SyncShifterCarriers() end
            CUI:RefreshPage() -- update the overlay toggle disabled state
        end,
    }, {
        type = "toggle",
        text = "Hide Edit Layout Overlays",
        tooltip = "Hides the battleground frame movers in Edit Layout while keeping their saved positions applied.",
        disabled = battlegroundUnlockOff,
        disabledTooltip = "Move Battleground Frames in Edit Layout",
        getValue = function() return CludesUIDB and CludesUIDB.shifterBattlegroundHideOverlays or false end,
        setValue = function(val) Account().shifterBattlegroundHideOverlays = val end,
    })
    cursorY = cursorY - height

    return math.abs(cursorY)
end
