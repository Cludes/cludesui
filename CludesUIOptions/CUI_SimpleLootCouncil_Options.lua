if CUI_CLIENT_BLOCKED then
    return
end

local ADDON_NAME = "CludesUISimpleLootCouncil"
local MODULE_DESC = "Loot council voting for your raid, synced over addon messages."
local mod = CludesUI._ModuleNS[ADDON_NAME]
if not mod then
    return
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    local CreateFrame = CludesUI._Pool.CreateFrame

    if mod.slcInert then
        local PAGE_INERT = "General"
        CludesUI:RegisterModule(ADDON_NAME, {
            title = "Simple Loot Council",
            description = MODULE_DESC,
            pages = { PAGE_INERT },
            buildPage = function(pageName, hostFrame, yOffset)
                if pageName ~= PAGE_INERT then
                    return
                end
                local W, Pix, PAD = CludesUI.Widgets, CludesUI.PanelPP, CludesUI.CONTENT_PAD
                local posY, _, hgt = yOffset
                CludesUI:ClearContentHeader()
                if not CludesUI.IsSearchPrebuild() then
                    hostFrame._showRowDivider = true
                end
                _, hgt = W:SectionHeader(hostFrame, CludesUI.L("OLDER STANDALONE ADDON"), posY)
                posY = posY - hgt
                local rowFrame = CreateFrame("Frame", nil, hostFrame)
                rowFrame._skipRowDivider = true
                local labelText = CludesUI.MakeFont(rowFrame, 12, nil, 1, 1, 1)
                labelText:SetAlpha(0.85)
                labelText:SetJustifyH("LEFT")
                labelText:SetWordWrap(true)
                labelText:SetWidth(hostFrame:GetWidth() - PAD * 2 - 40)
                labelText:SetPoint("TOPLEFT", rowFrame, "TOPLEFT", 20, -10)
                labelText:SetText(
                    CludesUI.L(
                        "An older SimpleLootCouncil addon is enabled, so the Simple Loot Council module is off until that addon is disabled or updated."
                    )
                )
                Pix.Size(rowFrame, hostFrame:GetWidth() - PAD * 2, 54)
                Pix.Point(rowFrame, "TOPLEFT", hostFrame, "TOPLEFT", PAD, posY)
                posY = posY - 54
                _, hgt = W:DualRow(hostFrame, posY, {
                    type = "button",
                    text = CludesUI.L("Disable and Reload"),
                    noCapture = true,
                    onClick = function()
                        CludesUI.RequestReload(nil, nil, mod.DisableStandalone)
                    end,
                }, CludesUI.BlankRowCfg())
                posY = posY - hgt
                return math.abs(posY)
            end,
        })
        return
    end

    local PAGE_LOOT, PAGE_COUNCIL, PAGE_DATA = "Loot and Sessions", "Loot Council", "Data and Diagnostics"
    local PAGES = { PAGE_LOOT, PAGE_COUNCIL, PAGE_DATA }
    local PAGE_SECTIONS = {
        [PAGE_LOOT] = { "lootHandling", "master", "session", "alts" },
        [PAGE_COUNCIL] = { "council", "voting", "responses" },
        [PAGE_DATA] = { "history", "diagnostics" },
    }
    local SUGGEST_MAX, SUGGEST_MIN_CHARS = 8, 2

    local function SLC()
        local slc = _G.SimpleLootCouncil
        if slc and slc.db and slc.UI and slc.UI.OptionsSchema then
            return slc
        end
    end

    local function PageShown()
        return CludesUI:IsShown() and CludesUI:GetActiveModule() == ADDON_NAME
    end

    local function Invalidate()
        local slc = SLC()
        if slc then
            slc.Callbacks:Invalidate("options")
        end
    end

    local rebuildQueued, focusResponse
    local function RequestRebuild()
        if rebuildQueued then
            return
        end
        rebuildQueued = true
        C_Timer.After(0, function()
            rebuildQueued = false
            if PageShown() then
                CludesUI:RefreshPage(true)
            end
        end)
    end

    local councilEntries, councilDirty = nil, true
    local councilEvents = {}
    local function CouncilEntries(specInfo)
        if councilDirty or not councilEntries then
            councilEntries, councilDirty = specInfo.entries(), false
        end
        return councilEntries
    end

    local subscribed
    local gameEvents = {}
    local function Heard(evt)
        if councilEvents[evt] then
            councilDirty = true
        end
        Invalidate()
    end
    local watcher = _G.CreateFrame("Frame")
    watcher:SetScript("OnEvent", function(_, evt)
        Heard(evt)
    end)
    local function Subscribe(slc, Schema)
        if subscribed then
            return
        end
        subscribed = true
        for _, evt in ipairs(Schema.Row("council").refreshOn) do
            councilEvents[evt] = true
        end
        for _, evt in ipairs(Schema.Events()) do
            if evt:find("^%u[%u_]*$") then
                gameEvents[#gameEvents + 1] = evt
            elseif evt == "SessionChanged" then
                slc.Callbacks:Register(evt, function(_, kindOf)
                    if kindOf == nil or Schema.SESSION_KINDS[kindOf] then
                        Invalidate()
                    end
                end)
            else
                slc.Callbacks:Register(evt, function()
                    Heard(evt)
                end)
            end
        end
    end
    local function Listen(enabled)
        for _, evt in ipairs(gameEvents) do
            if enabled then
                watcher:RegisterEvent(evt)
            else
                watcher:UnregisterEvent(evt)
            end
        end
    end

    local function Cfg(rowFrame)
        local conf = {
            type = rowFrame.type,
            text = rowFrame.text,
            tooltip = rowFrame.tooltip,
            values = rowFrame.values,
            order = rowFrame.order,
            inputWidth = rowFrame.inputWidth,
            min = rowFrame.min,
            max = rowFrame.max,
            step = rowFrame.step,
            valueSnap = rowFrame.valueSnap,

            noCapture = true,
        }
        local locked, disabled = rowFrame.locked, rowFrame.disabled
        local function LockReason()
            if not locked then
                return nil
            end
            local _, reason = locked()
            return reason
        end
        conf.getValue = function()
            if LockReason() then
                return (locked())
            end
            return rowFrame.getValue()
        end
        conf.setValue = function(value)
            if not LockReason() then
                rowFrame.setValue(value)
            end
            Invalidate()
        end

        if disabled then
            conf.disabled = function()
                return disabled() ~= nil
            end
            conf.disabledTooltip = disabled

            conf.rawTooltip = true
        end
        return conf
    end

    local CHECKS_W = 230
    local function ChecksReason(rowFrame)
        if rowFrame.disabled then
            return rowFrame.disabled()
        end
        return nil
    end
    local function ChecksLock(targetUnit, rowFrame)
        if not rowFrame.disabled then
            return targetUnit
        end
        targetUnit.disabled = function()
            return ChecksReason(rowFrame) ~= nil
        end
        targetUnit.disabledTooltip = function()
            return ChecksReason(rowFrame)
        end
        targetUnit.rawTooltip = true
        return targetUnit
    end

    local function RowLabel(rowFrame)
        if rowFrame.id == "councilQueue" then
            if rowFrame.cuiText then
                return CludesUI.L(rowFrame.cuiText)
            end
            return CludesUI.L("Council can manage queue")
        end
        return rowFrame.text
    end
    local function ChecksCfg(rowFrame)
        return ChecksLock({
            type = "dropdown",
            text = RowLabel(rowFrame),
            tooltip = rowFrame.tooltip,
            noCapture = true,
            values = { __placeholder = "..." },
            order = { "__placeholder" },
            getValue = function()
                return "__placeholder"
            end,
            setValue = function() end,
        }, rowFrame)
    end

    local function MultiselectTips()
        return {
            soundNotifications = {
                responseFrame = CludesUI.L("Add a sound notification when the loot response frame opens"),
                responseTab = CludesUI.L("Add a sound notification when the loot response tab label pulses"),
            },
        }
    end
    local function ChecksItems(rowFrame)
        if rowFrame.type ~= "multiselect" then
            return rowFrame.items
        end
        local tips = MultiselectTips()[rowFrame.id]
        local itemList = {}
        for idx, itemInfo in ipairs(rowFrame.items) do
            local tipText = itemInfo.tooltip or (tips and tips[itemInfo.key])
            itemList[idx] = { key = itemInfo.key, label = itemInfo.text, tooltip = tipText }
        end
        return itemList
    end

    local CHECKS_PAD = 80
    local measure
    local function ChecksWidth(itemList)
        if not measure then
            measure = UIParent:CreateFontString(nil, "OVERLAY")
            measure:SetFont(CludesUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF", 13, "")
            measure:Hide()
        end
        local widest = 0
        for _, itemInfo in ipairs(itemList) do
            measure:SetText(itemInfo.label or "")
            widest = math.max(widest, math.ceil(measure:GetStringWidth() or 0))
        end
        return widest + CHECKS_PAD
    end
    local function ChecksDecorator(rowFrame)
        local itemList = ChecksItems(rowFrame)
        local function Get(key)
            if rowFrame.lockedValue and rowFrame.locked and select(2, rowFrame.locked()) then
                return rowFrame.lockedValue(key)
            end
            return rowFrame.getValue(key)
        end
        return function(regionFrame)
            local width = regionFrame._control and regionFrame._control:GetWidth() or 0
            if width < 50 then
                width = CHECKS_W
            end
            if rowFrame.id == "councilQueue" then
                width = ChecksWidth(itemList)
            else
                width = math.max(width, ChecksWidth(itemList))
            end
            if regionFrame._control then
                regionFrame._control:Hide()
            end
            local dropdown, refresh = CludesUI.BuildVisOptsCBDropdown(
                regionFrame,
                width,
                regionFrame:GetFrameLevel() + 2,
                itemList,
                Get,
                function(key, value)
                    if
                        not ChecksReason(rowFrame)
                        and not (rowFrame.locked and select(2, rowFrame.locked()))
                        and (value or not rowFrame.exclusive)
                    then
                        rowFrame.setValue(key, value)
                    end
                    Invalidate()
                end,
                nil,
                nil,
                nil,
                nil,
                nil,
                ChecksLock({ emptyLabel = "None", noAllLabel = rowFrame.exclusive }, rowFrame)
            )
            CludesUI.PanelPP.Point(dropdown, "RIGHT", regionFrame, "RIGHT", -20, 0)
            regionFrame._control = dropdown
            regionFrame._lastInline = nil
            CludesUI.RegisterWidgetRefresh(refresh)
        end
    end

    local function StyledTag(hostFrame, width, onClick, make)
        local btn = (make or CreateFrame)("Button", nil, hostFrame)
        CludesUI.PanelPP.Size(btn, width, 24)
        btn:SetFrameLevel(hostFrame:GetFrameLevel() + 5)
        local _, border, labelText = CludesUI.MakeStyledButton(btn, "", 11, CludesUI.WB_COLOURS)

        local function Edge()
            local c = btn.tone
            if c then
                border:SetColor(c[1], c[2], c[3], 1)
            end
        end
        function btn:SetTone(c)
            btn.tone = c
            Edge()
        end
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        btn:SetScript("OnClick", function(_, btnFrame)
            CludesUI.HideWidgetTooltip()
            onClick(btnFrame)
        end)
        local hoverOn, hoverOff = btn:GetScript("OnEnter"), btn:GetScript("OnLeave")
        btn:SetScript("OnEnter", function(b)
            hoverOn(b)
            Edge()
            if b.tip then
                CludesUI.ShowWidgetTooltip(b, b.tip)
            end
        end)
        btn:SetScript("OnLeave", function(b)
            hoverOff(b)
            Edge()
            CludesUI.HideWidgetTooltip()
        end)
        btn.Label = labelText
        return btn
    end

    local SUG_ROW_H = 26
    local sugPopup
    local function SugPaint(p)
        for idx, rowFrame in ipairs(p.rows) do
            rowFrame.hl:SetColorTexture(1, 1, 1, idx == p.selected and 0.08 or 0)
        end
    end
    local function SugPopup()
        if sugPopup then
            return sugPopup
        end
        local p = _G.CreateFrame("Frame", nil, _G.UIParent)
        p:SetFrameStrata("FULLSCREEN_DIALOG")
        p:SetFrameLevel(220)
        p:SetClampedToScreen(true)
        p:EnableMouse(true)
        p:Hide()
        local backdrop = p:CreateTexture(nil, "BACKGROUND")
        backdrop:SetAllPoints()
        backdrop:SetColorTexture(0.098, 0.090, 0.082, 0.97)
        p._brd = CludesUI.MakeRoundedBorder(p, 1, 1, 1, 0.12, backdrop)
        p.rows, p.selected = {}, 0

        local away = _G.CreateFrame("Frame")
        away:SetScript("OnEvent", function()
            local ownerFrame = p.owner
            if not p:IsMouseOver() and not (ownerFrame and ownerFrame:IsMouseOver()) then
                p:Hide()
            end
        end)
        p:SetScript("OnShow", function()
            away:RegisterEvent("GLOBAL_MOUSE_DOWN")
        end)
        p:SetScript("OnHide", function()
            away:UnregisterEvent("GLOBAL_MOUSE_DOWN")
        end)
        sugPopup = p
        return p
    end
    local function SugRow(p, idx)
        local rowFrame = p.rows[idx]
        if rowFrame then
            return rowFrame
        end
        rowFrame = _G.CreateFrame("Button", nil, p)
        rowFrame:SetHeight(SUG_ROW_H)
        rowFrame:SetPoint("TOPLEFT", p, "TOPLEFT", 4, -4 - (idx - 1) * SUG_ROW_H)
        rowFrame:SetPoint("TOPRIGHT", p, "TOPRIGHT", -4, -4 - (idx - 1) * SUG_ROW_H)
        rowFrame.hl = rowFrame:CreateTexture(nil, "ARTWORK")
        rowFrame.hl:SetAllPoints()
        rowFrame.hl:SetColorTexture(1, 1, 1, 0)
        rowFrame.label = CludesUI.MakeFont(rowFrame, 12, nil, 1, 1, 1)
        rowFrame.label:SetPoint("LEFT", rowFrame, "LEFT", 8, 0)
        rowFrame.label:SetPoint("RIGHT", rowFrame, "RIGHT", -8, 0)
        rowFrame.label:SetJustifyH("LEFT")
        rowFrame.label:SetWordWrap(false)
        rowFrame:SetScript("OnEnter", function()
            p.selected = idx
            SugPaint(p)
        end)
        rowFrame:SetScript("OnClick", function()
            if p.onPick and rowFrame.entry then
                p.onPick(rowFrame.entry)
            end
        end)
        p.rows[idx] = rowFrame
        return rowFrame
    end
    local function SugOpen()
        return sugPopup ~= nil and sugPopup:IsShown()
    end
    local function CloseSuggestions()
        if sugPopup then
            sugPopup:Hide()
            sugPopup.selected = 0
        end
    end

    local addHolder, addBox, addButton
    local addHandlers = {}
    local function AddBox(rowFrame, width, buttonText)
        if not addHolder then
            addHolder = _G.CreateFrame("Frame", nil, rowFrame)
            addBox = _G.CreateFrame("EditBox", nil, addHolder)
            addBox:SetHeight(28)
            addBox:SetAutoFocus(false)
            addBox:SetAltArrowKeyMode(false)
            CludesUI.ApplyModuleFont(addBox, CludesUI.EXPRESSWAY, 11, nil, "")
            addBox:SetTextColor(1, 1, 1, 0.9)
            addBox:SetJustifyH("LEFT")
            addBox:SetTextInsets(10, 10, 0, 0)
            local backdrop = addBox:CreateTexture(nil, "BACKGROUND")
            backdrop:SetAllPoints()
            backdrop:SetColorTexture(0, 0, 0, 0.5)
            CludesUI.MakeBorder(addBox, 1, 1, 1, 0.2)
            addButton = _G.CreateFrame("Button", nil, addHolder)
            CludesUI.PanelPP.Size(addButton, 90, 28)
            CludesUI.PanelPP.Point(addButton, "LEFT", addBox, "RIGHT", 8, 0)
            local function Add()
                if addHandlers.add then
                    addHandlers.add()
                end
            end
            CludesUI.MakeStyledButton(addButton, buttonText, 12, CludesUI.WB_COLOURS, Add)
            addBox:SetScript("OnEnterPressed", function()
                if addHandlers.enter then
                    addHandlers.enter()
                else
                    Add()
                end
            end)
            addBox:HookScript("OnArrowPressed", function(b, key)
                if addHandlers.arrow then
                    addHandlers.arrow(b, key)
                end
            end)
            addBox:SetScript("OnEscapePressed", function(b)
                CloseSuggestions()
                b:ClearFocus()
            end)
            addBox:SetScript("OnHide", CloseSuggestions)
            addBox:SetScript("OnTextChanged", function(b, userInput)
                if addHandlers.typed then
                    addHandlers.typed(b, userInput)
                end
            end)
        end
        addHolder:SetParent(rowFrame)
        addHolder:ClearAllPoints()
        addHolder:SetAllPoints(rowFrame)
        addHolder:SetFrameLevel(rowFrame:GetFrameLevel() + 1)
        addButton:SetFrameLevel(addHolder:GetFrameLevel() + 2)
        addBox.slcSuggest = function()
            return sugPopup
        end
        addBox:SetWidth(width)
        addBox:ClearAllPoints()
        addBox:SetPoint("LEFT", addHolder, "LEFT", 20, 0)
        addHolder:Show()
        return addBox
    end

    local ART = "Interface\\AddOns\\" .. ADDON_NAME .. "\\art\\"
    local LOGO = { path = ART .. "logo", u = 396 / 512, w = 396 }
    local LOGO_PRIDE = { path = ART .. "logo-pride", u = 398 / 512, w = 398 }
    local LOGO_H, LOGO_V = 36, 36 / 64

    local LOGO_RULE_X = 51
    local MODULE_TITLE = "Simple Loot Council"

    local function FindTitle(widget, depth, translated)
        for _, regionFrame in ipairs({ widget:GetRegions() }) do
            local textValue = regionFrame.GetText and regionFrame:GetText()
            if
                (textValue == MODULE_TITLE or textValue == translated)
                and (select(2, regionFrame:GetFont()) or 0) >= 30
            then
                return regionFrame
            end
        end
        if depth == 0 then
            return nil
        end
        for _, childFrame in ipairs({ widget:GetChildren() }) do
            local found = FindTitle(childFrame, depth - 1, translated)
            if found then
                return found
            end
        end
    end

    local function FindText(widget, depth, textValue)
        for _, regionFrame in ipairs({ widget:GetRegions() }) do
            if regionFrame.GetText and regionFrame:GetText() == textValue then
                return regionFrame
            end
        end
        if depth == 0 then
            return nil
        end
        for _, childFrame in ipairs({ widget:GetChildren() }) do
            local found = FindText(childFrame, depth - 1, textValue)
            if found then
                return found
            end
        end
    end

    local bannerTitle, bannerTexture, bannerVersion, bannerDesc, bannerDescText, bannerDescAnchor
    local function AccentWord(slc, word)
        return slc.Style.Colorize(slc.Style.color.accent, word)
    end

    local TAG_H, TAG_PAD = 24, 9
    local function FitTag(tag)
        local width = tag.Label.GetStringWidth and tag.Label:GetStringWidth()
        if type(width) ~= "number" or (issecretvalue and issecretvalue(width)) then
            width = 0
        end
        CludesUI.PanelPP.Size(tag, math.ceil(width) + TAG_PAD * 2, TAG_H)
    end

    local STANDALONE_URL = "https://www.curseforge.com/wow/addons/simplelootcouncil"

    local linkMeasure
    local function WidenLinkPopup(url)
        local hostRegion = CludesUI.OverlayParent and CludesUI.OverlayParent() or UIParent
        for _, dialog in ipairs({ hostRegion:GetChildren() }) do
            local boxFrame = dialog._eb
            if boxFrame and dialog:IsShown() and boxFrame.GetText and boxFrame:GetText() == url then
                if not linkMeasure then
                    linkMeasure = UIParent:CreateFontString(nil, "OVERLAY")
                    linkMeasure:SetFontObject(GameFontHighlight)
                end
                linkMeasure:SetText(url)
                local width = linkMeasure:GetStringWidth()
                if type(width) ~= "number" or (issecretvalue and issecretvalue(width)) then
                    return
                end
                local boxW, popW = boxFrame:GetWidth(), dialog:GetWidth()
                boxFrame:SetWidth(math.max(boxW, math.ceil(width) + 24))
                dialog:SetWidth(math.max(popW, math.ceil(width) + 64))
                if not dialog._slcWidened then
                    dialog._slcWidened = true
                    dialog:HookScript("OnHide", function()
                        boxFrame:SetWidth(boxW)
                        dialog:SetWidth(popW)
                    end)
                end
                return
            end
        end
    end

    local function ApplyBanner(slc)
        local pride = slc and slc.Style.PrideActive() or false
        local logo = pride and LOGO_PRIDE or LOGO
        bannerTexture:SetTexture(logo.path)
        bannerTexture:SetTexCoord(0, logo.u, 0, LOGO_V)
        CludesUI.PanelPP.Size(bannerTexture, logo.w, LOGO_H)
    end

    local function OnOurPage()
        return not CludesUI.IsSearchPrebuild() and CludesUI:GetActiveModule() == ADDON_NAME
    end

    local function ShowBanner()
        if not OnOurPage() then
            return
        end
        local slc = SLC()
        local main = CludesUI._mainFrame
        if not (slc and main) then
            return
        end
        if not bannerTitle then
            bannerTitle = FindTitle(main, 6, CludesUI.L(MODULE_TITLE))
        end
        if not bannerTitle then
            return
        end
        if not bannerTexture then
            bannerTexture = bannerTitle:GetParent():CreateTexture(nil, "ARTWORK")
            bannerTexture:SetPoint("TOPLEFT", bannerTitle, "TOPLEFT", 0, 0)

            local slotIndex = {
                ApplyLogo = function()
                    ApplyBanner(SLC())
                end,
            }
            slc.Style.logoWindows[#slc.Style.logoWindows + 1] = slotIndex
        end

        if not bannerVersion then
            bannerVersion = bannerTitle:GetParent():CreateFontString(nil, "OVERLAY")
            bannerVersion:SetFontObject(slc.Style.fontBadge)
            bannerVersion:SetJustifyH("LEFT")
            bannerVersion:SetPoint("BOTTOMLEFT", bannerTexture, "BOTTOMRIGHT", 12, 4)
        end
        bannerVersion:SetText("v" .. tostring(slc.VERSION))

        if not bannerDesc then
            bannerDesc = FindText(main, 6, CludesUI.L(MODULE_DESC))
            bannerDescText = bannerDesc and bannerDesc:GetText()
            if bannerDesc and bannerDesc.GetPoint then
                local anchorPoint, rel, relPoint, posX, posY = bannerDesc:GetPoint(1)
                if anchorPoint then
                    bannerDescAnchor = { anchorPoint, rel, relPoint, posX or 0, posY or 0 }
                end
            end
        end
        if bannerDesc then
            local a = bannerDescAnchor
            if a then
                bannerDesc:ClearAllPoints()
                bannerDesc:SetPoint(a[1], a[2], a[3], a[4] + LOGO_RULE_X, a[5])
            end
            bannerDesc:SetText(CludesUI.L("Developed in partnership with ") .. AccentWord(slc, "Laxx"))
        end
        ApplyBanner(slc)
        bannerTexture:Show()
        bannerVersion:Show()
        bannerTitle:SetAlpha(0)
    end

    local function HideBanner()
        if bannerTexture then
            bannerTexture:Hide()
        end
        if bannerVersion then
            bannerVersion:Hide()
        end
        if bannerDesc and bannerDescText then
            bannerDesc:SetText(bannerDescText)
        end
        local a = bannerDescAnchor
        if bannerDesc and a then
            bannerDesc:ClearAllPoints()
            bannerDesc:SetPoint(a[1], a[2], a[3], a[4], a[5])
        end
        if bannerTitle then
            bannerTitle:SetAlpha(1)
        end
    end

    local function PageSections(Schema, pageName)
        local byId, list = {}, {}
        for _, section in ipairs(Schema.Sections()) do
            byId[section.id] = section
        end
        for _, ident in ipairs(PAGE_SECTIONS[pageName] or {}) do
            if byId[ident] then
                list[#list + 1] = byId[ident]
            end
        end
        return list
    end

    local ICONS = "Interface\\AddOns\\CludesUI\\media\\icons\\"
    local ICON_OPEN, ICON_HISTORY = ICONS .. "play.png", ICONS .. "undo.png"

    local RANK_ROW_H, RANK_VISIBLE = 36, 7

    local COUNCIL_CELL_W, COUNCIL_CELL_H, COUNCIL_MAX_LINES, COUNCIL_BOTTOM = 150, 22, 3, 18
    local ML_LABEL_Y, ML_NAME_Y, DIVIDER_Y, LIST_Y = 18, 36, 80, 106

    local function CouncilColumns(width)
        return math.max(2, math.min(6, math.floor((width - 80) / COUNCIL_CELL_W)))
    end
    local function CouncilLines(entries, cols)
        return math.max(1, math.min(COUNCIL_MAX_LINES, math.ceil(math.max(entries, 1) / cols)))
    end

    local function CouncilMembers(inForce, name, rank)
        local entries, count = inForce.entries(name, rank)
        local members = {}
        for _, entry in ipairs(entries) do
            if not entry.master then
                members[#members + 1] = entry
            end
        end
        return members, tonumber(count) or 0
    end

    local lockCovers, searching = {}, false
    local function PaintCover(entry)
        entry.cover:SetShown(not searching and entry.locked() and true or false)
    end
    hooksecurefunc(CludesUI, "ApplyInlineSearch", function(_, query)
        local nowTime = query ~= nil and query ~= ""
        if nowTime == searching then
            return
        end
        searching = nowTime
        for _, covers in pairs(lockCovers) do
            for _, entry in ipairs(covers) do
                PaintCover(entry)
            end
        end
    end)

    local function BuildSettingsPage(pageName, hostFrame, yOffset)
        local W = CludesUI.Widgets
        local Pix = CludesUI.PanelPP
        local PAD = CludesUI.CONTENT_PAD

        local prebuild = CludesUI.IsSearchPrebuild()
        local posY = yOffset
        local _, hgt

        CludesUI:ClearContentHeader()

        local slc = SLC()
        if not slc then
            return math.abs(posY)
        end

        if not prebuild then
            hostFrame._showRowDivider = true
        end
        councilDirty = true
        local Schema, Stl = slc.UI.OptionsSchema, slc.Style

        local T, Format = slc.Locale.Text, slc.Locale.Format
        local refreshes = {}
        local function OnRefresh(func)
            refreshes[#refreshes + 1] = func
        end

        local covers = {}
        if not prebuild then
            lockCovers[pageName] = covers
        end
        local function LockCover(topY, bottom, textValue, locked, onLock)
            local cover = CreateFrame("Frame", nil, hostFrame)
            cover._searchIgnore = true
            Pix.Size(cover, hostFrame:GetWidth() - PAD * 2, topY - bottom)
            Pix.Point(cover, "TOPLEFT", hostFrame, "TOPLEFT", PAD, topY)
            cover:SetFrameLevel(hostFrame:GetFrameLevel() + 30)
            cover:EnableMouse(true)
            cover:EnableMouseWheel(true)
            cover:SetScript("OnMouseWheel", function(_, delta)
                if CludesUI._ShiftWheelScale(delta) then
                    return
                end
                local page = CludesUI._scrollFrame
                local func = page and page:GetScript("OnMouseWheel")
                if func then
                    func(page, delta)
                end
            end)
            local shade = cover:CreateTexture(nil, "BACKGROUND")
            shade:SetAllPoints()
            shade:SetColorTexture(0.05, 0.05, 0.05, 0.8)
            local lockLabel = CludesUI.MakeFont(cover, 14, nil, 1, 1, 1)
            lockLabel:SetPoint("CENTER", cover, "CENTER", 0, 0)
            lockLabel:SetText(textValue)
            local entry = { cover = cover, locked = locked }
            covers[#covers + 1] = entry
            OnRefresh(function()
                if onLock and locked() then
                    onLock()
                end
                PaintCover(entry)
            end)
        end

        local colX, colW = 0, nil
        local function Width()
            return colW or (hostFrame:GetWidth() - PAD * 2)
        end

        local function Row(height)
            local rowFrame = CreateFrame("Frame", nil, hostFrame)
            Pix.Size(rowFrame, Width(), height)
            Pix.Point(rowFrame, "TOPLEFT", hostFrame, "TOPLEFT", PAD + colX, posY)
            rowFrame._skipRowDivider = true
            CludesUI.RowBg(rowFrame, hostFrame)
            posY = posY - height
            return rowFrame
        end

        local function Note(textValue, alpha)
            local rowFrame = CreateFrame("Frame", nil, hostFrame)
            rowFrame._skipRowDivider = true
            local labelText = CludesUI.MakeFont(rowFrame, 12, nil, 1, 1, 1)
            labelText:SetAlpha(alpha or 0.45)
            labelText:SetJustifyH("LEFT")
            labelText:SetWordWrap(true)
            labelText:SetWidth(Width() - 40)
            labelText:SetPoint("TOPLEFT", rowFrame, "TOPLEFT", 20, -10)
            labelText:SetText(textValue)
            local textH = labelText:GetStringHeight()
            if type(textH) ~= "number" or (issecretvalue and issecretvalue(textH)) then
                textH = 14
            end
            local height = math.max(34, math.ceil(textH) + 20)
            Pix.Size(rowFrame, Width(), height)
            Pix.Point(rowFrame, "TOPLEFT", hostFrame, "TOPLEFT", PAD + colX, posY)
            posY = posY - height
            return labelText
        end

        local function ClassText(classFile, textValue, fallback)
            local r, g, b = Stl.ClassColor(classFile)
            return Stl.Colorize(r and { r, g, b } or fallback or Stl.color.text, textValue)
        end
        local function PlayerText(fullName)
            local record = slc.Player:Get(fullName)
            return ClassText(record and record.classFile, Ambiguate(fullName, "short"))
        end
        local function RankText(rankName)
            return Stl.Colorize(Stl.color.accentPale, rankName)
        end
        local faint = Stl.ColorStart(Stl.Flatten(Stl.color.textFaint))

        local pending, lastRightId
        local function Place(conf, decorate, ident, dependsOn)
            if not pending then
                pending = { cfg = conf, decorate = decorate, id = ident, dependsOn = dependsOn }
                return
            end
            local widget
            widget, hgt = W:DualRow(hostFrame, posY, pending.cfg, conf)
            posY = posY - hgt
            if not prebuild then
                if pending.decorate then
                    pending.decorate(widget._leftRegion)
                end
                if decorate then
                    decorate(widget._rightRegion)
                end
            end
            pending, lastRightId = nil, ident
        end

        local function Flush()
            if not pending then
                return
            end
            local widget
            if pending.dependsOn and pending.dependsOn == lastRightId then
                widget, hgt = W:DualRow(hostFrame, posY, CludesUI.BlankRowCfg(), pending.cfg)
                posY = posY - hgt
                if not prebuild and pending.decorate then
                    pending.decorate(widget._rightRegion)
                end
            else
                widget, hgt = W:DualRow(hostFrame, posY, pending.cfg, CludesUI.BlankRowCfg())
                posY = posY - hgt
                if not prebuild and pending.decorate then
                    pending.decorate(widget._leftRegion)
                end
            end
            pending, lastRightId = nil, nil
        end

        local function Decorator(rowFrame)
            if not rowFrame.danger then
                return nil
            end
            return function(regionFrame)
                if regionFrame._label then
                    regionFrame._label:SetTextColor(Stl.Unpack(Stl.color.bad))
                end
            end
        end

        local lootMaster = Schema.Row("lootMaster")
        local inForce, main = Schema.Row("councilInForce"), Schema.Row("mainButtons")
        local actions = Schema.Actions()

        local withStatus = pageName == PAGE_LOOT
        local withTools = pageName == PAGE_DATA

        local function Open(action)
            return function()
                CludesUI:Hide()
                action.onClick()
            end
        end

        if withTools then
            _, hgt = W:SectionHeader(hostFrame, T["Tools"]:upper(), posY)
            posY = posY - hgt
            for idx = 1, #actions, 2 do
                local a, b = actions[idx], actions[idx + 1]
                _, hgt = W:WideDualButton(hostFrame, a.text, b and b.text, posY, Open(a), b and Open(b))
                posY = posY - hgt
            end
        end

        local councilCols
        if not withStatus then
        elseif prebuild then
            _, hgt = W:WideDualButton(hostFrame, main.openText, main.historyText, posY)
            posY = posY - hgt
            posY = posY - 32
        else
            _, hgt = W:Spacer(hostFrame, posY, 10)
            posY = posY - hgt
            local cards
            posY, cards = CludesUI.BuildActionCardRow(hostFrame, posY, {
                {
                    icon = ICON_OPEN,
                    title = main.openText,
                    desc = main.openDesc(),
                    pulse = true,
                    onClick = function()
                        if main.openLoot() then
                            CludesUI:Hide()
                        end
                    end,
                },
                {
                    icon = ICON_HISTORY,
                    title = main.historyText,
                    desc = main.historyDesc,
                    onClick = function()
                        CludesUI:Hide()
                        main.openHistory()
                    end,
                },
            })
            OnRefresh(function()
                cards[1]:SetCardContent(ICON_OPEN, main.openText, main.openDesc())

                if cards[1].SetPulse then
                    cards[1]:SetPulse(main.live())
                end
            end)

            _, hgt = W:Spacer(hostFrame, posY, 14)
            posY = posY - hgt

            local full = hostFrame:GetWidth() - PAD * 2
            councilCols = CouncilColumns(full)
            local lines = CouncilLines(#CouncilMembers(inForce, PlayerText, RankText), councilCols)
            local capacity = lines * councilCols
            local height = LIST_Y + lines * COUNCIL_CELL_H + COUNCIL_BOTTOM

            local blockData = CreateFrame("Frame", nil, hostFrame)
            Pix.Size(blockData, full, height)
            Pix.Point(blockData, "TOPLEFT", hostFrame, "TOPLEFT", PAD, posY)
            blockData._skipRowDivider = true
            CludesUI.RowBg(blockData, hostFrame)
            posY = posY - height

            local itemLink = CreateFrame("Button", nil, hostFrame)
            itemLink._isSpacer = true
            itemLink:SetSize(hostFrame:GetWidth(), 20)
            itemLink:SetPoint("TOP", hostFrame, "TOP", 0, posY - 15)
            local textValue = itemLink:CreateFontString(nil, "OVERLAY")
            textValue:SetFont(CludesUI.GetFontPath() or "Fonts\\FRIZQT__.TTF", 15, "")
            textValue:SetTextColor(1, 1, 1, 0.75)
            textValue:SetPoint("TOP", itemLink, "TOP", 0, 0)
            textValue:SetText(CludesUI.L("Friends not running CUI? Download the standalone version here!"))

            local width = textValue.GetStringWidth and textValue:GetStringWidth()
            if type(width) == "number" and not (issecretvalue and issecretvalue(width)) then
                itemLink:SetSize(width + 4, 20)
            end
            itemLink:SetScript("OnEnter", function()
                textValue:SetTextColor(1, 1, 1, 1)
            end)
            itemLink:SetScript("OnLeave", function()
                textValue:SetTextColor(1, 1, 1, 0.75)
            end)
            itemLink:SetScript("OnClick", function(self)
                if CludesUI.ShowLinkPopup then
                    CludesUI.ShowLinkPopup(STANDALONE_URL, self)
                    WidenLinkPopup(STANDALONE_URL)
                end
            end)
            posY = posY - 32

            local statusTags = Schema.Row("statusTags")
            local activeTag = StyledTag(blockData, 90, function(btnFrame)
                if btnFrame == "LeftButton" and statusTags.clickActive() then
                    Invalidate()
                end
            end)
            activeTag:Hide()
            Pix.Point(activeTag, "TOPLEFT", blockData, "TOPLEFT", 16, -12)
            OnRefresh(function()
                local titleText, tone, lines = statusTags.activeTooltip()

                if tone == "accent" and not slc.PlayerIsMasterLooter() then
                    tone = "good"
                end
                activeTag.Label:SetText(Stl.Colorize(Stl.color[tone], lootMaster.activeText))
                activeTag.tip = table.concat(lines, "\n")
                activeTag:SetTone(Stl.color[tone])
                FitTag(activeTag)

                activeTag:SetShown(titleText == statusTags.activeText)
            end)

            local liveTag = StyledTag(blockData, 60, function(btnFrame)
                if statusTags.clickLive(btnFrame) then
                    Invalidate()
                end
            end)
            liveTag:Hide()
            OnRefresh(function()
                local live = statusTags.live()
                liveTag:SetShown(live)
                if not live then
                    return
                end
                local _, tone, lines = statusTags.liveTooltip()
                liveTag.Label:SetText(Stl.Colorize(Stl.color[tone], statusTags.liveText))
                liveTag.tip = table.concat(lines, "\n")
                liveTag:SetTone(Stl.color[tone])
                FitTag(liveTag)
                liveTag:ClearAllPoints()
                if activeTag:IsShown() then
                    Pix.Point(liveTag, "LEFT", activeTag, "RIGHT", 8, 0)
                else
                    Pix.Point(liveTag, "TOPLEFT", blockData, "TOPLEFT", 16, -12)
                end
            end)

            local mlLabel = CludesUI.MakeFont(blockData, 11, nil, 1, 1, 1)
            mlLabel:SetAlpha(0.45)
            mlLabel:SetPoint("TOP", blockData, "TOP", 0, -ML_LABEL_Y)
            mlLabel:SetText(lootMaster.heading)
            local mlName = CludesUI.MakeFont(blockData, 22, nil, 1, 1, 1)
            mlName:SetPoint("TOP", blockData, "TOP", 0, -ML_NAME_Y)

            local mlNote = CludesUI.MakeFont(blockData, 16, nil, 1, 1, 1)
            mlNote:SetPoint("LEFT", mlName, "RIGHT", 8, 0)

            local gray = Stl.Flatten({ 1, 1, 1, 0.45 })
            local noteGray = Stl.ColorStart(gray)

            local headHolder = CreateFrame("Frame", nil, blockData)
            Pix.Size(headHolder, 160, 14)
            Pix.Point(headHolder, "TOP", blockData, "TOP", 0, -DIVIDER_Y)
            local heading = CludesUI.MakeFont(headHolder, 11, nil, 1, 1, 1)
            heading:SetAlpha(0.45)
            heading:SetPoint("LEFT", headHolder, "LEFT", 0, 0)
            heading:SetText(inForce.heading)
            local voters = CludesUI.MakeFont(headHolder, 12, nil, 1, 1, 1)
            voters:SetPoint("RIGHT", headHolder, "RIGHT", 0, 0)
            for _, sideName in ipairs({ "LEFT", "RIGHT" }) do
                local rule = blockData:CreateTexture(nil, "ARTWORK")
                rule:SetColorTexture(1, 1, 1, 0.08)
                rule:SetHeight(1)
                if sideName == "LEFT" then
                    rule:SetPoint("TOPLEFT", blockData, "TOPLEFT", 40, -(DIVIDER_Y + 7))
                    rule:SetPoint("TOPRIGHT", headHolder, "TOPLEFT", -14, -7)
                else
                    rule:SetPoint("TOPLEFT", headHolder, "TOPRIGHT", 14, -7)
                    rule:SetPoint("TOPRIGHT", blockData, "TOPRIGHT", -40, -(DIVIDER_Y + 7))
                end
            end

            local entryRows = {}
            for idx = 1, capacity do
                local rowFrame = CreateFrame("Frame", nil, blockData)
                Pix.Size(rowFrame, COUNCIL_CELL_W - 10, COUNCIL_CELL_H)
                rowFrame.label = CludesUI.MakeFont(rowFrame, 13, nil, 1, 1, 1)
                rowFrame.label:SetJustifyH("CENTER")
                rowFrame.label:SetWordWrap(false)
                rowFrame.label:SetPoint("LEFT", rowFrame, "LEFT", 0, 0)
                rowFrame.label:SetPoint("RIGHT", rowFrame, "RIGHT", 0, 0)
                rowFrame:EnableMouse(true)
                rowFrame:SetScript("OnEnter", function(self)
                    if self.tip then
                        CludesUI.ShowWidgetTooltip(self, self.tip)
                    end
                end)
                rowFrame:SetScript("OnLeave", function()
                    CludesUI.HideWidgetTooltip()
                end)
                entryRows[idx] = rowFrame
            end
            local emptyLabel = CludesUI.MakeFont(blockData, 13, nil, 1, 1, 1)
            emptyLabel:SetPoint("TOP", blockData, "TOP", 0, -(LIST_Y + 4))

            OnRefresh(function()
                local master = lootMaster.fullName()
                mlName:SetText(
                    master and PlayerText(master) or Stl.Colorize(Stl.color.textFaint, lootMaster.unknown)
                )
                local note
                if slc.IsLootPromoted() and UnitIsGroupLeader("player") then
                    note = Stl.Colorize(gray, T["(Promoted)"])
                elseif lootMaster.stored() then
                    local kept = slc.db.lootMasterKept
                    local record = slc.Player:Get(kept.guid or kept.name)
                    local who = ClassText(
                        (record and record.classFile) or kept.classFile,
                        Ambiguate(kept.name, "short")
                    ) .. noteGray
                    note = Stl.Colorize(gray, Format(T["(%s stored)"], Format(T["%s auto-promotion"], who)))
                end
                mlNote:SetText(note or "")
            end)
            OnRefresh(function()
                local entries, count = CouncilMembers(inForce, PlayerText, RankText)
                voters:SetText(
                    Stl.Colorize(count == 0 and Stl.color.bad or Stl.color.accentPale, tostring(count))
                )
                local headW = math.ceil(heading:GetStringWidth() or 0)
                local countW = math.ceil(voters:GetStringWidth() or 0)
                Pix.Size(headHolder, headW + 8 + countW, 14)
                emptyLabel:SetShown(#entries == 0)
                if #entries == 0 then
                    emptyLabel:SetText(
                        count == 0 and Stl.Colorize(Stl.color.bad, inForce.emptyText)
                            or Stl.Colorize(Stl.color.textFaint, inForce.othersEmpty)
                    )
                end

                if #entries > capacity then
                    local hidden, members, ranksHidden = {}, 0, false
                    for idx = capacity, #entries do
                        local entry = entries[idx]
                        hidden[#hidden + 1] = entry.count and Format(T["%s (%s)"], entry.text, entry.count)
                            or entry.text
                        for _, lineTex in ipairs(entry.rank and entry.tooltip or {}) do
                            hidden[#hidden + 1] = "  " .. lineTex
                        end
                        if entry.rank then
                            ranksHidden = true
                        else
                            members = members + 1
                        end
                    end
                    local overflow = #entries - capacity + 1
                    entries[capacity] = {
                        tooltip = hidden,
                        overflow = true,
                        text = ranksHidden
                                and Format(
                                    slc.Locale.Plural({
                                        one = "%d entries hidden",
                                        other = "%d entries hidden",
                                    }),
                                    overflow,
                                    overflow
                                )
                            or Format(
                                slc.Locale.Plural({ one = "%d member hidden", other = "%d members hidden" }),
                                members,
                                members
                            ),
                    }
                end
                local isShown = math.min(#entries, capacity)
                for idx, rowFrame in ipairs(entryRows) do
                    local entry = idx <= isShown and entries[idx]
                    rowFrame:SetShown(entry and true or false)
                    if entry then
                        local lineTex = math.floor((idx - 1) / councilCols)
                        local inLine = math.min(councilCols, isShown - lineTex * councilCols)
                        local leftX = math.floor((full - inLine * COUNCIL_CELL_W) / 2)
                        rowFrame:ClearAllPoints()
                        Pix.Point(
                            rowFrame,
                            "TOPLEFT",
                            blockData,
                            "TOPLEFT",
                            leftX + ((idx - 1) % councilCols) * COUNCIL_CELL_W + 5,
                            -(LIST_Y + lineTex * COUNCIL_CELL_H)
                        )
                        rowFrame.label:SetText(
                            entry.count and Format(T["%s (%s)"], entry.text, entry.count) or entry.text
                        )
                        local tipText = entry.tooltip
                            and #entry.tooltip > 0
                            and (
                                (entry.overflow and "" or entry.text .. "\n")
                                .. table.concat(entry.tooltip, "\n")
                            )
                        rowFrame.tip = tipText or nil
                    end
                end
            end)
        end

        local custom = {}

        function custom.responses(specInfo)
            for slotPos, built in ipairs(specInfo.list()) do
                local entry = built
                OnRefresh(function()
                    entry = specInfo.list()[slotPos] or entry
                end)
                Place({
                    type = "input",
                    text = Format(specInfo.nameLabel, slotPos),
                    inputStyle = "popup",
                    inputWidth = 180,
                    noCapture = true,
                    getValue = function()
                        return entry.text or ""
                    end,

                    setValue = function(textValue)
                        specInfo.setName(slotPos, textValue)
                        Invalidate()
                    end,
                }, function(regionFrame)
                    if regionFrame._label then
                        regionFrame._label:SetText("")
                    end
                    local boxFrame = regionFrame._control
                    if boxFrame then
                        boxFrame:ClearAllPoints()
                        Pix.Point(boxFrame, "LEFT", regionFrame, "LEFT", 20, 0)

                        boxFrame:SetMaxLetters(specInfo.maxLetters)
                        if focusResponse == slotPos then
                            focusResponse = nil
                            boxFrame:SetFocus()
                            boxFrame:HighlightText()
                        end
                    end

                    CludesUI.BuildInlineSwatches(regionFrame, {
                        {
                            getValue = function()
                                return entry.r or 0.8, entry.g or 0.8, entry.b or 0.8, 1
                            end,
                            setValue = function(r, g, b)
                                specInfo.setColour(entry, r, g, b)
                            end,
                        },
                    })

                    local colorSwatch = regionFrame._lastInline

                    local auto
                    if boxFrame and colorSwatch and colorSwatch ~= boxFrame then
                        auto = CreateFrame("Button", nil, regionFrame)
                        auto.slcAutoroll = true
                        local check, _, _, apply =
                            CludesUI.BuildCheckboxControl(auto, regionFrame:GetFrameLevel() + 2)
                        Pix.Point(check, "RIGHT", auto, "RIGHT", 0, 0)
                        local labelText = CludesUI.MakeFont(auto, 12, nil, 1, 1, 1)
                        labelText:SetAlpha(0.6)
                        labelText:SetPoint("RIGHT", check, "LEFT", -6, 0)
                        labelText:SetText(specInfo.autorollText)
                        local labelW = labelText:GetStringWidth()
                        if type(labelW) ~= "number" or (issecretvalue and issecretvalue(labelW)) then
                            labelW = 50
                        end
                        Pix.Size(auto, math.ceil(labelW) + 6 + 18, 24)
                        local hovering = false
                        local function Paint()
                            apply(entry.autoroll == true, hovering)
                        end
                        auto:SetScript("OnEnter", function(b)
                            hovering = true
                            Paint()
                            CludesUI.ShowWidgetTooltip(b, specInfo.autorollHelp)
                        end)
                        auto:SetScript("OnLeave", function()
                            hovering = false
                            Paint()
                            CludesUI.HideWidgetTooltip()
                        end)
                        auto:SetScript("OnClick", function()
                            if specInfo.sessionLocked() then
                                return
                            end
                            specInfo.setAutoroll(entry, not (entry.autoroll == true))
                            Paint()
                            Invalidate()
                        end)
                        OnRefresh(Paint)
                        Paint()
                        auto:ClearAllPoints()
                        Pix.Point(auto, "LEFT", boxFrame, "RIGHT", 8, 0)
                        colorSwatch:ClearAllPoints()
                        Pix.Point(colorSwatch, "LEFT", auto, "RIGHT", 8, 0)
                    end
                    local requirement = specInfo.deleteRequirement
                    local delete = CludesUI.BuildInlineButton(
                        regionFrame,
                        specInfo.confirmDelete().accept,
                        function()
                            if requirement() then
                                return
                            end
                            local copy = specInfo.confirmDelete()
                            Stl.Confirm({
                                title = copy.title,
                                body = copy.body,
                                accept = copy.accept,
                                onAccept = function()
                                    if specInfo.remove(slotPos) then
                                        Invalidate()
                                    end
                                end,
                            })
                        end,
                        {
                            width = 70,
                            disabled = function()
                                return requirement() ~= nil
                            end,
                            disabledTooltip = requirement,
                            rawTooltip = true,
                        }
                    )
                    if delete and colorSwatch and colorSwatch ~= boxFrame then
                        delete:ClearAllPoints()
                        Pix.Point(delete, "LEFT", colorSwatch, "RIGHT", 8, 0)
                    end

                    if boxFrame and colorSwatch and delete and colorSwatch ~= boxFrame then
                        local sum = boxFrame:GetWidth()
                            + 8
                            + (auto and (auto:GetWidth() + 8) or 0)
                            + colorSwatch:GetWidth()
                            + 8
                            + delete:GetWidth()
                        local room = regionFrame:GetWidth()
                        if type(sum) == "number" and type(room) == "number" and room > sum then
                            boxFrame:ClearAllPoints()
                            Pix.Point(boxFrame, "LEFT", regionFrame, "LEFT", math.floor((room - sum) / 2), 0)
                        end
                    end
                end)
            end
            if #specInfo.list() < specInfo.max then
                Place({
                    type = "button",
                    text = specInfo.addText,
                    noCapture = true,
                    onClick = function()
                        local accent = CludesUI.CLUDES_GREEN
                        local slotPos = specInfo.add(accent.r, accent.g, accent.b)
                        if slotPos then
                            focusResponse = slotPos
                            Invalidate()
                        end
                    end,
                })
            end
            Flush()
        end

        local PRIDE_ON = { ["i am gay"] = true, ["im gay"] = true }
        local PRIDE_OFF = { ["i am not gay"] = true, ["im not gay"] = true }
        local function PrideRequest(textValue)
            if textValue:find("-", 1, true) then
                return nil
            end
            local phrase = slc.Locale
                .Fold(textValue)
                :gsub("\226\128\153", "")
                :gsub("'", "")
                :gsub("%s+", " ")
                :gsub("^%s*(.-)%s*$", "%1")
            if PRIDE_ON[phrase] then
                return true
            end
            if PRIDE_OFF[phrase] then
                return false
            end
            return nil
        end

        local function Rainbow(textValue)
            if textValue:find("[\128-\255]") then
                return textValue
            end
            return Stl.Rainbow(textValue)
        end

        local function TryPride(textValue)
            local wanted = PrideRequest(textValue)
            if wanted == nil then
                return false
            end
            local current = slc.db and slc.db.pride and true or false
            if wanted == current then
                Stl.Confirm({
                    title = CludesUI.L("Gay Mode"),
                    acknowledge = true,
                    body = wanted and Rainbow(CludesUI.L("You're already gay"))
                        or CludesUI.L("You're already straight"),
                })
                return true
            end
            Stl.Confirm({
                title = CludesUI.L("Gay Mode"),
                accept = CludesUI.L("Yes"),
                body = wanted and Rainbow(CludesUI.L("Are you sure you're gay?"))
                    or CludesUI.L("Are you sure you're not gay?"),
                onAccept = function()
                    slc.db.pride = wanted
                    Stl.RefreshLogos()
                    slc.Log:I("UI", "pride mode " .. (wanted and "on" or "off"))
                end,
            })
            return true
        end

        function custom.council(specInfo)
            if prebuild then
                return
            end
            local status = Note("", 0.85)
            OnRefresh(function()
                local good, warn =
                    Stl.ColorStart(Stl.Flatten(Stl.color.good)), Stl.ColorStart(Stl.Flatten(Stl.color.warn))
                local state, leader = specInfo.authorship()
                status:SetText(specInfo.statusText(state, leader, good, warn))
            end)

            Note(specInfo.hint())
            local boxFrame = AddBox(Row(50), math.min(260, Width() - 20 - 8 - 90 - 20), specInfo.addText())

            local function AddTyped()
                CloseSuggestions()
                local name = boxFrame:GetText():trim()
                if name == "" then
                    return
                end

                if TryPride(name) then
                    boxFrame:SetText("")
                    boxFrame:ClearFocus()
                    return
                end
                if specInfo.add(name) then
                    boxFrame:SetText("")
                end
                boxFrame:ClearFocus()
                councilDirty = true
                Invalidate()
            end

            local isShown = {}
            local function Fill(b, entry)
                local fillTex = specInfo.suggestionText(entry)
                b:SetText(fillTex)
                b:SetCursorPosition(#fillTex)
                b:SetFocus()
            end
            local function ShowList(b)
                CloseSuggestions()
                if #isShown == 0 then
                    return
                end
                local p = SugPopup()
                p.owner = b
                p.onPick = function(entry)
                    CloseSuggestions()
                    isShown = {}
                    Fill(b, entry)
                end
                for slotPos, entry in ipairs(isShown) do
                    local rowFrame = SugRow(p, slotPos)
                    local name = (tostring(entry.name):gsub("|", "||"))
                    local rank = (tostring(entry.rank or ""):gsub("|", "||"))
                    rowFrame.entry = entry
                    rowFrame.label:SetText(
                        ClassText(
                            entry.classFile,
                            name,
                            entry.online and Stl.color.text or Stl.color.textFaint
                        )
                            .. "  "
                            .. faint
                            .. rank
                            .. "|r"
                    )
                    rowFrame:Show()
                end
                for slotPos = #isShown + 1, #p.rows do
                    p.rows[slotPos].entry = nil
                    p.rows[slotPos]:Hide()
                end
                p.selected = 0
                SugPaint(p)
                local own, baseValue = b:GetEffectiveScale(), _G.UIParent:GetEffectiveScale()
                if type(own) == "number" and type(baseValue) == "number" and baseValue > 0 and own > 0 then
                    p:SetScale(own / baseValue)
                end
                p:SetSize(b:GetWidth(), #isShown * SUG_ROW_H + 8)
                p:ClearAllPoints()
                p:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, -2)
                p._brd:Fit()
                p:Show()
            end
            local function Typed(b, userInput)
                if not userInput then
                    return
                end
                CloseSuggestions()
                isShown = {}
                local textValue = (b:GetText() or ""):trim()

                if select(2, textValue:gsub("[^\128-\191]", "")) < SUGGEST_MIN_CHARS then
                    return
                end
                if PrideRequest(textValue) ~= nil then
                    return
                end
                isShown = specInfo.suggest(textValue, SUGGEST_MAX)
                ShowList(b)
            end
            local function Arrow(_, key)
                if not SugOpen() or #isShown == 0 then
                    return
                end
                local p = sugPopup
                if key == "UP" then
                    p.selected = p.selected == 0 and #isShown or math.max(p.selected - 1, 1)
                elseif key == "DOWN" then
                    p.selected = p.selected == 0 and 1 or math.min(p.selected + 1, #isShown)
                else
                    return
                end
                SugPaint(p)
            end
            local function Enter()
                local entry = SugOpen() and isShown[sugPopup.selected]
                if entry then
                    CloseSuggestions()
                    isShown = {}
                    Fill(boxFrame, entry)
                else
                    AddTyped()
                end
            end
            addHandlers.add, addHandlers.typed = AddTyped, Typed
            addHandlers.arrow, addHandlers.enter = Arrow, Enter

            local entries, here = CouncilEntries(specInfo), slc.GetCandidates()
            OnRefresh(function()
                entries, here = CouncilEntries(specInfo), slc.GetCandidates()
            end)
            for slotPos = 1, #entries do
                local rowFrame = Row(34)
                local labelText = CludesUI.MakeFont(rowFrame, 13, nil, 1, 1, 1)
                labelText:SetPoint("LEFT", rowFrame, "LEFT", 20, 0)
                labelText:SetPoint("RIGHT", rowFrame, "RIGHT", -98, 0)
                labelText:SetJustifyH("LEFT")
                labelText:SetWordWrap(false)
                local entry, present
                OnRefresh(function()
                    entry = entries[slotPos]
                    present = entry.kind ~= "rank" and (here[entry.fullName] and true or false)
                    local nowTime = present
                    if entry.kind == "rank" then
                        local name = RankText(entry.name)
                        if not entry.known then
                            labelText:SetText(
                                Stl.Colorize(
                                    Stl.Flatten(Stl.color.textFaint),
                                    Format(T["%s  no such rank"], entry.name)
                                )
                            )
                        elseif entry.present == 0 then
                            labelText:SetText(Format(T["%s%s  none here|r"], name, faint))
                        else
                            labelText:SetText(Format(T["%s%s  %d here|r"], name, faint, entry.present))
                        end
                    elseif entry.pending then
                        labelText:SetText(
                            ClassText(
                                entry.classFile,
                                entry.fullName or entry.guid or "?",
                                Stl.Flatten(Stl.color.textFaint)
                            )
                        )
                    else
                        local short = ClassText(entry.classFile, Ambiguate(entry.fullName or "?", "short"))
                        labelText:SetText(nowTime and short or Format(T["%s%s  not here|r"], short, faint))
                    end
                end)

                rowFrame:EnableMouse(true)
                rowFrame:SetScript("OnEnter", function(r)
                    if not entry then
                        return
                    end
                    local titleText, lines = specInfo.describe(entry, present)
                    local textValue = { Stl.Colorize(Stl.color.accent, titleText) }
                    for _, lineTex in ipairs(lines) do
                        local body = lineTex.value
                                and (slc.Locale.SectionTitle(lineTex.text) .. " " .. lineTex.value)
                            or lineTex.text
                        textValue[#textValue + 1] = lineTex.tone
                                and Stl.Colorize(Stl.color[lineTex.tone], body)
                            or body
                    end
                    CludesUI.ShowWidgetTooltip(r, table.concat(textValue, "\n"), { justify = "LEFT" })
                end)
                rowFrame:SetScript("OnLeave", function()
                    CludesUI.HideWidgetTooltip()
                end)
                CludesUI.BuildInlineButton(rowFrame, T["Remove"], function()
                    if not entry then
                        return
                    end
                    specInfo.remove(entry)
                    councilDirty = true
                    Invalidate()
                end, { width = 70 })
            end
            if #entries == 0 then
                Note(specInfo.emptyText())
            end
        end

        function custom.councilRanks(specInfo)
            if not prebuild then
                Note(Stl.Colorize(Stl.color.accent, specInfo.heading:upper()), 0.85)
                for _, hint in ipairs(specInfo.hints()) do
                    Note(hint)
                end
            end
            local ranks = specInfo.ranks()
            local count = math.min(#ranks, specInfo.maxRows)
            local viewH = math.min(count, RANK_VISIBLE) * RANK_ROW_H
            if prebuild then
                posY = posY - viewH
            elseif count > 0 then
                local scrollFrame = CreateFrame("ScrollFrame", nil, hostFrame)
                Pix.Size(scrollFrame, Width(), viewH)
                Pix.Point(scrollFrame, "TOPLEFT", hostFrame, "TOPLEFT", PAD + colX, posY)
                posY = posY - viewH
                local list = CreateFrame("Frame", nil, scrollFrame)
                Pix.Size(list, Width(), count * RANK_ROW_H)
                scrollFrame:SetScrollChild(list)
                if count > RANK_VISIBLE then
                    local updateThumb = CludesUI.AttachSmoothScrollbar(scrollFrame, {
                        step = RANK_ROW_H,
                        child = list,
                        panelWheel = true,
                        passWheel = true,
                    })
                    OnRefresh(updateThumb)
                end
                for slotPos = 1, count do
                    local name = ranks[slotPos].name
                    local rowFrame = CreateFrame("Frame", nil, list)
                    Pix.Size(rowFrame, Width(), RANK_ROW_H)
                    Pix.Point(rowFrame, "TOPLEFT", list, "TOPLEFT", 0, -(slotPos - 1) * RANK_ROW_H)
                    CludesUI.RowBg(rowFrame, list)
                    local btn = CreateFrame("Button", nil, rowFrame)
                    btn:SetAllPoints(rowFrame)
                    local boxFrame, _, _, apply =
                        CludesUI.BuildCheckboxControl(btn, rowFrame:GetFrameLevel() + 1)
                    Pix.Point(boxFrame, "LEFT", btn, "LEFT", 20, 0)
                    local labelText = CludesUI.MakeFont(btn, 14, nil, 1, 1, 1)
                    labelText:SetPoint("LEFT", boxFrame, "RIGHT", 10, 0)
                    labelText:SetPoint("RIGHT", btn, "RIGHT", -20, 0)
                    labelText:SetJustifyH("LEFT")
                    labelText:SetWordWrap(false)
                    labelText:SetText(RankText(name))
                    local hovering = false
                    local function Paint()
                        apply(specInfo.isEmpowered(name) and true or false, hovering)
                    end
                    btn:SetScript("OnEnter", function()
                        hovering = true
                        Paint()
                    end)
                    btn:SetScript("OnLeave", function()
                        hovering = false
                        Paint()
                    end)
                    btn:SetScript("OnClick", function()
                        specInfo.setEmpowered(name, not specInfo.isEmpowered(name))
                        Paint()

                        councilDirty = true
                        Invalidate()
                    end)
                    OnRefresh(Paint)
                    Paint()
                end
            end
            local empty = specInfo.empty()
            if empty and not prebuild then
                Note(empty)
            end
        end

        function custom.councilPair(councilSpec, rankSpec)
            local GAP = 20
            local full = hostFrame:GetWidth() - PAD * 2
            local half = math.floor((full - GAP) / 2)
            local topY = posY
            colX, colW = 0, half
            custom.council(councilSpec)
            local leftEnd = posY
            posY = topY
            colX = half + GAP
            custom.councilRanks(rankSpec)
            local rightEnd = posY
            colX, colW = 0, nil
            posY = math.min(leftEnd, rightEnd)
            if not prebuild then
                local rule = hostFrame:CreateTexture(nil, "ARTWORK")
                rule:SetColorTexture(1, 1, 1, 0.08)
                rule:SetWidth(1)
                rule:SetPoint("TOPLEFT", hostFrame, "TOPLEFT", PAD + half + GAP / 2, topY - 4)
                rule:SetPoint("BOTTOMLEFT", hostFrame, "TOPLEFT", PAD + half + GAP / 2, posY + 4)
            end
        end

        function custom.alts(specInfo)
            local main = specInfo.main()
            local alts = specInfo.alts(main)
            local function Qualified(fullName)
                if not fullName then
                    return Stl.Colorize(Stl.color.textMuted, specInfo.unknownText)
                end
                local character, realm, colour = specInfo.nameParts(fullName, function(classFile)
                    local r, g, b = Stl.ClassColor(classFile)
                    return r and { r = r, g = g, b = b } or nil
                end)
                return Stl.Colorize(colour and { colour.r, colour.g, colour.b } or Stl.color.text, character)
                    .. Stl.Colorize(Stl.color.text, realm)
            end
            if not prebuild then
                local mainLine = Note("", 0.85)
                OnRefresh(function()
                    mainLine:SetText(Format(T["Main: %s"], Qualified(specInfo.main())))
                end)
            end

            local function Box(textValue, submit)
                local kept = ""
                return {
                    type = "input",
                    text = textValue,
                    inputStyle = "popup",
                    inputWidth = 200,
                    placeholder = specInfo.hint(),
                    noCapture = true,
                    getValue = function()
                        return kept
                    end,
                    setValue = function(value)
                        local done = submit(value)
                        kept = done == false and value or ""
                        if done then
                            Invalidate()
                        end
                    end,
                }
            end
            local showAlts = specInfo.showAlts
            local showCfg = {
                type = "toggle",
                text = showAlts.text,
                noCapture = true,
                getValue = showAlts.getValue,
                setValue = function(value)
                    showAlts.setValue(value)
                    Invalidate()
                end,
            }

            if #alts == 0 then
                Place(Box(specInfo.designateText, specInfo.designateMain))
            end
            Place(Box(specInfo.addText, specInfo.addAlt))
            Place(showCfg)
            Flush()
            if prebuild then
                return
            end

            OnRefresh(function()
                alts = specInfo.alts(specInfo.main())
            end)
            for slotPos = 1, #alts do
                local rowFrame = Row(34)

                local labelText = CludesUI.MakeFont(rowFrame, 13, nil, 1, 1, 1)
                labelText:SetPoint("LEFT", rowFrame, "LEFT", 20, 0)

                OnRefresh(function()
                    labelText:SetText(Qualified(alts[slotPos]))
                end)
                local copy = specInfo.confirmRemove()
                CludesUI.BuildInlineButton(rowFrame, copy.accept, function()
                    local alt = alts[slotPos]
                    Stl.Confirm({
                        title = copy.title,
                        body = copy.body,
                        accept = copy.accept,
                        onAccept = function()
                            specInfo.removeAlt(alt)
                            Invalidate()
                        end,
                    })
                end, { width = 70 })
            end
        end

        local sections = PageSections(Schema, pageName)
        for _, section in ipairs(sections) do
            _, hgt = W:SectionHeader(hostFrame, section.title:upper(), posY)
            posY = posY - hgt
            local rowsTop = posY
            for _, rowFrame in ipairs(section.rows) do
                if rowFrame.hidden and rowFrame.hidden() then
                elseif rowFrame.type == "checks" or rowFrame.type == "multiselect" then
                    Place(ChecksCfg(rowFrame), ChecksDecorator(rowFrame), rowFrame.id, rowFrame.dependsOn)
                elseif rowFrame.id == "council" then
                    Flush()
                    custom.councilPair(rowFrame, Schema.Row("councilRanks"))
                elseif rowFrame.id == "councilRanks" then
                elseif rowFrame.custom then
                    Flush()
                    custom[rowFrame.id](rowFrame)
                else
                    Place(Cfg(rowFrame), Decorator(rowFrame), rowFrame.id, rowFrame.dependsOn)
                end
            end
            Flush()

            local reason = section.locked and section.locked()
            if
                (section.id == "council" or section.id == "master" or section.id == "voting")
                and section.locked
                and not prebuild
                and posY < rowsTop
            then
                LockCover(rowsTop, posY, reason or Schema.LootMasterLockReason(), function()
                    return section.locked() ~= nil
                end)
            end

            if section.id == "responses" and not prebuild and posY < rowsTop then
                local specInfo = Schema.Row("responses")
                LockCover(rowsTop, posY, specInfo.sessionLockedText, specInfo.sessionLocked)
            end
        end

        if prebuild then
            return math.abs(posY)
        end

        local function Shape()
            local parts = {}
            for _, section in ipairs(sections) do
                for _, rowFrame in ipairs(section.rows) do
                    parts[#parts + 1] = (rowFrame.hidden and rowFrame.hidden()) and "h" or "v"
                end
            end
            local ranks = Schema.Row("councilRanks")
            local alts = Schema.Row("alts")
            parts[#parts + 1] = #Schema.Row("responses").list()
            parts[#parts + 1] = #CouncilEntries(Schema.Row("council"))
            parts[#parts + 1] = math.min(#ranks.ranks(), ranks.maxRows)
            parts[#parts + 1] = ranks.empty() or ""
            parts[#parts + 1] = #alts.alts(alts.main())

            if councilCols then
                parts[#parts + 1] = CouncilLines(
                    #CouncilMembers(Schema.Row("councilInForce"), tostring, tostring),
                    councilCols
                )
            end
            return table.concat(parts, ",")
        end
        local built = Shape()
        local function RefreshAll()
            if Shape() ~= built then
                RequestRebuild()
                return
            end
            for idx = 1, #refreshes do
                refreshes[idx]()
            end
        end
        CludesUI.RegisterWidgetRefresh(RefreshAll)
        RefreshAll()

        Subscribe(slc, Schema)

        hostFrame:SetScript("OnShow", function()
            Listen(true)
        end)
        hostFrame:SetScript("OnHide", function()
            Listen(false)
        end)
        if hostFrame:IsVisible() then
            Listen(true)
        end
        if not prebuild then
            ShowBanner()
        end

        return math.abs(posY)
    end

    CludesUI:RegisterModule(ADDON_NAME, {
        title = "Simple Loot Council",
        description = MODULE_DESC,
        pages = PAGES,
        buildPage = function(pageName, hostFrame, yOffset)
            if PAGE_SECTIONS[pageName] then
                return BuildSettingsPage(pageName, hostFrame, yOffset)
            end
        end,

        onPageCacheRestore = function()
            ShowBanner()
            councilDirty = true
            CludesUI:RefreshPage()
        end,

        onModuleLeave = HideBanner,
    })
end)

if IsLoggedIn() then
    initFrame:GetScript("OnEvent")(initFrame)
end
