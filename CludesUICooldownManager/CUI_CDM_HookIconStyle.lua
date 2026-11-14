if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_CDM_HookIconStyle.lua
--
--  The active aura cache, IsFrameIncluded, hiding Blizzard's decorations, stock
--  icon art and the charge cooldown style.
--  Reads the earlier hook files through ns and ns._hookInternals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._hookInternals
-- CludesUICdmHooks.lua or an earlier hook file failed to load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local barDataByKey = mod.barDataByKey
local _ecmeFC = mod._ecmeFC
local FC = mod.FC

local hookFrameData, ResolveSpellSettings = Inner.hookFrameData, Inner.ResolveSpellSettings

-- The options page pool's table (CludesUI_PixelPerfect.lua makes it; the
-- options addon fills it in place): read through this file local, never the
-- public slot, so nothing written to that slot later reaches the live icons.
local POOL = CludesUI._Pool

-------------------------------------------------------------------------------
--  Active aura cache (consumed by bar glow overlays)
--  Maintained by the 0.1s buff ticker, NOT here: it walks viewer pools cheaply
--  and writes spellID->true for any frame whose Blizzard-set
--  wasSetFromAura/auraInstanceID indicates an active aura. Bar glows read
--  ns._tickBlizzActiveCache.
-------------------------------------------------------------------------------
local _activeCache = {}
mod._tickBlizzActiveCache = _activeCache

-- Per-spellID application count, same population pass as _activeCache above,
-- same sid/baseSID/linked resolution (so it matches whatever spellID a Bar
-- Glow entry was saved against). Value is a plain number, a SECRET number,
-- or nil (no stack data). Consumed by Bar Glows' stack-threshold gate --
-- forwarded straight into a StatusBar:SetValue, never compared in Lua.
local _activeStacksCache = {}
mod._tickBlizzAuraStacks = _activeStacksCache

-------------------------------------------------------------------------------
--  IsFrameIncluded
--  Include if shown OR has cooldownInfo (catches transitional frames).
-------------------------------------------------------------------------------
local function IsFrameIncluded(widget)
    if not widget then
        return false
    end
    return widget:IsShown() or (widget.cooldownInfo ~= nil)
end

-------------------------------------------------------------------------------
--  HideBlizzardDecorations
--  Strip Blizzard visual chrome from a CDM frame (one-time per frame).
-------------------------------------------------------------------------------
local function HideBlizzardDecorations(widget)
    local fc = FC(widget)
    if fc.blizzHidden then
        return
    end
    fc.blizzHidden = true

    local function alphaZero(childFrame)
        if childFrame then
            childFrame:SetAlpha(0)
        end
    end
    alphaZero(widget.Border)
    if widget.SpellActivationAlert then
        widget.SpellActivationAlert:SetAlpha(0)
        widget.SpellActivationAlert:Hide()
    end
    alphaZero(widget.Shadow)
    alphaZero(widget.IconShadow)
    alphaZero(widget.DebuffBorder)
    alphaZero(widget.CooldownFlash)

    local iconWidget = widget.Icon
    local regions = { widget:GetRegions() }
    -- Blizzard Style keeps the viewer's rounded icon mask; only the ring
    -- overlay is replaced (ns.CdmApplyBlizzIconArt redraws it at the icon's
    -- live size, since the viewer's fixed inset only fits its stock sizes).
    -- Classic WoW UI icons are square, so they take the swap like the CUI look.
    local keepMask = mod.CdmIconStyle() == "blizzard"
    for ri = 1, #regions do
        local region = regions[ri]
        if not keepMask and region and region.IsObjectType and region:IsObjectType("MaskTexture") then
            pcall(function()
                region:SetTexture("Interface\\Buttons\\WHITE8X8")
            end)
        end
    end
    if widget.Cooldown and not keepMask then
        local cdRegions = { widget.Cooldown:GetRegions() }
        for ri = 1, #cdRegions do
            local region = cdRegions[ri]
            if region and region.IsObjectType and region:IsObjectType("MaskTexture") then
                pcall(function()
                    region:SetTexture("Interface\\Buttons\\WHITE8X8")
                end)
            end
        end
    end

    -- The ring overlay, matched by atlas or by its sheet file. The rounded
    -- MASK lives in the same sheet, so the file match must skip masks: a
    -- hidden mask masks nothing (Blizzard Style needs it; the CUI look has
    -- already squared it above).
    local OVERLAY_ATLAS = "UI-HUD-CoolDownManager-IconOverlay"
    local OVERLAY_FILE = 6707800
    for ri = 1, #regions do
        local region = regions[ri]
        if
            region
            and region ~= iconWidget
            and region.GetObjectType
            and region:GetObjectType() == "Texture"
        then
            local atlas = region.GetAtlas and region:GetAtlas()
            local texture = region.GetTexture and region:GetTexture()
            if atlas == OVERLAY_ATLAS or texture == OVERLAY_FILE then
                region:SetAlpha(0)
                region:Hide()
            end
        end
    end

    -- Do NOT call SetHideCountdownNumbers here; SetCountdownFont controls CD text.
end

-------------------------------------------------------------------------------
--  Stock style icon art (Global Settings > Style)
--  Blizzard Style: the viewer's look on every icon we lay out: rounded mask,
--  bevel ring and rounded swipe. Pooled viewer frames keep Blizzard's own mask
--  (HideBlizzardDecorations leaves it under this style); frames we create
--  (trinkets, placeholders, custom buffs, item presets) get an equivalent one.
--  Classic WoW UI: the vanilla action button ring round a square icon (no
--  mask, CUI's own square swipe).
--  The ring is our own texture on a child frame, so it survives pool reuse and
--  follows the icon's live size instead of the viewer's fixed stock inset.
--  Idempotent and cheap: structural work once per frame, then a size memo
--  gates the re-anchor. Never runs unless a stock style is on.
-------------------------------------------------------------------------------
function mod.CdmApplyBlizzIconArt(widget)
    if not widget then
        return
    end
    local fc = FC(widget)
    local classic = mod.CdmClassicIcons()
    local hostRegion = fc.blizzHost
    if not hostRegion then
        -- Pooled with an options preview slot (an options page pool host);
        -- the plain CreateFrame on a live icon.
        hostRegion = POOL.CreateFrame("Frame", nil, widget)
        hostRegion:SetAllPoints(widget)
        hostRegion:EnableMouse(false)
        fc.blizzHost = hostRegion
        local shade = hostRegion:CreateTexture(nil, "OVERLAY", nil, 5)
        if classic then
            shade:SetTexture(mod.CDM_CLASSIC_RING)
        else
            mod.CdmStockAtlas(shade, mod.CDM_BLIZZ_OVERLAY)
        end
        if shade.SetSnapToPixelGrid then
            shade:SetSnapToPixelGrid(false)
            shade:SetTexelSnappingBias(0)
        end
        fc.blizzOverlay = shade
        -- Own frames carry no viewer mask or swipe art: the rounded kit adds
        -- both (classic icons stay square on the default swipe).
        if not widget.viewerFrame and not classic then
            local fd = hookFrameData[widget]
            local texture = (fd and fd.tex) or widget._tex or widget.Icon
            if texture and texture.AddMaskTexture then
                local maskTex = widget:CreateMaskTexture()
                maskTex:SetAtlas(mod.CDM_BLIZZ_MASK)
                maskTex:SetAllPoints(widget)
                texture:AddMaskTexture(maskTex)
                fc.blizzMask = maskTex
            end
            local cd = (fd and fd.cooldown) or widget._cooldown or widget.Cooldown
            if cd and cd.SetSwipeTexture then
                pcall(cd.SetSwipeTexture, cd, mod.CDM_BLIZZ_SWIPE)
            end
        end
    end
    -- Viewer frames: the viewer's own rounded mask, re-asserted once (shown,
    -- on the atlas) so no earlier pass can have left it hidden or squared.
    -- Classic keeps the square mask HideBlizzardDecorations gave it.
    if widget.viewerFrame and not classic and not fc.blizzMaskOK then
        fc.blizzMaskOK = true
        local fd = hookFrameData[widget]
        local texture = (fd and fd.tex) or widget.Icon
        local num = texture and texture.GetNumMaskTextures and texture:GetNumMaskTextures() or 0
        for idx = 1, num do
            local m = texture:GetMaskTexture(idx)
            if m then
                pcall(m.SetAtlas, m, mod.CDM_BLIZZ_MASK)
                pcall(m.SetAlpha, m, 1)
                pcall(m.Show, m)
            end
        end
    end
    -- Ring above the art and swipe (+14), below glows (+16) and text (+23).
    local lvl = widget:GetFrameLevel() + 15
    if hostRegion:GetFrameLevel() ~= lvl then
        hostRegion:SetFrameLevel(lvl)
    end
    local wid, hgt = widget:GetSize()
    if fc.blizzArtW ~= wid or fc.blizzArtH ~= hgt then
        fc.blizzArtW, fc.blizzArtH = wid, hgt
        local shade = fc.blizzOverlay
        if classic then
            mod.CdmPlaceClassicRing(shade, hostRegion, wid, hgt)
        else
            shade:ClearAllPoints()
            shade:SetPoint(
                "TOPLEFT",
                hostRegion,
                "TOPLEFT",
                -wid * mod.CDM_BLIZZ_RING_X,
                hgt * mod.CDM_BLIZZ_RING_Y
            )
            shade:SetPoint(
                "BOTTOMRIGHT",
                hostRegion,
                "BOTTOMRIGHT",
                wid * mod.CDM_BLIZZ_RING_X,
                -hgt * mod.CDM_BLIZZ_RING_Y
            )
        end
    end
end
-- The rounded mask an icon's art carries under Blizzard Style (the viewer's
-- own on pooled frames, ours on own frames), for overlays that copy the art
-- (fake-active, press flash) so they round off with it. Nil under Classic
-- WoW UI, whose icons are square.
function mod.CdmBlizzIconMask(widget)
    if mod.CdmClassicIcons() then
        return nil
    end
    local fc = widget and _ecmeFC[widget]
    if fc and fc.blizzMask then
        return fc.blizzMask
    end
    local fd = widget and hookFrameData[widget]
    local texture = (fd and fd.tex) or (widget and (widget.Icon or widget._tex))
    if texture and texture.GetNumMaskTextures and texture:GetNumMaskTextures() > 0 then
        return texture:GetMaskTexture(1)
    end
    return nil
end

-------------------------------------------------------------------------------
--  Charge cooldown style
--  BASELINE: every charge spell draws the cooldown edge (spark) like the action
--  bars -- follows the icon shape's square/circular path at the shape's scale,
--  masked by the CDM shape system. Always on for charge spells, no setting.
--  PER-SPELL: "Hide Swipe (Charges)" also hides the radial swipe (edge only),
--  resolved only when in use (ns._cdmAnyChargeStyle) so others pay ~0.
-------------------------------------------------------------------------------
-- Game-indexed on purpose: the 12.1 edge channel renders game-indexed files
-- ONLY -- loose addon art (png/tga/blp) draws nothing, silently, with clean
-- state readbacks.
local CDM_EDGE_TEXTURE = "Interface\\Cooldown\\UI-HUD-ActionBar-SecondaryCooldown"

-- NOTE (probed 2026-08-12): the Cooldown widget clips ALL edge drawing at
-- the frame's own rect -- scales past flush render identically, so the edge
-- can never reach a square's corners without enlarging the cooldown frame
-- itself. Do not re-attempt corner coverage via SetEdgeScale.

-- Thin wrapper: frame spell/bar identity -> ResolveSpellSettings, the same
-- Hero-talent-aware resolver the SetSwipeColor / cdState / desat hooks use, so
-- the charge "Hide Swipe" path resolves override spells identically.
function mod._ResolveCdmSS(widget)
    local fc2 = _ecmeFC[widget]
    local sid2 = fc2 and fc2.spellID
    local bk2 = fc2 and fc2.barKey
    if not sid2 or not bk2 then
        return nil
    end
    return ResolveSpellSettings(widget, sid2, false)
end

-- Draw the styled cooldown edge -- one texture for every edge lane: the
-- always-on charge recharge edge and the bar-wide Always Show Cooldown Edge
-- re-assert both land here. The shape system owns the mask + circular-edge
-- flag; this applies texture, color, scale and draw flag.
local function ApplyCdmEdge(cd, bk2)
    if not cd then
        return
    end
    local edge = barDataByKey and barDataByKey[bk2]
    local shape = (edge and edge.iconShape) or "none"
    -- SetEdgeScale is frame-relative so the edge tracks icon size: plain icons
    -- use the action bars' baseline size, custom shapes the per-shape scale.
    local scale
    if shape == "none" or shape == "cropped" then
        scale = 1.8
    else
        scale = (mod.CDM_SHAPE_EDGE_SCALES and mod.CDM_SHAPE_EDGE_SCALES[shape]) or 0.75
    end
    -- Color rides SetEdgeTexture: the documented signature is
    -- (texture, r, g, b, a) with the color args required.
    if cd.SetEdgeTexture then
        cd:SetEdgeTexture(CDM_EDGE_TEXTURE, 1, 1, 1, 1)
    end
    if cd.SetEdgeScale then
        cd:SetEdgeScale(scale)
    end
    if cd.SetDrawEdge then
        cd:SetDrawEdge(true)
    end
end

-- Live active-state read from Blizzard's swipe color (fd._wasActive is stale on
-- falloffs). Secret-safe: a secret red channel reads as not active. Lets charge
-- "Hide Swipe" keep the active-state colored swipe visible.
local function CdmFrameIsActive(widget)
    local swipeColor = widget and widget.cooldownSwipeColor
    if swipeColor and type(swipeColor) ~= "number" and swipeColor.GetRGBA then
        local r = swipeColor:GetRGBA()
        if r and type(r) == "number" and not issecretvalue(r) then
            return r ~= 0
        end
    end
    return false
end

-- Blizzard resolves a cooldown item's spell through GetSpellID(), whose
-- precedence is aura > linkedSpellID > overrideTooltip > override > base
-- (CooldownViewerItemData.lua). When an aura ends without the item receiving the
-- UNIT_AURA removal, cooldownInfo.linkedSpellID keeps pointing at the aura, so
-- CheckCacheCooldownValuesFromSpellCooldown reads the cooldown from a spell that
-- HAS none: start/dur come back 0, IsExpired() answers true, and
-- RefreshSpellCooldownInfo takes its CooldownFrame_Clear branch on every refresh
-- -- no swipe, no countdown text -- while RefreshIconDesaturation leaves the icon
-- saturated. The ability is still on cooldown, so the icon reads as "never
-- pressed" until a target switch (OnNewTarget clears the link), a re-cast of the
-- base spell, or a cooldownID re-set. Blizzard's own repair for this,
-- RefreshLinkedSpell, is only called from OnCooldownIDSet, never from RefreshData.
--
-- How the link outlives the aura: ClearAuraInstanceInfo() drops the instance but
-- NOT the link, and the only path that drops both is OnUnitAuraRemovedEvent,
-- which is dispatched through auraInstanceIDToItemFramesMap and is therefore
-- missable. Any later RefreshData then clears the instance via RefreshAuraInstance
-- and leaves the link standing.
--
-- Detected with nil-compares and never-secret bools ONLY. In instanced combat
-- Cooldown:GetCooldownDuration answers a SECRET value, which is exactly why
-- ReAssertRealCooldown's "widget reads ~0" proof fails closed there -- i.e. in
-- the content where this is reported.
--
-- We repair OUR rendering only; Blizzard's item stays wrong, so its own alerts
-- and isOnActualCooldown keep answering against the linked spell.
--
-- Ordered cheapest-first: linkedSpellID is nil for nearly every icon, so the
-- common case costs two table lookups and no API call. Returns the STRUCTURAL
-- verdict only; callers add their own "is on a real cooldown" test.
local function CdmStaleLinkedSpell(widget)
    local details = widget and widget.cooldownInfo
    if details == nil or details.linkedSpellID == nil then
        return false
    end
    -- An aura that is actually being displayed owns the widget; never fight it.
    -- Covers the transient where UpdateLinkedSpell has set the link a moment
    -- before RefreshAuraInstance attaches the matching instance.
    if widget.auraInstanceID ~= nil or widget.wasSetFromAura then
        return false
    end
    return true
end

-- Charge info for a CDM frame, resolved the way BLIZZARD resolves it.
--
-- We were resolving the charge spell with C_SpellBook.FindSpellOverrideByID and
-- Blizzard resolves it from the CooldownViewer's OWN override record --
-- CooldownViewerItemDataMixin:GetSpellChargeInfo reads
-- `info.overrideSpellID or info.spellID`, deliberately, "to ensure that charges
-- work correctly for cooldown items that are actively cast, apply auras, and
-- have charges". Those are two different sources and they disagree in the field:
-- captured on a Mage, base Blink 1953 with FindSpellOverrideByID resolving to
-- Shimmer 212653, our read returned isActive=false (no recharge) while Blizzard's
-- own HasVisualDataSource_Charges was true (a recharge running with charges in
-- hand) on the very same frame in the very same call.
--
-- That disagreement is not cosmetic: chargeRecharging false is what lets the
-- Suppress GCD block alpha-0 a swipe, so with Suppress GCD on, an override
-- spell's recharge swipe gets blanked for the whole GCD every time another
-- ability is pressed -- the exact failure the charge carve-out exists to
-- prevent. Asking Blizzard removes the whole class rather than special-casing
-- Shimmer.
--
-- Falls back to the old resolution for frames without the accessor (preset,
-- custom-spell and item frames are ours, not CooldownViewer items), so those
-- keep exactly today's behaviour.
local function CdmChargeInfoFor(widget, spellRef)
    if widget and type(widget.GetSpellChargeInfo) == "function" then
        local ci = widget:GetSpellChargeInfo()
        if ci then
            return ci
        end
    end
    if not (spellRef and C_Spell and C_Spell.GetSpellCharges) then
        return nil
    end
    local effID = spellRef
    if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
        local ovr = C_SpellBook.FindSpellOverrideByID(spellRef)
        if ovr and ovr > 0 and ovr ~= spellRef then
            effID = ovr
        end
    end
    return C_Spell.GetSpellCharges(effID) or C_Spell.GetSpellCharges(spellRef)
end
mod.CdmChargeInfoFor = CdmChargeInfoFor

-- Apply charge cooldown style. Returns true for charge spells (caller skips its
-- own swipe forcing). Edge always drawn; the swipe hides only with per-spell
-- Hide Swipe (resolved only while ns._cdmAnyChargeStyle). Caller MUST guard with
-- fd._isProcessingOverride so the SetDrawSwipe sibling hook cannot recurse.
-- Secret-safe: HasVisualDataSource_Charges is a clean bool, the ss flag is ours.
local function ApplyCdmChargeStyle(widget, cd)
    -- Icon art suppressed (Only Show Numbers / Charges/Stacks Only): nothing for
    -- a swipe/edge to decorate. Report "handled" so callers skip their own
    -- swipe/edge defaults. The reentry guard is SAVED and restored, never forced
    -- false: ReapplyChargeStyle
    -- sets it before calling us and clearing it would drop its guard.
    local fdOsn = hookFrameData[widget]
    if fdOsn and fdOsn._osnOn then
        local prevGuard = fdOsn._isProcessingOverride
        fdOsn._isProcessingOverride = true
        if cd.SetDrawSwipe then
            cd:SetDrawSwipe(false)
        end
        if cd.SetDrawEdge then
            cd:SetDrawEdge(false)
        end
        fdOsn._isProcessingOverride = prevGuard
        return true
    end
    if type(widget.HasVisualDataSource_Charges) ~= "function" or not widget:HasVisualDataSource_Charges() then
        return false
    end
    local fc2 = _ecmeFC[widget]
    ApplyCdmEdge(cd, fc2 and fc2.barKey)
    local hide = false
    if mod._cdmAnyChargeStyle then
        local ss2 = mod._ResolveCdmSS(widget)
        if ss2 then
            -- Hide Recharge Edge (per-spell): drop the edge ApplyCdmEdge just
            -- drew. Secret-safe: ss flag is ours, SetDrawEdge takes no secret.
            if ss2.hideRechargeEdge and cd.SetDrawEdge then
                cd:SetDrawEdge(false)
            end
            if ss2.chargeHideSwipe then
                -- Hide only the recharge swipe: the active-state overlay IS the
                -- colored swipe, so keep it while active.
                local showActive = ss2.activeSwipeMode ~= "none" and CdmFrameIsActive(widget)
                hide = not showActive
            end
        end
    end
    if cd.SetDrawSwipe then
        cd:SetDrawSwipe(not hide)
    end
    return true
end

-- Immediately re-assert the charge style (Hide Recharge Edge + Hide Swipe) on one
-- icon instead of waiting for Blizzard's next cooldown re-push. Called from
-- RefreshCDMIconAppearance so toggling either setting (per-icon OR Apply to Bar)
-- updates a CURRENTLY recharging spell now. No-op on non-charge frames
-- (ApplyCdmChargeStyle self-skips); reentry-guarded so siblings cannot recurse.
function mod.ReapplyChargeStyle(widget)
    local fd = widget and hookFrameData[widget]
    local cd = fd and fd.cooldown
    if not cd or fd._isProcessingOverride then
        return
    end
    fd._isProcessingOverride = true
    ApplyCdmChargeStyle(widget, cd)
    fd._isProcessingOverride = false
end

-- Max Stacks Glow (per-spell): glow a charge spell at max charges. 1:1 with
-- Active State Glow but on its own overlay (the two never fight), driven by
-- charge state. ss2.maxStacksGlow is the STYLE, color is unified ss.glowColor.
-- atMax is a CLEAN bool from GetSpellCharges().isActive (recharge-active flag,
-- false only at max) -- never the secret currentCharges.
local function ApplyMaxStacksGlow(widget, fd, ss2, atMax)
    if not fd then
        return
    end
    local has = ss2 and ss2.maxStacksGlow and ss2.maxStacksGlow > 0
    if has and atMax then
        if not fd._maxStacksGlowOn then
            -- Lazy-create (unused feature adds no frame). Own overlay never
            -- fights the active glow (StartNativeGlow is per-overlay).
            local mo = fd.maxStacksGlowOverlay
            if not mo and widget then
                mo = CreateFrame("Frame", nil, widget)
                mo:SetAllPoints(widget)
                mo:SetAlpha(0)
                mo:EnableMouse(false)
                fd.maxStacksGlowOverlay = mo
            end
            if mo then
                if widget then
                    mo:SetFrameLevel(widget:GetFrameLevel() + 16)
                end
                local gr, gg, gb = mod.ResolveGlowColor(ss2)
                mod.StartNativeGlow(mo, ss2.maxStacksGlow, gr, gg, gb)
                fd._maxStacksGlowOn = true
            end
        end
    elseif fd._maxStacksGlowOn then
        if fd.maxStacksGlowOverlay then
            mod.StopNativeGlow(fd.maxStacksGlowOverlay)
        end
        fd._maxStacksGlowOn = false
    end
end

-- Driven by SPELL_UPDATE_CHARGES, NOT the cooldown-widget hooks: those fire when
-- a charge is SPENT but not when the last charge REFILLS to max. That event
-- fires on BOTH charge transitions and nothing else (far cheaper than
-- SPELL_UPDATE_COOLDOWN, every GCD) and isActive only flips with a charge-count
-- change, so one event catches both edges. The watch set holds only glow-enabled
-- icons; the event frame is created only once the feature is on (0 cost).
mod._maxStacksWatch = mod._maxStacksWatch or setmetatable({}, { __mode = "k" })

-- Re-derive at-max from CLEAN charge state and (un)glow. Self-unwatches when the
-- per-icon setting is off or the frame lost its spell, so the set drains itself.
local function EvalMaxStacksFrame(widget, fd)
    if not fd then
        return
    end
    local fcw = _ecmeFC[widget]
    local sidw = fcw and fcw.spellID
    local bkw = fcw and fcw.barKey
    if not sidw or not bkw then
        ApplyMaxStacksGlow(widget, fd, nil, false)
        mod._maxStacksWatch[widget] = nil
        return
    end
    local ssw = ResolveSpellSettings(widget, sidw, mod.GetBarSpellData(bkw))
    if not (ssw and ssw.maxStacksGlow and ssw.maxStacksGlow > 0) then
        ApplyMaxStacksGlow(widget, fd, ssw, false)
        mod._maxStacksWatch[widget] = nil
        return
    end
    local liveSid = sidw
    if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
        liveSid = C_SpellBook.FindSpellOverrideByID(sidw) or sidw
    end
    -- atMax derives PURELY from charge data (maxCharges + recharge isActive),
    -- NEVER HasVisualDataSource_Charges: that is false while the icon draws a GCD
    -- swipe, dropping the glow whenever a charge tops off mid-GCD. maxCharges>1
    -- is itself the charge-spell test (nil/1 for non-charge -> atMax false).
    local ci = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(liveSid)
    local atMax = ci ~= nil and (ci.maxCharges or 0) > 1 and not ci.isActive
    ApplyMaxStacksGlow(widget, fd, ssw, atMax)
end

local function WatchMaxStacksFrame(widget, fd)
    mod._maxStacksWatch[widget] = fd
    if not mod._maxStacksEventFrame then
        local ef = mod.TakeShell()
        ef:RegisterEvent("SPELL_UPDATE_CHARGES")
        ef:SetScript("OnEvent", function()
            for f, d in pairs(mod._maxStacksWatch) do
                EvalMaxStacksFrame(f, d)
            end
        end)
        mod._maxStacksEventFrame = ef
    end
end

-- Called from RefreshCDMIconAppearance (login + settings changes) so an at-max
-- charge spell (no swipe, so it never fires the swipe hook) still gets watched.
-- Early-outs on non-charge icons (cheap capability check, no settings lookup);
-- once watched SPELL_UPDATE_CHARGES keeps it current. Self-cleans when disabled.
function mod.WatchMaxStacksIfEnabled(widget)
    if not widget then
        return
    end
    local fd = hookFrameData[widget]
    if not fd then
        return
    end
    local fcw = _ecmeFC[widget]
    local sidw = fcw and fcw.spellID
    local bkw = fcw and fcw.barKey
    if not (sidw and bkw) then
        return
    end
    -- Charge-spell test via static charge data (stable). HasVisualDataSource_Charges
    -- flips false during a GCD swipe and would wrongly skip the spell here too.
    local liveSid = sidw
    if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
        liveSid = C_SpellBook.FindSpellOverrideByID(sidw) or sidw
    end
    local ci = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(liveSid)
    local isCharge = ci ~= nil and (ci.maxCharges or 0) > 1
    local ssw = isCharge and ResolveSpellSettings(widget, sidw, mod.GetBarSpellData(bkw)) or nil
    if ssw and ssw.maxStacksGlow and ssw.maxStacksGlow > 0 then
        mod._cdmAnyMaxStacksGlow = true
        WatchMaxStacksFrame(widget, fd)
        EvalMaxStacksFrame(widget, fd)
    elseif mod._maxStacksWatch[widget] then
        mod._maxStacksWatch[widget] = nil
        ApplyMaxStacksGlow(widget, fd, nil, false)
    end
end

Inner._activeCache, Inner._activeStacksCache = _activeCache, _activeStacksCache
Inner.ApplyCdmChargeStyle, Inner.ApplyCdmEdge = ApplyCdmChargeStyle, ApplyCdmEdge
Inner.ApplyMaxStacksGlow, Inner.CdmChargeInfoFor = ApplyMaxStacksGlow, CdmChargeInfoFor
Inner.CdmFrameIsActive, Inner.CdmStaleLinkedSpell = CdmFrameIsActive, CdmStaleLinkedSpell
Inner.EvalMaxStacksFrame, Inner.HideBlizzardDecorations = EvalMaxStacksFrame, HideBlizzardDecorations
Inner.IsFrameIncluded, Inner.WatchMaxStacksFrame = IsFrameIncluded, WatchMaxStacksFrame
Inner.broken = false
