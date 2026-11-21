if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_Minimap_Indicators.lua
--
--  The custom indicator buttons, the Great Vault button with its tooltip
--  and the M+ Portal button.
--  Reads the earlier Minimap files through ns._internals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._internals
-- CludesUIMinimap.lua or an earlier CUI_Minimap_*.lua file failed to load.
if not Inner or Inner.broken then return end
Inner.broken = true

local SKIN, GetFFD, GetCustomTooltipScale = Inner.EBS, Inner.GetFFD, Inner.GetCustomTooltipScale
local GetInteractableBtnSize, SetPortalFlyout = Inner.GetInteractableBtnSize, Inner.SetPortalFlyout

-- Shared state: one copy per file. A write goes through the Set<Name>
-- function of ns._internals, which hands the value to every copy.
local MO_Evaluate
Inner.moEvaluateSetters[#Inner.moEvaluateSetters + 1] = function(val) MO_Evaluate = val end

-------------------------------------------------------------------------------
--  Minimap Indicator Buttons (custom replacements for Blizzard's reparented frames)
--  Our own Button with black bg, icon and click handler: no Blizzard frame
--  reparenting = no taint, no layout fights.
-------------------------------------------------------------------------------
local _customIndicators = {} -- { tracking, calendar, mail, crafting }

-- Native atlas aspect ratios (width / height) and per-icon scale multipliers
local INDICATOR_ATLAS_RATIO = {
    ["UI-HUD-Minimap-Tracking-Up"] = 15 / 14,
    ["UI-HUD-Minimap-Tracking-Mouseover"] = 15 / 14,
    ["UI-HUD-Minimap-Tracking-Down"] = 16 / 15,
    ["UI-HUD-Minimap-Mail-Up"] = 19.5 / 15,
    ["UI-HUD-Minimap-Mail-Mouseover"] = 19.5 / 15,
    ["UI-HUD-Minimap-CraftingOrder-Up-2x"] = 17 / 16,
    ["UI-HUD-Minimap-CraftingOrder-Over-2x"] = 17 / 16,
    ["UI-HUD-Minimap-CraftingOrder-Down-2x"] = 17 / 16,
}
local INDICATOR_ATLAS_SCALE = {}
-- Calendar atlases: all 31 days share the same ratio/scale
for day = 1, 31 do
    local prefixText = "UI-HUD-Calendar-" .. day
    INDICATOR_ATLAS_RATIO[prefixText .. "-Up"] = 21 / 19
    INDICATOR_ATLAS_RATIO[prefixText .. "-Mouseover"] = 21 / 19
    INDICATOR_ATLAS_RATIO[prefixText .. "-Down"] = 21 / 19
    INDICATOR_ATLAS_SCALE[prefixText .. "-Up"] = 1.25
    INDICATOR_ATLAS_SCALE[prefixText .. "-Mouseover"] = 1.25
    INDICATOR_ATLAS_SCALE[prefixText .. "-Down"] = 1.25
end
-- Per-icon pixel offset from center { x, y }
local INDICATOR_ATLAS_OFFSET = {
    _gameTime = { 2, -2 },
    _mail = { 1, -1 },
}

local function CreateIndicatorBtn(name, hostFrame, upAtlas, overAtlas, downAtlas, onClick)
    local button = CreateFrame("Button", nil, hostFrame)
    button:SetSize(GetInteractableBtnSize(), GetInteractableBtnSize())
    button:SetFrameLevel(hostFrame:GetFrameLevel() + 20)
    button:EnableMouse(true)

    local backdrop = CreateFrame("Frame", nil, button, "BackdropTemplate")
    backdrop:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground" })
    backdrop:SetBackdropColor(0, 0, 0, 0.8)
    backdrop:SetAllPoints(button)
    backdrop:SetFrameLevel(button:GetFrameLevel() - 1)
    button._bg = backdrop

    -- Icon sized to preserve the atlas aspect ratio within the button.
    local iconTex = button:CreateTexture(nil, "ARTWORK")
    local inset = 3
    local ratio = upAtlas and INDICATOR_ATLAS_RATIO[upAtlas]
    if ratio then
        local btnSz = GetInteractableBtnSize()
        local avail = btnSz - inset * 2
        local scale = INDICATOR_ATLAS_SCALE[upAtlas] or 1
        local iconW, iconH
        if ratio >= 1 then
            iconW = avail * scale
            iconH = (avail / ratio) * scale
        else
            iconH = avail * scale
            iconW = (avail * ratio) * scale
        end
        iconTex:SetSize(iconW, iconH)
        local off = INDICATOR_ATLAS_OFFSET[name]
        iconTex:SetPoint("CENTER", button, "CENTER", off and off[1] or 0, off and off[2] or 0)
    else
        iconTex:SetPoint("TOPLEFT", button, "TOPLEFT", inset, -inset)
        iconTex:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -inset, inset)
    end
    if upAtlas then iconTex:SetAtlas(upAtlas) end
    button._icon = iconTex
    button._upAtlas = upAtlas
    button._overAtlas = overAtlas
    button._downAtlas = downAtlas
    button._indicatorKey = name

    button:SetScript("OnEnter", function(self)
        if self._overAtlas and self._icon then self._icon:SetAtlas(self._overAtlas) end
    end)
    button:SetScript("OnLeave", function(self)
        if self._upAtlas and self._icon then self._icon:SetAtlas(self._upAtlas) end
    end)
    button:SetScript("OnMouseDown", function(self)
        if self._downAtlas and self._icon then self._icon:SetAtlas(self._downAtlas) end
    end)
    button:SetScript("OnMouseUp", function(self)
        local over = self:IsMouseOver()
        local atlas = over and self._overAtlas or self._upAtlas
        if atlas and self._icon then self._icon:SetAtlas(atlas) end
    end)

    if onClick then
        button:SetScript("OnClick", function(self)
            if GetFFD(self).freeMoveJustDragged then return end
            onClick(self)
        end)
    end

    return button
end

-- Great Vault button: top of the ungrouped stack above the flyout toggle; a single "whole" atlas scaled to fit.
local GREAT_VAULT_WHOLE_ATLAS = "greatVault-whole-normal"

local function GetOrderedWeeklyActivities(activityType)
    if not C_WeeklyRewards or not C_WeeklyRewards.GetActivities then return nil end

    local activities = C_WeeklyRewards.GetActivities(activityType)
    if type(activities) ~= "table" or #activities == 0 then return nil end

    local ordered = {}
    for index = 1, #activities do
        ordered[index] = activities[index]
    end

    table.sort(ordered, function(lhs, rhs)
        local aIndex = lhs and lhs.index or 0
        local bIndex = rhs and rhs.index or 0
        if aIndex == bIndex then return (lhs and lhs.threshold or 0) < (rhs and rhs.threshold or 0) end
        return aIndex < bIndex
    end)

    return ordered
end

local function GetVaultTokenColor(status)
    if status == "done" then
        return 0.176, 0.796, 0.349
    elseif status == "partial" then
        return 0.812, 0.592, 0.212
    end

    return 0.58, 0.58, 0.58
end

-- Build vault row data: { label, isRaid, tokens = { {text, state}, ... } }
local function BuildVaultRowData(labelText, activityType, isRaid)
    local activities = GetOrderedWeeklyActivities(activityType)
    local tokens = {}
    for index = 1, 3 do
        local details = activities and activities[index]
        if not details then
            tokens[index] = { text = "-", state = "empty" }
        else
            local progress = math.max(0, tonumber(details.progress) or 0)
            local threshold = math.max(0, tonumber(details.threshold) or 0)
            local level = math.max(0, tonumber(details.level) or 0)
            if threshold <= 0 then
                tokens[index] = { text = "-", state = "empty" }
            elseif progress >= threshold then
                if isRaid then
                    tokens[index] = { text = ("%d/%d"):format(progress, threshold), state = "done" }
                elseif level > 0 then
                    tokens[index] = { text = "+" .. level, state = "done" }
                else
                    tokens[index] = { text = ("%d/%d"):format(progress, threshold), state = "done" }
                end
            else
                tokens[index] = {
                    text = ("%d/%d"):format(progress, threshold),
                    state = progress > 0 and "partial" or "empty",
                }
            end
        end
    end
    return { label = labelText, tokens = tokens }
end

-- Custom multi-column vault tooltip (pixel-aligned columns via FontStrings)
local _vaultTT
local _vaultTTRows = {} -- [row][col] = FontString
local VAULT_COL_GAP = 8
local VAULT_ROW_H = 14
local VAULT_PAD = 6

local function GetVaultTooltip()
    if _vaultTT then return _vaultTT end
    local frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    frame:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeSize = 1,
    })
    frame:SetBackdropColor(0.06, 0.06, 0.06, 0.90)
    frame:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
    frame:SetFrameStrata("TOOLTIP")
    frame:SetClampedToScreen(true)
    frame:Hide()

    -- Fade animations (matches ShowWidgetTooltip/HideWidgetTooltip)
    local fadeInAG = frame:CreateAnimationGroup()
    local fadeIn = fadeInAG:CreateAnimation("Alpha")
    fadeIn:SetDuration(0.25)
    fadeIn:SetSmoothing("OUT")
    fadeInAG:SetScript("OnFinished", function() frame:SetAlpha(1) end)
    frame._fadeInAG = fadeInAG
    frame._fadeIn = fadeIn

    local fadeOutAG = frame:CreateAnimationGroup()
    local fadeOut = fadeOutAG:CreateAnimation("Alpha")
    fadeOut:SetDuration(0.25)
    fadeOut:SetSmoothing("IN")
    fadeOutAG:SetScript("OnFinished", function()
        frame:SetAlpha(0)
        frame:Hide()
    end)
    frame._fadeOutAG = fadeOutAG
    frame._fadeOut = fadeOut

    -- Title row (font set at show-time)
    local title = frame:CreateFontString(nil, "OVERLAY")
    title:SetFont("Fonts\\FRIZQT__.TTF", 11, "") -- placeholder, updated on show
    title:SetTextColor(0.80, 0.80, 0.80, 1)
    title:SetPoint("TOP", frame, "TOP", 0, -VAULT_PAD)
    title:SetText(CludesUI.L("Great Vault"))
    frame._title = title

    -- 3 data rows x 4 columns (label + 3 tokens)
    for row = 1, 3 do
        _vaultTTRows[row] = {}
        for colour = 0, 3 do
            local fontStr = frame:CreateFontString(nil, "OVERLAY")
            fontStr:SetFont("Fonts\\FRIZQT__.TTF", 11, "") -- placeholder, updated on show
            fontStr:SetJustifyH("LEFT")
            _vaultTTRows[row][colour] = fontStr
        end
    end

    _vaultTT = frame
    return frame
end

local function ShowVaultTooltip(anchor)
    local raidType = (
        Enum
        and Enum.WeeklyRewardChestThresholdType
        and Enum.WeeklyRewardChestThresholdType.Raid
    ) or 3
    local dungeonType = (
        Enum
        and Enum.WeeklyRewardChestThresholdType
        and Enum.WeeklyRewardChestThresholdType.Activities
    ) or 1
    local worldType = (
        Enum
        and Enum.WeeklyRewardChestThresholdType
        and Enum.WeeklyRewardChestThresholdType.World
    ) or 6

    local rowList = {
        BuildVaultRowData(CludesUI.L("Raids"), raidType, true),
        BuildVaultRowData(CludesUI.L("Mythic+"), dungeonType, false),
        BuildVaultRowData(CludesUI.L("World"), worldType, false),
    }

    local tooltip = GetVaultTooltip()
    -- Scale the whole tooltip to the user's Custom Tooltip Size (re-applied each show).
    tooltip:SetScale(GetCustomTooltipScale())

    local fontFile = (CludesUI.GetFontPath("minimap")) or "Fonts\\FRIZQT__.TTF"
    local fontFlags = (CludesUI.GetFontOutlineFlag("minimap")) or ""
    tooltip._title:SetFont(fontFile, 11, fontFlags)
    for region = 1, 3 do
        _vaultTTRows[region][0]:SetFont(fontFile, 11, fontFlags)
        for c = 1, 3 do
            _vaultTTRows[region][c]:SetFont(fontFile, 10, fontFlags)
        end
    end

    local colWidths = { 0, 0, 0, 0 }
    for region = 1, 3 do
        local rd = rowList[region]
        local labelFS = _vaultTTRows[region][0]
        labelFS:SetText(rd.label)
        labelFS:SetTextColor(0.812, 0.592, 0.212, 1)
        local wid = labelFS:GetStringWidth() or 0
        if wid > colWidths[1] then colWidths[1] = wid end

        for c = 1, 3 do
            local tk = rd.tokens[c]
            local fontStr = _vaultTTRows[region][c]
            fontStr:SetText(tk.text)
            local tr, tg, tb = GetVaultTokenColor(tk.state)
            fontStr:SetTextColor(tr, tg, tb, 1)
            local tw = fontStr:GetStringWidth() or 0
            if tw > colWidths[c + 1] then colWidths[c + 1] = tw end
        end
    end

    local titleTop = VAULT_PAD + (tooltip._title:GetStringHeight() or 14) + 4
    local colX = { VAULT_PAD }
    for c = 2, 4 do
        colX[c] = colX[c - 1] + colWidths[c - 1] + VAULT_COL_GAP
    end
    local totalW = colX[4] + colWidths[4] + VAULT_PAD

    for region = 1, 3 do
        local posY = -(titleTop + (region - 1) * VAULT_ROW_H)
        for c = 0, 3 do
            _vaultTTRows[region][c]:ClearAllPoints()
            _vaultTTRows[region][c]:SetPoint("TOPLEFT", tooltip, "TOPLEFT", colX[c + 1], posY)
        end
    end

    local totalH = titleTop + 3 * VAULT_ROW_H + VAULT_PAD
    tooltip:SetSize(totalW, totalH)
    tooltip:ClearAllPoints()
    local gpt = SKIN._Grow.center[SKIN._Grow.Dir()] or SKIN._Grow.center.left
    tooltip:SetPoint(gpt[1], anchor, gpt[2], gpt[3], gpt[4])

    tooltip._fadeOutAG:Stop()
    tooltip._fadeInAG:Stop()
    tooltip:SetAlpha(0)
    tooltip:Show()
    tooltip._fadeIn:SetFromAlpha(0)
    tooltip._fadeIn:SetToAlpha(1)
    tooltip._fadeInAG:Play()
end

local function HideVaultTooltip()
    if not _vaultTT or not _vaultTT:IsShown() then return end
    _vaultTT._fadeInAG:Stop()
    _vaultTT._fadeOutAG:Stop()
    _vaultTT._fadeOut:SetFromAlpha(_vaultTT:GetAlpha())
    _vaultTT._fadeOut:SetToAlpha(0)
    _vaultTT._fadeOutAG:Play()
end

local function SizeGreatVaultBtn(button, showBg)
    local btnSz = GetInteractableBtnSize()
    button:SetSize(btnSz, btnSz)
    if button._bg then button._bg:SetShown(showBg ~= false) end
    local inset = 3
    local avail = btnSz - inset * 2
    -- Whole is 105x108: height is the limiting dimension. Fit by height.
    local wholeH = avail
    local wholeW = wholeH * (105 / 108)
    button._whole:SetSize(wholeW, wholeH)
    button._whole:ClearAllPoints()
    button._whole:SetPoint("CENTER", button, "CENTER", 0, 0)
end

local function CreateGreatVaultBtn(hostFrame)
    local button = CreateFrame("Button", nil, hostFrame)
    button:SetSize(GetInteractableBtnSize(), GetInteractableBtnSize())
    button:SetFrameLevel(hostFrame:GetFrameLevel() + 10)
    button:EnableMouse(true)

    local backdrop = CreateFrame("Frame", nil, button, "BackdropTemplate")
    backdrop:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground" })
    backdrop:SetBackdropColor(0, 0, 0, 0.8)
    backdrop:SetAllPoints(button)
    backdrop:SetFrameLevel(button:GetFrameLevel() - 1)
    button._bg = backdrop

    local whole = button:CreateTexture(nil, "ARTWORK")
    whole:SetAtlas(GREAT_VAULT_WHOLE_ATLAS)
    button._whole = whole

    SizeGreatVaultBtn(button)

    button:SetScript("OnEnter", function(self)
        self._whole:SetVertexColor(1, 1, 1, 1)
        ShowVaultTooltip(self)
    end)
    button:SetScript("OnLeave", function(self)
        self._whole:SetVertexColor(0.85, 0.85, 0.85, 1)
        HideVaultTooltip()
        CludesUI.HideWidgetTooltip()
    end)
    button:SetScript("OnMouseDown", function(self) self._whole:SetVertexColor(0.7, 0.7, 0.7, 1) end)
    button:SetScript("OnMouseUp", function(self)
        local over = self:IsMouseOver()
        local val = over and 1 or 0.85
        self._whole:SetVertexColor(val, val, val, 1)
    end)
    button:SetScript("OnClick", function(self)
        if GetFFD(self).freeMoveJustDragged then return end
        CludesUI.ToggleGreatVault()
    end)

    -- Resting tint matches OnLeave state
    whole:SetVertexColor(0.85, 0.85, 0.85, 1)

    button._indicatorKey = "_greatVault"

    return button
end

-------------------------------------------------------------------------------
-- M+ Portal button. Identical flyout as Chat sidebar but anchored to minimap.
-------------------------------------------------------------------------------
local _portalFlyout
Inner.portalFlyoutSetters[#Inner.portalFlyoutSetters + 1] = function(val) _portalFlyout = val end

local function ToggleMinimapPortalFlyout(anchorBtn)
    if InCombatLockdown() then return end
    if not _portalFlyout then
        SetPortalFlyout(CludesUI.CreatePortalFlyout({
            name = "CUIMinimap",
            bg = { 0.04, 0.04, 0.06 },
            clamp = true,
            unitEvents = true,
            labelFont = (CludesUI.GetFontPath("minimap")) or "Fonts\\FRIZQT__.TTF",
            labelFlags = "OUTLINE",
        }))
        -- Keep the mouseover stack shown while open; re-evaluate on close so it can hide.
        _portalFlyout:HookScript("OnShow", function()
            if MO_Evaluate then MO_Evaluate() end
        end)
        _portalFlyout:HookScript("OnHide", function()
            if MO_Evaluate then MO_Evaluate() end
        end)
    end
    local flyout = _portalFlyout
    -- Scale to the user's M+ Portals Scale (safe with secure children: combat
    -- early-returns above). Set before the anchor math so GetEffectiveScale reflects it.
    local _mp = SKIN.db and SKIN.db.profile.minimap
    flyout:SetScale(_mp and _mp.extraFlyoutScale or 1.0)
    if flyout:IsShown() then
        flyout:Hide()
    else
        -- Open in the Grow Tooltip/Popup direction. Anchor through UIParent in
        -- effective-scale space so the flyout's own scale never shifts it off the
        -- button. 4px gap on the facing edge; the other axis keeps its top/left edge.
        local bs = anchorBtn:GetEffectiveScale()
        local fontStr = flyout:GetEffectiveScale()
        local bTop = anchorBtn:GetTop() * bs
        local bBottom = anchorBtn:GetBottom() * bs
        local bLeft = anchorBtn:GetLeft() * bs
        local bRight = anchorBtn:GetRight() * bs
        local direction = SKIN._Grow.Dir()
        flyout:ClearAllPoints()
        if direction == "right" then
            flyout:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", (bRight + 4) / fontStr, (bTop + 4) / fontStr)
        elseif direction == "up" then
            flyout:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", (bLeft - 4) / fontStr, (bTop + 4) / fontStr)
        elseif direction == "down" then
            flyout:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", (bLeft - 4) / fontStr, (bBottom - 4) / fontStr)
        else
            flyout:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", (bLeft - 4) / fontStr, (bTop + 4) / fontStr)
        end
        flyout._toggle = anchorBtn
        flyout:Show()
    end
end

local function SizePortalBtn(button, showBg)
    local btnSz = GetInteractableBtnSize()
    button:SetSize(btnSz, btnSz)
    if button._bg then button._bg:SetShown(showBg ~= false) end
    local inset = 4
    local avail = btnSz - inset * 2
    button._icon:SetSize(avail, avail)
    button._icon:ClearAllPoints()
    button._icon:SetPoint("CENTER", button, "CENTER", 0, 0)
end

local function CreatePortalBtn(hostFrame)
    local button = CreateFrame("Button", nil, hostFrame)
    button:SetSize(GetInteractableBtnSize(), GetInteractableBtnSize())
    button:SetFrameLevel(hostFrame:GetFrameLevel() + 10)
    button:EnableMouse(true)

    local backdrop = CreateFrame("Frame", nil, button, "BackdropTemplate")
    backdrop:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground" })
    backdrop:SetBackdropColor(0, 0, 0, 0.8)
    backdrop:SetAllPoints(button)
    backdrop:SetFrameLevel(button:GetFrameLevel() - 1)
    button._bg = backdrop

    local iconTex = button:CreateTexture(nil, "ARTWORK")
    iconTex:SetTexture("Interface\\Icons\\Spell_Arcane_PortalDalaran")
    iconTex:SetTexCoord(6 / 64, 58 / 64, 6 / 64, 58 / 64)
    button._icon = iconTex

    SizePortalBtn(button)

    button:SetScript("OnEnter", function(self)
        self._icon:SetVertexColor(1, 1, 1, 1)
        if _portalFlyout and _portalFlyout:IsShown() then return end
        CludesUI.ShowWidgetTooltip(
            self,
            "M+ Portals",
            { anchor = SKIN._Grow.TT(), scale = GetCustomTooltipScale() }
        )
    end)
    button:SetScript("OnLeave", function(self)
        self._icon:SetVertexColor(0.85, 0.85, 0.85, 1)
        CludesUI.HideWidgetTooltip()
    end)
    button:SetScript("OnMouseDown", function(self) self._icon:SetVertexColor(0.7, 0.7, 0.7, 1) end)
    button:SetScript("OnMouseUp", function(self)
        local over = self:IsMouseOver()
        local val = over and 1 or 0.85
        self._icon:SetVertexColor(val, val, val, 1)
    end)
    button:SetScript("OnClick", function(self)
        if GetFFD(self).freeMoveJustDragged then return end
        CludesUI.HideWidgetTooltip(true)
        ToggleMinimapPortalFlyout(self)
    end)

    iconTex:SetVertexColor(0.85, 0.85, 0.85, 1)

    button._indicatorKey = "_portals"

    return button
end

Inner._customIndicators, Inner.CreateGreatVaultBtn = _customIndicators, CreateGreatVaultBtn
Inner.CreateIndicatorBtn, Inner.CreatePortalBtn = CreateIndicatorBtn, CreatePortalBtn
Inner.HideVaultTooltip, Inner.INDICATOR_ATLAS_OFFSET = HideVaultTooltip, INDICATOR_ATLAS_OFFSET
Inner.INDICATOR_ATLAS_RATIO, Inner.INDICATOR_ATLAS_SCALE = INDICATOR_ATLAS_RATIO, INDICATOR_ATLAS_SCALE
Inner.ShowVaultTooltip, Inner.SizeGreatVaultBtn = ShowVaultTooltip, SizeGreatVaultBtn
Inner.SizePortalBtn = SizePortalBtn
Inner.broken = false
