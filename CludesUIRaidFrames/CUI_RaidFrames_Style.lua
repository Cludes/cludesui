if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_RaidFrames_Style.lua
--
--  The debuff grid layout, right-click camera movement, StyleButton and the
--  secure half of the button setup.
--  Reads the earlier Raid Frames files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._internals
-- CludesUIRaidFrames.lua or an earlier Raid Frames file failed to load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true
-- The options page pool's table (CludesUI_PixelPerfect.lua makes it; the
-- options addon fills it in place): read through this file local, never the
-- public slot.
local POOL = CludesUI._Pool

local floor = math.floor
local max = math.max
local min = math.min
local abs = math.abs
local pairs = pairs
local ipairs = ipairs
local UnitExists = UnitExists
local IsInRaid = IsInRaid
local GetNumGroupMembers = GetNumGroupMembers
local C_Timer = C_Timer
local issecretvalue = issecretvalue
local CreateFrame = CreateFrame

local ApplyFont, defaultSet, GetFFD, PixelSnap =
    Inner.ApplyFont, Inner.defaults, Inner.GetFFD, Inner.PixelSnap
local ResolveHealthTexture, unitToButton = Inner.ResolveHealthTexture, Inner.unitToButton
local CreateAbsorbBar, UpdateAbsorb = Inner.CreateAbsorbBar, Inner.UpdateAbsorb

local saved
Inner.dbSetters[#Inner.dbSetters + 1] = function(val)
    saved = val
end
local Pix
Inner.PPSetters[#Inner.PPSetters + 1] = function(val)
    Pix = val
end

-------------------------------------------------------------------------------
--  Debuff grid layout (shared by the live render and the options preview)
-------------------------------------------------------------------------------
-- Absorb paint coalescer (Blizzard's own CompactUnitFrame model: absorb /
-- heal-prediction repaints are "frequent and expensive, update once per frame
-- at most"). Event branches MARK; the flush paints each dirty button once,
-- at most a budget of them per render frame -- server batches land several
-- absorb-family events per button in one frame at raid scale, and only the
-- last paint renders. The budget is the backstop for a genuine event storm
-- (a raid-wide shield landing on everyone in one frame); the belt below
-- spreads its own marks across ticks so it never fills the budget itself.
-- The flush frame is hidden whenever the set is empty.
mod._abDirty = {}
mod._abFlushBudget = 20
mod._abFlush = CreateFrame("Frame")
mod._abFlush:Hide()
mod._abFlush:SetScript("OnUpdate", function(self)
    local dirty = mod._abDirty
    local leftX = mod._abFlushBudget
    local nowTime = GetTime()
    for btnFrame in pairs(dirty) do
        dirty[btnFrame] = nil
        -- The button's CURRENT occupant, never the token captured at mark
        -- time: a header reassignment between mark and flush would paint the
        -- old occupant's absorb onto the new one.
        local unitToken = btnFrame:GetAttribute("unit")
        if unitToken then
            UpdateAbsorb(btnFrame, unitToken, nowTime)
        end
        leftX = leftX - 1
        if leftX <= 0 then
            break
        end
    end
    -- Leftovers past the budget keep the frame shown for the next frame.
    if next(dirty) == nil then
        self:Hide()
    end
end)
function mod._MarkAbsorbDirty(btnFrame, unitToken)
    -- unit is kept for the callers' convenience; the flush re-reads the
    -- button's current occupant itself.
    mod._abDirty[btnFrame] = true
    mod._abFlush:Show()
end

-- Armed-members belt: covers the ONE transition with no event at all -- an
-- aura-granted shield expiring on its TIMER on an unhit, topped unit (VDH
-- Infernal Strike field report; damaged/healed units correct instantly via
-- the health/absorb events). One shared ticker exists only while some member
-- is armed and cancels itself when the armed set empties. Zero event
-- registrations, zero cost with no shields anywhere.
--
-- STAGGERED: the ticker runs at 0.1s and each tick visits one fifth of the
-- armed set (members whose ordinal in the walk matches the tick's phase), so
-- every member is still visited every 0.5s -- the accepted corner latency --
-- but the marks land in five different render frames instead of one. A
-- single 0.5s sweep re-marked the whole shielded roster at once, and because
-- that painted them together their stamps aged together, locking the burst
-- into a permanent 2 Hz rhythm no drain budget could break. Members painted
-- within 0.45s (event-active) are still skipped by the stamp compare.
-- Membership churn reshuffles the walk order harmlessly: a member is at worst
-- visited twice in a row or waits one extra sweep once.
mod._abArmed = mod._abArmed or {}
mod._abBeltPhase = 0
function mod._AbArm(btnFrame, unitToken, d)
    d._absActive = true
    mod._abArmed[btnFrame] = unitToken
    if not mod._abBelt and C_Timer then
        mod._abBelt = C_Timer.NewTicker(0.1, function()
            local nowTime = GetTime()
            local phase = mod._abBeltPhase
            mod._abBeltPhase = (phase + 1) % 5
            local any = false
            local idx = 0
            for btn, u in pairs(mod._abArmed) do
                any = true
                if idx % 5 == phase then
                    local ab = GetFFD(btn).absorbBar
                    if not ab or (nowTime - (ab._paintAt or 0)) > 0.45 then
                        mod._MarkAbsorbDirty(btn, u)
                    end
                end
                idx = idx + 1
            end
            if not any then
                mod._abBelt:Cancel()
                mod._abBelt = nil
            end
        end)
    end
end

-- Effective icon size for dispellable debuffs routed to their own anchor ("Dispellable Debuff
-- Location"): 0 = match the main Debuff Size. Reads scaled proxies transparently (the key is in
-- INDICATOR_SCALE_KEYS; 0 scales to 0, so the match sentinel survives).
function mod.DispellableDebuffSize(s)
    local val = s.dispellableDebuffSize
    if val and val > 0 then
        return val
    end
    return s.debuffSize or 18
end

-- Grid placement for debuff icons. opts (optional) overrides pos/grow/ox/oy/size for a
-- sub-group (e.g. dispellable debuffs on their own anchor); spacing/wrap/perRow stay shared.
function mod.DebuffGridPoint(s, idx0, sum, options)
    local place = (options and options.pos) or s.debuffPosition or "bottomleft"
    local grow = (options and options.grow) or s.debuffGrowDirection or "RIGHT"
    local sz = PixelSnap((options and options.size) or s.debuffSize or 18)
    local spc = PixelSnap(s.debuffSpacing or 1)
    local step = sz + spc
    local ox = (options and options.ox) or s.debuffOffsetX or 0
    local oy = (options and options.oy) or s.debuffOffsetY or 0
    local perRow = s.debuffPerRow or 1
    if perRow < 1 then
        perRow = 1
    end

    -- Icon corner anchored to the same corner of the health bar. Every position is explicit, so the default fallback is only a safety net.
    local corner = "BOTTOMLEFT"
    if place == "topleft" then
        corner = "TOPLEFT"
    elseif place == "top" then
        corner = "TOP"
    elseif place == "topright" then
        corner = "TOPRIGHT"
    elseif place == "left" then
        corner = "LEFT"
    elseif place == "center" then
        corner = "CENTER"
    elseif place == "right" then
        corner = "RIGHT"
    elseif place == "bottomleft" then
        corner = "BOTTOMLEFT"
    elseif place == "bottom" then
        corner = "BOTTOM"
    elseif place == "bottomright" then
        corner = "BOTTOMRIGHT"
    end

    -- Growth vector (per column within a row), screen coords (+x right, +y up).
    -- CENTER grows horizontally like RIGHT but centers each row on the anchor.
    local horizontal = (grow ~= "UP" and grow ~= "DOWN")
    local gvx, gvy = 0, 0
    if grow == "LEFT" then
        gvx = -1
    elseif grow == "UP" then
        gvy = 1
    elseif grow == "DOWN" then
        gvy = -1
    else
        gvx = 1 -- RIGHT or CENTER
    end

    -- Row-stack vector (perpendicular). CENTER growth stacks away from the
    -- position's own edge (ResolveFlowAnchor parity); wrap has no options
    -- setter and defaults to "UP", so letting it win here put this preview's
    -- rows on the opposite side from the live frame. Otherwise the explicit
    -- wrap direction wins, else derive away from the anchored edge.
    local svx, svy = 0, 0
    local wrap = s.debuffWrapDirection
    local centerSvy
    if grow == "CENTER" then
        if place:find("top", 1, true) then
            centerSvy = -1
        elseif place:find("bottom", 1, true) then
            centerSvy = 1
        end
    end
    if centerSvy then
        svy = centerSvy
    elseif wrap == "UP" then
        svy = 1
    elseif wrap == "DOWN" then
        svy = -1
    elseif wrap == "RIGHT" then
        svx = 1
    elseif wrap == "LEFT" then
        svx = -1
    elseif horizontal then
        if place == "bottomleft" or place == "bottom" or place == "bottomright" then
            svy = 1
        else
            svy = -1
        end
    else
        if place == "topright" or place == "right" or place == "bottomright" then
            svx = -1
        else
            svx = 1
        end
    end

    -- perRow == 1 is a single line ALONG the growth direction (no wrapping), keeping the growth control meaningful; >= 2 wraps into rows.
    local row, col
    if perRow <= 1 then
        row, col = 0, idx0
    else
        row = floor(idx0 / perRow)
        col = idx0 % perRow
    end
    local centerOff = 0
    if grow == "CENTER" then
        local rowCount = (perRow <= 1) and (sum or 0) or min(perRow, max(0, (sum or 0) - row * perRow))
        if rowCount > 0 then
            centerOff = -((rowCount - 1) * step) / 2
        end
    end
    local along = col * step
    local across = row * step
    local fx = ox + gvx * along + svx * across + centerOff
    local fy = oy + gvy * along + svy * across
    return corner, fx, fy
end

-------------------------------------------------------------------------------
--  Right-click camera movement over raid/party frames: a global mouse watcher starts mouselook
--  when the right button is dragged past a small threshold over one of our unit buttons. It never
--  touches the secure buttons (no taint / click-cast interference); a right-click tap still menus.
-------------------------------------------------------------------------------
do
    local MOVE_THRESHOLD = 4
    local watcher = mod.TakeShell()
    local inLook = false
    local lastX, lastY = 0, 0

    local function stopLook()
        if inLook then
            MouselookStop()
            inLook = false
        end
        watcher:SetScript("OnUpdate", nil)
    end

    -- True if the cursor is over one of our visible unit buttons (direct IsMouseOver test against the registry).
    local function overOwnFrame()
        local reg = mod._cuiUnitButtons
        if not reg then
            return false
        end
        for btn in pairs(reg) do
            if btn:IsVisible() and btn:IsMouseOver() then
                return true
            end
        end
        return false
    end

    local function onUpdate()
        if not IsMouseButtonDown(2) then
            stopLook()
            return
        end
        if inLook then
            return
        end
        local posX, posY = GetCursorPosition()
        if abs(posX - lastX) > MOVE_THRESHOLD or abs(posY - lastY) > MOVE_THRESHOLD then
            pcall(MouselookStart)
            inLook = true
        end
    end

    watcher:SetScript("OnEvent", function(_, evt, btnFrame)
        if evt == "GLOBAL_MOUSE_DOWN" then
            if btnFrame ~= "RightButton" then
                return
            end
            if not (saved and saved.profile and saved.profile.freeRightClickCamera) then
                return
            end
            if not overOwnFrame() then
                return
            end
            inLook = false
            lastX, lastY = GetCursorPosition()
            watcher:SetScript("OnUpdate", onUpdate)
        elseif evt == "GLOBAL_MOUSE_UP" then
            if btnFrame == "RightButton" then
                stopLook()
            end
        elseif evt == "PLAYER_REGEN_ENABLED" then
            -- safety: never leave mouselook stuck after a combat-state change
            if not IsMouseButtonDown(2) then
                stopLook()
            end
        elseif evt == "PLAYER_LOGIN" then
            if mod.FRCM_Refresh then
                mod.FRCM_Refresh()
            end
        end
    end)
    watcher:RegisterEvent("PLAYER_LOGIN")

    -- Register the per-click global events only while the feature is on (zero cost when off). Call on toggle.
    function mod.FRCM_Refresh()
        if saved and saved.profile and saved.profile.freeRightClickCamera then
            watcher:RegisterEvent("GLOBAL_MOUSE_DOWN")
            watcher:RegisterEvent("GLOBAL_MOUSE_UP")
            watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
        else
            watcher:UnregisterEvent("GLOBAL_MOUSE_DOWN")
            watcher:UnregisterEvent("GLOBAL_MOUSE_UP")
            watcher:UnregisterEvent("PLAYER_REGEN_ENABLED")
            stopLook()
        end
    end
end

-- Hover/target highlight on a BORDERLESS frame (Border Size 0): the highlight recolors the
-- frame's own border, and with none drawn there is nothing to recolor, so it draws its own at
-- hoverBorderSize/targetBorderSize in the configured border style. `size` nil/0 = not
-- highlighted. `px` = that size's exact pixels (CludesUI.BorderPx of the hover/target
-- companion key against `size` and the drawn texture), nil = the legacy size. The drawn size
-- (and px) is cached on the border frame so a group-wide target swap is a color write per
-- button rather than a restyle; callers clear it when the base border returns.
function mod.ApplyHighlightBorder(bf, s, size, r, g, b, a, px)
    if not (Pix and bf) then
        return
    end
    local texKey = s.borderTexture or "solid"
    if not size or size <= 0 then
        if bf._hlBorderSize then
            CludesUI.ApplyBorderStyle(bf, 0, r, g, b, a, texKey)
            -- Keep the cache when the style call bailed (still shown) so the next one retries the hide.
            if not bf:IsShown() then
                bf._hlBorderSize = nil
            end
        end
        return
    end
    -- IsShown: a base restyle to Border Size 0 hides the frame without clearing the cache,
    -- so the size alone would let a hover/target repaint after one land on a hidden border.
    if bf._hlBorderSize == size and bf._hlBorderPx == px and bf:IsShown() then
        CludesUI.SetBorderStyleColor(bf, r, g, b, a)
        return
    end
    CludesUI.ApplyBorderStyle(
        bf,
        size,
        r,
        g,
        b,
        a,
        texKey,
        s.borderTextureOffset,
        s.borderTextureOffsetY,
        s.borderTextureShiftX,
        s.borderTextureShiftY,
        "unitframes",
        size,
        nil,
        px
    )
    bf._hlBorderSize = size
    bf._hlBorderPx = px
end

-- Hover/target on a drawn border recolors that same border, so a highlight
-- color (nearly) equal to the border's own shows no change at all: every
-- textured style but Pixels seeds a white border and the highlight defaults
-- to white. Such a highlight draws gold instead (white on a gold border).
function mod.RF_VisibleHighlight(s, r, g, b)
    local c = s.borderColor
    local br, backdrop, bb = 0, 0, 0
    if c then
        br, backdrop, bb = c.r, c.g, c.b
    end
    if math.abs(r - br) + math.abs(g - backdrop) + math.abs(b - bb) >= 0.15 then
        return r, g, b
    end
    if math.abs(1 - br) + math.abs(0.82 - backdrop) + math.abs(bb) >= 0.15 then
        return 1, 0.82, 0
    end
    return 1, 1, 1
end

function mod.RF_ColorPowerDivider(host, r, g, b, a)
    if not host or host._powerArtMode ~= "divider" then
        return
    end
    host._powerArtR, host._powerArtG, host._powerArtB, host._powerArtAlpha = r, g, b, a
    host._powerArtTex:SetVertexColor(r, g, b, a)
end

function mod.RF_ClearPowerBorderArt(host)
    if not host or not host._powerArtKey then
        return
    end
    if host._powerArtTex then
        host._powerArtTex:Hide()
    end
    if host._powerArtSeam then
        host._powerArtSeam:Hide()
    end
    CludesUI.HideBorderStyle(host)
    CludesUI.RegisterPxReapply(host, nil)
    Pix.ShowBorder(host)
    host._powerArtKey = nil
    host._powerArtMode = nil
end

function mod.RF_LayoutPowerBorderArt(host)
    if not host:IsShown() or not host._powerArtKey then
        return
    end
    if host._powerArtMode == "border" then
        CludesUI.ApplyBorderStyle(
            host,
            host._powerArtSize,
            host._powerArtR,
            host._powerArtG,
            host._powerArtB,
            host._powerArtAlpha,
            host._powerArtKey,
            host._powerArtOffset,
            host._powerArtOffsetY,
            host._powerArtShiftX,
            host._powerArtShiftY,
            "unitframes",
            host._powerArtSize,
            nil,
            host._powerArtPx
        )
        return
    end
    local seam = host._powerArtSeam
    seam:SetFrameStrata(host:GetFrameStrata())
    seam:SetFrameLevel(host:GetParent():GetFrameLevel() + mod.LVL_TEXT - 1)
    local es = host:GetEffectiveScale()
    if not (es and es > 0.01) then
        es = UIParent:GetEffectiveScale()
    end
    local thick =
        CludesUI.BorderCompanionThickness(host._powerArtKey, host._powerArtSize, host._powerArtPx, es)
    local realPP = CludesUI.PP
    local raise = realPP.SnapForES(thick * 5 / 32, es) - realPP.perfect / es
    local t = host._powerArtTex
    t:ClearAllPoints()
    if host._powerArtEdge == "BOTTOM" then
        t:SetTexCoord(0, 1, 1, 0)
        t:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 0, -raise)
        t:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, -raise)
    else
        t:SetTexCoord(0, 1, 0, 1)
        t:SetPoint("TOPLEFT", host, "TOPLEFT", 0, raise)
        t:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, raise)
    end
    t:SetHeight(thick)
    t:Show()
    seam:Show()
end

-- Settings passes refresh the cached art; ordinary power paints reuse it.
function mod.RF_ApplyPowerBorderArt(host, s, force, preview, nameBar)
    local mode = nameBar and "divider" or (s.powerBorderStyle or "cui")
    local key = (
        (nameBar and s.topNameBarDivider == true) or (not nameBar and s.powerBorderMatchFrame == true)
    )
        and not mod.RF_Stock()
        and s.borderTexture
    if not CludesUI._pixelArtBorders[key] or (mode ~= "divider" and mode ~= "border") then
        mod.RF_ClearPowerBorderArt(host)
        return false
    end
    local size = s.borderSize or 1
    local height = nameBar and (s.topNameBarHeight or 20) or (s.powerHeight or 4)
    if size <= 0 or (mode == "divider" and height < 4) then
        mod.RF_ClearPowerBorderArt(host)
        host:Hide()
        return true
    end
    if
        not force
        and host._powerArtKey == key
        and host._powerArtMode == mode
        and host._powerArtSize == size
    then
        host:Show()
        return true
    end
    CludesUI.HideBorderStyle(host)
    if host._powerArtTex then
        host._powerArtTex:Hide()
    end
    if host._powerArtSeam then
        host._powerArtSeam:Hide()
    end
    host._powerArtKey, host._powerArtMode = key, mode
    host._powerArtEdge = (nameBar and not s.topNameBarBottom) and "BOTTOM" or "TOP"
    host._powerArtSize = size
    host._powerArtPx = CludesUI.BorderPx(s.borderSizePx, size, key)
    local c = s.borderColor
    host._powerArtR, host._powerArtG, host._powerArtB = c and c.r or 0, c and c.g or 0, c and c.b or 0
    host._powerArtAlpha = s.borderAlpha or 1
    host._powerArtOffset, host._powerArtOffsetY = s.borderTextureOffset, s.borderTextureOffsetY
    host._powerArtShiftX, host._powerArtShiftY = s.borderTextureShiftX, s.borderTextureShiftY
    if mode == "divider" then
        local t = host._powerArtTex
        if not t then
            -- On the Buff / Debuff Manager preview (a frame of the options page
            -- pool, CludesUI_FramePool.lua) the seam is pooled with its host
            -- and handed out again by the next build; elsewhere a plain new frame.
            local seam = POOL.CreateFrame("Frame", nil, host)
            seam:SetAllPoints(host)
            host._powerArtSeam = seam
            t = seam:CreateTexture(nil, "ARTWORK")
            Pix.DisablePixelSnap(t)
            host._powerArtTex = t
        end
        t:SetTexture(CludesUI.GetBorderCompanion(key, "sepH"))
        t:SetVertexColor(host._powerArtR, host._powerArtG, host._powerArtB, host._powerArtAlpha)
    end
    host:Show()
    mod.RF_LayoutPowerBorderArt(host)
    CludesUI.RegisterPxReapply(
        host,
        (mode == "divider" and not preview) and mod.RF_LayoutPowerBorderArt or nil
    )
    return true, true
end

function mod.RF_ApplyTopNameDivider(tnb, s, preview)
    local host = tnb._divider
    local key = s.borderTexture
    if
        not Pix
        or not s.topNameBarEnabled
        or s.topNameBarDivider ~= true
        or mod.RF_Stock()
        or not CludesUI._pixelArtBorders[key]
        or (s.borderSize or 1) <= 0
        or (s.topNameBarHeight or 20) < 4
    then
        if host then
            mod.RF_ClearPowerBorderArt(host)
            host:Hide()
        end
        return
    end
    if not host then
        -- Pooled with the options preview's replica, as the seam above.
        host = POOL.CreateFrame("Frame", nil, tnb:GetParent())
        host:SetAllPoints(tnb)
        tnb._divider = host
    end
    mod.RF_ApplyPowerBorderArt(host, s, true, preview, true)
end

-- Unit tooltip and hover border for a raid/party button; the detached
-- portrait's click button replays them (CUI_RaidFrames_Portrait.lua).
local function ButtonOnEnter(self)
    local fd = GetFFD(self)
    fd._hovered = true
    if fd.ApplyBorderColor then
        fd.ApplyBorderColor()
    end
    -- Aura icons enable mouse and propagate motion up to this button, so entering an icon fires
    -- its OnEnter (aura tooltip) then bubbles here, clobbering it with the unit tooltip. Bail
    -- when the cursor is over one of our aura icons (stashed _tipIID).
    local foci = GetMouseFoci()
    if foci then
        for _, mf in ipairs(foci) do
            if mf ~= self and mf._tipIID ~= nil then
                return
            end
        end
    end
    -- Unit-tooltip gating: see ns.RaidFrameTooltipAllowed. It reads through the party-aware
    -- proxy, NOT raw db.profile -- else party_<key> overrides from a custom party
    -- "Range & Tooltip" section are never seen.
    if not mod.RaidFrameTooltipAllowed(self) then
        return
    end
    local u = self:GetAttribute("unit")
    if u and UnitExists(u) then
        GameTooltip_SetDefaultAnchor(GameTooltip, self)
        -- Populate with a freshly-built clean literal token (GUID-matched) rather than the
        -- secure unit attribute: a literal "raidN"/"partyN"/"player" string lacks the
        -- secure-frame origin that makes GameTooltip:GetUnit() return a secret, so external
        -- tooltip addons can resolve the unit. Falls back to the attribute if no clean token.
        local tipText, g = u, UnitGUID(u)
        if g and not (issecretvalue and issecretvalue(g)) then
            if UnitGUID("player") == g then
                tipText = "player"
            elseif IsInRaid() then
                for idx = 1, GetNumGroupMembers() do
                    local tk = "raid" .. idx
                    local tg = UnitGUID(tk)
                    if tg and not (issecretvalue and issecretvalue(tg)) and tg == g then
                        tipText = tk
                        break
                    end
                end
            else
                for idx = 1, GetNumSubgroupMembers() do
                    local tk = "party" .. idx
                    local tg = UnitGUID(tk)
                    if tg and not (issecretvalue and issecretvalue(tg)) and tg == g then
                        tipText = tk
                        break
                    end
                end
            end
        end
        GameTooltip:SetUnit(tipText)
        GameTooltip:Show()
    end
end
local function ButtonOnLeave(self)
    local fd = GetFFD(self)
    fd._hovered = false
    if fd.ApplyBorderColor then
        fd.ApplyBorderColor()
    end
    GameTooltip:Hide()
end
mod.RF_ButtonOnEnter, mod.RF_ButtonOnLeave = ButtonOnEnter, ButtonOnLeave

-------------------------------------------------------------------------------
--  Style a single button (called once per button at creation time)
-------------------------------------------------------------------------------
local function StyleButton(btnFrame)
    local d = GetFFD(btnFrame)
    if d.styled then
        return
    end
    d.styled = true

    -- Register our unit buttons so the free right-click camera watcher can tell when the cursor is
    -- over one. These are SecureGroupHeader/SecureUnitButton frames (Blizzard-owned), so membership
    -- lives in an external weak table, never a key on the button.
    mod._cuiUnitButtons = mod._cuiUnitButtons or setmetatable({}, { __mode = "k" })
    mod._cuiUnitButtons[btnFrame] = true

    local s = saved.profile
    -- The Anchor* closures below are stored on `d` and RE-CALLED after d._isParty / d._isExtra are
    -- set (StyleButton runs before that). They MUST resolve the settings source LIVE via LiveS()
    -- rather than capture this raid `s`, or party/extra frames would anchor every indicator, text
    -- and aura at the RAID position. The body keeps the raw `s` for creation-time sizing.
    local function LiveS()
        return d._isParty and mod._scaledPartyProxy
            or (d._isExtra and mod._scaledExtraProxy)
            or mod._scaledProfile
    end
    local wid = PixelSnap(s.frameWidth or 72)
    local hgt = PixelSnap(s.frameHeight or 46)
    -- The power bar is ALWAYS created (hidden) so a later swap into a power-enabled profile has a
    -- bar to show; UpdateButton drives per-role show/hide + matching health height. Health starts
    -- FULL height, else the bottom powerH strip shows dark bg as an "empty power bar" until the
    -- first UpdateButton (visible ~0.5s at login).
    local powerH = PixelSnap(s.powerHeight or 4)
    local healthH = hgt

    -- No SetSize here: sizing is window-phase work (combat-blocked), owned by
    -- ns._StyleButtonSecure below plus the header's initialConfigFunction.

    -- Background (visible behind the health bar where HP is missing)
    local backdrop = btnFrame:CreateTexture(nil, "BACKGROUND")
    backdrop:SetAllPoints()
    local bgc = s.customBgColor or defaultSet.customBgColor
    backdrop:SetColorTexture(bgc.r, bgc.g, bgc.b, (s.bgDarkness or 50) / 100)
    if Pix then
        Pix.DisablePixelSnap(backdrop)
    end
    d.bg = backdrop

    -- Health bar
    local health = CreateFrame("StatusBar", nil, btnFrame)
    health:SetFrameLevel(btnFrame:GetFrameLevel() + 2)
    health:SetPoint("TOPLEFT", btnFrame, "TOPLEFT", 0, 0)
    health:SetPoint("TOPRIGHT", btnFrame, "TOPRIGHT", 0, 0)
    health:SetHeight(healthH)
    local texPath = ResolveHealthTexture()
    health:SetStatusBarTexture(texPath)
    health:GetStatusBarTexture():SetHorizTile(false)
    if Pix then
        Pix.DisablePixelSnap(health)
    end
    -- Fill axis + inversion. StyleButton runs before d._isParty is set, so these use
    -- the raid values; ReanchorAbsorbToFill re-resolves both against the button's real
    -- settings source each update.
    mod.RF_ApplyHealthOrientation(health, s)
    health:SetMinMaxValues(0, 100)
    health:SetValue(100)
    -- Pre-paint tint: a StatusBar texture renders WHITE (default vertex
    -- color) until the first content paint assigns the real class/reaction
    -- color a few frames after login (the styling drain). Start dark so the
    -- loading shell reads as calm empty frames instead of a flat white flash.
    health:SetStatusBarColor(0.12, 0.12, 0.12)
    d.health = health

    -- Full-height anchor reference for Uniform Icon Anchoring: top tracks the health bar (so the
    -- Top Name Bar inset carries over), bottom pins to the button -- exactly where the health bar
    -- sits with no power bar. ns.RF_AnchorHost swaps decorations onto it; _cuiHealth points back
    -- for the few sites that must hug the real bar (full-overlay BM bars).
    d.uniformRef = CreateFrame("Frame", nil, btnFrame)
    d.uniformRef:SetFrameLevel(health:GetFrameLevel())
    d.uniformRef:SetPoint("TOPLEFT", health, "TOPLEFT", 0, 0)
    d.uniformRef:SetPoint("BOTTOMRIGHT", btnFrame, "BOTTOMRIGHT", 0, 0)
    health._cuiUniformRef = d.uniformRef
    d.uniformRef._cuiHealth = health

    -- Power bar: ALWAYS created, hidden, anchored to the button bottom for pixel alignment;
    -- UpdateButton's per-role gate shows/fills it. Unconditional creation is what lets a
    -- power-OFF login profile swap into a power-ON one.
    do
        local power = CreateFrame("StatusBar", nil, btnFrame)
        power:SetFrameLevel(btnFrame:GetFrameLevel() + 3)
        power:SetPoint("BOTTOMLEFT", btnFrame, "BOTTOMLEFT", 0, 0)
        power:SetPoint("BOTTOMRIGHT", btnFrame, "BOTTOMRIGHT", 0, 0)
        power:SetHeight(powerH)
        power:SetStatusBarTexture(texPath)
        power:GetStatusBarTexture():SetHorizTile(false)
        if Pix then
            Pix.DisablePixelSnap(power)
        end
        power:SetMinMaxValues(0, 1)
        power:SetValue(1)
        -- Pre-paint tint (see the health bar note above).
        power:SetStatusBarColor(0.12, 0.12, 0.12)
        local pwBg = power:CreateTexture(nil, "BACKGROUND")
        pwBg:SetAllPoints()
        pwBg:SetColorTexture(
            (s.powerBgColor or {}).r or 0,
            (s.powerBgColor or {}).g or 0,
            (s.powerBgColor or {}).b or 0,
            (s.powerBgDarkness or 70) / 100
        )
        if Pix then
            Pix.DisablePixelSnap(pwBg)
        end
        d.power = power
        d.powerBg = pwBg

        -- Power border frame
        local pwBdrFrame = CreateFrame("Frame", nil, btnFrame)
        pwBdrFrame:SetAllPoints(power)
        pwBdrFrame:SetFrameLevel(power:GetFrameLevel() + 1)
        if Pix then
            Pix.CreateBorder(pwBdrFrame, 0, 0, 0, 1, 1)
        end
        d.powerBorderFrame = pwBdrFrame

        -- Start hidden; UpdateButton shows it per role (wasShown=false there plain-snaps the first fill, no interpolation).
        power:Hide()
        pwBdrFrame:Hide()
    end

    -- Top Name Bar: ALWAYS created, hidden. The layout/refresh pass sizes, reserves and shows it from settings; UpdateButton sets the text.
    do
        local tnb = CreateFrame("Frame", nil, btnFrame)
        tnb:SetFrameLevel(btnFrame:GetFrameLevel() + 4)
        tnb:SetPoint("TOPLEFT", btnFrame, "TOPLEFT", 0, 0)
        tnb:SetPoint("TOPRIGHT", btnFrame, "TOPRIGHT", 0, 0)
        tnb:SetHeight(PixelSnap(s.topNameBarHeight or 20))
        local tnbBg = tnb:CreateTexture(nil, "BACKGROUND")
        tnbBg:SetAllPoints()
        if Pix then
            Pix.DisablePixelSnap(tnbBg)
        end
        local tnbText = tnb:CreateFontString(nil, "OVERLAY")
        ApplyFont(tnbText, s.topNameBarTextSize or 11)
        tnbText:SetWordWrap(false)
        d.topNameBar = tnb
        d.topNameBarBg = tnbBg
        d.topNameBarText = tnbText
        tnb:Hide()
    end

    -- Absorb shields
    CreateAbsorbBar(btnFrame, health)

    -- Border frame
    local bdrFrame = CreateFrame("Frame", nil, btnFrame)
    bdrFrame:SetAllPoints(btnFrame)
    bdrFrame:SetFrameLevel(btnFrame:GetFrameLevel() + 8)
    d.borderFrame = bdrFrame
    -- Styled via CludesUI.ApplyBorderStyle (PP or textured/SharedMedia) in UpdateBorder.
    -- Hover/Target are color states recolored onto this single border, not separate frames.

    -- Threat border
    local threatFrame = CreateFrame("Frame", nil, btnFrame)
    threatFrame:SetAllPoints(btnFrame)
    threatFrame:SetFrameLevel(btnFrame:GetFrameLevel() + 10)
    threatFrame:Hide()
    d.threatFrame = threatFrame
    if Pix then
        Pix.CreateBorder(threatFrame, 1, 0, 0, 1, 2)
    end

    -- Party Frames kit (the stock portrait party frame, latched): built here,
    -- before every anchor closure below and before the aura containers, so
    -- each of them takes the kit's host and spots from its first call.
    if d._isParty and mod.RF_PartyKit() then
        mod.RF_KitBuild(btnFrame, d, health, d.power, bdrFrame)
    end

    -- Text carrier: the texts in the text band (ns.LVL_TEXT) -- above every border incl.
    -- the raise, below the aura band. Their FontStrings are built on it on first need
    -- (ns.RF_TextLayout, run by AnchorTexts below and by the paints when the settings changed).
    local textCarrier = CreateFrame("Frame", nil, btnFrame)
    textCarrier:SetAllPoints(health)
    textCarrier:SetFrameLevel(btnFrame:GetFrameLevel() + mod.LVL_TEXT)
    d.textCarrier = textCarrier
    -- The second carrier for texts whose Show Above Icons differs from the name's: built
    -- here with the first (never in a later layout pass), levelled by ns.RF_TextLayout.
    local textCarrierAlt = CreateFrame("Frame", nil, btnFrame)
    textCarrierAlt:SetAllPoints(health)
    textCarrierAlt:SetFrameLevel(btnFrame:GetFrameLevel() + mod.LVL_TEXT)
    d._txAlt = textCarrierAlt
    -- Status text (DEAD / OFFLINE / AFK -- always shown, own position/size/color).
    -- Party Frames kit: in the text band, so the Classic art (drawn over the
    -- bars) never covers it; it still anchors to the kit health bar.
    local statusFS = (d.kit and textCarrier or health):CreateFontString(nil, "OVERLAY")
    local stc = s.statusTextColor or { r = 1, g = 1, b = 1 }
    ApplyFont(statusFS, s.statusTextSize or 14)
    statusFS:SetJustifyH("CENTER")
    statusFS:SetTextColor(stc.r, stc.g, stc.b)
    statusFS:Hide()
    d.statusText = statusFS

    local function AnchorStatusText()
        local s = LiveS() -- party/extra-aware (see LiveS note above)
        local health = mod.RF_BarHost(health, s) -- Uniform Icon Anchoring host swap / kit bar
        statusFS:ClearAllPoints()
        local place = s.statusTextPosition or "center"
        local ox = s.statusTextOffsetX or 0
        local oy = s.statusTextOffsetY or 0
        if place == "topleft" then
            statusFS:SetPoint("TOPLEFT", health, "TOPLEFT", 2 + ox, -2 + oy)
        elseif place == "top" then
            statusFS:SetPoint("TOP", health, "TOP", ox, -2 + oy)
        elseif place == "topright" then
            statusFS:SetPoint("TOPRIGHT", health, "TOPRIGHT", -2 + ox, -2 + oy)
        elseif place == "left" then
            statusFS:SetPoint("LEFT", health, "LEFT", 2 + ox, oy)
        elseif place == "right" then
            statusFS:SetPoint("RIGHT", health, "RIGHT", -2 + ox, oy)
        elseif place == "bottomleft" then
            statusFS:SetPoint("BOTTOMLEFT", health, "BOTTOMLEFT", 2 + ox, 2 + oy)
        elseif place == "bottom" then
            statusFS:SetPoint("BOTTOM", health, "BOTTOM", ox, 2 + oy)
        elseif place == "bottomright" then
            statusFS:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", -2 + ox, 2 + oy)
        else -- center
            statusFS:SetPoint("CENTER", health, "CENTER", ox, oy)
        end
    end
    AnchorStatusText()
    d.AnchorStatusText = AnchorStatusText

    -- Role icon. Carrier sits in the text band (ns.LVL_AURA - 1 = ns.LVL_TEXT): above every border incl. the raise, auras still over it.
    -- Level is owned by AnchorRoleIcon (live-resolves the "Show Behind Border" option); this is just the initial value.
    local roleCarrier = CreateFrame("Frame", nil, btnFrame)
    roleCarrier:SetAllPoints(health)
    roleCarrier:SetFrameLevel(btnFrame:GetFrameLevel() + (mod.LVL_AURA - 1))
    local roleIcon = roleCarrier:CreateTexture(nil, "OVERLAY")
    local riSz = PixelSnap(s.roleIconSize or 14)
    roleIcon:SetSize(riSz, riSz)
    roleIcon:Hide()
    d.roleIcon = roleIcon

    local function AnchorRoleIcon()
        local s = LiveS() -- party/extra-aware (see LiveS note above)
        -- Show Behind Border: just under the base border; default: the text band.
        roleCarrier:SetFrameLevel(
            btnFrame:GetFrameLevel() + (s.roleIconBehindBorder and mod.LVL_ROLE_BEHIND or (mod.LVL_AURA - 1))
        )
        local health = mod.RF_AnchorHost(health, s) -- Uniform Icon Anchoring host swap
        roleIcon:ClearAllPoints()
        -- Party Frames kit: the stock spot plus the user's offsets.
        if d.kitG then
            mod.RF_KitSpot(d.kitG.role, roleIcon, btnFrame, s.roleIconOffsetX, s.roleIconOffsetY)
            return
        end
        -- Attach Role Icons: the name bar's rect is the same with or without a power bar
        if s.roleIconOnNameBar and s.topNameBarEnabled and d.topNameBar then
            local place = (s.roleNameBarPosition or "left"):upper()
            roleIcon:SetPoint(
                place,
                d.topNameBar,
                place,
                s.roleNameBarOffsetX or 0,
                s.roleNameBarOffsetY or 0
            )
            return
        end
        -- The position key uppercases directly to a valid anchor point, so all
        -- 9 positions resolve like the Marker Position dropdown.
        local place = (s.roleIconPosition or "bottomleft"):upper()
        roleIcon:SetPoint(place, health, place, s.roleIconOffsetX or 0, s.roleIconOffsetY or 0)
    end
    AnchorRoleIcon()
    d.AnchorRoleIcon = AnchorRoleIcon

    -- Marker carrier: above the frame border (incl. the hover/target raise) so the raid marker renders on top, not clipped behind it.
    local markerCarrier = CreateFrame("Frame", nil, btnFrame)
    markerCarrier:SetAllPoints(health)
    markerCarrier:SetFrameLevel(btnFrame:GetFrameLevel() + mod.LVL_MARKER)

    -- Leader/assistant icon. Own host frame (strata/level contract in ns.ApplyLeaderStrata) --
    -- NOT the marker carrier, whose high level keeps the raid marker always on top. Parented to
    -- the button so it tracks the frame; SetAllPoints(health) anchors it to the health bar.
    d.leaderHost = CreateFrame("Frame", nil, btnFrame)
    d.leaderHost:SetAllPoints(health)
    mod.ApplyLeaderStrata(d.leaderHost)

    local leaderIcon = d.leaderHost:CreateTexture(nil, "OVERLAY")
    local liSz = PixelSnap(s.leaderIconSize or 14)
    leaderIcon:SetSize(liSz, liSz)
    local liPos = (s.leaderIconPosition or "top"):upper()
    leaderIcon:SetPoint(
        liPos,
        mod.RF_AnchorHost(health, s),
        liPos,
        s.leaderIconOffsetX or 0,
        s.leaderIconOffsetY or 0
    )
    leaderIcon:Hide()
    d.leaderIcon = leaderIcon
    -- Party Frames kit: the stock spot (re-seated by the party reload pass).
    if d.kitG then
        mod.RF_KitLeader(d, LiveS())
    end

    -- Raid marker (on marker carrier, above the border)
    local raidMarker = markerCarrier:CreateTexture(nil, "OVERLAY", nil, 2)
    local rmSz = PixelSnap(s.raidMarkerSize or 16)
    raidMarker:SetSize(rmSz, rmSz)
    raidMarker:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    raidMarker:Hide()
    d.raidMarker = raidMarker

    local function AnchorRaidMarker()
        local s = LiveS() -- party/extra-aware (see LiveS note above)
        local health = mod.RF_AnchorHost(health, s) -- Uniform Icon Anchoring host swap
        raidMarker:ClearAllPoints()
        local place = s.raidMarkerPosition or "center"
        local ox = s.raidMarkerOffsetX or 0
        local oy = s.raidMarkerOffsetY or 0
        if place == "topleft" then
            raidMarker:SetPoint("TOPLEFT", health, "TOPLEFT", 2 + ox, -2 + oy)
        elseif place == "top" then
            raidMarker:SetPoint("TOP", health, "TOP", ox, -2 + oy)
        elseif place == "topright" then
            raidMarker:SetPoint("TOPRIGHT", health, "TOPRIGHT", -2 + ox, -2 + oy)
        elseif place == "left" then
            raidMarker:SetPoint("LEFT", health, "LEFT", 2 + ox, oy)
        elseif place == "right" then
            raidMarker:SetPoint("RIGHT", health, "RIGHT", -2 + ox, oy)
        elseif place == "bottomleft" then
            raidMarker:SetPoint("BOTTOMLEFT", health, "BOTTOMLEFT", 2 + ox, 2 + oy)
        elseif place == "bottom" then
            raidMarker:SetPoint("BOTTOM", health, "BOTTOM", ox, 2 + oy)
        elseif place == "bottomright" then
            raidMarker:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", -2 + ox, 2 + oy)
        else -- center
            raidMarker:SetPoint("CENTER", health, "CENTER", ox, oy)
        end
    end
    AnchorRaidMarker()
    d.AnchorRaidMarker = AnchorRaidMarker

    -- Ready check icon (shared with incoming-summon / incoming-rez; above name text)
    local readyCheck = markerCarrier:CreateTexture(nil, "OVERLAY")
    readyCheck:SetSize(PixelSnap(s.readyCheckSize or 20), PixelSnap(s.readyCheckSize or 20))
    readyCheck:Hide()
    d.readyCheck = readyCheck

    local function AnchorReadyCheck()
        local s = LiveS() -- party/extra-aware (see LiveS note above)
        local health = mod.RF_AnchorHost(health, s) -- Uniform Icon Anchoring host swap
        readyCheck:ClearAllPoints()
        local place = s.readyCheckPosition or "center"
        local ox = s.readyCheckOffsetX or 0
        local oy = s.readyCheckOffsetY or 0
        -- Party Frames kit: centred on the portrait, as stock.
        if d.kitG and d.kitPortrait then
            mod.RF_KitSpot(d.kitG.rc, readyCheck, d.kitPortrait, ox, oy)
            return
        end
        if place == "topleft" then
            readyCheck:SetPoint("TOPLEFT", health, "TOPLEFT", 2 + ox, -2 + oy)
        elseif place == "top" then
            readyCheck:SetPoint("TOP", health, "TOP", ox, -2 + oy)
        elseif place == "topright" then
            readyCheck:SetPoint("TOPRIGHT", health, "TOPRIGHT", -2 + ox, -2 + oy)
        elseif place == "left" then
            readyCheck:SetPoint("LEFT", health, "LEFT", 2 + ox, oy)
        elseif place == "right" then
            readyCheck:SetPoint("RIGHT", health, "RIGHT", -2 + ox, oy)
        elseif place == "bottomleft" then
            readyCheck:SetPoint("BOTTOMLEFT", health, "BOTTOMLEFT", 2 + ox, 2 + oy)
        elseif place == "bottom" then
            readyCheck:SetPoint("BOTTOM", health, "BOTTOM", ox, 2 + oy)
        elseif place == "bottomright" then
            readyCheck:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", -2 + ox, 2 + oy)
        else -- center
            readyCheck:SetPoint("CENTER", health, "CENTER", ox, oy)
        end
    end
    AnchorReadyCheck()
    d.AnchorReadyCheck = AnchorReadyCheck

    -- Combat icon (marker carrier, above the border): members currently affecting combat; 9-position anchor mirrors the role icon.
    local combatIcon = markerCarrier:CreateTexture(nil, "OVERLAY", nil, 1)
    local ciSz = PixelSnap(s.combatIndicatorSize or 16)
    combatIcon:SetSize(ciSz, ciSz)
    combatIcon:Hide()
    d.combatIcon = combatIcon

    local function AnchorCombatIcon()
        local s = LiveS() -- party/extra-aware (see LiveS note above)
        local health = mod.RF_AnchorHost(health, s) -- Uniform Icon Anchoring host swap
        combatIcon:ClearAllPoints()
        local place = (s.combatIndicatorPosition or "right"):upper()
        combatIcon:SetPoint(
            place,
            health,
            place,
            s.combatIndicatorOffsetX or 0,
            s.combatIndicatorOffsetY or 0
        )
    end
    AnchorCombatIcon()
    d.AnchorCombatIcon = AnchorCombatIcon

    -- The texts: font, anchor and visibility of every shown text (Top Name Bar
    -- hides the name, the Party Frames kit puts it on the stock spot).
    local function AnchorTexts()
        local s = LiveS() -- party/extra-aware (see LiveS note above)
        -- Text band level, re-applied on every reload. Default sits under the aura band
        -- (ns.LVL_TEXT); "Show Above Icons" (the name's cog) lifts it above the band's children
        -- (+6 clears each aura unit's +1..+5), still below the marker carrier.
        textCarrier:SetFrameLevel(
            btnFrame:GetFrameLevel() + (s.nameTextAboveIcons and (mod.LVL_AURA + 6) or mod.LVL_TEXT)
        )
        mod.RF_TextLayout(d, s)
    end
    AnchorTexts()
    d.AnchorTexts = AnchorTexts
    -- Raise the border above neighbors while hovered/targeted (or recolored for aggro): buttons share a frame level, so with
    -- small/negative Frame Spacing a neighbor's border would cover this frame's highlight.
    -- Highlight states bump it up, normal restores the base level. The PP container's level is
    -- fixed at creation, so it must be moved explicitly (borderFrame alone won't move it).
    local function ApplyBorderLevel(raised, s)
        if not (Pix and d.borderFrame) then
            return
        end
        local pl = btnFrame:GetFrameLevel()
        -- Under a stock style the CludesUI border is stood down, so Show
        -- Behind has nothing to lower (the hover border must stay on top).
        -- Resolved LIVE like UpdateBorder (the caller passes its own LiveS()), so a
        -- party that keeps its own Show Behind (and the Color Custom Borders copy that
        -- follows it) stays in step.
        s = s or LiveS()
        local lvl = (s.borderBehind and not d.stockEdge and not d.kit) and math.max(0, pl - 1)
            or (pl + (raised and mod.LVL_RAISE or 8))
        -- Runs on hover/target transitions and restyles: skip the SetFrameLevel calls unless
        -- the level actually changes -- the common case is two getters.
        local boxHolder = Pix.GetBorders(d.borderFrame)
        if
            d.borderFrame:GetFrameLevel() == lvl
            and (not boxHolder or boxHolder:GetFrameLevel() == lvl + 1)
        then
            return
        end
        d.borderFrame:SetFrameLevel(lvl)
        if boxHolder then
            boxHolder:SetFrameLevel(lvl + 1)
        end
        -- A textured style draws on a backdrop child levelled only at style time: carry
        -- it too, so the raise also clears the Color Custom Borders copies (base + 1).
        local edge = CludesUI._bdBorderData and CludesUI._bdBorderData[d.borderFrame]
        if edge then
            edge:SetFrameLevel(lvl)
        end
    end

    -- Recolor the single border for the current state: hover > target > aggro (Threat
    -- Borders' Color Custom Borders, flagged by ns.RF_PaintThreat) > normal. A borderless
    -- frame has nothing to recolor, so the highlight draws its own (ns.ApplyHighlightBorder).
    local function ApplyBorderColor()
        if not (Pix and d.borderFrame) then
            return
        end
        -- Re-called long after StyleButton: resolve LIVE (see LiveS note) so party overrides and profile swaps are honored.
        local s = LiveS()
        if mod.RF_ButtonCompact(d, s) then
            mod.RF_CompactHighlight(d.borderFrame, d, s, btnFrame)
            return
        end
        -- Party Frames kit: hover and target glow along the frame art.
        if d.kit then
            ApplyBorderLevel(false, s)
            mod.RF_KitHighlight(
                d,
                d.borderFrame,
                s,
                d._hovered and s.hoverBorderEnabled ~= false,
                d._isTarget and s.targetBorderEnabled ~= false
            )
            return
        end
        -- Stock styles: the stock selection ring for the target, the hover
        -- border on the stood-down border frame.
        if d.stockEdge then
            local hover = d._hovered and s.hoverBorderEnabled ~= false
            ApplyBorderLevel(hover, s)
            mod.RF_StockHighlight(d, d.borderFrame, s, hover, d._isTarget and s.targetBorderEnabled ~= false)
            return
        end
        local r, g, b, a
        local raised, hlSize, hlPx = false, nil, nil
        if d._hovered and s.hoverBorderEnabled ~= false then
            local c = s.hoverBorderColor or { r = 1, g = 1, b = 1 }
            r, g, b, a = c.r, c.g, c.b, s.hoverBorderAlpha or 1
            raised, hlSize = true, s.hoverBorderSize or 1
            hlPx = CludesUI.BorderPx(s.hoverBorderSizePx, hlSize, s.borderTexture or "solid")
        elseif d._isTarget and s.targetBorderEnabled ~= false then
            local c = s.targetBorderColor or { r = 1, g = 1, b = 1 }
            r, g, b, a = c.r, c.g, c.b, s.targetBorderAlpha or 1
            raised, hlSize = true, s.targetBorderSize or 1
            hlPx = CludesUI.BorderPx(s.targetBorderSizePx, hlSize, s.borderTexture or "solid")
        elseif d._aggroBdr and s.threatCustomBorder == true and mod.RF_CustomBorderOn(s) then
            -- The threat color, raised like hover/target so it also covers the dispel
            -- Color Custom Borders copies (base + 9). Settings re-checked live: a
            -- restyle can run before the next threat paint clears the flag.
            r, g, b, a = 1, 0, 0, 1
            raised = true
        else
            local c = s.borderColor or { r = 0, g = 0, b = 0 }
            r, g, b, a = c.r, c.g, c.b, s.borderAlpha or 1
        end
        ApplyBorderLevel(raised, s)
        if (s.borderSize or 1) <= 0 then
            mod.ApplyHighlightBorder(d.borderFrame, s, hlSize, r, g, b, a, hlPx)
            return
        end
        if hlSize then
            r, g, b = mod.RF_VisibleHighlight(s, r, g, b)
        end
        d.borderFrame._hlBorderSize = nil
        CludesUI.SetBorderStyleColor(d.borderFrame, r, g, b, a)
        if
            s.powerBorderMatchColor == true
            and d.powerBorderFrame
            and d.powerBorderFrame._powerArtMode == "divider"
        then
            mod.RF_ColorPowerDivider(d.powerBorderFrame, r, g, b, a)
        end
        if s.topNameBarDividerMatchColor == true and d.topNameBar and d.topNameBar._divider then
            mod.RF_ColorPowerDivider(d.topNameBar._divider, r, g, b, a)
        end
    end
    d.ApplyBorderColor = ApplyBorderColor

    -- Apply border (style/size/texture/offsets via shared ApplyBorderStyle,
    -- then recolor for state). "Show Behind" lowers it below the frame; else +8.
    local function UpdateBorder()
        if not (Pix and d.borderFrame) then
            return
        end
        -- Re-called from Reload paths long after StyleButton: resolve LIVE (see LiveS note).
        local s = LiveS()
        local bs = s.borderSize or 1
        local bc = s.borderColor or { r = 0, g = 0, b = 0 }
        local texKey = s.borderTexture or "solid"
        local pl = btnFrame:GetFrameLevel()
        local compact = mod.RF_ButtonCompact(d, s)
        if compact or d._compactBorder then
            d._compactBorder = compact
        end
        if compact then
            CludesUI.ApplyBorderStyle(d.borderFrame, 0, 0, 0, 0, 0, "solid")
            ApplyBorderColor()
            CludesUI.RoundCorners(btnFrame, 0)
            return
        end
        -- Stock styles: the CludesUI border stands down for the stock edge
        -- (for the art under the Party Frames kit).
        if d.kit then
            d.borderFrame:SetFrameLevel(pl + 8)
            CludesUI.ApplyBorderStyle(d.borderFrame, 0, 0, 0, 0, 0, "solid")
            d.borderFrame._hlBorderSize = nil
            ApplyBorderColor()
            CludesUI.RoundCorners(btnFrame, 0)
            return
        end
        if d.stockEdge then
            d.borderFrame:SetFrameLevel(pl + 8)
            CludesUI.ApplyBorderStyle(d.borderFrame, 0, 0, 0, 0, 0, "solid")
            d.borderFrame._hlBorderSize = nil
            mod.RF_StockSeat(d)
            ApplyBorderColor()
            CludesUI.RoundCorners(btnFrame, 0)
            return
        end
        d.borderFrame:SetFrameLevel(s.borderBehind and math.max(0, pl - 1) or (pl + 8))
        CludesUI.ApplyBorderStyle(
            d.borderFrame,
            bs,
            bc.r,
            bc.g,
            bc.b,
            s.borderAlpha or 1,
            texKey,
            s.borderTextureOffset,
            s.borderTextureOffsetY,
            s.borderTextureShiftX,
            s.borderTextureShiftY,
            "unitframes",
            bs,
            nil,
            CludesUI.BorderPx(s.borderSizePx, bs, texKey)
        )
        ApplyBorderColor()
        -- Rounded corners (CludesUI_RoundedCorners.lua; nothing at radius 0).
        -- The power border rides in the body so its edge strips round too.
        local radius = s.cornerRadius or 0
        if radius > 0 then
            CludesUI.RoundCorners(btnFrame, radius, {
                roots = { d.health, d.power, d.topNameBar, d.powerBorderFrame },
                textures = { d.bg },
                border = d.borderFrame,
                style = texKey,
                corners = s.cornerMask,
            })
        else
            CludesUI.RoundCorners(btnFrame, 0)
        end
    end
    if mod.RF_Stock() and not d.kit then
        mod.RF_StockBuild(btnFrame, d, d.power)
    end
    UpdateBorder()
    d.UpdateBorder = UpdateBorder

    -- Apply power border
    local function UpdatePowerBorder(force)
        -- Party Frames kit: the mana bar sits in the art's own track.
        if d.kit then
            mod.RF_ClearPowerBorderArt(d.powerBorderFrame)
            if d.powerBorderFrame then
                d.powerBorderFrame:Hide()
            end
            return
        end
        -- No-op while the power bar is hidden: the border frame always exists and unconditional
        -- callers must not draw over a hidden bar. UpdateButton calls this AFTER power:Show().
        if not Pix or not d.powerBorderFrame then
            return
        end
        if d.power and not d.power:IsShown() then
            mod.RF_ClearPowerBorderArt(d.powerBorderFrame)
            d.powerBorderFrame:Hide()
            return
        end
        -- Classic WoW UI: the stock health/power divider in place of the power border.
        if d.stockDiv then
            mod.RF_ClearPowerBorderArt(d.powerBorderFrame)
            d.powerBorderFrame:Hide()
            mod.RF_StockDivider(d)
            return
        end
        -- Re-called long after StyleButton: resolve LIVE (see LiveS note) -- a captured `s` misses party overrides and profile swaps.
        local s = LiveS()
        if s.powerBorderMatchFrame == true or d.powerBorderFrame._powerArtKey then
            local handled, refreshed = mod.RF_ApplyPowerBorderArt(d.powerBorderFrame, s, force)
            if handled then
                if
                    refreshed
                    and s.powerBorderMatchColor == true
                    and d.powerBorderFrame._powerArtMode == "divider"
                then
                    ApplyBorderColor()
                end
                return
            end
        end
        local style = s.powerBorderStyle or "cui"
        if style == "cui" then
            -- CUI style: 1px divider, white at 20% opacity
            Pix.UpdateBorder(d.powerBorderFrame, 1, 1, 1, 1, 0.2)
            d.powerBorderFrame:Show()
            local ppC = Pix.GetBorders(d.powerBorderFrame)
            if ppC then
                if ppC._bottom then
                    ppC._bottom:SetAlpha(0)
                end
                if ppC._left then
                    ppC._left:SetAlpha(0)
                end
                if ppC._right then
                    ppC._right:SetAlpha(0)
                end
                if ppC._top then
                    ppC._top:SetAlpha(0.2)
                end
            end
            return
        end
        local bs = s.powerBorderSize or 1
        if bs <= 0 then
            d.powerBorderFrame:Hide()
            return
        end
        local bc = s.powerBorderColor
        local ba = s.powerBorderAlpha or 1
        Pix.UpdateBorder(d.powerBorderFrame, bs, bc.r, bc.g, bc.b, ba)
        d.powerBorderFrame:Show()
        local ppC = Pix.GetBorders(d.powerBorderFrame)
        if ppC then
            if style == "divider" then
                if ppC._bottom then
                    ppC._bottom:SetAlpha(0)
                end
                if ppC._left then
                    ppC._left:SetAlpha(0)
                end
                if ppC._right then
                    ppC._right:SetAlpha(0)
                end
                if ppC._top then
                    ppC._top:SetAlpha(ba)
                end
            else -- "border"
                if ppC._top then
                    ppC._top:SetAlpha(ba)
                end
                if ppC._bottom then
                    ppC._bottom:SetAlpha(ba)
                end
                if ppC._left then
                    ppC._left:SetAlpha(ba)
                end
                if ppC._right then
                    ppC._right:SetAlpha(ba)
                end
            end
        end
    end
    UpdatePowerBorder()
    d.UpdatePowerBorder = UpdatePowerBorder

    -- Tooltip handlers
    btnFrame:HookScript("OnEnter", ButtonOnEnter)
    btnFrame:HookScript("OnLeave", ButtonOnLeave)

    -- Private auras: re-anchor whenever the secure header reassigns this button's unit. The engine
    -- drops private-aura anchors on unit reassignment (join/leave, sort, zone-in) even when the
    -- token string is unchanged, so the roster-event RebuildUnitMap path (which re-registers only
    -- when the token CHANGES) can leave the anchor dropped. OnAttributeChanged is the reliable
    -- per-button signal for exactly those reassignments. HookScript (NEVER SetScript) preserves the
    -- secure header's own handlers; helpers go through ns because they are defined later.
    btnFrame:HookScript("OnAttributeChanged", function(self, name)
        if name ~= "unit" then
            return
        end
        local u = self:GetAttribute("unit")
        if u and UnitExists(u) then
            -- Repaint + remap the instant the header (re)assigns this button, so a late assignment
            -- landing after the roster-timer rebuild can never leave it blank or route live events
            -- to a stale button.
            local d = GetFFD(self)
            -- Extra Frames duplicates never enter the real routing maps (one button per unit);
            -- XF_Apply owns ns._xfUnitToButton. The repaint/range work below is 1:1.
            -- A set flagged hidden stays out of the maps: its headers can still
            -- re-process until the visibility driver hides them (the next tick), and
            -- a hidden button would win the routing over the set actually shown.
            if d._isExtra then
                -- map owned by XF_Apply
            elseif d._isParty then
                if mod._partyFramesVisible then
                    mod._partyUnitToButton[u] = self
                end
            elseif mod._raidFramesVisible then
                unitToButton[u] = self
            end
            -- The secure header re-sets EVERY child's unit on EVERY re-process (each
            -- roster/name event, each sort attribute change), so most fires are a
            -- same-occupant re-confirm: same token AND same person as the last full
            -- paint. Nothing on the button changed -- its own unit events kept it
            -- current -- so only the routing write above and the container's
            -- assist gate run; the roster timer refreshes roster-derived state
            -- (leader/role/power layout) for unchanged occupants. A secret guid
            -- (never memoized) or a cleared/unstyled button takes the full path.
            local unitGuid = UnitGUID(u)
            if issecretvalue(unitGuid) then
                unitGuid = nil
            end
            if unitGuid and d._lastGuid == unitGuid and d._lastUnit == u then
                if mod.RFC_OnUnitAssigned then
                    mod.RFC_OnUnitAssigned(self, d, u)
                end
                return
            end
            -- Identity caches (class token, power type) drop on a real assignment:
            -- a different person can land on this button under the same token, and
            -- those derive again on the next tick for one cheap read each.
            d._clsTok = nil
            d._pwType = nil
            d._rmhPct = nil
            -- Drop the power-hide cache only on a token change -- else it forces an
            -- unconditional Show/Hide/SetHeight repaint, reintroducing the pop the
            -- deferred-power fix removed.
            if d._lastUnit ~= u then
                d._lastUnit = u
                d._appliedHidePower = nil
            end
            d._lastGuid = d.styled and unitGuid or nil
            -- A ping marker belongs to the previous occupant; its pin-removed edge
            -- can no longer reach this button once the person moved.
            if d.pingFrame then
                d.pingFrame:Hide()
            end
            -- Containers first: the legacy refresh below still has restriction-era failure modes,
            -- and an error there must not starve the container of its unit assignment.
            if mod.RFC_OnUnitAssigned then
                mod.RFC_OnUnitAssigned(self, d, u)
            end
            -- Party Frames kit / party portrait: the new occupant's portrait
            -- (ahead of the legacy refresh for the same reason as the containers).
            if d.kitPortrait or d.pt then
                mod.RF_PtPaint(d, u, "UnitChanged")
            end
            if mod._RefreshAssignedButton then
                mod._RefreshAssignedButton(self, u)
            end
            if mod._UpdateButtonRange then
                mod._UpdateButtonRange(u, self)
            end
        else
            -- Cleared (button hidden by the header) or not yet resolvable: forget the
            -- painted occupant so the next assignment always takes the full path.
            GetFFD(self)._lastGuid = nil
        end
    end)

    -- 12.1 aura containers (container shell creation is combat-legal since
    -- 68914, so this rides the deferred styling pass with the rest of the body)
    if mod.RFC_SetupButton then
        mod.RFC_SetupButton(btnFrame, health, d)
    end
end

-------------------------------------------------------------------------------
--  Window-phase secure styling: everything on a fresh unit button that is
--  combat-blocked or writes secure state -- the size plus the click / ping /
--  click-cast tail (92 WrapScripts across the fleet live in CC_RegisterFrame).
--  Runs inside the login loading-screen window for every pre-spawned button;
--  the insecure visual body (StyleButton) runs in its own deferred
--  post-screen execution so the suite's shared login watchdog budget never
--  pays for it. Idempotent via d.securestyled, mirroring d.styled.
-------------------------------------------------------------------------------
mod._StyleButtonSecure = function(btnFrame)
    local d = GetFFD(btnFrame)
    if d.securestyled then
        return
    end
    d.securestyled = true
    local s = saved.profile
    -- Party buttons take the party box (their creator stamps _isParty
    -- first); everything else the raid size.
    if d._isParty then
        local pw, ph = mod.RF_PartyDims(s)
        btnFrame:SetSize(PixelSnap(pw), PixelSnap(ph))
    else
        btnFrame:SetSize(PixelSnap(s.frameWidth or 72), PixelSnap(s.frameHeight or 46))
    end

    -- Secure click: left=target, right=menu
    btnFrame:RegisterForClicks("AnyUp")
    btnFrame:SetAttribute("type1", "target")
    -- Wildcard fallback so left-click target survives if the click-cast engine later clears type1.
    btnFrame:SetAttribute("*type1", "target")
    -- The engine gates SecureUnitButton's togglemenu; route right-click through a SecureActionButton
    -- proxy so the menu (and protected items like Set Focus) works without taint (*type2 = "click").
    if CludesUI.AttachSecureUnitMenu then
        CludesUI.AttachSecureUnitMenu(btnFrame)
    else
        btnFrame:SetAttribute("type2", "togglemenu")
        btnFrame:SetAttribute("*type2", "togglemenu")
    end

    -- Hover ping support, MIXIN-PURE: Blizzard's mixin methods run untouched
    -- (its GetTargetInfo resolves the unit from our "unit" attribute, which
    -- tracks the current occupant across sorts). Never override
    -- GetIsPingable/GetTargetInfo -- addon Lua in the ping path makes a
    -- secret GUID "inaccessible" to PingManager's securecopy (hard error +
    -- wedged listener), and a secrecy-guarded override deadens pings in all
    -- restricted content (both field-failed 2026-08-20). Writes are safe --
    -- our own spawned secure template, once per button, out of combat.
    if PingableType_UnitFrameMixin then
        Mixin(btnFrame, PingableType_UnitFrameMixin)
        btnFrame:SetAttribute("ping-receiver", true)
    end

    -- Register for click-casting (CUI built-in system)
    if mod.CC_RegisterFrame then
        mod.CC_RegisterFrame(btnFrame)
    elseif ClickCastFrames then
        ClickCastFrames[btnFrame] = true
    end
end

Inner.StyleButton = StyleButton
Inner.broken = false
