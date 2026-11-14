if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_ActionBars_Unlock.lua
--
--  Bar position save and restore, and the Unlock Mode registration.
--  Loads after CUI_ActionBars_ApplyAll.lua; reads ns._internals.
-------------------------------------------------------------------------------
local _, mod = ...

local ipairs = ipairs
local InCombatLockdown = InCombatLockdown

local ABAR = mod.EAB
local Inner = mod._internals
local BAR_CONFIG, EXTRA_BARS, SHAPE_BTN_EXPAND = Inner.BAR_CONFIG, Inner.EXTRA_BARS, Inner.SHAPE_BTN_EXPAND
local barFrames, BLIZZ_MOVABLE_OVERLAY = Inner.barFrames, Inner.BLIZZ_MOVABLE_OVERLAY
local blizzMovableHolders = Inner.blizzMovableHolders
local LayoutBar = Inner.LayoutBar

-------------------------------------------------------------------------------
--  Position Save/Restore
-------------------------------------------------------------------------------
-- Convert CENTER position to edge for non-CENTER-grow bars (same pattern as CDM).
-- Stored on EAB, not in a file local.
function ABAR:ConvertCenterToEdge(barId, anchorPoint, posX, posY)
    if anchorPoint ~= "CENTER" then
        return anchorPoint, posX, posY
    end
    local conf = self.db and self.db.profile and self.db.profile.bars and self.db.profile.bars[barId]
    local grow = conf and conf.growDirection
    if not grow then
        return anchorPoint, posX, posY
    end
    grow = grow:upper()
    if grow == "CENTER" then
        return anchorPoint, posX, posY
    end
    local widget = barFrames[barId]
    if not widget then
        return anchorPoint, posX, posY
    end
    local fw = widget:GetWidth() or 0
    local fh = widget:GetHeight() or 0
    if grow == "RIGHT" and fw > 0 then
        return "LEFT", posX - fw / 2, posY
    elseif grow == "LEFT" and fw > 0 then
        return "RIGHT", posX + fw / 2, posY
    elseif grow == "DOWN" and fh > 0 then
        return "TOP", posX, posY + fh / 2
    elseif grow == "UP" and fh > 0 then
        return "BOTTOM", posX, posY - fh / 2
    end
    return anchorPoint, posX, posY
end

function ABAR:ConvertEdgeToCenter(barId, place)
    if not place or not place.point then
        return place
    end
    local pt = place.point
    if pt == "CENTER" then
        return place
    end
    if pt ~= "LEFT" and pt ~= "RIGHT" and pt ~= "TOP" and pt ~= "BOTTOM" then
        return place
    end
    local widget = barFrames[barId]
    if not widget then
        return place
    end
    local fw = widget:GetWidth() or 0
    local fh = widget:GetHeight() or 0
    local cx, cy = place.x or 0, place.y or 0
    if pt == "LEFT" then
        cx = cx + fw / 2
    elseif pt == "RIGHT" then
        cx = cx - fw / 2
    elseif pt == "TOP" then
        cy = cy - fh / 2
    elseif pt == "BOTTOM" then
        cy = cy + fh / 2
    end
    return { point = "CENTER", relPoint = place.relPoint, x = cx, y = cy }
end

local function SaveBarPosition(barId)
    local widget = barFrames[barId]
    if not widget then
        return
    end
    local anchorPoint, _, relPoint, posX, posY = widget:GetPoint(1)
    if anchorPoint then
        -- Pixel-perfect snapping can leave sub-pixel offsets (0.5) on
        -- CENTER-anchored bars, and re-snapping on restore drifts 1px at some
        -- UI scales. Clamp near-zero CENTER offsets to exactly 0 so the
        -- restore-skip at RestoreBarPositions fires correctly.
        if anchorPoint == "CENTER" and relPoint == "CENTER" then
            local es = widget:GetEffectiveScale() or 1
            local PPa = CludesUI and CludesUI.PP
            local onePx = PPa and PPa.perfect and (PPa.perfect / es) or 1
            if math.abs(posX) < onePx then
                posX = 0
            end
            if math.abs(posY) < onePx then
                posY = 0
            end
        end
        ABAR.db.profile.barPositions[barId] = {
            point = anchorPoint,
            relPoint = relPoint,
            x = posX,
            y = posY,
        }
    end
end

local function RestoreBarPositions()
    local positions = ABAR.db.profile.barPositions
    if not positions then
        return
    end
    local PPa = CludesUI and CludesUI.PP
    for _, details in ipairs(BAR_CONFIG) do
        local key = details.key
        local place = positions[key]
        local widget = barFrames[key]
        if place and widget then
            -- Skip bars owned by the unlock anchor system: position is computed
            -- from the anchor chain, not saved barPositions.
            local anchored = CludesUI and CludesUI.IsUnlockAnchored and CludesUI.IsUnlockAnchored(key)
            if anchored then
                -- skip: anchor system owns this bar's position
            else
                local pt = place.point or "CENTER"
                local rpt = place.relPoint or pt
                local px = place.x or 0
                local py = place.y or 0
                -- Skip CENTER 0,0: this is never an intentional position.
                -- Anchored bars save 0,0 as a placeholder; their real position
                -- comes from the anchor chain which resolves later.
                if pt == "CENTER" and rpt == "CENTER" and px == 0 and py == 0 then
                -- skip
                else
                    -- Snap to physical pixel grid. For CENTER-anchored bars use
                    -- SnapCenterForDim with the frame's actual size so odd-pixel
                    -- dimensions get the +0.5 center offset they need (plain
                    -- SnapForES drifts by 1px on save & exit for odd dimensions).
                    if PPa then
                        local es = widget:GetEffectiveScale()
                        local isCenterAnchor = (pt == "CENTER" and rpt == "CENTER")
                        if isCenterAnchor and PPa.SnapCenterForDim then
                            px = PPa.SnapCenterForDim(px, widget:GetWidth() or 0, es)
                            py = PPa.SnapCenterForDim(py, widget:GetHeight() or 0, es)
                        elseif PPa.SnapForES then
                            px = PPa.SnapForES(px, es)
                            py = PPa.SnapForES(py, es)
                        end
                    end
                    widget:ClearAllPoints()
                    widget:SetPoint(pt, UIParent, rpt, px, py)
                end
            end -- anchored else
        end
    end
    -- Note: anchored bars are handled later in RegisterWithUnlockMode
    -- (0.5s deferred) via ReapplyOwnAnchor, after elements are registered.
end

-------------------------------------------------------------------------------
--  Unlock Mode Integration
--  Register bars with CUI_UnlockMode for positioning.
-------------------------------------------------------------------------------
local function RegisterWithUnlockMode()
    if not CludesUI or not CludesUI.RegisterUnlockElements then
        return
    end
    local MK = CludesUI.MakeUnlockElement

    local elements = {}
    local orderBase = 200

    for position, details in ipairs(BAR_CONFIG) do
        local key = details.key
        elements[#elements + 1] = MK({
            key = key,
            label = details.label,
            group = "Action Bars",
            order = orderBase + position,
            isHidden = function()
                local s = ABAR.db.profile.bars[details.key]
                if not s then
                    return false
                end
                -- Honor the runtime "Toggle Action Bar" override the same way
                -- RefreshRuntimeVisibility does: a bar saved as Never but
                -- surfaced by the keybind is on screen, so it needs a mover;
                -- a saved-Always bar toggled off does not.
                local shade = ABAR._visOverride and ABAR._visOverride[details.key]
                if shade then
                    return shade == "never"
                end
                return ABAR.VisibilityCompat.IsNever(s) or (ABAR._padHide and s.gamepadHideBar == true)
            end,
            getFrame = function()
                return barFrames[details.key]
            end,
            getSize = function()
                local widget = barFrames[details.key]
                if not widget then
                    return 1, 1
                end
                return widget:GetWidth(), widget:GetHeight()
            end,
            linkedDimensions = true,
            -- Size matching works in every style: stock styles size their buttons
            -- from Icon Size too (LayoutBar scales the native-size button to it),
            -- and the math below uses the same layout shape as LayoutBar.
            -- A textured square border's reach past the bar's edges, so size
            -- matching lines up with what is on screen. The outer buttons sit
            -- flush on the bar frame's edges (LayoutBar: no outer inset), so
            -- the per-button reach is the bar's. Same arguments ApplyBordersForBar
            -- paints with; nil for custom shapes (their ring sits inside the
            -- button), stock looks and non-square icons.
            getMatchPad = function()
                local p = ABAR.db and ABAR.db.profile
                if not (p and p.squareIcons) or mod.AB_Style() ~= "cui" then
                    return nil
                end
                local s = p.bars[details.key]
                if not s then
                    return nil
                end
                local shape = s.buttonShape or "none"
                if shape ~= "none" and shape ~= "cropped" then
                    return nil
                end
                local sz, px = mod.ResolveBorderThickness(s)
                local c = s.borderColor
                return CludesUI.BorderMatchPad(
                    sz,
                    s.borderTexture or "solid",
                    s.borderTextureOffset,
                    s.borderTextureOffsetY,
                    s.borderTextureShiftX,
                    s.borderTextureShiftY,
                    "actionbars",
                    s.borderThickness or "thin",
                    px,
                    nil,
                    c and c.a or 1
                )
            end,
            setWidth = function(_, wid)
                local s = ABAR.db.profile.bars[details.key]
                if not s then
                    return
                end
                -- Reverse-engineer square button size from total bar width
                -- using physical pixel math to distribute remainder pixels.
                local numIcons = s.overrideNumIcons or s.numIcons or details.count
                local numRows = s.overrideNumRows or s.numRows or 1
                if numRows < 1 then
                    numRows = 1
                end
                local stride = math.ceil(numIcons / numRows)
                if stride < 1 then
                    stride = 1
                end
                local isVert = (s.orientation == "vertical")
                local pad = s.buttonPadding or 2
                local shape = mod.AB_LayoutShape(s)
                local cols = isVert and numRows or stride
                local Pix = CludesUI and CludesUI.PP
                local onePx = Pix and Pix.mult or 1
                local physTarget = math.floor(wid / onePx + 0.5)
                local physPad = math.floor(pad / onePx + 0.5)
                local rawPhysBtn = (physTarget - (cols - 1) * physPad) / cols
                if shape ~= "none" and shape ~= "cropped" then
                    rawPhysBtn = rawPhysBtn - math.floor((SHAPE_BTN_EXPAND or 10) / onePx + 0.5)
                end
                if rawPhysBtn < 8 then
                    rawPhysBtn = 8
                end
                local basePhysBtn = math.floor(rawPhysBtn)
                s.buttonWidth = basePhysBtn * onePx
                s.buttonHeight = s.buttonWidth
                -- Compute remainder pixels to distribute across columns
                local shapePhys = 0
                if shape ~= "none" and shape ~= "cropped" then
                    shapePhys = math.floor((SHAPE_BTN_EXPAND or 10) / onePx + 0.5)
                end
                local idealPhys = cols * (basePhysBtn + shapePhys) + (cols - 1) * physPad
                local extra = physTarget - idealPhys
                if extra > 0 and extra <= cols then
                    s._matchExtraPixels = extra
                else
                    s._matchExtraPixels = nil
                end
                LayoutBar(details.key)
            end,
            setHeight = function(_, hgt)
                local s = ABAR.db.profile.bars[details.key]
                if not s then
                    return
                end
                -- Reverse-engineer square button size from total bar height
                -- using physical pixel math to distribute remainder pixels.
                local numIcons = s.overrideNumIcons or s.numIcons or details.count
                local numRows = s.overrideNumRows or s.numRows or 1
                if numRows < 1 then
                    numRows = 1
                end
                local stride = math.ceil(numIcons / numRows)
                if stride < 1 then
                    stride = 1
                end
                local isVert = (s.orientation == "vertical")
                local pad = s.buttonPadding or 2
                local shape = mod.AB_LayoutShape(s)
                local rowList = isVert and stride or numRows
                local Pix = CludesUI and CludesUI.PP
                local onePx = Pix and Pix.mult or 1
                local physTarget = math.floor(hgt / onePx + 0.5)
                local physPad = math.floor(pad / onePx + 0.5)
                local rawPhysBtn = (physTarget - (rowList - 1) * physPad) / rowList
                if shape ~= "none" and shape ~= "cropped" then
                    rawPhysBtn = rawPhysBtn - math.floor((SHAPE_BTN_EXPAND or 10) / onePx + 0.5)
                elseif shape == "cropped" then
                    rawPhysBtn = rawPhysBtn / 0.80
                end
                if rawPhysBtn < 8 then
                    rawPhysBtn = 8
                end
                local basePhysBtn = math.floor(rawPhysBtn)
                s.buttonWidth = basePhysBtn * onePx
                s.buttonHeight = s.buttonWidth
                -- Compute remainder pixels to distribute across rows
                local shapePhys = 0
                if shape ~= "none" and shape ~= "cropped" then
                    shapePhys = math.floor((SHAPE_BTN_EXPAND or 10) / onePx + 0.5)
                end
                local croppedH = basePhysBtn + shapePhys
                if shape == "cropped" then
                    croppedH = math.floor(basePhysBtn * 0.80)
                end
                local idealPhys = rowList * croppedH + (rowList - 1) * physPad
                local extra = physTarget - idealPhys
                if extra > 0 and extra <= rowList then
                    s._matchExtraPixelsH = extra
                else
                    s._matchExtraPixelsH = nil
                end
                LayoutBar(details.key)
            end,
            savePos = function(_, anchorPoint, relPoint, posX, posY)
                if anchorPoint and posX and posY then
                    local sp, sx, sy = ABAR:ConvertCenterToEdge(details.key, anchorPoint, posX, posY)
                    ABAR.db.profile.barPositions[details.key] = {
                        point = sp,
                        relPoint = relPoint or anchorPoint,
                        x = sx,
                        y = sy,
                    }
                else
                    SaveBarPosition(details.key)
                end
                -- Follow baseline: capture the anchor target's geometry at save time so
                -- ApplyAnchorPosition can shift the absolute saved growth edge by the
                -- target's displacement when it moves/resizes at runtime. Applies to
                -- every growth-direction bar so a perpendicular corner anchor to a
                -- resizing chain target can follow; nil for unanchored/CENTER-grow
                -- bars, leaving the follow off and the pure pin unchanged.
                do
                    local record = ABAR.db.profile.barPositions[details.key]
                    local s = ABAR.db.profile.bars[details.key]
                    local gd = s and (s.growDirection or "up"):upper()
                    if record and gd and gd ~= "CENTER" and CludesUI.GetAnchorTargetCenterUI then
                        record.tgtx, record.tgty = CludesUI.GetAnchorTargetCenterUI(details.key)
                        if CludesUI.GetAnchorTargetEdgesUI then
                            record.tgtL, record.tgtR, record.tgtT, record.tgtB =
                                CludesUI.GetAnchorTargetEdgesUI(details.key)
                        end
                    end
                end
            end,
            loadPos = function()
                return ABAR:ConvertEdgeToCenter(details.key, ABAR.db.profile.barPositions[details.key])
            end,
            clearPos = function()
                ABAR.db.profile.barPositions[details.key] = nil
            end,
            applyPos = function()
                ABAR:RecalcFlyoutDirection(details.key)
                if CludesUI.IsPointAnchored(details.key) then
                    CludesUI.ReapplyOwnAnchor(details.key)
                    return
                end
                -- Anchored bars: position owned by anchor system. But bars
                -- with growth direction need edge bounds applied first so the
                -- live-edge reading in ApplyAnchorPosition has correct data.
                if CludesUI and CludesUI.IsUnlockAnchored and CludesUI.IsUnlockAnchored(details.key) then
                    local s = ABAR.db.profile.bars[details.key]
                    local gd = s and (s.growDirection or "up"):upper()
                    if gd and gd ~= "CENTER" and gd ~= "UP" then
                        local place = ABAR.db.profile.barPositions[details.key]
                        local widget = barFrames[details.key]
                        if place and widget then
                            local pt = place.point or "CENTER"
                            local px, py = place.x or 0, place.y or 0
                            -- Convert CENTER to edge (like CDM's ApplyBarPositionCentered)
                            if pt == "CENTER" then
                                local fw = widget:GetWidth() or 0
                                local fh = widget:GetHeight() or 0
                                if gd == "RIGHT" and fw > 0 then
                                    pt = "LEFT"
                                    px = px - fw / 2
                                elseif gd == "LEFT" and fw > 0 then
                                    pt = "RIGHT"
                                    px = px + fw / 2
                                elseif gd == "DOWN" and fh > 0 then
                                    pt = "TOP"
                                    py = py + fh / 2
                                end
                            end
                            if pt ~= "CENTER" then
                                local PPa = CludesUI and CludesUI.PP
                                if PPa and PPa.SnapForES then
                                    local es = widget:GetEffectiveScale()
                                    px = PPa.SnapForES(px, es)
                                    py = PPa.SnapForES(py, es)
                                end
                                widget:ClearAllPoints()
                                widget:SetPoint(pt, UIParent, place.relPoint or "CENTER", px, py)
                            end
                        end
                    end
                    return
                end
                local place = ABAR.db.profile.barPositions[details.key]
                local widget = barFrames[details.key]
                if place and widget then
                    local pt = place.point
                    local px, py = place.x, place.y
                    local PPa = CludesUI and CludesUI.PP
                    if PPa and px and py then
                        local es = widget:GetEffectiveScale()
                        local isCenterAnchor = (pt == "CENTER")
                            and (place.relPoint == "CENTER" or place.relPoint == nil)
                        if isCenterAnchor and PPa.SnapCenterForDim then
                            px = PPa.SnapCenterForDim(px, widget:GetWidth() or 0, es)
                            py = PPa.SnapCenterForDim(py, widget:GetHeight() or 0, es)
                        elseif PPa.SnapForES then
                            px = PPa.SnapForES(px, es)
                            py = PPa.SnapForES(py, es)
                        end
                    end
                    widget:ClearAllPoints()
                    widget:SetPoint(pt, UIParent, place.relPoint or pt, px, py)
                end
            end,
        })
    end

    -- Blizzard movable frames (Extra Action Button, Encounter Bar)
    local blizzOrder = orderBase + #BAR_CONFIG
    for _, details in ipairs(EXTRA_BARS) do
        if details.isBlizzardMovable then
            blizzOrder = blizzOrder + 1
            local bk = details.key
            elements[#elements + 1] = MK({
                key = bk,
                label = details.label,
                group = "Action Bars",
                order = blizzOrder,
                noResize = true,
                -- The Extra Action Button hidden for good (Never, or hidden by
                -- the Toggle Action Bar keybind), as RefreshRuntimeVisibility
                -- hides its holder: no mover, and the Cooldown Manager's group
                -- loot rolls stop keeping clear of it.
                isHidden = (bk == "ExtraActionButton") and function()
                    local s = ABAR.db.profile.bars[bk]
                    if not s then
                        return false
                    end
                    local shade = ABAR._visOverride and ABAR._visOverride[bk]
                    if shade then
                        return shade == "never"
                    end
                    return ABAR.VisibilityCompat.IsNever(s)
                end or nil,
                getFrame = function()
                    return blizzMovableHolders[bk]
                end,
                getSize = function()
                    local shade = BLIZZ_MOVABLE_OVERLAY[bk]
                    if shade then
                        return shade.w, shade.h
                    end
                    return 50, 50
                end,
                savePos = function(_, anchorPoint, relPoint, posX, posY)
                    if anchorPoint and posX and posY then
                        ABAR.db.profile.barPositions[bk] = {
                            point = anchorPoint,
                            relPoint = relPoint or anchorPoint,
                            x = posX,
                            y = posY,
                        }
                    end
                    if not CludesUI._unlockActive then
                        local holderFrame = blizzMovableHolders[bk]
                        if holderFrame and anchorPoint and posX and posY and not InCombatLockdown() then
                            holderFrame:ClearAllPoints()
                            holderFrame:SetPoint(anchorPoint, UIParent, relPoint or anchorPoint, posX, posY)
                        end
                    end
                end,
                loadPos = function()
                    local place = ABAR.db.profile.barPositions[bk]
                    if not place then
                        return nil
                    end
                    local pt = place.point
                    return { point = pt, relPoint = place.relPoint or pt, x = place.x, y = place.y }
                end,
                clearPos = function()
                    ABAR.db.profile.barPositions[bk] = nil
                end,
                applyPos = function()
                    local place = ABAR.db.profile.barPositions[bk]
                    local holderFrame = blizzMovableHolders[bk]
                    if not holderFrame or InCombatLockdown() then
                        return
                    end
                    holderFrame:ClearAllPoints()
                    if place then
                        local pt = place.point
                        local px, py = place.x, place.y
                        local PPa = CludesUI and CludesUI.PP
                        if PPa and px and py then
                            local es = holderFrame:GetEffectiveScale()
                            local isCenterAnchor = (pt == "CENTER")
                                and (place.relPoint == "CENTER" or place.relPoint == nil)
                            if isCenterAnchor and PPa.SnapCenterForDim then
                                px = PPa.SnapCenterForDim(px, holderFrame:GetWidth() or 0, es)
                                py = PPa.SnapCenterForDim(py, holderFrame:GetHeight() or 0, es)
                            elseif PPa.SnapForES then
                                px = PPa.SnapForES(px, es)
                                py = PPa.SnapForES(py, es)
                            end
                        end
                        holderFrame:SetPoint(pt, UIParent, place.relPoint or pt, px, py)
                    else
                        holderFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
                    end
                end,
            })
        end
    end

    CludesUI:RegisterUnlockElements(elements, "CludesUIActionBars")

    -- Reapply anchors now that elements are registered: RestoreBarPositions
    -- ran before registration (too early for ReapplyOwnAnchor to resolve
    -- frames), so anchored bars sit unresolved. Skip growth-direction bars:
    -- applyPos already pre-positioned them at the edge and the authoritative
    -- pass preserves that via live-edge reading.
    if CludesUI.ReapplyOwnAnchor then
        for _, details in ipairs(BAR_CONFIG) do
            if CludesUI.IsUnlockAnchored and CludesUI.IsUnlockAnchored(details.key) then
                local s = ABAR.db.profile.bars[details.key]
                local gd = s and (s.growDirection or "up"):upper()
                if not gd or gd == "CENTER" or gd == "UP" then
                    CludesUI.ReapplyOwnAnchor(details.key)
                end
            end
        end
    end
end

-- Entry points the files after this one re-import by name.
Inner.RestoreBarPositions, Inner.RegisterWithUnlockMode = RestoreBarPositions, RegisterWithUnlockMode
