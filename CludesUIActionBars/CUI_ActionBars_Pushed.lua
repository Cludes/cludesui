if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_ActionBars_Pushed.lua
--
--  Pushed and highlight textures, the border edge lines they draw, the
--  Match Bar Border copies and the pushed-state flash. Loads after the main
--  file and reads it through ns only.
-------------------------------------------------------------------------------
local _, mod = ...

local ipairs, pairs = ipairs, pairs
local InCombatLockdown = InCombatLockdown
local hooksecurefunc = hooksecurefunc
local GetBindingKey = GetBindingKey
local EFD = mod.EFD

local ABAR, barButtons = mod.EAB, mod.barButtons
local HIGHLIGHT_TEXTURES, ResolveBorderThickness = mod.HIGHLIGHT_TEXTURES, mod.ResolveBorderThickness
local Inner = mod._internals
local BAR_CONFIG, _quickKeybindState = Inner.BAR_CONFIG, Inner._quickKeybindState
local SetSquareTexture, _controllerButtons, allButtons =
    Inner.SetSquareTexture, Inner._controllerButtons, Inner.allButtons

-------------------------------------------------------------------------------
--  Pushed / Highlight Textures
--  These are global settings that apply to ALL action bar buttons.
-------------------------------------------------------------------------------
local PUSHED_TYPES = {
    [1] = "light", -- Light overlay
    [2] = "medium", -- Medium overlay
    [3] = "strong", -- Strong overlay
    [4] = "solid", -- Solid color fill
    [5] = "border", -- Border only
    [6] = "none", -- No pushed effect
}

do
    local function _setupBorderEdges(button, storeKey, driverTex)
        -- Edge state lives in EFD, never on the button table: StanceBar/PetBar
        -- flow through here with BLIZZARD-owned buttons (StanceButton/
        -- PetActionButton), which must never receive custom keys.
        local edges = EFD(button)[storeKey]
        if not edges then
            edges = {}
            for jdx = 1, 4 do
                local tex = button:CreateTexture(nil, "OVERLAY", nil, 2)
                tex:SetColorTexture(1, 1, 1, 1)
                tex:Hide()
                edges[jdx] = tex
            end
            EFD(button)[storeKey] = edges
            if driverTex then
                hooksecurefunc(driverTex, "Show", function()
                    if not edges._active then return end
                    for jdx = 1, 4 do
                        edges[jdx]:Show()
                    end
                end)
                hooksecurefunc(driverTex, "Hide", function()
                    for jdx = 1, 4 do
                        edges[jdx]:Hide()
                    end
                end)
            end
        end
        return edges
    end

    local function _applyBorderEdges(edges, button, brdSize, cr, cg, callback)
        edges._active = true
        local anchor = button.icon or button.Icon or button
        local Pix = CludesUI.PP
        for jdx = 1, 4 do
            edges[jdx]:SetVertexColor(cr, cg, callback, 1)
        end
        edges[1]:ClearAllPoints()
        edges[1]:SetPoint("TOPLEFT", anchor)
        edges[1]:SetPoint("TOPRIGHT", anchor)
        if Pix then
            Pix.Height(edges[1], brdSize)
        else
            edges[1]:SetHeight(brdSize)
        end
        edges[2]:ClearAllPoints()
        edges[2]:SetPoint("BOTTOMLEFT", anchor)
        edges[2]:SetPoint("BOTTOMRIGHT", anchor)
        if Pix then
            Pix.Height(edges[2], brdSize)
        else
            edges[2]:SetHeight(brdSize)
        end
        edges[3]:ClearAllPoints()
        edges[3]:SetPoint("TOPLEFT", edges[1], "BOTTOMLEFT")
        edges[3]:SetPoint("BOTTOMLEFT", edges[2], "TOPLEFT")
        if Pix then
            Pix.Width(edges[3], brdSize)
        else
            edges[3]:SetWidth(brdSize)
        end
        edges[4]:ClearAllPoints()
        edges[4]:SetPoint("TOPRIGHT", edges[1], "BOTTOMRIGHT")
        edges[4]:SetPoint("BOTTOMRIGHT", edges[2], "TOPRIGHT")
        if Pix then
            Pix.Width(edges[4], brdSize)
        else
            edges[4]:SetWidth(brdSize)
        end
    end

    local function _hideBorderEdges(button, storeKey)
        local edges = EFD(button)[storeKey]
        if not edges then return end
        edges._active = false
        for jdx = 1, 4 do
            edges[jdx]:Hide()
        end
    end
    mod._setupBorderEdges = _setupBorderEdges
    mod._applyBorderEdges = _applyBorderEdges
    mod._hideBorderEdges = _hideBorderEdges
end

-------------------------------------------------------------------------------
--  Match Bar Border (the Pushed / Highlight Border Settings cogs and the Spell
--  Cast Highlight cog). On bars with a textured Border Style, a press, a hover
--  or the active spell lights up a tinted copy of the button's own border in
--  place of the flat edge lines (pushed / hover) or the checked fill (cast).
--  One copy per button, built the first time a role arms it on an eligible
--  bar, never for players who leave the options off: EFD(btn).ixBorder is a
--  wrapper frame and the only Show/Hide target, EFD(btn).ixHost inside it
--  carries the backdrop and stays shown, so neither a restyle nor the UI-scale
--  re-apply (CludesUI.ReapplyPxBorders) can flash or drop the copy. Roles
--  (EFD ixPush / ixHover / ixCast) are armed by the three Apply*Textures
--  passes; the live states (ixPressed / ixOver / ixChecked) come from hooks
--  whose bodies return at once unless their role is armed. ONE painter picks
--  pressed > spell cast > hover. While the copy shows, the bar border hides
--  through its own backdrop's alpha (our frame), never Hide(); the button's
--  own alpha is never read or written. All on ns: the main file and the
--  glow file reach them there.
-------------------------------------------------------------------------------

-- Tint slots (r, g, b, a), refilled in place by the pushed and highlight passes
-- while their role is on, so a paint allocates nothing.
mod._ixPushC = { 1, 1, 1, 1 }
mod._ixHlC = { 1, 1, 1, 1 }
-- [barKey] = the bar's last computed eligibility (GetCheckedAlpha reads it).
mod._ixElig = {}

-- Which roles are on, from the profile alone: each needs its own opt-in plus
-- the setting it restyles (Border pushed / highlight type, cast highlight on).
mod._ixRolesOn = function(profile)
    return (profile.pushedBorderMatchBar and (profile.pushedTextureType or 2) == 5) or false,
        (profile.highlightBorderMatchBar and (profile.highlightTextureType or 2) == 5) or false,
        (profile.castHighlightBorder and profile.showCastHighlight ~= false) or false
end

-- Bar eligibility: CludesUI style, square icons, a None or Cropped shape, a
-- textured Border Style that resolves to a file, Border Size above 0. Returns
-- it and whether it differs from the stored value (stored here).
mod._ixBarEligible = function(barId)
    local profile = ABAR.db.profile
    local cfg = profile.bars[barId]
    local success = false
    if cfg and profile.squareIcons and mod.AB_Style() == "cui" then
        local shape = cfg.buttonShape or "none"
        local texture = cfg.borderTexture or "solid"
        if
            (shape == "none" or shape == "cropped")
            and texture ~= ""
            and texture ~= "solid"
            and CludesUI.ResolveBorderTexture(texture)
        then
            success = ResolveBorderThickness(cfg) > 0
        end
    end
    local changed = mod._ixElig[barId] ~= success
    mod._ixElig[barId] = success
    return success, changed
end

-- Styles the copy exactly like the bar border: texture, step, exact size,
-- offsets, shifts, and the bar border's frame level (Show Behind / Border
-- Above Effects; ApplyBorderStyle resets the backdrop to the host's level, so
-- it is set again after). Keeps the current tint. Unmemoized, like the bar
-- border's own textured path. Callers keep it out of combat.
mod._ixStyle = function(button, fd, cfg)
    local owner = fd.ixHost
    local sz, px = ResolveBorderThickness(cfg)
    CludesUI.ApplyBorderStyle(
        owner,
        sz,
        fd.ixR or 1,
        fd.ixG or 1,
        fd.ixB or 1,
        fd.ixA or 1,
        cfg.borderTexture,
        cfg.borderTextureOffset,
        cfg.borderTextureOffsetY,
        cfg.borderTextureShiftX,
        cfg.borderTextureShiftY,
        "actionbars",
        cfg.borderThickness or "thin",
        nil,
        px
    )
    local edge = CludesUI._bdBorderData[owner]
    if edge then edge:SetFrameLevel(mod._eabBorderLevel(button, cfg.borderBehind, cfg.borderAboveEffects)) end
    fd.ixStyled = true
end

-- The one painter: pressed > spell cast > hover (cast and hover share the
-- highlight tint). Recolours only on a real change, shows and hides only on an
-- edge. Runs from hooks in and out of combat: our own frames only.
mod._ixPaint = function(button, fd)
    local wid = fd.ixBorder
    if not wid then return end
    local bdData = CludesUI._bdBorderData
    local edge = bdData[fd.ixHost]
    local c
    if edge then
        if fd.ixPressed and fd.ixPush then
            c = mod._ixPushC
        elseif (fd.ixChecked and fd.ixCast) or (fd.ixOver and fd.ixHover) then
            c = mod._ixHlC
        end
    end
    if c then
        local red, green, blue, a = c[1], c[2], c[3], c[4]
        if fd.ixR ~= red or fd.ixG ~= green or fd.ixB ~= blue or fd.ixA ~= a then
            fd.ixR, fd.ixG, fd.ixB, fd.ixA = red, green, blue, a
            edge:SetBackdropBorderColor(red, green, blue, a)
        end
        if not fd.ixLit then
            fd.ixLit = true
            local base = bdData[button]
            if base then
                fd.ixBaseA = base:GetAlpha()
                base:SetAlpha(0)
            end
            wid:Show()
        end
    elseif fd.ixLit then
        fd.ixLit = nil
        wid:Hide()
        local base = bdData[button]
        if base then base:SetAlpha(fd.ixBaseA or 1) end
    end
end

-- Pressed-state drivers, one shared function each. Bodies return unless the
-- pushed role is armed (or, to release, a press is recorded).
mod._ixPressOn = function(button)
    local fd = mod._eabFD[button]
    if fd and fd.ixPush and not fd.ixPressed then
        fd.ixPressed = true
        mod._ixPaint(button, fd)
    end
end
mod._ixPressOff = function(button)
    local fd = mod._eabFD[button]
    if fd and fd.ixPressed then
        fd.ixPressed = nil
        mod._ixPaint(button, fd)
    end
end

-- Installed once per button, the first time the pushed role arms it. The
-- keybind flash path shows and hides PushedTexture from Lua; a mouse press is
-- drawn by the engine with no Lua call, so the button's own mouse scripts
-- drive that half, and OnHide drops a press a hidden bar would strand. A drag
-- off the button may never deliver OnMouseUp, so OnDragStart drops it too, on
-- our own action buttons only (the Stance and Pet bars reuse Blizzard's).
mod._ixHookPress = function(button, fd)
    fd.ixPressHooked = true
    local pt = button.PushedTexture
    if pt then
        hooksecurefunc(pt, "Show", function() mod._ixPressOn(button) end)
        hooksecurefunc(pt, "Hide", function() mod._ixPressOff(button) end)
    end
    button:HookScript("OnMouseDown", mod._ixPressOn)
    button:HookScript("OnMouseUp", mod._ixPressOff)
    button:HookScript("OnHide", mod._ixPressOff)
    if _controllerButtons[button] then button:HookScript("OnDragStart", mod._ixPressOff) end
end

-- Reads the checked state and paints only when it really changed. A secret
-- value is skipped without a retry; the next SetChecked samples again.
mod._ixSampleChecked = function(button, fd)
    local c = button:GetChecked()
    if issecretvalue and issecretvalue(c) then return end
    c = c and true or nil
    if fd.ixChecked ~= c then
        fd.ixChecked = c
        mod._ixPaint(button, fd)
    end
end

-- Installed once per button, the first time the cast role arms it. Blizzard's
-- UpdateState and our own dispatcher both set the checked state through
-- SetChecked. The hooked argument is never read (it can be secret).
mod._ixHookChecked = function(button, fd)
    fd.ixCheckHooked = true
    hooksecurefunc(button, "SetChecked", function()
        local skinData = mod._eabFD[button]
        if skinData and skinData.ixCast then mod._ixSampleChecked(button, skinData) end
    end)
end

-- Arms (on) or disarms one role ("ixPush" / "ixHover" / "ixCast") on one
-- button; returns whether it is armed. The first arm builds and styles the
-- copy and installs the role's driver, out of combat only: a combat arm defers
-- to the regen ApplyAll and returns false, so the caller keeps its own look.
-- Dropping the last role hides the copy, restores the bar border's alpha and
-- takes the host out of the px re-apply registry (HideBorderStyle).
mod._ixRole = function(button, s, role, enabled)
    local fd = EFD(button)
    if enabled then
        local needHook = (role == "ixPush" and not fd.ixPressHooked)
            or (role == "ixCast" and not fd.ixCheckHooked)
        if not fd.ixStyled or needHook then
            if InCombatLockdown() then
                mod._eabApplyDeferred = true
                return false
            end
            if not fd.ixBorder then
                local wid = CreateFrame("Frame", nil, button)
                wid:SetAllPoints(button)
                wid:Hide()
                local owner = CreateFrame("Frame", nil, wid)
                owner:SetAllPoints(wid)
                fd.ixBorder, fd.ixHost = wid, owner
                mod._ixEver = true
            end
            if not fd.ixStyled then mod._ixStyle(button, fd, s) end
            if role == "ixPush" and not fd.ixPressHooked then mod._ixHookPress(button, fd) end
            if role == "ixCast" and not fd.ixCheckHooked then mod._ixHookChecked(button, fd) end
        end
        fd[role] = true
        -- A (re)armed cast role starts from the button's real state.
        if role == "ixCast" then mod._ixSampleChecked(button, fd) end
        mod._ixPaint(button, fd)
        return true
    elseif fd[role] then
        fd[role] = nil
        if role == "ixPush" then
            fd.ixPressed = nil
        elseif role == "ixHover" then
            fd.ixOver = nil
        else
            fd.ixChecked = nil
        end
        mod._ixPaint(button, fd)
        if fd.ixStyled and not (fd.ixPush or fd.ixHover or fd.ixCast) then
            CludesUI.HideBorderStyle(fd.ixHost)
            fd.ixStyled = nil
        end
    end
    return false
end

function ABAR:ApplyPushedTextures()
    local profile = self.db.profile
    local abStyle = mod.AB_Style()
    local pType = profile.pushedTextureType or 2
    local useCC = profile.pushedUseClassColor
    local customC = profile.pushedCustomColor or { r = 0.973, g = 0.839, b = 0.604, a = 1 }
    local brdSize = profile.pushedBorderSize or 4

    local cr, cg, callback = customC.r, customC.g, customC.b
    if useCC then
        local _, classTok = UnitClass("player")
        if classTok then
            local cc = RAID_CLASS_COLORS[classTok]
            if cc then
                cr, cg, callback = cc.r, cc.g, cc.b
            end
        end
    end

    -- Match Bar Border (pushed): eligible bars trade the flat edges for the
    -- button's own border copy, tinted with this colour and its alpha. Once a
    -- copy exists (ixEver), every path that does not arm the role disarms it.
    local ixOn = abStyle == "cui" and (mod._ixRolesOn(profile))
    if ixOn then
        local tbl = mod._ixPushC
        tbl[1], tbl[2], tbl[3], tbl[4] = cr, cg, callback, customC.a or 1
    end
    local ixEver = mod._ixEver

    for _, details in ipairs(BAR_CONFIG) do
        local buttons = barButtons[details.key]
        if buttons then
            local s = profile.bars[details.key]
            local ixBar = ixOn and mod._ixBarEligible(details.key)
            for index = 1, #buttons do
                local button = buttons[index]
                if button and button.PushedTexture then
                    if abStyle ~= "cui" then
                        if abStyle == "classic" then
                            -- Classic WoW UI: the vanilla depress art over the button.
                            button.PushedTexture:SetAtlas(nil)
                            button.PushedTexture:SetTexture(mod.AB_CLASSIC.pushed)
                            button.PushedTexture:SetTexCoord(0, 1, 0, 1)
                        elseif details.isStance or details.isPetBar then
                            -- Blizzard's buttons: its own art pass re-atlases them.
                            button.PushedTexture:SetAtlas("UI-HUD-ActionBar-IconFrame-Down", true)
                        else
                            mod.AB_StockAtlas(button.PushedTexture, "UI-HUD-ActionBar-IconFrame-Down", true)
                        end
                        button.PushedTexture:SetDrawLayer("OVERLAY", 7)
                        button.PushedTexture:ClearAllPoints()
                        button.PushedTexture:SetAllPoints(button)
                        button.PushedTexture:SetVertexColor(1, 1, 1, 1)
                        button.PushedTexture:SetAlpha(1)
                        mod._hideBorderEdges(button, "_pushedBorder")
                    elseif pType == 6 then
                        button.PushedTexture:SetAlpha(0)
                        mod._hideBorderEdges(button, "_pushedBorder")
                    elseif pType == 5 then
                        button.PushedTexture:SetAlpha(0)
                        if ixBar and mod._ixRole(button, s, "ixPush", true) then
                            mod._hideBorderEdges(button, "_pushedBorder")
                        else
                            local edges = mod._setupBorderEdges(button, "_pushedBorder", button.PushedTexture)
                            mod._applyBorderEdges(edges, button, brdSize, cr, cg, callback)
                        end
                    else
                        button.PushedTexture:SetAlpha(1)
                        mod._hideBorderEdges(button, "_pushedBorder")
                        if pType <= 3 then
                            SetSquareTexture(
                                button.PushedTexture,
                                HIGHLIGHT_TEXTURES[pType] or HIGHLIGHT_TEXTURES[2]
                            )
                            button.PushedTexture:SetVertexColor(cr, cg, callback, 1)
                        elseif pType == 4 then
                            button.PushedTexture:SetColorTexture(cr, cg, callback, 0.35)
                        end
                    end
                    -- Stock styles, other pushed types, the option off and
                    -- bars that left eligibility all land here.
                    if ixEver and not ixBar then mod._ixRole(button, s, "ixPush", false) end
                end
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Pushed-State Flash: SetOverrideBinding routes keybinds to native engine
--  commands (ACTIONBUTTON1 etc.) so the engine fires the action directly
--  without clicking our buttons, so they never enter PUSHED state from
--  keyboard. Fix: hook UseAction to show PushedTexture, global keyup watcher
--  to hide all active textures.
-------------------------------------------------------------------------------
do
    local _pushedHooked = false
    local _activePushed = {} -- btn -> true
    local _activePushedN = 0
    local _btnKeys = {} -- btn -> { k1, k2 } (reused, no alloc per press)
    local _pollFrame
    function ABAR:HookPushedFlash()
        if _pushedHooked then return end
        _pushedHooked = true
        _pollFrame = mod.TakeShell()
        _pollFrame:SetScript("OnUpdate", function()
            if _activePushedN == 0 then
                _pollFrame:Hide()
                return
            end
            for button in pairs(_activePushed) do
                local keyList = _btnKeys[button]
                local held = false
                if keyList then
                    for index = 1, #keyList do
                        -- IsKeyDown reads no non-ASCII key name (the Nordic section key):
                        -- such a key stays lit until its binding's key-up below.
                        if IsKeyDown(keyList[index]) or keyList[index]:find("[\128-\255]") then
                            held = true
                            break
                        end
                    end
                end
                if not held then
                    if button.PushedTexture then button.PushedTexture:Hide() end
                    _activePushed[button] = nil
                    _activePushedN = _activePushedN - 1
                end
            end
            if _activePushedN == 0 then _pollFrame:Hide() end
        end)
        _pollFrame:Hide()
        -- Extract the base key from a compound binding ("SHIFT-1" -> "1",
        -- "CTRL-Q" -> "Q"): IsKeyDown only accepts raw key names.
        local function BaseKey(binding)
            if not binding then return nil end
            -- The minus key's name is the literal "-", so "-" and modifier
            -- combos like "SHIFT--" END in "-": the trailing char IS the key,
            -- and the pattern below would find no non-hyphen run (nil).
            if binding:sub(-1) == "-" then return "-" end
            return binding:match("[^%-]+$")
        end
        local function ShowPushedForSlot(slot)
            local prof = ABAR.db and ABAR.db.profile
            if not prof then return end
            if mod.AB_Style() == "cui" and (prof.pushedTextureType or 2) == 6 then return end
            local button = allButtons[slot]
            if not button or not button.PushedTexture then return end
            local cmd = button.commandName
            if not cmd then return end
            local k1, k2 = GetBindingKey(cmd)
            if not k1 then return end
            local keyList = _btnKeys[button]
            if not keyList then
                keyList = {}
                _btnKeys[button] = keyList
            end
            keyList[1] = BaseKey(k1)
            keyList[2] = BaseKey(k2)
            keyList[3] = nil
            button.PushedTexture:Show()
            if not _activePushed[button] then
                _activePushed[button] = true
                _activePushedN = _activePushedN + 1
            end
            _pollFrame:Show()
        end
        local function HidePushedForSlot(slot)
            local button = allButtons[slot]
            if not (button and _activePushed[button]) then return end
            if button.PushedTexture then button.PushedTexture:Hide() end
            _activePushed[button] = nil
            _activePushedN = _activePushedN - 1
        end
        -- ActionButtonDown/MultiActionButtonDown fire on key press regardless
        -- of "cast on key down" CVar. This ensures pushed texture shows while
        -- the key is held for both key-down and key-up casting modes.
        hooksecurefunc("ActionButtonDown", function(ident) ShowPushedForSlot(ident) end)
        hooksecurefunc("ActionButtonUp", function(ident) HidePushedForSlot(ident) end)
        if MultiActionButtonDown then
            local multiBarPage = {
                MultiBarBottomLeft = 6,
                MultiBarBottomRight = 5,
                MultiBarRight = 3,
                MultiBarLeft = 4,
                MultiBar5 = 13,
                MultiBar6 = 14,
                MultiBar7 = 15,
            }
            hooksecurefunc("MultiActionButtonDown", function(barName, ident)
                local page = multiBarPage[barName]
                if not page then return end
                local slot = (page - 1) * 12 + ident
                ShowPushedForSlot(slot)
            end)
            if MultiActionButtonUp then
                hooksecurefunc("MultiActionButtonUp", function(barName, ident)
                    local page = multiBarPage[barName]
                    if page then HidePushedForSlot((page - 1) * 12 + ident) end
                end)
            end
        end
    end
end

function ABAR:ApplyHighlightTextures()
    local profile = self.db.profile
    local abStock = mod.AB_Style() ~= "cui"
    local hType = profile.highlightTextureType or 2
    local useCC = profile.highlightUseClassColor
    local customC = profile.highlightCustomColor or { r = 0.973, g = 0.839, b = 0.604, a = 1 }
    local brdSize = profile.highlightBorderSize or 4

    local cr, cg, callback = customC.r, customC.g, customC.b
    if useCC then
        local _, classTok = UnitClass("player")
        if classTok then
            local cc = RAID_CLASS_COLORS[classTok]
            if cc then
                cr, cg, callback = cc.r, cc.g, cc.b
            end
        end
    end

    -- Match Bar Border (hover), plus the tint the spell-cast copy shares with
    -- it (this colour and its alpha). Once a copy exists (ixEver), every path
    -- that does not arm the hover role disarms it, and a lit cast copy picks
    -- up a colour change here. The tint is refreshed on every pass, options
    -- off included: the Spell Cast Highlight toggles arm the cast role through
    -- ApplyCheckedTextures alone, which paints with this slot as it stands.
    local _, ixOn, ixCast = mod._ixRolesOn(profile)
    ixOn = ixOn and not abStock
    do
        local tbl = mod._ixHlC
        tbl[1], tbl[2], tbl[3], tbl[4] = cr, cg, callback, customC.a or 1
    end
    local ixEver = mod._ixEver

    for _, details in ipairs(BAR_CONFIG) do
        if abStock then
            -- skip -- the stock kit owns the highlight (classic paints its
            -- own in ns.AB_PaintClassicButton)
            local buttons = ixEver and barButtons[details.key]
            if buttons then
                for index = 1, #buttons do
                    local button = buttons[index]
                    if button then mod._ixRole(button, nil, "ixHover", false) end
                end
            end
        else
            local buttons = barButtons[details.key]
            if buttons then
                local s = profile.bars[details.key]
                local ixBar = ixOn and mod._ixBarEligible(details.key)
                for index = 1, #buttons do
                    local button = buttons[index]
                    if button and button.HighlightTexture then
                        if hType == 6 then
                            button.HighlightTexture:SetAlpha(0)
                            mod._hideBorderEdges(button, "_highlightBorder")
                        elseif hType == 5 then
                            button.HighlightTexture:SetAlpha(0)
                            if ixBar and mod._ixRole(button, s, "ixHover", true) then
                                mod._hideBorderEdges(button, "_highlightBorder")
                            else
                                local edges = mod._setupBorderEdges(button, "_highlightBorder")
                                mod._applyBorderEdges(edges, button, brdSize, cr, cg, callback)
                            end
                            if not EFD(button).hlBorderHooked then
                                EFD(button).hlBorderHooked = true
                                -- Hover driver for both looks: the armed copy, else
                                -- today's edges.
                                button:HookScript("OnEnter", function(self)
                                    local fd = EFD(self)
                                    if fd.ixHover then
                                        fd.ixOver = true
                                        mod._ixPaint(self, fd)
                                        return
                                    end
                                    local be = fd._highlightBorder
                                    if be and be._active then
                                        for jdx = 1, 4 do
                                            be[jdx]:Show()
                                        end
                                    end
                                end)
                                button:HookScript("OnLeave", function(self)
                                    local fd = EFD(self)
                                    if fd.ixOver then
                                        fd.ixOver = nil
                                        mod._ixPaint(self, fd)
                                    end
                                    local be = fd._highlightBorder
                                    if be then
                                        for jdx = 1, 4 do
                                            be[jdx]:Hide()
                                        end
                                    end
                                end)
                            end
                        else
                            button.HighlightTexture:SetAlpha(1)
                            mod._hideBorderEdges(button, "_highlightBorder")
                            if hType <= 3 then
                                SetSquareTexture(
                                    button.HighlightTexture,
                                    HIGHLIGHT_TEXTURES[hType] or HIGHLIGHT_TEXTURES[1]
                                )
                                button.HighlightTexture:SetVertexColor(cr, cg, callback, 1)
                            elseif hType == 4 then
                                button.HighlightTexture:SetColorTexture(cr, cg, callback, 0.35)
                            end
                        end
                        if ixEver and not ixBar then mod._ixRole(button, s, "ixHover", false) end
                    end
                    if ixCast and ixEver and button then
                        local fd = mod._eabFD[button]
                        if fd and fd.ixCast then mod._ixPaint(button, fd) end
                    end
                    _quickKeybindState.art.RefreshButton(button)
                end
            end
        end -- abStock
    end

    -- Blizzard-owned special buttons do not flow through the standard bar
    -- button setup, but QuickKeybind still resets their overlay atlas.
    -- Keep their QuickKeybind highlight aligned with the CUI button art too.
    _quickKeybindState.art.ForEachSpecialButton(_quickKeybindState.art.InitializeButton)
end
