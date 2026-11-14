if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_QoL_MovementAlert_Options.lua
--  Options page for Movement Alert (registered as a page under the
--  CludesUIQoL module by CUI_QoL_Options.lua). Builds four sections:
--    MOVEMENT COOLDOWN ALERT, TRACKED SPELLS, TIME SPIRAL, GATEWAY SHARD.
--  Position/size for all three on-screen trackers is controlled entirely
--  through CUI's Unlock Mode (registered in CludesUIQoL_MovementAlert.lua)
--  rather than in-page sliders, matching how Combat Alert/BattleRes work.
-------------------------------------------------------------------------------

if not CludesUI._ModuleNS["CludesUIQoL"] then
    return
end -- module disabled: no options page

-- Page reuse: frames this file builds go through the options frame pool
-- (CludesUI_FramePool.lua), which hands a kept page its previous build's
-- frames back reset to new; on any other parent it is the plain CreateFrame.
local CreateFrame = CludesUI._Pool.CreateFrame

local function SavedDB()
    local func = _G._CUI_MovementAlert_DB
    return func and func() or nil
end

local function MA()
    local d = SavedDB()
    return d and d.profile and d.profile.movementAlert
end

local function Refresh()
    if CludesUI._applyMovementAlert then
        CludesUI._applyMovementAlert()
    end
    if CludesUI._applyTimeSpiral then
        CludesUI._applyTimeSpiral()
    end
    if CludesUI._applyGateway then
        CludesUI._applyGateway()
    end
    if CludesUI._UpdateMovementAlertEvents then
        CludesUI._UpdateMovementAlertEvents()
    end
    if CludesUI._CheckMovementCooldown then
        CludesUI._CheckMovementCooldown()
    end
    if CludesUI._CheckGatewayUsable then
        CludesUI._CheckGatewayUsable()
    end
end

-- The legacy stored "text" value displays and renders as text_dn (its old
-- duration-first default format) -- no migration, the getter maps it.
local DISPLAY_MODE_VALUES = {
    text_nd = "Text: Name Duration",
    text_dn = "Text: Duration Name",
    text_d = "Text: Duration",
    icon = "Icon",
    bar = "Bar",
}
local DISPLAY_MODE_ORDER = { "text_nd", "text_dn", "text_d", "icon", "bar" }

-- One-shot guard: the options-close hook that kills the movement preview is
-- registered on first page build, never per rebuild.
local _previewOnHideRegistered = false

local CLASS_ORDER = {
    "DEATHKNIGHT",
    "DEMONHUNTER",
    "DRUID",
    "EVOKER",
    "HUNTER",
    "MAGE",
    "MONK",
    "PALADIN",
    "PRIEST",
    "ROGUE",
    "SHAMAN",
    "WARLOCK",
    "WARRIOR",
}

-- Preset tracked spells for the checkbox grid: the castable mobility ids the tracker
-- (CludesUIQoL_MovementAlert.lua MOVEMENT_ABILITIES) actually polls, across ALL
-- classes/specs, curated against the raid-frame Buff Manager movement filter
-- (CludesUIRaidFrames\CUI_RaidFrames_BuffManager2.lua,
-- DEFAULT_FILTER_SPELLS.movement) for class coverage and alternate ids -- keep the
-- three tables in sync when mobility spells change. ids[1] is the primary (label +
-- checkbox state source); the rest are CASTABLE variant ids the tracker also polls
-- (talent replacements, form casts) whose override state follows the primary's checkbox
-- -- never aura-only ids, which the tracker cannot poll. Ids are never displayed; names
-- resolve live via GetSpellInfo.
local MOVEMENT_PRESETS = {
    { class = "DEATHKNIGHT", ids = { 48265 } }, -- Death's Advance
    { class = "DEATHKNIGHT", ids = { 212552 } }, -- Wraith Walk
    { class = "DEATHKNIGHT", ids = { 444347, 444010 } }, -- Death Charge (both ids share the name)
    { class = "DEMONHUNTER", ids = { 195072 } }, -- Fel Rush
    { class = "DEMONHUNTER", ids = { 189110 } }, -- Infernal Strike
    { class = "DEMONHUNTER", ids = { 1234796 } },
    { class = "DRUID", ids = { 102401, 102417 } }, -- Wild Charge
    { class = "DRUID", ids = { 1850 } }, -- Dash
    { class = "DRUID", ids = { 252216 } }, -- Tiger Dash
    { class = "DRUID", ids = { 106898, 77761, 77764 } }, -- Stampeding Roar (base + bear/cat form casts)
    { class = "EVOKER", ids = { 358267 } }, -- Hover
    { class = "HUNTER", ids = { 186257 } }, -- Aspect of the Cheetah
    { class = "HUNTER", ids = { 781 } }, -- Disengage
    { class = "MAGE", ids = { 1953, 212653 } }, -- Blink / Shimmer
    { class = "MONK", ids = { 109132, 115008 } }, -- Roll / Chi Torpedo
    { class = "MONK", ids = { 119085 } },
    { class = "MONK", ids = { 361138 } },
    { class = "MONK", ids = { 101545 } }, -- Flying Serpent Kick
    { class = "PALADIN", ids = { 190784 } }, -- Divine Steed
    { class = "PRIEST", ids = { 121536 } }, -- Angelic Feather
    { class = "PRIEST", ids = { 73325 } }, -- Leap of Faith
    { class = "ROGUE", ids = { 2983 } }, -- Sprint
    { class = "ROGUE", ids = { 36554 } }, -- Shadowstep
    { class = "ROGUE", ids = { 195457 } }, -- Grappling Hook
    { class = "SHAMAN", ids = { 79206 } }, -- Spiritwalker's Grace
    { class = "SHAMAN", ids = { 192063 } }, -- Gust of Wind
    { class = "SHAMAN", ids = { 58875, 90328 } }, -- Spirit Walk
    { class = "WARLOCK", ids = { 48020 } }, -- Demonic Circle: Teleport
    { class = "WARLOCK", ids = { 111400 } }, -- Burning Rush (buff-active, ships unchecked)
    { class = "WARRIOR", ids = { 6544 } }, -- Heroic Leap
}

-- Set of every preset id (all variants): any other id in ma.spellOverrides
-- is a user-added custom spell and gets its own deletable grid cell.
local MOVEMENT_PRESET_IDS = {}
for _, e in ipairs(MOVEMENT_PRESETS) do
    for _, ident in ipairs(e.ids) do
        MOVEMENT_PRESET_IDS[ident] = true
    end
end

-- Presets that default to unchecked (backend-owned set, shared so the grid
-- and the tracker read the same truth).
local MOVEMENT_DEFAULT_OFF = CludesUI._MovementDefaultOff or {}

-- Voices are enumerated live from C_VoiceChat rather than a static list --
-- availability varies by client/OS. Falls back to a single "Default" entry
-- (voiceID 0) if the API or voice list isn't available.
local function TTSVoiceDropdownValues()
    local values, sequence = { [0] = "Default" }, { 0 }
    if C_VoiceChat and C_VoiceChat.GetTtsVoices then
        local success, voices = pcall(C_VoiceChat.GetTtsVoices)
        if success and voices then
            for _, voice in ipairs(voices) do
                if voice.voiceID and voice.voiceID ~= 0 and voice.name then
                    values[voice.voiceID] = voice.name
                    sequence[#sequence + 1] = voice.voiceID
                end
            end
        end
    end
    values._menuOpts = {
        itemHeight = 26,
        maxTextWidthPct = 0.8,
        iconAtlas = function()
            return CludesUI.SOUND_ICON_ATLAS
        end,
        iconPressedAtlas = function()
            return CludesUI.SOUND_ICON_PRESSED_ATLAS
        end,
        iconOnClick = function(key)
            if C_VoiceChat and C_VoiceChat.SpeakText then
                pcall(C_VoiceChat.SpeakText, key, "This is a voice preview", 1, 100, true)
            end
        end,
        iconTooltip = function()
            return "Preview Voice"
        end,
    }
    return values, sequence
end

-------------------------------------------------------------------------------
--  "Add Spell" popup -- small modal for adding a custom tracked spell by ID,
--  styled after the CDM "Custom Buff ID" popup
--  (CludesUICooldownManager\CUI_CooldownManager_Options.lua).
-------------------------------------------------------------------------------
local addSpellPopup
local function ShowAddSpellPopup(onAdded)
    local Pix = CludesUI.PanelPP
    local FONT = CludesUI._font or "Interface\\AddOns\\CludesUI\\media\\fonts\\Expressway.TTF"

    if not addSpellPopup then
        local dimmer = CreateFrame("Frame", nil, UIParent)
        dimmer:SetFrameStrata("FULLSCREEN_DIALOG")
        dimmer:SetAllPoints(UIParent)
        dimmer:EnableMouse(true)
        dimmer:Hide()
        local dimTex = dimmer:CreateTexture(nil, "BACKGROUND")
        dimTex:SetAllPoints()
        dimTex:SetColorTexture(0, 0, 0, 0.25)

        local dialog = CreateFrame("Frame", nil, dimmer)
        dialog:SetSize(240, 150)
        dialog:SetPoint("CENTER", CludesUI._mainFrame or UIParent, "CENTER", 0, 60)
        dialog:SetFrameStrata("FULLSCREEN_DIALOG")
        dialog:SetFrameLevel(dimmer:GetFrameLevel() + 10)
        dialog:EnableMouse(true)
        local backdrop = dialog:CreateTexture(nil, "BACKGROUND")
        backdrop:SetAllPoints()
        backdrop:SetColorTexture(0.062, 0.070, 0.082, 1)
        CludesUI.MakeRoundedBorder(dialog, 1, 1, 1, 0.15, backdrop)

        local title = dialog:CreateFontString(nil, "OVERLAY")
        title:SetFont(FONT, 14, "")
        title:SetPoint("TOP", dialog, "TOP", 0, -18)
        title:SetTextColor(1, 1, 1, 1)
        title:SetText(CludesUI.L("Add Spell"))

        local sidLbl = dialog:CreateFontString(nil, "OVERLAY")
        sidLbl:SetFont(FONT, 11, "")
        sidLbl:SetPoint("TOPLEFT", dialog, "TOPLEFT", 24, -52)
        sidLbl:SetTextColor(0.7, 0.7, 0.7, 1)
        sidLbl:SetText(CludesUI.L("Spell ID"))

        local sidBox = CreateFrame("EditBox", nil, dialog)
        sidBox:SetSize(192, 28)
        sidBox:SetPoint("TOPLEFT", sidLbl, "BOTTOMLEFT", 0, -4)
        sidBox:SetAutoFocus(false)
        sidBox:SetNumeric(true)
        sidBox:SetMaxLetters(7)
        sidBox:SetFont(FONT, 13, "")
        sidBox:SetTextColor(1, 1, 1, 0.9)
        sidBox:SetJustifyH("LEFT")
        sidBox:SetTextInsets(6, 6, 0, 0)
        local sidBg = sidBox:CreateTexture(nil, "BACKGROUND")
        sidBg:SetAllPoints()
        sidBg:SetColorTexture(0.060, 0.049, 0.037, 1)
        CludesUI.MakeRoundedBorder(sidBox, 1, 1, 1, 0.12, sidBg)
        dialog._sidBox = sidBox

        local status = dialog:CreateFontString(nil, "OVERLAY")
        status:SetFont(FONT, 11, "")
        status:SetPoint("TOP", sidBox, "BOTTOM", 0, -8)
        status:SetTextColor(1, 0.3, 0.3, 1)
        dialog._status = status

        local ar, ag, ab = CludesUI.GetAccentColor()
        local addBtn = CreateFrame("Button", nil, dialog)
        addBtn:SetSize(80, 26)
        addBtn:SetPoint("BOTTOM", dialog, "BOTTOM", 0, 16)
        local addBg = addBtn:CreateTexture(nil, "BACKGROUND")
        addBg:SetAllPoints()
        addBg:SetColorTexture(ar, ag, ab, 0.15)
        CludesUI.MakeRoundedBorder(addBtn, ar, ag, ab, 0.4, addBg)
        local addLbl = addBtn:CreateFontString(nil, "OVERLAY")
        addLbl:SetFont(FONT, 12, "")
        addLbl:SetPoint("CENTER")
        addLbl:SetTextColor(ar, ag, ab, 1)
        addLbl:SetText(CludesUI.L("Add"))

        local function TryAdd()
            local ident = tonumber(sidBox:GetText())
            if not ident or ident <= 0 then
                dialog._status:SetText(CludesUI.L("Enter a valid spell ID"))
                return
            end
            sidBox:SetText("")
            dimmer:Hide()
            if dialog._onAdded then
                dialog._onAdded(ident)
            end
        end
        addBtn:SetScript("OnClick", TryAdd)
        sidBox:SetScript("OnEnterPressed", TryAdd)
        sidBox:SetScript("OnEscapePressed", function(self)
            self:ClearFocus()
        end)

        dimmer:SetScript("OnMouseDown", function(self)
            if not dialog:IsMouseOver() then
                self:Hide()
            end
        end)

        dialog._dimmer = dimmer
        addSpellPopup = dialog
    end

    addSpellPopup._status:SetText("")
    addSpellPopup._sidBox:SetText("")
    addSpellPopup._onAdded = onAdded
    addSpellPopup._dimmer:Show()
    addSpellPopup._sidBox:SetFocus()
end

-------------------------------------------------------------------------------
--  "Custom Text" popup -- right-click on a tracked-spell grid cell. Sets the
--  text the Movement Cooldown Alert shows for that spell instead of the
--  ability name; empty text restores the ability name. Same styling as the
--  Add Spell popup above.
-------------------------------------------------------------------------------
local customTextPopup
local function ShowCustomTextPopup(titleText, initial, onSave)
    local Pix = CludesUI.PanelPP
    local FONT = CludesUI._font or "Interface\\AddOns\\CludesUI\\media\\fonts\\Expressway.TTF"

    if not customTextPopup then
        local dimmer = CreateFrame("Frame", nil, UIParent)
        dimmer:SetFrameStrata("FULLSCREEN_DIALOG")
        dimmer:SetAllPoints(UIParent)
        dimmer:EnableMouse(true)
        dimmer:Hide()
        local dimTex = dimmer:CreateTexture(nil, "BACKGROUND")
        dimTex:SetAllPoints()
        dimTex:SetColorTexture(0, 0, 0, 0.25)

        local dialog = CreateFrame("Frame", nil, dimmer)
        dialog:SetSize(260, 150)
        dialog:SetPoint("CENTER", CludesUI._mainFrame or UIParent, "CENTER", 0, 60)
        dialog:SetFrameStrata("FULLSCREEN_DIALOG")
        dialog:SetFrameLevel(dimmer:GetFrameLevel() + 10)
        dialog:EnableMouse(true)
        local backdrop = dialog:CreateTexture(nil, "BACKGROUND")
        backdrop:SetAllPoints()
        backdrop:SetColorTexture(0.062, 0.070, 0.082, 1)
        CludesUI.MakeRoundedBorder(dialog, 1, 1, 1, 0.15, backdrop)

        local title = dialog:CreateFontString(nil, "OVERLAY")
        title:SetFont(FONT, 14, "")
        title:SetPoint("TOP", dialog, "TOP", 0, -18)
        title:SetTextColor(1, 1, 1, 1)
        dialog._title = title

        local labelFS = dialog:CreateFontString(nil, "OVERLAY")
        labelFS:SetFont(FONT, 11, "")
        labelFS:SetPoint("TOPLEFT", dialog, "TOPLEFT", 24, -52)
        labelFS:SetTextColor(0.7, 0.7, 0.7, 1)
        labelFS:SetText(CludesUI.L("Custom Alert Text (empty = ability name)"))

        local boxFrame = CreateFrame("EditBox", nil, dialog)
        boxFrame:SetSize(212, 28)
        boxFrame:SetPoint("TOPLEFT", labelFS, "BOTTOMLEFT", 0, -4)
        boxFrame:SetAutoFocus(false)
        boxFrame:SetMaxLetters(40)
        boxFrame:SetFont(FONT, 13, "")
        boxFrame:SetTextColor(1, 1, 1, 0.9)
        boxFrame:SetJustifyH("LEFT")
        boxFrame:SetTextInsets(6, 6, 0, 0)
        local boxBg = boxFrame:CreateTexture(nil, "BACKGROUND")
        boxBg:SetAllPoints()
        boxBg:SetColorTexture(0.060, 0.049, 0.037, 1)
        CludesUI.MakeRoundedBorder(boxFrame, 1, 1, 1, 0.12, boxBg)
        dialog._box = boxFrame

        local ar, ag, ab = CludesUI.GetAccentColor()
        local saveBtn = CreateFrame("Button", nil, dialog)
        saveBtn:SetSize(80, 26)
        saveBtn:SetPoint("BOTTOM", dialog, "BOTTOM", 0, 16)
        local saveBg = saveBtn:CreateTexture(nil, "BACKGROUND")
        saveBg:SetAllPoints()
        saveBg:SetColorTexture(ar, ag, ab, 0.15)
        CludesUI.MakeRoundedBorder(saveBtn, ar, ag, ab, 0.4, saveBg)
        local saveLbl = saveBtn:CreateFontString(nil, "OVERLAY")
        saveLbl:SetFont(FONT, 12, "")
        saveLbl:SetPoint("CENTER")
        saveLbl:SetTextColor(ar, ag, ab, 1)
        saveLbl:SetText(CludesUI.L("Save"))

        local function Commit()
            dimmer:Hide()
            if dialog._onSave then
                dialog._onSave(dialog._box:GetText() or "")
            end
        end
        saveBtn:SetScript("OnClick", Commit)
        boxFrame:SetScript("OnEnterPressed", Commit)
        boxFrame:SetScript("OnEscapePressed", function()
            dimmer:Hide()
        end)

        dimmer:SetScript("OnMouseDown", function(self)
            if not dialog:IsMouseOver() then
                self:Hide()
            end
        end)

        dialog._dimmer = dimmer
        customTextPopup = dialog
    end

    customTextPopup._title:SetText(titleText or "")
    customTextPopup._box:SetText(initial or "")
    customTextPopup._onSave = onSave
    customTextPopup._dimmer:Show()
    customTextPopup._box:SetFocus()
end

-------------------------------------------------------------------------------
--  Page builder
-------------------------------------------------------------------------------
local function BuildMovementAlertPage(page, hostFrame, yOffset)
    local W = CludesUI.Widgets
    local Pix = CludesUI.PanelPP
    local FONT = CludesUI._font or "Interface\\AddOns\\CludesUI\\media\\fonts\\Expressway.TTF"
    local ACC = CludesUI.CLUDES_GREEN or { r = 0.30, g = 0.79, b = 0.94 }
    local ma = MA()
    if not ma then
        return 0
    end
    local posY = yOffset
    local _, hgt, heading

    hostFrame._showRowDivider = true

    _, hgt = W:Spacer(hostFrame, posY, 12)
    posY = posY - hgt

    -- Activate / Deactivate Movement Preview -- centered wide button matching
    -- the Boss Frames preview button. Loops a fake cooldown through the real
    -- display path using all current settings; the backend self-terminates it
    -- on window close or page/module change (plus the OnHide hook below).
    local previewBtnLbl
    local function PreviewLabel()
        return (CludesUI._MovementAlertPreviewActive and CludesUI._MovementAlertPreviewActive())
                and CludesUI.L("Deactivate Movement Preview")
            or CludesUI.L("Activate Movement Preview")
    end
    local previewBtnFrame
    previewBtnFrame, hgt = W:WideButton(hostFrame, PreviewLabel(), posY, function()
        if not CludesUI._MovementAlertPreview then
            return
        end
        CludesUI._MovementAlertPreview(not CludesUI._MovementAlertPreviewActive())
        if previewBtnLbl then
            previewBtnLbl:SetText(PreviewLabel())
        end
    end)
    posY = posY - hgt
    if not CludesUI._prebuilding then
        -- The button the row was built with and its label, the SHOWN ones: a
        -- pooled row also holds the hidden children and regions an earlier
        -- dress left there, so the first child is not necessarily the button.
        local button
        for _, c in ipairs({ previewBtnFrame:GetChildren() }) do
            if c:IsShown() and c:IsObjectType("Button") then
                button = c
                break
            end
        end
        if button then
            for _, region in ipairs({ button:GetRegions() }) do
                if region:IsShown() and region:IsObjectType("FontString") and region:GetText() then
                    previewBtnLbl = region
                    break
                end
            end
        end
        -- Keep the label truthful if the preview self-terminated meanwhile.
        CludesUI.RegisterWidgetRefresh(function()
            if previewBtnLbl then
                previewBtnLbl:SetText(PreviewLabel())
            end
        end)
    end
    if not _previewOnHideRegistered and CludesUI.RegisterOnHide then
        _previewOnHideRegistered = true
        CludesUI:RegisterOnHide(function()
            if
                CludesUI._MovementAlertPreview
                and CludesUI._MovementAlertPreviewActive
                and CludesUI._MovementAlertPreviewActive()
            then
                CludesUI._MovementAlertPreview(false)
            end
        end)
    end

    _, hgt = W:Spacer(hostFrame, posY, 8)
    posY = posY - hgt

    -------------------------------------------------------------------------
    --  MOVEMENT COOLDOWN ALERT
    -------------------------------------------------------------------------
    heading, hgt = W:SectionHeader(hostFrame, "MOVEMENT COOLDOWN ALERT", posY)
    posY = posY - hgt

    -- Off = no class checked at all (enabledClasses nil), the Totem Bar
    -- convention -- the page stays configurable while ANY class is checked;
    -- the backend additionally gates runtime on the player's own class.
    local function maOff()
        return not ma.enabledClasses
    end
    CludesUI.BuildSectionUnlockJump(heading, {
        key = "CUI_MovementAlert",
        disabled = maOff,
        disabledTooltip = "Select a class above",
        rawTooltip = true,
    })

    local enableRow
    enableRow, hgt = W:DualRow(hostFrame, posY, {
        type = "label",
        text = "Enable Movement Alerts",
        tooltip = "Shows the checked classes' mobility spell(s) counting down on cooldown. Nothing checked = feature disabled. Use Layout Mode to reposition/resize.",
    }, {
        type = "toggle",
        text = "Combat Only",
        tooltip = "Only show the alert while in combat.",
        disabled = maOff,
        disabledTooltip = "Select a class above",
        rawTooltip = true,
        getValue = function()
            return ma.combatOnly == true
        end,
        setValue = function(val)
            ma.combatOnly = val
            Refresh()
        end,
    })
    posY = posY - hgt

    -- Enabled-classes checkbox dropdown (same widget/storage convention as
    -- the Resource Bars Totem Bar): nothing checked = zero-cost disabled.
    if not CludesUI._prebuilding then
        local leftRgn = enableRow._leftRegion
        local classItems = {}
        for _, castFrame in ipairs(CLASS_ORDER) do
            -- WoW Forever lists only the classes it has.
            if not CludesUI.IS_FOREVER or CludesUI.FOREVER_CLASS_SPEC[castFrame] then
                local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[castFrame]
                local name = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[castFrame])
                    or (castFrame:sub(1, 1):upper() .. castFrame:sub(2):lower())
                local hex = color and color.colorStr or "ffffffff"
                classItems[#classItems + 1] = { key = castFrame, label = "|c" .. hex .. name .. "|r" }
            end
        end
        local cbDD, cbDDRefresh
        cbDD, cbDDRefresh = CludesUI.BuildVisOptsCBDropdown(
            leftRgn,
            210,
            leftRgn:GetFrameLevel() + 2,
            classItems,
            function(key)
                return ma.enabledClasses and ma.enabledClasses[key] or false
            end,
            function(key, val)
                -- Zero classes checked collapses the set back to nil, which is THE
                -- disabled state: the backend's MovementEnabled() gate drops every
                -- event/cache/poll, same as the old master toggle being off.
                if not ma.enabledClasses then
                    ma.enabledClasses = {}
                end
                ma.enabledClasses[key] = val or nil
                if not next(ma.enabledClasses) then
                    ma.enabledClasses = nil
                end
                local ddMenu = cbDD._ddMenu
                if ddMenu then
                    for _, scrollFrame in ipairs({ ddMenu:GetChildren() }) do
                        local sc = scrollFrame.GetScrollChild and scrollFrame:GetScrollChild()
                        if sc then
                            for _, row in ipairs({ sc:GetChildren() }) do
                                if row._updateCheck then
                                    row._updateCheck()
                                end
                            end
                        end
                    end
                end
                if CludesUI._UpdateMovementAlertEvents then
                    CludesUI._UpdateMovementAlertEvents()
                end
                Refresh()
                CludesUI:RefreshPage()
            end,
            nil,
            8,
            false
        )
        Pix.Point(cbDD, "RIGHT", leftRgn, "RIGHT", -20, 0)
        leftRgn._control = cbDD
        CludesUI.RegisterWidgetRefresh(cbDDRefresh)
    end

    -- Display/alert settings as page rows (moved out of the old cog popup):
    -- every slot keeps the exact profile keys and side-effects the popup rows had;
    -- RefreshPage() is added only where a value gates another widget's disabled state.
    local sndValues, sndOrder = CludesUI.BuildSoundDropdownValues()
    local ttsValues, ttsOrder = TTSVoiceDropdownValues()

    -- Bar texture dropdown: identical catalog + SharedMedia merge +
    -- texture-preview rows as the CDM Tracking Bars "Bar Texture" dropdown.
    local barTexValues, barTexOrder = {}, {}
    do
        local mt = CludesUI._MovementBarTextures
        if mt then
            CludesUI.AppendSharedMediaTextures(mt.names, mt.order, nil, mt.lookup)
            for _, key in ipairs(mt.order) do
                if key ~= "---" then
                    barTexValues[key] = mt.names[key] or key
                end
                barTexOrder[#barTexOrder + 1] = key
            end
            barTexValues._menuOpts = {
                itemHeight = 28,
                background = function(key)
                    return mt.lookup[key]
                end,
            }
        end
    end
    -- Movement's voice dropdown doubles as the TTS enable: prepend "None"
    -- (the default) to this section's copy of the voice list and skip the
    -- preview icon for it. (Time Spiral/Gateway build their own copies.)
    ttsValues.NONE = "None"
    table.insert(ttsOrder, 1, "NONE")
    do
        local mo = ttsValues._menuOpts
        local origAtlas, origPressed, origClick = mo.iconAtlas, mo.iconPressedAtlas, mo.iconOnClick
        mo.iconAtlas = function(key)
            if key == "NONE" then
                return nil
            end
            return origAtlas and origAtlas(key)
        end
        mo.iconPressedAtlas = function(key)
            if key == "NONE" then
                return nil
            end
            return origPressed and origPressed(key)
        end
        mo.iconOnClick = function(key)
            if key == "NONE" then
                return
            end
            if origClick then
                origClick(key)
            end
        end
    end

    -- Text modes come in three fixed arrangements (the old free-form Text
    -- Format input is gone); the legacy stored "text" value maps to the
    -- duration-first arrangement it used to render.
    local function DMIsText()
        local val = ma.displayMode or "text"
        return val == "text" or val == "text_nd" or val == "text_dn" or val == "text_d"
    end
    local function DMSwatchesDisabled()
        return maOff() or ma.displayMode == "icon"
    end

    local dmRow
    dmRow, hgt = W:DualRow(hostFrame, posY, {
        type = "dropdown",
        text = "Display Mode",
        values = DISPLAY_MODE_VALUES,
        order = DISPLAY_MODE_ORDER,
        disabled = maOff,
        disabledTooltip = "Select a class above",
        rawTooltip = true,
        getValue = function()
            local val = ma.displayMode or "text"
            if val == "text" then
                val = "text_dn"
            end
            return val
        end,
        setValue = function(val)
            local wasText = DMIsText()
            ma.displayMode = val
            -- Crossing the text <-> bar/icon boundary re-seeds Text Size
            -- to that family's default (text 24, bar/icon 12).
            local isText = (val == "text_nd" or val == "text_dn" or val == "text_d")
            if wasText ~= isText then
                ma.textSize = isText and 24 or 12
            end
            Refresh()
            CludesUI:RefreshPage()
        end,
    }, {
        type = "dropdown",
        text = "Bar Texture",
        values = barTexValues,
        order = barTexOrder,
        disabled = function()
            return maOff() or ma.displayMode ~= "bar"
        end,
        disabledTooltip = "Requires Bar display mode",
        rawTooltip = true,
        getValue = function()
            return ma.barTexture or "none"
        end,
        setValue = function(val)
            ma.barTexture = val
            Refresh()
        end,
    })
    posY = posY - hgt

    -- Bar settings cog on the Bar Texture slot: Show Icon on Bar lives here.
    if not CludesUI._prebuilding then
        local region = dmRow._rightRegion
        local function BarCogOff()
            return maOff() or ma.displayMode ~= "bar"
        end
        CludesUI.BuildInlineCog(region, {
            title = "Bar Settings",
            rows = {
                {
                    type = "toggle",
                    label = "Show Icon on Bar",
                    get = function()
                        return ma.barShowIcon ~= false
                    end,
                    set = function(val)
                        ma.barShowIcon = val
                        Refresh()
                    end,
                },
                {
                    type = "toggle",
                    label = "Show Duration Text",
                    get = function()
                        return ma.barShowDuration ~= false
                    end,
                    set = function(val)
                        ma.barShowDuration = val
                        Refresh()
                    end,
                },
            },
            gap = 9,
            disabled = BarCogOff,
            disabledTooltip = "Requires Bar display mode",
        })
    end

    -- Inline controls on the Display Mode slot, mirroring the Unit Frames
    -- Health Bar Left/Right Text rows: dropdown at the right, then the
    -- resize cog, then the Custom + Class color swatch pair. The swatches
    -- (the Use Class Color replacement) only apply to Text and Bar modes.
    if not CludesUI._prebuilding then
        local leftRgn = dmRow._leftRegion

        -- Resize cog (nearest the control): Text Size / Icon Size, each gated to its mode.
        CludesUI.BuildInlineCog(leftRgn, {
            title = "Display Size",
            rows = {
                -- Never disabled: sizes the free text, the bar's number, and
                -- the icon's countdown numbers alike. Re-seeded on text <->
                -- bar/icon display mode switches (24 / 12).
                {
                    type = "slider",
                    label = "Text Size",
                    min = 8,
                    max = 72,
                    step = 1,
                    get = function()
                        return ma.textSize or 24
                    end,
                    set = function(val)
                        ma.textSize = val
                        Refresh()
                    end,
                },
                {
                    type = "slider",
                    label = "Icon Size",
                    min = 16,
                    max = 128,
                    step = 1,
                    disabled = function()
                        return ma.displayMode ~= "icon"
                    end,
                    disabledTooltip = "Requires the Icon display mode",
                    rawTooltip = true,
                    get = function()
                        return ma.iconSize or 40
                    end,
                    set = function(val)
                        ma.iconSize = val
                        Refresh()
                    end,
                },
                -- View over the old numeric precision key: on = 1 decimal,
                -- off = whole seconds.
                {
                    type = "toggle",
                    label = "Show Decimal",
                    disabled = function()
                        return ma.displayMode == "icon"
                    end,
                    disabledTooltip = "Not used in Icon display mode",
                    rawTooltip = true,
                    -- tonumber guard: an older numeric-input build could store
                    -- precision as a string ("1"), and `"1" > 0` is a hard error
                    -- in Lua 5.1 -- it would throw here before set could run, so
                    -- the toggle silently did nothing until a value was written.
                    get = function()
                        return (tonumber(ma.precision) or 1) > 0
                    end,
                    set = function(val)
                        ma.precision = val and 1 or 0
                        Refresh()
                    end,
                },
            },
            gap = 9,
            disabled = maOff,
            disabledTooltip = "Select an Enabled Class",
        })

        local dmAnchor = leftRgn._lastInline or leftRgn._control

        -- Class Colored swatch (nearest the cog)
        local dmClassSwatch, dmUpdateClassSwatch = CludesUI.BuildColorSwatch(
            leftRgn,
            leftRgn:GetFrameLevel() + 5,
            function()
                local _, classFile = UnitClass("player")
                local cc = classFile and CludesUI.GetClassColor(classFile)
                if cc then
                    return cc.r, cc.g, cc.b
                end
                return 1, 1, 1
            end,
            function() end,
            nil,
            20
        )
        Pix.Point(dmClassSwatch, "RIGHT", dmAnchor, "LEFT", -8, 0)
        dmClassSwatch:SetScript("OnClick", function()
            if DMSwatchesDisabled() then
                return
            end
            ma.textColorUseClass = true
            Refresh()
            CludesUI:RefreshPage()
        end)
        dmClassSwatch:SetScript("OnEnter", function()
            CludesUI.ShowWidgetTooltip(dmClassSwatch, "Class Colored")
        end)
        dmClassSwatch:SetScript("OnLeave", function()
            CludesUI.HideWidgetTooltip()
        end)

        -- Custom Colored swatch (left of the class swatch): opens the picker;
        -- clicking while class color is active switches back to custom first.
        local dmSwatch, dmUpdateSwatch = CludesUI.BuildColorSwatch(
            leftRgn,
            leftRgn:GetFrameLevel() + 5,
            function()
                return ma.textColorR or 1, ma.textColorG or 1, ma.textColorB or 1
            end,
            function(r, g, b)
                ma.textColorR, ma.textColorG, ma.textColorB = r, g, b
                Refresh()
            end,
            nil,
            20
        )
        Pix.Point(dmSwatch, "RIGHT", dmClassSwatch, "LEFT", -8, 0)
        leftRgn._lastInline = dmSwatch
        local dmOrigClick = dmSwatch:GetScript("OnClick")
        dmSwatch:SetScript("OnClick", function(self, ...)
            if DMSwatchesDisabled() then
                return
            end
            if ma.textColorUseClass then
                ma.textColorUseClass = false
                Refresh()
                CludesUI:RefreshPage()
                return
            end
            if dmOrigClick then
                dmOrigClick(self, ...)
            end
        end)
        dmSwatch:SetScript("OnEnter", function()
            CludesUI.ShowWidgetTooltip(dmSwatch, "Custom Colored")
        end)
        dmSwatch:SetScript("OnLeave", function()
            CludesUI.HideWidgetTooltip()
        end)
        local function UpdateDmSwatches()
            local offset = DMSwatchesDisabled()
            local isClass = ma.textColorUseClass == true
            dmSwatch:SetAlpha((offset or isClass) and 0.3 or 1)
            dmClassSwatch:SetAlpha((isClass and not offset) and 1 or 0.3)
        end
        CludesUI.RegisterWidgetRefresh(function()
            dmUpdateSwatch()
            dmUpdateClassSwatch()
            UpdateDmSwatches()
        end)
        UpdateDmSwatches()
    end

    -- TTS Voice doubles as the TTS enable ("None" = off, the default) -- a
    -- view over the old maTtsEnabled/maTtsVoiceID keys. It speaks the
    -- ability name (or its per-spell Custom Text); volume lives in the cog.
    local ttsRow
    ttsRow, hgt = W:DualRow(hostFrame, posY, {
        type = "dropdown",
        text = "Sound",
        values = sndValues,
        order = sndOrder,
        disabled = function()
            return maOff() or ma.maTtsEnabled == true
        end,
        disabledTooltip = "Text-to-Speech is enabled and takes priority over Sound.",
        rawTooltip = true,
        getValue = function()
            return ma.maSoundKey or "none"
        end,
        setValue = function(val)
            ma.maSoundKey = val
        end,
    }, {
        type = "dropdown",
        text = "TTS Voice",
        values = ttsValues,
        order = ttsOrder,
        tooltip = "Speaks the ability name once, right when it comes off cooldown -- not a running countdown. None = no speech.",
        disabled = maOff,
        disabledTooltip = "Select a class above",
        rawTooltip = true,
        getValue = function()
            if not ma.maTtsEnabled then
                return "NONE"
            end
            return ma.maTtsVoiceID or 0
        end,
        setValue = function(val)
            if val == "NONE" then
                ma.maTtsEnabled = false
            else
                ma.maTtsEnabled = true
                ma.maTtsVoiceID = val
            end
            CludesUI:RefreshPage()
        end,
    })
    posY = posY - hgt

    if not CludesUI._prebuilding then
        local leftRgn = ttsRow._rightRegion
        local function TtsCogOff()
            return maOff() or not ma.maTtsEnabled
        end
        CludesUI.BuildInlineCog(leftRgn, {
            title = "Text-to-Speech Settings",
            rows = {
                {
                    type = "slider",
                    label = "TTS Volume",
                    min = 0,
                    max = 100,
                    step = 5,
                    get = function()
                        return ma.maTtsVolume or 100
                    end,
                    set = function(val)
                        ma.maTtsVolume = val
                    end,
                },
            },
            gap = 9,
            disabled = TtsCogOff,
            disabledTooltip = "Select a TTS Voice",
        })
    end

    _, hgt = W:Spacer(hostFrame, posY, 16)
    posY = posY - hgt

    -------------------------------------------------------------------------
    --  TRACKED SPELLS
    -------------------------------------------------------------------------
    _, hgt = W:SectionHeader(hostFrame, "TRACKED SPELLS", posY)
    posY = posY - hgt
    posY = posY - 6

    -- 4-column checkbox grid (same visual system as the AuraBuffReminders Auras
    -- section): class-colored spell name left, checkbox right, no ids. Lists every
    -- class's mobility spells (not just the player's), then any user-added spells
    -- (deletable via the X icon), then the + Add Spell button in the next free slot.
    -- Adds/removes rebuild the page so cells always re-flow sequentially with no gaps.
    do
        local GRID_COLS = 4
        local GRID_ROW_H = 50
        local GRID_BOX_SZ = 18
        local GRID_PAD = CludesUI.CONTENT_PAD or 16
        local GRID_SIDE_PAD = 20
        local playerClass = select(2, UnitClass("player"))
        if not ma.spellOverrides then
            ma.spellOverrides = {}
        end

        local function GridChanged()
            if CludesUI._RebuildMovementSpellLookup then
                CludesUI._RebuildMovementSpellLookup()
            end
            if CludesUI._CacheMovementSpells then
                CludesUI._CacheMovementSpells()
            end
            Refresh()
        end

        -- Cell list: presets (all classes), then customs, then the add cell.
        local itemList = {}
        local byClassName = {}
        for _, preset in ipairs(MOVEMENT_PRESETS) do
            local primary = preset.ids[1]
            local details = C_Spell and C_Spell.GetSpellInfo(primary)
            -- WoW Forever: 781 is vanilla's threat drop, not a movement spell, and
            -- the tracker skips it there; it stays a preset id so a saved override
            -- is never shown as a custom cell. Classes Forever does not have list
            -- no presets there.
            local fvSkip = CludesUI.IS_FOREVER
                and (primary == 781 or not CludesUI.FOREVER_CLASS_SPEC[preset.class])
            if details and details.name and not fvSkip then
                local dupKey = preset.class .. ":" .. details.name
                local existing = byClassName[dupKey]
                if existing then
                    -- Same display name within a class (Blizzard splits some
                    -- abilities across ids): fold into the earlier cell so
                    -- one checkbox governs every id and no name lists twice.
                    for i = 1, #preset.ids do
                        existing.ids[#existing.ids + 1] = preset.ids[i]
                    end
                else
                    -- Copy the id list: folded duplicates append to it, and
                    -- the shared preset table must never be mutated.
                    local cellIds = {}
                    for i = 1, #preset.ids do
                        cellIds[i] = preset.ids[i]
                    end
                    local itemInfo = {
                        label = details.name,
                        classToken = preset.class,
                        spellId = primary,
                        ids = cellIds,
                        getVal = function()
                            local o = ma.spellOverrides[primary]
                            if o and o.enabled ~= nil then
                                return o.enabled ~= false
                            end
                            return not MOVEMENT_DEFAULT_OFF[primary]
                        end,
                        setVal = function(val)
                            for i = 1, #cellIds do
                                local ident = cellIds[i]
                                ma.spellOverrides[ident] = ma.spellOverrides[ident] or {}
                                ma.spellOverrides[ident].enabled = val
                            end
                        end,
                    }
                    byClassName[dupKey] = itemInfo
                    itemList[#itemList + 1] = itemInfo
                end
            end
        end
        local customIds = {}
        for spellId in pairs(ma.spellOverrides) do
            if type(spellId) == "number" and not MOVEMENT_PRESET_IDS[spellId] then
                customIds[#customIds + 1] = spellId
            end
        end
        table.sort(customIds)
        for _, spellId in ipairs(customIds) do
            local o = ma.spellOverrides[spellId]
            local details = C_Spell and C_Spell.GetSpellInfo(spellId)
            itemList[#itemList + 1] = {
                label = (details and details.name) or CludesUI.L("Unknown Spell"),
                classToken = o.class,
                spellId = spellId,
                ids = { spellId },
                custom = true,
                getVal = function()
                    local shade = ma.spellOverrides[spellId]
                    return shade ~= nil and shade.enabled ~= false
                end,
                setVal = function(val)
                    local shade = ma.spellOverrides[spellId]
                    if shade then
                        shade.enabled = val
                    end
                end,
            }
        end
        itemList[#itemList + 1] = { addButton = true }

        local totalRows = math.ceil(#itemList / GRID_COLS)
        local totalW = hostFrame:GetWidth() - GRID_PAD * 2
        local colW = math.floor(totalW / GRID_COLS)

        for row = 0, totalRows - 1 do
            local rowFrame = CreateFrame("Frame", nil, hostFrame)
            Pix.Size(rowFrame, totalW, GRID_ROW_H)
            Pix.Point(rowFrame, "TOPLEFT", hostFrame, "TOPLEFT", GRID_PAD, posY - row * GRID_ROW_H)
            rowFrame._skipRowDivider = true
            CludesUI.RowBg(rowFrame, hostFrame)

            for d = 1, GRID_COLS - 1 do
                local div = rowFrame:CreateTexture(nil, "ARTWORK")
                div:SetColorTexture(1, 1, 1, 0.06)
                if div.SetSnapToPixelGrid then
                    div:SetSnapToPixelGrid(false)
                    div:SetTexelSnappingBias(0)
                end
                div:SetWidth(1)
                local xPos = d * colW
                Pix.Point(div, "TOP", rowFrame, "TOPLEFT", xPos, 0)
                Pix.Point(div, "BOTTOM", rowFrame, "BOTTOMLEFT", xPos, 0)
            end

            for column = 0, GRID_COLS - 1 do
                local position = row * GRID_COLS + column + 1
                local itemInfo = itemList[position]
                if not itemInfo then
                    break
                end

                local cellFrame = CreateFrame("Frame", nil, rowFrame)
                cellFrame:SetSize(colW, GRID_ROW_H)
                cellFrame:SetPoint("TOPLEFT", rowFrame, "TOPLEFT", column * colW, 0)

                if itemInfo.addButton then
                    -- Keybind-button style (dropdown-look bg/border with the
                    -- hover brighten), centered in its grid slot.
                    local addBtn = CreateFrame("Button", nil, cellFrame)
                    Pix.Size(addBtn, 126, 29)
                    addBtn:SetPoint("CENTER", cellFrame, "CENTER", 0, 0)
                    addBtn:SetFrameLevel(cellFrame:GetFrameLevel() + 2)
                    local addBg = CludesUI.SolidTex(
                        addBtn,
                        "BACKGROUND",
                        CludesUI.DD_BG_R,
                        CludesUI.DD_BG_G,
                        CludesUI.DD_BG_B,
                        CludesUI.DD_BG_A
                    )
                    addBg:SetAllPoints()
                    local addBrd = CludesUI.MakeRoundedBorder(addBtn, 1, 1, 1, CludesUI.DD_BRD_A, addBg)
                    local addLbl = CludesUI.MakeFont(addBtn, 12, nil, 1, 1, 1)
                    addLbl:SetAlpha(CludesUI.DD_TXT_A)
                    addLbl:SetPoint("CENTER")
                    addLbl:SetText(CludesUI.L("+ Add Spell"))
                    addBtn:SetScript("OnEnter", function()
                        addBg:SetColorTexture(
                            CludesUI.DD_BG_R,
                            CludesUI.DD_BG_G,
                            CludesUI.DD_BG_B,
                            CludesUI.DD_BG_HA
                        )
                        if addBrd and addBrd.SetColor then
                            addBrd:SetColor(1, 1, 1, 0.3)
                        end
                    end)
                    addBtn:SetScript("OnLeave", function()
                        addBg:SetColorTexture(
                            CludesUI.DD_BG_R,
                            CludesUI.DD_BG_G,
                            CludesUI.DD_BG_B,
                            CludesUI.DD_BG_A
                        )
                        if addBrd and addBrd.SetColor then
                            addBrd:SetColor(1, 1, 1, CludesUI.DD_BRD_A)
                        end
                    end)
                    addBtn:SetScript("OnClick", function()
                        ShowAddSpellPopup(function(spellId)
                            ma.spellOverrides[spellId] = ma.spellOverrides[spellId]
                                or { enabled = true, class = playerClass }
                            GridChanged()
                            CludesUI:RefreshPage(true)
                        end)
                    end)
                else
                    local cr, cg, cb = 1, 1, 1
                    if itemInfo.classToken then
                        local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[itemInfo.classToken]
                        if cc then
                            cr, cg, cb = cc.r, cc.g, cc.b
                        end
                    end

                    local labelText = CludesUI.MakeFont(cellFrame, 13, nil, cr, cg, cb)
                    labelText:SetPoint("LEFT", cellFrame, "LEFT", GRID_SIDE_PAD, 0)
                    labelText:SetWidth(colW - GRID_SIDE_PAD * 2 - GRID_BOX_SZ - 6)
                    labelText:SetJustifyH("LEFT")
                    labelText:SetMaxLines(2)
                    labelText:SetText(itemInfo.label)

                    local boxFrame = CreateFrame("Frame", nil, cellFrame)
                    boxFrame:SetSize(GRID_BOX_SZ, GRID_BOX_SZ)
                    boxFrame:SetPoint("RIGHT", cellFrame, "RIGHT", -GRID_SIDE_PAD, 0)
                    local boxBg = boxFrame:CreateTexture(nil, "BACKGROUND")
                    boxBg:SetAllPoints()
                    boxBg:SetColorTexture(0.114, 0.106, 0.099, 1)
                    if boxBg.SetSnapToPixelGrid then
                        boxBg:SetSnapToPixelGrid(false)
                        boxBg:SetTexelSnappingBias(0)
                    end
                    local boxBrd = CludesUI.MakeRoundedBorder(boxFrame, 0.224, 0.215, 0.207, 0.6, boxBg)
                    local check = boxFrame:CreateTexture(nil, "ARTWORK")
                    check:SetPoint("TOPLEFT", boxFrame, "TOPLEFT", 3, -3)
                    check:SetPoint("BOTTOMRIGHT", boxFrame, "BOTTOMRIGHT", -3, 3)
                    check:SetColorTexture(ACC.r, ACC.g, ACC.b, 1)
                    CludesUI.RoundBody(boxFrame, check, 1)
                    if check.SetSnapToPixelGrid then
                        check:SetSnapToPixelGrid(false)
                        check:SetTexelSnappingBias(0)
                    end

                    local button = CreateFrame("Button", nil, cellFrame)
                    button:SetAllPoints(cellFrame)
                    button:SetFrameLevel(cellFrame:GetFrameLevel() + 2)
                    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")

                    -- A cell is disabled while its class is unchecked in the
                    -- Enable Movement Alerts dropdown (tracking can never
                    -- fire for it). The X delete on custom cells stays live
                    -- so stale entries can still be cleaned up.
                    local function CellDisabled()
                        local ec = ma.enabledClasses
                        if not ec then
                            return true
                        end
                        if itemInfo.classToken then
                            return not ec[itemInfo.classToken]
                        end
                        return false
                    end

                    local function ApplyVisual()
                        local dis = CellDisabled()
                        local on = itemInfo.getVal()
                        if on then
                            check:Show()
                            boxBrd:SetColor(ACC.r, ACC.g, ACC.b, 0.15)
                        else
                            check:Hide()
                            boxBrd:SetColor(0.224, 0.215, 0.207, 0.6)
                        end
                        if dis then
                            labelText:SetAlpha(0.3)
                            boxFrame:SetAlpha(0.4)
                        else
                            labelText:SetAlpha(on and 1 or 0.5)
                            boxFrame:SetAlpha(1)
                        end
                    end
                    ApplyVisual()

                    button:SetScript("OnClick", function(_, mouseButton)
                        if CellDisabled() then
                            return
                        end
                        if mouseButton == "RightButton" then
                            local shade = ma.spellOverrides[itemInfo.spellId]
                            ShowCustomTextPopup(
                                itemInfo.label,
                                shade and shade.customText or "",
                                function(txt)
                                    for i = 1, #itemInfo.ids do
                                        local ident = itemInfo.ids[i]
                                        ma.spellOverrides[ident] = ma.spellOverrides[ident] or {}
                                        ma.spellOverrides[ident].customText = (txt ~= "") and txt or nil
                                    end
                                    if CludesUI._CacheMovementSpells then
                                        CludesUI._CacheMovementSpells()
                                    end
                                    Refresh()
                                end
                            )
                            return
                        end
                        itemInfo.setVal(not itemInfo.getVal())
                        ApplyVisual()
                        GridChanged()
                    end)
                    button:SetScript("OnEnter", function()
                        if CellDisabled() then
                            CludesUI.ShowWidgetTooltip(
                                cellFrame,
                                CludesUI.DisabledTooltip("Enable this class above")
                            )
                            return
                        end
                        if not itemInfo.getVal() then
                            labelText:SetAlpha(0.8)
                        end
                        CludesUI.ShowWidgetTooltip(
                            cellFrame,
                            CludesUI.L("Right-Click to set custom alert text.")
                        )
                    end)
                    button:SetScript("OnLeave", function()
                        ApplyVisual()
                        CludesUI.HideWidgetTooltip()
                    end)

                    CludesUI.RegisterWidgetRefresh(ApplyVisual)

                    if itemInfo.custom then
                        local delBtn = CreateFrame("Button", nil, cellFrame)
                        delBtn:SetSize(12, 12)
                        delBtn:SetPoint("TOPRIGHT", cellFrame, "TOPRIGHT", -4, -4)
                        delBtn:SetFrameLevel(button:GetFrameLevel() + 2)
                        local delIcon = delBtn:CreateTexture(nil, "OVERLAY")
                        delIcon:SetAllPoints()
                        delIcon:SetTexture("Interface\\AddOns\\CludesUI\\media\\icons\\cui-close.png")
                        delIcon:SetAlpha(0.4)
                        delBtn:SetScript("OnEnter", function()
                            delIcon:SetAlpha(0.9)
                        end)
                        delBtn:SetScript("OnLeave", function()
                            delIcon:SetAlpha(0.4)
                        end)
                        delBtn:SetScript("OnClick", function()
                            ma.spellOverrides[itemInfo.spellId] = nil
                            GridChanged()
                            CludesUI:RefreshPage(true)
                        end)
                    end
                end
            end
        end
        posY = posY - totalRows * GRID_ROW_H
    end

    _, hgt = W:Spacer(hostFrame, posY, 16)
    posY = posY - hgt

    -------------------------------------------------------------------------
    --  EXTRA TRACKING
    -------------------------------------------------------------------------
    heading, hgt = W:SectionHeader(hostFrame, "EXTRA TRACKING", posY)
    posY = posY - hgt

    -- The two sibling trackers' master toggles, each carrying its full settings cog.
    local function tsOff()
        return not ma.tsEnabled
    end
    local function gwOff()
        return not ma.gwEnabled
    end
    -- Time Spiral is the section's first mover, so the header's button takes
    -- it; the Gateway Shard mover stays reachable through its cog's footer.
    CludesUI.BuildSectionUnlockJump(
        heading,
        { key = "CUI_TimeSpiralAlert", disabled = tsOff, disabledTooltip = "Enable Time Spiral Tracker" }
    )

    local extraRow
    extraRow, hgt = W:DualRow(hostFrame, posY, {
        type = "toggle",
        text = "Enable Time Spiral Tracker",
        tooltip = "Flashes a banner whenever a tracked mobility spell's cooldown is proc-reset. Use Layout Mode to reposition/resize.",
        getValue = function()
            return ma.tsEnabled == true
        end,
        setValue = function(val)
            ma.tsEnabled = val
            if CludesUI._UpdateMovementAlertEvents then
                CludesUI._UpdateMovementAlertEvents()
            end
            Refresh()
            CludesUI:RefreshPage()
        end,
    }, {
        type = "toggle",
        text = "Enable Gateway Shard Alert",
        tooltip = "Warlock only. Alerts when your Gateway Control Shard is usable. Use Layout Mode to reposition/resize.",
        getValue = function()
            return ma.gwEnabled == true
        end,
        setValue = function(val)
            ma.gwEnabled = val
            if CludesUI._UpdateMovementAlertEvents then
                CludesUI._UpdateMovementAlertEvents()
            end
            Refresh()
            CludesUI:RefreshPage()
        end,
    })
    posY = posY - hgt

    -- Time Spiral settings cog (left slot)
    if not CludesUI._prebuilding then
        local leftRgn = extraRow._leftRegion
        local sndValues2, sndOrder2 = CludesUI.BuildSoundDropdownValues()
        local ttsValues2, ttsOrder2 = TTSVoiceDropdownValues()
        CludesUI.BuildInlineCog(leftRgn, {
            title = "Time Spiral Settings",
            minWidth = 300,
            rows = {
                {
                    type = "input",
                    label = "Text Format",
                    get = function()
                        return ma.tsTextFormat or "FREE MOVEMENT\\n%.1f"
                    end,
                    set = function(val)
                        ma.tsTextFormat = val
                        Refresh()
                    end,
                },
                {
                    type = "colorpicker",
                    label = "Color",
                    disabled = function()
                        return ma.tsColorUseClass
                    end,
                    disabledTooltip = "Disable Class Color to pick a custom color.",
                    rawTooltip = true,
                    get = function()
                        return ma.tsColorR or 0.53, ma.tsColorG or 1, ma.tsColorB or 0
                    end,
                    set = function(r, g, b)
                        ma.tsColorR, ma.tsColorG, ma.tsColorB = r, g, b
                        Refresh()
                    end,
                },
                {
                    type = "toggle",
                    label = "Use Class Color",
                    get = function()
                        return ma.tsColorUseClass == true
                    end,
                    set = function(val)
                        ma.tsColorUseClass = val
                        Refresh()
                    end,
                },
                {
                    type = "dropdown",
                    label = "Sound",
                    values = sndValues2,
                    order = sndOrder2,
                    disabled = function()
                        return ma.tsTtsEnabled == true
                    end,
                    disabledTooltip = "Text-to-Speech is enabled below and takes priority over Sound.",
                    rawTooltip = true,
                    get = function()
                        return ma.tsSoundKey or "none"
                    end,
                    set = function(val)
                        ma.tsSoundKey = val
                    end,
                },
                {
                    type = "toggle",
                    label = "Use Text-to-Speech",
                    get = function()
                        return ma.tsTtsEnabled == true
                    end,
                    set = function(val)
                        ma.tsTtsEnabled = val
                    end,
                },
                {
                    type = "dropdown",
                    label = "TTS Voice",
                    values = ttsValues2,
                    order = ttsOrder2,
                    disabled = function()
                        return not ma.tsTtsEnabled
                    end,
                    disabledTooltip = "Enable Text-to-Speech first",
                    rawTooltip = true,
                    get = function()
                        return ma.tsTtsVoiceID or 0
                    end,
                    set = function(val)
                        ma.tsTtsVoiceID = val
                    end,
                },
                {
                    type = "input",
                    label = "TTS Message",
                    disabled = function()
                        return not ma.tsTtsEnabled
                    end,
                    disabledTooltip = "Enable Text-to-Speech first",
                    rawTooltip = true,
                    get = function()
                        return ma.tsTtsMessage or "Free movement"
                    end,
                    set = function(val)
                        ma.tsTtsMessage = val
                    end,
                },
                {
                    type = "slider",
                    label = "TTS Volume",
                    min = 0,
                    max = 100,
                    step = 5,
                    disabled = function()
                        return not ma.tsTtsEnabled
                    end,
                    get = function()
                        return ma.tsTtsVolume or 100
                    end,
                    set = function(val)
                        ma.tsTtsVolume = val
                    end,
                },
            },
            footer = { unlockKey = "CUI_TimeSpiralAlert" },
            gap = 9,
            disabled = tsOff,
            disabledTooltip = "Enable Time Spiral Tracker",
        })
    end

    -- Gateway Shard settings cog (right slot); Combat Only lives in here.
    if not CludesUI._prebuilding then
        local region = extraRow._rightRegion
        local sndValues2, sndOrder2 = CludesUI.BuildSoundDropdownValues()
        local ttsValues2, ttsOrder2 = TTSVoiceDropdownValues()
        CludesUI.BuildInlineCog(region, {
            title = "Gateway Shard Settings",
            minWidth = 300,
            rows = {
                {
                    type = "toggle",
                    label = "Combat Only",
                    tooltip = "Only show the alert while in combat.",
                    get = function()
                        return ma.gwCombatOnly == true
                    end,
                    set = function(val)
                        ma.gwCombatOnly = val
                        Refresh()
                    end,
                },
                {
                    type = "input",
                    label = "Text",
                    get = function()
                        return ma.gwText or "GATEWAY READY"
                    end,
                    set = function(val)
                        ma.gwText = val
                        Refresh()
                    end,
                },
                {
                    type = "colorpicker",
                    label = "Color",
                    disabled = function()
                        return ma.gwColorUseClass
                    end,
                    disabledTooltip = "Disable Class Color to pick a custom color.",
                    rawTooltip = true,
                    get = function()
                        return ma.gwColorR or 0.7, ma.gwColorG or 0, ma.gwColorB or 1
                    end,
                    set = function(r, g, b)
                        ma.gwColorR, ma.gwColorG, ma.gwColorB = r, g, b
                        Refresh()
                    end,
                },
                {
                    type = "toggle",
                    label = "Use Class Color",
                    get = function()
                        return ma.gwColorUseClass == true
                    end,
                    set = function(val)
                        ma.gwColorUseClass = val
                        Refresh()
                    end,
                },
                {
                    type = "dropdown",
                    label = "Sound",
                    values = sndValues2,
                    order = sndOrder2,
                    disabled = function()
                        return ma.gwTtsEnabled == true
                    end,
                    disabledTooltip = "Text-to-Speech is enabled below and takes priority over Sound.",
                    rawTooltip = true,
                    get = function()
                        return ma.gwSoundKey or "none"
                    end,
                    set = function(val)
                        ma.gwSoundKey = val
                    end,
                },
                {
                    type = "toggle",
                    label = "Use Text-to-Speech",
                    get = function()
                        return ma.gwTtsEnabled == true
                    end,
                    set = function(val)
                        ma.gwTtsEnabled = val
                    end,
                },
                {
                    type = "dropdown",
                    label = "TTS Voice",
                    values = ttsValues2,
                    order = ttsOrder2,
                    disabled = function()
                        return not ma.gwTtsEnabled
                    end,
                    disabledTooltip = "Enable Text-to-Speech first",
                    rawTooltip = true,
                    get = function()
                        return ma.gwTtsVoiceID or 0
                    end,
                    set = function(val)
                        ma.gwTtsVoiceID = val
                    end,
                },
                {
                    type = "input",
                    label = "TTS Message",
                    disabled = function()
                        return not ma.gwTtsEnabled
                    end,
                    disabledTooltip = "Enable Text-to-Speech first",
                    rawTooltip = true,
                    get = function()
                        return ma.gwTtsMessage or "Gateway ready"
                    end,
                    set = function(val)
                        ma.gwTtsMessage = val
                    end,
                },
                {
                    type = "slider",
                    label = "TTS Volume",
                    min = 0,
                    max = 100,
                    step = 5,
                    disabled = function()
                        return not ma.gwTtsEnabled
                    end,
                    get = function()
                        return ma.gwTtsVolume or 100
                    end,
                    set = function(val)
                        ma.gwTtsVolume = val
                    end,
                },
            },
            footer = { unlockKey = "CUI_GatewayShardAlert" },
            gap = 9,
            disabled = gwOff,
            disabledTooltip = "Enable Gateway Shard Alert",
        })
    end

    _, hgt = W:Spacer(hostFrame, posY, 20)
    posY = posY - hgt

    return math.abs(posY)
end

_G._CUI_BuildMovementAlertPage = BuildMovementAlertPage
