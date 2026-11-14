if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_Gamepad_Options.lua -- Global Settings > Gamepad. The settings that
--  apply only while a controller is connected and WoW's gamepad mode is on
--  (on WoW Forever: while its Gamepad interface style is on, connected or not;
--  CludesUI.PadModeOn): which action bars hide, and whether our cast bars
--  hide (Blizzard's gamepad interface draws its own cast bar). Every value lives in its module's
--  profile (Action Bars bars[key].gamepadHideBar, Unit Frames
--  player.castbarGamepadHide, Resource Bars castBar.gamepadHide); this page
--  only reads and writes them and calls the module's apply entry. It
--  registers nothing: the Global Settings module dispatches its builder.
-------------------------------------------------------------------------------

local AB_FOLDER = "CludesUIActionBars"
local UF_FOLDER = "CludesUIUnitFrames"
local RB_FOLDER = "CludesUIResourceBars"

-- Options page pool (CludesUI_FramePool.lua): frames made here on a pool
-- host are reset and dressed again by the next build instead of made anew;
-- elsewhere this is CreateFrame.
local CreateFrame = CludesUI._Pool.CreateFrame

-------------------------------------------------------------------------------
--  Module access (nil while a module is not loaded)
-------------------------------------------------------------------------------

-- Action Bars module ns once its profile exists.
local function ABNS()
    local mod = CludesUI.ModuleNS(AB_FOLDER)
    local ABAR = mod and mod.EAB
    if ABAR and ABAR.db then
        return mod
    end
    return nil
end

-- Unit Frames player unit settings.
local function UFPlayer()
    local mod = CludesUI.ModuleNS(UF_FOLDER)
    local saved = mod and mod.db
    return saved and saved.profile.player
end

-- Resource Bars cast bar settings.
local function RBCast()
    if not CludesUI.ModuleNS(RB_FOLDER) then
        return nil
    end
    local saved = _G._CURB_AceDB
    return saved and saved.profile.castBar
end

-------------------------------------------------------------------------------
--  Action bars checklist
-------------------------------------------------------------------------------

-- Every bar the runtime can hide, in the Action Bars dropdown order (the
-- visibility-only entries, such as the Micro Menu, Bag Bar and data bars,
-- never take the setting).
local function BarItems(mod)
    local itemList = {}
    local sequence, labels, visOnly = mod.BAR_DROPDOWN_ORDER, mod.BAR_DROPDOWN_VALUES, mod.VISIBILITY_ONLY
    for idx = 1, #sequence do
        local key = sequence[idx]
        if not visOnly[key] then
            itemList[#itemList + 1] = { key = key, label = labels[key] or key }
        end
    end
    return itemList
end

local function BarSettings(key)
    local mod = ABNS()
    return mod and mod.EAB.db.profile.bars[key]
end

local function BarHidden(key)
    local s = BarSettings(key)
    return (s and s.gamepadHideBar == true) or false
end

local function SetBarHidden(key, val)
    local s = BarSettings(key)
    if not s then
        return
    end
    s.gamepadHideBar = val and true or false
    local ABAR = ABNS().EAB
    -- Controller verdict first: the Never map and the drivers read it.
    ABAR._PadSync()
    ABAR:RefreshRuntimeVisibility()
end

-------------------------------------------------------------------------------
--  Page builder (dispatched from the Global Settings module registration)
-------------------------------------------------------------------------------
function _G._CUI_BuildGamepadPage(page, hostFrame, yOffset)
    local W = CludesUI.Widgets
    local Pix = CludesUI.PanelPP
    local BLANK = CludesUI.BlankRowCfg
    local posY = yOffset
    local _, hgt
    -- WoW Forever: the page follows its Gamepad interface style, not a connected controller.
    local FV = CludesUI.IS_FOREVER == true

    hostFrame._showRowDivider = true

    -- Intro: sized host + single TOPLEFT point (the search geometry
    -- contract). Chrome only, so the search index pass skips it.
    if not CludesUI._prebuilding then
        local introHost = CreateFrame("Frame", nil, hostFrame)
        Pix.Size(introHost, hostFrame:GetWidth() - CludesUI.CONTENT_PAD * 2, 44)
        Pix.Point(introHost, "TOPLEFT", hostFrame, "TOPLEFT", CludesUI.CONTENT_PAD, posY - 20)
        local intro = CludesUI.MakeFont(introHost, 14, nil, 1, 1, 1, 0.65)
        intro:SetPoint("TOPLEFT", introHost, "TOPLEFT", 0, -2)
        intro:SetPoint("TOPRIGHT", introHost, "TOPRIGHT", 0, -2)
        intro:SetJustifyH("CENTER")
        intro:SetWordWrap(true)
        if FV then
            intro:SetText(
                CludesUI.L(
                    "Everything here applies only while WoW's gamepad interface is turned on in its Gamepad settings."
                )
                    .. "\n"
                    .. CludesUI.L("Keyboard and mouse play is unaffected, even with a controller connected.")
            )
        else
            intro:SetText(
                CludesUI.L(
                    "Everything here applies only while a controller is connected and WoW's gamepad mode is on."
                )
                    .. "\n"
                    .. CludesUI.L("Mouse and keyboard play is unaffected.")
            )
        end
    end
    posY = posY - 48

    ---------------------------------------------------------------------------
    --  ACTION BARS
    ---------------------------------------------------------------------------
    _, hgt = W:SectionHeader(hostFrame, "ACTION BARS", posY)
    posY = posY - hgt

    local abNS = ABNS()
    -- The checklist replaces this placeholder dropdown (DualRow only builds
    -- plain widgets); the placeholder keeps the label, its tooltip and the
    -- disabled state while Action Bars is not loaded.
    local barRow
    barRow, hgt = W:DualRow(hostFrame, posY, {
        type = "dropdown",
        text = "Hide Action Bars",
        tooltip = FV
                and "Checked bars hide while WoW's gamepad interface is on, the way Visibility set to Never hides them."
            or "Checked bars hide while a controller is connected and gamepad mode is on, the way Visibility set to Never hides them.",
        values = { __placeholder = "..." },
        order = { "__placeholder" },
        getValue = function()
            return "__placeholder"
        end,
        setValue = function() end,
        disabled = function()
            return not ABNS()
        end,
        disabledTooltip = "Action Bars",
    }, BLANK())
    posY = posY - hgt

    if abNS and not CludesUI._prebuilding then
        local region = barRow._leftRegion
        if region._control then
            region._control:Hide()
        end
        local cbDD, cbDDRefresh = CludesUI.BuildVisOptsCBDropdown(
            region,
            210,
            region:GetFrameLevel() + 2,
            BarItems(abNS),
            BarHidden,
            SetBarHidden
        )
        Pix.Point(cbDD, "RIGHT", region, "RIGHT", -20, 0)
        region._control = cbDD
        region._lastInline = nil
        CludesUI.RegisterWidgetRefresh(cbDDRefresh)

        -- Chrome only (no search entry), so the index pass skips it too.
        posY = CludesUI.BuildNoteRow(
            hostFrame,
            posY,
            "Hidden bars still show in Quick Keybind mode so you can bind them."
        )
    elseif abNS then
        -- The index pass still steps past the note (BuildNoteRow's 34px row)
        -- so the rows below index at their live positions.
        posY = posY - 34
    end

    _, hgt = W:Spacer(hostFrame, posY, 20)
    posY = posY - hgt

    ---------------------------------------------------------------------------
    --  CAST BARS
    ---------------------------------------------------------------------------
    _, hgt = W:SectionHeader(hostFrame, "CAST BARS", posY)
    posY = posY - hgt

    _, hgt = W:DualRow(hostFrame, posY, {
        type = "toggle",
        text = "Hide Unit Frames Cast Bar",
        tooltip = FV
                and "Hides the Unit Frames player cast bar while WoW's gamepad interface is on. Blizzard's gamepad interface shows its own."
            or "Hides the Unit Frames player cast bar while a controller is connected and gamepad mode is on. Blizzard's gamepad interface shows its own.",
        getValue = function()
            local p = UFPlayer()
            return (p and p.castbarGamepadHide == true) or false
        end,
        setValue = function(val)
            local p = UFPlayer()
            if not p then
                return
            end
            p.castbarGamepadHide = val and true or false
            CludesUI.ModuleNS(UF_FOLDER).UF_ApplyGamepadCastbar()
        end,
        -- Our player cast bar exists only on the CludesUI player frame
        -- (a Blizzard or hidden frame source has none to hide).
        disabled = function()
            local p = UFPlayer()
            if not (p and p.showPlayerCastbar) then
                return true
            end
            return CludesUI.ModuleNS(UF_FOLDER).GetUnitFrameSource("player") ~= "cui"
        end,
        disabledTooltip = function()
            if not UFPlayer() then
                return "Unit Frames"
            end
            return "This option requires the Unit Frames player frame and its cast bar to be enabled"
        end,
    }, {
        type = "toggle",
        text = "Hide Resource Bars Cast Bar",
        tooltip = FV
                and "Hides the Resource & Cast Bars cast bar while WoW's gamepad interface is on. Blizzard's gamepad interface shows its own."
            or "Hides the Resource & Cast Bars cast bar while a controller is connected and gamepad mode is on. Blizzard's gamepad interface shows its own.",
        getValue = function()
            local cb = RBCast()
            return (cb and cb.gamepadHide == true) or false
        end,
        setValue = function(val)
            local cb = RBCast()
            if not cb then
                return
            end
            cb.gamepadHide = val and true or false
            CludesUI.ModuleNS(RB_FOLDER).RB_ApplyGamepadCastbar()
        end,
        disabled = function()
            local cb = RBCast()
            return not (cb and cb.enabled)
        end,
        disabledTooltip = function()
            if not RBCast() then
                return "Resource & Cast Bars"
            end
            return "This option requires the cast bar in Resource & Cast Bars to be enabled"
        end,
    })
    posY = posY - hgt

    -- Framework contract: return the positive total content height.
    return math.abs(posY)
end
