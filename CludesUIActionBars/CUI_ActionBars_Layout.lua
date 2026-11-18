if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_ActionBars_Layout.lua
--
--  The layout engine that places buttons in a grid, bar chrome sizing,
--  party mode and LayoutBar.
--  Loads after CUI_ActionBars_Bars.lua; reads ns._internals.
-------------------------------------------------------------------------------
local _, mod = ...

local ipairs = ipairs
local ceil, floor, max = math.ceil, math.floor, math.max
local wipe = wipe
local InCombatLockdown = InCombatLockdown
local GetBindingKey = GetBindingKey
local EFD = mod.EFD

local ABAR, barButtons = mod.EAB, mod.barButtons
local Inner = mod._internals
local _gridState, BAR_CONFIG, BAR_LOOKUP = Inner._gridState, Inner.BAR_CONFIG, Inner.BAR_LOOKUP
local SHAPE_BTN_EXPAND, ShouldQuickKeybindSurfaceBar =
    Inner.SHAPE_BTN_EXPAND, Inner.ShouldQuickKeybindSurfaceBar
local barBaseSize, barFrames = Inner.barBaseSize, Inner.barFrames
local LayoutPagingFrame, SetupPagingFrame = Inner.LayoutPagingFrame, Inner.SetupPagingFrame
local WireSecurePagingButton = Inner.WireSecurePagingButton
-- Written in CUI_ActionBars_Paging.lua;
-- SetPagingFrame hands the value to this copy.
local _pagingFrame
Inner.pagingFrameSetters[#Inner.pagingFrameSetters + 1] = function(val)
    _pagingFrame = val
end

-------------------------------------------------------------------------------
--  Layout Engine positions buttons in a grid
-------------------------------------------------------------------------------
-- Snap to a whole number of physical pixels at the bar's effective scale (same
-- round-trip as the border system), eliminating sub-pixel drift between siblings.
local function SnapForScale(posX, barScale)
    if posX == 0 then
        return 0
    end
    local Pix = CludesUI and CludesUI.PP
    if Pix then
        return Pix.Scale(posX)
    end
    return math.floor(posX + 0.5)
end

-- Grow direction for icon layout + fixed-edge resize. Lives on EAB, not a
-- file-scope local. Caveat: in an unlock
-- anchor chain a mid-chain bar can inherit its parent's grow visually while its
-- own DB still holds the old value.
function ABAR:ResolveGrowDirectionForLayout(key, s, depth)
    return (s.growDirection or "up"):upper()
end

-- Resolve a bar's icon order into abstract order parts. iconOrder supersedes the legacy
-- reverseIconOrder boolean; nil iconOrder falls back to the boolean, so old profiles
-- render unchanged with zero migration. Returns flowFlip (reverse button flow along the
-- fill axis) plus hAnchor ("LEFT"/"RIGHT") and vAnchor ("TOP"/"BOTTOM") for the corner
-- modes (both nil in the two legacy modes). do-end + ns so no file-scope local slots
-- are consumed.
do
    local function ResolveIconOrder(s)
        local sequence = s.iconOrder
        if sequence == nil then
            sequence = s.reverseIconOrder and "reversed" or "default"
        end
        if sequence == "reversed" then
            return true, nil, nil
        elseif sequence == "TOPLEFT" then
            return false, "LEFT", "TOP"
        elseif sequence == "TOPRIGHT" then
            return false, "RIGHT", "TOP"
        elseif sequence == "BOTTOMLEFT" then
            return false, "LEFT", "BOTTOM"
        elseif sequence == "BOTTOMRIGHT" then
            return false, "RIGHT", "BOTTOM"
        end
        return false, nil, nil
    end

    -- Resolved icon order -> concrete index flips for a bar's button grid.
    -- Corner modes place button 1 in that corner purely by permuting indexes:
    -- the frame, its size and the grid geometry never change. rowsUpward is meaningful
    -- only for horizontal bars. Third return (cornerFill): true in the four corner
    -- modes. On vertical bars those fill ACROSS the columns first and wrap down to the
    -- next row; Default/Reversed keep the legacy down-each-column fill. Horizontal bars
    -- already fill row-first, so callers ignore it there.
    function mod.GetOrderFlips(s, isVertical, rowsUpward)
        local flowFlip, hAnchor, vAnchor = ResolveIconOrder(s)
        local colFlip, rowFlip = false, false
        if isVertical then
            rowFlip = flowFlip or (vAnchor == "BOTTOM")
            colFlip = (hAnchor == "RIGHT")
        else
            colFlip = flowFlip or (hAnchor == "RIGHT")
            if vAnchor then
                rowFlip = ((vAnchor == "TOP") == rowsUpward)
            end
        end
        return colFlip, rowFlip, (hAnchor ~= nil)
    end
end

-- Compute layout for a bar and return a table of per-button data.
-- Returns: { [i] = { x, y, w, h, show } }, frameW, frameH
local function ComputeBarLayout(key)
    local details = BAR_LOOKUP[key]
    if not details then
        return {}, 1, 1
    end
    local buttons = barButtons[key]
    if not buttons then
        return {}, 1, 1
    end

    local s = ABAR.db.profile.bars[key]
    local numIcons = s.overrideNumIcons or s.numIcons or details.count
    if numIcons < 1 then
        numIcons = details.count
    end
    if numIcons > details.count then
        numIcons = details.count
    end
    if details.isStance then
        numIcons = GetNumShapeshiftForms() or details.count
    end
    if numIcons < 1 then
        numIcons = 1
    end

    local numRows = s.overrideNumRows or s.numRows or 1
    if numRows < 1 then
        numRows = 1
    end
    local stride = ceil(numIcons / numRows)
    numRows = ceil(numIcons / stride)
    -- Raw coords -- do NOT pre-snap with SnapForScale: PP.Scale truncates and
    -- loses a pixel where PP.mult > 1. Pixel-lock happens below, post-shape.
    local padding = s.buttonPadding or 2
    local isVertical = (s.orientation == "vertical")
    local growDir = ABAR:ResolveGrowDirectionForLayout(key, s)
    local shape = mod.AB_LayoutShape(s)

    local base = barBaseSize[key]
    local baseW = base and base.w or 45
    local baseH = base and base.h or 45
    local btnW = (s.buttonWidth and s.buttonWidth > 0) and s.buttonWidth or baseW
    local btnH = (s.buttonHeight and s.buttonHeight > 0) and s.buttonHeight or baseH
    if shape ~= "none" and shape ~= "cropped" then
        btnW = btnW + SHAPE_BTN_EXPAND
        btnH = btnH + SHAPE_BTN_EXPAND
    end
    if shape == "cropped" then
        btnH = btnH * 0.80
    end
    local PPc = CludesUI and CludesUI.PP
    local onePxC = PPc and PPc.mult or 1
    -- Lock btnW/btnH/padding to exact physical pixel multiples so stepW/stepH
    -- and the frame-size math below share the pixel grid of the width-match
    -- extras (onePxC). Otherwise coords drift sub-pixel as col grows, shrinking
    -- spacing and making the last button undershoot the match target.
    local btnWPxC = math.floor(btnW / onePxC + 0.5)
    local btnHPxC = math.floor(btnH / onePxC + 0.5)
    local paddingPxC = math.floor(padding / onePxC + 0.5)
    btnW = btnWPxC * onePxC
    btnH = btnHPxC * onePxC
    padding = paddingPxC * onePxC
    local stepW = btnW + padding
    local stepH = btnH + padding
    local extraWC = s._matchExtraPixels or 0
    local extraHC = s._matchExtraPixelsH or 0

    local showEmpty = s.alwaysShowButtons
    if showEmpty == nil then
        showEmpty = true
    end
    if details.isStance then
        showEmpty = false
    end

    -- Icon order flips are constant for the whole grid.
    local rowsUpward = not isVertical and (growDir == "UP" or growDir == "CENTER")
    local colFlip, rowFlip, cornerFill = mod.GetOrderFlips(s, isVertical, rowsUpward)

    local result = {}
    for index = 1, details.count do
        local button = buttons[index]
        if not button then
            break
        end
        if index > numIcons then
            result[index] = { x = 0, y = 0, w = btnW, h = btnH, show = false }
        else
            local colour, row
            if isVertical then
                if cornerFill then
                    -- Corner modes fill across columns first, then wrap down a
                    -- row (numRows = the column count on vertical bars).
                    colour = (index - 1) % numRows
                    row = floor((index - 1) / numRows)
                else
                    colour = floor((index - 1) / stride)
                    row = (index - 1) % stride
                end
            else
                colour = (index - 1) % stride
                row = floor((index - 1) / stride)
            end
            -- Icon order flips first so the width/height-match extras
            -- below derive from the final visual position.
            if colFlip then
                colour = (isVertical and numRows or stride) - 1 - colour
            end
            if rowFlip then
                row = (isVertical and stride or numRows) - 1 - row
            end
            local thisBtnW = (extraWC > 0 and colour < extraWC) and (btnW + onePxC) or btnW
            local thisBtnH = (extraHC > 0 and row < extraHC) and (btnH + onePxC) or btnH
            local extraBeforeW = math.min(colour, extraWC) * onePxC
            local extraBeforeH = math.min(row, extraHC) * onePxC
            local xOff = colour * stepW + extraBeforeW
            local yOff
            if rowsUpward then
                yOff = row * stepH + extraBeforeH
            else
                yOff = -(row * stepH + extraBeforeH)
            end
            local show = true
            if
                not showEmpty
                and not (_gridState.shown or ShouldQuickKeybindSurfaceBar(s))
                and mod.AB_EmptySlot(button, details)
            then
                show = false
            end
            result[index] = { x = xOff, y = yOff, w = thisBtnW, h = thisBtnH, show = show }
        end
    end

    -- Frame size in integer physical pixels, then back to coord. btnW/btnH/
    -- padding are already exact pixel multiples, so these multiplies produce
    -- exact pixel counts with no float dust or 1px truncation loss.
    local totalCols = isVertical and numRows or stride
    local totalRows = isVertical and stride or numRows
    local frameWPx = totalCols * btnWPxC + (totalCols - 1) * paddingPxC + extraWC
    local frameHPx = totalRows * btnHPxC + (totalRows - 1) * paddingPxC + extraHC
    local frameW = frameWPx * onePxC
    local frameH = frameHPx * onePxC
    return result, max(frameW, 1), max(frameH, 1)
end

local function HideSlotArt(button)
    if not button.SlotArt then
        return
    end
    if CludesUI and CludesUI._hiddenParent then
        button.SlotArt:SetParent(CludesUI._hiddenParent)
    else
        button.SlotArt:Hide()
        button.SlotArt:SetAlpha(0)
    end
end

-------------------------------------------------------------------------------
--  Party Mode: spinning action bars, on the shared spin engine
--  (CludesUI.PartySpin_Create, CludesUI_PartyMode.lua). Each bar's
--  shown buttons orbit that bar's centre by re-anchoring, not rotating, so
--  buttons stay upright and clicking, cooldowns and keybinds are unaffected.
--  Frozen in combat, where moving a protected button is blocked; offsets are
--  measured in screen space, so Blizzard style's per-button SetScale holds;
--  every button goes back onto its exact layout anchor when it stops.
--
--  do/end scope, so none of this takes
--  a main-chunk slot; the refresh lives on ns for ApplyAll.
-------------------------------------------------------------------------------
do
    local groups, groupOf = {}, {}
    mod.PartySpin_Refresh = CludesUI.PartySpin_Create({
        target = "actionBars",
        collect = function()
            wipe(groups)
            for _, details in ipairs(BAR_CONFIG) do
                local buttons, widget = barButtons[details.key], barFrames[details.key]
                if buttons and widget then
                    local grp = groupOf[details.key]
                    if not grp then
                        grp = { frames = {} }
                        groupOf[details.key] = grp
                    end
                    grp.pivot = widget
                    local entries = grp.frames
                    wipe(entries)
                    for index = 1, #buttons do
                        local button = buttons[index]
                        if button and button:IsShown() then
                            entries[#entries + 1] = button
                        end
                    end
                    groups[#groups + 1] = grp
                end
            end
            return groups
        end,
    })
end

-- Upvalue for LayoutBar (must be declared before it). ApplyAll sets it during full
-- rebuilds so edge preservation cannot save stale positions into the new profile.
local _isApplyingAll = false
Inner.isApplyingAllSetters[#Inner.isApplyingAllSetters + 1] = function(val)
    _isApplyingAll = val
end

local function LayoutBar(key)
    if InCombatLockdown() then
        mod._eabApplyDeferred = true
        return
    end
    local details = BAR_LOOKUP[key]
    if not details then
        return
    end
    local widget = barFrames[key]
    local buttons = barButtons[key]
    if not widget or not buttons then
        return
    end

    local s = ABAR.db.profile.bars[key]
    -- LAYOUT STAMP: skips a re-layout whose inputs are unchanged (the combat-exit
    -- ApplyAll re-ran this full layout for nothing). EVERY input the body reads
    -- folds into one string: raw settings, profile flags, barPositions, base sizes,
    -- PP.mult (resolution), derived helpers via their RESULTS (grow direction, order
    -- flips, quick keybind surface, unlock anchoring), the stance form count, the
    -- flyout screen-thirds bucket (live GetCenter, so anchor-chain moves invalidate
    -- too), and -- hide-empty bars only -- the per-slot filled bitmask driving
    -- empty-slot alpha. A matching stamp means byte-identical skip. Written only at
    -- the END of a completed pass and cleared on entry, so an interrupted pass can
    -- never leave a stale valid stamp.
    local _lbStamp
    do
        local p = ABAR.db.profile
        local place = p.barPositions and p.barPositions[key]
        local base0 = barBaseSize[key]
        local PPm = CludesUI and CludesUI.PP
        local growDirS = ABAR:ResolveGrowDirectionForLayout(key, s)
        local isVertS = (s.orientation == "vertical")
        local rowsUpS = not isVertS and (growDirS == "UP" or growDirS == "CENTER")
        local cfS, rfS, cnS = mod.GetOrderFlips(s, isVertS, rowsUpS)
        local nIcoS = s.overrideNumIcons or s.numIcons or details.count
        if details.isStance then
            nIcoS = GetNumShapeshiftForms() or details.count
        end
        local fbS = -1
        do
            local cx, cy = widget:GetCenter()
            if cx and cy then
                local region = widget:GetEffectiveScale() / UIParent:GetEffectiveScale()
                local uw, uh = UIParent:GetSize()
                fbS = ((cx * region > uw * 2 / 3) and 2 or 0) + ((cy * region > uh * 2 / 3) and 1 or 0)
            end
        end
        local showES = s.alwaysShowButtons
        if showES == nil then
            showES = true
        end
        if details.isStance then
            showES = false
        end
        local fillS = ""
        if not showES then
            local tf = {}
            for index = 1, details.count do
                local b = buttons[index]
                tf[index] = (b and not mod.AB_EmptySlot(b, details)) and "1" or "0"
            end
            fillS = table.concat(tf)
        end
        _lbStamp = table.concat({
            -- #buttons, not just the configured count: a Never bar is built with
            -- none and gains them at the reveal edge, and every other stamp input
            -- can be identical across that edge (the base size falls back to the
            -- same 45x45 the real button reports).
            tostring(nIcoS),
            tostring(#buttons),
            tostring(s.overrideNumRows or s.numRows or 1),
            tostring(s.buttonPadding or 2),
            tostring(s.orientation),
            growDirS or "-",
            tostring(s.buttonShape),
            tostring(s.buttonWidth),
            tostring(s.buttonHeight),
            tostring(s._matchExtraPixels),
            tostring(s._matchExtraPixelsH),
            tostring(showES),
            tostring(s.mouseoverEnabled),
            mod.AB_Forever() and "forever" or mod.AB_Style(),
            mod.AB_ChromeStamp(key),
            tostring(p.procGlowEnabled),
            place and tostring(place.point) or "-",
            place and tostring(place.relPoint) or "-",
            place and tostring(place.x) or "-",
            place and tostring(place.y) or "-",
            base0 and tostring(base0.w) or "-",
            base0 and tostring(base0.h) or "-",
            tostring(PPm and PPm.mult or 1),
            tostring(cfS),
            tostring(rfS),
            tostring(cnS),
            tostring(_gridState.shown),
            ShouldQuickKeybindSurfaceBar(s) and "1" or "0",
            (CludesUI.IsUnlockAnchored and CludesUI.IsUnlockAnchored(key)) and "1" or "0",
            tostring(fbS),
            fillS,
        }, "|")
        local st = mod._eabLayoutStamp
        if not st then
            st = {}
            mod._eabLayoutStamp = st
        end
        if st[key] == _lbStamp then
            return
        end
        st[key] = nil
        -- This pass rewrites the pet buttons from live state: drop the pet
        -- handler's shape memo so its next full pass lays them out again.
        if details.isPetBar then
            mod._eabPetLayoutSig = nil
        end
    end
    local numIcons = s.overrideNumIcons or s.numIcons or details.count
    if numIcons < 1 then
        numIcons = details.count
    end
    if numIcons > details.count then
        numIcons = details.count
    end
    if details.isStance then
        numIcons = GetNumShapeshiftForms() or details.count
    end
    if numIcons < 1 then
        numIcons = 1
    end

    local numRows = s.overrideNumRows or s.numRows or 1
    if numRows < 1 then
        numRows = 1
    end

    local stride = ceil(numIcons / numRows)
    if stride < 1 then
        stride = 1
    end
    -- Recalculate actual rows needed (avoids empty trailing rows)
    numRows = ceil(numIcons / stride)
    -- Raw coords -- do NOT pre-snap with SnapForScale: PP.Scale truncates and
    -- loses a pixel where PP.mult > 1. Pixel-lock happens below, post-shape.
    local padding = s.buttonPadding or 2
    local isVertical = (s.orientation == "vertical")
    local growDir = ABAR:ResolveGrowDirectionForLayout(key, s)
    local shape = mod.AB_LayoutShape(s)

    local base = barBaseSize[key]
    local baseW = base and base.w or 45
    local baseH = base and base.h or 45
    local btnW = (s.buttonWidth and s.buttonWidth > 0) and s.buttonWidth or baseW
    local btnH = (s.buttonHeight and s.buttonHeight > 0) and s.buttonHeight or baseH

    if shape ~= "none" and shape ~= "cropped" then
        btnW = btnW + SHAPE_BTN_EXPAND
        btnH = btnH + SHAPE_BTN_EXPAND
    end
    if shape == "cropped" then
        btnH = btnH * 0.80
    end

    -- Width/height match: distribute extra physical pixels across buttons
    local Pix = CludesUI and CludesUI.PP
    local onePx = Pix and Pix.mult or 1
    -- Lock btnW/btnH/padding to exact physical pixel multiples so stepW and the
    -- width-match +1px extras share one pixel grid; prevents sub-pixel drift
    -- that shrinks visible spacing where PP.mult > 1.
    local btnWPx = math.floor(btnW / onePx + 0.5)
    local btnHPx = math.floor(btnH / onePx + 0.5)
    local paddingPx = math.floor(padding / onePx + 0.5)
    btnW = btnWPx * onePx
    btnH = btnHPx * onePx
    padding = paddingPx * onePx
    local stepW = btnW + padding
    local stepH = btnH + padding

    local extraW = s._matchExtraPixels or 0
    local extraH = s._matchExtraPixelsH or 0

    -- Show empty slots (stance bar always forces this off)
    local showEmpty = s.alwaysShowButtons
    if showEmpty == nil then
        showEmpty = true
    end
    if details.isStance then
        showEmpty = false
    end

    -- Growth direction fixes which edge stays put on resize. UP/CENTER on
    -- horizontal bars stack rows upward (2nd row above 1st); icon order flips
    -- permute indexes within that fixed grid.
    local rowsUpward = not isVertical and (growDir == "UP" or growDir == "CENTER")
    local colFlip, rowFlip, cornerFill = mod.GetOrderFlips(s, isVertical, rowsUpward)

    -- Fit Ring to Cropped Buttons sizes the assist ring from the button's own
    -- rectangle: a shown ring on this bar is refitted (or restored) after the
    -- re-layout. A hidden ring is fitted by AssistShow before it next shows.
    local assistFit = ABAR.db.profile.assistGlowFitCropped
    local assistRefit = false

    for index = 1, details.count do
        local button = buttons[index]
        if not button then
            break
        end

        if index > numIcons then
            button:Hide()
            button:SetAlpha(0)
            mod._eabMarkParked(button, details)
        else
            -- Buttons inside range stay Shown; visibility is alpha-only so
            -- combat page swaps never strand a button hidden.
            local lfd = EFD(button)
            local demote = lfd.parkA0 == 2 and not button:IsShown()
            button:Show()
            if demote and button:IsShown() then
                lfd.parkA0 = 1
            end

            local colour, row
            if isVertical then
                if cornerFill then
                    -- Corner modes fill across columns first, then wrap down a
                    -- row (numRows = the column count on vertical bars).
                    colour = (index - 1) % numRows
                    row = floor((index - 1) / numRows)
                else
                    colour = floor((index - 1) / stride)
                    row = (index - 1) % stride
                end
            else
                colour = (index - 1) % stride
                row = floor((index - 1) / stride)
            end

            -- Icon order flips first so the width/height-match extras
            -- below derive from the final visual position.
            if colFlip then
                colour = (isVertical and numRows or stride) - 1 - colour
            end
            if rowFlip then
                row = (isVertical and stride or numRows) - 1 - row
            end

            -- Width/height match: first N columns/rows get +1 physical pixel.
            -- Only the matched axis expands, so a row stays uniform (no 1px jag).
            local thisBtnW = (extraW > 0 and colour < extraW) and (btnW + onePx) or btnW
            local thisBtnH = (extraH > 0 and row < extraH) and (btnH + onePx) or btnH
            -- Cumulative offset from expanded buttons before this one
            local extraBeforeW = math.min(colour, extraW) * onePx
            local extraBeforeH = math.min(row, extraH) * onePx

            button:ClearAllPoints()
            local xOff = colour * stepW + extraBeforeW
            local yOff, anchor
            if rowsUpward then
                yOff = row * stepH + extraBeforeH
                anchor = "BOTTOMLEFT"
            else
                yOff = -(row * stepH + extraBeforeH)
                anchor = "TOPLEFT"
            end
            EFD(button).barKey = key
            -- Stock styles (Blizzard, Classic) keep the native-size button and
            -- scale it, so the stock art scales with it.
            local abStyle = mod.AB_Style()
            if abStyle ~= "cui" then
                local base = barBaseSize[key]
                local nativeW = base and base.w or 45
                local nativeH = base and base.h or 45
                local sc = thisBtnW / nativeW
                button:SetScale(sc)
                button:SetSize(nativeW, nativeH)
                button:SetPoint(anchor, widget, anchor, xOff / sc, yOff / sc)
                -- Classic WoW UI: the vanilla ring on the native-size button,
                -- painted once per size (the scale carries it). Blizzard
                -- Style on the Forever client: the retail border, once.
                if abStyle == "classic" then
                    local cfd = EFD(button)
                    if cfd.classicW ~= nativeW or cfd.classicH ~= nativeH then
                        cfd.classicW, cfd.classicH = nativeW, nativeH
                        mod.AB_PaintClassicButton(button, nativeW, nativeH)
                    end
                elseif CludesUI.IS_FOREVER and not (details.isStance or details.isPetBar) then
                    mod.AB_StockNormal(button)
                end
            else
                button:SetPoint(anchor, widget, anchor, xOff, yOff)
                button:SetSize(thisBtnW, thisBtnH)
            end
            HideSlotArt(button)

            -- Stock styles: counter-scale SpellActivationAlert so the native
            -- proc glow renders at screen size despite the button's SetScale.
            if abStyle ~= "cui" and button.SpellActivationAlert then
                local base = barBaseSize[key]
                local nativeW = base and base.w or 45
                local sc = thisBtnW / nativeW
                if sc > 0 then
                    button.SpellActivationAlert:SetScale(1 / sc)
                end
            end

            -- Resize the autocast overlay to match the button size
            if button.AutoCastOverlay then
                button.AutoCastOverlay:SetAllPoints(button)
            end

            -- TargetReticleAnimFrame is authored 128x128 for the default 45x45
            -- button, so btnW/45 keeps the visual proportions.
            if button.TargetReticleAnimFrame then
                button.TargetReticleAnimFrame:SetScale(btnW / 45)
            end

            -- AssistedCombat frames are created lazily at the default 45x45,
            -- anchored CENTER; scale them to our button size. A highlight ring
            -- fitted to a Cropped button (ns._AssistFit) runs at scale 1 and is
            -- refitted by the assist pass queued at the end of this layout.
            local ahf = button.AssistedCombatHighlightFrame
            if ahf and not (mod._eabFD[ahf] and mod._eabFD[ahf].fitW) then
                ahf:SetScale(btnW / 45)
            end
            if assistFit and not assistRefit then
                local ohf = EFD(button).assistHL
                assistRefit = (ohf and ohf:IsShown()) or (ahf and ahf:IsShown()) or false
            end
            if button.AssistedCombatRotationFrame then
                button.AssistedCombatRotationFrame:SetScale(btnW / 45)
            end

            -- Pin SpellActivationAlert to button bounds for custom proc glows;
            -- with custom glows off or a stock style on, leave it untouched.
            if button.SpellActivationAlert and ABAR.db.profile.procGlowEnabled and abStyle == "cui" then
                button.SpellActivationAlert:SetAllPoints(button)
                button.SpellActivationAlert:SetScale(1)
            end

            -- Profession quality diamonds: EAB paints its own rank icon (the
            -- quality scan in OnEnable). Blizzard's overlay is created lazily
            -- inside the secure button Update, which our buttons get no
            -- events for, and forcing that update writes the new frame onto
            -- the secure button's table (taint). Keep it permanently hidden.
            if button.ProfessionQualityOverlayFrame then
                button.ProfessionQualityOverlayFrame:SetShown(false)
                if not EFD(button).qualityHooked then
                    button.ProfessionQualityOverlayFrame:HookScript("OnShow", function(self)
                        self:SetShown(false)
                    end)
                    EFD(button).qualityHooked = true
                end
            end
            if ABAR._QueueRankScan then
                ABAR._QueueRankScan()
            end

            if
                not showEmpty
                and not (_gridState.shown or ShouldQuickKeybindSurfaceBar(s))
                and mod.AB_EmptySlot(button, details)
            then
                button:SetAlpha(0)
                mod._eabMarkParked(button, details)
            else
                if not s.mouseoverEnabled then
                    button:SetAlpha(1)
                    lfd.parkA0 = nil
                end
            end
        end
    end

    -- Size the bar frame to encompass all visible buttons (including extra px)
    local totalCols = isVertical and numRows or stride
    local totalRows = isVertical and stride or numRows
    local frameW = totalCols * btnW + (totalCols - 1) * padding + extraW * onePx
    local frameH = totalRows * btnH + (totalRows - 1) * padding + extraH * onePx

    -- Sync frame anchor with barPositions before SetSize so the frame grows
    -- from the correct edge (or center). Skip anchored bars: their position
    -- is owned by the anchor chain, not barPositions.
    local isAnchored = CludesUI.IsUnlockAnchored and CludesUI.IsUnlockAnchored(key)
    if not isAnchored then
        local curPt = ({ widget:GetPoint(1) })[1]
        local place = ABAR.db.profile.barPositions and ABAR.db.profile.barPositions[key]
        if place and place.point and place.relPoint == "CENTER" and curPt ~= place.point then
            local PPa = CludesUI and CludesUI.PP
            local px, py = place.x or 0, place.y or 0
            if place.point == "CENTER" and curPt and curPt ~= "CENTER" then
                -- Edge -> CENTER: read the live center (stored CENTER coords may
                -- be stale from a different width) so the bar does not jump.
                local fCx, fCy = widget:GetCenter()
                if fCx and fCy then
                    local uiS = UIParent:GetEffectiveScale()
                    local fS = widget:GetEffectiveScale()
                    local ratio = fS / uiS
                    local uiW, uiH = UIParent:GetSize()
                    px = fCx * ratio - uiW / 2
                    py = fCy * ratio - uiH / 2
                end
                if PPa and PPa.SnapCenterForDim then
                    local es = widget:GetEffectiveScale()
                    px = PPa.SnapCenterForDim(px, widget:GetWidth() or 0, es)
                    py = PPa.SnapCenterForDim(py, widget:GetHeight() or 0, es)
                end
            elseif PPa and PPa.SnapForES then
                local es = widget:GetEffectiveScale()
                px = PPa.SnapForES(px, es)
                py = PPa.SnapForES(py, es)
            end
            widget:ClearAllPoints()
            widget:SetPoint(place.point, UIParent, place.relPoint or place.point, px, py)
        end
    end
    -- Pre-resize center in UIParent space, captured BEFORE SetSize (an
    -- edge-pointed frame moves its center when resized); the anchor offset
    -- upkeep below validates against it.
    local preCX, preCY
    do
        local c1, c2 = widget:GetCenter()
        if c1 and c2 then
            local region = widget:GetEffectiveScale() / UIParent:GetEffectiveScale()
            preCX, preCY = c1 * region, c2 * region
        end
    end
    CludesUI._layoutBarResizing = key
    widget:SetSize(max(frameW, 1), max(frameH, 1))
    CludesUI._layoutBarResizing = nil
    -- Anchor offset upkeep: a growth-direction resize shifts the center by
    -- delta/2 while the fixed edge stays put, so the center-based anchor
    -- offset must follow. _eabPrevLayout* separates real resizes from init/reload sizing.
    do
        local newW = max(frameW, 1)
        local newH = max(frameH, 1)
        local prevW = widget._eabPrevLayoutW
        local prevH = widget._eabPrevLayoutH
        widget._eabPrevLayoutW = newW
        widget._eabPrevLayoutH = newH
        -- Self-validating gate: dw/2 compensation is correct only when the PRE-resize
        -- center sat at the anchor-derived position (target center + stored offset on
        -- the compensated axis). Mid-profile-apply the bar still holds the OUTGOING
        -- position while unlockAnchors already carries the INCOMING offsets;
        -- compensating that corrupts offsets cumulatively on every swap. Layout passes
        -- land before/inside/after the _abAnchorSuppressed window (extra bars build on
        -- a timer), so only the position check is ordering-proof.
        if
            (prevW or prevH)
            and not CludesUI._unlockActive
            and not CludesUI._abAnchorSuppressed
            and not _isApplyingAll
        then
            local s = ABAR.db.profile.bars[key]
            local grow = s and s.growDirection
            if grow then
                grow = grow:upper()
                if grow ~= "CENTER" then
                    local adb = CludesUIDB and CludesUIDB.unlockAnchors
                    local ai = adb and adb[key]
                    if ai and ai.mode ~= "POINT" then
                        local side = ai.side
                        local PPo = CludesUI and CludesUI.PP
                        local uiES = PPo and UIParent:GetEffectiveScale()
                        local tCX, tCY
                        if CludesUI.GetAnchorTargetCenterUI then
                            tCX, tCY = CludesUI.GetAnchorTargetCenterUI(key)
                        end
                        local TOL = 2 -- UI px; pixel-snap noise stays well under 1
                        -- Width/height-matched bars: the match owns that axis, so
                        -- a resize there is the match asserting the target size
                        -- the saved offset already matches; compensating would
                        -- corrupt it (CDM has a twin of this block).
                        local wMatched = CludesUIDB
                            and CludesUIDB.unlockWidthMatch
                            and CludesUIDB.unlockWidthMatch[key]
                        local hMatched = CludesUIDB
                            and CludesUIDB.unlockHeightMatch
                            and CludesUIDB.unlockHeightMatch[key]
                        -- Horizontal growth (LEFT/RIGHT): adjust offsetX on TOP/BOTTOM anchors
                        if
                            prevW
                            and math.abs(newW - prevW) > 0.1
                            and (side == "TOP" or side == "BOTTOM")
                            and not wMatched
                            and preCX
                            and tCX
                            and math.abs(preCX - (tCX + (ai.offsetX or 0))) <= TOL
                        then
                            local dw = newW - prevW
                            if grow == "RIGHT" then
                                ai.offsetX = ai.offsetX + dw / 2
                            elseif grow == "LEFT" then
                                ai.offsetX = ai.offsetX - dw / 2
                            end
                            if PPo and uiES then
                                ai.offsetX = PPo.SnapForES(ai.offsetX, uiES)
                            end
                        end
                        -- Vertical growth (UP/DOWN): adjust offsetY on LEFT/RIGHT anchors
                        if
                            prevH
                            and math.abs(newH - prevH) > 0.1
                            and (side == "LEFT" or side == "RIGHT")
                            and not hMatched
                            and preCY
                            and tCY
                            and math.abs(preCY - (tCY + (ai.offsetY or 0))) <= TOL
                        then
                            local dh = newH - prevH
                            if grow == "DOWN" then
                                ai.offsetY = ai.offsetY - dh / 2
                            elseif grow == "UP" then
                                ai.offsetY = ai.offsetY + dh / 2
                            end
                            if PPo and uiES then
                                ai.offsetY = PPo.SnapForES(ai.offsetY, uiES)
                            end
                        end
                    end
                end
            end
        end
    end

    if CludesUI.IsPointAnchored(key) then
        CludesUI.ReapplyOwnAnchor(key)
    end

    -- flyoutDirection per button from orientation + live screen position: split
    -- each axis into thirds and open away from the nearest screen edge.
    local flyDir
    do
        local cx, cy = widget:GetCenter()
        local uiW = UIParent:GetWidth()
        local uiH = UIParent:GetHeight()
        local uiScale = UIParent:GetEffectiveScale()
        local fScale = widget:GetEffectiveScale()
        -- Convert to UIParent coordinate space
        if cx and cy then
            cx = cx * fScale / uiScale
            cy = cy * fScale / uiScale
        end
        if cx and cy then
            local thirdW = uiW / 3
            local thirdH = uiH / 3
            if isVertical then
                -- Vertical bar: flyout goes left if bar is in the right third, else right
                flyDir = (cx > thirdW * 2) and "LEFT" or "RIGHT"
            else
                -- Horizontal bar: flyout goes down if bar is in the top third, else up
                flyDir = (cy > thirdH * 2) and "DOWN" or "UP"
            end
        else
            -- Frame not yet on screen safe fallback
            flyDir = isVertical and "RIGHT" or "UP"
        end
    end
    for index = 1, #buttons do
        local button = buttons[index]
        if button then
            -- Ensure the button has GetPopupDirection for Blizzard's SpellFlyout system
            -- (must be available on all buttons, regardless of squareIcons setting)
            if not button.GetPopupDirection then
                button.GetPopupDirection = function(self)
                    return self:GetAttribute("flyoutDirection") or "UP"
                end
            end
            if not InCombatLockdown() then
                button:SetAttribute("flyoutDirection", flyDir)
            end
        end
    end

    -- Notify the position system for width/height match propagation and
    -- anchor chains. Anchored bars with a growth direction skip it: the
    -- deferred ApplyAnchorPosition it queues would override edge
    -- positioning, and OnSizeChanged already propagates to dependents.
    local skipNotify = CludesUI.IsUnlockAnchored
        and CludesUI.IsUnlockAnchored(key)
        and growDir ~= "CENTER"
        and growDir ~= "UP"
    if not skipNotify then
        if CludesUI.NotifyElementResized then
            CludesUI.NotifyElementResized(key)
        end
        if CludesUI.PropagateAnchorChain then
            CludesUI.PropagateAnchorChain(key)
        end
    end

    -- Position paging arrows after MainBar layout
    if key == "MainBar" then
        if not _pagingFrame then
            SetupPagingFrame()
        end
        LayoutPagingFrame()
        -- Set up secure paging keybind overrides (once, out of combat).
        -- Redirects NEXTACTIONPAGE / PREVIOUSACTIONPAGE to hidden secure
        -- buttons so page cycling works in combat without taint.
        if _pagingFrame and not _pagingFrame._pageBindsSet and not InCombatLockdown() then
            _pagingFrame._pageBindsSet = true
            local nextBtn = CreateFrame("Button", "EABPageNext", UIParent, "SecureActionButtonTemplate")
            nextBtn:SetSize(1, 1)
            nextBtn:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -200, 200)
            nextBtn:SetAlpha(0)
            nextBtn:RegisterForClicks("AnyUp", "AnyDown")
            WireSecurePagingButton(nextBtn, 1)

            local prevBtn = CreateFrame("Button", "EABPagePrev", UIParent, "SecureActionButtonTemplate")
            prevBtn:SetSize(1, 1)
            prevBtn:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -200, 200)
            prevBtn:SetAlpha(0)
            prevBtn:RegisterForClicks("AnyUp", "AnyDown")
            WireSecurePagingButton(prevBtn, -1)
            mod.RefreshPagingCycleMacros()

            local function ApplyPageBindings()
                if InCombatLockdown() then
                    return
                end
                ClearOverrideBindings(_pagingFrame)
                local nextKeys = { GetBindingKey("NEXTACTIONPAGE") }
                local prevKeys = { GetBindingKey("PREVIOUSACTIONPAGE") }
                for _, k in ipairs(nextKeys) do
                    SetOverrideBindingClick(_pagingFrame, true, k, "EABPageNext")
                end
                for _, k in ipairs(prevKeys) do
                    SetOverrideBindingClick(_pagingFrame, true, k, "EABPagePrev")
                end
            end
            ApplyPageBindings()
            -- Re-apply if user changes keybinds
            _pagingFrame:RegisterEvent("UPDATE_BINDINGS")
            local origOnEvent = _pagingFrame:GetScript("OnEvent")
            _pagingFrame:SetScript("OnEvent", function(self, evt, ...)
                if evt == "UPDATE_BINDINGS" then
                    if not InCombatLockdown() then
                        ApplyPageBindings()
                    end
                    return
                end
                if origOnEvent then
                    origOnEvent(self, evt, ...)
                end
            end)
        end
    end

    -- The bar's chrome: WoW Forever's frame and dividers when shown (dividers
    -- only on a one-line bar at spacing 2 or less, as Blizzard draws them)
    -- and the bar's end caps. A bar that never showed either builds nothing.
    if (mod._abChrome and mod._abChrome[key]) or mod.AB_ForeverBg(key) or mod.AB_CapsLook(key) then
        local oneLine = (isVertical and totalCols or totalRows) == 1 and (s.buttonPadding or 2) <= 2
        mod.AB_ApplyBarChrome(
            key,
            widget,
            max(frameW, 1),
            max(frameH, 1),
            btnW,
            isVertical,
            totalRows > 1,
            oneLine and (isVertical and totalRows or totalCols) or 0,
            isVertical and stepH or stepW,
            isVertical and extraH or extraW,
            onePx
        )
    end
    -- The micro menu's and bag bar's caps size from Action Bar 1's buttons
    -- and may carry its caps (the span): repaint them after bar 1's pass.
    if key == "MainBar" then
        mod._abMainBtnW = btnW
        mod.AB_ExtraCapsAll()
    end

    -- Countdown size can be capped against button width (CooldownFonts .EffectiveSize,
    -- opt-in per bar), so any re-layout can change the cap. It sits here, not at the
    -- ~fourteen callers (icon size, padding, row/column overrides, width/height-match
    -- links, profile swaps, ...), because hooking one leaves the rest applying a stale
    -- size. Cheap when nothing changed: the per-frame stamp no-ops unless size differs.
    ABAR:ApplyCooldownFontsForBar(key)
    -- A shown fitted-or-fittable assist ring on this bar: refit or restore it
    -- on the next assist pass (coalesced; never queued with the option off).
    if assistRefit then
        mod.QueueAssistRescan()
    end
    -- Publish the stamp only on a completed pass (cleared on entry above).
    mod._eabLayoutStamp[key] = _lbStamp
end

-- Recompute a bar's flyout direction from its current screen position.
function ABAR:RecalcFlyoutDirection(barId)
    if InCombatLockdown() then
        return
    end
    local widget = barFrames[barId]
    local btns = barButtons[barId]
    local s = self.db.profile.bars[barId]
    if not widget or not btns or not s then
        return
    end
    local isVert = (s.orientation == "vertical")
    local cx, cy = widget:GetCenter()
    if not cx or not cy then
        return
    end
    local uiW = UIParent:GetWidth()
    local uiH = UIParent:GetHeight()
    local uiScale = UIParent:GetEffectiveScale()
    local fScale = widget:GetEffectiveScale()
    cx = cx * fScale / uiScale
    cy = cy * fScale / uiScale
    local thirdW = uiW / 3
    local thirdH = uiH / 3
    local direction
    if isVert then
        direction = (cx > thirdW * 2) and "LEFT" or "RIGHT"
    else
        direction = (cy > thirdH * 2) and "DOWN" or "UP"
    end
    for _, button in ipairs(btns) do
        button:SetAttribute("flyoutDirection", direction)
    end
end

-- Entry points the files after this one re-import by name.
Inner.LayoutBar, Inner.HideSlotArt, Inner.ComputeBarLayout = LayoutBar, HideSlotArt, ComputeBarLayout
