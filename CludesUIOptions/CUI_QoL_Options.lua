if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-------------------------------------------------------------------------------
--  CUI_QoL_Options.lua
--  Registers the Quality of Life sidebar addon with its two tabs:
--    * Quality of Life -- general QoL features (built by parent general options)
--    * Cursor          -- cursor skin (built by CUI_QoL_Cursor_Options.lua)
-------------------------------------------------------------------------------
-- Page names are DEEP-LINK IDENTIFIERS, not just tab labels: every
-- NavigateToElementSettings tuple (_ELEMENT_SETTINGS_MAP, What's New nav)
-- and every GetActivePage() comparison carries them as strings and fails
-- SILENTLY on a mismatch. Renaming one means updating every consumer.
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
-- Row accessors over Account(): a key read (or its default) and written.
local function AccountField(settingKey)
    return function(value) Account()[settingKey] = value end
end
local function AccountFieldThen(settingKey)
    return function(value)
        Account()[settingKey] = value
        CUI:RefreshPage()
    end
end
local function AccountFieldThen2(settingKey)
    return function(value)
        Account()[settingKey] = value
        if CUI._applyTargetDistanceFrame then CUI._applyTargetDistanceFrame() end
    end
end

local PAGE_QOL = "QoL"
local PAGE_CURSOR = "Cursor"
local PAGE_UPGCALC = "Upgrader"
local PAGE_SHIFTER = "Shifter"
local PAGE_MOVEMENT = "MoveAlert"
local PAGE_RAIDTOOLS = "Raid Tools"

-------------------------------------------------------------------------------
--  Hide Item Transforms picker popup
--  Item checklist styled after the spec-assign popup: dimmed backdrop, one
--  column per category, Check/Uncheck All links and a green Apply button.
--  Edits are staged and only written on Apply; clicking outside or pressing
--  Escape discards them. Item data comes from CludesUI.HideTransformsData
--  (owned by the runtime in CludesUIQoL.lua).
-------------------------------------------------------------------------------
local transformsPopup
local transformsStaged = {}

local function ShowTransformsPopup()
    local payload = CUI.HideTransformsData
    if not payload then return end

    if not transformsPopup then
        local FONT = CUI._font or "Interface\\AddOns\\CludesUI\\media\\fonts\\Expressway.TTF"
        local ACC = CUI.CLUDES_GREEN or { r = 0.30, g = 0.79, b = 0.94 }
        local Pix = CUI.PanelPP
        local COL_W, COL_GAP = 190, 12
        local CONTENT_LEFT, CONTENT_RIGHT, CONTENT_TOP = 41, 36, 118
        local HDR_H, ROW_H = 30, 26
        local numCols = #payload.order

        -- Group items per category; the tallest column drives the popup height.
        local catItems = {}
        for _, entry in ipairs(payload.items) do
            catItems[entry.cat] = catItems[entry.cat] or {}
            catItems[entry.cat][#catItems[entry.cat] + 1] = entry
        end
        local maxRows = 0
        for _, category in ipairs(payload.order) do
            local num = catItems[category] and #catItems[category] or 0
            if num > maxRows then maxRows = num end
        end

        local POPUP_W = CONTENT_LEFT + CONTENT_RIGHT + numCols * COL_W + (numCols - 1) * COL_GAP
        local POPUP_H = CONTENT_TOP + HDR_H + 4 + maxRows * ROW_H + 24 + 39 + 38
        local ppScale = CUI.GetPopupScale() or 1

        local shade = CreateFrame("Frame", nil, UIParent)
        shade:SetFrameStrata("FULLSCREEN_DIALOG")
        shade:SetAllPoints(UIParent)
        shade:EnableMouse(true)
        shade:EnableMouseWheel(true)
        shade:SetScript("OnMouseWheel", function() end)
        shade:Hide()
        shade:SetScale(ppScale)
        local dimTex = shade:CreateTexture(nil, "BACKGROUND")
        dimTex:SetAllPoints()
        dimTex:SetColorTexture(0, 0, 0, 0.25)

        local dialog = CreateFrame("Frame", nil, shade)
        dialog:SetScale(CUI.PopupBump(1))
        dialog:SetFrameStrata("FULLSCREEN_DIALOG")
        dialog:SetFrameLevel(shade:GetFrameLevel() + 10)
        dialog:SetSize(POPUP_W, POPUP_H)
        dialog:SetPoint("CENTER", CUI._mainFrame or UIParent, "CENTER", 0, 0)
        dialog:EnableMouse(true)
        local popFrame = CUI._popupFrames
        if popFrame then popFrame[#popFrame + 1] = { popup = dialog, dimmer = shade } end

        local backdrop = dialog:CreateTexture(nil, "BACKGROUND")
        backdrop:SetAllPoints()
        backdrop:SetColorTexture(0.062, 0.070, 0.082, 1)
        CUI.MakeRoundedBorder(dialog, 1, 1, 1, 0.15, backdrop)

        local title = dialog:CreateFontString(nil, "OVERLAY")
        title:SetFont(FONT, 22, "")
        title:SetTextColor(1, 1, 1, 1)
        title:SetPoint("TOP", dialog, "TOP", 0, -32)
        title:SetText(CUI.L("Hide Item Transforms"))

        local subMenu = dialog:CreateFontString(nil, "OVERLAY")
        subMenu:SetFont(FONT, 14, "")
        subMenu:SetTextColor(1, 1, 1, 0.45)
        subMenu:SetPoint("TOP", title, "BOTTOM", 0, -8)
        subMenu:SetText(CUI.L("Checked transforms are removed automatically when applied to you."))

        local rowList = {}
        local function RefreshRows()
            for _, line in ipairs(rowList) do
                if transformsStaged[line._key] then
                    line._check:Show()
                    line._boxBorder:SetColor(ACC.r, ACC.g, ACC.b, 0.8)
                else
                    line._check:Hide()
                    line._boxBorder:SetColor(0.4, 0.4, 0.4, 0.6)
                end
            end
        end
        dialog._refreshRows = RefreshRows

        -- Check All / Uncheck All links
        local function SetAll(val)
            for _, entry in ipairs(payload.items) do
                transformsStaged[entry.key] = val
            end
            RefreshRows()
        end
        local checkAllBtn = CreateFrame("Button", nil, dialog)
        checkAllBtn:SetFrameLevel(dialog:GetFrameLevel() + 2)
        local checkAllText = checkAllBtn:CreateFontString(nil, "OVERLAY")
        checkAllText:SetFont(FONT, 14, "")
        checkAllText:SetText(CUI.L("Check All"))
        checkAllText:SetTextColor(1, 1, 1, 0.45)
        checkAllText:SetPoint("CENTER")
        checkAllBtn:SetSize(checkAllText:GetStringWidth() + 4, 20)
        checkAllBtn:SetPoint("TOPLEFT", dialog, "TOPLEFT", CONTENT_LEFT, -(CONTENT_TOP - 22))
        checkAllBtn:SetScript("OnEnter", function() checkAllText:SetTextColor(1, 1, 1, 0.80) end)
        checkAllBtn:SetScript("OnLeave", function() checkAllText:SetTextColor(1, 1, 1, 0.45) end)
        checkAllBtn:SetScript("OnClick", function() SetAll(true) end)

        local linkDivider = dialog:CreateTexture(nil, "OVERLAY", nil, 7)
        linkDivider:SetColorTexture(1, 1, 1, 0.18)
        if linkDivider.SetSnapToPixelGrid then
            linkDivider:SetSnapToPixelGrid(false)
            linkDivider:SetTexelSnappingBias(0)
        end
        linkDivider:SetPoint("LEFT", checkAllBtn, "RIGHT", 10, 0)
        linkDivider:SetWidth(1)
        linkDivider:SetHeight(12)

        local uncheckAllBtn = CreateFrame("Button", nil, dialog)
        uncheckAllBtn:SetFrameLevel(dialog:GetFrameLevel() + 2)
        local uncheckAllText = uncheckAllBtn:CreateFontString(nil, "OVERLAY")
        uncheckAllText:SetFont(FONT, 14, "")
        uncheckAllText:SetText(CUI.L("Uncheck All"))
        uncheckAllText:SetTextColor(1, 1, 1, 0.45)
        uncheckAllText:SetPoint("CENTER")
        uncheckAllBtn:SetSize(uncheckAllText:GetStringWidth() + 4, 20)
        uncheckAllBtn:SetPoint("LEFT", checkAllBtn, "RIGHT", 20, 0)
        uncheckAllBtn:SetScript("OnEnter", function() uncheckAllText:SetTextColor(1, 1, 1, 0.80) end)
        uncheckAllBtn:SetScript("OnLeave", function() uncheckAllText:SetTextColor(1, 1, 1, 0.45) end)
        uncheckAllBtn:SetScript("OnClick", function() SetAll(false) end)

        -- Category columns
        for colIdx, category in ipairs(payload.order) do
            local colX = CONTENT_LEFT + (colIdx - 1) * (COL_W + COL_GAP)
            local heading = dialog:CreateFontString(nil, "OVERLAY")
            heading:SetFont(FONT, 17, "")
            heading:SetTextColor(1, 1, 1, 0.7)
            heading:SetPoint("TOPLEFT", dialog, "TOPLEFT", colX + 4, -(CONTENT_TOP + 8))
            heading:SetText(CUI.L(payload.labels[category] or category))

            local itemList = catItems[category] or {}
            for idx, entry in ipairs(itemList) do
                local line = CreateFrame("Button", nil, dialog)
                line:SetSize(COL_W, ROW_H)
                line:SetPoint(
                    "TOPLEFT",
                    dialog,
                    "TOPLEFT",
                    colX,
                    -(CONTENT_TOP + HDR_H + 4 + (idx - 1) * ROW_H)
                )
                line._key = entry.key

                local boxFrame = CreateFrame("Frame", nil, line)
                boxFrame:SetSize(18, 18)
                boxFrame:SetPoint("LEFT", line, "LEFT", 4, 0)
                boxFrame:SetFrameLevel(line:GetFrameLevel() + 1)
                local boxBg = boxFrame:CreateTexture(nil, "BACKGROUND")
                boxBg:SetAllPoints()
                boxBg:SetColorTexture(0.114, 0.106, 0.099, 1)
                line._boxBorder = CUI.MakeRoundedBorder(boxFrame, 0.4, 0.4, 0.4, 0.6, boxBg)
                local check = boxFrame:CreateTexture(nil, "ARTWORK")
                check:SetPoint("TOPLEFT", boxFrame, "TOPLEFT", 3, -3)
                check:SetPoint("BOTTOMRIGHT", boxFrame, "BOTTOMRIGHT", -3, 3)
                check:SetColorTexture(ACC.r, ACC.g, ACC.b, 1)
                CUI.RoundBody(boxFrame, check, 1)
                line._check = check

                local labelFS = line:CreateFontString(nil, "OVERLAY")
                labelFS:SetFont(FONT, 13, "")
                labelFS:SetPoint("LEFT", boxFrame, "RIGHT", 8, 0)
                labelFS:SetPoint("RIGHT", line, "RIGHT", -2, 0)
                labelFS:SetJustifyH("LEFT")
                labelFS:SetWordWrap(false)
                labelFS:SetTextColor(1, 1, 1, 0.65)
                labelFS:SetText(CUI.L(entry.label))

                line:SetScript("OnEnter", function() labelFS:SetTextColor(1, 1, 1, 0.95) end)
                line:SetScript("OnLeave", function() labelFS:SetTextColor(1, 1, 1, 0.65) end)
                line:SetScript("OnClick", function()
                    transformsStaged[entry.key] = not transformsStaged[entry.key]
                    RefreshRows()
                end)
                rowList[#rowList + 1] = line
            end
        end

        -- Apply button (green, spec-popup style)
        local applyButton = CreateFrame("Button", nil, dialog)
        applyButton:SetFrameLevel(dialog:GetFrameLevel() + 2)
        applyButton:SetSize(200, 39)
        applyButton:SetPoint("BOTTOM", dialog, "BOTTOM", 0, 38)
        local applyBg = applyButton:CreateTexture(nil, "BACKGROUND")
        applyBg:SetAllPoints()
        applyBg:SetColorTexture(0.062, 0.070, 0.082, 0.92)
        local applyBrd = CUI.MakeRoundedBorder(applyButton, ACC.r, ACC.g, ACC.b, 0.9, applyBg)
        local applyLbl = applyButton:CreateFontString(nil, "OVERLAY")
        applyLbl:SetFont(FONT, 16, "")
        applyLbl:SetPoint("CENTER")
        applyLbl:SetText(CUI.L("Apply"))
        applyLbl:SetTextColor(ACC.r, ACC.g, ACC.b, 0.9)
        applyButton:SetScript("OnEnter", function()
            applyLbl:SetTextColor(ACC.r, ACC.g, ACC.b, 1)
            applyBrd:SetColor(ACC.r, ACC.g, ACC.b, 1)
        end)
        applyButton:SetScript("OnLeave", function()
            applyLbl:SetTextColor(ACC.r, ACC.g, ACC.b, 0.9)
            applyBrd:SetColor(ACC.r, ACC.g, ACC.b, 0.9)
        end)
        applyButton:SetScript("OnClick", function()
            Account().hideTransformItems = CludesUIDB.hideTransformItems or {}
            local tbl = CludesUIDB.hideTransformItems
            for _, entry in ipairs(payload.items) do
                local staged = transformsStaged[entry.key] and true or false
                if staged == not entry.defaultOff then
                    tbl[entry.key] = nil -- matches the per-key default
                else
                    tbl[entry.key] = staged -- stored deviations only
                end
            end
            if CUI._applyHideTransforms then CUI._applyHideTransforms() end
            shade:Hide()
        end)

        -- Click outside or Escape discards staged edits
        shade:SetScript("OnMouseDown", function(self)
            if not dialog:IsMouseOver() then self:Hide() end
        end)
        CUI.PopupTakeKeys(dialog, shade)
        dialog:SetScript("OnKeyDown", function(self, settingKey)
            if InCombatLockdown() then return end
            if settingKey == "ESCAPE" then
                self:SetPropagateKeyboardInput(false)
                shade:Hide()
            else
                self:SetPropagateKeyboardInput(true)
            end
        end)

        dialog._dimmer = shade
        transformsPopup = dialog
    end

    -- Seed the staged state from the saved settings, then show
    for _, entry in ipairs(payload.items) do
        transformsStaged[entry.key] = CUI.GetHideTransformItem(entry.key) and true or false
    end
    transformsPopup._refreshRows()
    transformsPopup._dimmer:Show()
end

-------------------------------------------------------------------------------
--  SELF COMBAT TEXT section of the QoL page (runtime:
--  CludesUIQoL_SelfCombatText.lua, settings through its SCT_Get/SCT_Set)
-------------------------------------------------------------------------------
local function BuildSelfCombatTextSection(hostFrame, cursorY)
    local W = CUI.Widgets
    local qns = CUI._ModuleNS["CludesUIQoL"]
    local SCTGet, SCTSet = qns.SCT_Get, qns.SCT_Set
    local _, height, heading

    heading, height = W:SectionHeader(hostFrame, "SELF COMBAT TEXT", cursorY)
    cursorY = cursorY - height

    local function sctOff() return not SCTGet("enabled") end
    CUI.BuildSectionUnlockJump(
        heading,
        { key = "CUI_SelfCombatText", disabled = sctOff, disabledTooltip = "Self Combat Text" }
    )
    local function sctToggle(textValue, settingKey)
        return {
            type = "toggle",
            text = textValue,
            disabled = sctOff,
            disabledTooltip = "Self Combat Text",
            getValue = function() return SCTGet(settingKey) end,
            setValue = function(val)
                SCTSet(settingKey, val)
                CUI:RefreshPage()
            end,
        }
    end
    local function sctDropdown(textValue, settingKey, values, sequence)
        return {
            type = "dropdown",
            text = textValue,
            values = values,
            order = sequence,
            disabled = sctOff,
            disabledTooltip = "Self Combat Text",
            getValue = function() return SCTGet(settingKey) end,
            setValue = function(val) SCTSet(settingKey, val) end,
        }
    end
    -- A category toggle's colour, locked while the feature or that category is off
    local function sctColorSwatch(region, settingKey, colorKey, labelText)
        if CUI._prebuilding then return end
        CUI.BuildInlineSwatches(region, {
            {
                disabled = function() return sctOff() or not SCTGet(settingKey) end,
                disabledTooltip = function() return sctOff() and "Self Combat Text" or labelText end,
                getValue = function()
                    local color = SCTGet(colorKey)
                    return color.r, color.g, color.b
                end,
                setValue = function(red, green, blue) SCTSet(colorKey, { r = red, g = green, b = blue }) end,
            },
        })
    end

    local sctRow
    sctRow, height = W:DualRow(hostFrame, cursorY, {
        type = "toggle",
        text = "Self Combat Text",
        tooltip = "Shows your damage taken, healing, avoids and combat enter/leave above the player frame instead of Blizzard's combat text, whose other messages are hidden while this is on. Move it in Edit Layout.",
        getValue = function() return not sctOff() end,
        setValue = CUI.SectionToggleSetValue(function(val) SCTSet("enabled", val) end),
    }, {
        type = "slider",
        text = "Combat Text Size",
        min = 10,
        max = 48,
        step = 1,
        disabled = sctOff,
        disabledTooltip = "Self Combat Text",
        getValue = function() return SCTGet("size") end,
        setValue = function(val) SCTSet("size", val) end,
    })
    cursorY = cursorY - height
    if not CUI._prebuilding then
        CUI.BuildInlineCog(sctRow._leftRegion, {
            disabled = sctOff,
            disabledTooltip = "Self Combat Text",
            title = "Self Combat Text",
            rows = {
                {
                    type = "slider",
                    label = "Scroll Distance",
                    min = 20,
                    max = 300,
                    step = 5,
                    get = function() return SCTGet("rise") end,
                    set = function(val) SCTSet("rise", val) end,
                },
                {
                    type = "slider",
                    label = "Scroll Duration",
                    min = 0.5,
                    max = 4,
                    step = 0.1,
                    get = function() return SCTGet("duration") end,
                    set = function(val) SCTSet("duration", val) end,
                },
                {
                    type = "slider",
                    label = "Crit Scale",
                    min = 1,
                    max = 3,
                    step = 0.1,
                    get = function() return SCTGet("critScale") end,
                    set = function(val) SCTSet("critScale", val) end,
                },
                {
                    type = "toggle",
                    label = "Stagger Hits",
                    tooltip = "Spaces out hits that land together so none hides another.",
                    get = function() return SCTGet("stagger") end,
                    set = function(val) SCTSet("stagger", val) end,
                },
            },
        })
    end

    -- Section gate: the rows below exist only while Self Combat Text is on (the
    -- toggle's SectionToggleSetValue rebuilds the page).
    if sctOff() then return cursorY end

    _, height = W:DualRow(
        hostFrame,
        cursorY,
        sctDropdown(
            "Animation",
            "anim",
            { straight = "Straight", fountain = "Fountain", static = "Static" },
            { "straight", "fountain", "static" }
        ),
        sctDropdown("Scroll Direction", "direction", { up = "Up", down = "Down" }, { "up", "down" })
    )
    cursorY = cursorY - height

    local fontValues, fontOrder = CUI.BuildFontDropdownData()
    fontValues["__combat"] = { text = "Combat Text Font" }
    table.insert(fontOrder, 1, "__combat")
    _, height = W:DualRow(
        hostFrame,
        cursorY,
        sctDropdown("Font", "font", fontValues, fontOrder),
        sctDropdown(
            "Outline",
            "outline",
            { NONE = "None", OUTLINE = "Outline", THICKOUTLINE = "Thick Outline" },
            { "NONE", "OUTLINE", "THICKOUTLINE" }
        )
    )
    cursorY = cursorY - height

    _, height = W:DualRow(
        hostFrame,
        cursorY,
        sctToggle("Text Shadow", "shadow"),
        sctToggle("Abbreviate Numbers", "abbreviate")
    )
    cursorY = cursorY - height

    local sctRow2
    sctRow2, height = W:DualRow(
        hostFrame,
        cursorY,
        sctToggle("Show Damage Taken", "damage"),
        sctToggle("Show Healing Received", "heal")
    )
    cursorY = cursorY - height
    sctColorSwatch(sctRow2._leftRegion, "damage", "damageColor", "Show Damage Taken")
    sctColorSwatch(sctRow2._rightRegion, "heal", "healColor", "Show Healing Received")

    local sctRow3
    sctRow3, height = W:DualRow(
        hostFrame,
        cursorY,
        sctToggle("Show Avoidance", "avoid"),
        sctToggle("Show Combat Enter/Leave", "combat")
    )
    cursorY = cursorY - height
    sctColorSwatch(sctRow3._leftRegion, "avoid", "avoidColor", "Show Avoidance")
    sctColorSwatch(sctRow3._rightRegion, "combat", "combatColor", "Show Combat Enter/Leave")

    return cursorY
end

CUI.AtOptionsLogin(function()
    ---------------------------------------------------------------------------
    --  QoL Features page
    ---------------------------------------------------------------------------
    -- The Macro Factory card: open or closed for the session (closed at its
    -- start), the section name its header carries in search (set by each
    -- build), and its glyph, the Potion macro's icon.
    local macroFactoryOpen = {}
    local macroFactorySection
    local function MacroFactoryGlyph(heading)
        local Pix = CUI.PanelPP
        local icon = heading:CreateTexture(nil, "ARTWORK")
        Pix.Size(icon, 22, 22)
        Pix.Point(icon, "LEFT", heading, "LEFT", 17, 0)
        icon:SetTexture("Interface\\Icons\\inv_potion_54")
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    -- Deep-link pre-hook: a jump to the card's own search entry opens the card
    -- first, so the jump lands on the open factory (a jump to any other row of
    -- the page leaves the card as it is).
    do
        local origNav = CUI.NavigateToElementSettings
        function CUI:NavigateToElementSettings(moduleName, page, sectionName, preSelectFn, highlightText)
            -- The original refuses in combat: no page state changes then.
            if InCombatLockdown() then
                return origNav(self, moduleName, page, sectionName, preSelectFn, highlightText)
            end
            if
                moduleName == "CludesUIQoL"
                and page == PAGE_QOL
                and sectionName ~= nil
                and sectionName == macroFactorySection
                and not macroFactoryOpen.macroFactory
            then
                macroFactoryOpen.macroFactory = true
                CUI:InvalidatePageCache()
            end
            return origNav(self, moduleName, page, sectionName, preSelectFn, highlightText)
        end
    end

    local function BuildQoLPage(page, hostFrame, yOffset)
        local W = CUI.Widgets
        local cursorY = yOffset
        local _, height, heading
        local Pix = CUI.PanelPP

        hostFrame._showRowDivider = true

        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height

        -- The Macro Factory sits in an expandable card (the patch notes' card),
        -- closed at the start of every session: its section is built only while
        -- the card is open, and a closed card parks the section an earlier build
        -- left. The card's header is a search entry (a jump to it opens the card,
        -- see the pre-hook below), but the factory's own rows stay out of the
        -- index, and the hidden search pre-build builds the header only: it never
        -- builds the section and never parks the one on screen. WoW Forever has no
        -- Macro Factory: no card there.
        if CUI.BuildMacroFactory and not CUI.IS_FOREVER then
            local prebuilding = CUI._prebuilding
            local mfTile = {
                key = "macroFactory",
                display = "Macro Factory",
                desc = CUI.L(
                    "Ready-made macros for potions, food, trinkets and focus, plus a set for your spec"
                ),
                buildContent = function(_, cy)
                    if prebuilding then return cy end
                    CUI._searchIndexSuppress = true
                    local mfH = CUI.BuildMacroFactory(hostFrame, cy, Pix)
                    CUI._searchIndexSuppress = nil
                    return cy - mfH
                end,
            }
            macroFactorySection = mfTile.display .. " " .. mfTile.desc
            cursorY = CUI.BuildModuleCard(hostFrame, cursorY, W, mfTile, {
                enabled = true,
                expanded = macroFactoryOpen,
                descW = 560,
                glyph = MacroFactoryGlyph,
            })
            if not macroFactoryOpen.macroFactory and not prebuilding then CUI.ParkMacroFactory() end
        end

        ---------------------------------------------------------------------------
        --  GENERAL
        ---------------------------------------------------------------------------
        _, height = W:SectionHeader(hostFrame, "GENERAL", cursorY)
        cursorY = cursorY - height

        -- Row 1: Hide Blizzard Elements (checklist + Loot Rolls Window cog) |
        -- Skip Cinematics (+ cog). Each checklist row reads and writes its own
        -- saved key, as its toggle did. Party Panel is the same key and apply
        -- as the Raid Frames toggle (CludesUI_BlizzardParty.lua). The talking
        -- head, banner and toast rows are retail only: their runtime blocks do
        -- not exist on WoW Forever.
        do
            local HBE_LABEL = "Hide Blizzard Elements"
            local function QDB()
                if not CludesUIDB then CludesUIDB = {} end
                return CludesUIDB
            end
            -- The toast rows share the hideAlertToasts switch: a kind hides while
            -- the switch is on and its own key allows it (Loot unset = on, the
            -- others unset = off), the runtime's KindHidden rule.
            local TOAST_KEYS =
                { "hideAlertToastsLoot", "hideAlertToastsAchievements", "hideAlertToastsHousing" }
            local function ToastHidden(settingKey)
                local saved = CludesUIDB
                if not (saved and saved.hideAlertToasts) then return false end
                local val = saved[settingKey]
                if val == nil then return settingKey == "hideAlertToastsLoot" end
                return val
            end
            local function SetToast(settingKey, val)
                local saved = QDB()
                if val and not saved.hideAlertToasts then
                    -- The switch goes on for this kind alone.
                    saved.hideAlertToasts = true
                    for idx = 1, #TOAST_KEYS do
                        saved[TOAST_KEYS[idx]] = false
                    end
                end
                saved[settingKey] = val and true or false
                if not val then
                    local any = false
                    for idx = 1, #TOAST_KEYS do
                        if ToastHidden(TOAST_KEYS[idx]) then any = true end
                    end
                    if not any then saved.hideAlertToasts = false end
                end
                if CUI._applyHideAlertToasts then CUI._applyHideAlertToasts() end
            end
            local function Toast(settingKey, labelText, aliasName)
                return {
                    key = settingKey,
                    label = labelText,
                    alias = aliasName,
                    read = function() return ToastHidden(settingKey) end,
                    write = function(val) SetToast(settingKey, val) end,
                }
            end

            -- alias: the row's old label, kept as search text.
            local RETAIL = not CUI.IS_FOREVER
            local itemList = {}
            itemList[#itemList + 1] = {
                key = "hideBlizzardPartyFrame",
                label = "Party Panel (Sidebar)",
                alias = "Hide Blizzard Party Panel",
                tooltip = "Hides the collapsed Blizzard party/raid sidebar panel on the side of the screen.",
                read = function() return CludesUIDB and CludesUIDB.hideBlizzardPartyFrame or false end,
                write = function(val)
                    QDB().hideBlizzardPartyFrame = val
                    CUI._applyHideBlizzardPartyFrame()
                end,
            }
            if RETAIL then
                itemList[#itemList + 1] = {
                    key = "hideTalkingHead",
                    label = "Talking Head",
                    alias = "Hide Talking Head",
                    tooltip = "Hides the large NPC dialogue popup that appears during quests and dungeons.",
                    read = function() return CludesUIDB and CludesUIDB.hideTalkingHead or false end,
                    write = function(val)
                        QDB().hideTalkingHead = val
                        CUI._applyHideTalkingHead()
                    end,
                }
                itemList[#itemList + 1] = {
                    key = "muteTalkingHead",
                    label = "Talking Head Audio",
                    alias = "Mute Talking Head",
                    tooltip = "Silences the talking head's voice lines.",
                    read = function() return CludesUIDB and CludesUIDB.muteTalkingHead == true end,
                    write = function(val)
                        QDB().muteTalkingHead = val
                        CUI._applyHideTalkingHead()
                    end,
                }
            end
            itemList[#itemList + 1] = {
                key = "hideTutorials",
                label = "Tutorial Popups",
                alias = "Hide Tutorial Pop-ups",
                tooltip = "Hides Blizzard's tutorial UI: the yellow HelpTip bubbles and the glowing (i) help-plate buttons on the spellbook, talents, map, collections, and other panels.",
                read = function() return CludesUIDB and CludesUIDB.hideTutorials or false end,
                write = function(val)
                    QDB().hideTutorials = val
                    if CUI._applyHideTutorials then CUI._applyHideTutorials() end
                end,
            }
            itemList[#itemList + 1] = {
                key = "hideZoneText",
                label = "Zone Text",
                alias = "Hide Zone Text",
                tooltip = "Hides the zone and subzone names that appear in the middle of the screen as you travel.",
                read = function() return CludesUIDB and CludesUIDB.hideZoneText or false end,
                write = function(val)
                    QDB().hideZoneText = val
                    if CUI._applyHideZoneText then CUI._applyHideZoneText() end
                end,
            }
            itemList[#itemList + 1] = {
                key = "hideErrorMessages",
                label = "Error Messages",
                alias = "Hide Error Messages",
                tooltip = "Hides most red error messages (such as 'Not enough rage' or 'Ability is not ready yet'). Important errors like a full bag or quest log are still shown.",
                read = function() return CludesUIDB and CludesUIDB.hideErrorMessages or false end,
                write = function(val)
                    QDB().hideErrorMessages = val
                    -- Turning it off takes effect at the next reload; the apply
                    -- returns true while one is due.
                    if CUI._applyHideErrorMessages and CUI._applyHideErrorMessages() then
                        CUI:ShowConfirmPopup({
                            title = "Reload Required",
                            message = "Hidden error messages come back after a UI reload.",
                            confirmText = "Reload Now",
                            cancelText = "Later",
                            reload = true,
                        })
                    end
                end,
            }
            itemList[#itemList + 1] = {
                key = "hideLootHistory",
                label = "Group Loot Rolls Window",
                alias = "Hide Loot Rolls Window",
                tooltip = 'Hides Blizzard\'s "Loot Rolls" window -- the running list of dropped items showing who rolled what and who won. Use the cog to let it appear briefly and close itself instead. The Need/Greed roll popups themselves are not affected.',
                read = function() return CludesUIDB and CludesUIDB.hideLootHistory or false end,
                write = function(val)
                    QDB().hideLootHistory = val
                    if CUI._applyHideLootHistory then CUI._applyHideLootHistory() end
                    CUI:RefreshPage() -- the Loot Rolls Window cog follows
                end,
            }
            if RETAIL then
                itemList[#itemList + 1] = {
                    key = "hideBanners",
                    label = "Top Screen Banners",
                    alias = "Hide Banners",
                    tooltip = "Hides the big banners at the top of the screen.",
                    read = function() return CludesUIDB and CludesUIDB.hideBanners or false end,
                    write = function(val)
                        QDB().hideBanners = val
                        if CUI._applyHideBanners then CUI._applyHideBanners() end
                    end,
                }
            end
            -- The same CludesUIDB.suppressErrors key and scriptErrors CVar as
            -- Global Settings > Developer, applied on login by the parent.
            itemList[#itemList + 1] = {
                key = "suppressErrors",
                label = "Lua Errors",
                alias = "Suppress Lua Errors",
                tooltip = "Hides the Lua error popup. The same setting as Core Settings > General > Developer.",
                read = function() return not (CludesUIDB and CludesUIDB.suppressErrors == false) end,
                write = function(val)
                    QDB().suppressErrors = val
                    if not InCombatLockdown() then CUI.SetCVar("scriptErrors", val and "0" or "1") end
                end,
            }
            if RETAIL then
                itemList[#itemList + 1] = Toast("hideAlertToastsLoot", "Loot Toasts", "Hide Alert Toasts")
                itemList[#itemList + 1] = Toast("hideAlertToastsAchievements", "Achievement Toasts")
                itemList[#itemList + 1] = Toast("hideAlertToastsHousing", "Housing Toasts")
            end

            -- Global search sees row labels and tooltips only, so this row's
            -- entry, registered before the row (the index keeps the first one),
            -- carries the checklist's names as search text; it is never shown.
            if CUI._RegisterSearchEntry then
                local words = {}
                local function Word(s)
                    if not s then return end
                    words[#words + 1] = s
                    local loc = CUI.L(s)
                    if loc ~= s then words[#words + 1] = loc end
                end
                for idx = 1, #itemList do
                    Word(itemList[idx].label)
                    Word(itemList[idx].alias)
                end
                local labelLoc = CUI.L(HBE_LABEL)
                CUI._RegisterSearchEntry(
                    HBE_LABEL,
                    labelLoc ~= HBE_LABEL and labelLoc or nil,
                    table.concat(words, " "),
                    CUI._buildingModule,
                    CUI._buildingPage,
                    hostFrame._currentSection and hostFrame._currentSection._sectionName
                )
            end

            local row1
            row1, height = W:DualRow(
                hostFrame,
                cursorY,
                { type = "label", text = HBE_LABEL, tooltip = "Choose which Blizzard elements to hide." },
                {
                    type = "toggle",
                    text = "Skip Cinematics",
                    tooltip = "When you press Escape or Space during a cinematic, the confirmation prompt is automatically accepted.",
                    getValue = function() return CludesUIDB and CludesUIDB.skipCinematics or false end,
                    setValue = AccountFieldThen("skipCinematics"),
                }
            )
            cursorY = cursorY - height

            if not CUI._prebuilding then
                local leftRegion = row1._leftRegion
                local byKey = {}
                for idx = 1, #itemList do
                    byKey[itemList[idx].key] = itemList[idx]
                end
                local hbeDD, hbeDDRefresh = CUI.BuildVisOptsCBDropdown(
                    leftRegion,
                    210,
                    leftRegion:GetFrameLevel() + 2,
                    itemList,
                    function(settingKey) return byKey[settingKey].read() end,
                    function(settingKey, val) byKey[settingKey].write(val) end
                )
                Pix.Point(hbeDD, "RIGHT", leftRegion, "RIGHT", -20, 0)
                leftRegion._control = hbeDD
                leftRegion._lastInline = nil
                CUI.RegisterWidgetRefresh(hbeDDRefresh)

                -- Loot Rolls Window cog (mode + auto-close delay), left of the list
                local function lootHistOff() return not (CludesUIDB and CludesUIDB.hideLootHistory) end
                -- The delay only means anything in auto-close mode.
                local function delayOff()
                    return lootHistOff() or (CludesUIDB and CludesUIDB.lootHistoryMode) ~= "autoclose"
                end
                CUI.BuildInlineCog(leftRegion, {
                    title = "Loot Rolls Window Settings",
                    minWidth = 300,
                    rows = {
                        {
                            type = "dropdown",
                            label = "Mode",
                            values = { hide = "Hide Completely", autoclose = "Close After Delay" },
                            order = { "hide", "autoclose" },
                            get = function() return (CludesUIDB and CludesUIDB.lootHistoryMode) or "hide" end,
                            set = function(val)
                                QDB().lootHistoryMode = val
                                if CUI._applyHideLootHistory then CUI._applyHideLootHistory() end
                            end,
                        },
                        {
                            type = "slider",
                            label = "Close After (sec)",
                            min = 1,
                            max = 30,
                            step = 1,
                            disabled = delayOff,
                            get = function() return (CludesUIDB and CludesUIDB.lootHistoryDelay) or 5 end,
                            set = function(val)
                                QDB().lootHistoryDelay = val
                                if CUI._applyHideLootHistory then CUI._applyHideLootHistory() end
                            end,
                        },
                    },
                    gap = 9,
                    disabled = lootHistOff,
                    disabledTooltip = "Group Loot Rolls Window",
                })

                -- Cog on Skip Cinematics (right region)
                local function cinematicsOff() return not (CludesUIDB and CludesUIDB.skipCinematics) end
                CUI.BuildInlineCog(row1._rightRegion, {
                    title = "Cinematic Settings",
                    rows = {
                        {
                            type = "toggle",
                            label = "Automatically Skip If Possible",
                            get = function() return CludesUIDB and CludesUIDB.skipCinematicsAuto or false end,
                            set = AccountField("skipCinematicsAuto"),
                        },
                    },
                    gap = 9,
                    disabled = cinematicsOff,
                    disabledTooltip = "Skip Cinematics",
                })
            end
        end

        local row2
        row2, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Quick Loot",
            tooltip = "Enables auto loot and hides the loot window when looting. Hold Shift when looting to show.",
            getValue = function() return CludesUIDB and CludesUIDB.quickLoot or false end,
            setValue = function(val)
                Account().quickLoot = val
                if CUI._applyQuickLoot then CUI._applyQuickLoot() end
            end,
        }, {
            type = "toggle",
            text = "Auto-Fill Delete Confirmation",
            tooltip = "Automatically types DELETE when throwing away a valuable item. Also allows you to press enter to accept the deletion.",
            getValue = function() return CludesUIDB and CludesUIDB.autoFillDelete or false end,
            setValue = AccountFieldThen("autoFillDelete"),
        })
        cursorY = cursorY - height

        -- Auto Repair | Auto Sell Junk
        local repairRow
        repairRow, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Auto Repair",
            tooltip = "Automatically repair all gear when visiting a repair vendor.",
            getValue = function()
                if not CludesUIDB then return true end
                return CludesUIDB.autoRepair ~= false
            end,
            setValue = AccountFieldThen("autoRepair"),
        }, {
            type = "toggle",
            text = "Auto Sell Junk",
            tooltip = "Automatically sell all junk items when visiting a vendor.",
            getValue = function()
                if not CludesUIDB then return true end
                return CludesUIDB.autoSellJunk ~= false
            end,
            setValue = AccountField("autoSellJunk"),
        })
        cursorY = cursorY - height

        -- Cog on Auto Repair (left region)
        if not CUI._prebuilding then
            local leftRegion = repairRow._leftRegion
            local function repairOff() return not (CludesUIDB and CludesUIDB.autoRepair ~= false) end

            CUI.BuildInlineCog(leftRegion, {
                title = "Auto Repair Settings",
                rows = {
                    {
                        type = "toggle",
                        label = "Use Guild Bank Funds",
                        get = function()
                            if not CludesUIDB then return true end
                            return CludesUIDB.autoRepairGuild ~= false
                        end,
                        set = AccountField("autoRepairGuild"),
                    },
                    -- Off (default) = short text "12o 34a"; on = coin icons.
                    {
                        type = "toggle",
                        label = "Coin Icons",
                        get = function() return CludesUIDB and CludesUIDB.repairCoinIcons == true end,
                        set = AccountField("repairCoinIcons"),
                    },
                },
                gap = 9,
                disabled = repairOff,
                disabledTooltip = "Auto Repair",
            })
        end

        -- Hide Item Transforms (+ picker cog) | Auto Select Single Gossip (+ cog)
        local transformRow
        transformRow, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Hide Item Transforms (ex: Chef's Hat)",
            tooltip = "Automatically removes cosmetic transforms when they are applied to you, such as profession gear, holiday costumes, toys and consumables. Use the cog to pick exactly which transforms are removed. Transforms applied during combat are removed when combat ends.",
            getValue = function() return CludesUIDB and CludesUIDB.hideTransforms or false end,
            setValue = function(val)
                Account().hideTransforms = val
                if CUI._applyHideTransforms then CUI._applyHideTransforms() end
                CUI:RefreshPage() -- update the picker cog disabled state
            end,
        }, {
            type = "toggle",
            text = "Auto Select Single Gossip",
            tooltip = "Picks an NPC's only dialog option for you.",
            getValue = function() return CludesUIDB and CludesUIDB.autoGossip or false end,
            setValue = function(val)
                Account().autoGossip = val
                if CUI._applyAutoGossip then CUI._applyAutoGossip() end
                CUI:RefreshPage()
            end,
        })
        cursorY = cursorY - height

        -- Inline picker cog on Hide Item Transforms (left slot): opens the item
        -- checklist popup. Dimmed and inert while the toggle is off, mirroring
        -- the resource-bar spec-picker button.
        if not CUI._prebuilding then
            local region = transformRow._leftRegion
            local function hitOff() return not (CludesUIDB and CludesUIDB.hideTransforms) end
            CUI.BuildInlineCog(region, {
                gap = 9,
                tip = CUI.L("Choose which transforms are removed"),
                disabled = hitOff,
                disabledTooltip = "Hide Item Transforms",
                show = function() ShowTransformsPopup() end,
            })
        end

        -- Cog on Auto Select Single Gossip (right slot)
        if not CUI._prebuilding then
            local rightRegion = transformRow._rightRegion
            local function gossipOff() return not (CludesUIDB and CludesUIDB.autoGossip) end

            CUI.BuildInlineCog(rightRegion, {
                title = "Auto Gossip Settings",
                rows = {
                    {
                        type = "toggle",
                        label = "Hold Shift to Skip",
                        get = function()
                            if not CludesUIDB then return true end
                            return CludesUIDB.autoGossipShiftSkip ~= false
                        end,
                        set = AccountField("autoGossipShiftSkip"),
                    },
                    {
                        type = "dropdown",
                        label = "Modifier Key",
                        tooltip = "The key the setting above listens to.",
                        values = { SHIFT = "Shift", CTRL = "Ctrl", ALT = "Alt" },
                        order = { "SHIFT", "CTRL", "ALT" },
                        disabled = function() return CludesUIDB and CludesUIDB.autoGossipShiftSkip == false end,
                        disabledTooltip = "Hold Shift to Skip",
                        get = function() return CludesUIDB and CludesUIDB.autoGossipModifier or "SHIFT" end,
                        set = AccountField("autoGossipModifier"),
                    },
                    {
                        type = "dropdown",
                        label = "Modifier Does",
                        tooltip = "Skips: it picks unless you hold the key. Triggers: it picks only while you hold it.",
                        values = { SKIP = "Skips", TRIGGER = "Triggers" },
                        order = { "SKIP", "TRIGGER" },
                        disabled = function() return CludesUIDB and CludesUIDB.autoGossipShiftSkip == false end,
                        disabledTooltip = "Hold Shift to Skip",
                        get = function() return CludesUIDB and CludesUIDB.autoGossipModifierMode or "SKIP" end,
                        set = AccountField("autoGossipModifierMode"),
                    },
                    {
                        type = "toggle",
                        label = "Only Service NPCs",
                        tooltip = "Pick the lone option only at a vendor, trainer, banker, auctioneer or stable master: never one that costs money or takes you somewhere.",
                        get = function() return CludesUIDB and CludesUIDB.autoGossipServiceOnly == true end,
                        set = AccountField("autoGossipServiceOnly"),
                    },
                    {
                        type = "toggle",
                        label = "Disable in Instances",
                        get = function()
                            if not CludesUIDB then return true end
                            return CludesUIDB.autoGossipDisableInstance ~= false
                        end,
                        set = AccountField("autoGossipDisableInstance"),
                    },
                    {
                        type = "toggle",
                        label = "Ignore Low Level Quests",
                        get = function() return CludesUIDB and CludesUIDB.autoGossipIgnoreTrivial or false end,
                        set = AccountField("autoGossipIgnoreTrivial"),
                    },
                },
                gap = 9,
                disabled = gossipOff,
                disabledTooltip = "Auto Select Single Gossip",
            })
        end

        -- Type /cd to open Blizzard CDM | AH Current Expansion Only. The AH
        -- filter is not offered on WoW Forever (its runtime block does not
        -- exist there), so that slot is blank there.
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            -- Cooldown Manager registers /cd at load from this key, so a change reloads
            {
                type = "toggle",
                text = "Type /cd to open Blizzard CDM",
                tooltip = "Lets /cd open or close Blizzard's Cooldown Manager settings.",
                disabled = function() return not CUI._ModuleNS["CludesUICooldownManager"] end,
                disabledTooltip = "Cooldown Manager",
                getValue = function() return CludesUIDB and CludesUIDB.blizzCDMSlash == true end,
                setValue = function(val)
                    Account().blizzCDMSlash = val and true or nil
                    CUI:ShowConfirmPopup({
                        title = "Reload Required",
                        message = "The /cd change applies after a UI reload.",
                        confirmText = "Reload Now",
                        cancelText = "Later",
                        reload = true,
                    })
                end,
            },
            CUI.IS_FOREVER and CUI.BlankRowCfg()
                or {
                    type = "toggle",
                    text = "AH Current Expansion Only",
                    tooltip = "Automatically enables the 'Current Expansion Only' filter whenever you open the Auction House.",
                    getValue = function() return CludesUIDB and CludesUIDB.ahCurrentExpansion or false end,
                    setValue = AccountField("ahCurrentExpansion"),
                }
        )
        cursorY = cursorY - height

        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height

        ---------------------------------------------------------------------------
        --  EXTRAS
        ---------------------------------------------------------------------------
        heading, height = W:SectionHeader(hostFrame, "EXTRAS", cursorY)
        cursorY = cursorY - height
        -- The FPS Counter is the section's first mover, so the header's button
        -- takes it; the button explains itself while the counter is off.
        CUI.BuildSectionUnlockJump(heading, {
            key = "CUI_FPS",
            disabled = function() return not CUI.QoLExtrasGet("showFPS") end,
            disabledTooltip = "Show FPS Counter",
        })

        -- Row 1: Show FPS Counter (left, with cog+swatch) | FPS Toggle Keybind (right)
        local fpsRow
        fpsRow, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Show FPS Counter",
            getValue = function() return CUI.QoLExtrasGet("showFPS") or false end,
            setValue = function(val)
                CUI.QoLExtrasSet("showFPS", val)
                if CUI._applyFPSDisplay then CUI._applyFPSDisplay() end
                CUI:RefreshPage()
            end,
        }, { type = "label", text = "FPS Toggle Keybind" })
        cursorY = cursorY - height

        -- Inline cog + color swatches on the FPS toggle (left region)
        if not CUI._prebuilding then
            local leftRegion = fpsRow._leftRegion
            local function fpsOff() return not CUI.QoLExtrasGet("showFPS") end

            -- Inline class + custom colour swatches, the same convention as the
            -- Secondary Stats row: the active mode renders at full alpha, the
            -- other dimmed, each with a naming tooltip.
            local function fpsMode()
                -- No mode saved: custom -- the look before the mode existed,
                -- which is white until a colour is actually picked.
                return CUI.QoLExtrasGet("fpsColorMode") or "custom"
            end
            local fpsUpdateState -- forward: swatches reference it from OnClick
            local function fpsSetMode(val)
                CUI.QoLExtrasSet("fpsColorMode", val)
                if CUI._applyFPSDisplay then CUI._applyFPSDisplay() end
                if fpsUpdateState then fpsUpdateState() end
            end

            local fpsSwGet = function()
                local color = CUI.QoLExtrasGet("fpsColor")
                if color then return color.r, color.g, color.b, color.a end
                return 1, 1, 1, 1
            end
            local fpsSwSet = function(red, green, blue, a)
                CUI.QoLExtrasSet("fpsColor", { r = red, g = green, b = blue, a = a })
                CUI.QoLExtrasSet("fpsColorMode", "custom")
                if CUI._applyFPSDisplay then CUI._applyFPSDisplay() end
                if fpsUpdateState then fpsUpdateState() end
            end

            CUI.BuildInlineCog(leftRegion, {
                title = "FPS Counter Settings",
                rows = {
                    {
                        type = "toggle",
                        label = "Attach to Secondary Stats",
                        disabled = function() return not CUI.QoLExtrasGet("showSecondaryStats") end,
                        disabledTooltip = "Secondary Stat Display",
                        get = function() return CUI.QoLExtrasGet("fpsAttachToStats") or false end,
                        set = function(val)
                            CUI.QoLExtrasSet("fpsAttachToStats", val)
                            if CUI._applyFPSDisplay then CUI._applyFPSDisplay() end
                        end,
                    },
                    -- Attached rows take the Secondary Stats font size, so this
                    -- has nothing to drive while the readout lives over there.
                    {
                        type = "slider",
                        label = "Text Size",
                        min = 8,
                        max = 30,
                        step = 1,
                        disabled = function()
                            return CUI._fpsAttachedToStats and CUI._fpsAttachedToStats() or false
                        end,
                        disabledTooltip = "Attach to Secondary Stats",
                        requireState = "disabled",
                        get = function() return CUI.QoLExtrasGet("fpsTextSize") or 12 end,
                        set = function(val)
                            CUI.QoLExtrasSet("fpsTextSize", val)
                            if CUI._applyFPSDisplay then CUI._applyFPSDisplay() end
                        end,
                    },
                    {
                        type = "toggle",
                        label = "Show Local MS",
                        get = function()
                            local sl = CUI.QoLExtrasGet("fpsShowLocalMS")
                            if sl == nil then return true end
                            return sl
                        end,
                        set = function(val)
                            CUI.QoLExtrasSet("fpsShowLocalMS", val)
                            if CUI._applyFPSDisplay then CUI._applyFPSDisplay() end
                        end,
                    },
                    {
                        type = "toggle",
                        label = "Show World MS",
                        get = function() return CUI.QoLExtrasGet("fpsShowWorldMS") or false end,
                        set = function(val)
                            CUI.QoLExtrasSet("fpsShowWorldMS", val)
                            if CUI._applyFPSDisplay then CUI._applyFPSDisplay() end
                        end,
                    },
                    {
                        type = "toggle",
                        label = "Hide Local/World Label",
                        get = function() return CUI.QoLExtrasGet("fpsHideLabel") or false end,
                        set = function(val)
                            CUI.QoLExtrasSet("fpsHideLabel", val)
                            if CUI._applyFPSDisplay then CUI._applyFPSDisplay() end
                        end,
                    },
                    {
                        type = "slider",
                        label = "Update Interval",
                        min = 1,
                        max = 5,
                        step = 1,
                        get = function() return CUI.QoLExtrasGet("fpsUpdateInterval") or 3 end,
                        set = function(val)
                            CUI.QoLExtrasSet("fpsUpdateInterval", val)
                            if CUI._applyFPSDisplay then CUI._applyFPSDisplay() end
                        end,
                    },
                },
                gap = 9,
                disabled = fpsOff,
                disabledTooltip = "Show FPS Counter",
            })

            -- Custom swatch (nearest the cog): a click switches to custom
            -- mode first; a second click opens the picker.
            local fpsSwatch, fpsUpdateSwatch = CUI.BuildColorSwatch(
                leftRegion,
                leftRegion:GetFrameLevel() + 5,
                fpsSwGet,
                fpsSwSet,
                true,
                20
            )
            do
                local openPicker = fpsSwatch:GetScript("OnClick")
                fpsSwatch:SetScript("OnClick", function(self)
                    if fpsMode() ~= "custom" then
                        fpsSetMode("custom")
                        return
                    end
                    if openPicker then openPicker(self) end
                end)
            end
            Pix.Point(fpsSwatch, "RIGHT", leftRegion._lastInline or leftRegion._control, "LEFT", -8, 0)
            leftRegion._lastInline = fpsSwatch

            -- Class-colour swatch: live player class colour.
            local fpsClassSw, fpsUpdClass = CUI.BuildColorSwatch(
                leftRegion,
                leftRegion:GetFrameLevel() + 5,
                function()
                    local classColor = CUI.GetClassColor(select(2, UnitClass("player")))
                    if classColor then return classColor.r, classColor.g, classColor.b end
                    return 1, 1, 1
                end,
                function() end,
                nil,
                20
            )
            fpsClassSw:SetScript("OnClick", function() fpsSetMode("class") end)
            Pix.Point(fpsClassSw, "RIGHT", leftRegion._lastInline, "LEFT", -8, 0)
            leftRegion._lastInline = fpsClassSw

            local fpsTips = { { fpsClassSw, "Class Color" }, { fpsSwatch, "Custom Color" } }
            for _, entry in ipairs(fpsTips) do
                entry[1]:HookScript("OnEnter", function() CUI.ShowWidgetTooltip(entry[1], entry[2]) end)
                entry[1]:HookScript("OnLeave", function() CUI.HideWidgetTooltip() end)
            end

            -- Blocking overlays while Show FPS Counter is off (shown from the
            -- single refresh below, like the swatch alphas).
            local fpsBlocks = {}
            for _, entry in ipairs(fpsTips) do
                local sw = entry[1]
                local block = CUI.NewSwatchBlocker(sw)
                block:SetScript(
                    "OnEnter",
                    function() CUI.ShowWidgetTooltip(sw, CUI.DisabledTooltip("Show FPS Counter")) end
                )
                block:SetScript("OnLeave", function() CUI.HideWidgetTooltip() end)
                fpsBlocks[#fpsBlocks + 1] = block
            end

            -- While the counter is off both swatches dim flat; while on, the
            -- active mode is bright and the other dimmed. One refresh owns
            -- both, plus the swatch fills (class color changes, custom picks).
            fpsUpdateState = function()
                if fpsUpdateSwatch then fpsUpdateSwatch() end
                if fpsUpdClass then fpsUpdClass() end
                local isOff = fpsOff()
                for _, block in ipairs(fpsBlocks) do
                    block:SetShown(isOff)
                end
                local m = not isOff and fpsMode() or nil
                fpsClassSw:SetAlpha(m == "class" and 1 or 0.3)
                fpsSwatch:SetAlpha(m == "custom" and 1 or 0.3)
            end
            CUI.RegisterWidgetRefresh(fpsUpdateState)
            fpsUpdateState()
        end

        -- FPS Toggle Keybind (built into right region of fpsRow)
        if not CUI._prebuilding then
            local rightRegion = fpsRow._rightRegion
            local kbBtn, refresh = CUI.BuildKeybindButton(rightRegion, {
                w = 140,
                h = 30,
                font = 13,
                get = function() return CludesUIDB and CludesUIDB.fpsToggleKey end,
                set = function(fullKey)
                    if not CludesUIDB then CludesUIDB = {} end
                    local bindBtn = _G["CUI_FPSBindBtn"]
                    if not fullKey then
                        if CludesUIDB.fpsToggleKey and bindBtn then ClearOverrideBindings(bindBtn) end
                    elseif bindBtn then
                        -- Binding refused in combat: keep the old key.
                        if InCombatLockdown() then return end
                        ClearOverrideBindings(bindBtn)
                        SetOverrideBindingClick(bindBtn, true, fullKey, "CUI_FPSBindBtn")
                    end
                    CludesUIDB.fpsToggleKey = fullKey
                end,
            })
            Pix.Point(kbBtn, "RIGHT", rightRegion, "RIGHT", -20, 0)
            CUI.RegisterWidgetRefresh(refresh)
        end

        -- Row 2: Low Durability Warning (left, with cog+eye+swatch) | Disable Right Click Targeting (right)
        local durWarnRow
        durWarnRow, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Low Durability Warning",
            tooltip = "Flashes a warning on screen when any equipped item drops below the configured durability threshold. Only triggers out of combat.",
            getValue = function() return CludesUIDB and CludesUIDB.repairWarning ~= false end,
            setValue = function(val)
                Account().repairWarning = val
                if CUI._syncDurWarnEvents then CUI._syncDurWarnEvents() end
                if not val and CUI._durWarnHidePreview then CUI._durWarnHidePreview() end
                CUI:RefreshPage()
            end,
        }, {
            type = "dropdown",
            text = "Disable Right Click",
            tooltip = "Suppresses right click targeting. Enemies applies everywhere. Allies In Combat only suppresses friendly targets while you are in combat, so you can still right click vendors and NPCs out of combat.\n\nNote: while this is active, holding Left+Right click to move forward won't work if your cursor is over a suppressed nameplate/unit, since this feature has to take over the right mouse button entirely to block targeting.",
            values = { ["_placeholder"] = "..." },
            order = { "_placeholder" },
            getValue = function() return "_placeholder" end,
            setValue = function() end,
        })
        cursorY = cursorY - height

        -- Right slot: multi-select dropdown (Enemies / Allies In Combat).
        -- The backend stays two independent booleans; the dropdown is purely a
        -- front-end grouping, so existing disableRightClickTarget users are kept
        -- exactly as-is and Allies is additive (defaults off).
        if not CUI._prebuilding then
            local rcRgn = durWarnRow._rightRegion
            if rcRgn._control then rcRgn._control:Hide() end
            local rcItems = {
                { key = "enemy", label = "Enemies" },
                { key = "ally", label = "Allies In Combat" },
            }
            local rcCB, rcCBRefresh = CUI.BuildVisOptsCBDropdown(
                rcRgn,
                200,
                rcRgn:GetFrameLevel() + 2,
                rcItems,
                function(keyName)
                    if not CludesUIDB then return false end
                    if keyName == "enemy" then return CludesUIDB.disableRightClickTarget or false end
                    return CludesUIDB.disableRightClickTargetAllyCombat or false
                end,
                function(keyName, val)
                    if not CludesUIDB then CludesUIDB = {} end
                    if keyName == "enemy" then
                        CludesUIDB.disableRightClickTarget = val
                    else
                        CludesUIDB.disableRightClickTargetAllyCombat = val
                    end
                    if CUI._applyRightClickTarget then CUI._applyRightClickTarget() end
                end
            )
            Pix.Point(rcCB, "RIGHT", rcRgn, "RIGHT", -20, 0)
            rcRgn._control = rcCB
            rcRgn._lastInline = nil
            CUI.RegisterWidgetRefresh(rcCBRefresh)
        end

        -- Inline: eyeball | color swatch | cog on the durability warning toggle
        if not CUI._prebuilding then
            local leftRegion = durWarnRow._leftRegion
            local function durOff() return CludesUIDB and CludesUIDB.repairWarning == false end

            -- Cog popup for durability settings (rightmost inline, closest to toggle)
            CUI.BuildInlineCog(leftRegion, {
                title = "Durability Settings",
                rows = {
                    {
                        type = "slider",
                        label = "Text Size",
                        min = 10,
                        max = 50,
                        step = 1,
                        get = function() return (CludesUIDB and CludesUIDB.durWarnTextSize) or 30 end,
                        set = function(val)
                            Account().durWarnTextSize = val
                            if CUI._durWarnApplySettings then CUI._durWarnApplySettings() end
                        end,
                    },
                    {
                        type = "slider",
                        label = "Y-Offset",
                        min = -600,
                        max = 600,
                        step = 1,
                        get = function() return CludesUIDB and CludesUIDB.durWarnYOffset or 250 end,
                        set = function(val)
                            Account().durWarnYOffset = val
                            CludesUIDB.durWarnPos = nil -- clear custom pos so slider always takes effect
                            if CUI._durWarnPreview then CUI._durWarnPreview() end
                        end,
                    },
                    {
                        type = "slider",
                        label = "Repair %",
                        min = 5,
                        max = 100,
                        step = 1,
                        get = function() return CludesUIDB and CludesUIDB.durWarnThreshold or 40 end,
                        set = AccountField("durWarnThreshold"),
                    },
                    CUI.IS_FOREVER
                            and {
                                type = "toggle",
                                label = "Ignore Thrown Weapons",
                                tooltip = "Thrown weapons lose durability with every throw.",
                                get = function()
                                    return CludesUIDB and CludesUIDB.durWarnIgnoreThrown ~= false
                                end,
                                set = function(val)
                                    Account().durWarnIgnoreThrown = val
                                    if CUI._syncDurWarnEvents then CUI._syncDurWarnEvents() end
                                end,
                            }
                        or nil,
                },
                gap = 9,
                disabled = durOff,
                disabledTooltip = "Low Durability Warning",
            })

            -- Color swatch (left of the cog)
            local durSwGet = function()
                local color = CludesUIDB and CludesUIDB.durWarnColor
                if color then return color.r, color.g, color.b end
                return 1, 0.27, 0.27
            end
            local durSwSet = function(red, green, blue)
                Account().durWarnColor = { r = red, g = green, b = blue }
                if CUI._applyDurWarn then CUI._applyDurWarn() end
            end
            local durSwatch, durUpdateSwatch = CUI.BuildColorSwatch(
                leftRegion,
                leftRegion:GetFrameLevel() + 5,
                durSwGet,
                durSwSet,
                nil,
                20
            )
            Pix.Point(durSwatch, "RIGHT", leftRegion._lastInline or leftRegion._control, "LEFT", -8, 0)
            leftRegion._lastInline = durSwatch

            -- Disabled overlay for swatch when durability warning is off
            local durSwBlock = CUI.NewSwatchBlocker(durSwatch)
            durSwBlock:SetScript(
                "OnEnter",
                function()
                    CUI.ShowWidgetTooltip(durSwatch, CUI.DisabledTooltip("Low Durability Warning"))
                end
            )
            durSwBlock:SetScript("OnLeave", function() CUI.HideWidgetTooltip() end)

            CUI.RegisterWidgetRefresh(function()
                local isOff = durOff()
                if isOff then
                    durSwatch:SetAlpha(0.3)
                    durSwBlock:Show()
                else
                    durSwatch:SetAlpha(1)
                    durSwBlock:Hide()
                end
                durUpdateSwatch()
            end)
            local durInitOff = durOff()
            durSwatch:SetAlpha(durInitOff and 0.3 or 1)
            if durInitOff then
                durSwBlock:Show()
            else
                durSwBlock:Hide()
            end

            -- Eye icon to toggle durability warning preview (left of swatch)
            local EYE_VISIBLE = CUI.EYE_VISIBLE_ICON
            local EYE_INVISIBLE = CUI.EYE_INVISIBLE_ICON
            local durabilityPreview = false
            local eyeButton = CreateFrame("Button", nil, leftRegion)
            eyeButton:SetSize(26, 26)
            eyeButton:SetPoint("RIGHT", leftRegion._lastInline or leftRegion._control, "LEFT", -8, 0)
            leftRegion._lastInline = eyeButton
            eyeButton:SetFrameLevel(leftRegion:GetFrameLevel() + 5)
            CUI.SetGlyphAlpha(eyeButton, durOff() and 0.15 or 0.4)
            local eyeTex = eyeButton:CreateTexture(nil, "OVERLAY")
            eyeTex:SetAllPoints()
            local function SyncDurabilityEye()
                if durabilityPreview then
                    eyeTex:SetTexture(EYE_INVISIBLE)
                else
                    eyeTex:SetTexture(EYE_VISIBLE)
                end
            end
            SyncDurabilityEye()
            eyeButton:SetScript("OnEnter", function(self)
                CUI.SetGlyphAlpha(self, 0.7)
                CUI.ShowWidgetTooltip(self, "Preview durability warning")
            end)
            eyeButton:SetScript("OnLeave", function(self)
                CUI.HideWidgetTooltip()
                CUI.SetGlyphAlpha(self, 0.4)
            end)
            eyeButton:SetScript("OnClick", function(self)
                durabilityPreview = not durabilityPreview
                SyncDurabilityEye()
                if durabilityPreview then
                    if CUI._applyDurWarn then CUI._applyDurWarn() end
                    if CUI._durWarnPreview then CUI._durWarnPreview() end
                else
                    if CUI._durWarnHidePreview then CUI._durWarnHidePreview() end
                end
            end)

            -- Blocking overlay for eye when durability warning is off
            local eyeBlock = CUI.NewSwatchBlocker(eyeButton)
            eyeBlock:SetScript(
                "OnEnter",
                function()
                    CUI.ShowWidgetTooltip(eyeButton, CUI.DisabledTooltip("Low Durability Warning"))
                end
            )
            eyeBlock:SetScript("OnLeave", function() CUI.HideWidgetTooltip() end)

            CUI.RegisterWidgetRefresh(function()
                local isOff = durOff()
                if isOff then
                    durabilityPreview = false
                    SyncDurabilityEye()
                    CUI.SetGlyphAlpha(eyeButton, 0.15)
                    eyeBlock:Show()
                else
                    CUI.SetGlyphAlpha(eyeButton, 0.4)
                    eyeBlock:Hide()
                end
            end)
            local eyeInitOff = durOff()
            CUI.SetGlyphAlpha(eyeButton, eyeInitOff and 0.15 or 0.4)
            if eyeInitOff then
                eyeBlock:Show()
            else
                eyeBlock:Hide()
            end
        end

        -- Row 3: Secondary Stat Display (left, with cog+swatches) | Guild Chat Privacy (right)
        local row4
        row4, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Secondary Stat Display",
            tooltip = CUI.IS_FOREVER and "Displays your character stats at the top left of the screen."
                or "Displays secondary stat percentages (Crit, Haste, Mastery, Vers) at the top left of the screen.",
            getValue = function() return CUI.QoLExtrasGet("showSecondaryStats") or false end,
            setValue = function(val)
                CUI.QoLExtrasSet("showSecondaryStats", val)
                -- Turning the block off has to release an attached FPS readout
                -- back to its own frame, so route through the shared apply.
                if CUI._applyFPSDisplay then
                    CUI._applyFPSDisplay()
                elseif CUI._applySecondaryStats then
                    CUI._applySecondaryStats()
                end
                CUI:RefreshPage()
            end,
        }, {
            type = "toggle",
            text = "Guild Chat Privacy Cover",
            tooltip = "Displays a spoiler tag over guild chat in the communities window that you can click to hide",
            getValue = function() return CludesUIDB and CludesUIDB.guildChatPrivacy or false end,
            setValue = function(val)
                Account().guildChatPrivacy = val
                if CUI._applyGuildChatPrivacy then CUI._applyGuildChatPrivacy() end
            end,
        })
        cursorY = cursorY - height

        -- Inline cog + color swatches on Secondary Stat Display (left region)
        if not CUI._prebuilding then
            local leftRegion = row4._leftRegion
            local function statsOff() return not CUI.QoLExtrasGet("showSecondaryStats") end

            -- Cog popup: stat visibility/order + tertiary swatch pair + Scale
            local function tsMode()
                local m = CUI.QoLExtrasGet("tertiaryStatsColorMode")
                if m then return m end
                -- No mode saved: an old profile with a stored color was using it.
                return CUI.QoLExtrasGet("tertiaryStatsColor") and "custom" or "class"
            end
            local function tsSetMode(val)
                CUI.QoLExtrasSet("tertiaryStatsColorMode", val)
                if CUI._applySecondaryStats then CUI._applySecondaryStats() end
            end
            local STAT_LABELS = {
                crit = "Crit",
                haste = "Haste",
                mastery = "Mastery",
                vers = "Versatility",
                leech = "Leech",
                avoidance = "Avoidance",
                speed = "Speed",
            }
            local TERTIARY_STATS = { leech = true, avoidance = true, speed = true }
            local DEFAULT_STAT_ORDER = {
                "crit",
                "haste",
                "mastery",
                "vers",
                "leech",
                "avoidance",
                "speed",
            }
            local function StatItems()
                local sequence = CUI._secondaryStatsOrder and CUI._secondaryStatsOrder()
                    or DEFAULT_STAT_ORDER
                local itemList = {}
                for _, settingKey in ipairs(sequence) do
                    itemList[#itemList + 1] = { key = settingKey, label = STAT_LABELS[settingKey] }
                end
                return itemList
            end
            -- Key stays `coloredPercentages`: it is the shipped setting
            -- name, and renaming it would drop everyone's saved choice.
            local coloredRow = {
                type = "toggle",
                label = "Colored Values",
                get = function() return CUI.QoLExtrasGet("coloredPercentages") or false end,
                set = function(val)
                    CUI.QoLExtrasSet("coloredPercentages", val)
                    if CUI._applySecondaryStats then CUI._applySecondaryStats() end
                end,
            }
            local abbreviateRow = {
                type = "toggle",
                label = "Abbreviate Stat Labels",
                get = function() return CUI.QoLExtrasGet("secondaryStatsAbbreviateLabels") or false end,
                set = function(val)
                    CUI.QoLExtrasSet("secondaryStatsAbbreviateLabels", val)
                    if CUI._applySecondaryStats then CUI._applySecondaryStats() end
                end,
            }
            local scaleRow = {
                type = "slider",
                label = "Scale",
                min = 50,
                max = 200,
                step = 5,
                get = function()
                    local place = CUI.QoLExtrasGet("secondaryStatsPos")
                    return math.floor(((place and place.scale) or 1.0) * 100 + 0.5)
                end,
                set = function(val)
                    -- Shallow-copy so we never mutate the shared account-wide
                    -- fallback table in place; the write lands per-profile.
                    local prev = CUI.QoLExtrasGet("secondaryStatsPos")
                    local newPos = {}
                    if prev then
                        for pk, preview in pairs(prev) do
                            newPos[pk] = preview
                        end
                    end
                    newPos.scale = val / 100
                    CUI.QoLExtrasSet("secondaryStatsPos", newPos)
                    if CUI._applySecondaryStats then CUI._applySecondaryStats() end
                end,
            }
            local cogRows, cogBtn, cogShow
            if CUI.IS_FOREVER then
                -- WoW Forever has no ratings or tertiaries: its stat catalog is
                -- picked in the grouped Choose Stats window
                -- (CUI_QoL_StatPicker.lua) and the shown stats ordered here.
                local FV_STAT = CUI._ModuleNS["CludesUIQoL"].FvStats.byKey
                cogRows = {
                    coloredRow,
                    abbreviateRow,
                    {
                        type = "button",
                        label = "Choose Stats...",
                        action = function()
                            -- The window takes the cog popup's place under the cog.
                            cogShow._popupFrame:Hide()
                            CUI._ShowStatPicker(cogBtn)
                        end,
                    },
                    {
                        type = "reorder",
                        label = "Reorder Shown Stats",
                        maxVisible = 12,
                        items = function()
                            local isHidden = CUI.QoLExtrasGet("secondaryStatsHidden")
                            local itemList = {}
                            for _, settingKey in ipairs(CUI._secondaryStatsOrder()) do
                                if not (type(isHidden) == "table" and isHidden[settingKey]) then
                                    itemList[#itemList + 1] =
                                        { key = settingKey, label = CUI.L(FV_STAT[settingKey].label) }
                                end
                            end
                            return itemList
                        end,
                        -- The hidden stats follow the shown ones, in their saved order.
                        set = function(keyList)
                            local sequence, seen = {}, {}
                            for _, settingKey in ipairs(keyList) do
                                sequence[#sequence + 1] = settingKey
                                seen[settingKey] = true
                            end
                            for _, settingKey in ipairs(CUI._secondaryStatsOrder()) do
                                if not seen[settingKey] then sequence[#sequence + 1] = settingKey end
                            end
                            CUI.QoLExtrasSet("secondaryStatsOrder", sequence)
                            CUI._applySecondaryStats()
                        end,
                    },
                    scaleRow,
                }
            else
                cogRows = {
                    coloredRow,
                    abbreviateRow,
                    {
                        type = "toggle",
                        label = "Show Raw Rating",
                        get = function() return CUI.QoLExtrasGet("showSecondaryStatsRaw") or false end,
                        set = function(val)
                            CUI.QoLExtrasSet("showSecondaryStatsRaw", val)
                            if val then CUI.QoLExtrasSet("showSecondaryStatsBoth", false) end
                            if CUI._applySecondaryStats then CUI._applySecondaryStats() end
                        end,
                    },
                    {
                        type = "toggle",
                        label = "Show % and Raw",
                        get = function() return CUI.QoLExtrasGet("showSecondaryStatsBoth") or false end,
                        set = function(val)
                            CUI.QoLExtrasSet("showSecondaryStatsBoth", val)
                            if val then CUI.QoLExtrasSet("showSecondaryStatsRaw", false) end
                            if CUI._applySecondaryStats then CUI._applySecondaryStats() end
                        end,
                    },
                    {
                        type = "reordercheck",
                        label = "Stats to Show",
                        items = StatItems,
                        hint = "Drag to Reorder",
                        get = function(settingKey)
                            local isHidden = CUI.QoLExtrasGet("secondaryStatsHidden")
                            return not (type(isHidden) == "table" and isHidden[settingKey])
                        end,
                        set = function(settingKey, isShown)
                            local old = CUI.QoLExtrasGet("secondaryStatsHidden")
                            local isHidden = {}
                            if type(old) == "table" then
                                for keyName, val in pairs(old) do
                                    isHidden[keyName] = val
                                end
                            end
                            if isShown then
                                -- Tertiaries default off, so false is the explicit
                                -- per-profile override that keeps one checked.
                                if TERTIARY_STATS[settingKey] then
                                    isHidden[settingKey] = false
                                else
                                    isHidden[settingKey] = nil
                                end
                            else
                                isHidden[settingKey] = true
                            end
                            CUI.QoLExtrasSet("secondaryStatsHidden", isHidden)
                            if CUI._applySecondaryStats then CUI._applySecondaryStats() end
                        end,
                        setOrder = function(keyList)
                            local sequence = {}
                            for idx, settingKey in ipairs(keyList) do
                                sequence[idx] = settingKey
                            end
                            CUI.QoLExtrasSet("secondaryStatsOrder", sequence)
                            if CUI._applySecondaryStats then CUI._applySecondaryStats() end
                        end,
                    },
                    -- Class / custom swatch pair, the same convention as the
                    -- minimap border row: the active mode at full alpha, a
                    -- naming tooltip on each swatch.
                    {
                        type = "multiswatch",
                        label = "Tertiary Label Color",
                        disabled = function()
                            local isHidden = CUI.QoLExtrasGet("secondaryStatsHidden")
                            return type(isHidden) == "table"
                                and isHidden.leech
                                and isHidden.avoidance
                                and isHidden.speed
                        end,
                        disabledTooltip = "a tertiary stat in Stats to Show",
                        swatches = {
                            {
                                tooltip = "Class Color",
                                getValue = function()
                                    local classColor = CUI.GetClassColor(select(2, UnitClass("player")))
                                    if classColor then return classColor.r, classColor.g, classColor.b end
                                    return 1, 1, 1
                                end,
                                onClick = function() tsSetMode("class") end,
                                refreshAlpha = function() return tsMode() == "class" and 1 or 0.3 end,
                            },
                            {
                                tooltip = "Custom Color",
                                getValue = function()
                                    local color = CUI.QoLExtrasGet("tertiaryStatsColor")
                                    if color then return color.r, color.g, color.b end
                                    return 1, 1, 1
                                end,
                                setValue = function(red, green, blue)
                                    CUI.QoLExtrasSet(
                                        "tertiaryStatsColor",
                                        { r = red, g = green, b = blue }
                                    )
                                    CUI.QoLExtrasSet("tertiaryStatsColorMode", "custom")
                                    if CUI._applySecondaryStats then CUI._applySecondaryStats() end
                                end,
                                -- First click switches to custom; a second opens the picker.
                                onClick = function(self, ...)
                                    if tsMode() ~= "custom" then
                                        tsSetMode("custom")
                                        return
                                    end
                                    if self._eabOrigClick then self._eabOrigClick(self, ...) end
                                end,
                                refreshAlpha = function() return tsMode() == "custom" and 1 or 0.3 end,
                            },
                        },
                    },
                    scaleRow,
                }
            end
            cogBtn, cogShow = CUI.BuildInlineCog(leftRegion, {
                title = "Secondary Stats Settings",
                rows = cogRows,
                disabled = statsOff,
                disabledTooltip = "Secondary Stat Display",
            })

            -- Inline default + class + custom colour swatches, following the
            -- minimap border's swatch-row convention: the active mode renders
            -- at full alpha, the others dimmed, each with a naming tooltip.
            local function ssMode()
                local m = CUI.QoLExtrasGet("secondaryStatsColorMode")
                if m then return m end
                -- No mode saved: a stored color was in use, otherwise class
                -- color -- the pre-mode default look.
                return CUI.QoLExtrasGet("secondaryStatsColor") and "custom" or "class"
            end
            local ssUpdateState -- forward: swatches reference it from OnClick
            local function ssSetMode(val)
                CUI.QoLExtrasSet("secondaryStatsColorMode", val)
                if CUI._applySecondaryStats then CUI._applySecondaryStats() end
                if ssUpdateState then ssUpdateState() end
            end

            -- Custom swatch (nearest the cog): stored custom colour. A
            -- click switches to custom mode first; a second click opens the
            -- picker (same two-step as the minimap border swatches).
            local ssCustom, ssUpdCustom = CUI.BuildColorSwatch(
                leftRegion,
                leftRegion:GetFrameLevel() + 5,
                function()
                    local color = CUI.QoLExtrasGet("secondaryStatsColor")
                    if color then return color.r, color.g, color.b end
                    return 1, 1, 1
                end,
                function(red, green, blue)
                    CUI.QoLExtrasSet("secondaryStatsColor", { r = red, g = green, b = blue })
                    CUI.QoLExtrasSet("secondaryStatsColorMode", "custom")
                    if CUI._applySecondaryStats then CUI._applySecondaryStats() end
                    if ssUpdateState then ssUpdateState() end
                end,
                nil,
                20
            )
            do
                local openPicker = ssCustom:GetScript("OnClick")
                ssCustom:SetScript("OnClick", function(self)
                    if ssMode() ~= "custom" then
                        ssSetMode("custom")
                        return
                    end
                    if openPicker then openPicker(self) end
                end)
            end
            Pix.Point(ssCustom, "RIGHT", leftRegion._lastInline or leftRegion._control, "LEFT", -8, 0)
            leftRegion._lastInline = ssCustom

            -- Class-colour swatch: live player class colour.
            local ssClass, ssUpdClass = CUI.BuildColorSwatch(
                leftRegion,
                leftRegion:GetFrameLevel() + 5,
                function()
                    local classColor = CUI.GetClassColor(select(2, UnitClass("player")))
                    if classColor then return classColor.r, classColor.g, classColor.b end
                    return 1, 1, 1
                end,
                function() end,
                nil,
                20
            )
            ssClass:SetScript("OnClick", function() ssSetMode("class") end)
            Pix.Point(ssClass, "RIGHT", leftRegion._lastInline, "LEFT", -8, 0)
            leftRegion._lastInline = ssClass

            -- Multicolored swatch (outermost): the per-stat palette, previewed
            -- by its first hue (crit gold).
            local ssMulti, ssUpdMulti = CUI.BuildColorSwatch(
                leftRegion,
                leftRegion:GetFrameLevel() + 5,
                function() return 1, 209 / 255, 0 end,
                function() end,
                nil,
                20
            )
            ssMulti:SetScript("OnClick", function() ssSetMode("palette") end)
            Pix.Point(ssMulti, "RIGHT", leftRegion._lastInline, "LEFT", -8, 0)
            leftRegion._lastInline = ssMulti

            local ssTips =
                { { ssMulti, "Multicolored" }, { ssClass, "Class Color" }, { ssCustom, "Custom Color" } }
            for _, entry in ipairs(ssTips) do
                entry[1]:HookScript("OnEnter", function() CUI.ShowWidgetTooltip(entry[1], entry[2]) end)
                entry[1]:HookScript("OnLeave", function() CUI.HideWidgetTooltip() end)
            end

            -- Blocking overlays while Secondary Stat Display is off (shown from
            -- the single refresh below, like the swatch alphas).
            local ssBlocks = {}
            for _, entry in ipairs(ssTips) do
                local sw = entry[1]
                local block = CUI.NewSwatchBlocker(sw)
                block:SetScript(
                    "OnEnter",
                    function()
                        CUI.ShowWidgetTooltip(sw, CUI.DisabledTooltip("Secondary Stat Display"))
                    end
                )
                block:SetScript("OnLeave", function() CUI.HideWidgetTooltip() end)
                ssBlocks[#ssBlocks + 1] = block
            end

            -- While the display is off every swatch dims flat; while on, the
            -- active mode is bright and the others dimmed. One refresh owns
            -- both, plus the swatch fills (class color changes, custom picks).
            ssUpdateState = function()
                if ssUpdCustom then ssUpdCustom() end
                if ssUpdClass then ssUpdClass() end
                if ssUpdMulti then ssUpdMulti() end
                local isOff = statsOff()
                for _, block in ipairs(ssBlocks) do
                    block:SetShown(isOff)
                end
                local m = not isOff and ssMode() or nil
                ssMulti:SetAlpha(m == "palette" and 1 or 0.3)
                ssClass:SetAlpha(m == "class" and 1 or 0.3)
                ssCustom:SetAlpha(m == "custom" and 1 or 0.3)
            end
            CUI.RegisterWidgetRefresh(ssUpdateState)
            ssUpdateState()
        end

        -- Row 4: Rested Indicator (left; mirrored in the Unit Frames player
        -- EXTRAS, CludesUI.RestedIndicatorCfg) |
        local restedRow
        restedRow, height = W:DualRow(hostFrame, cursorY, CUI.RestedIndicatorCfg(), {
            type = "toggle",
            text = "Target Distance (Range) Text",
            tooltip = "Shows the approximate distance to your current target as movable on-screen text (default 30-35). Use the cog for format, alignment, and text size; use Edit Layout to position or Anchor to your Player Frame.",
            getValue = function() return CludesUIDB and CludesUIDB.targetDistanceEnabled or false end,
            setValue = function(val)
                Account().targetDistanceEnabled = val
                if CUI._applyTargetDistance then CUI._applyTargetDistance() end
                CUI:RefreshPage()
            end,
        })
        cursorY = cursorY - height

        -- Inline cog on Rested Indicator (left region): Animated, Size, X/Y offsets
        CUI.BuildRestedIndicatorCog(restedRow._leftRegion)

        -- Target Distance settings cog (right slot of the Rested row)
        if not CUI._prebuilding then
            local region = restedRow._rightRegion
            local function tdOff() return not (CludesUIDB and CludesUIDB.targetDistanceEnabled) end

            local tdFormatValues = {
                range = "Range (30-35)",
                plus = "Lower Bound (30+)",
                min = "Minimum (30)",
            }
            local tdFormatOrder = { "range", "plus", "min" }
            local tdAlignValues = {
                LEFT = "Left",
                CENTER = "Center",
                RIGHT = "Right",
            }
            local tdAlignOrder = { "LEFT", "CENTER", "RIGHT" }

            CUI.BuildInlineCog(region, {
                title = "Target Distance Settings",
                minWidth = 280,
                rows = {
                    {
                        type = "dropdown",
                        label = "Format",
                        values = tdFormatValues,
                        order = tdFormatOrder,
                        get = function()
                            local f = CludesUIDB and CludesUIDB.targetDistanceFormat
                            if f == "plus" or f == "min" or f == "range" then return f end
                            return "range"
                        end,
                        set = AccountFieldThen2("targetDistanceFormat"),
                    },
                    {
                        type = "dropdown",
                        label = "Text Align",
                        values = tdAlignValues,
                        order = tdAlignOrder,
                        get = function()
                            local a = CludesUIDB and CludesUIDB.targetDistanceAlign
                            if a == "LEFT" or a == "CENTER" or a == "RIGHT" then return a end
                            return "CENTER"
                        end,
                        set = AccountFieldThen2("targetDistanceAlign"),
                    },
                    {
                        type = "slider",
                        label = "Text Size",
                        min = 10,
                        max = 48,
                        step = 1,
                        get = function() return (CludesUIDB and CludesUIDB.targetDistanceTextSize) or 18 end,
                        set = AccountFieldThen2("targetDistanceTextSize"),
                    },
                    {
                        type = "dropdown",
                        label = "Frame Strata",
                        tooltip = "Controls the order that overlapping elements display in. Set higher to show above other elements.",
                        values = CUI.FRAME_STRATA_LABELS,
                        order = CUI.FRAME_STRATA_ORDER_BASE,
                        get = function() return (CludesUIDB and CludesUIDB.targetDistanceStrata) or "HIGH" end,
                        set = AccountFieldThen2("targetDistanceStrata"),
                    },
                },
                footer = { unlockKey = "CUI_TargetDistance" },
                gap = 9,
                disabled = tdOff,
                disabledTooltip = "Target Distance (Range) Text",
            })
        end

        -- Row 5: Environment Ping keybind (left) | Show Coordinates on Map (+ cog)
        local pingRow
        pingRow, height = W:DualRow(hostFrame, cursorY, { type = "label", text = "Environment Ping" }, {
            type = "toggle",
            text = "Show Coordinates on Map",
            tooltip = "Displays cursor and player coordinates at the bottom of the world map.",
            getValue = function() return CludesUIDB and CludesUIDB.mapCoords or false end,
            setValue = function(val)
                Account().mapCoords = val
                if CUI._applyMapCoords then CUI._applyMapCoords() end
                CUI:RefreshPage()
            end,
        })
        cursorY = cursorY - height
        -- Cog on Show Coordinates on Map (right region)
        if not CUI._prebuilding then
            local function coordsOff() return not (CludesUIDB and CludesUIDB.mapCoords) end
            CUI.BuildInlineCog(pingRow._rightRegion, {
                title = "Map Coordinates Settings",
                rows = {
                    {
                        type = "slider",
                        label = "Text Size",
                        min = 8,
                        max = 24,
                        step = 1,
                        get = function() return (CludesUIDB and CludesUIDB.mapCoordsTextSize) or 12 end,
                        set = function(val)
                            Account().mapCoordsTextSize = val
                            if CUI._applyMapCoords then CUI._applyMapCoords() end
                        end,
                    },
                },
                gap = 9,
                disabled = coordsOff,
                disabledTooltip = "Show Coordinates on Map",
            })
        end
        if not CUI._prebuilding then
            local region = pingRow._leftRegion
            local kbBtn, refresh = CUI.BuildKeybindButton(region, {
                w = 140,
                h = 30,
                font = 13,
                mouse = true,
                get = function() return CludesUIDB.envPingKey end,
                set = function(val)
                    -- The hold key cannot be the button it claims.
                    local base = val and val:match("[^%-]+$")
                    if base == "BUTTON1" or base == "BUTTON2" then return end
                    CludesUIDB.envPingKey = val
                    if CUI._applyEnvPing then CUI._applyEnvPing() end
                end,
                tooltip = "While held, left-clicking the world sends a ping that ignores units and only targets the environment.\n\nLeft-click to set a keybind.\nRight-click to unbind.",
            })
            Pix.Point(kbBtn, "RIGHT", region, "RIGHT", -20, 0)
            CUI.RegisterWidgetRefresh(refresh)
        end

        -- Auto-Accept Resurrection: right of Row 6, or its own row on WoW Forever.
        local resCfg = {
            type = "toggle",
            text = "Auto-Accept Resurrection",
            tooltip = "Automatically accepts resurrections from players who are out of combat, such as raid resses after a wipe. Use the cog to also accept combat resurrections.",
            getValue = function() return CludesUIDB and CludesUIDB.autoAcceptRes or false end,
            setValue = function(val)
                Account().autoAcceptRes = val
                if CUI._applyAutoAcceptRes then CUI._applyAutoAcceptRes() end
                CUI:RefreshPage()
            end,
        }
        local function BuildResCog(region)
            if CUI._prebuilding then return end
            CUI.BuildInlineCog(region, {
                title = "Auto-Accept Resurrection",
                rows = {
                    {
                        type = "toggle",
                        label = "Accept Combat Resurrections",
                        get = function() return CludesUIDB and CludesUIDB.autoAcceptResCombat or false end,
                        set = AccountField("autoAcceptResCombat"),
                    },
                },
                gap = 9,
                disabled = function() return not (CludesUIDB and CludesUIDB.autoAcceptRes) end,
                disabledTooltip = "Auto-Accept Resurrection",
            })
        end

        -- Row 6: Transparent World Map Sidebars (left) | Auto-Accept Resurrection. Not offered
        -- on WoW Forever: Forever Essentials has its own map background option there.
        if not CUI.IS_FOREVER then
            local sidebarsRow
            sidebarsRow, height = W:DualRow(hostFrame, cursorY, {
                type = "toggle",
                text = "Transparent World Map Sidebars",
                tooltip = "Makes the black bars beside the maximized world map transparent, and lets you click, turn the camera and zoom through them. Use the cog to set their opacity.",
                getValue = function() return CludesUIDB and CludesUIDB.mapSidebarsClear or false end,
                setValue = function(val)
                    Account().mapSidebarsClear = val
                    if CUI._applyMapSidebars then CUI._applyMapSidebars() end
                    CUI:RefreshPage()
                end,
            }, resCfg)
            cursorY = cursorY - height
            BuildResCog(sidebarsRow._rightRegion)
            -- Cog on Transparent World Map Sidebars (left region)
            if not CUI._prebuilding then
                local function sidebarsOff() return not (CludesUIDB and CludesUIDB.mapSidebarsClear) end
                CUI.BuildInlineCog(sidebarsRow._leftRegion, {
                    title = "World Map Sidebars Settings",
                    rows = {
                        {
                            type = "slider",
                            label = "Opacity",
                            min = 0,
                            max = 100,
                            step = 5,
                            get = function() return (CludesUIDB and CludesUIDB.mapSidebarsOpacity) or 0 end,
                            set = function(val)
                                Account().mapSidebarsOpacity = val
                                if CUI._applyMapSidebars then CUI._applyMapSidebars() end
                            end,
                        },
                    },
                    gap = 9,
                    disabled = sidebarsOff,
                    disabledTooltip = "Transparent World Map Sidebars",
                })
            end
        else
            local resRow
            resRow, height = W:DualRow(hostFrame, cursorY, resCfg, CUI.BlankRowCfg())
            cursorY = cursorY - height
            BuildResCog(resRow._leftRegion)
        end

        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height

        ---------------------------------------------------------------------------
        --  CROSSHAIR
        ---------------------------------------------------------------------------
        _, height = W:SectionHeader(hostFrame, "CROSSHAIR", cursorY)
        cursorY = cursorY - height

        -- Crosshair: per-profile live in the QoL DB (_CUCL_AceDB.profile),
        -- with the account-wide CludesUIDB root as the inherited default.
        local function cdb() return _G._CUCL_AceDB and _G._CUCL_AceDB.profile end
        local function cursorGet(keyName)
            local p = cdb()
            if p and p[keyName] ~= nil then return p[keyName] end
            return CludesUIDB and CludesUIDB[keyName]
        end
        local function cset(keyName, val)
            local p = cdb()
            if p then p[keyName] = val end
        end
        local function crosshairOff() return (cursorGet("crosshairSize") or "None") == "None" end

        -- True when the effective thickness is custom (would display as
        -- "Custom" if enabled) -- i.e. H/V widths differ or don't match a preset.
        -- Checked regardless of None so a saved custom config can be restored.
        local function crosshairIsCustom()
            local PRESETS = CUI.CROSSHAIR_PRESETS
            local s = cursorGet("crosshairSize")
            local sizeForBase = (s and s ~= "None" and s) or "Normal"
            local base = (PRESETS and (PRESETS[sizeForBase] or PRESETS.Normal)) or { width = 2 }
            local hw = cursorGet("crosshairHWidth") or base.width
            local vw = cursorGet("crosshairVWidth") or base.width
            if hw ~= vw then return true end
            if PRESETS then
                for _, p in pairs(PRESETS) do
                    if p.width == hw then return false end
                end
            end
            return true
        end

        -- Row 1: Character Crosshair (left: dropdown + cog + swatch) | Visibility
        local crosshairRow
        crosshairRow, height = W:DualRow(hostFrame, cursorY, {
            type = "dropdown",
            text = "Character Crosshair",
            tooltip = "Displays a crosshair at the center of the screen.",
            -- "Custom" is only selectable when a custom thickness is
            -- stored (re-evaluated each time the menu opens); otherwise it's
            -- greyed, since picking it would just produce a preset look.
            itemDisabled = function(val) return val == "custom" and not crosshairIsCustom() end,
            itemDisabledTooltip = function(val)
                if val == "custom" then return "This option requires a custom thickness to be set." end
            end,
            -- The shown value is derived from the actual thickness: a preset name
            -- when the width matches one, otherwise "Custom". "Custom" is also
            -- selectable -- picking it re-enables using the user's stored values
            values = {
                ["None"] = "None",
                ["Thin"] = "Thin",
                ["Normal"] = "Normal",
                ["Thick"] = "Thick",
                ["custom"] = "Custom",
            },
            order = { "None", "Thin", "Normal", "Thick", "custom" },
            getValue = function()
                local size = cursorGet("crosshairSize") or "None"
                if size == "None" then return "None" end
                local PRESETS = CUI.CROSSHAIR_PRESETS
                local base = (PRESETS and (PRESETS[size] or PRESETS.Normal)) or { width = 2 }
                local hw = cursorGet("crosshairHWidth") or base.width
                local vw = cursorGet("crosshairVWidth") or base.width
                if hw == vw and PRESETS then
                    for name, p in pairs(PRESETS) do
                        if p.width == hw then return name end
                    end
                end
                return "custom"
            end,
            setValue = function(val)
                local p = cdb()
                if not p then return end
                p.crosshairSize = val
                -- Presets exist mainly for backwards compatibility. They stamp
                -- only the thickness baseline so Thin/Normal/Thick stay distinct
                -- and the cog reflects them. Length is not touched: it defaults
                -- to the preset length (40) only while unset, and once a user
                -- customises it, it persists across preset changes.
                local preset = CUI.CROSSHAIR_PRESETS and CUI.CROSSHAIR_PRESETS[val]
                if preset then
                    p.crosshairHWidth = preset.width
                    p.crosshairVWidth = preset.width
                end
                if CUI._applyCrosshair then CUI._applyCrosshair() end
                CUI:RefreshPage()
            end,
        }, {
            type = "dropdown",
            text = "Visibility",
            tooltip = "Choose when the crosshair is shown.",
            disabled = function() return crosshairOff() end,
            disabledTooltip = "Enable the crosshair to set its visibility.",
            rawTooltip = true,
            -- Real control is a multi-select checkbox dropdown injected below;
            -- this placeholder just provides the labelled right-region slot.
            values = { ["_placeholder"] = "..." },
            order = { "_placeholder" },
            getValue = function() return "_placeholder" end,
            setValue = function() end,
        })
        cursorY = cursorY - height

        -- Visibility: multi-select checkbox dropdown (Always / Combat / Instances),
        -- backed by the single crosshairVisibility string for backwards compat:
        --   always | combat | instances | instances_combat
        -- "Always" is the base state. Picking it
        -- clears the others; clearing both reverts to it.
        if not CUI._prebuilding then
            local visRgn = crosshairRow._rightRegion
            if visRgn._control then visRgn._control:Hide() end

            local function curVis() return cursorGet("crosshairVisibility") or "always" end
            local visItems = {
                {
                    key = "always",
                    label = "Always",
                    tooltip = "Always show the crosshair.",
                },
                {
                    key = "combat",
                    label = "Combat",
                    tooltip = "Show only while in combat. Combine with Instances to show only during instanced combat.",
                },
                {
                    key = "instances",
                    label = "Instances",
                    tooltip = "Show only while in a dungeon, raid, arena or battleground. Combine with Combat to show only during instanced combat.",
                },
            }
            local visCB, visCBRefresh = CUI.BuildVisOptsCBDropdown(
                visRgn,
                200,
                visRgn:GetFrameLevel() + 2,
                visItems,
                function(keyName)
                    local val = curVis()
                    if keyName == "always" then return val == "always" end
                    if keyName == "combat" then return val == "combat" or val == "instances_combat" end
                    return val == "instances" or val == "instances_combat"
                end,
                function(keyName, on)
                    local val = curVis()
                    local combat = (val == "combat" or val == "instances_combat")
                    local instances = (val == "instances" or val == "instances_combat")
                    if keyName == "always" then
                        if not on then return end -- can't un-pick the base state directly
                        combat, instances = false, false
                    elseif keyName == "combat" then
                        combat = on
                    else
                        instances = on
                    end
                    local nv = "always"
                    if combat and instances then
                        nv = "instances_combat"
                    elseif combat then
                        nv = "combat"
                    elseif instances then
                        nv = "instances"
                    end
                    cset("crosshairVisibility", nv)
                    if CUI._applyCrosshair then CUI._applyCrosshair() end
                end
            )
            Pix.Point(visCB, "RIGHT", visRgn, "RIGHT", -20, 0)
            visRgn._control = visCB
            visRgn._lastInline = nil

            -- Disabled overlay: grey + block when the crosshair is off, matching
            -- the placeholder's disabled state.
            local visBlock = CreateFrame("Frame", nil, visCB)
            visBlock:SetAllPoints()
            visBlock:SetFrameLevel(visCB:GetFrameLevel() + 20)
            visBlock:EnableMouse(true)
            visBlock:SetScript(
                "OnEnter",
                function() CUI.ShowWidgetTooltip(visCB, "Enable the crosshair to set its visibility.") end
            )
            visBlock:SetScript("OnLeave", function() CUI.HideWidgetTooltip() end)
            local function visUpdateDisabled()
                if crosshairOff() then
                    visCB:SetAlpha(0.4)
                    visBlock:Show()
                else
                    visCB:SetAlpha(1)
                    visBlock:Hide()
                end
            end
            CUI.RegisterWidgetRefresh(visCBRefresh)
            CUI.RegisterWidgetRefresh(visUpdateDisabled)
            visUpdateDisabled()
        end

        -- Inline cog on the crosshair dropdown (left region) for expanded options
        if not CUI._prebuilding then
            local leftRegion = crosshairRow._leftRegion
            local function chCogOff() return crosshairOff() end
            local function presetThick()
                local s = cursorGet("crosshairSize")
                local PRESETS = CUI.CROSSHAIR_PRESETS
                local p = PRESETS and (PRESETS[s] or PRESETS.Normal)
                return (p and p.width) or 2
            end
            local function applyCrosshair()
                if CUI._applyCrosshair then CUI._applyCrosshair() end
            end
            local function dbset(keyName, val)
                cset(keyName, val)
                applyCrosshair()
            end
            -- Re-resolve the size dropdown's label so it shows "Custom" (or snaps
            -- back to a preset) live when the thickness is changed in this cog.
            local function refreshSizeLabel()
                local control = crosshairRow._leftRegion and crosshairRow._leftRegion._control
                if control and control._refreshLabel then control._refreshLabel() end
            end

            local chCogRows = {
                {
                    type = "slider",
                    label = "H Length",
                    min = 1,
                    max = 500,
                    step = 1,
                    get = function() return cursorGet("crosshairHLength") or 40 end,
                    set = function(val) dbset("crosshairHLength", val) end,
                },
                {
                    type = "slider",
                    label = "H Width",
                    min = 1,
                    max = 20,
                    step = 1,
                    get = function() return cursorGet("crosshairHWidth") or presetThick() end,
                    set = function(val)
                        dbset("crosshairHWidth", val)
                        refreshSizeLabel()
                    end,
                },
                {
                    type = "slider",
                    label = "V Length",
                    min = 1,
                    max = 500,
                    step = 1,
                    get = function() return cursorGet("crosshairVLength") or 40 end,
                    set = function(val) dbset("crosshairVLength", val) end,
                },
                {
                    type = "slider",
                    label = "V Width",
                    min = 1,
                    max = 20,
                    step = 1,
                    get = function() return cursorGet("crosshairVWidth") or presetThick() end,
                    set = function(val)
                        dbset("crosshairVWidth", val)
                        refreshSizeLabel()
                    end,
                },
                {
                    type = "slider",
                    label = "Border",
                    min = 0,
                    max = 5,
                    step = 1,
                    get = function() return cursorGet("crosshairBorderSize") or 0 end,
                    set = function(val) dbset("crosshairBorderSize", val) end,
                },
                {
                    type = "colorpicker",
                    label = "Border Color",
                    hasAlpha = true,
                    get = function()
                        local bc = cursorGet("crosshairBorderColor")
                        if bc then return bc.r, bc.g, bc.b, bc.a end
                        return 0, 0, 0, 1
                    end,
                    set = function(red, green, blue, a)
                        cset("crosshairBorderColor", { r = red, g = green, b = blue, a = a or 1 })
                        applyCrosshair()
                    end,
                },
                {
                    type = "slider",
                    label = "X Offset",
                    min = -200,
                    max = 200,
                    step = 1,
                    get = function() return cursorGet("crosshairXOffset") or 0 end,
                    set = function(val) dbset("crosshairXOffset", val) end,
                },
                {
                    type = "slider",
                    label = "Y Offset",
                    min = -200,
                    max = 200,
                    step = 1,
                    get = function() return cursorGet("crosshairYOffset") or 0 end,
                    set = function(val) dbset("crosshairYOffset", val) end,
                },
                {
                    type = "dropdown",
                    label = "Frame Strata",
                    tooltip = "Controls the order that overlapping elements display in. Set higher to show above other elements.",
                    values = CUI.FRAME_STRATA_LABELS,
                    order = CUI.FRAME_STRATA_ORDER_BASE,
                    get = function() return cursorGet("crosshairStrata") or "MEDIUM" end,
                    set = function(val) dbset("crosshairStrata", val) end,
                },
            }
            -- Holy Paladin uses a 40yd out-of-range cutoff by default; let
            -- paladins opt into a melee (5yd) cutoff. Shown only for Paladins.
            if select(2, UnitClass("player")) == "PALADIN" then
                chCogRows[#chCogRows + 1] = {
                    type = "toggle",
                    label = "Show Melee Range for Hpal",
                    get = function() return cursorGet("crosshairHpalMelee") == true end,
                    set = function(val)
                        cset("crosshairHpalMelee", val)
                        if CUI._RefreshCrosshairCutoffRange then
                            CUI._RefreshCrosshairCutoffRange()
                        end
                        applyCrosshair()
                    end,
                }
            end

            CUI.BuildInlineCog(leftRegion, {
                title = "Crosshair Options",
                rows = chCogRows,
                gap = 9,
                disabled = chCogOff,
                disabledTooltip = "Character Crosshair",
            })
        end

        -- Inline color swatch on the crosshair dropdown (left region)
        if not CUI._prebuilding then
            local leftRegion = crosshairRow._leftRegion

            local chSwGet = function()
                local color = cursorGet("crosshairColor")
                if color then return color.r, color.g, color.b, color.a end
                return 1, 1, 1, 0.75
            end
            local chSwSet = function(red, green, blue, a)
                cset("crosshairColor", { r = red, g = green, b = blue, a = a or 1 })
                if CUI._applyCrosshair then CUI._applyCrosshair() end
            end
            local chSwatch, chUpdateSwatch = CUI.BuildColorSwatch(
                leftRegion,
                leftRegion:GetFrameLevel() + 5,
                chSwGet,
                chSwSet,
                true,
                20
            )
            Pix.Point(chSwatch, "RIGHT", leftRegion._lastInline or leftRegion._control, "LEFT", -8, 0)
            leftRegion._lastInline = chSwatch

            local chSwBlock = CUI.NewSwatchBlocker(chSwatch)
            chSwBlock:SetScript(
                "OnEnter",
                function()
                    CUI.ShowWidgetTooltip(chSwatch, CUI.DisabledTooltip("Character Crosshair"))
                end
            )
            chSwBlock:SetScript("OnLeave", function() CUI.HideWidgetTooltip() end)

            CUI.RegisterWidgetRefresh(function()
                local isOff = crosshairOff()
                if isOff then
                    chSwatch:SetAlpha(0.3)
                    chSwBlock:Show()
                else
                    chSwatch:SetAlpha(1)
                    chSwBlock:Hide()
                end
                chUpdateSwatch()
            end)
            local chInitOff = crosshairOff()
            chSwatch:SetAlpha(chInitOff and 0.3 or 1)
            if chInitOff then
                chSwBlock:Show()
            else
                chSwBlock:Hide()
            end
        end

        -- Color Out of Range (toggle + inline color picker)
        local meleeRow
        meleeRow, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Color Out of Range",
            tooltip = function()
                local text =
                    CUI.L("Changes the crosshair color when your current target is out of range.")
                if CUI._getCrosshairCutoffRange then
                    local range = CUI._getCrosshairCutoffRange()
                    text = text .. " " .. CUI.Lf("Currently active range cutoff: %1$syd.", range)
                end
                return text
            end,
            disabled = function() return crosshairOff() end,
            disabledTooltip = "Enable the crosshair to use this option.",
            rawTooltip = true,
            getValue = function() return cursorGet("crosshairMeleeColorEnabled") == true end,
            setValue = function(val)
                cset("crosshairMeleeColorEnabled", val)
                if CUI._applyCrosshair then CUI._applyCrosshair() end
                CUI:RefreshPage()
            end,
        }, { type = "label", text = "" })
        cursorY = cursorY - height
        -- Inline color swatch (disabled when toggle is off or crosshair is None)
        if not CUI._prebuilding then
            local leftRegion = meleeRow._leftRegion
            local function meleeOff() return crosshairOff() or cursorGet("crosshairMeleeColorEnabled") ~= true end
            local mcGet = function()
                local color = cursorGet("crosshairMeleeColor")
                if color then return color.r, color.g, color.b, color.a end
                return 1, 0, 0, 1
            end
            local mcSet = function(red, green, blue, a)
                cset("crosshairMeleeColor", { r = red, g = green, b = blue, a = a or 1 })
                if CUI._applyCrosshair then CUI._applyCrosshair() end
            end
            local mcSwatch, mcUpdate =
                CUI.BuildColorSwatch(leftRegion, leftRegion:GetFrameLevel() + 5, mcGet, mcSet, true, 20)
            Pix.Point(mcSwatch, "RIGHT", leftRegion._control, "LEFT", -12, 0)
            leftRegion._lastInline = mcSwatch

            local mcBlock = CUI.NewSwatchBlocker(mcSwatch)
            mcBlock:SetScript(
                "OnEnter",
                function()
                    CUI.ShowWidgetTooltip(mcSwatch, CUI.DisabledTooltip("Color Out of Range"))
                end
            )
            mcBlock:SetScript("OnLeave", function() CUI.HideWidgetTooltip() end)
            CUI.RegisterWidgetRefresh(function()
                local isOff = meleeOff()
                mcSwatch:SetAlpha(isOff and 0.3 or 1)
                if isOff then
                    mcBlock:Show()
                else
                    mcBlock:Hide()
                end
                mcUpdate()
            end)
            local mcInitOff = meleeOff()
            mcSwatch:SetAlpha(mcInitOff and 0.3 or 1)
            if mcInitOff then
                mcBlock:Show()
            else
                mcBlock:Hide()
            end
        end

        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height

        cursorY = BuildSelfCombatTextSection(hostFrame, cursorY)
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height

        ---------------------------------------------------------------------------
        --  GROUP FINDER (INSTANCES on WoW Forever)
        ---------------------------------------------------------------------------
        _, height = W:SectionHeader(hostFrame, CUI.IS_FOREVER and "INSTANCES" or "GROUP FINDER", cursorY)
        cursorY = cursorY - height

        -- Auto Insert Keystone | Announce Instance Reset, then Quick Signup |
        -- Persistent Signup Note, which Group Finder's settings page mirrors (the
        -- same account-wide switches). WoW Forever has no keystones and no premade
        -- group list, so only Announce Instance Reset is built there.
        local autoKeyCfg = {
            type = "toggle",
            text = "Auto Insert Keystone",
            tooltip = "Automatically inserts your key into the Font of Power.",
            getValue = function()
                if not CludesUIDB then return true end
                return CludesUIDB.autoInsertKeystone ~= false
            end,
            setValue = AccountField("autoInsertKeystone"),
        }
        local announceCfg = {
            type = "toggle",
            text = "Announce Instance Reset",
            tooltip = "After a successful instance reset, automatically announces it in party or raid chat so your group knows they can re-enter.",
            getValue = function() return CludesUIDB and CludesUIDB.instanceResetAnnounce or false end,
            setValue = function(val)
                Account().instanceResetAnnounce = val
                if CUI._applyInstanceResetAnnounce then CUI._applyInstanceResetAnnounce() end
            end,
        }
        local quickCfg = {
            type = "toggle",
            text = "Quick Signup",
            tooltip = "Double-click a group listing to instantly sign up without pressing the Sign Up button. Hold Shift to keep the dialog open, e.g. to type a signup note.",
            getValue = function() return CludesUIDB and CludesUIDB.quickSignup or false end,
            setValue = function(val)
                Account().quickSignup = val
                CUI._applyQuickSignup()
            end,
        }
        local persistCfg = {
            type = "toggle",
            text = "Persistent Signup Note",
            tooltip = "Keeps a saved signup note you can copy into the Sign Up dialog with the Copy button.",
            getValue = function() return CludesUIDB and CludesUIDB.persistSignupNote or false end,
            setValue = function(val)
                Account().persistSignupNote = val
                CUI._applyPersistSignupNote()
                CUI:RefreshPage()
            end,
        }
        local noteRow
        if CUI.IS_FOREVER then
            _, height = W:DualRow(hostFrame, cursorY, announceCfg, CUI.BlankRowCfg())
            cursorY = cursorY - height
        else
            _, height = W:DualRow(hostFrame, cursorY, autoKeyCfg, announceCfg)
            cursorY = cursorY - height
            noteRow, height = W:DualRow(hostFrame, cursorY, quickCfg, persistCfg)
            cursorY = cursorY - height
        end

        if noteRow and not CUI._prebuilding then
            local rightRegion = noteRow._rightRegion
            local function persistOff() return not (CludesUIDB and CludesUIDB.persistSignupNote) end

            CUI.BuildInlineCog(rightRegion, {
                gap = 9,
                tip = "Edit the saved signup note.",
                disabled = persistOff,
                disabledTooltip = "Persistent Signup Note",
                show = function()
                    CUI:ShowInputPopup({
                        title = "Signup Note",
                        message = "Saved between reloads and relogs. In Group Finder, choose Copy, press Ctrl+C, then Ctrl+V.",
                        placeholder = "Enter signup note...",
                        initialText = CUI.GetPersistentSignupNote(),
                        maxLetters = 63,
                        inputHeight = 70,
                        multiline = true,
                        showCount = true,
                        allowEmpty = true,
                        confirmText = "Save",
                        onConfirm = function(note) CUI.SetPersistentSignupNote(note or "") end,
                    })
                end,
            })
        end

        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height

        ---------------------------------------------------------------------------
        --  UI
        ---------------------------------------------------------------------------
        _, height = W:SectionHeader(hostFrame, "UI", cursorY)
        cursorY = cursorY - height

        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Hide Screenshot Status",
            tooltip = "Hides the 'Screenshot saved' notification that appears on screen after taking a screenshot.",
            getValue = function()
                if not CludesUIDB then return true end
                return CludesUIDB.hideScreenshotStatus ~= false
            end,
            setValue = function(val)
                Account().hideScreenshotStatus = val
                if CUI._applyScreenshotStatus then CUI._applyScreenshotStatus() end
            end,
        }, {
            type = "toggle",
            text = "Train All Button",
            tooltip = "Adds a 'Train All' button next to the Train button at profession trainers, allowing you to learn all available skills with one click.",
            getValue = function() return CludesUIDB and CludesUIDB.trainAllButton or false end,
            setValue = function(val)
                Account().trainAllButton = val
                if CUI._applyTrainAllButton then CUI._applyTrainAllButton() end
            end,
        })
        cursorY = cursorY - height

        -- Console Variables window | Put Back Pinned at Login
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "labeledButton",
            text = "Console Variables",
            buttonText = "Open",
            width = 90,
            tooltip = "Every console variable the game lets you change, with its value beside its default: search, change, reset, export and import them, and pin the ones to keep. You can also type /ccvar.",
            onClick = function()
                if CUI.OpenConsoleVariables then CUI.OpenConsoleVariables() end
            end,
        }, {
            type = "toggle",
            text = "Put Back Pinned at Login",
            tooltip = "Sets each console variable you pinned in the Console Variables window back to its pinned value every time you log in.",
            getValue = function() return CludesUIDB and CludesUIDB.cvarPinsOn == true end,
            setValue = function(val)
                Account().cvarPinsOn = val and true or false
                if val and CUI._ConsoleVariablesPutBack then CUI._ConsoleVariablesPutBack() end
            end,
        })
        cursorY = cursorY - height

        -- Auto Unwrap Collections | Auto Open Containers
        local autoOpenContainerRow
        autoOpenContainerRow, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Auto Unwrap Collections",
            tooltip = "Automatically dismisses the 'new mount/pet/toy' fanfare notification when you receive one, so you don't have to click through the collections journal.",
            getValue = function() return CludesUIDB and CludesUIDB.autoUnwrapCollections or false end,
            setValue = function(val)
                Account().autoUnwrapCollections = val
                if CUI._applyAutoUnwrap then CUI._applyAutoUnwrap() end
            end,
        }, {
            type = "toggle",
            text = "Auto Open Containers",
            tooltip = "Automatically opens bags, boxes and parcels in your inventory when they are added to your bags.\n\nContainers received from the mailbox are held until you close the mailbox, so opening them cannot collide with mail still delivering items.",
            getValue = function()
                if not CludesUIDB then return false end
                return CludesUIDB.autoOpenContainers == true
            end,
            setValue = function(val)
                Account().autoOpenContainers = val
                if CUI._applyAutoOpenContainers then CUI._applyAutoOpenContainers() end
                CUI:RefreshPage()
            end,
        })
        cursorY = cursorY - height

        -- Cog on Auto Open Containers (right region)
        if not CUI._prebuilding then
            local rightRegion = autoOpenContainerRow._rightRegion
            local function autoOpenContainerOff()
                return not (CludesUIDB and CludesUIDB.autoOpenContainers == true)
            end

            CUI.BuildInlineCog(rightRegion, {
                title = "Auto Open Containers Settings",
                rows = {
                    {
                        type = "toggle",
                        label = "Exclude Warbound Containers",
                        get = function()
                            if not CludesUIDB then return true end
                            return CludesUIDB.autoOpenContainersExcludeWarbound ~= false
                        end,
                        set = AccountField("autoOpenContainersExcludeWarbound"),
                    },
                    {
                        type = "toggle",
                        label = "Hold Capped Artisan Payouts",
                        tooltip = "Keeps Artisan's Consortium Payouts closed while Shard of Dundun is at its maximum, then resumes automatic opening after you spend shards.",
                        get = function()
                            return CludesUIDB
                                and CludesUIDB.autoOpenContainersHoldCappedArtisanPayouts == true
                        end,
                        set = function(val)
                            Account().autoOpenContainersHoldCappedArtisanPayouts = val
                            if CUI._applyAutoOpenContainers then CUI._applyAutoOpenContainers() end
                        end,
                    },
                },
                gap = 9,
                disabled = autoOpenContainerOff,
                disabledTooltip = "Auto Open Containers",
            })
        end

        -- Bonus Roll Confirmation. Not offered on WoW Forever: no bonus rolls
        -- there, so the row is not built and the runtime block does not exist.
        if not CUI.IS_FOREVER then
            local bonusRollRow
            local function bonusRollConflict() return C_AddOns.IsAddOnLoaded("BonusRollConfirm") end
            bonusRollRow, height = W:DualRow(hostFrame, cursorY, {
                type = "toggle",
                text = CUI.L("Bonus Roll Confirmation"),
                tooltip = CUI.L(
                    "Asks before spending a bonus roll and shows your loot specialization. Use the cog to also confirm Pass."
                ),
                disabled = bonusRollConflict,
                disabledTooltip = CUI.L(
                    "BonusRollConfirm is loaded and handles confirmation. Disable that addon and reload to use this feature."
                ),
                rawTooltip = true,
                getValue = function() return CludesUIDB and CludesUIDB.bonusRollConfirmation == true end,
                setValue = function(val)
                    Account().bonusRollConfirmation = val
                    if CUI._applyBonusRollConfirmation then CUI._applyBonusRollConfirmation() end
                    CUI:RefreshPage()
                end,
            }, CUI.BlankRowCfg())
            cursorY = cursorY - height
            if not CUI._prebuilding then
                CUI.BuildInlineCog(bonusRollRow._leftRegion, {
                    title = CUI.L("Bonus Roll Settings"),
                    rows = {
                        {
                            type = "toggle",
                            label = CUI.L("Only Confirm Roll"),
                            tooltip = CUI.L(
                                "Pass immediately without confirmation. Turn off to confirm both Roll and Pass."
                            ),
                            get = function() return not CludesUIDB or CludesUIDB.bonusRollOnly ~= false end,
                            set = function(val)
                                Account().bonusRollOnly = val
                                if CUI._applyBonusRollConfirmation then
                                    CUI._applyBonusRollConfirmation()
                                end
                            end,
                        },
                    },
                    gap = 9,
                    disabled = function()
                        return bonusRollConflict() or not (CludesUIDB and CludesUIDB.bonusRollConfirmation)
                    end,
                    disabledTooltip = CUI.L("Bonus Roll Confirmation"),
                })
            end
        end -- not IS_FOREVER

        -- Keys, Logs & Brez sections live at the bottom of this page (the
        -- separate tab was retired to keep the tab bar at five pages).
        if _G._CUI_BuildAutoLoggingPage then
            _, height = W:Spacer(hostFrame, cursorY, 16)
            cursorY = cursorY - height
            local alH = _G._CUI_BuildAutoLoggingPage(page, hostFrame, cursorY)
            if alH then cursorY = cursorY - alH end
        end

        return math.abs(cursorY)
    end

    local pages = { PAGE_QOL, PAGE_RAIDTOOLS, PAGE_CURSOR, PAGE_SHIFTER, PAGE_MOVEMENT }
    -- No item upgrade system on WoW Forever: the Upgrader tab is not offered there
    -- (its resident file returns at load, so the page builder never exists either).
    if not CUI.IS_FOREVER then pages[#pages + 1] = PAGE_UPGCALC end
    local searchTerms = {
        "brez",
        "bres",
        "battle res",
        "combat res",
        "cursor",
        "macro",
        "fps",
        "logging",
        "combat log",
        "warcraft logs",
        "upgrade",
        "ilvl",
        "item level",
        "crest",
        "upgrade calculator",
        "upgrade tooltips",
        "tooltip",
        "shifter",
        "move",
        "drag",
        "position",
        "demodal",
        "drift",
        "combat alert",
        "enter combat",
        "leave combat",
        "in combat",
        "combat text",
        "combat notification",
        "transform",
        "transforms",
        "costume",
        "disguise",
        "chef's hat",
        "noggenfogger",
        "target distance",
        "distance to target",
        "range text",
        "yard",
        "yards",
        "movement",
        "mobility",
        "gap closer",
        "blink",
        "gateway",
        "warlock gateway",
        "control shard",
        "time spiral",
        "free movement",
        "raid tools",
        "raid",
        "pull timer",
        "pull",
        "ready check",
        "role check",
        "raid marker",
        "target marker",
        "world marker",
        "flare",
        "disband",
        "convert to raid",
        "countdown",
    }
    -- Terms for features WoW Forever does not have (the Battle Res indicator,
    -- the Macro Factory) are dropped there, so a sidebar search for them does
    -- not list this module; retail keeps the full list.
    if CUI.IS_FOREVER then
        local foreverDrop = {
            ["brez"] = true,
            ["bres"] = true,
            ["battle res"] = true,
            ["combat res"] = true,
            ["macro"] = true,
        }
        for idx = #searchTerms, 1, -1 do
            if foreverDrop[searchTerms[idx]] then table.remove(searchTerms, idx) end
        end
    end
    CUI:RegisterModule("CludesUIQoL", {
        title = "Utilities",
        description = "Quality of life features and custom cursor.",
        pages = pages,
        -- Shown names (the page keys stay, so saved places and links still match).
        tabLabels = {
            [PAGE_QOL] = "General",
            [PAGE_SHIFTER] = "Window Mover",
            [PAGE_MOVEMENT] = "Movement Alerts",
            [PAGE_UPGCALC] = "Upgrade Calculator",
        },
        searchTerms = searchTerms,
        buildPage = function(page, hostFrame, yOffset)
            -- The Raid Tools settings preview ends when any OTHER QoL page
            -- builds (the CDM tracking-bars placeholder arrangement); window
            -- close and module switches are handled in the Raid Tools options
            -- file. Global Search's hidden pre-build never touches it.
            if page ~= PAGE_RAIDTOOLS and not CUI._prebuilding and _G._CUI_RaidTools_Preview then
                _G._CUI_RaidTools_Preview(false)
            end
            if page == PAGE_QOL then return BuildQoLPage(page, hostFrame, yOffset) end
            if page == PAGE_CURSOR and _G._CUBS_BuildCursorPage then
                return _G._CUBS_BuildCursorPage(page, hostFrame, yOffset)
            end
            if page == PAGE_UPGCALC and _G._CUI_BuildUpgradeCalcPage then
                return _G._CUI_BuildUpgradeCalcPage(page, hostFrame, yOffset)
            end
            if page == PAGE_SHIFTER and _G._CUI_BuildShifterPage then
                return _G._CUI_BuildShifterPage(page, hostFrame, yOffset)
            end
            if page == PAGE_MOVEMENT and _G._CUI_BuildMovementAlertPage then
                return _G._CUI_BuildMovementAlertPage(page, hostFrame, yOffset)
            end
            if page == PAGE_RAIDTOOLS and _G._CUI_BuildRaidToolsPage then
                return _G._CUI_BuildRaidToolsPage(page, hostFrame, yOffset)
            end
        end,
        -- Cached pages are restored WITHOUT a rebuild, so buildPage never runs
        -- on the warm path -- reopening the window onto Raid Tools would leave
        -- its settings preview off without this (the CDM tracking-bars
        -- arrangement: mirror the flag on BOTH paths).
        onPageCacheRestore = function(page)
            if CUI._prebuilding then return end
            if _G._CUI_RaidTools_Preview then _G._CUI_RaidTools_Preview(page == PAGE_RAIDTOOLS) end
        end,
        resetScope = "account",
        onReset = function()
            if CludesUIDB then
                CludesUIDB.hideBlizzardPartyFrame = false
                CludesUIDB.quickLoot = false
                CludesUIDB.autoGossip = false
                CludesUIDB.autoGossipShiftSkip = nil
                CludesUIDB.autoGossipDisableInstance = nil
                CludesUIDB.autoGossipIgnoreTrivial = nil
                CludesUIDB.autoGossipModifier = nil
                CludesUIDB.autoGossipModifierMode = nil
                CludesUIDB.autoGossipServiceOnly = nil
                CludesUIDB.skipCinematics = false
                CludesUIDB.skipCinematicsAuto = false
                CludesUIDB.autoFillDelete = false
                CludesUIDB.autoInsertKeystone = false
                CludesUIDB.instanceResetAnnounce = false
                CludesUIDB.instanceResetAnnounceMsg = ""
                CludesUIDB.quickSignup = false
                CludesUIDB.persistSignupNote = false
                CludesUIDB.signupNote = nil
                CludesUIDB.ahCurrentExpansion = false
                CludesUIDB.hideTalkingHead = false
                CludesUIDB.muteTalkingHead = nil
                CludesUIDB.hideScreenshotStatus = false
                CludesUIDB.trainAllButton = false
                CludesUIDB.autoUnwrapCollections = false
                CludesUIDB.autoOpenContainers = false
                CludesUIDB.bonusRollConfirmation = false
                CludesUIDB.bonusRollOnly = true
                CludesUIDB.autoOpenContainersExcludeWarbound = true
                CludesUIDB.autoOpenContainersHoldCappedArtisanPayouts = false
                CludesUIDB.autoRepairGuild = false
                -- Low Durability Warning settings (its on/off switch is in the
                -- Global Settings reset).
                CludesUIDB.durWarnThreshold = nil
                CludesUIDB.durWarnTextSize = nil
                CludesUIDB.durWarnColor = nil
                CludesUIDB.durWarnYOffset = nil
                CludesUIDB.durWarnPos = nil
                CludesUIDB.durWarnIgnoreThrown = nil
                CludesUIDB.shifterEnabled = false
                CludesUIDB.shifterPositions = nil
                CludesUIDB.hideErrorMessages = false
                CludesUIDB.hideTutorials = false
                -- Hands the tutorial CVars back before the reset's reload.
                if CUI._applyHideTutorials then CUI._applyHideTutorials() end
                CludesUIDB.hideLootHistory = false
                CludesUIDB.lootHistoryMode = nil
                CludesUIDB.lootHistoryDelay = nil
                if CUI._applyHideLootHistory then CUI._applyHideLootHistory() end
                -- Talking Head does not exist on WoW Forever.
                if CUI._applyHideTalkingHead then CUI._applyHideTalkingHead() end
                CludesUIDB.hideBanners = false
                CludesUIDB.hideAlertToasts = false
                CludesUIDB.hideAlertToastsLoot = nil
                CludesUIDB.hideAlertToastsAchievements = nil
                CludesUIDB.hideAlertToastsHousing = nil
                CludesUIDB.announceGroupDeaths = false
                CludesUIDB.groupDeathTextSize = nil
                CludesUIDB.groupDeathAlertPos = nil
                CludesUIDB.groupDeathSound = nil -- legacy boolean (pre-dropdown)
                CludesUIDB.groupDeathSoundKey = nil
                CludesUIDB.combatAlertEnabled = false
                CludesUIDB.combatAlertMode = nil
                CludesUIDB.combatAlertTextSize = nil
                CludesUIDB.combatAlertPos = nil
                CludesUIDB.combatAlertEnterText = nil
                CludesUIDB.combatAlertLeaveText = nil
                CludesUIDB.combatAlertEnterColor = nil
                CludesUIDB.combatAlertLeaveColor = nil
                CludesUIDB.combatAlertEnterUseClassColor = nil
                CludesUIDB.combatAlertLeaveUseClassColor = nil
                CludesUIDB.alertsPos = nil
                CludesUIDB.potionAlertEnabled = false
                CludesUIDB.potionAlertText = nil
                CludesUIDB.potionAlertTextSize = nil
                CludesUIDB.potionAlertColor = nil
                CludesUIDB.potionAlertUseClassColor = nil
                CludesUIDB.talentAlertEnabled = false
                CludesUIDB.talentAlertText = nil
                CludesUIDB.talentAlertTextSize = nil
                CludesUIDB.talentAlertColor = nil
                CludesUIDB.talentAlertUseClassColor = nil
                CludesUIDB.targetDistanceEnabled = false
                CludesUIDB.targetDistanceFormat = nil
                CludesUIDB.targetDistanceAlign = nil
                CludesUIDB.targetDistanceAttach = nil
                CludesUIDB.targetDistanceOffsetX = nil
                CludesUIDB.targetDistanceOffsetY = nil
                CludesUIDB.targetDistanceTextSize = nil
                CludesUIDB.targetDistancePos = nil
                CludesUIDB.mapSidebarsClear = nil
                CludesUIDB.mapSidebarsOpacity = nil
                CludesUIDB.autoAcceptRes = nil
                CludesUIDB.autoAcceptResCombat = nil
                if CludesUIDB.unlockAnchors then
                    CludesUIDB.unlockAnchors.CUI_TargetDistance = nil
                    CludesUIDB.unlockAnchors.CUI_CombatAlert = nil
                    CludesUIDB.unlockAnchors.CUI_BattleRes = nil
                    CludesUIDB.unlockAnchors.CUI_Bloodlust = nil
                end
                CludesUIDB.hideTransforms = false
                CludesUIDB.hideTransformItems = nil
                -- The /keys popup, LFG Reminder and /way sections (the reset reloads).
                CludesUIDB.keystonePopup = nil
                CludesUIDB.teleportPrompt = nil
                CludesUIDB.waypointCmd = nil
            end
            CludesUIDB.autoLogging = nil
            if _G._CUI_ResetUpgradeCalc then _G._CUI_ResetUpgradeCalc() end
            if _G._CUBS_ResetCursor then _G._CUBS_ResetCursor() end
            -- Battle Res and Bloodlust do not exist on WoW Forever.
            if _G._CUI_BattleRes_Reset then _G._CUI_BattleRes_Reset() end
            CUI._applyHideBlizzardPartyFrame()
            if CUI._applyBonusRollConfirmation then CUI._applyBonusRollConfirmation() end
            if CUI._applyHideErrorMessages then CUI._applyHideErrorMessages() end
            if CUI._applyAnnounceGroupDeaths then CUI._applyAnnounceGroupDeaths() end
            if CUI._applyCombatAlert then CUI._applyCombatAlert() end
            if CUI._applyPotionAlert then CUI._applyPotionAlert() end
            if CUI._applyTalentAlert then CUI._applyTalentAlert() end
            if CUI._applyTargetDistance then CUI._applyTargetDistance() end
            if CUI._applyHideTransforms then CUI._applyHideTransforms() end
            if CUI._applyQuickSignup then CUI._applyQuickSignup() end
            if CUI._applyPersistSignupNote then CUI._applyPersistSignupNote() end
            if CUI._applyQuickLoot then CUI._applyQuickLoot() end
            if CUI._applyAutoGossip then CUI._applyAutoGossip() end
            if CUI._applyInstanceResetAnnounce then CUI._applyInstanceResetAnnounce() end
            if CUI._applyAutoOpenContainers then CUI._applyAutoOpenContainers() end
            if CUI._ShutdownShifter then CUI._ShutdownShifter() end
            if _G._CUI_AutoLogging_Check then _G._CUI_AutoLogging_Check() end
            CUI._ModuleNS["CludesUIQoL"].SCT_Reset()
            CUI:InvalidatePageCache()
        end,
        -- Tears down Duration Warning, Raid Tools, and Movement Alert
        -- previews on module switch (Movement Alert also stops its ticker).
        onModuleLeave = function()
            if CUI._durWarnHidePreview then CUI._durWarnHidePreview() end
            if _G._CUI_RaidTools_Preview then _G._CUI_RaidTools_Preview(false) end
            if CUI._MovementAlertPreview then CUI._MovementAlertPreview(false) end
        end,
    })

    SLASH_EQOL1 = "/qol"
    SlashCmdList.EQOL = function()
        if InCombatLockdown and InCombatLockdown() then return end
        CUI:ShowModule("CludesUIQoL")
    end
end)
