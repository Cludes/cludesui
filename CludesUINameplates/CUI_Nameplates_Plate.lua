if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_Nameplates_Plate.lua
--
--  Blizzard frame hiding, the cast fallback frame, text helpers and the
--  NameplateFrame mixin: cast text, appearance, target of target, SetUnit,
--  ClearUnit.
--  Reads the earlier nameplate files through ns and ns._npInternals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._npInternals
-- CludesUINameplates.lua or an earlier nameplate file failed to load.
if not Inner or Inner.broken then return end
Inner.broken = true

local pairs, type = pairs, type
local Pix = CludesUI.PP
local UnitName = UnitName
local UnitIsUnit, UnitCanAttack = UnitIsUnit, UnitCanAttack
local UnitIsPlayer = UnitIsPlayer
local UnitClassBase = UnitClassBase
local UnitCastingInfo, UnitChannelInfo = UnitCastingInfo, UnitChannelInfo

local defaultSet, GetNPOutline, HP_BAR_SLOTS = Inner.defaults, Inner.GetNPOutline, Inner.HP_BAR_SLOTS
local SetFSFont, ApplyHealthBarTexture = Inner.SetFSFont, Inner.ApplyHealthBarTexture
local GetCastBarHeight, GetEnemyNameTextSize = Inner.GetCastBarHeight, Inner.GetEnemyNameTextSize
local GetFocusCastHeight, GetHealthBarHeight = Inner.GetFocusCastHeight, Inner.GetHealthBarHeight
local GetHealthBarWidth, GetHitboxYShift = Inner.GetHealthBarWidth, Inner.GetHitboxYShift
local GetNameplateYOffset, GetNameYOffset = Inner.GetNameplateYOffset, Inner.GetNameYOffset
local GetShowCastIcon, GetStackSpacingScale = Inner.GetShowCastIcon, Inner.GetStackSpacingScale
local GetTextSlot, GetTextSlotColor = Inner.GetTextSlot, Inner.GetTextSlotColor
local GetTextSlotOffsets, GetTextSlotSize = Inner.GetTextSlotOffsets, Inner.GetTextSlotSize
local IsComboHealthText = Inner.IsComboHealthText
local NotifyCastEnded, GetClassPowerTopPush = Inner.NotifyCastEnded, Inner.GetClassPowerTopPush
local HideClassPowerOnPlate = Inner.HideClassPowerOnPlate

local p
Inner.profileSetters[#Inner.profileSetters + 1] = function(val) p = val end

-- Pre-hook SetTexture for pooled aura-slot icons (snap-disabled at creation, so
-- the pixel-snap hook is pure overhead). Upgraded to PP.RawSetTexture in
-- OnEnable; starts as a plain wrapper so it is never nil.
local RawSetTex = function(t, val) t:SetTexture(val) end

local hookedUFs = {}
local hookedHighlights = {}
local hookedSoftTargetIcons = {}
local npOffscreenParent = CreateFrame("Frame")
npOffscreenParent:Hide()
local savedParents = {}
-- Park record per pooled UnitFrame (our table, weak on the frame): the swept children in park
-- order, plus .held while HideBlizzardFrame owns the frame. Wiped and reused by the reclaim.
mod._npParked = setmetatable({}, { __mode = "k" })
local function MoveToOffscreen(part, unitToken)
    if not part then return end
    -- PERF: skip SetParent if already offscreen (saves ~14 calls per plate respawn)
    if part:GetParent() == npOffscreenParent then return end
    if not savedParents[part] then savedParents[part] = part:GetParent() end
    part:SetParent(npOffscreenParent)
end
local function HideBlizzardFrame(plateFrame, unitToken)
    if not plateFrame then return end
    local unitFrame = plateFrame.UnitFrame
    if not unitFrame then return end
    -- Suppress unconditionally: if we are called, an CUI plate is taking over this nameplate.
    -- NEVER gate on UnitCanAttack -- it can return false on the first frame (unit not fully
    -- registered), skipping the whole block and leaving Blizzard's UnitFrame visible as a
    -- giant black box.
    unitFrame:SetAlpha(0)
    local rec = mod._npParked[unitFrame]
    if not rec then
        rec = {}
        mod._npParked[unitFrame] = rec
    end
    rec.held = true
    -- The AurasFrame rides offscreen with the other children (WidgetContainer is the one child
    -- kept live, below): our containers own plate auras and these lists are taint-locked and
    -- unused. Alpha-0 keep-alive is NOT enough -- its item frames are mouse-enabled Blizzard
    -- templates with tooltip handlers, an invisible tooltip/click trap parked above every plate.
    if unitFrame.AurasFrame then MoveToOffscreen(unitFrame.AurasFrame, unitToken) end
    -- Park the UnitFrame's child frames on the hidden holder, discovered generically:
    -- whatever Blizzard parents under the UnitFrame is swept, no per-widget list to maintain.
    -- The UnitFrame ITSELF must stay on the nameplate where Blizzard placed it (alpha 0 above)
    -- -- parking the whole frame under a hidden holder flips every plate's content to
    -- IsVisible()==false and breaks click target selection between overlapping plates in packs.
    -- Exclusions: kept-live frames, plus protected/forbidden children (alpha 0 hides them).
    -- Walk backwards: each SetParent below removes that child from uf's list, and only the
    -- indices already visited shift, so none is skipped. Runs twice per enemy plate add, so
    -- it reads the live list instead of building a table. A child is recorded once: an enemy
    -- re-acquire finds its children already parked, so the record never grows.
    for index = unitFrame:GetNumChildren(), 1, -1 do
        local childFrame = (select(index, unitFrame:GetChildren()))
        if
            childFrame
            and childFrame ~= unitFrame.WidgetContainer
            and childFrame ~= unitFrame.AurasFrame
            and childFrame ~= unitFrame.SoftTargetFrame
            and not childFrame:IsForbidden()
            and not childFrame:IsProtected()
        then
            if not savedParents[childFrame] then
                savedParents[childFrame] = unitFrame
                rec[#rec + 1] = childFrame
            end
            childFrame:SetParent(npOffscreenParent)
        end
    end
    -- All visual children are reparented offscreen so layout recalculations cannot shift
    -- bounds.
    -- Kill the CompactUnitFrame's ENTIRE event surface (raid-frames-style
    -- takeover): Blizzard registers ~27 unit events (incl. UNIT_AURA) plus
    -- ~20 globals (incl. UPDATE_MOUSEOVER_UNIT) per plate, and its dirty
    -- flags arm a real OnUpdate on this alpha-0 frame -- none of which our
    -- rendering uses, all of which was running under every plate all combat
    -- long. Partial self-heal: the driver's secure CompactUnitFrame_SetUnit
    -- restores the unit events and OnUnitSet's set when the pooled frame is
    -- next acquired, for any unit; the globals CompactUnitFrame_OnLoad
    -- registers never come back, and UpdateAll on each acquire keeps that
    -- stale window to one plate life. The soft-target trio comes back below:
    -- the kept-alive SoftTargetFrame icon is driven by exactly those events
    -- (the OnEvent script itself stays -- Blizzard set it, and
    -- UnregisterAllEvents clears registrations only).
    unitFrame:UnregisterAllEvents()
    unitFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    unitFrame:RegisterEvent("PLAYER_SOFT_FRIEND_CHANGED")
    unitFrame:RegisterEvent("PLAYER_SOFT_ENEMY_CHANGED")
    -- The cast bar is its own frame with its own registrations (we render our own). It lives
    -- at CastBarsContainer.castBar; the driver's SetUnit re-registers it on reacquisition.
    local blizzCastBar = unitFrame.castBar
        or (unitFrame.CastBarsContainer and unitFrame.CastBarsContainer.castBar)
    if blizzCastBar and not blizzCastBar:IsForbidden() then blizzCastBar:UnregisterAllEvents() end
    -- Keep WidgetContainer functional but reparent to the nameplate itself so its layout
    -- doesn't affect the UnitFrame's bounds.
    if unitFrame.WidgetContainer then unitFrame.WidgetContainer:SetParent(plateFrame) end
    -- Keep the soft-target cursor icon working: reparent it live instead of sweeping it
    -- offscreen or leaving it under uf's forced alpha-0.
    if unitFrame.SoftTargetFrame then
        unitFrame.SoftTargetFrame:SetParent(plateFrame)
        unitFrame.SoftTargetFrame:SetAlpha(1)
        -- Same icon is reused for enemy/friend/interact soft-targets; only allow the
        -- interact case through. The hook cannot be uninstalled, so it gates on the
        -- pooled UnitFrame's own current unit (the driver's SetUnit sets it before it
        -- shows the icon), never on where the icon hangs: the first Show of an add
        -- runs before we park or reclaim the frame. Every attackable unit is ours.
        local iconTex = unitFrame.SoftTargetFrame.Icon
        if iconTex and not hookedSoftTargetIcons[iconTex] then
            hookedSoftTargetIcons[iconTex] = unitFrame
            hooksecurefunc(iconTex, "Show", function(self)
                local ownerFrame = hookedSoftTargetIcons[self]
                local frameUnit = ownerFrame and ownerFrame.unit
                if not frameUnit then return end
                -- Hide only for attackable enemies. NPCs and non-attackable
                -- objects, even hostile ones, keep the icon.
                local canAttack = UnitCanAttack("player", frameUnit)
                if issecretvalue and issecretvalue(canAttack) then return end
                if canAttack then self:Hide() end
            end)
        end
    end
    if not hookedUFs[unitFrame] then
        hookedUFs[unitFrame] = true
        local locked = false
        hooksecurefunc(unitFrame, "SetAlpha", function(self)
            if locked then return end
            -- Force alpha 0 only while an CUI plate owns this nameplate. On recycle to a
            -- friendly unit the plate is released and ns.plates[unit] is nil, so the hook no-ops.
            local frameUnit = self.unit or (self.GetUnit and self:GetUnit())
            if not frameUnit or not mod.plates[frameUnit] then return end
            locked = true
            self:SetAlpha(0)
            locked = false
        end)
    end
    if unitFrame.selectionHighlight and not hookedHighlights[unitFrame.selectionHighlight] then
        hookedHighlights[unitFrame.selectionHighlight] = true
        hooksecurefunc(unitFrame.selectionHighlight, "Show", function(self)
            local hostFrame = self:GetParent()
            if hostFrame == npOffscreenParent then return end
            if hostFrame then
                local frameUnit = hostFrame.unit or (hostFrame.GetUnit and hostFrame:GetUnit())
                if frameUnit and UnitExists(frameUnit) and UnitCanAttack("player", frameUnit) then
                    self:SetAlpha(0)
                    self:Hide()
                end
            end
        end)
        hooksecurefunc(unitFrame.selectionHighlight, "SetShown", function(self, isShown)
            if isShown then
                local hostFrame = self:GetParent()
                if hostFrame == npOffscreenParent then return end
                if hostFrame then
                    local frameUnit = hostFrame.unit or (hostFrame.GetUnit and hostFrame:GetUnit())
                    if frameUnit and UnitExists(frameUnit) and UnitCanAttack("player", frameUnit) then
                        self:SetAlpha(0)
                        self:Hide()
                    end
                end
            end
        end)
    end
end
-- Hand a pooled UnitFrame back its parked pieces when the driver acquires it for a unit we do
-- not take over. Not at NAME_PLATE_UNIT_REMOVED: the driver has already released the frame
-- (base.UnitFrame is nil) before any addon sees that event. Enemy re-acquires skip this and
-- re-park in place. Zero cost for a frame no enemy ever held: one lookup.
function mod.NP_ReclaimBlizzardFrame(unitFrame)
    local rec = unitFrame and mod._npParked[unitFrame]
    if not (rec and rec.held) or unitFrame:IsForbidden() then return end
    -- Reverse park order, so the children return to uf in their original order.
    for index = #rec, 1, -1 do
        local childFrame = rec[index]
        if savedParents[childFrame] == unitFrame then
            savedParents[childFrame] = nil
            if childFrame:GetParent() == npOffscreenParent then childFrame:SetParent(unitFrame) end
        end
    end
    wipe(rec)
    unitFrame:SetAlpha(1)
    local auras = unitFrame.AurasFrame
    local auraParent = auras and savedParents[auras]
    if auraParent then
        savedParents[auras] = nil
        if auras:GetParent() == npOffscreenParent then auras:SetParent(auraParent) end
    end
    -- The kept-live frames still sit on the base of the enemy that last held this frame.
    local wc, stf = unitFrame.WidgetContainer, unitFrame.SoftTargetFrame
    if wc and wc:GetParent() ~= unitFrame then wc:SetParent(unitFrame) end
    if stf and stf:GetParent() ~= unitFrame then stf:SetParent(unitFrame) end
end
-- Blizzard's behind-camera arrow (the rotated offscreen icon under a plate whose unit is
-- behind the camera; retail and WoW Forever) stays hidden on every plate, friendly ones
-- included. Alpha only: Blizzard drives nothing but its shown state, so alpha 0 holds
-- for the life of the pooled UnitFrame; once per frame (weak external record, nothing
-- written on Blizzard's frame). A client without the arrow has nothing to hide.
local hiddenBehindCam = setmetatable({}, { __mode = "k" })
function mod.NP_HideBehindCameraIcon(unitFrame)
    if not unitFrame or hiddenBehindCam[unitFrame] or unitFrame:IsForbidden() then return end
    hiddenBehindCam[unitFrame] = true
    local iconTex = unitFrame.behindCameraIcon
    if iconTex then iconTex:SetAlpha(0) end
end
mod.HideBlizzardFrame = HideBlizzardFrame
local castFallback = CreateFrame("Frame")
Inner.fallbackCastCount = 0
local _fallbackPlates = {}
castFallback._textAccum = 0.1
castFallback:SetScript("OnUpdate", function(self, elapsed)
    -- Bar fill tracks every frame (smoothness); target TEXT refreshes at 10Hz -- names never
    -- change faster and per-frame SetText is wasted, especially on secret strings.
    local textAccum = self._textAccum + elapsed
    local doText = textAccum >= 0.1
    self._textAccum = doText and 0 or textAccum
    for backing in pairs(_fallbackPlates) do
        if backing.isCasting and backing.unit and backing.nameplate then
            local bc = backing.nameplate.UnitFrame and backing.nameplate.UnitFrame.castBar
            if bc and bc:IsShown() then
                backing.cast:SetMinMaxValues(bc:GetMinMaxValues())
                backing.cast:SetValue(bc:GetValue())
                -- Keep spell name + target current in fallback mode.
                if doText and backing.UpdateCastText then
                    local castName = UnitCastingInfo(backing.unit)
                    if type(castName) == "nil" then castName = UnitChannelInfo(backing.unit) end
                    backing:UpdateCastText(castName)
                end
            else
                if not backing._interrupted then backing.cast:Hide() end
                backing.isCasting = false
                backing._castFallback = nil
                _fallbackPlates[backing] = nil
                Inner.fallbackCastCount = Inner.fallbackCastCount - 1
                if Inner.fallbackCastCount <= 0 then
                    Inner.fallbackCastCount = 0
                    castFallback:Hide()
                end
                NotifyCastEnded(backing)
            end
        end
    end
end)
castFallback:Hide()

-- Shared cast-bar text anchoring. The text line holds three elements (spell name, spell
-- target, cast timer), each assigned to a side. The timer reserves a fixed width on its side;
-- a non-center element sharing that side shifts inward by that width. Center elements anchor
-- to the bar center and are never pushed.
--   side    : "left" | "right" | "center"
--   pushed  : true when the timer shares this side and this element must move in
--   reserve : timer reserved width (only consumed when pushed)
--   isTimer : the timer uses slightly tighter base insets than text
-- Returns: point (anchor), xOff (base, before the user X offset), justify
function mod.GetCastTextAnchor(side, pushed, reserve, isTimer)
    if side == "center" then
        return "CENTER", 0, "CENTER"
    elseif side == "left" then
        local base = isTimer and 3 or 5
        if pushed then base = base + reserve end
        return "LEFT", base, "LEFT"
    else -- "right"
        local base = -3
        if pushed then base = base - reserve end
        return "RIGHT", base, "RIGHT"
    end
end

-- WoW does not visually re-lay-out a FontString when only SetJustifyH changes (only a fresh
-- build does), so clear then re-set the text to force realignment -- and it MUST be a real
-- change, since re-setting an identical string is deduped and skips the re-layout. GetText may
-- return a secret (enemy name, cast name/target): SetText accepts secrets without inspecting
-- them, but truthiness/equality on a secret errors, so the existence check uses type() rather
-- than `t or ""`.
function mod.ReflowFontString(fontStr)
    local t = fontStr:GetText()
    fontStr:SetText("")
    if type(t) == "nil" then
        fontStr:SetText("")
    else
        fontStr:SetText(t)
    end
end

local NameplateFrame = {}

function NameplateFrame:UpdateCastText(spellName)
    local castTarget, spellTargetClass
    if UnitShouldDisplaySpellTargetName and UnitShouldDisplaySpellTargetName(self.unit) then
        local rawTarget = UnitSpellTargetName and UnitSpellTargetName(self.unit)
        -- Names may be SECRET: type() is safe, and SetText/SetFormattedText accept secret
        -- strings without exposing them to Lua.
        if type(rawTarget) ~= "nil" then
            castTarget = rawTarget
            spellTargetClass = UnitSpellTargetClass and UnitSpellTargetClass(self.unit)
        end
    end

    local targeted = type(castTarget) ~= "nil"
    local saved = p or defaultSet
    local combine = saved.castCombineNameTarget == true
    local useClassColor = defaultSet.castTargetClassColor
    if saved.castTargetClassColor ~= nil then useClassColor = saved.castTargetClassColor end

    local targetColor
    if useClassColor then
        if type(spellTargetClass) ~= "nil" and C_ClassColor then
            targetColor = C_ClassColor.GetClassColor(spellTargetClass)
        end
    end

    local nameColor = saved.castNameColor or defaultSet.castNameColor
    -- Combined mode paints the target color onto the cast NAME string (the target rides
    -- in it as a format arg); separate mode paints its own FontString.
    local targetLabel
    if combine and targeted then
        targetLabel = self.castName
    else
        targetLabel = self.castTarget
    end
    if useClassColor then
        if targetColor then
            targetLabel:SetTextColor(targetColor:GetRGB())
        else
            targetLabel:SetTextColor(1, 1, 1, 1)
        end
    else
        local color = saved.castTargetColor or defaultSet.castTargetColor
        targetLabel:SetTextColor(color.r, color.g, color.b, 1)
    end
    if not combine or not targeted then
        self.castName:SetTextColor(nameColor.r, nameColor.g, nameColor.b, 1)
    end

    if type(spellName) == "nil" then
        self.castName:SetText("")
    elseif combine and targeted then
        -- 12.1 class RGB may be SECRET: use it as the FontString's base color,
        -- then override only the spell prefix with a clean profile-color escape.
        local nameHex = string.format(
            "ff%02x%02x%02x",
            math.floor(nameColor.r * 255 + 0.5),
            math.floor(nameColor.g * 255 + 0.5),
            math.floor(nameColor.b * 255 + 0.5)
        )
        self.castName:SetFormattedText("|c" .. nameHex .. "%s - |r%s", spellName, castTarget)
    else
        self.castName:SetText(spellName)
    end
    if combine or not targeted then
        self.castTarget:SetText("")
    else
        self.castTarget:SetText(castTarget)
    end

    local castWidth = self.cast:GetWidth()
    if castWidth and castWidth > 0 then
        local nameWidth = combine and (saved.castCombinedWidthPct or defaultSet.castCombinedWidthPct)
            or (saved.castNameWidthPct or defaultSet.castNameWidthPct)
        self.castName:SetWidth(castWidth * nameWidth / 100)
    end
    self.castName:SetShown((saved.castNameSide or defaultSet.castNameSide) ~= "none")
    self.castTarget:SetShown(
        not combine and targeted and (saved.castTargetSide or defaultSet.castTargetSide) ~= "none"
    )
end

-- Appearance generation: bumped by RefreshAllSettings so plates re-apply static appearance on
-- next SetUnit. Plates stamp _appearanceGen after applying so cache-hit re-spawns skip the work.
mod._npAppearanceGen = mod._npAppearanceGen or 1

-- Static appearance: anchors, sizes, fonts, colors and aura layout depending only on settings,
-- not the bound unit. Runs once per plate after creation, then only when RefreshAllSettings
-- bumps the generation. Saves ~0.7ms per spawn.
function NameplateFrame:ApplyAppearance()
    self:SetSize(1, 1)
    local castH = GetCastBarHeight()
    self.health:ClearAllPoints()
    self.health:SetPoint("CENTER", self, "CENTER", 0, GetNameplateYOffset())
    self.health:SetSize(GetHealthBarWidth(), GetHealthBarHeight())
    mod.NP_SizeAbsorbBars(self, GetHealthBarWidth(), GetHealthBarHeight())
    -- (Classic WoW UI seats its health border from self:ApplyBorder below,
    -- once the bar carries its new size. A second seat here would repeat the
    -- level's font, anchors and unit reads for nothing.)
    mod.ApplyLowHpGlow(self)
    -- Width may have changed: clear the overlay gates so the next apply re-runs geometry (the
    -- stripe texcoord crop derives from the settings width, which the gates never watch).
    self._ovTgtTex, self._ovFocTex, self._ovHoverTex = nil, nil, nil
    mod.LayoutCastBar(self, mod.GetHealthBarWidth(), castH)
    mod.LayoutCastIcon(self, castH)
    local showIcon = GetShowCastIcon()
    if showIcon then
        self.castIconFrame:Show()
    else
        self.castIconFrame:Hide()
    end
    -- After the icon's own show state: the custom icon border is not its child.
    mod.ApplyCastIconBorder(self)
    self.castLeftBorder:SetWidth(1)
    mod.NP_SetSparkHeight(self, castH)
    -- Show Spark (Cast Color cog): default on; explicit false hides it.
    self.castSpark:SetShown(not (p and p.castBarSparkEnabled == false))
    self.kickMarker:SetSize(GetHealthBarWidth(), castH)
    -- Enemy name color (per-slot; any name-family variant)
    local nameSlotKey = mod.FindNameSlot()
    if nameSlotKey then
        local nr, ng, nb = GetTextSlotColor(nameSlotKey)
        self.name:SetTextColor(nr, ng, nb, 1)
    end
    -- The Threat Colors name memo: the static write above replaces its tint.
    self._nameThR, self._nameThG, self._nameThB = nil, nil, nil
    -- Same for the Text Coloring slot memo: the static slot colours written here and
    -- in ApplyHealthTextAppearance below replace what it last painted.
    if self._scMemo then
        for _, entry in pairs(self._scMemo) do
            entry[1] = nil
        end
    end
    self:RefreshNamePosition()
    -- Cast text sizes, colors, and offsets
    local cns = (p and p.castNameSize) or defaultSet.castNameSize
    local cts = (p and p.castTargetSize) or defaultSet.castTargetSize
    local cnc = (p and p.castNameColor) or defaultSet.castNameColor
    local ctmSz = (p and p.castTimerSize) or defaultSet.castTimerSize
    local ctmC = (p and p.castTimerColor) or defaultSet.castTimerColor
    local cnOX = (p and p.castNameOffsetX) or defaultSet.castNameOffsetX
    local cnOY = (p and p.castNameOffsetY) or defaultSet.castNameOffsetY
    local ctOX = (p and p.castTargetOffsetX) or defaultSet.castTargetOffsetX
    local ctOY = (p and p.castTargetOffsetY) or defaultSet.castTargetOffsetY
    local tmOX = (p and p.castTimerOffsetX) or defaultSet.castTimerOffsetX
    local tmOY = (p and p.castTimerOffsetY) or defaultSet.castTimerOffsetY
    SetFSFont(self.castName, cns, GetNPOutline())
    SetFSFont(self.castTarget, cts, GetNPOutline())
    SetFSFont(self.castTimer, ctmSz, GetNPOutline())
    self.castTimer:SetTextColor(ctmC.r, ctmC.g, ctmC.b, 1)
    local showTimer = defaultSet.showCastTimer
    if p and p.showCastTimer ~= nil then showTimer = p.showCastTimer end
    self._showCastTimer = showTimer
    local nameSide = (p and p.castNameSide) or defaultSet.castNameSide
    local targetSide = (p and p.castTargetSide) or defaultSet.castTargetSide
    local timerSide = (p and p.castTimerSide) or defaultSet.castTimerSide
    local combineNameTarget = p and p.castCombineNameTarget == true
    local castWidth = self.cast:GetWidth()
    local timerW = ctmSz * 2.2
    -- Per-element truncation: width as a % of the cast bar, plus a wrap toggle.
    local cnWPct = (p and p.castNameWidthPct) or defaultSet.castNameWidthPct
    if combineNameTarget then cnWPct = (p and p.castCombinedWidthPct) or defaultSet.castCombinedWidthPct end
    local ctWPct = (p and p.castTargetWidthPct) or defaultSet.castTargetWidthPct
    local cnWrap = defaultSet.castNameWrap
    if p and p.castNameWrap ~= nil then cnWrap = p.castNameWrap end
    local ctWrap = defaultSet.castTargetWrap
    if p and p.castTargetWrap ~= nil then ctWrap = p.castTargetWrap end
    self.castName:SetWordWrap(cnWrap)
    self.castName:SetMaxLines(cnWrap and 2 or 1)
    self.castTarget:SetWordWrap(ctWrap)
    self.castTarget:SetNonSpaceWrap(false)
    self.castTarget:SetMaxLines(ctWrap and 2 or 1)
    if castWidth and castWidth > 0 then
        if nameSide ~= "none" then
            local pt, xb, jh =
                mod.GetCastTextAnchor(nameSide, showTimer and timerSide == nameSide, timerW, false)
            self.castName:SetWidth(castWidth * cnWPct / 100)
            self.castName:SetJustifyH(jh)
            self.castName:ClearAllPoints()
            self.castName:SetPoint(pt, self.cast, pt, xb + cnOX, cnOY)
        end
        if targetSide ~= "none" then
            local pt, xb, jh =
                mod.GetCastTextAnchor(targetSide, showTimer and timerSide == targetSide, timerW, false)
            self.castTarget:SetWidth(castWidth * ctWPct / 100)
            self.castTarget:SetJustifyH(jh)
            self.castTarget:ClearAllPoints()
            self.castTarget:SetPoint(pt, self.cast, pt, xb + ctOX, ctOY)
        end
        -- Timer side is only "left"/"right"; visibility stays governed by showTimer.
        local tpt, txb, tjh = mod.GetCastTextAnchor(timerSide, false, timerW, true)
        -- timerW stays the layout reserve (pushes name/target inward above), but the timer
        -- FontString auto-sizes (width 0) so a long value never truncates. Pinned by its outer
        -- edge (RIGHT on the right side, LEFT on the left), so overflow grows inward past the
        -- reserved slot while the pinned edge holds.
        self.castTimer:SetWidth(0)
        self.castTimer:SetJustifyH(tjh)
        self.castTimer:ClearAllPoints()
        self.castTimer:SetPoint(tpt, self.cast, tpt, txb + tmOX, tmOY)
    end
    -- Base visibility by side (UpdateCast refines the target per cast on hasTarget).
    self.castName:SetShown(nameSide ~= "none")
    self.castTarget:SetShown(not combineNameTarget and targetSide ~= "none")
    self.castTimer:SetShown(showTimer)
    -- Force the new justify onto already-rendered text (side changed mid-cast): a fresh cast
    -- re-flows itself via UpdateCast, a live setting change does not.
    mod.ReflowFontString(self.castName)
    mod.ReflowFontString(self.castTarget)
    mod.ReflowFontString(self.castTimer)
    self.castName:SetTextColor(cnc.r, cnc.g, cnc.b, 1)
    ApplyHealthBarTexture(self)
    mod.ApplyCastBarTexture(self)
    mod.ApplyBarBackgrounds(self)
    mod.ApplyAbsorbStyle(self)
    self:ApplyBorder()
    self:ApplyBorderColor()
    if self.ApplyCastBorder then self:ApplyCastBorder() end
    if self.ApplyCastBorderColor then self:ApplyCastBorderColor() end
    self:ApplyHealthTextAppearance()
    if mod.RefreshCastOverlay then mod.RefreshCastOverlay(self) end
    -- Re-sync the cast-bar wrap LAST, after normal borders and cast-overlay lift are
    -- re-applied: for a wrapped plate this re-hides the borders ApplyBorder/ApplyCastBorder
    -- just re-showed (no double border). Pure no-op unless enabled or wrapped.
    if self.UpdateBorderWrap and (self._wrapActive or self._cbWrapActive or mod.GetWrapBorderCastbar()) then
        self:UpdateBorderWrap()
    end
    mod.ApplySlotStrata(self)
end

-- PERF: health text font/position/color + cached slot assignments. Called from ApplyAppearance
-- (settings change/fresh plate), NEVER per health tick; UpdateHealthValues only rewrites text
-- content via the cache.
-- Anchors one bar-slot font string. A bottom slot hangs under the health bar's
-- corner and drops below the cast bar while one shows (AnchorBottomTexts
-- re-runs this on every cast show / hide). A top corner slot sits over the
-- bar's corner at the Top text's height, above the class power pips while they
-- show (AnchorTopCornerTexts re-runs this with the name's re-anchor).
function NameplateFrame:PlaceSlotText(fontStr, slotRec, textOffX, textOffY)
    fontStr:ClearAllPoints()
    if slotRec.bottom then
        local drop = (self.cast:IsShown() and self._castDrop) or 0
        Pix.Point(
            fontStr,
            slotRec.anchor,
            self.health,
            slotRec.point,
            slotRec.xOff + textOffX,
            drop - 2 + textOffY
        )
    elseif slotRec.top then
        Pix.Point(
            fontStr,
            slotRec.anchor,
            self.health,
            slotRec.point,
            slotRec.xOff + textOffX,
            4 + GetNameYOffset() + GetClassPowerTopPush(self) + textOffY
        )
    elseif slotRec.anchor == "CENTER" then
        fontStr:SetPoint("CENTER", self.health, "CENTER", textOffX, textOffY)
    else
        Pix.Point(fontStr, slotRec.anchor, self.health, slotRec.point, slotRec.xOff + textOffX, textOffY)
    end
end
-- Cast shown or hidden: re-anchor whatever the bottom slots hold. Runs only
-- while a bottom slot is in use (ns._npBottomUsed).
function NameplateFrame:AnchorBottomTexts()
    local B = mod._npBottomFS
    for slotIdx = 4, 5 do
        local slotRec = HP_BAR_SLOTS[slotIdx]
        local key = B[slotIdx - 3]
        local fontStr = key and self[key]
        if fontStr then
            -- Prebuilt keys: this runs on every cast show / hide.
            local textOffX = (p and p[slotRec.xKey]) or 0
            local textOffY = (p and p[slotRec.yKey]) or 0
            if key == "name" and slotIdx == 4 and self._nameRaidMarkerShown then
                textOffX = textOffX
                    + ((p and p.nameRaidMarkerSize) or defaultSet.nameRaidMarkerSize or 14)
                    + 3
            end
            self:PlaceSlotText(fontStr, slotRec, textOffX, textOffY)
        end
    end
end
-- The class power push changed (RefreshNamePosition): re-anchor whatever the top
-- corner slots hold. Runs only while a top corner slot is in use (ns._npTopCornerUsed).
function NameplateFrame:AnchorTopCornerTexts()
    local T = mod._npTopCornerFS
    for slotIdx = 6, 7 do
        local slotRec = HP_BAR_SLOTS[slotIdx]
        local key = T[slotIdx - 5]
        local fontStr = key and self[key]
        if fontStr then
            local textOffX = (p and p[slotRec.xKey]) or 0
            local textOffY = (p and p[slotRec.yKey]) or 0
            if key == "name" and slotIdx == 6 and self._nameRaidMarkerShown then
                textOffX = textOffX
                    + ((p and p.nameRaidMarkerSize) or defaultSet.nameRaidMarkerSize or 14)
                    + 3
            end
            self:PlaceSlotText(fontStr, slotRec, textOffX, textOffY)
        end
    end
end
-- Target of Target text: its own font string, built the first time a slot
-- shows it.
function NameplateFrame:EnsureToTText()
    local fontStr = self.totText
    if not fontStr then
        fontStr = self.healthTextFrame:CreateFontString(nil, "OVERLAY")
        SetFSFont(fontStr, 10, GetNPOutline())
        fontStr:Hide()
        self.totText = fontStr
    end
    return fontStr
end
-- The unit's target's name, repainted through RefreshTargetTexts below while a slot
-- shows it. Name and class token may be secret: they only reach setters.
-- The slot's Class text mode paints a player target in its class colour; anything
-- else keeps the slot colour.
function NameplateFrame:UpdateToT()
    local fontStr, unitToken, slotKey = self.totText, self.unit, mod._npToTSlot
    if not (fontStr and unitToken and slotKey) then return end
    local tu = mod._npToTUnits[unitToken]
    if not tu then
        tu = unitToken .. "target"
        mod._npToTUnits[unitToken] = tu
    end
    -- No target: a space, so the text keeps its line (top auras and the range
    -- text anchor to it).
    if not UnitExists(tu) then
        fontStr:SetText(" ")
        return
    end
    -- WoW Forever joins the surname; then the slot's Name Format.
    local name = mod.NP_FormatName(CludesUI.WithSurname(UnitName(tu)), slotKey, tu)
    fontStr:SetText(name)
    if not mod._npToTClass then return end
    local plateUnit
    if UnitIsPlayer(tu) then plateUnit = UnitClassBase(tu) end
    if type(plateUnit) ~= "nil" then
        if issecretvalue(plateUnit) then
            -- Same order as the slot painter: the restricted-unit palette, then Blizzard's.
            local success, red, green, blue = CludesUI.GetClassColorForRestrictedUnit(tu, plateUnit)
            if success then
                fontStr:SetTextColor(red, green, blue, 1)
                return
            end
            local color = C_ClassColor.GetClassColor(plateUnit)
            if color then
                fontStr:SetTextColor(color:GetRGB())
                return
            end
        else
            local color = CludesUI.GetClassColor(plateUnit)
            if color then
                fontStr:SetTextColor(color.r, color.g, color.b, 1)
                return
            end
        end
    end
    local color = (p and p[mod._npToTColorKey]) or defaultSet[mod._npToTColorKey]
    if color then
        fontStr:SetTextColor(color.r, color.g, color.b, 1)
    else
        fontStr:SetTextColor(1, 1, 1, 1)
    end
end
function NameplateFrame:UNIT_TARGET() self:RefreshTargetTexts(true) end
-- Target of Target and the [target] custom texts. UNIT_TARGET does not arrive for
-- every nameplate unit (seen in game) and in restricted combat the target cannot be
-- compared, so threat list updates, casts and the health tick repaint them too, while
-- a slot shows one. force (UNIT_TARGET) repaints now; the rest at most every 0.2 s per
-- plate, counted from any repaint. A call inside that window marks the plate, and one
-- shared flusher repaints it once the window is over (shown only while a mark waits),
-- so the last change is never dropped. what: the custom entries to repaint (default
-- "tgt"; "tgtOnly" from the health tick, whose own paint wrote the rest).
mod._npTgtDirty = mod._npTgtDirty or {}
mod._npTgtFlush = mod._npTgtFlush or CreateFrame("Frame")
mod._npTgtFlush:Hide()
mod._npTgtFlush:SetScript("OnUpdate", function(self)
    local nowTime, dirty = GetTime(), mod._npTgtDirty
    for backing, what in pairs(dirty) do
        if nowTime - (backing._tgtT or 0) >= 0.2 then
            dirty[backing] = nil
            backing:RefreshTargetTexts(true, what)
        end
    end
    if next(dirty) == nil then self:Hide() end
end)
function NameplateFrame:RefreshTargetTexts(force, what)
    if not self.unit then return end
    local nowTime = GetTime()
    if not force and nowTime - (self._tgtT or 0) < 0.2 then
        local dirty = mod._npTgtDirty
        local current = dirty[self]
        if current ~= "tgt" then dirty[self] = what or "tgt" end
        -- A new mark wakes the flusher; it stays shown while any mark waits.
        if not current then mod._npTgtFlush:Show() end
        return
    end
    self._tgtT = nowTime
    mod._npTgtDirty[self] = nil
    self:UpdateToT()
    self:PaintCustomTexts(what or "tgt")
end
-- Target of Target for the plate's (new) unit: UNIT_TARGET follows the token
-- while a slot shows it or a custom text reads [target], and the text repaints.
-- Plate acquire and both occupant-swap paths come here.
function NameplateFrame:SyncToT(unitToken)
    if mod._npTgtTexts then
        if self._totEv ~= unitToken then
            self:RegisterUnitEvent("UNIT_TARGET", unitToken)
            self._totEv = unitToken
        end
        self:UpdateToT()
    elseif self._totEv then
        self:UnregisterEvent("UNIT_TARGET")
        self._totEv = nil
    end
end

-- Custom text in one slot (slot: its HP_BAR_SLOTS entry, nil for Top): its own font
-- string, placed and coloured like the slot's other texts, plus an entry in the
-- plate's custom list (ca._cu) for PaintCustomTexts.
function NameplateFrame:AddCustomText(cachedSlots, slotKey, slotRec)
    local fsKey = mod.NP_CustomFSKey[slotKey]
    local fontStr = self[fsKey]
    if not fontStr then
        fontStr = self.healthTextFrame:CreateFontString(nil, "OVERLAY")
        self[fsKey] = fontStr
    end
    local c = mod.NP_CustomCompiled(slotKey)
    local textOffX, textOffY = GetTextSlotOffsets(slotKey)
    local sr, sg, scrollBar = GetTextSlotColor(slotKey)
    fontStr:SetParent(mod.SlotTextHost(self, slotKey, (p and p[slotKey .. "Strata"]) or "MEDIUM"))
    SetFSFont(fontStr, GetTextSlotSize(slotKey), GetNPOutline())
    if slotRec then
        self:PlaceSlotText(fontStr, slotRec, textOffX, textOffY)
        fontStr:SetJustifyH(slotRec.justify or slotRec.anchor)
    else
        fontStr:ClearAllPoints()
        Pix.Point(
            fontStr,
            "BOTTOM",
            self.health,
            "TOP",
            textOffX,
            4 + GetNameYOffset() + GetClassPowerTopPush(self) + textOffY
        )
        fontStr:SetJustifyH("CENTER")
    end
    fontStr:SetTextColor(sr, sg, scrollBar, 1)
    -- Width: the corner slots never truncate. A text naming the unit ends where the
    -- name would (the bar left by the other bar texts, or on Top the room the name
    -- has there, kept current by UpdateNameWidth), scaled by Width %; any other text
    -- is boxed only below 100% (the health loop).
    local corner = slotRec and slotRec.corner
    local wid = 0
    if not slotRec then self._cuTopName = (c and c.has.name) and true or nil end
    if not corner then
        local wpct = (p and p[slotKey .. "WidthPct"]) or 100
        if c and c.has.name then
            wid = math.max(
                (slotRec and mod.NP_BarRestWidth(slotKey) or mod.NP_TopNameWidth(self, GetHealthBarWidth()))
                    * wpct
                    / 100,
                20
            )
        elseif wpct < 100 then
            wid = GetHealthBarWidth() * wpct / 100
        end
    end
    fontStr:SetWidth(wid)
    local wrap = (not corner and p and p[slotKey .. "Wrap"]) and true or false
    fontStr:SetWordWrap(wrap)
    fontStr:SetMaxLines(wrap and 2 or 1)
    if wid > 0 then mod.ReflowFontString(fontStr) end
    fontStr:Show()
    if not c then
        fontStr:SetText("")
        return
    end
    local cu = cachedSlots._cu
    if not cu then
        cu = {}
        cachedSlots._cu = cu
    end
    local num = cachedSlots._cuN + 1
    local e = cu[num]
    if not e then
        e = {}
        cu[num] = e
    end
    e.fs, e.slot, e.c = fontStr, slotKey, c
    e.tick = (c.reads.hp or c.reads.abs) and true or false
    e.tgt = c.reads.tgt and true or false
    -- The health tick's target refresh skips what its own tick paint just wrote.
    e.tgtOnly = e.tgt and not e.tick
    cachedSlots._cuN = num
    if e.tick then cachedSlots._cuTick = true end
end
-- Repaints the plate's custom texts: all of them (what nil), or those whose entry
-- flag what is set ("tick": reads health or absorbs; "tgt": reads [target];
-- "tgtOnly": reads [target] but not health or absorbs).
function NameplateFrame:PaintCustomTexts(what)
    local cachedSlots, unitToken = self._cachedHealthSlots, self.unit
    if not (cachedSlots and unitToken) then return end
    local cu = cachedSlots._cu
    for index = 1, cachedSlots._cuN or 0 do
        local e = cu[index]
        if not what or e[what] then mod.NP_PaintCustom(e.fs, e.c, unitToken, e.slot) end
    end
end

function NameplateFrame:ApplyHealthTextAppearance()
    self.hpText:Hide()
    self.hpNumber:Hide()
    if self.levelText then self.levelText:Hide() end
    if self.totText then self.totText:Hide() end
    for index = 1, #mod.textSlotKeys do
        local fontStr = self[mod.NP_CustomFSKey[mod.textSlotKeys[index]]]
        if fontStr then fontStr:Hide() end
    end
    -- Slot assignments may change element kinds: drop the value memo so the
    -- next UpdateHealthValues rewrites every slot's content.
    self._hpTxtPct, self._hpTxtCur, self._hpTxtMax = nil, nil, nil
    if not self._cachedHealthSlots then self._cachedHealthSlots = { _count = 0 } end
    local cachedSlots = self._cachedHealthSlots
    -- Slot kinds may change: re-derive the lazily-computed number/combo flag.
    cachedSlots._anyNum = nil
    cachedSlots._cuN, cachedSlots._cuTick = 0, false
    self._cuTopName = nil
    local castIndex = 0

    for slotIdx = 1, #HP_BAR_SLOTS do
        local slotRec = HP_BAR_SLOTS[slotIdx]
        local part = GetTextSlot(slotRec.key)
        local textOffX, textOffY = GetTextSlotOffsets(slotRec.key)
        local slotFontSz = GetTextSlotSize(slotRec.key)
        local sr, sg, scrollBar = GetTextSlotColor(slotRec.key)
        local slotStrata = (p and p[slotRec.key .. "Strata"]) or "MEDIUM"
        if part == "healthPercent" or part == "healthPercentNoSign" then
            local fontStr = self.hpText
            fontStr:SetParent(mod.SlotTextHost(self, slotRec.key, slotStrata))
            SetFSFont(fontStr, slotFontSz, GetNPOutline())
            self:PlaceSlotText(fontStr, slotRec, textOffX, textOffY)
            fontStr:SetJustifyH(slotRec.justify or slotRec.anchor)
            fontStr:SetTextColor(sr, sg, scrollBar, 1)
            fontStr:Show()
            castIndex = castIndex + 1
            if not cachedSlots[castIndex] then cachedSlots[castIndex] = {} end
            cachedSlots[castIndex].element = part
            cachedSlots[castIndex].fs = fontStr
            cachedSlots[castIndex].slotKey = slotRec.key
            cachedSlots[castIndex].corner = slotRec.corner or false
        elseif part == "healthNumber" then
            local fontStr = self.hpNumber
            fontStr:SetParent(mod.SlotTextHost(self, slotRec.key, slotStrata))
            SetFSFont(fontStr, slotFontSz, GetNPOutline())
            self:PlaceSlotText(fontStr, slotRec, textOffX, textOffY)
            fontStr:SetJustifyH(slotRec.justify or slotRec.anchor)
            fontStr:SetTextColor(sr, sg, scrollBar, 1)
            fontStr:Show()
            castIndex = castIndex + 1
            if not cachedSlots[castIndex] then cachedSlots[castIndex] = {} end
            cachedSlots[castIndex].element = part
            cachedSlots[castIndex].fs = fontStr
            cachedSlots[castIndex].slotKey = slotRec.key
            cachedSlots[castIndex].corner = slotRec.corner or false
        elseif IsComboHealthText(part) then
            local fontStr = self.hpText
            fontStr:SetParent(mod.SlotTextHost(self, slotRec.key, slotStrata))
            SetFSFont(fontStr, slotFontSz, GetNPOutline())
            self:PlaceSlotText(fontStr, slotRec, textOffX, textOffY)
            fontStr:SetJustifyH(slotRec.justify or slotRec.anchor)
            fontStr:SetTextColor(sr, sg, scrollBar, 1)
            fontStr:Show()
            castIndex = castIndex + 1
            if not cachedSlots[castIndex] then cachedSlots[castIndex] = {} end
            cachedSlots[castIndex].element = part
            cachedSlots[castIndex].fs = fontStr
            cachedSlots[castIndex].slotKey = slotRec.key
            cachedSlots[castIndex].corner = slotRec.corner or false
        elseif part == "level" or part == "targetOfTarget" then
            -- Standalone level / Target of Target: own FontString, NOT in the health slot
            -- cache (level content is static per unit -- written here and by UpdateName on
            -- acquire; Target of Target repaints through RefreshTargetTexts).
            -- Width/wrap applied inline since the cache loop below skips it.
            local isLevel = part == "level"
            local fontStr = isLevel and self.levelText or self:EnsureToTText()
            fontStr:SetParent(mod.SlotTextHost(self, slotRec.key, slotStrata))
            SetFSFont(fontStr, slotFontSz, GetNPOutline())
            self:PlaceSlotText(fontStr, slotRec, textOffX, textOffY)
            fontStr:SetJustifyH(slotRec.justify or slotRec.anchor)
            fontStr:SetTextColor(sr, sg, scrollBar, 1)
            if isLevel and self.unit then fontStr:SetText(mod.GetUnitLevelText(self.unit)) end
            -- The corner slots never truncate: no Width % or Wrap there.
            local lwpct = (not slotRec.corner and p and p[slotRec.key .. "WidthPct"]) or 100
            fontStr:SetWidth(lwpct < 100 and (GetHealthBarWidth() * lwpct / 100) or 0)
            local lwrap = (not slotRec.corner and p and p[slotRec.key .. "Wrap"]) and true or false
            fontStr:SetWordWrap(lwrap)
            fontStr:SetMaxLines(lwrap and 2 or 1)
            fontStr:Show()
        elseif part == "custom" then
            self:AddCustomText(cachedSlots, slotRec.key, slotRec)
        end
    end

    -- Top slot health text
    local topPart = GetTextSlot("textSlotTop")
    if
        topPart == "healthPercent"
        or topPart == "healthPercentNoSign"
        or topPart == "healthNumber"
        or IsComboHealthText(topPart)
    then
        local nameYOff = GetNameYOffset()
        local cpPush = GetClassPowerTopPush(self)
        local textOffX, textOffY = GetTextSlotOffsets("textSlotTop")
        local topFontSz = GetTextSlotSize("textSlotTop")
        local tr, tg, tb = GetTextSlotColor("textSlotTop")
        local fontStr
        if topPart == "healthNumber" then
            fontStr = self.hpNumber
        else
            fontStr = self.hpText
        end
        SetFSFont(fontStr, topFontSz, GetNPOutline())
        fontStr:SetParent(mod.SlotTextHost(self, "textSlotTop", (p and p.textSlotTopStrata) or "MEDIUM"))
        fontStr:ClearAllPoints()
        Pix.Point(fontStr, "BOTTOM", self.health, "TOP", textOffX, 4 + nameYOff + cpPush + textOffY)
        fontStr:SetJustifyH("CENTER")
        fontStr:SetTextColor(tr, tg, tb, 1)
        fontStr:Show()
        castIndex = castIndex + 1
        if not cachedSlots[castIndex] then cachedSlots[castIndex] = {} end
        cachedSlots[castIndex].element = topPart
        cachedSlots[castIndex].fs = fontStr
        cachedSlots[castIndex].slotKey = "textSlotTop"
        cachedSlots[castIndex].corner = false
    elseif topPart == "level" or topPart == "targetOfTarget" then
        -- Standalone level / Target of Target in the top slot: same shape as the
        -- health block above, on its own font string, no cache entry.
        local nameYOff = GetNameYOffset()
        local cpPush = GetClassPowerTopPush(self)
        local textOffX, textOffY = GetTextSlotOffsets("textSlotTop")
        local topFontSz = GetTextSlotSize("textSlotTop")
        local tr, tg, tb = GetTextSlotColor("textSlotTop")
        local isLevel = topPart == "level"
        local fontStr = isLevel and self.levelText or self:EnsureToTText()
        SetFSFont(fontStr, topFontSz, GetNPOutline())
        fontStr:SetParent(mod.SlotTextHost(self, "textSlotTop", (p and p.textSlotTopStrata) or "MEDIUM"))
        fontStr:ClearAllPoints()
        Pix.Point(fontStr, "BOTTOM", self.health, "TOP", textOffX, 4 + nameYOff + cpPush + textOffY)
        fontStr:SetJustifyH("CENTER")
        fontStr:SetTextColor(tr, tg, tb, 1)
        if isLevel and self.unit then fontStr:SetText(mod.GetUnitLevelText(self.unit)) end
        local lwpct = (p and p.textSlotTopWidthPct) or 100
        fontStr:SetWidth(lwpct < 100 and (GetHealthBarWidth() * lwpct / 100) or 0)
        local lwrap = (p and p.textSlotTopWrap) and true or false
        fontStr:SetWordWrap(lwrap)
        fontStr:SetMaxLines(lwrap and 2 or 1)
        fontStr:Show()
    elseif topPart == "custom" then
        self:AddCustomText(cachedSlots, "textSlotTop")
    end
    cachedSlots._count = castIndex
    -- Per-slot health % decimal preference, resolved in this rare appearance pass and cached
    -- per entry + an _anyDecimal flag, so the per-tick render in UpdateHealthValues stays lean.
    local barW = GetHealthBarWidth()
    local anyDec = false
    for index = 1, castIndex do
        local e = cachedSlots[index]
        local el = e.element
        if el == "healthPercent" or el == "healthPercentNoSign" or IsComboHealthText(el) then
            local dec = (p and e.slotKey and p[e.slotKey .. "PctDecimal"]) and true or false
            e.pctDecimal = dec
            if dec then anyDec = true end
        else
            e.pctDecimal = false
        end
        -- Per-slot Width % of the health bar + Wrap. SetWidth/SetWordWrap re-flow the
        -- FontString themselves (only SetJustifyH needs ReflowFontString), and
        -- UpdateHealthValues re-sets text on the same SetUnit pass, so no reflow here. Default
        -- 100 = unconstrained (SetWidth 0 = auto-size): a width box on a single-point-anchored
        -- FontString ignores SetJustifyH and would re-centre a right/left value, so only box
        -- it when narrowed.
        -- The corner slots never truncate: no Width % or Wrap there.
        local wpct = (not e.corner and p and e.slotKey and p[e.slotKey .. "WidthPct"]) or 100
        e.fs:SetWidth(wpct < 100 and (barW * wpct / 100) or 0)
        local wrap = false
        if not e.corner and p and e.slotKey and p[e.slotKey .. "Wrap"] ~= nil then
            wrap = p[e.slotKey .. "Wrap"]
        end
        e.fs:SetWordWrap(wrap)
        e.fs:SetMaxLines(wrap and 2 or 1)
    end
    cachedSlots._anyDecimal = anyDec
    self:PaintCustomTexts()
end

function NameplateFrame:SetUnit(unitToken, plateFrame)
    self.unit = unitToken
    self.nameplate = plateFrame
    self:SetParent(plateFrame)
    self:ClearAllPoints()
    self:SetPoint("CENTER", plateFrame, "CENTER", 0, GetHitboxYShift())
    self:SetFrameLevel(plateFrame:GetFrameLevel() + 1)
    self:Show()
    -- Recycled/fresh plate: forget any prior eased scale so the first ApplyScale snaps instead of growing in from a stale one.
    self._curScale = nil
    mod._scaleAnim[self] = nil
    if mod._hitboxOverlayShown or self.hitboxOverlay then mod._ApplyHitboxOverlay(self) end
    -- Apply static appearance only when stale (settings changed or fresh pool plate).
    if self._appearanceGen ~= mod._npAppearanceGen then
        self:ApplyAppearance()
        self._appearanceGen = mod._npAppearanceGen
    end
    HideBlizzardFrame(plateFrame, unitToken)
    self:RegisterUnitEvent("UNIT_HEALTH", unitToken)
    self:RegisterUnitEvent("UNIT_MAXHEALTH", unitToken)
    self:RegisterUnitEvent("UNIT_ABSORB_AMOUNT_CHANGED", unitToken)
    self:RegisterUnitEvent("UNIT_NAME_UPDATE", unitToken)
    -- Elite/rare badge: Blizzard's own plates repaint it on this event.
    self:RegisterUnitEvent("UNIT_CLASSIFICATION_CHANGED", unitToken)
    self:RegisterUnitEvent("UNIT_THREAT_LIST_UPDATE", unitToken)
    -- Target of Target text: its event only while a slot shows it.
    self:SyncToT(unitToken)
    -- Attach a pooled aura-container bundle for this unit.
    if mod.NPC_AttachPlate then mod.NPC_AttachPlate(self, unitToken) end
    if mod.DebuffColors_Attach then mod.DebuffColors_Attach(self, unitToken) end
    -- Non-Target and Out of Combat Opacity (zero cost while off: numeric compares).
    if mod._oocAlpha < 1 then self:RegisterUnitEvent("UNIT_FLAGS", unitToken) end
    if mod._ntAlpha < 1 or mod._oocAlpha < 1 then mod.NT_Apply(self) end
    -- Minor / Non-Elite Enemy Scale: the type base for the spawn pass's ApplyScale.
    if mod._typeScaleOn then self:UpdateTypeScale() end
    -- Execute glow is per-spawn state, not appearance: ApplyAppearance is generation-cached
    -- (skipped on recycled plates) and the threshold watcher only reaches plates active at flip
    -- time, so a plate pooled during a no-execute window would return glowless. Re-assert.
    mod.ApplyLowHpGlow(self)
    -- Critical: health bar must display immediately
    self:UpdateHealth()
    -- PERF: defer non-critical work 1 frame. Stacking bounds, name, cast bar, classification,
    -- raid icon, target glow, mouseover -- all imperceptible 1 frame late. Cuts ~40% off spike.
    self._castDirtyFull = true
    if not self._deferredSetupCB then
        self._deferredSetupCB = function()
            if not self.unit then return end
            local plateRef = self.nameplate
            -- Stacking bounds
            if plateRef and plateRef.SetStackingBoundsFrame then
                if not self._stackBounds then
                    self._stackBounds = CreateFrame("Frame", nil, plateRef)
                    -- Load-bearing: SetStackingBoundsFrame reads this frame's rendered bounds
                    -- (union of its regions), NOT its SetSize. Without a full-size region the
                    -- bounds rect is empty and plates stop stacking. Alpha 0 so it never shows.
                    local texture = self._stackBounds:CreateTexture(nil, "BACKGROUND")
                    texture:SetColorTexture(1, 0, 0, 0)
                    texture:SetAllPoints(self._stackBounds)
                end
                self._stackBounds:SetParent(plateRef)
                self._stackBounds:ClearAllPoints()
                local barH = GetHealthBarHeight()
                local castH2 = GetCastBarHeight()
                local nameGap = 4 + GetEnemyNameTextSize()
                local totalH = nameGap + barH + castH2
                local scale = GetStackSpacingScale() / 100
                self._stackBounds:SetPoint("CENTER", plateRef, "CENTER", 0, GetNameplateYOffset())
                self._stackBounds:SetSize(GetHealthBarWidth(), totalH * scale)
                self._stackBounds:Show()
                plateRef:SetStackingBoundsFrame(self._stackBounds)
            end
            -- Focus cast height override
            if UnitIsUnit(self.unit, "focus") then
                local pct = GetFocusCastHeight()
                if pct ~= 100 then
                    local castH = math.floor(GetCastBarHeight() * pct / 100 + 0.5)
                    mod.LayoutCastBar(self, mod.GetHealthBarWidth(), castH)
                    mod.LayoutCastIcon(self, castH)
                    mod.NP_SetSparkHeight(self, castH)
                    self.kickMarker:SetSize(GetHealthBarWidth(), castH)
                end
            end
            -- Cast target color
            local useClassColor = defaultSet.castTargetClassColor
            if p and p.castTargetClassColor ~= nil then useClassColor = p.castTargetClassColor end
            if useClassColor then
                local appliedCTC = false
                local classToken
                if UnitSpellTargetClass then classToken = UnitSpellTargetClass(self.unit) end
                -- classToken may be SECRET: type() is the safe nil check
                if type(classToken) == "nil" then
                    local target = self.unit .. "target"
                    if UnitIsPlayer(target) then classToken = UnitClassBase(target) end
                end
                if type(classToken) ~= "nil" and C_ClassColor then
                    local color = C_ClassColor.GetClassColor(classToken)
                    if color then
                        self.castTarget:SetTextColor(color:GetRGB())
                        appliedCTC = true
                    end
                end
                if not appliedCTC then self.castTarget:SetTextColor(1, 1, 1, 1) end
            else
                local ctc = (p and p.castTargetColor) or defaultSet.castTargetColor
                self.castTarget:SetTextColor(ctc.r, ctc.g, ctc.b, 1)
            end
            self:UpdateName()
            self:UpdateClassification()
            if not (p and p.classificationIncludeFaction) then self:UpdateFaction() end
            self:UpdateRaidIcon()
            if p and p.nameRaidMarkerEnabled == true then self:RefreshNamePosition(true) end
            self:ApplyTarget()
            self:ApplyMouseover()
            self:UpdateCast()
        end
    end
    C_Timer.After(0, self._deferredSetupCB)
end
function NameplateFrame:ClearUnit()
    self:UnregisterAllEvents()
    self._factionEv = nil
    self._totEv = nil
    self._tgtT = nil
    mod._npTgtDirty[self] = nil

    -- Classic WoW UI: blank the level in the border's plate. Plates are
    -- pooled, so a recycled one would otherwise carry the last unit's level
    -- until its first paint.
    if self._classicLevel then
        self._classicLevel:SetText("")
        if self._classicSkull then self._classicSkull:Hide() end
    end
    -- WoW Forever: the level box waits for the next unit's level.
    if self._fvLevelBox then self._fvLevelBox:Hide() end

    -- Color Casting Enemies: the next unit starts with no casts seen.
    if self._castSeen ~= nil then mod.NP_ResetCastKind(self) end

    if self.isCasting then
        self.isCasting = false
        if self._castFallback then
            self._castFallback = nil
            _fallbackPlates[self] = nil
            Inner.fallbackCastCount = Inner.fallbackCastCount - 1
            if Inner.fallbackCastCount <= 0 then
                Inner.fallbackCastCount = 0
                castFallback:Hide()
            end
        end
        NotifyCastEnded(self)
    end

    -- Non-Target Opacity: released pool frames always go back at full alpha (nil
    -- _ntCurAlpha = never faded, keeps this a no-op). After the cast end above, which
    -- reapplies opacity for Full Opacity While Casting.
    if self._ntCurAlpha and self._ntCurAlpha < 1 then self:SetAlpha(1) end
    self._ntCurAlpha = nil
    self._oorCurAlpha = nil

    self.name:SetText("")
    -- The Custom texts too: a recycled plate never shows the last unit's for a frame.
    local cachedSlots = self._cachedHealthSlots
    local cu = cachedSlots and cachedSlots._cu
    if cu then
        for index = 1, cachedSlots._cuN or 0 do
            cu[index].fs:SetText("")
        end
    end
    -- Release this plate's aura-container bundle back to the pool.
    if mod.NPC_DetachPlate then mod.NPC_DetachPlate(self) end
    if mod.DebuffColors_Detach then mod.DebuffColors_Detach(self) end
    self.unit = nil
    self.nameplate = nil
    self._absorbHidden = nil
    self._maxHPValid = nil
    self._lastHCr, self._lastHCg, self._lastHCb = nil, nil, nil
    -- Threat Colors border/text channels: drop the skip-if-unchanged caches so a recycled
    -- plate always repaints for its new unit. _threatBdOn / _threatNameOn are deliberately
    -- LEFT set -- they record that the border and name still carry a threat tint, and the
    -- next UpdateHealthColor uses that to hand them back if the new unit has no signal.
    self._threatBdKr, self._threatBdKg, self._threatBdKb = nil, nil, nil
    self._nameThR, self._nameThG, self._nameThB = nil, nil, nil
    -- Hostility / Class slot colours: the next occupant's class token is read afresh.
    self._scUnit = nil
    -- Health-text value memo (UpdateHealthValues): a recycled plate must
    -- always write its first values, never skip against the old unit's.
    self._hpTxtPct, self._hpTxtCur, self._hpTxtMax = nil, nil, nil
    self._ovFocShown, self._ovTgtShown = nil, nil
    self._focusLetterShown = nil
    if self._tptShown then self.threatPctText:Hide() end
    self._tptShown = nil
    self._kickIsChannel = nil
    self._castIsChannel = nil
    self._kickIsEmpowered = nil
    self._kickGeoDirty = nil
    self._castTex = nil
    self._castLockout = nil
    self._nameRaidMarkerShown = nil
    -- A recycled frame's first health paint must not treat the new occupant as
    -- the old target (the hash line reads this flag).
    self._isTarget = nil
    self.cast:Hide()
    self.castShieldFrame:Hide()
    self.castShieldFrame:SetAlpha(1)
    self.castBarOverlay:SetAlpha(0)
    self.isCasting = false
    self._castFallback = nil
    _fallbackPlates[self] = nil
    self._kickProtected = nil
    self._castImportant = false
    self:HideKickTick()
    -- Both glows: also after an interrupt or fallback end, which leave isCasting false
    -- with the glow still up. Each checks its own active flag.
    self:ClearImportantCastGlow()
    self:ClearCastTargetGlow()
    if self._interruptTimer then
        self._interruptTimer:Cancel()
        self._interruptTimer = nil
    end
    self._interrupted = nil
    if self.glow then self.glow:Hide() end
    if self.targetHighlight then self.targetHighlight:Hide() end
    mod.HideHoverEffect(self)
    if self.nameRaidFrame then self.nameRaidFrame:Hide() end
    self.raidFrame:Hide()
    self.classFrame:Hide()
    if self.factionFrame then self.factionFrame:Hide() end
    if self.questTextFrame then self.questTextFrame:Hide() end
    if self.questTextTypeIcon then self.questTextTypeIcon:Hide() end
    if self.focusLetter then self.focusLetter:Hide() end
    if self.leftArrow then self.leftArrow:Hide() end
    if self.rightArrow then self.rightArrow:Hide() end
    HideClassPowerOnPlate(self)
    self._absCurClip:Hide()
    self._absMissClip:Hide()
    self:Hide()
    self:SetScale(1)
    self._curScale = nil
    mod._scaleAnim[self] = nil
    self:SetParent(UIParent)
    self:ClearAllPoints()
    -- Detach stacking bounds from the old nameplate so it doesn't
    -- confuse the stacking engine when the nameplate is recycled.
    if self._stackBounds then
        self._stackBounds:ClearAllPoints()
        self._stackBounds:SetParent(self)
        self._stackBounds:Hide()
    end
end

Inner._fallbackPlates, Inner.castFallbackFrame = _fallbackPlates, castFallback
Inner.NameplateFrame = NameplateFrame
Inner.SetRawSetTex = function(frame) RawSetTex = frame end
Inner.broken = false
