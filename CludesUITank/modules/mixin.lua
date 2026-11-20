local addonName, mod = ...
if mod.standalone then
    return
end
-- Core.lua is loaded before this file (see TOC), so ns.K is available.
local K = mod.K

local CoTankAuras_Mixin = {}

-- ── Settings getters ──────────────────────────────────────────────────────
function CoTankAuras_Mixin:MaxShownPrivateAuras()
    return self.maxPrivateAuras or mod.SettingNumber("maxPrivateAuras", K.PRIVATE_AURAS_DEFAULT_COUNT)
end
function CoTankAuras_Mixin:MaxShownDebuffs()
    return self.maxDebuffs or mod.SettingNumber("maxDebuffs", K.DEBUFF_DEFAULT_COUNT)
end
function CoTankAuras_Mixin:MaxShownDefensives()
    return self.maxDefensives or mod.SettingNumber("maxDefensives", K.BIG_DEFENSIVES_DEFAULT_COUNT)
end
function CoTankAuras_Mixin:ShowPrivateAuras()
    return self:MaxShownPrivateAuras() > 0
end
function CoTankAuras_Mixin:ShowDebuffs()
    return mod.DebuffsEnabled() and self:MaxShownDebuffs() > 0
end
function CoTankAuras_Mixin:ShowDefensives()
    return self:MaxShownDefensives() > 0
end

-- ── Dead indicator ────────────────────────────────────────────────────────
function CoTankAuras_Mixin:CreateDeadOverlay()
    self.deadOverlay = self:CreateTexture(nil, "OVERLAY")
    self.deadOverlay:SetAllPoints()
    self.deadOverlay:SetColorTexture(0.06, 0.06, 0.10, 0.85)
    self.deadOverlay:Hide()
    self.deadText = self:CreateFontString(nil, "OVERLAY")
    self.deadText:SetFont(mod.FontPath(), 16, mod.FontFlags())
    self.deadText:SetPoint("CENTER", 0, 4)
    self.deadText:SetText("|cffcc3333DEAD|r")
    self.deadText:Hide()
end

function CoTankAuras_Mixin:UpdateDeadState()
    if mod.isTestMode then
        if self.deadOverlay then
            self.deadOverlay:Hide()
        end
        if self.deadText then
            self.deadText:Hide()
        end
        return
    end
    local unit = self:GetAttribute("unit")
    local isDead = unit and UnitExists(unit) and UnitIsDeadOrGhost(unit)
    if self.deadOverlay then
        self.deadOverlay:SetShown(isDead)
    end
    if self.deadText then
        self.deadText:SetShown(isDead)
    end
end

-- ── Clear helpers ─────────────────────────────────────────────────────────
-- Shows the stack highlight on a preview icon the way the engine does on a
-- live one: at or above the configured stack count.
local function SetPreviewHighlight(f, stacks)
    local at = mod.StackHighlightAt()
    local enabled = at > 0 and stacks >= at
    if enabled and not f.stackEdges then
        f.stackEdges = mod.CreateEdges(f, K.STACK_HIGHLIGHT_EDGE)
    end
    if not f.stackEdges then
        return
    end
    if enabled then
        mod.ColorEdges(f.stackEdges, mod.FontColor("stackHighlightColor"))
    end
    for _, t in ipairs(f.stackEdges) do
        t:SetShown(enabled)
    end
end

local function ClearIconFrame(frame)
    SetPreviewHighlight(frame, 0)
    frame:SetAlpha(0)
    frame.icon:SetTexture(nil)
    frame.count:SetText("")
    frame.cd:SetCooldown(0, 0)
    frame.auraInstanceID = nil
    frame.expirationTime = 0
end

function CoTankAuras_Mixin:ClearDebuffs()
    mod.Alert:PreviewBanner(false)
    if not self.debuffs then
        return
    end
    for i = 1, #self.debuffs do
        ClearIconFrame(self.debuffs[i])
    end
end

function CoTankAuras_Mixin:ClearBigDefensives()
    if not self.bigDefensives then
        return
    end
    for i = 1, #self.bigDefensives do
        ClearIconFrame(self.bigDefensives[i])
    end
end

-- ── Aura display ──────────────────────────────────────────────────────────
-- As with debuffs, the live display belongs to the AuraContainer. Outside
-- edit mode this only draws the test-mode preview.
function CoTankAuras_Mixin:UpdateBigDefensives()
    if mod.IsInEditMode() then
        return
    end
    if mod.isTestMode and self:ShowDefensives() then
        self:ShowMockDefensives()
    else
        self:ClearBigDefensives()
    end
end

function CoTankAuras_Mixin:ShowMockDefensives()
    if not self.bigDefensives then
        return
    end
    local mocks = K.MOCK_PREVIEW_DEFENSIVE_SPELLS
    local max = math.min(self:MaxShownDefensives(), #mocks)
    local nowTime = GetTime()
    for i, f in ipairs(self.bigDefensives) do
        if i <= max then
            f.auraInstanceID = nil
            f.icon:SetTexture(C_Spell.GetSpellTexture(mocks[i]) or K.MOCK_PREVIEW_DEBUFF_ICONS[i])
            f.count:SetText("")
            f.count:SetAlpha(0)
            local duration = 8 + (i * 4)
            local elapsed = (i * 2.3) % duration
            f.cd:SetCooldown(nowTime - elapsed, duration)
            f.expirationTime = nowTime + (duration - elapsed)
            f:SetAlpha(1)
        else
            f:SetAlpha(0)
            f.expirationTime = 0
        end
    end
end

-- Debuff types given to the preview icons, so the type borders can be seen.
local MOCK_DEBUFF_TYPES = { false, "Magic", "Poison", "Bleed", "Curse" }

local function SetPreviewTypeBorder(frame, i)
    local dispelType = MOCK_DEBUFF_TYPES[((i - 1) % #MOCK_DEBUFF_TYPES) + 1]
    if mod.DB().debuffTypeBorders and dispelType and AuraUtil and AuraUtil.GetAuraBorderColor then
        frame:SetBackdropBorderColor(AuraUtil.GetAuraBorderColor(dispelType):GetRGBA())
    else
        frame:SetBackdropBorderColor(0, 0, 0, 0.7)
    end
end

function CoTankAuras_Mixin:ShowMockDebuffs()
    local anyAtThreshold = false
    local highlightAt = mod.StackHighlightAt()
    local mocks = K.MOCK_PREVIEW_DEBUFF_ICONS
    local max = math.min(self:MaxShownDebuffs(), #mocks)
    local nowTime = GetTime()
    for i = 1, #self.debuffs do
        local frame = self.debuffs[i]
        if i <= max then
            frame.auraInstanceID = nil
            frame.icon:SetTexture(mocks[i])
            -- Stable mock stacks (varies per slot for visual variety)
            local stacks = (i == 2 or i == 4) and 3 or (i == 3) and 5 or 1
            if stacks > 1 and not frame.stackHidden then
                frame.count:SetText(stacks)
                frame.count:SetAlpha(1)
            else
                frame.count:SetText("")
                frame.count:SetAlpha(0)
            end
            -- Mock cooldown sweep (each icon at a different point in its timer)
            local duration = 8 + (i * 2)
            local elapsed = (i * 1.7) % duration
            frame.cd:SetCooldown(nowTime - elapsed, duration)
            frame.expirationTime = nowTime + (duration - elapsed)
            SetPreviewHighlight(frame, stacks)
            SetPreviewTypeBorder(frame, i)
            if highlightAt > 0 and stacks >= highlightAt then
                anyAtThreshold = true
            end
            frame:SetAlpha(1)
        else
            SetPreviewHighlight(frame, 0)
            frame:SetAlpha(0)
            frame.expirationTime = 0
        end
    end
    mod.Alert:PreviewBanner(anyAtThreshold and mod.DB().stackBanner and true or false)
end

-- Live debuffs are drawn by the AuraContainer (see modules/auras.lua); the
-- addon never enumerates the co-tank's auras itself any more. This is only
-- the test-mode preview path plus the alert check.
function CoTankAuras_Mixin:UpdateDebuffs()
    if mod.IsInEditMode() then
        return
    end
    if mod.isTestMode then
        if self:ShowDebuffs() then
            self:ShowMockDebuffs()
        else
            self:ClearDebuffs()
        end
        return
    end
    -- No clearing here: this runs on every throttled update, and the preview
    -- frames are already cleared and hidden by RefreshDebuffLayout when test
    -- mode ends.
    local unit = self:GetAttribute("unit")
    if not unit or not UnitExists(unit) then
        return
    end
    mod.Alert:Check(unit)
end

-- ── Health / Power bars ───────────────────────────────────────────────────
function CoTankAuras_Mixin:UpdateHealthBarColor()
    if mod.isTestMode then
        -- Paladin pink as mock class colour
        self.health:SetStatusBarColor(
            0.96 * K.HEALTH_BAR_INTENSITY,
            0.55 * K.HEALTH_BAR_INTENSITY,
            0.73 * K.HEALTH_BAR_INTENSITY
        )
        return
    end
    local unit = self:GetAttribute("unit")
    local color
    if unit then
        local _, class = UnitClass(unit)
        if class then
            color = RAID_CLASS_COLORS[class]
        end
    end
    if color then
        self.health:SetStatusBarColor(
            color.r * K.HEALTH_BAR_INTENSITY,
            color.g * K.HEALTH_BAR_INTENSITY,
            color.b * K.HEALTH_BAR_INTENSITY
        )
    else
        self.health:SetStatusBarColor(0.5, 0.5, 0.5)
    end
end

function CoTankAuras_Mixin:UpdateHealthText()
    if mod.isTestMode then
        self:SetNameText(K.MOCK_NAMES[4]) -- "Iblameheals"
        self.hpText:SetText("65,432 | 65%")
        return
    end
    local unit = self:GetAttribute("unit")
    if not unit or not UnitExists(unit) then
        self.hpText:SetText("")
        return
    end
    self:SetNameText(UnitName(unit))

    if
        self.hpText.HasSecretValues
        and type(self.hpText.HasSecretValues) == "function"
        and self.hpText:HasSecretValues()
    then
        self.hpText:SetToDefaults()
    end

    local unitHealth
    if AbbreviateLargeNumbers and type(AbbreviateLargeNumbers) == "function" then
        unitHealth = AbbreviateLargeNumbers(UnitHealth(unit))
    else
        unitHealth = UnitHealth(unit)
    end
    local success, pct
    if CurveConstants and CurveConstants.ScaleTo100 then
        success, pct = pcall(UnitHealthPercent, unit, false, CurveConstants.ScaleTo100)
    else
        success, pct = pcall(UnitHealthPercent, unit, false, true)
    end
    if success and pct ~= nil and unitHealth ~= nil then
        self.hpText:SetFormattedText("%s | %.0f%%", unitHealth, pct)
    elseif unitHealth then
        self.hpText:SetText(unitHealth)
    else
        self.hpText:SetText("??")
    end
end

function CoTankAuras_Mixin:UpdateHealthBar()
    if mod.isTestMode then
        self.health:SetMinMaxValues(0, 100)
        self.health:SetValue(65)
        self:UpdateHealthText()
        return
    end
    local unit = self:GetAttribute("unit")
    if not unit or not UnitExists(unit) then
        return
    end
    self.health:SetMinMaxValues(0, UnitHealthMax(unit))
    self.health:SetValue(UnitHealth(unit))
    self:UpdateHealthText()
end

function CoTankAuras_Mixin:UpdatePower()
    if mod.isTestMode then
        self.power:SetMinMaxValues(0, 100)
        self.power:SetValue(45)
        self.power:SetStatusBarColor(0.0, 0.52, 1.0)
        return
    end
    local unit = self:GetAttribute("unit")
    if not unit or not UnitExists(unit) then
        return
    end
    local _, powerToken = UnitPowerType(unit)
    self.power:SetMinMaxValues(0, UnitPowerMax(unit))
    self.power:SetValue(UnitPower(unit))
    local color = PowerBarColor[powerToken] or PowerBarColor["MANA"]
    self.power:SetStatusBarColor(color.r, color.g, color.b)
end

-- ── Layout helpers ────────────────────────────────────────────────────────
function CoTankAuras_Mixin:UpdateIconList(frameList, maxCount)
    if InCombatLockdown() or not frameList then
        return
    end
    for i, f in ipairs(frameList) do
        f:SetShown(i <= maxCount)
    end
end

function CoTankAuras_Mixin:UpdateAndRefreshAuraLayout(newVal)
    local changed = self:MaxShownPrivateAuras() ~= newVal
    self.maxPrivateAuras = newVal
    self:RefreshAuraLayout()
    return changed
end
function CoTankAuras_Mixin:UpdateAndRefreshDebuffLayout(newVal)
    local changed = self:MaxShownDebuffs() ~= newVal
    self.maxDebuffs = newVal
    self:RefreshDebuffLayout()
    return changed
end
function CoTankAuras_Mixin:UpdateAndRefreshDefensiveLayout(newVal)
    local changed = self:MaxShownDefensives() ~= newVal
    self.maxDefensives = newVal
    self:RefreshDefensiveLayout()
    return changed
end

function CoTankAuras_Mixin:RefreshAuraLayout()
    self:UpdateIconList(self.anchorFrames, self:MaxShownPrivateAuras())
end

-- The icon frames below are the test-mode/edit-mode preview only. Live auras
-- are drawn by the AuraContainers, so outside those modes the previews stay
-- hidden and the container count is what matters.
function CoTankAuras_Mixin:RefreshDebuffLayout()
    local preview = (mod.isTestMode or mod.IsInEditMode()) and self:ShowDebuffs()
    if not preview then
        self:ClearDebuffs()
    end
    self:UpdateIconList(self.debuffs, preview and self:MaxShownDebuffs() or 0)
    mod.RefreshDebuffContainer(self)
end

function CoTankAuras_Mixin:RefreshDefensiveLayout()
    local preview = (mod.isTestMode or mod.IsInEditMode()) and self:ShowDefensives()
    if not preview then
        self:ClearBigDefensives()
    end
    self:UpdateIconList(self.bigDefensives, preview and self:MaxShownDefensives() or 0)
    mod.RefreshDefensiveContainer(self)
end

-- ── Icon settings helpers ─────────────────────────────────────────────────
function mod.ApplyIconSettings(f)
    local saved = mod.DB()
    local face = mod.FontPath()
    local flags = mod.FontFlags()
    -- Stack count size (0 = hidden)
    local size = mod.SettingNumber("stackCountSize", K.STACK_COUNT_DEFAULT_SIZE)
    f.stackHidden = (size <= 0)
    f.count:SetFont(face, math.max(size, 1), flags)
    f.count:SetTextColor(mod.FontColor("stackCountColor"))
    -- Stack count position, plus the free nudge offsets
    local posId = saved.stackCountPos or "BR_IN"
    local place
    for _, p in ipairs(K.STACK_COUNT_POSITIONS) do
        if p.id == posId then
            place = p
            break
        end
    end
    place = place or K.STACK_COUNT_POSITIONS[1]
    local nudgeX = mod.SettingNumber("stackCountNudgeX", 0)
    local nudgeY = mod.SettingNumber("stackCountNudgeY", 0)
    f.count:ClearAllPoints()
    f.count:SetPoint(place.point, f, place.rel or place.point, place.px + nudgeX, place.py + nudgeY)
    -- Cooldown scale and position
    local scaleInt = mod.SettingNumber("cdFontScale", K.CD_FONT_SCALE_DEFAULT)
    local scale = scaleInt / 10.0
    local cdAbove = saved.cdAbove or false
    if f.cd.SetFontScale then
        f.cd:SetFontScale(math.max(scale, 0.05))
    end
    f.cd:SetHideCountdownNumbers(cdAbove or scale <= 0)
    if f.timerText then
        f.timerText:SetShown(cdAbove)
        local timerSize = mod.SettingNumber("timerTextSize", K.TIMER_TEXT_DEFAULT_SIZE)
        f.timerText:SetFont(face, math.max(timerSize, 1), flags)
        f.timerText:SetTextColor(mod.FontColor("timerTextColor"))
    end
end

function mod.RefreshAllFonts()
    if not CoTankAuras then
        return
    end
    local face = mod.FontPath()
    local flags = mod.FontFlags()
    if CoTankAuras.nameText then
        CoTankAuras.nameText:SetFont(face, mod.SettingNumber("nameFontSize", K.DEFAULT_NAME_FONT_SIZE), flags)
        CoTankAuras.nameText:SetTextColor(mod.FontColor("nameTextColor"))
    end
    if CoTankAuras.hpText then
        CoTankAuras.hpText:SetFont(face, mod.SettingNumber("hpFontSize", K.DEFAULT_HP_FONT_SIZE), flags)
        CoTankAuras.hpText:SetTextColor(mod.FontColor("hpTextColor"))
    end
    if CoTankAuras.deadText then
        CoTankAuras.deadText:SetFont(face, 16, flags)
    end
    if mod.Alert and mod.Alert.RefreshFont then
        mod.Alert:RefreshFont()
    end
    mod.RefreshAllIconSettings()
end

function mod.RefreshAllIconSettings()
    if not CoTankAuras then
        return
    end
    if CoTankAuras.debuffs then
        for _, f in ipairs(CoTankAuras.debuffs) do
            mod.ApplyIconSettings(f)
        end
    end
    if CoTankAuras.bigDefensives then
        for _, f in ipairs(CoTankAuras.bigDefensives) do
            mod.ApplyIconSettings(f)
        end
    end
    -- Live AuraButtons carry their own copies of these settings; they can only
    -- be restyled while auras are readable, which RestyleAuraButtons checks.
    mod.RestyleAuraButtons()
end

function mod.RefreshDebuffSpacing()
    if not CoTankAuras then
        return
    end
    mod.RefreshAuraContainerLayout(CoTankAuras)
    if not CoTankAuras.debuffs then
        return
    end
    local spacing = mod.SettingNumber("debuffSpacing", K.DEBUFF_SPACING)
    for i, f in ipairs(CoTankAuras.debuffs) do
        f:ClearAllPoints()
        if i == 1 then
            f:SetPoint("TOPRIGHT", CoTankAuras, "BOTTOMRIGHT", 0, 0)
        else
            f:SetPoint("RIGHT", CoTankAuras.debuffs[i - 1], "LEFT", -spacing, 0)
        end
    end
end

-- For each grow direction: where the first icon attaches to the frame, and
-- how each following icon continues from the one before it. The offsets are
-- multipliers applied to the configured spacing.
local PRIVATE_AURA_GROW = {
    LEFT = { anchor = { "BOTTOMRIGHT", "TOPRIGHT" }, step = { "RIGHT", "LEFT", -1, 0 } },
    RIGHT = { anchor = { "BOTTOMLEFT", "TOPLEFT" }, step = { "LEFT", "RIGHT", 1, 0 } },
    UP = { anchor = { "BOTTOMLEFT", "TOPLEFT" }, step = { "BOTTOM", "TOP", 0, 1 } },
    DOWN = { anchor = { "TOPRIGHT", "BOTTOMRIGHT" }, step = { "TOP", "BOTTOM", 0, -1 } },
}

local function ApplyPrivateAuraGrow(frames, spacing)
    local grow = PRIVATE_AURA_GROW[mod.DB().privateAuraGrowDir or "LEFT"] or PRIVATE_AURA_GROW.LEFT
    for i, boxHolder in ipairs(frames) do
        boxHolder:ClearAllPoints()
        if i == 1 then
            boxHolder:SetPoint(grow.anchor[1], CoTankAuras, grow.anchor[2], 0, 0)
        else
            local anchorPoint, relPoint, dx, dy = unpack(grow.step)
            boxHolder:SetPoint(anchorPoint, frames[i - 1], relPoint, dx * spacing, dy * spacing)
        end
    end
end

function mod.RefreshPrivateAuraSpacing()
    if not CoTankAuras or not CoTankAuras.anchorFrames then
        return
    end
    local spacing = mod.SettingNumber("privateAuraSpacing", K.DEBUFF_SPACING)
    ApplyPrivateAuraGrow(CoTankAuras.anchorFrames, spacing)
end

function mod.RefreshPrivateAuraGrow()
    if not CoTankAuras or InCombatLockdown() then
        return
    end
    CoTankAuras:CleanupPrivateAnchors()
    mod.RefreshPrivateAuraSpacing()
    CoTankAuras:AttachPrivateAnchors()
end

function mod.RefreshPrivateAuraSize()
    if not CoTankAuras or not CoTankAuras.anchorFrames then
        return
    end
    if InCombatLockdown() then
        return
    end
    local size = mod.SettingNumber("privateAuraSize", K.PRIVATE_AURA_SIZE_DEFAULT)
    for _, boxHolder in ipairs(CoTankAuras.anchorFrames) do
        boxHolder:SetSize(size, size)
    end
    CoTankAuras:CleanupPrivateAnchors()
    CoTankAuras:AttachPrivateAnchors()
end

-- Above-icon timer updater for the preview icons only. Live icons are
-- AuraButtons whose duration text the engine formats itself, so this no longer
-- runs during normal play - only while the test or edit preview is up.
local timerUpdater = CreateFrame("Frame")
timerUpdater:SetScript("OnUpdate", function()
    if not mod.DB().cdAbove then
        return
    end
    if not CoTankAuras then
        return
    end
    if not (mod.isTestMode or mod.IsInEditMode()) then
        return
    end
    local nowTime = GetTime()
    local function updateList(entries)
        if not entries then
            return
        end
        for _, f in ipairs(entries) do
            if f.timerText and f:GetAlpha() > 0 and (f.expirationTime or 0) > 0 then
                local rem = f.expirationTime - nowTime
                if rem > 0 then
                    if rem >= 60 then
                        f.timerText:SetFormattedText("%d:%02d", math.floor(rem / 60), rem % 60)
                    elseif rem >= 10 then
                        f.timerText:SetFormattedText("%d", math.floor(rem))
                    else
                        f.timerText:SetFormattedText("%.1f", rem)
                    end
                    f.timerText:Show()
                else
                    f.timerText:Hide()
                end
            elseif f.timerText then
                f.timerText:Hide()
            end
        end
    end
    updateList(CoTankAuras.debuffs)
    updateList(CoTankAuras.bigDefensives)
end)

-- ── Icon frame factory ────────────────────────────────────────────────────
local function CreateIconFrame(iconList, iconSize, anchorPoint, hostFrame, relativePoint, ofsx, ofsy)
    local frame = CreateFrame("Button", nil, hostFrame, "BackdropTemplate")
    frame:SetFrameStrata("MEDIUM")
    frame:SetMouseClickEnabled(true)
    frame:SetSize(iconSize, iconSize)
    frame:SetBackdrop({ edgeFile = K.BACKDROP_TEXTURE, edgeSize = 1 })
    frame:SetBackdropBorderColor(0, 0, 0, 0.7)
    frame.border = frame

    -- Icon with 30% TexCoord zoom (removes default blizzard icon padding)
    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    frame.icon:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    frame.cd = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    frame.cd:SetAllPoints(frame.icon)
    frame.cd:SetReverse(true)

    -- Stack count (position/size driven by ns.ApplyIconSettings)
    frame.count = frame:CreateFontString(nil, "OVERLAY")
    frame.count:SetFont(mod.FontPath(), 9, mod.FontFlags())
    frame.count:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 2, 1)
    frame.count:SetTextColor(1, 1, 1)

    -- Above-icon timer text (shown when cdAbove=true)
    frame.timerText = frame:CreateFontString(nil, "OVERLAY")
    frame.timerText:SetFont(mod.FontPath(), 9, mod.FontFlags())
    frame.timerText:SetPoint("BOTTOM", frame, "TOP", 0, 2)
    frame.timerText:SetTextColor(1, 0.85, 0.4)
    frame.timerText:Hide()

    frame:EnableMouse(true)
    frame:SetScript("OnLeave", function()
        GameTooltip:Hide()
        if GameTooltip.ClearLines then
            GameTooltip:ClearLines()
        end
    end)
    frame:SetScript("OnEnter", function(button)
        -- TooltipInfo aura lookups by instance ID error while auras are
        -- secret. These frames are the test-mode preview only (live icons are
        -- AuraButtons, which carry their own engine tooltip), so bail out
        -- rather than risk the call.
        if mod.AurasAreSecret() then
            return
        end
        local unit = CoTankAuras and CoTankAuras:GetAttribute("unit")
        if unit and button.auraInstanceID then
            GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
            pcall(GameTooltip.SetUnitAura, GameTooltip, unit, button.auraInstanceID)
            GameTooltip:Show()
        end
    end)

    local position = #iconList + 1
    if position == 1 then
        frame:SetPoint(anchorPoint, hostFrame, relativePoint, ofsx, ofsy)
    else
        frame:SetPoint("RIGHT", iconList[position - 1], "LEFT", -K.DEBUFF_SPACING, 0)
    end
    frame:SetAlpha(0)
    iconList[position] = frame
    mod.ApplyIconSettings(frame)
end

function CoTankAuras_Mixin:CreateDebuffContainer()
    self.debuffs = {}
    for i = 1, K.DEBUFF_MAX_COUNT do
        CreateIconFrame(self.debuffs, K.DEBUFF_ICON_SIZE, "TOPRIGHT", self, "BOTTOMRIGHT", 0, 0)
    end
    self:RefreshDebuffLayout()
end

function CoTankAuras_Mixin:CreateDefensiveContainer()
    if InCombatLockdown() or self.bigDefensives then
        return
    end
    self.bigDefensives = {}
    local iconSize = K.DEFAULT_HEIGHT - K.POWER_BAR_HEIGHT - 16
    for i = 1, K.BIG_DEFENSIVES_MAX_COUNT do
        CreateIconFrame(self.bigDefensives, iconSize, "RIGHT", self.health, "RIGHT", -K.DEBUFF_SPACING, -2)
    end
    self:RefreshDefensiveLayout()
end

function CoTankAuras_Mixin:CreatePrivateAnchorContainers()
    if InCombatLockdown() or self.anchorFrames then
        return
    end
    self.anchorFrames = {}
    local scaleFactor = mod.CalculateScaleFactor()
    local size = mod.SettingNumber("privateAuraSize", K.PRIVATE_AURA_SIZE_DEFAULT)
    for i = 1, K.PRIVATE_AURAS_MAX_COUNT do
        local boxHolder = CreateFrame("Frame", nil, self, "BackdropTemplate")
        boxHolder:SetSize(size, size)
        boxHolder:SetBackdrop({ edgeFile = K.BACKDROP_TEXTURE, edgeSize = 1 })
        boxHolder:SetBackdropBorderColor(0, 0, 0, 0)
        local anchor = CreateFrame("Frame", nil, boxHolder)
        anchor:SetAllPoints(boxHolder)
        self.anchorFrames[i] = boxHolder
        self.anchorFrames[i]:SetAlpha(1)
        self.anchorFrames[i]:SetScale(scaleFactor)
    end
    local spacing = mod.SettingNumber("privateAuraSpacing", K.DEBUFF_SPACING)
    ApplyPrivateAuraGrow(self.anchorFrames, spacing)
    self:RefreshAuraLayout()
end

-- ── Private aura anchors ──────────────────────────────────────────────────
function CoTankAuras_Mixin:ShowMockPrivateAuras()
    if not self.anchorFrames then
        return
    end
    local mocks = K.MOCK_PREVIEW_DEBUFF_ICONS
    local max = math.min(self:MaxShownPrivateAuras(), #mocks)
    for i, boxHolder in ipairs(self.anchorFrames) do
        if i <= max then
            if not boxHolder.mockIcon then
                local texture = boxHolder:CreateTexture(nil, "OVERLAY")
                texture:SetPoint("TOPLEFT", boxHolder, "TOPLEFT", 1, -1)
                texture:SetPoint("BOTTOMRIGHT", boxHolder, "BOTTOMRIGHT", -1, 1)
                texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                boxHolder.mockIcon = texture
            end
            boxHolder.mockIcon:SetTexture(mocks[i])
            boxHolder.mockIcon:SetAlpha(0.5)
            boxHolder:SetBackdropBorderColor(0, 0, 0, 0.7)
            -- Mock stack count
            if not boxHolder.mockStack then
                local fontStr = boxHolder:CreateFontString(nil, "OVERLAY")
                fontStr:SetFont(mod.FontPath(), 10, mod.FontFlags())
                fontStr:SetPoint("BOTTOMRIGHT", boxHolder, "BOTTOMRIGHT", 1, 1)
                boxHolder.mockStack = fontStr
            end
            local stacks = ({ 3, 1, 5, 2 })[((i - 1) % 4) + 1]
            boxHolder.mockStack:SetText(stacks > 1 and tostring(stacks) or "")
            boxHolder.mockStack:Show()
        elseif boxHolder.mockIcon then
            boxHolder.mockIcon:SetAlpha(0)
            boxHolder:SetBackdropBorderColor(0, 0, 0, 0)
            if boxHolder.mockStack then
                boxHolder.mockStack:Hide()
            end
        end
    end
end

function CoTankAuras_Mixin:HideMockPrivateAuras()
    if not self.anchorFrames then
        return
    end
    for _, boxHolder in ipairs(self.anchorFrames) do
        if boxHolder.mockIcon then
            boxHolder.mockIcon:SetAlpha(0)
        end
        boxHolder:SetBackdropBorderColor(0, 0, 0, 0)
    end
end

function CoTankAuras_Mixin:AttachPrivateAnchors()
    self:CleanupPrivateAnchors()
    self:RefreshAuraLayout()
    if not self:IsVisible() or not self:ShowPrivateAuras() then
        return
    end
    -- In test mode show placeholder icons instead of attaching real engine anchors
    if mod.isTestMode then
        self:ShowMockPrivateAuras()
        return
    end
    local unit = self:GetAttribute("unit")
    if not unit then
        return
    end
    self.privateAnchorIDs = self.privateAnchorIDs or {}
    self.privateStackAnchorIDs = self.privateStackAnchorIDs or {}
    self.privateStackFrames = self.privateStackFrames or {}
    local size = mod.SettingNumber("privateAuraSize", K.PRIVATE_AURA_SIZE_DEFAULT)
    local borderVal = mod.SettingNumber("privateAuraBorderScale", K.PRIVATE_AURA_BORDER_SCALE_DEFAULT)
    local borderScale = borderVal <= 0 and -100 or borderVal
    local stackScale = mod.SettingNumber("privateAuraStackScale", K.PRIVATE_AURA_STACK_SCALE_DEFAULT)
    for i = 1, #self.anchorFrames do
        local ident = C_UnitAuras.AddPrivateAuraAnchor({
            unitToken = unit,
            auraIndex = i,
            parent = self.anchorFrames[i],
            showCountdownFrame = true,
            showCountdownNumbers = stackScale <= 1,
            iconInfo = {
                iconWidth = size - 4,
                iconHeight = size - 4,
                borderScale = borderScale,
                iconAnchor = {
                    point = "CENTER",
                    relativeTo = self.anchorFrames[i],
                    relativePoint = "CENTER",
                    offsetX = 0,
                    offsetY = 0,
                },
            },
        })
        if ident then
            table.insert(self.privateAnchorIDs, ident)
        end
        if stackScale > 1 then
            if not self.privateStackFrames[i] then
                local scrollFrame = CreateFrame("Frame", nil, self.anchorFrames[i])
                scrollFrame:SetSize(0.001, 0.001)
                scrollFrame:SetPoint("BOTTOMRIGHT", self.anchorFrames[i], "BOTTOMRIGHT", 0, 0)
                self.privateStackFrames[i] = scrollFrame
            end
            self.privateStackFrames[i]:SetScale(stackScale)
            local spellRef = C_UnitAuras.AddPrivateAuraAnchor({
                unitToken = unit,
                auraIndex = i,
                parent = self.privateStackFrames[i],
                showCountdownFrame = false,
                showCountdownNumbers = false,
                durationAnchor = {
                    point = "CENTER",
                    relativeTo = self.anchorFrames[i],
                    relativePoint = "CENTER",
                    offsetX = 0,
                    offsetY = 0,
                },
                iconInfo = {
                    iconWidth = 0.001,
                    iconHeight = 0.001,
                    borderScale = -100,
                    iconAnchor = {
                        point = "BOTTOMRIGHT",
                        relativeTo = self.anchorFrames[i],
                        relativePoint = "BOTTOMRIGHT",
                        offsetX = 2,
                        offsetY = -2,
                    },
                },
            })
            if spellRef then
                table.insert(self.privateStackAnchorIDs, spellRef)
            end
        end
    end
end

function CoTankAuras_Mixin:CleanupPrivateAnchors()
    if self.privateAnchorIDs then
        for _, ident in ipairs(self.privateAnchorIDs) do
            C_UnitAuras.RemovePrivateAuraAnchor(ident)
        end
        self.privateAnchorIDs = {}
    end
    if self.privateStackAnchorIDs then
        for _, ident in ipairs(self.privateStackAnchorIDs) do
            C_UnitAuras.RemovePrivateAuraAnchor(ident)
        end
        self.privateStackAnchorIDs = {}
    end
    self:HideMockPrivateAuras()
end

-- ── Event handlers ────────────────────────────────────────────────────────
function CoTankAuras_Mixin:OnAttributeChanged(name, value)
    if name ~= "unit" then
        return
    end
    self:UnregisterAllEvents()
    local watchUnit = mod.isTestMode and "player" or value
    if watchUnit then
        self:RegisterUnitEvent("UNIT_HEALTH", watchUnit)
        self:RegisterUnitEvent("UNIT_MAXHEALTH", watchUnit)
        self:RegisterUnitEvent("UNIT_POWER_UPDATE", watchUnit)
        self:RegisterUnitEvent("UNIT_MAXPOWER", watchUnit)
        self:RegisterUnitEvent("UNIT_DISPLAYPOWER", watchUnit)
        self:RegisterUnitEvent("UNIT_AURA", watchUnit)
        -- In test mode also watch the real co-tank's auras so debuffs update live
        if mod.isTestMode and value and value ~= watchUnit then
            self:RegisterUnitEvent("UNIT_AURA", value)
        end
        self:AttachPrivateAnchors()
        mod.RefreshAuraContainers(self)
        mod.Alert:RegisterAuraSounds(value)
        self:UpdateVisuals()
    else
        if not mod.isTestMode then
            self:SetNameText("NO CO-TANK")
        end
        self.health:SetValue(0)
        self.power:SetValue(0)
        self:ClearDebuffs()
        self:CleanupPrivateAnchors()
        mod.RefreshAuraContainers(self)
        mod.Alert:RegisterAuraSounds(nil)
    end
end

function CoTankAuras_Mixin:OnSizeChangedHandler()
    self:FitNameToWidth()
end

function CoTankAuras_Mixin:SetNameText(nameText)
    self.nameText.rawText = nameText
    self.nameText:SetText(nameText)
    self:FitNameToWidth()
end

function CoTankAuras_Mixin:FitNameToWidth()
    local maxWidth = self:GetWidth() - 8
    local raw = self.nameText.rawText
    self.nameText:SetText(raw)
    if self.nameText:GetStringWidth() > maxWidth then
        for i = string.len(raw), 1, -1 do
            -- Only cut between characters. Accented letters in names are
            -- several bytes in UTF-8, and a cut through one draws garbage.
            local nextByte = raw:byte(i + 1)
            if not nextByte or nextByte < 0x80 or nextByte >= 0xC0 then
                self.nameText:SetText(string.sub(raw, 1, i) .. "...")
                if self.nameText:GetStringWidth() <= maxWidth then
                    break
                end
            end
        end
    end
end

function CoTankAuras_Mixin:UpdateVisuals(_event, _unusedUnit, _info)
    -- No early-out on the UNIT_AURA payload: since 12.1 the whole updateInfo
    -- table is secret while auras are restricted, and info.isFullUpdate is a
    -- secret boolean - testing it for truth is an immediate Lua error. The
    -- UPDATE_THROTTLE below already does the rate limiting this was for.
    local nowTime = GetTime()
    if (self.nextUpdate or 0) > nowTime then
        -- Throttled. Queue one catch-up pass for the end of the window, or
        -- the last change in a burst is dropped and the bar sits on a stale
        -- value until the co-tank next takes damage or healing.
        if not self.updateQueued then
            self.updateQueued = true
            C_Timer.After(self.nextUpdate - nowTime, function()
                self.updateQueued = false
                self:UpdateVisuals()
            end)
        end
        return
    end
    self.nextUpdate = nowTime + K.UPDATE_THROTTLE
    local unit = self:GetAttribute("unit")
    if not unit or not UnitExists(unit) then
        return
    end
    self:UpdateHealthBar()
    self:UpdatePower()
    self:UpdateDebuffs()
    self:UpdateBigDefensives()
    self:UpdateDeadState()
    if not mod.isTestMode then
        local name = UnitName(unit)
        if name then
            self:SetNameText(name)
        end
    end
end

-- Export
mod.Mixin = CoTankAuras_Mixin
