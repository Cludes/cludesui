if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-- CUI_ResourceBars_ArcaneSoul.lua
-- 12.1 ONLY: engine-slot driver for the Sunfury Arcane Mage "Arcane Soul" callout.
--
-- Arcane Soul (451038) is a fixed 4s buff granted the instant Arcane Surge
-- (buff 365362) ends -- but Surge's own length is NOT fixed: Savor the Moment adds
-- 0.8s per Spellfire Sphere held at cast time, and that sphere count is a
-- secret value the moment you pull. Predicting the window from the CAST (what
-- the reference helper addons do) is therefore wrong by up to 2.4s.
--
-- So this tracks the LIVE Arcane Surge buff, whose remaining duration already
-- carries the sphere bonus -- and never reads it. Two hidden one-slot aura
-- containers on the player (includeSpellIDs -- helpful-on-self passes the
-- identity gate regardless of secrecy) whose slot subtrees ARE the display:
-- the button shows only while its aura is up, and a bound FontString renders
-- the countdown through a NumericRuleFormatter evaluated C-side. Exact in
-- restricted content, and zero Lua per frame -- no OnUpdate, no polling, no
-- duration ever crossing into Lua.
--
-- Two containers rather than one two-slot container: AddAuraSlot has no
-- per-slot layout override, so a shared container would lay the slots out
-- side by side. The buffs can never overlap, so both slot buttons simply
-- SetAllPoints the one movable proxy (the EbonMight121-proven shape) and only
-- ever one of them is visible.
--
-- Everything the display does beyond "show remaining" is a formatter
-- breakpoint, because the subtree is denied to addon code after creation:
-- the "hide until the last N seconds" rule is an empty format above the
-- threshold, the GCD counter is a components div by the GCD length, and the
-- final-Barrage "LAST" is a literal band below one GCD. Colors ride a Step
-- ColorCurve on the same registration, which doubles as the belt-and-braces
-- hide (alpha 0 above the threshold) if the empty format is ever rejected.

local _, mod = ...
local CludesUI = _G.CludesUI
-- Born in this module's main chunk, so the aura containers it builds bill this
-- module (AuraKit's shared build scheduler).
local AKWorker = CludesUI.AuraKit.NewBuildWorker()

-- Arcane Surge splits cast id from aura id, exactly like Ebon Might (395152 ->
-- 395296, which CUI_ResourceBars_EbonMight121 tracks by the AURA id). The suite
-- already records the pair in CludesUI_BuffPresets: [365350] = { class =
-- "MAGE", alts = { 365362 } }. UNIT_SPELLCAST_SUCCEEDED reports the CAST id;
-- the buff that lands on the player is the ALT. Both go in the slot's candidate
-- set the way BmIncludeMap folds a preset's alts into one slot -- an id that
-- never appears as a player buff simply never matches.
local SURGE_CAST_ID = 365350 -- Arcane Surge, the castable ability
local SURGE_AURA_ID = 365362 -- Arcane Surge, the buff it applies
local SOUL_AURA_ID = 451038 -- Arcane Soul (fixed 4s, granted when Surge ends)
local ARCANE_SPEC_ID = 62
local SUNFURY_TREE_ID = 39 -- C_ClassTalents.GetActiveHeroTalentSpec()
local GCD_SPELL_ID = CludesUI.GCD_SPELL
local STYLE_KEY = "erb:arcsoul121"
local UNLOCK_KEY = "CUI_ArcaneSoul"
-- WoW Forever has no Arcane spec or Sunfury: the helper stays off there.
local FOREVER = CludesUI.IS_FOREVER == true

local DEFAULT_POS = { point = "CENTER", relPoint = "CENTER", x = 0, y = -150 }

-- proxy, built, queued, gcdLen, dirty, fsErr, ev/evCast, sample/sampleHost,
-- class; ph[phase] = { container, btn, fs, stamp }; options live preview:
-- demo (driver), demoOwner/demoPending (page watcher), demoApplied/demoCombat/
-- demoEv (SyncDemo)
local SoulState = { ph = { surge = {}, soul = {} } }
SoulState.class = select(2, UnitClass("player"))

-------------------------------------------------------------------------------
--  Settings access
-------------------------------------------------------------------------------

local function P()
    local ERB = mod.ERB
    local saved = ERB and ERB.db
    local profile = saved and saved.profile
    return profile and profile.arcaneSoul or nil
end

-- countMode is one stored key so the options page keeps one dropdown, but the
-- two phases resolve their display independently:
--   "seconds"    -> tenths of a second in both phases
--   "gcd"        -> whole GCDs in both (Barrage count + LAST inside Soul)
--   "secondsGcd" -> tenths counting down to the window, Barrage count inside it
-- Counting GCDs before the window opens and counting Barrages inside it are
-- different questions, so they are separately answerable.
local function PhaseMode(phaseNum)
    local profile = P()
    local m = profile and profile.countMode
    if m == "gcd" then
        return "gcd"
    end
    if m == "secondsGcd" then
        return (phaseNum == "soul") and "gcd" or "seconds"
    end
    return "seconds"
end

-- Does any phase need a GCD length? Drives the one combat event this module
-- registers, so a pure-seconds setup stays event-free in combat.
local function NeedsGcd()
    local profile = P()
    local m = profile and profile.countMode
    return m == "gcd" or m == "secondsGcd"
end

-- Seconds of Arcane Surge left at which "Soul in" starts showing. Floor 1,
-- never 0: a 0 threshold would collide with the tenths breakpoint at 0.
local function Thr()
    local profile = P()
    local val = tonumber(profile and profile.threshold) or 5
    if val < 1 then
        val = 1
    elseif val > 15 then
        val = 15
    end
    return math.floor(val + 0.5)
end

local function TextSize()
    local profile = P()
    local val = tonumber(profile and profile.textSize) or 24
    if val < 10 then
        val = 10
    elseif val > 48 then
        val = 48
    end
    return math.floor(val + 0.5)
end

local function ProxySize()
    local sz = TextSize()
    return math.max(80, sz * 6), math.max(20, math.floor(sz * 1.6))
end

local function PreColor()
    local p = P() or {}
    return p.preR or 0.64, p.preG or 0.21, p.preB or 0.93
end

local function SoulColor()
    local p = P() or {}
    return p.soulR or 0.64, p.soulG or 0.21, p.soulB or 0.93
end

local function LastColor()
    local p = P() or {}
    return p.lastR or 1.0, p.lastG or 0.25, p.lastB or 0.25
end

-------------------------------------------------------------------------------
--  Fonts -- the Battle Res text pattern: "__global" follows the CUI Fonts &
--  Colors defaults, a named key resolves through the shared font registry, and
--  outline overrides stay slug-gated. Key is "resourceBars" (this module's own
--  entry in _addonKeyToFolder), so a per-module font override applies here too.
-------------------------------------------------------------------------------

local function GetASFont()
    local profile = P()
    local cacheKey = (profile and profile.font) or "__global"
    if cacheKey ~= "__global" and CludesUI and CludesUI.ResolveFontName then
        local filePath = CludesUI.ResolveFontName(cacheKey)
        if filePath then
            return filePath
        end
    end
    return (CludesUI.GetFontPath("resourceBars")) or STANDARD_TEXT_FONT
end

local function GetASOutline()
    local profile = P()
    local modeName = (profile and profile.outlineMode) or "__global"
    if modeName == "outline" then
        return (CludesUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG"
    end
    if modeName == "thick" then
        return (CludesUI.SlugFlag("THICKOUTLINE, SLUG")) or "THICKOUTLINE, SLUG"
    end
    if modeName == "none" then
        return ""
    end
    return (CludesUI.GetFontOutlineFlag("resourceBars"))
        or (CludesUI.SlugFlag("OUTLINE, SLUG"))
        or "OUTLINE, SLUG"
end

-- Empty flags = Drop Shadow mode, primed via FontObject (instance shadow
-- setters do not render). The primed object resolves BLACK, so the instance
-- color is always re-stated afterwards -- it is also the fallback tint if the
-- engine ever refuses the color curve.
local function ApplyFsLook(phaseNum, fontStr)
    if not fontStr then
        return
    end
    local flags = GetASOutline()
    CludesUI.PrimeFontShadow(fontStr, flags == "")
    fontStr:SetFont(GetASFont(), TextSize(), flags)
    local red, green, blue
    if phaseNum == "soul" then
        red, green, blue = SoulColor()
    else
        red, green, blue = PreColor()
    end
    fontStr:SetTextColor(red, green, blue, 1)
end

-------------------------------------------------------------------------------
--  GCD length -- a PLAIN NUMBER, used only to build breakpoints and curve
--  points. Never compared against anything the engine owns.
--
--  The live cooldown first: the one moment this matters is the Arcane Surge
--  cast, which starts a GCD, so the client's own number carries every haste
--  buff that is currently up. It is secret in restricted combat, hence the
--  issecretvalue guard (captureGCD's pattern); the haste formula is the
--  fallback (ns.GCDTailAlpha's pattern), then the last known value, then the
--  unhasted 1.5.
-------------------------------------------------------------------------------

local function ReadLiveGcd()
    local cd = C_Spell and C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(GCD_SPELL_ID)
    local skinData = cd and cd.duration
    if skinData == nil then
        return nil
    end
    if issecretvalue and issecretvalue(skinData) then
        return nil
    end
    if type(skinData) ~= "number" then
        return nil
    end
    -- duration only means anything while the cooldown runs; idle it reports 0.
    if skinData >= 0.7 and skinData <= 1.6 then
        return skinData
    end
    return nil
end

local function ReadHasteGcd()
    local haste = UnitSpellHaste and UnitSpellHaste("player")
    if haste == nil then
        return nil
    end
    if issecretvalue and issecretvalue(haste) then
        return nil
    end
    if type(haste) ~= "number" then
        return nil
    end
    return 1.5 / (1 + haste / 100)
end

-- Reads only; GetGcdLen also records the result as the bound GCD.
local function CalcGcdLen()
    local success, length = pcall(ReadLiveGcd)
    if not success then
        length = nil
    end
    if not length then
        local ok2, hasted = pcall(ReadHasteGcd)
        if ok2 then
            length = hasted
        end
    end
    if not length then
        length = SoulState.gcdLen or 1.5
    end
    if length < 0.75 then
        length = 0.75
    elseif length > 1.6 then
        length = 1.6
    end -- engine floor / unhasted cap
    return math.floor(length * 100 + 0.5) / 100 -- bounds the formatter and curve caches
end

local function GetGcdLen()
    local length = CalcGcdLen()
    SoulState.gcdLen = length
    return length
end

-------------------------------------------------------------------------------
--  Formatters
--
--  Schema per the field-proven CDM/AuraKit tables: step and rounding live at
--  the BREAKPOINT level, components carry only the divisor, and a breakpoint
--  owns every value at or above its threshold. Thresholds are always in
--  SECONDS -- components change the displayed number, not the banding.
--
--  Two shapes here are novel for this codebase and so are attempted in
--  descending order with pcall on every SetBreakpoints: a format with a
--  LITERAL PREFIX ("Soul in %.1f") and a format with NO conversion at all
--  ("" to hide, "LAST" to warn). Each degrades to something still useful.
-------------------------------------------------------------------------------

local function NewFormatter(points)
    if
        not (
            C_StringUtil
            and C_StringUtil.CreateNumericRuleFormatter
            and Enum
            and Enum.NumericRuleFormatRounding
        )
    then
        return nil
    end
    local frame = C_StringUtil.CreateNumericRuleFormatter()
    if not pcall(frame.SetBreakpoints, frame, points) then
        return nil
    end
    return frame
end

-- Whole-GCD counting is laid out as one explicit band per GCD rather than
-- through a components divisor. Every proven divisor in this suite is an
-- INTEGER (60, 3600, 86400); a GCD is fractional (1.25s at raid haste), and a
-- fractional div is accepted by the validator and then ignored, which renders
-- the raw seconds instead of the count -- indistinguishable from "the counter
-- shows whole seconds". Bands need no divisor at all: band N owns
-- [ (N-1)*gcd, N*gcd ), which is exactly ceil(remaining / gcd). The epsilon
-- keeps the boundary off the band edge so an exact multiple of the GCD counts
-- as the lower band (a press landing precisely as the window shuts does not
-- land). The divisor form is kept as a fallback for the day divs go fractional.
local BAND_EPS = 0.0001
local BAND_MAX = 24

local function GcdBandPoints(fmt, gcdInfo, upTo, firstLabel)
    local pts = {}
    for num = 1, BAND_MAX do
        local t = (num == 1) and 0 or ((num - 1) * gcdInfo + BAND_EPS)
        if num > 1 and t >= upTo then
            break
        end
        pts[#pts + 1] = { threshold = t, format = (num == 1 and firstLabel) or string.format(fmt, num) }
    end
    return pts
end

-- Arcane Surge phase: nothing at all until `thr` seconds remain, then the
-- countdown to the Soul window. Attempts run best-first and each is retried
-- with hide rules "" then " " then none -- a formatter with no hide rule still
-- hides above the threshold via the alpha-0 color curve. The last attempt is
-- always TENTHS OF SECONDS, never the engine default: a formatter that fails
-- to build leaves SetDurationText with no formatter at all, and the engine
-- default renders bare whole seconds.
local surgeFmtCache = {}
local function SurgeFormatter(modeName, thresholdVal, gcdInfo)
    local cacheKey = modeName .. "|" .. thresholdVal .. "|" .. tostring(gcdInfo or 0)
    local cached = surgeFmtCache[cacheKey]
    if cached ~= nil then
        return cached or nil
    end

    local Up = Enum and Enum.NumericRuleFormatRounding and Enum.NumericRuleFormatRounding.Up
    local Down = Enum and Enum.NumericRuleFormatRounding and Enum.NumericRuleFormatRounding.Down
    local soulInCount = CludesUI.L("Soul in %d")
    local soulInTenths = CludesUI.L("Soul in %.1f")
    local tries
    if modeName == "gcd" then
        tries = {
            GcdBandPoints(soulInCount, gcdInfo, thresholdVal, string.format(soulInCount, 1)),
            {
                {
                    threshold = 0,
                    format = soulInCount,
                    step = 1,
                    rounding = Up,
                    components = { { div = gcdInfo } },
                },
            },
            { { threshold = 0, format = soulInTenths, step = 0.1, rounding = Down } },
            { { threshold = 0, format = "%.1f", step = 0.1, rounding = Down } },
        }
    else
        tries = {
            { { threshold = 0, format = soulInTenths, step = 0.1, rounding = Down } },
            { { threshold = 0, format = "%.1f", step = 0.1, rounding = Down } },
        }
    end
    local hides = { "", " ", false }

    for a = 1, #tries do
        local base = tries[a]
        for hgt = 1, #hides do
            local points = {}
            for i = 1, #base do
                points[i] = base[i]
            end
            -- Every band sits strictly below thr (GcdBandPoints stops there),
            -- so the hide rule always lands last and never duplicates a threshold.
            if hides[hgt] then
                points[#points + 1] = { threshold = thresholdVal, format = hides[hgt] }
            end
            local frame = NewFormatter(points)
            if frame then
                surgeFmtCache[cacheKey] = frame
                return frame
            end
        end
    end
    surgeFmtCache[cacheKey] = false
    return nil
end

-- Arcane Soul phase: seconds left, or the number of Arcane Barrages that still
-- fit. Barrage is instant and GCD-capped, so that count is ceil(remaining/gcd),
-- and the final one is the "do not cast another" warning. Soul is a fixed 4s;
-- the band table is generated a little past that for headroom.
local SOUL_BAND_MAX_S = 6
local soulFmtCache = {}
local function SoulFormatter(modeName, gcdInfo)
    local cacheKey = modeName .. "|" .. tostring(gcdInfo or 0)
    local cached = soulFmtCache[cacheKey]
    if cached ~= nil then
        return cached or nil
    end

    local Up = Enum and Enum.NumericRuleFormatRounding and Enum.NumericRuleFormatRounding.Up
    local Down = Enum and Enum.NumericRuleFormatRounding and Enum.NumericRuleFormatRounding.Down
    local frame
    if modeName == "gcd" then
        local lastText = CludesUI.L("LAST")
        frame = NewFormatter(GcdBandPoints("%d", gcdInfo, SOUL_BAND_MAX_S, lastText))
        if not frame then
            -- Divisor fallback. If the literal-only "LAST" band is what was
            -- refused, the same ceil renders a "1" there instead -- still red,
            -- because the color flip rides the curve, not the text.
            local total = {
                threshold = gcdInfo + BAND_EPS,
                format = "%d",
                step = 1,
                rounding = Up,
                components = { { div = gcdInfo } },
            }
            frame = NewFormatter({ { threshold = 0, format = lastText }, total })
                or NewFormatter({
                    { threshold = 0, format = "%d", step = 1, rounding = Up, components = { { div = gcdInfo } } },
                    total,
                })
        end
    end
    if not frame then
        frame = NewFormatter({ { threshold = 0, format = "%.1f", step = 0.1, rounding = Down } })
    end
    soulFmtCache[cacheKey] = frame or false
    return frame
end

-------------------------------------------------------------------------------
--  Color curves. Step type: a point owns every value from its position up to
--  the next one, so the bands line up exactly with the formatter's.
-------------------------------------------------------------------------------

-- Colors bake in at AddPoint time, so a curve exists per distinct color set.
-- Dragging a colour picker walks through hundreds of them, so the cache is
-- bounded rather than unbounded-but-small: past the cap it starts over, and
-- the settled color is rebuilt once on the next apply.
local CURVE_CACHE_MAX = 64
local curves, curveCacheN = {}, 0
local curvePoints
local function BuildCurve()
    local color = C_CurveUtil.CreateColorCurve()
    color:SetType(Enum.LuaCurveType.Step)
    for i = 1, #curvePoints do
        local point = curvePoints[i]
        color:AddPoint(point[1], CreateColor(point[2], point[3], point[4], point[5]))
    end
    return color
end

local function StepCurve(cacheKey, points)
    local cached = curves[cacheKey]
    if cached ~= nil then
        return cached or nil
    end
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and Enum and Enum.LuaCurveType) then
        curves[cacheKey] = false
        return nil
    end
    curvePoints = points
    local success, colorCurve = pcall(BuildCurve)
    curvePoints = nil
    if not success or not colorCurve then
        curves[cacheKey] = false
        return nil
    end
    if curveCacheN >= CURVE_CACHE_MAX then
        curves, curveCacheN = {}, 0
    end
    curves[cacheKey] = colorCurve
    curveCacheN = curveCacheN + 1
    return colorCurve
end

-- Visible below the threshold, alpha 0 above it: the second, independent hide
-- for the pre-Soul text (the formatter's empty-format rule is the first).
local function SurgeCurve(thresholdVal)
    local red, green, blue = PreColor()
    local cacheKey = string.format("s|%d|%.3f|%.3f|%.3f", thresholdVal, red, green, blue)
    return StepCurve(cacheKey, { { 0, red, green, blue, 1 }, { thresholdVal, red, green, blue, 0 } })
end

-- Seconds mode is one flat color; GCD mode flips to the Last color for the
-- final Barrage. Two points either way -- a one-point curve has no band.
local function SoulCurve(modeName, gcdInfo)
    local sr, sg, scrollBar = SoulColor()
    if modeName ~= "gcd" then
        local cacheKey = string.format("c|%.3f|%.3f|%.3f", sr, sg, scrollBar)
        return StepCurve(cacheKey, { { 0, sr, sg, scrollBar, 1 }, { 60, sr, sg, scrollBar, 1 } })
    end
    local lr, lg, lb = LastColor()
    local cacheKey = string.format("l|%.2f|%.3f|%.3f|%.3f|%.3f|%.3f|%.3f", gcdInfo, sr, sg, scrollBar, lr, lg, lb)
    return StepCurve(cacheKey, { { 0, lr, lg, lb, 1 }, { gcdInfo + 0.0001, sr, sg, scrollBar, 1 } })
end

-------------------------------------------------------------------------------
--  Duration-text binding
--
--  SetDurationText is a button call, so it is denied while auras are secret.
--  Every attempt is stamped only on a COMPLETE landing (BmRebindDurationCurve's
--  rule): a denied or color-stripped registration leaves the stamp alone and
--  raises S.dirty, so the restriction-lift drain re-runs it. Until then the
--  previously bound formatter keeps rendering -- stale banding, still correct
--  time, which is the accepted degradation.
-------------------------------------------------------------------------------

local function StampFor(phaseNum, modeName, thresholdVal, gcdInfo)
    if phaseNum == "surge" then
        local red, green, blue = PreColor()
        return string.format("%s|%d|%.2f|%.3f|%.3f|%.3f", modeName, thresholdVal, gcdInfo or 0, red, green, blue)
    end
    local sr, sg, scrollBar = SoulColor()
    local lr, lg, lb = LastColor()
    return string.format(
        "%s|%.2f|%.3f|%.3f|%.3f|%.3f|%.3f|%.3f",
        modeName,
        gcdInfo or 0,
        sr,
        sg,
        scrollBar,
        lr,
        lg,
        lb
    )
end

local function BindPhase(phaseNum, force)
    local AK = CludesUI.AuraKit
    local state = SoulState.ph[phaseNum]
    if not (AK and state.btn and state.fs) then
        return
    end

    local modeName = PhaseMode(phaseNum)
    local thresholdVal = Thr()
    local gcdInfo = (modeName == "gcd") and GetGcdLen() or nil
    local stamp = StampFor(phaseNum, modeName, thresholdVal, gcdInfo)
    if not force and state.stamp == stamp then
        return
    end

    local fmt, colorCurve
    if phaseNum == "surge" then
        fmt, colorCurve = SurgeFormatter(modeName, thresholdVal, gcdInfo), SurgeCurve(thresholdVal)
    else
        fmt, colorCurve = SoulFormatter(modeName, gcdInfo), SoulCurve(modeName, gcdInfo)
    end

    local success, full = AK.SetDurationTextSafe(state.btn, state.fs, AK.BuildDurationTextOpts(fmt, colorCurve))
    if success and (full or not colorCurve) then
        state.stamp = stamp
    else
        state.stamp = nil
        SoulState.dirty = true
    end
end

-------------------------------------------------------------------------------
--  Build
-------------------------------------------------------------------------------

local function MakeProxy()
    if SoulState.proxy then
        return
    end
    SoulState.proxy = CreateFrame("Frame", nil, UIParent)
    SoulState.proxy:SetSize(ProxySize())
    SoulState.proxy:Hide()
end

local SURGE_INCLUDE = { [SURGE_AURA_ID] = true, [SURGE_CAST_ID] = true }
local SOUL_INCLUDE = { [SOUL_AURA_ID] = true }

local function BuildPhase(phaseNum, include)
    local AK = CludesUI.AuraKit
    local state = SoulState.ph[phaseNum]
    if state.container then
        return
    end

    local boxHolder = AK.CreateContainerShell(SoulState.proxy, { point = { "CENTER" } })
    AK.AddSlotToContainer(boxHolder, {
        key = phaseNum,
        filter = { "HELPFUL" },
        candidateFilters = { includeSpellIDs = include },
        style = STYLE_KEY,
        extraInit = function(btnFrame)
            -- Creation window: the only legal moment to touch this subtree.
            -- Two-point anchoring sizes the button by anchors forever; all
            -- repositioning after this is proxy moves.
            btnFrame:SetAllPoints(SoulState.proxy)
            -- Display-only overlay with no OnClick: an engine aura button comes
            -- mouse-enabled, and clicks alone would make it an invisible blocker
            -- over its whole rect for as long as the buff is up.
            if btnFrame.SetMouseClickEnabled then
                btnFrame:SetMouseClickEnabled(false)
            end
            if btnFrame.SetMouseMotionEnabled then
                btnFrame:SetMouseMotionEnabled(false)
            end
            state.btn = btnFrame

            -- ARMORED: an uncaught error here aborts the engine's
            -- CreateFrameBatch and kills the slot. Failures land in S.fsErr.
            local okFS, errFS = pcall(function()
                local tc = CreateFrame("Frame", nil, btnFrame)
                tc:SetAllPoints(btnFrame)
                tc:SetFrameLevel(btnFrame:GetFrameLevel() + 5)
                local fontStr = tc:CreateFontString(nil, "OVERLAY")
                -- Font BEFORE registration (the engine SetText()s every
                -- registered string; an unfonted FontString hard-errors).
                ApplyFsLook(phaseNum, fontStr)
                fontStr:SetPoint("CENTER", btnFrame, "CENTER", 0, 0)
                state.fs = fontStr
                BindPhase(phaseNum, true)
            end)
            if not okFS then
                SoulState.fsErr = errFS
            end
        end,
    })
    AK.FinishContainer(boxHolder, "player")
    -- One container-level set lifts the whole engine subtree above the proxy.
    boxHolder:SetFrameLevel(SoulState.proxy:GetFrameLevel() + 1)
    state.container = boxHolder
end

-- POSITION ONLY. Unlock mode owns the frame's placement for as long as the
-- mover is up, and GetBarFrame -> elem.getFrame runs on every drag frame, so
-- this must never be reachable from getFrame: re-anchoring there yanks the
-- frame the player is dragging straight back to the stored position. Only
-- applyPos and ordinary (non-unlock) applies call it. Same split as the Target
-- Distance element, whose getFrame deliberately skips ApplyFrameSettings.
local function PlaceProxy()
    if not SoulState.proxy then
        return
    end
    -- Anchored to another element: the unlock anchor system owns placement;
    -- re-applying the stored absolute here would slam the frame back to a
    -- stale spot on every apply (same guard as the GCD / totem bars).
    local anchored = CludesUI.IsUnlockAnchored and CludesUI.IsUnlockAnchored(UNLOCK_KEY)
    if anchored and SoulState.proxy:GetLeft() then
        return
    end

    local profile = P()
    local place = (profile and profile.unlockPos) or DEFAULT_POS
    local point = place.point or "CENTER"
    local px, py = place.x or 0, place.y or 0
    local PPa = CludesUI and CludesUI.PP
    if PPa then
        local effScale = SoulState.proxy:GetEffectiveScale()
        -- CENTER anchor with stored CENTER offsets: SnapCenterForDim gives
        -- odd-pixel-dim frames the +0.5 offset that lands edges on whole pixels.
        local isCenterAnchor = (point == "CENTER") and (place.relPoint == "CENTER" or place.relPoint == nil)
        if isCenterAnchor and PPa.SnapCenterForDim then
            px = PPa.SnapCenterForDim(px, SoulState.proxy:GetWidth() or 0, effScale)
            py = PPa.SnapCenterForDim(py, SoulState.proxy:GetHeight() or 0, effScale)
        elseif PPa.SnapForES then
            px = PPa.SnapForES(px, effScale)
            py = PPa.SnapForES(py, effScale)
        end
    end
    SoulState.proxy:ClearAllPoints()
    SoulState.proxy:SetPoint(point, UIParent, place.relPoint or point, px, py)
end

-- LOOK ONLY: size, fonts, colors, duration bindings. Safe to run at any time,
-- including mid-drag.
local function ApplyLook()
    if not SoulState.proxy then
        return
    end
    SoulState.proxy:SetSize(ProxySize())

    -- Font/size/color live on OUR regions, but they are children of an engine
    -- aura button, so post-creation writes are denied under aura secrecy like
    -- any other write into that subtree: pcall and defer to the lift.
    for phaseNum, state in pairs(SoulState.ph) do
        if state.fs then
            if not pcall(ApplyFsLook, phaseNum, state.fs) then
                SoulState.dirty = true
            end
        end
        BindPhase(phaseNum)
    end
end

local function ApplySettings()
    ApplyLook()
    PlaceProxy()
end

local function Build()
    local AK = CludesUI.AuraKit
    if SoulState.built or not AK then
        return
    end
    AK.styles[STYLE_KEY] = AK.styles[STYLE_KEY] or { noRegions = true, width = 1, height = 1 }
    MakeProxy()
    BuildPhase("surge", SURGE_INCLUDE)
    BuildPhase("soul", SOUL_INCLUDE)
    SoulState.built = true

    -- Self-guarded dirty flag: lift callbacks are never unregistered, so an
    -- idle firing must cost one boolean test.
    if not SoulState.liftHooked and AK.OnRestrictionLift then
        SoulState.liftHooked = true
        AK.OnRestrictionLift(function()
            if not SoulState.dirty then
                return
            end
            SoulState.dirty = nil
            if mod.AS_Apply then
                mod.AS_Apply()
            end
        end)
    end
end

local function EnsureBuilt()
    if SoulState.built or SoulState.queued or SoulState.buildErr then
        return
    end
    local AK = CludesUI.AuraKit
    if not (AK and AK.QueueBuildJob) then
        return
    end
    SoulState.queued = true
    AKWorker:Queue(function()
        SoulState.queued = nil
        -- Latched, not retried: every ERB:ApplyAll would otherwise re-enter a
        -- hard build failure and turn one broken container into an error storm.
        -- The display stays absent until a /reload; the reason sits in S.buildErr.
        local success, err = pcall(Build)
        if not success then
            SoulState.buildErr = err
            return
        end
        ApplySettings()
    end, "erb:arcsoul-shell")
end

-------------------------------------------------------------------------------
--  Sample string over the proxy, for the unlock-mode mover and the options live
--  preview. Engine slots only render while their aura is up, so both get a
--  plain string on our own frame -- no engine restrictions.
-------------------------------------------------------------------------------

-- Sample look and text, shared with the options preview header. The font is
-- set again only when it changed; returns the text size and whether it did.
local function StyleSample(fontStr)
    local font, flags, size, modeName = GetASFont(), GetASOutline(), TextSize(), PhaseMode("surge")
    local stamp = font .. "|" .. size .. "|" .. flags .. "|" .. modeName
    local changed = fontStr._asStamp ~= stamp
    if changed then
        CludesUI.PrimeFontShadow(fontStr, flags == "")
        fontStr:SetFont(font, size, flags)
        fontStr._asStamp = stamp
    end
    fontStr:SetTextColor(PreColor())
    fontStr:SetText(
        modeName == "gcd" and string.format(CludesUI.L("Soul in %d"), 3)
            or string.format(CludesUI.L("Soul in %.1f"), 3.2)
    )
    return size, changed
end
_G._CURB_StyleArcaneSoulSample = StyleSample

-- The sample sits on its own host over the proxy, so it can show while the
-- proxy (and with it any engine slot built earlier) stays hidden. Showing the
-- proxy is Activate's: every caller runs it first.
local function ShowPreview()
    MakeProxy()
    local fontStr = SoulState.sample
    if not fontStr then
        local owner = CreateFrame("Frame", nil, UIParent)
        owner:SetAllPoints(SoulState.proxy)
        owner:SetFrameStrata(SoulState.proxy:GetFrameStrata())
        owner:SetFrameLevel(SoulState.proxy:GetFrameLevel() + 10)
        SoulState.sampleHost = owner
        fontStr = owner:CreateFontString(nil, "OVERLAY")
        fontStr:SetPoint("CENTER", owner, "CENTER", 0, 0)
        SoulState.sample = fontStr
    end
    StyleSample(fontStr)
    if SoulState.demo then
        SoulState.demo:Hide()
    end
    fontStr:Show()
    SoulState.sampleHost:Show()
end

local function HideSample()
    if SoulState.sampleHost then
        SoulState.sampleHost:Hide()
    end
    if SoulState.demo then
        SoulState.demo:Hide()
    end
end

-------------------------------------------------------------------------------
--  Live preview: the combat sequence replayed for the options page, in its
--  header and, while that page shows out of combat, as this sample at its real
--  spot. Texts and colours follow the formatters and curves above. The driver
--  only runs while a frame using it shows.
-------------------------------------------------------------------------------

local SOUL_LEN, DEMO_GAP, DEMO_GCD_AGE = 4, 1, 5

-- ceil(left / gcd) with the band boundary rule of GcdBandPoints.
local function DemoGcdCount(leftX, gcdInfo)
    local num = math.floor((leftX - BAND_EPS) / gcdInfo) + 1
    return (num < 1) and 1 or num
end

local function DemoText(fontStr, t, gcdInfo)
    local thresholdVal = Thr()
    t = t % (thresholdVal + SOUL_LEN + DEMO_GAP)
    if t >= thresholdVal + SOUL_LEN then
        fontStr:SetText("")
        return
    end
    local red, green, blue
    if t < thresholdVal then
        -- The hide rule owns thr itself: the first visible value is below it.
        local leftX = math.min(thresholdVal - t, thresholdVal - 0.01)
        if PhaseMode("surge") == "gcd" then
            fontStr:SetFormattedText(CludesUI.L("Soul in %d"), DemoGcdCount(leftX, gcdInfo))
        else
            fontStr:SetFormattedText(CludesUI.L("Soul in %.1f"), math.floor(leftX * 10) / 10)
        end
        red, green, blue = PreColor()
    else
        local leftX = thresholdVal + SOUL_LEN - t
        if PhaseMode("soul") ~= "gcd" then
            fontStr:SetFormattedText("%.1f", math.floor(leftX * 10) / 10)
            red, green, blue = SoulColor()
        else
            local num = DemoGcdCount(leftX, gcdInfo)
            if num == 1 then
                fontStr:SetText(CludesUI.L("LAST"))
                red, green, blue = LastColor()
            else
                fontStr:SetFormattedText("%d", num)
                red, green, blue = SoulColor()
            end
        end
    end
    fontStr:SetTextColor(red, green, blue, 1)
end

-- One step for a driver frame holding its font string in _fs. The GCD is the
-- driver's own (re-read every few seconds while a phase counts GCDs), never
-- the live binding's S.gcdLen.
local function DemoTick(self)
    local t = self._demoT or 0
    if NeedsGcd() and (not self._demoGcd or t - (self._demoGcdAt or 0) > DEMO_GCD_AGE) then
        self._demoGcd, self._demoGcdAt = CalcGcdLen(), t
    end
    if self._fs then
        DemoText(self._fs, t, self._demoGcd)
    end
end
_G._CURB_ArcaneSoulDemoTick = DemoTick

local function DemoOnUpdate(self, elapsed)
    self._demoT = (self._demoT or 0) + elapsed
    self._demoAcc = (self._demoAcc or 0) + elapsed
    if self._demoAcc < 0.1 then
        return
    end
    self._demoAcc = 0
    DemoTick(self)
end
_G._CURB_ArcaneSoulDemoOnUpdate = DemoOnUpdate

local function ShowDemo()
    ShowPreview()
    if not SoulState.demo then
        SoulState.demo = CreateFrame("Frame", nil, SoulState.sampleHost)
        SoulState.demo:SetScript("OnUpdate", DemoOnUpdate)
    end
    SoulState.demo._fs = SoulState.sample
    SoulState.demo:Show()
    DemoTick(SoulState.demo)
end

-------------------------------------------------------------------------------
--  Gating -- MAGE + Arcane + Sunfury. The hero-tree test only ever NARROWS:
--  an unreadable or absent answer falls through to the spec-only gate rather
--  than parking a display the player asked for.
-------------------------------------------------------------------------------

local function OnForClass()
    local profile = P()
    return (profile and profile.enabled and SoulState.class == "MAGE" and not FOREVER) and true or false
end

local function GateOK()
    if not OnForClass() then
        return false
    end
    -- Both spellings are live in this codebase (the options pages use the
    -- C_ namespace, the modules the globals); take whichever answers.
    local position = (
        C_SpecializationInfo
        and C_SpecializationInfo.GetSpecialization
        and C_SpecializationInfo.GetSpecialization()
    ) or (GetSpecialization and GetSpecialization())
    if not position then
        return false
    end
    local specID = (
        C_SpecializationInfo
        and C_SpecializationInfo.GetSpecializationInfo
        and C_SpecializationInfo.GetSpecializationInfo(position)
    ) or (GetSpecializationInfo and GetSpecializationInfo(position))
    if specID ~= ARCANE_SPEC_ID then
        return false
    end
    if C_ClassTalents and C_ClassTalents.GetActiveHeroTalentSpec then
        local success, tree = pcall(C_ClassTalents.GetActiveHeroTalentSpec)
        if success and type(tree) == "number" and tree ~= SUNFURY_TREE_ID then
            return false
        end
    end
    return true
end

local function Park()
    HideSample()
    if SoulState.proxy then
        SoulState.proxy:Hide()
    end
end

-- Mover callbacks are NOT unlock-mode-only: the spec-override layer flush
-- re-applies stored positions on spec/talent changes, and GetBarFrame resolves
-- anchors at any time. Activate() ends in proxy:Show(), so those callbacks must
-- not reach it on a non-Sunfury tree (Spellslinger still casts Arcane Surge, so
-- the Surge slot would render). Placement is always safe; SHOWING is the gate's
-- to decide, and unlock mode is the one caller that overrides it (the mover has
-- to be grabbable for any Mage).
local function MoverShowOK()
    return (CludesUI and CludesUI._unlockActive) or GateOK()
end

-- placeOnly: size and position the proxy but keep it, and with it any engine
-- slot built earlier, hidden (the options live preview for a Mage the gate
-- does not pass; its sample has a host of its own).
local function StartTracking(placeOnly)
    MakeProxy()
    if placeOnly then
        SoulState.proxy:SetSize(ProxySize())
    else
        ApplyLook()
    end
    -- Placement belongs to the mover while unlock mode is open (see ApplyPosition).
    if not (CludesUI and CludesUI._unlockActive) then
        PlaceProxy()
    end
    if placeOnly then
        SoulState.proxy:Hide()
        return
    end
    SoulState.proxy:Show()
    if not SoulState.built then
        EnsureBuilt()
    end
end

-------------------------------------------------------------------------------
--  Events -- registered only while the feature is on and the player is a Mage.
--  Seconds mode costs nothing in combat at all; GCD mode adds the one Surge
--  cast, which is where the GCD length is worth re-reading.
-------------------------------------------------------------------------------

local applyPending
local function RunPendingApply()
    applyPending = nil
    if mod.AS_Apply then
        mod.AS_Apply()
    end
end

-- Talent/loadout changes fire in a burst (a loadout swap applies many nodes at
-- once); coalesce into one gate re-evaluation.
local function ScheduleApply()
    if applyPending then
        return
    end
    applyPending = true
    C_Timer.After(0.1, RunPendingApply)
end

local function OnGateEvent(_, evt, _, _, spellId)
    if evt == "UNIT_SPELLCAST_SUCCEEDED" then
        if spellId ~= SURGE_CAST_ID then
            return
        end
        -- Rebind only on a genuine change: the deadband stops haste jitter from
        -- churning the formatter cache, and a denied rebind leaves the previous
        -- (still ticking) binding in place.
        local previous = SoulState.gcdLen
        local length = GetGcdLen()
        if previous and length >= previous - 0.02 and length <= previous + 0.02 then
            SoulState.gcdLen = previous
            return
        end
        BindPhase("surge")
        BindPhase("soul")
        return
    end
    ScheduleApply()
end

local function EnsureGateEvents()
    if not SoulState.ev then
        SoulState.ev = CreateFrame("Frame")
        SoulState.ev:SetScript("OnEvent", OnGateEvent)
    end
    if not SoulState.evGate then
        SoulState.evGate = true
        SoulState.ev:RegisterEvent("PLAYER_ENTERING_WORLD")
        SoulState.ev:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        SoulState.ev:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
        SoulState.ev:RegisterEvent("TRAIT_CONFIG_UPDATED")
    end
    local wantCast = NeedsGcd()
    if wantCast and not SoulState.evCast then
        SoulState.evCast = true
        SoulState.ev:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    elseif not wantCast and SoulState.evCast then
        SoulState.evCast = nil
        SoulState.ev:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    end
end

local function DropGateEvents()
    if not SoulState.ev then
        return
    end
    SoulState.ev:UnregisterAllEvents()
    SoulState.evGate, SoulState.evCast = nil, nil
end

-------------------------------------------------------------------------------
--  Options live preview state. The options page header reports whether it
--  shows (owner: its watcher frame, so a rebuilt header's late hide cannot
--  switch off the new one). The combat events are registered only while that
--  page shows for a Mage with the helper on.
-------------------------------------------------------------------------------

local function DemoOnEvent(_, evt)
    SoulState.demoCombat = (evt == "PLAYER_REGEN_DISABLED")
    if mod.AS_Apply then
        mod.AS_Apply()
    end
end

-- Brings S.demoApplied (what AS_Apply reads) and the combat events in line
-- with the owner; true when that changed anything.
local function SyncDemo()
    local wanted = (SoulState.demoOwner ~= nil) and OnForClass()
    if wanted == (SoulState.demoApplied or false) then
        return false
    end
    SoulState.demoApplied = wanted
    if wanted then
        if not SoulState.demoEv then
            SoulState.demoEv = CreateFrame("Frame")
            SoulState.demoEv:SetScript("OnEvent", DemoOnEvent)
        end
        SoulState.demoEv:RegisterEvent("PLAYER_REGEN_DISABLED")
        SoulState.demoEv:RegisterEvent("PLAYER_REGEN_ENABLED")
        SoulState.demoCombat = InCombatLockdown() and true or nil
    elseif SoulState.demoEv then
        SoulState.demoEv:UnregisterAllEvents()
        SoulState.demoCombat = nil
    end
    return true
end

-------------------------------------------------------------------------------
--  Single entry point: called from ERB:ApplyAll (login, profile swap, every
--  options change) and from this module's own gate events.
-------------------------------------------------------------------------------

function mod.AS_Apply()
    SyncDemo()
    if not OnForClass() then
        DropGateEvents()
        Park()
        return
    end
    EnsureGateEvents()
    if CludesUI and CludesUI._unlockActive then
        StartTracking()
        ShowPreview()
        return
    end
    HideSample()
    -- Options page open, out of combat: the live preview, for any Mage (as
    -- unlock mode). The engine slots only for a Mage the gate passes.
    if SoulState.demoApplied and not SoulState.demoCombat then
        StartTracking(not GateOK())
        ShowDemo()
        return
    end
    if not GateOK() then
        Park()
        return
    end
    StartTracking()
end

-- Applied a frame later, once: a rebuild hides and shows the watcher in one pass.
local function ApplyDemoState()
    SoulState.demoPending = nil
    if SyncDemo() and mod.AS_Apply then
        mod.AS_Apply()
    end
end

_G._CURB_ArcaneSoulScreenDemo = function(ownerFrame, on)
    if on then
        SoulState.demoOwner = ownerFrame
    elseif SoulState.demoOwner == ownerFrame then
        SoulState.demoOwner = nil
    else
        return
    end
    if not SoulState.demoPending then
        SoulState.demoPending = true
        C_Timer.After(0, ApplyDemoState)
    end
end

-------------------------------------------------------------------------------
--  Unlock element
-------------------------------------------------------------------------------

function mod.AS_MakeUnlockElement(MK)
    if not MK or SoulState.class ~= "MAGE" or FOREVER then
        return nil
    end

    if not SoulState.unlockHooked and CludesUI and CludesUI.RegisterUnlockModeListener then
        SoulState.unlockHooked = true
        CludesUI:RegisterUnlockModeListener(UNLOCK_KEY, function(isActive)
            if isActive then
                if OnForClass() then
                    StartTracking()
                    ShowPreview()
                end
            else
                HideSample()
                if mod.AS_Apply then
                    mod.AS_Apply()
                end
            end
        end)
    end

    return MK({
        key = UNLOCK_KEY,
        label = "Arcane Soul",
        group = "Resource Bars",
        order = 507,
        noResize = true,
        noAnchorTarget = true,
        isHidden = function()
            return not OnForClass()
        end,
        getFrame = function()
            if not OnForClass() then
                return nil
            end
            if CludesUI._unlockActive then
                StartTracking()
                ShowPreview()
            else
                -- Outside unlock mode this is a pure geometry request (anchor
                -- resolution), so it hands back the proxy WITHOUT showing it.
                -- See MoverShowOK: Activate() ends in proxy:Show().
                MakeProxy()
                if MoverShowOK() then
                    StartTracking()
                end
            end
            return SoulState.proxy
        end,
        getSize = function()
            return ProxySize()
        end,
        savePos = function(_, anchorPoint, relPoint, posX, posY)
            if not anchorPoint then
                return
            end
            local profile = P()
            if not profile then
                return
            end
            profile.unlockPos = { point = anchorPoint, relPoint = relPoint or anchorPoint, x = posX, y = posY }
            if not CludesUI._unlockActive then
                PlaceProxy()
            end
        end,
        loadPos = function()
            local profile = P()
            local place = profile and profile.unlockPos
            if place and place.point then
                return {
                    point = place.point,
                    relPoint = place.relPoint or place.point,
                    x = place.x,
                    y = place.y,
                }
            end
            return {
                point = DEFAULT_POS.point,
                relPoint = DEFAULT_POS.relPoint,
                x = DEFAULT_POS.x,
                y = DEFAULT_POS.y,
            }
        end,
        clearPos = function()
            local profile = P()
            if profile then
                profile.unlockPos = nil
            end
            if SoulState.proxy then
                PlaceProxy()
            end
        end,
        applyPos = function()
            if not OnForClass() then
                return
            end
            MakeProxy()
            -- applyPos IS the "put it where it is stored" request, so it PLACES
            -- unconditionally -- but placing is not showing (see MoverShowOK).
            if MoverShowOK() then
                StartTracking()
            end
            PlaceProxy()
            if CludesUI._unlockActive then
                ShowPreview()
            end
        end,
    })
end
