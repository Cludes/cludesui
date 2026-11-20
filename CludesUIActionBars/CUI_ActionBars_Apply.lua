if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_ActionBars_Apply.lua
--
--  The apply methods the options UI and ApplyAll call: borders, shapes,
--  layout passthroughs, fonts and keybind text, cooldown countdown fonts,
--  bar and icon backgrounds, Always Show Buttons and the main bar page sync.
--  Loads after the main file and CUI_ActionBars_ButtonArt.lua and reads them
--  through ns only.
-------------------------------------------------------------------------------
local _, mod = ...

local _G = _G
local ipairs, pairs, pcall = ipairs, pairs, pcall
local max = math.max
local InCombatLockdown = InCombatLockdown
local C_Timer_After = C_Timer.After
local GetBindingKey = GetBindingKey
local EFD = mod.EFD

local ABAR, EAB_VTABLE, BAR_LOOKUP = mod.EAB, mod.EAB_VTABLE, mod.BAR_LOOKUP
local ResolveBorderThickness, barButtons = mod.ResolveBorderThickness, mod.barButtons
local Inner = mod._internals
local BAR_CONFIG, BINDING_MAP, FONT_PATH = Inner.BAR_CONFIG, Inner.BINDING_MAP, Inner.FONT_PATH
local NUM_ACTIONBAR_BUTTONS = Inner.NUM_ACTIONBAR_BUTTONS
local barFrames, buttonToBar, _fadeAlpha = Inner.barFrames, Inner.buttonToBar, Inner._fadeAlpha
local _gridState, _quickKeybindState = Inner._gridState, Inner._quickKeybindState
local LayoutBar, SyncPagingAlpha, FormatHotkeyText =
    Inner.LayoutBar, Inner.SyncPagingAlpha, Inner.FormatHotkeyText
local ApplyButtonBorders, ApplyShapeToButton = Inner.ApplyButtonBorders, Inner.ApplyShapeToButton
local SafeEnableMouse, SafeEnableMouseMotionOnly = Inner.SafeEnableMouse, Inner.SafeEnableMouseMotionOnly
local ShouldQuickKeybindSurfaceBar = Inner.ShouldQuickKeybindSurfaceBar
local SHOWGRID, SetShowGridInsecure = Inner.SHOWGRID, Inner.SetShowGridInsecure

-------------------------------------------------------------------------------
--  EAB Methods Apply functions called by the options UI
-------------------------------------------------------------------------------
function ABAR:ApplyBordersForBar(barId)
    if not self.db then
        return
    end
    -- Border reach counts in size matching (the bar's getMatchPad reads these
    -- settings): re-push the bar's matches when it moved. At entry so the look
    -- and square-icon returns below report too; the re-push is deferred.
    if CludesUI.MatchPadChanged then
        CludesUI.MatchPadChanged(barId)
    end
    if not self.db.profile.squareIcons then
        return
    end
    if mod.AB_Style() ~= "cui" then
        return
    end
    local barCfg = self.db.profile.bars[barId]
    if not barCfg then
        return
    end
    local color = barCfg.borderColor or { r = 0, g = 0, b = 0, a = 1 }
    local sz, px = ResolveBorderThickness(barCfg)
    local enabled = sz > 0
    local cr, cg, callback, ca = color.r, color.g, color.b, color.a or 1
    if barCfg.borderClassColor then
        local _, classToken = UnitClass("player")
        if classToken then
            local cc = RAID_CLASS_COLORS[classToken]
            if cc then
                cr, cg, callback = cc.r, cc.g, cc.b
            end
        end
    end
    local zoom = (barCfg.iconZoom or self.db.profile.iconZoom or 5.5) / 100
    local textureKey = barCfg.borderTexture or "solid"
    local texOffset = barCfg.borderTextureOffset
    local texOffsetY = barCfg.borderTextureOffsetY
    local texShiftX = barCfg.borderTextureShiftX
    local texShiftY = barCfg.borderTextureShiftY
    local thicknessKey = barCfg.borderThickness or "thin"
    local behind = barCfg.borderBehind
    local above = barCfg.borderAboveEffects
    local buttons = barButtons[barId]
    if not buttons then
        return
    end
    for index = 1, #buttons do
        local button = buttons[index]
        if button then
            EFD(button).barKey = barId
            ApplyButtonBorders(
                button,
                enabled,
                cr,
                cg,
                callback,
                ca,
                sz,
                zoom,
                textureKey,
                texOffset,
                texOffsetY,
                texShiftX,
                texShiftY,
                "actionbars",
                thicknessKey,
                behind,
                px,
                above
            )
        end
    end
    -- Match Bar Border copies follow the bar border (one boolean read while off).
    mod._ixBarSync(barId)
end

function ABAR:ApplyBorders()
    if not self.db then
        return
    end
    for _, details in ipairs(BAR_CONFIG) do
        self:ApplyBordersForBar(details.key)
    end
end

function ABAR:ApplyShapesForBar(barId)
    if InCombatLockdown() then
        mod._eabApplyDeferred = true
        return
    end
    if not self.db then
        return
    end
    if mod.AB_Style() ~= "cui" then
        return
    end
    local barCfg = self.db.profile.bars[barId]
    if not barCfg then
        return
    end
    local shape = barCfg.buttonShape or "none"
    local zoom = (barCfg.iconZoom or self.db.profile.iconZoom or 5.5) / 100
    local brdSz = ResolveBorderThickness(barCfg)
    local brdOn = brdSz > 0
    local borderColor = barCfg.shapeBorderColor or barCfg.borderColor or { r = 0, g = 0, b = 0, a = 1 }
    local brdR, brdG, brdB, brdA = borderColor.r, borderColor.g, borderColor.b, borderColor.a or 1
    if barCfg.borderClassColor then
        local _, countText = UnitClass("player")
        if countText then
            local cc = RAID_CLASS_COLORS[countText]
            if cc then
                brdR, brdG, brdB = cc.r, cc.g, cc.b
            end
        end
    end
    local buttons = barButtons[barId]
    if not buttons then
        return
    end
    for index = 1, #buttons do
        local button = buttons[index]
        if button then
            ApplyShapeToButton(button, shape, brdOn, brdR, brdG, brdB, brdA, brdSz, zoom)
        end
    end
    LayoutBar(barId)
    -- A shape change moves the bar in or out of Match Bar Border eligibility;
    -- the copies' style inputs all go through ApplyBordersForBar's own sync.
    mod._ixBarSync(barId, true)
end

function ABAR:ApplyShapes()
    if not self.db then
        return
    end
    for _, details in ipairs(BAR_CONFIG) do
        self:ApplyShapesForBar(details.key)
    end
end

function ABAR:ApplyPaddingForBar(barId)
    LayoutBar(barId)
end

function ABAR:ApplyButtonSizeForBar(barId)
    LayoutBar(barId)
end

function ABAR:ApplyIconRowOverrides(barId)
    LayoutBar(barId)
    self:ApplyAlwaysShowButtons(barId)
end

function ABAR:ApplyBarOpacity(barId)
    local barCfg = self.db.profile.bars[barId]
    if not barCfg then
        return
    end
    local widget = barFrames[barId]
    if not widget then
        return
    end
    -- In mouseover mode the hover system owns alpha (0 when unhovered,
    -- mouseoverAlpha when hovered). Don't override it here.
    if not barCfg.mouseoverEnabled then
        local a = barCfg.mouseoverAlpha or 1
        widget:SetAlpha(a)
        _fadeAlpha[widget] = a
        if barId == "MainBar" then
            SyncPagingAlpha(barCfg.mouseoverAlpha or 1)
        end
    end
end

function ABAR:BarSupportsOrientation(barId)
    local details = BAR_LOOKUP[barId]
    return details and details.count ~= nil or false
end

function ABAR:GetOrientationForBar(barId)
    local barCfg = self.db.profile.bars[barId]
    if not barCfg then
        return true
    end
    return barCfg.orientation ~= "vertical"
end

function ABAR:LayoutAnchoredBarsFrom(targetKey, depth)
    if not targetKey or (depth or 0) > 12 then
        return
    end
    local adb = _G.CludesUIDB and _G.CludesUIDB.unlockAnchors
    if not adb then
        return
    end
    local nextDepth = (depth or 0) + 1
    for childKey, ai in pairs(adb) do
        if
            ai.target == targetKey
            and childKey ~= targetKey
            and self.db.profile.bars[childKey]
            and barFrames[childKey]
        then
            LayoutBar(childKey)
            self:LayoutAnchoredBarsFrom(childKey, nextDepth)
        end
    end
end

function ABAR:SetOrientationForBar(barId, isHorizontal)
    local barCfg = self.db.profile.bars[barId]
    if not barCfg then
        return
    end
    barCfg.orientation = isHorizontal and "horizontal" or "vertical"
    -- Reset growth direction to orientation-appropriate default when switching
    local g = (barCfg.growDirection or "up"):upper()
    if isHorizontal then
        -- Switching to horizontal: if current growth is vertical-only, reset
        if g == "UP" or g == "DOWN" then
            barCfg.growDirection = "center"
        end
    else
        -- Switching to vertical: if current growth is horizontal-only, reset
        if g == "LEFT" or g == "RIGHT" then
            barCfg.growDirection = "up"
        end
    end
    LayoutBar(barId)
    self:LayoutAnchoredBarsFrom(barId, 0)
end

function ABAR:SetGrowDirectionForBar(barId, direction)
    local barCfg = self.db.profile.bars[barId]
    if not barCfg then
        return
    end
    barCfg.growDirection = direction or "up"
    LayoutBar(barId)
    self:LayoutAnchoredBarsFrom(barId, 0)
end

-------------------------------------------------------------------------------
--  Font / Keybind Text
-------------------------------------------------------------------------------
-- Button text anchoring (keybind / charges / macro name). Opt-in per bar via
-- <text>Anchor; nil or false = stock placement, handled by the caller, which only
-- calls in here once an anchor is set. Returns false for an anchor it does not
-- know (a hand-edited profile), so the caller falls back to stock. The text is
-- stretched across the chosen edge (both corners anchored, same as the stock
-- keybind placement) and JustifyH does the alignment, so it holds regardless
-- of the font string's own width. Shared with
-- the options preview, hence on EAB not a local.
ABAR.TEXT_ANCHOR_ORDER = { "TOPLEFT", "TOP", "TOPRIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }
-- The spacing each stock placement carries (keybind -1/-3, charges -1/+4,
-- macro +1/+4). It lives in a text's offset boxes while a position is set: a
-- position pick swaps the old corner's spacing for the new one's and keeps the
-- user's own nudge on top, so no pick ever moves the text by the spacing alone.
-- Not applied on the drawing side: there, 0/0 is the corner itself.
ABAR.TEXT_INSET_X = 1
ABAR.TEXT_INSET_Y = { keybind = 3, count = 4, macro = 4 }

-- Offsets that reproduce a text's stock spacing at the position just picked.
-- 0/0 for a position PlaceButtonText does not know (hand-edited, or from a newer
-- build): that text draws at the stock placement, which carries its own spacing.
function ABAR.StockTextOffsets(kind, anchor)
    if not ABAR.TEXT_ANCHOR_JUSTIFY[anchor] then
        return 0, 0
    end
    local posX = 0
    if anchor:find("LEFT", 1, true) then
        posX = ABAR.TEXT_INSET_X
    elseif anchor:find("RIGHT", 1, true) then
        posX = -ABAR.TEXT_INSET_X
    end
    local posY = ABAR.TEXT_INSET_Y[kind] or 0
    if anchor:find("TOP", 1, true) then
        posY = -posY
    end
    return posX, posY
end

-- Writes a button-shape preset's keybind / charges offsets onto bar settings `bs`.
-- The preset values are relative to the stock placement; a text with a position
-- also carries that corner's stock spacing, as a position pick gives it.
function ABAR.ApplyShapeTextOffsets(bs, kbX, kbY, ctX, ctY)
    local anchorX, anchorY = 0, 0
    if bs.keybindAnchor then
        anchorX, anchorY = ABAR.StockTextOffsets("keybind", bs.keybindAnchor)
    end
    bs.keybindOffsetX, bs.keybindOffsetY = kbX + anchorX, kbY + anchorY
    anchorX, anchorY = 0, 0
    if bs.countAnchor then
        anchorX, anchorY = ABAR.StockTextOffsets("count", bs.countAnchor)
    end
    bs.countOffsetX, bs.countOffsetY = ctX + anchorX, ctY + anchorY
end
ABAR.TEXT_ANCHOR_JUSTIFY = {
    TOPLEFT = "LEFT",
    TOP = "CENTER",
    TOPRIGHT = "RIGHT",
    BOTTOMLEFT = "LEFT",
    BOTTOM = "CENTER",
    BOTTOMRIGHT = "RIGHT",
}
function ABAR.PlaceButtonText(fontStr, hostFrame, anchor, ox, oy)
    local justify = anchor and ABAR.TEXT_ANCHOR_JUSTIFY[anchor]
    if not justify then
        return false
    end
    -- Offset 0/0 is the corner the position names, with no inset of its own: the
    -- boxes are the only thing between the text and the edge, and they read the
    -- same at all six positions. The spacing the three stock placements carry
    -- (EAB.TEXT_INSET_*) rides in those boxes (see EAB.TEXT_INSET_X).
    local edge = (anchor:find("TOP", 1, true) and "TOP") or "BOTTOM"
    local posY = oy or 0
    ox = ox or 0
    fontStr:ClearAllPoints()
    fontStr:SetPoint(edge .. "LEFT", hostFrame, edge .. "LEFT", ox, posY)
    fontStr:SetPoint(edge .. "RIGHT", hostFrame, edge .. "RIGHT", ox, posY)
    local prevJustify = fontStr:GetJustifyH()
    fontStr:SetJustifyH(justify)
    -- A justification change alone does not re-lay the string out (SetPoint with
    -- unchanged values and SetText with unchanged text are no-ops), so only then
    -- clear and restore the text. issecretvalue first: a secret count must not be
    -- compared.
    if prevJustify ~= justify then
        local textValue = fontStr:GetText()
        if (issecretvalue and issecretvalue(textValue)) or (textValue and textValue ~= "") then
            fontStr:SetText("")
            fontStr:SetText(textValue)
        end
    end
    return true
end

function ABAR:ApplyFontsForBar(barId)
    local barCfg = self.db.profile.bars[barId]
    if not barCfg then
        return
    end
    local buttons = barButtons[barId]
    if not buttons then
        return
    end
    local fontFile = CludesUI.GetFontPath("actionBars") or FONT_PATH
    local hideKB = barCfg.hideKeybind
    local kbSize = barCfg.keybindFontSize or 12
    -- Stance/pet bar buttons are smaller (30px vs 45px) shrink keybind text
    -- by 2px so it doesn't overwhelm the icon.
    local details = BAR_LOOKUP[barId]
    if details and (details.isStance or details.isPetBar) then
        kbSize = max(kbSize - 2, 6)
    end
    local kbColor = barCfg.keybindFontColor or { r = 1, g = 1, b = 1 }
    local ctSize = barCfg.countFontSize or 12
    local ctColor = barCfg.countFontColor or { r = 1, g = 1, b = 1 }
    local kbOX = barCfg.keybindOffsetX or 0
    local kbOY = barCfg.keybindOffsetY or 0
    local kbAnchor = barCfg.keybindAnchor
    local ctOX = barCfg.countOffsetX or 0
    local ctOY = barCfg.countOffsetY or 0
    local ctAnchor = barCfg.countAnchor
    local hideMacro = barCfg.hideMacroText
    local macroSize = barCfg.macroFontSize or 12
    if details and (details.isStance or details.isPetBar) then
        macroSize = max(macroSize - 2, 6)
    end
    local macroColor = barCfg.macroFontColor or { r = 1, g = 1, b = 1 }
    local macroOX = barCfg.macroOffsetX or 0
    local macroOY = barCfg.macroOffsetY or 0
    local macroAnchor = barCfg.macroAnchor
    local RANGE_INDICATOR = RANGE_INDICATOR or "\226\128\162"

    for index = 1, #buttons do
        local button = buttons[index]
        if not button then
            break
        end

        -- Keybind text
        local hotkeyText = button.HotKey
        if hotkeyText then
            if hideKB then
                hotkeyText:SetText("")
                hotkeyText:Hide()
            else
                -- Get binding text
                local bindingAction
                local details = BAR_LOOKUP[barId]
                if details and not details.isStance and not details.isPetBar then
                    if barId == "MainBar" then
                        bindingAction = "ACTIONBUTTON" .. index
                    else
                        local bindPrefix = BINDING_MAP[barId]
                        if bindPrefix then
                            bindingAction = bindPrefix .. index
                        end
                    end
                elseif details and details.isStance then
                    bindingAction = "SHAPESHIFTBUTTON" .. index
                elseif details and details.isPetBar then
                    bindingAction = "BONUSACTIONBUTTON" .. index
                end

                local key1 = bindingAction and GetBindingKey(bindingAction)
                local textValue = key1 and FormatHotkeyText(key1) or ""
                if textValue == RANGE_INDICATOR or textValue == "\226\128\162" then
                    textValue = ""
                end
                hotkeyText:SetText(textValue)
                hotkeyText:Show()
                CludesUI.ApplyIconTextFont(hotkeyText, fontFile, kbSize, "actionBars")
                hotkeyText:SetTextColor(kbColor.r, kbColor.g, kbColor.b)
                -- Anchor unset (the default) = the stock placement below; the
                -- nil test is the whole cost of the feature while it is off.
                if not (kbAnchor and ABAR.PlaceButtonText(hotkeyText, button, kbAnchor, kbOX, kbOY)) then
                    hotkeyText:ClearAllPoints()
                    hotkeyText:SetPoint("TOPRIGHT", button, "TOPRIGHT", -1 + kbOX, -3 + kbOY)
                    hotkeyText:SetPoint("TOPLEFT", button, "TOPLEFT", 4 + kbOX, -3 + kbOY)
                    hotkeyText:SetJustifyH("RIGHT")
                end
            end
        end

        -- Count / charges text
        local countText = button.Count
        if countText then
            CludesUI.ApplyIconTextFont(countText, fontFile, ctSize, "actionBars")
            countText:SetTextColor(ctColor.r, ctColor.g, ctColor.b)
            if not (ctAnchor and ABAR.PlaceButtonText(countText, button, ctAnchor, ctOX, ctOY)) then
                countText:ClearAllPoints()
                countText:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1 + ctOX, 4 + ctOY)
                countText:SetJustifyH("RIGHT")
            end
        end

        -- Macro name text
        local macroName = button.Name
        if macroName then
            if hideMacro then
                macroName:SetAlpha(0)
            else
                macroName:SetAlpha(1)
                CludesUI.PrimeFontShadow(macroName, false)
                macroName:SetFont(fontFile, macroSize, (CludesUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG")
                macroName:SetTextColor(macroColor.r, macroColor.g, macroColor.b)
                if not (macroAnchor and ABAR.PlaceButtonText(macroName, button, macroAnchor, macroOX, macroOY)) then
                    macroName:ClearAllPoints()
                    macroName:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 1 + macroOX, 4 + macroOY)
                    macroName:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1 + macroOX, 4 + macroOY)
                    macroName:SetJustifyH("CENTER")
                end
            end
        end
    end
end

function ABAR:ApplyFonts()
    for _, details in ipairs(BAR_CONFIG) do
        self:ApplyFontsForBar(details.key)
    end
    self:ApplyCooldownFonts()
end

-- Color-only re-assert for custom keybind text colors. Blizzard's button
-- refreshes (UpdateAction/UpdateHotkeys, usable-state recolor) reset HotKey's
-- text color, reverting a custom color to white on target change, combat
-- transitions, drag-and-drop, and usability flips until the next full
-- ApplyFonts. Re-applies ONLY the color -- no fonts, no anchors -- and does no
-- button work at all for bars on the default white.
function ABAR:ReapplyHotkeyColors()
    local barList = self.db and self.db.profile and self.db.profile.bars
    if not barList then
        return
    end
    for barId, buttons in pairs(barButtons) do
        local s = barList[barId]
        local color = s and not s.hideKeybind and s.keybindFontColor
        if color and (color.r ~= 1 or color.g ~= 1 or color.b ~= 1) then
            for index = 1, #buttons do
                local hotkeyText = buttons[index] and buttons[index].HotKey
                if hotkeyText then
                    hotkeyText:SetTextColor(color.r, color.g, color.b)
                end
            end
        end
    end
end

-- One deferred color pass per event burst: the dispatcher can see dozens of
-- ACTIONBAR_SLOT_CHANGED per second while mouseover-conditional macros
-- re-resolve, and the pending flag coalesces the burst into one next-frame
-- pass. State lives on EAB.
function ABAR:QueueHotkeyColorReassert()
    if self._kbColorPending then
        return
    end
    self._kbColorPending = true
    self._kbColorRunner = self._kbColorRunner
        or function()
            ABAR._kbColorPending = false
            ABAR:ReapplyHotkeyColors()
        end
    C_Timer_After(0, self._kbColorRunner)
end

-------------------------------------------------------------------------------
--  Cooldown Countdown Font Override
-------------------------------------------------------------------------------
function EAB_VTABLE.CooldownFonts.GetSettings(cfg)
    return (CludesUI.GetFontPath("actionBars")) or FONT_PATH,
        cfg.cooldownFontSize or 12,
        cfg.cooldownTextXOffset or 0,
        cfg.cooldownTextYOffset or 0,
        cfg.cooldownTextColor or { r = 1, g = 1, b = 1 },
        cfg.cooldownFontFit or false
end

-- Cap the configured countdown size against the button it must fit inside. The size is
-- absolute while the countdown string is Blizzard's, formatted in the CLIENT locale:
-- the two-character "5m" of an English client is five characters on other locales, so
-- one setting fits one client and overflows another. A textured border only HIDES the
-- spill (frame anchors OUTSIDE the button -- see ApplyBorderStyle); a solid border sits
-- on the edge and covers nothing. OPT-IN per bar (cdFit, "Fit Size to Button"): the
-- configured size wins unless the bar opts in, so the off path returns it untouched.
function EAB_VTABLE.CooldownFonts.EffectiveSize(cdFrame, cdSize, cdFit)
    if not cdFit then
        return cdSize
    end
    local owner = cdFrame and (cdFrame:GetParent() or cdFrame)
    if not (owner and owner.GetWidth and owner.GetHeight) then
        return cdSize
    end
    local wid, hgt = owner:GetWidth(), owner:GetHeight()
    if not wid or not hgt or wid <= 0 or hgt <= 0 then
        return cdSize -- not laid out yet; re-applied on the next layout pass
    end
    -- Smaller dimension, not width: buttonWidth and buttonHeight are separate
    -- settings, so a wide short button still overflows vertically. The tighter
    -- axis is the one that constrains.
    local size = (wid < hgt) and wid or hgt
    local cap = math.floor(size * 0.40)
    if cap < 5 then
        cap = 5
    end -- never shrink to illegibility
    return (cdSize > cap) and cap or cdSize
end

function EAB_VTABLE.CooldownFonts.ApplyToFrame(cdFrame, fontFile, cdSize, cdOX, cdOY, cdColor, cdFit)
    if not cdFrame then
        return false
    end

    -- Stamp on the EFFECTIVE size, not requested: keyed to the request, a bar
    -- resize would leave the setting unchanged, match the stamp, and freeze
    -- the old size. Toggling the fit option changes eff too, so that flip re-applies.
    local eff = EAB_VTABLE.CooldownFonts.EffectiveSize(cdFrame, cdSize, cdFit)

    -- Skip if these exact settings were already applied to this frame
    local cdfd = EFD(cdFrame)
    local stamp = cdfd.cdFontStamp
    local cr, cg, callback = cdColor.r, cdColor.g, cdColor.b
    if
        stamp
        and stamp[1] == fontFile
        and stamp[2] == eff
        and stamp[3] == cdOX
        and stamp[4] == cdOY
        and stamp[5] == cr
        and stamp[6] == cg
        and stamp[7] == callback
    then
        return true
    end

    local regions = { cdFrame:GetRegions() }
    for ri = 1, #regions do
        local regionFrame = regions[ri]
        if regionFrame and regionFrame.GetObjectType and regionFrame:GetObjectType() == "FontString" then
            CludesUI.ApplyIconTextFont(regionFrame, fontFile, eff, "actionBars")
            regionFrame:SetTextColor(cr, cg, callback)
            regionFrame:ClearAllPoints()
            regionFrame:SetPoint("CENTER", cdFrame, "CENTER", cdOX, cdOY)
            cdfd.cdFontStamp = { fontFile, eff, cdOX, cdOY, cr, cg, callback }
            return true
        end
    end

    return false
end

function EAB_VTABLE.CooldownFonts.ApplyToButton(button, fontFile, cdSize, cdOX, cdOY, cdColor, cdFit)
    if not button then
        return
    end

    local applied =
        EAB_VTABLE.CooldownFonts.ApplyToFrame(button.cooldown, fontFile, cdSize, cdOX, cdOY, cdColor, cdFit)
    -- Retry when EITHER frame failed: the charge cooldown's FontString is
    -- created later than the main one's, so a main-only gate would strand the
    -- recharge countdown in Blizzard's default font permanently.
    local appliedCharge = not button.chargeCooldown
        or EAB_VTABLE.CooldownFonts.ApplyToFrame(
            button.chargeCooldown,
            fontFile,
            cdSize,
            cdOX,
            cdOY,
            cdColor,
            cdFit
        )
    if applied and appliedCharge then
        return
    end

    -- Some cooldown frames create their countdown FontString lazily on the
    -- first update after SetCooldown(). Retry once on the next frame.
    C_Timer_After(0, function()
        EAB_VTABLE.CooldownFonts.ApplyToFrame(button.cooldown, fontFile, cdSize, cdOX, cdOY, cdColor, cdFit)
        EAB_VTABLE.CooldownFonts.ApplyToFrame(
            button.chargeCooldown,
            fontFile,
            cdSize,
            cdOX,
            cdOY,
            cdColor,
            cdFit
        )
    end)
end

function ABAR:ApplyCooldownFontsForBar(barId)
    local barCfg = self.db.profile.bars[barId]
    if not barCfg then
        return
    end
    local buttons = barButtons[barId]
    if not buttons then
        return
    end
    local fontFile, cdSize, cdOX, cdOY, cdColor, cdFit = EAB_VTABLE.CooldownFonts.GetSettings(barCfg)

    C_Timer.After(0, function()
        for index = 1, #buttons do
            local button = buttons[index]
            if not button then
                break
            end
            EAB_VTABLE.CooldownFonts.ApplyToButton(button, fontFile, cdSize, cdOX, cdOY, cdColor, cdFit)
        end
    end)
end

function ABAR:ApplyCooldownFonts()
    EAB_VTABLE.CooldownFonts.HookAll()
    for _, details in ipairs(BAR_CONFIG) do
        self:ApplyCooldownFontsForBar(details.key)
    end
end

-- Equipped Item Color, live: every square button's Border takes the look
-- (and shows on an equipped item's button, in its rarity color) or hides
-- again. The Blizzard and Classic styles keep their own equipped border, so
-- CludesUI style only. changedOnly (ApplyAll: profile / spec switches,
-- imports) repaints only when the value differs from the one last painted;
-- the first pass just records it, as button setup painted from it.
function ABAR:ApplyEquippedBorder(changedOnly)
    local enabled = self.db.profile.showEquippedBorder and true or false
    local was = mod._eabEqBorderOn
    mod._eabEqBorderOn = enabled
    if changedOnly and (was == nil or was == enabled) then
        return
    end
    if mod.AB_Style() ~= "cui" then
        return
    end
    for _, details in ipairs(BAR_CONFIG) do
        local buttonList = barButtons[details.key]
        if buttonList then
            for _, button in ipairs(buttonList) do
                local bd = button.Border
                if bd and EFD(button).squared then
                    if enabled then
                        mod.AB_SyncEquippedBorder(button, button:GetAttribute("action"))
                    else
                        bd:Hide()
                        bd:SetAlpha(0)
                    end
                end
            end
        end
    end
end

-- Immediate re-apply of the count alpha (a bar's Charge Numbers and Hide Count
-- at 0) on one bar's buttons, or every bar's with no key, so an options change
-- applies on click instead of waiting for the next count event. Alpha only --
-- the count TEXT stays whatever its owners last wrote. Cold path: options
-- clicks only.
function ABAR:RefreshCountVisibility(barId)
    if not (C_ActionBar and C_ActionBar.GetActionDisplayCount) then
        return
    end
    for _, details in ipairs(BAR_CONFIG) do
        if not details.isStance and not details.isPetBar and (barId == nil or details.key == barId) then
            local buttonList = barButtons[details.key]
            if buttonList then
                for _, button in ipairs(buttonList) do
                    if button.Count then
                        local action = button:GetAttribute("action")
                        if action and HasAction(action) then
                            -- The count alpha finds the bar by this key.
                            local fd = EFD(button)
                            fd.barKey = details.key
                            mod._EABZeroCountAlpha(
                                fd,
                                button.Count,
                                C_ActionBar.GetActionDisplayCount(action),
                                action
                            )
                        end
                    end
                end
            end
        end
    end
end

function ABAR:RefreshAllCounts()
    self:RefreshCountVisibility()
end

-- Re-apply "Alpha on Cooldown" across every action button: on setting change (immediate
-- feedback plus a clean restore to full alpha at 100) and on the main apply. Same
-- secret-safe curve detection as the live ACTIONBAR_UPDATE_COOLDOWN handler.
function ABAR:ApplyCDAlphaAll()
    local profileDB = self.db and self.db.profile
    local cdAlpha = (profileDB and profileDB.alphaWhenOnCD) or 100
    local enabled = cdAlpha ~= 100
    -- This used to carry its own copy of the on-cooldown test, and the copy
    -- drifted: it treated ANY charge spell as being on a real cooldown, so
    -- touching the slider (or any full apply) during a GCD dimmed every charge
    -- spell sitting at full charges. Delegate to the live classifier instead,
    -- which owns the GCD threshold and the charge rules in one place. Restore
    -- to full alpha first so setting the slider back to 100 -- and every button
    -- the classifier declines to dim -- lands on a clean icon.
    for _, details in ipairs(BAR_CONFIG) do
        if not details.isStance and not details.isPetBar then
            local buttonList = barButtons[details.key]
            if buttonList then
                for _, button in ipairs(buttonList) do
                    local iconTex = button and button.icon
                    if iconTex then
                        iconTex:SetAlpha(1)
                        if enabled and ABAR._RefreshCooldownVisuals then
                            ABAR._RefreshCooldownVisuals(button)
                        end
                    end
                end
            end
        end
    end
end

function ABAR:ApplySlotBackgroundColor()
    local profileDB = self.db and self.db.profile
    if not profileDB then
        return
    end
    local color = profileDB.slotBgColor or { r = 0.15, g = 0.15, b = 0.15 }
    local a = profileDB.slotBgOpacity
    if a == nil then
        a = 50
    end
    a = a / 100
    for _, details in ipairs(BAR_CONFIG) do
        local buttonList = barButtons[details.key]
        if buttonList then
            for _, button in ipairs(buttonList) do
                local buttonData = button and EFD(button)
                if buttonData and buttonData.slotBG then
                    buttonData.slotBG:SetColorTexture(color.r or 0.15, color.g or 0.15, color.b or 0.15, a)
                end
            end
        end
    end
end

-- Custom cooldown-swipe color + opacity on every button's cooldown. Cheap and
-- idempotent (SetSwipeColor persists on the frame), so it runs on the main apply
-- and on setting change. Defaults mirror the Blizzard look.
function ABAR:ApplyCooldownSwipeColor()
    local profileDB = self.db and self.db.profile
    if not profileDB then
        return
    end
    local color = profileDB.cdSwipeColor or { r = 0, g = 0, b = 0 }
    local a = (profileDB.cdSwipeAlpha or 80) / 100
    for _, details in ipairs(BAR_CONFIG) do
        local buttonList = barButtons[details.key]
        if buttonList then
            for _, button in ipairs(buttonList) do
                local cd = button and button.cooldown
                if cd and cd.SetSwipeColor then
                    pcall(cd.SetSwipeColor, cd, color.r or 0, color.g or 0, color.b or 0, a)
                end
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Bar Background
-------------------------------------------------------------------------------
local barBackgrounds = {} -- [barKey] = { fill = Texture, border = Frame }

function ABAR:ApplyBackgroundForBar(barId)
    local barCfg = self.db.profile.bars[barId]
    if not barCfg then
        return
    end
    local widget = barFrames[barId]
    if not widget then
        return
    end

    if not barCfg.bgEnabled then
        local bgTex = barBackgrounds[barId]
        if bgTex then
            bgTex.fill:Hide()
            if CludesUI and CludesUI.ApplyBorderStyle then
                CludesUI.ApplyBorderStyle(bgTex.border, 0, 0, 0, 0, barCfg.bgBorderTexture or "solid")
            else
                bgTex.border:Hide()
            end
        end
        return
    end

    local bgTex = barBackgrounds[barId]
    if not bgTex then
        local fillTex = widget:CreateTexture(nil, "BACKGROUND", nil, -1)
        local border = CreateFrame("Frame", nil, widget, "BackdropTemplate")
        border:EnableMouse(false)
        border:SetFrameLevel(math.max(0, widget:GetFrameLevel()))
        bgTex = { fill = fillTex, border = border }
        barBackgrounds[barId] = bgTex
    end

    local color = barCfg.bgColor or { r = 0, g = 0, b = 0, a = 0.5 }
    local alpha = barCfg.bgOpacity ~= nil and barCfg.bgOpacity / 100 or color.a
    bgTex.fill:SetColorTexture(color.r, color.g, color.b, alpha)
    -- bgPadX/bgPadY remain as fallbacks for profiles predating bgPadding.
    local pad = barCfg.bgPadding
    local padX = pad ~= nil and pad or (barCfg.bgPadX or 0)
    local padY = pad ~= nil and pad or (barCfg.bgPadY or 0)
    local multiplierX = math.max(1, math.min(4, math.floor((barCfg.bgMultiplierX or 1) + 0.5)))
    local multiplierY = math.max(1, math.min(4, math.floor((barCfg.bgMultiplierY or 1) + 0.5)))
    local directionX = barCfg.bgExpandDirectionX or "right"
    local directionY = barCfg.bgExpandDirectionY or "up"
    local iconPadding = barCfg.buttonPadding or 0
    local growX = (multiplierX - 1) * ((widget:GetWidth() or 0) + iconPadding)
    local growY = (multiplierY - 1) * ((widget:GetHeight() or 0) + iconPadding)
    local leftX, right, topY, bottom = -padX, padX, padY, -padY
    if directionX == "left" then
        leftX = leftX - growX
    else
        right = right + growX
    end
    if directionY == "down" then
        bottom = bottom - growY
    else
        topY = topY + growY
    end
    bgTex.fill:ClearAllPoints()
    bgTex.fill:SetPoint("TOPLEFT", widget, "TOPLEFT", leftX, topY)
    bgTex.fill:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", right, bottom)
    bgTex.fill:Show()

    local border = bgTex.border
    border:SetFrameLevel(
        barCfg.bgBorderBehind and math.max(0, widget:GetFrameLevel() - 1) or widget:GetFrameLevel()
    )
    border:ClearAllPoints()
    border:SetPoint("TOPLEFT", widget, "TOPLEFT", leftX, topY)
    border:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", right, bottom)
    if CludesUI and CludesUI.ApplyBorderStyle then
        local bc = barCfg.bgBorderColor or { r = 0, g = 0, b = 0, a = 1 }
        local thicknessKey = barCfg.bgBorderThickness or "none"
        local thickness = mod.BORDER_THICKNESS and mod.BORDER_THICKNESS[thicknessKey]
        local borderSize = thickness and thickness.regular or 0
        -- Exact size (bgBorderThicknessPx) while it pairs with this step and texture; nil = legacy path.
        local bgPx = CludesUI.BorderPx(barCfg.bgBorderThicknessPx, borderSize, barCfg.bgBorderTexture)
        CludesUI.ApplyBorderStyle(
            border,
            borderSize,
            bc.r,
            bc.g,
            bc.b,
            bc.a or 1,
            barCfg.bgBorderTexture or "solid",
            barCfg.bgBorderOffsetX,
            barCfg.bgBorderOffsetY,
            barCfg.bgBorderShiftX,
            barCfg.bgBorderShiftY,
            "actionbars",
            thicknessKey,
            nil,
            bgPx
        )
    else
        border:Hide()
    end
end

-------------------------------------------------------------------------------
--  Blizzard Icon Background (per-button slot texture)
-------------------------------------------------------------------------------
function ABAR:ApplyIconBackgroundForBar(barId)
    local pr = self.db.profile
    local buttons = barButtons[barId]
    if not buttons then
        return
    end
    local show = pr.showBlizzIconBg or false
    -- Session gate for the per-button OnEvent hook below: feature defaults
    -- OFF and the hook rides every event every button receives, so the
    -- disabled path must cost one boolean. This apply pass owns the visuals
    -- on every settings edge, so the flag can't go stale.
    mod._iconBgOn = show
    local alpha = pr.blizzIconBgAlpha or 1
    local blizzStyle = mod.AB_Style() ~= "cui"
    local inset = blizzStyle and 0 or 4
    for index = 1, #buttons do
        local button = buttons[index]
        if not button then
            break
        end
        local buttonData = EFD(button)
        if not show then
            -- Disabled (the default): build nothing. Only a clip left over
            -- from an earlier ON has anything to hide; every other reader of
            -- iconBg / iconBgClip (slot sync, shape masks) nil-checks.
            if buttonData.iconBgClip then
                buttonData.iconBgClip:Hide()
            end
        else
            -- Only show icon background on empty slots
            local okHA, hasAction = pcall(button.HasAction, button)
            hasAction = okHA and hasAction
            if not buttonData.iconBgClip then
                local clip = CreateFrame("Frame", nil, button)
                clip:SetAllPoints(button)
                clip:SetClipsChildren(true)
                clip:SetFrameLevel(math.max(1, button:GetFrameLevel() - 1))
                clip:EnableMouse(false)
                local backdrop = clip:CreateTexture(nil, "BACKGROUND", nil, -1)
                -- Built once; the look is reload-gated, so the stock looks
                -- take the retail slot art here for the session.
                if blizzStyle then
                    mod.AB_StockAtlas(backdrop, "UI-HUD-ActionBar-IconFrame-Slot")
                else
                    backdrop:SetAtlas("UI-HUD-ActionBar-IconFrame-Slot")
                end
                buttonData.iconBgClip = clip
                buttonData.iconBg = backdrop
            end
            -- Auto-update on button events. ACTIONBAR_SLOT_CHANGED is not
            -- delivered to buttons (central dispatcher owns it and syncs the
            -- clip there); this hook covers the remaining per-button events.
            -- Installed on the first ON edge only: a script hook rides every
            -- event every button receives and cannot be removed, so a
            -- session that never enables the feature never pays even its
            -- early-return. The EFD flag survives bar rebuilds that reuse
            -- the button frame, so the hook never stacks.
            if not buttonData.iconBgHooked then
                buttonData.iconBgHooked = true
                button:HookScript("OnEvent", function(self)
                    -- Feature gate FIRST: turned off later in the session, the
                    -- hook must cost one boolean. The apply pass hides a
                    -- freshly-disabled clip on the settings edge, never this hook.
                    if not mod._iconBgOn then
                        return
                    end
                    local sfd = EFD(self)
                    local c = sfd.iconBgClip
                    if c then
                        local okHA, ha = pcall(self.HasAction, self)
                        c:SetShown(not (okHA and ha))
                    end
                end)
            end
            buttonData.iconBg:ClearAllPoints()
            buttonData.iconBg:SetPoint("TOPLEFT", button, "TOPLEFT", -inset, inset)
            buttonData.iconBg:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", inset, -inset)
            buttonData.iconBg:SetAlpha(alpha)
            -- Apply custom shape mask if active (shapes run before this)
            if buttonData.shapeMask and buttonData.shapeApplied then
                pcall(buttonData.iconBg.AddMaskTexture, buttonData.iconBg, buttonData.shapeMask)
            end
            buttonData.iconBgClip:SetShown(not hasAction)
        end
    end
end

-------------------------------------------------------------------------------
--  Always Show Buttons
-------------------------------------------------------------------------------
function ABAR:ApplyAlwaysShowButtons(barId)
    -- Hard-dormant bars skip the whole pass; the dormancy reveal reconcile
    -- runs it once when a settings edge brings the bar back.
    if mod._eabBarNever[barId] then
        return
    end
    local barCfg = self.db.profile.bars[barId]
    if not barCfg then
        return
    end
    local details = BAR_LOOKUP[barId]
    if not details then
        return
    end
    local buttons = barButtons[barId]
    if not buttons then
        return
    end
    local showEmpty = barCfg.alwaysShowButtons
    if showEmpty == nil then
        showEmpty = true
    end
    -- Stance bar always hides empty slots (count is dynamic per class)
    if details.isStance then
        showEmpty = false
    end

    -- Respect icon cutoff (hoisted above the grid half so the signature
    -- below sees every input)
    local numIcons = barCfg.overrideNumIcons or barCfg.numIcons or details.count
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

    local quickKeybindVisible = ShouldQuickKeybindSurfaceBar(barCfg)
    local clickable = quickKeybindVisible or not barCfg.clickThrough

    -- Default-config fast path. With Always Show Buttons ON, per-button visibility is
    -- CONSTANT (visible regardless of slot contents), so a pass that already asserted
    -- this configuration has nothing content-dependent left to do -- yet form/page
    -- flips queue it per tick at ~140 secure-attribute reads plus idempotent writes.
    -- The signature covers every input; settings changes alter it, drag restores wipe
    -- the stamp table, and combat passes never stamp (skipped writes heal on the next
    -- unlocked pass). Hide-empty bars always run: visibility tracks slot contents.
    local asbSig = (showEmpty and 1 or 0)
        + (quickKeybindVisible and 2 or 0)
        + (clickable and 4 or 0)
        + numIcons * 8
    local asbSt = mod._asbStamp
    if not asbSt then
        asbSt = {}
        mod._asbStamp = asbSt
    end
    if showEmpty and asbSt[barId] == asbSig and not _gridState.shown and not InCombatLockdown() then
        return
    end

    -- Update the SHOWGRID.ALWAYS flag on managed action buttons
    if not InCombatLockdown() and not details.isStance and not details.isPetBar then
        for _, button in ipairs(buttons) do
            if button then
                SetShowGridInsecure(button, showEmpty, SHOWGRID.ALWAYS)
                -- Heal transient drag/spellbook bits. A COMBAT drag reveals
                -- empty slots through the secure path (which honors these bits),
                -- but its HIDEGRID can land while the insecure handler is
                -- combat-gated, leaving a stuck bit that keeps empty slots
                -- visible after combat. Runs from the post-drag re-assert and
                -- the regen-deferred ApplyAll, both outside any live drag.
                if not _gridState.shown then
                    SetShowGridInsecure(button, false, SHOWGRID.GAME_EVENT)
                    SetShowGridInsecure(button, false, SHOWGRID.SPELLBOOK)
                end
            end
        end
    end

    -- During a spell drag, we leave the controller's secure visibility path
    -- alone. QuickKeybind still needs the normal visibility refresh so its
    -- dedicated KEYBOUND flag can show empty slots on EAB-owned bars.
    if _gridState.shown and not _quickKeybindState.open then
        return
    end
    -- The loop below rewrites the pet buttons from live state: drop the pet
    -- handler's shape memo so its next full pass lays them out again.
    if details.isPetBar then
        mod._eabPetLayoutSig = nil
    end
    local lastVisible = 0
    for index = 1, numIcons do
        local button = buttons[index]
        if button then
            if details.nativeMainBar then
                EAB_VTABLE.MainBarPageSync.SetButtonConfig(button, true, showEmpty)
            end
            local isVisible = showEmpty or quickKeybindVisible or not mod.AB_EmptySlot(button, details)

            local buttonData = EFD(button)
            if buttonData.slotBG then
                buttonData.slotBG:SetShown(isVisible)
            end
            if buttonData.borders and not (buttonData.shapeMask and buttonData.shapeMask:IsShown()) then
                buttonData.borders:SetShown(isVisible)
            end
            if buttonData.shapeBorder then
                buttonData.shapeBorder:SetShown(isVisible and EFD(buttonData.shapeBorder).wantsShow == true)
            end

            -- Stamp the secure-side facts the restricted reveal needs
            -- (see the SetShowGrid snippet): this button is within the icon
            -- cutoff, whether empty slots are shown at all, and whether a
            -- reveal may enable mouse clicks. eab-showempty is what lets the
            -- paging snippet (ns._eabPageVisSnippet) re-evaluate a parked slot
            -- during combat on every bar, not just MainBar -- without it a
            -- custom-paged bar 2-10 leaves the slot statehidden for the whole
            -- fight.
            if not InCombatLockdown() then
                button:SetAttributeNoHandler("eab-withincutoff", 1)
                button:SetAttributeNoHandler("eab-showempty", showEmpty and 1 or 0)
                button:SetAttributeNoHandler("eab-click", clickable and 1 or 0)
            end
            if not isVisible then
                button:SetAlpha(0)
                -- Invisible empty slots must not catch mouse events; statehidden
                -- makes the secure UpdateShown snippet keep them hidden.
                SafeEnableMouse(button, false)
                if not InCombatLockdown() then
                    button:SetAttributeNoHandler("statehidden", true)
                    button:Hide()
                    mod._eabMarkParked(button, details, true)
                else
                    mod._eabMarkParked(button, details)
                end
            else
                if not InCombatLockdown() then
                    button:SetAttributeNoHandler("statehidden", nil)
                    button:SetAttribute("showgrid", 1)
                    button:Show()
                end
                -- Always restore button alpha to 1. The bar frame's own
                -- alpha (via mouseover fade) handles overall visibility.
                button:SetAlpha(1)
                buttonData.parkA0 = nil
                -- Restore mouse state based on bar's click-through setting.
                -- When click-through is on but mouseover is enabled, keep
                -- mouse motion so OnEnter/OnLeave still fire for hover fade.
                if clickable then
                    SafeEnableMouse(button, true)
                elseif barCfg.mouseoverEnabled then
                    SafeEnableMouseMotionOnly(button, true)
                else
                    SafeEnableMouse(button, false)
                end
                lastVisible = index
            end
        end
    end
    -- Hide buttons beyond cutoff
    for index = numIcons + 1, #buttons do
        local button = buttons[index]
        if button then
            if details.nativeMainBar then
                EAB_VTABLE.MainBarPageSync.SetButtonConfig(button, false, showEmpty)
            end
            button:SetAlpha(0)
            SafeEnableMouse(button, false)
            if not InCombatLockdown() then
                -- Cutoff buttons are excluded from the secure drag reveal:
                -- revealing them would paint slots the user configured away.
                button:SetAttributeNoHandler("eab-withincutoff", 0)
                button:SetAttributeNoHandler("eab-showempty", showEmpty and 1 or 0)
                button:SetAttributeNoHandler("statehidden", true)
                button:Hide()
                mod._eabMarkParked(button, details, true)
            else
                mod._eabMarkParked(button, details)
            end
        end
    end

    -- Stamp only fully-applied passes: a combat pass skipped its secure
    -- writes and must not suppress the healing re-run.
    if not InCombatLockdown() then
        asbSt[barId] = asbSig
    else
        asbSt[barId] = nil
    end

    -- Frame size stays as LayoutBar left it: the mouseover OnEnter handler
    -- already checks cursor proximity to visible buttons, and shrinking the
    -- frame can misposition bars whose anchor point is not TOPLEFT.
end

-------------------------------------------------------------------------------
--  Main Bar Page Sync: EAB owns MainBar paging via a custom secure parent, so
--  Blizzard's stock ActionBarController never runs its "set actionpage, then
--  refresh every button" sequence for ActionButton1-12 (the actionpage half is
--  mirrored onto MainActionBar by the MainBar _onstate-page handler). Restored by tracking
--  page-sensitive visibility inputs on the buttons, then using a secure
--  child-update from the MainBar frame to drive the buttons' normal
--  OnAttributeChanged -> UpdateAction path in combat.
-------------------------------------------------------------------------------
-- A combat pass (every page flip and spell swap) owes the main bar's own
-- AlwaysShow pass once combat ends, never a full ApplyAll: the regen handler
-- runs it from ns._eabMainBarAsbOwed.
function EAB_VTABLE.MainBarPageSync.SetButtonConfig(button, withinCutoff, showEmpty)
    if not button then
        return
    end
    if InCombatLockdown() then
        mod._eabMainBarAsbOwed = true
        return
    end
    button:SetAttributeNoHandler("eab-withincutoff", withinCutoff and 1 or 0)
    button:SetAttributeNoHandler("eab-showempty", showEmpty and 1 or 0)
end

function EAB_VTABLE.MainBarPageSync.Queue()
    local status = EAB_VTABLE.MainBarPageSync
    if status.pending then
        return
    end
    status.pending = true
    C_Timer_After(0, function()
        status.pending = false
        if InCombatLockdown() then
            mod._eabMainBarAsbOwed = true
            return
        end
        if not ABAR or not ABAR.db then
            return
        end
        ABAR:ApplyAlwaysShowButtons("MainBar")
    end)
end

function EAB_VTABLE.MainBarPageSync.InstallAll()
    if InCombatLockdown() then
        mod._eabApplyDeferred = true
        return
    end
    local buttons = barButtons["MainBar"]
    if not buttons then
        return
    end
    for _, button in ipairs(buttons) do
        EAB_VTABLE.MainBarPageSync.InstallButton(button)
    end
end

function EAB_VTABLE.MainBarPageSync.InstallButton(button)
    if not button or button:GetAttribute("_eabPageSyncInstalled") or InCombatLockdown() then
        return
    end

    -- Bake the base index directly into the snippet as a literal so it
    -- doesn't depend on attribute reads in the restricted environment.
    local details = buttonToBar[button]
    local baseIdx = details and details.index or 1

    -- Only the slot arithmetic is interpolated. The body is concatenated raw:
    -- it contains a modulo, and string.format eats a bare "%" as a broken
    -- conversion spec.
    button:SetAttributeNoHandler("_childupdate-eab-page", ([[
        local page = tonumber(message) or 1
        local slot = %d + (page - 1) * %d
        self:SetAttribute("action", slot)
    ]]):format(baseIdx, NUM_ACTIONBAR_BUTTONS) .. [[
        local withinCutoff = self:GetAttribute("eab-withincutoff") ~= 0
        local visible = withinCutoff

        if visible and self:GetAttribute("eab-showempty") == 0 then
            visible = HasAction(slot)
        end

        -- Transient grid reveal outranks the empty-slot park (see
        -- ns._eabPageVisSnippet, which carries the same rule for bars 2-10):
        -- a page flip during a combat spell drag must not delete the drop
        -- targets. Bits 2+ only -- bit 1 is Blizzard's CVAR reason.
        local grid = self:GetAttribute("showgrid") or 0
        local transient = withinCutoff and (grid % 32) >= 2

        local hidden = self:GetAttribute("statehidden")
        local changed = false

        if visible or transient then
            if visible and hidden then
                self:SetAttribute("statehidden", nil)
                changed = true
            end
    ]] .. mod._eabPageUnparkSnippet .. [[
            self:Show(true)
        else
            if not hidden then
                self:SetAttribute("statehidden", true)
                changed = true
            end
            self:Hide(true)
        end

        if not changed then
            local token = self:GetAttribute("eab-pagesync-token") or 0
            self:SetAttribute("eab-pagesync-token", token == 0 and 1 or 0)
        end
    ]])

    button:SetAttributeNoHandler("_eabPageSyncInstalled", true)
end
