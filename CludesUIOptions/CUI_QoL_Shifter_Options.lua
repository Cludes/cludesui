if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_QoL_Shifter_Options.lua
--  Builds the "Shifter" page inside the Quality of Life module.
-------------------------------------------------------------------------------

-- "CharacterFrame" -> "Character", "AuctionHouseFrame" -> "Auction House", etc.
if not CludesUI._ModuleNS["CludesUIQoL"] then
    return
end -- module disabled: no options page

-- Page reuse: frames this file builds go through the options frame pool
-- (CludesUI_FramePool.lua), which hands a kept page its previous build's
-- frames back reset to new; on any other parent it is the plain CreateFrame.
local CreateFrame = CludesUI._Pool.CreateFrame

local function PrettifyName(name)
    local pretty = name:gsub("Frame$", "")
    pretty = pretty:gsub("(%l)(%u)", "%1 %2"):gsub("(%u)(%u%l)", "%1 %2")
    return pretty
end

_G._CUI_BuildShifterPage = function(page, hostFrame, yOffset)
    local W = CludesUI.Widgets
    local posY = yOffset
    local _, hgt, heading

    -- Info text (top of page, matching bags pattern)
    do
        local fontFile = (CludesUI.GetFontPath()) or "Fonts\\FRIZQT__.TTF"
        local infoFrame = CreateFrame("Frame", nil, hostFrame)
        infoFrame:SetSize(hostFrame:GetWidth(), 34)
        infoFrame:SetPoint("TOP", hostFrame, "TOP", 0, posY - 10)
        infoFrame._isSpacer = true
        local line1 = infoFrame:CreateFontString(nil, "OVERLAY")
        line1:SetFont(fontFile, 15, "")
        line1:SetTextColor(1, 1, 1, 0.75)
        line1:SetPoint("TOP", infoFrame, "TOP", 0, 0)
        line1:SetJustifyH("CENTER")
        line1:SetText(CludesUI.L("Shift + Left-Click Drag to permanently save a panel's position."))
        local line2 = infoFrame:CreateFontString(nil, "OVERLAY")
        line2:SetFont(fontFile, 15, "")
        line2:SetTextColor(1, 1, 1, 0.75)
        line2:SetPoint("TOP", line1, "BOTTOM", 0, -2)
        line2:SetJustifyH("CENTER")
        line2:SetText(
            CludesUI.L("Ctrl + Left-Click Drag for a temporary move that resets when the panel closes.")
        )
        local line3 = infoFrame:CreateFontString(nil, "OVERLAY")
        line3:SetFont(fontFile, 15, "")
        line3:SetTextColor(1, 1, 1, 0.75)
        line3:SetPoint("TOP", line2, "BOTTOM", 0, -2)
        line3:SetJustifyH("CENTER")
        line3:SetText(
            CludesUI.L("Shift + Scroll to permanently zoom a panel. Ctrl + Scroll for a temporary zoom.")
        )
        posY = posY - 70
    end

    -- Reset All button
    _, hgt = W:WideButton(hostFrame, "Reset All Positions & Zoom", posY, function()
        CludesUI:ShowConfirmPopup({
            title = "Reset Shifter Positions & Zoom",
            message = "This will reset all saved panel positions and zoom levels and reload your UI.",
            confirmText = "Reset",
            cancelText = "Cancel",
            reload = true,
            onConfirm = function()
                if CludesUI._ResetShifterPositions then
                    CludesUI._ResetShifterPositions()
                end
            end,
        })
    end)
    posY = posY - hgt

    ---------------------------------------------------------------------------
    --  SHIFTER
    ---------------------------------------------------------------------------
    _, hgt = W:SectionHeader(hostFrame, "SHIFTER", posY)
    posY = posY - hgt

    hostFrame._showRowDivider = true

    -- Build dropdown values for Reset Specific Window (any window with a
    -- saved position OR a saved zoom)
    local ddValues = { [""] = "Choose Window..." }
    local ddOrder = {}
    do
        local seen = {}
        local function collect(tbl)
            if not tbl then
                return
            end
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
        table.sort(ddOrder, function(a, b)
            return ddValues[a] < ddValues[b]
        end)
    end

    -- Row 1: Enable Shifter | Reset Specific Window
    _, hgt = W:DualRow(hostFrame, posY, {
        type = "toggle",
        text = "Enable Shifter",
        getValue = function()
            return CludesUIDB and CludesUIDB.shifterEnabled or false
        end,
        setValue = function(val)
            if not CludesUIDB then
                CludesUIDB = {}
            end
            CludesUIDB.shifterEnabled = val
            if val and CludesUI._InitShifter then
                CludesUI._InitShifter()
            elseif not val and CludesUI._ShutdownShifter then
                CludesUI._ShutdownShifter()
            end
        end,
    }, {
        type = "dropdown",
        text = "Reset Specific Window",
        values = ddValues,
        order = ddOrder,
        getValue = function()
            return ""
        end,
        setValue = function(frameName)
            if frameName == "" then
                return
            end
            local pretty = ddValues[frameName] or PrettifyName(frameName)
            CludesUI:ShowConfirmPopup({
                title = "Reset Window Position & Zoom",
                message = CludesUI.Lf(
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
    posY = posY - hgt

    -- Row 2: Move windows without shift
    _, hgt = W:DualRow(hostFrame, posY, {
        type = "toggle",
        text = "Move Windows Without Shift",
        tooltip = "When enabled, left-click dragging a window will save its position without needing to hold Shift. Ctrl+drag still does a temporary move.",
        getValue = function()
            return CludesUIDB and CludesUIDB.shifterNoShift or false
        end,
        setValue = function(val)
            if not CludesUIDB then
                CludesUIDB = {}
            end
            CludesUIDB.shifterNoShift = val
        end,
    }, { type = "label", text = "" })
    posY = posY - hgt

    ---------------------------------------------------------------------------
    --  LOOT WINDOWS
    ---------------------------------------------------------------------------
    heading, hgt = W:SectionHeader(hostFrame, "LOOT WINDOWS", posY)
    posY = posY - hgt

    local function lootUnlockOff()
        return not (CludesUIDB and CludesUIDB.shifterLootUnlock)
    end
    -- One toggle adds all three loot movers, so the button takes the first.
    CludesUI.BuildSectionUnlockJump(heading, {
        key = "CUI_BonusRoll",
        disabled = lootUnlockOff,
        disabledTooltip = "Move Loot Windows in Layout Mode",
    })

    _, hgt = W:DualRow(hostFrame, posY, {
        type = "toggle",
        text = "Move Loot Windows in Layout Mode",
        tooltip = "Adds Bonus Roll, Group Loot, and Alert Toast movers to Layout Mode.",
        getValue = function()
            return CludesUIDB and CludesUIDB.shifterLootUnlock or false
        end,
        setValue = function(val)
            if not CludesUIDB then
                CludesUIDB = {}
            end
            CludesUIDB.shifterLootUnlock = val
            if val then
                if CludesUI._InitShifterLootWindows then
                    CludesUI._InitShifterLootWindows()
                end
            else
                if CludesUI._DisableShifterLootWindows then
                    CludesUI._DisableShifterLootWindows()
                end
            end
            CludesUI:RefreshPage() -- update the overlay toggle disabled state
        end,
    }, {
        type = "toggle",
        text = "Hide Layout Mode Overlays",
        tooltip = "Hides the loot window movers in Layout Mode while keeping their saved positions applied.",
        disabled = lootUnlockOff,
        disabledTooltip = "Move Loot Windows in Layout Mode",
        getValue = function()
            return CludesUIDB and CludesUIDB.shifterLootHideOverlays or false
        end,
        setValue = function(val)
            if not CludesUIDB then
                CludesUIDB = {}
            end
            CludesUIDB.shifterLootHideOverlays = val
        end,
    })
    posY = posY - hgt

    ---------------------------------------------------------------------------
    --  BLIZZARD TOP BAR EVENT TEXT
    ---------------------------------------------------------------------------
    heading, hgt = W:SectionHeader(hostFrame, "BLIZZARD TOP BAR EVENT TEXT", posY)
    posY = posY - hgt

    local function topBarUnlockOff()
        return not (CludesUIDB and CludesUIDB.shifterTopBarUnlock)
    end
    CludesUI.BuildSectionUnlockJump(heading, {
        key = "CUI_TopBarEventText",
        disabled = topBarUnlockOff,
        disabledTooltip = "Move Top Bar Event Text in Layout Mode",
    })

    _, hgt = W:DualRow(hostFrame, posY, {
        type = "toggle",
        text = "Move Top Bar Event Text in Layout Mode",
        tooltip = "Adds a mover for Blizzard's top-center event text and widgets (scenario, event, and encounter bars).",
        getValue = function()
            return CludesUIDB and CludesUIDB.shifterTopBarUnlock or false
        end,
        setValue = function(val)
            if not CludesUIDB then
                CludesUIDB = {}
            end
            CludesUIDB.shifterTopBarUnlock = val
            if val then
                if CludesUI._InitShifterTopBar then
                    CludesUI._InitShifterTopBar()
                end
            else
                if CludesUI._DisableShifterTopBar then
                    CludesUI._DisableShifterTopBar()
                end
            end
            CludesUI:RefreshPage() -- update the overlay toggle disabled state
        end,
    }, {
        type = "toggle",
        text = "Hide Layout Mode Overlay",
        tooltip = "Hides the Top Bar Event Text mover in Layout Mode while keeping its saved position applied.",
        disabled = topBarUnlockOff,
        disabledTooltip = "Move Top Bar Event Text in Layout Mode",
        getValue = function()
            return CludesUIDB and CludesUIDB.shifterTopBarHideOverlay or false
        end,
        setValue = function(val)
            if not CludesUIDB then
                CludesUIDB = {}
            end
            CludesUIDB.shifterTopBarHideOverlay = val
        end,
    })
    posY = posY - hgt

    ---------------------------------------------------------------------------
    --  BATTLEGROUND FRAMES
    ---------------------------------------------------------------------------
    heading, hgt = W:SectionHeader(hostFrame, "BATTLEGROUND FRAMES", posY)
    posY = posY - hgt

    local function battlegroundUnlockOff()
        return not (CludesUIDB and CludesUIDB.shifterBattlegroundUnlock)
    end
    -- One toggle adds both battleground movers, so the button takes the flag carriers'.
    CludesUI.BuildSectionUnlockJump(heading, {
        key = "CUI_FlagCarriers",
        disabled = battlegroundUnlockOff,
        disabledTooltip = "Move Battleground Frames in Layout Mode",
    })

    _, hgt = W:DualRow(hostFrame, posY, {
        type = "toggle",
        text = "Move Battleground Frames in Layout Mode",
        tooltip = "Adds movers for the battleground flag carriers and the capture bar to Layout Mode.",
        getValue = function()
            return CludesUIDB and CludesUIDB.shifterBattlegroundUnlock or false
        end,
        setValue = function(val)
            if not CludesUIDB then
                CludesUIDB = {}
            end
            CludesUIDB.shifterBattlegroundUnlock = val
            if CludesUI._InitShifterLootWindows then
                CludesUI._InitShifterLootWindows()
            end
            if CludesUI._SyncShifterCarriers then
                CludesUI._SyncShifterCarriers()
            end
            CludesUI:RefreshPage() -- update the overlay toggle disabled state
        end,
    }, {
        type = "toggle",
        text = "Hide Layout Mode Overlays",
        tooltip = "Hides the battleground frame movers in Layout Mode while keeping their saved positions applied.",
        disabled = battlegroundUnlockOff,
        disabledTooltip = "Move Battleground Frames in Layout Mode",
        getValue = function()
            return CludesUIDB and CludesUIDB.shifterBattlegroundHideOverlays or false
        end,
        setValue = function(val)
            if not CludesUIDB then
                CludesUIDB = {}
            end
            CludesUIDB.shifterBattlegroundHideOverlays = val
        end,
    })
    posY = posY - hgt

    return math.abs(posY)
end
