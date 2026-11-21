if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_CDM_HookCustomBuffs.lua
--
--  UpdateCustomBuffBars and the aura-tracked custom buffs.
--  Reads the earlier hook files through ns and ns._hookInternals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._hookInternals
-- CludesUICdmHooks.lua or an earlier hook file failed to load.
if not Inner or Inner.broken then return end
Inner.broken = true
-- Born in this module's main chunk, so the aura containers it builds bill this
-- module (AuraKit's shared build scheduler).
local AKWorker = CludesUI.AuraKit.NewBuildWorker()

local ECME = mod.ECME
local barDataByKey = mod.barDataByKey
local cdmBarFrames = mod.cdmBarFrames
local cdmBarIcons = mod.cdmBarIcons
local _, _playerClass = UnitClass("player")
local GetTime = GetTime

local ResolveSpellSettings, DecorateFrame, _AC = Inner.ResolveSpellSettings, Inner.DecorateFrame, Inner._AC
local _presetFrames, _customAuraTimers = Inner._presetFrames, Inner._customAuraTimers
local _pendingCastIDs, QueueCustomBuffUpdate = Inner._pendingCastIDs, Inner.QueueCustomBuffUpdate

-------------------------------------------------------------------------------
--  UpdateCustomBuffBars
--  Custom Aura bars use UNIT_SPELLCAST_SUCCEEDED to detect usage,
--  then show icon with hardcoded duration (reverse cooldown swipe).
--  (_customAuraTimers is declared earlier so the buff-phase injection in
--  CollectAndReanchor can read the same live timers.)
-------------------------------------------------------------------------------

-- Per-icon "Audio on Buff Gain" for self-timed preset/custom buffs (potions,
-- Bloodlust/Heroism, Light's Potential, user-added custom buff IDs). These never
-- fire Blizzard's TriggerAuraAppliedAlert (they appear on a cast/edge for a
-- fixed window), so the regular-buff apply-edge hook can't reach them; play the
-- SAME stored key (ss.buffActiveSoundKey) here, off the cast edge that
-- (re)starts the icon's timer. No loss sound: the real aura is secret/other-cast,
-- so only the gain edge is knowable. The id comes straight from the bar's
-- assignedSpells (clean, never secret), so the lookup is a direct spellSettings
-- hit, no GetCanonicalSpellIDForFrame dance. Gated 0-cost on ns._cdmAnyBuffSound
-- (same flag RescanBuffSoundFlag sets from these spellSettings) and throttled.
local _presetGainSoundAt = {}
local _presetLossSoundAt = {}
local PRESET_GAIN_SOUND_GAP = 0.3
local function PlayPresetBuffGainSound(sd, barId, spellRef, nowTime)
    if not mod._cdmAnyBuffSound then return end
    -- Loading screen / login settle: cast/edge timers restart across a zone/login,
    -- which would false-fire the gain sound. Drop while suppressed.
    if mod._cdmSoundSuppressed and mod._cdmSoundSuppressed() then return end
    -- Family store direct hit + bar-tier fallback (no frame: id from assignedSpells).
    local ss = ResolveSpellSettings(nil, spellRef, sd, barId)
    local key = ss and ss.buffActiveSoundKey
    if not key or key == "none" then return end
    local last = _presetGainSoundAt[spellRef]
    if last and (nowTime - last) < PRESET_GAIN_SOUND_GAP then return end
    _presetGainSoundAt[spellRef] = nowTime
    local paths = mod.FOCUSKICK_SOUND_PATHS
    local filePath = paths and paths[key]
    if filePath then PlaySoundFile(filePath, "Master") end
end
-- Loss counterpart to PlayPresetBuffGainSound for self-timed preset/custom buffs
-- (no real aura-removed alert): fired when the displayed timer runs out. Separate
-- throttle table so gain/loss never suppress each other.
local function PlayPresetBuffLossSound(sd, spellRef, nowTime)
    if not mod._cdmAnyBuffSound then return end
    if mod._cdmSoundSuppressed and mod._cdmSoundSuppressed() then return end
    local ss = sd and sd.spellSettings and sd.spellSettings[spellRef]
    local key = ss and ss.buffLostSoundKey
    if not key or key == "none" then return end
    local last = _presetLossSoundAt[spellRef]
    if last and (nowTime - last) < PRESET_GAIN_SOUND_GAP then return end
    _presetLossSoundAt[spellRef] = nowTime
    local paths = mod.FOCUSKICK_SOUND_PATHS
    local filePath = paths and paths[key]
    if filePath then PlaySoundFile(filePath, "Master") end
end

-------------------------------------------------------------------------------
--  Aura-tracked custom buffs (12.1). ONE engine flow container per bar: the
--  engine owns everything secret-derived, Lua declares only the id set and
--  the style; why they cannot join the bar's icon row is on _AC above the
--  collect passes. ENTRIES WITH A STORED DURATION ARE LEGACY CAST-TIMER
--  CUSTOMS AND NEVER REACH HERE. Styling reads the bar's own settings; glows
--  and per-spell overrides do not reach these icons, with one exception:
--  per-spell Custom Icon. A spell carrying one is split out of the shared
--  group into a single-spell group of its own, so every button in that group
--  is known to hold that spell without Lua ever reading the (secret) aura, and
--  its style paints the fixed art (_AC.ApplyExtra). Bars with no Custom Icon
--  keep the single shared group, byte-for-byte.
-------------------------------------------------------------------------------

-- Appearance fingerprint: the settings a restyle can carry. Geometry the engine
-- flow owns (size, shape, spacing, growth, ids) rebuilds instead, in _AC.Build.
function _AC.StyleSig(edge)
    if not edge then return "" end
    return table.concat({
        edge.iconShape or "none",
        edge.iconZoom or 0.08,
        edge.borderSize or 1,
        edge.borderR or 0,
        edge.borderG or 0,
        edge.borderB or 0,
        edge.borderA or 1,
        edge.borderTexture or "solid",
        edge.borderThickness or "thin",
        edge.borderSizePx or "",
        edge.borderClassColor and 1 or 0,
        edge.borderBehind and 1 or 0,
        edge.borderTextureOffset or 0,
        edge.borderTextureOffsetY or 0,
        edge.borderTextureShiftX or 0,
        edge.borderTextureShiftY or 0,
        edge.bgR or 0.08,
        edge.bgG or 0.08,
        edge.bgB or 0.08,
        edge.bgA or 0.6,
        edge.swipeAlpha or 0.7,
        edge.onlyShowNumbers and 1 or 0,
        mod.CdmDurationTextOn(edge) and 1 or 0,
        edge.cooldownFontSize or 12,
        edge.cooldownTextPosition or "center",
        edge.cooldownTextR or 1,
        edge.cooldownTextG or 1,
        edge.cooldownTextB or 1,
        edge.cooldownTextX or 0,
        edge.cooldownTextY or 0,
        edge.showChargeStackText ~= false and 1 or 0,
        edge.stackCountSize or 11,
        edge.stackCountR or 1,
        edge.stackCountG or 1,
        edge.stackCountB or 1,
        edge.stackCountX or 0,
        edge.stackCountY or 0,
        edge.stackCountPosition or "bottomright",
        edge.showTooltip and 1 or 0,
        edge.barStrata or "MEDIUM",
        (edge.anchorTo == "mouse") and 1 or 0,
    }, "|")
end

-- Countdown formatter for custom auras. Blizzard's own cooldown countdown --
-- what every other icon on the bar draws -- FLOORS the remaining time, so it
-- reads "0" through the last second; AuraKit's shared formatter rounds up and
-- read one higher beside it. Floor every unit to match. Built once (immutable,
-- shared by every bar); nil leaves AuraKit's formatter in place.
function _AC.DurationFormatter()
    if _AC.durFmtTried then return _AC.durFmt end
    _AC.durFmtTried = true
    if not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter and Enum.NumericRuleFormatRounding) then
        return nil
    end
    local Down = Enum.NumericRuleFormatRounding.Down
    local frame = C_StringUtil.CreateNumericRuleFormatter()
    -- Thresholds sit ON each unit boundary: a floored value never crosses one,
    -- so none of the "just above the boundary" offsets the up-rounding
    -- formatters need apply here.
    local success = pcall(frame.SetBreakpoints, frame, {
        { threshold = 0, format = "%d", step = 1, rounding = Down },
        { threshold = 60, format = "%dm", step = 1, rounding = Down, components = { { div = 60 } } },
        { threshold = 3600, format = "%dh", step = 1, rounding = Down, components = { { div = 3600 } } },
        { threshold = 86400, format = "%dd", step = 1, rounding = Down, components = { { div = 86400 } } },
    })
    if not success then return nil end
    _AC.durFmt = frame
    return frame
end

-- Round to the nearest whole physical pixel -- the formula LayoutCDMBar uses for
-- the bar's own icons. PP.Scale (what the other AuraKit consumers use) truncates
-- instead, and lands a pixel short of the icon sitting next to this one.
function _AC.SnapPx(val)
    local onePx = CludesUI.PP and CludesUI.PP.mult
    if not onePx or onePx <= 0 then return val end
    return math.floor(val / onePx + 0.5) * onePx
end

-- The style a bar's custom auras render with. Read from the SAME bar settings
-- the bar's own icons use (RefreshCDMIconAppearance / ApplyShapeToCDMIcon) so a
-- custom aura and a Blizzard buff beside it look identical. AuraKit owns size,
-- crop, swipe and border; style.cdm carries what _AC.ApplyExtra draws on our own
-- regions (background, custom shape, text). PER-SPELL settings cannot reach here:
-- one engine group renders every custom aura on the bar and, while auras are
-- secret, Lua cannot tell which button holds which aura. The lone exception is
-- fixedIcon (a Custom Icon fileID), which only a single-spell group's style carries.
function _AC.BuildStyle(edge, fixedIcon)
    -- Snapped to the physical pixel grid, as LayoutCDMBar does for the bar's own
    -- icons: an unsnapped button renders a fraction off its neighbors at
    -- non-integral UI scales.
    local rawSZ = (edge and edge.iconSize) or 36
    local SZ = _AC.SnapPx(rawSZ)
    local zoom = (edge and edge.iconZoom) or 0.08
    local shape = (edge and edge.iconShape) or "none"
    -- Stock styles: full art, the style's ring instead of a border, no CUI
    -- shape (see the blizz block in _AC.ApplyExtra); Blizzard Style rounds
    -- the art with the viewer mask, Classic WoW UI keeps it square.
    local blizz = mod.CdmBlizzIcons()
    local classic = mod.CdmClassicIcons()
    if blizz then
        zoom = 0
        shape = "none"
    end
    local customShape = (shape ~= "none" and shape ~= "cropped")
    local onlyNumbers = (edge and edge.onlyShowNumbers) and true or false
    local brdSize = (edge and edge.borderSize) or 1
    local brdR, brdG, brdB =
        (edge and edge.borderR) or 0, (edge and edge.borderG) or 0, (edge and edge.borderB) or 0
    if edge and edge.borderClassColor then
        local cc = _playerClass and RAID_CLASS_COLORS[_playerClass]
        if cc then
            brdR, brdG, brdB = cc.r, cc.g, cc.b
        end
    end
    local brdA = (edge and edge.borderA) or 1
    local cdFont = (CludesUI.GetFontPath("cdm"))
        or "Interface\\AddOns\\CludesUI\\media\\fonts\\Expressway.TTF"

    -- Icon rect. A shaped icon samples OUTSIDE its texture to fill the mask, so
    -- the coords come from the shape's inset, not the bar's zoom -- same math as
    -- ApplyShapeToCDMIcon. Carried on the style (not written in ApplyExtra)
    -- because AuraKit re-applies texture coords on every restyle pass.
    local texCoord
    local SH = mod.CDM_SHAPES
    if shape == "cropped" then
        local trim = mod.CdmCropTrim(edge)
        texCoord = { zoom, 1 - zoom, zoom + trim, 1 - zoom - trim }
    elseif customShape and SH and SH.masks[shape] then
        local visRatio = (128 - 2 * (SH.insets[shape] or 17)) / 128
        local grow = ((1 / visRatio) - 1) * 0.5
        texCoord = { -grow, 1 + grow, -grow, 1 + grow }
    end

    -- Square border only where the bar's own icons draw one: a custom shape
    -- rings itself (_AC.ApplyExtra), Only Show Numbers strips the art entirely.
    local border
    if brdSize > 0 and not customShape and not onlyNumbers and not blizz then
        local brdTex = (edge and edge.borderTexture) or "solid"
        border = {
            brdR,
            brdG,
            brdB,
            brdA,
            size = brdSize,
            texture = brdTex,
            behind = (edge and edge.borderBehind) or nil,
            offsetX = edge and edge.borderTextureOffset,
            offsetY = edge and edge.borderTextureOffsetY,
            shiftX = edge and edge.borderTextureShiftX,
            shiftY = edge and edge.borderTextureShiftY,
            addonKey = "cdm",
            sizeKey = (edge and edge.borderThickness) or "thin",
            -- Exact size (borderSizePx); nil = the legacy step, as the bar's own icons.
            edgePx = CludesUI.BorderPx(edge and edge.borderSizePx, brdSize, brdTex),
        }
    end

    return {
        width = SZ,
        height = (shape == "cropped") and _AC.SnapPx(math.floor(rawSZ * mod.CdmCropFactor(edge) + 0.5)) or SZ,
        iconCrop = true,
        iconZoom = zoom,
        texCoord = texCoord,
        cooldownReverse = true,
        hideSwipe = onlyNumbers or nil,
        hideDurationText = (not mod.CdmDurationTextOn(edge)) or nil,
        durationFormatter = _AC.DurationFormatter(),
        -- Own text pipeline: the house icon-text rules (font, outline, slug) come
        -- from ApplyIconTextFont in _AC.ApplyExtra, exactly as the bar's icons do.
        noDefaultFonts = true,
        -- Tooltips follow the bar's Show Tooltip, except on a cursor-anchored
        -- bar: its icons stay mouse-through there, like the bar's own icons
        -- (a motion-enabled icon riding the cursor breaks [@mouseover] casts).
        noTooltips = (not (edge and edge.showTooltip) or (edge and edge.anchorTo == "mouse")) or nil,
        border = border,
        applyExtra = _AC.ApplyExtra,
        cdm = {
            font = cdFont,
            size = SZ,
            zoom = zoom,
            fixedIcon = fixedIcon,
            blizz = blizz or nil,
            classic = classic or nil,
            shape = shape,
            customShape = customShape,
            brdSize = brdSize,
            brdR = brdR,
            brdG = brdG,
            brdB = brdB,
            brdA = brdA,
            onlyNumbers = onlyNumbers,
            bgR = (edge and edge.bgR) or 0.08,
            bgG = (edge and edge.bgG) or 0.08,
            bgB = (edge and edge.bgB) or 0.08,
            bgA = (edge and edge.bgA) or 0.6,
            swipeAlpha = (edge and edge.swipeAlpha) or 0.7,
            durSize = (edge and edge.cooldownFontSize) or 12,
            durPos = (edge and edge.cooldownTextPosition) or "center",
            durX = (edge and edge.cooldownTextX) or 0,
            durY = (edge and edge.cooldownTextY) or 0,
            durR = (edge and edge.cooldownTextR) or 1,
            durG = (edge and edge.cooldownTextG) or 1,
            durB = (edge and edge.cooldownTextB) or 1,
            stackOn = (edge and edge.showChargeStackText) ~= false,
            stackSize = (edge and edge.stackCountSize) or 11,
            stackPos = (edge and edge.stackCountPosition) or "bottomright",
            stackX = (edge and edge.stackCountX) or 0,
            stackY = (edge and edge.stackCountY) or 0,
            stackR = (edge and edge.stackCountR) or 1,
            stackG = (edge and edge.stackCountG) or 1,
            stackB = (edge and edge.stackCountB) or 1,
        },
    }
end

-- Regions the CDM look needs that AuraKit does not build. Runs in the button's
-- creation window -- the only place a region may be parented to an engine aura
-- button. Everything here is ours, so _AC.ApplyExtra can write it under secrecy.
function _AC.InitExtra(btnFrame, skinData)
    skinData.cdmBg = btnFrame:CreateTexture(nil, "BACKGROUND")
    skinData.cdmBg:SetAllPoints(btnFrame)
    skinData.cdmMask = btnFrame:CreateMaskTexture()
    skinData.cdmMask:SetAllPoints(btnFrame)
    skinData.cdmMask:Hide()
    -- Shape ring draws over the swipe, below the dispel ring and text carrier.
    -- Levelled off the cooldown (always the button's own level) rather than the
    -- border host, whose level a "Show Behind" border drops below the button.
    skinData.cdmRingHost = CreateFrame("Frame", nil, btnFrame)
    skinData.cdmRingHost:SetAllPoints(btnFrame)
    skinData.cdmRingHost:EnableMouse(false)
    skinData.cdmRingHost:SetFrameLevel(skinData.cooldown:GetFrameLevel() + 2)
    skinData.cdmRing = skinData.cdmRingHost:CreateTexture(nil, "OVERLAY", nil, 6)
    skinData.cdmRing:SetAllPoints(skinData.cdmRingHost)
    skinData.cdmRing:SetSnapToPixelGrid(false)
    skinData.cdmRing:SetTexelSnappingBias(0)
    skinData.cdmRing:Hide()
    local Kit = CludesUI.AuraKit
    local style = Kit and skinData.styleKey and Kit.styles[skinData.styleKey]
    -- Custom Icon art gets a texture of its own instead of a SetTexture on d.icon:
    -- the engine re-stamps the aura's art onto its registered icon on every update,
    -- so ApplyExtra hides d.icon and this takes its place. Anchored to d.icon so it
    -- follows every shape/zoom re-point without anchoring anything under secrecy.
    -- Creation time is enough: whether a spell has a Custom Icon is part of the
    -- structural signature, so a group's style never gains or loses fixedIcon
    -- without a rebuild. Only its value changes in place, and ApplyExtra re-reads it.
    if style and style.cdm and style.cdm.fixedIcon and skinData.icon then
        skinData.cdmFixedIcon = btnFrame:CreateTexture(nil, "ARTWORK", nil, 1)
        skinData.cdmFixedIcon:SetAllPoints(skinData.icon)
    end
    -- Stock style regions: the ring overlay (on the ring host, above the
    -- swipe) and, under Blizzard Style, the viewer's rounded mask (Classic
    -- WoW UI icons are square). Whether a style is on is a reload-gated
    -- profile flag, so it is fixed for the button's whole life.
    if style and style.cdm and style.cdm.blizz then
        if not style.cdm.classic then
            skinData.cdmBlizzMask = btnFrame:CreateMaskTexture()
            skinData.cdmBlizzMask:SetAtlas(mod.CDM_BLIZZ_MASK)
            skinData.cdmBlizzMask:SetAllPoints(btnFrame)
        end
        skinData.cdmBlizzOverlay = skinData.cdmRingHost:CreateTexture(nil, "OVERLAY", nil, 5)
        if style.cdm.classic then
            skinData.cdmBlizzOverlay:SetTexture(mod.CDM_CLASSIC_RING)
        else
            mod.CdmStockAtlas(skinData.cdmBlizzOverlay, mod.CDM_BLIZZ_OVERLAY)
        end
        skinData.cdmBlizzOverlay:SetSnapToPixelGrid(false)
        skinData.cdmBlizzOverlay:SetTexelSnappingBias(0)
    end
    -- AuraKit runs applyExtra BEFORE this creation hook, so the pass that draws
    -- these regions has to run once more now that they exist.
    if style then _AC.ApplyExtra(btnFrame, skinData, style) end
end

-- Re-seat a mask reference. AddMaskTexture is additive, so the drop always
-- runs first or a re-apply stacks the same mask twice.
function _AC.SetMask(regionFrame, mask, wanted)
    if not regionFrame then return end
    pcall(regionFrame.RemoveMaskTexture, regionFrame, mask)
    if wanted then pcall(regionFrame.AddMaskTexture, regionFrame, mask) end
end

-- Background, custom shape and text, on our own regions. Anchors use
-- d.borderHost (created SetAllPoints(button) in the creation window) rather than
-- the button: a SetPoint whose relative frame is the button is denied while
-- auras are secret, which is exactly when a settings change must still land.
function _AC.ApplyExtra(btnFrame, skinData, style)
    local c = style.cdm
    if not c then return end
    local Pix = CludesUI.PP

    -- Only Show Numbers strips the art down to the countdown. Shown-state as
    -- well as alpha, the same pair ApplyOnlyNumbers uses on the bar's own icons:
    -- a texture's alpha and its vertex color share one slot on this client.
    -- A Custom Icon group hides the engine's art the same way and shows its own
    -- texture (d.cdmFixedIcon, see InitExtra) in its place.
    local fixed = c.fixedIcon and skinData.cdmFixedIcon
    local artOn = not c.onlyNumbers
    local engineArtOn = artOn and not fixed
    if skinData.icon then
        skinData.icon:SetAlpha(engineArtOn and 1 or 0)
        skinData.icon:SetShown(engineArtOn)
        -- Cropped samples a heavy vertical slice, and a snapped image edge can
        -- round to a different physical pixel than the unsnapped swipe (the 1px
        -- split ApplyShapeToCDMIcon disables snapping for). Restored otherwise.
        if skinData.icon.SetSnapToPixelGrid then skinData.icon:SetSnapToPixelGrid(c.shape ~= "cropped") end
        if c.shape == "cropped" and skinData.icon.SetTexelSnappingBias then
            skinData.icon:SetTexelSnappingBias(0)
        end
    end
    if fixed then
        fixed:SetTexture(c.fixedIcon)
        -- The crop AuraKit's ApplyStyleToRegions gives d.icon from this same style.
        local tc = style.texCoord
        if tc then
            fixed:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
        elseif style.iconCrop then
            local z = style.iconZoom or 0.07
            fixed:SetTexCoord(z, 1 - z, z, 1 - z)
        else
            fixed:SetTexCoord(0, 1, 0, 1)
        end
        if fixed.SetSnapToPixelGrid then fixed:SetSnapToPixelGrid(c.shape ~= "cropped") end
        if c.shape == "cropped" and fixed.SetTexelSnappingBias then fixed:SetTexelSnappingBias(0) end
        fixed:SetAlpha(artOn and 1 or 0)
        fixed:SetShown(artOn)
    end
    if skinData.cdmBg then
        -- Blizzard Style has no CUI background (hidden once below, never
        -- shown here first).
        if c.onlyNumbers or c.blizz then
            skinData.cdmBg:Hide()
        else
            skinData.cdmBg:SetColorTexture(c.bgR, c.bgG, c.bgB, c.bgA)
            skinData.cdmBg:Show()
        end
    end
    if skinData.cooldown then skinData.cooldown:SetSwipeColor(0, 0, 0, c.swipeAlpha) end

    -- Custom shape: mask on icon/background/swipe plus the shape's own ring,
    -- mirroring ApplyShapeToCDMIcon so both renderers land on the same geometry.
    local SH = mod.CDM_SHAPES
    local mask, ring = skinData.cdmMask, skinData.cdmRing
    local maskPath = (c.customShape and SH and not c.onlyNumbers) and SH.masks[c.shape] or nil
    local shapeKey = maskPath and (c.shape .. "|" .. c.zoom .. "|" .. c.brdSize .. "|" .. c.size) or ""
    if skinData.cdmShapeKey ~= shapeKey and mask then
        if maskPath then
            mask:SetTexture(maskPath, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            mask:Show()
            _AC.SetMask(skinData.icon, mask, true)
            _AC.SetMask(skinData.cdmFixedIcon, mask, true)
            _AC.SetMask(skinData.cdmBg, mask, true)
            _AC.SetMask(skinData.cooldown, mask, true)
            local exp = SH.iconExpand
                + (SH.iconExpandOffsets[c.shape] or 0)
                + ((c.zoom - (SH.zoomDefaults[c.shape] or 0.06)) * 200)
            if exp < 0 then exp = 0 end
            local half = exp / 2
            if skinData.icon then
                skinData.icon:ClearAllPoints()
                Pix.Point(skinData.icon, "TOPLEFT", skinData.borderHost, "TOPLEFT", -half, half)
                Pix.Point(skinData.icon, "BOTTOMRIGHT", skinData.borderHost, "BOTTOMRIGHT", half, -half)
            end
            mask:ClearAllPoints()
            if c.brdSize >= 1 then
                Pix.Point(mask, "TOPLEFT", skinData.borderHost, "TOPLEFT", 1, -1)
                Pix.Point(mask, "BOTTOMRIGHT", skinData.borderHost, "BOTTOMRIGHT", -1, 1)
            else
                mask:SetAllPoints(skinData.borderHost)
            end
            if skinData.cooldown then
                pcall(skinData.cooldown.SetSwipeTexture, skinData.cooldown, maskPath)
                if skinData.cooldown.SetUseCircularEdge then
                    pcall(
                        skinData.cooldown.SetUseCircularEdge,
                        skinData.cooldown,
                        c.shape ~= "square" and c.shape ~= "csquare"
                    )
                end
                if skinData.cooldown.SetEdgeScale then
                    pcall(skinData.cooldown.SetEdgeScale, skinData.cooldown, SH.edgeScales[c.shape] or 0.60)
                end
            end
        else
            _AC.SetMask(skinData.icon, mask)
            _AC.SetMask(skinData.cdmFixedIcon, mask)
            _AC.SetMask(skinData.cdmBg, mask)
            _AC.SetMask(skinData.cooldown, mask)
            mask:SetTexture(nil)
            mask:ClearAllPoints()
            mask:SetSize(0.001, 0.001)
            mask:Hide()
            if skinData.icon then
                skinData.icon:ClearAllPoints()
                skinData.icon:SetAllPoints(skinData.borderHost)
            end
            if skinData.cooldown then
                pcall(
                    skinData.cooldown.SetSwipeTexture,
                    skinData.cooldown,
                    "Interface\\AddOns\\CludesUI\\media\\white-square.png"
                )
                if skinData.cooldown.SetUseCircularEdge then
                    pcall(skinData.cooldown.SetUseCircularEdge, skinData.cooldown, false)
                end
            end
        end
        skinData.cdmShapeKey = shapeKey
    end
    -- Ring color follows the border color on every pass, so a color-only change
    -- lands without re-running the geometry above. Border Size 0 drops the ring,
    -- as it does on the bar's own shaped icons.
    if ring then
        local ringPath = (maskPath and c.brdSize > 0) and SH.borders[c.shape] or nil
        if ringPath then
            ring:SetTexture(ringPath)
            ring:SetVertexColor(c.brdR, c.brdG, c.brdB, c.brdA)
            ring:Show()
        else
            ring:Hide()
        end
    end

    -- Stock styles: ring overlay sized to the button (the same geometry as
    -- the bar's own icons) and no CUI background; Blizzard Style also seats
    -- the rounded viewer mask on the art and the viewer's rounded swipe
    -- (Classic WoW UI keeps the square art and swipe). Anchored to
    -- d.borderHost like the shape geometry above (button-relative points are
    -- denied under secrecy). Geometry is memoized on the button size.
    if c.blizz and skinData.cdmBlizzOverlay then
        if skinData.cdmBg then skinData.cdmBg:Hide() end
        local bKey = "blizz|" .. c.size
        if skinData.cdmBlizzKey ~= bKey then
            skinData.cdmBlizzKey = bKey
            local shade = skinData.cdmBlizzOverlay
            if c.classic then
                mod.CdmPlaceClassicRing(shade, skinData.borderHost, c.size, c.size)
            else
                _AC.SetMask(skinData.icon, skinData.cdmBlizzMask, true)
                _AC.SetMask(skinData.cdmFixedIcon, skinData.cdmBlizzMask, true)
                shade:ClearAllPoints()
                Pix.Point(
                    shade,
                    "TOPLEFT",
                    skinData.borderHost,
                    "TOPLEFT",
                    -c.size * mod.CDM_BLIZZ_RING_X,
                    c.size * mod.CDM_BLIZZ_RING_Y
                )
                Pix.Point(
                    shade,
                    "BOTTOMRIGHT",
                    skinData.borderHost,
                    "BOTTOMRIGHT",
                    c.size * mod.CDM_BLIZZ_RING_X,
                    -c.size * mod.CDM_BLIZZ_RING_Y
                )
                if skinData.cooldown then
                    pcall(skinData.cooldown.SetSwipeTexture, skinData.cooldown, mod.CDM_BLIZZ_SWIPE)
                end
            end
        end
        skinData.cdmBlizzOverlay:SetShown(artOn)
    end

    if skinData.duration then
        local fKey = c.font .. "|" .. c.durSize
        if skinData.cdmDurFont ~= fKey then
            skinData.cdmDurFont = fKey
            CludesUI.ApplyIconTextFont(skinData.duration, c.font, c.durSize, "cdm")
        end
        local aKey = c.durPos .. "|" .. c.durX .. "|" .. c.durY
        if skinData.cdmDurAnchor ~= aKey then
            skinData.cdmDurAnchor = aKey
            mod.AnchorCooldownText(skinData.duration, skinData.borderHost, c.durPos, c.durX, c.durY)
        end
        skinData.duration:SetTextColor(c.durR, c.durG, c.durB)
    end

    if skinData.stack then
        local fKey = c.font .. "|" .. c.stackSize
        if skinData.cdmStackFont ~= fKey then
            skinData.cdmStackFont = fKey
            CludesUI.ApplyIconTextFont(skinData.stack, c.font, c.stackSize, "cdm")
        end
        local aKey = c.stackPos .. "|" .. c.stackX .. "|" .. c.stackY
        if skinData.cdmStackAnchor ~= aKey then
            skinData.cdmStackAnchor = aKey
            local pt, posY = mod.CdmStackAnchorPoint(c.stackPos, c.stackY)
            skinData.stack:ClearAllPoints()
            skinData.stack:SetPoint(pt, skinData.borderHost, pt, c.stackX, posY)
        end
        skinData.stack:SetTextColor(c.stackR, c.stackG, c.stackB)
        -- Alpha, not Hide: the engine re-shows this font string whenever the
        -- slot's application count refreshes.
        skinData.stack:SetAlpha(c.stackOn and 1 or 0)
    end
end

-- Add every id form the live aura can carry (typed + override + base) to map.
function _AC.AddSpellForms(map, spellRef)
    map[spellRef] = true
    local ovr = C_SpellBook
        and C_SpellBook.FindSpellOverrideByID
        and C_SpellBook.FindSpellOverrideByID(spellRef)
    if ovr and ovr > 0 then map[ovr] = true end
    local base = C_Spell and C_Spell.GetBaseSpell and C_Spell.GetBaseSpell(spellRef)
    if base and base > 0 then map[base] = true end
    return map
end

function _AC.FixedIconStyleKey(barId, spellRef) return "cdm:aurabuff:" .. barId .. ":ci:" .. spellRef end

-- A new fileID for a spell that already has its own group is appearance, not
-- structure: restyle that group in place. A rebuild would abandon the old
-- container, whose engine-created group buttons can never be freed
-- (AK.ReleaseContainer), so re-picking an icon must not cost one.
function _AC.SyncFixedIcons(rec, edge, cis)
    local styles = rec.ciStyles
    if not (styles and cis) then return end
    local Kit = CludesUI.AuraKit
    if not (Kit and Kit.styles) then return end
    for spellRef, ci in pairs(cis) do
        local key = _AC.FixedIconStyleKey(edge.key, spellRef)
        local current = styles[key]
        if current and current ~= ci then
            styles[key] = ci
            Kit.styles[key] = _AC.BuildStyle(edge, ci)
            if Kit.RestyleSoon then Kit.RestyleSoon(key) end
        end
    end
end

-- cis: optional sid -> Custom Icon fileID for the entries that carry one.
function _AC.Build(rec, barId, edge, sids, sig, cis)
    local Kit = CludesUI.AuraKit
    local barFrame = cdmBarFrames[barId]
    -- Bar not built yet (login race): bail WITHOUT stamping the signature;
    -- the next tracking sync re-queues the build.
    if not (Kit and Kit.CreateContainerShell and Kit.AddGroupToContainer and barFrame) then return end
    local styleKey = "cdm:aurabuff:" .. barId
    Kit.styles[styleKey] = _AC.BuildStyle(edge)
    rec.styleSig = _AC.StyleSig(edge)
    -- Retire the previous generation properly (the holder is reused).
    if rec.container and Kit.ReleaseContainer then Kit.ReleaseContainer(rec.container) end
    local holderFrame = rec.holder
    if not holderFrame then
        holderFrame = CreateFrame("Frame", nil, UIParent)
        holderFrame:SetSize(1, 1)
        holderFrame:EnableMouse(false)
        rec.holder = holderFrame
    end
    holderFrame:SetFrameStrata((edge and edge.barStrata) or "MEDIUM")
    holderFrame:Show()
    -- ONE flow group carrying every id form the live aura can carry (typed
    -- + override + base): the engine compacts actives and renders nothing
    -- when none are up. A spell with a Custom Icon gets a single-spell group
    -- instead, flowing after the shared one. Its forms are struck from the
    -- shared map, so an id it shares with a plain entry (the add-time variant
    -- dedup rules that out, but overrides move with talents) renders once.
    local includeMap, nShared = {}, 0
    local ciGroups, claimed
    for index = 1, #sids do
        local spellRef = sids[index]
        local ci = cis and cis[spellRef]
        if ci then
            local forms = _AC.AddSpellForms({}, spellRef)
            claimed = claimed or {}
            for ident in pairs(forms) do
                claimed[ident] = true
            end
            ciGroups = ciGroups or {}
            ciGroups[#ciGroups + 1] = { sid = spellRef, ci = ci, forms = forms }
        else
            nShared = nShared + 1
            _AC.AddSpellForms(includeMap, spellRef)
        end
    end
    if claimed then
        for ident in pairs(claimed) do
            includeMap[ident] = nil
        end
    end
    local vertical = (edge and edge.verticalOrientation) and true or false
    local gap = (edge and edge.spacing) or 2
    local grow = (edge and edge.growDirection) or "CENTER"
    -- Container point mirrors _AC.Anchor's holder placement: the tail
    -- always flows AWAY from the bar's end (end-of-bar for all growths).
    local pt
    if vertical then
        pt = (grow == "UP") and "BOTTOM" or "TOP"
    elseif grow == "LEFT" then
        pt = "RIGHT"
    else
        pt = "LEFT"
    end
    local boxHolder = Kit.CreateContainerShell(holderFrame, { point = { pt } })
    rec.pt = pt
    rec.curPt = pt
    if Kit.SetContainerAxis then Kit.SetContainerAxis(boxHolder, vertical) end
    -- Group keys in flow order. The shared group is skipped when nothing is left
    -- in its map: an EMPTY includeSpellIDs would not narrow the HELPFUL filter.
    local groupKeys = {}
    if nShared > 0 and next(includeMap) then
        Kit.AddGroupToContainer(boxHolder, {
            key = "spells",
            filter = { "HELPFUL" },
            style = styleKey,
            extraInit = _AC.InitExtra,
            maxFrameCount = nShared,
            -- Helpful spellID includes on the player pass the identity gate
            -- regardless of the spell's secrecy flag.
            candidateFilters = { includeSpellIDs = includeMap },
        })
        groupKeys[#groupKeys + 1] = "spells"
    end
    -- Custom Icon groups: one style per spell, since the fixed art is the one
    -- thing that differs from the shared style. Kept on rec.ciStyles so a restyle
    -- (RefreshAuraCustomStyle) reaches them too. Cost: every AddAuraGroup mints
    -- a 10-button engine batch that is never released, so each split spell is
    -- ten more buttons per container build -- which is why a file-id change
    -- restyles in place (SyncFixedIcons) instead of rebuilding.
    local ciStyles
    if ciGroups then
        ciStyles = {}
        for index = 1, #ciGroups do
            local g = ciGroups[index]
            local ciStyleKey = _AC.FixedIconStyleKey(barId, g.sid)
            Kit.styles[ciStyleKey] = _AC.BuildStyle(edge, g.ci)
            ciStyles[ciStyleKey] = g.ci
            local gKey = "ci:" .. g.sid
            Kit.AddGroupToContainer(boxHolder, {
                key = gKey,
                filter = { "HELPFUL" },
                style = ciStyleKey,
                extraInit = _AC.InitExtra,
                maxFrameCount = 1,
                candidateFilters = { includeSpellIDs = g.forms },
            })
            groupKeys[#groupKeys + 1] = gKey
        end
    end
    -- Drop the styles of Custom Icon groups this build no longer has. Their old
    -- buttons stay registered under the key (group buttons are never released),
    -- and AuraKit skips a key with no style, so nothing restyles them again.
    if rec.ciStyles then
        for oldKey in pairs(rec.ciStyles) do
            if not (ciStyles and ciStyles[oldKey]) then Kit.styles[oldKey] = nil end
        end
    end
    rec.ciStyles = ciStyles
    if boxHolder.SetAuraGroupLayout then
        -- elementWidth/Height feed the engine's flow math (the style sizes the
        -- button itself). Without them the flow spaces icons at the engine
        -- default, so any bar not at that size overlaps or gaps -- and a cropped
        -- bar, whose buttons are shorter (ns.CdmCropFactor), is off on both axes. Every group
        -- shares one layout: their styles differ only in the fixed art.
        local st = Kit.styles[styleKey]
        local gapPx = _AC.SnapPx(gap)
        local layout = {
            elementWidth = st and st.width,
            elementHeight = st and st.height,
            elementSpacing = gapPx,
            lineSpacing = gapPx,
            groupSpacing = gapPx,
            groupLineSpacing = gapPx,
        }
        for index = 1, #groupKeys do
            boxHolder:SetAuraGroupLayout(groupKeys[index], layout)
        end
    end
    Kit.FinishContainer(boxHolder, "player")
    rec.container = boxHolder
    rec.sig, rec.sids = sig, sids
    rec.bdRef = edge
    -- Follow the bar's rect from OUR frame's own change signals (post-hook
    -- + scripts): the holder re-derives its position one coalesced frame
    -- after any bar move/resize/visibility change.
    if rec.hookedBar ~= barFrame then
        rec.hookedBar = barFrame
        local function poke() _AC.MarkSync(barId) end
        hooksecurefunc(barFrame, "SetPoint", poke)
        barFrame:HookScript("OnSizeChanged", poke)
        barFrame:HookScript("OnShow", poke)
        barFrame:HookScript("OnHide", poke)
    end
    _AC.Anchor(barId, rec)
end

local function UpdateCustomBuffBars()
    if not ECME then return end
    local profile = ECME.db and ECME.db.profile
    if not profile or not profile.cdmBars or not profile.cdmBars.bars then return end
    local LayoutCDMBar = mod.LayoutCDMBar
    local RefreshCDMIconAppearance = mod.RefreshCDMIconAppearance
    local cdmPageOpen = mod._cdmBarsPageOpen or false
    local nowTime = GetTime()

    for _, barInfo in ipairs(profile.cdmBars.bars) do
        if barInfo.enabled and barInfo.barType == "custom_buff" then
            local barId = barInfo.key
            local boxHolder = cdmBarFrames[barId]
            if boxHolder then
                local sd = mod.GetBarSpellData(barId)
                local spellList = sd and sd.assignedSpells or {}
                local icons = cdmBarIcons[barId]
                if not icons then
                    icons = {}
                    cdmBarIcons[barId] = icons
                end
                local total = 0

                for _, spellRef in ipairs(spellList) do
                    if type(spellRef) == "number" and spellRef > 0 then
                        local duration = sd.spellDurations and sd.spellDurations[spellRef] or 0
                        if duration > 0 then
                            local timerKey = barId .. ":" .. spellRef
                            local timer = _customAuraTimers[timerKey]

                            if _pendingCastIDs[spellRef] and duration > 0 then
                                _customAuraTimers[timerKey] = {
                                    start = nowTime,
                                    duration = duration,
                                }
                                timer = _customAuraTimers[timerKey]
                                PlayPresetBuffGainSound(sd, barId, spellRef, nowTime)
                            end

                            -- Loss edge: displayed timer ran out -> fire once, drop it.
                            if timer and (nowTime - timer.start) >= timer.duration then
                                PlayPresetBuffLossSound(sd, spellRef, nowTime)
                                _customAuraTimers[timerKey] = nil
                                timer = nil
                            end

                            local isActive = timer
                                and duration > 0
                                and (nowTime - timer.start) < timer.duration

                            if isActive or cdmPageOpen then
                                local fkey = barId .. ":custombuff:" .. spellRef
                                local frame = _presetFrames[fkey]
                                if not frame then
                                    frame = CreateFrame("Frame", nil, UIParent)
                                    frame:SetSize(36, 36)
                                    frame:Hide()
                                    frame:EnableMouse(false)
                                    local texture = frame:CreateTexture(nil, "ARTWORK")
                                    texture:SetAllPoints()
                                    mod.CdmOwnIconCrop(texture)
                                    frame.Icon = texture
                                    frame._tex = texture
                                    local cd = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
                                    cd:SetAllPoints()
                                    cd:SetDrawEdge(false)
                                    cd:SetDrawBling(false)
                                    cd:SetHideCountdownNumbers(not mod.CdmDurationTextOn(barInfo))
                                    cd:SetReverse(true)
                                    frame.Cooldown = cd
                                    frame._cooldown = cd
                                    frame._isCustomSpellFrame = true
                                    frame._isCustomBuffFrame = true
                                    frame.cooldownID = nil
                                    frame.cooldownInfo = nil
                                    frame.layoutIndex = 99999
                                    _presetFrames[fkey] = frame
                                    cd:HookScript(
                                        "OnCooldownDone",
                                        function() C_Timer.After(0, QueueCustomBuffUpdate) end
                                    )
                                    local iconSID = mod.LustPresetIconSpellID
                                            and mod.LustPresetIconSpellID(spellRef)
                                        or spellRef
                                    local spInfo = C_Spell
                                        and C_Spell.GetSpellInfo
                                        and C_Spell.GetSpellInfo(iconSID)
                                    if spInfo and spInfo.iconID and frame._tex then
                                        frame._tex:SetTexture(spInfo.iconID)
                                    end
                                end
                                if isActive and timer then
                                    frame._cooldown:SetCooldown(timer.start, timer.duration)
                                else
                                    frame._cooldown:Clear()
                                end
                                DecorateFrame(frame, barInfo)
                                frame:Show()
                                -- A frame (re)shown while its bar is visibility-hidden must not
                                -- come back at its last alpha: only listed icons get the hide
                                -- pass, and this one may have been unlisted (inactive) then.
                                frame:SetAlpha(
                                    boxHolder._visHidden and 0
                                        or ((mod.EffectiveBarAlpha and mod.EffectiveBarAlpha(barInfo)) or 1)
                                )
                                frame:EnableMouse(false)
                                if frame.Cooldown and frame.Cooldown.SetDrawSwipe then
                                    -- Only Show Numbers hides the swipe with the icon art.
                                    frame.Cooldown:SetDrawSwipe(not barInfo.onlyShowNumbers)
                                end
                                total = total + 1
                                icons[total] = frame
                            else
                                local fkey = barId .. ":custombuff:" .. spellRef
                                local frame = _presetFrames[fkey]
                                if frame then frame:Hide() end
                                if timer and not isActive then _customAuraTimers[timerKey] = nil end
                            end
                        end
                    end
                end

                for index = total + 1, #icons do
                    if icons[index] then icons[index]:Hide() end
                    icons[index] = nil
                end

                -- Custom aura bars are display-only, never clickable
                boxHolder:EnableMouse(false)
                if boxHolder.EnableMouseClicks then boxHolder:EnableMouseClicks(false) end
                if boxHolder.EnableMouseMotion then pcall(boxHolder.EnableMouseMotion, boxHolder, false) end

                local prevCount = boxHolder._prevVisibleCount or 0
                if total ~= prevCount then
                    if RefreshCDMIconAppearance then RefreshCDMIconAppearance(barId) end
                    if LayoutCDMBar then LayoutCDMBar(barId) end
                end
                boxHolder._prevVisibleCount = total
            end
        end
    end

    -- Buff-family bars: custom/preset buffs are injected + rendered by
    -- CollectAndReanchor's buff phase. Here we only run cast detection: when a
    -- pending cast matches a custom buff on a buff bar, (re)start its timer and
    -- queue a reanchor so the icon appears. Expiry is handled by the frame's
    -- OnCooldownDone hook (which also reanchors to drop the icon).
    local needBuffReanchor = false
    for _, barInfo in ipairs(profile.cdmBars.bars) do
        if barInfo.enabled and barInfo.barType == "buffs" then
            local sd = mod.GetBarSpellData(barInfo.key)
            local spellList = sd and sd.assignedSpells
            local durs = sd and sd.spellDurations
            if spellList and durs then
                for _, spellRef in ipairs(spellList) do
                    if type(spellRef) == "number" and spellRef > 0 and (durs[spellRef] or 0) > 0 then
                        local tkey = barInfo.key .. ":" .. spellRef
                        if _pendingCastIDs[spellRef] then
                            _customAuraTimers[tkey] = {
                                start = nowTime,
                                duration = durs[spellRef],
                            }
                            needBuffReanchor = true
                            PlayPresetBuffGainSound(sd, barInfo.key, spellRef, nowTime)
                        else
                            -- Loss edge: displayed window ran out -> fire once, drop timer.
                            local tbl = _customAuraTimers[tkey]
                            if tbl and (nowTime - tbl.start) >= tbl.duration then
                                PlayPresetBuffLossSound(sd, spellRef, nowTime)
                                _customAuraTimers[tkey] = nil
                                needBuffReanchor = true
                            end
                        end
                    end
                end
            end
        end
    end
    if needBuffReanchor and mod.QueueReanchor then mod.QueueReanchor() end

    wipe(_pendingCastIDs)
end
mod.UpdateCustomBuffBars = UpdateCustomBuffBars

-- Sync pass for aura-tracked custom buffs, run from the rebuild tails and
-- the picker add flows. Collects each bar's no-duration custom ids, and
-- (re)builds that bar's engine tail container ONLY when the signature --
-- the id list plus the baked styling inputs -- changes. Containers for
-- bars that no longer have aura customs are hidden (dormant, zero cost).
function mod.UpdateCustomBuffAuraTracking()
    local profile = ECME and ECME.db and ECME.db.profile
    local barList = profile and profile.cdmBars and profile.cdmBars.bars
    local seen = {}
    if barList then
        for _, edge in ipairs(barList) do
            if edge.enabled and (edge.barType == "custom_buff" or edge.barType == "buffs") then
                local sd = mod.GetBarSpellData and mod.GetBarSpellData(edge.key)
                local entries = sd and sd.assignedSpells
                local tags = sd and sd.customSpellIDs
                if entries and tags then
                    local durs = sd.spellDurations
                    local sids
                    for _, spellRef in ipairs(entries) do
                        if
                            type(spellRef) == "number"
                            and spellRef > 0
                            and tags[spellRef]
                            and (not durs or (durs[spellRef] or 0) <= 0)
                        then
                            sids = sids or {}
                            sids[#sids + 1] = spellRef
                        end
                    end
                    if sids then
                        seen[edge.key] = true
                        -- Which spells carry a per-spell Custom Icon is structural:
                        -- each gets a group of its own. The fileID itself is not --
                        -- it restyles in place (_AC.SyncFixedIcons). Resolved only
                        -- once anyone has set one (monotonic gate); everyone else
                        -- keeps the exact signature they had and pays nothing for it.
                        local cis, ciSig
                        if mod._cdmAnyCustomIcon then
                            for index = 1, #sids do
                                local spellRef = sids[index]
                                local ss = ResolveSpellSettings(nil, spellRef, sd, edge.key)
                                local ci = ss and ss.customIcon
                                if type(ci) == "number" and ci > 0 then
                                    cis = cis or {}
                                    cis[spellRef] = ci
                                    ciSig = (ciSig or "|ci") .. ":" .. spellRef
                                end
                            end
                        end
                        -- Structural only: the id list plus the geometry the
                        -- engine flow owns. Everything else is appearance and
                        -- rides ns.RefreshAuraCustomStyle without a rebuild.
                        local sig = table.concat(sids, ":")
                            .. "|"
                            .. tostring(edge.iconSize or 36)
                            .. "|"
                            .. tostring(edge.iconShape or "none")
                            .. "|"
                            .. tostring(edge.growDirection or "CENTER")
                            .. "|"
                            .. (edge.verticalOrientation and 1 or 0)
                            .. "|"
                            .. tostring(edge.spacing or 2)
                            -- Adjust Crop changes the button height the flow lays out, so it
                            -- is geometry. Appended only while cropped: every other bar keeps
                            -- its exact signature.
                            .. ((edge.iconShape == "cropped") and ("|crop" .. mod.CdmCropPercent(edge)) or "")
                            .. (ciSig or "")
                        local rec = _AC.bars[edge.key]
                        if not rec then
                            rec = {}
                            _AC.bars[edge.key] = rec
                        end
                        rec.bdRef = edge
                        if rec.sig ~= sig and not rec.queued then
                            local Kit = CludesUI.AuraKit
                            if Kit and Kit.QueueBuildJob then
                                rec.queued = true
                                local barId, bdRef, sidsRef, sigRef, cisRef = edge.key, edge, sids, sig, cis
                                AKWorker:Queue(function()
                                    rec.queued = nil
                                    _AC.Build(rec, barId, bdRef, sidsRef, sigRef, cisRef)
                                    -- The job captured the id list as it was when
                                    -- it was queued. A change that landed while it
                                    -- was in flight (two adds in a row) is not in
                                    -- what it just built, and stamping rec.sig hides
                                    -- it from every later compare -- so re-sync once
                                    -- here instead of losing the spell until a reload.
                                    if rec.resync then
                                        rec.resync = nil
                                        mod.UpdateCustomBuffAuraTracking()
                                    end
                                end, "cdm:aurabuff-shell")
                            end
                        elseif rec.queued and rec.sig ~= sig then
                            rec.resync = true
                        else
                            _AC.SyncFixedIcons(rec, edge, cis)
                            mod.RefreshAuraCustomStyle(edge.key)
                        end
                    end
                end
            end
        end
    end
    for barId, rec in pairs(_AC.bars) do
        if not seen[barId] and rec.sids then
            -- Bar lost its aura customs: hide the holder, release the
            -- engine container, forget the build.
            if rec.holder then rec.holder:Hide() end
            local Kit = CludesUI.AuraKit
            if rec.container and Kit and Kit.ReleaseContainer then Kit.ReleaseContainer(rec.container) end
            rec.container = nil
            rec.sig = nil
            rec.sids = nil
            rec.styleSig = nil
            if rec.ciStyles and Kit and Kit.styles then
                for oldKey in pairs(rec.ciStyles) do
                    Kit.styles[oldKey] = nil
                end
            end
            rec.ciStyles = nil
        end
    end
end

-- Re-apply a bar's appearance to its custom-aura icons. Called from every CDM
-- restyle path, so an options change lands on them the same frame it lands on
-- the bar's own icons instead of waiting for a reload or a spec swap. Free for
-- bars with no custom auras (one table lookup) and a no-op when nothing the
-- style reads has changed.
function mod.RefreshAuraCustomStyle(barId)
    local rec = barId and _AC.bars[barId]
    if not (rec and rec.container) then return end
    local edge = barDataByKey[barId]
    if not edge then return end
    rec.bdRef = edge
    local sig = _AC.StyleSig(edge)
    if rec.styleSig == sig then return end
    local Kit = CludesUI.AuraKit
    if not (Kit and Kit.styles) then return end
    if rec.holder then rec.holder:SetFrameStrata(edge.barStrata or "MEDIUM") end
    local styleKey = "cdm:aurabuff:" .. barId
    Kit.styles[styleKey] = _AC.BuildStyle(edge)
    if Kit.RestyleSoon then Kit.RestyleSoon(styleKey) end
    -- Custom Icon groups carry the same appearance under their own style keys.
    if rec.ciStyles then
        for ciStyleKey, ci in pairs(rec.ciStyles) do
            Kit.styles[ciStyleKey] = _AC.BuildStyle(edge, ci)
            if Kit.RestyleSoon then Kit.RestyleSoon(ciStyleKey) end
        end
    end
    -- Stamped only once the style is actually installed: recording a style that
    -- never applied would make every later call with the same settings early-out.
    rec.styleSig = sig
end

Inner.UpdateCustomBuffBars = UpdateCustomBuffBars
Inner.broken = false
