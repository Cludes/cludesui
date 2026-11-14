if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-- Nine-point picking lives on movers; gameplay frames receive no mouse hooks.
local _, mod = ...
mod = mod.__cuiCoreNS or mod
mod.unlockParts = mod.unlockParts or {}
mod.unlockParts.PointPicker = function(LM)
    local PA = mod.PointAnchors
    local visuals = mod.PointVisuals
    LM.PointVisuals = visuals
    local picker = {}
    LM.PointPicker = picker
    local sourceSet, targetSet, sourcePoint

    local function Enabled()
        return CludesUIDB and CludesUIDB.unlockPointHandles == true
    end

    local function Reject(mover, message)
        LM.FlashRedBorder(mover)
        LM.RejectH.ShowTooltip(message)
    end

    local function Eligible(mover, source)
        if not mover or not mover:IsShown() or mover._tempHidden then
            return false
        end
        local key = mover._barKey
        local elem = LM.registeredElements[key]
        if not elem or CludesUI.IsScreenEdgeKey(key) then
            return false
        end
        if source then
            if elem.noAnchorTo or elem.ownsPosition or mod.IsMoverPosLocked(key) then
                return false
            end
            if elem.isAnchored and elem.isAnchored(key) then
                return false
            end
        elseif elem.noAnchorTarget then
            return false
        end
        return PA.Rect(key, LM.GetBarFrame(key)) ~= nil
    end

    local function FrameDependsOn(widget, wanted, seen, depth)
        if widget == wanted then
            return true
        end
        if not widget or widget == UIParent or seen[widget] then
            return false
        end
        if depth > 30 then
            return true
        end
        seen[widget] = true
        local success, total = pcall(widget.GetNumPoints, widget)
        if not success or (issecretvalue and issecretvalue(total)) or type(total) ~= "number" then
            return true
        end
        for idx = 1, total do
            local plain, _, relative = pcall(widget.GetPoint, widget, idx)
            if not plain or (issecretvalue and issecretvalue(relative)) then
                return true
            end
            if relative and FrameDependsOn(relative, wanted, seen, depth + 1) then
                return true
            end
        end
        return false
    end

    local function CanLink(source, targetUnit)
        if not Eligible(source, true) or not Eligible(targetUnit, false) then
            return false
        end
        local childKey, targetKey = source._barKey, targetUnit._barKey
        local childFrame = LM.GetBarFrame(childKey)
        if childKey == targetKey or FrameDependsOn(LM.GetBarFrame(targetKey), childFrame, {}, 0) then
            return false
        end
        local seen, stack = {}, { targetKey }
        while #stack > 0 do
            local key = table.remove(stack)
            if key == childKey or LM.GetBarFrame(key) == childFrame then
                return false
            end
            if not seen[key] then
                seen[key] = true
                local details = LM.GetAnchorInfo(key)
                if details and details.target then
                    stack[#stack + 1] = details.target
                end
                if details and details.fallback and details.fallback.target then
                    stack[#stack + 1] = details.fallback.target
                end
                local overrides = CludesUI._OverrideAnchorTargets and CludesUI._OverrideAnchorTargets(key)
                if overrides then
                    for idx = 1, #overrides do
                        stack[#stack + 1] = overrides[idx]
                    end
                end
            end
        end
        return true
    end

    local function UpdateDot(btnFrame, animate)
        local dim = (btnFrame.hovered or btnFrame.selected) and btnFrame.hoverSize or btnFrame.idleSize
        local current = btnFrame.art:GetWidth()
        if animate and btnFrame.animation:IsPlaying() then
            local progress = btnFrame.scaleAnimation:GetSmoothProgress()
            current = btnFrame.fromSize + (btnFrame.toSize - btnFrame.fromSize) * progress
        end
        btnFrame.animation:Stop()
        visuals.SizeDot(btnFrame.art, dim)
        visuals.ColorDot(btnFrame.art, (btnFrame.hovered or btnFrame.selected) and 1 or 0.8)
        if animate and math.abs(current - dim) > 0.01 then
            btnFrame.fromSize, btnFrame.toSize = current, dim
            btnFrame.scaleAnimation:SetScaleFrom(current / dim, current / dim)
            btnFrame.animation:Play()
        end
    end

    local function Choose(group, anchorPoint)
        if not LM.isUnlocked or InCombatLockdown() or not Enabled() then
            return
        end
        local source = LM.pickModeMover
        if group == sourceSet and LM.pickMode == "anchorTo" then
            if not Eligible(source, true) then
                LM.CancelPickMode()
                return
            end
            sourcePoint = anchorPoint
            LM.pickMode = "pointAnchor"
            for _, btnFrame in ipairs(sourceSet.buttons) do
                btnFrame.selected = btnFrame.point == anchorPoint
                UpdateDot(btnFrame, false)
                btnFrame:SetShown(btnFrame.point == anchorPoint)
                btnFrame:EnableMouse(false)
            end
            if source._showPickText then
                source._showPickText(CludesUI.L("Click a point on another element"))
            end
            return
        end
        if group ~= targetSet or LM.pickMode ~= "pointAnchor" or not sourcePoint then
            return
        end
        local targetUnit = group.mover
        if not CanLink(source, targetUnit) then
            Reject(
                targetUnit,
                CludesUI.L("This point anchor is unavailable or would create a circular anchor")
            )
            return
        end
        local childKey, targetKey = source._barKey, targetUnit._barKey
        local details = {
            mode = "POINT",
            target = targetKey,
            sourcePoint = sourcePoint,
            targetPoint = anchorPoint,
            offsetX = 0,
            offsetY = 0,
        }
        if not PA.Center(childKey, LM.GetBarFrame(childKey), details, LM.GetBarFrame(targetKey)) then
            Reject(targetUnit, CludesUI.L("This element's position is not available yet"))
            return
        end
        LM.CancelPickMode()
        LM.SetAnchorInfo(childKey, targetKey, nil, 0, 0)
        local stored = LM.GetAnchorInfo(childKey)
        stored.mode, stored.sourcePoint, stored.targetPoint =
            "POINT", details.sourcePoint, details.targetPoint
        stored.edge = nil -- An explicit point owns both axes of the new relationship.
        LM.hasChanges = true
        LM.ApplyAnchorPosition(childKey, targetKey)
        if source.RefreshAnchoredText then
            source:RefreshAnchoredText()
        end
        LM.DeferMoverSync(source, function(m)
            m:Sync()
        end, LM.GetBarFrame(childKey))
        C_Timer.After(0, function()
            LM.PropagateAnchorChain(childKey)
        end)
    end

    local function Layout(group)
        local wid, hgt = group:GetSize()
        local px = LM.PP.perfect / group:GetEffectiveScale()
        local hit = math.max(px, math.min(12 * px, wid / 3, hgt / 3))
        local idle, hover = math.min(visuals.idleSize * px, hit), visuals.hoverSize * px
        for _, btnFrame in ipairs(group.buttons) do
            btnFrame:SetSize(hit, hit)
            if btnFrame.idleSize ~= idle or btnFrame.hoverSize ~= hover then
                btnFrame.idleSize, btnFrame.hoverSize = idle, hover
                UpdateDot(btnFrame, false)
            end
        end
    end

    local function CreateSet()
        local group = CreateFrame("Frame", nil, LM.unlockFrame)
        group:EnableMouse(false)
        group.buttons = {}
        local labels = {
            TOPLEFT = CludesUI.L("Top Left"),
            TOP = CludesUI.L("Top"),
            TOPRIGHT = CludesUI.L("Top Right"),
            LEFT = CludesUI.L("Left"),
            CENTER = CludesUI.L("Center"),
            RIGHT = CludesUI.L("Right"),
            BOTTOMLEFT = CludesUI.L("Bottom Left"),
            BOTTOM = CludesUI.L("Bottom"),
            BOTTOMRIGHT = CludesUI.L("Bottom Right"),
        }
        for _, anchorPoint in ipairs(PA.order) do
            local btnFrame = CreateFrame("Button", nil, group)
            btnFrame.point = anchorPoint
            btnFrame.idleSize, btnFrame.hoverSize = visuals.idleSize, visuals.hoverSize
            btnFrame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            local art = visuals.CreateDot(btnFrame)
            visuals.SizeDot(art, visuals.idleSize)
            art:SetPoint("CENTER", btnFrame, "CENTER")
            btnFrame.art = art
            visuals.ColorDot(art, 0.8)
            btnFrame.dot = art.fill
            btnFrame.animation = art:CreateAnimationGroup()
            btnFrame.scaleAnimation = btnFrame.animation:CreateAnimation("Scale")
            btnFrame.scaleAnimation:SetOrigin("CENTER", 0, 0)
            btnFrame.scaleAnimation:SetDuration(0.12)
            btnFrame.scaleAnimation:SetSmoothing("OUT")
            btnFrame.scaleAnimation:SetScaleTo(1, 1)
            btnFrame:SetScript("OnEnter", function()
                btnFrame.hovered = true
                group.mover._pointHandleHovered = btnFrame
                UpdateDot(btnFrame, true)
                CludesUI.ShowWidgetTooltip(btnFrame, labels[anchorPoint])
            end)
            btnFrame:SetScript("OnLeave", function()
                btnFrame.hovered = nil
                if group.mover._pointHandleHovered == btnFrame then
                    group.mover._pointHandleHovered = nil
                end
                UpdateDot(btnFrame, true)
                CludesUI.HideWidgetTooltip()
                local leave = group.mover:GetScript("OnLeave")
                if leave then
                    leave(group.mover)
                else
                    picker.Leave(group.mover)
                end
            end)
            btnFrame:SetScript("OnHide", function()
                if btnFrame.hovered then
                    CludesUI.HideWidgetTooltip()
                end
                if group.mover and group.mover._pointHandleHovered == btnFrame then
                    group.mover._pointHandleHovered = nil
                end
                btnFrame.hovered, btnFrame.selected = nil, nil
                UpdateDot(btnFrame, false)
            end)
            btnFrame:SetScript("OnClick", function(_, mouse)
                CludesUI.HideWidgetTooltip()
                if mouse == "RightButton" then
                    LM.CancelPickMode()
                else
                    Choose(group, anchorPoint)
                end
            end)
            group.buttons[#group.buttons + 1] = btnFrame
        end
        group:SetScript("OnSizeChanged", Layout)
        return group
    end

    local function Show(group, mover)
        if group.mover ~= mover then
            group:Hide()
        end
        group.mover = mover
        group:SetParent(mover)
        visuals.RaiseAboveMover(group, mover)
        group:ClearAllPoints()
        group:SetAllPoints(mover)
        Layout(group)
        for _, btnFrame in ipairs(group.buttons) do
            -- Bind after the pooled set has bounds, avoiding unresolved corner handles.
            btnFrame:ClearAllPoints()
            btnFrame:SetPoint("CENTER", group, btnFrame.point, 0, 0)
            local selected = group == sourceSet and btnFrame.point == sourcePoint
            if btnFrame.selected ~= selected then
                btnFrame.selected = selected
                UpdateDot(btnFrame, false)
            end
            btnFrame:SetShown(group ~= sourceSet or not sourcePoint or btnFrame.point == sourcePoint)
            btnFrame:EnableMouse(group ~= sourceSet or not sourcePoint)
        end
        group:Show()
    end

    function picker.Point(mover, anchorPoint)
        -- Mover bounds already include visual insets and hover expansion.
        return PA.Point(nil, mover, anchorPoint)
    end

    function picker.Begin(mover)
        if not Enabled() or not Eligible(mover, true) then
            return
        end
        sourceSet = sourceSet or CreateSet()
        sourcePoint = nil
        Show(sourceSet, mover)
    end

    function picker.Enter(mover)
        if LM.pickMode ~= "pointAnchor" or not sourcePoint or mover == LM.pickModeMover then
            return
        end
        if not Eligible(mover, false) then
            if targetSet then
                targetSet:Hide()
            end
            return
        end
        targetSet = targetSet or CreateSet()
        Show(targetSet, mover)
    end

    function picker.Leave(mover)
        if not targetSet or targetSet.mover ~= mover or not targetSet:IsShown() then
            return
        end
        -- Let the next mouse focus settle when crossing onto an edge handle.
        C_Timer.After(0, function()
            if targetSet.mover == mover and not mover:IsMouseOver() and not mover._pointHandleHovered then
                targetSet:Hide()
            end
        end)
    end

    function picker.Refresh(mover)
        if not LM.isUnlocked or not LM.pickMode then
            return
        end
        if sourceSet and sourceSet.mover == mover and sourceSet:IsShown() then
            Show(sourceSet, mover)
        end
        if targetSet and targetSet.mover == mover and targetSet:IsShown() then
            Show(targetSet, mover)
        end
    end

    function picker.BodyClick(mover, btnFrame)
        if LM.pickMode ~= "pointAnchor" or btnFrame ~= "LeftButton" then
            return false
        end
        if mover == LM.pickModeMover then
            LM.CancelPickMode()
        end
        return true
    end

    function picker.Cancel()
        if sourceSet and sourceSet:IsShown() then
            CludesUI.HideWidgetTooltip()
        end
        if sourceSet then
            sourceSet:Hide()
        end
        if targetSet then
            targetSet:Hide()
        end
        sourcePoint = nil
    end

    function picker.Active()
        return sourceSet and sourceSet:IsShown()
    end

    PA.cancelPicker = function()
        if picker.Active() then
            LM.CancelPickMode()
        end
    end
end
