if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
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
if not CludesUI._ModuleNS["CludesUIQoL"] then return end  -- module disabled: no options page

-- Page reuse: frames this file builds go through the options frame pool
-- (CludesUI_FramePool.lua), which hands a kept page its previous build's
-- frames back reset to new; on any other parent it is the plain CreateFrame.
local CreateFrame = CludesUI._Pool.CreateFrame

local PAGE_QOL      = "QoL"
local PAGE_CURSOR   = "Cursor"
local PAGE_UPGCALC  = "Upgrader"
local PAGE_SHIFTER  = "Shifter"
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
    local data = CludesUI.HideTransformsData
    if not data then return end

    if not transformsPopup then
        local FONT = CludesUI._font or "Interface\\AddOns\\CludesUI\\media\\fonts\\Expressway.TTF"
        local EG = CludesUI.CLUDES_GREEN or { r = 0.30, g = 0.79, b = 0.94 }
        local PP = CludesUI.PanelPP
        local COL_W, COL_GAP = 190, 12
        local CONTENT_LEFT, CONTENT_RIGHT, CONTENT_TOP = 41, 36, 118
        local HDR_H, ROW_H = 30, 26
        local numCols = #data.order

        -- Group items per category; the tallest column drives the popup height.
        local catItems = {}
        for _, item in ipairs(data.items) do
            catItems[item.cat] = catItems[item.cat] or {}
            catItems[item.cat][#catItems[item.cat] + 1] = item
        end
        local maxRows = 0
        for _, cat in ipairs(data.order) do
            local n = catItems[cat] and #catItems[cat] or 0
            if n > maxRows then maxRows = n end
        end

        local POPUP_W = CONTENT_LEFT + CONTENT_RIGHT + numCols * COL_W + (numCols - 1) * COL_GAP
        local POPUP_H = CONTENT_TOP + HDR_H + 4 + maxRows * ROW_H + 24 + 39 + 38
        local ppScale = CludesUI.GetPopupScale() or 1

        local dimmer = CreateFrame("Frame", nil, UIParent)
        dimmer:SetFrameStrata("FULLSCREEN_DIALOG")
        dimmer:SetAllPoints(UIParent)
        dimmer:EnableMouse(true)
        dimmer:EnableMouseWheel(true)
        dimmer:SetScript("OnMouseWheel", function() end)
        dimmer:Hide()
        dimmer:SetScale(ppScale)
        local dimTex = dimmer:CreateTexture(nil, "BACKGROUND")
        dimTex:SetAllPoints()
        dimTex:SetColorTexture(0, 0, 0, 0.25)

        local popup = CreateFrame("Frame", nil, dimmer)
        popup:SetScale(CludesUI.PopupBump(1))
        popup:SetFrameStrata("FULLSCREEN_DIALOG")
        popup:SetFrameLevel(dimmer:GetFrameLevel() + 10)
        popup:SetSize(POPUP_W, POPUP_H)
        popup:SetPoint("CENTER", CludesUI._mainFrame or UIParent, "CENTER", 0, 0)
        popup:EnableMouse(true)
        local pf = CludesUI._popupFrames
        if pf then pf[#pf + 1] = { popup = popup, dimmer = dimmer } end

        local bg = popup:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.077, 0.068, 0.058, 1)
        CludesUI.MakeRoundedBorder(popup, 1, 1, 1, 0.15, bg)

        local title = popup:CreateFontString(nil, "OVERLAY")
        title:SetFont(FONT, 22, "")
        title:SetTextColor(1, 1, 1, 1)
        title:SetPoint("TOP", popup, "TOP", 0, -32)
        title:SetText(CludesUI.L("Hide Item Transforms"))

        local sub = popup:CreateFontString(nil, "OVERLAY")
        sub:SetFont(FONT, 14, "")
        sub:SetTextColor(1, 1, 1, 0.45)
        sub:SetPoint("TOP", title, "BOTTOM", 0, -8)
        sub:SetText(CludesUI.L("Checked transforms are removed automatically when applied to you."))

        local rows = {}
        local function RefreshRows()
            for _, row in ipairs(rows) do
                if transformsStaged[row._key] then
                    row._check:Show()
                    row._boxBorder:SetColor(EG.r, EG.g, EG.b, 0.8)
                else
                    row._check:Hide()
                    row._boxBorder:SetColor(0.4, 0.4, 0.4, 0.6)
                end
            end
        end
        popup._refreshRows = RefreshRows

        -- Check All / Uncheck All links
        local function SetAll(v)
            for _, item in ipairs(data.items) do transformsStaged[item.key] = v end
            RefreshRows()
        end
        local checkAllBtn = CreateFrame("Button", nil, popup)
        checkAllBtn:SetFrameLevel(popup:GetFrameLevel() + 2)
        local checkAllLbl = checkAllBtn:CreateFontString(nil, "OVERLAY")
        checkAllLbl:SetFont(FONT, 14, "")
        checkAllLbl:SetText(CludesUI.L("Check All"))
        checkAllLbl:SetTextColor(1, 1, 1, 0.45)
        checkAllLbl:SetPoint("CENTER")
        checkAllBtn:SetSize(checkAllLbl:GetStringWidth() + 4, 20)
        checkAllBtn:SetPoint("TOPLEFT", popup, "TOPLEFT", CONTENT_LEFT, -(CONTENT_TOP - 22))
        checkAllBtn:SetScript("OnEnter", function() checkAllLbl:SetTextColor(1, 1, 1, 0.80) end)
        checkAllBtn:SetScript("OnLeave", function() checkAllLbl:SetTextColor(1, 1, 1, 0.45) end)
        checkAllBtn:SetScript("OnClick", function() SetAll(true) end)

        local linkDivider = popup:CreateTexture(nil, "OVERLAY", nil, 7)
        linkDivider:SetColorTexture(1, 1, 1, 0.18)
        if linkDivider.SetSnapToPixelGrid then linkDivider:SetSnapToPixelGrid(false); linkDivider:SetTexelSnappingBias(0) end
        linkDivider:SetPoint("LEFT", checkAllBtn, "RIGHT", 10, 0)
        linkDivider:SetWidth(1)
        linkDivider:SetHeight(12)

        local uncheckAllBtn = CreateFrame("Button", nil, popup)
        uncheckAllBtn:SetFrameLevel(popup:GetFrameLevel() + 2)
        local uncheckAllLbl = uncheckAllBtn:CreateFontString(nil, "OVERLAY")
        uncheckAllLbl:SetFont(FONT, 14, "")
        uncheckAllLbl:SetText(CludesUI.L("Uncheck All"))
        uncheckAllLbl:SetTextColor(1, 1, 1, 0.45)
        uncheckAllLbl:SetPoint("CENTER")
        uncheckAllBtn:SetSize(uncheckAllLbl:GetStringWidth() + 4, 20)
        uncheckAllBtn:SetPoint("LEFT", checkAllBtn, "RIGHT", 20, 0)
        uncheckAllBtn:SetScript("OnEnter", function() uncheckAllLbl:SetTextColor(1, 1, 1, 0.80) end)
        uncheckAllBtn:SetScript("OnLeave", function() uncheckAllLbl:SetTextColor(1, 1, 1, 0.45) end)
        uncheckAllBtn:SetScript("OnClick", function() SetAll(false) end)

        -- Category columns
        for colIdx, cat in ipairs(data.order) do
            local colX = CONTENT_LEFT + (colIdx - 1) * (COL_W + COL_GAP)
            local hdr = popup:CreateFontString(nil, "OVERLAY")
            hdr:SetFont(FONT, 17, "")
            hdr:SetTextColor(1, 1, 1, 0.7)
            hdr:SetPoint("TOPLEFT", popup, "TOPLEFT", colX + 4, -(CONTENT_TOP + 8))
            hdr:SetText(CludesUI.L(data.labels[cat] or cat))

            local items = catItems[cat] or {}
            for i, item in ipairs(items) do
                local row = CreateFrame("Button", nil, popup)
                row:SetSize(COL_W, ROW_H)
                row:SetPoint("TOPLEFT", popup, "TOPLEFT", colX, -(CONTENT_TOP + HDR_H + 4 + (i - 1) * ROW_H))
                row._key = item.key

                local box = CreateFrame("Frame", nil, row)
                box:SetSize(18, 18)
                box:SetPoint("LEFT", row, "LEFT", 4, 0)
                box:SetFrameLevel(row:GetFrameLevel() + 1)
                local boxBg = box:CreateTexture(nil, "BACKGROUND")
                boxBg:SetAllPoints()
                boxBg:SetColorTexture(0.114, 0.106, 0.099, 1)
                row._boxBorder = CludesUI.MakeRoundedBorder(box, 0.4, 0.4, 0.4, 0.6, boxBg)
                local check = box:CreateTexture(nil, "ARTWORK")
                check:SetPoint("TOPLEFT", box, "TOPLEFT", 3, -3)
                check:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -3, 3)
                check:SetColorTexture(EG.r, EG.g, EG.b, 1)
                CludesUI.RoundBody(box, check, 1)
                row._check = check

                local lbl = row:CreateFontString(nil, "OVERLAY")
                lbl:SetFont(FONT, 13, "")
                lbl:SetPoint("LEFT", box, "RIGHT", 8, 0)
                lbl:SetPoint("RIGHT", row, "RIGHT", -2, 0)
                lbl:SetJustifyH("LEFT")
                lbl:SetWordWrap(false)
                lbl:SetTextColor(1, 1, 1, 0.65)
                lbl:SetText(CludesUI.L(item.label))

                row:SetScript("OnEnter", function() lbl:SetTextColor(1, 1, 1, 0.95) end)
                row:SetScript("OnLeave", function() lbl:SetTextColor(1, 1, 1, 0.65) end)
                row:SetScript("OnClick", function()
                    transformsStaged[item.key] = not transformsStaged[item.key]
                    RefreshRows()
                end)
                rows[#rows + 1] = row
            end
        end

        -- Apply button (green, spec-popup style)
        local applyBtn = CreateFrame("Button", nil, popup)
        applyBtn:SetFrameLevel(popup:GetFrameLevel() + 2)
        applyBtn:SetSize(200, 39)
        applyBtn:SetPoint("BOTTOM", popup, "BOTTOM", 0, 38)
        local applyBg = applyBtn:CreateTexture(nil, "BACKGROUND")
        applyBg:SetAllPoints()
        applyBg:SetColorTexture(0.077, 0.068, 0.058, 0.92)
        local applyBrd = CludesUI.MakeRoundedBorder(applyBtn, EG.r, EG.g, EG.b, 0.9, applyBg)
        local applyLbl = applyBtn:CreateFontString(nil, "OVERLAY")
        applyLbl:SetFont(FONT, 16, "")
        applyLbl:SetPoint("CENTER")
        applyLbl:SetText(CludesUI.L("Apply"))
        applyLbl:SetTextColor(EG.r, EG.g, EG.b, 0.9)
        applyBtn:SetScript("OnEnter", function()
            applyLbl:SetTextColor(EG.r, EG.g, EG.b, 1)
            applyBrd:SetColor(EG.r, EG.g, EG.b, 1)
        end)
        applyBtn:SetScript("OnLeave", function()
            applyLbl:SetTextColor(EG.r, EG.g, EG.b, 0.9)
            applyBrd:SetColor(EG.r, EG.g, EG.b, 0.9)
        end)
        applyBtn:SetScript("OnClick", function()
            if not CludesUIDB then CludesUIDB = {} end
            CludesUIDB.hideTransformItems = CludesUIDB.hideTransformItems or {}
            local t = CludesUIDB.hideTransformItems
            for _, item in ipairs(data.items) do
                local staged = transformsStaged[item.key] and true or false
                if staged == (not item.defaultOff) then
                    t[item.key] = nil       -- matches the per-key default
                else
                    t[item.key] = staged    -- stored deviations only
                end
            end
            if CludesUI._applyHideTransforms then CludesUI._applyHideTransforms() end
            dimmer:Hide()
        end)

        -- Click outside or Escape discards staged edits
        dimmer:SetScript("OnMouseDown", function(self)
            if not popup:IsMouseOver() then self:Hide() end
        end)
        CludesUI.PopupTakeKeys(popup, dimmer)
        popup:SetScript("OnKeyDown", function(self, key)
            if InCombatLockdown() then return end
            if key == "ESCAPE" then
                self:SetPropagateKeyboardInput(false)
                dimmer:Hide()
            else
                self:SetPropagateKeyboardInput(true)
            end
        end)

        popup._dimmer = dimmer
        transformsPopup = popup
    end

    -- Seed the staged state from the saved settings, then show
    for _, item in ipairs(data.items) do
        transformsStaged[item.key] = CludesUI.GetHideTransformItem(item.key) and true or false
    end
    transformsPopup._refreshRows()
    transformsPopup._dimmer:Show()
end

-------------------------------------------------------------------------------
--  SELF COMBAT TEXT section of the QoL page (runtime:
--  CludesUIQoL_SelfCombatText.lua, settings through its SCT_Get/SCT_Set)
-------------------------------------------------------------------------------
local function BuildSelfCombatTextSection(parent, y)
    local W = CludesUI.Widgets
    local qns = CludesUI._ModuleNS["CludesUIQoL"]
    local SCTGet, SCTSet = qns.SCT_Get, qns.SCT_Set
    local _, h, hdr

    hdr, h = W:SectionHeader(parent, "SELF COMBAT TEXT", y);  y = y - h

    local function sctOff() return not SCTGet("enabled") end
    CludesUI.BuildSectionUnlockJump(hdr, { key = "CUI_SelfCombatText", disabled = sctOff, disabledTooltip = "Self Combat Text" })
    local function sctToggle(text, key)
        return { type="toggle", text=text,
          disabled=sctOff, disabledTooltip="Self Combat Text",
          getValue=function() return SCTGet(key) end,
          setValue=function(v) SCTSet(key, v); CludesUI:RefreshPage() end }
    end
    local function sctDropdown(text, key, values, order)
        return { type="dropdown", text=text, values=values, order=order,
          disabled=sctOff, disabledTooltip="Self Combat Text",
          getValue=function() return SCTGet(key) end,
          setValue=function(v) SCTSet(key, v) end }
    end
    -- A category toggle's colour, locked while the feature or that category is off
    local function sctSwatch(rgn, key, colorKey, label)
        if CludesUI._prebuilding then return end
        CludesUI.BuildInlineSwatches(rgn, { {
            disabled = function() return sctOff() or not SCTGet(key) end,
            disabledTooltip = function() return sctOff() and "Self Combat Text" or label end,
            getValue = function() local c = SCTGet(colorKey); return c.r, c.g, c.b end,
            setValue = function(r, g, b) SCTSet(colorKey, { r = r, g = g, b = b }) end,
        } })
    end

    local sctRow
    sctRow, h = W:DualRow(parent, y,
        { type="toggle", text="Self Combat Text",
          tooltip="Shows your damage taken, healing, avoids and combat enter/leave above the player frame instead of Blizzard's combat text, whose other messages are hidden while this is on. Move it in Layout Mode.",
          getValue=function() return not sctOff() end,
          setValue=CludesUI.SectionToggleSetValue(function(v) SCTSet("enabled", v) end) },
        { type="slider", text="Combat Text Size", min=10, max=48, step=1,
          disabled=sctOff, disabledTooltip="Self Combat Text",
          getValue=function() return SCTGet("size") end,
          setValue=function(v) SCTSet("size", v) end });  y = y - h
    if not CludesUI._prebuilding then
        CludesUI.BuildInlineCog(sctRow._leftRegion, { disabled = sctOff, disabledTooltip = "Self Combat Text",
            title = "Self Combat Text",
            rows = {
                { type="slider", label="Scroll Distance", min=20, max=300, step=5,
                  get=function() return SCTGet("rise") end,
                  set=function(v) SCTSet("rise", v) end },
                { type="slider", label="Scroll Duration", min=0.5, max=4, step=0.1,
                  get=function() return SCTGet("duration") end,
                  set=function(v) SCTSet("duration", v) end },
                { type="slider", label="Crit Scale", min=1, max=3, step=0.1,
                  get=function() return SCTGet("critScale") end,
                  set=function(v) SCTSet("critScale", v) end },
                { type="toggle", label="Stagger Hits",
                  tooltip="Spaces out hits that land together so none hides another.",
                  get=function() return SCTGet("stagger") end,
                  set=function(v) SCTSet("stagger", v) end },
            },
        })
    end

    -- Section gate: the rows below exist only while Self Combat Text is on (the
    -- toggle's SectionToggleSetValue rebuilds the page).
    if sctOff() then return y end

    _, h = W:DualRow(parent, y,
        sctDropdown("Animation", "anim",
            { straight = "Straight", fountain = "Fountain", static = "Static" },
            { "straight", "fountain", "static" }),
        sctDropdown("Scroll Direction", "direction",
            { up = "Up", down = "Down" }, { "up", "down" }));  y = y - h

    local fontValues, fontOrder = CludesUI.BuildFontDropdownData()
    fontValues["__combat"] = { text = "Combat Text Font" }
    table.insert(fontOrder, 1, "__combat")
    _, h = W:DualRow(parent, y,
        sctDropdown("Font", "font", fontValues, fontOrder),
        sctDropdown("Outline", "outline",
            { NONE = "None", OUTLINE = "Outline", THICKOUTLINE = "Thick Outline" },
            { "NONE", "OUTLINE", "THICKOUTLINE" }));  y = y - h

    _, h = W:DualRow(parent, y,
        sctToggle("Text Shadow", "shadow"),
        sctToggle("Abbreviate Numbers", "abbreviate"));  y = y - h

    local sctRow2
    sctRow2, h = W:DualRow(parent, y,
        sctToggle("Show Damage Taken", "damage"),
        sctToggle("Show Healing Received", "heal"));  y = y - h
    sctSwatch(sctRow2._leftRegion, "damage", "damageColor", "Show Damage Taken")
    sctSwatch(sctRow2._rightRegion, "heal", "healColor", "Show Healing Received")

    local sctRow3
    sctRow3, h = W:DualRow(parent, y,
        sctToggle("Show Avoidance", "avoid"),
        sctToggle("Show Combat Enter/Leave", "combat"));  y = y - h
    sctSwatch(sctRow3._leftRegion, "avoid", "avoidColor", "Show Avoidance")
    sctSwatch(sctRow3._rightRegion, "combat", "combatColor", "Show Combat Enter/Leave")

    return y
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if not CludesUI or not CludesUI.RegisterModule then return end

    ---------------------------------------------------------------------------
    --  QoL Features page
    ---------------------------------------------------------------------------
    -- The Macro Factory card: open or closed for the session (closed at its
    -- start), the section name its header carries in search (set by each
    -- build), and its glyph, the Potion macro's icon.
    local macroFactoryOpen = {}
    local macroFactorySection
    local function MacroFactoryGlyph(hdr)
        local PP = CludesUI.PanelPP
        local icon = hdr:CreateTexture(nil, "ARTWORK")
        PP.Size(icon, 22, 22)
        PP.Point(icon, "LEFT", hdr, "LEFT", 17, 0)
        icon:SetTexture("Interface\\Icons\\inv_potion_54")
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    -- Deep-link pre-hook: a jump to the card's own search entry opens the card
    -- first, so the jump lands on the open factory (a jump to any other row of
    -- the page leaves the card as it is).
    do
        local origNav = CludesUI.NavigateToElementSettings
        function CludesUI:NavigateToElementSettings(moduleName, pageName, sectionName, preSelectFn, highlightText)
            -- The original refuses in combat: no page state changes then.
            if InCombatLockdown() then
                return origNav(self, moduleName, pageName, sectionName, preSelectFn, highlightText)
            end
            if moduleName == "CludesUIQoL" and pageName == PAGE_QOL and sectionName ~= nil
               and sectionName == macroFactorySection and not macroFactoryOpen.macroFactory then
                macroFactoryOpen.macroFactory = true
                CludesUI:InvalidatePageCache()
            end
            return origNav(self, moduleName, pageName, sectionName, preSelectFn, highlightText)
        end
    end

    local function BuildQoLPage(pageName, parent, yOffset)
        local W = CludesUI.Widgets
        local y = yOffset
        local _, h, hdr
        local PP = CludesUI.PanelPP

        parent._showRowDivider = true

        _, h = W:Spacer(parent, y, 20);  y = y - h

        -- The Macro Factory sits in an expandable card (the patch notes' card),
        -- closed at the start of every session: its section is built only while
        -- the card is open, and a closed card parks the section an earlier build
        -- left. The card's header is a search entry (a jump to it opens the card,
        -- see the pre-hook below), but the factory's own rows stay out of the
        -- index, and the hidden search pre-build builds the header only: it never
        -- builds the section and never parks the one on screen. WoW Forever has no
        -- Macro Factory: no card there.
        if CludesUI.BuildMacroFactory and not CludesUI.IS_FOREVER then
            local prebuilding = CludesUI._prebuilding
            local mfTile = { key = "macroFactory", display = "Macro Factory",
                desc = CludesUI.L("Ready-made macros for potions, food, trinkets and focus, plus a set for your spec"),
                buildContent = function(_, cy)
                    if prebuilding then return cy end
                    CludesUI._searchIndexSuppress = true
                    local mfH = CludesUI.BuildMacroFactory(parent, cy, PP)
                    CludesUI._searchIndexSuppress = nil
                    return cy - mfH
                end }
            macroFactorySection = mfTile.display .. " " .. mfTile.desc
            y = CludesUI.BuildModuleCard(parent, y, W, mfTile, {
                enabled = true, expanded = macroFactoryOpen, descW = 560,
                glyph = MacroFactoryGlyph })
            if not macroFactoryOpen.macroFactory and not prebuilding then
                CludesUI.ParkMacroFactory()
            end
        end

        ---------------------------------------------------------------------------
        --  GENERAL
        ---------------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "GENERAL", y);  y = y - h

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
            local TOAST_KEYS = { "hideAlertToastsLoot", "hideAlertToastsAchievements", "hideAlertToastsHousing" }
            local function ToastHidden(key)
                local db = CludesUIDB
                if not (db and db.hideAlertToasts) then return false end
                local v = db[key]
                if v == nil then return key == "hideAlertToastsLoot" end
                return v
            end
            local function SetToast(key, v)
                local db = QDB()
                if v and not db.hideAlertToasts then
                    -- The switch goes on for this kind alone.
                    db.hideAlertToasts = true
                    for i = 1, #TOAST_KEYS do db[TOAST_KEYS[i]] = false end
                end
                db[key] = v and true or false
                if not v then
                    local any = false
                    for i = 1, #TOAST_KEYS do
                        if ToastHidden(TOAST_KEYS[i]) then any = true end
                    end
                    if not any then db.hideAlertToasts = false end
                end
                if CludesUI._applyHideAlertToasts then CludesUI._applyHideAlertToasts() end
            end
            local function Toast(key, label, alias)
                return { key = key, label = label, alias = alias,
                    read = function() return ToastHidden(key) end,
                    write = function(v) SetToast(key, v) end }
            end

            -- alias: the row's old label, kept as search text.
            local RETAIL = not CludesUI.IS_FOREVER
            local items = {}
            items[#items + 1] = { key = "hideBlizzardPartyFrame", label = "Party Panel (Sidebar)",
                alias = "Hide Blizzard Party Panel",
                tooltip = "Hides the collapsed Blizzard party/raid sidebar panel on the side of the screen.",
                read = function() return CludesUIDB and CludesUIDB.hideBlizzardPartyFrame or false end,
                write = function(v)
                    QDB().hideBlizzardPartyFrame = v
                    CludesUI._applyHideBlizzardPartyFrame()
                end }
            if RETAIL then
                items[#items + 1] = { key = "hideTalkingHead", label = "Talking Head",
                    alias = "Hide Talking Head",
                    tooltip = "Hides the large NPC dialogue popup that appears during quests and dungeons.",
                    read = function() return CludesUIDB and CludesUIDB.hideTalkingHead or false end,
                    write = function(v)
                        QDB().hideTalkingHead = v
                        CludesUI._applyHideTalkingHead()
                    end }
                items[#items + 1] = { key = "muteTalkingHead", label = "Talking Head Audio",
                    alias = "Mute Talking Head",
                    tooltip = "Silences the talking head's voice lines.",
                    read = function() return CludesUIDB and CludesUIDB.muteTalkingHead == true end,
                    write = function(v)
                        QDB().muteTalkingHead = v
                        CludesUI._applyHideTalkingHead()
                    end }
            end
            items[#items + 1] = { key = "hideTutorials", label = "Tutorial Popups",
                alias = "Hide Tutorial Pop-ups",
                tooltip = "Hides Blizzard's tutorial UI: the yellow HelpTip bubbles and the glowing (i) help-plate buttons on the spellbook, talents, map, collections, and other panels.",
                read = function() return CludesUIDB and CludesUIDB.hideTutorials or false end,
                write = function(v)
                    QDB().hideTutorials = v
                    if CludesUI._applyHideTutorials then CludesUI._applyHideTutorials() end
                end }
            items[#items + 1] = { key = "hideErrorMessages", label = "Error Messages",
                alias = "Hide Error Messages",
                tooltip = "Hides most red error messages (such as 'Not enough rage' or 'Ability is not ready yet'). Important errors like a full bag or quest log are still shown.",
                read = function() return CludesUIDB and CludesUIDB.hideErrorMessages or false end,
                write = function(v)
                    QDB().hideErrorMessages = v
                    -- Turning it off takes effect at the next reload; the apply
                    -- returns true while one is due.
                    if CludesUI._applyHideErrorMessages and CludesUI._applyHideErrorMessages() then
                        CludesUI:ShowConfirmPopup({
                            title       = "Reload Required",
                            message     = "Hidden error messages come back after a UI reload.",
                            confirmText = "Reload Now",
                            cancelText  = "Later",
                            reload      = true,
                        })
                    end
                end }
            items[#items + 1] = { key = "hideLootHistory", label = "Group Loot Rolls Window",
                alias = "Hide Loot Rolls Window",
                tooltip = "Hides Blizzard's \"Loot Rolls\" window -- the running list of dropped items showing who rolled what and who won. Use the cog to let it appear briefly and close itself instead. The Need/Greed roll popups themselves are not affected.",
                read = function() return CludesUIDB and CludesUIDB.hideLootHistory or false end,
                write = function(v)
                    QDB().hideLootHistory = v
                    if CludesUI._applyHideLootHistory then CludesUI._applyHideLootHistory() end
                    CludesUI:RefreshPage()  -- the Loot Rolls Window cog follows
                end }
            if RETAIL then
                items[#items + 1] = { key = "hideBanners", label = "Top Screen Banners",
                    alias = "Hide Banners",
                    tooltip = "Hides the big banners at the top of the screen.",
                    read = function() return CludesUIDB and CludesUIDB.hideBanners or false end,
                    write = function(v)
                        QDB().hideBanners = v
                        if CludesUI._applyHideBanners then CludesUI._applyHideBanners() end
                    end }
            end
            -- The same CludesUIDB.suppressErrors key and scriptErrors CVar as
            -- Global Settings > Developer, applied on login by the parent.
            items[#items + 1] = { key = "suppressErrors", label = "Lua Errors",
                alias = "Suppress Lua Errors",
                tooltip = "Hides the Lua error popup. The same setting as Global Settings > Developer.",
                read = function() return not (CludesUIDB and CludesUIDB.suppressErrors == false) end,
                write = function(v)
                    QDB().suppressErrors = v
                    if not InCombatLockdown() then CludesUI.SetCVar("scriptErrors", v and "0" or "1") end
                end }
            if RETAIL then
                items[#items + 1] = Toast("hideAlertToastsLoot", "Loot Toasts", "Hide Alert Toasts")
                items[#items + 1] = Toast("hideAlertToastsAchievements", "Achievement Toasts")
                items[#items + 1] = Toast("hideAlertToastsHousing", "Housing Toasts")
            end

            -- Global search sees row labels and tooltips only, so this row's
            -- entry, registered before the row (the index keeps the first one),
            -- carries the checklist's names as search text; it is never shown.
            if CludesUI._RegisterSearchEntry then
                local words = {}
                local function Word(s)
                    if not s then return end
                    words[#words + 1] = s
                    local loc = CludesUI.L(s)
                    if loc ~= s then words[#words + 1] = loc end
                end
                for i = 1, #items do
                    Word(items[i].label)
                    Word(items[i].alias)
                end
                local labelLoc = CludesUI.L(HBE_LABEL)
                CludesUI._RegisterSearchEntry(HBE_LABEL, labelLoc ~= HBE_LABEL and labelLoc or nil,
                    table.concat(words, " "), CludesUI._buildingModule, CludesUI._buildingPage,
                    parent._currentSection and parent._currentSection._sectionName)
            end

            local row1
            row1, h = W:DualRow(parent, y,
                { type="label", text=HBE_LABEL,
                  tooltip="Choose which Blizzard elements to hide." },
                { type="toggle", text="Skip Cinematics",
                  tooltip="When you press Escape or Space during a cinematic, the confirmation prompt is automatically accepted.",
                  getValue=function()
                      return CludesUIDB and CludesUIDB.skipCinematics or false
                  end,
                  setValue=function(v)
                      if not CludesUIDB then CludesUIDB = {} end
                      CludesUIDB.skipCinematics = v
                      CludesUI:RefreshPage()
                  end }
            );  y = y - h

            if not CludesUI._prebuilding then
                local leftRgn = row1._leftRegion
                local byKey = {}
                for i = 1, #items do byKey[items[i].key] = items[i] end
                local hbeDD, hbeDDRefresh = CludesUI.BuildVisOptsCBDropdown(
                    leftRgn, 210, leftRgn:GetFrameLevel() + 2, items,
                    function(key) return byKey[key].read() end,
                    function(key, v) byKey[key].write(v) end)
                PP.Point(hbeDD, "RIGHT", leftRgn, "RIGHT", -20, 0)
                leftRgn._control = hbeDD
                leftRgn._lastInline = nil
                CludesUI.RegisterWidgetRefresh(hbeDDRefresh)

                -- Loot Rolls Window cog (mode + auto-close delay), left of the list
                local function lootHistOff()
                    return not (CludesUIDB and CludesUIDB.hideLootHistory)
                end
                -- The delay only means anything in auto-close mode.
                local function delayOff()
                    return lootHistOff()
                        or (CludesUIDB and CludesUIDB.lootHistoryMode) ~= "autoclose"
                end
                CludesUI.BuildInlineCog(leftRgn, {
                    title = "Loot Rolls Window Settings",
                    minWidth = 300,
                    rows = {
                        { type="dropdown", label="Mode",
                          values={ hide = "Hide Completely", autoclose = "Close After Delay" },
                          order={ "hide", "autoclose" },
                          get=function() return (CludesUIDB and CludesUIDB.lootHistoryMode) or "hide" end,
                          set=function(v)
                            QDB().lootHistoryMode = v
                            if CludesUI._applyHideLootHistory then CludesUI._applyHideLootHistory() end
                          end },
                        { type="slider", label="Close After (sec)",
                          min=1, max=30, step=1,
                          disabled=delayOff,
                          get=function()
                            return (CludesUIDB and CludesUIDB.lootHistoryDelay) or 5
                          end,
                          set=function(v)
                            QDB().lootHistoryDelay = v
                            if CludesUI._applyHideLootHistory then CludesUI._applyHideLootHistory() end
                          end },
                    },
                    gap = 9, disabled = lootHistOff, disabledTooltip = "Group Loot Rolls Window",
                })

                -- Cog on Skip Cinematics (right region)
                local function cinematicsOff()
                    return not (CludesUIDB and CludesUIDB.skipCinematics)
                end
                CludesUI.BuildInlineCog(row1._rightRegion, {
                    title = "Cinematic Settings",
                    rows = {
                        { type="toggle", label="Automatically Skip If Possible",
                          get=function()
                              return CludesUIDB and CludesUIDB.skipCinematicsAuto or false
                          end,
                          set=function(v)
                              if not CludesUIDB then CludesUIDB = {} end
                              CludesUIDB.skipCinematicsAuto = v
                          end },
                    },
                    gap = 9, disabled = cinematicsOff, disabledTooltip = "Skip Cinematics",
                })
            end
        end

        local row2
        row2, h = W:DualRow(parent, y,
            { type="toggle", text="Quick Loot",
              tooltip="Enables auto loot and hides the loot window when looting. Hold Shift when looting to show.",
              getValue=function()
                  return CludesUIDB and CludesUIDB.quickLoot or false
              end,
              setValue=function(v)
                  if not CludesUIDB then CludesUIDB = {} end
                  CludesUIDB.quickLoot = v
                  if CludesUI._applyQuickLoot then CludesUI._applyQuickLoot() end
              end },
            { type="toggle", text="Auto-Fill Delete Confirmation",
              tooltip="Automatically types DELETE when throwing away a valuable item. Also allows you to press enter to accept the deletion.",
              getValue=function()
                  return CludesUIDB and CludesUIDB.autoFillDelete or false
              end,
              setValue=function(v)
                  if not CludesUIDB then CludesUIDB = {} end
                  CludesUIDB.autoFillDelete = v
                  CludesUI:RefreshPage()
              end }
        );  y = y - h

        -- Auto Repair | Auto Sell Junk
        local repairRow
        repairRow, h = W:DualRow(parent, y,
            { type="toggle", text="Auto Repair",
              tooltip="Automatically repair all gear when visiting a repair vendor.",
              getValue=function()
                  if not CludesUIDB then return true end
                  return CludesUIDB.autoRepair ~= false
              end,
              setValue=function(v)
                  if not CludesUIDB then CludesUIDB = {} end
                  CludesUIDB.autoRepair = v
                  CludesUI:RefreshPage()
              end },
            { type="toggle", text="Auto Sell Junk",
              tooltip="Automatically sell all junk items when visiting a vendor.",
              getValue=function()
                  if not CludesUIDB then return true end
                  return CludesUIDB.autoSellJunk ~= false
              end,
              setValue=function(v)
                  if not CludesUIDB then CludesUIDB = {} end
                  CludesUIDB.autoSellJunk = v
              end }
        );  y = y - h

        -- Cog on Auto Repair (left region)
        if not CludesUI._prebuilding then
            local leftRgn = repairRow._leftRegion
            local function repairOff()
                return not (CludesUIDB and CludesUIDB.autoRepair ~= false)
            end

            CludesUI.BuildInlineCog(leftRgn, {
                title = "Auto Repair Settings",
                rows = {
                    { type="toggle", label="Use Guild Bank Funds",
                      get=function()
                          if not CludesUIDB then return true end
                          return CludesUIDB.autoRepairGuild ~= false
                      end,
                      set=function(v)
                          if not CludesUIDB then CludesUIDB = {} end
                          CludesUIDB.autoRepairGuild = v
                      end },
                    -- Off (default) = short text "12o 34a"; on = coin icons.
                    { type="toggle", label="Coin Icons",
                      get=function()
                          return CludesUIDB and CludesUIDB.repairCoinIcons == true
                      end,
                      set=function(v)
                          if not CludesUIDB then CludesUIDB = {} end
                          CludesUIDB.repairCoinIcons = v
                      end },
                },
                gap = 9, disabled = repairOff, disabledTooltip = "Auto Repair",
            })
        end

        -- Hide Item Transforms (+ picker cog) | Auto Select Single Gossip (+ cog)
        local transformRow
        transformRow, h = W:DualRow(parent, y,
            { type="toggle", text="Hide Item Transforms (ex: Chef's Hat)",
              tooltip="Automatically removes cosmetic transforms when they are applied to you, such as profession gear, holiday costumes, toys and consumables. Use the cog to pick exactly which transforms are removed. Transforms applied during combat are removed when combat ends.",
              getValue=function()
                  return CludesUIDB and CludesUIDB.hideTransforms or false
              end,
              setValue=function(v)
                  if not CludesUIDB then CludesUIDB = {} end
                  CludesUIDB.hideTransforms = v
                  if CludesUI._applyHideTransforms then
                      CludesUI._applyHideTransforms()
                  end
                  CludesUI:RefreshPage()  -- update the picker cog disabled state
              end },
            { type="toggle", text="Auto Select Single Gossip",
              tooltip="Picks an NPC's only dialog option for you.",
              getValue=function()
                  return CludesUIDB and CludesUIDB.autoGossip or false
              end,
              setValue=function(v)
                  if not CludesUIDB then CludesUIDB = {} end
                  CludesUIDB.autoGossip = v
                  if CludesUI._applyAutoGossip then CludesUI._applyAutoGossip() end
                  CludesUI:RefreshPage()
              end }
        );  y = y - h

        -- Inline picker cog on Hide Item Transforms (left slot): opens the item
        -- checklist popup. Dimmed and inert while the toggle is off, mirroring
        -- the resource-bar spec-picker button.
        if not CludesUI._prebuilding then
            local rgn = transformRow._leftRegion
            local function hitOff()
                return not (CludesUIDB and CludesUIDB.hideTransforms)
            end
            CludesUI.BuildInlineCog(rgn, {
                gap = 9, tip = CludesUI.L("Choose which transforms are removed"),
                disabled = hitOff, disabledTooltip = "Hide Item Transforms",
                show = function() ShowTransformsPopup() end,
            })
        end

        -- Cog on Auto Select Single Gossip (right slot)
        if not CludesUI._prebuilding then
            local rightRgn = transformRow._rightRegion
            local function gossipOff()
                return not (CludesUIDB and CludesUIDB.autoGossip)
            end

            CludesUI.BuildInlineCog(rightRgn, {
                title = "Auto Gossip Settings",
                rows = {
                    { type="toggle", label="Hold Shift to Skip",
                      get=function()
                          if not CludesUIDB then return true end
                          return CludesUIDB.autoGossipShiftSkip ~= false
                      end,
                      set=function(v)
                          if not CludesUIDB then CludesUIDB = {} end
                          CludesUIDB.autoGossipShiftSkip = v
                      end },
                    { type="toggle", label="Disable in Instances",
                      get=function()
                          if not CludesUIDB then return true end
                          return CludesUIDB.autoGossipDisableInstance ~= false
                      end,
                      set=function(v)
                          if not CludesUIDB then CludesUIDB = {} end
                          CludesUIDB.autoGossipDisableInstance = v
                      end },
                    { type="toggle", label="Ignore Low Level Quests",
                      get=function()
                          return CludesUIDB and CludesUIDB.autoGossipIgnoreTrivial or false
                      end,
                      set=function(v)
                          if not CludesUIDB then CludesUIDB = {} end
                          CludesUIDB.autoGossipIgnoreTrivial = v
                      end },
                },
                gap = 9, disabled = gossipOff, disabledTooltip = "Auto Select Single Gossip",
            })
        end

        -- Type /cd to open Blizzard CDM | AH Current Expansion Only. The AH
        -- filter is not offered on WoW Forever (its runtime block does not
        -- exist there), so that slot is blank there.
        _, h = W:DualRow(parent, y,
            -- Cooldown Manager registers /cd at load from this key, so a change reloads
            { type="toggle", text="Type /cd to open Blizzard CDM",
              tooltip="Lets /cd open or close Blizzard's Cooldown Manager settings.",
              disabled=function() return not CludesUI._ModuleNS["CludesUICooldownManager"] end,
              disabledTooltip="Cooldown Manager",
              getValue=function()
                  return CludesUIDB and CludesUIDB.blizzCDMSlash == true
              end,
              setValue=function(v)
                  if not CludesUIDB then CludesUIDB = {} end
                  CludesUIDB.blizzCDMSlash = v and true or nil
                  CludesUI:ShowConfirmPopup({
                      title       = "Reload Required",
                      message     = "The /cd change applies after a UI reload.",
                      confirmText = "Reload Now",
                      cancelText  = "Later",
                      reload      = true,
                  })
              end },
            CludesUI.IS_FOREVER and CludesUI.BlankRowCfg() or
            { type="toggle", text="AH Current Expansion Only",
              tooltip="Automatically enables the 'Current Expansion Only' filter whenever you open the Auction House.",
              getValue=function()
                  return CludesUIDB and CludesUIDB.ahCurrentExpansion or false
              end,
              setValue=function(v)
                  if not CludesUIDB then CludesUIDB = {} end
                  CludesUIDB.ahCurrentExpansion = v
              end }
        );  y = y - h

        _, h = W:Spacer(parent, y, 20);  y = y - h

        ---------------------------------------------------------------------------
        --  EXTRAS
        ---------------------------------------------------------------------------
        hdr, h = W:SectionHeader(parent, "EXTRAS", y);  y = y - h
        -- The FPS Counter is the section's first mover, so the header's button
        -- takes it; the button explains itself while the counter is off.
        CludesUI.BuildSectionUnlockJump(hdr, { key = "CUI_FPS",
            disabled = function() return not CludesUI.QoLExtrasGet("showFPS") end,
            disabledTooltip = "Show FPS Counter" })

        -- Row 1: Show FPS Counter (left, with cog+swatch) | FPS Toggle Keybind (right)
        local fpsRow
        fpsRow, h = W:DualRow(parent, y,
            { type="toggle", text="Show FPS Counter",
              getValue=function()
                return CludesUI.QoLExtrasGet("showFPS") or false
              end,
              setValue=function(v)
                CludesUI.QoLExtrasSet("showFPS", v)
                if CludesUI._applyFPSDisplay then CludesUI._applyFPSDisplay() end
                CludesUI:RefreshPage()
              end },
            { type="label", text="FPS Toggle Keybind" }
        );  y = y - h

        -- Inline cog + color swatches on the FPS toggle (left region)
        if not CludesUI._prebuilding then
            local leftRgn = fpsRow._leftRegion
            local function fpsOff()
                return not CludesUI.QoLExtrasGet("showFPS")
            end

            -- Inline class + custom colour swatches, the same convention as the
            -- Secondary Stats row: the active mode renders at full alpha, the
            -- other dimmed, each with a naming tooltip.
            local function fpsMode()
                -- No mode saved: custom -- the look before the mode existed,
                -- which is white until a colour is actually picked.
                return CludesUI.QoLExtrasGet("fpsColorMode") or "custom"
            end
            local fpsUpdateState   -- forward: swatches reference it from OnClick
            local function fpsSetMode(v)
                CludesUI.QoLExtrasSet("fpsColorMode", v)
                if CludesUI._applyFPSDisplay then CludesUI._applyFPSDisplay() end
                if fpsUpdateState then fpsUpdateState() end
            end

            local fpsSwGet = function()
                local c = CludesUI.QoLExtrasGet("fpsColor")
                if c then return c.r, c.g, c.b, c.a end
                return 1, 1, 1, 1
            end
            local fpsSwSet = function(r, g, b, a)
                CludesUI.QoLExtrasSet("fpsColor", { r = r, g = g, b = b, a = a })
                CludesUI.QoLExtrasSet("fpsColorMode", "custom")
                if CludesUI._applyFPSDisplay then CludesUI._applyFPSDisplay() end
                if fpsUpdateState then fpsUpdateState() end
            end

            CludesUI.BuildInlineCog(leftRgn, {
                title = "FPS Counter Settings",
                rows = {
                    { type="toggle", label="Attach to Secondary Stats",
                      disabled=function()
                        return not CludesUI.QoLExtrasGet("showSecondaryStats")
                      end,
                      disabledTooltip="Secondary Stat Display",
                      get=function()
                        return CludesUI.QoLExtrasGet("fpsAttachToStats") or false
                      end,
                      set=function(v)
                        CludesUI.QoLExtrasSet("fpsAttachToStats", v)
                        if CludesUI._applyFPSDisplay then CludesUI._applyFPSDisplay() end
                      end },
                    -- Attached rows take the Secondary Stats font size, so this
                    -- has nothing to drive while the readout lives over there.
                    { type="slider", label="Text Size",
                      min=8, max=30, step=1,
                      disabled=function()
                        return CludesUI._fpsAttachedToStats
                            and CludesUI._fpsAttachedToStats() or false
                      end,
                      disabledTooltip="Attach to Secondary Stats",
                      requireState="disabled",
                      get=function()
                        return CludesUI.QoLExtrasGet("fpsTextSize") or 12
                      end,
                      set=function(v)
                        CludesUI.QoLExtrasSet("fpsTextSize", v)
                        if CludesUI._applyFPSDisplay then CludesUI._applyFPSDisplay() end
                      end },
                    { type="toggle", label="Show Local MS",
                      get=function()
                        local sl = CludesUI.QoLExtrasGet("fpsShowLocalMS")
                        if sl == nil then return true end
                        return sl
                      end,
                      set=function(v)
                        CludesUI.QoLExtrasSet("fpsShowLocalMS", v)
                        if CludesUI._applyFPSDisplay then CludesUI._applyFPSDisplay() end
                      end },
                    { type="toggle", label="Show World MS",
                      get=function()
                        return CludesUI.QoLExtrasGet("fpsShowWorldMS") or false
                      end,
                      set=function(v)
                        CludesUI.QoLExtrasSet("fpsShowWorldMS", v)
                        if CludesUI._applyFPSDisplay then CludesUI._applyFPSDisplay() end
                      end },
                    { type="toggle", label="Hide Local/World Label",
                      get=function()
                        return CludesUI.QoLExtrasGet("fpsHideLabel") or false
                      end,
                      set=function(v)
                        CludesUI.QoLExtrasSet("fpsHideLabel", v)
                        if CludesUI._applyFPSDisplay then CludesUI._applyFPSDisplay() end
                      end },
                    { type="slider", label="Update Interval", min=1, max=5, step=1,
                      get=function()
                        return CludesUI.QoLExtrasGet("fpsUpdateInterval") or 3
                      end,
                      set=function(v)
                        CludesUI.QoLExtrasSet("fpsUpdateInterval", v)
                        if CludesUI._applyFPSDisplay then CludesUI._applyFPSDisplay() end
                      end },
                },
                gap = 9, disabled = fpsOff, disabledTooltip = "Show FPS Counter",
            })

            -- Custom swatch (nearest the cog): a click switches to custom
            -- mode first; a second click opens the picker.
            local fpsSwatch, fpsUpdateSwatch = CludesUI.BuildColorSwatch(leftRgn, leftRgn:GetFrameLevel() + 5, fpsSwGet, fpsSwSet, true, 20)
            do
                local openPicker = fpsSwatch:GetScript("OnClick")
                fpsSwatch:SetScript("OnClick", function(self)
                    if fpsMode() ~= "custom" then fpsSetMode("custom") return end
                    if openPicker then openPicker(self) end
                end)
            end
            PP.Point(fpsSwatch, "RIGHT", leftRgn._lastInline or leftRgn._control, "LEFT", -8, 0)
            leftRgn._lastInline = fpsSwatch

            -- Class-colour swatch: live player class colour.
            local fpsClassSw, fpsUpdClass = CludesUI.BuildColorSwatch(
                leftRgn, leftRgn:GetFrameLevel() + 5,
                function()
                    local cc = CludesUI.GetClassColor(select(2, UnitClass("player")))
                    if cc then return cc.r, cc.g, cc.b end
                    return 1, 1, 1
                end,
                function() end, nil, 20)
            fpsClassSw:SetScript("OnClick", function() fpsSetMode("class") end)
            PP.Point(fpsClassSw, "RIGHT", leftRgn._lastInline, "LEFT", -8, 0)
            leftRgn._lastInline = fpsClassSw

            local fpsTips = { { fpsClassSw, "Class Color" }, { fpsSwatch, "Custom Color" } }
            for _, e in ipairs(fpsTips) do
                e[1]:HookScript("OnEnter", function() CludesUI.ShowWidgetTooltip(e[1], e[2]) end)
                e[1]:HookScript("OnLeave", function() CludesUI.HideWidgetTooltip() end)
            end

            -- Blocking overlays while Show FPS Counter is off (shown from the
            -- single refresh below, like the swatch alphas).
            local fpsBlocks = {}
            for _, e in ipairs(fpsTips) do
                local sw = e[1]
                local block = CreateFrame("Frame", nil, sw)
                block:SetAllPoints()
                block:SetFrameLevel(sw:GetFrameLevel() + 10)
                block:EnableMouse(true)
                block:SetScript("OnEnter", function()
                    CludesUI.ShowWidgetTooltip(sw, CludesUI.DisabledTooltip("Show FPS Counter"))
                end)
                block:SetScript("OnLeave", function() CludesUI.HideWidgetTooltip() end)
                fpsBlocks[#fpsBlocks + 1] = block
            end

            -- While the counter is off both swatches dim flat; while on, the
            -- active mode is bright and the other dimmed. One refresh owns
            -- both, plus the swatch fills (class color changes, custom picks).
            fpsUpdateState = function()
                if fpsUpdateSwatch then fpsUpdateSwatch() end
                if fpsUpdClass then fpsUpdClass() end
                local off = fpsOff()
                for _, block in ipairs(fpsBlocks) do block:SetShown(off) end
                local m = not off and fpsMode() or nil
                fpsClassSw:SetAlpha(m == "class" and 1 or 0.3)
                fpsSwatch:SetAlpha(m == "custom" and 1 or 0.3)
            end
            CludesUI.RegisterWidgetRefresh(fpsUpdateState)
            fpsUpdateState()
        end

        -- FPS Toggle Keybind (built into right region of fpsRow)
        if not CludesUI._prebuilding then
            local rightRgn = fpsRow._rightRegion
            local kbBtn, refresh = CludesUI.BuildKeybindButton(rightRgn, {
                w = 140, h = 30, font = 13,
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
            PP.Point(kbBtn, "RIGHT", rightRgn, "RIGHT", -20, 0)
            CludesUI.RegisterWidgetRefresh(refresh)
        end

        -- Row 2: Low Durability Warning (left, with cog+eye+swatch) | Disable Right Click Targeting (right)
        local durWarnRow
        durWarnRow, h = W:DualRow(parent, y,
            { type="toggle", text="Low Durability Warning",
              tooltip="Flashes a warning on screen when any equipped item drops below the configured durability threshold. Only triggers out of combat.",
              getValue=function()
                return CludesUIDB and CludesUIDB.repairWarning ~= false
              end,
              setValue=function(v)
                if not CludesUIDB then CludesUIDB = {} end
                CludesUIDB.repairWarning = v
                if CludesUI._syncDurWarnEvents then CludesUI._syncDurWarnEvents() end
                if not v and CludesUI._durWarnHidePreview then
                    CludesUI._durWarnHidePreview()
                end
                CludesUI:RefreshPage()
              end },
            { type="dropdown", text="Disable Right Click",
              tooltip="Suppresses right click targeting. Enemies applies everywhere. Allies In Combat only suppresses friendly targets while you are in combat, so you can still right click vendors and NPCs out of combat.\n\nNote: while this is active, holding Left+Right click to move forward won't work if your cursor is over a suppressed nameplate/unit, since this feature has to take over the right mouse button entirely to block targeting.",
              values={ ["_placeholder"]="..." }, order={ "_placeholder" },
              getValue=function() return "_placeholder" end,
              setValue=function() end }
        );  y = y - h

        -- Right slot: multi-select dropdown (Enemies / Allies In Combat).
        -- The backend stays two independent booleans; the dropdown is purely a
        -- front-end grouping, so existing disableRightClickTarget users are kept
        -- exactly as-is and Allies is additive (defaults off).
        if not CludesUI._prebuilding then
            local rcRgn = durWarnRow._rightRegion
            if rcRgn._control then rcRgn._control:Hide() end
            local rcItems = {
                { key = "enemy", label = "Enemies" },
                { key = "ally",  label = "Allies In Combat" },
            }
            local rcCB, rcCBRefresh = CludesUI.BuildVisOptsCBDropdown(
                rcRgn, 200, rcRgn:GetFrameLevel() + 2,
                rcItems,
                function(k)
                    if not CludesUIDB then return false end
                    if k == "enemy" then return CludesUIDB.disableRightClickTarget or false end
                    return CludesUIDB.disableRightClickTargetAllyCombat or false
                end,
                function(k, v)
                    if not CludesUIDB then CludesUIDB = {} end
                    if k == "enemy" then
                        CludesUIDB.disableRightClickTarget = v
                    else
                        CludesUIDB.disableRightClickTargetAllyCombat = v
                    end
                    if CludesUI._applyRightClickTarget then CludesUI._applyRightClickTarget() end
                end)
            PP.Point(rcCB, "RIGHT", rcRgn, "RIGHT", -20, 0)
            rcRgn._control = rcCB
            rcRgn._lastInline = nil
            CludesUI.RegisterWidgetRefresh(rcCBRefresh)
        end

        -- Inline: eyeball | color swatch | cog on the durability warning toggle
        if not CludesUI._prebuilding then
            local leftRgn = durWarnRow._leftRegion
            local function durOff()
                return CludesUIDB and CludesUIDB.repairWarning == false
            end

            -- Cog popup for durability settings (rightmost inline, closest to toggle)
            CludesUI.BuildInlineCog(leftRgn, {
                title = "Durability Settings",
                rows = {
                    { type="slider", label="Text Size",
                      min=10, max=50, step=1,
                      get=function()
                        return (CludesUIDB and CludesUIDB.durWarnTextSize) or 30
                      end,
                      set=function(v)
                        if not CludesUIDB then CludesUIDB = {} end
                        CludesUIDB.durWarnTextSize = v
                        if CludesUI._durWarnApplySettings then CludesUI._durWarnApplySettings() end
                      end },
                    { type="slider", label="Y-Offset",
                      min=-600, max=600, step=1,
                      get=function()
                        return CludesUIDB and CludesUIDB.durWarnYOffset or 250
                      end,
                      set=function(v)
                        if not CludesUIDB then CludesUIDB = {} end
                        CludesUIDB.durWarnYOffset = v
                        CludesUIDB.durWarnPos = nil  -- clear custom pos so slider always takes effect
                        if CludesUI._durWarnPreview then CludesUI._durWarnPreview() end
                      end },
                    { type="slider", label="Repair %",
                      min=5, max=100, step=1,
                      get=function()
                        return CludesUIDB and CludesUIDB.durWarnThreshold or 40
                      end,
                      set=function(v)
                        if not CludesUIDB then CludesUIDB = {} end
                        CludesUIDB.durWarnThreshold = v
                      end },
                    CludesUI.IS_FOREVER and { type="toggle", label="Ignore Thrown Weapons",
                      tooltip="Thrown weapons lose durability with every throw.",
                      get=function()
                        return CludesUIDB and CludesUIDB.durWarnIgnoreThrown ~= false
                      end,
                      set=function(v)
                        if not CludesUIDB then CludesUIDB = {} end
                        CludesUIDB.durWarnIgnoreThrown = v
                        if CludesUI._syncDurWarnEvents then CludesUI._syncDurWarnEvents() end
                      end } or nil,
                },
                gap = 9, disabled = durOff, disabledTooltip = "Low Durability Warning",
            })

            -- Color swatch (left of the cog)
            local durSwGet = function()
                local c = CludesUIDB and CludesUIDB.durWarnColor
                if c then return c.r, c.g, c.b end
                return 1, 0.27, 0.27
            end
            local durSwSet = function(r, g, b)
                if not CludesUIDB then CludesUIDB = {} end
                CludesUIDB.durWarnColor = { r = r, g = g, b = b }
                if CludesUI._applyDurWarn then CludesUI._applyDurWarn() end
            end
            local durSwatch, durUpdateSwatch = CludesUI.BuildColorSwatch(leftRgn, leftRgn:GetFrameLevel() + 5, durSwGet, durSwSet, nil, 20)
            PP.Point(durSwatch, "RIGHT", leftRgn._lastInline or leftRgn._control, "LEFT", -8, 0)
            leftRgn._lastInline = durSwatch

            -- Disabled overlay for swatch when durability warning is off
            local durSwBlock = CreateFrame("Frame", nil, durSwatch)
            durSwBlock:SetAllPoints()
            durSwBlock:SetFrameLevel(durSwatch:GetFrameLevel() + 10)
            durSwBlock:EnableMouse(true)
            durSwBlock:SetScript("OnEnter", function()
                CludesUI.ShowWidgetTooltip(durSwatch, CludesUI.DisabledTooltip("Low Durability Warning"))
            end)
            durSwBlock:SetScript("OnLeave", function() CludesUI.HideWidgetTooltip() end)

            CludesUI.RegisterWidgetRefresh(function()
                local off = durOff()
                if off then
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
            if durInitOff then durSwBlock:Show() else durSwBlock:Hide() end

            -- Eye icon to toggle durability warning preview (left of swatch)
            local EYE_VISIBLE   = CludesUI.EYE_VISIBLE_ICON
            local EYE_INVISIBLE = CludesUI.EYE_INVISIBLE_ICON
            local durPreviewShown = false
            local eyeBtn = CreateFrame("Button", nil, leftRgn)
            eyeBtn:SetSize(26, 26)
            eyeBtn:SetPoint("RIGHT", leftRgn._lastInline or leftRgn._control, "LEFT", -8, 0)
            leftRgn._lastInline = eyeBtn
            eyeBtn:SetFrameLevel(leftRgn:GetFrameLevel() + 5)
            CludesUI.SetGlyphAlpha(eyeBtn, durOff() and 0.15 or 0.4)
            local eyeTex = eyeBtn:CreateTexture(nil, "OVERLAY")
            eyeTex:SetAllPoints()
            local function RefreshDurEye()
                if durPreviewShown then
                    eyeTex:SetTexture(EYE_INVISIBLE)
                else
                    eyeTex:SetTexture(EYE_VISIBLE)
                end
            end
            RefreshDurEye()
            eyeBtn:SetScript("OnEnter", function(self)
                CludesUI.SetGlyphAlpha(self, 0.7)
                CludesUI.ShowWidgetTooltip(self, "Preview durability warning")
            end)
            eyeBtn:SetScript("OnLeave", function(self)
                CludesUI.HideWidgetTooltip()
                CludesUI.SetGlyphAlpha(self, 0.4)
            end)
            eyeBtn:SetScript("OnClick", function(self)
                durPreviewShown = not durPreviewShown
                RefreshDurEye()
                if durPreviewShown then
                    if CludesUI._applyDurWarn then CludesUI._applyDurWarn() end
                    if CludesUI._durWarnPreview then
                        CludesUI._durWarnPreview()
                    end
                else
                    if CludesUI._durWarnHidePreview then
                        CludesUI._durWarnHidePreview()
                    end
                end
            end)

            -- Blocking overlay for eye when durability warning is off
            local eyeBlock = CreateFrame("Frame", nil, eyeBtn)
            eyeBlock:SetAllPoints()
            eyeBlock:SetFrameLevel(eyeBtn:GetFrameLevel() + 10)
            eyeBlock:EnableMouse(true)
            eyeBlock:SetScript("OnEnter", function()
                CludesUI.ShowWidgetTooltip(eyeBtn, CludesUI.DisabledTooltip("Low Durability Warning"))
            end)
            eyeBlock:SetScript("OnLeave", function() CludesUI.HideWidgetTooltip() end)

            CludesUI.RegisterWidgetRefresh(function()
                local off = durOff()
                if off then
                    durPreviewShown = false
                    RefreshDurEye()
                    CludesUI.SetGlyphAlpha(eyeBtn, 0.15)
                    eyeBlock:Show()
                else
                    CludesUI.SetGlyphAlpha(eyeBtn, 0.4)
                    eyeBlock:Hide()
                end
            end)
            local eyeInitOff = durOff()
            CludesUI.SetGlyphAlpha(eyeBtn, eyeInitOff and 0.15 or 0.4)
            if eyeInitOff then eyeBlock:Show() else eyeBlock:Hide() end
        end

        -- Row 3: Secondary Stat Display (left, with cog+swatches) | Guild Chat Privacy (right)
        local row4
        row4, h = W:DualRow(parent, y,
            { type="toggle", text="Secondary Stat Display",
              tooltip=CludesUI.IS_FOREVER
                  and "Displays your character stats at the top left of the screen."
                  or "Displays secondary stat percentages (Crit, Haste, Mastery, Vers) at the top left of the screen.",
              getValue=function()
                return CludesUI.QoLExtrasGet("showSecondaryStats") or false
              end,
              setValue=function(v)
                CludesUI.QoLExtrasSet("showSecondaryStats", v)
                -- Turning the block off has to release an attached FPS readout
                -- back to its own frame, so route through the shared apply.
                if CludesUI._applyFPSDisplay then
                    CludesUI._applyFPSDisplay()
                elseif CludesUI._applySecondaryStats then
                    CludesUI._applySecondaryStats()
                end
                CludesUI:RefreshPage()
              end },
            { type="toggle", text="Guild Chat Privacy Cover",
              tooltip="Displays a spoiler tag over guild chat in the communities window that you can click to hide",
              getValue=function()
                return CludesUIDB and CludesUIDB.guildChatPrivacy or false
              end,
              setValue=function(v)
                if not CludesUIDB then CludesUIDB = {} end
                CludesUIDB.guildChatPrivacy = v
                if CludesUI._applyGuildChatPrivacy then CludesUI._applyGuildChatPrivacy() end
              end }
        );  y = y - h

        -- Inline cog + color swatches on Secondary Stat Display (left region)
        if not CludesUI._prebuilding then
            local leftRgn = row4._leftRegion
            local function statsOff()
                return not CludesUI.QoLExtrasGet("showSecondaryStats")
            end

            -- Cog popup: stat visibility/order + tertiary swatch pair + Scale
            local function tsMode()
                local m = CludesUI.QoLExtrasGet("tertiaryStatsColorMode")
                if m then return m end
                -- No mode saved: an old profile with a stored color was using it.
                return CludesUI.QoLExtrasGet("tertiaryStatsColor") and "custom" or "class"
            end
            local function tsSetMode(v)
                CludesUI.QoLExtrasSet("tertiaryStatsColorMode", v)
                if CludesUI._applySecondaryStats then CludesUI._applySecondaryStats() end
            end
            local STAT_LABELS = {
                crit = "Crit", haste = "Haste", mastery = "Mastery", vers = "Versatility",
                leech = "Leech", avoidance = "Avoidance", speed = "Speed",
            }
            local TERTIARY_STATS = { leech = true, avoidance = true, speed = true }
            local DEFAULT_STAT_ORDER = {
                "crit", "haste", "mastery", "vers", "leech", "avoidance", "speed",
            }
            local function StatItems()
                local order = CludesUI._secondaryStatsOrder
                    and CludesUI._secondaryStatsOrder() or DEFAULT_STAT_ORDER
                local items = {}
                for _, key in ipairs(order) do
                    items[#items + 1] = { key = key, label = STAT_LABELS[key] }
                end
                return items
            end
            -- Key stays `coloredPercentages`: it is the shipped setting
            -- name, and renaming it would drop everyone's saved choice.
            local coloredRow = { type = "toggle", label = "Colored Values",
                get = function()
                    return CludesUI.QoLExtrasGet("coloredPercentages") or false
                end,
                set = function(v)
                    CludesUI.QoLExtrasSet("coloredPercentages", v)
                    if CludesUI._applySecondaryStats then CludesUI._applySecondaryStats() end
                end }
            local abbreviateRow = { type = "toggle", label = "Abbreviate Stat Labels",
                get = function()
                    return CludesUI.QoLExtrasGet("secondaryStatsAbbreviateLabels") or false
                end,
                set = function(v)
                    CludesUI.QoLExtrasSet("secondaryStatsAbbreviateLabels", v)
                    if CludesUI._applySecondaryStats then CludesUI._applySecondaryStats() end
                end }
            local scaleRow = { type = "slider", label = "Scale", min = 50, max = 200, step = 5,
                get = function()
                    local pos = CludesUI.QoLExtrasGet("secondaryStatsPos")
                    return math.floor(((pos and pos.scale) or 1.0) * 100 + 0.5)
                end,
                set = function(v)
                    -- Shallow-copy so we never mutate the shared account-wide
                    -- fallback table in place; the write lands per-profile.
                    local prev = CludesUI.QoLExtrasGet("secondaryStatsPos")
                    local newPos = {}
                    if prev then for pk, pv in pairs(prev) do newPos[pk] = pv end end
                    newPos.scale = v / 100
                    CludesUI.QoLExtrasSet("secondaryStatsPos", newPos)
                    if CludesUI._applySecondaryStats then CludesUI._applySecondaryStats() end
                end }
            local cogRows, cogBtn, cogShow
            if CludesUI.IS_FOREVER then
                -- WoW Forever has no ratings or tertiaries: its stat catalog is
                -- picked in the grouped Choose Stats window
                -- (CUI_QoL_StatPicker.lua) and the shown stats ordered here.
                local FV_STAT = CludesUI._ModuleNS["CludesUIQoL"].FvStats.byKey
                cogRows = {
                    coloredRow,
                    abbreviateRow,
                    { type = "button", label = "Choose Stats...",
                      action = function()
                          -- The window takes the cog popup's place under the cog.
                          cogShow._popupFrame:Hide()
                          CludesUI._ShowStatPicker(cogBtn)
                      end },
                    { type = "reorder", label = "Reorder Shown Stats", maxVisible = 12,
                      items = function()
                          local hidden = CludesUI.QoLExtrasGet("secondaryStatsHidden")
                          local items = {}
                          for _, key in ipairs(CludesUI._secondaryStatsOrder()) do
                              if not (type(hidden) == "table" and hidden[key]) then
                                  items[#items + 1] = { key = key, label = CludesUI.L(FV_STAT[key].label) }
                              end
                          end
                          return items
                      end,
                      -- The hidden stats follow the shown ones, in their saved order.
                      set = function(keys)
                          local order, seen = {}, {}
                          for _, key in ipairs(keys) do
                              order[#order + 1] = key
                              seen[key] = true
                          end
                          for _, key in ipairs(CludesUI._secondaryStatsOrder()) do
                              if not seen[key] then order[#order + 1] = key end
                          end
                          CludesUI.QoLExtrasSet("secondaryStatsOrder", order)
                          CludesUI._applySecondaryStats()
                      end },
                    scaleRow,
                }
            else
                cogRows = {
                    coloredRow,
                    abbreviateRow,
                    { type = "toggle", label = "Show Raw Rating",
                      get = function()
                          return CludesUI.QoLExtrasGet("showSecondaryStatsRaw") or false
                      end,
                      set = function(v)
                          CludesUI.QoLExtrasSet("showSecondaryStatsRaw", v)
                          if v then CludesUI.QoLExtrasSet("showSecondaryStatsBoth", false) end
                          if CludesUI._applySecondaryStats then CludesUI._applySecondaryStats() end
                      end },
                    { type = "toggle", label = "Show % and Raw",
                      get = function()
                          return CludesUI.QoLExtrasGet("showSecondaryStatsBoth") or false
                      end,
                      set = function(v)
                          CludesUI.QoLExtrasSet("showSecondaryStatsBoth", v)
                          if v then CludesUI.QoLExtrasSet("showSecondaryStatsRaw", false) end
                          if CludesUI._applySecondaryStats then CludesUI._applySecondaryStats() end
                      end },
                    { type = "reordercheck", label = "Stats to Show",
                      items = StatItems,
                      hint = "Drag to Reorder",
                      get = function(key)
                          local hidden = CludesUI.QoLExtrasGet("secondaryStatsHidden")
                          return not (type(hidden) == "table" and hidden[key])
                      end,
                      set = function(key, shown)
                          local old = CludesUI.QoLExtrasGet("secondaryStatsHidden")
                          local hidden = {}
                          if type(old) == "table" then
                              for k, v in pairs(old) do hidden[k] = v end
                          end
                          if shown then
                              -- Tertiaries default off, so false is the explicit
                              -- per-profile override that keeps one checked.
                              if TERTIARY_STATS[key] then
                                  hidden[key] = false
                              else
                                  hidden[key] = nil
                              end
                          else
                              hidden[key] = true
                          end
                          CludesUI.QoLExtrasSet("secondaryStatsHidden", hidden)
                          if CludesUI._applySecondaryStats then CludesUI._applySecondaryStats() end
                      end,
                      setOrder = function(keys)
                          local order = {}
                          for i, key in ipairs(keys) do order[i] = key end
                          CludesUI.QoLExtrasSet("secondaryStatsOrder", order)
                          if CludesUI._applySecondaryStats then CludesUI._applySecondaryStats() end
                      end },
                    -- Class / custom swatch pair, the same convention as the
                    -- minimap border row: the active mode at full alpha, a
                    -- naming tooltip on each swatch.
                    { type = "multiswatch", label = "Tertiary Label Color",
                      disabled = function()
                          local hidden = CludesUI.QoLExtrasGet("secondaryStatsHidden")
                          return type(hidden) == "table"
                              and hidden.leech and hidden.avoidance and hidden.speed
                      end,
                      disabledTooltip = "a tertiary stat in Stats to Show",
                      swatches = {
                          { tooltip = "Class Color",
                            getValue = function()
                                local cc = CludesUI.GetClassColor(select(2, UnitClass("player")))
                                if cc then return cc.r, cc.g, cc.b end
                                return 1, 1, 1
                            end,
                            onClick = function() tsSetMode("class") end,
                            refreshAlpha = function() return tsMode() == "class" and 1 or 0.3 end },
                          { tooltip = "Custom Color",
                            getValue = function()
                                local c = CludesUI.QoLExtrasGet("tertiaryStatsColor")
                                if c then return c.r, c.g, c.b end
                                return 1, 1, 1
                            end,
                            setValue = function(r, g, b)
                                CludesUI.QoLExtrasSet("tertiaryStatsColor", { r = r, g = g, b = b })
                                CludesUI.QoLExtrasSet("tertiaryStatsColorMode", "custom")
                                if CludesUI._applySecondaryStats then CludesUI._applySecondaryStats() end
                            end,
                            -- First click switches to custom; a second opens the picker.
                            onClick = function(self, ...)
                                if tsMode() ~= "custom" then tsSetMode("custom") return end
                                if self._eabOrigClick then self._eabOrigClick(self, ...) end
                            end,
                            refreshAlpha = function() return tsMode() == "custom" and 1 or 0.3 end },
                      } },
                    scaleRow,
                }
            end
            cogBtn, cogShow = CludesUI.BuildInlineCog(leftRgn, {
                title = "Secondary Stats Settings",
                rows = cogRows,
                disabled = statsOff, disabledTooltip = "Secondary Stat Display",
            })

            -- Inline default + class + custom colour swatches, following the
            -- minimap border's swatch-row convention: the active mode renders
            -- at full alpha, the others dimmed, each with a naming tooltip.
            local function ssMode()
                local m = CludesUI.QoLExtrasGet("secondaryStatsColorMode")
                if m then return m end
                -- No mode saved: a stored color was in use, otherwise class
                -- color -- the pre-mode default look.
                return CludesUI.QoLExtrasGet("secondaryStatsColor") and "custom" or "class"
            end
            local ssUpdateState   -- forward: swatches reference it from OnClick
            local function ssSetMode(v)
                CludesUI.QoLExtrasSet("secondaryStatsColorMode", v)
                if CludesUI._applySecondaryStats then CludesUI._applySecondaryStats() end
                if ssUpdateState then ssUpdateState() end
            end

            -- Custom swatch (nearest the cog): stored custom colour. A
            -- click switches to custom mode first; a second click opens the
            -- picker (same two-step as the minimap border swatches).
            local ssCustom, ssUpdCustom = CludesUI.BuildColorSwatch(
                leftRgn, leftRgn:GetFrameLevel() + 5,
                function()
                    local c = CludesUI.QoLExtrasGet("secondaryStatsColor")
                    if c then return c.r, c.g, c.b end
                    return 1, 1, 1
                end,
                function(r, g, b)
                    CludesUI.QoLExtrasSet("secondaryStatsColor", { r = r, g = g, b = b })
                    CludesUI.QoLExtrasSet("secondaryStatsColorMode", "custom")
                    if CludesUI._applySecondaryStats then CludesUI._applySecondaryStats() end
                    if ssUpdateState then ssUpdateState() end
                end, nil, 20)
            do
                local openPicker = ssCustom:GetScript("OnClick")
                ssCustom:SetScript("OnClick", function(self)
                    if ssMode() ~= "custom" then ssSetMode("custom") return end
                    if openPicker then openPicker(self) end
                end)
            end
            PP.Point(ssCustom, "RIGHT", leftRgn._lastInline or leftRgn._control, "LEFT", -8, 0)
            leftRgn._lastInline = ssCustom

            -- Class-colour swatch: live player class colour.
            local ssClass, ssUpdClass = CludesUI.BuildColorSwatch(
                leftRgn, leftRgn:GetFrameLevel() + 5,
                function()
                    local cc = CludesUI.GetClassColor(select(2, UnitClass("player")))
                    if cc then return cc.r, cc.g, cc.b end
                    return 1, 1, 1
                end,
                function() end, nil, 20)
            ssClass:SetScript("OnClick", function() ssSetMode("class") end)
            PP.Point(ssClass, "RIGHT", leftRgn._lastInline, "LEFT", -8, 0)
            leftRgn._lastInline = ssClass

            -- Multicolored swatch (outermost): the per-stat palette, previewed
            -- by its first hue (crit gold).
            local ssMulti, ssUpdMulti = CludesUI.BuildColorSwatch(
                leftRgn, leftRgn:GetFrameLevel() + 5,
                function() return 1, 209 / 255, 0 end,
                function() end, nil, 20)
            ssMulti:SetScript("OnClick", function() ssSetMode("palette") end)
            PP.Point(ssMulti, "RIGHT", leftRgn._lastInline, "LEFT", -8, 0)
            leftRgn._lastInline = ssMulti

            local ssTips = { { ssMulti, "Multicolored" }, { ssClass, "Class Color" }, { ssCustom, "Custom Color" } }
            for _, e in ipairs(ssTips) do
                e[1]:HookScript("OnEnter", function() CludesUI.ShowWidgetTooltip(e[1], e[2]) end)
                e[1]:HookScript("OnLeave", function() CludesUI.HideWidgetTooltip() end)
            end

            -- Blocking overlays while Secondary Stat Display is off (shown from
            -- the single refresh below, like the swatch alphas).
            local ssBlocks = {}
            for _, e in ipairs(ssTips) do
                local sw = e[1]
                local block = CreateFrame("Frame", nil, sw)
                block:SetAllPoints()
                block:SetFrameLevel(sw:GetFrameLevel() + 10)
                block:EnableMouse(true)
                block:SetScript("OnEnter", function()
                    CludesUI.ShowWidgetTooltip(sw, CludesUI.DisabledTooltip("Secondary Stat Display"))
                end)
                block:SetScript("OnLeave", function() CludesUI.HideWidgetTooltip() end)
                ssBlocks[#ssBlocks + 1] = block
            end

            -- While the display is off every swatch dims flat; while on, the
            -- active mode is bright and the others dimmed. One refresh owns
            -- both, plus the swatch fills (class color changes, custom picks).
            ssUpdateState = function()
                if ssUpdCustom then ssUpdCustom() end
                if ssUpdClass then ssUpdClass() end
                if ssUpdMulti then ssUpdMulti() end
                local off = statsOff()
                for _, block in ipairs(ssBlocks) do block:SetShown(off) end
                local m = not off and ssMode() or nil
                ssMulti:SetAlpha(m == "palette" and 1 or 0.3)
                ssClass:SetAlpha(m == "class" and 1 or 0.3)
                ssCustom:SetAlpha(m == "custom" and 1 or 0.3)
            end
            CludesUI.RegisterWidgetRefresh(ssUpdateState)
            ssUpdateState()
        end

        -- Row 4: Rested Indicator (left; mirrored in the Unit Frames player
        -- EXTRAS, CludesUI.RestedIndicatorCfg) |
        local restedRow
        restedRow, h = W:DualRow(parent, y,
            CludesUI.RestedIndicatorCfg(),
            { type="toggle", text="Target Distance (Range) Text",
              tooltip="Shows the approximate distance to your current target as movable on-screen text (default 30-35). Use the cog for format, alignment, and text size; use Layout Mode to position or Anchor to your Player Frame.",
              getValue=function()
                  return CludesUIDB and CludesUIDB.targetDistanceEnabled or false
              end,
              setValue=function(v)
                  if not CludesUIDB then CludesUIDB = {} end
                  CludesUIDB.targetDistanceEnabled = v
                  if CludesUI._applyTargetDistance then CludesUI._applyTargetDistance() end
                  CludesUI:RefreshPage()
              end }
        );  y = y - h

        -- Inline cog on Rested Indicator (left region): Animated, Size, X/Y offsets
        CludesUI.BuildRestedIndicatorCog(restedRow._leftRegion)

        -- Target Distance settings cog (right slot of the Rested row)
        if not CludesUI._prebuilding then
            local rgn = restedRow._rightRegion
            local function tdOff()
                return not (CludesUIDB and CludesUIDB.targetDistanceEnabled)
            end

            local tdFormatValues = {
                range = "Range (30-35)",
                plus  = "Lower Bound (30+)",
                min   = "Minimum (30)",
            }
            local tdFormatOrder = { "range", "plus", "min" }
            local tdAlignValues = {
                LEFT   = "Left",
                CENTER = "Center",
                RIGHT  = "Right",
            }
            local tdAlignOrder = { "LEFT", "CENTER", "RIGHT" }

            CludesUI.BuildInlineCog(rgn, {
                title = "Target Distance Settings",
                minWidth = 280,
                rows = {
                    { type="dropdown", label="Format",
                      values=tdFormatValues, order=tdFormatOrder,
                      get=function()
                        local f = CludesUIDB and CludesUIDB.targetDistanceFormat
                        if f == "plus" or f == "min" or f == "range" then return f end
                        return "range"
                      end,
                      set=function(v)
                        if not CludesUIDB then CludesUIDB = {} end
                        CludesUIDB.targetDistanceFormat = v
                        if CludesUI._applyTargetDistanceFrame then CludesUI._applyTargetDistanceFrame() end
                      end },
                    { type="dropdown", label="Text Align",
                      values=tdAlignValues, order=tdAlignOrder,
                      get=function()
                        local a = CludesUIDB and CludesUIDB.targetDistanceAlign
                        if a == "LEFT" or a == "CENTER" or a == "RIGHT" then return a end
                        return "CENTER"
                      end,
                      set=function(v)
                        if not CludesUIDB then CludesUIDB = {} end
                        CludesUIDB.targetDistanceAlign = v
                        if CludesUI._applyTargetDistanceFrame then CludesUI._applyTargetDistanceFrame() end
                      end },
                    { type="slider", label="Text Size",
                      min=10, max=48, step=1,
                      get=function()
                        return (CludesUIDB and CludesUIDB.targetDistanceTextSize) or 18
                      end,
                      set=function(v)
                        if not CludesUIDB then CludesUIDB = {} end
                        CludesUIDB.targetDistanceTextSize = v
                        if CludesUI._applyTargetDistanceFrame then CludesUI._applyTargetDistanceFrame() end
                      end },
                    { type="dropdown", label="Frame Strata",
                      tooltip="Controls the order that overlapping elements display in. Set higher to show above other elements.",
                      values = CludesUI.FRAME_STRATA_LABELS,
                      order = CludesUI.FRAME_STRATA_ORDER_BASE,
                      get=function()
                        return (CludesUIDB and CludesUIDB.targetDistanceStrata) or "HIGH"
                      end,
                      set=function(v)
                        if not CludesUIDB then CludesUIDB = {} end
                        CludesUIDB.targetDistanceStrata = v
                        if CludesUI._applyTargetDistanceFrame then CludesUI._applyTargetDistanceFrame() end
                      end },
                },
                footer = { unlockKey = "CUI_TargetDistance" },
                gap = 9, disabled = tdOff, disabledTooltip = "Target Distance (Range) Text",
            })
        end

        -- Row 5: Environment Ping keybind (left) | Show Coordinates on Map (+ cog)
        local pingRow
        pingRow, h = W:DualRow(parent, y,
            { type="label", text="Environment Ping" },
            { type="toggle", text="Show Coordinates on Map",
              tooltip="Displays cursor and player coordinates at the bottom of the world map.",
              getValue=function()
                  return CludesUIDB and CludesUIDB.mapCoords or false
              end,
              setValue=function(v)
                  if not CludesUIDB then CludesUIDB = {} end
                  CludesUIDB.mapCoords = v
                  if CludesUI._applyMapCoords then CludesUI._applyMapCoords() end
                  CludesUI:RefreshPage()
              end }
        );  y = y - h
        -- Cog on Show Coordinates on Map (right region)
        if not CludesUI._prebuilding then
            local function coordsOff()
                return not (CludesUIDB and CludesUIDB.mapCoords)
            end
            CludesUI.BuildInlineCog(pingRow._rightRegion, {
                title = "Map Coordinates Settings",
                rows = {
                    { type = "slider", label = "Text Size", min = 8, max = 24, step = 1,
                      get = function()
                          return (CludesUIDB and CludesUIDB.mapCoordsTextSize) or 12
                      end,
                      set = function(v)
                          if not CludesUIDB then CludesUIDB = {} end
                          CludesUIDB.mapCoordsTextSize = v
                          if CludesUI._applyMapCoords then CludesUI._applyMapCoords() end
                      end },
                },
                gap = 9, disabled = coordsOff, disabledTooltip = "Show Coordinates on Map",
            })
        end
        if not CludesUI._prebuilding then
            local rgn = pingRow._leftRegion
            local kbBtn, refresh = CludesUI.BuildKeybindButton(rgn, {
                w = 140, h = 30, font = 13, mouse = true,
                get = function() return CludesUIDB.envPingKey end,
                set = function(v)
                    -- The hold key cannot be the button it claims.
                    local base = v and v:match("[^%-]+$")
                    if base == "BUTTON1" or base == "BUTTON2" then return end
                    CludesUIDB.envPingKey = v
                    if CludesUI._applyEnvPing then CludesUI._applyEnvPing() end
                end,
                tooltip = "While held, left-clicking the world sends a ping that ignores units and only targets the environment.\n\nLeft-click to set a keybind.\nRight-click to unbind.",
            })
            PP.Point(kbBtn, "RIGHT", rgn, "RIGHT", -20, 0)
            CludesUI.RegisterWidgetRefresh(refresh)
        end

        -- Auto-Accept Resurrection: right of Row 6, or its own row on WoW Forever.
        local resCfg = { type="toggle", text="Auto-Accept Resurrection",
            tooltip="Automatically accepts resurrections from players who are out of combat, such as raid resses after a wipe. Use the cog to also accept combat resurrections.",
            getValue=function()
                return CludesUIDB and CludesUIDB.autoAcceptRes or false
            end,
            setValue=function(v)
                if not CludesUIDB then CludesUIDB = {} end
                CludesUIDB.autoAcceptRes = v
                if CludesUI._applyAutoAcceptRes then CludesUI._applyAutoAcceptRes() end
                CludesUI:RefreshPage()
            end }
        local function BuildResCog(rgn)
            if CludesUI._prebuilding then return end
            CludesUI.BuildInlineCog(rgn, {
                title = "Auto-Accept Resurrection",
                rows = {
                    { type="toggle", label="Accept Combat Resurrections",
                      get=function()
                          return CludesUIDB and CludesUIDB.autoAcceptResCombat or false
                      end,
                      set=function(v)
                          if not CludesUIDB then CludesUIDB = {} end
                          CludesUIDB.autoAcceptResCombat = v
                      end },
                },
                gap = 9,
                disabled = function() return not (CludesUIDB and CludesUIDB.autoAcceptRes) end,
                disabledTooltip = "Auto-Accept Resurrection",
            })
        end

        -- Row 6: Transparent World Map Sidebars (left) | Auto-Accept Resurrection. Not offered
        -- on WoW Forever: Forever Essentials has its own map background option there.
        if not CludesUI.IS_FOREVER then
            local sidebarsRow
            sidebarsRow, h = W:DualRow(parent, y,
                { type="toggle", text="Transparent World Map Sidebars",
                  tooltip="Makes the black bars beside the maximized world map transparent, and lets you click, turn the camera and zoom through them. Use the cog to set their opacity.",
                  getValue=function()
                      return CludesUIDB and CludesUIDB.mapSidebarsClear or false
                  end,
                  setValue=function(v)
                      if not CludesUIDB then CludesUIDB = {} end
                      CludesUIDB.mapSidebarsClear = v
                      if CludesUI._applyMapSidebars then CludesUI._applyMapSidebars() end
                      CludesUI:RefreshPage()
                  end },
                resCfg
            );  y = y - h
            BuildResCog(sidebarsRow._rightRegion)
            -- Cog on Transparent World Map Sidebars (left region)
            if not CludesUI._prebuilding then
                local function sidebarsOff()
                    return not (CludesUIDB and CludesUIDB.mapSidebarsClear)
                end
                CludesUI.BuildInlineCog(sidebarsRow._leftRegion, {
                    title = "World Map Sidebars Settings",
                    rows = {
                        { type = "slider", label = "Opacity", min = 0, max = 100, step = 5,
                          get = function()
                              return (CludesUIDB and CludesUIDB.mapSidebarsOpacity) or 0
                          end,
                          set = function(v)
                              if not CludesUIDB then CludesUIDB = {} end
                              CludesUIDB.mapSidebarsOpacity = v
                              if CludesUI._applyMapSidebars then CludesUI._applyMapSidebars() end
                          end },
                    },
                    gap = 9, disabled = sidebarsOff, disabledTooltip = "Transparent World Map Sidebars",
                })
            end
        else
            local resRow
            resRow, h = W:DualRow(parent, y, resCfg, CludesUI.BlankRowCfg());  y = y - h
            BuildResCog(resRow._leftRegion)
        end

        _, h = W:Spacer(parent, y, 20);  y = y - h

        ---------------------------------------------------------------------------
        --  CROSSHAIR
        ---------------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "CROSSHAIR", y);  y = y - h

        -- Crosshair: per-profile live in the QoL DB (_ECL_AceDB.profile),
        -- with the account-wide CludesUIDB root as the inherited default.
        local function cdb() return _G._ECL_AceDB and _G._ECL_AceDB.profile end
        local function cget(k)
            local p = cdb()
            if p and p[k] ~= nil then return p[k] end
            return CludesUIDB and CludesUIDB[k]
        end
        local function cset(k, v) local p = cdb(); if p then p[k] = v end end
        local function crosshairOff()
            return (cget("crosshairSize") or "None") == "None"
        end

        -- True when the effective thickness is custom (would display as
        -- "Custom" if enabled) -- i.e. H/V widths differ or don't match a preset.
        -- Checked regardless of None so a saved custom config can be restored.
        local function crosshairIsCustom()
            local P = CludesUI.CROSSHAIR_PRESETS
            local s = cget("crosshairSize")
            local sizeForBase = (s and s ~= "None" and s) or "Normal"
            local base = (P and (P[sizeForBase] or P.Normal)) or { width = 2 }
            local hw = cget("crosshairHWidth") or base.width
            local vw = cget("crosshairVWidth") or base.width
            if hw ~= vw then return true end
            if P then
                for _, p in pairs(P) do if p.width == hw then return false end end
            end
            return true
        end

        -- Row 1: Character Crosshair (left: dropdown + cog + swatch) | Visibility
        local crosshairRow
        crosshairRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Character Crosshair",
              tooltip="Displays a crosshair at the center of the screen.",
              -- "Custom" is only selectable when a custom thickness is
              -- stored (re-evaluated each time the menu opens); otherwise it's
              -- greyed, since picking it would just produce a preset look.
              itemDisabled=function(v) return v == "custom" and not crosshairIsCustom() end,
			  itemDisabledTooltip=function(v)
				if v == "custom" then return "This option requires a custom thickness to be set." end
      		  end,
              -- The shown value is derived from the actual thickness: a preset name
              -- when the width matches one, otherwise "Custom". "Custom" is also
              -- selectable -- picking it re-enables using the user's stored values
              values={ ["None"]="None", ["Thin"]="Thin", ["Normal"]="Normal", ["Thick"]="Thick", ["custom"]="Custom" },
              order={ "None", "Thin", "Normal", "Thick", "custom" },
              getValue=function()
                local size = cget("crosshairSize") or "None"
                if size == "None" then return "None" end
                local P = CludesUI.CROSSHAIR_PRESETS
                local base = (P and (P[size] or P.Normal)) or { width = 2 }
                local hw = cget("crosshairHWidth") or base.width
                local vw = cget("crosshairVWidth") or base.width
                if hw == vw and P then
                    for name, p in pairs(P) do
                        if p.width == hw then return name end
                    end
                end
                return "custom"
              end,
              setValue=function(v)
                local p = cdb()
                if not p then return end
                p.crosshairSize = v
                -- Presets exist mainly for backwards compatibility. They stamp
                -- only the thickness baseline so Thin/Normal/Thick stay distinct
                -- and the cog reflects them. Length is not touched: it defaults
                -- to the preset length (40) only while unset, and once a user
                -- customises it, it persists across preset changes.
                local preset = CludesUI.CROSSHAIR_PRESETS and CludesUI.CROSSHAIR_PRESETS[v]
                if preset then
                    p.crosshairHWidth = preset.width
                    p.crosshairVWidth = preset.width
                end
                if CludesUI._applyCrosshair then CludesUI._applyCrosshair() end
                CludesUI:RefreshPage()
              end },
            { type="dropdown", text="Visibility",
              tooltip="Choose when the crosshair is shown.",
              disabled=function() return crosshairOff() end,
              disabledTooltip="Enable the crosshair to set its visibility.", rawTooltip=true,
              -- Real control is a multi-select checkbox dropdown injected below;
              -- this placeholder just provides the labelled right-region slot.
              values={ ["_placeholder"]="..." }, order={ "_placeholder" },
              getValue=function() return "_placeholder" end,
              setValue=function() end }
        );  y = y - h

        -- Visibility: multi-select checkbox dropdown (Always / Combat / Instances),
        -- backed by the single crosshairVisibility string for backwards compat:
        --   always | combat | instances | instances_combat
        -- "Always" is the base state. Picking it
        -- clears the others; clearing both reverts to it.
        if not CludesUI._prebuilding then
            local visRgn = crosshairRow._rightRegion
            if visRgn._control then visRgn._control:Hide() end

            local function curVis() return cget("crosshairVisibility") or "always" end
            local visItems = {
                { key = "always",    label = "Always",
                  tooltip = "Always show the crosshair." },
                { key = "combat",    label = "Combat",
                  tooltip = "Show only while in combat. Combine with Instances to show only during instanced combat." },
                { key = "instances", label = "Instances",
                  tooltip = "Show only while in a dungeon, raid, arena or battleground. Combine with Combat to show only during instanced combat." },
            }
            local visCB, visCBRefresh = CludesUI.BuildVisOptsCBDropdown(
                visRgn, 200, visRgn:GetFrameLevel() + 2,
                visItems,
                function(k)
                    local v = curVis()
                    if k == "always"    then return v == "always" end
                    if k == "combat"    then return v == "combat" or v == "instances_combat" end
                    return v == "instances" or v == "instances_combat"
                end,
                function(k, on)
                    local v = curVis()
                    local combat    = (v == "combat" or v == "instances_combat")
                    local instances = (v == "instances" or v == "instances_combat")
                    if k == "always" then
                        if not on then return end  -- can't un-pick the base state directly
                        combat, instances = false, false
                    elseif k == "combat" then
                        combat = on
                    else
                        instances = on
                    end
                    local nv = "always"
                    if combat and instances then nv = "instances_combat"
                    elseif combat then nv = "combat"
                    elseif instances then nv = "instances" end
                    cset("crosshairVisibility", nv)
                    if CludesUI._applyCrosshair then CludesUI._applyCrosshair() end
                end)
            PP.Point(visCB, "RIGHT", visRgn, "RIGHT", -20, 0)
            visRgn._control = visCB
            visRgn._lastInline = nil

            -- Disabled overlay: grey + block when the crosshair is off, matching
            -- the placeholder's disabled state.
            local visBlock = CreateFrame("Frame", nil, visCB)
            visBlock:SetAllPoints()
            visBlock:SetFrameLevel(visCB:GetFrameLevel() + 20)
            visBlock:EnableMouse(true)
            visBlock:SetScript("OnEnter", function()
                CludesUI.ShowWidgetTooltip(visCB, "Enable the crosshair to set its visibility.")
            end)
            visBlock:SetScript("OnLeave", function() CludesUI.HideWidgetTooltip() end)
            local function visUpdateDisabled()
                if crosshairOff() then
                    visCB:SetAlpha(0.4); visBlock:Show()
                else
                    visCB:SetAlpha(1); visBlock:Hide()
                end
            end
            CludesUI.RegisterWidgetRefresh(visCBRefresh)
            CludesUI.RegisterWidgetRefresh(visUpdateDisabled)
            visUpdateDisabled()
        end

        -- Inline cog on the crosshair dropdown (left region) for expanded options
        if not CludesUI._prebuilding then
            local leftRgn = crosshairRow._leftRegion
            local function chCogOff() return crosshairOff() end
            local function presetThick()
                local s = cget("crosshairSize")
                local P = CludesUI.CROSSHAIR_PRESETS
                local p = P and (P[s] or P.Normal)
                return (p and p.width) or 2
            end
            local function applyCH()
                if CludesUI._applyCrosshair then CludesUI._applyCrosshair() end
            end
            local function dbset(k, v)
                cset(k, v)
                applyCH()
            end
            -- Re-resolve the size dropdown's label so it shows "Custom" (or snaps
            -- back to a preset) live when the thickness is changed in this cog.
            local function refreshSizeLabel()
                local ctrl = crosshairRow._leftRegion and crosshairRow._leftRegion._control
                if ctrl and ctrl._refreshLabel then ctrl._refreshLabel() end
            end

            local chCogRows = {
                    { type="slider", label="H Length", min=1, max=500, step=1,
                      get=function() return cget("crosshairHLength") or 40 end,
                      set=function(v) dbset("crosshairHLength", v) end },
                    { type="slider", label="H Width", min=1, max=20, step=1,
                      get=function() return cget("crosshairHWidth") or presetThick() end,
                      set=function(v) dbset("crosshairHWidth", v); refreshSizeLabel() end },
                    { type="slider", label="V Length", min=1, max=500, step=1,
                      get=function() return cget("crosshairVLength") or 40 end,
                      set=function(v) dbset("crosshairVLength", v) end },
                    { type="slider", label="V Width", min=1, max=20, step=1,
                      get=function() return cget("crosshairVWidth") or presetThick() end,
                      set=function(v) dbset("crosshairVWidth", v); refreshSizeLabel() end },
                    { type="slider", label="Border", min=0, max=5, step=1,
                      get=function() return cget("crosshairBorderSize") or 0 end,
                      set=function(v) dbset("crosshairBorderSize", v) end },
                    { type="colorpicker", label="Border Color", hasAlpha=true,
                      get=function()
                          local bc = cget("crosshairBorderColor")
                          if bc then return bc.r, bc.g, bc.b, bc.a end
                          return 0, 0, 0, 1
                      end,
                      set=function(r, g, b, a)
                          cset("crosshairBorderColor", { r = r, g = g, b = b, a = a or 1 })
                          applyCH()
                      end },
                    { type="slider", label="X Offset", min=-200, max=200, step=1,
                      get=function() return cget("crosshairXOffset") or 0 end,
                      set=function(v) dbset("crosshairXOffset", v) end },
                    { type="slider", label="Y Offset", min=-200, max=200, step=1,
                      get=function() return cget("crosshairYOffset") or 0 end,
                      set=function(v) dbset("crosshairYOffset", v) end },
                    { type="dropdown", label="Frame Strata",
                      tooltip="Controls the order that overlapping elements display in. Set higher to show above other elements.",
                      values = CludesUI.FRAME_STRATA_LABELS,
                      order = CludesUI.FRAME_STRATA_ORDER_BASE,
                      get=function() return cget("crosshairStrata") or "MEDIUM" end,
                      set=function(v) dbset("crosshairStrata", v) end },
            }
            -- Holy Paladin uses a 40yd out-of-range cutoff by default; let
            -- paladins opt into a melee (5yd) cutoff. Shown only for Paladins.
            if select(2, UnitClass("player")) == "PALADIN" then
                chCogRows[#chCogRows + 1] = {
                    type="toggle", label="Show Melee Range for Hpal",
                    get=function() return cget("crosshairHpalMelee") == true end,
                    set=function(v)
                        cset("crosshairHpalMelee", v)
                        if CludesUI._RefreshCrosshairCutoffRange then CludesUI._RefreshCrosshairCutoffRange() end
                        applyCH()
                    end,
                }
            end

            CludesUI.BuildInlineCog(leftRgn, {
                title = "Crosshair Options",
                rows = chCogRows,
                gap = 9, disabled = chCogOff, disabledTooltip = "Character Crosshair",
            })
        end

        -- Inline color swatch on the crosshair dropdown (left region)
        if not CludesUI._prebuilding then
            local leftRgn = crosshairRow._leftRegion

            local chSwGet = function()
                local c = cget("crosshairColor")
                if c then return c.r, c.g, c.b, c.a end
                return 1, 1, 1, 0.75
            end
            local chSwSet = function(r, g, b, a)
                cset("crosshairColor", { r = r, g = g, b = b, a = a or 1 })
                if CludesUI._applyCrosshair then CludesUI._applyCrosshair() end
            end
            local chSwatch, chUpdateSwatch = CludesUI.BuildColorSwatch(leftRgn, leftRgn:GetFrameLevel() + 5, chSwGet, chSwSet, true, 20)
            PP.Point(chSwatch, "RIGHT", leftRgn._lastInline or leftRgn._control, "LEFT", -8, 0)
            leftRgn._lastInline = chSwatch

            local chSwBlock = CreateFrame("Frame", nil, chSwatch)
            chSwBlock:SetAllPoints()
            chSwBlock:SetFrameLevel(chSwatch:GetFrameLevel() + 10)
            chSwBlock:EnableMouse(true)
            chSwBlock:SetScript("OnEnter", function()
                CludesUI.ShowWidgetTooltip(chSwatch, CludesUI.DisabledTooltip("Character Crosshair"))
            end)
            chSwBlock:SetScript("OnLeave", function() CludesUI.HideWidgetTooltip() end)

            CludesUI.RegisterWidgetRefresh(function()
                local off = crosshairOff()
                if off then
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
            if chInitOff then chSwBlock:Show() else chSwBlock:Hide() end
        end

        -- Color Out of Range (toggle + inline color picker)
        local meleeRow
        meleeRow, h = W:DualRow(parent, y,
            { type="toggle", text="Color Out of Range",
              tooltip=function()
                  local s = CludesUI.L("Changes the crosshair color when your current target is out of range.")
                  if CludesUI._getCrosshairCutoffRange then
                      local range = CludesUI._getCrosshairCutoffRange()
                      s = s .. " " .. CludesUI.Lf("Currently active range cutoff: %1$syd.", range)
                  end
                  return s
              end,
              disabled=function() return crosshairOff() end,
              disabledTooltip="Enable the crosshair to use this option.", rawTooltip=true,
              getValue=function() return cget("crosshairMeleeColorEnabled") == true end,
              setValue=function(v)
                cset("crosshairMeleeColorEnabled", v)
                if CludesUI._applyCrosshair then CludesUI._applyCrosshair() end
                CludesUI:RefreshPage()
              end },
            { type="label", text="" }
        );  y = y - h
        -- Inline color swatch (disabled when toggle is off or crosshair is None)
        if not CludesUI._prebuilding then
            local leftRgn = meleeRow._leftRegion
            local function meleeOff()
                return crosshairOff() or cget("crosshairMeleeColorEnabled") ~= true
            end
            local mcGet = function()
                local c = cget("crosshairMeleeColor")
                if c then return c.r, c.g, c.b, c.a end
                return 1, 0, 0, 1
            end
            local mcSet = function(r, g, b, a)
                cset("crosshairMeleeColor", { r = r, g = g, b = b, a = a or 1 })
                if CludesUI._applyCrosshair then CludesUI._applyCrosshair() end
            end
            local mcSwatch, mcUpdate = CludesUI.BuildColorSwatch(leftRgn, leftRgn:GetFrameLevel() + 5, mcGet, mcSet, true, 20)
            PP.Point(mcSwatch, "RIGHT", leftRgn._control, "LEFT", -12, 0)
            leftRgn._lastInline = mcSwatch

            local mcBlock = CreateFrame("Frame", nil, mcSwatch)
            mcBlock:SetAllPoints()
            mcBlock:SetFrameLevel(mcSwatch:GetFrameLevel() + 10)
            mcBlock:EnableMouse(true)
            mcBlock:SetScript("OnEnter", function()
                CludesUI.ShowWidgetTooltip(mcSwatch, CludesUI.DisabledTooltip("Color Out of Range"))
            end)
            mcBlock:SetScript("OnLeave", function() CludesUI.HideWidgetTooltip() end)
            CludesUI.RegisterWidgetRefresh(function()
                local off = meleeOff()
                mcSwatch:SetAlpha(off and 0.3 or 1)
                if off then mcBlock:Show() else mcBlock:Hide() end
                mcUpdate()
            end)
            local mcInitOff = meleeOff()
            mcSwatch:SetAlpha(mcInitOff and 0.3 or 1)
            if mcInitOff then mcBlock:Show() else mcBlock:Hide() end
        end

        _, h = W:Spacer(parent, y, 20);  y = y - h

        y = BuildSelfCombatTextSection(parent, y)
        _, h = W:Spacer(parent, y, 20);  y = y - h

        ---------------------------------------------------------------------------
        --  GROUP FINDER (INSTANCES on WoW Forever)
        ---------------------------------------------------------------------------
        _, h = W:SectionHeader(parent, CludesUI.IS_FOREVER and "INSTANCES" or "GROUP FINDER", y);  y = y - h

        -- Auto Insert Keystone | Announce Instance Reset, then Quick Signup |
        -- Persistent Signup Note, which Group Finder's settings page mirrors (the
        -- same account-wide switches). WoW Forever has no keystones and no premade
        -- group list, so only Announce Instance Reset is built there.
        local autoKeyCfg = { type="toggle", text="Auto Insert Keystone",
              tooltip="Automatically inserts your key into the Font of Power.",
              getValue=function()
                  if not CludesUIDB then return true end
                  return CludesUIDB.autoInsertKeystone ~= false
              end,
              setValue=function(v)
                  if not CludesUIDB then CludesUIDB = {} end
                  CludesUIDB.autoInsertKeystone = v
              end }
        local announceCfg = { type="toggle", text="Announce Instance Reset",
              tooltip="After a successful instance reset, automatically announces it in party or raid chat so your group knows they can re-enter.",
              getValue=function()
                  return CludesUIDB and CludesUIDB.instanceResetAnnounce or false
              end,
              setValue=function(v)
                  if not CludesUIDB then CludesUIDB = {} end
                  CludesUIDB.instanceResetAnnounce = v
                  if CludesUI._applyInstanceResetAnnounce then
                      CludesUI._applyInstanceResetAnnounce()
                  end
              end }
        local quickCfg = { type="toggle", text="Quick Signup",
              tooltip="Double-click a group listing to instantly sign up without pressing the Sign Up button. Hold Shift to keep the dialog open, e.g. to type a signup note.",
              getValue=function()
                  return CludesUIDB and CludesUIDB.quickSignup or false
              end,
              setValue=function(v)
                  if not CludesUIDB then CludesUIDB = {} end
                  CludesUIDB.quickSignup = v
                  CludesUI._applyQuickSignup()
              end }
        local persistCfg = { type="toggle", text="Persistent Signup Note",
              tooltip="Keeps a saved signup note you can copy into the Sign Up dialog with the Copy button.",
              getValue=function()
                  return CludesUIDB and CludesUIDB.persistSignupNote or false
              end,
              setValue=function(v)
                  if not CludesUIDB then CludesUIDB = {} end
                  CludesUIDB.persistSignupNote = v
                  CludesUI._applyPersistSignupNote()
                  CludesUI:RefreshPage()
              end }
        local noteRow
        if CludesUI.IS_FOREVER then
            _, h = W:DualRow(parent, y, announceCfg, CludesUI.BlankRowCfg());  y = y - h
        else
            _, h = W:DualRow(parent, y, autoKeyCfg, announceCfg);  y = y - h
            noteRow, h = W:DualRow(parent, y, quickCfg, persistCfg);  y = y - h
        end

        if noteRow and not CludesUI._prebuilding then
            local rightRgn = noteRow._rightRegion
            local function persistOff()
                return not (CludesUIDB and CludesUIDB.persistSignupNote)
            end

            CludesUI.BuildInlineCog(rightRgn, {
                gap = 9, tip = "Edit the saved signup note.",
                disabled = persistOff, disabledTooltip = "Persistent Signup Note",
                show = function()
                    CludesUI:ShowInputPopup({
                        title="Signup Note",
                        message="Saved between reloads and relogs. In Group Finder, choose Copy, press Ctrl+C, then Ctrl+V.",
                        placeholder="Enter signup note...",
                        initialText=CludesUI.GetPersistentSignupNote(),
                        maxLetters=63,
                        inputHeight=70,
                        multiline=true,
                        showCount=true,
                        allowEmpty=true,
                        confirmText="Save",
                        onConfirm=function(note)
                            CludesUI.SetPersistentSignupNote(note or "")
                        end,
                    })
                end,
            })
        end

        _, h = W:Spacer(parent, y, 20);  y = y - h

        ---------------------------------------------------------------------------
        --  UI
        ---------------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "UI", y);  y = y - h

        _, h = W:DualRow(parent, y,
            { type="toggle", text="Hide Screenshot Status",
              tooltip="Hides the 'Screenshot saved' notification that appears on screen after taking a screenshot.",
              getValue=function()
                  if not CludesUIDB then return true end
                  return CludesUIDB.hideScreenshotStatus ~= false
              end,
              setValue=function(v)
                  if not CludesUIDB then CludesUIDB = {} end
                  CludesUIDB.hideScreenshotStatus = v
                  if CludesUI._applyScreenshotStatus then
                      CludesUI._applyScreenshotStatus()
                  end
              end },
            { type="toggle", text="Train All Button",
              tooltip="Adds a 'Train All' button next to the Train button at profession trainers, allowing you to learn all available skills with one click.",
              getValue=function()
                  return CludesUIDB and CludesUIDB.trainAllButton or false
              end,
              setValue=function(v)
                  if not CludesUIDB then CludesUIDB = {} end
                  CludesUIDB.trainAllButton = v
                  if CludesUI._applyTrainAllButton then
                      CludesUI._applyTrainAllButton()
                  end
              end }
        );  y = y - h

        -- Auto Unwrap Collections | Auto Open Containers
        local autoOpenContainerRow
        autoOpenContainerRow, h = W:DualRow(parent, y,
            { type="toggle", text="Auto Unwrap Collections",
              tooltip="Automatically dismisses the 'new mount/pet/toy' fanfare notification when you receive one, so you don't have to click through the collections journal.",
              getValue=function()
                  return CludesUIDB and CludesUIDB.autoUnwrapCollections or false
              end,
              setValue=function(v)
                  if not CludesUIDB then CludesUIDB = {} end
                  CludesUIDB.autoUnwrapCollections = v
                  if CludesUI._applyAutoUnwrap then
                      CludesUI._applyAutoUnwrap()
                  end
              end },
            { type="toggle", text="Auto Open Containers",
              tooltip="Automatically opens bags, boxes and parcels in your inventory when they are added to your bags.\n\nContainers received from the mailbox are held until you close the mailbox, so opening them cannot collide with mail still delivering items.",
              getValue=function()
                  if not CludesUIDB then return false end
                  return CludesUIDB.autoOpenContainers == true
              end,
              setValue=function(v)
                  if not CludesUIDB then CludesUIDB = {} end
                  CludesUIDB.autoOpenContainers = v
                  if CludesUI._applyAutoOpenContainers then
                      CludesUI._applyAutoOpenContainers()
                  end
                  CludesUI:RefreshPage()
              end }
        );  y = y - h

        -- Cog on Auto Open Containers (right region)
        if not CludesUI._prebuilding then
            local rightRgn = autoOpenContainerRow._rightRegion
            local function autoOpenContainerOff()
                return not (CludesUIDB and CludesUIDB.autoOpenContainers == true)
            end

            CludesUI.BuildInlineCog(rightRgn, {
                title = "Auto Open Containers Settings",
                rows = {
                    { type="toggle", label="Exclude Warbound Containers",
                      get=function()
                          if not CludesUIDB then return true end
                          return CludesUIDB.autoOpenContainersExcludeWarbound ~= false
                      end,
                      set=function(v)
                          if not CludesUIDB then CludesUIDB = {} end
                          CludesUIDB.autoOpenContainersExcludeWarbound = v
                      end },
                    { type="toggle", label="Hold Capped Artisan Payouts",
                      tooltip="Keeps Artisan's Consortium Payouts closed while Shard of Dundun is at its maximum, then resumes automatic opening after you spend shards.",
                      get=function()
                          return CludesUIDB
                              and CludesUIDB.autoOpenContainersHoldCappedArtisanPayouts == true
                      end,
                      set=function(v)
                          if not CludesUIDB then CludesUIDB = {} end
                          CludesUIDB.autoOpenContainersHoldCappedArtisanPayouts = v
                          if CludesUI._applyAutoOpenContainers then
                              CludesUI._applyAutoOpenContainers()
                          end
                      end },
                },
                gap = 9, disabled = autoOpenContainerOff, disabledTooltip = "Auto Open Containers",
            })
        end

        -- Bonus Roll Confirmation. Not offered on WoW Forever: no bonus rolls
        -- there, so the row is not built and the runtime block does not exist.
        if not CludesUI.IS_FOREVER then
        local bonusRollRow
        local function bonusRollConflict()
            return C_AddOns.IsAddOnLoaded("BonusRollConfirm")
        end
        bonusRollRow, h = W:DualRow(parent, y,
            { type="toggle", text=CludesUI.L("Bonus Roll Confirmation"),
              tooltip=CludesUI.L("Asks before spending a bonus roll and shows your loot specialization. Use the cog to also confirm Pass."),
              disabled=bonusRollConflict,
              disabledTooltip=CludesUI.L("BonusRollConfirm is loaded and handles confirmation. Disable that addon and reload to use this feature."),
              rawTooltip=true,
              getValue=function()
                  return CludesUIDB and CludesUIDB.bonusRollConfirmation == true
              end,
              setValue=function(v)
                  if not CludesUIDB then CludesUIDB = {} end
                  CludesUIDB.bonusRollConfirmation = v
                  if CludesUI._applyBonusRollConfirmation then CludesUI._applyBonusRollConfirmation() end
                  CludesUI:RefreshPage()
              end },
            CludesUI.BlankRowCfg()
        );  y = y - h
        if not CludesUI._prebuilding then
            CludesUI.BuildInlineCog(bonusRollRow._leftRegion, {
                title = CludesUI.L("Bonus Roll Settings"),
                rows = {
                    { type="toggle", label=CludesUI.L("Only Confirm Roll"),
                      tooltip=CludesUI.L("Pass immediately without confirmation. Turn off to confirm both Roll and Pass."),
                      get=function()
                          return not CludesUIDB or CludesUIDB.bonusRollOnly ~= false
                      end,
                      set=function(v)
                          if not CludesUIDB then CludesUIDB = {} end
                          CludesUIDB.bonusRollOnly = v
                          if CludesUI._applyBonusRollConfirmation then CludesUI._applyBonusRollConfirmation() end
                      end },
                },
                gap = 9,
                disabled = function()
                    return bonusRollConflict() or not (CludesUIDB and CludesUIDB.bonusRollConfirmation)
                end,
                disabledTooltip = CludesUI.L("Bonus Roll Confirmation"),
            })
        end
        end -- not IS_FOREVER

        -- Keys, Logs & Brez sections live at the bottom of this page (the
        -- separate tab was retired to keep the tab bar at five pages).
        if _G._CUI_BuildAutoLoggingPage then
            _, h = W:Spacer(parent, y, 16);  y = y - h
            local alH = _G._CUI_BuildAutoLoggingPage(pageName, parent, y)
            if alH then y = y - alH end
        end

        return math.abs(y)
    end

    local pages = { PAGE_QOL, PAGE_RAIDTOOLS, PAGE_CURSOR, PAGE_SHIFTER, PAGE_MOVEMENT }
    -- No item upgrade system on WoW Forever: the Upgrader tab is not offered there
    -- (its resident file returns at load, so the page builder never exists either).
    if not CludesUI.IS_FOREVER then pages[#pages + 1] = PAGE_UPGCALC end
    local searchTerms = { "brez", "bres", "battle res", "combat res", "cursor", "macro", "fps", "logging", "combat log", "warcraft logs", "upgrade", "ilvl", "item level", "crest", "upgrade calculator", "upgrade tooltips", "tooltip", "shifter", "move", "drag", "position", "demodal", "drift", "combat alert", "enter combat", "leave combat", "in combat", "combat text", "combat notification", "transform", "transforms", "costume", "disguise", "chef's hat", "noggenfogger", "target distance", "distance to target", "range text", "yard", "yards", "movement", "mobility", "gap closer", "blink", "gateway", "warlock gateway", "control shard", "time spiral", "free movement", "raid tools", "raid", "pull timer", "pull", "ready check", "role check", "raid marker", "target marker", "world marker", "flare", "disband", "convert to raid", "countdown" }
    -- Terms for features WoW Forever does not have (the Battle Res indicator,
    -- the Macro Factory) are dropped there, so a sidebar search for them does
    -- not list this module; retail keeps the full list.
    if CludesUI.IS_FOREVER then
        local foreverDrop = { ["brez"] = true, ["bres"] = true, ["battle res"] = true, ["combat res"] = true,
            ["macro"] = true }
        for i = #searchTerms, 1, -1 do
            if foreverDrop[searchTerms[i]] then table.remove(searchTerms, i) end
        end
    end
    CludesUI:RegisterModule("CludesUIQoL", {
        title       = "Utilities",
        description = "Quality of life features and custom cursor.",
        pages       = pages,
        searchTerms = searchTerms,
        buildPage   = function(pageName, parent, yOffset)
            -- The Raid Tools settings preview ends when any OTHER QoL page
            -- builds (the CDM tracking-bars placeholder arrangement); window
            -- close and module switches are handled in the Raid Tools options
            -- file. Global Search's hidden pre-build never touches it.
            if pageName ~= PAGE_RAIDTOOLS and not CludesUI._prebuilding
               and _G._CUI_RaidTools_Preview then
                _G._CUI_RaidTools_Preview(false)
            end
            if pageName == PAGE_QOL then
                return BuildQoLPage(pageName, parent, yOffset)
            end
            if pageName == PAGE_CURSOR and _G._EBS_BuildCursorPage then
                return _G._EBS_BuildCursorPage(pageName, parent, yOffset)
            end
            if pageName == PAGE_UPGCALC and _G._CUI_BuildUpgradeCalcPage then
                return _G._CUI_BuildUpgradeCalcPage(pageName, parent, yOffset)
            end
            if pageName == PAGE_SHIFTER and _G._CUI_BuildShifterPage then
                return _G._CUI_BuildShifterPage(pageName, parent, yOffset)
            end
            if pageName == PAGE_MOVEMENT and _G._CUI_BuildMovementAlertPage then
                return _G._CUI_BuildMovementAlertPage(pageName, parent, yOffset)
            end
            if pageName == PAGE_RAIDTOOLS and _G._CUI_BuildRaidToolsPage then
                return _G._CUI_BuildRaidToolsPage(pageName, parent, yOffset)
            end
        end,
        -- Cached pages are restored WITHOUT a rebuild, so buildPage never runs
        -- on the warm path -- reopening the window onto Raid Tools would leave
        -- its settings preview off without this (the CDM tracking-bars
        -- arrangement: mirror the flag on BOTH paths).
        onPageCacheRestore = function(pageName)
            if CludesUI._prebuilding then return end
            if _G._CUI_RaidTools_Preview then
                _G._CUI_RaidTools_Preview(pageName == PAGE_RAIDTOOLS)
            end
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
                if CludesUI._applyHideTutorials then CludesUI._applyHideTutorials() end
                CludesUIDB.hideLootHistory = false
                CludesUIDB.lootHistoryMode = nil
                CludesUIDB.lootHistoryDelay = nil
                if CludesUI._applyHideLootHistory then CludesUI._applyHideLootHistory() end
                -- Talking Head does not exist on WoW Forever.
                if CludesUI._applyHideTalkingHead then CludesUI._applyHideTalkingHead() end
                CludesUIDB.hideBanners = false
                CludesUIDB.hideAlertToasts = false
                CludesUIDB.hideAlertToastsLoot = nil
                CludesUIDB.hideAlertToastsAchievements = nil
                CludesUIDB.hideAlertToastsHousing = nil
                CludesUIDB.announceGroupDeaths = false
                CludesUIDB.groupDeathTextSize = nil
                CludesUIDB.groupDeathAlertPos = nil
                CludesUIDB.groupDeathSound = nil      -- legacy boolean (pre-dropdown)
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
            if _G._EBS_ResetCursor then _G._EBS_ResetCursor() end
            -- Battle Res and Bloodlust do not exist on WoW Forever.
            if _G._CUI_BattleRes_Reset then _G._CUI_BattleRes_Reset() end
            CludesUI._applyHideBlizzardPartyFrame()
            if CludesUI._applyBonusRollConfirmation then CludesUI._applyBonusRollConfirmation() end
            if CludesUI._applyHideErrorMessages then CludesUI._applyHideErrorMessages() end
            if CludesUI._applyAnnounceGroupDeaths then CludesUI._applyAnnounceGroupDeaths() end
            if CludesUI._applyCombatAlert then CludesUI._applyCombatAlert() end
            if CludesUI._applyPotionAlert then CludesUI._applyPotionAlert() end
            if CludesUI._applyTalentAlert then CludesUI._applyTalentAlert() end
            if CludesUI._applyTargetDistance then CludesUI._applyTargetDistance() end
            if CludesUI._applyHideTransforms then CludesUI._applyHideTransforms() end
            if CludesUI._applyQuickSignup then CludesUI._applyQuickSignup() end
            if CludesUI._applyPersistSignupNote then CludesUI._applyPersistSignupNote() end
            if CludesUI._applyQuickLoot then CludesUI._applyQuickLoot() end
            if CludesUI._applyAutoGossip then CludesUI._applyAutoGossip() end
            if CludesUI._applyInstanceResetAnnounce then CludesUI._applyInstanceResetAnnounce() end
            if CludesUI._applyAutoOpenContainers then CludesUI._applyAutoOpenContainers() end
            if CludesUI._ShutdownShifter then CludesUI._ShutdownShifter() end
            if _G._CUI_AutoLogging_Check then _G._CUI_AutoLogging_Check() end
            CludesUI._ModuleNS["CludesUIQoL"].SCT_Reset()
            CludesUI:InvalidatePageCache()
        end,
        -- Tears down Duration Warning, Raid Tools, and Movement Alert
        -- previews on module switch (Movement Alert also stops its ticker).
        onModuleLeave = function()
            if CludesUI._durWarnHidePreview then CludesUI._durWarnHidePreview() end
            if _G._CUI_RaidTools_Preview then _G._CUI_RaidTools_Preview(false) end
            if CludesUI._MovementAlertPreview then CludesUI._MovementAlertPreview(false) end
        end,
    })

    SLASH_EQOL1 = "/qol"
    SlashCmdList.EQOL = function()
        if InCombatLockdown and InCombatLockdown() then return end
        CludesUI:ShowModule("CludesUIQoL")
    end
end)
-- LoadOnDemand: this addon loads after PLAYER_LOGIN, so the event above will never fire; run the init now.
if IsLoggedIn() then initFrame:GetScript("OnEvent")(initFrame) end
