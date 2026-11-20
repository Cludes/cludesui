if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-- CludesUI_AuraKit.lua Shared engine for the 12.1 aura container system. Every
-- CludesUI module consumes aura displays through this file; modules never call
-- AddAuraGroup / AddAuraSlot / button setters directly. Centralizing this gives us one
-- place for filter-string normalization (exact-string dedup inside the engine),
-- decoration presets, the restyle registry, and combat-safe creation.

local AK = {}
CludesUI.AuraKit = AK

local InCombatLockdown = InCombatLockdown
local CreateFrame = CreateFrame
local issecretvalue = issecretvalue or function()
    return false
end

------------------------------------------------------------------------------
-- Filter normalization
--
-- The engine batches aura parsing per container by EXACT filter string. Two
-- groups only share one scan if their strings are byte-identical, so every
-- filter in the suite is built through AK.Filter to guarantee one canonical
-- token order: base polarity first (HELPFUL/HARMFUL), then the remaining
-- tokens sorted alphabetically (negated tokens sort by their bare name).
------------------------------------------------------------------------------

local filterCache = {}

local function TokenSortKey(unitToken)
    if unitToken:sub(1, 1) == "!" then
        return unitToken:sub(2) .. "!" -- negation sorts directly after its bare token
    end
    return unitToken
end

function AK.Filter(...)
    local styleId = table.concat({ ... }, "|")
    local cached = filterCache[styleId]
    if cached then
        return cached
    end

    local base, rest = nil, {}
    for idx = 1, select("#", ...) do
        local unitToken = select(idx, ...)
        if unitToken == "HELPFUL" or unitToken == "HARMFUL" then
            base = unitToken
        else
            rest[#rest + 1] = unitToken
        end
    end
    table.sort(rest, function(lhs, rhs)
        return TokenSortKey(lhs) < TokenSortKey(rhs)
    end)

    local result
    if base and #rest > 0 then
        result = base .. "|" .. table.concat(rest, "|")
    else
        result = base or table.concat(rest, "|")
    end

    filterCache[styleId] = result
    return result
end

------------------------------------------------------------------------------
-- Duration text formatters
--
-- SetDurationText accepts a NumericFormatter object evaluated engine-side against the
-- (possibly secret) remaining duration. A SecondsFormatter cannot drop the unit on
-- seconds, so this is a banded NumericRuleFormatter that reads like Blizzard's buff
-- frame: bare seconds ("10"), then "2m" from 90 seconds, "2h" from 90 minutes and "2d"
-- from 36 hours, each rounded up. Seconds round up as well, so the text never reads 0
-- while time remains, unless the account turns on Global Settings' Round Timer
-- Seconds Down, which rounds them down as Blizzard's buff frame does.
------------------------------------------------------------------------------

local durationFormatter, durationFormatterS
local preciseDurationFormatters = {}
-- One second past Blizzard's switch to hours and to days; see the band note below.
local HOURS_AT, DAYS_AT = 5401, 129601

-- Round Timer Seconds Down, read once: every timer keeps the formatter it was
-- handed, so a change waits for the reload its row asks for.
local secondsDown
local function SecondsRoundDown()
    if secondsDown == nil then
        secondsDown = CludesUIDB and CludesUIDB.timerSecondsDown == true or false
    end
    return secondsDown
end

local function BuildRuleDurationFormatter(withSecondsUnit, preciseBelow)
    if not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter and Enum.NumericRuleFormatRounding) then
        return nil
    end
    local Up = Enum.NumericRuleFormatRounding.Up
    local secRound = SecondsRoundDown() and Enum.NumericRuleFormatRounding.Down or Up
    local formatFn = C_StringUtil.CreateNumericRuleFormatter()
    -- Schema per the field-proven CDM threshold formatter: step/rounding
    -- live at the BREAKPOINT level; components carry only the divisor.
    -- (The original nested step/rounding inside components -- silently
    -- rejected or default-rounded depending on validation strictness.)
    --
    -- The engine picks a band by the raw value, and when that band's rounding
    -- carries the value into the next band it formats the raw value with the
    -- next band's rules. So hours and days start one second past Blizzard's
    -- switch, keeping the rounded-up "90m" and "36h" in their own band, while
    -- minutes start at 90 seconds itself: the seconds count down from "89" in
    -- either rounding, as Blizzard's do.
    local seconds =
        { threshold = 0, format = withSecondsUnit and "%ds" or "%d", step = 1, rounding = secRound }
    local hours =
        { threshold = HOURS_AT, format = "%dh", step = 3600, rounding = Up, components = { { div = 3600 } } }
    local days =
        { threshold = DAYS_AT, format = "%dd", step = 86400, rounding = Up, components = { { div = 86400 } } }
    local points
    -- > 60, not > 0: with the threshold at exactly one minute the m:ss band is
    -- empty and the table would carry duplicate 60-thresholds -- the standard
    -- table renders identically there.
    if preciseBelow and preciseBelow > 60 then
        -- Below the selected threshold, a clock-style value such as 5:23; under
        -- a minute plain seconds, as in the standard table (rounded-up seconds
        -- carry 59.5 into the clock, which reads it as exactly 1:00). Minutes
        -- start one second past the threshold so the clock reads "10:00" before
        -- "9:59"; at 90 minutes the clock runs up to the hours.
        points = {
            seconds,
            {
                threshold = 60,
                format = "%d:%02d",
                step = 1,
                rounding = secRound,
                components = { { div = 60 }, { mod = 60 } },
            },
        }
        if preciseBelow + 1 < HOURS_AT then
            points[#points + 1] = {
                threshold = preciseBelow + 1,
                format = "%dm",
                step = 60,
                rounding = Up,
                components = { { div = 60 } },
            }
        end
        points[#points + 1] = hours
        points[#points + 1] = days
    else
        points = {
            seconds,
            { threshold = 90, format = "%dm", step = 60, rounding = Up, components = { { div = 60 } } },
            hours,
            days,
        }
    end
    local success = pcall(formatFn.SetBreakpoints, formatFn, points)
    if not success then
        return nil
    end
    return formatFn
end

-- Fallback if the rule formatter is unavailable/rejected: compact
-- one-letter units ("10s"/"2m") -- closest a SecondsFormatter gets.
local function BuildSecondsDurationFormatter()
    local curve = C_CurveUtil.CreateCurve()
    curve:AddPoint(61, Enum.SecondsFormatterInterval.Minutes)
    curve:AddPoint(3601, Enum.SecondsFormatterInterval.Hours)
    curve:AddPoint(86401, Enum.SecondsFormatterInterval.Days)

    local formatFn = C_StringUtil.CreateSecondsFormatter()
    formatFn:SetDefaultAbbreviation(Enum.SecondsFormatterAbbreviation.OneLetter)
    formatFn:SetMinInterval(Enum.SecondsFormatterInterval.Seconds)
    formatFn:SetMaxIntervalCurve(curve)
    formatFn:SetDesiredUnitCount(1)
    if formatFn.SetStripIntervalWhitespace and Enum.SecondsFormatterIntervalWhitespace then
        formatFn:SetStripIntervalWhitespace(Enum.SecondsFormatterIntervalWhitespace.Strip)
    end
    return formatFn
end

-- showSecondsUnit: seconds readings keep their unit ("10s" instead of "10");
-- minutes and up are identical. Two cached instances -- omitting the arg
-- (every pre-existing caller) returns the bare-seconds formatter. The
-- SecondsFormatter fallback shows the unit in both variants (it cannot drop
-- it) -- the accepted degraded look either way.
function AK.GetDurationFormatter(showSecondsUnit, preciseBelow)
    preciseBelow = tonumber(preciseBelow)
    if preciseBelow and preciseBelow > 0 then
        -- The UI tops out at 90 minutes, where the hours begin. Clamp saved and
        -- imported values too so a malformed profile cannot put the bands out
        -- of order.
        preciseBelow = math.max(60, math.floor(preciseBelow + 0.5))
        if preciseBelow > 5400 then
            preciseBelow = 5400
        end
        local styleId = (showSecondsUnit and "s" or "b") .. preciseBelow
        if preciseDurationFormatters[styleId] == nil then
            preciseDurationFormatters[styleId] = BuildRuleDurationFormatter(showSecondsUnit, preciseBelow)
                or false
        end
        return preciseDurationFormatters[styleId] or AK.GetDurationFormatter(showSecondsUnit)
    end
    if showSecondsUnit then
        if not durationFormatterS then
            durationFormatterS = BuildRuleDurationFormatter(true) or BuildSecondsDurationFormatter()
        end
        return durationFormatterS
    end
    if not durationFormatter then
        durationFormatter = BuildRuleDurationFormatter() or BuildSecondsDurationFormatter()
    end
    return durationFormatter
end

------------------------------------------------------------------------------
-- Styles and the button registry
--
-- A style describes how a button is decorated. Buttons are Blizzard-owned
-- AuraButton frames, so per-button state lives in an external weak-keyed
-- table (never written onto the button itself). Regions we create are
-- children of the button, anchored inside it; that is a hard engine rule.
------------------------------------------------------------------------------

AK.styles = {}

-- Per-button region refs: bd[button] = { icon, cooldown, stackCarrier, stack,
-- duration, borderHost, styleKey }
local bd = setmetatable({}, { __mode = "k" })

-- styleButtons[styleKey][button] = true, weak keys, for restyling.
local styleButtons = {}

local function GetStyleSet(lookKey)
    local set = styleButtons[lookKey]
    if not set then
        set = setmetatable({}, { __mode = "k" })
        styleButtons[lookKey] = set
    end
    return set
end

-- Style keys whose apply hit a denied button call while auras were secret.
-- 12.1 (build 68745+): engine aura buttons carry the
-- DenyTaintedAccessWhenAurasAreSecret access restriction, applied by the engine
-- immediately AFTER initializeFrame returns -- so creation-window decoration is always
-- legal, but post-creation reads/writes on the BUTTON object from addon code are
-- rejected in secret contexts (our own child regions stay writable). Deferred keys
-- re-queue when the restriction lifts; see the lift watcher below the restyle worker.
local pendingRestyles = {}

-- The button whose initializeFrame callback is running (AK.MakeInitializer):
-- its creation window, where every call into it is legal whatever the aura
-- restriction says (the engine applies the access restriction right after the
-- callback returns). AK.InCreationWindow / AK.CanTouchButton read it.
local initButton

-- Textured dispel ring (style.dispelBorderTexture): the eight slices of an edge file,
-- in a fixed order (the registration loop walks the array part; the named keys are
-- what CludesUI.LayoutSecretBorderEdges anchors).
local RING_SLICES = { "topLeft", "topRight", "bottomLeft", "bottomRight", "top", "bottom", "left", "right" }

-- Style keys whose textured ring is laid out from an exact border px. That geometry
-- is pixels at UIParent scale, so a UI scale change moves it, and the engine keeps
-- the geometry it snapshotted at registration: the UI-scale re-apply
-- (CludesUI.RegisterPxReapply) restyles these keys, whose changed setKey then
-- re-registers the ring. AK is registered as the owner only while the set has keys.
local pxRingStyles = {}
local function RestylePxRings()
    for styleId in pairs(pxRingStyles) do
        AK.RestyleSoon(styleId)
    end
end

-- Dispel-type ICON channel (style.dispelTypeIcon): ONE texture per button
-- registered with the engine's NATIVE Icon style
-- (Enum.CustomAuraButtonDispelTypeTextureStyle.Icon). Per aura, the engine
-- stamps the RaidFrame-Icon-Debuff<Type> atlas via AuraUtil.
-- SetAuraDispelTypeIcon, writes a white vertex color, and hides on untyped
-- auras (ShouldShowDispelTypeForAura -- showWithoutDispelType unset), all in
-- Blizzard_CustomAuraButton.lua. The aura's dispel type is never read by our
-- code: identical in and out of the secret-value system. NO customDispelColorMap
-- rides along -- the first build of this channel registered five one-hot
-- alpha-mapped textures and the C-side options processor rejected the maps
-- (all five rendered; the rollback also unhooked the ring until /reload).
-- One options table shared across all buttons (engine securecopies per call).
local DISPEL_ICON_POINTS = {
    topleft = "TOPLEFT",
    top = "TOP",
    topright = "TOPRIGHT",
    left = "LEFT",
    center = "CENTER",
    right = "RIGHT",
    bottomleft = "BOTTOMLEFT",
    bottom = "BOTTOM",
    bottomright = "BOTTOMRIGHT",
}
local DISPEL_ICON_OPTS
do
    local iconStyle = Enum
        and Enum.CustomAuraButtonDispelTypeTextureStyle
        and Enum.CustomAuraButtonDispelTypeTextureStyle.Icon
    if iconStyle ~= nil then
        DISPEL_ICON_OPTS = { style = iconStyle, showWhenHarmful = true, showWhenHelpful = false }
    end
end

-- An icon's texcoords under a style. A shaped icon (iconShape with a mask) keeps
-- its button's rect and takes coordinates past 0-1, as Action Bars' shaped icons
-- do: the mask's opening is the button's middle visRatio (each shape's art leaves
-- shapeInsetPx of its 128 clear on every side), and the art's middle (1 - 2 * zoom)
-- fills it, the crop an unshaped icon takes at the same Icon Zoom. Shared with the
-- Player Aura Bars options preview.
function AK.IconTexCoord(look)
    if look.iconShape and look.iconShape ~= "none" and look.shapeMaskPath then
        local visRatio = (128 - 2 * (look.shapeInsetPx or 17)) / 128
        local half = (0.5 - (look.iconZoom or 0.055)) / visRatio
        return 0.5 - half, 0.5 + half, 0.5 - half, 0.5 + half
    end
    local tc = look.texCoord
    if tc then
        return tc[1], tc[2], tc[3], tc[4]
    end
    if look.iconCrop then
        local z = look.iconZoom or 0.07
        return z, 1 - z, z, 1 - z
    end
    return 0, 1, 0, 1
end

local function ApplyStyleToRegions(btnFrame, look)
    local state = bd[btnFrame]
    if not state then
        return
    end

    -- The engine's flow layout only ANCHORS group buttons; their physical size
    -- is entirely ours to set (group layout elementWidth/Height feeds the flow
    -- math only). An unsized button renders nothing. SetSize on aura buttons
    -- is an engine-wrapped call, so restyles skip it when unchanged.
    local wid = look.width or 32
    local hgt = look.height or look.width or 32
    if state.appliedW ~= wid or state.appliedH ~= hgt then
        -- Stamp AFTER the call: SetSize on the button is denied while auras
        -- are secret, and a pre-stamped failure would make the
        -- restriction-lift retry skip the resize as "unchanged".
        btnFrame:SetSize(wid, hgt)
        state.appliedW, state.appliedH = wid, hgt
    end

    -- One mask shared by the icon, cooldown swipe, and base/dispel border art.
    local shaped = look.iconShape and look.iconShape ~= "none" and look.shapeMaskPath
    if shaped then
        if not state.shapeMask then
            state.shapeMask = btnFrame:CreateMaskTexture()
        end
        state.shapeMask:SetTexture(look.shapeMaskPath, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        state.shapeMask:SetAllPoints(btnFrame)
        state.shapeMask:Show()
    elseif state.shapeMask then
        state.shapeMask:Hide()
    end

    if state.icon then
        state.icon:SetTexCoord(AK.IconTexCoord(look))

        -- AddMaskTexture is change-guarded and deferred like d.borderHost's anchor
        -- below: denied while auras are secret, retried once the restriction lifts.
        if shaped then
            if state.akIconShapeKey ~= look.iconShape then
                local success = pcall(function()
                    pcall(state.icon.RemoveMaskTexture, state.icon, state.shapeMask)
                    state.icon:AddMaskTexture(state.shapeMask)
                end)
                if success then
                    state.akIconShapeKey = look.iconShape
                elseif state.styleKey and AK.AurasRestricted() then
                    pendingRestyles[state.styleKey] = true
                end
            end
        elseif state.akIconShapeKey then
            if not state.shapeMask or pcall(state.icon.RemoveMaskTexture, state.icon, state.shapeMask) then
                state.akIconShapeKey = nil
            elseif state.styleKey and AK.AurasRestricted() then
                pendingRestyles[state.styleKey] = true
            end
        end
    end

    if state.cooldown then
        state.cooldown:SetReverse(look.cooldownReverse ~= false)
        state.cooldown:SetDrawEdge(look.cooldownDrawEdge == true)
        state.cooldown:SetHideCountdownNumbers(true) -- duration text comes from the binding, not the swipe
        -- Hidden-swipe gate. SetShown alone does not stick: the engine calls
        -- Cooldown:SetCooldown on this frame whenever the slot's aura data
        -- refreshes, and that native API implicitly re-Shows the frame.
        -- Withholding the frame from SetDurationCooldown does not work either --
        -- that registration is the button's DURATION SOURCE, so a button
        -- without one loses its duration TEXT along with the swipe.
        -- SetDrawSwipe is the knob that means what we want: keep the cooldown
        -- registered and running, draw no swipe from it. It is persistent
        -- cooldown STYLE rather than visibility (SetCooldown never resets it),
        -- and it is annotated AllowedWhenTainted. With swipe, edge, and
        -- countdown numbers all off, a re-shown frame draws nothing, so the
        -- engine's re-Show is harmless.
        local hideSwipe = look.hideSwipe == true
        state.cooldown:SetShown(not hideSwipe)
        if state.akHideSwipe ~= hideSwipe then
            state.akHideSwipe = hideSwipe
            if state.cooldown.SetDrawSwipe then
                state.cooldown:SetDrawSwipe(not hideSwipe)
            end
        end

        -- Clip the swipe to the shape and recolor its silhouette to match, instead
        -- of a plain square/circle radial. Both calls are on our own d.cooldown
        -- region, not the button -- no guard needed.
        local cdMaskKey = shaped and look.iconShape or nil
        if state.akCdMaskKey ~= cdMaskKey then
            if cdMaskKey then
                pcall(state.cooldown.AddMaskTexture, state.cooldown, state.shapeMask)
                if state.cooldown.SetSwipeTexture then
                    pcall(state.cooldown.SetSwipeTexture, state.cooldown, look.shapeMaskPath)
                end
            else
                if state.shapeMask then
                    pcall(state.cooldown.RemoveMaskTexture, state.cooldown, state.shapeMask)
                end
                if state.cooldown.SetSwipeTexture then
                    pcall(state.cooldown.SetSwipeTexture, state.cooldown, "")
                end
            end
            state.akCdMaskKey = cdMaskKey
        end
    end

    -- Modules with their own text pipeline (fonts, anchors, outline rules) set
    -- noDefaultFonts and do all text styling in style.applyExtra instead.
    -- Text anchors are change-guarded (stamp AFTER the calls): SetPoint
    -- with the button as the relative frame is policed by the 12.1 button
    -- access restriction while auras are secret, and unchanged anchors must
    -- make zero button-involving calls so restyles stay live in-instance.
    if state.stack and not look.noDefaultFonts then
        local f = look.stackFont or STANDARD_TEXT_FONT
        state.stack:SetFont(f, look.stackFontSize or 12, look.stackFontFlags or "OUTLINE")
        local sp = look.stackPoint or "BOTTOMRIGHT"
        local sKey = sp .. "|" .. (look.stackX or 2) .. "|" .. (look.stackY or -2)
        if state.akStackAnchor ~= sKey then
            state.stack:ClearAllPoints()
            state.stack:SetPoint(sp, btnFrame, sp, look.stackX or 2, look.stackY or -2)
            state.akStackAnchor = sKey
        end
        local c = look.stackColor
        if c then
            state.stack:SetTextColor(c.r, c.g, c.b, c.a or 1)
        end
    end

    if state.duration then
        if not look.noDefaultFonts then
            local f = look.durationFont or STANDARD_TEXT_FONT
            state.duration:SetFont(f, look.durationFontSize or 11, look.durationFontFlags or "OUTLINE")
            local dp = look.durationPoint or "TOP"
            local drp = look.durationRelPoint or "BOTTOM"
            local aKey = dp .. "|" .. drp .. "|" .. (look.durationX or 0) .. "|" .. (look.durationY or -2)
            if state.akDurAnchor ~= aKey then
                state.duration:ClearAllPoints()
                state.duration:SetPoint(dp, btnFrame, drp, look.durationX or 0, look.durationY or -2)
                state.akDurAnchor = aKey
            end
        end
        -- The engine keeps writing the text either way; visibility is ours.
        state.duration:SetShown(not look.hideDurationText)
    end

    if state.borderHost then
        local Pix = CludesUI.PP
        local b = look.border
        if Pix and b then
            if shaped and look.shapeBorderPath then
                -- A previous non-shaped style may have left either PP strips or
                -- the secret-safe eight-slice texture set on this owned host.
                -- Clear both before the shape ring takes over.
                if state.borderMade then
                    if CludesUI.ApplySecretSafeBorderStyle then
                        CludesUI.ApplySecretSafeBorderStyle(state.borderHost, state, 0, 0, 0, 0, 0, "solid")
                    else
                        Pix.HideBorder(state.borderHost)
                    end
                end
                Pix:ApplyMaskedShapeBorder(
                    state.borderHost,
                    state.shapeMask,
                    look.shapeBorderPath,
                    look.shapeBorderSize or b.size or 1,
                    b[1] or 0,
                    b[2] or 0,
                    b[3] or 0,
                    b[4] or 1
                )
            else
                Pix:HideMaskedShapeBorder(state.borderHost)
                if b.texture and CludesUI.ApplyBorderStyle then
                    -- Aura buttons can expose restricted geometry. Give the owned
                    -- border host an explicit public size (change-guarded because
                    -- anchoring to the aura button is denied while restricted).
                    local borderRect = (look.width or 18) .. "|" .. (look.height or look.width or 18)
                    if state.akBorderRect ~= borderRect then
                        state.borderHost:ClearAllPoints()
                        state.borderHost:SetPoint("CENTER", btnFrame, "CENTER")
                        state.borderHost:SetSize(look.width or 18, look.height or look.width or 18)
                        state.akBorderRect = borderRect
                    end
                    if b.behindUnitFrame then
                        state.borderHost:SetFrameLevel(math.max(0, (b.unitFrameLevel or 1) - 1))
                    else
                        state.borderHost:SetFrameLevel(
                            b.behind and math.max(0, (state.buttonFrameLevel or 1) - 1)
                                or (state.cooldown:GetFrameLevel() + 1)
                        )
                    end
                    -- addonKey/sizeKey pick the per-module texture offset defaults a
                    -- style leaves nil; CDM passes its own so a textured border sits
                    -- where the module's other icons put theirs.
                    local appliedSize = (b.texture and b.texture ~= "" and b.texture ~= "solid")
                            and (b.textureSize or b.size or 1)
                        or (b.size or 1)
                    -- b.edgePx: the surface's exact size (CludesUI.BorderPx), nil = legacy.
                    CludesUI.ApplySecretSafeBorderStyle(
                        state.borderHost,
                        state,
                        appliedSize,
                        b[1] or 0,
                        b[2] or 0,
                        b[3] or 0,
                        b[4] or 1,
                        b.texture or "solid",
                        b.offsetX,
                        b.offsetY,
                        b.shiftX,
                        b.shiftY,
                        b.addonKey or "unitframes",
                        b.sizeKey or b.size or 1,
                        b.edgeScale,
                        b.edgePx
                    )
                    state.borderMade = true
                else
                    -- Solid border on the plain PP path. A style that came back
                    -- from a textured pick leaves the eight-slice edges on this
                    -- host and may never have built PP strips (the textured lane
                    -- only hides them), so presence is decided by the strips
                    -- themselves, not by borderMade.
                    -- A textured exact size registered this host for the UI-scale
                    -- re-apply: the size-0 solid call unregisters it and hides the
                    -- edges (the strips and the host are shown again below).
                    if state._pxsbEdge then
                        CludesUI.ApplySecretSafeBorderStyle(state.borderHost, state, 0, 0, 0, 0, 0, "solid")
                    else
                        local edges = state._secretBorderEdges
                        if edges then
                            for _, texture in pairs(edges) do
                                texture:Hide()
                            end
                        end
                    end
                    local solidPx = b.edgePx or b.size or 1
                    if Pix.GetBorders(state.borderHost) then
                        Pix.UpdateBorder(state.borderHost, solidPx, b[1] or 0, b[2] or 0, b[3] or 0, b[4] or 1)
                        Pix.ShowBorder(state.borderHost)
                    else
                        Pix.CreateBorder(
                            state.borderHost,
                            b[1] or 0,
                            b[2] or 0,
                            b[3] or 0,
                            b[4] or 1,
                            solidPx,
                            "OVERLAY",
                            7
                        )
                    end
                    state.borderMade = true
                end
            end
            state.borderHost:Show()
        else
            if state._pxsbEdge then
                CludesUI.ApplySecretSafeBorderStyle(state.borderHost, state, 0, 0, 0, 0, 0, "solid")
            end
            state.borderHost:Hide()
            if Pix then
                Pix:HideMaskedShapeBorder(state.borderHost)
            end
        end
    end

    -- Engine dispel-type border (style.dispelBorder): textures the engine shows only on
    -- typed (dispellable) auras and tints per dispel type -- per-aura dispel data is
    -- secret, so show/hide and color are ENGINE decisions. The ART is entirely ours,
    -- registered purely as a tint target, and the user's dispel palette rides in via
    -- customDispelColorMap (68824).
    --
    -- FOUR SOLID STRIPS, not one ring-shaped texture: the engine applies options,
    -- visibility and SetVertexColor per registered texture (Blizzard_CustomAuraButton
    -- iterates the whole list), so a four-texture ring is as legal as a one-texture
    -- one. Thickness is GEOMETRY -- a cropped band texture goes sub-texel at large
    -- icon sizes and bilinear-fades to alpha < 1, letting the static border bleed
    -- into the dispel tint; solid strips never sample. Strips also stay off
    -- SetTexCoord, which AddDispelTypeTexture stamps as a secret aspect on every
    -- texture it takes (along with Alpha, VertexColor and Shown), and off
    -- style.width: they hang from the holder, which SetAllPoints the button, so the
    -- button rect drives the ring without ever being read (button rects are
    -- restricted).
    --
    -- The strips live on a dedicated holder one frame level over the static border host
    -- so the recolor always draws ON TOP of the border strips; the text carrier sits one
    -- more above. Registration follows the static border: no border configured, no
    -- dispel recolor (live parity). 68914 reworked the border API into the dispel-type
    -- texture system: the tint-our-own-art style is now PreserveAsset on
    -- Enum.CustomAuraButtonDispelTypeTextureStyle (the old CustomAuraButtonBorderStyle
    -- enum is deleted; its Color value is the ancestor, kept as a fallback for stale PTR
    -- builds). The style MUST resolve: registering without it takes the BorderWithIcon
    -- default, which stamps Blizzard atlas art over ours. PreserveAsset is also the only
    -- style that leaves our geometry alone -- it calls SetAuraBorderColor and nothing
    -- else, no SetTexture and no SetTexCoord.
    --
    -- Shaped bars (style.iconShape) use a SEPARATE single-texture path (d.dispelShapeTex)
    -- instead of the 4 strips: a hexagon/circle/etc outline cannot be built from 4
    -- rectangles. It reuses the pre-shaped <shape>_border.tga art, WHOLE-texture (never
    -- SetTexCoord-cropped -- that cropping is exactly what caused the bug the strips
    -- above replaced) and clipped by the hardware mask (d.shapeMask), sized via the same
    -- mask-expand math as the base border (bExp = 7 - borderPx). The two sets are
    -- mutually exclusive per button; whichever is inactive is kept hidden every pass so a
    -- shape toggle never leaves the other set's textures stuck visible after their
    -- registration is cleared.
    local dispelTint = Enum
        and Enum.CustomAuraButtonDispelTypeTextureStyle
        and Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset
    if dispelTint == nil then
        local legacy = (Enum and Enum.CustomAuraButtonBorderStyle) or AuraButtonBorderStyle
        dispelTint = legacy and legacy.Color
    end
    -- Blizzard Style (style.blizzBorder): ONE texture registered with the
    -- engine's built-in Border style -- the engine stamps Blizzard's own
    -- per-dispel-type debuff border atlas on it (red for untyped debuffs via
    -- showWithoutDispelType), so this IS the stock aura border, art and colour
    -- both engine-owned. No static border, no palette, no strips.
    local blizzBorderStyle = look.blizzBorder
        and btnFrame.AddDispelTypeTexture
        and Enum
        and Enum.CustomAuraButtonDispelTypeTextureStyle
        and Enum.CustomAuraButtonDispelTypeTextureStyle.Border
    -- Textured ring (style.dispelBorderTexture = a border texture key or file path, set
    -- only by a module's opt-in): a fourth set beside the Blizzard border, the shape
    -- ring and the strips. Eight slices cut from the edge art, laid on the aura
    -- border's own geometry (SecretBorderGeometry, the numbers its textured border is
    -- drawn with) and tinted per dispel type by the engine through PreserveAsset like
    -- the strips, so white art takes the dispel colour. Only beside a textured aura
    -- border of positive size (a size-0 border keeps the strips), never with the
    -- Blizzard border or a shaped icon. Every other style pays this one nil test.
    local ringFile
    if look.dispelBorderTexture and look.dispelBorder and not blizzBorderStyle and not shaped then
        local rb = look.border
        if
            rb
            and rb.texture
            and rb.texture ~= ""
            and rb.texture ~= "solid"
            and (rb.textureSize or rb.size or 1) > 0
        then
            ringFile = CludesUI.ResolveBorderTexture(look.dispelBorderTexture)
        end
    end
    -- An exact-size ring rides the UI-scale re-apply (see pxRingStyles); d.akRingPx
    -- marks the buttons that joined it, so every other button pays two nil tests.
    if ringFile and look.border.edgePx then
        if not state.akRingPx then
            state.akRingPx = true
            if state.styleKey and not pxRingStyles[state.styleKey] then
                pxRingStyles[state.styleKey] = true
                CludesUI.RegisterPxReapply(AK, RestylePxRings)
            end
        end
    elseif state.akRingPx then
        state.akRingPx = nil
        if state.styleKey and pxRingStyles[state.styleKey] then
            pxRingStyles[state.styleKey] = nil
            if not next(pxRingStyles) then
                CludesUI.RegisterPxReapply(AK, nil)
            end
        end
    end
    if
        look.dispelBorder
        and state.dispelHolder
        and (btnFrame.AddDispelTypeTexture or btnFrame.SetAuraBorder)
        and dispelTint ~= nil
    then
        if blizzBorderStyle then
            if not state.blizzBorderTex then
                -- Hidden on creation (the engine shows it per aura); no vertex
                -- prewrite needed, the Border style writes white itself.
                local texture = state.dispelHolder:CreateTexture(nil, "OVERLAY")
                if texture.SetSnapToPixelGrid then
                    texture:SetSnapToPixelGrid(false)
                    texture:SetTexelSnappingBias(0)
                end
                texture:Hide()
                state.blizzBorderTex = texture
            end
        elseif shaped and look.shapeBorderPath then
            if not state.dispelShapeTex then
                -- Neutral white tint base, written ONCE here (same rule as the strips
                -- below): registration turns VertexColor into an engine-driven secret
                -- aspect, so this must never be re-written on later restyle passes.
                local texture = state.dispelHolder:CreateTexture(nil, "OVERLAY")
                texture:SetVertexColor(1, 1, 1, 1)
                if texture.SetSnapToPixelGrid then
                    texture:SetSnapToPixelGrid(false)
                    texture:SetTexelSnappingBias(0)
                end
                texture:Hide()
                state.dispelShapeTex = texture
            end
            -- Unlike VertexColor, SetTexture isn't secret-tainted by registration --
            -- must track shape changes here too, or the ring keeps whatever shape's
            -- art was loaded when the texture was first created.
            if state.akDispelShapeTexPath ~= look.shapeBorderPath then
                state.dispelShapeTex:SetTexture(look.shapeBorderPath)
                state.akDispelShapeTexPath = look.shapeBorderPath
            end
        elseif ringFile then
            if not state.dispelRing then
                -- Same rules as the strips below: hidden, white tint base, and the
                -- slice texcoords written ONCE here, before any registration turns
                -- TexCoord, Alpha, VertexColor and Shown into engine aspects.
                local uv = CludesUI.SECRET_BORDER_UV
                local ringTex = {}
                for idx = 1, #RING_SLICES do
                    local styleId = RING_SLICES[idx]
                    local texture = state.dispelHolder:CreateTexture(nil, "OVERLAY")
                    texture:SetTexCoord(unpack(uv[styleId]))
                    texture:SetVertexColor(1, 1, 1, 1)
                    texture:Hide()
                    ringTex[idx] = texture
                    ringTex[styleId] = texture
                end
                state.dispelRing = ringTex
            end
            -- SetTexture is not a registration aspect (the shape ring swaps its art the
            -- same way); the path is also in setKey, so new art re-registers.
            if state.akDispelRingPath ~= ringFile then
                local ringTex = state.dispelRing
                for idx = 1, #RING_SLICES do
                    ringTex[idx]:SetTexture(ringFile, true, true)
                end
                state.akDispelRingPath = ringFile
            end
        elseif not state.dispelStrips then
            -- Flat white: the engine multiplies its dispel color in through SetVertexColor,
            -- so white is the neutral tint base. Written once here, while VertexColor is
            -- still ours -- registration turns it into a secret aspect. Textures on our own
            -- holder, never parented to the button, so creating them outside the button's
            -- one legal creation window is fine.
            --
            -- Hidden on creation. A texture is shown by default, and the engine is what
            -- shows these (per aura, on a typed one) -- if the registration below is denied
            -- while auras are secret, an unhidden strip set would sit on the icon as a plain
            -- WHITE ring until the restriction lifts and the deferred restyle re-runs.
            local strips = {}
            for idx = 1, 4 do
                local texture = state.dispelHolder:CreateTexture(nil, "OVERLAY")
                texture:SetColorTexture(1, 1, 1, 1)
                if texture.SetSnapToPixelGrid then
                    texture:SetSnapToPixelGrid(false)
                    texture:SetTexelSnappingBias(0)
                end
                texture:Hide()
                strips[idx] = texture
            end
            state.dispelStrips = strips
        end
    end

    -- Dispel-type icon texture (see the channel catalog above). No art or tint
    -- prewrites: the engine stamps atlas and vertex color per aura paint, and
    -- registration turns Alpha/VertexColor/TexCoords/Shown into engine-driven
    -- secret aspects anyway. Hidden on creation for the same reason as the
    -- strips: the engine is what shows it. OVERLAY sublevel 2 draws it above
    -- the recolor ring on the shared holder. Requires the NATIVE
    -- AddDispelTypeTexture plus the Icon enum -- never the legacy alias.
    if
        look.dispelTypeIcon
        and state.dispelHolder
        and not state.dispelIconTex
        and btnFrame.AddDispelTypeTexture
        and DISPEL_ICON_OPTS
    then
        local texture = state.dispelHolder:CreateTexture(nil, "OVERLAY", nil, 2)
        if texture.SetSnapToPixelGrid then
            texture:SetSnapToPixelGrid(false)
            texture:SetTexelSnappingBias(0)
        end
        texture:Hide()
        state.dispelIconTex = texture
    end

    -- The four sets are mutually exclusive: whichever are inactive stay hidden.
    local dispelSet
    if blizzBorderStyle and state.blizzBorderTex then
        dispelSet = { state.blizzBorderTex }
        if state.dispelStrips then
            for idx = 1, 4 do
                state.dispelStrips[idx]:Hide()
            end
        end
        if state.dispelShapeTex then
            state.dispelShapeTex:Hide()
        end
        if state.dispelRing then
            for idx = 1, #RING_SLICES do
                state.dispelRing[idx]:Hide()
            end
        end
    elseif shaped and state.dispelShapeTex then
        dispelSet = { state.dispelShapeTex }
        if state.dispelStrips then
            for idx = 1, 4 do
                state.dispelStrips[idx]:Hide()
            end
        end
        if state.blizzBorderTex then
            state.blizzBorderTex:Hide()
        end
        if state.dispelRing then
            for idx = 1, #RING_SLICES do
                state.dispelRing[idx]:Hide()
            end
        end
    elseif ringFile and state.dispelRing then
        dispelSet = state.dispelRing
        if state.dispelStrips then
            for idx = 1, 4 do
                state.dispelStrips[idx]:Hide()
            end
        end
        if state.dispelShapeTex then
            state.dispelShapeTex:Hide()
        end
        if state.blizzBorderTex then
            state.blizzBorderTex:Hide()
        end
    elseif state.dispelStrips then
        dispelSet = state.dispelStrips
        if state.dispelShapeTex then
            state.dispelShapeTex:Hide()
        end
        if state.blizzBorderTex then
            state.blizzBorderTex:Hide()
        end
        if state.dispelRing then
            for idx = 1, #RING_SLICES do
                state.dispelRing[idx]:Hide()
            end
        end
    elseif state.dispelRing then
        -- Ring built, no strips, and the ring no longer wanted (dispel border off):
        -- it is still the set to clear and park below.
        dispelSet = state.dispelRing
        if state.dispelShapeTex then
            state.dispelShapeTex:Hide()
        end
        if state.blizzBorderTex then
            state.blizzBorderTex:Hide()
        end
    end

    if dispelSet or state.dispelIconTex then
        -- Level re-assert (change-guarded): a style can move the border host's level;
        -- the ring stays FOUR levels above it (PP strip container at +1, DM fx
        -- border-override container at +2, DM per-filter glow at +3 -- the dispel
        -- recolor always wins over every border and glow), the text carrier one more.
        -- All owned frames -- legal under restriction.
        local bl = state.borderHost and state.borderHost:GetFrameLevel() or 0
        if state.akDispelLvl ~= bl then
            state.dispelHolder:SetFrameLevel(bl + 4)
            if state.stackCarrier then
                state.stackCarrier:SetFrameLevel(bl + 5)
            end
            state.akDispelLvl = bl
        end

        if not dispelSet then
            -- Icons-only style: no ring set was ever created, skip ring geometry.
        elseif blizzBorderStyle and state.blizzBorderTex then
            -- The stock buff frame draws its 40px border round a 30px icon: a
            -- sixth of the icon on each side. Anchored to the holder (button
            -- rects are restricted) from the style's own size. Folded into
            -- setKey below: the engine snapshots geometry at registration.
            local bw, bh = look.width or 18, look.height or look.width or 18
            local shapeKey = bw .. "|" .. bh
            if state.akBlizzGeom ~= shapeKey then
                local ox, oy = bw / 6, bh / 6
                state.blizzBorderTex:ClearAllPoints()
                state.blizzBorderTex:SetPoint("TOPLEFT", state.dispelHolder, "TOPLEFT", -ox, oy)
                state.blizzBorderTex:SetPoint("BOTTOMRIGHT", state.dispelHolder, "BOTTOMRIGHT", ox, -oy)
                state.akBlizzGeom = shapeKey
            end
        elseif shaped and state.dispelShapeTex then
            -- Same bExp mask-expand math as PP.ApplyMaskedShapeBorder, inlined since that
            -- helper also writes SetVertexColor, which would fight the engine's per-aura
            -- tint once registered. shapeBorderSize (not raw dispelBorderPx) so this ring
            -- uses the same remapped units as the base shaped border.
            local px = look.shapeBorderSize or look.dispelBorderPx or 2
            local shapeKey = look.iconShape .. "|" .. px
            if state.akDispelGeom ~= shapeKey then
                local PPx = CludesUI.PP
                local bExp = 7 - math.min(px, 7)
                -- Pcall'd like the icon's own reposition above: an uncaught error would
                -- abort the rest of this function, and the geomKey guard would never
                -- retry with the same inputs.
                local success = pcall(function()
                    state.dispelShapeTex:ClearAllPoints()
                    PPx.Point(state.dispelShapeTex, "TOPLEFT", state.dispelHolder, "TOPLEFT", -bExp, bExp)
                    PPx.Point(state.dispelShapeTex, "BOTTOMRIGHT", state.dispelHolder, "BOTTOMRIGHT", bExp, -bExp)
                    if state.shapeMask then
                        pcall(state.dispelShapeTex.RemoveMaskTexture, state.dispelShapeTex, state.shapeMask)
                        pcall(state.dispelShapeTex.AddMaskTexture, state.dispelShapeTex, state.shapeMask)
                    end
                end)
                if success then
                    state.akDispelGeom = shapeKey
                elseif state.styleKey and AK.AurasRestricted() then
                    pendingRestyles[state.styleKey] = true
                end
            end
        elseif dispelSet == state.dispelRing then
            -- The aura border's own geometry: the same arguments its textured lane
            -- passes ApplySecretSafeBorderStyle above, as numbers only. That call is
            -- not used for the ring: it rewrites colour and Show on every pass and
            -- registers exact sizes for the UI-scale re-apply, all engine-owned here.
            -- Change-guarded on the numbers (no per-pass string); the key built on a
            -- change is the setKey, because the engine snapshots geometry at
            -- registration. Pcall'd like the shape ring's reposition.
            if ringFile then
                local rb = look.border
                local sz = rb.textureSize or rb.size or 1
                local edge, aL, aT, aR, aB = CludesUI.SecretBorderGeometry(
                    state.dispelHolder,
                    sz,
                    rb.texture,
                    rb.offsetX,
                    rb.offsetY,
                    rb.shiftX,
                    rb.shiftY,
                    rb.addonKey or "unitframes",
                    rb.sizeKey or rb.size or 1,
                    rb.edgeScale,
                    rb.edgePx
                )
                if
                    state.akRingEdge ~= edge
                    or state.akRingL ~= aL
                    or state.akRingT ~= aT
                    or state.akRingR ~= aR
                    or state.akRingB ~= aB
                    or state.akRingKeyPath ~= ringFile
                then
                    local ringTex, holderFrame = state.dispelRing, state.dispelHolder
                    local success = pcall(function()
                        for idx = 1, #RING_SLICES do
                            ringTex[idx]:ClearAllPoints()
                        end
                        CludesUI.LayoutSecretBorderEdges(ringTex, holderFrame, edge, aL, aT, aR, aB)
                    end)
                    if success then
                        state.akRingEdge, state.akRingL, state.akRingT, state.akRingR, state.akRingB = edge, aL, aT, aR, aB
                        state.akRingKeyPath = ringFile
                        state.akDispelRingKey = "tex:"
                            .. ringFile
                            .. "|"
                            .. edge
                            .. "|"
                            .. aL
                            .. "|"
                            .. aT
                            .. "|"
                            .. aR
                            .. "|"
                            .. aB
                    elseif state.styleKey and AK.AurasRestricted() then
                        pendingRestyles[state.styleKey] = true
                    end
                end
            end
        else
            -- Physical-pixel thickness by GEOMETRY. t converts the user's setting into this
            -- frame's units via the holder's effective scale (our frame -- readable). The
            -- side strips are inset by t top and bottom so no two strips ever overlap at a
            -- corner: a dispel color carrying alpha < 1 would double-blend there and read as
            -- four darker corner pixels. Change-guarded on t alone -- the anchors are fixed
            -- to the holder, which tracks the button, so nothing else can move them.
            local px = look.dispelBorderPx or 2
            local t = px
            local eff = state.dispelHolder:GetEffectiveScale()
            if eff and eff > 0 then
                local PPx = CludesUI.PP
                t = px * ((PPx and PPx.perfect) or 0.75) / eff
            end
            if state.akDispelT ~= t then
                local stack = state.dispelStrips
                stack[1]:ClearAllPoints()
                stack[1]:SetPoint("TOPLEFT", state.dispelHolder, "TOPLEFT", 0, 0)
                stack[1]:SetPoint("TOPRIGHT", state.dispelHolder, "TOPRIGHT", 0, 0)
                stack[1]:SetHeight(t)
                stack[2]:ClearAllPoints()
                stack[2]:SetPoint("BOTTOMLEFT", state.dispelHolder, "BOTTOMLEFT", 0, 0)
                stack[2]:SetPoint("BOTTOMRIGHT", state.dispelHolder, "BOTTOMRIGHT", 0, 0)
                stack[2]:SetHeight(t)
                stack[3]:ClearAllPoints()
                stack[3]:SetPoint("TOPLEFT", state.dispelHolder, "TOPLEFT", 0, -t)
                stack[3]:SetPoint("BOTTOMLEFT", state.dispelHolder, "BOTTOMLEFT", 0, t)
                stack[3]:SetWidth(t)
                stack[4]:ClearAllPoints()
                stack[4]:SetPoint("TOPRIGHT", state.dispelHolder, "TOPRIGHT", 0, -t)
                stack[4]:SetPoint("BOTTOMRIGHT", state.dispelHolder, "BOTTOMRIGHT", 0, t)
                stack[4]:SetWidth(t)
                state.akDispelT = t
            end
        end

        -- Icon geometry (change-guarded; folded into setKey below because the
        -- engine snapshots a texture's geometry at registration time, so any
        -- change here must ride a clear+re-add cycle to take effect). Anchored
        -- to the holder, never the button (button rects are restricted).
        local icg = look.dispelTypeIcon
        if icg and state.dispelIconTex then
            local shapeKey = (icg.pos or "center")
                .. "|"
                .. (icg.size or 16)
                .. "|"
                .. (icg.offX or 0)
                .. "|"
                .. (icg.offY or 0)
            if state.akDispelIconGeom ~= shapeKey then
                local point = DISPEL_ICON_POINTS[icg.pos] or "CENTER"
                state.dispelIconTex:SetSize(icg.size or 16, icg.size or 16)
                state.dispelIconTex:ClearAllPoints()
                state.dispelIconTex:SetPoint(point, state.dispelHolder, point, icg.offX or 0, icg.offY or 0)
                state.akDispelIconGeom = shapeKey
            end
        end

        -- Registration follows the static border AND a nonzero thickness
        -- (0 = the user disabled the dispel recolor outright). setKey additionally
        -- tracks WHICH texture set (strip vs shape) is meant to be registered, so a
        -- shape toggle forces the same clear+re-add cycle a palette edit does --
        -- AddDispelTypeTexture has no "swap one entry" semantics, the whole
        -- registration is all-or-nothing either way.
        local borderWant = (
            look.dispelBorder
            and dispelSet ~= nil
            and (
                (blizzBorderStyle and state.blizzBorderTex) or (look.border and (look.dispelBorderPx or 2) > 0)
            )
        )
                and true
            or false
        local iconWant = (look.dispelTypeIcon and state.dispelIconTex ~= nil) and true or false
        local wanted = borderWant or iconWant
        local mapFP = look.dispelColorFP or ""
        -- Includes the size-derived px: the engine snapshots this texture's geometry
        -- at registration time, so a border-size-only change (same shape, same want)
        -- needs the same clear+re-add cycle or the OLD ring geometry keeps rendering.
        -- Ring-only styles keep their historical keys ("strip"/"shape:...") so
        -- shipping the icon channel forces no re-registration on them; the icon
        -- suffix folds in the icon geometry for the same snapshot reason. The
        -- Blizzard border folds in its own geometry key the same way.
        local setKey = "noborder"
        if borderWant then
            if blizzBorderStyle and state.blizzBorderTex then
                setKey = "blizz:" .. (state.akBlizzGeom or "")
            elseif shaped and state.dispelShapeTex then
                setKey = "shape:"
                    .. look.iconShape
                    .. "|"
                    .. (look.shapeBorderSize or look.dispelBorderPx or 2)
            elseif dispelSet == state.dispelRing then
                -- "tex:<path>|<edge>|<offsets>", built only when the ring's geometry
                -- changes (a UI scale move under an exact size included).
                setKey = state.akDispelRingKey or "tex:"
            else
                setKey = "strip"
            end
        end
        if iconWant then
            setKey = setKey .. "|icons:" .. (state.akDispelIconGeom or "")
        end
        if
            state.dispelBorderOn ~= wanted or (wanted and (state.akDispelMapFP ~= mapFP or state.akDispelSet ~= setKey))
        then
            -- Stamp only on SUCCESS: these are button calls, denied while auras are
            -- secret; a pre-stamped failure would strand the registration in the wrong
            -- state after the restriction lifts. A restricted failure defers this
            -- style key to the lift drain. AddDispelTypeTexture APPENDS (unlike the
            -- old set-semantics alias), so a re-registration must clear first -- and
            -- if the clear is denied, the add is skipped too, or the button would
            -- accumulate duplicate entries.
            local clearFn = btnFrame.ClearDispelTypeTextures or btnFrame.ClearAuraBorder
            if wanted then
                local proceed = true
                if state.dispelBorderOn then
                    proceed = (clearFn and pcall(clearFn, btnFrame)) and true or false
                end
                if proceed then
                    -- ALL OR NOTHING (1 add for a shape, 4 for strips). A denial can land
                    -- on any one of them, and a partial set is worse than none: the engine
                    -- would tint some sides/none and leave the rest sitting in the user's
                    -- static border color. On any failure the whole set is cleared again
                    -- (the clear is a full reset -- "self.dispelTypeTextures = {}") and
                    -- the style key is deferred to the restriction lift, which re-runs
                    -- this from a known-empty state. One options table shared across every
                    -- add: the engine securecopies it per call, so sharing it cannot leak
                    -- between them.
                    local addFn = btnFrame.AddDispelTypeTexture or btnFrame.SetAuraBorder
                    -- Nothing is registered right now (fresh or just cleared), so
                    -- Shown is ours again: park whichever set this cycle does not
                    -- re-add, or it would keep the engine's last visible state.
                    if not borderWant and dispelSet then
                        for idx = 1, #dispelSet do
                            dispelSet[idx]:Hide()
                        end
                    end
                    if not iconWant and state.dispelIconTex then
                        state.dispelIconTex:Hide()
                    end
                    local added = true
                    if borderWant then
                        local options
                        if blizzBorderStyle and state.blizzBorderTex then
                            -- Stock art needs no palette; untyped debuffs get the
                            -- stock red "None" border like the buff frame.
                            options = {
                                style = blizzBorderStyle,
                                showWhenHarmful = true,
                                showWhenHelpful = false,
                                showWithoutDispelType = true,
                            }
                        else
                            options = {
                                style = dispelTint,
                                showWhenHarmful = true,
                                showWhenHelpful = look.dispelHelpful == true,
                                customDispelColorMap = look.dispelColorMap,
                            }
                        end
                        for idx = 1, #dispelSet do
                            if not pcall(addFn, btnFrame, dispelSet[idx], options) then
                                added = false
                                break
                            end
                        end
                    end
                    if added and iconWant then
                        -- Native call only (creation gated on it): the legacy
                        -- alias predates the Icon style.
                        if
                            not pcall(
                                btnFrame.AddDispelTypeTexture,
                                btnFrame,
                                state.dispelIconTex,
                                DISPEL_ICON_OPTS
                            )
                        then
                            added = false
                        end
                    end
                    if added then
                        state.dispelBorderOn = wanted
                        state.akDispelMapFP = mapFP
                        state.akDispelSet = setKey
                    else
                        -- Rollback. dispelBorderOn goes FALSE rather than keeping its old
                        -- value: the clear above already succeeded, so nothing is
                        -- registered now whatever the flag said before.
                        if clearFn then
                            pcall(clearFn, btnFrame)
                        end
                        state.dispelBorderOn = false
                        if state.styleKey and AK.AurasRestricted() then
                            pendingRestyles[state.styleKey] = true
                        end
                    end
                elseif state.styleKey and AK.AurasRestricted() then
                    pendingRestyles[state.styleKey] = true
                end
            else
                if clearFn and pcall(clearFn, btnFrame) then
                    if dispelSet then
                        for idx = 1, #dispelSet do
                            dispelSet[idx]:Hide()
                        end
                    end
                    if state.dispelIconTex then
                        state.dispelIconTex:Hide()
                    end
                    state.dispelBorderOn = wanted
                elseif state.styleKey and AK.AurasRestricted() then
                    pendingRestyles[state.styleKey] = true
                end
            end
        end
    end

    -- Tooltip behavior (68914 button APIs): combat-only hiding and anchor
    -- overrides from the 4-state tooltip mode (style.tooltipCombatHide /
    -- style.tooltipAnchor = "cursor"). Button-surface calls: change-guarded,
    -- stamped on success only, deferred to the restriction lift when denied.
    -- API-existence guards keep stale builds inert. Skipped entirely for
    -- noTooltips styles: these buttons must never show a tooltip, and
    -- configuring tooltip behaviour re-arms the button's mouse as a side
    -- effect (the nameplate click/tooltip eater), so never touch the tooltip
    -- surface of a button that has no tooltip to configure.
    if not look.noTooltips then
        -- Style flip noTooltips -> tooltips (e.g. the unit-frame aura-tooltip
        -- toggle re-enabled): this button's motion was disabled by the pass
        -- below, and the tooltip-config calls underneath are change-guarded by
        -- stamps that still match, so nothing else would re-arm it. Re-enable
        -- explicitly, only for buttons we ourselves turned off (akMotionOff),
        -- so buttons that were never noTooltips see zero new calls.
        if state.akMotionOff and btnFrame.SetMouseMotionEnabled then
            if pcall(btnFrame.SetMouseMotionEnabled, btnFrame, true) then
                state.akMotionOff = nil
            elseif state.styleKey and AK.AurasRestricted() then
                pendingRestyles[state.styleKey] = true
            end
        end
        if btnFrame.SetHideTooltipInCombat then
            local wantCombat = look.tooltipCombatHide and true or false
            if state.akTipCombat ~= wantCombat then
                if pcall(btnFrame.SetHideTooltipInCombat, btnFrame, wantCombat) then
                    state.akTipCombat = wantCombat
                elseif state.styleKey and AK.AurasRestricted() then
                    pendingRestyles[state.styleKey] = true
                end
            end
        end
        if btnFrame.SetTooltipAnchorPoint then
            local wantAnchor = (look.tooltipAnchor == "cursor") and "ANCHOR_CURSOR" or "ANCHOR_BOTTOMLEFT"
            if state.akTipAnchor ~= wantAnchor then
                if pcall(btnFrame.SetTooltipAnchorPoint, btnFrame, wantAnchor) then
                    state.akTipAnchor = wantAnchor
                elseif state.styleKey and AK.AurasRestricted() then
                    pendingRestyles[state.styleKey] = true
                end
            end
        end
    end

    -- Re-assert the mouse state the style wants. It has to run AFTER the tooltip calls
    -- above: configuring tooltip behaviour on an engine button turns its mouse back on,
    -- which silently re-opened the nameplate click-eater. Motion needs the same
    -- treatment: the module motion passes are change-guarded by stamps that still read
    -- "off" after the engine flips it back, so they never repair it (field evidence:
    -- debuff tooltips appearing over empty space beside nameplates, whose styles set
    -- noTooltips). Running here also covers every Restyle, so a settings change cannot
    -- re-open either one. Same deferral as the neighbours above when the button is
    -- locked down while auras are secret.
    -- The click channel is symmetric, unlike the click-off-only pass this used to be.
    -- A style that GAINS cancelButtons later only reaches its already-created buttons
    -- through Restyle (PAB's per-bar "Right-Click to Cancel" toggled off and back on, a
    -- profile switch into a profile that has it on), and nothing undid the earlier
    -- SetMouseClickEnabled(false) -- the bar stayed click-through until the next
    -- /reload, with the right-click landing on the container below the icon. Field
    -- report 2026-08-12: player buffs that cannot be right-click cancelled, /fstack
    -- showing no button above the AuraContainer. SetCancelAuraButtons is re-asserted in
    -- the same breath: it ran at button creation only, so the re-enabled toggle also
    -- needed its click token registered again (Blizzard's own
    -- AuraButtonSharedMixin:SetCancelAuraButtons -> RegisterForClicks). Change-guarded
    -- by stamps, both deferred to the restriction lift like the neighbours above.
    if look.cancelButtons then
        if state.akClickOff and btnFrame.SetMouseClickEnabled then
            if pcall(btnFrame.SetMouseClickEnabled, btnFrame, true) then
                state.akClickOff = nil
            elseif state.styleKey and AK.AurasRestricted() then
                pendingRestyles[state.styleKey] = true
            end
        end
        if state.akCancel ~= look.cancelButtons and btnFrame.SetCancelAuraButtons then
            if pcall(btnFrame.SetCancelAuraButtons, btnFrame, look.cancelButtons) then
                state.akCancel = look.cancelButtons
            elseif state.styleKey and AK.AurasRestricted() then
                pendingRestyles[state.styleKey] = true
            end
        end
    elseif btnFrame.SetMouseClickEnabled then
        -- Re-asserted every pass (not stamp-guarded): configuring tooltip behaviour on
        -- an engine button turns its mouse back on, which silently re-opened the
        -- nameplate click-eater. The stamp only records that WE own the off state, for
        -- the re-arm above.
        if pcall(btnFrame.SetMouseClickEnabled, btnFrame, false) then
            state.akClickOff = true
        elseif state.styleKey and AK.AurasRestricted() then
            pendingRestyles[state.styleKey] = true
        end
    end
    if look.noTooltips and btnFrame.SetMouseMotionEnabled then
        if pcall(btnFrame.SetMouseMotionEnabled, btnFrame, false) then
            -- Deliberately re-asserted every pass (the engine re-arms motion
            -- as a side effect of tooltip config); the stamp only records
            -- that WE own the off state, for the flip-back re-arm above.
            state.akMotionOff = true
        elseif state.styleKey and AK.AurasRestricted() then
            pendingRestyles[state.styleKey] = true
        end
    end

    -- Mouse-area insets (style.hitInsetX / hitInsetY, UI units per side). The
    -- engine's aura buttons share one tooltip, and every button's OnLeave hides
    -- it without checking who owns it (AuraButtonPrivateMixin:HideTooltip). Where
    -- neighbouring buttons overlap (negative spacing) the cursor stands on both,
    -- so the button it is leaving hides the tooltip the next one just showed:
    -- tooltips that vanish when moving from one icon onto the next. Insetting
    -- each mouse area by half the overlap keeps the areas apart while the icons
    -- still overlap. Change-guarded, deferred to the restriction lift when denied.
    local hitX, hitY = look.hitInsetX or 0, look.hitInsetY or 0
    if (state.akHitX or 0) ~= hitX or (state.akHitY or 0) ~= hitY then
        if
            btnFrame.SetHitRectInsets and pcall(btnFrame.SetHitRectInsets, btnFrame, hitX, hitX, hitY, hitY)
        then
            state.akHitX, state.akHitY = hitX, hitY
        elseif state.styleKey and AK.AurasRestricted() then
            pendingRestyles[state.styleKey] = true
        end
    end

    -- Weapon-enchant cells (stamped by AK.EnchantCellInit): the stock
    -- temp-enchant ring under Blizzard Style, re-fitted on every restyle.
    if state.enchantCell then
        AK.ApplyBlizzEnchantRing(btnFrame, state, look)
    end

    -- Blizzard Style nameplate cells: the stock rounded mask and ring.
    if look.blizzRoundArt or state.blizzRoundRing then
        AK.ApplyBlizzRoundArt(btnFrame, state, look, shaped)
    end

    -- Module-specific styling pass; runs at init and on every Restyle.
    if look.applyExtra then
        look.applyExtra(btnFrame, state, look)
    end
end

-- SetDurationText options, 68914 schema: formatter -> textFormatter,
-- textColorCurve -> textColor = { curve, property }, and binding-level knobs
-- (updateInterval, expiredText, zeroDurationText, timeModifier) no longer
-- exist as bare options -- they travel on a caller-configured
-- DurationTextBinding passed as options.binding (the engine copies it at
-- registration). The old one-arg SetTextColorCurve consumer bug is fixed
-- upstream in 68914, so color curves are live for the first time.

-- The curve property the engine recolors against; RemainingDuration is 0, so resolve
-- with an explicit nil check (never `and/or` an enum that can legitimately be zero).
function AK.DurationTextColor(curve)
    if not curve then
        return nil
    end
    local e = Enum and Enum.DurationTextBindingProperty
    local prop = e and e.RemainingDuration
    if prop == nil then
        prop = 0
    end
    return { curve = curve, property = prop }
end

-- Builds a SetDurationText options table in the 68914 schema. When a
-- binding-level knob (updateInterval) is requested, the formatter and the
-- knob are configured on a fresh binding and passed via options.binding;
-- otherwise the plain textFormatter key suffices.
function AK.BuildDurationTextOpts(formatFn, colorCurve, updateInterval)
    local options
    if updateInterval and C_DurationUtil and C_DurationUtil.CreateDurationTextBinding then
        local binding = C_DurationUtil.CreateDurationTextBinding()
        if formatFn then
            binding:SetFormatter(formatFn)
        end
        binding:SetUpdateInterval(updateInterval)
        options = { binding = binding }
    else
        options = { textFormatter = formatFn }
    end
    if colorCurve then
        options.textColor = AK.DurationTextColor(colorCurve)
    end
    return options
end

-- Registration armor: an uncaught error inside SetDurationText aborts the
-- whole engine CreateFrameBatch (killing the AddAuraSlot/AddAuraGroup that
-- triggered it), so every attempt is pcall-wrapped and degrades in steps --
-- full options, then without the color binding, then bare. This is the
-- standing rule for novel engine option paths, kept even though the 68824
-- one-arg SetTextColorCurve bug this guard was born for is fixed.
-- Returns (registered, full): registered = some registration landed;
-- full = the complete option set landed. Callers that stamp-after-success
-- (BmRebindDurationCurve) key off these -- this function never throws, so
-- a denied button call under restriction must be visible in the returns.
function AK.SetDurationTextSafe(btnFrame, fontString, durationOpts)
    if pcall(btnFrame.SetDurationText, btnFrame, fontString, durationOpts) then
        return true, true
    end
    if durationOpts.textColor ~= nil then
        durationOpts.textColor = nil
        if pcall(btnFrame.SetDurationText, btnFrame, fontString, durationOpts) then
            return true, false
        end
    end
    if pcall(btnFrame.SetDurationText, btnFrame, fontString, {}) then
        return true, false
    end
    return false, false
end

-- Returns the initializeFrame callback for a style. It runs ONCE per created
-- button (buttons are pre-created in engine batches of 10, so it fires at
-- group-declare time, not per shown aura), and it receives the PUBLIC button
-- reference. All region wiring happens here. rec: the group record of an
-- aura group (AK.AddGroupToContainer), which numbers its buttons in build
-- order for AK.ButtonCanShow.
function AK.MakeInitializer(lookKey, extra, record)
    local wasBuilt = 0
    local function Init(btnFrame)
        local look = AK.styles[lookKey] or {}
        local state = {}
        bd[btnFrame] = state
        state.styleKey = lookKey
        if record then
            wasBuilt = wasBuilt + 1
            state.akGroup, state.akIndex = record, wasBuilt
            record.buttons[wasBuilt] = btnFrame
        end

        -- Bare mode: no standard regions at all. The button is a pure
        -- presence-driven host (engine still drives its visibility); the
        -- module builds whatever it wants in applyExtra/extra.
        if look.noRegions then
            ApplyStyleToRegions(btnFrame, look)
            GetStyleSet(lookKey)[btnFrame] = true
            if extra then
                extra(btnFrame, state, look)
            end
            return
        end

        -- Create every region first, style them, and only THEN register them
        -- with the button: each Set* registration immediately runs the engine's
        -- UpdateAuraDisplay, which SetText()s our font strings -- an unstyled
        -- FontString has no font assigned and hard-errors inside the engine.

        state.icon = btnFrame:CreateTexture(nil, "ARTWORK")
        state.icon:SetAllPoints(btnFrame)

        -- CooldownFrameTemplate supplies the swipe/edge textures; a bare
        -- Cooldown renders no swipe at all. The template carries no frame
        -- scripts, so it is aspect-safe on button children.
        state.cooldown = CreateFrame("Cooldown", nil, btnFrame, "CooldownFrameTemplate")
        state.cooldown:SetAllPoints(btnFrame)

        -- Level order above the swipe: border first (as close to the icon as possible),
        -- then the text carrier -- duration/stack text must never render behind the
        -- border strips. The three holders below are pure art/text carriers stacked
        -- over the whole button, so none of them may take mouse input: on a NAMEPLATE
        -- aura they sit between the cursor and the plate's own click region, and a
        -- click that lands on one is swallowed instead of switching target --
        -- unmissable in M+, where every enemy plate is covered in debuff icons. The
        -- button itself keeps its mouse for tooltips. (CUI_Nameplates_AuraContainers
        -- does the same for its glow host.)
        state.borderHost = CreateFrame("Frame", nil, btnFrame)
        state.borderHost:SetAllPoints(btnFrame)
        state.borderHost:SetFrameLevel(state.cooldown:GetFrameLevel() + 1)
        state.borderHost:EnableMouse(false)
        -- Cache while initializeFrame still has legal button access. A textured
        -- Shadow selected later must never call button:GetFrameLevel() after the
        -- engine has applied DenyTaintedAccessWhenAurasAreSecret.
        state.buttonFrameLevel = btnFrame:GetFrameLevel()

        -- Dispel-ring holder: its own frame between the border host and the text
        -- carrier so the engine-tinted ring ALWAYS WINS over every border AND the DM
        -- per-filter glow. +4, not +3: PP.CreateBorder parks its strips on a CONTAINER
        -- child at borderHost+1, the DM per-filter border override's container lands at
        -- borderHost+2, and the DM per-filter glow itself sits at borderHost+3
        -- (ApplyDmFx / PAB_ApplyDmFx) -- the ring clears all three. Created
        -- UNCONDITIONALLY here -- this is the only guaranteed-legal window for
        -- parenting a frame to the button, and a style can gain dispelBorder later via
        -- a settings toggle (UF) when the window is long closed.
        state.dispelHolder = CreateFrame("Frame", nil, btnFrame)
        state.dispelHolder:SetAllPoints(btnFrame)
        state.dispelHolder:SetFrameLevel(state.borderHost:GetFrameLevel() + 4)
        state.dispelHolder:EnableMouse(false)

        -- Stack and duration text ride a carrier frame above the cooldown,
        -- borders, DM glow, and dispel ring so none of them can cover the text.
        state.stackCarrier = CreateFrame("Frame", nil, btnFrame)
        state.stackCarrier:SetAllPoints(btnFrame)
        state.stackCarrier:SetFrameLevel(state.borderHost:GetFrameLevel() + 5)
        state.stackCarrier:EnableMouse(false)
        state.stack = state.stackCarrier:CreateFontString(nil, "OVERLAY")
        state.duration = state.stackCarrier:CreateFontString(nil, "OVERLAY")

        -- Engine aura buttons come CLICK-enabled. On nameplates a click-alive
        -- icon sits between the cursor and the plate's click region, eating
        -- target-switch clicks (measured in-game: the M+ "takes several
        -- clicks to swap target" report was an CUI plate aura icon with
        -- clicks on). This is the ONLY reliable place to turn them off:
        -- post-creation writes on the button are denied in secret contexts
        -- (12.x DenyTaintedAccessWhenAurasAreSecret), which is combat --
        -- exactly when it matters. Motion stays per-style so tooltips keep
        -- working where styles want them. Styles that wire a click action
        -- (cancelButtons: player buffs right-click-to-cancel, applied below)
        -- keep their clicks -- those buttons overlay nothing clickable.
        if not look.cancelButtons then
            pcall(btnFrame.SetMouseClickEnabled, btnFrame, false)
        end

        ApplyStyleToRegions(btnFrame, look)

        btnFrame:SetIcon(state.icon)
        -- Re-registering the icon re-runs the button's visibility: the kick for
        -- the animations it runs itself (AK.KickShownAnimations).
        state.akKickIcon = state.icon
        btnFrame:SetDurationCooldown(state.cooldown)
        btnFrame:SetApplicationCount(state.stack, {})

        -- style.durationFormatter: a module whose countdown must agree with a
        -- neighboring non-AuraKit display supplies its own rule formatter.
        -- Omitted (every pre-existing style) keeps the shared one.
        local durationOpts = AK.BuildDurationTextOpts(
            look.durationFormatter
                or AK.GetDurationFormatter(look.durationShowSeconds, look.durationPrecisionThreshold),
            look.durationColorCurve,
            look.durationUpdateInterval
        )
        AK.SetDurationTextSafe(btnFrame, state.duration, durationOpts)
        -- Formatter-choice stamp for live rebinds (style.applyExtra reruns on
        -- restyles; duration opts otherwise land only here at creation).
        state.durationFmtS = (look.durationShowSeconds and "s" or "b")
            .. tostring(look.durationPrecisionThreshold or 0)

        -- Creation-time guarantee, stamp-guarded: ApplyStyleToRegions above already
        -- wires the click token on this pass, so this only fires if that call was
        -- denied (secret-value lockdown), leaving the deferred restyle to repair it.
        if look.cancelButtons and state.akCancel ~= look.cancelButtons then
            btnFrame:SetCancelAuraButtons(look.cancelButtons)
            state.akCancel = look.cancelButtons
        end

        GetStyleSet(lookKey)[btnFrame] = true

        if extra then
            extra(btnFrame, state, look)
        end
    end
    -- Holds the button's creation window open for the whole body and always
    -- closes it, also when the body errors (raised again after, so the
    -- engine still reports it).
    return function(btnFrame)
        initButton = btnFrame
        local success, problem = pcall(Init, btnFrame)
        initButton = nil
        if not success then
            error(problem, 0)
        end
    end
end

-- A cell of `styleKey` on a plain frame of the caller's (no engine aura button
-- behind it): the same regions and style pass as an engine button's
-- initializer, registered for restyles, minus the engine registrations (icon,
-- duration, stacks, cancel), which the caller drives itself. For content the
-- engine has no source for (WoW Forever's weapon imbues). Returns frame, d.
function AK.CreateStyledCell(hostFrame, lookKey, extra)
    local look = AK.styles[lookKey] or {}
    local btnFrame = CreateFrame("Frame", nil, hostFrame)
    local state = {}
    bd[btnFrame] = state
    state.styleKey = lookKey
    state.icon = btnFrame:CreateTexture(nil, "ARTWORK")
    state.icon:SetAllPoints(btnFrame)
    state.cooldown = CreateFrame("Cooldown", nil, btnFrame, "CooldownFrameTemplate")
    state.cooldown:SetAllPoints(btnFrame)
    state.borderHost = CreateFrame("Frame", nil, btnFrame)
    state.borderHost:SetAllPoints(btnFrame)
    state.borderHost:SetFrameLevel(state.cooldown:GetFrameLevel() + 1)
    state.borderHost:EnableMouse(false)
    state.buttonFrameLevel = btnFrame:GetFrameLevel()
    state.dispelHolder = CreateFrame("Frame", nil, btnFrame)
    state.dispelHolder:SetAllPoints(btnFrame)
    state.dispelHolder:SetFrameLevel(state.borderHost:GetFrameLevel() + 4)
    state.dispelHolder:EnableMouse(false)
    state.stackCarrier = CreateFrame("Frame", nil, btnFrame)
    state.stackCarrier:SetAllPoints(btnFrame)
    state.stackCarrier:SetFrameLevel(state.borderHost:GetFrameLevel() + 5)
    state.stackCarrier:EnableMouse(false)
    state.stack = state.stackCarrier:CreateFontString(nil, "OVERLAY")
    state.duration = state.stackCarrier:CreateFontString(nil, "OVERLAY")
    ApplyStyleToRegions(btnFrame, look)
    GetStyleSet(lookKey)[btnFrame] = true
    if extra then
        extra(btnFrame, state, look)
    end
    return btnFrame, state
end

-- Re-applies a style to every registered button (settings changed). Geometry
-- owned by the container (element sizes, spacing, growth) is re-driven by the
-- caller through AK.ApplyContainerLayout / group setters, not here.
function AK.Restyle(lookKey)
    local look = AK.styles[lookKey]
    local set = styleButtons[lookKey]
    if not look or not set then
        return
    end
    for btnFrame in pairs(set) do
        ApplyStyleToRegions(btnFrame, look)
    end
end

-- Deferred, time-sliced restyle. Group frame pools are 10x their visible count (engine
-- count-obfuscation batches), so one style flip can cover thousands of registered
-- buttons -- synchronous restyles froze the client on raid-frame settings changes. This
-- queues the key and re-decorates a bounded number of buttons per frame; re-queuing a
-- key already in flight re-processes it with the latest style table (resolved at apply
-- time). The worker frame is hidden whenever the queue is empty.
local RESTYLE_BUDGET = 200 -- buttons per frame

local restyleQueue = {}
local restyleWork
local restyler = CreateFrame("Frame")
restyler:Hide()
restyler:SetScript("OnUpdate", function(self)
    local budget = RESTYLE_BUDGET
    while budget > 0 do
        if not restyleWork then
            local styleId = next(restyleQueue)
            if not styleId then
                self:Hide()
                return
            end
            restyleQueue[styleId] = nil
            local set = styleButtons[styleId]
            if AK.styles[styleId] and set then
                local buttons = {}
                for b in pairs(set) do
                    buttons[#buttons + 1] = b
                end
                restyleWork = { key = styleId, buttons = buttons, index = 1 }
            end
        end
        if restyleWork then
            local wid = restyleWork
            local look = AK.styles[wid.key]
            local num = #wid.buttons
            local restricted = AK.AurasRestricted()
            while budget > 0 and wid.index <= num do
                local btnFrame = wid.buttons[wid.index]
                -- Advance BEFORE applying: an error must never wedge the
                -- queue on one button. (Field incident, 12.1 build 68745:
                -- a denied button call under aura secrecy retried the same
                -- button every frame forever -- a 1298-error storm.)
                wid.index = wid.index + 1
                if look then
                    local success, problem = pcall(ApplyStyleToRegions, btnFrame, look)
                    if not success then
                        if
                            type(problem) == "string"
                            and wid.wd ~= false
                            and string.find(problem, "script ran too long", 1, true)
                        then
                            -- The client watchdog killed the slice, not this button:
                            -- rewind, keep the work item, and resume next frame on a
                            -- fresh execution budget. Capped so a pathological button
                            -- still falls through to the normal error handling below.
                            wid.wd = (wid.wd or 0) + 1
                            if wid.wd > 3 then
                                wid.wd = false
                            end
                            if wid.wd then
                                wid.index = wid.index - 1
                                return
                            end
                        end
                        if restricted then
                            -- Expected under secrecy: button-object writes
                            -- are denied. Re-run the whole key at lift.
                            pendingRestyles[wid.key] = true
                        else
                            geterrorhandler()(problem)
                        end
                    end
                end
                budget = budget - 1
            end
            if wid.index > num then
                restyleWork = nil
            end
        end
    end
end)

function AK.RestyleSoon(lookKey)
    restyleQueue[lookKey] = true
    restyler:Show()
end

------------------------------------------------------------------------------
-- Restriction-lift watcher. Aura secrecy is instance-gated (combat end, encounter end,
-- zoning) plus the /cuidev forced-restriction CVars; on each edge, re-probe and drain
-- the deferred restyles. Fail-open: still restricted just means wait for the next edge.
-- Modules with their own deferred (skipped-without-stamping) work register a callback;
-- callbacks must self-guard with a dirty flag so idle firings cost one boolean test.
------------------------------------------------------------------------------

local liftCallbacks = {}
function AK.OnRestrictionLift(func)
    liftCallbacks[#liftCallbacks + 1] = func
end

local liftWatcher = CreateFrame("Frame")
liftWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
liftWatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
liftWatcher:RegisterEvent("ZONE_CHANGED_NEW_AREA")
liftWatcher:RegisterEvent("ENCOUNTER_END")
liftWatcher:RegisterEvent("CVAR_UPDATE")
liftWatcher:SetScript("OnEvent", function(_, evt, cvarName)
    if evt == "CVAR_UPDATE" and cvarName and not string.find(cvarName, "RestrictionsForced", 1, true) then
        return
    end
    if not next(pendingRestyles) and #liftCallbacks == 0 then
        return
    end
    if AK.AurasRestricted() then
        return
    end
    for styleId in pairs(pendingRestyles) do
        pendingRestyles[styleId] = nil
        restyleQueue[styleId] = true
        restyler:Show()
    end
    for idx = 1, #liftCallbacks do
        liftCallbacks[idx]()
    end
end)

------------------------------------------------------------------------------
-- Container creation
--
-- spec = {
--   layout = { anchorPoint, growthH, growthV, padding = {l, r, t, b}, rowWidth },
--   groups = { { key, filter = {tokens...}, maxFrameCount, sortMethod,
--                sortDirection, candidateFilters, style, extraInit,
--                layout = { elementWidth, elementHeight, elementSpacing,
--                           lineSpacing, groupSpacing, groupLineSpacing,
--                           forceNewLine, layoutIndex } }, ... },  (68914 keys)
--   slots  = { { key, filter = {tokens...}, candidateFilters, sortMethod,
--                sortDirection, style, extraInit }, ... },
--   processAura = { ... } -- optional SetAuraProcessingPolicy options
-- }
--
-- Groups are ADD-ONLY on a container: declare everything up front; a disabled
-- group is maxFrameCount 0, never a removed one.
------------------------------------------------------------------------------

local containerData = setmetatable({}, { __mode = "k" })

-- Container-level layout setters. 68914 replaced the SetAuraLayout* family
-- with SetFlowLayout* (rowWidth generalized to maximumLineSize) and added a
-- flow axis; resolve per call with the old names as fallback so a stale PTR
-- build degrades to the previous behavior instead of erroring. Every module
-- goes through these instead of calling the container methods directly.
function AK.SetContainerAnchor(boxHolder, anchorPoint)
    local f = boxHolder.SetFlowLayoutAnchorPoint or boxHolder.SetAuraLayoutAnchorPoint
    if f then
        f(boxHolder, anchorPoint)
    end
end

function AK.SetContainerGrowth(boxHolder, growthH, growthV)
    local f = boxHolder.SetFlowLayoutGrowthDirection or boxHolder.SetAuraLayoutGrowthDirection
    if f then
        f(boxHolder, growthH, growthV)
    end
end

function AK.SetContainerPadding(boxHolder, l, r, t, b)
    local f = boxHolder.SetFlowLayoutPadding or boxHolder.SetAuraLayoutPadding
    if f then
        f(boxHolder, l, r, t, b)
    end
end

function AK.SetContainerRowWidth(boxHolder, rowWidth)
    -- nil resets to unlimited on both API generations
    local f = boxHolder.SetFlowLayoutMaximumLineSize or boxHolder.SetAuraLayoutRowWidth
    if f then
        f(boxHolder, rowWidth)
    end
end

-- Flow axis (68914+): Horizontal = lines are rows (the classic layout),
-- Vertical = lines are COLUMNS (fill down/up first, wrap sideways at the
-- line size). No-op on builds without the API -- callers degrade to the
-- old single-column vertical behavior there.
function AK.SetContainerAxis(boxHolder, vertical)
    local axes = AnchorUtil and AnchorUtil.FlowLayoutAxis
    local f = boxHolder.SetFlowLayoutAxis
    if not (axes and f) then
        return
    end
    f(boxHolder, vertical and axes.Vertical or axes.Horizontal)
end

function AK.ApplyContainerLayout(boxHolder, layout)
    if not layout then
        return
    end
    if layout.anchorPoint then
        AK.SetContainerAnchor(boxHolder, layout.anchorPoint)
    end
    if layout.growthH and layout.growthV then
        AK.SetContainerGrowth(boxHolder, layout.growthH, layout.growthV)
    end
    if layout.padding then
        local p = layout.padding
        AK.SetContainerPadding(boxHolder, p[1] or 0, p[2] or 0, p[3] or 0, p[4] or 0)
    end
    AK.SetContainerRowWidth(boxHolder, layout.rowWidth)
end

-- Incremental construction: each AddAuraGroup call eagerly creates a
-- 10-button engine batch through the full region initializer (~4-6ms), so
-- monolithic container builds produce frame spikes proportional to their
-- group count. Shell/AddGroup/AddSlot/Finish let builders spread that work
-- across the shared build scheduler below; CreateContainer composes them
-- for synchronous callers (settings-change swaps, small containers).

function AK.CreateContainerShell(hostFrame, specInfo)
    -- Combat creation is legal since 68914 (PTR-7 notes; /cuit3 field PASS
    -- 2026-07-23). The old in-combat zombie soft-fail -- and the OOC assert
    -- that guarded against it -- are gone.
    if not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
        C_AddOns.LoadAddOn("Blizzard_AuraContainer")
    end
    local boxHolder = CreateFrame("AuraContainer", nil, hostFrame, "CustomAuraContainerTemplate")

    -- Anchor and a provisional size up front: the engine drains its parse and
    -- layout phases from an OnUpdate armed in run-when-visible mode, so the
    -- container needs a renderable rect from the very first dirty mark. The
    -- engine replaces the size on every layout pass.
    if specInfo.point then
        boxHolder:SetPoint(unpack(specInfo.point))
    end
    boxHolder:SetSize(1, 1)

    if specInfo.processAura then
        boxHolder:SetAuraProcessingPolicy(
            CustomAuraContainerAuraProcessingPolicy.ProcessAura,
            specInfo.processAura
        )
    end

    AK.ApplyContainerLayout(boxHolder, specInfo.layout)

    containerData[boxHolder] = { spec = specInfo, slotFrames = {} }
    return boxHolder
end

------------------------------------------------------------------------------
-- Animations the button runs itself (12.1.5)
--
-- A group handed to button:AddAuraShownAnimation is played by Blizzard when
-- the button starts showing an aura and stopped whenever it has none
-- (CustomAuraButton ApplyVisibility, also on clear and release), so decoration
-- that animates costs nothing on hidden pooled buttons. The glow engine is the
-- one caller (CludesUI.Glows.BindEngineHost): it registers only the groups
-- the drawn style plays, since Blizzard plays every registered group on each
-- show. Once registered, a group's progress may not be queried (IsPlaying
-- throws); its setters, Play and Stop still work out of restriction. The
-- registrations are stamped in the button's weak bd entry (d.akShown), never
-- on the button.
--
-- While auras are restricted the button subtree refuses every call from our
-- code outside the creation window: such work is skipped and its style key
-- re-runs at the restriction lift (AK.DeferRestyle). Inside the creation
-- window every call is legal.
--
-- Registering does not refresh the button, and its shown state is secret even
-- out of restriction, so a group added or restarted outside the creation
-- window is played at once and the button is then made to re-run its own
-- visibility (the kick): re-registering an element it already holds runs its
-- display update, which stops the group again when the button has no aura and
-- leaves it playing when it shows one. The element is d.akKickIcon: the
-- standard icon, a module's own icon texture (AK.EnsureKickIcon with held), or
-- a hidden texture made for a bare button that registers no icon. Inside the
-- creation window no kick is needed: the engine updates the button right after
-- its initializer returns. Buttons without the API (WoW Forever) keep the
-- AK.ButtonCanShow gate below.
------------------------------------------------------------------------------
local animErrShown = false

-- A refused button call: deferred to the lift while auras are restricted,
-- else a real error, reported once a session. Returns false.
local function AnimCallFailed(state, problem)
    if AK.AurasRestricted() then
        if state and state.styleKey then
            pendingRestyles[state.styleKey] = true
        end
    elseif not animErrShown then
        animErrShown = true
        geterrorhandler()(problem)
    end
    return false
end

-- True while this button's initializeFrame callback runs.
function AK.InCreationWindow(btnFrame)
    return btnFrame ~= nil and btnFrame == initButton
end

-- May our code call into this button's subtree right now: inside its creation
-- window, or while auras are not restricted.
function AK.CanTouchButton(btnFrame)
    return (btnFrame ~= nil and btnFrame == initButton) or not AK.AurasRestricted()
end

-- Re-runs a style key once the aura restriction lifts (for module code that
-- skipped a button call it may not make yet).
function AK.DeferRestyle(lookKey)
    if lookKey then
        pendingRestyles[lookKey] = true
    end
end

-- Can the live button run animations itself (12.1.5+; not on WoW Forever).
function AK.CanRunAnimations(btnFrame)
    return btnFrame ~= nil
        and btnFrame.AddAuraShownAnimation ~= nil
        and btnFrame.RemoveAuraShownAnimation ~= nil
end

-- Registers (on = true) or removes one shown animation. Stamped after success
-- in d.akShown, so a repeat is free and never adds a group twice (the engine
-- asserts on a duplicate). A call the button refuses under restriction defers
-- d.styleKey to the lift (callers that can test first use AK.CanTouchButton).
-- true when the button's registration now matches on.
function AK.SetShownAnimation(btnFrame, state, ag, enabled)
    local region = state.akShown
    if enabled then
        if region and region[ag] then
            return true
        end
    elseif not (region and region[ag]) then
        return true
    end
    if enabled then
        local success, problem = pcall(btnFrame.AddAuraShownAnimation, btnFrame, ag)
        -- "already been added": registered under a lost stamp, which is the state wanted.
        if
            not success and not (type(problem) == "string" and string.find(problem, "already been added", 1, true))
        then
            return AnimCallFailed(state, problem)
        end
        if not region then
            region = {}
            state.akShown = region
        end
        region[ag] = true
        return true
    end
    local success, problem = pcall(btnFrame.RemoveAuraShownAnimation, btnFrame, ag)
    if not success then
        return AnimCallFailed(state, problem)
    end
    region[ag] = nil
    return true
end

-- The kick (see above): plays groups[1..n], then has the button re-run its
-- visibility, which stops them again on a button with no aura. A no-op inside
-- the button's creation window; refused under restriction like the calls
-- above. true when it landed.
function AK.KickShownAnimations(btnFrame, state, groups, num)
    if btnFrame == initButton then
        return true
    end
    for idx = 1, num do
        local ag = groups[idx]
        local success, problem = pcall(ag.Play, ag)
        if not success then
            return AnimCallFailed(state, problem)
        end
    end
    local icon = state.akKickIcon
    -- A bare button without one: making and registering it is the kick.
    if not icon then
        return AK.EnsureKickIcon(btnFrame, state)
    end
    local success, problem = pcall(btnFrame.SetIcon, btnFrame, icon)
    if not success then
        return AnimCallFailed(state, problem)
    end
    return true
end

-- The kick element of a bare button (style.noRegions builds no icon). held: an
-- icon texture the module registered itself with button:SetIcon -- pass it, or
-- the kick would replace that registration with a hidden texture of its own.
-- Without held, a hidden texture is made on the button and registered as its
-- icon (the engine only ever sets its texture), in the creation window or out
-- of restriction. true once the button has a kick element.
function AK.EnsureKickIcon(btnFrame, state, held)
    if held then
        state.akKickIcon = held
        return true
    end
    if state.akKickIcon then
        return true
    end
    -- Made once: a refused step keeps it for the next attempt. It draws nothing
    -- before registration (no texture set), and is hidden before it is handed
    -- over, so the aura's art the engine then sets never shows.
    local texture = state.akKickTex
    if not texture then
        local success
        success, texture = pcall(btnFrame.CreateTexture, btnFrame, nil, "BACKGROUND")
        if not success then
            return AnimCallFailed(state, texture)
        end
        state.akKickTex = texture
    end
    if not state.akKickHidden then
        local success, problem = pcall(texture.Hide, texture)
        if not success then
            return AnimCallFailed(state, problem)
        end
        state.akKickHidden = true
    end
    local success, problem = pcall(btnFrame.SetIcon, btnFrame, texture)
    if not success then
        return AnimCallFailed(state, problem)
    end
    state.akKickIcon = texture
    return true
end

-- Which of a group's buttons can ever show an aura: the fallback for buttons
-- that cannot run animations themselves (AK.CanRunAnimations false), and the
-- gate Nameplates puts on its glow setup on every client (a bound host on a
-- button that never shows would only cost build time and memory). The engine
-- hands a group's buttons out from the top of a stack:
-- AddAuraGroup builds one batch of GROUP_BATCH up front, an acquire pops the
-- last free button and a release pushes it back on top
-- (Blizzard_AuraContainerFrameProviders). While the
-- group's cap fits in that batch, the bottom (batch - cap) buttons are never
-- popped, so only the last <cap> buttons built can show. Decoration that costs
-- while its button is hidden (a playing glow animation) goes on those alone;
-- the rest still build it in the creation window and leave it stopped. The cap
-- is the highest the group ever had: released buttons go back on top in any
-- order, so every button a past cap reached stays in use. Slot and enchant
-- buttons always can show. A "no" marks the group gated: only gated groups
-- are re-dressed when their cap grows.
local GROUP_BATCH = 10

function AK.ButtonCanShow(btnFrame)
    local state = bd[btnFrame]
    local record = state and state.akGroup
    if not record or record.allShow or record.maxCap > GROUP_BATCH or state.akIndex > GROUP_BATCH - record.maxCap then
        return true
    end
    record.gated = true
    return false
end

-- Re-dresses group buttons that just became able to show, so the decoration
-- AK.ButtonCanShow held back starts on them. Under aura secrecy their child
-- writes are denied: the whole style re-runs once the restriction lifts.
local function RedressGroupButtons(record, first, last)
    if not record.gated then
        return
    end
    for idx = first, last do
        local btnFrame = record.buttons[idx]
        local state = btnFrame and bd[btnFrame]
        local look = state and AK.styles[state.styleKey]
        if look and not pcall(ApplyStyleToRegions, btnFrame, look) then
            if AK.AurasRestricted() then
                pendingRestyles[state.styleKey] = true
            else
                AK.RestyleSoon(state.styleKey)
            end
        end
    end
end

function AK.AddGroupToContainer(boxHolder, g)
    local record = { maxCap = g.maxFrameCount or math.huge, buttons = {} }
    boxHolder:AddAuraGroup(g.key, AK.Filter(unpack(g.filter)), {
        maxFrameCount = g.maxFrameCount,
        sortMethod = g.sortMethod,
        sortDirection = g.sortDirection,
        candidateFilters = g.candidateFilters,
        initializeFrame = AK.MakeInitializer(g.style, g.extraInit, record),
        layout = g.layout,
    })
    -- A first batch of another size breaks the stack rule: every button can show.
    -- None built yet counts too: buttons made later may come one at a time.
    local wasBuilt = #record.buttons
    if wasBuilt ~= GROUP_BATCH and record.maxCap < GROUP_BATCH then
        record.allShow = true
        RedressGroupButtons(record, 1, wasBuilt)
    end
    local cooldown = containerData[boxHolder]
    if cooldown then
        cooldown.groups = cooldown.groups or {}
        cooldown.groups[g.key] = record
    end
end

-- A declared group's frame cap. Where the client can (12.1.5+), a cap of 0
-- also switches the group off: a disabled group is neither parsed nor
-- refreshed, and a container whose groups and slots are all off stops
-- watching UNIT_AURA. Before that build a cap of 0 only hides its frames.
-- Every cap write goes through here, so a group switched off always wakes
-- with its next cap. Both setters return at once on an unchanged value, so
-- only a real flip costs anything (the container re-parses, once per frame).
-- A cap above the group's highest yet brings more of its buttons into use
-- (AK.ButtonCanShow): those are re-dressed.
function AK.SetGroupCap(boxHolder, styleId, cap)
    if boxHolder.SetAuraGroupEnabled then
        if cap > 0 then
            boxHolder:SetAuraGroupEnabled(styleId, true)
        end
        boxHolder:SetAuraGroupMaxFrameCount(styleId, cap)
        if cap <= 0 then
            boxHolder:SetAuraGroupEnabled(styleId, false)
        end
    else
        boxHolder:SetAuraGroupMaxFrameCount(styleId, cap)
    end
    local cooldown = containerData[boxHolder]
    local record = cooldown and cooldown.groups and cooldown.groups[styleId]
    if not record or record.allShow or cap <= record.maxCap then
        return
    end
    local old = record.maxCap
    record.maxCap = cap
    if old >= GROUP_BATCH then
        return
    end
    RedressGroupButtons(record, GROUP_BATCH - math.min(cap, GROUP_BATCH) + 1, GROUP_BATCH - old)
end

function AK.AddSlotToContainer(boxHolder, s)
    local f = boxHolder:AddAuraSlot(s.key, AK.Filter(unpack(s.filter)), {
        candidateFilters = s.candidateFilters,
        sortMethod = s.sortMethod,
        sortDirection = s.sortDirection,
        initializeFrame = AK.MakeInitializer(s.style, s.extraInit),
    })
    local cooldown = containerData[boxHolder]
    if cooldown then
        cooldown.slotFrames[s.key] = f
    end
    return f
end

------------------------------------------------------------------------------
-- Item enchantments (temporary weapon enchants: oils, imbues, stones)
--
-- Not auras (an enchantID, no spell ID) but engine display sources since
-- 12.1: the container builds the frame through the SAME initializer as an
-- aura group, resolves the icon off the inventory slot, shows the item
-- tooltip, and runs the protected CancelTemporaryEnchantment on a cancel
-- click (style.cancelButtons feeds SetCancelAuraButtons, as for auras).
AK.ITEM_ENCH_SLOTS = { "MainHand", "OffHand", "Ranged" }

-- Blizzard Style (style.blizzEnchant, set by the consumers' style builders):
-- the stock purple temp-enchant ring round a weapon-enchant cell, the one
-- piece of aura border art the engine does not stamp itself (its Border
-- style is harmful-only). 32px round a 30px icon in the stock buff frame,
-- so a thirtieth of the cell on each side; anchored to the border host
-- (button rects are restricted). Hidden, never destroyed, without the flag.
function AK.ApplyBlizzEnchantRing(btnFrame, state, look)
    local ringTex = state.blizzEnchantRing
    if not look.blizzEnchant then
        if ringTex then
            ringTex:Hide()
        end
        return
    end
    local host = state.borderHost or btnFrame
    if not ringTex then
        ringTex = host:CreateTexture(nil, "OVERLAY")
        ringTex:SetTexture("Interface\\Buttons\\UI-TempEnchant-Border")
        if ringTex.SetSnapToPixelGrid then
            ringTex:SetSnapToPixelGrid(false)
            ringTex:SetTexelSnappingBias(0)
        end
        state.blizzEnchantRing = ringTex
    end
    local wid = look.width or 32
    local hgt = look.height or wid
    local styleId = wid .. "|" .. hgt
    if state.blizzEnchantGeom ~= styleId then
        local ex, ey = wid / 30, hgt / 30
        ringTex:ClearAllPoints()
        ringTex:SetPoint("TOPLEFT", host, "TOPLEFT", -ex, ey)
        ringTex:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", ex, -ey)
        state.blizzEnchantGeom = styleId
    end
    ringTex:Show()
end

-- extraInit for AddItemEnchantmentsToContainer: marks the cell so the style
-- pass (ApplyStyleToRegions, at init and on every restyle) can tell it from
-- an aura button, and fits the ring once now (the pass ran before this hook).
function AK.EnchantCellInit(btnFrame, state, look)
    state.enchantCell = true
    AK.ApplyBlizzEnchantRing(btnFrame, state, look)
end

-- Blizzard Style (style.blizzRoundArt, set by the nameplate style builder):
-- the stock nameplate aura item look -- the full icon art under the rounded
-- Cooldown Manager mask, the ring overlay hung round the cell (6px by 5px
-- past a 25px item, so the overhang scales with the cell) and the rounded
-- stock swipe. The mask goes on the engine's icon region, so it rides the
-- same restriction guard as the shape mask; the ring sits on the border
-- host (button rects are restricted). Hidden, never destroyed, without the
-- flag. Yields to an icon shape, which owns the mask and swipe itself. The
-- ring is the retail art on WoW Forever too (CludesUI.StockAtlas) unless
-- style.blizzRoundNative (that client's own look) is set.
AK.BLIZZ_ROUND_MASK = "UI-HUD-CoolDownManager-Mask"
AK.BLIZZ_ROUND_RING = "UI-HUD-CoolDownManager-IconOverlay"
AK.BLIZZ_ROUND_SWIPE = "Interface\\HUD\\UI-HUD-CoolDownManager-Icon-Swipe"
function AK.ApplyBlizzRoundArt(btnFrame, state, look, shaped)
    local ringTex = state.blizzRoundRing
    local wanted = look.blizzRoundArt and not shaped
    if wanted and AK._blizzRoundOK == nil then
        AK._blizzRoundOK = (
            C_Texture
            and C_Texture.GetAtlasInfo
            and C_Texture.GetAtlasInfo(AK.BLIZZ_ROUND_MASK)
            and C_Texture.GetAtlasInfo(AK.BLIZZ_ROUND_RING)
        )
                and true
            or false
    end
    if not (wanted and AK._blizzRoundOK) then
        if ringTex then
            ringTex:Hide()
        end
        if state.akBlizzRoundMasked then
            if state.icon and state.blizzRoundMask then
                pcall(state.icon.RemoveMaskTexture, state.icon, state.blizzRoundMask)
            end
            if state.cooldown and state.cooldown.SetSwipeTexture then
                pcall(state.cooldown.SetSwipeTexture, state.cooldown, "")
            end
            state.akBlizzRoundMasked = nil
        end
        return
    end
    local host = state.borderHost or btnFrame
    if not ringTex then
        ringTex = host:CreateTexture(nil, "OVERLAY")
        if look.blizzRoundNative then
            ringTex:SetAtlas(AK.BLIZZ_ROUND_RING)
        else
            CludesUI.StockAtlas(ringTex, AK.BLIZZ_ROUND_RING)
        end
        if ringTex.SetSnapToPixelGrid then
            ringTex:SetSnapToPixelGrid(false)
            ringTex:SetTexelSnappingBias(0)
        end
        state.blizzRoundRing = ringTex
    end
    if not state.blizzRoundMask then
        local mask = btnFrame:CreateMaskTexture()
        mask:SetAtlas(AK.BLIZZ_ROUND_MASK)
        mask:SetAllPoints(btnFrame)
        state.blizzRoundMask = mask
    end
    if not state.akBlizzRoundMasked and state.icon then
        if pcall(state.icon.AddMaskTexture, state.icon, state.blizzRoundMask) then
            state.akBlizzRoundMasked = true
            if state.cooldown and state.cooldown.SetSwipeTexture then
                pcall(state.cooldown.SetSwipeTexture, state.cooldown, AK.BLIZZ_ROUND_SWIPE)
            end
        elseif state.styleKey and AK.AurasRestricted() then
            pendingRestyles[state.styleKey] = true
        end
    end
    local wid = look.width or 32
    local hgt = look.height or wid
    if state.blizzRoundW ~= wid or state.blizzRoundH ~= hgt then
        local ex, ey = wid * 0.24, hgt * 0.2
        ringTex:ClearAllPoints()
        ringTex:SetPoint("TOPLEFT", host, "TOPLEFT", -ex, ey)
        ringTex:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", ex, -ey)
        state.blizzRoundW, state.blizzRoundH = wid, hgt
    end
    ringTex:Show()
end

-- Their position is LAYOUT data: they are a flow group of their own, and
-- `placement`/`layoutIndex` decides whether they lead or trail the aura
-- groups. Nothing may be anchored to a container (forbidden aspects).
function AK.SetContainerItemEnchantmentLayout(boxHolder, layout)
    if not (boxHolder and layout and boxHolder.SetItemEnchantmentLayout) then
        return
    end
    boxHolder:SetItemEnchantmentLayout(layout)
end

-- BOTH halves required: the inbound setter validates before it defaults, so a
-- method without a direction is a hard error engine-side.
function AK.SetContainerItemEnchantmentSort(boxHolder, sortMethod, sortDirection)
    if not (boxHolder and sortMethod and sortDirection and boxHolder.SetItemEnchantmentSortMethod) then
        return
    end
    boxHolder:SetItemEnchantmentSortMethod(sortMethod, sortDirection)
end

-- e = { style, extraInit, hidePermanent (default true: duration-bearing
-- only), maxSlots (declare only the first N of ITEM_ENCH_SLOTS, for a
-- display too small to hold all three), layout, sortMethod, sortDirection }.
-- ONE-WAY: with no addon-facing unregister, a consumer that must stop
-- showing them releases the container and builds a fresh one. Re-calling is
-- idempotent and re-applies layout and sort only.
function AK.AddItemEnchantmentsToContainer(boxHolder, e)
    if not (boxHolder and e and boxHolder.AddItemEnchantment) then
        return
    end
    local slotEnum = AuraContainerItemEnchantmentSlot
    if not slotEnum then
        return
    end
    local cooldown = containerData[boxHolder]
    if cooldown and not cooldown.itemEnchFrames then
        cooldown.itemEnchFrames = {}
    end
    local tracked = cooldown and cooldown.itemEnchFrames
    local nameList = AK.ITEM_ENCH_SLOTS
    local last = math.min(e.maxSlots or #nameList, #nameList)
    for idx = 1, last do
        local name = nameList[idx]
        local slot = slotEnum[name]
        -- HasItemEnchantment is engine-private and a second declaration for
        -- the same slot asserts, so the declared set is ours to keep. pcall'd
        -- anyway: ReleaseContainer drops the whole containerData entry, so a
        -- container that is released and then re-declared (no consumer does
        -- that today) would hit that assert with the tracking gone.
        if slot ~= nil and not (tracked and tracked[name]) then
            local success, widget = pcall(boxHolder.AddItemEnchantment, boxHolder, slot, {
                initializeFrame = AK.MakeInitializer(e.style, e.extraInit),
                hidePermanent = e.hidePermanent ~= false,
            })
            if success and tracked then
                tracked[name] = widget or true
            end
        end
    end
    AK.SetContainerItemEnchantmentLayout(boxHolder, e.layout)
    AK.SetContainerItemEnchantmentSort(boxHolder, e.sortMethod, e.sortDirection)
end

-- Binds the unit, then requests a full refresh. Builders call it once their
-- content is declared, but the order is free: every group or slot
-- declaration, every unit change and the container's own show re-run the
-- engine's event registration (12.1 and WoW Forever), which holds UNIT_AURA
-- only while the container has content and is visible. Unit Frames binds
-- every element at build and declares an element's groups only once it is on.
function AK.FinishContainer(boxHolder, unitToken)
    boxHolder:SetUnit(unitToken)
    boxHolder:UpdateAllAuras()
end

function AK.CreateContainer(hostFrame, unitToken, specInfo)
    local boxHolder = AK.CreateContainerShell(hostFrame, specInfo)

    if specInfo.groups then
        for idx = 1, #specInfo.groups do
            AK.AddGroupToContainer(boxHolder, specInfo.groups[idx])
        end
    end

    if specInfo.slots then
        for idx = 1, #specInfo.slots do
            AK.AddSlotToContainer(boxHolder, specInfo.slots[idx])
        end
    end

    AK.FinishContainer(boxHolder, unitToken)

    return boxHolder, containerData[boxHolder].slotFrames
end

------------------------------------------------------------------------------
-- Shared build scheduler
--
-- Time-budgeted queues for ALL deferred container construction (RF buttons, NP
-- bundle pool, UF units). Each module builds through its own worker frame
-- (AK.NewBuildWorker, called from the module's main chunk): the engine bills a
-- container's aura processing, and the buttons it builds, to the addon whose code
-- created the frame the build ran from, so a module's aura work shows on that
-- module's row instead of the parent's. Every worker runs its own jobs in FIFO order
-- and all of them draw on ONE per-frame budget, so the modules' builders can never
-- stack their work into the same frame. OnUpdate never ticks during a loading screen,
-- so queued work always lands in rendered gameplay frames; combat clamps the budget
-- (client combat watchdog), never the work. Explicit head/tail indices: consumed
-- slots are nil'd and the length operator is undefined on arrays with holes.
------------------------------------------------------------------------------

local BUILD_BUDGET_MS = 8
-- Login/reload window: module setup runs from timer-deferred OnEnable chains that
-- fire only AFTER the loading screen drops, so their build jobs cannot be caught by
-- the behind-the-screen burst -- they drain through the worker on low,
-- streaming-world fps. At the mid-session 8ms budget that read as seconds of missing
-- auras. Outside raids, the window runs a near-burst budget instead: the whole
-- post-login queue lands in a handful of frames during the world fade-in (the
-- user-stated contract: "spread over a few frames on reload/login"), and the gentle
-- budget resumes for everything mid-session.
local BUILD_BUDGET_LOGIN_MS = 250
local LOGIN_WINDOW_S = 15
local loginStamp = -LOGIN_WINDOW_S
-- ONE budget, every job combat-runnable: 68914 made container creation
-- legal in combat (/cuit3 field PASS), which retired the whole
-- hold-lane/oocOnly regime -- jobs run in FIFO order whenever their worker
-- ticks, and the only pacing is the per-frame budget (combat-clamped).
local workers = {}
-- Budget spent this frame across every worker (GetTime() names the frame).
local spentStamp, spentMs = nil, 0

-- Job verdicts: nil = done; "again" = the job is a multi-atom stepper with
-- more bounded work left (front-requeued so it finishes before newer work,
-- with a budget check between atoms); "watchdog" = synthesized here, never
-- returned by jobs. The pcall exists for the client watchdog ("script ran too long"):
-- login contention can balloon one job's engine batches past the
-- per-execution limit, which previously aborted the whole tick AND lost the
-- dequeued job mid-flight (half-built unit). Jobs are written resumable
-- (existence-guarded stages), so a watchdog-killed job front-requeues and the
-- tick ends -- it resumes with a fresh execution budget next frame. Real
-- errors surface once and drop the job; the rest of the tick keeps draining.
local WATCHDOG_RETRIES = 3
local function RunJob(record)
    local success, verdict = pcall(record.fn)
    if success then
        return verdict
    end
    if type(verdict) == "string" and string.find(verdict, "script ran too long", 1, true) then
        record.watchdogged = (record.watchdogged or 0) + 1
        if record.watchdogged <= WATCHDOG_RETRIES then
            return "watchdog"
        end
    end
    geterrorhandler()(verdict)
end

local function WorkerOnUpdate(self)
    local inCombat = InCombatLockdown()
    -- The turbo budget is OOC and non-raid only: raid-instance login can use the lower
    -- script watchdog before combat lockdown reflects the new world, so a 250ms drain
    -- can abort this outer loop beyond the per-job pcall. Restricted frames drain at
    -- the gentle budget; the regen wake re-arms the turbo for safe worlds.
    local budget = BUILD_BUDGET_MS
    if not inCombat and select(2, IsInInstance()) ~= "raid" and GetTime() - loginStamp < LOGIN_WINDOW_S then
        budget = BUILD_BUDGET_LOGIN_MS
    end
    local nowTime = GetTime()
    if spentStamp ~= nowTime then
        spentStamp, spentMs = nowTime, 0
    end
    if spentMs >= budget then
        return
    end
    local t0 = debugprofilestop()

    local queue = self._akQueue
    while self._akHead <= self._akTail do
        local head = self._akHead
        local record = queue[head]
        queue[head] = nil
        self._akHead = head + 1
        if record then
            local verdict = RunJob(record)
            if verdict == "again" or verdict == "watchdog" then
                self._akHead = head
                queue[head] = record
                if verdict == "watchdog" then
                    spentMs = spentMs + debugprofilestop() - t0
                    return
                end
            end
        end
        if spentMs + debugprofilestop() - t0 >= budget then
            spentMs = spentMs + debugprofilestop() - t0
            return
        end
    end
    spentMs = spentMs + debugprofilestop() - t0
    self._akQueue, self._akHead, self._akTail = {}, 1, 0
    self:Hide()
end

local function QueueOnWorker(job, func, labelText)
    local tail = job._akTail + 1
    job._akTail = tail
    job._akQueue[tail] = { fn = func, label = labelText }
    job:Show()
end

-- A module's build worker. Call it from the module's MAIN CHUNK: the frame has
-- to be created in the module's own load context for its builds to bill the
-- module. worker:Queue(fn, label) queues a job on it.
function AK.NewBuildWorker()
    local job = CreateFrame("Frame")
    job:Hide()
    job._akQueue, job._akHead, job._akTail = {}, 1, 0
    job.Queue = QueueOnWorker
    job:SetScript("OnUpdate", WorkerOnUpdate)
    workers[#workers + 1] = job
    return job
end

-- The parent's own worker, for callers that bring none.
local buildWorker = AK.NewBuildWorker()

-- Shows every worker holding jobs; true when any did.
local function WakeWorkers()
    local any = false
    for idx = 1, #workers do
        local job = workers[idx]
        if job._akHead <= job._akTail then
            any = true
            job:Show()
        end
    end
    return any
end

function AK.QueueBuildJob(func, labelText, job)
    QueueOnWorker(job or buildWorker, func, labelText)
end

-- Back-compat name: a combat-runnable job (declarations/setters on
-- EXISTING containers). Back-compat alias; identical to QueueBuildJob.
function AK.QueueLiveBuildJob(func, labelText, job)
    QueueOnWorker(job or buildWorker, func, labelText)
end

-- NO synchronous loading-screen burst: a long drain inside the PEW handler stacks onto
-- every other addon's login work in ONE script execution and trips the client watchdog
-- ("script ran too long") -- field-hit at 1500ms. It also cannot reach the RF/UF jobs,
-- which are enqueued by timer-deferred module setup AFTER the screen drops. PEW only
-- opens the workers' login window: outside raids the whole demand-architecture queue
-- drains in a handful of 250ms frames during the world fade-in; raids retain the safe
-- 8ms budget. Regen wake: a backlog that accrued under the gentle budget snaps in at
-- the turbo budget instead of trickling when the current world allows it.
local wakeFrame = CreateFrame("Frame")
wakeFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
wakeFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
wakeFrame:SetScript("OnEvent", function(_, evt)
    if evt == "PLAYER_REGEN_ENABLED" then
        if WakeWorkers() then
            loginStamp = GetTime()
        end
        return
    end
    -- A reconnect mid-pull lands here before InCombatLockdown reflects the fight;
    -- the turbo drain would run straight into the lower in-combat watchdog, so the
    -- window opens only out of combat (the regen wake snaps the backlog in at turbo
    -- once the pull ends).
    local fighting = UnitAffectingCombat("player")
    if issecretvalue and issecretvalue(fighting) then
        fighting = false
    end
    if not fighting then
        loginStamp = GetTime()
    end
    WakeWorkers() -- in case jobs were queued behind the screen
end)

-- Synchronous create-and-callback, in ANY combat state. Container creation
-- has been combat-legal since 68914 (see CreateContainerShell; RF/NP build
-- in combat through the queue above); the pre-68914 "queue until
-- PLAYER_REGEN_ENABLED" gate this wrapper used to carry left Player Aura Bars
-- (and the Movement Alert) blank until combat ended after an in-combat reload.
-- Kept as a wrapper so callers keep one entry point.
function AK.RequestContainer(hostFrame, unitToken, specInfo, callback)
    local boxHolder, slotFrames = AK.CreateContainer(hostFrame, unitToken, specInfo)
    if callback then
        callback(boxHolder, slotFrames)
    end
end

-- Releases a swapped-out container's tracked slot buttons from the restyle registry.
-- Abandoned containers can never be destroyed (frames are permanent), so without this
-- every swap leaves zombie buttons that all future Restyle passes keep re-decorating --
-- restyle cost grows with every swap. Group buttons are engine-created without a handle
-- list and are not individually tracked; group-based containers swap rarely
-- (filter-class changes), so their zombies are accepted for now.
function AK.ReleaseContainer(boxHolder)
    if not boxHolder then
        return
    end
    local payload = containerData[boxHolder]
    local function Untrack(btnFrame)
        local state = type(btnFrame) == "table" and bd[btnFrame]
        if state then
            if state.styleKey and styleButtons[state.styleKey] then
                styleButtons[state.styleKey][btnFrame] = nil
            end
            bd[btnFrame] = nil
        end
    end
    if payload and payload.slotFrames then
        for _, slotButton in pairs(payload.slotFrames) do
            Untrack(slotButton)
        end
    end
    -- Item enchantment frames come back as handles on declaration, so unlike
    -- group buttons they can be untracked instead of left as restyle zombies.
    if payload and payload.itemEnchFrames then
        for _, enchButton in pairs(payload.itemEnchFrames) do
            Untrack(enchButton)
        end
    end
    containerData[boxHolder] = nil
    boxHolder:Hide()
    -- Release its buttons now: a hidden container runs no aura pass, so they
    -- would keep the auras they show, and the animations they play themselves
    -- (bound glows) would run for the rest of the session. Switching a slot
    -- or group off clears its buttons at once; after the hide, so the switches
    -- register no events. pcall: a key the build never finished is no error.
    if payload and payload.slotFrames and boxHolder.SetAuraSlotEnabled then
        for styleId in pairs(payload.slotFrames) do
            pcall(boxHolder.SetAuraSlotEnabled, boxHolder, styleId, false)
        end
    end
    if payload and payload.groups then
        for styleId in pairs(payload.groups) do
            pcall(AK.SetGroupCap, boxHolder, styleId, 0)
        end
    end
end

------------------------------------------------------------------------------
-- Restriction probe
--
-- Prefer Blizzard's official secrecy query; retain the aura-data probe as a fallback
-- for builds where that API is unavailable. Never treat either as a data source.
--
-- Cached per frame time: while restricted, the probe THROWS (and catches) a
-- real Lua error, and error construction is the expensive part -- callers
-- (ABR reminder evaluators, QoL sweeps) hit this several times per pass.
-- Restriction is instance-gated state that cannot flip mid-frame; the RF
-- containers' own copy of this probe has always relied on the same fact.
------------------------------------------------------------------------------

-- ASYMMETRIC cache: only the RESTRICTED answer is cached (that is the one whose probe
-- throws -- error construction is the cost being amortized). The clear answer is
-- re-probed on every call, because a stale "false" sends callers into hard-erroring
-- scans when restriction engages within the frame window (field-hit: /cuidev flips and
-- zone edges); the success probe is a cheap C call, so not caching it costs nothing. A
-- stale "true" merely suppresses a display for one frame -- safe.
local restrictedStamp = -1
function AK.AurasRestricted()
    local nowTime = GetTime()
    if C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() then
        restrictedStamp = nowTime
        return true
    end
    if nowTime == restrictedStamp then
        return true
    end
    if pcall(C_UnitAuras.GetAuraDataByIndex, "player", 1, "HELPFUL") then
        return false
    end
    restrictedStamp = nowTime
    return true
end

------------------------------------------------------------------------------
-- Offensive dispel capability: can the PLAYER remove Magic buffs or enrages
-- from an enemy (purge, spellsteal, soothe, tranquilizing shot). This asks
-- what the player knows, never what an aura is, so it keeps working in
-- restricted content. Shared by the nameplate and unit frame purge glows.
-- Lazy: the watcher frame exists only once a consumer asks or subscribes.
------------------------------------------------------------------------------
do
    -- { spellID, category ("Magic", "Enrage", or "Both"), requiredClass or nil, requiredTalent or nil }
    local SPELLS = {
        { 370, "Magic", nil }, -- Purge (Shaman)
        { 378773, "Magic", nil }, -- Greater Purge (Shaman)
        { 528, "Magic", nil }, -- Dispel Magic (Priest)
        { 32375, "Magic", nil }, -- Mass Dispel (Priest)
        { 278326, "Magic", nil }, -- Consume Magic (Demon Hunter)
        { 19505, "Magic", "WARLOCK" }, -- Devour Magic (Felhunter)
        { 19801, "Both", nil }, -- Tranquilizing Shot (Hunter)
        { 2908, "Enrage", nil }, -- Soothe (Druid)
        { 30449, "Magic", nil }, -- Spellsteal (Mage)
        { 115078, "Enrage", "MONK", 450432 }, -- Paralysis (w/ Pressure Points talent)
    }
    local magic, enrage, wasBuilt, watcher = false, false, false, nil
    local listeners = {}

    -- IsSpellKnown answers "does the player have this", which is the question a
    -- PASSIVE talent needs -- IsSpellInSpellBook says no for one. The globals
    -- IsPlayerSpell / IsSpellKnown exist only in Blizzard_DeprecatedSpellBook,
    -- behind the loadDeprecationFallbacks CVar, so they are never used here.
    local function Knows(spellId, bank)
        local BANK = Enum and Enum.SpellBookSpellBank
        if not (C_SpellBook and C_SpellBook.IsSpellKnown and BANK) then
            return false
        end
        local success, val = pcall(C_SpellBook.IsSpellKnown, spellId, bank or BANK.Player)
        return success and val == true
    end
    local function InBook(spellId, bank)
        local BANK = Enum and Enum.SpellBookSpellBank
        if not (C_SpellBook and BANK) then
            return false
        end
        if not C_SpellBook.IsSpellKnownOrInSpellBook then
            return Knows(spellId, bank)
        end
        local success, val = pcall(C_SpellBook.IsSpellKnownOrInSpellBook, spellId, bank or BANK.Player)
        return success and val == true
    end

    local function Rebuild()
        local wasMagic, wasEnrage = magic, enrage
        magic, enrage = false, false
        local _, playerClass = UnitClass("player")
        local BANK = Enum and Enum.SpellBookSpellBank
        for idx = 1, #SPELLS do
            local e = SPELLS[idx]
            local spellId, category, reqClass, reqTalent = e[1], e[2], e[3], e[4]
            if not (reqClass and playerClass ~= reqClass) then
                local known
                if reqTalent then
                    known = Knows(reqTalent)
                elseif reqClass then
                    -- Pet bank: true only while that pet is actually out, which
                    -- is why UNIT_PET is registered below.
                    known = InBook(spellId, BANK and BANK.Pet)
                else
                    known = InBook(spellId)
                end
                if known then
                    if category == "Magic" or category == "Both" then
                        magic = true
                    end
                    if category == "Enrage" or category == "Both" then
                        enrage = true
                    end
                end
            end
        end
        -- The first pass has nothing to compare against, so it never notifies:
        -- consumers read the capability when they build.
        if wasBuilt and (wasMagic ~= magic or wasEnrage ~= enrage) then
            for idx = 1, #listeners do
                listeners[idx]()
            end
        end
        wasBuilt = true
    end

    local function Ensure()
        if watcher then
            return
        end
        watcher = CreateFrame("Frame")
        watcher:RegisterEvent("SPELLS_CHANGED")
        watcher:RegisterEvent("UNIT_PET")
        -- A talent swap does not reliably reach SPELLS_CHANGED first, and without
        -- these a talent-gated entry is only correct after a /reload.
        watcher:RegisterEvent("TRAIT_CONFIG_UPDATED")
        watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
        watcher:SetScript("OnEvent", function(_, evt, unit)
            if evt == "UNIT_PET" and unit ~= "player" then
                return
            end
            Rebuild()
        end)
        Rebuild()
    end

    -- canDispelMagic, canDispelEnrage.
    function AK.OffensiveDispelTypes()
        Ensure()
        return magic, enrage
    end

    -- fn() runs whenever either answer flips (talents, spec, pet).
    function AK.OnOffensiveDispelChange(func)
        Ensure()
        listeners[#listeners + 1] = func
    end
end
