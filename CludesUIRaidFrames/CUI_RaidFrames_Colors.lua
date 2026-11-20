if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_RaidFrames_Colors.lua
--
--  Health percent and the class, health, name and power colors, the display
--  name, the top name bar, power text and level text.
--  Reads the earlier Raid Frames files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._internals
-- CludesUIRaidFrames.lua or an earlier Raid Frames file failed to load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local pairs = pairs
local wipe = wipe
local type = type
local tostring = tostring
local UnitHealth = UnitHealth
local UnitPower = UnitPower
local UnitPowerType = UnitPowerType
local UnitName = UnitName
local UnitClass = UnitClass
local UnitExists = UnitExists
local UnitIsConnected = UnitIsConnected
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitGetTotalHealAbsorbs = UnitGetTotalHealAbsorbs
local InCombatLockdown = InCombatLockdown
local issecretvalue = issecretvalue

local AbbreviateNumbers, ApplyFont, defaultSet = Inner.AbbreviateNumbers, Inner.ApplyFont, Inner.defaults
local DISPEL_COLORS, GetFFD, PixelSnap = Inner.DISPEL_COLORS, Inner.GetFFD, Inner.PixelSnap
local unitToButton = Inner.unitToButton

-- Health, max health and absorb text: the global Number Format for valueType
-- (Power Text keeps the module's default call).
local AbbreviateValue = mod.CludesUI.AbbreviateValue

local saved
Inner.dbSetters[#Inner.dbSetters + 1] = function(val)
    saved = val
end

-------------------------------------------------------------------------------
--  Color helpers
-------------------------------------------------------------------------------
-- Safe health percent: returns 0-100, no secret value arithmetic. inv: the
-- missing-health percent instead (100-0, the reversed curve), for a bar under
-- Inverted Fill.
local function GetSafeHealthPercent(unitToken, inv)
    if inv then
        return UnitHealthPercent(unitToken, true, CurveConstants.ReverseTo100)
    end
    return UnitHealthPercent(unitToken, true, CurveConstants.ScaleTo100)
end

-- Classic health color curve: red (dead) -> yellow (mid) -> green (full). Built
-- once via C_CurveUtil and passed to UnitHealthPercent, which handles secret
-- values internally and returns a clean ColorMixin.
local classicHealthCurve
local function GetClassicHealthCurve()
    if classicHealthCurve then
        return classicHealthCurve
    end
    local curve = C_CurveUtil.CreateColorCurve()
    curve:SetType(Enum.LuaCurveType.Linear)
    curve:AddPoint(0, CreateColor(1, 0, 0, 1)) -- red at 0%
    curve:AddPoint(0.5, CreateColor(1, 1, 0, 1)) -- yellow at 50%
    curve:AddPoint(1, CreateColor(0, 1, 0, 1)) -- green at 100%
    classicHealthCurve = curve
    return curve
end

-- Custom Dynamic Colors: the Classic path with user-chosen stops. Live frames feed a C_CurveUtil
-- curve to UnitHealthPercent (secret-value safe); cached, rebuilt only when one of the three
-- colors changes. do-block keeps the cache state off the main-chunk local budget.
do
    local DEF100 = { r = 0, g = 1, b = 0 }
    local DEF50 = { r = 0xEC / 255, g = 0xEC / 255, b = 0x32 / 255 }
    local DEF0 = { r = 0xE3 / 255, g = 0x30 / 255, b = 0x30 / 255 }
    local dynCurve
    local r0, g0, b0, r50, g50, b50, r100, g100, b100
    function mod.GetCustomDynamicCurve(cfg)
        cfg = cfg or saved.profile
        local c0 = cfg.dynamicColor0 or DEF0
        local c50 = cfg.dynamicColor50 or DEF50
        local c100 = cfg.dynamicColor100 or DEF100
        if
            not (
                dynCurve
                and r0 == c0.r
                and g0 == c0.g
                and b0 == c0.b
                and r50 == c50.r
                and g50 == c50.g
                and b50 == c50.b
                and r100 == c100.r
                and g100 == c100.g
                and b100 == c100.b
            )
        then
            dynCurve = C_CurveUtil.CreateColorCurve()
            dynCurve:SetType(Enum.LuaCurveType.Linear)
            dynCurve:AddPoint(0, CreateColor(c0.r, c0.g, c0.b, 1))
            dynCurve:AddPoint(0.5, CreateColor(c50.r, c50.g, c50.b, 1))
            dynCurve:AddPoint(1, CreateColor(c100.r, c100.g, c100.b, 1))
            r0, g0, b0 = c0.r, c0.g, c0.b
            r50, g50, b50 = c50.r, c50.g, c50.b
            r100, g100, b100 = c100.r, c100.g, c100.b
        end
        return dynCurve
    end

    -- Clean-number interpolation matching the curve, for previews where the
    -- percent is a known fake (0-1): linear 0/50 below half, 50/100 above.
    function mod.ResolveDynamicColor(cfg, pct01)
        cfg = cfg or saved.profile
        local c0 = cfg.dynamicColor0 or DEF0
        local c50 = cfg.dynamicColor50 or DEF50
        local c100 = cfg.dynamicColor100 or DEF100
        if pct01 >= 0.5 then
            local t = (pct01 - 0.5) * 2
            return c50.r + (c100.r - c50.r) * t, c50.g + (c100.g - c50.g) * t, c50.b + (c100.b - c50.b) * t
        end
        local t = pct01 * 2
        return c0.r + (c50.r - c0.r) * t, c0.g + (c50.g - c0.g) * t, c0.b + (c50.b - c0.b) * t
    end
end

-- Class Color Reactive: the Custom Dynamic gradient whose 100% stop is the
-- unit's CLASS color -- full health reads as class identity, wounds bleed
-- into the reactive palette, fully reactive by 40%. One engine curve cached
-- per class token; the fingerprint names every input (0%/50% stops + the
-- class color, so Custom Class Colors edits rebuild too). Secret-safe: the
-- curve is evaluated inside UnitHealthPercent exactly like Classic/Dynamic.
do
    local DEF50 = { r = 0xEC / 255, g = 0xEC / 255, b = 0x32 / 255 }
    local DEF0 = { r = 0xE3 / 255, g = 0x30 / 255, b = 0x30 / 255 }
    local GRAY = { r = 0.5, g = 0.5, b = 0.5 }
    local curves = {} -- classToken -> { curve, r, g, b (class color used) }
    local r0, g0, b0, r50, g50, b50
    function mod.GetClassReactiveCurve(cfg, classToken)
        local CludesUI = mod.CludesUI -- upvalue read, not a global read (see the taint note at the top of CludesUIRaidFrames.lua)
        cfg = cfg or saved.profile
        local c0 = cfg.dynamicColor0 or DEF0
        local c50 = cfg.dynamicColor50 or DEF50
        if
            not (r0 == c0.r and g0 == c0.g and b0 == c0.b and r50 == c50.r and g50 == c50.g and b50 == c50.b)
        then
            wipe(curves)
            r0, g0, b0 = c0.r, c0.g, c0.b
            r50, g50, b50 = c50.r, c50.g, c50.b
        end
        local classColor = CludesUI.GetClassColor(classToken) or GRAY
        local e = curves[classToken]
        if not (e and e.r == classColor.r and e.g == classColor.g and e.b == classColor.b) then
            local curve = C_CurveUtil.CreateColorCurve()
            curve:SetType(Enum.LuaCurveType.Linear)
            -- Front-loaded class return: full reactive at 40% health, and the
            -- 0.75 stop carries 75% class weight, so identity snaps back
            -- quickly (40->75% climbs 0->75% class, 75->100% eases the rest).
            curve:AddPoint(0, CreateColor(c0.r, c0.g, c0.b, 1))
            curve:AddPoint(0.4, CreateColor(c50.r, c50.g, c50.b, 1))
            curve:AddPoint(
                0.75,
                CreateColor(
                    c50.r + (classColor.r - c50.r) * 0.75,
                    c50.g + (classColor.g - c50.g) * 0.75,
                    c50.b + (classColor.b - c50.b) * 0.75,
                    1
                )
            )
            curve:AddPoint(1, CreateColor(classColor.r, classColor.g, classColor.b, 1))
            e = { curve = curve, r = classColor.r, g = classColor.g, b = classColor.b }
            curves[classToken] = e
        end
        return e.curve
    end

    -- Clean-number twin for previews (fake 0-1 percents), mirroring the curve
    -- above: reactive 0-stop -> mid-stop below 40% health, front-loaded class
    -- weight above (75% class by 75% health, easing in the rest to 100%).
    function mod.ResolveClassReactiveColor(cfg, classToken, pct01)
        local CludesUI = mod.CludesUI -- upvalue read, not a global read (see the taint note at the top of CludesUIRaidFrames.lua)
        cfg = cfg or saved.profile
        local cc = (classToken and CludesUI.GetClassColor(classToken)) or GRAY
        local c0 = cfg.dynamicColor0 or DEF0
        local c50 = cfg.dynamicColor50 or DEF50
        if pct01 >= 0.4 then
            local wid
            if pct01 >= 0.75 then
                wid = 0.75 + (pct01 - 0.75)
            else
                wid = (pct01 - 0.4) / 0.35 * 0.75
            end
            return c50.r + (cc.r - c50.r) * wid, c50.g + (cc.g - c50.g) * wid, c50.b + (cc.b - c50.b) * wid
        end
        local t = pct01 / 0.4
        return c0.r + (c50.r - c0.r) * t, c0.g + (c50.g - c0.g) * t, c0.b + (c50.b - c0.b) * t
    end
end

-- Textured Background (Health Bar Fill cog; off by default): the bar texture on the
-- bar backgrounds, tinted by the colour each is painted. A tinted background's own
-- SetColorTexture tints the texture, so every existing paint keeps it: paint these
-- backgrounds only through SetColorTexture. The health background follows the fill
-- edge, so there the texture is a fixed full-size layer on the health bar, shown
-- while the fill is opaque, with the flat background under it painted clear.
do
    local SetColor -- the stock SetColorTexture
    local function PaintTinted(self, red, green, blue, a)
        self:SetVertexColor(red, green, blue, a)
    end
    local function PaintLayer(self, red, green, blue, a)
        SetColor(self, red, green, blue, 0)
        self._rfTexBgLayer:SetVertexColor(red, green, blue, a)
    end
    -- The background texture path in settings s (nil = flat); the previews share it.
    function mod.RF_TexBgPath(cfg)
        if not (cfg and cfg.textureBg) then
            return nil
        end
        local key = cfg.healthBarTexture or "atrocity"
        if key == "none" then
            return nil
        end
        return mod.CludesUI.ResolveTexturePath(mod.healthBarTextures, key, nil)
    end
    -- Whether a health fill painted from s is opaque (dark: the Dark Mode Fill).
    function mod.RF_TexBgOpaque(cfg, dark)
        if dark then
            local _, _, _, a = mod.CludesUI.GetDarkModeFill()
            return a >= 1
        end
        return (cfg.healthBarOpacity or 100) >= 100
    end
    -- A background that never moves: swapped to the texture at path, tinted by its
    -- paints (vertical: turned with a vertical bar); nil puts the flat colour back at
    -- the next paint.
    function mod.RF_TexBgTint(backdrop, filePath, vertical)
        if filePath then
            SetColor = SetColor or backdrop.SetColorTexture
            if backdrop._rfTexBgPath ~= filePath then
                backdrop:SetTexture(filePath)
                backdrop._rfTexBgPath = filePath
            end
            if vertical then
                backdrop:SetTexCoord(1, 0, 0, 0, 1, 1, 0, 1)
            else
                backdrop:SetTexCoord(0, 1, 0, 1)
            end
            backdrop.SetColorTexture = PaintTinted
        elseif backdrop._rfTexBgPath then
            backdrop._rfTexBgPath = nil
            backdrop.SetColorTexture = nil
            backdrop:SetVertexColor(1, 1, 1, 1)
            backdrop:SetTexCoord(0, 1, 0, 1)
        end
    end
    -- The health background's fixed layer (built once, turned as the fill is), shown
    -- while path is set; the next paint of bg tints it.
    function mod.RF_TexBgLayer(health, backdrop, filePath)
        if filePath then
            SetColor = SetColor or backdrop.SetColorTexture
            local layer = backdrop._rfTexBgLayer
            if not layer then
                layer = health:CreateTexture(nil, "BACKGROUND", nil, 2)
                layer:SetAllPoints(health)
                backdrop._rfTexBgLayer = layer
            end
            if layer._rfTexBgPath ~= filePath then
                layer:SetTexture(filePath)
                layer._rfTexBgPath = filePath
            end
            if health:GetRotatesTexture() then
                layer:SetTexCoord(1, 0, 0, 0, 1, 1, 0, 1)
            else
                layer:SetTexCoord(0, 1, 0, 1)
            end
            layer:Show()
            backdrop.SetColorTexture = PaintLayer
        elseif backdrop.SetColorTexture == PaintLayer then
            backdrop.SetColorTexture = nil
            backdrop._rfTexBgLayer:Hide()
        end
    end
    -- Buttons with a health layer, re-checked by every colour push before
    -- ERF:UpdateAllFrames repaints (a Dark Mode Fill edit can cross 100 with no
    -- reload). Nil until the option is first on.
    local watched
    function mod.RF_TexBgRecheck()
        if not watched then
            return
        end
        for btnFrame, health in pairs(watched) do
            local skinData = GetFFD(btnFrame)
            local s = skinData._isParty and mod._scaledPartyProxy
                or (skinData._isExtra and mod._scaledExtraProxy)
                or mod._scaledProfile
            local filePath = mod.RF_TexBgPath(s)
            filePath = filePath
                    and not skinData.kit
                    and mod.RF_TexBgOpaque(s, s.healthColorMode == "dark")
                    and filePath
                or nil
            if (filePath ~= nil) ~= (skinData.bg.SetColorTexture == PaintLayer) then
                mod.RF_TexBgLayer(health, skinData.bg, filePath)
                skinData._bgSt, skinData._bgA = nil, nil
                local u = btnFrame:GetAttribute("unit")
                if u and UnitExists(u) then
                    mod._ApplyHealthBg(skinData, health, s, u)
                end
            end
        end
        if mod._PT_TexBgRecheck then
            mod._PT_TexBgRecheck()
        end
    end
    function mod.RF_TexBgWatch()
        if not watched then
            watched = setmetatable({}, { __mode = "k" })
        end
        return watched
    end
    -- The raid, party and Extra Frames buttons (ReanchorAbsorbToFill: built, and
    -- every settings reload before both backgrounds repaint). s: the button's view.
    function mod.RF_TexBgApply(btnFrame, skinData, health, cfg)
        local filePath = mod.RF_TexBgPath(cfg)
        if not (filePath or skinData._rfTexBg) then
            return
        end
        skinData._rfTexBg = filePath and true or nil
        local hp = filePath and not skinData.kit and mod.RF_TexBgOpaque(cfg, cfg.healthColorMode == "dark") and filePath
            or nil
        if skinData.bg then
            mod.RF_TexBgLayer(health, skinData.bg, hp)
        end
        if skinData.powerBg then
            mod.RF_TexBgTint(skinData.powerBg, filePath)
        end
        if hp then
            mod.RF_TexBgWatch()[btnFrame] = health
        elseif watched then
            watched[btnFrame] = nil
        end
    end
end

-- Dark mode colors come from the global per-profile palette via GetDarkModeFill()/GetDarkModeBg(),
-- fetched live at each use so settings changes show on the next refresh. Opacity honored here
-- (RF + UF); only Resource Bars keep their own alpha.

-- Paints the health-bar background (and dims the fill) for life/connection state. Dead/offline:
-- bg covers the FULL bar (tint reads even at full last-known health), fill dims. Alive: bg covers
-- only the missing-health portion so it never bleeds behind the fill during the OOR fade.
-- Centralized so the full update and the lightweight UNIT_HEALTH update (which owns
-- death/resurrect transitions) stay in lockstep -- else a resurrect arriving only via UNIT_HEALTH
-- strands the tint. Colors overridable via the Status Colors swatch in Extras; inline fallbacks
-- allocate only when the DB key is missing.
function mod._ApplyHealthBg(skinData, health, cfg, unitToken, connected, deadOrGhost)
    local CludesUI = mod.CludesUI -- upvalue read, not a global read (see the taint note at the top of CludesUIRaidFrames.lua)
    local backdrop = skinData.bg
    if connected == nil then
        connected = UnitIsConnected(unitToken)
    end
    if deadOrGhost == nil then
        deadOrGhost = UnitIsDeadOrGhost(unitToken)
    end
    -- Party Frames kit: the portrait greys out while offline, as stock does
    -- (every connection edge passes through here).
    local kp = skinData.kitPortrait
    if kp then
        local off = not connected
        if skinData._kitDesat ~= off then
            skinData._kitDesat = off
            kp:SetDesaturated(off)
        end
    end
    -- Party portrait (CUI_RaidFrames_Portrait.lua): the same grey.
    local pt = skinData.pt
    if pt and pt._on and pt._desat ~= not connected then
        mod.RF_PtOffline(skinData, unitToken, connected)
    end
    -- Dead/offline: bg covers the FULL bar, fill dims. State+color stamped so
    -- a repeated tick in the same state re-applies nothing; entering either
    -- state clears the alive-path anchor/color stamps AND the fill-color
    -- stamp in _UpdateButtonHealth (the tint here overwrote its work).
    if not connected or deadOrGhost then
        local c = not connected
                and (cfg.statusColorOffline or { r = 0x66 / 255, g = 0x66 / 255, b = 0x66 / 255 })
            or (cfg.statusColorDead or { r = 0x24 / 255, g = 0x17 / 255, b = 0x17 / 255 })
        local st = (not connected) and 3 or 2
        -- Under Inverted Fill a corpse paints a full missing-health bar (UpdateButton):
        -- its own state, so that fill is hidden and the status colour shows undimmed.
        local hideFill = deadOrGhost and health and health._cuiInv
        if hideFill then
            st = st + 2
        end
        if skinData._bgSt ~= st or skinData._bgR ~= c.r or skinData._bgG ~= c.g or skinData._bgB ~= c.b then
            skinData._bgSt, skinData._bgR, skinData._bgG, skinData._bgB = st, c.r, c.g, c.b
            skinData._bgTex, skinData._bgA = nil, nil
            skinData._hcR = nil
            if backdrop then
                backdrop:ClearAllPoints()
                backdrop:SetAllPoints(health)
                backdrop:SetColorTexture(c.r, c.g, c.b, 1)
            end
            if health then
                if hideFill then
                    health:SetStatusBarColor(0.3, 0.3, 0.3, 0)
                elseif not connected then
                    health:SetStatusBarColor(0.3, 0.3, 0.3, 0.3)
                else
                    health:SetStatusBarColor(0.3, 0.3, 0.3, 0.5)
                end
            end
        end
        return
    end
    if not backdrop then
        return
    end
    -- Alive: the bg covers exactly the half of the bar the fill texture does NOT
    -- paint, so it hangs off the fill's leading edge -- the fill's right edge
    -- normally, its top edge on a vertical bar, and the opposite edge under
    -- Inverted Fill (where the fill paints missing health and the bg becomes the
    -- current-health surface). The anchor set changes only when the fill texture
    -- object, the axis, or the inversion does; all three change only in the
    -- restyle passes (ReloadFrames / ReloadPartyFrames), which clear d._bgSt right
    -- after, so the steady-state tick skips the reads and the anchor pass entirely.
    if skinData._bgSt ~= 1 then
        -- Axis and inversion both read off the bar, never the settings, so the
        -- bg follows the direction the fill actually paints.
        local vert = health.GetOrientation and health:GetOrientation() == "VERTICAL"
        local invert = health:GetReverseFill()
        local texture = health:GetStatusBarTexture()
        skinData._bgSt, skinData._bgTex, skinData._bgVert = 1, texture, vert
        skinData._bgA = nil
        backdrop:ClearAllPoints()
        if vert then
            if invert then
                backdrop:SetPoint("TOPLEFT", texture, "BOTTOMLEFT", 0, 0)
                backdrop:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, 0)
            else
                backdrop:SetPoint("TOPLEFT", health, "TOPLEFT", 0, 0)
                backdrop:SetPoint("BOTTOMRIGHT", texture, "TOPRIGHT", 0, 0)
            end
        else
            if invert then
                backdrop:SetPoint("TOPLEFT", health, "TOPLEFT", 0, 0)
                backdrop:SetPoint("BOTTOMRIGHT", texture, "BOTTOMLEFT", 0, 0)
            else
                backdrop:SetPoint("TOPLEFT", texture, "TOPRIGHT", 0, 0)
                backdrop:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, 0)
            end
        end
    end
    local br, bgr, bb, ba
    if cfg.healthColorMode == "dark" then
        br, bgr, bb, ba = CludesUI.GetDarkModeBg()
    else
        -- Class-colored when bgClassColored, else custom (GetBgColor handles the secret-value
        -- guard + alpha = bgDarkness). MUST match the layout-pass and preview paths or this
        -- refresh clobbers the class-colored bg.
        br, bgr, bb, ba = mod.GetBgColor(unitToken, cfg)
    end
    if skinData._bgR ~= br or skinData._bgG ~= bgr or skinData._bgB ~= bb or skinData._bgA ~= ba then
        skinData._bgR, skinData._bgG, skinData._bgB, skinData._bgA = br, bgr, bb, ba
        backdrop:SetColorTexture(br, bgr, bb, ba)
    end
end

local function GetHealthColor(unitToken, cfg)
    local CludesUI = mod.CludesUI -- upvalue read, not a global read (see the taint note at the top of CludesUIRaidFrames.lua)
    cfg = cfg or saved.profile
    local mode = cfg.healthColorMode or "class"

    if mode == "dark" then
        local dfr, dfg, dfb = CludesUI.GetDarkModeFill()
        return dfr, dfg, dfb
    elseif mode == "classic" then
        -- Native WoW health gradient via Blizzard's curve system (secret-value safe)
        local color = UnitHealthPercent(unitToken, true, GetClassicHealthCurve())
        if color and color.GetRGB then
            return color:GetRGB()
        end
        return 0, 1, 0
    elseif mode == "customDynamic" then
        -- User-customizable gradient via the same secret-safe curve path as Classic
        local color = UnitHealthPercent(unitToken, true, mod.GetCustomDynamicCurve(cfg))
        if color and color.GetRGB then
            return color:GetRGB()
        end
        return 0, 1, 0
    elseif mode == "classReactive" then
        -- Class color at full health bleeding into the reactive palette as the
        -- unit takes damage (fully reactive by 40%); engine-evaluated per-class
        -- curve, so secret health never touches Lua.
        local _, classToken = UnitClass(unitToken)
        if classToken and not issecretvalue(classToken) then
            local color = UnitHealthPercent(unitToken, true, mod.GetClassReactiveCurve(cfg, classToken))
            if color and color.GetRGB then
                return color:GetRGB()
            end
        end
        return 0.5, 0.5, 0.5
    elseif mode == "custom" then
        local color = cfg.customFillColor
        return color.r, color.g, color.b
    else -- "class"
        local _, classToken = UnitClass(unitToken)
        -- Secret-safe: a secret classToken would throw on GetClassColor's table index.
        if classToken and not issecretvalue(classToken) then
            local classColor = CludesUI.GetClassColor(classToken)
            if classColor then
                return classColor.r, classColor.g, classColor.b
            end
        end
        return 0.5, 0.5, 0.5
    end
end

-- UTF-8 aware character-count cap for an in-frame display name. Shared by the
-- live frames (via ResolveDisplayName) and every preview surface. Skips secret
-- strings entirely (#, string.byte and string.sub all throw on secrets), so a
-- secret name shows verbatim and uncapped. nameMaxLength 0 = off.
-- Takes the caller's settings table `s` so a party override applies correctly.
function mod.CapName(display, cfg)
    if type(display) ~= "string" then
        return display
    end
    if issecretvalue and issecretvalue(display) then
        return display
    end
    if display == "" then
        return display
    end
    cfg = cfg or (saved and saved.profile)
    local maxLen = cfg and cfg.nameMaxLength or 15
    if not maxLen or maxLen <= 0 then
        return display
    end
    return CludesUI.Utf8Prefix(display, maxLen)
end

-- The Name Format (Text Display, nameFormat): the character name shaped by
-- CludesUI.ShortName; unset or "full" shows it whole. Nicknames are never
-- shortened. fmt (a tag's own modifier, [name:abbr]) takes the setting's place.
-- unit: whose name it is; the setting asks CludesUI.UnitNameFormat (WoW
-- Forever: First / Last Name leave a non-player's name whole, a mob a member
-- targets included). A tag's modifier shapes any name.
function mod.RF_FormatName(display, cfg, fmt, unitToken)
    local mode = fmt or (cfg and cfg.nameFormat)
    if not mode or mode == "full" then
        return display
    end
    if not fmt then
        mode = CludesUI.UnitNameFormat(mode, unitToken)
    end
    return CludesUI.ShortName(display, mode)
end

-- Fraction of the frame width the NAME text may fill before auto-truncating
-- (1.0 = full width). Every name-width SetWidth routes through this knob;
-- health text keeps its own inline budget.
mod.RF_NAME_WIDTH_FRACTION = 1.0

-- Display name for a unit. Nickname sources in order: CludesUI's own (Raid Lead nicknames,
-- CludesUI.GetNickname), then other addons' lists for players with none: Northern Sky Raid Tools (NSAPI), MethodInternal
-- (EasyNicknameAPI), TimelineReminders, the Liquid addon (LiquidAPI), RakGaming Aliases
-- (RG_UnitName), then CustomNames; falls back to the short character name. NSAPI
-- gets our addon key "CUI" (it has a dedicated per-addon setting + CUI_NICKNAME_TOGGLE callback):
-- NSAPI:GetName self-gates on its global nicknames toggle AND that checkbox and returns the short
-- name when unset, falling through to the next source. Every source gates itself entirely (no
-- CUI-side toggle); pcall keeps a misbehaving external API from breaking name rendering.
-- fmt: a tag's Name Format modifier in place of the setting (ns.RF_FormatName).
local function ResolveDisplayName(unitToken, applyCap, s, fmt)
    local name, surname = UnitName(unitToken)
    name = name or ""
    local display = CludesUI.GetNickname and CludesUI.GetNickname(name)
    if not display and NSAPI and NSAPI.GetName then
        local success, dn = pcall(NSAPI.GetName, NSAPI, name, mod.EXT_NICK.nsKey)
        if
            success
            and type(dn) == "string"
            and not (issecretvalue and issecretvalue(dn))
            and dn ~= ""
            and dn ~= name
        then
            display = dn
        end
    end
    -- MethodInternal nicknames (EasyNicknameAPI), second source.
    if not display and EasyNicknameAPI and EasyNicknameAPI.GetNicknameForUnitForSurface then
        local success, dn, handled =
            pcall(EasyNicknameAPI.GetNicknameForUnitForSurface, unitToken, "raidFrames")
        if success and handled == true then
            if type(dn) == "string" and not (issecretvalue and issecretvalue(dn)) and dn ~= "" then
                display = dn
            else
                display = mod.RF_FormatName(CludesUI.WithSurname(name, surname), s, fmt, unitToken)
            end
        end
    end
    -- TimelineReminders, gated by its own CludesUI checkbox. GetNickname falls back to the
    -- plain unit name when none is set, so HasNickname is checked first to keep the Ambiguate path.
    if not display then
        local TR = TimelineReminders
        if TR and TR.GetNickname and TR.HasNickname and TR.NicknamesEnabledForAddOn then
            local okGate, enabled = pcall(TR.NicknamesEnabledForAddOn, TR, mod.NICK_ADDON)
            if okGate and enabled then
                local okHas, has = pcall(TR.HasNickname, TR, unitToken)
                if okHas and has then
                    local success, dn = pcall(TR.GetNickname, TR, unitToken)
                    if
                        success
                        and type(dn) == "string"
                        and not (issecretvalue and issecretvalue(dn))
                        and dn ~= ""
                    then
                        display = dn
                    end
                end
            end
        end
    end
    -- The Liquid addon's nickname function (ns.EXT_NICK.liquidFn) takes the raw UnitName string and returns a nickname or
    -- nil (unset / disabled provider-side / secret or empty name) -- it gates itself. pcall-wrapped
    -- (dot call, single arg, not a method); result re-checked as a clean non-empty string.
    local liquidFn = not display and LiquidAPI and LiquidAPI[mod.EXT_NICK.liquidFn]
    if liquidFn then
        local success, dn = pcall(liquidFn, name)
        if success and type(dn) == "string" and not (issecretvalue and issecretvalue(dn)) and dn ~= "" then
            display = dn
        end
    end
    -- RakGaming Aliases (RGA), gated on ns._rgaNick (maintained by
    -- RegisterRGALIASNicknames + RGA's module callbacks: true only while RGA is present AND its
    -- module for this suite is enabled), so this hot path costs one flag read and never dereferences
    -- RGA's settings shape. dn ~= name keeps the Ambiguate path for unaliased units.
    if not display and mod._rgaNick then
        local success, dn = pcall(RG_UnitName, unitToken)
        if
            success
            and type(dn) == "string"
            and not (issecretvalue and issecretvalue(dn))
            and dn ~= ""
            and dn ~= name
        then
            display = dn
        end
    end
    -- CustomNames (LibStub library), set by RegisterCustomNames once it has loaded.
    -- UnitName returns the raw name when none is set, so dn ~= name keeps the
    -- Ambiguate path; a secret name is never compared.
    if not display and mod._customNames and not (issecretvalue and issecretvalue(name)) then
        local success, dn = pcall(mod._customNames.UnitName, unitToken)
        if
            success
            and type(dn) == "string"
            and not (issecretvalue and issecretvalue(dn))
            and dn ~= ""
            and dn ~= name
        then
            display = dn
        end
    end
    if not display then
        if Ambiguate then
            name = Ambiguate(name, "short")
        end
        display = mod.RF_FormatName(CludesUI.WithSurname(name, surname), s, fmt, unitToken)
    end
    -- Cap only the in-frame name (applyCap), not the top name bar banner.
    if applyCap then
        display = mod.CapName(display, s)
    end
    return display
end

-- Background color: class color when bgClassColored, else the custom bg color.
-- Returns r, g, b, a (alpha = bgDarkness). Mirrors the health-fill class option.
function mod.GetBgColor(unitToken, cfg)
    cfg = cfg or saved.profile
    local a = (cfg.bgDarkness or 50) / 100
    if cfg.bgClassColored and unitToken and UnitExists(unitToken) then
        local _, classToken = UnitClass(unitToken)
        -- classToken can be secret (out-of-range/uninspectable units) and indexing GetClassColor's
        -- tables with one throws "table index is secret"; fall back to custom bg when secret/nil.
        if classToken and not issecretvalue(classToken) then
            local classColor = CludesUI.GetClassColor(classToken)
            if classColor then
                return classColor.r, classColor.g, classColor.b, a
            end
        end
    end
    -- Partial/imported profiles can lack the key (field report 2026-08-16).
    local color = cfg.customBgColor or defaultSet.customBgColor
    return color.r, color.g, color.b, a
end

-- Class/custom color resolution for the Top Name Bar text (no accent mode).
local function GetTopNameBarColor(unitToken, cfg)
    cfg = cfg or saved.profile
    if (cfg.topNameBarTextColorMode or "class") == "custom" then
        local color = cfg.topNameBarTextColor or { r = 1, g = 1, b = 1 }
        return color.r, color.g, color.b
    end
    local _, classToken = UnitClass(unitToken)
    if classToken and not issecretvalue(classToken) then
        local classColor = CludesUI.GetClassColor(classToken)
        if classColor then
            return classColor.r, classColor.g, classColor.b
        end
    end
    return 1, 1, 1
end

-- Top Name Bar text placement. With Attach Role Icons the name is bounded clear of a shown
-- icon's side (tnb._cuiRoleIcon, "..." past it); a centred name keeps equal room both sides.
function mod.RF_PlaceTopNameText(tnbText, tnb, cfg)
    local align = cfg.topNameBarTextAlign or "center"
    local ox = cfg.topNameBarTextOffsetX or 0
    local oy = cfg.topNameBarTextOffsetY or 0
    tnbText:ClearAllPoints()
    local padL, padR
    if cfg.roleIconOnNameBar and tnb._cuiRoleIcon ~= false then
        local place = cfg.roleNameBarPosition or "left"
        local room = (cfg.roleIconSize or 14) + 4
        local rx = cfg.roleNameBarOffsetX or 0
        if place:find("left") then
            padL = room + rx
        elseif place:find("right") then
            padR = room - rx
        end
    end
    if padL or padR then
        padL, padR = math.max(4, padL or 4), math.max(4, padR or 4)
        if align ~= "left" and align ~= "right" then
            padL = math.max(padL, padR)
            padR = padL
        end
        tnbText:SetPoint("LEFT", tnb, "LEFT", padL + ox, oy)
        tnbText:SetPoint("RIGHT", tnb, "RIGHT", -padR + ox, oy)
        tnbText:SetJustifyH((align == "left" and "LEFT") or (align == "right" and "RIGHT") or "CENTER")
    elseif align == "left" then
        tnbText:SetPoint("LEFT", tnb, "LEFT", 4 + ox, oy)
        tnbText:SetJustifyH("LEFT")
    elseif align == "right" then
        tnbText:SetPoint("RIGHT", tnb, "RIGHT", -4 + ox, oy)
        tnbText:SetJustifyH("RIGHT")
    else
        tnbText:SetPoint("CENTER", tnb, "CENTER", ox, oy)
        tnbText:SetJustifyH("CENTER")
    end
    tnbText:SetJustifyV("MIDDLE")
end

-- Reserve the Top Name Bar's height from the TOP of a frame and style it. Shared by real buttons
-- and every preview so they never drift. Layout + appearance only; the caller sets name text +
-- color. Returns the reserved height (0 when disabled; health re-anchors flush to the top).
-- Show on Bottom (topNameBarBottom): the bar takes the frame's BOTTOM edge instead. Health starts
-- flush at the top (same height), and the power bar and the uniform anchor region (health +
-- power) end on the bar. Those two, and the bar's own edge, are re-anchored only while the option
-- is or just was on, so the top layout never touches them.
local function LayoutTopNameBar(cfg, baseH, powerH, healthBar, tnb, tnbBg, tnbText, powerBar, preview)
    local enabled = cfg.topNameBarEnabled
    local topBarH = enabled and PixelSnap(cfg.topNameBarHeight or 20) or 0
    local bottomY = (enabled and cfg.topNameBarBottom == true) and topBarH or 0
    local hostFrame
    if healthBar then
        -- A party portrait's bars' area (CUI_RaidFrames_Portrait.lua), else the frame.
        hostFrame = healthBar._cuiBarArea or healthBar:GetParent()
        local topY = (bottomY > 0) and 0 or -topBarH
        healthBar:ClearAllPoints()
        healthBar:SetPoint("TOPLEFT", hostFrame, "TOPLEFT", 0, topY)
        healthBar:SetPoint("TOPRIGHT", hostFrame, "TOPRIGHT", 0, topY)
        healthBar:SetHeight(PixelSnap(baseH - mod.RF_HealthPowerInset(cfg, powerH) - topBarH))
        if bottomY > 0 or (healthBar._cuiTnbBottomY or 0) > 0 then
            local uref = healthBar._cuiUniformRef
            -- Aura containers protect these once anchored: a combat pass leaves
            -- them for the next one (the stamp stays unchanged).
            if
                not (
                    InCombatLockdown()
                    and ((powerBar and powerBar:IsProtected()) or (uref and uref:IsProtected()))
                )
            then
                if uref then
                    uref:ClearAllPoints()
                    uref:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
                    uref:SetPoint("BOTTOMRIGHT", hostFrame, "BOTTOMRIGHT", 0, bottomY)
                end
                if powerBar then
                    powerBar:ClearAllPoints()
                    powerBar:SetPoint("BOTTOMLEFT", hostFrame, "BOTTOMLEFT", 0, bottomY)
                    powerBar:SetPoint("BOTTOMRIGHT", hostFrame, "BOTTOMRIGHT", 0, bottomY)
                end
                healthBar._cuiTnbBottomY = bottomY
            end
        end
    end
    if not tnb then
        return topBarH
    end
    if not enabled then
        if tnb._divider then
            mod.RF_ApplyTopNameDivider(tnb, cfg, preview)
        end
        tnb:Hide()
        return topBarH
    end
    if hostFrame and (bottomY > 0 or tnb._cuiTnbBottom) then
        tnb:ClearAllPoints()
        if bottomY > 0 then
            tnb:SetPoint("BOTTOMLEFT", hostFrame, "BOTTOMLEFT", 0, 0)
            tnb:SetPoint("BOTTOMRIGHT", hostFrame, "BOTTOMRIGHT", 0, 0)
        else
            tnb:SetPoint("TOPLEFT", hostFrame, "TOPLEFT", 0, 0)
            tnb:SetPoint("TOPRIGHT", hostFrame, "TOPRIGHT", 0, 0)
        end
        tnb._cuiTnbBottom = (bottomY > 0) or nil
    end
    tnb:SetHeight(topBarH)
    if tnbBg then
        local bgc = cfg.topNameBarBgColor or {}
        tnbBg:SetColorTexture(
            bgc.r or 17 / 255,
            bgc.g or 17 / 255,
            bgc.b or 17 / 255,
            (cfg.topNameBarBgOpacity or 80) / 100
        )
    end
    if tnbText then
        ApplyFont(tnbText, cfg.topNameBarTextSize or 11)
        mod.RF_PlaceTopNameText(tnbText, tnb, cfg)
        -- Force re-layout on a JustifyH change (WoW doesn't relayout otherwise)
        local current = tnbText:GetText()
        if current then
            tnbText:SetText("")
            tnbText:SetText(current)
        end
    end
    tnb:Show()
    if cfg.topNameBarDivider == true or tnb._divider then
        mod.RF_ApplyTopNameDivider(tnb, cfg, preview)
    end
    return topBarH
end

-- Live name refresh for every raid + party button. Fired by the external
-- nickname-provider callbacks so changes apply instantly without a /reload.
function mod.RefreshAllNames()
    local s = saved and saved.profile
    if not s then
        return
    end
    local function refresh(unitToken, button)
        local skinData = GetFFD(button)
        -- Party buttons read through the party proxy so a per-party cap applies.
        local bs = (skinData and skinData._isParty) and (mod._scaledPartyProxy or s) or s
        if skinData then
            mod.RF_TextNames(skinData, unitToken)
        end
        -- The Top Name Bar keeps the level in front of the name as the name does.
        local attach = mod.RF_TextNameAttach(bs)
        if skinData and skinData.topNameBarText and bs.topNameBarEnabled then
            if attach then
                mod._RFNameWithLevel(
                    skinData.topNameBarText,
                    ResolveDisplayName(unitToken, false, bs),
                    unitToken,
                    attach
                )
            else
                skinData.topNameBarText:SetText(ResolveDisplayName(unitToken, false, bs))
            end
            local tr, tg, tb = GetTopNameBarColor(unitToken, bs)
            skinData.topNameBarText:SetTextColor(tr, tg, tb)
        end
    end
    for unitToken, button in pairs(unitToButton) do
        refresh(unitToken, button)
    end
    for unitToken, button in pairs(mod._partyUnitToButton) do
        refresh(unitToken, button)
    end
end

-- A preview text's colour for its colour mode: accent, class (classToken: the sample member's
-- class; none, as for a pet, reads white), power (pToken: the sample member's power type) or
-- custom (custom: the colour). r, g, b: the colour without one.
function mod.RF_PreviewTextColor(mode, custom, classToken, red, green, blue, pToken)
    if mode == "accent" then
        local ar, ag, ab = CludesUI.ResolveActiveAccent()
        if ar then
            return ar, ag, ab
        end
    elseif mode == "class" then
        local classColor = CludesUI.GetClassColor(classToken)
        return classColor.r, classColor.g, classColor.b
    elseif mode == "power" then
        local pc = CludesUI.GetPowerColor(pToken or "MANA")
        if pc then
            return pc.r, pc.g, pc.b
        end
    elseif custom then
        return custom.r, custom.g, custom.b
    end
    return red, green, blue
end

-- Anchor a FontString to the health bar using the shared position scheme of the texts.
-- Optional width clamps long values like health text.
function mod.AnchorRFText(fontStr, health, place, ox, oy, width)
    if not fontStr or not health then
        return
    end
    fontStr:ClearAllPoints()
    if width then
        fontStr:SetWidth(width)
        fontStr:SetHeight(0)
    end
    ox = ox or 0
    oy = oy or 0
    if place == "topleft" then
        fontStr:SetPoint("TOPLEFT", health, "TOPLEFT", 2 + ox, -2 + oy)
        fontStr:SetJustifyH("LEFT")
        fontStr:SetJustifyV("TOP")
    elseif place == "top" then
        fontStr:SetPoint("TOP", health, "TOP", ox, -2 + oy)
        fontStr:SetJustifyH("CENTER")
        fontStr:SetJustifyV("TOP")
    elseif place == "topright" then
        fontStr:SetPoint("TOPRIGHT", health, "TOPRIGHT", -2 + ox, -2 + oy)
        fontStr:SetJustifyH("RIGHT")
        fontStr:SetJustifyV("TOP")
    elseif place == "left" then
        fontStr:SetPoint("LEFT", health, "LEFT", 2 + ox, oy)
        fontStr:SetJustifyH("LEFT")
        fontStr:SetJustifyV("MIDDLE")
    elseif place == "right" then
        fontStr:SetPoint("RIGHT", health, "RIGHT", -2 + ox, oy)
        fontStr:SetJustifyH("RIGHT")
        fontStr:SetJustifyV("MIDDLE")
    elseif place == "bottomleft" then
        fontStr:SetPoint("BOTTOMLEFT", health, "BOTTOMLEFT", 2 + ox, 2 + oy)
        fontStr:SetJustifyH("LEFT")
        fontStr:SetJustifyV("BOTTOM")
    elseif place == "bottom" then
        fontStr:SetPoint("BOTTOM", health, "BOTTOM", ox, 2 + oy)
        fontStr:SetJustifyH("CENTER")
        fontStr:SetJustifyV("BOTTOM")
    elseif place == "bottomright" then
        fontStr:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", -2 + ox, 2 + oy)
        fontStr:SetJustifyH("RIGHT")
        fontStr:SetJustifyV("BOTTOM")
    else -- "center"
        fontStr:SetPoint("CENTER", health, "CENTER", ox, oy)
        fontStr:SetJustifyH("CENTER")
        fontStr:SetJustifyV("MIDDLE")
    end
    -- Force re-render after a JustifyH change (mirrors the name/health text fns).
    local txt = fontStr:GetText()
    fontStr:SetText("")
    fontStr:SetText(txt or "")
end

-------------------------------------------------------------------------------
--  Custom Health / Power Text: one CludesUI.TextTags catalog for both. A
--  piece is (unit, s, pv); unit nil is a preview (pv's made-up values, else the
--  schema sample). Values only reach a format setter, never a comparison. Dead
--  or offline keeps the text: [hp] names the status, [hp:pct] reads 0 (as UF).
-------------------------------------------------------------------------------
do
    local TextTags = CludesUI.TextTags
    local sformat, sfind, ssub, unpack = string.format, string.find, string.sub, unpack
    local UnitHealthMax, UnitPowerMax = UnitHealthMax, UnitPowerMax
    local UnitPowerPercent, UnitGetTotalAbsorbs = UnitPowerPercent, UnitGetTotalAbsorbs
    local UnitInRaid, GetRaidRosterInfo, IsInRaid = UnitInRaid, GetRaidRosterInfo, IsInRaid
    local SCHEMA = TextTags.UNIT.keys
    local IsZeroValue = CludesUI.IsZeroValue

    -- OFFLINE / DEAD, nil while alive and connected (clean booleans for group units).
    local function Status(unitToken, pv)
        if unitToken then
            if not UnitIsConnected(unitToken) then
                return CludesUI.L("OFFLINE")
            end
            if UnitIsDeadOrGhost(unitToken) then
                return CludesUI.L("DEAD")
            end
        elseif pv then
            if pv.offline then
                return CludesUI.L("OFFLINE")
            end
            if pv.dead then
                return CludesUI.L("DEAD")
            end
        end
    end

    local function GetHealth(unitToken, max)
        if max then
            return UnitHealthMax(unitToken) or 0
        end
        return UnitHealth(unitToken, true) or 0
    end
    local function GetPower(unitToken, max)
        local pType = UnitPowerType(unitToken)
        if max then
            return UnitPowerMax(unitToken, pType) or 0
        end
        return UnitPower(unitToken, pType) or 0
    end

    -- [hp], [pp] and their :max / :abr keys. Current health names the status, so
    -- Health / Max names it once ("DEAD / 150 K").
    local function Amount(key)
        local kind = ssub(key, 1, 2)
        local get = kind == "hp" and GetHealth or GetPower
        local max, abr = sfind(key, ":max", 1, true) ~= nil, sfind(key, ":abr", 1, true) ~= nil
        local status = kind == "hp" and not max
        local pctKey, perKey, sample = kind .. "Pct", kind .. "Per", SCHEMA[key].sample
        local valueType = kind == "hp" and (max and "maxHealth" or "health") or nil
        return function(unitToken, s, pv)
            local st = status and Status(unitToken, pv)
            if st then
                return st
            end
            local val
            if unitToken then
                val = get(unitToken, max)
            elseif pv and pv[perKey] then
                val = max and 100 * pv[perKey] or (pv[pctKey] or 0) * pv[perKey]
            else
                return sample
            end
            if abr then
                if valueType then
                    return AbbreviateValue(val, valueType)
                end
                return AbbreviateNumbers(val)
            end
            return sformat("%d", val)
        end
    end

    local function HealthPct(unitToken, s, pv)
        if unitToken then
            if UnitIsDeadOrGhost(unitToken) then
                return "0"
            end
            return sformat("%.0f", GetSafeHealthPercent(unitToken) or 0)
        end
        if pv and pv.hpPct then
            return sformat("%.0f", pv.dead and 0 or pv.hpPct)
        end
        return SCHEMA["hp:pct"].sample
    end
    local function PowerPct(unitToken, s, pv)
        if unitToken then
            return sformat(
                "%.0f",
                UnitPowerPercent(unitToken, UnitPowerType(unitToken), true, CurveConstants.ScaleTo100) or 0
            )
        end
        if pv and pv.ppPct then
            return sformat("%.0f", pv.ppPct)
        end
        return SCHEMA["pp:pct"].sample
    end

    -- Full and abbreviated amounts blank at zero, as the Unit Frames' Absorb Short.
    local function Absorb(key, get)
        local abr, sample = sfind(key, ":abr", 1, true) ~= nil, SCHEMA[key].sample
        return function(unitToken)
            if not unitToken then
                return sample
            end
            local val = get(unitToken) or 0
            if abr then
                if IsZeroValue(val) then
                    return ""
                end
                return AbbreviateValue(val, "absorb")
            end
            return C_StringUtil.TruncateWhenZero(val)
        end
    end

    -- [name] and [target], plain or with a Name Format modifier ([name:abbr]):
    -- fmt, when given, takes the place of the text's Name Format, so the cap
    -- still comes last and nicknames stay whole. [name:last] and [target:last]
    -- show nothing for your own unit while your name is your first name alone
    -- (OwnSurnameHidden: WoW Forever, Blizzard's My Surname off).
    local function NamePiece(key, fmt)
        local sample = SCHEMA[key].sample
        return function(unitToken, s, pv)
            if unitToken and fmt == "last" and CludesUI.OwnSurnameHidden(unitToken) then
                return ""
            end
            if unitToken then
                return ResolveDisplayName(unitToken, true, s, fmt)
            end
            -- A preview member's name as its name text would show it.
            if fmt and pv and pv.rawName then
                return mod.CapName(mod.RF_FormatName(pv.rawName, s, fmt), s)
            end
            return pv and pv.name or sample
        end
    end
    -- The target's name through the same resolver, uncapped (Name Max Length is the
    -- unit's own name, and only a clean name could be capped); a secret one passes raw.
    local targetOf = setmetatable({}, {
        __index = function(t, unitToken)
            local val = unitToken .. "target"
            t[unitToken] = val
            return val
        end,
    })
    local function TargetPiece(key, fmt)
        local sample = SCHEMA[key].sample
        return function(unitToken, s)
            if not unitToken then
                return sample
            end
            local tunit = targetOf[unitToken]
            if not UnitExists(tunit) then
                return ""
            end
            if fmt == "last" and CludesUI.OwnSurnameHidden(tunit) then
                return ""
            end
            local name = UnitName(tunit)
            if issecretvalue(name) then
                return name
            end
            return ResolveDisplayName(tunit, false, s, fmt)
        end
    end
    local function Group(unitToken)
        if not unitToken then
            return SCHEMA.group.sample
        end
        if not IsInRaid() then
            return ""
        end
        local position = UnitInRaid(unitToken)
        if position and not issecretvalue(position) then
            local _, _, subgroup = GetRaidRosterInfo(position)
            return subgroup or ""
        end
        return ""
    end

    local CATALOG = TextTags.Bind(TextTags.UNIT, {
        ["hp"] = Amount("hp"),
        ["hp:abr"] = Amount("hp:abr"),
        ["hp:max"] = Amount("hp:max"),
        ["hp:max:abr"] = Amount("hp:max:abr"),
        ["hp:pct"] = HealthPct,
        ["pp"] = Amount("pp"),
        ["pp:abr"] = Amount("pp:abr"),
        ["pp:max"] = Amount("pp:max"),
        ["pp:max:abr"] = Amount("pp:max:abr"),
        ["pp:pct"] = PowerPct,
        ["absorb"] = Absorb("absorb", UnitGetTotalAbsorbs),
        ["absorb:abr"] = Absorb("absorb:abr", UnitGetTotalAbsorbs),
        ["healabsorb"] = Absorb("healabsorb", UnitGetTotalHealAbsorbs),
        ["healabsorb:abr"] = Absorb("healabsorb:abr", UnitGetTotalHealAbsorbs),
        ["name"] = NamePiece("name"),
        ["name:first"] = NamePiece("name:first", "first"),
        ["name:last"] = NamePiece("name:last", "last"),
        ["name:abbr"] = NamePiece("name:abbr", "abbr"),
        ["target"] = TargetPiece("target"),
        ["target:first"] = TargetPiece("target:first", "first"),
        ["target:last"] = TargetPiece("target:last", "last"),
        ["target:abbr"] = TargetPiece("target:abbr", "abbr"),
        ["group"] = Group,
    })
    mod.RF_TextTags = CATALOG

    -- Compiled once per parse (the engine caches parses per template): fmt, the
    -- pieces in tag order, each piece's value class (cls), their count and the value
    -- classes the template reads.
    local compiled = setmetatable({}, { __mode = "k" })
    function mod.RF_CustomCompile(template)
        local parsed = TextTags.Parse(CATALOG, template)
        if not parsed then
            return nil
        end
        local cc = compiled[parsed]
        if cc then
            return cc
        end
        local keyList, map, pieces, cls = parsed.keys, CATALOG.map, {}, {}
        for i = 1, #keyList do
            pieces[i], cls[i] = map[keyList[i]], SCHEMA[keyList[i]].reads
        end
        cc = { fmt = parsed.fmt, pieces = pieces, cls = cls, n = #keyList, reads = parsed.reads }
        compiled[parsed] = cc
        return cc
    end
    local Compile = mod.RF_CustomCompile

    -- Paints a template; returns the value classes it reads (TextTags' reads set),
    -- or false (blank) for a missing or empty one. args: a button's values for this
    -- text, kept between paints; a / b: only the pieces reading those classes are
    -- read again, the rest keep their values (a nil, a new template or no args:
    -- every piece, as on the previews).
    local scratch = {}
    local function CustomTextInto(fontStr, template, unitToken, s, pv, args, a, b)
        local cc = Compile(template)
        if not cc then
            fontStr:SetText("")
            return false
        end
        if not args then
            args, a = scratch, nil
        elseif args.cc ~= cc then
            args.cc, a = cc, nil
        end
        local pieces, cls, n = cc.pieces, cc.cls, cc.n
        for k = 1, n do
            if not a or cls[k] == a or cls[k] == b then
                args[k] = pieces[k](unitToken, s, pv)
            end
        end
        fontStr:SetFormattedText(cc.fmt, unpack(args, 1, n))
        return cc.reads
    end
    mod.RF_CustomTextInto = CustomTextInto
end

-- Health text in one of the health text modes (Custom texts paint through RF_CustomTextInto). A
-- unit's values are read only in the modes that show them; a preview (unit nil) shows made-up
-- ones, perPct per percent. Returns false for None or an unknown mode, which blank the text;
-- otherwise true.
function mod.RF_HealthTextInto(fontStr, mode, pct, unitToken, perPct)
    local val
    if mode == "percent" then
        fontStr:SetFormattedText("%.0f%%", pct)
    elseif mode == "percentNoSign" then
        fontStr:SetFormattedText("%.0f", pct)
    elseif mode == "number" then
        if unitToken then
            val = UnitHealth(unitToken, true)
        else
            val = pct * perPct
        end
        if val and AbbreviateNumbers then
            fontStr:SetText(AbbreviateValue(val, "health"))
        elseif val then
            fontStr:SetFormattedText("%s", val)
        end
    elseif mode == "numberPercent" or mode == "percentNumber" then
        if unitToken then
            val = UnitHealth(unitToken, true)
        else
            val = pct * perPct
        end
        local numStr = (val and AbbreviateNumbers) and AbbreviateValue(val, "health") or tostring(val or 0)
        if mode == "numberPercent" then
            fontStr:SetFormattedText("%s | %.0f%%", numStr, pct)
        else
            fontStr:SetFormattedText("%.0f%% | %s", pct, numStr)
        end
    elseif mode == "missing" then
        if unitToken then
            val = UnitHealthMissing(unitToken, true)
        else
            val = (100 - pct) * perPct
        end
        fontStr:SetText(C_StringUtil.TruncateWhenZero(val))
        if fontStr:GetText() then
            if val and AbbreviateNumbers then
                fontStr:SetText(AbbreviateValue(val, "health"))
            elseif val then
                fontStr:SetFormattedText("%s", val)
            end
        end
    else
        fontStr:SetText("")
        return false
    end
    return true
end

-- Format a heal-absorb amount into a FontString. mode: "amount" (full), "short" (abbreviated like
-- 240k), "none"/nil (blank). C_StringUtil.TruncateWhenZero blanks at zero; its result (and GetText
-- after) is a SECRET string for a secret absorb, so ONLY feed it to SetText or test truthiness --
-- never compare it (== "" taints). "short" gates on GetText truthiness alone (non-nil exactly when
-- non-zero) before abbreviating.
function mod.FormatHealAbsorbInto(fontStr, amt, mode)
    if not fontStr then
        return
    end
    if not mode or mode == "none" then
        fontStr:SetText("")
        return
    end
    fontStr:SetText(C_StringUtil.TruncateWhenZero(amt or 0))
    if mode == "short" and AbbreviateNumbers and fontStr:GetText() then
        fontStr:SetText(AbbreviateValue(amt or 0, "absorb"))
    end
end

-- Update one button's Heal Absorb Texts. Called from the absorb-only event path
-- (UNIT_HEAL_ABSORB_AMOUNT_CHANGED), which runs no full button update.
function mod.UpdateHealAbsorbTextFor(btnFrame, unitToken)
    mod.RF_TextHealAbsorb(GetFFD(btnFrame), unitToken)
end

-- Maps a dispel type to its saved-color key. The "" type (Bleed/physical) is
-- stored under dispelColorBleed.
local DISPEL_COLOR_KEYS = {
    Magic = "dispelColorMagic",
    Curse = "dispelColorCurse",
    Disease = "dispelColorDisease",
    Poison = "dispelColorPoison",
    [""] = "dispelColorBleed",
}

-- Resolve a dispel type's color: user value (via the proxy `s`) falling back to the DISPEL_COLORS
-- default. Returns nil for an unknown/nil type so callers keep their own fallback behavior.
local function GetDispelColor(dtype, cfg)
    cfg = cfg or saved.profile
    local key = DISPEL_COLOR_KEYS[dtype]
    if key then
        local c = cfg[key]
        if c then
            return c
        end
    end
    return DISPEL_COLORS[dtype]
end

local function GetPowerColor(unitToken)
    local _, pToken = UnitPowerType(unitToken)
    if pToken and CludesUI.GetPowerColor then
        local details = CludesUI.GetPowerColor(pToken)
        if details then
            return details.r, details.g, details.b
        end
    end
    local pType = UnitPowerType(unitToken) or 0
    local details = PowerBarColor[pType]
    if details then
        return details.r, details.g, details.b
    end
    return 0.5, 0.5, 0.5
end

-- Power type + color + bounds (+ the opt-in power-colored bg) for a button's
-- power bar: identity-class state that only moves on UNIT_DISPLAYPOWER, an
-- occupant change or a full paint -- Blizzard's CompactUnitFrame recolors
-- power on exactly those edges -- so the per-tick UNIT_POWER_UPDATE path pushes
-- the value alone. Stamps d._pwType (nil = not derived for this occupant).
-- force = full paint: settings may have changed, so the bg re-tints even when
-- the type/darken stamps still match.
mod._RFPowerTypeEdge = function(skinData, unitToken, force)
    local pType = UnitPowerType(unitToken) or 0
    local pr, pg, pb = GetPowerColor(unitToken)
    skinData._pwType = pType
    skinData.power:SetMinMaxValues(0, 100)
    skinData.power:SetStatusBarColor(pr, pg, pb, 1)
    local s = skinData._isParty and mod._scaledPartyProxy
        or (skinData._isExtra and mod._scaledExtraProxy)
        or mod._scaledProfile
    if s.powerBgPowerColored and skinData.powerBg then
        local frame = mod.CludesUI.GetPowerBgDarkenFactor()
        if force or skinData._pwBgTintType ~= pType or skinData._pwBgTintF ~= frame then
            skinData.powerBg:SetColorTexture(pr * frame, pg * frame, pb * frame, (s.powerBgDarkness or 70) / 100)
            skinData._pwBgTintType = pType
            skinData._pwBgTintF = frame
        end
    end
    -- Power Text's colour is identity-class state too (its Power mode is this type's colour).
    if skinData._pwtOn then
        mod.RF_TextPowerColor(skinData, unitToken, s, pr, pg, pb)
    end
end

-------------------------------------------------------------------------------
--  Power Text formatting. The texts, their visibility (only while the power bar
--  shows) and the event paths live in CUI_RaidFrames_TextPaint.lua.
-------------------------------------------------------------------------------

-- Power text in one of its modes (Health Text's minus Missing). pct: the bar's percent
-- (UnitPowerPercent, which can be secret in combat: it only ever reaches a format setter).
-- unit + pType: the live unit, blank while dead or offline like Health Text (both checks return
-- clean booleans for group units); its amount is read only in the modes that show it and goes
-- straight through AbbreviateNumbers into the setter, never compared. A preview (unit nil)
-- shows made-up amounts, perPct per percent. Returns false when it blanks the text (dead,
-- offline, None or an unknown mode), otherwise true.
function mod.RF_PowerTextInto(fontStr, mode, pct, unitToken, pType, perPct)
    if unitToken and (UnitIsDeadOrGhost(unitToken) or not UnitIsConnected(unitToken)) then
        fontStr:SetText("")
        return false
    end
    if mode == "percent" then
        fontStr:SetFormattedText("%.0f%%", pct)
    elseif mode == "percentNoSign" then
        fontStr:SetFormattedText("%.0f", pct)
    elseif mode == "number" or mode == "numberPercent" or mode == "percentNumber" then
        local num
        if unitToken then
            num = AbbreviateNumbers(UnitPower(unitToken, pType))
        else
            num = AbbreviateNumbers(pct * perPct)
        end
        if mode == "number" then
            fontStr:SetText(num)
        elseif mode == "numberPercent" then
            fontStr:SetFormattedText("%s | %.0f%%", num, pct)
        else
            fontStr:SetFormattedText("%.0f%% | %s", pct, num)
        end
    else
        fontStr:SetText("")
        return false
    end
    return true
end

-------------------------------------------------------------------------------
--  Level formatting: the unit's level in front of the name ("60 Name", the WoW
--  Forever default, or "60 | Name") or on its own spot. UNIT_LEVEL (a level-only
--  repaint, ns._RFRepaintLevel) is registered only while some view shows the level.
--  The level is the effective one (scaled content), like the suite's other level
--  texts.
-------------------------------------------------------------------------------

-- The attached positions and their formats: known level, unknown ("??") level.
mod.RF_LEVEL_ATTACH = {
    name = { "%d %s", "?? %s" },
    nameDiv = { "%d | %s", "?? | %s" },
}

-- The level as text: a secret level goes straight to the setter (never compared),
-- "??" for a unit too far above to read, blank while it is not known yet.
mod._RFLevelInto = function(fontStr, unitToken)
    local lvl = UnitEffectiveLevel(unitToken)
    if issecretvalue(lvl) then
        fontStr:SetFormattedText("%d", lvl)
    elseif not lvl or lvl == 0 then
        fontStr:SetText("")
    elseif lvl < 0 then
        fontStr:SetText("??")
    else
        fontStr:SetFormattedText("%d", lvl)
    end
end

-- The level the previews show on every sample member: the player's own.
mod._RFPreviewLevel = function()
    local lvl = UnitEffectiveLevel("player")
    if issecretvalue(lvl) or not lvl or lvl <= 0 then
        return 60
    end
    return lvl
end

-- Attach to Name: the name text in an attached position's format (fmt, from
-- RF_LEVEL_ATTACH). The name (possibly secret) and the level only ever reach the
-- format setter; an unknown level, or a name not known yet (empty), leaves the
-- name alone.
mod._RFNameWithLevel = function(fontStr, name, unitToken, fmt)
    local lvl = UnitEffectiveLevel(unitToken)
    local nameKnown = issecretvalue(name) or (name ~= nil and name ~= "")
    if not nameKnown then
        fontStr:SetText(name)
    elseif issecretvalue(lvl) then
        fontStr:SetFormattedText(fmt[1], lvl, name)
    elseif not lvl or lvl == 0 then
        fontStr:SetText(name)
    elseif lvl < 0 then
        fontStr:SetFormattedText(fmt[2], name)
    else
        fontStr:SetFormattedText(fmt[1], lvl, name)
    end
end

Inner.GetClassicHealthCurve, Inner.GetDispelColor = GetClassicHealthCurve, GetDispelColor
Inner.GetHealthColor, Inner.GetPowerColor = GetHealthColor, GetPowerColor
Inner.GetSafeHealthPercent, Inner.GetTopNameBarColor = GetSafeHealthPercent, GetTopNameBarColor
Inner.LayoutTopNameBar, Inner.ResolveDisplayName = LayoutTopNameBar, ResolveDisplayName
Inner.broken = false
