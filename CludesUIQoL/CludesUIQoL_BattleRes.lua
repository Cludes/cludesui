if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUIQoL_BattleRes.lua
--  Runtime for the BattleRes icon. Polls GetSpellCharges(20484) and shows
--  the shared raid brez pool (charges + recharge timer) as a single icon.
-------------------------------------------------------------------------------

local _, mod = ...

local BREZ_SPELL_ID = 20484 -- Rebirth -- canonical shared brez pool spell ID

local SHAPE_MASKS = CludesUI.SHAPE_MASKS

-- Sits under CludesUIQoLDB.profile.battleRes so we don't clobber the
-- existing cursor / QoL feature data that already lives in that SavedVariable.
local defaultSet = {
    profile = {
        battleRes = {
            enabled = true,
            visibility = "MPLUS_AND_RAID", -- MPLUS_AND_RAID | MPLUS | RAID | NEVER
            displayMode = "icon", -- icon | text ("2 | 4:14" line)
            iconSize = 40,
            iconZoom = 11, -- percent
            shape = "none",
            borderSize = "thin", -- none / thin / normal / heavy / strong
            borderColor = { r = 0, g = 0, b = 0, a = 1 },
            borderUseClass = false,
            durationSize = 12,
            durationOffsetX = 0,
            durationOffsetY = 0,
            countSize = 11,
            countOffsetX = 0,
            countOffsetY = 0,
            desaturateNoCharges = true, -- grey the icon at 0 charges (icon display only)
            textSize = 14,
            textCountColor = { r = 1, g = 1, b = 1 },
            textTimerColor = { r = 1, g = 1, b = 1 },
            font = "__global", -- key into the shared font registry
            outlineMode = "__global", -- __global | none (shadow) | outline | thick
            pos = nil, -- { centerX, centerY } stored after first move
        },
        -- Bloodlust Tracker: additive sibling of battleRes. Stores ONLY its own keys
        -- here (enable, visibility, position). Appearance keys are left out on purpose
        -- so the runtime/options proxy-read through to the current battleRes values
        -- until the user overrides a setting on the tracker (the same "starts
        -- identical, can diverge" model used for raid/party frames). This keeps
        -- existing battleRes settings completely untouched for current users.
        bloodlust = {
            enabled = true,
            visibility = "NEVER", -- MPLUS_AND_RAID | MPLUS | RAID | NEVER
            pos = nil, -- { centerX, centerY } stored after first move
            -- Show Sated / Show Ready: independent toggles. Own keys, never proxied to
            -- battleRes (which has no ready state). Sated on / Ready off = the
            -- pre-existing behaviour (countdown only, hidden once it expires).
            showSated = true,
            showReady = false,
            readySize = 12,
            readyColor = { r = 1, g = 1, b = 1 },
            readyOffsetX = 0,
            readyOffsetY = 0,
            desaturateSated = true, -- own key, independent of battleRes.desaturateNoCharges
        },
    },
}

local addonName = {}
addonName.db = nil
local function P() return addonName.db and addonName.db.profile and addonName.db.profile.battleRes end

local widget, iconTexture, borderTex, durationText, countLine, cdFrame, textLine

-- Options-page live preview: forces the icon on screen for as long as the owning
-- page is. Real charge data is used whenever the brez pool reports any; outside
-- a raid or key it reports none, so PollCharges falls back to the stand-in below
-- rather than previewing an icon with no count and no timer.
local _previewOwner
local function _previewActive() return _previewOwner ~= nil and _previewOwner:IsVisible() and true or false end

local function TextMode()
    local profile = P()
    return (profile and profile.displayMode) == "text"
end

-------------------------------------------------------------------------------
--  Font resolution -- mirrors the Chat module's font / outline settings:
--  "__global" follows the CUI global font defaults, a named key resolves
--  through the shared font registry, and outline overrides stay slug-gated.
-------------------------------------------------------------------------------
local function GetBrezFont()
    local profile = P()
    local key = (profile and profile.font) or "__global"
    if key ~= "__global" and CludesUI and CludesUI.ResolveFontName then
        local filePath = CludesUI.ResolveFontName(key)
        if filePath then return filePath end
    end
    return (CludesUI.GetFontPath("extras")) or STANDARD_TEXT_FONT
end

local function GetBrezOutline()
    local profile = P()
    local mode = (profile and profile.outlineMode) or "__global"
    if mode == "outline" then return (CludesUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG" end
    if mode == "thick" then return (CludesUI.SlugFlag("THICKOUTLINE, SLUG")) or "THICKOUTLINE, SLUG" end
    if mode == "none" then return "" end
    return (CludesUI.GetFontOutlineFlag("qol")) or (CludesUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG"
end

-- ONLY the text display ("2 | 4:14") routes through this; the icon's
-- duration / count texts keep the fixed house style via SetBrezIconFont
-- below. Empty flags = Drop Shadow mode, primed via FontObject (instance
-- shadow setters do not render).
local function SetBrezFont(fontStr, size)
    if not fontStr then return end
    local flags = GetBrezOutline()
    CludesUI.PrimeFontShadow(fontStr, flags == "")
    fontStr:SetFont(GetBrezFont(), size, flags)
end

-- Icon-mode duration / count texts: fixed module font + forced crisp
-- outline (slug-gated), untouched by the Font / Font Outline settings.
local function SetBrezIconFont(fontStr, size)
    if not fontStr then return end
    fontStr:SetFont(
        (CludesUI.GetFontPath("extras")) or STANDARD_TEXT_FONT,
        size,
        (CludesUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG"
    )
end

-------------------------------------------------------------------------------
--  Shape application
-------------------------------------------------------------------------------
local BORDER_PX = { none = 0, thin = 1, normal = 2, heavy = 3, strong = 4 }

local function _resolveBorderColor(profile)
    if profile.borderUseClass then
        local _, countText = UnitClass("player")
        if countText and RAID_CLASS_COLORS[countText] then
            return RAID_CLASS_COLORS[countText].r,
                RAID_CLASS_COLORS[countText].g,
                RAID_CLASS_COLORS[countText].b,
                1
        end
    end
    local color = profile.borderColor
    if color then return color.r or 0, color.g or 0, color.b or 0, color.a or 1 end
    return 0, 0, 0, 1
end

-- Snap a config-driven layout offset onto the pixel grid. The frame's own edges
-- and center are snapped already (ApplyShape / ApplyPosition), so snapping the
-- offset is what keeps the child anchored to it on the grid too.
local function _snapOff(val)
    local Pix = CludesUI and CludesUI.PP
    if Pix and Pix.Snap then return Pix.Snap(val) end
    return val
end

-- Custom-shape outline: the shape's mask grown by the border size and filled with
-- the border colour behind the masked icon, leaving a ring exactly that thick.
local function _applyShapeOutline(owner, shapeKey, bs, red, green, blue, a)
    local t = owner._cuiOutline
    local maskFile = shapeKey and CludesUI.SHAPE_MASKS[shapeKey]
    local Pix = CludesUI and CludesUI.PP
    if not (maskFile and Pix) or bs <= 0 then
        if t then t:Hide() end
        return
    end
    if not t then
        t = owner:CreateTexture(nil, "BACKGROUND", nil, 7)
        owner._cuiOutlineMask = owner:CreateMaskTexture()
        t:AddMaskTexture(owner._cuiOutlineMask)
        owner._cuiOutline = t
    end
    local m = owner._cuiOutlineMask
    -- The mask's opening is its middle (128 - 2 * inset) / 128: grow it by bs over
    -- that ratio so the outline reaches bs pixels past the icon's own edge.
    local inset = CludesUI.SHAPE_INSETS[shapeKey] or 17
    local grow = _snapOff(Pix.FromPixels(bs * 128 / (128 - 2 * inset)))
    m:ClearAllPoints()
    m:SetPoint("TOPLEFT", owner, "TOPLEFT", -grow, grow)
    m:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", grow, -grow)
    m:SetTexture(maskFile, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    t:ClearAllPoints()
    t:SetAllPoints(m)
    t:SetColorTexture(red, green, blue, a)
    t:Show()
end
-- Shared with the Bloodlust tracker (this file loads first).
mod.QoL_ApplyShapeOutline = _applyShapeOutline

local function ApplyShape()
    if not widget then return end
    local profile = P()
    if not profile then return end

    local Pix = CludesUI and CludesUI.PP
    local shapeKey = profile.shape or "none"
    local bs = BORDER_PX[profile.borderSize or "thin"] or 1

    -- Frame sizing: square by default; for "cropped" the height is 80% of width
    -- (mirrors Action Bars line 2263: btnH = btnH * 0.80).
    local size = profile.iconSize or 40
    local fw, fh = size, size
    if shapeKey == "cropped" then fh = math.floor(size * 0.80 + 0.5) end
    if Pix and Pix.Snap then
        fw, fh = Pix.Snap(fw), Pix.Snap(fh)
    end
    widget:SetSize(fw, fh)
    iconTexture:ClearAllPoints()
    iconTexture:SetAllPoints(widget)

    -- Cooldown swirl: covers the icon area.
    if cdFrame then
        cdFrame:ClearAllPoints()
        cdFrame:SetAllPoints(widget)
    end

    -- Duration text (centered) and count text (bottom-right) -- positioned for
    -- every shape since the early-return below would otherwise skip them.
    SetBrezIconFont(durationText, profile.durationSize or 12)
    durationText:ClearAllPoints()
    durationText:SetPoint(
        "CENTER",
        widget,
        "CENTER",
        _snapOff(profile.durationOffsetX or 0),
        _snapOff(profile.durationOffsetY or 0)
    )

    SetBrezIconFont(countLine, profile.countSize or 11)
    countLine:ClearAllPoints()
    countLine:SetPoint(
        "BOTTOMRIGHT",
        widget,
        "BOTTOMRIGHT",
        _snapOff(-2 + (profile.countOffsetX or 0)),
        _snapOff(2 + (profile.countOffsetY or 0))
    )

    -----------------------------------------------------------------------
    --  BASE CASE: "none" or "cropped" -- plain texture, no mask
    -----------------------------------------------------------------------
    if shapeKey == "none" or shapeKey == "cropped" then
        if iconTexture._mask then
            -- Remove the mask from the cooldown swipe and reset its
            -- swipe texture BEFORE we nil out the mask reference.
            -- Otherwise the swipe stays cropped to the previous shape.
            if cdFrame and not cdFrame:IsForbidden() then
                pcall(cdFrame.RemoveMaskTexture, cdFrame, iconTexture._mask)
                if cdFrame.SetSwipeTexture then pcall(cdFrame.SetSwipeTexture, cdFrame, "") end
            end
            iconTexture:RemoveMaskTexture(iconTexture._mask)
            iconTexture._mask:SetTexture(nil)
            iconTexture._mask:ClearAllPoints()
            iconTexture._mask:SetSize(0.001, 0.001)
            iconTexture._mask:Hide()
            iconTexture._mask = nil
        end
        borderTex:Hide() -- shape-border atlas is for custom shapes only
        _applyShapeOutline(widget, nil, 0)

        local z = (profile.iconZoom or 11) / 100
        if shapeKey == "cropped" then
            iconTexture:SetTexCoord(z, 1 - z, z + 0.10, 1 - z - 0.10)
        elseif z > 0 then
            iconTexture:SetTexCoord(z, 1 - z, z, 1 - z)
        else
            iconTexture:SetTexCoord(0, 1, 0, 1)
        end

        -- Pixel-perfect border via PP.CreateBorder (canonical CUI pattern).
        if Pix then
            if not Pix.GetBorders(widget) then Pix.CreateBorder(widget, 0, 0, 0, 1, 1, "OVERLAY", 2) end
            if bs > 0 then
                local red, green, blue, a = _resolveBorderColor(profile)
                Pix.UpdateBorder(widget, bs, red, green, blue, a)
                Pix.ShowBorder(widget)
            else
                Pix.HideBorder(widget)
            end
        end
        return
    end

    -----------------------------------------------------------------------
    --  CUSTOM SHAPE: apply mask + shape-matching border overlay
    -----------------------------------------------------------------------
    if Pix then Pix.HideBorder(widget) end

    local maskFile = SHAPE_MASKS[shapeKey]
    if maskFile then
        if not iconTexture._mask then
            iconTexture._mask = widget:CreateMaskTexture()
            iconTexture._mask:SetAllPoints(iconTexture)
            iconTexture:AddMaskTexture(iconTexture._mask)
        end
        iconTexture._mask:SetTexture(maskFile, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        iconTexture._mask:Show()
        iconTexture:SetTexCoord(0, 1, 0, 1)
        -- Crop the cooldown swipe to the same shape (matches action bar
        -- behavior). Adds the icon's mask to the cooldown frame and uses
        -- the mask path as the swipe texture so the spinning swipe
        -- follows the custom outline rather than a square.
        if cdFrame and not cdFrame:IsForbidden() then
            pcall(cdFrame.AddMaskTexture, cdFrame, iconTexture._mask)
            if cdFrame.SetSwipeTexture then pcall(cdFrame.SetSwipeTexture, cdFrame, maskFile) end
        end
    elseif cdFrame and not cdFrame:IsForbidden() then
        -- Default shape: remove any prior mask + restore default swipe.
        if iconTexture._mask then pcall(cdFrame.RemoveMaskTexture, cdFrame, iconTexture._mask) end
        if cdFrame.SetSwipeTexture then pcall(cdFrame.SetSwipeTexture, cdFrame, "") end
    end

    borderTex:Hide()
    local red, green, blue, a = _resolveBorderColor(profile)
    _applyShapeOutline(widget, shapeKey, bs, red, green, blue, a)
end

-------------------------------------------------------------------------------
--  Text display -- "2 | 4:14" (charges, then time until the next charge).
--  Alternative to the icon, toggled via displayMode; shares the same frame,
--  position, visibility, and unlock element.
-------------------------------------------------------------------------------
local _cntPfx, _timPfx = CludesUI.COLOR_CODES.WHITE, CludesUI.COLOR_CODES.WHITE
local _txtCount, _txtTime, _txtZero

local function _colorPrefix(color)
    return CludesUI.HexColor((color and color.r) or 1, (color and color.g) or 1, (color and color.b) or 1)
end

-- Compose the line only when a part actually changed (once per second while
-- recharging). The separator pipe is escaped as || for the renderer; the
-- count goes red at 0 charges, matching the icon display's count text.
local function _setTextDisplay(countStr, timeStr, isZero)
    if not textLine then return end
    if countStr == _txtCount and timeStr == _txtTime and isZero == _txtZero then return end
    _txtCount, _txtTime, _txtZero = countStr, timeStr, isZero
    local cpfx = isZero and "|cffff3333" or _cntPfx
    if timeStr ~= "" then
        textLine:SetFormattedText("%s%s|r |cffa6a6a6|||r %s%s|r", cpfx, countStr, _timPfx, timeStr)
    else
        textLine:SetFormattedText("%s%s|r", cpfx, countStr)
    end
end

-- Font, colors, and the frame's nominal box (read by the unlock mover).
-- Runs on settings changes only. While hidden the measurement uses a
-- placeholder string; live polling overwrites it the moment the tracker
-- shows (UpdateVisibility polls immediately on Show).
local function ApplyText()
    local profile = P()
    if not profile or not textLine then return end
    _cntPfx = _colorPrefix(profile.textCountColor)
    _timPfx = _colorPrefix(profile.textTimerColor)
    SetBrezFont(textLine, profile.textSize or 14)
    -- Drop the dedupe caches so the next compose re-renders with new colors
    -- (the ticker repaints within half a second while shown).
    _txtCount, _txtTime, _txtZero = nil, nil, nil
    if not widget:IsShown() then _setTextDisplay("2", "4:14", false) end
    local wid = textLine:GetStringWidth() or 0
    local hgt = textLine:GetStringHeight() or 0
    if wid < 1 then wid = (profile.textSize or 14) * 4 end
    if hgt < 1 then hgt = profile.textSize or 14 end
    local tw, th = math.ceil(wid) + 4, math.ceil(hgt) + 2
    local PPt = CludesUI and CludesUI.PP
    if PPt and PPt.Snap then
        tw, th = PPt.Snap(tw), PPt.Snap(th)
    end
    widget:SetSize(tw, th)
end

-------------------------------------------------------------------------------
--  Position
-------------------------------------------------------------------------------
local function ApplyPosition()
    if not widget then return end
    local profile = P()
    if not profile then return end
    widget:ClearAllPoints()
    local place = profile.pos
    local cx = (place and place.centerX) or 0
    local cy = (place and place.centerY) or 200
    local PPp = CludesUI and CludesUI.PP
    if PPp and PPp.SnapCenterForDim then
        cx = PPp.SnapCenterForDim(cx, widget:GetWidth())
        cy = PPp.SnapCenterForDim(cy, widget:GetHeight())
    end
    widget:SetPoint("CENTER", UIParent, "CENTER", cx, cy)
end

-------------------------------------------------------------------------------
--  Visibility -- driven by encounter / keystone events, not polling.
-------------------------------------------------------------------------------
local _state = {
    inEncounter = false,
    encounterIsRaid = false,
    inChallenge = false,
}

-- Keystone/encounter state writers, shared with the Bloodlust tracker through
-- ns (this file loads first). Each icon passes its own state table.

local function _activeKeystoneLevel()
    -- IsChallengeModeActive only returns true when the timer is running,
    -- not just from having a keystone in bags inside a dungeon.
    if not C_ChallengeMode then return nil end
    if not C_ChallengeMode.IsChallengeModeActive or not C_ChallengeMode.IsChallengeModeActive() then
        return nil
    end
    if C_ChallengeMode.GetActiveKeystoneInfo then
        local lvl = C_ChallengeMode.GetActiveKeystoneInfo()
        return (lvl and lvl > 0) and lvl or nil
    end
    return nil
end

-- Re-read encounter and keystone state directly (zone-in, or events re-registered).
function mod.RefreshInstanceState(state)
    state.inEncounter = IsEncounterInProgress() or false
    if state.inEncounter then
        local _, instanceType = GetInstanceInfo()
        state.encounterIsRaid = (instanceType == "raid")
    else
        state.encounterIsRaid = false
    end
    state.inChallenge = _activeKeystoneLevel() ~= nil
end

-- Mirrors CludesUIMythicTimer's keystone events plus ENCOUNTER_START/END
-- for raid bosses. Other events are ignored.
function mod.ApplyInstanceEvent(state, evt)
    if evt == "ENCOUNTER_START" then
        state.inEncounter = true
        local _, instanceType = GetInstanceInfo()
        state.encounterIsRaid = (instanceType == "raid")
    elseif evt == "ENCOUNTER_END" then
        state.inEncounter = false
        state.encounterIsRaid = false
    elseif evt == "CHALLENGE_MODE_START" or evt == "WORLD_STATE_TIMER_START" then
        state.inChallenge = _activeKeystoneLevel() ~= nil
    elseif
        evt == "CHALLENGE_MODE_COMPLETED"
        or evt == "CHALLENGE_MODE_RESET"
        or evt == "WORLD_STATE_TIMER_STOP"
    then
        state.inChallenge = false
    elseif evt == "PLAYER_ENTERING_WORLD" then
        mod.RefreshInstanceState(state)
    end
end

local function ShouldShow()
    local profile = P()
    if not profile or not profile.enabled then return false end
    local val = profile.visibility or "MPLUS_AND_RAID"
    if val == "NEVER" then return false end
    -- Options preview: forced on screen while the page is up, skipping the instance
    -- and M+/raid gates below -- the point is to configure it from anywhere.
    if _previewActive() then return true end

    -- Hard gate: must be in a party or raid instance. Prevents any stuck state from
    -- showing the icon in town/open world. Unlock mode relies on the overlay mover for
    -- positioning feedback, so we never force-show the real icon here -- it would
    -- persist past an "exit without saving" since DoClose doesn't re-run visibility.
    local _, instanceType = GetInstanceInfo()
    if instanceType ~= "party" and instanceType ~= "raid" then return false end

    local wantMPlus = (val == "MPLUS_AND_RAID" or val == "MPLUS")
    local wantRaid = (val == "MPLUS_AND_RAID" or val == "RAID")
    if wantMPlus and _state.inChallenge then return true end
    if wantRaid and _state.inEncounter and _state.encounterIsRaid then return true end
    return false
end

-------------------------------------------------------------------------------
--  Polling
-------------------------------------------------------------------------------
local function FormatTime(s)
    if not s or s <= 0 then return "" end
    local m = math.floor(s / 60)
    local sec = math.floor(s % 60)
    return string.format("%d:%02d", m, sec)
end
-- Shared with the Bloodlust tracker (identical display contract; this file
-- loads first).
mod.FormatTime = FormatTime

-- WoW Forever has no shared battle res charge pool, so the indicator does not
-- exist there: the shared helpers above stay defined, and nothing below runs
-- (no DB, frame, events, unlock mover or _G._CUI_BattleRes_* hooks), even when
-- a saved or imported profile has it enabled. Every reader of those hooks
-- nil-guards, and the options section and Fonts rows are not built there.
if CludesUI.IS_FOREVER then return end

local _lastCountText, _lastDurText, _lastCountColor
local function _setCount(s, isZero)
    if s ~= _lastCountText then
        countLine:SetText(s)
        _lastCountText = s
    end
    local key = isZero and "zero" or "ok"
    if key ~= _lastCountColor then
        if isZero then
            countLine:SetTextColor(1, 0.2, 0.2, 1)
        else
            countLine:SetTextColor(1, 1, 1, 1)
        end
        _lastCountColor = key
    end
end
local function _setDur(s)
    if s ~= _lastDurText then
        durationText:SetText(s)
        _lastDurText = s
    end
end
local _lastDesat = false
local function _setDesat(wanted)
    wanted = wanted and true or false
    if wanted ~= _lastDesat then
        iconTexture:SetDesaturated(wanted)
        _lastDesat = wanted
    end
end

-- Options preview stand-in. The shared brez pool only reports charges inside a
-- raid or key, and BREZ_SPELL_ID is Rebirth, so for most characters in most
-- places GetSpellCharges returns nothing and the preview would be a bare icon --
-- exactly the two texts the Count and Duration options tune. Same placeholder
-- count ApplyText measures with, plus a looping countdown.
local _previewExpiry = 0
local function _showPreviewCharges()
    if _previewExpiry <= GetTime() then
        -- Once per cycle: re-setting the SAME values each poll is idempotent, but
        -- re-setting new ones would restart the swipe animation twice a second.
        _previewExpiry = GetTime() + 90
        if cdFrame then cdFrame:SetCooldown(GetTime(), 90) end
    end
    local timeLabel = FormatTime(_previewExpiry - GetTime())
    if TextMode() then
        _setTextDisplay("2", timeLabel, false)
        return
    end
    _setCount("2", false)
    _setDur(timeLabel)
    _setDesat(false)
end

local function PollCharges()
    if not widget then return end
    local textMode = TextMode()
    local details = C_Spell and C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(BREZ_SPELL_ID)
    if not details or not details.maxCharges then
        if _previewActive() then return _showPreviewCharges() end
        if textMode then
            _setTextDisplay("", "", false)
        else
            _setCount("", false)
            _setDur("")
            _setDesat(false)
        end
        return
    end
    local chargeCount, maxCharges = details.currentCharges, details.maxCharges
    local start, dur = details.cooldownStartTime, details.cooldownDuration
    local recharging = chargeCount < maxCharges and start and dur and dur > 0
    local timeLabel = ""
    if recharging then
        local remaining = (start + dur) - GetTime()
        timeLabel = remaining > 0 and FormatTime(remaining) or ""
    end

    if textMode then
        _setTextDisplay(tostring(chargeCount), timeLabel, chargeCount <= 0)
        return
    end

    _setCount(tostring(chargeCount), chargeCount <= 0)
    _setDur(timeLabel)
    local profile = P()
    _setDesat(profile and profile.desaturateNoCharges ~= false and chargeCount <= 0)
    if cdFrame then
        if recharging then
            cdFrame:SetCooldown(start, dur)
        else
            cdFrame:Clear()
        end
    end
end

-- Ticker only runs while the icon is actually visible.
local _ticker
local function SyncResShown()
    if not widget then return end
    if ShouldShow() then
        if not widget:IsShown() then widget:Show() end
        if not _ticker then _ticker = C_Timer.NewTicker(0.5, PollCharges) end
        PollCharges()
    else
        if widget:IsShown() then widget:Hide() end
        if _ticker then
            _ticker:Cancel()
            _ticker = nil
        end
        -- Preview just ended: drop the stand-in swipe and texts so no later path
        -- can surface them as if they were real charge data.
        if _previewExpiry ~= 0 and not _previewActive() then
            _previewExpiry = 0
            if cdFrame then cdFrame:Clear() end
            if TextMode() then
                _setTextDisplay("", "", false)
            else
                _setCount("", false)
                _setDur("")
            end
        end
    end
end
_G._CUI_BattleRes_UpdateVisibility = SyncResShown

-- The options page hands us its frame on build; _previewActive() takes it from there.
function _G._CUI_BattleRes_SetPreviewOwner(frame)
    _previewOwner = frame
    _previewExpiry = 0 -- every visit starts a fresh stand-in countdown
    SyncResShown()
end

-------------------------------------------------------------------------------
--  Frame creation
-------------------------------------------------------------------------------
local function BuildResFrame()
    if widget then return widget end
    widget = CreateFrame("Frame", "CludesUIBattleResIcon", UIParent)
    widget:SetFrameStrata("MEDIUM")
    widget:SetSize(40, 40)
    widget:Hide()

    iconTexture = widget:CreateTexture(nil, "ARTWORK")
    iconTexture:SetAllPoints(widget)
    local brezIcon
    if C_Spell and C_Spell.GetSpellTexture then brezIcon = C_Spell.GetSpellTexture(BREZ_SPELL_ID) end
    iconTexture:SetTexture(brezIcon or 136080)
    iconTexture:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    borderTex = widget:CreateTexture(nil, "OVERLAY")
    borderTex:Hide()

    cdFrame = CreateFrame("Cooldown", nil, widget, "CooldownFrameTemplate")
    cdFrame:SetAllPoints(widget)
    cdFrame:SetDrawEdge(false)
    cdFrame:SetHideCountdownNumbers(true) -- we render our own duration text
    cdFrame:SetFrameLevel(widget:GetFrameLevel() + 1)

    durationText = cdFrame:CreateFontString(nil, "OVERLAY")
    SetBrezIconFont(durationText, 14)
    durationText:SetText("")

    countLine = cdFrame:CreateFontString(nil, "OVERLAY")
    SetBrezIconFont(countLine, 12)
    countLine:SetText("")

    -- Text display ("2 | 4:14"): centered on the frame, shown instead of the
    -- icon elements when displayMode is "text". A default font is required
    -- before any SetText ("Font not set" error otherwise); ApplyText re-applies
    -- the configured size on top of it.
    textLine = widget:CreateFontString(nil, "OVERLAY")
    SetBrezFont(textLine, 14)
    textLine:SetPoint("CENTER", widget, "CENTER", 0, 0)
    textLine:SetText("")
    textLine:Hide()

    return widget
end

-------------------------------------------------------------------------------
--  Apply (settings entry point)
-------------------------------------------------------------------------------
local _syncEventRegistration -- defined in the event section below
local function ApplyResTracker()
    if not addonName.db then return end
    if not widget then BuildResFrame() end
    if TextMode() then
        -- Text display: hide every icon element (duration/count texts are
        -- children of the cooldown frame, so they hide with it).
        iconTexture:Hide()
        borderTex:Hide()
        if cdFrame then
            cdFrame:Clear()
            cdFrame:Hide()
        end
        local Pix = CludesUI and CludesUI.PP
        if Pix and Pix.GetBorders and Pix.GetBorders(widget) then Pix.HideBorder(widget) end
        _applyShapeOutline(widget, nil, 0)
        textLine:Show()
        ApplyText()
    else
        textLine:Hide()
        iconTexture:Show()
        if cdFrame then cdFrame:Show() end
        ApplyShape()
    end
    ApplyPosition()
    _syncEventRegistration()
    SyncResShown()
end
_G._CUI_BattleRes_Apply = ApplyResTracker

-- QoL Reset: the Battle Res and Bloodlust slices back to their defaults (both
-- live in this file's defaults table).
function _G._CUI_BattleRes_Reset()
    local prof = addonName.db and addonName.db.profile
    if not prof then return end
    prof.battleRes, prof.bloodlust = {}, {}
    CludesUI.Lite.DeepMergeDefaults(prof, defaultSet.profile)
    ApplyResTracker()
    if _G._CUI_Bloodlust_Apply then _G._CUI_Bloodlust_Apply() end
end

-------------------------------------------------------------------------------
--  Event handler (state writes live in ns.ApplyInstanceEvent above)
-------------------------------------------------------------------------------
local _eventFrame
local function OnEvent(_, evt)
    mod.ApplyInstanceEvent(_state, evt)
    SyncResShown()
end

-- Events are registered only while the icon can ever show (enabled and
-- visibility not NEVER) and unregistered when it cannot, so a disabled
-- tracker costs nothing on boss pulls / key starts. On (re-)registration the
-- encounter/keystone state is re-read directly, so enabling mid-fight or
-- mid-key still catches up on events missed while unregistered.
local _eventsRegistered = false
_syncEventRegistration = function()
    local profile = P()
    local wanted = (profile and profile.enabled and (profile.visibility or "MPLUS_AND_RAID") ~= "NEVER")
            and true
        or false
    if wanted == _eventsRegistered then return end
    _eventsRegistered = wanted
    if wanted then
        if not _eventFrame then
            _eventFrame = CreateFrame("Frame")
            _eventFrame:SetScript("OnEvent", OnEvent)
        end
        _eventFrame:RegisterEvent("ENCOUNTER_START")
        _eventFrame:RegisterEvent("ENCOUNTER_END")
        _eventFrame:RegisterEvent("CHALLENGE_MODE_START")
        _eventFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
        _eventFrame:RegisterEvent("CHALLENGE_MODE_RESET")
        _eventFrame:RegisterEvent("WORLD_STATE_TIMER_START")
        _eventFrame:RegisterEvent("WORLD_STATE_TIMER_STOP")
        _eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        mod.RefreshInstanceState(_state)
    else
        if _eventFrame then _eventFrame:UnregisterAllEvents() end
    end
end

-------------------------------------------------------------------------------
--  Unlock mode registration
-------------------------------------------------------------------------------
local function RegisterUnlock()
    if not CludesUI or not CludesUI.RegisterUnlockElements then return end
    local MK = CludesUI.MakeUnlockElement
    if not MK then return end
    local loadPos, clearPos = mod.CenterPosFns(P)

    CludesUI:RegisterUnlockElements({
        MK({
            key = "CUI_BattleRes",
            label = "Brez",
            group = "Utilities",
            order = 600,
            noAnchorTarget = true, -- icon size changes; nothing should be anchored to it
            isHidden = function()
                local profile = P()
                return not profile or not profile.enabled or (profile.visibility == "NEVER")
            end,
            getFrame = function()
                if not widget then BuildResFrame() end
                return widget
            end,
            getSize = function()
                local profile = P()
                if profile and profile.displayMode == "text" then
                    -- Text display: the frame is sized to the measured text
                    -- box by ApplyText, so report that instead of iconSize.
                    if not widget then BuildResFrame() end
                    local wid, hgt = widget:GetWidth(), widget:GetHeight()
                    if wid and wid > 0 then return wid, hgt end
                end
                local s = (profile and profile.iconSize) or 40
                return s, s
            end,
            linkedDimensions = true, -- always square; one slider drives both
            setWidth = function(_, wid)
                local profile = P()
                if not profile then return end
                if profile.displayMode == "text" then
                    -- Text display: the box width is measured from the rendered string
                    -- (ApplyText), never an input. Writing it into textSize turned the
                    -- unlock Cancel round-trip (getSize -> setWidth) into a 40-point font.
                    return
                end
                local PPb = CludesUI and CludesUI.PP
                profile.iconSize = math.max(16, PPb and PPb.Snap(wid) or math.floor(wid + 0.5))
                ApplyResTracker()
                if CludesUI._unlockActive and CludesUI.RepositionBarToMover then
                    CludesUI.RepositionBarToMover("CUI_BattleRes")
                end
            end,
            setHeight = function(_, hgt)
                local profile = P()
                if not profile then return end
                if profile.displayMode == "text" then
                    -- Text display: getSize reports the measured box, so a height equal
                    -- to the current one is the unlock round-trip (Cancel feeds the open
                    -- snapshot back) and leaves textSize alone; a different height is a
                    -- real resize, mapped back through ApplyText's box padding.
                    if widget and math.abs(hgt - widget:GetHeight()) < 0.5 then return end
                    profile.textSize = math.max(8, math.min(40, math.floor(hgt + 0.5) - 2))
                else
                    local PPb = CludesUI and CludesUI.PP
                    profile.iconSize = math.max(16, PPb and PPb.Snap(hgt) or math.floor(hgt + 0.5))
                end
                ApplyResTracker()
                if CludesUI._unlockActive and CludesUI.RepositionBarToMover then
                    CludesUI.RepositionBarToMover("CUI_BattleRes")
                end
            end,
            savePos = function(_, anchorPoint, relPoint, posX, posY)
                -- Unlock mode hands over CENTER/CENTER coords; on Cancel the frame
                -- still sits at the dragged spot, so never read the live position.
                local profile = P()
                if not profile then return end
                profile.pos = { centerX = posX, centerY = posY }
            end,
            loadPos = loadPos,
            clearPos = clearPos,
            applyPos = function() ApplyPosition() end,
        }),
    })
end
_G._CUI_BattleRes_RegisterUnlock = RegisterUnlock

-------------------------------------------------------------------------------
--  Init
-------------------------------------------------------------------------------
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    if not CludesUI or not CludesUI.Lite or not CludesUI.Lite.NewDB then return end
    addonName.db = CludesUI.Lite.NewDB("CludesUIQoLDB", defaultSet, true)
    _G._CUI_BattleRes_DB = function() return addonName.db end
    BuildResFrame()
    -- Apply registers events (gated on enabled + visibility) and refreshes
    -- encounter/keystone state as part of _syncEventRegistration
    ApplyResTracker()
    RegisterUnlock()
end)
