local addonName, ns = ...
if ns.standalone then
    return
end
-- Core.lua is loaded before this file (see TOC), so ns.K is available.
local K = ns.K

local CoTankAuras_Mixin = {}

-- ── Settings getters ──────────────────────────────────────────────────────
function CoTankAuras_Mixin:MaxShownPrivateAuras()
    return self.maxPrivateAuras or ns.SettingNumber("maxPrivateAuras", K.PRIVATE_AURAS_DEFAULT_COUNT)
end
function CoTankAuras_Mixin:MaxShownDebuffs()
    return self.maxDebuffs or ns.SettingNumber("maxDebuffs", K.DEBUFF_DEFAULT_COUNT)
end
function CoTankAuras_Mixin:MaxShownDefensives()
    return self.maxDefensives or ns.SettingNumber("maxDefensives", K.BIG_DEFENSIVES_DEFAULT_COUNT)
end
function CoTankAuras_Mixin:ShowPrivateAuras()
    return self:MaxShownPrivateAuras() > 0
end
function CoTankAuras_Mixin:ShowDebuffs()
    return ns.DebuffsEnabled() and self:MaxShownDebuffs() > 0
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
    self.deadText:SetFont(ns.FontPath(), 16, ns.FontFlags())
    self.deadText:SetPoint("CENTER", 0, 4)
    self.deadText:SetText("|cffcc3333DEAD|r")
    self.deadText:Hide()
end

function CoTankAuras_Mixin:UpdateDeadState()
    if ns.isTestMode then
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
    local at = ns.StackHighlightAt()
    local on = at > 0 and stacks >= at
    if on and not f.stackEdges then
        f.stackEdges = ns.CreateEdges(f, K.STACK_HIGHLIGHT_EDGE)
    end
    if not f.stackEdges then
        return
    end
    if on then
        ns.ColorEdges(f.stackEdges, ns.FontColor("stackHighlightColor"))
    end
    for _, t in ipairs(f.stackEdges) do
        t:SetShown(on)
    end
end

local function ClearIconFrame(f)
    SetPreviewHighlight(f, 0)
    f:SetAlpha(0)
    f.icon:SetTexture(nil)
    f.count:SetText("")
    f.cd:SetCooldown(0, 0)
    f.auraInstanceID = nil
    f.expirationTime = 0
end

function CoTankAuras_Mixin:ClearDebuffs()
    ns.Alert:PreviewBanner(false)
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
    if ns.IsInEditMode() then
        return
    end
    if ns.isTestMode and self:ShowDefensives() then
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
    local now = GetTime()
    for i, f in ipairs(self.bigDefensives) do
        if i <= max then
            f.auraInstanceID = nil
            f.icon:SetTexture(C_Spell.GetSpellTexture(mocks[i]) or K.MOCK_PREVIEW_DEBUFF_ICONS[i])
            f.count:SetText("")
            f.count:SetAlpha(0)
            local duration = 8 + (i * 4)
            local elapsed = (i * 2.3) % duration
            f.cd:SetCooldown(now - elapsed, duration)
            f.expirationTime = now + (duration - elapsed)
            f:SetAlpha(1)
        else
            f:SetAlpha(0)
            f.expirationTime = 0
        end
    end
end

-- Debuff types given to the preview icons, so the type borders can be seen.
local MOCK_DEBUFF_TYPES = { false, "Magic", "Poison", "Bleed", "Curse" }

local function SetPreviewTypeBorder(f, i)
    local dispelType = MOCK_DEBUFF_TYPES[((i - 1) % #MOCK_DEBUFF_TYPES) + 1]
    if ns.DB().debuffTypeBorders and dispelType and AuraUtil and AuraUtil.GetAuraBorderColor then
        f:SetBackdropBorderColor(AuraUtil.GetAuraBorderColor(dispelType):GetRGBA())
    else
        f:SetBackdropBorderColor(0, 0, 0, 0.7)
    end
end

function CoTankAuras_Mixin:ShowMockDebuffs()
    local anyAtThreshold = false
    local highlightAt = ns.StackHighlightAt()
    local mocks = K.MOCK_PREVIEW_DEBUFF_ICONS
    local max = math.min(self:MaxShownDebuffs(), #mocks)
    local now = GetTime()
    for i = 1, #self.debuffs do
        local f = self.debuffs[i]
        if i <= max then
            f.auraInstanceID = nil
            f.icon:SetTexture(mocks[i])
            -- Stable mock stacks (varies per slot for visual variety)
            local stacks = (i == 2 or i == 4) and 3 or (i == 3) and 5 or 1
            if stacks > 1 and not f.stackHidden then
                f.count:SetText(stacks)
                f.count:SetAlpha(1)
            else
                f.count:SetText("")
                f.count:SetAlpha(0)
            end
            -- Mock cooldown sweep (each icon at a different point in its timer)
            local duration = 8 + (i * 2)
            local elapsed = (i * 1.7) % duration
            f.cd:SetCooldown(now - elapsed, duration)
            f.expirationTime = now + (duration - elapsed)
            SetPreviewHighlight(f, stacks)
            SetPreviewTypeBorder(f, i)
            if highlightAt > 0 and stacks >= highlightAt then
                anyAtThreshold = true
            end
            f:SetAlpha(1)
        else
            SetPreviewHighlight(f, 0)
            f:SetAlpha(0)
            f.expirationTime = 0
        end
    end
    ns.Alert:PreviewBanner(anyAtThreshold and ns.DB().stackBanner and true or false)
end

-- Live debuffs are drawn by the AuraContainer (see modules/auras.lua); the
-- addon never enumerates the co-tank's auras itself any more. This is only
-- the test-mode preview path plus the alert check.
function CoTankAuras_Mixin:UpdateDebuffs()
    if ns.IsInEditMode() then
        return
    end
    if ns.isTestMode then
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
    ns.Alert:Check(unit)
end

-- ── Health / Power bars ───────────────────────────────────────────────────
function CoTankAuras_Mixin:UpdateHealthBarColor()
    if ns.isTestMode then
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
    if ns.isTestMode then
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
    local ok, pct
    if CurveConstants and CurveConstants.ScaleTo100 then
        ok, pct = pcall(UnitHealthPercent, unit, false, CurveConstants.ScaleTo100)
    else
        ok, pct = pcall(UnitHealthPercent, unit, false, true)
    end
    if ok and pct ~= nil and unitHealth ~= nil then
        self.hpText:SetFormattedText("%s | %.0f%%", unitHealth, pct)
    elseif unitHealth then
        self.hpText:SetText(unitHealth)
    else
        self.hpText:SetText("??")
    end
end

function CoTankAuras_Mixin:UpdateHealthBar()
    if ns.isTestMode then
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
    if ns.isTestMode then
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
    local preview = (ns.isTestMode or ns.IsInEditMode()) and self:ShowDebuffs()
    if not preview then
        self:ClearDebuffs()
    end
    self:UpdateIconList(self.debuffs, preview and self:MaxShownDebuffs() or 0)
    ns.RefreshDebuffContainer(self)
end

function CoTankAuras_Mixin:RefreshDefensiveLayout()
    local preview = (ns.isTestMode or ns.IsInEditMode()) and self:ShowDefensives()
    if not preview then
        self:ClearBigDefensives()
    end
    self:UpdateIconList(self.bigDefensives, preview and self:MaxShownDefensives() or 0)
    ns.RefreshDefensiveContainer(self)
end

-- ── Icon settings helpers ─────────────────────────────────────────────────
function ns.ApplyIconSettings(f)
    local db = ns.DB()
    local face = ns.FontPath()
    local flags = ns.FontFlags()
    -- Stack count size (0 = hidden)
    local size = ns.SettingNumber("stackCountSize", K.STACK_COUNT_DEFAULT_SIZE)
    f.stackHidden = (size <= 0)
    f.count:SetFont(face, math.max(size, 1), flags)
    f.count:SetTextColor(ns.FontColor("stackCountColor"))
    -- Stack count position, plus the free nudge offsets
    local posId = db.stackCountPos or "BR_IN"
    local pos
    for _, p in ipairs(K.STACK_COUNT_POSITIONS) do
        if p.id == posId then
            pos = p
            break
        end
    end
    pos = pos or K.STACK_COUNT_POSITIONS[1]
    local nudgeX = ns.SettingNumber("stackCountNudgeX", 0)
    local nudgeY = ns.SettingNumber("stackCountNudgeY", 0)
    f.count:ClearAllPoints()
    f.count:SetPoint(pos.point, f, pos.rel or pos.point, pos.px + nudgeX, pos.py + nudgeY)
    -- Cooldown scale and position
    local scaleInt = ns.SettingNumber("cdFontScale", K.CD_FONT_SCALE_DEFAULT)
    local scale = scaleInt / 10.0
    local cdAbove = db.cdAbove or false
    if f.cd.SetFontScale then
        f.cd:SetFontScale(math.max(scale, 0.05))
    end
    f.cd:SetHideCountdownNumbers(cdAbove or scale <= 0)
    if f.timerText then
        f.timerText:SetShown(cdAbove)
        local timerSize = ns.SettingNumber("timerTextSize", K.TIMER_TEXT_DEFAULT_SIZE)
        f.timerText:SetFont(face, math.max(timerSize, 1), flags)
        f.timerText:SetTextColor(ns.FontColor("timerTextColor"))
    end
end

function ns.RefreshAllFonts()
    if not CoTankAuras then
        return
    end
    local face = ns.FontPath()
    local flags = ns.FontFlags()
    if CoTankAuras.nameText then
        CoTankAuras.nameText:SetFont(face, ns.SettingNumber("nameFontSize", K.DEFAULT_NAME_FONT_SIZE), flags)
        CoTankAuras.nameText:SetTextColor(ns.FontColor("nameTextColor"))
    end
    if CoTankAuras.hpText then
        CoTankAuras.hpText:SetFont(face, ns.SettingNumber("hpFontSize", K.DEFAULT_HP_FONT_SIZE), flags)
        CoTankAuras.hpText:SetTextColor(ns.FontColor("hpTextColor"))
    end
    if CoTankAuras.deadText then
        CoTankAuras.deadText:SetFont(face, 16, flags)
    end
    if ns.Alert and ns.Alert.RefreshFont then
        ns.Alert:RefreshFont()
    end
    ns.RefreshAllIconSettings()
end

function ns.RefreshAllIconSettings()
    if not CoTankAuras then
        return
    end
    if CoTankAuras.debuffs then
        for _, f in ipairs(CoTankAuras.debuffs) do
            ns.ApplyIconSettings(f)
        end
    end
    if CoTankAuras.bigDefensives then
        for _, f in ipairs(CoTankAuras.bigDefensives) do
            ns.ApplyIconSettings(f)
        end
    end
    -- Live AuraButtons carry their own copies of these settings; they can only
    -- be restyled while auras are readable, which RestyleAuraButtons checks.
    ns.RestyleAuraButtons()
end

function ns.RefreshDebuffSpacing()
    if not CoTankAuras then
        return
    end
    ns.RefreshAuraContainerLayout(CoTankAuras)
    if not CoTankAuras.debuffs then
        return
    end
    local spacing = ns.SettingNumber("debuffSpacing", K.DEBUFF_SPACING)
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
    local grow = PRIVATE_AURA_GROW[ns.DB().privateAuraGrowDir or "LEFT"] or PRIVATE_AURA_GROW.LEFT
    for i, container in ipairs(frames) do
        container:ClearAllPoints()
        if i == 1 then
            container:SetPoint(grow.anchor[1], CoTankAuras, grow.anchor[2], 0, 0)
        else
            local point, relPoint, dx, dy = unpack(grow.step)
            container:SetPoint(point, frames[i - 1], relPoint, dx * spacing, dy * spacing)
        end
    end
end

function ns.RefreshPrivateAuraSpacing()
    if not CoTankAuras or not CoTankAuras.anchorFrames then
        return
    end
    local spacing = ns.SettingNumber("privateAuraSpacing", K.DEBUFF_SPACING)
    ApplyPrivateAuraGrow(CoTankAuras.anchorFrames, spacing)
end

function ns.RefreshPrivateAuraGrow()
    if not CoTankAuras or InCombatLockdown() then
        return
    end
    CoTankAuras:CleanupPrivateAnchors()
    ns.RefreshPrivateAuraSpacing()
    CoTankAuras:AttachPrivateAnchors()
end

function ns.RefreshPrivateAuraSize()
    if not CoTankAuras or not CoTankAuras.anchorFrames then
        return
    end
    if InCombatLockdown() then
        return
    end
    local size = ns.SettingNumber("privateAuraSize", K.PRIVATE_AURA_SIZE_DEFAULT)
    for _, container in ipairs(CoTankAuras.anchorFrames) do
        container:SetSize(size, size)
    end
    CoTankAuras:CleanupPrivateAnchors()
    CoTankAuras:AttachPrivateAnchors()
end

-- Above-icon timer updater for the preview icons only. Live icons are
-- AuraButtons whose duration text the engine formats itself, so this no longer
-- runs during normal play - only while the test or edit preview is up.
local timerUpdater = CreateFrame("Frame")
timerUpdater:SetScript("OnUpdate", function()
    if not ns.DB().cdAbove then
        return
    end
    if not CoTankAuras then
        return
    end
    if not (ns.isTestMode or ns.IsInEditMode()) then
        return
    end
    local now = GetTime()
    local function updateList(list)
        if not list then
            return
        end
        for _, f in ipairs(list) do
            if f.timerText and f:GetAlpha() > 0 and (f.expirationTime or 0) > 0 then
                local rem = f.expirationTime - now
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
local function CreateIconFrame(iconList, iconSize, point, parent, relativePoint, ofsx, ofsy)
    local f = CreateFrame("Button", nil, parent, "BackdropTemplate")
    f:SetFrameStrata("MEDIUM")
    f:SetMouseClickEnabled(true)
    f:SetSize(iconSize, iconSize)
    f:SetBackdrop({ edgeFile = K.BACKDROP_TEXTURE, edgeSize = 1 })
    f:SetBackdropBorderColor(0, 0, 0, 0.7)
    f.border = f

    -- Icon with 30% TexCoord zoom (removes default blizzard icon padding)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    f.icon:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.cd:SetAllPoints(f.icon)
    f.cd:SetReverse(true)

    -- Stack count (position/size driven by ns.ApplyIconSettings)
    f.count = f:CreateFontString(nil, "OVERLAY")
    f.count:SetFont(ns.FontPath(), 9, ns.FontFlags())
    f.count:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 2, 1)
    f.count:SetTextColor(1, 1, 1)

    -- Above-icon timer text (shown when cdAbove=true)
    f.timerText = f:CreateFontString(nil, "OVERLAY")
    f.timerText:SetFont(ns.FontPath(), 9, ns.FontFlags())
    f.timerText:SetPoint("BOTTOM", f, "TOP", 0, 2)
    f.timerText:SetTextColor(1, 0.85, 0.4)
    f.timerText:Hide()

    f:EnableMouse(true)
    f:SetScript("OnLeave", function()
        GameTooltip:Hide()
        if GameTooltip.ClearLines then
            GameTooltip:ClearLines()
        end
    end)
    f:SetScript("OnEnter", function(btn)
        -- TooltipInfo aura lookups by instance ID error while auras are
        -- secret. These frames are the test-mode preview only (live icons are
        -- AuraButtons, which carry their own engine tooltip), so bail out
        -- rather than risk the call.
        if ns.AurasAreSecret() then
            return
        end
        local unit = CoTankAuras and CoTankAuras:GetAttribute("unit")
        if unit and btn.auraInstanceID then
            GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
            pcall(GameTooltip.SetUnitAura, GameTooltip, unit, btn.auraInstanceID)
            GameTooltip:Show()
        end
    end)

    local idx = #iconList + 1
    if idx == 1 then
        f:SetPoint(point, parent, relativePoint, ofsx, ofsy)
    else
        f:SetPoint("RIGHT", iconList[idx - 1], "LEFT", -K.DEBUFF_SPACING, 0)
    end
    f:SetAlpha(0)
    iconList[idx] = f
    ns.ApplyIconSettings(f)
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
    local scaleFactor = ns.CalculateScaleFactor()
    local size = ns.SettingNumber("privateAuraSize", K.PRIVATE_AURA_SIZE_DEFAULT)
    for i = 1, K.PRIVATE_AURAS_MAX_COUNT do
        local container = CreateFrame("Frame", nil, self, "BackdropTemplate")
        container:SetSize(size, size)
        container:SetBackdrop({ edgeFile = K.BACKDROP_TEXTURE, edgeSize = 1 })
        container:SetBackdropBorderColor(0, 0, 0, 0)
        local anchor = CreateFrame("Frame", nil, container)
        anchor:SetAllPoints(container)
        self.anchorFrames[i] = container
        self.anchorFrames[i]:SetAlpha(1)
        self.anchorFrames[i]:SetScale(scaleFactor)
    end
    local spacing = ns.SettingNumber("privateAuraSpacing", K.DEBUFF_SPACING)
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
    for i, container in ipairs(self.anchorFrames) do
        if i <= max then
            if not container.mockIcon then
                local tex = container:CreateTexture(nil, "OVERLAY")
                tex:SetPoint("TOPLEFT", container, "TOPLEFT", 1, -1)
                tex:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -1, 1)
                tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                container.mockIcon = tex
            end
            container.mockIcon:SetTexture(mocks[i])
            container.mockIcon:SetAlpha(0.5)
            container:SetBackdropBorderColor(0, 0, 0, 0.7)
            -- Mock stack count
            if not container.mockStack then
                local fs = container:CreateFontString(nil, "OVERLAY")
                fs:SetFont(ns.FontPath(), 10, ns.FontFlags())
                fs:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 1, 1)
                container.mockStack = fs
            end
            local stacks = ({ 3, 1, 5, 2 })[((i - 1) % 4) + 1]
            container.mockStack:SetText(stacks > 1 and tostring(stacks) or "")
            container.mockStack:Show()
        elseif container.mockIcon then
            container.mockIcon:SetAlpha(0)
            container:SetBackdropBorderColor(0, 0, 0, 0)
            if container.mockStack then
                container.mockStack:Hide()
            end
        end
    end
end

function CoTankAuras_Mixin:HideMockPrivateAuras()
    if not self.anchorFrames then
        return
    end
    for _, container in ipairs(self.anchorFrames) do
        if container.mockIcon then
            container.mockIcon:SetAlpha(0)
        end
        container:SetBackdropBorderColor(0, 0, 0, 0)
    end
end

function CoTankAuras_Mixin:AttachPrivateAnchors()
    self:CleanupPrivateAnchors()
    self:RefreshAuraLayout()
    if not self:IsVisible() or not self:ShowPrivateAuras() then
        return
    end
    -- In test mode show placeholder icons instead of attaching real engine anchors
    if ns.isTestMode then
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
    local size = ns.SettingNumber("privateAuraSize", K.PRIVATE_AURA_SIZE_DEFAULT)
    local borderVal = ns.SettingNumber("privateAuraBorderScale", K.PRIVATE_AURA_BORDER_SCALE_DEFAULT)
    local borderScale = borderVal <= 0 and -100 or borderVal
    local stackScale = ns.SettingNumber("privateAuraStackScale", K.PRIVATE_AURA_STACK_SCALE_DEFAULT)
    for i = 1, #self.anchorFrames do
        local id = C_UnitAuras.AddPrivateAuraAnchor({
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
        if id then
            table.insert(self.privateAnchorIDs, id)
        end
        if stackScale > 1 then
            if not self.privateStackFrames[i] then
                local sf = CreateFrame("Frame", nil, self.anchorFrames[i])
                sf:SetSize(0.001, 0.001)
                sf:SetPoint("BOTTOMRIGHT", self.anchorFrames[i], "BOTTOMRIGHT", 0, 0)
                self.privateStackFrames[i] = sf
            end
            self.privateStackFrames[i]:SetScale(stackScale)
            local sid = C_UnitAuras.AddPrivateAuraAnchor({
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
            if sid then
                table.insert(self.privateStackAnchorIDs, sid)
            end
        end
    end
end

function CoTankAuras_Mixin:CleanupPrivateAnchors()
    if self.privateAnchorIDs then
        for _, id in ipairs(self.privateAnchorIDs) do
            C_UnitAuras.RemovePrivateAuraAnchor(id)
        end
        self.privateAnchorIDs = {}
    end
    if self.privateStackAnchorIDs then
        for _, id in ipairs(self.privateStackAnchorIDs) do
            C_UnitAuras.RemovePrivateAuraAnchor(id)
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
    local watchUnit = ns.isTestMode and "player" or value
    if watchUnit then
        self:RegisterUnitEvent("UNIT_HEALTH", watchUnit)
        self:RegisterUnitEvent("UNIT_MAXHEALTH", watchUnit)
        self:RegisterUnitEvent("UNIT_POWER_UPDATE", watchUnit)
        self:RegisterUnitEvent("UNIT_MAXPOWER", watchUnit)
        self:RegisterUnitEvent("UNIT_DISPLAYPOWER", watchUnit)
        self:RegisterUnitEvent("UNIT_AURA", watchUnit)
        -- In test mode also watch the real co-tank's auras so debuffs update live
        if ns.isTestMode and value and value ~= watchUnit then
            self:RegisterUnitEvent("UNIT_AURA", value)
        end
        self:AttachPrivateAnchors()
        ns.RefreshAuraContainers(self)
        ns.Alert:RegisterAuraSounds(value)
        self:UpdateVisuals()
    else
        if not ns.isTestMode then
            self:SetNameText("NO CO-TANK")
        end
        self.health:SetValue(0)
        self.power:SetValue(0)
        self:ClearDebuffs()
        self:CleanupPrivateAnchors()
        ns.RefreshAuraContainers(self)
        ns.Alert:RegisterAuraSounds(nil)
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
    local now = GetTime()
    if (self.nextUpdate or 0) > now then
        -- Throttled. Queue one catch-up pass for the end of the window, or
        -- the last change in a burst is dropped and the bar sits on a stale
        -- value until the co-tank next takes damage or healing.
        if not self.updateQueued then
            self.updateQueued = true
            C_Timer.After(self.nextUpdate - now, function()
                self.updateQueued = false
                self:UpdateVisuals()
            end)
        end
        return
    end
    self.nextUpdate = now + K.UPDATE_THROTTLE
    local unit = self:GetAttribute("unit")
    if not unit or not UnitExists(unit) then
        return
    end
    self:UpdateHealthBar()
    self:UpdatePower()
    self:UpdateDebuffs()
    self:UpdateBigDefensives()
    self:UpdateDeadState()
    if not ns.isTestMode then
        local name = UnitName(unit)
        if name then
            self:SetNameText(name)
        end
    end
end

-- Export
ns.Mixin = CoTankAuras_Mixin
