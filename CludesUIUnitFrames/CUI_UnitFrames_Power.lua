if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_UnitFrames_Power.lua
--
--  The power bar seam, portrait separator and power border, spell cost
--  prediction and CreatePowerBar, published as I.CreatePowerBar for the files
--  that load after this one. Reads earlier files through ns and
--  ns._internals; db is set through I.dbSetters.
-------------------------------------------------------------------------------
local _, mod = ...
-- The options page pool's table (CludesUI_PixelPerfect.lua makes it; the
-- options addon fills it in place): read through this file local, never the
-- public slot.
local POOL = CludesUI._Pool

local issecretvalue = issecretvalue
local Pix = CludesUI.PP

local Inner = mod._internals
local GetSettingsForUnit, UnitToSettingsKey, SetFSFont =
    Inner.GetSettingsForUnit, Inner.UnitToSettingsKey, Inner.SetFSFont
local UnsnapTex, healthBarTextures = Inner.UnsnapTex, Inner.healthBarTextures
local ApplyBarGradient, ApplyPowerBarAlpha = Inner.ApplyBarGradient, Inner.ApplyPowerBarAlpha
local CUI_IsSmartPowerPercent = Inner.CUI_IsSmartPowerPercent
local PLAYER_POWER_DEFAULT, PLAYER_POWER_ALT = Inner.PLAYER_POWER_DEFAULT, Inner.PLAYER_POWER_ALT
local ClassColorSourceUnit = Inner.ClassColorSourceUnit
local saved
Inner.dbSetters[#Inner.dbSetters + 1] = function(val)
    saved = val
end

-- Power bar border: detached bars use the selected full border style; attached bars
-- use a solid divider only along the edge shared with the health bar. Lazy creation
-- lets a newly detached/attached bar (or Border Size raised from 0) gain its border
-- live. Shared by the creation path and player/target/focus refresh branches. On ns
-- for the Lua 5.1 200-local ceiling.
--
-- Power Bar Seam (s.borderPowerSeam, opt-in; player / target / focus / boss): the frame
-- Border Style's separator strip (CludesUI.GetBorderCompanion "sepH") along the
-- health / power join while the power bar is attached with a height, the frame
-- border is above 0 and its style has seam art; flipped for a bar above health.
-- It rides power._pbSeam, our own frame anchored to the power bar, built on first
-- enable and parented outside the bar clip so its ends can overlap the border,
-- tinted with the frame border colour, which FrameBorderEnter / Leave recolour
-- with the border. Thickness follows the border's edge (exact size, else the
-- step's), height and offsets snapped at the bar's effective scale; re-laid on
-- every pass (a pass on a zero-height bar leaves no resolved rect) and, for an
-- exact size, on a UI scale change (CludesUI.RegisterPxReapply). Returns true
-- while it shows, so the power border drops its solid shared-edge strip. Off,
-- under a stock style or a style without the art: nothing is built or run past
-- the first tests. stock = nil reads the session's style; preview = true (the
-- options preview, which repaints itself on a scale change) skips the UI-scale
-- registration.
function mod.UpdatePowerSeam(power, s, stock, preview)
    local seam = power._pbSeam
    local b = s
    local sizeOverride
    local filePath
    if s and s.borderPowerSeam == true then
        if s == saved.profile.boss then
            b = mod.UF_BossBorderSettings()
            sizeOverride = s.borderSizeOverride
        end
        if stock == nil then
            stock = mod.UF_Blizz()
        end
        local place = s.powerPosition or "below"
        if
            not stock
            and (place == "above" or place == "below")
            and (s.powerHeight or 6) > 0
            and (sizeOverride or b.borderSize or 1) > 0
            and power:IsShown()
        then
            filePath = CludesUI.GetBorderCompanion(b.borderTexture or "solid", "sepH")
        end
    end
    if not filePath then
        if seam and seam:IsShown() then
            seam:Hide()
            CludesUI.RegisterPxReapply(seam, nil)
        end
        return false
    end
    -- Live power bars sit inside _barClip; a higher level alone cannot escape
    -- that clipping. Keep the seam on the unit frame, as in the preview.
    local ownerFrame = power:GetParent()
    while ownerFrame and not (ownerFrame.unifiedBorder or ownerFrame._border) do
        ownerFrame = ownerFrame:GetParent()
    end
    local border = ownerFrame and (ownerFrame.unifiedBorder or ownerFrame._border)
    local hostFrame = ownerFrame or power
    if not seam then
        -- Through the options frame pool: a real frame for a live bar, handed
        -- back by the pool on the options preview's next build.
        seam = POOL.CreateFrame("Frame", nil, hostFrame)
        seam._tex = seam:CreateTexture(nil, "ARTWORK")
        power._pbSeam = seam
    elseif seam:GetParent() ~= hostFrame then
        seam:SetParent(hostFrame)
    end
    seam._power = power
    seam:ClearAllPoints()
    seam:SetAllPoints(power)
    -- Above the fills and the unit frame border, on the border's strata; capped
    -- at frame +11 so a border lifted for an inside 3D portrait (frame +20)
    -- does not carry the seam over the portrait and text layers.
    seam:SetFrameStrata((border or power):GetFrameStrata())
    seam:SetFrameLevel(
        math.max(
            power:GetFrameLevel() + 1,
            border and math.min(border:GetFrameLevel() + 1, ownerFrame:GetFrameLevel() + 11) or 0
        )
    )
    local key, size = b.borderTexture, sizeOverride or b.borderSize or 1
    local px
    if not sizeOverride then
        px = CludesUI.BorderPx(b.borderSizePx, size, key)
    end
    seam._key, seam._step, seam._px, seam._path = key, size, px, filePath
    seam._above = (s.powerPosition == "above")
    local c = b.borderColor
    seam._tex:SetVertexColor(c and c.r or 0, c and c.g or 0, c and c.b or 0, b.borderAlpha or 1)
    seam:Show()
    mod.UF_LayoutPowerSeam(seam)
    CludesUI.RegisterPxReapply(seam, (px and not preview) and mod.UF_LayoutPowerSeam or nil)
    return true
end

-- Lays the seam strip from the values UpdatePowerSeam stamped (also the
-- UI-scale re-derive for an exact size). The art's line sits in its top
-- texels (its soft edge spans texels 0-9 of 32, centred on texel 5): raising
-- the strip 5/32 of its thickness centres the line on the join.
function mod.UF_LayoutPowerSeam(seam)
    local power, t = seam._power, seam._tex
    local es = power:GetEffectiveScale()
    if not (es and es > 0.01) then
        es = UIParent:GetEffectiveScale()
    end
    local thick = CludesUI.BorderCompanionThickness(seam._key, seam._step, seam._px, es)
    if not thick or thick <= 0 then
        t:Hide()
        return
    end
    if t._path ~= seam._path then
        t:SetTexture(seam._path)
        t._path = seam._path
    end
    local raise = Pix.SnapForES(thick * 5 / 32, es)
    local portraitSeam = seam:GetParent()._portraitSeparator
    local leftInset, rightInset = 0, 0
    if portraitSeam and portraitSeam:IsShown() then
        -- Leave one physical pixel clear where the portrait divider meets the seam.
        if portraitSeam._right then
            rightInset = Pix.perfect / es
        else
            leftInset = Pix.perfect / es
        end
    end
    t:ClearAllPoints()
    if seam._above then
        -- Power above health: the join is the bar's bottom edge.
        t:SetTexCoord(0, 1, 1, 0)
        t:SetPoint("BOTTOMLEFT", power, "BOTTOMLEFT", leftInset, -raise)
        t:SetPoint("BOTTOMRIGHT", power, "BOTTOMRIGHT", -rightInset, -raise)
    else
        t:SetTexCoord(0, 1, 0, 1)
        t:SetPoint("TOPLEFT", power, "TOPLEFT", leftInset, raise)
        t:SetPoint("TOPRIGHT", power, "TOPRIGHT", -rightInset, raise)
    end
    t:SetHeight(thick)
    t:Show()
end

-- Attached portrait divider: reuse the border style's vertical companion art.
-- A sibling of the portrait avoids clipping the strip where it crosses into the
-- bars. Built only on opt-in; layout and colour updates use existing passes.
function mod.UpdatePortraitSeparator(widget, portrait, s, side, attached, stock, preview, borderSettings)
    local seam = widget._portraitSeparator
    local power = widget.Power or widget._power
    local powerSeam = power and power._pbSeam
    local sizeOverride = borderSettings and s.borderSizeOverride
    local b = borderSettings or s
    local size = sizeOverride or b.borderSize or 1
    local filePath
    if s.portraitSeparator and attached and portrait and portrait:IsShown() and not stock and size > 0 then
        filePath = CludesUI.GetBorderCompanion(b.borderTexture or "solid", "sepV")
    end
    if not filePath then
        if seam then
            seam:Hide()
            CludesUI.RegisterPxReapply(seam, nil)
            if powerSeam and powerSeam:IsShown() then
                mod.UF_LayoutPowerSeam(powerSeam)
            end
        end
        return
    end
    if not seam then
        -- Options frame pool: a real frame for a live frame (as above).
        seam = POOL.CreateFrame("Frame", nil, widget)
        seam._tex = seam:CreateTexture(nil, "ARTWORK")
        widget._portraitSeparator = seam
    end
    seam:SetAllPoints(portrait)
    -- Above portrait/bar fills and the outer border, on the same strata.
    local border = widget.unifiedBorder or widget._border
    seam:SetFrameLevel(
        math.max(widget:GetFrameLevel() + (preview and 4 or 9), border and border:GetFrameLevel() + 1 or 0)
    )
    seam._key, seam._step = b.borderTexture, size
    seam._px = nil
    if not sizeOverride then
        seam._px = CludesUI.BorderPx(b.borderSizePx, size, seam._key)
    end
    seam._right = side == "right"
    local c = b.borderColor
    seam._tex:SetVertexColor(c and c.r or 0, c and c.g or 0, c and c.b or 0, b.borderAlpha or 1)
    mod.UF_LayoutPortraitSeparator(seam)
    seam:Show()
    if powerSeam and powerSeam:IsShown() then
        mod.UF_LayoutPowerSeam(powerSeam)
    end
    CludesUI.RegisterPxReapply(seam, (seam._px and not preview) and mod.UF_LayoutPortraitSeparator or nil)
end

-- Lays the divider from the values UpdatePortraitSeparator stamped (also the
-- UI-scale re-layout): the shared placement on the portrait's inner edge,
-- the art's lead over the portrait, as on cast icons.
function mod.UF_LayoutPortraitSeparator(seam)
    CludesUI.PlaceBorderDividerV(
        seam._tex,
        seam,
        seam._right,
        true,
        seam._key,
        seam._step,
        seam._px,
        seam:GetEffectiveScale()
    )
end

function mod.UpdatePowerBorder(power, prefs)
    if not power or not prefs then
        return
    end
    -- Before the lazy return below: the seam has its own host.
    local seamOn = mod.UpdatePowerSeam(power, prefs)
    local place = mod.UF_PowerPos(prefs)
    local isDet = (place == "detached_top" or place == "detached_bottom")
    local isAttached = (place == "above" or place == "below")
    local size = prefs.powerBorderSize or 0
    local border = power._pbBorder
    if not border then
        -- Nothing to render and nothing to hide: stay lazy.
        if not ((isDet or isAttached) and size > 0) then
            return
        end
        -- Options frame pool: a real frame for a live bar (see UpdatePowerSeam).
        border = POOL.CreateFrame("Frame", nil, power)
        power._pbBorder = border
    end
    -- Re-anchored every pass: a pass that lands while the power bar is zero-height
    -- (Power Bar Height 0 before a Spec Override raises it) leaves the anchors set but
    -- no resolved rect, and nothing recomputes it; re-setting both points restores it.
    border:ClearAllPoints()
    Pix.Point(border, "TOPLEFT", power, "TOPLEFT", 0, 0)
    Pix.Point(border, "BOTTOMRIGHT", power, "BOTTOMRIGHT", 0, 0)
    local c = prefs.powerBorderColor or { r = 0, g = 0, b = 0 }
    local alpha = prefs.powerBorderAlpha or 1
    -- Attached bars are always Solid; their unused edges are hidden below so only
    -- the health/power seam stays visible.
    local style = isAttached and "solid" or (prefs.powerBorderStyle or "solid")
    -- Exact size (nil = the legacy path), resolved against the style actually
    -- painted: an attached bar is forced Solid, so a value paired with a textured
    -- style stands down there.
    local px = CludesUI.BorderPx(prefs.powerBorderSizePx, size, style)
    CludesUI.ApplyBorderStyle(
        border,
        size,
        c.r,
        c.g,
        c.b,
        alpha,
        style,
        prefs.powerBorderOffsetX,
        prefs.powerBorderOffsetY,
        prefs.powerBorderShiftX,
        prefs.powerBorderShiftY,
        "unitframes",
        size,
        nil,
        px
    )
    local edges = Pix.GetBorders(border)
    if edges then
        edges._hideLeft = isAttached or nil
        edges._hideRight = isAttached or nil
        edges._hideTop = (isAttached and place == "above") or nil
        edges._hideBottom = (isAttached and place == "below") or nil
        Pix.SetBorderSize(border, px or size)
    end
    local borderLevel = prefs.powerBorderBehind and math.max(0, power:GetFrameLevel() - 1)
        or (power:GetFrameLevel() + 5)
    border:SetFrameLevel(borderLevel)
    -- An attached bar's only strip is the shared edge, which a shown seam replaces.
    local showBorder = (isDet or isAttached) and size > 0 and not (isAttached and seamOn)
    if showBorder then
        border:Show()
    else
        border:Hide()
    end

    -- The power text overlay must clear the border: the border shares the bar's strata
    -- and can outrank the overlay's default level, so match strata and lift past it.
    local ovr = power._ppTextOvr
    if ovr then
        ovr:SetFrameStrata(power:GetFrameStrata())
        if showBorder then
            ovr:SetFrameLevel(borderLevel + 5)
        else
            local popFrame = power:GetParent()
            ovr:SetFrameLevel((popFrame and popFrame:GetFrameLevel() or power:GetFrameLevel()) + 15)
        end
    end
end

-------------------------------------------------------------------------------
--  Spell Cost Prediction (WoW Forever only; player, opt-in
--  s.powerCostPrediction): while a spell with a cast time is cast, the mana it
--  will spend is drawn on the power bar in a lighter color, like Blizzard's
--  player frame. The shared engine (CludesUI_SpellCostPrediction.lua, nil
--  off Forever) draws it; the bar attaches while the option is on and the bar
--  can show (position not None, height above 0) and detaches otherwise, so
--  nothing is built or registered while it is off.
--  On ns: this chunk sits at the Lua 5.1 local ceiling.
-------------------------------------------------------------------------------
-- Custom color, else Blizzard's mana prediction color: the engine's rule, read
-- here by the options row and its preview (both built only with the engine).
function mod.UF_PowerCostColor(s)
    return CludesUI.SpellCostPrediction.Color(s)
end

-- True while the player power bar draws: a position other than None (under a
-- stock style: Hide Power Bar off), and a height above 0 in the CUI look (a
-- stock style draws the attached bar at its own height). Spell Cost
-- Prediction and the mana regen spark gate on it.
function mod.UF_PowerBarDraws(prefs)
    local place = mod.UF_PowerPos(prefs)
    return place ~= "none"
        and ((prefs.powerHeight or 6) > 0 or (mod.UF_Blizz() and (place == "below" or place == "above")))
end

-- The player bar as an engine host: the power type PaintPower resolved (the
-- Power Type override first), the color at Power Bar Opacity, and the
-- Blizzard Style mask while the stock art masks the bar. The segment sits one
-- level above the bar (no inBar); the power border draws at power + 5.
if CludesUI.SpellCostPrediction then
    mod.UF_POWER_COST_HOST = {
        PowerType = function(power)
            return power.displayType or UnitPowerType("player")
        end,
        -- Power Bar Opacity, normalized as ApplyPowerBarAlpha does: the fill's
        -- own alpha stays at 1 while a gradient carries the opacity.
        Color = function()
            local s = GetSettingsForUnit("player")
            local r, g, b = mod.UF_PowerCostColor(s)
            local op = (s and s.powerBarOpacity) or 100
            if op <= 1.0 then
                op = op * 100
            end
            return r, g, b, op / 100
        end,
        Mask = function(power)
            return power._blizzMasked and power._blizzMask or nil
        end,
    }
end

function mod.UF_SetupPowerCost(power, prefs)
    local SCP = CludesUI.SpellCostPrediction
    if not SCP then
        return
    end
    if power and prefs and prefs.powerCostPrediction == true and mod.UF_PowerBarDraws(prefs) then
        SCP.Attach("uf", power, mod.UF_POWER_COST_HOST)
    else
        SCP.Detach("uf")
    end
end

-- The player's power value channel (engine "powerval", UNIT_POWER_FREQUENT)
-- is live while the player frame is visible, paints power, and shows the
-- value: the bar draws or a text zone reads power. Otherwise the event is
-- unregistered (a hidden frame, the UI hidden, a pet battle). Run on attach,
-- on the frame's show and hide, on each settings reload, on text zone changes
-- and on the Power element toggles; other frames return at once.
function mod.UF_PowerValSync(widget)
    if widget._cuiBaseUnit ~= "player" then
        return
    end
    local enabled = false
    if widget.Power and widget:IsVisible() and mod.Engine.ElementOn(widget, "Power") then
        local s = GetSettingsForUnit("player")
        enabled = (s and mod.UF_PowerBarDraws(s)) or false
        local zones = widget._cuiTextZones
        if not enabled and zones then
            for idx = 1, #zones do
                if zones[idx].power then
                    enabled = true
                    break
                end
            end
        end
    end
    mod.Engine.SetChannelOn(widget, "powerval", enabled)
end

-- A main frame's Power element under a stock style with Hide Power Bar on
-- paints nothing while no text zone reads power (Engine.ElementOn), and the
-- player's power value channel follows the element (UF_PowerValSync). A zone
-- that reads power keeps it on: the player's value pass, which repaints those
-- zones at full rate, and the power type they format run through it. Run on
-- every text zone change (the reload pass re-applies the power text, so a
-- Hide Power Bar change reaches it there). Every other frame, and the
-- CludesUI look, keeps the element as it is.
function mod.UF_PowerElementSync(widget)
    local base = widget._cuiBaseUnit
    if not widget.Power or not (base == "player" or base == "target" or base == "focus") then
        return
    end
    local wanted = not (mod.UF_Blizz() and mod.UF_PowerPos(GetSettingsForUnit(base)) == "none")
    if not wanted then
        local zones = widget._cuiTextZones
        if zones then
            for idx = 1, #zones do
                if zones[idx].power then
                    wanted = true
                    break
                end
            end
        end
    end
    if mod.Engine.ElementOn(widget, "Power") ~= wanted then
        if wanted then
            widget:EnableElement("Power")
        else
            widget:DisableElement("Power")
        end
    elseif base == "player" then
        mod.UF_PowerValSync(widget)
    end
end

-- Gray-out classification for the power bar's PostUpdate: true for a generic
-- melee NPC (no real power). One function, run through pcall with the unit.
function mod.UF_PowerShouldGray(u)
    if u == "player" or not UnitExists(u) then
        return false
    end
    if not UnitCanAttack("player", u) or UnitIsPlayer(u) then
        return false
    end
    local cls = UnitClassification(u)
    if cls == "worldboss" then
        return false
    end
    local isElite = (cls == "elite" or cls == "rareelite")
    local lvl = UnitLevel(u)
    local pLvl = UnitLevel("player")
    local lvlOk = lvl and not (issecretvalue and issecretvalue(lvl))
    local pLvlOk = pLvl and not (issecretvalue and issecretvalue(pLvl))
    if isElite and lvlOk and (lvl == -1 or (pLvlOk and lvl >= pLvl + 1)) then
        return false
    end
    local uCls = UnitClassBase and UnitClassBase(u)
    if issecretvalue(uCls) then
        uCls = nil
    end
    if uCls == "PALADIN" then
        return false
    end
    return true
end

-- Class Colored power fill (powerClassColored): players and AI party members use
-- their class color, the pet its owner's; NPCs return false and keep the power color.
-- Returns ok, r, g, b; r/g/b may be SECRET (see ns.ResolveBgClassColor).
mod.UF_PowerClassColor = function(unitToken)
    local cu = ClassColorSourceUnit(unitToken, unitToken)
    if not (UnitIsPlayer(cu) or (UnitInPartyIsAI and UnitInPartyIsAI(cu))) then
        return false
    end
    return mod.ResolveBgClassColor(cu)
end

local function CreatePowerBar(widget, unitToken, prefs)
    local powerPos = mod.UF_PowerPos(prefs)

    local power = CreateFrame("StatusBar", nil, widget)
    local isDetached = (powerPos == "detached_top" or powerPos == "detached_bottom")
    if isDetached then
        -- Custom strata when enabled, otherwise MEDIUM.
        if saved.profile.enableCustomBarStratas then
            power:SetFrameStrata(saved.profile.detachedPowerStrata or "HIGH")
        else
            power:SetFrameStrata("MEDIUM")
        end
    else
        power:SetFrameStrata(widget:GetFrameStrata())
    end
    power:SetFrameLevel(widget:GetFrameLevel() + (isDetached and 12 or 3))
    local pw = prefs.frameWidth
    if isDetached and (prefs.powerWidth or 0) > 0 then
        pw = prefs.powerWidth
    end
    Pix.Size(power, pw, prefs.powerHeight)

    if powerPos == "none" then
        power:Hide()
    elseif powerPos == "above" then
        Pix.Point(power, "BOTTOMLEFT", widget.Health, "TOPLEFT", 0, 0)
        Pix.Point(power, "BOTTOMRIGHT", widget.Health, "TOPRIGHT", 0, 0)
    elseif powerPos == "detached_top" then
        power:SetPoint("BOTTOM", widget.Health, "TOP", prefs.powerX or 0, 15 + (prefs.powerY or 0))
    elseif powerPos == "detached_bottom" then
        power:SetPoint("TOP", widget.Health, "BOTTOM", prefs.powerX or 0, -15 + (prefs.powerY or 0))
    else -- "below" (default)
        Pix.Point(power, "TOPLEFT", widget.Health, "BOTTOMLEFT", 0, 0)
        Pix.Point(power, "TOPRIGHT", widget.Health, "BOTTOMRIGHT", 0, 0)
    end

    -- Same bar texture as health; WHITE8X8 when none is configured.
    local texKey = (prefs and prefs.healthBarTexture) or saved.profile.healthBarTexture or "none"
    local texPath = CludesUI.ResolveTexturePath(healthBarTextures, texKey, "Interface\\Buttons\\WHITE8X8")
    power:SetStatusBarTexture(texPath)
    power:GetStatusBarTexture():SetHorizTile(false)
    do
        local pFill = power:GetStatusBarTexture()
        if pFill then
            UnsnapTex(pFill)
        end
    end

    local backdrop = power:CreateTexture(nil, "BACKGROUND")
    Pix.Point(backdrop, "TOPLEFT", power, "TOPLEFT", 0, 0)
    Pix.Point(backdrop, "BOTTOMRIGHT", power, "BOTTOMRIGHT", 0, 0)
    local initBg = prefs.customPowerBgColor
    if initBg then
        backdrop:SetColorTexture(initBg.r, initBg.g, initBg.b, 1)
    else
        backdrop:SetColorTexture(17 / 255, 17 / 255, 17 / 255, 1)
    end
    UnsnapTex(backdrop)
    power.bg = backdrop

    -- Fill color is driven by the powerPercentPowerColor toggle; the gradient
    -- layers additively on top of the resolved custom/power-type color.
    local usePowerColor = prefs.powerPercentPowerColor ~= false
    power.colorPower = usePowerColor
    if not usePowerColor then
        local customFill = prefs.customPowerFillColor
        if customFill then
            power:SetStatusBarColor(customFill.r, customFill.g, customFill.b)
        else
            power:SetStatusBarColor(0, 0, 1)
        end
    end
    power.PostUpdateColor = function(self)
        local s2 = GetSettingsForUnit(unitToken)
        if not s2 then
            return
        end
        local useP = s2.powerPercentPowerColor ~= false
        local bR, bG, bB
        -- PLAIN stand-ins for bR, which is secret for a restricted unit's class color.
        local haveBase, baseSecret = false, false
        if not useP then
            local castFrame = s2.customPowerFillColor
            if castFrame then
                bR, bG, bB = castFrame.r, castFrame.g, castFrame.b
            else
                bR, bG, bB = 0, 0, 1
            end
            haveBase = true
        else
            if s2.powerClassColored then
                haveBase, bR, bG, bB = mod.UF_PowerClassColor(unitToken)
                baseSecret = haveBase and issecretvalue(bR)
            end
            if not haveBase then
                -- Secret-safe: player via the clean token, non-player via the clean integer
                -- power type, so the custom color applies on EVERY unit without depending
                -- on oUF's colors.power sync. Unmapped power types return nil (keep oUF's).
                bR, bG, bB = CludesUI.ResolveUnitPowerColor(unitToken)
                haveBase = bR ~= nil
            end
        end
        -- SetGradient rejects secrets; a secret base falls through to the flat paint.
        if s2.powerGradientEnabled and haveBase and not baseSecret then
            local gc = s2.powerGradientColor
            -- Bake Bar Opacity into the gradient endpoint alphas (a gradient
            -- overrides region alpha).
            local ga = s2.powerBarOpacity or 100
            if ga > 1.0 then
                ga = ga / 100
            end
            ApplyBarGradient(
                self:GetStatusBarTexture(),
                s2.powerGradientDir or "HORIZONTAL",
                bR,
                bG,
                bB,
                ga,
                gc and gc.r or 0.20,
                gc and gc.g or 0.20,
                gc and gc.b or 0.80,
                ga
            )
        elseif not useP then
            local castFrame = s2.customPowerFillColor
            if castFrame then
                self:SetStatusBarColor(castFrame.r, castFrame.g, castFrame.b)
            else
                self:SetStatusBarColor(0, 0, 1)
            end
        elseif haveBase then
            -- Power/class-color mode without gradient: apply CUI's GLOBAL color.
            -- oUF.colors.power is not overridden, so oUF would otherwise leave the
            -- bar on its built-in default instead of the user's.
            self:SetStatusBarColor(bR, bG, bB)
        end
        -- Power-colored bg tracks this unit's power color each update, following
        -- target/power-type changes (mirrors the fill). Opacity stays on
        -- customPowerBgAlpha; gated off = zero cost (custom/dark bg stands unchanged).
        if s2.powerBgPowerColored and self.bg then
            local pr, pg, pb = CludesUI.ResolveUnitPowerColor(unitToken)
            if pr then
                local f = CludesUI.GetPowerBgDarkenFactor()
                self.bg:SetColorTexture(pr * f, pg * f, pb * f, 1)
            end
        end
        -- Keep power-percent text color in sync with THIS unit (fires on target/focus
        -- change + UNIT_DISPLAYPOWER, following the unit rather than creation-time
        -- color). Gated on power-colored AND text shown: no cost on other frames.
        if
            s2.powerPercentTextPowerColor
            and (s2.powerPercentText or "none") ~= "none"
            and self._applyPowerTextColor
        then
            self._applyPowerTextColor(s2)
        end
        -- Same for the Bottom Text Bar's power-colored text (per-slot early-out
        -- keeps it ~free when no slot uses power color).
        local btb = widget.BottomTextBar
        if btb and btb._applyBTBPowerColors then
            btb._applyBTBPowerColors(s2)
        end
    end

    local customBg = prefs.customPowerBgColor
    if customBg then
        backdrop:SetColorTexture(customBg.r, customBg.g, customBg.b, 1)
    end

    power:SetReverseFill(prefs.powerReverseFill and true or false)

    -- Power percent text overlay, parented to the frame (not power) so the bar
    -- clip container cannot clip it.
    local ppTextOvr = CreateFrame("Frame", nil, widget)
    ppTextOvr:SetAllPoints(power)
    ppTextOvr:SetFrameLevel(widget:GetFrameLevel() + 15)
    local ppFS = ppTextOvr:CreateFontString(nil, "OVERLAY")
    SetFSFont(ppFS, prefs.powerPercentSize or 9)
    ppFS:Hide()
    power._ppFS = ppFS
    power._ppTextOvr = ppTextOvr

    -- Power-percent text color for the CURRENT unit, so target/focus follow the unit
    -- rather than the player. Power-color mode resolves the unit's own power type;
    -- enemies returning a secret token that can't map to a color fall back to white.
    -- No-power units are NOT special-cased and keep showing 0%.
    local function ApplyPowerTextColor(s)
        if s.powerPercentTextPowerColor then
            -- Secret-safe per-unit color: player keeps the exact token color,
            -- non-player recovers it from the clean integer power type.
            local r, g, b = CludesUI.ResolveUnitPowerColor(unitToken)
            if r then
                ppFS:SetTextColor(r, g, b)
            else
                ppFS:SetTextColor(1, 1, 1)
            end
        elseif s.powerTextColor then
            local tc = s.powerTextColor
            ppFS:SetTextColor(tc.r, tc.g, tc.b, tc.a or 1)
        else
            ppFS:SetTextColor(1, 1, 1)
        end
    end
    power._applyPowerTextColor = ApplyPowerTextColor

    local function ApplyPowerPercentText(s)
        local place = s.powerPercentText or "none"
        -- Hide Power Bar (a stock style's main frames) takes the text down
        -- with the bar, its zone included, so nothing reads power for it.
        if mod.UF_Blizz() and mod.UF_IsMainSettings(s) and mod.UF_StockHidesPower(s) then
            place = "none"
        end
        local sz = s.powerPercentSize or 9
        local ox = s.powerPercentX or 0
        local oy = s.powerPercentY or 0

        -- Power Bar Height 0 collapses the bar to a ZERO-HEIGHT frame, and WoW does not
        -- resolve a zero-height frame's rect (GetLeft() returns nil), so any overlay
        -- anchored to it becomes a 0-width unpositioned strip and text never renders.
        -- Anchor the text overlay to the HEALTH bar instead (always resolved), giving
        -- it real height in the row the power bar would occupy. _cuiHeight0 leaves
        -- frames that never hit height 0 untouched; a positive height restores SetAllPoints.
        -- A stock style draws an attached bar at its track's own height.
        local pPos = mod.UF_PowerPos(s)
        if (s.powerHeight or 6) <= 0 and not (mod.UF_Blizz() and (pPos == "below" or pPos == "above")) then
            local anchorTo = widget.Health or power
            ppTextOvr:ClearAllPoints()
            if pPos == "above" or pPos == "detached_top" then
                -- Power row above health: text strip sits above the health bar.
                ppTextOvr:SetPoint("BOTTOMLEFT", anchorTo, "TOPLEFT", 0, 0)
                ppTextOvr:SetPoint("BOTTOMRIGHT", anchorTo, "TOPRIGHT", 0, 0)
            else
                -- "below"/"detached_bottom": strip sits below the health bar.
                ppTextOvr:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, 0)
                ppTextOvr:SetPoint("TOPRIGHT", anchorTo, "BOTTOMRIGHT", 0, 0)
            end
            ppTextOvr:SetHeight(sz + 6)
            ppTextOvr._cuiHeight0 = true
        elseif ppTextOvr._cuiHeight0 then
            ppTextOvr:ClearAllPoints()
            ppTextOvr:SetAllPoints(power)
            ppTextOvr._cuiHeight0 = nil
        end

        SetFSFont(ppFS, sz)
        ppFS:ClearAllPoints()

        if place == "none" then
            ppFS:Hide()
            mod.SetTextZoneRaw(widget, ppFS, nil)
            return
        end

        if place == "left" then
            ppFS:SetJustifyH("LEFT")
            Pix.Point(ppFS, "LEFT", ppTextOvr, "LEFT", 2 + ox, oy)
        elseif place == "right" then
            ppFS:SetJustifyH("RIGHT")
            Pix.Point(ppFS, "RIGHT", ppTextOvr, "RIGHT", -2 + ox, oy)
        else
            ppFS:SetJustifyH("CENTER")
            Pix.Point(ppFS, "CENTER", ppTextOvr, "CENTER", ox, oy)
        end

        local showPct = s.powerShowPercent ~= false
        local pctSuffix = showPct and "%%" or ""
        local fmt = s.powerTextFormat or "perpp"
        local TP = mod.TextPieces
        if fmt == "custom" then
            -- Tag template (powerTextCustomFormat); a missing format shows nothing.
            mod.SetTextZone(widget, ppFS, "custom", "powerText", s)
        elseif fmt == "curpp" then
            mod.SetTextZoneRaw(widget, ppFS, "%s", { TP.curpp })
        elseif fmt == "curmaxpp" then
            mod.SetTextZoneRaw(widget, ppFS, "%s / %s", { TP.curpp, TP.maxpp })
        elseif fmt == "both" then
            mod.SetTextZoneRaw(widget, ppFS, "%s | %s" .. pctSuffix, { TP.curpp, TP.perpp })
        elseif fmt == "smart" then
            -- Percent for mana-based specs, numeric otherwise (always numeric on
            -- WoW Forever); resolved at apply time and re-applied on spec change
            -- via ReloadAndUpdate.
            local isPercent = CUI_IsSmartPowerPercent()
            if isPercent then
                mod.SetTextZoneRaw(widget, ppFS, "%s" .. pctSuffix, { TP.perpp })
            else
                mod.SetTextZoneRaw(widget, ppFS, "%s", { TP.curpp })
            end
        else -- "perpp" default
            mod.SetTextZoneRaw(widget, ppFS, "%s" .. pctSuffix, { TP.perpp })
        end
        mod.UF_PaintText(widget, widget._cuiUnit or unitToken)

        -- Priority: power-colored (per-unit) > custom color > white.
        ApplyPowerTextColor(s)
        ppFS:Show()
    end

    ApplyPowerPercentText(prefs)
    power._applyPowerPercentText = ApplyPowerPercentText

    ApplyPowerBarAlpha(power, UnitToSettingsKey(unitToken))

    -- Gray out the power bar for enemy NPCs with no real power (melee mobs); keep
    -- it for player, friendly units, enemy players, bosses, minibosses, casters.
    power._grayedOut = false
    power.PostUpdate = function(self, u, current, min, max)
        local s = GetSettingsForUnit(u)
        if not s then
            return
        end

        local pp = mod.UF_PowerPos(s)
        if pp == "none" or pp == "detached_top" or pp == "detached_bottom" then
            return
        end

        -- Classification check: generic melee NPCs get the gray bar.
        local success, shouldGray = pcall(mod.UF_PowerShouldGray, u)
        if not success then
            return
        end

        if shouldGray and not self._grayedOut then
            self._grayedOut = true
            if self.bg then
                self.bg:SetColorTexture(0.25, 0.25, 0.25, 1)
                self.bg:SetAlpha(1)
            end
        elseif not shouldGray and self._grayedOut then
            self._grayedOut = false
            if s.powerBgPowerColored and self.bg then
                -- Restore this unit's power color (mirrors the fill); the next
                -- PostUpdateColor keeps it tracking thereafter.
                local pr, pg, pb = CludesUI.ResolveUnitPowerColor(u)
                if pr then
                    local f = CludesUI.GetPowerBgDarkenFactor()
                    self.bg:SetColorTexture(pr * f, pg * f, pb * f, 1)
                else
                    self.bg:SetColorTexture(17 / 255, 17 / 255, 17 / 255, 1)
                end
            else
                local customBg = s.customPowerBgColor
                if customBg then
                    if self.bg then
                        self.bg:SetColorTexture(customBg.r, customBg.g, customBg.b, 1)
                    end
                else
                    if self.bg then
                        self.bg:SetColorTexture(17 / 255, 17 / 255, 17 / 255, 1)
                    end
                end
            end
            -- Bg alpha comes from customPowerBgAlpha (matching ApplyPowerBarAlpha),
            -- NOT powerBarOpacity, which is the FILL opacity.
            if self.bg then
                self.bg:SetAlpha((s and (s.customPowerBgAlpha or 100) or 100) / 100)
            end
        end
    end

    -- Per-spec power type override: an alternate power type on the player power bar
    -- (e.g. Balance Druid: Astral Power vs Mana). Shadow Priest and Mistweaver Monk
    -- default to Mana; other specs default to UnitPowerType.
    if unitToken == "player" then
        local _, class = UnitClass("player")
        if PLAYER_POWER_DEFAULT[class] or PLAYER_POWER_ALT[class] then
            power.displayAltPower = true
            power.GetDisplayPower = function(self, u)
                local resolved = CludesUI.GetPlayerPowerOverride()
                -- Publish for tags so the text matches the bar.
                _G._CUI_ResolvedPowerType[u or "player"] = resolved
                return resolved
            end
        end
    end

    -- Power bar border: full when detached, divider when attached; lazy.
    mod.UpdatePowerBorder(power, prefs)

    if unitToken == "player" then
        mod.UF_SetupPowerCost(power, prefs)
    end
    -- WoW Forever druids: Mana + Form Power (CUI_UnitFrames_ForeverFormBar.lua).
    if unitToken == "player" and mod.UF_ForeverFormBar then
        mod.UF_ForeverFormBar(widget, power, prefs)
    end

    return power
end

Inner.CreatePowerBar = CreatePowerBar
