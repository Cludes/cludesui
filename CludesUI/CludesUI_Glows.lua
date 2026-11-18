if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUI_Glows.lua
--  Shared glow rendering engine for the CludesUI addon suite.
--  Provides: Pixel Glow (procedural ants), Action Button Glow, Auto-Cast
--  Shine, Shape Glow, FlipBook-based glows (GCD, Modern WoW, Classic WoW), and
--  Blackout (solid colour fill with adjustable transparency).
--  Each addon attaches to CludesUI.Glows.* instead of duplicating engines.
-------------------------------------------------------------------------------
if not CludesUI then
    return
end
if CludesUI.Glows then
    return
end -- already loaded by another addon

local floor = math.floor
local min = math.min
local ceil = math.ceil
local sin = math.sin

-------------------------------------------------------------------------------
--  Style Definitions (superset of all addons)
--  Each addon picks from this table by index or iterates for its dropdown.
--  Fields: name, procedural, buttonGlow, autocast, shapeGlow, solidFill, atlas,
--          texture, rows, columns, frames, duration, frameW, frameH, scale,
--          previewScale
-------------------------------------------------------------------------------
local GLOW_STYLES = {
    { name = "Pixel Glow", procedural = true },
    { name = "Action Button Glow", buttonGlow = true },
    { name = "Auto-Cast Shine", autocast = true },
    { name = "Shape Glow", shapeGlow = true },
    { name = "GCD", atlas = "RotationHelper_Ants_Flipbook", texPadding = 1.6 },
    { name = "Modern WoW Glow", atlas = "UI-HUD-ActionBar-Proc-Loop-Flipbook", texPadding = 1.4 },
    {
        name = "Classic WoW Glow",
        texture = "Interface\\SpellActivationOverlay\\IconAlertAnts",
        -- 5x5 grid = 25 cells, but only the first 22 are real ant frames; the last
        -- 3 are blank. Playing all 25 flashed an empty gap each loop that read as a
        -- backwards stutter. 22 matches what the Action Button Glow uses.
        -- This entry also doubles as Action Button Glow's FlipBook twin on
        -- engine-hosted buttons; the twin adds ABG's soft outer halo via
        -- opts.abgHalo, scoped to that substitution (see StartEngineGlow) --
        -- a direct Classic pick keeps this entry's bare-ants look.
        rows = 5,
        columns = 5,
        frames = 22,
        duration = 0.3,
        frameW = 48,
        frameH = 48,
        texPadding = 1.25,
    },
    { name = "Blackout", solidFill = true },
}

-- Static border styles, picker values outside the STYLES list (see the
-- Blizzard Border and Blizzard Pandemic Border blocks below).
local STEALABLE_BORDER = 99
local PANDEMIC_BORDER = 98

-- Engine hosts bound to their aura button (G.BindEngineHost): wrapper ->
-- { button, d }. Kept outside the wrapper's own fields, so the options frame
-- pool needs no key for it.
local BOUND = setmetatable({}, { __mode = "k" })

-------------------------------------------------------------------------------
--  Texture constants
-------------------------------------------------------------------------------
local ANTS_TEX = [[Interface\SpellActivationOverlay\IconAlertAnts]]
local ICON_ALERT_TEX = [[Interface\SpellActivationOverlay\IconAlert]]
local BG_GLOW_L, BG_GLOW_R = 0.00781250, 0.50781250
local BG_GLOW_T, BG_GLOW_B = 0.27734375, 0.52734375
local SHINE_TEX = [[Interface\Artifacts\Artifacts]]
local SHINE_COORDS = { 0.8115234375, 0.9169921875, 0.8798828125, 0.9853515625 }
local SPARKLE_LAYER_SIZES = { 7, 6, 5, 4 }

-------------------------------------------------------------------------------
--  Central Glow Driver
--  One OnUpdate (on a frame we own) animates every active glow. Each animated
--  engine registers its wrapper tagged by kind; this driver gates the WHOLE
--  dispatch loop at ~60fps and routes each registered wrapper to its update
--  function. FlipBook glows are C-driven (AnimationGroup) and never register
--  here. The driver hides itself when no glow is registered (zero idle cost)
--  and re-arms when the first glow registers.
-------------------------------------------------------------------------------
local DRIVER_GATE = 0.016 -- ~60fps ceiling for the entire dispatch loop

-- Array-based registry for cheap churn. _reg is a dense 1..N array of wrapper frames;
-- _regFn the parallel array of their engine update functions (called directly in the
-- hot loop, so dispatch is pure array access with no kind->fn lookup); _regIndex maps
-- wrapper -> its slot in _reg (for O(1) swap-remove); _regKind maps wrapper -> its kind
-- tag, read only by Unregister (cold path). _regCount is the live entry count.
local _reg = {}
local _regFn = {}
local _regIndex = {}
local _regKind = {}
local _regCount = 0
local _driver
local _driverAccum = 0

-- Unregister a wrapper. Safe no-op when the wrapper was never registered (Stop
-- without Start), so calling every Stop* in StopAllGlows is fine. When a kind is
-- passed it must match the wrapper's current registration: this makes a lone
-- cross-kind Stop* (e.g. StopButtonGlow on an "ants"-registered wrapper) a no-op
-- instead of tearing down the still-active engine. A nil kind stays kind-agnostic.
-- Swap-removes the entry so churn stays O(1); hides the driver when empty.
-- (Defined above the driver loop: the loop drops forbidden wrappers itself.)
local function _Unregister(holder, kind)
    local position = _regIndex[holder]
    if not position then
        return
    end
    if kind and _regKind[holder] ~= kind then
        return
    end
    local last = _reg[_regCount]
    _reg[position] = last
    _regFn[position] = _regFn[_regCount]
    _regIndex[last] = position
    _reg[_regCount] = nil
    _regFn[_regCount] = nil
    _regCount = _regCount - 1
    _regIndex[holder] = nil
    _regKind[holder] = nil
    if _regCount == 0 and _driver then
        _driver:Hide()
    end
end

local function _VisProbe(wid)
    return wid:IsVisible()
end

local function _DriverOnUpdate(self, timePassed)
    -- Gate the WHOLE loop at ~60fps: accumulate raw elapsed and only run a
    -- dispatch pass once the accumulator reaches the gate. The accumulated dt
    -- is handed to every engine and the accumulator resets to 0 (not minus the
    -- gate), so the sum of dispatched dt equals real elapsed exactly --
    -- animation speed is identical to a per-frame OnUpdate.
    local dt = _driverAccum + timePassed
    if dt < DRIVER_GATE then
        _driverAccum = dt
        return
    end
    _driverAccum = 0
    -- Walk the dense array by index. An engine may unregister itself (or
    -- another wrapper) from inside its own update via Stop*, which swap-removes
    -- and shrinks _regCount; re-read _regCount each step and, when the current
    -- slot was swapped, re-test the same slot instead of advancing.
    local i = 1
    while i <= _regCount do
        local holder = _reg[i]
        -- Visibility gate: a per-wrapper OnUpdate used to stop for free when
        -- the frame OR any ancestor was hidden. IsVisible() reproduces that
        -- (own shown flag AND every ancestor shown). It reads only boolean
        -- shown flags, never alpha, so it is safe on the secret-alpha overlays
        -- (important-cast, RaidFrames threshold) whose alpha is a secret value.
        -- A wrapper that is shown but alpha-0 stays IsVisible()==true and keeps
        -- animating exactly as it did under its own OnUpdate; only Hide()-d or
        -- hidden-ancestor wrappers are skipped, and they resume automatically.
        -- 12.1: a wrapper inside an ENGINE aura-button subtree has a SECRET
        -- visibility (the engine drives the button's shown state); a boolean test on it
        -- errors. Treat secret as hidden: the animation freezes for those wrappers
        -- while restricted (the glow still renders when its parent is actually shown)
        -- instead of ticking on the engine's 10x hidden pool buttons. Since PTR build
        -- 68914 the aura-button subtree is FORBIDDEN to addon code outside sanctioned
        -- windows: the IsVisible call itself throws instead of returning a secret, and
        -- one throwing wrapper would error every driver pass and freeze every other
        -- registered glow behind it. Probe under pcall and drop a throwing wrapper
        -- permanently -- forbidden-partition membership never recovers. (Driver styles
        -- should not be hosted there at all; StartEngineGlow is the sanctioned path.
        -- This guard makes a mistake non-fatal.)
        local vis = true
        if holder.IsVisible then
            local okv
            okv, vis = pcall(_VisProbe, holder)
            if not okv then
                _Unregister(holder)
                vis = false
            elseif issecretvalue and issecretvalue(vis) then
                vis = false
            end
        end
        if vis then
            local func = _regFn[i]
            if func then
                func(holder, dt)
            end
        end
        if _reg[i] == holder then
            i = i + 1
        end
    end
    if _regCount == 0 then
        self:Hide()
    end
end

local function _Arm()
    if not _driver then
        _driver = CreateFrame("Frame")
        _driver:Hide()
        _driver:SetScript("OnUpdate", _DriverOnUpdate)
    end
    _driverAccum = 0 -- avoid a stale-dt spike after an idle period
    _driver:Show()
end

-- Register a wrapper under the given kind. Idempotent: a second Start on the
-- same wrapper does not duplicate the entry or move the count; it only refreshes
-- the kind tag (so a style switch is robust even without a Stop first). Arms the
-- driver on the 0 -> 1 transition.
local function _Register(holder, func, kind)
    local i = _regIndex[holder]
    if i then
        _regFn[i] = func
        _regKind[holder] = kind
        return
    end
    _regCount = _regCount + 1
    _reg[_regCount] = holder
    _regFn[_regCount] = func
    _regIndex[holder] = _regCount
    _regKind[holder] = kind
    if _regCount == 1 then
        _Arm()
    end
end

-------------------------------------------------------------------------------
--  Procedural Ants Engine (texcoord-scroll)
--  4 fixed edge textures whose dashes march by scrolling a tileable strip via
--  SetTexCoord -- no per-frame SetPoint/SetSize, so it is FlipBook-cheap. The
--  N (line count) / thickness / speed / color are all configurable; the dash
--  LENGTH is the texture's duty cycle rather than a runtime segment length.
-------------------------------------------------------------------------------
local DASH_H = [[Interface\AddOns\CludesUI\media\glow-dash-h.tga]]
local DASH_V = [[Interface\AddOns\CludesUI\media\glow-dash-v.tga]]

-- Resolve the wrapper's pixel-snapped size and precompute the per-edge phase endpoints
-- (invariant until the next resize). Returns false while the size is still 0, the scale
-- chain is degenerate, or the pixel grid is unusable, so the caller retries on a later
-- tick. Shared by the animated (_AntsOnUpdate) and static (_AntsStaticSettle) paths.
local function _AntsResolveSize(self, glowData)
    local wid, hgt = self:GetSize()
    -- A secret size (the wrapper sits in a restricted layout) never reaches tostring or
    -- arithmetic: it takes the start-time fallback. Plain sizes keep the taint strip.
    if issecretvalue(wid) or issecretvalue(hgt) then
        wid, hgt = 0, 0
    else
        wid = tonumber(tostring(wid)) or 0
        hgt = tonumber(tostring(hgt)) or 0
    end
    if wid * hgt == 0 and glowData.fallbackW and glowData.fallbackW > 0 then
        wid = glowData.fallbackW
        hgt = glowData.fallbackH or glowData.fallbackW
    end
    if wid * hgt == 0 then
        return false
    end
    -- Snap dimensions AND thickness to physical pixels so every edge renders
    -- the same whole-pixel thickness (unsnapped SetHeight/SetWidth lets some
    -- sides round thicker than others at fractional effective scale).
    local Pix = CludesUI.PP
    -- A degenerate scale chain (0 while layout is unresolved, or the
    -- SetScale(0.001) hide path) makes onePixel enormous, which collapses the
    -- snap below to w = h = 0 and turns the k divide into N/0. Every phase
    -- endpoint then goes non-finite and SetTexCoord rejects it on every driver
    -- tick. Stay unresolved instead and retry once the scale is real.
    local es = self:GetEffectiveScale()
    -- Same subtree class the GetSize taint-strip above exists for: a secret
    -- effective scale would hard-error on the comparison below, so take the
    -- retry path instead. No-op for normal values.
    if not es or (issecretvalue and issecretvalue(es)) or es < 0.1 then
        return false
    end
    local onePixel = Pix.perfect / es
    wid = floor(wid / onePixel + 0.5) * onePixel
    hgt = floor(hgt / onePixel + 0.5) * onePixel
    -- A genuinely sub-pixel wrapper passes the size test above but snaps to 0;
    -- floor both dimensions at one pixel so (w + h) is always a real divisor.
    if wid < onePixel then
        wid = onePixel
    end
    if hgt < onePixel then
        hgt = onePixel
    end
    -- Total sanity gate before anything is cached. An infinite onePixel (a
    -- bogus PP.physicalHeight makes PP.perfect infinite) snaps w and h to NaN,
    -- which slips past every comparison above and then poisons the k divide
    -- below. NaN and inf both fail this test, so the phase endpoints are always
    -- real numbers and SetTexCoord can never be handed a value it rejects.
    if not (wid > 0 and hgt > 0 and wid + hgt < math.huge) then
        return false
    end
    local sTh = floor(glowData.th / onePixel + 0.5) * onePixel
    if sTh < onePixel then
        sTh = onePixel
    end
    glowData.top:SetHeight(sTh)
    glowData.bottom:SetHeight(sTh)
    glowData.left:SetWidth(sTh)
    glowData.right:SetWidth(sTh)
    glowData.w = wid
    glowData.h = hgt
    -- Precompute the per-edge phase endpoints; they are invariant until the
    -- next resize/restart, so only the scroll offset o changes per tick.
    -- ph(P) = P * N / perim is the perimeter position in dash-period units;
    -- the four edges share it so dashes stay continuous around every corner.
    local k = glowData.N / (2 * (wid + hgt))
    glowData.wk = wid * k
    glowData.whk = (wid + hgt) * k
    glowData.wwhk = (2 * wid + hgt) * k
    return true
end

local function _AntsOnUpdate(self, timePassed)
    local glowData = self._cuiScrollData
    if not glowData then
        return
    end
    glowData.timer = glowData.timer + timePassed
    if glowData.timer >= glowData.period then
        glowData.timer = glowData.timer - glowData.period
    end
    -- Positive-test rather than == 0 so a non-finite cached size fails it too
    -- and re-resolves, instead of feeding bad texcoords in forever.
    if not (glowData.w > 0 and glowData.h > 0) then
        if not _AntsResolveSize(self, glowData) then
            return
        end
    end
    local N = glowData.N
    local o = (glowData.timer / glowData.period) * N -- scroll offset (N integer -> seamless wrap)
    -- Direction is clockwise; the bottom/left edges flip their coords to match.
    local wk, whk, wwhk = glowData.wk, glowData.whk, glowData.wwhk
    glowData.top:SetTexCoord(-o, wk - o, 0, 1)
    glowData.right:SetTexCoord(0, 1, wk - o, whk - o)
    glowData.bottom:SetTexCoord(wwhk - o, whk - o, 0, 1)
    glowData.left:SetTexCoord(0, 1, N - o, wwhk - o)
end

-- Static (non-marching) dashes: draw once at the frozen base phase (scroll
-- offset 0). These are exactly the animated coords evaluated at o = 0, so the
-- dashes stay corner-continuous -- a dashed border rather than marching ants.
local function _AntsDrawStatic(self, glowData)
    local N = glowData.N
    local wk, whk, wwhk = glowData.wk, glowData.whk, glowData.wwhk
    glowData.top:SetTexCoord(0, wk, 0, 1)
    glowData.right:SetTexCoord(0, 1, wk, whk)
    glowData.bottom:SetTexCoord(wwhk, whk, 0, 1)
    glowData.left:SetTexCoord(0, 1, N, wwhk)
end

-- One-shot settler for static mode when the size was not resolved at Start time
-- (SetAllPoints wrappers can read 0 before layout resolves). Resolves, draws
-- once, then unregisters so a static border costs nothing per frame thereafter.
local function _AntsStaticSettle(self, timePassed)
    local glowData = self._cuiScrollData
    if not glowData then
        _Unregister(self, "ants")
        return
    end
    if not (glowData.w > 0 and glowData.h > 0) then
        if not _AntsResolveSize(self, glowData) then
            return
        end
    end
    _AntsDrawStatic(self, glowData)
    _Unregister(self, "ants")
end

-- lineLen is accepted for call-signature compatibility but unused: the dash
-- length is the texture's duty cycle, not a runtime segment length.
local function StartProceduralAnts(
    holder,
    N,
    th,
    period,
    lineLen,
    cornerR,
    cornerG,
    cornerB,
    szOrW,
    szH,
    bgR,
    bgG,
    bgB,
    bgA,
    static
)
    if not holder._cuiScrollData then
        local function mk(p1, p1f, p2, p2f)
            local t = holder:CreateTexture(nil, "OVERLAY", nil, 7)
            t:SetPoint(p1, holder, p1f)
            t:SetPoint(p2, holder, p2f)
            return t
        end
        holder._cuiScrollData = {
            top = mk("TOPLEFT", "TOPLEFT", "TOPRIGHT", "TOPRIGHT"),
            bottom = mk("BOTTOMLEFT", "BOTTOMLEFT", "BOTTOMRIGHT", "BOTTOMRIGHT"),
            left = mk("TOPLEFT", "TOPLEFT", "BOTTOMLEFT", "BOTTOMLEFT"),
            right = mk("TOPRIGHT", "TOPRIGHT", "BOTTOMRIGHT", "BOTTOMRIGHT"),
            timer = 0,
            w = 0,
            h = 0,
        }
    end
    local glowData = holder._cuiScrollData
    glowData.N = (N and N > 0) and N or 8
    glowData.period = period or 4
    glowData.w = 0
    glowData.h = 0
    glowData.fallbackW = szOrW or 0
    glowData.fallbackH = szH or szOrW or 0
    th = th or 2
    glowData.th = th
    glowData.top:SetTexture(DASH_H, "REPEAT", "REPEAT")
    glowData.top:SetHeight(th)
    glowData.bottom:SetTexture(DASH_H, "REPEAT", "REPEAT")
    glowData.bottom:SetHeight(th)
    glowData.left:SetTexture(DASH_V, "REPEAT", "REPEAT")
    glowData.left:SetWidth(th)
    glowData.right:SetTexture(DASH_V, "REPEAT", "REPEAT")
    glowData.right:SetWidth(th)
    -- bgR being non-nil is the "background on" signal; callers pass nil to
    -- disable. Do NOT change this to `bgR > 0`: a fully black background is
    -- r=0, which is a valid enabled color and must still draw.
    if bgR then
        if not glowData.bgTop then
            local function mkBg(p1, p1f, p2, p2f)
                local t = holder:CreateTexture(nil, "OVERLAY", nil, 6)
                t:SetPoint(p1, holder, p1f)
                t:SetPoint(p2, holder, p2f)
                return t
            end
            glowData.bgTop = mkBg("TOPLEFT", "TOPLEFT", "TOPRIGHT", "TOPRIGHT")
            glowData.bgBottom = mkBg("BOTTOMLEFT", "BOTTOMLEFT", "BOTTOMRIGHT", "BOTTOMRIGHT")
            glowData.bgLeft = mkBg("TOPLEFT", "TOPLEFT", "BOTTOMLEFT", "BOTTOMLEFT")
            glowData.bgRight = mkBg("TOPRIGHT", "TOPRIGHT", "BOTTOMRIGHT", "BOTTOMRIGHT")
        end
        bgA = bgA or 1
        glowData.bgTop:SetHeight(th)
        glowData.bgBottom:SetHeight(th)
        glowData.bgLeft:SetWidth(th)
        glowData.bgRight:SetWidth(th)
        glowData.bgTop:SetColorTexture(bgR, bgG or 0, bgB or 0, bgA)
        glowData.bgTop:Show()
        glowData.bgBottom:SetColorTexture(bgR, bgG or 0, bgB or 0, bgA)
        glowData.bgBottom:Show()
        glowData.bgLeft:SetColorTexture(bgR, bgG or 0, bgB or 0, bgA)
        glowData.bgLeft:Show()
        glowData.bgRight:SetColorTexture(bgR, bgG or 0, bgB or 0, bgA)
        glowData.bgRight:Show()
    elseif glowData.bgTop then
        glowData.bgTop:Hide()
        glowData.bgBottom:Hide()
        glowData.bgLeft:Hide()
        glowData.bgRight:Hide()
    end
    glowData.top:SetVertexColor(cornerR, cornerG, cornerB, 1)
    glowData.top:Show()
    glowData.bottom:SetVertexColor(cornerR, cornerG, cornerB, 1)
    glowData.bottom:Show()
    glowData.left:SetVertexColor(cornerR, cornerG, cornerB, 1)
    glowData.left:Show()
    glowData.right:SetVertexColor(cornerR, cornerG, cornerB, 1)
    glowData.right:Show()
    if static then
        -- Frozen dashes: draw once now (size permitting) and stay off the
        -- animation driver. If layout has not resolved yet, a one-shot settler
        -- draws on the first tick that reads a real size, then unregisters.
        if _AntsResolveSize(holder, glowData) then
            _AntsDrawStatic(holder, glowData)
            _Unregister(holder, "ants") -- clear any prior animated registration
        else
            _Register(holder, _AntsStaticSettle, "ants")
        end
    else
        _Register(holder, _AntsOnUpdate, "ants")
    end
end

local function StopProceduralAnts(holder)
    _Unregister(holder, "ants")
    local glowData = holder._cuiScrollData
    if glowData then
        glowData.top:Hide()
        glowData.bottom:Hide()
        glowData.left:Hide()
        glowData.right:Hide()
        if glowData.bgTop then
            glowData.bgTop:Hide()
            glowData.bgBottom:Hide()
            glowData.bgLeft:Hide()
            glowData.bgRight:Hide()
        end
    end
end

-- Recolor active dashes in place. Secret-safe: r,g,b,a flow straight into
-- SetVertexColor with no arithmetic, so a secret (restricted) color is fine.
-- Used by the Raid Frames Frame-Border threshold recolor.
local function SetProceduralAntsColor(holder, r, g, b, a)
    local glowData = holder._cuiScrollData
    if not glowData then
        return
    end
    a = a or 1
    glowData.top:SetVertexColor(r, g, b, a)
    glowData.bottom:SetVertexColor(r, g, b, a)
    glowData.left:SetVertexColor(r, g, b, a)
    glowData.right:SetVertexColor(r, g, b, a)
end

-------------------------------------------------------------------------------
--  Action Button Glow Engine
--  Outer glow (soft border from IconAlert) + animated marching ants.
-------------------------------------------------------------------------------
-- Marching-ants sprite cycler. Replaces a Blizzard SharedXML global that was
-- removed in 12.0 (present on live, nil on the PTR -> the glow OnUpdate erroring
-- out). Framerate-independent: it advances by however many cells the elapsed
-- time covers and carries the remainder, so the march speed is identical whether
-- the glow driver ticks at 60fps or faster, and it does not inherit the original
-- global's framerate-dependent quirks. ANTS_FRAME_TIME (seconds per cell) is the
-- single knob for the speed. State lives on our own ants texture.
local ANTS_FRAME_TIME = 0.017 -- ~59 cells/sec -> ~0.37s per 22-frame loop
local function _AnimateTexCoords(texture, sheetW, sheetH, cellW, cellH, numFrames, timePassed)
    if not texture._cuiAnimCols then
        texture._cuiAnimCols = floor(sheetW / cellW)
        texture._cuiAnimColW = cellW / sheetW
        texture._cuiAnimRowH = cellH / sheetH
        texture._cuiAnimFrame = 0
        texture._cuiAnimAccum = 0
    end
    texture._cuiAnimAccum = texture._cuiAnimAccum + timePassed
    if texture._cuiAnimAccum < ANTS_FRAME_TIME then
        return
    end

    local advance = floor(texture._cuiAnimAccum / ANTS_FRAME_TIME)
    texture._cuiAnimAccum = texture._cuiAnimAccum - advance * ANTS_FRAME_TIME
    local widget = (texture._cuiAnimFrame + advance) % numFrames
    texture._cuiAnimFrame = widget

    local cols = texture._cuiAnimCols
    local colW = texture._cuiAnimColW
    local rowH = texture._cuiAnimRowH
    local leftX = (widget % cols) * colW
    local topY = floor(widget / cols) * rowH
    texture:SetTexCoord(leftX, leftX + colW, topY, topY + rowH)
end

local function _ButtonGlowOnUpdate(self, timePassed)
    local glowData = self._cuiBgData
    if not glowData then
        return
    end
    _AnimateTexCoords(glowData.ants, 256, 256, 48, 48, 22, timePassed)
end

local function StartButtonGlow(holder, szOrW, cornerR, cornerG, cornerB, scale, szH)
    scale = scale or 1.0
    local wid = szOrW or 36
    local hgt = szH or wid
    if not holder._cuiBgData then
        local glowFrame = holder:CreateTexture(nil, "OVERLAY", nil, 7)
        glowFrame:SetTexture(ICON_ALERT_TEX)
        glowFrame:SetTexCoord(BG_GLOW_L, BG_GLOW_R, BG_GLOW_T, BG_GLOW_B)
        glowFrame:SetBlendMode("ADD")
        glowFrame:SetPoint("CENTER")
        local ants = holder:CreateTexture(nil, "OVERLAY", nil, 7)
        ants:SetTexture(ANTS_TEX)
        ants:SetBlendMode("ADD")
        ants:SetPoint("CENTER")
        holder._cuiBgData = { glow = glowFrame, ants = ants }
    end
    local glowData = holder._cuiBgData
    -- The ants texture has transparent padding baked into its frames,
    -- so we scale up to compensate and match the button edge visually.
    local antsW, antsH = wid * 1.35, hgt * 1.35
    local glowW, glowH = antsW * 1.3, antsH * 1.3
    glowData.glow:SetSize(glowW, glowH)
    glowData.glow:SetDesaturated(true)
    glowData.glow:SetVertexColor(cornerR, cornerG, cornerB, 1)
    glowData.glow:SetAlpha(1)
    glowData.glow:Show()
    glowData.ants:SetSize(antsW, antsH)
    glowData.ants:SetDesaturated(true)
    glowData.ants:SetVertexColor(cornerR, cornerG, cornerB, 1)
    glowData.ants:SetAlpha(1)
    glowData.ants:Show()
    _Register(holder, _ButtonGlowOnUpdate, "button")
end

local function StopButtonGlow(holder)
    _Unregister(holder, "button")
    if holder._cuiBgData then
        holder._cuiBgData.ants:Hide()
        holder._cuiBgData.glow:Hide()
    end
end

-------------------------------------------------------------------------------
--  Auto-Cast Shine Engine
--  4 layers of sparkle dots orbit the perimeter at staggered speeds.
--  Each layer has dotsPerLayer dots evenly spaced. Layer k orbits k times
--  slower than layer 1, creating a cascading sparkle effect.
-------------------------------------------------------------------------------

-- Compute x,y offset from TOPLEFT for a point at distance `dist`
-- around the perimeter (clockwise from top-left corner).
local function _OrbitXY(dist, wid, hgt)
    if dist < wid then
        return dist, 0
    end
    dist = dist - wid
    if dist < hgt then
        return wid, -dist
    end
    dist = dist - hgt
    if dist < wid then
        return wid - dist, -hgt
    end
    return 0, -(hgt - (dist - wid))
end

local function _AutoCastOnUpdate(self, timePassed)
    local glowData = self._cuiAcData
    if not glowData then
        return
    end
    local layerPhase = glowData.layerPhase
    local basePeriod = glowData.period
    for layer = 1, 4 do
        layerPhase[layer] = layerPhase[layer] + timePassed / (basePeriod * layer)
        if layerPhase[layer] > 1 then
            layerPhase[layer] = layerPhase[layer] - 1
        end
    end
    glowData._accum = (glowData._accum or 0) + timePassed
    if glowData._accum < 0.016 then
        return
    end
    glowData._accum = 0
    local wid, hgt = glowData.w, glowData.h
    if wid * hgt == 0 then
        wid, hgt = self:GetSize()
        -- A secret size never reaches tostring or arithmetic: it takes the
        -- start-time fallback below. Plain sizes keep the taint strip.
        if issecretvalue(wid) or issecretvalue(hgt) then
            wid, hgt = 0, 0
        else
            wid = tonumber(tostring(wid)) or 0
            hgt = tonumber(tostring(hgt)) or 0
        end
        -- Fallback to the w/h passed at start time (SetAllPoints wrappers
        -- may return 0 before layout resolves)
        if wid * hgt == 0 and glowData.fallbackW and glowData.fallbackW > 0 then
            wid = glowData.fallbackW
            hgt = glowData.fallbackH or glowData.fallbackW
        end
        if wid * hgt == 0 then
            return
        end
        glowData.w = wid
        glowData.h = hgt
        glowData.perim = 2 * (wid + hgt)
        glowData.spacing = glowData.perim / glowData.dotsPerLayer
    end
    local perim = glowData.perim
    local spacing = glowData.spacing
    local sparkles = glowData.sparkles
    local dotsPerLayer = glowData.dotsPerLayer
    local position = 0
    for layer = 1, 4 do
        local phase = layerPhase[layer] * perim
        for i = 1, dotsPerLayer do
            position = position + 1
            local dist = (spacing * i + phase) % perim
            local px, py = _OrbitXY(dist, wid, hgt)
            local dot = sparkles[position]
            dot:ClearAllPoints()
            dot:SetPoint("CENTER", self, "TOPLEFT", px, py)
        end
    end
end

local function StartAutoCastShine(holder, szOrW, cornerR, cornerG, cornerB, scale, szH)
    scale = scale or 1.0
    local dotsPerLayer = 4
    local totalDots = dotsPerLayer * 4
    if not holder._cuiAcData then
        holder._cuiAcData = {
            sparkles = {},
            layerPhase = { 0, 0.25, 0.5, 0.75 },
            dotsPerLayer = dotsPerLayer,
            period = 2,
            w = 0,
            h = 0,
        }
    end
    local glowData = holder._cuiAcData
    glowData.dotsPerLayer = dotsPerLayer
    glowData.layerPhase[1] = 0
    glowData.layerPhase[2] = 0.25
    glowData.layerPhase[3] = 0.5
    glowData.layerPhase[4] = 0.75
    for position = 1, totalDots do
        if not glowData.sparkles[position] then
            local dot = holder:CreateTexture(nil, "OVERLAY", nil, 7)
            dot:SetTexture(SHINE_TEX)
            dot:SetTexCoord(SHINE_COORDS[1], SHINE_COORDS[2], SHINE_COORDS[3], SHINE_COORDS[4])
            dot:SetDesaturated(true)
            dot:SetBlendMode("ADD")
            glowData.sparkles[position] = dot
        end
        local layer = ceil(position / dotsPerLayer)
        local baseSz = (SPARKLE_LAYER_SIZES[layer] or 4) * scale
        glowData.sparkles[position]:SetSize(baseSz, baseSz)
        glowData.sparkles[position]:SetVertexColor(cornerR, cornerG, cornerB, 1)
        glowData.sparkles[position]:Show()
    end
    for position = totalDots + 1, #glowData.sparkles do
        glowData.sparkles[position]:Hide()
    end
    glowData.w = 0
    glowData.h = 0
    glowData.fallbackW = szOrW or 0
    glowData.fallbackH = szH or szOrW or 0
    _Register(holder, _AutoCastOnUpdate, "autocast")
end

local function StopAutoCastShine(holder)
    _Unregister(holder, "autocast")
    if holder._cuiAcData then
        for _, dot in ipairs(holder._cuiAcData.sparkles) do
            dot:Hide()
        end
    end
end

-------------------------------------------------------------------------------
--  Shape Glow Engine
--  Pulsing additive glow using the icon's shape mask texture.
--  Used by ActionBars (custom shapes) and CDM (custom icon shapes).
--  opts.maskPath   — path to the shape mask texture
--  opts.borderPath — path to the shape border texture
--  opts.shapeMask  — MaskTexture object for AddMaskTexture
-------------------------------------------------------------------------------
local function _ShapeGlowOnUpdate(self, timePassed)
    local glowData = self._cuiSgData
    if not glowData then
        return
    end
    local timer = glowData.timer + timePassed * glowData.speed
    if timer > 6.2832 then
        timer = timer - 6.2832
    end
    glowData.timer = timer
    glowData.glow:SetAlpha(0.25 + 0.25 * (0.5 + 0.5 * sin(timer)))
    local bright = glowData.bright
    if bright then
        local bTimer = (glowData.bTimer or 0) + timePassed * glowData.speed * 0.50
        if bTimer > 6.2832 then
            bTimer = bTimer - 6.2832
        end
        glowData.bTimer = bTimer
        bright:SetAlpha(0.35 + 0.10 * (0.5 + 0.5 * sin(bTimer)))
    end
end

local function StartShapeGlow(holder, sz, cornerR, cornerG, cornerB, scale, options)
    scale = scale or 1.20
    options = options or {}
    -- anchorFrame overrides GetParent() for cases where the wrapper is
    -- parented to a different frame (e.g. action bar wrappers use
    -- btn:GetParent() to escape mask clipping).
    local btn = options.anchorFrame or holder:GetParent()
    if not btn then
        return
    end
    if not holder._cuiSgData then
        local glowFrame = btn:CreateTexture(nil, "OVERLAY", nil, 5)
        glowFrame:SetBlendMode("ADD")
        local edge = btn:CreateTexture(nil, "OVERLAY", nil, 5)
        edge:SetBlendMode("ADD")
        local bright = btn:CreateTexture(nil, "OVERLAY", nil, 7)
        bright:SetBlendMode("ADD")
        holder._cuiSgData = { glow = glowFrame, edge = edge, bright = bright, timer = 0, speed = 10.0 }
    end
    local glowData = holder._cuiSgData
    glowData.timer = 0

    -- Glow extends slightly past the button edge for the pulsing effect
    local extend = sz * 0.10
    glowData.glow:ClearAllPoints()
    glowData.glow:SetPoint("TOPLEFT", btn, "TOPLEFT", -extend, extend)
    glowData.glow:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", extend, -extend)
    local maskPath = options.maskPath
    local borderPath = options.borderPath
    if maskPath then
        glowData.glow:SetTexture(maskPath, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    else
        glowData.glow:SetColorTexture(1, 1, 1, 1)
    end
    glowData.glow:SetVertexColor(cornerR, cornerG, cornerB, 1)
    glowData.glow:SetAlpha(1)
    glowData.glow:Show()

    -- Edge: not used (created an ugly inset inner border ring)
    glowData.edge:Hide()

    -- Bright border overlay
    glowData.bright:ClearAllPoints()
    glowData.bright:SetAllPoints(btn)
    if borderPath then
        glowData.bright:SetTexture(borderPath)
    else
        glowData.bright:SetColorTexture(0, 0, 0, 0)
    end
    glowData.bright:SetVertexColor(cornerR, cornerG, cornerB, 1)
    glowData.bright:SetAlpha(0.5)
    glowData.bright:Show()

    -- Mask the pulsing glow with the shape mask texture
    local shapeMask = options.shapeMask
    if shapeMask then
        pcall(glowData.glow.RemoveMaskTexture, glowData.glow, shapeMask)
        pcall(glowData.glow.AddMaskTexture, glowData.glow, shapeMask)
    end
    _Register(holder, _ShapeGlowOnUpdate, "shape")
end

local function StopShapeGlow(holder)
    _Unregister(holder, "shape")
    if holder._cuiSgData then
        holder._cuiSgData.glow:Hide()
        holder._cuiSgData.edge:Hide()
        holder._cuiSgData.bright:Hide()
    end
end

-------------------------------------------------------------------------------
--  FlipBook Glow Engine
--  Handles atlas-based and raw-texture FlipBook animations (GCD, Modern WoW
--  Glow, Classic WoW Glow, and any future FlipBook styles).
-------------------------------------------------------------------------------
-- Region creation only: the texture with its looping FlipBook group, plus on
-- request the atlas ants overlay (ants) and ABG's soft halo (halo), all
-- hidden. Shared with PrewarmEngineHost, which creates without configuring.
-- Each part's field appears only once its regions exist.
local function _EnsureFlip(holder, ants, halo)
    local glowData = holder._cuiFlipData
    if not glowData then
        local texture = holder:CreateTexture(nil, "OVERLAY", nil, 7)
        texture:SetPoint("CENTER")
        texture:Hide()
        local ag = texture:CreateAnimationGroup()
        ag:SetLooping("REPEAT")
        local anim = ag:CreateAnimation("FlipBook")
        glowData = { tex = texture, ag = ag, anim = anim }
        holder._cuiFlipData = glowData
    end
    if ants and not glowData.ants then
        local aTex = holder:CreateTexture(nil, "OVERLAY", nil, 7)
        aTex:SetPoint("CENTER")
        aTex:SetBlendMode("ADD")
        aTex:Hide()
        local aAg = aTex:CreateAnimationGroup()
        aAg:SetLooping("REPEAT")
        glowData.antsAnim = aAg:CreateAnimation("FlipBook")
        glowData.antsAg = aAg
        glowData.ants = aTex
    end
    if halo and not glowData.halo then
        local haloTex = holder:CreateTexture(nil, "OVERLAY", nil, 6)
        haloTex:SetTexture(ICON_ALERT_TEX)
        haloTex:SetTexCoord(BG_GLOW_L, BG_GLOW_R, BG_GLOW_T, BG_GLOW_B)
        haloTex:SetBlendMode("ADD")
        haloTex:SetPoint("CENTER")
        haloTex:Hide()
        glowData.halo = haloTex
    end
    return glowData
end

local function StartFlipBookGlow(holder, szOrW, record, cornerR, cornerG, cornerB, szH, options)
    -- FlipBook frames have transparent padding baked in. Each atlas
    -- has a different amount, so the style entry carries a texPadding
    -- multiplier (defaults to 1 = no compensation).
    local wid = szOrW or 36
    local hgt = szH or wid
    local texW = wid * (record.texPadding or 1)
    local texH = hgt * (record.texPadding or 1)

    local glowData = _EnsureFlip(holder, record.atlas ~= nil, options and options.abgHalo)
    glowData.tex:SetSize(texW, texH)
    if record.atlas then
        glowData.tex:SetAtlas(record.atlas)
    elseif record.texture then
        glowData.tex:SetTexture(record.texture)
    end
    if cornerR then
        glowData.tex:SetDesaturated(true)
        glowData.tex:SetVertexColor(cornerR, cornerG, cornerB)
    else
        -- no color requested - just show atlas untinted
        glowData.tex:SetDesaturated(false)
        glowData.tex:SetVertexColor(1, 1, 1)
    end
    glowData.tex:Show()
    glowData.anim:SetFlipBookRows(record.rows or 6)
    glowData.anim:SetFlipBookColumns(record.columns or 5)
    glowData.anim:SetFlipBookFrames(record.frames or 30)
    glowData.anim:SetDuration(record.duration or 1.0)
    glowData.anim:SetFlipBookFrameWidth(record.frameW or 0)
    glowData.anim:SetFlipBookFrameHeight(record.frameH or 0)
    -- Restart. Never asked through IsPlaying: once a bound host's group is
    -- registered with its aura button, querying its progress throws.
    glowData.ag:Stop()
    glowData.ag:Play()

    -- Ants overlay: a non-desaturated duplicate at low alpha for atlas styles
    if record.atlas then
        glowData.ants:SetSize(texW, texH)
        glowData.ants:SetAtlas(record.atlas)
        glowData.ants:SetDesaturated(false)
        glowData.ants:SetVertexColor(1, 1, 1)
        glowData.ants:SetAlpha(0.35)
        glowData.antsAnim:SetFlipBookRows(record.rows or 6)
        glowData.antsAnim:SetFlipBookColumns(record.columns or 5)
        glowData.antsAnim:SetFlipBookFrames(record.frames or 30)
        glowData.antsAnim:SetDuration(record.duration or 1.0)
        glowData.antsAnim:SetFlipBookFrameWidth(record.frameW or 0)
        glowData.antsAnim:SetFlipBookFrameHeight(record.frameH or 0)
        glowData.ants:Show()
        glowData.antsAg:Stop()
        glowData.antsAg:Play()
    elseif glowData.ants then
        glowData.ants:Hide()
        if glowData.antsAg then
            glowData.antsAg:Stop()
        end
    end

    -- Soft outer halo: matches the halo StartButtonGlow draws behind its ants.
    -- Keyed on the CALL (opts.abgHalo -- set only by StartEngineGlow's Action
    -- Button Glow substitution), never on the shared style entry: a direct
    -- Classic WoW Glow pick and the RestrictionSafeStyle Pixel remap keep
    -- their own bare-ants look, while the ABG stand-in matches the real
    -- thing instead of rendering visibly thinner.
    if options and options.abgHalo then
        glowData.halo:SetSize(texW * 1.3, texH * 1.3)
        glowData.halo:SetDesaturated(true)
        -- The halo carries the glow color (the ants stay white); no color
        -- chosen = the suite's canonical gold, the same default
        -- StartNativeGlow feeds tinted styles.
        glowData.halo:SetVertexColor(options.haloR or 1.0, options.haloG or 0.788, options.haloB or 0.137, 1)
        glowData.halo:Show()
    elseif glowData.halo then
        glowData.halo:Hide()
    end

    -- The scrub is pointless on a bound host, whose wrapper never had a script.
    if not BOUND[holder] then
        holder:SetScript("OnUpdate", nil)
    end
end

local function StopFlipBookGlow(holder)
    if holder._cuiFlipData then
        holder._cuiFlipData.tex:Hide()
        if holder._cuiFlipData.ag then
            holder._cuiFlipData.ag:Stop()
        end
        if holder._cuiFlipData.ants then
            holder._cuiFlipData.ants:Hide()
        end
        if holder._cuiFlipData.antsAg then
            holder._cuiFlipData.antsAg:Stop()
        end
        if holder._cuiFlipData.halo then
            holder._cuiFlipData.halo:Hide()
        end
    end
end

-------------------------------------------------------------------------------
--  Solid Fill Engine (Blackout)
--  One colour texture covering the wrapper at a caller-chosen alpha (opaque
--  by default), so the icon can be fully hidden or only partially obscured.
--  Static: no driver tick and no AnimationGroup, so it costs nothing per
--  frame. The texture is created on the first start and PrewarmEngineHost has
--  no fill family, so this is not an engine-host style.
-------------------------------------------------------------------------------
local function StartSolidFill(holder, cornerR, cornerG, cornerB, options)
    options = options or {}
    if not holder._cuiFillData then
        local texture = holder:CreateTexture(nil, "OVERLAY", nil, 7)
        texture:SetAllPoints(holder)
        holder._cuiFillData = { tex = texture }
    end
    local glowData = holder._cuiFillData
    glowData.tex:SetColorTexture(cornerR or 0, cornerG or 0, cornerB or 0, options.alpha or 1)
    glowData.tex:SetAlpha(1)
    -- Shape-masked icons: clip the fill to the icon silhouette so it cannot
    -- spill past a rounded/circular border.
    local shapeMask = options.shapeMask
    if glowData.mask ~= shapeMask then
        if glowData.mask then
            pcall(glowData.tex.RemoveMaskTexture, glowData.tex, glowData.mask)
        end
        if shapeMask then
            pcall(glowData.tex.AddMaskTexture, glowData.tex, shapeMask)
        end
        glowData.mask = shapeMask
    end
    glowData.tex:Show()
end

local function StopSolidFill(holder)
    if holder._cuiFillData then
        holder._cuiFillData.tex:Hide()
    end
end

-- Defined above StopAllGlows so engine-hosted ants (StartEngineGlow /
-- StartAnimatedAnts) tear down through the same unified stop path.
local function StopAnimatedAnts(holder)
    local glowData = holder._cuiAnimAnts
    if not glowData then
        return
    end
    for i = 1, 4 do
        glowData.groups[i]:Stop()
        glowData.strips[i]:Hide()
        if glowData.bgs and glowData.bgs[i] then
            glowData.bgs[i]:Hide()
        end
    end
end

-------------------------------------------------------------------------------
--  StopAllGlows — clears any active glow engine on a wrapper frame
-------------------------------------------------------------------------------
local function StopAllGlows(holder)
    if not holder then
        return
    end
    StopProceduralAnts(holder)
    StopButtonGlow(holder)
    StopAutoCastShine(holder)
    StopShapeGlow(holder)
    StopFlipBookGlow(holder)
    StopSolidFill(holder)
    StopAnimatedAnts(holder)
    -- Blizzard Border (CludesUI.Glows.STEALABLE_BORDER) and Blizzard
    -- Pandemic Border (PANDEMIC_BORDER) are static textures on the same hosts;
    -- a stop clears them too.
    local steal = holder._cuiStealTex
    if steal then
        steal:Hide()
    end
    local pan = holder._cuiPanTex
    if pan then
        pan:Hide()
    end
    -- StartSpecGlow's change signature describes a glow that is now gone.
    local sig = holder._cuiSpecSig
    if sig then
        sig.idx = nil
    end
    -- Defensive scrub: the central driver owns the only OnUpdate now, so the
    -- five Stop* calls above already unregistered this wrapper from the driver.
    -- This clears any stale OnUpdate a pre-migration build may have left on the
    -- wrapper itself (harmless on our own frame; never touches the driver).
    -- A bound host (G.BindEngineHost) never had one. Its groups stay
    -- registered here: StopGlow hands them back, a restart re-plays them.
    if not BOUND[holder] then
        holder:SetScript("OnUpdate", nil)
    end
end

-------------------------------------------------------------------------------
--  ApplyMaskWith -- bound every texture a glow engine created on a wrapper
--  with the caller's MaskTexture (caller supplies CLAMPTOBLACKADDITIVE wrap).
--  Every glow engine creates its textures directly on the wrapper, so the
--  region list is the complete set. Used by threshold-gated glows: the mask
--  tracks a gate StatusBar's fill rect, so a C-side value comparison decides
--  visibility without the value ever crossing into Lua. Masks keep rendering
--  where a SetClipsChildren bound goes dark on secret-derived rects in
--  restricted content. Dedicated wrappers only: the mask is never removed.
-------------------------------------------------------------------------------
local function ApplyMaskWith(holder, maskTex)
    if not (holder and maskTex) then
        return
    end
    for _, r in ipairs({ holder:GetRegions() }) do
        if r.AddMaskTexture and r._cuiTGMask ~= maskTex then
            r._cuiTGMask = maskTex
            r:AddMaskTexture(maskTex)
        end
    end
end

-------------------------------------------------------------------------------
--  StartGlow — unified entry point
--  wrapper  : Frame to render the glow on
--  styleIdx : index into GLOW_STYLES (1-based)
--  sz       : icon/frame size in pixels
--  cr,cg,cb : glow color (0-1)
--  opts     : optional table with overrides:
--    .scale       — override entry.scale
--    .N, .th, .period, .bg — pixel glow tuning/background
--    .maskPath, .borderPath, .shapeMask — shape glow textures
--    .untinted    -- a nil color stays nil on the FlipBook path (the atlas's
--                   own untinted look) instead of desaturated white
--    .alpha       -- Blackout fill opacity (0-1, default 1 = opaque)
-------------------------------------------------------------------------------
local function StartGlow(holder, styleIdx, szOrW, cornerR, cornerG, cornerB, options, szH)
    if not holder then
        return
    end
    styleIdx = tonumber(styleIdx) or 1
    if styleIdx < 1 or styleIdx > #GLOW_STYLES then
        styleIdx = 1
    end
    local record = GLOW_STYLES[styleIdx]
    options = options or {}
    local wid = szOrW or 36
    local hgt = szH or wid
    -- An unspecified colour means black for Blackout (its default look), not
    -- the white every other style falls back to below.
    local noColor = (cornerR == nil)
    local keepUntinted = options.untinted and cornerR == nil
    cornerR = cornerR or 1
    cornerG = cornerG or 1
    cornerB = cornerB or 1

    -- Stop any previous glow
    StopAllGlows(holder)

    if record.procedural then
        local N = options.N or 8
        local th = options.th or 2
        local period = options.period or 4
        local lineLen = floor((wid + hgt) * (2 / N - 0.1))
        lineLen = min(lineLen, min(wid, hgt))
        if lineLen < 1 then
            lineLen = 1
        end
        local backdrop = options.bg
        StartProceduralAnts(
            holder,
            N,
            th,
            period,
            lineLen,
            cornerR,
            cornerG,
            cornerB,
            wid,
            hgt,
            backdrop and (backdrop.r or 0) or nil,
            backdrop and (backdrop.g or 0) or nil,
            backdrop and (backdrop.b or 0) or nil,
            backdrop and (backdrop.a or 1) or nil
        )
    elseif record.buttonGlow then
        StartButtonGlow(holder, wid, cornerR, cornerG, cornerB, nil, hgt)
    elseif record.autocast then
        StartAutoCastShine(holder, wid, cornerR, cornerG, cornerB, 1.0, hgt)
    elseif record.shapeGlow then
        StartShapeGlow(holder, wid, cornerR, cornerG, cornerB, 1.20, options)
    elseif record.solidFill then
        StartSolidFill(holder, noColor and 0 or cornerR, noColor and 0 or cornerG, noColor and 0 or cornerB, options)
    else
        -- FlipBook mode (GCD, Modern WoW Glow, Classic WoW Glow, etc.)
        if keepUntinted then
            StartFlipBookGlow(holder, wid, record, nil, nil, nil, hgt, options)
        else
            StartFlipBookGlow(holder, wid, record, cornerR, cornerG, cornerB, hgt, options)
        end
    end

    if options.maskWith then
        ApplyMaskWith(holder, options.maskWith)
    end

    holder._cuiGlowActive = true
    holder:SetAlpha(1)
    -- No Show() — wrapper should already be shown. Toggling visibility
    -- on children of Blizzard viewer frames triggers Layout cascades.
end

-------------------------------------------------------------------------------
--  Bound engine hosts (12.1.5): the aura button runs the host's animations.
--  A group handed to the button's AddAuraShownAnimation is played by Blizzard
--  when the button starts showing an aura and stopped whenever it has none,
--  so a glow on a hidden pooled button costs nothing. Our engines still
--  configure the host exactly as before; a bound host then registers only
--  the groups the drawn style plays (Blizzard plays every registered group on
--  each show) and, after a change outside the button's creation window, has
--  the button re-run its own visibility (the kick, AuraKit's
--  KickShownAnimations), because a button's shown state is secret: our code
--  can never tell a hidden button from a shown one. The registrations and
--  their stamps live in AuraKit (the button's weak bd entry). While auras are
--  restricted the button subtree refuses every call from our code outside
--  the creation window: such a start or stop is skipped, its change
--  signature left unset, and the button's style key re-runs at the lift.
--  Unbound wrappers (previews, Mythic Timer, cast bars, Action Bars, CDM)
--  are untouched by all of this.
-------------------------------------------------------------------------------

-- The groups the style drawn for shared index idx plays on wrapper, written to
-- out[1..n] (the rest of out cleared); returns n. Mirrors StartEngineGlow's
-- routing: Pixel (and Blackout or an unknown index, both drawn as Pixel) its
-- four ants groups, Action Button Glow its Classic twin's flipbook, Auto-Cast
-- and Shape the Modern loop (flipbook and atlas overlay), an atlas flipbook
-- both groups, a texture flipbook its one group, the static borders none.
-- Only groups that exist are listed.
local function EngineGroupsInto(holder, position, result)
    local num = 0
    position = tonumber(position) or 1
    if position ~= STEALABLE_BORDER and position ~= PANDEMIC_BORDER then
        if position < 1 or position > #GLOW_STYLES or GLOW_STYLES[position].solidFill then
            position = 1
        end
        local record = GLOW_STYLES[position]
        if record.procedural then
            local a = holder._cuiAnimAnts
            if a then
                for i = 1, 4 do
                    result[i] = a.groups[i]
                end
                num = 4
            end
        else
            if record.buttonGlow then
                record = GLOW_STYLES[7]
            elseif record.autocast or record.shapeGlow then
                record = GLOW_STYLES[6]
            end
            local f = holder._cuiFlipData
            if f then
                num = 1
                result[1] = f.ag
                if record.atlas and f.antsAg then
                    num = 2
                    result[2] = f.antsAg
                end
            end
        end
    end
    for i = num + 1, #result do
        result[i] = nil
    end
    return num
end

-- Scratch for the wanted groups (read synchronously by the sync below).
local _bWant = {}

local function _InWant(ag, num)
    for i = 1, num do
        if _bWant[i] == ag then
            return true
        end
    end
    return false
end

-- True (after deferring the button's style key to the restriction lift) when
-- the bound host's button refuses our calls right now.
local function BoundBlocked(rec)
    local AK = CludesUI.AuraKit
    if AK.CanTouchButton(rec.button) then
        return false
    end
    AK.DeferRestyle(rec.d.styleKey)
    return true
end

-- Makes the button hold exactly _bWant[1..n] of the wrapper's groups (the
-- others it holds are removed), then kicks when anything is wanted. n = 0
-- hands every group back. true when all of it landed.
local function SyncBoundHost(holder, rec, num)
    local AK = CludesUI.AuraKit
    local btnFrame, glowData = rec.button, rec.d
    local success = true
    local a = holder._cuiAnimAnts
    if a then
        for i = 1, 4 do
            local ag = a.groups[i]
            if not _InWant(ag, num) and not AK.SetShownAnimation(btnFrame, glowData, ag, false) then
                success = false
            end
        end
    end
    local f = holder._cuiFlipData
    if f then
        if not _InWant(f.ag, num) and not AK.SetShownAnimation(btnFrame, glowData, f.ag, false) then
            success = false
        end
        local antsAg = f.antsAg
        if antsAg and not _InWant(antsAg, num) and not AK.SetShownAnimation(btnFrame, glowData, antsAg, false) then
            success = false
        end
    end
    for i = 1, num do
        if not AK.SetShownAnimation(btnFrame, glowData, _bWant[i], true) then
            success = false
        end
    end
    if success and num > 0 then
        success = AK.KickShownAnimations(btnFrame, glowData, _bWant, num)
    end
    return success
end

-- Bound host: false when the stop had to wait for the restriction lift (the
-- glow keeps its state until then), else whether its groups were handed back.
local function StopGlow(holder)
    if not holder then
        return
    end
    local rec = BOUND[holder]
    if rec and BoundBlocked(rec) then
        return false
    end
    StopAllGlows(holder)
    holder._cuiGlowActive = false
    holder:SetAlpha(0)
    if rec then
        return SyncBoundHost(holder, rec, 0)
    end
end

-------------------------------------------------------------------------------
--  Animation-driven glow (engine aura buttons)
--  The 12.1 slot-button subtree is forbidden to addon code outside its
--  creation window, so the driver-ticked engines above (Lua OnUpdate)
--  freeze there. This variant reproduces the Pixel Glow march with C-side
--  AnimationGroups: created in the creation window, it animates with zero
--  per-frame Lua -- identically in and out of secret contexts (on a bound
--  host only while its button shows an aura).
-------------------------------------------------------------------------------
local ANIM_MASK_TEX = [[Interface\Buttons\WHITE8X8]]

-- One hidden background strip of the animated ants, spanning p1 to p2.
local function _MkAntsBg(holder, p1, p2)
    local t = holder:CreateTexture(nil, "OVERLAY", nil, 6)
    t:SetPoint(p1, holder, p1)
    t:SetPoint(p2, holder, p2)
    t:Hide()
    return t
end

-- Region creation only (shared with PrewarmEngineHost): per edge the rect mask,
-- the dash strip and its looping Translation, then the background strips,
-- all hidden. The data table appears only once every region exists.
local function _EnsureAnimAnts(holder)
    local glowData = holder._cuiAnimAnts
    if glowData then
        return glowData
    end
    glowData = { strips = {}, masks = {}, groups = {}, trs = {}, bgs = {} }
    for i = 1, 4 do
        local maskTex = holder:CreateMaskTexture()
        maskTex:SetTexture(ANIM_MASK_TEX, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        local stripTex = holder:CreateTexture(nil, "OVERLAY", nil, 7)
        stripTex:AddMaskTexture(maskTex)
        stripTex:Hide()
        local ag = stripTex:CreateAnimationGroup()
        ag:SetLooping("REPEAT")
        local tr = ag:CreateAnimation("Translation")
        tr:SetSmoothing("NONE")
        glowData.masks[i], glowData.strips[i], glowData.groups[i], glowData.trs[i] = maskTex, stripTex, ag, tr
    end
    -- Background strips: top, right, bottom, left (same order as the edges).
    glowData.bgs[1] = _MkAntsBg(holder, "TOPLEFT", "TOPRIGHT")
    glowData.bgs[2] = _MkAntsBg(holder, "TOPRIGHT", "BOTTOMRIGHT")
    glowData.bgs[3] = _MkAntsBg(holder, "BOTTOMLEFT", "BOTTOMRIGHT")
    glowData.bgs[4] = _MkAntsBg(holder, "TOPLEFT", "BOTTOMLEFT")
    holder._cuiAnimAnts = glowData
    return glowData
end

-- Marching dashes: per edge, a dash strip one pattern-cycle longer than the edge slides
-- by exactly one cycle and loops; a rect mask clips it to the edge, so the snap-back is
-- invisible and the march is seamless. Strip texcoords carry the cumulative perimeter
-- phase, keeping dashes corner-continuous exactly like the driver-ticked ants (phase
-- matters modulo one cycle, so the one-cycle anchor offsets cancel out).
-- bgR non-nil = background on (same contract as StartProceduralAnts): a static
-- solid strip under each edge. The strips are created WITH the dash strips on
-- the first call, so turning the background on later never creates a region
-- outside the host's creation window.
local function StartAnimatedAnts(holder, N, th, period, cornerR, cornerG, cornerB, wid, hgt, ca, bgR, bgG, bgB, bgA)
    N = (N and N > 0) and N or 8
    th = th or 2
    period = period or 4
    wid = wid or 36
    hgt = hgt or wid
    local perim = 2 * (wid + hgt)
    local P = perim / N -- pixels per dash cycle
    local step = period / N -- seconds per dash cycle
    local glowData = _EnsureAnimAnts(holder)
    for i = 1, 4 do
        local t = glowData.bgs[i]
        if bgR then
            if i == 1 or i == 3 then
                t:SetHeight(th)
            else
                t:SetWidth(th)
            end
            t:SetColorTexture(bgR, bgG or 0, bgB or 0, bgA or 1)
            t:Show()
        else
            t:Hide()
        end
    end
    -- Edge order (clockwise): 1 top scrolls right, 2 right scrolls down,
    -- 3 bottom scrolls left, 4 left scrolls up. base = cumulative
    -- perimeter phase in cycles at the edge's visual start. Computed per
    -- edge in place (no per-call tables).
    cornerR, cornerG, cornerB, ca = cornerR or 1, cornerG or 1, cornerB or 1, ca or 1
    for i = 1, 4 do
        local maskTex, stripTex, ag, tr = glowData.masks[i], glowData.strips[i], glowData.groups[i], glowData.trs[i]
        ag:Stop()
        stripTex:SetVertexColor(cornerR, cornerG, cornerB, ca)
        maskTex:ClearAllPoints()
        stripTex:ClearAllPoints()
        if i == 1 or i == 3 then
            local base = 0
            if i == 3 then
                base = (wid + hgt) / P
            end
            stripTex:SetTexture(DASH_H, "REPEAT", "REPEAT")
            maskTex:SetSize(wid, th)
            stripTex:SetSize(wid + P, th)
            if i == 1 then
                maskTex:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
                stripTex:SetPoint("TOPLEFT", holder, "TOPLEFT", -P, 0)
                tr:SetOffset(P, 0)
            else
                maskTex:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 0, 0)
                stripTex:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 0, 0)
                tr:SetOffset(-P, 0)
            end
            stripTex:SetTexCoord(base, base + (wid + P) / P, 0, 1)
        else
            local base = wid / P
            if i == 4 then
                base = (wid + hgt + wid) / P
            end
            stripTex:SetTexture(DASH_V, "REPEAT", "REPEAT")
            maskTex:SetSize(th, hgt)
            stripTex:SetSize(th, hgt + P)
            if i == 2 then
                maskTex:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, 0)
                stripTex:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, P)
                tr:SetOffset(0, -P)
            else
                maskTex:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 0, 0)
                stripTex:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 0, -P)
                tr:SetOffset(0, P)
            end
            stripTex:SetTexCoord(0, 1, base, base + (hgt + P) / P)
        end
        stripTex:Show()
        tr:SetDuration(step)
        ag:Play()
    end
end

-------------------------------------------------------------------------------
--  StartEngineGlow — StartGlow for wrappers on ENGINE aura-button subtrees
--  (12.1 forbidden partition: NP purge, RF DM fx, RF BM icon glow, ...).
--  Driver-ticked engines cannot run there -- the driver's Lua reads on the
--  wrapper throw outside sanctioned windows -- so every driver style routes
--  to its C-side equivalent and animates identically in and out of secret
--  contexts: Pixel Glow renders its GENUINE dash march through the animated
--  ants engine (not a lookalike remap), Action Button Glow plays its
--  flipbook twin (the same IconAlertAnts sheet the driver version scrolls),
--  and Auto-Cast Shine / Shape Glow -- no C-side equivalent built -- fall
--  back to the Modern WoW Glow loop (options on engine-hosted pickers hide
--  those two; the fallback only covers stale saved values). FlipBook picks
--  pass through untouched. Never registers with the central driver.
-------------------------------------------------------------------------------
local ABG_HALO_OPTS = { abgHalo = true } -- shared scratch for the no-opts ABG substitution (halo color rewritten per call, read synchronously)
local function StartEngineGlow(holder, styleIdx, szOrW, cornerR, cornerG, cornerB, options, szH)
    if not holder then
        return
    end
    styleIdx = tonumber(styleIdx) or 1
    -- Blackout is Cooldown Manager only: engine hosts draw Pixel instead, as
    -- ResolveStyle does.
    if styleIdx < 1 or styleIdx > #GLOW_STYLES or GLOW_STYLES[styleIdx].solidFill then
        styleIdx = 1
    end
    local record = GLOW_STYLES[styleIdx]
    if record.procedural then
        options = options or {}
        local wid = szOrW or 36
        local backdrop = options.bg
        StopAllGlows(holder)
        StartAnimatedAnts(
            holder,
            options.N or 8,
            options.th or 2,
            options.period or 4,
            cornerR or 1,
            cornerG or 1,
            cornerB or 1,
            wid,
            szH or wid,
            nil,
            backdrop and (backdrop.r or 0) or nil,
            backdrop and (backdrop.g or 0) or nil,
            backdrop and (backdrop.b or 0) or nil,
            backdrop and (backdrop.a or 1) or nil
        )
        holder._cuiGlowActive = true
        holder:SetAlpha(1)
        return
    end
    if record.buttonGlow then
        -- Classic's flipbook sheet plus ABG's soft outer halo (opts.abgHalo),
        -- scoped to this substitution and never to the shared Classic entry.
        -- Real ABG anatomy: the ants stay white (nil color = the flipbook's
        -- white default) while the COLOR rides the halo alone -- gold when
        -- the caller never chose one.
        styleIdx = 7
        -- untinted would turn the white ants into the sheet's raw gold; the
        -- substitution always wants them white.
        if options then
            options.abgHalo = true
            options.untinted = nil
        else
            options = ABG_HALO_OPTS
        end
        options.haloR, options.haloG, options.haloB = cornerR, cornerG, cornerB
        cornerR, cornerG, cornerB = nil, nil, nil
    elseif record.autocast or record.shapeGlow then
        styleIdx = 6
    end
    StartGlow(holder, styleIdx, szOrW, cornerR, cornerG, cornerB, options, szH)
end

-------------------------------------------------------------------------------
--  Public API — attached to CludesUI.Glows
-------------------------------------------------------------------------------
-- Styles that render through C-side FlipBook AnimationGroups (GCD, Modern WoW Glow,
-- Classic WoW Glow) animate IDENTICALLY under 12.1 aura restrictions; driver-ticked
-- styles (Pixel, Action Button, Auto-Cast, Shape) cannot -- secret visibility blocks
-- their Lua ticks, leaving a frozen artifact. Kept for external callers that want a
-- plain style REMAP (in-tree engine-button hosts use StartEngineGlow instead, which
-- renders Pixel genuinely): Pixel -> Classic WoW Glow (ants), everything else
-- driver-based -> Modern WoW Glow (the standard proc loop).
local SAFE_STYLE_MAP = { [1] = 7, [2] = 6, [3] = 6, [4] = 6 }
local function RestrictionSafeStyle(position)
    local record = GLOW_STYLES[position]
    if record and (record.procedural or record.buttonGlow or record.autocast or record.shapeGlow) then
        return SAFE_STYLE_MAP[position] or 6
    end
    return position
end

-- The public animated ants for direct callers (the Buff Manager's dashed
-- border): on a bound host (G.BindEngineHost) a start registers the four ants
-- groups and kicks, a stop hands them back, both skipped and deferred to the
-- restriction lift while the button refuses our calls (they then return
-- false). Unbound wrappers run the engine exactly as before.
local function StartAnimatedAntsPublic(holder, ...)
    local rec = BOUND[holder]
    if not rec then
        return StartAnimatedAnts(holder, ...)
    end
    if BoundBlocked(rec) then
        return false
    end
    StartAnimatedAnts(holder, ...)
    return SyncBoundHost(holder, rec, EngineGroupsInto(holder, 1, _bWant))
end

local function StopAnimatedAntsPublic(holder)
    local rec = BOUND[holder]
    if not rec then
        return StopAnimatedAnts(holder)
    end
    -- Never armed: nothing to stop and nothing registered.
    if not holder._cuiAnimAnts then
        return true
    end
    if BoundBlocked(rec) then
        return false
    end
    StopAnimatedAnts(holder)
    return SyncBoundHost(holder, rec, 0)
end

CludesUI.Glows = {
    STYLES = GLOW_STYLES,

    -- High-level API (recommended)
    StartGlow = StartGlow,
    StartEngineGlow = StartEngineGlow,
    StopGlow = StopGlow,
    RestrictionSafeStyle = RestrictionSafeStyle,

    -- Low-level engines (for addons that need direct control)
    StartProceduralAnts = StartProceduralAnts,
    StopProceduralAnts = StopProceduralAnts,
    SetProceduralAntsColor = SetProceduralAntsColor,
    StartButtonGlow = StartButtonGlow,
    StopButtonGlow = StopButtonGlow,
    StartAutoCastShine = StartAutoCastShine,
    StopAutoCastShine = StopAutoCastShine,
    StartAnimatedAnts = StartAnimatedAntsPublic,
    StopAnimatedAnts = StopAnimatedAntsPublic,
    StartShapeGlow = StartShapeGlow,
    StopShapeGlow = StopShapeGlow,
    StartFlipBookGlow = StartFlipBookGlow,
    StopFlipBookGlow = StopFlipBookGlow,
    StartSolidFill = StartSolidFill,
    StopSolidFill = StopSolidFill,
    ApplyMaskWith = ApplyMaskWith,
    StopAllGlows = StopAllGlows,
}

-------------------------------------------------------------------------------
--  Blizzard Border: the static art Blizzard's own target frame puts on a buff
--  it can steal or purge. No driver and no animation, so it renders the same
--  in and out of restricted content on engine aura buttons (where a glow host
--  belongs to a purgeable GROUP, never to a per-aura read). Its picker value
--  sits outside the STYLES list. The texture is made on first use (the
--  flipbook glows create theirs on the same hosts the same way); Show/Hide
--  then only resize, tint and toggle it.
-------------------------------------------------------------------------------
do
    local G = CludesUI.Glows
    local TEX = "Interface\\TargetingFrame\\UI-TargetingFrame-Stealable"
    -- Blizzard draws it 24 px on a 21 px buff icon.
    local SCALE = 24 / 21
    G.STEALABLE_BORDER = STEALABLE_BORDER

    function G.EnsureStealableBorder(owner)
        local texture = owner._cuiStealTex
        if not texture then
            texture = owner:CreateTexture(nil, "OVERLAY")
            texture:SetTexture(TEX)
            texture:SetBlendMode("ADD")
            texture:SetPoint("CENTER")
            texture:Hide()
            owner._cuiStealTex = texture
        end
        return texture
    end

    -- w/h: the icon's size; nil color = Blizzard's own look. A tint
    -- desaturates first, like the flipbook glows, so the pick reads true.
    function G.ShowStealableBorder(owner, wid, hgt, cornerR, cornerG, cornerB)
        local texture = G.EnsureStealableBorder(owner)
        wid = wid or 24
        hgt = hgt or wid
        texture:SetSize(wid * SCALE, hgt * SCALE)
        texture:SetDesaturated(cornerR ~= nil)
        texture:SetVertexColor(cornerR or 1, cornerG or 1, cornerB or 1)
        texture:Show()
    end
end

-------------------------------------------------------------------------------
--  Blizzard Pandemic Border: the Cooldown Manager's own pandemic art, drawn
--  static round an icon, outset a fifth of the icon so it covers the icon's
--  square corners. Untinted (it always shows Blizzard's own look), no driver
--  and no animation, so like the Blizzard Border it renders the same in and
--  out of restricted content and costs nothing per frame. Its picker value
--  sits outside the STYLES list. The texture is made on first use (or by
--  PrewarmEngineHost); Show/Hide then only re-anchor and toggle it.
-------------------------------------------------------------------------------
do
    local G = CludesUI.Glows
    local ATLAS = "UI-CooldownManager-PandemicBorder"
    G.PANDEMIC_BORDER = PANDEMIC_BORDER

    function G.EnsurePandemicBorder(owner)
        local texture = owner._cuiPanTex
        if not texture then
            texture = owner:CreateTexture(nil, "ARTWORK")
            texture:SetAtlas(ATLAS)
            texture:Hide()
            owner._cuiPanTex = texture
        end
        return texture
    end

    -- w/h: the icon's size (the host covers the icon).
    function G.ShowPandemicBorder(owner, wid, hgt)
        local texture = G.EnsurePandemicBorder(owner)
        wid = wid or 24
        hgt = hgt or wid
        local result = floor(min(wid, hgt) * 0.2 + 0.5)
        texture:ClearAllPoints()
        texture:SetPoint("TOPLEFT", owner, "TOPLEFT", -result, result)
        texture:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", result, -result)
        texture:Show()
    end
end

-------------------------------------------------------------------------------
--  Unified glow model
--  GLOW_STYLES is the one style table (the "shared index"). Modules keep their
--  historical saved numbering through a VIEW, hosts describe what can render
--  where, and StartSpecGlow renders a whole glow setting (style, color, pixel
--  parameters, background) in one call. Saved keys stay module-owned: these
--  helpers only translate and render.
-------------------------------------------------------------------------------
do
    local G = CludesUI.Glows

    -- Suite default look ("default" color mode): gold for the drawn engines,
    -- the atlas's own untinted look for FlipBook styles.
    local DEF_R, DEF_G, DEF_B = 1.0, 0.788, 0.137
    G.DEFAULT_COLOR = { r = DEF_R, g = DEF_G, b = DEF_B }

    -- A module's style list in its saved order. list[i] is the shared entry
    -- itself, or a proxy over it when overrides[i] adds module-only fields
    -- (read through __index, so frames/texPadding always come from the shared
    -- table). toShared[i] / fromShared[shared] translate saved <-> shared.
    -- ordered = the saved values in shared order, so every menu lists the
    -- styles the same way whatever a module's saved numbering is.
    function G.MakeView(sequence, overrides)
        local entries, toShared, fromShared, ordered = {}, {}, {}, {}
        for i = 1, #sequence do
            local si = sequence[i]
            local shade = overrides and overrides[i]
            entries[i] = shade and setmetatable(shade, { __index = GLOW_STYLES[si] }) or GLOW_STYLES[si]
            toShared[i] = si
            fromShared[si] = i
        end
        for si = 1, #GLOW_STYLES do
            if fromShared[si] then
                ordered[#ordered + 1] = fromShared[si]
            end
        end
        return { list = entries, toShared = toShared, fromShared = fromShared, ordered = ordered }
    end

    -- Styles each host can render, by shared index. Technical limits live
    -- here; which styles a site OFFERS (e.g. no Shape without an icon shape) is
    -- the site's own excludes list. Blackout (8) is Cooldown Manager only and
    -- stays out of every host on purpose: that keeps it out of every shared
    -- glow picker (StyleOffered), and ResolveStyle turns a stray 8 into Pixel.
    --   icon   : our own frame, driver-ticked engines allowed
    --   bar    : our own rectangular frame; Shape has no shape to follow
    --   engine : 12.1 aura-button subtree; no driver ticks, so no Auto-Cast or
    --            Shape (Pixel renders as animated ants, ABG as its FlipBook twin)
    G.HOSTS = {
        icon = { true, true, true, true, true, true, true },
        bar = { true, true, true, false, true, true, true },
        engine = { true, true, false, false, true, true, true },
    }

    -- Rectangles (buff bars, whole-frame glows): the texture styles
    -- (ABG, GCD, Modern, Classic) are square art that stretches on a wide bar,
    -- and Shape has no shape to follow, so only Pixel and Auto-Cast draw
    -- cleanly. Rectangle sites pass this as their excludes, in the options and
    -- in the live spec (an engine host drops Auto-Cast on top: Pixel only).
    G.RECT_EXCLUDES = { [2] = true, [4] = true, [5] = true, [6] = true, [7] = true }

    -- Nearest renderable replacement, in preference order, per wanted style.
    local FALLBACK = {
        [1] = { 7, 6, 5 }, -- Pixel      -> Classic ants
        [2] = { 7, 6, 1 }, -- ABG        -> Classic
        [3] = { 6, 5, 1 }, -- Auto-Cast  -> Modern (StartEngineGlow's own remap)
        [4] = { 6, 1, 7 }, -- Shape      -> Modern
        [5] = { 6, 7, 1 },
        [6] = { 5, 7, 1 },
        [7] = { 1, 6, 5 },
        [8] = { 1, 6, 7 }, -- Blackout   -> Pixel
    }

    -- Shared index -> renderable shared index, plus whether it had to change.
    function G.ResolveStyle(position, owner, excludes)
        position = tonumber(position) or 1
        -- The two static borders are plain textures: every host can show them.
        if position == STEALABLE_BORDER or position == PANDEMIC_BORDER then
            return position, false
        end
        if position < 1 or position > #GLOW_STYLES then
            position = 1
        end
        local caps = G.HOSTS[owner or "icon"] or G.HOSTS.icon
        if caps[position] and not (excludes and excludes[position]) then
            return position, false
        end
        local alts = FALLBACK[position]
        for k = 1, #alts do
            local a = alts[k]
            if caps[a] and not (excludes and excludes[a]) then
                return a, true
            end
        end
        return 1, true
    end

    -- Color for a mode. nil = the suite default (StartSpecGlow resolves it per
    -- style). A nil mode is a legacy site that never stored one: it reads as
    -- custom with the site's own default, so its look is unchanged.
    function G.ResolveColor(mode, r, g, b, defR, defG, defB)
        if mode == "default" then
            return nil
        end
        if mode == "class" then
            -- The palette colour (custom + Class Color Darken); an unknown class is white.
            local c = CludesUI.GetClassColor(CludesUI._playerClass)
            return c.r, c.g, c.b
        end
        if r ~= nil then
            return r, g or 0, b or 0
        end
        return defR, defG, defB
    end

    -- Legacy sites store a class-color boolean instead of a mode.
    function G.DeriveColorMode(mode, classFlag)
        if mode then
            return mode
        end
        return classFlag and "class" or "custom"
    end

    -- Speed: the UI shows 1-8 with higher = faster; saved values are the march
    -- period in seconds. Stored periods above 8 (older 1-10 sliders) still
    -- render as saved and read as the slowest step until edited.
    function G.SpeedToUI(period)
        local val = 9 - (period or 4)
        if val < 1 then
            val = 1
        elseif val > 8 then
            val = 8
        end
        return val
    end
    function G.SpeedFromUI(val)
        return 9 - val
    end

    -- Spec from a settings table using the prefix key schema shared by the aura
    -- managers: <p>Type (shared index, 0 = off), <p>ColorMode, legacy
    -- <p>ClassColor, <p>R/G/B, <p>Lines, <p>Thickness, <p>Speed, <p>Background,
    -- <p>BackgroundR/G/B. Returns nil when off. Keys are built once per prefix.
    local _prefixKeys = {}
    local function PrefixKeys(p)
        local k = _prefixKeys[p]
        if not k then
            k = {
                type = p .. "Type",
                mode = p .. "ColorMode",
                class = p .. "ClassColor",
                r = p .. "R",
                g = p .. "G",
                b = p .. "B",
                lines = p .. "Lines",
                th = p .. "Thickness",
                speed = p .. "Speed",
                bg = p .. "Background",
                bgR = p .. "BackgroundR",
                bgG = p .. "BackgroundG",
                bgB = p .. "BackgroundB",
            }
            _prefixKeys[p] = k
        end
        return k
    end
    G.PrefixKeys = PrefixKeys

    function G.SpecFromPrefix(result, t, p, defR, defG, defB)
        local k = PrefixKeys(p)
        local style = t and t[k.type] or 0
        if not style or style == 0 then
            return nil
        end
        result.style = style
        result.r, result.g, result.b =
            G.ResolveColor(G.DeriveColorMode(t[k.mode], t[k.class]), t[k.r], t[k.g], t[k.b], defR, defG, defB)
        result.lines, result.thickness, result.speed = t[k.lines], t[k.th], t[k.speed]
        if t[k.bg] then
            result.bg, result.bgR, result.bgG, result.bgB = true, t[k.bgR] or 0, t[k.bgG] or 0, t[k.bgB] or 0
        else
            -- out is the caller's reused scratch: clear the colour too.
            result.bg, result.bgR, result.bgG, result.bgB = nil, nil, nil, nil
        end
        return result
    end

    -- The flat key schema most module glows save: <p>Color, <p>Lines,
    -- <p>Thickness, <p>Speed, <p>Background, <p>BackgroundColor (colors as
    -- {r,g,b} tables), plus <p>Style and <p>ColorMode where a site keeps them.
    -- Keys are built once per prefix; the options' FlatGet / FlatSet read them.
    local _flatKeys = {}
    function G.FlatKeys(p)
        local k = _flatKeys[p]
        if not k then
            k = {
                style = p .. "Style",
                mode = p .. "ColorMode",
                color = p .. "Color",
                lines = p .. "Lines",
                thickness = p .. "Thickness",
                speed = p .. "Speed",
                bg = p .. "Background",
                bgColor = p .. "BackgroundColor",
            }
            _flatKeys[p] = k
        end
        return k
    end

    -- Spec from a flat-schema settings table, all but the style: sites number
    -- their styles and store their color modes their own way, so the caller
    -- passes the mode and sets out.style. k: the prefix's FlatKeys table.
    -- defs: fallbacks under the same keys (a module's defaults table).
    local function FlatVal(t, defs, key)
        local val = t[key]
        if val == nil and defs then
            val = defs[key]
        end
        return val
    end
    function G.SpecFromFlat(result, t, k, mode, defs)
        local c = FlatVal(t, defs, k.color)
        result.r, result.g, result.b = G.ResolveColor(mode, c and c.r, c and c.g, c and c.b)
        result.lines = FlatVal(t, defs, k.lines)
        result.thickness = FlatVal(t, defs, k.thickness)
        result.speed = FlatVal(t, defs, k.speed)
        if FlatVal(t, defs, k.bg) == true then
            local bc = FlatVal(t, defs, k.bgColor)
            result.bg = true
            result.bgR, result.bgG, result.bgB = bc and bc.r or 0, bc and bc.g or 0, bc and bc.b or 0
        else
            -- out is the caller's reused scratch: clear the colour too.
            result.bg, result.bgR, result.bgG, result.bgB = nil, nil, nil, nil
        end
        return result
    end

    -- Options previews sit in the panel, whose pixel grid differs from
    -- UIParent's: a raw thickness would draw a different (or no) pixel count
    -- there. Pass PANEL_EXTRA as StartSpecGlow's extra to draw the pixels the
    -- live UIParent glow shows.
    G.PANEL_EXTRA = { panel = true }
    function G.PanelThickness(th)
        local Pix, PPP = CludesUI.PP, CludesUI.PanelPP
        local px = math.floor(th / ((Pix and Pix.mult) or 1) + 0.5)
        if px < 1 then
            px = 1
        end
        return px * ((PPP and PPP.mult) or 1)
    end

    -- Scratch opts for StartSpecGlow: every field is rewritten on every call.
    -- StartEngineGlow writes abgHalo/halo* into the table it is given, so a
    -- field left over from one call would leak into the next (a Classic pick
    -- after an ABG pick would keep the halo).
    local _opts, _bg = {}, {}

    -- spec = { style = shared index, r, g, b (already resolved; nil = default
    --          look), lines, thickness, speed (period), bg, bgR, bgG, bgB,
    --          excludes }
    -- host = "icon" | "bar" | "engine"; extra = { maskWith, maskPath,
    --          borderPath, shapeMask, anchorFrame, panel } (optional, read in this call)
    -- Restarts only when something changed; returns the rendered shared index
    -- and whether it was converted from the requested one.
    -- A bound host (G.BindEngineHost) always draws as an engine host, then
    -- makes its button hold exactly the groups the drawn style plays and kicks
    -- (see the bound engine hosts note above StopGlow). The change signature
    -- is stored only once all of that landed. While its button refuses our
    -- calls (auras restricted, outside the creation window) a call that would
    -- change anything returns nothing and defers the button's style key to
    -- the restriction lift; an unchanged glow still returns at once.
    function G.StartSpecGlow(holder, specInfo, wid, hgt, owner, extra)
        if not (holder and specInfo) then
            return
        end
        local position, converted = G.ResolveStyle(specInfo.style, owner, specInfo.excludes)
        wid = wid or 36
        hgt = hgt or wid
        local s = holder._cuiSpecSig
        local rec = BOUND[holder]
        -- The static borders: no glow, no parameters. Blizzard Border: nil
        -- color = Blizzard's art. Blizzard Pandemic Border: always untinted.
        if position == STEALABLE_BORDER or position == PANDEMIC_BORDER then
            local r, g, b
            if position == STEALABLE_BORDER then
                r, g, b = specInfo.r, specInfo.g, specInfo.b
            end
            if rec and BoundBlocked(rec) then
                return
            end
            -- StopGlow leaves the host at alpha 0 and a caller may park it
            -- there, so the alpha is re-asserted even when nothing changed.
            holder:SetAlpha(1)
            if
                s
                and s.idx == position
                and s.w == wid
                and s.h == hgt
                and s.r == r
                and s.g == g
                and s.b == b
            then
                return position, false
            end
            -- Clear the flag too (StopAllGlows keeps it), so later calls skip the teardown.
            if holder._cuiGlowActive then
                StopAllGlows(holder)
                holder._cuiGlowActive = false
            else
                -- From the other static border: only its texture can be up.
                local other = (position == STEALABLE_BORDER) and holder._cuiPanTex or holder._cuiStealTex
                if other then
                    other:Hide()
                end
                if s then
                    s.idx = nil
                end
            end
            if position == STEALABLE_BORDER then
                G.ShowStealableBorder(holder, wid, hgt, r, g, b)
            else
                G.ShowPandemicBorder(holder, wid, hgt)
            end
            -- A static border plays no group: a bound host hands them back.
            if rec and not SyncBoundHost(holder, rec, 0) then
                return position, false
            end
            if not s then
                s = {}
                holder._cuiSpecSig = s
            end
            s.idx, s.host, s.w, s.h, s.r, s.g, s.b = position, owner, wid, hgt, r, g, b
            return position, false
        end
        -- A shown static border needs no separate hide: every start below
        -- runs StopAllGlows first, which hides it and clears the signature.
        local engineHost = (owner == "engine") or rec ~= nil
        local record = GLOW_STYLES[position]
        local r, g, b = specInfo.r, specInfo.g, specInfo.b
        local isFlip = not (record.procedural or record.buttonGlow or record.autocast or record.shapeGlow)
        -- Default look: FlipBooks stay untinted (nil). The engine-hosted ABG
        -- twin takes nil too (white ants, gold halo); everything else is gold.
        if r == nil and not isFlip and not (engineHost and record.buttonGlow) then
            r, g, b = DEF_R, DEF_G, DEF_B
        end
        local N, th, period = specInfo.lines or 8, specInfo.thickness or 2, specInfo.speed or 4
        if extra and extra.panel then
            th = G.PanelThickness(th)
        end
        local bgOn = specInfo.bg and true or false
        -- An off background draws nothing, so its colour never counts (a
        -- reused scratch spec can still carry an old one).
        local bgR, bgG, bgB = 0, 0, 0
        if bgOn then
            bgR, bgG, bgB = specInfo.bgR or 0, specInfo.bgG or 0, specInfo.bgB or 0
        end
        local maskTex = extra and extra.maskWith or nil
        local maskPath = extra and extra.maskPath or nil
        local shapeMask = extra and extra.shapeMask or nil

        if
            s
            and holder._cuiGlowActive
            and s.idx == position
            and s.host == owner
            and s.w == wid
            and s.h == hgt
            and s.r == r
            and s.g == g
            and s.b == b
            and s.N == N
            and s.th == th
            and s.period == period
            and s.bg == bgOn
            and s.bgR == bgR
            and s.bgG == bgG
            and s.bgB == bgB
            and s.mask == maskTex
            and s.maskPath == maskPath
            and s.shapeMask == shapeMask
        then
            return position, converted
        end
        if rec and BoundBlocked(rec) then
            return
        end

        local o = _opts
        o.N, o.th, o.period = N, th, period
        if bgOn then
            _bg.r, _bg.g, _bg.b, _bg.a = bgR, bgG, bgB, 1
            o.bg = _bg
        else
            o.bg = nil
        end
        o.untinted = (r == nil) or nil
        o.abgHalo, o.haloR, o.haloG, o.haloB = nil, nil, nil, nil
        o.maskWith = maskTex
        o.maskPath = maskPath
        o.borderPath = extra and extra.borderPath or nil
        o.shapeMask = shapeMask
        o.anchorFrame = extra and extra.anchorFrame or nil
        if engineHost then
            StartEngineGlow(holder, position, wid, r, g, b, o, hgt)
        else
            StartGlow(holder, position, wid, r, g, b, o, hgt)
        end
        -- The start's StopAllGlows left the signature unset, so a failed
        -- registration retries on the next call (at the lift when deferred).
        if rec and not SyncBoundHost(holder, rec, EngineGroupsInto(holder, position, _bWant)) then
            return position, converted
        end

        -- Stored after the start: StartGlow's StopAllGlows invalidates it.
        s = holder._cuiSpecSig
        if not s then
            s = {}
            holder._cuiSpecSig = s
        end
        s.idx, s.host, s.w, s.h, s.r, s.g, s.b = position, owner, wid, hgt, r, g, b
        s.N, s.th, s.period = N, th, period
        s.bg, s.bgR, s.bgG, s.bgB, s.mask = bgOn, bgR, bgG, bgB, maskTex
        s.maskPath, s.shapeMask = maskPath, shapeMask
        return position, converted
    end

    -- Create the regions an engine-hosted glow can need, hidden and
    -- unconfigured, from the host's creation window (extraInit): a later style
    -- or background change then only reconfigures existing regions, and the
    -- first StartSpecGlow does the only setup (nothing is sized, tinted or
    -- played here). need = nil creates every family; else a table naming what
    -- the site can draw: ants (Pixel's animated ants and their background
    -- strips), flip (the FlipBook styles, with the atlas ants overlay and
    -- ABG's halo), stealable (the Blizzard Border texture), pandemic (the
    -- Blizzard Pandemic Border texture). Pass a file-scope constant. w, h
    -- stay for call compatibility (creation needs no size). Repeat calls are
    -- free: each family's data table appears only once its regions exist.
    function G.PrewarmEngineHost(holder, wid, hgt, need)
        if not holder then
            return
        end
        if not need or need.ants then
            _EnsureAnimAnts(holder)
        end
        if not need or need.flip then
            _EnsureFlip(holder, true, true)
        end
        if not need or need.stealable then
            G.EnsureStealableBorder(holder)
        end
        if not need or need.pandemic then
            G.EnsurePandemicBorder(holder)
        end
    end

    -- Binds an engine host to the aura button it sits on, so the button runs
    -- the host's animations (see the bound engine hosts note above StopGlow).
    -- d is the button's AuraKit data (the d its initializer and applyExtra
    -- receive). Call it once, at host creation, right after PrewarmEngineHost;
    -- repeat calls are free. kickIcon: for a bare button (style.noRegions)
    -- whose module registered an icon texture of its own with button:SetIcon,
    -- that texture (CludesUI.AuraKit.EnsureKickIcon); a bare button with no
    -- icon gets a hidden one on its first kick. Returns true when bound;
    -- false when the button cannot run animations itself (no
    -- AddAuraShownAnimation: WoW Forever), and the caller keeps its unbound
    -- path. A glow already running on the host restarts through the next
    -- StartSpecGlow, which registers it.
    function G.BindEngineHost(holder, btnFrame, glowData, kickIcon)
        if not (holder and btnFrame and glowData) then
            return false
        end
        local AK = CludesUI.AuraKit
        local rec = BOUND[holder]
        if not rec then
            if not (AK and AK.CanRunAnimations(btnFrame)) then
                return false
            end
            rec = { button = btnFrame, d = glowData }
            BOUND[holder] = rec
            local s = holder._cuiSpecSig
            if s then
                s.idx = nil
            end
        end
        if kickIcon then
            AK.EnsureKickIcon(btnFrame, glowData, kickIcon)
        end
        return true
    end

    function G.IsEngineHostBound(holder)
        return holder ~= nil and BOUND[holder] ~= nil
    end
end
