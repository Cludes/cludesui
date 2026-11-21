if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_Nameplates_Cast.lua
--
--  NameplateFrame: the cast bar, kick tick, interrupts and the spellcast events.
--  Reads the earlier nameplate files through ns and ns._npInternals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._npInternals
-- CludesUINameplates.lua or an earlier nameplate file failed to load.
if not Inner or Inner.broken then return end
Inner.broken = true

local pairs, type = pairs, type
local UnitName = UnitName
local UnitIsUnit = UnitIsUnit
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitClassification = UnitClassification
local UnitCastingInfo, UnitChannelInfo = UnitCastingInfo, UnitChannelInfo
local GetTime = GetTime
local Enum = Enum
local ComputeCastBarTint = mod.ComputeCastBarTint

local defaultSet, GetCastBarHeight, GetCastScale = Inner.defaults, Inner.GetCastBarHeight, Inner.GetCastScale
local GetKickTickColor, GetKickTickEnabled = Inner.GetKickTickColor, Inner.GetKickTickEnabled
local GetShowClassPower, GetTargetScale = Inner.GetShowClassPower, Inner.GetTargetScale
local PANDEMIC_GLOW_STYLES, GetActiveKickSpell = Inner.PANDEMIC_GLOW_STYLES, Inner.GetActiveKickSpell
local NotifyCastEnded, NotifyCastStarted = Inner.NotifyCastEnded, Inner.NotifyCastStarted
local UpdateClassPowerOnPlate, _fallbackPlates = Inner.UpdateClassPowerOnPlate, Inner._fallbackPlates
local castFallbackFrame, NameplateFrame = Inner.castFallbackFrame, Inner.NameplateFrame

local classPowerType
Inner.classPowerTypeSetters[#Inner.classPowerTypeSetters + 1] = function(val) classPowerType = val end
local p
Inner.profileSetters[#Inner.profileSetters + 1] = function(val) p = val end

-- Minor / Non-Elite Enemy Scale: factors cached from the profile (1 = off), so while both
-- are off every hook is one flag read. Each plate stores its type base in _typeScale.
mod._typeScaleOn = false
local minorScale, nonEliteScale = 1, 1

-- Re-reads the plate's type base; true when it changed. Classification is read here only,
-- never in ApplyScale. A unit first seen this session reads "normal" (and its name
-- UNKNOWNOBJECT) until its data arrives, so Non-Elite waits for UNIT_NAME_UPDATE then:
-- a dungeon elite never spawns shrunk and grows back.
function NameplateFrame:UpdateTypeScale()
    local baseColor = 1
    local unitToken = self.unit
    if unitToken and mod._typeScaleOn then
        local c = UnitClassification(unitToken)
        if c == "minus" or c == "trivial" then
            baseColor = minorScale
        elseif c == "normal" and nonEliteScale ~= 1 and mod._inDungeon and not UnitIsPlayer(unitToken) then
            local spellName = UnitName(unitToken)
            if (issecretvalue and issecretvalue(spellName)) or spellName ~= UNKNOWNOBJECT then
                baseColor = nonEliteScale
            end
        end
    end
    if self._typeScale == baseColor then return false end
    self._typeScale = baseColor
    return true
end

-- From the sliders, OnInitialize and RefreshAllSettings.
function mod.NP_RefreshTypeScaleSetting()
    minorScale = ((p and p.minorEnemyScale) or defaultSet.minorEnemyScale) / 100
    nonEliteScale = ((p and p.nonEliteEnemyScale) or defaultSet.nonEliteEnemyScale) / 100
    mod._typeScaleOn = minorScale ~= 1 or nonEliteScale ~= 1
    for _, backing in pairs(mod.plates) do
        if backing.unit then
            backing:UpdateTypeScale()
            backing:ApplyScale()
        end
    end
end

-- Non-Elite Enemy Scale is dungeon-only: from RefreshThreatContextAndPlateColors, which runs
-- on roster, role and spec events too, so the plates are walked only when ns._inDungeon flips.
local lastInDungeon
function mod.NP_RefreshTypeScale()
    local skinData = mod._inDungeon
    if skinData == lastInDungeon then return end
    lastInDungeon = skinData
    if not mod._typeScaleOn or nonEliteScale == 1 then return end
    for _, backing in pairs(mod.plates) do
        if backing.unit and backing:UpdateTypeScale() then backing:ApplyScale() end
    end
end

local function EnsureCastGlowOverlay(self, field, levelOffset)
    local shade = self[field]
    if not shade then
        shade = CreateFrame("Frame", nil, self.cast)
        shade:SetAllPoints(self.cast)
        shade:SetFrameLevel(self.cast:GetFrameLevel() + levelOffset)
        shade:EnableMouse(false)
        self[field] = shade
    end
    return shade
end

-- The two cast bar glows' flat-schema keys, built once (so a cast start does no string work).
local IMP_GLOW_KEYS = CludesUI.Glows.FlatKeys("importantCastGlow")
local TGT_GLOW_KEYS = CludesUI.Glows.FlatKeys("castTargetGlow")
-- One scratch spec for every plate and both glows: StartSpecGlow reads it synchronously.
local castGlowSpec = {}

-- Starts the glow on a cast bar overlay. Restarts only when the setting or the bar size changed.
local function StartCastGlow(self, shade, conf, key)
    local Glows = CludesUI.Glows
    local style = conf[key.style] or defaultSet[key.style] or 1
    if type(style) ~= "number" or style < 1 or style > #PANDEMIC_GLOW_STYLES then style = 1 end
    local specInfo = Glows.SpecFromFlat(castGlowSpec, conf, key, conf[key.mode] or "custom", defaultSet)
    specInfo.style = mod.NP_TO_SHARED_GLOW[style] or 1
    local pW, pH = self.cast:GetWidth(), self.cast:GetHeight()
    if pW < 5 then pW = 100 end
    if pH < 5 then pH = 14 end
    Glows.StartSpecGlow(shade, specInfo, pW, pH, "bar")
end

-- Reads self._castImportant, cached by UpdateCast just before.
function NameplateFrame:UpdateImportantCastGlow()
    local conf = p or defaultSet
    local enabled = conf.importantCastGlow
    if enabled == nil then enabled = defaultSet.importantCastGlow end
    if not enabled then
        self:ClearImportantCastGlow()
        return
    end

    if not C_Spell or not C_Spell.IsSpellImportant then
        self:ClearImportantCastGlow()
        return
    end

    local shade = EnsureCastGlowOverlay(self, "_importantCastOverlay", 5)
    StartCastGlow(self, shade, conf, IMP_GLOW_KEYS)
    self._importantGlowActive = true

    -- SetAlphaFromBoolean handles the secret boolean taint-free.
    -- Important = alpha 1 (glow visible), not important = alpha 0 (glow hidden).
    shade:Show()
    shade:SetAlphaFromBoolean(self._castImportant)
end

-- Cast Targets You Glow (opt-in): the cast bar glows while the cast's target is the player.
-- PlayerIsSpellTarget is SECRET, so it only drives the overlay's alpha. Read at cast start,
-- as Blizzard's own nameplate cast bar does. Runs after UpdateImportantCastGlow: while the
-- important glow shows, it wins (this overlay sits above it), so the important flag folds
-- into this alpha.
function NameplateFrame:UpdateCastTargetGlow()
    local conf = p or defaultSet
    if not conf.castTargetGlow or not PlayerIsSpellTarget then
        self:ClearCastTargetGlow()
        return
    end
    local shade = EnsureCastGlowOverlay(self, "_castTargetOverlay", 6)
    StartCastGlow(self, shade, conf, TGT_GLOW_KEYS)
    self._castTargetGlowActive = true
    shade:Show()
    if self._importantGlowActive then
        -- Both flags may be SECRET: folded C-side, the result only reaches SetAlpha
        -- (the kick tick's pattern).
        local eventName = C_CurveUtil.EvaluateColorValueFromBoolean
        local isImportant = self._castImportant
        if type(isImportant) == "nil" then isImportant = false end
        shade:SetAlpha(eventName(PlayerIsSpellTarget(self.unit), eventName(isImportant, 0, 1), 0))
    else
        shade:SetAlphaFromBoolean(PlayerIsSpellTarget(self.unit))
    end
end

function NameplateFrame:ClearCastTargetGlow()
    if self._castTargetGlowActive and self._castTargetOverlay then
        CludesUI.Glows.StopAllGlows(self._castTargetOverlay)
        self._castTargetOverlay:SetAlpha(0)
        self._castTargetOverlay:Hide()
        self._castTargetGlowActive = false
    end
end

function NameplateFrame:ClearImportantCastGlow()
    if self._importantGlowActive and self._importantCastOverlay then
        CludesUI.Glows.StopAllGlows(self._importantCastOverlay)
        self._importantCastOverlay:SetAlpha(0)
        self._importantCastOverlay:Hide()
        self._importantGlowActive = false
    end
end

-- A cast glow setting changed (its options row, Global Settings > Glows): the casts already
-- showing take it at once. A new cast reads the settings itself.
function mod.NP_RefreshCastGlows()
    for _, backing in pairs(mod.plates) do
        if backing.unit and backing.isCasting then
            backing:UpdateImportantCastGlow()
            backing:UpdateCastTargetGlow()
        end
    end
end

function NameplateFrame:UpdateCast()
    if not self.unit then
        self.cast:Hide()
        self:ApplyNameVisibility()
        return
    end
    local spellName, _, texture, _, _, _, _, kickLocked, castSpellId = UnitCastingInfo(self.unit)
    local channeling = false
    local empowered = false
    if type(spellName) == "nil" then
        spellName, _, texture, _, _, _, kickLocked, castSpellId = UnitChannelInfo(self.unit)
        channeling = true
    end
    if type(spellName) == "nil" then
        if not self._interrupted then self.cast:Hide() end
        self:ApplyNameVisibility()
        self.castTimer:SetText("")
        if self.isCasting then
            if self._castFallback then
                self._castFallback = nil
                _fallbackPlates[self] = nil
                Inner.fallbackCastCount = Inner.fallbackCastCount - 1
                if Inner.fallbackCastCount <= 0 then
                    Inner.fallbackCastCount = 0
                    castFallbackFrame:Hide()
                end
            end
            NotifyCastEnded(self)
        end
        self.isCasting = false
        self._castTex = nil
        self._castDirtyFull = nil
        self:HideKickTick()
        self:ClearImportantCastGlow()
        self:ClearCastTargetGlow()
        self:ApplyScale()
        if
            GetShowClassPower()
            and classPowerType
            and self._cpPips
            and self.unit
            and UnitIsUnit(self.unit, "target")
        then
            UpdateClassPowerOnPlate(self)
        end
        return
    end

    if self._interrupted then
        self._interrupted = nil
        if self._interruptTimer then
            self._interruptTimer:Cancel()
            self._interruptTimer = nil
        end
    end

    -- FAST PATH: on DELAYED/UPDATE events (not START), the icon, name, target, and glow
    -- haven't changed; only duration needs updating. _castDirtyFull is set by
    -- UNIT_SPELLCAST_START/CHANNEL_START/EMPOWER_START.
    local isFullSetup = self._castDirtyFull or not self.isCasting
    self._castDirtyFull = nil

    if isFullSetup then
        self.cast:Show()
        self:ApplyNameVisibility()
        -- Icon and name MUST describe the SAME cast: both come from this UnitCastingInfo/
        -- UnitChannelInfo snapshot. The icon uses the live texture (possibly SECRET --
        -- SetTexture accepts secrets natively), never a cached/leftover icon.
        if type(texture) ~= "nil" then
            self.castIcon:SetTexture(texture)
        elseif type(castSpellId) ~= "nil" then
            -- Texture genuinely absent (rare): fall back to THIS cast's spell icon. pcall
            -- guards an invalid/0/unknown spellID; iconID feeds SetTexture, never branched on.
            local okInfo, details = pcall(C_Spell.GetSpellInfo, castSpellId)
            if okInfo and type(details) == "table" then
                self.castIcon:SetTexture(details.iconID)
            else
                self.castIcon:SetTexture(nil)
            end
        else
            self.castIcon:SetTexture(nil)
        end
        self:UpdateCastText(spellName)
        self.castTimer:SetShown(self._showCastTimer)

        if type(kickLocked) == "nil" then kickLocked = false end
        self._kickProtected = kickLocked
        -- Cache the game's "important" flag for the cast bar colour. May be SECRET, so it is
        -- stored raw and only fed to a boolean-curve evaluator, never branched on. pcall
        -- guards a 0/invalid spellID. Persists across interruptible flips/kick ticker reuse.
        self._castImportant = false
        if C_Spell and C_Spell.IsSpellImportant then
            local impOK, importance = pcall(C_Spell.IsSpellImportant, castSpellId or 0)
            if impOK then self._castImportant = importance end
        end
        -- A cast that starts before the last one's stop was handled skips NotifyCastStarted:
        -- Full Opacity While Casting (Important Casts) takes the new flag here.
        if self.isCasting and mod._ntCastFull and mod._ntCastImportantOnly and mod._ntAlpha < 1 then
            self._ntBoolHi = nil
            mod.NT_Apply(self)
        end
        local conf = p or defaultSet
        local lockedColor = conf.castBarUninterruptible or defaultSet.castBarUninterruptible
        if self._blizzCastArt then
            -- Blizzard Style: the overlay IS the stock grey fill art (painted
            -- white; the user's colour stays if that atlas never seated), and
            -- the fill atlas follows the cast kind.
            if self._blizzShieldFill then
                self.castBarOverlay:SetVertexColor(1, 1, 1)
            else
                self.castBarOverlay:SetVertexColor(lockedColor.r, lockedColor.g, lockedColor.b)
            end
            self._blizzCastLastKind = channeling and "channel" or "cast"
            mod.NP_SetBlizzCastFill(self, self._blizzCastLastKind)
        else
            self.castBarOverlay:SetVertexColor(lockedColor.r, lockedColor.g, lockedColor.b)
        end
        self.castShieldFrame:Show()
        self:ApplyCastColor(kickLocked)
    end

    if UnitCastingDuration and self.cast.SetTimerDuration then
        if channeling then
            local castLen
            -- Empowered channel duration first (Evoker empower spells): normal UnitChannelDuration
            -- can return nil during the empower phase, leaving the bar unticked despite a name.
            if UnitEmpoweredChannelDuration then
                castLen = UnitEmpoweredChannelDuration(self.unit, true)
                if castLen then empowered = true end
            end
            if not castLen then castLen = UnitChannelDuration(self.unit) end
            if castLen then
                self.cast:SetReverseFill(false)
                -- Empowered channels fill forward (elapsed time / stages);
                -- normal channels fill backward (remaining time).
                local direction = empowered and Enum.StatusBarTimerDirection.ElapsedTime
                    or Enum.StatusBarTimerDirection.RemainingTime
                self.cast:SetTimerDuration(castLen, nil, direction)
                if not self.isCasting then NotifyCastStarted(self) end
                self.isCasting = true
            end
        else
            local castLen = UnitCastingDuration(self.unit)
            if castLen then
                self.cast:SetReverseFill(false)
                self.cast:SetTimerDuration(castLen, nil, Enum.StatusBarTimerDirection.ElapsedTime)
            end
            if not self.isCasting then NotifyCastStarted(self) end
            self.isCasting = true
        end
    else
        if not self.isCasting then
            self.isCasting = true
            self._castFallback = true
            _fallbackPlates[self] = true
            Inner.fallbackCastCount = Inner.fallbackCastCount + 1
            castFallbackFrame:Show()
            NotifyCastStarted(self)
        end
    end
    -- Cast kind for the STOP handler (UNIT_SPELLCAST_STOP): cached here rather than
    -- read back, since the read is what can go stale/secret at the stop edge.
    self._castIsChannel = channeling
    if isFullSetup then
        self._kickGeoDirty = nil
        self:ApplyScale()
        self:UpdateKickTick(kickLocked, channeling, empowered)
        self:UpdateImportantCastGlow()
        self:UpdateCastTargetGlow()
        if p and p.castingEnemyColors then mod.NP_NoteCastKind(self, kickLocked) end
        if
            GetShowClassPower()
            and classPowerType
            and self._cpPips
            and self.unit
            and UnitIsUnit(self.unit, "target")
        then
            UpdateClassPowerOnPlate(self)
        end
    elseif self._kickGeoDirty then
        -- Cast timing changed mid-cast (delay/channel/empower update): re-derive kick
        -- geometry from the cached cast identity
        self._kickGeoDirty = nil
        self:UpdateKickTick(self._kickProtected, self._kickIsChannel, self._kickIsEmpowered)
    end
end
-- Smooth scale transitions: one shared OnUpdate eases every plate whose displayed scale
-- (_curScale) differs from its destination (_destScale). Driver hides itself the instant no
-- plate is animating, so idle costs nothing; at target/cast scale 100 dest stays 1 and
-- ApplyScale snaps without enrolling.
mod._scaleAnim = {} -- [plate] = true while its scale is easing
do
    local SPEED = 11 -- exponential approach rate (higher = snappier)
    local SNAP = 0.004 -- within this of dest -> finish and drop from set
    local anim = mod._scaleAnim
    local driver = CreateFrame("Frame")
    driver:Hide()
    driver:SetScript("OnUpdate", function(_, elapsed)
        -- Frame-rate independent ease: same settle time at any FPS.
        local t = 1 - math.exp(-SPEED * elapsed)
        for backing in pairs(anim) do
            local current = backing._curScale or 1
            local destColor = backing._destScale or 1
            local nv = current + (destColor - current) * t
            if nv - destColor < SNAP and destColor - nv < SNAP then
                nv = destColor
                anim[backing] = nil
            end
            backing._curScale = nv
            backing:SetScale(nv)
            -- The held "Interrupted" flash keeps the bar visible after isCasting clears; it must ride the shrink-back too.
            if (backing.isCasting or backing._interrupted) and mod.RefreshCastOverlay then
                mod.RefreshCastOverlay(backing)
            end
        end
        if not next(anim) then driver:Hide() end
    end)
    mod._ScaleDriverShow = function() driver:Show() end
end
function NameplateFrame:ApplyScale()
    local baseColor = 1
    if self.unit and UnitIsUnit(self.unit, "target") then
        local ts = GetTargetScale() / 100
        if ts ~= 1 then baseColor = ts end
    elseif mod._typeScaleOn then
        -- Minor Enemy Scale: minor (minus) and trivial mobs. Non-Elite Enemy Scale: normal NPCs in
        -- dungeons (the Mini Enemies color's scope). The target keeps Target Scale.
        baseColor = self._typeScale or 1
    end
    local cs = GetCastScale() / 100
    local destColor = baseColor
    if self.isCasting and cs ~= 1 then destColor = baseColor * cs end
    self._destScale = destColor
    local current = self._curScale
    if current == nil or (destColor - current < 0.004 and current - destColor < 0.004) then
        -- Fresh/recycled plate, or already at the destination: snap instantly.
        self._curScale = destColor
        mod._scaleAnim[self] = nil
        self:SetScale(destColor)
    else
        -- Ease toward the new destination via the shared OnUpdate driver.
        mod._scaleAnim[self] = true
        mod._ScaleDriverShow()
    end
    -- Lifted cast bar renders outside this plate's scale chain; keep its container pinned to the plate's effective scale.
    if mod.RefreshCastOverlay then mod.RefreshCastOverlay(self) end
end
function NameplateFrame:ApplyCastColor(cannotKick)
    local conf = p or defaultSet
    local kickReadyTint = conf.interruptReady or defaultSet.interruptReady
    local normalCastTint = conf.castBar or defaultSet.castBar
    -- Blizzard Style: the fill atlas is its own colour, so the normal and
    -- uninterruptible tints are white; the kick-ready and Important tints
    -- still layer on top exactly as before. No per-call allocation.
    local blizzCast = self._blizzCastArt
    if blizzCast then
        if not mod._npWhite then mod._npWhite = { r = 1, g = 1, b = 1 } end
        normalCastTint = mod._npWhite
    end
    -- Important Cast Color (opt-in): a cast the game flags important shows the Important
    -- colour. The flag may be SECRET, so blend per channel via EvaluateColorValueFromBoolean
    -- (ifTrue=Important, ifFalse=the tint it replaces), never branch on it. Two priorities
    -- (importantCastKickReadyAsInterruptible): off (default), Important replaces Interruptible
    -- and Interrupt-on-CD still wins; on, Interruptible wins while the kick is ready and
    -- Important replaces Interrupt-on-CD. On with no known kick falls back to off, else
    -- Important would never show. Uninterruptible casts keep their look (overlay on top).
    local importantOn = conf.importantCastColorEnabled
    if importantOn == nil then importantOn = defaultSet.importantCastColorEnabled end
    if importantOn and C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean then
        local importance = conf.castBarImportant or defaultSet.castBarImportant
        local isImportant = self._castImportant
        if type(isImportant) == "nil" then isImportant = false end
        local kickFirst = conf.importantCastKickReadyAsInterruptible
        if kickFirst == nil then kickFirst = defaultSet.importantCastKickReadyAsInterruptible end
        local impFirst = not (kickFirst and GetActiveKickSpell())
        local under = impFirst and normalCastTint or kickReadyTint
        local eventName = C_CurveUtil.EvaluateColorValueFromBoolean
        -- Scratch table (same pattern as _dispelScratch): runs per cast event per plate, a fresh color table per call was pure GC churn.
        local sc = mod._castImpScratch
        if not sc then
            sc = {}
            mod._castImpScratch = sc
        end
        sc.r = eventName(isImportant, importance.r, under.r)
        sc.g = eventName(isImportant, importance.g, under.g)
        sc.b = eventName(isImportant, importance.b, under.b)
        if impFirst then
            normalCastTint = sc
        else
            kickReadyTint = sc
        end
    end
    local cr, cg, callback = ComputeCastBarTint(kickReadyTint, normalCastTint)

    -- Match the base cast fill to uninterruptible casts so plate opacity
    -- doesn't reveal the interruptible color underneath the overlay.
    if C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean then
        local lockedColor = blizzCast and mod._npWhite
            or (conf.castBarUninterruptible or defaultSet.castBarUninterruptible)
        -- The settings-refresh callers pass the stored _kickProtected stamp,
        -- which is nil until the first cast event -- and a nil reaching the
        -- fold throws. type() is the secret-legal nil test (a plain == nil
        -- compare throws on a secret boolean), same idiom as the Important
        -- Cast block above.
        local isUnint = cannotKick
        if type(isUnint) == "nil" then isUnint = false end
        local eventName = C_CurveUtil.EvaluateColorValueFromBoolean
        cr = eventName(isUnint, lockedColor.r, cr)
        cg = eventName(isUnint, lockedColor.g, cg)
        callback = eventName(isUnint, lockedColor.b, callback)
    end
    self.cast:GetStatusBarTexture():SetVertexColor(cr, cg, callback)
    -- Shield icon is opt-out: when disabled it never shows, even on uninterruptible casts. The
    -- setting is a clean boolean, so it gates the (possibly SECRET) flag without evaluating it.
    local showShield = true
    if conf.castBarShieldEnabled ~= nil then showShield = conf.castBarShieldEnabled end
    if self.castBarOverlay.SetAlphaFromBoolean then
        self.castBarOverlay:SetAlphaFromBoolean(cannotKick)
        if showShield then
            self.castShieldFrame:SetAlphaFromBoolean(cannotKick)
        else
            self.castShieldFrame:SetAlpha(0)
        end
    else
        local a = cannotKick and 1 or 0
        self.castBarOverlay:SetAlpha(a)
        self.castShieldFrame:SetAlpha(showShield and a or 0)
    end
end
function NameplateFrame:HideKickTick()
    self.kickPositioner:Hide()
    self.kickMarker:Hide()
    self.kickReadyFill:Hide()
    if self._kickTicker then
        self._kickTicker:Cancel()
        self._kickTicker = nil
    end
end
function NameplateFrame:UpdateKickTick(kickLocked, channeling, empowered)
    -- Two independent CLEAN toggles drive this geometry: the visible tick (kickTickEnabled)
    -- and the interrupt-ready mid-cast fill (interruptMidCastEnabled). Either needs the
    -- positioner/marker StatusBars below; each visible element is gated on its own toggle.
    local tickOn = GetKickTickEnabled()
    local midOn = defaultSet.interruptMidCastEnabled
    if p and p.interruptMidCastEnabled ~= nil then midOn = p.interruptMidCastEnabled end
    if (not (tickOn or midOn)) or not GetActiveKickSpell() then
        self:HideKickTick()
        return
    end
    -- kickProtected is a SECRET boolean: never branch on it. Store it and apply visibility via
    -- SetAlphaFromBoolean after setup. isChannel/isEmpowered cached too (cooldown watcher
    -- re-setups from these).
    self._kickProtected = kickLocked
    self._kickIsChannel = channeling
    self._kickIsEmpowered = empowered
    if not (C_Spell and C_Spell.GetSpellCooldownDuration) then
        self:HideKickTick()
        return
    end
    -- Midnight path: use secret duration objects
    if UnitCastingDuration and self.cast.SetTimerDuration then
        local castLen
        if channeling then
            if empowered and UnitEmpoweredChannelDuration then
                castLen = UnitEmpoweredChannelDuration(self.unit, true)
            end
            if not castLen then castLen = UnitChannelDuration(self.unit) end
        else
            castLen = UnitCastingDuration(self.unit)
        end
        if not castLen then
            self:HideKickTick()
            return
        end
        local totalDur = castLen:GetTotalDuration()
        local kickCooldown = C_Spell.GetSpellCooldownDuration(GetActiveKickSpell())
        if not kickCooldown then
            self:HideKickTick()
            return
        end
        -- Size the StatusBars to match the cast bar (positioner uses SetPoint("CENTER"), not SetAllPoints)
        local castH = GetCastBarHeight()
        local barW = self.cast:GetWidth()
        self.kickPositioner:SetSize(barW, castH)
        self.kickPositioner:SetMinMaxValues(0, totalDur)
        self.kickMarker:SetMinMaxValues(0, totalDur)
        self.kickMarker:SetSize(barW, castH)
        -- Initial PAIRED snapshot: the tick's position is positioner(elapsed) +
        -- marker(kick CD remaining), which equals the fixed "kick ready here" point only when
        -- both are sampled at the same instant. RefreshKickTick re-pins the pair on every
        -- cooldown event. NEVER update one without the other -- a marker-only refresh drifts
        -- the tick left.
        self.kickPositioner:SetValue(castLen:GetElapsedDuration())
        self.kickMarker:SetValue(kickCooldown:GetRemainingDuration())
        -- Apply color
        local kr, kg, kb = GetKickTickColor()
        self.kickTick:SetColorTexture(kr, kg, kb, 1)
        -- Handle channel vs cast fill direction. Empowered channels fill
        -- forward (like a normal cast), so treat them as non-channel here.
        if channeling and not empowered then
            self.kickPositioner:SetFillStyle(Enum.StatusBarFillStyle.Reverse)
            self.kickMarker:SetFillStyle(Enum.StatusBarFillStyle.Reverse)
            -- LOAD-BEARING: SetFillStyle resets the inner fill to snap-ON and the global
            -- SetStatusBarTexture unsnap hook will NOT re-fire (caches per StatusBar frame).
            -- Re-disable snap so positioner(elapsed) + marker(CD remaining) stays an exact
            -- float and the tick holds still.
            local pt = self.kickPositioner:GetStatusBarTexture()
            if pt and pt.SetSnapToPixelGrid then
                pt:SetSnapToPixelGrid(false)
                pt:SetTexelSnappingBias(0)
            end
            local mt = self.kickMarker:GetStatusBarTexture()
            if mt and mt.SetSnapToPixelGrid then
                mt:SetSnapToPixelGrid(false)
                mt:SetTexelSnappingBias(0)
            end
            self.kickMarker:ClearAllPoints()
            self.kickTick:ClearAllPoints()
            self.kickMarker:SetPoint("RIGHT", self.kickPositioner:GetStatusBarTexture(), "LEFT")
            self.kickTick:SetPoint("TOP", self.kickMarker, "TOP", 0, 0)
            self.kickTick:SetPoint("BOTTOM", self.kickMarker, "BOTTOM", 0, 0)
            self.kickTick:SetPoint("RIGHT", self.kickMarker:GetStatusBarTexture(), "LEFT")
            -- Reverse fill (draining channel): the kick-ready point is the
            -- marker texture LEFT edge; the "kick available" window runs from
            -- the channel end (bar left) to that point. Not-in-time pushes the
            -- marker edge past the left edge, crossing the anchors to zero width.
            self.kickReadyFill:ClearAllPoints()
            self.kickReadyFill:SetPoint("TOP", self.cast, "TOP", 0, 0)
            self.kickReadyFill:SetPoint("BOTTOM", self.cast, "BOTTOM", 0, 0)
            self.kickReadyFill:SetPoint("LEFT", self.cast, "LEFT", 0, 0)
            self.kickReadyFill:SetPoint("RIGHT", self.kickMarker:GetStatusBarTexture(), "LEFT")
        else
            self.kickPositioner:SetFillStyle(Enum.StatusBarFillStyle.Standard)
            self.kickMarker:SetFillStyle(Enum.StatusBarFillStyle.Standard)
            -- LOAD-BEARING: re-disable snap on the re-minted fill textures (see the reverse
            -- branch) so the summed elapsed+remaining edge is exact and the tick stays still.
            local pt = self.kickPositioner:GetStatusBarTexture()
            if pt and pt.SetSnapToPixelGrid then
                pt:SetSnapToPixelGrid(false)
                pt:SetTexelSnappingBias(0)
            end
            local mt = self.kickMarker:GetStatusBarTexture()
            if mt and mt.SetSnapToPixelGrid then
                mt:SetSnapToPixelGrid(false)
                mt:SetTexelSnappingBias(0)
            end
            self.kickMarker:ClearAllPoints()
            self.kickTick:ClearAllPoints()
            self.kickMarker:SetPoint("LEFT", self.kickPositioner:GetStatusBarTexture(), "RIGHT")
            self.kickTick:SetPoint("TOP", self.kickMarker, "TOP", 0, 0)
            self.kickTick:SetPoint("BOTTOM", self.kickMarker, "BOTTOM", 0, 0)
            self.kickTick:SetPoint("LEFT", self.kickMarker:GetStatusBarTexture(), "RIGHT")
            -- Standard fill (cast/empowered channel): the kick-ready point is the marker
            -- texture RIGHT edge; the "kick available" window runs from it to cast end (bar
            -- right). Not-in-time pushes the marker edge past the right edge, zeroing width.
            self.kickReadyFill:ClearAllPoints()
            self.kickReadyFill:SetPoint("TOP", self.cast, "TOP", 0, 0)
            self.kickReadyFill:SetPoint("BOTTOM", self.cast, "BOTTOM", 0, 0)
            self.kickReadyFill:SetPoint("LEFT", self.kickMarker:GetStatusBarTexture(), "RIGHT")
            self.kickReadyFill:SetPoint("RIGHT", self.cast, "RIGHT", 0, 0)
        end
        self.kickPositioner:Show()
        self.kickMarker:Show()
        -- Mid-cast fill: CLEAN DB color tint + CLEAN per-toggle visibility. Its alpha (the
        -- SECRET on-CD x interruptible gate) is applied with the tick alpha below. Geometry
        -- above runs when the tick OR the fill is enabled; SetShown gates each independently.
        local mc = (p and p.interruptMidCastColor) or defaultSet.interruptMidCastColor
        self.kickReadyFill:SetVertexColor(mc.r, mc.g, mc.b, 1)
        self.kickTick:SetShown(tickOn)
        self.kickReadyFill:SetShown(midOn)
        -- Compute initial tick alpha immediately (avoids split-second delay
        -- from waiting for the first ticker fire at 0.1s).
        if kickCooldown.IsZero and C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean then
            local canKick = C_CurveUtil.EvaluateColorValueFromBoolean(self._kickProtected, 0, 1)
            local kickReady = kickCooldown:IsZero()
            local opacity = C_CurveUtil.EvaluateColorValueFromBoolean(kickReady, 0, canKick)
            self.kickTick:SetAlpha(opacity)
            self.kickReadyFill:SetAlpha(opacity)
        else
            self.kickTick:SetAlpha(0)
            self.kickReadyFill:SetAlpha(0)
        end
        -- Ticker: tick ALPHA only at 10fps (kick-ready x interruptibility secret combine). Bar
        -- values are re-pinned as a PAIR by RefreshKickTick on cooldown events, not here.
        if self._kickTicker then self._kickTicker:Cancel() end
        -- Self-identifying ticker: a superseded ticker cancels ITSELF rather than
        -- calling HideKickTick, which would cancel its successor.
        local ownTicker
        ownTicker = C_Timer.NewTicker(0.1, function()
            if self._kickTicker ~= ownTicker then
                ownTicker:Cancel()
                return
            end
            if not self.isCasting or not self.unit then
                self:HideKickTick()
                return
            end
            -- activeKickSpell can go nil mid-cast if a spec/talent change fires SPELLS_CHANGED
            -- and the new spec has no kick learned. Bail rather than pass nil to C_Spell.
            if not GetActiveKickSpell() then
                self:HideKickTick()
                return
            end
            -- Compute tick visibility: show only when kick is on CD AND cast is interruptible.
            -- Both are secret booleans, chain EvaluateColorValueFromBoolean calls to combine.
            local interruptCd = C_Spell.GetSpellCooldownDuration(GetActiveKickSpell())
            if
                interruptCd
                and interruptCd.IsZero
                and C_CurveUtil
                and C_CurveUtil.EvaluateColorValueFromBoolean
            then
                local canKick = C_CurveUtil.EvaluateColorValueFromBoolean(self._kickProtected, 0, 1)
                local kickReady = interruptCd:IsZero()
                local opacity = C_CurveUtil.EvaluateColorValueFromBoolean(kickReady, 0, canKick)
                self.kickTick:SetAlpha(opacity)
                self.kickReadyFill:SetAlpha(opacity)
            end
        end)
        self._kickTicker = ownTicker
    else
        -- API not available; hide tick
        self:HideKickTick()
    end
end
-- Light per-cooldown-event refresh: bar values + tick alpha only; geometry (sizes, anchors,
-- fill styles, colors) is cast-identity work done once by UpdateKickTick. CRITICAL: the tick
-- position is positioner(elapsed) + marker(remaining), the true "kick ready here" point only
-- when BOTH snapshots are taken at the same instant -- re-pinning the marker alone drifts the
-- tick left. Always re-pin both together.
function NameplateFrame:RefreshKickTick()
    if not GetActiveKickSpell() or not (C_Spell and C_Spell.GetSpellCooldownDuration) then
        self:HideKickTick()
        return
    end
    local interruptCd = C_Spell.GetSpellCooldownDuration(GetActiveKickSpell())
    if not interruptCd then
        -- Transient read miss during an ongoing cast: skip this refresh and keep the current
        -- tick/fill. Hiding here would make the tick and kick-ready bar blink through the
        -- rotation. Genuine cast-end is handled by cast-stop/interrupt paths.
        return
    end
    if UnitCastingDuration and self.unit then
        local castLen
        if self._kickIsChannel then
            if self._kickIsEmpowered and UnitEmpoweredChannelDuration then
                castLen = UnitEmpoweredChannelDuration(self.unit, true)
            end
            if not castLen then castLen = UnitChannelDuration(self.unit) end
        else
            castLen = UnitCastingDuration(self.unit)
        end
        if not castLen then
            -- Transient read miss (see above): skip, do not hide.
            return
        end
        self.kickPositioner:SetValue(castLen:GetElapsedDuration())
    end
    self.kickMarker:SetValue(interruptCd:GetRemainingDuration())
    if interruptCd.IsZero and C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean then
        local canKick = C_CurveUtil.EvaluateColorValueFromBoolean(self._kickProtected, 0, 1)
        local opacity = C_CurveUtil.EvaluateColorValueFromBoolean(interruptCd:IsZero(), 0, canKick)
        self.kickTick:SetAlpha(opacity)
        self.kickReadyFill:SetAlpha(opacity)
    end
end
function NameplateFrame:ShowInterrupted(kickerGuid)
    if self.isCasting then
        if self._castFallback then
            self._castFallback = nil
            _fallbackPlates[self] = nil
            Inner.fallbackCastCount = Inner.fallbackCastCount - 1
            if Inner.fallbackCastCount <= 0 then
                Inner.fallbackCastCount = 0
                castFallbackFrame:Hide()
            end
        end
        NotifyCastEnded(self)
    end
    self.isCasting = false
    self:HideKickTick()
    self:ApplyScale()

    -- If the interrupted flash effect is disabled, end the cast like a normal
    -- stop (hide the bar) without the flash + held "Interrupted" text.
    local flashOn = defaultSet.interruptedFlashEnabled
    if p and p.interruptedFlashEnabled ~= nil then flashOn = p.interruptedFlashEnabled end
    if not flashOn then
        self.cast:Hide()
        self:ApplyNameVisibility()
        return
    end

    self._interrupted = true
    self.cast:SetReverseFill(false)
    self.cast:SetMinMaxValues(0, 1)
    self.cast:SetValue(1)
    if self._blizzCastArt then
        -- Blizzard Style: the stock interrupted fill art, untinted.
        mod.NP_SetBlizzCastFill(self, "interrupted")
        self.cast:GetStatusBarTexture():SetVertexColor(1, 1, 1)
    else
        local fc = (p and p.interruptedFlashColor) or defaultSet.interruptedFlashColor
        self.cast:GetStatusBarTexture():SetVertexColor(fc.r, fc.g, fc.b)
    end

    -- GetPlayerInfoByGUID accepts the event's SECRET interrupter GUID and may
    -- return a SECRET name/class. Keep those values opaque until native sinks.
    local kickerName
    local interrupterClass
    if type(kickerGuid) ~= "nil" then
        local _, class, _, _, _, spellName = GetPlayerInfoByGUID(kickerGuid)
        interrupterClass = class
        kickerName = spellName
        if type(kickerName) == "nil" then
            -- Fallback for a NON-player interrupter GUID (pet or NPC): GetPlayerInfoByGUID
            -- only resolves players, so pull the name from the GUID's live unit token instead.
            -- Non-players have no class, so interrupterClass stays nil and the class-color path
            -- is skipped. A SECRET GUID resolves to a SECRET token/name; both pass straight to
            -- SetFormattedText as display args, so the name still shows. type() is the only legal check.
            local token = UnitTokenFromGUID(kickerGuid)
            if type(token) ~= "nil" then kickerName = UnitName(token) end
        end
    end
    local conf = p or defaultSet
    local useClassColor = defaultSet.castTargetClassColor
    if conf.castTargetClassColor ~= nil then useClassColor = conf.castTargetClassColor end
    local castNameColor = conf.castNameColor or defaultSet.castNameColor
    local interrupterColor
    if useClassColor and type(interrupterClass) ~= "nil" and C_ClassColor then
        interrupterColor = C_ClassColor.GetClassColor(interrupterClass)
    end
    if interrupterColor then
        self.castName:SetTextColor(interrupterColor:GetRGB())
    else
        self.castName:SetTextColor(castNameColor.r, castNameColor.g, castNameColor.b, 1)
    end

    -- Show the interrupter inline as "Interrupted (Name)" in the single cast-name
    -- FontString; the cast-target / timer slots are cleared during the flash.
    local hasInterrupter = type(kickerName) ~= "nil"
    local castWidth = self.cast:GetWidth()
    if castWidth and castWidth > 0 then
        local cnWPct = (p and p.castNameWidthPct) or defaultSet.castNameWidthPct
        self.castName:SetWidth(hasInterrupter and math.max(castWidth - 8, 20) or castWidth * cnWPct / 100)
    end

    local interruptedText = (CludesUI.L("Interrupted")) or "Interrupted"
    if hasInterrupter then
        -- The base FontString color carries SECRET class RGB; only the clean
        -- localized label/punctuation uses an inline profile-color escape.
        local nameHex = string.format(
            "ff%02x%02x%02x",
            math.floor(castNameColor.r * 255 + 0.5),
            math.floor(castNameColor.g * 255 + 0.5),
            math.floor(castNameColor.b * 255 + 0.5)
        )
        self.castName:SetFormattedText(
            "|c" .. nameHex .. "%s (|r%s|c" .. nameHex .. ")|r",
            interruptedText,
            kickerName
        )
    else
        self.castName:SetText(interruptedText)
    end

    self.castTarget:SetText("")
    self.castTarget:Hide()
    self.castTimer:Hide()
    self.castShieldFrame:Hide()
    self.castShieldFrame:SetAlpha(1)
    self.castBarOverlay:SetAlpha(0)
    self.cast:Show()
    self:ApplyNameVisibility()

    if self._interruptTimer then
        self._interruptTimer:Cancel()
        self._interruptTimer = nil
    end

    self._interruptTimer = C_Timer.NewTimer(1.0, function()
        if self._interrupted then
            self._interrupted = nil
            self._interruptTimer = nil
            self.cast:Hide()
            self:ApplyNameVisibility()
        end
    end)
end
function NameplateFrame:ShowCastLockout()
    if not mod.ShowCastLockoutAsCrowdControl() or not self.unit then return end
    local nowTime = GetTime()
    local lockout = {
        icon = mod.CAST_LOCKOUT_ICON,
        start = nowTime,
        duration = mod.DEFAULT_CAST_LOCKOUT_DURATION,
        expires = nowTime + mod.DEFAULT_CAST_LOCKOUT_DURATION,
    }
    self._castLockout = lockout
    if mod.NPC_UpdateLockout then mod.NPC_UpdateLockout(self) end
    C_Timer.After(mod.DEFAULT_CAST_LOCKOUT_DURATION, function()
        if self._castLockout ~= lockout or GetTime() < lockout.expires then return end
        self._castLockout = nil
        if mod.NPC_UpdateLockout then mod.NPC_UpdateLockout(self) end
    end)
end
function NameplateFrame:UNIT_HEALTH()
    -- If the mob dies while the "Interrupted" flash is held up, Blizzard's death animation
    -- scales the still-shown cast bar and it looks warped, so tear the flash down on death.
    -- Gated on _interrupted first, so UnitIsDeadOrGhost only runs during the flash window.
    if self._interrupted and self.unit and UnitIsDeadOrGhost(self.unit) then
        self._interrupted = nil
        if self._interruptTimer then
            self._interruptTimer:Cancel()
            self._interruptTimer = nil
        end
        self.cast:Hide()
        self:ApplyNameVisibility()
    end
    self:MarkHealthDirty()
end
-- Max health changed: drop the cached max so the next paint re-derives it and
-- re-pushes the bar bounds (per-paint SetMinMaxValues is gone from the lean
-- path; bounds ride this event, exactly like Blizzard's CompactUnitFrame).
function NameplateFrame:UNIT_MAXHEALTH()
    self._maxHPValid = nil
    self:MarkHealthDirty()
end
function NameplateFrame:UNIT_ABSORB_AMOUNT_CHANGED()
    -- The dedicated absorb edge: force the next paint onto the full absorb
    -- path so the lean-gate flag re-derives from a fresh read.
    self._absorbEdge = true
    self:MarkHealthDirty()
end
-- Health paint coalescer (Blizzard's CompactUnitFrame shape: healthDirty is
-- drained once per frame at most). Health, max and absorb edges for one mob
-- land together in a server batch, and only the last paint of a frame ever
-- renders. Marks are a set write; the drain frame is hidden whenever the set
-- is empty (zero cost idle) and paints inside the same frame the events
-- arrived in, so nothing is displayed later than before. On ns (200-cap).
mod._npHvDirty = mod._npHvDirty or {}
mod._npHvFlush = mod._npHvFlush or CreateFrame("Frame")
mod._npHvFlush:Hide()
mod._npHvFlush:SetScript("OnUpdate", function(self)
    local dirty = mod._npHvDirty
    for backing in pairs(dirty) do
        dirty[backing] = nil
        -- A plate recycled between mark and drain has no unit; the paint's
        -- own guard returns. A re-acquired one paints its new occupant.
        if backing.unit then backing:UpdateHealthValues() end
    end
    if next(dirty) == nil then self:Hide() end
end)
function NameplateFrame:MarkHealthDirty()
    mod._npHvDirty[self] = true
    mod._npHvFlush:Show()
end
function NameplateFrame:UNIT_NAME_UPDATE()
    self:UpdateName()
    -- A unit first seen this session reads "normal" until its data arrives, the
    -- same moment its name resolves: re-read the elite/rare badge with the name.
    self:UpdateClassification()
    if mod._typeScaleOn and self:UpdateTypeScale() then self:ApplyScale() end
end
function NameplateFrame:UNIT_CLASSIFICATION_CHANGED()
    self:UpdateClassification()
    if mod._typeScaleOn and self:UpdateTypeScale() then self:ApplyScale() end
end
function NameplateFrame:UNIT_THREAT_LIST_UPDATE()
    self:UpdateHealthColor()
    -- An aggro change often moves the target: the target texts follow (throttled).
    if mod._npTgtTexts then self:RefreshTargetTexts() end
    -- Out of Combat Opacity: UNIT_FLAGS alone misses some pulls.
    if mod._oocAlpha < 1 then mod.NT_Apply(self) end
end
-- Out of Combat Opacity, registered only while it is on: the only signal when an
-- evading mob drops combat after the player has.
function NameplateFrame:UNIT_FLAGS() mod.NT_Apply(self) end
-- Faction badge: faction and PvP flag changes. The tap-state repaint rides the
-- shared UNIT_FACTION handler (factionFrame), not this one.
function NameplateFrame:UNIT_FACTION() self:UpdateFaction(true) end
function NameplateFrame:UNIT_SPELLCAST_START()
    self._castDirtyFull = true
    self:UpdateCast()
    -- A cast may turn the caster (its target field moves late or not at all, so this
    -- is a throttled repaint like any other, chained casts included).
    if mod._npTgtTexts then self:RefreshTargetTexts() end
end
function NameplateFrame:UNIT_SPELLCAST_CHANNEL_START()
    self._castDirtyFull = true
    self:UpdateCast()
    if mod._npTgtTexts then self:RefreshTargetTexts() end
end
function NameplateFrame:UNIT_SPELLCAST_DELAYED()
    -- Cast timing changed: the kick-tick geometry (min/max, positioner
    -- snapshot) must re-derive even on the non-full UpdateCast path
    self._kickGeoDirty = true
    self:UpdateCast()
end
function NameplateFrame:UNIT_SPELLCAST_CHANNEL_UPDATE()
    self._kickGeoDirty = true
    self:UpdateCast()
end
function NameplateFrame:UNIT_SPELLCAST_STOP()
    self:UpdateCast()
    -- Same hole CHANNEL_STOP and EMPOWER_STOP close directly: under restricted
    -- execution UnitCastingInfo can still hand UpdateCast a SECRET (non-nil) tuple
    -- for the cast that just stopped, so the ended branch never runs, isCasting stays
    -- true and ApplyScale keeps the cast multiplier on the plate after the cast (and
    -- after untargeting). A unit has one cast-time cast at a time, so a STOP landing
    -- while a non-channel cast is still flagged means that cast is over; a live
    -- channel (a STOP from an instant mid-channel) is left to CHANNEL_STOP.
    if self.isCasting and not self._castIsChannel then
        self.isCasting = false
        self:HideKickTick()
        self:ClearImportantCastGlow()
        self:ClearCastTargetGlow()
        self:ApplyScale()
        if not self._interrupted then self.cast:Hide() end
        self:ApplyNameVisibility()
        self.castTimer:SetText("")
        if self._castFallback then
            self._castFallback = nil
            _fallbackPlates[self] = nil
            Inner.fallbackCastCount = math.max(0, Inner.fallbackCastCount - 1)
            if Inner.fallbackCastCount == 0 then castFallbackFrame:Hide() end
        end
        NotifyCastEnded(self)
        if
            GetShowClassPower()
            and classPowerType
            and self._cpPips
            and self.unit
            and UnitIsUnit(self.unit, "target")
        then
            UpdateClassPowerOnPlate(self)
        end
    end
end
function NameplateFrame:UNIT_SPELLCAST_CHANNEL_STOP(_, _, _, kickerGuid)
    -- Directly hide instead of UpdateCast: in restricted execution, UnitCastingInfo can
    -- return secret values (not nil) for a stale channel, making UpdateCast think it's active.
    -- An interrupted channel carries the interrupter GUID on this event; a natural end leaves it nil.
    if self.isCasting then
        if self._castFallback then
            self._castFallback = nil
            _fallbackPlates[self] = nil
            Inner.fallbackCastCount = Inner.fallbackCastCount - 1
            if Inner.fallbackCastCount <= 0 then
                Inner.fallbackCastCount = 0
                castFallbackFrame:Hide()
            end
        end
        NotifyCastEnded(self)
    end
    self.isCasting = false
    self:HideKickTick()
    self:ClearImportantCastGlow()
    self:ClearCastTargetGlow()
    self:ApplyScale()
    if not self._interrupted then self.cast:Hide() end
    self:ApplyNameVisibility()
    self.castTimer:SetText("")
    if
        GetShowClassPower()
        and classPowerType
        and self._cpPips
        and self.unit
        and UnitIsUnit(self.unit, "target")
    then
        UpdateClassPowerOnPlate(self)
    end
    if type(kickerGuid) ~= "nil" and not self._interrupted then self:HandleInterrupted(kickerGuid) end
end
function NameplateFrame:UNIT_SPELLCAST_FAILED() self:UpdateCast() end
function NameplateFrame:HandleInterrupted(kickerGuid)
    local protected = self._kickProtected
    if type(kickerGuid) ~= "nil" and ((issecretvalue and issecretvalue(protected)) or not protected) then
        self:ShowCastLockout()
    end
    self:ShowInterrupted(kickerGuid)
end
function NameplateFrame:UNIT_SPELLCAST_INTERRUPTED(_, _, _, kickerGuid) self:HandleInterrupted(kickerGuid) end
-- Mid-cast interruptibility flips: re-read protection once, store it, refresh
-- color + kick tick + overlay. The cooldown watcher never re-reads cast info per
-- event, so these events are the only mid-cast source of protection changes.
function NameplateFrame:KickProtectionChanged()
    if not self.unit then return end
    local kickLocked
    local sName, _, _, _, _, _, _, kp = UnitCastingInfo(self.unit)
    if type(sName) ~= "nil" then
        kickLocked = kp
    else
        local chName
        chName, _, _, _, _, _, kp = UnitChannelInfo(self.unit)
        if type(chName) == "nil" then return end
        kickLocked = kp
    end
    if type(kickLocked) == "nil" then kickLocked = false end
    self._kickProtected = kickLocked
    self:ApplyCastColor(kickLocked)
    self:RefreshKickTick()
    if p and p.castingEnemyColors then mod.NP_NoteCastKind(self, kickLocked) end
end
function NameplateFrame:UNIT_SPELLCAST_INTERRUPTIBLE()
    self:KickProtectionChanged()
    self:UpdateCast()
end
function NameplateFrame:UNIT_SPELLCAST_NOT_INTERRUPTIBLE()
    self:KickProtectionChanged()
    self:UpdateCast()
end
function NameplateFrame:UNIT_SPELLCAST_EMPOWER_START()
    self._castDirtyFull = true
    self:UpdateCast()
end
function NameplateFrame:UNIT_SPELLCAST_EMPOWER_UPDATE()
    self._kickGeoDirty = true
    self:UpdateCast()
end
function NameplateFrame:UNIT_SPELLCAST_EMPOWER_STOP(_, _, _, _, kickerGuid)
    -- Stop directly. Re-checking cast info here can return a stale secret
    -- value in PvP and look like the cast is still going. An interrupted empower
    -- carries the interrupter GUID as the 5th arg (after unit, castGUID, spellID, complete).
    local wasCasting = self.isCasting
    self.isCasting = false
    self:HideKickTick()
    self:ClearImportantCastGlow()
    self:ClearCastTargetGlow()
    self:ApplyScale()
    if not self._interrupted then self.cast:Hide() end
    self:ApplyNameVisibility()
    self.castTimer:SetText("")
    if wasCasting then
        if self._castFallback then
            self._castFallback = nil
            _fallbackPlates[self] = nil
            Inner.fallbackCastCount = math.max(0, Inner.fallbackCastCount - 1)
            if Inner.fallbackCastCount == 0 then castFallbackFrame:Hide() end
        end
        NotifyCastEnded(self)
    end
    if
        GetShowClassPower()
        and classPowerType
        and self._cpPips
        and self.unit
        and UnitIsUnit(self.unit, "target")
    then
        UpdateClassPowerOnPlate(self)
    end
    if type(kickerGuid) ~= "nil" and not self._interrupted then self:HandleInterrupted(kickerGuid) end
end

Inner.broken = false
