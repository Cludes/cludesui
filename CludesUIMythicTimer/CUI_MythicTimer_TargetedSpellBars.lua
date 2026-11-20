if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
--------------------------------------------------------------------------------
--  CUI_MythicTimer_TargetedSpellBars.lua
--  Targeted Spell Bars (Mythic+ Tools): one movable group of cast bars, one per
--  enemy nameplate currently casting -- a replica of the nameplate cast display
--  (spell name, spell target, timer) collected in one place so every active
--  cast reads at a glance. Optional interrupt awareness (kick-ready tint,
--  uninterruptible wash, important-cast tint/glow), out-of-interrupt-range
--  fade, and raid target markers, all opt-in and off by default.
--
--  Zero cost while disabled: no events are registered and no frames are built
--  until the feature is enabled. All cast reads follow the nameplate module's
--  secret discipline: type() existence checks, duration objects into
--  SetTimerDuration, secret strings straight into SetText, never a Lua branch
--  on a secret value.
--------------------------------------------------------------------------------
local ADDON_NAME, mod = ...

local saved -- Lite DB handle, handed over by ns.TSB_OnEnable

local function Cfg()
    local p = saved and saved.profile
    return p and p.tsb
end

--------------------------------------------------------------------------------
--  Fonts: module-wide family/outline/shadow (surface key "mythicTimer"), only
--  per-text sizes are settings -- same contract as every other bar surface.
--------------------------------------------------------------------------------
-- A bar's target text names a player, so the bar texts take a font family
-- (Cyrillic, Korean and Chinese names draw); no plain SetFont may reach them after it.
local function SetFSFont(fontStr, size)
    CludesUI.ApplyModuleFontFamily(fontStr, nil, size, "mythicTimer")
end

--------------------------------------------------------------------------------
--  Shared engines consumed read-only (core addon, loaded before this module).
--------------------------------------------------------------------------------
local GetActiveKickSpell = CludesUI.GetActiveKickSpell
local ComputeCastBarTint = CludesUI.ComputeCastBarTint
local Glows = CludesUI.Glows

-- Raid marker sheet texcoords (4x4 grid), same layout as CludesUIRaidFrames.
local RAID_MARKER_TEXCOORDS = {
    [1] = { 0, 0.25, 0, 0.25 }, -- Star
    [2] = { 0.25, 0.5, 0, 0.25 }, -- Circle
    [3] = { 0.5, 0.75, 0, 0.25 }, -- Diamond
    [4] = { 0.75, 1, 0, 0.25 }, -- Triangle
    [5] = { 0, 0.25, 0.25, 0.5 }, -- Moon
    [6] = { 0.25, 0.5, 0.25, 0.5 }, -- Square
    [7] = { 0.5, 0.75, 0.25, 0.5 }, -- Cross
    [8] = { 0.75, 1, 0.25, 0.5 }, -- Skull
}

--------------------------------------------------------------------------------
--  State
--------------------------------------------------------------------------------
local boxHolder -- anchor frame the unlock mover drags; built lazily
local barList = {} -- frame pool (holder frames, reused forever)
local isShown = {} -- active entries in display order
local unitEntry = {} -- unit token -> entry while its bar is shown
local plateUnits = {} -- unit token -> true while its nameplate exists
local isActive = false -- events registered / feature live
local previewOn = false -- sample bars forced on (unlock placement)
local timerTicker -- shared 10Hz text ticker, self-stops when idle
local slowAccum = 0 -- 10Hz tick counter driving the 0.2s poll pass
local styleGen = 0 -- bumped by TSB_Refresh; O3 restyle-on-stale stamp
local anyCastDropped = false -- true only when the maxBars cap actually dropped a cast

local DEFAULT_X, DEFAULT_Y = -340, 60

--------------------------------------------------------------------------------
--  Where to Show: content-type gate (positive filter, see ns.MTWhere.Shows).
--  Runs independently of the nameplate-tracking lifecycle below -- entering or
--  leaving a matching zone must be able to (de)activate the group even while
--  the bucket the player is currently in is excluded, so the subscription to
--  the shared location/combat watcher stays for as long as the feature is
--  enabled, never tied to `active`.
--------------------------------------------------------------------------------
local MTWhere = mod.MTWhere

-- The location buckets this filter offers. Arena and battleground are not
-- among them, so that content never hides the bars.
local WHERE_KEYS = MTWhere.NewKeySet({
    "open_world",
    "raid_mythic",
    "raid_heroic",
    "raid_normal_lfr",
    "dungeon_mythic",
    "dungeon_nonmythic",
    "timewalking",
    "delve",
    "lair",
    "scenario",
})

-- Zone/combat edges only flip the group on or off (defined after Activate/
-- Deactivate); a full restyle belongs to settings writes, not combat entry.
local SyncWhereActive

--------------------------------------------------------------------------------
--  Container + position (unlock interchange = raw UIParent-logical center
--  delta, same contract as the timer frame -- scale division never leaves the
--  module's own SetPoint).
--------------------------------------------------------------------------------
local function ApplyContainerPosition()
    if not boxHolder then
        return
    end
    local conf = Cfg()
    local place = conf and conf.pos
    boxHolder:ClearAllPoints()
    if place and place.centerX and place.centerY then
        boxHolder:SetPoint("CENTER", UIParent, "CENTER", place.centerX, place.centerY)
    else
        boxHolder:SetPoint("CENTER", UIParent, "CENTER", DEFAULT_X, DEFAULT_Y)
    end
end

local function EnsureContainer()
    if boxHolder then
        return boxHolder
    end
    boxHolder = CreateFrame("Frame", nil, UIParent)
    boxHolder:SetSize(240, 20)
    ApplyContainerPosition()
    return boxHolder
end

--------------------------------------------------------------------------------
--  Bar construction: holder > bg + icon + StatusBar fill + uninterruptible
--  overlay + raid marker + text zones. Built once per pool slot, restyled by
--  StyleBar. `parent` is the options header sample's host; the live pool
--  passes nothing and hangs its bars on the group container.
--------------------------------------------------------------------------------
local function BuildBar(hostFrame)
    local holderFrame = CreateFrame("Frame", nil, hostFrame or EnsureContainer())
    holderFrame:Hide()

    holderFrame.bg = holderFrame:CreateTexture(nil, "BACKGROUND")
    holderFrame.bg:SetAllPoints(holderFrame)

    holderFrame.iconFrame = CreateFrame("Frame", nil, holderFrame)
    holderFrame.iconFrame:SetPoint("TOPLEFT", holderFrame, "TOPLEFT", 0, 0)
    holderFrame.iconFrame:SetPoint("BOTTOMLEFT", holderFrame, "BOTTOMLEFT", 0, 0)
    holderFrame.icon = holderFrame.iconFrame:CreateTexture(nil, "ARTWORK")
    holderFrame.icon:SetAllPoints(holderFrame.iconFrame)
    holderFrame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Icon/bar seam divider (opt-in). Rides its own frame above holder.sb:
    -- a texture on holder itself would draw under the StatusBar child.
    holderFrame.overlayFrame = CreateFrame("Frame", nil, holderFrame)
    holderFrame.overlayFrame:SetAllPoints(holderFrame)
    holderFrame.overlayFrame:SetFrameLevel(holderFrame:GetFrameLevel() + 5)
    holderFrame.iconDivider = holderFrame.overlayFrame:CreateTexture(nil, "OVERLAY", nil, 7)
    holderFrame.iconDivider:Hide()

    holderFrame.sb = CreateFrame("StatusBar", nil, holderFrame)
    -- Placeholder fill: a StatusBar has NO texture object until one is set, and
    -- the fill-edge rider below (the uninterruptible overlay) would index nil
    -- on a bar that never reached StyleBar (TargetFocusBars carries the same
    -- guard, same reason).
    holderFrame.sb:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    holderFrame.sb:SetPoint("TOPLEFT", holderFrame.iconFrame, "TOPRIGHT", 0, 0)
    holderFrame.sb:SetPoint("BOTTOMRIGHT", holderFrame, "BOTTOMRIGHT", 0, 0)
    holderFrame.sb:SetMinMaxValues(0, 1)
    holderFrame.sb:SetValue(0)

    -- Uninterruptible grey wash: rides the fill texture, alpha-gated by the
    -- (possibly secret) protection flag via SetAlphaFromBoolean.
    holderFrame.overlay = holderFrame.sb:CreateTexture(nil, "ARTWORK", nil, 2)
    holderFrame.overlay:SetAllPoints(holderFrame.sb:GetStatusBarTexture())
    holderFrame.overlay:SetTexture("Interface\\Buttons\\WHITE8x8")
    holderFrame.overlay:SetAlpha(0)

    -- Text zones ride a child frame so they draw above the fill and any border.
    holderFrame.textFrame = CreateFrame("Frame", nil, holderFrame.sb)
    holderFrame.textFrame:SetAllPoints(holderFrame.sb)

    -- Raid target marker, left of the spell name; hidden until a cast paints it.
    holderFrame.marker = holderFrame.textFrame:CreateTexture(nil, "OVERLAY")
    holderFrame.marker:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    holderFrame.marker:Hide()

    -- Fonts applied at BUILD as well as in StyleBar: SetText on a fontless
    -- FontString errors, and build/paint ordering must not be load-bearing.
    holderFrame.name = holderFrame.textFrame:CreateFontString(nil, "OVERLAY")
    holderFrame.name:SetJustifyH("LEFT")
    holderFrame.name:SetWordWrap(false)
    holderFrame.name:SetMaxLines(1)
    SetFSFont(holderFrame.name, 10)
    holderFrame.target = holderFrame.textFrame:CreateFontString(nil, "OVERLAY")
    holderFrame.target:SetJustifyH("RIGHT")
    holderFrame.target:SetWordWrap(false)
    holderFrame.target:SetMaxLines(1)
    SetFSFont(holderFrame.target, 10)
    holderFrame.timer = holderFrame.textFrame:CreateFontString(nil, "OVERLAY")
    holderFrame.timer:SetJustifyH("RIGHT")
    holderFrame.timer:SetWordWrap(false)
    holderFrame.timer:SetMaxLines(1)
    SetFSFont(holderFrame.timer, 10)

    return holderFrame
end

local function AcquireBarFrame()
    for i = 1, #barList do
        if not barList[i]._tsbInUse then
            barList[i]._tsbInUse = true
            return barList[i]
        end
    end
    local b = BuildBar()
    barList[#barList + 1] = b
    b._tsbInUse = true
    return b
end

--------------------------------------------------------------------------------
--  Name anchoring: shared by StyleBar and the raid-marker paint pass, since
--  the name has to shift right while a marker is shown.
--------------------------------------------------------------------------------
-- hasTarget: whether the target zone is actually in use for the current cast.
-- Most casts never populate it (no target, or Show Target off), so the plain
-- 48% split needlessly caps -- and truncates -- names that have the room.
local function AnchorName(holderFrame, conf, markerShown, hasTarget)
    local wid = conf.width or 240
    local hgt = conf.height or 20
    local markerReserve = markerShown and ((conf.raidMarkerSize or 14) + 2) or 0
    holderFrame.name:ClearAllPoints()
    holderFrame.name:SetPoint(
        "LEFT",
        holderFrame.sb,
        "LEFT",
        4 + markerReserve + (conf.nameX or 0),
        conf.nameY or 0
    )
    local shared = (wid - hgt) * 0.48 - markerReserve
    local nameWidth = shared
    if not hasTarget then
        local timerReserve = (conf.showTimer ~= false) and ((conf.timerSize or 10) * 2.2) or 0
        nameWidth = math.max(shared, (wid - hgt) - 8 - markerReserve - timerReserve)
    end
    if nameWidth < 1 then
        nameWidth = 1
    end
    holderFrame.name:SetWidth(nameWidth)
end

--------------------------------------------------------------------------------
--  Style pass: sizes, texture, colors, fonts, text layout. Runs on enable and
--  on any settings change (options call ns.TSB_Refresh), and once per bar the
--  first time it is used after a refresh (O3: StartCast skips this otherwise).
--------------------------------------------------------------------------------
local function StyleBar(holderFrame, conf)
    local wid = conf.width or 240
    local hgt = conf.height or 20
    holderFrame:SetSize(wid, hgt)

    local backdrop = conf.bgColor
    if backdrop then
        holderFrame.bg:SetColorTexture(backdrop.r, backdrop.g, backdrop.b, backdrop.a or 0.45)
    else
        holderFrame.bg:SetColorTexture(0, 0, 0, 0.45)
    end

    local showIcon = conf.showIcon ~= false
    -- Hidden icon stays on the left so the bar keeps its full-width anchors.
    local iconOnRight = showIcon and conf.iconOnRight
    holderFrame.iconFrame:ClearAllPoints()
    if iconOnRight then
        holderFrame.iconFrame:SetPoint("TOPRIGHT", holderFrame, "TOPRIGHT", 0, 0)
        holderFrame.iconFrame:SetPoint("BOTTOMRIGHT", holderFrame, "BOTTOMRIGHT", 0, 0)
    else
        holderFrame.iconFrame:SetPoint("TOPLEFT", holderFrame, "TOPLEFT", 0, 0)
        holderFrame.iconFrame:SetPoint("BOTTOMLEFT", holderFrame, "BOTTOMLEFT", 0, 0)
    end
    holderFrame.iconFrame:SetWidth(showIcon and hgt or 0.001)
    holderFrame.iconFrame:SetShown(showIcon)

    holderFrame.sb:ClearAllPoints()
    if iconOnRight then
        holderFrame.sb:SetPoint("TOPLEFT", holderFrame, "TOPLEFT", 0, 0)
        holderFrame.sb:SetPoint("BOTTOMRIGHT", holderFrame.iconFrame, "BOTTOMLEFT", 0, 0)
    else
        holderFrame.sb:SetPoint("TOPLEFT", holderFrame.iconFrame, "TOPRIGHT", 0, 0)
        holderFrame.sb:SetPoint("BOTTOMRIGHT", holderFrame, "BOTTOMRIGHT", 0, 0)
    end

    local texPath = CludesUI.ResolveTexturePath(
        mod.barTextures,
        conf.texture or "none",
        "Interface\\Buttons\\WHITE8x8"
    ) or "Interface\\Buttons\\WHITE8x8"
    holderFrame.sb:SetStatusBarTexture(texPath)
    local pp = CludesUI.PP
    if pp and pp.DisablePixelSnap then
        pp.DisablePixelSnap(holderFrame.sb:GetStatusBarTexture())
    end
    local color = conf.barColor
    if color then
        holderFrame.sb:SetStatusBarColor(color.r, color.g, color.b)
    end

    -- Fill texture re-mint: SetStatusBarTexture creates a NEW texture object
    -- every call, so the uninterruptible overlay must be re-pinned to it.
    holderFrame.overlay:ClearAllPoints()
    holderFrame.overlay:SetAllPoints(holderFrame.sb:GetStatusBarTexture())
    local un = conf.uninterruptible
    if un then
        holderFrame.overlay:SetVertexColor(un.r, un.g, un.b)
    end

    -- Solid black border on the holder; size 0 removes it. The Border Size
    -- slider stores coordinate units (px * PP.mult) while PP borders take
    -- physical pixels, so convert here: the bar draws the number the slider
    -- shows, and the icon divider below follows the same count.
    local bsz = conf.borderSize
    if bsz == nil then
        bsz = 1
    end
    if pp and pp.ToPixels then
        bsz = pp.ToPixels(bsz)
    end
    if pp and pp.CreateBorder then
        if bsz > 0 then
            if not holderFrame._tsbBorder then
                holderFrame._tsbBorder = true
                pp.CreateBorder(holderFrame, 0, 0, 0, 1, bsz, "OVERLAY", 7)
            elseif pp.UpdateBorder then
                pp.UpdateBorder(holderFrame, bsz)
            end
            if pp.ShowBorder then
                pp.ShowBorder(holderFrame)
            end
        elseif holderFrame._tsbBorder and pp.HideBorder then
            pp.HideBorder(holderFrame)
        end
    end

    -- Optional icon/bar seam divider (opt-in "Show Icon Divider"), matching
    -- the border color so it reads as part of the same frame.
    if showIcon and conf.showIconDivider then
        local des = holderFrame:GetEffectiveScale()
        local onePixel = (pp and des > 0) and (pp.perfect / des) or ((pp and pp.mult) or 1)
        local dbs = bsz > 0 and bsz or 1
        holderFrame.iconDivider:ClearAllPoints()
        holderFrame.iconDivider:SetWidth(math.max(onePixel, math.floor(dbs + 0.5) * onePixel))
        if iconOnRight then
            holderFrame.iconDivider:SetPoint("TOPRIGHT", holderFrame.iconFrame, "TOPLEFT", 0, 0)
            holderFrame.iconDivider:SetPoint("BOTTOMRIGHT", holderFrame.iconFrame, "BOTTOMLEFT", 0, 0)
        else
            holderFrame.iconDivider:SetPoint("TOPLEFT", holderFrame.iconFrame, "TOPRIGHT", 0, 0)
            holderFrame.iconDivider:SetPoint("BOTTOMLEFT", holderFrame.iconFrame, "BOTTOMRIGHT", 0, 0)
        end
        holderFrame.iconDivider:SetColorTexture(0, 0, 0, 1)
        holderFrame.iconDivider:Show()
    else
        holderFrame.iconDivider:Hide()
    end

    SetFSFont(holderFrame.name, conf.nameSize or 10)
    SetFSFont(holderFrame.target, conf.targetSize or 10)
    SetFSFont(holderFrame.timer, conf.timerSize or 10)

    local showTimer = conf.showTimer ~= false
    local timerReserve = showTimer and ((conf.timerSize or 10) * 2.2) or 0
    AnchorName(holderFrame, conf, holderFrame.marker:IsShown(), holderFrame.target:IsShown())
    holderFrame.timer:ClearAllPoints()
    holderFrame.timer:SetPoint("RIGHT", holderFrame.sb, "RIGHT", -3 + (conf.timerX or 0), conf.timerY or 0)
    holderFrame.target:ClearAllPoints()
    holderFrame.target:SetPoint(
        "RIGHT",
        holderFrame.sb,
        "RIGHT",
        -3 - timerReserve + (conf.targetX or 0),
        conf.targetY or 0
    )
    holderFrame.target:SetWidth((wid - hgt) * 0.40)

    -- Marker size/anchor; visibility and texcoords are per-cast (ApplyRaidMarker).
    local msz = conf.raidMarkerSize or 14
    holderFrame.marker:SetSize(msz, msz)
    holderFrame.marker:ClearAllPoints()
    holderFrame.marker:SetPoint("LEFT", holderFrame.sb, "LEFT", 3, 0)

    holderFrame.name:SetShown(conf.showSpellName ~= false)
    holderFrame.timer:SetShown(showTimer)
    -- target visibility is per-cast (hasTarget); the paint pass owns it

    holderFrame._styleGen = styleGen
end

-- anchor: the frame the slot stacks from (the options header sample's host);
-- the live group passes nothing and stacks from its container.
local function PositionBar(holderFrame, slot, conf, anchor)
    anchor = anchor or boxHolder
    holderFrame:ClearAllPoints()
    local off = (slot - 1) * ((conf.height or 20) + (conf.spacing or 4))
    if conf.growUp then
        holderFrame:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 0, off)
    else
        holderFrame:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, -off)
    end
end

local function Reflow()
    local conf = Cfg()
    if not conf then
        return
    end
    for i = 1, #isShown do
        PositionBar(isShown[i].bar, i, conf)
    end
end

--------------------------------------------------------------------------------
--  Important-cast glow: an engine host by choice (the C-side AnimationGroup
--  path built for the 12.1 forbidden aura partition), so it costs ZERO
--  per-frame Lua regardless of how many bars glow. The engine host draws
--  Pixel, Action Button, GCD, Modern and Classic; a stored Auto-Cast or
--  Shape pick renders as Modern WoW Glow.
--------------------------------------------------------------------------------
local function EnsureGlowOverlay(holderFrame)
    if holderFrame._glow then
        return holderFrame._glow
    end
    local shade = CreateFrame("Frame", nil, holderFrame.sb)
    shade:SetAllPoints(holderFrame.sb)
    shade:SetFrameLevel(holderFrame.sb:GetFrameLevel() + 5)
    shade:EnableMouse(false)
    holderFrame._glow = shade
    return shade
end

local function ClearImportantGlow(holderFrame)
    if holderFrame._glowActive and holderFrame._glow then
        Glows.StopAllGlows(holderFrame._glow)
        holderFrame._glow:SetAlpha(0)
        holderFrame._glow:Hide()
        holderFrame._glowActive = false
    end
end

local IMP_GLOW_SPEC = {}
local function StartImportantGlowAnim(holderFrame, conf)
    local shade = EnsureGlowOverlay(holderFrame)
    local color = conf.importantGlowColor or { r = 1, g = 0.2, b = 0.2 }
    local bgc = conf.importantGlowBackgroundColor
    local specInfo = IMP_GLOW_SPEC
    specInfo.style = conf.importantGlowStyle or 1
    specInfo.r, specInfo.g, specInfo.b =
        Glows.ResolveColor(conf.importantGlowColorMode or "custom", color.r, color.g, color.b)
    specInfo.lines, specInfo.thickness, specInfo.speed =
        conf.importantGlowLines, conf.importantGlowThickness, conf.importantGlowSpeed
    specInfo.bg = (conf.importantGlowBackground == true) or nil
    specInfo.bgR, specInfo.bgG, specInfo.bgB = bgc and bgc.r, bgc and bgc.g, bgc and bgc.b
    local pW, pH = holderFrame.sb:GetWidth(), holderFrame.sb:GetHeight()
    if pW < 5 then
        pW = 100
    end
    if pH < 5 then
        pH = 14
    end
    -- Restarts only on a real style/color/param/size change, never per cast event.
    Glows.StartSpecGlow(shade, specInfo, pW, pH, "engine")
    holderFrame._glowActive = true
    shade:Show()
    return shade
end

-- e._important may be true / false / a SECRET boolean (C_Spell.IsSpellImportant
-- can return secret under restricted execution) -- only the issecretvalue()
-- branch below is allowed to touch it without deciding what it IS.
local function ApplyImportantGlow(e, conf)
    local holderFrame = e.bar
    if not conf.importantGlow then
        ClearImportantGlow(holderFrame)
        return
    end
    local imp = e._important
    if type(imp) == "nil" then
        ClearImportantGlow(holderFrame)
        return
    end
    if issecretvalue and issecretvalue(imp) then
        -- Must run the animation regardless; only its alpha carries the answer.
        -- The glow start forces alpha 1 on (re)start, so the boolean alpha
        -- assignment always runs AFTER the start call, never before.
        local shade = StartImportantGlowAnim(holderFrame, conf)
        shade:SetAlphaFromBoolean(imp)
        return
    end
    -- Known, non-secret boolean: safe to branch directly.
    if imp then
        local shade = StartImportantGlowAnim(holderFrame, conf)
        shade:SetAlpha(1)
    else
        ClearImportantGlow(holderFrame)
    end
end

--------------------------------------------------------------------------------
--  Cast color: kick-ready tint and uninterruptible wash always apply (Cast
--  Colors has no off switch); the important-cast tint blends in on top only
--  when enabled. All secret combines ride C_CurveUtil boolean curves or
--  SetAlphaFromBoolean; nothing branches on a secret.
--------------------------------------------------------------------------------
-- Kick off-cooldown flag (possibly SECRET), read ONCE per slow pass and shared
-- by every bar; nil when the API is unavailable (callers fall back to the
-- shared per-call tint helper).
local function KickOffCooldown()
    local kick = GetActiveKickSpell and GetActiveKickSpell()
    if not (kick and C_Spell and C_Spell.GetSpellCooldownDuration) then
        return nil
    end
    local cd = C_Spell.GetSpellCooldownDuration(kick)
    if not (cd and cd.IsZero) then
        return nil
    end
    return cd:IsZero()
end

local impScratch = {}
-- offCd: pre-read KickOffCooldown() for batched passes; omitted on per-cast
-- paints. Same blend as the shared helper (off cooldown = base, on = ready tint).
local function ApplyCastColor(e, conf, offCd)
    local holderFrame = e.bar
    holderFrame.overlay:SetAlphaFromBoolean(e._kickProtected)
    local base = conf.barColor or { r = 0.70, g = 0.40, b = 0.90 }
    local ev = C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean
    if conf.importantEnabled and ev then
        local imp = e._important
        if type(imp) == "nil" then
            imp = false
        end
        local ic = conf.importantColor or { r = 1, g = 0.2, b = 0.2 }
        impScratch.r = ev(imp, ic.r, base.r)
        impScratch.g = ev(imp, ic.g, base.g)
        impScratch.b = ev(imp, ic.b, base.b)
        base = impScratch
    end
    local cr, cg, callback = base.r, base.g, base.b
    local ready = conf.interruptReady or { r = 0.92, g = 0.35, b = 0.20 }
    if type(offCd) ~= "nil" and ev then
        cr = ev(offCd, base.r, ready.r)
        cg = ev(offCd, base.g, ready.g)
        callback = ev(offCd, base.b, ready.b)
    elseif ComputeCastBarTint then
        cr, cg, callback = ComputeCastBarTint(ready, base)
    end
    holderFrame.sb:GetStatusBarTexture():SetVertexColor(cr, cg, callback)
end

--------------------------------------------------------------------------------
--  Raid target marker: left of the spell name. Deliberately NOT
--  SetRaidTargetIconTexture -- that helper derives texcoords with Lua
--  arithmetic on the index, which throws on a secret number.
--  GetRaidTargetIndex is a known secret-prone call.
--------------------------------------------------------------------------------
local function ApplyRaidMarker(e, conf)
    local holderFrame = e.bar
    if not conf.showRaidMarker then
        if holderFrame.marker:IsShown() then
            holderFrame.marker:Hide()
            AnchorName(holderFrame, conf, false, holderFrame.target:IsShown())
        end
        return
    end
    local position = GetRaidTargetIndex and GetRaidTargetIndex(e.unit)
    if type(position) == "nil" then -- type() is the taint-safe existence check
        if holderFrame.marker:IsShown() then
            holderFrame.marker:Hide()
            AnchorName(holderFrame, conf, false, holderFrame.target:IsShown())
        end
        return
    end
    if issecretvalue and issecretvalue(position) then
        if holderFrame.marker.SetSpriteSheetCell then
            pcall(holderFrame.marker.SetSpriteSheetCell, holderFrame.marker, position, 4, 4, 64, 64)
        end
    else
        local tc = RAID_MARKER_TEXCOORDS[position]
        if tc then
            holderFrame.marker:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
        end
    end
    holderFrame.marker:Show()
    AnchorName(holderFrame, conf, true, holderFrame.target:IsShown())
end

--------------------------------------------------------------------------------
--  Out-of-interrupt-range fade: dims the whole bar (icon, texts, marker, glow
--  together) when the unit is beyond the player's active interrupt spell's
--  range. Secret-safe idiom: issecretvalue() runs BEFORE the ~= nil check so
--  the comparison never touches a secret value.
--------------------------------------------------------------------------------
local function ApplyRangeAlpha(e, conf)
    local holderFrame = e.bar
    if
        not (
            conf.oorEnabled
            and GetActiveKickSpell
            and GetActiveKickSpell()
            and C_Spell
            and C_Spell.IsSpellInRange
        )
    then
        if e._oorApplied then
            holderFrame:SetAlpha(1)
            e._oorApplied = nil
        end
        return
    end
    local inRange = C_Spell.IsSpellInRange(GetActiveKickSpell(), e.unit)
    if (issecretvalue and issecretvalue(inRange)) or inRange ~= nil then
        holderFrame:SetAlphaFromBoolean(inRange, 1, conf.oorAlpha or 0.45)
    else
        holderFrame:SetAlpha(1)
    end
    e._oorApplied = true
end

--------------------------------------------------------------------------------
--  Duration lookup: ArmFill already knows which getter applies (it picks the
--  fill direction), so the timer text reuses that instead of trying all three
--  duration APIs every tick (O2). Falls back to the full chain on a transient
--  miss or before any kind has been cached, so behaviour never regresses.
--------------------------------------------------------------------------------
local function GetDurationObj(e)
    local kind = e.durKind
    if kind == "cast" then
        local skinData = UnitCastingDuration(e.unit)
        if skinData then
            return skinData
        end
    elseif kind == "empowered" then
        local skinData = UnitEmpoweredChannelDuration and UnitEmpoweredChannelDuration(e.unit, true)
        if skinData then
            return skinData
        end
    elseif kind == "channel" then
        local skinData = UnitChannelDuration and UnitChannelDuration(e.unit)
        if skinData then
            return skinData
        end
    end
    return UnitCastingDuration(e.unit)
        or (UnitEmpoweredChannelDuration and UnitEmpoweredChannelDuration(e.unit, true))
        or (UnitChannelDuration and UnitChannelDuration(e.unit))
end

--------------------------------------------------------------------------------
--  Shared 10Hz timer text: one ticker for the whole group, armed only while
--  needed (O1), self-stops when the last bar releases. Remaining time comes
--  from the duration object only -- cast start/end times are secret and
--  unusable in arithmetic. Also drives a 0.2s slow pass (every 2nd fire) for
--  kick-ready repaint and range fade, since neither reliably fires a naming
--  event (a kick coming off cooldown, or walking back into range).
--------------------------------------------------------------------------------
local function TimerBody()
    local num = #isShown
    if num == 0 then
        return false
    end
    local conf = Cfg()
    local showTimer = UnitCastingDuration and conf and conf.showTimer ~= false
    if showTimer then
        for i = 1, num do
            local e = isShown[i]
            if not e.preview then
                local fontStr = e.bar.timer
                local durObj = GetDurationObj(e)
                if durObj then
                    fontStr:SetFormattedText("%.1f", durObj:GetRemainingDuration())
                else
                    fontStr:SetText("")
                end
            end
        end
    end

    local wantColor = conf and GetActiveKickSpell and GetActiveKickSpell()
    local wantRange = conf and conf.oorEnabled
    if wantColor or wantRange then
        slowAccum = slowAccum + 1
        if slowAccum >= 2 then
            slowAccum = 0
            -- One cooldown read per pass, not per bar. Plain assignment: the
            -- flag can be SECRET, and `x and flag or y` would boolean-test it.
            local offCd
            if wantColor then
                offCd = KickOffCooldown()
            end
            for i = 1, num do
                local e = isShown[i]
                if not e.preview then
                    if wantColor then
                        ApplyCastColor(e, conf, offCd)
                    end
                    if wantRange then
                        ApplyRangeAlpha(e, conf)
                    end
                end
            end
        end
    end

    return true
end

local function ArmTimerTicker()
    local conf = Cfg()
    -- O1: don't arm the ticker at all unless something needs its 10Hz tick --
    -- the timer text, or one of the polling features.
    local needed = conf
        and (conf.showTimer ~= false or conf.oorEnabled or (GetActiveKickSpell and GetActiveKickSpell()))
    if not needed then
        return
    end
    if not timerTicker and CludesUI.Tick and CludesUI.Tick.NewAnimTicker then
        timerTicker = CludesUI.Tick.NewAnimTicker(EnsureContainer(), TimerBody, 0.1)
    end
    if timerTicker then
        TimerBody()
        timerTicker.Start()
    end
end

--------------------------------------------------------------------------------
--  Cast lifecycle
--------------------------------------------------------------------------------
local function ArmFill(e, isChannel)
    local scrollBar = e.bar.sb
    if not (UnitCastingDuration and scrollBar.SetTimerDuration) then
        return
    end
    local dur, isEmp
    if isChannel then
        if UnitEmpoweredChannelDuration then
            dur = UnitEmpoweredChannelDuration(e.unit, true)
            if dur then
                isEmp = true
            end
        end
        if not dur then
            dur = UnitChannelDuration(e.unit)
        end
        if dur then
            scrollBar:SetReverseFill(false)
            -- Empowered channels build forward; normal channels drain.
            local dirn = isEmp and Enum.StatusBarTimerDirection.ElapsedTime
                or Enum.StatusBarTimerDirection.RemainingTime
            scrollBar:SetTimerDuration(dur, nil, dirn)
            e.durKind = isEmp and "empowered" or "channel"
        end
    else
        dur = UnitCastingDuration(e.unit)
        if dur then
            scrollBar:SetReverseFill(false)
            scrollBar:SetTimerDuration(dur, nil, Enum.StatusBarTimerDirection.ElapsedTime)
            e.durKind = "cast"
        end
    end
end

local function PaintTarget(e, conf)
    local holderFrame = e.bar
    local fontStr = holderFrame.target
    if conf.showTarget == false then
        fontStr:SetText("")
        fontStr:Hide()
        AnchorName(holderFrame, conf, holderFrame.marker:IsShown(), false)
        return
    end
    local spellTarget, spellTargetClass
    if UnitShouldDisplaySpellTargetName and UnitShouldDisplaySpellTargetName(e.unit) then
        -- Names may be SECRET: type() is the safe existence check, and
        -- SetText accepts secret strings without exposing them to Lua.
        local raw = UnitSpellTargetName and UnitSpellTargetName(e.unit)
        if type(raw) ~= "nil" then
            spellTarget = raw
            spellTargetClass = UnitSpellTargetClass and UnitSpellTargetClass(e.unit)
        end
    end
    if type(spellTarget) == "nil" then
        fontStr:SetText("")
        fontStr:Hide()
        AnchorName(holderFrame, conf, holderFrame.marker:IsShown(), false)
        return
    end
    if conf.targetClassColor ~= false and type(spellTargetClass) ~= "nil" and C_ClassColor then
        local colour = C_ClassColor.GetClassColor(spellTargetClass)
        if colour then
            fontStr:SetTextColor(colour:GetRGB())
        else
            fontStr:SetTextColor(1, 1, 1, 1)
        end
    else
        local tc = conf.targetColor
        if tc then
            fontStr:SetTextColor(tc.r, tc.g, tc.b, 1)
        else
            fontStr:SetTextColor(1, 1, 1, 1)
        end
    end
    fontStr:SetText(spellTarget)
    fontStr:Show()
    AnchorName(holderFrame, conf, holderFrame.marker:IsShown(), true)
end

local function Release(unitToken)
    local e = unitEntry[unitToken]
    if not e then
        return
    end
    unitEntry[unitToken] = nil
    for i = 1, #isShown do
        if isShown[i] == e then
            table.remove(isShown, i)
            break
        end
    end
    -- Bars are pooled and reused forever: every piece of per-cast visual state
    -- set by the new features must be cleared here, or the next occupant
    -- inherits it.
    local holderFrame = e.bar
    ClearImportantGlow(holderFrame)
    holderFrame:SetAlpha(1)
    holderFrame.overlay:SetAlpha(0)
    holderFrame.marker:Hide()
    holderFrame._tsbInUse = nil
    holderFrame:Hide()
    Reflow()
end

-- Only CLEANLY-friendly plates are excluded (friendly NPC nameplates). The
-- attackable flag can be SECRET in instanced combat; a secret answer fail-
-- OPENS (the cast shows) rather than ever branching on the secret.
local function IsTrackableUnit(unitToken)
    local success, att = pcall(UnitCanAttack, "player", unitToken)
    if success and not (issecretvalue and issecretvalue(att)) and att == false then
        return false
    end
    return true
end

local PromoteWaiting -- forward: StartCast <-> PromoteWaiting recursion

local function StartCast(unitToken)
    local conf = Cfg()
    if not conf then
        return
    end
    local name, _, texture, _, _, _, _, kickProtected, castSpellID = UnitCastingInfo(unitToken)
    local isChannel = false
    if type(name) == "nil" then
        name, _, texture, _, _, _, kickProtected, castSpellID = UnitChannelInfo(unitToken)
        isChannel = true
    end
    if type(name) == "nil" then
        Release(unitToken)
        if PromoteWaiting then
            PromoteWaiting()
        end
        return
    end
    if not IsTrackableUnit(unitToken) then
        return
    end

    local e = unitEntry[unitToken]
    local isNew = false
    if not e then
        if #isShown >= (conf.maxBars or 5) then
            anyCastDropped = true -- promoted when a slot frees (O4)
            return
        end
        e = { unit = unitToken, bar = AcquireBarFrame() }
        unitEntry[unitToken] = e
        isShown[#isShown + 1] = e
        isNew = true
        PositionBar(e.bar, #isShown, conf)
    end
    -- O3: a bar only needs a full restyle once per settings generation, not on
    -- every cast -- new/reused-from-pool bars never carry the current stamp.
    if isNew or e.bar._styleGen ~= styleGen then
        StyleBar(e.bar, conf)
    end
    e.isChannel = isChannel
    e.preview = nil

    if type(kickProtected) == "nil" then
        kickProtected = false
    end
    e._kickProtected = kickProtected
    -- Important flag may be SECRET: stored raw, fed only to color curves and
    -- SetAlphaFromBoolean, never branched on directly.
    e._important = false
    if C_Spell and C_Spell.IsSpellImportant then
        local impOK, imp = pcall(C_Spell.IsSpellImportant, castSpellID or 0)
        if impOK then
            e._important = imp
        end
    end

    -- Icon and name MUST describe the SAME cast: both come from this
    -- snapshot. The live texture may be SECRET -- SetTexture accepts it.
    if conf.showIcon ~= false then
        if type(texture) ~= "nil" then
            e.bar.icon:SetTexture(texture)
        elseif type(castSpellID) ~= "nil" then
            local okInfo, details = pcall(C_Spell.GetSpellInfo, castSpellID)
            if okInfo and type(details) == "table" then
                e.bar.icon:SetTexture(details.iconID)
            else
                e.bar.icon:SetTexture(nil)
            end
        else
            e.bar.icon:SetTexture(nil)
        end
    end
    -- PaintTarget/ApplyRaidMarker first: they size bar.name for this cast's
    -- target/marker state, and SetWidth after SetText does not reliably
    -- re-truncate an already-laid-out FontString.
    PaintTarget(e, conf)
    ApplyRaidMarker(e, conf)
    if conf.showSpellName ~= false then
        e.bar.name:SetText(name)
    end
    ApplyCastColor(e, conf)
    ApplyImportantGlow(e, conf)
    e.bar.timer:SetText("")
    ArmFill(e, isChannel)
    ApplyRangeAlpha(e, conf)
    e.bar:Show()
    ArmTimerTicker()
end

-- Fill freed slots from plates that were casting while the group was full.
-- O4: only scans plateUnits when a cast was actually dropped at the cap --
-- with nothing ever dropped, every release is a free no-op instead of a full
-- plate walk.
PromoteWaiting = function()
    if not anyCastDropped then
        return
    end
    local conf = Cfg()
    if not conf then
        return
    end
    if #isShown >= (conf.maxBars or 5) then
        return
    end
    anyCastDropped = false
    for unitToken in pairs(plateUnits) do
        if not unitEntry[unitToken] then
            local nm = UnitCastingInfo(unitToken)
            if type(nm) == "nil" then
                nm = UnitChannelInfo(unitToken)
            end
            if type(nm) ~= "nil" then
                StartCast(unitToken)
                if #isShown >= (conf.maxBars or 5) then
                    return
                end
            end
        end
    end
end

-- Mid-cast interruptibility flips: re-read protection once, store, repaint.
-- Port of the TargetFocusBars KickProtectionChanged pattern.
local function RefreshKickProtection(unitToken)
    local conf = Cfg()
    if not conf then
        return
    end
    local e = unitEntry[unitToken]
    if not e then
        return
    end
    local kickProtected
    local sName, _, _, _, _, _, _, kp = UnitCastingInfo(unitToken)
    if type(sName) ~= "nil" then
        kickProtected = kp
    else
        local cName
        cName, _, _, _, _, _, kp = UnitChannelInfo(unitToken)
        if type(cName) == "nil" then
            return
        end
        kickProtected = kp
    end
    if type(kickProtected) == "nil" then
        kickProtected = false
    end
    e._kickProtected = kickProtected
    ApplyCastColor(e, conf)
end

local function RefreshAllRaidMarkers()
    local conf = Cfg()
    if not conf then
        return
    end
    for i = 1, #isShown do
        local e = isShown[i]
        if not e.preview then
            ApplyRaidMarker(e, conf)
        end
    end
end

--------------------------------------------------------------------------------
--  Events: registered ONLY while enabled. One frame; unit filtering is the
--  plateUnits hash (nameplate tokens only -- party/raid cast chatter costs
--  one failed lookup).
--------------------------------------------------------------------------------
local evt = CreateFrame("Frame")

local START_EVENTS = {
    UNIT_SPELLCAST_START = true,
    UNIT_SPELLCAST_CHANNEL_START = true,
    UNIT_SPELLCAST_EMPOWER_START = true,
}
local UPDATE_EVENTS = {
    UNIT_SPELLCAST_DELAYED = true,
    UNIT_SPELLCAST_CHANNEL_UPDATE = true,
    UNIT_SPELLCAST_EMPOWER_UPDATE = true,
}
local PROBE_EVENTS = {
    UNIT_SPELLCAST_STOP = true,
    UNIT_SPELLCAST_FAILED = true,
}
-- These release directly instead of re-probing: in restricted execution the
-- cast-info reads can return secret values (not nil) for a stale channel or
-- empowered cast, making a probe think it is still active (nameplate lesson).
local RELEASE_EVENTS = {
    UNIT_SPELLCAST_CHANNEL_STOP = true,
    UNIT_SPELLCAST_EMPOWER_STOP = true,
    UNIT_SPELLCAST_INTERRUPTED = true,
}

evt:SetScript("OnEvent", function(_, event, unitToken)
    -- The plate roster is kept current for as long as the FEATURE is enabled,
    -- not only while the group is live: the Where to Show gate can switch the
    -- group on mid-combat ("In Combat"), and the plates that already exist at
    -- that moment have to be known. Reading them back with
    -- C_NamePlate.GetNamePlates() at that point does not answer in combat,
    -- which left every already-visible caster untracked until its plate was
    -- removed and re-added.
    if event == "NAME_PLATE_UNIT_ADDED" then
        if not unitToken then
            return
        end
        plateUnits[unitToken] = true
        if not isActive or previewOn then
            return
        end
        -- Probe the delta: only this plate, only if it is mid-cast.
        local nm = UnitCastingInfo(unitToken)
        if type(nm) == "nil" then
            nm = UnitChannelInfo(unitToken)
        end
        if type(nm) ~= "nil" then
            StartCast(unitToken)
        end
        return
    end
    if event == "NAME_PLATE_UNIT_REMOVED" then
        if not unitToken then
            return
        end
        plateUnits[unitToken] = nil
        if not isActive or previewOn then
            return
        end
        Release(unitToken)
        PromoteWaiting()
        return
    end
    if previewOn then
        return
    end
    if event == "RAID_TARGET_UPDATE" then
        RefreshAllRaidMarkers()
        return
    end
    -- Spellcast family: nameplate units only.
    if not unitToken or not plateUnits[unitToken] then
        return
    end
    if START_EVENTS[event] then
        StartCast(unitToken)
    elseif UPDATE_EVENTS[event] then
        local e = unitEntry[unitToken]
        if e then
            ArmFill(e, e.isChannel)
        end
    elseif PROBE_EVENTS[event] then
        if unitEntry[unitToken] then
            StartCast(unitToken)
        end
    elseif RELEASE_EVENTS[event] then
        Release(unitToken)
        PromoteWaiting()
    elseif event == "UNIT_SPELLCAST_INTERRUPTIBLE" or event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
        RefreshKickProtection(unitToken)
    end
end)

-- Registered while the feature is enabled (roster only, see the handler above).
local PLATE_EVENTS = { "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED" }

-- Registered only while the group is live.
local CAST_EVENTS = {
    "UNIT_SPELLCAST_START",
    "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_EMPOWER_START",
    "UNIT_SPELLCAST_DELAYED",
    "UNIT_SPELLCAST_CHANNEL_UPDATE",
    "UNIT_SPELLCAST_EMPOWER_UPDATE",
    "UNIT_SPELLCAST_STOP",
    "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_EMPOWER_STOP",
    "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_INTERRUPTIBLE",
    "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
}

-- RAID_TARGET_UPDATE only while the marker feature is on (zero cost otherwise).
local function SyncMarkerEvent(conf)
    if not isActive then
        return
    end
    if conf and conf.showRaidMarker then
        evt:RegisterEvent("RAID_TARGET_UPDATE")
    else
        evt:UnregisterEvent("RAID_TARGET_UPDATE")
    end
end

local function ReleaseAll()
    for i = #isShown, 1, -1 do
        local e = isShown[i]
        unitEntry[e.unit] = nil
        local holderFrame = e.bar
        ClearImportantGlow(holderFrame)
        holderFrame:SetAlpha(1)
        holderFrame.overlay:SetAlpha(0)
        holderFrame.marker:Hide()
        holderFrame._tsbInUse = nil
        holderFrame:Hide()
        isShown[i] = nil
    end
end

-- Plate roster lifecycle: tied to cfg.enabled, never to `active`.
local plateRoster = false
local function SetPlateRosterActive(on)
    on = on and true or false
    if on == plateRoster then
        return
    end
    plateRoster = on
    if on then
        for i = 1, #PLATE_EVENTS do
            evt:RegisterEvent(PLATE_EVENTS[i])
        end
    else
        for i = 1, #PLATE_EVENTS do
            evt:UnregisterEvent(PLATE_EVENTS[i])
        end
        wipe(plateUnits)
    end
end

-- Seed from plates that already exist (mid-session enable, or the gate turning
-- the group on mid-combat). The event-maintained roster is the source of truth;
-- this sweep only tops it up with plates that appeared BEFORE the feature was
-- enabled. It walks the unit tokens: a plate's namePlateUnitToken can be nil
-- when polled outside its NAME_PLATE_UNIT_ADDED.
local NAMEPLATE_TOKENS = mod.NAMEPLATE_TOKENS

local function SeedFromLivePlates()
    for i = 1, #NAMEPLATE_TOKENS do
        local u = NAMEPLATE_TOKENS[i]
        if UnitExists(u) then
            plateUnits[u] = true
        end
    end
    for unitToken in pairs(plateUnits) do
        local nm = UnitCastingInfo(unitToken)
        if type(nm) == "nil" then
            nm = UnitChannelInfo(unitToken)
        end
        if type(nm) ~= "nil" then
            StartCast(unitToken)
        end
    end
end

local function Activate()
    if isActive then
        return
    end
    isActive = true
    EnsureContainer()
    for i = 1, #CAST_EVENTS do
        evt:RegisterEvent(CAST_EVENTS[i])
    end
    SyncMarkerEvent(Cfg())
    SeedFromLivePlates()
end

local function Deactivate()
    if not isActive then
        return
    end
    isActive = false
    -- Cast traffic only: the plate roster stays registered so a later
    -- mid-combat Activate() already knows every plate on screen.
    for i = 1, #CAST_EVENTS do
        evt:UnregisterEvent(CAST_EVENTS[i])
    end
    evt:UnregisterEvent("RAID_TARGET_UPDATE")
    ReleaseAll()
end

SyncWhereActive = function()
    local conf = Cfg()
    -- Feature off: nothing runs, and a lingering preview goes down with it.
    if not (conf and conf.enabled == true) then
        if isActive then
            Deactivate()
        end
        previewOn = false
        return
    end
    -- The preview owns the display while it runs: the unlock mover must show
    -- sample bars wherever the player stands, including content the Where to
    -- Show filter excludes. Leaving it re-applies the gate.
    if previewOn then
        return
    end
    local wanted = MTWhere.Shows(conf.whereToShow, WHERE_KEYS)
    if wanted and not isActive then
        Activate()
    elseif not wanted and isActive then
        Deactivate()
    end
end

--------------------------------------------------------------------------------
--  Preview: sample bars for options / unlock placement. Static content --
--  plain SetValue (cancels timer mode) so nothing animates or reads units.
--  Every new feature gets one sample row so it is visible while configuring.
--------------------------------------------------------------------------------
local PREVIEW_ROWS = {
    { name = "Shadow Bolt", fill = 0.65, timer = "1.2" },
    { name = "Mending", fill = 0.35, timer = "2.4", uninterruptible = true },
    { name = "Terrifying Roar", fill = 0.85, timer = "0.6", marker = 8, important = true },
}

-- One sample row: style, stack into `slot` from `anchor` (nil = the group
-- container) and paint the static content. `e` is an entry table (e.bar,
-- e._important), shared by the on-screen preview and the options header
-- sample.
local function PaintSampleRow(e, conf, sample, slot, anchor)
    StyleBar(e.bar, conf)
    PositionBar(e.bar, slot, conf, anchor)
    e.bar:SetAlpha(1)
    e.bar.icon:SetTexture(134400)
    local hasTarget = conf.showTarget ~= false
    if hasTarget then
        local tc = conf.targetColor
        if conf.targetClassColor ~= false and C_ClassColor and UnitClassBase then
            -- Class token only: UnitClassBase also returns the class ID, which
            -- would land in GetClassColor's optional tint color argument.
            local colour = C_ClassColor.GetClassColor((UnitClassBase("player")))
            if colour then
                e.bar.target:SetTextColor(colour:GetRGB())
            end
        elseif tc then
            e.bar.target:SetTextColor(tc.r, tc.g, tc.b, 1)
        end
        e.bar.target:SetText(UnitName("player") or "Target")
        e.bar.target:Show()
    else
        e.bar.target:SetText("")
        e.bar.target:Hide()
    end

    -- Raid marker sample: static, non-secret index.
    if conf.showRaidMarker and sample.marker then
        local tc = RAID_MARKER_TEXCOORDS[sample.marker]
        if tc then
            e.bar.marker:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
        end
        e.bar.marker:Show()
        AnchorName(e.bar, conf, true, hasTarget)
    else
        e.bar.marker:Hide()
        AnchorName(e.bar, conf, false, hasTarget)
    end
    -- Name sized/anchored above; SetWidth after SetText does not reliably
    -- re-truncate an already-laid-out FontString.
    if conf.showSpellName ~= false then
        e.bar.name:SetText(sample.name)
    end
    e.bar.timer:SetText(conf.showTimer ~= false and sample.timer or "")
    e.bar.sb:SetValue(sample.fill)

    -- Uninterruptible / kick-ready sample: static, no live unit involved.
    if sample.uninterruptible then
        e.bar.overlay:SetAlpha(1)
        local un = conf.uninterruptible or { r = 0.45, g = 0.45, b = 0.45 }
        e.bar.sb:GetStatusBarTexture():SetVertexColor(un.r, un.g, un.b)
    else
        e.bar.overlay:SetAlpha(0)
        local color = conf.barColor
        if color then
            e.bar.sb:GetStatusBarTexture():SetVertexColor(color.r, color.g, color.b)
        end
    end

    -- Important sample: tint and/or glow, both driven by a plain (never
    -- secret) boolean here.
    e._important = sample.important == true
    if conf.importantEnabled and sample.important then
        local ic = conf.importantColor or { r = 1, g = 0.2, b = 0.2 }
        e.bar.sb:GetStatusBarTexture():SetVertexColor(ic.r, ic.g, ic.b)
    end
    if conf.importantGlow and sample.important then
        ApplyImportantGlow(e, conf)
    else
        ClearImportantGlow(e.bar)
    end

    e.bar:Show()
end

local function ShowPreview()
    local conf = Cfg()
    if not conf then
        return
    end
    ReleaseAll()
    EnsureContainer()
    local rowList = math.min(#PREVIEW_ROWS, conf.maxBars or 5)
    for i = 1, rowList do
        local e = { unit = "preview" .. i, bar = AcquireBarFrame(), preview = true }
        isShown[#isShown + 1] = e
        PaintSampleRow(e, conf, PREVIEW_ROWS[i], i, nil)
    end
end

--------------------------------------------------------------------------------
--  Options header sample: the first preview row, built ONCE on the header's
--  column host and painted static on every call (no events, tickers or
--  OnUpdate; a plain SetValue fill). The holder never joins the live pool,
--  so the cast lifecycle, the restyle pass and the ticker never see it.
--------------------------------------------------------------------------------
local sampleBar
local sampleEntry = { unit = "sample", preview = true }

-- Hangs the sample at the host's TOPLEFT and returns its size (width, height
-- in the host's units); nil before the settings exist.
function mod.TSB_PaintSample(owner)
    local conf = Cfg()
    if not conf then
        return nil
    end
    if not sampleBar then
        sampleBar = BuildBar(owner)
    end
    sampleEntry.bar = sampleBar
    sampleBar:SetParent(owner)
    sampleBar._styleGen = nil
    PaintSampleRow(sampleEntry, conf, PREVIEW_ROWS[1], 1, owner)
    return conf.width or 240, conf.height or 20
end

function mod.TSB_SetPreview(on)
    previewOn = on == true
    if previewOn then
        ShowPreview()
    else
        ReleaseAll()
        -- The gate was held open while the preview ran: re-apply it before
        -- reseeding, so leaving the preview lands on the real content state.
        SyncWhereActive()
        if isActive then
            SeedFromLivePlates()
        end
    end
end

function mod.TSB_IsPreview()
    return previewOn
end

--------------------------------------------------------------------------------
--  Refresh: the one entry point for enable/disable + live restyle. Options
--  call this after every settings write.
--------------------------------------------------------------------------------
function mod.TSB_Refresh()
    local conf = Cfg()
    if conf and conf.enabled == true then
        MTWhere.Subscribe("tsb", SyncWhereActive)
    else
        MTWhere.Unsubscribe("tsb")
    end
    SetPlateRosterActive(conf and conf.enabled == true)
    SyncWhereActive()
    if not conf then
        return
    end
    SyncMarkerEvent(conf)
    styleGen = styleGen + 1 -- O3: invalidate every bar's cached style stamp
    if boxHolder then
        boxHolder:SetSize(conf.width or 240, conf.height or 20)
        ApplyContainerPosition()
    end
    if previewOn then
        ShowPreview()
        return
    end
    -- Restyle live bars in place; trim overflow if Max Bars shrank.
    local maxBars = conf.maxBars or 5
    for i = #isShown, maxBars + 1, -1 do
        local e = isShown[i]
        unitEntry[e.unit] = nil
        local holderFrame = e.bar
        ClearImportantGlow(holderFrame)
        holderFrame:SetAlpha(1)
        holderFrame.overlay:SetAlpha(0)
        holderFrame.marker:Hide()
        holderFrame._tsbInUse = nil
        holderFrame:Hide()
        isShown[i] = nil
    end
    for i = 1, #isShown do
        local e = isShown[i]
        StyleBar(e.bar, conf)
        PositionBar(e.bar, i, conf)
        if not e.preview then
            ApplyRaidMarker(e, conf)
            ApplyCastColor(e, conf)
            ApplyImportantGlow(e, conf)
            ApplyRangeAlpha(e, conf)
        end
    end
    ArmTimerTicker()
end

--------------------------------------------------------------------------------
--  Unlock mode: one group element. Registered once at init (a stored table);
--  the mover is hidden while the feature is disabled.
--------------------------------------------------------------------------------
local function RegisterUnlock()
    local MK = CludesUI.MakeUnlockElement
    CludesUI:RegisterUnlockElements({
        MK({
            key = "EMT_TargetedSpellBars",
            label = "Cast Bars",
            group = "Mythic+",
            order = 521,
            -- Sized by the options sliders (no drag-resize handle), but the
            -- group can size-MATCH another element and be matched TO: the match
            -- apply pushes through setWidth/setHeight into the same cfg keys
            -- the sliders write (per-bar size; the container relayouts).
            noResize = true,
            allowMatchSource = true,
            isHidden = function()
                local conf = Cfg()
                return not (conf and conf.enabled == true)
            end,
            getFrame = function()
                return EnsureContainer()
            end,
            getSize = function()
                local conf = Cfg()
                return (conf and conf.width) or 240, (conf and conf.height) or 20
            end,
            setWidth = function(_, wid)
                local conf = Cfg()
                if not conf then
                    return
                end
                conf.width = math.floor(wid + 0.5)
                mod.TSB_Refresh()
            end,
            setHeight = function(_, hgt)
                local conf = Cfg()
                if not conf then
                    return
                end
                conf.height = math.floor(hgt + 0.5)
                mod.TSB_Refresh()
            end,
            savePos = function(_, _, _, posX, posY)
                -- Unlock mode hands over CENTER/CENTER coords; on Cancel the frame
                -- still sits at the dragged spot, so never read the live position.
                local conf = Cfg()
                if not (conf and posX and posY) then
                    return
                end
                conf.pos = { centerX = posX, centerY = posY }
                if not CludesUI._unlockActive then
                    ApplyContainerPosition()
                end
            end,
            loadPos = function()
                local conf = Cfg()
                local place = conf and conf.pos
                if not (place and place.centerX and place.centerY) then
                    return nil
                end
                return { point = "CENTER", relPoint = "CENTER", x = place.centerX, y = place.centerY }
            end,
            clearPos = function()
                local conf = Cfg()
                if conf then
                    conf.pos = nil
                end
            end,
            applyPos = function()
                ApplyContainerPosition()
            end,
        }),
    }, "CludesUIMythicTimer")

    if CludesUI.RegisterUnlockModeListener then
        CludesUI:RegisterUnlockModeListener("EMT_TargetedSpellBars", function(unlockActive)
            local conf = Cfg()
            if not (conf and conf.enabled == true) then
                return
            end
            -- Sample bars while placing; back to live content on exit.
            mod.TSB_SetPreview(unlockActive == true)
            local anchored = CludesUI.IsUnlockAnchored and CludesUI.IsUnlockAnchored("EMT_TargetedSpellBars")
            if not anchored then
                ApplyContainerPosition()
            end
        end)
    end
end

--------------------------------------------------------------------------------
--  Init: called from EMT:OnEnable (before the timer's own enable guard).
--------------------------------------------------------------------------------
function mod.TSB_OnEnable(database)
    saved = database
    if not saved then
        return
    end
    RegisterUnlock()
    mod.TSB_Refresh()
end
