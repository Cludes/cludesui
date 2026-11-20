if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_Nameplates_Name.lua
--
--  NameplateFrame: name, classification, Quest Objective Text, faction, raid
--  icon, target and hover extras.
--  Reads the earlier nameplate files through ns and ns._npInternals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._npInternals
-- CludesUINameplates.lua or an earlier nameplate file failed to load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local ipairs, type = ipairs, type
local Pix = CludesUI.PP
local UnitName = UnitName
local UnitIsUnit = UnitIsUnit
local UnitClassification = UnitClassification
local GetRaidTargetIndex, SetRaidTargetIconTexture = GetRaidTargetIndex, SetRaidTargetIconTexture

local defaultSet, GetNPOutline, HP_BAR_SLOTS = Inner.defaults, Inner.GetNPOutline, Inner.HP_BAR_SLOTS
local SetFSFont, EstimateHealthTextWidth = Inner.SetFSFont, Inner.EstimateHealthTextWidth
local GetAuraSlotOffsets, GetClassificationSlot = Inner.GetAuraSlotOffsets, Inner.GetClassificationSlot
local GetDebuffYOffset, GetHealthBarWidth = Inner.GetDebuffYOffset, Inner.GetHealthBarWidth
local GetHideEnemyNameWhileCasting = Inner.GetHideEnemyNameWhileCasting
local GetNameYOffset, GetRaidMarkerPos = Inner.GetNameYOffset, Inner.GetRaidMarkerPos
local GetRaidMarkerSize, GetRareEliteIconSize = Inner.GetRaidMarkerSize, Inner.GetRareEliteIconSize
local GetShowCastIcon, GetShowClassPower = Inner.GetShowCastIcon, Inner.GetShowClassPower
local GetSideAuraXOffset, GetSlotOffsets = Inner.GetSideAuraXOffset, Inner.GetSlotOffsets
local GetTextSlot, GetTextSlotOffsets = Inner.GetTextSlot, Inner.GetTextSlotOffsets
local GetTextSlotSize, IsBorderEnabled = Inner.GetTextSlotSize, Inner.IsBorderEnabled
local PositionArrowsOutsideAuras, EnsureArrows = Inner.PositionArrowsOutsideAuras, Inner.EnsureArrows
local EnsureGlow, EnsureTargetHighlight = Inner.EnsureGlow, Inner.EnsureTargetHighlight
local EnsureClassPowerPips = Inner.EnsureClassPowerPips
local GetClassPowerTopPush = Inner.GetClassPowerTopPush
local HideClassPowerOnPlate = Inner.HideClassPowerOnPlate
local UpdateClassPowerOnPlate, NameplateFrame = Inner.UpdateClassPowerOnPlate, Inner.NameplateFrame

local classPowerType
Inner.classPowerTypeSetters[#Inner.classPowerTypeSetters + 1] = function(val)
    classPowerType = val
end
local p
Inner.profileSetters[#Inner.profileSetters + 1] = function(val)
    p = val
end

function NameplateFrame:UpdateName()
    local unitToken = self.unit
    if not unitToken then
        return
    end
    if self.nameplate then
        local actualUnit = self.nameplate.namePlateUnitToken
        if actualUnit and actualUnit ~= unitToken then
            self.unit = actualUnit
            unitToken = actualUnit
            -- Occupant changed: nil the absorb lean-gate flag so the next health
            -- paint takes the full absorb path for the new unit; the cached max
            -- belongs to the old unit, drop it too.
            self._absorbHidden = nil
            -- Color Casting Enemies remembers the mob, not the plate.
            if self._castSeen ~= nil then
                mod.NP_ResetCastKind(self)
            end
            -- Repaint target/hover styling for the new occupant so the old one's
            -- paint cannot stick; mirrors the UpdateHealthValues swap.
            -- ApplyTarget re-owns the shared target-plate cache as a side effect.
            -- The new occupant's type scale first: ApplyTarget ends in ApplyScale.
            if mod._typeScaleOn then
                self:UpdateTypeScale()
            end
            mod.ClearHoverExtras(self)
            self:ApplyTarget()
            self._maxHPValid = nil
            if mod._npTgtTexts or self._totEv then
                self:SyncToT(actualUnit)
            end
        end
    end
    -- Standalone level renders on its own FontString and can share the plate with a
    -- name-family slot. Refreshed here (plate acquire/unit swap) so pooled reuse never stales.
    -- Plain text: its colour is the slot's Text Coloring mode (font string colour).
    if self.levelText and self.levelText:IsShown() then
        self.levelText:SetText(mod.GetUnitLevelText(unitToken))
    end
    -- Classic WoW UI: the level in the vanilla border's plate.
    if self._classicLevel then
        mod.NP_UpdateClassicLevel(self)
    end
    -- WoW Forever: the level in the box right of the bar.
    if self._fvLevelBox then
        mod.NP_UpdateForeverLevel(self)
    end
    -- The slotted name-family variant decides what renders: name or a level+name
    -- combo (in the slot's materialized part colours). A nil slot keeps the plain-name
    -- write (RefreshNamePosition hides it).
    local slotRec = mod.FindNameSlot()
    local el = slotRec and GetTextSlot(slotRec) or "enemyName"
    local name = CludesUI.WithSurname(UnitName(unitToken))
    if type(name) == "string" then
        name = mod.NP_FormatName(name, slotRec, unitToken) -- the slot's Name Format
        mod.SetNameElementText(self.name, el, name, unitToken, slotRec)
        -- Debuff coloring's Color Name copies follow the text (RefreshNamePosition
        -- passes it on too).
        if p and p.nameRaidMarkerEnabled == true then
            self:RefreshNamePosition(true)
        elseif mod.DebuffColors_NameChanged then
            mod.DebuffColors_NameChanged(self)
        end
    end
    -- Custom texts: name, level and target follow the unit.
    self:PaintCustomTexts()
end
-- Places an icon of a Core Positions slot (the raid marker, the Rare/Quest indicator, the
-- Quest Objective Text, the faction badge; sz: its height) by the slot's own rule: centred
-- above the bar at Top, beside the bar at Left and Right (past the cast icon where the two
-- meet), on the bar's top corners (lift: the raid marker sits on the corner, the indicators
-- 2 up; above the corner's Top Left / Top Right text while it shows one), under the cast bar
-- at Bottom.
-- The Core Positions chain (ns.NP_CoreChain) places the first shown element of a shared
-- slot with it too.
local function PlaceSlotIcon(backing, frame, place, xOff, yOff, lift, size)
    local cpPush = GetClassPowerTopPush(backing)
    frame:ClearAllPoints()
    if place == "top" then
        Pix.Point(frame, "BOTTOM", backing.health, "TOP", xOff, GetDebuffYOffset() + cpPush + yOff)
    elseif place == "left" then
        local iconPush = mod.NP_SideIconPush(backing, "left", yOff, size)
        Pix.Point(frame, "RIGHT", backing.health, "LEFT", -GetSideAuraXOffset() - iconPush + xOff, yOff)
    elseif place == "right" then
        local iconPush = mod.NP_SideIconPush(backing, "right", yOff, size)
        Pix.Point(frame, "LEFT", backing.health, "RIGHT", GetSideAuraXOffset() + iconPush + xOff, yOff)
    elseif place == "topleft" then
        Pix.Point(
            frame,
            "BOTTOMLEFT",
            backing.health,
            "TOPLEFT",
            xOff,
            lift + cpPush + mod.NP_TopCornerLift("topleft") + yOff
        )
    elseif place == "topright" then
        Pix.Point(
            frame,
            "BOTTOMRIGHT",
            backing.health,
            "TOPRIGHT",
            xOff,
            lift + cpPush + mod.NP_TopCornerLift("topright") + yOff
        )
    elseif place == "bottom" then
        -- Below the cast bar, centered (the aura slots' "bottom" convention).
        Pix.Point(frame, "TOP", backing.cast, "BOTTOM", xOff, -2 + yOff)
    end
end
mod.NP_PlaceSlotIcon = PlaceSlotIcon
-- Whether the player is in a dungeon, raid, battleground or arena: there each Core Positions
-- quest and rare element shows only while its own Show In Instances allows it.
local function InInstance()
    local _, iconType = GetInstanceInfo()
    return iconType == "party" or iconType == "raid" or iconType == "pvp" or iconType == "arena"
end
-- The Rare/Quest frame: the Quest Indicator (the quest icon on a quest mob) takes priority
-- over the Elite/Rare Indicator (the elite and rare marks), each half on while its box is
-- checked and, in an instance, its Show In Instances is on. The frame keeps the size it was
-- given in _npSz (each half its own size; the chain and the faction badge read it).
function NameplateFrame:UpdateClassification()
    if not self.unit then
        return
    end
    local slotRec = GetClassificationSlot()
    if slotRec == "none" then
        self.classFrame:Hide()
        self:UpdateNameWidth()
        return
    end
    local inInstance = InInstance()
    -- Elite/Rare Indicator off: no elite or rare marks (the WoW Forever look starts with
    -- it off, NP_SeedForever). Quest Indicator off: no quest scan, a quest mob shows its
    -- elite/rare mark instead.
    local rareOn = not (p and p.classificationHideRare) and (not inInstance or mod.NP_ShowInInstances("rare"))
    local questOn = mod.NP_QuestIconOn() and (not inInstance or mod.NP_ShowInInstances("quest"))
    local size
    if questOn and mod.IsQuestMob(self.unit) then
        self.class:SetAtlas("Crosshair_Quest_64")
        size = mod.NP_ElementSize("quest")
    else
        if not rareOn then
            self.classFrame:Hide()
            self:UpdateNameWidth()
            return
        end
        size = GetRareEliteIconSize()
        local c = UnitClassification(self.unit)
        -- Classic WoW UI carries elite rank in the plate's own art, so the
        -- indicator marks RARITY alone there: a plain elite shows nothing,
        -- and a rare elite takes the rare mark rather than the elite one.
        if mod.NP_Classic() then
            if c == "rare" or c == "rareelite" then
                self.class:SetAtlas("nameplates-icon-rareelite")
            else
                self.classFrame:Hide()
                self:UpdateNameWidth()
                return
            end
        elseif c == "elite" or c == "worldboss" then
            self.class:SetAtlas("nameplates-icon-elite-gold")
        elseif c == "rareelite" then
            self.class:SetAtlas("nameplates-icon-elite-silver")
        elseif c == "rare" then
            self.class:SetAtlas("nameplates-icon-rareelite")
        else
            self.classFrame:Hide()
            self:UpdateNameWidth()
            return
        end
    end
    local cxOff, cyOff = GetAuraSlotOffsets("classification")
    self.classFrame._npSz = size
    Pix.Size(self.classFrame, size, size)
    PlaceSlotIcon(self, self.classFrame, slotRec, cxOff, cyOff, 2, size)
    self.classFrame:Show()
    self:UpdateNameWidth()
end
-- "Rare/Quest + Faction": the faction badge's step-aside depends on whether the
-- classification icon shows, and some passes (quest objective refreshes) redraw only
-- the classification, so re-place the badge after every classification pass. The Quest
-- Objective Text follows every classification pass too (quest refreshes, plate setup).
NameplateFrame._UpdateClassificationBase = NameplateFrame.UpdateClassification
function NameplateFrame:UpdateClassification()
    self:_UpdateClassificationBase()
    if p and p.classificationIncludeFaction then
        self:UpdateFaction()
    end
    local slotRec = GetClassificationSlot()
    -- Its own chain pass is this one's when the two share the slot.
    self:UpdateQuestText(slotRec)
    -- Elements sharing the slot follow the indicator's show, hide and move.
    if mod.NP_CoreChain then
        mod.NP_CoreChain(self, slotRec)
    end
end

-- Quest Objective Text: a Core Positions element of its own (its slot ns.NP_GetQuestTextSlot).
-- On a quest mob it shows the objective's progress (2/6, 40%) as plain verified text; with no
-- readable count it shows the quest icon instead, unless the Quest Indicator is on (one quest
-- icon per plate). Frames: plate.questTextFrame (built on first show, so nothing exists for a
-- player who never turns it on), plate.questText and plate.questTextIcon; the frame is sized
-- to what it shows (_npW x _npSz) and placed like the slot's icons. The text is measured on a
-- font string of the module's own, outside every plate, and only when the text, its size, its
-- font or its outline moved. chainedBy: the slot whose chain pass follows this call.
local QT = {}
local function QuestTextMeasure(textValue, size, font, outline)
    local fontStr = QT.fs
    if not fontStr then
        local owner = CreateFrame("Frame", nil, UIParent)
        owner:Hide()
        fontStr = owner:CreateFontString(nil, "OVERLAY")
        QT.fs = fontStr
    end
    if QT.size ~= size or QT.font ~= font or QT.outline ~= outline then
        SetFSFont(fontStr, size, outline)
        QT.size, QT.font, QT.outline = size, font, outline
    end
    fontStr:SetText(textValue)
    local wid, hgt = fontStr:GetStringWidth(), fontStr:GetStringHeight()
    if not (wid and wid > 0) then
        wid = size * 0.6 * #textValue
    end
    if not (hgt and hgt > 0) then
        hgt = size
    end
    return math.ceil(wid), math.ceil(hgt)
end
local function QuestTextTypeIconHide(self)
    local frame = self.questTextFrame
    local iconTex = self.questTextTypeIcon
    if iconTex and iconTex:IsShown() then
        iconTex:Hide()
    end
    if frame and frame._qtTypeIconOn then
        self.questText:ClearAllPoints()
        self.questText:SetPoint("CENTER", frame, "CENTER", 0, 0)
        frame._qtTypeIconOn = nil
    end
end
-- The objective type icon beside the count: its size follows the text size and Icon Scale, 2 px
-- right of the count. Returns the element's width and height, the count's x offset from the
-- frame's centre, the icon's left edge from the centre and the icon's size. The options
-- preview lays its sample out with the same function.
function mod.NP_QuestTypeIconLayout(counterW, counterH, fontSize, scale)
    local iconSize = math.max(8, math.floor(fontSize * 0.8 * scale / 100 + 0.5))
    local gap = 2
    return counterW + gap + iconSize,
        math.max(counterH, iconSize),
        -((iconSize + gap) / 2),
        (counterW + gap - iconSize) / 2,
        iconSize
end
-- Hides the frame; the name width, the target arrows and the slot's other elements follow.
local function QuestTextHide(self, chainParent)
    if self.questTextTypeIcon then
        QuestTextTypeIconHide(self)
    end
    local frame = self.questTextFrame
    if not (frame and frame:IsShown()) then
        return
    end
    frame:Hide()
    local last = self._qtSlot
    self:UpdateNameWidth()
    if last == "left" or last == "right" then
        PositionArrowsOutsideAuras(self)
    end
    if mod.NP_CoreChain and last and last ~= chainParent then
        mod.NP_CoreChain(self, last)
    end
end
function NameplateFrame:UpdateQuestText(chainParent)
    local slotRec = mod.NP_GetQuestTextSlot()
    local unitToken = self.unit
    if slotRec == "none" or not unitToken then
        QuestTextHide(self, chainParent)
        return
    end
    if (InInstance() and not mod.NP_ShowInInstances("questtext")) or not mod.IsQuestMob(unitToken) then
        QuestTextHide(self, chainParent)
        return
    end
    local textValue = mod.GetQuestObjectiveText(unitToken)
    local iconSz
    if not textValue then
        -- No readable count or percent: the quest icon, unless the Quest Indicator draws it.
        if mod.NP_QuestIconOn() then
            QuestTextHide(self, chainParent)
            return
        end
        iconSz = mod.NP_ElementSize("quest", nil, slotRec)
    end
    local frame = self.questTextFrame
    if not frame then
        -- The faction badge's tier, born in the plate's aspect holder like the other slot
        -- icons (PlatePool, coreHost), so a Core Positions chain can anchor it to an aura row.
        frame = CreateFrame("Frame", nil, self.coreHost or self)
        frame:SetFrameStrata(mod.GetSlotRaiseStrata(slotRec) and "HIGH" or "MEDIUM")
        frame:SetFrameLevel(self.health:GetFrameLevel() + 2)
        frame:Hide()
        local fontStr = frame:CreateFontString(nil, "OVERLAY")
        fontStr:SetPoint("CENTER", frame, "CENTER", 0, 0)
        fontStr:SetJustifyH("CENTER")
        fontStr:SetJustifyV("MIDDLE")
        fontStr:SetWordWrap(false)
        fontStr:SetTextColor(1, 1, 1, 1)
        local iconTex = frame:CreateTexture(nil, "ARTWORK")
        iconTex:SetAllPoints()
        iconTex:SetAtlas("Crosshair_Quest_64")
        iconTex:Hide()
        self.questText, self.questTextIcon, self.questTextFrame = fontStr, iconTex, frame
    end
    local wid, hgt
    if textValue then
        local size, font, outline = mod.NP_QuestTextSize(), mod.GetFont(), GetNPOutline()
        local fontStr = self.questText
        -- Paint and measure only when the text or its font moved (the text is a verified
        -- plain string: SetFormattedText's "%s" is the secret-safe text path all the same).
        if frame._qtText ~= textValue or frame._qtSize ~= size or frame._qtFont ~= font or frame._qtOutline ~= outline then
            SetFSFont(fontStr, size, outline)
            fontStr:SetFormattedText("%s", textValue)
            frame._qtW, frame._qtH = QuestTextMeasure(textValue, size, font, outline)
            frame._qtText, frame._qtSize, frame._qtFont, frame._qtOutline = textValue, size, font, outline
        end
        wid, hgt = frame._qtW, frame._qtH
        if p and p.showQuestObjectiveTypeIcon == true then
            local typeTex = self.questTextTypeIcon
            if not typeTex then
                typeTex = frame:CreateTexture(nil, "ARTWORK")
                typeTex:SetAtlas("Crosshair_Quest_64")
                self.questTextTypeIcon = typeTex
            end
            local objectiveType = mod.GetQuestObjectiveType(unitToken)
            local art = objectiveType == "monster" and "monster"
                or (objectiveType == "item" and "item" or "generic")
            if frame._qtTypeIconArt ~= art then
                if art == "monster" then
                    typeTex:SetTexture("Interface\\Icons\\INV_Sword_04")
                elseif art == "item" then
                    typeTex:SetTexture("Interface\\Icons\\INV_Misc_Bag_08")
                else
                    typeTex:SetAtlas("Crosshair_Quest_64")
                end
                frame._qtTypeIconArt = art
            end
            local fullW, fullH, textX, iconX, iconSize =
                mod.NP_QuestTypeIconLayout(frame._qtW, frame._qtH, size, p.questObjectiveTypeIconScale or 100)
            -- Laid out again only when the count's width or the icon's size moved.
            if not frame._qtTypeIconOn or frame._qtTypeIconCounterW ~= frame._qtW or frame._qtTypeIconW ~= iconSize then
                fontStr:ClearAllPoints()
                fontStr:SetPoint("CENTER", frame, "CENTER", textX, 0)
                typeTex:ClearAllPoints()
                typeTex:SetSize(iconSize, iconSize)
                typeTex:SetPoint("LEFT", frame, "CENTER", iconX, 0)
                frame._qtTypeIconOn = true
                frame._qtTypeIconCounterW, frame._qtTypeIconW = frame._qtW, iconSize
            end
            typeTex:Show()
            wid, hgt = fullW, fullH
        elseif self.questTextTypeIcon then
            QuestTextTypeIconHide(self)
        end
        self.questTextIcon:Hide()
        fontStr:Show()
    else
        if self.questTextTypeIcon then
            QuestTextTypeIconHide(self)
        end
        wid, hgt = iconSz, iconSz
        self.questText:Hide()
        self.questTextIcon:Show()
    end
    local lastW, lastSlot, wasShown = frame._npW, self._qtSlot, frame:IsShown()
    frame._npW, frame._npSz = wid, hgt
    Pix.Size(frame, wid, hgt)
    local xOff, yOff = GetSlotOffsets(slotRec)
    PlaceSlotIcon(self, frame, slotRec, xOff, yOff, 2, hgt)
    self._qtSlot = slotRec
    frame:Show()
    if not wasShown or lastW ~= wid then
        self:UpdateNameWidth()
    end
    -- A side slot pushes the target arrows out, like the classification icon.
    if
        (not wasShown or lastSlot ~= slotRec or lastW ~= wid)
        and (slotRec == "left" or slotRec == "right" or lastSlot == "left" or lastSlot == "right")
    then
        PositionArrowsOutsideAuras(self)
    end
    -- Elements sharing the slot follow its show and move (and close up where it left).
    if mod.NP_CoreChain then
        if wasShown and lastSlot and lastSlot ~= slotRec and lastSlot ~= chainParent then
            mod.NP_CoreChain(self, lastSlot)
        end
        if slotRec ~= chainParent then
            mod.NP_CoreChain(self, slotRec)
        end
    end
end
-- Faction badge (Horde/Alliance): a Core Positions slot element, placed exactly like
-- the Rare/Quest indicator above. Which badge (if any) comes from ns.NP_FactionBadge,
-- shared with the friendly plates.
-- artOnly (the plate's own UNIT_FACTION): a badge already up in this slot only
-- needs its art checked; every layout input moves through a layout caller.
function NameplateFrame:UpdateFaction(artOnly)
    local slotRec = mod.NP_GetFactionSlot()
    local unitToken = self.unit
    -- Zero cost while the slot is None: no badge frame, no events.
    if unitToken and slotRec ~= "none" then
        -- Faction and PvP flag changes both arrive as UNIT_FACTION (the one event
        -- Blizzard's own unit frames repaint their PvP badge on).
        if self._factionEv ~= unitToken then
            self:RegisterUnitEvent("UNIT_FACTION", unitToken)
            self._factionEv = unitToken
        end
        if not self.factionFrame then
            -- Same indicator tier as the classification icon, one level below it, so
            -- a stacked Rare/Quest + Faction pair draws Rare/Quest on top. Born in the
            -- plate's aspect holder like the other slot icons (PlatePool, coreHost), so a
            -- Core Positions chain can anchor it to an aura row.
            local frame = CreateFrame("Frame", nil, self.coreHost or self)
            frame:SetFrameStrata(mod.GetSlotRaiseStrata(slotRec) and "HIGH" or "MEDIUM")
            frame:SetFrameLevel(self.health:GetFrameLevel() + 2)
            frame:Hide()
            self.faction = frame:CreateTexture(nil, "ARTWORK")
            self.faction:SetAllPoints()
            self.factionFrame = frame
        end
    elseif self._factionEv then
        self:UnregisterEvent("UNIT_FACTION")
        self._factionEv = nil
    end
    local atlasName, dimmed
    if unitToken and slotRec ~= "none" then
        atlasName, dimmed = mod.NP_FactionBadge(unitToken)
    end
    if not atlasName then
        if self.factionFrame and self.factionFrame:IsShown() then
            self.factionFrame:Hide()
            self:UpdateNameWidth()
            -- A side-slot badge had pushed the target arrows out: pull them back in.
            if self._facSlot == "left" or self._facSlot == "right" then
                PositionArrowsOutsideAuras(self)
            end
            -- Elements sharing the slot close up.
            if mod.NP_CoreChain then
                mod.NP_CoreChain(self, slotRec)
            end
        end
        return
    end
    -- Repaint only when the art or the dim changes (inputs: faction, Icon Style, honor
    -- badge, dim). The texture keeps its art across pool recycles, so the memo never
    -- goes stale.
    local style = mod.NP_GetFactionStyle()
    local badge = CludesUI.FactionBadgeFor(style, unitToken)
    if self._facArt ~= atlasName or self._facStyle ~= style or self._facBadge ~= badge then
        CludesUI.SetFactionArt(self.faction, style, atlasName, badge)
        self._facArt, self._facStyle, self._facBadge = atlasName, style, badge
    end
    if self._facDim ~= dimmed then
        self.faction:SetDesaturated(dimmed)
        self.faction:SetAlpha(dimmed and 0.6 or 1)
        self._facDim = dimmed
    end
    if artOnly and self._facSlot == slotRec and self.factionFrame:IsShown() then
        return
    end
    local fxOff, fyOff = GetSlotOffsets(slotRec)
    local size = mod.NP_GetFactionIconSize()
    self.factionFrame._npSz = size
    Pix.Size(self.factionFrame, size, size)
    -- "Rare/Quest + Faction" with the classification icon showing too: the faction
    -- badge stacks behind it, overlapping by 40% of the icon's current size
    -- (classification is a frame level above, so it draws on top); up, or down in the
    -- Bottom slot so it clears the cast bar.
    if p and p.classificationIncludeFaction and self.classFrame:IsShown() then
        local step = math.floor((self.classFrame._npSz or GetRareEliteIconSize()) * 0.6 + 0.5)
        if slotRec == "bottom" then
            step = -step
        end
        if mod.NP_CoreChained and mod.NP_CoreChained(slotRec) then
            -- Other elements share the slot: the pair is one member of its chain, so the
            -- badge rides the indicator wherever the chain puts it.
            self.factionFrame:ClearAllPoints()
            Pix.Point(self.factionFrame, "BOTTOMLEFT", self.classFrame, "BOTTOMLEFT", 0, step)
        else
            PlaceSlotIcon(self, self.factionFrame, slotRec, fxOff, fyOff + step, 2, size)
        end
    else
        PlaceSlotIcon(self, self.factionFrame, slotRec, fxOff, fyOff, 2, size)
    end
    local wasShown = self.factionFrame:IsShown()
    local lastSlot = self._facSlot
    self._facSlot = slotRec
    self.factionFrame:Show()
    if not wasShown then
        self:UpdateNameWidth()
    end
    -- A side-slot badge pushes the target arrows out, like the classification icon:
    -- re-flank them when it appears or moves into or out of a side slot.
    if
        (not wasShown or lastSlot ~= slotRec)
        and (slotRec == "left" or slotRec == "right" or lastSlot == "left" or lastSlot == "right")
    then
        PositionArrowsOutsideAuras(self)
    end
    -- Elements sharing the slot follow the badge's show and move.
    if mod.NP_CoreChain then
        mod.NP_CoreChain(self, slotRec)
    end
end
-- The room a name has in the Top slot: the bar minus the raid marker, the Rare/Quest
-- indicator, the Quest Objective Text and the faction badge while they show, and minus the
-- wider Top Left / Top Right text on each side (the name is centred between them). The Top
-- Custom text naming the unit takes it too (AddCustomText, then UpdateNameWidth keeps it
-- current).
local function TopNameWidth(self, barW)
    local nameWidth = barW
        - 2
            * math.max(
                mod.NP_TopCornerTextWidth("textSlotTopLeft"),
                mod.NP_TopCornerTextWidth("textSlotTopRight")
            )
    local rmPos = GetRaidMarkerPos()
    if rmPos ~= "none" and self.raidFrame:IsShown() then
        nameWidth = nameWidth - 2 * (GetRaidMarkerSize() - 2) - 7
    end
    local clSlot = GetClassificationSlot()
    if clSlot ~= "none" and self.classFrame:IsShown() then
        nameWidth = nameWidth - ((self.classFrame._npSz or GetRareEliteIconSize()) + 4)
    end
    local qf = self.questTextFrame
    if qf and qf:IsShown() then
        nameWidth = nameWidth - ((qf._npW or 0) + 4)
    end
    -- Stacked with the classification icon ("Rare/Quest + Faction") it takes
    -- no extra width; alone it reserves its own.
    local stacked = p and p.classificationIncludeFaction and self.classFrame:IsShown()
    if self.factionFrame and self.factionFrame:IsShown() and not stacked then
        nameWidth = nameWidth - (mod.NP_GetFactionIconSize() + 4)
    end
    return nameWidth
end
mod.NP_TopNameWidth = TopNameWidth
function NameplateFrame:UpdateNameWidth()
    local barW = GetHealthBarWidth()
    -- Width % scales the computed (bar-derived) width; 100 = historical behaviour.
    local pct = (p and p.enemyNameWidthPct) or defaultSet.enemyNameWidthPct
    local nameSlotKey = mod.FindNameSlot()
    local markerSpace = self._nameRaidMarkerShown == true
            and (((p and p.nameRaidMarkerSize) or defaultSet.nameRaidMarkerSize or 14) + 3)
        or 0
    if nameSlotKey == "textSlotTop" then
        -- Above the bar: reserve a fixed slot for the inline raid marker.
        local nameWidth = TopNameWidth(self, barW) - markerSpace
        Pix.Width(self.name, math.max(nameWidth * pct / 100, 20))
    elseif
        nameSlotKey == "textSlotBottomLeft"
        or nameSlotKey == "textSlotBottomRight"
        or nameSlotKey == "textSlotTopLeft"
        or nameSlotKey == "textSlotTopRight"
    then
        -- On a corner of the bar the name never truncates: no width box (auto-sized).
        self.name:SetWidth(0)
    elseif nameSlotKey then
        -- Inside the bar: estimate how much space health text occupies in
        -- opposing slots, then give the name everything that remains.
        local usedWidth = 0
        for _, key in ipairs(mod._npBarTextKeys) do
            if key ~= nameSlotKey then
                local el = GetTextSlot(key)
                if el == "custom" then
                    usedWidth = usedWidth + mod.NP_CustomWidth(key)
                elseif el ~= "none" and not mod.IsNameElement(el) then
                    usedWidth = usedWidth + EstimateHealthTextWidth(el)
                end
            end
        end
        local nameWidth = barW - usedWidth - markerSpace
        Pix.Width(self.name, math.max(nameWidth * pct / 100, 20))
    else
        -- Name not in any slot, use minimal width
        Pix.Width(self.name, math.max(barW * pct / 100, 20))
    end
    if self._cuTopName then
        local fontStr = self.customTop
        fontStr:SetWidth(
            math.max(TopNameWidth(self, barW) * ((p and p.textSlotTopWidthPct) or 100) / 100, 20)
        )
        mod.ReflowFontString(fontStr)
    end
end
function NameplateFrame:ApplyNameVisibility()
    -- Zero cost when off: the name's shown state is owned by RefreshNamePosition;
    -- only override it (hide while the cast bar is up) when the feature is on.
    if not GetHideEnemyNameWhileCasting() then
        return
    end
    local hasNameSlot = mod.FindNameSlot() ~= nil
    local isShown = hasNameSlot and not self.cast:IsShown()
    self.name:SetShown(isShown)
    if self.nameRaidFrame then
        self.nameRaidFrame:SetShown(isShown and self._nameRaidMarkerShown == true)
    end
    if mod.DebuffColors_NameChanged then
        mod.DebuffColors_NameChanged(self, true)
    end
end
-- The full-size cast icon (a cast-bar child) occupies its side-slot space only while a cast is
-- up, so its push is gated on the cast bar being shown (see ns.NP_FullIconPush). On every cast
-- show/hide, re-anchor the side elements it pushes (classification icon, faction badge, raid
-- marker, the side aura rows) and the target arrows, so they track the icon instead of sitting
-- shoved out by a phantom gap. Zero cost unless the full-size icon is enabled.
function NameplateFrame:RefreshCastIconSideReserve()
    if not (GetShowCastIcon() and mod.GetCastIconFullSize()) then
        return
    end
    self:UpdateClassification()
    if not (p and p.classificationIncludeFaction) then
        self:UpdateFaction()
    end
    self:UpdateRaidIcon()
    if mod.NPC_PlaceSideRows then
        mod.NPC_PlaceSideRows(self)
    end
    PositionArrowsOutsideAuras(self)
end

function NameplateFrame:RefreshNamePosition(localOnly)
    local nameSlotKey = mod.FindNameSlot()
    local nameYOff = GetNameYOffset()
    local nameMarkerShown
    local nameMarkerSize = (p and p.nameRaidMarkerSize) or defaultSet.nameRaidMarkerSize or 14
    if self.nameRaidFrame then
        local position
        if p and p.nameRaidMarkerEnabled == true and nameSlotKey and self.unit then
            position = GetRaidTargetIndex and GetRaidTargetIndex(self.unit)
        end
        if type(position) == "nil" then
            self._nameRaidMarkerShown = nil
            self.nameRaidFrame:Hide()
        else
            SetRaidTargetIconTexture(self.nameRaid, position)
            Pix.Size(self.nameRaidFrame, nameMarkerSize, nameMarkerSize)
            self._nameRaidMarkerShown = true
            self.nameRaidFrame:Show()
            nameMarkerShown = true
        end
    end
    local markerSpace = nameMarkerShown and (nameMarkerSize + 3) or 0
    local nameStrata = (p and nameSlotKey and p[nameSlotKey .. "Strata"]) or "MEDIUM"
    self:UpdateNameWidth()
    self.name:ClearAllPoints()
    if nameSlotKey == "textSlotLeft" then
        local textOffX, textOffY = GetTextSlotOffsets("textSlotLeft")
        SetFSFont(self.name, GetTextSlotSize("textSlotLeft"), GetNPOutline())
        self.name:SetParent(mod.SlotTextHost(self, nameSlotKey, nameStrata))
        Pix.Point(self.name, "LEFT", self.health, "LEFT", 4 + textOffX + markerSpace, textOffY)
        self.name:SetJustifyH("LEFT")
        self.name:Show()
    elseif nameSlotKey == "textSlotCenter" then
        local textOffX, textOffY = GetTextSlotOffsets("textSlotCenter")
        SetFSFont(self.name, GetTextSlotSize("textSlotCenter"), GetNPOutline())
        self.name:SetParent(mod.SlotTextHost(self, nameSlotKey, nameStrata))
        self.name:SetPoint("CENTER", self.health, "CENTER", textOffX + (markerSpace * 0.5), textOffY)
        self.name:SetJustifyH("CENTER")
        self.name:Show()
    elseif nameSlotKey == "textSlotRight" then
        local textOffX, textOffY = GetTextSlotOffsets("textSlotRight")
        SetFSFont(self.name, GetTextSlotSize("textSlotRight"), GetNPOutline())
        self.name:SetParent(mod.SlotTextHost(self, nameSlotKey, nameStrata))
        Pix.Point(self.name, "RIGHT", self.health, "RIGHT", -2 + textOffX, textOffY)
        self.name:SetJustifyH("RIGHT")
        self.name:Show()
    elseif
        nameSlotKey == "textSlotBottomLeft"
        or nameSlotKey == "textSlotBottomRight"
        or nameSlotKey == "textSlotTopLeft"
        or nameSlotKey == "textSlotTopRight"
    then
        local textOffX, textOffY = GetTextSlotOffsets(nameSlotKey)
        local slotRec =
            HP_BAR_SLOTS[(nameSlotKey == "textSlotBottomLeft" and 4) or (nameSlotKey == "textSlotBottomRight" and 5) or (nameSlotKey == "textSlotTopLeft" and 6) or 7]
        SetFSFont(self.name, GetTextSlotSize(nameSlotKey), GetNPOutline())
        self.name:SetParent(mod.SlotTextHost(self, nameSlotKey, nameStrata))
        self:PlaceSlotText(
            self.name,
            slotRec,
            textOffX + ((slotRec.justify == "LEFT") and markerSpace or 0),
            textOffY
        )
        self.name:SetJustifyH(slotRec.justify)
        self.name:Show()
    elseif nameSlotKey == "textSlotTop" then
        local textOffX, textOffY = GetTextSlotOffsets("textSlotTop")
        SetFSFont(self.name, GetTextSlotSize("textSlotTop"), GetNPOutline())
        self.name:SetParent(mod.SlotTextHost(self, "textSlotTop", nameStrata))
        local cpPush = GetClassPowerTopPush(self)
        Pix.Point(
            self.name,
            "BOTTOM",
            self.health,
            "TOP",
            textOffX + (markerSpace * 0.5),
            4 + nameYOff + cpPush + textOffY
        )
        self.name:SetJustifyH("CENTER")
        self.name:Show()
    else
        -- Name not assigned to any slot
        self.name:Hide()
    end
    -- Apply name wrap here (not only at creation) so the cog toggle takes effect on the next
    -- settings refresh. Off = single line + ellipsis, on = up to two lines; reflow re-lays out.
    local nameWrap = defaultSet.enemyNameWrap
    if p and p.enemyNameWrap ~= nil then
        nameWrap = p.enemyNameWrap
    end
    if
        nameSlotKey == "textSlotBottomLeft"
        or nameSlotKey == "textSlotBottomRight"
        or nameSlotKey == "textSlotTopLeft"
        or nameSlotKey == "textSlotTopRight"
    then
        nameWrap = false
    end
    self.name:SetWordWrap(nameWrap)
    self.name:SetNonSpaceWrap(false)
    self.name:SetMaxLines(nameWrap and 2 or 1)
    mod.ReflowFontString(self.name)
    self:ApplyNameVisibility()
    local raidMarker = self.nameRaidFrame
    if raidMarker and self._nameRaidMarkerShown and self.name:IsShown() then
        Pix.Size(raidMarker, nameMarkerSize, nameMarkerSize)
        -- Follows the name's host so the marker rides the slot's strata; the
        -- host's own SetFrameStrata (SlotTextHost) resets child frames, so
        -- re-assert AFTER parenting.
        raidMarker:SetParent(mod.SlotTextHost(self, nameSlotKey, nameStrata))
        raidMarker:SetFrameStrata(nameStrata)
        raidMarker:SetFrameLevel(901)
        raidMarker:ClearAllPoints()
        raidMarker:SetPoint("RIGHT", self.name, "LEFT", -3, 0)
        raidMarker:Show()
    elseif raidMarker then
        raidMarker:Hide()
    end
    -- Debuff coloring's Color Name copies follow the name's host, font and wrapping.
    if mod.DebuffColors_NameChanged then
        mod.DebuffColors_NameChanged(self)
    end
    -- The top corner texts sit at the name's height: they follow the class power
    -- push with it (a target change runs this on the target's plate).
    if mod._npTopCornerUsed then
        self:AnchorTopCornerTexts()
    end
    if localOnly then
        return
    end
    self:UpdateClassification()
    if not (p and p.classificationIncludeFaction) then
        self:UpdateFaction()
    end
end
function NameplateFrame:UpdateRaidIcon()
    if not self.unit then
        return
    end
    local place = GetRaidMarkerPos()
    if place == "none" then
        self.raidFrame:Hide()
        self:UpdateNameWidth()
        return
    end
    -- type() is taint-safe: returns "nil"/"number" without reading the secret value
    local position = GetRaidTargetIndex and GetRaidTargetIndex(self.unit)
    if type(position) == "nil" then
        self.raidFrame:Hide()
        self:UpdateNameWidth()
        -- Elements sharing the slot close up.
        if mod.NP_CoreChain then
            mod.NP_CoreChain(self, place)
        end
        return
    end
    SetRaidTargetIconTexture(self.raid, position)
    local size = GetRaidMarkerSize()
    self.raidFrame._npSz = size
    Pix.Size(self.raidFrame, size, size)
    local rxOff, ryOff = GetAuraSlotOffsets("raidMarker")
    PlaceSlotIcon(self, self.raidFrame, place, rxOff, ryOff, 0, size)
    self.raidFrame:Show()
    self:UpdateNameWidth()
    -- Elements sharing the slot follow the marker's show and move.
    if mod.NP_CoreChain then
        mod.NP_CoreChain(self, place)
    end
end
function NameplateFrame:ApplyTarget()
    if not self.unit then
        return
    end
    local targeted = UnitIsUnit(self.unit, "target")
    local flip = (self._isTarget == true) ~= (targeted == true)
    -- The hash line is painted by the health pass from this cached flag, so a
    -- flip queues one coalesced repaint (only while the line is enabled).
    if flip and p and p.hashLineEnabled then
        self:MarkHealthDirty()
    end
    self._isTarget = targeted -- cached for hot-path hash line check
    -- The Threat Gap shows on the target's plate only: a flip repaints its text.
    if flip and mod._npTgapOn then
        mod.NP_UpdateThreatPct(self, self.unit)
    end
    -- Cache ownership lives here so EVERY painter keeps it coherent:
    -- SetUnit's deferred setup (pending-watcher promotion), the UpdateHealthValues
    -- token swap and PLAYER_TARGET_CHANGED all funnel through this method. Gaining
    -- target claims the slot; a recycled plate that lost target frees it, so a
    -- stale entry can never skip the un-paint on the next target change.
    if targeted then
        mod._cachedTargetPlate = self
    elseif mod._cachedTargetPlate == self then
        mod._cachedTargetPlate = nil
    end
    -- CludesUI: background glow around the plate, tinted + faded with the
    -- target Glow Color/Opacity (re-applied on show so live edits update).
    if targeted and mod.GetTargetGlowCludesUI() then
        EnsureGlow(self)
        if self.glowTextures then
            local gc = mod.GetTargetGlowColor()
            local ga = mod.GetTargetGlowAlpha()
            for _, tex in ipairs(self.glowTextures) do
                tex:SetVertexColor(gc.r, gc.g, gc.b, ga)
            end
        end
        self.glow:Show()
    elseif self.glow then
        self.glow:Hide()
    end
    -- Border Size: resize the health border while targeted. tbsz stays nil unless the effect is
    -- on AND a size was snapshotted. Runs BEFORE Border Color so a rebuilt custom border gets
    -- its target tint right after. Restore is one-shot via self._targetBorderSized.
    local tbsz
    if targeted and mod.GetTargetGlowBorderSize() then
        tbsz = mod.GetTargetBorderSizeValue()
    end
    if tbsz then
        if mod.IsCustomBorderEnabled() then
            mod.ApplyCustomBorderStyle(self, tbsz)
        elseif Pix and IsBorderEnabled() then
            Pix.SetBorderSize(self.health, tbsz)
        end
        self._targetBorderSized = true
    elseif self._targetBorderSized then
        self._targetBorderSized = nil
        self:ApplyBorder()
    end
    -- Border Color: recolor the health bar border with the custom target color
    if targeted and mod.GetTargetGlowBorderColor() then
        if Pix then
            local bc = mod.GetTargetBorderColor()
            if mod.IsCustomBorderEnabled() then
                -- Custom border replaces the simple one; recolor with the target color,
                -- lazy-creating it if this plate is targeted before its first ApplyBorder ran.
                if not self._customBorder then
                    mod.ApplyCustomBorderStyle(self)
                end
                if self._customBorder and CludesUI.SetBorderStyleColor then
                    CludesUI.SetBorderStyleColor(self._customBorder, bc.r, bc.g, bc.b, 1)
                end
            else
                mod.NP_BasicBorderColor(self, bc.r, bc.g, bc.b, 1)
            end
            self._hbThreatTint = nil
        end
        -- Use Target Border Color on the custom spell icon border (the else branch's
        -- ApplyBorderColor restores it). One field read while off.
        if p and p.castIconCustomBorder then
            mod.ApplyCastIconBorder(self)
        end
    else
        self:ApplyBorderColor()
    end
    -- If this plate is wrapping its border around the cast bar, the colour just set landed on
    -- the HIDDEN health border: re-sync the visible unified border. One field read unless live.
    -- (Custom wrap: re-syncs the lower piece and seam to the size and colour just set.)
    if self._wrapActive or self._cbWrapActive then
        self:UpdateBorderWrap()
    end
    -- Blizzard Style: stock selection ring / deselected overlay. The classic
    -- plate marks its target through the CUI effects above alone.
    if mod.NP_Style() == "blizzard" then
        mod.NP_ApplyBlizzSelection(self, targeted)
    end
    -- Highlight: translucent wash across the health bar (color + opacity are
    -- configurable; re-applied on show so live edits and pooled textures update)
    if targeted and mod.GetTargetGlowHighlight() then
        EnsureTargetHighlight(self)
        local color = mod.GetTargetHighlightColor()
        self.targetHighlight:SetColorTexture(color.r, color.g, color.b, mod.GetTargetHighlightAlpha())
        self.targetHighlight:Show()
    elseif self.targetHighlight then
        self.targetHighlight:Hide()
    end
    if p and p.showTargetArrows then
        if targeted then
            EnsureArrows(self)
            local sc = p.targetArrowScale or 1.0
            local arrowStyle = mod.ResolveTargetArrowStyle(p)
            self.leftArrow:SetTexture(mod.TARGET_ARROW_DIR .. arrowStyle.l .. ".png")
            self.rightArrow:SetTexture(mod.TARGET_ARROW_DIR .. arrowStyle.r .. ".png")
            local acr, acg, acb = mod.GetTargetArrowColor(p)
            self.leftArrow:SetVertexColor(acr, acg, acb)
            self.rightArrow:SetVertexColor(acr, acg, acb)
            local aw, ah = math.floor(arrowStyle.w * sc + 0.5), math.floor(16 * sc + 0.5)
            Pix.Size(self.leftArrow, aw, ah)
            Pix.Size(self.rightArrow, aw, ah)
            self.leftArrow:Show()
            self.rightArrow:Show()
            PositionArrowsOutsideAuras(self)
        elseif self.leftArrow then
            self.leftArrow:Hide()
            self.rightArrow:Hide()
        end
    elseif self.leftArrow then
        self.leftArrow:Hide()
        self.rightArrow:Hide()
    end
    -- Class power pips: show on target, hide on others
    if GetShowClassPower() and classPowerType then
        if targeted then
            EnsureClassPowerPips(self)
            UpdateClassPowerOnPlate(self)
        else
            HideClassPowerOnPlate(self)
        end
    end
    self:ApplyScale()
end
function NameplateFrame:ApplyMouseover()
    if not self.unit then
        return
    end
    if UnitExists("mouseover") and UnitIsUnit(self.unit, "mouseover") then
        mod.ShowHoverEffect(self)
        mod.ApplyHoverExtras(self)
        mod._currentMouseoverPlate = self
        if mod._EnsureMouseoverTicker then
            mod._EnsureMouseoverTicker()
        end
    else
        mod.HideHoverEffect(self)
        mod.ClearHoverExtras(self)
    end
end

-- Hover Effect extra channels (CUI Glow / Border Color / Border Size --
-- mirrors ApplyTarget's branches; the Highlight channel lives inside
-- ShowHoverEffect). TARGET PRECEDENCE per shared visual: while this plate is
-- the target and the TARGET effect drives the same channel, hover leaves it
-- alone -- and ApplyTarget runs after every target change, so the target
-- state always reasserts over a stale hover write.
function mod.ApplyHoverExtras(backing)
    if not backing or not backing.unit or not backing.health then
        return
    end
    local targeted = backing._isTarget
    local any = false
    local wrapSync = false -- one cast bar wrap re-sync at the end, after size and colour
    -- CUI Glow (shared self.glow visual).
    if mod.GetHoverGlowCludesUI() and not (targeted and mod.GetTargetGlowCludesUI()) then
        EnsureGlow(backing)
        if backing.glowTextures then
            local gc = mod.GetHoverGlowColor()
            local ga = mod.GetHoverGlowAlpha()
            for _, tex in ipairs(backing.glowTextures) do
                tex:SetVertexColor(gc.r, gc.g, gc.b, ga)
            end
        end
        backing.glow:Show()
        any = true
    end
    -- Border Size (a target-sized border wins; restore is ClearHoverExtras').
    if mod.GetHoverGlowBorderSize() and not backing._targetBorderSized then
        local hbsz = mod.GetHoverBorderSizeValue()
        if hbsz then
            if mod.IsCustomBorderEnabled() then
                mod.ApplyCustomBorderStyle(backing, hbsz)
            elseif Pix and IsBorderEnabled() then
                Pix.SetBorderSize(backing.health, hbsz)
            end
            -- The resize drew the base colour (custom rebuild) or the last clean one
            -- (re-snap) over a Threat Colors tint: put it back unless a hover or target
            -- border colour paints this border instead.
            if
                backing._threatBdOn
                and not mod.GetHoverGlowBorderColor()
                and not (targeted and mod.GetTargetGlowBorderColor())
            then
                backing:ApplyBorderColor()
            end
            backing._hoverBorderSized = true
            any = true
            -- The custom wrap copies the size its border is drawn at. Not the Basic
            -- wrap: it re-applies the base size and would undo the hover size.
            if backing._cbWrapActive then
                wrapSync = true
            end
        end
    end
    -- Border Color (the target color wins).
    if mod.GetHoverGlowBorderColor() and not (targeted and mod.GetTargetGlowBorderColor()) then
        if Pix then
            local bc = mod.GetHoverBorderColor()
            if mod.IsCustomBorderEnabled() then
                if not backing._customBorder then
                    mod.ApplyCustomBorderStyle(backing)
                end
                if backing._customBorder and CludesUI.SetBorderStyleColor then
                    CludesUI.SetBorderStyleColor(backing._customBorder, bc.r, bc.g, bc.b, 1)
                end
            else
                mod.NP_BasicBorderColor(backing, bc.r, bc.g, bc.b, 1)
            end
            backing._hbThreatTint = nil
            any = true
            -- A friendly plate's ApplyTarget has no border colour of its own to fall back
            -- on: this flag tells it to repaint the base colour on the way out.
            backing._fxBorderTinted = true
        end
        if backing._wrapActive or backing._cbWrapActive then
            wrapSync = true
        end
    end
    if wrapSync then
        backing:UpdateBorderWrap()
    end
    if any then
        backing._hoverFxOn = true
    end
end

-- One-shot restore of every shared channel to the target/base state: the
-- hover-sized border resets explicitly (ApplyTarget only restores its OWN
-- sizing flag), then ApplyTarget's else-branches reset glow/border color.
-- Early-out keeps the no-extras case (the shipped default) zero-cost.
function mod.ClearHoverExtras(backing)
    if not backing or not backing._hoverFxOn then
        return
    end
    backing._hoverFxOn = nil
    if backing._hoverBorderSized then
        backing._hoverBorderSized = nil
        backing:ApplyBorder()
    end
    backing:ApplyTarget()
end

Inner.broken = false
