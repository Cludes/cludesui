if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-------------------------------------------------------------------------------
--  CUI_CDM_HookDecorate.lua
--
--  DecorateFrame and CategorizeFrame.
--  Reads the earlier hook files through ns and ns._hookInternals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._hookInternals
-- CludesUICdmHooks.lua or an earlier hook file failed to load.
if not Inner or Inner.broken then return end
Inner.broken = true

local barMap = mod.barDataByKey
local GetCDMFont = mod.GetCDMFont
local _ecmeFC = mod._ecmeFC
local FC = mod.FC
local _, _playerClass = UnitClass("player")

local hookFrameData, ResolveCDIDToBar = Inner.hookFrameData, Inner.ResolveCDIDToBar
local ResolveFrameSpellID, ResolveSpellSettings = Inner.ResolveFrameSpellID, Inner.ResolveSpellSettings
local ApplyCdmChargeStyle, ApplyCdmEdge = Inner.ApplyCdmChargeStyle, Inner.ApplyCdmEdge
local ApplyMaxStacksGlow, CdmChargeInfoFor = Inner.ApplyMaxStacksGlow, Inner.CdmChargeInfoFor
local CdmFrameIsActive, CdmStaleLinkedSpell = Inner.CdmFrameIsActive, Inner.CdmStaleLinkedSpell
local EvalMaxStacksFrame = Inner.EvalMaxStacksFrame
local HideBlizzardDecorations = Inner.HideBlizzardDecorations
local WatchMaxStacksFrame, ApplyCustomIcon = Inner.WatchMaxStacksFrame, Inner.ApplyCustomIcon
local ApplyOnlyNumbers, ArmCdStateEval = Inner.ApplyOnlyNumbers, Inner.ArmCdStateEval
local TryHookSwiftmend, ApplyResourceTint = Inner.TryHookSwiftmend, Inner.ApplyResourceTint

-------------------------------------------------------------------------------
--  Viewer re-anchoring
--  All viewers measure their children after placing them. An icon moved to our
--  bar (or parked) mid-Layout makes the viewer measure that gap as its own size,
--  which pushes everything above it in Blizzard's bottom stack. Restore our
--  anchors (or park unclaimed icons) only after that measurement, from
--  RefreshLayout's post-hook (Blizzard's one Layout call) or this one-shot
--  callback when an icon moves outside a layout.
-------------------------------------------------------------------------------
local viewerPending = setmetatable({}, { __mode = "k" })
local viewerRestore = mod.TakeShell()
viewerRestore:Hide()

local function QueueViewerAnchor(widget)
    viewerPending[widget] = true
    viewerRestore:Show()
end

-- CD/utility icons the reanchor parked before any claim decorated them (a
-- spell on Hidden CDs or on no bar since login) have no SetPoint hook from
-- DecorateFrame. Blizzard's next layout puts such an icon back in the
-- viewer's grid with its tooltip motion on, where it catches hover at alpha
-- 0 over whatever sits under that slot. This hook queues it for the park
-- below; the park itself (relative to UIParent) passes, and once a claim
-- has decorated it, DecorateFrame's hook keeps it.
local parkWatched = setmetatable({}, { __mode = "k" })

local function OnParkedIconSetPoint(widget, _, relativeTo)
    if relativeTo == UIParent then return end
    local frameData = hookFrameData[widget]
    if frameData and frameData.decorated then return end
    widget:SetAlpha(0)
    QueueViewerAnchor(widget)
end

local function WatchParkedIcon(widget)
    if parkWatched[widget] then return end
    local frameData = hookFrameData[widget]
    if frameData and frameData.decorated then return end
    parkWatched[widget] = true
    hooksecurefunc(widget, "SetPoint", OnParkedIconSetPoint)
end

local function RestoreViewerAnchors(viewer)
    for widget in pairs(viewerPending) do
        -- A nested refresh must not restore another viewer's unfinished grid.
        if not viewer or widget.viewerFrame == viewer then
            viewerPending[widget] = nil
            -- Read the current claim: the pool may have released or reassigned it.
            local frameData = hookFrameData[widget]
            local a = frameData and frameData._cdmAnchor
            if a then
                widget:ClearAllPoints()
                widget:SetPoint(a[1], a[2], a[3], a[4], a[5])
            elseif frameData and frameData.decorated and not frameData._isBuffViewerFrame then
                -- Match LayoutCDMBar's anchor keyword so a later claim replaces it.
                frameData._parkGuard = true
                widget:ClearAllPoints()
                widget:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10000, 10000)
                frameData._parkGuard = nil
            elseif parkWatched[widget] then
                widget:ClearAllPoints()
                widget:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10000, 10000)
            end
        end
    end
    if next(viewerPending) == nil then viewerRestore:Hide() end
end
viewerRestore:SetScript("OnUpdate", function() RestoreViewerAnchors() end)

-------------------------------------------------------------------------------
--  DecorateFrame
--  Add our visual overlays to a CDM frame (one-time per frame).
-------------------------------------------------------------------------------
local function DecorateFrame(widget, barInfo)
    -- Empty Slot: deliberately undecorated (true blank grid space, no texture/
    -- cooldown/border/glowOverlay). Never register it in hookFrameData -- every
    -- _getFD(icon) lookup then reads nil and every fd-driven pass (bar-wide
    -- glow/border/background included) already no-ops on a nil fd.
    if widget._isEmptySlotFrame then return end
    local frameData = hookFrameData[widget]
    if not frameData then
        frameData = {}
        hookFrameData[widget] = frameData
    end

    -- Border + background track the CURRENT bar's settings on EVERY call, not just the
    -- first: Blizzard recycles one icon-frame pool across bars/spells, so a frame
    -- decorated under another bar's style must pick this bar's up on every (re)claim.
    -- For hooked default bars (Essential/Utility) this is the ONLY re-style path
    -- (RefreshCDMIconAppearance is skipped for them); structural creation stays
    -- one-time via the fd.borderFrame/fd.bg guards, only styling is unconditional.
    -- Frame levels are relative to the icon's LIVE level (never cached at first
    -- decoration) so a reclaimed pooled frame stays correctly layered.
    local baseLvl = widget:GetFrameLevel()

    -- Blizzard Style (Global Settings > Style): no CUI background or border;
    -- the viewer's rounded mask stays and ns.CdmApplyBlizzIconArt draws the
    -- ring. Stamped on fd so the swipe hooks read one flag per push.
    local blizzArt = mod.CdmBlizzIcons()
    frameData._blizzArt = blizzArt or nil

    if blizzArt then
        if frameData.bg then frameData.bg:Hide() end
    else
        if not frameData.bg then
            local backdrop = widget:CreateTexture(nil, "BACKGROUND")
            backdrop:SetAllPoints()
            frameData.bg = backdrop
        end
        frameData.bg:SetColorTexture(
            barInfo.bgR or 0.08,
            barInfo.bgG or 0.08,
            barInfo.bgB or 0.08,
            barInfo.bgA or 0.6
        )
    end

    -- Show Cooldown Edge: stamped per (re)claim so the cooldown hooks read one
    -- flag instead of chasing frame -> bar -> settings on every push. Toggling
    -- rebuilds bars, so the stamp always tracks the live setting; on the
    -- on -> off transition drop a mid-sweep edge now instead of waiting for
    -- Blizzard's next cooldown push.
    local edgeOn = barInfo.showCooldownEdge or nil
    if frameData._edgeFeatureOn and not edgeOn and frameData.cooldown and frameData.cooldown.SetDrawEdge then
        frameData._isProcessingOverride = true
        frameData.cooldown:SetDrawEdge(false)
        frameData._isProcessingOverride = false
        frameData._edgeApplied = nil
    end
    frameData._edgeFeatureOn = edgeOn

    -- Custom-shape bars own their border: ApplyShapeToCDMIcon draws the ring on
    -- shapeBorder and hides the square border. Re-applying the square style here
    -- would force it back on unchanged reanchors (no shape re-apply follows those),
    -- so keep it hidden -- newly (re)claimed frames land in an iconsChanged refresh
    -- that re-applies the shape. Active-state tint on shaped icons rides
    -- shapeBorder, never the square border, so both re-asserts below are square-only.
    local shapeKey = barInfo.iconShape
    if blizzArt then
        -- Blizzard Style: the ring overlay is the frame; no square border.
        if frameData.borderFrame then
            CUI.PP.HideBorder(frameData.borderFrame)
            local bdFrame = CUI._bdBorderData and CUI._bdBorderData[frameData.borderFrame]
            if bdFrame then bdFrame:Hide() end
        end
    elseif shapeKey and shapeKey ~= "none" and shapeKey ~= "cropped" then
        if frameData.borderFrame then
            CUI.PP.HideBorder(frameData.borderFrame)
            local bdFrame = CUI._bdBorderData and CUI._bdBorderData[frameData.borderFrame]
            if bdFrame then bdFrame:Hide() end
        end
    else
        if not frameData.borderFrame then
            local bf = CreateFrame("Frame", nil, widget)
            bf:SetAllPoints(widget)
            frameData.borderFrame = bf
        end
        local brdR, brdG, brdB = barInfo.borderR or 0, barInfo.borderG or 0, barInfo.borderB or 0
        if barInfo.borderClassColor then
            local cc = _playerClass and RAID_CLASS_COLORS[_playerClass]
            if cc then
                brdR, brdG, brdB = cc.r, cc.g, cc.b
            end
        end
        local textureKey = barInfo.borderTexture or "solid"
        local brdSize = barInfo.borderSize or 1
        -- "Show Behind": +13 draws the border in front of the icon (+14 for the Pixels
        -- styles, above frame.Cooldown), level-1 behind it. Set BEFORE styling so the
        -- textured backdrop inherits it.
        frameData.borderFrame:SetFrameLevel(
            barInfo.borderBehind and math.max(0, baseLvl - 1)
                or (baseLvl + (CUI._pixelArtBorders[textureKey] and 14 or 13))
        )
        CUI.ApplyBorderStyle(
            frameData.borderFrame,
            brdSize,
            brdR,
            brdG,
            brdB,
            barInfo.borderA or 1,
            textureKey,
            barInfo.borderTextureOffset,
            barInfo.borderTextureOffsetY,
            barInfo.borderTextureShiftX,
            barInfo.borderTextureShiftY,
            "cdm",
            barInfo.borderThickness or "thin",
            true,
            CUI.BorderPx(barInfo.borderSizePx, brdSize, textureKey)
        )
        -- ApplyBorderStyle always paints the bar's BASE color, so re-assert the
        -- active-state tint if engaged (fd._activeBorderOn, set by
        -- ApplyActiveOverlays off Blizzard's SetSwipeColor) or a reanchor mid-proc flashes it back to base.
        if frameData._activeBorderOn and CUI.SetBorderStyleColor then
            local fcA = _ecmeFC[widget]
            local sidA, bkA = fcA and fcA.spellID, fcA and fcA.barKey
            local spellSettings = sidA and ResolveSpellSettings(widget, sidA, mod.GetBarSpellData(bkA))
            local abR = (spellSettings and spellSettings.activeBorderR) or 1
            local abG = (spellSettings and spellSettings.activeBorderG) or 0.776
            local abB = (spellSettings and spellSettings.activeBorderB) or 0.376
            local abA = (spellSettings and spellSettings.activeBorderA) or 1
            CUI.SetBorderStyleColor(frameData.borderFrame, abR, abG, abB, abA)
        end
    end
    if frameData.glowOverlay then frameData.glowOverlay:SetFrameLevel(baseLvl + 16) end
    -- Blackout (solid-fill Cooldown State glow) sits BELOW frame.Cooldown
    -- (icon+14, +13 under a Pixels border), unlike every other glow style on glowOverlay (icon+16): a
    -- fill above it would hide the swipe and countdown. Made by
    -- ns.StartCdGlow on the icon's first Blackout start.
    if frameData.blackoutOverlay then frameData.blackoutOverlay:SetFrameLevel(baseLvl + 12) end
    if frameData.textOverlay then frameData.textOverlay:SetFrameLevel(baseLvl + 23) end
    if blizzArt then mod.CdmApplyBlizzIconArt(widget) end

    if frameData.decorated then
        -- Late retry: the style block already ran; skip one-time decoration.
        TryHookSwiftmend(widget, frameData)
        ApplyResourceTint(widget, frameData)
        ApplyCustomIcon(widget, frameData)
        ApplyOnlyNumbers(widget, frameData, barInfo)
        return frameData
    end
    frameData.decorated = true

    -- A HOSTED buff frame is a Blizzard buff-viewer frame on a CD/util bar: its
    -- swipe is the AURA DURATION, so the cd-style swipe hooks below (Suppress-GCD,
    -- active-state override, charge logic) must NEVER touch it or they blank the
    -- duration swipe every GCD. viewerFrame is stable per pooled frame: flag once.
    frameData._isBuffViewerFrame = (
        widget.viewerFrame == _G.BuffIconCooldownViewer or widget.viewerFrame == _G.BuffBarCooldownViewer
    ) or nil

    local iconWidget = widget.Icon
    if iconWidget and not iconWidget.GetTexture then
        if iconWidget.Icon then iconWidget = iconWidget.Icon end
    end
    frameData.tex = iconWidget
    frameData.cooldown = widget.Cooldown

    -- Swiftmend brightness (druid only; retried from the decorated early-return).
    TryHookSwiftmend(widget, frameData)
    -- Ignore Resource Cost (inert until some spell uses it; retried the same way).
    ApplyResourceTint(widget, frameData)

    -- First decoration: fd.tex is now available, so Custom Icon can stamp.
    ApplyCustomIcon(widget, frameData)
    ApplyOnlyNumbers(widget, frameData, barInfo)

    HideBlizzardDecorations(widget)

    -- Per-icon Audio on Buff Gain/Loss: hook one-time here, before the frame is ever
    -- active, so the first activation is not missed. Buff-family only;
    -- EnsureBuffSoundHook self-guards on TriggerAuraAppliedAlert presence, so
    -- injected-custom/non-aura frames are no-ops.
    if
        (barInfo and (barInfo.barType == "buffs" or barInfo.key == "buffs"))
        and mod._cdmAnyBuffSound
        and mod.EnsureBuffSoundHook
    then
        mod.EnsureBuffSoundHook(widget)
    end

    -- Hook SetPoint: restore our anchor after Blizzard repositions the icon.
    -- Viewers must finish measuring their native grid first; redirecting
    -- one child during Layout makes ResizeLayout measure the distance between
    -- our bar and the viewer's remaining children as the viewer's own size.
    if not frameData._setPointHooked then
        frameData._setPointHooked = true
        hooksecurefunc(widget, "SetPoint", function(_, anchorPoint, relativeTo)
            if frameData._parkGuard then return end
            local anchor = frameData._cdmAnchor
            if not anchor then
                -- Not yet claimed by our bar system: re-blank so it does not flash at
                -- the viewer's position before CollectAndReanchor claims it.
                if frameData.decorated then
                    widget:SetAlpha(0)
                    -- Alpha can be raised by the engine; park CD/utility icons
                    -- after measurement. Unclaimed buff pools stay hands-off.
                    if not frameData._isBuffViewerFrame then QueueViewerAnchor(widget) end
                end
                return
            end
            -- relativeTo == our bar container: our own LayoutCDMBar SetPoint.
            if relativeTo == anchor[2] then return end
            QueueViewerAnchor(widget)
        end)
    end

    -- Per-icon active state hooks installed lazily during CollectAndReanchor,
    -- ONLY for spells with custom active state settings.

    -- Overlay creation is one-time; frame levels re-applied at the top.
    if not frameData.glowOverlay then
        local go = CreateFrame("Frame", nil, widget)
        go:SetAllPoints(widget)
        go:SetAlpha(0)
        go:EnableMouse(false)
        frameData.glowOverlay = go
        go:SetFrameLevel(baseLvl + 16)
    end

    -- Re-arm the buff ticker's active-glow "nothing configured" latch: this
    -- function re-runs on rebuilds/settings changes (exactly when the cached
    -- answer can change), so a newly enabled glow is picked up next pass.
    frameData._activeGlowNoCfg = nil

    if not frameData.textOverlay then
        local txo = CreateFrame("Frame", nil, widget)
        txo:SetAllPoints(widget)
        txo:EnableMouse(false)
        frameData.textOverlay = txo
        txo:SetFrameLevel(baseLvl + 23)
    end

    if not frameData.keybindText then
        local kt = frameData.textOverlay:CreateFontString(nil, "OVERLAY")
        local kbScale = widget:GetScale() or 1
        if kbScale < 0.01 then kbScale = 1 end
        CUI.ApplyIconTextFont(kt, GetCDMFont(), (barInfo.keybindSize or 10) / kbScale, "cdm")
        kt:Hide()
        mod.StyleCDMKeybind(kt, barInfo, frameData.textOverlay, 1 / kbScale, GetCDMFont())
        frameData.keybindText = kt
    end

    frameData.tooltipShown = false

    -- Pandemic hooks deliberately NOT installed here: they install lazily from
    -- the buff tick, per icon, only when the bar uses a custom pandemic style
    -- (zero cost unless enabled; closures are CDM-billed via file-scope bodies).

    local fc = FC(widget)
    if not fc.tooltipHooked then
        fc.tooltipHooked = true
        widget:HookScript("OnEnter", function()
            local ffc = _ecmeFC[widget]
            local edge = ffc and ffc.barKey and barMap[ffc.barKey]
            if edge and not edge.showTooltip then GameTooltip:Hide() end
        end)
    end

    frameData.procGlowActive = false

    if frameData.cooldown then
        frameData.cooldown:SetDrawEdge(false)
        -- Swipe starts disabled; CollectAndReanchor enables it once claimed and
        -- positioned, so no black-swipe flash at the viewer's default position.
        frameData.cooldown:SetDrawSwipe(false)
        frameData.cooldown:SetDrawBling(false)
        frameData._isProcessingOverride = true
        frameData.cooldown:SetSwipeColor(0, 0, 0, barInfo.swipeAlpha or 0.7)
        frameData._isProcessingOverride = false
        -- High-res flat white, never WHITE8x8: the wedge cut's anti-aliasing comes
        -- from texel filtering, so an 8px texture rasterizes the boundary jagged at
        -- any angle. Own asset over the game's viewer swipe for sharp corners (the
        -- stock file bakes in corner rounding that mismatches our squared icons).
        -- Blizzard Style keeps the viewer's rounded swipe to match its mask.
        frameData.cooldown:SetSwipeTexture(mod.CdmSwipeFile())
        -- Hook SetSwipeColor on EVERY CD/utility frame: forces our swipe color
        -- (black, or per-spell custom) so Blizzard's active-state color flash
        -- never shows. SetDrawSwipe hooked too, to keep charge swipes visible.
        if not frameData._swipeColorHooked then
            frameData._swipeColorHooked = true
            local cooldown = frameData.cooldown
            hooksecurefunc(cooldown, "SetSwipeColor", function()
                if frameData._isProcessingOverride then return end
                -- Buff-viewer frame (buff bar or hosted) or our own preset/custom
                -- buff frame (cast-timer driven): the swipe is the aura DURATION,
                -- so skip all cd-style logic (Suppress-GCD, active-state) and
                -- apply only per-spell "Cooldown Swipe Color" (Default = bar's
                -- swipe colour/black, Class/Custom per settings).
                if frameData._isBuffViewerFrame or widget._isCustomBuffFrame then
                    frameData._isProcessingOverride = true
                    local fcB = _ecmeFC[widget]
                    local sidB = fcB and fcB.spellID
                    local buffBarKey = fcB and fcB.barKey
                    local ssB = (sidB and buffBarKey and mod.ResolveSpellSettings)
                            and mod.ResolveSpellSettings(widget, sidB, false, buffBarKey)
                        or nil
                    local sr, sg, scrollBar
                    -- CURRENT bar's swipe alpha, not the decorate-time closure
                    -- barData: pooled frames decorate once, so it holds whichever
                    -- bar first decorated this frame.
                    local bdB = buffBarKey and barMap and barMap[buffBarKey]
                    local alpha = (bdB and bdB.swipeAlpha) or barInfo.swipeAlpha or 0.7
                    local mode = ssB and ssB.cdSwipeColor
                    if mode == "class" then
                        local _, classTok = UnitClass("player")
                        local cc = classTok and RAID_CLASS_COLORS[classTok]
                        if cc then
                            sr, sg, scrollBar = cc.r, cc.g, cc.b
                        end
                    elseif mode == "custom" then
                        sr, sg, scrollBar = ssB.cdSwipeColorR, ssB.cdSwipeColorG, ssB.cdSwipeColorB
                    elseif mode == "none" then
                        alpha = 0 -- fully hide the swipe (alpha 0, geometry still valid)
                    end
                    cooldown:SetSwipeColor(sr or 0, sg or 0, scrollBar or 0, alpha)
                    frameData._isProcessingOverride = false
                    return
                end
                frameData._isProcessingOverride = true
                local iconCache = _ecmeFC[widget]
                local spellKey = iconCache and iconCache.spellID
                local barKeyOf = iconCache and iconCache.barKey
                local bd2 = barKeyOf and barMap and barMap[barKeyOf]
                -- Resolved BEFORE the Suppress GCD block: the per-spell
                -- suppressGCD flag joins the bar toggle there (pure hoist --
                -- this resolve always ran once per hook pass, just later).
                local iconSettings
                if spellKey and barKeyOf then iconSettings = ResolveSpellSettings(widget, spellKey, false) end
                local _gcdSuppressed = false
                -- Recharge duration of a charge spell whose recharge is running
                -- out underneath a GCD; see ns.GCDTailAlpha at the swipe writes.
                local _gcdChargeTail
                -- Per-bar "Suppress GCD": alpha-0 the swipe while the displayed
                -- cooldown is just a GCD (isOnGCD is a clean bool). Do NOT return
                -- early -- active-state detection below must still run so overlays
                -- and duration timers work during a GCD. Two cases must NEVER be
                -- suppressed: (1) the Hide-Active override window forcing the real
                -- recharge display (a GCD from another ability is moot); (2) a
                -- charge spell with a recharge in flight (ANY count below max,
                -- incl. 0) -- that swipe IS the recharge, and alpha-0'ing it blanks
                -- the recharge for a whole GCD whenever another ability is pressed.
                -- The Hide-Active exclusion applies to whole-swipe suppression
                -- ONLY, not the charge tail: _hideActiveOverriding follows the
                -- active read, which flaps for charge spells.
                -- Per-spell "Suppress GCD" ORs into the bar toggle: with the
                -- bar toggle ON the per-spell flag is a natural no-op.
                if
                    ((bd2 and bd2.suppressGCD) or (iconSettings and iconSettings.suppressGCD))
                    and spellKey
                    and C_Spell
                    and C_Spell.GetSpellCooldown
                then
                    -- Charge-recharge guard: mid-recharge (INCLUDING 0 charges)
                    -- shows the recharge, never a GCD, so never alpha-0 it.
                    -- Derived from STABLE charge data (maxCharges > 1 AND
                    -- GetSpellCharges().isActive), NOT
                    -- HasVisualDataSource_Charges, which flips FALSE while a GCD
                    -- swipe is layered on top -- the exact moment this hook runs
                    -- -- letting a 0-charge recharge get suppressed. Both fields
                    -- clean; secret currentCharges never read. Override ID
                    -- resolved for transform spells.
                    local effID2 = spellKey
                    if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
                        local overrideId = C_SpellBook.FindSpellOverrideByID(spellKey)
                        if overrideId and overrideId > 0 and overrideId ~= spellKey then
                            effID2 = overrideId
                        end
                    end
                    -- Resolved through Blizzard's own accessor: see CdmChargeInfoFor.
                    -- This value decides whether the swipe may be alpha-0'd, and a
                    -- wrong "not recharging" here blanks a live recharge for a whole
                    -- GCD on every override spell.
                    local chargeRecharging = false
                    do
                        local chargeInfo = CdmChargeInfoFor(widget, spellKey)
                        chargeRecharging = (
                            chargeInfo
                            and (chargeInfo.maxCharges or 0) > 1
                            and chargeInfo.isActive == true
                        ) or false
                    end
                    -- The GCD read must use the override too: a transform's real
                    -- CD ticks on the override ID, and the base-ID query reads
                    -- isOnGCD=true through that whole CD, suppressing the swipe
                    -- for its full duration.
                    local cooldownInfo = C_Spell.GetSpellCooldown(effID2)
                        or C_Spell.GetSpellCooldown(spellKey)
                    if cooldownInfo and cooldownInfo.isOnGCD then
                        if not chargeRecharging then
                            if not frameData._hideActiveOverriding then
                                cooldown:SetSwipeColor(0, 0, 0, 0)
                                _gcdSuppressed = true
                            end
                        elseif C_Spell.GetSpellChargeDuration then
                            -- Recharge in flight, but its LAST GCD-length slice
                            -- is drawn by the GCD. Hand the recharge duration to
                            -- the swipe writes below, which alpha-0 that slice
                            -- only; earlier keeps the recharge swipe (case 2).
                            _gcdChargeTail = C_Spell.GetSpellChargeDuration(effID2)
                                or C_Spell.GetSpellChargeDuration(spellKey)
                        end
                    end
                end
                -- Publish the tail decision for ReArmChargeRecharge. That runs from
                -- the SetCooldown hooks, which fire for EVERY icon on every push,
                -- so it must decide whether it cares without paying for a spell
                -- lookup. This flag is exactly the state it needs -- a charge
                -- recharge running underneath a GCD -- and it is already computed
                -- here from clean bools. Blizzard's refresh calls SetSwipeColor
                -- before CooldownFrame_Set, so it is fresh when the re-arm reads it.
                frameData._gcdChargeTailArmed = _gcdChargeTail ~= nil
                -- Active state detected from the swipe color.
                local swipeColor = widget.cooldownSwipeColor
                local isActive = false
                if swipeColor and type(swipeColor) ~= "number" and swipeColor.GetRGBA then
                    local region = swipeColor:GetRGBA()
                    if region and type(region) == "number" and not issecretvalue(region) then
                        isActive = (region ~= 0)
                    end
                end

                -- Flip the per-session gates the moment any spell uses these
                -- settings, so the SetDesaturated/SetDrawSwipe hooks early-out on
                -- one check for everyone else. Runs for every icon on login.
                if iconSettings and iconSettings.desatNotActive then mod._cdmAnyDesatNotActive = true end
                if iconSettings and iconSettings.noDesatOnCD then mod._cdmAnyNoDesatOnCD = true end
                if iconSettings and iconSettings.noResourceTint and not frameData._resTintHooked then
                    mod._cdmAnyNoResourceTint = true
                    ApplyResourceTint(widget, frameData)
                end
                if iconSettings and (iconSettings.chargeHideSwipe or iconSettings.hideRechargeEdge) then
                    mod._cdmAnyChargeStyle = true
                end
                if iconSettings and iconSettings.maxStacksGlow and iconSettings.maxStacksGlow > 0 then
                    mod._cdmAnyMaxStacksGlow = true
                end
                if iconSettings and iconSettings.activeGlow and iconSettings.activeGlow > 0 then
                    mod._cdmAnyActiveGlow = true
                end
                if iconSettings and iconSettings.chargeHideCdText then mod._cdmAnyChargeHideCdText = true end
                if iconSettings and iconSettings.showCooldownText ~= nil then
                    mod._cdmAnySpellDurationText = true
                end
                if iconSettings and iconSettings.hideChargeText then mod._cdmAnyHideChargeText = true end
                if iconSettings and iconSettings.suppressGCD then mod._cdmAnySuppressGcd = true end
                if iconSettings and iconSettings.reverseSwipe then mod._cdmAnyReverseSwipe = true end
                if iconSettings and iconSettings.hideCDSwipe then mod._cdmAnyHideCDSwipe = true end
                if iconSettings and (tonumber(iconSettings.thresholdSeconds) or 0) > 0 then
                    mod._cdmAnyThresholdText = true
                end

                if iconSettings and iconSettings.activeSwipeMode == "none" then
                    -- Hide Active State: force black swipe, track active flag (CD
                    -- model override belongs to the SetDesaturation hook, which fires
                    -- on every Blizzard cooldown tick). Suppress GCD for a hero-talent
                    -- transform to a usable follow-up: while a castable proc shows
                    -- (override present, not on its own real CD) this icon has no real
                    -- CD, so the black swipe has no geometry -- until another ability
                    -- pushes a GCD via SetCooldown, whose geometry the PERSISTENT
                    -- black colour sweeps as a visible bar (SetCooldown changes
                    -- geometry, not colour, so nothing re-hides it). Paint fully
                    -- transparent for exactly that case, and also for a plain
                    -- hide-active spell whose swipe color never zeroes out
                    -- (e.g. Prismatic Barrier), which pins fd._hideActiveOverriding
                    -- and otherwise leaks a bare GCD once charges max out. Gated
                    -- on Suppress GCD; a spell genuinely on its own real CD keeps
                    -- the black swipe, and a charge proc mid-recharge is carved
                    -- out (its swipe IS the recharge).
                    local hideActiveAlpha = barInfo.swipeAlpha or 0.7
                    if
                        ((bd2 and bd2.suppressGCD) or (iconSettings and iconSettings.suppressGCD))
                        and spellKey
                        and C_SpellBook
                        and C_SpellBook.FindSpellOverrideByID
                        and C_Spell
                        and C_Spell.GetSpellCooldown
                    then
                        local chargeRecharging = false
                        do
                            local chargeInfo = CdmChargeInfoFor(widget, spellKey)
                            chargeRecharging = (
                                chargeInfo
                                and (chargeInfo.maxCharges or 0) > 1
                                and chargeInfo.isActive == true
                            ) or false
                        end
                        if not chargeRecharging then
                            local ovrID = C_SpellBook.FindSpellOverrideByID(spellKey)
                            local checkID = (ovrID and ovrID > 0 and ovrID ~= spellKey) and ovrID or spellKey
                            local overlayCache = C_Spell.GetSpellCooldown(checkID)
                            if overlayCache and not (overlayCache.isActive and not overlayCache.isOnGCD) then
                                hideActiveAlpha = 0
                            end
                        end
                    end
                    if not _gcdSuppressed then
                        cooldown:SetSwipeColor(0, 0, 0, mod.GCDTailAlpha(_gcdChargeTail, hideActiveAlpha))
                    end
                    if isActive then
                        frameData._hideActiveOverriding = true
                        frameData._wasActive = true
                    elseif frameData._hideActiveOverriding then
                        frameData._hideActiveOverriding = false
                        if cooldown.SetUseAuraDisplayTime then cooldown:SetUseAuraDisplayTime(true) end
                    end
                elseif isActive then
                    -- Active: swipe color (custom, class, or default #FFC660).
                    local cr, cg, callback, ca
                    if iconSettings and iconSettings.activeSwipeClassColor then
                        local _, classTok = UnitClass("player")
                        if classTok then
                            local cc = RAID_CLASS_COLORS[classTok]
                            if cc then
                                cr, cg, callback = cc.r, cc.g, cc.b
                            end
                        end
                    end
                    -- Blizzard Style: the viewer's own active swipe colour
                    -- unless a per-spell active colour is set.
                    if
                        frameData._blizzArt
                        and not cr
                        and not (iconSettings and iconSettings.activeSwipeR)
                    then
                        cr, cg, callback = 1, 0.95, 0.57
                    end
                    cr = cr or (iconSettings and iconSettings.activeSwipeR) or 1
                    cg = cg or (iconSettings and iconSettings.activeSwipeG) or 0.776
                    callback = callback or (iconSettings and iconSettings.activeSwipeB) or 0.376
                    ca = (iconSettings and iconSettings.activeSwipeA) or 0.7
                    cooldown:SetSwipeColor(cr, cg, callback, ca)
                    if frameData.tex then
                        frameData.tex:SetDesaturated(false)
                        frameData._desatNA = nil
                    end
                    frameData._wasActive = true
                else
                    -- Not active: black swipe.
                    if not _gcdSuppressed then
                        cooldown:SetSwipeColor(
                            0,
                            0,
                            0,
                            mod.GCDTailAlpha(_gcdChargeTail, barInfo.swipeAlpha or 0.7)
                        )
                    end
                    -- Desaturate When Not Active (per-spell). Symmetric, but
                    -- re-saturates only icons WE desaturated (fd._desatNA), so
                    -- turning it off never fights cdState/buff desaturation and
                    -- un-greys without waiting for the next cooldown event.
                    if frameData.tex then
                        if iconSettings and iconSettings.desatNotActive then
                            frameData.tex:SetDesaturated(true)
                            frameData._desatNA = true
                        elseif frameData._desatNA then
                            frameData.tex:SetDesaturated(false)
                            frameData._desatNA = nil
                        end
                    end
                    -- Buff ended, CD starting: re-apply the cooldown duration so
                    -- the swipe shows immediately. Once per transition, only when
                    -- the spell actually has an active cooldown.
                    if frameData._wasActive then
                        frameData._wasActive = false
                        if
                            spellKey
                            and cooldown.SetCooldownFromDurationObject
                            and C_Spell.GetSpellCooldown
                        then
                            local cooldownInfo = C_Spell.GetSpellCooldown(spellKey)
                            if cooldownInfo and cooldownInfo.isActive then
                                local durationObj = C_Spell.GetSpellCooldownDuration(spellKey)
                                if durationObj then
                                    cooldown:SetCooldownFromDurationObject(durationObj)
                                    cooldown:SetDrawSwipe(true)
                                end
                            end
                        end
                    end
                end

                -- Charge "Hide Swipe" suppresses only the recharge swipe: the
                -- active-state colored swipe IS the active overlay, so keep it
                -- while active. Inside the override guard, so no re-entry.
                if
                    mod._cdmAnyChargeStyle
                    and iconSettings
                    and iconSettings.chargeHideSwipe
                    and cooldown.SetDrawSwipe
                    and type(widget.HasVisualDataSource_Charges) == "function"
                    and widget:HasVisualDataSource_Charges()
                then
                    cooldown:SetDrawSwipe(iconSettings.activeSwipeMode ~= "none" and isActive)
                end

                -- Active glow + border (per-spell). Extracted so the Fake-Active
                -- engine can drive the same overlays from its own ticker, sharing
                -- fd._activeGlowOn / fd._activeBorderOn. Touches only our
                -- overlays, never the Blizzard swipe: safe from any context.
                mod.ApplyActiveOverlays(widget, frameData, iconSettings, isActive, bd2)

                -- Max Stacks Glow: "at max" = no recharge running
                -- (GetSpellCharges().isActive; secret currentCharges never read).
                -- Consuming a charge fires this swipe hook, refilling to max
                -- fires Cooldown:Clear. Register for charge events (the only
                -- catch for refill-to-max) and eval now so a SPEND is immediate.
                if
                    mod._cdmAnyMaxStacksGlow
                    and iconSettings
                    and iconSettings.maxStacksGlow
                    and iconSettings.maxStacksGlow > 0
                then
                    WatchMaxStacksFrame(widget, frameData)
                    EvalMaxStacksFrame(widget, frameData)
                elseif frameData._maxStacksGlowOn then
                    ApplyMaxStacksGlow(widget, frameData, nil, false) -- setting cleared -> off
                    mod._maxStacksWatch[widget] = nil
                end

                frameData._gcdSwipeSuppressed = _gcdSuppressed
                frameData._isProcessingOverride = false
            end)
            hooksecurefunc(cooldown, "SetDrawSwipe", function(_, shouldShow)
                if frameData._isProcessingOverride then return end
                -- Hosted buff: never toggle its duration swipe from our cd logic.
                if frameData._isBuffViewerFrame then return end
                -- Charges/Stacks Only (No Icon): art is hidden, so a swipe would
                -- draw a dark pie over empty space on every re-push. Suppress
                -- instead of the force-true below, ahead of the charge-style call
                -- (with no icon there is nothing for an edge to decorate).
                if frameData._osnOn then
                    if shouldShow then
                        frameData._isProcessingOverride = true
                        cooldown:SetDrawSwipe(false)
                        frameData._isProcessingOverride = false
                    end
                    return
                end
                -- Charge spells get the baseline edge (+ per-spell Hide Swipe):
                -- ApplyCdmChargeStyle returns true and owns swipe + edge for
                -- them; non-charge frames fall to the force-true below.
                frameData._isProcessingOverride = true
                local handled = ApplyCdmChargeStyle(widget, cooldown)
                -- Bar-wide Show Cooldown Edge (non-charge frames; charge frames
                -- get their edge from ApplyCdmChargeStyle). GCD suppression
                -- drops an edge we applied, tracked so the disabled/default
                -- path never issues a redundant SetDrawEdge.
                if not handled and frameData._edgeFeatureOn and cooldown.SetDrawEdge then
                    if not frameData._gcdSwipeSuppressed then
                        local fcEdge = _ecmeFC[widget]
                        ApplyCdmEdge(cooldown, fcEdge and fcEdge.barKey)
                        frameData._edgeApplied = true
                    elseif frameData._edgeApplied then
                        cooldown:SetDrawEdge(false)
                        frameData._edgeApplied = nil
                    end
                end
                frameData._isProcessingOverride = false
                if handled then return end
                -- Per-spell Hide CD Swipe (non-charge): keep the swipe suppressed
                -- across Blizzard re-pushes. Gated (costs nothing until enabled),
                -- resolved from our own flags (secret-safe) in BOTH stores:
                -- per-bar spellSettings and preset customActiveStates.
                if mod._cdmAnyHideCDSwipe then
                    local ssH = mod._ResolveCdmSS(widget)
                    local hideSw = ssH and ssH.hideCDSwipe
                    if not hideSw and mod.GetEffectiveCustomActiveState then
                        local fcH = _ecmeFC[widget]
                        local sidH = fcH and fcH.spellID
                        if sidH then
                            local casH = mod.GetEffectiveCustomActiveState(sidH)
                            hideSw = casH and casH.hideCDSwipe
                        end
                    end
                    if hideSw then
                        if shouldShow then
                            frameData._isProcessingOverride = true
                            cooldown:SetDrawSwipe(false)
                            frameData._isProcessingOverride = false
                        end
                        return
                    end
                end
                if shouldShow then return end
                frameData._isProcessingOverride = true
                cooldown:SetDrawSwipe(true)
                frameData._isProcessingOverride = false
            end)
            -- Cooldown edge enforcement. Re-assert the bar-wide Blizzard edge, or
            -- per-spell Hide Recharge Edge, across Blizzard cooldown re-pushes.
            if cooldown.SetDrawEdge then
                hooksecurefunc(cooldown, "SetDrawEdge", function(_, shouldShow)
                    if frameData._isProcessingOverride then return end
                    -- Edge-off pushes only matter to the bar-wide edge re-assert
                    -- (every other branch below acts on show=true alone), so the
                    -- disabled/default path keeps its zero-cost early-out.
                    if not shouldShow and not frameData._edgeFeatureOn then return end
                    if frameData._isBuffViewerFrame then return end
                    -- No icon art: no recharge edge, charge or not. Blizzard
                    -- re-enables it on every re-push, so this must be in the hook.
                    if frameData._osnOn then
                        if shouldShow then
                            frameData._isProcessingOverride = true
                            cooldown:SetDrawEdge(false)
                            frameData._isProcessingOverride = false
                        end
                        return
                    end
                    local hasChargeSource = type(widget.HasVisualDataSource_Charges) == "function"
                        and widget:HasVisualDataSource_Charges()
                    if hasChargeSource and mod._cdmAnyChargeStyle then
                        local iconSettings = mod._ResolveCdmSS(widget)
                        if iconSettings and iconSettings.hideRechargeEdge then
                            if shouldShow then
                                frameData._isProcessingOverride = true
                                cooldown:SetDrawEdge(false)
                                frameData._isProcessingOverride = false
                            end
                            return
                        end
                    end
                    -- Bar-wide Show Cooldown Edge: re-assert across Blizzard's
                    -- own edge-off pushes (stock disables it on every non-charge
                    -- cooldown update).
                    if frameData._edgeFeatureOn and not frameData._gcdSwipeSuppressed then
                        local fcEdge = _ecmeFC[widget]
                        frameData._isProcessingOverride = true
                        ApplyCdmEdge(cooldown, fcEdge and fcEdge.barKey)
                        frameData._isProcessingOverride = false
                        frameData._edgeApplied = true
                    end
                end)
            end
            -- Non-charge cooldown re-assert. Blizzard's CooldownViewer zeroes the
            -- widget for some spells partway through their REAL cooldown and never
            -- re-pushes -- e.g. DH placement sigils (Flame/Misery/Silence, not Spite)
            -- clear when the sigil activates (~1s in) while GetSpellCooldown still
            -- reports the full 30s, leaving no swipe for the rest of the CD. Charge
            -- spells use the charge re-arm below. Gated tightly to that exact failure
            -- (widget cleared to ~0 while a genuine non-GCD cooldown is live), so it never fights a GCD swipe or aura-display time (both non-zero).
            local function ReAssertRealCooldown()
                if frameData._isProcessingOverride then return end
                -- Always-Show placeholders deliberately keep their widget cleared
                -- (never arm a 0-duration swipe); never re-assert onto one.
                if frameData._isBuffViewerFrame or widget._isPlaceholderFrame then return end
                -- Charge spells: owned by the charge re-arm path.
                if
                    type(widget.HasVisualDataSource_Charges) == "function"
                    and widget:HasVisualDataSource_Charges()
                then
                    return
                end
                if not (C_Spell and C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldownDuration) then
                    return
                end
                local iconCache = _ecmeFC[widget]
                local spellKey = iconCache and iconCache.spellID
                if not spellKey then return end
                -- Act only when the widget is cleared to ~0 (never fight a real
                -- cooldown, GCD, or aura-display time). The secret check MUST
                -- precede any truthiness/comparison (a secret errors on either);
                -- a secret duration cannot prove "cleared", so fail closed (the
                -- sigil failure moment reads a clean 0, so the fix still runs).
                --
                -- SECOND PROOF, needed because the fail-closed above is permanent in
                -- instanced combat (the duration reads secret there, so this function
                -- could never act -- see CdmStaleLinkedSpell). A stale linked spell
                -- means Blizzard clears this widget on EVERY refresh, so there is
                -- nothing to fight and no duration read is required to know it.
                --
                -- These free reads run BEFORE the spell queries below: every Clear on
                -- every non-charge icon lands here, and the cooldown query allocates a
                -- table per call, so the common exits (secret duration in instanced
                -- combat, a widget still carrying a real swipe) must cost no query.
                local staleLink = CdmStaleLinkedSpell(widget)
                if not staleLink and cooldown.GetCooldownDuration then
                    local success, curDur = pcall(cooldown.GetCooldownDuration, cooldown)
                    if not success then return end
                    if issecretvalue and issecretvalue(curDur) then return end
                    if curDur and curDur > 100 then return end
                end
                local effectiveId = spellKey
                if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
                    local overrideId = C_SpellBook.FindSpellOverrideByID(spellKey)
                    if overrideId and overrideId > 0 and overrideId ~= spellKey then
                        effectiveId = overrideId
                    end
                end
                -- Only re-assert for a genuine, non-GCD cooldown still running.
                -- isActive / isOnGCD are clean bools (read bare elsewhere).
                local cooldownInfo = C_Spell.GetSpellCooldown(effectiveId)
                    or C_Spell.GetSpellCooldown(spellKey)
                if not (cooldownInfo and cooldownInfo.isActive and not cooldownInfo.isOnGCD) then return end
                local durationObj = C_Spell.GetSpellCooldownDuration(effectiveId)
                    or C_Spell.GetSpellCooldownDuration(spellKey)
                if not durationObj then return end
                frameData._isProcessingOverride = true
                if cooldown.SetUseAuraDisplayTime then cooldown:SetUseAuraDisplayTime(false) end
                cooldown:SetCooldownFromDurationObject(durationObj)
                if staleLink then
                    -- Blizzard's expired branch never calls SetSwipeColor, so the
                    -- widget still carries whatever colour was painted last. For an
                    -- aura-tracking icon that is the ACTIVE colour from the aura
                    -- window, and it then renders over the cooldown we just armed --
                    -- field-seen as "the swipe was still yellow". Repaint the resting
                    -- cooldown colour, the same black the SetSwipeColor hook's
                    -- not-active branch uses (the per-spell Cooldown Swipe Color only
                    -- applies to buff-viewer frames, which never reach here).
                    -- This also releases a Suppress-GCD alpha-0 that can be stuck for
                    -- the same reason -- what we just armed is a real cooldown, never
                    -- a GCD. Mirrors ReArmChargeRecharge, which repaints for exactly
                    -- this reason on the charge path.
                    -- Gated to the stale case on purpose: the placement-sigil case
                    -- reaches here with a colour Blizzard has kept current, so it is
                    -- left alone. Bar data is resolved LIVE rather than from the
                    -- decorate-time closure, since pooled frames decorate once.
                    local bkS = iconCache.barKey
                    local bdS = bkS and barMap and barMap[bkS]
                    cooldown:SetSwipeColor(0, 0, 0, (bdS and bdS.swipeAlpha) or 0.7)
                end
                -- Only geometry was wiped (Blizzard's clear leaves draw-swipe on),
                -- so re-arming the duration restores the swipe. Deliberately NOT
                -- forcing SetDrawSwipe(true): under the override guard that would
                -- bypass per-spell "Hide CD Swipe".
                frameData._isProcessingOverride = false
            end

            -- Charge-spell recharge swipe restore. The swipe renders from the
            -- widget's armed duration, NOT the SetDrawSwipe flag (which only
            -- gates an existing swipe). When one charge refills while another
            -- still recharges Blizzard calls Cooldown:Clear(), wiping the armed
            -- duration, so SetDrawSwipe(true) has no geometry and the valid
            -- recharge swipe vanishes: re-arm from the charge recharge duration.
            -- Charge spells only; non-charge frames route to the re-assert above.
            hooksecurefunc(cooldown, "Clear", function()
                if frameData._isProcessingOverride then return end
                -- HasVisualDataSource_Charges is a clean bool present only on
                -- Blizzard CooldownViewer item frames, so this also excludes our
                -- custom (trinket/racial/item) and aura buff frames.
                local hasCharges = type(widget.HasVisualDataSource_Charges) == "function"
                    and widget:HasVisualDataSource_Charges()
                if not hasCharges then
                    ReAssertRealCooldown()
                    return
                end
                local iconCache = _ecmeFC[widget]
                local spellKey = iconCache and iconCache.spellID
                if
                    not spellKey
                    or not C_Spell
                    or not C_Spell.GetSpellCooldown
                    or not C_Spell.GetSpellChargeDuration
                then
                    return
                end
                -- Resolve the override ID for transformed spells BEFORE querying
                -- cooldown state, so replacements report against the live spell.
                local effectiveId = spellKey
                if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
                    local overrideId = C_SpellBook.FindSpellOverrideByID(spellKey)
                    if overrideId and overrideId > 0 and overrideId ~= spellKey then
                        effectiveId = overrideId
                    end
                end
                -- isActive / isOnGCD are clean bools. Only re-arm while genuinely
                -- recharging AND not merely on GCD: a GCD-tail race can report
                -- isActive with a degenerate charge duration, and arming a 0,0
                -- cooldown strobes the swipe. All charges back (isActive false):
                -- leave cleared so the swipe correctly disappears.
                -- Max Stacks Glow: Clear fires on every charge refill (incl. to
                -- max), so re-eval from GetSpellCharges().isActive (clean, false
                -- only at max) and the glow lights as the last charge returns.
                if mod._cdmAnyMaxStacksGlow then
                    local bkm = iconCache and iconCache.barKey
                    local ssm = bkm and ResolveSpellSettings(widget, spellKey, false) or nil
                    if ssm and ssm.maxStacksGlow and ssm.maxStacksGlow > 0 then
                        WatchMaxStacksFrame(widget, frameData)
                        EvalMaxStacksFrame(widget, frameData)
                    end
                end
                local cooldownInfo = C_Spell.GetSpellCooldown(effectiveId)
                local cdActive = cooldownInfo and cooldownInfo.isActive and not cooldownInfo.isOnGCD
                -- Charge-in-hand Hide-Active window: GetSpellCooldown().isActive
                -- is false while a castable charge remains, so the cd gate above
                -- never re-arms and Blizzard's per-aura-refresh wipe leaves the
                -- swipe blank. Re-arm off the clean recharge flag instead, ONLY
                -- inside our Hide-Active override so non-override charge spells
                -- keep Blizzard's native display. currentCharges never read.
                local chargeActive = frameData._hideActiveOverriding
                    and (CdmChargeInfoFor(widget, spellKey) or {}).isActive == true
                if not (cdActive or chargeActive) then return end
                -- Re-derive the recharge duration. The duration object is opaque,
                -- fed straight to the widget and never inspected: secret-safe.
                local durationObj = C_Spell.GetSpellChargeDuration(effectiveId)
                if not durationObj and effectiveId ~= spellKey then
                    durationObj = C_Spell.GetSpellChargeDuration(spellKey)
                end
                if not durationObj then return end
                frameData._isProcessingOverride = true
                if cooldown.SetUseAuraDisplayTime then cooldown:SetUseAuraDisplayTime(false) end
                cooldown:SetCooldownFromDurationObject(durationObj)
                -- Baseline charge edge (+ per-spell Hide Swipe) on the re-arm.
                ApplyCdmChargeStyle(widget, cooldown)
                frameData._isProcessingOverride = false
            end)
            -- During the Hide-Active window Blizzard re-pushes the widget for a
            -- charge-in-hand spell via SetCooldownFromDurationObject (aura
            -- display) and SetUseAuraDisplayTime -- NOT plain SetCooldown -- and
            -- those pushes wipe the recharge we armed (Clear/SetDesaturated fire
            -- far too rarely to keep up). Re-assert on those two real drivers,
            -- gated to EXACTLY (charge frame + Hide-Active window + recharge
            -- running) = no-op otherwise; _isProcessingOverride blocks recursion.
            local function ReArmChargeRecharge()
                if frameData._isProcessingOverride then return end
                -- Two field reads and nothing else. This runs from the SetCooldown
                -- / SetCooldownFromDurationObject / SetUseAuraDisplayTime hooks, so
                -- it fires for EVERY icon on EVERY cooldown push -- every GCD the
                -- player triggers. Neither entry can be live without one of these
                -- set, so bail before touching the frame or any API.
                if not (frameData._hideActiveOverriding or frameData._gcdChargeTailArmed) then return end
                local iconCache = _ecmeFC[widget]
                local spellKey = iconCache and iconCache.spellID
                if
                    not spellKey
                    or not C_Spell
                    or not C_Spell.GetSpellCharges
                    or not C_Spell.GetSpellChargeDuration
                then
                    return
                end
                -- Hosted buff / custom buff frames are excluded here for the same
                -- reason the SetSwipeColor and Clear hooks exclude them: their
                -- cooldown widget is showing an AURA, and arming a spell recharge
                -- over it would overwrite the duration they exist to display.
                if frameData._isBuffViewerFrame or widget._isCustomBuffFrame then return end
                -- Split from the value: "false" and "the frame has no such method"
                -- are different states, and entry B needs the first. Preset, racial,
                -- custom-spell and trinket frames are ours rather than CooldownViewer
                -- items and have no data source at all, which the sibling Clear hook
                -- relies on as an exclusion -- treating that as "at zero charges"
                -- would let them into a branch written for viewer items.
                local isViewerItem = type(widget.HasVisualDataSource_Charges) == "function"
                local hasCharges = isViewerItem and widget:HasVisualDataSource_Charges()
                -- ENTRY A (original): the Hide-Active override window, where
                -- Blizzard's aura pushes wipe the recharge we armed.
                local entryA = (frameData._hideActiveOverriding and hasCharges) or false
                -- ENTRY B: the GCD has taken the icon over at the TAIL of a
                -- recharge. Measured in game: once the remaining recharge falls
                -- below one GCD length, Blizzard re-points the widget at the GCD
                -- (SetCooldown fires, GetSpellCooldown().isOnGCD flips true), and
                -- HasVisualDataSource_Charges is false throughout because the
                -- player is at ZERO charges -- so entry A cannot fire. Suppress
                -- GCD then does its job and alpha-0s that swipe, and the last
                -- second of the recharge goes blank, snapping back only when the
                -- charge lands. That is the reported "0 -> 1 breaks the cooldown
                -- swipe", and hiding was never the right answer: the recharge is
                -- still running and is what the player is watching. Re-arm the
                -- real recharge so the swipe keeps showing the truth.
                --
                -- fd._gcdChargeTailArmed is the SetSwipeColor hook's own verdict on
                -- that state, published one call earlier in the same refresh, so
                -- this path re-derives nothing.
                --
                -- Suppress GCD is re-checked here rather than trusted from the
                -- latch. Blizzard's expired branch skips SetSwipeColor entirely and
                -- frames are pooled, so the latch can survive into a frame or a bar
                -- it was not set for; requiring the setting again bounds a stale
                -- latch to "re-arm a charge spell that is genuinely recharging",
                -- which is the intended action anyway.
                local entryB = false
                if
                    not entryA
                    and isViewerItem
                    and not hasCharges
                    and frameData._gcdChargeTailArmed == true
                then
                    local buffBarKey = iconCache.barKey
                    local bdB = buffBarKey and barMap and barMap[buffBarKey]
                    entryB = (bdB and bdB.suppressGCD and true) or false
                    -- Per-spell Suppress GCD: same re-check contract as the bar
                    -- toggle. Session-gated so unused installs never resolve.
                    if not entryB and mod._cdmAnySuppressGcd then
                        local ssB = mod._ResolveCdmSS and mod._ResolveCdmSS(widget)
                        entryB = (ssB and ssB.suppressGCD and true) or false
                    end
                end
                if not (entryA or entryB) then return end
                local effectiveId = spellKey
                if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
                    local overrideId = C_SpellBook.FindSpellOverrideByID(spellKey)
                    if overrideId and overrideId > 0 and overrideId ~= spellKey then
                        effectiveId = overrideId
                    end
                end
                -- Charge spell with a recharge genuinely running. maxCharges > 1 is
                -- the charge-spell test every other carve-out in this file uses --
                -- a 1-charge spell reports charge data too, and re-arming one that
                -- Suppress GCD had just alpha-0'd would repaint it at full alpha in
                -- the same refresh. Both fields are clean; the secret
                -- currentCharges is never read.
                local chargeInfo = CdmChargeInfoFor(widget, spellKey)
                if not (chargeInfo and (chargeInfo.maxCharges or 0) > 1 and chargeInfo.isActive == true) then
                    return
                end
                local durationObj = C_Spell.GetSpellChargeDuration(effectiveId)
                if not durationObj and effectiveId ~= spellKey then
                    durationObj = C_Spell.GetSpellChargeDuration(spellKey)
                end
                if not durationObj then return end
                frameData._isProcessingOverride = true
                if cooldown.SetUseAuraDisplayTime then cooldown:SetUseAuraDisplayTime(false) end
                cooldown:SetCooldownFromDurationObject(durationObj)
                -- No-op on the entry-B path by construction: ApplyCdmChargeStyle
                -- bails unless HasVisualDataSource_Charges is true, and entry B
                -- requires it false. That is correct rather than an oversight --
                -- Hide Swipe (Charges) and Hide Recharge Edge already do not apply
                -- while the widget is off the charge source, so the tail now
                -- matches the rest of the zero-charge window instead of differing
                -- from it. Entry A still needs the call.
                ApplyCdmChargeStyle(widget, cooldown)
                -- We have just re-armed the REAL recharge, so whatever is now
                -- displayed is the recharge -- never a GCD. Suppress-GCD's alpha-0
                -- swipe (set while isOnGCD, e.g. right after pressing ANOTHER
                -- ability) must not stick here or the recharge stays invisible.
                --
                -- Black is only unconditionally right on the entry-A path, which by
                -- definition runs inside the Hide-Active window. Entry B can reach
                -- an icon whose active state paints a COLOURED swipe, and this write
                -- sits under _isProcessingOverride so the SetSwipeColor hook cannot
                -- put that colour back -- hence the active check. When the icon is
                -- active, leaving the colour alone is correct: the next refresh
                -- repaints it, and the geometry we just armed is what mattered.
                local bkA = iconCache.barKey
                local bdA = bkA and barMap and barMap[bkA]
                if entryA or not CdmFrameIsActive(widget) then
                    cooldown:SetSwipeColor(0, 0, 0, (bdA and bdA.swipeAlpha) or 0.7)
                end
                frameData._isProcessingOverride = false
            end
            if cooldown.SetCooldownFromDurationObject then
                hooksecurefunc(cooldown, "SetCooldownFromDurationObject", ReArmChargeRecharge)
                -- Also catch the placement-sigil case where Blizzard clears the
                -- widget via a zero-duration SetCooldownFromDurationObject rather
                -- than Clear(). The guard blocks recursion and the ~0 duration
                -- gate makes this a no-op for normal pushes.
                hooksecurefunc(cooldown, "SetCooldownFromDurationObject", ReAssertRealCooldown)
            end
            if cooldown.SetUseAuraDisplayTime then
                hooksecurefunc(cooldown, "SetUseAuraDisplayTime", ReArmChargeRecharge)
            end
            -- Pressing ANOTHER ability pushes the GCD onto this frame via
            -- SetCooldown (not the aura-display setters), replacing the charge
            -- recharge geometry -- in the Hide-Active window that wipes the real
            -- recharge until the active state ends, so re-arm on SetCooldown too.
            -- ReArmChargeRecharge fully self-gates and is re-entry guarded: a
            -- no-op for normal cooldowns and outside the override window.
            if cooldown.SetCooldown then hooksecurefunc(cooldown, "SetCooldown", ReArmChargeRecharge) end
        end
        -- Hook SetDesaturated AND SetDesaturation on the icon texture (Blizzard
        -- calls these every cooldown tick): while overriding the CD model (hide
        -- active state), re-apply the real CD duration so it cannot revert.
        if frameData.tex and not frameData._desatOverrideHooked then
            frameData._desatOverrideHooked = true
            local function onDesatChange()
                if frameData._isProcessingOverride then return end
                -- Two owners of this path now. The Hide-Active override is the
                -- original one. The second is the stale-linked-spell state, where
                -- Blizzard re-clears the widget AND re-saturates the icon on every
                -- refresh -- so the repair has to ride the same per-tick driver to
                -- survive, and the body below already does exactly the right thing
                -- for it: it re-arms the cooldown from OUR spell id and then sets
                -- the desaturation from that same id's real cooldown state.
                -- Cheap-first: the flag is one lookup, the helper two more.
                if not (frameData._hideActiveOverriding or CdmStaleLinkedSpell(widget)) then return end
                frameData._isProcessingOverride = true
                local cooldownWidget = frameData.cooldown
                local iconCache = _ecmeFC[widget]
                local spellKey = iconCache and iconCache.spellID
                if spellKey and cooldownWidget then
                    if cooldownWidget.SetUseAuraDisplayTime then
                        cooldownWidget:SetUseAuraDisplayTime(false)
                    end
                    if cooldownWidget.SetCooldownFromDurationObject then
                        -- Effective spell ID: for transforms the charge/cooldown
                        -- APIs report against the override ID, not the base.
                        -- Query override first, fall back to base.
                        local effectiveId = spellKey
                        if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
                            local overrideId = C_SpellBook.FindSpellOverrideByID(spellKey)
                            if overrideId and overrideId > 0 and overrideId ~= spellKey then
                                effectiveId = overrideId
                            end
                        end
                        local hasCharges = type(widget.HasVisualDataSource_Charges) == "function"
                            and widget:HasVisualDataSource_Charges()
                        local durationObj
                        if hasCharges and C_Spell.GetSpellChargeDuration then
                            durationObj = C_Spell.GetSpellChargeDuration(effectiveId)
                            if not durationObj and effectiveId ~= spellKey then
                                durationObj = C_Spell.GetSpellChargeDuration(spellKey)
                            end
                        end
                        if not durationObj and C_Spell.GetSpellCooldownDuration then
                            durationObj = C_Spell.GetSpellCooldownDuration(effectiveId)
                            if not durationObj and effectiveId ~= spellKey then
                                -- Borrow the base spell's cooldown ONLY when the live
                                -- override is itself on a real CD (a cosmetic transform
                                -- sharing the base cooldown -- the fallback's purpose)
                                -- OR its cooldown is unknown (oc nil). A hero-talent
                                -- transform to a CASTABLE follow-up reports no real CD
                                -- and must NOT inherit the base's remaining cooldown
                                -- (that painted the base CD swipe over a usable proc);
                                -- leaving durObj nil takes the same no-swipe path as a
                                -- proc without a real CD. Only a CONFIRMED- castable
                                -- proc suppresses the borrow. Mirrors the desat guard
                                -- below so swipe and saturation agree. isActive/isOnGCD
                                -- are clean bools.
                                local overlayCache = C_Spell.GetSpellCooldown
                                    and C_Spell.GetSpellCooldown(effectiveId)
                                if
                                    not overlayCache or (overlayCache.isActive and not overlayCache.isOnGCD)
                                then
                                    durationObj = C_Spell.GetSpellCooldownDuration(spellKey)
                                end
                            end
                        end
                        if durationObj then cooldownWidget:SetCooldownFromDurationObject(durationObj) end
                    end
                end
                -- Desaturate only if actually on cooldown; procs without a real
                -- CD stay saturated. Filter GCDs like the suppressGCD check. Ask
                -- the EFFECTIVE spell, override first: a transform's real cooldown
                -- ticks on the OVERRIDE id while the base reports none (measured:
                -- base isActive=false, override isActive=true isOnGCD=false), so a
                -- base-only read verdicts "not on cooldown" and never greys. Fall
                -- back to the base ONLY when the override query returns nothing
                -- (unknown), never on a clean "not active" -- that is the
                -- castable-proc case and must win.
                local effID2 = spellKey
                if spellKey and C_SpellBook and C_SpellBook.FindSpellOverrideByID then
                    local overrideId = C_SpellBook.FindSpellOverrideByID(spellKey)
                    if overrideId and overrideId > 0 and overrideId ~= spellKey then effID2 = overrideId end
                end
                local cdInfo2 = effID2
                    and C_Spell.GetSpellCooldown
                    and (
                        C_Spell.GetSpellCooldown(effID2)
                        or (effID2 ~= spellKey and C_Spell.GetSpellCooldown(spellKey))
                        or nil
                    )
                local onRealCD = cdInfo2 and cdInfo2.isActive and not cdInfo2.isOnGCD
                -- Charge spells report cooldown isActive mid-recharge even with a
                -- castable charge left, which would wrongly desaturate a usable
                -- icon. currentCharges is SECRET in this tainted hook, so the
                -- usable-charge verdict has to come from somewhere else -- see
                -- the guard below.
                -- The charge-SPELL test is static charge data, NOT the
                -- HasVisualDataSource_Charges flag: that one is documented three
                -- times in this file as answering "is this icon drawing its recharge
                -- right now", which is false at full charges and during a GCD, so
                -- gating the whole branch on it made it dead code. maxCharges is
                -- stable and clean; the secret currentCharges is never read.
                -- Resolve it through Blizzard's own accessor rather than a base-ID
                -- read: CdmChargeInfoFor documents the two disagreeing on override
                -- spells (captured on Blink 1953 -> Shimmer 212653), where a base
                -- read reports the charge-less base, so this test came back false
                -- and the guard never ran on a 2-charge ability. The swipe guard
                -- already resolves charges this way and the two verdicts must agree.
                local chargeCI = CdmChargeInfoFor(widget, spellKey)
                local maxCh = chargeCI and chargeCI.maxCharges
                local isChargeSpell = type(maxCh) == "number"
                    and not (issecretvalue and issecretvalue(maxCh))
                    and maxCh > 1
                local outOfCharges
                if onRealCD and isChargeSpell then
                    -- Preferred signal: Blizzard's own charge visual-data-source
                    -- flag. isOnActualCooldown below is derived from the cooldown
                    -- startTime + duration, both SECRET inside instanced content,
                    -- so it comes back unreadable from this tainted hook the
                    -- moment a key starts -- the guard then set nothing and a
                    -- banked charge desaturated. Fresh login looked fine because
                    -- nothing was secret yet. wasSetFromCharges is a plain literal
                    -- assigned inside an untainted branch, so it survives that,
                    -- and RefreshData clears it and CacheCooldownValues re-sets it
                    -- immediately before the SetDesaturated call this hooks, so it
                    -- is never stale here.
                    -- Only TRUE is informative: Blizzard sets it for
                    -- "cooldownStartTime > 0 and currentCharges > 0", so false is
                    -- equally what a full-charge icon and an aura-driven one
                    -- report -- those keep falling through to the read below, which
                    -- is why this cannot re-break greying at zero charges.
                    -- Read the field, falling back to the getter: a past field
                    -- dump on a 12.0 client reported the getter as nil on these
                    -- frames while isOnActualCooldown beside it read fine, so
                    -- take whichever of the two this client actually carries.
                    local fromCharges = widget.wasSetFromCharges
                    if
                        type(fromCharges) ~= "boolean"
                        and type(widget.HasVisualDataSource_Charges) == "function"
                    then
                        fromCharges = widget:HasVisualDataSource_Charges()
                    end
                    if
                        type(fromCharges) == "boolean"
                        and not (issecretvalue and issecretvalue(fromCharges))
                        and fromCharges
                    then
                        outOfCharges = false
                    end
                    if type(outOfCharges) ~= "boolean" then
                        local actualCD = widget.isOnActualCooldown
                        if not issecretvalue or not issecretvalue(actualCD) then
                            if actualCD == false then
                                outOfCharges = false
                            elseif actualCD == true then
                                outOfCharges = true
                            end
                        end
                    end
                end
                if outOfCharges == false then onRealCD = false end
                -- No clear-only transform guard here: asking the override first
                -- already answers the castable-proc case. Such a guard can turn
                -- greying off but never on, so an icon whose cooldown lives on
                -- the override could never grey -- do not reintroduce one.
                frameData.tex:SetDesaturated(onRealCD or false)
                frameData._isProcessingOverride = false
            end
            hooksecurefunc(frameData.tex, "SetDesaturated", onDesatChange)
            if frameData.tex.SetDesaturation then
                hooksecurefunc(frameData.tex, "SetDesaturation", onDesatChange)
            end
        end
        -- Swipe direction baseline by FRAME kind, not just bar kind: a buff frame
        -- (or hosted-buff placeholder) fills like a buff even on a CD/utility bar.
        -- Decoration is once-per-frame while Blizzard POOLS frames, so record the
        -- kind in fd._revKind and let the claim loops re-assert on kind change,
        -- else a frame decorated for the wrong family keeps that direction all
        -- session (buffs randomly reversed by pool history).
        local isBuff = (
            barInfo.barType == "buffs"
            or barInfo.key == "buffs"
            or barInfo.barType == "custom_buff"
            or frameData._isBuffViewerFrame
            or widget._isPlaceholderFrame
        )
                and true
            or false
        -- Per-spell Reverse Swipe flips the baseline (see EffectiveReverseSwipe):
        -- writing the bare kind here undid the setting on every reanchor.
        local revEff = mod.EffectiveReverseSwipe(widget, barInfo.key, isBuff)
        frameData.cooldown:SetReverse(revEff)
        frameData._revKind = revEff

        -- Clear IS hooked above (_swipeColorHooked block) to restore the recharge swipe
        -- on charge spells, and SetCooldown too (ReArmChargeRecharge) so an off-GCD
        -- push cannot wipe the recharge in the Hide-Active window. A hooksecurefunc
        -- post-hook does not taint the secure caller; taint would stick only if the
        -- hook BODY wrote a Blizzard frame field (isActive, allowAvailableAlert) or
        -- called Show/Hide/SetAlpha on a Blizzard frame. Neither does: they read clean
        -- getters and call pure cooldown-widget setters (SetUseAuraDisplayTime /
        -- SetCooldownFromDurationObject / SetDrawSwipe / SetSwipeColor), and all hook
        -- state lives on the external fd table, never on the Blizzard frame.

        -- Cooldown State Effect: separate additive SetDesaturated hook.
        -- Blizzard calls it on every CD tick AND on CD end -- the right event
        -- for both transitions. Independent from onDesatChange (hideActive).
        if frameData.tex and not frameData._cdStateHooked then
            frameData._cdStateHooked = true
            hooksecurefunc(frameData.tex, "SetDesaturated", function()
                if frameData._isProcessingOverride then return end
                local iconCache = _ecmeFC[widget]
                local spellKey = iconCache and iconCache.spellID
                local barKeyOf = iconCache and iconCache.barKey
                if not spellKey or not barKeyOf then return end
                if barKeyOf:sub(1, 7) == "__ghost" then return end
                -- FocusKick icon alpha is owned by SetFocusKickAlpha only.
                if barKeyOf == mod.FOCUSKICK_BAR_KEY then return end
                -- Preset frames (trinket/racial/potion/custom spell) own their cd-state
                -- through the Fake-Active engine, which reads the ITEM/racial cooldown.
                -- GetSpellCooldown cannot read a negative item key, so this spell path
                -- always sees the item as ready and would re-light the shared
                -- glowOverlay every desat tick while on cooldown. Hand off cleanly
                -- (clear any glow we owned).
                if mod.PresetHasCdState and mod.PresetHasCdState(widget) then
                    if frameData._cdStateGlowOn then
                        mod.StopCdGlow(frameData)
                        frameData._cdStateGlowOn = false
                        -- The Fake-Active path tracks this overlay via its own
                        -- flag; clear it too so its next tick re-asserts the
                        -- glow we just stopped (else it thinks the glow is
                        -- still on and a ready preset stays dark).
                        frameData._presetCdGlowOn = false
                    end
                    return
                end
                local iconSettings = ResolveSpellSettings(widget, spellKey, false)
                -- The effect is a hide (cse) and a glow, each run on its own:
                -- the hide part below never returns before the glow part.
                local cooldownEdge, glow = mod.CdStateOf(iconSettings, widget)
                -- The hide effects run as their base mode plus flags
                -- (ns.CD_STATE_HIDE: Shift Icons, Hidden Until Usable, Hidden
                -- Outside Form/Stance), so every comparison below is unchanged.
                local m = cooldownEdge and mod.CD_STATE_HIDE[cooldownEdge]
                local cseShift, cseUsable, cseForm
                if m then
                    cooldownEdge, cseShift, cseUsable, cseForm = m.base, m.shift, m.usable, m.form
                end
                -- Stance Bar (CludesUICdmStanceBar.lua): one more hide reason. Alone,
                -- it runs as Hidden (On CD) with the cooldown never read.
                local stance = mod.CdmStanceBarOf(iconSettings, widget)
                local stanceOnly = false
                if
                    stance
                    and cooldownEdge ~= "hiddenOnCD"
                    and cooldownEdge ~= "hiddenReady"
                    and cooldownEdge ~= "lowerAlphaOnCD"
                then
                    cooldownEdge, stanceOnly = "hiddenOnCD", true
                end
                if not cooldownEdge and not glow then
                    if frameData._cdStateGlowOn then
                        mod.StopCdGlow(frameData)
                        frameData._cdStateGlowOn = false
                    end
                    -- A preset's cdState lives in customActiveStates (Fake-Active
                    -- engine), not per-bar spellSettings -- clearing its hidden flag
                    -- here would flash it visible every desat tick. Those frames
                    -- already returned through the PresetHasCdState hand-off above,
                    -- so no re-check is needed on this path.
                    if iconCache and iconCache._cdStateHidden then iconCache._cdStateHidden = false end
                    if iconCache and iconCache._cdStateShiftHidden and mod.SetCdStateShiftHidden then
                        mod.SetCdStateShiftHidden(iconCache, false)
                    end
                    return
                end
                -- Clear stale hidden state while no hide effect runs (a glow
                -- alone; lowerAlphaOnCD is alpha-owning like the hidden modes,
                -- so exclude it).
                if
                    cooldownEdge ~= "hiddenOnCD"
                    and cooldownEdge ~= "hiddenReady"
                    and cooldownEdge ~= "lowerAlphaOnCD"
                then
                    if iconCache and iconCache._cdStateHidden then
                        iconCache._cdStateHidden = false
                        local bd2 = barMap and barMap[barKeyOf]
                        widget:SetAlpha(mod.IconShownAlpha(iconCache, bd2))
                    end
                    -- (cse is already normalized, so Shift variants never land here.)
                    if iconCache and mod.SetCdStateShiftHidden then
                        mod.SetCdStateShiftHidden(iconCache, false)
                    end
                end
                -- Hidden / lower-alpha modes: hand off to the shared deferred
                -- evaluator (ArmCdStateEval -- see its comment for the
                -- one-frame wait). cse is normalized, so Shift variants arrive
                -- as their base mode plus cseShift.
                if
                    cooldownEdge == "hiddenOnCD"
                    or cooldownEdge == "hiddenReady"
                    or cooldownEdge == "lowerAlphaOnCD"
                then
                    ArmCdStateEval(
                        widget,
                        frameData,
                        cooldownEdge,
                        cseShift,
                        (iconSettings and iconSettings.cdStateLowerAlpha) or 0.5,
                        iconSettings and iconSettings.chargeHideUntilSpent,
                        cseUsable,
                        cseForm,
                        stance,
                        stanceOnly
                    )
                    -- Proc, form and stance bar edges never fire this hook: the watch
                    -- re-arms on SPELL_UPDATE_USABLE / UPDATE_SHAPESHIFT_FORM /
                    -- UPDATE_BONUS_ACTIONBAR.
                    if cseUsable or cseForm or stance then
                        mod.WatchCdUsable(widget, cseForm, stance ~= nil, cseUsable)
                    end
                    -- Hidden (CD Ready) on a charge spell also needs the refill-to-max
                    -- edge, which this hook never fires. Registered once per spell
                    -- binding (a pooled frame can be handed a different spell), so
                    -- steady-state cost is one field compare per repaint.
                    if cooldownEdge == "hiddenReady" and frameData._cdStateChargeBoundSid ~= spellKey then
                        frameData._cdStateChargeBoundSid = spellKey
                        mod.WatchCdStateChargeIfEnabled(widget)
                    end
                end
                -- The glow part. A hide alone takes down a glow left from an
                -- earlier setting.
                if not glow then
                    if frameData._cdStateGlowOn then
                        mod.StopCdGlow(frameData)
                        frameData._cdStateGlowOn = false
                    end
                    return
                end
                -- Query cooldown on the live override (e.g. Shimmer, not
                -- Blink) so charge-based replacements report correctly. The
                -- glow runs on this plain read, whatever the hide runs on.
                local liveSid = spellKey
                if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
                    liveSid = C_SpellBook.FindSpellOverrideByID(spellKey) or spellKey
                end
                local onCD = mod.CdmOnRealCD(widget, C_Spell.GetSpellCooldown(liveSid))
                if glow == "pixelGlowReady" or glow == "buttonGlowReady" then
                    -- Plain CD Ready Glow: cooldown state only, decided right here
                    -- -- no usability reads, no deferral, no events for genuine
                    -- Blizzard frames (Blizzard calls SetDesaturated on them at
                    -- every cd transition, re-firing this hook). CUI's own custom
                    -- frames (racials / trinkets / potions / custom spells) instead
                    -- drive desaturation via SetDesaturation(float), which does NOT
                    -- trigger this SetDesaturated hook -- so on those the glow would
                    -- never re-evaluate and would stay lit through the whole
                    -- cooldown. Register just those for the event-driven cooldown
                    -- watch (its loop handles plain variants too); Blizzard frames
                    -- keep the zero-event path.
                    if
                        (
                            widget._isRacialFrame
                            or widget._isTrinketFrame
                            or widget._isPresetFrame
                            or widget._isItemPresetFrame
                            or widget._isCustomSpellFrame
                        ) and mod.CDGlowWatch
                    then
                        mod.CDGlowWatch(widget)
                    end
                    -- Pool reassignment: glow state inherited from a previous
                    -- spell on this frame belongs to that spell -- reset now.
                    if frameData._cdGlowBoundSid ~= spellKey then
                        frameData._cdGlowBoundSid = spellKey
                        if frameData._cdStateGlowOn then
                            mod.StopCdGlow(frameData)
                            frameData._cdStateGlowOn = false
                        end
                    end
                    if not onCD then
                        -- The proc and active-state glows share this overlay
                        -- and have priority: ns.StartCdGlow never starts over
                        -- them (only a Blackout, on its own overlay, shows
                        -- beside them) and records the glow as owed instead.
                        if frameData.glowOverlay and not frameData._cdStateGlowOn then
                            local style = mod.CdReadyGlowStyle(glow, iconSettings)
                            local cr, cg, callback = mod.CdReadyGlowColor(style, iconSettings)
                            frameData._cdStateGlowOn = mod.StartCdGlow(
                                frameData,
                                style,
                                cr,
                                cg,
                                callback,
                                mod.CdReadyGlowAlpha(iconSettings)
                            ) ~= nil
                        end
                    elseif frameData._cdStateGlowOn then
                        mod.StopCdGlow(frameData)
                        frameData._cdStateGlowOn = false
                    end
                elseif
                    glow == "pixelGlowReadyUsable"
                    or glow == "buttonGlowReadyUsable"
                    or glow == "glowOnCD"
                then
                    -- Resource Aware CD Ready Glow: also requires the spell to
                    -- be castable (resources/form/lockout). Glow (On CD): the plain
                    -- Ready rule inverted -- glows for the whole cooldown.
                    -- Pool reassignment reset, same as the plain variants.
                    if frameData._cdGlowBoundSid ~= spellKey then
                        frameData._cdGlowBoundSid = spellKey
                        if frameData._cdStateGlowOn then
                            mod.StopCdGlow(frameData)
                            frameData._cdStateGlowOn = false
                        end
                    end
                    -- Track this frame for the event-driven re-evaluation loop:
                    -- every Resource Aware glow, and On CD glows on CUI's custom
                    -- frames (see the plain branch). The loop's events stay
                    -- unregistered until the first watch, so the whole system is
                    -- inert unless such a glow is actually configured somewhere.
                    if
                        mod.CDGlowWatch
                        and (
                            glow ~= "glowOnCD"
                            or widget._isRacialFrame
                            or widget._isTrinketFrame
                            or widget._isPresetFrame
                            or widget._isItemPresetFrame
                            or widget._isCustomSpellFrame
                        )
                    then
                        mod.CDGlowWatch(widget)
                    end
                    -- Defer the actual decision by one frame, same as the
                    -- hide effects above: SetDesaturated fires inside
                    -- Blizzard's secure CDM chain where C_Spell.IsSpellUsable can
                    -- return stale values and a GCD can read as a real cooldown
                    -- (lighting Glow (On CD) on a ready spell). The OnUpdate script
                    -- is installed ONCE per frame object -- this hook fires on every
                    -- repaint (range/resource tints), so the per-fire work must stay
                    -- at plain field writes, never closure creation.
                    local waiting = frameData._cdStateGlowPending
                    if not waiting then
                        waiting = CreateFrame("Frame")
                        waiting:Hide()
                        frameData._cdStateGlowPending = waiting
                        waiting:SetScript("OnUpdate", function(self)
                            self:Hide()
                            -- Re-read the cooldown now instead of trusting a value
                            -- sampled inside the secure chain a frame ago (GCD
                            -- transients misreport isActive there).
                            local pOnCD = mod.CdmOnRealCD(widget, C_Spell.GetSpellCooldown(self.sid))
                            local shouldGlow
                            if self.cse == "glowOnCD" then
                                shouldGlow = pOnCD
                            else
                                local isUsable
                                if mod._cdmSoundSuppressed and mod._cdmSoundSuppressed() then
                                    -- Loading-screen settle window: IsSpellUsable is not
                                    -- trustworthy yet. Glow from cooldown state alone
                                    -- (pre-usability behavior); the queued post-settle
                                    -- pass re-evaluates with real data.
                                    isUsable = true
                                else
                                    -- nil = API has no data for this spell -> treat as
                                    -- not usable; a later event re-evaluates.
                                    isUsable = C_Spell.IsSpellUsable and C_Spell.IsSpellUsable(self.sid)
                                end
                                shouldGlow = (not pOnCD) and (isUsable == true)
                            end
                            if shouldGlow then
                                -- A live proc or active-state glow owns the
                                -- shared overlay: ns.StartCdGlow lights only a
                                -- Blackout beside it.
                                if frameData.glowOverlay and not frameData._cdStateGlowOn then
                                    local style = mod.CdReadyGlowStyle(self.cse, self.ss2)
                                    local cr, cg, callback = mod.CdReadyGlowColor(style, self.ss2)
                                    frameData._cdStateGlowOn = mod.StartCdGlow(
                                        frameData,
                                        style,
                                        cr,
                                        cg,
                                        callback,
                                        mod.CdReadyGlowAlpha(self.ss2)
                                    ) ~= nil
                                end
                            elseif frameData._cdStateGlowOn then
                                mod.StopCdGlow(frameData)
                                frameData._cdStateGlowOn = false
                            end
                        end)
                    end
                    waiting.cse = glow
                    waiting.sid = liveSid
                    waiting.ss2 = iconSettings
                    waiting:Show()
                end
            end)
        end

        -- Desaturate When Not Active: additive hook on SetDesaturated AND
        -- SetDesaturation (Blizzard re-saturates ready icons via either, on CD-end
        -- and ticks). Re-applies desaturation whenever the spell is NOT in its
        -- active state, read LIVE from the swipe color (fd._wasActive is stale on
        -- some falloffs, e.g. DoT expiry); secret arg never read, guarded against
        -- fighting the swipe block's own SetDesaturated. ZERO-COST WHEN UNUSED: the
        -- first line is a flag check (ns._cdmAnyDesatNotActive, set only when a
        -- spell actually uses the setting), so disabled users pay nothing.
        if frameData.tex and not frameData._desatNotActiveHooked then
            frameData._desatNotActiveHooked = true
            local function _maintainDesat()
                if not mod._cdmAnyDesatNotActive then return end
                if frameData._isProcessingOverride then return end
                local iconCache = _ecmeFC[widget]
                local spellKey = iconCache and iconCache.spellID
                local barKeyOf = iconCache and iconCache.barKey
                if not spellKey or not barKeyOf then return end
                local iconSettings = ResolveSpellSettings(widget, spellKey, false)
                if not (iconSettings and iconSettings.desatNotActive) then
                    -- Setting turned off: re-saturate if WE greyed this icon, so it
                    -- doesn't stay desaturated until the next cooldown event.
                    if frameData._desatNA then
                        frameData._isProcessingOverride = true
                        frameData.tex:SetDesaturated(false)
                        frameData._isProcessingOverride = false
                        frameData._desatNA = nil
                    end
                    return
                end
                local isAct = false
                local sc = widget.cooldownSwipeColor
                if sc and type(sc) ~= "number" and sc.GetRGBA then
                    local region = sc:GetRGBA()
                    if type(region) == "number" and not issecretvalue(region) then isAct = (region ~= 0) end
                end
                if isAct then return end
                frameData._isProcessingOverride = true
                frameData.tex:SetDesaturated(true)
                frameData._desatNA = true
                frameData._isProcessingOverride = false
            end
            hooksecurefunc(frameData.tex, "SetDesaturated", _maintainDesat)
            if frameData.tex.SetDesaturation then
                hooksecurefunc(frameData.tex, "SetDesaturation", _maintainDesat)
            end
        end

        -- Keep Colored (On CD): additive hook on SetDesaturated/SetDesaturation,
        -- mirror of the block above. Desaturating on cooldown is BLIZZARD's own
        -- behaviour (greys the icon every CD tick), so suppressing it means
        -- re-saturating right after each call rather than skipping our own.
        -- Deliberately does NOT clear fd._desatNA: Desaturate When Not Active is the
        -- more specific setting and wins when both are on (bail below); this one
        -- only removes the implicit cooldown grey. Zero-cost when unused (same shape as above).
        if frameData.tex and not frameData._noDesatOnCDHooked then
            frameData._noDesatOnCDHooked = true
            local function _keepColored()
                if not mod._cdmAnyNoDesatOnCD then return end
                if frameData._isProcessingOverride then return end
                local iconCache = _ecmeFC[widget]
                local spellKey = iconCache and iconCache.spellID
                local barKeyOf = iconCache and iconCache.barKey
                if not spellKey or not barKeyOf then return end
                local iconSettings = ResolveSpellSettings(widget, spellKey, false)
                if not (iconSettings and iconSettings.noDesatOnCD) then return end
                if iconSettings.desatNotActive then return end
                frameData._isProcessingOverride = true
                frameData.tex:SetDesaturated(false)
                if frameData.tex.SetDesaturation then frameData.tex:SetDesaturation(0) end
                frameData._isProcessingOverride = false
            end
            hooksecurefunc(frameData.tex, "SetDesaturated", _keepColored)
            if frameData.tex.SetDesaturation then
                hooksecurefunc(frameData.tex, "SetDesaturation", _keepColored)
            end
        end

        -- Audio Effect on CD Ready (cd/utility per-icon) is driven purely by the
        -- authoritative SPELL_UPDATE_COOLDOWN/SPELL_UPDATE_CHARGES events via
        -- WatchCdReadySoundIfEnabled (called from DecorateFrame), deliberately NOT
        -- off a SetDesaturated visual hook: that hook fires at repaint moments
        -- unrelated to the real cooldown and sampled a transient GCD race
        -- (isActive=true/isOnGCD=false) that false-fired the sound.
    end

    hookFrameData[widget] = frameData
    return frameData
end

-------------------------------------------------------------------------------
--  CategorizeFrame
-------------------------------------------------------------------------------
local function CategorizeFrame(widget, viewerBarKey)
    local displaySID, baseSID = ResolveFrameSpellID(widget)
    if not displaySID or displaySID <= 0 then return nil, nil, nil end

    -- Lazy route resolution: ResolveCDIDToBar handles cache lookup,
    -- diversion-set match, and viewer-default fallback (defaultBar =
    -- viewerBarKey, the viewer this frame came from). Always returns a
    -- valid bar key for any non-nil cdID.
    local cdID = widget.cooldownID
    local claimBarKey = ResolveCDIDToBar(cdID, viewerBarKey)
    if claimBarKey then
        local claimBD = barMap[claimBarKey]
        local claimType = claimBD and claimBD.barType or claimBarKey
        local viewerIsBuff = (viewerBarKey == "buffs")
        local claimIsBuff = (claimType == "buffs" or claimType == "custom_buff")
        -- Same family always routes. A BUFF viewer resolving to a CD/util bar is
        -- also honored: that only happens for an explicit HOSTED buff (the sole
        -- writer of a CD/util bar key into _divertedSpellsBuff is the hosted-buff
        -- pass in RebuildSpellRouteMap), so the buff's real frame reparents onto
        -- the CD/util bar just like on a buff bar. A CD viewer -> buff bar is still
        -- rejected (falls through) -- that direction is never wanted.
        if viewerIsBuff == claimIsBuff or viewerIsBuff then return claimBarKey, displaySID, baseSID end
        -- Type mismatch (CD viewer routing to a buff bar). Under the 1-spell-per-bar
        -- rule this can't happen via picker claims, but legacy data could trigger
        -- it. Fall through to the viewer's default bar so the frame still renders.
    end
    return viewerBarKey, displaySID, baseSID
end

Inner.CategorizeFrame, Inner.DecorateFrame = CategorizeFrame, DecorateFrame
Inner.QueueViewerAnchor, Inner.RestoreViewerAnchors = QueueViewerAnchor, RestoreViewerAnchors
Inner.WatchParkedIcon = WatchParkedIcon
Inner.broken = false
