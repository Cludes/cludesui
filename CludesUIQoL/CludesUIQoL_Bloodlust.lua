if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
if CUI and CUI.IS_FOREVER then return end -- no raid-wide lust on WoW Forever: no icon, no events, no unlock mover, even when a saved or imported profile has the tracker enabled; the options section is not built there and every reader of the _G._CUI_Bloodlust_* hooks nil-guards
-------------------------------------------------------------------------------
--  CludesUIQoL_Bloodlust.lua
--  Runtime for the Bloodlust Tracker icon. Detects the player's Sated /
--  Exhaustion lockout debuff (the "you cannot Bloodlust again yet" debuff) and
--  shows a single icon with the remaining lockout timer.
--
--  Lightweight by design:
--    * Only registers UNIT_AURA filtered to the player unit (never all units,
--      never a global aura scan) and only while the tracker is enabled.
--    * Pure event driven detection + a 0.5s text ticker that runs only while
--      the icon is actually shown.
--
--  Appearance proxy-reads through to the BattleRes icon: any appearance key the
--  user has NOT overridden on the Bloodlust Tracker uses the BattleRes value,
--  so the tracker "starts identical" to Brez and only diverges once a setting
--  is changed here (the same model used for raid/party frames). Only the Enable
--  dropdown and on-screen position are stored independently per icon. Both icons
--  live side by side in CludesUIQoLDB.profile (battleRes + bloodlust), so
--  existing BattleRes data is never touched.
-------------------------------------------------------------------------------

-- Last-resort texture source for the active-aura path, used only if a lockout
-- debuff ever reports no icon of its own. The resting, ready and preview icon
-- resolve per character through _lustBuffIcon below.
local PREVIEW_SPELL_ID = 2825 -- Bloodlust

-- Player-castable lust spells, checked in this order: the first one the character
-- actually knows supplies the icon, so a Mage sees Time Warp and an Evoker sees
-- Fury of the Aspects rather than the faction default. Spec- and talent-gated
-- spells leave the spellbook on their own, so no class/spec table is needed.
local LUST_SPELLS = {
    2825, -- Bloodlust (Shaman, Horde)
    32182, -- Heroism (Shaman, Alliance)
    80353, -- Time Warp (Mage)
    390386, -- Fury of the Aspects (Evoker)
    272678, -- Primal Rage (Hunter)
}

-- Sated / Exhaustion debuff ids (every lust variant's lockout debuff). These
-- mirror the SATED_DEBUFFS list used by the Raid Frames lust filter.
local SATED_DEBUFFS = {
    57723, -- Exhaustion (Heroism)
    57724, -- Sated (Bloodlust)
    80354, -- Temporal Displacement (Time Warp)
    95809, -- Insanity (Ancient Hysteria)
    160455, -- Fatigued (Netherwinds)
    264689, -- Fatigued (Primal Rage)
    390435, -- Exhaustion (Fury of the Aspects)
}

local _, mod = ...

local SHAPE_MASKS = CUI.SHAPE_MASKS
local BORDER_PX = { none = 0, thin = 1, normal = 2, heavy = 3, strong = 4 }

-------------------------------------------------------------------------------
--  DB access. We reuse the BattleRes DB handle (same SavedVariable) so we do
--  not create a second NewDB on the shared table.
-------------------------------------------------------------------------------
local saved
local function P() -- our own profile slice
    return saved and saved.profile and saved.profile.bloodlust
end
local function BR() -- BattleRes profile slice (proxy fallback source)
    return saved and saved.profile and saved.profile.battleRes
end

-- Per-key fallback defaults (mirror the battleRes appearance defaults). Used
-- only when neither the bloodlust override nor the battleRes value exists.
local APP_DEFAULTS = {
    iconSize = 40,
    iconZoom = 11,
    shape = "none",
    borderSize = "thin",
    borderUseClass = false,
    durationSize = 12,
    durationOffsetX = 0,
    durationOffsetY = 0,
    countSize = 11,
    countOffsetX = 0,
    countOffsetY = 0,
}

-- Effective (proxied) appearance value: bloodlust override -> battleRes -> default.
local function LustVal(key)
    local bl = P()
    if bl and bl[key] ~= nil then return bl[key] end
    local borderRing = BR()
    if borderRing and borderRing[key] ~= nil then return borderRing[key] end
    return APP_DEFAULTS[key]
end

local function EP_borderColor()
    local bl = P()
    if bl and bl.borderColor ~= nil then return bl.borderColor end
    local borderRing = BR()
    if borderRing and borderRing.borderColor ~= nil then return borderRing.borderColor end
    return { r = 0, g = 0, b = 0, a = 1 }
end

-- Ready-display keys and desaturateSated are OWN keys: they have no BattleRes
-- counterpart to follow, so they read straight from the bloodlust slice
-- instead of EP()'s proxy chain.
local READY_DEFAULTS = {
    showSated = true,
    showReady = false,
    readySize = 12,
    readyOffsetX = 0,
    readyOffsetY = 0,
    desaturateSated = true,
}

local function RP(key)
    local bl = P()
    if bl and bl[key] ~= nil then return bl[key] end
    return READY_DEFAULTS[key]
end

local function RP_color()
    local color = P() and P().readyColor
    if color then return color.r or 1, color.g or 1, color.b or 1 end
    return 1, 1, 1
end

local widget, iconTexture, borderTex, durationFS, countFS, cdFrame
local textOverlay, buffTextOverlay, readyText -- text layers (see CreateBloodlustFrame for the level stack)
local buffShade, buffTexture, buffCd, buffDurationFS, buffBorderTex -- the 40s active-lust overlay (sits on top of the debuff icon)
local _satedActive = false
local _readyShown = false -- ready label currently rendered (idempotence for the 0.5s poll)
local _previewOwner -- options page frame driving the live preview (nil = none)
local _previewExpiry = 0 -- stand-in lockout expiry for the preview countdown

-- Preview runs exactly as long as the owning options page is on screen. Reading
-- IsVisible() beats latching a boolean: a page that was hidden, destroyed or
-- replaced by a rebuild ends the preview on its own, in any order.
local function _previewShown() return _previewOwner ~= nil and _previewOwner:IsVisible() and true or false end
local _satedWasPresent = false -- rising-edge baseline so only a FRESH debuff arms the buff window
local _buffExpiry = 0 -- GetTime() when the 40s active-buff window ends
local _buffZoneGuard = 0 -- suppress rising edges until this time (set on zone-in)
-- Last known Sated expiry (GetTime() clock). Synced from the real
-- expirationTime whenever it is readable, and armed as now+600 on a fresh
-- rising edge (every lust lockout is 10 minutes). While 12.1 aura
-- restrictions hide the real value in combat, this carries the countdown.
local _satedExpiryGuess = 0
local UpdateVisibility -- forward declaration (referenced by PollSated below)
local _ticker -- 0.5s countdown ticker (PollSated cancels it directly, see there)
local FormatTime -- forward declaration (shared by the debuff text and the buff overlay)

-------------------------------------------------------------------------------
--  Shape / appearance application (mirrors the BattleRes icon)
-------------------------------------------------------------------------------
local function _resolveBorderColor()
    if LustVal("borderUseClass") then
        local _, classTok = UnitClass("player")
        if classTok and RAID_CLASS_COLORS[classTok] then
            return RAID_CLASS_COLORS[classTok].r,
                RAID_CLASS_COLORS[classTok].g,
                RAID_CLASS_COLORS[classTok].b,
                1
        end
    end
    local color = EP_borderColor()
    if color then return color.r or 0, color.g or 0, color.b or 0, color.a or 1 end
    return 0, 0, 0, 1
end

-- Snap a config-driven layout offset onto the pixel grid. The frame's own edges
-- and center are snapped already (ApplyShape / ApplyPosition), so snapping the
-- offset is what keeps the child anchored to it on the grid too.
local function _snapOff(val)
    local Pix = CUI and CUI.PP
    if Pix and Pix.Snap then return Pix.Snap(val) end
    return val
end

-- Custom-shape outline, shared with the Battle Res icon (CludesUIQoL_BattleRes.lua).
local _applyShapeOutline = mod.QoL_ApplyShapeOutline

-- Border for one icon layer: PP edge strips for "none"/"cropped", the
-- shape-matching atlas (shapeTex) otherwise. Applied to the debuff icon AND to
-- the 40s buff overlay, whose opaque icon would otherwise cover the debuff
-- icon's border. level pins the PP strip container (see CreateBloodlustFrame).
local function _applyBorder(owner, shapeTex, level)
    local Pix = CUI and CUI.PP
    local shapeKey = LustVal("shape") or "none"
    local bs = BORDER_PX[LustVal("borderSize") or "thin"] or 1

    if shapeKey == "none" or shapeKey == "cropped" then
        shapeTex:Hide()
        _applyShapeOutline(owner, nil, 0)
        if Pix then
            if not Pix.GetBorders(owner) then Pix.CreateBorder(owner, 0, 0, 0, 1, 1, "OVERLAY", 2) end
            local brd = Pix.GetBorders(owner)
            if brd then brd:SetFrameLevel(level) end
            if bs > 0 then
                local red, green, blue, a = _resolveBorderColor()
                Pix.UpdateBorder(owner, bs, red, green, blue, a)
                Pix.ShowBorder(owner)
            else
                Pix.HideBorder(owner)
            end
        end
        return
    end

    if Pix and Pix.GetBorders(owner) then Pix.HideBorder(owner) end
    shapeTex:Hide()
    local red, green, blue, a = _resolveBorderColor()
    _applyShapeOutline(owner, shapeKey, bs, red, green, blue, a)
end

-- Configure the buff overlay (texture coords + optional shape mask) so it
-- visually matches the debuff icon underneath it. The overlay owns its OWN mask
-- so the debuff icon's mask lifecycle is never touched.
local function _applyBuffShape()
    if not buffShade then return end
    local shapeKey = LustVal("shape") or "none"

    buffShade:ClearAllPoints()
    buffShade:SetAllPoints(widget)
    buffTexture:SetAllPoints(buffShade)
    buffCd:ClearAllPoints()
    buffCd:SetAllPoints(buffShade)
    _applyBorder(buffShade, buffBorderTex, buffCd:GetFrameLevel() + 1)

    -- Match the debuff icon's duration text exactly (font, size, position).
    buffDurationFS:SetFont(
        (CUI.GetFontPath("extras")) or STANDARD_TEXT_FONT,
        LustVal("durationSize") or 12,
        (CUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG"
    )
    buffDurationFS:ClearAllPoints()
    buffDurationFS:SetPoint(
        "CENTER",
        widget,
        "CENTER",
        _snapOff(LustVal("durationOffsetX") or 0),
        _snapOff(LustVal("durationOffsetY") or 0)
    )

    if shapeKey == "none" or shapeKey == "cropped" then
        if buffTexture._mask then
            if not buffCd:IsForbidden() then
                pcall(buffCd.RemoveMaskTexture, buffCd, buffTexture._mask)
                pcall(buffCd.SetSwipeTexture, buffCd, "")
            end
            buffTexture:RemoveMaskTexture(buffTexture._mask)
            buffTexture._mask:SetTexture(nil)
            buffTexture._mask:Hide()
            buffTexture._mask = nil
        end
        local z = (LustVal("iconZoom") or 11) / 100
        if shapeKey == "cropped" then
            buffTexture:SetTexCoord(z, 1 - z, z + 0.10, 1 - z - 0.10)
        elseif z > 0 then
            buffTexture:SetTexCoord(z, 1 - z, z, 1 - z)
        else
            buffTexture:SetTexCoord(0, 1, 0, 1)
        end
        return
    end

    local maskFile = SHAPE_MASKS[shapeKey]
    if maskFile then
        if not buffTexture._mask then
            buffTexture._mask = buffShade:CreateMaskTexture()
            buffTexture._mask:SetAllPoints(buffTexture)
            buffTexture:AddMaskTexture(buffTexture._mask)
        end
        buffTexture._mask:SetTexture(maskFile, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        buffTexture._mask:Show()
        buffTexture:SetTexCoord(0, 1, 0, 1)
        if not buffCd:IsForbidden() then
            pcall(buffCd.AddMaskTexture, buffCd, buffTexture._mask)
            pcall(buffCd.SetSwipeTexture, buffCd, maskFile)
        end
    end
end

local function ApplyShape()
    if not widget then return end

    local Pix = CUI and CUI.PP
    local shapeKey = LustVal("shape") or "none"

    local size = LustVal("iconSize") or 40
    local fw, fh = size, size
    if shapeKey == "cropped" then fh = math.floor(size * 0.80 + 0.5) end
    if Pix and Pix.Snap then
        fw, fh = Pix.Snap(fw), Pix.Snap(fh)
    end
    widget:SetSize(fw, fh)
    iconTexture:ClearAllPoints()
    iconTexture:SetAllPoints(widget)

    if cdFrame then
        cdFrame:ClearAllPoints()
        cdFrame:SetAllPoints(widget)
    end

    -- Duration text (centered) and count text (bottom-right). Sated debuffs
    -- have no stacks so the count string stays empty, but we keep the field for
    -- 1:1 parity with the BattleRes icon layout.
    durationFS:SetFont(
        (CUI.GetFontPath("extras")) or STANDARD_TEXT_FONT,
        LustVal("durationSize") or 12,
        (CUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG"
    )
    durationFS:ClearAllPoints()
    durationFS:SetPoint(
        "CENTER",
        widget,
        "CENTER",
        _snapOff(LustVal("durationOffsetX") or 0),
        _snapOff(LustVal("durationOffsetY") or 0)
    )

    countFS:SetFont(
        (CUI.GetFontPath("extras")) or STANDARD_TEXT_FONT,
        LustVal("countSize") or 11,
        (CUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG"
    )
    countFS:ClearAllPoints()
    countFS:SetPoint(
        "BOTTOMRIGHT",
        widget,
        "BOTTOMRIGHT",
        _snapOff(-2 + (LustVal("countOffsetX") or 0)),
        _snapOff(2 + (LustVal("countOffsetY") or 0))
    )

    -- Ready label: same font family as the countdown it replaces, but its own
    -- size, colour and offset. Dropped back to hidden so the next poll re-renders
    -- it with the new style instead of leaving a stale string on screen.
    if readyText then
        readyText:SetFont(
            (CUI.GetFontPath("extras")) or STANDARD_TEXT_FONT,
            RP("readySize") or 12,
            (CUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG"
        )
        readyText:ClearAllPoints()
        readyText:SetPoint(
            "CENTER",
            widget,
            "CENTER",
            _snapOff(RP("readyOffsetX") or 0),
            _snapOff(RP("readyOffsetY") or 0)
        )
        readyText:SetTextColor(RP_color())
        readyText:Hide()
        _readyShown = false
    end

    -- PP.CreateBorder parents its container to frame+1, the SAME level
    -- cooldownFrame sits at -- a level TIE the border only won by creation
    -- order. Pin it to its slot in the stack documented at CreateBloodlustFrame
    -- instead of an implicit tie-break a future overlay could flip.
    _applyBorder(widget, borderTex, widget:GetFrameLevel() + 2)

    -----------------------------------------------------------------------
    --  BASE CASE: "none" or "cropped" -- plain texture, no mask
    -----------------------------------------------------------------------
    if shapeKey == "none" or shapeKey == "cropped" then
        if iconTexture._mask then
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

        local z = (LustVal("iconZoom") or 11) / 100
        if shapeKey == "cropped" then
            iconTexture:SetTexCoord(z, 1 - z, z + 0.10, 1 - z - 0.10)
        elseif z > 0 then
            iconTexture:SetTexCoord(z, 1 - z, z, 1 - z)
        else
            iconTexture:SetTexCoord(0, 1, 0, 1)
        end
        return
    end

    -----------------------------------------------------------------------
    --  CUSTOM SHAPE: apply mask (the shape border is set by _applyBorder)
    -----------------------------------------------------------------------
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
        if cdFrame and not cdFrame:IsForbidden() then
            pcall(cdFrame.AddMaskTexture, cdFrame, iconTexture._mask)
            if cdFrame.SetSwipeTexture then pcall(cdFrame.SetSwipeTexture, cdFrame, maskFile) end
        end
    elseif cdFrame and not cdFrame:IsForbidden() then
        if iconTexture._mask then pcall(cdFrame.RemoveMaskTexture, cdFrame, iconTexture._mask) end
        if cdFrame.SetSwipeTexture then pcall(cdFrame.SetSwipeTexture, cdFrame, "") end
    end
end

-------------------------------------------------------------------------------
--  Position. Default starting position sits just to the LEFT of the BattleRes
--  icon, so the first time the tracker is enabled it appears next to Brez.
-------------------------------------------------------------------------------
local function _defaultLeftOfBrezCenter()
    local borderRing = BR()
    local brCX, brCY = 0, 200
    if borderRing and borderRing.pos and borderRing.pos.centerX and borderRing.pos.centerY then
        brCX, brCY = borderRing.pos.centerX, borderRing.pos.centerY
    end
    local brSize = (borderRing and borderRing.iconSize) or 40
    local myW = LustVal("iconSize") or 40
    local gap = 6
    return brCX - (brSize * 0.5 + gap + myW * 0.5), brCY
end

local function PlaceLust()
    if not widget then return end
    local profile = P()
    if not profile then return end
    widget:ClearAllPoints()
    local cx, cy
    if profile.pos and profile.pos.centerX and profile.pos.centerY then
        cx, cy = profile.pos.centerX, profile.pos.centerY
    else
        cx, cy = _defaultLeftOfBrezCenter()
    end
    local PPp = CUI and CUI.PP
    if PPp and PPp.SnapCenterForDim then
        cx = PPp.SnapCenterForDim(cx, widget:GetWidth())
        cy = PPp.SnapCenterForDim(cy, widget:GetHeight())
    end
    widget:SetPoint("CENTER", UIParent, "CENTER", cx, cy)
end

-- Seed a concrete starting position (left of Brez) the first time the tracker
-- is switched away from "Never". Does nothing if a position already exists.
local function SeedDefaultPos()
    local profile = P()
    if not profile then return end
    if profile.pos then return end
    local cx, cy = _defaultLeftOfBrezCenter()
    profile.pos = { centerX = cx, centerY = cy }
    PlaceLust()
end
_G._CUI_Bloodlust_SeedPos = SeedDefaultPos

-------------------------------------------------------------------------------
--  Detection (player-only, secret-value safe)
-------------------------------------------------------------------------------
local function _findSated()
    if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then return nil end
    for index = 1, #SATED_DEBUFFS do
        local spellRef = SATED_DEBUFFS[index]
        -- Known-spellId query works mid-fight ONLY because Sated-class ids are
        -- field-proven unflagged: GetPlayerAuraBySpellID is RequiresNonSecretAura
        -- and returns ZERO VALUES for a restriction-FLAGGED spell while its aura
        -- is up (Burning Rush proved this 2026-08-13 -- do NOT copy this probe
        -- as a general presence pattern; flagged ids need an engine container).
        -- We never read the (possibly secret) spellId back off the aura.
        local auraInfo = C_UnitAuras.GetPlayerAuraBySpellID(spellRef)
        if auraInfo then return auraInfo, spellRef end
    end
    return nil
end

-- 12.1: duration APIs (GetAuraDuration included) hard-error while aura
-- restrictions are active, even with a clean auraInstanceID.
local function AurasRestricted()
    local AK = CUI.AuraKit
    if AK and AK.AurasRestricted then return AK.AurasRestricted() end
    return false
end

-- Sync the expiry cache from the aura whenever the real value is readable
-- (out of combat / unrestricted content).
local function _syncSatedGuess(auraInfo)
    local expiresAt = auraInfo and auraInfo.expirationTime
    if expiresAt and not issecretvalue(expiresAt) and expiresAt > 0 then _satedExpiryGuess = expiresAt end
end

-- Drive the icon texture + cooldown swipe from the active debuff. Secret-safe:
-- the swipe is set from a DurationObject (no value is read by us); under 12.1
-- restrictions it falls back to the cached/self-timed expiry. The numeric
-- countdown text is filled in by the ticker with the same fallback.
local function _applyActiveAura(auraInfo, spellRef)
    if not widget then return end

    local texture = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellRef)
    if not texture and C_Spell and C_Spell.GetSpellTexture then
        texture = C_Spell.GetSpellTexture(PREVIEW_SPELL_ID)
    end
    iconTexture:SetTexture(texture or 136080)

    if cdFrame then
        local iid = auraInfo.auraInstanceID
        if AurasRestricted() then
            -- Swipe from the cached expiry; SetCooldown with the same start
            -- and duration every pass is idempotent (no animation reset).
            if _satedExpiryGuess > GetTime() then cdFrame:SetCooldown(_satedExpiryGuess - 600, 600) end
        elseif iid and not issecretvalue(iid) and C_UnitAuras.GetAuraDuration then
            local durObj = C_UnitAuras.GetAuraDuration("player", iid)
            if durObj then cdFrame:SetCooldownFromDurationObject(durObj) end
        else
            local duration = auraInfo.duration
            local expiresAt = auraInfo.expirationTime
            if
                duration
                and expiresAt
                and not issecretvalue(duration)
                and not issecretvalue(expiresAt)
                and duration > 0
            then
                cdFrame:SetCooldown(expiresAt - duration, duration)
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Active-lust buff overlay. When the lockout debuff is freshly acquired (lust
--  was just cast) we lay a 40s buff icon + cooldown swipe ON TOP of the debuff
--  icon. We cannot read the actual buff, so the 40s window is self-timed. After
--  40s (or on death) the overlay hides, revealing the untouched debuff icon.
-------------------------------------------------------------------------------
-- Icon for "this character's lust". Falls back to the faction buff (Horde
-- Bloodlust / Alliance Heroism) for everyone who cannot cast one themselves.
-- The fallback is cached too: without that, every character who cannot cast a
-- lust re-runs the whole probe on every call, including twice a second from the
-- options preview. A cache taken before the spellbook is populated is corrected
-- by the PLAYER_ENTERING_WORLD reset below (registered on PLAYER_LOGIN, so it
-- catches the login zone-in), and a spec swap drops it as well -- those are the
-- only points at which one of these spells can appear or disappear.
local _lustIconCache
local _lustIconResolved = false
local function _lustBuffIcon()
    if _lustIconResolved then return _lustIconCache end
    for index = 1, #LUST_SPELLS do
        local spellRef = LUST_SPELLS[index]
        local known = (IsPlayerSpell and IsPlayerSpell(spellRef)) or (IsSpellKnown and IsSpellKnown(spellRef))
        if known then
            local texture = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellRef)
            if texture then
                _lustIconCache = texture
                _lustIconResolved = true
                return texture
            end
        end
    end
    _lustIconCache = (UnitFactionGroup("player") == "Alliance") and 132313 or 136012
    _lustIconResolved = true
    return _lustIconCache
end

-- Countdown text for the overlay, deduped so we only SetText on a real change.
local _lastBuffDurText
local function _showBuffDuration(s)
    if s ~= _lastBuffDurText then
        buffDurationFS:SetText(s)
        _lastBuffDurText = s
    end
end

-- Drives the 40s countdown text and hides the overlay the instant it expires.
-- Runs only while the overlay is shown (cleared on hide), so it is never an idle
-- OnUpdate. The expiry check is every frame; the text refresh is throttled.
local _buffAccum = 0
local function _buffOnUpdate(_, elapsed)
    local remaining = _buffExpiry - GetTime()
    if remaining <= 0 then
        _buffExpiry = 0
        buffShade:SetScript("OnUpdate", nil)
        buffShade:Hide()
        _showBuffDuration("")
        -- The window is part of the visibility rule (ShouldShow keeps the icon up
        -- for it even with "Show when Sated" off), so its end has to re-evaluate
        -- rather than wait for the next unrelated event.
        UpdateVisibility()
        return
    end
    _buffAccum = _buffAccum + (elapsed or 0)
    if _buffAccum < 0.1 then return end
    _buffAccum = 0
    -- Buff window is only 40s, so show plain seconds ("40", "39", ...) with no
    -- leading "0:". ceil keeps each number on screen for its full second.
    _showBuffDuration(tostring(math.ceil(remaining)))
end

local function _showBuffOverlay()
    if not buffShade then return end
    buffTexture:SetTexture(_lustBuffIcon())
    _applyBuffShape()
    _buffExpiry = GetTime() + 40
    _buffAccum = 0
    buffCd:SetCooldown(GetTime(), 40)
    _showBuffDuration("40")
    buffShade:Show()
    buffShade:SetScript("OnUpdate", _buffOnUpdate)
end

-- Lockout gone: swap to the lust icon, clear the swipe and show the label in
-- place of the countdown. Guarded so the 0.5s poll re-applies nothing.
local function _showReadyState()
    if _readyShown or not widget then return end
    iconTexture:SetTexture(_lustBuffIcon())
    -- Clear(), never SetCooldown(0, 0): a zero-duration cooldown makes the widget
    -- hide itself, and the leftover swipe has to go either way.
    if cdFrame then cdFrame:Clear() end
    if readyText then
        readyText:SetText(CUI.L("Ready"))
        readyText:Show()
    end
    _readyShown = true
end

local function _clearReady()
    if not _readyShown then return end
    if readyText then readyText:Hide() end
    _readyShown = false
end

-- Grey the base icon while it shows a lockout (real or preview), never in the
-- ready state. The 40s buff overlay is its own texture and stays in colour.
local _lastDesat = false
local function _syncGrey()
    if not iconTexture then return end
    local wanted = (RP("desaturateSated") and not _readyShown) and true or false
    if wanted ~= _lastDesat then
        iconTexture:SetDesaturated(wanted)
        _lastDesat = wanted
    end
end

local function _hideBuffOverlay()
    _buffExpiry = 0
    if buffShade then
        buffShade:SetScript("OnUpdate", nil)
        buffShade:Hide()
    end
    _showBuffDuration("")
end

-------------------------------------------------------------------------------
--  Content state (mirrors the BattleRes icon so "M+"/"Raid" mean the same
--  thing: M+ = an active keystone run, Raid = a raid encounter in progress).
-------------------------------------------------------------------------------
-- Written by ns.RefreshInstanceState / ns.ApplyInstanceEvent (BattleRes file).
local _state = {
    inEncounter = false,
    encounterIsRaid = false,
    inChallenge = false,
}

-------------------------------------------------------------------------------
--  Visibility / text
-------------------------------------------------------------------------------
local function ShouldShow()
    local profile = P()
    if not profile or not profile.enabled then return false end
    local val = profile.visibility or "NEVER"
    if val == "NEVER" then return false end
    -- Options preview: forced on screen while the page is up, skipping the state
    -- gate below along with the instance and M+/raid gates -- the point is to
    -- configure it from anywhere. It deliberately ignores the two toggles for
    -- VISIBILITY: everything above them (size, shape, border, zoom, position)
    -- stays configurable with both switched off, so a blank page would just read
    -- as broken. Which state gets previewed still follows Show Ready, in PollSated.
    if _previewShown() then return true end
    -- Show Sated / Show Ready are independent: which one gates visibility depends
    -- on which state the icon is currently in.
    if _satedActive then
        -- The 40s active-lust overlay is worth seeing even when the lockout
        -- countdown itself is switched off, so only the remainder of the lockout
        -- after that window is suppressed.
        if RP("showSated") == false and _buffExpiry <= GetTime() then return false end
    elseif not RP("showReady") then
        return false
    end

    -- Hard gate: must be in a party or raid instance. Prevents any stuck state
    -- from showing the icon in town / open world.
    local _, instanceType = GetInstanceInfo()
    if instanceType ~= "party" and instanceType ~= "raid" then return false end

    local wantMPlus = (val == "MPLUS_AND_RAID" or val == "MPLUS")
    local wantRaid = (val == "MPLUS_AND_RAID" or val == "RAID")
    if wantMPlus and _state.inChallenge then return true end
    if wantRaid and _state.inEncounter and _state.encounterIsRaid then return true end
    return false
end

FormatTime = mod.FormatTime

local _lastDurText
local function _showDuration(s)
    if s ~= _lastDurText then
        durationFS:SetText(s)
        _lastDurText = s
    end
end

-- Options preview with no real lockout and no ready label: a stand-in 10 minute
-- countdown so icon size, shape and the duration offsets can be judged. It loops
-- on expiry, so a long options session keeps showing something.
local function _showPreviewLockout()
    if not widget then return end
    _clearReady()
    if _previewExpiry <= GetTime() then
        -- Once per cycle: re-setting the SAME values each poll is idempotent, but
        -- re-setting new ones would restart the swipe animation twice a second.
        -- The texture goes here for the same reason -- nothing about it changes
        -- between ticks.
        _previewExpiry = GetTime() + 600
        iconTexture:SetTexture(_lustBuffIcon())
        if cdFrame then cdFrame:SetCooldown(GetTime(), 600) end
    end
    _showDuration(FormatTime(_previewExpiry - GetTime()))
end

-- Text ticker: updates the countdown number and re-confirms the debuff is still present
-- (a safety net in case a UNIT_AURA removal event is ever missed). When the remaining
-- time is secret (in combat) the swipe still animates but the number is left blank.
local function PollSated()
    if not widget then return end
    local auraInfo, auraSid = _findSated()
    if not auraInfo then
        _satedActive = false
        _satedExpiryGuess = 0
        if RP("showReady") then
            -- Render in place and RETURN: UpdateVisibility calls back into this
            -- function whenever the icon is shown, so re-entering it here would
            -- recurse forever now that "not sated" can still mean "shown". That is
            -- also why the ticker is cancelled directly rather than by letting
            -- UpdateVisibility do it: this branch is exactly the path taken when
            -- the ticker (not a UNIT_AURA edge) is what spots the lockout ending,
            -- and the ready state has nothing left to count down.
            if _ticker then
                _ticker:Cancel()
                _ticker = nil
            end
            _showDuration("")
            _showReadyState()
            _syncGrey()
            return
        end
        if _previewShown() then
            -- Same reasoning; the stand-in sets its own countdown text. This is
            -- the fallback state for the preview: Show Ready above picks the ready
            -- label when it is on, everything else previews the lockout, including
            -- the both-off case where the icon has no live state of its own.
            _showPreviewLockout()
            _syncGrey()
            return
        end
        _showDuration("")
        return UpdateVisibility()
    end
    if _readyShown then
        -- Coming back from the ready state (normally the UNIT_AURA edge, but this
        -- poll is also the safety net for a missed one): restore the debuff icon
        -- and its swipe, not just the text.
        _clearReady()
        _applyActiveAura(auraInfo, auraSid)
    end
    local expiresAt = auraInfo.expirationTime
    if expiresAt and not issecretvalue(expiresAt) then
        _syncSatedGuess(auraInfo)
        local remaining = expiresAt - GetTime()
        _showDuration(remaining > 0 and FormatTime(remaining) or "")
    elseif _satedExpiryGuess > GetTime() then
        -- Real value secret (12.1 combat): count down on the cached expiry.
        _showDuration(FormatTime(_satedExpiryGuess - GetTime()))
    else
        _showDuration("")
    end
    _syncGrey()
end

function UpdateVisibility()
    if not widget then return end
    if ShouldShow() then
        if not widget:IsShown() then widget:Show() end
        -- The ticker exists to animate the countdown, so it runs only while the
        -- lockout does. In the ready state there is nothing to count down and a
        -- fresh debuff arrives on UNIT_AURA, so polling there would just burn
        -- aura lookups for the whole encounter.
        if _satedActive or (_previewShown() and not RP("showReady")) then
            if not _ticker then _ticker = C_Timer.NewTicker(0.5, PollSated) end
        elseif _ticker then
            _ticker:Cancel()
            _ticker = nil
        end
        PollSated()
    else
        if widget:IsShown() then widget:Hide() end
        if _ticker then
            _ticker:Cancel()
            _ticker = nil
        end
        -- Preview just ended: drop the stand-in swipe and countdown text so no
        -- later path can surface them as if they were real lockout data.
        if _previewExpiry ~= 0 and not _previewShown() then
            _previewExpiry = 0
            if cdFrame then cdFrame:Clear() end
            _showDuration("")
        end
    end
end
_G._CUI_Bloodlust_UpdateVisibility = UpdateVisibility

-- The options page hands us its frame on build; _previewActive() takes it from there.
function _G._CUI_Bloodlust_SetPreviewOwner(frame)
    _previewOwner = frame
    _previewExpiry = 0 -- every visit starts a fresh stand-in countdown
    UpdateVisibility()
end

local function _readSated()
    local auraInfo, spellRef = _findSated()
    _satedActive = (auraInfo ~= nil)
    if auraInfo then
        _syncSatedGuess(auraInfo)
        _applyActiveAura(auraInfo, spellRef)
    else
        _satedExpiryGuess = 0
    end
    return _satedActive
end

-------------------------------------------------------------------------------
--  Events. The ONLY aura registration is UNIT_AURA filtered to the player unit
--  (never all units, never a global aura scan). The encounter / keystone events
--  mirror the BattleRes icon so the M+/Raid visibility modes match. Everything
--  is registered solely while the tracker is enabled.
-------------------------------------------------------------------------------
local _eventFrame
local function _onEvent(_, evt, _, updateInfo)
    if evt == "UNIT_AURA" then
        local was = _satedWasPresent
        local present = _readSated()
        _satedWasPresent = present
        -- Rising edge = lust was just cast. Arm the 40s active-buff overlay ONLY
        -- on a genuine incremental application: never on a full aura refresh
        -- (zone/login resends every aura) and never inside the post-zone grace
        -- window, so a Sated debuff we already carry when zoning out of a dungeon
        -- can't re-pop the overlay. (The lust BUFF itself is secret-flagged on
        -- 12.1 -- presence reads absent in restricted combat -- so the READABLE
        -- Sated edge is the only viable trigger.)
        -- 12.1: the UNIT_AURA payload (and its fields) can be SECRET in combat;
        -- a secret payload is treated as incremental (full refreshes come from
        -- zone/login, which the zone guard covers; boolean use of a secret errors).
        local isFull = false
        if not issecretvalue(updateInfo) and updateInfo then
            local val = updateInfo.isFullUpdate
            if not issecretvalue(val) and val then isFull = true end
        end
        if present and not was and not isFull and GetTime() >= _buffZoneGuard then
            -- Fresh application: the lockout is a known 10 minutes, so
            -- the cache is exact even while the real expiry is secret.
            -- Re-apply so the swipe picks it up now, not on the next event.
            _satedExpiryGuess = GetTime() + 600
            local auraInfo, spellRef = _findSated()
            if auraInfo then _applyActiveAura(auraInfo, spellRef) end
            _showBuffOverlay()
        end
    elseif evt == "PLAYER_SPECIALIZATION_CHANGED" then
        -- A spec swap can add or remove this character's lust spell. Drop the cached
        -- icon and tear the ready label down properly -- clearing only the latch
        -- would leave the fontstring on screen with the old icon behind it.
        _lustIconResolved = false
        _lustIconCache = nil
        _clearReady()
    elseif evt == "PLAYER_DEAD" then
        -- Buffs drop on death; hide the active-lust overlay even if 40s remain.
        _hideBuffOverlay()
    elseif evt == "PLAYER_ENTERING_WORLD" then
        _lustIconResolved = false
        _lustIconCache = nil
        _readSated()
        -- Baseline the edge tracker so a debuff already present on login/zone-in
        -- is NOT mistaken for a fresh cast (no buff overlay reconstruction), and
        -- suppress edges briefly while the zone's aura table settles.
        _satedWasPresent = _satedActive
        _buffZoneGuard = GetTime() + 1.5
        mod.RefreshInstanceState(_state)
    else
        mod.ApplyInstanceEvent(_state, evt)
    end
    UpdateVisibility()
end

local function _ensureEvents(enabled)
    if not _eventFrame then
        _eventFrame = CreateFrame("Frame")
        _eventFrame:SetScript("OnEvent", _onEvent)
    end
    if enabled then
        _eventFrame:RegisterUnitEvent("UNIT_AURA", "player")
        _eventFrame:RegisterEvent("ENCOUNTER_START")
        _eventFrame:RegisterEvent("ENCOUNTER_END")
        _eventFrame:RegisterEvent("CHALLENGE_MODE_START")
        _eventFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
        _eventFrame:RegisterEvent("CHALLENGE_MODE_RESET")
        _eventFrame:RegisterEvent("WORLD_STATE_TIMER_START")
        _eventFrame:RegisterEvent("WORLD_STATE_TIMER_STOP")
        _eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        _eventFrame:RegisterEvent("PLAYER_DEAD")
        _eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    else
        _eventFrame:UnregisterAllEvents()
    end
end

-------------------------------------------------------------------------------
--  Frame creation
-------------------------------------------------------------------------------
local function BuildLustFrame()
    if widget then return widget end
    widget = CreateFrame("Frame", "CludesUIBloodlustIcon", UIParent)
    widget:SetFrameStrata("MEDIUM")
    widget:SetSize(40, 40)
    widget:Hide()

    iconTexture = widget:CreateTexture(nil, "ARTWORK")
    iconTexture:SetAllPoints(widget)
    iconTexture:SetTexture(_lustBuffIcon() or 136080)
    iconTexture:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    borderTex = widget:CreateTexture(nil, "OVERLAY")
    borderTex:Hide()

    cdFrame = CreateFrame("Cooldown", nil, widget, "CooldownFrameTemplate")
    cdFrame:SetAllPoints(widget)
    cdFrame:SetDrawEdge(false)
    cdFrame:SetHideCountdownNumbers(true) -- we render our own duration text
    cdFrame:SetFrameLevel(widget:GetFrameLevel() + 1)

    -- TWO text layers, one per state, so each state's text reads over its own
    -- border and swipe while the opaque 40s buff icon still covers the debuff
    -- text underneath it (a single shared layer puts the lockout countdown on
    -- top of the buff icon and its 40s number). Level stack inside the frame:
    --   +0 iconTex   +1 cooldownFrame   +2 PP border (pinned in ApplyShape)
    --   +3 debuff text: duration / count / ready
    --   +5 buffOverlay   +6 buffCooldown   +7 buff PP border   +8 buff text
    textOverlay = CreateFrame("Frame", nil, widget)
    textOverlay:SetAllPoints(widget)
    textOverlay:SetFrameLevel(widget:GetFrameLevel() + 3)

    durationFS = textOverlay:CreateFontString(nil, "OVERLAY")
    durationFS:SetFont(
        (CUI.GetFontPath("extras")) or STANDARD_TEXT_FONT,
        14,
        (CUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG"
    )
    durationFS:SetText("")

    -- SetFont FIRST: SetText on a fontstring that has no font yet errors out, and
    -- this runs before ApplyShape ever styles it.
    readyText = textOverlay:CreateFontString(nil, "OVERLAY")
    readyText:SetFont(
        (CUI.GetFontPath("extras")) or STANDARD_TEXT_FONT,
        12,
        (CUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG"
    )
    readyText:SetText("")
    readyText:Hide()

    countFS = textOverlay:CreateFontString(nil, "OVERLAY")
    countFS:SetFont(
        (CUI.GetFontPath("extras")) or STANDARD_TEXT_FONT,
        12,
        (CUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG"
    )
    countFS:SetText("")

    -- 40s active-lust overlay. Sits ABOVE the debuff icon and its swipe; shown
    -- for 40s on a fresh debuff acquire, then hidden, revealing the untouched
    -- debuff icon underneath. We never modify the debuff icon itself.
    buffShade = CreateFrame("Frame", nil, widget)
    buffShade:SetAllPoints(widget)
    buffShade:SetFrameLevel(cdFrame:GetFrameLevel() + 4)
    buffShade:Hide()

    buffTexture = buffShade:CreateTexture(nil, "ARTWORK")
    buffTexture:SetAllPoints(buffShade)

    buffBorderTex = buffShade:CreateTexture(nil, "OVERLAY")
    buffBorderTex:Hide()

    buffCd = CreateFrame("Cooldown", nil, buffShade, "CooldownFrameTemplate")
    buffCd:SetAllPoints(buffShade)
    buffCd:SetDrawEdge(false)
    buffCd:SetHideCountdownNumbers(true)
    buffCd:SetReverse(true) -- active buff: starts bright and darkens as it runs out
    buffCd:SetFrameLevel(buffShade:GetFrameLevel() + 1)

    -- Parented to the overlay, not to frame: the 40s text hides with the window
    -- it belongs to instead of relying on every hide path to blank the string.
    buffTextOverlay = CreateFrame("Frame", nil, buffShade)
    buffTextOverlay:SetAllPoints(buffShade)
    buffTextOverlay:SetFrameLevel(buffCd:GetFrameLevel() + 2)

    buffDurationFS = buffTextOverlay:CreateFontString(nil, "OVERLAY")
    buffDurationFS:SetFont(
        (CUI.GetFontPath("extras")) or STANDARD_TEXT_FONT,
        12,
        (CUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG"
    )
    buffDurationFS:SetText("")

    return widget
end

-------------------------------------------------------------------------------
--  Apply (settings entry point)
-------------------------------------------------------------------------------
local function ApplyLust()
    if not saved then return end
    if not widget then BuildLustFrame() end
    ApplyShape()
    _applyBuffShape()
    PlaceLust()
    local profile = P()
    local enabled = profile and profile.enabled and (profile.visibility ~= "NEVER")
    _ensureEvents(enabled)
    if enabled then
        _readSated()
        -- Baseline so a debuff already present when the tracker is enabled does
        -- not retroactively pop the 40s buff overlay.
        _satedWasPresent = _satedActive
        mod.RefreshInstanceState(_state)
    end
    UpdateVisibility()
end
_G._CUI_Bloodlust_Apply = ApplyLust

-------------------------------------------------------------------------------
--  Unlock mode registration (mirrors the BattleRes icon)
-------------------------------------------------------------------------------
local function RegisterUnlock()
    if not CUI or not CUI.RegisterUnlockElements then return end
    local MK = CUI.MakeUnlockElement
    if not MK then return end
    local loadPos, clearPos = mod.CenterPosFns(P)

    CUI:RegisterUnlockElements({
        MK({
            key = "CUI_Bloodlust",
            label = "Lust",
            group = "Utilities",
            order = 601,
            noAnchorTarget = true, -- icon size changes; nothing should anchor to it
            isHidden = function()
                local profile = P()
                return not profile or not profile.enabled or (profile.visibility == "NEVER")
            end,
            getFrame = function()
                if not widget then BuildLustFrame() end
                return widget
            end,
            getSize = function()
                local s = LustVal("iconSize") or 40
                return s, s
            end,
            linkedDimensions = true, -- always square; one slider drives both
            setWidth = function(_, wid)
                local profile = P()
                if not profile then return end
                local PPb = CUI and CUI.PP
                profile.iconSize = math.max(16, PPb and PPb.Snap(wid) or math.floor(wid + 0.5))
                ApplyLust()
                if CUI._unlockActive and CUI.RepositionBarToMover then
                    CUI.RepositionBarToMover("CUI_Bloodlust")
                end
            end,
            setHeight = function(_, hgt)
                local profile = P()
                if not profile then return end
                local PPb = CUI and CUI.PP
                profile.iconSize = math.max(16, PPb and PPb.Snap(hgt) or math.floor(hgt + 0.5))
                ApplyLust()
                if CUI._unlockActive and CUI.RepositionBarToMover then
                    CUI.RepositionBarToMover("CUI_Bloodlust")
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
            applyPos = function() PlaceLust() end,
        }),
    })
end
_G._CUI_Bloodlust_RegisterUnlock = RegisterUnlock

-------------------------------------------------------------------------------
--  Init. We reuse the BattleRes DB handle, so we wait until it exists (the
--  BattleRes runtime loads first via the TOC; the retry guard covers any
--  ordering surprise).
-------------------------------------------------------------------------------
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    local function init()
        if not (CUI and CUI.Lite) then return end
        local getDB = _G._CUI_BattleRes_DB
        local skinData = getDB and getDB()
        if not skinData then
            C_Timer.After(0.2, init) -- BattleRes DB not ready yet
            return
        end
        saved = skinData
        _G._CUI_Bloodlust_DB = function() return saved end
        BuildLustFrame()
        ApplyLust()
        RegisterUnlock()
    end
    init()
end)
