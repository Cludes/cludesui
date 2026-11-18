if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUIBlizzardSkin_GreatVault.lua
--  Great Vault reskin.
-------------------------------------------------------------------------------
local ADDON_NAME, mod = ...
local LOCK_TEXTURE = "Interface\\LFGFrame\\UI-LFG-ICON-LOCK"

-- External weak-keyed lookup table for frame state (prevents tainting Blizzard frames)
local FFD, GetFFD = CludesUI.NewFrameData()

-------------------------------------------------------------------------------
--  Config / Theme Access
-------------------------------------------------------------------------------
local DEFAULT_RESKIN = {
    BG_R = 0.03,
    BG_G = 0.045,
    BG_B = 0.05,
    QT_ALPHA = 0.96,
    BRD_ALPHA = 0.4,
}

local STYLE = {
    paddings = {
        inset = 3,
        activityCard = 4,
        concessionCard = 6,
        icon = 2,
    },
    sizes = {
        itemName = 10,
        threshold = 10,
        progress = 11,
        overlayTitle = 18,
        overlayText = 11,
        warningText = 10,
        headerTitle = 14,
        progressBarHeight = 3,
        lockIcon = 28,
    },
    offsets = {
        progressBar = { x = 0, y = 0 },
        lockIcon = { x = 0, y = -7 },
        selectRewardButton = { x = 0, y = -4 },
    },
    alpha = {
        selectedGlow = 0.08,
        overlayText = 0.9,
        warningText = 0.85,
        progressRewardFill = 0.95,
        progressUnlockedFill = 0.7,
        progressRewardTrack = 0.16,
        progressUnlockedTrack = 0.12,
        progressLockedTrack = 0.10,
        thresholdUnlocked = 0.92,
        thresholdLocked = 0.65,
        progressUnlockedText = 0.9,
        rewardsLabel = 0.75,
        itemName = 0.95,
    },
    colors = {
        white = { r = 1, g = 1, b = 1 },
        itemSlotBackground = { r = 0.5, g = 0.5, b = 0.5, a = 0.7 },
        itemDefaultBorder = { r = 0.4, g = 0.4, b = 0.4, a = 1 },
        progressInactive = { r = 0.55, g = 0.55, b = 0.55, a = 1 },
        complete = { r = 0.176, g = 0.796, b = 0.349 },
        locked = { r = 0.812, g = 0.592, b = 0.212, a = 1 },
        typeName = { r = 0.812, g = 0.592, b = 0.212 },
    },
}

local function IsGreatVaultSkinEnabled()
    -- Own toggle (default on), but like every window it honors the profile's
    -- Window Skins kill switch: both resolve to "off" here.
    return CludesUI.GetBlizzWindowStyle("greatvault") ~= "off"
end

local function BuildThemeContext()
    local region, g, button = CludesUI.GetAccentColor()
    return {
        accent = { r = region, g = g, b = button },
        borderAPI = CludesUI.PP or CludesUI.PanelPP,
        fontPath = CludesUI.GetFontPath("blizzardSkin") or STANDARD_TEXT_FONT,
        reskin = CludesUI.RESKIN or DEFAULT_RESKIN,
    }
end

-------------------------------------------------------------------------------
--  Low-Level Skin Primitives
-------------------------------------------------------------------------------
local function ApplyColorTexture(texture, color, alpha)
    if not texture or not color then
        return
    end
    texture:SetColorTexture(color.r or 1, color.g or 1, color.b or 1, alpha or color.a or 1)
end

local function SetBorderColor(widget, theme, color, alpha)
    local pp = theme and theme.borderAPI
    if pp and pp.SetBorderColor and widget and color then
        pp.SetBorderColor(widget, color.r or 1, color.g or 1, color.b or 1, alpha or color.a or 1)
    end
end

local function StripTexture(texture)
    if texture and texture.SetAlpha and not texture._cuiOwned then
        texture:SetAlpha(0)
    end
end

local function SuppressTexture(texture)
    if not texture or texture._cuiOwned then
        return
    end
    local skinData = GetFFD(texture)
    if skinData.suppressed then
        return
    end
    skinData.suppressed = true

    if texture.Hide then
        texture:Hide()
    end
    if texture.SetAlpha then
        texture:SetAlpha(0)
    end

    if texture.Show then
        hooksecurefunc(texture, "Show", function(self)
            self:Hide()
            self:SetAlpha(0)
        end)
    end
end

local function ApplyFont(fontString, theme, size, region, g, button, a, flags)
    if not fontString then
        return
    end

    CludesUI.PrimeFontShadow(fontString, true)
    fontString:SetFont((theme and theme.fontPath) or STANDARD_TEXT_FONT, size, flags or "")
    fontString:SetTextColor(region or 1, g or 1, button or 1, a or 1)
end

local function EnsureBackdrop(widget, theme, alpha)
    if not widget then
        return
    end

    local rs = theme.reskin
    local skinData = GetFFD(widget)
    if not skinData.bg then
        skinData.bg = widget:CreateTexture(nil, "BACKGROUND", nil, -8)
        skinData.bg:SetAllPoints()
        skinData.bg._cuiOwned = true
    end

    skinData.bg:SetColorTexture(rs.BG_R, rs.BG_G, rs.BG_B, alpha or rs.QT_ALPHA)
    skinData.bg:Show()

    local pp = theme.borderAPI
    if pp and pp.CreateBorder and not skinData.borderCreated then
        skinData.borderCreated = true
        pp.CreateBorder(widget, 1, 1, 1, rs.BRD_ALPHA, 1, "OVERLAY", 7)
    end
end

local function EnsureInsetBackdrop(widget, theme, padding)
    if not widget then
        return nil
    end

    local pad = padding or STYLE.paddings.inset
    local pp = theme.borderAPI
    local skinData = GetFFD(widget)

    if not skinData.skinFrame then
        local skinFrame = CreateFrame("Frame", nil, widget)
        skinData.skinFrame = skinFrame
    end

    local skinFrame = skinData.skinFrame
    skinFrame:ClearAllPoints()
    skinFrame:SetPoint("TOPLEFT", widget, "TOPLEFT", pad, -pad)
    skinFrame:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", -pad, pad)
    skinFrame:SetFrameLevel(math.max(1, widget:GetFrameLevel()))

    if pp and pp.CreateBorder and not skinFrame._cuiBorderCreated then
        skinFrame._cuiBorderCreated = true
        pp.CreateBorder(skinFrame, 1, 1, 1, theme.reskin.BRD_ALPHA, 1, "OVERLAY", 7)
    end

    skinFrame:Show()
    return skinFrame
end

local function EnsureSelectionGlow(widget, anchorFrame)
    if not widget then
        return nil
    end

    local skinData = GetFFD(widget)
    if not skinData.selectedGlow then
        local glow = widget:CreateTexture(nil, "ARTWORK", nil, -5)
        glow._cuiOwned = true
        glow:Hide()
        skinData.selectedGlow = glow
    end

    local glow = skinData.selectedGlow
    local anchor = anchorFrame or widget
    glow:ClearAllPoints()
    glow:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
    glow:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 0, 0)
    return glow
end

local function EnsureProgressBar(widget, anchorFrame)
    if not widget then
        return nil
    end

    local skinData = GetFFD(widget)
    if not skinData.progressBarFrame then
        local barFrame = CreateFrame("Frame", nil, widget)
        local track = barFrame:CreateTexture(nil, "BACKGROUND", nil, -4)
        local fillTex = barFrame:CreateTexture(nil, "ARTWORK", nil, -3)

        track:SetAllPoints()
        track._cuiOwned = true
        fillTex:SetPoint("TOPLEFT", barFrame, "TOPLEFT", 0, 0)
        fillTex:SetPoint("BOTTOMLEFT", barFrame, "BOTTOMLEFT", 0, 0)
        fillTex._cuiOwned = true

        barFrame._cuiTrack = track
        barFrame._cuiFill = fillTex
        barFrame:SetScript("OnSizeChanged", function(self)
            if self._cuiFill then
                local ratio = self._cuiRatio or 0
                local width = math.max(0, self:GetWidth() * ratio)
                self._cuiFill:SetWidth(width)
                self._cuiFill:SetShown(width > 0)
            end
        end)

        skinData.progressBarFrame = barFrame
    end

    local barFrame = skinData.progressBarFrame
    local anchor = anchorFrame or widget
    local pp = CludesUI.PP or CludesUI.PanelPP
    local pixel = pp and pp.Scale and pp.Scale(1) or 1
    barFrame:ClearAllPoints()
    barFrame:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", pixel, pixel)
    barFrame:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -pixel, pixel)
    barFrame:SetHeight(STYLE.sizes.progressBarHeight)
    return barFrame
end

local function EnsureLockIcon(widget, anchorFrame)
    if not widget then
        return nil
    end

    local skinData = GetFFD(widget)
    if not skinData.lockIcon then
        local lock = widget:CreateTexture(nil, "OVERLAY", nil, 3)
        lock:SetTexture(LOCK_TEXTURE)
        lock._cuiOwned = true
        skinData.lockIcon = lock
    end

    local lock = skinData.lockIcon
    local anchor = anchorFrame or widget
    lock:SetSize(STYLE.sizes.lockIcon, STYLE.sizes.lockIcon)
    lock:ClearAllPoints()
    lock:SetPoint("CENTER", anchor, "CENTER", STYLE.offsets.lockIcon.x, STYLE.offsets.lockIcon.y)
    lock:SetVertexColor(1, 1, 1, 1)
    return lock
end

local function ResolveWeeklyRewardItemLink(activityFrame, itemFrame)
    -- displayedItemDBID is the reward Blizzard actually shows (best quality,
    -- keystones skipped); it is set asynchronously by SetDisplayedItem.
    local getLink = C_WeeklyRewards and C_WeeklyRewards.GetItemHyperlink
    if not getLink then
        return nil
    end

    if itemFrame and itemFrame.displayedItemDBID then
        local itemLink = getLink(itemFrame.displayedItemDBID)
        if itemLink and itemLink ~= "" then
            return itemLink
        end
    end

    local details = activityFrame and activityFrame.info
    local rewards = details and details.rewards
    if type(rewards) ~= "table" then
        return nil
    end

    for _, reward in ipairs(rewards) do
        if reward and reward.itemDBID then
            local itemLink = getLink(reward.itemDBID)
            if itemLink and itemLink ~= "" then
                return itemLink
            end
        end
    end

    return nil
end

local function ResolveItemBorderColor(itemLink)
    if not itemLink then
        return STYLE.colors.itemDefaultBorder
    end

    -- C_Item.GetItemInfo reads the link (bonus-modified quality); ByID reads the base item.
    local _, _, quality = C_Item.GetItemInfo(itemLink)
    if not quality and C_Item and C_Item.GetItemQualityByID then
        quality = C_Item.GetItemQualityByID(itemLink)
    end

    if quality then
        local region, g, button
        if C_Item and C_Item.GetItemQualityColor then
            region, g, button = C_Item.GetItemQualityColor(quality)
        elseif GetItemQualityColor then
            region, g, button = GetItemQualityColor(quality)
        end
        if region and g and button then
            return { r = region, g = g, b = button, a = 1 }
        end
    end

    return STYLE.colors.itemDefaultBorder
end

local function EnsureIconChrome(itemFrame, theme, borderColor)
    if not itemFrame or not itemFrame.Icon then
        return
    end

    local iconTex = itemFrame.Icon
    local pad = STYLE.paddings.icon
    local pp = theme.borderAPI
    local skinData = GetFFD(itemFrame)

    if not skinData.iconBg then
        local backdrop = itemFrame:CreateTexture(nil, "BACKGROUND", nil, -6)
        backdrop._cuiOwned = true
        skinData.iconBg = backdrop
    end

    skinData.iconBg:ClearAllPoints()
    skinData.iconBg:SetPoint("TOPLEFT", iconTex, "TOPLEFT", -pad, pad)
    skinData.iconBg:SetPoint("BOTTOMRIGHT", iconTex, "BOTTOMRIGHT", pad, -pad)
    ApplyColorTexture(skinData.iconBg, STYLE.colors.itemSlotBackground)

    if not skinData.iconBorder then
        local borderHost = CreateFrame("Frame", nil, itemFrame)
        skinData.iconBorder = borderHost

        if pp and pp.CreateBorder then
            pp.CreateBorder(borderHost, 1, 1, 1, 1, 2, "OVERLAY", 7)
        end
    end

    local borderHost = skinData.iconBorder
    borderHost:ClearAllPoints()
    borderHost:SetPoint("TOPLEFT", iconTex, "TOPLEFT", -pad, pad)
    borderHost:SetPoint("BOTTOMRIGHT", iconTex, "BOTTOMRIGHT", pad, -pad)
    borderHost:SetFrameLevel(itemFrame:GetFrameLevel() + 1)
    SetBorderColor(borderHost, theme, borderColor or STYLE.colors.itemDefaultBorder, 1)

    return borderHost
end

local function SuppressItemButtonChrome(itemFrame)
    if not itemFrame then
        return
    end

    for _, key in ipairs({
        "Border",
        "Background",
        "IconBorder",
        "IconOverlay",
        "IconOverlay2",
        "SlotBackground",
        "Highlight",
        "Glow",
        "NormalTexture",
        "PushedTexture",
    }) do
        SuppressTexture(itemFrame[key])
    end

    if itemFrame.GetNormalTexture then
        SuppressTexture(itemFrame:GetNormalTexture())
    end
    if itemFrame.GetPushedTexture then
        SuppressTexture(itemFrame:GetPushedTexture())
    end
    if itemFrame.GetHighlightTexture then
        SuppressTexture(itemFrame:GetHighlightTexture())
    end

    local regionList = { itemFrame:GetRegions() }
    for idx = 1, #regionList do
        local regionFrame = regionList[idx]
        if
            regionFrame
            and regionFrame:IsObjectType("Texture")
            and regionFrame ~= itemFrame.Icon
            and not regionFrame._cuiOwned
        then
            SuppressTexture(regionFrame)
        end
    end
end

local function ApplyStoredAnchorOffset(widget, cacheKey, offsetX, offsetY)
    if not widget then
        return
    end

    local skinData = GetFFD(widget)
    local appliedOffsetKey = cacheKey .. "AppliedOffset"
    local appliedOffset = skinData[appliedOffsetKey] or { x = 0, y = 0 }
    local cachedPoints = {}

    for idx = 1, widget:GetNumPoints() do
        local anchorPoint, relativeTo, relativePoint, xOfs, yOfs = widget:GetPoint(idx)
        cachedPoints[idx] = {
            point = anchorPoint,
            relativeTo = relativeTo,
            relativePoint = relativePoint,
            x = (xOfs or 0) - appliedOffset.x,
            y = (yOfs or 0) - appliedOffset.y,
        }
    end

    skinData[cacheKey] = cachedPoints
    skinData[appliedOffsetKey] = { x = offsetX or 0, y = offsetY or 0 }

    if #cachedPoints == 0 then
        return
    end

    widget:ClearAllPoints()
    for _, anchor in ipairs(cachedPoints) do
        widget:SetPoint(
            anchor.point,
            anchor.relativeTo,
            anchor.relativePoint,
            (anchor.x or 0) + (offsetX or 0),
            (anchor.y or 0) + (offsetY or 0)
        )
    end
end

-------------------------------------------------------------------------------
--  Component Stylers
-------------------------------------------------------------------------------
local function RefreshButtonState(btnFrame)
    if not btnFrame then
        return
    end
    -- Engine button treatment: flat theme block, 1px border, white hover, and
    -- a label that mirrors the enabled/disabled state. Idempotent, so calling
    -- it from every refresh pass is free after the first.
    local Skin = mod.WSkin
    if not Skin or not Skin.Button then
        return
    end
    Skin.Button(btnFrame)
    Skin.StateButtonLabel(btnFrame)
    -- Fully opaque fill: the engine block carries the theme backdrop's
    -- translucency, which reads washed out over the vault scene.
    local skinData = Skin.GetFFD and Skin.GetFFD(btnFrame)
    local theme = Skin.Theme
    if skinData and skinData.bg and theme then
        skinData.bg:SetColorTexture(theme.bgR or 0, theme.bgG or 0, theme.bgB or 0, 1)
    end
end

local function RefreshTypeFrameState(widget, theme)
    if not widget then
        return
    end
    if widget.Name then
        local c = STYLE.colors.typeName
        widget.Name:SetTextColor(c.r, c.g, c.b, 1)

        local skinData = GetFFD(widget)
        if not skinData.nameRaised then
            skinData.nameRaised = true
            local raiseFrame = CreateFrame("Frame", nil, widget)
            raiseFrame:SetAllPoints()
            raiseFrame:SetFrameLevel(widget:GetFrameLevel() + 20)
            widget.Name:SetParent(raiseFrame)
        end
    end
end

local function RefreshActivityItemState(itemFrame, activityFrame, theme)
    if not itemFrame then
        return
    end

    SuppressItemButtonChrome(itemFrame)

    if itemFrame.Icon then
        itemFrame.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    end

    local itemLink = ResolveWeeklyRewardItemLink(activityFrame, itemFrame)
    local borderColor = ResolveItemBorderColor(itemLink)
    EnsureIconChrome(itemFrame, theme, borderColor)

    -- Blizzard resolves the displayed reward asynchronously (ContinueOnLoad ->
    -- SetDisplayedItem), often after our refresh pass; recolor on that edge.
    local skinData = GetFFD(itemFrame)
    if not skinData.displayHooked and itemFrame.SetDisplayedItem then
        skinData.displayHooked = true
        hooksecurefunc(itemFrame, "SetDisplayedItem", function(self)
            if not IsGreatVaultSkinEnabled() then
                return
            end
            local owner = GetFFD(self).iconBorder
            if not owner then
                return
            end
            local link = ResolveWeeklyRewardItemLink(self:GetParent(), self)
            SetBorderColor(owner, BuildThemeContext(), ResolveItemBorderColor(link), 1)
        end)
    end

    if itemFrame.Name then
        ApplyFont(itemFrame.Name, theme, STYLE.sizes.itemName, 1, 1, 1, STYLE.alpha.itemName)
    end
end

local function GetProgressTextColor(progress, threshold)
    if not progress or not threshold or threshold <= 0 or progress <= 0 then
        return STYLE.colors.progressInactive
    end
    return STYLE.colors.locked
end

local function GetActivityState(widget, selectedActivity)
    local hasRewards = widget and widget.hasRewards or false
    local progress = widget and widget.info and widget.info.progress or 0
    local threshold = widget and widget.info and widget.info.threshold or 0
    local isComplete = hasRewards or (threshold > 0 and progress >= threshold)

    return {
        hasRewards = hasRewards,
        isSelected = selectedActivity and selectedActivity == widget and hasRewards or false,
        isComplete = isComplete,
        progress = progress,
        threshold = threshold,
        ratio = (threshold and threshold > 0) and (progress / threshold) or 0,
        progressColor = GetProgressTextColor(progress, threshold),
    }
end

local function SetActivityProgressBar(widget, ratio, color, alpha, trackAlpha)
    local skinData = GetFFD(widget)
    if not widget or not skinData.progressBarFrame then
        return
    end

    local barFrame = skinData.progressBarFrame
    local clampedRatio = math.max(0, math.min(1, ratio or 0))
    barFrame._cuiRatio = clampedRatio

    if barFrame._cuiTrack then
        barFrame._cuiTrack:SetColorTexture(1, 1, 1, trackAlpha or STYLE.alpha.progressLockedTrack)
    end

    if barFrame._cuiFill then
        ApplyColorTexture(barFrame._cuiFill, color or STYLE.colors.white, alpha or 1)
        local width = math.max(0, barFrame:GetWidth() * clampedRatio)
        barFrame._cuiFill:SetWidth(width)
        barFrame._cuiFill:SetShown(width > 0)
    end
end

local function RefreshSelectableCardState(theme, skinFrame, glow, status)
    if glow then
        ApplyColorTexture(glow, theme.accent, STYLE.alpha.selectedGlow)
        glow:SetShown(status.isSelected and true or false)
    end

    if not skinFrame then
        return
    end

    -- Cards keep the faint inset edge; rarity color lives on the icon border only.
    SetBorderColor(skinFrame, theme, STYLE.colors.white, theme.reskin.BRD_ALPHA)
end

local function RefreshActivityVisualState(widget, selectedActivity, theme)
    if not widget then
        return
    end

    StripTexture(widget.Background)
    if widget.Border then
        local edge = GetFFD(widget.Border)
        if not edge.suppressed then
            edge.suppressed = true
            widget.Border:SetAlpha(0)
            widget.Border:Hide()
            hooksecurefunc(widget.Border, "Show", function(self)
                self:Hide()
                self:SetAlpha(0)
            end)
        else
            widget.Border:SetAlpha(0)
            widget.Border:Hide()
        end
    end
    StripTexture(widget.SelectedTexture)
    StripTexture(widget.ItemGlow)
    if widget.UncollectedGlow then
        local ud = GetFFD(widget.UncollectedGlow)
        if not ud.hidden then
            ud.hidden = true
            local hiddenParent = CreateFrame("Frame")
            hiddenParent:Hide()
            widget.UncollectedGlow:SetParent(hiddenParent)
        end
    end
    if widget.UnselectedFrame then
        widget.UnselectedFrame:SetAlpha(0)
    end

    local skinFrame = EnsureInsetBackdrop(widget, theme, STYLE.paddings.activityCard)
    local glow = EnsureSelectionGlow(widget, skinFrame)
    EnsureProgressBar(widget, skinFrame)
    EnsureLockIcon(widget, skinFrame)

    local activityState = GetActivityState(widget, selectedActivity)
    local complete = STYLE.colors.complete

    RefreshSelectableCardState(theme, skinFrame, glow, {
        isSelected = activityState.isSelected,
    })

    -- Tile background: bottom half for completed, top half for incomplete
    if not skinFrame._cuiTileBg then
        local tbg = skinFrame:CreateTexture(nil, "BACKGROUND", nil, -6)
        tbg:SetAllPoints()
        tbg:SetAtlas("characterupdate_background")
        tbg._cuiOwned = true
        skinFrame._cuiTileBg = tbg
    end
    if activityState.isComplete then
        skinFrame._cuiTileBg:SetTexCoord(0, 1, 0.5, 1)
    else
        skinFrame._cuiTileBg:SetTexCoord(0, 1, 0, 0.5)
    end

    -- Dark overlay: 20% on complete, 40% on incomplete
    if not skinFrame._cuiDarkOverlay then
        local overlayFrame = skinFrame:CreateTexture(nil, "ARTWORK", nil, 2)
        overlayFrame:SetAllPoints()
        overlayFrame:SetColorTexture(0, 0, 0, 1)
        overlayFrame._cuiOwned = true
        skinFrame._cuiDarkOverlay = overlayFrame
    end
    if activityState.isComplete then
        skinFrame._cuiDarkOverlay:SetAlpha(0.2)
    else
        skinFrame._cuiDarkOverlay:SetAlpha(0.4)
    end
    skinFrame._cuiDarkOverlay:Show()

    if activityState.isComplete then
        SetActivityProgressBar(
            widget,
            1,
            complete,
            STYLE.alpha.progressRewardFill,
            STYLE.alpha.progressRewardTrack
        )
    else
        SetActivityProgressBar(
            widget,
            activityState.ratio,
            activityState.progressColor,
            activityState.progressColor.a,
            STYLE.alpha.progressLockedTrack
        )
    end

    local skinData = GetFFD(widget)
    if skinData.lockIcon then
        skinData.lockIcon:SetShown(not activityState.isComplete)
    end

    if widget.Threshold then
        local thresholdAlpha = activityState.isComplete and STYLE.alpha.thresholdUnlocked
            or STYLE.alpha.thresholdLocked
        ApplyFont(widget.Threshold, theme, STYLE.sizes.threshold, 1, 1, 1, thresholdAlpha)
    end

    if widget.Progress then
        if activityState.isComplete then
            -- Grab Blizzard's difficulty text, stripping our ilvl prefix if
            -- we already modified it on a prior pass so it stays current.
            local rawText = widget.Progress:GetText() or ""
            local diffText = rawText:match("^%d+%s*%((.+)%)$") or rawText
            ApplyFont(widget.Progress, theme, STYLE.sizes.progress, complete.r, complete.g, complete.b, 1)

            local details = widget.info
            local ilvl
            if
                details
                and details.id
                and C_WeeklyRewards
                and C_WeeklyRewards.GetExampleRewardItemHyperlinks
            then
                local itemLink = C_WeeklyRewards.GetExampleRewardItemHyperlinks(details.id)
                if itemLink then
                    ilvl = C_Item.GetDetailedItemLevelInfo(itemLink)
                end
            end
            if ilvl then
                widget.Progress:SetText(ilvl .. " (" .. diffText .. ")")
            end
        else
            local progressColor = activityState.progressColor
            ApplyFont(
                widget.Progress,
                theme,
                STYLE.sizes.progress,
                progressColor.r,
                progressColor.g,
                progressColor.b,
                progressColor.a
            )
        end
    end

    if widget.CompletedIcon and activityState.isComplete then
        widget.CompletedIcon:SetAtlas("VAS-icon-checkmark-glw")
        widget.CompletedIcon:SetVertexColor(complete.r, complete.g, complete.b, 1)
        widget.CompletedIcon:SetDrawLayer("OVERLAY", 4)
    end

    if widget.CompletedActivityFlipbook then
        local fieldData = GetFFD(widget.CompletedActivityFlipbook)
        if not fieldData.hidden then
            fieldData.hidden = true
            local hiddenParent = CreateFrame("Frame")
            hiddenParent:Hide()
            fieldData.hiddenParent = hiddenParent
            widget.CompletedActivityFlipbook:SetParent(hiddenParent)
        end
    end

    RefreshActivityItemState(widget.ItemFrame, widget, theme)
end

local function RefreshConcessionVisualState(widget, selectedActivity, theme)
    if not widget then
        return
    end

    StripTexture(widget.Background)
    StripTexture(widget.SelectedTexture)
    StripTexture(widget.Divider1)
    StripTexture(widget.Divider2)
    if widget.UnselectedFrame then
        widget.UnselectedFrame:SetAlpha(0)
    end

    local skinFrame = EnsureInsetBackdrop(widget, theme, STYLE.paddings.concessionCard)
    local glow = EnsureSelectionGlow(widget, skinFrame)

    RefreshSelectableCardState(theme, skinFrame, glow, {
        isSelected = selectedActivity and selectedActivity == widget or false,
    })

    if widget.RewardsFrame then
        if widget.RewardsFrame.Label then
            ApplyFont(
                widget.RewardsFrame.Label,
                theme,
                STYLE.sizes.itemName,
                1,
                1,
                1,
                STYLE.alpha.rewardsLabel
            )
        end
        if widget.RewardsFrame.Text then
            ApplyFont(
                widget.RewardsFrame.Text,
                theme,
                STYLE.sizes.itemName,
                theme.accent.r,
                theme.accent.g,
                theme.accent.b,
                1
            )
        end
    end
end

local function RefreshOverlayState(overlayFrame, theme)
    if not overlayFrame then
        return
    end

    EnsureBackdrop(overlayFrame, theme, 0.97)
    if overlayFrame.Background then
        overlayFrame.Background:SetAlpha(0)
    end
    if overlayFrame.NineSlice then
        overlayFrame.NineSlice:SetAlpha(0)
    end

    if overlayFrame.Title then
        ApplyFont(
            overlayFrame.Title,
            theme,
            STYLE.sizes.overlayTitle,
            theme.accent.r,
            theme.accent.g,
            theme.accent.b,
            1
        )
    end
    if overlayFrame.Text then
        ApplyFont(overlayFrame.Text, theme, STYLE.sizes.overlayText, 1, 1, 1, STYLE.alpha.overlayText)
    end
end

local function RefreshWarningDialogState(widget, theme)
    if not widget then
        return
    end

    EnsureBackdrop(widget, theme, 0.97)
    if widget.NineSlice then
        widget.NineSlice:SetAlpha(0)
    end
    if widget.WarningIcon and widget.WarningIcon.SetDesaturated then
        widget.WarningIcon:SetDesaturated(true)
    end
    if widget.Description then
        ApplyFont(widget.Description, theme, STYLE.sizes.warningText, 1, 1, 1, STYLE.alpha.warningText)
    end
    -- Any standard buttons on the dialog get the engine treatment too
    -- (depth-capped, no-op when there are none).
    if mod.WSkin and mod.WSkin.ButtonsIn then
        mod.WSkin.ButtonsIn(widget)
    end
end

-------------------------------------------------------------------------------
--  Frame Orchestration / Hooks
-------------------------------------------------------------------------------
local RefreshGreatVaultFrame

local function ScheduleGreatVaultRefresh(widget)
    if not widget then
        return
    end
    local skinData = GetFFD(widget)
    if skinData.refreshQueued then
        return
    end

    skinData.refreshQueued = true
    C_Timer.After(0, function()
        skinData.refreshQueued = nil
        if widget and not widget:IsForbidden() then
            RefreshGreatVaultFrame(widget)
        end
    end)
end

RefreshGreatVaultFrame = function(widget)
    if not widget or widget:IsForbidden() or not widget:IsShown() or not IsGreatVaultSkinEnabled() then
        return
    end

    local theme = BuildThemeContext()

    -- Window border: the engine's shared atlas frame, so the vault carries the
    -- same soft-edged border as every other Window Skins pack. The 0.2 darken
    -- wash that tames the vault scene stays, on our own overlay frame.
    local skinData = GetFFD(widget)
    if not skinData.borderOverlay then
        local overlayFrame = CreateFrame("Frame", nil, widget)
        overlayFrame:SetPoint("TOPLEFT", widget, "TOPLEFT", 10, -8)
        overlayFrame:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", -10, 8)
        overlayFrame:SetFrameLevel(widget:GetFrameLevel() + 2)

        local darken = overlayFrame:CreateTexture(nil, "BACKGROUND", nil, 1)
        darken:SetAllPoints()
        darken:SetColorTexture(0, 0, 0, 0.2)
        darken._cuiOwned = true

        skinData.borderOverlay = overlayFrame
    end
    -- The atlas border hangs on the inset overlay, not the frame: the vault frame's
    -- bounds extend ~10px past its visible panel, so a border on the frame itself draws
    -- off the panel edge. At half opacity so it sits back against the vault scene.
    if mod.WSkin and mod.WSkin.AtlasBorder then
        mod.WSkin.AtlasBorder(skinData.borderOverlay)
        local ab = mod.WSkin.GetFFD and mod.WSkin.GetFFD(skinData.borderOverlay).atlasBorderFrame
        if ab then
            ab:SetAlpha(0.65)
        end
    end

    -- Hide Blizzard's border decorations
    SuppressTexture(widget.BorderShadow)
    if widget.BorderContainer then
        local bcd = GetFFD(widget.BorderContainer)
        if not bcd.hidden then
            bcd.hidden = true
            local hiddenParent = CreateFrame("Frame")
            hiddenParent:Hide()
            widget.BorderContainer:SetParent(hiddenParent)
        end
    end

    -- Header adjustments
    if widget.HeaderFrame then
        local hf = widget.HeaderFrame
        local hfd = GetFFD(hf)
        if not hfd.adjusted then
            hfd.adjusted = true

            if hf.Text then
                local anchorPoint, rel, relPoint, posX, posY = hf.Text:GetPoint(1)
                if anchorPoint then
                    hf.Text:ClearAllPoints()
                    hf.Text:SetPoint(anchorPoint, rel, relPoint, posX, (posY or 0) + 30)
                end
                hf.Text:SetFont(theme.fontPath, STYLE.sizes.headerTitle, "")
            end

            if hf.HeaderDivider then
                local hd = hf.HeaderDivider
                local wid = hd:GetWidth()
                local hgt = hd:GetHeight()
                if wid and wid > 0 and hgt and hgt > 0 then
                    hd:SetSize(wid * 0.60, hgt * 0.60)
                end
                local anchorPoint, rel, relPoint, posX, posY = hd:GetPoint(1)
                if anchorPoint then
                    hd:ClearAllPoints()
                    hd:SetPoint(anchorPoint, rel, relPoint, posX, (posY or 0) - 15)
                end
            end
        end
    end

    for _, typeFrame in ipairs({ widget.RaidFrame, widget.MythicFrame, widget.PVPFrame, widget.WorldFrame }) do
        if typeFrame and typeFrame:IsShown() then
            RefreshTypeFrameState(typeFrame, theme)
        end
    end

    local concessionType = Enum
        and Enum.WeeklyRewardChestThresholdType
        and Enum.WeeklyRewardChestThresholdType.Concession
    if widget.Activities then
        for _, activityFrame in ipairs(widget.Activities) do
            if activityFrame.type == concessionType then
                RefreshConcessionVisualState(activityFrame, widget.selectedActivity, theme)
            else
                RefreshActivityVisualState(activityFrame, widget.selectedActivity, theme)
            end
        end
    end

    ApplyStoredAnchorOffset(
        widget.SelectRewardButton,
        "_cuiOriginalPoints",
        STYLE.offsets.selectRewardButton.x,
        STYLE.offsets.selectRewardButton.y
    )
    RefreshButtonState(widget.SelectRewardButton)

    -- Close button: engine primitive, same X glyph and hover as every pack.
    if widget.CloseButton and mod.WSkin and mod.WSkin.CloseButton then
        mod.WSkin.CloseButton(widget.CloseButton)
    end

    RefreshOverlayState(widget.Overlay, theme)
    RefreshWarningDialogState(_G.WeeklyRewardExpirationWarningDialog, theme)
end

local function HookGreatVault()
    local widget = _G.WeeklyRewardsFrame
    if not widget or not IsGreatVaultSkinEnabled() then
        return
    end
    local skinData = GetFFD(widget)
    if skinData.hooked then
        return
    end

    skinData.hooked = true

    -- Window-style system: treat Blizzard's vault scene as this window's CUI
    -- backdrop, so picking Modern fades the scene and shows the flat user
    -- color instead (nil-safe if the scene texture key is absent).
    if mod.WSkin and mod.WSkin.AdoptShell then
        local scene = widget.Background or widget.BackgroundTile
        mod.WSkin.AdoptShell("greatvault", widget, scene)
    end

    widget:HookScript("OnShow", function(self)
        ScheduleGreatVaultRefresh(self)
    end)

    for _, methodName in ipairs({ "Refresh", "UpdateSelection", "SetUpConditionalActivities" }) do
        hooksecurefunc(widget, methodName, function(self)
            ScheduleGreatVaultRefresh(self)
        end)
    end
end

do
    local hookFrame = CreateFrame("Frame")
    hookFrame:RegisterEvent("ADDON_LOADED")
    hookFrame:RegisterEvent("PLAYER_LOGIN")
    hookFrame:SetScript("OnEvent", function(self, _, addon)
        if addon and addon ~= "Blizzard_WeeklyRewards" then
            return
        end

        if
            addon == "Blizzard_WeeklyRewards"
            or (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_WeeklyRewards"))
        then
            HookGreatVault()
            self:UnregisterEvent("ADDON_LOADED")
            self:UnregisterEvent("PLAYER_LOGIN")
        end
    end)
end
