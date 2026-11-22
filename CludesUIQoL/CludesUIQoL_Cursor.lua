if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
local ADDON_NAME = ...

local ECL = CUI.Lite.NewAddon("CludesUICursor")

-- Shared with the Quickdraw hub: the full Cludes logo in the parent's
-- media folder.
local TEX_CUSTOM = "Interface\\AddOns\\CludesUI\\media\\logo-full-thin-2.png"

local RING_TEXTURES = {
    thin = "Interface\\AddOns\\CludesUIQoL\\Media\\ring_thin.tga",
    light = "Interface\\AddOns\\CludesUIQoL\\Media\\ring_light.tga",
    normal = "Interface\\AddOns\\CludesUIQoL\\Media\\ring_normal.tga",
    heavy = "Interface\\AddOns\\CludesUIQoL\\Media\\ring_heavy.tga",
    thick = "Interface\\AddOns\\CludesUIQoL\\Media\\ring_thick.tga",
}

local DEF_BASESIZE = 28
local DEF_SCALE = 1
local DEF_HEX = "4CC9F0"
local DEF_TEX = "ring_normal"
local DEF_INSTANCE_ONLY = false

local floor, tonumber, strupper, strsub, strgsub, strmatch =
    math.floor, tonumber, string.upper, string.sub, string.gsub, string.match
local min, max = math.min, math.max
local sin, cos = _G.sin or math.sin, _G.cos or math.cos -- WoW globals are degree-based
local GetTime = GetTime
local GetCursorPosition = GetCursorPosition
local GetSpellCooldown = C_Spell.GetSpellCooldown
local GCD_SPELL = CUI.GCD_SPELL
local UnitCastingInfo = UnitCastingInfo
local UnitChannelInfo = UnitChannelInfo

local frame, t, reticleTex
local lastX, lastY

local lastScale, lastHex, lastTex, lastAlpha
local visible = true
local mouselooking = false -- true while the hardware cursor is hidden (mouselook)

-------------------------------------------------------------------------------
--  Utility
-------------------------------------------------------------------------------
local function HexToRGB(hexColor)
    return tonumber(strsub(hexColor, 1, 2), 16) / 255,
        tonumber(strsub(hexColor, 3, 4), 16) / 255,
        tonumber(strsub(hexColor, 5, 6), 16) / 255
end

local function ParseHex(rawValue)
    if not rawValue then return 76 / 255, 201 / 255, 240 / 255 end
    rawValue = strupper(strgsub(rawValue, "#", ""))
    if not strmatch(rawValue, "^[0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F]$") then return 1, 1, 1 end
    return HexToRGB(rawValue)
end

-------------------------------------------------------------------------------
--  Color resolution: accent > class > custom hex. Shared by all three
--  cursor modules (Circle, GCD, Cast). Mutually exclusive: useAccentColor
--  wins over useClassColor which wins over the stored hex.
-------------------------------------------------------------------------------
local function ResolveColor(conf)
    if not conf then return 1, 1, 1 end
    if conf.useAccentColor and CUI.GetAccentColor then return CUI.GetAccentColor() end
    if conf.useClassColor then
        local _, engClass = UnitClass("player")
        local cc = engClass
            and (CUI.GetRawClassColor(engClass) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[engClass]))
        if cc then return cc.r, cc.g, cc.b end
    end
    return ParseHex(conf.hex or DEF_HEX)
end

local function InRealInstancedContent()
    local _, instanceType, difficultyID = GetInstanceInfo()
    difficultyID = tonumber(difficultyID) or 0
    if difficultyID == 0 then return false end
    if C_Garrison and C_Garrison.IsOnGarrisonMap and C_Garrison.IsOnGarrisonMap() then return false end
    return instanceType == "party" or instanceType == "raid"
end

-------------------------------------------------------------------------------
--  Cursor visibility (forward declaration -- defined after trail/GCD/cast locals)
-------------------------------------------------------------------------------
local UpdateVisibility

local lastUseClassColor

local function CursorSize(profile)
    local size = floor((profile.baseSize or DEF_BASESIZE) * (profile.scale or DEF_SCALE) + 0.5)
    if size < 8 then return 8 end
    if size > 512 then return 512 end
    return size
end

local function ApplyReticle(profile, size, red, green, blue, a)
    if not reticleTex then return end
    if not profile.reticle then
        reticleTex:Hide()
        return
    end
    -- ~20% of the ring so the mask has enough pixels to stay circular.
    local dotTex = max(4, floor(size * 0.2 + 0.5))
    reticleTex:SetSize(dotTex, dotTex)
    reticleTex:SetColorTexture(red, green, blue, a)
    reticleTex:Show()
end

local function ApplyCursorLook()
    if not frame or not t then return end
    local p = ECL.db.profile

    local zoom = p.scale or DEF_SCALE
    local size = CursorSize(p)
    if zoom ~= lastScale then
        lastScale = zoom
        frame:SetSize(size, size)
    end

    local hexColor = p.hex or DEF_HEX
    local colorModeChanged = (p.useClassColor ~= lastUseClassColor)
    lastUseClassColor = p.useClassColor
    -- Recompute whenever hex, class mode, accent mode, or the mode flag
    -- changed. Accent mode also needs per-frame re-read since CLUDES_GREEN
    -- mutates in place when the user changes their accent color mid-session.
    local a = (p.alpha or 100) / 100
    local red, green, blue
    if hexColor ~= lastHex or p.useClassColor or p.useAccentColor or colorModeChanged or a ~= lastAlpha then
        lastHex = hexColor
        lastAlpha = a
        red, green, blue = ResolveColor(p)
        t:SetVertexColor(red, green, blue, a)
    end

    local texture = p.texture or DEF_TEX
    if texture ~= lastTex then
        lastTex = texture
        -- Map dropdown keys (ring_thin, etc.) to RING_TEXTURES keys (thin, etc.)
        local ringKey = texture:match("^ring_(.+)$")
        local filePath = (ringKey and RING_TEXTURES[ringKey]) or RING_TEXTURES[texture] or TEX_CUSTOM
        t:SetTexture(filePath)
    end

    -- Reticle is cheap and Apply() only runs on setting changes, so always
    -- refresh it (toggle, scale, and color all land here).
    if not red then
        red, green, blue = ResolveColor(p)
    end
    ApplyReticle(p, size, red, green, blue, a)

    UpdateVisibility()
end

-------------------------------------------------------------------------------
--  Cursor Trail Engine (simple dot trail)
-------------------------------------------------------------------------------
local trailList = {} -- texture pool
local trailActive = {} -- active dot entries { tex, life, maxLife }
local trailPool = {} -- recycled entry tables to avoid GC churn
local trailTimer = 0
local trailLastCX, trailLastCY = 0, 0
local trailOn = false

local TRAIL_POOL_SIZE = 150
local TRAIL_DOT_DURATION = 0.5
local TRAIL_DOT_DENSITY = 0.004
local TRAIL_DOT_BASE_SIZE = 40

local trailHolder -- high-strata parent for trail dots

local function InitTrailDotPool()
    if not trailHolder then
        trailHolder = CreateFrame("Frame", "ECL_TrailContainer", UIParent)
        trailHolder:SetAllPoints(UIParent)
        trailHolder:SetFrameStrata("TOOLTIP")
        trailHolder:SetFrameLevel(9998)
        trailHolder:EnableMouse(false)
    end
    for index = 1, TRAIL_POOL_SIZE do
        local dotTex = trailHolder:CreateTexture(nil, "ARTWORK")
        dotTex:SetTexture("Interface\\AddOns\\CludesUIQoL\\Media\\ring_normal.tga")
        dotTex:SetBlendMode("ADD")
        dotTex:Hide()
        trailList[index] = dotTex
    end
end

local function GetTrailColor()
    local profile = ECL.db and ECL.db.profile
    return ResolveColor(profile)
end

local function SpawnTrailDot(cursorX, cursorY)
    if #trailList == 0 then return end
    local dotTex = trailList[#trailList]
    trailList[#trailList] = nil
    local uiScale = UIParent:GetEffectiveScale()
    local red, green, blue = GetTrailColor()
    local baseSize = TRAIL_DOT_BASE_SIZE * 0.8
    dotTex:SetVertexColor(red, green, blue, 1)
    dotTex:SetSize(baseSize, baseSize)
    dotTex:ClearAllPoints()
    dotTex:SetPoint("CENTER", trailHolder, "BOTTOMLEFT", cursorX / uiScale, cursorY / uiScale)
    dotTex:SetAlpha(1)
    dotTex:Show()
    local record = table.remove(trailPool) or {}
    record.tex = dotTex
    record.life = TRAIL_DOT_DURATION
    record.maxLife = TRAIL_DOT_DURATION
    trailActive[#trailActive + 1] = record
end

local function UpdateTrailDots(timePassed)
    for index = #trailActive, 1, -1 do
        local e = trailActive[index]
        e.life = e.life - timePassed
        if e.life <= 0 then
            e.tex:Hide()
            trailList[#trailList + 1] = e.tex
            e.tex = nil
            trailPool[#trailPool + 1] = e
            trailActive[index] = trailActive[#trailActive]
            trailActive[#trailActive] = nil
        else
            local percent = e.life / e.maxLife
            local sz = max(2, TRAIL_DOT_BASE_SIZE * 0.8 * percent)
            e.tex:SetSize(sz, sz)
            e.tex:SetAlpha(percent)
        end
    end
end

local function HideTrailDots()
    for index = #trailActive, 1, -1 do
        local e = trailActive[index]
        e.tex:Hide()
        trailList[#trailList + 1] = e.tex
        e.tex = nil
        trailPool[#trailPool + 1] = e
        trailActive[index] = nil
    end
end

local function ApplyTrail()
    local profile = ECL.db and ECL.db.profile
    trailOn = profile and profile.trail or false

    if not trailOn then
        HideTrailDots()
        if trailHolder then trailHolder:SetScript("OnUpdate", nil) end
        return
    end

    if #trailList == 0 and #trailActive == 0 then InitTrailDotPool() end

    -- Trail runs on trailContainer (always visible) so it keeps ticking
    -- even when the cursor circle frame is hidden (disabled or instance-only).
    if trailHolder and not trailHolder:GetScript("OnUpdate") then
        trailHolder:SetScript("OnUpdate", function(_, timePassed)
            if not trailOn then return end

            -- Only spawn dots while the cursor circle itself is visible, so the
            -- trail follows every gate on the circle (Combat Only, Only Show in
            -- Instances, Only Show When Hidden, the Visibility block) rather
            -- than re-deriving a subset of them.
            if visible then
                local cursorX, cursorY = GetCursorPosition()
                trailTimer = trailTimer + timePassed
                local dx = cursorX - trailLastCX
                local dy = cursorY - trailLastCY
                local moved = (dx * dx + dy * dy) ^ 0.5
                if trailTimer >= TRAIL_DOT_DENSITY and moved >= 0.5 then
                    trailTimer = 0
                    SpawnTrailDot(cursorX, cursorY)
                    trailLastCX, trailLastCY = cursorX, cursorY
                end
            end

            -- Always update (fade/shrink) active dots so they finish animating
            UpdateTrailDots(timePassed)
        end)
    end
end

-- Cursor glue, riding the suite's shared cursor service
-- (CludesUI.Mouse) instead of a per-frame OnUpdate on the cursor frame:
-- the glue is a Tier A motionOnly subscriber (per render frame while the cursor MOVES,
-- parked while it rests -- a resting cursor ring needs no repositioning, and mouselook
-- freezes GetCursorPosition so steering parks it too, which Only-Show-When-Hidden wants
-- anyway). Unlock mode hides the attached circles through the listener in OnEnable.
-- It is subscribed ONLY while the frame is visible (UpdateVisibility owns the
-- edges), preserving the old hidden-frame-stops-OnUpdate behavior.
local function CursorGlueBody(rawX, rawY)
    local uiScale = UIParent:GetEffectiveScale()
    local posX, posY = floor(rawX / uiScale + 0.5), floor(rawY / uiScale + 0.5)
    if posX ~= lastX or posY ~= lastY then
        lastX, lastY = posX, posY
        frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", posX, posY)
    end
end
local function GlueToCursor(on)
    local M = CUI and CUI.Mouse
    if not M then return end
    if on then
        -- Snap immediately: the motionOnly subscriber stays parked until the cursor
        -- moves, so without this the frame would sit wherever it last was (OnEnable's
        -- CENTER default on login) until the first pixel of motion.
        CursorGlueBody(M.Get())
        M.SubscribeFrame("qolCursor", CursorGlueBody, true)
    else
        M.UnsubscribeFrame("qolCursor")
    end
end

-------------------------------------------------------------------------------
--  Ring rendering engine (Cooldown-swipe based)
--  Uses CooldownFrameTemplate for smooth circular sweep.
--  Ring thickness is controlled by swapping pre-baked ring textures
--  (ring_thin, ring_light, ring_normal, ring_heavy, ring_thick).
-------------------------------------------------------------------------------

--- Create a ring frame using cooldown swipe for smooth circular fill.
--- @param parent Frame   parent frame
--- @param radius number  half-size of the ring frame
--- @param ringTex string  ring texture key (thin/light/normal/heavy/thick)
--- @param r number  red
--- @param g number  green
--- @param b number  blue
--- @param a number  alpha
--- @return Frame  the ring frame with :StartRing / :StopRing / :SetRingColor / :SetRingTexture
local function CreateRing(hostFrame, ringRadius, ringTex, red, green, blue, a)
    local ring = CreateFrame("Frame", nil, hostFrame)
    ring:SetSize(ringRadius * 2, ringRadius * 2)
    ring:SetPoint("CENTER", hostFrame, "CENTER", 0, 0)
    ring:SetFrameLevel(hostFrame:GetFrameLevel() + 1)

    ring.radius = ringRadius
    ring.dur = 0
    ring.maxDur = 0
    ring._r, ring._g, ring._b, ring._a = red, green, blue, a

    local texPath = RING_TEXTURES[ringTex] or RING_TEXTURES.normal

    -- Ring texture: static full ring for non-animated display
    ring._fg = ring:CreateTexture(nil, "ARTWORK")
    ring._fg:SetAllPoints(ring)
    ring._fg:SetTexture(texPath)
    ring._fg:SetVertexColor(red, green, blue, a)
    ring._fg:Hide()

    -- Cooldown swipe for smooth progress using the ring texture directly.
    ring._cd = CreateFrame("Cooldown", nil, ring, "CooldownFrameTemplate")
    ring._cd:SetAllPoints(ring)
    ring._cd:SetFrameLevel(ring:GetFrameLevel() + 1)
    ring._cd:SetHideCountdownNumbers(true)
    ring._cd:SetDrawEdge(false)
    ring._cd:SetDrawBling(false)
    ring._cd:SetReverse(true)
    ring._cd:SetSwipeTexture(texPath)
    ring._cd:SetSwipeColor(red, green, blue, a)
    ring._cd:Hide()

    function ring:SetRingColor(newR, newG, newB, newA)
        self._r, self._g, self._b, self._a = newR, newG, newB, newA
        self._fg:SetVertexColor(newR, newG, newB, newA)
        self._cd:SetSwipeColor(newR, newG, newB, newA)
    end

    function ring:SetRingRadius(nextRadius)
        self.radius = nextRadius
        self:SetSize(nextRadius * 2, nextRadius * 2)
    end

    function ring:SetRingTexture(newKey)
        local tp = RING_TEXTURES[newKey] or RING_TEXTURES.normal
        self._fg:SetTexture(tp)
        self._cd:SetSwipeTexture(tp)
    end

    function ring:StartRing(timePassed, maxDur)
        self.dur = max(timePassed, 0)
        self.maxDur = maxDur
        self._fg:Hide()
        local nowTime = GetTime()
        self._cd:SetCooldown(nowTime - timePassed, maxDur)
        self._cd:Show()
        self:Show()
    end

    -- Secret-value path: the engine draws the real cooldown from the duration
    -- object; ceiling only bounds how long the ring frame stays shown
    function ring:StartRingFromDuration(durObj, ceiling)
        self.dur = 0
        self.maxDur = ceiling
        self._fg:Hide()
        self._cd:SetCooldownFromDurationObject(durObj)
        self._cd:Show()
        self:Show()
    end

    function ring:StopRing()
        self._cd:Hide()
        self._fg:Hide()
        self.dur = 0
        self.maxDur = 0
        self:Hide()
    end

    ring:SetScript("OnUpdate", function(self, elapsed)
        if self.maxDur <= 0 then return end
        self.dur = self.dur + elapsed
        if self.dur >= self.maxDur then self:StopRing() end
    end)

    ring:Hide()
    return ring
end

-------------------------------------------------------------------------------
--  GCD Circle
-------------------------------------------------------------------------------
local gcdRoot, gcdRing
local gcdAttached = true -- follows cursor by default

local function GcdCfg()
    local profile = ECL.db and ECL.db.profile
    return profile and profile.gcd or {}
end

-- Start the ring from the live GCD (does nothing when no GCD is running).
-- Called from the cast events and from the combat-start visibility pass.
local function ArmGCDRing()
    if not gcdRing then return end
    local cdData = GetSpellCooldown(GCD_SPELL)
    if not cdData then return end
    local skinData, s = cdData.duration, cdData.startTime
    if issecretvalue(skinData) or issecretvalue(s) then
        -- Restricted combat hides the numbers: hand the GCD's duration object to
        -- the swipe (the Resource Bars GCD bar's native path). isActive is never
        -- secret and skips a GCD that already ended (the SUCCEEDED of a hard cast).
        if not cdData.isActive then return end
        local durObj = C_Spell.GetSpellCooldownDuration(GCD_SPELL)
        if durObj then gcdRing:StartRingFromDuration(durObj, 1.6) end
    elseif skinData and skinData > 0 and skinData <= 1.6 and s and s > 0 then
        gcdRing:StartRing(GetTime() - s, skinData)
    end
end

local function CreateGCDCircle()
    if gcdRoot then return end
    local gcdCfg = GcdCfg()
    local ringRadius = (gcdCfg.radius or 30)
    local region, newG, b = ParseHex(gcdCfg.hex)
    local a = (gcdCfg.alpha or 100) / 100

    gcdRoot = CreateFrame("Frame", "ECL_GCDRoot", UIParent)
    gcdRoot:SetSize(ringRadius * 2, ringRadius * 2)
    gcdRoot:SetFrameStrata("TOOLTIP")
    gcdRoot:SetFrameLevel(9990)
    gcdRoot:EnableMouse(false)
    gcdRoot:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

    gcdRing = CreateRing(gcdRoot, ringRadius, gcdCfg.ringTex or "normal", region, newG, b, a)

    -- GCD event handling
    gcdRoot:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    gcdRoot:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
    gcdRoot:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
    gcdRoot:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
    gcdRoot:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
    gcdRoot:SetScript("OnEvent", function(self, evt, unitToken, _, spellId)
        if unitToken ~= "player" then return end
        local g2 = GcdCfg()
        if not g2.enabled then return end
        if g2.instanceOnly and not InRealInstancedContent() then return end
        if g2.combatOnly and not InCombatLockdown() then return end
        -- On cancelled/failed/interrupted casts the GCD resets stop the ring
        if
            evt == "UNIT_SPELLCAST_FAILED"
            or evt == "UNIT_SPELLCAST_INTERRUPTED"
            or evt == "UNIT_SPELLCAST_STOP"
        then
            local cdData = GetSpellCooldown(GCD_SPELL)
            local stillActive = false
            if cdData then
                -- A secret read (restricted combat) keeps the ring: the GCD may still
                -- be running (same rule as the Resource Bars GCD bar stop handler).
                local skinData, s = cdData.duration, cdData.startTime
                if issecretvalue(skinData) or issecretvalue(s) then
                    stillActive = true
                else
                    stillActive = (skinData and skinData > 0 and s and s > 0) and true or false
                end
            end
            if not stillActive then gcdRing:StopRing() end
            return
        end
        ArmGCDRing()
    end)

    gcdRoot:Hide()
end

local function PaintGcdCircle()
    local gcdCfg = GcdCfg()
    local enabled = gcdCfg.enabled
    if not enabled then
        if gcdRoot then
            gcdRoot:Hide()
            gcdRoot:SetScript("OnUpdate", nil)
            gcdRoot:UnregisterAllEvents()
        end
        return
    end
    if not gcdRoot then CreateGCDCircle() end
    -- Re-register events in case they were unregistered when disabled
    gcdRoot:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    gcdRoot:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
    gcdRoot:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
    gcdRoot:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
    gcdRoot:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
    local attached = gcdCfg.attached ~= false -- default true
    local ringRadius = gcdCfg.radius or 30
    local zoom = (gcdCfg.scale or 100) / 100
    -- ResolveColor picks accent > class > custom hex automatically
    local region, newG, b = ResolveColor(gcdCfg)
    local a = (gcdCfg.alpha or 100) / 100

    gcdAttached = attached
    gcdRoot:SetScale(zoom)
    gcdRing:SetRingColor(region, newG, b, a)
    gcdRing:SetRingRadius(ringRadius)
    gcdRing:SetRingTexture(gcdCfg.ringTex or "normal")
    gcdRoot:SetSize(ringRadius * 2, ringRadius * 2)

    gcdRoot:Show()
    -- Respect instance-only: hide if not in instance
    if gcdCfg.instanceOnly and not InRealInstancedContent() then gcdRoot:Hide() end
    -- Respect combat-only: hide if not in combat
    if gcdCfg.combatOnly and not InCombatLockdown() then gcdRoot:Hide() end
    if attached and not CUI._unlockActive then
        -- When the cursor circle is visible, anchor directly to it.
        -- When the cursor circle is hidden (e.g. instance-only outside an instance),
        -- the cursor frame's OnUpdate stops firing so it no longer tracks the mouse.
        -- In that case we give the GCD circle its own cursor-tracking OnUpdate.
        local cursorShown = frame and frame:IsShown()
        if cursorShown then
            gcdRoot:SetScript("OnUpdate", nil)
            gcdRoot:ClearAllPoints()
            gcdRoot:SetPoint("CENTER", frame, "CENTER", 0, 0)
        else
            gcdRoot:ClearAllPoints()
            gcdRoot:SetPoint("CENTER", UIParent, "BOTTOMLEFT", 0, 0)
            local uiScale = UIParent:GetEffectiveScale()
            local cursorX, cursorY = GetCursorPosition()
            gcdRoot:SetPoint(
                "CENTER",
                UIParent,
                "BOTTOMLEFT",
                floor(cursorX / uiScale + 0.5),
                floor(cursorY / uiScale + 0.5)
            )
            gcdRoot:SetScript("OnUpdate", function()
                local castColor = UIParent:GetEffectiveScale()
                local mouseX, mouseY = GetCursorPosition()
                gcdRoot:ClearAllPoints()
                gcdRoot:SetPoint(
                    "CENTER",
                    UIParent,
                    "BOTTOMLEFT",
                    floor(mouseX / castColor + 0.5),
                    floor(mouseY / castColor + 0.5)
                )
            end)
        end
    else
        gcdRoot:SetScript("OnUpdate", nil)
        -- Skip repositioning during unlock mode (mover owns position)
        if not CUI._unlockActive then _G._CUCL_ApplyGCDPosition() end
    end
end

-------------------------------------------------------------------------------
--  Cast Bar Circle
-------------------------------------------------------------------------------
local castRoot, castRing
local castAttached = true

local function Cast_DB()
    local profile = ECL.db and ECL.db.profile
    return profile and profile.castCircle or {}
end

-- Defined here so it closes over the real trailEnabled, HideTrailDots,
-- gcdRoot, GCD_DB, castRoot, and Cast_DB locals declared above.
UpdateVisibility = function()
    if not frame then return end
    local p = ECL.db.profile
    local showIt = (p.enabled ~= false)
    if showIt and p.instanceOnly then showIt = InRealInstancedContent() end
    -- "Combat Only": only show while the player is in combat. The combat-edge
    -- events driving this are registered only while a toggle is on
    -- (ApplyCombatOnlyEvents).
    if showIt and p.combatOnly then showIt = InCombatLockdown() and true or false end
    -- Standard visibility options (returns true if should HIDE)
    if showIt and CUI.CheckVisibilityOptions(p) then showIt = false end
    -- Standard visibility mode (mouseover treated as always for cursor)
    if showIt then
        local mode = p.visibility or "always"
        if mode == "never" then
            showIt = false
        elseif mode == "in_combat" then
            showIt = _G._CUBS_InCombat and _G._CUBS_InCombat() or false
        elseif mode == "out_of_combat" then
            showIt = not (_G._CUBS_InCombat and _G._CUBS_InCombat())
        elseif mode == "in_raid" then
            showIt = IsInRaid()
        elseif mode == "in_party" then
            showIt = IsInGroup() and not IsInRaid()
        elseif mode == "solo" then
            showIt = not IsInGroup()
            -- "always" and "mouseover" both show (cursor is always at mouse)
        end
    end
    -- "Only Show When Hidden": only show while steering the camera/character with
    -- the mouse (cursor hidden). mouselookActive is maintained by the world mouse-
    -- handler hooks (CameraOrSelectOrMove / TurnOrAction) further below.
    if showIt and p.onlyWhenHidden and not mouselooking then showIt = false end
    if showIt and not visible then
        visible = true
        -- Snap to the current cursor BEFORE showing, otherwise the frame flashes
        -- at its last (stale) position for one frame -- the glue only repositions
        -- on the following motion sample.
        local uiScale = UIParent:GetEffectiveScale()
        local cursorX, cursorY = GetCursorPosition()
        cursorX, cursorY = floor(cursorX / uiScale + 0.5), floor(cursorY / uiScale + 0.5)
        lastX, lastY = cursorX, cursorY
        frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cursorX, cursorY)
        frame:Show()
        GlueToCursor(true)
    elseif not showIt and visible then
        visible = false
        frame:Hide()
        GlueToCursor(false)
    end

    -- Trail: hide dots and suppress spawning when circle is hidden
    if not showIt and trailOn then HideTrailDots() end

    -- GCD circle instance-only / combat-only check
    if gcdRoot then
        local gcdCfg = GcdCfg()
        if gcdCfg.enabled then
            if
                (gcdCfg.instanceOnly and not InRealInstancedContent())
                or (gcdCfg.combatOnly and not InCombatLockdown())
            then
                gcdRoot:Hide()
                gcdRoot:SetScript("OnUpdate", nil)
            else
                gcdRoot:Show()
                -- Combat Only: the pull cast lands before combat starts, so the
                -- OnEvent gate dropped its GCD; pick up whatever of it remains
                if gcdCfg.combatOnly and gcdRing and gcdRing.maxDur <= 0 then ArmGCDRing() end
                -- Re-apply cursor tracking since cursor visibility may have changed.
                -- Skip while unlocked: the mover owns position, and re-arming this
                -- would fight it (see the same gate in ApplyGCDCircle).
                if gcdCfg.attached ~= false and not CUI._unlockActive then
                    local cursorShown = frame and frame:IsShown()
                    if cursorShown then
                        gcdRoot:SetScript("OnUpdate", nil)
                        gcdRoot:ClearAllPoints()
                        gcdRoot:SetPoint("CENTER", frame, "CENTER", 0, 0)
                    else
                        gcdRoot:SetScript("OnUpdate", function()
                            local castColor = UIParent:GetEffectiveScale()
                            local mouseX, mouseY = GetCursorPosition()
                            gcdRoot:ClearAllPoints()
                            gcdRoot:SetPoint(
                                "CENTER",
                                UIParent,
                                "BOTTOMLEFT",
                                floor(mouseX / castColor + 0.5),
                                floor(mouseY / castColor + 0.5)
                            )
                        end)
                    end
                elseif gcdCfg.attached ~= false then
                    gcdRoot:SetScript("OnUpdate", nil)
                end
            end
        end
    end

    -- Cast circle instance-only / combat-only check
    if castRoot then
        local cfg = Cast_DB()
        if cfg.enabled then
            if
                (cfg.instanceOnly and not InRealInstancedContent())
                or (cfg.combatOnly and not InCombatLockdown())
            then
                castRoot:Hide()
                castRoot:SetScript("OnUpdate", nil)
            else
                castRoot:Show()
                -- Re-apply cursor tracking since cursor visibility may have changed.
                -- Skip while unlocked: the mover owns position, and re-arming this
                -- would fight it (see the same gate in ApplyCastCircle).
                if cfg.attached ~= false and not CUI._unlockActive then
                    local cursorShown = frame and frame:IsShown()
                    if cursorShown then
                        castRoot:SetScript("OnUpdate", nil)
                        castRoot:ClearAllPoints()
                        castRoot:SetPoint("CENTER", frame, "CENTER", 0, 0)
                    else
                        castRoot:SetScript("OnUpdate", function()
                            local castColor = UIParent:GetEffectiveScale()
                            local mouseX, mouseY = GetCursorPosition()
                            castRoot:ClearAllPoints()
                            castRoot:SetPoint(
                                "CENTER",
                                UIParent,
                                "BOTTOMLEFT",
                                floor(mouseX / castColor + 0.5),
                                floor(mouseY / castColor + 0.5)
                            )
                        end)
                    end
                elseif cfg.attached ~= false then
                    castRoot:SetScript("OnUpdate", nil)
                end
            end
        end
    end
end

-------------------------------------------------------------------------------
--  "Only Show When Hidden"
--  Show the cursor circle only while the player is steering the camera/character
--  with the mouse (cursor hidden), and NOT on UI clicks. We post-hook WoW's world
--  mouse handlers, which the game calls ONLY for presses on the 3D world (never
--  for UI -- confirmed: dragging a UI frame fires neither):
--    * Left on the world  -> CameraOrSelectOrMoveStart / ...Stop
--    * Right (turn/move)  -> TurnOrActionStart / ...Stop
--  The cursor position freezes while hidden, so "moving vs static" can't be read;
--  instead a press must be HELD past HOLD_DELAY to count, which ignores quick
--  clicks and leaves only sustained pans/turns. Event + one-shot-timer driven
--  (no per-frame polling); the hooks no-op unless the option is enabled.
-------------------------------------------------------------------------------
local mouselookOn = false
local mlLeftWorld, mlRight = false, false -- a world left / right control is active
local mlPending = false -- a delayed show is scheduled
local MS_HOLD_DELAY = 0.15 -- hold this long before it counts as a pan (not a click)

local function ML_Show()
    mlPending = false
    if mouselookOn and (mlLeftWorld or mlRight) and not mouselooking then
        mouselooking = true
        UpdateVisibility()
    end
end

local function ML_ControlStart()
    if not mouselookOn or mouselooking or mlPending then return end
    mlPending = true
    C_Timer.After(MS_HOLD_DELAY, ML_Show)
end

local function ML_ControlStop()
    if mouselookOn and not (mlLeftWorld or mlRight) and mouselooking then
        mouselooking = false
        UpdateVisibility()
    end
end

local mlHooked = false
local function ML_InstallHooks()
    if mlHooked then return end
    mlHooked = true
    if type(CameraOrSelectOrMoveStart) == "function" then
        hooksecurefunc("CameraOrSelectOrMoveStart", function()
            mlLeftWorld = true
            ML_ControlStart()
        end)
        hooksecurefunc("CameraOrSelectOrMoveStop", function()
            mlLeftWorld = false
            ML_ControlStop()
        end)
    end
    if type(TurnOrActionStart) == "function" then
        hooksecurefunc("TurnOrActionStart", function()
            mlRight = true
            ML_ControlStart()
        end)
        hooksecurefunc("TurnOrActionStop", function()
            mlRight = false
            ML_ControlStop()
        end)
    end
end

local function ApplyOnlyWhenHidden()
    local profile = ECL.db and ECL.db.profile
    mouselookOn = profile and profile.onlyWhenHidden or false
    if mouselookOn then
        ML_InstallHooks() -- hooksecurefunc can't be undone; install once, gate by mlFeatureOn
    else
        mlLeftWorld, mlRight, mlPending = false, false, false
        mouselooking = false
    end
    UpdateVisibility()
end

local function CreateCastCircle()
    if castRoot then return end
    local cfg = Cast_DB()
    local ringRadius = (cfg.radius or 36)
    local region, newG, b = ParseHex(cfg.hex)
    local a = (cfg.alpha or 100) / 100

    castRoot = CreateFrame("Frame", "ECL_CastRoot", UIParent)
    castRoot:SetSize(ringRadius * 2, ringRadius * 2)
    castRoot:SetFrameStrata("TOOLTIP")
    castRoot:SetFrameLevel(9988)
    castRoot:EnableMouse(false)
    castRoot:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

    castRing = CreateRing(castRoot, ringRadius, cfg.ringTex or "normal", region, newG, b, a)

    -- Spark textures: main spark + glow layer for vibrancy
    local sparkLayer = CreateFrame("Frame", nil, castRoot)
    sparkLayer:SetAllPoints(castRoot)
    sparkLayer:SetFrameLevel(castRoot:GetFrameLevel() + 3)

    -- Primary spark
    castRoot._spark = sparkLayer:CreateTexture(nil, "OVERLAY")
    castRoot._spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    castRoot._spark:SetBlendMode("ADD")
    castRoot._spark:SetSize(ringRadius * 0.6, ringRadius * 0.6)
    castRoot._spark:Hide()

    -- Glow layer: a second additive spark, slightly larger and softer, for bloom
    castRoot._sparkGlow = sparkLayer:CreateTexture(nil, "OVERLAY", nil, -1)
    castRoot._sparkGlow:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    castRoot._sparkGlow:SetBlendMode("ADD")
    castRoot._sparkGlow:SetSize(ringRadius * 0.9, ringRadius * 0.9)
    castRoot._sparkGlow:SetAlpha(0.5)
    castRoot._sparkGlow:Hide()

    -- Spark position updater: orbits the ring centerline each frame
    sparkLayer:SetScript("OnUpdate", function()
        local sparkTex = castRoot._spark
        local glow = castRoot._sparkGlow
        if not sparkTex or not sparkTex:IsShown() then return end
        local dur, maxDur = castRing.dur, castRing.maxDur
        if not dur or not maxDur or maxDur <= 0 then
            sparkTex:Hide()
            if glow then glow:Hide() end
            return
        end
        local percent = dur / maxDur
        if percent <= 0 or percent >= 1 then
            sparkTex:Hide()
            if glow then glow:Hide() end
            return
        end

        local castCfg = Cast_DB()
        local ringRadius = castCfg.radius or 36
        -- Approximate inner radius ratio per ring texture for spark orbit
        local RING_INNER = { thin = 0.92, light = 0.85, normal = 0.78, heavy = 0.68, thick = 0.58 }
        local innerRatio = RING_INNER[castCfg.ringTex or "normal"] or 0.78
        local sparkOrbitR = ringRadius * (1 + innerRatio) * 0.5

        local angleDegrees = 90 - (percent * 360)
        local sx = cos(angleDegrees) * sparkOrbitR
        local sy = sin(angleDegrees) * sparkOrbitR

        sparkTex:ClearAllPoints()
        sparkTex:SetPoint("CENTER", castRoot, "CENTER", sx, sy)
        sparkTex:SetRotation(math.rad(angleDegrees - 90))

        if glow then
            glow:ClearAllPoints()
            glow:SetPoint("CENTER", castRoot, "CENTER", sx, sy)
            glow:SetRotation(math.rad(angleDegrees - 90))
        end
    end)

    -- Cast event handling
    castRoot:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
    castRoot:RegisterUnitEvent("UNIT_SPELLCAST_DELAYED", "player")
    castRoot:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
    castRoot:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
    castRoot:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
    castRoot:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
    castRoot:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_UPDATE", "player")
    castRoot:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
    if UnitChannelInfo and GetUnitEmpowerHoldAtMaxTime then
        castRoot:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_START", "player")
        castRoot:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_UPDATE", "player")
        castRoot:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_STOP", "player")
    end

    castRoot._castID = nil

    castRoot:SetScript("OnEvent", function(self, evt, unitToken, castID)
        if unitToken ~= "player" then return end
        local castCfg = Cast_DB()
        if not castCfg.enabled then return end
        if castCfg.instanceOnly and not InRealInstancedContent() then return end
        if castCfg.combatOnly and not InCombatLockdown() then return end

        if evt == "UNIT_SPELLCAST_START" or evt == "UNIT_SPELLCAST_DELAYED" then
            local label, _, _, startMS, endMs, _, cID = UnitCastingInfo("player")
            if label then
                self._castID = cID
                local timePassed = GetTime() - startMS * 0.001
                local sum = (endMs - startMS) * 0.001
                castRing:StartRing(timePassed, sum)
                if castCfg.sparkEnabled then
                    if self._spark then self._spark:Show() end
                    if self._sparkGlow then self._sparkGlow:Show() end
                end
            end
        elseif
            evt == "UNIT_SPELLCAST_CHANNEL_START"
            or evt == "UNIT_SPELLCAST_CHANNEL_UPDATE"
            or evt == "UNIT_SPELLCAST_EMPOWER_START"
            or evt == "UNIT_SPELLCAST_EMPOWER_UPDATE"
        then
            local label, _, _, startMS, endMs, _, _, _, _, numStages = UnitChannelInfo("player")
            if label then
                self._castID = nil
                if numStages and numStages > 0 and GetUnitEmpowerHoldAtMaxTime then
                    endMs = endMs + GetUnitEmpowerHoldAtMaxTime("player")
                end
                local timePassed = GetTime() - startMS * 0.001
                local sum = (endMs - startMS) * 0.001
                castRing:StartRing(timePassed, sum)
                if castCfg.sparkEnabled then
                    if self._spark then self._spark:Show() end
                    if self._sparkGlow then self._sparkGlow:Show() end
                end
            end
        elseif evt == "UNIT_SPELLCAST_STOP" then
            if castID == self._castID then
                self._castID = nil
                castRing:StopRing()
                if self._spark then self._spark:Hide() end
                if self._sparkGlow then self._sparkGlow:Hide() end
            end
        else -- FAILED, INTERRUPTED, CHANNEL_STOP, EMPOWER_STOP
            if not castID or castID == self._castID then
                self._castID = nil
                castRing:StopRing()
                if self._spark then self._spark:Hide() end
                if self._sparkGlow then self._sparkGlow:Hide() end
            end
        end
    end)

    castRoot:Hide()
end

local function PaintCastCircle()
    local cfg = Cast_DB()
    local enabled = cfg.enabled
    if not enabled then
        if castRoot then
            castRoot:Hide()
            castRoot:SetScript("OnUpdate", nil)
            castRoot:UnregisterAllEvents()
        end
        return
    end
    if not castRoot then CreateCastCircle() end
    -- Re-register events in case they were unregistered when disabled
    castRoot:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
    castRoot:RegisterUnitEvent("UNIT_SPELLCAST_DELAYED", "player")
    castRoot:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
    castRoot:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
    castRoot:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
    castRoot:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
    castRoot:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_UPDATE", "player")
    castRoot:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
    if UnitChannelInfo and GetUnitEmpowerHoldAtMaxTime then
        castRoot:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_START", "player")
        castRoot:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_UPDATE", "player")
        castRoot:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_STOP", "player")
    end
    local attached = cfg.attached ~= false -- default true
    local ringRadius = cfg.radius or 36
    local zoom = (cfg.scale or 100) / 100
    -- ResolveColor picks accent > class > custom hex automatically
    local region, newG, b = ResolveColor(cfg)
    local a = (cfg.alpha or 100) / 100

    castAttached = attached
    castRoot:SetScale(zoom)
    castRing:SetRingColor(region, newG, b, a)
    castRing:SetRingRadius(ringRadius)
    castRing:SetRingTexture(cfg.ringTex or "normal")
    castRoot:SetSize(ringRadius * 2, ringRadius * 2)

    -- Spark settings
    if castRoot._spark then
        local sparkSize = ringRadius * 0.6
        castRoot._spark:SetSize(sparkSize, sparkSize)
        if cfg.sparkEnabled then
            local sr, sg, scrollBar
            -- In accent or class mode, the spark inherits the ring color.
            -- In custom mode, the spark uses its own sparkHex (or falls
            -- back to the ring hex if sparkHex isn't set).
            if cfg.useAccentColor or cfg.useClassColor then
                sr, sg, scrollBar = region, newG, b
            else
                sr, sg, scrollBar = ParseHex(cfg.sparkHex or cfg.hex)
            end
            castRoot._spark:SetVertexColor(sr, sg, scrollBar, 1)
            -- Glow layer: same color, slightly transparent for bloom
            if castRoot._sparkGlow then
                castRoot._sparkGlow:SetVertexColor(sr, sg, scrollBar, 1)
                castRoot._sparkGlow:SetSize(ringRadius * 0.9, ringRadius * 0.9)
                castRoot._sparkGlow:SetAlpha(0.5)
            end
        end
    end

    castRoot:Show()
    -- Respect instance-only: hide if not in instance
    if cfg.instanceOnly and not InRealInstancedContent() then castRoot:Hide() end
    -- Respect combat-only: hide if not in combat
    if cfg.combatOnly and not InCombatLockdown() then castRoot:Hide() end
    if attached and not CUI._unlockActive then
        -- When the cursor circle is visible, anchor directly to it.
        -- When the cursor circle is hidden (e.g. instance-only outside an instance),
        -- the cursor frame's OnUpdate stops firing so it no longer tracks the mouse.
        -- In that case we give the cast circle its own cursor-tracking OnUpdate.
        local cursorShown = frame and frame:IsShown()
        if cursorShown then
            castRoot:SetScript("OnUpdate", nil)
            castRoot:ClearAllPoints()
            castRoot:SetPoint("CENTER", frame, "CENTER", 0, 0)
        else
            castRoot:ClearAllPoints()
            castRoot:SetPoint("CENTER", UIParent, "BOTTOMLEFT", 0, 0)
            local uiScale = UIParent:GetEffectiveScale()
            local cursorX, cursorY = GetCursorPosition()
            castRoot:SetPoint(
                "CENTER",
                UIParent,
                "BOTTOMLEFT",
                floor(cursorX / uiScale + 0.5),
                floor(cursorY / uiScale + 0.5)
            )
            castRoot:SetScript("OnUpdate", function()
                local castColor = UIParent:GetEffectiveScale()
                local mouseX, mouseY = GetCursorPosition()
                castRoot:ClearAllPoints()
                castRoot:SetPoint(
                    "CENTER",
                    UIParent,
                    "BOTTOMLEFT",
                    floor(mouseX / castColor + 0.5),
                    floor(mouseY / castColor + 0.5)
                )
            end)
        end
    else
        castRoot:SetScript("OnUpdate", nil)
        -- Skip repositioning during unlock mode (mover owns position)
        if not CUI._unlockActive then _G._CUCL_ApplyCastPosition() end
    end
end

-------------------------------------------------------------------------------
--  Unlock Mode registration (for detached GCD / Cast circles)
-------------------------------------------------------------------------------
local function RegisterUnlockElements()
    if not CUI or not CUI.RegisterUnlockElements then return end
    local MK = CUI.MakeUnlockElement

    local elements = {}

    -- Both keys register whenever the module runs and qualify LIVE through
    -- isHidden/getFrame (a circle only has a mover while enabled and detached).
    -- Never unregister a key that can come back: UnregisterUnlockElement runs
    -- PruneStaleLinks, which deletes the key's saved anchor links, so toggling
    -- Attach to Cursor would silently destroy a detached circle's anchor. The
    -- mover sync reads isHidden every pass, and the options setters re-run
    -- this registration on every Attach flip, so the mover follows the toggle
    -- inside an open unlock session too.
    local function GcdIsDetached()
        local g2 = GcdCfg()
        return g2.enabled and g2.attached == false
    end
    local function CastIsDetached()
        local castCfg = Cast_DB()
        return castCfg.enabled and castCfg.attached == false
    end

    do
        elements[#elements + 1] = MK({
            key = "ECL_GCD",
            label = "GCD Circle",
            group = "Cursor Lite",
            order = 500,
            isHidden = function() return not GcdIsDetached() end,
            getFrame = function()
                if not GcdIsDetached() then return nil end
                return gcdRoot
            end,
            getSize = function()
                local g2 = GcdCfg()
                local region = g2.radius or 30
                return region * 2, region * 2
            end,
            setWidth = function(_, wid)
                local profile = ECL.db and ECL.db.profile
                if not profile or not profile.gcd then return end
                local PPg = CUI and CUI.PP
                profile.gcd.radius = math.max(PPg and PPg.Snap(wid / 2) or math.floor(wid / 2 + 0.5), 5)
                PaintGcdCircle()
                if CUI._unlockActive and CUI.RepositionBarToMover then
                    CUI.RepositionBarToMover("ECL_GCD")
                end
            end,
            setHeight = function(_, hgt)
                local profile = ECL.db and ECL.db.profile
                if not profile or not profile.gcd then return end
                local PPg = CUI and CUI.PP
                profile.gcd.radius = math.max(PPg and PPg.Snap(hgt / 2) or math.floor(hgt / 2 + 0.5), 5)
                PaintGcdCircle()
                if CUI._unlockActive and CUI.RepositionBarToMover then
                    CUI.RepositionBarToMover("ECL_GCD")
                end
            end,
            savePos = function(key, anchorPoint, relPoint, posX, posY)
                local profile = ECL.db and ECL.db.profile
                if not profile then return end
                if not profile.gcd then profile.gcd = {} end
                profile.gcd.pos = { point = anchorPoint, relPoint = relPoint, x = posX, y = posY }
                if not CUI._unlockActive then PaintGcdCircle() end
            end,
            loadPos = function()
                local g2 = GcdCfg()
                return g2.pos
            end,
            clearPos = function()
                local profile = ECL.db and ECL.db.profile
                if profile and profile.gcd then profile.gcd.pos = nil end
            end,
            applyPos = function() _G._CUCL_ApplyGCDPosition() end,
        })
    end

    do
        elements[#elements + 1] = MK({
            key = "ECL_Cast",
            label = "Cast Bar Circle",
            group = "Cursor Lite",
            order = 501,
            isHidden = function() return not CastIsDetached() end,
            getFrame = function()
                if not CastIsDetached() then return nil end
                return castRoot
            end,
            getSize = function()
                local castCfg = Cast_DB()
                local region = castCfg.radius or 36
                return region * 2, region * 2
            end,
            setWidth = function(_, wid)
                local profile = ECL.db and ECL.db.profile
                if not profile or not profile.castCircle then return end
                local PPc = CUI and CUI.PP
                profile.castCircle.radius =
                    math.max(PPc and PPc.Snap(wid / 2) or math.floor(wid / 2 + 0.5), 5)
                PaintCastCircle()
                CUI.RepositionBarToMover("ECL_Cast")
            end,
            setHeight = function(_, hgt)
                local profile = ECL.db and ECL.db.profile
                if not profile or not profile.castCircle then return end
                local PPc = CUI and CUI.PP
                profile.castCircle.radius =
                    math.max(PPc and PPc.Snap(hgt / 2) or math.floor(hgt / 2 + 0.5), 5)
                PaintCastCircle()
                CUI.RepositionBarToMover("ECL_Cast")
            end,
            savePos = function(key, anchorPoint, relPoint, posX, posY)
                local profile = ECL.db and ECL.db.profile
                if not profile then return end
                if not profile.castCircle then profile.castCircle = {} end
                profile.castCircle.pos = { point = anchorPoint, relPoint = relPoint, x = posX, y = posY }
                if not CUI._unlockActive then PaintCastCircle() end
            end,
            loadPos = function()
                local castCfg = Cast_DB()
                return castCfg.pos
            end,
            clearPos = function()
                local profile = ECL.db and ECL.db.profile
                if profile and profile.castCircle then profile.castCircle.pos = nil end
            end,
            applyPos = function() _G._CUCL_ApplyCastPosition() end,
        })
    end

    if #elements > 0 then CUI:RegisterUnlockElements(elements, "CludesUIQoL") end
end

-- Position apply helpers (called from unlock mode and from ApplyGCDCircle/ApplyCastCircle)
_G._CUCL_ApplyGCDPosition = function()
    if not gcdRoot then return end
    -- Skip for unlock-anchored elements (anchor system is authority)
    local anchored = CUI and CUI.IsUnlockAnchored and CUI.IsUnlockAnchored("ECL_GCD")
    if anchored and gcdRoot:GetLeft() then return end
    local gcdCfg = GcdCfg()
    local place = gcdCfg.pos
    if place and place.point then
        local pixel, py = place.x or 0, place.y or 0
        local PPa = CUI and CUI.PP
        if PPa then
            local effScale = gcdRoot:GetEffectiveScale()
            local isCenterAnchor = (place.point == "CENTER")
                and (place.relPoint == "CENTER" or place.relPoint == nil)
            if isCenterAnchor and PPa.SnapCenterForDim then
                pixel = PPa.SnapCenterForDim(pixel, gcdRoot:GetWidth() or 0, effScale)
                py = PPa.SnapCenterForDim(py, gcdRoot:GetHeight() or 0, effScale)
            elseif PPa.SnapForES then
                pixel = PPa.SnapForES(pixel, effScale)
                py = PPa.SnapForES(py, effScale)
            end
        end
        gcdRoot:ClearAllPoints()
        gcdRoot:SetPoint(place.point, UIParent, place.relPoint or place.point, pixel, py)
    else
        -- Default: screen center
        gcdRoot:ClearAllPoints()
        gcdRoot:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

_G._CUCL_ApplyCastPosition = function()
    if not castRoot then return end
    -- Skip for unlock-anchored elements (anchor system is authority)
    local anchored = CUI and CUI.IsUnlockAnchored and CUI.IsUnlockAnchored("ECL_Cast")
    if anchored and castRoot:GetLeft() then return end
    local cfg = Cast_DB()
    local place = cfg.pos
    if place and place.point then
        local pixel, py = place.x or 0, place.y or 0
        local PPa = CUI and CUI.PP
        if PPa then
            local effScale = castRoot:GetEffectiveScale()
            local isCenterAnchor = (place.point == "CENTER")
                and (place.relPoint == "CENTER" or place.relPoint == nil)
            if isCenterAnchor and PPa.SnapCenterForDim then
                pixel = PPa.SnapCenterForDim(pixel, castRoot:GetWidth() or 0, effScale)
                py = PPa.SnapCenterForDim(py, castRoot:GetHeight() or 0, effScale)
            elseif PPa.SnapForES then
                pixel = PPa.SnapForES(pixel, effScale)
                py = PPa.SnapForES(py, effScale)
            end
        end
        castRoot:ClearAllPoints()
        castRoot:SetPoint(place.point, UIParent, place.relPoint or place.point, pixel, py)
    else
        -- Default: screen center
        castRoot:ClearAllPoints()
        castRoot:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

-- Combat-edge events exist only while some Combat Only toggle is on: the
-- cursor circle is default-enabled, so unconditional PLAYER_REGEN_*
-- registrations would run the visibility pass on every combat edge for every
-- user. Re-evaluated from OnEnable and the three options setters; Lite's
-- UnregisterEvent is nil-safe, the _combatEventsOn latch skips no-op flips.
local function ApplyCombatOnlyEvents()
    local profile = ECL.db and ECL.db.profile
    local wanted = (
        profile
        and (
            profile.combatOnly
            or (profile.gcd and profile.gcd.combatOnly)
            or (profile.castCircle and profile.castCircle.combatOnly)
        )
    )
            and true
        or false
    if wanted == ECL._combatEventsOn then return end
    ECL._combatEventsOn = wanted
    if wanted then
        ECL:RegisterEvent("PLAYER_REGEN_DISABLED", UpdateVisibility)
        ECL:RegisterEvent("PLAYER_REGEN_ENABLED", UpdateVisibility)
    else
        ECL:UnregisterEvent("PLAYER_REGEN_DISABLED")
        ECL:UnregisterEvent("PLAYER_REGEN_ENABLED")
    end
end

-------------------------------------------------------------------------------
--  Initialization
-------------------------------------------------------------------------------
function ECL:OnInitialize()
    -- Cursor owns its own slice of CludesUIQoLDB at profile.cursor
    local cursorDefaults = {
        profile = {
            cursor = {
                enabled = true,
                instanceOnly = false,
                onlyWhenHidden = false,
                combatOnly = false,
                useClassColor = true,
                hex = "4CC9F0",
                texture = "ring_normal",
                scale = 1,
                alpha = 100,
                gcd = {
                    enabled = false,
                    attached = true,
                    radius = 21,
                    ringTex = "light",
                    scale = 100,
                    hex = "FFFFFF",
                    alpha = 80,
                    useClassColor = false,
                    instanceOnly = false,
                    combatOnly = false,
                },
                castCircle = {
                    enabled = false,
                    attached = true,
                    radius = 30,
                    ringTex = "normal",
                    scale = 100,
                    hex = "3FA7FF",
                    alpha = 80,
                    sparkEnabled = true,
                    sparkHex = nil,
                    useClassColor = true,
                    instanceOnly = false,
                    combatOnly = false,
                },
                trail = false,
                reticle = false,
                visibility = "always",
                visOnlyInstances = false,
                visHideHousing = false,
                visHideMounted = false,
                visHideNoTarget = false,
                visHideNoEnemy = false,
            },
        },
    }
    local sharedDB = CUI.Lite.NewDB("CludesUIQoLDB", cursorDefaults)
    -- Narrow view onto the cursor sub-table so legacy code using
    -- self.db.profile.<key> keeps working without rewrites.
    -- profile is resolved DYNAMICALLY so it follows profile swaps. The profile
    -- system repoints the registered sharedDB.profile in place (RepointAllDBs);
    -- a frozen `profile = sharedDB.profile.cursor` reference would go stale after
    -- a swap and the cursor would keep applying the old profile's settings.
    self.db = setmetatable({ _shared = sharedDB }, {
        __index = function(tbl, key)
            if key == "profile" then
                local p = tbl._shared.profile
                if not p.cursor then p.cursor = {} end
                return p.cursor
            end
        end,
    })
    self.db.ResetProfile = function(dbSelf)
        local defaultSet = cursorDefaults.profile.cursor
        wipe(dbSelf.profile)
        for key, val in pairs(defaultSet) do
            if type(val) == "table" then
                dbSelf.profile[key] = {}
                for k2, v2 in pairs(val) do
                    dbSelf.profile[key][k2] = v2
                end
            else
                dbSelf.profile[key] = val
            end
        end
    end

    -- Expose for CUI_QoL_Cursor_Options.lua
    _G._CUCL_AceDB = self.db
    _G._CUCL_Apply = ApplyCursorLook
    _G._CUCL_UpdateVisibility = UpdateVisibility
    _G._CUCL_ApplyCombatOnlyEvents = ApplyCombatOnlyEvents
    CUI.RegisterVisibilityUpdater(UpdateVisibility)
    _G._CUCL_ApplyGCDCircle = PaintGcdCircle
    _G._CUCL_ApplyCastCircle = PaintCastCircle
    _G._CUCL_RegisterUnlock = RegisterUnlockElements
    _G._CUCL_RING_TEXTURES = RING_TEXTURES
    _G._CUCL_ApplyTrail = ApplyTrail
    _G._CUCL_ApplyOnlyWhenHidden = ApplyOnlyWhenHidden
end

function ECL:OnEnable()
    if _G._CUBS_TEMP_DISABLED and _G._CUBS_TEMP_DISABLED.cursor then return end
    frame = CreateFrame("Frame", "CludesUICursorFrame", UIParent)
    frame:SetFrameStrata("TOOLTIP")
    frame:SetFrameLevel(9999)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(false)
    frame:SetPoint("CENTER")

    t = frame:CreateTexture(nil, "OVERLAY")
    t:SetAllPoints(frame)
    t:SetTexture(TEX_CUSTOM)

    -- Center reticle: solid fill through the shared portrait circle mask,
    -- same construction as the patch-notes sidebar dot.
    reticleTex = frame:CreateTexture(nil, "OVERLAY", nil, 1)
    reticleTex:SetPoint("CENTER")
    reticleTex:SetColorTexture(1, 1, 1, 1)
    if reticleTex.SetSnapToPixelGrid then
        reticleTex:SetSnapToPixelGrid(false)
        reticleTex:SetTexelSnappingBias(0)
    end
    local reticleMask = frame:CreateMaskTexture()
    reticleMask:SetTexture(
        "Interface\\AddOns\\CludesUI\\media\\portraits\\circle_mask.tga",
        "CLAMPTOBLACKADDITIVE",
        "CLAMPTOBLACKADDITIVE"
    )
    reticleMask:SetAllPoints(reticleTex)
    reticleTex:AddMaskTexture(reticleMask)
    reticleTex:Hide()

    -- No OnUpdate: the shared cursor service drives positioning. The frame
    -- is SHOWN by default and isVisible initializes TRUE, so the first
    -- UpdateVisibility never takes a show TRANSITION -- subscribe here
    -- explicitly; UpdateVisibility owns both edges from then on.
    GlueToCursor(true)

    ApplyCursorLook()

    -- Repaint when the accent lands: the lifecycle's PLAYER_LOGIN fires
    -- before the core resolves the profile accent, so Apply() above painted
    -- the parse-time fallback and is never called again. Also covers a
    -- mid-session accent change, which nothing pushed to us before.
    CUI.RegAccent({
        type = "callback",
        fn = function()
            local profile = ECL.db and ECL.db.profile
            if not profile then return end
            if profile.useAccentColor then ApplyCursorLook() end
            if profile.gcd and profile.gcd.useAccentColor then PaintGcdCircle() end
            if profile.castCircle and profile.castCircle.useAccentColor then PaintCastCircle() end
        end,
    })

    -- Apply GCD / Cast circles (creates on demand only when enabled)
    C_Timer.After(0.5, function()
        -- Re-apply the circle too: the RegAccent callback only lands if we
        -- registered before the core notified (event-dispatch order, not a
        -- guarantee). This runs past the login resolution either way.
        ApplyCursorLook()
        PaintGcdCircle()
        PaintCastCircle()
        ApplyTrail()
        ApplyOnlyWhenHidden()
        RegisterUnlockElements()

        -- Every _unlockActive check in this file only stops a FUTURE re-arm
        -- of the attached cursor-tracking OnUpdate -- none of them tear down
        -- one that's already running, so hook the real unlock open/close here.
        if CUI and CUI.RegisterUnlockModeListener then
            CUI:RegisterUnlockModeListener("CludesUIQoL_Cursor", function(active)
                if active then
                    if gcdRoot then
                        gcdRoot:SetScript("OnUpdate", nil)
                        if gcdAttached then gcdRoot:Hide() end
                    end
                    if castRoot then
                        castRoot:SetScript("OnUpdate", nil)
                        if castAttached then castRoot:Hide() end
                    end
                else
                    -- Re-apply: an attached circle resumes live cursor
                    -- tracking, a detached one snaps back to its saved spot.
                    PaintGcdCircle()
                    PaintCastCircle()
                end
            end)
        end
    end)

    self:RegisterEvent("PLAYER_ENTERING_WORLD", UpdateVisibility)
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA", UpdateVisibility)
    -- Combat-edge events only while a Combat Only toggle needs them.
    ApplyCombatOnlyEvents()
end
