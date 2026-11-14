if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if CludesUI and CludesUI.IS_FOREVER then
    return
end -- no item upgrade system on WoW Forever: the QoL module lists no Upgrader tab there and its callers nil-guard the page builder and reset
-------------------------------------------------------------------------------
--  CUI_UpgradeCalc_Options.lua
--  Options page for the Upgrade Calculator feature (part of CludesUIQoL).
-------------------------------------------------------------------------------

if not CludesUI._ModuleNS["CludesUIQoL"] then
    return
end -- module disabled: no options page

-- Page reuse: frames this file builds go through the options frame pool
-- (CludesUI_FramePool.lua), which hands a kept page its previous build's
-- frames back reset to new; on any other parent it is the plain CreateFrame.
local CreateFrame = CludesUI._Pool.CreateFrame

local function GetAddonDB()
    -- Always delegate to the main module so we read from the same profile
    -- slice that persists via CludesUIDB (not the wiped CludesUIQoLDB).
    if CUIUpgCalc and CUIUpgCalc.GetOptsDB then
        return CUIUpgCalc.GetOptsDB()
    end
    CludesUIQoLDB = CludesUIQoLDB or {}
    CludesUIQoLDB.upgradeCalcOpts = CludesUIQoLDB.upgradeCalcOpts or {}
    return CludesUIQoLDB.upgradeCalcOpts
end

local function BuildUpgradeCalcPage(page, hostFrame, yOffset)
    local W = CludesUI.Widgets
    local Pix = CludesUI.PanelPP
    local posY = yOffset
    local _, hgt

    hostFrame._showRowDivider = true

    if CludesUI.ClearContentHeader then
        CludesUI:ClearContentHeader()
    end

    local function LiveRefresh()
        local fr = _G["CUIUpgCalcFrame"]
        if fr and fr:IsShown() and CUIUpgCalc and CUIUpgCalc.PopulateGear then
            CUIUpgCalc.PopulateGear()
        end
    end

    ---------------------------------------------------------------------------
    --  Top action buttons: Open Calculator + Clear Upgrade Cache
    ---------------------------------------------------------------------------
    do
        local BTN_W = 312
        local BTN_H = 38
        local GAP = 40
        local ROW_H = BTN_H + 20
        local rowFrame = CreateFrame("Frame", nil, hostFrame)
        local totalW = hostFrame:GetWidth() - CludesUI.CONTENT_PAD * 2
        Pix.Size(rowFrame, totalW, ROW_H)
        Pix.Point(rowFrame, "TOPLEFT", hostFrame, "TOPLEFT", CludesUI.CONTENT_PAD, posY)

        local openBtn = CreateFrame("Button", nil, rowFrame)
        Pix.Size(openBtn, BTN_W, BTN_H)
        Pix.Point(openBtn, "RIGHT", rowFrame, "CENTER", -(GAP / 2), 0)
        openBtn:SetFrameLevel(rowFrame:GetFrameLevel() + 1)
        CludesUI.MakeStyledButton(openBtn, "Open Calculator", 14, CludesUI.WB_COLOURS, function()
            local widget = _G["CUIUpgCalcFrame"]
            if widget then
                if widget:IsShown() then
                    widget:Hide()
                else
                    widget:Show()
                end
            end
        end)

        local clearBtn = CreateFrame("Button", nil, rowFrame)
        Pix.Size(clearBtn, BTN_W, BTN_H)
        Pix.Point(clearBtn, "LEFT", rowFrame, "CENTER", GAP / 2, 0)
        clearBtn:SetFrameLevel(rowFrame:GetFrameLevel() + 1)
        CludesUI.MakeStyledButton(clearBtn, "Clear Upgrade Cache", 14, CludesUI.WB_COLOURS, function()
            if CUIUpgCalc and CUIUpgCalc.ClearCache then
                CUIUpgCalc:ClearCache()
            end
        end)

        posY = posY - ROW_H
    end

    -- Reposition hint
    do
        local fontFile = (CludesUI.GetFontPath()) or "Fonts\\FRIZQT__.TTF"
        local infoFrame = CreateFrame("Frame", nil, hostFrame)
        infoFrame:SetSize(hostFrame:GetWidth(), 20)
        infoFrame:SetPoint("TOP", hostFrame, "TOP", 0, posY - 10)
        infoFrame._isSpacer = true
        local line1 = infoFrame:CreateFontString(nil, "OVERLAY")
        line1:SetFont(fontFile, 15, "")
        line1:SetTextColor(1, 1, 1, 0.75)
        line1:SetPoint("TOP", infoFrame, "TOP", 0, 0)
        line1:SetJustifyH("CENTER")
        line1:SetText(CludesUI.L("Reposition this element with Shift+Click and Drag."))
        posY = posY - 36
    end

    ---------------------------------------------------------------------------
    --  DISPLAY
    ---------------------------------------------------------------------------
    _, hgt = W:SectionHeader(hostFrame, "DISPLAY", posY)
    posY = posY - hgt

    -- Row 1: Open with Character Sheet | Window Scale
    _, hgt = W:DualRow(hostFrame, posY, {
        type = "toggle",
        text = "Open with Character Sheet",
        tooltip = "Automatically opens and closes the Upgrade Calculator when the Character Sheet is opened or closed.",
        getValue = function()
            return GetAddonDB().openWithCharSheet or false
        end,
        setValue = function(val)
            GetAddonDB().openWithCharSheet = val
        end,
    }, {
        type = "slider",
        text = "Window Scale",
        min = 50,
        max = 150,
        step = 5,
        getValue = function()
            return GetAddonDB().uiScale or 100
        end,
        setValue = function(val)
            GetAddonDB().uiScale = val
            if CUIUpgCalc and CUIUpgCalc.ApplyScale then
                CUIUpgCalc.ApplyScale()
            end
        end,
    })
    posY = posY - hgt

    -- Row 2: Show Fully-Upgraded Items | Hide Crafted Items
    _, hgt = W:DualRow(hostFrame, posY, {
        type = "toggle",
        text = "Show Fully-Upgraded Items",
        tooltip = "Show gear tiles for items already at their maximum item level.",
        getValue = function()
            return GetAddonDB().showMaxed or false
        end,
        setValue = function(val)
            GetAddonDB().showMaxed = val
            LiveRefresh()
        end,
    }, {
        type = "toggle",
        text = "Hide Crafted Items",
        tooltip = "Hide crafted items from the gear tile list.\nCrafted items cannot be upgraded at the Upgrade NPC.",
        getValue = function()
            return GetAddonDB().hideCrafted or false
        end,
        setValue = function(val)
            GetAddonDB().hideCrafted = val
            LiveRefresh()
        end,
    })
    posY = posY - hgt

    -- Row 3: Slot Groups | Crest Rows
    local SLOT_GROUP_ITEMS = {
        { key = "Armour", label = "Armour" },
        { key = "Jewellery", label = "Jewelry" },
        { key = "Trinkets", label = "Trinkets" },
        { key = "Weapons", label = "Weapons" },
    }

    local CREST_TRACK_ITEMS = {
        { key = "Adventurer", label = "Adventurer" },
        { key = "Veteran", label = "Veteran" },
        { key = "Champion", label = "Champion" },
        { key = "Hero", label = "Hero" },
        { key = "Myth", label = "Myth" },
    }

    local filterRow, filterRowH = W:DualRow(hostFrame, posY, {
        type = "dropdown",
        text = "Slot Groups",
        values = { __placeholder = "..." },
        order = { "__placeholder" },
        getValue = function()
            return "__placeholder"
        end,
        setValue = function() end,
    }, {
        type = "dropdown",
        text = "Crest Rows",
        values = { __placeholder = "..." },
        order = { "__placeholder" },
        getValue = function()
            return "__placeholder"
        end,
        setValue = function() end,
    })
    if not CludesUI._prebuilding then
        local leftRgn = filterRow._leftRegion
        if leftRgn._control then
            leftRgn._control:Hide()
        end
        local cbDD, cbDDRefresh = CludesUI.BuildVisOptsCBDropdown(
            leftRgn,
            210,
            leftRgn:GetFrameLevel() + 2,
            SLOT_GROUP_ITEMS,
            function(k)
                local scrollFrame = GetAddonDB().slotFilter
                return scrollFrame == nil or scrollFrame[k] ~= false
            end,
            function(k, val)
                local saved = GetAddonDB()
                saved.slotFilter = saved.slotFilter or {}
                saved.slotFilter[k] = val
                LiveRefresh()
            end
        )
        Pix.Point(cbDD, "RIGHT", leftRgn, "RIGHT", -20, 0)
        leftRgn._control = cbDD
        leftRgn._lastInline = nil
        CludesUI.RegisterWidgetRefresh(cbDDRefresh)
    end
    if not CludesUI._prebuilding then
        local rightRgn = filterRow._rightRegion
        if rightRgn._control then
            rightRgn._control:Hide()
        end
        local cbDD, cbDDRefresh = CludesUI.BuildVisOptsCBDropdown(
            rightRgn,
            210,
            rightRgn:GetFrameLevel() + 2,
            CREST_TRACK_ITEMS,
            function(k)
                local castFrame = GetAddonDB().crestFilter
                return castFrame == nil or castFrame[k] ~= false
            end,
            function(k, val)
                local saved = GetAddonDB()
                saved.crestFilter = saved.crestFilter or {}
                saved.crestFilter[k] = val
                LiveRefresh()
            end
        )
        Pix.Point(cbDD, "RIGHT", rightRgn, "RIGHT", -20, 0)
        rightRgn._control = cbDD
        rightRgn._lastInline = nil
        CludesUI.RegisterWidgetRefresh(cbDDRefresh)
    end
    posY = posY - filterRowH

    -- Row 4: Show Earned/Cap Column | Show Still Available Column
    _, hgt = W:DualRow(hostFrame, posY, {
        type = "toggle",
        text = "Show Earned / Cap Column",
        tooltip = "Show the seasonal Earned / Cap column in the crest table.",
        getValue = function()
            return GetAddonDB().showEarnedCap or false
        end,
        setValue = function(val)
            GetAddonDB().showEarnedCap = val
            LiveRefresh()
        end,
    }, {
        type = "toggle",
        text = "Show Still Available Column",
        tooltip = "Show how many crests you can still earn before hitting the season cap (cap minus earned so far).",
        getValue = function()
            return GetAddonDB().showWeeklyRemaining or false
        end,
        setValue = function(val)
            GetAddonDB().showWeeklyRemaining = val
            LiveRefresh()
        end,
    })
    posY = posY - hgt

    -- Row 5: Show Calc Button on Character Sheet | Open with Crest Upgrader.
    -- The button is a tab on the CludesUI character sheet: gated while the
    -- sheet's Blizz Default (Window Skins card) keeps Blizzard's tab row.
    local calcBtnCfg = {
        type = "toggle",
        text = "Show Calc Button on Character Sheet",
        tooltip = "Adds a Calc toggle button to the character sheet that opens and closes the Upgrade Calculator.",
        getValue = function()
            return GetAddonDB().showCalcButton or false
        end,
        setValue = function(val)
            GetAddonDB().showCalcButton = val
            if CludesUI and CludesUI.ApplyCharSheetCalcTab then
                CludesUI.ApplyCharSheetCalcTab()
            end
        end,
    }
    local skinNS = CludesUI._ModuleNS and CludesUI._ModuleNS.CludesUIBlizzardSkin
    if skinNS and skinNS.CharSheetStock() then
        calcBtnCfg.disabled = function()
            return true
        end
        calcBtnCfg.disabledTooltip = "Character Sheet: Blizz Default"
        calcBtnCfg.requireState = "disabled"
    end
    _, hgt = W:DualRow(hostFrame, posY, calcBtnCfg, {
        type = "toggle",
        text = "Open with Crest Upgrader",
        tooltip = "Automatically opens the Upgrade Calculator when the Crest Upgrade NPC window is opened.",
        getValue = function()
            return GetAddonDB().openWithUpgrader or false
        end,
        setValue = function(val)
            GetAddonDB().openWithUpgrader = val
        end,
    })
    posY = posY - hgt

    _, hgt = W:SectionHeader(hostFrame, "TOOLTIPS", posY)
    posY = posY - hgt
    _, hgt = W:DualRow(hostFrame, posY, {
        type = "toggle",
        text = "Enhanced Upgrade Tooltips",
        tooltip = "Replaces the Upgrade Level line with a colored rank, track and potential item-level range, including Ascension for eligible weapons, trinkets and necklaces. Shows the upgrade currency beside it while upgrades remain. Unmatched tracks keep Blizzard's text.",
        getValue = function()
            return CludesUI.QoLExtrasGet("upgradeTooltips") == true
        end,
        setValue = function(val)
            CludesUI.QoLExtrasSet("upgradeTooltips", val)
            CludesUI._applyUpgradeTooltips()
        end,
    }, CludesUI.BlankRowCfg())
    posY = posY - hgt

    _, hgt = W:Spacer(hostFrame, posY, 20)
    posY = posY - hgt

    hostFrame:SetHeight(math.abs(posY - yOffset))

    return math.abs(posY)
end

-- Open/close-with-Character-Sheet hook lives in CUI_UpgradeCalc.lua (resident
-- runtime machinery; this file is LoadOnDemand).

-- Expose page builder for CUI_QoL_Options.lua
_G._CUI_BuildUpgradeCalcPage = BuildUpgradeCalcPage

-- Expose reset helper for QoL onReset
_G._CUI_ResetUpgradeCalc = function()
    CludesUI.QoLExtrasSet("upgradeTooltips", false)
    CludesUI._applyUpgradeTooltips()
    if CUIUpgCalc and CUIUpgCalc.GetOptsDB then
        local options = CUIUpgCalc.GetOptsDB()
        for k in pairs(options) do
            options[k] = nil
        end
    elseif CludesUIQoLDB then
        CludesUIQoLDB.upgradeCalcOpts = {}
    end
    if CUIUpgCalc and CUIUpgCalc.ClearCache then
        CUIUpgCalc:ClearCache()
    end
    -- Also wipe the persisted queue and crest manual-add offsets.
    if CUIUpgCalc and CUIUpgCalc.GetOptsDB then
        local saved = CUIUpgCalc.GetCalcDB and CUIUpgCalc.GetCalcDB()
        if saved then
            saved.queue = {}
            saved.crestManualAdds = {}
        end
    end
end
