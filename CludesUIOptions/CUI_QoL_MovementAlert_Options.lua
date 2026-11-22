if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-------------------------------------------------------------------------------
--  CUI_QoL_MovementAlert_Options.lua
--  Options page for Movement Alert (registered as a page under the
--  CludesUIQoL module by CUI_QoL_Options.lua). Builds four sections:
--    MOVEMENT COOLDOWN ALERT, TRACKED SPELLS, TIME SPIRAL, GATEWAY SHARD.
--  Position/size for all three on-screen trackers is controlled entirely
--  through CUI's Unlock Mode (registered in CludesUIQoL_MovementAlert.lua)
--  rather than in-page sliders, matching how Combat Alert/BattleRes work.
-------------------------------------------------------------------------------

if not CUI._ModuleNS["CludesUIQoL"] then return end -- module disabled: no options page

-- Page reuse: frames this file builds go through the options frame pool
-- (CludesUI_FramePool.lua), which hands a kept page its previous build's
-- frames back reset to new; on any other parent it is the plain CreateFrame.
local CreateFrame = CUI._Pool.CreateFrame

local function DB()
    local func = _G._CUI_MovementAlert_DB
    return func and func() or nil
end

local function MA()
    local profile = DB()
    return profile and profile.profile and profile.profile.movementAlert
end

local function ApplyMovementAlert()
    if CUI._applyMovementAlert then CUI._applyMovementAlert() end
    if CUI._applyTimeSpiral then CUI._applyTimeSpiral() end
    if CUI._applyGateway then CUI._applyGateway() end
    if CUI._UpdateMovementAlertEvents then CUI._UpdateMovementAlertEvents() end
    if CUI._CheckMovementCooldown then CUI._CheckMovementCooldown() end
    if CUI._CheckGatewayUsable then CUI._CheckGatewayUsable() end
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
for _, entry in ipairs(MOVEMENT_PRESETS) do
    for _, ident in ipairs(entry.ids) do
        MOVEMENT_PRESET_IDS[ident] = true
    end
end

-- Presets that default to unchecked (backend-owned set, shared so the grid
-- and the tracker read the same truth).
local MOVEMENT_DEFAULT_OFF = CUI._MovementDefaultOff or {}

-- Voices are enumerated live from C_VoiceChat rather than a static list --
-- availability varies by client/OS. Falls back to a single "Default" entry
-- (voiceID 0) if the API or voice list isn't available.
local function VoiceChoices()
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
        iconAtlas = function() return CUI.SOUND_ICON_ATLAS end,
        iconPressedAtlas = function() return CUI.SOUND_ICON_PRESSED_ATLAS end,
        iconOnClick = function(key)
            if C_VoiceChat and C_VoiceChat.SpeakText then
                pcall(C_VoiceChat.SpeakText, key, "This is a voice preview", 1, 100, true)
            end
        end,
        iconTooltip = function() return "Preview Voice" end,
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
    local Pix = CUI.PanelPP
    local FONT = CUI._font or "Interface\\AddOns\\CludesUI\\media\\fonts\\Expressway.TTF"

    if not addSpellPopup then
        local shade = CreateFrame("Frame", nil, UIParent)
        shade:SetFrameStrata("FULLSCREEN_DIALOG")
        shade:SetAllPoints(UIParent)
        shade:EnableMouse(true)
        shade:Hide()
        local dimTex = shade:CreateTexture(nil, "BACKGROUND")
        dimTex:SetAllPoints()
        dimTex:SetColorTexture(0, 0, 0, 0.25)

        local dialog = CreateFrame("Frame", nil, shade)
        dialog:SetSize(240, 150)
        dialog:SetPoint("CENTER", CUI._mainFrame or UIParent, "CENTER", 0, 60)
        dialog:SetFrameStrata("FULLSCREEN_DIALOG")
        dialog:SetFrameLevel(shade:GetFrameLevel() + 10)
        dialog:EnableMouse(true)
        local backdrop = dialog:CreateTexture(nil, "BACKGROUND")
        backdrop:SetAllPoints()
        backdrop:SetColorTexture(0.062, 0.070, 0.082, 1)
        CUI.MakeRoundedBorder(dialog, 1, 1, 1, 0.15, backdrop)

        local title = dialog:CreateFontString(nil, "OVERLAY")
        title:SetFont(FONT, 14, "")
        title:SetPoint("TOP", dialog, "TOP", 0, -18)
        title:SetTextColor(1, 1, 1, 1)
        title:SetText(CUI.L("Add Spell"))

        local sidLbl = dialog:CreateFontString(nil, "OVERLAY")
        sidLbl:SetFont(FONT, 11, "")
        sidLbl:SetPoint("TOPLEFT", dialog, "TOPLEFT", 24, -52)
        sidLbl:SetTextColor(0.7, 0.7, 0.7, 1)
        sidLbl:SetText(CUI.L("Spell ID"))

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
        CUI.MakeRoundedBorder(sidBox, 1, 1, 1, 0.12, sidBg)
        dialog._sidBox = sidBox

        local status = dialog:CreateFontString(nil, "OVERLAY")
        status:SetFont(FONT, 11, "")
        status:SetPoint("TOP", sidBox, "BOTTOM", 0, -8)
        status:SetTextColor(1, 0.3, 0.3, 1)
        dialog._status = status

        local accR, accG, accB = CUI.GetAccentColor()
        local addBtn = CreateFrame("Button", nil, dialog)
        addBtn:SetSize(80, 26)
        addBtn:SetPoint("BOTTOM", dialog, "BOTTOM", 0, 16)
        local addBg = addBtn:CreateTexture(nil, "BACKGROUND")
        addBg:SetAllPoints()
        addBg:SetColorTexture(accR, accG, accB, 0.15)
        CUI.MakeRoundedBorder(addBtn, accR, accG, accB, 0.4, addBg)
        local addLbl = addBtn:CreateFontString(nil, "OVERLAY")
        addLbl:SetFont(FONT, 12, "")
        addLbl:SetPoint("CENTER")
        addLbl:SetTextColor(accR, accG, accB, 1)
        addLbl:SetText(CUI.L("Add"))

        local function TryAdd()
            local ident = tonumber(sidBox:GetText())
            if not ident or ident <= 0 then
                dialog._status:SetText(CUI.L("Enter a valid spell ID"))
                return
            end
            sidBox:SetText("")
            shade:Hide()
            if dialog._onAdded then dialog._onAdded(ident) end
        end
        addBtn:SetScript("OnClick", TryAdd)
        sidBox:SetScript("OnEnterPressed", TryAdd)
        sidBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

        shade:SetScript("OnMouseDown", function(self)
            if not dialog:IsMouseOver() then self:Hide() end
        end)

        dialog._dimmer = shade
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
    local Pix = CUI.PanelPP
    local FONT = CUI._font or "Interface\\AddOns\\CludesUI\\media\\fonts\\Expressway.TTF"

    if not customTextPopup then
        local shade = CreateFrame("Frame", nil, UIParent)
        shade:SetFrameStrata("FULLSCREEN_DIALOG")
        shade:SetAllPoints(UIParent)
        shade:EnableMouse(true)
        shade:Hide()
        local dimTex = shade:CreateTexture(nil, "BACKGROUND")
        dimTex:SetAllPoints()
        dimTex:SetColorTexture(0, 0, 0, 0.25)

        local dialog = CreateFrame("Frame", nil, shade)
        dialog:SetSize(260, 150)
        dialog:SetPoint("CENTER", CUI._mainFrame or UIParent, "CENTER", 0, 60)
        dialog:SetFrameStrata("FULLSCREEN_DIALOG")
        dialog:SetFrameLevel(shade:GetFrameLevel() + 10)
        dialog:EnableMouse(true)
        local backdrop = dialog:CreateTexture(nil, "BACKGROUND")
        backdrop:SetAllPoints()
        backdrop:SetColorTexture(0.062, 0.070, 0.082, 1)
        CUI.MakeRoundedBorder(dialog, 1, 1, 1, 0.15, backdrop)

        local title = dialog:CreateFontString(nil, "OVERLAY")
        title:SetFont(FONT, 14, "")
        title:SetPoint("TOP", dialog, "TOP", 0, -18)
        title:SetTextColor(1, 1, 1, 1)
        dialog._title = title

        local labelFS = dialog:CreateFontString(nil, "OVERLAY")
        labelFS:SetFont(FONT, 11, "")
        labelFS:SetPoint("TOPLEFT", dialog, "TOPLEFT", 24, -52)
        labelFS:SetTextColor(0.7, 0.7, 0.7, 1)
        labelFS:SetText(CUI.L("Custom Alert Text (empty = ability name)"))

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
        CUI.MakeRoundedBorder(boxFrame, 1, 1, 1, 0.12, boxBg)
        dialog._box = boxFrame

        local accR, accG, accB = CUI.GetAccentColor()
        local saveBtn = CreateFrame("Button", nil, dialog)
        saveBtn:SetSize(80, 26)
        saveBtn:SetPoint("BOTTOM", dialog, "BOTTOM", 0, 16)
        local saveBg = saveBtn:CreateTexture(nil, "BACKGROUND")
        saveBg:SetAllPoints()
        saveBg:SetColorTexture(accR, accG, accB, 0.15)
        CUI.MakeRoundedBorder(saveBtn, accR, accG, accB, 0.4, saveBg)
        local saveLbl = saveBtn:CreateFontString(nil, "OVERLAY")
        saveLbl:SetFont(FONT, 12, "")
        saveLbl:SetPoint("CENTER")
        saveLbl:SetTextColor(accR, accG, accB, 1)
        saveLbl:SetText(CUI.L("Save"))

        local function Commit()
            shade:Hide()
            if dialog._onSave then dialog._onSave(dialog._box:GetText() or "") end
        end
        saveBtn:SetScript("OnClick", Commit)
        boxFrame:SetScript("OnEnterPressed", Commit)
        boxFrame:SetScript("OnEscapePressed", function() shade:Hide() end)

        shade:SetScript("OnMouseDown", function(self)
            if not dialog:IsMouseOver() then self:Hide() end
        end)

        dialog._dimmer = shade
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
    local W = CUI.Widgets
    local Pix = CUI.PanelPP
    local FONT = CUI._font or "Interface\\AddOns\\CludesUI\\media\\fonts\\Expressway.TTF"
    local ACC = CUI.CLUDES_GREEN or { r = 0.30, g = 0.79, b = 0.94 }
    local ma = MA()
    -- Row accessors over ma: a key read (or its default) and written.
    local function MaField(key)
        return function(value) ma[key] = value end
    end
    local function MaFieldThen(key)
        return function(value)
            ma[key] = value
            ApplyMovementAlert()
        end
    end
    local function MaFieldOr(key, default)
        return function() return ma[key] or default end
    end
    if not ma then return 0 end
    local cursorY = yOffset
    local _, height, heading

    hostFrame._showRowDivider = true

    _, height = W:Spacer(hostFrame, cursorY, 12)
    cursorY = cursorY - height

    -- Activate / Deactivate Movement Preview -- centered wide button matching
    -- the Boss Frames preview button. Loops a fake cooldown through the real
    -- display path using all current settings; the backend self-terminates it
    -- on window close or page/module change (plus the OnHide hook below).
    local previewBtnLbl
    local function PreviewLabel()
        return (CUI._MovementAlertPreviewActive and CUI._MovementAlertPreviewActive())
                and CUI.L("Deactivate Movement Preview")
            or CUI.L("Activate Movement Preview")
    end
    local previewBtnFrame
    previewBtnFrame, height = W:WideButton(hostFrame, PreviewLabel(), cursorY, function()
        if not CUI._MovementAlertPreview then return end
        CUI._MovementAlertPreview(not CUI._MovementAlertPreviewActive())
        if previewBtnLbl then previewBtnLbl:SetText(PreviewLabel()) end
    end)
    cursorY = cursorY - height
    if not CUI._prebuilding then
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
        CUI.RegisterWidgetRefresh(function()
            if previewBtnLbl then previewBtnLbl:SetText(PreviewLabel()) end
        end)
    end
    if not _previewOnHideRegistered and CUI.RegisterOnHide then
        _previewOnHideRegistered = true
        CUI:RegisterOnHide(function()
            if
                CUI._MovementAlertPreview
                and CUI._MovementAlertPreviewActive
                and CUI._MovementAlertPreviewActive()
            then
                CUI._MovementAlertPreview(false)
            end
        end)
    end

    _, height = W:Spacer(hostFrame, cursorY, 8)
    cursorY = cursorY - height

    -------------------------------------------------------------------------
    --  MOVEMENT COOLDOWN ALERT
    -------------------------------------------------------------------------
    heading, height = W:SectionHeader(hostFrame, "MOVEMENT COOLDOWN ALERT", cursorY)
    cursorY = cursorY - height

    -- Off = no class checked at all (enabledClasses nil), the Totem Bar
    -- convention -- the page stays configurable while ANY class is checked;
    -- the backend additionally gates runtime on the player's own class.
    local function maOff() return not ma.enabledClasses end
    CUI.BuildSectionUnlockJump(heading, {
        key = "CUI_MovementAlert",
        disabled = maOff,
        disabledTooltip = "Select a class above",
        rawTooltip = true,
    })

    local enableRow
    enableRow, height = W:DualRow(hostFrame, cursorY, {
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
        getValue = function() return ma.combatOnly == true end,
        setValue = MaFieldThen("combatOnly"),
    })
    cursorY = cursorY - height

    -- Enabled-classes checkbox dropdown (same widget/storage convention as
    -- the Resource Bars Totem Bar): nothing checked = zero-cost disabled.
    if not CUI._prebuilding then
        local leftRegion = enableRow._leftRegion
        local classItems = {}
        for _, castFrame in ipairs(CLASS_ORDER) do
            -- WoW Forever lists only the classes it has.
            if not CUI.IS_FOREVER or CUI.FOREVER_CLASS_SPEC[castFrame] then
                local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[castFrame]
                local name = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[castFrame])
                    or (castFrame:sub(1, 1):upper() .. castFrame:sub(2):lower())
                local hex = color and color.colorStr or "ffffffff"
                classItems[#classItems + 1] = { key = castFrame, label = "|c" .. hex .. name .. "|r" }
            end
        end
        local checkDrop, cbDDRefresh
        checkDrop, cbDDRefresh = CUI.BuildVisOptsCBDropdown(
            leftRegion,
            210,
            leftRegion:GetFrameLevel() + 2,
            classItems,
            function(key) return ma.enabledClasses and ma.enabledClasses[key] or false end,
            function(key, val)
                -- Zero classes checked collapses the set back to nil, which is THE
                -- disabled state: the backend's MovementEnabled() gate drops every
                -- event/cache/poll, same as the old master toggle being off.
                if not ma.enabledClasses then ma.enabledClasses = {} end
                ma.enabledClasses[key] = val or nil
                if not next(ma.enabledClasses) then ma.enabledClasses = nil end
                local ddMenu = checkDrop._ddMenu
                if ddMenu then
                    for _, scrollFrame in ipairs({ ddMenu:GetChildren() }) do
                        local sc = scrollFrame.GetScrollChild and scrollFrame:GetScrollChild()
                        if sc then
                            for _, row in ipairs({ sc:GetChildren() }) do
                                if row._updateCheck then row._updateCheck() end
                            end
                        end
                    end
                end
                if CUI._UpdateMovementAlertEvents then CUI._UpdateMovementAlertEvents() end
                ApplyMovementAlert()
                CUI:RefreshPage()
            end,
            nil,
            8,
            false
        )
        Pix.Point(checkDrop, "RIGHT", leftRegion, "RIGHT", -20, 0)
        leftRegion._control = checkDrop
        CUI.RegisterWidgetRefresh(cbDDRefresh)
    end

    -- Display/alert settings as page rows (moved out of the old cog popup):
    -- every slot keeps the exact profile keys and side-effects the popup rows had;
    -- RefreshPage() is added only where a value gates another widget's disabled state.
    local sndValues, sndOrder = CUI.BuildSoundDropdownValues()
    local ttsValues, ttsOrder = VoiceChoices()

    -- Bar texture dropdown: identical catalog + SharedMedia merge +
    -- texture-preview rows as the CDM Tracking Bars "Bar Texture" dropdown.
    local barTexValues, barTexOrder = {}, {}
    do
        local mt = CUI._MovementBarTextures
        if mt then
            CUI.AppendSharedMediaTextures(mt.names, mt.order, nil, mt.lookup)
            for _, key in ipairs(mt.order) do
                if key ~= "---" then barTexValues[key] = mt.names[key] or key end
                barTexOrder[#barTexOrder + 1] = key
            end
            barTexValues._menuOpts = {
                itemHeight = 28,
                background = function(key) return mt.lookup[key] end,
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
            if key == "NONE" then return nil end
            return origAtlas and origAtlas(key)
        end
        mo.iconPressedAtlas = function(key)
            if key == "NONE" then return nil end
            return origPressed and origPressed(key)
        end
        mo.iconOnClick = function(key)
            if key == "NONE" then return end
            if origClick then origClick(key) end
        end
    end

    -- Text modes come in three fixed arrangements (the old free-form Text
    -- Format input is gone); the legacy stored "text" value maps to the
    -- duration-first arrangement it used to render.
    local function DMIsText()
        local val = ma.displayMode or "text"
        return val == "text" or val == "text_nd" or val == "text_dn" or val == "text_d"
    end
    local function DMSwatchesDisabled() return maOff() or ma.displayMode == "icon" end

    local dmRow
    dmRow, height = W:DualRow(hostFrame, cursorY, {
        type = "dropdown",
        text = "Display Mode",
        values = DISPLAY_MODE_VALUES,
        order = DISPLAY_MODE_ORDER,
        disabled = maOff,
        disabledTooltip = "Select a class above",
        rawTooltip = true,
        getValue = function()
            local val = ma.displayMode or "text"
            if val == "text" then val = "text_dn" end
            return val
        end,
        setValue = function(val)
            local wasText = DMIsText()
            ma.displayMode = val
            -- Crossing the text <-> bar/icon boundary re-seeds Text Size
            -- to that family's default (text 24, bar/icon 12).
            local isText = (val == "text_nd" or val == "text_dn" or val == "text_d")
            if wasText ~= isText then ma.textSize = isText and 24 or 12 end
            ApplyMovementAlert()
            CUI:RefreshPage()
        end,
    }, {
        type = "dropdown",
        text = "Bar Texture",
        values = barTexValues,
        order = barTexOrder,
        disabled = function() return maOff() or ma.displayMode ~= "bar" end,
        disabledTooltip = "Requires Bar display mode",
        rawTooltip = true,
        getValue = MaFieldOr("barTexture", "none"),
        setValue = MaFieldThen("barTexture"),
    })
    cursorY = cursorY - height

    -- Bar settings cog on the Bar Texture slot: Show Icon on Bar lives here.
    if not CUI._prebuilding then
        local region = dmRow._rightRegion
        local function BarCogOff() return maOff() or ma.displayMode ~= "bar" end
        CUI.BuildInlineCog(region, {
            title = "Bar Settings",
            rows = {
                {
                    type = "toggle",
                    label = "Show Icon on Bar",
                    get = function() return ma.barShowIcon ~= false end,
                    set = MaFieldThen("barShowIcon"),
                },
                {
                    type = "toggle",
                    label = "Show Duration Text",
                    get = function() return ma.barShowDuration ~= false end,
                    set = MaFieldThen("barShowDuration"),
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
    if not CUI._prebuilding then
        local leftRegion = dmRow._leftRegion

        -- Resize cog (nearest the control): Text Size / Icon Size, each gated to its mode.
        CUI.BuildInlineCog(leftRegion, {
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
                    get = MaFieldOr("textSize", 24),
                    set = MaFieldThen("textSize"),
                },
                {
                    type = "slider",
                    label = "Icon Size",
                    min = 16,
                    max = 128,
                    step = 1,
                    disabled = function() return ma.displayMode ~= "icon" end,
                    disabledTooltip = "Requires the Icon display mode",
                    rawTooltip = true,
                    get = MaFieldOr("iconSize", 40),
                    set = MaFieldThen("iconSize"),
                },
                -- View over the old numeric precision key: on = 1 decimal,
                -- off = whole seconds.
                {
                    type = "toggle",
                    label = "Show Decimal",
                    disabled = function() return ma.displayMode == "icon" end,
                    disabledTooltip = "Not used in Icon display mode",
                    rawTooltip = true,
                    -- tonumber guard: an older numeric-input build could store
                    -- precision as a string ("1"), and `"1" > 0` is a hard error
                    -- in Lua 5.1 -- it would throw here before set could run, so
                    -- the toggle silently did nothing until a value was written.
                    get = function() return (tonumber(ma.precision) or 1) > 0 end,
                    set = function(val)
                        ma.precision = val and 1 or 0
                        ApplyMovementAlert()
                    end,
                },
            },
            gap = 9,
            disabled = maOff,
            disabledTooltip = "Select an Enabled Class",
        })

        local dmAnchor = leftRegion._lastInline or leftRegion._control

        -- Class Colored swatch (nearest the cog)
        local dmClassSwatch, dmUpdateClassSwatch = CUI.BuildColorSwatch(
            leftRegion,
            leftRegion:GetFrameLevel() + 5,
            function()
                local _, class = UnitClass("player")
                local classColor = class and CUI.GetClassColor(class)
                if classColor then return classColor.r, classColor.g, classColor.b end
                return 1, 1, 1
            end,
            function() end,
            nil,
            20
        )
        Pix.Point(dmClassSwatch, "RIGHT", dmAnchor, "LEFT", -8, 0)
        dmClassSwatch:SetScript("OnClick", function()
            if DMSwatchesDisabled() then return end
            ma.textColorUseClass = true
            ApplyMovementAlert()
            CUI:RefreshPage()
        end)
        CUI.HoverTip(dmClassSwatch, "Class Colored")

        -- Custom Colored swatch (left of the class swatch): opens the picker;
        -- clicking while class color is active switches back to custom first.
        local dmSwatch, dmUpdateSwatch = CUI.BuildColorSwatch(
            leftRegion,
            leftRegion:GetFrameLevel() + 5,
            function() return ma.textColorR or 1, ma.textColorG or 1, ma.textColorB or 1 end,
            function(red, green, blue)
                ma.textColorR, ma.textColorG, ma.textColorB = red, green, blue
                ApplyMovementAlert()
            end,
            nil,
            20
        )
        Pix.Point(dmSwatch, "RIGHT", dmClassSwatch, "LEFT", -8, 0)
        leftRegion._lastInline = dmSwatch
        local dmOrigClick = dmSwatch:GetScript("OnClick")
        dmSwatch:SetScript("OnClick", function(self, ...)
            if DMSwatchesDisabled() then return end
            if ma.textColorUseClass then
                ma.textColorUseClass = false
                ApplyMovementAlert()
                CUI:RefreshPage()
                return
            end
            if dmOrigClick then dmOrigClick(self, ...) end
        end)
        CUI.HoverTip(dmSwatch, "Custom Colored")
        local function UpdateDmSwatches()
            local off = DMSwatchesDisabled()
            local isClass = ma.textColorUseClass == true
            dmSwatch:SetAlpha((off or isClass) and 0.3 or 1)
            dmClassSwatch:SetAlpha((isClass and not off) and 1 or 0.3)
        end
        CUI.RegisterWidgetRefresh(function()
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
    ttsRow, height = W:DualRow(hostFrame, cursorY, {
        type = "dropdown",
        text = "Sound",
        values = sndValues,
        order = sndOrder,
        disabled = function() return maOff() or ma.maTtsEnabled == true end,
        disabledTooltip = "Text-to-Speech is enabled and takes priority over Sound.",
        rawTooltip = true,
        getValue = MaFieldOr("maSoundKey", "none"),
        setValue = MaField("maSoundKey"),
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
            if not ma.maTtsEnabled then return "NONE" end
            return ma.maTtsVoiceID or 0
        end,
        setValue = function(val)
            if val == "NONE" then
                ma.maTtsEnabled = false
            else
                ma.maTtsEnabled = true
                ma.maTtsVoiceID = val
            end
            CUI:RefreshPage()
        end,
    })
    cursorY = cursorY - height

    if not CUI._prebuilding then
        local leftRegion = ttsRow._rightRegion
        local function TtsCogOff() return maOff() or not ma.maTtsEnabled end
        CUI.BuildInlineCog(leftRegion, {
            title = "Text-to-Speech Settings",
            rows = {
                {
                    type = "slider",
                    label = "TTS Volume",
                    min = 0,
                    max = 100,
                    step = 5,
                    get = MaFieldOr("maTtsVolume", 100),
                    set = MaField("maTtsVolume"),
                },
            },
            gap = 9,
            disabled = TtsCogOff,
            disabledTooltip = "Select a TTS Voice",
        })
    end

    _, height = W:Spacer(hostFrame, cursorY, 16)
    cursorY = cursorY - height

    -------------------------------------------------------------------------
    --  TRACKED SPELLS
    -------------------------------------------------------------------------
    _, height = W:SectionHeader(hostFrame, "TRACKED SPELLS", cursorY)
    cursorY = cursorY - height
    cursorY = cursorY - 6

    -- 4-column checkbox grid (same visual system as the AuraBuffReminders Auras
    -- section): class-colored spell name left, checkbox right, no ids. Lists every
    -- class's mobility spells (not just the player's), then any user-added spells
    -- (deletable via the X icon), then the + Add Spell button in the next free slot.
    -- Adds/removes rebuild the page so cells always re-flow sequentially with no gaps.
    do
        local GRID_COLS = 4
        local GRID_ROW_H = 50
        local GRID_BOX_SZ = 18
        local GRID_PAD = CUI.CONTENT_PAD or 16
        local GRID_SIDE_PAD = 20
        local playerClass = select(2, UnitClass("player"))
        if not ma.spellOverrides then ma.spellOverrides = {} end

        local function OnGridChanged()
            if CUI._RebuildMovementSpellLookup then CUI._RebuildMovementSpellLookup() end
            if CUI._CacheMovementSpells then CUI._CacheMovementSpells() end
            ApplyMovementAlert()
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
            local fvSkip = CUI.IS_FOREVER
                and (primary == 781 or not CUI.FOREVER_CLASS_SPEC[preset.class])
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
                    local entry = {
                        label = details.name,
                        classToken = preset.class,
                        spellId = primary,
                        ids = cellIds,
                        getVal = function()
                            local o = ma.spellOverrides[primary]
                            if o and o.enabled ~= nil then return o.enabled ~= false end
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
                    byClassName[dupKey] = entry
                    itemList[#itemList + 1] = entry
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
                label = (details and details.name) or CUI.L("Unknown Spell"),
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
                    if shade then shade.enabled = val end
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
            Pix.Point(rowFrame, "TOPLEFT", hostFrame, "TOPLEFT", GRID_PAD, cursorY - row * GRID_ROW_H)
            rowFrame._skipRowDivider = true
            CUI.RowBg(rowFrame, hostFrame)

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

            for col = 0, GRID_COLS - 1 do
                local position = row * GRID_COLS + col + 1
                local entry = itemList[position]
                if not entry then break end

                local cell = CreateFrame("Frame", nil, rowFrame)
                cell:SetSize(colW, GRID_ROW_H)
                cell:SetPoint("TOPLEFT", rowFrame, "TOPLEFT", col * colW, 0)

                if entry.addButton then
                    -- Keybind-button style (dropdown-look bg/border with the
                    -- hover brighten), centered in its grid slot.
                    local addBtn = CreateFrame("Button", nil, cell)
                    Pix.Size(addBtn, 126, 29)
                    addBtn:SetPoint("CENTER", cell, "CENTER", 0, 0)
                    addBtn:SetFrameLevel(cell:GetFrameLevel() + 2)
                    local addBg = CUI.SolidTex(
                        addBtn,
                        "BACKGROUND",
                        CUI.DD_BG_R,
                        CUI.DD_BG_G,
                        CUI.DD_BG_B,
                        CUI.DD_BG_A
                    )
                    addBg:SetAllPoints()
                    local addBrd = CUI.MakeRoundedBorder(addBtn, 1, 1, 1, CUI.DD_BRD_A, addBg)
                    local addLbl = CUI.MakeFont(addBtn, 12, nil, 1, 1, 1)
                    addLbl:SetAlpha(CUI.DD_TXT_A)
                    addLbl:SetPoint("CENTER")
                    addLbl:SetText(CUI.L("+ Add Spell"))
                    addBtn:SetScript("OnEnter", function()
                        addBg:SetColorTexture(
                            CUI.DD_BG_R,
                            CUI.DD_BG_G,
                            CUI.DD_BG_B,
                            CUI.DD_BG_HA
                        )
                        if addBrd and addBrd.SetColor then addBrd:SetColor(1, 1, 1, 0.3) end
                    end)
                    addBtn:SetScript("OnLeave", function()
                        addBg:SetColorTexture(
                            CUI.DD_BG_R,
                            CUI.DD_BG_G,
                            CUI.DD_BG_B,
                            CUI.DD_BG_A
                        )
                        if addBrd and addBrd.SetColor then addBrd:SetColor(1, 1, 1, CUI.DD_BRD_A) end
                    end)
                    addBtn:SetScript("OnClick", function()
                        ShowAddSpellPopup(function(spellId)
                            ma.spellOverrides[spellId] = ma.spellOverrides[spellId]
                                or { enabled = true, class = playerClass }
                            OnGridChanged()
                            CUI:RefreshPage(true)
                        end)
                    end)
                else
                    local cr, cg, checkBtn = 1, 1, 1
                    if entry.classToken then
                        local classColor = RAID_CLASS_COLORS and RAID_CLASS_COLORS[entry.classToken]
                        if classColor then
                            cr, cg, checkBtn = classColor.r, classColor.g, classColor.b
                        end
                    end

                    local labelText = CUI.MakeFont(cell, 13, nil, cr, cg, checkBtn)
                    labelText:SetPoint("LEFT", cell, "LEFT", GRID_SIDE_PAD, 0)
                    labelText:SetWidth(colW - GRID_SIDE_PAD * 2 - GRID_BOX_SZ - 6)
                    labelText:SetJustifyH("LEFT")
                    labelText:SetMaxLines(2)
                    labelText:SetText(entry.label)

                    local boxFrame = CreateFrame("Frame", nil, cell)
                    boxFrame:SetSize(GRID_BOX_SZ, GRID_BOX_SZ)
                    boxFrame:SetPoint("RIGHT", cell, "RIGHT", -GRID_SIDE_PAD, 0)
                    local boxBg = boxFrame:CreateTexture(nil, "BACKGROUND")
                    boxBg:SetAllPoints()
                    boxBg:SetColorTexture(0.114, 0.106, 0.099, 1)
                    if boxBg.SetSnapToPixelGrid then
                        boxBg:SetSnapToPixelGrid(false)
                        boxBg:SetTexelSnappingBias(0)
                    end
                    local boxBrd = CUI.MakeRoundedBorder(boxFrame, 0.224, 0.215, 0.207, 0.6, boxBg)
                    local check = boxFrame:CreateTexture(nil, "ARTWORK")
                    check:SetPoint("TOPLEFT", boxFrame, "TOPLEFT", 3, -3)
                    check:SetPoint("BOTTOMRIGHT", boxFrame, "BOTTOMRIGHT", -3, 3)
                    check:SetColorTexture(ACC.r, ACC.g, ACC.b, 1)
                    CUI.RoundBody(boxFrame, check, 1)
                    if check.SetSnapToPixelGrid then
                        check:SetSnapToPixelGrid(false)
                        check:SetTexelSnappingBias(0)
                    end

                    local button = CreateFrame("Button", nil, cell)
                    button:SetAllPoints(cell)
                    button:SetFrameLevel(cell:GetFrameLevel() + 2)
                    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")

                    -- A cell is disabled while its class is unchecked in the
                    -- Enable Movement Alerts dropdown (tracking can never
                    -- fire for it). The X delete on custom cells stays live
                    -- so stale entries can still be cleaned up.
                    local function ClassCellOff()
                        local ec = ma.enabledClasses
                        if not ec then return true end
                        if entry.classToken then return not ec[entry.classToken] end
                        return false
                    end

                    local function PaintCell()
                        local dis = ClassCellOff()
                        local on = entry.getVal()
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
                    PaintCell()

                    button:SetScript("OnClick", function(_, mouseButton)
                        if ClassCellOff() then return end
                        if mouseButton == "RightButton" then
                            local shade = ma.spellOverrides[entry.spellId]
                            ShowCustomTextPopup(entry.label, shade and shade.customText or "", function(txt)
                                for i = 1, #entry.ids do
                                    local ident = entry.ids[i]
                                    ma.spellOverrides[ident] = ma.spellOverrides[ident] or {}
                                    ma.spellOverrides[ident].customText = (txt ~= "") and txt or nil
                                end
                                if CUI._CacheMovementSpells then CUI._CacheMovementSpells() end
                                ApplyMovementAlert()
                            end)
                            return
                        end
                        entry.setVal(not entry.getVal())
                        PaintCell()
                        OnGridChanged()
                    end)
                    button:SetScript("OnEnter", function()
                        if ClassCellOff() then
                            CUI.ShowWidgetTooltip(
                                cell,
                                CUI.DisabledTooltip("Enable this class above")
                            )
                            return
                        end
                        if not entry.getVal() then labelText:SetAlpha(0.8) end
                        CUI.ShowWidgetTooltip(cell, CUI.L("Right-Click to set custom alert text."))
                    end)
                    button:SetScript("OnLeave", function()
                        PaintCell()
                        CUI.HideWidgetTooltip()
                    end)

                    CUI.RegisterWidgetRefresh(PaintCell)

                    if entry.custom then
                        local delBtn = CreateFrame("Button", nil, cell)
                        delBtn:SetSize(12, 12)
                        delBtn:SetPoint("TOPRIGHT", cell, "TOPRIGHT", -4, -4)
                        delBtn:SetFrameLevel(button:GetFrameLevel() + 2)
                        local delIcon = delBtn:CreateTexture(nil, "OVERLAY")
                        delIcon:SetAllPoints()
                        delIcon:SetTexture("Interface\\AddOns\\CludesUI\\media\\icons\\cui-close.png")
                        delIcon:SetAlpha(0.4)
                        delBtn:SetScript("OnEnter", function() delIcon:SetAlpha(0.9) end)
                        delBtn:SetScript("OnLeave", function() delIcon:SetAlpha(0.4) end)
                        delBtn:SetScript("OnClick", function()
                            ma.spellOverrides[entry.spellId] = nil
                            OnGridChanged()
                            CUI:RefreshPage(true)
                        end)
                    end
                end
            end
        end
        cursorY = cursorY - totalRows * GRID_ROW_H
    end

    _, height = W:Spacer(hostFrame, cursorY, 16)
    cursorY = cursorY - height

    -------------------------------------------------------------------------
    --  EXTRA TRACKING
    -------------------------------------------------------------------------
    heading, height = W:SectionHeader(hostFrame, "EXTRA TRACKING", cursorY)
    cursorY = cursorY - height

    -- The two sibling trackers' master toggles, each carrying its full settings cog.
    local function tsOff() return not ma.tsEnabled end
    local function gwOff() return not ma.gwEnabled end
    -- Time Spiral is the section's first mover, so the header's button takes
    -- it; the Gateway Shard mover stays reachable through its cog's footer.
    CUI.BuildSectionUnlockJump(
        heading,
        { key = "CUI_TimeSpiralAlert", disabled = tsOff, disabledTooltip = "Enable Time Spiral Tracker" }
    )

    local extraRow
    extraRow, height = W:DualRow(hostFrame, cursorY, {
        type = "toggle",
        text = "Enable Time Spiral Tracker",
        tooltip = "Flashes a banner whenever a tracked mobility spell's cooldown is proc-reset. Use Layout Mode to reposition/resize.",
        getValue = function() return ma.tsEnabled == true end,
        setValue = function(val)
            ma.tsEnabled = val
            if CUI._UpdateMovementAlertEvents then CUI._UpdateMovementAlertEvents() end
            ApplyMovementAlert()
            CUI:RefreshPage()
        end,
    }, {
        type = "toggle",
        text = "Enable Gateway Shard Alert",
        tooltip = "Warlock only. Alerts when your Gateway Control Shard is usable. Use Layout Mode to reposition/resize.",
        getValue = function() return ma.gwEnabled == true end,
        setValue = function(val)
            ma.gwEnabled = val
            if CUI._UpdateMovementAlertEvents then CUI._UpdateMovementAlertEvents() end
            ApplyMovementAlert()
            CUI:RefreshPage()
        end,
    })
    cursorY = cursorY - height

    -- Time Spiral settings cog (left slot)
    if not CUI._prebuilding then
        local leftRegion = extraRow._leftRegion
        local sndValues2, sndOrder2 = CUI.BuildSoundDropdownValues()
        local ttsValues2, ttsOrder2 = VoiceChoices()
        CUI.BuildInlineCog(leftRegion, {
            title = "Time Spiral Settings",
            minWidth = 300,
            rows = {
                {
                    type = "input",
                    label = "Text Format",
                    get = MaFieldOr("tsTextFormat", "FREE MOVEMENT\\n%.1f"),
                    set = MaFieldThen("tsTextFormat"),
                },
                {
                    type = "colorpicker",
                    label = "Color",
                    disabled = function() return ma.tsColorUseClass end,
                    disabledTooltip = "Disable Class Color to pick a custom color.",
                    rawTooltip = true,
                    get = function() return ma.tsColorR or 0.53, ma.tsColorG or 1, ma.tsColorB or 0 end,
                    set = function(red, green, blue)
                        ma.tsColorR, ma.tsColorG, ma.tsColorB = red, green, blue
                        ApplyMovementAlert()
                    end,
                },
                {
                    type = "toggle",
                    label = "Use Class Color",
                    get = function() return ma.tsColorUseClass == true end,
                    set = MaFieldThen("tsColorUseClass"),
                },
                {
                    type = "dropdown",
                    label = "Sound",
                    values = sndValues2,
                    order = sndOrder2,
                    disabled = function() return ma.tsTtsEnabled == true end,
                    disabledTooltip = "Text-to-Speech is enabled below and takes priority over Sound.",
                    rawTooltip = true,
                    get = MaFieldOr("tsSoundKey", "none"),
                    set = MaField("tsSoundKey"),
                },
                {
                    type = "toggle",
                    label = "Use Text-to-Speech",
                    get = function() return ma.tsTtsEnabled == true end,
                    set = MaField("tsTtsEnabled"),
                },
                {
                    type = "dropdown",
                    label = "TTS Voice",
                    values = ttsValues2,
                    order = ttsOrder2,
                    disabled = function() return not ma.tsTtsEnabled end,
                    disabledTooltip = "Enable Text-to-Speech first",
                    rawTooltip = true,
                    get = MaFieldOr("tsTtsVoiceID", 0),
                    set = MaField("tsTtsVoiceID"),
                },
                {
                    type = "input",
                    label = "TTS Message",
                    disabled = function() return not ma.tsTtsEnabled end,
                    disabledTooltip = "Enable Text-to-Speech first",
                    rawTooltip = true,
                    get = MaFieldOr("tsTtsMessage", "Free movement"),
                    set = MaField("tsTtsMessage"),
                },
                {
                    type = "slider",
                    label = "TTS Volume",
                    min = 0,
                    max = 100,
                    step = 5,
                    disabled = function() return not ma.tsTtsEnabled end,
                    get = MaFieldOr("tsTtsVolume", 100),
                    set = MaField("tsTtsVolume"),
                },
            },
            footer = { unlockKey = "CUI_TimeSpiralAlert" },
            gap = 9,
            disabled = tsOff,
            disabledTooltip = "Enable Time Spiral Tracker",
        })
    end

    -- Gateway Shard settings cog (right slot); Combat Only lives in here.
    if not CUI._prebuilding then
        local region = extraRow._rightRegion
        local sndValues2, sndOrder2 = CUI.BuildSoundDropdownValues()
        local ttsValues2, ttsOrder2 = VoiceChoices()
        CUI.BuildInlineCog(region, {
            title = "Gateway Shard Settings",
            minWidth = 300,
            rows = {
                {
                    type = "toggle",
                    label = "Combat Only",
                    tooltip = "Only show the alert while in combat.",
                    get = function() return ma.gwCombatOnly == true end,
                    set = MaFieldThen("gwCombatOnly"),
                },
                {
                    type = "input",
                    label = "Text",
                    get = MaFieldOr("gwText", "GATEWAY READY"),
                    set = MaFieldThen("gwText"),
                },
                {
                    type = "colorpicker",
                    label = "Color",
                    disabled = function() return ma.gwColorUseClass end,
                    disabledTooltip = "Disable Class Color to pick a custom color.",
                    rawTooltip = true,
                    get = function() return ma.gwColorR or 0.7, ma.gwColorG or 0, ma.gwColorB or 1 end,
                    set = function(red, green, blue)
                        ma.gwColorR, ma.gwColorG, ma.gwColorB = red, green, blue
                        ApplyMovementAlert()
                    end,
                },
                {
                    type = "toggle",
                    label = "Use Class Color",
                    get = function() return ma.gwColorUseClass == true end,
                    set = MaFieldThen("gwColorUseClass"),
                },
                {
                    type = "dropdown",
                    label = "Sound",
                    values = sndValues2,
                    order = sndOrder2,
                    disabled = function() return ma.gwTtsEnabled == true end,
                    disabledTooltip = "Text-to-Speech is enabled below and takes priority over Sound.",
                    rawTooltip = true,
                    get = MaFieldOr("gwSoundKey", "none"),
                    set = MaField("gwSoundKey"),
                },
                {
                    type = "toggle",
                    label = "Use Text-to-Speech",
                    get = function() return ma.gwTtsEnabled == true end,
                    set = MaField("gwTtsEnabled"),
                },
                {
                    type = "dropdown",
                    label = "TTS Voice",
                    values = ttsValues2,
                    order = ttsOrder2,
                    disabled = function() return not ma.gwTtsEnabled end,
                    disabledTooltip = "Enable Text-to-Speech first",
                    rawTooltip = true,
                    get = MaFieldOr("gwTtsVoiceID", 0),
                    set = MaField("gwTtsVoiceID"),
                },
                {
                    type = "input",
                    label = "TTS Message",
                    disabled = function() return not ma.gwTtsEnabled end,
                    disabledTooltip = "Enable Text-to-Speech first",
                    rawTooltip = true,
                    get = MaFieldOr("gwTtsMessage", "Gateway ready"),
                    set = MaField("gwTtsMessage"),
                },
                {
                    type = "slider",
                    label = "TTS Volume",
                    min = 0,
                    max = 100,
                    step = 5,
                    disabled = function() return not ma.gwTtsEnabled end,
                    get = MaFieldOr("gwTtsVolume", 100),
                    set = MaField("gwTtsVolume"),
                },
            },
            footer = { unlockKey = "CUI_GatewayShardAlert" },
            gap = 9,
            disabled = gwOff,
            disabledTooltip = "Enable Gateway Shard Alert",
        })
    end

    _, height = W:Spacer(hostFrame, cursorY, 20)
    cursorY = cursorY - height

    return math.abs(cursorY)
end

_G._CUI_BuildMovementAlertPage = BuildMovementAlertPage
