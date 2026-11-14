if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_Nameplates_PlatePool.lua
--
--  The frame pool and plate construction, the pool prewarm, RefreshBorder, the
--  hitbox overlay and ns.RefreshAllSettings.
--  Reads the earlier nameplate files through ns and ns._npInternals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._npInternals
-- CludesUINameplates.lua or an earlier nameplate file failed to load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local pairs, ipairs = pairs, ipairs
local UnitIsUnit = UnitIsUnit
local C_NamePlate = C_NamePlate
local Enum = Enum

local CAST_H, defaultSet, ENP, GetNPOutline = Inner.CAST_H, Inner.defaults, Inner.ENP, Inner.GetNPOutline
local SetFSFont, GetBorderColor = Inner.SetFSFont, Inner.GetBorderColor
local GetCastBarHeight = Inner.GetCastBarHeight
local GetEnemyNameTextSize, GetHealthBarHeight = Inner.GetEnemyNameTextSize, Inner.GetHealthBarHeight
local GetHealthBarWidth, GetHitboxYShift = Inner.GetHealthBarWidth, Inner.GetHitboxYShift
local GetNameplateYOffset, GetRaidMarkerSize = Inner.GetNameplateYOffset, Inner.GetRaidMarkerSize
local GetRareEliteIconSize, GetShowCastIcon = Inner.GetRareEliteIconSize, Inner.GetShowCastIcon
local GetStackSpacingScale, IsBorderEnabled = Inner.GetStackSpacingScale, Inner.IsBorderEnabled
local SetProfile = Inner.SetProfile

local p
Inner.profileSetters[#Inner.profileSetters + 1] = function(v)
    p = v
end

local frameCache = CreateFramePool("Frame", UIParent, nil, nil, false, function(backing)
    backing:SetFlattensRenderLayers(true)
    backing.health = CreateFrame("StatusBar", nil, backing)
    backing.health:SetFrameLevel(10)
    backing.health:SetPoint("CENTER", backing, "CENTER", 0, GetNameplateYOffset())
    backing.health:SetSize(GetHealthBarWidth(), GetHealthBarHeight())
    backing.health:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    backing.health:SetClipsChildren(false)
    backing.healthBG = backing.health:CreateTexture(nil, "BACKGROUND")
    backing.healthBG:SetAllPoints()
    local _bg = (p and p.bgColor) or defaultSet.bgColor
    local _bga = (p and p.bgAlpha) or defaultSet.bgAlpha
    backing.healthBG:SetColorTexture(_bg.r, _bg.g, _bg.b, _bga)
    -- Hash line: thin vertical marker at a configurable health percentage
    backing.hashLine = backing.health:CreateTexture(nil, "OVERLAY", nil, 3)
    backing.hashLine:SetColorTexture(1, 1, 1, 0.8)
    backing.hashLine:SetWidth(2)
    backing.hashLine:SetPoint("TOP", backing.health, "TOP", 0, 0)
    backing.hashLine:SetPoint("BOTTOM", backing.health, "BOTTOM", 0, 0)
    backing.hashLine:Hide()
    -- Mask texture: constrains absorb rendering to exact health bar bounds at the GPU level,
    -- preventing the 1px subpixel bleed absorb textures show at certain nameplate positions.
    local absorbMask = backing.health:CreateMaskTexture()
    absorbMask:SetAllPoints(backing.health)
    absorbMask:SetTexture("Interface\\Buttons\\WHITE8X8")
    backing._absorbMask = absorbMask

    mod.NP_BuildAbsorbBars(backing, backing.health, absorbMask)
    mod.NP_SizeAbsorbBars(backing, GetHealthBarWidth(), GetHealthBarHeight())
    mod.NP_LayoutAbsorbBars(backing, backing.health, (p and p.absorbEdgeMode) or defaultSet.absorbEdgeMode)
    if CreateUnitHealPredictionCalculator then
        backing.hpCalculator = CreateUnitHealPredictionCalculator()
        -- Configured once: plain max health (the shield never widens the
        -- bar's range) and absorbs clamped to it (a shield fills at most the bar).
        if backing.hpCalculator.SetMaximumHealthMode then
            backing.hpCalculator:SetMaximumHealthMode(Enum.UnitMaximumHealthMode.Default)
            backing.hpCalculator:SetDamageAbsorbClampMode(Enum.UnitDamageAbsorbClampMode.MaximumHealth)
        end
    end
    local function AddBorder(hostFrame)
        local Pix = CludesUI and CludesUI.PP
        if Pix then
            Pix.CreateBorder(hostFrame, 0, 0, 0, 1, 1, "OVERLAY", 5, true) -- scaleGuard: NP frame
        end
    end
    -- Border: single pixel-perfect PP.CreateBorder (BackdropTemplate).
    -- Two settings: showBorder (bool) and borderSize (physical pixels).
    local Pix = CludesUI and CludesUI.PP
    local bc = { r = 0, g = 0, b = 0 }
    bc.r, bc.g, bc.b = GetBorderColor()
    if Pix and Pix.CreateBorder then
        local sz = mod.NP_BorderSize()
        Pix.CreateBorder(backing.health, bc.r, bc.g, bc.b, 1, sz, "OVERLAY", 7, true) -- scaleGuard: NP frame
        if not IsBorderEnabled() or mod.NP_Classic() then
            Pix.HideBorder(backing.health)
        end
    end

    function backing:ApplyBorder()
        if not Pix then
            return
        end
        if mod.NP_Classic() then
            -- Classic WoW UI: the vanilla border art replaces every CUI border.
            Pix.HideBorder(backing.health)
            mod.HideCustomBorder(backing)
            mod.NP_ApplyClassicHealthArt(backing)
            mod.NP_ApplyRounding(backing)
            return
        end
        if mod.IsCustomBorderEnabled() then
            -- Custom border replaces the simple one: hide the PP strips on the
            -- health bar and render the custom border on its own child frame.
            Pix.HideBorder(backing.health)
            mod.ApplyCustomBorderStyle(backing)
        else
            mod.HideCustomBorder(backing)
            if IsBorderEnabled() then
                Pix.SetBorderSize(backing.health, mod.NP_BorderSize())
                Pix.ShowBorder(backing.health)
            else
                Pix.HideBorder(backing.health)
            end
        end
        -- WoW Forever: the level box right of the bar, sized to it (the
        -- style latched at enable, before any plate).
        if mod._npForever then
            mod.NP_ApplyForeverLevelBox(backing)
        end
        -- The spell icon border and divider follow border style edits.
        if
            (p and (p.castIconCustomBorder or p.castIconSeparator))
            or (backing.cast and backing.cast._iconSeam)
        then
            mod.ApplyCastIconBorder(backing)
        end
        mod.NP_ApplyRounding(backing)
    end
    function backing:ApplyBorderColor()
        if not Pix then
            return
        end
        -- Threat Colors "Border" channel: UpdateHealthColor parks the resolved threat color
        -- on the plate and this stays the single funnel that paints the BASE border, so
        -- every caller that restores it -- RefreshBorderColor, ApplyTarget's else-branch,
        -- ClearHoverExtras -- picks the threat tint up for free. The target and hover border
        -- colors are applied AFTER this and still win: those are explicit selection states
        -- the user asked for. _threatBdOn is the plain gate; the components themselves can
        -- be SECRET (off-tank C-fold), so they are never tested for truth, only handed to
        -- the setter.
        if backing._threatBdOn then
            if mod.IsCustomBorderEnabled() then
                -- Same lazy build ApplyTarget does: a plate can take the threat tint before
                -- its first ApplyBorder ever ran.
                if not backing._customBorder then
                    mod.ApplyCustomBorderStyle(backing)
                end
                if backing._customBorder then
                    local a = (p and p.customBorderAlpha) or defaultSet.customBorderAlpha or 1
                    CludesUI.SetBorderStyleColor(
                        backing._customBorder,
                        backing._threatBdR,
                        backing._threatBdG,
                        backing._threatBdB,
                        a
                    )
                end
                backing._hbThreatTint = nil
            else
                mod.NP_BasicBorderColor(
                    backing,
                    backing._threatBdR,
                    backing._threatBdG,
                    backing._threatBdB,
                    1
                )
                -- The health border wears the parked tint now: UpdateBorderWrap reads this,
                -- and every other border colour paint (base, target, hover) clears it.
                backing._hbThreatTint = true
            end
        else
            backing._hbThreatTint = nil
            if mod.IsCustomBorderEnabled() then
                mod.ApplyCustomBorderColor(backing)
            else
                local cr, cg, cb = GetBorderColor()
                mod.NP_BasicBorderColor(backing, cr, cg, cb, 1)
            end
        end
        -- ...and border colour edits and the target tint's restore (a tint only), on the
        -- threat path too: untargeting a threat-tinted plate drops the target colour here.
        if
            (p and (p.castIconCustomBorder or p.castIconSeparator))
            or (backing.cast and backing.cast._iconSeam)
        then
            mod.ApplyCastIconBorder(backing)
        end
    end
    -- Target glow, arrows and focus overlay are lazy (EnsureGlow / EnsureArrows /
    -- EnsureFocusOverlay): only 1 plate shows them, saving ~14 objects per plate.
    backing.healthTextFrame = CreateFrame("Frame", nil, backing)
    backing.healthTextFrame:SetAllPoints(backing.health)
    -- TEXT TIER (top). All three layered groups -- text (900), aura icons (800), indicators
    -- (raid marker/classification, ~13-18) -- use explicit MEDIUM strata so they are pulled out
    -- of the plate's flattened render layer together, ordered purely by frame level. Without
    -- it this frame stays flattened and renders BELOW the aura icons. Text > Auras > Ind.
    backing.healthTextFrame:SetFrameStrata("MEDIUM")
    backing.healthTextFrame:SetFrameLevel(900)
    backing.hpText = backing.healthTextFrame:CreateFontString(nil, "OVERLAY")
    SetFSFont(backing.hpText, 10, GetNPOutline())
    Pix.Point(backing.hpText, "RIGHT", backing.health, "RIGHT", -2, 0)
    backing.hpNumber = backing.healthTextFrame:CreateFontString(nil, "OVERLAY")
    SetFSFont(backing.hpNumber, 10, GetNPOutline())
    backing.hpNumber:SetPoint("CENTER", backing.health, "CENTER", 0, 0)
    backing.hpNumber:Hide()
    -- Standalone level text: its own FontString so it can share the plate
    -- with the name (see the NAME_FAMILY note). Content is static per unit.
    backing.levelText = backing.healthTextFrame:CreateFontString(nil, "OVERLAY")
    SetFSFont(backing.levelText, 10, GetNPOutline())
    backing.levelText:SetPoint("CENTER", backing.health, "CENTER", 0, 0)
    backing.levelText:Hide()
    -- Mouseover highlight: parented to the health bar (not the higher-level text
    -- frame) so it renders BEHIND the border (a child at health level + 1).
    -- Blizzard Style: under the stock ring / deselected overlay (OVERLAY 4/5),
    -- above the target wash (0). The CUI and classic looks keep it at 6.
    backing.highlight =
        backing.health:CreateTexture(nil, "OVERLAY", nil, mod.NP_Style() == "blizzard" and 1 or 6)
    backing.highlight:SetAllPoints(backing.health)
    local _hc = (p and p.hoverColor) or defaultSet.hoverColor
    local _ha = (p and p.hoverAlpha) or defaultSet.hoverAlpha
    backing.highlight:SetColorTexture(_hc.r, _hc.g, _hc.b, _ha)
    backing.highlight:Hide()
    -- Top text overlay: renders above health bar + borders so top-slot text is never hidden
    backing.topTextFrame = CreateFrame("Frame", nil, backing)
    backing.topTextFrame:SetAllPoints(backing.health)
    -- TEXT TIER (see healthTextFrame). MEDIUM + level 900 so name text renders
    -- above the aura icons (the name/health fontstrings are reparented between
    -- this frame and healthTextFrame depending on the chosen text slot).
    backing.topTextFrame:SetFrameStrata("MEDIUM")
    backing.topTextFrame:SetFrameLevel(900)
    backing.name = backing:CreateFontString(nil, "OVERLAY")
    SetFSFont(backing.name, GetEnemyNameTextSize(), GetNPOutline())
    Pix.Point(backing.name, "BOTTOM", backing.health, "TOP", 0, 4)
    Pix.Width(backing.name, math.max(GetHealthBarWidth(), 20))
    backing.name:SetWordWrap(false)
    backing.name:SetMaxLines(1)
    backing.nameRaidFrame = CreateFrame("Frame", nil, backing)
    local nameRmSize = (p and p.nameRaidMarkerSize) or defaultSet.nameRaidMarkerSize or 14
    Pix.Size(backing.nameRaidFrame, nameRmSize, nameRmSize)
    backing.nameRaidFrame:SetFrameStrata("MEDIUM")
    backing.nameRaidFrame:SetFrameLevel(901)
    backing.nameRaidFrame:Hide()
    backing.nameRaid = backing.nameRaidFrame:CreateTexture(nil, "ARTWORK")
    backing.nameRaid:SetAllPoints()
    backing.nameRaid:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    -- Core Positions chains (ns.NP_CoreChain) anchor the raid marker, the Rare/Quest
    -- indicator, the faction badge and the cast-lockout icon to aura containers, which only
    -- aspect-bearing objects may anchor to (EnsureArrows), and the aspect is inherited at
    -- creation alone: the four are born inside one template holder per plate, a child of the
    -- plate so they show, fade and scale as before. Without the template they stay plain
    -- children, and a chain leaves an icon that would follow a row at its own spot.
    local coreHost = backing
    do
        local success, holderFrame =
            pcall(CreateFrame, "Frame", nil, backing, "DisableUntrustedLayoutScriptsTemplate")
        if success and holderFrame then
            holderFrame:SetAllPoints(backing.health)
            backing.coreHost = holderFrame
            coreHost = holderFrame
        end
    end
    backing.raidFrame = CreateFrame("Frame", nil, coreHost)
    local rmSize = GetRaidMarkerSize()
    Pix.Size(backing.raidFrame, rmSize, rmSize)
    -- INDICATOR TIER (bottom of the three groups). Explicit MEDIUM strata like the aura icons
    -- and text, so frame level alone orders the pulled-out group: the marker (health+8=18)
    -- sits BELOW auras (800) and text (900) but above the flattened health bar. Sharing MEDIUM
    -- across all three tiers keeps order predictable -- a no-strata frame drops into flattening.
    backing.raidFrame:SetFrameStrata("MEDIUM")
    backing.raidFrame:SetFrameLevel(backing.health:GetFrameLevel() + 8)
    backing.raidFrame:Hide()
    backing.raid = backing.raidFrame:CreateTexture(nil, "ARTWORK")
    backing.raid:SetAllPoints()
    backing.raid:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    backing.classFrame = CreateFrame("Frame", nil, coreHost)
    local _reIconSz = GetRareEliteIconSize()
    Pix.Size(backing.classFrame, _reIconSz, _reIconSz)
    Pix.Point(backing.classFrame, "LEFT", backing.health, "LEFT", 2, 0)
    -- INDICATOR TIER (see raidFrame). MEDIUM strata + low level (health+3=13) so the
    -- classification/elite/rare/quest indicator sits below auras/text but above the flattened bar.
    backing.classFrame:SetFrameStrata("MEDIUM")
    backing.classFrame:SetFrameLevel(backing.health:GetFrameLevel() + 3)
    backing.classFrame:Hide()
    backing.class = backing.classFrame:CreateTexture(nil, "ARTWORK")
    backing.class:SetAllPoints()
    -- The faction badge (plate.factionFrame) is built on first use by UpdateFaction.
    backing.cast = CreateFrame("StatusBar", nil, backing)
    -- Cast bar spans the health bar width; by default the icon hangs outside left, and with
    -- "Make Icon Part of the Bar" the bar shrinks to fit it. Must run after plate.health exists.
    mod.LayoutCastBar(backing, mod.GetHealthBarWidth(), CAST_H)
    backing.cast:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    backing.cast:SetMinMaxValues(0, 1)
    backing.cast:Hide()
    backing.castBG = backing.cast:CreateTexture(nil, "BACKGROUND")
    backing.castBG:SetAllPoints()
    local _cbg = (p and p.castBgColor) or defaultSet.castBgColor
    local _cba = (p and p.castBgAlpha) or defaultSet.castBgAlpha
    backing.castBG:SetColorTexture(_cbg.r, _cbg.g, _cbg.b, _cba)
    -- Cast bar border: pixel-perfect PP.CreateBorder, lazy-created (size 0 default, costs
    -- nothing unless enabled). Mirrors the health border; a child of plate.cast.
    function backing:ApplyCastBorder()
        if not Pix or not Pix.CreateBorder then
            return
        end
        local sz = (p and p.castBorderSize) or defaultSet.castBorderSize or 0
        -- The stock styles carry their own cast bar art (the stock art, the
        -- vanilla cast border): no CUI border.
        if mod.NP_Blizz() then
            sz = 0
        end
        if sz and sz > 0 then
            if Pix.GetBorders(backing.cast) then
                Pix.SetBorderSize(backing.cast, sz)
                Pix.ShowBorder(backing.cast)
            else
                local cr, cg, cb = mod.NP_CastBorderColor()
                Pix.CreateBorder(backing.cast, cr, cg, cb, 1, sz, "OVERLAY", 7, true) -- scaleGuard: NP frame
            end
        elseif Pix.GetBorders(backing.cast) then
            Pix.HideBorder(backing.cast)
        end
        mod.NP_ApplyRounding(backing, "cast")
    end
    function backing:ApplyCastBorderColor()
        if not Pix or not Pix.GetBorders or not Pix.GetBorders(backing.cast) then
            return
        end
        local cr, cg, cb = mod.NP_CastBorderColor()
        Pix.SetBorderColor(backing.cast, cr, cg, cb, 1)
    end
    -- "Wrap Border Around Castbar" (opt-in). While cast bar shown + feature on, health + cast
    -- get ONE continuous border from two pieces: the REAL health border (top+sides, untouched
    -- colour) and a region frame for the lower half (sides+bottom, full footprint width, health
    -- bottom -> cast bottom). Touching edges hidden so they read as one outline; region copies
    -- the health border's colour. Each piece MUST live in its own bar's subtree: a PP border is
    -- an OVERLAY texture that reliably beats its OWN bar's ARTWORK fill in the flattened render
    -- layer -- one frame spanning BOTH bars does NOT work (health half would render over the
    -- cast fill, the unreliable cross-flatten case). The region rides "Casts In Front of
    -- Nameplates" natively and lets the lower half bridge a Cast Bar Y gap / enclose an
    -- in-width icon: PP snaps a border's edges to its own frame (SnapBorderTextures), so the
    -- cast bar's own border could only hug the narrower/gapped cast bar. shouldWrap covers
    -- the simple PP border only; the custom border has its own branch and flag
    -- (ns.NP_UpdateCustomBorderWrap, plate._cbWrapActive), run after it.
    function backing:UpdateBorderWrap()
        if not Pix or not Pix.GetBorders then
            return
        end
        -- Classic WoW UI: no CUI borders to wrap (the vanilla art is drawn).
        if mod.NP_Classic() then
            return
        end
        local shouldWrap = mod.GetWrapBorderCastbar()
            and backing.cast
            and backing.cast:IsShown()
            and IsBorderEnabled()
            and not mod.IsCustomBorderEnabled()
        if shouldWrap then
            local hb = Pix.GetBorders(backing.health)
            if hb then
                local sz = mod.NP_BorderSize()
                -- The target border-size effect (ApplyTarget) already resized the health
                -- border before the cast bar showed; carry that size into the wrap instead
                -- of falling back to the base size, or starting a cast on your target visibly
                -- shrinks the border back to normal until the next target change.
                if backing._targetBorderSized then
                    local tbsz = mod.GetTargetBorderSizeValue()
                    if tbsz then
                        sz = tbsz
                    end
                end
                local column = hb._bdColor
                local r, g, b, a = 0, 0, 0, 1
                if column then
                    r, g, b, a = column[1], column[2], column[3], column[4] or 1
                end
                -- Threat Colors "Border" tint on the health border: _bdColor keeps only the
                -- last CLEAN colour (PP leaves a secret off-tank fold out of it), so the
                -- region and the re-snapped health border take the parked tint from the
                -- plate. It may be secret: it only ever reaches PP.SetBorderColor, never
                -- the CreateBorder below (which stores its colour) or a compare.
                local thr = backing._hbThreatTint and backing._threatBdOn
                -- Region frame (child of plate.cast) spans the FULL footprint width from the
                -- health bar's BOTTOM to the cast bar's BOTTOM, bridging any Cast Bar Y-offset
                -- gap and enclosing an in-width cast icon; health border keeps top+sides. The
                -- seam (health bottom + region top) is hidden to read as one outline, and the
                -- health border's live colour is copied onto the region (target highlight carries over).
                local regionFrame = backing.castWrapRegion
                if not regionFrame then
                    regionFrame = CreateFrame("Frame", nil, backing.cast)
                    backing.castWrapRegion = regionFrame
                end
                regionFrame:ClearAllPoints()
                regionFrame:SetPoint("TOPLEFT", backing.health, "BOTTOMLEFT", 0, 0)
                regionFrame:SetPoint("TOPRIGHT", backing.health, "BOTTOMRIGHT", 0, 0)
                regionFrame:SetPoint("BOTTOM", backing.cast, "BOTTOM", 0, 0)
                regionFrame:Show()
                -- Lift the region above the cast spell icon (raised to health-level+1 so a
                -- full-size icon clears the health bar), else an in-width icon draws ON TOP of
                -- the wrap border. Re-set every pass -- a strata propagation from the cast-lift would collapse it.
                if backing.castIconFrame then
                    regionFrame:SetFrameLevel(backing.castIconFrame:GetFrameLevel() + 2)
                end
                if not Pix.GetBorders(regionFrame) then
                    Pix.CreateBorder(regionFrame, r, g, b, a, sz, "OVERLAY", 7, true) -- scaleGuard: NP frame
                end
                -- Seam flags go on the containers BEFORE (re)snapping so SnapBorderTextures
                -- hides the two touching edges AND runs the side strips to the seam (no edge
                -- line, no corner notch). Flags survive every later re-snap (create-border
                -- 2-tick OnUpdate, scale changes, RefreshBorder); a one-shot :Hide() would not.
                local rb = Pix.GetBorders(regionFrame)
                if rb then
                    rb._hideTop = true
                end
                hb._hideBottom = true
                Pix.SetBorderSize(regionFrame, sz)
                if thr then
                    Pix.SetBorderColor(
                        regionFrame,
                        backing._threatBdR,
                        backing._threatBdG,
                        backing._threatBdB,
                        1
                    )
                else
                    Pix.SetBorderColor(regionFrame, r, g, b, a)
                end
                Pix.ShowBorder(regionFrame)
                Pix.SetBorderSize(backing.health, sz)
                -- The re-snap just re-applied _bdColor to the health strips.
                if thr then
                    mod.NP_BasicBorderColor(
                        backing,
                        backing._threatBdR,
                        backing._threatBdG,
                        backing._threatBdB,
                        1
                    )
                end
                -- Leave the cast bar's OWN border ACTIVE under the wrap (region border sits
                -- higher and draws over it); only the icon-separator line is hidden so an
                -- in-width icon stays seamless.
                if backing.castLeftBorder then
                    backing.castLeftBorder:Hide()
                end
                -- Optional: tint the full-size icon's border with the live target border colour
                -- to match the wrapped bar; else-branch keeps it black so toggling off resets it.
                if backing.castIconFrame and Pix.GetBorders(backing.castIconFrame) then
                    if
                        p
                        and p.castIconTargetBorder
                        and GetShowCastIcon()
                        and mod.GetCastIconFullSize()
                        and backing.unit
                        and UnitIsUnit(backing.unit, "target")
                        and mod.GetTargetGlowBorderColor()
                    then
                        Pix.SetBorderColor(backing.castIconFrame, r, g, b, a)
                    else
                        Pix.SetBorderColor(backing.castIconFrame, 0, 0, 0, 1)
                    end
                end
            end
            backing._wrapActive = true
        elseif backing._wrapActive then
            backing._wrapActive = false
            -- Clear the seam flag and re-snap the health border so its bottom edge/side insets
            -- come back (re-applies the live colour). Drop the region, hand the cast border back.
            local hb = Pix.GetBorders(backing.health)
            if hb then
                hb._hideBottom = nil
                local sz = mod.NP_BorderSize()
                if backing._targetBorderSized then
                    local tbsz = mod.GetTargetBorderSizeValue()
                    if tbsz then
                        sz = tbsz
                    end
                end
                Pix.SetBorderSize(backing.health, sz)
                -- The re-snap re-applied the last clean colour: put a threat tint back.
                if backing._hbThreatTint and backing._threatBdOn then
                    mod.NP_BasicBorderColor(
                        backing,
                        backing._threatBdR,
                        backing._threatBdG,
                        backing._threatBdB,
                        1
                    )
                end
            end
            if backing.castWrapRegion then
                local crb = Pix.GetBorders(backing.castWrapRegion)
                if crb then
                    crb._hideTop = nil
                end
                if crb then
                    Pix.HideBorder(backing.castWrapRegion)
                end
                backing.castWrapRegion:Hide()
            end
            if backing.castLeftBorder then
                backing.castLeftBorder:Show()
            end
            if backing.castIconFrame and Pix.GetBorders(backing.castIconFrame) then
                Pix.SetBorderColor(backing.castIconFrame, 0, 0, 0, 1)
            end
            backing:ApplyCastBorder()
            backing:ApplyCastBorderColor()
        end
        -- Custom border: wraps (or unwraps a plate it wrapped) whatever the Border mode now is.
        if backing._cbWrapActive or mod.IsCustomBorderEnabled() then
            mod.NP_UpdateCustomBorderWrap(backing)
        end
        mod.ApplyCastIconBorder(backing)
    end
    backing:ApplyCastBorder()
    backing.castLeftBorder = backing.cast:CreateTexture(nil, "OVERLAY", nil, 7)
    backing.castLeftBorder:SetColorTexture(0, 0, 0, 1)
    backing.castLeftBorder:SetWidth(1)
    backing.castLeftBorder:SetPoint("TOPLEFT", backing.cast, "TOPLEFT", 0, 0)
    backing.castLeftBorder:SetPoint("BOTTOMLEFT", backing.cast, "BOTTOMLEFT", 0, 0)
    -- Icon frame hangs outside the cast bar's left edge. Parented AND anchored to cast
    -- (auto-hides with it; same frame = single-pass resolve, no jitter).
    backing.castIconFrame = CreateFrame("Frame", nil, backing.cast)
    -- Lift above the health bar (level 10) once so a full-size icon is never occluded.
    backing.castIconFrame:SetFrameLevel(backing.health:GetFrameLevel() + 1)
    mod.LayoutCastIcon(backing, CAST_H)
    AddBorder(backing.castIconFrame)
    mod.ApplyCastIconBorder(backing)
    backing.castIcon = backing.castIconFrame:CreateTexture(nil, "ARTWORK")
    -- Fill the frame (inset 0) so the 1px OVERLAY border draws ON TOP of the icon's rim: the
    -- visible edge IS the border's inner edge, no bare frame gap. DisablePixelSnap matches the
    -- icon to the unsnapped border strips so they translate together under plate motion.
    backing.castIcon:SetPoint("TOPLEFT", backing.castIconFrame, "TOPLEFT", 0, 0)
    backing.castIcon:SetPoint("BOTTOMRIGHT", backing.castIconFrame, "BOTTOMRIGHT", 0, 0)
    if Pix and Pix.DisablePixelSnap then
        Pix.DisablePixelSnap(backing.castIcon)
    end
    -- Stock styles draw the whole icon (zoom 0); the CUI look trims the art's rim.
    if mod.NP_Blizz() then
        backing.castIcon:SetTexCoord(0, 1, 0, 1)
    else
        backing.castIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    backing.castSpark = backing.cast:CreateTexture(nil, "OVERLAY", nil, 1)
    backing.castSpark:SetTexture("Interface\\AddOns\\CludesUI\\media\\cast_spark.tga")
    backing.castSpark:SetSize(8, CAST_H)
    backing.castSpark:SetPoint("CENTER", backing.cast:GetStatusBarTexture(), "RIGHT", 0, 0)
    backing.castSpark:SetBlendMode("ADD")
    -- Show Spark (Cast Color cog): default on; explicit false hides it.
    backing.castSpark:SetShown(not (p and p.castBarSparkEnabled == false))
    local shieldHeight = CAST_H * 0.75
    local shieldWidth = shieldHeight * (29 / 35)
    backing.castShieldFrame = CreateFrame("Frame", nil, backing.cast)
    backing.castShieldFrame:SetSize(shieldWidth, shieldHeight)
    backing.castShieldFrame:SetPoint("CENTER", backing.cast, "LEFT", 0, 0)
    backing.castShieldFrame:SetFrameLevel(backing.castIconFrame:GetFrameLevel() + 5)
    backing.castShieldFrame:Hide()
    backing.castShield = backing.castShieldFrame:CreateTexture(nil, "OVERLAY")
    backing.castShield:SetAllPoints()
    backing.castShield:SetTexture("Interface\\AddOns\\CludesUINameplates\\Media\\shield.png")
    backing.castBarOverlay = backing.cast:CreateTexture(nil, "ARTWORK", nil, 2)
    backing.castBarOverlay:SetAllPoints(backing.cast:GetStatusBarTexture())
    backing.castBarOverlay:SetTexture("Interface\\Buttons\\WHITE8x8")
    backing.castBarOverlay:SetAlpha(0)
    -- Kick tick: clip frame so the tick never renders outside the cast bar when kick CD exceeds
    -- remaining cast time. ONLY kick elements go here; icon/text/shield/spark stay unclipped.
    backing.kickClip = CreateFrame("Frame", nil, backing.cast)
    backing.kickClip:SetAllPoints(backing.cast)
    backing.kickClip:SetClipsChildren(true)
    backing.kickPositioner = CreateFrame("StatusBar", nil, backing.kickClip)
    backing.kickPositioner:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    backing.kickPositioner:GetStatusBarTexture():SetAlpha(0)
    -- Pixel-snap OFF on the fill texture. The tick sits at positioner_width + marker_width; if
    -- either fill snaps independently, round(a)+round(b) flips by 1px when one width crosses a
    -- pixel boundary and the other does not, even though the ratio is invariant -- that's the
    -- jitter. Belt-and-suspenders: the load-bearing unsnap is after each SetFillStyle in
    -- UpdateKickTick (SetFillStyle re-mints the fill to snap-ON; the global SetStatusBarTexture
    -- hook won't re-fire on an already-cached bar).
    if backing.kickPositioner:GetStatusBarTexture().SetSnapToPixelGrid then
        backing.kickPositioner:GetStatusBarTexture():SetSnapToPixelGrid(false)
        backing.kickPositioner:GetStatusBarTexture():SetTexelSnappingBias(0)
    end
    backing.kickPositioner:SetPoint("CENTER", backing.cast)
    backing.kickPositioner:SetFrameLevel(backing.cast:GetFrameLevel() + 1)
    backing.kickPositioner:Hide()
    backing.kickMarker = CreateFrame("StatusBar", nil, backing.kickClip)
    backing.kickMarker:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    backing.kickMarker:GetStatusBarTexture():SetAlpha(0)
    if backing.kickMarker:GetStatusBarTexture().SetSnapToPixelGrid then
        backing.kickMarker:GetStatusBarTexture():SetSnapToPixelGrid(false)
        backing.kickMarker:GetStatusBarTexture():SetTexelSnappingBias(0)
    end
    backing.kickMarker:SetPoint("LEFT", backing.kickPositioner:GetStatusBarTexture(), "RIGHT")
    backing.kickMarker:SetSize(1, 1) -- sized later in UpdateKickTick
    backing.kickMarker:SetFrameLevel(backing.cast:GetFrameLevel() + 2)
    backing.kickMarker:Hide()
    backing.kickTick = backing.kickMarker:CreateTexture(nil, "OVERLAY", nil, 3)
    backing.kickTick:SetColorTexture(1, 1, 1, 1)
    backing.kickTick:SetWidth(2)
    backing.kickTick:SetPoint("TOP", backing.kickMarker, "TOP", 0, 0)
    backing.kickTick:SetPoint("BOTTOM", backing.kickMarker, "BOTTOM", 0, 0)
    backing.kickTick:SetPoint("LEFT", backing.kickMarker:GetStatusBarTexture(), "RIGHT")
    -- Interrupt-ready mid-cast fill: colors the cast-bar segment from "kick ready here" to cast
    -- end (window where the interrupt is available) when kick is on CD now but comes off before
    -- the cast finishes. Rides the SAME kickMarker geometry as the tick, so the "ready in time"
    -- two-secret-duration test resolves purely by where the marker texture edge lands: if the
    -- kick will NOT be ready the left/right anchors cross, the fill collapses to zero width and
    -- self-hides with no Lua branch on a secret. On plate.cast at ARTWORK sublevel 1: above the
    -- bar fill, below the OVERLAY cast text and uninterruptible grey overlay (sublevel 2).
    -- Anchors (re)applied per cast in UpdateKickTick.
    backing.kickReadyFill = backing.cast:CreateTexture(nil, "ARTWORK", nil, 1)
    backing.kickReadyFill:SetColorTexture(1, 1, 1, 1)
    backing.kickReadyFill:SetAlpha(0)
    backing.kickReadyFill:Hide()
    -- Cast bar text: three independent fixed zones [castName LEFT 50%] [castTarget
    -- CENTER-RIGHT 25%] [castTimer RIGHT 15%]. Explicit MEDIUM frame so text leaves the
    -- plate's flattened render layer and draws ABOVE the cast bar border.
    backing.castTextFrame = CreateFrame("Frame", nil, backing.cast)
    backing.castTextFrame:SetAllPoints(backing.cast)
    backing.castTextFrame:SetFrameStrata("MEDIUM")
    backing.castTextFrame:SetFrameLevel(900)
    backing.castName = backing.castTextFrame:CreateFontString(nil, "OVERLAY")
    SetFSFont(backing.castName, 10, GetNPOutline())
    backing.castName:SetPoint("LEFT", backing.cast, "LEFT", 5, 0)
    backing.castName:SetJustifyH("LEFT")
    backing.castName:SetWordWrap(false)
    backing.castName:SetMaxLines(1)
    backing.castTarget = backing.castTextFrame:CreateFontString(nil, "OVERLAY")
    SetFSFont(backing.castTarget, 10, GetNPOutline())
    backing.castTarget:SetJustifyH("RIGHT")
    backing.castTarget:SetWordWrap(false)
    backing.castTarget:SetNonSpaceWrap(false)
    backing.castTarget:SetMaxLines(1)
    backing.castTimer = backing.castTextFrame:CreateFontString(nil, "OVERLAY")
    SetFSFont(backing.castTimer, 10, GetNPOutline())
    backing.castTimer:SetPoint("RIGHT", backing.cast, "RIGHT", -3, 0)
    backing.castTimer:SetJustifyH("RIGHT")
    backing.castTimer:SetWordWrap(false)
    backing.castTimer:SetMaxLines(1)
    backing.castTimer:SetTextColor(1, 1, 1, 1)
    -- Cast timer on a 10Hz ANIM TICKER (engine sleeps between fires), never a per-frame
    -- OnUpdate: text is %.1f, so the displayed tenth cannot change faster than 0.1s, and a
    -- per-render-frame entry per casting plate at uncapped FPS is pure dispatch-floor cost for
    -- a 10Hz job (old accumulator measured 60.8ms/min in a caster-heavy pull). Armed by
    -- NotifyCastStarted; body self-stops at cast end. Uses
    -- UnitCastingDuration/UnitChannelDuration objects + :GetRemainingDuration(), since
    -- UnitCastingInfo's endTime/startTime are secret and unusable in arithmetic.
    backing.cast._timerTick = function(force)
        local self = backing.cast
        local ownerFrame = self._timerPlate
        -- force = the synchronous arm-time paint from NotifyCastStarted, which fires BEFORE
        -- the caller sets isCasting (Notify IS the rising-edge detector).
        if not ownerFrame or not ownerFrame.unit or (not ownerFrame.isCasting and not force) then
            return
        end
        if not ownerFrame._showCastTimer then
            return true
        end
        if UnitCastingDuration then
            local durObj = UnitCastingDuration(ownerFrame.unit)
                or (UnitEmpoweredChannelDuration and UnitEmpoweredChannelDuration(ownerFrame.unit, true))
                or (UnitChannelDuration and UnitChannelDuration(ownerFrame.unit))
            if durObj then
                local remaining = durObj:GetRemainingDuration()
                ownerFrame.castTimer:SetFormattedText("%.1f", remaining)
            else
                ownerFrame.castTimer:SetText("")
            end
        else
            local min, upper = ownerFrame.cast:GetMinMaxValues()
            local val = ownerFrame.cast:GetValue()
            if upper and upper > 0 then
                local remaining = upper - val
                if remaining < 0 then
                    remaining = 0
                end
                ownerFrame.castTimer:SetFormattedText("%.1f", remaining)
            else
                ownerFrame.castTimer:SetText("")
            end
        end
        return true
    end
    backing.cast._timerTicker = CludesUI.Tick.NewAnimTicker(backing.cast, backing.cast._timerTick, 0.1)
    backing.cast._timerPlate = backing
    -- Full-size cast icon: side-slot reserve is valid only while the cast bar is shown, so
    -- re-anchor reserving side elements on every cast show/hide. One chokepoint catches every
    -- path (start/stop/channel stop/interrupt flash+timer); RefreshCastIconSideReserve
    -- early-outs unless full-size is on.
    local function OnCastVisibilityChanged(self)
        local ownerFrame = self._timerPlate
        if ownerFrame and ownerFrame.RefreshCastIconSideReserve then
            ownerFrame:RefreshCastIconSideReserve()
        end
        -- Wrap-border driver, gated so when the feature is off (plate not wrapped) nothing
        -- runs beyond a field read + setting lookup.
        if
            ownerFrame
            and ownerFrame.UpdateBorderWrap
            and (ownerFrame._wrapActive or ownerFrame._cbWrapActive or mod.GetWrapBorderCastbar())
        then
            ownerFrame:UpdateBorderWrap()
        end
        -- Bottom text slots drop below the cast bar while it shows (one flag read when unused).
        if ownerFrame and mod._npBottomUsed then
            ownerFrame:AnchorBottomTexts()
        end
        -- Rounded corners, Join Cast Bar: the health bar's bottom corners follow the cast bar
        -- (a corners-only pass while nothing else about the health bar's rounding moved).
        if ownerFrame and ownerFrame._npJoinCast then
            mod.NP_ApplyRounding(ownerFrame, "health", true)
        end
        -- A cast end may turn the caster back (cast starts repaint in Cast.lua). The
        -- unit check skips a plate ClearUnit is releasing.
        if mod._npTgtTexts and ownerFrame and ownerFrame.unit and not self:IsShown() then
            ownerFrame:RefreshTargetTexts()
        end
    end
    backing.cast:HookScript("OnShow", OnCastVisibilityChanged)
    backing.cast:HookScript("OnHide", OnCastVisibilityChanged)
    backing:SetScript("OnEvent", function(self, evt, ...)
        local handler = self[evt]
        if handler then
            handler(self, ...)
        end
    end)
end)

-- Pre-warm the plate frame pool so AoE pulls don't pay the 2ms+ per-plate creation cost
-- (CreateFrame + child textures + cooldowns) on every Acquire when many plates appear in one
-- engine frame; a 5-mob pack can otherwise stack 10+ms of synchronous setup -> visible stutter.
-- Spread over 2 seconds (1 plate/100ms) after PLAYER_LOGIN so login stays smooth. Each Acquire
-- runs the pool's creation function; Release returns the frame for instant reuse.
do
    local prewarmFrame = CreateFrame("Frame")
    prewarmFrame:RegisterEvent("PLAYER_LOGIN")
    prewarmFrame:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        C_Timer.After(2, function()
            -- Hold acquires until end so each one actually creates a new pool frame.
            local held = {}
            local made = 0
            local targetUnit = 20
            local ticker
            ticker = C_Timer.NewTicker(0.1, function()
                made = made + 1
                if made > targetUnit then
                    for idx = 1, #held do
                        frameCache:Release(held[idx])
                    end
                    ticker:Cancel()
                    return
                end
                held[made] = frameCache:Acquire()
            end)
        end)
    end)
end

function mod.GetActiveKickSpell()
    return CludesUI.GetActiveKickSpell()
end
-- Cast overlay uses the same tint as the on-plate cast bar.
mod.ComputeCastBarTint = function(readyTint, baseTint)
    if CludesUI and CludesUI.ComputeCastBarTint then
        return CludesUI.ComputeCastBarTint(readyTint, baseTint)
    end
    return baseTint.r, baseTint.g, baseTint.b
end
local function GetActiveKickSpell()
    return mod.GetActiveKickSpell()
end
local ComputeCastBarTint = mod.ComputeCastBarTint
-- Re-evaluate the cast-bar wrap on every enemy plate; each plate self-decides to wrap or
-- unwrap, so this both applies and tears down. Called unconditionally from the option toggle
-- (catches toggle-off) and, gated on the setting, from the border refreshers, so size/colour
-- edits during a wrapped mid-cast plate keep the unified border in sync.
function mod.ApplyBorderWrapToAll()
    for _, backing in pairs(mod.plates) do
        if backing.UpdateBorderWrap then
            backing:UpdateBorderWrap()
        end
    end
end
function mod.RefreshBorder()
    -- Bump appearance gen so pooled/off-screen plates pick up the change on their next SetUnit.
    mod._npAppearanceGen = (mod._npAppearanceGen or 0) + 1
    for _, backing in pairs(mod.plates) do
        if backing.ApplyBorder then
            backing:ApplyBorder()
        end
        -- ApplyBorder draws the base colour (custom rebuild) or the last clean one (re-snap)
        -- over a Threat Colors tint, and the _threatBdK memo would skip the repaint.
        if backing._threatBdOn and backing.unit then
            backing:RepaintThreatBorder(backing.unit)
        end
    end
    -- Friendly plates mirror the enemy border settings 1:1.
    if mod.friendlyPlates then
        -- Target Border Effects: the base repaint drops a friendly target's target size
        -- and tint, so its ApplyTarget puts them back. One field read while off.
        local fx = p and p.friendlyTargetBorderFx
        for _, backing in pairs(mod.friendlyPlates) do
            if backing.ApplyBorder then
                backing:ApplyBorder()
            end
            if fx and backing._isTarget then
                backing:ApplyTarget()
            end
        end
    end
    -- Additive: no-op unless the wrap feature is enabled.
    if mod.GetWrapBorderCastbar() then
        mod.ApplyBorderWrapToAll()
    end
    -- Custom Border on Aura Icons: the aura styles carry the custom border, so a border
    -- edit restyles them (fingerprint-gated). One field read while off.
    if p and p.auraIconCustomBorder and mod.NPC_ReloadAll then
        mod.NPC_ReloadAll()
    end
    -- Debuff Coloring's Color Border is drawn from the border's own numbers
    -- (fingerprint-gated, one profile read while off).
    if mod.DebuffColors_RequestRefresh then
        mod.DebuffColors_RequestRefresh()
    end
end
mod.RefreshBorderStyle = mod.RefreshBorder
mod.RefreshSimpleBorderSize = mod.RefreshBorder
function mod.RefreshBorderColor()
    mod._npAppearanceGen = (mod._npAppearanceGen or 0) + 1
    for _, backing in pairs(mod.plates) do
        if backing.ApplyBorderColor then
            backing:ApplyBorderColor()
        end
    end
    -- Friendly plates mirror the enemy border settings 1:1.
    if mod.friendlyPlates then
        -- Target Border Effects: a friendly target keeps its target tint (a tint only;
        -- its untarget restore paints the new base colour). One field read while off.
        local keepTint = p and p.friendlyTargetBorderFx and mod.GetTargetGlowBorderColor()
        for _, backing in pairs(mod.friendlyPlates) do
            if
                backing.ApplyBorderColor and not (keepTint and backing._isTarget and backing._fxBorderTinted)
            then
                backing:ApplyBorderColor()
            end
        end
    end
    -- Additive: no-op unless the wrap feature is enabled.
    if mod.GetWrapBorderCastbar() then
        mod.ApplyBorderWrapToAll()
    end
    if p and p.auraIconCustomBorder and mod.NPC_ReloadAll then
        mod.NPC_ReloadAll()
    end
end
function mod.RefreshCastBorder()
    mod._npAppearanceGen = (mod._npAppearanceGen or 0) + 1
    for _, backing in pairs(mod.plates) do
        if backing.ApplyCastBorder then
            backing:ApplyCastBorder()
        end
    end
    -- ApplyCastBorder re-shows/re-sizes the cast border, so a wrapped mid-cast plate must re-merge.
    if mod.GetWrapBorderCastbar() then
        mod.ApplyBorderWrapToAll()
    end
end
function mod.RefreshCastBorderColor()
    mod._npAppearanceGen = (mod._npAppearanceGen or 0) + 1
    for _, backing in pairs(mod.plates) do
        if backing.ApplyCastBorderColor then
            backing:ApplyCastBorderColor()
        end
    end
    if mod.GetWrapBorderCastbar() then
        mod.ApplyBorderWrapToAll()
    end
end

function mod.RefreshStackingBounds()
    local scale = GetStackSpacingScale() / 100
    local barH = GetHealthBarHeight()
    local castH2 = GetCastBarHeight()
    local nameGap = 4 + GetEnemyNameTextSize()
    local totalH = nameGap + barH + castH2
    local wid = GetHealthBarWidth()
    for _, backing in pairs(mod.plates) do
        if backing._stackBounds then
            backing._stackBounds:SetSize(wid, totalH * scale)
        end
    end
end

function mod.RefreshStackingMotion()
    if not (Enum and Enum.NamePlateStackType) then
        return
    end
    local saved = p or defaultSet
    -- Enemy stacking is always CUI-owned; apply every time. Must NOT be gated on friendly
    -- players, or enemy plates stop stacking for anyone who hands friendly plates to Blizzard.
    CludesUI.SetCVarBitfield(
        "nameplateStackingTypes",
        Enum.NamePlateStackType.Enemy,
        saved.stackingEnabled ~= false,
        "CludesUINameplates"
    )
    -- Friendly stacking is only ours to write while we manage friendly players; when
    -- Blizzard-managed, leave the friendly bit untouched so the user's setting survives.
    if saved.showFriendlyPlayers ~= false then
        CludesUI.SetCVarBitfield(
            "nameplateStackingTypes",
            Enum.NamePlateStackType.Friendly,
            saved.stackingFriendly == true,
            "CludesUINameplates"
        )
    end
end

-- The click area's height: Hitbox Size Y scales the bar's height, and the
-- stock looks (Blizzard Style, its WoW Forever variant, Classic WoW UI) add 6
-- on top, their art reaching past the bar. The setting itself is untouched.
function mod.NP_HitboxHeight(saved)
    local hgt = GetHealthBarHeight() * ((saved.hitboxScaleY or 100) / 100)
    if mod.NP_Blizz() then
        hgt = hgt + 6
    end
    return hgt
end

function mod.RefreshHitboxSize()
    if InCombatLockdown() then
        return
    end
    if not C_NamePlate or not C_NamePlate.SetNamePlateSize then
        return
    end
    local saved = p or defaultSet
    local sx = (saved.hitboxScaleX or 100) / 100
    C_NamePlate.SetNamePlateSize(GetHealthBarWidth() * sx, mod.NP_HitboxHeight(saved))
    -- The frame grows from its CENTER, so a taller size enlarges the hitbox evenly above and
    -- below the unit. -10000 insets let the hit rect fill the full (centered) frame.
    if
        C_NamePlateManager
        and C_NamePlateManager.SetNamePlateHitTestInsets
        and Enum
        and Enum.NamePlateType
    then
        C_NamePlateManager.SetNamePlateHitTestInsets(Enum.NamePlateType.Enemy, -10000, -10000, -10000, -10000)
        C_NamePlateManager.SetNamePlateHitTestInsets(
            Enum.NamePlateType.Friendly,
            -10000,
            -10000,
            -10000,
            -10000
        )
    end
    -- Anchor content at the frame center (GetHitboxYShift is 0): the frame grows
    -- centered, so the bar stays put and the hitbox stays centered on it.
    local yShift = GetHitboxYShift()
    for _, backing in pairs(mod.plates) do
        backing:ClearAllPoints()
        backing:SetPoint("CENTER", backing.nameplate, "CENTER", 0, yShift)
    end
end

-- Hitbox visualizer: translucent overlay matching each enemy nameplate's clickable bounds (the
-- frame sized by SetNamePlateSize), so the Hitbox Size sliders can be dialled in visually.
-- Runtime-only (resets on reload), created lazily so it costs nothing when off. On ns (cap).
function mod._ApplyHitboxOverlay(backing)
    local np = backing and backing.nameplate
    if not np then
        return
    end
    if mod._hitboxOverlayShown then
        local shade = backing.hitboxOverlay
        if not shade then
            shade = CreateFrame("Frame", nil, np)
            local fillTex = shade:CreateTexture(nil, "BACKGROUND")
            fillTex:SetAllPoints()
            fillTex:SetColorTexture(0.298, 0.788, 0.941, 0.18)
            local function Edge()
                local t = shade:CreateTexture(nil, "BORDER")
                t:SetColorTexture(0.298, 0.788, 0.941, 0.85)
                return t
            end
            local topY, bottom, leftX, right = Edge(), Edge(), Edge(), Edge()
            topY:SetPoint("TOPLEFT")
            topY:SetPoint("TOPRIGHT")
            topY:SetHeight(1)
            bottom:SetPoint("BOTTOMLEFT")
            bottom:SetPoint("BOTTOMRIGHT")
            bottom:SetHeight(1)
            leftX:SetPoint("TOPLEFT")
            leftX:SetPoint("BOTTOMLEFT")
            leftX:SetWidth(1)
            right:SetPoint("TOPRIGHT")
            right:SetPoint("BOTTOMRIGHT")
            right:SetWidth(1)
            backing.hitboxOverlay = shade
        end
        -- Re-parent + re-anchor each apply: pooled plates get reused on a fresh nameplate.
        shade:SetParent(np)
        shade:SetFrameLevel(np:GetFrameLevel() + 10)
        shade:ClearAllPoints()
        shade:SetAllPoints(np)
        shade:Show()
    elseif backing.hitboxOverlay then
        backing.hitboxOverlay:Hide()
    end
end

-- Toggle the hitbox visualizer across every active enemy plate; driven by the eyeball button
-- beside the Hitbox Size sliders in options.
function mod.SetHitboxOverlayShown(show)
    mod._hitboxOverlayShown = show and true or false
    for _, backing in pairs(mod.plates) do
        mod._ApplyHitboxOverlay(backing)
    end
end

--- Full visual refresh for all plates when an entire preset is applied: re-runs SetUnit on each
--- active plate (re-reads all DB values). Deliberate switch only, never per-frame or per-event.
function mod.RefreshAllSettings()
    -- Re-read the profile reference: RepointAllDBs may have swapped the profile table
    -- (spec-linked profiles). All color lookups via _C() read this local.
    SetProfile(ENP.db.profile)
    -- Before any plate repaints: the Text Coloring slot flags the health pass reads
    -- and the name text's combo formats.
    mod.NP_RefreshSlotClassFlags()
    mod.NP_RefreshThreatPctFlag()
    mod.NP_RefreshThreatColorFlag()
    -- Bump the appearance generation so SetUnit re-runs ApplyAppearance per plate; without it,
    -- cache-hit re-spawns skip the static appearance work and new settings never apply.
    mod._npAppearanceGen = (mod._npAppearanceGen or 0) + 1
    -- Color Casting Enemies tint colors, before the loop below repaints the plates.
    if mod.NP_CastTintsDirty then
        mod.NP_CastTintsDirty()
    end
    for _, backing in pairs(mod.plates) do
        if backing.unit and backing.nameplate then
            backing:SetUnit(backing.unit, backing.nameplate)
        elseif backing.cast and backing.cast._iconSeam then
            mod.ApplyCastIconBorder(backing)
        end
    end
    -- WoW Forever's Show Level Box (per profile): on a flip the level
    -- watchers follow it and the friendly plates gain or park their boxes
    -- (the enemy plates followed through the appearance pass above).
    if mod._npForever and mod.NP_ForeverWatchLevels() then
        mod.NP_ForeverFriendlyBoxes()
    end
    if mod.NT_RefreshSetting then
        mod.NT_RefreshSetting()
    end
    if mod.NP_RefreshTypeScaleSetting then
        mod.NP_RefreshTypeScaleSetting()
    end
    if mod.RangeText_Apply then
        mod.RangeText_Apply()
    end
    if mod.ApplyClassPowerSetting then
        mod.ApplyClassPowerSetting()
    end
    if mod.DebuffColors_Refresh then
        mod.DebuffColors_Refresh()
    end
    -- Aura containers: fingerprint-guarded, near-free when no aura setting changed.
    if mod.NPC_ReloadAll then
        mod.NPC_ReloadAll()
    end
    -- Hide Enemy Nameplates OOC is CVar + event driven, and its options setter plus
    -- PLAYER_LOGIN were its only callers: a value written straight into the profile
    -- (override group, profile switch, import) flipped the checkbox while plates kept
    -- the old behaviour. Self-guarded, so an unchanged key costs nothing.
    if mod.ApplyOOCPlates then
        mod.ApplyOOCPlates()
    end
    -- Friendly faction badges: redraw for this profile's faction settings.
    mod.NP_RefreshFriendlyFaction()
    -- Friendly Target Border Effects: a profile or override flip reaches the friendly
    -- target now (applies, or restores a plate it styled). Field reads while off.
    if mod.friendlyPlates then
        local fx = p and p.friendlyTargetBorderFx
        for _, fp in pairs(mod.friendlyPlates) do
            if fx or fp._targetBorderSized or fp._fxBorderTinted then
                fp:ApplyTarget()
            end
        end
    end
    -- Friendly bar and name colours: a profile or override flip of the class colour
    -- toggles reaches the live full plates.
    if mod.RefreshFriendlyColors then
        mod.RefreshFriendlyColors()
    end
    -- A profile or override flip of the friendly Name Format, the Subtitle Text
    -- mode or its guild brackets reaches the live friendly names (one compare
    -- while they are unchanged).
    if mod.NP_SyncFriendlyNameFormat then
        mod.NP_SyncFriendlyNameFormat()
    end
end

Inner.frameCache, Inner.GetActiveKickSpell = frameCache, GetActiveKickSpell
Inner.broken = false
