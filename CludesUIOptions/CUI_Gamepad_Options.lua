if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
--------------------------------------------------------------------------------
--  CUI_Gamepad_Options.lua - Global Settings > Gamepad.
--
--  The settings that only matter while the player is on a controller
--  (CludesUI.PadModeOn: on retail a controller connected with WoW's gamepad
--  mode on; on WoW Forever its Gamepad interface style on, connected or not):
--  which action bars hide, and whether our two cast bars hide, since
--  Blizzard's gamepad interface draws its own.
--
--  The page owns no settings. Each value lives in its module's profile
--  (Action Bars bars[key].gamepadHideBar, Unit Frames
--  player.castbarGamepadHide, Resource Bars castBar.gamepadHide); the page
--  reads and writes them and asks the module to apply. Global Settings calls
--  the builder, so nothing is registered here.
--------------------------------------------------------------------------------

-- Frames made on an options page come from the page pool (CludesUI_FramePool.lua).
local CreateFrame = CludesUI._Pool.CreateFrame

local IS_FOREVER = CludesUI.IS_FOREVER == true

-- Two wordings for the same sentence: retail talks about a connected
-- controller, WoW Forever about its gamepad interface. Both are full strings
-- so each keeps its own locale entry.
local function Wording(retail, forever)
    if IS_FOREVER then return forever end
    return retail
end

--------------------------------------------------------------------------------
--  Where the settings live (each nil while its module is not loaded)
--------------------------------------------------------------------------------
local function ActionBars()
    local mod = CludesUI.ModuleNS("CludesUIActionBars")
    if mod and mod.EAB and mod.EAB.db then return mod end
    return nil
end

local function UnitFrames() return CludesUI.ModuleNS("CludesUIUnitFrames") end

local function PlayerFrameSettings()
    local mod = UnitFrames()
    return mod and mod.db and mod.db.profile.player
end

local function CastBarSettings()
    if not CludesUI.ModuleNS("CludesUIResourceBars") then return nil end
    local db = _G._CURB_AceDB
    return db and db.profile.castBar
end

--------------------------------------------------------------------------------
--  Action bars to hide
--------------------------------------------------------------------------------
-- The bars that can take the setting, in the Action Bars dropdown order. The
-- visibility-only entries (Micro Menu, Bag Bar, data bars) never hide this way.
local function HideableBars(mod)
    local list = {}
    for _, key in ipairs(mod.BAR_DROPDOWN_ORDER) do
        if not mod.VISIBILITY_ONLY[key] then
            list[#list + 1] = { key = key, label = mod.BAR_DROPDOWN_VALUES[key] or key }
        end
    end
    return list
end

local function BarSettings(key)
    local mod = ActionBars()
    return mod and mod.EAB.db.profile.bars[key]
end

local function IsBarHidden(key)
    local bar = BarSettings(key)
    return bar ~= nil and bar.gamepadHideBar == true
end

local function SetBarHidden(key, hide)
    local bar = BarSettings(key)
    if not bar then return end
    bar.gamepadHideBar = hide and true or false
    local EAB = ActionBars().EAB
    -- The controller verdict goes first: the Never map and the drivers read it.
    EAB._PadSync()
    EAB:RefreshRuntimeVisibility()
end

--------------------------------------------------------------------------------
--  Cast bars to hide
--------------------------------------------------------------------------------
local CAST_BARS = {
    {
        text = "Hide Unit Frames Cast Bar",
        tooltip = Wording(
            "Hides the Unit Frames player cast bar while a controller is connected and gamepad mode is on. Blizzard's gamepad interface shows its own.",
            "Hides the Unit Frames player cast bar while WoW's gamepad interface is on. Blizzard's gamepad interface shows its own."
        ),
        settings = PlayerFrameSettings,
        key = "castbarGamepadHide",
        apply = function() UnitFrames().UF_ApplyGamepadCastbar() end,
        -- Only the CludesUI player frame has our cast bar; a Blizzard or
        -- hidden frame source has nothing to hide.
        disabled = function(player)
            if not (player and player.showPlayerCastbar) then return true end
            return UnitFrames().GetUnitFrameSource("player") ~= "cui"
        end,
        moduleName = "Unit Frames",
        needs = "This option requires the Unit Frames player frame and its cast bar to be enabled",
    },
    {
        text = "Hide Resource Bars Cast Bar",
        tooltip = Wording(
            "Hides the Resource & Cast Bars cast bar while a controller is connected and gamepad mode is on. Blizzard's gamepad interface shows its own.",
            "Hides the Resource & Cast Bars cast bar while WoW's gamepad interface is on. Blizzard's gamepad interface shows its own."
        ),
        settings = CastBarSettings,
        key = "gamepadHide",
        apply = function() CludesUI.ModuleNS("CludesUIResourceBars").RB_ApplyGamepadCastbar() end,
        disabled = function(castBar) return not (castBar and castBar.enabled) end,
        moduleName = "Resource & Cast Bars",
        needs = "This option requires the cast bar in Resource & Cast Bars to be enabled",
    },
}

-- One cast bar entry as a toggle row half.
local function CastBarToggle(entry)
    return {
        type = "toggle",
        text = entry.text,
        tooltip = entry.tooltip,
        getValue = function()
            local saved = entry.settings()
            return saved ~= nil and saved[entry.key] == true
        end,
        setValue = function(on)
            local saved = entry.settings()
            if not saved then return end
            saved[entry.key] = on and true or false
            entry.apply()
        end,
        disabled = function() return entry.disabled(entry.settings()) end,
        -- While the module is not loaded the tooltip names it; once it is,
        -- it says what has to be turned on first.
        disabledTooltip = function()
            if not entry.settings() then return entry.moduleName end
            return entry.needs
        end,
    }
end

--------------------------------------------------------------------------------
--  The page
--------------------------------------------------------------------------------
local INTRO = {
    Wording(
        "Everything here applies only while a controller is connected and WoW's gamepad mode is on.",
        "Everything here applies only while WoW's gamepad interface is turned on in its Gamepad settings."
    ),
    Wording(
        "Mouse and keyboard play is unaffected.",
        "Keyboard and mouse play is unaffected, even with a controller connected."
    ),
}

-- The checklist note's row height (CludesUI.BuildNoteRow).
local NOTE_ROW_H = 34

-- The intro: chrome only, so the search index pass (which builds the page
-- with CludesUI._prebuilding set) skips it but still steps past its space.
-- A sized host with one TOPLEFT point, as the search geometry expects.
local function BuildIntro(hostFrame, cursorY)
    if CludesUI._prebuilding then return end
    local PP = CludesUI.PanelPP
    local pad = CludesUI.CONTENT_PAD
    local host = CreateFrame("Frame", nil, hostFrame)
    PP.Size(host, hostFrame:GetWidth() - pad * 2, 44)
    PP.Point(host, "TOPLEFT", hostFrame, "TOPLEFT", pad, cursorY - 20)
    local text = CludesUI.MakeFont(host, 14, nil, 1, 1, 1, 0.65)
    text:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -2)
    text:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, -2)
    text:SetJustifyH("CENTER")
    text:SetWordWrap(true)
    text:SetText(CludesUI.L(INTRO[1]) .. "\n" .. CludesUI.L(INTRO[2]))
end

-- Swaps the row's stand-in dropdown for the checklist of bars, and adds the
-- note under it. Returns the new y.
local function BuildBarChecklist(hostFrame, row, cursorY, mod)
    local region = row._leftRegion
    if region._control then region._control:Hide() end
    local list, refresh = CludesUI.BuildVisOptsCBDropdown(
        region,
        210,
        region:GetFrameLevel() + 2,
        HideableBars(mod),
        IsBarHidden,
        SetBarHidden
    )
    CludesUI.PanelPP.Point(list, "RIGHT", region, "RIGHT", -20, 0)
    region._control = list
    region._lastInline = nil
    CludesUI.RegisterWidgetRefresh(refresh)
    -- Chrome only (no search entry).
    return CludesUI.BuildNoteRow(
        hostFrame,
        cursorY,
        "Hidden bars still show in Quick Keybind mode so you can bind them."
    )
end

-- Builds the page into hostFrame from yOffset down; returns its height.
function _G._CUI_BuildGamepadPage(page, hostFrame, yOffset)
    local W = CludesUI.Widgets
    local cursorY = yOffset
    local _, row, height

    hostFrame._showRowDivider = true

    BuildIntro(hostFrame, cursorY)
    cursorY = cursorY - 48

    -- Action bars. The row is built as a stand-in dropdown (rows only build
    -- plain widgets) so it carries the label, the tooltip and the disabled
    -- state while Action Bars is not loaded; with it loaded, the checklist
    -- takes the dropdown's place.
    _, height = W:SectionHeader(hostFrame, "ACTION BARS", cursorY)
    cursorY = cursorY - height

    local actionBars = ActionBars()
    row, height = W:DualRow(hostFrame, cursorY, {
        type = "dropdown",
        text = "Hide Action Bars",
        tooltip = Wording(
            "Checked bars hide while a controller is connected and gamepad mode is on, the way Visibility set to Never hides them.",
            "Checked bars hide while WoW's gamepad interface is on, the way Visibility set to Never hides them."
        ),
        values = { __placeholder = "..." },
        order = { "__placeholder" },
        getValue = function() return "__placeholder" end,
        setValue = function() end,
        disabled = function() return not ActionBars() end,
        disabledTooltip = "Action Bars",
    }, CludesUI.BlankRowCfg())
    cursorY = cursorY - height

    if actionBars then
        if CludesUI._prebuilding then
            -- The index pass steps past the note so the rows below index
            -- where they really sit.
            cursorY = cursorY - NOTE_ROW_H
        else
            cursorY = BuildBarChecklist(hostFrame, row, cursorY, actionBars)
        end
    end

    _, height = W:Spacer(hostFrame, cursorY, 20)
    cursorY = cursorY - height

    -- Cast bars.
    _, height = W:SectionHeader(hostFrame, "CAST BARS", cursorY)
    cursorY = cursorY - height

    _, height = W:DualRow(hostFrame, cursorY, CastBarToggle(CAST_BARS[1]), CastBarToggle(CAST_BARS[2]))
    cursorY = cursorY - height

    -- The page framework takes the content height as a positive number.
    return math.abs(cursorY)
end
